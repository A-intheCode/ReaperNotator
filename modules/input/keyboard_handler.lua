-- ==============================================================================
-- REAPER Native Notator - Module: KeyboardHandler
-- Keyboard control: Freely configurable shortcuts via ShortcutManager
-- ==============================================================================

local KeyboardHandler = {}
local ShortcutManager = require("services.shortcut_manager")
local AudioPreview = require("services.audio_preview")
local Engraver = require("rendering.engraver")
local has_kss, KeySignatureService = pcall(require, "services.key_signature_service")
local has_uss, UndoStateService = pcall(require, "services.undo_state_service")

function KeyboardHandler.handle(ctx, state, midi_service, clipboard_service, dynamics_engine, active_tracks_data)
    -- When a shortcut is being captured in settings, or a text/chord/rehearsal/annotation layer item is being edited, do not execute ANY shortcuts!
    local ann_drawer = package.loaded["ui.annotation_drawer"]
    if state.capturing_action
        or state.editing_text_item
        or state.editing_chord_item
        or state.editing_rehearsal_mark
        or state.editing_annotation_layer
        or (ann_drawer and ann_drawer.renaming_layer_id ~= nil)
    then
        return
    end

    -- Modifier key detection (Ctrl, Shift, Alt)
    local is_ctrl = false
    if reaper.APIExists("ImGui_Mod_Ctrl") and reaper.APIExists("ImGui_GetKeyMods") then
        is_ctrl = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Ctrl()) ~= 0
    end
    if not is_ctrl and reaper.APIExists("ImGui_Key_LeftCtrl") and reaper.APIExists("ImGui_Key_RightCtrl") then
        is_ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl())
    end

    local is_shift = false
    if reaper.APIExists("ImGui_Mod_Shift") and reaper.APIExists("ImGui_GetKeyMods") then
        is_shift = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Shift()) ~= 0
    end
    if not is_shift and reaper.APIExists("ImGui_Key_LeftShift") and reaper.APIExists("ImGui_Key_RightShift") then
        is_shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
    end

    local is_alt = false
    if reaper.APIExists("ImGui_Mod_Alt") and reaper.APIExists("ImGui_GetKeyMods") then
        is_alt = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Alt()) ~= 0
    end
    if not is_alt and reaper.APIExists("ImGui_Key_LeftAlt") and reaper.APIExists("ImGui_Key_RightAlt") then
        is_alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftAlt()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightAlt())
    end

    local is_step = (state.input_mode_type == "step" or state.input_mode == true)

    -- Shortcut query with automatic deactivation of note letter hotkeys in step input mode
    local function is_action_pressed(action_id)
        if is_step then
            local sc = ShortcutManager.shortcuts[action_id]
            if sc and not sc.ctrl and not sc.alt then
                local k = sc.key and string.upper(sc.key)
                if k == "C" or k == "D" or k == "E" or k == "F" or k == "G" or k == "A" or k == "B" or k == "H" then
                    -- In step input mode, hotkeys on note letter keys are deactivated!
                    return false
                end
            end
        end
        return ShortcutManager.is_action_pressed(ctx, action_id, is_ctrl, is_shift, is_alt)
    end

    local play_state = reaper.GetPlayState()
    local is_playing = (play_state & 1) == 1 or (play_state & 4) == 4
    if is_playing then
        -- Playback Fast-Path: Allow transport commands (Play/Pause, Escape) and Live Custom Marker insertion!
        if is_action_pressed("add_custom_marker") then
            local RehearsalMarkService = package.loaded["services.rehearsal_mark_service"] or require("services.rehearsal_mark_service")
            RehearsalMarkService.add_custom_marker_at_current_pos(state)
            return
        elseif is_action_pressed("play_pause") or (reaper.APIExists("ImGui_Key_Space") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Space(), false)) then
            reaper.OnStopButton()
            state.status_msg = "Playback stopped"
            state.status_time = reaper.time_precise()
        elseif reaper.APIExists("ImGui_Key_Escape") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape(), false) then
            state:clear_selection()
        end
        return
    end

    -- Add Custom Marker at Edit Cursor when stopped (Ctrl+M default)
    if is_action_pressed("add_custom_marker") then
        local RehearsalMarkService = package.loaded["services.rehearsal_mark_service"] or require("services.rehearsal_mark_service")
        RehearsalMarkService.add_custom_marker_at_current_pos(state)
        return
    end

    -- Refresh Engine Cache / Reload Modules (F5 or user-defined shortcut)
    if is_action_pressed("refresh_cache") or (reaper.APIExists("ImGui_Key_F5") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F5(), false)) then
        for k in pairs(package.loaded) do
            if k:match("^constants") or k:match("^state") or k:match("^classes%.") or k:match("^services%.") or k:match("^rendering%.") or k:match("^ui%.") or k:match("^input%.") then
                package.loaded[k] = nil
            end
        end
        state.status_msg = "🔄 Notator Engine & Modules reloaded!"
        state.status_time = reaper.time_precise()
    end

    -- Input mode switching helper
    local function change_mode(m)
        if state.set_input_mode then
            state:set_input_mode(m)
        else
            state.input_mode_type = m
            state.input_mode = (m == "step")
            state.draw_preview = nil
            state.status_msg = (m == "draw") and "Write Notes active" or ((m == "step") and "Step Input active" or "Selection mode active")
        end
    end

    -- Undo/Redo
    if is_action_pressed("undo") then
        local can_undo = reaper.Undo_CanUndo2 and reaper.Undo_CanUndo2(0)
        local uss_can_undo = has_uss and UndoStateService and UndoStateService.can_undo and UndoStateService.can_undo()
        if can_undo ~= nil and can_undo == "" and not uss_can_undo then
            state.status_msg = "Nothing to undo"
            return
        end
        local can_redo_now = reaper.Undo_CanRedo2 and reaper.Undo_CanRedo2(0) or ""
        local uss_can_redo_now = has_uss and UndoStateService and UndoStateService.can_redo and UndoStateService.can_redo()
        if can_redo_now == "" and not uss_can_redo_now then
            state._consecutive_undo_steps = 0
        end
        local max_steps = state.max_undo_steps or 50
        if max_steps > 0 and (state._consecutive_undo_steps or 0) >= max_steps then
            state.status_msg = string.format("Maximum undo limit (%d steps) reached", max_steps)
            return
        end
        state._consecutive_undo_steps = (state._consecutive_undo_steps or 0) + 1
        state._in_undo_redo_action = true
        reaper.Main_OnCommand(40029, 0) -- Undo
        if has_uss and UndoStateService and UndoStateService.on_undo then
            UndoStateService.on_undo(can_undo)
        end
        if state.reload_score_from_project then
            state:reload_score_from_project()
        end
        state._last_can_undo_str = (reaper.Undo_CanUndo2 and reaper.Undo_CanUndo2(0)) or ""
        state._last_can_redo_str = (reaper.Undo_CanRedo2 and reaper.Undo_CanRedo2(0)) or ""
        state._last_proj_change_cleanup = reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0) or state._last_proj_change_cleanup
        state._last_total_tracks_cleanup = reaper.CountTracks and reaper.CountTracks(0) or state._last_total_tracks_cleanup
        state._last_arm_sel_sig = midi_service and midi_service._last_sel_sig or state._last_arm_sel_sig
        state._in_undo_redo_action = false
        if can_undo and can_undo ~= "" then
            state.status_msg = "Undo: " .. tostring(can_undo)
        end
        return
    end
    local is_ctrl_y = is_ctrl and not is_shift and not is_alt and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Y())
    if is_action_pressed("redo") or is_ctrl_y then
        local can_redo = reaper.Undo_CanRedo2 and reaper.Undo_CanRedo2(0)
        local uss_can_redo = has_uss and UndoStateService and UndoStateService.can_redo and UndoStateService.can_redo()
        if can_redo ~= nil and can_redo == "" and not uss_can_redo then
            state.status_msg = "Nothing to redo"
            return
        end
        if state._consecutive_undo_steps and state._consecutive_undo_steps > 0 then
            state._consecutive_undo_steps = state._consecutive_undo_steps - 1
        end
        state._in_undo_redo_action = true
        reaper.Main_OnCommand(40030, 0) -- Redo
        if has_uss and UndoStateService and UndoStateService.on_redo then
            UndoStateService.on_redo()
        end
        if state.reload_score_from_project then
            state:reload_score_from_project()
        end
        state._last_can_undo_str = (reaper.Undo_CanUndo2 and reaper.Undo_CanUndo2(0)) or ""
        state._last_can_redo_str = (reaper.Undo_CanRedo2 and reaper.Undo_CanRedo2(0)) or ""
        state._last_proj_change_cleanup = reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0) or state._last_proj_change_cleanup
        state._last_total_tracks_cleanup = reaper.CountTracks and reaper.CountTracks(0) or state._last_total_tracks_cleanup
        state._last_arm_sel_sig = midi_service and midi_service._last_sel_sig or state._last_arm_sel_sig
        state._in_undo_redo_action = false
        if can_redo and can_redo ~= "" then
            state.status_msg = "Redo: " .. tostring(can_redo)
        end
        return
    end

    -- Escape / Selection Mode (ends Step Input or Write Mode)
    if is_action_pressed("select_mode") or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        if state.input_mode_type and state.input_mode_type ~= "select" then
            change_mode("select")
            return
        elseif (state:count_selected_notes() > 0) or state.selected_dynamic or state.selected_hairpin or state.selected_dynamic_text or state.selected_pedal or state.selected_portamento or state.selected_glissando or state.selected_tempo_marker or state.selected_octave_line or state.selected_text_item or state.selected_chord_item then
            state:clear_selection()
            state.selected_dynamic_text = nil
            state.selected_pedal = nil
            state.selected_portamento = nil
            state.selected_glissando = nil
            state.selected_text_item = nil
            state.editing_text_item = nil
            state.selected_chord_item = nil
            state.editing_chord_item = nil
            midi_service.sync_selection_to_reaper(state, active_tracks_data)
            return
        end
    end

    -- 1. Step Input note entry (C, D, E, F, G, A, B, H)
    -- Highest priority in Step Input mode: note letters without Ctrl/Alt write notes directly!
    if is_step and not is_ctrl and not is_alt then
        local note_keys = {
            { key = reaper.ImGui_Key_C(), semi = 0,  step = 0, name = "C" },
            { key = reaper.ImGui_Key_D(), semi = 2,  step = 1, name = "D" },
            { key = reaper.ImGui_Key_E(), semi = 4,  step = 2, name = "E" },
            { key = reaper.ImGui_Key_F(), semi = 5,  step = 3, name = "F" },
            { key = reaper.ImGui_Key_G(), semi = 7,  step = 4, name = "G" },
            { key = reaper.ImGui_Key_A(), semi = 9,  step = 5, name = "A" },
            { key = reaper.ImGui_Key_B(), semi = 11, step = 6, name = "B" },
        }
        if reaper.APIExists("ImGui_Key_H") then
            table.insert(note_keys, { key = reaper.ImGui_Key_H(), semi = 11, step = 6, name = "H" })
        end

        for _, nk in ipairs(note_keys) do
            if reaper.ImGui_IsKeyPressed(ctx, nk.key, false) then
                local cursor_pos = reaper.GetCursorPosition()
                local qn = reaper.TimeMap2_timeToQN(0, cursor_pos)

                local target_trk = state.focused_track
                if active_tracks_data then
                    for _, tdata in ipairs(active_tracks_data) do
                        if tdata.track == state.focused_track then
                            target_trk = tdata
                            break
                        end
                    end
                    if not target_trk then target_trk = active_tracks_data[1] end
                end

                local eff_key_idx = state.key_signature or 0
                if has_kss and KeySignatureService and KeySignatureService.resolve_effective_key then
                    local res = KeySignatureService.resolve_effective_key(state, target_trk, nil, qn)
                    eff_key_idx = (type(res) == "table" and (res.idx or res.key_idx)) or (type(res) == "number" and res) or 0
                end

                local oct = state.current_octave or 4
                local acc = state.accidental or 0
                local eff_acc = 0
                if acc == 1 or acc == -1 then
                    eff_acc = acc
                elseif acc == 2 then
                    eff_acc = 0
                else
                    eff_acc = Engraver.get_key_sig_step_accidental(nk.step, eff_key_idx)
                end

                local pitch = (oct + 1) * 12 + nk.semi + eff_acc
                pitch = math.max(0, math.min(127, pitch))

                local dur = state.active_dur or 1.0
                if state.is_dotted then dur = dur * 1.5 end
                if state.get_tuplet_factor then
                    dur = dur * state:get_tuplet_factor()
                elseif state.is_triplet then
                    dur = dur * (2.0 / 3.0)
                end

                local n_obj = midi_service.insert_note_at_qn(state, qn, pitch, dur)
                if n_obj then
                    AudioPreview.play_note(state, n_obj.pitch or pitch, n_obj.vel or 96, n_obj.chan or 0, n_obj.track or state.focused_track, n_obj.start_qn or qn, n_obj)
                end

                -- Advance cursor by note duration
                local new_qn = qn + dur
                local new_time = reaper.TimeMap2_QNToTime(0, new_qn)
                reaper.SetEditCurPos(new_time, true, false)

                local acc_str = ""
                if acc == 2 then
                    acc_str = "♮"
                elseif eff_acc == 1 then
                    acc_str = "♯"
                elseif eff_acc == -1 then
                    acc_str = "♭"
                end
                state.status_msg = string.format("Step Input: Inserted note %s%s%d (%.2f QN)", nk.name, acc_str, oct, dur)
                return
            end
        end
    end

    -- Write Notes [D] (only active outside Step Input)
    if is_action_pressed("toggle_write_mode") then
        change_mode(state.input_mode_type == "draw" and "select" or "draw")
        return
    end

    if is_action_pressed("make_legato") then
        midi_service.make_legato(state)
    end

    if is_action_pressed("quantize") then
        state.show_quantize_modal = not state.show_quantize_modal
        if state.show_quantize_modal then
            state.focus_quantize_modal = true
        end
        return
    end

    -- Fenster maximieren / wiederherstellen (F11)
    if reaper.APIExists("ImGui_Key_F11") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F11()) then
        state.request_maximize_toggle = true
        return
    end

    -- Transport: Go to Start of Project
    if is_action_pressed("rewind") then
        reaper.Main_OnCommand(40042, 0)
    end

    -- Transport: Leertaste Play/Stop
    if is_action_pressed("play_pause") then
        reaper.Main_OnCommand(40044, 0)
    end

    if is_action_pressed("toggle_autoscroll") then
        state.auto_scroll = not state.auto_scroll
        return
    end

    if is_action_pressed("toggle_articulations") then
        state.show_articulations_drawer = not state.show_articulations_drawer
        if state.show_articulations_drawer then
            state.show_dynamics = false
            state.show_tempo = false
            state.show_clefs = false
            local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
            ReaticulateParser.reload_all_banks()
        end
        return
    end

    if is_action_pressed("toggle_dynamics") then
        state.show_dynamics = not state.show_dynamics
        if state.show_dynamics then
            state.show_tempo = false
            state.show_clefs = false
            state.show_articulations_drawer = false
        end
        reaper.SetExtState("REAPER_Notator", "ShowDynamics", tostring(state.show_dynamics), true)
        return
    end

    if is_action_pressed("toggle_tempo") then
        state.show_tempo = not state.show_tempo
        if state.show_tempo then
            state.show_dynamics = false
            state.show_clefs = false
            state.show_articulations_drawer = false
        end
        return
    end

    if is_action_pressed("toggle_clefs") then
        state.show_clefs = not state.show_clefs
        if state.show_clefs then
            state.show_dynamics = false
            state.show_tempo = false
            state.show_articulations_drawer = false
        end
        return
    end

    -- Zwischenablage (Copy, Paste, Cut, Select All)
    if is_action_pressed("copy") then
        clipboard_service.copy(state, active_tracks_data)
    end

    if is_action_pressed("paste") then
        clipboard_service.paste(state, midi_service, active_tracks_data)
    end

    if is_action_pressed("cut") then
        clipboard_service.cut(state, midi_service, active_tracks_data)
    end

    if is_action_pressed("select_all") then
        state.selected_notes = {}
        state.selected_note = nil
        if active_tracks_data then
            for _, tdata in ipairs(active_tracks_data) do
                for _, n in ipairs(tdata.notes) do
                    state:select_note(n)
                end
            end
        end
        state.selected_dynamic = nil
        midi_service.sync_selection_to_reaper(state, active_tracks_data)
        state.status_msg = string.format("Selected all %d notes across all active tracks", state:count_selected_notes())
    end

    if is_action_pressed("select_to_end") then
        local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
        SelectionService.select_to_end(state, active_tracks_data, midi_service)
    end

    if is_action_pressed("filter_notes") then
        local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
        SelectionService.set_filter_notes_only(state, active_tracks_data, midi_service)
    end

    if is_action_pressed("filter_dynamics") then
        local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
        SelectionService.set_filter_dynamics_only(state, active_tracks_data, midi_service)
    end

    -- Delete via Delete / Backspace
    local del_pressed = is_action_pressed("delete")
    if not del_pressed and not is_ctrl and not is_shift and not is_alt then
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace()) or (reaper.APIExists("ImGui_Key_Delete") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete())) then
            del_pressed = true
        end
    end
    if del_pressed then
        if state.selected_fermata then
            local FermataService = package.loaded["services.fermata_service"] or require("services.fermata_service")
            FermataService.remove_fermata(state, state.selected_fermata.id, active_tracks_data)
            state.selected_fermata = nil
            state.context_fermata = nil
            return
        end
        if state.selected_rehearsal_mark then
            local RehearsalMarkService = package.loaded["services.rehearsal_mark_service"] or require("services.rehearsal_mark_service")
            RehearsalMarkService.remove_mark(state, state.selected_rehearsal_mark.id)
            state.selected_rehearsal_mark = nil
            state.context_rehearsal_mark = nil
            return
        end
        if state.selected_slur then
            local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
            SlurService.delete_slur(state, state.selected_slur.id, midi_service, active_tracks_data)
            state.selected_slur = nil
            return
        end
        if state.selected_tie then
            local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
            SlurService.delete_tie(state, state.selected_tie.id, midi_service, active_tracks_data)
            state.selected_tie = nil
            return
        end
        if state.selected_portamento then
            local PortamentoService = package.loaded["services.portamento_service"] or require("services.portamento_service")
            PortamentoService.delete_portamento(state, state.selected_portamento.id, active_tracks_data)
            state.selected_portamento = nil
            return
        end
        if state.selected_glissando then
            local GlissandoService = package.loaded["services.glissando_service"] or require("services.glissando_service")
            GlissandoService.delete_glissando(state, state.selected_glissando.id, active_tracks_data)
            state.selected_glissando = nil
            return
        end
        local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
        if SelectionService and SelectionService.count_all_selected(state) > 1 then
            SelectionService.delete_all_selected(state, midi_service, active_tracks_data)
            return
        end
        if state.selected_tempo_marker then
            local TempoService = require("services.tempo_service")
            TempoService.delete_selected_tempo_marker(state)
            return
        end
        if state.selected_octave_line then
            local OctaveService = require("services.octave_service")
            OctaveService.delete_line(state, state.selected_octave_line.id)
            state.selected_octave_line = nil
            return
        end
        if state.selected_hairpin then
            local HairpinService = require("services.hairpin_service")
            HairpinService.delete_hairpin(state, state.selected_hairpin.id, midi_service, active_tracks_data)
            state.selected_hairpin = nil
            return
        end
        if state.selected_dynamic_text then
            local DynamicTextService = require("services.dynamic_text_service")
            DynamicTextService.delete_dynamic_text(state, state.selected_dynamic_text.id, midi_service, active_tracks_data)
            state.selected_dynamic_text = nil
            return
        end
        if state.selected_pedal then
            local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
            PedalService.delete_pedal(state, state.selected_pedal.id, midi_service, active_tracks_data)
            state.selected_pedal = nil
            return
        end
        if state.selected_chord_item then
            local ScaleService = package.loaded["services.scale_service"] or require("services.scale_service")
            ScaleService.delete_chord_item(state, state.selected_chord_item.id, true)
            state.selected_chord_item = nil
            return
        end
        if state.selected_text_item then
            local TextItemService = require("services.text_item_service")
            TextItemService.delete_text_item(state, state.selected_text_item.id)
            state.selected_text_item = nil
            return
        end
        if state:count_selected_notes() > 0 or state.selected_note then
            midi_service.delete_selected_notes(state)
            midi_service.sync_selection_to_reaper(state, active_tracks_data)
            return
        end
        if (state.selected_articulations and state:count_selected_articulations() > 0) or state.selected_articulation then
            midi_service.delete_selected_articulations(state)
            return
        end
        if state.selected_dynamic then
            dynamics_engine.delete_selected_dynamic(state, midi_service, active_tracks_data)
            return
        end
    end

    -- Escape: Clear selection
    if reaper.APIExists("ImGui_Key_Escape") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        state:clear_selection()
        state:clear_articulation_selection()
        state.selected_dynamic = nil
        state.selected_tempo_marker = nil
        state.selected_octave_line = nil
        state.selected_fermata = nil
        state.context_fermata = nil
        state.selected_rehearsal_mark = nil
        state.context_rehearsal_mark = nil
        state.selected_hairpin = nil
        state.selected_dynamic_text = nil
        state.selected_pedal = nil
        state.selected_articulation = nil
        state.selected_text_item = nil
        state.editing_text_item = nil
        state.selected_chord_item = nil
        state.editing_chord_item = nil
        state.selected_slur = nil
        state.selected_tie = nil
        state.selected_portamento = nil
        state.selected_glissando = nil
        midi_service.sync_selection_to_reaper(state, active_tracks_data)
        state.status_msg = "Selection cleared"
    end

    -- Note selection navigation across timeline & chords (Alt + Arrow keys, Shift + Alt for range extension)
    local nav_right = is_action_pressed("select_next_note") or is_action_pressed("extend_next_note")
        or (is_alt and not is_ctrl and reaper.APIExists("ImGui_Key_RightArrow") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightArrow(), false))

    local nav_left = is_action_pressed("select_prev_note") or is_action_pressed("extend_prev_note")
        or (is_alt and not is_ctrl and reaper.APIExists("ImGui_Key_LeftArrow") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftArrow(), false))

    local nav_up = is_action_pressed("select_note_above") or is_action_pressed("extend_note_above")
        or (is_alt and not is_ctrl and reaper.APIExists("ImGui_Key_UpArrow") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow(), false))

    local nav_down = is_action_pressed("select_note_below") or is_action_pressed("extend_note_below")
        or (is_alt and not is_ctrl and reaper.APIExists("ImGui_Key_DownArrow") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow(), false))

    if nav_right then
        local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
        SelectionService.navigate_note(state, active_tracks_data, midi_service, "next", is_shift)
        return
    elseif nav_left then
        local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
        SelectionService.navigate_note(state, active_tracks_data, midi_service, "prev", is_shift)
        return
    elseif nav_up then
        local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
        SelectionService.navigate_note(state, active_tracks_data, midi_service, "above", is_shift)
        return
    elseif nav_down then
        local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
        SelectionService.navigate_note(state, active_tracks_data, midi_service, "below", is_shift)
        return
    end

    -- Note duration, moving & pitch via arrow keys
    if state:count_selected_notes() > 0 or state.selected_note then
        local step = state.grid_qn or 0.25

        -- Change grid note duration (Shift + arrow keys default)
        if is_action_pressed("lengthen_note") then
            midi_service.delta_selected_duration(state, step)
        elseif is_action_pressed("shorten_note") then
            midi_service.delta_selected_duration(state, -step)
        -- Horizontal movement on grid (Left/Right arrow keys)
        elseif is_action_pressed("move_right") then
            midi_service.move_selected_qn(state, step)
        elseif is_action_pressed("move_left") then
            midi_service.move_selected_qn(state, -step)
        -- Transposition (semitone / octave)
        elseif is_action_pressed("octave_up") then
            midi_service.transpose_selected(state, 12)
        elseif is_action_pressed("octave_down") then
            midi_service.transpose_selected(state, -12)
        elseif is_action_pressed("pitch_up") then
            midi_service.transpose_selected(state, 1)
        elseif is_action_pressed("pitch_down") then
            midi_service.transpose_selected(state, -1)
        end

        -- Invert / Flip Stem Direction (X)
        if is_action_pressed("invert_stem") or (not is_ctrl and not is_alt and not is_shift and reaper.APIExists("ImGui_Key_X") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_X())) then
            if midi_service and midi_service.invert_selected_notes_stem_direction then
                midi_service.invert_selected_notes_stem_direction(state, "invert")
            end
        end

        -- Cross-Staff Move / Toggle (M or Ctrl+Shift+Up/Down)
        local cross_toggle = is_action_pressed("cross_staff_toggle") or (not is_ctrl and not is_alt and not is_shift and reaper.APIExists("ImGui_Key_M") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_M()))
        local cross_up = is_action_pressed("cross_staff_up") or (is_ctrl and is_shift and not is_alt and reaper.APIExists("ImGui_Key_UpArrow") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_UpArrow()))
        local cross_down = is_action_pressed("cross_staff_down") or (is_ctrl and is_shift and not is_alt and reaper.APIExists("ImGui_Key_DownArrow") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_DownArrow()))

        if cross_up then
            if midi_service and midi_service.set_selected_notes_staff then
                midi_service.set_selected_notes_staff(state, "treble")
            end
        elseif cross_down then
            if midi_service and midi_service.set_selected_notes_staff then
                midi_service.set_selected_notes_staff(state, "bass")
            end
        elseif cross_toggle then
            if midi_service and midi_service.set_selected_notes_staff then
                midi_service.set_selected_notes_staff(state, "toggle")
            end
        end
    end

    -- Number keys for note values (2..7)
    local function set_dur(dval, dlbl)
        if state.set_active_duration then
            state:set_active_duration(dval, dlbl, midi_service)
        else
            state.active_dur = dval
            state.dur_label = dlbl
            if state.sync_grid_to_note then
                state.grid_qn = dval
                state.grid_label = dlbl
            end
            if state:count_selected_notes() > 0 then
                midi_service.change_selected_duration(state, dval)
            end
        end
        state.status_msg = "Note value: " .. dlbl .. (state.sync_grid_to_note and " (🔗 Grid synced)" or "")
    end

    if is_action_pressed("dur_32") then set_dur(0.125, "1/32") end
    if is_action_pressed("dur_16") then set_dur(0.25,  "1/16") end
    if is_action_pressed("dur_8")  then set_dur(0.5,   "1/8")  end
    if is_action_pressed("dur_4")  then set_dur(1.0,   "1/4")  end
    if is_action_pressed("dur_2")  then set_dur(2.0,   "1/2")  end
    if is_action_pressed("dur_1")  then set_dur(4.0,   "1/1")  end

    -- Grid shortcuts (Ctrl + 1..7)
    local function set_grid(gqn, glbl)
        if state.set_grid then
            state:set_grid(gqn, glbl, midi_service)
        else
            state.grid_qn = gqn
            state.grid_label = glbl
            if state.sync_grid_to_note and gqn > 0 then
                state.active_dur = gqn
                state.dur_label = glbl
                if state:count_selected_notes() > 0 then
                    midi_service.change_selected_duration(state, gqn)
                end
            end
        end
        state.status_msg = "Grid: " .. glbl .. (state.sync_grid_to_note and " (🔗 Note synced)" or "")
    end

    if is_action_pressed("grid_1") then set_grid(4.0, "1/1") end
    if is_action_pressed("grid_2") then set_grid(2.0, "1/2") end
    if is_action_pressed("grid_4") then set_grid(1.0, "1/4") end
    if is_action_pressed("grid_8") then set_grid(0.5, "1/8") end
    if is_action_pressed("grid_16") then set_grid(0.25, "1/16") end
    if is_action_pressed("grid_32") then set_grid(0.125, "1/32") end
    if is_action_pressed("grid_free") then set_grid(0.0, "Free") end

    -- Toggle Grid & Note Value Sync (🔗)
    if is_action_pressed("toggle_grid_note_sync") then
        state.sync_grid_to_note = not state.sync_grid_to_note
        if state.sync_grid_to_note and state.active_dur and state.active_dur > 0 then
            state.grid_qn = state.active_dur
            state.grid_label = state.dur_label or "1/4"
        end
        state.status_msg = "Grid & Note Duration Linked: " .. (state.sync_grid_to_note and "🔗 ON" or "OFF")
        require("state").save_settings(state)
    end

    -- Dotting
    if is_action_pressed("toggle_dot") then
        state.is_dotted = not state.is_dotted
        state.status_msg = "Dotting: " .. (state.is_dotted and "ON" or "OFF")
        if state:count_selected_notes() > 0 then
            for _, sn in pairs(state.selected_notes) do
                local new_dur = state.is_dotted and (sn.dur_qn * 1.5) or (sn.dur_qn / 1.5)
                midi_service.change_selected_duration(state, new_dur)
                break
            end
        end
    end

    -- Accidentals (♭ Flat, ♮ Natural, ♯ Sharp)
    local is_flat = is_action_pressed("acc_flat")
    if not is_flat and not is_ctrl and not is_alt and not is_shift then
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Minus()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadSubtract()) then
            is_flat = true
        end
    end
    if is_flat then
        if state:count_selected_notes() > 0 or state.selected_note then
            midi_service.apply_accidental_to_selected(state, -1)
        else
            state.accidental = (state.accidental == -1) and 0 or -1
            state.status_msg = "Accidental: " .. (state.accidental == -1 and "♭ Flat" or "♮ Natural")
        end
    end

    local is_natural = is_action_pressed("acc_natural")
    if not is_natural and not is_ctrl and not is_alt and not is_shift then
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_0()) or (reaper.APIExists("ImGui_Key_Keypad0") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Keypad0())) then
            is_natural = true
        end
    end
    if is_natural then
        if state:count_selected_notes() > 0 or state.selected_note then
            midi_service.apply_accidental_to_selected(state, 0)
        else
            if state.accidental == 0 then
                state.accidental = 2
                state.status_msg = "Accidental: ♮ Natural (Override Key Signature)"
            else
                state.accidental = 0
                state.status_msg = "Accidental: Key Signature Default"
            end
        end
    end

    local is_sharp = is_action_pressed("acc_sharp")
    if not is_sharp and not is_ctrl and not is_alt and not is_shift then
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Equal()) or (reaper.APIExists("ImGui_Key_KeypadAdd") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_KeypadAdd())) then
            is_sharp = true
        end
    end
    if is_sharp then
        if state:count_selected_notes() > 0 or state.selected_note then
            midi_service.apply_accidental_to_selected(state, 1)
        else
            state.accidental = (state.accidental == 1) and 0 or 1
            state.status_msg = "Accidental: " .. (state.accidental == 1 and "♯ Sharp" or "♮ Natural")
        end
    end

    -- Text Items (Ctrl + T: New Text Item at cursor position)
    if is_action_pressed("new_text_item") or (is_ctrl and not is_shift and not is_alt and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_T())) then
        local cur_time = reaper.GetCursorPosition()
        local cur_qn = reaper.TimeMap2_timeToQN(0, cur_time)
        local cur_trk = state.focused_track or (active_tracks_data and active_tracks_data[1] and active_tracks_data[1].track)
        if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
            local guid = reaper.GetTrackGUID(cur_trk)
            local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
            local ti = TextItemService.create_text_item(state, guid, cur_qn, 32.0, "Text", "italic", 16.0)
            state.selected_text_item = ti
            state.editing_text_item = ti
            state.editing_text_str = ti.text
            state.editing_text_just_opened = true
            state.status_msg = "New Text Item created (Ctrl+T)"
            return
        end
    end

    -- Project Save (Ctrl + S)
    if is_ctrl and not is_shift and not is_alt and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S()) then
        reaper.Main_SaveProject(0, false)
        state.status_msg = "Project saved (Ctrl+S)."
    end

    -- Articulations, Slurs & Ties (T for tie, S for slur, A for accent)
    local eff_tracks_data = active_tracks_data or state.active_tracks_cache
    if not is_ctrl and not is_alt and not is_shift then
        if is_action_pressed("toggle_tie") or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_T()) then
            midi_service.toggle_tie(state, eff_tracks_data)
        end
        if is_action_pressed("toggle_slur") or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_S()) then
            midi_service.toggle_slur(state, eff_tracks_data)
        end
        if is_action_pressed("toggle_portamento") or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_P()) then
            midi_service.toggle_portamento(state, eff_tracks_data)
        end
        if not is_step and (is_action_pressed("toggle_glissando") or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_G())) then
            midi_service.toggle_glissando(state, eff_tracks_data)
        end
        if not is_step and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_A()) then
            midi_service.toggle_selected_articulation(state, "accent")
        end
    end
end

return KeyboardHandler

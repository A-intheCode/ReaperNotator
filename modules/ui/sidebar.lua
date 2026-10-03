-- ==============================================================================
-- REAPER Native Notator - Module: Sidebar (Main Left Panel / Palette)
-- Input modes, clipboard (Copy/Paste), note values, accidentals, articulations
-- ==============================================================================

local Constants = require("constants")
local Sidebar = {}

local function toggle_btn(ctx, label, is_active, w, h, active_col)
    local pushed = false
    if is_active then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), active_col or 0xFF9F1CFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFFA726FF)
        pushed = true
    end
    local clicked = reaper.ImGui_Button(ctx, label, w or 0, h or 0)
    if pushed then
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
    return clicked
end

function Sidebar.render(ctx, state, midi_service, clipboard_service, active_tracks_data, w, h, child_border, sidebar_flags)
    if not reaper.ImGui_BeginChild(ctx, "SidebarPalette", w, h, child_border, sidebar_flags) then
        return
    end
    
    -- ZOOM
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "ZOOM")
    reaper.ImGui_Separator(ctx)
    local avail_w_zoom = reaper.ImGui_GetContentRegionAvail(ctx)
    local zoom_half_w = math.floor((avail_w_zoom - 6) / 2)
    if reaper.ImGui_Button(ctx, "Zoom -", zoom_half_w, 26) then
        state.zoom = math.max(0.6, state.zoom - 0.1)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "Zoom +", zoom_half_w, 26) then
        state.zoom = math.min(2.0, state.zoom + 0.1)
    end
    reaper.ImGui_Spacing(ctx)
    
    -- A. INPUT MODES (Selection, Write Notes / Draw, Step Input)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "INPUT MODE")
    reaper.ImGui_Separator(ctx)
    local cur_mode = state.input_mode_type or "select"
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
    
    if toggle_btn(ctx, "🖱 Selection Mode", cur_mode == "select", -1, 25, 0x3498DBFF) then
        change_mode("select")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Selection Mode (Esc): Select, move and edit notes")
    end
    
    if toggle_btn(ctx, "🪶 Write Notes [D]", cur_mode == "draw", -1, 25, 0x2ECC71FF) then
        change_mode(cur_mode == "draw" and "select" or "draw")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Write Notes / Mouse Draw Mode [D]: Hover over staff to preview, left-click to insert note")
    end
    
    if toggle_btn(ctx, "✏ Step Input", cur_mode == "step", -1, 25, 0xE67E22FF) then
        change_mode(cur_mode == "step" and "select" or "step")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Step Input Mode: Insert notes using keys C, D, E, F, G, A, B at cursor")
    end
    
    -- B. NOTE VALUES (1/1 to 1/32 with shortcuts [7] to [2])
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "NOTE VALUES")
    reaper.ImGui_Separator(ctx)
    
    local dur_list = {
        { val = 4.0,   label = "𝅝  1/1 (Whole)", key = "7" },
        { val = 2.0,   label = "𝅗𝅥  1/2 (Half)", key = "6" },
        { val = 1.0,   label = "𝅘𝅥  1/4 (Quarter)", key = "5" },
        { val = 0.5,   label = "𝅘𝅥𝅮  1/8 (Eighth)", key = "4" },
        { val = 0.25,  label = "𝅘𝅥𝅯  1/16 (16th)", key = "3" },
        { val = 0.125, label = "𝅘𝅥𝅰  1/32 (32nd)", key = "2" }
    }
    for _, d in ipairs(dur_list) do
        local is_active = (state.active_dur == d.val)
        local btn_lbl = string.format("%s [%s]", d.label, d.key)
        if toggle_btn(ctx, btn_lbl, is_active, -1, 25) then
            state.active_dur = d.val
            state.dur_label = d.label:match("(%d+/%d+)")
            if state:count_selected_notes() > 0 then
                midi_service.change_selected_duration(state, d.val)
            end
        end
    end
    
    -- C. TUPLETS
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "TUPLETS")
    reaper.ImGui_Separator(ctx)
    
    local avail_w_tup = reaper.ImGui_GetContentRegionAvail(ctx)
    local tup_third_w = math.floor((avail_w_tup - 8) / 3)
    local cur_tup = state.tuplet_type
    
    local function apply_tuplet(t_val)
        if state:count_selected_notes() > 0 then
            if t_val == nil or t_val == "none" or t_val == "normal" then
                midi_service.change_selected_duration(state, state.active_dur)
            else
                midi_service.convert_selected_to_tuplet(state, t_val, active_tracks_data)
            end
        else
            state:set_tuplet_type(t_val)
        end
    end

    -- Row 1: 1:1 Normal, 3 Triplet, 5 Quintuplet
    if toggle_btn(ctx, "1:1 Norm", cur_tup == nil, tup_third_w, 24, 0x444444FF) then
        apply_tuplet(nil)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Normal note value (1:1 without tuplet subdivision)")
    end
    reaper.ImGui_SameLine(ctx)
    if toggle_btn(ctx, "3 Triplet", cur_tup == "3", tup_third_w, 24) then
        apply_tuplet(cur_tup == "3" and nil or "3")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Triplet (3:2) - 3 notes in the space of 2")
    end
    reaper.ImGui_SameLine(ctx)
    if toggle_btn(ctx, "5 Quintuplet", cur_tup == "5", tup_third_w, 24) then
        apply_tuplet(cur_tup == "5" and nil or "5")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Quintuplet (5:4) - 5 notes in the space of 4")
    end

    -- Row 2: 6 Sextuplet, 7 Septuplet, 8 Octuplet
    if toggle_btn(ctx, "6 Sextuplet", cur_tup == "6", tup_third_w, 24) then
        apply_tuplet(cur_tup == "6" and nil or "6")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Sextuplet (6:4) - 6 notes in the space of 4")
    end
    reaper.ImGui_SameLine(ctx)
    if toggle_btn(ctx, "7 Septuplet", cur_tup == "7", tup_third_w, 24) then
        apply_tuplet(cur_tup == "7" and nil or "7")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Septuplet (7:4) - 7 notes in the space of 4")
    end
    reaper.ImGui_SameLine(ctx)
    if toggle_btn(ctx, "8 Octuplet", cur_tup == "8", tup_third_w, 24) then
        apply_tuplet(cur_tup == "8" and nil or "8")
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Octuplet (8:6) - 8 notes in the space of 6")
    end

    -- Button to create at cursor
    local cr_lbl = cur_tup and string.format("➕ Create %s at Cursor", (Constants.TUPLET_DEFS and Constants.TUPLET_DEFS[cur_tup] and Constants.TUPLET_DEFS[cur_tup].name or (cur_tup .. "-tuplet"))) or "➕ Create Triplet at Cursor"
    if reaper.ImGui_Button(ctx, cr_lbl, -1, 26) then
        midi_service.create_tuplet_at_cursor(state, cur_tup or "3", active_tracks_data)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Creates a tuplet pattern at cursor (or converts selected notes) and selects first note for Step-Input / Draw.")
    end

    -- D. ACCIDENTALS
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "ACCIDENTALS")
    reaper.ImGui_Separator(ctx)
    
    local avail_w_acc = reaper.ImGui_GetContentRegionAvail(ctx)
    local third_w = math.floor((avail_w_acc - 8) / 3)
    
    local cur_acc = state.accidental
    local target_note = state.selected_note
    if not target_note then
        for _, n in pairs(state.selected_notes) do target_note = n break end
    end
    if target_note then
        local sn = target_note
        local k = sn.key or (sn.get_key and sn:get_key())
        local pref = state.note_accidentals and state.note_accidentals[k]
        if pref == nil and state.note_accidentals and sn.take then
            local id_k = string.format("%s_%s_%.3f", tostring(sn.take or "0"), tostring(sn.idx), sn.start_qn)
            pref = state.note_accidentals[id_k]
            if pref == nil then
                local pos_k = string.format("%s_%.3f_%d", tostring(sn.take or "0"), sn.start_qn, sn.pitch)
                pref = state.note_accidentals[pos_k]
            end
        end
        if pref ~= nil then
            cur_acc = (pref == 2) and 0 or pref
        else
            local p_mod = sn.pitch % 12
            local p_info = Constants.PITCH_MAP[p_mod]
            cur_acc = p_info and p_info.acc or 0
        end
    end
    
    local is_flat_active = (cur_acc == -1)
    local is_nat_active = (cur_acc == 0)
    local is_sharp_active = (cur_acc == 1)
    
    if toggle_btn(ctx, "♭ Flat [-]", is_flat_active, third_w, 24) then
        if state:count_selected_notes() > 0 or state.selected_note then
            midi_service.apply_accidental_to_selected(state, -1)
        else
            state.accidental = (state.accidental == -1) and 0 or -1
            state.status_msg = "Accidental: " .. (state.accidental == -1 and "♭ Flat" or "♮ Natural")
        end
    end
    reaper.ImGui_SameLine(ctx)
    if toggle_btn(ctx, "♮ Natural [0]", is_nat_active, third_w, 24, 0x444444FF) then
        if state:count_selected_notes() > 0 or state.selected_note then
            midi_service.apply_accidental_to_selected(state, 0)
        else
            state.accidental = 0
            state.status_msg = "Accidental: ♮ Natural"
        end
    end
    reaper.ImGui_SameLine(ctx)
    if toggle_btn(ctx, "♯ Sharp [+]", is_sharp_active, third_w, 24) then
        if state:count_selected_notes() > 0 or state.selected_note then
            midi_service.apply_accidental_to_selected(state, 1)
        else
            state.accidental = (state.accidental == 1) and 0 or 1
            state.status_msg = "Accidental: " .. (state.accidental == 1 and "♯ Sharp" or "♮ Natural")
        end
    end
    
    -- E. ARTICULATIONS (Staccato, Tenuto, Accent, Marcato, Harmonic, Clear)
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "ARTICULATIONS")
    reaper.ImGui_Separator(ctx)
    
    local avail_w_art = reaper.ImGui_GetContentRegionAvail(ctx)
    local third_w_art = math.floor((avail_w_art - 8) / 3)
    
    local function normalize_art(a)
        if not a or a == "" or a == "none" then return nil end
        local low = tostring(a):lower()
        if low:find("staccatiss") or low:find("spicc") then return "staccatissimo"
        elseif low:find("stacc") then return "staccato"
        elseif low:find("marc") then return "marcato"
        elseif low:find("tenuto") or low == "ten" then return "tenuto"
        elseif low:find("accent") or low == "acc" then return "accent"
        elseif low:find("harm") or low:find("flag") then return "harmonic"
        end
        return low
    end
    
    local active_track = state.focused_track
    if not active_track and state.selected_note and state.selected_note.track then
        active_track = state.selected_note.track
    end
    if not active_track and state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            if sn.track then active_track = sn.track break end
        end
    end
    if not active_track then
        active_track = reaper.GetSelectedTrack(0, 0)
    end
    
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser.get_all_banks()
    local track_guid = active_track and reaper.GetTrackGUID(active_track)
    local trk_override = track_guid and state.track_articulation_banks and state.track_articulation_banks[track_guid]
    local active_bank = active_track and ReaticulateParser.get_bank_for_track(active_track, all_banks, trk_override)
    
    local function is_art_supported(art_id)
        if not active_bank then return true end
        return midi_service.find_reaticulate_art_for_id(active_bank, art_id) ~= nil
    end
    
    local cur_art = normalize_art(state.active_articulation)
    local target_note_art = state.selected_note
    if not target_note_art then
        for _, n in pairs(state.selected_notes) do target_note_art = n break end
    end
    if target_note_art and (state:count_selected_notes() > 0 or state.selected_note) then
        cur_art = normalize_art(target_note_art.articulation)
    end
    
    local function handle_art_btn(art_id)
        if (state.selected_articulations and state:count_selected_articulations() > 0) or state.selected_articulation then
            midi_service.delete_selected_articulations(state)
            state.active_articulation = nil
        elseif state:count_selected_notes() > 0 or state.selected_note then
            midi_service.toggle_selected_articulation(state, art_id or "none")
            state.active_articulation = (art_id and state.selected_note) and normalize_art(state.selected_note.articulation) or nil
        else
            local norm_clicked = normalize_art(art_id)
            state.active_articulation = (cur_art == norm_clicked) and nil or norm_clicked
            if state.active_articulation then
                state.status_msg = string.format("Sticky Articulation: %s (applies to next entered notes)", state.active_articulation)
            else
                state.status_msg = "Sticky Articulation: Off"
            end
        end
    end
    
    local hov_flags = (reaper.ImGui_HoveredFlags_AllowWhenDisabled and reaper.ImGui_HoveredFlags_AllowWhenDisabled()) or 0
    
    local function render_art_button(art_id, label, default_tooltip, w)
        local avail = is_art_supported(art_id)
        if not avail then
            reaper.ImGui_BeginDisabled(ctx)
        end
        
        local is_active = (cur_art == art_id)
        if toggle_btn(ctx, label, is_active, w, 24) then
            if avail then
                handle_art_btn(art_id)
            end
        end
        
        if reaper.ImGui_IsItemHovered(ctx, hov_flags) then
            if not avail then
                local b_name = active_bank and (active_bank.name or "Bank") or "Bank"
                reaper.ImGui_SetTooltip(ctx, string.format("%s\n⚠️ Not available in Reaticulate bank '%s'!", default_tooltip, b_name))
            else
                reaper.ImGui_SetTooltip(ctx, default_tooltip)
            end
        end
        
        if not avail then
            reaper.ImGui_EndDisabled(ctx)
        end
    end
    
    -- Row 1: • Staccato, ▼ Staccatissimo, — Tenuto
    render_art_button("staccato", "• Stacc", "Staccato (•): Short and detached.\nBridges to Reaticulate if track has an articulation bank!", third_w_art)
    reaper.ImGui_SameLine(ctx)
    render_art_button("staccatissimo", "▼ Staccatiss", "Staccatissimo (▼/▲): Very short / pointed wedge (or Spiccato).\nBridges to Reaticulate if track has an articulation bank!", third_w_art)
    reaper.ImGui_SameLine(ctx)
    render_art_button("tenuto", "— Ten", "Tenuto (—): Held full value.\nBridges to Reaticulate if track has an articulation bank!", third_w_art)
    
    -- Row 2: > Accent, ^ Marcato, ○ Harmonic
    render_art_button("accent", "> Acc", "Accent (>): Emphasized attack.\nBridges to Reaticulate if track has an articulation bank!", third_w_art)
    reaper.ImGui_SameLine(ctx)
    render_art_button("marcato", "^ Marc", "Marcato (^): Strong accent / pointed attack.\nBridges to Reaticulate if track has an articulation bank!", third_w_art)
    reaper.ImGui_SameLine(ctx)
    render_art_button("harmonic", "○ Harm", "Harmonic / Flageolet (○): String flageolet / natural harmonic.\nBridges to Reaticulate if track has an articulation bank!", third_w_art)
    
    -- Row 3: Clear / None
    if reaper.ImGui_Button(ctx, "✕ Clear Articulation", -1, 22) then
        handle_art_btn(nil)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Clear Articulation: Removes articulation from selected notes or turns off sticky mode.")
    end
    
    -- F. TRANSPOSE & OCTAVE
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "TRANSPOSE")
    reaper.ImGui_Separator(ctx)
    
    local avail_w_trans = reaper.ImGui_GetContentRegionAvail(ctx)
    local quarter_w = math.floor((avail_w_trans - 12) / 4)
    local half_w = math.floor((avail_w_trans - 6) / 2)
    
    if reaper.ImGui_Button(ctx, "▲ +1", quarter_w, 26) then midi_service.transpose_selected(state, 1) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "▼ -1", quarter_w, 26) then midi_service.transpose_selected(state, -1) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "▲▲ +Oct", quarter_w, 26) then midi_service.transpose_selected(state, 12) end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "▼▼ -Oct", quarter_w, 26) then midi_service.transpose_selected(state, -12) end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Text(ctx, string.format("Input Octave: C%d", state.current_octave))
    if reaper.ImGui_Button(ctx, "- Oct##Inp", half_w, 24) then
        if state:count_selected_notes() > 0 then
            midi_service.transpose_selected(state, -12)
        else
            state.current_octave = math.max(1, state.current_octave - 1)
            state.status_msg = string.format("Input octave set to C%d", state.current_octave)
        end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "+ Oct##Inp", half_w, 24) then
        if state:count_selected_notes() > 0 then
            midi_service.transpose_selected(state, 12)
        else
            state.current_octave = math.min(7, state.current_octave + 1)
            state.status_msg = string.format("Input octave set to C%d", state.current_octave)
        end
    end
    
    reaper.ImGui_Spacing(ctx)
    if reaper.ImGui_Button(ctx, "🎹 Scale...", -1, 26) then
        state.show_scale_modal = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Scale Transpose: Snap/transpose selected notes to any scale or mode.")
    end
    
    local is_keys_active = (state.show_key_signatures == true)
    if toggle_btn(ctx, "♯♭ Key Signatures...", is_keys_active, -1, 26, 0xFF9F1CFF) then
        state.show_key_signatures = not state.show_key_signatures
        if state.show_key_signatures then
            state.show_clefs = false
            state.show_dynamics = false
            state.show_tempo = false
            state.show_articulations_drawer = false
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Key & Time Signature Drawer:\nBrowse and set key signatures (7♭ to 7♯) and time signatures per MIDI item, track or project.")
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_Spacing(ctx)
    
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "TEXT & NOTES")
    if reaper.ImGui_Button(ctx, "🔤 + Text Item [Ctrl+T]", -1, 26) then
        local cur_time = reaper.GetCursorPosition()
        local cur_qn = reaper.TimeMap2_timeToQN(0, cur_time)
        local cur_trk = state.focused_track
        if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
            local guid = reaper.GetTrackGUID(cur_trk)
            local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
            local ti = TextItemService.create_text_item(state, guid, cur_qn, 32.0, "Text", "italic", 16.0)
            state.selected_text_item = ti
            state.editing_text_item = ti
            state.editing_text_str = ti.text
            state.editing_text_just_opened = true
            state.status_msg = "New Text Item created"
        else
            state.status_msg = "Please select a track first!"
        end
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "REPEAT MARKS (%)")
    local cur_time = reaper.GetCursorPosition()
    local cur_qn = reaper.TimeMap2_timeToQN(0, cur_time)
    local _, cur_m = reaper.TimeMap2_timeToBeats(0, cur_time)
    cur_m = cur_m or math.floor(cur_qn / 4.0)
    
    local cur_trk = state.focused_track
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        cur_trk = reaper.GetSelectedTrack(0, 0)
        if not cur_trk and active_tracks_data and active_tracks_data[1] then
            cur_trk = active_tracks_data[1].track
        end
    end
    if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        state.focused_track = cur_trk
    end
    
    local has_rep = false
    if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        local RepeatService = require("services.repeat_service")
        local guid = reaper.GetTrackGUID(cur_trk)
        has_rep = RepeatService.has_repeat_mark(state, guid, cur_m)
    end
    
    local rep_label = has_rep and string.format("❌ Remove Repeat Bar %d (%%)", cur_m + 1) or string.format("🔁 Repeat Bar %d (%%)", cur_m + 1)
    if reaper.ImGui_Button(ctx, rep_label, -1, 26) then
        if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
            local RepeatService = require("services.repeat_service")
            RepeatService.toggle_repeat_mark(state, cur_trk, cur_m, active_tracks_data)
        else
            state.status_msg = "Please focus or select a track first to set Repeat Mark!"
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Toggle 1-Bar Repeat Mark (%) at current edit cursor.\nRepeats notes from preceding measure and writes MIDI data into the REAPER MIDI item!")
    end
    
    if reaper.ImGui_Button(ctx, "🔄 Sync Repeat Marks", -1, 24) then
        local RepeatService = require("services.repeat_service")
        RepeatService.sync_all(state)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Re-scans preceding source measures and updates repeated MIDI notes on all tracks.")
    end
    
    reaper.ImGui_EndChild(ctx)
end

return Sidebar

-- ==============================================================================
-- REAPER Native Notator - Module: MouseHandler
-- Mouse interactions: Edit cursor, track focus, drag & drop, edge resizing & marquee
-- ==============================================================================

local Constants = require("constants")
local MidiNote  = require("classes.note")
local Engraver  = require("rendering.engraver")
local MidiService = require("services.midi_service")
local AudioPreview = require("services.audio_preview")
local HairpinService = require("services.hairpin_service")
local DynamicTextService = require("services.dynamic_text_service")

local MouseHandler = {}

function MouseHandler.handle(ctx, state, canvas_info, midi_service, dynamics_engine)
    if not canvas_info then return end
    local margin_left = canvas_info.margin_left
    local qn_per_measure = canvas_info.qn_per_measure
    local measure_map = canvas_info.measure_map or state.measure_map
    local active_tracks_data = canvas_info.active_tracks_data or {}
    local s = state.zoom
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
    local is_ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl())
    local is_shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
    
    -- 1. ITEM RESIZING
    if state.hovered_item_edge and reaper.ImGui_IsMouseClicked(ctx, 0) and not is_ctrl then
        state.is_resizing_item = true
        state.resize_item_info = state.hovered_item_edge.item_info
        state.resize_edge = state.hovered_item_edge.edge
        state.resize_start_x = mouse_x
        state.resize_orig_pos = state.hovered_item_edge.item_info.pos
        state.resize_orig_len = state.hovered_item_edge.item_info.len
    end
    
    if state.is_resizing_item and reaper.ImGui_IsMouseDown(ctx, 0) then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
        local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
        
        if state.resize_edge == "right" then
            local start_qn = reaper.TimeMap2_timeToQN(0, state.resize_orig_pos)
            local new_end_qn = math.max(start_qn + 0.25, target_qn)
            reaper.SetMediaItemInfo_Value(state.resize_item_info.item, "B_LOOPSRC", 0)
            reaper.MIDI_SetItemExtents(state.resize_item_info.item, start_qn, new_end_qn)
            reaper.SetMediaItemInfo_Value(state.resize_item_info.item, "B_LOOPSRC", 0)
        elseif state.resize_edge == "left" then
            local orig_end_time = state.resize_orig_pos + state.resize_orig_len
            local orig_end_qn = reaper.TimeMap2_timeToQN(0, orig_end_time)
            local new_start_qn = math.min(orig_end_qn - 0.25, target_qn)
            reaper.SetMediaItemInfo_Value(state.resize_item_info.item, "B_LOOPSRC", 0)
            reaper.MIDI_SetItemExtents(state.resize_item_info.item, new_start_qn, orig_end_qn)
            reaper.SetMediaItemInfo_Value(state.resize_item_info.item, "B_LOOPSRC", 0)
        end
        reaper.UpdateArrange()
    end
    
    if state.is_resizing_item and reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.resize_item_info and state.resize_item_info.item then
            reaper.SetMediaItemInfo_Value(state.resize_item_info.item, "B_LOOPSRC", 0)
            reaper.UpdateArrange()
        end
        state.is_resizing_item = false
        state.resize_item_info = nil
        state.resize_edge = nil
        reaper.Undo_OnStateChangeEx2(0, "Notator: Resize MIDI Item", 4, -1)
        if MidiService and MidiService.invalidate_cache then
            MidiService.invalidate_cache()
        end
    end
    
    -- 2. NOTE DRAG & DROP (Continuously calculates target position & pitch for preview)
    if state.drag_note and state.input_mode_type ~= "draw" and reaper.ImGui_IsMouseDown(ctx, 0) and not state.is_resizing_item and not state.marquee_active and not state.marquee_potential then
        local dx = math.abs(mouse_x - state.drag_start_x)
        local dy = math.abs(mouse_y - state.drag_start_y)
        if dx > 3 or dy > 3 or reaper.ImGui_IsMouseDragging(ctx, 0, 3.0) then
            state.is_dragging = true
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll())
            
            -- Determine target track & staff under mouse (including ledger line tolerance)
            local note_trk = nil
            for _, tdata in ipairs(active_tracks_data) do
                if tdata.track == state.drag_note.track then
                    note_trk = tdata
                    break
                end
            end
            
            local target_trk = nil
            for _, tdata in ipairs(active_tracks_data) do
                if tdata.band_y0 and tdata.band_y1 and mouse_y >= tdata.band_y0 and mouse_y <= tdata.band_y1 then
                    target_trk = tdata
                    break
                end
            end
            target_trk = target_trk or note_trk or active_tracks_data[1]
            
            if target_trk and target_trk.band_y0 then
                local line_spacing = 8.0 * s
                local step_y = line_spacing / 2.0
                local treble_bot = target_trk.treble_bottom_y or (target_trk.band_y0 + 72 * s)
                local bass_bot = target_trk.bass_bottom_y or (target_trk.is_grand and (target_trk.band_y0 + 148 * s) or (target_trk.band_y0 + 80 * s))
                local mid_bot = target_trk.mid_bottom_y
                local new_pitch, in_tr = Engraver.canvas_y_to_pitch(mouse_y, treble_bot, bass_bot, step_y, target_trk.is_grand, target_trk.clef, nil, mid_bot)
                state.drag_target_pitch = math.max(0, math.min(127, new_pitch or (state.drag_note and state.drag_note.pitch) or 60))
            else
                state.drag_target_pitch = state.drag_note and state.drag_note.pitch or 60
            end
            
            local orig_start_qn = state.drag_note and state.drag_note.start_qn or 0
            local orig_pitch = state.drag_note and state.drag_note.pitch or 60
            
            -- Axis locking / deadzone:
            -- For primarily vertical motion (pitch change), the rhythmic position remains untouched (delta_qn = 0).
            -- This prevents breaking tuplets and accidental grid jumping!
            local is_vertical_drag = (dy > 3 * s and dx < 10 * s) or (dy > dx * 1.8 and dx < 18 * s)
            local is_horizontal_drag = (dx > 3 * s and dy < 8 * s) or (dx > dy * 1.8 and dy < 14 * s)
            
            if is_vertical_drag then
                state.drag_target_qn = orig_start_qn
                state.drag_delta_qn = 0
                state.drag_delta_pitch = state.drag_target_pitch - orig_pitch
            elseif is_horizontal_drag then
                local snap_grid = is_shift and 0.001 or state.grid_qn
                local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map) or orig_start_qn
                state.drag_target_qn = math.max(0, target_qn)
                state.drag_delta_qn = state.drag_target_qn - orig_start_qn
                state.drag_target_pitch = orig_pitch
                state.drag_delta_pitch = 0
            else
                local snap_grid = is_shift and 0.001 or state.grid_qn
                local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map) or orig_start_qn
                state.drag_target_qn = math.max(0, target_qn)
                state.drag_delta_qn = state.drag_target_qn - orig_start_qn
                state.drag_delta_pitch = state.drag_target_pitch - orig_pitch
            end
            
            -- Clamp deltas so no note becomes < 0 QN or pitch < 0 / > 127
            for _, sn in ipairs(state.drag_selected_snapshot or {}) do
                if sn.start_qn and (sn.start_qn + state.drag_delta_qn < 0) then
                    state.drag_delta_qn = -sn.start_qn
                end
                if sn.pitch then
                    if sn.pitch + state.drag_delta_pitch < 0 then
                        state.drag_delta_pitch = -sn.pitch
                    end
                    if sn.pitch + state.drag_delta_pitch > 127 then
                        state.drag_delta_pitch = 127 - sn.pitch
                    end
                end
            end
            
            -- Audition upon vertical movement (pitch change)
            local effective_pitch = orig_pitch + state.drag_delta_pitch
            if state.is_dragging and state.last_drag_audition_pitch ~= effective_pitch then
                state.last_drag_audition_pitch = effective_pitch
                local trk_ptr = (target_trk and target_trk.track) or (state.drag_note and state.drag_note.track)
                AudioPreview.play_note(state, effective_pitch, state.drag_note and state.drag_note.vel, state.drag_note and state.drag_note.chan, trk_ptr, state.drag_note and state.drag_note.start_qn)
            end
        end
    end
    
    if state.drag_note and reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.is_dragging and not state.marquee_active and not state.marquee_potential then
            local orig_start_qn = state.drag_note and state.drag_note.start_qn or 0
            local orig_pitch = state.drag_note and state.drag_note.pitch or 60
            local delta_qn = state.drag_delta_qn or ((state.drag_target_qn or orig_start_qn) - orig_start_qn)
            local delta_pitch = state.drag_delta_pitch or ((state.drag_target_pitch or orig_pitch) - orig_pitch)
            
            if (math.abs(delta_qn) > 0.01 or delta_pitch ~= 0) and #state.drag_selected_snapshot > 0 then
                reaper.Undo_BeginBlock2(0)
                local affected_takes = {}
                local take_moved_notes = {}
                local new_selected = {}
                local items_to_expand = {}
                
                -- Disable re-sorting prior to modifying all notes so indices remain stable!
                for _, sn in ipairs(state.drag_selected_snapshot) do
                    local take = sn.take
                    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
                        if not affected_takes[take] then
                            affected_takes[take] = true
                            reaper.MIDI_DisableSort(take)
                        end
                    end
                end
                
                for _, sn in ipairs(state.drag_selected_snapshot) do
                    local take = sn.take
                    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
                        local new_sqn = math.max(0, sn.start_qn + delta_qn)
                        local new_eqn = new_sqn + sn.dur_qn
                        local new_pitch = math.max(0, math.min(127, sn.pitch + delta_pitch))
                        
                        local item = reaper.GetMediaItemTake_Item(take)
                        if item and delta_qn > 0 then
                            local it_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                            local it_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                            local it_end_qn = reaper.TimeMap2_timeToQN(0, it_pos + it_len)
                            if new_eqn > it_end_qn then
                                items_to_expand[item] = math.max(items_to_expand[item] or it_end_qn, new_eqn + 1.0)
                            end
                        end
                        
                        local orig_sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn)
                        local target_idx = nil
                        local ok, _, muted, s_chk, e_chk, chan, p_chk, vel = reaper.MIDI_GetNote(take, sn.idx)
                        if ok and p_chk == sn.pitch and math.abs(s_chk - orig_sppq) < 15 then
                            target_idx = sn.idx
                        else
                            local _, notecnt = reaper.MIDI_CountEvts(take)
                            for i = 0, notecnt - 1 do
                                local ok2, _, m2, s2, e2, c2, p2, v2 = reaper.MIDI_GetNote(take, i)
                                if ok2 and p2 == sn.pitch and math.abs(s2 - orig_sppq) < 15 then
                                    target_idx = i
                                    ok, muted, s_chk, e_chk, chan, p_chk, vel = ok2, m2, s2, e2, c2, p2, v2
                                    break
                                end
                            end
                        end
                        
                        if target_idx and ok then
                            -- If only pitch changed: sppq and eppq remain 1:1 untouched!
                            local sppq, eppq
                            if math.abs(delta_qn) <= 0.01 then
                                sppq = s_chk
                                eppq = e_chk
                                new_sqn = sn.start_qn
                                new_eqn = sn.end_qn
                            else
                                sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, new_sqn) + 0.5)
                                eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, new_eqn) + 0.5)
                            end
                            
                            reaper.MIDI_SetNote(take, target_idx, true, muted, sppq, eppq, chan, new_pitch, vel, true)
                            take_moved_notes[take] = take_moved_notes[take] or {}
                            table.insert(take_moved_notes[take], { idx = target_idx, pitch = new_pitch, chan = chan, sppq = sppq, eppq = eppq })
                            
                            local updated = MidiNote.new({
                                idx = target_idx, pitch = new_pitch, start_qn = new_sqn, end_qn = new_eqn,
                                dur_qn = sn.dur_qn, vel = vel, chan = chan, take = take, item = item or sn.item,
                                track = sn.track, articulation = sn.articulation
                            })
                            local new_k = updated:get_key()
                            new_selected[new_k] = updated
                            
                            local old_k = sn.key or (sn.get_key and sn:get_key()) or string.format("%s_%s_%.3f_%d_%d", tostring(sn.item or item), tostring(take), sn.start_qn, sn.pitch, sn.chan or chan or 0)
                            local old_id = string.format("%s_%s_%.3f", tostring(take), tostring(sn.idx), sn.start_qn)
                            local old_pos = string.format("%s_%.3f_%d", tostring(take), sn.start_qn, sn.pitch)
                            local new_id = string.format("%s_%s_%.3f", tostring(take), tostring(target_idx), new_sqn)
                            local new_pos = string.format("%s_%.3f_%d", tostring(take), new_sqn, new_pitch)
                            if state.note_base_pitch then
                                local bp = state.note_base_pitch[old_k] or state.note_base_pitch[old_id] or state.note_base_pitch[old_pos]
                                if bp then
                                    state.note_base_pitch[new_k] = bp + delta_pitch
                                    state.note_base_pitch[new_id] = bp + delta_pitch
                                    state.note_base_pitch[new_pos] = bp + delta_pitch
                                    state.note_base_pitch[old_k] = nil
                                    state.note_base_pitch[old_id] = nil
                                    state.note_base_pitch[old_pos] = nil
                                end
                            end
                            if state.note_accidentals then
                                local acc = state.note_accidentals[old_k] or state.note_accidentals[old_id] or state.note_accidentals[old_pos]
                                if acc ~= nil then
                                    state.note_accidentals[new_k] = acc
                                    state.note_accidentals[new_id] = acc
                                    state.note_accidentals[new_pos] = acc
                                    state.note_accidentals[old_k] = nil
                                    state.note_accidentals[old_id] = nil
                                    state.note_accidentals[old_pos] = nil
                                end
                            end
                        end
                    end
                end
                for tk, ref_list in pairs(take_moved_notes) do
                    MidiService.resolve_voice_conflicts(tk, ref_list)
                end
                for tk in pairs(affected_takes) do reaper.MIDI_Sort(tk) end
                for it, max_eqn in pairs(items_to_expand) do
                    local it_pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                    local it_start_qn = reaper.TimeMap2_timeToQN(0, it_pos)
                    reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
                    reaper.MIDI_SetItemExtents(it, it_start_qn, max_eqn)
                    reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
                end
                reaper.Undo_EndBlock2(0, "Notator: Move notes", -1)
                reaper.UpdateArrange()
                if MidiService and MidiService.invalidate_cache then
                    MidiService.invalidate_cache()
                end
                
                state.selected_notes = new_selected
                for _, sn in pairs(new_selected) do state.selected_note = sn break end
                state.status_msg = string.format("Moved %d note(s) (Δ %.2f QN, %+d semitones)", #state.drag_selected_snapshot, delta_qn, delta_pitch)
            end
        end
        state.is_dragging = false
        state.drag_note = nil
        state.drag_selected_snapshot = {}
        state.drag_delta_qn = 0
        state.drag_delta_pitch = 0
        state.last_drag_audition_pitch = nil
        AudioPreview.on_mouse_released(state)
    end
    
    -- 3. DYNAMICS DRAG & DROP
    if state.drag_dynamic and reaper.ImGui_IsMouseDragging(ctx, 0, 3.0) and not state.is_resizing_item then
        state.is_dragging_dynamic = true
        state.drag_dyn_target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll())
    end
    
    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.is_dragging_dynamic and state.drag_dynamic then
            local d = state.drag_dynamic
            local orig_qn = state.drag_dyn_start_qn or d.qn
            local target_qn = state.drag_dyn_target_qn or Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
            if d and d.take and reaper.ValidatePtr(d.take, "MediaItem_Take*") then
                local orig_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(d.take, orig_qn) + 0.5)
                local target_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(d.take, target_qn) + 0.5)
                dynamics_engine.move_dynamic_marker(d, d.take, target_ppq, d.track)
                
                -- Move docked hairpins (start or end) along to the new position
                if state.hairpins then
                    local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
                    local trk_guid = d.track and reaper.ValidatePtr(d.track, "MediaTrack*") and reaper.GetTrackGUID(d.track)
                    local hp_updated = false
                    for _, hp in ipairs(state.hairpins) do
                        if not trk_guid or hp.track_guid == trk_guid then
                            if math.abs(hp.start_qn - orig_qn) <= 0.35 then
                                local l_b = HairpinService.get_hairpin_bounds(state, hp, canvas_info and canvas_info.active_tracks_data)
                                hp.start_qn = math.max(l_b, math.min((hp.end_qn or 4.0) - 0.25, target_qn))
                                hp_updated = true
                            end
                            if math.abs((hp.end_qn or (hp.start_qn + 4.0)) - orig_qn) <= 0.35 then
                                local _, r_b = HairpinService.get_hairpin_bounds(state, hp, canvas_info and canvas_info.active_tracks_data)
                                hp.end_qn = math.min(r_b, math.max(hp.start_qn + 0.25, target_qn))
                                hp_updated = true
                            end
                        end
                    end
                    if hp_updated then
                        HairpinService.save_hairpins(state)
                    end
                end
                
                -- Move docked dynamic texts (cresc. / dim. start or end) along to the new position
                if state.dynamic_texts then
                    local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
                    local trk_guid = d.track and reaper.ValidatePtr(d.track, "MediaTrack*") and reaper.GetTrackGUID(d.track)
                    local dt_updated = false
                    for _, dt in ipairs(state.dynamic_texts) do
                        if not trk_guid or dt.track_guid == trk_guid then
                            if math.abs(dt.start_qn - orig_qn) <= 0.35 then
                                local l_b = DynamicTextService.get_bounds(state, dt, canvas_info and canvas_info.active_tracks_data)
                                dt.start_qn = math.max(l_b, math.min((dt.end_qn or 4.0) - 0.25, target_qn))
                                dt_updated = true
                            end
                            if math.abs((dt.end_qn or (dt.start_qn + 4.0)) - orig_qn) <= 0.35 then
                                local _, r_b = DynamicTextService.get_bounds(state, dt, canvas_info and canvas_info.active_tracks_data)
                                dt.end_qn = math.min(r_b, math.max(dt.start_qn + 0.25, target_qn))
                                dt_updated = true
                            end
                        end
                    end
                    if dt_updated then
                        DynamicTextService.save_dynamic_texts(state)
                    end
                end
                
                local active_td = canvas_info and canvas_info.active_tracks_data
                dynamics_engine.smart_reblend_all(state, midi_service, active_td, d.take)
                if MidiService and MidiService.invalidate_cache then
                    MidiService.invalidate_cache()
                end
                state.status_msg = string.format("Moved dynamic %s to measure %.2f & re-blended track", d.label, (target_qn / qn_per_measure) + 1)
            end
        end
        state.is_dragging_dynamic = false
        state.drag_dynamic = nil
        state.drag_dyn_start_qn = nil
        state.drag_dyn_target_qn = nil
    end

    -- 3b. ARTICULATION DRAG & DROP
    if state.drag_articulation and reaper.ImGui_IsMouseDragging(ctx, 0, 3.0) and not state.is_resizing_item then
        state.is_dragging_articulation = true
        state.drag_art_target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll())
    end
    
    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.is_dragging_articulation and state.drag_articulation then
            local art = state.drag_articulation
            local target_qn = state.drag_art_target_qn or Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
            if art and art.take and reaper.ValidatePtr(art.take, "MediaItem_Take*") then
                local it = reaper.GetMediaItemTake_Item(art.take)
                if it then
                    local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                    local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                    local is_qn = reaper.TimeMap2_timeToQN(0, ipos)
                    local ie_qn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                    target_qn = math.max(is_qn, math.min(ie_qn - 0.05, target_qn))
                end
                local target_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(art.take, target_qn) + 0.5)
                midi_service.move_articulation(art, art.take, target_ppq, art.track)
                state.status_msg = string.format("Moved articulation %s to measure %.2f", art.label or ("PC " .. tostring(art.pc)), (target_qn / qn_per_measure) + 1)
            end
        end
        state.is_dragging_articulation = false
        state.drag_articulation = nil
        state.drag_art_target_qn = nil
    end
    
    -- 3c. TEMPO MARKER & DUAL-HANDLE DRAG & DROP
    if reaper.ImGui_IsMouseClicked(ctx, 0) and state.hovered_tempo_marker and not state.is_resizing_item then
        state.selected_tempo_marker = state.hovered_tempo_marker
        state.drag_tempo_marker = state.hovered_tempo_marker
        state.drag_tempo_handle = state.hovered_tempo_handle or "start"
        state.drag_tempo_start_x = mouse_x
        state.drag_tempo_orig_start = state.hovered_tempo_marker.start_qn
        state.drag_tempo_orig_end = state.hovered_tempo_marker.end_qn or (state.hovered_tempo_marker.start_qn + 4.0)
        state.drag_tempo_last_qn = state.hovered_tempo_marker.start_qn
    end
    
    if state.drag_tempo_marker and reaper.ImGui_IsMouseDragging(ctx, 0, 2.0) and not state.is_resizing_item then
        state.is_dragging_tempo = true
        local snap_grid = is_shift and 0.001 or state.grid_qn
        local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
        
        if state.drag_tempo_handle == "start" then
            if state.drag_tempo_marker.type == "absolute" then
                -- Fixed tempo markers can be freely moved across the entire length of the timeline!
                state.drag_tempo_target_qn = math.max(0.0, target_qn)
            else
                local max_start = (state.drag_tempo_marker.end_qn or 4.0) - 0.25
                state.drag_tempo_target_qn = math.min(max_start, math.max(0.0, target_qn))
            end
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
        elseif state.drag_tempo_handle == "end" then
            local min_end = (state.drag_tempo_marker.start_qn or 0.0) + 0.25
            state.drag_tempo_target_qn = math.max(min_end, target_qn)
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
        elseif state.drag_tempo_handle == "body" then
            if state.drag_tempo_marker.type == "absolute" then
                state.drag_tempo_target_qn = math.max(0.0, target_qn)
            else
                local start_qn_at_click = Engraver.canvas_x_to_qn(state.drag_tempo_start_x or mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
                state.drag_tempo_delta_qn = target_qn - start_qn_at_click
            end
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
        end
        
        -- Live synchronization of REAPER tempo map on every change during drag
        local orig_s = state.drag_tempo_orig_start
        local orig_e = state.drag_tempo_orig_end
        local current_drag_val = (state.drag_tempo_handle == "body") and state.drag_tempo_delta_qn or state.drag_tempo_target_qn
        if current_drag_val and current_drag_val ~= state.last_drag_tempo_val then
            state.last_drag_tempo_val = current_drag_val
            local TempoService = require("services.tempo_service")
            local tm = state.drag_tempo_marker
            if tm.type == "absolute" then
                local prev_qn = state.drag_tempo_last_qn or orig_s
                state.drag_tempo_last_qn = state.drag_tempo_target_qn
                TempoService.move_absolute_tempo_marker(state, tm, state.drag_tempo_target_qn, prev_qn)
            else
                if state.drag_tempo_handle == "start" and state.drag_tempo_target_qn then
                    TempoService.update_marker_bounds(state, tm, state.drag_tempo_target_qn, nil, orig_s, orig_e)
                elseif state.drag_tempo_handle == "end" and state.drag_tempo_target_qn then
                    TempoService.update_marker_bounds(state, tm, nil, state.drag_tempo_target_qn, orig_s, orig_e)
                elseif state.drag_tempo_handle == "body" and state.drag_tempo_delta_qn then
                    local span = (orig_e or (orig_s + 4.0)) - orig_s
                    local new_s = math.max(0.0, orig_s + state.drag_tempo_delta_qn)
                    TempoService.update_marker_bounds(state, tm, new_s, new_s + span, orig_s, orig_e)
                end
            end
        end
    end
    
    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.is_dragging_tempo and state.drag_tempo_marker then
            local tm = state.drag_tempo_marker
            local TempoService = require("services.tempo_service")
            local orig_s = state.drag_tempo_orig_start
            local orig_e = state.drag_tempo_orig_end
            if tm.type == "absolute" then
                local prev_qn = state.drag_tempo_last_qn or orig_s
                local final_qn = state.drag_tempo_target_qn or orig_s
                TempoService.move_absolute_tempo_marker(state, tm, final_qn, prev_qn)
            else
                if state.drag_tempo_handle == "start" and state.drag_tempo_target_qn then
                    TempoService.update_marker_bounds(state, tm, state.drag_tempo_target_qn, nil, orig_s, orig_e)
                elseif state.drag_tempo_handle == "end" and state.drag_tempo_target_qn then
                    TempoService.update_marker_bounds(state, tm, nil, state.drag_tempo_target_qn, orig_s, orig_e)
                elseif state.drag_tempo_handle == "body" and state.drag_tempo_delta_qn then
                    local span = (orig_e or (orig_s + 4.0)) - orig_s
                    local new_s = math.max(0.0, orig_s + state.drag_tempo_delta_qn)
                    TempoService.update_marker_bounds(state, tm, new_s, new_s + span, orig_s, orig_e)
                end
            end
            TempoService.clean_all_duplicate_tempo_markers(state)
            TempoService.save_markers(state)
            reaper.Undo_OnStateChange2(0, "Notator: Adjust Tempo Marker")
            state.status_msg = string.format("Adjusted tempo '%s' (measure %.2f - %.2f)", tm:get_display_text(), (tm.start_qn / qn_per_measure) + 1, ((tm.end_qn or tm.start_qn) / qn_per_measure) + 1)
        end
        state.is_dragging_tempo = false
        state.drag_tempo_marker = nil
        state.drag_tempo_handle = nil
        state.drag_tempo_target_qn = nil
        state.drag_tempo_delta_qn = nil
        state.drag_tempo_orig_start = nil
        state.drag_tempo_orig_end = nil
        state.drag_tempo_last_qn = nil
        state.last_drag_tempo_val = nil
    end
    
    -- 3d. OTTAVA / OCTAVE LINE DUAL-HANDLE DRAG & DROP
    local OctaveService = require("services.octave_service")
    if reaper.ImGui_IsMouseClicked(ctx, 0) and state.hovered_octave_line and not state.is_resizing_item then
        state.selected_octave_line = state.hovered_octave_line
        state.drag_octave_line = state.hovered_octave_line
        state.drag_octave_handle = state.hovered_octave_handle or "start"
        state.drag_octave_start_x = mouse_x
        state.drag_octave_orig_start = state.hovered_octave_line.start_qn
        state.drag_octave_orig_end = state.hovered_octave_line.end_qn or (state.hovered_octave_line.start_qn + 4.0)
    end
    
    if state.drag_octave_line and reaper.ImGui_IsMouseDragging(ctx, 0, 2.0) and not state.is_resizing_item then
        state.is_dragging_octave = true
        local snap_grid = is_shift and 0.001 or state.grid_qn
        local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
        
        local oline = state.drag_octave_line
        local orig_s = state.drag_octave_orig_start
        local orig_e = state.drag_octave_orig_end
        
        if state.drag_octave_handle == "start" then
            local max_s = (orig_e or 4.0) - 0.25
            local new_s = math.min(max_s, math.max(0.0, target_qn))
            oline.start_qn = new_s
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
        elseif state.drag_octave_handle == "end" then
            local min_e = (oline.start_qn or 0.0) + 0.25
            local new_e = math.max(min_e, target_qn)
            oline.end_qn = new_e
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
        elseif state.drag_octave_handle == "body" then
            local start_qn_at_click = Engraver.canvas_x_to_qn(state.drag_octave_start_x or mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
            local delta_qn = target_qn - start_qn_at_click
            local span = (orig_e or (orig_s + 4.0)) - orig_s
            local new_s = math.max(0.0, orig_s + delta_qn)
            oline.start_qn = new_s
            oline.end_qn = new_s + span
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
        end
    end
    
    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.is_dragging_octave and state.drag_octave_line then
            local oline = state.drag_octave_line
            local orig_s = state.drag_octave_orig_start or oline.start_qn
            local orig_e = state.drag_octave_orig_end or oline.end_qn
            local new_s = oline.start_qn
            local new_e = oline.end_qn
            
            if (math.abs(new_s - orig_s) > 0.01 or math.abs(new_e - orig_e) > 0.01) then
                OctaveService.resize_octave_line(state, oline, orig_s, orig_e, new_s, new_e)
            else
                OctaveService.save_lines(state)
            end
            reaper.Undo_OnStateChange2(0, "Notator: Adjust Octave Line")
            state.is_dragging_octave = false
            state.drag_octave_line = nil
            state.drag_octave_handle = nil
            state.drag_octave_orig_start = nil
            state.drag_octave_orig_end = nil
        end
    end
    
    -- 3e. HAIRPIN DUAL-HANDLE DRAG & DROP (Crescendo < & Decrescendo >)
    if reaper.ImGui_IsMouseClicked(ctx, 0) and state.hovered_hairpin and not state.is_resizing_item then
        state.selected_hairpin = state.hovered_hairpin
        state.drag_hairpin = state.hovered_hairpin
        state.drag_hairpin_handle = state.hovered_hairpin_handle or "start"
        state.drag_hairpin_start_x = mouse_x
        state.drag_hairpin_orig_start = state.hovered_hairpin.start_qn
        state.drag_hairpin_orig_end = state.hovered_hairpin.end_qn or (state.hovered_hairpin.start_qn + 4.0)
        state.drag_hairpin_min_start = state.hovered_hairpin.start_qn
        state.drag_hairpin_max_end = state.hovered_hairpin.end_qn or (state.hovered_hairpin.start_qn + 4.0)
        state:clear_selection()
        state.selected_hairpin = state.drag_hairpin
        state.marquee_potential = false
        state.marquee_active = false
    end
    
    if state.drag_hairpin and reaper.ImGui_IsMouseDragging(ctx, 0, 2.0) and not state.is_resizing_item then
        state.is_dragging_hairpin = true
        state.marquee_potential = false
        state.marquee_active = false
        local snap_grid = is_shift and 0.001 or state.grid_qn
        local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
        local hp = state.drag_hairpin
        local orig_s = state.drag_hairpin_orig_start
        local orig_e = state.drag_hairpin_orig_end
        
        -- Determine strict physical bounds: hairpins bump against neighbors/dynamics and cannot scale over each other
        local l_bound, r_bound = HairpinService.get_hairpin_bounds(state, hp, canvas_info.active_tracks_data)
        
        if state.drag_hairpin_handle == "start" then
            local max_s = (orig_e or hp.end_qn or 4.0) - 0.25
            local new_s = target_qn
            if not is_shift then
                -- Snapping to left bound (prev_hp.end_qn or prev_dyn.qn)
                if math.abs(new_s - l_bound) <= 0.35 or new_s <= l_bound then
                    new_s = l_bound
                end
            end
            -- Strict clamping: must NEVER be smaller than l_bound or greater than max_s!
            new_s = math.max(l_bound, math.min(max_s, new_s))
            state.drag_hairpin_target_qn = new_s
            hp.start_qn = new_s
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
            
        elseif state.drag_hairpin_handle == "end" then
            local min_e = (orig_s or hp.start_qn or 0.0) + 0.25
            local new_e = target_qn
            if not is_shift then
                -- Snapping to right bound (next_hp.start_qn or next_dyn.qn)
                if math.abs(new_e - r_bound) <= 0.35 or new_e >= r_bound then
                    new_e = r_bound
                end
            end
            -- Strict clamping: must NEVER be greater than r_bound or smaller than min_e!
            new_e = math.min(r_bound, math.max(min_e, new_e))
            state.drag_hairpin_target_qn = new_e
            hp.end_qn = new_e
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
            
        elseif state.drag_hairpin_handle == "body" then
            local start_qn_at_click = Engraver.canvas_x_to_qn(state.drag_hairpin_start_x or mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
            local delta_qn = target_qn - start_qn_at_click
            state.drag_hairpin_delta_qn = delta_qn
            local span = (orig_e or (orig_s + 4.0)) - orig_s
            local new_s = orig_s + delta_qn
            local max_body_s = math.max(l_bound, r_bound - span)
            new_s = math.max(l_bound, math.min(max_body_s, new_s))
            if not is_shift then
                if math.abs(new_s - l_bound) <= 0.35 then
                    new_s = l_bound
                elseif math.abs((new_s + span) - r_bound) <= 0.35 then
                    new_s = r_bound - span
                end
            end
            hp.start_qn = new_s
            hp.end_qn = new_s + span
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
        end
        state.drag_hairpin_min_start = math.min(state.drag_hairpin_min_start or orig_s or hp.start_qn, hp.start_qn)
        state.drag_hairpin_max_end = math.max(state.drag_hairpin_max_end or orig_e or hp.end_qn, hp.end_qn)
        local take = HairpinService.find_take_for_track(hp.track_guid, canvas_info.active_tracks_data)
        local clear_s_ppq = (take and state.drag_hairpin_min_start) and math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, state.drag_hairpin_min_start) + 0.5)
        local clear_e_ppq = (take and state.drag_hairpin_max_end) and math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, state.drag_hairpin_max_end) + 0.5)
        HairpinService.save_hairpins(state)
        HairpinService.apply_hairpin_cc(state, hp, midi_service, canvas_info.active_tracks_data, clear_s_ppq, clear_e_ppq)
    end
    
    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.is_dragging_hairpin and state.drag_hairpin then
            local hp = state.drag_hairpin
            local min_s = state.drag_hairpin_min_start or state.drag_hairpin_orig_start or hp.start_qn
            local max_e = state.drag_hairpin_max_end or state.drag_hairpin_orig_end or hp.end_qn
            local take = HairpinService.find_take_for_track(hp.track_guid, canvas_info.active_tracks_data)
            local clear_s_ppq = (take and min_s) and math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, min_s) + 0.5)
            local clear_e_ppq = (take and max_e) and math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, max_e) + 0.5)
            HairpinService.save_hairpins(state)
            HairpinService.resolve_all_track_hairpins(state, hp.track_guid, canvas_info.active_tracks_data)
            
            -- Update all hairpins on this track chronologically (complete seamlessness without artifacts)
            local track_hps = {}
            if state.hairpins then
                for _, thp in ipairs(state.hairpins) do
                    if thp.track_guid == hp.track_guid then
                        table.insert(track_hps, thp)
                    end
                end
            end
            table.sort(track_hps, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
            for _, thp in ipairs(track_hps) do
                local s_ppq = (thp.id == hp.id) and clear_s_ppq or nil
                local e_ppq = (thp.id == hp.id) and clear_e_ppq or nil
                HairpinService.apply_hairpin_cc(state, thp, midi_service, canvas_info.active_tracks_data, s_ppq, e_ppq)
            end
            
            -- Also refresh remaining dynamic texts on the same track
            if state.dynamic_texts then
                local track_dts = {}
                for _, tdt in ipairs(state.dynamic_texts) do
                    if tdt.track_guid == hp.track_guid then
                        table.insert(track_dts, tdt)
                    end
                end
                table.sort(track_dts, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
                for _, tdt in ipairs(track_dts) do
                    DynamicTextService.apply_cc(state, tdt, midi_service, canvas_info.active_tracks_data)
                end
            end
            
            local bpi = qn_per_measure or 4.0
            reaper.Undo_OnStateChange2(0, "Notator: Adjust Hairpin")
            state.status_msg = string.format("Adjusted %s (measure %.2f - %.2f)", hp:get_display_name(), (hp.start_qn / bpi) + 1, (hp.end_qn / bpi) + 1)
        end
        state.is_dragging_hairpin = false
        state.drag_hairpin = nil
        state.drag_hairpin_handle = nil
        state.drag_hairpin_target_qn = nil
        state.drag_hairpin_delta_qn = nil
        state.drag_hairpin_orig_start = nil
        state.drag_hairpin_orig_end = nil
        state.drag_hairpin_min_start = nil
        state.drag_hairpin_max_end = nil
    end
    
    -- 2g. DYNAMIC TEXT DRAG & DROP (Scale & move cresc. & dim. text tags)
    if reaper.ImGui_IsMouseClicked(ctx, 0) and state.hovered_dynamic_text and not state.is_resizing_item then
        state.selected_dynamic_text = state.hovered_dynamic_text
        state.drag_dynamic_text = state.hovered_dynamic_text
        state.drag_dynamic_text_handle = state.hovered_dynamic_text_handle or "start"
        state.drag_dynamic_text_start_x = mouse_x
        state.drag_dynamic_text_orig_start = state.hovered_dynamic_text.start_qn
        state.drag_dynamic_text_orig_end = state.hovered_dynamic_text.end_qn
        state.drag_dynamic_text_min_start = state.hovered_dynamic_text.start_qn
        state.drag_dynamic_text_max_end = state.hovered_dynamic_text.end_qn
        state:clear_selection()
        state.selected_dynamic_text = state.drag_dynamic_text
        state.marquee_potential = false
        state.marquee_active = false
    end
    
    if state.drag_dynamic_text and reaper.ImGui_IsMouseDragging(ctx, 0, 2.0) and not state.is_resizing_item then
        state.is_dragging_dynamic_text = true
        state.marquee_potential = false
        state.marquee_active = false
        local snap_grid = is_shift and 0.001 or state.grid_qn
        local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
        local dt = state.drag_dynamic_text
        local orig_s = state.drag_dynamic_text_orig_start
        local orig_e = state.drag_dynamic_text_orig_end
        
        -- Determine strict physical bounds (markers, hairpins, other dynamic texts)
        local l_bound, r_bound = DynamicTextService.get_bounds(state, dt, canvas_info.active_tracks_data)
        
        if state.drag_dynamic_text_handle == "start" then
            local max_s = (orig_e or dt.end_qn or 4.0) - 0.25
            local new_s = target_qn
            if not is_shift then
                if math.abs(new_s - l_bound) <= 0.35 or new_s <= l_bound then
                    new_s = l_bound
                end
            end
            new_s = math.max(l_bound, math.min(max_s, new_s))
            state.drag_dynamic_text_target_qn = new_s
            dt.start_qn = new_s
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
            
        elseif state.drag_dynamic_text_handle == "end" then
            local min_e = (orig_s or dt.start_qn or 0.0) + 0.25
            local new_e = target_qn
            if not is_shift then
                if math.abs(new_e - r_bound) <= 0.35 or new_e >= r_bound then
                    new_e = r_bound
                end
            end
            new_e = math.min(r_bound, math.max(min_e, new_e))
            state.drag_dynamic_text_target_qn = new_e
            dt.end_qn = new_e
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
            
        elseif state.drag_dynamic_text_handle == "body" then
            local start_qn_at_click = Engraver.canvas_x_to_qn(state.drag_dynamic_text_start_x or mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
            local delta_qn = target_qn - start_qn_at_click
            state.drag_dynamic_text_delta_qn = delta_qn
            local span = (orig_e or (orig_s + 4.0)) - orig_s
            local new_s = orig_s + delta_qn
            local max_body_s = math.max(l_bound, r_bound - span)
            new_s = math.max(l_bound, math.min(max_body_s, new_s))
            if not is_shift then
                if math.abs(new_s - l_bound) <= 0.35 then
                    new_s = l_bound
                elseif math.abs((new_s + span) - r_bound) <= 0.35 then
                    new_s = r_bound - span
                end
            end
            dt.start_qn = new_s
            dt.end_qn = new_s + span
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
        end
        
        state.drag_dynamic_text_min_start = math.min(state.drag_dynamic_text_min_start or orig_s or dt.start_qn, dt.start_qn)
        state.drag_dynamic_text_max_end = math.max(state.drag_dynamic_text_max_end or orig_e or dt.end_qn, dt.end_qn)
        
        local take = DynamicTextService.find_take_for_track(dt.track_guid, canvas_info.active_tracks_data)
        local clear_s_ppq = (take and state.drag_dynamic_text_min_start) and math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, state.drag_dynamic_text_min_start) + 0.5)
        local clear_e_ppq = (take and state.drag_dynamic_text_max_end) and math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, state.drag_dynamic_text_max_end) + 0.5)
        
        DynamicTextService.save_dynamic_texts(state)
        DynamicTextService.apply_cc(state, dt, midi_service, canvas_info.active_tracks_data, clear_s_ppq, clear_e_ppq)
    end
    
    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.is_dragging_dynamic_text and state.drag_dynamic_text then
            local dt = state.drag_dynamic_text
            local min_s = state.drag_dynamic_text_min_start or state.drag_dynamic_text_orig_start or dt.start_qn
            local max_e = state.drag_dynamic_text_max_end or state.drag_dynamic_text_orig_end or dt.end_qn
            local take = DynamicTextService.find_take_for_track(dt.track_guid, canvas_info.active_tracks_data)
            local clear_s_ppq = (take and min_s) and math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, min_s) + 0.5)
            local clear_e_ppq = (take and max_e) and math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, max_e) + 0.5)
            DynamicTextService.save_dynamic_texts(state)
            DynamicTextService.apply_cc(state, dt, midi_service, canvas_info.active_tracks_data, clear_s_ppq, clear_e_ppq)
            
            -- Also refresh remaining hairpins on the same track
            if state.hairpins then
                local track_hps = {}
                for _, thp in ipairs(state.hairpins) do
                    if thp.track_guid == dt.track_guid then
                        table.insert(track_hps, thp)
                    end
                end
                table.sort(track_hps, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
                for _, thp in ipairs(track_hps) do
                    HairpinService.apply_hairpin_cc(state, thp, midi_service, canvas_info.active_tracks_data)
                end
            end
            
            local bpi = qn_per_measure or 4.0
            reaper.Undo_OnStateChange2(0, "Notator: Adjust Dynamic Text")
            state.status_msg = string.format("Adjusted text dynamic '%s' (measure %.2f - %.2f)", dt.text, (dt.start_qn / bpi) + 1, (dt.end_qn / bpi) + 1)
        end
        state.is_dragging_dynamic_text = false
        state.drag_dynamic_text = nil
        state.drag_dynamic_text_handle = nil
        state.drag_dynamic_text_target_qn = nil
        state.drag_dynamic_text_delta_qn = nil
        state.drag_dynamic_text_orig_start = nil
        state.drag_dynamic_text_orig_end = nil
        state.drag_dynamic_text_max_end = nil
        state.drag_dynamic_text_min_start = nil
    end
    
    -- 2h. HOLDING / SUSTAIN PEDAL DRAG & DROP (Scale & move pedal lines & retakes/pauses)
    local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
    if reaper.ImGui_IsMouseClicked(ctx, 0) and state.hovered_pedal and not state.is_resizing_item then
        state.selected_pedal = state.hovered_pedal
        state.drag_pedal = state.hovered_pedal
        state.drag_pedal_handle = state.hovered_pedal_handle or "start"
        state.drag_pedal_start_x = mouse_x
        state.drag_pedal_orig_start = state.hovered_pedal.start_qn
        state.drag_pedal_orig_end = state.hovered_pedal.end_qn
        
        if state.drag_pedal_handle:find("^pause_") then
            local pid = state.drag_pedal_handle:sub(7)
            for _, p in ipairs(state.hovered_pedal.pauses or {}) do
                if p.id == pid then
                    state.drag_pedal_pause_orig_qn = p.qn
                    break
                end
            end
        end
        
        state:clear_selection()
        state.selected_pedal = state.drag_pedal
        state.marquee_potential = false
        state.marquee_active = false
    end
    
    if state.drag_pedal and reaper.ImGui_IsMouseDragging(ctx, 0, 2.0) and not state.is_resizing_item then
        state.is_dragging_pedal = true
        state.marquee_potential = false
        state.marquee_active = false
        local snap_grid = is_shift and 0.001 or state.grid_qn
        local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
        local pm = state.drag_pedal
        local orig_s = state.drag_pedal_orig_start
        local orig_e = state.drag_pedal_orig_end
        
        if state.drag_pedal_handle == "start" then
            local max_s = (orig_e or pm.end_qn or 4.0) - 0.25
            local new_s = math.max(0, math.min(max_s, target_qn))
            state.drag_pedal_target_qn = new_s
            pm.start_qn = new_s
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
            
        elseif state.drag_pedal_handle == "end" then
            local min_e = (orig_s or pm.start_qn or 0.0) + 0.25
            local new_e = math.max(min_e, target_qn)
            state.drag_pedal_target_qn = new_e
            pm.end_qn = new_e
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
            
        elseif state.drag_pedal_handle == "body" then
            local start_qn_at_click = Engraver.canvas_x_to_qn(state.drag_pedal_start_x or mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
            local delta_qn = target_qn - start_qn_at_click
            state.drag_pedal_delta_qn = delta_qn
            local span = (orig_e or (orig_s + 4.0)) - orig_s
            local new_s = math.max(0, orig_s + delta_qn)
            local shift_diff = new_s - pm.start_qn
            pm.start_qn = new_s
            pm.end_qn = new_s + span
            
            for _, p in ipairs(pm.pauses or {}) do
                p.qn = math.max(new_s + 0.05, math.min(pm.end_qn - 0.05, p.qn + shift_diff))
            end
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
            
        elseif state.drag_pedal_handle:find("^pause_") then
            local pid = state.drag_pedal_handle:sub(7)
            local min_pqn = pm.start_qn + 0.1
            local max_pqn = pm.end_qn - 0.1
            local new_pqn = math.max(min_pqn, math.min(max_pqn, target_qn))
            state.drag_pedal_target_qn = new_pqn
            for _, p in ipairs(pm.pauses or {}) do
                if p.id == pid then
                    p.qn = new_pqn
                    break
                end
            end
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
        end
    end
    
    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.is_dragging_pedal and state.drag_pedal then
            local pm = state.drag_pedal
            local orig_s = state.drag_pedal_orig_start or pm.start_qn
            local orig_e = state.drag_pedal_orig_end or pm.end_qn
            local clear_s = math.min(orig_s, pm.start_qn)
            local clear_e = math.max(orig_e, pm.end_qn)
            
            -- Filter/clamp pauses outside new range
            local kept_pauses = {}
            for _, p in ipairs(pm.pauses or {}) do
                if p.qn > pm.start_qn and p.qn < pm.end_qn then
                    table.insert(kept_pauses, p)
                end
            end
            pm.pauses = kept_pauses
            
            PedalService.save_pedals(state)
            if pm.apply_cc then
                PedalService.apply_cc(state, pm, midi_service, canvas_info.active_tracks_data, clear_s, clear_e)
            end
            local bpi = qn_per_measure or 4.0
            reaper.Undo_OnStateChange2(0, "Notator: Adjust Sustain Pedal")
            state.status_msg = string.format("Adjusted pedal marking (measure %.2f - %.2f)", (pm.start_qn / bpi) + 1, (pm.end_qn / bpi) + 1)
        end
        state.is_dragging_pedal = false
        state.drag_pedal = nil
        state.drag_pedal_handle = nil
        state.drag_pedal_target_qn = nil
        state.drag_pedal_delta_qn = nil
        state.drag_pedal_orig_start = nil
        state.drag_pedal_orig_end = nil
        state.drag_pedal_pause_orig_qn = nil
    end
    
    -- 2i. Text Items: Drag & Drop (X = QN, Y = Offset)
    if state.hovered_text_item and reaper.ImGui_IsMouseClicked(ctx, 0) and not is_ctrl and not is_alt and not state.is_resizing_item then
        state.drag_text_item = state.hovered_text_item
        state.drag_text_start_mouse_x = mouse_x
        state.drag_text_start_mouse_y = mouse_y
        state.drag_text_orig_qn = state.hovered_text_item.qn
        state.drag_text_orig_offset_y = state.hovered_text_item.offset_y or 32.0
        state.drag_text_target_qn = state.drag_text_orig_qn
        state.drag_text_target_offset_y = state.drag_text_orig_offset_y
        state:clear_selection()
        state.selected_text_item = state.drag_text_item
        state.marquee_potential = false
        state.marquee_active = false
    end

    if state.drag_text_item and reaper.ImGui_IsMouseDragging(ctx, 0, 2.0) and not state.is_resizing_item then
        state.is_dragging_text_item = true
        state.marquee_potential = false
        state.marquee_active = false
        
        local snap_grid = is_shift and 0.001 or state.grid_qn
        local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
        target_qn = math.max(0, target_qn)
        
        local dy = (mouse_y - (state.drag_text_start_mouse_y or mouse_y)) / s
        local target_offset_y = (state.drag_text_orig_offset_y or 32.0) + dy
        
        state.drag_text_target_qn = target_qn
        state.drag_text_target_offset_y = target_offset_y
        
        state.drag_text_item.qn = target_qn
        state.drag_text_item.offset_y = target_offset_y
        
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end

    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.is_dragging_text_item and state.drag_text_item then
            local TextItemService = require("services.text_item_service")
            TextItemService.save_text_items(state)
            local bpi = qn_per_measure or 4.0
            reaper.Undo_OnStateChange2(0, "Notator: Move Text Item")
            state.status_msg = string.format("Moved Text Item: measure %.2f (Y offset: %.0f px)", (state.drag_text_item.qn / bpi) + 1, state.drag_text_item.offset_y or 32.0)
        end
        state.is_dragging_text_item = false
        state.drag_text_item = nil
        state.drag_text_target_qn = nil
        state.drag_text_target_offset_y = nil
        state.drag_text_orig_qn = nil
        state.drag_text_orig_offset_y = nil
        state.drag_text_start_mouse_x = nil
        state.drag_text_start_mouse_y = nil
    end

    -- 3b. WRITE NOTES / MOUSE DRAW MODE: Note entry via mouse click
    if state.input_mode_type == "draw" and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 0) and not is_ctrl and not is_alt and not state.is_resizing_item then
        local prev = state.draw_preview
        if prev and prev.track and reaper.ValidatePtr(prev.track, "MediaTrack*") and prev.qn and prev.pitch then
            state.focused_track = prev.track
            reaper.SetOnlyTrackSelected(prev.track)
            state.last_reaper_sel_track = prev.track
            
            local dur = state.active_dur or 1.0
            if state.is_dotted then dur = dur * 1.5 end
            if state.get_tuplet_factor then
                dur = dur * state:get_tuplet_factor()
            elseif state.is_triplet then
                dur = dur * (2.0 / 3.0)
            end
            
            local n_obj = midi_service.insert_note_at_qn(state, prev.qn, prev.pitch, dur)
            if n_obj then
                AudioPreview.play_note(state, prev.pitch, 96, 0, prev.track, prev.qn)
                local bpi = qn_per_measure or 4.0
                local p_info = Constants.PITCH_MAP and Constants.PITCH_MAP[prev.pitch % 12]
                local p_name = p_info and p_info.name or "C"
                local p_oct = math.floor(prev.pitch / 12) - 1
                local dur_str = state.dur_label or "1/4"
                if state.is_dotted then dur_str = dur_str .. "." end
                if state.tuplet_type then
                    dur_str = dur_str .. " (T" .. tostring(state.tuplet_type) .. ")"
                elseif state.is_triplet then
                    dur_str = dur_str .. "T"
                end
                state.status_msg = string.format("Inserted note: %s%d [%s] at measure %.2f (%s)", p_name, p_oct, dur_str, (prev.qn / bpi) + 1, prev.trk and prev.trk.name or "Track")
                
                -- Move edit cursor to the end of the newly placed note
                local next_qn = prev.qn + dur
                reaper.SetEditCurPos2(0, reaper.TimeMap2_QNToTime(0, next_qn), true, false)
            end
            return
        end
    end

    -- 4. CLICK IN EMPTY SPACE: Sets REAPER edit cursor & focuses track (or prepares Ctrl+marquee)
    local in_chord_lane = (state.show_chord_lane ~= false and canvas_info.canvas_p0_y and mouse_y >= canvas_info.canvas_p0_y and mouse_y <= (canvas_info.canvas_p0_y + 42 * s))
    local empty_click = (state.input_mode_type ~= "draw") and reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 0)
                        and not state.hovered_note and not state.hovered_dynamic and not state.hovered_articulation and not state.hovered_item_edge and not state.hovered_tempo_marker and not state.hovered_octave_line and not state.hovered_hairpin and not state.hovered_dynamic_text and not state.hovered_pedal and not state.hovered_text_item and not state.hovered_chord_item and not in_chord_lane
                        
    if empty_click then
        state.drag_note = nil
        state.is_dragging = false
        state.drag_selected_snapshot = {}
        state.drag_delta_qn = 0
        state.drag_delta_pitch = 0
        
        if is_ctrl then
            -- When Ctrl key is held: Retain existing selection & prepare additive marquee
            state.marquee_start_x = mouse_x
            state.marquee_start_y = mouse_y
            state.marquee_cur_x = mouse_x
            state.marquee_cur_y = mouse_y
            state.marquee_potential = true
            state.marquee_active = false
            state.marquee_add_mode = true
            state.marquee_initial_selection = {}
            for k, sn in pairs(state.selected_notes) do
                state.marquee_initial_selection[k] = sn
            end
            state.marquee_initial_art_selection = {}
            for k, sa in pairs(state.selected_articulations or {}) do
                state.marquee_initial_art_selection[k] = sa
            end
        else
            -- Normal click without Ctrl: Set edit cursor to clicked QN position
            local click_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
            local click_time = reaper.TimeMap2_QNToTime(0, click_qn)
            reaper.SetEditCurPos2(0, click_time, true, false)
            
            -- Determine clicked track and focus it
            local focused_name = "Track"
            if canvas_info.active_tracks_data then
                for _, tdata in ipairs(canvas_info.active_tracks_data) do
                    if tdata.band_y0 and tdata.band_y1 and mouse_y >= tdata.band_y0 and mouse_y <= tdata.band_y1 then
                        if tdata.track and reaper.ValidatePtr(tdata.track, "MediaTrack*") then
                            state.focused_track = tdata.track
                            reaper.SetOnlyTrackSelected(tdata.track)
                            state.last_reaper_sel_track = tdata.track
                            state.jump_to_item = nil
                            focused_name = tdata.name or "Track"
                        end
                        break
                    end
                end
            end
            
            -- Clear selection
            state:clear_selection()
            state:clear_articulation_selection()
            state.selected_dynamic = nil
            state.selected_tempo_marker = nil
            state.selected_octave_line = nil
            state.selected_hairpin = nil
            state.selected_dynamic_text = nil
            state.selected_pedal = nil
            state.selected_text_item = nil
            state.selected_chord_item = nil
            midi_service.sync_selection_to_reaper(state, canvas_info.active_tracks_data)
            
            -- Prepare marquee selection (in case dragging occurs after click)
            state.marquee_start_x = mouse_x
            state.marquee_start_y = mouse_y
            state.marquee_cur_x = mouse_x
            state.marquee_cur_y = mouse_y
            state.marquee_potential = true
            state.marquee_active = false
            state.marquee_add_mode = false
            state.marquee_initial_selection = {}
            state.marquee_initial_art_selection = {}
            
            local bpi = qn_per_measure or 4.0
            state.status_msg = string.format("Cursor set to measure %.2f [%s]", (click_qn / bpi) + 1, focused_name)
        end
    end
    
    -- 5. MARQUEE SELECTION RECTANGLE (Activate only upon real drag > 4 pixels)
    if state.marquee_potential and reaper.ImGui_IsMouseDragging(ctx, 0, 4.0)
       and not state.is_resizing_item 
       and not state.is_dragging 
       and not state.is_dragging_dynamic 
       and not state.is_dragging_dynamic_text
       and not state.is_dragging_pedal
       and not state.is_dragging_hairpin 
       and not state.is_dragging_octave 
       and not state.is_dragging_tempo 
       and not state.is_dragging_articulation
       and not state.is_dragging_text_item then
        state.marquee_active = true
        state.drag_note = nil
        state.is_dragging = false
        state.drag_selected_snapshot = {}
        state.drag_delta_qn = 0
        state.drag_delta_pitch = 0
    end
    
    if state.marquee_active and reaper.ImGui_IsMouseDown(ctx, 0) then
        state.marquee_cur_x = mouse_x
        state.marquee_cur_y = mouse_y
        
        local x0 = math.min(state.marquee_start_x, state.marquee_cur_x)
        local x1 = math.max(state.marquee_start_x, state.marquee_cur_x)
        local y0 = math.min(state.marquee_start_y, state.marquee_cur_y)
        local y1 = math.max(state.marquee_start_y, state.marquee_cur_y)
        
        state.selected_notes = {}
        state.selected_note = nil
        state.selected_articulations = {}
        state.selected_articulation = nil

        if (state.marquee_add_mode or is_ctrl) and state.marquee_initial_selection then
            for k, sn in pairs(state.marquee_initial_selection) do
                state.selected_notes[k] = sn
                state.selected_note = sn
            end
        end
        if (state.marquee_add_mode or is_ctrl) and state.marquee_initial_art_selection then
            for k, sa in pairs(state.marquee_initial_art_selection) do
                state.selected_articulations[k] = sa
                state.selected_articulation = sa
            end
        end

        for _, rd in ipairs(canvas_info.all_note_render_data or {}) do
            if rd.nx >= x0 and rd.nx <= x1 and rd.ny >= y0 and rd.ny <= y1 then
                if rd.note then state:select_note(rd.note) end
            end
        end

        for _, ad in ipairs(canvas_info.all_articulation_render_data or {}) do
            -- Hit if articulation box overlaps with marquee rectangle
            if not (ad.bx1 < x0 or ad.bx0 > x1 or ad.by1 < y0 or ad.by0 > y1) then
                if ad.art then state:select_articulation(ad.art) end
            end
        end
    end
    
    if reaper.ImGui_IsMouseReleased(ctx, 0) then
        if state.marquee_active then
            local n_cnt = state:count_selected_notes()
            local a_cnt = state:count_selected_articulations()
            if a_cnt > 0 and n_cnt > 0 then
                state.status_msg = string.format("%d note(s), %d articulation(s) selected", n_cnt, a_cnt)
            elseif a_cnt > 0 then
                state.status_msg = string.format("%d articulation(s) selected", a_cnt)
            elseif n_cnt > 0 then
                state.status_msg = string.format("%d note(s) selected", n_cnt)
            end
            midi_service.sync_selection_to_reaper(state, canvas_info.active_tracks_data)
        end
        state.marquee_active = false
        state.marquee_potential = false
        state.marquee_add_mode = false
        state.marquee_initial_selection = nil
        state.marquee_initial_art_selection = nil
        state.drag_note = nil
        state.is_dragging = false
        state.drag_selected_snapshot = {}
        state.drag_delta_qn = 0
        state.drag_delta_pitch = 0
    end
end

return MouseHandler

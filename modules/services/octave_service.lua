-- ==============================================================================
-- REAPER Native Notator - Service: OctaveService
-- Manages Ottava / Octave Lines (8va, 15ma, 22ma, 8vb, 15mb, 22mb, loco)
-- Supports dual-handle dragging (like gradual tempo markers) & pitch transposition
-- Octave lines modify the underlying REAPER MIDI pitch (sounding pitch),
-- while the canvas displays the written pitch without moving on the staff.
-- ==============================================================================

local Constants  = require("constants")
local OctaveLine = require("classes.octave_line")

local OctaveService = {}

local function sync_lines_to_takes(state)
    local by_guid = {}
    for _, line in ipairs(state.octave_lines or {}) do
        if line.track_guid then
            by_guid[line.track_guid] = by_guid[line.track_guid] or {}
            table.insert(by_guid[line.track_guid], line)
        end
    end
    
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            local track_line_list = by_guid[trk_guid] or {}
            
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local i_start_qn = reaper.TimeMap2_timeToQN(0, item_pos)
                    local i_end_qn = reaper.TimeMap2_timeToQN(0, item_pos + item_len)
                    
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                    local to_del = {}
                    for t_idx = text_cnt - 1, 0, -1 do
                        local ok, _, _, _, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, t_idx)
                        if ok and ev_type == 15 and msg:match("^NOTATOR_OCTAVE") then
                            table.insert(to_del, t_idx)
                        end
                    end
                    for _, d_idx in ipairs(to_del) do
                        reaper.MIDI_DeleteTextSysexEvt(take, d_idx)
                    end
                    
                    local inserted = false
                    for _, line in ipairs(track_line_list) do
                        if line.start_qn >= (i_start_qn - 0.05) and line.start_qn < (i_end_qn + 0.05) then
                            local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, line.start_qn) + 0.5)
                            local msg = string.format("NOTATOR_OCTAVE|%s|%s|%.4f|%.4f",
                                line.id, line.type, line.start_qn, line.end_qn)
                            reaper.MIDI_InsertTextSysexEvt(take, false, false, ppq, 15, msg)
                            inserted = true
                        end
                    end
                    if inserted or #to_del > 0 then
                        reaper.MIDI_Sort(take)
                    end
                end
            end
        end
    end
end

function OctaveService.load_lines(state)
    state.octave_lines = {}
    local known = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "octave_lines")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id = parts[1]
            local track_guid = parts[2]
            local otype = parts[3]
            local start_qn = tonumber(parts[4]) or 0.0
            local end_qn = tonumber(parts[5]) or 4.0
            if id and id ~= "" and track_guid and otype then
                known[id] = true
                local line = OctaveLine.new({
                    id         = id,
                    track_guid = track_guid,
                    type       = otype,
                    start_qn   = start_qn,
                    end_qn     = end_qn
                })
                table.insert(state.octave_lines, line)
            end
        end
    end

    -- DUAL PERSISTENCE: Read from MIDI takes (Type 15 notation events in .RPP)
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                    for text_i = 0, text_cnt - 1 do
                        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
                        if ok and ev_type == 15 and msg:match("^NOTATOR_OCTAVE") then
                            local parts = {}
                            for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
                            local id = parts[2]
                            local otype = parts[3]
                            local start_qn = tonumber(parts[4]) or reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                            local end_qn = tonumber(parts[5]) or (start_qn + 4.0)
                            if id and id ~= "" and otype and not known[id] then
                                known[id] = true
                                table.insert(state.octave_lines, OctaveLine.new({
                                    id         = id,
                                    track_guid = trk_guid,
                                    type       = otype,
                                    start_qn   = start_qn,
                                    end_qn     = end_qn
                                }))
                            end
                        end
                    end
                end
            end
        end
    end
end

function OctaveService.parse_notation_event(state, track, take, ppq, msg)
    if not state or not msg then return end
    if not state.octave_lines then state.octave_lines = {} end
    local trk_guid = track and reaper.ValidatePtr(track, "MediaTrack*") and reaper.GetTrackGUID(track)
    if not trk_guid then return end
    
    local parts = {}
    for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
    local id = parts[2]
    if not id or id == "" then return end
    
    for _, ol in ipairs(state.octave_lines) do
        if ol.id == id then return end
    end
    
    local otype = parts[3] or "8va"
    local start_qn = tonumber(parts[4]) or (take and reaper.MIDI_GetProjQNFromPPQPos(take, ppq)) or 0.0
    local end_qn = tonumber(parts[5]) or (start_qn + 4.0)
    
    table.insert(state.octave_lines, OctaveLine.new({
        id         = id,
        track_guid = trk_guid,
        type       = otype,
        start_qn   = start_qn,
        end_qn     = end_qn
    }))
end

function OctaveService.save_lines(state)
    local parts = {}
    for _, line in ipairs(state.octave_lines or {}) do
        local entry = string.format("%s|%s|%s|%.4f|%.4f",
            line.id, line.track_guid, line.type, line.start_qn, line.end_qn)
        table.insert(parts, entry)
    end
    local raw = table.concat(parts, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "octave_lines", raw)
    sync_lines_to_takes(state)
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    if reaper.Main_UpdateLoopInfo then reaper.Main_UpdateLoopInfo(0) end
end

function OctaveService.get_lines_for_track(state, track_guid)
    local lines = state and state.octave_lines
    if not lines or #lines == 0 then return {} end
    local res = {}
    for _, line in ipairs(lines) do
        if line.track_guid == track_guid then
            table.insert(res, line)
        end
    end
    table.sort(res, function(a, b) return a.start_qn < b.start_qn end)
    return res
end

function OctaveService.get_active_line_at_qn(state, track_guid, qn)
    local lines = state and state.octave_lines
    if not lines or #lines == 0 then return nil end
    for _, line in ipairs(lines) do
        local s_qn = line.start_qn
        local e_qn = line.end_qn
        -- While dragging/resizing: The REAPER MIDI still corresponds to
        -- original bounds (orig_start / orig_end). Use these for pitch rendering,
        -- so notes on the canvas do not jump at any time during resizing!
        if state and state.is_dragging_octave and state.drag_octave_line == line then
            s_qn = state.drag_octave_orig_start or s_qn
            e_qn = state.drag_octave_orig_end or e_qn
        end
        local tg = line.track_guid
        local match_track = (tg == track_guid) or (tg and track_guid and tg:upper() == track_guid:upper())
        if match_track and qn >= (s_qn - 0.01) and qn < (e_qn - 0.01) then
            return line
        end
    end
    return nil
end

function OctaveService.resize_octave_line(state, oline, orig_s, orig_e, new_s, new_e)
    if not oline then return end
    local def = Constants.OCTAVE_LINE_DEFS[oline.type]
    local shift = def and def.shift_semitones or 0
    if shift == 0 then
        oline.start_qn = new_s
        oline.end_qn = new_e
        OctaveService.save_lines(state)
        return
    end

    local track_guid = oline.track_guid
    local trk = nil
    if track_guid and track_guid ~= "" then
        local trk_cnt = reaper.CountTracks(0)
        for i = 0, trk_cnt - 1 do
            local t = reaper.GetTrack(0, i)
            local tg = reaper.GetTrackGUID(t)
            if tg == track_guid or (tg and tg:upper() == track_guid:upper()) then
                trk = t
                break
            end
        end
    end
    if not trk and state and state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            if sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then trk = sn.track break end
        end
    end
    if not trk and state and state.focused_track then trk = state.focused_track end
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then
        oline.start_qn = new_s
        oline.end_qn = new_e
        OctaveService.save_lines(state)
        return
    end

    local item_cnt = reaper.CountTrackMediaItems(trk)
    reaper.Undo_BeginBlock2(0)
    local any_modified = false
    for i = 0, item_cnt - 1 do
        local it = reaper.GetTrackMediaItem(trk, i)
        local take = reaper.GetActiveTake(it)
        if take and reaper.TakeIsMIDI(take) then
            local _, notecnt = reaper.MIDI_CountEvts(take)
            local modified = false
            reaper.MIDI_DisableSort(take)
            for n_idx = 0, notecnt - 1 do
                local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n_idx)
                if ok then
                    local n_sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                    local was_in = (n_sqn >= (orig_s - 0.01) and n_sqn < (orig_e - 0.01))
                    local is_in  = (n_sqn >= (new_s - 0.01)  and n_sqn < (new_e - 0.01))
                    
                    local delta = 0
                    if was_in and not is_in then
                        -- Note has left the octave line -> restore MIDI pitch
                        delta = -shift
                    elseif not was_in and is_in then
                        -- Note has newly entered the octave line -> transpose MIDI pitch
                        delta = shift
                    end
                    
                    if delta ~= 0 then
                        local new_pitch = math.max(0, math.min(127, pitch + delta))
                        if new_pitch ~= pitch then
                            reaper.MIDI_SetNote(take, n_idx, sel, muted, sppq, eppq, chan, new_pitch, vel, true)
                            modified = true
                            any_modified = true
                        end
                    end
                end
            end
            reaper.MIDI_Sort(take)
            if modified then
                reaper.UpdateItemInProject(it)
            end
        end
    end
    
    -- Keep selection in state synchronized if selected notes crossed the boundary
    if any_modified and state and state.selected_notes then
        local updated_sel = {}
        for k, sn in pairs(state.selected_notes) do
            local was_in = (sn.start_qn >= (orig_s - 0.01) and sn.start_qn < (orig_e - 0.01))
            local is_in  = (sn.start_qn >= (new_s - 0.01)  and sn.start_qn < (new_e - 0.01))
            local delta = 0
            if was_in and not is_in then
                delta = -shift
            elseif not was_in and is_in then
                delta = shift
            end
            if delta ~= 0 then
                sn.pitch = math.max(0, math.min(127, sn.pitch + delta))
                local new_k = sn.get_key and sn:get_key() or string.format("%s_%s_%.3f_%d_%d", tostring(sn.item), tostring(sn.take), sn.start_qn, sn.pitch, sn.chan or 0)
                sn.key = new_k
                updated_sel[new_k] = sn
            else
                updated_sel[k] = sn
            end
        end
        state.selected_notes = updated_sel
    end

    reaper.Undo_EndBlock2(0, string.format("Notator: Resize %s (%.1f to %.1f QN)", def.name, new_s, new_e), -1)
    reaper.UpdateArrange()
    local MidiService = package.loaded["services.midi_service"]
    if MidiService and MidiService.invalidate_cache then MidiService.invalidate_cache() end

    oline.start_qn = new_s
    oline.end_qn = new_e
    OctaveService.save_lines(state)
end

function OctaveService.apply_shift_to_track_midi(state, track_guid, start_qn, end_qn, semitones)
    if not semitones or semitones == 0 then return end
    local trk = nil
    if track_guid and track_guid ~= "" then
        local trk_cnt = reaper.CountTracks(0)
        for i = 0, trk_cnt - 1 do
            local t = reaper.GetTrack(0, i)
            local tg = reaper.GetTrackGUID(t)
            if tg == track_guid or (tg and tg:upper() == track_guid:upper()) then
                trk = t
                break
            end
        end
    end
    if not trk and state and state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            if sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then
                trk = sn.track
                break
            end
        end
    end
    if not trk and state and state.selected_note and state.selected_note.track then
        trk = state.selected_note.track
    end
    if not trk and state and state.focused_track then trk = state.focused_track end
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then return end
    
    local item_cnt = reaper.CountTrackMediaItems(trk)
    reaper.Undo_BeginBlock2(0)
    local any_modified = false
    for i = 0, item_cnt - 1 do
        local it = reaper.GetTrackMediaItem(trk, i)
        local take = reaper.GetActiveTake(it)
        if take and reaper.TakeIsMIDI(take) then
            local _, notecnt = reaper.MIDI_CountEvts(take)
            local modified = false
            reaper.MIDI_DisableSort(take)
            for n_idx = 0, notecnt - 1 do
                local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n_idx)
                if ok then
                    local n_sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                    if n_sqn >= (start_qn - 0.01) and n_sqn < (end_qn - 0.01) then
                        local new_pitch = math.max(0, math.min(127, pitch + semitones))
                        if new_pitch ~= pitch then
                            reaper.MIDI_SetNote(take, n_idx, sel, muted, sppq, eppq, chan, new_pitch, vel, true)
                            modified = true
                            any_modified = true
                        end
                    end
                end
            end
            reaper.MIDI_Sort(take)
            if modified then
                reaper.UpdateItemInProject(it)
            end
        end
    end
    reaper.Undo_EndBlock2(0, string.format("Notator: Octave Line Shift (%+d Semitones)", semitones), -1)
    reaper.UpdateArrange()
    local MidiService = package.loaded["services.midi_service"]
    if MidiService and MidiService.invalidate_cache then MidiService.invalidate_cache() end
    
    -- Keep selection in state synchronized so keys and pitches remain consistent
    if any_modified and state and state.selected_notes then
        local updated_sel = {}
        for k, sn in pairs(state.selected_notes) do
            if sn.start_qn >= (start_qn - 0.05) and sn.start_qn < (end_qn - 0.05) then
                sn.pitch = math.max(0, math.min(127, sn.pitch + semitones))
                local new_k = sn.get_key and sn:get_key() or string.format("%s_%s_%.3f_%d_%d", tostring(sn.item), tostring(sn.take), sn.start_qn, sn.pitch, sn.chan or 0)
                sn.key = new_k
                updated_sel[new_k] = sn
            else
                updated_sel[k] = sn
            end
        end
        state.selected_notes = updated_sel
    end
end

function OctaveService.add_octave_line(state, track_guid, otype, midi_service, active_tracks_data, opt_start_qn, opt_end_qn)
    if not track_guid or track_guid == "" then
        for _, sn in pairs(state.selected_notes or {}) do
            if sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then
                track_guid = reaper.GetTrackGUID(sn.track)
                break
            end
        end
    end
    if not track_guid or track_guid == "" then
        if state.selected_note and state.selected_note.track and reaper.ValidatePtr(state.selected_note.track, "MediaTrack*") then
            track_guid = reaper.GetTrackGUID(state.selected_note.track)
        end
    end
    if not track_guid or track_guid == "" then
        if state.focused_track and reaper.ValidatePtr(state.focused_track, "MediaTrack*") then
            track_guid = reaper.GetTrackGUID(state.focused_track)
        end
    end
    if not track_guid or track_guid == "" then
        state.status_msg = "Please focus a track or select notes first to add an octave line"
        return nil
    end
    
    local def = Constants.OCTAVE_LINE_DEFS[otype] or Constants.OCTAVE_LINE_DEFS["8va"]
    
    -- Determine start and end QN: either passed QNs, range of selected notes, or edit cursor
    local start_qn = opt_start_qn or 0.0
    local end_qn = opt_end_qn or (start_qn + 4.0)
    
    if not opt_start_qn then
        local sel_cnt = state:count_selected_notes()
        if sel_cnt > 0 then
            local min_s = 1e9
            local max_e = -1e9
            for _, n in pairs(state.selected_notes) do
                if n.start_qn < min_s then min_s = n.start_qn end
                if n.end_qn > max_e then max_e = n.end_qn end
            end
            if min_s < 1e8 and max_e > -1e8 then
                start_qn = min_s
                end_qn = math.max(min_s + 0.5, max_e)
            end
        else
            local cur_time = reaper.GetCursorPosition()
            start_qn = reaper.TimeMap2_timeToQN(0, cur_time)
            end_qn = start_qn + 4.0
        end
    end
    
    -- If an octave line already exists at this location, remove old shift first (prevents stacking shifts)
    state.octave_lines = state.octave_lines or {}
    for i = #state.octave_lines, 1, -1 do
        local ex = state.octave_lines[i]
        if ex.track_guid == track_guid and math.abs(ex.start_qn - start_qn) < 0.2 and math.abs(ex.end_qn - end_qn) < 0.2 then
            OctaveService.delete_octave_line(state, ex)
            break
        end
    end
    
    local new_line = OctaveLine.new({
        track_guid = track_guid,
        type       = otype,
        start_qn   = start_qn,
        end_qn     = end_qn
    })
    
    table.insert(state.octave_lines, new_line)
    state.selected_octave_line = new_line
    OctaveService.save_lines(state)
    
    -- Transpose the underlying MIDI data in the REAPER track
    local shift = def.shift_semitones or 0
    if shift ~= 0 then
        OctaveService.apply_shift_to_track_midi(state, track_guid, start_qn, end_qn, shift)
    end
    
    state.status_msg = string.format("Added %s line (%.1f to %.1f QN, MIDI %+d)", def.name, start_qn, end_qn, shift)
    reaper.Undo_OnStateChange2(0, string.format("Notator: Add %s", def.name))
    return new_line
end

function OctaveService.delete_octave_line(state, line_or_id)
    if not line_or_id or not state.octave_lines then return end
    local id = (type(line_or_id) == "table") and line_or_id.id or line_or_id
    for i = #state.octave_lines, 1, -1 do
        local l = state.octave_lines[i]
        if l == line_or_id or l.id == id then
            local def = Constants.OCTAVE_LINE_DEFS[l.type]
            local shift = def and def.shift_semitones or 0
            if shift ~= 0 then
                OctaveService.apply_shift_to_track_midi(state, l.track_guid, l.start_qn, l.end_qn, -shift)
            end
            table.remove(state.octave_lines, i)
            break
        end
    end
    if state.selected_octave_line and (state.selected_octave_line == line_or_id or state.selected_octave_line.id == id) then
        state.selected_octave_line = nil
    end
    OctaveService.save_lines(state)
    reaper.Undo_OnStateChange2(0, "Notator: Delete Octave Line")
    state.status_msg = "Octave line deleted (MIDI restored)"
end
OctaveService.delete_line = OctaveService.delete_octave_line

function OctaveService.update_line_bounds(state, line, new_start_qn, new_end_qn)
    if not line then return end
    if new_start_qn then line.start_qn = math.max(0.0, new_start_qn) end
    if new_end_qn then line.end_qn = math.max((line.start_qn or 0.0) + 0.25, new_end_qn) end
    OctaveService.save_lines(state)
end

return OctaveService

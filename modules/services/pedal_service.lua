-- ==============================================================================
-- REAPER Native Notator - Service: PedalService
-- Manages Holding/Sustain marks (Pedal line, CC64) with dual handles,
-- sustain pauses/retakes, and live REAPER CC64 synchronization.
-- ==============================================================================

local PedalMark = require("classes.pedal_mark")

local PedalService = {}

local function sync_pedals_to_takes(state)
    local by_guid = {}
    for _, pm in ipairs(state.pedal_marks or {}) do
        if pm.track_guid then
            by_guid[pm.track_guid] = by_guid[pm.track_guid] or {}
            table.insert(by_guid[pm.track_guid], pm)
        end
    end

    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            local track_pm_list = by_guid[trk_guid] or {}

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
                        if ok and ev_type == 15 and msg:match("^NOTATOR_PEDAL") then
                            table.insert(to_del, t_idx)
                        end
                    end
                    for _, d_idx in ipairs(to_del) do
                        reaper.MIDI_DeleteTextSysexEvt(take, d_idx)
                    end

                    local inserted = false
                    for _, pm in ipairs(track_pm_list) do
                        if pm.start_qn >= (i_start_qn - 0.05) and pm.start_qn < (i_end_qn + 0.05) then
                            local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, pm.start_qn) + 0.5)
                            local p_entries = {}
                            for _, p in ipairs(pm.pauses or {}) do
                                table.insert(p_entries, string.format("%.4f:%s:%.4f:%s", p.qn, p.type or "asterisk", p.dur or 0.0, p.id or ""))
                            end
                            local pauses_str = table.concat(p_entries, ",")
                            local msg = string.format("NOTATOR_PEDAL|%s|%.4f|%.4f|%s|%s|%s|%s",
                                pm.id, pm.start_qn, pm.end_qn, pm.style or "classic",
                                pm.apply_cc and "1" or "0", pm.staff or "bass", pauses_str)
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

function PedalService.load_pedals(state, read_only)
    state.pedal_marks = {}
    local known = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "pedal_marks")
    local has_proj_ext = (raw and raw ~= "")
    if has_proj_ext then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id         = parts[1]
            local track_guid = parts[2]
            local start_qn   = tonumber(parts[3]) or 0.0
            local end_qn     = tonumber(parts[4]) or 4.0
            local style      = (parts[5] and parts[5] ~= "") and parts[5] or "classic"
            local apply_cc   = (parts[6] ~= "0" and parts[6] ~= "false")
            local staff      = (parts[7] and parts[7] ~= "") and parts[7] or "bass"
            local raw_pauses = parts[8] or ""

            local pauses_list = {}
            if raw_pauses ~= "" then
                for p_str in raw_pauses:gmatch("([^,]+)") do
                    local p_parts = {}
                    for field in (p_str .. ":"):gmatch("([^:]*):") do
                        table.insert(p_parts, field)
                    end
                    local pqn = tonumber(p_parts[1])
                    if pqn then
                        table.insert(pauses_list, {
                            id   = p_parts[4] or string.format("p_%d", math.random(1000, 9999)),
                            qn   = pqn,
                            type = (p_parts[2] and p_parts[2] ~= "") and p_parts[2] or "asterisk",
                            dur  = tonumber(p_parts[3]) or 0.0
                        })
                    end
                end
            end

            if id and id ~= "" and track_guid and track_guid ~= "" then
                known[id] = true
                local pm = PedalMark.new({
                    id         = id,
                    track_guid = track_guid,
                    start_qn   = start_qn,
                    end_qn     = end_qn,
                    style      = style,
                    apply_cc   = apply_cc,
                    staff      = staff,
                    pauses     = pauses_list
                })
                table.insert(state.pedal_marks, pm)
            end
        end
    end

    -- DUAL PERSISTENCE: Read from MIDI takes only on initial load when ProjExtState is empty
    if not read_only and not has_proj_ext then
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
                            if ok and ev_type == 15 and msg:match("^NOTATOR_PEDAL") then
                                local parts = {}
                                for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
                                local id = parts[2]
                                local start_qn = tonumber(parts[3]) or reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                                local end_qn = tonumber(parts[4]) or (start_qn + 4.0)
                                local style = (parts[5] and parts[5] ~= "") and parts[5] or "classic"
                                local apply_cc = (parts[6] ~= "0" and parts[6] ~= "false")
                                local staff = (parts[7] and parts[7] ~= "") and parts[7] or "bass"
                                local raw_pauses = parts[8] or ""
                                local pauses_list = {}
                                if raw_pauses ~= "" then
                                    for p_str in raw_pauses:gmatch("([^,]+)") do
                                        local p_parts = {}
                                        for field in (p_str .. ":"):gmatch("([^:]*):") do table.insert(p_parts, field) end
                                        local pqn = tonumber(p_parts[1])
                                        if pqn then
                                            table.insert(pauses_list, {
                                                id = p_parts[4] or string.format("p_%d", math.random(1000, 9999)),
                                                qn = pqn,
                                                type = (p_parts[2] and p_parts[2] ~= "") and p_parts[2] or "asterisk",
                                                dur = tonumber(p_parts[3]) or 0.0
                                            })
                                        end
                                    end
                                end
                                if id and id ~= "" and not known[id] then
                                    known[id] = true
                                    table.insert(state.pedal_marks, PedalMark.new({
                                        id = id,
                                        track_guid = trk_guid,
                                        start_qn = start_qn,
                                        end_qn = end_qn,
                                        style = style,
                                        apply_cc = apply_cc,
                                        staff = staff,
                                        pauses = pauses_list
                                    }))
                                end
                            end
                        end
                    end
                end
            end
        end
        if #state.pedal_marks > 0 then
            PedalService.save_pedals(state)
        end
    elseif not read_only and has_proj_ext then
        sync_pedals_to_takes(state)
    elseif read_only then
        PedalService.sync_all_tracks_cc64_if_needed(state)
    end

    state._pedals_loaded = true
    if state.selected_pedal then
        local found = nil
        for _, pm in ipairs(state.pedal_marks) do
            if pm.id == state.selected_pedal.id then found = pm; break end
        end
        state.selected_pedal = found
    end
end

function PedalService.parse_notation_event(state, track, take, ppq, msg)
    if not state or not msg then return end
    if state._pedals_loaded then return end
    if not state.pedal_marks then state.pedal_marks = {} end
    local trk_guid = track and reaper.ValidatePtr(track, "MediaTrack*") and reaper.GetTrackGUID(track)
    if not trk_guid then return end

    local parts = {}
    for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
    local id = parts[2]
    if not id or id == "" then return end

    for _, pm in ipairs(state.pedal_marks) do
        if pm.id == id then return end
    end

    local start_qn = tonumber(parts[3]) or (take and reaper.MIDI_GetProjQNFromPPQPos(take, ppq)) or 0.0
    local end_qn = tonumber(parts[4]) or (start_qn + 4.0)
    local style = (parts[5] and parts[5] ~= "") and parts[5] or "classic"
    local apply_cc = (parts[6] ~= "0" and parts[6] ~= "false")
    local staff = (parts[7] and parts[7] ~= "") and parts[7] or "bass"
    local raw_pauses = parts[8] or ""
    local pauses_list = {}
    if raw_pauses ~= "" then
        for p_str in raw_pauses:gmatch("([^,]+)") do
            local p_parts = {}
            for field in (p_str .. ":"):gmatch("([^:]*):") do table.insert(p_parts, field) end
            local pqn = tonumber(p_parts[1])
            if pqn then
                table.insert(pauses_list, {
                    id = p_parts[4] or string.format("p_%d", math.random(1000, 9999)),
                    qn = pqn,
                    type = (p_parts[2] and p_parts[2] ~= "") and p_parts[2] or "asterisk",
                    dur = tonumber(p_parts[3]) or 0.0
                })
            end
        end
    end

    table.insert(state.pedal_marks, PedalMark.new({
        id = id,
        track_guid = trk_guid,
        start_qn = start_qn,
        end_qn = end_qn,
        style = style,
        apply_cc = apply_cc,
        staff = staff,
        pauses = pauses_list
    }))
end

function PedalService.save_pedals(state)
    local parts = {}
    for _, pm in ipairs(state.pedal_marks or {}) do
        local p_entries = {}
        for _, p in ipairs(pm.pauses or {}) do
            table.insert(p_entries, string.format("%.4f:%s:%.4f:%s", p.qn, p.type or "asterisk", p.dur or 0.0, p.id or ""))
        end
        local pauses_str = table.concat(p_entries, ",")
        local entry = string.format("%s|%s|%.4f|%.4f|%s|%s|%s|%s",
            pm.id, pm.track_guid, pm.start_qn, pm.end_qn, pm.style or "classic",
            pm.apply_cc and "1" or "0", pm.staff or "bass", pauses_str)
        table.insert(parts, entry)
    end
    local raw = table.concat(parts, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "pedal_marks", raw)
    sync_pedals_to_takes(state)
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    if reaper.Main_UpdateLoopInfo then reaper.Main_UpdateLoopInfo(0) end
end

function PedalService.get_pedals_for_track(state, track_guid)
    local res = {}
    for _, pm in ipairs(state.pedal_marks or {}) do
        if pm.track_guid == track_guid then
            table.insert(res, pm)
        end
    end
    return res
end

function PedalService.get_all_takes_for_track(track_guid, active_tracks_data)
    local takes = {}
    local trk = nil
    for _, td in ipairs(active_tracks_data or {}) do
        if td.guid == track_guid and td.track and reaper.ValidatePtr(td.track, "MediaTrack*") then
            trk = td.track
            break
        end
    end
    if not trk then
        local trk_cnt = reaper.CountTracks(0)
        for i = 0, trk_cnt - 1 do
            local t = reaper.GetTrack(0, i)
            if t and reaper.GetTrackGUID(t) == track_guid then
                trk = t
                break
            end
        end
    end
    if not trk then return takes, nil end

    local item_cnt = reaper.CountTrackMediaItems(trk)
    for i = 0, item_cnt - 1 do
        local it = reaper.GetTrackMediaItem(trk, i)
        if it then
            local tk = reaper.GetActiveTake(it)
            if tk and reaper.TakeIsMIDI(tk) then
                local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                local s_qn = reaper.TimeMap2_timeToQN(0, ipos)
                local e_qn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                table.insert(takes, { take = tk, item = it, start_qn = s_qn, end_qn = e_qn })
            end
        end
    end
    return takes, trk
end

function PedalService.find_take_for_track(track_guid, active_tracks_data)
    local takes, trk = PedalService.get_all_takes_for_track(track_guid, active_tracks_data)
    if #takes > 0 then
        return takes[1].take, takes[1].item
    end
    return nil, nil
end

local function find_take_covering_qn(takes_list, qn)
    for _, tinfo in ipairs(takes_list) do
        if qn >= (tinfo.start_qn - 0.05) and qn < (tinfo.end_qn + 0.05) then
            return tinfo.take, tinfo.item
        end
    end
    if #takes_list > 0 then
        return takes_list[1].take, takes_list[1].item
    end
    return nil, nil
end

function PedalService.create_pedal(state, track_guid, start_qn, end_qn, style, midi_service, active_tracks_data, staff)
    if not track_guid or track_guid == "" then return nil end
    local s_qn = start_qn or 0.0
    local e_qn = end_qn or (s_qn + 4.0)
    if e_qn <= s_qn then e_qn = s_qn + 1.0 end

    local pm = PedalMark.new({
        track_guid = track_guid,
        start_qn   = s_qn,
        end_qn     = e_qn,
        style      = style or "classic",
        apply_cc   = true,
        staff      = staff or "bass",
        pauses     = {}
    })

    reaper.Undo_BeginBlock2(0)
    if not state.pedal_marks then state.pedal_marks = {} end
    table.insert(state.pedal_marks, pm)
    state.selected_pedal = pm
    PedalService.save_pedals(state)

    if pm.apply_cc then
        PedalService.apply_cc(state, pm, midi_service, active_tracks_data)
    end
    reaper.Undo_EndBlock2(0, "Notator: Add Sustain Pedal", -1)
    state.status_msg = string.format("Pedal mark created (measure %.2f - %.2f)", (s_qn / 4) + 1, (e_qn / 4) + 1)
    return pm
end

function PedalService.delete_pedal(state, pedal_id, midi_service, active_tracks_data)
    if not state.pedal_marks then return end
    for i, pm in ipairs(state.pedal_marks) do
        if pm.id == pedal_id then
            reaper.Undo_BeginBlock2(0)
            local deleted = table.remove(state.pedal_marks, i)
            if state.selected_pedal and state.selected_pedal.id == pedal_id then
                state.selected_pedal = nil
            end
            if state.hovered_pedal and state.hovered_pedal.id == pedal_id then
                state.hovered_pedal = nil
            end
            PedalService.save_pedals(state)

            -- Rebuild CC64 cleanly across all remaining pedals on the track
            if deleted.apply_cc then
                PedalService.rebuild_track_cc64(state, deleted.track_guid, midi_service, active_tracks_data)
            end
            reaper.Undo_EndBlock2(0, "Notator: Delete Sustain Pedal", -1)
            state.status_msg = "Pedal mark deleted"
            return
        end
    end
end

function PedalService.resize_pedal(state, pedal_id, new_start, new_end, midi_service, active_tracks_data)
    for _, pm in ipairs(state.pedal_marks or {}) do
        if pm.id == pedal_id then
            reaper.Undo_BeginBlock2(0)
            local old_s = pm.start_qn
            local old_e = pm.end_qn
            if new_start then pm.start_qn = math.max(0.0, new_start) end
            if new_end then pm.end_qn = math.max(pm.start_qn + 0.25, new_end) end

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
                local clear_s = math.min(old_s, pm.start_qn)
                local clear_e = math.max(old_e, pm.end_qn)
                PedalService.apply_cc(state, pm, midi_service, active_tracks_data, clear_s, clear_e)
            end
            reaper.Undo_EndBlock2(0, "Notator: Resize Sustain Pedal", -1)
            return
        end
    end
end

function PedalService.add_pause_point(state, pedal, qn, ptype, midi_service, active_tracks_data)
    if not pedal then return end
    reaper.Undo_BeginBlock2(0)
    local pqn = math.max(pedal.start_qn + 0.1, math.min(pedal.end_qn - 0.1, qn))
    local pid = pedal:add_pause(pqn, ptype or "asterisk", 0.0)
    PedalService.save_pedals(state)

    if pedal.apply_cc then
        PedalService.apply_cc(state, pedal, midi_service, active_tracks_data)
    end
    reaper.Undo_EndBlock2(0, "Notator: Add Sustain Pedal Retake", -1)
    state.status_msg = string.format("Inserted sustain break/retake at measure %.2f", (pqn / 4) + 1)
    return pid
end

function PedalService.remove_pause_point(state, pedal, pause_id, midi_service, active_tracks_data)
    if not pedal then return end
    reaper.Undo_BeginBlock2(0)
    pedal:remove_pause(pause_id)
    PedalService.save_pedals(state)

    if pedal.apply_cc then
        PedalService.apply_cc(state, pedal, midi_service, active_tracks_data)
    end
    reaper.Undo_EndBlock2(0, "Notator: Remove Sustain Pedal Retake", -1)
    state.status_msg = "Removed sustain break/retake"
end

function PedalService.rebuild_track_cc64(state, track_guid, midi_service, active_tracks_data)
    if not state or not track_guid or track_guid == "" then return end
    local MidiService = midi_service or package.loaded["services.midi_service"]
    local takes_list, trk = PedalService.get_all_takes_for_track(track_guid, active_tracks_data)
    if #takes_list == 0 then return end

    local pms = {}
    for _, other_pm in ipairs(state.pedal_marks or {}) do
        if other_pm.track_guid == track_guid and other_pm.apply_cc and other_pm.start_qn < other_pm.end_qn then
            table.insert(pms, other_pm)
        end
    end
    table.sort(pms, function(a, b) return a.start_qn < b.start_qn end)

    local port_pms = {}
    for _, port_pm in ipairs(state.portamento_marks or {}) do
        if port_pm.track_guid == track_guid and (port_pm.mode or "cc64") == "cc64" and port_pm.hold_start_qn and port_pm.hold_end_qn and port_pm.hold_start_qn < port_pm.hold_end_qn then
            table.insert(port_pms, port_pm)
        end
    end
    table.sort(port_pms, function(a, b) return a.hold_start_qn < b.hold_start_qn end)

    local touched_takes = {}

    -- 1. Remove all old CC64 events across all takes on this track
    for _, tinfo in ipairs(takes_list) do
        local tk = tinfo.take
        reaper.MIDI_DisableSort(tk)
        local _, _, cc_cnt = reaper.MIDI_CountEvts(tk)
        local to_del = {}
        for j = (cc_cnt or 0) - 1, 0, -1 do
            local ok, _, _, _, _, _, msg2, _ = reaper.MIDI_GetCC(tk, j)
            if ok and msg2 == 64 then
                table.insert(to_del, j)
            end
        end
        for _, d_idx in ipairs(to_del) do
            reaper.MIDI_DeleteCC(tk, d_idx)
        end
        touched_takes[tk] = tinfo.item
    end

    -- 2. Re-insert CC64 events cleanly for every active pedal on this track
    for _, cur_pm in ipairs(pms) do
        local tk_start, it_start = find_take_covering_qn(takes_list, cur_pm.start_qn)
        if tk_start then
            local s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_start, cur_pm.start_qn) + 0.5)
            reaper.MIDI_InsertCC(tk_start, false, false, s_ppq, 0xB0, 0, 64, 127)
            touched_takes[tk_start] = it_start or touched_takes[tk_start]
        end

        local sorted_pauses = {}
        for _, p in ipairs(cur_pm.pauses or {}) do
            if p.qn > cur_pm.start_qn and p.qn < cur_pm.end_qn then
                table.insert(sorted_pauses, p)
            end
        end
        table.sort(sorted_pauses, function(a, b) return a.qn < b.qn end)

        for _, p in ipairs(sorted_pauses) do
            local tk_p, it_p = find_take_covering_qn(takes_list, p.qn)
            if tk_p then
                local p_off_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_p, p.qn) + 0.5)
                reaper.MIDI_InsertCC(tk_p, false, false, p_off_ppq, 0xB0, 0, 64, 0)
                touched_takes[tk_p] = it_p or touched_takes[tk_p]

                local resume_qn = p.qn + (p.dur > 0 and p.dur or 0.125)
                if resume_qn < cur_pm.end_qn then
                    local tk_res, it_res = find_take_covering_qn(takes_list, resume_qn)
                    if tk_res then
                        local p_on_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_res, resume_qn) + 0.5)
                        reaper.MIDI_InsertCC(tk_res, false, false, p_on_ppq, 0xB0, 0, 64, 127)
                        touched_takes[tk_res] = it_res or touched_takes[tk_res]
                    end
                end
            end
        end

        local tk_end, it_end = find_take_covering_qn(takes_list, cur_pm.end_qn)
        if tk_end then
            local e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_end, cur_pm.end_qn) + 0.5)
            reaper.MIDI_InsertCC(tk_end, false, false, e_ppq, 0xB0, 0, 64, 0)
            touched_takes[tk_end] = it_end or touched_takes[tk_end]
        end
    end

    -- 2b. Also re-insert CC64 events for any active CC64 Portamento marks on this track
    for _, port_pm in ipairs(port_pms) do
        local chan = (port_pm.chan or 0) & 0x0F
        local tk_s, it_s = find_take_covering_qn(takes_list, port_pm.hold_start_qn)
        if tk_s then
            local s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_s, port_pm.hold_start_qn) + 0.5)
            reaper.MIDI_InsertCC(tk_s, false, false, s_ppq, 0xB0, chan, 64, 127)
            touched_takes[tk_s] = it_s or touched_takes[tk_s]
        end
        local tk_e, it_e = find_take_covering_qn(takes_list, port_pm.hold_end_qn)
        if tk_e then
            local e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_e, port_pm.hold_end_qn) + 0.5)
            reaper.MIDI_InsertCC(tk_e, false, false, e_ppq, 0xB0, chan, 64, 0)
            touched_takes[tk_e] = it_e or touched_takes[tk_e]
        end
    end

    -- 3. Sort and enforce Square CC shape (0) for all CC64 events
    for tk, it in pairs(touched_takes) do
        reaper.MIDI_Sort(tk)
        if reaper.MIDI_SetCCShape then
            local _, _, cc_cnt = reaper.MIDI_CountEvts(tk)
            for j = 0, (cc_cnt or 0) - 1 do
                local ok, _, _, _, _, _, msg2, _ = reaper.MIDI_GetCC(tk, j)
                if ok and msg2 == 64 then
                    reaper.MIDI_SetCCShape(tk, j, 0, 0, true)
                end
            end
            reaper.MIDI_Sort(tk)
        end
        if trk and it and reaper.MarkTrackItemsDirty then
            reaper.MarkTrackItemsDirty(trk, it)
        end
    end

    if MidiService and MidiService.invalidate_editor_cache then
        MidiService.invalidate_editor_cache()
    end
end

function PedalService.sync_all_tracks_cc64_if_needed(state)
    if not state then return end
    local trk_cnt = reaper.CountTracks(0)
    for i = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, i)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            if trk_guid and trk_guid ~= "" then
                local takes_list = PedalService.get_all_takes_for_track(trk_guid)
                if #takes_list > 0 then
                    -- Build expected CC64 events per take
                    local expected_by_take = {}
                    for _, tinfo in ipairs(takes_list) do
                        expected_by_take[tinfo.take] = {}
                    end
                    local pms = {}
                    for _, pm in ipairs(state.pedal_marks or {}) do
                        if pm.track_guid == trk_guid and pm.apply_cc and pm.start_qn < pm.end_qn then
                            table.insert(pms, pm)
                        end
                    end
                    table.sort(pms, function(a, b) return a.start_qn < b.start_qn end)
                    for _, cur_pm in ipairs(pms) do
                        local tk_s = find_take_covering_qn(takes_list, cur_pm.start_qn)
                        if tk_s and expected_by_take[tk_s] then
                            table.insert(expected_by_take[tk_s], { ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_s, cur_pm.start_qn) + 0.5), val = 127 })
                        end
                        for _, p in ipairs(cur_pm.pauses or {}) do
                            if p.qn > cur_pm.start_qn and p.qn < cur_pm.end_qn then
                                local tk_p = find_take_covering_qn(takes_list, p.qn)
                                if tk_p and expected_by_take[tk_p] then
                                    table.insert(expected_by_take[tk_p], { ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_p, p.qn) + 0.5), val = 0 })
                                end
                                local resume_qn = p.qn + (p.dur > 0 and p.dur or 0.125)
                                if resume_qn < cur_pm.end_qn then
                                    local tk_r = find_take_covering_qn(takes_list, resume_qn)
                                    if tk_r and expected_by_take[tk_r] then
                                        table.insert(expected_by_take[tk_r], { ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_r, resume_qn) + 0.5), val = 127 })
                                    end
                                end
                            end
                        end
                        local tk_e = find_take_covering_qn(takes_list, cur_pm.end_qn)
                        if tk_e and expected_by_take[tk_e] then
                            table.insert(expected_by_take[tk_e], { ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_e, cur_pm.end_qn) + 0.5), val = 0 })
                        end
                    end
                    for _, port_pm in ipairs(state.portamento_marks or {}) do
                        if port_pm.track_guid == trk_guid and (port_pm.mode or "cc64") == "cc64" and port_pm.hold_start_qn and port_pm.hold_end_qn and port_pm.hold_start_qn < port_pm.hold_end_qn then
                            local tk_s = find_take_covering_qn(takes_list, port_pm.hold_start_qn)
                            if tk_s and expected_by_take[tk_s] then
                                table.insert(expected_by_take[tk_s], { ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_s, port_pm.hold_start_qn) + 0.5), val = 127 })
                            end
                            local tk_e = find_take_covering_qn(takes_list, port_pm.hold_end_qn)
                            if tk_e and expected_by_take[tk_e] then
                                table.insert(expected_by_take[tk_e], { ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_e, port_pm.hold_end_qn) + 0.5), val = 0 })
                            end
                        end
                    end

                    local mismatch = false
                    for _, tinfo in ipairs(takes_list) do
                        local tk = tinfo.take
                        local exp = expected_by_take[tk] or {}
                        table.sort(exp, function(a, b) return a.ppq < b.ppq end)
                        local actual = {}
                        local _, _, cc_cnt = reaper.MIDI_CountEvts(tk)
                        for j = 0, (cc_cnt or 0) - 1 do
                            local ok, _, _, ppq, _, _, msg2, msg3 = reaper.MIDI_GetCC(tk, j)
                            if ok and msg2 == 64 then
                                table.insert(actual, { ppq = ppq, val = msg3 })
                            end
                        end
                        if #actual ~= #exp then
                            mismatch = true
                            break
                        end
                        for k = 1, #exp do
                            if math.abs(actual[k].ppq - exp[k].ppq) > 2 or actual[k].val ~= exp[k].val then
                                mismatch = true
                                break
                            end
                        end
                        if mismatch then break end
                    end

                    if mismatch then
                        PedalService.rebuild_track_cc64(state, trk_guid)
                    end
                end
            end
        end
    end
end

function PedalService.apply_cc(state, pm, midi_service, active_tracks_data, opt_clear_s_qn, opt_clear_e_qn)
    if not pm or not pm.apply_cc or pm.start_qn >= pm.end_qn then return end

    local takes_list, trk = PedalService.get_all_takes_for_track(pm.track_guid, active_tracks_data)
    if #takes_list == 0 then
        -- If no item exists yet, create one
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") and midi_service and midi_service.get_or_create_item_at_qn then
            local dur = math.max(4.0, pm.end_qn - pm.start_qn)
            midi_service.get_or_create_item_at_qn(trk, pm.start_qn, dur)
        end
    end

    PedalService.rebuild_track_cc64(state, pm.track_guid, midi_service, active_tracks_data)
end

function PedalService.resync_track_cc(state, track_guid, midi_service, active_tracks_data)
    if not state or not track_guid then return end
    local pms = PedalService.get_pedals_for_track(state, track_guid)
    local takes_list = PedalService.get_all_takes_for_track(track_guid, active_tracks_data)
    if #takes_list == 0 then return end

    reaper.Undo_BeginBlock2(0)
    PedalService.rebuild_track_cc64(state, track_guid, midi_service, active_tracks_data)
    reaper.Undo_EndBlock2(0, "Notator: Resync Sustain Pedal CC64", -1)
    state.status_msg = string.format("Resynced CC64 for %d pedal marks on track", #pms)
end

return PedalService

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

function PedalService.load_pedals(state)
    state.pedal_marks = {}
    local known = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "pedal_marks")
    if raw and raw ~= "" then
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
end

function PedalService.parse_notation_event(state, track, take, ppq, msg)
    if not state or not msg then return end
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

    if not state.pedal_marks then state.pedal_marks = {} end
    table.insert(state.pedal_marks, pm)
    state.selected_pedal = pm
    PedalService.save_pedals(state)

    if pm.apply_cc then
        PedalService.apply_cc(state, pm, midi_service, active_tracks_data)
    end
    reaper.Undo_OnStateChange2(0, "Notator: Add Sustain Pedal")
    state.status_msg = string.format("Pedal mark created (measure %.2f - %.2f)", (s_qn / 4) + 1, (e_qn / 4) + 1)
    return pm
end

function PedalService.delete_pedal(state, pedal_id, midi_service, active_tracks_data)
    if not state.pedal_marks then return end
    for i, pm in ipairs(state.pedal_marks) do
        if pm.id == pedal_id then
            local deleted = table.remove(state.pedal_marks, i)
            if state.selected_pedal and state.selected_pedal.id == pedal_id then
                state.selected_pedal = nil
            end
            if state.hovered_pedal and state.hovered_pedal.id == pedal_id then
                state.hovered_pedal = nil
            end
            PedalService.save_pedals(state)

            -- Thoroughly clean up CC64 across the entire former range on all takes of the track
            if deleted.apply_cc then
                local takes_list, trk = PedalService.get_all_takes_for_track(deleted.track_guid, active_tracks_data)
                
                -- Find next pedal marker on the track as upper bound
                local next_s = nil
                for _, other_pm in ipairs(state.pedal_marks or {}) do
                    if other_pm.track_guid == deleted.track_guid and other_pm.start_qn >= deleted.end_qn then
                        if not next_s or other_pm.start_qn < next_s then next_s = other_pm.start_qn end
                    end
                end
                local clear_e = next_s and math.max(deleted.end_qn, next_s - 0.05) or (deleted.end_qn + 16.0)
                
                reaper.Undo_BeginBlock2(0)
                for _, tinfo in ipairs(takes_list) do
                    local tk = tinfo.take
                    if not (tinfo.end_qn < (deleted.start_qn - 0.1) or tinfo.start_qn > (clear_e + 0.1)) then
                        local s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk, deleted.start_qn) + 0.5) - 20
                        local e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk, clear_e) + 0.5) + 20
                        local _, _, cc_cnt = reaper.MIDI_CountEvts(tk)
                        local to_del = {}
                        for j = (cc_cnt or 0) - 1, 0, -1 do
                            local ok, _, _, ppq, _, _, msg2, _ = reaper.MIDI_GetCC(tk, j)
                            if ok and msg2 == 64 and ppq >= s_ppq and ppq <= e_ppq then
                                table.insert(to_del, j)
                            end
                        end
                        for _, d_idx in ipairs(to_del) do
                            reaper.MIDI_DeleteCC(tk, d_idx)
                        end
                        if #to_del > 0 then reaper.MIDI_Sort(tk) end
                    end
                end
                reaper.Undo_EndBlock2(0, "Delete Sustain Pedal CC64", -1)
            end
            state.status_msg = "Pedal mark deleted"
            return
        end
    end
end

function PedalService.resize_pedal(state, pedal_id, new_start, new_end, midi_service, active_tracks_data)
    for _, pm in ipairs(state.pedal_marks or {}) do
        if pm.id == pedal_id then
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
            return
        end
    end
end

function PedalService.add_pause_point(state, pedal, qn, ptype, midi_service, active_tracks_data)
    if not pedal then return end
    local pqn = math.max(pedal.start_qn + 0.1, math.min(pedal.end_qn - 0.1, qn))
    local pid = pedal:add_pause(pqn, ptype or "asterisk", 0.0)
    PedalService.save_pedals(state)

    if pedal.apply_cc then
        PedalService.apply_cc(state, pedal, midi_service, active_tracks_data)
    end
    state.status_msg = string.format("Inserted sustain break/retake at measure %.2f", (pqn / 4) + 1)
    return pid
end

function PedalService.remove_pause_point(state, pedal, pause_id, midi_service, active_tracks_data)
    if not pedal then return end
    pedal:remove_pause(pause_id)
    PedalService.save_pedals(state)

    if pedal.apply_cc then
        PedalService.apply_cc(state, pedal, midi_service, active_tracks_data)
    end
    state.status_msg = "Removed sustain break/retake"
end

function PedalService.apply_cc(state, pm, midi_service, active_tracks_data, opt_clear_s_qn, opt_clear_e_qn)
    if not pm or not pm.apply_cc or pm.start_qn >= pm.end_qn then return end

    local takes_list, trk = PedalService.get_all_takes_for_track(pm.track_guid, active_tracks_data)
    if #takes_list == 0 then
        -- If no item exists yet, create one
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") and midi_service and midi_service.get_or_create_item_at_qn then
            local dur = math.max(4.0, pm.end_qn - pm.start_qn)
            midi_service.get_or_create_item_at_qn(trk, pm.start_qn, dur)
            takes_list, trk = PedalService.get_all_takes_for_track(pm.track_guid, active_tracks_data)
        end
    end
    if #takes_list == 0 then return end

    -- Search for next pedal marker on the track to determine safe clearing range
    local next_pedal_s = nil
    for _, other_pm in ipairs(state.pedal_marks or {}) do
        if other_pm.track_guid == pm.track_guid and other_pm.id ~= pm.id and other_pm.start_qn >= pm.end_qn then
            if not next_pedal_s or other_pm.start_qn < next_pedal_s then
                next_pedal_s = other_pm.start_qn
            end
        end
    end

    local clear_s_qn = opt_clear_s_qn and math.min(opt_clear_s_qn, pm.start_qn) or pm.start_qn
    local clear_e_qn = opt_clear_e_qn and math.max(opt_clear_e_qn, pm.end_qn) or pm.end_qn
    
    -- Thoroughly cover orphaned endpoints after shortening:
    -- Clear up to next pedal marker or former end + buffer
    if next_pedal_s then
        clear_e_qn = math.min(math.max(clear_e_qn, pm.end_qn + 16.0), next_pedal_s - 0.05)
    else
        clear_e_qn = math.max(clear_e_qn, pm.end_qn + 16.0)
    end

    reaper.Undo_BeginBlock2(0)
    local touched_takes = {}

    -- 1. Remove old CC64 events in clear interval [clear_s_qn, clear_e_qn] completely across ALL affected takes
    for _, tinfo in ipairs(takes_list) do
        local tk = tinfo.take
        if not (tinfo.end_qn < (clear_s_qn - 0.1) or tinfo.start_qn > (clear_e_qn + 0.1)) then
            reaper.MIDI_DisableSort(tk)
            local clear_s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk, clear_s_qn) + 0.5) - 20
            local clear_e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk, clear_e_qn) + 0.5) + 20
            
            local _, _, cc_cnt = reaper.MIDI_CountEvts(tk)
            local to_del = {}
            for j = (cc_cnt or 0) - 1, 0, -1 do
                local ok, _, _, ppq, _, _, msg2, _ = reaper.MIDI_GetCC(tk, j)
                if ok and msg2 == 64 and ppq >= clear_s_ppq and ppq <= clear_e_ppq then
                    table.insert(to_del, j)
                end
            end
            for _, d_idx in ipairs(to_del) do
                reaper.MIDI_DeleteCC(tk, d_idx)
            end
            touched_takes[tk] = true
        end
    end

    -- 2. Sustain On at pm.start_qn (CC64 = 127)
    local tk_start = find_take_covering_qn(takes_list, pm.start_qn)
    if tk_start then
        local s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_start, pm.start_qn) + 0.5)
        reaper.MIDI_InsertCC(tk_start, false, false, s_ppq, 0xB0, 0, 64, 127)
        touched_takes[tk_start] = true
    end

    -- 3. Breaks / retake points
    for _, p in ipairs(pm.pauses or {}) do
        if p.qn > pm.start_qn and p.qn < pm.end_qn then
            local tk_p = find_take_covering_qn(takes_list, p.qn)
            if tk_p then
                local p_off_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_p, p.qn) + 0.5)
                -- Pedal Release (CC64 = 0)
                reaper.MIDI_InsertCC(tk_p, false, false, p_off_ppq, 0xB0, 0, 64, 0)
                touched_takes[tk_p] = true

                -- Pedal Press (Retake / continuation CC64 = 127)
                local resume_qn = p.qn + (p.dur > 0 and p.dur or 0.125)
                if resume_qn < pm.end_qn then
                    local tk_res = find_take_covering_qn(takes_list, resume_qn)
                    if tk_res then
                        local p_on_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_res, resume_qn) + 0.5)
                        reaper.MIDI_InsertCC(tk_res, false, false, p_on_ppq, 0xB0, 0, 64, 127)
                        touched_takes[tk_res] = true
                    end
                end
            end
        end
    end

    -- 4. Sustain Off at pm.end_qn (CC64 = 0)
    local tk_end = find_take_covering_qn(takes_list, pm.end_qn)
    if tk_end then
        local e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_end, pm.end_qn) + 0.5)
        reaper.MIDI_InsertCC(tk_end, false, false, e_ppq, 0xB0, 0, 64, 0)
        touched_takes[tk_end] = true
    end

    for tk, _ in pairs(touched_takes) do
        reaper.MIDI_Sort(tk)
    end
    reaper.Undo_EndBlock2(0, "Update Sustain Pedal CC64", -1)
end

function PedalService.resync_track_cc(state, track_guid, midi_service, active_tracks_data)
    if not state or not track_guid then return end
    local pms = PedalService.get_pedals_for_track(state, track_guid)
    table.sort(pms, function(a, b) return a.start_qn < b.start_qn end)
    
    local takes_list, trk = PedalService.get_all_takes_for_track(track_guid, active_tracks_data)
    if #takes_list == 0 then return end
    
    reaper.Undo_BeginBlock2(0)
    -- First delete all CC64 on the track
    for _, tinfo in ipairs(takes_list) do
        local tk = tinfo.take
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
        if #to_del > 0 then reaper.MIDI_Sort(tk) end
    end
    
    -- Then rebuild all pedal marks fresh and clean
    for _, pm in ipairs(pms) do
        if pm.apply_cc then
            PedalService.apply_cc(state, pm, midi_service, active_tracks_data)
        end
    end
    reaper.Undo_EndBlock2(0, "Notator: Resync Sustain Pedal CC64", -1)
    state.status_msg = string.format("Resynced CC64 for %d pedal marks on track", #pms)
end

return PedalService

-- ==============================================================================
-- REAPER Native Notator - Service: RepeatService
-- Manages measure repeat marks (simile %, repeat1Bar).
-- Notes from the source measure before the repeat marker (that are not repeat markers themselves)
-- are adopted into the target measure and PHYSICALLY written into the MIDI item.
-- ==============================================================================

local Constants = require("constants")
local MidiService = require("services.midi_service")

local RepeatService = {}

function RepeatService.load_repeat_marks(state)
    state.repeat_marks = {}
    local known = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "repeat_marks")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id         = parts[1]
            local track_guid = parts[2]
            local measure    = tonumber(parts[3])
            local rep_type   = (parts[4] and parts[4] ~= "") and parts[4] or "1bar"
            
            if id and id ~= "" and track_guid and track_guid ~= "" and measure ~= nil then
                local k = track_guid .. "_" .. tostring(measure)
                known[k] = true
                table.insert(state.repeat_marks, {
                    id = id,
                    track_guid = track_guid,
                    measure = measure,
                    type = rep_type
                })
            end
        end
    end

    -- DUAL PERSISTENCE: Read from MIDI takes (Type-15 Notation Events in .RPP)
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
                        if ok and ev_type == 15 and msg:match("^NOTATOR_REPEAT") then
                            local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                            local bpi = 4.0
                            local ts_num, ts_den = reaper.TimeMap_GetTimeSigAtTime(0, reaper.TimeMap2_QNToTime(0, qn))
                            if ts_num and ts_den and ts_den > 0 then bpi = ts_num * (4.0 / ts_den) end
                            local m = math.floor((qn + 0.05) / bpi)
                            local k = trk_guid .. "_" .. tostring(m)
                            if not known[k] then
                                known[k] = true
                                table.insert(state.repeat_marks, {
                                    id = string.format("rep_%s_%d", trk_guid:sub(2,7), m),
                                    track_guid = trk_guid,
                                    measure = m,
                                    type = "1bar"
                                })
                            end
                        end
                    end
                end
            end
        end
    end
end

function RepeatService.parse_notation_event(state, track, take, ppq, msg)
    if not state or not msg then return end
    if not state.repeat_marks then state.repeat_marks = {} end
    local trk_guid = track and reaper.ValidatePtr(track, "MediaTrack*") and reaper.GetTrackGUID(track)
    if not trk_guid then return end
    
    local qn = (take and reaper.MIDI_GetProjQNFromPPQPos(take, ppq)) or 0.0
    local bpi = 4.0
    local ts_num, ts_den = reaper.TimeMap_GetTimeSigAtTime(0, reaper.TimeMap2_QNToTime(0, qn))
    if ts_num and ts_den and ts_den > 0 then bpi = ts_num * (4.0 / ts_den) end
    local m = math.floor((qn + 0.05) / bpi)
    
    for _, rm in ipairs(state.repeat_marks) do
        if rm.track_guid == trk_guid and rm.measure == m then return end
    end
    
    table.insert(state.repeat_marks, {
        id = string.format("rep_%s_%d", trk_guid:sub(2,7), m),
        track_guid = trk_guid,
        measure = m,
        type = "1bar"
    })
end

function RepeatService.save_repeat_marks(state)
    local parts = {}
    for _, rm in ipairs(state.repeat_marks or {}) do
        local entry = string.format("%s|%s|%d|%s",
            rm.id or ("rep_" .. tostring(os.time())),
            rm.track_guid,
            rm.measure,
            rm.type or "1bar"
        )
        table.insert(parts, entry)
    end
    local raw = table.concat(parts, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "repeat_marks", raw)
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    if reaper.Main_UpdateLoopInfo then reaper.Main_UpdateLoopInfo(0) end
end

function RepeatService.has_repeat_mark(state, track_guid, measure)
    if not state or not state.repeat_marks or #state.repeat_marks == 0 or not track_guid or measure == nil then
        return false, nil
    end
    if not state._repeat_marks_map or state._repeat_marks_map_cnt ~= #state.repeat_marks then
        local map = {}
        for _, rm in ipairs(state.repeat_marks) do
            if rm.track_guid and rm.measure ~= nil then
                local tm = map[rm.track_guid]
                if not tm then
                    tm = {}
                    map[rm.track_guid] = tm
                end
                tm[rm.measure] = rm
            end
        end
        state._repeat_marks_map = map
        state._repeat_marks_map_cnt = #state.repeat_marks
    end
    local trk_map = state._repeat_marks_map[track_guid]
    local rm = trk_map and trk_map[measure]
    if rm then return true, rm end
    return false, nil
end

function RepeatService.is_measure_repeated(state, track_guid, measure)
    local has, _ = RepeatService.has_repeat_mark(state, track_guid, measure)
    return has
end

-- Finds source measure for a repeat marker:
-- Goes backwards from measure - 1 to 0 and finds the first measure
-- that IS NOT A REPEAT MARKER ITSELF.
function RepeatService.find_source_measure(state, track_guid, target_measure)
    if target_measure <= 0 then return nil end
    for prev_m = target_measure - 1, 0, -1 do
        if not RepeatService.has_repeat_mark(state, track_guid, prev_m) then
            return prev_m
        end
    end
    return nil
end

-- Calculates QN per measure at given time
local function get_qn_per_measure_at(measure, bpi_default)
    local timesig_num, timesig_denom = reaper.TimeMap_GetTimeSigAtTime(0, 0)
    timesig_num = (timesig_num and timesig_num > 0) and timesig_num or 4
    timesig_denom = (timesig_denom and timesig_denom > 0) and timesig_denom or 4
    return timesig_num * (4.0 / timesig_denom)
end

-- Reads all notes on track within a QN range
function RepeatService.get_notes_in_range(track, start_qn, end_qn)
    local notes = {}
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return notes end
    local num_items = reaper.CountTrackMediaItems(track)
    for i = 0, num_items - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            local _, notecnt, _, textcnt = reaper.MIDI_CountEvts(take)
            
            -- Read articulations
            local art_map = {}
            for ti = 0, textcnt - 1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 then
                    local p, ch, art = msg:match("NOTE%s+(%d+)%s+(%d+)%s+a%s+([%a%d_]+)")
                    if p and art then
                        art_map[string.format("%d_%d", math.floor(ppq+0.5), tonumber(p))] = art
                    end
                end
            end
            
            for ni = 0, notecnt - 1 do
                local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
                if ok and not muted then
                    local n_sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                    local n_eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                    if n_sqn >= (start_qn - 0.01) and n_sqn < (end_qn - 0.01) then
                        local dur = math.max(0.0625, n_eqn - n_sqn)
                        local art = art_map[string.format("%d_%d", math.floor(sppq+0.5), pitch)]
                        table.insert(notes, {
                            pitch = pitch,
                            start_qn = n_sqn,
                            end_qn = n_eqn,
                            dur_qn = dur,
                            vel = vel,
                            chan = chan,
                            articulation = art
                        })
                    end
                end
            end
        end
    end
    return notes
end

-- Physically writes notes of source measure into MIDI item of target measure
function RepeatService.sync_repeat_measure_notes(state, track, target_measure)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") or target_measure == nil then
        return 0
    end
    local track_guid = reaper.GetTrackGUID(track)
    local src_measure = RepeatService.find_source_measure(state, track_guid, target_measure)
    if src_measure == nil then
        return 0
    end
    
    local qn_per_measure = get_qn_per_measure_at(target_measure, 4.0)
    local src_start_qn = src_measure * qn_per_measure
    local src_end_qn = (src_measure + 1) * qn_per_measure
    
    local tgt_start_qn = target_measure * qn_per_measure
    local tgt_end_qn = (target_measure + 1) * qn_per_measure
    local delta_qn = tgt_start_qn - src_start_qn
    
    -- 1. Collect source notes
    local src_notes = RepeatService.get_notes_in_range(track, src_start_qn, src_end_qn)
    if #src_notes == 0 then
        return 0
    end
    
    reaper.Undo_BeginBlock2(0)
    
    -- 2. Locate or create target item/take
    local tgt_item, tgt_take = MidiService.get_or_create_item_at_qn(track, tgt_start_qn, qn_per_measure)
    if not tgt_take or not reaper.ValidatePtr(tgt_take, "MediaItem_Take*") then
        reaper.Undo_EndBlock2(0, "Notator: Repeat Mark sync failed", -1)
        return 0
    end
    
    -- 3. Delete existing notes in target range [tgt_start_qn, tgt_end_qn) to prevent duplicates
    local _, notecnt = reaper.MIDI_CountEvts(tgt_take)
    local to_del = {}
    for ni = 0, notecnt - 1 do
        local ok, _, _, sppq, _, _, _, _ = reaper.MIDI_GetNote(tgt_take, ni)
        if ok then
            local n_sqn = reaper.MIDI_GetProjQNFromPPQPos(tgt_take, sppq)
            if n_sqn >= (tgt_start_qn - 0.02) and n_sqn < (tgt_end_qn - 0.02) then
                table.insert(to_del, ni)
            end
        end
    end
    table.sort(to_del, function(a, b) return a > b end)
    for _, idx in ipairs(to_del) do
        reaper.MIDI_DeleteNote(tgt_take, idx)
    end
    
    -- 4. Copy & insert notes from source measure with time offset delta_qn
    local inserted_cnt = 0
    for _, sn in ipairs(src_notes) do
        local new_sqn = sn.start_qn + delta_qn
        local new_dur = sn.dur_qn
        MidiService.insert_note(tgt_take, new_sqn, sn.pitch, new_dur, sn.vel or 96, sn.chan or 0, sn.articulation)
        inserted_cnt = inserted_cnt + 1
    end
    
    -- Dual Persistence: Store Type-15 Notation Event in take (physically in .RPP)
    local tgt_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tgt_take, tgt_start_qn) + 0.5)
    local _, _, _, text_cnt = reaper.MIDI_CountEvts(tgt_take)
    for ti = text_cnt - 1, 0, -1 do
        local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(tgt_take, ti)
        if ok and etype == 15 and msg:match("^NOTATOR_REPEAT") then
            local eq_qn = reaper.MIDI_GetProjQNFromPPQPos(tgt_take, ppq)
            if math.abs(eq_qn - tgt_start_qn) < 0.5 then
                reaper.MIDI_DeleteTextSysexEvt(tgt_take, ti)
            end
        end
    end
    reaper.MIDI_InsertTextSysexEvt(tgt_take, false, false, tgt_ppq, 15, "NOTATOR_REPEAT 1bar")
    
    reaper.MIDI_Sort(tgt_take)
    reaper.Undo_EndBlock2(0, string.format("Notator: Write %d repeated notes to Bar %d", inserted_cnt, target_measure + 1), -1)
    reaper.UpdateArrange()
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    MidiService.invalidate_cache(track)
    
    return inserted_cnt
end

-- Physically deletes all notes of a measure from MIDI items of track
function RepeatService.clear_measure_notes(track, measure)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") or measure == nil then
        return 0
    end
    local qn_per_measure = get_qn_per_measure_at(measure, 4.0)
    local tgt_start_qn = measure * qn_per_measure
    local tgt_end_qn = (measure + 1) * qn_per_measure
    
    local num_items = reaper.CountTrackMediaItems(track)
    local total_deleted = 0
    
    reaper.Undo_BeginBlock2(0)
    
    for i = 0, num_items - 1 do
        local it = reaper.GetTrackMediaItem(track, i)
        local tk = it and reaper.GetActiveTake(it)
        if tk and reaper.TakeIsMIDI(tk) then
            local _, notecnt = reaper.MIDI_CountEvts(tk)
            local to_del = {}
            for ni = 0, notecnt - 1 do
                local ok, _, _, sppq, _, _, _, _ = reaper.MIDI_GetNote(tk, ni)
                if ok then
                    local n_sqn = reaper.MIDI_GetProjQNFromPPQPos(tk, sppq)
                    if n_sqn >= (tgt_start_qn - 0.02) and n_sqn < (tgt_end_qn - 0.02) then
                        table.insert(to_del, ni)
                    end
                end
            end
            if #to_del > 0 then
                table.sort(to_del, function(a, b) return a > b end)
                for _, idx in ipairs(to_del) do
                    reaper.MIDI_DeleteNote(tk, idx)
                    total_deleted = total_deleted + 1
                end
            end
            
            -- Remove Type-15 NOTATOR_REPEAT Notation Events from take
            local _, _, _, text_cnt = reaper.MIDI_CountEvts(tk)
            local text_del = {}
            for text_i = 0, text_cnt - 1 do
                local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(tk, text_i)
                if ok and ev_type == 15 and msg:match("^NOTATOR_REPEAT") then
                    local n_sqn = reaper.MIDI_GetProjQNFromPPQPos(tk, ppq)
                    if n_sqn >= (tgt_start_qn - 0.02) and n_sqn < (tgt_end_qn - 0.02) then
                        table.insert(text_del, text_i)
                    end
                end
            end
            if #text_del > 0 then
                table.sort(text_del, function(a, b) return a > b end)
                for _, idx in ipairs(text_del) do
                    reaper.MIDI_DeleteTextSysexEvt(tk, idx)
                end
            end
            
            if #to_del > 0 or #text_del > 0 then
                reaper.MIDI_Sort(tk)
            end
        end
    end
    
    reaper.Undo_EndBlock2(0, string.format("Notator: Clear %d notes from Bar %d", total_deleted, measure + 1), -1)
    reaper.UpdateArrange()
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    MidiService.invalidate_cache(track)
    
    return total_deleted
end

-- Removes a repeat marker and deletes notes within it from MIDI item
function RepeatService.remove_repeat_mark(state, track, measure)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") or measure == nil then return 0 end
    local track_guid = reaper.GetTrackGUID(track)
    local has, _ = RepeatService.has_repeat_mark(state, track_guid, measure)
    if has then
        local new_list = {}
        for _, rm in ipairs(state.repeat_marks or {}) do
            if not (rm.track_guid == track_guid and rm.measure == measure) then
                table.insert(new_list, rm)
            end
        end
        state.repeat_marks = new_list
        RepeatService.save_repeat_marks(state)
        
        -- Physically remove MIDI notes from MIDI item!
        local del_cnt = RepeatService.clear_measure_notes(track, measure)
        state.status_msg = string.format("Bar %d: Repeat mark (%%) removed (%d notes cleared from MIDI item)", measure + 1, del_cnt)
        return del_cnt
    end
    return 0
end

-- Toggles a repeat marker on a measure (create or delete)
function RepeatService.toggle_repeat_mark(state, track, measure, active_tracks_data)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") or measure == nil then return end
    local track_guid = reaper.GetTrackGUID(track)
    local has, existing_rm = RepeatService.has_repeat_mark(state, track_guid, measure)
    
    if has then
        -- Remove including physical deletion of notes in MIDI item
        RepeatService.remove_repeat_mark(state, track, measure)
    else
        -- Add
        local new_rm = {
            id = string.format("rep_%d_%d", os.time(), math.random(100, 999)),
            track_guid = track_guid,
            measure = measure,
            type = "1bar"
        }
        table.insert(state.repeat_marks, new_rm)
        RepeatService.save_repeat_marks(state)
        
        -- Physically write MIDI notes into MIDI item!
        local cnt = RepeatService.sync_repeat_measure_notes(state, track, measure)
        state.status_msg = string.format("Bar %d: Repeat mark (%%) set (%d MIDI notes generated from preceding bar)", measure + 1, cnt)
    end
end

-- Synchronizes all repeat markers across all tracks (e.g. after note edits)
function RepeatService.sync_all(state)
    if not state.repeat_marks or #state.repeat_marks == 0 then
        state.status_msg = "No Repeat Marks in project to sync."
        return
    end
    -- Sort ascending by measure number so chains of repeats cascade properly
    local sorted = {}
    for _, rm in ipairs(state.repeat_marks) do table.insert(sorted, rm) end
    table.sort(sorted, function(a, b) return a.measure < b.measure end)
    
    local total_synced = 0
    for _, rm in ipairs(sorted) do
        -- Find MediaTrack
        local num_tracks = reaper.CountTracks(0)
        local target_track = nil
        for t = 0, num_tracks - 1 do
            local trk = reaper.GetTrack(0, t)
            if trk and reaper.GetTrackGUID(trk) == rm.track_guid then
                target_track = trk
                break
            end
        end
        if target_track then
            local cnt = RepeatService.sync_repeat_measure_notes(state, target_track, rm.measure)
            total_synced = total_synced + cnt
        end
    end
    state.status_msg = string.format("Synced %d repeated measures (%d total notes)", #sorted, total_synced)
end

return RepeatService

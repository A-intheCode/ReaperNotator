-- ==============================================================================
-- REAPER Native Notator - Service: FermataService
-- Manages score-wide vertical fermatas with tempomap coupling & dual-persistence
-- ==============================================================================

local Fermata = require("classes.fermata")

local FermataService = {}

function FermataService.load_fermatas(state)
    state.fermatas = {}
    local known = {}

    -- 1. Load from Project Ext State
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "fermatas")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id = parts[1]
            local qn = tonumber(parts[2])
            if id and id ~= "" and qn ~= nil then
                local ferm = Fermata.new({
                    id            = id,
                    qn            = qn,
                    measure       = tonumber(parts[3]) or 0,
                    beat_rel      = tonumber(parts[4]) or 0.0,
                    type          = (parts[5] and parts[5] ~= "") and parts[5] or "standard",
                    hold_factor   = tonumber(parts[6]) or 1.5,
                    playback_mode = (parts[7] and parts[7] ~= "") and parts[7] or "tempo_curve",
                    duration_qn   = tonumber(parts[8]) or 1.0
                })
                table.insert(state.fermatas, ferm)
                local k = string.format("%.2f", qn)
                known[k] = true
            end
        end
    end

    -- 2. DUAL PERSISTENCE: Scan active MIDI takes for Type-15 Notation Events
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                    for text_i = 0, text_cnt - 1 do
                        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
                        if ok and ev_type == 15 and msg:match("^NOTATOR_FERMATA") then
                            local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                            local k = string.format("%.2f", qn)
                            if not known[k] then
                                known[k] = true
                                local f_type, h_fac = msg:match("^NOTATOR_FERMATA%s+([%w_]+)%s*([%d%.]*)")
                                local bpi = 4.0
                                local ts_num, ts_den = reaper.TimeMap_GetTimeSigAtTime(0, reaper.TimeMap2_QNToTime(0, qn))
                                if ts_num and ts_den and ts_den > 0 then bpi = ts_num * (4.0 / ts_den) end
                                local m = math.floor((qn + 0.01) / bpi)
                                local beat = qn - (m * bpi)

                                local ferm = Fermata.new({
                                    id            = string.format("ferm_%d", math.floor(qn * 100)),
                                    qn            = qn,
                                    measure       = m,
                                    beat_rel      = beat,
                                    type          = f_type or "standard",
                                    hold_factor   = tonumber(h_fac) or 1.5,
                                    playback_mode = "tempo_curve",
                                    duration_qn   = 1.0
                                })
                                table.insert(state.fermatas, ferm)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Sort chronologically
    table.sort(state.fermatas, function(a, b) return a.qn < b.qn end)
end

function FermataService.save_fermatas(state)
    if not state.fermatas then return end
    local entries = {}
    for _, f in ipairs(state.fermatas) do
        table.insert(entries, string.format("%s|%.3f|%d|%.3f|%s|%.2f|%s|%.3f",
            f.id or "",
            f.qn or 0.0,
            f.measure or 0,
            f.beat_rel or 0.0,
            f.type or "standard",
            f.hold_factor or 1.5,
            f.playback_mode or "tempo_curve",
            f.duration_qn or 1.0
        ))
    end
    reaper.SetProjExtState(0, "REAPER_Notator", "fermatas", table.concat(entries, ";"))
end

function FermataService.add_fermata(state, qn, f_type, hold_factor, active_tracks_data, duration_qn, playback_mode)
    if not state.fermatas then state.fermatas = {} end
    f_type = f_type or "standard"
    hold_factor = hold_factor or 1.5
    playback_mode = playback_mode or "tempo_curve"

    -- Auto-detect note duration if duration_qn was not passed
    if not duration_qn or duration_qn <= 0.001 then
        duration_qn = 1.0
        if active_tracks_data then
            for _, td in ipairs(active_tracks_data) do
                if td.notes then
                    for _, n in ipairs(td.notes) do
                        if math.abs(n.start_qn - qn) < 0.15 then
                            duration_qn = n.dur_qn or 1.0
                            break
                        end
                    end
                end
            end
        end
    end

    -- Remove any existing fermata at virtually the same QN
    FermataService.remove_fermata_at_qn(state, qn, active_tracks_data)

    local bpi = 4.0
    local ts_num, ts_den = reaper.TimeMap_GetTimeSigAtTime(0, reaper.TimeMap2_QNToTime(0, qn))
    if ts_num and ts_den and ts_den > 0 then bpi = ts_num * (4.0 / ts_den) end
    local m = math.floor((qn + 0.01) / bpi)
    local beat = qn - (m * bpi)

    local ferm = Fermata.new({
        id            = string.format("ferm_%d_%d", math.floor(qn * 100), math.random(1000, 9999)),
        qn            = qn,
        measure       = m,
        beat_rel      = beat,
        type          = f_type,
        hold_factor   = hold_factor,
        playback_mode = playback_mode,
        duration_qn   = duration_qn
    })
    table.insert(state.fermatas, ferm)
    table.sort(state.fermatas, function(a, b) return a.qn < b.qn end)

    -- Write Type-15 events across all tracks that span this QN
    FermataService.sync_takes_for_fermata(ferm, active_tracks_data, false)

    FermataService.save_fermatas(state)

    -- Synchronize REAPER Tempomap (reliably invoke sync_all_to_reaper or sync_to_reaper)
    local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
    if TempoService then
        if TempoService.sync_all_to_reaper then
            TempoService.sync_all_to_reaper(state)
        elseif TempoService.sync_to_reaper then
            TempoService.sync_to_reaper(state)
        end
    end

    state.status_msg = string.format("Added %s Fermata at Bar %d (Beat %.1f, Hold %.1fx)", f_type, m + 1, beat + 1, hold_factor)
    return ferm
end

function FermataService.remove_fermata(state, ferm_id, active_tracks_data)
    if not state.fermatas then return end
    local target_ferm = nil
    local rem_idx = nil
    for idx, f in ipairs(state.fermatas) do
        if f.id == ferm_id then
            target_ferm = f
            rem_idx = idx
            break
        end
    end

    if target_ferm and rem_idx then
        -- Clean up Type-15 events across takes
        FermataService.sync_takes_for_fermata(target_ferm, active_tracks_data, true)
        table.remove(state.fermatas, rem_idx)
        FermataService.save_fermatas(state)

        -- Synchronize REAPER Tempomap
        local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
        if TempoService then
            if TempoService.sync_all_to_reaper then
                TempoService.sync_all_to_reaper(state)
            elseif TempoService.sync_to_reaper then
                TempoService.sync_to_reaper(state)
            end
        end
        state.status_msg = "Removed Fermata"
    end
end

function FermataService.remove_fermata_at_qn(state, qn, active_tracks_data)
    if not state.fermatas then return end
    for idx = #state.fermatas, 1, -1 do
        local f = state.fermatas[idx]
        if math.abs(f.qn - qn) < 0.25 then
            FermataService.remove_fermata(state, f.id, active_tracks_data)
        end
    end
end

function FermataService.sync_takes_for_fermata(ferm, active_tracks_data, is_remove)
    local qn = ferm.qn
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local ipos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local ilen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local item_sqn = reaper.TimeMap2_timeToQN(0, ipos)
                local item_eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)

                if qn >= item_sqn - 0.05 and qn <= item_eqn + 0.05 then
                    local take = reaper.GetActiveTake(item)
                    if take and reaper.TakeIsMIDI(take) then
                        local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, qn) + 0.5)

                        -- Clean existing fermata events near this position
                        local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                        for text_i = text_cnt - 1, 0, -1 do
                            local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
                            if ok and ev_type == 15 and msg:match("^NOTATOR_FERMATA") then
                                if math.abs(ppq - sppq) < 50 then
                                    reaper.MIDI_DeleteTextSysexEvt(take, text_i)
                                end
                            end
                        end

                        if not is_remove then
                            local tag_msg = string.format("NOTATOR_FERMATA %s %.2f", ferm.type or "standard", ferm.hold_factor or 1.5)
                            reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, tag_msg)

                            -- Also tag sounding notes with native notation articulation
                            local _, notecnt = reaper.MIDI_CountEvts(take)
                            for ni = 0, notecnt - 1 do
                                local nok, _, _, n_sppq, n_eppq, chan, pitch = reaper.MIDI_GetNote(take, ni)
                                if nok and sppq >= n_sppq - 10 and sppq < n_eppq then
                                    reaper.MIDI_InsertTextSysexEvt(take, false, false, n_sppq, 15, string.format("NOTE %d %d a fermata", pitch, chan))
                                end
                            end
                        end
                        reaper.MIDI_Sort(take)
                    end
                end
            end
        end
    end
end

function FermataService.get_fermata_at_qn(state, qn, tolerance)
    if not state.fermatas then return nil end
    local tol = tolerance or 0.25
    for _, f in ipairs(state.fermatas) do
        if math.abs(f.qn - qn) <= tol then
            return f
        end
    end
    return nil
end

return FermataService

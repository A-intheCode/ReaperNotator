-- ==============================================================================
-- REAPER Native Notator - Service: RecordQuantizeService
-- Auto-quantizes recorded MIDI takes on armed tracks upon recording stop:
-- - Cleans keyboard bounces and same-pitch overlapping notes
-- - Snaps onsets within tick tolerance to selected metric grid (e.g. 1/8 @ 25 ticks)
-- - Configurable outlier handling (keep unquantized / delete / route to Voice 16)
-- ==============================================================================

local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")

local RecordQuantizeService = {}

RecordQuantizeService.GRIDS = {
    { label = "1/1  (Whole)",   qn = 4.0 },
    { label = "1/2  (Half)",    qn = 2.0 },
    { label = "1/4  (Quarter)", qn = 1.0 },
    { label = "1/8  (Eighth)",  qn = 0.5 },
    { label = "1/16 (16th)",    qn = 0.25 },
    { label = "1/32 (32nd)",    qn = 0.125 },
    { label = "1/64 (64th)",    qn = 0.0625 },
}

--- Resolves all MIDI takes recorded during the session on armed tracks
--- @param state table
--- @param start_time number Project time when recording started
--- @param stop_time number Project time when recording stopped
--- @return table takes Array of MediaItem_Take*
function RecordQuantizeService.get_recorded_takes(state, start_time, stop_time)
    local takes = {}
    local seen = {}

    -- Tolerance window around recording times (default to current project bounds if not specified)
    start_time = start_time or (reaper.GetCursorPosition() - 60.0)
    stop_time = stop_time or (reaper.GetCursorPosition() + 2.0)
    if stop_time < start_time then
        start_time, stop_time = stop_time, start_time
    end

    local trk_cnt = reaper.CountTracks(0)
    for ti = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            local is_armed = (reaper.GetMediaTrackInfo_Value(trk, "I_RECARM") == 1)
            -- Process armed tracks, or all tracks if items were explicitly recorded
            if is_armed then
                local it_cnt = reaper.CountTrackMediaItems(trk)
                for ii = 0, it_cnt - 1 do
                    local it = reaper.GetTrackMediaItem(trk, ii)
                    if it and reaper.ValidatePtr(it, "MediaItem*") then
                        local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                        local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                        local iend = ipos + ilen
                        
                        -- Item intersects recording interval or was selected/created during record
                        local is_in_rec = (ipos < stop_time + 1.0) and (iend > start_time - 1.0)
                        if is_in_rec or reaper.IsMediaItemSelected(it) then
                            local take = reaper.GetActiveTake(it)
                            if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
                                if not seen[take] then
                                    seen[take] = true
                                    table.insert(takes, take)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return takes
end

--- Processes recorded takes with auto-quantize and overlap resolution
--- @param state table
--- @param start_time number
--- @param stop_time number
--- @return table stats
function RecordQuantizeService.process_recording(state, start_time, stop_time)
    if state.rec_auto_quantize == false then
        return { total_notes = 0, snapped = 0, cleaned = 0, outliers_handled = 0 }
    end

    local base_grid_qn = state.rec_quantize_grid_qn or 0.5
    local grid_type = state.rec_quantize_grid_type or "straight"
    local tolerance_ticks = state.rec_tolerance_ticks or 25
    local clean_overlaps = (state.rec_clean_overlaps ~= false)
    local outlier_mode = state.rec_outlier_mode or "keep" -- "keep" | "delete" | "voice16"

    local eff_grid = base_grid_qn
    if grid_type == "triplet" then
        eff_grid = base_grid_qn * (2.0 / 3.0)
    elseif grid_type == "dotted" then
        eff_grid = base_grid_qn * 1.5
    end
    if eff_grid <= 0.001 then eff_grid = 0.5 end

    local takes = RecordQuantizeService.get_recorded_takes(state, start_time, stop_time)
    if #takes == 0 then
        -- Fallback: check active take
        local at = MidiService.get_active_midi_take()
        if at and reaper.TakeIsMIDI(at) then
            table.insert(takes, at)
        end
    end

    if #takes == 0 then
        return { total_notes = 0, snapped = 0, cleaned = 0, outliers_handled = 0 }
    end

    reaper.Undo_BeginBlock2(0)

    local total_notes = 0
    local total_snapped = 0
    local total_cleaned = 0
    local total_outliers = 0

    for _, take in ipairs(takes) do
        reaper.MIDI_DisableSort(take)
        local _, notecnt = reaper.MIDI_CountEvts(take)
        total_notes = total_notes + notecnt

        -- 1. Read all notes into structured list
        local notes = {}
        for i = 0, notecnt - 1 do
            local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
            if ok then
                table.insert(notes, {
                    idx = i,
                    sel = sel,
                    muted = muted,
                    sppq = sppq,
                    eppq = eppq,
                    chan = chan,
                    pitch = pitch,
                    vel = vel,
                    action = "keep" -- "keep" | "delete" | "modify"
                })
            end
        end

        -- 2. Group notes by pitch to resolve keyboard pre-bounce & same-pitch overlaps
        if clean_overlaps then
            local by_pitch = {}
            for _, n in ipairs(notes) do
                if not by_pitch[n.pitch] then by_pitch[n.pitch] = {} end
                table.insert(by_pitch[n.pitch], n)
            end

            for pitch, p_notes in pairs(by_pitch) do
                table.sort(p_notes, function(a, b) return a.sppq < b.sppq end)
                for k = 1, #p_notes - 1 do
                    local n1 = p_notes[k]
                    local n2 = p_notes[k + 1]
                    
                    if n1.action ~= "delete" and n2.action ~= "delete" then
                        -- Detection A: Key bounce (starts within 15 ticks on exact same pitch)
                        if math.abs(n2.sppq - n1.sppq) < 15 then
                            -- Keep the note with greater velocity, delete the weaker bounce artifact
                            if n2.vel > n1.vel then
                                n1.action = "delete"
                            else
                                n2.action = "delete"
                            end
                            total_cleaned = total_cleaned + 1
                        -- Detection B: Overlapping note tails on same pitch
                        elseif n1.eppq >= n2.sppq then
                            -- Clamp prior note's end to 1 tick before subsequent note onset
                            local clamped_eppq = math.max(n1.sppq + 20, n2.sppq - 1)
                            if clamped_eppq < n1.eppq then
                                n1.eppq = clamped_eppq
                                n1.action = "modify"
                                total_cleaned = total_cleaned + 1
                            end
                        end
                    end
                end
            end
        end

        -- 3. Metric Grid Snapping within Tolerance & Outlier Handling
        for _, n in ipairs(notes) do
            if n.action ~= "delete" then
                local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, n.sppq)
                local eqn = reaper.MIDI_GetProjQNFromPPQPos(take, n.eppq)
                local orig_dur_qn = math.max(0.05, eqn - sqn)

                -- Calculate measure-relative alignment
                local _, qn_measure_start, _ = reaper.TimeMap_QNToMeasures(0, sqn)
                local rel_qn = sqn - qn_measure_start
                local nearest_k = math.floor((rel_qn / eff_grid) + 0.5)
                local nearest_grid_qn = qn_measure_start + (nearest_k * eff_grid)
                local diff_qn = math.abs(sqn - nearest_grid_qn)
                local diff_ticks = diff_qn * 960.0

                -- Floating point epsilon
                if diff_ticks < 0.05 then
                    diff_ticks = 0.0
                end

                if diff_ticks <= (tolerance_ticks + 0.05) then
                    -- Note is within tolerance radius -> Snap onset to grid line
                    local new_sqn = math.max(0, nearest_grid_qn)
                    local new_eqn = new_sqn + orig_dur_qn
                    local new_sppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_sqn)
                    local new_eppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_eqn)

                    n.sppq = new_sppq
                    n.eppq = new_eppq
                    n.action = "modify"
                    total_snapped = total_snapped + 1
                else
                    -- Outlier outside tolerance radius
                    if outlier_mode == "delete" then
                        n.action = "delete"
                        total_outliers = total_outliers + 1
                    elseif outlier_mode == "voice16" then
                        n.chan = 15 -- Voice 16 in REAPER multi-voice notation (0-indexed channel 15)
                        n.action = "modify"
                        total_outliers = total_outliers + 1
                    else
                        -- "keep": Leave unquantized
                    end
                end
            end
        end

        -- 4. Apply changes to take: Delete backwards, update modified
        for i = #notes, 1, -1 do
            local n = notes[i]
            if n.action == "delete" then
                reaper.MIDI_DeleteNote(take, n.idx)
            elseif n.action == "modify" then
                reaper.MIDI_SetNote(take, n.idx, n.sel, n.muted, n.sppq, n.eppq, n.chan, n.pitch, n.vel, true)
            end
        end

        reaper.MIDI_Sort(take)
    end

    reaper.Undo_EndBlock2(0, "Auto-Quantize Recorded MIDI", -1)

    -- Invalidate score canvas cache for immediate visual update
    MidiService.invalidate_cache()

    local stats = {
        total_notes = total_notes,
        snapped = total_snapped,
        cleaned = total_cleaned,
        outliers_handled = total_outliers
    }

    if total_notes > 0 then
        state.status_msg = string.format("⚡ Auto-Quantize: %d notes processed (%d snapped to %s, %d overlaps cleaned)",
            total_notes, total_snapped, state.rec_quantize_grid_label or "1/8", total_cleaned)
    end

    return stats
end

return RecordQuantizeService

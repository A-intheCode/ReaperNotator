-- ==============================================================================
-- REAPER Native Notator - Service: TempoService
-- Management, storage, and synchronization of tempo markings
-- (Absolute tempi & gradual transitions with dual handles)
-- ==============================================================================

local TempoMarker = require("classes.tempo_marker")

local TempoService = {}

function TempoService.load_markers(state)
    state.tempo_markers = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "tempo_markers")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for part in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, part)
            end
            local id, m_type = parts[1], parts[2]
            if id and id ~= "" and m_type and m_type ~= "" then
                local tm = TempoMarker.new({
                    id                = id,
                    type              = m_type,
                    label             = parts[3] or "",
                    modifier          = parts[4] or "",
                    bpm               = tonumber(parts[5]) or 120,
                    start_qn          = tonumber(parts[6]) or 0.0,
                    end_qn            = tonumber(parts[7]) or 4.0,
                    target_bpm        = tonumber(parts[8]) or nil,
                    custom_bpm_only   = (not parts[3] or parts[3] == ""),
                    custom_target_bpm = (parts[9] == "1")
                })
                table.insert(state.tempo_markers, tm)
            end
        end
    end
    
    -- If no markers were stored in Notator yet:
    -- Initialize from existing REAPER tempo markers or project tempo
    if #state.tempo_markers == 0 then
        local cnt = reaper.CountTempoTimeSigMarkers(0)
        if cnt > 0 then
            for i = 0, cnt - 1 do
                local ok, tpos, _, _, bpm, ts_n, ts_d, lin = reaper.GetTempoTimeSigMarker(0, i)
                if ok then
                    local qn = reaper.TimeMap2_timeToQN(0, tpos)
                    local tm = TempoMarker.new({
                        type            = "absolute",
                        label           = (i == 0 and "Allegro" or ""),
                        bpm             = bpm,
                        start_qn        = qn,
                        end_qn          = qn + 4.0,
                        custom_bpm_only = (i > 0)
                    })
                    table.insert(state.tempo_markers, tm)
                end
            end
        else
            local cur_bpm = reaper.Master_GetTempo() or 120
            local tm = TempoMarker.new({
                type            = "absolute",
                label           = "Allegro",
                bpm             = cur_bpm,
                start_qn        = 0.0,
                end_qn          = 4.0,
                custom_bpm_only = false
            })
            table.insert(state.tempo_markers, tm)
        end
    end
    
    -- Only if an absolute starting marker is very close to beginning (<= 0.5 QN),
    -- snap it exactly to the beginning at measure 1.1 (0.0):
    for _, tm in ipairs(state.tempo_markers or {}) do
        if tm.type == "absolute" and tm.start_qn > 0.0 and tm.start_qn <= 0.5 then
            tm.start_qn = 0.0
            tm.end_qn = math.max(tm.end_qn or 4.0, 4.0)
            break
        end
    end
    
    -- Synchronize all markers with REAPER on load
    TempoService.sync_all_to_reaper(state)
end

function TempoService.save_markers(state)
    local entries = {}
    for _, tm in ipairs(state.tempo_markers or {}) do
        local line = string.format("%s|%s|%s|%s|%.2f|%.3f|%.3f|%.2f|%s",
            tm.id, tm.type, tm.label or "", tm.modifier or "", tm.bpm or 120, tm.start_qn or 0, tm.end_qn or 4, tm.target_bpm or 0, tm.custom_target_bpm and "1" or "0")
        table.insert(entries, line)
    end
    local raw = table.concat(entries, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "tempo_markers", raw)
    if reaper.Main_UpdateLoopInfo then reaper.Main_UpdateLoopInfo(0) end
end

-- Checks whether an active Notator marker exists at a specific QN position
function TempoService.is_notator_tempo_marker_qn(state, qn, tol, exclude_tm)
    if not state or not state.tempo_markers or not qn then return false end
    local t = tol or 0.20
    for _, tm in ipairs(state.tempo_markers) do
        if tm ~= exclude_tm then
            if tm.type == "absolute" and math.abs(tm.start_qn - qn) <= t then
                return true, tm
            elseif tm.type == "gradual" then
                if math.abs(tm.start_qn - qn) <= t or math.abs(tm.end_qn - qn) <= t then
                    return true, tm
                end
            end
        end
    end
    return false
end

-- Calculates the exact, musically effective tempo at any QN position
-- based on all active markers in Notator (including custom BPMs and transitions)
function TempoService.get_tempo_at_qn(state, target_qn, exclude_tm)
    target_qn = target_qn or 0.0
    if not state or not state.tempo_markers or #state.tempo_markers == 0 then
        local t_pos = reaper.TimeMap2_QNToTime(0, target_qn)
        local _, _, bpm = reaper.TimeMap_GetTimeSigAtTime(0, t_pos)
        return (bpm and bpm > 0) and bpm or (reaper.Master_GetTempo() or 120)
    end
    
    local markers = {}
    for _, tm in ipairs(state.tempo_markers) do
        if tm ~= exclude_tm then
            table.insert(markers, tm)
        end
    end
    table.sort(markers, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.001 then
            return a.start_qn < b.start_qn
        end
        if a.type ~= b.type then
            return a.type == "absolute"
        end
        return false
    end)
    
    local effective_bpm = 120
    for _, tm in ipairs(markers) do
        if tm.type == "absolute" and tm.bpm and tm.bpm > 0 then
            effective_bpm = tm.bpm
            break
        end
    end
    
    for _, tm in ipairs(markers) do
        if tm.type == "absolute" then
            if tm.start_qn <= target_qn + 0.01 then
                effective_bpm = tm.bpm or effective_bpm
            else
                break
            end
        elseif tm.type == "gradual" then
            if target_qn >= (tm.end_qn - 0.01) then
                effective_bpm = tm.target_bpm or effective_bpm
            elseif target_qn > (tm.start_qn + 0.01) and tm.end_qn > tm.start_qn then
                local alpha = (target_qn - tm.start_qn) / (tm.end_qn - tm.start_qn)
                alpha = math.max(0.0, math.min(1.0, alpha))
                local s_bpm = tm.bpm or effective_bpm
                local t_bpm = tm.target_bpm or effective_bpm
                effective_bpm = s_bpm + alpha * (t_bpm - s_bpm)
            end
        end
    end
    
    return math.max(20, math.min(360, math.floor(effective_bpm + 0.5)))
end

-- Finds a REAPER tempo marker by QN position (tolerance: 1/16 note = 0.25 QN)
function TempoService.find_reaper_tempo_marker_idx(target_qn)
    if not target_qn then return nil end
    local cnt = reaper.CountTempoTimeSigMarkers(0)
    local best_idx = nil
    local best_dist = 0.25
    for i = 0, cnt - 1 do
        local ok, timepos = reaper.GetTempoTimeSigMarker(0, i)
        if ok then
            local m_qn = reaper.TimeMap2_timeToQN(0, timepos)
            local dist = math.abs(m_qn - target_qn)
            if dist < best_dist then
                best_dist = dist
                best_idx = i
            end
        end
    end
    return best_idx
end

-- Calculates target tempo for gradual tempo changes according to standard music practice
function TempoService.calc_gradual_target_bpm(term, modifier, start_bpm)
    local t = (term or ""):lower()
    local is_accel = (t:find("accel") or t:find("string") or t:find("precip"))
    local factor = 0.20
    if modifier == "poco" then
        factor = 0.10
    elseif modifier == "molto" then
        factor = 0.35
    end
    
    local target = is_accel and (start_bpm * (1.0 + factor)) or (start_bpm * (1.0 - factor))
    return math.max(30, math.min(360, math.floor(target + 0.5)))
end

-- Smoothly moves a fixed tempo marker in REAPER and Notator
function TempoService.move_absolute_tempo_marker(state, tm, new_qn, prev_qn)
    if not tm or not new_qn then return end
    tm.start_qn = math.max(0.0, new_qn)
    tm.end_qn = tm.start_qn + 4.0
    TempoService.save_markers(state)
    TempoService.sync_all_to_reaper(state)
end

function TempoService.update_marker_bounds(state, tm, new_start_qn, new_end_qn, orig_start_qn, orig_end_qn)
    if not tm then return end
    if new_start_qn then
        tm.start_qn = math.max(0.0, new_start_qn)
        if tm.type == "absolute" then
            tm.end_qn = tm.start_qn + 4.0
        end
    end
    if new_end_qn then
        tm.end_qn = math.max(tm.start_qn + 0.25, new_end_qn)
    end
    TempoService.save_markers(state)
    TempoService.sync_all_to_reaper(state)
end

function TempoService.sync_reaper_gradual(state, tm, old_start_qn, old_end_qn)
    if not tm then return end
    TempoService.sync_all_to_reaper(state)
end

function TempoService.clean_all_duplicate_tempo_markers(state)
    if state then
        TempoService.sync_all_to_reaper(state)
    end
end

function TempoService.clear_reaper_tempo_range_qn(state_or_min, min_or_max, max_or_k1, k1_or_k2, k2_or_ex, ex_tm)
    local state = type(state_or_min) == "table" and state_or_min or nil
    if state then
        TempoService.sync_all_to_reaper(state)
    end
end

function TempoService.clean_redundant_following_markers(state_or_from, from_or_tbpm, tbpm_or_max, max_qn)
    local state = type(state_or_from) == "table" and state_or_from or nil
    if state then
        TempoService.sync_all_to_reaper(state)
    end
end

function TempoService.delete_reaper_gradual(state, start_qn, end_qn, tm)
    TempoService.sync_all_to_reaper(state)
end

function TempoService.delete_reaper_tempo_marker(state, start_qn, tm)
    TempoService.sync_all_to_reaper(state)
end

function TempoService.add_tempo_marker(state, data)
    state.tempo_markers = state.tempo_markers or {}
    local bpi = (state.time_sig_num and state.time_sig_num > 0) and state.time_sig_num or 4.0
    
    -- If a tempo marker is currently focused/selected and no note is selected, update it directly
    local m_type = data.type or "absolute"
    if state.selected_tempo_marker and not state.selected_note and (data.type == nil or data.type == state.selected_tempo_marker.type) then
        local tm = state.selected_tempo_marker
        tm.bpm = data.bpm or tm.bpm
        tm.label = data.label or tm.label
        tm.modifier = data.modifier or tm.modifier
        if data.target_bpm then tm.target_bpm = data.target_bpm end
        tm.custom_bpm_only = (data.custom_bpm_only == true)
        TempoService.save_markers(state)
        TempoService.sync_all_to_reaper(state)
        reaper.Undo_OnStateChange2(0, "Notator: Update Tempo Marker")
        state.status_msg = string.format("Tempo '%s' updated & synced to REAPER tempo map", tm:get_display_text())
        return tm
    end

    local start_qn = 0.0
    if state.selected_note then
        start_qn = state.selected_note.start_qn
    else
        local cursor_pos = reaper.GetCursorPosition()
        start_qn = reaper.TimeMap2_timeToQN(0, cursor_pos)
    end
    
    if state.grid_qn and state.grid_qn > 0.001 then
        start_qn = math.floor((start_qn / state.grid_qn) + 0.5) * state.grid_qn
    end
    if start_qn < 0 then start_qn = 0 end
    
    local has_initial_marker = false
    for _, em in ipairs(state.tempo_markers) do
        if em.start_qn <= 0.05 then
            has_initial_marker = true
            break
        end
    end
    
    if not state.selected_note and not has_initial_marker and start_qn <= 0.5 then
        start_qn = 0.0
    end
    
    local end_qn = start_qn + (data.dur_qn or bpi)
    
    -- Determine effective tempo at start point from Notator state:
    local context_bpm = TempoService.get_tempo_at_qn(state, start_qn)
    local bpm = (m_type == "absolute") and (data.bpm or context_bpm) or context_bpm
    local target_bpm = nil
    if m_type == "gradual" then
        target_bpm = data.target_bpm or TempoService.calc_gradual_target_bpm(data.label or "accel.", data.modifier or "", bpm)
    end
    
    -- If a marker of the same type exists at this position: overwrite it directly
    local existing_tm = nil
    for _, em in ipairs(state.tempo_markers) do
        if em.type == m_type and math.abs(em.start_qn - start_qn) < 0.25 then
            existing_tm = em
            break
        end
    end
    
    local tm = existing_tm
    if tm then
        tm.bpm = bpm
        tm.label = data.label or tm.label
        tm.modifier = data.modifier or ""
        tm.target_bpm = target_bpm
        tm.custom_bpm_only = (data.custom_bpm_only == true)
    else
        tm = TempoMarker.new({
            type            = m_type,
            label           = data.label or "Allegro",
            modifier        = data.modifier or "",
            bpm             = bpm,
            target_bpm      = target_bpm,
            start_qn        = start_qn,
            end_qn          = end_qn,
            custom_bpm_only = (data.custom_bpm_only == true)
        })
        table.insert(state.tempo_markers, tm)
    end
    
    state.selected_tempo_marker = tm
    TempoService.save_markers(state)
    
    -- Synchronize completely and consistently with REAPER
    TempoService.sync_all_to_reaper(state)
    reaper.Undo_OnStateChange2(0, "Notator: Add Tempo Marker")
    
    state.status_msg = string.format("Tempo '%s' set & synced to REAPER tempo map", tm:get_display_text())
    return tm
end

function TempoService.set_custom_bpm(state, tm, new_bpm)
    if not tm then return end
    
    if tm.type == "gradual" then
        tm.target_bpm = tonumber(new_bpm) or tm.target_bpm
        tm.custom_target_bpm = true
        state.status_msg = string.format("Target tempo adjusted to %d BPM", math.floor(tm.target_bpm))
    else
        tm.bpm = tonumber(new_bpm) or tm.bpm
        tm.label = ""
        tm.custom_bpm_only = true
        state.status_msg = string.format("Tempo overwritten to ♩ = %d", math.floor(tm.bpm))
    end
    
    TempoService.save_markers(state)
    TempoService.sync_all_to_reaper(state)
    reaper.Undo_OnStateChange2(0, "Notator: Adjust Tempo")
end

function TempoService.delete_selected_tempo_marker(state)
    if not state.selected_tempo_marker or not state.tempo_markers then return false end
    local sel_id = state.selected_tempo_marker.id
    for idx, tm in ipairs(state.tempo_markers) do
        if tm.id == sel_id then
            table.remove(state.tempo_markers, idx)
            state.selected_tempo_marker = nil
            TempoService.save_markers(state)
            TempoService.sync_all_to_reaper(state)
            reaper.Undo_OnStateChange2(0, "Notator: Delete Tempo Marker")
            state.status_msg = "Tempo marker and REAPER marker deleted"
            return true
        end
    end
    return false
end

-- Synchronizes all Notator tempo markers with REAPER's timeline
-- Links consecutive tempi seamlessly and guarantees clean interpolation without ghost points
function TempoService.sync_all_to_reaper(state)
    if not state or not state.tempo_markers then return end
    
    -- 1. Sort Notator markers chronologically by start_qn
    table.sort(state.tempo_markers, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.001 then
            return a.start_qn < b.start_qn
        end
        if a.type ~= b.type then
            return a.type == "absolute"
        end
        return false
    end)
    
    -- 2. Determine target musical tempo points for REAPER
    local target_points = {}
    
    -- Ensure a starting point exists at 0.0
    local has_start_0 = false
    for _, tm in ipairs(state.tempo_markers) do
        if tm.start_qn <= 0.05 then
            has_start_0 = true
            break
        end
    end
    if not has_start_0 then
        local first_bpm = 120
        if #state.tempo_markers > 0 and state.tempo_markers[1].bpm then
            first_bpm = state.tempo_markers[1].bpm
        else
            first_bpm = reaper.Master_GetTempo() or 120
        end
        table.insert(target_points, {
            qn     = 0.0,
            bpm    = first_bpm,
            linear = false
        })
    end
    
    -- Add all absolute markers
    for _, tm in ipairs(state.tempo_markers) do
        if tm.type == "absolute" and tm.bpm and tm.bpm > 0 then
            table.insert(target_points, {
                qn     = math.max(0.0, tm.start_qn),
                bpm    = tm.bpm,
                linear = false,
                is_abs = true
            })
        end
    end
    
    -- Add / link all gradual markers
    for _, tm in ipairs(state.tempo_markers) do
        if tm.type == "gradual" then
            tm.bpm = TempoService.get_tempo_at_qn(state, tm.start_qn, tm)
            local s_bpm = tm.bpm or 120
            
            -- IMPORTANT: If an absolute marker follows this gradual marker (e.g. Andante = 80),
            -- the ramp should interpolate seamlessly to that target tempo!
            if not tm.custom_target_bpm then
                local next_abs_bpm = nil
                for _, other in ipairs(state.tempo_markers) do
                    if other.type == "absolute" and other.start_qn >= (tm.end_qn - 0.25) then
                        next_abs_bpm = other.bpm
                        break
                    end
                end
                if next_abs_bpm and next_abs_bpm > 0 then
                    tm.target_bpm = next_abs_bpm
                else
                    tm.target_bpm = TempoService.calc_gradual_target_bpm(tm.label, tm.modifier, s_bpm)
                end
            end
            local t_bpm = tm.target_bpm or (s_bpm * 0.8)
            
            -- Ramp start point
            local found_start = false
            for _, pt in ipairs(target_points) do
                if math.abs(pt.qn - tm.start_qn) < 0.15 then
                    pt.linear = true
                    found_start = true
                    break
                end
            end
            if not found_start then
                table.insert(target_points, {
                    qn     = tm.start_qn,
                    bpm    = s_bpm,
                    linear = true
                })
            end
            
            -- Ramp end point
            local found_end = false
            for _, pt in ipairs(target_points) do
                if math.abs(pt.qn - tm.end_qn) < 0.15 then
                    found_end = true
                    break
                end
            end
            if not found_end then
                table.insert(target_points, {
                    qn     = tm.end_qn,
                    bpm    = t_bpm,
                    linear = false
                })
            end
        end
    end
    
    -- Incorporate score-wide fermata tempo dips (Playback hold & curve)
    if state.fermatas and #state.fermatas > 0 then
        table.sort(target_points, function(a, b) return a.qn < b.qn end)
        for _, ferm in ipairs(state.fermatas) do
            if ferm.playback_mode ~= "visual_only" then
                local base_bpm = 120
                for _, pt in ipairs(target_points) do
                    if pt.qn <= ferm.qn + 0.05 then
                        base_bpm = pt.bpm or base_bpm
                    else
                        break
                    end
                end
                local hold_fac = ferm.hold_factor or 1.5
                local ferm_bpm = math.max(15, math.floor((base_bpm / hold_fac) + 0.5))
                local ferm_dur = ferm.duration_qn or 1.0
                local ferm_end_qn = ferm.qn + ferm_dur
                local is_curve = (ferm.playback_mode == "tempo_curve" or ferm.playback_mode ~= "tempo_dip")

                table.insert(target_points, {
                    qn         = ferm.qn,
                    bpm        = ferm_bpm,
                    linear     = is_curve,
                    is_fermata = true
                })
                table.insert(target_points, {
                    qn                 = ferm_end_qn,
                    bpm                = base_bpm,
                    linear             = false,
                    is_fermata_restore = true
                })
            end
        end
    end

    -- Sort chronologically
    table.sort(target_points, function(a, b)
        return a.qn < b.qn
    end)
    
    -- Merge points at practically identical positions
    local merged_points = {}
    for _, pt in ipairs(target_points) do
        local prev = merged_points[#merged_points]
        if prev and math.abs(prev.qn - pt.qn) < 0.15 then
            if pt.linear ~= nil then prev.linear = pt.linear end
            if pt.is_abs then prev.bpm = pt.bpm end
            if pt.is_fermata then
                prev.bpm = pt.bpm
                prev.linear = pt.linear
                prev.is_fermata = true
            end
        else
            table.insert(merged_points, pt)
        end
    end
    
    -- 3. Synchronize into REAPER timeline (deterministic without ghost points)
    local cur_ts_num, cur_ts_den = reaper.TimeMap_GetTimeSigAtTime(0, 0.0)
    local bpi = (state.time_sig_num and state.time_sig_num > 0) and state.time_sig_num or (cur_ts_num or 4)
    local bpi_d = (state.time_sig_denom and state.time_sig_denom > 0) and state.time_sig_denom or (cur_ts_den or 4)
    
    local pt0 = merged_points[1]
    local bpm0 = pt0 and pt0.bpm or 120
    local lin0 = pt0 and (pt0.linear == true) or false

    local cnt_before = reaper.CountTempoTimeSigMarkers(0)
    
    -- Preserve any existing REAPER time signatures at markers > 0
    local existing_time_sigs = {}
    if cnt_before > 1 then
        for i = 1, cnt_before - 1 do
            local ok, tpos, _, _, _, ts_num, ts_den = reaper.GetTempoTimeSigMarker(0, i)
            if ok and ts_num > 0 and ts_den > 0 then
                table.insert(existing_time_sigs, { timepos = tpos, num = ts_num, den = ts_den })
            end
        end
    end
    
    -- Point 0 at time 0.0:
    -- If REAPER already has markers, update marker 0.
    -- If REAPER has 0 markers, ptidx MUST be -1 to insert the first marker!
    if cnt_before > 0 then
        local ok, _, _, _, _, m0_num, m0_den = reaper.GetTempoTimeSigMarker(0, 0)
        if ok and m0_num > 0 and m0_den > 0 then
            bpi = (state.time_sig_num and state.time_sig_num > 0) and state.time_sig_num or m0_num
            bpi_d = (state.time_sig_denom and state.time_sig_denom > 0) and state.time_sig_denom or m0_den
        end
        reaper.SetTempoTimeSigMarker(0, 0, 0.0, -1, -1, bpm0, bpi, bpi_d, lin0)
    else
        reaper.SetTempoTimeSigMarker(0, -1, 0.0, -1, -1, bpm0, bpi, bpi_d, lin0)
    end
    
    -- Notify REAPER transport and control surfaces immediately
    if reaper.CSurf_OnTempoChange then
        reaper.CSurf_OnTempoChange(bpm0)
    end
    if reaper.Master_SetTempo then
        reaper.Master_SetTempo(bpm0, true)
    end
    
    -- Remove all old markers above index 0 completely to eliminate ghost points during dragging:
    local cnt_after_pt0 = reaper.CountTempoTimeSigMarkers(0)
    for i = cnt_after_pt0 - 1, 1, -1 do
        reaper.DeleteTempoTimeSigMarker(0, i)
    end
    
    -- Now create all further points cleanly and exactly in chronological order:
    for i = 2, #merged_points do
        local pt = merged_points[i]
        local t_pos = reaper.TimeMap2_QNToTime(0, pt.qn)
        local ts_n, ts_d = 0, 0
        for _, ts in ipairs(existing_time_sigs) do
            if not ts.used and math.abs(ts.timepos - t_pos) < 0.05 then
                ts_n, ts_d = ts.num, ts.den
                ts.used = true
                break
            end
        end
        reaper.SetTempoTimeSigMarker(0, -1, t_pos, -1, -1, pt.bpm, ts_n, ts_d, pt.linear == true)
    end
    
    -- Re-insert any preserved time signature markers that were not matched by a tempo point
    for _, ts in ipairs(existing_time_sigs) do
        if not ts.used then
            local qn = reaper.TimeMap2_timeToQN(0, ts.timepos)
            local effective_bpm = TempoService.get_tempo_at_qn(state, qn)
            reaper.SetTempoTimeSigMarker(0, -1, ts.timepos, -1, -1, effective_bpm, ts.num, ts.den, false)
        end
    end
    
    reaper.UpdateTimeline()
    reaper.UpdateArrange()
    reaper.TrackList_AdjustWindows(false)
end

-- Export alias for backward/forward service compatibility
TempoService.sync_to_reaper = TempoService.sync_all_to_reaper

return TempoService

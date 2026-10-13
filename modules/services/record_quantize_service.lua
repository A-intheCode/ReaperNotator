-- ==============================================================================
-- REAPER Native Notator - Service: RecordQuantizeService
-- Manages MIDI Recording Routing, Live Note Preview during Recording, and
-- Auto-Quantize & Overlap Cleaning upon Record Stop:
-- - Bidirectional REAPER Track Arming + automatic MIDI Input / Overdub routing
-- - Real-time MIDI input polling (MIDI_GetRecentInputEvent) for live canvas preview
-- - Keyboard bounce (<15 ticks) & same-pitch overlap cleaning
-- - Metric grid snapping within configurable tick tolerance (e.g. 1/8 @ 25 ticks)
-- - Flexible outlier handling (keep natural / delete / move to Voice 16)
-- ==============================================================================

local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
local MidiNote    = package.loaded["classes.note"] or require("classes.note")

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

-- Live MIDI recording buffer for real-time score canvas preview before record stop
RecordQuantizeService._live_notes = {}
RecordQuantizeService._held_notes = {}
RecordQuantizeService._last_midi_seq = nil

-- ==============================================================================
-- 1. MIDI INPUT DEVICE ENUMERATION & TRACK ROUTING
-- ==============================================================================

--- Enumerates all available MIDI Input Options in REAPER
--- @return table devices Array of { id = number, name = string }
function RecordQuantizeService.get_midi_input_devices()
    local devices = {
        { id = 63, name = "All MIDI Inputs (All Devices)" },
        { id = 62, name = "Virtual MIDI Keyboard (REAPER VMK)" },
    }
    local max_inputs = (reaper.GetNumMIDIInputs and reaper.GetNumMIDIInputs()) or 64
    for i = 0, max_inputs - 1 do
        local ok, dev_name = reaper.GetMIDIInputName(i, "")
        if ok and dev_name and dev_name ~= "" then
            table.insert(devices, {
                id = i,
                name = string.format("[%d] %s", i + 1, dev_name)
            })
        end
    end
    return devices
end

--- Encodes REAPER I_RECINPUT bitfield for MIDI input
--- @param dev_id number 0..61 (Hardware device), 62 (VMK), 63 (All MIDI Inputs)
--- @param chan number 0 (All Channels) or 1..16 (MIDI Channel 1..16)
--- @return number rec_input
function RecordQuantizeService.encode_midi_recinput(dev_id, chan)
    local d = math.max(0, math.min(63, math.floor(tonumber(dev_id) or 63)))
    local c = math.max(0, math.min(16, math.floor(tonumber(chan) or 0)))
    return 4096 | (d << 5) | c
end

--- Decodes REAPER I_RECINPUT bitfield
--- @param rec_input number
--- @return boolean is_midi, number dev_id, number chan
function RecordQuantizeService.decode_midi_recinput(rec_input)
    local val = math.floor(tonumber(rec_input) or 0)
    if val < 0 or (val & 4096) == 0 then
        return false, 63, 0
    end
    local dev_id = (val >> 5) & 63
    local chan = val & 31
    if chan > 16 then chan = 0 end
    return true, dev_id, chan
end

--- Formats a human-readable summary of a track's current MIDI input
--- @param trk userdata MediaTrack*
--- @return string label, boolean is_midi
function RecordQuantizeService.format_track_midi_input(trk)
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then
        return "None", false
    end
    local rec_in = reaper.GetMediaTrackInfo_Value(trk, "I_RECINPUT")
    local is_midi, dev_id, chan = RecordQuantizeService.decode_midi_recinput(rec_in)
    if not is_midi then
        return "Audio Input (Switch to MIDI)", false
    end
    local dev_str = "All MIDI"
    if dev_id == 63 then
        dev_str = "All MIDI Inputs"
    elseif dev_id == 62 then
        dev_str = "Virtual MIDI KB"
    else
        local ok, dname = reaper.GetMIDIInputName(dev_id, "")
        dev_str = (ok and dname and dname ~= "") and dname or string.format("MIDI Dev %d", dev_id + 1)
    end
    local ch_str = (chan == 0) and "All Ch" or string.format("Ch %d", chan)
    return string.format("%s (%s)", dev_str, ch_str), true
end

--- Applies MIDI Input, Record Mode (MIDI Overdub), and Monitoring to a track
--- Prevents REAPER from recording Audio (.wav) and showing the "Save recorded media" dialog!
--- @param state table
--- @param trk userdata MediaTrack*
--- @param force_input boolean If true, overwrites existing MIDI input with state.rec_midi_device/channel
function RecordQuantizeService.apply_midi_routing_to_track(state, trk, force_input)
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then return end

    local cur_in = math.floor(reaper.GetMediaTrackInfo_Value(trk, "I_RECINPUT") or 0)
    local is_midi = (cur_in >= 0) and ((cur_in & 4096) ~= 0)

    if force_input or not is_midi then
        local target_in = RecordQuantizeService.encode_midi_recinput(
            state and state.rec_midi_device or 63,
            state and state.rec_midi_channel or 0
        )
        reaper.SetMediaTrackInfo_Value(trk, "I_RECINPUT", target_in)
    end

    -- Enable Input Monitoring (I_RECMON = 1) so the VSTi is audible while playing
    if not state or state.rec_auto_monitor ~= false then
        local cur_mon = math.floor(reaper.GetMediaTrackInfo_Value(trk, "I_RECMON") or 0)
        if cur_mon == 0 then
            reaper.SetMediaTrackInfo_Value(trk, "I_RECMON", 1)
        end
    end

    -- Set Record Mode (Default 7 = MIDI Overdub: writes directly into MIDI item without Save dialog)
    local target_mode = (state and state.rec_mode) or 7
    reaper.SetMediaTrackInfo_Value(trk, "I_RECMODE", target_mode)
end

--- Arms or disarms a track in REAPER, synchronizes TCP/MCP UI, and ensures visibility in Notator
--- @param state table
--- @param trk userdata MediaTrack*
--- @param armed boolean
function RecordQuantizeService.set_track_armed(state, trk, armed)
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then return end

    local arm_val = armed and 1 or 0
    reaper.SetMediaTrackInfo_Value(trk, "I_RECARM", arm_val)
    if reaper.APIExists("CSurf_OnRecArmChange") then
        pcall(reaper.CSurf_OnRecArmChange, trk, arm_val)
    end

    if armed then
        RecordQuantizeService.apply_midi_routing_to_track(state, trk, false)
        local guid = reaper.GetTrackGUID(trk)
        if state and state.selected_tracks and guid then
            state.selected_tracks[guid] = true
        end
    end

    MidiService.invalidate_cache()
    if reaper.TrackList_AdjustWindows then
        reaper.TrackList_AdjustWindows(false)
    end
    if reaper.UpdateArrange then
        reaper.UpdateArrange()
    end
end

--- Prepares all armed tracks right when recording starts
--- Ensures every armed track is set to MIDI Input (preventing Audio Save dialogs)
--- and resets the real-time live note preview buffer.
--- @param state table
function RecordQuantizeService.on_record_start(state)
    RecordQuantizeService.clear_live_recording()

    if reaper.APIExists("MIDI_GetRecentInputEvent") then
        local seq = reaper.MIDI_GetRecentInputEvent(0)
        RecordQuantizeService._last_midi_seq = seq or 0
    end

    local trk_cnt = reaper.CountTracks(0)
    local armed_count = 0
    for ti = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            if reaper.GetMediaTrackInfo_Value(trk, "I_RECARM") == 1 then
                armed_count = armed_count + 1
                RecordQuantizeService.apply_midi_routing_to_track(state, trk, false)
                local guid = reaper.GetTrackGUID(trk)
                if state and state.selected_tracks and guid then
                    state.selected_tracks[guid] = true
                end
            end
        end
    end

    -- If no track was armed at all when clicking Record, auto-arm the focused/selected track!
    if armed_count == 0 then
        local fallback_trk = (state and state.focused_track) or reaper.GetSelectedTrack(0, 0) or reaper.GetTrack(0, 0)
        if fallback_trk and reaper.ValidatePtr(fallback_trk, "MediaTrack*") then
            RecordQuantizeService.set_track_armed(state, fallback_trk, true)
        end
    end

    MidiService.invalidate_cache()
    if reaper.TrackList_AdjustWindows then
        reaper.TrackList_AdjustWindows(false)
    end
end

-- ==============================================================================
-- 2. REAL-TIME LIVE MIDI NOTE PREVIEW DURING RECORDING
-- ==============================================================================

function RecordQuantizeService.clear_live_recording()
    RecordQuantizeService._live_notes = {}
    RecordQuantizeService._held_notes = {}
    if reaper.APIExists("MIDI_GetRecentInputEvent") then
        local seq = reaper.MIDI_GetRecentInputEvent(0)
        RecordQuantizeService._last_midi_seq = seq or 0
    else
        RecordQuantizeService._last_midi_seq = nil
    end
end

--- Snaps a QN position to the configured recording grid if within tolerance
local function snap_qn_for_live_preview(state, raw_qn)
    if not state or state.rec_auto_quantize == false then
        return raw_qn
    end
    local base_grid_qn = state.rec_quantize_grid_qn or 0.5
    local grid_type = state.rec_quantize_grid_type or "straight"
    local tolerance_ticks = state.rec_tolerance_ticks or 25

    local eff_grid = base_grid_qn
    if grid_type == "triplet" then
        eff_grid = base_grid_qn * (2.0 / 3.0)
    elseif grid_type == "dotted" then
        eff_grid = base_grid_qn * 1.5
    end
    if eff_grid <= 0.001 then eff_grid = 0.5 end

    local _, qn_measure_start, _ = reaper.TimeMap_QNToMeasures(0, raw_qn)
    local rel_qn = raw_qn - qn_measure_start
    local nearest_k = math.floor((rel_qn / eff_grid) + 0.5)
    local nearest_grid_qn = qn_measure_start + (nearest_k * eff_grid)
    local diff_ticks = math.abs(raw_qn - nearest_grid_qn) * 960.0

    if diff_ticks <= (tolerance_ticks + 0.05) then
        return math.max(0, nearest_grid_qn)
    end
    return raw_qn
end

--- Polls incoming MIDI events in real time during recording
--- @param state table
function RecordQuantizeService.update_live_recording(state)
    local play_state = reaper.GetPlayState()
    local is_recording = (play_state & 4) == 4
    if not is_recording then
        if #RecordQuantizeService._live_notes > 0 then
            RecordQuantizeService.clear_live_recording()
        end
        return
    end

    local play_pos = reaper.GetPlayPosition()
    local play_qn = math.max(0, reaper.TimeMap2_timeToQN(0, play_pos))
    local min_step_qn = (state and state.rec_quantize_grid_qn) or 0.25
    if min_step_qn > 0.5 then min_step_qn = 0.25 end

    if reaper.APIExists("MIDI_GetRecentInputEvent") then
        if not RecordQuantizeService._last_midi_seq then
            local init_seq = reaper.MIDI_GetRecentInputEvent(0)
            RecordQuantizeService._last_midi_seq = init_seq or 0
        end

        local new_evts = {}
        local newest_seq = RecordQuantizeService._last_midi_seq
        for idx = 0, 64 do
            local seq, buf, ts, dev_idx, proj_pos = reaper.MIDI_GetRecentInputEvent(idx)
            if not seq or seq == 0 or seq <= RecordQuantizeService._last_midi_seq then
                break
            end
            if idx == 0 then
                newest_seq = seq
            end
            table.insert(new_evts, {
                seq = seq,
                buf = buf,
                dev_idx = dev_idx,
                proj_pos = proj_pos
            })
        end
        RecordQuantizeService._last_midi_seq = newest_seq

        -- Process chronologically (oldest to newest)
        for i = #new_evts, 1, -1 do
            local ev = new_evts[i]
            local buf = ev.buf
            if buf and #buf >= 3 then
                local status_byte = string.byte(buf, 1)
                local status = status_byte & 0xF0
                local chan = status_byte & 0x0F
                local pitch = string.byte(buf, 2)
                local vel = string.byte(buf, 3)

                local ev_qn = play_qn
                if ev.proj_pos and ev.proj_pos > 0 then
                    ev_qn = math.max(0, reaper.TimeMap2_timeToQN(0, ev.proj_pos))
                end

                if status == 0x90 and vel > 0 then
                    -- Close any previously held note on the same pitch
                    local prev_held = RecordQuantizeService._held_notes[pitch]
                    if prev_held then
                        prev_held.is_held = false
                        prev_held.end_qn = math.max(prev_held.start_qn + 0.125, ev_qn)
                        prev_held.dur_qn = prev_held.end_qn - prev_held.start_qn
                        RecordQuantizeService._held_notes[pitch] = nil
                    end

                    local snapped_sqn = snap_qn_for_live_preview(state, ev_qn)
                    local live_n = {
                        pitch = pitch,
                        chan = chan,
                        vel = vel,
                        raw_start_qn = ev_qn,
                        start_qn = snapped_sqn,
                        end_qn = snapped_sqn + min_step_qn,
                        dur_qn = min_step_qn,
                        dev_idx = ev.dev_idx,
                        is_held = true,
                        is_live_recording = true
                    }
                    table.insert(RecordQuantizeService._live_notes, live_n)
                    RecordQuantizeService._held_notes[pitch] = live_n

                elseif status == 0x80 or (status == 0x90 and vel == 0) then
                    local held = RecordQuantizeService._held_notes[pitch]
                    if held then
                        held.is_held = false
                        held.end_qn = math.max(held.start_qn + 0.125, ev_qn)
                        held.dur_qn = held.end_qn - held.start_qn
                        RecordQuantizeService._held_notes[pitch] = nil
                    end
                end
            end
        end
    end

    -- Dynamically extend currently held notes up to the live recording playhead
    for _, held in pairs(RecordQuantizeService._held_notes) do
        if held and held.is_held then
            held.end_qn = math.max(held.start_qn + min_step_qn, play_qn)
            held.dur_qn = held.end_qn - held.start_qn
        end
    end
end

--- Returns merged note list (existing take notes + live preview notes) for a track during recording
--- @param state table
--- @param tdata table Track data entry in ScoreCanvas
--- @return table merged_notes, number max_live_qn
function RecordQuantizeService.get_merged_live_notes_for_track(state, tdata)
    local base_notes = (tdata and tdata.notes) or {}
    if not state or state.rec_live_preview == false then
        return base_notes, 0
    end
    if (reaper.GetPlayState() & 4) ~= 4 then
        return base_notes, 0
    end
    if not tdata or not tdata.track or not reaper.ValidatePtr(tdata.track, "MediaTrack*") then
        return base_notes, 0
    end
    if reaper.GetMediaTrackInfo_Value(tdata.track, "I_RECARM") ~= 1 then
        return base_notes, 0
    end
    if #RecordQuantizeService._live_notes == 0 then
        return base_notes, 0
    end

    local is_midi, trk_dev, trk_chan = RecordQuantizeService.decode_midi_recinput(
        reaper.GetMediaTrackInfo_Value(tdata.track, "I_RECINPUT")
    )

    local merged = {}
    for _, n in ipairs(base_notes) do
        table.insert(merged, n)
    end

    local max_live_qn = 0
    for idx, ln in ipairs(RecordQuantizeService._live_notes) do
        -- Check device and channel match
        local dev_ok = (not is_midi) or (trk_dev == 63) or (trk_dev == 62) or (ln.dev_idx == nil) or (ln.dev_idx == trk_dev)
        local chan_ok = (not is_midi) or (trk_chan == 0) or ((ln.chan + 1) == trk_chan)

        if dev_ok and chan_ok then
            -- Deduplicate against notes that REAPER may have already flushed into the take
            local already_in_take = false
            for _, tn in ipairs(base_notes) do
                if tn.pitch == ln.pitch and (math.abs(tn.start_qn - ln.start_qn) < 0.18 or math.abs(tn.start_qn - ln.raw_start_qn) < 0.18) then
                    tn.is_live_recording = true
                    already_in_take = true
                    break
                end
            end

            if not already_in_take then
                local preview_note = MidiNote.new({
                    idx = -1000 - idx,
                    pitch = ln.pitch,
                    start_qn = ln.start_qn,
                    end_qn = ln.end_qn,
                    dur_qn = ln.dur_qn,
                    vel = ln.vel or 96,
                    chan = ln.chan or 0,
                    take = nil,
                    item = nil,
                    track = tdata.track
                })
                preview_note.is_live_recording = true
                preview_note.is_held = ln.is_held
                table.insert(merged, preview_note)
                if ln.end_qn > max_live_qn then
                    max_live_qn = ln.end_qn
                end
            end
        end
    end

    table.sort(merged, function(a, b)
        local as = a.start_qn or 0
        local bs = b.start_qn or 0
        if math.abs(as - bs) > 0.001 then return as < bs end
        return (a.pitch or 0) < (b.pitch or 0)
    end)

    return merged, max_live_qn
end

-- ==============================================================================
-- 3. AUTO-QUANTIZE & OVERLAP CLEANING ON RECORD STOP
-- ==============================================================================

--- Resolves all MIDI takes recorded during the session on armed tracks
--- @param state table
--- @param start_time number Project time when recording started
--- @param stop_time number Project time when recording stopped
--- @return table takes Array of MediaItem_Take*
function RecordQuantizeService.get_recorded_takes(state, start_time, stop_time)
    local takes = {}
    local seen = {}

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
            if is_armed then
                local it_cnt = reaper.CountTrackMediaItems(trk)
                for ii = 0, it_cnt - 1 do
                    local it = reaper.GetTrackMediaItem(trk, ii)
                    if it and reaper.ValidatePtr(it, "MediaItem*") then
                        local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                        local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                        local iend = ipos + ilen
                        
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
    RecordQuantizeService.clear_live_recording()

    if state.rec_auto_quantize == false then
        MidiService.invalidate_cache()
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
        local at = MidiService.get_active_midi_take()
        if at and reaper.TakeIsMIDI(at) then
            table.insert(takes, at)
        end
    end

    if #takes == 0 then
        MidiService.invalidate_cache()
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
                            if n2.vel > n1.vel then
                                n1.action = "delete"
                            else
                                n2.action = "delete"
                            end
                            total_cleaned = total_cleaned + 1
                        -- Detection B: Overlapping note tails on same pitch
                        elseif n1.eppq >= n2.sppq then
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

                local _, qn_measure_start, _ = reaper.TimeMap_QNToMeasures(0, sqn)
                local rel_qn = sqn - qn_measure_start
                local nearest_k = math.floor((rel_qn / eff_grid) + 0.5)
                local nearest_grid_qn = qn_measure_start + (nearest_k * eff_grid)
                local diff_qn = math.abs(sqn - nearest_grid_qn)
                local diff_ticks = diff_qn * 960.0

                if diff_ticks < 0.05 then
                    diff_ticks = 0.0
                end

                if diff_ticks <= (tolerance_ticks + 0.05) then
                    local new_sqn = math.max(0, nearest_grid_qn)
                    local new_eqn = new_sqn + orig_dur_qn
                    local new_sppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_sqn)
                    local new_eppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_eqn)

                    n.sppq = new_sppq
                    n.eppq = new_eppq
                    n.action = "modify"
                    total_snapped = total_snapped + 1
                else
                    if outlier_mode == "delete" then
                        n.action = "delete"
                        total_outliers = total_outliers + 1
                    elseif outlier_mode == "voice16" then
                        n.chan = 15
                        n.action = "modify"
                        total_outliers = total_outliers + 1
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

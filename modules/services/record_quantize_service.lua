-- ==============================================================================
-- REAPER Native Notator - Service: RecordQuantizeService
-- Manages MIDI Recording Routing, Real-Time Auto-Quantize & Live Note Preview
-- during Direct Recording, and Final Clean-Up upon Record Stop:
-- - Bidirectional REAPER Track Arming + automatic MIDI Input / Overdub routing
-- - Real-time MIDI input polling (MIDI_GetRecentInputEvent) with live grid snap
--   and immediate outlier filtering (Keep / Delete / Voice 16)
-- - Real-time take quantization during Direct Recording (MIDI Overdub)
-- - Keyboard bounce (<15 ticks) & same-pitch overlap cleaning
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

-- Live MIDI recording buffer for real-time score canvas preview
RecordQuantizeService._live_notes = {}
RecordQuantizeService._held_notes = {}
RecordQuantizeService._last_midi_seq = nil
RecordQuantizeService._realtime_take_counts = {}
RecordQuantizeService._processed_note_sigs = {}

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

    -- Enable Input Monitoring (I_RECMON = 1) when Monitor Input is active, or disable when unchecked
    if not state or state.rec_auto_monitor ~= false then
        local cur_mon = math.floor(reaper.GetMediaTrackInfo_Value(trk, "I_RECMON") or 0)
        if cur_mon == 0 then
            reaper.SetMediaTrackInfo_Value(trk, "I_RECMON", 1)
        end
    else
        reaper.SetMediaTrackInfo_Value(trk, "I_RECMON", 0)
    end

    -- Set Record Mode (Default 7 = MIDI Overdub: writes directly into MIDI item without Save dialog)
    local target_mode = (state and state.rec_mode) or 7
    reaper.SetMediaTrackInfo_Value(trk, "I_RECMODE", target_mode)
end

RecordQuantizeService._tracked_armed_guids = {}

--- Arms or disarms a track in REAPER, synchronizes TCP/MCP UI, and ensures visibility in Notator
--- @param state table
--- @param trk userdata MediaTrack*
--- @param armed boolean
function RecordQuantizeService.set_track_armed(state, trk, armed)
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then return end

    local arm_val = armed and 1 or 0
    local mon_val = (armed and (not state or state.rec_auto_monitor ~= false)) and 1 or 0
    local guid = reaper.GetTrackGUID(trk)

    local ap = package.loaded["services.audio_preview"]
    if ap and ap.track_restore and ap.track_restore[trk] then
        ap.track_restore[trk].orig_arm = arm_val
        ap.track_restore[trk].changed_arm = false
        ap.track_restore[trk].orig_mon = mon_val
        ap.track_restore[trk].changed_mon = false
    end

    reaper.SetMediaTrackInfo_Value(trk, "I_RECARM", arm_val)
    if reaper.APIExists("CSurf_OnRecArmChange") then
        pcall(reaper.CSurf_OnRecArmChange, trk, arm_val)
    end

    if armed then
        if guid then RecordQuantizeService._tracked_armed_guids[guid] = true end
        RecordQuantizeService.apply_midi_routing_to_track(state, trk, false)
        if state and state.selected_tracks and guid then
            state.selected_tracks[guid] = true
        end
    else
        if guid then RecordQuantizeService._tracked_armed_guids[guid] = nil end
        reaper.SetMediaTrackInfo_Value(trk, "I_RECMON", 0)
    end

    MidiService.invalidate_cache()
    if reaper.TrackList_AdjustWindows then
        reaper.TrackList_AdjustWindows(false)
    end
    if reaper.UpdateArrange then
        reaper.UpdateArrange()
    end
end

--- Synchronizes monitoring state across all project tracks so tracks disarmed in REAPER TCP/MCP also disable I_RECMON
function RecordQuantizeService.sync_all_tracks_monitoring()
    RecordQuantizeService._tracked_armed_guids = RecordQuantizeService._tracked_armed_guids or {}
    local ap = package.loaded["services.audio_preview"]
    local trk_cnt = reaper.CountTracks(0)
    for ti = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            if not (ap and ap.track_restore and ap.track_restore[trk]) then
                local guid = reaper.GetTrackGUID(trk)
                local is_armed
                if ap and ap.is_track_user_armed then
                    is_armed = ap.is_track_user_armed(trk)
                else
                    is_armed = (reaper.GetMediaTrackInfo_Value(trk, "I_RECARM") == 1)
                end
                if is_armed then
                    if guid then RecordQuantizeService._tracked_armed_guids[guid] = true end
                elseif guid and RecordQuantizeService._tracked_armed_guids[guid] then
                    RecordQuantizeService._tracked_armed_guids[guid] = nil
                    reaper.SetMediaTrackInfo_Value(trk, "I_RECMON", 0)
                end
            end
        end
    end
end

RecordQuantizeService._pre_existing_notes = {}

--- Prepares all armed tracks right when recording starts and snapshots existing notes
--- @param state table
function RecordQuantizeService.on_record_start(state)
    local ap = package.loaded["services.audio_preview"]
    if ap and ap.restore_all_tracks then
        ap.restore_all_tracks()
    end

    RecordQuantizeService.clear_live_recording()
    RecordQuantizeService._realtime_take_counts = {}
    RecordQuantizeService._processed_note_sigs = {}
    RecordQuantizeService._pre_existing_notes = {}

    if state then
        state._was_recording = true
        state._rec_start_time = math.min(reaper.GetCursorPosition(), reaper.GetPlayPosition())
        state._last_rec_play_pos = state._rec_start_time
    end

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

    if armed_count == 0 then
        local fallback_trk = (state and state.focused_track) or reaper.GetSelectedTrack(0, 0) or reaper.GetTrack(0, 0)
        if fallback_trk and reaper.ValidatePtr(fallback_trk, "MediaTrack*") then
            RecordQuantizeService.set_track_armed(state, fallback_trk, true)
        end
    end

    -- Snapshot pre-existing notes on all armed tracks so we only quantize newly recorded notes
    for ti = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") and reaper.GetMediaTrackInfo_Value(trk, "I_RECARM") == 1 then
            local it_cnt = reaper.CountTrackMediaItems(trk)
            for ii = 0, it_cnt - 1 do
                local it = reaper.GetTrackMediaItem(trk, ii)
                local take = it and reaper.GetActiveTake(it)
                if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
                    local tk_key = tostring(take)
                    local pre_map = {}
                    local _, notecnt = reaper.MIDI_CountEvts(take)
                    for ni = 0, notecnt - 1 do
                        local ok, _, _, sppq, eppq, chan, pitch = reaper.MIDI_GetNote(take, ni)
                        if ok then
                            local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                            local eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                            local sig = string.format("%d_%d_%d", pitch, math.floor(sqn * 960 + 0.5), chan)
                            pre_map[sig] = eqn
                        end
                    end
                    RecordQuantizeService._pre_existing_notes[tk_key] = pre_map
                end
            end
        end
    end

    MidiService.invalidate_cache()
    if reaper.TrackList_AdjustWindows then
        reaper.TrackList_AdjustWindows(false)
    end
end

-- ==============================================================================
-- 2. REAL-TIME QUANTIZATION MATH & LIVE RECORDING ENGINE
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

local function get_effective_grid_qn(state)
    local base_grid_qn = (state and state.rec_quantize_grid_qn) or 0.5
    local grid_type = (state and state.rec_quantize_grid_type) or "straight"
    local eff_grid = base_grid_qn
    if grid_type == "triplet" then
        eff_grid = base_grid_qn * (2.0 / 3.0)
    elseif grid_type == "dotted" then
        eff_grid = base_grid_qn * 1.5
    end
    if eff_grid <= 0.001 then eff_grid = 0.5 end
    return eff_grid
end

--- Evaluates a note onset and duration against the real-time quantize settings
--- @param state table
--- @param raw_sqn number
--- @param raw_dur_qn number
--- @return table result { action = "snap"|"keep"|"delete"|"voice16", sqn = number, dur_qn = number, chan_override = number|nil }
local function evaluate_note_quantization(state, raw_sqn, raw_dur_qn)
    local eff_grid = get_effective_grid_qn(state)
    if not state or state.rec_auto_quantize == false then
        return { action = "keep", sqn = raw_sqn, dur_qn = math.max(0.125, raw_dur_qn or eff_grid), chan_override = nil }
    end

    local tolerance_ticks = state.rec_tolerance_ticks or 25
    local outlier_mode = state.rec_outlier_mode or "snap"

    local _, qn_measure_start, _ = reaper.TimeMap_QNToMeasures(0, raw_sqn)
    local rel_qn = raw_sqn - qn_measure_start
    local nearest_k = math.floor((rel_qn / eff_grid) + 0.5)
    local nearest_grid_qn = qn_measure_start + (nearest_k * eff_grid)
    local diff_ticks = math.abs(raw_sqn - nearest_grid_qn) * 960.0
    if diff_ticks < 0.05 then diff_ticks = 0.0 end

    if diff_ticks <= (tolerance_ticks + 0.05) or outlier_mode == "snap" then
        local snapped_sqn = math.max(0, nearest_grid_qn)
        local snapped_dur = math.max(eff_grid, math.floor(((raw_dur_qn or eff_grid) / eff_grid) + 0.5) * eff_grid)
        return {
            action = "snap",
            sqn = snapped_sqn,
            dur_qn = snapped_dur,
            chan_override = nil
        }
    else
        if outlier_mode == "delete" then
            return { action = "delete", sqn = raw_sqn, dur_qn = raw_dur_qn }
        elseif outlier_mode == "voice16" then
            return { action = "voice16", sqn = raw_sqn, dur_qn = math.max(0.125, raw_dur_qn or eff_grid), chan_override = 15 }
        else
            return { action = "keep", sqn = raw_sqn, dur_qn = math.max(0.125, raw_dur_qn or eff_grid), chan_override = nil }
        end
    end
end

--- Polls incoming MIDI events in real time for non-destructive live quantization preview on ScoreCanvas.
--- NOTE: Never calls MIDI_SetNote/MIDI_Sort on REAPER takes while recording is active, because mutating
--- a take while keys are held down in MIDI Overdub mode bakes unclosed Note-Ons to the end of the item!
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
    local eff_grid = get_effective_grid_qn(state)
    local min_step_qn = (state and state.rec_auto_quantize ~= false) and eff_grid or math.min(0.25, eff_grid)
    local clean_overlaps = (not state) or (state.rec_clean_overlaps ~= false)

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
                    local pqn = reaper.TimeMap2_timeToQN(0, ev.proj_pos)
                    if pqn and pqn >= 0 and math.abs(pqn - play_qn) <= 4.0 then
                        ev_qn = pqn
                    end
                end

                if status == 0x90 and vel > 0 then
                    -- Close any previously held note on the same pitch
                    local prev_held = RecordQuantizeService._held_notes[pitch]
                    if prev_held then
                        prev_held.is_held = false
                        local clamped_end = math.min(play_qn, math.max(prev_held.raw_start_qn + 0.05, ev_qn))
                        local raw_d = math.max(0.125, clamped_end - prev_held.start_qn)
                        if prev_held.is_snapped and state and state.rec_auto_quantize ~= false then
                            raw_d = math.max(eff_grid, math.floor((raw_d / eff_grid) + 0.5) * eff_grid)
                        end
                        prev_held.dur_qn = raw_d
                        prev_held.end_qn = prev_held.start_qn + raw_d
                        RecordQuantizeService._held_notes[pitch] = nil
                    end

                    -- Keyboard bounce filter (<15 ticks = 0.015625 QN on same pitch)
                    local is_bounce = false
                    if clean_overlaps then
                        for k = #RecordQuantizeService._live_notes, 1, -1 do
                            local prev_ln = RecordQuantizeService._live_notes[k]
                            if prev_ln.pitch == pitch then
                                if math.abs(ev_qn - prev_ln.raw_start_qn) * 960.0 < 15.0 then
                                    is_bounce = true
                                    if vel > (prev_ln.vel or 0) then
                                        prev_ln.vel = vel
                                    end
                                end
                                break
                            end
                        end
                    end

                    if not is_bounce then
                        local q_res = evaluate_note_quantization(state, ev_qn, min_step_qn)
                        if q_res.action ~= "delete" then
                            local target_sqn = q_res.sqn
                            local target_chan = q_res.chan_override or chan

                            -- Trim same-pitch overlapping live notes
                            if clean_overlaps then
                                for k = #RecordQuantizeService._live_notes, 1, -1 do
                                    local prev_ln = RecordQuantizeService._live_notes[k]
                                    if prev_ln.pitch == pitch and prev_ln.end_qn > target_sqn then
                                        if target_sqn <= prev_ln.start_qn + 0.02 then
                                            table.remove(RecordQuantizeService._live_notes, k)
                                        else
                                            prev_ln.end_qn = target_sqn
                                            prev_ln.dur_qn = prev_ln.end_qn - prev_ln.start_qn
                                            prev_ln.is_held = false
                                        end
                                    end
                                end
                            end

                            local live_n = {
                                pitch = pitch,
                                chan = target_chan,
                                vel = vel,
                                raw_start_qn = ev_qn,
                                start_qn = target_sqn,
                                end_qn = target_sqn + min_step_qn,
                                dur_qn = min_step_qn,
                                dev_idx = ev.dev_idx,
                                is_held = true,
                                is_snapped = (q_res.action == "snap"),
                                is_live_recording = true
                            }
                            table.insert(RecordQuantizeService._live_notes, live_n)
                            RecordQuantizeService._held_notes[pitch] = live_n
                        end
                    end

                elseif status == 0x80 or (status == 0x90 and vel == 0) then
                    local held = RecordQuantizeService._held_notes[pitch]
                    if held then
                        held.is_held = false
                        local clamped_end = math.min(play_qn + 0.05, math.max(held.raw_start_qn + 0.05, ev_qn))
                        local raw_d = math.max(0.125, clamped_end - held.start_qn)
                        if held.is_snapped and state and state.rec_auto_quantize ~= false then
                            raw_d = math.max(eff_grid, math.floor((raw_d / eff_grid) + 0.5) * eff_grid)
                        end
                        held.dur_qn = raw_d
                        held.end_qn = held.start_qn + raw_d
                        RecordQuantizeService._held_notes[pitch] = nil
                    end
                end
            end
        end
    end

    -- Dynamically extend currently held notes up to the live recording playhead (strictly bounded by play_qn)
    for _, held in pairs(RecordQuantizeService._held_notes) do
        if held and held.is_held then
            local raw_d = math.max(min_step_qn, play_qn - held.start_qn)
            if held.is_snapped and state and state.rec_auto_quantize ~= false then
                raw_d = math.max(eff_grid, math.ceil((raw_d - 0.05) / eff_grid) * eff_grid)
            end
            held.dur_qn = raw_d
            held.end_qn = held.start_qn + raw_d
        end
    end
end

local function is_note_pre_existing(take, pitch, sqn, chan, min_rec_qn)
    if take then
        local pre_map = RecordQuantizeService._pre_existing_notes[tostring(take)]
        if pre_map then
            local tick_key = math.floor(sqn * 960 + 0.5)
            for dt = -2, 2 do
                local sig = string.format("%d_%d_%d", pitch, tick_key + dt, chan or 0)
                if pre_map[sig] ~= nil then
                    return true
                end
            end
            return false
        end
    end
    if min_rec_qn and sqn < (min_rec_qn - 0.15) then
        return true
    end
    return false
end

-- ==============================================================================
-- 2B. AUTO-DIVISI REGISTER INTELLIGENCE & MONOTONIC VOICE ASSIGNMENT ENGINE
-- ==============================================================================

local CLEF_REGISTER_DEFAULTS = {
    treble_15ma   = { min_p = 69, max_p = 103, center_p = 84, family = "high_15ma", role_label = "15ma (A4–G7)",     rank_bias = 10 },
    treble_8va    = { min_p = 64, max_p = 96,  center_p = 78, family = "high_8va",  role_label = "8va (E4–C7)",      rank_bias = 7 },
    french_violin = { min_p = 57, max_p = 89,  center_p = 71, family = "treble",    role_label = "High (A3–F6)",     rank_bias = 3 },
    treble        = { min_p = 55, max_p = 88,  center_p = 68, family = "treble",    role_label = "Treble (G3–E6)",   rank_bias = 2 },
    soprano       = { min_p = 55, max_p = 84,  center_p = 67, family = "treble",    role_label = "Soprano (G3–C6)",  rank_bias = 2 },
    mezzo         = { min_p = 52, max_p = 81,  center_p = 64, family = "mid_high",  role_label = "Mezzo (E3–A5)",    rank_bias = 1 },
    alto          = { min_p = 48, max_p = 79,  center_p = 58, family = "alto",      role_label = "Alto/Mid (C3–G5)", rank_bias = 0 },
    treble_8vb    = { min_p = 45, max_p = 76,  center_p = 57, family = "tenor",     role_label = "Tenor (A2–E5)",    rank_bias = -1 },
    tenor         = { min_p = 43, max_p = 74,  center_p = 55, family = "tenor",     role_label = "Tenor (G2–D5)",    rank_bias = -1 },
    baritone_c    = { min_p = 40, max_p = 69,  center_p = 52, family = "baritone",  role_label = "Baritone (E2–A4)", rank_bias = -2 },
    baritone_f    = { min_p = 40, max_p = 69,  center_p = 52, family = "baritone",  role_label = "Baritone (E2–A4)", rank_bias = -2 },
    bass          = { min_p = 36, max_p = 67,  center_p = 48, family = "bass",      role_label = "Bass (C2–G4)",     rank_bias = -3 },
    tenor_8vb     = { min_p = 36, max_p = 64,  center_p = 48, family = "bass",      role_label = "Bass (C2–E4)",     rank_bias = -3 },
    bass_8vb      = { min_p = 24, max_p = 55,  center_p = 38, family = "sub_bass",  role_label = "Sub-Bass (C1–G3)", rank_bias = -6 },
    bass_15mb     = { min_p = 21, max_p = 50,  center_p = 34, family = "sub_bass",  role_label = "Sub-Bass (A0–D3)", rank_bias = -8 },
    grand         = { min_p = 36, max_p = 88,  center_p = 60, family = "grand",     role_label = "Grand (C2–E6)",    rank_bias = 0 },
}

--- Resolves the acoustic register, Clef, and role profile for a single REAPER track
--- @param state table
--- @param trk userdata MediaTrack*
--- @return table profile
function RecordQuantizeService.get_track_register_profile(state, trk)
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then
        return { min_p = 48, max_p = 84, center_p = 60, effective_center = 60, family = "mid", role_label = "Mid (C3–C6)", rank_bias = 0 }
    end

    local guid = reaper.GetTrackGUID(trk)
    local track_idx = math.floor(reaper.GetMediaTrackInfo_Value(trk, "IP_TRACKNUMBER") or 1)
    local _, raw_name = reaper.GetTrackName(trk)
    local tname = (raw_name and raw_name ~= "") and raw_name or string.format("Track %d", track_idx)
    local name_l = tname:lower()

    -- 1. Resolve Clef ID
    local clef_id = nil
    if state and state.track_clefs and guid then
        local saved = state.track_clefs[guid] or state.track_clefs[guid:upper()] or state.track_clefs[guid:lower()]
        if saved and saved ~= "auto" then
            clef_id = saved
        end
    end
    if not clef_id or clef_id == "auto" then
        local ok_eng, Engraver = pcall(require, "rendering.engraver")
        if ok_eng and Engraver and Engraver.get_track_clef then
            clef_id = Engraver.get_track_clef(guid, tname, nil, state)
        end
    end
    clef_id = clef_id or "treble"

    local base = CLEF_REGISTER_DEFAULTS[clef_id] or CLEF_REGISTER_DEFAULTS.treble
    local min_p = base.min_p
    local max_p = base.max_p
    local center_p = base.center_p
    local family = base.family
    local role_label = base.role_label
    local rank_bias = base.rank_bias or 0
    local is_primary_section_voice = true

    -- 2. Refine from instrument name keywords (Strings, Woodwinds, Brass, Choir)
    if name_l:find("double bass") or name_l:find("kontrabass") or name_l:find("contrabass") or name_l:find("string bass") or name_l:find("bassi") or name_l:match("%f[%a]cb%f[%A]") or name_l:match("%f[%a]db%f[%A]") or name_l:match("%f[%a]kb%f[%A]") then
        min_p, max_p, center_p = 24, 55, 38 -- C1 .. G3 (Double Bass)
        family, role_label, rank_bias = "double_bass", "D.Bass (C1–G3)", -7
    elseif name_l:find("contrabassoon") or name_l:find("kontrafagott") or name_l:match("%f[%a]cbsn%f[%A]") then
        min_p, max_p, center_p = 22, 53, 36
        family, role_label, rank_bias = "double_bass", "CBsn (Bb0–F3)", -7
    elseif name_l:find("tuba") or name_l:find("cimbasso") then
        min_p, max_p, center_p = 26, 58, 40
        family, role_label, rank_bias = "tuba", "Tuba (D1–Bb3)", -6
    elseif name_l:find("cell") or name_l:match("%f[%a]vc%f[%A]") or name_l:match("%f[%a]vlc%f[%A]") then
        min_p, max_p, center_p = 36, 69, 48 -- C2 .. A4 (Cello)
        family, role_label, rank_bias = "cello", "Cello (C2–A4)", -3
        if name_l:match("2") or name_l:match("%f[%a]ii%f[%A]") then
            center_p = 45
            rank_bias = -4
            role_label = "Cello 2 (C2–A4)"
            is_primary_section_voice = false
        end
    elseif name_l:find("bassoon") or name_l:find("fagott") or name_l:match("%f[%a]bsn%f[%A]") or name_l:match("%f[%a]fg%f[%A]") then
        min_p, max_p, center_p = 34, 67, 48
        family, role_label, rank_bias = "bassoon", "Bsn (Bb1–G4)", -3
    elseif name_l:find("trombone") or name_l:find("posaune") or name_l:match("%f[%a]trb%f[%A]") or name_l:match("%f[%a]tbn%f[%A]") then
        min_p, max_p, center_p = 38, 69, 50
        family, role_label, rank_bias = "trombone", "Tbn (D2–A4)", -2
    elseif name_l:find("viola") or name_l:find("bratsche") or name_l:match("%f[%a]vla%f[%A]") or name_l:match("%f[%a]va%f[%A]") then
        min_p, max_p, center_p = 48, 79, 58 -- C3 .. G5 (Viola)
        family, role_label, rank_bias = "viola", "Viola (C3–G5)", 0
    elseif name_l:find("horn") or name_l:find("corno") or name_l:match("%f[%a]hn%f[%A]") then
        min_p, max_p, center_p = 43, 77, 57
        family, role_label, rank_bias = "horn", "Horn (G2–F5)", 0
    elseif name_l:find("clarinet") or name_l:find("klarinette") or name_l:match("%f[%a]cl%f[%A]") then
        min_p, max_p, center_p = 50, 86, 63
        family, role_label, rank_bias = "clarinet", "Clar (D3–D6)", 1
    elseif name_l:find("violin") or name_l:find("violine") or name_l:find("geige") or name_l:match("%f[%a]vln%f[%A]") or name_l:match("%f[%a]vl%f[%A]") then
        if name_l:match("2") or name_l:match("%f[%a]ii%f[%A]") or name_l:find("2nd") or name_l:find("second") then
            min_p, max_p, center_p = 55, 88, 65 -- G3 .. E6 (Violin 2)
            family, role_label, rank_bias = "violin2", "Vln 2 (G3–E6)", 2
            is_primary_section_voice = false
        elseif name_l:match("1") or name_l:match("%f[%a]i%f[%A]") or name_l:find("1st") or name_l:find("first") then
            min_p, max_p, center_p = 55, 93, 72 -- G3 .. A6 (Violin 1)
            family, role_label, rank_bias = "violin1", "Vln 1 (G3–A6)", 5
        else
            min_p, max_p, center_p = 55, 91, 69 -- G3 .. G6 (Generic Violin)
            family, role_label, rank_bias = "violin", "Violin (G3–G6)", 3
        end
    elseif name_l:find("piccolo") or name_l:match("%f[%a]picc%f[%A]") then
        min_p, max_p, center_p = 62, 98, 80
        family, role_label, rank_bias = "piccolo", "Picc (D4–D7)", 9
    elseif name_l:find("flute") or name_l:find("flöte") or name_l:find("floete") or name_l:match("%f[%a]fl%f[%A]") then
        min_p, max_p, center_p = 60, 93, 74
        family, role_label, rank_bias = "flute", "Flute (C4–A6)", 6
    elseif name_l:find("oboe") or name_l:match("%f[%a]ob%f[%A]") then
        min_p, max_p, center_p = 58, 88, 70
        family, role_label, rank_bias = "oboe", "Oboe (Bb3–E6)", 4
    elseif name_l:find("trumpet") or name_l:find("trompete") or name_l:match("%f[%a]tpt%f[%A]") or name_l:match("%f[%a]trp%f[%A]") then
        min_p, max_p, center_p = 54, 84, 67
        family, role_label, rank_bias = "trumpet", "Tpt (F#3–C6)", 3
    elseif name_l:find("bass") and not name_l:find("bassoon") then
        min_p, max_p, center_p = 26, 57, 40
        family, role_label, rank_bias = "double_bass", "Bass (D1–A3)", -6
    end

    return {
        track = trk,
        guid = guid,
        track_idx = track_idx,
        name = tname,
        clef_id = clef_id,
        min_p = min_p,
        max_p = max_p,
        center_p = center_p,
        effective_center = center_p,
        family = family,
        role_label = role_label,
        rank_bias = rank_bias,
        is_primary_section_voice = is_primary_section_voice,
        voice_rank = 1
    }
end

--- Collects and sorts all currently armed tracks from Highest Register (#1) to Lowest Register (#M)
--- @param state table
--- @return table armed_profiles, table by_guid
function RecordQuantizeService.get_armed_tracks_divisi_profile(state)
    local profiles = {}
    local by_guid = {}
    local ap = package.loaded["services.audio_preview"]
    local trk_cnt = reaper.CountTracks(0)

    for ti = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            local is_armed
            if ap and ap.is_track_user_armed then
                is_armed = ap.is_track_user_armed(trk)
            else
                is_armed = (reaper.GetMediaTrackInfo_Value(trk, "I_RECARM") == 1)
            end
            if is_armed then
                local prof = RecordQuantizeService.get_track_register_profile(state, trk)
                table.insert(profiles, prof)
                if prof.guid then
                    by_guid[prof.guid] = prof
                end
            end
        end
    end

    -- Stagger tracks that share the exact same family & center_p (e.g. two generic "Violin" or two "Treble" tracks)
    local by_fam = {}
    for _, p in ipairs(profiles) do
        local fkey = string.format("%s_%d", p.family or "gen", p.center_p or 60)
        by_fam[fkey] = by_fam[fkey] or {}
        table.insert(by_fam[fkey], p)
    end
    for _, group in pairs(by_fam) do
        if #group > 1 then
            for idx, p in ipairs(group) do
                local offset = ((#group + 1) * 0.5 - idx) * 4.5
                p.effective_center = p.center_p + offset
                if idx > 1 then
                    p.is_primary_section_voice = false
                end
            end
        end
    end

    -- Sort from highest register to lowest register; tie-break by top-to-bottom track index
    table.sort(profiles, function(a, b)
        local score_a = (a.effective_center or 60) + (a.rank_bias or 0)
        local score_b = (b.effective_center or 60) + (b.rank_bias or 0)
        if math.abs(score_a - score_b) > 0.25 then
            return score_a > score_b
        end
        return (a.track_idx or 1) < (b.track_idx or 1)
    end)

    for rank, p in ipairs(profiles) do
        p.voice_rank = rank
    end

    return profiles, by_guid
end

--- Assigns a chronological session note list across `armed_profiles` using:
--- 1. Tick-based micro-splinter suppression (`rec_divisi_tol_ticks`)
--- 2. Tick-based chord attack grouping (`|raw_sqn_2 - raw_sqn_1| <= tol_qn`)
--- 3. Tick-based legato finger-overlap trimming (`overlap <= 1.65 * tol_qn`)
--- 4. Monotonic Register-Aware Dynamic Programming Assignment (no voice crossing)
--- @param raw_notes table Array of { pitch, sqn, eqn, raw_sqn, raw_eqn, vel, chan, is_held, ... }
--- @param armed_profiles table Sorted array of armed track profiles (#1 Highest .. #M Lowest)
--- @param state table
--- @return table unique_assigned_notes
function RecordQuantizeService.compute_auto_divisi_assignment(raw_notes, armed_profiles, state)
    if not raw_notes or #raw_notes == 0 then return {} end
    local M = (armed_profiles and #armed_profiles) or 0
    if M == 0 then return raw_notes end

    local tol_ticks = math.max(5, tonumber(state and state.rec_divisi_tol_ticks) or 45)
    local tol_qn = tol_ticks / 960.0
    local min_splinter_qn = math.min(45, tol_ticks * 0.80) / 960.0
    local mode = (state and state.rec_auto_divisi_mode) or "smart_register"
    local do_quantize = (not state) or (state.rec_auto_quantize ~= false)

    -- 1. Copy and sort chronologically by raw_sqn
    local sorted = {}
    for _, n in ipairs(raw_notes) do
        local r_sqn = n.raw_sqn or n.raw_start_qn or n.sqn or n.start_qn or 0
        local s_sqn = n.sqn or n.start_qn or r_sqn
        local s_eqn = n.eqn or n.end_qn or (s_sqn + 0.25)
        local r_eqn = n.raw_eqn or s_eqn
        table.insert(sorted, {
            orig = n,
            pitch = n.pitch or 60,
            vel = n.vel or 96,
            chan = n.chan or 0,
            sqn = s_sqn,
            eqn = s_eqn,
            raw_sqn = r_sqn,
            raw_eqn = r_eqn,
            is_held = (n.is_held == true),
            _divisi_drop = false,
            assigned_guid = armed_profiles[1].guid,
            assigned_rank = 1
        })
    end

    table.sort(sorted, function(a, b)
        if math.abs(a.raw_sqn - b.raw_sqn) > 0.001 then
            return a.raw_sqn < b.raw_sqn
        end
        if math.abs(a.sqn - b.sqn) > 0.001 then
            return a.sqn < b.sqn
        end
        return a.pitch > b.pitch
    end)

    -- 2. Deduplicate identical physical notes across armed takes (same pitch & within ±max(18 ticks, 0.5*tol))
    local unique = {}
    local dedup_qn = math.max(18.0 / 960.0, tol_qn * 0.55)
    for _, item in ipairs(sorted) do
        local merged_existing = false
        for k = #unique, math.max(1, #unique - 16), -1 do
            local prev = unique[k]
            if (item.raw_sqn - prev.raw_sqn) > dedup_qn * 1.5 then
                break
            end
            if prev.pitch == item.pitch and math.abs(item.raw_sqn - prev.raw_sqn) <= dedup_qn then
                if item.vel > prev.vel then prev.vel = item.vel end
                if item.raw_eqn > prev.raw_eqn then prev.raw_eqn = item.raw_eqn end
                if item.eqn > prev.eqn then prev.eqn = item.eqn end
                if item.is_held then prev.is_held = true end
                merged_existing = true
                break
            end
        end
        if not merged_existing then
            table.insert(unique, item)
        end
    end

    if M == 1 then
        for _, u in ipairs(unique) do
            u.assigned_guid = armed_profiles[1].guid
            u.assigned_rank = 1
            if u.orig then
                u.orig.assigned_guid = u.assigned_guid
            end
        end
        return unique
    end

    -- 3. Micro-Splinter Filter: suppress accidental grazing keys (< min_splinter_qn) during note transitions
    if #unique > 1 then
        for i = 1, #unique do
            local u = unique[i]
            local raw_dur = u.raw_eqn - u.raw_sqn
            if not u.is_held and raw_dur < min_splinter_qn then
                local has_neighbor = false
                if i > 1 and math.abs(u.raw_sqn - unique[i - 1].raw_sqn) <= (tol_qn * 2.5) then
                    has_neighbor = true
                elseif i < #unique and math.abs(unique[i + 1].raw_sqn - u.raw_sqn) <= (tol_qn * 2.5) then
                    has_neighbor = true
                elseif i > 1 and math.abs(u.raw_sqn - unique[i - 1].raw_eqn) <= (tol_qn * 1.5) then
                    has_neighbor = true
                end
                if has_neighbor then
                    u._divisi_drop = true
                    if u.orig then u.orig._divisi_drop = true end
                end
            end
        end
    end

    -- 4. Group non-dropped notes into Simultaneous Chord Attack Clusters within tol_qn
    local clusters = {}
    for _, u in ipairs(unique) do
        if not u._divisi_drop then
            local last_c = clusters[#clusters]
            local join_cluster = false
            if last_c then
                local raw_diff = math.abs(u.raw_sqn - last_c.raw_sqn)
                local snap_same = do_quantize and (math.abs(u.sqn - last_c.sqn) <= 0.004) and (raw_diff <= tol_qn * 1.75)
                if raw_diff <= tol_qn or snap_same then
                    join_cluster = true
                end
            end

            if join_cluster then
                -- Check if same pitch already exists in this chord cluster
                local dup_in_c = false
                for _, cn in ipairs(last_c.notes) do
                    if cn.pitch == u.pitch then
                        if u.raw_eqn > cn.raw_eqn then cn.raw_eqn = u.raw_eqn end
                        if u.eqn > cn.eqn then cn.eqn = u.eqn end
                        if u.vel > cn.vel then cn.vel = u.vel end
                        u._divisi_drop = true
                        if u.orig then u.orig._divisi_drop = true end
                        dup_in_c = true
                        break
                    end
                end
                if not dup_in_c then
                    table.insert(last_c.notes, u)
                end
            else
                table.insert(clusters, {
                    raw_sqn = u.raw_sqn,
                    sqn = u.sqn,
                    notes = { u }
                })
            end
        end
    end

    -- Sort notes within each chord cluster strictly from Highest Pitch to Lowest Pitch
    for _, c in ipairs(clusters) do
        table.sort(c.notes, function(a, b) return a.pitch > b.pitch end)
    end

    -- 5. Tick-Based Legato Finger-Overlap Guard between Consecutive Clusters
    -- If a note in cluster[ci] overlaps the attack of cluster[ci+1] by <= 1.65 * tol_qn,
    -- trim its tail to cluster[ci+1] so releasing fingers don't trigger false Divisi splits!
    local legato_release_window = tol_qn * 1.65
    for ci = 1, #clusters - 1 do
        local cur_c = clusters[ci]
        local next_c = clusters[ci + 1]
        for _, un in ipairs(cur_c.notes) do
            local raw_ov = un.raw_eqn - next_c.raw_sqn
            if raw_ov > 0 and raw_ov <= legato_release_window then
                un.raw_eqn = next_c.raw_sqn
                if un.eqn > next_c.sqn and next_c.sqn >= un.sqn + 0.04 then
                    un.eqn = next_c.sqn
                    un._trimmed_eqn = next_c.sqn
                    if un.orig then
                        un.orig.end_qn = next_c.sqn
                        un.orig.dur_qn = math.max(0.05, next_c.sqn - (un.orig.start_qn or un.sqn))
                        un.orig._trimmed_eqn = next_c.sqn
                    end
                end
            end
        end
    end

    -- 6. Monotonic Register & Voice Assignment across Armed Tracks
    local sustained_by_track = {} -- k -> { pitch = number, raw_eqn = number }
    local prev_single_track_k = nil
    local prev_single_pitch = nil

    for _, c in ipairs(clusters) do
        local N = #c.notes
        local is_sustained = {}
        for k = 1, M do
            local st = sustained_by_track[k]
            if st and st.raw_eqn > (c.raw_sqn + legato_release_window) then
                is_sustained[k] = true
            else
                sustained_by_track[k] = nil
            end
        end

        local function single_note_cost(pitch, k, is_solo_cluster)
            local prof = armed_profiles[k]
            local dist = math.abs(pitch - (prof.effective_center or prof.center_p or 60))
            local out_pen = 0
            if pitch < prof.min_p then
                out_pen = 42.0 + (prof.min_p - pitch) * 3.5
            elseif pitch > prof.max_p then
                out_pen = 42.0 + (pitch - prof.max_p) * 3.5
            end
            local sust_pen = is_sustained[k] and 34.0 or 0.0
            local lead_bonus = 0.0
            if is_solo_cluster then
                if prof.is_primary_section_voice ~= false then
                    lead_bonus = -5.5
                end
                if prev_single_track_k == k and prev_single_pitch and math.abs(pitch - prev_single_pitch) <= 7 and out_pen == 0 and not is_sustained[k] then
                    lead_bonus = lead_bonus - 5.0
                end
            end
            return dist + out_pen + sust_pen + lead_bonus
        end

        if mode == "top_down" then
            -- Pure Top-Down Voice Split (1st Note -> Track 1, 2nd -> Track 2, ...)
            local used_k = 0
            for i = 1, N do
                local target_k = math.min(M, i)
                for cand_k = used_k + 1, M do
                    if not is_sustained[cand_k] then
                        target_k = cand_k
                        break
                    end
                end
                used_k = target_k
                local cn = c.notes[i]
                cn.assigned_rank = target_k
                cn.assigned_guid = armed_profiles[target_k].guid
                if cn.orig then cn.orig.assigned_guid = cn.assigned_guid end
            end
        elseif N == 1 then
            -- Single melodic/bass note: pick lowest-cost register track with melodic continuity
            local cn = c.notes[1]
            local best_k = 1
            local best_cost = 1e9
            for k = 1, M do
                local cost = single_note_cost(cn.pitch, k, true)
                if cost < best_cost then
                    best_cost = cost
                    best_k = k
                end
            end
            cn.assigned_rank = best_k
            cn.assigned_guid = armed_profiles[best_k].guid
            if cn.orig then cn.orig.assigned_guid = cn.assigned_guid end
            prev_single_track_k = best_k
            prev_single_pitch = cn.pitch
        elseif N <= M then
            -- Chord with N <= M notes: Exact Monotonic DP (1 <= k_1 < k_2 < ... < k_N <= M)
            local dp = {}
            local parent = {}
            for i = 1, N do
                dp[i] = {}
                parent[i] = {}
                for k = 1, M do
                    dp[i][k] = 1e9
                end
            end

            for k = 1, M - N + 1 do
                dp[1][k] = single_note_cost(c.notes[1].pitch, k, false)
            end

            for i = 2, N do
                local p_cur = c.notes[i].pitch
                local p_prev = c.notes[i - 1].pitch
                local pitch_gap = p_prev - p_cur
                for k = i, M - (N - i) do
                    local base_c = single_note_cost(p_cur, k, false)
                    for prev_k = i - 1, k - 1 do
                        local step_adj = 0.0
                        if pitch_gap <= 9 and (k == prev_k + 1) then
                            -- Close interval (<= 6th): reward pairing adjacent Divisi instruments (e.g. Vln 1+2 or Vc+Cb)
                            step_adj = -4.5
                        elseif pitch_gap >= 14 and (k == prev_k + 1) and M > N then
                            step_adj = 2.5
                        end
                        local cand = dp[i - 1][prev_k] + base_c + step_adj
                        if cand < dp[i][k] then
                            dp[i][k] = cand
                            parent[i][k] = prev_k
                        end
                    end
                end
            end

            local best_last_k = N
            local best_total = 1e9
            for k = N, M do
                if dp[N][k] < best_total then
                    best_total = dp[N][k]
                    best_last_k = k
                end
            end

            local cur_k = best_last_k
            for i = N, 1, -1 do
                local cn = c.notes[i]
                cn.assigned_rank = cur_k
                cn.assigned_guid = armed_profiles[cur_k].guid
                if cn.orig then cn.orig.assigned_guid = cn.assigned_guid end
                cur_k = parent[i][cur_k] or math.max(1, cur_k - 1)
            end
            prev_single_track_k = nil
        else
            -- Chord with N > M notes (more simultaneous notes than armed tracks):
            -- Monotonic non-decreasing assignment (1 <= k_1 <= k_2 <= ... <= k_N <= M)
            local prev_k = 1
            for i = 1, N do
                local cn = c.notes[i]
                local remaining_notes = N - i
                local max_allowed_k = math.min(M, M - math.min(M - prev_k, remaining_notes))
                if max_allowed_k < prev_k then max_allowed_k = prev_k end

                local best_k = prev_k
                local best_c = 1e9
                for k = prev_k, M do
                    local cost = single_note_cost(cn.pitch, k, false)
                    if cost < best_c then
                        best_c = cost
                        best_k = k
                    end
                end
                prev_k = best_k
                cn.assigned_rank = best_k
                cn.assigned_guid = armed_profiles[best_k].guid
                if cn.orig then cn.orig.assigned_guid = cn.assigned_guid end
            end
            prev_single_track_k = nil
        end

        -- Record sustained notes on their assigned tracks
        for _, cn in ipairs(c.notes) do
            local rk = cn.assigned_rank
            if rk then
                local cur_st = sustained_by_track[rk]
                if not cur_st or cn.raw_eqn > cur_st.raw_eqn then
                    sustained_by_track[rk] = { pitch = cn.pitch, raw_eqn = cn.raw_eqn }
                end
            end
        end
    end

    return unique
end

--- Returns merged note list (pre-existing take notes + real-time quantized session notes) for a track during recording
--- @param state table
--- @param tdata table Track data entry in ScoreCanvas
--- @return table merged_notes, number max_live_qn
function RecordQuantizeService.get_merged_live_notes_for_track(state, tdata)
    local base_notes = (tdata and tdata.notes) or {}
    if not state then
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

    local play_pos = reaper.GetPlayPosition()
    local play_qn = math.max(0, reaper.TimeMap2_timeToQN(0, play_pos))
    local start_time = (state and state._rec_start_time) or 0
    local min_rec_qn = reaper.TimeMap2_timeToQN(0, start_time)
    local eff_grid = get_effective_grid_qn(state)
    local min_step_qn = (state and state.rec_auto_quantize ~= false) and eff_grid or math.min(0.25, eff_grid)
    local clean_overlaps = (not state) or (state.rec_clean_overlaps ~= false)

    local is_midi, trk_dev, trk_chan = RecordQuantizeService.decode_midi_recinput(
        reaper.GetMediaTrackInfo_Value(tdata.track, "I_RECINPUT")
    )

    local merged = {}
    local session_notes = {}
    local max_live_qn = 0

    -- 1. Separate pre-existing notes from newly recorded session notes in base_notes (MIDI Overdub)
    for idx, n in ipairs(base_notes) do
        if is_note_pre_existing(n.take, n.pitch, n.start_qn, n.chan, min_rec_qn) then
            table.insert(merged, n)
        else
            -- This note was added into the take by REAPER during the current recording session!
            -- While a key is still held down in MIDI Overdub mode, REAPER temporarily sets n.end_qn
            -- to the end of the entire MIDI item. Strictly clamp its live end to play_qn!
            local is_still_held = (n.end_qn > play_qn + 0.08)
            if not is_still_held then
                -- REAPER has already closed this note with a Note-Off; make sure _held_notes is also closed
                local held = RecordQuantizeService._held_notes[n.pitch]
                if held and math.abs(held.raw_start_qn - n.start_qn) < 0.25 then
                    held.is_held = false
                    RecordQuantizeService._held_notes[n.pitch] = nil
                end
            end

            local raw_eqn = is_still_held and math.max(n.start_qn + min_step_qn, play_qn) or math.min(n.end_qn, play_qn + 0.05)
            local raw_dur = math.max(0.05, raw_eqn - n.start_qn)
            local q_res = evaluate_note_quantization(state, n.start_qn, raw_dur)

            if q_res.action ~= "delete" then
                local q_sqn = q_res.sqn
                local q_dur = q_res.dur_qn
                local q_eqn = q_sqn + q_dur
                local q_chan = q_res.chan_override or n.chan or 0

                local live_copy = MidiNote.new({
                    idx = n.idx or (-2000 - idx),
                    pitch = n.pitch,
                    start_qn = q_sqn,
                    end_qn = q_eqn,
                    dur_qn = q_dur,
                    vel = n.vel or 96,
                    chan = q_chan,
                    take = n.take,
                    item = n.item,
                    track = tdata.track
                })
                live_copy.raw_start_qn = n.start_qn
                live_copy.raw_eqn = raw_eqn
                live_copy.is_live_recording = true
                live_copy.is_held = is_still_held
                table.insert(session_notes, live_copy)
                if q_eqn > max_live_qn then
                    max_live_qn = q_eqn
                end
            end
        end
    end

    -- 2. Include live input preview notes that haven't been flushed to base_notes yet
    if state.rec_live_preview ~= false then
        for idx, ln in ipairs(RecordQuantizeService._live_notes) do
            local dev_ok = (not is_midi) or (trk_dev == 63) or (trk_dev == 62) or (ln.dev_idx == nil) or (ln.dev_idx == trk_dev)
            local chan_ok = (not is_midi) or (trk_chan == 0) or ((ln.chan + 1) == trk_chan) or (ln.chan == 15)

            if dev_ok and chan_ok then
                local already_in_take = false
                for _, bn in ipairs(base_notes) do
                    if bn.pitch == ln.pitch and (math.abs(bn.start_qn - ln.start_qn) < 0.22 or math.abs(bn.start_qn - ln.raw_start_qn) < 0.22) then
                        already_in_take = true
                        break
                    end
                end

                if not already_in_take then
                    local clamped_eqn = math.min(ln.end_qn, math.max(ln.start_qn + min_step_qn, play_qn + eff_grid))
                    local clamped_dur = math.max(min_step_qn, clamped_eqn - ln.start_qn)
                    local preview_note = MidiNote.new({
                        idx = -1000 - idx,
                        pitch = ln.pitch,
                        start_qn = ln.start_qn,
                        end_qn = clamped_eqn,
                        dur_qn = clamped_dur,
                        vel = ln.vel or 96,
                        chan = ln.chan or 0,
                        take = nil,
                        item = nil,
                        track = tdata.track
                    })
                    preview_note.raw_start_qn = ln.raw_start_qn
                    preview_note.raw_eqn = clamped_eqn
                    preview_note.is_live_recording = true
                    preview_note.is_held = ln.is_held
                    table.insert(session_notes, preview_note)
                    if clamped_eqn > max_live_qn then
                        max_live_qn = clamped_eqn
                    end
                end
            end
        end
    end

    -- 2b. Live Auto-Divisi Filtering: when multiple tracks are armed and Auto-Divisi is enabled,
    -- show only the notes assigned to THIS track's register/voice on the live ScoreCanvas!
    if state.rec_auto_divisi and #session_notes > 0 then
        local armed_profiles = RecordQuantizeService.get_armed_tracks_divisi_profile(state)
        if #armed_profiles >= 2 then
            local trk_guid = tdata.guid or reaper.GetTrackGUID(tdata.track)
            RecordQuantizeService.compute_auto_divisi_assignment(session_notes, armed_profiles, state)
            local divisi_filtered = {}
            for _, sn in ipairs(session_notes) do
                if not sn._divisi_drop and sn.assigned_guid == trk_guid then
                    table.insert(divisi_filtered, sn)
                end
            end
            session_notes = divisi_filtered
        end
    end

    -- 3. Clean bounces (<15 ticks), duplicate grid snaps, and same-pitch overlaps on session_notes
    if clean_overlaps and #session_notes > 1 then
        table.sort(session_notes, function(a, b)
            local as = a.start_qn or a.raw_start_qn or 0
            local bs = b.start_qn or b.raw_start_qn or 0
            if math.abs(as - bs) > 0.001 then return as < bs end
            local ras = a.raw_start_qn or as
            local rbs = b.raw_start_qn or bs
            if math.abs(ras - rbs) > 0.001 then return ras < rbs end
            return (a.pitch or 0) < (b.pitch or 0)
        end)
        local by_pitch = {}
        for _, sn in ipairs(session_notes) do
            by_pitch[sn.pitch] = by_pitch[sn.pitch] or {}
            table.insert(by_pitch[sn.pitch], sn)
        end
        for _, p_list in pairs(by_pitch) do
            local prev = nil
            for k = 1, #p_list do
                local cur = p_list[k]
                if not cur._drop then
                    if not prev then
                        prev = cur
                    else
                        local raw_s1 = prev.raw_start_qn or prev.start_qn
                        local raw_s2 = cur.raw_start_qn or cur.start_qn
                        if math.abs(raw_s2 - raw_s1) * 960.0 < 15.0 or math.abs(cur.start_qn - prev.start_qn) * 960.0 < 15.0 then
                            -- Hardware bounce or two notes snapped to the exact same grid slot
                            if (cur.vel or 96) > (prev.vel or 96) then
                                prev._drop = true
                                prev = cur
                            else
                                if (cur.end_qn or 0) > (prev.end_qn or 0) then
                                    prev.end_qn = cur.end_qn
                                    prev.dur_qn = prev.end_qn - prev.start_qn
                                end
                                cur._drop = true
                            end
                        elseif prev.end_qn > cur.start_qn then
                            prev.end_qn = cur.start_qn
                            prev.dur_qn = prev.end_qn - prev.start_qn
                            prev = cur
                        else
                            prev = cur
                        end
                    end
                end
            end
        end
    end

    for _, sn in ipairs(session_notes) do
        if not sn._drop then
            table.insert(merged, sn)
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
-- 3. POST-RECORD TAKE QUANTIZATION, AUTO-DIVISI & INFINITE-NOTE CLAMPING ENGINE
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
        start_time, stop_time = stop_time, stop_time
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

--- Builds a cross-track Auto-Divisi assignment list from all newly recorded takes
local function build_post_record_divisi_plan(state, takes, armed_profiles, min_rec_qn, max_rec_qn)
    if not state or not state.rec_auto_divisi or not armed_profiles or #armed_profiles < 2 then
        return nil
    end

    local eff_grid = get_effective_grid_qn(state)
    local do_quantize = (state.rec_auto_quantize ~= false)
    local tolerance_ticks = state.rec_tolerance_ticks or 25
    local outlier_mode = state.rec_outlier_mode or "snap"

    local raw_all = {}
    for _, take in ipairs(takes) do
        local _, notecnt = reaper.MIDI_CountEvts(take)
        for i = 0, notecnt - 1 do
            local ok, _, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
            if ok and not muted then
                local raw_sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                local raw_eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                if not is_note_pre_existing(take, pitch, raw_sqn, chan, min_rec_qn) then
                    if max_rec_qn and raw_eqn > max_rec_qn + 0.10 then
                        raw_eqn = math.max(raw_sqn + eff_grid, max_rec_qn)
                    end
                    local sqn = raw_sqn
                    local eqn = raw_eqn
                    if do_quantize then
                        local orig_dur_qn = math.max(0.05, raw_eqn - raw_sqn)
                        local _, qn_measure_start, _ = reaper.TimeMap_QNToMeasures(0, raw_sqn)
                        local rel_qn = raw_sqn - qn_measure_start
                        local nearest_k = math.floor((rel_qn / eff_grid) + 0.5)
                        local nearest_grid_qn = qn_measure_start + (nearest_k * eff_grid)
                        local diff_ticks = math.abs(raw_sqn - nearest_grid_qn) * 960.0
                        if diff_ticks <= (tolerance_ticks + 0.05) or outlier_mode == "snap" then
                            sqn = math.max(0, nearest_grid_qn)
                            local snapped_dur = math.max(eff_grid, math.floor((orig_dur_qn / eff_grid) + 0.5) * eff_grid)
                            eqn = sqn + snapped_dur
                        end
                    end
                    table.insert(raw_all, {
                        pitch = pitch,
                        vel = vel,
                        chan = chan,
                        raw_sqn = raw_sqn,
                        raw_eqn = raw_eqn,
                        sqn = sqn,
                        eqn = eqn,
                        is_held = false
                    })
                end
            end
        end
    end

    if #raw_all == 0 then
        return nil
    end

    return RecordQuantizeService.compute_auto_divisi_assignment(raw_all, armed_profiles, state)
end

--- Core quantization & Auto-Divisi filtering pass on a single take when recording stops
--- @param state table
--- @param take userdata MediaItem_Take*
--- @param min_rec_qn number Minimum QN where current recording started
--- @param max_rec_qn number Maximum QN where current recording stopped
--- @param divisi_plan table|nil Optional Auto-Divisi assignment list
--- @return number notecnt, number snapped, number cleaned, number outliers, boolean modified, number divisi_kept
local function quantize_single_take(state, take, min_rec_qn, max_rec_qn, divisi_plan)
    local eff_grid = get_effective_grid_qn(state)
    local do_quantize = (not state) or (state.rec_auto_quantize ~= false)
    local tolerance_ticks = (state and state.rec_tolerance_ticks) or 25
    local clean_overlaps = (not state) or (state.rec_clean_overlaps ~= false)
    local outlier_mode = (state and state.rec_outlier_mode) or "snap"
    local divisi_tol_ticks = math.max(5, tonumber(state and state.rec_divisi_tol_ticks) or 45)
    local divisi_match_qn = math.max(24.0 / 960.0, (divisi_tol_ticks / 960.0) * 0.75)

    local take_trk = reaper.GetMediaItemTake_Track(take)
    local take_trk_guid = (take_trk and reaper.ValidatePtr(take_trk, "MediaTrack*")) and reaper.GetTrackGUID(take_trk) or nil

    local _, notecnt = reaper.MIDI_CountEvts(take)
    if notecnt == 0 then
        return 0, 0, 0, 0, false, 0
    end

    local notes = {}
    for i = 0, notecnt - 1 do
        local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if ok then
            local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
            local eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
            local pre_existing = is_note_pre_existing(take, pitch, sqn, chan, min_rec_qn)
            local in_session = not pre_existing
            table.insert(notes, {
                idx = i,
                sel = sel,
                muted = muted,
                sppq = sppq,
                eppq = eppq,
                sqn = sqn,
                eqn = eqn,
                raw_sqn = sqn,
                chan = chan,
                pitch = pitch,
                vel = vel,
                in_session = in_session,
                action = "keep"
            })
        end
    end

    local snapped_cnt = 0
    local cleaned_cnt = 0
    local outlier_cnt = 0
    local divisi_kept = 0
    local any_modified = false

    -- 0. Apply Auto-Divisi Track Assignment & Legato Transition Trimming
    if divisi_plan and take_trk_guid then
        for _, n in ipairs(notes) do
            if n.in_session and n.action ~= "delete" then
                local matched_u = nil
                local best_diff = 1e9
                for _, u in ipairs(divisi_plan) do
                    if u.pitch == n.pitch then
                        local d = math.abs(n.raw_sqn - u.raw_sqn)
                        if d <= divisi_match_qn and d < best_diff then
                            best_diff = d
                            matched_u = u
                        end
                    end
                end

                if not matched_u or matched_u._divisi_drop or matched_u.assigned_guid ~= take_trk_guid then
                    n.action = "delete"
                    any_modified = true
                else
                    divisi_kept = divisi_kept + 1
                    -- Apply legato finger-overlap trim if computed by the Tick-Tolerance transition guard
                    if matched_u.raw_eqn and matched_u.raw_eqn < n.eqn - 0.01 then
                        n.eqn = math.max(n.sqn + 0.05, matched_u.raw_eqn)
                        n.eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n.eqn) + 0.5)
                        n.action = "modify"
                        any_modified = true
                    end
                end
            end
        end
    end

    -- 1. Clamp any unclosed/infinite session notes to max_rec_qn & apply Metric Grid Snapping + Outlier Handling
    for _, n in ipairs(notes) do
        if n.in_session and n.action ~= "delete" then
            -- Strict guard: a note recorded in this session can NEVER end past max_rec_qn (where recording stopped)!
            if max_rec_qn and n.eqn > max_rec_qn + 0.10 then
                n.eqn = math.max(n.sqn + eff_grid, max_rec_qn)
                n.eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n.eqn) + 0.5)
                n.action = "modify"
                any_modified = true
            end

            if do_quantize then
                local orig_dur_qn = math.max(0.05, n.eqn - n.sqn)
                local _, qn_measure_start, _ = reaper.TimeMap_QNToMeasures(0, n.sqn)
                local rel_qn = n.sqn - qn_measure_start
                local nearest_k = math.floor((rel_qn / eff_grid) + 0.5)
                local nearest_grid_qn = qn_measure_start + (nearest_k * eff_grid)
                local diff_ticks = math.abs(n.sqn - nearest_grid_qn) * 960.0
                if diff_ticks < 0.05 then diff_ticks = 0.0 end

                if diff_ticks <= (tolerance_ticks + 0.05) or outlier_mode == "snap" then
                    local new_sqn = math.max(0, nearest_grid_qn)
                    local snapped_dur = math.max(eff_grid, math.floor((orig_dur_qn / eff_grid) + 0.5) * eff_grid)
                    local new_eqn = new_sqn + snapped_dur
                    if max_rec_qn and new_eqn > max_rec_qn + eff_grid then
                        new_eqn = math.max(new_sqn + eff_grid, math.floor((max_rec_qn / eff_grid) + 0.5) * eff_grid)
                    end
                    local new_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, new_sqn) + 0.5)
                    local new_eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, new_eqn) + 0.5)

                    if new_sppq ~= n.sppq or new_eppq ~= n.eppq then
                        n.sppq = new_sppq
                        n.eppq = new_eppq
                        n.sqn = new_sqn
                        n.eqn = new_eqn
                        n.action = "modify"
                        any_modified = true
                    end
                    snapped_cnt = snapped_cnt + 1
                else
                    if outlier_mode == "delete" then
                        n.action = "delete"
                        any_modified = true
                        outlier_cnt = outlier_cnt + 1
                    elseif outlier_mode == "voice16" then
                        if n.chan ~= 15 then
                            n.chan = 15
                            n.action = "modify"
                            any_modified = true
                        end
                        outlier_cnt = outlier_cnt + 1
                    end
                end
            end
        end
    end

    -- 2. Group notes by pitch to resolve keyboard bounce (<15 ticks) & same-pitch overlaps
    if do_quantize and clean_overlaps then
        local by_pitch = {}
        for _, n in ipairs(notes) do
            if n.in_session and n.action ~= "delete" then
                if not by_pitch[n.pitch] then by_pitch[n.pitch] = {} end
                table.insert(by_pitch[n.pitch], n)
            end
        end

        for _, p_notes in pairs(by_pitch) do
            table.sort(p_notes, function(a, b) return a.sppq < b.sppq end)
            local prev = nil
            for k = 1, #p_notes do
                local cur = p_notes[k]
                if cur.action ~= "delete" then
                    if not prev then
                        prev = cur
                    else
                        if math.abs(cur.sppq - prev.sppq) < 15 then
                            if cur.vel > prev.vel then
                                prev.action = "delete"
                                prev = cur
                            else
                                if cur.eppq > prev.eppq then
                                    prev.eppq = cur.eppq
                                    prev.action = "modify"
                                end
                                cur.action = "delete"
                            end
                            any_modified = true
                            cleaned_cnt = cleaned_cnt + 1
                        elseif prev.eppq >= cur.sppq then
                            local clamped_eppq = math.max(prev.sppq + 20, cur.sppq)
                            if clamped_eppq < prev.eppq then
                                prev.eppq = clamped_eppq
                                prev.action = "modify"
                                any_modified = true
                                cleaned_cnt = cleaned_cnt + 1
                            end
                            prev = cur
                        else
                            prev = cur
                        end
                    end
                end
            end
        end
    end

    if any_modified then
        reaper.MIDI_DisableSort(take)
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

    return notecnt, snapped_cnt, cleaned_cnt, outlier_cnt, any_modified, divisi_kept
end

--- Final quantization, Auto-Divisi distribution & note-end clamping pass when recording stops
--- @param state table
--- @param start_time number
--- @param stop_time number
--- @return table stats
function RecordQuantizeService.process_recording(state, start_time, stop_time)
    RecordQuantizeService.clear_live_recording()
    RecordQuantizeService._realtime_take_counts = {}
    RecordQuantizeService._processed_note_sigs = {}

    local takes = RecordQuantizeService.get_recorded_takes(state, start_time, stop_time)
    if #takes == 0 then
        local at = MidiService.get_active_midi_take()
        if at and reaper.TakeIsMIDI(at) then
            table.insert(takes, at)
        end
    end

    if #takes == 0 then
        RecordQuantizeService._pre_existing_notes = {}
        MidiService.invalidate_cache()
        return { total_notes = 0, snapped = 0, cleaned = 0, outliers_handled = 0 }
    end

    local min_rec_qn = start_time and reaper.TimeMap2_timeToQN(0, start_time) or 0
    local max_rec_qn = stop_time and reaper.TimeMap2_timeToQN(0, stop_time) or nil
    if max_rec_qn and max_rec_qn < min_rec_qn then
        max_rec_qn = nil
    end

    local armed_profiles = nil
    local divisi_plan = nil
    if state and state.rec_auto_divisi then
        armed_profiles = RecordQuantizeService.get_armed_tracks_divisi_profile(state)
        if armed_profiles and #armed_profiles >= 2 then
            divisi_plan = build_post_record_divisi_plan(state, takes, armed_profiles, min_rec_qn, max_rec_qn)
        end
    end

    reaper.Undo_BeginBlock2(0)

    local total_notes = 0
    local total_snapped = 0
    local total_cleaned = 0
    local total_outliers = 0
    local total_divisi_kept = 0

    for _, take in ipairs(takes) do
        local n_cnt, s_cnt, c_cnt, o_cnt, _, d_kept = quantize_single_take(state, take, min_rec_qn, max_rec_qn, divisi_plan)
        total_notes = total_notes + n_cnt
        total_snapped = total_snapped + s_cnt
        total_cleaned = total_cleaned + c_cnt
        total_outliers = total_outliers + o_cnt
        total_divisi_kept = total_divisi_kept + (d_kept or 0)
    end

    local undo_lbl = divisi_plan and "Auto-Divisi & Real-Time Quantize Recorded MIDI" or "Real-Time Auto-Quantize Recorded MIDI"
    reaper.Undo_EndBlock2(0, undo_lbl, -1)

    RecordQuantizeService._pre_existing_notes = {}
    MidiService.invalidate_cache()

    local stats = {
        total_notes = total_notes,
        snapped = total_snapped,
        cleaned = total_cleaned,
        outliers_handled = total_outliers,
        divisi_kept = total_divisi_kept
    }

    if state and total_notes > 0 then
        if divisi_plan and armed_profiles then
            state.status_msg = string.format("🎼 Auto-Divisi Recording: Distributed %d notes across %d armed tracks (±%d Ticks transition guard)",
                total_divisi_kept, #armed_profiles, state.rec_divisi_tol_ticks or 45)
        elseif state.rec_auto_quantize ~= false then
            state.status_msg = string.format("⚡ Real-Time Auto-Quantize: %d notes processed (%d snapped to %s, %d overlaps cleaned)",
                total_notes, total_snapped, state.rec_quantize_grid_label or "1/8", total_cleaned)
        end
    end

    return stats
end

return RecordQuantizeService

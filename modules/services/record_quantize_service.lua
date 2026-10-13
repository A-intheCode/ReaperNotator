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

RecordQuantizeService._pre_existing_notes = {}

--- Prepares all armed tracks right when recording starts and snapshots existing notes
--- @param state table
function RecordQuantizeService.on_record_start(state)
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
-- 3. POST-RECORD TAKE QUANTIZATION & INFINITE-NOTE CLAMPING ENGINE
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

--- Core quantization pass on a single take when recording stops
--- @param state table
--- @param take userdata MediaItem_Take*
--- @param min_rec_qn number Minimum QN where current recording started
--- @param max_rec_qn number Maximum QN where current recording stopped
--- @return number notecnt, number snapped, number cleaned, number outliers, boolean modified
local function quantize_single_take(state, take, min_rec_qn, max_rec_qn)
    local eff_grid = get_effective_grid_qn(state)
    local do_quantize = (not state) or (state.rec_auto_quantize ~= false)
    local tolerance_ticks = (state and state.rec_tolerance_ticks) or 25
    local clean_overlaps = (not state) or (state.rec_clean_overlaps ~= false)
    local outlier_mode = (state and state.rec_outlier_mode) or "snap"

    local _, notecnt = reaper.MIDI_CountEvts(take)
    if notecnt == 0 then
        return 0, 0, 0, 0, false
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
    local any_modified = false

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

    return notecnt, snapped_cnt, cleaned_cnt, outlier_cnt, any_modified
end

--- Final quantization & note-end clamping pass when recording stops
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

    reaper.Undo_BeginBlock2(0)

    local total_notes = 0
    local total_snapped = 0
    local total_cleaned = 0
    local total_outliers = 0

    for _, take in ipairs(takes) do
        local n_cnt, s_cnt, c_cnt, o_cnt = quantize_single_take(state, take, min_rec_qn, max_rec_qn)
        total_notes = total_notes + n_cnt
        total_snapped = total_snapped + s_cnt
        total_cleaned = total_cleaned + c_cnt
        total_outliers = total_outliers + o_cnt
    end

    reaper.Undo_EndBlock2(0, "Real-Time Auto-Quantize Recorded MIDI", -1)

    RecordQuantizeService._pre_existing_notes = {}
    MidiService.invalidate_cache()

    local stats = {
        total_notes = total_notes,
        snapped = total_snapped,
        cleaned = total_cleaned,
        outliers_handled = total_outliers
    }

    if state and state.rec_auto_quantize ~= false and total_notes > 0 then
        state.status_msg = string.format("⚡ Real-Time Auto-Quantize: %d notes processed (%d snapped to %s, %d overlaps cleaned)",
            total_notes, total_snapped, state.rec_quantize_grid_label or "1/8", total_cleaned)
    end

    return stats
end

return RecordQuantizeService

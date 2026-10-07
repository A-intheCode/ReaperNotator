-- ==============================================================================
-- REAPER Native Notator - Service: AudioPreview (Note preview like in MIDI Editor)
-- Auditioning notes when clicking, moving, drawing & transposing via MIDI API
-- Supports intelligent articulation chasing & strict single-track isolation
-- ==============================================================================

local AudioPreview = {}

AudioPreview.active_note = nil
AudioPreview.current_track = nil
AudioPreview.current_art_pc = nil
AudioPreview.last_audition_time = 0
AudioPreview.track_restore = {} -- [track_ptr] = { orig_arm = ..., orig_mon = ..., orig_inp = ..., changed_arm = bool, changed_mon = bool, changed_inp = bool }
AudioPreview.active_cc_override = nil -- { track = ..., chan = ..., cc = ..., items = { { chan = ..., cc = ..., orig_val = ... } } }

--- Restores any temporarily altered CC values to their original pre-preview state
--- @param state table
--- @param opt_track MediaTrack Optional track filter
function AudioPreview.restore_cc_override(state, opt_track)
    local ov = AudioPreview.active_cc_override
    if not ov then return end
    if opt_track and ov.track ~= opt_track then return end

    local should_restore = (state == nil or state.audition_restore_cc ~= false)
    if should_restore and ov.items then
        for _, item in ipairs(ov.items) do
            reaper.StuffMIDIMessage(0, 0xB0 + item.chan, item.cc, item.orig_val)
        end
    end
    AudioPreview.active_cc_override = nil
end

--- Finds the existing CC value in the track/take at or before the given QN
--- @param track MediaTrack
--- @param chan number 0-15
--- @param cc_num number 0-127
--- @param qn number
--- @param opt_take MediaItem_Take Optional take pointer
--- @return number orig_val
function AudioPreview.get_track_cc_at_qn(track, chan, cc_num, qn, opt_take)
    local target_chan = chan or 0
    local target_cc = cc_num or 11
    local qn_pos = qn or 0

    local take = opt_take
    if not take and track and reaper.ValidatePtr(track, "MediaTrack*") then
        local item_cnt = reaper.CountTrackMediaItems(track)
        for ii = 0, item_cnt - 1 do
            local item = reaper.GetTrackMediaItem(track, ii)
            if item then
                local ipos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local ilen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local i_sqn = reaper.TimeMap2_timeToQN(0, ipos)
                local i_eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                if qn_pos >= i_sqn - 0.05 and qn_pos <= i_eqn + 0.05 then
                    take = reaper.GetActiveTake(item)
                    break
                end
            end
        end
    end

    if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
        local target_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn_pos) + 15
        local _, _, cc_cnt = reaper.MIDI_CountEvts(take)
        local latest_ppq = -1
        local latest_val = nil
        for ci = 0, cc_cnt - 1 do
            local ok, _, _, ppq, chanmsg, cchan, msg2, msg3 = reaper.MIDI_GetCC(take, ci)
            if ok and (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) then
                if cchan == target_chan and msg2 == target_cc and ppq <= target_ppq then
                    if ppq >= latest_ppq then
                        latest_ppq = ppq
                        latest_val = msg3
                    end
                end
            end
        end
        if latest_val ~= nil then
            return latest_val
        end
    end

    -- Default fallbacks according to MIDI specification when no CC automation exists:
    -- Expression (11), Volume (7), Modwheel (1), Balance (8): default 127
    if target_cc == 11 or target_cc == 7 or target_cc == 8 or target_cc == 1 then
        return 127
    elseif target_cc == 10 then -- Pan centered
        return 64
    else
        return 0
    end
end

--- Restores a modified track cleanly to its original settings
--- @param track MediaTrack
function AudioPreview.restore_track(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return end
    if AudioPreview.active_cc_override and AudioPreview.active_cc_override.track == track then
        AudioPreview.restore_cc_override(nil, track)
    end
    if AudioPreview.current_track == track then
        AudioPreview.current_track = nil
        AudioPreview.current_art_pc = nil
    end
end

--- Restores all temporarily modified tracks
function AudioPreview.restore_all_tracks()
    AudioPreview.restore_cc_override(nil)
    AudioPreview.current_track = nil
    AudioPreview.current_art_pc = nil
    AudioPreview.track_restore = {}
end

--- Prepares a track for preview playback without modifying its arming or monitoring
--- @param track MediaTrack
function AudioPreview.prepare_track(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return end
    AudioPreview.current_track = track
end

--- Stops active note (sends Note Off via MIDI) and restores temporary CC overrides
--- @param state table
--- @param is_chaining boolean|nil If true, another note is playing immediately so CC override stays active
function AudioPreview.stop_note(state, is_chaining)
    local an = AudioPreview.active_note or (state and state.audition_active_note)
    if an then
        local ch = (an.chan or 0) & 0x0F
        reaper.StuffMIDIMessage(0, 0x80 + ch, an.pitch, 0)
        AudioPreview.active_note = nil
        if state then state.audition_active_note = nil end
    end

    if not is_chaining then
        AudioPreview.restore_cc_override(state)
    end
end

--- Finds closest written dynamic marker (before or at note)
--- @param state table
--- @param track MediaTrack
--- @param qn number
function AudioPreview.find_written_dynamic(state, track, qn)
    if not state or not track or not qn then return nil end
    local tracks_data = state.active_tracks_cache
    if not tracks_data then return nil end

    local best_dyn = nil
    for _, tdata in ipairs(tracks_data) do
        if tdata.track == track and tdata.dynamics then
            for _, d in ipairs(tdata.dynamics) do
                if d.qn <= (qn + 0.05) then
                    if not best_dyn or d.qn >= best_dyn.qn then
                        best_dyn = d
                    end
                end
            end
            break
        end
    end
    return best_dyn
end

--- Finds the active articulation for a track at a specific QN position
--- (scans from beginning to qn for persistent techniques & checks note-level articulation)
--- @param state table
--- @param track MediaTrack
--- @param qn number
--- @param chan number
--- @param opt_note table
--- @param bank table
--- @return table|nil target_art
function AudioPreview.find_active_articulation_at_qn(state, track, qn, chan, opt_note, bank)
    if not bank or not bank.articulations or #bank.articulations == 0 then
        return nil
    end

    local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")

    -- 1. Identify bank's default base articulation (e.g. Long / Sustain)
    local default_base_art = nil
    for _, ba in ipairs(bank.articulations) do
        if not MidiService.is_momentary_articulation(ba.name) then
            default_base_art = ba
            break
        end
    end
    if not default_base_art and #bank.articulations > 0 then
        default_base_art = bank.articulations[1]
    end

    -- 2. Scan from the beginning of the track/take up to qn for the active persistent technique
    local persistent_art = default_base_art
    local qn_pos = qn or (opt_note and opt_note.start_qn) or 0
    local target_chan = chan or (opt_note and opt_note.chan) or 0

    -- 2a. Check state.active_tracks_cache first if available
    local tracks_data = state and state.active_tracks_cache
    local found_in_cache = false
    if tracks_data then
        for _, tdata in ipairs(tracks_data) do
            if tdata.track == track and tdata.articulations then
                local latest_qn = -1
                local latest_pc = nil
                for _, art in ipairs(tdata.articulations) do
                    if (art.chan or 0) == target_chan and art.qn <= (qn_pos + 0.05) then
                        if art.qn >= latest_qn then
                            latest_qn = art.qn
                            latest_pc = art.pc
                        end
                    end
                end
                if latest_pc then
                    for _, ba in ipairs(bank.articulations) do
                        if ba.pc == latest_pc then
                            persistent_art = ba
                            found_in_cache = true
                            break
                        end
                    end
                end
                break
            end
        end
    end

    -- 2b. If not found in cache, inspect the take directly for Program Changes up to qn
    if not found_in_cache and track and reaper.ValidatePtr(track, "MediaTrack*") then
        local take = opt_note and opt_note.take
        if not take then
            local item_cnt = reaper.CountTrackMediaItems(track)
            for ii = 0, item_cnt - 1 do
                local item = reaper.GetTrackMediaItem(track, ii)
                local ipos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local ilen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local i_sqn = reaper.TimeMap2_timeToQN(0, ipos)
                local i_eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                if qn_pos >= i_sqn - 0.01 and qn_pos <= i_eqn + 0.01 then
                    take = reaper.GetActiveTake(item)
                    break
                end
            end
        end
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
            local target_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, qn_pos) + 15
            local _, _, cc_cnt = reaper.MIDI_CountEvts(take)
            local latest_ppq = -1
            local latest_pc = nil
            for ci = 0, cc_cnt - 1 do
                local ok, _, _, ppq, chanmsg, cchan, msg2 = reaper.MIDI_GetCC(take, ci)
                if ok and (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0) and cchan == target_chan and ppq <= target_ppq then
                    if ppq >= latest_ppq then
                        latest_ppq = ppq
                        latest_pc = msg2
                    end
                end
            end
            if latest_pc then
                for _, ba in ipairs(bank.articulations) do
                    if ba.pc == latest_pc then
                        persistent_art = ba
                        break
                    end
                end
            end
        end
    end

    -- 3. Check if note itself has a specific note-level articulation (staccato, marcato, tenuto, etc.)
    local note_art_id = opt_note and opt_note.articulation
    if not note_art_id and state and state.active_articulation then
        note_art_id = state.active_articulation
    end

    if note_art_id and note_art_id ~= "" and note_art_id ~= "none" then
        local match = MidiService.find_reaticulate_art_for_id(bank, note_art_id)
        if match then
            return match
        end
    end

    -- 4. Otherwise, the note plays the persistent articulation at this position
    return persistent_art
end

--- Plays a MIDI note (Note On) with proper articulation routing & track isolation
--- @param state table Notator state object
--- @param pitch number MIDI pitch (0-127)
--- @param vel number Velocity (1-127, default: 96)
--- @param chan number MIDI channel (0-15, default: 0)
--- @param track MediaTrack Optional REAPER track pointer
--- @param qn number Optional position in QN (to detect dynamic markers & articulations)
--- @param opt_note table Optional note object (to detect note-level articulation)
function AudioPreview.play_note(state, pitch, vel, chan, track, qn, opt_note)
    if state and state.audition_notes == false then return end
    if not pitch then return end

    -- Stop active note beforehand (with chaining so active CC override stays intact while playing new note)
    AudioPreview.stop_note(state, true)

    -- Determine target track
    local target_track = track or (opt_note and opt_note.track)
    if not target_track and state and state.focused_track then
        target_track = state.focused_track
    end
    if not target_track then
        target_track = reaper.GetSelectedTrack(0, 0)
    end

    if target_track then
        AudioPreview.prepare_track(target_track)
    end

    local p = math.max(0, math.min(127, math.floor(pitch)))
    local ch = (chan or (opt_note and opt_note.chan) or 0) & 0x0F
    local qn_pos = qn or (opt_note and opt_note.start_qn) or 0
    local opt_take = opt_note and opt_note.take

    -- Dynamics and volume calculation based on audition_volume slider:
    local pct = (state and state.audition_volume) or 50
    pct = math.max(0, math.min(100, pct))

    local dyn = AudioPreview.find_written_dynamic(state, target_track, qn_pos)
    local written_vel = (dyn and dyn.c1) or vel or (opt_note and opt_note.vel) or 96
    local written_c1  = (dyn and dyn.c1) or written_vel
    local written_c11 = (dyn and dyn.c2) or written_vel

    local final_vel, final_c1, final_c11
    if pct == 50 then
        final_vel = written_vel
        final_c1  = written_c1
        final_c11 = written_c11
    elseif pct > 50 then
        local t = (pct - 50.0) / 50.0
        final_vel = math.floor(written_vel + t * (127 - written_vel) + 0.5)
        final_c1  = math.floor(written_c1  + t * (127 - written_c1)  + 0.5)
        final_c11 = math.floor(written_c11 + t * (127 - written_c11) + 0.5)
    else
        local t = pct / 50.0
        final_vel = math.floor(1 + t * (written_vel - 1) + 0.5)
        final_c1  = math.floor(t * written_c1 + 0.5)
        final_c11 = math.floor(t * written_c11 + 0.5)
    end

    final_vel = math.max(1, math.min(127, final_vel))
    final_c1  = math.max(0, math.min(127, final_c1))
    final_c11 = math.max(0, math.min(127, final_c11))

    -- --------------------------------------------------------------------------
    -- Chase & determine which articulation must be played at this position (qn)
    -- --------------------------------------------------------------------------
    local target_art = nil
    local bank = nil
    if target_track and reaper.ValidatePtr(target_track, "MediaTrack*") then
        local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
        local all_banks = ReaticulateParser.get_all_banks(false, state)
        bank = ReaticulateParser.get_bank_for_track(target_track, all_banks)
        if bank and bank.articulations and #bank.articulations > 0 then
            target_art = AudioPreview.find_active_articulation_at_qn(state, target_track, qn_pos, ch, opt_note, bank)
        end
    end

    if target_art and target_art.pc and target_art.pc >= 0 then
        local eff_msb = (target_art.msb and target_art.msb >= 0) and target_art.msb or (bank and bank.msb and bank.msb >= 0 and bank.msb or -1)
        local eff_lsb = (target_art.lsb and target_art.lsb >= 0) and target_art.lsb or (bank and bank.lsb and bank.lsb >= 0 and bank.lsb or -1)
        if eff_msb >= 0 then
            reaper.StuffMIDIMessage(0, 0xB0 + ch, 0, eff_msb)
        end
        if eff_lsb >= 0 then
            reaper.StuffMIDIMessage(0, 0xB0 + ch, 32, eff_lsb)
        end
        reaper.StuffMIDIMessage(0, 0xC0 + ch, target_art.pc, 0)
        AudioPreview.current_art_pc = target_art.pc
    end

    -- Send configured CC controller(s) according to state.audition_cc
    local cc_mode = state and state.audition_cc or "11_1"
    if cc_mode == "none" or cc_mode == -1 or cc_mode == "-1" then
        -- Velocity Only: Do NOT send any CC! (Safe for Pianos, Keyboards, Drums & Synths)
        -- If an earlier CC override exists from a different mode, restore it now
        AudioPreview.restore_cc_override(state)
    elseif cc_mode == "11_1" or cc_mode == "11" then
        -- Dual mode: Send CC 1 (Modwheel) & CC 11 (Expression) in advance - Standard Default for Orchestral
        if not AudioPreview.active_cc_override or AudioPreview.active_cc_override.track ~= target_track or AudioPreview.active_cc_override.chan ~= ch then
            local orig_1  = AudioPreview.get_track_cc_at_qn(target_track, ch, 1, qn_pos, opt_take)
            local orig_11 = AudioPreview.get_track_cc_at_qn(target_track, ch, 11, qn_pos, opt_take)
            AudioPreview.active_cc_override = {
                track = target_track,
                chan = ch,
                items = {
                    { chan = ch, cc = 1, orig_val = orig_1 },
                    { chan = ch, cc = 11, orig_val = orig_11 }
                }
            }
        end
        reaper.StuffMIDIMessage(0, 0xB0 + ch, 1, final_c1)
        reaper.StuffMIDIMessage(0, 0xB0 + ch, 11, final_c11)
    else
        -- Single CC mode (e.g. CC 7, CC 1, CC 11 only, or any 0..127)
        local target_cc = tonumber(cc_mode) or 11
        target_cc = math.max(0, math.min(127, target_cc))
        if not AudioPreview.active_cc_override or AudioPreview.active_cc_override.track ~= target_track or AudioPreview.active_cc_override.chan ~= ch or AudioPreview.active_cc_override.cc ~= target_cc then
            local orig_val = AudioPreview.get_track_cc_at_qn(target_track, ch, target_cc, qn_pos, opt_take)
            AudioPreview.active_cc_override = {
                track = target_track,
                chan = ch,
                cc = target_cc,
                items = {
                    { chan = ch, cc = target_cc, orig_val = orig_val }
                }
            }
        end
        local val_to_send = (target_cc == 1) and final_c1 or final_c11
        reaper.StuffMIDIMessage(0, 0xB0 + ch, target_cc, val_to_send)
    end

    AudioPreview.last_audition_time = reaper.time_precise()

    -- Note On fired IMMEDIATELY in the same frame right after track arming & CC!
    -- This guarantees notes sound on the very first click with 0 latency and 0 dropped clicks!
    reaper.StuffMIDIMessage(0, 0x90 + ch, p, final_vel)
    local note_info = {
        pitch = p,
        chan = ch,
        vel = final_vel,
        track = target_track,
        start_time = reaper.time_precise(),
        released = false,
        bank = bank
    }
    AudioPreview.active_note = note_info
    if state then
        state.audition_active_note = note_info
    end
end

--- Signals that the mouse button was released
--- @param state table
function AudioPreview.on_mouse_released(state)
    if AudioPreview.active_note then
        AudioPreview.active_note.released = true
    end
    if state and state.audition_active_note then
        state.audition_active_note.released = true
    end
end

--- Stops all notes on all channels and restores all tracks
--- @param state table
function AudioPreview.stop_all(state)
    AudioPreview.stop_note(state)
    for ch = 0, 15 do
        reaper.StuffMIDIMessage(0, 0xB0 + ch, 123, 0) -- All Notes Off
    end
    AudioPreview.restore_all_tracks()
end

--- Per-frame update for timing and clean note release
--- @param state table
--- @param ctx ImGui_Context
function AudioPreview.update(state, ctx)
    local an = AudioPreview.active_note or (state and state.audition_active_note)
    if not an then return end

    local now = reaper.time_precise()
    local dur = now - an.start_time

    -- Safety timeout: automatically stop after at most 3.0 seconds
    if dur > 3.0 then
        AudioPreview.stop_note(state)
        return
    end

    -- Check if mouse button is held down
    local mouse_down = false
    if ctx then
        mouse_down = reaper.ImGui_IsMouseDown(ctx, 0) or reaper.ImGui_IsMouseDown(ctx, 1)
    end

    if not mouse_down then
        an.released = true
    end

    -- Generous audition duration: at least 0.65s (650ms) for short clicks so notes ring out musically
    if an.released and dur >= 0.65 then
        AudioPreview.stop_note(state)
    end
end

return AudioPreview

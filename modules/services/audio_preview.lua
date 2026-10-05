-- ==============================================================================
-- REAPER Native Notator - Service: AudioPreview (Note preview like in MIDI Editor)
-- Auditioning notes when clicking, moving, drawing & transposing via MIDI API
-- Supports intelligent articulation chasing & strict single-track isolation
-- ==============================================================================

local AudioPreview = {}

AudioPreview.active_note = nil
AudioPreview.pending_note = nil
AudioPreview.current_track = nil
AudioPreview.current_art_pc = nil
AudioPreview.last_audition_time = 0
AudioPreview.track_restore = {} -- [track_ptr] = { orig_arm = ..., orig_mon = ..., orig_inp = ..., changed_arm = bool, changed_mon = bool, changed_inp = bool }

--- Restores a modified track cleanly to its original settings
--- @param track MediaTrack
function AudioPreview.restore_track(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return end
    local r = AudioPreview.track_restore[track]
    if r then
        if r.changed_arm and r.orig_arm ~= nil then
            reaper.SetMediaTrackInfo_Value(track, "I_RECARM", r.orig_arm)
        end
        if r.changed_mon and r.orig_mon ~= nil then
            reaper.SetMediaTrackInfo_Value(track, "I_RECMON", r.orig_mon)
        end
        if r.changed_inp and r.orig_inp ~= nil then
            reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", r.orig_inp)
        end
        AudioPreview.track_restore[track] = nil
    end
    if AudioPreview.current_track == track then
        AudioPreview.current_track = nil
        AudioPreview.current_art_pc = nil
    end
end

--- Restores all temporarily modified tracks
function AudioPreview.restore_all_tracks()
    for trk, _ in pairs(AudioPreview.track_restore) do
        AudioPreview.restore_track(trk)
    end
    AudioPreview.current_track = nil
    AudioPreview.current_art_pc = nil
    AudioPreview.track_restore = {}
end

--- Prepares a track for MIDI monitoring (VKB input, arm & monitor) without flickering on each click
--- and temporarily disarms all other armed tracks in the project so only the target track plays.
--- @param track MediaTrack
--- @return boolean just_armed
function AudioPreview.prepare_track(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return false end

    -- If track changed: restore previous track to original state
    if AudioPreview.current_track and AudioPreview.current_track ~= track then
        AudioPreview.restore_track(AudioPreview.current_track)
    end

    -- Temporarily disarm any OTHER tracks currently armed in the project
    local num_trks = reaper.CountTracks(0)
    for ti = 0, num_trks - 1 do
        local tr = reaper.GetTrack(0, ti)
        if tr and tr ~= track then
            local is_armed = reaper.GetMediaTrackInfo_Value(tr, "I_RECARM")
            if is_armed == 1 then
                if not AudioPreview.track_restore[tr] then
                    AudioPreview.track_restore[tr] = {
                        track = tr,
                        orig_arm = 1,
                        orig_mon = reaper.GetMediaTrackInfo_Value(tr, "I_RECMON"),
                        orig_inp = reaper.GetMediaTrackInfo_Value(tr, "I_RECINPUT"),
                        changed_arm = true
                    }
                end
                reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 0)
            end
        end
    end

    local orig_arm = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
    local orig_mon = reaper.GetMediaTrackInfo_Value(track, "I_RECMON")
    local orig_inp = reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT")

    -- 6112 = Input: MIDI -> Virtual MIDI Keyboard -> All Channels (4096 | (63 << 5) | 0)
    -- 6080 = Input: MIDI -> All MIDI Inputs -> All Channels (4096 | (62 << 5) | 0)
    local is_vkb_ready = (orig_inp == 6112 or orig_inp == 6080)
    local needs_arm = (orig_arm == 0)
    local needs_mon = (orig_mon == 0)
    local needs_inp = not is_vkb_ready

    if needs_arm or needs_mon or needs_inp then
        if not AudioPreview.track_restore[track] then
            AudioPreview.track_restore[track] = {
                track = track,
                orig_arm = orig_arm,
                orig_mon = orig_mon,
                orig_inp = orig_inp,
                changed_arm = needs_arm,
                changed_mon = needs_mon,
                changed_inp = needs_inp
            }
        end

        if needs_inp then
            reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", 6112)
        end
        if needs_arm then
            reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
        end
        if needs_mon then
            reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
        end
    end

    reaper.SetOnlyTrackSelected(track)
    AudioPreview.current_track = track
    return needs_arm
end

--- Stops active note (sends Note Off via MIDI)
--- @param state table
function AudioPreview.stop_note(state)
    -- If there was a pending Note On waiting to fire, cancel it
    AudioPreview.pending_note = nil

    local an = AudioPreview.active_note or (state and state.audition_active_note)
    if an then
        local ch = (an.chan or 0) & 0x0F
        reaper.StuffMIDIMessage(0, 0x80 + ch, an.pitch, 0)
        AudioPreview.active_note = nil
        if state then state.audition_active_note = nil end
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

    -- Stop active note beforehand
    AudioPreview.stop_note(state)

    -- Determine target track
    local target_track = track or (opt_note and opt_note.track)
    if not target_track and state and state.focused_track then
        target_track = state.focused_track
    end
    if not target_track then
        target_track = reaper.GetSelectedTrack(0, 0)
    end

    local just_armed = false
    if target_track then
        just_armed = AudioPreview.prepare_track(target_track)
    end

    local p = math.max(0, math.min(127, math.floor(pitch)))
    local ch = (chan or (opt_note and opt_note.chan) or 0) & 0x0F
    local qn_pos = qn or (opt_note and opt_note.start_qn) or 0

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

    local art_changed = false
    if target_art and target_art.pc and target_art.pc >= 0 then
        if AudioPreview.current_art_pc ~= target_art.pc or AudioPreview.current_track ~= target_track then
            art_changed = true
        end

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

    -- Send CC1 (Modwheel) & CC11 (Expression) in advance for orchestral libraries
    reaper.StuffMIDIMessage(0, 0xB0 + ch, 1, final_c1)
    reaper.StuffMIDIMessage(0, 0xB0 + ch, 11, final_c11)

    AudioPreview.last_audition_time = reaper.time_precise()

    -- If articulation changed or track was just armed, allow 15ms (1 audio block / 1 frame) for the
    -- VST sampler (e.g. Kontakt / Spitfire SSO) to switch group before Note On arrives.
    -- This guarantees notes sound on the very first click with 0 double-clicks needed!
    if art_changed or just_armed then
        AudioPreview.pending_note = {
            pitch = p,
            chan = ch,
            vel = final_vel,
            track = target_track,
            time = reaper.time_precise(),
            bank = bank
        }
    else
        -- Already on this articulation: fire Note On immediately in the same frame!
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

--- Per-frame update for timing, pre-switched Note On firing, and clean note release
--- @param state table
--- @param ctx ImGui_Context
function AudioPreview.update(state, ctx)
    local now = reaper.time_precise()

    -- 1. Fire pending Note On once articulation has had 1 frame / >= 10ms to switch
    if AudioPreview.pending_note then
        local pn = AudioPreview.pending_note
        local elapsed = now - pn.time
        if elapsed >= 0.010 or pn.frame_passed then
            reaper.StuffMIDIMessage(0, 0x90 + pn.chan, pn.pitch, pn.vel)
            local note_info = {
                pitch = pn.pitch,
                chan = pn.chan,
                vel = pn.vel,
                track = pn.track,
                start_time = reaper.time_precise(),
                released = false,
                bank = pn.bank
            }
            AudioPreview.active_note = note_info
            if state then
                state.audition_active_note = note_info
            end
            AudioPreview.pending_note = nil
        else
            pn.frame_passed = true
        end
    end

    local an = AudioPreview.active_note or (state and state.audition_active_note)
    if not an then return end

    local dur = now - an.start_time

    -- Safety timeout: automatically stop after at most 2 seconds
    if dur > 2.0 then
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

    -- Shortest clicks sound for at least 350ms so instrument samples (attack/body) are audible
    if an.released and dur >= 0.35 then
        AudioPreview.stop_note(state)
    end
end

return AudioPreview

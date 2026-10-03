-- ==============================================================================
-- REAPER Native Notator - Service: AudioPreview (Note preview like in MIDI Editor)
-- Auditioning notes when clicking, moving, drawing & transposing via MIDI API
-- ==============================================================================

local AudioPreview = {}

AudioPreview.active_note = nil
AudioPreview.current_track = nil
AudioPreview.track_restore = {} -- [track_ptr] = { orig_arm = ..., orig_mon = ..., orig_inp = ..., changed_arm = bool, changed_mon = bool, changed_inp = bool }

--- Restores a modified track cleanly to its original settings
--- @param track MediaTrack
function AudioPreview.restore_track(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return end
    local r = AudioPreview.track_restore[track]
    if r then
        if r.changed_arm then
            reaper.SetMediaTrackInfo_Value(track, "I_RECARM", r.orig_arm)
        end
        if r.changed_mon then
            reaper.SetMediaTrackInfo_Value(track, "I_RECMON", r.orig_mon)
        end
        if r.changed_inp then
            reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", r.orig_inp)
        end
        AudioPreview.track_restore[track] = nil
    end
    if AudioPreview.current_track == track then
        AudioPreview.current_track = nil
    end
end

--- Restores all temporarily modified tracks
function AudioPreview.restore_all_tracks()
    for trk, _ in pairs(AudioPreview.track_restore) do
        AudioPreview.restore_track(trk)
    end
    AudioPreview.current_track = nil
    AudioPreview.track_restore = {}
end

--- Prepares a track for MIDI monitoring (VKB input, arm & monitor) without flickering on each click
--- @param track MediaTrack
function AudioPreview.prepare_track(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return end

    -- If track changed: restore previous track to original state
    if AudioPreview.current_track and AudioPreview.current_track ~= track then
        AudioPreview.restore_track(AudioPreview.current_track)
    end

    if AudioPreview.current_track ~= track then
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
            AudioPreview.track_restore[track] = {
                track = track,
                orig_arm = orig_arm,
                orig_mon = orig_mon,
                orig_inp = orig_inp,
                changed_arm = needs_arm,
                changed_mon = needs_mon,
                changed_inp = needs_inp
            }

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
    end
end

--- Stops active note (sends Note Off via MIDI)
--- @param state table
function AudioPreview.stop_note(state)
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

--- Plays a MIDI note (Note On)
--- @param state table Notator state object
--- @param pitch number MIDI pitch (0-127)
--- @param vel number Velocity (1-127, default: 96)
--- @param chan number MIDI channel (0-15, default: 0)
--- @param track MediaTrack Optional REAPER track pointer
--- @param qn number Optional position in QN (to detect dynamic markers)
function AudioPreview.play_note(state, pitch, vel, chan, track, qn)
    if state and state.audition_notes == false then return end
    if not pitch then return end

    -- Stop active note beforehand
    AudioPreview.stop_note(state)

    -- Determine target track
    local target_track = track
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
    local ch = (chan or 0) & 0x0F

    -- Dynamics and volume calculation based on audition_volume slider:
    -- 50% = Exactly what was written (dynamic marker or note velocity)
    -- 100% = 100% volume / max velocity 127 induced for the moment
    local pct = (state and state.audition_volume) or 50
    pct = math.max(0, math.min(100, pct))

    local dyn = AudioPreview.find_written_dynamic(state, target_track, qn)
    local written_vel = (dyn and dyn.c1) or vel or 96
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

    -- Send CC1 (Modwheel) & CC11 (Expression) in advance for orchestral libraries
    reaper.StuffMIDIMessage(0, 0xB0 + ch, 1, final_c1)
    reaper.StuffMIDIMessage(0, 0xB0 + ch, 11, final_c11)

    -- Note On via REAPER Virtual MIDI Keyboard Stream (Mode 0)
    reaper.StuffMIDIMessage(0, 0x90 + ch, p, final_vel)

    local note_info = {
        pitch = p,
        chan = ch,
        vel = final_vel,
        track = target_track,
        start_time = reaper.time_precise(),
        released = false
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

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
AudioPreview.last_activity_time = 0
AudioPreview.track_restore = {} -- [track_ptr] = { orig_inp = ..., switched_time = ... }
AudioPreview.active_cc_override = nil -- { track = ..., chan = ..., cc = ..., items = { { chan = ..., cc = ..., orig_val = ... } } }
AudioPreview._timer_running = false
AudioPreview._last_state = nil
AudioPreview.arm_click_note = nil

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
            local safe_val = item.orig_val
            if (item.cc == 1 or item.cc == 11 or item.cc == 7) and (not safe_val or safe_val <= 0) then
                safe_val = 100
            end
            reaper.StuffMIDIMessage(0, 0xB0 + item.chan, item.cc, safe_val)
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

--- Restores a modified track's input device and arm state cleanly to its original setting
--- @param track MediaTrack
function AudioPreview.restore_track(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return end
    if AudioPreview.active_cc_override and AudioPreview.active_cc_override.track == track then
        AudioPreview.restore_cc_override(nil, track)
    end

    -- If track has record disabled (I_RECMODE == 2) left over from earlier, restore to normal 0
    if reaper.GetMediaTrackInfo_Value(track, "I_RECMODE") == 2 then
        reaper.SetMediaTrackInfo_Value(track, "I_RECMODE", 0)
    end

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
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
        AudioPreview.track_restore[track] = nil
    end

    if AudioPreview.current_track == track then
        AudioPreview.current_track = nil
        AudioPreview.current_art_pc = nil
    end
end

--- Restores all temporarily modified tracks
function AudioPreview.restore_all_tracks()
    AudioPreview.restore_cc_override(nil)
    for trk, _ in pairs(AudioPreview.track_restore) do
        AudioPreview.restore_track(trk)
    end
    AudioPreview.current_track = nil
    AudioPreview.current_art_pc = nil
    AudioPreview.track_restore = {}
end

--- Returns true only if the track was genuinely record-armed by the user,
--- ignoring temporary I_RECARM changes made by AudioPreview for VKB auditioning.
--- @param track MediaTrack
--- @return boolean is_user_armed
function AudioPreview.is_track_user_armed(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return false end
    local r = AudioPreview.track_restore and AudioPreview.track_restore[track]
    if r and r.changed_arm then
        return (r.orig_arm == 1)
    end
    return (reaper.GetMediaTrackInfo_Value(track, "I_RECARM") == 1)
end

--- Prepares a track by temporarily switching its input device to Virtual MIDI Keyboard (6080)
--- and arming the track for monitoring during the initial 50ms window.
--- @param track MediaTrack
--- @return boolean just_switched Returns true if input or arm was switched (requiring >=50ms delay)
function AudioPreview.prepare_track(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return false end

    -- If we switched to a different track, restore the previous track
    if AudioPreview.current_track and AudioPreview.current_track ~= track then
        AudioPreview.restore_track(AudioPreview.current_track)
    end

    -- Disarm any OTHER tracks in the project so they do NOT receive Virtual MIDI Keyboard broadcast!
    local proj_track_count = reaper.CountTracks(0)
    for ti = 0, proj_track_count - 1 do
        local other_track = reaper.GetTrack(0, ti)
        if other_track and other_track ~= track and reaper.ValidatePtr(other_track, "MediaTrack*") then
            local other_arm = reaper.GetMediaTrackInfo_Value(other_track, "I_RECARM")
            if other_arm == 1 then
                if not AudioPreview.track_restore[other_track] then
                    AudioPreview.track_restore[other_track] = {
                        track = other_track,
                        orig_arm = 1,
                        changed_arm = true,
                        switched_time = reaper.time_precise()
                    }
                end
                reaper.SetMediaTrackInfo_Value(other_track, "I_RECARM", 0)
            end
        end
    end

    -- If track has record disabled (I_RECMODE == 2) left over from earlier, restore to normal 0
    if reaper.GetMediaTrackInfo_Value(track, "I_RECMODE") == 2 then
        reaper.SetMediaTrackInfo_Value(track, "I_RECMODE", 0)
    end

    local orig_inp = reaper.GetMediaTrackInfo_Value(track, "I_RECINPUT")
    local orig_arm = reaper.GetMediaTrackInfo_Value(track, "I_RECARM")
    local orig_mon = reaper.GetMediaTrackInfo_Value(track, "I_RECMON")
    local VKB_INPUT = 6080 -- Virtual MIDI Keyboard (All Channels: 4096 | (62 << 5) | 0)

    local needs_inp = (orig_inp ~= VKB_INPUT)
    local needs_arm = (orig_arm == 0)
    local needs_mon = (orig_mon == 0)

    local just_switched = false
    if needs_inp or needs_arm or needs_mon then
        if not AudioPreview.track_restore[track] then
            AudioPreview.track_restore[track] = {
                track = track,
                orig_inp = orig_inp,
                orig_arm = orig_arm,
                orig_mon = orig_mon,
                changed_inp = needs_inp,
                changed_arm = needs_arm,
                changed_mon = needs_mon,
                switched_time = reaper.time_precise()
            }
        end
        if needs_inp then
            reaper.SetMediaTrackInfo_Value(track, "I_RECINPUT", VKB_INPUT)
        end
        if needs_mon then
            reaper.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
        end
        if needs_arm then
            reaper.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
        end
        reaper.TrackList_AdjustWindows(false)
        reaper.UpdateArrange()
        just_switched = true
    end

    AudioPreview.current_track = track
    AudioPreview.last_activity_time = reaper.time_precise()
    return just_switched
end

--- Stops active note (sends Note Off via MIDI) and restores temporary CC overrides
--- @param state table
--- @param is_chaining boolean|nil If true, another note is playing immediately so CC override stays active
function AudioPreview.stop_note(state, is_chaining)
    if type(state) ~= "table" then
        state = AudioPreview._last_state
    end
    local an = AudioPreview.active_note or (state and state.audition_active_note)
    if an then
        local ch = (an.chan or 0) & 0x0F
        reaper.StuffMIDIMessage(0, 0x80 + ch, an.pitch, 0)
        if an.extra_pitches then
            for _, ep in ipairs(an.extra_pitches) do
                reaper.StuffMIDIMessage(0, 0x80 + ch, ep, 0)
            end
        end
        AudioPreview.active_note = nil
        if state then state.audition_active_note = nil end
    end

    AudioPreview.last_activity_time = reaper.time_precise()

    if not is_chaining then
        AudioPreview.restore_cc_override(state)
    end
end

--- Finds closest written dynamic marker (before or at note)
--- @param state table
--- @param track MediaTrack
--- @param qn number
function AudioPreview.find_written_dynamic(state, track, qn)
    if type(state) ~= "table" or not track or not qn then return nil end
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
--- Finds the active articulation for a track at a specific QN position
--- (scans for note-level articulation on the note, or preceding persistent articulation on the track)
--- @param state table Notator state
--- @param track MediaTrack
--- @param qn number
--- @param chan number
--- @param opt_note table|nil
--- @param bank table
--- @return table|nil target_art
function AudioPreview.find_active_articulation_at_qn(state, track, qn, chan, opt_note, bank)
    if not bank or not bank.articulations or #bank.articulations == 0 then
        return nil
    end

    local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
    local qn_pos = qn or (opt_note and opt_note.start_qn) or 0
    local target_chan = (chan or (opt_note and opt_note.chan) or 0) & 0x0F
    local opt_pitch = opt_note and opt_note.pitch

    -- 1. Identify bank's default base articulation (Long / Sustain, never Legato)
    local default_base_art = MidiService.get_default_base_articulation(bank)

    -- Helper: resolve take covering qn_pos on track
    local function resolve_take_at_qn()
        local take = opt_note and opt_note.take
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
            return take
        end
        if track and reaper.ValidatePtr(track, "MediaTrack*") then
            local item_cnt = reaper.CountTrackMediaItems(track)
            local fallback_take = nil
            for ii = 0, item_cnt - 1 do
                local item = reaper.GetTrackMediaItem(track, ii)
                if item then
                    local tk = reaper.GetActiveTake(item)
                    if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") and reaper.TakeIsMIDI(tk) then
                        if not fallback_take then fallback_take = tk end
                        local ipos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        local ilen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                        local i_sqn = reaper.TimeMap2_timeToQN(0, ipos)
                        local i_eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                        if qn_pos >= i_sqn - 0.05 and qn_pos <= i_eqn + 0.05 then
                            return tk
                        end
                    end
                end
            end
            return fallback_take
        end
        return nil
    end

    local active_take = resolve_take_at_qn()

    -- 2. PRIORITY 1: Check if note is inside an active Slur phrase -> return track's configured Slur articulation (Auto: Legato -> Long)
    local is_under_slur = false
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        local trk_guid = reaper.GetTrackGUID(track)
        local norm_trk_guid = trk_guid and trk_guid:gsub("[{}%-]", ""):upper() or ""
        if state and state.user_slurs then
            for _, sl in ipairs(state.user_slurs) do
                local sl_guid = (sl.track_guid or ""):gsub("[{}%-]", ""):upper()
                if (sl_guid == "" or sl_guid == norm_trk_guid) and (sl.chan or 0) == target_chan then
                    local s_qn = sl.start_qn or 0
                    local e_qn = sl.n2_start_qn or sl.end_qn or s_qn
                    if qn_pos >= s_qn - 0.05 and qn_pos <= e_qn + 0.05 then
                        is_under_slur = true
                        break
                    end
                end
            end
        end
        if not is_under_slur and active_take then
            local _, _, _, tcnt = reaper.MIDI_CountEvts(active_take)
            for ti = 0, tcnt - 1 do
                local ok_t, _, _, _, etype, msg = reaper.MIDI_GetTextSysexEvt(active_take, ti)
                if ok_t and etype == 15 and msg and msg:find("^NOTATOR_SLUR") then
                    local _, s_ch, _, _, sqn, n2sqn = msg:match("^NOTATOR_SLUR%s+([%w_]+)%s+(%d+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)")
                    if s_ch and (tonumber(s_ch) or 0) == target_chan then
                        local s_qn = tonumber(sqn) or 0
                        local e_qn = tonumber(n2sqn) or s_qn
                        if qn_pos >= s_qn - 0.05 and qn_pos <= e_qn + 0.05 then
                            is_under_slur = true
                            break
                        end
                    end
                end
            end
        end
    end
    if is_under_slur then
        local slur_art = MidiService.find_slur_articulation_in_bank(bank, track, state)
        if slur_art then return slur_art end
    end

    -- 3. PRIORITY 2: Check articulation ON THE NOTE ("auf der Note")
    local note_art_id = opt_note and opt_note.articulation
    if (not note_art_id or note_art_id == "" or note_art_id == "none") and opt_note and opt_note.art then
        note_art_id = opt_note.art
    end

    -- 3a. If not directly on opt_note, search active_tracks_cache for note at qn_pos matching pitch & channel
    if (not note_art_id or note_art_id == "" or note_art_id == "none") and state and state.active_tracks_cache then
        for _, tdata in ipairs(state.active_tracks_cache) do
            if tdata.track == track and tdata.notes then
                for _, n in ipairs(tdata.notes) do
                    if (n.chan or 0) == target_chan and math.abs(n.start_qn - qn_pos) <= 0.05 then
                        if not opt_pitch or n.pitch == opt_pitch then
                            if n.articulation and n.articulation ~= "" and n.articulation ~= "none" then
                                note_art_id = n.articulation
                                break
                            end
                        end
                    end
                end
                if note_art_id and note_art_id ~= "" and note_art_id ~= "none" then break end
            end
        end
    end

    -- 3b. Also check Type 15 NOTE tag directly in MIDI take at this note's position
    if (not note_art_id or note_art_id == "" or note_art_id == "none") and active_take then
        local note_ppq = reaper.MIDI_GetPPQPosFromProjQN(active_take, qn_pos)
        local _, _, _, tcnt = reaper.MIDI_CountEvts(active_take)
        for ti = 0, tcnt - 1 do
            local ok_t, _, _, ppq_t, etype, msg = reaper.MIDI_GetTextSysexEvt(active_take, ti)
            if ok_t and etype == 15 and math.abs(ppq_t - note_ppq) <= 25 then
                local p_str, ch_str, art_str = msg:match("^NOTE%s+(%d+)%s+(%d+)%s+a%s+([%a%d_]+)")
                if p_str and art_str and (tonumber(ch_str) or 0) == target_chan then
                    if not opt_pitch or tonumber(p_str) == opt_pitch then
                        note_art_id = art_str
                        break
                    end
                end
            end
        end
    end

    -- 3c. If note_art_id found on the note, resolve it in bank
    if note_art_id and note_art_id ~= "" and note_art_id ~= "none" then
        if note_art_id:lower() == "legato" then
            local slur_art = MidiService.find_slur_articulation_in_bank(bank, track, state)
            if slur_art then return slur_art end
        end
        local match = MidiService.find_reaticulate_art_for_id(bank, note_art_id)
        if match then
            return match
        end
        for _, ba in ipairs(bank.articulations) do
            if ba.name and ba.name:lower() == note_art_id:lower() then
                return ba
            end
        end
    end

    -- 4. PRIORITY 3: Check Program Change AT or BEFORE the note ("davor") across both cache and raw MIDI take!
    -- Momentary articulations (Staccato / Short / Spiccato) on earlier notes NEVER persist onto a subsequent note without a dot!
    local persistent_art = nil
    local latest_qn = -100000

    local function is_bank_art_momentary(ba)
        if not ba then return false end
        if MidiService.is_momentary_articulation and MidiService.is_momentary_articulation(ba.name) then
            return true
        end
        local mapped = MidiService.art_id_from_reaticulate_art and MidiService.art_id_from_reaticulate_art(ba)
        if mapped and MidiService.is_momentary_articulation and MidiService.is_momentary_articulation(mapped) then
            return true
        end
        return false
    end

    -- 4a. Search tdata.articulations in cache
    if state and state.active_tracks_cache then
        for _, tdata in ipairs(state.active_tracks_cache) do
            if tdata.track == track and tdata.articulations then
                for _, art in ipairs(tdata.articulations) do
                    local ch_ok = ((art.chan or 0) == target_chan) or (art.chan == nil)
                    if ch_ok and art.qn <= (qn_pos + 0.05) then
                        local is_at_note = math.abs(art.qn - qn_pos) <= 0.05
                        if art.qn >= latest_qn then
                            for _, ba in ipairs(bank.articulations) do
                                if ba.pc == art.pc then
                                    local is_mom = is_bank_art_momentary(ba)
                                    -- Only accept a momentary PC if it is AT this exact position AND note_obj wasn't explicitly un-marked
                                    if not is_mom or (is_at_note and not note_obj and not art.is_auto_return) then
                                        latest_qn = art.qn
                                        persistent_art = ba
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
                break
            end
        end
    end

    -- 4b. ALWAYS also scan the MIDI take directly for 0xC0 Program Changes at or before qn_pos
    -- (Ensures standalone PCs like Legato / Trill at bar 1 beat 1 are found, while skipping earlier momentary Staccato PCs)
    if active_take then
        local note_ppq = reaper.MIDI_GetPPQPosFromProjQN(active_take, qn_pos)
        local target_ppq = note_ppq + 25
        local _, _, cc_cnt = reaper.MIDI_CountEvts(active_take)
        local best_take_ppq = -100000
        local best_take_ba = nil
        local fallback_any_chan_ppq = -100000
        local fallback_any_chan_ba = nil

        for ci = 0, cc_cnt - 1 do
            local ok, _, _, ppq, chanmsg, cchan, msg2 = reaper.MIDI_GetCC(active_take, ci)
            if ok and (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0) and ppq <= target_ppq then
                local matched_ba = nil
                for _, ba in ipairs(bank.articulations) do
                    if ba.pc == msg2 then
                        matched_ba = ba
                        break
                    end
                end
                if matched_ba then
                    local is_mom = is_bank_art_momentary(matched_ba)
                    local is_at_note = math.abs(ppq - note_ppq) <= 25
                    if not is_mom or (is_at_note and not note_obj) then
                        if cchan == target_chan and ppq >= best_take_ppq then
                            best_take_ppq = ppq
                            best_take_ba = matched_ba
                        end
                        if ppq >= fallback_any_chan_ppq then
                            fallback_any_chan_ppq = ppq
                            fallback_any_chan_ba = matched_ba
                        end
                    end
                end
            end
        end

        local chosen_ppq = (best_take_ba ~= nil) and best_take_ppq or fallback_any_chan_ppq
        local chosen_ba  = (best_take_ba ~= nil) and best_take_ba  or fallback_any_chan_ba
        if chosen_ba ~= nil then
            local chosen_qn = reaper.MIDI_GetProjQNFromPPQPos(active_take, chosen_ppq)
            if chosen_qn >= latest_qn - 0.01 then
                persistent_art = chosen_ba
                latest_qn = chosen_qn
            end
        end
    end

    if persistent_art then
        return persistent_art
    end

    -- 5. Fallback: bank's default base articulation (Long / Sustain)
    return default_base_art
end

--- Prepares track (VKB + arming + CC/Bank) on Mouse Down when user clicks a note
--- @param state table
--- @param pitch number
--- @param vel number
--- @param chan number
--- @param track MediaTrack
--- @param qn number
--- @param opt_note table
function AudioPreview.prepare_for_note_click(state, pitch, vel, chan, track, qn, opt_note)
    if state and state.audition_notes == false then return end

    local target_track = track or (opt_note and opt_note.track) or (state and state.focused_track) or reaper.GetSelectedTrack(0, 0)
    if not target_track or not reaper.ValidatePtr(target_track, "MediaTrack*") then
        local trk_cnt = reaper.CountTracks(0)
        if trk_cnt > 0 then target_track = reaper.GetTrack(0, 0) end
    end
    if not target_track then return end

    -- Record activity timestamp immediately so idle restore_all_tracks() never disarms the track mid-click
    AudioPreview.last_activity_time = reaper.time_precise()
    AudioPreview.last_audition_time = AudioPreview.last_activity_time

    -- 1. Switch to Virtual MIDI Keyboard (6080) and arm track immediately on Mouse Down
    local just_switched = AudioPreview.prepare_track(target_track)

    local p = math.max(0, math.min(127, math.floor(pitch or 60)))
    local ch = (chan or (opt_note and opt_note.chan) or 0) & 0x0F
    local qn_pos = qn or (opt_note and opt_note.start_qn) or 0
    local opt_take = opt_note and opt_note.take

    -- 2. Dynamics & CC
    local pct = (state and state.audition_volume) or 50
    pct = math.max(0, math.min(100, pct))

    local dyn = AudioPreview.find_written_dynamic(state, target_track, qn_pos)
    local written_vel = (dyn and dyn.c1) or vel or (opt_note and opt_note.vel) or 96
    local written_c1  = (dyn and dyn.c1) or written_vel
    local written_c11 = (dyn and (dyn.c11 or dyn.c2)) or written_vel

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

    -- 3. Resolve Reaticulate bank and active articulation at qn_pos
    local target_art = nil
    local bank = nil
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser.get_all_banks(false, state)
    bank = ReaticulateParser.get_bank_for_track(target_track, all_banks, state)
    if bank and bank.articulations and #bank.articulations > 0 then
        ReaticulateParser.ensure_track_reaticulate_fx_and_bank(target_track, bank, state, false)
        target_art = AudioPreview.find_active_articulation_at_qn(state, target_track, qn_pos, ch, opt_note, bank)
    end

    local eff_msb = -1
    local eff_lsb = -1
    if target_art and target_art.pc and target_art.pc >= 0 then
        eff_msb = (target_art.msb and target_art.msb >= 0) and target_art.msb or (bank and bank.msb and bank.msb >= 0 and bank.msb or -1)
        eff_lsb = (target_art.lsb and target_art.lsb >= 0) and target_art.lsb or (bank and bank.lsb and bank.lsb >= 0 and bank.lsb or -1)
        if not just_switched then
            if eff_msb >= 0 then reaper.StuffMIDIMessage(0, 0xB0 + ch, 0, eff_msb) end
            if eff_lsb >= 0 then reaper.StuffMIDIMessage(0, 0xB0 + ch, 32, eff_lsb) end
            reaper.StuffMIDIMessage(0, 0xC0 + ch, target_art.pc, 0)
            AudioPreview.current_art_pc = target_art.pc
        end
    end

    local cc_mode = state and state.audition_cc or "11_1"
    if cc_mode == "none" or cc_mode == -1 or cc_mode == "-1" then
        reaper.StuffMIDIMessage(0, 0xB0 + ch, 1, math.max(final_c1, 100))
        reaper.StuffMIDIMessage(0, 0xB0 + ch, 11, math.max(final_c11, 100))
    elseif cc_mode == "11_1" or cc_mode == "11" then
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
        local target_cc = tonumber(cc_mode) or 11
        local val_to_send = (target_cc == 1) and final_c1 or final_c11
        reaper.StuffMIDIMessage(0, 0xB0 + ch, target_cc, val_to_send)
        if target_cc == 1 then
            reaper.StuffMIDIMessage(0, 0xB0 + ch, 11, math.max(final_c11, 100))
        elseif target_cc == 11 then
            reaper.StuffMIDIMessage(0, 0xB0 + ch, 1, math.max(final_c1, 100))
        end
    end

    -- Store note data for mouse release trigger
    AudioPreview.arm_click_note = {
        pitch = p,
        vel = final_vel,
        final_c1 = final_c1,
        final_c11 = final_c11,
        chan = ch,
        track = target_track,
        qn = qn_pos,
        note = opt_note,
        bank = bank,
        target_art = target_art,
        eff_msb = eff_msb,
        eff_lsb = eff_lsb,
        just_armed = just_switched,
        click_time = reaper.time_precise()
    }
end

--- Plays the prepared note on Mouse Release (clean two-stage PC -> Note On trigger)
--- @param state table
function AudioPreview.play_note_on_release(state)
    local ac = AudioPreview.arm_click_note
    if not ac then return end
    AudioPreview.arm_click_note = nil

    if state and state.audition_notes == false then return end

    -- Stop any active sounding note beforehand
    AudioPreview.stop_note(state, true)

    local target_track = ac.track
    if not target_track or not reaper.ValidatePtr(target_track, "MediaTrack*") then return end

    local ch = ac.chan & 0x0F
    local now = reaper.time_precise()
    AudioPreview.last_activity_time = now

    -- If track was freshly armed on this click, run two-stage release:
    -- Stage 1 (after VKB input settles): Send Bank Select + Program Change + CCs
    -- Stage 2 (45 ms after Stage 1): Send Note On so Reaticulate & VSTi keyswitch finish before Note On arrives!
    if ac.just_armed then
        AudioPreview.pending_release_note = {
            pitch = ac.pitch,
            vel = ac.vel,
            final_c1 = ac.final_c1,
            final_c11 = ac.final_c11,
            chan = ch,
            track = target_track,
            target_art = ac.target_art,
            eff_msb = ac.eff_msb,
            eff_lsb = ac.eff_lsb,
            bank = ac.bank,
            release_time = now,
            stage = 1,
            delay = 0.080
        }
        AudioPreview.start_sequence_loop(state)
        return
    end

    -- Track was already armed on VKB:
    -- Bank MSB/LSB and Program Change were already sent on Mouse Down (prepare_for_note_click).
    -- Ensure at least 45ms have elapsed since the PC was sent before triggering Note On (0x90) so Reaticulate's keyswitch is never racing Note On in the same audio block!
    local held_ms = now - (ac.click_time or now)
    if held_ms < 0.045 then
        AudioPreview.pending_release_note = {
            pitch = ac.pitch,
            vel = ac.vel,
            final_c1 = ac.final_c1,
            final_c11 = ac.final_c11,
            chan = ch,
            track = target_track,
            target_art = ac.target_art,
            eff_msb = ac.eff_msb,
            eff_lsb = ac.eff_lsb,
            bank = ac.bank,
            release_time = now,
            stage = 2,
            stage2_time = now,
            stage2_delay = math.max(0.015, 0.045 - held_ms)
        }
        AudioPreview.start_sequence_loop(state)
        return
    end

    -- 2. Trigger the note: Note On (PC already settled during mouse press)
    reaper.StuffMIDIMessage(0, 0x90 + ch, ac.pitch, ac.vel)

    local is_momentary = false
    if ac.target_art and ac.target_art.name then
        local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
        is_momentary = MidiService.is_momentary_articulation(ac.target_art.name)
    end

    local note_info = {
        pitch = ac.pitch,
        chan = ch,
        vel = ac.vel,
        track = target_track,
        start_time = now,
        released = true, -- Triggered note: releases promptly via trigger pulse!
        is_momentary = is_momentary,
        bank = ac.bank
    }
    AudioPreview.active_note = note_info
    if state then
        state.audition_active_note = note_info
    end
    AudioPreview.last_activity_time = now

    -- Run autonomous loop for clean note trigger and 2s idle restore
    AudioPreview.start_sequence_loop(state)
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
    if type(state) == "userdata" then
        track = state
        state = AudioPreview._last_state
    elseif type(state) ~= "table" then
        state = AudioPreview._last_state
    end
    if state and state.audition_notes == false then return end
    if not pitch then return end

    local extra_pitches = nil
    if type(pitch) == "table" then
        if #pitch == 0 then return end
        if #pitch > 1 then
            extra_pitches = {}
            for i = 2, #pitch do
                local ep = tonumber(pitch[i])
                if ep then
                    table.insert(extra_pitches, math.max(0, math.min(127, math.floor(ep))))
                end
            end
        end
        pitch = tonumber(pitch[1])
        if not pitch then return end
    end

    -- Stop active note beforehand (with chaining so active CC override stays intact while playing new note)
    AudioPreview.stop_note(state, true)

    -- Determine target track
    local target_track = (type(track) == "userdata" and track) or (opt_note and opt_note.track)
    if not target_track and state and state.focused_track then
        target_track = state.focused_track
    end
    if not target_track then
        target_track = reaper.GetSelectedTrack(0, 0)
    end

    local just_switched = false
    if target_track then
        just_switched = AudioPreview.prepare_track(target_track)
    end

    local p = math.max(0, math.min(127, math.floor(pitch)))
    local ch = (chan or (opt_note and opt_note.chan) or 0) & 0x0F
    local qn_pos = (type(qn) == "number" and qn) or (opt_note and opt_note.start_qn) or 0
    local opt_take = opt_note and opt_note.take

    -- Dynamics and volume calculation based on audition_volume slider:
    local pct = (state and state.audition_volume) or 50
    pct = math.max(0, math.min(100, pct))

    local dyn = AudioPreview.find_written_dynamic(state, target_track, qn_pos)
    local written_vel = (dyn and dyn.c1) or vel or (opt_note and opt_note.vel) or 96
    local written_c1  = (dyn and dyn.c1) or written_vel
    local written_c11 = (dyn and (dyn.c11 or dyn.c2)) or written_vel

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
        bank = ReaticulateParser.get_bank_for_track(target_track, all_banks, state)
        if bank and bank.articulations and #bank.articulations > 0 then
            ReaticulateParser.ensure_track_reaticulate_fx_and_bank(target_track, bank, state, false)
            target_art = AudioPreview.find_active_articulation_at_qn(state, target_track, qn_pos, ch, opt_note, bank)
        end
    end

    local eff_msb = -1
    local eff_lsb = -1
    if target_art and target_art.pc and target_art.pc >= 0 then
        eff_msb = (target_art.msb and target_art.msb >= 0) and target_art.msb or (bank and bank.msb and bank.msb >= 0 and bank.msb or -1)
        eff_lsb = (target_art.lsb and target_art.lsb >= 0) and target_art.lsb or (bank and bank.lsb and bank.lsb >= 0 and bank.lsb or -1)
    end

    -- Build list of CC messages to send according to audition_cc mode:
    local cc_list = {}
    local cc_mode = state and state.audition_cc or "11_1"
    if cc_mode == "none" or cc_mode == -1 or cc_mode == "-1" then
        -- Velocity Only: Keep CC1 and CC11 at safe audible volume (100) so orchestral engines don't mute
        table.insert(cc_list, { cc = 1, val = math.max(final_c1, 100) })
        table.insert(cc_list, { cc = 11, val = math.max(final_c11, 100) })
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
        table.insert(cc_list, { cc = 1, val = final_c1 })
        table.insert(cc_list, { cc = 11, val = final_c11 })
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
        table.insert(cc_list, { cc = target_cc, val = val_to_send })
        -- Keep counterpart at audible level for dual-controller orchestral engines
        if target_cc == 1 then
            table.insert(cc_list, { cc = 11, val = math.max(final_c11, 100) })
        elseif target_cc == 11 then
            table.insert(cc_list, { cc = 1, val = math.max(final_c1, 100) })
        end
    end

    local now = reaper.time_precise()
    AudioPreview.last_audition_time = now
    AudioPreview.last_activity_time = now

    if just_switched then
        -- Timing: Wait 50 ms for Virtual MIDI Keyboard & arming to settle, then another 50 ms before Note On
        AudioPreview.pending_note = {
            pitch = p,
            extra_pitches = extra_pitches,
            chan = ch,
            vel = final_vel,
            track = target_track,
            target_art = target_art,
            eff_msb = eff_msb,
            eff_lsb = eff_lsb,
            cc_list = cc_list,
            switch_time = now,
            bank = bank,
            stage = 1
        }
        AudioPreview.start_sequence_loop(state)
    else
        -- Already on Virtual MIDI Keyboard: send Bank/PC and CCs immediately
        local pc_changed = false
        if target_art and target_art.pc and target_art.pc >= 0 then
            if AudioPreview.current_art_pc ~= target_art.pc then
                pc_changed = true
            end
            if eff_msb >= 0 then
                reaper.StuffMIDIMessage(0, 0xB0 + ch, 0, eff_msb)
            end
            if eff_lsb >= 0 then
                reaper.StuffMIDIMessage(0, 0xB0 + ch, 32, eff_lsb)
            end
            reaper.StuffMIDIMessage(0, 0xC0 + ch, target_art.pc, 0)
            AudioPreview.current_art_pc = target_art.pc
        end

        for _, cmsg in ipairs(cc_list) do
            reaper.StuffMIDIMessage(0, 0xB0 + ch, cmsg.cc, cmsg.val)
        end

        if pc_changed then
            -- Wait 40 ms after Program Change so Reaticulate & VSTi keyswitch complete before Note On arrives
            AudioPreview.pending_note = {
                pitch = p,
                extra_pitches = extra_pitches,
                chan = ch,
                vel = final_vel,
                track = target_track,
                target_art = target_art,
                eff_msb = eff_msb,
                eff_lsb = eff_lsb,
                cc_list = cc_list,
                switch_time = now,
                stage2_time = now,
                bank = bank,
                stage = 2
            }
            AudioPreview.start_sequence_loop(state)
            return
        end

        local is_momentary = false
        if target_art and target_art.name then
            local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
            is_momentary = MidiService.is_momentary_articulation(target_art.name)
        end

        reaper.StuffMIDIMessage(0, 0x90 + ch, p, final_vel)
        if extra_pitches then
            for _, ep in ipairs(extra_pitches) do
                reaper.StuffMIDIMessage(0, 0x90 + ch, ep, final_vel)
            end
        end
        local note_info = {
            pitch = p,
            extra_pitches = extra_pitches,
            chan = ch,
            vel = final_vel,
            track = target_track,
            start_time = now,
            released = false,
            is_momentary = is_momentary,
            bank = bank
        }
        AudioPreview.active_note = note_info
        if state then
            state.audition_active_note = note_info
        end
        AudioPreview.start_sequence_loop(state)
    end
end

--- Starts the autonomous background sequence loop (via reaper.defer)
--- to ensure the full sequence (Arm/VKB -> 50ms -> CC -> 50ms -> Note -> Trigger -> 2s unarmed)
--- runs continuously and sequentially from ONE single click without requiring any second click.
--- @param state table
function AudioPreview.start_sequence_loop(state)
    if type(state) == "table" then
        AudioPreview._last_state = state
    end
    if AudioPreview._timer_running then return end
    AudioPreview._timer_running = true

    local function preview_step()
        AudioPreview.update(AudioPreview._last_state, nil)
        if AudioPreview.pending_note or AudioPreview.pending_release_note or AudioPreview.active_note or AudioPreview.arm_click_note or next(AudioPreview.track_restore) ~= nil then
            reaper.defer(preview_step)
        else
            AudioPreview._timer_running = false
        end
    end
    reaper.defer(preview_step)
end

--- Signals that the mouse button was released
--- @param state table
function AudioPreview.on_mouse_released(state)
    if type(state) ~= "table" then
        state = AudioPreview._last_state
    end
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
    if type(state) ~= "table" then
        state = AudioPreview._last_state
    end
    AudioPreview.pending_note = nil
    AudioPreview.pending_release_note = nil
    AudioPreview.arm_click_note = nil
    AudioPreview.stop_note(state)
    for ch = 0, 15 do
        reaper.StuffMIDIMessage(0, 0xB0 + ch, 123, 0) -- All Notes Off
    end
    AudioPreview.restore_all_tracks()
    AudioPreview._timer_running = false
end

--- Per-frame update for timing, pre-switching delay (50ms + 50ms), prompt note trigger release and 2-second restore delay
--- @param state table
--- @param ctx ImGui_Context
function AudioPreview.update(state, ctx)
    if type(state) == "table" then AudioPreview._last_state = state else state = AudioPreview._last_state end
    local now = reaper.time_precise()

    -- 1. Check pending note (Two-stage delay: 50ms arming/VKB stage + additional 45ms settling stage before note)
    if AudioPreview.pending_note then
        local pn = AudioPreview.pending_note
        local elapsed = now - pn.switch_time

        -- Stage 1: At 50ms, track is armed and VKB is active -> send Bank/PC and CC messages
        if pn.stage == 1 and elapsed >= 0.050 then
            local ch = pn.chan
            if pn.target_art and pn.target_art.pc and pn.target_art.pc >= 0 then
                if pn.eff_msb and pn.eff_msb >= 0 then
                    reaper.StuffMIDIMessage(0, 0xB0 + ch, 0, pn.eff_msb)
                end
                if pn.eff_lsb and pn.eff_lsb >= 0 then
                    reaper.StuffMIDIMessage(0, 0xB0 + ch, 32, pn.eff_lsb)
                end
                reaper.StuffMIDIMessage(0, 0xC0 + ch, pn.target_art.pc, 0)
                AudioPreview.current_art_pc = pn.target_art.pc
            end

            if pn.cc_list then
                for _, cmsg in ipairs(pn.cc_list) do
                    reaper.StuffMIDIMessage(0, 0xB0 + ch, cmsg.cc, cmsg.val)
                end
            end

            pn.stage = 2
            pn.stage2_time = now
        end

        -- Stage 2: Wait 45ms after Program Change so Reaticulate & VSTi keyswitch complete before triggering Note On
        if pn.stage == 2 and (now - (pn.stage2_time or pn.switch_time) >= 0.045) then
            local ch = pn.chan
            local is_momentary = false
            if pn.target_art and pn.target_art.name then
                local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
                is_momentary = MidiService.is_momentary_articulation(pn.target_art.name)
            end

            reaper.StuffMIDIMessage(0, 0x90 + ch, pn.pitch, pn.vel)
            if pn.extra_pitches then
                for _, ep in ipairs(pn.extra_pitches) do
                    reaper.StuffMIDIMessage(0, 0x90 + ch, ep, pn.vel)
                end
            end
            local note_info = {
                pitch = pn.pitch,
                extra_pitches = pn.extra_pitches,
                chan = ch,
                vel = pn.vel,
                track = pn.track,
                start_time = now,
                released = false,
                is_momentary = is_momentary,
                bank = pn.bank
            }
            AudioPreview.active_note = note_info
            if state then
                state.audition_active_note = note_info
            end
            AudioPreview.pending_note = nil
            AudioPreview.last_activity_time = now
        end
    end

    -- 1b. Check pending release note (two-stage: Stage 1 sends Bank/PC after VKB settles, Stage 2 sends Note On 45ms later)
    if AudioPreview.pending_release_note then
        local prn = AudioPreview.pending_release_note
        local ch = prn.chan & 0x0F
        if (prn.stage or 1) == 1 and (now - prn.release_time) >= (prn.delay or 0.080) then
            if prn.target_art and prn.target_art.pc and prn.target_art.pc >= 0 then
                if prn.eff_msb and prn.eff_msb >= 0 then reaper.StuffMIDIMessage(0, 0xB0 + ch, 0, prn.eff_msb) end
                if prn.eff_lsb and prn.eff_lsb >= 0 then reaper.StuffMIDIMessage(0, 0xB0 + ch, 32, prn.eff_lsb) end
                reaper.StuffMIDIMessage(0, 0xC0 + ch, prn.target_art.pc, 0)
                AudioPreview.current_art_pc = prn.target_art.pc
            end
            if prn.final_c1 then reaper.StuffMIDIMessage(0, 0xB0 + ch, 1, prn.final_c1) end
            if prn.final_c11 then reaper.StuffMIDIMessage(0, 0xB0 + ch, 11, prn.final_c11) end
            prn.stage = 2
            prn.stage2_time = now
            prn.stage2_delay = 0.045
        elseif prn.stage == 2 and (now - (prn.stage2_time or prn.release_time)) >= (prn.stage2_delay or 0.045) then
            reaper.StuffMIDIMessage(0, 0x90 + ch, prn.pitch, prn.vel)

            local is_momentary = false
            if prn.target_art and prn.target_art.name then
                local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
                is_momentary = MidiService.is_momentary_articulation(prn.target_art.name)
            end

            local note_info = {
                pitch = prn.pitch,
                chan = ch,
                vel = prn.vel,
                track = prn.track,
                start_time = now,
                released = true,
                is_momentary = is_momentary,
                bank = prn.bank
            }
            AudioPreview.active_note = note_info
            if state then
                state.audition_active_note = note_info
            end
            AudioPreview.pending_release_note = nil
            AudioPreview.last_activity_time = now
        end
    end

    -- 2. Check active playing note
    local an = AudioPreview.active_note or (state and state.audition_active_note)
    if an then
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

        -- Audition duration: 0.30s (300ms) for momentary/staccato and 0.45s (450ms) for legato/standard
        local min_dur = an.is_momentary and 0.30 or 0.45
        if an.released and dur >= min_dur then
            AudioPreview.stop_note(state)
        end
    else
        -- 3. Inactivity delay: if no notes played or armed for >= 2.0 seconds (and no pattern preview active), restore original input device
        local pat_svc = package.loaded["services.pattern_service"]
        local pat_playing = (pat_svc and pat_svc.active_preview ~= nil)
        if not pat_playing and not AudioPreview.pending_note and not AudioPreview.pending_release_note and not AudioPreview.arm_click_note and next(AudioPreview.track_restore) ~= nil then
            local idle_dur = now - (AudioPreview.last_activity_time or 0)
            if idle_dur >= 2.0 then
                AudioPreview.restore_all_tracks()
            end
        end
    end
end

return AudioPreview

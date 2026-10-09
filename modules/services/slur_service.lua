-- ==============================================================================
-- REAPER Native Notator - Service: SlurService
-- Manages Slurs (Legato phrase marks) & Ties (Held notes of identical pitch)
-- Handles Reaticulate legato keyswitches, note overlap, and auto-chase return
-- ==============================================================================

local Constants = require("constants")
local Engraver  = require("rendering.engraver")

local SlurService = {}

local function pitch_to_name(pitch)
    if not pitch then return "" end
    local names = Constants.PITCH_NAMES or { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
    local oct = math.floor(pitch / 12) - 1
    local name = names[(pitch % 12) + 1] or "C"
    return string.format("%s%d", name, oct)
end

local function get_track_from_take(take)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil end
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then return nil end
    return reaper.GetMediaItem_Track(item)
end

local function normalize_guid(g)
    if not g then return "" end
    return g:upper():gsub("[^%w]", "")
end

local function get_track_from_note(n)
    if not n then return nil end
    if n.track and reaper.ValidatePtr(n.track, "MediaTrack*") then
        return n.track
    end
    if n.take and reaper.ValidatePtr(n.take, "MediaItem_Take*") then
        local item = reaper.GetMediaItemTake_Item(n.take)
        if item and reaper.ValidatePtr(item, "MediaItem*") then
            local trk = reaper.GetMediaItem_Track(item)
            if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                return trk
            end
        end
    end
    if n.orig then
        return get_track_from_note(n.orig)
    end
    return nil
end

local function get_item_from_note(n)
    if not n then return nil end
    if n.item and reaper.ValidatePtr(n.item, "MediaItem*") then
        return n.item
    end
    if n.take and reaper.ValidatePtr(n.take, "MediaItem_Take*") then
        local item = reaper.GetMediaItemTake_Item(n.take)
        if item and reaper.ValidatePtr(item, "MediaItem*") then
            return item
        end
    end
    if n.orig then
        return get_item_from_note(n.orig)
    end
    return nil
end

local function get_track_guid_from_note(n)
    if not n then return nil end
    if n.track_guid and n.track_guid ~= "" then
        return n.track_guid
    end
    if n.orig and n.orig.track_guid and n.orig.track_guid ~= "" then
        return n.orig.track_guid
    end
    local trk = get_track_from_note(n)
    if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
        return reaper.GetTrackGUID(trk)
    end
    return nil
end

local function notes_share_same_track(n1, n2)
    if not n1 or not n2 then return false end
    local trk1 = get_track_from_note(n1)
    local trk2 = get_track_from_note(n2)
    if trk1 and trk2 and trk1 ~= trk2 then
        return false
    end
    local guid1 = get_track_guid_from_note(n1)
    local guid2 = get_track_guid_from_note(n2)
    if guid1 and guid2 and guid1 ~= "" and guid2 ~= "" then
        if normalize_guid(guid1) ~= normalize_guid(guid2) then
            return false
        end
    end
    return true
end


local function find_take_note_by_pos(take, pitch, chan, target_qn, opt_tolerance_qn)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil, nil end
    local tol_qn = opt_tolerance_qn or 0.10
    local target_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, target_qn)
    local tol_ppq = math.max(35, math.abs(reaper.MIDI_GetPPQPosFromProjQN(take, target_qn + tol_qn) - target_ppq))
    
    local _, notecnt = reaper.MIDI_CountEvts(take)
    local best_idx = nil
    local min_dppq = 999999
    local best_note_data = nil
    
    for i = 0, notecnt - 1 do
        local ok, sel, muted, sppq, eppq, ch, p, vel = reaper.MIDI_GetNote(take, i)
        if ok and p == pitch and (chan == nil or ch == chan) then
            local dppq = math.abs(sppq - target_ppq)
            if dppq <= tol_ppq and dppq < min_dppq then
                min_dppq = dppq
                best_idx = i
                best_note_data = { sel = sel, muted = muted, sppq = sppq, eppq = eppq, chan = ch, pitch = p, vel = vel }
            end
        end
    end
    return best_idx, best_note_data
end


-- ------------------------------------------------------------------------------
-- Target Note Resolution
-- ------------------------------------------------------------------------------

local function get_target_notes(state)
    local targets = {}
    if state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            table.insert(targets, sn)
        end
    end
    if #targets == 0 and state.selected_note then
        table.insert(targets, state.selected_note)
    end
    table.sort(targets, function(a, b)
        if math.abs((a.start_qn or 0) - (b.start_qn or 0)) > 0.001 then
            return (a.start_qn or 0) < (b.start_qn or 0)
        end
        return (a.pitch or 0) < (b.pitch or 0)
    end)
    return targets
end

local function find_next_chronological_note(n1, active_tracks_data, require_same_pitch)
    if not n1 then return nil end
    local n1_sqn = n1.start_qn or 0
    local n1_chan = n1.chan or 0
    local n1_guid = get_track_guid_from_note(n1)
    local n1_trk = get_track_from_note(n1)
    local best_note = nil
    local min_dt = 999999.0
    
    if active_tracks_data then
        for _, td in ipairs(active_tracks_data) do
            local is_match_track = false
            if td.track and n1_trk and td.track == n1_trk then
                is_match_track = true
            elseif n1_guid and td.guid and normalize_guid(td.guid) == normalize_guid(n1_guid) then
                is_match_track = true
            elseif td.track and n1.take and reaper.ValidatePtr(n1.take, "MediaItem_Take*") then
                local take_trk = get_track_from_take(n1.take)
                if take_trk == td.track then is_match_track = true end
            end
            
            if is_match_track and td.notes then
                for _, cand in ipairs(td.notes) do
                    local cand_sqn = cand.start_qn or 0
                    local dt = cand_sqn - n1_sqn
                    if dt > 0.005 and (cand.chan or 0) == n1_chan then
                        if not require_same_pitch or cand.pitch == n1.pitch then
                            if dt < min_dt then
                                min_dt = dt
                                best_note = cand
                            elseif math.abs(dt - min_dt) < 0.005 and best_note then
                                -- In chord: pick note with closest pitch
                                if math.abs(cand.pitch - n1.pitch) < math.abs(best_note.pitch - n1.pitch) then
                                    best_note = cand
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Fallback: scan directly in n1.take if active_tracks_data didn't contain it
    if not best_note and n1.take and reaper.ValidatePtr(n1.take, "MediaItem_Take*") then
        local take = n1.take
        local _, notecnt = reaper.MIDI_CountEvts(take)
        for i = 0, notecnt - 1 do
            local ok, _, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
            if ok and not muted and chan == n1_chan then
                local cand_sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                local cand_eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                local dt = cand_sqn - n1_sqn
                if dt > 0.005 then
                    if not require_same_pitch or pitch == n1.pitch then
                        if dt < min_dt then
                            min_dt = dt
                            best_note = {
                                idx = i,
                                take = take,
                                track = n1.track,
                                chan = chan,
                                pitch = pitch,
                                vel = vel,
                                start_qn = cand_sqn,
                                end_qn = cand_eqn,
                                dur_qn = cand_eqn - cand_sqn,
                                key = string.format("%d_%.4f_%d", pitch, cand_sqn, chan)
                            }
                        end
                    end
                end
            end
        end
    end
    
    return best_note
end

-- ------------------------------------------------------------------------------
-- Slur Management (Bindebögen / Legato)
-- ------------------------------------------------------------------------------

function SlurService.toggle_slur(state, active_tracks_data)
    local targets = get_target_notes(state)
    if #targets == 0 then
        state.status_msg = "Select 1 note (to slur to next) or 2+ notes to slur."
        return
    end
    
    local n1, n_last
    local phrase_notes = {}
    if #targets >= 2 then
        -- Strict Cross-Track Guard: all selected notes MUST belong to the same instrument/track!
        for i = 2, #targets do
            if not notes_share_same_track(targets[1], targets[i]) then
                state.status_msg = "⚠️ Slurs can only connect notes within the same instrument."
                return
            end
        end
        n1 = targets[1]
        n_last = targets[#targets]
        for _, t in ipairs(targets) do
            if (t.chan or 0) == (n1.chan or 0) then
                table.insert(phrase_notes, t)
            end
        end
    else
        n1 = targets[1]
        n_last = find_next_chronological_note(n1, active_tracks_data, false)
        if not n_last then
            state.status_msg = "⚠️ No subsequent note found to slur to on this track/voice."
            return
        end
        table.insert(phrase_notes, n1)
        table.insert(phrase_notes, n_last)
    end
    
    -- Expand to all intermediate notes between n1 and n_last on the same voice/channel strictly within this track!
    if active_tracks_data and #targets >= 2 and n_last.start_qn - n1.start_qn > 0.005 then
        local all_cands = {}
        local n1_guid = get_track_guid_from_note(n1)
        local n1_trk = get_track_from_note(n1)
        for _, td in ipairs(active_tracks_data) do
            local is_match = false
            if n1_trk and td.track and td.track == n1_trk then
                is_match = true
            elseif n1_guid and td.guid and normalize_guid(td.guid) == normalize_guid(n1_guid) then
                is_match = true
            end
            if is_match and td.notes then
                for _, cand in ipairs(td.notes) do
                    if (cand.chan or 0) == (n1.chan or 0) and cand.start_qn >= n1.start_qn - 0.005 and cand.start_qn <= n_last.start_qn + 0.005 then
                        table.insert(all_cands, cand)
                    end
                end
            end
        end
        if #all_cands >= 2 then
            table.sort(all_cands, function(a, b) return a.start_qn < b.start_qn end)
            phrase_notes = all_cands
            n1 = phrase_notes[1]
            n_last = phrase_notes[#phrase_notes]
        end
    end
    
    local n1_k = n1.key or (n1.get_key and n1:get_key()) or string.format("%d_%.4f_%d", n1.pitch, n1.start_qn, n1.chan or 0)
    local n_last_k = n_last.key or (n_last.get_key and n_last:get_key()) or string.format("%d_%.4f_%d", n_last.pitch, n_last.start_qn, n_last.chan or 0)
    
    state.user_slurs = state.user_slurs or {}
    
    -- Check if a slur already starts at Note 1 or connects Note 1 to Note Last (Toggle Off)
    local existing_idx = nil
    for idx, sl in ipairs(state.user_slurs) do
        if sl.n1_key == n1_k or (math.abs(sl.start_qn - n1.start_qn) < 0.01 and sl.pitch1 == n1.pitch and (sl.chan or 0) == (n1.chan or 0)) then
            existing_idx = idx
            break
        end
    end
    
    local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    
    if existing_idx then
        -- TOGGLE OFF: Remove slur and restore original note durations / playback
        local sl = state.user_slurs[existing_idx]
        SlurService.delete_slur(state, sl, MidiService, active_tracks_data)
        return
    end
    
    -- TOGGLE ON: Create Slur
    local take = n1.take or (n_last and n_last.take) or MidiService.get_active_midi_take()
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        state.status_msg = "⚠️ Active MIDI take not found."
        return
    end
    
    reaper.Undo_BeginBlock2(0)
    reaper.MIDI_DisableSort(take)
    
    local slur_id = "slur_" .. tostring(reaper.time_precise()):gsub("%.", "")
    local orig_dur1 = n1.dur_qn or ((n1.end_qn or (n1.start_qn + 1.0)) - n1.start_qn)
    local chan = n1.chan or 0
    
    local trk = get_track_from_take(take)
    local trk_guid = (trk and reaper.GetTrackGUID(trk)) or ""
    local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks()
    local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, all_banks)
    
    local n1_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n1.start_qn) + 0.5)
    
    -- 1. Scan for active pre-slur articulation on this channel (e.g. Tremolo)
    local pre_slur_pc = nil
    local pre_slur_msb = -1
    local pre_slur_lsb = -1
    local latest_pc_ppq = -1
    local cur_msb = -1
    local cur_lsb = -1
    local _, _, cur_cc_cnt = reaper.MIDI_CountEvts(take)
    for ci = 0, cur_cc_cnt - 1 do
        local ok, _, _, ppq, chanmsg, cchan, msg2, msg3 = reaper.MIDI_GetCC(take, ci)
        if ok and cchan == chan and ppq < n1_sppq - 10 then
            if (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and msg2 == 0 then
                cur_msb = msg3
            elseif (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and msg2 == 32 then
                cur_lsb = msg3
            elseif (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0) then
                if ppq > latest_pc_ppq then
                    latest_pc_ppq = ppq
                    pre_slur_pc = msg2
                    pre_slur_msb = cur_msb
                    pre_slur_lsb = cur_lsb
                end
            end
        end
    end
    
    -- 2. Extend each note in phrase to touch the next note for true sampler legato interval triggering
    for i = 1, #phrase_notes - 1 do
        local curr = phrase_notes[i]
        local next_n = phrase_notes[i + 1]
        local next_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, next_n.start_qn) + 0.5)
        local curr_idx, curr_data = find_take_note_by_pos(take, curr.pitch, curr.chan or 0, curr.start_qn)
        if curr_idx and curr_data then
            local leg_end_ppq
            if curr.pitch == next_n.pitch then
                -- Notes of the same pitch: never overlap to avoid REAPER note merging/deletion
                leg_end_ppq = math.min(curr_data.eppq, math.max(curr_data.sppq + 20, next_sppq - 1))
            else
                leg_end_ppq = math.max(curr_data.sppq + 20, next_sppq + 2)
            end
            reaper.MIDI_SetNote(take, curr_idx, curr_data.sel, curr_data.muted, curr_data.sppq, leg_end_ppq, curr_data.chan, curr_data.pitch, curr_data.vel, false)
        end
    end
    
    -- 3. Insert Legato articulation: look for "legato", fallback to "long" / "sustain" (User requirement!)
    local art_match = bank and MidiService.find_reaticulate_art_for_id(bank, "legato")
    if not art_match and bank then
        art_match = MidiService.find_reaticulate_art_for_id(bank, "long")
    end
    if not art_match and bank then
        art_match = MidiService.find_reaticulate_art_for_id(bank, "sustain")
    end
    
    if art_match then
        local eff_msb = (bank.msb and bank.msb >= 0) and bank.msb or pre_slur_msb
        local eff_lsb = (bank.lsb and bank.lsb >= 0) and bank.lsb or pre_slur_lsb
        if eff_msb and eff_msb >= 0 then
            reaper.MIDI_InsertCC(take, false, false, n1_sppq, 0xB0, chan, 0, eff_msb)
        end
        if eff_lsb and eff_lsb >= 0 then
            reaper.MIDI_InsertCC(take, false, false, n1_sppq, 0xB0, chan, 32, eff_lsb)
        end
        reaper.MIDI_InsertCC(take, false, false, n1_sppq, 0xC0, chan, art_match.pc, 0)
    end
    
    -- 4. Tag all notes in phrase with Type 15 "NOTE pitch chan a legato"
    for _, pn in ipairs(phrase_notes) do
        local pn_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, pn.start_qn) + 0.5)
        reaper.MIDI_InsertTextSysexEvt(take, false, false, pn_sppq, 15, string.format("NOTE %d %d a legato", pn.pitch, chan))
        pn.articulation = "legato"
    end
    
    -- 5. Insert Type 15 Slur persistence tag with pre_slur articulation memory
    reaper.MIDI_InsertTextSysexEvt(take, false, false, n1_sppq, 15, string.format("NOTATOR_SLUR %s %d %d %d %.4f %.4f %.4f %s %s %s",
        slur_id, chan, n1.pitch, n_last.pitch, n1.start_qn, n_last.start_qn, orig_dur1,
        pre_slur_pc or "", pre_slur_msb or -1, pre_slur_lsb or -1))
    
    -- 6. Store slur in state
    local slur_obj = {
        id = slur_id,
        track_guid = trk_guid,
        chan = chan,
        pitch1 = n1.pitch,
        pitch2 = n_last.pitch,
        start_qn = n1.start_qn,
        end_qn = n_last.end_qn or (n_last.start_qn + 1.0),
        n2_start_qn = n_last.start_qn,
        orig_dur1 = orig_dur1,
        pre_slur_pc = pre_slur_pc,
        pre_slur_msb = pre_slur_msb,
        pre_slur_lsb = pre_slur_lsb,
        n1_key = n1_k,
        n2_key = n_last_k
    }
    table.insert(state.user_slurs, slur_obj)
    n1.slur_to = n_last_k
    n1.slur_id = slur_id
    
    -- 7. Auto-Chase Return at end of phrase (automatically restores pre_slur_pc, e.g. Tremolo!)
    MidiService.auto_chase_momentary_articulations(take, bank)
    
    reaper.MIDI_Sort(take)
    reaper.Undo_EndBlock2(0, "Notator: Add Slur", -1)
    reaper.UpdateArrange()
    
    SlurService.save_slurs(state)
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    local art_label = (art_match and art_match.name) or "Legato"
    state.status_msg = string.format("Slur created [S] (%s %s -> %s, %d notes)", art_label, pitch_to_name(n1.pitch), pitch_to_name(n_last.pitch), #phrase_notes)
end

-- ------------------------------------------------------------------------------
-- Tie Management (Haltebögen)
-- ------------------------------------------------------------------------------

function SlurService.toggle_tie(state, active_tracks_data)
    local targets = get_target_notes(state)
    if #targets == 0 then
        state.status_msg = "Select 1 note (to tie to next of same pitch) or 2 notes to tie."
        return
    end
    
    state.user_ties = state.user_ties or {}
    local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
    
    -- Check if any selected note is already part of an existing tie -> UNTIE
    local existing_tie_idx = nil
    for idx, tie in ipairs(state.user_ties) do
        for _, tn in ipairs(targets) do
            local tn_k = tn.key or (tn.get_key and tn:get_key())
            local match_key = (tn_k and (tie.n1_key == tn_k or tie.n2_key == tn_k))
            local match_pos1 = (tie.pitch == tn.pitch and (tie.chan or 0) == (tn.chan or 0) and math.abs(tie.n1_start_qn - (tn.start_qn or 0)) < 0.10)
            local match_pos2 = (tie.pitch == tn.pitch and (tie.chan or 0) == (tn.chan or 0) and math.abs(tie.n2_start_qn - (tn.start_qn or 0)) < 0.10)
            if match_key or match_pos1 or match_pos2 then
                existing_tie_idx = idx
                break
            end
        end
        if existing_tie_idx then break end
    end
    
    if existing_tie_idx then
        -- UNTIE / TOGGLE OFF
        local tie = state.user_ties[existing_tie_idx]
        SlurService.delete_tie(state, tie, MidiService, active_tracks_data)
        return
    end
    
    -- TIE CREATION: Find pair of notes to tie
    local n1, n2
    if #targets >= 2 then
        n1 = targets[1]
        n2 = targets[2]
        if not notes_share_same_track(n1, n2) then
            state.status_msg = "⚠️ Ties can only connect notes within the same instrument."
            return
        end
        if n1.pitch ~= n2.pitch then
            state.status_msg = "⚠️ Tie requires notes of the same pitch! Use Slur [S] for melodic phrases."
            return
        end
    else
        n1 = targets[1]
        n2 = find_next_chronological_note(n1, active_tracks_data, true)
        if not n2 then
            state.status_msg = "⚠️ No subsequent note with the same pitch found to tie."
            return
        end
    end
    
    local take = n1.take or (n2 and n2.take) or MidiService.get_active_midi_take()
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        state.status_msg = "⚠️ Active MIDI take not found."
        return
    end
    
    local n1_k = n1.key or (n1.get_key and n1:get_key()) or string.format("%d_%.4f_%d", n1.pitch, n1.start_qn, n1.chan or 0)
    local n2_k = n2.key or (n2.get_key and n2:get_key()) or string.format("%d_%.4f_%d", n2.pitch, n2.start_qn, n2.chan or 0)
    
    reaper.Undo_BeginBlock2(0)
    reaper.MIDI_DisableSort(take)
    
    local tie_id = "tie_" .. tostring(reaper.time_precise()):gsub("%.", "")
    local n1_dur = n1.dur_qn or ((n1.end_qn or (n1.start_qn + 1.0)) - n1.start_qn)
    local n2_dur = n2.dur_qn or ((n2.end_qn or (n2.start_qn + 1.0)) - n2.start_qn)
    local n2_vel = n2.vel or 96
    
    local n1_idx, n1_data
    if n1.idx and n1.idx >= 0 then
        local ok, sel, muted, sppq, eppq, ch, p, vel = reaper.MIDI_GetNote(take, n1.idx)
        if ok and p == n1.pitch then
            n1_idx = n1.idx
            n1_data = { sel = sel, muted = muted, sppq = sppq, eppq = eppq, chan = ch, pitch = p, vel = vel }
        end
    end
    if not n1_idx then
        n1_idx, n1_data = find_take_note_by_pos(take, n1.pitch, n1.chan or 0, n1.start_qn, 0.35)
    end
    
    local n2_idx, n2_data
    if n2.idx and n2.idx >= 0 then
        local ok, sel, muted, sppq, eppq, ch, p, vel = reaper.MIDI_GetNote(take, n2.idx)
        if ok and p == n2.pitch then
            n2_idx = n2.idx
            n2_data = { sel = sel, muted = muted, sppq = sppq, eppq = eppq, chan = ch, pitch = p, vel = vel }
        end
    end
    if not n2_idx then
        n2_idx, n2_data = find_take_note_by_pos(take, n2.pitch, n2.chan or 0, n2.start_qn, 0.35)
    end
    
    local n1_sppq = n1_data and n1_data.sppq or math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n1.start_qn) + 0.5)
    local n2_sppq = n2_data and n2_data.sppq or math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n2.start_qn) + 0.5)
    local n2_eppq = n2_data and n2_data.eppq or math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n2.end_qn or (n2.start_qn + n2_dur)) + 0.5)
    
    -- 1. Safely delete Note 2 from the MIDI take so audio playback never re-strikes
    -- (The visual Note 2 is seamlessly synthesized on the score canvas from NOTATOR_TIE!)
    local eff_n1_idx = n1_idx
    if n2_idx and n2_data then
        reaper.MIDI_DeleteNote(take, n2_idx)
        if eff_n1_idx and eff_n1_idx > n2_idx then
            eff_n1_idx = eff_n1_idx - 1
        end
    end
    
    -- 2. Extend Note 1 to cover Note 2's end so REAPER holds audio sustain continuously
    if eff_n1_idx then
        local ok, sel, muted, sppq, _, chan, pitch, vel = reaper.MIDI_GetNote(take, eff_n1_idx)
        if ok then
            reaper.MIDI_SetNote(take, eff_n1_idx, sel, false, sppq, n2_eppq, chan, pitch, vel, false)
        end
    else
        local cur_n1_idx = find_take_note_by_pos(take, n1.pitch, n1.chan or 0, n1.start_qn, 0.35)
        if cur_n1_idx then
            local ok, sel, muted, sppq, _, chan, pitch, vel = reaper.MIDI_GetNote(take, cur_n1_idx)
            if ok then
                reaper.MIDI_SetNote(take, cur_n1_idx, sel, false, sppq, n2_eppq, chan, pitch, vel, false)
            end
        end
    end
    
    -- 3. Save Type 15 Tie Tags for master and slave
    reaper.MIDI_InsertTextSysexEvt(take, false, false, n1_sppq, 15, string.format("NOTATOR_TIE %s %d %d %.4f %.4f %.4f %.4f %d",
        tie_id, n1.chan or 0, n1.pitch, n1.start_qn, n1_dur, n2.start_qn, n2_dur, n2_vel))
    reaper.MIDI_InsertTextSysexEvt(take, false, false, n2_sppq, 15, string.format("NOTATOR_TIE_SLAVE %s %d %d %.4f %.4f",
        tie_id, n1.chan or 0, n1.pitch, n2.start_qn, n2_dur))
    
    -- 4. Store in state
    local trk = get_track_from_note(n1) or (take and get_track_from_take(take))
    local trk_guid = get_track_guid_from_note(n1) or (trk and reaper.GetTrackGUID(trk)) or ""
    local tie_obj = {
        id = tie_id,
        track_guid = trk_guid,
        chan = n1.chan or 0,
        pitch = n1.pitch,
        n1_start_qn = n1.start_qn,
        n1_dur = n1_dur,
        n2_start_qn = n2.start_qn,
        n2_dur = n2_dur,
        n2_vel = n2_vel,
        n1_key = n1_k,
        n2_key = n2_k
    }
    table.insert(state.user_ties, tie_obj)
    
    -- If Note 1 has an existing portamento, shift it to start at Note 2!
    if state.portamento_marks then
        local PortamentoService = package.loaded["services.portamento_service"] or require("services.portamento_service")
        local changed_port = false
        for _, pm in ipairs(state.portamento_marks) do
            if pm.pitch1 == n1.pitch and math.abs(pm.start_qn1 - n1.start_qn) < 0.05 then
                pm.start_qn1 = n2.start_qn
                pm.dur_qn1   = n2_dur
                pm.n1_key    = n2_k
                pm:recalculate_timing()
                PortamentoService.apply_cc(state, pm, active_tracks_data)
                changed_port = true
            end
        end
        if changed_port then
            PortamentoService.save_portamentos(state)
        end
    end
    
    reaper.MIDI_Sort(take)
    
    -- Refresh REAPER audio engine and open MIDI editor window
    local it = reaper.GetMediaItemTake_Item(take)
    if it then
        local it_trk = reaper.GetMediaItem_Track(it)
        reaper.MarkTrackItemsDirty(it_trk, it)
    end
    local cur_editor = reaper.MIDIEditor_GetActive()
    if cur_editor then
        reaper.MIDIEditor_OnCommand(cur_editor, 40435) -- Reload MIDI in editor
    end
    
    reaper.Undo_EndBlock2(0, "Notator: Tie Notes", -1)
    reaper.UpdateArrange()
    
    SlurService.save_slurs(state)
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    state.status_msg = string.format("Tied notes [T] (%s, visual separate notes preserved, held audio)", pitch_to_name(n1.pitch))
end

-- ------------------------------------------------------------------------------
-- Residue-Free Removal
-- ------------------------------------------------------------------------------

function SlurService.delete_slur(state, slur_or_id, midi_service, active_tracks_data)
    if not state then return end
    state.user_slurs = state.user_slurs or {}
    
    local target_id = type(slur_or_id) == "table" and slur_or_id.id or slur_or_id
    local sl = nil
    local sl_idx = nil
    for idx, s in ipairs(state.user_slurs) do
        if s.id == target_id then
            sl = s
            sl_idx = idx
            break
        end
    end
    if not sl then return end
    
    local MidiService = midi_service or package.loaded["services.midi_service"] or require("services.midi_service")
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    
    -- Locate take
    local take = nil
    if sl.track_guid and sl.track_guid ~= "" then
        local num_tracks = reaper.CountTracks(0)
        for ti = 0, num_tracks - 1 do
            local trk = reaper.GetTrack(0, ti)
            if trk and reaper.GetTrackGUID(trk) == sl.track_guid then
                local num_items = reaper.CountTrackMediaItems(trk)
                for ii = 0, num_items - 1 do
                    local it = reaper.GetTrackMediaItem(trk, ii)
                    local tk = it and reaper.GetActiveTake(it)
                    if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") and reaper.TakeIsMIDI(tk) then
                        take = tk
                        break
                    end
                end
                break
            end
        end
    end
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        take = MidiService.get_active_midi_take()
    end
    
    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        reaper.Undo_BeginBlock2(0)
        reaper.MIDI_DisableSort(take)
        
        local n1_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sl.start_qn or 0.0) + 0.5)
        local n2_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sl.n2_start_qn or (sl.start_qn + 1.0)) + 0.5)
        local sl_end_qn = sl.end_qn or (sl.n2_start_qn and (sl.n2_start_qn + 1.0)) or (sl.start_qn + 2.0)
        local n2_eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sl_end_qn) + 0.5)
        
        -- 1. Restore note durations across phrase (if shortened or elongated)
        local n1_idx, n1_data = find_take_note_by_pos(take, sl.pitch1, sl.chan or 0, sl.start_qn)
        if n1_idx and n1_data and sl.orig_dur1 then
            local orig_eqn1 = (sl.start_qn or 0.0) + (sl.orig_dur1 or 1.0)
            local orig_eppq1 = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, orig_eqn1) + 0.5)
            reaper.MIDI_SetNote(take, n1_idx, n1_data.sel, n1_data.muted, n1_data.sppq, orig_eppq1, n1_data.chan, n1_data.pitch, n1_data.vel, false)
        end
        -- Also scan notes within slur time span and clamp any micro-legato overlap remnants (<= 10 ticks)
        local _, slur_notecnt = reaper.MIDI_CountEvts(take)
        for i = 0, slur_notecnt - 1 do
            local ok_s, sel_s, mut_s, sp_s, ep_s, ch_s, pt_s, vel_s = reaper.MIDI_GetNote(take, i)
            if ok_s and not mut_s and ch_s == (sl.chan or 0) and sp_s >= n1_sppq - 10 and sp_s <= n2_eppq + 10 then
                for j = 0, slur_notecnt - 1 do
                    if j ~= i then
                        local ok_j, _, mut_j, sp_j, _, ch_j, _, _ = reaper.MIDI_GetNote(take, j)
                        if ok_j and not mut_j and ch_j == ch_s and sp_j > sp_s and sp_j < ep_s and (ep_s - sp_j) <= 10 then
                            reaper.MIDI_SetNote(take, i, sel_s, mut_s, sp_s, sp_j, ch_s, pt_s, vel_s, false)
                            ep_s = sp_j
                            break
                        end
                    end
                end
            end
        end
        
        -- 2. Delete Type 15 tags: NOTATOR_SLUR and NOTE pitch chan a legato
        local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
        for ti = text_cnt - 1, 0, -1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
            if ok and etype == 15 then
                if msg:match("^NOTATOR_SLUR%s+" .. sl.id) then
                    reaper.MIDI_DeleteTextSysexEvt(take, ti)
                elseif msg:match("%s+a%s+legato") and ppq >= n1_sppq - 80 and ppq <= n2_eppq + 80 then
                    reaper.MIDI_DeleteTextSysexEvt(take, ti)
                end
            end
        end
        
        -- 3. Delete Program Change and Bank CCs inserted for the slur at Note 1 (within 80 PPQ)
        local _, _, cur_cccnt = reaper.MIDI_CountEvts(take)
        for ci = cur_cccnt - 1, 0, -1 do
            local ok, _, _, ppq, chanmsg, cchan, msg2 = reaper.MIDI_GetCC(take, ci)
            if ok and cchan == (sl.chan or 0) and math.abs(ppq - n1_sppq) <= 80 then
                local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                if is_pc or is_bank then
                    reaper.MIDI_DeleteCC(take, ci)
                end
            end
        end
        
        -- 4. Delete return chase events (NOTATOR_CHASE text events and return Bank CCs/PCs) that belonged to this slur
        -- NOTE: We intentionally do NOT insert pre_slur_pc at Note 1.
        -- Any prior articulation (e.g. Tremolo from Bar 1) is already active on this channel and naturally stays in effect!
        local _, _, _, cur_text_cnt2 = reaper.MIDI_CountEvts(take)
        for ti = cur_text_cnt2 - 1, 0, -1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
            if ok and etype == 15 then
                local ch_c, pc_c = msg:match("NOTATOR_CHASE%s+(%d+)%s+(%-?%d+)")
                if ch_c and tonumber(ch_c) == (sl.chan or 0) and ppq >= n1_sppq - 80 and ppq <= n2_eppq + 150 then
                    local num_pc = tonumber(pc_c)
                    reaper.MIDI_DeleteTextSysexEvt(take, ti)
                    local _, _, cur_cc_cnt3 = reaper.MIDI_CountEvts(take)
                    for ci = cur_cc_cnt3 - 1, 0, -1 do
                        local ok_c, _, _, c_ppq, chanmsg, c_chan, msg2 = reaper.MIDI_GetCC(take, ci)
                        if ok_c and c_chan == (sl.chan or 0) and math.abs(c_ppq - ppq) <= 35 then
                            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                            local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                            if is_pc and (msg2 == num_pc or (num_pc and num_pc < 0 and msg2 == 127)) then
                                reaper.MIDI_DeleteCC(take, ci)
                            elseif is_bank then
                                reaper.MIDI_DeleteCC(take, ci)
                            end
                        end
                    end
                end
            end
        end
        
        -- 5. Remove slur from state before running auto_chase
        table.remove(state.user_slurs, sl_idx)
        if state.selected_slur and state.selected_slur.id == sl.id then
            state.selected_slur = nil
        end
        
        -- 6. Re-evaluate remaining momentary articulations (if any)
        local trk = get_track_from_take(take)
        local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, ReaticulateParser.get_all_banks())
        MidiService.auto_chase_momentary_articulations(take, bank)
        
        reaper.MIDI_Sort(take)
        
        -- Refresh REAPER audio engine and open MIDI editor window
        local it = reaper.GetMediaItemTake_Item(take)
        if it then
            local it_trk = reaper.GetMediaItem_Track(it)
            reaper.MarkTrackItemsDirty(it_trk, it)
        end
        local cur_editor = reaper.MIDIEditor_GetActive()
        if cur_editor then
            reaper.MIDIEditor_OnCommand(cur_editor, 40435) -- Reload MIDI in editor
        end
        
        reaper.Undo_EndBlock2(0, "Notator: Delete Slur", -1)
        reaper.UpdateArrange()
    else
        table.remove(state.user_slurs, sl_idx)
        if state.selected_slur and state.selected_slur.id == sl.id then
            state.selected_slur = nil
        end
    end
    
    SlurService.save_slurs(state)
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    state.status_msg = "Slur deleted."
end

function SlurService.delete_tie(state, tie_or_id, midi_service, active_tracks_data)
    if not state then return end
    state.user_ties = state.user_ties or {}
    
    local target_id = type(tie_or_id) == "table" and tie_or_id.id or tie_or_id
    local tie = nil
    local tie_idx = nil
    for idx, t in ipairs(state.user_ties) do
        if t.id == target_id then
            tie = t
            tie_idx = idx
            break
        end
    end
    if not tie then return end
    
    local MidiService = midi_service or package.loaded["services.midi_service"] or require("services.midi_service")
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    
    -- Locate take
    local take = nil
    if tie.track_guid and tie.track_guid ~= "" then
        local num_tracks = reaper.CountTracks(0)
        for ti = 0, num_tracks - 1 do
            local trk = reaper.GetTrack(0, ti)
            if trk and reaper.GetTrackGUID(trk) == tie.track_guid then
                local num_items = reaper.CountTrackMediaItems(trk)
                for ii = 0, num_items - 1 do
                    local it = reaper.GetTrackMediaItem(trk, ii)
                    local tk = it and reaper.GetActiveTake(it)
                    if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") and reaper.TakeIsMIDI(tk) then
                        take = tk
                        break
                    end
                end
                break
            end
        end
    end
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        take = MidiService.get_active_midi_take()
    end
    
    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        reaper.Undo_BeginBlock2(0)
        reaper.MIDI_DisableSort(take)
        
        local orig_eppq1 = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, tie.n1_start_qn + (tie.n1_dur or 1.0)) + 0.5)
        local orig_eppq2 = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, tie.n2_start_qn + (tie.n2_dur or 1.0)) + 0.5)
        
        local n1_idx, n1_data = find_take_note_by_pos(take, tie.pitch, tie.chan or 0, tie.n1_start_qn)
        local n2_idx, n2_data = find_take_note_by_pos(take, tie.pitch, tie.chan or 0, tie.n2_start_qn)
        
        if n1_idx and n1_data then
            reaper.MIDI_SetNote(take, n1_idx, n1_data.sel, false, n1_data.sppq, orig_eppq1, n1_data.chan, n1_data.pitch, n1_data.vel, false)
        end
        if n2_idx and n2_data then
            reaper.MIDI_SetNote(take, n2_idx, n2_data.sel, false, n2_data.sppq, orig_eppq2, n2_data.chan, n2_data.pitch, n2_data.vel, false)
        else
            local sppq2_target = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, tie.n2_start_qn) + 0.5)
            reaper.MIDI_InsertNote(take, false, false, sppq2_target, orig_eppq2, tie.chan or 0, tie.pitch, tie.n2_vel or 96, false)
        end
        
        -- Delete Type 15 Tie tags (both master and slave)
        local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
        for ti = text_cnt - 1, 0, -1 do
            local ok, _, _, _, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
            if ok and etype == 15 and (msg:match("^NOTATOR_TIE%s+" .. tie.id) or msg:match("^NOTATOR_TIE_SLAVE%s+" .. tie.id)) then
                reaper.MIDI_DeleteTextSysexEvt(take, ti)
            end
        end
        
        local trk = get_track_from_take(take)
        local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, ReaticulateParser.get_all_banks())
        MidiService.auto_chase_momentary_articulations(take, bank)
        
        reaper.MIDI_Sort(take)
        
        -- Refresh REAPER audio engine and open MIDI editor window
        local it = reaper.GetMediaItemTake_Item(take)
        if it then
            local it_trk = reaper.GetMediaItem_Track(it)
            reaper.MarkTrackItemsDirty(it_trk, it)
        end
        local cur_editor = reaper.MIDIEditor_GetActive()
        if cur_editor then
            reaper.MIDIEditor_OnCommand(cur_editor, 40435) -- Reload MIDI in editor
        end
        
        reaper.Undo_EndBlock2(0, "Notator: Untie Notes", -1)
        reaper.UpdateArrange()
    end
    
    table.remove(state.user_ties, tie_idx)
    if state.selected_tie and state.selected_tie.id == tie.id then
        state.selected_tie = nil
    end
    SlurService.save_slurs(state)
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    state.status_msg = "Tie removed [T]."
end

function SlurService.remove_slurs_for_notes(state, notes)
    if not notes or #notes == 0 then return end
    state.user_slurs = state.user_slurs or {}
    state.user_ties = state.user_ties or {}
    
    local note_keys = {}
    local note_positions = {}
    for _, n in ipairs(notes) do
        local k = n.key or (n.get_key and n:get_key())
        if k then note_keys[k] = true end
        local n_guid = get_track_guid_from_note(n)
        table.insert(note_positions, { pitch = n.pitch, chan = n.chan or 0, sqn = n.start_qn or 0, guid = n_guid })
    end
    
    local to_del_slurs = {}
    for _, sl in ipairs(state.user_slurs) do
        local match = (sl.n1_key and note_keys[sl.n1_key]) or (sl.n2_key and note_keys[sl.n2_key])
        if not match then
            local sl_sqn = sl.start_qn or 0.0
            local sl_end = sl.end_qn or sl.n2_start_qn or (sl_sqn + 1.0)
            local sl_guid = sl.track_guid and normalize_guid(sl.track_guid)
            for _, np in ipairs(note_positions) do
                local guid_match = true
                if sl_guid and sl_guid ~= "" and np.guid and np.guid ~= "" then
                    guid_match = (sl_guid == normalize_guid(np.guid))
                end
                if guid_match and (sl.chan or 0) == np.chan and (math.abs(sl_sqn - np.sqn) < 0.10 or math.abs(sl_end - np.sqn) < 0.10) then
                    match = true; break
                end
            end
        end
        if match then table.insert(to_del_slurs, sl) end
    end
    for _, sl in ipairs(to_del_slurs) do
        SlurService.delete_slur(state, sl)
    end
    
    local to_del_ties = {}
    for _, tie in ipairs(state.user_ties) do
        local match = (tie.n1_key and note_keys[tie.n1_key]) or (tie.n2_key and note_keys[tie.n2_key])
        if not match then
            local t_sqn1 = tie.n1_start_qn or 0.0
            local t_sqn2 = tie.n2_start_qn or (t_sqn1 + 1.0)
            local tie_guid = tie.track_guid and normalize_guid(tie.track_guid)
            for _, np in ipairs(note_positions) do
                local guid_match = true
                if tie_guid and tie_guid ~= "" and np.guid and np.guid ~= "" then
                    guid_match = (tie_guid == normalize_guid(np.guid))
                end
                if guid_match and tie.pitch == np.pitch and (tie.chan or 0) == np.chan and (math.abs(t_sqn1 - np.sqn) < 0.10 or math.abs(t_sqn2 - np.sqn) < 0.10) then
                    match = true; break
                end
            end
        end
        if match then table.insert(to_del_ties, tie) end
    end
    for _, tie in ipairs(to_del_ties) do
        SlurService.delete_tie(state, tie)
    end
end

function SlurService.remove_slurs_and_ties(state, opt_notes)
    local targets = opt_notes or get_target_notes(state)
    if not targets or #targets == 0 then
        state.status_msg = "No notes selected to clear slurs or ties."
        return
    end
    SlurService.remove_slurs_for_notes(state, targets)
    state.status_msg = "Cleared slurs and ties from selected notes."
end

-- ------------------------------------------------------------------------------
-- Rendering: Cubic Bézier Slurs & Ties
-- ------------------------------------------------------------------------------

local function resolve_effective_slur_notes(state, sl, all_note_render_by_key)
    if not sl or not all_note_render_by_key then return nil, nil end

    local sl_guid = sl.track_guid and normalize_guid(sl.track_guid)
    
    local function note_matches_slur_track(nd)
        if not nd then return false end
        if sl_guid and sl_guid ~= "" then
            local nd_guid = get_track_guid_from_note(nd)
            if nd_guid and nd_guid ~= "" then
                if normalize_guid(nd_guid) ~= sl_guid then
                    return false
                end
            end
        end
        return true
    end

    local nd1 = all_note_render_by_key[sl.n1_key]
    local nd2 = all_note_render_by_key[sl.n2_key]

    if nd1 and not note_matches_slur_track(nd1) then nd1 = nil end
    if nd2 and not note_matches_slur_track(nd2) then nd2 = nil end

    -- Fallback by pitch and start_qn if key was re-keyed, strictly scoped to matching track & channel
    if not nd1 or not nd2 then
        local best_d1 = 999999
        local best_d2 = 999999
        for _, nd in pairs(all_note_render_by_key) do
            if note_matches_slur_track(nd) and (sl.chan == nil or (nd.chan or (nd.orig and nd.orig.chan) or 0) == (sl.chan or 0)) then
                local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                if not nd1 and nd.pitch == sl.pitch1 then
                    local d = math.abs(sqn - sl.start_qn)
                    if d < 0.05 and d < best_d1 then
                        best_d1 = d
                        nd1 = nd
                    end
                end
                if not nd2 and nd.pitch == sl.pitch2 then
                    local d = math.abs(sqn - (sl.n2_start_qn or sl.start_qn))
                    if d < 0.05 and d < best_d2 then
                        best_d2 = d
                        nd2 = nd
                    end
                end
            end
        end
    end

    if not nd1 or not nd2 then return nil, nil end

    -- If sl.track_guid was missing (legacy), inherit and persist from matched note
    if (not sl.track_guid or sl.track_guid == "") and nd1 then
        sl.track_guid = get_track_guid_from_note(nd1) or ""
    end

    -- STRICT GUARD: Notes MUST share same track!
    if not notes_share_same_track(nd1, nd2) then
        return nil, nil
    end

    local base_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or sl.start_qn or 0

    -- Segment arrival handling (Elaine Gould standard):
    -- If nd2 has multiple barline segments or is tied, ensure the slur lands on the FIRST segment
    if nd2.orig and nd2.is_segment then
        local first_seg = nd2
        local first_sqn = nd2.start_qn or 999999
        for _, nd in pairs(all_note_render_by_key) do
            if notes_share_same_track(nd, nd2) then
                local is_same_note = (nd.orig and nd2.orig and nd.orig == nd2.orig)
                if not is_same_note and nd2.orig and nd.orig and nd2.orig.take and nd.orig.take and nd2.orig.take == nd.orig.take and nd2.orig.idx and nd.orig.idx and nd2.orig.idx == nd.orig.idx then
                    is_same_note = true
                end
                if is_same_note and nd.is_segment then
                    local sqn = nd.start_qn or 0
                    if sqn < first_sqn and sqn > (base_sqn1 + 0.01) then
                        first_sqn = sqn
                        first_seg = nd
                    end
                end
            end
        end
        nd2 = first_seg
    end

    return nd1, nd2
end

local function resolve_effective_tie_notes(state, tie, all_note_render_by_key)
    if not tie or not all_note_render_by_key then return nil, nil end

    local tie_guid = tie.track_guid and normalize_guid(tie.track_guid)
    
    local function note_matches_tie_track(nd)
        if not nd then return false end
        if tie_guid and tie_guid ~= "" then
            local nd_guid = get_track_guid_from_note(nd)
            if nd_guid and nd_guid ~= "" then
                if normalize_guid(nd_guid) ~= tie_guid then
                    return false
                end
            end
        end
        return true
    end

    local nd1 = all_note_render_by_key[tie.n1_key]
    local nd2 = all_note_render_by_key[tie.n2_key]

    if nd1 and not note_matches_tie_track(nd1) then nd1 = nil end
    if nd2 and not note_matches_tie_track(nd2) then nd2 = nil end

    -- Fallback by pitch and start_qn if key was re-keyed, strictly scoped to matching track & channel
    if not nd1 or not nd2 then
        local best_d1 = 999999
        local best_d2 = 999999
        for _, nd in pairs(all_note_render_by_key) do
            if note_matches_tie_track(nd) and (tie.chan == nil or (nd.chan or (nd.orig and nd.orig.chan) or 0) == (tie.chan or 0)) then
                local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                if not nd1 and nd.pitch == tie.pitch then
                    local d = math.abs(sqn - (tie.n1_start_qn or 0.0))
                    if d < 0.05 and d < best_d1 then
                        best_d1 = d
                        nd1 = nd
                    end
                end
                if not nd2 and nd.pitch == tie.pitch then
                    local d = math.abs(sqn - (tie.n2_start_qn or 1.0))
                    if d < 0.05 and d < best_d2 then
                        best_d2 = d
                        nd2 = nd
                    end
                end
            end
        end
    end

    if not nd1 or not nd2 then return nil, nil end

    -- If tie.track_guid was missing (legacy), inherit from note
    if (not tie.track_guid or tie.track_guid == "") and nd1 then
        tie.track_guid = get_track_guid_from_note(nd1) or ""
    end

    -- STRICT GUARD: Notes MUST share same track and same pitch!
    if not notes_share_same_track(nd1, nd2) then
        return nil, nil
    end
    if nd1.pitch ~= nd2.pitch then
        return nil, nil
    end

    local base_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or tie.n1_start_qn or 0
    if nd2.orig and nd2.is_segment then
        local first_seg = nd2
        local first_sqn = nd2.start_qn or 999999
        for _, nd in pairs(all_note_render_by_key) do
            if notes_share_same_track(nd, nd2) then
                local is_same_note = (nd.orig and nd2.orig and nd.orig == nd2.orig)
                if not is_same_note and nd2.orig and nd.orig and nd2.orig.take and nd.orig.take and nd2.orig.take == nd.orig.take and nd2.orig.idx and nd.orig.idx and nd2.orig.idx == nd.orig.idx then
                    is_same_note = true
                end
                if is_same_note and nd.is_segment then
                    local sqn = nd.start_qn or 0
                    if sqn < first_sqn and sqn > (base_sqn1 + 0.01) then
                        first_sqn = sqn
                        first_seg = nd
                    end
                end
            end
        end
        nd2 = first_seg
    end

    return nd1, nd2
end

function SlurService.draw_slurs(ctx_or_dl, draw_list_or_state, state_or_notes, all_notes_or_s, s_or_cminx, cminx_or_cmaxx, cmaxx_or_cminy, cminy_or_cmaxy, cmaxy_or_hov, opt_hov, opt_mx, opt_my)
    local ctx, draw_list, state, all_note_render_by_key, s, cull_min_x, cull_max_x, cull_min_y, cull_max_y, is_hovered, mouse_x, mouse_y
    if reaper.APIExists("ImGui_ValidatePtr") and reaper.ImGui_ValidatePtr(ctx_or_dl, "ImGui_Context*") then
        ctx = ctx_or_dl
        draw_list = draw_list_or_state
        state = state_or_notes
        all_note_render_by_key = all_notes_or_s
        s = s_or_cminx
        cull_min_x = cminx_or_cmaxx
        cull_max_x = cmaxx_or_cminy
        cull_min_y = cminy_or_cmaxy
        cull_max_y = cmaxy_or_hov
        is_hovered = opt_hov
        mouse_x = opt_mx
        mouse_y = opt_my
    else
        draw_list = ctx_or_dl
        state = draw_list_or_state
        all_note_render_by_key = state_or_notes
        s = all_notes_or_s
        cull_min_x = s_or_cminx
        cull_max_x = cminx_or_cmaxx
        cull_min_y = cmaxx_or_cminy
        cull_max_y = cminy_or_cmaxy
        is_hovered = cmaxy_or_hov
        mouse_x = opt_hov
        mouse_y = opt_mx
    end

    if not state or not state.user_slurs or #state.user_slurs == 0 then return end
    
    for _, sl in ipairs(state.user_slurs) do
        local nd1, nd2 = resolve_effective_slur_notes(state, sl, all_note_render_by_key)
        
        if nd1 and nd2 and nd1.nx and nd2.nx then
            local x_min = math.min(nd1.nx, nd2.nx)
            local x_max = math.max(nd1.nx, nd2.nx)
            if x_max >= cull_min_x and x_min <= cull_max_x then
                -- Determine curve direction (Elaine Gould standard)
                -- If both stems up -> curve below (above = false)
                -- If both stems down -> curve above (above = true)
                -- If mixed -> curve above (above = true)
                local above = true
                if nd1.stem_down == false and nd2.stem_down == false then
                    above = false
                end
                
                local dist_x = nd2.nx - nd1.nx
                local dy = nd2.ny - nd1.ny
                local chord_len = math.sqrt(dist_x * dist_x + dy * dy)
                local arc_h = math.min(26 * s, math.max(8 * s, chord_len * 0.12))
                local dir = above and -1 or 1
                
                local start_x = nd1.nx + 5.0 * s
                local end_x   = nd2.nx - 5.0 * s
                local start_y = nd1.ny + dir * 6.0 * s
                local end_y   = nd2.ny + dir * 6.0 * s
                
                local cp_dist = math.abs(start_x - end_x) * 0.28
                local cp1_x = start_x + cp_dist
                local cp1_y = start_y + dir * arc_h
                local cp2_x = end_x - cp_dist
                local cp2_y = end_y + dir * arc_h
                
                -- Interactive Bezier Hit-testing
                local is_hit = false
                if ctx and is_hovered and mouse_x and mouse_y and end_x > start_x then
                    if mouse_x >= start_x - 6.0 * s and mouse_x <= end_x + 6.0 * s then
                        local t = math.max(0.0, math.min(1.0, (mouse_x - start_x) / (end_x - start_x)))
                        local u = 1.0 - t
                        local y_curve = (u * u * u * start_y) + (3.0 * u * u * t * cp1_y) + (3.0 * u * t * t * cp2_y) + (t * t * t * end_y)
                        if math.abs(mouse_y - y_curve) <= 8.0 * s then
                            is_hit = true
                        end
                    end
                end
                
                if is_hit then
                    state.hovered_slur = sl
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                    reaper.ImGui_SetTooltip(ctx, string.format("Slur: %s -> %s\nClick to select | Delete to remove", pitch_to_name(sl.pitch1), pitch_to_name(sl.pitch2)))
                    if reaper.ImGui_IsMouseClicked(ctx, 0) then
                        state:clear_selection()
                        state.selected_slur = sl
                        state.selected_tie = nil
                    end
                end
                
                local is_sel = (state.selected_slur and state.selected_slur.id == sl.id)
                local col = is_sel and (Constants.COLORS.selection_gold or 0xFFD700FF) or (Constants.COLORS.slur_col or Constants.COLORS.tie_col or 0x1A1A1AFF)
                local thickness = is_sel and (3.2 * s) or (2.0 * s)
                
                local is_ghost = (nd1.is_ghost_voice == true) or (nd2.is_ghost_voice == true)
                if is_ghost and not is_sel then
                    local alpha = math.floor((state.ghost_voice_opacity or 0.25) * 255)
                    col = (col & 0xFFFFFF00) | alpha
                end
                
                Engraver.draw_slur(draw_list, nd1.nx, nd1.ny, nd2.nx, nd2.ny, s, col, above, thickness)
            end
        end
    end
end

function SlurService.draw_user_ties(ctx_or_dl, draw_list_or_state, state_or_notes, all_notes_or_s, s_or_cminx, cminx_or_cmaxx, cmaxx_or_cminy, cminy_or_cmaxy, cmaxy_or_hov, opt_hov, opt_mx, opt_my)
    local ctx, draw_list, state, all_note_render_by_key, s, cull_min_x, cull_max_x, cull_min_y, cull_max_y, is_hovered, mouse_x, mouse_y
    if reaper.APIExists("ImGui_ValidatePtr") and reaper.ImGui_ValidatePtr(ctx_or_dl, "ImGui_Context*") then
        ctx = ctx_or_dl
        draw_list = draw_list_or_state
        state = state_or_notes
        all_note_render_by_key = all_notes_or_s
        s = s_or_cminx
        cull_min_x = cminx_or_cmaxx
        cull_max_x = cmaxx_or_cminy
        cull_min_y = cminy_or_cmaxy
        cull_max_y = cmaxy_or_hov
        is_hovered = opt_hov
        mouse_x = opt_mx
        mouse_y = opt_my
    else
        draw_list = ctx_or_dl
        state = draw_list_or_state
        all_note_render_by_key = state_or_notes
        s = all_notes_or_s
        cull_min_x = s_or_cminx
        cull_max_x = cminx_or_cmaxx
        cull_min_y = cmaxx_or_cminy
        cull_max_y = cminy_or_cmaxy
        is_hovered = cmaxy_or_hov
        mouse_x = opt_hov
        mouse_y = opt_mx
    end

    if not state or not state.user_ties or #state.user_ties == 0 then return end
    
    for _, tie in ipairs(state.user_ties) do
        local nd1, nd2 = resolve_effective_tie_notes(state, tie, all_note_render_by_key)
        
        if nd1 and nd2 and nd1.nx and nd2.nx then
            local x_min = math.min(nd1.nx, nd2.nx)
            local x_max = math.max(nd1.nx, nd2.nx)
            if x_max >= cull_min_x and x_min <= cull_max_x then
                -- Determine curve direction (Elaine Gould standard)
                -- If both stems up -> tie is below (above = false)
                -- If both stems down -> tie is above (above = true)
                -- If mixed -> opposite first stem
                local above = true
                if nd1.stem_down == false and nd2.stem_down == false then
                    above = false
                elseif nd1.stem_down == false then
                    above = false
                end
                
                local dist = math.abs(nd2.nx - nd1.nx)
                local arc_h = math.min(16 * s, math.max(6 * s, dist * 0.10))
                local dir = above and -1 or 1
                local offset_y = dir * arc_h
                local cp_offset = dist * 0.28
                
                local start_x = nd1.nx + 4 * s
                local end_x   = nd2.nx - 4 * s
                local start_y = nd1.ny + dir * 5.0 * s
                local end_y   = nd2.ny + dir * 5.0 * s
                local cp1_x = start_x + cp_offset
                local cp1_y = start_y + offset_y
                local cp2_x = end_x - cp_offset
                local cp2_y = end_y + offset_y
                
                -- Interactive Bezier Hit-testing
                local is_hit = false
                if ctx and is_hovered and mouse_x and mouse_y and end_x > start_x then
                    if mouse_x >= start_x - 6.0 * s and mouse_x <= end_x + 6.0 * s then
                        local t = math.max(0.0, math.min(1.0, (mouse_x - start_x) / (end_x - start_x)))
                        local u = 1.0 - t
                        local y_curve = (u * u * u * start_y) + (3.0 * u * u * t * cp1_y) + (3.0 * u * t * t * cp2_y) + (t * t * t * end_y)
                        if math.abs(mouse_y - y_curve) <= 8.0 * s then
                            is_hit = true
                        end
                    end
                end
                
                if is_hit then
                    state.hovered_tie = tie
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                    reaper.ImGui_SetTooltip(ctx, string.format("Tie: %s\nClick to select | Delete to remove", pitch_to_name(tie.pitch)))
                    if reaper.ImGui_IsMouseClicked(ctx, 0) then
                        state:clear_selection()
                        state.selected_tie = tie
                        state.selected_slur = nil
                    end
                end
                
                local is_sel = (state.selected_tie and state.selected_tie.id == tie.id)
                local col = is_sel and (Constants.COLORS.selection_gold or 0xFFD700FF) or (Constants.COLORS.tie_col or Constants.COLORS.slur_col or 0x1A1A1AFF)
                local thickness = is_sel and (3.2 * s) or (2.0 * s)
                
                local is_ghost = (nd1.is_ghost_voice == true) or (nd2.is_ghost_voice == true)
                if is_ghost and not is_sel then
                    local alpha = math.floor((state.ghost_voice_opacity or 0.25) * 255)
                    col = (col & 0xFFFFFF00) | alpha
                end
                
                Engraver.draw_tie(draw_list, nd1.nx, nd1.ny, nd2.nx, nd2.ny, s, col, above, thickness)
            end
        end
    end
end

-- ------------------------------------------------------------------------------
-- Persistence (ProjExtState + Type 15 Events)
-- ------------------------------------------------------------------------------

function SlurService.load_slurs(state)
    state.user_slurs = {}
    state.user_ties = {}
    local known_slurs = {}
    local known_ties = {}
    
    -- 1. Load from ProjExtState
    local _, raw_slurs = reaper.GetProjExtState(0, "REAPER_Notator", "user_slurs")
    if raw_slurs and raw_slurs ~= "" then
        for entry in raw_slurs:gmatch("([^;]+)") do
            local p = {}
            for field in (entry .. "|"):gmatch("([^|]*)|") do table.insert(p, field) end
            if p[1] and p[1] ~= "" then
                table.insert(state.user_slurs, {
                    id          = p[1],
                    track_guid  = p[2] or "",
                    chan        = tonumber(p[3]) or 0,
                    pitch1      = tonumber(p[4]) or 60,
                    pitch2      = tonumber(p[5]) or 62,
                    start_qn    = tonumber(p[6]) or 0.0,
                    n2_start_qn = tonumber(p[7]) or 1.0,
                    end_qn      = (tonumber(p[7]) or 1.0) + 1.0,
                    orig_dur1   = tonumber(p[8]) or 1.0,
                    pre_slur_pc = (p[9] and p[9] ~= "") and tonumber(p[9]) or nil,
                    pre_slur_msb = tonumber(p[10]) or -1,
                    pre_slur_lsb = tonumber(p[11]) or -1,
                    n1_key      = string.format("%d_%.4f_%d", tonumber(p[4]) or 60, tonumber(p[6]) or 0.0, tonumber(p[3]) or 0),
                    n2_key      = string.format("%d_%.4f_%d", tonumber(p[5]) or 62, tonumber(p[7]) or 1.0, tonumber(p[3]) or 0)
                })
                known_slurs[p[1]] = true
            end
        end
    end
    
    local _, raw_ties = reaper.GetProjExtState(0, "REAPER_Notator", "user_ties")
    if raw_ties and raw_ties ~= "" then
        for entry in raw_ties:gmatch("([^;]+)") do
            local p = {}
            for field in (entry .. "|"):gmatch("([^|]*)|") do table.insert(p, field) end
            if p[1] and p[1] ~= "" then
                table.insert(state.user_ties, {
                    id          = p[1],
                    track_guid  = p[2] or "",
                    chan        = tonumber(p[3]) or 0,
                    pitch       = tonumber(p[4]) or 60,
                    n1_start_qn = tonumber(p[5]) or 0.0,
                    n1_dur      = tonumber(p[6]) or 1.0,
                    n2_start_qn = tonumber(p[7]) or 1.0,
                    n2_dur      = tonumber(p[8]) or 1.0,
                    n2_vel      = tonumber(p[9]) or 96,
                    n1_key      = string.format("%d_%.4f_%d", tonumber(p[4]) or 60, tonumber(p[5]) or 0.0, tonumber(p[3]) or 0),
                    n2_key      = string.format("%d_%.4f_%d", tonumber(p[4]) or 60, tonumber(p[7]) or 1.0, tonumber(p[3]) or 0)
                })
                known_ties[p[1]] = true
            end
        end
    end
    
    -- 2. Dual persistence: scan takes for Type 15 NOTATOR_SLUR / NOTATOR_TIE
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                    for text_i = 0, text_cnt - 1 do
                        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
                        if ok and ev_type == 15 then
                            local s_id, s_chan, p1, p2, sqn, n2sqn, odur, pre_pc, pre_msb, pre_lsb = msg:match("^NOTATOR_SLUR%s+([%w_]+)%s+(%d+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*(%-?%d*)%s*(%-?%d*)%s*(%-?%d*)")
                            if s_id and not known_slurs[s_id] then
                                known_slurs[s_id] = true
                                table.insert(state.user_slurs, {
                                    id          = s_id,
                                    track_guid  = trk_guid,
                                    chan        = tonumber(s_chan) or 0,
                                    pitch1      = tonumber(p1) or 60,
                                    pitch2      = tonumber(p2) or 62,
                                    start_qn    = tonumber(sqn) or 0.0,
                                    n2_start_qn = tonumber(n2sqn) or 1.0,
                                    end_qn      = (tonumber(n2sqn) or 1.0) + 1.0,
                                    orig_dur1   = tonumber(odur) or 1.0,
                                    pre_slur_pc = (pre_pc and pre_pc ~= "") and tonumber(pre_pc) or nil,
                                    pre_slur_msb = tonumber(pre_msb) or -1,
                                    pre_slur_lsb = tonumber(pre_lsb) or -1,
                                    n1_key      = string.format("%d_%.4f_%d", tonumber(p1) or 60, tonumber(sqn) or 0.0, tonumber(s_chan) or 0),
                                    n2_key      = string.format("%d_%.4f_%d", tonumber(p2) or 62, tonumber(n2sqn) or 1.0, tonumber(s_chan) or 0)
                                })
                            elseif s_id and known_slurs[s_id] then
                                -- Restore missing track_guid from take's track if missing
                                for _, es in ipairs(state.user_slurs) do
                                    if es.id == s_id and (not es.track_guid or es.track_guid == "") then
                                        es.track_guid = trk_guid
                                        break
                                    end
                                end
                            end
                            local t_id, t_chan, tp, t_s1, t_d1, t_s2, t_d2, t_vel = msg:match("^NOTATOR_TIE%s+([%w_]+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*(%d*)")
                            if t_id and not known_ties[t_id] then
                                known_ties[t_id] = true
                                table.insert(state.user_ties, {
                                    id          = t_id,
                                    track_guid  = trk_guid,
                                    chan        = tonumber(t_chan) or 0,
                                    pitch       = tonumber(tp) or 60,
                                    n1_start_qn = tonumber(t_s1) or 0.0,
                                    n1_dur      = tonumber(t_d1) or 1.0,
                                    n2_start_qn = tonumber(t_s2) or 1.0,
                                    n2_dur      = tonumber(t_d2) or 1.0,
                                    n2_vel      = (t_vel and t_vel ~= "") and tonumber(t_vel) or 96,
                                    n1_key      = string.format("%d_%.4f_%d", tonumber(tp) or 60, tonumber(t_s1) or 0.0, tonumber(t_chan) or 0),
                                    n2_key      = string.format("%d_%.4f_%d", tonumber(tp) or 60, tonumber(t_s2) or 1.0, tonumber(t_chan) or 0)
                                })
                            elseif t_id and known_ties[t_id] then
                                -- Restore missing track_guid from take's track if missing
                                for _, et in ipairs(state.user_ties) do
                                    if et.id == t_id and (not et.track_guid or et.track_guid == "") then
                                        et.track_guid = trk_guid
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function SlurService.heal_slurs_and_ties(state)
    if not state then return end
    state.user_slurs = state.user_slurs or {}
    state.user_ties = state.user_ties or {}
    
    local valid_guids = {}
    local trk_cnt = reaper.CountTracks(0)
    for ti = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local g = reaper.GetTrackGUID(trk)
            if g then valid_guids[normalize_guid(g)] = true end
        end
    end
    
    local clean_slurs = {}
    for _, sl in ipairs(state.user_slurs) do
        local keep = true
        if sl.track_guid and sl.track_guid ~= "" then
            if not valid_guids[normalize_guid(sl.track_guid)] then
                keep = false -- Track no longer exists in project
            end
        end
        if keep then table.insert(clean_slurs, sl) end
    end
    state.user_slurs = clean_slurs
    
    local clean_ties = {}
    for _, tie in ipairs(state.user_ties) do
        local keep = true
        if tie.track_guid and tie.track_guid ~= "" then
            if not valid_guids[normalize_guid(tie.track_guid)] then
                keep = false -- Track no longer exists in project
            end
        end
        if keep then table.insert(clean_ties, tie) end
    end
    state.user_ties = clean_ties
    
    SlurService.save_slurs(state)
end

function SlurService.save_slurs(state)
    if not state then return end
    
    local slur_entries = {}
    for _, sl in ipairs(state.user_slurs or {}) do
        table.insert(slur_entries, string.format("%s|%s|%d|%d|%d|%.4f|%.4f|%.4f|%s|%d|%d",
            sl.id or "",
            sl.track_guid or "",
            sl.chan or 0,
            sl.pitch1 or 60,
            sl.pitch2 or 62,
            sl.start_qn or 0.0,
            sl.n2_start_qn or 1.0,
            sl.orig_dur1 or 1.0,
            sl.pre_slur_pc or "",
            sl.pre_slur_msb or -1,
            sl.pre_slur_lsb or -1
        ))
    end
    reaper.SetProjExtState(0, "REAPER_Notator", "user_slurs", table.concat(slur_entries, ";"))
    
    local tie_entries = {}
    for _, tie in ipairs(state.user_ties or {}) do
        table.insert(tie_entries, string.format("%s|%s|%d|%d|%.4f|%.4f|%.4f|%.4f|%d",
            tie.id or "",
            tie.track_guid or "",
            tie.chan or 0,
            tie.pitch or 60,
            tie.n1_start_qn or 0.0,
            tie.n1_dur or 1.0,
            tie.n2_start_qn or 1.0,
            tie.n2_dur or 1.0,
            tie.n2_vel or 96
        ))
    end
    reaper.SetProjExtState(0, "REAPER_Notator", "user_ties", table.concat(tie_entries, ";"))
end

return SlurService

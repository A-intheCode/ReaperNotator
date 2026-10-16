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

local _norm_guid_cache = {}
local function normalize_guid(g)
    if not g or g == "" then return "" end
    local cached = _norm_guid_cache[g]
    if cached then return cached end
    local norm = tostring(g):upper():gsub("[^%w]", "")
    _norm_guid_cache[g] = norm
    return norm
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
                n.track = trk
                return trk
            end
        end
    end
    if n.orig then
        local trk = get_track_from_note(n.orig)
        if trk then n.track = trk end
        return trk
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
            n.item = item
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
        n.track_guid = n.orig.track_guid
        return n.track_guid
    end
    local trk = get_track_from_note(n)
    if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
        local g = reaper.GetTrackGUID(trk)
        if g and g ~= "" then
            n.track_guid = g
            if n.orig then n.orig.track_guid = g end
        end
        return g
    end
    return nil
end

local function notes_share_same_track(n1, n2)
    if not n1 or not n2 then return false end
    -- Fast path: direct MediaTrack userdata equality without C-API ValidatePtr overhead
    local t1 = n1.track or (n1.orig and n1.orig.track)
    local t2 = n2.track or (n2.orig and n2.orig.track)
    if t1 and t2 then
        return t1 == t2
    end
    local g1 = (n1.track_guid and n1.track_guid ~= "" and n1.track_guid) or (n1.orig and n1.orig.track_guid and n1.orig.track_guid ~= "" and n1.orig.track_guid)
    local g2 = (n2.track_guid and n2.track_guid ~= "" and n2.track_guid) or (n2.orig and n2.orig.track_guid and n2.orig.track_guid ~= "" and n2.orig.track_guid)
    if g1 and g2 then
        return normalize_guid(g1) == normalize_guid(g2)
    end
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
SlurService.find_take_note_by_pos = find_take_note_by_pos


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
    local n1_eqn = n1.end_qn or (n1_sqn + (n1.dur_qn or 1.0))
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
                    if dt > 0.005 then
                        -- For ties (require_same_pitch): cand must be immediately contiguous (no intervening rests)!
                        local is_contiguous = not require_same_pitch or (cand_sqn <= n1_eqn + 0.06 and math.abs(cand_sqn - n1_eqn) <= 0.15)
                        if is_contiguous then
                            local chan_match = ((cand.chan or 0) == n1_chan) or require_same_pitch
                            if chan_match and (not require_same_pitch or cand.pitch == n1.pitch) then
                                if dt < min_dt then
                                    min_dt = dt
                                    best_note = cand
                                elseif math.abs(dt - min_dt) < 0.005 and best_note then
                                    -- In chord: pick note with matching channel or closest pitch
                                    if (cand.chan or 0) == n1_chan and (best_note.chan or 0) ~= n1_chan then
                                        best_note = cand
                                    elseif math.abs(cand.pitch - n1.pitch) < math.abs(best_note.pitch - n1.pitch) then
                                        best_note = cand
                                    end
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
        local item = n1.item or (reaper.GetMediaItemTake_Item and reaper.GetMediaItemTake_Item(take))
        local MidiNote = package.loaded["classes.note"] or require("classes.note")
        local _, notecnt = reaper.MIDI_CountEvts(take)
        for i = 0, notecnt - 1 do
            local ok, _, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
            if ok and not muted then
                local cand_sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                local cand_eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                local dt = cand_sqn - n1_sqn
                if dt > 0.005 then
                    local is_contiguous = not require_same_pitch or (cand_sqn <= n1_eqn + 0.06 and math.abs(cand_sqn - n1_eqn) <= 0.15)
                    if is_contiguous then
                        local chan_match = (chan == n1_chan) or require_same_pitch
                        if chan_match and (not require_same_pitch or pitch == n1.pitch) then
                            if dt < min_dt then
                                min_dt = dt
                                best_note = MidiNote.new({
                                    idx = i,
                                    take = take,
                                    item = item,
                                    track = n1.track,
                                    chan = chan,
                                    pitch = pitch,
                                    vel = vel,
                                    start_qn = cand_sqn,
                                    end_qn = cand_eqn,
                                    dur_qn = cand_eqn - cand_sqn
                                })
                            end
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
    local eff_tracks_data = active_tracks_data or state.active_tracks_cache
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
        n_last = find_next_chronological_note(n1, eff_tracks_data, false)
        if not n_last then
            state.status_msg = "⚠️ No subsequent note found to slur to on this track/voice."
            return
        end
        table.insert(phrase_notes, n1)
        table.insert(phrase_notes, n_last)
    end
    
    -- Expand to all intermediate notes between n1 and n_last on the same voice/channel strictly within this track!
    if eff_tracks_data and #targets >= 2 and n_last.start_qn - n1.start_qn > 0.005 then
        local all_cands = {}
        local n1_guid = get_track_guid_from_note(n1)
        local n1_trk = get_track_from_note(n1)
        for _, td in ipairs(eff_tracks_data) do
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
        SlurService.delete_slur(state, sl, MidiService, eff_tracks_data)
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
    local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, all_banks, state)
    if trk and bank and ReaticulateParser and ReaticulateParser.ensure_track_reaticulate_fx_and_bank then
        ReaticulateParser.ensure_track_reaticulate_fx_and_bank(trk, bank, state, false)
    end
    
    local n1_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n1.start_qn) + 0.5)
    local n_last_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n_last.start_qn) + 0.5)
    
    local function is_pc_momentary(pc_val)
        if not bank or not bank.articulations or not pc_val then return false end
        for _, ba in ipairs(bank.articulations) do
            if ba.pc == pc_val then
                return MidiService.is_momentary_articulation(ba.name)
            end
        end
        return false
    end

    -- 1. Scan for active sustained pre-slur articulation on this channel (e.g. Tremolo / Trill, excluding momentary / chase PCs)
    local chase_ppq_map = {}
    local _, _, cur_cc_cnt, cur_t_cnt = reaper.MIDI_CountEvts(take)
    for ti = 0, (cur_t_cnt or 0) - 1 do
        local ok_t, _, _, t_ppq, etype, msg_t = reaper.MIDI_GetTextSysexEvt(take, ti)
        if ok_t and etype == 15 then
            local ch_c, pc_c = msg_t:match("NOTATOR_CHASE%s+(%d+)%s+(%-?%d+)")
            if ch_c and tonumber(ch_c) == chan and pc_c then
                table.insert(chase_ppq_map, { ppq = t_ppq, pc = tonumber(pc_c) })
            end
        end
    end

    local pre_slur_pc = nil
    local pre_slur_msb = -1
    local pre_slur_lsb = -1
    local latest_pc_ppq = -1
    local cur_msb = -1
    local cur_lsb = -1
    for ci = 0, cur_cc_cnt - 1 do
        local ok, _, _, ppq, chanmsg, cchan, msg2, msg3 = reaper.MIDI_GetCC(take, ci)
        if ok and cchan == chan and ppq < n1_sppq - 10 then
            if (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and msg2 == 0 then
                cur_msb = msg3
            elseif (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and msg2 == 32 then
                cur_lsb = msg3
            elseif (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0) then
                local is_ch = false
                for _, ce in ipairs(chase_ppq_map) do
                    if math.abs(ce.ppq - ppq) <= 15 and ce.pc == msg2 then
                        is_ch = true
                        break
                    end
                end
                if not is_ch and not is_pc_momentary(msg2) and ppq > latest_pc_ppq then
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
    
    -- 3. Insert Slur articulation using track behavior priority (Auto: Legato -> Long / Sustain, or explicit selection)
    local art_match = bank and MidiService.find_slur_articulation_in_bank(bank, trk, state)
    
    if art_match then
        -- Remove any conflicting PCs / Bank Selects or NOTATOR_CHASE tags across the slurred phrase [n1_sppq - 25, n_last_sppq + 15]
        local _, _, cc_del_cnt, text_del_cnt = reaper.MIDI_CountEvts(take)
        for ci = (cc_del_cnt or 0) - 1, 0, -1 do
            local ok_c, _, _, c_ppq, chanmsg, c_chan, msg2 = reaper.MIDI_GetCC(take, ci)
            if ok_c and c_chan == chan and c_ppq >= n1_sppq - 25 and c_ppq <= n_last_sppq + 15 then
                local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                if is_pc or is_bank then
                    reaper.MIDI_DeleteCC(take, ci)
                end
            end
        end
        for ti = (text_del_cnt or 0) - 1, 0, -1 do
            local ok_t, _, _, t_ppq, etype, msg_t = reaper.MIDI_GetTextSysexEvt(take, ti)
            if ok_t and t_ppq >= n1_sppq - 25 and t_ppq <= n_last_sppq + 15 and msg_t and msg_t:find("NOTATOR_CHASE") then
                reaper.MIDI_DeleteTextSysexEvt(take, ti)
            end
        end
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
    
    -- 4. Tag all notes in phrase with Type 15 articulation tag and clean conflicting short/momentary tags
    local slur_art_tag = (art_match and art_match.name and not art_match.name:lower():find("legato") and not art_match.name:lower():find("portato") and not art_match.name:lower():find("gliss") and not art_match.name:lower():find("portamento")) and "long" or "legato"
    for _, pn in ipairs(phrase_notes) do
        local pn_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, pn.start_qn) + 0.5)
        local _, _, _, textcnt = reaper.MIDI_CountEvts(take)
        for ti = (textcnt or 0) - 1, 0, -1 do
            local ok_t, _, _, t_ppq, etype, msg_t = reaper.MIDI_GetTextSysexEvt(take, ti)
            if ok_t and etype == 15 and math.abs(t_ppq - pn_sppq) <= 25 then
                local p_m, ch_m = msg_t:match("^NOTE%s+(%d+)%s+(%d+)%s+a%s+")
                if p_m and tonumber(p_m) == pn.pitch and (tonumber(ch_m) or 0) == chan then
                    reaper.MIDI_DeleteTextSysexEvt(take, ti)
                end
            end
        end
        reaper.MIDI_InsertTextSysexEvt(take, false, false, pn_sppq, 15, string.format("NOTE %d %d a %s", pn.pitch, chan, slur_art_tag))
        pn.articulation = slur_art_tag
    end
    
    -- 5. Insert Type 15 Slur persistence tag with pre_slur articulation memory (numeric -1 fallback so pattern matching never shifts columns)
    reaper.MIDI_InsertTextSysexEvt(take, false, false, n1_sppq, 15, string.format("NOTATOR_SLUR %s %d %d %d %.4f %.4f %.4f %d %d %d",
        slur_id, chan, n1.pitch, n_last.pitch, n1.start_qn, n_last.start_qn, orig_dur1,
        tonumber(pre_slur_pc) or -1, tonumber(pre_slur_msb) or -1, tonumber(pre_slur_lsb) or -1))
    
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

    -- Auto-advance selection focus to the arrival note (n_last)
    if n_last then
        state:clear_selection()
        state:select_note(n_last)
        if MidiService and MidiService.sync_selection_to_reaper then
            MidiService.sync_selection_to_reaper(state, eff_tracks_data)
        end
    end

    local art_label = (art_match and art_match.name) or "Legato"
    state.status_msg = string.format("Slur created [S] (%s %s -> %s, %d notes)", art_label, pitch_to_name(n1.pitch), pitch_to_name(n_last.pitch), #phrase_notes)
end

-- ------------------------------------------------------------------------------
-- Tie Management (Haltebögen)
-- ------------------------------------------------------------------------------

function SlurService.toggle_tie(state, active_tracks_data)
    local eff_tracks_data = active_tracks_data or state.active_tracks_cache
    local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
    state.user_ties = state.user_ties or {}
    
    -- Priority 1: Direct tie curve selection -> untie immediately
    if state.selected_tie then
        local tie = state.selected_tie
        SlurService.delete_tie(state, tie, MidiService, eff_tracks_data)
        state.selected_tie = nil
        return
    end

    local targets = get_target_notes(state)
    if #targets == 0 then
        state.status_msg = "Select 1 note (to tie to next of same pitch) or 2+ notes to tie."
        return
    end
    
    -- Strict Cross-Track & Same-Pitch Validation for multi-selection
    if #targets >= 2 then
        for i = 2, #targets do
            if not notes_share_same_track(targets[1], targets[i]) then
                state.status_msg = "⚠️ Ties can only connect notes within the same instrument."
                return
            end
            if targets[i].pitch ~= targets[1].pitch then
                state.status_msg = "⚠️ Tie requires notes of the same pitch! Use Slur [S] for melodic phrases."
                return
            end
            local prev_eqn = targets[i - 1].end_qn or ((targets[i - 1].start_qn or 0) + (targets[i - 1].dur_qn or 1.0))
            local cur_sqn = targets[i].start_qn or 0
            if cur_sqn > prev_eqn + 0.06 or (cur_sqn - prev_eqn) < -0.06 then
                state.status_msg = "⚠️ Ties can only connect immediately adjacent notes without intervening rests."
                return
            end
        end
    end
    
    -- Elaine Gould Adjacency Rule (Behind Bars p. 60):
    -- Build complete adjacent chain (expand any unselected intermediate notes on same track/voice)
    local chain_notes = {}
    if #targets >= 2 then
        local min_sqn = targets[1].start_qn or 0
        local max_sqn = targets[#targets].start_qn or 0
        local p = targets[1].pitch
        local ch = targets[1].chan or 0
        local trk_g = get_track_guid_from_note(targets[1])
        local trk = get_track_from_note(targets[1])
        
        local all_cands = {}
        if eff_tracks_data then
            for _, td in ipairs(eff_tracks_data) do
                local is_match = false
                if trk and td.track and td.track == trk then is_match = true
                elseif trk_g and td.guid and normalize_guid(td.guid) == normalize_guid(trk_g) then is_match = true
                end
                if is_match and td.notes then
                    for _, cand in ipairs(td.notes) do
                        if cand.pitch == p and (cand.chan or 0) == ch then
                            local c_sqn = cand.start_qn or 0
                            if c_sqn >= min_sqn - 0.01 and c_sqn <= max_sqn + 0.01 then
                                table.insert(all_cands, cand)
                            end
                        end
                    end
                end
            end
        end
        
        if #all_cands > #targets then
            table.sort(all_cands, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
            local last_s = -999
            for _, c in ipairs(all_cands) do
                if math.abs((c.start_qn or 0) - last_s) > 0.01 then
                    table.insert(chain_notes, c)
                    last_s = c.start_qn or 0
                end
            end
        else
            chain_notes = targets
        end
    else
        table.insert(chain_notes, targets[1])
    end
    
    -- Check if selected notes should trigger UNTIE:
    local ties_to_untie = {}
    if #chain_notes >= 2 then
        for i = 1, #chain_notes - 1 do
            local tn1, tn2 = chain_notes[i], chain_notes[i + 1]
            local k1 = tn1.key or (tn1.get_key and tn1:get_key())
            local k2 = tn2.key or (tn2.get_key and tn2:get_key())
            for idx, tie in ipairs(state.user_ties) do
                local key_match = (k1 and k2 and tie.n1_key == k1 and tie.n2_key == k2)
                local pos_match = (tie.pitch == tn1.pitch
                    and (tie.chan or 0) == (tn1.chan or 0) and (tie.chan or 0) == (tn2.chan or 0)
                    and math.abs(tie.n1_start_qn - (tn1.start_qn or 0)) < 0.10
                    and math.abs(tie.n2_start_qn - (tn2.start_qn or 0)) < 0.10)
                if key_match or pos_match then
                    table.insert(ties_to_untie, tie)
                    break
                end
            end
        end
    else
        -- 1 note: ONLY untie if the selected note is the origin/head (n1) of an existing tie!
        local tn = chain_notes[1]
        local tn_k = tn.key or (tn.get_key and tn:get_key())
        for idx, tie in ipairs(state.user_ties) do
            local match_key = (tn_k and tie.n1_key == tn_k)
            local match_pos1 = (tie.pitch == tn.pitch and (tie.chan or 0) == (tn.chan or 0) and math.abs(tie.n1_start_qn - (tn.start_qn or 0)) < 0.10)
            if match_key or match_pos1 then
                table.insert(ties_to_untie, tie)
                break
            end
        end
    end
    
    if #ties_to_untie > 0 then
        -- UNTIE / TOGGLE OFF
        for _, tie in ipairs(ties_to_untie) do
            SlurService.delete_tie(state, tie, MidiService, eff_tracks_data)
        end
        return
    end
    
    -- TIE CREATION: Connect adjacent notes
    if #chain_notes == 1 then
        local n2 = find_next_chronological_note(chain_notes[1], eff_tracks_data, true)
        if not n2 then
            state.status_msg = "⚠️ No subsequent note with the same pitch found to tie."
            return
        end
        table.insert(chain_notes, n2)
    end
    
    local take = chain_notes[1].take or (chain_notes[2] and chain_notes[2].take) or MidiService.get_active_midi_take()
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        state.status_msg = "⚠️ Active MIDI take not found."
        return
    end
    
    reaper.Undo_BeginBlock2(0)
    reaper.MIDI_DisableSort(take)
    
    local base_time_str = tostring(reaper.time_precise()):gsub("%.", "")
    for i = 1, #chain_notes - 1 do
        local n1 = chain_notes[i]
        local n2 = chain_notes[i + 1]
        local tie_id = "tie_" .. base_time_str .. "_" .. tostring(i)
        
        local n1_k = n1.key or (n1.get_key and n1:get_key()) or string.format("%d_%.4f_%d", n1.pitch, n1.start_qn, n1.chan or 0)
        local n2_k = n2.key or (n2.get_key and n2:get_key()) or string.format("%d_%.4f_%d", n2.pitch, n2.start_qn, n2.chan or 0)
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
        if not n1_idx then
            local target_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n1.start_qn) + 0.5)
            local _, notecnt = reaper.MIDI_CountEvts(take)
            for ni = 0, notecnt - 1 do
                local ok, sel, muted, sppq, eppq, ch, p, vel = reaper.MIDI_GetNote(take, ni)
                if ok and p == n1.pitch and (n1.chan == nil or ch == (n1.chan or 0)) then
                    if sppq <= target_ppq + 50 and eppq >= target_ppq - 50 then
                        n1_idx = ni
                        n1_data = { sel = sel, muted = muted, sppq = sppq, eppq = eppq, chan = ch, pitch = p, vel = vel }
                        break
                    end
                end
            end
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
        
        local n1_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n1.start_qn) + 0.5)
        local n2_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n2.start_qn) + 0.5)
        local n2_eppq = n2_data and n2_data.eppq or math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n2.end_qn or (n2.start_qn + n2_dur)) + 0.5)
        
        -- 1. Safely delete Note 2 from the MIDI take so audio playback never re-strikes
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

    -- Auto-advance selection focus to the arrival note of the chain
    local last_n = chain_notes[#chain_notes]
    if last_n then
        state:clear_selection()
        state:select_note(last_n)
        if MidiService and MidiService.sync_selection_to_reaper then
            MidiService.sync_selection_to_reaper(state, eff_tracks_data)
        end
    end

    state.status_msg = string.format("Tied notes [T] (%s, %d notes chained, visual separate notes preserved, held audio)", pitch_to_name(chain_notes[1].pitch), #chain_notes)
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
        if not n1_idx then
            local target_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, tie.n1_start_qn) + 0.5)
            local _, notecnt = reaper.MIDI_CountEvts(take)
            for i = 0, notecnt - 1 do
                local ok, sel, muted, sppq, eppq, ch, p, vel = reaper.MIDI_GetNote(take, i)
                if ok and p == tie.pitch and (tie.chan == nil or ch == (tie.chan or 0)) then
                    if sppq <= target_ppq + 50 and eppq >= target_ppq - 50 then
                        n1_idx = i
                        n1_data = { sel = sel, muted = muted, sppq = sppq, eppq = eppq, chan = ch, pitch = p, vel = vel }
                        break
                    end
                end
            end
        end
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

local _last_render_map = nil
local _last_render_index = nil

local function get_note_render_index(all_note_render_by_key)
    if not all_note_render_by_key then return nil end
    if _last_render_map == all_note_render_by_key and _last_render_index then
        return _last_render_index
    end
    local by_pitch = {}
    local min_qn = 99999999
    local max_qn = -99999999
    local has_notes = false
    for _, nd in pairs(all_note_render_by_key) do
        if type(nd) == "table" and nd.pitch then
            has_notes = true
            local p = nd.pitch
            local list = by_pitch[p]
            if not list then
                list = {}
                by_pitch[p] = list
            end
            list[#list + 1] = nd
            local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
            local eqn = nd.end_qn or (nd.orig and nd.orig.end_qn) or (sqn + (nd.dur_qn or 1.0))
            if sqn < min_qn then min_qn = sqn end
            if eqn > max_qn then max_qn = eqn end
        end
    end
    _last_render_map = all_note_render_by_key
    _last_render_index = {
        by_pitch = by_pitch,
        min_qn = has_notes and min_qn or 0,
        max_qn = has_notes and max_qn or 0,
        has_notes = has_notes,
        resolved_ties = {},
        resolved_slurs = {}
    }
    return _last_render_index
end

local function resolve_effective_slur_notes(state, sl, all_note_render_by_key)
    if not sl or not all_note_render_by_key then return nil, nil end

    local r_idx = get_note_render_index(all_note_render_by_key)
    if not r_idx or not r_idx.has_notes then return nil, nil end

    local cached = r_idx.resolved_slurs[sl]
    if cached then
        return cached[1] or nil, cached[2] or nil
    end

    local s1_qn = sl.start_qn or 0
    local target_n2_qn = sl.n2_start_qn or sl.end_qn or (s1_qn + 1.0)
    if math.max(s1_qn, target_n2_qn) < (r_idx.min_qn - 24.0) or math.min(s1_qn, target_n2_qn) > (r_idx.max_qn + 24.0) then
        r_idx.resolved_slurs[sl] = { false, false }
        return nil, nil
    end

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

    -- Fallback by pitch and start_qn if key was re-keyed, scoped to pitch buckets
    if not nd1 or not nd2 then
        local best_d1 = 999999
        local best_d2 = 999999
        local eff_chan1 = sl.n1_chan or sl.chan
        local eff_chan2 = sl.n2_chan or sl.chan
        local p1_list = r_idx.by_pitch[sl.pitch1]
        local p2_list = r_idx.by_pitch[sl.pitch2]

        -- Pass 1: Try channel affinity within matching pitch buckets
        if not nd1 and p1_list then
            for _, nd in ipairs(p1_list) do
                if note_matches_slur_track(nd) then
                    local nd_ch = nd.chan or (nd.orig and nd.orig.chan) or 0
                    if eff_chan1 == nil or nd_ch == eff_chan1 then
                        local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                        local d = math.abs(sqn - s1_qn)
                        if d <= 0.12 and d < best_d1 then
                            best_d1 = d
                            nd1 = nd
                        end
                    end
                end
            end
        end
        if not nd2 and p2_list then
            for _, nd in ipairs(p2_list) do
                if note_matches_slur_track(nd) then
                    local nd_ch = nd.chan or (nd.orig and nd.orig.chan) or 0
                    if eff_chan2 == nil or nd_ch == eff_chan2 then
                        local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                        local d = math.abs(sqn - target_n2_qn)
                        if d <= 0.12 and d < best_d2 then
                            best_d2 = d
                            nd2 = nd
                        end
                    end
                end
            end
        end

        -- Pass 2: Fallback across any channel on the same track (essential for grand staff & multi-voice)
        if not nd1 and p1_list then
            for _, nd in ipairs(p1_list) do
                if note_matches_slur_track(nd) then
                    local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                    local d = math.abs(sqn - s1_qn)
                    if d <= 0.12 and d < best_d1 then
                        best_d1 = d
                        nd1 = nd
                    end
                end
            end
        end
        if not nd2 and p2_list then
            for _, nd in ipairs(p2_list) do
                if note_matches_slur_track(nd) then
                    local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                    local d = math.abs(sqn - target_n2_qn)
                    if d <= 0.12 and d < best_d2 then
                        best_d2 = d
                        nd2 = nd
                    end
                end
            end
        end
    end

    if not nd1 or not nd2 then
        r_idx.resolved_slurs[sl] = { false, false }
        return nil, nil
    end

    -- If sl.track_guid was missing (legacy), inherit and persist from matched note
    if (not sl.track_guid or sl.track_guid == "") and nd1 then
        sl.track_guid = get_track_guid_from_note(nd1) or ""
    end

    -- STRICT GUARD: Notes MUST share same track!
    if not notes_share_same_track(nd1, nd2) then
        r_idx.resolved_slurs[sl] = { false, false }
        return nil, nil
    end

    local base_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or sl.start_qn or 0

    -- Segment arrival handling (Elaine Gould standard):
    -- If nd2 has multiple barline segments or is tied, ensure the slur lands on the FIRST segment
    if nd2.orig and nd2.is_segment then
        local first_seg = nd2
        local first_sqn = nd2.start_qn or 999999
        local seg_candidates = r_idx.by_pitch[nd2.pitch]
        if seg_candidates then
            for _, nd in ipairs(seg_candidates) do
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
        end
        nd2 = first_seg
    end

    r_idx.resolved_slurs[sl] = { nd1, nd2 }
    return nd1, nd2
end

local function resolve_effective_tie_notes(state, tie, all_note_render_by_key)
    if not tie or not all_note_render_by_key then return nil, nil end

    local r_idx = get_note_render_index(all_note_render_by_key)
    if not r_idx or not r_idx.has_notes then return nil, nil end

    local cached = r_idx.resolved_ties[tie]
    if cached then
        return cached[1] or nil, cached[2] or nil
    end

    local t_s1 = tie.n1_start_qn or 0.0
    local t_s2 = tie.n2_start_qn or (t_s1 + 1.0)
    if math.max(t_s1, t_s2) < (r_idx.min_qn - 16.0) or math.min(t_s1, t_s2) > (r_idx.max_qn + 16.0) then
        r_idx.resolved_ties[tie] = { false, false }
        return nil, nil
    end

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

    -- Fallback by pitch and start_qn if key was re-keyed, strictly scoped to matching pitch bucket & track
    if not nd1 or not nd2 then
        local pitch_notes = r_idx.by_pitch[tie.pitch]
        if pitch_notes then
            local best_d1 = 999999
            local best_d2 = 999999
            -- Pass 1: Try channel affinity
            for _, nd in ipairs(pitch_notes) do
                if note_matches_tie_track(nd) then
                    local nd_ch = nd.chan or (nd.orig and nd.orig.chan) or 0
                    local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                    if not nd1 and (tie.chan == nil or nd_ch == tie.chan) then
                        local d = math.abs(sqn - t_s1)
                        if d <= 0.12 and d < best_d1 then
                            best_d1 = d
                            nd1 = nd
                        end
                    end
                    if not nd2 and (tie.chan == nil or nd_ch == tie.chan) then
                        local d = math.abs(sqn - t_s2)
                        local eqn = nd.end_qn or (nd.orig and nd.orig.end_qn) or (sqn + (nd.dur_qn or 1.0))
                        local in_span = (sqn <= t_s2 + 0.05) and (eqn >= t_s2 - 0.05)
                        if (d <= 0.12 or in_span) and d < best_d2 then
                            best_d2 = d
                            nd2 = nd
                        end
                    end
                end
            end
            -- Pass 2: Fallback across any channel on the same track
            if not nd1 or not nd2 then
                for _, nd in ipairs(pitch_notes) do
                    if note_matches_tie_track(nd) then
                        local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                        if not nd1 then
                            local d = math.abs(sqn - t_s1)
                            if d <= 0.12 and d < best_d1 then
                                best_d1 = d
                                nd1 = nd
                            end
                        end
                        if not nd2 then
                            local d = math.abs(sqn - t_s2)
                            local eqn = nd.end_qn or (nd.orig and nd.orig.end_qn) or (sqn + (nd.dur_qn or 1.0))
                            local in_span = (sqn <= t_s2 + 0.05) and (eqn >= t_s2 - 0.05)
                            if (d <= 0.12 or in_span) and d < best_d2 then
                                best_d2 = d
                                nd2 = nd
                            end
                        end
                    end
                end
            end
        end
    end

    if not nd1 or not nd2 then
        r_idx.resolved_ties[tie] = { false, false }
        return nil, nil
    end

    -- STRICT GUARD: Notes MUST share same track and same pitch!
    if not notes_share_same_track(nd1, nd2) then
        r_idx.resolved_ties[tie] = { false, false }
        return nil, nil
    end
    if nd1.pitch ~= nd2.pitch then
        r_idx.resolved_ties[tie] = { false, false }
        return nil, nil
    end

    -- If tie.track_guid was missing (legacy), inherit from note only after verifying both notes share the same track
    if (not tie.track_guid or tie.track_guid == "") and nd1 then
        tie.track_guid = get_track_guid_from_note(nd1) or ""
    end

    local pitch_candidates = r_idx.by_pitch[nd1.pitch]

    -- If nd1 is segmented (e.g. cross-barline or metric pulse splits), resolve to its LAST segment before nd2
    local target_s2 = nd2.start_qn or (nd2.orig and nd2.orig.start_qn) or tie.n2_start_qn or 999999
    if nd1.orig and nd1.is_segment and pitch_candidates then
        local last_seg = nd1
        local last_sqn = nd1.start_qn or -999999
        for _, nd in ipairs(pitch_candidates) do
            if notes_share_same_track(nd, nd1) then
                local is_same_note = (nd.orig and nd1.orig and nd.orig == nd1.orig)
                if not is_same_note and nd1.orig and nd.orig and nd1.orig.take and nd.orig.take and nd1.orig.take == nd.orig.take and nd1.orig.idx and nd.orig.idx and nd1.orig.idx >= 0 and nd.orig.idx >= 0 and nd1.orig.idx == nd.orig.idx then
                    is_same_note = true
                end
                if is_same_note and nd.is_segment then
                    local sqn = nd.start_qn or 0
                    if sqn > last_sqn and sqn < (target_s2 - 0.01) then
                        last_sqn = sqn
                        last_seg = nd
                    end
                end
            end
        end
        nd1 = last_seg
    end

    local base_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or tie.n1_start_qn or 0
    if nd2.orig and nd2.is_segment and pitch_candidates then
        local first_seg = nd2
        local first_sqn = nd2.start_qn or 999999
        for _, nd in ipairs(pitch_candidates) do
            if notes_share_same_track(nd, nd2) then
                local is_same_note = (nd.orig and nd2.orig and nd.orig == nd2.orig)
                if not is_same_note and nd2.orig and nd.orig and nd2.orig.take and nd.orig.take and nd2.orig.take == nd.orig.take and nd2.orig.idx and nd.orig.idx and nd2.orig.idx >= 0 and nd.orig.idx >= 0 and nd2.orig.idx == nd.orig.idx then
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

    r_idx.resolved_ties[tie] = { nd1, nd2 }
    return nd1, nd2
end

function SlurService.is_note_slurred(n, state, trk_guid)
    if not n then return false end
    if n.slur_id or n.slur_to or n.is_slurred then return true end
    if n.articulation == "legato" then return true end
    if not state or not state.user_slurs or #state.user_slurs == 0 then return false end

    -- 1. Frame-level cache check: instant O(1) return for notes checked multiple times in a frame
    local f_cache = state._is_note_slurred_cache
    if f_cache then
        local cached_val = f_cache[n]
        if cached_val ~= nil then return cached_val end
    else
        f_cache = {}
        state._is_note_slurred_cache = f_cache
    end

    -- 2. Fast-lookup index for slurs (rebuilt only when slurs change, not every note/frame)
    local cur_slurs_ver = state._slurs_version or #state.user_slurs
    local s_index = state._slur_fast_index
    if not s_index or s_index.ver ~= cur_slurs_ver or s_index.count ~= #state.user_slurs then
        s_index = {
            ver = cur_slurs_ver,
            count = #state.user_slurs,
            endpoint_keys = {},
            spans_by_track = {}
        }
        for _, sl in ipairs(state.user_slurs) do
            local tg = sl.track_guid and normalize_guid(sl.track_guid) or ""
            if sl.n1_key and sl.n1_key ~= "" then s_index.endpoint_keys[sl.n1_key] = true end
            if sl.n2_key and sl.n2_key ~= "" then s_index.endpoint_keys[sl.n2_key] = true end
            if sl.pitch1 and sl.start_qn then
                s_index.endpoint_keys[string.format("%s_%d_%.2f", tg, sl.pitch1, sl.start_qn)] = true
            end
            if sl.pitch2 and (sl.n2_start_qn or sl.start_qn) then
                s_index.endpoint_keys[string.format("%s_%d_%.2f", tg, sl.pitch2, sl.n2_start_qn or sl.start_qn)] = true
            end

            s_index.spans_by_track[tg] = s_index.spans_by_track[tg] or {}
            table.insert(s_index.spans_by_track[tg], {
                start_qn = sl.start_qn or 0.0,
                end_qn   = sl.end_qn or (sl.start_qn and (sl.start_qn + 1.0)) or 1.0,
                chan     = sl.chan
            })
        end
        state._slur_fast_index = s_index
    end

    -- 3. Direct O(1) lookup on slur phrase endpoints
    local n_k = n.key or (n.get_key and n:get_key())
    if n_k and s_index.endpoint_keys[n_k] then
        f_cache[n] = true
        return true
    end

    local t_norm = trk_guid and normalize_guid(trk_guid) or ""
    local p = n.pitch or (n.orig and n.orig.pitch)
    local sqn = n.start_qn or (n.orig and n.orig.start_qn) or 0.0
    if p then
        local approx_k = string.format("%s_%d_%.2f", t_norm, p, sqn)
        if s_index.endpoint_keys[approx_k] then
            f_cache[n] = true
            return true
        end
    end

    -- 4. Intermediate note check strictly scoped to this track's spans (avoids scanning other tracks)
    local track_spans = s_index.spans_by_track[t_norm] or s_index.spans_by_track[""]
    if not track_spans then
        f_cache[n] = false
        return false
    end

    local ch = n.chan or (n.orig and n.orig.chan) or 0
    for _, sp in ipairs(track_spans) do
        if (sp.chan == nil or sp.chan == ch) and sqn >= (sp.start_qn - 0.01) and sqn <= (sp.end_qn + 0.01) then
            f_cache[n] = true
            return true
        end
    end

    f_cache[n] = false
    return false
end

local function has_tie_on_same_side(state, nd1, nd2, slur_above, all_note_render_by_key)
    local min_x = math.min(nd1.nx, nd2.nx) - 2
    local max_x = math.max(nd1.nx, nd2.nx) + 2
    
    -- Check user ties
    if state and state.user_ties then
        for _, tie in ipairs(state.user_ties) do
            local t_nd1, t_nd2 = resolve_effective_tie_notes(state, tie, all_note_render_by_key)
            if t_nd1 and t_nd2 and t_nd1.nx and t_nd2.nx and notes_share_same_track(t_nd1, nd1) then
                local t_min_x = math.min(t_nd1.nx, t_nd2.nx)
                local t_max_x = math.max(t_nd1.nx, t_nd2.nx)
                if t_max_x >= min_x and t_min_x <= max_x then
                    local tie_above = true
                    if t_nd1.stem_down == false and t_nd2.stem_down == false then
                        tie_above = false
                    elseif t_nd1.stem_down == false then
                        tie_above = false
                    end
                    if tie_above == slur_above then
                        return true
                    end
                end
            end
        end
    end
    
    -- Check automatic barline / segmentation ties
    if state and state.active_bar_ties then
        for _, bt in ipairs(state.active_bar_ties) do
            local b_nd1 = all_note_render_by_key and all_note_render_by_key[bt.from_key]
            local b_nd2 = all_note_render_by_key and all_note_render_by_key[bt.to_key]
            if b_nd1 and b_nd2 and b_nd1.nx and b_nd2.nx and notes_share_same_track(b_nd1, nd1) then
                local b_min_x = math.min(b_nd1.nx, b_nd2.nx)
                local b_max_x = math.max(b_nd1.nx, b_nd2.nx)
                if b_max_x >= min_x and b_min_x <= max_x then
                    local tie_above = (b_nd1.stem_down == true) or (b_nd1.dstep and b_nd1.dstep >= 4)
                    if tie_above == slur_above then
                        return true
                    end
                end
            end
        end
    end
    
    -- Also check if nd1 or nd2 is a tied segment of the same note
    if nd1.orig and nd2.orig and nd1.orig == nd2.orig then
        return true
    end
    
    return false
end

function SlurService.draw_slurs(ctx_or_dl, draw_list_or_state, state_or_notes, all_notes_or_s, s_or_cminx, cminx_or_cmaxx, cmaxx_or_cminy, cminy_or_cmaxy, cmaxy_or_hov, opt_hov, opt_mx, opt_my, opt_note_hovered)
    local ctx, draw_list, state, all_note_render_by_key, s, cull_min_x, cull_max_x, cull_min_y, cull_max_y, is_hovered, mouse_x, mouse_y, note_hovered
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
        note_hovered = opt_note_hovered
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
        note_hovered = opt_my
    end

    if not state or not state.user_slurs or #state.user_slurs == 0 then return end
    
    local drawn_slur_pairs = {}
    for _, sl in ipairs(state.user_slurs) do
        local nd1, nd2 = resolve_effective_slur_notes(state, sl, all_note_render_by_key)
        
        if nd1 and nd2 and nd1.nx and nd2.nx then
            local k1 = nd1.key or (nd1.orig and nd1.orig.key) or (nd1.get_key and nd1:get_key()) or tostring(nd1)
            local k2 = nd2.key or (nd2.orig and nd2.orig.key) or (nd2.get_key and nd2:get_key()) or tostring(nd2)
            local pair_key = string.format("%s_%s_%s", normalize_guid(sl.track_guid), k1, k2)
            if not drawn_slur_pairs[pair_key] then
                drawn_slur_pairs[pair_key] = true
            local x_min = math.min(nd1.nx, nd2.nx)
            local x_max = math.max(nd1.nx, nd2.nx)
            local y_min = math.min(nd1.ny, nd2.ny) - 30 * s
            local y_max = math.max(nd1.ny, nd2.ny) + 30 * s
            if x_max >= cull_min_x and x_min <= cull_max_x and (not cull_min_y or (y_max >= cull_min_y and y_min <= cull_max_y)) then
                -- Determine curve direction (Elaine Gould standard)
                -- If both stems up -> curve below (above = false)
                -- If both stems down -> curve above (above = true)
                -- If mixed -> curve above (above = true)
                local above = true
                if nd1.stem_down == false and nd2.stem_down == false then
                    above = false
                end
                
                local has_tie = has_tie_on_same_side(state, nd1, nd2, above, all_note_render_by_key)
                local extra_offset_y = 0
                local extra_arc = 0
                if has_tie then
                    -- Elaine Gould ("Behind Bars" p. 60-63, 110-115):
                    -- Slur must clear and enclose the tie on the outside with at least 1 staff space separation!
                    extra_offset_y = 6.5 * s   -- (base 6.5 * s + 6.5 * s = 13.0 * s, well outside the tie at 3.8 * s)
                    extra_arc = 12.0 * s       -- (deep, wide arch clearing the tie's peak completely)
                end
                
                local dist_x = nd2.nx - nd1.nx
                local dy = nd2.ny - nd1.ny
                local chord_len = math.sqrt(dist_x * dist_x + dy * dy)
                local base_arc_h = math.min(32.0 * s, math.max(10.0 * s, chord_len * 0.15))
                local arc_h = base_arc_h + extra_arc
                local dir = above and -1 or 1
                
                local start_x = nd1.nx + 4.5 * s
                local end_x   = nd2.nx - 4.5 * s
                local base_offset_y = 6.5 * s
                local start_y = nd1.ny + dir * (base_offset_y + extra_offset_y)
                local end_y   = nd2.ny + dir * (base_offset_y + extra_offset_y)
                
                local cp_dist = math.abs(start_x - end_x) * 0.28
                local cp1_x = start_x + cp_dist
                local cp1_y = start_y + dir * arc_h
                local cp2_x = end_x - cp_dist
                local cp2_y = end_y + dir * arc_h
                
                -- Interactive Bezier Hit-testing (strictly prioritizes notehead clicks!)
                local is_hit = false
                local note_is_hovered = note_hovered or (state and state.hovered_note)
                if ctx and is_hovered and mouse_x and mouse_y and end_x > start_x and not note_is_hovered then
                    local d1 = math.sqrt((mouse_x - nd1.nx)^2 + (mouse_y - nd1.ny)^2)
                    local d2 = math.sqrt((mouse_x - nd2.nx)^2 + (mouse_y - nd2.ny)^2)
                    if d1 >= 14.0 * s and d2 >= 14.0 * s then
                        if mouse_x >= start_x and mouse_x <= end_x then
                            local t = (mouse_x - start_x) / (end_x - start_x)
                            if t >= 0.15 and t <= 0.85 then
                                local u = 1.0 - t
                                local y_curve = (u * u * u * start_y) + (3.0 * u * u * t * cp1_y) + (3.0 * u * t * t * cp2_y) + (t * t * t * end_y)
                                if math.abs(mouse_y - y_curve) <= 8.0 * s then
                                    is_hit = true
                                end
                            end
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
                
                Engraver.draw_slur(draw_list, nd1.nx, nd1.ny, nd2.nx, nd2.ny, s, col, above, thickness, extra_offset_y, extra_arc)
            end
        end
    end
    end
end

function SlurService.draw_user_ties(ctx_or_dl, draw_list_or_state, state_or_notes, all_notes_or_s, s_or_cminx, cminx_or_cmaxx, cmaxx_or_cminy, cminy_or_cmaxy, cmaxy_or_hov, opt_hov, opt_mx, opt_my, opt_note_hovered)
    local ctx, draw_list, state, all_note_render_by_key, s, cull_min_x, cull_max_x, cull_min_y, cull_max_y, is_hovered, mouse_x, mouse_y, note_hovered
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
        note_hovered = opt_note_hovered
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
        note_hovered = opt_my
    end

    if not state or not state.user_ties or #state.user_ties == 0 then return end
    
    local r_idx = get_note_render_index(all_note_render_by_key)
    local drawn_tie_pairs = {}
    for _, tie in ipairs(state.user_ties) do
        local nd1, nd2 = resolve_effective_tie_notes(state, tie, all_note_render_by_key)
        
        if nd1 and nd2 and nd1.nx and nd2.nx then
            local k1 = nd1.key or (nd1.orig and nd1.orig.key) or (nd1.get_key and nd1:get_key()) or tostring(nd1)
            local k2 = nd2.key or (nd2.orig and nd2.orig.key) or (nd2.get_key and nd2:get_key()) or tostring(nd2)
            local pair_key = string.format("%s_%s_%s", normalize_guid(tie.track_guid), k1, k2)
            if not drawn_tie_pairs[pair_key] then
                drawn_tie_pairs[pair_key] = true
            local x_min = math.min(nd1.nx, nd2.nx)
            local x_max = math.max(nd1.nx, nd2.nx)
            
            -- Elaine Gould Adjacency Rule (Behind Bars p. 60):
            -- A tie connects ONLY two immediately adjacent notes of the same pitch.
            -- It NEVER connects across an intervening note of the same pitch!
            local has_intermediate_note = false
            local pitch_candidates = r_idx and r_idx.by_pitch[tie.pitch]
            if pitch_candidates then
                local nd1_sqn = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or tie.n1_start_qn or 0
                local nd2_sqn = nd2.start_qn or (nd2.orig and nd2.orig.start_qn) or tie.n2_start_qn or 0
                local min_sqn = math.min(nd1_sqn, nd2_sqn)
                local max_sqn = math.max(nd1_sqn, nd2_sqn)
                for _, cand in ipairs(pitch_candidates) do
                    if cand ~= nd1 and cand ~= nd2 and cand.nx and notes_share_same_track(cand, nd1) then
                        local c_sqn = cand.start_qn or (cand.orig and cand.orig.start_qn) or 0
                        local cx = cand.nx
                        if c_sqn > (min_sqn + 0.05) and c_sqn < (max_sqn - 0.05) and cx > (x_min + 8.0 * s) and cx < (x_max - 8.0 * s) then
                            has_intermediate_note = true
                            break
                        end
                    end
                end
            end
            
            if not has_intermediate_note then
            local y_min = math.min(nd1.ny, nd2.ny) - 30 * s
            local y_max = math.max(nd1.ny, nd2.ny) + 30 * s
            if x_max >= cull_min_x and x_min <= cull_max_x and (not cull_min_y or (y_max >= cull_min_y and y_min <= cull_max_y)) then
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
                local arc_h = math.min(10.0 * s, math.max(4.0 * s, dist * 0.075))
                local dir = above and -1 or 1
                local offset_y = dir * arc_h
                local cp_offset = dist * 0.25
                
                local start_x = nd1.nx + 6.0 * s
                local end_x   = nd2.nx - 6.0 * s
                local start_y = nd1.ny + dir * 3.8 * s
                local end_y   = nd2.ny + dir * 3.8 * s
                local cp1_x = start_x + cp_offset
                local cp1_y = start_y + offset_y
                local cp2_x = end_x - cp_offset
                local cp2_y = end_y + offset_y
                
                -- Interactive Bezier Hit-testing (strictly prioritizes notehead clicks!)
                local is_hit = false
                local note_is_hovered = note_hovered or (state and state.hovered_note)
                if ctx and is_hovered and mouse_x and mouse_y and end_x > start_x and not note_is_hovered then
                    local d1 = math.sqrt((mouse_x - nd1.nx)^2 + (mouse_y - nd1.ny)^2)
                    local d2 = math.sqrt((mouse_x - nd2.nx)^2 + (mouse_y - nd2.ny)^2)
                    if d1 >= 14.0 * s and d2 >= 14.0 * s then
                        if mouse_x >= start_x and mouse_x <= end_x then
                            local t = (mouse_x - start_x) / (end_x - start_x)
                            if t >= 0.15 and t <= 0.85 then
                                local u = 1.0 - t
                                local y_curve = (u * u * u * start_y) + (3.0 * u * u * t * cp1_y) + (3.0 * u * t * t * cp2_y) + (t * t * t * end_y)
                                if math.abs(mouse_y - y_curve) <= 8.0 * s then
                                    is_hit = true
                                end
                            end
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
                
                -- Elaine Gould Tie Deduplication:
                -- Check if all_bar_ties already rendered this exact tie segment
                local trk_id = tostring(nd1.track or (nd1.orig and nd1.orig.track) or "0")
                local x1_r = math.floor(x_min + 0.5)
                local x2_r = math.floor(x_max + 0.5)
                local coord_sig = string.format("%s_%d_%d_%d", trk_id, nd1.pitch or 0, x1_r, x2_r)
                local is_already_drawn = state and state.drawn_tie_signatures and (
                    state.drawn_tie_signatures[coord_sig] or
                    state.drawn_tie_signatures[pair_key] or
                    (k1 and k2 and state.drawn_tie_signatures[k1 .. "->" .. k2])
                )
                
                if is_sel then
                    Engraver.draw_tie(draw_list, nd1.nx, nd1.ny, nd2.nx, nd2.ny, s, col, above, thickness)
                elseif not is_already_drawn then
                    Engraver.draw_tie(draw_list, nd1.nx, nd1.ny, nd2.nx, nd2.ny, s, col, above, thickness)
                end
            end
            end
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
    state._slurs_version = (state._slurs_version or 0) + 1
    state._is_note_slurred_cache = nil
    local known_slurs = {}
    local known_slur_pairs = {}
    local known_ties = {}
    local known_tie_pairs = {}
    local duplicates_pruned = false
    
    -- 1. Load from ProjExtState
    local _, raw_slurs = reaper.GetProjExtState(0, "REAPER_Notator", "user_slurs")
    if raw_slurs and raw_slurs ~= "" then
        for entry in raw_slurs:gmatch("([^;]+)") do
            local p = {}
            for field in (entry .. "|"):gmatch("([^|]*)|") do table.insert(p, field) end
            local sid = p[1]
            if sid and sid ~= "" then
                local trk_g = p[2] or ""
                local norm_tg = normalize_guid(trk_g)
                local ch = tonumber(p[3]) or 0
                local p1 = tonumber(p[4]) or 60
                local p2 = tonumber(p[5]) or 62
                local sqn = tonumber(p[6]) or 0.0
                local n2sqn = tonumber(p[7]) or 1.0
                local n1_k = string.format("%d_%.4f_%d", p1, sqn, ch)
                local n2_k = string.format("%d_%.4f_%d", p2, n2sqn, ch)
                local pair_key = string.format("%s_%s_%s", norm_tg, n1_k, n2_k)

                if known_slurs[sid] or known_slur_pairs[pair_key] then
                    duplicates_pruned = true
                else
                    known_slurs[sid] = true
                    known_slurs[sid .. "_" .. norm_tg] = true
                    known_slur_pairs[pair_key] = true
                    table.insert(state.user_slurs, {
                        id          = sid,
                        track_guid  = trk_g,
                        chan        = ch,
                        pitch1      = p1,
                        pitch2      = p2,
                        start_qn    = sqn,
                        n2_start_qn = n2sqn,
                        end_qn      = n2sqn + 1.0,
                        orig_dur1   = tonumber(p[8]) or 1.0,
                        pre_slur_pc = (p[9] and p[9] ~= "" and tonumber(p[9]) and tonumber(p[9]) >= 0) and tonumber(p[9]) or nil,
                        pre_slur_msb = tonumber(p[10]) or -1,
                        pre_slur_lsb = tonumber(p[11]) or -1,
                        n1_key      = n1_k,
                        n2_key      = n2_k
                    })
                end
            end
        end
    end
    
    local _, raw_ties = reaper.GetProjExtState(0, "REAPER_Notator", "user_ties")
    if raw_ties and raw_ties ~= "" then
        for entry in raw_ties:gmatch("([^;]+)") do
            local p = {}
            for field in (entry .. "|"):gmatch("([^|]*)|") do table.insert(p, field) end
            local tid = p[1]
            if tid and tid ~= "" then
                local trk_g = p[2] or ""
                local norm_tg = normalize_guid(trk_g)
                local ch = tonumber(p[3]) or 0
                local tp = tonumber(p[4]) or 60
                local s1 = tonumber(p[5]) or 0.0
                local s2 = tonumber(p[7]) or 1.0
                local n1_k = string.format("%d_%.4f_%d", tp, s1, ch)
                local n2_k = string.format("%d_%.4f_%d", tp, s2, ch)
                local pair_key = string.format("%s_%s_%s", norm_tg, n1_k, n2_k)

                if known_ties[tid] or known_tie_pairs[pair_key] then
                    duplicates_pruned = true
                else
                    known_ties[tid] = true
                    known_ties[tid .. "_" .. norm_tg] = true
                    known_tie_pairs[pair_key] = true
                    table.insert(state.user_ties, {
                        id          = tid,
                        track_guid  = trk_g,
                        chan        = ch,
                        pitch       = tp,
                        n1_start_qn = s1,
                        n1_dur      = tonumber(p[6]) or 1.0,
                        n2_start_qn = s2,
                        n2_dur      = tonumber(p[8]) or 1.0,
                        n2_vel      = tonumber(p[9]) or 96,
                        n1_key      = n1_k,
                        n2_key      = n2_k
                    })
                end
            end
        end
    end
    
    -- 2. Dual persistence: scan takes for Type 15 NOTATOR_SLUR / NOTATOR_TIE
    local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
    local takes_to_heal_slurs = {}
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local norm_trk_guid = normalize_guid(trk_guid)
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local take_has_slur = false
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                    for text_i = 0, text_cnt - 1 do
                        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
                        if ok and ev_type == 15 then
                            local s_id, s_chan, p1, p2, sqn, n2sqn, odur, pre_pc, pre_msb, pre_lsb = msg:match("^NOTATOR_SLUR%s+([%w_]+)%s+(%d+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*(%-?%d*)%s*(%-?%d*)%s*(%-?%d*)")
                            if s_id then
                                take_has_slur = true
                                local track_key = s_id .. "_" .. norm_trk_guid
                                local ch = tonumber(s_chan) or 0
                                local p1_n = tonumber(p1) or 60
                                local p2_n = tonumber(p2) or 62
                                local sqn_n = tonumber(sqn) or 0.0
                                local n2sqn_n = tonumber(n2sqn) or 1.0
                                local n1_k = string.format("%d_%.4f_%d", p1_n, sqn_n, ch)
                                local n2_k = string.format("%d_%.4f_%d", p2_n, n2sqn_n, ch)
                                local pair_key = string.format("%s_%s_%s", norm_trk_guid, n1_k, n2_k)

                                if not known_slurs[track_key] and not known_slur_pairs[pair_key] then
                                    known_slurs[track_key] = true
                                    known_slur_pairs[pair_key] = true
                                    local eff_id = s_id
                                    if known_slurs[s_id] then
                                        eff_id = s_id .. "_cp_" .. norm_trk_guid:sub(1, 6)
                                    else
                                        known_slurs[s_id] = true
                                    end
                                    table.insert(state.user_slurs, {
                                        id          = eff_id,
                                        track_guid  = trk_guid,
                                        chan        = ch,
                                        pitch1      = p1_n,
                                        pitch2      = p2_n,
                                        start_qn    = sqn_n,
                                        n2_start_qn = n2sqn_n,
                                        end_qn      = n2sqn_n + 1.0,
                                        orig_dur1   = tonumber(odur) or 1.0,
                                        pre_slur_pc = (pre_pc and pre_pc ~= "" and tonumber(pre_pc) and tonumber(pre_pc) >= 0) and tonumber(pre_pc) or nil,
                                        pre_slur_msb = tonumber(pre_msb) or -1,
                                        pre_slur_lsb = tonumber(pre_lsb) or -1,
                                        n1_key      = n1_k,
                                        n2_key      = n2_k
                                    })
                                else
                                    if known_slurs[track_key] or known_slur_pairs[pair_key] then
                                        for _, es in ipairs(state.user_slurs) do
                                            if (es.id == s_id or (es.n1_key == n1_k and es.n2_key == n2_k)) and (not es.track_guid or es.track_guid == "") then
                                                es.track_guid = trk_guid
                                                break
                                            end
                                        end
                                    else
                                        duplicates_pruned = true
                                    end
                                end
                            end
                            local t_id, t_chan, tp, t_s1, t_d1, t_s2, t_d2, t_vel = msg:match("^NOTATOR_TIE%s+([%w_]+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*(%d*)")
                            if t_id then
                                local tie_track_key = t_id .. "_" .. norm_trk_guid
                                local ch = tonumber(t_chan) or 0
                                local tp_n = tonumber(tp) or 60
                                local s1_n = tonumber(t_s1) or 0.0
                                local s2_n = tonumber(t_s2) or 1.0
                                local n1_k = string.format("%d_%.4f_%d", tp_n, s1_n, ch)
                                local n2_k = string.format("%d_%.4f_%d", tp_n, s2_n, ch)
                                local pair_key = string.format("%s_%s_%s", norm_trk_guid, n1_k, n2_k)

                                if not known_ties[tie_track_key] and not known_tie_pairs[pair_key] then
                                    known_ties[tie_track_key] = true
                                    known_tie_pairs[pair_key] = true
                                    local eff_id = t_id
                                    if known_ties[t_id] then
                                        eff_id = t_id .. "_cp_" .. norm_trk_guid:sub(1, 6)
                                    else
                                        known_ties[t_id] = true
                                    end
                                    table.insert(state.user_ties, {
                                        id          = eff_id,
                                        track_guid  = trk_guid,
                                        chan        = ch,
                                        pitch       = tp_n,
                                        n1_start_qn = s1_n,
                                        n1_dur      = tonumber(t_d1) or 1.0,
                                        n2_start_qn = s2_n,
                                        n2_dur      = tonumber(t_d2) or 1.0,
                                        n2_vel      = (t_vel and t_vel ~= "") and tonumber(t_vel) or 96,
                                        n1_key      = n1_k,
                                        n2_key      = n2_k
                                    })
                                else
                                    if known_ties[tie_track_key] or known_tie_pairs[pair_key] then
                                        for _, et in ipairs(state.user_ties) do
                                            if (et.id == t_id or (et.n1_key == n1_k and et.n2_key == n2_k)) and (not et.track_guid or et.track_guid == "") then
                                                et.track_guid = trk_guid
                                                break
                                            end
                                        end
                                    else
                                        duplicates_pruned = true
                                    end
                                end
                            end
                        end
                    end
                    if take_has_slur then
                        table.insert(takes_to_heal_slurs, take)
                    end
                end
            end
        end
    end

    if MidiService and MidiService.auto_chase_momentary_articulations then
        for _, tk in ipairs(takes_to_heal_slurs) do
            reaper.MIDI_DisableSort(tk)
            MidiService.auto_chase_momentary_articulations(tk)
            reaper.MIDI_Sort(tk)
        end
    end

    if duplicates_pruned then
        SlurService.save_slurs(state)
    end
    SlurService.heal_slurs_and_ties(state)
end

function SlurService.heal_slurs_and_ties(state)
    if not state then return end
    state.user_slurs = state.user_slurs or {}
    state.user_ties = state.user_ties or {}
    
    local valid_guids = {}
    local trk_cnt = reaper.CountTracks(0)
    local has_unguided = false
    for _, sl in ipairs(state.user_slurs) do
        if not sl.track_guid or sl.track_guid == "" then has_unguided = true break end
    end
    if not has_unguided then
        for _, tie in ipairs(state.user_ties) do
            if not tie.track_guid or tie.track_guid == "" then has_unguided = true break end
        end
    end

    local track_takes = {}
    for ti = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local g = reaper.GetTrackGUID(trk)
            if g then
                valid_guids[normalize_guid(g)] = true
                if has_unguided then
                    local takes = {}
                    local item_cnt = reaper.CountTrackMediaItems(trk)
                    for ii = 0, item_cnt - 1 do
                        local it = reaper.GetTrackMediaItem(trk, ii)
                        local tk = it and reaper.GetActiveTake(it)
                        if tk and reaper.TakeIsMIDI(tk) then
                            takes[#takes + 1] = tk
                        end
                    end
                    if #takes > 0 then
                        track_takes[#track_takes + 1] = { guid = g, takes = takes }
                    end
                end
            end
        end
    end

    local function find_matching_track_guid(p1, qn1, p2, qn2, chan)
        for _, tt in ipairs(track_takes) do
            local found1, found2 = false, false
            for _, tk in ipairs(tt.takes) do
                if not found1 and find_take_note_by_pos(tk, p1, chan, qn1, 0.15) then found1 = true end
                if not found2 and find_take_note_by_pos(tk, p2, chan, qn2, 0.15) then found2 = true end
                if found1 and found2 then return tt.guid end
            end
        end
        return nil
    end
    
    local clean_slurs = {}
    local seen_slur_pairs = {}
    for _, sl in ipairs(state.user_slurs) do
        local keep = true
        if sl.track_guid and sl.track_guid ~= "" then
            if not valid_guids[normalize_guid(sl.track_guid)] then
                keep = false -- Track no longer exists in project
            end
        elseif trk_cnt > 0 then
            local matched_g = find_matching_track_guid(sl.pitch1 or 60, sl.start_qn or 0, sl.pitch2 or 60, sl.n2_start_qn or (sl.start_qn or 0) + 1.0, sl.chan)
            if matched_g then
                sl.track_guid = matched_g
            else
                keep = false -- Orphaned legacy slur with no matching notes in project
            end
        end
        local pair_key = string.format("%s_%s_%s", normalize_guid(sl.track_guid), sl.n1_key or "", sl.n2_key or "")
        if seen_slur_pairs[pair_key] then
            keep = false
        end
        if keep then
            seen_slur_pairs[pair_key] = true
            table.insert(clean_slurs, sl)
        end
    end
    state.user_slurs = clean_slurs
    
    local clean_ties = {}
    local seen_tie_pairs = {}
    for _, tie in ipairs(state.user_ties) do
        local keep = true
        if tie.track_guid and tie.track_guid ~= "" then
            if not valid_guids[normalize_guid(tie.track_guid)] then
                keep = false -- Track no longer exists in project
            end
        elseif trk_cnt > 0 then
            local tp = tie.pitch or 60
            local matched_g = find_matching_track_guid(tp, tie.n1_start_qn or 0, tp, tie.n2_start_qn or (tie.n1_start_qn or 0) + 1.0, tie.chan)
            if matched_g then
                tie.track_guid = matched_g
            else
                keep = false -- Orphaned legacy tie with no matching notes in project
            end
        end
        local pair_key = string.format("%s_%s_%s", normalize_guid(tie.track_guid), tie.n1_key or "", tie.n2_key or "")
        if seen_tie_pairs[pair_key] then
            keep = false
        end
        if keep then
            seen_tie_pairs[pair_key] = true
            table.insert(clean_ties, tie)
        end
    end
    
    -- Elaine Gould Adjacency Rule (Behind Bars p. 60):
    -- A tie connects ONLY two adjacent notes. Prune any leaping tie that spans across an intermediate tie endpoint!
    local non_leaping_ties = {}
    for i, t1 in ipairs(clean_ties) do
        local is_leap = false
        local t1_min = math.min(t1.n1_start_qn or 0, t1.n2_start_qn or 0)
        local t1_max = math.max(t1.n1_start_qn or 0, t1.n2_start_qn or 0)
        local t1_norm_tg = normalize_guid(t1.track_guid)
        for j, t2 in ipairs(clean_ties) do
            if i ~= j and t1.pitch == t2.pitch and normalize_guid(t2.track_guid) == t1_norm_tg then
                local s1 = math.min(t2.n1_start_qn or 0, t2.n2_start_qn or 0)
                local s2 = math.max(t2.n1_start_qn or 0, t2.n2_start_qn or 0)
                -- If t1 and t2 touch at an endpoint, they form a valid chain:
                local touches = math.abs(s1 - t1_max) <= 0.06 or math.abs(s2 - t1_min) <= 0.06 or math.abs(s1 - t1_min) <= 0.06 or math.abs(s2 - t1_max) <= 0.06
                if not touches then
                    if (s1 > t1_min + 0.05 and s1 < t1_max - 0.05) or (s2 > t1_min + 0.05 and s2 < t1_max - 0.05) then
                        is_leap = true
                        break
                    end
                else
                    -- If they touch at one end, but the other end of t2 is strictly inside t1, then t1 is a leap over t2!
                    if (s1 > t1_min + 0.06 and s1 < t1_max - 0.06) or (s2 > t1_min + 0.06 and s2 < t1_max - 0.06) then
                        is_leap = true
                        break
                    end
                end
            end
        end
        if not is_leap then
            table.insert(non_leaping_ties, t1)
        end
    end
    state.user_ties = non_leaping_ties
    
    SlurService.save_slurs(state)
end

function SlurService.reconcile_from_takes(state)
    if not state then return false end
    state.user_slurs = state.user_slurs or {}
    state.user_ties = state.user_ties or {}
    local any_changed = false

    local slur_by_id = {}
    local seen_slur_pairs = {}
    for _, sl in ipairs(state.user_slurs) do
        if sl.id then slur_by_id[sl.id] = sl end
        local p_key = string.format("%s_%s_%s", normalize_guid(sl.track_guid), sl.n1_key or "", sl.n2_key or "")
        seen_slur_pairs[p_key] = sl
    end
    local tie_by_id = {}
    local seen_tie_pairs = {}
    for _, tie in ipairs(state.user_ties) do
        if tie.id then tie_by_id[tie.id] = tie end
        local p_key = string.format("%s_%s_%s", normalize_guid(tie.track_guid), tie.n1_key or "", tie.n2_key or "")
        seen_tie_pairs[p_key] = tie
    end

    local seen_slur_ids = {}
    local seen_tie_ids = {}
    local newly_discovered_slur_takes = {}

    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local norm_trk_guid = normalize_guid(trk_guid)
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
                    local take_new_slur = false
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                    for text_i = 0, text_cnt - 1 do
                        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
                        if ok and ev_type == 15 then
                            local s_id, s_chan, p1, p2, sqn, n2sqn, odur, pre_pc, pre_msb, pre_lsb = msg:match("^NOTATOR_SLUR%s+([%w_]+)%s+(%d+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*(%-?%d*)%s*(%-?%d*)%s*(%-?%d*)")
                            if s_id then
                                local ch = tonumber(s_chan) or 0
                                local p1_n = tonumber(p1) or 60
                                local p2_n = tonumber(p2) or 62
                                local sqn_n = tonumber(sqn) or 0.0
                                local n2sqn_n = tonumber(n2sqn) or 1.0
                                local n1_k = string.format("%d_%.4f_%d", p1_n, sqn_n, ch)
                                local n2_k = string.format("%d_%.4f_%d", p2_n, n2sqn_n, ch)
                                local pair_key = string.format("%s_%s_%s", norm_trk_guid, n1_k, n2_k)

                                if seen_slur_ids[s_id .. "_" .. norm_trk_guid] or seen_slur_pairs[pair_key] then
                                    local es = slur_by_id[s_id] or seen_slur_pairs[pair_key]
                                    if es and es.track_guid ~= trk_guid then
                                        es.track_guid = trk_guid
                                        any_changed = true
                                    end
                                else
                                    seen_slur_ids[s_id .. "_" .. norm_trk_guid] = true
                                    local es = slur_by_id[s_id]
                                    if es then
                                        if es.track_guid ~= trk_guid then
                                            es.track_guid = trk_guid
                                            any_changed = true
                                        end
                                    else
                                        local nsl = {
                                            id          = s_id,
                                            track_guid  = trk_guid,
                                            chan        = ch,
                                            pitch1      = p1_n,
                                            pitch2      = p2_n,
                                            start_qn    = sqn_n,
                                            n2_start_qn = n2sqn_n,
                                            end_qn      = n2sqn_n + 1.0,
                                            orig_dur1   = tonumber(odur) or 1.0,
                                            pre_slur_pc = (pre_pc and pre_pc ~= "" and tonumber(pre_pc) and tonumber(pre_pc) >= 0) and tonumber(pre_pc) or nil,
                                            pre_slur_msb = tonumber(pre_msb) or -1,
                                            pre_slur_lsb = tonumber(pre_lsb) or -1,
                                            n1_key      = n1_k,
                                            n2_key      = n2_k
                                        }
                                        table.insert(state.user_slurs, nsl)
                                        slur_by_id[s_id] = nsl
                                        seen_slur_pairs[pair_key] = nsl
                                        any_changed = true
                                        take_new_slur = true
                                    end
                                end
                            end

                            local t_id, t_chan, tp, t_s1, t_d1, t_s2, t_d2, t_vel = msg:match("^NOTATOR_TIE%s+([%w_]+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*(%d*)")
                            if t_id then
                                local ch = tonumber(t_chan) or 0
                                local tp_n = tonumber(tp) or 60
                                local s1_n = tonumber(t_s1) or 0.0
                                local s2_n = tonumber(t_s2) or 1.0
                                local n1_k = string.format("%d_%.4f_%d", tp_n, s1_n, ch)
                                local n2_k = string.format("%d_%.4f_%d", tp_n, s2_n, ch)
                                local pair_key = string.format("%s_%s_%s", norm_trk_guid, n1_k, n2_k)

                                if seen_tie_ids[t_id .. "_" .. norm_trk_guid] or seen_tie_pairs[pair_key] then
                                    local et = tie_by_id[t_id] or seen_tie_pairs[pair_key]
                                    if et and et.track_guid ~= trk_guid then
                                        et.track_guid = trk_guid
                                        any_changed = true
                                    end
                                else
                                    seen_tie_ids[t_id .. "_" .. norm_trk_guid] = true
                                    local et = tie_by_id[t_id]
                                    if et then
                                        if et.track_guid ~= trk_guid then
                                            et.track_guid = trk_guid
                                            any_changed = true
                                        end
                                    else
                                        local ntie = {
                                            id          = t_id,
                                            track_guid  = trk_guid,
                                            chan        = ch,
                                            pitch       = tp_n,
                                            n1_start_qn = s1_n,
                                            n1_dur      = tonumber(t_d1) or 1.0,
                                            n2_start_qn = s2_n,
                                            n2_dur      = tonumber(t_d2) or 1.0,
                                            n2_vel      = (t_vel and t_vel ~= "") and tonumber(t_vel) or 96,
                                            n1_key      = n1_k,
                                            n2_key      = n2_k
                                        }
                                        table.insert(state.user_ties, ntie)
                                        tie_by_id[t_id] = ntie
                                        seen_tie_pairs[pair_key] = ntie
                                        any_changed = true
                                    end
                                end
                            end
                        end
                    end
                    if take_new_slur then
                        table.insert(newly_discovered_slur_takes, take)
                    end
                end
            end
        end
    end

    if #newly_discovered_slur_takes > 0 then
        local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
        if MidiService and MidiService.auto_chase_momentary_articulations then
            for _, tk in ipairs(newly_discovered_slur_takes) do
                reaper.MIDI_DisableSort(tk)
                MidiService.auto_chase_momentary_articulations(tk)
                reaper.MIDI_Sort(tk)
            end
        end
    end

    if any_changed then
        SlurService.save_slurs(state)
    end
    return any_changed
end

function SlurService.save_slurs(state)
    if not state then return end
    state._slurs_version = (state._slurs_version or 0) + 1
    state._is_note_slurred_cache = nil
    
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

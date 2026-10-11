-- ==============================================================================
-- REAPER Native Notator - Service: DivisioVocumService
-- Splits multi-voice chords on a single track and distributes them vertically
-- across the tracks displayed in the viewport below the source track (Divisio Vocum).
-- ==============================================================================

local MidiService = require("services.midi_service")

local DivisioVocumService = {}

--- Helper to get track display name
local function get_track_display_name(trk)
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then return "Track" end
    local _, name = reaper.GetTrackName(trk)
    local idx = math.floor(reaper.GetMediaTrackInfo_Value(trk, "IP_TRACKNUMBER"))
    if name and name ~= "" then
        return string.format("Track %d: %s", idx, name)
    else
        return string.format("Track %d", idx)
    end
end

--- Resolves the source track and list of destination tracks in the viewport
--- @param state table
--- @param active_tracks_data table List of active tracks in viewport
--- @param target_voice_count number Number of voices/tracks to distribute to
--- @param opt_source_track MediaTrack Optional explicit source track
--- @return table target_tracks List of { track = MediaTrack*, name = string, guid = string, is_source = boolean }
--- @return MediaTrack* source_track
function DivisioVocumService.get_target_tracks(state, active_tracks_data, target_voice_count, opt_source_track)
    local voice_count = math.max(2, math.min(16, target_voice_count or 4))
    
    -- 1. Identify source track
    local src_track = opt_source_track
    if not src_track or not reaper.ValidatePtr(src_track, "MediaTrack*") then
        if state and state.selected_note and state.selected_note.track and reaper.ValidatePtr(state.selected_note.track, "MediaTrack*") then
            src_track = state.selected_note.track
        elseif state and state.selected_notes then
            for _, sn in pairs(state.selected_notes) do
                if sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then
                    src_track = sn.track
                    break
                end
            end
        end
    end
    if not src_track or not reaper.ValidatePtr(src_track, "MediaTrack*") then
        src_track = state and state.focused_track
    end
    if not src_track or not reaper.ValidatePtr(src_track, "MediaTrack*") then
        src_track = reaper.GetSelectedTrack(0, 0)
    end
    if (not src_track or not reaper.ValidatePtr(src_track, "MediaTrack*")) and active_tracks_data and #active_tracks_data > 0 then
        src_track = active_tracks_data[1].track
    end
    if not src_track or not reaper.ValidatePtr(src_track, "MediaTrack*") then
        return {}, nil
    end

    local src_guid = reaper.GetTrackGUID(src_track)
    local target_tracks = {}

    -- 2. First, locate source track index in active_tracks_data
    local src_idx = nil
    if active_tracks_data and #active_tracks_data > 0 then
        for i, tdata in ipairs(active_tracks_data) do
            if tdata.track == src_track or (tdata.guid and tdata.guid == src_guid) then
                src_idx = i
                break
            end
        end
    end

    -- 3. Collect from active_tracks_data starting at source track downwards
    if src_idx and active_tracks_data then
        for i = src_idx, math.min(#active_tracks_data, src_idx + voice_count - 1) do
            local td = active_tracks_data[i]
            if td and td.track and reaper.ValidatePtr(td.track, "MediaTrack*") then
                table.insert(target_tracks, {
                    track = td.track,
                    name = td.name or get_track_display_name(td.track),
                    guid = td.guid or reaper.GetTrackGUID(td.track),
                    is_source = (i == src_idx)
                })
            end
        end
    end

    -- 4. If active_tracks_data did not have enough tracks below, check REAPER project tracks
    if #target_tracks < voice_count then
        local parent_idx = math.floor(reaper.GetMediaTrackInfo_Value(src_track, "IP_TRACKNUMBER")) -- 1-based
        local total_proj_tracks = reaper.CountTracks(0)
        
        -- Start from the track index directly after what we already collected
        local start_track_idx = parent_idx + #target_tracks -- 1-based
        for t_idx = start_track_idx, math.min(total_proj_tracks, parent_idx + voice_count - 1) do
            local tr = reaper.GetTrack(0, t_idx - 1)
            if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
                table.insert(target_tracks, {
                    track = tr,
                    name = get_track_display_name(tr),
                    guid = reaper.GetTrackGUID(tr),
                    is_source = false
                })
            end
        end
    end

    return target_tracks, src_track
end

--- Collects notes from the source track and groups them into chords based on tolerance window
--- @param source_track MediaTrack
--- @param tolerance_ms number Tolerance in milliseconds (e.g. 25ms)
--- @param selected_only boolean Whether to process selected notes only
--- @param state table Optional Notator state for selection filtering
--- @return table chord_groups List of { { pitch = ..., start_time = ..., dur_qn = ..., vel = ..., chan = ..., articulation = ..., take = ... }, ... }
--- @return number total_notes
function DivisioVocumService.collect_notes_and_chords(source_track, tolerance_ms, selected_only, state)
    local chord_groups = {}
    local total_notes = 0
    if not source_track or not reaper.ValidatePtr(source_track, "MediaTrack*") then
        return chord_groups, total_notes
    end

    local tol_sec = math.max(0.001, (tolerance_ms or 25) / 1000.0)
    local raw_notes = {}
    local item_count = reaper.CountTrackMediaItems(source_track)

    for ii = 0, item_count - 1 do
        local item = reaper.GetTrackMediaItem(source_track, ii)
        local take = item and reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            local _, notecnt, _, textcnt = reaper.MIDI_CountEvts(take)
            
            -- Read type 15 articulations
            local note_arts_list = {}
            for ti = 0, textcnt - 1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 then
                    local p, ch, art = msg:match("NOTE%s+(%d+)%s+(%d+)%s+a%s+([%a%d_]+)")
                    if p and art then
                        table.insert(note_arts_list, { ppq = ppq, pitch = tonumber(p), chan = tonumber(ch) or 0, art = art })
                    end
                end
            end

            for ni = 0, notecnt - 1 do
                local ok, sel, mut, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
                if ok and not mut then
                    local keep = true
                    if selected_only then
                        keep = sel
                    end

                    if keep then
                        local start_time = reaper.MIDI_GetProjTimeFromPPQPos(take, sppq)
                        local end_time = reaper.MIDI_GetProjTimeFromPPQPos(take, eppq)
                        local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                        local end_qn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                        local dur_qn = math.max(0.0625, end_qn - start_qn)

                        -- Match articulation
                        local art = nil
                        for _, na in ipairs(note_arts_list) do
                            if na.pitch == pitch and math.abs(na.ppq - sppq) <= 25 then
                                art = na.art
                                break
                            end
                        end

                        table.insert(raw_notes, {
                            take = take,
                            item = item,
                            note_idx = ni,
                            sppq = sppq,
                            eppq = eppq,
                            start_time = start_time,
                            end_time = end_time,
                            start_qn = start_qn,
                            end_qn = end_qn,
                            dur_qn = dur_qn,
                            pitch = pitch,
                            vel = vel,
                            chan = chan,
                            selected = sel,
                            articulation = art
                        })
                    end
                end
            end
        end
    end

    total_notes = #raw_notes
    if total_notes == 0 then
        return chord_groups, 0
    end

    -- Sort notes chronologically by start time
    table.sort(raw_notes, function(a, b)
        if math.abs(a.start_time - b.start_time) > 0.001 then
            return a.start_time < b.start_time
        end
        return a.pitch > b.pitch -- If identical time, highest pitch first
    end)

    -- Group into chords based on tolerance window
    local i = 1
    while i <= #raw_notes do
        local group = { raw_notes[i] }
        local j = i + 1
        while j <= #raw_notes and (raw_notes[j].start_time - raw_notes[i].start_time) <= tol_sec do
            table.insert(group, raw_notes[j])
            j = j + 1
        end

        -- Sort each chord group strictly descending by pitch (highest to lowest)
        table.sort(group, function(a, b) return a.pitch > b.pitch end)
        table.insert(chord_groups, group)
        i = j
    end

    return chord_groups, total_notes
end

--- Executes the Explode Chords operation:
--- - Retains Voice 1 on the source track.
--- - Distributes Voice 2..N to target tracks in the viewport below.
--- - Deletes secondary notes from the source track (consuming the chord).
--- - Restores momentary articulations & updates display.
--- @param state table Notator state object
--- @param opts table Configuration options
--- @return boolean success
--- @return string status_msg
function DivisioVocumService.execute(state, opts)
    opts = opts or {}
    local active_tracks_data = opts.active_tracks_data or (state and state.active_tracks_cache)
    local target_voice_count = math.max(2, math.min(16, opts.target_voices or 5))
    local tolerance_ms = opts.tolerance_ms or 25
    local gap_fill = (opts.gap_fill ~= false)
    local selected_only = (opts.scope == "selected")

    -- If user requested selected only but no notes are selected, fallback to all notes
    local sel_cnt = (state and state.count_selected_notes and state:count_selected_notes()) or 0
    if selected_only and sel_cnt == 0 then
        selected_only = false
    end

    local target_tracks, src_track = DivisioVocumService.get_target_tracks(state, active_tracks_data, target_voice_count, opts.source_track)
    if not src_track or #target_tracks < 2 then
        return false, "Divisio Vocum requires at least 2 tracks (Source + destination tracks in viewport)!"
    end

    local chord_groups, total_notes = DivisioVocumService.collect_notes_and_chords(src_track, tolerance_ms, selected_only, state)
    if #chord_groups == 0 then
        return false, "No notes or chords found for Divisio Vocum on source track!"
    end

    reaper.Undo_BeginBlock2(0)

    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks()

    local affected_takes = {}
    local notes_to_delete_by_take = {}
    local exploded_notes_count = 0
    local exploded_chords_count = 0

    for _, group in ipairs(chord_groups) do
        -- Only chords with 2 or more notes actually get exploded (single notes stay on source)
        if #group >= 2 then
            exploded_chords_count = exploded_chords_count + 1
        end

        -- Voice 1 (group[1]): stays on source track! No change needed.
        affected_takes[group[1].take] = group[1].take

        -- Voice 2 .. N: distribute to target tracks below
        for v = 2, target_voice_count do
            local dest_track_info = target_tracks[v]
            if dest_track_info and dest_track_info.track and reaper.ValidatePtr(dest_track_info.track, "MediaTrack*") then
                local dest_track = dest_track_info.track
                
                -- Determine note for this voice
                local note_to_write = nil
                if v <= #group then
                    note_to_write = group[v]
                elseif gap_fill and #group >= 1 then
                    -- Pad/double lowest note of chord
                    note_to_write = group[#group]
                end

                if note_to_write then
                    local dest_item, dest_take = MidiService.get_or_create_item_at_qn(dest_track, note_to_write.start_qn, note_to_write.dur_qn)
                    if dest_take and reaper.ValidatePtr(dest_take, "MediaItem_Take*") then
                        affected_takes[dest_take] = dest_take

                        local new_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(dest_take, note_to_write.start_qn) + 0.5)
                        local new_eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(dest_take, note_to_write.start_qn + note_to_write.dur_qn) + 0.5)

                        -- Determine active channel/voice for dest track
                        local dest_guid = dest_track_info.guid or reaper.GetTrackGUID(dest_track)
                        local v_idx = (state and state.track_voices and dest_guid and state.track_voices[dest_guid]) or 0
                        local chan = (v_idx > 0) and (v_idx - 1) or (note_to_write.chan or 0)

                        -- Insert note into destination take
                        reaper.MIDI_InsertNote(dest_take, false, false, new_sppq, new_eppq, chan, note_to_write.pitch, note_to_write.vel or 96, false)
                        exploded_notes_count = exploded_notes_count + 1

                        -- Copy articulation if present
                        if note_to_write.articulation and note_to_write.articulation ~= "" then
                            local art_str = string.format("NOTE %d %d a %s", note_to_write.pitch, chan, note_to_write.articulation)
                            reaper.MIDI_InsertTextSysexEvt(dest_take, false, false, new_sppq, 15, art_str)

                            -- Bridge Reaticulate PC if bank exists on dest track
                            local trk_override = dest_guid and state and state.track_articulation_banks and state.track_articulation_banks[dest_guid]
                            local dest_bank = dest_track and ReaticulateParser and ReaticulateParser.get_bank_for_track(dest_track, all_banks, trk_override)
                            local art_match = dest_bank and MidiService.find_reaticulate_art_for_id(dest_bank, note_to_write.articulation)
                            if art_match then
                                if dest_bank.msb and dest_bank.msb >= 0 then
                                    reaper.MIDI_InsertCC(dest_take, false, false, new_sppq, 0xB0, chan, 0, dest_bank.msb)
                                end
                                if dest_bank.lsb and dest_bank.lsb >= 0 then
                                    reaper.MIDI_InsertCC(dest_take, false, false, new_sppq, 0xB0, chan, 32, dest_bank.lsb)
                                end
                                reaper.MIDI_InsertCC(dest_take, false, false, new_sppq, 0xC0, chan, art_match.pc, 0)
                            end
                        end
                    end
                end
            end
        end

        -- Secondary notes (group[2] .. group[#group]) on source track are consumed / deleted
        for v = 2, #group do
            local sec_note = group[v]
            if sec_note and sec_note.take then
                if not notes_to_delete_by_take[sec_note.take] then
                    notes_to_delete_by_take[sec_note.take] = {}
                end
                table.insert(notes_to_delete_by_take[sec_note.take], sec_note)
            end
        end
    end

    -- 5. Delete consumed secondary notes from source takes
    for tk, del_list in pairs(notes_to_delete_by_take) do
        if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") then
            affected_takes[tk] = tk
            local _, cur_notecnt, _, cur_textcnt = reaper.MIDI_CountEvts(tk)
            
            -- Find matching note indices to delete
            local to_delete_indices = {}
            for _, dn in ipairs(del_list) do
                for ni = cur_notecnt - 1, 0, -1 do
                    local ok, _, _, sppq, _, _, pitch, _ = reaper.MIDI_GetNote(tk, ni)
                    if ok and pitch == dn.pitch and math.abs(sppq - dn.sppq) <= 15 then
                        table.insert(to_delete_indices, ni)
                        break
                    end
                end
            end

            -- Sort descending by index to delete safely
            table.sort(to_delete_indices, function(a, b) return a > b end)
            for _, idx in ipairs(to_delete_indices) do
                reaper.MIDI_DeleteNote(tk, idx)
            end

            -- Clean up orphaned Type 15 articulation events for deleted notes
            for _, dn in ipairs(del_list) do
                local _, _, _, text_cnt = reaper.MIDI_CountEvts(tk)
                for ti = text_cnt - 1, 0, -1 do
                    local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(tk, ti)
                    if ok and etype == 15 and math.abs(ppq - dn.sppq) <= 25 then
                        local p = msg:match("NOTE%s+(%d+)")
                        if p and tonumber(p) == dn.pitch then
                            reaper.MIDI_DeleteTextSysexEvt(tk, ti)
                        end
                    end
                end
            end
        end
    end

    -- 6. Sort and resolve auto chase for all affected takes
    for tk, _ in pairs(affected_takes) do
        if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") then
            local trk = reaper.GetMediaItemTake_Track(tk)
            local trk_guid = trk and reaper.GetTrackGUID(trk)
            local trk_override = trk_guid and state and state.track_articulation_banks and state.track_articulation_banks[trk_guid]
            local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, all_banks, trk_override)
            MidiService.auto_chase_momentary_articulations(tk, bank)
            reaper.MIDI_Sort(tk)
        end
    end

    reaper.Undo_EndBlock2(0, string.format("Notator: Divisio Vocum (%d Chords to %d Tracks)", exploded_chords_count, #target_tracks), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    if state then
        state.active_tracks_cache = nil
        state.selected_notes = {}
        state.selected_note = nil
        state.status_msg = string.format("Divisio Vocum: Distributed %d chord(s) across %d tracks (%d voices written)", exploded_chords_count, #target_tracks, exploded_notes_count)
    end

    return true, string.format("Divisio Vocum: Distributed %d chord(s) across %d tracks!", exploded_chords_count, #target_tracks)
end

-- Backward compatibility alias
DivisioVocumService.explode = DivisioVocumService.execute

return DivisioVocumService


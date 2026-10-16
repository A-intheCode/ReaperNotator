-- ==============================================================================
-- REAPER Native Notator - Service: DivisiService
-- Splits voices (Voice 1..16 / MIDI Channels 1..16) from selected notes or an
-- entire staff/track onto newly duplicated REAPER tracks (including full FX chain,
-- Kontakt/VSTi instances, Reaticulate banks, routing/sends, and MIDI items).
-- ==============================================================================

local MidiService = require("services.midi_service")

local DivisiService = {}

--- Helper to get a clean track name
--- @param trk MediaTrack
--- @return string
local function get_clean_track_name(trk)
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then return "Instrument" end
    local _, name = reaper.GetTrackName(trk)
    local idx = math.floor(reaper.GetMediaTrackInfo_Value(trk, "IP_TRACKNUMBER"))
    if name and name ~= "" then
        return name
    end
    return string.format("Track %d", idx)
end

--- Resolves the target source track for Divisi
--- @param state table
--- @param active_tracks_data table|nil
--- @param opt_source_track MediaTrack|nil
--- @return MediaTrack|nil
function DivisiService.resolve_source_track(state, active_tracks_data, opt_source_track)
    if opt_source_track and reaper.ValidatePtr(opt_source_track, "MediaTrack*") then
        return opt_source_track
    end
    if state then
        if state.selected_note and state.selected_note.track and reaper.ValidatePtr(state.selected_note.track, "MediaTrack*") then
            return state.selected_note.track
        end
        if state.selected_notes then
            for _, sn in pairs(state.selected_notes) do
                if sn and sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then
                    return sn.track
                end
            end
        end
        if state.focused_track and reaper.ValidatePtr(state.focused_track, "MediaTrack*") then
            return state.focused_track
        end
    end
    local sel_trk = reaper.GetSelectedTrack(0, 0)
    if sel_trk and reaper.ValidatePtr(sel_trk, "MediaTrack*") then
        return sel_trk
    end
    if active_tracks_data and active_tracks_data[1] and active_tracks_data[1].track and reaper.ValidatePtr(active_tracks_data[1].track, "MediaTrack*") then
        return active_tracks_data[1].track
    end
    return nil
end

--- Checks whether a note in a take is currently selected in REAPER or Notator state
--- @param state table|nil
--- @param take MediaItem_Take
--- @param ni number 0-based note index
--- @param sel boolean REAPER MIDI note selected flag
--- @param pitch number
--- @param sppq number
--- @param start_qn number
--- @return boolean
local function is_note_in_selection(state, take, ni, sel, pitch, sppq, start_qn)
    if sel then return true end
    if not state or not state.selected_notes then return false end
    local take_str = tostring(take)
    for _, sn in pairs(state.selected_notes) do
        if sn then
            local same_take = (sn.take == take) or (tostring(sn.take) == take_str)
            if same_take then
                if sn.idx == ni then
                    return true
                elseif sn.pitch == pitch and sn.sppq and math.abs(sn.sppq - sppq) <= 25 then
                    return true
                elseif sn.pitch == pitch and sn.start_qn and math.abs(sn.start_qn - start_qn) <= 0.03 then
                    return true
                end
            end
        end
    end
    return false
end

--- Analyzes all voices present on the source track (either within selected notes or whole track)
--- @param state table
--- @param src_track MediaTrack
--- @param selected_only boolean
--- @return table voice_list Sorted list of { voice = 1..16, chan = 0..15, count = N, min_pitch = P, max_pitch = P }
--- @return number total_notes_in_scope
--- @return table item_snapshots Per-item note snapshots for exact splitting
function DivisiService.analyze_voices(state, src_track, selected_only)
    if type(selected_only) == "string" then
        selected_only = (selected_only == "selected" or selected_only == "selection")
    end
    local voice_list = {}
    local total_notes_in_scope = 0
    local item_snapshots = {}

    if not src_track or not reaper.ValidatePtr(src_track, "MediaTrack*") then
        return voice_list, 0, item_snapshots
    end

    local voice_stats = {}
    local item_cnt = reaper.CountTrackMediaItems(src_track)

    for it_idx = 0, item_cnt - 1 do
        local item = reaper.GetTrackMediaItem(src_track, it_idx)
        local take = item and reaper.GetActiveTake(item)
        local snap = {
            item_idx = it_idx,
            item = item,
            take = take,
            is_midi = false,
            notes = {}
        }

        if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
            snap.is_midi = true
            local _, notecnt = reaper.MIDI_CountEvts(take)
            for ni = 0, notecnt - 1 do
                local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
                if ok then
                    local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                    local end_qn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                    local is_sel = is_note_in_selection(state, take, ni, sel, pitch, sppq, start_qn)
                    local in_scope = (not muted) and ((not selected_only) or is_sel)
                    local ch = (chan or 0) & 0x0F
                    local v = ch + 1

                    table.insert(snap.notes, {
                        ni = ni,
                        sel = sel,
                        is_sel = is_sel,
                        muted = muted,
                        sppq = sppq,
                        eppq = eppq,
                        start_qn = start_qn,
                        end_qn = end_qn,
                        chan = ch,
                        voice = v,
                        pitch = pitch,
                        vel = vel,
                        in_scope = in_scope
                    })

                    if in_scope then
                        total_notes_in_scope = total_notes_in_scope + 1
                        local st = voice_stats[v]
                        if not st then
                            st = {
                                voice = v,
                                chan = ch,
                                count = 0,
                                min_pitch = pitch,
                                max_pitch = pitch,
                                min_qn = start_qn,
                                max_qn = end_qn
                            }
                            voice_stats[v] = st
                        end
                        st.count = st.count + 1
                        if pitch < st.min_pitch then st.min_pitch = pitch end
                        if pitch > st.max_pitch then st.max_pitch = pitch end
                        if start_qn < st.min_qn then st.min_qn = start_qn end
                        if end_qn > st.max_qn then st.max_qn = end_qn end
                    end
                end
            end
        end

        item_snapshots[it_idx] = snap
    end

    for v = 1, 16 do
        if voice_stats[v] and voice_stats[v].count > 0 then
            table.insert(voice_list, voice_stats[v])
        end
    end

    table.sort(voice_list, function(a, b) return a.voice < b.voice end)
    return voice_list, total_notes_in_scope, item_snapshots
end

--- Executes the Divisi split:
--- - Keeps the primary voice (e.g. Voice 1) on the source track
--- - Duplicates the source track (Kontakt/VSTi, Reaticulate Bank, Sends, Folder depth, Items) for each secondary voice
--- - Keeps only the respective voice's notes on each duplicated track and removes them from the source track
--- @param state table
--- @param opts table|nil { source_track = MediaTrack*, scope = "selected"|"all", enabled_voices = table, normalize_to_voice_1 = boolean }
--- @return boolean success
--- @return string message
function DivisiService.execute(state, opts)
    opts = opts or {}
    local active_tracks_data = opts.active_tracks_data or (state and state.active_tracks_cache)
    local src_track = DivisiService.resolve_source_track(state, active_tracks_data, opts.source_track)
    if not src_track or not reaper.ValidatePtr(src_track, "MediaTrack*") then
        local msg = "Divisi: No valid source track selected!"
        if state then state.status_msg = msg end
        return false, msg
    end

    local sel_cnt = (state and state.count_selected_notes and state:count_selected_notes()) or 0
    local selected_only = false
    if opts.scope == "selected" or opts.scope == "selection" then
        selected_only = (sel_cnt > 0)
    elseif opts.scope == "all" or opts.scope == "track" then
        selected_only = false
    else
        selected_only = (sel_cnt > 0)
    end

    local normalize_to_voice_1 = (opts.normalize_to_voice_1 ~= false) and (opts.normalize_voice_to_1 ~= false)

    local voice_list, total_in_scope, item_snapshots = DivisiService.analyze_voices(state, src_track, selected_only)
    if selected_only and #voice_list < 2 then
        -- Fallback check: if user selected notes of only 1 voice or none on this track, check if whole track has multiple voices
        local all_voices, all_total, all_snaps = DivisiService.analyze_voices(state, src_track, false)
        if #all_voices >= 2 and opts.scope == nil then
            selected_only = false
            voice_list = all_voices
            total_in_scope = all_total
            item_snapshots = all_snaps
        end
    end

    if #voice_list < 2 then
        local msg = "Divisi requires at least 2 voices on the track/selection (run Auto-Voice first)!"
        if state then state.status_msg = msg end
        return false, msg
    end

    -- Primary voice stays on source track; secondary voices are split onto duplicated tracks
    local primary_voice_info = voice_list[1]
    local secondary_voices = {}
    local extracted_voice_set = {}
    for i = 2, #voice_list do
        local vi = voice_list[i]
        if not opts.enabled_voices or opts.enabled_voices[vi.voice] ~= false then
            table.insert(secondary_voices, vi)
            extracted_voice_set[vi.voice] = true
        end
    end

    if #secondary_voices == 0 then
        local msg = "Divisi: No secondary voices selected to split!"
        if state then state.status_msg = msg end
        return false, msg
    end

    reaper.Undo_BeginBlock2(0)
    reaper.PreventUIRefresh(1)

    local base_name = get_clean_track_name(src_track)
    local src_guid = reaper.GetTrackGUID(src_track)
    local orig_folder_depth = reaper.GetMediaTrackInfo_Value(src_track, "I_FOLDERDEPTH")
    local _, orig_reat_ext = reaper.GetSetMediaTrackInfo_String(src_track, "P_EXT:reaticulate", "", false)

    -- If source track closes one or more folders (orig_folder_depth < 0), temporarily set it to 0
    -- so all duplicated Divisi tracks stay inside the same folder, then restore folder-close on the last Divisi track.
    if orig_folder_depth < 0 then
        reaper.SetMediaTrackInfo_Value(src_track, "I_FOLDERDEPTH", 0)
    end

    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks(false, state)

    local created_tracks = {} -- ordered matching secondary_voices (1 .. #secondary_voices)

    -- Duplicate in reverse order from src_track so that secondary_voices[1] ends up directly below src_track,
    -- secondary_voices[2] below secondary_voices[1], etc.
    for idx = #secondary_voices, 1, -1 do
        reaper.SetOnlyTrackSelected(src_track)
        reaper.Main_OnCommand(40062, 0) -- Track: Duplicate tracks (clones FX/Kontakt, Reaticulate, Sends, Routing & Items)
        local dup_track = reaper.GetSelectedTrack(0, 0)
        if dup_track and dup_track ~= src_track and reaper.ValidatePtr(dup_track, "MediaTrack*") then
            created_tracks[idx] = dup_track
        end
    end

    -- Restore folder closure on the very last duplicated track (if src_track was closing a folder)
    if orig_folder_depth < 0 then
        if #created_tracks > 0 then
            for i = 1, #created_tracks - 1 do
                if created_tracks[i] and reaper.ValidatePtr(created_tracks[i], "MediaTrack*") then
                    reaper.SetMediaTrackInfo_Value(created_tracks[i], "I_FOLDERDEPTH", 0)
                end
            end
            local last_dup = created_tracks[#created_tracks]
            if last_dup and reaper.ValidatePtr(last_dup, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(last_dup, "I_FOLDERDEPTH", orig_folder_depth)
            else
                reaper.SetMediaTrackInfo_Value(src_track, "I_FOLDERDEPTH", orig_folder_depth)
            end
        else
            reaper.SetMediaTrackInfo_Value(src_track, "I_FOLDERDEPTH", orig_folder_depth)
        end
    end

    local total_extracted_notes = 0

    -- Process each duplicated track for its assigned voice
    for idx, vi in ipairs(secondary_voices) do
        local dup_track = created_tracks[idx]
        local target_v = vi.voice
        local target_chan = vi.chan

        if dup_track and reaper.ValidatePtr(dup_track, "MediaTrack*") then
            local dup_guid = reaper.GetTrackGUID(dup_track)
            local div_name = string.format("%s (Divisi %d)", base_name, target_v)
            reaper.GetSetMediaTrackInfo_String(dup_track, "P_NAME", div_name, true)

            -- Ensure P_EXT:reaticulate is copied
            if orig_reat_ext and orig_reat_ext ~= "" then
                reaper.GetSetMediaTrackInfo_String(dup_track, "P_EXT:reaticulate", orig_reat_ext, true)
            end

            -- Copy Notator per-track settings (Clef, Reaticulate Bank override, visibility in Score Canvas)
            if state then
                state.selected_tracks = state.selected_tracks or {}
                state.selected_tracks[dup_guid] = true
                if state.track_clefs and state.track_clefs[src_guid] then
                    state.track_clefs[dup_guid] = state.track_clefs[src_guid]
                end
                if state.track_articulation_banks and state.track_articulation_banks[src_guid] then
                    state.track_articulation_banks[dup_guid] = state.track_articulation_banks[src_guid]
                end
                -- Copy any user slurs belonging to this voice on src_track to dup_track
                if state.user_slurs then
                    local norm_src = src_guid:gsub("[{}%-]", ""):upper()
                    local new_slurs = {}
                    for _, sl in ipairs(state.user_slurs) do
                        local sl_g = (sl.track_guid or ""):gsub("[{}%-]", ""):upper()
                        if sl_g == norm_src and (sl.chan or 0) == target_chan then
                            local sl_copy = {}
                            for k, v in pairs(sl) do sl_copy[k] = v end
                            sl_copy.id = "slur_div_" .. tostring(math.random(100000, 999999))
                            sl_copy.track_guid = dup_guid
                            sl_copy.chan = normalize_to_voice_1 and 0 or target_chan
                            table.insert(new_slurs, sl_copy)
                        end
                    end
                    for _, nsl in ipairs(new_slurs) do
                        table.insert(state.user_slurs, nsl)
                    end
                end
            end

            -- Filter MIDI items on dup_track so ONLY notes of target_v (in scope) remain
            local dup_item_cnt = reaper.CountTrackMediaItems(dup_track)
            local items_to_remove = {}

            for it_idx = 0, dup_item_cnt - 1 do
                local dup_item = reaper.GetTrackMediaItem(dup_track, it_idx)
                local dup_take = dup_item and reaper.GetActiveTake(dup_item)
                local snap = item_snapshots[it_idx]

                if dup_take and reaper.ValidatePtr(dup_take, "MediaItem_Take*") and reaper.TakeIsMIDI(dup_take) and snap and snap.is_midi then
                    reaper.GetSetMediaItemTakeInfo_String(dup_take, "P_NAME", div_name, true)
                    reaper.MIDI_DisableSort(dup_take)

                    local kept_in_item = 0
                    local deleted_notes_info = {}
                    local kept_notes_info = {}

                    -- Iterate backwards over notes using the exact snapshot indices
                    for n_i = #snap.notes, 1, -1 do
                        local ns = snap.notes[n_i]
                        if ns.in_scope and ns.voice == target_v then
                            kept_in_item = kept_in_item + 1
                            total_extracted_notes = total_extracted_notes + 1
                            local out_chan = normalize_to_voice_1 and 0 or ns.chan
                            reaper.MIDI_SetNote(dup_take, ns.ni, false, ns.muted, ns.sppq, ns.eppq, out_chan, ns.pitch, ns.vel, true)
                            table.insert(kept_notes_info, ns)
                        else
                            reaper.MIDI_DeleteNote(dup_take, ns.ni)
                            table.insert(deleted_notes_info, ns)
                        end
                    end

                    -- Update or clean Type 15 NOTE articulation events & Slur events in dup_take
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(dup_take)
                    for ti = text_cnt - 1, 0, -1 do
                        local ok_t, sel_t, mut_t, ppq_t, etype, msg = reaper.MIDI_GetTextSysexEvt(dup_take, ti)
                        if ok_t and etype == 15 and msg then
                            local p_str, ch_str, rest_str = msg:match("^NOTE%s+(%d+)%s+(%d+)%s+(.*)")
                            if p_str and ch_str then
                                local p_num = tonumber(p_str)
                                local ch_num = tonumber(ch_str) or 0
                                -- Check if this matches a kept note
                                local matched_kept = false
                                for _, kn in ipairs(kept_notes_info) do
                                    if kn.pitch == p_num and math.abs(kn.sppq - ppq_t) <= 25 and (kn.chan == ch_num or ch_num == 0) then
                                        matched_kept = true
                                        break
                                    end
                                end
                                if matched_kept then
                                    if normalize_to_voice_1 and ch_num ~= 0 then
                                        local new_msg = string.format("NOTE %d 0 %s", p_num, rest_str)
                                        reaper.MIDI_SetTextSysexEvt(dup_take, ti, sel_t, mut_t, ppq_t, etype, new_msg, true)
                                    end
                                else
                                    reaper.MIDI_DeleteTextSysexEvt(dup_take, ti)
                                end
                            elseif msg:find("^NOTATOR_SLUR") then
                                local s_id, s_ch, rest_sl = msg:match("^NOTATOR_SLUR%s+([%w_]+)%s+(%d+)%s+(.*)")
                                if s_id and s_ch then
                                    local sl_ch = tonumber(s_ch) or 0
                                    if sl_ch == target_chan then
                                        if normalize_to_voice_1 and sl_ch ~= 0 then
                                            local new_sl_msg = string.format("NOTATOR_SLUR %s 0 %s", s_id, rest_sl)
                                            reaper.MIDI_SetTextSysexEvt(dup_take, ti, sel_t, mut_t, ppq_t, etype, new_sl_msg, true)
                                        end
                                    else
                                        reaper.MIDI_DeleteTextSysexEvt(dup_take, ti)
                                    end
                                end
                            end
                        end
                    end

                    -- Normalize CC / Program Change channel to 0 if normalize_to_voice_1 is active
                    if normalize_to_voice_1 and target_chan ~= 0 then
                        local _, _, cc_cnt = reaper.MIDI_CountEvts(dup_take)
                        for ci = 0, cc_cnt - 1 do
                            local ok_c, sel_c, mut_c, ppq_c, chanmsg, cchan, msg2, msg3 = reaper.MIDI_GetCC(dup_take, ci)
                            if ok_c and cchan == target_chan then
                                reaper.MIDI_SetCC(dup_take, ci, sel_c, mut_c, ppq_c, chanmsg, 0, msg2, msg3, true)
                            end
                        end
                    end

                    reaper.MIDI_Sort(dup_take)

                    -- Run momentary articulation auto-chase on duplicated take
                    local trk_override = state and state.track_articulation_banks and state.track_articulation_banks[dup_guid]
                    local bank = ReaticulateParser and ReaticulateParser.get_bank_for_track(dup_track, all_banks, trk_override)
                    if bank then
                        MidiService.auto_chase_momentary_articulations(dup_take, bank)
                        reaper.MIDI_Sort(dup_take)
                    end

                    if kept_in_item == 0 and dup_item_cnt > 1 then
                        table.insert(items_to_remove, dup_item)
                    end
                end
            end

            -- If track had multiple items and some items had 0 notes for this voice, remove those empty items
            if #items_to_remove < dup_item_cnt then
                for _, rem_it in ipairs(items_to_remove) do
                    if reaper.ValidatePtr(rem_it, "MediaItem*") then
                        reaper.DeleteTrackMediaItem(dup_track, rem_it)
                    end
                end
            end
        end
    end

    -- Remove extracted secondary voice notes from the source track
    if opts.remove_from_source ~= false then
        local src_item_cnt = reaper.CountTrackMediaItems(src_track)
        for it_idx = 0, src_item_cnt - 1 do
            local src_item = reaper.GetTrackMediaItem(src_track, it_idx)
            local src_take = src_item and reaper.GetActiveTake(src_item)
            local snap = item_snapshots[it_idx]

            if src_take and reaper.ValidatePtr(src_take, "MediaItem_Take*") and reaper.TakeIsMIDI(src_take) and snap and snap.is_midi then
                reaper.MIDI_DisableSort(src_take)
                local deleted_from_src = {}

                for n_i = #snap.notes, 1, -1 do
                    local ns = snap.notes[n_i]
                    if ns.in_scope and extracted_voice_set[ns.voice] then
                        reaper.MIDI_DeleteNote(src_take, ns.ni)
                        table.insert(deleted_from_src, ns)
                    end
                end

                -- Remove orphaned Type 15 NOTE events for extracted notes from source take
                if #deleted_from_src > 0 then
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(src_take)
                    for ti = text_cnt - 1, 0, -1 do
                        local ok_t, _, _, ppq_t, etype, msg = reaper.MIDI_GetTextSysexEvt(src_take, ti)
                        if ok_t and etype == 15 and msg then
                            local p_str, ch_str = msg:match("^NOTE%s+(%d+)%s+(%d+)")
                            if p_str then
                                local p_num = tonumber(p_str)
                                local ch_num = tonumber(ch_str) or 0
                                for _, dn in ipairs(deleted_from_src) do
                                    if dn.pitch == p_num and math.abs(dn.sppq - ppq_t) <= 25 and (dn.chan == ch_num or extracted_voice_set[ch_num + 1]) then
                                        reaper.MIDI_DeleteTextSysexEvt(src_take, ti)
                                        break
                                    end
                                end
                            elseif msg:find("^NOTATOR_SLUR") then
                                local _, s_ch = msg:match("^NOTATOR_SLUR%s+([%w_]+)%s+(%d+)")
                                if s_ch and extracted_voice_set[(tonumber(s_ch) or 0) + 1] then
                                    reaper.MIDI_DeleteTextSysexEvt(src_take, ti)
                                end
                            end
                        end
                    end
                end

                reaper.MIDI_Sort(src_take)

                local trk_override = state and state.track_articulation_banks and state.track_articulation_banks[src_guid]
                local bank = ReaticulateParser and ReaticulateParser.get_bank_for_track(src_track, all_banks, trk_override)
                if bank then
                    MidiService.auto_chase_momentary_articulations(src_take, bank)
                    reaper.MIDI_Sort(src_take)
                end
            end
        end
    end

    -- Restore selection to source track
    reaper.SetOnlyTrackSelected(src_track)
    reaper.PreventUIRefresh(-1)
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateArrange()

    MidiService.invalidate_cache()
    if state then
        state.active_tracks_cache = nil
        state.selected_notes = {}
        state.selected_note = nil
        state.focused_track = src_track
    end

    local summary_msg = string.format(
        "Divisi: Split %d voice(s) onto %d duplicated track(s) (%d notes moved, Voice %d kept on '%s')",
        #secondary_voices, #created_tracks, total_extracted_notes, primary_voice_info.voice, base_name
    )
    if state then
        state.status_msg = summary_msg
    end

    reaper.Undo_EndBlock2(0, string.format("Notator: Divisi (%d Voices to Duplicated Tracks)", #secondary_voices + 1), -1)
    return true, summary_msg
end

return DivisiService

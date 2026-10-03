-- ==============================================================================
-- REAPER Native Notator - Service: ScaleService
-- Manages scale definitions, chord parsing, live scale transposition,
-- target track filtering, native MIDI note modifications, and
-- reversible original pitch restoration (NOTATOR_CHORD_ORIG).
-- ==============================================================================

local ChordItem = require("classes.chord_item")

local ScaleService = {}

ScaleService.ROOT_NAMES = { "C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }

local ROOT_MAP = {
    c = 0, ["c#"] = 1, db = 1,
    d = 2, ["d#"] = 3, eb = 3,
    e = 4,
    f = 5, ["f#"] = 6, gb = 6,
    g = 7, ["g#"] = 8, ab = 8,
    a = 9, ["a#"] = 10, bb = 10,
    b = 11, h = 11
}

ScaleService.SCALES = {
    major = {
        name = "Major / Ionian",
        short_name = "maj",
        intervals = { 0, 2, 4, 5, 7, 9, 11 },
        desc = "Natural major scale (1 2 3 4 5 6 7)"
    },
    minor = {
        name = "Natural Minor / Aeolian",
        short_name = "m",
        intervals = { 0, 2, 3, 5, 7, 8, 10 },
        desc = "Natural minor scale (1 2 b3 4 5 b6 b7)"
    },
    harmonic_minor = {
        name = "Harmonic Minor",
        short_name = "m(maj7)",
        intervals = { 0, 2, 3, 5, 7, 8, 11 },
        desc = "Classical harmonic minor with leading tone (1 2 b3 4 5 b6 7)"
    },
    melodic_minor = {
        name = "Melodic Minor (Jazz)",
        short_name = "m6",
        intervals = { 0, 2, 3, 5, 7, 9, 11 },
        desc = "Ascending melodic minor (1 2 b3 4 5 6 7)"
    },
    dorian = {
        name = "Dorian",
        short_name = "m7",
        intervals = { 0, 2, 3, 5, 7, 9, 10 },
        desc = "Minor mode with natural 6th (1 2 b3 4 5 6 b7)"
    },
    phrygian = {
        name = "Phrygian",
        short_name = "phryg",
        intervals = { 0, 1, 3, 5, 7, 8, 10 },
        desc = "Spanish / flamenco minor with flat 2nd (1 b2 b3 4 5 b6 b7)"
    },
    lydian = {
        name = "Lydian",
        short_name = "lyd",
        intervals = { 0, 2, 4, 6, 7, 9, 11 },
        desc = "Bright major mode with raised 4th (1 2 3 #4 5 6 7)"
    },
    mixolydian = {
        name = "Mixolydian (Dominant 7th)",
        short_name = "7",
        intervals = { 0, 2, 4, 5, 7, 9, 10 },
        desc = "Dominant scale with flat 7th (1 2 3 4 5 6 b7)"
    },
    locrian = {
        name = "Locrian",
        short_name = "m7b5",
        intervals = { 0, 1, 3, 5, 6, 8, 10 },
        desc = "Diminished mode with flat 2nd and flat 5th (1 b2 b3 4 b5 b6 b7)"
    },
    pentatonic_maj = {
        name = "Major Pentatonic",
        short_name = "5maj",
        intervals = { 0, 2, 4, 7, 9 },
        desc = "5-tone folk and pop scale (1 2 3 5 6)"
    },
    pentatonic_min = {
        name = "Minor Pentatonic",
        short_name = "5min",
        intervals = { 0, 3, 5, 7, 10 },
        desc = "5-tone rock and blues foundation (1 b3 4 5 b7)"
    },
    blues = {
        name = "Blues Scale",
        short_name = "blues",
        intervals = { 0, 3, 5, 6, 7, 10 },
        desc = "Minor pentatonic with blue note #4/b5 (1 b3 4 b5 5 b7)"
    },
    whole_tone = {
        name = "Whole Tone",
        short_name = "wt",
        intervals = { 0, 2, 4, 6, 8, 10 },
        desc = "Symmetrical whole tone impressionist scale"
    },
    diminished_wh = {
        name = "Diminished (Whole-Half)",
        short_name = "dim",
        intervals = { 0, 2, 3, 5, 6, 8, 9, 11 },
        desc = "8-tone diminished scale for dim7 chords"
    },
    diminished_hw = {
        name = "Diminished (Half-Whole)",
        short_name = "7b9",
        intervals = { 0, 1, 3, 4, 6, 7, 9, 10 },
        desc = "8-tone diminished scale for altered dominants"
    }
}

ScaleService.SCALE_ORDER = {
    "major", "minor", "harmonic_minor", "melodic_minor",
    "dorian", "phrygian", "lydian", "mixolydian", "locrian",
    "pentatonic_maj", "pentatonic_min", "blues",
    "whole_tone", "diminished_wh", "diminished_hw"
}

-- ------------------------------------------------------------------------------
-- Lead-Sheet / Chord Text Parser
-- Parses strings like "Am", "C", "F#m", "G7", "D dorian", "Bbmaj7"
-- ------------------------------------------------------------------------------
function ScaleService.parse_chord_text(text)
    if not text or text == "" then
        return { root = 0, root_name = "C", scale_type = "major", text = "C" }
    end

    local clean = text:gsub("^%s+", ""):gsub("%s+$", "")
    local root_str, suffix = clean:match("^([A-Ga-g][#b]?)(.*)$")
    if not root_str then
        return { root = 0, root_name = "C", scale_type = "major", text = clean }
    end

    local r_key = root_str:lower()
    local root_pitch = ROOT_MAP[r_key] or 0
    local root_name = ScaleService.ROOT_NAMES[root_pitch + 1] or root_str:upper()
    local suf_low = (suffix or ""):lower():gsub("^%s+", "")

    local scale_type = "major"
    if suf_low:find("dorian") then
        scale_type = "dorian"
    elseif suf_low:find("phryg") then
        scale_type = "phrygian"
    elseif suf_low:find("lyd") then
        scale_type = "lydian"
    elseif suf_low:find("mixo") then
        scale_type = "mixolydian"
    elseif suf_low:find("locr") then
        scale_type = "locrian"
    elseif suf_low:find("harm") then
        scale_type = "harmonic_minor"
    elseif suf_low:find("melod") then
        scale_type = "melodic_minor"
    elseif suf_low:find("blues") then
        scale_type = "blues"
    elseif suf_low:find("penta") then
        if suf_low:find("min") or suf_low:find("m") then
            scale_type = "pentatonic_min"
        else
            scale_type = "pentatonic_maj"
        end
    elseif suf_low:find("dim") or suf_low:find("°") or suf_low:find("o") then
        scale_type = "diminished_wh"
    elseif suf_low:find("whole") or suf_low:find("wt") then
        scale_type = "whole_tone"
    elseif suf_low:match("^m7b5") or suf_low:find("ø") then
        scale_type = "locrian"
    elseif suf_low:match("^maj") or suf_low:match("^Δ") or suf_low:match("^%^7") then
        scale_type = "major"
    elseif suf_low:match("^m7") or suf_low:match("^min7") or suf_low:match("^%-7") then
        scale_type = "dorian"
    elseif suf_low:match("^m") or suf_low:match("^min") or suf_low:match("^%-") then
        scale_type = "minor"
    elseif suf_low:match("^7") or suf_low:match("^9") or suf_low:match("^13") then
        scale_type = "mixolydian"
    elseif suf_low:match("^sus") then
        scale_type = "mixolydian"
    else
        scale_type = "major"
    end

    return {
        root = root_pitch,
        root_name = root_name,
        scale_type = scale_type,
        text = clean
    }
end

-- ------------------------------------------------------------------------------
-- Snap pitch to scale
-- Transposes a single note pitch (0..127) to the nearest scale degree.
-- Ties (equidistant pitches like F between E and F# in D-major) resolve
-- to Chord Tones (e.g. F# is the 3rd of D) and conform to sharp/flat key direction.
-- ------------------------------------------------------------------------------
local SHARP_ROOTS = { [7] = true, [2] = true, [9] = true, [4] = true, [11] = true, [6] = true } -- G, D, A, E, B, F#

local function get_chord_tones(root, scale_type)
    local r = (root or 0) % 12
    local sdef = ScaleService.SCALES[scale_type] or ScaleService.SCALES["major"]
    local iv = sdef and sdef.intervals or { 0, 2, 4, 5, 7, 9, 11 }
    local ct = { [r] = true }
    if iv[3] then ct[(r + iv[3]) % 12] = true end -- 3rd degree
    if iv[5] then ct[(r + iv[5]) % 12] = true end -- 5th degree
    if iv[7] then ct[(r + iv[7]) % 12] = true end -- 7th degree
    return ct
end

function ScaleService.snap_pitch_to_scale(pitch, root, scale_type)
    local sdef = ScaleService.SCALES[scale_type] or ScaleService.SCALES["major"]
    local intervals = sdef.intervals

    local in_scale = {}
    for _, iv in ipairs(intervals) do
        in_scale[(root + iv) % 12] = true
    end

    local pc = pitch % 12
    if in_scale[pc] then
        return pitch
    end

    local chord_tones = get_chord_tones(root, scale_type)
    local is_sharp_key = SHARP_ROOTS[root % 12] == true

    local best_pitch = pitch

    for d = 1, 6 do
        local pc_down = (pitch - d) % 12
        local pc_up   = (pitch + d) % 12
        local in_down = in_scale[pc_down]
        local in_up   = in_scale[pc_up]

        if in_down and in_up then
            local ct_down = chord_tones[pc_down]
            local ct_up   = chord_tones[pc_up]
            if ct_up and not ct_down then
                best_pitch = pitch + d
                break
            elseif ct_down and not ct_up then
                best_pitch = pitch - d
                break
            elseif is_sharp_key then
                best_pitch = pitch + d
                break
            else
                best_pitch = pitch - d
                break
            end
        elseif in_down then
            best_pitch = pitch - d
            break
        elseif in_up then
            best_pitch = pitch + d
            break
        end
    end

    return math.max(0, math.min(127, best_pitch))
end

-- ------------------------------------------------------------------------------
-- Target Track Management
-- Determines which tracks are transposed by chord items
-- ------------------------------------------------------------------------------
function ScaleService.is_track_targeted(state, track_guid)
    if not track_guid or track_guid == "" then return true end
    if not state or not state.chord_target_tracks then return true end
    if state.chord_target_tracks[track_guid] == false then
        return false
    end
    return true
end

function ScaleService.set_track_targeted(state, track_guid, targeted)
    if not state.chord_target_tracks then
        state.chord_target_tracks = {}
    end
    state.chord_target_tracks[track_guid] = (targeted == true)
    ScaleService.save_chord_items(state)
end

function ScaleService.set_all_tracks_targeted(state, targeted)
    state.chord_target_tracks = {}
    if not targeted then
        local trk_count = reaper.CountTracks(0)
        for i = 0, trk_count - 1 do
            local trk = reaper.GetTrack(0, i)
            if trk then
                local guid = reaper.GetTrackGUID(trk)
                state.chord_target_tracks[guid] = false
            end
        end
    end
    ScaleService.save_chord_items(state)
end

-- ------------------------------------------------------------------------------
-- Meta Event / Original Pitch Restoration Helpers
-- ------------------------------------------------------------------------------
local function get_take_chord_tags(take)
    local tags_by_trans = {}
    local tags_by_orig  = {}
    local tags_by_time  = {}
    local all_tags = {}

    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
    for i = 0, text_cnt - 1 do
        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, i)
        if ok and ev_type == 15 and msg then
            local orig_p, ch, trans_p = msg:match("^NOTATOR_CHORD_ORIG%s+(%d+)%s+(%d+)%s*(%d*)")
            if orig_p then
                local o_pitch = tonumber(orig_p)
                local channel = tonumber(ch) or 0
                local t_pitch = (trans_p and trans_p ~= "") and tonumber(trans_p) or nil
                local rounded_ppq = math.floor(ppq + 0.5)
                local tag_data = {
                    idx = i,
                    ppq = ppq,
                    rounded_ppq = rounded_ppq,
                    orig_pitch = o_pitch,
                    chan = channel,
                    trans_pitch = t_pitch
                }
                table.insert(all_tags, tag_data)

                local time_key = string.format("%d_%d", rounded_ppq, channel)
                if not tags_by_time[time_key] then
                    tags_by_time[time_key] = {}
                end
                table.insert(tags_by_time[time_key], tag_data)

                if t_pitch ~= nil then
                    local trans_key = string.format("%d_%d_%d", rounded_ppq, channel, t_pitch)
                    tags_by_trans[trans_key] = tag_data
                end
                local orig_key = string.format("%d_%d_%d", rounded_ppq, channel, o_pitch)
                tags_by_orig[orig_key] = tag_data
            end
        end
    end
    return {
        by_trans = tags_by_trans,
        by_orig  = tags_by_orig,
        by_time  = tags_by_time,
        all      = all_tags,
        count    = #all_tags
    }
end

-- ------------------------------------------------------------------------------
-- Apply a ChordItem to target tracks
-- ------------------------------------------------------------------------------
function ScaleService.apply_chord_item_to_target_tracks(state, chord_item)
    if not chord_item then return end
    local parsed = ScaleService.parse_chord_text(chord_item.text)
    local root = parsed.root
    local scale_type = parsed.scale_type
    chord_item.root = root
    chord_item.scale_type = scale_type

    local start_qn = chord_item.start_qn
    local end_qn   = chord_item.end_qn

    local trk_count = reaper.CountTracks(0)
    local any_changed = false

    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            if ScaleService.is_track_targeted(state, trk_guid) then
                local item_count = reaper.CountTrackMediaItems(trk)
                for ii = 0, item_count - 1 do
                    local item = reaper.GetTrackMediaItem(trk, ii)
                    local take = item and reaper.GetActiveTake(item)
                    if take and reaper.TakeIsMIDI(take) then
                        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                        local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                        local i_start_qn = reaper.TimeMap2_timeToQN(0, item_pos)
                        local i_end_qn = reaper.TimeMap2_timeToQN(0, item_pos + item_len)

                        if i_end_qn > (start_qn - 0.05) and i_start_qn < (end_qn + 0.05) then
                            reaper.MIDI_DisableSort(take)
                            local tags = get_take_chord_tags(take)
                            local note_count = select(1, reaper.MIDI_CountEvts(take))
                            local take_modified = false

                            for n_idx = 0, note_count - 1 do
                                local ok, sel, muted, start_ppq, end_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n_idx)
                                if ok then
                                    local n_qn = reaper.MIDI_GetProjQNFromPPQPos(take, start_ppq)
                                    if n_qn >= (start_qn - 0.05) and n_qn < (end_qn - 0.005) then
                                        local rounded_ppq = math.floor(start_ppq + 0.5)
                                        local trans_key = string.format("%d_%d_%d", rounded_ppq, chan, pitch)
                                        local orig_key  = string.format("%d_%d_%d", rounded_ppq, chan, pitch)
                                        local time_key  = string.format("%d_%d", rounded_ppq, chan)

                                        local existing_tag = tags.by_trans[trans_key] or tags.by_orig[orig_key]
                                        if not existing_tag and tags.by_time[time_key] then
                                            for _, t in ipairs(tags.by_time[time_key]) do
                                                if not t.claimed then
                                                    existing_tag = t
                                                    t.claimed = true
                                                    break
                                                end
                                            end
                                        end

                                        local orig_pitch = existing_tag and existing_tag.orig_pitch or pitch
                                        local new_pitch = ScaleService.snap_pitch_to_scale(orig_pitch, root, scale_type)

                                        if not existing_tag then
                                            local tag_msg = string.format("NOTATOR_CHORD_ORIG %d %d %d", orig_pitch, chan, new_pitch)
                                            reaper.MIDI_InsertTextSysexEvt(take, false, false, start_ppq, 15, tag_msg)
                                            local new_tag = {
                                                ppq = start_ppq,
                                                rounded_ppq = rounded_ppq,
                                                orig_pitch = orig_pitch,
                                                chan = chan,
                                                trans_pitch = new_pitch,
                                                claimed = true
                                            }
                                            tags.by_trans[string.format("%d_%d_%d", rounded_ppq, chan, new_pitch)] = new_tag
                                            tags.by_orig[string.format("%d_%d_%d", rounded_ppq, chan, orig_pitch)] = new_tag
                                            take_modified = true
                                            any_changed = true
                                        elseif existing_tag.trans_pitch ~= new_pitch then
                                            local tag_msg = string.format("NOTATOR_CHORD_ORIG %d %d %d", orig_pitch, chan, new_pitch)
                                            if existing_tag.idx then
                                                reaper.MIDI_SetTextSysexEvt(take, existing_tag.idx, false, false, start_ppq, 15, tag_msg, true)
                                                take_modified = true
                                                any_changed = true
                                            end
                                            existing_tag.trans_pitch = new_pitch
                                        end

                                        if new_pitch ~= pitch then
                                            reaper.MIDI_SetNote(take, n_idx, sel, muted, start_ppq, end_ppq, chan, new_pitch, vel, true)
                                            take_modified = true
                                            any_changed = true
                                        end
                                    end
                                end
                            end

                            reaper.MIDI_Sort(take)
                            if take_modified then
                                reaper.UpdateItemInProject(item)
                            end
                        end
                    end
                end
            end
        end
    end

    if any_changed then
        reaper.UpdateArrange()
        local MidiService = package.loaded["services.midi_service"] or (package.loaded["modules.services.midi_service"])
        if MidiService and MidiService.invalidate_cache then
            MidiService.invalidate_cache()
        end
    end
end

-- ------------------------------------------------------------------------------
-- Revert notes in range [start_qn, end_qn] back to original pitches
-- ------------------------------------------------------------------------------
function ScaleService.revert_notes_in_range(state, start_qn, end_qn)
    local trk_count = reaper.CountTracks(0)
    local any_changed = false

    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            -- Revert any track that has chord tags, regardless of target filter
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local i_start_qn = reaper.TimeMap2_timeToQN(0, item_pos)
                    local i_end_qn = reaper.TimeMap2_timeToQN(0, item_pos + item_len)

                    if i_end_qn > (start_qn - 0.05) and i_start_qn < (end_qn + 0.05) then
                        local tags = get_take_chord_tags(take)
                        if tags.count > 0 then
                            reaper.MIDI_DisableSort(take)
                            local note_count = select(1, reaper.MIDI_CountEvts(take))
                            local take_modified = false

                            for n_idx = 0, note_count - 1 do
                                local ok, sel, muted, start_ppq, end_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n_idx)
                                if ok then
                                    local n_qn = reaper.MIDI_GetProjQNFromPPQPos(take, start_ppq)
                                    if n_qn >= (start_qn - 0.05) and n_qn < (end_qn - 0.005) then
                                        local rounded_ppq = math.floor(start_ppq + 0.5)
                                        local trans_key = string.format("%d_%d_%d", rounded_ppq, chan, pitch)
                                        local orig_key  = string.format("%d_%d_%d", rounded_ppq, chan, pitch)
                                        local time_key  = string.format("%d_%d", rounded_ppq, chan)

                                        local tag = tags.by_trans[trans_key] or tags.by_orig[orig_key]
                                        if not tag and tags.by_time[time_key] then
                                            for _, t in ipairs(tags.by_time[time_key]) do
                                                if not t.revert_claimed then
                                                    tag = t
                                                    t.revert_claimed = true
                                                    break
                                                end
                                            end
                                        end

                                        if tag and tag.orig_pitch then
                                            tag.revert_claimed = true
                                            if tag.orig_pitch ~= pitch then
                                                reaper.MIDI_SetNote(take, n_idx, sel, muted, start_ppq, end_ppq, chan, tag.orig_pitch, vel, true)
                                                take_modified = true
                                                any_changed = true
                                            end
                                        end
                                    end
                                end
                            end

                            -- Delete NOTATOR_CHORD_ORIG text events in this range
                            local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                            for t_idx = text_cnt - 1, 0, -1 do
                                local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, t_idx)
                                if ok and ev_type == 15 and msg:match("^NOTATOR_CHORD_ORIG") then
                                    local t_qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                                    if t_qn >= (start_qn - 0.05) and t_qn < (end_qn - 0.005) then
                                        reaper.MIDI_DeleteTextSysexEvt(take, t_idx)
                                        take_modified = true
                                        any_changed = true
                                    end
                                end
                            end

                            reaper.MIDI_Sort(take)
                            if take_modified then
                                reaper.UpdateItemInProject(item)
                            end
                        end
                    end
                end
            end
        end
    end

    if any_changed then
        reaper.UpdateArrange()
        local MidiService = package.loaded["services.midi_service"] or (package.loaded["modules.services.midi_service"])
        if MidiService and MidiService.invalidate_cache then
            MidiService.invalidate_cache()
        end
    end
end

-- ------------------------------------------------------------------------------
-- Revert all orphaned notes (with NOTATOR_CHORD_ORIG not in any chord_item)
-- ------------------------------------------------------------------------------
function ScaleService.revert_orphaned_chord_notes(state)
    local chord_items = ScaleService.get_chord_items(state)
    local trk_count = reaper.CountTracks(0)
    local any_changed = false

    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local tags = get_take_chord_tags(take)
                    if tags.count > 0 then
                        reaper.MIDI_DisableSort(take)
                        local note_count = select(1, reaper.MIDI_CountEvts(take))
                        local take_modified = false

                        for n_idx = 0, note_count - 1 do
                            local ok, sel, muted, start_ppq, end_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, n_idx)
                            if ok then
                                local n_qn = reaper.MIDI_GetProjQNFromPPQPos(take, start_ppq)
                                local is_covered = false
                                for _, ci in ipairs(chord_items) do
                                    if n_qn >= (ci.start_qn - 0.05) and n_qn < (ci.end_qn - 0.005) then
                                        is_covered = true
                                        break
                                    end
                                end

                                if not is_covered then
                                    local rounded_ppq = math.floor(start_ppq + 0.5)
                                    local trans_key = string.format("%d_%d_%d", rounded_ppq, chan, pitch)
                                    local orig_key  = string.format("%d_%d_%d", rounded_ppq, chan, pitch)
                                    local time_key  = string.format("%d_%d", rounded_ppq, chan)

                                    local tag = tags.by_trans[trans_key] or tags.by_orig[orig_key]
                                    if not tag and tags.by_time[time_key] then
                                        for _, t in ipairs(tags.by_time[time_key]) do
                                            if not t.orphan_claimed then
                                                tag = t
                                                t.orphan_claimed = true
                                                break
                                            end
                                        end
                                    end

                                    if tag and tag.orig_pitch then
                                        tag.orphan_claimed = true
                                        if tag.orig_pitch ~= pitch then
                                            reaper.MIDI_SetNote(take, n_idx, sel, muted, start_ppq, end_ppq, chan, tag.orig_pitch, vel, true)
                                            take_modified = true
                                            any_changed = true
                                        end
                                    end
                                end
                            end
                        end

                        -- Delete orphaned NOTATOR_CHORD_ORIG text events not covered by any chord item
                        local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                        for t_idx = text_cnt - 1, 0, -1 do
                            local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, t_idx)
                            if ok and ev_type == 15 and msg:match("^NOTATOR_CHORD_ORIG") then
                                local t_qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                                local is_covered = false
                                for _, ci in ipairs(chord_items) do
                                    if t_qn >= (ci.start_qn - 0.05) and t_qn < (ci.end_qn - 0.005) then
                                        is_covered = true
                                        break
                                    end
                                end
                                if not is_covered then
                                    reaper.MIDI_DeleteTextSysexEvt(take, t_idx)
                                    take_modified = true
                                    any_changed = true
                                end
                            end
                        end

                        reaper.MIDI_Sort(take)
                        if take_modified then
                            reaper.UpdateItemInProject(item)
                        end
                    end
                end
            end
        end
    end

    if any_changed then
        reaper.UpdateArrange()
        local MidiService = package.loaded["services.midi_service"] or (package.loaded["modules.services.midi_service"])
        if MidiService and MidiService.invalidate_cache then
            MidiService.invalidate_cache()
        end
    end
end

-- ------------------------------------------------------------------------------
-- Add, update, delete ChordItems
-- ------------------------------------------------------------------------------
function ScaleService.get_chord_items(state)
    return (state and state.chord_items) or {}
end

function ScaleService.add_chord_item(state, text_or_s, s_or_e, e_or_text, maybe_text)
    if type(text_or_s) == "string" then
        return ScaleService.create_chord_item(state, s_or_e, e_or_text, text_or_s)
    else
        return ScaleService.create_chord_item(state, text_or_s, s_or_e, e_or_text or maybe_text)
    end
end

function ScaleService.create_chord_item(state, start_qn, end_qn, text)
    if not state.chord_items then state.chord_items = {} end
    local parsed = ScaleService.parse_chord_text(text or "C")
    local ci = ChordItem.new({
        start_qn = math.max(0.0, start_qn or 0.0),
        end_qn = math.max((start_qn or 0.0) + 1.0, end_qn or ((start_qn or 0.0) + 4.0)),
        text = parsed.text,
        root = parsed.root,
        scale_type = parsed.scale_type
    })
    table.insert(state.chord_items, ci)
    ScaleService.save_chord_items(state)
    ScaleService.apply_chord_item_to_target_tracks(state, ci)
    reaper.Undo_OnStateChange2(0, "Notator: Add Chord Item (" .. ci.text .. ")")
    return ci
end

function ScaleService.update_chord_text(state, item_id, new_text)
    if not state.chord_items then return end
    for _, ci in ipairs(state.chord_items) do
        if ci.id == item_id then
            ci.text = tostring(new_text or "C")
            local parsed = ScaleService.parse_chord_text(ci.text)
            ci.root = parsed.root
            ci.scale_type = parsed.scale_type
            ScaleService.apply_chord_item_to_target_tracks(state, ci)
            break
        end
    end
    ScaleService.save_chord_items(state)
    reaper.Undo_OnStateChange2(0, "Notator: Edit Chord Item")
end

function ScaleService.delete_chord_item(state, item_id, revert_notes)
    if not state.chord_items then return end
    local found_item = nil
    for i = #state.chord_items, 1, -1 do
        local ci = state.chord_items[i]
        if ci.id == item_id then
            found_item = ci
            table.remove(state.chord_items, i)
            break
        end
    end

    if found_item and revert_notes then
        -- 1. Revert all notes in the deleted chord item's range
        ScaleService.revert_notes_in_range(state, found_item.start_qn, found_item.end_qn)

        -- 2. Re-apply remaining chord items that overlapped this range
        for _, other_ci in ipairs(state.chord_items) do
            if other_ci.end_qn > found_item.start_qn and other_ci.start_qn < found_item.end_qn then
                ScaleService.apply_chord_item_to_target_tracks(state, other_ci)
            end
        end

        -- 3. Clean up any remaining orphaned tags
        ScaleService.revert_orphaned_chord_notes(state)
    end

    if state.selected_chord_item and state.selected_chord_item.id == item_id then
        state.selected_chord_item = nil
    end

    ScaleService.save_chord_items(state)
    reaper.Undo_OnStateChange2(0, "Notator: Delete Chord Item" .. (revert_notes and " (Reverted)" or ""))
end

function ScaleService.clear_all_chord_items(state, revert_notes)
    if not state.chord_items then return end
    if revert_notes then
        for _, ci in ipairs(state.chord_items) do
            ScaleService.revert_notes_in_range(state, ci.start_qn, ci.end_qn)
        end
        ScaleService.revert_orphaned_chord_notes(state)
    end
    state.chord_items = {}
    state.selected_chord_item = nil
    ScaleService.save_chord_items(state)
    reaper.Undo_OnStateChange2(0, "Notator: Clear Chord Track" .. (revert_notes and " (Reverted)" or ""))
end

-- ------------------------------------------------------------------------------
-- Free Scale Transposition for Selection (Used by Sidebar Scale Modal)
-- ------------------------------------------------------------------------------
function ScaleService.transpose_selection_to_scale(state, root, scale_type)
    local has_multi = (state:count_selected_notes() > 0)
    local target_notes = {}

    if has_multi then
        for _, n in pairs(state.selected_notes) do
            table.insert(target_notes, n)
        end
    elseif state.selected_note then
        table.insert(target_notes, state.selected_note)
    end

    if #target_notes == 0 then
        state.status_msg = "Scale Transpose: No notes selected!"
        return false
    end

    reaper.Undo_BeginBlock2(0)

    -- Group notes by take
    local by_take = {}
    for _, n in ipairs(target_notes) do
        if n.take and reaper.ValidatePtr(n.take, "MediaItem_Take*") then
            by_take[n.take] = by_take[n.take] or {}
            table.insert(by_take[n.take], n)
        end
    end

    local changed_count = 0
    for take, n_list in pairs(by_take) do
        reaper.MIDI_DisableSort(take)
        local note_cnt = select(1, reaper.MIDI_CountEvts(take))

        for _, sn in ipairs(n_list) do
            local found_idx = nil
            if sn.idx and sn.idx < note_cnt then
                local ok, _, _, start_ppq, _, _, p = reaper.MIDI_GetNote(take, sn.idx)
                if ok and p == sn.pitch and math.abs(reaper.MIDI_GetProjQNFromPPQPos(take, start_ppq) - sn.start_qn) < 0.05 then
                    found_idx = sn.idx
                end
            end
            if not found_idx then
                for i = 0, note_cnt - 1 do
                    local ok, _, _, start_ppq, _, chan, p = reaper.MIDI_GetNote(take, i)
                    if ok and p == sn.pitch and math.abs(reaper.MIDI_GetProjQNFromPPQPos(take, start_ppq) - sn.start_qn) < 0.05 then
                        found_idx = i
                        break
                    end
                end
            end

            if found_idx then
                local ok, sel, muted, sppq, eppq, ch, cur_p, vel = reaper.MIDI_GetNote(take, found_idx)
                if ok then
                    local new_p = ScaleService.snap_pitch_to_scale(cur_p, root, scale_type)
                    if new_p ~= cur_p then
                        reaper.MIDI_SetNote(take, found_idx, sel, muted, sppq, eppq, ch, new_p, vel, true)
                        sn.pitch = new_p
                        changed_count = changed_count + 1
                    end
                end
            end
        end

        reaper.MIDI_Sort(take)
        local item = reaper.GetMediaItemTake_Item(take)
        if item then reaper.UpdateItemInProject(item) end
    end

    reaper.Undo_EndBlock2(0, string.format("Notator: Transpose to %s %s (%d notes)", ScaleService.ROOT_NAMES[root + 1], scale_type, changed_count), -1)
    reaper.UpdateArrange()

    local sname = ScaleService.SCALES[scale_type] and ScaleService.SCALES[scale_type].name or scale_type
    state.status_msg = string.format("Scale Transpose applied: %s %s (%d notes updated)", ScaleService.ROOT_NAMES[root + 1], sname, changed_count)
    return true
end

-- ------------------------------------------------------------------------------
-- Project Persistence (reaper.SetProjExtState)
-- ------------------------------------------------------------------------------
function ScaleService.save_chord_items(state)
    local items = state.chord_items or {}
    local parts = {}
    for _, ci in ipairs(items) do
        -- Format: id|start_qn|end_qn|root|scale_type|text
        local text_clean = (ci.text or "C"):gsub("|", "_"):gsub(";", "_")
        table.insert(parts, string.format("%s|%.3f|%.3f|%d|%s|%s",
            tostring(ci.id or ""),
            ci.start_qn or 0.0,
            ci.end_qn or 4.0,
            ci.root or 0,
            tostring(ci.scale_type or "major"),
            text_clean
        ))
    end
    local raw_items = table.concat(parts, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "chord_items", raw_items)

    -- Target tracks
    if state.chord_target_tracks then
        local t_parts = {}
        for guid, val in pairs(state.chord_target_tracks) do
            if val then table.insert(t_parts, guid) end
        end
        reaper.SetProjExtState(0, "REAPER_Notator", "chord_target_tracks", table.concat(t_parts, ";"))
    end

    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
end

function ScaleService.load_chord_items(state)
    state.chord_items = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "chord_items")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id         = parts[1]
            local start_qn   = tonumber(parts[2]) or 0.0
            local end_qn     = tonumber(parts[3]) or 4.0
            local root       = tonumber(parts[4]) or 0
            local scale_type = parts[5] or "major"
            local text       = parts[6] or "C"

            if id and id ~= "" then
                table.insert(state.chord_items, ChordItem.new({
                    id         = id,
                    start_qn   = start_qn,
                    end_qn     = end_qn,
                    root       = root,
                    scale_type = scale_type,
                    text       = text
                }))
            end
        end
    end

    -- Target tracks
    state.chord_target_tracks = {}
    local _, raw_targets = reaper.GetProjExtState(0, "REAPER_Notator", "chord_target_tracks")
    if raw_targets and raw_targets ~= "" then
        for guid in raw_targets:gmatch("([^;]+)") do
            if guid and guid ~= "" then
                state.chord_target_tracks[guid] = true
            end
        end
    end
end

-- ------------------------------------------------------------------------------
-- Test MIDI Case Generator for Chord Snapping Verification
-- ------------------------------------------------------------------------------
function ScaleService.insert_test_midi_case(state, start_measure, track)
    local target_m = start_measure or 1
    local bpi = 4.0
    local start_qn = (target_m - 1) * bpi

    local trk = track or (state and state.focused_track) or reaper.GetSelectedTrack(0, 0) or reaper.GetTrack(0, 0)
    if not trk then
        reaper.InsertTrackAtIndex(0, true)
        trk = reaper.GetTrack(0, 0)
        reaper.GetSetMediaTrackInfo_String(trk, "P_NAME", "Chord Test Track", true)
    end

    local MidiService = package.loaded["services.midi_service"] or (package.loaded["modules.services.midi_service"]) or require("services.midi_service")
    local item, take = MidiService.get_or_create_item_at_qn(trk, start_qn, 16.0)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return false end

    reaper.Undo_BeginBlock()
    reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", string.format("Chord Test (Bars %d-%d)", target_m, target_m + 3), true)

    -- Bar 1: C4 (60), E4 (64), F4 (65 - will snap in D!), A4 (69)
    -- Bar 2: Chromatic notes: C#4 (61), D#4 (63), F#4 (66), G#4 (68)
    -- Bar 3: C4 (60), D4 (62), F4 (65), B4 (71)
    -- Bar 4: C-Dur Triad C-E-G-C (60, 64, 67, 72)
    local test_pattern = {
        -- Bar 1
        { qn_rel = 0.0, dur = 0.9, pitch = 60 }, -- C4 (snaps to C# in D-Dur)
        { qn_rel = 1.0, dur = 0.9, pitch = 64 }, -- E4 (stays in D-Dur)
        { qn_rel = 2.0, dur = 0.9, pitch = 65 }, -- F4 (snaps to F# in D-Dur!)
        { qn_rel = 3.0, dur = 0.9, pitch = 69 }, -- A4 (stays in D-Dur: Quinte)
        -- Bar 2: Chromatics
        { qn_rel = 4.0, dur = 0.9, pitch = 61 }, -- C#4
        { qn_rel = 5.0, dur = 0.9, pitch = 63 }, -- D#4
        { qn_rel = 6.0, dur = 0.9, pitch = 66 }, -- F#4
        { qn_rel = 7.0, dur = 0.9, pitch = 68 }, -- G#4
        -- Bar 3
        { qn_rel = 8.0, dur = 0.9, pitch = 60 }, -- C4
        { qn_rel = 9.0, dur = 0.9, pitch = 62 }, -- D4
        { qn_rel = 10.0, dur = 0.9, pitch = 65 }, -- F4
        { qn_rel = 11.0, dur = 0.9, pitch = 71 }, -- B4
        -- Bar 4
        { qn_rel = 12.0, dur = 0.9, pitch = 60 }, -- C4
        { qn_rel = 13.0, dur = 0.9, pitch = 64 }, -- E4
        { qn_rel = 14.0, dur = 0.9, pitch = 67 }, -- G4
        { qn_rel = 15.0, dur = 0.9, pitch = 72 }, -- C5
    }

    reaper.MIDI_DisableSort(take)
    for _, tn in ipairs(test_pattern) do
        local n_qn = start_qn + tn.qn_rel
        local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, n_qn)
        local eppq = reaper.MIDI_GetPPQPosFromProjQN(take, n_qn + tn.dur)
        reaper.MIDI_InsertNote(take, false, false, sppq, eppq, 0, tn.pitch, 96, true)
    end
    reaper.MIDI_Sort(take)
    reaper.UpdateItemInProject(item)
    reaper.Undo_EndBlock2(0, "Notator: Insert Test MIDI Case", -1)
    reaper.UpdateArrange()
    if MidiService and MidiService.invalidate_cache then
        MidiService.invalidate_cache()
    end
    if state then
        state.status_msg = string.format("Inserted Test MIDI Item at Bar %d (C, F snap in D-Major; A stays)", target_m)
    end
    return true
end

return ScaleService

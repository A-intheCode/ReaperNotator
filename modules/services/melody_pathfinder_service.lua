-- ==============================================================================
-- REAPER Native Notator - Service: MelodyPathfinderService
-- Algorithmic Melodic Waypoint Inpainting & Contrapuntal Counter-Melody Engine
-- Features:
--   • Clef & Instrument Playable Register Intelligence (Octave-Aware Folding)
--   • Corpus-Trained Markov Interval Weights + Higher-Order Viterbi Pathfinding
--   • 4 Film Composer Style Archetypes (Heroic Fanfare, Mysterious Pivot Pulse,
--     Kinetic Sequence Action, Pastoral Modal Romance) + Leonard Meyer Gap-Fill
--   • Reference Track Harmonic Consonance & Melodic Inversion / Retrograde
-- ==============================================================================

local Constants         = require("constants")
local Engraver          = require("rendering.engraver")
local MelodyStyleCorpus = require("services.melody_style_corpus")
local SlurService       = require("services.slur_service")

local MelodyPathfinderService = {}

MelodyPathfinderService.SCALES = {
    { id = "auto",             name = "Auto (From Track Key Signature / Style)", intervals = nil },
    { id = "major",            name = "Major (Ionian)",                          intervals = { 0, 2, 4, 5, 7, 9, 11 } },
    { id = "aeolian",          name = "Natural Minor (Aeolian)",                 intervals = { 0, 2, 3, 5, 7, 8, 10 } },
    { id = "harmonic_minor",   name = "Harmonic Minor",                          intervals = { 0, 2, 3, 5, 7, 8, 11 } },
    { id = "melodic_minor",    name = "Melodic Minor",                           intervals = { 0, 2, 3, 5, 7, 9, 11 } },
    { id = "dorian",           name = "Dorian (Cinematic / Modal ♮6)",           intervals = { 0, 2, 3, 5, 7, 9, 10 } },
    { id = "phrygian",         name = "Phrygian (Dark / Thriller ♭2)",           intervals = { 0, 1, 3, 5, 7, 8, 10 } },
    { id = "lydian",           name = "Lydian (Wonder / Symphonic ♯4)",          intervals = { 0, 2, 4, 6, 7, 9, 11 } },
    { id = "mixolydian",       name = "Mixolydian (Heroic / Pastoral ♭7)",       intervals = { 0, 2, 4, 5, 7, 9, 10 } },
    { id = "minor_pentatonic", name = "Minor Pentatonic / Action",               intervals = { 0, 3, 5, 7, 10 } },
    { id = "blues_punk",       name = "Blues / Punk (Pentatonic + ♭5)",          intervals = { 0, 3, 5, 6, 7, 10 } },
}

MelodyPathfinderService.TRANSFORMS = {
    { id = "normal",               name = "Normal (Original Contour)" },
    { id = "inversion",            name = "Melodic Inversion (Mirror Intervals)" },
    { id = "retrograde",           name = "Retrograde (Reverse Motif Flow)" },
    { id = "retrograde_inversion", name = "Retrograde-Inversion (Mirror + Reverse)" },
}

-- Playable MIDI compass per Clef ID (prevents generating notes in VSTi keyswitch / silent zones)
local CLEF_RANGES = {
    bass_15mb    = { min_p = 24, max_p = 50, center_p = 36, label = "Bass 15mb" },
    bass_8vb     = { min_p = 28, max_p = 55, center_p = 40, label = "Bass 8vb" },
    tenor_8vb    = { min_p = 36, max_p = 62, center_p = 48, label = "Tenor 8vb" },
    bass         = { min_p = 36, max_p = 64, center_p = 48, label = "Bass Clef" },
    baritone_f   = { min_p = 40, max_p = 67, center_p = 53, label = "Baritone Clef" },
    baritone_c   = { min_p = 40, max_p = 67, center_p = 53, label = "Baritone Clef" },
    tenor        = { min_p = 45, max_p = 72, center_p = 57, label = "Tenor Clef" },
    treble_8vb   = { min_p = 45, max_p = 74, center_p = 57, label = "Treble 8vb" },
    alto         = { min_p = 48, max_p = 76, center_p = 60, label = "Alto Clef" },
    mezzo        = { min_p = 52, max_p = 79, center_p = 64, label = "Mezzo-Soprano Clef" },
    soprano      = { min_p = 55, max_p = 81, center_p = 67, label = "Soprano Clef" },
    treble       = { min_p = 55, max_p = 86, center_p = 67, label = "Treble Clef" },
    french_violin= { min_p = 57, max_p = 88, center_p = 71, label = "French Violin Clef" },
    bass_8va     = { min_p = 48, max_p = 74, center_p = 60, label = "Bass 8va" },
    treble_8va   = { min_p = 67, max_p = 96, center_p = 79, label = "Treble 8va" },
    treble_15ma  = { min_p = 72, max_p = 103, center_p = 84, label = "Treble 15ma" },
    grand        = { min_p = 40, max_p = 86, center_p = 60, label = "Grand Staff" },
    harp_3staff  = { min_p = 38, max_p = 88, center_p = 60, label = "Harp (3 Staves)" },
    percussion_1 = { min_p = 36, max_p = 72, center_p = 48, label = "Percussion Clef" },
    percussion_2 = { min_p = 36, max_p = 72, center_p = 48, label = "Percussion Clef" },
}

local SCALE_BY_ID = {}
for _, sc in ipairs(MelodyPathfinderService.SCALES) do
    SCALE_BY_ID[sc.id] = sc
end

-- Circle of fifths key_idx (-7..+7) to tonic pitch class (0=C .. 11=B)
local KEY_IDX_TO_TONIC_PC = {
    [-7] = 11, [-6] = 6, [-5] = 1, [-4] = 8, [-3] = 3, [-2] = 10, [-1] = 5,
    [0]  = 0,
    [1]  = 7,  [2]  = 2, [3]  = 9, [4]  = 4, [5]  = 11, [6] = 6,  [7]  = 1,
}

--- Deterministic pseudo-random generator (so seed rerolls are 100% reproducible)
local function make_rng(seed)
    local s = math.max(1, math.floor(tonumber(seed) or 12345) % 2147483647)
    return function()
        s = (s * 48271) % 2147483647
        return (s - 1) / 2147483646
    end
end

--- Resolves active target track and selected key notes (waypoints)
--- @param state table
--- @param active_tracks_data table
--- @return MediaTrack|nil, table waypoints, MediaItem_Take|nil
function MelodyPathfinderService.get_selected_waypoints(state, active_tracks_data)
    local raw = {}
    local target_track = (state and state.focused_track and reaper.ValidatePtr(state.focused_track, "MediaTrack*")) and state.focused_track or nil
    local target_take = nil

    if state and state.selected_notes and next(state.selected_notes) ~= nil then
        -- Collect all valid selected notes first, then pick target_track deterministically (earliest note or focused_track)
        local all_sel = {}
        for _, entry in pairs(state.selected_notes) do
            if entry and entry.take and reaper.ValidatePtr(entry.take, "MediaItem_Take*") and entry.idx then
                local ok, _, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(entry.take, entry.idx)
                if ok and not muted then
                    local sqn = reaper.MIDI_GetProjQNFromPPQPos(entry.take, sppq)
                    local eqn = reaper.MIDI_GetProjQNFromPPQPos(entry.take, eppq)
                    local trk = entry.track or reaper.GetMediaItemTake_Track(entry.take)
                    table.insert(all_sel, {
                        pitch = pitch,
                        start_qn = sqn,
                        end_qn = eqn,
                        dur_qn = math.max(0.125, eqn - sqn),
                        vel = vel or 96,
                        chan = chan or 0,
                        take = entry.take,
                        track = trk,
                        idx = entry.idx,
                        is_waypoint = true,
                    })
                end
            end
        end
        table.sort(all_sel, function(a, b)
            if math.abs(a.start_qn - b.start_qn) > 0.02 then
                return a.start_qn < b.start_qn
            end
            return a.pitch > b.pitch
        end)
        if #all_sel > 0 then
            local has_focused = false
            if target_track then
                for _, n in ipairs(all_sel) do
                    if n.track == target_track then
                        has_focused = true
                        break
                    end
                end
            end
            if not has_focused then
                target_track = all_sel[1].track
            end
            for _, n in ipairs(all_sel) do
                if n.track == target_track then
                    if not target_take then target_take = n.take end
                    table.insert(raw, n)
                end
            end
        end
    elseif state and state.selected_note and state.selected_note.take and reaper.ValidatePtr(state.selected_note.take, "MediaItem_Take*") then
        local sn = state.selected_note
        local ok, _, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(sn.take, sn.idx)
        if ok and not muted then
            local sqn = reaper.MIDI_GetProjQNFromPPQPos(sn.take, sppq)
            local eqn = reaper.MIDI_GetProjQNFromPPQPos(sn.take, eppq)
            target_track = sn.track or reaper.GetMediaItemTake_Track(sn.take)
            target_take = sn.take
            table.insert(raw, {
                pitch = pitch,
                start_qn = sqn,
                end_qn = eqn,
                dur_qn = math.max(0.125, eqn - sqn),
                vel = vel or 96,
                chan = chan or 0,
                take = sn.take,
                idx = sn.idx,
                is_waypoint = true,
            })
        end
    end

    if not target_track then
        target_track = (state and state.focused_track)
            or (active_tracks_data and active_tracks_data[1] and active_tracks_data[1].track)
            or reaper.GetSelectedTrack(0, 0)
            or reaper.GetTrack(0, 0)
    end

    if not target_take and state and state.selected_take and reaper.ValidatePtr(state.selected_take, "MediaItem_Take*") then
        if reaper.GetMediaItemTake_Track(state.selected_take) == target_track then
            target_take = state.selected_take
        end
    end

    -- Sort by start_qn; if multiple notes share the exact same onset, keep highest melody note
    table.sort(raw, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.02 then
            return a.start_qn < b.start_qn
        end
        return a.pitch > b.pitch
    end)

    local deduped = {}
    for _, n in ipairs(raw) do
        if #deduped == 0 or math.abs(n.start_qn - deduped[#deduped].start_qn) > 0.04 then
            table.insert(deduped, n)
        end
    end

    if deduped[1] and deduped[1].take then
        target_take = deduped[1].take
    end

    -- If the user just clicked "Insert" in the current Melodic Pathfinder modal session and hasn't
    -- manually changed the canvas selection since, preserve the original session waypoints & start_qn
    -- so subsequent parameter tweaks / re-insertions replace the exact same pattern span without drift!
    if state and state.mpf_locked_sel_sig and state.mpf_locked_waypoints then
        local cur_sig = string.format(
            "%s_%d_%.2f_%.2f",
            tostring(target_take),
            #raw,
            raw[1] and raw[1].start_qn or -1,
            raw[#raw] and raw[#raw].start_qn or -1
        )
        if cur_sig == state.mpf_locked_sel_sig and state.mpf_locked_track == target_track then
            return target_track, state.mpf_locked_waypoints, state.mpf_locked_take or target_take
        else
            -- User selected a different pattern on the canvas -> unlock and adopt the new selection
            state.mpf_locked_sel_sig = nil
            state.mpf_locked_waypoints = nil
            state.mpf_locked_min_qn = nil
            state.mpf_locked_max_qn = nil
            state.mpf_locked_track = nil
            state.mpf_locked_take = nil
        end
    end

    return target_track, deduped, target_take
end

--- Resolves the active Clef & Playable Instrument Register for `target_track` / `target_take`
--- Ensures generated notes & Audition always stay inside the instrument's real acoustic & Clef compass!
function MelodyPathfinderService.get_clef_register(state, target_track, target_take, waypoints, octave_shift)
    local clef_id = nil
    local trk_name = ""

    if target_track and reaper.ValidatePtr(target_track, "MediaTrack*") then
        local _, nm = reaper.GetTrackName(target_track)
        trk_name = nm or ""
        local trk_guid = reaper.GetTrackGUID(target_track)

        -- 1. Check item-level clef first if a take is active
        if target_take and reaper.ValidatePtr(target_take, "MediaItem_Take*") then
            local item = reaper.GetMediaItemTake_Item(target_take)
            if item and state and state.item_clefs then
                local ok_g, iguid = reaper.GetSetMediaItemInfo_String(item, "GUID", "", false)
                if ok_g and iguid and state.item_clefs[iguid] and state.item_clefs[iguid] ~= "auto" then
                    clef_id = state.item_clefs[iguid]
                end
            end
        end

        -- 2. Check track-level clef or auto-detect from Engraver
        if not clef_id or clef_id == "auto" then
            if state and state.track_clefs and trk_guid then
                local saved = state.track_clefs[trk_guid] or state.track_clefs[trk_guid:upper()] or state.track_clefs[trk_guid:lower()]
                if saved and saved ~= "auto" then
                    clef_id = saved
                end
            end
        end

        if not clef_id or clef_id == "auto" then
            -- Gather existing notes on the target track if no waypoints are selected so auto-clef is accurate
            local sample_notes = waypoints
            if not sample_notes or #sample_notes == 0 then
                sample_notes = {}
                local icnt = reaper.CountTrackMediaItems(target_track)
                for ii = 0, math.min(icnt - 1, 3) do
                    local it = reaper.GetTrackMediaItem(target_track, ii)
                    local tk = it and reaper.GetActiveTake(it)
                    if tk and reaper.TakeIsMIDI(tk) then
                        local _, ncnt = reaper.MIDI_CountEvts(tk)
                        for ni = 0, math.min((ncnt or 0) - 1, 32) do
                            local nok, _, muted, _, _, _, p = reaper.MIDI_GetNote(tk, ni)
                            if nok and not muted then
                                table.insert(sample_notes, { pitch = p })
                            end
                        end
                    end
                end
            end
            if Engraver and Engraver.get_track_clef then
                clef_id = Engraver.get_track_clef(target_track, trk_name, sample_notes, state)
            end
        end
    end

    clef_id = clef_id or "treble"
    local base = CLEF_RANGES[clef_id] or CLEF_RANGES.treble
    local min_p = base.min_p
    local max_p = base.max_p
    local center_p = base.center_p
    local clef_def = Constants.CLEF_DEFS and Constants.CLEF_DEFS[clef_id]
    local label = (clef_def and clef_def.name) or base.label or "Treble Clef"

    -- Refine playable VSTi range from instrument keywords in track name (prevents keyswitch triggers!)
    local name_l = trk_name:lower()
    if name_l:find("double bass") or name_l:find("kontrabass") or name_l:find("contrabass") or name_l:match("%f[%a]cb%f[%A]") or name_l:match("%f[%a]db%f[%A]") then
        min_p, max_p, center_p = 28, 57, 41 -- E1 .. A3 (Double Bass playable range)
    elseif name_l:find("timpani") or name_l:find("pauke") then
        min_p, max_p, center_p = 38, 57, 48 -- D2 .. A3 (Orchestral Timpani compass)
    elseif name_l:find("tuba") then
        min_p, max_p, center_p = 29, 58, 43 -- F1 .. Bb3
    elseif name_l:find("cell") or name_l:match("%f[%a]vc%f[%A]") or name_l:match("%f[%a]vlc%f[%A]") then
        if clef_id == "bass" then
            min_p, max_p, center_p = 36, 67, 48 -- C2 .. G4 (Cello playable range)
        end
    elseif name_l:find("bassoon") or name_l:find("fagott") or name_l:match("%f[%a]bsn%f[%A]") then
        min_p, max_p, center_p = 34, 67, 48 -- Bb1 .. G4
    elseif name_l:find("trombone") or name_l:find("posaune") or name_l:match("%f[%a]trb%f[%A]") or name_l:match("%f[%a]tbn%f[%A]") then
        min_p, max_p, center_p = 40, 69, 53 -- E2 .. A4
    elseif name_l:find("horn") or name_l:find("corno") or name_l:match("%f[%a]hn%f[%A]") then
        min_p, max_p, center_p = 43, 77, 60 -- G2 .. F5 (French Horn)
    elseif name_l:find("viola") or name_l:find("bratsche") or name_l:match("%f[%a]vla%f[%A]") then
        min_p, max_p, center_p = 48, 79, 60 -- C3 .. G5 (Viola lowest string C3 = 48)
    elseif name_l:find("violin") or name_l:find("violine") or name_l:find("geige") or name_l:match("%f[%a]vln%f[%A]") then
        min_p, max_p, center_p = 55, 88, 69 -- G3 .. E6 (Violin lowest string G3 = 55!)
    elseif name_l:find("flute") or name_l:find("flöte") or name_l:match("%f[%a]fl%f[%A]") then
        min_p, max_p, center_p = 60, 91, 72 -- C4 .. G6 (Concert Flute lowest note C4 = 60!)
    elseif name_l:find("oboe") or name_l:match("%f[%a]ob%f[%A]") then
        min_p, max_p, center_p = 58, 86, 69 -- Bb3 .. D6
    elseif name_l:find("trumpet") or name_l:find("trompete") or name_l:match("%f[%a]tpt%f[%A]") then
        min_p, max_p, center_p = 54, 84, 67 -- F#3 .. C6
    end

    -- Apply optional user Octave Shift (-2 .. +2 octaves)
    local oct_shift = math.floor(tonumber(octave_shift) or 0)
    if oct_shift ~= 0 then
        local shift_semi = oct_shift * 12
        min_p = math.max(12, math.min(108, min_p + shift_semi))
        max_p = math.max(min_p + 12, math.min(115, max_p + shift_semi))
        center_p = math.max(min_p, math.min(max_p, center_p + shift_semi))
    end

    -- If user explicitly selected Waypoints, expand the register window to include their waypoints
    if waypoints and #waypoints > 0 then
        local wp_sum = 0
        for _, wp in ipairs(waypoints) do
            wp_sum = wp_sum + wp.pitch
            if wp.pitch - 5 < min_p then min_p = math.max(21, wp.pitch - 5) end
            if wp.pitch + 5 > max_p then max_p = math.min(108, wp.pitch + 5) end
        end
        center_p = math.floor((wp_sum / #waypoints) + 0.5)
    end

    return {
        clef_id = clef_id,
        label = label,
        min_p = min_p,
        max_p = max_p,
        center_p = center_p,
    }
end

--- Transposes `pitch` by octaves (±12 semitones) so it preserves its exact pitch class
--- while landing squarely inside `[min_p, max_p]` as close as possible to `prefer_center`.
function MelodyPathfinderService.fold_pitch_into_register(pitch, min_p, max_p, prefer_center)
    pitch = math.floor((tonumber(pitch) or 60) + 0.5)
    min_p = math.floor((tonumber(min_p) or 36) + 0.5)
    max_p = math.max(min_p, math.floor((tonumber(max_p) or 84) + 0.5))
    local pc = pitch % 12
    local center = tonumber(prefer_center) or math.floor((min_p + max_p) * 0.5)
    local best_p = nil
    local best_dist = 999

    for oct = 1, 9 do
        local cand = oct * 12 + pc
        if cand >= min_p and cand <= max_p then
            local d = math.abs(cand - center)
            if d < best_dist then
                best_dist = d
                best_p = cand
            end
        end
    end

    if best_p then return best_p end

    -- Fallback: clamp by ±12 steps toward [min_p, max_p]
    local p = pitch
    local guard = 0
    while p < min_p and guard < 16 do p = p + 12; guard = guard + 1 end
    while p > max_p and guard < 32 do p = p - 12; guard = guard + 1 end
    return math.max(min_p, math.min(max_p, p))
end

--- Resolves the start_qn when 0 notes are selected:
--- Prioritizes the active session anchor or REAPER Edit Cursor position so inserted notes
--- always land at the cursor instead of jumping back to the start of a multi-bar MIDI item.
function MelodyPathfinderService.resolve_default_start_qn(state, target_track, ref_mode, qn_per_bar)
    if state and state.mpf_locked_min_qn then
        return state.mpf_locked_min_qn
    end
    qn_per_bar = qn_per_bar or 4.0
    local cur_sec = reaper.GetCursorPosition()
    local cur_qn = reaper.TimeMap2_timeToQN(0, cur_sec)

    -- Snap Edit Cursor to nearest quarter-note beat (or bar if within 0.08 QN of a barline)
    local snapped_cur_qn = math.floor(cur_qn + 0.08)
    if math.abs(cur_qn - snapped_cur_qn) > 0.15 then
        snapped_cur_qn = math.floor(cur_qn * 4.0 + 0.5) / 4.0
    end
    snapped_cur_qn = math.max(0, snapped_cur_qn)

    -- 1. If a MIDI item on target_track covers the Edit Cursor, start right at `snapped_cur_qn`!
    if target_track and reaper.ValidatePtr(target_track, "MediaTrack*") then
        local icnt = reaper.CountTrackMediaItems(target_track)
        for ii = 0, icnt - 1 do
            local it = reaper.GetTrackMediaItem(target_track, ii)
            if it then
                local pos_qn = reaper.TimeMap2_timeToQN(0, reaper.GetMediaItemInfo_Value(it, "D_POSITION"))
                local end_qn = reaper.TimeMap2_timeToQN(0, reaper.GetMediaItemInfo_Value(it, "D_POSITION") + reaper.GetMediaItemInfo_Value(it, "D_LENGTH"))
                if cur_qn >= pos_qn - 0.1 and cur_qn <= end_qn + 0.1 then
                    return snapped_cur_qn
                end
            end
        end
        -- If `state.selected_item` is on `target_track` and cursor is outside it, align to the selected item's start
        if state and state.selected_item and reaper.ValidatePtr(state.selected_item, "MediaItem*") then
            if reaper.GetMediaItem_Track(state.selected_item) == target_track then
                local pos_qn = reaper.TimeMap2_timeToQN(0, reaper.GetMediaItemInfo_Value(state.selected_item, "D_POSITION"))
                return math.floor(pos_qn * 4.0 + 0.5) / 4.0
            end
        end
    end

    -- 2. Otherwise use the Edit Cursor position directly (snapped to beat/bar)
    return snapped_cur_qn
end

--- Collects MIDI notes from reference track(s) strictly within [min_qn, max_qn]
function MelodyPathfinderService.collect_reference_notes(ref_mode, target_track, min_qn, max_qn)
    local ref_notes = {}
    if not ref_mode or ref_mode == "none" then
        return ref_notes
    end

    local tracks_to_scan = {}
    if type(ref_mode) == "userdata" and reaper.ValidatePtr(ref_mode, "MediaTrack*") then
        table.insert(tracks_to_scan, ref_mode)
    elseif ref_mode == "auto_all" then
        local cnt = reaper.CountTracks(0)
        for ti = 0, cnt - 1 do
            local tr = reaper.GetTrack(0, ti)
            if tr and tr ~= target_track then
                table.insert(tracks_to_scan, tr)
            end
        end
    end

    local q0 = (min_qn or 0) - 0.02
    local q1 = (max_qn or 16) + 0.02

    for _, tr in ipairs(tracks_to_scan) do
        local icnt = reaper.CountTrackMediaItems(tr)
        for ii = 0, icnt - 1 do
            local item = reaper.GetTrackMediaItem(tr, ii)
            local take = item and reaper.GetActiveTake(item)
            if take and reaper.TakeIsMIDI(take) then
                local ok, ncnt = reaper.MIDI_CountEvts(take)
                if ok and ncnt > 0 then
                    for ni = 0, ncnt - 1 do
                        local nok, _, muted, sppq, eppq, _, pitch, vel = reaper.MIDI_GetNote(take, ni)
                        if nok and not muted then
                            local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                            local eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                            if eqn > q0 + 0.04 and sqn < q1 - 0.04 then
                                local c_sqn = math.max(min_qn or 0, sqn)
                                local c_eqn = math.min(max_qn or 16, eqn)
                                table.insert(ref_notes, {
                                    pitch = pitch,
                                    start_qn = c_sqn,
                                    end_qn = c_eqn,
                                    dur_qn = math.max(0.08, c_eqn - c_sqn),
                                    vel = vel or 90,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(ref_notes, function(a, b) return a.start_qn < b.start_qn end)
    return ref_notes
end

--- Builds a sorted list of scale pitches across MIDI 21..108
function MelodyPathfinderService.build_scale_pitches(tonic_pc, scale_id, style_obj)
    local resolved_id = scale_id
    if not resolved_id or resolved_id == "auto" then
        resolved_id = (style_obj and style_obj.default_scale) or "aeolian"
    end
    local sc = SCALE_BY_ID[resolved_id] or SCALE_BY_ID["aeolian"]
    local ivs = sc.intervals or { 0, 2, 3, 5, 7, 8, 10 }
    local pc_set = {}
    for _, iv in ipairs(ivs) do
        pc_set[(tonic_pc + iv) % 12] = true
    end

    local pitches = {}
    local pitch_to_deg = {}
    for p = 21, 108 do
        if pc_set[p % 12] then
            table.insert(pitches, p)
            pitch_to_deg[p] = #pitches
        end
    end
    return pitches, pitch_to_deg, pc_set
end

--- Evaluates harmonic relationship between candidate pitch `p` and reference notes at `qn`
local function score_harmony_at_qn(p, qn, dur_qn, ref_notes, prev_p, harmony_blend, is_counter_melody)
    if not ref_notes or #ref_notes == 0 then return 0.0 end

    local active_refs = {}
    local prev_refs = {}
    local mid_qn = qn + (dur_qn * 0.35)

    for _, rn in ipairs(ref_notes) do
        if rn.start_qn <= mid_qn + 0.05 and rn.end_qn >= qn + 0.05 then
            table.insert(active_refs, rn)
        elseif rn.end_qn <= qn + 0.05 and rn.end_qn >= qn - 1.5 then
            table.insert(prev_refs, rn)
        end
    end

    if #active_refs == 0 then return 0.0 end

    local raw_consonance = 0.0
    for _, rn in ipairs(active_refs) do
        local iv = math.abs(p - rn.pitch) % 12
        local c_val = 0.0
        if iv == 3 or iv == 4 or iv == 8 or iv == 9 then
            -- Imperfect consonances (3rds & 6ths): ideal for rich counterpoint & harmony
            c_val = 1.25
        elseif iv == 7 then
            -- Perfect 5th
            c_val = 0.85
        elseif iv == 0 then
            -- Unison / Octave
            c_val = is_counter_melody and 0.25 or 0.70
        elseif iv == 5 or iv == 2 or iv == 10 then
            -- 4th, Major 2nd, Minor 7th (suspensions / mild color)
            c_val = 0.15
        else
            -- Minor 2nd (1), Tritone (6), Major 7th (11) -> sharp dissonance
            c_val = -1.25
        end
        raw_consonance = raw_consonance + c_val

        if is_counter_melody and math.abs(p - rn.pitch) < 2 then
            raw_consonance = raw_consonance - 0.5
        end
    end
    raw_consonance = raw_consonance / #active_refs

    local weight = (harmony_blend - 0.32) * 3.2
    local total_h_score = raw_consonance * weight

    -- Contrapuntal Contrary Motion bonus when Counter-Melody mode is active
    if is_counter_melody and prev_p and #prev_refs > 0 then
        local ref_now = active_refs[1].pitch
        local ref_prev = prev_refs[#prev_refs].pitch
        local ref_dir = ref_now - ref_prev
        local mel_dir = p - prev_p
        if (ref_dir > 0 and mel_dir < 0) or (ref_dir < 0 and mel_dir > 0) then
            total_h_score = total_h_score + 0.65
        elseif ref_dir ~= 0 and mel_dir == ref_dir and (math.abs(p - ref_now) % 12 == 0 or math.abs(p - ref_now) % 12 == 7) then
            total_h_score = total_h_score - 0.90
        end
    end

    return total_h_score
end

--- Builds rhythmic onset/duration steps between `start_qn` and `end_qn`
--- Guaranteed termination (no deadzone between outer and inner loop thresholds)
local function subdivide_segment_rhythm(start_qn, end_qn, style_obj, density_level, ref_notes, is_counter_melody, rng, memorized_cell)
    local span_qn = (tonumber(end_qn) or 0) - (tonumber(start_qn) or 0)
    if span_qn <= 0.01 then return {} end

    local MIN_STEP = 0.12
    if span_qn < MIN_STEP then
        return { { start_qn = start_qn, dur_qn = span_qn } }, (memorized_cell or { span_qn })
    end

    local d_key = "medium"
    if density_level <= 0.35 then
        d_key = "sparse"
    elseif density_level >= 0.68 then
        d_key = "dense"
    end

    local cells = (style_obj.rhythm_cells and style_obj.rhythm_cells[d_key]) or { { 1.0, 1.0, 1.0, 1.0 } }
    local steps = {}
    local cur = start_qn
    local safety = 0

    while (end_qn - cur) >= MIN_STEP - 1e-6 and safety < 256 do
        safety = safety + 1
        local rem = end_qn - cur

        local cell_pool = cells
        if is_counter_melody and ref_notes and #ref_notes > 0 then
            local ref_onsets_in_window = 0
            for _, rn in ipairs(ref_notes) do
                if rn.start_qn >= cur - 0.05 and rn.start_qn < cur + math.min(4.0, rem) - 0.05 then
                    ref_onsets_in_window = ref_onsets_in_window + 1
                end
            end
            if ref_onsets_in_window <= 1 and style_obj.rhythm_cells and style_obj.rhythm_cells.dense then
                cell_pool = (density_level < 0.4) and style_obj.rhythm_cells.medium or style_obj.rhythm_cells.dense
            elseif ref_onsets_in_window >= 5 and style_obj.rhythm_cells and style_obj.rhythm_cells.sparse then
                cell_pool = style_obj.rhythm_cells.sparse
            end
        end

        if not cell_pool or #cell_pool == 0 then
            cell_pool = { { 1.0, 1.0, 1.0, 1.0 } }
        end

        local chosen_cell = memorized_cell
        if not chosen_cell or #chosen_cell == 0 or rng() > 0.65 or is_counter_melody then
            local c_idx = math.floor(rng() * #cell_pool) + 1
            chosen_cell = cell_pool[c_idx] or cell_pool[1] or { 1.0 }
        end

        local advanced = false
        for _, raw_d in ipairs(chosen_cell) do
            local left = end_qn - cur
            if left < MIN_STEP - 1e-6 then break end
            local d = math.max(MIN_STEP, tonumber(raw_d) or 0.5)
            local dur = math.min(d, left)
            -- Absorb any tiny trailing remainder (< MIN_STEP) into this step so no deadzone gap remains
            if (left - dur) > 0 and (left - dur) < MIN_STEP then
                dur = left
            end
            if dur >= MIN_STEP - 1e-6 then
                table.insert(steps, { start_qn = cur, dur_qn = dur })
                cur = cur + dur
                advanced = true
            else
                break
            end
        end

        if not advanced then
            local left = end_qn - cur
            if left >= 0.04 then
                if #steps > 0 then
                    steps[#steps].dur_qn = steps[#steps].dur_qn + left
                else
                    table.insert(steps, { start_qn = cur, dur_qn = left })
                end
            end
            break
        end
    end

    -- Absorb any microscopic residual into the last step so segment steps sum to exact span_qn
    if #steps > 0 and (end_qn - cur) > 1e-4 then
        steps[#steps].dur_qn = steps[#steps].dur_qn + (end_qn - cur)
    elseif #steps == 0 then
        table.insert(steps, { start_qn = start_qn, dur_qn = span_qn })
    end

    return steps, (memorized_cell or cells[1])
end

--- Solves the optimal melodic pitch path from `p_start` to `p_end` across `rhythm_steps`
--- using Viterbi Dynamic Programming + Clef Register Clamping + Film Composer Style Rules 1-4
local function solve_segment_viterbi(p_start, p_end, rhythm_steps, scale_pitches, style_obj, opts, ref_notes, clef_reg, tonic_pc, rng)
    local K = #rhythm_steps
    if K == 0 then return {} end

    -- Strictly respect the target instrument's Clef & Playable VSTi Register!
    local reg_min = (clef_reg and clef_reg.min_p) or 36
    local reg_max = (clef_reg and clef_reg.max_p) or 86
    local seg_min = math.max(reg_min, math.min(p_start, p_end) - 9)
    local seg_max = math.min(reg_max, math.max(p_start, p_end) + 9)
    if seg_max < seg_min + 5 then
        seg_min = reg_min
        seg_max = reg_max
    end

    local cands = {}
    for _, sp in ipairs(scale_pitches) do
        if sp >= seg_min and sp <= seg_max then
            table.insert(cands, sp)
        end
    end

    -- Ensure p_start and p_end are in candidates
    local has_start, has_end = false, false
    for _, c in ipairs(cands) do
        if c == p_start then has_start = true end
        if c == p_end then has_end = true end
    end
    if not has_start then table.insert(cands, p_start) end
    if not has_end then table.insert(cands, p_end) end
    table.sort(cands)

    local N = #cands
    if N == 0 then return {} end

    local leap_pref     = tonumber(opts.leap_character) or 0.5
    local harmony_blend = tonumber(opts.harmony_blend) or 0.75
    local is_counter    = (opts.counter_melody_mode == true)

    -- Higher-order Film Composer Style rule weights
    local fanfare_w   = tonumber(style_obj.triad_fanfare_bonus) or 0.25
    local pivot_w     = tonumber(style_obj.pivot_return_bonus) or 0.20
    local seq_w       = tonumber(style_obj.sequence_repeat_bonus) or 0.30
    local no_semitone = (style_obj.avoid_semitone_lead == true)

    local modal_color_map = {}
    if style_obj.modal_color_semitones then
        for _, semi in ipairs(style_obj.modal_color_semitones) do
            modal_color_map[((tonic_pc or 0) + semi) % 12] = true
        end
    end

    local dp = {}
    local backptr = {}
    for k = 1, K do
        dp[k] = {}
        backptr[k] = {}
        for i = 1, N do
            dp[k][i] = -1e9
            backptr[k][i] = 1
        end
    end

    for i = 1, N do
        if cands[i] == p_start then
            dp[1][i] = 0.0
        else
            dp[1][i] = -1e6
        end
    end

    local cad_list = style_obj.cadence_approaches or { { -1 }, { 1 } }
    local chosen_cad = cad_list[math.floor(rng() * #cad_list) + 1] or { -1 }
    local target_penultimate_semi = chosen_cad[#chosen_cad] or -1

    -- Forward Viterbi pass for k = 2 .. K
    for k = 2, K do
        local step_info = rhythm_steps[k]
        local frac = (k - 1) / math.max(1, K)
        local arch_offset = math.sin(frac * math.pi) * (opts.arch_height or 3.0)
        local guide_p = math.max(reg_min, math.min(reg_max, p_start + (p_end - p_start) * frac + arch_offset))
        local is_strong_beat = (math.abs(step_info.start_qn % 2.0) < 0.08)

        for j = 1, N do
            local p_curr = cands[j]
            local h_score = score_harmony_at_qn(
                p_curr, step_info.start_qn, step_info.dur_qn,
                ref_notes, nil, harmony_blend, is_counter
            )

            -- Guide contour attraction + comfortable Clef center attraction
            local dist_to_guide = math.abs(p_curr - guide_p)
            local guide_score = -dist_to_guide * (0.08 + 0.18 * frac)
            if clef_reg and clef_reg.center_p then
                guide_score = guide_score - math.abs(p_curr - clef_reg.center_p) * 0.025
            end

            -- Modal Color Tone Bonus (e.g. Lydian #4 wonder, Dorian natural 6, Mixolydian b7)
            local color_bonus = modal_color_map[p_curr % 12] and 0.42 or 0.0

            -- Cadential preparation bonus on the final step (k == K) before p_end
            local cad_bonus = 0.0
            if k == K then
                local diff_to_end = p_end - p_curr
                if no_semitone then
                    -- Pastoral / Celtic modal cadence: reward whole-step (±2) or minor 3rd (±3), penalize half-step (±1)
                    if math.abs(diff_to_end) == 2 or math.abs(diff_to_end) == 3 or math.abs(diff_to_end) == 5 then
                        cad_bonus = 2.8
                    elseif math.abs(diff_to_end) == 1 then
                        cad_bonus = -2.2
                    end
                else
                    if diff_to_end == target_penultimate_semi or math.abs(diff_to_end) == 1 or math.abs(diff_to_end) == 2 then
                        cad_bonus = 2.4
                    elseif (diff_to_end == -5 or diff_to_end == 5 or diff_to_end == -7) and fanfare_w > 0.6 then
                        cad_bonus = 2.5 -- Heroic 4th/5th fanfare cadence!
                    elseif diff_to_end == 0 and (style_obj.anticipation_prob or 0) > 0.3 then
                        cad_bonus = 1.8
                    end
                end
                if math.abs(diff_to_end) > 7 then
                    cad_bonus = cad_bonus - 3.5
                end
            end

            local noise = (rng() - 0.5) * 0.55

            for i = 1, N do
                if dp[k - 1][i] > -1e5 then
                    local p_prev = cands[i]
                    local iv = p_curr - p_prev
                    local abs_iv = math.abs(iv)

                    -- 1. Empirical Style Corpus Interval Score
                    local w = (style_obj.interval_weights and style_obj.interval_weights[iv]) or 0.01
                    local iv_score = math.log(math.max(0.002, w)) * 0.85

                    -- Pastoral / Modal Semitone Suppression (Film Composer Style 4)
                    if no_semitone and abs_iv == 1 then
                        iv_score = iv_score - 1.6
                    end

                    -- Adjust for user's Leap Character slider (0 = stepwise, 1 = wide heroic leaps)
                    if abs_iv >= 5 and abs_iv <= 12 then
                        iv_score = iv_score + (leap_pref - 0.45) * 1.6
                    elseif abs_iv >= 1 and abs_iv <= 2 then
                        iv_score = iv_score + (0.55 - leap_pref) * 1.1
                    elseif abs_iv > 12 then
                        iv_score = iv_score - 4.0
                    end

                    -- 2. Higher-Order Rule Evaluation using 2-step & 3-step history
                    local gap_fill_bonus = 0.0
                    local style_rule_bonus = 0.0

                    if k >= 3 then
                        local prev_prev_idx = backptr[k - 1][i]
                        local p_prev2 = cands[prev_prev_idx] or p_prev
                        local prev_iv = p_prev - p_prev2
                        local abs_prev_iv = math.abs(prev_iv)

                        -- (a) Leonard Meyer's Gap-Fill Law
                        if abs_prev_iv >= 5 then
                            if (prev_iv > 0 and iv < 0 and abs_iv <= 3) or (prev_iv < 0 and iv > 0 and abs_iv <= 3) then
                                gap_fill_bonus = (style_obj.gap_fill_strength or 0.75) * 1.8
                            elseif (prev_iv > 0 and iv > 0) or (prev_iv < 0 and iv < 0) then
                                gap_fill_bonus = -1.2
                            end
                        end

                        -- (b) Film Style 1 Rule: Heroic Symphonic Fanfare (Quartal / Triad Outlines + Stepwise Turn)
                        if fanfare_w > 0.3 then
                            if (prev_iv == 5 or prev_iv == 7) and (iv == 2 or iv == -1 or iv == -2 or iv == 5 or iv == 4) then
                                style_rule_bonus = style_rule_bonus + fanfare_w * 1.35
                            elseif is_strong_beat and (iv == 5 or iv == 7 or iv == 12) then
                                style_rule_bonus = style_rule_bonus + fanfare_w * 0.95
                            end
                        end

                        -- (c) Film Style 2 Rule: Hypnotic Pivot-Tone Return after Neighbor/6th Excursion
                        if pivot_w > 0.3 then
                            if p_curr == p_prev2 and (abs_prev_iv == 1 or abs_prev_iv == 2 or abs_prev_iv == 3 or abs_prev_iv == 8) then
                                style_rule_bonus = style_rule_bonus + pivot_w * 1.30
                            elseif p_curr == p_start and k % 2 == 1 and abs_iv <= 3 then
                                style_rule_bonus = style_rule_bonus + pivot_w * 0.75
                            end
                        end

                        -- (d) Film Style 3 Rule: Kinetic Rising Motivic Sequence
                        if seq_w > 0.3 and k >= 4 then
                            local idx_k3 = backptr[k - 2] and backptr[k - 2][prev_prev_idx]
                            local p_prev3 = idx_k3 and cands[idx_k3]
                            if p_prev3 then
                                local iv_2_ago = p_prev2 - p_prev3
                                -- Reward repeating a 2-step contour transposed up by +1..+3 semitones
                                local trans = p_curr - p_prev2
                                if iv_2_ago ~= 0 and (iv * iv_2_ago > 0) and (trans >= 1 and trans <= 3) then
                                    style_rule_bonus = style_rule_bonus + seq_w * 1.25
                                end
                            end
                        end
                    end

                    -- 3. Contrapuntal contrary motion with Reference Track
                    local cp_bonus = 0.0
                    if is_counter and ref_notes and #ref_notes > 0 then
                        cp_bonus = score_harmony_at_qn(
                            p_curr, step_info.start_qn, step_info.dur_qn,
                            ref_notes, p_prev, harmony_blend, true
                        ) - h_score
                    end

                    local cand_total = dp[k - 1][i] + iv_score + gap_fill_bonus + style_rule_bonus + color_bonus + h_score + cp_bonus + guide_score + cad_bonus + noise
                    if cand_total > dp[k][j] then
                        dp[k][j] = cand_total
                        backptr[k][j] = i
                    end
                end
            end
        end
    end

    -- Backtrack from best state at step K
    local best_last_idx = 1
    local best_val = -1e9
    for j = 1, N do
        if dp[K][j] > best_val then
            best_val = dp[K][j]
            best_last_idx = j
        end
    end

    local chosen_pitches = {}
    local cur_idx = best_last_idx
    for k = K, 1, -1 do
        chosen_pitches[k] = cands[cur_idx]
        cur_idx = backptr[k][cur_idx] or 1
    end

    return chosen_pitches
end

--- Applies Melodic Inversion, Retrograde, or Retrograde-Inversion within scale degrees & Clef Register
local function apply_contour_transform(notes, transform_id, pivot_pitch, scale_pitches, clef_reg)
    if not transform_id or transform_id == "normal" or not notes or #notes <= 1 then
        return notes
    end

    local reg_min = (clef_reg and clef_reg.min_p) or 28
    local reg_max = (clef_reg and clef_reg.max_p) or 96
    local reg_center = (clef_reg and clef_reg.center_p) or 60

    local function snap_to_scale_and_clef(p)
        local folded = MelodyPathfinderService.fold_pitch_into_register(p, reg_min, reg_max, reg_center)
        local best_p = folded
        local best_d = 999
        for _, sp in ipairs(scale_pitches or {}) do
            if sp >= reg_min and sp <= reg_max then
                local d = math.abs(sp - folded)
                if d < best_d then
                    best_d = d
                    best_p = sp
                end
            end
        end
        return math.max(reg_min, math.min(reg_max, best_p))
    end

    local do_invert = (transform_id == "inversion" or transform_id == "retrograde_inversion")
    local do_retro  = (transform_id == "retrograde" or transform_id == "retrograde_inversion")

    if do_invert then
        local axis = tonumber(pivot_pitch) or tonumber(notes[1].pitch) or reg_center
        for _, n in ipairs(notes) do
            local np = tonumber(n.pitch) or axis
            local mirrored = axis - (np - axis)
            n.pitch = snap_to_scale_and_clef(mirrored)
        end
    end

    if do_retro and #notes >= 2 then
        local q0 = tonumber(notes[1].start_qn) or 0
        -- Compute exact inter-onset step durations from actual note start_qn positions
        -- so reversing the motif preserves the exact start `q0` and total phrase span without drift
        local actual_steps = {}
        for i = 1, #notes do
            if i < #notes then
                local diff = (tonumber(notes[i + 1].start_qn) or q0) - (tonumber(notes[i].start_qn) or q0)
                actual_steps[i] = math.max(0.05, diff)
            else
                actual_steps[i] = math.max(0.1, tonumber(notes[i].step_dur_qn) or tonumber(notes[i].dur_qn) or 0.5)
            end
        end

        local rev_pitches = {}
        local rev_durs = {}
        local rev_step_durs = {}
        local rev_vels = {}
        local rev_arts = {}
        local rev_wps = {}
        for i = #notes, 1, -1 do
            table.insert(rev_pitches, notes[i].pitch)
            table.insert(rev_durs, tonumber(notes[i].dur_qn) or 0.5)
            table.insert(rev_step_durs, actual_steps[i])
            table.insert(rev_vels, notes[i].vel or 90)
            table.insert(rev_arts, notes[i].art or "normal")
            table.insert(rev_wps, notes[i].is_waypoint == true)
        end
        local cur_q = q0
        for i = 1, #notes do
            notes[i].pitch = rev_pitches[i]
            notes[i].start_qn = math.floor(cur_q * 1000 + 0.5) / 1000
            local max_allowed_dur = (i < #notes) and math.max(0.08, rev_step_durs[i] * 0.96) or rev_durs[i]
            notes[i].dur_qn = math.max(0.08, math.floor(math.min(rev_durs[i], max_allowed_dur) * 1000 + 0.5) / 1000)
            notes[i].step_dur_qn = rev_step_durs[i]
            notes[i].vel = rev_vels[i]
            notes[i].art = rev_arts[i]
            notes[i].is_waypoint = rev_wps[i]
            cur_q = cur_q + rev_step_durs[i]
        end
    end

    return notes
end

--- Generates the complete melody / counter-melody preview from current state & options
function MelodyPathfinderService.generate_preview(state, active_tracks_data, opts)
    opts = opts or {}
    local style_id = opts.style_id or "cinematic"
    local style_obj = MelodyStyleCorpus.BY_ID[style_id] or MelodyStyleCorpus.STYLES[1]
    local rng = make_rng(opts.seed or 1001)

    local target_track, waypoints, target_take = MelodyPathfinderService.get_selected_waypoints(state, active_tracks_data)

    -- Resolve active Clef & Playable Instrument Register for target_track
    local clef_reg = MelodyPathfinderService.get_clef_register(
        state, target_track, target_take, waypoints, opts.octave_shift
    )

    -- Determine tonic pitch class from track's Key Signature (or C if 0)
    local key_idx = 0
    if state and state.get_key_signature_at_qn then
        local first_qn = (waypoints[1] and waypoints[1].start_qn) or 0
        key_idx = state:get_key_signature_at_qn(target_track, first_qn) or 0
    end
    local tonic_pc = KEY_IDX_TO_TONIC_PC[key_idx] or 0

    local scale_pitches = MelodyPathfinderService.build_scale_pitches(tonic_pc, opts.scale_id, style_obj)

    -- Determine time span & Reference Track notes
    local phrase_bars = tonumber(opts.phrase_bars) or 4
    local qn_per_bar = 4.0
    local min_qn, max_qn
    if #waypoints >= 2 then
        min_qn = waypoints[1].start_qn
        max_qn = waypoints[#waypoints].start_qn + waypoints[#waypoints].dur_qn
        if max_qn <= min_qn + 0.25 then
            max_qn = min_qn + qn_per_bar
        end
    elseif #waypoints == 1 then
        min_qn = waypoints[1].start_qn
        max_qn = min_qn + (phrase_bars * qn_per_bar)
    else
        min_qn = MelodyPathfinderService.resolve_default_start_qn(state, target_track, opts.ref_track_mode, qn_per_bar)
        max_qn = (state and state.mpf_locked_max_qn) or (min_qn + (phrase_bars * qn_per_bar))
    end

    local ref_notes = MelodyPathfinderService.collect_reference_notes(
        opts.ref_track_mode, target_track, min_qn, max_qn
    )

    -- When Counter-Melody mode is active on a selected multi-note pattern and no external reference track
    -- has notes in [min_qn, max_qn], use the selected pattern notes themselves as the reference harmony!
    if opts.counter_melody_mode and (#ref_notes == 0) and #waypoints >= 2 then
        for _, wp in ipairs(waypoints) do
            table.insert(ref_notes, {
                pitch = wp.pitch,
                start_qn = wp.start_qn,
                end_qn = wp.start_qn + (wp.dur_qn or 0.5),
                dur_qn = wp.dur_qn or 0.5,
                vel = wp.vel or 90,
            })
        end
    end

    -- Build effective waypoints anchored inside the Target Track's Clef Register
    local effective_waypoints = {}
    local is_dense_pattern_counter = (opts.counter_melody_mode == true and #waypoints >= 3)

    if not is_dense_pattern_counter then
        for _, wp in ipairs(waypoints) do
            local wp_p = wp.pitch
            if opts.octave_shift and tonumber(opts.octave_shift) ~= 0 then
                wp_p = math.max(21, math.min(108, wp_p + math.floor(tonumber(opts.octave_shift)) * 12))
            end
            table.insert(effective_waypoints, {
                pitch = wp_p,
                start_qn = wp.start_qn,
                dur_qn = wp.dur_qn,
                vel = wp.vel,
                chan = wp.chan,
                is_waypoint = true,
            })
        end
    end

    if #effective_waypoints < 2 then
        -- Default seed pitch uses the detected Clef's natural center pitch (e.g. C3=48 for Bass Clef, G4=67 for Treble)
        local raw_seed = (effective_waypoints[1] and effective_waypoints[1].pitch)
            or (waypoints[1] and waypoints[1].pitch)
            or clef_reg.center_p
        if opts.octave_shift and tonumber(opts.octave_shift) ~= 0 and waypoints[1] and #effective_waypoints == 0 then
            raw_seed = math.max(21, math.min(108, raw_seed + math.floor(tonumber(opts.octave_shift)) * 12))
        end
        local seed_pitch = raw_seed
        if #effective_waypoints == 0 and #waypoints == 0 then
            -- Snap default clef center to tonic or 5th of active scale inside clef register
            seed_pitch = MelodyPathfinderService.fold_pitch_into_register(
                60 + tonic_pc, clef_reg.min_p, clef_reg.max_p, clef_reg.center_p
            )
        elseif is_dense_pattern_counter then
            -- Start the counter-melody on a consonant 3rd/6th/5th relative to the first note of the selected pattern
            local iv_choices = { 3, 4, -3, -4, 7, -5, 8, 9 }
            local pick_iv = iv_choices[math.floor(rng() * #iv_choices) + 1] or 4
            local cand_seed = MelodyPathfinderService.fold_pitch_into_register(
                raw_seed + pick_iv, clef_reg.min_p, clef_reg.max_p, clef_reg.center_p
            )
            local best_sp = cand_seed
            local best_d = 999
            for _, sp in ipairs(scale_pitches) do
                if sp >= clef_reg.min_p and sp <= clef_reg.max_p then
                    local d = math.abs(sp - cand_seed)
                    if d < best_d then
                        best_d = d
                        best_sp = sp
                    end
                end
            end
            seed_pitch = best_sp
        end
        local seed_chan = (waypoints[1] and waypoints[1].chan) or 0
        local seed_vel  = (waypoints[1] and waypoints[1].vel) or 96

        if #effective_waypoints == 0 then
            table.insert(effective_waypoints, {
                pitch = seed_pitch,
                start_qn = min_qn,
                dur_qn = 1.0,
                vel = seed_vel,
                chan = seed_chan,
                is_waypoint = true,
            })
        end

        local span_total = math.max(2.0, max_qn - min_qn)
        local num_landmarks = math.max(1, math.min(8, math.ceil(span_total / qn_per_bar)))
        local step_span = span_total / num_landmarks
        local arch_Offsets = { 4, 7, 3, 0, 5, 8, 2, 0 }
        for b = 1, num_landmarks do
            local w_qn = (b == num_landmarks)
                and math.max(min_qn + 0.5, max_qn - math.min(1.0, step_span * 0.4))
                or (min_qn + (b * step_span))
            local target_p = seed_pitch + (arch_Offsets[((b - 1) % #arch_Offsets) + 1] or 0)

            -- If Reference Track has notes near `w_qn`, pick a consonant contrapuntal pitch class
            -- AND fold it into the Target Track's Clef & Seed Note octave!
            if #ref_notes > 0 then
                for _, rn in ipairs(ref_notes) do
                    if math.abs(rn.start_qn - w_qn) < math.max(1.5, step_span * 0.6) then
                        local interval_choices = { 3, 4, 8, 9, -3, -4, 7 }
                        local pick_iv = interval_choices[math.floor(rng() * #interval_choices) + 1]
                        target_p = rn.pitch + pick_iv
                        break
                    end
                end
            end

            -- Fold `target_p` into the Target Track's Clef register around `seed_pitch`
            target_p = MelodyPathfinderService.fold_pitch_into_register(
                target_p, clef_reg.min_p, clef_reg.max_p, seed_pitch
            )

            -- Snap `target_p` to scale within Clef register
            local best_sp = seed_pitch
            local best_d = 999
            for _, sp in ipairs(scale_pitches) do
                if sp >= clef_reg.min_p and sp <= clef_reg.max_p then
                    local d = math.abs(sp - target_p)
                    if d < best_d then
                        best_d = d
                        best_sp = sp
                    end
                end
            end

            local last_dur = (b == num_landmarks) and math.max(0.25, max_qn - w_qn) or 1.0
            table.insert(effective_waypoints, {
                pitch = best_sp,
                start_qn = w_qn,
                dur_qn = last_dur,
                vel = seed_vel,
                chan = seed_chan,
                is_waypoint = false,
            })
        end
    end

    -- Solve each segment between consecutive waypoints W_s -> W_{s+1}
    local generated = {}
    local memorized_cell = nil
    local density = tonumber(opts.density) or 0.5

    for s = 1, #effective_waypoints - 1 do
        local wA = effective_waypoints[s]
        local wB = effective_waypoints[s + 1]

        local seg_steps, used_cell = subdivide_segment_rhythm(
            wA.start_qn, wB.start_qn,
            style_obj, density, ref_notes, opts.counter_melody_mode, rng, memorized_cell
        )
        if not memorized_cell then memorized_cell = used_cell end

        local seg_pitches = solve_segment_viterbi(
            wA.pitch, wB.pitch, seg_steps, scale_pitches, style_obj, opts, ref_notes, clef_reg, tonic_pc, rng
        )

        for k, st in ipairs(seg_steps) do
            local is_anchor = (k == 1 and wA.is_waypoint)
            local p = is_anchor and wA.pitch or (seg_pitches[k] or wA.pitch)
            local dur = st.dur_qn * (style_obj.legato_ratio or 0.92)

            local art = "normal"
            local beat_frac = st.start_qn % 1.0
            if not is_anchor then
                if rng() < (style_obj.staccato_prob or 0.1) and st.dur_qn <= 0.5 then
                    art = "staccato"
                    dur = math.min(dur, 0.22)
                elseif math.abs(beat_frac) < 0.05 and rng() < (style_obj.accent_prob or 0.25) then
                    art = "accent"
                end
            else
                art = "tenuto"
            end

            local seg_frac = (k - 1) / math.max(1, #seg_steps)
            local vel_curve = math.sin(seg_frac * math.pi) * 14
            local base_vel = is_anchor and (wA.vel or 100) or 86
            if art == "accent" then base_vel = base_vel + 12 end
            local vel = math.max(52, math.min(124, math.floor(base_vel + vel_curve + (rng() - 0.5) * 8)))

            table.insert(generated, {
                pitch = p,
                start_qn = math.floor(st.start_qn * 1000 + 0.5) / 1000,
                dur_qn = math.max(0.08, math.floor(dur * 1000 + 0.5) / 1000),
                step_dur_qn = st.dur_qn,
                vel = vel,
                chan = wA.chan or 0,
                art = art,
                is_waypoint = is_anchor,
            })
        end
    end

    local wLast = effective_waypoints[#effective_waypoints]
    if wLast then
        local last_step_dur = math.max(0.25, wLast.dur_qn or 1.0)
        table.insert(generated, {
            pitch = wLast.pitch,
            start_qn = math.floor(wLast.start_qn * 1000 + 0.5) / 1000,
            dur_qn = last_step_dur,
            step_dur_qn = last_step_dur,
            vel = wLast.vel or 102,
            chan = wLast.chan or 0,
            art = "tenuto",
            is_waypoint = wLast.is_waypoint,
        })
    end

    -- Apply optional Melodic Inversion / Retrograde contour transformation within Clef Register
    if opts.transform_id and opts.transform_id ~= "normal" then
        local pivot = (effective_waypoints[1] and effective_waypoints[1].pitch) or clef_reg.center_p
        generated = apply_contour_transform(generated, opts.transform_id, pivot, scale_pitches, clef_reg)
    end

    return {
        notes = generated,
        waypoints = waypoints,
        ref_notes = ref_notes,
        target_track = target_track,
        target_take = target_take,
        clef_register = clef_reg,
        style = style_obj,
        min_qn = min_qn,
        max_qn = max_qn,
    }
end

--- Directly inverts the currently selected notes in the score around their first note within Clef Register
function MelodyPathfinderService.invert_selected_notes_in_place(state, active_tracks_data, scale_id)
    local target_track, waypoints, target_take = MelodyPathfinderService.get_selected_waypoints(state, active_tracks_data)
    if not target_take or #waypoints < 2 then
        return false, "Select at least 2 notes to invert."
    end

    local clef_reg = MelodyPathfinderService.get_clef_register(state, target_track, target_take, waypoints, 0)
    local key_idx = (state and state.get_key_signature_at_qn and state:get_key_signature_at_qn(target_track, waypoints[1].start_qn)) or 0
    local tonic_pc = KEY_IDX_TO_TONIC_PC[key_idx] or 0
    local scale_pitches = MelodyPathfinderService.build_scale_pitches(tonic_pc, scale_id or "auto", nil)
    local axis = waypoints[1].pitch

    reaper.Undo_BeginBlock()
    for _, wp in ipairs(waypoints) do
        local mirrored = axis - (wp.pitch - axis)
        local folded = MelodyPathfinderService.fold_pitch_into_register(
            mirrored, clef_reg.min_p, clef_reg.max_p, axis
        )
        local best_p = folded
        local best_d = 999
        for _, sp in ipairs(scale_pitches) do
            if sp >= clef_reg.min_p and sp <= clef_reg.max_p then
                if math.abs(sp - folded) < best_d then
                    best_d = math.abs(sp - folded)
                    best_p = sp
                end
            end
        end
        reaper.MIDI_SetNote(target_take, wp.idx, nil, nil, nil, nil, nil, best_p, nil, true)
        wp.pitch = best_p
    end
    reaper.MIDI_Sort(target_take)
    reaper.SetEditCurPos2(0, reaper.TimeMap2_QNToTime(0, waypoints[1].start_qn), false, false)
    if state then
        state._suppress_autoscroll_frames = 2
        state.active_tracks_cache = nil
    end
    local MidiService = package.loaded["services.midi_service"]
    if MidiService and MidiService.invalidate_cache then
        pcall(MidiService.invalidate_cache)
    end
    if reaper.MarkTrackItemsDirty then
        reaper.MarkTrackItemsDirty(target_track, reaper.GetMediaItemTake_Item(target_take))
    end
    reaper.Undo_EndBlock("Melodic Pathfinder: Invert Selected Notes", -1)
    reaper.UpdateArrange()
    return true, string.format("Inverted %d selected notes around pitch %d (%s).", #waypoints, axis, clef_reg.label)
end

--- Commits the previewed melody / counter-melody into the target track's MIDI item
function MelodyPathfinderService.apply_to_score(state, midi_service, preview, opts)
    if not preview or not preview.notes or #preview.notes == 0 then
        return false, "No generated notes to insert."
    end

    local track = preview.target_track
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return false, "No valid target track found."
    end

    local min_qn = preview.min_qn or preview.notes[1].start_qn
    local last_n = preview.notes[#preview.notes]
    local max_qn = math.max(preview.max_qn or 0, last_n.start_qn + last_n.dur_qn)

    reaper.Undo_BeginBlock()

    local start_sec = reaper.TimeMap2_QNToTime(0, min_qn)
    local end_sec   = reaper.TimeMap2_QNToTime(0, max_qn + 0.5)

    -- Always place the REAPER Edit Cursor at the exact start of the selected/inserted pattern!
    reaper.SetEditCurPos2(0, start_sec, false, false)
    if state then
        state._suppress_autoscroll_frames = 2
    end

    local take = preview.target_take
    local item = take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.GetMediaItemTake_Item(take) or nil

    -- Verify that `item` actually overlaps `[min_qn, max_qn]` if another item on the track covers this range
    if item then
        local ipos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local ilen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local isqn = reaper.TimeMap2_timeToQN(0, ipos)
        local ieqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
        if ieqn < min_qn - 0.1 or isqn > max_qn + 0.1 then
            local icnt = reaper.CountTrackMediaItems(track)
            for ii = 0, icnt - 1 do
                local it = reaper.GetTrackMediaItem(track, ii)
                local tk = it and reaper.GetActiveTake(it)
                if tk and reaper.TakeIsMIDI(tk) then
                    local pos_s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                    local len_s = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                    local i_sqn = reaper.TimeMap2_timeToQN(0, pos_s)
                    local i_eqn = reaper.TimeMap2_timeToQN(0, pos_s + len_s)
                    if i_eqn >= min_qn - 0.1 and i_sqn <= max_qn + 0.1 then
                        item = it
                        take = tk
                        break
                    end
                end
            end
        end
    end

    if not item then
        local icnt = reaper.CountTrackMediaItems(track)
        for ii = 0, icnt - 1 do
            local it = reaper.GetTrackMediaItem(track, ii)
            local tk = it and reaper.GetActiveTake(it)
            if tk and reaper.TakeIsMIDI(tk) then
                local pos_s = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local len_s = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                local i_sqn = reaper.TimeMap2_timeToQN(0, pos_s)
                local i_eqn = reaper.TimeMap2_timeToQN(0, pos_s + len_s)
                if i_eqn >= min_qn - 0.1 and i_sqn <= max_qn + 0.1 then
                    item = it
                    take = tk
                    break
                end
            end
        end
    end

    if not item or not take then
        item = reaper.CreateNewMIDIItemInProj(track, start_sec, end_sec, false)
        if item then
            reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
        end
        take = item and reaper.GetActiveTake(item)
    else
        local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end = item_pos + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        if start_sec < item_pos - 0.001 or end_sec > item_end + 0.001 then
            local new_s_qn = math.min(reaper.TimeMap2_timeToQN(0, item_pos), min_qn)
            local new_e_qn = math.max(reaper.TimeMap2_timeToQN(0, item_end), max_qn + 0.5)
            reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
            reaper.MIDI_SetItemExtents(item, new_s_qn, new_e_qn)
            reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
        end
    end

    if not take then
        reaper.Undo_EndBlock("Melodic Pathfinder (Failed)", -1)
        return false, "Could not resolve or create MIDI take."
    end

    local target_chan = (preview.notes[1] and preview.notes[1].chan) or 0
    local _, ncnt = reaper.MIDI_CountEvts(take)
    for ni = (ncnt or 0) - 1, 0, -1 do
        local nok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
        if nok then
            local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
            if chan == target_chan and sqn >= min_qn - 0.04 and sqn <= max_qn - 0.02 then
                reaper.MIDI_DeleteNote(take, ni)
            elseif sel then
                reaper.MIDI_SetNote(take, ni, false, muted, sppq, eppq, chan, pitch, vel, true)
            end
        end
    end

    for _, gn in ipairs(preview.notes) do
        local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, gn.start_qn)
        local eppq = reaper.MIDI_GetPPQPosFromProjQN(take, gn.start_qn + gn.dur_qn)
        if eppq <= sppq + 10 then eppq = sppq + 60 end
        reaper.MIDI_InsertNote(take, true, false, sppq, eppq, gn.chan or 0, gn.pitch, gn.vel or 90, true)

        if gn.art and gn.art ~= "normal" then
            local notation_str = string.format("NOTE %d %d a %s", gn.pitch, gn.chan or 0, gn.art)
            reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, notation_str)
        end
    end

    if opts and opts.auto_slur and #preview.notes >= 2 then
        local trk_guid = reaper.GetTrackGUID(track)
        local n1 = preview.notes[1]
        local n_last = preview.notes[#preview.notes]
        local slur_id = string.format("slur_%s_%d_%.3f", tostring(trk_guid):gsub("[^%w]", ""), target_chan or 0, n1.start_qn)
        local n1_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n1.start_qn) + 0.5)
        reaper.MIDI_InsertTextSysexEvt(take, false, false, n1_sppq, 15, string.format(
            "NOTATOR_SLUR %s %d %d %d %.4f %.4f %.4f -1 -1 -1",
            slur_id, target_chan or 0, n1.pitch, n_last.pitch, n1.start_qn, n_last.start_qn, n1.dur_qn or 0.5
        ))
        if state then
            state.user_slurs = state.user_slurs or {}
            table.insert(state.user_slurs, {
                id = slur_id,
                track_guid = trk_guid,
                chan = target_chan or 0,
                pitch1 = n1.pitch,
                pitch2 = n_last.pitch,
                start_qn = n1.start_qn,
                end_qn = (n_last.start_qn or 0) + (n_last.dur_qn or 1.0),
                n2_start_qn = n_last.start_qn,
                orig_dur1 = n1.dur_qn or 0.5,
            })
            if SlurService and SlurService.save_slurs then
                pcall(SlurService.save_slurs, state)
            end
        end
    end

    reaper.MIDI_Sort(take)

    -- Rebuild `state.selected_notes` with the exact post-MIDI_Sort indices of the newly inserted notes
    -- and lock the original session waypoints so further adjustments in the open modal never drift!
    if state then
        local MidiNote = package.loaded["classes.note"] or require("classes.note")
        local new_sel_notes = {}
        local first_sel_note = nil
        local inserted_raw = {}
        local _, post_ncnt = reaper.MIDI_CountEvts(take)
        for ni = 0, (post_ncnt or 0) - 1 do
            local nok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
            if nok and sel and not muted then
                local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                local eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                if sqn >= min_qn - 0.05 and sqn <= max_qn + 0.05 then
                    local n_obj = MidiNote.new({
                        idx = ni,
                        pitch = pitch,
                        start_qn = sqn,
                        end_qn = eqn,
                        dur_qn = math.max(0.05, eqn - sqn),
                        vel = vel or 90,
                        chan = chan or 0,
                        take = take,
                        item = item,
                        track = track,
                    })
                    new_sel_notes[n_obj:get_key()] = n_obj
                    if not first_sel_note or sqn < first_sel_note.start_qn then
                        first_sel_note = n_obj
                    end
                    table.insert(inserted_raw, n_obj)
                end
            end
        end
        table.sort(inserted_raw, function(a, b)
            if math.abs(a.start_qn - b.start_qn) > 0.02 then
                return a.start_qn < b.start_qn
            end
            return a.pitch > b.pitch
        end)

        state.selected_notes = new_sel_notes
        state.selected_note = first_sel_note
        state.selected_item = item
        state.selected_take = take

        local wp_copy = {}
        for _, wp in ipairs(preview.waypoints or {}) do
            table.insert(wp_copy, {
                pitch = wp.pitch,
                start_qn = wp.start_qn,
                end_qn = wp.end_qn,
                dur_qn = wp.dur_qn,
                vel = wp.vel,
                chan = wp.chan,
                take = take,
                idx = wp.idx,
                is_waypoint = true,
            })
        end
        state.mpf_locked_waypoints = wp_copy
        state.mpf_locked_min_qn = min_qn
        state.mpf_locked_max_qn = max_qn
        state.mpf_locked_track = track
        state.mpf_locked_take = take
        state.mpf_locked_sel_sig = string.format(
            "%s_%d_%.2f_%.2f",
            tostring(take),
            #inserted_raw,
            inserted_raw[1] and inserted_raw[1].start_qn or -1,
            inserted_raw[#inserted_raw] and inserted_raw[#inserted_raw].start_qn or -1
        )
    end

    if midi_service and midi_service.invalidate_cache then
        pcall(midi_service.invalidate_cache)
    end
    if state then
        state.active_tracks_cache = nil
        state.cached_measure_map = nil
        state.cached_measure_map_sig = nil
    end

    if reaper.MarkTrackItemsDirty then
        reaper.MarkTrackItemsDirty(track, item)
    end

    local mode_lbl = (opts and opts.counter_melody_mode) and "Counter-Melody" or "Melodic Path"
    reaper.Undo_EndBlock("Melodic Pathfinder: Generate " .. mode_lbl, -1)
    reaper.UpdateArrange()

    return true, string.format(
        "Inserted %d notes (%s, %s, %s) at Bar %d!",
        #preview.notes,
        mode_lbl,
        (preview.style and preview.style.name) or "Custom",
        (preview.clef_register and preview.clef_register.label) or "Clef",
        math.floor(min_qn / 4.0) + 1
    )
end

return MelodyPathfinderService

-- ==============================================================================
-- REAPER Native Notator - Service: MelodyPathfinderService
-- Algorithmic Melodic Waypoint Inpainting & Contrapuntal Counter-Melody Engine
-- Features:
--   • Clef & Instrument Playable Register Intelligence (Octave-Aware Folding)
--   • Corpus-Trained Markov Interval Weights + Higher-Order Viterbi Pathfinding
--   • 8 Film Score Archetypes with Leitmotif cells & A - A' - B - A'' phrase grammar
--     (Leonard Meyer Gap-Fill, agogic accents, suspensions & breathing rests)
--   • Automatic Key / Mode detection (Krumhansl-Schmuckler) + per-half-bar chord lock
--     from Reference Tracks, Chord Lane & selected Anchor Notes
--   • 3 coupled Bezier curves (Tension, Note Length, Pitch) with Tension -> Velocity
--   • Freehand-to-Bezier simplification (RDP + Catmull-Rom) & JSON curve export/import
--   • Anchor-Note (Waypoint) blending, Melodic Inversion / Retrograde, up to 32 bars
-- ==============================================================================

local Constants           = require("constants")
local Engraver            = require("rendering.engraver")
local MelodyStyleCorpus   = require("services.melody_style_corpus")
local SlurService         = require("services.slur_service")
local KeySignatureService = require("services.key_signature_service")
local JsonHelper          = require("services.json_helper")

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
    percussion   = { min_p = 36, max_p = 72, center_p = 48, label = "Percussion Clef" },
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
                        local nok, _, muted, sppq, eppq, n_chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
                        if nok and not muted and n_chan ~= 9 then
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

--- Resolves the active Key Signature (`key_idx`, `key_mode`, `tonic_pc`, `key_label`)
--- at `qn` for `target_track` / `target_take` using KeySignatureService.resolve_effective_key.
--- Supports Item Key Signatures, Track Key Signatures, Project Key Signatures, and both Major & Minor modes.
function MelodyPathfinderService.resolve_track_key_signature(state, target_track, target_take, qn)
    local key_idx = 0
    local key_mode = "major"
    local item = nil
    if target_take and reaper and reaper.ValidatePtr and reaper.ValidatePtr(target_take, "MediaItem_Take*") then
        item = reaper.GetMediaItemTake_Item(target_take)
    end

    if KeySignatureService and KeySignatureService.resolve_effective_key then
        local resolved = KeySignatureService.resolve_effective_key(state, target_track, item, qn)
        if type(resolved) == "table" then
            key_idx = tonumber(resolved.key_idx or resolved.idx) or 0
            key_mode = (resolved.mode and resolved.mode ~= "") and resolved.mode or "major"
        elseif type(resolved) == "number" then
            key_idx = resolved
        end
    elseif state and state.get_key_signature_at_qn then
        key_idx = tonumber(state:get_key_signature_at_qn(target_track, qn or 0)) or 0
        key_mode = (state and state.key_signature_mode) or "major"
    elseif state then
        key_idx = tonumber(state.key_signature) or 0
        key_mode = state.key_signature_mode or "major"
    end

    local major_tonic_pc = KEY_IDX_TO_TONIC_PC[key_idx]
    if major_tonic_pc == nil then
        major_tonic_pc = ((key_idx * 7) % 12 + 12) % 12
    end
    local tonic_pc = (key_mode == "minor") and ((major_tonic_pc + 9) % 12) or major_tonic_pc

    local key_label = "C Major"
    local kdef = Constants and Constants.KEY_SIGNATURES and Constants.KEY_SIGNATURES[key_idx]
    if kdef then
        if key_mode == "minor" and kdef.minor_name then
            key_label = kdef.minor_name
        else
            key_label = kdef.name or "C Major"
        end
    end

    return key_idx, key_mode, tonic_pc, key_label
end

--- Builds a sorted list of scale pitches across MIDI 21..108
function MelodyPathfinderService.build_scale_pitches(tonic_pc, scale_id, style_obj, key_idx, key_mode)
    local resolved_id = scale_id
    if not resolved_id or resolved_id == "auto" then
        if key_mode == "minor" then
            resolved_id = "aeolian"
        elseif key_idx and tonumber(key_idx) ~= 0 then
            resolved_id = "major"
        else
            resolved_id = (style_obj and style_obj.default_scale) or "major"
        end
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

-- ==============================================================================
-- 3-CURVE BEZIER ENGINE (Tension, Note Length, Pitch)
-- Curves are stored as { nodes = { { t, v, cp1 = { dt, dv }, cp2 = { dt, dv } }, ... } }
-- with t, v in [0, 1]. cp1 is the incoming tangent handle, cp2 the outgoing one,
-- both relative to their anchor node.
-- ==============================================================================

MelodyPathfinderService.MAX_PHRASE_BARS = 32
MelodyPathfinderService.CURVE_IDS = { "tension", "note_length", "pitch" }
MelodyPathfinderService.CURVE_META = {
    tension     = { name = "Tension",     color = 0xFF5252FF, hint = "Harmonic tension, leap size & velocity (pp .. ff)" },
    note_length = { name = "Note Length", color = 0x3498DBFF, hint = "Agile short notes .. long sustained notes & breathing rests" },
    pitch       = { name = "Pitch",       color = 0xF1C40FFF, hint = "Melodic register contour inside the instrument's Clef compass" },
}
MelodyPathfinderService.CURVE_SHAPES = {
    { id = "flat",   name = "Flat",                points = { { 0.0, 0.5 }, { 1.0, 0.5 } } },
    { id = "arch",   name = "Arch (Rise & Fall)",  points = { { 0.0, 0.3 }, { 0.6, 0.85 }, { 1.0, 0.35 } } },
    { id = "golden", name = "Golden-Ratio Climax", points = { { 0.0, 0.15 }, { 0.618, 0.95 }, { 1.0, 0.3 } } },
    { id = "rise",   name = "Steady Rise",         points = { { 0.0, 0.2 }, { 1.0, 0.9 } } },
    { id = "fall",   name = "Steady Fall",         points = { { 0.0, 0.85 }, { 1.0, 0.2 } } },
    { id = "valley", name = "Valley",              points = { { 0.0, 0.7 }, { 0.5, 0.25 }, { 1.0, 0.7 } } },
    { id = "wave",   name = "Wave",                points = { { 0.0, 0.4 }, { 0.25, 0.75 }, { 0.5, 0.4 }, { 0.75, 0.8 }, { 1.0, 0.45 } } },
}

local function clamp01(v)
    v = tonumber(v) or 0
    if v ~= v then return 0 end
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = deep_copy(x) end
    return out
end
MelodyPathfinderService.deep_copy = deep_copy

--- Recomputes smooth Catmull-Rom tangent handles (kept x-monotonic inside each segment)
--- @param nodes table sorted node list
--- @param keep_manual boolean|nil keep handles of nodes flagged `manual`
function MelodyPathfinderService.auto_smooth_nodes(nodes, keep_manual)
    local n = #nodes
    for i = 1, n do
        local nd = nodes[i]
        if not (keep_manual and nd.manual and nd.cp1 and nd.cp2) then
            local prev = nodes[i - 1] or nd
            local nxt = nodes[i + 1] or nd
            local mdt = (nxt.t - prev.t) / 6.0
            local mdv = (nxt.v - prev.v) / 6.0
            -- Local extrema / plateaus get flat tangents (monotone cubic: no overshoot)
            if i > 1 and i < n and (nd.v - prev.v) * (nxt.v - nd.v) <= 0 then mdv = 0 end
            local in_len = (i > 1) and (nd.t - prev.t) or 0
            local out_len = (i < n) and (nxt.t - nd.t) or 0
            local in_dt = math.max(0, math.min(mdt, in_len * 0.95))
            local out_dt = math.max(0, math.min(mdt, out_len * 0.95))
            local in_dv = (mdt > 1e-9) and (mdv * in_dt / mdt) or 0
            local out_dv = (mdt > 1e-9) and (mdv * out_dt / mdt) or 0
            nd.cp1 = { dt = -in_dt, dv = -in_dv }
            nd.cp2 = { dt = out_dt, dv = out_dv }
        end
    end
    return nodes
end

--- Validates / repairs a curve (accepts `{ nodes = {...} }` or a raw `{ {t, v}, ... }` point list).
--- Guarantees sorted nodes, endpoints at t = 0 and t = 1, and tangent handles on every node.
function MelodyPathfinderService.normalize_curve(curve, fallback_v)
    local src = {}
    if type(curve) == "table" then
        if type(curve.nodes) == "table" then src = curve.nodes else src = curve end
    end
    local nodes = {}
    for _, p in ipairs(src) do
        if type(p) == "table" then
            local t = tonumber(p.t or p[1])
            local v = tonumber(p.v or p[2])
            if t and v and t == t and v == v then
                local nd = { t = clamp01(t), v = clamp01(v) }
                if p.manual == true then nd.manual = true end
                if type(p.cp1) == "table" and tonumber(p.cp1.dt) and tonumber(p.cp1.dv) then
                    nd.cp1 = { dt = math.min(0, tonumber(p.cp1.dt)), dv = tonumber(p.cp1.dv) }
                end
                if type(p.cp2) == "table" and tonumber(p.cp2.dt) and tonumber(p.cp2.dv) then
                    nd.cp2 = { dt = math.max(0, tonumber(p.cp2.dt)), dv = tonumber(p.cp2.dv) }
                end
                table.insert(nodes, nd)
            end
        end
    end
    table.sort(nodes, function(a, b) return a.t < b.t end)

    local dedup = {}
    for _, nd in ipairs(nodes) do
        if #dedup > 0 and math.abs(nd.t - dedup[#dedup].t) < 0.004 then
            dedup[#dedup] = nd
        else
            table.insert(dedup, nd)
        end
    end
    nodes = dedup

    local fv = clamp01(fallback_v or 0.5)
    if #nodes == 0 then
        nodes = { { t = 0.0, v = fv }, { t = 1.0, v = fv } }
    end
    if nodes[1].t > 0.0001 then
        table.insert(nodes, 1, { t = 0.0, v = nodes[1].v })
    else
        nodes[1].t = 0.0
    end
    if nodes[#nodes].t < 0.9999 then
        table.insert(nodes, { t = 1.0, v = nodes[#nodes].v })
    else
        nodes[#nodes].t = 1.0
    end

    local need = false
    for _, nd in ipairs(nodes) do
        if not nd.cp1 or not nd.cp2 then need = true break end
    end
    if need then
        local smoothed = deep_copy(nodes)
        MelodyPathfinderService.auto_smooth_nodes(smoothed, false)
        for i, nd in ipairs(nodes) do
            nd.cp1 = nd.cp1 or smoothed[i].cp1
            nd.cp2 = nd.cp2 or smoothed[i].cp2
        end
    end
    -- Endpoint outer handles are meaningless -> zero them
    nodes[1].cp1 = { dt = 0, dv = 0 }
    nodes[#nodes].cp2 = { dt = 0, dv = 0 }
    return { nodes = nodes }
end

--- Builds a smooth curve from a simple point list `{ {t, v}, ... }`
function MelodyPathfinderService.make_curve(points, fallback_v)
    local raw = {}
    for _, p in ipairs(points or {}) do
        if type(p) == "table" then
            table.insert(raw, { t = p.t or p[1], v = p.v or p[2] })
        end
    end
    return MelodyPathfinderService.normalize_curve(raw, fallback_v)
end

function MelodyPathfinderService.make_shape_curve(shape_id)
    for _, sh in ipairs(MelodyPathfinderService.CURVE_SHAPES) do
        if sh.id == shape_id then
            return MelodyPathfinderService.make_curve(sh.points)
        end
    end
    return MelodyPathfinderService.make_curve({ { 0, 0.5 }, { 1, 0.5 } })
end

local function bezier_segment_value(n0, n1, t)
    local x0, y0, x3, y3 = n0.t, n0.v, n1.t, n1.v
    local w = x3 - x0
    if w < 1e-6 then return y3 end
    local c2 = n0.cp2 or { dt = 0, dv = 0 }
    local c1 = n1.cp1 or { dt = 0, dv = 0 }
    local x1 = x0 + math.max(0, math.min(w, tonumber(c2.dt) or 0))
    local y1 = y0 + (tonumber(c2.dv) or 0)
    local x2 = x3 + math.max(-w, math.min(0, tonumber(c1.dt) or 0))
    local y2 = y3 + (tonumber(c1.dv) or 0)
    -- Control points inside [x0, x3] keep x(u) monotonic -> bisection is exact & robust
    local lo, hi = 0.0, 1.0
    for _ = 1, 24 do
        local u = (lo + hi) * 0.5
        local mu = 1 - u
        local x = mu * mu * mu * x0 + 3 * mu * mu * u * x1 + 3 * mu * u * u * x2 + u * u * u * x3
        if x < t then lo = u else hi = u end
    end
    local u = (lo + hi) * 0.5
    local mu = 1 - u
    return mu * mu * mu * y0 + 3 * mu * mu * u * y1 + 3 * mu * u * u * y2 + u * u * u * y3
end

--- Evaluates a Cubic Bezier curve at normalized time `t` (0..1) -> value 0..1
function MelodyPathfinderService.evaluate_bezier_curve(curve, t)
    local nodes = type(curve) == "table" and curve.nodes
    if type(nodes) ~= "table" or #nodes == 0 then return 0.5 end
    t = clamp01(t)
    if #nodes == 1 or t <= nodes[1].t then return clamp01(nodes[1].v) end
    if t >= nodes[#nodes].t then return clamp01(nodes[#nodes].v) end
    for i = 1, #nodes - 1 do
        if t <= nodes[i + 1].t then
            return clamp01(bezier_segment_value(nodes[i], nodes[i + 1], t))
        end
    end
    return clamp01(nodes[#nodes].v)
end

--- Samples `count` evenly spaced points `{ t, v }` along the curve (for drawing)
function MelodyPathfinderService.sample_curve(curve, count)
    count = math.max(2, math.floor(tonumber(count) or 64))
    local out = {}
    for i = 0, count - 1 do
        local t = i / (count - 1)
        out[#out + 1] = { t = t, v = MelodyPathfinderService.evaluate_bezier_curve(curve, t) }
    end
    return out
end

--- Iterative Ramer-Douglas-Peucker polyline reduction
local function rdp_reduce(pts, eps)
    local n = #pts
    if n <= 2 then return pts end
    local keep = { [1] = true, [n] = true }
    local stack = { { 1, n } }
    while #stack > 0 do
        local seg = table.remove(stack)
        local a, b = seg[1], seg[2]
        local ax, ay, bx, by = pts[a].t, pts[a].v, pts[b].t, pts[b].v
        local dx, dy = bx - ax, by - ay
        local len = math.sqrt(dx * dx + dy * dy)
        local best_d, best_i = -1, nil
        for i = a + 1, b - 1 do
            local d
            if len < 1e-9 then
                d = math.sqrt((pts[i].t - ax) ^ 2 + (pts[i].v - ay) ^ 2)
            else
                d = math.abs(dy * pts[i].t - dx * pts[i].v + bx * ay - by * ax) / len
            end
            if d > best_d then best_d, best_i = d, i end
        end
        if best_i and best_d > eps then
            keep[best_i] = true
            table.insert(stack, { a, best_i })
            table.insert(stack, { best_i, b })
        end
    end
    local out = {}
    for i = 1, n do
        if keep[i] then out[#out + 1] = pts[i] end
    end
    return out
end

--- Converts a detailed freehand mouse stroke into a clean, editable Cubic Bezier curve.
--- 1) bins & de-jitters the raw stroke, 2) Ramer-Douglas-Peucker reduction (adaptive epsilon,
--- max `max_nodes` anchors), 3) Catmull-Rom tangent fitting for every new anchor node.
--- If `existing_curve` is given, only the time range covered by the stroke is replaced
--- (partial redraw); nodes & handles outside the stroke are preserved.
--- @param raw_points table { {t=, v=}, ... } normalized stroke points
--- @param existing_curve table|nil
--- @param epsilon number|nil RDP tolerance in normalized units (default 0.025)
--- @param max_nodes number|nil (default 12)
--- @return table curve
function MelodyPathfinderService.simplify_freehand_to_bezier(raw_points, existing_curve, epsilon, max_nodes)
    epsilon = tonumber(epsilon) or 0.025
    max_nodes = math.max(2, math.floor(tonumber(max_nodes) or 12))

    local BINS = 160
    local sum, cnt = {}, {}
    for _, p in ipairs(raw_points or {}) do
        if type(p) == "table" then
            local t = clamp01(p.t or p[1])
            local v = clamp01(p.v or p[2])
            local b = math.floor(t * (BINS - 1) + 0.5)
            sum[b] = (sum[b] or 0) + v
            cnt[b] = (cnt[b] or 0) + 1
        end
    end
    local pts = {}
    for b = 0, BINS - 1 do
        if cnt[b] then
            pts[#pts + 1] = { t = b / (BINS - 1), v = sum[b] / cnt[b] }
        end
    end

    if #pts < 2 then
        if existing_curve then return MelodyPathfinderService.normalize_curve(existing_curve) end
        return MelodyPathfinderService.make_curve({ { 0, (pts[1] and pts[1].v) or 0.5 }, { 1, (pts[1] and pts[1].v) or 0.5 } })
    end

    -- 3-tap smoothing removes mouse jitter (stroke ends stay exact)
    local sm = {}
    for i = 1, #pts do
        local a = pts[math.max(1, i - 1)]
        local c = pts[math.min(#pts, i + 1)]
        sm[i] = { t = pts[i].t, v = (a.v + 2 * pts[i].v + c.v) * 0.25 }
    end
    sm[1].v = pts[1].v
    sm[#sm].v = pts[#pts].v

    local reduced = rdp_reduce(sm, epsilon)
    local guard = 0
    while #reduced > max_nodes and guard < 16 do
        epsilon = epsilon * 1.35
        reduced = rdp_reduce(sm, epsilon)
        guard = guard + 1
    end

    local stroke_t0, stroke_t1 = pts[1].t, pts[#pts].t
    local merged = {}
    if existing_curve then
        local base = MelodyPathfinderService.normalize_curve(existing_curve)
        for _, nd in ipairs(base.nodes) do
            if nd.t < stroke_t0 - 0.02 or nd.t > stroke_t1 + 0.02 then
                merged[#merged + 1] = deep_copy(nd)
            end
        end
    end
    for _, p in ipairs(reduced) do
        merged[#merged + 1] = { t = p.t, v = p.v }
    end
    -- New anchors receive fresh Catmull-Rom handles; preserved nodes keep theirs
    return MelodyPathfinderService.normalize_curve(merged)
end

--- Evaluates the 3 curves at `t` and applies the mutual coupling matrix:
---   • Tension -> Velocity (pp 38 .. ff 124)
---   • Pitch slope -> Tension boost (heroic leaps on steep ascents) & agogic peak length
---   • Tension x Note Length -> suspension / motoric drive / calm breathing rests
---   • Peak Tension (> 0.75) -> Pitch climax pull (+2..+4 scale degrees)
function MelodyPathfinderService.evaluate_coupled_curves(curves, t)
    curves = curves or {}
    local ev = MelodyPathfinderService.evaluate_bezier_curve
    t = clamp01(t)
    local T = ev(curves.tension, t)
    local L = ev(curves.note_length, t)
    local P = ev(curves.pitch, t)
    local dt = 0.025
    local p_prev = ev(curves.pitch, t - dt)
    local p_next = ev(curves.pitch, t + dt)
    local slope = (p_next - p_prev) / (2 * dt)
    local rise = math.max(0, slope)

    local T_eff = clamp01(T + math.min(0.22, rise * 0.10))
    local is_peak = ((P - p_prev) > 0.004) and ((p_next - P) < -0.001)
    local L_eff = L
    if is_peak then L_eff = math.max(L_eff, 0.70) end

    local climax_deg = 0
    if T_eff > 0.75 then
        climax_deg = 2 + math.floor(((T_eff - 0.75) / 0.25) * 2 + 0.5)
    end

    return {
        tension = T_eff,
        raw_tension = T,
        note_length = L_eff,
        raw_note_length = L,
        pitch = P,
        pitch_slope = slope,
        is_peak = is_peak,
        climax_deg = climax_deg,
        velocity = math.floor(38 + 86 * T_eff + 0.5),
        density = clamp01((1 - L_eff) * (0.85 + 0.30 * T_eff)),
        suspension = clamp01(T_eff * L_eff * 1.35),
        breath = clamp01((1 - T_eff) * L_eff * 1.25),
        leap = clamp01(0.15 + 0.65 * T_eff + math.min(0.25, rise * 0.12)),
    }
end

--- Default 3-curve profile of a style (Film Score archetype)
function MelodyPathfinderService.get_style_default_curves(style_obj)
    local dc = (style_obj and style_obj.default_curves) or {}
    return {
        tension     = MelodyPathfinderService.make_curve(dc.tension or { { 0, 0.4 }, { 0.6, 0.75 }, { 1, 0.35 } }),
        note_length = MelodyPathfinderService.make_curve(dc.note_length or { { 0, 0.55 }, { 1, 0.65 } }),
        pitch       = MelodyPathfinderService.make_curve(dc.pitch or { { 0, 0.4 }, { 0.55, 0.7 }, { 1, 0.4 } }),
    }
end

--- Validates a full `{ tension, note_length, pitch }` set (missing curves -> style defaults)
function MelodyPathfinderService.normalize_curves(curves, style_obj)
    local out, defaults = {}, nil
    for _, id in ipairs(MelodyPathfinderService.CURVE_IDS) do
        if type(curves) == "table" and type(curves[id]) == "table" then
            out[id] = MelodyPathfinderService.normalize_curve(curves[id])
        else
            defaults = defaults or MelodyPathfinderService.get_style_default_curves(style_obj)
            out[id] = defaults[id]
        end
    end
    return out
end

-- ==============================================================================
-- KEY / MODE DETECTION & HARMONIC SLICE ANALYSIS
-- ==============================================================================

local KS_MAJOR = { 6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88 }
local KS_MINOR = { 6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17 }
local MAJOR_TONIC_NAMES = { [0] = "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B" }
local MINOR_TONIC_NAMES = { [0] = "C", "C#", "D", "Eb", "E", "F", "F#", "G", "G#", "A", "Bb", "B" }
local MAJOR_FAMILY = { major = true, lydian = true, mixolydian = true }
local MINOR_FAMILY = { aeolian = true, dorian = true, phrygian = true, harmonic_minor = true, melodic_minor = true, minor_pentatonic = true, blues_punk = true }
local SCALE_MODE_LABEL = {
    major = "Major", aeolian = "Minor", harmonic_minor = "Harmonic Minor", melodic_minor = "Melodic Minor",
    dorian = "Dorian", phrygian = "Phrygian", lydian = "Lydian", mixolydian = "Mixolydian",
    minor_pentatonic = "Minor Pentatonic", blues_punk = "Blues",
}

local function is_strong_beat(qn)
    local r = (tonumber(qn) or 0) % 2.0
    return r < 0.04 or r > 1.96
end

local function is_on_beat(qn)
    local q = tonumber(qn) or 0
    return math.abs(q - math.floor(q + 0.5)) < 0.04
end

--- Adds weighted pitch classes of `notes` to `hist` (duration & downbeat weighted)
function MelodyPathfinderService.add_notes_to_histogram(hist, notes, weight)
    hist = hist or {}
    for pc = 0, 11 do hist[pc] = hist[pc] or 0 end
    weight = tonumber(weight) or 1.0
    for _, n in ipairs(notes or {}) do
        local p = tonumber(n.pitch)
        if p then
            local dur = tonumber(n.dur_qn) or ((tonumber(n.end_qn) or 0) - (tonumber(n.start_qn) or 0))
            if not dur or dur <= 0 then dur = 0.5 end
            local w = weight * math.max(0.25, math.min(4.0, dur))
            local sq = tonumber(n.start_qn) or 0
            if math.abs(sq - math.floor(sq / 4.0 + 0.5) * 4.0) < 0.05 then w = w * 1.5 end
            local pc = math.floor(p + 0.5) % 12
            hist[pc] = hist[pc] + w
        end
    end
    return hist
end

--- Krumhansl-Schmuckler key finding: best Pearson correlation over all 24 major/minor keys
--- @return table|nil { tonic_pc, mode = "major"|"minor", score, total }
function MelodyPathfinderService.detect_key_from_histogram(hist)
    if type(hist) ~= "table" then return nil end
    local total = 0
    for pc = 0, 11 do total = total + (tonumber(hist[pc]) or 0) end
    if total <= 1e-6 then return nil end
    local mean_h = total / 12
    local best = nil
    for _, mode in ipairs({ "major", "minor" }) do
        local prof = (mode == "major") and KS_MAJOR or KS_MINOR
        local mean_p = 0
        for i = 1, 12 do mean_p = mean_p + prof[i] end
        mean_p = mean_p / 12
        for tonic = 0, 11 do
            local num, da, db = 0, 0, 0
            for pc = 0, 11 do
                local x = (tonumber(hist[pc]) or 0) - mean_h
                local y = prof[((pc - tonic) % 12) + 1] - mean_p
                num = num + x * y
                da = da + x * x
                db = db + y * y
            end
            local r = (da > 0 and db > 0) and (num / math.sqrt(da * db)) or 0
            if not best or r > best.score + 1e-9 then
                best = { tonic_pc = tonic, mode = mode, score = r }
            end
        end
    end
    best.total = total
    return best
end

--- Chooses the concrete mode inside a major/minor family from pitch-class evidence.
--- Ambiguous evidence keeps the style's characteristic mode (if it belongs to the family).
function MelodyPathfinderService.choose_modal_scale(hist, tonic_pc, family, style_default)
    local total = 0
    if type(hist) == "table" then
        for pc = 0, 11 do total = total + (tonumber(hist[pc]) or 0) end
    end
    local function w(iv) return (type(hist) == "table" and tonumber(hist[(tonic_pc + iv) % 12])) or 0 end
    local thr = total * 0.035
    local sd = style_default
    if family == "minor" then
        if sd == "minor_pentatonic" or sd == "blues_punk" then return sd end
        if total <= 0 then return MINOR_FAMILY[sd] and sd or "aeolian" end
        if w(1) > thr and w(1) > w(2) * 1.2 then return "phrygian" end
        if w(9) > thr and w(9) > w(8) * 1.2 then return "dorian" end
        if w(11) > thr and w(11) > w(10) * 1.2 then return "harmonic_minor" end
        if w(8) > thr and w(8) > w(9) * 1.2 then
            if sd == "phrygian" and w(1) >= w(2) then return "phrygian" end
            if sd == "harmonic_minor" and w(10) <= w(11) * 1.2 then return "harmonic_minor" end
            return "aeolian"
        end
        return MINOR_FAMILY[sd] and sd or "aeolian"
    end
    if total <= 0 then return MAJOR_FAMILY[sd] and sd or "major" end
    if w(6) > thr and w(6) > w(5) * 1.2 then return "lydian" end
    if w(10) > thr and w(10) > w(11) * 1.2 then return "mixolydian" end
    if w(5) > thr and w(5) > w(6) * 1.2 then
        if sd == "mixolydian" and w(10) >= w(11) then return "mixolydian" end
        return "major"
    end
    return MAJOR_FAMILY[sd] and sd or "major"
end

--- Triad (+ optional 7th from evidence) on `root_pc` built from the active pitch-class set
function MelodyPathfinderService.triad_tones(root_pc, pc_set, evidence)
    root_pc = root_pc % 12
    local function has(iv) return pc_set and pc_set[(root_pc + iv) % 12] end
    local function ev(iv) return (evidence and evidence[(root_pc + iv) % 12]) or 0 end
    local third = 4
    if evidence and (ev(3) > ev(4) * 1.1) then
        third = 3
    elseif evidence and (ev(4) > ev(3) * 1.1) then
        third = 4
    elseif has(4) then
        third = 4
    elseif has(3) then
        third = 3
    end
    local fifth = 7
    if not has(7) and has(6) and not (evidence and ev(7) > ev(6)) then fifth = 6 end
    local tones = { [root_pc] = true, [(root_pc + third) % 12] = true, [(root_pc + fifth) % 12] = true }
    if evidence then
        local tot = 0
        for pc = 0, 11 do tot = tot + (evidence[pc] or 0) end
        if ev(10) > tot * 0.12 and ev(10) >= ev(11) then tones[(root_pc + 10) % 12] = true end
        if ev(11) > tot * 0.12 and ev(11) > ev(10) then tones[(root_pc + 11) % 12] = true end
    end
    return tones
end

--- Parses a Chord-Lane item into root pitch class + chord tone set
function MelodyPathfinderService.chord_item_tones(ci)
    local root = math.floor(tonumber(ci and ci.root) or 0) % 12
    local txt = tostring((ci and ci.text) or "")
    txt = txt:gsub("^%s*[A-Ga-g]", "")
    txt = txt:gsub("^#", ""):gsub("^♯", ""):gsub("^♭", "")
    if txt:sub(1, 1) == "b" and not txt:find("^b5") then txt = txt:sub(2) end
    local low = txt:lower()
    local st = tostring((ci and ci.scale_type) or "")
    local third, fifth, seventh = 4, 7, nil
    if low:find("sus4") then
        third = 5
    elseif low:find("sus2") then
        third = 2
    elseif low:find("dim") or low:find("°") then
        third, fifth = 3, 6
        if low:find("7") then seventh = 9 end
    elseif low:find("m7b5") or low:find("ø") then
        third, fifth, seventh = 3, 6, 10
    elseif (low:find("^m") and not low:find("^maj")) or low:find("^min") or low:find("^%-")
        or st == "minor" or st == "dorian" or st == "phrygian" or st == "aeolian" or st == "harmonic_minor" or st == "melodic_minor" then
        third = 3
    end
    if low:find("aug") or low:find("%+") then fifth = 8 end
    if not seventh then
        if low:find("maj7") or low:find("ma7") or low:find("Δ") then
            seventh = 11
        elseif low:find("7") then
            seventh = 10
        end
    end
    local tones = { [root] = true, [(root + third) % 12] = true, [(root + fifth) % 12] = true }
    if seventh then tones[(root + seventh) % 12] = true end
    return root, tones
end

--- Collects notes of the target track itself around the phrase (outside the generated span)
--- as additional key evidence (melodic context before/after the inpainted region).
function MelodyPathfinderService.collect_track_context_notes(track, q0, q1, excl0, excl1)
    local out = {}
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return out end
    local icnt = reaper.CountTrackMediaItems(track)
    local budget = 4000
    for ii = 0, icnt - 1 do
        local item = reaper.GetTrackMediaItem(track, ii)
        local take = item and reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            local ok, ncnt = reaper.MIDI_CountEvts(take)
            if ok and ncnt and ncnt > 0 then
                for ni = 0, ncnt - 1 do
                    budget = budget - 1
                    if budget <= 0 then return out end
                    local nok, _, muted, sppq, eppq, chan, pitch = reaper.MIDI_GetNote(take, ni)
                    if nok and not muted and chan ~= 9 then
                        local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                        local eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                        local inside = excl0 and excl1 and sqn >= excl0 - 0.02 and sqn < excl1 - 0.02
                        if eqn > q0 and sqn < q1 and not inside then
                            out[#out + 1] = { pitch = pitch, start_qn = sqn, end_qn = eqn, dur_qn = math.max(0.05, eqn - sqn) }
                        end
                    end
                end
            end
        end
    end
    return out
end

--- Resolves Tonic + concrete Scale/Mode for generation.
--- • Explicit track/item key signature -> honored (mode refined from evidence, e.g. D Dorian).
--- • Default C Major key signature + Scale "Auto" -> automatic Krumhansl-Schmuckler detection
---   from Reference Tracks, Chord Lane, selected Anchor Notes and surrounding track notes.
function MelodyPathfinderService.resolve_key_context(state, target_track, target_take, min_qn, max_qn, opts, style_obj, waypoints, ref_notes_wide, context_notes)
    opts = opts or {}
    local key_idx, key_mode, tonic_pc, key_label = MelodyPathfinderService.resolve_track_key_signature(
        state, target_track, target_take, min_qn
    )
    local explicit_key = not ((tonumber(key_idx) or 0) == 0 and (key_mode or "major") == "major")

    local hist = {}
    for pc = 0, 11 do hist[pc] = 0 end
    MelodyPathfinderService.add_notes_to_histogram(hist, ref_notes_wide, 1.0)
    MelodyPathfinderService.add_notes_to_histogram(hist, waypoints, 2.5)
    MelodyPathfinderService.add_notes_to_histogram(hist, context_notes, 0.7)
    for _, ci in ipairs((state and state.chord_items) or {}) do
        local cs, ce = tonumber(ci.start_qn) or 0, tonumber(ci.end_qn) or 0
        if ce > (min_qn or 0) - 8 and cs < (max_qn or 16) + 8 then
            local root, tones = MelodyPathfinderService.chord_item_tones(ci)
            local dur = math.max(0.5, math.min(8.0, ce - cs))
            for pc in pairs(tones) do
                hist[pc] = hist[pc] + dur * ((pc == root) and 3.0 or 1.5)
            end
        end
    end
    local total = 0
    for pc = 0, 11 do total = total + hist[pc] end

    local detected = (total >= 3.0) and MelodyPathfinderService.detect_key_from_histogram(hist) or nil
    local scale_id = opts.scale_id or "auto"
    local resolved_scale, family
    local source = "key_signature"
    local res_tonic = tonic_pc

    if scale_id ~= "auto" and SCALE_BY_ID[scale_id] then
        resolved_scale = scale_id
        source = "user"
        if not explicit_key and detected then
            -- Root the chosen mode on the detected key (keeping the detected pitch collection)
            local want_minor = MINOR_FAMILY[scale_id] == true
            if detected.mode == "major" and want_minor then
                res_tonic = (detected.tonic_pc + 9) % 12
            elseif detected.mode == "minor" and not want_minor then
                res_tonic = (detected.tonic_pc + 3) % 12
            else
                res_tonic = detected.tonic_pc
            end
            source = "user+detected"
        end
    else
        if not explicit_key and detected then
            res_tonic = detected.tonic_pc
            family = detected.mode
            source = "detected"
        elseif explicit_key then
            family = (key_mode == "minor") and "minor" or "major"
        end
        if family then
            resolved_scale = MelodyPathfinderService.choose_modal_scale(
                (total > 0) and hist or nil, res_tonic, family, style_obj and style_obj.default_scale
            )
        else
            -- No key signature and no musical evidence at all -> style's characteristic mode
            resolved_scale = (style_obj and style_obj.default_scale) or "major"
            source = "style"
        end
    end

    local fam_minor = MINOR_FAMILY[resolved_scale] == true
    local tname = (fam_minor and MINOR_TONIC_NAMES or MAJOR_TONIC_NAMES)[res_tonic % 12] or "C"
    local mode_lbl = SCALE_MODE_LABEL[resolved_scale] or resolved_scale
    if source == "detected" or source == "user+detected" then
        key_label = string.format("%s %s (auto-detected)", tname, mode_lbl)
    elseif source == "style" or source == "user" then
        key_label = string.format("%s %s", tname, mode_lbl)
    elseif resolved_scale ~= "major" and resolved_scale ~= "aeolian" then
        key_label = string.format("%s • %s %s", key_label or "", tname, mode_lbl)
    end

    return {
        key_idx = key_idx,
        key_mode = key_mode,
        tonic_pc = res_tonic,
        key_label = key_label,
        scale_id = resolved_scale,
        hist = hist,
        detected = detected,
        source = source,
        explicit_key = explicit_key,
    }
end

--- Builds per-slice (default: half-bar) harmonic analysis: chord root + chord tones.
--- Priority: Chord Lane > Reference Track notes > implied phrase harmony (if no evidence at all).
--- @param ctx table { tonic_pc, scale_ivs, pc_set, slice_qn, implied_root_deg = fn(slice) -> degree }
function MelodyPathfinderService.build_harmonic_slices(min_qn, max_qn, ref_notes, chord_items, ctx)
    ctx = ctx or {}
    local slice_qn = tonumber(ctx.slice_qn) or 2.0
    local pc_set = ctx.pc_set or {}
    local slices = {}
    local q0 = math.floor(((min_qn or 0) + 1e-6) / slice_qn) * slice_qn
    local q = q0
    local any_real = false
    local guard = 0
    while q < (max_qn or 16) - 1e-6 and guard < 1024 do
        guard = guard + 1
        local s = { start_qn = q, end_qn = q + slice_qn }
        local mid = q + slice_qn * 0.5
        for _, ci in ipairs(chord_items or {}) do
            local cs = tonumber(ci.start_qn) or 0
            local ce = tonumber(ci.end_qn) or cs
            if cs <= mid and ce > mid then
                s.root_pc, s.tones = MelodyPathfinderService.chord_item_tones(ci)
                s.source = "chord_lane"
                break
            end
        end
        if not s.root_pc and ref_notes and #ref_notes > 0 then
            local h = {}
            for pc = 0, 11 do h[pc] = 0 end
            local low_p, low_pc, tot = 999, nil, 0
            for _, rn in ipairs(ref_notes) do
                local ov = math.min(rn.end_qn, s.end_qn) - math.max(rn.start_qn, s.start_qn)
                if ov > 0.02 then
                    local pc = rn.pitch % 12
                    local w = ov * ((math.abs(rn.start_qn - s.start_qn) < 0.05) and 1.3 or 1.0)
                    h[pc] = h[pc] + w
                    tot = tot + w
                    if rn.pitch < low_p then low_p, low_pc = rn.pitch, pc end
                end
            end
            if tot > 0.05 then
                local best_r, best_sc, best_tones = nil, -1e9, nil
                for pc = 0, 11 do
                    if pc_set[pc] or h[pc] > 0 then
                        local tones = MelodyPathfinderService.triad_tones(pc, pc_set, h)
                        local sc = 0.5 * h[pc]
                        for opc = 0, 11 do
                            if tones[opc] then sc = sc + h[opc] else sc = sc - 0.6 * h[opc] end
                        end
                        if low_pc == pc then sc = sc + 0.35 * tot end
                        if not pc_set[pc] then sc = sc - 0.25 * tot end
                        if sc > best_sc then best_r, best_sc, best_tones = pc, sc, tones end
                    end
                end
                if best_r then
                    s.root_pc, s.tones, s.source = best_r, best_tones, "reference"
                end
            end
        end
        if s.root_pc then any_real = true end
        slices[#slices + 1] = s
        q = q + slice_qn
    end

    if any_real then
        -- Harmony sustains through silent slices
        local last = nil
        for _, s in ipairs(slices) do
            if s.root_pc then
                last = s
            elseif last then
                s.root_pc, s.tones, s.source = last.root_pc, last.tones, "sustain"
            end
        end
        local first = nil
        for _, s in ipairs(slices) do
            if s.root_pc then first = s break end
        end
        for _, s in ipairs(slices) do
            if s.root_pc then break end
            s.root_pc, s.tones, s.source = first.root_pc, first.tones, "sustain"
        end
    elseif type(ctx.implied_root_deg) == "function" and ctx.scale_ivs and #ctx.scale_ivs > 0 then
        local n = #ctx.scale_ivs
        for _, s in ipairs(slices) do
            local deg = math.floor(tonumber(ctx.implied_root_deg(s)) or 0)
            local root = ((ctx.tonic_pc or 0) + ctx.scale_ivs[(deg % n) + 1]) % 12
            s.root_pc = root
            s.tones = MelodyPathfinderService.triad_tones(root, pc_set, nil)
            s.source = "implied"
        end
    end

    slices.start_qn = q0
    slices.slice_qn = slice_qn
    return slices
end

--- Returns the harmonic slice active at `qn` (or nil)
function MelodyPathfinderService.chord_at(slices, qn)
    if type(slices) ~= "table" or #slices == 0 then return nil end
    local idx = math.floor(((qn or 0) - (slices.start_qn or 0)) / (slices.slice_qn or 2.0) + 1e-6) + 1
    idx = math.max(1, math.min(#slices, idx))
    local s = slices[idx]
    if s and s.root_pc then return s end
    return nil
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

--- Fills `fill` QN from `cur` up to the next barline with beat-aligned values (pickup bar alignment)
local function pickup_fill(cur, fill, dens)
    local out = {}
    if fill < 0.12 then
        return { fill }
    end
    if dens < 0.3 then
        return { fill }
    end
    local unit = (dens >= 0.68) and 0.5 or 1.0
    local left = fill
    local to_grid = (math.floor(cur / unit + 1e-6) + 1) * unit - cur
    if to_grid > 1e-3 and to_grid < unit - 1e-3 and to_grid < left - 1e-3 then
        if to_grid >= 0.12 then
            out[#out + 1] = to_grid
            left = left - to_grid
        end
    end
    while left > 1e-3 do
        local d = math.min(unit, left)
        if left - d < 0.12 then d = left end
        out[#out + 1] = d
        left = left - d
    end
    -- merge a leading too-short value into the next one
    if #out >= 2 and out[1] < 0.12 then
        out[2] = out[2] + out[1]
        table.remove(out, 1)
    end
    return out
end

--- Builds rhythmic onset/duration steps between `start_qn` and `end_qn`
--- Guaranteed termination (no deadzone between outer and inner loop thresholds).
--- When `cv_at` (coupled curve evaluator) is given, the rhythmic density follows the
--- Note Length / Tension curves per bar and cells are aligned to the barlines.
local function subdivide_segment_rhythm(start_qn, end_qn, style_obj, density_level, ref_notes, is_counter_melody, rng, memorized_cell, cv_at)
    local span_qn = (tonumber(end_qn) or 0) - (tonumber(start_qn) or 0)
    if span_qn <= 0.01 then return {} end

    local MIN_STEP = 0.12
    if span_qn < MIN_STEP then
        return { { start_qn = start_qn, dur_qn = span_qn } }, (memorized_cell or { span_qn })
    end

    local function dens_key(dl)
        if dl <= 0.35 then return "sparse" end
        if dl >= 0.68 then return "dense" end
        return "medium"
    end

    local base_key = dens_key(tonumber(density_level) or 0.5)
    local cells = (style_obj.rhythm_cells and style_obj.rhythm_cells[base_key]) or { { 1.0, 1.0, 1.0, 1.0 } }
    local steps = {}
    local cur = start_qn
    local safety = 0
    local memo_key = nil

    while (end_qn - cur) >= MIN_STEP - 1e-6 and safety < 512 do
        safety = safety + 1
        local rem = end_qn - cur
        local dens = tonumber(density_level) or 0.5
        local cv = cv_at and cv_at(cur) or nil
        if cv then dens = cv.density end
        local d_key = dens_key(dens)
        local cell_pool = (style_obj.rhythm_cells and style_obj.rhythm_cells[d_key]) or cells

        local handled = false
        if cv then
            local bar_pos = cur - math.floor(cur / 4.0 + 1e-6) * 4.0
            if bar_pos > 0.02 and bar_pos < 3.98 then
                local fill = math.min(4.0 - bar_pos, rem)
                for _, d in ipairs(pickup_fill(cur, fill, dens)) do
                    local left = end_qn - cur
                    local dur = math.min(d, left)
                    if (left - dur) > 0 and (left - dur) < MIN_STEP then dur = left end
                    if dur >= 0.04 then
                        steps[#steps + 1] = { start_qn = cur, dur_qn = dur }
                        cur = cur + dur
                    end
                end
                handled = true
            end
        end

        if not handled then
            if is_counter_melody and ref_notes and #ref_notes > 0 then
                local ref_onsets_in_window = 0
                for _, rn in ipairs(ref_notes) do
                    if rn.start_qn >= cur - 0.05 and rn.start_qn < cur + math.min(4.0, rem) - 0.05 then
                        ref_onsets_in_window = ref_onsets_in_window + 1
                    end
                end
                if ref_onsets_in_window <= 1 and style_obj.rhythm_cells and style_obj.rhythm_cells.dense then
                    cell_pool = (dens < 0.4) and style_obj.rhythm_cells.medium or style_obj.rhythm_cells.dense
                elseif ref_onsets_in_window >= 5 and style_obj.rhythm_cells and style_obj.rhythm_cells.sparse then
                    cell_pool = style_obj.rhythm_cells.sparse
                end
            end

            if not cell_pool or #cell_pool == 0 then
                cell_pool = { { 1.0, 1.0, 1.0, 1.0 } }
            end

            -- Rhythmic motif memory: re-use the memorized cell (motivic coherence) when the density matches
            local chosen_cell = memorized_cell
            local memo_ok = chosen_cell and #chosen_cell > 0 and (not cv or memo_key == nil or memo_key == d_key)
            if not memo_ok or rng() > 0.65 or is_counter_melody then
                local c_idx = math.floor(rng() * #cell_pool) + 1
                chosen_cell = cell_pool[c_idx] or cell_pool[1] or { 1.0 }
                if cv and not memorized_cell then
                    memorized_cell = chosen_cell
                    memo_key = d_key
                end
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
                cur = end_qn
                break
            end
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
--- using Viterbi Dynamic Programming + Clef Register Clamping + Film Score Style Rules.
--- Optional `vctx` adds the 3-curve physics & harmonic slice lock:
---   vctx.cv_at(qn)        -> coupled curve values (tension, leap, suspension, ...)
---   vctx.chord_at(qn)     -> harmonic slice { root_pc, tones }
---   vctx.guide_fn(qn, f)  -> target contour pitch
local function solve_segment_viterbi(p_start, p_end, rhythm_steps, scale_pitches, style_obj, opts, ref_notes, clef_reg, tonic_pc, rng, vctx)
    local K = #rhythm_steps
    if K == 0 then return {} end

    -- Strictly respect the target instrument's Clef & Playable VSTi Register!
    local reg_min = (clef_reg and clef_reg.min_p) or 36
    local reg_max = (clef_reg and clef_reg.max_p) or 86

    local guide_cache = {}
    local g_lo, g_hi = math.min(p_start, p_end), math.max(p_start, p_end)
    if vctx and vctx.guide_fn then
        for k = 2, K do
            local g = vctx.guide_fn(rhythm_steps[k].start_qn, (k - 1) / math.max(1, K))
            g = math.max(reg_min, math.min(reg_max, tonumber(g) or p_start))
            guide_cache[k] = g
            if g < g_lo then g_lo = g end
            if g > g_hi then g_hi = g end
        end
    end
    local margin = (vctx and vctx.guide_fn) and 7 or 9
    local seg_min = math.max(reg_min, math.floor(g_lo) - margin)
    local seg_max = math.min(reg_max, math.ceil(g_hi) + margin)
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
    if not has_end and p_end ~= p_start then table.insert(cands, p_end) end
    table.sort(cands)

    local N = #cands
    if N == 0 then return {} end

    local leap_pref     = tonumber(opts.leap_character) or 0.5
    local harmony_blend = tonumber(opts.harmony_blend) or 0.75
    local is_counter    = (opts.counter_melody_mode == true)

    -- Higher-order Film Score Style rule weights
    local fanfare_w   = tonumber(style_obj.triad_fanfare_bonus) or 0.25
    local pivot_w     = tonumber(style_obj.pivot_return_bonus) or 0.20
    local seq_w       = tonumber(style_obj.sequence_repeat_bonus) or 0.30
    local no_semitone = (style_obj.avoid_semitone_lead == true)
    local susp_aff    = tonumber(style_obj.suspension_prob) or 0.4

    local modal_color_map = {}
    if style_obj.modal_color_semitones then
        for _, semi in ipairs(style_obj.modal_color_semitones) do
            modal_color_map[((tonic_pc or 0) + semi) % 12] = true
        end
    end

    -- Per-step curve & harmony context
    local step_cv, step_chord, step_strong, step_beat = {}, {}, {}, {}
    for k = 1, K do
        local st = rhythm_steps[k]
        step_cv[k] = vctx and vctx.cv_at and vctx.cv_at(st.start_qn) or nil
        step_chord[k] = vctx and vctx.chord_at and vctx.chord_at(st.start_qn) or nil
        step_strong[k] = is_strong_beat(st.start_qn)
        step_beat[k] = is_on_beat(st.start_qn)
    end
    local hw = 0.55 + harmony_blend

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
        local cv_k = step_cv[k]
        local chord_k = step_chord[k]
        local prev_chord = step_chord[k - 1]
        local strong_k = step_strong[k]
        local prev_strong = step_strong[k - 1]
        local step_leap = cv_k and cv_k.leap or leap_pref
        local guide_p
        if guide_cache[k] then
            guide_p = guide_cache[k]
        else
            local arch_offset = math.sin(frac * math.pi) * (opts.arch_height or 3.0)
            guide_p = math.max(reg_min, math.min(reg_max, p_start + (p_end - p_start) * frac + arch_offset))
        end
        local is_strong_beat_step = (math.abs(step_info.start_qn % 2.0) < 0.08)

        for j = 1, N do
            local p_curr = cands[j]
            local h_score = score_harmony_at_qn(
                p_curr, step_info.start_qn, step_info.dur_qn,
                ref_notes, nil, harmony_blend, is_counter
            )

            -- Guide contour attraction + comfortable Clef center attraction
            local dist_to_guide = math.abs(p_curr - guide_p)
            local guide_score
            if vctx and vctx.guide_fn then
                guide_score = -dist_to_guide * (0.12 + 0.12 * frac)
            else
                guide_score = -dist_to_guide * (0.08 + 0.18 * frac)
            end
            if clef_reg and clef_reg.center_p then
                guide_score = guide_score - math.abs(p_curr - clef_reg.center_p) * 0.025
            end

            -- Modal Color Tone Bonus (e.g. Lydian #4 wonder, Dorian natural 6, Mixolydian b7)
            local color_bonus = modal_color_map[p_curr % 12] and 0.42 or 0.0

            -- Harmonic slice lock: chord tones on strong beats, expressive appoggiaturas under high Tension
            local chord_score = 0.0
            if chord_k and chord_k.tones and cv_k then
                local T = cv_k.tension
                local is_ct = chord_k.tones[p_curr % 12] == true
                if is_ct then
                    local w = strong_k and 1.5 or (step_beat[k] and 0.65 or 0.2)
                    if strong_k and chord_k.root_pc == (p_curr % 12) then w = w + 0.25 end
                    chord_score = w * (1.15 - 0.55 * T) * hw
                elseif strong_k then
                    if cv_k.suspension > 0.42 and step_info.dur_qn >= 0.75 then
                        chord_score = 0.9 * cv_k.suspension * susp_aff
                    else
                        chord_score = -1.35 * (1.0 - 0.6 * T) * hw
                    end
                elseif step_beat[k] then
                    chord_score = -0.35 * (1.0 - T) * hw
                end
            end

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

                    -- Pastoral / Modal Semitone Suppression
                    if no_semitone and abs_iv == 1 then
                        iv_score = iv_score - 1.6
                    end

                    -- Leap character (0 = stepwise, 1 = wide heroic leaps) — driven by the Tension curve
                    if abs_iv >= 5 and abs_iv <= 12 then
                        iv_score = iv_score + (step_leap - 0.45) * 1.6
                    elseif abs_iv >= 1 and abs_iv <= 2 then
                        iv_score = iv_score + (0.55 - step_leap) * 1.1
                    elseif abs_iv > 12 then
                        iv_score = iv_score - 4.0
                    end

                    -- Appoggiatura / suspension resolution: a strong-beat non-chord tone resolves by step
                    local resolve_bonus = 0.0
                    if prev_chord and prev_chord.tones and prev_strong and not prev_chord.tones[p_prev % 12] then
                        local now_ct = chord_k and chord_k.tones and chord_k.tones[p_curr % 12]
                        if abs_iv >= 1 and abs_iv <= 2 and now_ct then
                            resolve_bonus = (iv < 0) and 1.5 or 1.1
                        elseif abs_iv > 2 then
                            resolve_bonus = -1.1
                        end
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

                        -- (b) Heroic Symphonic Fanfare (Quartal / Triad Outlines + Stepwise Turn)
                        if fanfare_w > 0.3 then
                            if (prev_iv == 5 or prev_iv == 7) and (iv == 2 or iv == -1 or iv == -2 or iv == 5 or iv == 4) then
                                style_rule_bonus = style_rule_bonus + fanfare_w * 1.35
                            elseif is_strong_beat_step and (iv == 5 or iv == 7 or iv == 12) then
                                style_rule_bonus = style_rule_bonus + fanfare_w * 0.95
                            end
                        end

                        -- (c) Hypnotic Pivot-Tone Return after Neighbor/6th Excursion
                        if pivot_w > 0.3 then
                            if p_curr == p_prev2 and (abs_prev_iv == 1 or abs_prev_iv == 2 or abs_prev_iv == 3 or abs_prev_iv == 8) then
                                style_rule_bonus = style_rule_bonus + pivot_w * 1.30
                            elseif p_curr == p_start and k % 2 == 1 and abs_iv <= 3 then
                                style_rule_bonus = style_rule_bonus + pivot_w * 0.75
                            end
                        end

                        -- (d) Kinetic Rising Motivic Sequence
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

                    local cand_total = dp[k - 1][i] + iv_score + gap_fill_bonus + style_rule_bonus + color_bonus
                        + h_score + cp_bonus + guide_score + cad_bonus + noise + chord_score + resolve_bonus
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

-- ==============================================================================
-- SYMPHONIC PHRASE ARCHITECT (Leitmotif + A - A' - B - A'' period grammar)
-- ==============================================================================

local DEFAULT_MOTIFS = {
    { { d = 0, l = 1.5 }, { d = 1, l = 0.5 }, { d = 2, l = 1.0 }, { d = 4, l = 1.0 }, { d = 3, l = 1.5 }, { d = 2, l = 0.5 }, { d = 1, l = 2.0 } },
}

--- Copies a motif template truncated / padded to exactly `limit_qn`
local function slice_motif(template, limit_qn)
    local out, acc = {}, 0
    for _, n in ipairs(template or {}) do
        if acc >= limit_qn - 1e-6 then break end
        local l = math.min(tonumber(n.l) or 1.0, limit_qn - acc)
        if l >= 0.12 then
            out[#out + 1] = { d = tonumber(n.d) or 0, l = l, c = tonumber(n.c) or 0 }
            acc = acc + l
        elseif #out > 0 then
            out[#out].l = out[#out].l + l
            acc = acc + l
        else
            break
        end
    end
    if #out > 0 and acc < limit_qn - 1e-6 then
        out[#out].l = out[#out].l + (limit_qn - acc)
    end
    return out
end

local function nearest_scale_idx(scale_pitches, pitch)
    local best_i, best_d = 1, 1e9
    for i, sp in ipairs(scale_pitches) do
        local d = math.abs(sp - pitch)
        if d < best_d then best_d, best_i = d, i end
    end
    return best_i
end

--- Phrase layout for a span: phrase length in bars + number of phrases
function MelodyPathfinderService.compute_phrase_layout(span_qn)
    local span_bars = math.max(1, math.floor((tonumber(span_qn) or 16) / 4.0 + 0.5))
    local phrase_bars = (span_bars >= 8) and 4 or ((span_bars >= 4) and 2 or 1)
    local num_phrases = math.ceil(span_bars / phrase_bars)
    local form = { "A", "A'", "B", "A''" }
    local labels = {}
    for i = 1, num_phrases do labels[i] = form[((i - 1) % #form) + 1] end
    return {
        span_bars = span_bars,
        phrase_bars = phrase_bars,
        num_phrases = num_phrases,
        labels = labels,
        cadence_len = (phrase_bars >= 4) and 4.0 or 2.0,
    }
end

--- Note Length curve applied to motif rhythm: long values merge pairs, short values split notes
local function modulate_motif_rhythm(notes, cv_at, rng, idx_to_pitch)
    local function grid_ok(d) return math.abs(d * 4 - math.floor(d * 4 + 0.5)) < 0.02 end
    local out = {}
    local i = 1
    while i <= #notes do
        local n = notes[i]
        local nx = notes[i + 1]
        local cv = cv_at(n.start_qn)
        if cv.note_length > 0.74 and nx and not n.locked and not nx.locked and is_on_beat(n.start_qn)
            and n.dur_qn < 1.0 and nx.dur_qn <= 1.0 and (n.dur_qn + nx.dur_qn) <= 2.0
            and grid_ok(n.dur_qn) and grid_ok(nx.dur_qn) then
            out[#out + 1] = { idx = n.idx, pitch = n.pitch, start_qn = n.start_qn, dur_qn = n.dur_qn + nx.dur_qn, c = n.c, locked = n.locked }
            i = i + 2
        elseif cv.note_length < 0.30 and n.dur_qn >= 1.0 and not n.locked and rng() < 0.8 then
            local half = n.dur_qn * 0.5
            local dir = 1
            if nx then dir = (nx.idx > n.idx) and 1 or ((nx.idx < n.idx) and -1 or 1) end
            out[#out + 1] = { idx = n.idx, pitch = n.pitch, start_qn = n.start_qn, dur_qn = half, c = n.c }
            out[#out + 1] = { idx = n.idx + dir, pitch = idx_to_pitch(n.idx + dir, 0), start_qn = n.start_qn + half, dur_qn = half, c = 0 }
            i = i + 1
        else
            out[#out + 1] = n
            i = i + 1
        end
    end
    return out
end

--- Builds the fixed landmark notes (Leitmotif statements + cadences) for free / seed generation.
--- Continuations between motif and cadence are filled later by the Viterbi voice-leading solver.
local function build_symphonic_landmarks(G)
    local landmarks = {}
    local style = G.style
    local layout = G.layout
    local sp = G.scale_pitches
    local reg_min, reg_max = G.clef_reg.min_p, G.clef_reg.max_p
    local reg_span = math.max(12, reg_max - reg_min)
    local slen = math.max(1, G.scale_len)
    local rng = G.rng

    local function idx_to_pitch(idx, c)
        idx = math.max(1, math.min(#sp, math.floor(idx + 0.5)))
        local p = sp[idx]
        if c and c ~= 0 then
            local alt = p + c
            -- Chromatic neighbour only if it is NOT already another diatonic degree
            if not G.pc_set[alt % 12] then p = alt end
        end
        return p
    end

    local templates = (style.motif_templates and #style.motif_templates > 0) and style.motif_templates or DEFAULT_MOTIFS
    local motif_src = templates[math.floor(rng() * #templates) + 1] or templates[1]
    local motif_qn = (layout.phrase_bars >= 4) and 8.0 or ((layout.phrase_bars == 2) and 4.0 or 2.0)
    local base_motif = slice_motif(motif_src, motif_qn)
    if #base_motif == 0 then base_motif = slice_motif(DEFAULT_MOTIFS[1], motif_qn) end

    local tonic_idxs = {}
    for i, p in ipairs(sp) do
        if p % 12 == G.tonic_pc and p >= reg_min - 12 and p <= reg_max + 12 then
            tonic_idxs[#tonic_idxs + 1] = i
        end
    end
    if #tonic_idxs == 0 then tonic_idxs = { nearest_scale_idx(sp, G.clef_reg.center_p or 60) } end

    local seed_idx = G.seed and nearest_scale_idx(sp, G.seed.pitch) or nil
    local seed_base = seed_idx and (seed_idx - (base_motif[1] and base_motif[1].d or 0)) or nil
    local seq_step = tonumber(style.sequence_step) or 1
    local prev_last_pitch = G.seed and G.seed.pitch or nil
    local phrase_len_qn = layout.phrase_bars * 4.0

    for ph = 1, layout.num_phrases do
        local ph_start = G.min_qn + (ph - 1) * phrase_len_qn
        if ph_start >= G.max_qn - 0.25 then break end
        local ph_end = math.min(G.max_qn, ph_start + phrase_len_qn)
        local ph_len = ph_end - ph_start
        local label = layout.labels[ph] or "A"
        local is_final = (ph == layout.num_phrases) or (ph_end >= G.max_qn - 0.01)
        local cv_mid = G.cv_at(ph_start + ph_len * 0.5)

        -- 1. Motif variation for this phrase
        local m = deep_copy(base_motif)
        local shift = 0
        if label == "A'" then
            shift = seq_step
        elseif label == "B" then
            if cv_mid.tension > 0.6 then
                -- Urgent fragmentation: first half of the motif stated twice, sequenced upward
                local half = slice_motif(base_motif, motif_qn * 0.5)
                m = {}
                for _, n in ipairs(half) do m[#m + 1] = { d = n.d, l = n.l, c = n.c } end
                for _, n in ipairs(half) do m[#m + 1] = { d = n.d + 1, l = n.l, c = n.c } end
            else
                -- Lyrical contrast: melodic inversion around the first motif degree, lifted a third
                local axis = (base_motif[1] and base_motif[1].d) or 0
                for _, n in ipairs(m) do
                    n.d = axis - (n.d - axis)
                    n.c = -(n.c or 0)
                end
                shift = 2
            end
        end
        local m_len = math.min(motif_qn, ph_len * 0.5)
        m = slice_motif(m, m_len)
        if #m == 0 then m = { { d = 0, l = math.max(0.25, m_len), c = 0 } } end

        local climax = cv_mid.climax_deg or 0
        local mean_d = 0
        for _, n in ipairs(m) do mean_d = mean_d + n.d end
        mean_d = mean_d / #m
        local target_p = reg_min + G.cv_at(ph_start + m_len * 0.5).pitch * reg_span

        -- 2. Register placement guided by the Pitch curve (+ melodic continuity)
        local base_idx
        if ph == 1 and seed_base then
            base_idx = seed_base
            shift, climax = 0, 0
        else
            local cand_bases = {}
            if seed_base then
                for k = -2, 2 do cand_bases[#cand_bases + 1] = seed_base + k * slen end
            else
                cand_bases = tonic_idxs
            end
            local best, best_d = cand_bases[1], 1e9
            for _, bi in ipairs(cand_bases) do
                local center = idx_to_pitch(bi + mean_d + shift + climax, 0)
                local first_p = idx_to_pitch(bi + m[1].d + shift + climax, 0)
                local d = math.abs(center - target_p)
                if prev_last_pitch then d = d + 0.35 * math.abs(first_p - prev_last_pitch) end
                if first_p < reg_min or first_p > reg_max then d = d + 24 end
                if d < best_d then best, best_d = bi, d end
            end
            base_idx = best
        end

        local motif_notes = {}
        local q = ph_start
        for i, n in ipairs(m) do
            local idx = base_idx + n.d + shift + climax
            local p = idx_to_pitch(idx, n.c)
            local locked = (ph == 1 and i == 1 and G.seed ~= nil)
            if locked then p = G.seed.pitch end
            motif_notes[#motif_notes + 1] = { idx = idx, pitch = p, start_qn = q, dur_qn = n.l, c = n.c, locked = locked }
            q = q + n.l
        end
        motif_notes = modulate_motif_rhythm(motif_notes, G.cv_at, rng, idx_to_pitch)

        -- 3. Keep motif notes playable & harmonically anchored (chord tones on strong beats)
        for i, mn in ipairs(motif_notes) do
            if not mn.locked then
                local guard = 0
                while mn.pitch < reg_min and guard < 4 do mn.idx = mn.idx + slen; mn.pitch = idx_to_pitch(mn.idx, mn.c); guard = guard + 1 end
                while mn.pitch > reg_max and guard < 8 do mn.idx = mn.idx - slen; mn.pitch = idx_to_pitch(mn.idx, mn.c); guard = guard + 1 end
                local slice = G.chord_at(mn.start_qn)
                if slice and slice.tones and is_strong_beat(mn.start_qn) and (mn.c or 0) == 0
                    and not slice.tones[mn.pitch % 12] then
                    local cv = G.cv_at(mn.start_qn)
                    local nx = motif_notes[i + 1]
                    local susp_ok = cv.suspension > 0.42 and mn.dur_qn >= 0.75 and nx
                        and math.abs((nx.idx or mn.idx) - mn.idx) == 1
                        and rng() < ((tonumber(style.suspension_prob) or 0.4) + 0.25)
                    if susp_ok then
                        mn.appoggiatura = true
                    else
                        local dir_pref = (nx and nx.idx and nx.idx < mn.idx) and -1 or 1
                        for _, dd in ipairs({ dir_pref, -dir_pref, 2 * dir_pref, -2 * dir_pref }) do
                            local cp = idx_to_pitch(mn.idx + dd, 0)
                            if slice.tones[cp % 12] and cp >= reg_min and cp <= reg_max then
                                mn.idx = mn.idx + dd
                                mn.pitch = cp
                                break
                            end
                        end
                    end
                end
            end
        end

        for i, mn in ipairs(motif_notes) do
            landmarks[#landmarks + 1] = {
                pitch = mn.pitch,
                start_qn = mn.start_qn,
                dur_qn = mn.dur_qn,
                fixed_dur = mn.dur_qn,
                fixed = true,
                kind = (i == 1) and "motif_head" or "motif",
                is_waypoint = mn.locked == true,
                vel = mn.locked and G.seed and G.seed.vel or nil,
                chan = G.chan,
                phrase = ph,
                label = label,
            }
        end

        -- 4. Cadence (half cadence on A / B, tonic arrival on A' / A'' / final phrase)
        local last_m = motif_notes[#motif_notes]
        local motif_end = last_m.start_qn + last_m.dur_qn
        local cad_len = (ph_len >= 16 - 1e-6) and 4.0 or math.min(2.0, ph_len * 0.5)
        local cad_start = ph_end - cad_len
        if cad_start < motif_end - 1e-6 then
            cad_start = motif_end
            cad_len = ph_end - cad_start
        end
        if cad_len >= 0.25 then
            local tonic_cad = is_final or label == "A''" or label == "A'"
            local slice = G.chord_at(cad_start + 0.01)
            local cad_target_p = reg_min + G.cv_at(cad_start).pitch * reg_span
            local best_p, best_sc = nil, 1e9
            for _, cp in ipairs(sp) do
                if cp >= reg_min and cp <= reg_max then
                    local pc = cp % 12
                    local ok_pc
                    if slice and slice.tones then
                        ok_pc = slice.tones[pc] == true
                    else
                        ok_pc = tonic_cad and (pc == G.tonic_pc) or (pc == G.half_cad_pc or pc == G.tonic_pc)
                    end
                    if ok_pc then
                        local sc = math.abs(cp - last_m.pitch) * 1.0 + math.abs(cp - cad_target_p) * 0.45
                        if tonic_cad and pc == G.tonic_pc then sc = sc - (is_final and 9 or 5) end
                        if slice and slice.root_pc == pc then sc = sc - 1.5 end
                        if math.abs(cp - last_m.pitch) > 9 then sc = sc + 6 end
                        if sc < best_sc then best_p, best_sc = cp, sc end
                    end
                end
            end
            best_p = best_p or last_m.pitch
            local cv_c = G.cv_at(cad_start)
            local breath = 0
            if not is_final then
                if cv_c.breath > 0.3 or rng() < (tonumber(style.rest_prob) or 0.4) * 0.6 then
                    breath = math.min(cad_len * 0.5, math.floor((0.5 + cv_c.breath) * 2 + 0.5) * 0.5)
                end
            end
            landmarks[#landmarks + 1] = {
                pitch = best_p,
                start_qn = cad_start,
                dur_qn = cad_len,
                fixed_dur = cad_len,
                sound_dur = (breath > 0) and math.max(0.25, cad_len - breath) or nil,
                fixed = true,
                kind = "cadence",
                is_final = is_final,
                chan = G.chan,
                phrase = ph,
                label = label,
            }
            prev_last_pitch = best_p
        else
            -- No room for a separate cadence: stretch the last motif note to the phrase end
            local lm = landmarks[#landmarks]
            lm.dur_qn = ph_end - lm.start_qn
            lm.fixed_dur = lm.dur_qn
            lm.kind = "cadence"
            prev_last_pitch = lm.pitch
        end
    end

    return landmarks
end

--- Agogic accents: a short note reached by an upward leap (>= P4) absorbs the following
--- short note so the melodic summit is sustained (never touches Anchor / motif notes).
local function apply_agogic_accents(notes, cv_at, style_obj)
    local i = 2
    while i < #notes do
        local a, b, c = notes[i - 1], notes[i], notes[i + 1]
        if not b.fixed and not b.is_waypoint and not c.fixed and not c.is_waypoint
            and (b.pitch - a.pitch) >= 5 and (b.step_dur_qn or 0) < 1.0
            and math.abs((b.start_qn + (b.step_dur_qn or 0)) - c.start_qn) < 0.01
            and (c.step_dur_qn or 0) <= 1.0
            and math.abs(b.step_dur_qn * 4 - math.floor(b.step_dur_qn * 4 + 0.5)) < 0.02
            and math.abs(c.step_dur_qn * 4 - math.floor(c.step_dur_qn * 4 + 0.5)) < 0.02 then
            local cv = cv_at(b.start_qn)
            if not (cv.note_length < 0.25 and (style_obj.legato_ratio or 0.9) < 0.8) then
                local ratio = (b.dur_qn or b.step_dur_qn) / math.max(0.01, b.step_dur_qn)
                b.step_dur_qn = b.step_dur_qn + c.step_dur_qn
                b.dur_qn = math.max(0.08, math.floor(b.step_dur_qn * math.min(0.98, math.max(0.85, ratio)) * 1000 + 0.5) / 1000)
                b.vel = math.min(127, (b.vel or 90) + 6)
                b.agogic = true
                table.remove(notes, i + 1)
            end
        end
        i = i + 1
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

    -- Determine time span first so we resolve Key Signature at the exact phrase start `min_qn`
    local phrase_bars = math.max(1, math.min(MelodyPathfinderService.MAX_PHRASE_BARS, math.floor(tonumber(opts.phrase_bars) or 4)))
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
    local span_q = math.max(0.25, max_qn - min_qn)

    -- 3 coupled Bezier curves (Tension, Note Length, Pitch) mapped across [min_qn, max_qn]
    local curves = MelodyPathfinderService.normalize_curves(opts.curves, style_obj)
    local cv_cache = {}
    local function cv_at(qn)
        local t = clamp01(((tonumber(qn) or min_qn) - min_qn) / span_q)
        local key = math.floor(t * 512 + 0.5)
        local c = cv_cache[key]
        if not c then
            c = MelodyPathfinderService.evaluate_coupled_curves(curves, key / 512)
            cv_cache[key] = c
        end
        return c
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

    -- True Key & Mode lock (explicit key signature or automatic detection from the musical context)
    local ref_wide = MelodyPathfinderService.collect_reference_notes(opts.ref_track_mode, target_track, min_qn - 8, max_qn + 8)
    local ctx_notes = MelodyPathfinderService.collect_track_context_notes(target_track, min_qn - 16, max_qn + 16, min_qn, max_qn)
    local kc = MelodyPathfinderService.resolve_key_context(
        state, target_track, target_take, min_qn, max_qn, opts, style_obj, waypoints, ref_wide, ctx_notes
    )
    local key_idx, key_mode, tonic_pc, key_label = kc.key_idx, kc.key_mode, kc.tonic_pc, kc.key_label

    local scale_pitches, _, pc_set = MelodyPathfinderService.build_scale_pitches(
        tonic_pc, kc.scale_id, style_obj, key_idx, key_mode
    )
    local scale_ivs = (SCALE_BY_ID[kc.scale_id] and SCALE_BY_ID[kc.scale_id].intervals) or { 0, 2, 4, 5, 7, 9, 11 }
    local scale_len = #scale_ivs

    -- Phrase layout & implied harmonic rhythm (used only when no reference harmony exists)
    local layout = MelodyPathfinderService.compute_phrase_layout(span_q)
    local prog = (style_obj.progression and #style_obj.progression > 0) and style_obj.progression or { 0, 3, 4, 0 }
    local half_cad = tonumber(style_obj.half_cadence_deg) or 4
    local dom_deg = 4
    if kc.scale_id == "phrygian" then
        dom_deg = 1
    elseif style_obj.avoid_semitone_lead then
        dom_deg = 6
    end
    local function implied_root_deg(slice)
        local rel = math.max(0, slice.start_qn - min_qn)
        local ph_len = layout.phrase_bars * 4.0
        local ph = math.floor(rel / ph_len + 1e-6)
        local pos = rel - ph * ph_len
        local label = layout.labels[ph + 1] or "A"
        local is_final_ph = (ph >= layout.num_phrases - 1)
        local tonic_cad = is_final_ph or label == "A''" or label == "A'"
        local cad_deg = tonic_cad and 0 or half_cad
        local cad_rel = ph_len - layout.cadence_len
        if pos >= cad_rel - 1e-6 then return cad_deg end
        if pos >= cad_rel - 2.0 - 1e-6 then return tonic_cad and dom_deg or 3 end
        local bar_i = math.floor(pos / 4.0 + 1e-6)
        return prog[(bar_i % #prog) + 1] or 0
    end

    local slices = MelodyPathfinderService.build_harmonic_slices(
        min_qn, max_qn, ref_notes, state and state.chord_items,
        { tonic_pc = tonic_pc, scale_ivs = scale_ivs, pc_set = pc_set, slice_qn = 2.0, implied_root_deg = implied_root_deg }
    )
    local function chord_at(qn) return MelodyPathfinderService.chord_at(slices, qn) end

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

    local gen_mode = "blend"
    local landmarks = effective_waypoints
    local seed_chan = (waypoints[1] and waypoints[1].chan) or 0
    local seed_vel  = (waypoints[1] and waypoints[1].vel) or 96

    if #effective_waypoints < 2 and not opts.counter_melody_mode then
        -- ============================================================
        -- MODE 2: Symphonic Phrase Generation (free or from 1 Seed Note)
        -- ============================================================
        gen_mode = "phrase"
        local half_cad_pc = (tonic_pc + scale_ivs[(half_cad % scale_len) + 1]) % 12
        landmarks = build_symphonic_landmarks({
            style = style_obj,
            layout = layout,
            scale_pitches = scale_pitches,
            scale_len = scale_len,
            pc_set = pc_set,
            tonic_pc = tonic_pc,
            half_cad_pc = half_cad_pc,
            clef_reg = clef_reg,
            min_qn = min_qn,
            max_qn = max_qn,
            cv_at = cv_at,
            chord_at = chord_at,
            rng = rng,
            seed = effective_waypoints[1],
            chan = seed_chan,
        })
    elseif #effective_waypoints < 2 then
        -- ============================================================
        -- Counter-Melody landmarks (1 seed / no selection / dense pattern)
        -- ============================================================
        gen_mode = "counter"
        landmarks = effective_waypoints
        -- Default seed pitch uses the detected Clef's natural center pitch (e.g. C3=48 for Bass Clef, G4=67 for Treble)
        local raw_seed = (landmarks[1] and landmarks[1].pitch)
            or (waypoints[1] and waypoints[1].pitch)
            or clef_reg.center_p
        if opts.octave_shift and tonumber(opts.octave_shift) ~= 0 and waypoints[1] and #landmarks == 0 then
            raw_seed = math.max(21, math.min(108, raw_seed + math.floor(tonumber(opts.octave_shift)) * 12))
        end
        local seed_pitch = raw_seed
        if #landmarks == 0 and #waypoints == 0 then
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
            seed_pitch = scale_pitches[nearest_scale_idx(scale_pitches, cand_seed)] or cand_seed
            if seed_pitch < clef_reg.min_p or seed_pitch > clef_reg.max_p then seed_pitch = cand_seed end
        end

        if #landmarks == 0 then
            table.insert(landmarks, {
                pitch = seed_pitch,
                start_qn = min_qn,
                dur_qn = 1.0,
                vel = seed_vel,
                chan = seed_chan,
                is_waypoint = true,
            })
        end

        local span_total = math.max(2.0, max_qn - min_qn)
        local num_landmarks = math.max(1, math.min(MelodyPathfinderService.MAX_PHRASE_BARS, math.ceil(span_total / qn_per_bar)))
        local step_span = span_total / num_landmarks
        local reg_span = clef_reg.max_p - clef_reg.min_p
        for b = 1, num_landmarks do
            local w_qn = (b == num_landmarks)
                and math.max(min_qn + 0.5, max_qn - math.min(1.0, step_span * 0.4))
                or (min_qn + (b * step_span))
            -- Pitch curve drives the register contour of the counter line
            local cvb = cv_at(w_qn)
            local target_p = clef_reg.min_p + cvb.pitch * reg_span + (cvb.climax_deg or 0) * 1.5

            -- If Reference Track has notes near `w_qn`, pick a consonant contrapuntal pitch class
            if #ref_notes > 0 then
                for _, rn in ipairs(ref_notes) do
                    if math.abs(rn.start_qn - w_qn) < math.max(1.5, step_span * 0.6) then
                        local interval_choices = { 3, 4, 8, 9, -3, -4, 7 }
                        local pick_iv = interval_choices[math.floor(rng() * #interval_choices) + 1]
                        target_p = MelodyPathfinderService.fold_pitch_into_register(
                            rn.pitch + pick_iv, clef_reg.min_p, clef_reg.max_p, target_p
                        )
                        break
                    end
                end
            end

            target_p = MelodyPathfinderService.fold_pitch_into_register(
                math.floor(target_p + 0.5), clef_reg.min_p, clef_reg.max_p, target_p
            )
            local best_sp = seed_pitch
            local best_d = 999
            for _, spp in ipairs(scale_pitches) do
                if spp >= clef_reg.min_p and spp <= clef_reg.max_p then
                    local d = math.abs(spp - target_p)
                    if d < best_d then
                        best_d = d
                        best_sp = spp
                    end
                end
            end

            local last_dur = (b == num_landmarks) and math.max(0.25, max_qn - w_qn) or 1.0
            table.insert(landmarks, {
                pitch = best_sp,
                start_qn = w_qn,
                dur_qn = last_dur,
                vel = seed_vel,
                chan = seed_chan,
                is_waypoint = false,
            })
        end
    end

    -- ==================================================================
    -- Fill every gap between consecutive landmarks (Anchor-Note blending,
    -- motif continuations & counter lines) with curve-aware rhythm + Viterbi
    -- ==================================================================
    local reg_span_all = math.max(12, clef_reg.max_p - clef_reg.min_p)
    local legato_base = tonumber(style_obj.legato_ratio) or 0.92
    local generated = {}
    local memorized_cell = nil

    local function legato_at(qn)
        local cv = cv_at(qn)
        return math.min(0.98, legato_base + (1 - legato_base) * cv.note_length * 0.8)
    end

    local function vel_at(qn, extra)
        local cv = cv_at(qn)
        local v = cv.velocity + (extra or 0)
        local r = qn % 4.0
        if r < 0.04 or r > 3.96 then
            v = v + 5
        elseif is_strong_beat(qn) then
            v = v + 2
        end
        v = v + math.floor((rng() - 0.5) * 6)
        return math.max(28, math.min(127, math.floor(v + 0.5)))
    end

    local function make_guide(A, B)
        local tA = clamp01((A.start_qn - min_qn) / span_q)
        local tB = clamp01((B.start_qn - min_qn) / span_q)
        local pA = MelodyPathfinderService.evaluate_bezier_curve(curves.pitch, tA)
        local pB = MelodyPathfinderService.evaluate_bezier_curve(curves.pitch, tB)
        return function(qn, frac)
            local lin = A.pitch + (B.pitch - A.pitch) * frac
            local cv = cv_at(qn)
            local arch = math.sin(frac * math.pi)
            local climax = (cv.climax_deg or 0) * 1.6 * arch
            if gen_mode == "blend" then
                -- The Pitch curve's deviation from its own straight line bends the bridge,
                -- while both Anchor Notes stay exact landmarks.
                local p_lin = pA + (pB - pA) * frac
                return lin + (cv.pitch - p_lin) * reg_span_all * 0.6 + climax
            end
            local abs_t = clef_reg.min_p + cv.pitch * reg_span_all
            return lin + (abs_t - lin) * arch * 0.8 + climax
        end
    end

    local vctx = { cv_at = cv_at, chord_at = chord_at }

    local function emit_landmark(L, step_dur)
        local sound = step_dur * legato_at(L.start_qn)
        if L.sound_dur then sound = math.min(L.sound_dur, step_dur) end
        local art = "normal"
        if L.is_waypoint then
            art = "tenuto"
        elseif L.kind == "cadence" then
            art = "tenuto"
        end
        local extra = 0
        if L.kind == "motif_head" then extra = 3 end
        if L.kind == "cadence" and cv_at(L.start_qn).tension < 0.5 then extra = -8 end
        table.insert(generated, {
            pitch = L.pitch,
            start_qn = math.floor(L.start_qn * 1000 + 0.5) / 1000,
            dur_qn = math.max(0.08, math.floor(sound * 1000 + 0.5) / 1000),
            step_dur_qn = step_dur,
            vel = (L.is_waypoint and L.vel) and L.vel or vel_at(L.start_qn, extra),
            chan = L.chan or seed_chan,
            art = art,
            is_waypoint = L.is_waypoint == true,
            fixed = L.fixed == true,
            kind = L.kind,
        })
    end

    local function emit_generated(p, st, chan)
        local cv = cv_at(st.start_qn)
        local art = "normal"
        local beat_frac = st.start_qn % 1.0
        local stacc_p = (style_obj.staccato_prob or 0.1) * (0.5 + (1 - cv.note_length)) * (0.6 + cv.tension * 0.6)
        if st.dur_qn <= 0.5 and rng() < stacc_p then
            art = "staccato"
        elseif math.abs(beat_frac) < 0.05 and cv.tension > 0.62 and rng() < (style_obj.accent_prob or 0.25) then
            art = "accent"
        end
        local dur = st.dur_qn * legato_at(st.start_qn)
        table.insert(generated, {
            pitch = p,
            start_qn = math.floor(st.start_qn * 1000 + 0.5) / 1000,
            dur_qn = math.max(0.08, math.floor(dur * 1000 + 0.5) / 1000),
            step_dur_qn = st.dur_qn,
            vel = vel_at(st.start_qn, (art == "accent") and 8 or 0),
            chan = chan or seed_chan,
            art = art,
            is_waypoint = false,
        })
    end

    for s = 1, #landmarks - 1 do
        local A = landmarks[s]
        local B = landmarks[s + 1]
        local a_fixed = A.fixed_dur
        local gap_start = a_fixed and (A.start_qn + a_fixed) or A.start_qn
        if a_fixed and (B.start_qn - gap_start) < 0.12 then
            emit_landmark(A, math.max(0.08, B.start_qn - A.start_qn))
        else
            local steps
            if a_fixed then
                steps = { { start_qn = A.start_qn, dur_qn = a_fixed } }
                local more = subdivide_segment_rhythm(
                    gap_start, B.start_qn, style_obj, 0.5, ref_notes, opts.counter_melody_mode, rng, memorized_cell, cv_at
                )
                for _, st in ipairs(more) do steps[#steps + 1] = st end
            else
                local used_cell
                steps, used_cell = subdivide_segment_rhythm(
                    A.start_qn, B.start_qn, style_obj, 0.5, ref_notes, opts.counter_melody_mode, rng, memorized_cell, cv_at
                )
                if not memorized_cell then memorized_cell = used_cell end
            end

            vctx.guide_fn = make_guide(A, B)
            local seg_pitches = solve_segment_viterbi(
                A.pitch, B.pitch, steps, scale_pitches, style_obj, opts, ref_notes, clef_reg, tonic_pc, rng, vctx
            )
            for k, st in ipairs(steps) do
                if k == 1 then
                    emit_landmark(A, st.dur_qn)
                else
                    emit_generated(seg_pitches[k] or A.pitch, st, A.chan)
                end
            end
        end
    end

    local wLast = landmarks[#landmarks]
    if wLast then
        local last_step_dur = math.max(0.25, wLast.fixed_dur or wLast.dur_qn or 1.0)
        local sound = wLast.sound_dur or last_step_dur
        table.insert(generated, {
            pitch = wLast.pitch,
            start_qn = math.floor(wLast.start_qn * 1000 + 0.5) / 1000,
            dur_qn = sound,
            step_dur_qn = last_step_dur,
            vel = (wLast.is_waypoint and wLast.vel) or vel_at(wLast.start_qn, -4),
            chan = wLast.chan or seed_chan,
            art = "tenuto",
            is_waypoint = wLast.is_waypoint == true,
            fixed = true,
            kind = "cadence",
        })
    end

    -- Agogic accents on leap summits (rhythm follows melody, never touches anchors / motifs)
    apply_agogic_accents(generated, cv_at, style_obj)

    -- Apply optional Melodic Inversion / Retrograde contour transformation within Clef Register
    if opts.transform_id and opts.transform_id ~= "normal" then
        local pivot = (effective_waypoints[1] and effective_waypoints[1].pitch)
            or (generated[1] and generated[1].pitch) or clef_reg.center_p
        generated = apply_contour_transform(generated, opts.transform_id, pivot, scale_pitches, clef_reg)
    end

    local harmony_src = "none"
    for _, sl in ipairs(slices) do
        if sl.source == "chord_lane" then harmony_src = "Chord Lane" break end
        if sl.source == "reference" then harmony_src = "Reference Track" end
        if sl.source == "implied" and harmony_src == "none" then harmony_src = "Implied (Style Progression)" end
    end
    local form_summary
    if gen_mode == "phrase" then
        form_summary = string.format("%s (%d-bar phrases)", table.concat(layout.labels, " "), layout.phrase_bars)
    elseif gen_mode == "blend" then
        form_summary = string.format("Anchor-Note Blending (%d anchors)", #effective_waypoints)
    else
        form_summary = "Counter-Melody"
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
        key_idx = key_idx,
        key_mode = key_mode,
        tonic_pc = tonic_pc,
        key_label = key_label,
        scale_id = kc.scale_id,
        key_source = kc.source,
        pc_set = pc_set,
        curves = curves,
        harmonic_slices = slices,
        harmony_source = harmony_src,
        mode = gen_mode,
        layout = layout,
        form_summary = form_summary,
    }
end

--- Directly inverts the currently selected notes in the score around their first note within Clef Register
function MelodyPathfinderService.invert_selected_notes_in_place(state, active_tracks_data, scale_id)
    local target_track, waypoints, target_take = MelodyPathfinderService.get_selected_waypoints(state, active_tracks_data)
    if not target_take or #waypoints < 2 then
        return false, "Select at least 2 notes to invert."
    end

    local clef_reg = MelodyPathfinderService.get_clef_register(state, target_track, target_take, waypoints, 0)
    local key_idx, key_mode, tonic_pc = MelodyPathfinderService.resolve_track_key_signature(
        state, target_track, target_take, waypoints[1].start_qn
    )
    local scale_pitches = MelodyPathfinderService.build_scale_pitches(
        tonic_pc, scale_id or "auto", nil, key_idx, key_mode
    )
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
    if KeySignatureService and KeySignatureService.respell_item_notes then
        KeySignatureService.respell_item_notes(state, target_take, key_idx, key_mode)
    end
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

    -- Respell inserted notes according to the active Key Signature (e.g. F# in G Major, Bb/Eb in Gm/Bb Major)
    if KeySignatureService and KeySignatureService.respell_item_notes then
        local eff_kidx = preview.key_idx
        local eff_kmode = preview.key_mode
        if eff_kidx == nil then
            eff_kidx, eff_kmode = MelodyPathfinderService.resolve_track_key_signature(state, track, take, min_qn)
        end
        KeySignatureService.respell_item_notes(state, take, eff_kidx or 0, eff_kmode or "major")
    end

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


-- ==============================================================================
-- CURVE PERSISTENCE: Session RAM slots + JSON Export / Import
-- ==============================================================================

local function round4(x)
    x = tonumber(x) or 0
    return math.floor(x * 10000 + 0.5) / 10000
end

--- Serializes the 3 curves (anchor nodes + Bezier tangent handles) to a JSON string
function MelodyPathfinderService.curves_to_json(curves, meta)
    meta = meta or {}
    local data = {
        format = "reaper_notator_mpf_curves",
        version = 1,
        style_id = meta.style_id,
        name = meta.name,
        curves = {},
    }
    for _, id in ipairs(MelodyPathfinderService.CURVE_IDS) do
        local c = MelodyPathfinderService.normalize_curve(curves and curves[id])
        local nodes = {}
        for _, nd in ipairs(c.nodes) do
            nodes[#nodes + 1] = {
                t = round4(nd.t),
                v = round4(nd.v),
                cp1 = { dt = round4(nd.cp1.dt), dv = round4(nd.cp1.dv) },
                cp2 = { dt = round4(nd.cp2.dt), dv = round4(nd.cp2.dv) },
                manual = nd.manual and true or nil,
            }
        end
        data.curves[id] = { nodes = nodes }
    end
    return JsonHelper.encode(data)
end

--- Parses a curve JSON string -> normalized curves table (or nil, error)
function MelodyPathfinderService.curves_from_json(str, style_obj)
    if type(str) ~= "string" or str == "" then return nil, "Empty JSON." end
    local ok, data = pcall(JsonHelper.decode, str)
    if not ok or type(data) ~= "table" then return nil, "Invalid JSON." end
    local src = (type(data.curves) == "table") and data.curves or data
    local found = false
    for _, id in ipairs(MelodyPathfinderService.CURVE_IDS) do
        if type(src[id]) == "table" then found = true end
    end
    if not found then return nil, "No Tension / Note Length / Pitch curves found in JSON." end
    return MelodyPathfinderService.normalize_curves(src, style_obj), data
end

--- Writes the 3 curves to a `.json` file
function MelodyPathfinderService.export_curves_json(curves, path, meta)
    if type(path) ~= "string" or path == "" then return false, "No file path selected." end
    if not path:lower():match("%.json$") then path = path .. ".json" end
    local f = io.open(path, "w")
    if not f then return false, "Could not write file: " .. path end
    f:write(MelodyPathfinderService.curves_to_json(curves, meta))
    f:close()
    return true, path
end

--- Reads curves from a `.json` file
function MelodyPathfinderService.import_curves_json(path, style_obj)
    if type(path) ~= "string" or path == "" then return nil, "No file path selected." end
    local f = io.open(path, "r")
    if not f then return nil, "Could not open file: " .. path end
    local content = f:read("*a")
    f:close()
    return MelodyPathfinderService.curves_from_json(content, style_obj)
end

return MelodyPathfinderService

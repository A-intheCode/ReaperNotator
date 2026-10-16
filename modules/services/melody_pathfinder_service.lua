-- ==============================================================================
-- REAPER Native Notator - Service: MelodyPathfinderService
-- Algorithmic Melodic Waypoint Inpainting & Contrapuntal Counter-Melody Engine
-- Uses Corpus-Trained Markov Interval Weights + Viterbi Pathfinding +
-- Leonard Meyer Gap-Fill + Reference Track Harmonic Consonance & Inversion
-- ==============================================================================

local MelodyStyleCorpus = require("services.melody_style_corpus")
local SlurService       = require("services.slur_service")

local MelodyPathfinderService = {}

MelodyPathfinderService.SCALES = {
    { id = "auto",             name = "Auto (From Track Key Signature / Style)", intervals = nil },
    { id = "major",            name = "Major (Ionian)",                          intervals = { 0, 2, 4, 5, 7, 9, 11 } },
    { id = "aeolian",          name = "Natural Minor (Aeolian)",                 intervals = { 0, 2, 3, 5, 7, 8, 10 } },
    { id = "harmonic_minor",   name = "Harmonic Minor",                          intervals = { 0, 2, 3, 5, 7, 8, 11 } },
    { id = "melodic_minor",    name = "Melodic Minor",                           intervals = { 0, 2, 3, 5, 7, 9, 11 } },
    { id = "dorian",           name = "Dorian (Cinematic / Celtic)",             intervals = { 0, 2, 3, 5, 7, 9, 10 } },
    { id = "phrygian",         name = "Phrygian (Dark / Spanish / Thriller)",    intervals = { 0, 1, 3, 5, 7, 8, 10 } },
    { id = "lydian",           name = "Lydian (Wonder / Sci-Fi #4)",             intervals = { 0, 2, 4, 6, 7, 9, 11 } },
    { id = "mixolydian",       name = "Mixolydian (Heroic / Epic b7)",           intervals = { 0, 2, 4, 5, 7, 9, 10 } },
    { id = "minor_pentatonic", name = "Minor Pentatonic / Rock",                 intervals = { 0, 3, 5, 7, 10 } },
    { id = "blues_punk",       name = "Blues / Punk (Pentatonic + b5)",          intervals = { 0, 3, 5, 6, 7, 10 } },
}

MelodyPathfinderService.TRANSFORMS = {
    { id = "normal",               name = "Normal (Original Contour)" },
    { id = "inversion",            name = "Melodic Inversion (Mirror Intervals)" },
    { id = "retrograde",           name = "Retrograde (Reverse Motif Flow)" },
    { id = "retrograde_inversion", name = "Retrograde-Inversion (Mirror + Reverse)" },
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
    local target_track = nil
    local target_take = nil

    if state and state.selected_notes and next(state.selected_notes) ~= nil then
        for _, entry in pairs(state.selected_notes) do
            if entry and entry.take and reaper.ValidatePtr(entry.take, "MediaItem_Take*") and entry.idx then
                local ok, _, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(entry.take, entry.idx)
                if ok and not muted then
                    local sqn = reaper.MIDI_GetProjQNFromPPQPos(entry.take, sppq)
                    local eqn = reaper.MIDI_GetProjQNFromPPQPos(entry.take, eppq)
                    local trk = entry.track or reaper.GetMediaItemTake_Track(entry.take)
                    if not target_track then
                        target_track = trk
                        target_take = entry.take
                    end
                    if trk == target_track then
                        table.insert(raw, {
                            pitch = pitch,
                            start_qn = sqn,
                            end_qn = eqn,
                            dur_qn = math.max(0.125, eqn - sqn),
                            vel = vel or 96,
                            chan = chan or 0,
                            take = entry.take,
                            idx = entry.idx,
                            is_waypoint = true,
                        })
                    end
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

    return target_track, deduped, target_take
end

--- Collects MIDI notes from reference track(s) within [min_qn - 4, max_qn + 8]
--- @param ref_mode string|MediaTrack ("none", "auto_all", or MediaTrack*)
--- @param target_track MediaTrack|nil
--- @param min_qn number
--- @param max_qn number
--- @return table list of { pitch, start_qn, end_qn, dur_qn, vel }
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

    local q0 = (min_qn or 0) - 4.0
    local q1 = (max_qn or 64) + 8.0

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
                            if eqn >= q0 and sqn <= q1 then
                                table.insert(ref_notes, {
                                    pitch = pitch,
                                    start_qn = sqn,
                                    end_qn = eqn,
                                    dur_qn = math.max(0.1, eqn - sqn),
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

--- Builds a sorted list of scale pitches across MIDI 24..108
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
    for p = 24, 108 do
        if pc_set[p % 12] then
            table.insert(pitches, p)
            pitch_to_deg[p] = #pitches
        end
    end
    return pitches, pitch_to_deg, pc_set
end

--- Evaluates harmonic relationship between candidate pitch `p` and reference notes at `qn`
--- Returns a score in [-1.5 .. +1.5] scaled by `harmony_blend` (0.0 = dissonant/tense, 1.0 = consonant)
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
            -- Unison / Octave (good in unison orchestration, slightly less independent in counterpoint)
            c_val = is_counter_melody and 0.25 or 0.70
        elseif iv == 5 or iv == 2 or iv == 10 then
            -- 4th, Major 2nd, Minor 7th (suspensions / mild color)
            c_val = 0.15
        else
            -- Minor 2nd (1), Tritone (6), Major 7th (11) -> sharp dissonance
            c_val = -1.25
        end
        raw_consonance = raw_consonance + c_val

        -- Voice crossing & register spacing check in Counter-Melody mode
        if is_counter_melody and math.abs(p - rn.pitch) < 2 then
            raw_consonance = raw_consonance - 0.5
        end
    end
    raw_consonance = raw_consonance / #active_refs

    -- Map harmony_blend [0..1]:
    -- At 1.0 -> strongly reward consonance (+2.2 * raw_consonance)
    -- At 0.5 -> mildly reward consonance (+0.7 * raw_consonance)
    -- At 0.0 -> invert preference to reward tense dissonance (-1.5 * raw_consonance)
    local weight = (harmony_blend - 0.32) * 3.2
    local total_h_score = raw_consonance * weight

    -- Contrapuntal Contrary Motion bonus when Counter-Melody mode is active
    if is_counter_melody and prev_p and #prev_refs > 0 then
        local ref_now = active_refs[1].pitch
        local ref_prev = prev_refs[#prev_refs].pitch
        local ref_dir = ref_now - ref_prev
        local mel_dir = p - prev_p
        if (ref_dir > 0 and mel_dir < 0) or (ref_dir < 0 and mel_dir > 0) then
            total_h_score = total_h_score + 0.65 -- Contrary motion bonus!
        elseif ref_dir ~= 0 and mel_dir == ref_dir and (math.abs(p - ref_now) % 12 == 0 or math.abs(p - ref_now) % 12 == 7) then
            total_h_score = total_h_score - 0.90 -- Penalize parallel 5ths/8ves!
        end
    end

    return total_h_score
end

--- Builds rhythmic onset/duration steps between `start_qn` and `end_qn`
local function subdivide_segment_rhythm(start_qn, end_qn, style_obj, density_level, ref_notes, is_counter_melody, rng, memorized_cell)
    local span_qn = end_qn - start_qn
    if span_qn <= 0.15 then return {} end

    local d_key = "medium"
    if density_level <= 0.35 then
        d_key = "sparse"
    elseif density_level >= 0.68 then
        d_key = "dense"
    end

    local cells = (style_obj.rhythm_cells and style_obj.rhythm_cells[d_key]) or { { 1.0, 1.0, 1.0, 1.0 } }
    local steps = {}
    local cur = start_qn

    while cur < end_qn - 0.08 do
        local rem = end_qn - cur

        -- In Counter-Melody mode, adapt local density to complement the Reference Track!
        local cell_pool = cells
        if is_counter_melody and ref_notes and #ref_notes > 0 then
            local ref_onsets_in_window = 0
            for _, rn in ipairs(ref_notes) do
                if rn.start_qn >= cur - 0.05 and rn.start_qn < cur + math.min(4.0, rem) - 0.05 then
                    ref_onsets_in_window = ref_onsets_in_window + 1
                end
            end
            if ref_onsets_in_window <= 1 and style_obj.rhythm_cells.dense then
                -- Reference track holds a long note or rests -> Counter-melody fills the space!
                cell_pool = (density_level < 0.4) and style_obj.rhythm_cells.medium or style_obj.rhythm_cells.dense
            elseif ref_onsets_in_window >= 5 and style_obj.rhythm_cells.sparse then
                -- Reference track is very busy -> Counter-melody plays broader, calmer notes!
                cell_pool = style_obj.rhythm_cells.sparse
            end
        end

        -- Pick cell (reuse memorized_cell 65% of the time for motivic self-similarity)
        local chosen_cell = memorized_cell
        if not chosen_cell or rng() > 0.65 or is_counter_melody then
            local c_idx = math.floor(rng() * #cell_pool) + 1
            chosen_cell = cell_pool[c_idx] or cell_pool[1]
        end

        for _, d in ipairs(chosen_cell) do
            if cur >= end_qn - 0.08 then break end
            local dur = math.min(d, end_qn - cur)
            if dur >= 0.12 then
                table.insert(steps, { start_qn = cur, dur_qn = dur })
                cur = cur + dur
            else
                break
            end
        end
    end

    return steps, (memorized_cell or cells[1])
end

--- Solves the optimal melodic pitch path from `p_start` to `p_end` across `rhythm_steps`
--- using Viterbi Dynamic Programming + Meyer Gap-Fill + Target Gravity + Reference Harmony
local function solve_segment_viterbi(p_start, p_end, rhythm_steps, scale_pitches, style_obj, opts, ref_notes, rng)
    local K = #rhythm_steps
    if K == 0 then return {} end

    -- Filter candidate pitches within playable range around [min(p_start,p_end)-9 .. max(p_start,p_end)+9]
    local min_p = math.max(28, math.min(p_start, p_end) - 10)
    local max_p = math.min(96, math.max(p_start, p_end) + 10)
    local cands = {}
    for _, sp in ipairs(scale_pitches) do
        if sp >= min_p and sp <= max_p then
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

    local leap_pref = tonumber(opts.leap_character) or 0.5
    local harmony_blend = tonumber(opts.harmony_blend) or 0.75
    local is_counter = (opts.counter_melody_mode == true)

    -- Step 1 is anchored at p_start (if include_start_waypoint) or transitions from p_start
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

    -- Initialize k = 1 (first note of the segment IS the start waypoint p_start)
    for i = 1, N do
        if cands[i] == p_start then
            dp[1][i] = 0.0
        else
            dp[1][i] = -1e6
        end
    end

    -- Choose a cadential approach figure from the style corpus for the final step K
    local cad_list = style_obj.cadence_approaches or { { -1 }, { 1 } }
    local chosen_cad = cad_list[math.floor(rng() * #cad_list) + 1] or { -1 }
    local target_penultimate_semi = chosen_cad[#chosen_cad] or -1

    -- Forward Viterbi pass for k = 2 .. K
    for k = 2, K do
        local step_info = rhythm_steps[k]
        local frac = (k - 1) / math.max(1, K)
        -- Ideal linear/arch guide pitch at fraction `frac`
        local arch_offset = math.sin(frac * math.pi) * (opts.arch_height or 3.0)
        local guide_p = p_start + (p_end - p_start) * frac + arch_offset

        for j = 1, N do
            local p_curr = cands[j]
            local h_score = score_harmony_at_qn(
                p_curr, step_info.start_qn, step_info.dur_qn,
                ref_notes, nil, harmony_blend, is_counter
            )

            -- Guide contour attraction (stronger as we get closer to K)
            local dist_to_guide = math.abs(p_curr - guide_p)
            local guide_score = -dist_to_guide * (0.08 + 0.18 * frac)

            -- Cadential preparation bonus on the final step (k == K) before p_end
            local cad_bonus = 0.0
            if k == K then
                local diff_to_end = p_end - p_curr
                if diff_to_end == target_penultimate_semi or math.abs(diff_to_end) == 1 or math.abs(diff_to_end) == 2 then
                    cad_bonus = 2.4
                elseif diff_to_end == 0 and (style_obj.anticipation_prob or 0) > 0.3 then
                    cad_bonus = 1.8 -- Punky/Romantic anticipation of target note!
                elseif math.abs(diff_to_end) > 7 then
                    cad_bonus = -3.5 -- Avoid awkward huge jump into the anchor note
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

                    -- Adjust for user's Leap Character slider (0 = stepwise, 1 = wide heroic leaps)
                    if abs_iv >= 5 and abs_iv <= 12 then
                        iv_score = iv_score + (leap_pref - 0.45) * 1.6
                    elseif abs_iv >= 1 and abs_iv <= 2 then
                        iv_score = iv_score + (0.55 - leap_pref) * 1.1
                    elseif abs_iv > 12 then
                        iv_score = iv_score - 4.0
                    end

                    -- 2. Leonard Meyer's Gap-Fill Law (2nd-order check using backptr[k-1][i])
                    local gap_fill_bonus = 0.0
                    if k >= 3 then
                        local prev_prev_idx = backptr[k - 1][i]
                        local p_prev2 = cands[prev_prev_idx] or p_prev
                        local prev_iv = p_prev - p_prev2
                        if math.abs(prev_iv) >= 5 then
                            -- Previous step was a leap! Strongly reward contrary stepwise recovery
                            if (prev_iv > 0 and iv < 0 and abs_iv <= 3) or (prev_iv < 0 and iv > 0 and abs_iv <= 3) then
                                gap_fill_bonus = (style_obj.gap_fill_strength or 0.75) * 1.8
                            elseif (prev_iv > 0 and iv > 0) or (prev_iv < 0 and iv < 0) then
                                gap_fill_bonus = -1.2 -- Penalize consecutive leaps in same direction
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

                    local cand_total = dp[k - 1][i] + iv_score + gap_fill_bonus + h_score + cp_bonus + guide_score + cad_bonus + noise
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

--- Applies Melodic Inversion, Retrograde, or Retrograde-Inversion within scale degrees
local function apply_contour_transform(notes, transform_id, pivot_pitch, scale_pitches)
    if not transform_id or transform_id == "normal" or #notes <= 1 then
        return notes
    end

    -- Helper to snap any inverted pitch to the nearest active scale tone
    local function snap_to_scale(p)
        local best_p = p
        local best_d = 999
        for _, sp in ipairs(scale_pitches) do
            local d = math.abs(sp - p)
            if d < best_d then
                best_d = d
                best_p = sp
            end
        end
        return math.max(24, math.min(108, best_p))
    end

    local do_invert = (transform_id == "inversion" or transform_id == "retrograde_inversion")
    local do_retro  = (transform_id == "retrograde" or transform_id == "retrograde_inversion")

    if do_invert then
        local axis = pivot_pitch or notes[1].pitch
        for _, n in ipairs(notes) do
            if not n.is_waypoint or transform_id == "inversion" then
                local mirrored = axis - (n.pitch - axis)
                n.pitch = snap_to_scale(mirrored)
            end
        end
    end

    if do_retro and #notes >= 2 then
        -- Reverse pitch & duration sequence across the phrase span while keeping start_qn monotonic
        local q0 = notes[1].start_qn
        local rev_pitches = {}
        local rev_durs = {}
        local rev_vels = {}
        local rev_arts = {}
        for i = #notes, 1, -1 do
            table.insert(rev_pitches, notes[i].pitch)
            table.insert(rev_durs, notes[i].dur_qn)
            table.insert(rev_vels, notes[i].vel)
            table.insert(rev_arts, notes[i].art)
        end
        local cur_q = q0
        for i = 1, #notes do
            notes[i].pitch = rev_pitches[i]
            notes[i].start_qn = cur_q
            notes[i].dur_qn = rev_durs[i]
            notes[i].vel = rev_vels[i]
            notes[i].art = rev_arts[i]
            cur_q = cur_q + rev_durs[i]
        end
    end

    return notes
end

--- Generates the complete melody / counter-melody preview from current state & options
--- @param state table
--- @param active_tracks_data table
--- @param opts table
--- @return table result { notes = ..., waypoints = ..., ref_notes = ..., target_track = ..., status = ... }
function MelodyPathfinderService.generate_preview(state, active_tracks_data, opts)
    opts = opts or {}
    local style_id = opts.style_id or "cinematic"
    local style_obj = MelodyStyleCorpus.BY_ID[style_id] or MelodyStyleCorpus.STYLES[1]
    local rng = make_rng(opts.seed or 1001)

    local target_track, waypoints, target_take = MelodyPathfinderService.get_selected_waypoints(state, active_tracks_data)

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
    elseif #waypoints == 1 then
        min_qn = waypoints[1].start_qn
        max_qn = min_qn + (phrase_bars * qn_per_bar)
    else
        local cur_sec = reaper.GetCursorPosition()
        min_qn = math.floor(reaper.TimeMap2_timeToQN(0, cur_sec) + 0.5)
        max_qn = min_qn + (phrase_bars * qn_per_bar)
    end

    local ref_notes = MelodyPathfinderService.collect_reference_notes(
        opts.ref_track_mode, target_track, min_qn, max_qn
    )

    -- If only 1 waypoint (or 0 waypoints) is selected, synthesize musical landmark waypoints
    -- across `phrase_bars` so Single-Note Counter-Melody / Seed Generation works effortlessly!
    local effective_waypoints = {}
    for _, wp in ipairs(waypoints) do
        table.insert(effective_waypoints, {
            pitch = wp.pitch,
            start_qn = wp.start_qn,
            dur_qn = wp.dur_qn,
            vel = wp.vel,
            chan = wp.chan,
            is_waypoint = true,
        })
    end

    if #effective_waypoints < 2 then
        local seed_pitch = (effective_waypoints[1] and effective_waypoints[1].pitch) or 60
        local seed_chan  = (effective_waypoints[1] and effective_waypoints[1].chan) or 0
        local seed_vel   = (effective_waypoints[1] and effective_waypoints[1].vel) or 96

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

        -- Create 1 structural waypoint per measure across `phrase_bars`
        local arch_Offsets = { 4, 7, 3, 0, 5, 8, 2, 0 }
        for b = 1, phrase_bars do
            local w_qn = min_qn + (b * qn_per_bar)
            local target_p = seed_pitch + (arch_Offsets[((b - 1) % #arch_Offsets) + 1] or 0)

            -- If Reference Track has notes near `w_qn`, pick a consonant contrapuntal pitch (3rd or 6th above/below)!
            if #ref_notes > 0 then
                for _, rn in ipairs(ref_notes) do
                    if math.abs(rn.start_qn - w_qn) < 1.5 then
                        local interval_choices = { 3, 4, 8, 9, -3, -4, 7 }
                        local pick_iv = interval_choices[math.floor(rng() * #interval_choices) + 1]
                        target_p = rn.pitch + pick_iv
                        break
                    end
                end
            end

            -- Snap `target_p` to scale
            local best_sp = seed_pitch
            local best_d = 999
            for _, sp in ipairs(scale_pitches) do
                if math.abs(sp - target_p) < best_d then
                    best_d = math.abs(sp - target_p)
                    best_sp = sp
                end
            end

            table.insert(effective_waypoints, {
                pitch = best_sp,
                start_qn = (b == phrase_bars) and (max_qn - 1.0) or w_qn,
                dur_qn = 1.0,
                vel = seed_vel,
                chan = seed_chan,
                is_waypoint = (b == 1 and #waypoints == 1) and false or false,
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
            wA.pitch, wB.pitch, seg_steps, scale_pitches, style_obj, opts, ref_notes, rng
        )

        for k, st in ipairs(seg_steps) do
            local is_anchor = (k == 1 and wA.is_waypoint)
            local p = is_anchor and wA.pitch or (seg_pitches[k] or wA.pitch)
            local dur = st.dur_qn * (style_obj.legato_ratio or 0.92)

            -- Articulation & dynamic phrasing curve
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

            -- Shape velocity arch across the segment
            local seg_frac = (k - 1) / math.max(1, #seg_steps)
            local vel_curve = math.sin(seg_frac * math.pi) * 14
            local base_vel = is_anchor and (wA.vel or 100) or 86
            if art == "accent" then base_vel = base_vel + 12 end
            local vel = math.max(52, math.min(124, math.floor(base_vel + vel_curve + (rng() - 0.5) * 8)))

            table.insert(generated, {
                pitch = p,
                start_qn = math.floor(st.start_qn * 1000 + 0.5) / 1000,
                dur_qn = math.max(0.1, math.floor(dur * 1000 + 0.5) / 1000),
                vel = vel,
                chan = wA.chan or 0,
                art = art,
                is_waypoint = is_anchor,
            })
        end
    end

    -- Append the final waypoint W_last
    local wLast = effective_waypoints[#effective_waypoints]
    if wLast then
        table.insert(generated, {
            pitch = wLast.pitch,
            start_qn = math.floor(wLast.start_qn * 1000 + 0.5) / 1000,
            dur_qn = math.max(0.25, wLast.dur_qn or 1.0),
            vel = wLast.vel or 102,
            chan = wLast.chan or 0,
            art = "tenuto",
            is_waypoint = wLast.is_waypoint,
        })
    end

    -- Apply optional Melodic Inversion / Retrograde contour transformation
    if opts.transform_id and opts.transform_id ~= "normal" then
        local pivot = (effective_waypoints[1] and effective_waypoints[1].pitch) or 60
        generated = apply_contour_transform(generated, opts.transform_id, pivot, scale_pitches)
    end

    return {
        notes = generated,
        waypoints = waypoints,
        ref_notes = ref_notes,
        target_track = target_track,
        target_take = target_take,
        style = style_obj,
        min_qn = min_qn,
        max_qn = max_qn,
    }
end

--- Directly inverts the currently selected notes in the score around their first note (or average pitch)
function MelodyPathfinderService.invert_selected_notes_in_place(state, active_tracks_data, scale_id)
    local target_track, waypoints, target_take = MelodyPathfinderService.get_selected_waypoints(state, active_tracks_data)
    if not target_take or #waypoints < 2 then
        return false, "Select at least 2 notes to invert."
    end

    local key_idx = (state and state.get_key_signature_at_qn and state:get_key_signature_at_qn(target_track, waypoints[1].start_qn)) or 0
    local tonic_pc = KEY_IDX_TO_TONIC_PC[key_idx] or 0
    local scale_pitches = MelodyPathfinderService.build_scale_pitches(tonic_pc, scale_id or "auto", nil)
    local axis = waypoints[1].pitch

    reaper.Undo_BeginBlock()
    for _, wp in ipairs(waypoints) do
        local mirrored = axis - (wp.pitch - axis)
        local best_p = mirrored
        local best_d = 999
        for _, sp in ipairs(scale_pitches) do
            if math.abs(sp - mirrored) < best_d then
                best_d = math.abs(sp - mirrored)
                best_p = sp
            end
        end
        best_p = math.max(12, math.min(115, best_p))
        if wp.take and wp.idx then
            reaper.MIDI_SetNote(wp.take, wp.idx, nil, nil, nil, nil, nil, best_p, nil, true)
        end
    end
    reaper.MIDI_Sort(target_take)
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Notator: Melodic Inversion on Selection", -1)
    return true, string.format("Inverted %d selected notes around pitch %d", #waypoints, axis)
end

--- Commits the generated preview melody into the target REAPER track / MIDI take
function MelodyPathfinderService.apply_generated_melody(state, preview, midi_service, opts)
    if not preview or not preview.notes or #preview.notes == 0 then
        return false, "No generated melody notes to insert."
    end

    local target_track = (opts and opts.output_track and reaper.ValidatePtr(opts.output_track, "MediaTrack*"))
        and opts.output_track
        or preview.target_track
    if not target_track or not reaper.ValidatePtr(target_track, "MediaTrack*") then
        return false, "No valid target track found."
    end

    local min_qn = preview.notes[1].start_qn
    local last_n = preview.notes[#preview.notes]
    local max_qn = last_n.start_qn + (last_n.dur_qn or 1.0)
    local span_qn = math.max(4.0, max_qn - min_qn)

    reaper.Undo_BeginBlock()

    local take = preview.target_take
    if (opts and opts.output_track and opts.output_track ~= preview.target_track) or not (take and reaper.ValidatePtr(take, "MediaItem_Take*")) then
        local _, new_take = midi_service.get_or_create_item_at_qn(target_track, min_qn, span_qn)
        take = new_take
    end

    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        reaper.Undo_EndBlock("Notator: Melodic Pathfinder (Failed)", -1)
        return false, "Could not resolve or create MIDI take."
    end

    -- Ensure the MIDI item extends far enough to hold the entire generated phrase
    local item = reaper.GetMediaItemTake_Item(take)
    if item and reaper.ValidatePtr(item, "MediaItem*") then
        local item_start_sec = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local item_end_sec = item_start_sec + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local needed_end_sec = reaper.TimeMap2_QNToTime(0, max_qn + 0.5)
        if needed_end_sec > item_end_sec then
            reaper.SetMediaItemInfo_Value(item, "D_LENGTH", needed_end_sec - item_start_sec)
        end
    end

    -- If writing onto the same take where waypoints were selected, remove the original waypoints first
    -- (since `preview.notes` already includes the waypoints at their exact positions with tailored durations)
    if target_track == preview.target_track and preview.waypoints and #preview.waypoints > 0 then
        local idxs = {}
        for _, wp in ipairs(preview.waypoints) do
            if wp.take == take and wp.idx ~= nil then
                table.insert(idxs, wp.idx)
            end
        end
        table.sort(idxs, function(a, b) return a > b end)
        for _, idx in ipairs(idxs) do
            reaper.MIDI_DeleteNote(take, idx)
        end
    end

    -- Insert all generated melody notes (and select them so the user sees them highlighted!)
    reaper.MIDI_SelectAll(take, false)
    for _, gn in ipairs(preview.notes) do
        local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, gn.start_qn)
        local eppq = reaper.MIDI_GetPPQPosFromProjQN(take, gn.start_qn + gn.dur_qn)
        local p = math.max(0, math.min(127, math.floor(gn.pitch + 0.5)))
        local v = math.max(1, math.min(127, math.floor(gn.vel or 90)))
        local c = math.max(0, math.min(15, math.floor(gn.chan or 0)))
        reaper.MIDI_InsertNote(take, true, false, sppq, eppq, c, p, v, true)
    end

    reaper.MIDI_Sort(take)

    -- Optional Auto-Slur across legato phrases
    if opts and opts.auto_slur and SlurService and SlurService.add_slur then
        SlurService.add_slur(state, target_track, min_qn, max_qn, 1)
    end

    reaper.MarkTrackItemsDirty(target_track, item)
    reaper.UpdateArrange()
    state.force_refresh = true

    local mode_lbl = (opts and opts.counter_melody_mode) and "Counter-Melody" or "Melodic Pathfinder"
    reaper.Undo_EndBlock("Notator: " .. mode_lbl .. " (" .. #preview.notes .. " notes)", -1)
    return true, string.format("Inserted %d notes (%s)", #preview.notes, preview.style and preview.style.name or mode_lbl)
end

return MelodyPathfinderService


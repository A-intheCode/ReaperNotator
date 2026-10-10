-- ==============================================================================
-- REAPER Native Notator - Module: Engraver
-- Engraving rules: measure division, rests, accidentals & standard-compliant beams
-- ==============================================================================

local Constants = require("constants")
local SMUFL = Constants.SMUFL
local OctaveService = require("services.octave_service")

local Engraver = {}

function Engraver.get_flag_count(dur_qn)
    if not dur_qn or dur_qn <= 0 then return 0 end
    -- Dotted note values
    if math.abs(dur_qn - 0.75) < 0.025 then return 1 end   -- dotted eighth note (1 flag)
    if math.abs(dur_qn - 0.375) < 0.015 then return 2 end  -- dotted 16th note (2 flags)
    if math.abs(dur_qn - 0.1875) < 0.008 then return 3 end -- dotted 32nd note (3 flags)
    
    -- Continuous rhythmic zones (including all tuplets according to Gardner Read / Elaine Gould):
    if dur_qn >= 0.57 then return 0 end  -- Quarter (1.0), quintuplet quarter (0.80), triplet quarter (0.667), septuplet quarter (0.571)
    if dur_qn >= 0.27 then return 1 end  -- Eighth (0.50), quintuplet eighth (0.40), triplet eighth (0.333), septuplet eighth (0.286)
    if dur_qn >= 0.13 then return 2 end  -- 16th (0.25), quintuplet 16th (0.20), triplet 16th (0.167), septuplet 16th (0.143)
    if dur_qn >= 0.065 then return 3 end -- 32nd (0.125), quintuplet 32nd (0.10), triplet 32nd (0.083), septuplet 32nd (0.071)
    return 4                             -- 64th (0.0625)
end

function Engraver.get_nominal_rhythmic_duration(raw_dur)
    if not raw_dur or raw_dur <= 0 then return 0.25 end
    if raw_dur >= 3.85 then
        return 4.0
    elseif raw_dur >= 2.65 then
        return 3.0
    elseif raw_dur >= 1.75 then
        return 2.0
    elseif raw_dur >= 1.25 then
        return 1.5
    elseif raw_dur >= 0.85 then
        return 1.0
    elseif raw_dur >= 0.60 then
        return 0.75
    elseif raw_dur >= 0.35 then
        return 0.5
    elseif raw_dur >= 0.18 then
        return 0.25
    elseif raw_dur >= 0.09 then
        return 0.125
    else
        return 0.0625
    end
end

function Engraver.is_dotted_duration(dur_qn)
    local dotted_vals = { 6.0, 3.0, 1.5, 0.75, 0.375, 0.1875 }
    for _, dv in ipairs(dotted_vals) do
        local tol = math.min(0.015, dv * 0.04)
        if math.abs(dur_qn - dv) < tol then return true end
    end
    return false
end

function Engraver.build_measure_map(active_tracks_data, total_measures, qn_per_measure, margin_left, s, state)
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0
    local base_w = 260.0 * s * (bpi / 4.0)
    local pad_left = 30.0 * s
    local pad_right = 25.0 * s
    
    local widths = {}
    local pad_lefts = {}
    local onsets_by_bar = {}
    local num_m = math.max(total_measures + 4, 32)
    
    local has_kss, KeySignatureService = pcall(require, "services.key_signature_service")
    if not has_kss or not KeySignatureService then
        has_kss, KeySignatureService = pcall(require, "modules.services.key_signature_service")
    end
    local key_changes = nil
    if has_kss and KeySignatureService and KeySignatureService.get_measure_key_signature_changes then
        key_changes = KeySignatureService.get_measure_key_signature_changes(state, active_tracks_data, num_m, bpi, s)
    end
    
    local dq = (state and state.display_quantize and state.display_quantize_grid and state.display_quantize_grid > 0.001) and state.display_quantize_grid or nil
    -- Pre-generate or retrieve cached rests per track so they are factored into measure width calculation
    local rests_by_track = {}
    local r_key = string.format("%d_%.3f_%s", num_m + 1, bpi, tostring(dq))
    for _, tdata in ipairs(active_tracks_data or {}) do
        local r_cache = tdata.rests_cache
        local tr_rests = r_cache and r_cache[r_key]
        if not tr_rests then
            tr_rests = Engraver.generate_voice_rests(tdata.notes or {}, num_m + 1, bpi, dq)
            if r_cache then
                r_cache[r_key] = tr_rests
            end
        end
        rests_by_track[tdata] = tr_rests
    end
    
    -- O(N) note and rest bucketing by measure
    local track_notes_by_bar = {}
    local track_rests_by_bar = {}
    for _, tdata in ipairs(active_tracks_data or {}) do
        local notes_by_bar = {}
        track_notes_by_bar[tdata] = notes_by_bar
        if tdata.notes and #tdata.notes > 0 then
            for _, n in ipairs(tdata.notes) do
                local m = math.floor(n.start_qn / bpi + 0.0001)
                if m >= 0 and m <= num_m then
                    local b_list = notes_by_bar[m]
                    if not b_list then
                        b_list = {}
                        notes_by_bar[m] = b_list
                    end
                    table.insert(b_list, n)
                end
            end
        end

        local rests_by_bar = {}
        track_rests_by_bar[tdata] = rests_by_bar
        local tr_rests = rests_by_track[tdata]
        if tr_rests and #tr_rests > 0 then
            for _, r in ipairs(tr_rests) do
                if not r.is_full_measure then
                    local m = math.floor(r.start_qn / bpi + 0.0001)
                    if m >= 0 and m <= num_m then
                        local r_list = rests_by_bar[m]
                        if not r_list then
                            r_list = {}
                            rests_by_bar[m] = r_list
                        end
                        table.insert(r_list, r)
                    end
                end
            end
        end
    end

    -- For each measure from 0 to num_m
    for m = 0, num_m do
        local m_start_qn = m * bpi
        local m_end_qn = (m + 1) * bpi
        local max_needed_for_m = base_w
        local m_combined_onsets = {}
        
        -- Check all active tracks for note density, accidentals, dots, and rests in measure m
        for _, tdata in ipairs(active_tracks_data or {}) do
            local onsets = {}
            local bar_notes = track_notes_by_bar[tdata] and track_notes_by_bar[tdata][m]
            if bar_notes then
                for _, n in ipairs(bar_notes) do
                    local rounded_qn = math.floor(n.start_qn * 32.0 + 0.5) / 32.0
                    local rel_qn = math.floor((n.start_qn - m_start_qn) * 32.0 + 0.5) / 32.0
                    m_combined_onsets[rel_qn] = true
                    if not onsets[rounded_qn] then
                        onsets[rounded_qn] = {
                            qn = n.start_qn,
                            has_acc = false,
                            has_dot = false,
                            count = 0,
                            is_rest = false
                        }
                    end
                    local o = onsets[rounded_qn]
                    o.count = o.count + 1
                    
                    -- Check accidentals
                    local k = n.key or (n.get_key and n:get_key())
                    local pref_acc = state and state.note_accidentals and state.note_accidentals[k]
                    if pref_acc == nil and state and state.note_accidentals and n.take then
                        local id_k = string.format("%s_%s_%.3f", tostring(n.take or "0"), tostring(n.idx), n.start_qn)
                        pref_acc = state.note_accidentals[id_k]
                    end
                    local p_mod = n.pitch % 12
                    local is_black = (p_mod == 1 or p_mod == 3 or p_mod == 6 or p_mod == 8 or p_mod == 10)
                    if pref_acc == 1 or pref_acc == -1 or pref_acc == 2 or (is_black and pref_acc ~= 0) then
                        o.has_acc = true
                    end
                    
                    -- Check augmentation dots
                    if Engraver.is_dotted_duration(n.dur_qn) then
                        o.has_dot = true
                    end
                end
            end
            
            -- Include rests (e.g. 16th / 32nd rests) in space allocation
            local bar_rests = track_rests_by_bar[tdata] and track_rests_by_bar[tdata][m]
            if bar_rests then
                for _, r in ipairs(bar_rests) do
                    local rounded_qn = math.floor(r.start_qn * 32.0 + 0.5) / 32.0
                    local rel_qn = math.floor((r.start_qn - m_start_qn) * 32.0 + 0.5) / 32.0
                    m_combined_onsets[rel_qn] = true
                    if not onsets[rounded_qn] then
                        onsets[rounded_qn] = {
                            qn = r.start_qn,
                            has_acc = false,
                            has_dot = false,
                            count = 1,
                            is_rest = true
                        }
                    end
                end
            end
            
            -- Calculate required width for this track in measure m
            local sorted_onsets = {}
            for _, o in pairs(onsets) do
                table.insert(sorted_onsets, o)
            end
            table.sort(sorted_onsets, function(a, b) return a.qn < b.qn end)
            
            if #sorted_onsets > 0 then
                local track_needed_w = pad_left + pad_right
                for idx, o in ipairs(sorted_onsets) do
                    local onset_w = o.is_rest and (16.0 * s) or (11.5 * s) -- Rest or notehead
                    if o.has_acc then
                        onset_w = onset_w + 14.0 * s -- Accidental on left
                    end
                    if o.has_dot then
                        onset_w = onset_w + 10.0 * s -- Augmentation dot on right
                    end
                    if o.count > 1 then
                        onset_w = onset_w + 6.0 * s -- Chord displacement / second interval offset
                    end
                    
                    local gap = (idx < #sorted_onsets) and (16.0 * s) or (6.0 * s)
                    track_needed_w = track_needed_w + onset_w + gap
                end
                
                if track_needed_w > max_needed_for_m then
                    max_needed_for_m = track_needed_w
                end
            end
        end
        
        local m_pad_l = pad_left
        if key_changes and key_changes[m] and key_changes[m].has_change then
            local extra_kw = (key_changes[m].max_kw or 0) + 12.0 * s
            m_pad_l = m_pad_l + extra_kw
            max_needed_for_m = math.max(max_needed_for_m, base_w + extra_kw)
        end
        pad_lefts[m] = m_pad_l
        widths[m] = max_needed_for_m
        
        local sorted_bar_onsets = {}
        for o_qn in pairs(m_combined_onsets) do
            table.insert(sorted_bar_onsets, o_qn)
        end
        table.sort(sorted_bar_onsets)
        onsets_by_bar[m] = sorted_bar_onsets
    end
    
    -- Calculate start positions of all measures
    local starts = {}
    local cur_x = margin_left
    for m = 0, num_m do
        starts[m] = cur_x
        cur_x = cur_x + (widths[m] or base_w)
    end
    starts[num_m + 1] = cur_x
    
    return {
        bpi = bpi,
        num_m = num_m,
        base_w = base_w,
        pad_left = pad_left,
        pad_lefts = pad_lefts,
        pad_right = pad_right,
        widths = widths,
        starts = starts,
        margin_left = margin_left,
        total_measures = total_measures,
        total_score_w = cur_x - margin_left,
        onsets_by_bar = onsets_by_bar,
        key_changes = key_changes
    }
end

function Engraver.reanchor_measure_map(measure_map, new_margin_left)
    if not measure_map or not measure_map.starts or not measure_map.margin_left then return end
    local delta = new_margin_left - measure_map.margin_left
    if math.abs(delta) < 0.0001 then return end
    local max_m = (measure_map.num_m and (measure_map.num_m + 1)) or (#measure_map.starts + 1)
    for m = 0, max_m do
        if measure_map.starts[m] then
            measure_map.starts[m] = measure_map.starts[m] + delta
        end
    end
    measure_map.margin_left = new_margin_left
end

function Engraver.get_measure_layout(s, qn_per_measure)
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4
    local base_w = 260 * s
    local measure_w = base_w * (bpi / 4.0)
    local pad_left = 20 * s
    local pad_right = 20 * s
    local usable_w = measure_w - pad_left - pad_right
    return measure_w, pad_left, pad_right, usable_w
end

function Engraver.qn_to_canvas_x(qn, margin_left, s, qn_per_measure, measure_map)
    local bpi = (measure_map and measure_map.bpi) or ((qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4)
    local m_idx = math.floor(qn / bpi)
    if m_idx < 0 then m_idx = 0 end
    local qn_in_m = qn - (m_idx * bpi)
    
    if not measure_map or not measure_map.starts then
        local measure_w, pad_left, pad_right, usable_w = Engraver.get_measure_layout(s, bpi)
        local m_x = margin_left + (m_idx * measure_w)
        return m_x + pad_left + (qn_in_m / bpi) * usable_w
    end
    
    local m_start_x = measure_map.starts[m_idx]
    local m_w = measure_map.widths[m_idx]
    if not m_start_x then
        local last_idx = measure_map.num_m or (#measure_map.starts - 1)
        m_start_x = (measure_map.starts[last_idx] or margin_left) + (m_idx - last_idx) * measure_map.base_w
        m_w = measure_map.base_w
    end
    m_w = m_w or measure_map.base_w
    
    local pad_l = (measure_map.pad_lefts and measure_map.pad_lefts[m_idx]) or measure_map.pad_left or (30.0 * s)
    local pad_r = measure_map.pad_right or (30.0 * s)
    local usable_w = math.max(10.0 * s, m_w - pad_l - pad_r)
    
    -- Linear note placement based on onset within the measure (beat 1 placed on the left at pad_l)
    return m_start_x + pad_l + (qn_in_m / bpi) * usable_w
end

function Engraver.cursor_qn_to_canvas_x(qn, margin_left, s, qn_per_measure, measure_map)
    if not measure_map or not measure_map.starts then
        local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4
        local m_idx = math.floor(qn / bpi)
        local qn_in_m = qn - (m_idx * bpi)
        local measure_w = Engraver.get_measure_layout(s, bpi)
        local m_x = margin_left + (m_idx * measure_w)
        return m_x + (qn_in_m / bpi) * measure_w
    end
    
    local bpi = measure_map.bpi
    local m_idx = math.floor(qn / bpi)
    if m_idx < 0 then m_idx = 0 end
    local qn_in_m = qn - (m_idx * bpi)
    
    local m_start_x = measure_map.starts[m_idx]
    local m_w = measure_map.widths[m_idx]
    if not m_start_x then
        local last_idx = measure_map.num_m or (#measure_map.starts - 1)
        m_start_x = (measure_map.starts[last_idx] or margin_left) + (m_idx - last_idx) * measure_map.base_w
        m_w = measure_map.base_w
    end
    m_w = m_w or measure_map.base_w
    
    return m_start_x + (qn_in_m / bpi) * m_w
end

function Engraver.canvas_x_to_qn(x, margin_left, s, qn_per_measure, grid_qn, measure_map)
    local bpi = (measure_map and measure_map.bpi) or ((qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4)
    local snap = (grid_qn and grid_qn > 0) and grid_qn or 0.25
    
    local function calc_measure_qn(m_idx, m_start_x, m_w, cur_x, pad_l, pad_r)
        local usable_w = math.max(10.0 * s, m_w - pad_l - pad_r)
        local rel_x = cur_x - m_start_x
        local raw_qn_in_m
        if rel_x <= pad_l then
            raw_qn_in_m = 0.0
        elseif rel_x >= pad_l + usable_w then
            raw_qn_in_m = bpi - 0.0001
        else
            raw_qn_in_m = ((rel_x - pad_l) / usable_w) * bpi
        end
        local snapped = math.floor((raw_qn_in_m / snap) + 0.5) * snap
        local max_snap = (snap <= bpi) and (bpi - snap) or 0.0
        snapped = math.max(0.0, math.min(max_snap, snapped))
        return (m_idx * bpi) + snapped
    end
    
    if not measure_map or not measure_map.starts then
        local measure_w, pad_left, pad_right, usable_w = Engraver.get_measure_layout(s, bpi)
        local rel_x = x - margin_left
        if rel_x <= 0 then return 0 end
        local m_idx = math.floor(rel_x / measure_w)
        local m_start_x = margin_left + (m_idx * measure_w)
        return calc_measure_qn(m_idx, m_start_x, measure_w, x, pad_left, pad_right)
    end
    
    local starts = measure_map.starts
    local num_starts = measure_map.num_m or #starts
    local pad_l = measure_map.pad_left or (30.0 * s)
    local pad_r = measure_map.pad_right or (25.0 * s)
    
    if x <= (starts[0] or margin_left) then
        return 0
    end
    
    for m = 0, num_starts - 1 do
        if starts[m] and starts[m + 1] and x >= starts[m] and x < starts[m + 1] then
            local m_w = starts[m + 1] - starts[m]
            return calc_measure_qn(m, starts[m], m_w, x, pad_l, pad_r)
        end
    end
    
    -- Beyond defined measures
    local last_m = num_starts
    local last_x = starts[last_m] or starts[num_starts - 1] or margin_left
    local m_w = measure_map.base_w or (260.0 * s)
    local rel_x = x - last_x
    if rel_x < 0 then rel_x = 0 end
    local extra_m = math.floor(rel_x / m_w)
    local extra_m_start = last_x + (extra_m * m_w)
    return calc_measure_qn(last_m + extra_m, extra_m_start, m_w, x, pad_l, pad_r)
end

local ENHARMONIC_SPELLINGS = {
    [0] = {
        [1]  = { step = 6, acc = 1,  name = "B#", oct_shift = -1 },
        [-1] = { step = 0, acc = 0,  name = "C" },
        [0]  = { step = 0, acc = 0,  name = "C" },
        [2]  = { step = 0, acc = 2,  name = "C♮" },
    },
    [1] = {
        [1]  = { step = 0, acc = 1,  name = "C#" },
        [-1] = { step = 1, acc = -1, name = "Db" },
        [0]  = { step = 0, acc = 1,  name = "C#" },
    },
    [2] = {
        [1]  = { step = 1, acc = 0,  name = "D" },
        [-1] = { step = 1, acc = 0,  name = "D" },
        [0]  = { step = 1, acc = 0,  name = "D" },
        [2]  = { step = 1, acc = 2,  name = "D♮" },
    },
    [3] = {
        [1]  = { step = 1, acc = 1,  name = "D#" },
        [-1] = { step = 2, acc = -1, name = "Eb" },
        [0]  = { step = 2, acc = -1, name = "Eb" },
    },
    [4] = {
        [1]  = { step = 2, acc = 0,  name = "E" },
        [-1] = { step = 3, acc = -1, name = "Fb" },
        [0]  = { step = 2, acc = 0,  name = "E" },
        [2]  = { step = 2, acc = 2,  name = "E♮" },
    },
    [5] = {
        [1]  = { step = 2, acc = 1,  name = "E#" },
        [-1] = { step = 3, acc = 0,  name = "F" },
        [0]  = { step = 3, acc = 0,  name = "F" },
        [2]  = { step = 3, acc = 2,  name = "F♮" },
    },
    [6] = {
        [1]  = { step = 3, acc = 1,  name = "F#" },
        [-1] = { step = 4, acc = -1, name = "Gb" },
        [0]  = { step = 3, acc = 1,  name = "F#" },
    },
    [7] = {
        [1]  = { step = 4, acc = 0,  name = "G" },
        [-1] = { step = 4, acc = 0,  name = "G" },
        [0]  = { step = 4, acc = 0,  name = "G" },
        [2]  = { step = 4, acc = 2,  name = "G♮" },
    },
    [8] = {
        [1]  = { step = 4, acc = 1,  name = "G#" },
        [-1] = { step = 5, acc = -1, name = "Ab" },
        [0]  = { step = 4, acc = 1,  name = "G#" },
    },
    [9] = {
        [1]  = { step = 5, acc = 0,  name = "A" },
        [-1] = { step = 5, acc = 0,  name = "A" },
        [0]  = { step = 5, acc = 0,  name = "A" },
        [2]  = { step = 5, acc = 2,  name = "A♮" },
    },
    [10] = {
        [1]  = { step = 5, acc = 1,  name = "A#" },
        [-1] = { step = 6, acc = -1, name = "Bb" },
        [0]  = { step = 6, acc = -1, name = "Bb" },
    },
    [11] = {
        [1]  = { step = 6, acc = 0,  name = "B" },
        [-1] = { step = 0, acc = -1, name = "Cb", oct_shift = 1 },
        [0]  = { step = 6, acc = 0,  name = "B" },
        [2]  = { step = 6, acc = 2,  name = "B♮" },
    },
}

function Engraver.get_track_clef(track_or_guid, p2, p3, state)
    local track_name, track_notes
    if type(p2) == "string" then
        track_name = p2
        track_notes = p3
    elseif type(p3) == "string" then
        track_name = p3
        track_notes = p2
    else
        track_name = ""
        track_notes = p2 or p3
    end

    local guid = ""
    if type(track_or_guid) == "string" then
        guid = track_or_guid
    elseif track_or_guid and reaper and reaper.ValidatePtr and reaper.ValidatePtr(track_or_guid, "MediaTrack*") then
        guid = reaper.GetTrackGUID(track_or_guid)
    end

    if state and state.track_clefs and guid ~= "" then
        local saved = state.track_clefs[guid] or (guid.upper and state.track_clefs[guid:upper()]) or (guid.lower and state.track_clefs[guid:lower()])
        if saved and saved ~= "auto" then
            return saved
        end
    end

    if state and state.view_mode and state.view_mode ~= "auto" and (state.view_mode == "treble" or state.view_mode == "bass" or state.view_mode == "grand" or state.view_mode == "alto") then
        return state.view_mode
    end

    local name_l = (track_name or ""):lower()

    -- 1. Explicit harp instruments (3 staves)
    if name_l:find("harfe") or name_l:find("harp") then
        return "harp_3staff"
    end

    -- 2. Explicit grand staff instruments (keyboard instruments)
    if name_l:find("piano") or name_l:find("klavier") or name_l:find("flügel") or name_l:find("fluegel") or
       name_l:find("steinway") or name_l:find("organ") or name_l:find("orgel") or 
       name_l:find("celesta") or name_l:find("cembalo") or name_l:find("harpsichord") or
       name_l:find("accord") or name_l:find("akkord") or name_l:find("keyboard") or name_l:find("keys") or name_l:find("rhodes") then
        return "grand"
    end

    -- 3. Explicit alto instruments (viola)
    if name_l:find("viola") or name_l:find("violen") or name_l:find("bratsche") or name_l:find("bratschen") or
       name_l:match("%f[%a]vla%f[%A]") or name_l == "va" then
        return "alto"
    end

    -- 4. Explicit bass instruments (cellos, double bass, tuba, bassoon, trombone, timpani, etc.)
    if name_l:find("cell") or name_l:find("violoncell") or name_l:match("%f[%a]vc%f[%A]") or name_l:match("%f[%a]vlc%f[%A]") or
       name_l:find("bass") or name_l:find("kontra") or name_l:find("contra") or name_l:match("%f[%a]cb%f[%A]") or name_l:match("%f[%a]kb%f[%A]") or name_l:match("%f[%a]db%f[%A]") or
       name_l:find("tuba") or name_l:find("fagott") or name_l:find("bassoon") or name_l:match("%f[%a]bsn%f[%A]") or name_l:match("%f[%a]fgt%f[%A]") or
       name_l:find("posaune") or name_l:find("trombone") or name_l:match("%f[%a]trb%f[%A]") or name_l:match("%f[%a]pos%f[%A]") or name_l:match("%f[%a]tbn%f[%A]") or
       name_l:find("timpani") or name_l:find("pauke") or name_l:find("pauken") or name_l:match("%f[%a]timp%f[%A]") or
       name_l:find("baritone") or name_l:find("euphonium") or name_l:find("kick") then
        return "bass"
    end

    -- 5. Explicit treble instruments (violin, flute, oboe, clarinet, trumpet, horn, guitar, etc.)
    if name_l:find("violin") or name_l:find("violine") or name_l:find("geige") or name_l:find("fiddle") or name_l:match("%f[%a]vln%f[%A]") or name_l:match("%f[%a]vn%f[%A]") or
       name_l:find("flute") or name_l:find("flöte") or name_l:find("piccolo") or name_l:match("%f[%a]fl%f[%A]") or name_l:match("%f[%a]picc%f[%A]") or
       name_l:find("oboe") or name_l:find("cor anglais") or name_l:find("englischhorn") or name_l:match("%f[%a]ob%f[%A]") or name_l:match("%f[%a]eh%f[%A]") or
       name_l:find("clarinet") or name_l:find("klarinette") or name_l:match("%f[%a]cl%f[%A]") or name_l:match("%f[%a]kl%f[%A]") or
       name_l:find("trumpet") or name_l:find("trompete") or name_l:find("cornet") or name_l:match("%f[%a]tpt%f[%A]") or name_l:match("%f[%a]trp%f[%A]") or
       name_l:find("horn") or name_l:find("corno") or name_l:match("%f[%a]hn%f[%A]") or name_l:match("%f[%a]cr%f[%A]") or
       name_l:find("guitar") or name_l:find("gitarre") or name_l:match("%f[%a]git%f[%A]") or
       name_l:find("sopran") or name_l:find("voice") or name_l:find("gesang") or
       name_l:find("sax") then
        return "treble"
    end

    -- 6. Pitch fallback if instrument name is unknown
    if track_notes and #track_notes > 0 then
        local sum_p = 0
        local count = 0
        local min_p = 127
        local max_p = 0
        for _, n in ipairs(track_notes) do
            local p = n.pitch or n.nominal_pitch
            if p then
                sum_p = sum_p + p
                count = count + 1
                if p < min_p then min_p = p end
                if p > max_p then max_p = p end
            end
        end
        if count > 0 then
            -- Wide keyboard range spanning across both staves (e.g. piano pieces without explicit name)
            if min_p <= 53 and max_p >= 67 and (max_p - min_p >= 20) then
                return "grand"
            end
            local avg_p = sum_p / count
            if avg_p < 55 then
                return "bass"
            else
                return "treble"
            end
        end
    end
    return "treble"
end

function Engraver.get_note_preferred_accidental(vn, state)
    if not (vn and state and state.note_accidentals) then return nil end
    local orig = vn.orig
    if not orig then return nil end
    local k = orig.key or (orig.get_key and orig:get_key())
    local pref = state.note_accidentals[k]
    if pref ~= nil then return pref end
    if orig.take then
        local id_k = string.format("%s_%s_%.3f", tostring(orig.take or "0"), tostring(orig.idx or 0), orig.start_qn or 0)
        pref = state.note_accidentals[id_k]
        if pref ~= nil then return pref end
        local pos_k = string.format("%s_%.3f_%d", tostring(orig.take or "0"), orig.start_qn or 0, orig.pitch or 0)
        return state.note_accidentals[pos_k]
    end
    return nil
end

function Engraver.get_note_stem_direction(vn, state)
    if not vn then return nil end
    if vn.stem_dir and (vn.stem_dir == "up" or vn.stem_dir == "down") then
        return vn.stem_dir
    end
    local orig = vn.orig
    if orig and orig.stem_dir and (orig.stem_dir == "up" or orig.stem_dir == "down") then
        return orig.stem_dir
    end
    if not (state and state.note_stem_directions) then return nil end
    local k = (orig and (orig.key or (orig.get_key and orig:get_key()))) or vn.key
    local pref = state.note_stem_directions[k]
    if pref ~= nil then return pref end
    if orig and orig.take then
        local id_k = string.format("%s_%s_%.3f", tostring(orig.take or "0"), tostring(orig.idx or 0), orig.start_qn or 0)
        pref = state.note_stem_directions[id_k]
        if pref ~= nil then return pref end
        local pos_k = string.format("%s_%.3f_%d", tostring(orig.take or "0"), orig.start_qn or 0, orig.pitch or 0)
        return state.note_stem_directions[pos_k]
    end
    return nil
end

function Engraver.get_note_staff(vn, state)
    if not vn then return nil end
    if vn.staff and (vn.staff == "treble" or vn.staff == "bass") then
        return vn.staff
    end
    local orig = vn.orig or (vn.take and vn)
    if orig and orig.staff and (orig.staff == "treble" or orig.staff == "bass") then
        return orig.staff
    end
    if not (state and state.note_staff_assignments) then return nil end
    local k = (orig and (orig.key or (orig.get_key and orig:get_key()))) or vn.key
    local pref = state.note_staff_assignments[k]
    if pref ~= nil then return pref end
    if orig and orig.take then
        local id_k = string.format("%s_%s_%.3f", tostring(orig.take or "0"), tostring(orig.idx or 0), orig.start_qn or 0)
        pref = state.note_staff_assignments[id_k]
        if pref ~= nil then return pref end
        local pos_k = string.format("%s_%.3f_%d", tostring(orig.take or "0"), orig.start_qn or 0, orig.pitch or 0)
        return state.note_staff_assignments[pos_k]
    end
    return nil
end

function Engraver.get_note_effective_pitch(raw_pitch, start_qn, track_guid, state)
    local pitch = raw_pitch or 60
    if not (state and track_guid and track_guid ~= "") then
        return pitch, nil, 0
    end
    local active_oct = (OctaveService and OctaveService.get_active_line_at_qn) and OctaveService.get_active_line_at_qn(state, track_guid, start_qn or 0) or nil
    local oct_shift = active_oct and (Constants.OCTAVE_LINE_DEFS[active_oct.type] and Constants.OCTAVE_LINE_DEFS[active_oct.type].shift_semitones or 0) or 0
    local eff_pitch = math.max(0, math.min(127, pitch - oct_shift))
    return eff_pitch, active_oct, oct_shift
end

function Engraver.pitch_to_canvas_y(pitch, treble_bottom_y, bass_bottom_y, step_y, is_grand, track_clef, preferred_acc, mid_bottom_y, key_sig_idx, force_staff)
    if type(key_sig_idx) == "table" then
        key_sig_idx = key_sig_idx.key_idx or key_sig_idx.idx or 0
    end
    local p_mod = pitch % 12
    local p_info = Constants.PITCH_MAP[p_mod]
    local oct_shift = 0
    local eff_pref_acc = preferred_acc
    if eff_pref_acc == nil and key_sig_idx and key_sig_idx ~= 0 then
        if key_sig_idx > 0 and ENHARMONIC_SPELLINGS[p_mod] and ENHARMONIC_SPELLINGS[p_mod][1] then
            eff_pref_acc = 1
        elseif key_sig_idx < 0 and ENHARMONIC_SPELLINGS[p_mod] and ENHARMONIC_SPELLINGS[p_mod][-1] then
            eff_pref_acc = -1
        end
    end
    if eff_pref_acc and ENHARMONIC_SPELLINGS[p_mod] and ENHARMONIC_SPELLINGS[p_mod][eff_pref_acc] then
        p_info = ENHARMONIC_SPELLINGS[p_mod][eff_pref_acc]
        oct_shift = p_info.oct_shift or 0
    end
    local octave = (math.floor(pitch / 12) - 1) + oct_shift
    local total_diatonic_step = (octave * 7) + p_info.step
    local c4_step = (4 * 7) + 0 -- C4 = diatonic step 28
    local diatonic_from_c4 = total_diatonic_step - c4_step
    
    local cdef = Constants.CLEF_DEFS and Constants.CLEF_DEFS[track_clef]
    local is_harp = (track_clef == "harp_3staff") or (cdef and cdef.is_multi_staff == "harp_3staff")
    local is_dual = is_grand or (cdef and cdef.is_multi_staff == "grand")
    
    local ny
    local staff_target = "treble" -- "treble" | "mid" | "bass"
    local in_treble = true
    local offset = 0
    
    if is_harp then
        -- 3-staff harp / organ
        local mb_y = mid_bottom_y or (treble_bottom_y + 70 * (step_y / 4.0))
        if pitch >= 65 then
            staff_target = "treble"
            in_treble = true
            offset = diatonic_from_c4 - 2 -- Treble bottom = E4 (2)
            ny = treble_bottom_y - (offset * step_y)
        elseif pitch >= 53 then
            staff_target = "mid"
            in_treble = false
            offset = diatonic_from_c4 - (-4) -- Alto bottom = F3 (-4)
            ny = mb_y - (offset * step_y)
        else
            staff_target = "bass"
            in_treble = false
            offset = diatonic_from_c4 - (-10) -- Bass bottom = G2 (-10)
            ny = bass_bottom_y - (offset * step_y)
        end
    elseif is_dual then
        if force_staff == "bass" then
            in_treble = false
        elseif force_staff == "treble" then
            in_treble = true
        else
            in_treble = (pitch >= 60)
        end
        staff_target = in_treble and "treble" or "bass"
        if in_treble then
            offset = diatonic_from_c4 - 2
            ny = treble_bottom_y - (offset * step_y)
        else
            offset = diatonic_from_c4 - (-10)
            ny = bass_bottom_y - (offset * step_y)
        end
    else
        -- Arbitrary single clef (treble, bass, alto, tenor, percussion, etc.)
        local target_bottom_y = (track_clef == "bass" and bass_bottom_y) or ((track_clef == "alto" and mid_bottom_y) and mid_bottom_y or treble_bottom_y)
        in_treble = (track_clef ~= "bass")
        staff_target = (track_clef == "bass") and "bass" or ((track_clef == "alto") and "alto" or "treble")
        if cdef and cdef.unpitched and Constants.GM_DRUM_STEP_MAP and Constants.GM_DRUM_STEP_MAP[pitch] then
            offset = Constants.GM_DRUM_STEP_MAP[pitch]
            ny = target_bottom_y - (offset * step_y)
            return ny, in_treble, offset, 0, staff_target
        end
        local b_diatonic = (cdef and cdef.bottom_line_diatonic) or (track_clef == "bass" and -10 or 2)
        offset = diatonic_from_c4 - b_diatonic
        ny = target_bottom_y - (offset * step_y)
    end
    
    local final_acc = (cdef and cdef.unpitched) and 0 or (p_info and p_info.acc or 0)
    if not (cdef and cdef.unpitched) and key_sig_idx and key_sig_idx ~= 0 then
        local KEY_SHARPS_ORDER = { 6, 1, 8, 3, 10, 5, 0 } -- F#, C#, G#, D#, A#, E#, B#
        local KEY_SHARPS_NATS  = { 5, 0, 7, 2, 9,  4, 11 } -- F,  C,  G,  D,  A,  E,  B
        local KEY_FLATS_ORDER  = { 10, 3, 8, 1, 6, 11, 4 } -- Bb, Eb, Ab, Db, Gb, Cb, Fb
        local KEY_FLATS_NATS   = { 11, 4, 9, 2, 7, 0,  5 } -- B,  E,  A,  D,  G,  C,  F

        if key_sig_idx > 0 then
            local count = math.min(7, key_sig_idx)
            for i = 1, count do
                if p_mod == KEY_SHARPS_ORDER[i] then
                    final_acc = 0 -- Accidental dictated by key signature (suppress)
                    break
                elseif p_mod == KEY_SHARPS_NATS[i] then
                    final_acc = 2 -- Non-diatonic cancellation (natural sign ♮)
                    break
                end
            end
        elseif key_sig_idx < 0 then
            local count = math.min(7, math.abs(key_sig_idx))
            for i = 1, count do
                if p_mod == KEY_FLATS_ORDER[i] then
                    final_acc = 0 -- Accidental dictated by key signature (suppress)
                    break
                elseif p_mod == KEY_FLATS_NATS[i] then
                    final_acc = 2 -- Non-diatonic cancellation (natural sign ♮)
                    break
                end
            end
        end
    end

    return ny, in_treble, offset, final_acc, staff_target
end

local DIATONIC_STEP_TO_SEMITONE = { [0] = 0, [1] = 2, [2] = 4, [3] = 5, [4] = 7, [5] = 9, [6] = 11 }

local GM_STEP_TO_DRUM_PITCH = {
    [-2] = 44, -- Pedal Hi-Hat
    [-1] = 35, -- Acoustic Bass Drum
    [0]  = 41, -- Low Floor Tom
    [1]  = 36, -- Bass Drum 1
    [2]  = 45, -- Low Tom
    [3]  = 47, -- Low-Mid Tom
    [4]  = 38, -- Snare Drum
    [5]  = 48, -- Hi-Mid Tom
    [6]  = 50, -- High Tom
    [7]  = 54, -- Tambourine
    [8]  = 51, -- Ride Cymbal
    [9]  = 42, -- Closed Hi-Hat
    [10] = 49, -- Crash Cymbal
}

function Engraver.canvas_y_to_pitch(y, treble_bottom_y, bass_bottom_y, step_y, is_grand, track_clef, accidental, mid_bottom_y)
    local acc = accidental or 0
    local cdef = Constants.CLEF_DEFS and Constants.CLEF_DEFS[track_clef]
    local is_harp = (track_clef == "harp_3staff") or (cdef and cdef.is_multi_staff == "harp_3staff")
    local is_dual = is_grand or (cdef and cdef.is_multi_staff == "grand")
    
    local diatonic_from_c4
    local in_treble = true
    
    if is_harp then
        local mb_y = mid_bottom_y or (treble_bottom_y + 70 * (step_y / 4.0))
        local split_1 = (treble_bottom_y + mb_y) / 2
        local split_2 = (mb_y + bass_bottom_y) / 2
        if y < split_1 then
            in_treble = true
            local offset = math.floor(((treble_bottom_y - y) / step_y) + 0.5)
            diatonic_from_c4 = offset + 2
        elseif y < split_2 then
            in_treble = false
            local offset = math.floor(((mb_y - y) / step_y) + 0.5)
            diatonic_from_c4 = offset - 4
        else
            in_treble = false
            local offset = math.floor(((bass_bottom_y - y) / step_y) + 0.5)
            diatonic_from_c4 = offset - 10
        end
    elseif is_dual then
        local split_y = (treble_bottom_y + (bass_bottom_y - 4 * (step_y * 2))) / 2
        in_treble = (y <= split_y)
        if in_treble then
            local e4_offset = math.floor(((treble_bottom_y - y) / step_y) + 0.5)
            diatonic_from_c4 = e4_offset + 2
        else
            local g2_offset = math.floor(((bass_bottom_y - y) / step_y) + 0.5)
            diatonic_from_c4 = g2_offset - 10
        end
    else
        local target_bottom_y = (track_clef == "bass" and bass_bottom_y) or treble_bottom_y
        in_treble = (track_clef ~= "bass")
        local offset = math.floor(((target_bottom_y - y) / step_y) + 0.5)
        if cdef and cdef.unpitched then
            local dp = GM_STEP_TO_DRUM_PITCH[offset]
            if dp then return dp, in_treble end
        end
        local b_diatonic = (cdef and cdef.bottom_line_diatonic) or (track_clef == "bass" and -10 or 2)
        diatonic_from_c4 = offset + b_diatonic
    end
    
    local total_diatonic_step = diatonic_from_c4 + 28
    local octave = math.floor(total_diatonic_step / 7)
    local step_in_oct = total_diatonic_step % 7
    local semitone = DIATONIC_STEP_TO_SEMITONE[step_in_oct] or 0
    local pitch = ((octave + 1) * 12) + semitone + acc
    return math.max(0, math.min(127, pitch)), in_treble
end

function Engraver.decompose_rest_gap(rests, start_qn, dur_qn, m, qn_per_measure)
    if not dur_qn or dur_qn < 0.05 then return end
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0
    local rem = dur_qn
    local cur = start_qn
    
    -- 1. Fill off-beat fractions up to the next quarter-beat boundary (e.g. 0.5 -> 1.0)
    local beat_offset = cur % 1.0
    if beat_offset > 0.04 and rem >= 0.05 then
        local needed_to_beat = 1.0 - beat_offset
        local sub_rests = {
            { val = 0.5,    type = "8th" },
            { val = 0.25,   type = "16th" },
            { val = 0.125,  type = "32nd" },
            { val = 0.0625, type = "64th" }
        }
        for _, rdef in ipairs(sub_rests) do
            if rem >= rdef.val - 0.01 and math.abs((needed_to_beat % rdef.val)) < 0.02 then
                table.insert(rests, {
                    type = rdef.type,
                    start_qn = cur,
                    dur_qn = rdef.val,
                    measure_idx = m,
                    is_full_measure = false
                })
                cur = cur + rdef.val
                rem = rem - rdef.val
                break
            end
        end
    end
    
    -- 2. Main rest decomposition observing metric beat hierarchy (half rests only on beats 1 & 3 in 4/4)
    while rem >= 0.05 do
        local matched = false
        local cur_in_bar = cur % bpi
        local is_half_bar_aligned = (math.abs(cur_in_bar % 2.0) < 0.02)
        
        if rem >= 2.0 - 0.01 and is_half_bar_aligned then
            table.insert(rests, {
                type = "half",
                start_qn = cur,
                dur_qn = 2.0,
                measure_idx = m,
                is_full_measure = false
            })
            cur = cur + 2.0
            rem = rem - 2.0
            matched = true
        elseif rem >= 1.0 - 0.01 then
            table.insert(rests, {
                type = "quarter",
                start_qn = cur,
                dur_qn = 1.0,
                measure_idx = m,
                is_full_measure = false
            })
            cur = cur + 1.0
            rem = rem - 1.0
            matched = true
        elseif rem >= 0.5 - 0.01 then
            table.insert(rests, {
                type = "8th",
                start_qn = cur,
                dur_qn = 0.5,
                measure_idx = m,
                is_full_measure = false
            })
            cur = cur + 0.5
            rem = rem - 0.5
            matched = true
        elseif rem >= 0.25 - 0.01 then
            table.insert(rests, {
                type = "16th",
                start_qn = cur,
                dur_qn = 0.25,
                measure_idx = m,
                is_full_measure = false
            })
            cur = cur + 0.25
            rem = rem - 0.25
            matched = true
        elseif rem >= 0.125 - 0.01 then
            table.insert(rests, {
                type = "32nd",
                start_qn = cur,
                dur_qn = 0.125,
                measure_idx = m,
                is_full_measure = false
            })
            cur = cur + 0.125
            rem = rem - 0.125
            matched = true
        elseif rem >= 0.0625 - 0.005 then
            table.insert(rests, {
                type = "64th",
                start_qn = cur,
                dur_qn = 0.0625,
                measure_idx = m,
                is_full_measure = false
            })
            cur = cur + 0.0625
            rem = rem - 0.0625
            matched = true
        end
        if not matched then break end
    end
end

function Engraver.generate_track_rests(track_notes, total_measures, qn_per_measure, dq, min_m, max_m)
    local rests = {}
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0
    local start_m = math.max(0, min_m or 0)
    local stop_m = math.min(total_measures - 1, max_m or (total_measures - 1))
    if start_m > stop_m then return rests end

    local notes_by_bar = {}
    for m = start_m, stop_m do notes_by_bar[m] = {} end
    
    for _, n in ipairs(track_notes) do
        local n_start = dq and (math.floor((n.start_qn / dq) + 0.5) * dq) or n.start_qn
        local n_dur = dq and (math.max(dq, math.floor(((n.dur_qn or (n.end_qn - n.start_qn)) / dq) + 0.5) * dq)) or (n.dur_qn or (n.end_qn - n.start_qn))
        local n_end = n_start + n_dur
        local start_bar = math.floor((n_start + 0.001) / bpi)
        local end_bar = math.floor(math.max(n_start, n_end - 0.001) / bpi)
        local from_b = math.max(start_m, start_bar)
        local to_b = math.min(stop_m, end_bar)
        for m = from_b, to_b do
            if notes_by_bar[m] then table.insert(notes_by_bar[m], n) end
        end
    end
    
    for m = start_m, stop_m do
        local bar_notes = notes_by_bar[m]
        local bar_start_qn = m * bpi
        local bar_end_qn = (m + 1) * bpi
        
        if #bar_notes == 0 then
            table.insert(rests, {
                type = "whole",
                start_qn = bar_start_qn,
                dur_qn = bpi,
                measure_idx = m,
                is_full_measure = true
            })
        else
            -- Sort notes in measure chronologically
            table.sort(bar_notes, function(a, b) return a.start_qn < b.start_qn end)
            
            -- Group by unique rhythmic onset slots (combine chords)
            local distinct_onsets = {}
            for _, n in ipairs(bar_notes) do
                local snap_grid = dq or 0.125
                local rel_s = n.start_qn - bar_start_qn
                local snapped_s = bar_start_qn + (math.floor((rel_s / snap_grid) + 0.5) * snap_grid)
                local raw_dur = n.dur_qn or (n.end_qn - n.start_qn)
                local nom_dur = dq and (math.max(dq, math.floor((raw_dur / dq) + 0.5) * dq)) or Engraver.get_nominal_rhythmic_duration(raw_dur)
                
                local found = false
                local tol = dq and (dq * 0.7) or 0.10
                for _, slot in ipairs(distinct_onsets) do
                    if math.abs(slot.s - snapped_s) < tol then
                        slot.dur = math.max(slot.dur, nom_dur)
                        slot.actual_end = math.max(slot.actual_end, n.end_qn)
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(distinct_onsets, {
                        s = snapped_s,
                        dur = nom_dur,
                        actual_end = n.end_qn
                    })
                end
            end
            table.sort(distinct_onsets, function(a, b) return a.s < b.s end)
            
            -- If display quantize is active: close small gaps between consecutive onsets
            if dq then
                for idx = 1, #distinct_onsets do
                    local slot = distinct_onsets[idx]
                    if idx < #distinct_onsets then
                        local next_s = distinct_onsets[idx + 1].s
                        if next_s > slot.s and next_s <= slot.s + (dq * 1.5) then
                            slot.dur = math.max(slot.dur, next_s - slot.s)
                        end
                    else
                        if slot.s + slot.dur >= bar_end_qn - (dq * 0.75) then
                            slot.dur = bar_end_qn - slot.s
                        end
                    end
                end
            end
            
            -- Calculate sum of nominal note values in measure
            local total_nom_dur = 0
            for _, slot in ipairs(distinct_onsets) do
                total_nom_dur = total_nom_dur + slot.dur
            end
            
            -- IMPORTANT: If notes rhythmically fill the measure completely,
            -- NO rests must be generated!
            local fill_tol = dq and (dq * 0.5) or 0.20
            if total_nom_dur < bpi - fill_tol then
                local intervals = {}
                for idx, slot in ipairs(distinct_onsets) do
                    local s_qn = math.max(bar_start_qn, slot.s)
                    local nom_e = s_qn + slot.dur
                    
                    if idx < #distinct_onsets then
                        local next_s = distinct_onsets[idx + 1].s
                        if next_s > s_qn + 0.05 then
                            nom_e = math.min(nom_e, next_s)
                        end
                    else
                        -- Last note in measure: if it reaches close to the barline, fill to end of measure
                        if nom_e >= bar_end_qn - fill_tol or slot.actual_end >= bar_end_qn - fill_tol then
                            nom_e = bar_end_qn
                        end
                    end
                    
                    if slot.actual_end >= bar_end_qn - 0.05 then
                        nom_e = bar_end_qn
                    end
                    
                    local e_qn = math.min(bar_end_qn, math.max(nom_e, slot.actual_end))
                    if e_qn > s_qn + 0.05 then
                        table.insert(intervals, { s = s_qn, e = e_qn })
                    end
                end
                
                local merged = {}
                for _, inv in ipairs(intervals) do
                    if #merged == 0 or inv.s > merged[#merged].e + 0.08 then
                        table.insert(merged, { s = inv.s, e = inv.e })
                    else
                        merged[#merged].e = math.max(merged[#merged].e, inv.e)
                    end
                end
                
                local covered = 0
                for _, inv in ipairs(merged) do
                    covered = covered + (inv.e - inv.s)
                end
                
                if covered < bpi - fill_tol then
                    local cur_pos = bar_start_qn
                    for _, inv in ipairs(merged) do
                        if inv.s > cur_pos + fill_tol then
                            local gap_dur = inv.s - cur_pos
                            Engraver.decompose_rest_gap(rests, cur_pos, gap_dur, m, bpi)
                        end
                        cur_pos = math.max(cur_pos, inv.e)
                    end
                    if bar_end_qn > cur_pos + fill_tol then
                        Engraver.decompose_rest_gap(rests, cur_pos, bar_end_qn - cur_pos, m, bpi)
                    end
                end
            end
        end
    end
    return rests
end


function Engraver.generate_voice_rests(track_notes, total_measures, qn_per_measure, dq, min_m, max_m)
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0
    
    -- Check if track has multiple voices
    local voices_present = {}
    for _, n in ipairs(track_notes or {}) do
        local v = (n.chan or 0) + 1
        voices_present[v] = true
    end
    
    local voice_count = 0
    for _ in pairs(voices_present) do voice_count = voice_count + 1 end
    
    -- Monophonic track: standard rest generation
    if voice_count <= 1 then
        return Engraver.generate_track_rests(track_notes, total_measures, qn_per_measure, dq, min_m, max_m)
    end
    
    -- Polyphonic track (Elaine Gould / Gardner Read):
    -- Each voice has its own metric rest stream.
    local all_rests = {}
    local start_m = math.max(0, min_m or 0)
    local stop_m = math.min(total_measures - 1, max_m or (total_measures - 1))
    
    -- Determine measure occupancy across all voices
    local bar_has_notes = {}
    for m = start_m, stop_m do bar_has_notes[m] = false end
    for _, n in ipairs(track_notes or {}) do
        local m = math.floor((n.start_qn + 0.001) / bpi)
        if bar_has_notes[m] ~= nil then
            bar_has_notes[m] = true
        end
    end
    
    for v = 1, 4 do
        if voices_present[v] then
            local v_notes = {}
            for _, n in ipairs(track_notes) do
                if ((n.chan or 0) + 1) == v then
                    table.insert(v_notes, n)
                end
            end
            
            local v_rests = Engraver.generate_track_rests(v_notes, total_measures, qn_per_measure, dq, min_m, max_m)
            for _, r in ipairs(v_rests) do
                r.voice = v
                local m = r.measure_idx or math.floor(r.start_qn / bpi)
                -- If measure is completely empty (no notes in any voice):
                -- Only voice 1 emits the centered whole measure rest (Gould standard).
                if r.is_full_measure and not bar_has_notes[m] then
                    if v == 1 then
                        r.voice = nil -- Standard centered
                        table.insert(all_rests, r)
                    end
                else
                    table.insert(all_rests, r)
                end
            end
        end
    end
    
    return all_rests
end


-- ==============================================================================
-- RHYTHMIC DECOMPOSITION ACCORDING TO ELAINE GOULD ("BEHIND BARS") & GARDNER READ
-- Decomposes note values across beats, half-bar boundaries, and metric pulses
-- ==============================================================================

function Engraver.decompose_bar_segment(start_in_bar, raw_dur, bpi, depth, allow_half_bar_split)
    local segments = {}
    local bpi = (bpi and bpi > 0) and bpi or 4.0
    depth = depth or 0
    if allow_half_bar_split == nil then allow_half_bar_split = true end
    
    -- Recursion guard to prevent stack overflow
    if depth > 5 then
        table.insert(segments, { start_in_bar = start_in_bar, dur_qn = raw_dur })
        return segments
    end
    
    -- 0. Tuplet protection (triplets, quintuplets, septuplets according to Gould / Gardner Read):
    -- Tuplet durations (e.g. quarter quintuplet 0.80, eighth quintuplet 0.40, quarter triplet 0.667 etc.)
    -- are coherent rhythmic units and must NEVER be split at half-bar boundaries or
    -- decomposed into binary fractions (0.75 + 0.05 etc.)!
    local tuplet_dur_targets = {
        1.3333, 0.8000, 0.6667, 0.5714, 0.4000, 0.3333, 0.2857, 0.2000, 0.1667, 0.1429, 0.1000, 0.0833, 0.0714
    }
    for _, td in ipairs(tuplet_dur_targets) do
        if math.abs(raw_dur - td) <= 0.035 then
            table.insert(segments, { start_in_bar = start_in_bar, dur_qn = td })
            return segments
        end
    end
    
    -- 1. Metric tolerance check and rounding to standard musical durations (down to 1/64 = 0.0625 QN)
    local dur = raw_dur
    local std_vals = { 4.0, 3.5, 3.0, 2.5, 2.0, 1.75, 1.5, 1.25, 1.0, 0.75, 0.5, 0.375, 0.25, 0.1875, 0.125, 0.0625 }
    for _, sv in ipairs(std_vals) do
        local tol = math.min(0.08, sv * 0.25)
        if math.abs(dur - sv) <= tol then
            dur = sv
            break
        end
    end
    
    -- Must not exceed current measure
    if start_in_bar + dur > bpi + 0.02 then
        dur = math.max(0.0625, bpi - start_in_bar)
    end
    
    -- If this segment was already split at the half-bar, dur must not cross boundary again
    local half_bar = bpi / 2.0
    if not allow_half_bar_split then
        if start_in_bar < half_bar and start_in_bar + dur > half_bar then
            dur = math.max(0.0625, half_bar - start_in_bar)
        elseif start_in_bar >= half_bar and start_in_bar + dur > bpi then
            dur = math.max(0.0625, bpi - start_in_bar)
        end
    end
    
    -- 2. Full-measure whole note (in 4/4 time: start on beat 1, duration >= bpi - 0.35)
    if start_in_bar < 0.20 and dur >= (bpi - 0.35) then
        table.insert(segments, { start_in_bar = 0.0, dur_qn = bpi })
        return segments
    end
    
    -- 3. Notes starting on beat 1 (0.0):
    if start_in_bar < 0.05 then
        if math.abs(dur - 3.5) <= 0.08 then
            -- 3.5 quarters: Dotted half (3.0) tied to eighth (0.5)
            table.insert(segments, { start_in_bar = 0.0, dur_qn = 3.0 })
            table.insert(segments, { start_in_bar = 3.0, dur_qn = 0.5 })
            return segments
        elseif math.abs(dur - 3.0) <= 0.08 then
            -- 3.0 quarters: Dotted half
            table.insert(segments, { start_in_bar = 0.0, dur_qn = 3.0 })
            return segments
        elseif math.abs(dur - 2.5) <= 0.08 then
            -- 2.5 quarters: Half note (2.0) tied to eighth (0.5)
            table.insert(segments, { start_in_bar = 0.0, dur_qn = 2.0 })
            table.insert(segments, { start_in_bar = 2.0, dur_qn = 0.5 })
            return segments
        elseif math.abs(dur - 2.0) <= 0.08 then
            -- 2.0 quarters: Half note
            table.insert(segments, { start_in_bar = 0.0, dur_qn = 2.0 })
            return segments
        end
    end
    
    -- 4. Half-bar rule (in 4/4 time at beat 2.0)
    local end_in_bar = start_in_bar + dur
    if allow_half_bar_split and bpi == 4.0 and start_in_bar < half_bar - 0.05 and end_in_bar > half_bar + 0.05 then
        local dur1 = half_bar - start_in_bar
        local dur2 = end_in_bar - half_bar
        local segs1 = Engraver.decompose_bar_segment(start_in_bar, dur1, bpi, depth + 1, false)
        local segs2 = Engraver.decompose_bar_segment(half_bar, dur2, bpi, depth + 1, false)
        for _, s in ipairs(segs1) do table.insert(segments, s) end
        for _, s in ipairs(segs2) do table.insert(segments, s) end
        return segments
    end
    
    -- 5. Standard individual note symbols:
    local single_standards = { 3.0, 2.0, 1.5, 1.0, 0.75, 0.5, 0.375, 0.25, 0.1875, 0.125, 0.0625 }
    for _, sv in ipairs(single_standards) do
        if math.abs(dur - sv) <= 0.04 then
            table.insert(segments, { start_in_bar = start_in_bar, dur_qn = sv })
            return segments
        end
    end
    
    -- 6. Greedy decomposition of remaining irregular durations:
    local cur_s = start_in_bar
    local rem_d = dur
    local max_steps = 16
    while rem_d > 0.03 and max_steps > 0 do
        max_steps = max_steps - 1
        local piece = nil
        for _, sv in ipairs(single_standards) do
            if sv <= rem_d + 0.02 then
                piece = sv
                break
            end
        end
        if not piece or piece < 0.0625 then piece = math.max(0.0625, rem_d) end
        table.insert(segments, { start_in_bar = cur_s, dur_qn = piece })
        cur_s = cur_s + piece
        rem_d = rem_d - piece
    end
    
    return segments
end

function Engraver.get_visual_notes(notes, qn_per_measure, vis_min_qn, vis_max_qn)
    local visual_notes = {}
    local bar_ties = {}
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0
    if not notes then return visual_notes, bar_ties end
    
    for _, n in ipairs(notes) do
        local n_sqn = n.start_qn or n.sqn or 0
        if vis_max_qn and n_sqn > vis_max_qn + 1.0 then
            break
        end
        local n_eqn = n.end_qn or n.eqn or (n_sqn + (n.dur_qn or 1.0))
        
        if not vis_min_qn or n_eqn >= vis_min_qn - 2.0 then
            -- Metric smoothing of unquantized REAPER MIDI notes (1/64 grid = 0.0625 QN)
            local grid = 0.0625
            local raw_dur = math.max(grid, n_eqn - n_sqn)
            
            -- Check first for common tuplet durations (triplets 3:2, quintuplets 5:4, septuplets 7:4),
            -- so they are not erroneously snapped or distorted to binary note values:
            local tuplet_dur_targets = {
                1.3333, 0.8000, 0.6667, 0.5714, 0.4000, 0.3333, 0.2857, 0.2000, 0.1667, 0.1429, 0.1000, 0.0833, 0.0714
            }
            local matched_tuplet_dur = nil
            for _, td in ipairs(tuplet_dur_targets) do
                if math.abs(raw_dur - td) <= 0.025 then
                    matched_tuplet_dur = td
                    break
                end
            end

            local clean_sqn
            local snapped_dur
            if matched_tuplet_dur then
                snapped_dur = matched_tuplet_dur
                -- For tuplets, also align start time to tuplet step grid (instead of 1/64 binary)
                local t_step = matched_tuplet_dur
                local step_idx = math.floor((n_sqn / t_step) + 0.5)
                if math.abs(n_sqn - step_idx * t_step) <= 0.04 then
                    clean_sqn = step_idx * t_step
                else
                    clean_sqn = math.floor((n_sqn / grid) + 0.5) * grid
                end
            else
                clean_sqn = math.floor((n_sqn / grid) + 0.5) * grid
                -- Legato snap: When raw duration is very close to full quarters/eighths (e.g. 0.88 -> 1.0, 1.88 -> 2.0, 2.88 -> 3.0, 3.85 -> 4.0)
                snapped_dur = math.floor((raw_dur / grid) + 0.5) * grid
                if snapped_dur < grid then snapped_dur = grid end
                local close_targets = { 4.0, 3.5, 3.0, 2.5, 2.0, 1.75, 1.5, 1.25, 1.0, 0.75, 0.5, 0.375, 0.25, 0.1875, 0.125, 0.0625 }
                for _, ct in ipairs(close_targets) do
                    local tol = math.min(0.14, math.max(0.025, ct * 0.25))
                    if math.abs(raw_dur - ct) <= tol then
                        snapped_dur = ct
                        break
                    end
                end
            end
            local clean_eqn = clean_sqn + snapped_dur
            
            if (not vis_min_qn or clean_eqn >= vis_min_qn) and (not vis_max_qn or clean_sqn <= vis_max_qn) then
                local start_bar = math.floor((clean_sqn + 0.001) / bpi)
                local end_bar = math.floor(math.max(clean_sqn, clean_eqn - 0.001) / bpi)
                
                local prev_seg_key = nil
                local prev_seg_bar = nil
                for bar = start_bar, end_bar do
                    local bar_sqn = bar * bpi
                    local seg_sqn = math.max(clean_sqn, bar_sqn)
                    local seg_eqn = math.min(clean_eqn, (bar + 1) * bpi)
                    local seg_dur = seg_eqn - seg_sqn
                    
                    if seg_dur > 0.01 then
                        local start_in_bar = seg_sqn - bar_sqn
                        local sub_segs = Engraver.decompose_bar_segment(start_in_bar, seg_dur, bpi)
                        
                        local it_str = tostring(n.item or "0")
                        local tk_str = tostring(n.take or "0")
                        
                        for sub_i, sub in ipairs(sub_segs) do
                            local sub_sqn = bar_sqn + sub.start_in_bar
                            local sub_eqn = sub_sqn + sub.dur_qn
                            local seg_key = string.format("%s_%s_%.3f_%d_%d_b%d_s%d", it_str, tk_str, sub_sqn, n.pitch, n.chan or 0, bar, sub_i)
                            
                            local is_segmented = (start_bar ~= end_bar) or (#sub_segs > 1)
                            local seg = {
                                orig = n,
                                pitch = n.pitch,
                                start_qn = sub_sqn,
                                end_qn = sub_eqn,
                                dur_qn = sub.dur_qn,
                                is_segment = is_segmented,
                                seg_idx = sub_i,
                                key = seg_key,
                                bar = bar,
                                item = n.item,
                                item_obj = n.item_obj,
                                take = n.take,
                                track = n.track
                            }
                            table.insert(visual_notes, seg)
                            
                            if prev_seg_key then
                                local is_cross = (prev_seg_bar ~= nil and prev_seg_bar ~= bar)
                                table.insert(bar_ties, {
                                    from_key = prev_seg_key,
                                    to_key = seg_key,
                                    pitch = n.pitch,
                                    orig = n,
                                    is_cross_barline = is_cross,
                                    from_bar = prev_seg_bar,
                                    to_bar = bar
                                })
                            end
                            prev_seg_key = seg_key
                            prev_seg_bar = bar
                        end
                    end
                end
            end
        end
    end
    return visual_notes, bar_ties
end

-- ==============================================================================
-- STANDARD-COMPLIANT BEAMING ENGINE
-- ==============================================================================

function Engraver.get_beam_groups(visual_notes, qn_per_measure, grouping)
    local groups = {}
    if grouping == "none" then return groups end
    
    local group_size = 1.0
    if grouping == "bar" then
        group_size = qn_per_measure
    elseif grouping == "half_bar" then
        group_size = qn_per_measure / 2.0
    else
        group_size = 1.0 -- Standard: per beat (quarter note in 4/4)
    end
    
    local function has_multiple_onsets(notes_grp)
        if not notes_grp or #notes_grp < 2 then return false end
        local first_qn = notes_grp[1].start_qn
        for i = 2, #notes_grp do
            if math.abs(notes_grp[i].start_qn - first_qn) > 0.02 then
                return true
            end
        end
        return false
    end

    local function group_staff_notes(notes_list)
        local beamable = {}
        for _, vn in ipairs(notes_list) do
            if Engraver.get_flag_count(vn.dur_qn) > 0 then
                table.insert(beamable, vn)
            end
        end
        table.sort(beamable, function(a, b)
            if math.abs(a.start_qn - b.start_qn) > 0.02 then return a.start_qn < b.start_qn end
            return a.pitch < b.pitch
        end)
        
        -- Detection of tuplet sequences (e.g. eighth-note quintuplets across 2 beats or triplets),
        -- so they remain continuous as a cohesive beam group and are not severed at beats:
        local tuplet_assigned = {}
        local num_b = #beamable
        local b_idx = 1
        local tup_counter = 0
        while b_idx <= num_b do
            local found_tup = false
            for _, tn in ipairs({ 8, 7, 6, 5, 3 }) do
                if b_idx + tn - 1 <= num_b then
                    local first_b = beamable[b_idx]
                    local last_b = beamable[b_idx + tn - 1]
                    local m_first = math.floor((first_b.start_qn + 0.001) / qn_per_measure)
                    local m_last  = math.floor((last_b.start_qn + 0.001) / qn_per_measure)
                    if m_first == m_last then
                        local span = last_b.start_qn - first_b.start_qn
                        local step = span / (tn - 1)
                        local is_uniform = true
                        for k = 1, tn - 1 do
                            local diff = beamable[b_idx + k].start_qn - beamable[b_idx + k - 1].start_qn
                            if math.abs(diff - step) > 0.05 then is_uniform = false break end
                        end
                        if is_uniform and step > 0.06 and step < 0.65 then
                            tup_counter = tup_counter + 1
                            local g_tag = "tup_" .. tostring(tup_counter)
                            for k = 0, tn - 1 do
                                tuplet_assigned[beamable[b_idx + k]] = g_tag
                            end
                            b_idx = b_idx + tn
                            found_tup = true
                            break
                        end
                    end
                end
            end
            if not found_tup then
                b_idx = b_idx + 1
            end
        end

        local cur_group = {}
        local cur_group_start = nil
        for _, vn in ipairs(beamable) do
            local g_idx = tuplet_assigned[vn] or math.floor(vn.start_qn / group_size)
            if cur_group_start == nil or g_idx ~= cur_group_start then
                if has_multiple_onsets(cur_group) then
                    table.insert(groups, cur_group)
                end
                cur_group = { vn }
                cur_group_start = g_idx
            else
                table.insert(cur_group, vn)
            end
        end
        if has_multiple_onsets(cur_group) then
            table.insert(groups, cur_group)
        end
    end
    
    -- Partition strictly by staff AND voice (treble vs. mid/alto vs. bass, voice 1 vs voice 2)
    -- to prevent stem/beam merging across grand staff and across polyphonic voices!
    local notes_by_partition = {}
    local partition_keys_in_order = {}
    for _, vn in ipairs(visual_notes) do
        local st = vn.in_staff or (vn.in_treble and "treble" or "bass")
        local v = (vn.orig and vn.orig.chan) or 0
        local part_key = st .. "_v" .. tostring(v)
        if not notes_by_partition[part_key] then
            notes_by_partition[part_key] = {}
            table.insert(partition_keys_in_order, part_key)
        end
        table.insert(notes_by_partition[part_key], vn)
    end
    
    for _, pk in ipairs(partition_keys_in_order) do
        group_staff_notes(notes_by_partition[pk])
    end
    
    return groups
end

-- Calculates standard-compliant beam geometry (stem direction, slant, stem endpoints)
function Engraver.calculate_and_draw_beams(draw_list, group, s, col, all_note_render_by_key, state, is_polyphonic)
    if #group < 2 then return {} end
    
    -- 1. Condense notes by temporal onsets (chord notes share the same stem/beam step)
    local onsets = {}
    for _, vn in ipairs(group) do
        local last_onset = onsets[#onsets]
        if last_onset and math.abs(vn.start_qn - last_onset.start_qn) < 0.02 then
            table.insert(last_onset.notes, vn)
            if vn.dur_qn < last_onset.dur_qn then last_onset.dur_qn = vn.dur_qn end
            if vn.vis_ny < last_onset.min_ny then last_onset.min_ny = vn.vis_ny end
            if vn.vis_ny > last_onset.max_ny then last_onset.max_ny = vn.vis_ny end
            if vn.dstep < last_onset.min_dstep then last_onset.min_dstep = vn.dstep end
            if vn.dstep > last_onset.max_dstep then last_onset.max_dstep = vn.dstep end
        else
            local onset_base_x = (vn.vis_nx or vn.nominal_nx) - (vn.head_x_offset or 0)
            table.insert(onsets, {
                start_qn = vn.start_qn,
                dur_qn = vn.dur_qn,
                notes = { vn },
                nominal_nx = onset_base_x,
                min_ny = vn.vis_ny,
                max_ny = vn.vis_ny,
                min_dstep = vn.dstep,
                max_dstep = vn.dstep,
                in_treble = vn.in_treble
            })
        end
    end
    
    -- A beam must connect at least 2 DISTINCT temporal onsets!
    if #onsets < 2 then return {} end
    
    local beam_col = col or 0x111111FF
    local beam_h = 3.2 * s
    local beam_gap = 5.8 * s -- Improved spacing between 16th and 8th beams
    
    -- 2. Uniform stem direction for the group:
    local max_dist = -1
    local group_stem_down = false
    local manual_stem_dir = nil
    for _, onset in ipairs(onsets) do
        for _, vn in ipairs(onset.notes) do
            local sdir = Engraver.get_note_stem_direction(vn, state)
            if sdir then
                manual_stem_dir = sdir
            end
            local mid_step = 4 -- Middle line of 5-line staff (B4 in treble clef, D3 in bass clef, C4 in alto clef)
            local dist = math.abs(vn.dstep - mid_step)
            if dist > max_dist then
                max_dist = dist
                group_stem_down = (vn.dstep >= mid_step)
            end
        end
    end
    if manual_stem_dir == "up" then
        group_stem_down = false
    elseif manual_stem_dir == "down" then
        group_stem_down = true
    elseif is_polyphonic then
        -- Gould ("Behind Bars", p. 308): Polyphonic voice-leading standard
        -- Voice 1 (and odd voices 1, 3 -> chan 0, 2) = stems UP!
        -- Voice 2 (and even voices 2, 4 -> chan 1, 3) = stems DOWN!
        local grp_v = (group[1] and group[1].orig and group[1].orig.chan) or 0
        if grp_v % 2 == 1 then
            group_stem_down = true
        else
            group_stem_down = false
        end
    end
    
    -- 3. Stem X positions per onset (and for all notes within the onset)
    for _, onset in ipairs(onsets) do
        local sx = onset.nominal_nx + (group_stem_down and (-5.0 * s) or (5.0 * s))
        onset.stem_x = sx
        for _, vn in ipairs(onset.notes) do
            vn.beam_stem_x = sx
        end
    end
    
    local first_onset = onsets[1]
    local last_onset  = onsets[#onsets]
    local x1 = first_onset.stem_x
    local x2 = last_onset.stem_x
    local dx = math.max(1.0, x2 - x1)
    
    -- 4. Melodic slope according to Gardner Read / Elaine Gould:
    -- Allows dynamic slant up to 0.42 for wide intervals and extended runs,
    -- avoiding artificial flatness without flattening immediately on minor contour undulations:
    local y_first = group_stem_down and first_onset.max_ny or first_onset.min_ny
    local y_last  = group_stem_down and last_onset.max_ny or last_onset.min_ny
    local raw_slope = (y_last - y_first) / dx
    local slope = math.max(-0.42, math.min(0.42, raw_slope))
    
    -- If melody fluctuates strongly (sharp direction changes without contour trend), keep horizontal
    local span_y = math.abs(y_last - y_first)
    local has_higher, has_lower = false, false
    for i = 2, #onsets - 1 do
        local mid_y = group_stem_down and onsets[i].max_ny or onsets[i].min_ny
        if mid_y < math.min(y_first, y_last) - 8*s then has_higher = true end
        if mid_y > math.max(y_first, y_last) + 8*s then has_lower = true end
    end
    if (has_higher and has_lower) or (span_y < 3 * s and #onsets > 2) then
        slope = 0
    end
    
    -- 5. Vertical position of primary beam
    local std_stem_len = 30 * s
    local beam_y1
    
    if group_stem_down then
        local max_needed_y1 = -math.huge
        for _, onset in ipairs(onsets) do
            local cur_x = onset.stem_x
            local needed_y1 = (onset.max_ny + std_stem_len) - slope * (cur_x - x1)
            if needed_y1 > max_needed_y1 then max_needed_y1 = needed_y1 end
        end
        beam_y1 = max_needed_y1
    else
        local min_needed_y1 = math.huge
        for _, onset in ipairs(onsets) do
            local cur_x = onset.stem_x
            local needed_y1 = (onset.min_ny - std_stem_len) - slope * (cur_x - x1)
            if needed_y1 < min_needed_y1 then min_needed_y1 = needed_y1 end
        end
        beam_y1 = min_needed_y1
    end
    
    local beam_y2 = beam_y1 + slope * (x2 - x1)
    
    -- 6. Exact calculation of stem endpoints for each note (gapless connection)
    for _, onset in ipairs(onsets) do
        local cur_x = onset.stem_x
        local cur_beam_y = beam_y1 + slope * (cur_x - x1)
        for _, vn in ipairs(onset.notes) do
            vn.beam_stem_x = cur_x
            vn.beam_stem_end_y = cur_beam_y
            vn.beam_stem_down = group_stem_down
            
            if all_note_render_by_key and all_note_render_by_key[vn.key] then
                local rdata = all_note_render_by_key[vn.key]
                rdata.stem_x = cur_x
                rdata.stem_end_y = cur_beam_y
                rdata.stem_down = group_stem_down
            end
        end
    end
    
    -- 7. Draw beams
    local dir = group_stem_down and -1 or 1
    local half_stem = 1.25 * s
    
    local function draw_beam_quad(x_a, y_a, x_b, y_b)
        if not draw_list then return end
        local left_x, right_x, y_left, y_right
        if x_a <= x_b then
            left_x, right_x = x_a, x_b
            y_left, y_right = y_a, y_b
        else
            left_x, right_x = x_b, x_a
            y_left, y_right = y_b, y_a
        end
        
        local top_y1, btm_y1, top_y2, btm_y2
        if group_stem_down then
            top_y1 = y_left - beam_h
            btm_y1 = y_left
            top_y2 = y_right - beam_h
            btm_y2 = y_right
        else
            top_y1 = y_left
            btm_y1 = y_left + beam_h
            top_y2 = y_right
            btm_y2 = y_right + beam_h
        end
        
        if reaper.APIExists("ImGui_DrawList_AddQuadFilled") then
            -- Vertices are strictly clockwise in Dear ImGui screen space:
            -- top-left -> top-right -> bottom-right -> bottom-left.
            -- This guarantees outward-facing anti-aliasing normals on all 4 edges,
            -- rendering silky smooth, non-jagged beam edges regardless of stem direction.
            reaper.ImGui_DrawList_AddQuadFilled(draw_list,
                left_x,  top_y1,
                right_x, top_y2,
                right_x, btm_y2,
                left_x,  btm_y1,
                beam_col)
        else
            local my1 = (top_y1 + btm_y1) * 0.5
            local my2 = (top_y2 + btm_y2) * 0.5
            reaper.ImGui_DrawList_AddLine(draw_list, left_x, my1, right_x, my2, beam_col, beam_h)
        end
    end
    
    -- Primary beam (Level 0: eighths)
    local bx1 = x1 - half_stem
    local bx2 = x2 + half_stem
    local by1 = beam_y1 + slope * (bx1 - x1)
    local by2 = beam_y1 + slope * (bx2 - x1)
    draw_beam_quad(bx1, by1, bx2, by2)
    
    -- Secondary beam levels (Level 1: 16ths, Level 2: 32nds) across onsets
    local max_flags = 0
    for _, onset in ipairs(onsets) do
        local fc = Engraver.get_flag_count(onset.dur_qn)
        if fc > max_flags then max_flags = fc end
    end
    
    for level = 1, max_flags - 1 do
        local offset_y = level * beam_gap * dir
        local seg_start = nil
        for i, onset in ipairs(onsets) do
            local fc = Engraver.get_flag_count(onset.dur_qn)
            if fc > level then
                if not seg_start then seg_start = i end
            else
                if seg_start and (i - seg_start) >= 2 then
                    local sx = onsets[seg_start].stem_x - (seg_start == 1 and half_stem or 0)
                    local sy = (beam_y1 + slope * (sx - x1)) + offset_y
                    local ex = onsets[i-1].stem_x + ((i-1) == #onsets and half_stem or 0)
                    local ey = (beam_y1 + slope * (ex - x1)) + offset_y
                    draw_beam_quad(sx, sy, ex, ey)
                elseif seg_start and (i - seg_start) == 1 then
                    -- Fractional beam (stub / beamlet)
                    local stem_pos = onsets[seg_start].stem_x
                    local stub_len = 9 * s
                    local stub_dir = (seg_start > 1) and -1 or 1
                    local sx, ex
                    if stub_dir == 1 then
                        sx = stem_pos - (seg_start == 1 and half_stem or 0)
                        ex = stem_pos + stub_len
                    else
                        sx = stem_pos + (seg_start == #onsets and half_stem or 0)
                        ex = stem_pos - stub_len
                    end
                    local sy = (beam_y1 + slope * (sx - x1)) + offset_y
                    local ey = (beam_y1 + slope * (ex - x1)) + offset_y
                    draw_beam_quad(sx, sy, ex, ey)
                end
                seg_start = nil
            end
        end
        if seg_start then
            if (#onsets - seg_start + 1) >= 2 then
                local sx = onsets[seg_start].stem_x - (seg_start == 1 and half_stem or 0)
                local sy = (beam_y1 + slope * (sx - x1)) + offset_y
                local ex = onsets[#onsets].stem_x + half_stem
                local ey = (beam_y1 + slope * (ex - x1)) + offset_y
                draw_beam_quad(sx, sy, ex, ey)
            elseif (#onsets - seg_start + 1) == 1 then
                local stem_pos = onsets[seg_start].stem_x
                local stub_len = 9 * s
                local stub_dir = (#onsets > 1) and -1 or 1
                local sx, ex
                if stub_dir == 1 then
                    sx = stem_pos - (seg_start == 1 and half_stem or 0)
                    ex = stem_pos + stub_len
                else
                    sx = stem_pos + (seg_start == #onsets and half_stem or 0)
                    ex = stem_pos - stub_len
                end
                local sy = (beam_y1 + slope * (sx - x1)) + offset_y
                local ey = (beam_y1 + slope * (ex - x1)) + offset_y
                draw_beam_quad(sx, sy, ex, ey)
            end
        end
    end
    
    -- Record beamed notes
    local beamed_keys = {}
    for _, onset in ipairs(onsets) do
        for _, vn in ipairs(onset.notes) do
            beamed_keys[vn.key] = true
        end
    end
    return beamed_keys
end

-- ==============================================================================
-- NOTATION ELEMENT DRAW HELPERS (NOTEHEADS, ACCIDENTALS, TIES, ETC.)
-- ==============================================================================

function Engraver.draw_oval_notehead(draw_list, cx, cy, s, col, filled, is_whole, font_music, notehead_type)
    local font_sz = math.floor(40 * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local glyph
        if notehead_type == "circle_x" then
            glyph = SMUFL.noteheadCircleX
        elseif notehead_type == "x" then
            glyph = is_whole and SMUFL.noteheadXWhole or (filled and SMUFL.noteheadXBlack or SMUFL.noteheadXHalf)
        elseif notehead_type == "triangle" then
            glyph = is_whole and SMUFL.noteheadTriangleUpWhole or (filled and SMUFL.noteheadTriangleUpBlack or SMUFL.noteheadTriangleUpHalf)
        elseif notehead_type == "diamond" then
            glyph = (is_whole or not filled) and SMUFL.noteheadDiamondHalf or SMUFL.noteheadDiamondBlack
        else
            glyph = is_whole and SMUFL.note_whole or (filled and SMUFL.note_black or SMUFL.note_half)
        end
        local pos_y = cy - (font_sz * 2.012)
        local pos_x = cx - (is_whole and 8.4 or 5.9) * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, glyph)
        return
    end
    
    -- Fallback vector shapes for percussion noteheads
    if notehead_type == "x" or notehead_type == "circle_x" then
        local r = 5.0 * s
        reaper.ImGui_DrawList_AddLine(draw_list, cx - r, cy - r, cx + r, cy + r, col, 2.0 * s)
        reaper.ImGui_DrawList_AddLine(draw_list, cx - r, cy + r, cx + r, cy - r, col, 2.0 * s)
        if notehead_type == "circle_x" then
            reaper.ImGui_DrawList_AddCircle(draw_list, cx, cy, 6.5 * s, col, 0, 1.6 * s)
        end
        return
    elseif notehead_type == "triangle" then
        local r = 5.5 * s
        local p1x, p1y = cx, cy - r
        local p2x, p2y = cx - r * 1.1, cy + r * 0.8
        local p3x, p3y = cx + r * 1.1, cy + r * 0.8
        if filled then
            reaper.ImGui_DrawList_AddTriangleFilled(draw_list, p1x, p1y, p2x, p2y, p3x, p3y, col)
        else
            reaper.ImGui_DrawList_AddTriangle(draw_list, p1x, p1y, p2x, p2y, p3x, p3y, col, 1.8 * s)
        end
        return
    elseif notehead_type == "diamond" then
        local rx = 5.5 * s
        local ry = 4.0 * s
        local p1x, p1y = cx, cy - ry
        local p2x, p2y = cx + rx, cy
        local p3x, p3y = cx, cy + ry
        local p4x, p4y = cx - rx, cy
        reaper.ImGui_DrawList_PathClear(draw_list)
        reaper.ImGui_DrawList_PathLineTo(draw_list, p1x, p1y)
        reaper.ImGui_DrawList_PathLineTo(draw_list, p2x, p2y)
        reaper.ImGui_DrawList_PathLineTo(draw_list, p3x, p3y)
        reaper.ImGui_DrawList_PathLineTo(draw_list, p4x, p4y)
        if filled then
            reaper.ImGui_DrawList_PathFillConvex(draw_list, col)
        else
            reaper.ImGui_DrawList_PathStroke(draw_list, col, reaper.ImGui_DrawFlags_Closed(), 1.8 * s)
        end
        return
    end

    if not reaper.APIExists("ImGui_DrawList_PathClear") then
        if filled then
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, 5.2*s, col)
        else
            reaper.ImGui_DrawList_AddCircle(draw_list, cx, cy, 5.5*s, col, 0, 2.0*s)
        end
        return
    end
    
    local rx = 5.8 * s
    local ry = 3.6 * s
    local tilt = 0.35
    local cos_t = math.cos(tilt)
    local sin_t = math.sin(tilt)
    local segs = 20
    reaper.ImGui_DrawList_PathClear(draw_list)
    for i = 0, segs do
        local angle = (i / segs) * 2 * math.pi
        local px = rx * math.cos(angle)
        local py = ry * math.sin(angle)
        local rpx = px * cos_t - py * sin_t
        local rpy = px * sin_t + py * cos_t
        reaper.ImGui_DrawList_PathLineTo(draw_list, cx + rpx, cy + rpy)
    end
    if filled then
        reaper.ImGui_DrawList_PathFillConvex(draw_list, col)
    else
        reaper.ImGui_DrawList_PathStroke(draw_list, col, reaper.ImGui_DrawFlags_Closed(), 2.0 * s)
    end
end

function Engraver.draw_repeat_mark(draw_list, cx, cy, s, col, font_music, repeat_type)
    repeat_type = repeat_type or "1bar"
    local font_sz = math.floor(46 * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local glyph = SMUFL.repeat1Bar
        if repeat_type == "2bar" then
            glyph = SMUFL.repeat2Bars
        elseif repeat_type == "1beat" then
            glyph = SMUFL.repeat1Beat
        end
        local pos_y = cy - (font_sz * 2.012)
        local pos_x = cx - 11.0 * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, glyph)
        return
    end
    
    -- Fallback: Authentic simile mark % (thick slash + two dots)
    local slash_len = 16 * s
    reaper.ImGui_DrawList_AddLine(draw_list, cx - slash_len, cy + slash_len, cx + slash_len, cy - slash_len, col, 3.2 * s)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, cx - 7 * s, cy - 6 * s, 3.2 * s, col)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, cx + 7 * s, cy + 6 * s, 3.2 * s, col)
end

function Engraver.draw_accidental(draw_list, acc_type, x, y, s, font_music, custom_col)
    local col = custom_col or Constants.COLORS.notehead_black or 0x1A1A1AFF
    local font_sz = math.floor(40 * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local glyph = (acc_type == 1) and SMUFL.acc_sharp or ((acc_type == -1) and SMUFL.acc_flat or SMUFL.acc_natural)
        local pos_y = y - (font_sz * 2.012)
        local pos_x = x - 6.0 * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, glyph)
        return
    end
    if acc_type == 1 then
        reaper.ImGui_DrawList_AddLine(draw_list, x - 3*s, y - 8*s, x - 3*s, y + 8*s, col, 1.5*s)
        reaper.ImGui_DrawList_AddLine(draw_list, x + 3*s, y - 8*s, x + 3*s, y + 8*s, col, 1.5*s)
        reaper.ImGui_DrawList_AddLine(draw_list, x - 7*s, y - 2*s, x + 7*s, y - 4*s, col, 2.0*s)
        reaper.ImGui_DrawList_AddLine(draw_list, x - 7*s, y + 4*s, x + 7*s, y + 2*s, col, 2.0*s)
    elseif acc_type == -1 then
        reaper.ImGui_DrawList_AddLine(draw_list, x - 3*s, y - 10*s, x - 3*s, y + 6*s, col, 1.5*s)
        reaper.ImGui_DrawList_AddBezierCubic(draw_list, x - 3*s, y - 2*s, x + 5*s, y - 4*s, x + 5*s, y + 6*s, x - 3*s, y + 4*s, col, 1.8*s)
    end
end

function Engraver.get_key_signature_width(key_idx, s)
    if type(key_idx) == "table" then
        key_idx = key_idx.key_idx or key_idx.idx or 0
    end
    return math.abs(key_idx or 0) * (9.5 * (s or 1.0))
end

function Engraver.draw_key_signature(draw_list, key_idx, x, bot_y, line_spacing, s, col, font_music, clef_type, cancel_key_idx)
    if type(key_idx) == "table" then
        key_idx = key_idx.key_idx or key_idx.idx or 0
    end
    if type(cancel_key_idx) == "table" then
        cancel_key_idx = cancel_key_idx.key_idx or cancel_key_idx.idx or 0
    end
    local eff_k = key_idx or 0
    local is_cancelling = (eff_k == 0 and cancel_key_idx and cancel_key_idx ~= 0)
    if not is_cancelling and eff_k == 0 then return x end

    local ref_k = is_cancelling and cancel_key_idx or eff_k
    local count = math.min(7, math.abs(ref_k))
    local is_sharp = (ref_k > 0)
    local acc_type = is_cancelling and 0 or (is_sharp and 1 or -1)
    local scale = s or 1.0
    local acc_spacing = 9.5 * scale
    local draw_col = col or Constants.COLORS.clef_col or Constants.COLORS.notehead_black or 0x1A1A1AFF
    local step_y = (line_spacing or (8.0 * scale)) / 2.0

    local clef = clef_type or "treble"
    if clef ~= "treble" and clef ~= "bass" and clef ~= "alto" then
        if clef == "tenor" then
            clef = "alto"
        else
            clef = "treble"
        end
    end

    local step_tables = {
        sharp = {
            treble = { 8, 5, 9, 6, 3, 7, 4 },
            bass   = { 6, 3, 7, 4, 1, 5, 2 },
            alto   = { 7, 4, 8, 5, 2, 6, 3 }
        },
        flat = {
            treble = { 4, 7, 3, 6, 2, 5, 1 },
            bass   = { 2, 5, 1, 4, 0, 3, -1 },
            alto   = { 3, 6, 2, 5, 1, 4, 0 }
        }
    }

    local steps = is_sharp and step_tables.sharp[clef] or step_tables.flat[clef]
    for i = 1, count do
        local step = steps[i] or 4
        local acc_y = bot_y - (step * step_y)
        local acc_x = x + ((i - 1) * acc_spacing) + (5.0 * scale)
        Engraver.draw_accidental(draw_list, acc_type, acc_x, acc_y, scale, font_music, draw_col)
    end

    return x + (count * acc_spacing)
end

function Engraver.draw_dot(draw_list, cx, cy, s, col, font_music)
    local font_sz = math.floor(40 * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local pos_y = cy - (font_sz * 2.012)
        local pos_x = cx + 8.5 * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, SMUFL.dot)
        return
    end
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, cx + 9*s, cy - 2*s, 1.8*s, col)
end

function Engraver.draw_articulation(draw_list, art_id, x, y, s, col, font_music, is_above)
    if not art_id or art_id == "" then return end
    local art_col = col or 0x1A1A1AFF
    
    if art_id == "staccato" or art_id == "stacc" then
        -- Solid round dot
        reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, 2.2 * s, art_col)
        return
    elseif art_id == "staccatissimo" or art_id == "staccatiss" or art_id == "wedge" then
        if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            local font_sz = math.floor(34 * s + 0.5)
            local glyph = is_above and (SMUFL.staccatissimoAbove or utf8.char(0xE4A6)) or (SMUFL.staccatissimoBelow or utf8.char(0xE4A7))
            local pos_y = y - (font_sz * 2.012)
            local pos_x = x - (font_sz * 0.05)
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, art_col, glyph)
            return
        end
        -- Smooth vector fallback (filled wedge with anti-aliased contour stroke)
        if is_above then
            -- Above notehead: pointing down towards notehead
            reaper.ImGui_DrawList_AddTriangleFilled(draw_list, x - 2.5*s, y - 7.0*s, x + 2.5*s, y - 7.0*s, x, y, art_col)
            if reaper.APIExists("ImGui_DrawList_AddTriangle") then
                reaper.ImGui_DrawList_AddTriangle(draw_list, x - 2.5*s, y - 7.0*s, x + 2.5*s, y - 7.0*s, x, y, art_col, 1.2 * s)
            end
        else
            -- Below notehead: pointing up towards notehead
            reaper.ImGui_DrawList_AddTriangleFilled(draw_list, x - 2.5*s, y + 7.0*s, x + 2.5*s, y + 7.0*s, x, y, art_col)
            if reaper.APIExists("ImGui_DrawList_AddTriangle") then
                reaper.ImGui_DrawList_AddTriangle(draw_list, x - 2.5*s, y + 7.0*s, x + 2.5*s, y + 7.0*s, x, y, art_col, 1.2 * s)
            end
        end
        return
    elseif art_id == "tenuto" or art_id == "ten" then
        -- Clean horizontal line under/over notehead
        reaper.ImGui_DrawList_AddLine(draw_list, x - 6.0 * s, y, x + 6.0 * s, y, art_col, 2.2 * s)
        return
    elseif art_id == "harmonic" or art_id == "harm" or art_id == "flageolet" then
        -- Flageolet open circle
        reaper.ImGui_DrawList_AddCircle(draw_list, x, y, 3.2 * s, art_col, 16, 1.5 * s)
        return
    elseif art_id == "marcato" or art_id == "marc" then
        -- Pointed roof / hat ^
        reaper.ImGui_DrawList_AddLine(draw_list, x - 4.5*s, y + 3.5*s, x, y - 4*s, art_col, 2.0 * s)
        reaper.ImGui_DrawList_AddLine(draw_list, x + 4.5*s, y + 3.5*s, x, y - 4*s, art_col, 2.0 * s)
        return
    elseif art_id == "accent" or art_id == "acc" then
        -- Horizontal wedge >
        reaper.ImGui_DrawList_AddLine(draw_list, x - 5.5*s, y - 3.5*s, x + 5.5*s, y, art_col, 1.8 * s)
        reaper.ImGui_DrawList_AddLine(draw_list, x - 5.5*s, y + 3.5*s, x + 5.5*s, y, art_col, 1.8 * s)
        return
    elseif art_id == "fermata" then
        Engraver.draw_fermata(draw_list, x, y, s, art_col, font_music, not is_above, "standard")
        return
    end
end

function Engraver.draw_fermata(draw_list, x, y, s, col, font_music, is_below, ferm_type)
    local f_col = col or Constants.COLORS.notehead_black or 0x111111FF
    local font_sz = math.floor(38 * s + 0.5)
    local glyph = nil
    if ferm_type == "short" then
        glyph = is_below and SMUFL.fermataShortBelow or SMUFL.fermataShortAbove
    elseif ferm_type == "long" then
        glyph = is_below and SMUFL.fermataLongBelow or SMUFL.fermataLongAbove
    elseif ferm_type == "very_long" then
        glyph = is_below and SMUFL.fermataVeryLongBelow or SMUFL.fermataVeryLongAbove
    else
        glyph = is_below and SMUFL.fermataBelow or SMUFL.fermataAbove
    end

    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") and glyph then
        local pos_x = x - (11 * s)
        local pos_y = is_below and (y - 5 * s) or (y - (font_sz * 0.72))
        local ok = pcall(reaper.ImGui_DrawList_AddTextEx, draw_list, font_music, font_sz, pos_x, pos_y, f_col, glyph)
        if ok then return end
    end

    -- Vector fallback: Arc + Dot
    local r = 8.0 * s
    local dot_r = 2.2 * s
    if is_below then
        reaper.ImGui_DrawList_PathClear(draw_list)
        reaper.ImGui_DrawList_PathArcTo(draw_list, x, y - 2*s, r, 0, math.pi)
        reaper.ImGui_DrawList_PathStroke(draw_list, f_col, 0, 2.0 * s)
        reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y + 2*s, dot_r, f_col)
    else
        reaper.ImGui_DrawList_PathClear(draw_list)
        reaper.ImGui_DrawList_PathArcTo(draw_list, x, y + 2*s, r, math.pi, 2 * math.pi)
        reaper.ImGui_DrawList_PathStroke(draw_list, f_col, 0, 2.0 * s)
        reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y - 2*s, dot_r, f_col)
    end
end

function Engraver.draw_rehearsal_mark(draw_list, x, y, s, label, is_selected, is_hovered, font_bold, m_type)
    label = label or "A"
    m_type = m_type or "letter"

    local is_symbol = (m_type == "segno" or m_type == "coda")
    local txt_len = #label
    local box_w = math.max(26 * s, (txt_len * 11 * s) + 14 * s)
    local box_h = 24 * s
    local x0 = x - (box_w / 2)
    local y0 = y - (box_h / 2)
    local x1 = x0 + box_w
    local y1 = y0 + box_h

    local bg_col = is_selected and 0xFFF3E0FF
                 or (is_hovered and 0xFFF8E7FF or (Constants.COLORS.rehearsal_box_bg or 0xFAF8F5FF))
    local border_col = is_selected and (Constants.COLORS.selection_gold or 0xFF9F1CFF)
                     or (is_hovered and 0xFFB300FF or (Constants.COLORS.rehearsal_border or 0x1A1A1AFF))
    local text_col = is_selected and (Constants.COLORS.selection_gold or 0xFF9F1CFF)
                   or (Constants.COLORS.rehearsal_text or 0x111111FF)

    if is_symbol then
        -- Draw symbol with prominent engraving size without surrounding box
        if is_hovered or is_selected then
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, x, y, 16 * s, 0xFF9F1C33)
        end
        local sym_col = is_selected and (Constants.COLORS.selection_gold or 0xFF9F1CFF)
                      or (is_hovered and 0xFFB300FF or (Constants.COLORS.rehearsal_text or Constants.COLORS.notehead_black or 0x111111FF))
        local f_sz = 26 * s
        local tx = x - 8 * s
        local ty = y - 13 * s
        if font_bold and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            pcall(reaper.ImGui_DrawList_AddTextEx, draw_list, font_bold, f_sz, tx, ty, sym_col, label)
        else
            reaper.ImGui_DrawList_AddText(draw_list, tx, ty, sym_col, label)
        end
    else
        -- Classical boxed rehearsal frame (Elaine Gould standard)
        reaper.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, bg_col, 4.0 * s)
        reaper.ImGui_DrawList_AddRect(draw_list, x0, y0, x1, y1, border_col, 4.0 * s, 0, 2.0 * s)

        local f_sz = 15 * s
        local tx = x0 + (box_w - (txt_len * 8.5 * s)) / 2
        local ty = y0 + (box_h - f_sz) / 2
        if font_bold and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            pcall(reaper.ImGui_DrawList_AddTextEx, draw_list, font_bold, f_sz, tx, ty, text_col, label)
        else
            reaper.ImGui_DrawList_AddText(draw_list, tx, ty, text_col, label)
        end
    end
end

function Engraver.draw_arpeggio(draw_list, x, y_top, y_bottom, s, col, font_music, dir)
    local arp_col = col or Constants.COLORS.notehead_black or 0x111111FF
    local wave_h = 7.0 * s
    local amp = 3.2 * s
    local total_h = math.max(wave_h * 2, y_bottom - y_top + 6 * s)
    local num_waves = math.max(2, math.floor(total_h / wave_h + 0.5))
    local start_y = y_top - 3 * s

    for i = 0, num_waves - 1 do
        local cy = start_y + (i * wave_h)
        local y_end = cy + wave_h
        -- Smooth S-curve (cubic bezier)
        reaper.ImGui_DrawList_AddBezierCubic(draw_list,
            x, cy,
            x - amp, cy + (wave_h * 0.25),
            x + amp, cy + (wave_h * 0.75),
            x, y_end,
            arp_col, 1.8 * s)
    end

    -- Direction arrow if explicitly specified
    if dir == "down" then
        local arrow_y = start_y + (num_waves * wave_h)
        reaper.ImGui_DrawList_AddTriangleFilled(draw_list,
            x - 3.5 * s, arrow_y,
            x + 3.5 * s, arrow_y,
            x, arrow_y + 6.5 * s,
            arp_col)
    elseif dir == "up" then
        local arrow_y = start_y
        reaper.ImGui_DrawList_AddTriangleFilled(draw_list,
            x - 3.5 * s, arrow_y,
            x + 3.5 * s, arrow_y,
            x, arrow_y - 6.5 * s,
            arp_col)
    end
end

function Engraver.draw_flags(draw_list, stem_x, stem_end_y, s, col, count, stem_down, font_music)
    local font_sz = math.floor(40 * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local glyph = nil
        if count == 1 then glyph = stem_down and SMUFL.flag_8th_down or SMUFL.flag_8th_up
        elseif count == 2 then glyph = stem_down and SMUFL.flag_16th_down or SMUFL.flag_16th_up
        elseif count == 3 then glyph = stem_down and SMUFL.flag_32nd_down or SMUFL.flag_32nd_up
        elseif count >= 4 then glyph = stem_down and SMUFL.flag_64th_down or SMUFL.flag_64th_up end
        if glyph then
            local pos_y = stem_end_y - (font_sz * 2.012)
            local pos_x = stem_x - 0.5 * s
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, glyph)
            return
        end
    end
    for f = 0, count - 1 do
        local flag_offset = f * 7 * s
        local fy = stem_down and (stem_end_y + flag_offset) or (stem_end_y - flag_offset)
        local dir = stem_down and 1 or -1
        reaper.ImGui_DrawList_AddBezierCubic(draw_list,
            stem_x, fy,
            stem_x + 7*s, fy + dir * 10*s,
            stem_x + 13*s, fy + dir * 5*s,
            stem_x + 6*s, fy + dir * 16*s,
            col, 1.8*s)
    end
end

function Engraver.draw_tie(draw_list, x1, y1, x2, y2, s, col, above, opt_thickness)
    local dist = math.abs(x2 - x1)
    if dist < 6 * s then return end
    if math.abs(y2 - y1) > 16 * s then return end
    
    local arc_h = math.min(16 * s, math.max(6 * s, dist * 0.10))
    local dir = above and -1 or 1
    local offset_y = dir * arc_h
    local cp_offset = dist * 0.28
    
    local tie_col = col or Constants.COLORS.tie_col or Constants.COLORS.notehead_black or 0x1A1A1AFF
    local start_x = x1 + 4 * s
    local end_x   = x2 - 4 * s
    local start_y = y1 + dir * 5.0 * s
    local end_y   = y2 + dir * 5.0 * s
    local thickness = opt_thickness or (2.0 * s)
    
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        start_x, start_y,
        start_x + cp_offset, start_y + offset_y,
        end_x - cp_offset, end_y + offset_y,
        end_x, end_y,
        tie_col, thickness)
end

function Engraver.draw_slur(draw_list, x1, y1, x2, y2, s, col, above, opt_thickness)
    local dist_x = x2 - x1
    if math.abs(dist_x) < 4 * s then return end
    
    local dx = dist_x
    local dy = y2 - y1
    local chord_len = math.sqrt(dx * dx + dy * dy)
    
    local arc_h = math.min(26 * s, math.max(8 * s, chord_len * 0.12))
    local dir = above and -1 or 1
    
    local start_x = x1 + 5.0 * s
    local end_x   = x2 - 5.0 * s
    local start_y = y1 + dir * 6.0 * s
    local end_y   = y2 + dir * 6.0 * s
    
    local cp_dist = math.abs(start_x - end_x) * 0.28
    local cp1_x = start_x + cp_dist
    local cp1_y = start_y + dir * arc_h
    local cp2_x = end_x - cp_dist
    local cp2_y = end_y + dir * arc_h
    
    local slur_col = col or Constants.COLORS.slur_col or Constants.COLORS.tie_col or Constants.COLORS.notehead_black or 0x1A1A1AFF
    local thickness = opt_thickness or (2.0 * s)
    
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        start_x, start_y,
        cp1_x, cp1_y,
        cp2_x, cp2_y,
        end_x, end_y,
        slur_col, thickness)
end

function Engraver.draw_rest(draw_list, r, staff_bottom_y, line_spacing, margin_left, s, qn_per_measure, col, font_music, measure_map, custom_x)
    local rx = custom_x
    if not rx then
        if r.is_full_measure then
            if measure_map and measure_map.starts then
                local m_idx = r.measure_idx or 0
                local m_start = measure_map.starts[m_idx] or (margin_left + m_idx * measure_map.base_w)
                local m_w = measure_map.widths[m_idx] or measure_map.base_w
                rx = m_start + (m_w / 2)
            else
                local measure_w, pad_left, pad_right, usable_w = Engraver.get_measure_layout(s, qn_per_measure)
                local m_x = margin_left + (r.measure_idx * measure_w)
                rx = m_x + pad_left + (usable_w / 2)
            end
        else
            rx = Engraver.qn_to_canvas_x(r.start_qn, margin_left, s, qn_per_measure, measure_map)
        end
    end
    
    local font_sz = math.floor(40 * s + 0.5)
    local rest_col = col or Constants.COLORS.rest_col or Constants.COLORS.notehead_black or 0x1A1A1AFF
    
    -- Gould ("Behind Bars"): Voice-separated vertical placement of rests
    local y_offset = 0
    if r.voice == 2 then
        y_offset = line_spacing -- Lower voice: shifted down by one staff space
    elseif r.voice == 1 then
        y_offset = -0.5 * line_spacing -- Upper voice: shifted slightly upwards
    end
    
    local y_line4 = staff_bottom_y - 3 * line_spacing + y_offset
    local y_line3 = staff_bottom_y - 2 * line_spacing + y_offset
    
    if r.type == "whole" then
        if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            local pos_x = rx - 5.6 * s
            local pos_y = y_line4 - (font_sz * 2.012)
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, rest_col, SMUFL.rest_whole)
        else
            reaper.ImGui_DrawList_AddRectFilled(draw_list, rx - 6*s, y_line4, rx + 6*s, y_line4 + 5*s, rest_col)
        end
    elseif r.type == "half" then
        if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            local pos_x = rx - 5.6 * s
            local pos_y = y_line3 - (font_sz * 2.012)
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, rest_col, SMUFL.rest_half)
        else
            reaper.ImGui_DrawList_AddRectFilled(draw_list, rx - 6*s, y_line3 - 5*s, rx + 6*s, y_line3, rest_col)
        end
    elseif r.type == "quarter" then
        if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            local pos_x = rx - 5.4 * s
            local pos_y = y_line3 - (font_sz * 2.012)
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, rest_col, SMUFL.rest_quarter)
        else
            reaper.ImGui_DrawList_AddLine(draw_list, rx, y_line3 - 10*s, rx + 4*s, y_line3 - 4*s, rest_col, 2*s)
            reaper.ImGui_DrawList_AddLine(draw_list, rx + 4*s, y_line3 - 4*s, rx - 3*s, y_line3 + 2*s, rest_col, 2*s)
            reaper.ImGui_DrawList_AddLine(draw_list, rx - 3*s, y_line3 + 2*s, rx + 2*s, y_line3 + 8*s, rest_col, 2*s)
        end
    elseif r.type == "8th" then
        if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            local pos_x = rx - 5.0 * s
            local pos_y = y_line3 - (font_sz * 2.012)
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, rest_col, SMUFL.rest_8th)
        else
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 - 4*s, 2.5*s, rest_col)
            reaper.ImGui_DrawList_AddLine(draw_list, rx - 2*s, y_line3 - 4*s, rx + 3*s, y_line3 + 8*s, rest_col, 1.8*s)
        end
    elseif r.type == "16th" then
        if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            local pos_x = rx - 6.4 * s
            local pos_y = y_line3 - (font_sz * 2.012)
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, rest_col, SMUFL.rest_16th)
        else
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 - 7*s, 2.2*s, rest_col)
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 - 1*s, 2.2*s, rest_col)
            reaper.ImGui_DrawList_AddLine(draw_list, rx - 2*s, y_line3 - 7*s, rx + 4*s, y_line3 + 9*s, rest_col, 1.8*s)
        end
    elseif r.type == "32nd" then
        if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            local pos_x = rx - 7.2 * s
            local pos_y = y_line3 - (font_sz * 2.012)
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, rest_col, SMUFL.rest_32nd)
        else
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 - 10*s, 2.0*s, rest_col)
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 - 4*s, 2.0*s, rest_col)
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 + 2*s, 2.0*s, rest_col)
            reaper.ImGui_DrawList_AddLine(draw_list, rx - 2*s, y_line3 - 10*s, rx + 4*s, y_line3 + 10*s, rest_col, 1.8*s)
        end
    elseif r.type == "64th" then
        if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            local pos_x = rx - 7.5 * s
            local pos_y = y_line3 - (font_sz * 2.012)
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, rest_col, SMUFL.rest_64th)
        else
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 - 12*s, 1.8*s, rest_col)
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 - 7*s, 1.8*s, rest_col)
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 - 2*s, 1.8*s, rest_col)
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, rx - 2*s, y_line3 + 3*s, 1.8*s, rest_col)
            reaper.ImGui_DrawList_AddLine(draw_list, rx - 2*s, y_line3 - 12*s, rx + 4*s, y_line3 + 11*s, rest_col, 1.6*s)
        end
    end
end

-- ==============================================================================
-- TUPLET DETECTION & ENGRAVING (GARDNER READ / ELAINE GOULD STANDARDS)
-- Recognizes triplets (3:2), quintuplets (5:4), sextuplets (6:4), septuplets (7:4), octuplets (8:6)
-- Beamed: Numeral centered above/below beam without bracket
-- Unbeamed: Bracket with hooks [ N ] and centered numeral
-- ==============================================================================

local function is_tuplet_step(step, n)
    if n == 3 then
        -- Triplet 3:2 (3 notes in 1 beat or 2 beats etc.)
        -- 8th-note triplet: 0.333 QN (in 1.0 QN)
        -- 16th-note triplet: 0.167 QN (in 0.5 QN)
        -- Quarter-note triplet: 0.667 QN (in 2.0 QN)
        -- 32nd-note triplet: 0.083 QN (in 0.25 QN)
        -- Half-note triplet: 1.333 QN (in 4.0 QN)
        return (math.abs(step - 0.3333) < 0.055) or
               (math.abs(step - 0.1667) < 0.035) or
               (math.abs(step - 0.6667) < 0.070) or
               (math.abs(step - 0.0833) < 0.025) or
               (math.abs(step - 1.3333) < 0.100)
    elseif n == 5 then
        -- Quintuplet 5:4 (5 notes instead of 4)
        -- 16th: 0.200 QN (in 1.0 QN)
        -- 8th: 0.400 QN (in 2.0 QN)
        -- 32nd: 0.100 QN (in 0.5 QN)
        -- Quarter: 0.800 QN (in 4.0 QN)
        return (math.abs(step - 0.200) < 0.040) or
               (math.abs(step - 0.400) < 0.060) or
               (math.abs(step - 0.100) < 0.025) or
               (math.abs(step - 0.800) < 0.080)
    elseif n == 6 then
        -- Sextuplet 6:4 (6 notes instead of 4)
        -- 16th: 0.1667 QN (in 1.0 QN)
        -- 8th: 0.3333 QN (in 2.0 QN)
        -- 32nd: 0.0833 QN (in 0.5 QN)
        return (math.abs(step - 0.1667) < 0.035) or
               (math.abs(step - 0.3333) < 0.055) or
               (math.abs(step - 0.0833) < 0.025)
    elseif n == 7 then
        -- Septuplet 7:4 (7 notes instead of 4)
        -- 16th: 0.1429 QN (in 1.0 QN)
        -- 8th: 0.2857 QN (in 2.0 QN)
        -- 32nd: 0.0714 QN (in 0.5 QN)
        return (math.abs(step - 0.1429) < 0.020) or
               (math.abs(step - 0.2857) < 0.020) or
               (math.abs(step - 0.0714) < 0.015)
    elseif n == 8 then
        -- Compound meter octuplet: 8:6 in 1.5 QN (0.1875 QN) or 8:6 in 3.0 QN (0.3750 QN)
        -- (In simple meters, 8 notes in 2.0 QN or 1.0 QN are standard binary 16ths/32nds, not tuplets)
        return (math.abs(step - 0.1875) < 0.035) or
               (math.abs(step - 0.3750) < 0.055)
    end
    return false
end

local function draw_tuplet_digit(draw_list, cx, cy, n, s, col, font_music, font_main)
    local num_sz = math.floor(15 * s + 0.5)
    local str = tostring(n)
    local drew = false
    if font_main and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local pos_x = cx - (num_sz * 0.28)
        local pos_y = cy - (num_sz * 0.52)
        drew = pcall(reaper.ImGui_DrawList_AddTextEx, draw_list, font_main, num_sz, pos_x, pos_y, col, str)
    end
    if not drew then
        reaper.ImGui_DrawList_AddText(draw_list, cx - 4 * s, cy - 6 * s, col, str)
    end
end

local function is_valid_tuplet(onsets, i, n, qn_per_measure)
    if i + n - 1 > #onsets then return false end
    
    local first_o = onsets[i]
    local last_o = onsets[i + n - 1]
    
    -- All notes must lie within the same measure
    local m_first = math.floor(first_o.start_qn / qn_per_measure)
    local m_last  = math.floor(last_o.start_qn / qn_per_measure)
    if m_first ~= m_last then return false end
    
    local total_span_approx = (last_o.start_qn - first_o.start_qn)
    local step = total_span_approx / (n - 1)
    
    -- 1. Check start time uniformity (uniform step)
    for k = 1, n - 1 do
        local diff = onsets[i + k].start_qn - onsets[i + k - 1].start_qn
        if math.abs(diff - step) > 0.05 then
            return false
        end
    end
    
    -- 2. Step size must correspond to a valid tuplet division
    if not is_tuplet_step(step, n) then return false end
    
    -- 3. Each note in tuplet must have an appropriate duration (dur ~ step)
    for k = 0, n - 1 do
        local o = onsets[i + k]
        local d = o.dur_qn or step
        -- Duration must not deviate dramatically (e.g. no quarter note in eighth-note triplet)
        if math.abs(d - step) > (step * 0.45) then
            return false
        end
    end
    
    -- 4. Metric alignment: Tuplet onset must fit its total duration
    local total_dur = n * step
    local beat_in_bar = (first_o.start_qn % qn_per_measure)
    if math.abs(total_dur - 4.0) < 0.20 then
        -- Full-measure tuplet (e.g. quarter quintuplet in 4/4): Start must be on downbeat (beat 0)
        if beat_in_bar > 0.10 and beat_in_bar < (qn_per_measure - 0.10) then return false end
    elseif math.abs(total_dur - 1.0) < 0.12 then
        -- 1-beat tuplet (e.g. 8th-note triplet in 1.0 QN): Start must align with beat
        local sub = beat_in_bar % 1.0
        if sub > 0.08 and sub < (1.0 - 0.08) then return false end
    elseif math.abs(total_dur - 2.0) < 0.15 then
        -- 2-beat tuplet (e.g. quarter-note triplet in 2.0 QN): Start aligns with beat
        local sub = beat_in_bar % 1.0
        if sub > 0.08 and sub < (1.0 - 0.08) then return false end
    elseif math.abs(total_dur - 0.5) < 0.08 then
        -- 0.5-beat tuplet (16th-note triplet): Start on 0.5 beat grid
        local sub = beat_in_bar % 0.5
        if sub > 0.06 and sub < (0.5 - 0.06) then return false end
    end
    
    return true, step
end

function Engraver.detect_and_draw_tuplets(draw_list, visual_notes, s, col, font_music, font_main, qn_per_measure, beam_groups, cull_min_x, cull_max_x, ghost_col)
    if not visual_notes or #visual_notes < 3 then return end

    local handled_note_keys = {}
    local beamed_note_keys = {}

    -- Collect all notes that reside in beam groups (beam_groups)
    if beam_groups then
        for _, bgroup in ipairs(beam_groups) do
            for _, vn in ipairs(bgroup) do
                if vn.key then
                    beamed_note_keys[vn.key] = true
                end
            end
        end
    end

    -- --------------------------------------------------------------------------
    -- PASS 1: BEAMED TUPLETS (NO BRACKET, NUMERAL DIRECTLY AT BEAM)
    -- --------------------------------------------------------------------------
    if beam_groups then
        for _, bgroup in ipairs(beam_groups) do
            local onsets = {}
            for _, vn in ipairs(bgroup) do
                local last = onsets[#onsets]
                if last and math.abs(vn.start_qn - last.start_qn) < 0.02 then
                    table.insert(last.notes, vn)
                else
                    table.insert(onsets, {
                        start_qn = vn.start_qn,
                        dur_qn = vn.dur_qn,
                        notes = { vn },
                        nominal_nx = vn.nominal_nx or vn.vis_nx,
                        beam_stem_x = vn.beam_stem_x,
                        beam_stem_end_y = vn.beam_stem_end_y,
                        beam_stem_down = vn.beam_stem_down
                    })
                end
            end

            local num_o = #onsets
            local bi = 1
            while bi <= num_o do
                local b_matched = false
                for _, n in ipairs({ 8, 7, 6, 5, 3 }) do
                    if bi + n - 1 <= num_o then
                        local ok, step = is_valid_tuplet(onsets, bi, n, qn_per_measure)
                        if ok then
                            local is_ghost_tuplet = true
                            for k = 0, n - 1 do
                                for _, vn in ipairs(onsets[bi + k].notes) do
                                    if vn.key then handled_note_keys[vn.key] = true end
                                    if not vn.is_ghost_voice then is_ghost_tuplet = false end
                                end
                            end

                            local first_o = onsets[bi]
                            local last_o = onsets[bi + n - 1]
                            local x1 = first_o.beam_stem_x or first_o.nominal_nx
                            local x2 = last_o.beam_stem_x or last_o.nominal_nx
                            if not (cull_max_x and x1 > cull_max_x) and not (cull_min_x and x2 < cull_min_x) then
                                local cx = (x1 + x2) / 2.0
                                local y1 = first_o.beam_stem_end_y
                                local y2 = last_o.beam_stem_end_y
                                local cy_beam = (y1 and y2) and ((y1 + y2) / 2.0) or first_o.notes[1].vis_ny
                                local stem_down = first_o.beam_stem_down
                                local cy = stem_down and (cy_beam + 10 * s) or (cy_beam - 10 * s)

                                local digit_col = is_ghost_tuplet and (ghost_col or 0x88888835) or col
                                draw_tuplet_digit(draw_list, cx, cy, n, s, digit_col, font_music, font_main)
                            end

                            bi = bi + n
                            b_matched = true
                            break
                        end
                    end
                end
                if not b_matched then
                    bi = bi + 1
                end
            end
        end
    end

    -- --------------------------------------------------------------------------
    -- PASS 2: UNBEAMED TUPLETS (QUARTER-NOTE TRIPLETS ETC. - WITH BRACKET [ N ])
    -- BEAMED NOTES ARE STRICTLY EXCLUDED HERE!
    -- --------------------------------------------------------------------------
    local onsets_by_staff = {}
    local staff_list = {}
    local function get_or_create_onset_list(st)
        if not onsets_by_staff[st] then
            onsets_by_staff[st] = {}
            table.insert(staff_list, st)
        end
        return onsets_by_staff[st]
    end

    local function add_to_onset_list(list, vn)
        local last = list[#list]
        if last and math.abs(vn.start_qn - last.start_qn) < 0.02 then
            table.insert(last.notes, vn)
            if vn.vis_ny < last.min_ny then last.min_ny = vn.vis_ny end
            if vn.vis_ny > last.max_ny then last.max_ny = vn.vis_ny end
        else
            table.insert(list, {
                start_qn = vn.start_qn,
                dur_qn = vn.dur_qn,
                notes = { vn },
                nominal_nx = vn.nominal_nx or vn.vis_nx,
                min_ny = vn.vis_ny,
                max_ny = vn.vis_ny,
                in_treble = vn.in_treble,
                in_staff = vn.in_staff
            })
        end
    end

    for _, vn in ipairs(visual_notes) do
        if not (vn.key and (handled_note_keys[vn.key] or beamed_note_keys[vn.key])) then
            local st = vn.in_staff or (vn.in_treble and "treble" or "bass")
            add_to_onset_list(get_or_create_onset_list(st), vn)
        end
    end

    local function scan_and_draw_unbeamed(onset_list)
        local i = 1
        local num_o = #onset_list
        while i <= num_o do
            local matched = false
            for _, n in ipairs({ 8, 7, 6, 5, 3 }) do
                if i + n - 1 <= num_o then
                    local ok, step = is_valid_tuplet(onset_list, i, n, qn_per_measure)
                    if ok then
                        local first_o = onset_list[i]
                        local last_o = onset_list[i + n - 1]
                        local x1 = first_o.nominal_nx - 4 * s
                        local x2 = last_o.nominal_nx + 4 * s
                        local dx = math.max(1.0, x2 - x1)
                        local cx = (x1 + x2) / 2.0

                        if not (cull_max_x and x1 > cull_max_x) and not (cull_min_x and x2 < cull_min_x) then
                            -- Helper function: determines highest optical point of an onset
                            local function get_onset_top(o)
                                local top_y = o.min_ny
                                for _, vn in ipairs(o.notes) do
                                    if vn.stem_end_y and not vn.stem_down then
                                        if vn.stem_end_y < top_y then top_y = vn.stem_end_y end
                                    elseif not vn.stem_end_y then
                                        local est = vn.vis_ny - 32 * s
                                        if est < top_y then top_y = est end
                                    end
                                end
                                return top_y
                            end

                            local y_first_top = get_onset_top(first_o)
                            local y_last_top  = get_onset_top(last_o)

                            -- Slant (slope) following note contour (Gardner Read / Gould engraving standard)
                            local raw_slope = (y_last_top - y_first_top) / dx
                            local slope = math.max(-0.25, math.min(0.25, raw_slope))

                            -- If direction changes (convex/concave) -> horizontal
                            local has_higher, has_lower = false, false
                            for idx = i + 1, i + n - 2 do
                                local mid_top = get_onset_top(onset_list[idx])
                                if mid_top < math.min(y_first_top, y_last_top) - 2 * s then has_higher = true end
                                if mid_top > math.max(y_first_top, y_last_top) + 2 * s then has_lower = true end
                            end
                            if has_higher and has_lower then slope = 0 end

                            -- Calculate y1 ensuring at least clearance (12*s) distance at each onset
                            local clearance = 12 * s
                            local y1 = y_first_top - clearance
                            for idx = i, i + n - 1 do
                                local o = onset_list[idx]
                                local top_k = get_onset_top(o)
                                local ox = o.nominal_nx
                                local req_y1 = (top_k - clearance) - slope * (ox - x1)
                                if req_y1 < y1 then
                                    y1 = req_y1
                                end
                            end

                            local y2 = y1 + slope * (x2 - x1)
                            local cy = (y1 + y2) / 2.0

                            local is_ghost_tuplet = true
                            for k = 0, n - 1 do
                                for _, vn in ipairs(onset_list[i + k].notes) do
                                    if not vn.is_ghost_voice then is_ghost_tuplet = false break end
                                end
                            end
                            local hook_len = 6 * s
                            local gap_half = 9 * s
                            local line_w = 1.4 * s
                            local bracket_col = is_ghost_tuplet and (ghost_col or 0x88888835) or (col or 0x111111FF)

                            local gx1 = cx - gap_half
                            local gy1 = y1 + slope * (gx1 - x1)

                            local gx2 = cx + gap_half
                            local gy2 = y1 + slope * (gx2 - x1)

                            -- Left bracket segment + hook
                            reaper.ImGui_DrawList_AddLine(draw_list, x1, y1, gx1, gy1, bracket_col, line_w)
                            reaper.ImGui_DrawList_AddLine(draw_list, x1, y1, x1, y1 + hook_len, bracket_col, line_w)

                            -- Right bracket segment + hook
                            reaper.ImGui_DrawList_AddLine(draw_list, gx2, gy2, x2, y2, bracket_col, line_w)
                            reaper.ImGui_DrawList_AddLine(draw_list, x2, y2, x2, y2 + hook_len, bracket_col, line_w)

                            -- Centered numeral in bracket gap
                            draw_tuplet_digit(draw_list, cx, cy, n, s, bracket_col, font_music, font_main)
                        end

                        i = i + n
                        matched = true
                        break
                    end
                end
            end
            if not matched then
                i = i + 1
            end
        end
    end

    for _, st in ipairs(staff_list) do
        scan_and_draw_unbeamed(onsets_by_staff[st])
    end
end

return Engraver

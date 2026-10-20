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
    elseif raw_dur >= 3.35 then
        return 3.5
    elseif raw_dur >= 2.75 then
        return 3.0
    elseif raw_dur >= 2.35 then
        return 2.5
    elseif raw_dur >= 1.85 then
        return 2.0
    elseif raw_dur >= 1.62 then
        return 1.75
    elseif raw_dur >= 1.35 then
        return 1.5
    elseif raw_dur >= 1.12 then
        return 1.25
    elseif raw_dur >= 0.85 then
        return 1.0
    elseif raw_dur >= 0.62 then
        return 0.75
    elseif raw_dur >= 0.43 then
        return 0.5
    elseif raw_dur >= 0.31 then
        return 0.375
    elseif raw_dur >= 0.21 then
        return 0.25
    elseif raw_dur >= 0.155 then
        return 0.1875
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

function Engraver.qn_to_measure_info(qn, bpi, measure_map)
    local q = math.max(0.0, tonumber(qn) or 0.0)
    if measure_map and measure_map.m_start_qn and measure_map.m_end_qn and measure_map.m_bpi then
        local m_start = measure_map.m_start_qn
        local m_end   = measure_map.m_end_qn
        local m_bpi   = measure_map.m_bpi
        local m_num   = measure_map.m_ts_num
        local m_den   = measure_map.m_ts_den
        local max_m   = measure_map.num_m or #m_start
        for m = 0, max_m do
            if m_start[m] and m_end[m] and q + 0.0005 >= m_start[m] and q + 0.0005 < m_end[m] then
                return m, m_start[m], m_bpi[m], m_num and m_num[m], m_den and m_den[m]
            end
        end
        local last_m   = max_m
        local last_sqn = m_start[last_m] or 0.0
        local last_bpi = m_bpi[last_m] or (measure_map.bpi or 4.0)
        local extra_m  = math.floor(math.max(0.0, q - last_sqn + 0.0005) / last_bpi)
        local res_m    = last_m + extra_m
        return res_m, last_sqn + extra_m * last_bpi, last_bpi, m_num and m_num[last_m], m_den and m_den[last_m]
    end
    local eff_bpi = (measure_map and measure_map.bpi) or ((bpi and bpi > 0) and bpi or 4.0)
    local m = math.max(0, math.floor((q + 0.0005) / eff_bpi))
    return m, m * eff_bpi, eff_bpi, nil, nil
end

function Engraver.measure_to_qn_info(m, bpi, measure_map)
    local m_idx = math.max(0, math.floor(tonumber(m) or 0))
    if measure_map and measure_map.m_start_qn and measure_map.m_bpi then
        local m_start = measure_map.m_start_qn
        local m_end   = measure_map.m_end_qn
        local m_bpi   = measure_map.m_bpi
        local m_num   = measure_map.m_ts_num
        local m_den   = measure_map.m_ts_den
        if m_start[m_idx] and m_bpi[m_idx] then
            local sqn = m_start[m_idx]
            local mb  = m_bpi[m_idx]
            local eqn = (m_end and m_end[m_idx]) or (sqn + mb)
            return sqn, eqn, mb, m_num and m_num[m_idx], m_den and m_den[m_idx]
        end
        local last_m   = measure_map.num_m or #m_start
        local last_sqn = m_start[last_m] or 0.0
        local last_bpi = m_bpi[last_m] or (measure_map.bpi or 4.0)
        local extra_m  = math.max(0, m_idx - last_m)
        local sqn      = last_sqn + extra_m * last_bpi
        return sqn, sqn + last_bpi, last_bpi, m_num and m_num[last_m], m_den and m_den[last_m]
    end
    local eff_bpi = (measure_map and measure_map.bpi) or ((bpi and bpi > 0) and bpi or 4.0)
    return m_idx * eff_bpi, (m_idx + 1) * eff_bpi, eff_bpi, nil, nil
end

function Engraver.build_measure_map(active_tracks_data, total_measures, qn_per_measure, margin_left, s, state)
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0
    local base_w = 260.0 * s * (bpi / 4.0)
    local pad_left = 30.0 * s
    local pad_right = 25.0 * s
    
    local widths = {}
    local pad_lefts = {}
    local onsets_by_bar = {}
    local bar_anchors = {}
    local num_m = math.max((total_measures or 16) + 64, 64)
    
    local has_kss, KeySignatureService = pcall(require, "services.key_signature_service")
    if not has_kss or not KeySignatureService then
        has_kss, KeySignatureService = pcall(require, "modules.services.key_signature_service")
    end

    local tmap = nil
    if has_kss and KeySignatureService and KeySignatureService.get_measure_time_map then
        tmap = KeySignatureService.get_measure_time_map(state, num_m, bpi, s)
    end
    local m_start_qn   = (tmap and tmap.m_start_qn) or {}
    local m_end_qn     = (tmap and tmap.m_end_qn) or {}
    local m_bpi        = (tmap and tmap.m_bpi) or {}
    local m_ts_num     = (tmap and tmap.m_ts_num) or {}
    local m_ts_den     = (tmap and tmap.m_ts_den) or {}
    local time_changes = (tmap and tmap.time_changes) or {}
    if not tmap then
        for m = 0, num_m + 1 do
            m_start_qn[m] = m * bpi
            m_end_qn[m]   = (m + 1) * bpi
            m_bpi[m]      = bpi
            m_ts_num[m]   = 4
            m_ts_den[m]   = 4
        end
    end
    if m_bpi[0] and m_bpi[0] > 0 then
        bpi = m_bpi[0]
        base_w = 260.0 * s * (bpi / 4.0)
    end

    local time_map_ref = {
        bpi          = bpi,
        num_m        = num_m,
        m_start_qn   = m_start_qn,
        m_end_qn     = m_end_qn,
        m_bpi        = m_bpi,
        m_ts_num     = m_ts_num,
        m_ts_den     = m_ts_den,
        time_changes = time_changes
    }

    local key_changes = nil
    if has_kss and KeySignatureService and KeySignatureService.get_measure_key_signature_changes then
        key_changes = KeySignatureService.get_measure_key_signature_changes(state, active_tracks_data, num_m, bpi, s)
    end
    
    local dq = (state and state.display_quantize and state.display_quantize_grid and state.display_quantize_grid > 0.001) and state.display_quantize_grid or nil

    -- Decompose visual notes (including intra-bar tied sub-segments) & rests per track
    local track_vnotes_by_bar = {}
    local track_rests_by_bar = {}
    local user_ties = state and state.user_ties
    local max_map_qn = m_end_qn[num_m + 1] or ((num_m + 1) * bpi)

    for _, tdata in ipairs(active_tracks_data or {}) do
        local vnotes = Engraver.get_visual_notes(tdata.notes or {}, bpi, nil, max_map_qn, user_ties, time_map_ref)
        local vnotes_by_bar = {}
        track_vnotes_by_bar[tdata] = vnotes_by_bar

        local eff_notes = {}
        local eff_notes_by_bar = {}
        for _, vn in ipairs(vnotes) do
            local m = vn.bar or Engraver.qn_to_measure_info(vn.start_qn + 0.0001, bpi, time_map_ref)
            if m >= 0 and m <= num_m then
                local blist = vnotes_by_bar[m]
                if not blist then
                    blist = {}
                    vnotes_by_bar[m] = blist
                end
                table.insert(blist, vn)
            end

            local n_sqn = dq and (math.floor((vn.start_qn / dq) + 0.5) * dq) or vn.start_qn
            local n_dur = vn.dur_qn or 1.0
            local en = {
                pitch = vn.pitch,
                start_qn = n_sqn,
                end_qn = n_sqn + n_dur,
                dur_qn = n_dur,
                chan = (vn.orig and vn.orig.chan) or (vn.chan or 0)
            }
            table.insert(eff_notes, en)
            local mb_start = Engraver.qn_to_measure_info(en.start_qn, bpi, time_map_ref)
            local mb_end = Engraver.qn_to_measure_info(math.max(en.start_qn, en.end_qn - 0.001), bpi, time_map_ref)
            for mb = mb_start, mb_end do
                local eblist = eff_notes_by_bar[mb]
                if not eblist then
                    eblist = {}
                    eff_notes_by_bar[mb] = eblist
                end
                table.insert(eblist, en)
            end
        end

        local tc_cnt = 0
        for _ in pairs(time_changes) do tc_cnt = tc_cnt + 1 end
        local r_key = string.format("v2_%d_%.3f_%d_%s_%d", num_m + 1, bpi, tc_cnt, tostring(dq), #vnotes)
        local r_cache = tdata.rests_cache
        local tr_rests = r_cache and r_cache[r_key]
        if not tr_rests then
            tr_rests = Engraver.generate_voice_rests(eff_notes, num_m + 1, bpi, dq, nil, nil, time_map_ref)
            if r_cache then
                r_cache[r_key] = tr_rests
            end
        end

        local rests_by_bar = {}
        track_rests_by_bar[tdata] = rests_by_bar
        if tr_rests and #tr_rests > 0 then
            for _, r in ipairs(tr_rests) do
                if not r.is_full_measure then
                    local m = r.measure_idx or Engraver.qn_to_measure_info(r.start_qn + 0.0001, bpi, time_map_ref)
                    if m >= 0 and m <= num_m then
                        local r_start = r.start_qn
                        local r_end = r_start + (r.dur_qn or 0.25)
                        local collision = false
                        local bar_ens = eff_notes_by_bar[m]
                        if bar_ens then
                            local tol = dq and (dq * 0.3) or 0.05
                            local onset_tol = dq and (dq * 0.7) or 0.20
                            for _, en in ipairs(bar_ens) do
                                if not (r_end <= en.start_qn + tol or r_start >= en.end_qn - tol) or math.abs(en.start_qn - r_start) < onset_tol then
                                    collision = true
                                    break
                                end
                            end
                        end
                        if not collision then
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
    end

    -- For each measure from 0 to num_m: build Elaine Gould optical spacing anchors & dynamic measure width
    for m = 0, num_m do
        local m_sqn = m_start_qn[m] or (m * bpi)
        local mb = m_bpi[m] or bpi
        local m_base_w = 260.0 * s * (mb / 4.0)
        local base_pad_l = pad_left
        if key_changes and key_changes[m] and key_changes[m].has_change then
            local extra_kw = (key_changes[m].max_kw or 0) + 12.0 * s
            base_pad_l = base_pad_l + extra_kw
        end
        if m > 0 and time_changes and time_changes[m] then
            local extra_tw = (time_changes[m].width or (24.0 * s)) + 8.0 * s
            base_pad_l = base_pad_l + extra_tw
        end
        local m_pad_l = base_pad_l

        local m_combined_onsets = { [0.0] = true, [mb] = true }
        local measure_track_onsets = {}

        for _, tdata in ipairs(active_tracks_data or {}) do
            local onsets = {}
            local bar_vnotes = track_vnotes_by_bar[tdata] and track_vnotes_by_bar[tdata][m]
            local seen_pitch_in_bar = {}

            if bar_vnotes then
                for _, vn in ipairs(bar_vnotes) do
                    local raw_rel = math.max(0.0, math.min(mb - 0.03125, vn.start_qn - m_sqn))
                    local rel_qn = math.floor(raw_rel * 32.0 + 0.5) / 32.0
                    m_combined_onsets[rel_qn] = true
                    local o = onsets[rel_qn]
                    if not o then
                        o = {
                            rel_qn = rel_qn,
                            qn = m_sqn + rel_qn,
                            acc_count = 0,
                            has_dot = false,
                            has_arpeggio = false,
                            max_flags = 0,
                            is_tied_to_next = false,
                            note_count = 0,
                            is_rest = false
                        }
                        onsets[rel_qn] = o
                    else
                        o.is_rest = false
                    end
                    o.note_count = o.note_count + 1

                    local orig = vn.orig or vn
                    if orig and (orig.arpeggio or orig.articulation == "arpeggio") then
                        o.has_arpeggio = true
                    end

                    -- Accidental estimation respecting tied segments and intra-bar pitch memory
                    if not vn.is_tied_from_prev and (not vn.is_segment or vn.seg_idx == 1) then
                        local k = orig and (orig.key or (orig.get_key and orig:get_key()))
                        local pref_acc = k and state and state.note_accidentals and state.note_accidentals[k]
                        if pref_acc == nil and state and state.note_accidentals and orig and orig.take then
                            local id_k = string.format("%s_%s_%.3f", tostring(orig.take or "0"), tostring(orig.idx), orig.start_qn or vn.start_qn)
                            pref_acc = state.note_accidentals[id_k]
                        end
                        local p_mod = (vn.pitch or 60) % 12
                        local is_black = (p_mod == 1 or p_mod == 3 or p_mod == 6 or p_mod == 8 or p_mod == 10)
                        local oct_step = math.floor((vn.pitch or 60) / 12) * 7 + (Constants.PITCH_MAP[p_mod] and Constants.PITCH_MAP[p_mod].step or 0)
                        local prev_alt = seen_pitch_in_bar[oct_step]
                        local cur_alt = is_black and 1 or 0
                        if pref_acc == 1 or pref_acc == -1 or pref_acc == 2 then
                            o.acc_count = o.acc_count + 1
                            seen_pitch_in_bar[oct_step] = (pref_acc == 2) and 0 or pref_acc
                        elseif prev_alt ~= nil and prev_alt ~= cur_alt then
                            o.acc_count = o.acc_count + 1
                            seen_pitch_in_bar[oct_step] = cur_alt
                        elseif prev_alt == nil and is_black then
                            o.acc_count = o.acc_count + 1
                            seen_pitch_in_bar[oct_step] = cur_alt
                        end
                    end

                    if Engraver.is_dotted_duration(vn.dur_qn) then
                        o.has_dot = true
                    end
                    local fc = Engraver.get_flag_count(vn.dur_qn)
                    if fc > o.max_flags then
                        o.max_flags = fc
                    end
                    if vn.is_tied_to_next then
                        o.is_tied_to_next = true
                    end
                end
            end

            local bar_rests = track_rests_by_bar[tdata] and track_rests_by_bar[tdata][m]
            if bar_rests then
                for _, r in ipairs(bar_rests) do
                    local raw_rel = math.max(0.0, math.min(mb - 0.03125, r.start_qn - m_sqn))
                    local rel_qn = math.floor(raw_rel * 32.0 + 0.5) / 32.0
                    m_combined_onsets[rel_qn] = true
                    if not onsets[rel_qn] then
                        onsets[rel_qn] = {
                            rel_qn = rel_qn,
                            qn = m_sqn + rel_qn,
                            acc_count = 0,
                            has_dot = false,
                            has_arpeggio = false,
                            max_flags = 0,
                            is_tied_to_next = false,
                            note_count = 1,
                            is_rest = true,
                            rest_type = r.type
                        }
                    end
                end
            end

            local sorted_onsets = {}
            for _, o in pairs(onsets) do
                -- Compute exact graphical left & right extents per Elaine Gould ("Behind Bars" pp. 39-43)
                if o.is_rest then
                    local is_short_rest = (o.rest_type == "16th" or o.rest_type == "32nd" or o.rest_type == "64th")
                    o.left_ext  = (is_short_rest and 8.5 or 7.5) * s
                    o.right_ext = (is_short_rest and 9.0 or 8.0) * s
                else
                    o.left_ext  = 6.5 * s
                    o.right_ext = 6.5 * s
                    if o.note_count > 1 then
                        o.left_ext  = o.left_ext + 5.0 * s
                        o.right_ext = o.right_ext + 6.0 * s
                    end
                    if o.acc_count > 0 then
                        local acc_cols = math.min(3, o.acc_count)
                        o.left_ext = o.left_ext + (acc_cols * 12.5 * s) + 3.5 * s
                    end
                    if o.has_arpeggio then
                        o.left_ext = o.left_ext + 12.0 * s
                    end
                    if o.has_dot then
                        o.right_ext = o.right_ext + 10.5 * s
                    end
                    if o.max_flags > 0 then
                        o.right_ext = o.right_ext + 6.0 * s
                    end
                    if o.is_tied_to_next then
                        o.right_ext = math.max(o.right_ext, 14.0 * s)
                    end
                end
                table.insert(sorted_onsets, o)
            end
            table.sort(sorted_onsets, function(a, b) return a.rel_qn < b.rel_qn end)
            if #sorted_onsets > 0 then
                table.insert(measure_track_onsets, sorted_onsets)
            end
        end

        local anchor_qns = {}
        for o_qn in pairs(m_combined_onsets) do
            table.insert(anchor_qns, o_qn)
        end
        table.sort(anchor_qns)

        local sorted_bar_onsets = {}
        for _, o_qn in ipairs(anchor_qns) do
            if o_qn < mb - 0.001 then
                table.insert(sorted_bar_onsets, o_qn)
            end
        end
        onsets_by_bar[m] = sorted_bar_onsets

        local K = #anchor_qns
        local base_usable_w = math.max(40.0 * s, m_base_w - pad_left - pad_right)

        if K > 2 and #measure_track_onsets > 0 then
            local qn_to_idx = {}
            for k, qv in ipairs(anchor_qns) do
                qn_to_idx[qv] = k
            end

            -- Step 1: Elaine Gould non-linear proportional base weights (delta_t ^ 0.70)
            local weights = {}
            local sum_w = 0.0
            for k = 1, K - 1 do
                local dt = math.max(0.03125, anchor_qns[k + 1] - anchor_qns[k])
                local w = dt ^ 0.70
                weights[k] = w
                sum_w = sum_w + w
            end

            local seg_w = {}
            for k = 1, K - 1 do
                local dt = math.max(0.03125, anchor_qns[k + 1] - anchor_qns[k])
                local prop_w = (sum_w > 0) and (base_usable_w * (weights[k] / sum_w)) or ((dt / mb) * base_usable_w)
                local min_lin_w = (dt / mb) * base_usable_w * 0.82
                seg_w[k] = math.max(prop_w, min_lin_w)
            end

            -- Step 2: Pairwise collision-free clearance satisfaction across all active tracks
            local optical_gap = 7.5 * s
            for _, trk_onsets in ipairs(measure_track_onsets) do
                local first_o = trk_onsets[1]
                if first_o.rel_qn <= 0.001 then
                    if first_o.left_ext > 11.0 * s then
                        local extra_pad = first_o.left_ext - 11.0 * s
                        if m_pad_l < base_pad_l + extra_pad then
                            m_pad_l = base_pad_l + extra_pad
                        end
                    end
                else
                    local idx1 = qn_to_idx[first_o.rel_qn]
                    if idx1 and idx1 > 1 then
                        local cur_lead = 0.0
                        for k = 1, idx1 - 1 do cur_lead = cur_lead + seg_w[k] end
                        local req_lead = first_o.left_ext + 4.0 * s
                        if cur_lead < req_lead then
                            local sf = req_lead / math.max(1.0, cur_lead)
                            for k = 1, idx1 - 1 do seg_w[k] = seg_w[k] * sf end
                        end
                    end
                end

                for r = 1, #trk_onsets - 1 do
                    local oa = trk_onsets[r]
                    local ob = trk_onsets[r + 1]
                    local ia = qn_to_idx[oa.rel_qn]
                    local ib = qn_to_idx[ob.rel_qn]
                    if ia and ib and ib > ia then
                        local req_dx = oa.right_ext + ob.left_ext + optical_gap
                        if oa.is_tied_to_next then
                            req_dx = math.max(req_dx, 26.0 * s)
                        end
                        local cur_dx = 0.0
                        for k = ia, ib - 1 do
                            cur_dx = cur_dx + seg_w[k]
                        end
                        if cur_dx < req_dx then
                            local sf = req_dx / math.max(1.0, cur_dx)
                            for k = ia, ib - 1 do
                                seg_w[k] = seg_w[k] * sf
                            end
                        end
                    end
                end

                local last_o = trk_onsets[#trk_onsets]
                local ilast = qn_to_idx[last_o.rel_qn]
                if ilast and ilast < K then
                    local req_tail = last_o.right_ext + (last_o.is_tied_to_next and 14.0 * s or 8.0 * s)
                    local cur_tail = 0.0
                    for k = ilast, K - 1 do
                        cur_tail = cur_tail + seg_w[k]
                    end
                    if cur_tail < req_tail then
                        local sf = req_tail / math.max(1.0, cur_tail)
                        for k = ilast, K - 1 do
                            seg_w[k] = seg_w[k] * sf
                        end
                    end
                end
            end

            local total_usable_w = 0.0
            for k = 1, K - 1 do
                total_usable_w = total_usable_w + seg_w[k]
            end
            if total_usable_w < base_usable_w and total_usable_w > 0 then
                local scale_up = base_usable_w / total_usable_w
                for k = 1, K - 1 do
                    seg_w[k] = seg_w[k] * scale_up
                end
                total_usable_w = base_usable_w
            end

            local anchor_xs = { [1] = 0.0 }
            for k = 1, K - 1 do
                anchor_xs[k + 1] = anchor_xs[k] + seg_w[k]
            end
            bar_anchors[m] = {
                qns = anchor_qns,
                xs = anchor_xs,
                usable_w = total_usable_w
            }
            pad_lefts[m] = m_pad_l
            widths[m] = math.max(m_base_w, m_pad_l + total_usable_w + pad_right)
        else
            -- Check single beat-1 onset accidental padding even when K == 2
            for _, trk_onsets in ipairs(measure_track_onsets) do
                local first_o = trk_onsets[1]
                if first_o and first_o.rel_qn <= 0.001 and first_o.left_ext > 11.0 * s then
                    local extra_pad = first_o.left_ext - 11.0 * s
                    if m_pad_l < base_pad_l + extra_pad then
                        m_pad_l = base_pad_l + extra_pad
                    end
                end
            end
            pad_lefts[m] = m_pad_l
            widths[m] = math.max(m_base_w, m_pad_l + base_usable_w + pad_right)
        end
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
        bar_anchors = bar_anchors,
        key_changes = key_changes,
        time_changes = time_changes,
        m_start_qn = m_start_qn,
        m_end_qn = m_end_qn,
        m_bpi = m_bpi,
        m_ts_num = m_ts_num,
        m_ts_den = m_ts_den
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
    local m_idx, m_sqn, mb = Engraver.qn_to_measure_info(qn, bpi, measure_map)
    local qn_in_m = math.max(0.0, qn - m_sqn)
    
    if not measure_map or not measure_map.starts then
        local measure_w, pad_left, pad_right, usable_w = Engraver.get_measure_layout(s, mb)
        local m_x = margin_left + (m_idx * measure_w)
        return m_x + pad_left + (qn_in_m / mb) * usable_w
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
    local pad_r = measure_map.pad_right or (25.0 * s)
    local usable_w = math.max(10.0 * s, m_w - pad_l - pad_r)
    
    -- Use Elaine Gould optical anchor interpolation when available for this measure
    local anchors = measure_map.bar_anchors and measure_map.bar_anchors[m_idx]
    if anchors and anchors.qns and anchors.xs and #anchors.qns >= 2 then
        local qns = anchors.qns
        local xs = anchors.xs
        local n_pts = #qns
        if qn_in_m <= qns[1] then
            return m_start_x + pad_l + xs[1]
        elseif qn_in_m >= qns[n_pts] then
            return m_start_x + pad_l + xs[n_pts]
        else
            for k = 1, n_pts - 1 do
                local q0, q1 = qns[k], qns[k + 1]
                if qn_in_m >= q0 and qn_in_m <= q1 then
                    local dq_seg = q1 - q0
                    local t = (dq_seg > 0.0001) and ((qn_in_m - q0) / dq_seg) or 0.0
                    return m_start_x + pad_l + xs[k] + t * (xs[k + 1] - xs[k])
                end
            end
        end
    end
    
    return m_start_x + pad_l + (qn_in_m / mb) * usable_w
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
    local m_idx, m_sqn, mb = Engraver.qn_to_measure_info(qn, bpi, measure_map)
    local qn_in_m = math.max(0.0, qn - m_sqn)
    
    local m_start_x = measure_map.starts[m_idx]
    local m_w = measure_map.widths[m_idx]
    if not m_start_x then
        local last_idx = measure_map.num_m or (#measure_map.starts - 1)
        m_start_x = (measure_map.starts[last_idx] or margin_left) + (m_idx - last_idx) * measure_map.base_w
        m_w = measure_map.base_w
    end
    m_w = m_w or measure_map.base_w
    
    return m_start_x + (qn_in_m / mb) * m_w
end

function Engraver.canvas_x_to_qn(x, margin_left, s, qn_per_measure, grid_qn, measure_map)
    local bpi = (measure_map and measure_map.bpi) or ((qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4)
    local snap = (grid_qn and grid_qn > 0) and grid_qn or 0.25
    
    local function calc_measure_qn(m_idx, m_start_x, m_w, cur_x, pad_l, pad_r)
        local m_sqn, _, mb = Engraver.measure_to_qn_info(m_idx, bpi, measure_map)
        local eff_pad_l = (measure_map and measure_map.pad_lefts and measure_map.pad_lefts[m_idx]) or pad_l
        local usable_w = math.max(10.0 * s, m_w - eff_pad_l - pad_r)
        local rel_x = cur_x - m_start_x
        local raw_qn_in_m
        if rel_x <= eff_pad_l then
            raw_qn_in_m = 0.0
        elseif rel_x >= eff_pad_l + usable_w then
            raw_qn_in_m = mb - 0.0001
        else
            local ux = rel_x - eff_pad_l
            local anchors = measure_map and measure_map.bar_anchors and measure_map.bar_anchors[m_idx]
            if anchors and anchors.qns and anchors.xs and #anchors.xs >= 2 then
                local qns = anchors.qns
                local xs = anchors.xs
                local n_pts = #xs
                if ux <= xs[1] then
                    raw_qn_in_m = qns[1]
                elseif ux >= xs[n_pts] then
                    raw_qn_in_m = qns[n_pts] - 0.0001
                else
                    raw_qn_in_m = (ux / usable_w) * mb
                    for k = 1, n_pts - 1 do
                        local x0, x1 = xs[k], xs[k + 1]
                        if ux >= x0 and ux <= x1 then
                            local dx_seg = x1 - x0
                            local t = (dx_seg > 0.0001) and ((ux - x0) / dx_seg) or 0.0
                            raw_qn_in_m = qns[k] + t * (qns[k + 1] - qns[k])
                            break
                        end
                    end
                end
            else
                raw_qn_in_m = (ux / usable_w) * mb
            end
        end
        local snapped = math.floor((raw_qn_in_m / snap) + 0.5) * snap
        local max_snap = (snap <= mb) and (mb - snap) or 0.0
        snapped = math.max(0.0, math.min(max_snap, snapped))
        return m_sqn + snapped
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

function Engraver.is_percussion_instrument_name(track_name)
    if type(track_name) ~= "string" or track_name == "" then
        return false
    end
    local name_l = track_name:lower()

    -- 1. Exclude pitched kettle drums (Timpani / Pauken -> Bass Clef)
    if name_l:find("timpani") or name_l:find("pauke") or name_l:find("pauken") or name_l:match("%f[%a]timp%f[%A]") then
        return false
    end

    -- 2. Exclude pitched mallet & tuned percussion (Xylophone, Marimba, Vibraphone, Glockenspiel, Celesta, Chimes, etc.)
    if name_l:find("xylophon") or name_l:find("marimba") or name_l:find("vibraphon") or name_l:match("%f[%a]vibes%f[%A]") or
       name_l:find("glockenspiel") or name_l:find("celesta") or name_l:find("crotales") or
       name_l:find("tubular bell") or name_l:match("%f[%a]chimes%f[%A]") or name_l:find("campanelli") or name_l:find("carillon") or
       name_l:find("kalimba") or name_l:find("mbira") or name_l:find("mallet") or
       name_l:find("pitched perc") or name_l:find("tuned perc") or
       name_l:find("steel drum") or name_l:find("steeldrum") or name_l:find("steel pan") or
       name_l:find("handpan") or name_l:find("hang drum") or name_l:find("tongue drum") then
        return false
    end

    -- 3. True unpitched drums, snares, drumkits, toms, world drums, cymbals & auxiliary percussion
    if name_l:match("%f[%a]snares?%f[%A]") or name_l:find("snaredrum") or name_l:find("kleine trommel") or
       name_l:find("side stick") or name_l:find("sidestick") or name_l:find("rimshot") or
       name_l:find("bass drum") or name_l:find("bassdrum") or name_l:find("gran cassa") or
       name_l:find("große trommel") or name_l:find("grosse trommel") or
       name_l:find("kick drum") or name_l:find("kickdrum") or name_l:match("%f[%a]kick%f[%A]") or
       name_l:match("%f[%a]drums?%f[%A]") or name_l:find("drumkit") or name_l:find("drumset") or
       name_l:find("framedrum") or name_l:find("bodhran") or
       name_l:find("schlagzeug") or name_l:find("schlagwerk") or
       name_l:match("%f[%a]trommeln?%f[%A]") or
       name_l:match("%f[%a]toms?%f[%A]") or name_l:find("rototom") or name_l:find("taiko") or name_l:find("surdo") or name_l:find("timbale") or
       name_l:find("bongo") or name_l:find("conga") or name_l:find("djembe") or name_l:find("cajon") or name_l:find("darbuka") or name_l:find("doumbek") or
       name_l:find("tambourin") or name_l:find("tamburin") or name_l:find("pandeiro") or
       name_l:find("cymbal") or name_l:find("becken") or name_l:find("piatti") or
       name_l:find("hi-hat", 1, true) or name_l:find("hihat") or name_l:match("%f[%a]hi%s+hat%f[%A]") or
       name_l:find("tam-tam", 1, true) or name_l:find("tamtam") or name_l:match("%f[%a]gong%f[%A]") or
       name_l:find("cowbell") or name_l:find("agogo") or name_l:find("anvil") or
       name_l:find("woodblock") or name_l:find("wood block") or name_l:find("holzblock") or name_l:find("temple block") or
       name_l:find("claves") or name_l:find("castanet") or name_l:find("kastagnetten") or
       name_l:find("maracas") or name_l:find("cabasa") or name_l:find("guiro") or name_l:match("%f[%a]shakers?%f[%A]") or
       name_l:find("vibraslap") or name_l:find("slapstick") or name_l:find("peitsche") or name_l:find("ratchet") or
       name_l:find("percussion") or name_l:match("%f[%a]perc%f[%A]") then
        return true
    end

    if (name_l:find("triangle") or name_l:find("triangel")) and
       not (name_l:find("synth") or name_l:find("wave") or name_l:find("osc") or name_l:find("lead") or name_l:find("pad")) then
        return true
    end

    return false
end

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
            return (saved == "percussion") and "percussion_1" or saved
        end
    end

    if state and state.view_mode and state.view_mode ~= "auto" and (state.view_mode == "treble" or state.view_mode == "bass" or state.view_mode == "grand" or state.view_mode == "alto" or state.view_mode == "percussion_1" or state.view_mode == "percussion_2" or state.view_mode == "percussion") then
        return (state.view_mode == "percussion") and "percussion_1" or state.view_mode
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

    -- 4. Pitched kettle drums (Timpani / Pauken -> Bass Clef) & pitched mallet percussion (-> Treble Clef)
    if name_l:find("timpani") or name_l:find("pauke") or name_l:find("pauken") or name_l:match("%f[%a]timp%f[%A]") then
        return "bass"
    end
    if name_l:find("xylophon") or name_l:find("marimba") or name_l:find("vibraphon") or name_l:match("%f[%a]vibes%f[%A]") or
       name_l:find("glockenspiel") or name_l:find("crotales") or name_l:find("tubular bell") or name_l:match("%f[%a]chimes%f[%A]") or
       name_l:find("campanelli") or name_l:find("carillon") or name_l:find("kalimba") or name_l:find("mbira") or
       name_l:find("mallet") or name_l:find("pitched perc") or name_l:find("tuned perc") or
       name_l:find("steel drum") or name_l:find("steeldrum") or name_l:find("steel pan") or
       name_l:find("handpan") or name_l:find("hang drum") or name_l:find("tongue drum") then
        return "treble"
    end

    -- 5. True unpitched percussion instruments (snares, drums, drumset, bass drum, toms, cymbals, etc.)
    if Engraver.is_percussion_instrument_name(name_l) then
        return "percussion_1"
    end

    -- 6. Explicit bass instruments (cellos, double bass, tuba, bassoon, trombone, euphonium, etc.)
    if name_l:find("cell") or name_l:find("violoncell") or name_l:match("%f[%a]vc%f[%A]") or name_l:match("%f[%a]vlc%f[%A]") or
       name_l:find("bass") or name_l:find("kontra") or name_l:find("contra") or name_l:match("%f[%a]cb%f[%A]") or name_l:match("%f[%a]kb%f[%A]") or name_l:match("%f[%a]db%f[%A]") or
       name_l:find("tuba") or name_l:find("fagott") or name_l:find("bassoon") or name_l:match("%f[%a]bsn%f[%A]") or name_l:match("%f[%a]fgt%f[%A]") or
       name_l:find("posaune") or name_l:find("trombone") or name_l:match("%f[%a]trb%f[%A]") or name_l:match("%f[%a]pos%f[%A]") or name_l:match("%f[%a]tbn%f[%A]") or
       name_l:find("baritone") or name_l:find("euphonium") then
        return "bass"
    end

    -- 7. Explicit treble instruments (violin, flute, oboe, clarinet, trumpet, horn, guitar, etc.)
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
    local pref = k and state.note_stem_directions[k]
    if pref ~= nil then return pref end
    local eff_sqn = (orig and orig.start_qn) or vn.start_qn or 0
    local eff_pitch = (orig and orig.pitch) or vn.pitch or 0
    local eff_chan = (orig and orig.chan) or vn.chan or 0
    if orig and orig.take then
        local id_k = string.format("%s_%s_%.3f", tostring(orig.take or "0"), tostring(orig.idx or 0), eff_sqn)
        pref = state.note_stem_directions[id_k]
        if pref ~= nil then return pref end
        local pos_k = string.format("%s_%.3f_%d", tostring(orig.take or "0"), eff_sqn, eff_pitch)
        pref = state.note_stem_directions[pos_k]
        if pref ~= nil then return pref end
    end
    local trk = (orig and orig.track) or vn.track
    local trk_guid = vn.track_guid or (trk and reaper.ValidatePtr(trk, "MediaTrack*") and reaper.GetTrackGUID(trk)) or nil
    if trk_guid then
        local trk_k = string.format("trk_%s_%.3f_%d_%d", tostring(trk_guid), eff_sqn, eff_pitch, eff_chan)
        pref = state.note_stem_directions[trk_k]
        if pref ~= nil then return pref end
        local trk_pos_k = string.format("trk_%s_%.2f_%d", tostring(trk_guid), eff_sqn, eff_pitch)
        pref = state.note_stem_directions[trk_pos_k]
        if pref ~= nil then return pref end
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

function Engraver.get_note_custom_notehead_type(vn, state)
    if not vn then return nil end
    local orig = vn.orig or (vn.take and vn) or nil
    if orig and orig.notehead_type and orig.notehead_type ~= "auto" and Constants.NOTEHEAD_DEFS and Constants.NOTEHEAD_DEFS[orig.notehead_type] then
        return orig.notehead_type
    end
    if vn.custom_notehead_type and vn.custom_notehead_type ~= "auto" and Constants.NOTEHEAD_DEFS and Constants.NOTEHEAD_DEFS[vn.custom_notehead_type] then
        return vn.custom_notehead_type
    end
    if state and state.note_head_types then
        local k = (orig and (orig.key or (orig.get_key and orig:get_key()))) or vn.key
        local pref = k and state.note_head_types[k]
        if pref and pref ~= "auto" and Constants.NOTEHEAD_DEFS and Constants.NOTEHEAD_DEFS[pref] then
            return pref
        end
        local eff_sqn = (orig and orig.start_qn) or vn.start_qn or 0
        local eff_pitch = (orig and orig.pitch) or vn.pitch or 0
        local eff_chan = (orig and orig.chan) or vn.chan or 0
        if orig and orig.take then
            local id_k = string.format("%s_%s_%.3f", tostring(orig.take or "0"), tostring(orig.idx or 0), eff_sqn)
            pref = state.note_head_types[id_k]
            if pref and pref ~= "auto" and Constants.NOTEHEAD_DEFS and Constants.NOTEHEAD_DEFS[pref] then return pref end
            local pos_k = string.format("%s_%.3f_%d", tostring(orig.take or "0"), eff_sqn, eff_pitch)
            pref = state.note_head_types[pos_k]
            if pref and pref ~= "auto" and Constants.NOTEHEAD_DEFS and Constants.NOTEHEAD_DEFS[pref] then return pref end
        end
        local trk = (orig and orig.track) or vn.track
        local trk_guid = vn.track_guid or (trk and reaper and reaper.ValidatePtr and reaper.ValidatePtr(trk, "MediaTrack*") and reaper.GetTrackGUID(trk)) or nil
        if trk_guid then
            local trk_k = string.format("trk_%s_%.3f_%d_%d", tostring(trk_guid), eff_sqn, eff_pitch, eff_chan)
            pref = state.note_head_types[trk_k]
            if pref and pref ~= "auto" and Constants.NOTEHEAD_DEFS and Constants.NOTEHEAD_DEFS[pref] then return pref end
            local trk_pos_k = string.format("trk_%s_%.2f_%d", tostring(trk_guid), eff_sqn, eff_pitch)
            pref = state.note_head_types[trk_pos_k]
            if pref and pref ~= "auto" and Constants.NOTEHEAD_DEFS and Constants.NOTEHEAD_DEFS[pref] then return pref end
        end
    end
    return nil
end

function Engraver.get_note_notehead_type(vn, state, is_unpitched, eff_pitch)
    local custom = Engraver.get_note_custom_notehead_type(vn, state)
    if custom then
        return custom
    end
    return "standard"
end

-- Elaine Gould ("Behind Bars", pp. 291-295) & SMuFL Engraving Anchors (stemUpSE / stemDownNW):
-- Returns (dx, dy) offset from notehead center (nx, ny) where the stem attaches cleanly to the notehead contour.
function Engraver.get_notehead_stem_attachment(notehead_type, stem_down, s, is_filled)
    s = s or 1.0
    local ntype = notehead_type or "standard"
    if ntype == "x" then
        if stem_down then return -4.6 * s, 3.8 * s else return 4.6 * s, -3.8 * s end
    elseif ntype == "circle_x" then
        if stem_down then return -4.2 * s, 2.2 * s else return 4.2 * s, -2.2 * s end
    elseif ntype == "diamond" then
        if is_filled == false then
            if stem_down then return -4.4 * s, 0.8 * s else return 4.4 * s, -0.8 * s end
        end
        if stem_down then return -4.6 * s, 1.4 * s else return 4.6 * s, -1.4 * s end
    elseif ntype == "triangle" then
        if stem_down then return -4.7 * s, 4.4 * s else return 4.7 * s, 4.4 * s end
    elseif ntype == "triangle_down" then
        if stem_down then return -4.7 * s, -4.4 * s else return 4.7 * s, -4.4 * s end
    elseif ntype == "plus" then
        if stem_down then return -4.2 * s, 0.0 else return 4.2 * s, 0.0 end
    elseif ntype == "slash" then
        local dy = (is_filled == false) and (4.2 * s) or (3.5 * s)
        if stem_down then return -3.9 * s, dy else return 3.9 * s, -dy end
    elseif ntype == "square" then
        if stem_down then return -4.2 * s, 0.0 else return 4.2 * s, 0.0 end
    else
        if stem_down then return -4.8 * s, 1.2 * s else return 4.8 * s, -1.2 * s end
    end
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

-- Diatonic steps (0=C, 1=D, 2=E, 3=F, 4=G, 5=A, 6=B) altered by sharp/flat key signatures:
local KEY_SHARP_DIATONIC_STEPS = { 3, 0, 4, 1, 5, 2, 6 } -- F#, C#, G#, D#, A#, E#, B#
local KEY_FLAT_DIATONIC_STEPS  = { 6, 2, 5, 1, 4, 0, 3 } -- Bb, Eb, Ab, Db, Gb, Cb, Fb

function Engraver.get_key_sig_step_accidental(step_in_oct, key_sig_idx)
    if type(key_sig_idx) == "table" then
        key_sig_idx = key_sig_idx.key_idx or key_sig_idx.idx or 0
    end
    local kidx = tonumber(key_sig_idx) or 0
    if kidx == 0 then return 0 end
    local step = ((step_in_oct or 0) % 7 + 7) % 7
    if kidx > 0 then
        local count = math.min(7, kidx)
        for i = 1, count do
            if KEY_SHARP_DIATONIC_STEPS[i] == step then
                return 1
            end
        end
    elseif kidx < 0 then
        local count = math.min(7, math.abs(kidx))
        for i = 1, count do
            if KEY_FLAT_DIATONIC_STEPS[i] == step then
                return -1
            end
        end
    end
    return 0
end

local function resolve_key_enharmonic_pref(p_mod, preferred_acc, key_sig_idx)
    if preferred_acc ~= nil and preferred_acc ~= 0 then
        return preferred_acc
    end
    local kidx = tonumber(key_sig_idx) or 0
    if kidx > 0 then
        if p_mod == 1 or p_mod == 3 or p_mod == 6 or p_mod == 8 or p_mod == 10
           or (kidx >= 6 and p_mod == 5)
           or (kidx >= 7 and p_mod == 0) then
            return 1
        end
    elseif kidx < 0 then
        if p_mod == 1 or p_mod == 3 or p_mod == 6 or p_mod == 8 or p_mod == 10
           or (kidx <= -6 and p_mod == 11)
           or (kidx <= -7 and p_mod == 4) then
            return -1
        end
    end
    return preferred_acc
end

function Engraver.get_pitch_display_name(pitch, preferred_acc, key_sig_idx)
    if type(key_sig_idx) == "table" then
        key_sig_idx = key_sig_idx.key_idx or key_sig_idx.idx or 0
    end
    local p = math.max(0, math.min(127, math.floor((pitch or 60) + 0.5)))
    local p_mod = p % 12
    local p_info = Constants.PITCH_MAP[p_mod]
    local oct_shift = 0
    local eff_pref_acc = resolve_key_enharmonic_pref(p_mod, preferred_acc, key_sig_idx)
    if eff_pref_acc and ENHARMONIC_SPELLINGS[p_mod] and ENHARMONIC_SPELLINGS[p_mod][eff_pref_acc] then
        p_info = ENHARMONIC_SPELLINGS[p_mod][eff_pref_acc]
        oct_shift = p_info.oct_shift or 0
    end
    local octave = (math.floor(p / 12) - 1) + oct_shift
    return (p_info and p_info.name or "C"), octave
end

function Engraver.pitch_to_canvas_y(pitch, treble_bottom_y, bass_bottom_y, step_y, is_grand, track_clef, preferred_acc, mid_bottom_y, key_sig_idx, force_staff)
    if type(key_sig_idx) == "table" then
        key_sig_idx = key_sig_idx.key_idx or key_sig_idx.idx or 0
    end
    local p_mod = pitch % 12
    local p_info = Constants.PITCH_MAP[p_mod]
    local oct_shift = 0
    local eff_pref_acc = resolve_key_enharmonic_pref(p_mod, preferred_acc, key_sig_idx)
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
        if cdef and cdef.unpitched and Constants.GM_DRUM_STEP_MAP then
            local eff_p = math.max(0, math.min(127, math.floor(pitch or 60)))
            offset = Constants.GM_DRUM_STEP_MAP[eff_p] or Constants.GM_DRUM_STEP_MAP[60 + (eff_p % 12)] or 4
            ny = target_bottom_y - (offset * step_y)
            return ny, in_treble, offset, 0, staff_target, 0
        end
        local b_diatonic = (cdef and cdef.bottom_line_diatonic) or (track_clef == "bass" and -10 or 2)
        offset = diatonic_from_c4 - b_diatonic
        ny = target_bottom_y - (offset * step_y)
    end
    
    local final_acc = (cdef and cdef.unpitched) and 0 or (p_info and p_info.acc or 0)
    local key_step_acc = 0
    if not (cdef and cdef.unpitched) and key_sig_idx and key_sig_idx ~= 0 and p_info then
        key_step_acc = Engraver.get_key_sig_step_accidental(p_info.step, key_sig_idx)
        local raw_note_acc = (p_info.acc == 2) and 0 or (p_info.acc or 0)
        if p_info.acc == 2 then
            final_acc = 2
        elseif raw_note_acc == key_step_acc then
            final_acc = 0 -- Accidental dictated by key signature (suppress)
        elseif raw_note_acc == 0 and key_step_acc ~= 0 then
            final_acc = 2 -- Non-diatonic cancellation (natural sign ♮)
        else
            final_acc = raw_note_acc
        end
    end

    return ny, in_treble, offset, final_acc, staff_target, key_step_acc
end

-- ==============================================================================
-- ELAINE GOULD ("BEHIND BARS", PP. 78-84) ACCIDENTAL MEMORY & CHORD STACKING
-- 1. Intra-bar accidental persistence per diatonic staff step (resets at barline)
-- 2. Automatic natural (♮) cancellation when an altered step returns to natural in-bar
-- 3. Suppression of redundant accidentals on tied continuation segments
-- 4. Multi-column high-to-low chord accidental staggering (7ths/octaves share column)
-- ==============================================================================
function Engraver.apply_measure_accidental_memory(visual_notes, qn_per_measure, measure_map)
    if not visual_notes or #visual_notes == 0 then return end
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0
    local state_by_bar_staff = {}

    for _, vn in ipairs(visual_notes) do
        local qn = vn.display_qn or vn.start_qn or 0
        local m = vn.bar or (Engraver.qn_to_measure_info(qn + 0.001, bpi, measure_map))
        local staff = vn.in_staff or (vn.in_treble and "treble" or "bass")
        local key = tostring(m) .. "_" .. tostring(staff)
        if not state_by_bar_staff[key] then
            state_by_bar_staff[key] = {}
        end
        local mem = state_by_bar_staff[key]
        local dstep = vn.dstep

        if vn.is_tied_from_prev then
            -- Tied continuation notes never restate the accidental on the tied notehead
            vn.acc = 0
        elseif dstep then
            local raw_acc = vn.acc or 0
            local prev_entry = mem[dstep]
            local active_acc = prev_entry and prev_entry.acc or 0

            if prev_entry and math.abs(qn - prev_entry.qn) <= 0.02 then
                -- Simultaneous note at same onset: keep its own accidental if distinct
                if raw_acc == prev_entry.raw_acc then
                    vn.acc = prev_entry.shown_acc
                end
            else
                local shown_acc = 0
                if raw_acc ~= active_acc then
                    if raw_acc == 0 and active_acc ~= 0 then
                        -- Return to key-signature state for this step in the same measure:
                        -- show sharp/flat if step is altered in key signature, otherwise natural (♮)
                        shown_acc = (vn.key_step_acc and vn.key_step_acc ~= 0) and vn.key_step_acc or 2
                    else
                        shown_acc = raw_acc
                    end
                    mem[dstep] = { acc = raw_acc, raw_acc = raw_acc, shown_acc = shown_acc, qn = qn }
                else
                    -- Same accidental already active at this diatonic step in this measure: suppress
                    shown_acc = 0
                    mem[dstep] = { acc = active_acc, raw_acc = raw_acc, shown_acc = 0, qn = qn }
                end
                vn.acc = shown_acc
            end
        end
    end
end

function Engraver.layout_chord_accidentals(visual_notes, s)
    if not visual_notes or #visual_notes == 0 then return end
    local scale = s or 1.0
    local i = 1
    local n_total = #visual_notes

    while i <= n_total do
        local j = i
        local base_qn = visual_notes[i].display_qn or visual_notes[i].start_qn or 0
        local base_staff = visual_notes[i].in_staff or (visual_notes[i].in_treble and "treble" or "bass")

        local min_head_offset = math.min(0, visual_notes[i].head_x_offset or 0)
        local acc_notes = {}
        if (visual_notes[i].acc or 0) ~= 0 then
            table.insert(acc_notes, visual_notes[i])
        end

        while j + 1 <= n_total do
            local nxt = visual_notes[j + 1]
            local nxt_qn = nxt.display_qn or nxt.start_qn or 0
            local nxt_staff = nxt.in_staff or (nxt.in_treble and "treble" or "bass")
            if nxt_staff == base_staff and math.abs(nxt_qn - base_qn) <= 0.02 then
                j = j + 1
                if (nxt.head_x_offset or 0) < min_head_offset then
                    min_head_offset = nxt.head_x_offset or 0
                end
                if (nxt.acc or 0) ~= 0 then
                    table.insert(acc_notes, nxt)
                end
            else
                break
            end
        end

        if #acc_notes == 1 then
            local vn = acc_notes[1]
            vn.acc_x_offset = min_head_offset - (vn.head_x_offset or 0)
        elseif #acc_notes > 1 then
            -- Sort top-to-bottom (highest dstep first) per Elaine Gould ("Behind Bars", pp. 81-83)
            table.sort(acc_notes, function(a, b)
                return (a.dstep or 0) > (b.dstep or 0)
            end)
            local columns = {} -- columns[col_idx] = list of dsteps placed in that column
            for _, vn in ipairs(acc_notes) do
                local ds = vn.dstep or 0
                local placed_col = nil
                for c = 1, #columns do
                    local conflict = false
                    for _, existing_ds in ipairs(columns[c]) do
                        -- Accidentals closer than a 7th (6 diatonic steps) collide vertically
                        if math.abs(ds - existing_ds) < 6 then
                            conflict = true
                            break
                        end
                    end
                    if not conflict then
                        placed_col = c
                        table.insert(columns[c], ds)
                        break
                    end
                end
                if not placed_col then
                    placed_col = #columns + 1
                    columns[placed_col] = { ds }
                end
                vn.acc_x_offset = (min_head_offset - (vn.head_x_offset or 0)) - ((placed_col - 1) * 9.5 * scale)
            end
        end

        i = j + 1
    end
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

function Engraver.canvas_y_to_pitch(y, treble_bottom_y, bass_bottom_y, step_y, is_grand, track_clef, accidental, mid_bottom_y, key_sig_idx)
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
        local target_bottom_y = (track_clef == "bass" and bass_bottom_y) or ((track_clef == "alto" and mid_bottom_y) and mid_bottom_y or treble_bottom_y)
        in_treble = (track_clef ~= "bass")
        local offset = math.floor(((target_bottom_y - y) / step_y) + 0.5)
        if cdef and cdef.unpitched then
            local dp = GM_STEP_TO_DRUM_PITCH[offset]
            if dp then return dp, in_treble, offset, 0 end
        end
        local b_diatonic = (cdef and cdef.bottom_line_diatonic) or (track_clef == "bass" and -10 or 2)
        diatonic_from_c4 = offset + b_diatonic
    end
    
    local total_diatonic_step = diatonic_from_c4 + 28
    local octave = math.floor(total_diatonic_step / 7)
    local step_in_oct = total_diatonic_step % 7
    local semitone = DIATONIC_STEP_TO_SEMITONE[step_in_oct] or 0
    local eff_acc
    if acc == 1 or acc == -1 then
        eff_acc = acc
    elseif acc == 2 then
        eff_acc = 0 -- Explicit Natural (♮) override cancels key signature
    else
        eff_acc = Engraver.get_key_sig_step_accidental(step_in_oct, key_sig_idx)
    end
    local pitch = ((octave + 1) * 12) + semitone + eff_acc
    return math.max(0, math.min(127, pitch)), in_treble, step_in_oct, eff_acc
end

function Engraver.decompose_rest_gap(rests, start_qn, dur_qn, m, qn_per_measure, bar_start_qn)
    if not dur_qn or dur_qn < 0.05 then return end
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0
    local b_sqn = bar_start_qn or (m * bpi)
    local rem = dur_qn
    local cur = start_qn
    
    -- 1. Fill off-beat subdivisions step-by-step up to the next quarter-beat boundary (Elaine Gould p. 163)
    local sub_rests = {
        { val = 0.5,    type = "8th" },
        { val = 0.25,   type = "16th" },
        { val = 0.125,  type = "32nd" },
        { val = 0.0625, type = "64th" }
    }
    local guard = 0
    while guard < 8 and rem >= 0.05 do
        guard = guard + 1
        local beat_offset = (cur - b_sqn) % 1.0
        if beat_offset <= 0.03 or beat_offset >= 0.97 then break end
        local needed_to_beat = 1.0 - beat_offset
        local matched_sub = false
        for _, rdef in ipairs(sub_rests) do
            -- Pick the smallest binary subdivision that aligns cur to the next coarser binary boundary
            if rem >= rdef.val - 0.01 and math.abs((beat_offset % (rdef.val * 2.0)) - rdef.val) < 0.02 and rdef.val <= needed_to_beat + 0.02 then
                table.insert(rests, {
                    type = rdef.type,
                    start_qn = cur,
                    dur_qn = rdef.val,
                    measure_idx = m,
                    is_full_measure = false
                })
                cur = cur + rdef.val
                rem = rem - rdef.val
                matched_sub = true
                break
            end
        end
        if not matched_sub then
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
                    matched_sub = true
                    break
                end
            end
        end
        if not matched_sub then break end
    end
    
    -- 2. Main rest decomposition observing metric beat hierarchy (half rests only on beats 1 & 3 in 4/4)
    while rem >= 0.05 do
        local matched = false
        local cur_in_bar = math.max(0.0, cur - b_sqn)
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

function Engraver.generate_track_rests(track_notes, total_measures, qn_per_measure, dq, min_m, max_m, measure_map)
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
        local start_bar = Engraver.qn_to_measure_info(n_start + 0.001, bpi, measure_map)
        local end_bar = Engraver.qn_to_measure_info(math.max(n_start, n_end - 0.001), bpi, measure_map)
        local from_b = math.max(start_m, start_bar)
        local to_b = math.min(stop_m, end_bar)
        for m = from_b, to_b do
            if notes_by_bar[m] then table.insert(notes_by_bar[m], n) end
        end
    end
    
    for m = start_m, stop_m do
        local bar_notes = notes_by_bar[m]
        local bar_start_qn, bar_end_qn, bar_bpi = Engraver.measure_to_qn_info(m, bpi, measure_map)
        
        if #bar_notes == 0 then
            table.insert(rests, {
                type = "whole",
                start_qn = bar_start_qn,
                dur_qn = bar_bpi,
                measure_idx = m,
                is_full_measure = true
            })
        else
            -- Sort notes in measure chronologically
            table.sort(bar_notes, function(a, b) return a.start_qn < b.start_qn end)
            
            -- Group by unique rhythmic onset slots (combine chords)
            local distinct_onsets = {}
            for _, n in ipairs(bar_notes) do
                local snap_grid = dq or 0.0625
                local eff_n_start = math.max(bar_start_qn, n.start_qn)
                local eff_n_end = math.min(bar_end_qn, n.end_qn or (n.start_qn + (n.dur_qn or (n.end_qn and (n.end_qn - n.start_qn) or 1.0))))
                local eff_n_dur = math.max(0, eff_n_end - eff_n_start)
                local rel_s = eff_n_start - bar_start_qn
                local snapped_s = bar_start_qn + (math.floor((rel_s / snap_grid) + 0.5) * snap_grid)
                local raw_dur = eff_n_dur
                local nom_dur = dq and (math.max(dq, math.floor((raw_dur / dq) + 0.5) * dq)) or Engraver.get_nominal_rhythmic_duration(raw_dur)
                
                local found = false
                local tol = dq and (dq * 0.7) or 0.05
                for _, slot in ipairs(distinct_onsets) do
                    if math.abs(slot.s - snapped_s) < tol then
                        slot.dur = math.max(slot.dur, nom_dur)
                        slot.actual_end = math.max(slot.actual_end, eff_n_end)
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(distinct_onsets, {
                        s = snapped_s,
                        dur = nom_dur,
                        actual_end = eff_n_end
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
            if total_nom_dur < bar_bpi - fill_tol then
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
                
                if covered < bar_bpi - fill_tol then
                    local cur_pos = bar_start_qn
                    for _, inv in ipairs(merged) do
                        if inv.s > cur_pos + fill_tol then
                            local gap_dur = inv.s - cur_pos
                            Engraver.decompose_rest_gap(rests, cur_pos, gap_dur, m, bar_bpi, bar_start_qn)
                        end
                        cur_pos = math.max(cur_pos, inv.e)
                    end
                    if bar_end_qn > cur_pos + fill_tol then
                        Engraver.decompose_rest_gap(rests, cur_pos, bar_end_qn - cur_pos, m, bar_bpi, bar_start_qn)
                    end
                end
            end
        end
    end
    return rests
end


function Engraver.generate_voice_rests(track_notes, total_measures, qn_per_measure, dq, min_m, max_m, measure_map)
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
        return Engraver.generate_track_rests(track_notes, total_measures, qn_per_measure, dq, min_m, max_m, measure_map)
    end
    
    -- Polyphonic track (Elaine Gould "Behind Bars" p. 308 / Gardner Read):
    -- Each voice has its own metric rest stream when sounding simultaneously.
    -- However, when voices share a stave consecutively rather than simultaneously
    -- (e.g. voice 1 plays beats 1-2, voice 2 plays beats 3-4):
    -- 1. Inactive voices NEVER emit rests for inactive periods if the measure is filled sequentially!
    -- 2. If consecutive voices leave a gap, a single shared rest fills the empty part.
    -- 3. Stems and rests only split per voice when multiple voices actually coexist/overlap.
    local all_rests = {}
    local start_m = math.max(0, min_m or 0)
    local stop_m = math.min(total_measures - 1, max_m or (total_measures - 1))
    if start_m > stop_m then return all_rests end
    
    local notes_by_bar = {}
    for m = start_m, stop_m do notes_by_bar[m] = {} end
    
    for _, n in ipairs(track_notes or {}) do
        local n_start = dq and (math.floor((n.start_qn / dq) + 0.5) * dq) or n.start_qn
        local n_dur = dq and (math.max(dq, math.floor(((n.dur_qn or (n.end_qn - n.start_qn)) / dq) + 0.5) * dq)) or (n.dur_qn or (n.end_qn - n.start_qn))
        local n_end = n_start + n_dur
        local start_bar = Engraver.qn_to_measure_info(n_start + 0.001, bpi, measure_map)
        local end_bar = Engraver.qn_to_measure_info(math.max(n_start, n_end - 0.001), bpi, measure_map)
        local from_b = math.max(start_m, start_bar)
        local to_b = math.min(stop_m, end_bar)
        for m = from_b, to_b do
            if notes_by_bar[m] then table.insert(notes_by_bar[m], n) end
        end
    end
    
    for m = start_m, stop_m do
        local bar_notes = notes_by_bar[m]
        local bar_sqn, bar_eqn, bar_bpi = Engraver.measure_to_qn_info(m, bpi, measure_map)
        local bar_end_qn = bar_eqn
        
        if #bar_notes == 0 then
            -- Measure is completely empty across ALL voices: emit a single centered whole rest
            table.insert(all_rests, {
                type = "whole",
                start_qn = bar_sqn,
                dur_qn = bar_bpi,
                measure_idx = m,
                is_full_measure = true
            })
        else
            -- Group notes in this measure by voice
            local voices_in_bar = {}
            local notes_by_v = {}
            for _, n in ipairs(bar_notes) do
                local v = (n.chan or 0) + 1
                if not notes_by_v[v] then
                    notes_by_v[v] = {}
                    table.insert(voices_in_bar, v)
                end
                table.insert(notes_by_v[v], n)
            end
            table.sort(voices_in_bar)
            
            if #voices_in_bar == 1 then
                -- Only ONE voice is active in this measure.
                -- Inactive voices emit 0 rests. The active voice behaves like a standard single voice.
                local v = voices_in_bar[1]
                local v_rests = Engraver.generate_track_rests(notes_by_v[v], total_measures, qn_per_measure, dq, m, m, measure_map)
                for _, r in ipairs(v_rests) do
                    if not r.is_full_measure then
                        r.voice = nil -- Standard centered rest for monophonic measure
                        table.insert(all_rests, r)
                    end
                end
            else
                -- Multiple voices are active in this measure.
                -- Check for simultaneous overlap between distinct voices:
                local has_simultaneous_overlap = false
                for i = 1, #bar_notes do
                    local na = bar_notes[i]
                    local va = (na.chan or 0) + 1
                    local sa = math.max(bar_sqn, na.start_qn)
                    local ea = math.min(bar_eqn, na.end_qn or (na.start_qn + (na.dur_qn or 1.0)))
                    for j = i + 1, #bar_notes do
                        local nb = bar_notes[j]
                        local vb = (nb.chan or 0) + 1
                        if va ~= vb then
                            local sb = math.max(bar_sqn, nb.start_qn)
                            local eb = math.min(bar_eqn, nb.end_qn or (nb.start_qn + (nb.dur_qn or 1.0)))
                            local overlap_len = math.min(ea, eb) - math.max(sa, sb)
                            if overlap_len > 0.05 then
                                has_simultaneous_overlap = true
                                break
                            end
                        end
                    end
                    if has_simultaneous_overlap then break end
                end
                
                if not has_simultaneous_overlap then
                    -- Consecutive voices (Gould "Behind Bars" p. 308):
                    -- Voices do not sound simultaneously. Check combined metric coverage of the measure.
                    local distinct_onsets = {}
                    for _, n in ipairs(bar_notes) do
                        local snap_grid = dq or 0.0625
                        local eff_n_start = math.max(bar_sqn, n.start_qn)
                        local eff_n_end = math.min(bar_eqn, n.end_qn or (n.start_qn + (n.dur_qn or (n.end_qn and (n.end_qn - n.start_qn) or 1.0))))
                        local eff_n_dur = math.max(0, eff_n_end - eff_n_start)
                        local rel_s = eff_n_start - bar_sqn
                        local snapped_s = bar_sqn + (math.floor((rel_s / snap_grid) + 0.5) * snap_grid)
                        local nom_dur = dq and (math.max(dq, math.floor((eff_n_dur / dq) + 0.5) * dq)) or Engraver.get_nominal_rhythmic_duration(eff_n_dur)
                        
                        local found = false
                        local tol = dq and (dq * 0.7) or 0.05
                        for _, slot in ipairs(distinct_onsets) do
                            if math.abs(slot.s - snapped_s) < tol then
                                slot.dur = math.max(slot.dur, nom_dur)
                                slot.actual_end = math.max(slot.actual_end, eff_n_end)
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(distinct_onsets, {
                                s = snapped_s,
                                dur = nom_dur,
                                actual_end = eff_n_end
                            })
                        end
                    end
                    table.sort(distinct_onsets, function(a, b) return a.s < b.s end)
                    
                    local intervals = {}
                    for idx, slot in ipairs(distinct_onsets) do
                        local s_qn = math.max(bar_sqn, slot.s)
                        local nom_e = s_qn + slot.dur
                        if idx < #distinct_onsets then
                            local next_s = distinct_onsets[idx + 1].s
                            if next_s > s_qn + 0.05 then
                                nom_e = math.min(nom_e, next_s)
                            end
                        else
                            local fill_tol = dq and (dq * 0.5) or 0.20
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
                    
                    local fill_tol = dq and (dq * 0.5) or 0.20
                    if covered < bar_bpi - fill_tol then
                        local cur_pos = bar_sqn
                        for _, inv in ipairs(merged) do
                            if inv.s > cur_pos + fill_tol then
                                local gap_dur = inv.s - cur_pos
                                Engraver.decompose_rest_gap(all_rests, cur_pos, gap_dur, m, bar_bpi, bar_sqn)
                            end
                            cur_pos = math.max(cur_pos, inv.e)
                        end
                        if bar_eqn > cur_pos + fill_tol then
                            Engraver.decompose_rest_gap(all_rests, cur_pos, bar_eqn - cur_pos, m, bar_bpi, bar_sqn)
                        end
                    end
                    -- If covered >= bar_bpi - fill_tol: completely full consecutively, 0 rests!
                else
                    -- Overlapping voices: true polyphony in this measure (Elaine Gould "Behind Bars" p. 308-310).
                    -- 1. Analyze voice activity spans in this measure
                    local v_stats = {}
                    for _, v in ipairs(voices_in_bar) do
                        local v_notes = notes_by_v[v] or {}
                        local min_s = 999999
                        local max_e = -999999
                        for _, n in ipairs(v_notes) do
                            local ns = math.max(bar_sqn, n.start_qn)
                            local ne = math.min(bar_eqn, n.end_qn or (n.start_qn + (n.dur_qn or 1.0)))
                            if ns < min_s then min_s = ns end
                            if ne > max_e then max_e = ne end
                        end
                        v_stats[v] = { min_s = min_s, max_e = max_e }
                    end

                    -- 2. Generate rests per voice with subordinate entry/exit suppression
                    local raw_poly_rests = {}
                    for _, v in ipairs(voices_in_bar) do
                        local v_rests = Engraver.generate_track_rests(notes_by_v[v], total_measures, qn_per_measure, dq, m, m, measure_map)
                        local stats = v_stats[v]
                        for _, r in ipairs(v_rests) do
                            if not r.is_full_measure then
                                local r_s = r.start_qn
                                local r_e = r_s + r.dur_qn
                                local is_leading_rest = (stats and r_e <= stats.min_s + 0.05)
                                local is_trailing_rest = (stats and r_s >= stats.max_e - 0.05)

                                -- Check if another voice is actively sounding during this leading/trailing rest:
                                local other_voice_playing = false
                                for other_v, other_stat in pairs(v_stats) do
                                    if other_v ~= v then
                                        for _, on in ipairs(notes_by_v[other_v] or {}) do
                                            local ons = math.max(bar_sqn, on.start_qn)
                                            local one = math.min(bar_eqn, on.end_qn or (on.start_qn + (on.dur_qn or 1.0)))
                                            if not (r_e <= ons + 0.05 or r_s >= one - 0.05) then
                                                other_voice_playing = true
                                                break
                                            end
                                        end
                                    end
                                    if other_voice_playing then break end
                                end

                                -- Gould p. 308: Do not crowd stave with rests for a secondary voice before entry or after exit
                                if not ((is_leading_rest or is_trailing_rest) and other_voice_playing) then
                                    r.voice = v
                                    table.insert(raw_poly_rests, r)
                                end
                            end
                        end
                    end

                    -- 3. Sort tentative rests chronologically
                    table.sort(raw_poly_rests, function(a, b)
                        if math.abs(a.start_qn - b.start_qn) > 0.01 then
                            return a.start_qn < b.start_qn
                        end
                        return (a.voice or 0) < (b.voice or 0)
                    end)

                    -- 4. Coincident Rest Fusion (Gould p. 308):
                    -- When both voices rest simultaneously, combine into a single rest centered on staff
                    local fused_rests = {}
                    local skip_rest = {}
                    for i = 1, #raw_poly_rests do
                        if not skip_rest[i] then
                            local ra = raw_poly_rests[i]
                            for j = i + 1, #raw_poly_rests do
                                if not skip_rest[j] then
                                    local rb = raw_poly_rests[j]
                                    if math.abs(ra.start_qn - rb.start_qn) < 0.08 then
                                        -- Both voices rest at the same time -> single centered rest!
                                        ra.voice = nil
                                        ra.dur_qn = math.min(ra.dur_qn, rb.dur_qn)
                                        ra.type = (ra.dur_qn >= 4.0 and "whole") or
                                                  (ra.dur_qn >= 2.0 and "half") or
                                                  (ra.dur_qn >= 1.0 and "quarter") or
                                                  (ra.dur_qn >= 0.5 and "8th") or
                                                  (ra.dur_qn >= 0.25 and "16th") or "32nd"
                                        skip_rest[j] = true
                                    end
                                end
                            end
                            table.insert(fused_rests, ra)
                        end
                    end

                    -- 5. Cross-Voice Sounding Note Collision Avoidance (Gould p. 309):
                    -- A rest must NEVER obscure or touch a notehead of another voice.
                    for _, r in ipairs(fused_rests) do
                        local r_s = r.start_qn
                        local r_e = r_s + r.dur_qn
                        local collides_with_note = false
                        for _, n in ipairs(bar_notes) do
                            local ns = math.max(bar_sqn, n.start_qn)
                            local ne = math.min(bar_eqn, n.end_qn or (n.start_qn + (n.dur_qn or 1.0)))
                            local tol = dq and (dq * 0.3) or 0.05
                            if not (r_e <= ns + tol or r_s >= ne - tol) or math.abs(ns - r_s) < (dq and (dq * 0.7) or 0.22) then
                                collides_with_note = true
                                break
                            end
                        end
                        if not collides_with_note then
                            table.insert(all_rests, r)
                        end
                    end
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
        local tol = (sv >= 2.0) and 0.18 or math.min(0.10, math.max(0.03, sv * 0.20))
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
        if math.abs(dur - 3.5) <= 0.12 then
            -- 3.5 quarters: Dotted half (3.0) tied to eighth (0.5)
            table.insert(segments, { start_in_bar = 0.0, dur_qn = 3.0 })
            table.insert(segments, { start_in_bar = 3.0, dur_qn = 0.5 })
            return segments
        elseif math.abs(dur - 3.0) <= 0.18 then
            -- 3.0 quarters: Dotted half
            table.insert(segments, { start_in_bar = 0.0, dur_qn = 3.0 })
            return segments
        elseif math.abs(dur - 2.5) <= 0.12 then
            -- 2.5 quarters: Half note (2.0) tied to eighth (0.5)
            table.insert(segments, { start_in_bar = 0.0, dur_qn = 2.0 })
            table.insert(segments, { start_in_bar = 2.0, dur_qn = 0.5 })
            return segments
        elseif math.abs(dur - 2.0) <= 0.18 then
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

function Engraver.get_visual_notes(notes, qn_per_measure, vis_min_qn, vis_max_qn, user_ties, measure_map)
    local visual_notes = {}
    local bar_ties = {}
    local bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0
    if not notes then return visual_notes, bar_ties end
    
    -- Step 1: Sort notes chronologically to build contiguous chains
    local sorted_notes = {}
    for _, n in ipairs(notes) do
        table.insert(sorted_notes, n)
    end
    table.sort(sorted_notes, function(a, b)
        local s1 = a.start_qn or a.sqn or 0
        local s2 = b.start_qn or b.sqn or 0
        if math.abs(s1 - s2) > 0.001 then return s1 < s2 end
        return (a.pitch or 0) < (b.pitch or 0)
    end)
    
    -- Step 2: Consolidate contiguous tied chains (Elaine Gould "Behind Bars" p. 166)
    -- When notes of the same pitch and channel are tied and contiguous without intervening rests,
    -- they form a single sustained musical event across measures (e.g. a full measure becomes a whole note).
    local visited = {}
    local chains = {}
    for i, n in ipairs(sorted_notes) do
        if not visited[n] then
            visited[n] = true
            local chain = { n }
            local search_forward = true
            while search_forward do
                local cur_tail = chain[#chain]
                local tail_pitch = cur_tail.pitch
                local tail_chan = cur_tail.chan or 0
                local tail_s = cur_tail.start_qn or cur_tail.sqn or 0
                local tail_e = cur_tail.end_qn or cur_tail.eqn or (tail_s + (cur_tail.dur_qn or 1.0))
                local next_cand = nil
                
                for j = 1, #sorted_notes do
                    local cand = sorted_notes[j]
                    if not visited[cand] and cand.pitch == tail_pitch and (cand.chan or 0) == tail_chan then
                        local cand_s = cand.start_qn or cand.sqn or 0
                        -- Contiguity check: cand must start at or very near tail_e (tolerance 0.08 QN)
                        if cand_s >= (tail_s - 0.01) and math.abs(cand_s - tail_e) <= 0.08 then
                            local is_connected = false
                            if cur_tail.tie_id and cand.tie_id and cur_tail.tie_id == cand.tie_id then
                                is_connected = true
                            elseif cur_tail.is_tied_master and (cand.is_tied_slave or (cand.idx and cand.idx == -1)) then
                                is_connected = true
                            elseif cur_tail.is_tied_master and cand.is_tied_slave then
                                is_connected = true
                            elseif user_ties and #user_ties > 0 then
                                for _, ut in ipairs(user_ties) do
                                    if ut.pitch == tail_pitch and (ut.chan == nil or ut.chan == tail_chan) then
                                        local ut_s1 = ut.n1_start_qn or 0
                                        local ut_s2 = ut.n2_start_qn or 0
                                        if math.abs(ut_s1 - tail_s) <= 0.10 and math.abs(ut_s2 - cand_s) <= 0.10 then
                                            is_connected = true
                                            break
                                        end
                                    end
                                end
                            end
                            
                            if is_connected then
                                next_cand = cand
                                break
                            end
                        end
                    end
                end
                
                if next_cand then
                    visited[next_cand] = true
                    table.insert(chain, next_cand)
                else
                    search_forward = false
                end
            end
            table.insert(chains, chain)
        end
    end
    
    local tuplet_dur_targets = {
        1.3333, 0.8000, 0.6667, 0.5714, 0.4000, 0.3333, 0.2857, 0.2000, 0.1667, 0.1429, 0.1000, 0.0833, 0.0714
    }
    local function is_note_tuplet_metric(n)
        if not n then return false end
        local s = n.start_qn or n.sqn or 0
        local e = n.end_qn or n.eqn or (s + (n.dur_qn or 1.0))
        local d = math.max(0.01, e - s)
        for _, td in ipairs(tuplet_dur_targets) do
            if math.abs(d - td) <= 0.025 then return true end
        end
        local rem_s = math.abs(s - math.floor((s / 0.125) + 0.5) * 0.125)
        local rem_e = math.abs(e - math.floor((e / 0.125) + 0.5) * 0.125)
        if rem_s > 0.022 or rem_e > 0.022 then
            return true
        end
        return false
    end

    -- Step 3: Decompose each note or consolidated tied chain into measure-specific visual notes.
    -- CRITICAL (Tuplet + Tie Rule): If ANY note in a tied chain is a tuplet note, NEVER merge the chain
    -- into a single combined duration (which would destroy tuplet onsets/durations and prevent tuplet engraving);
    -- instead, emit each note of the chain with its exact individual rhythmic value while linking them via bar_ties!
    for _, chain in ipairs(chains) do
        local first_n = chain[1]
        local last_n = chain[#chain]
        local chain_sqn = first_n.start_qn or first_n.sqn or 0
        if vis_max_qn and chain_sqn > vis_max_qn + 1.0 then
            break
        end
        local chain_eqn = last_n.end_qn or last_n.eqn or (chain_sqn + (last_n.dur_qn or 1.0))

        if not vis_min_qn or chain_eqn >= vis_min_qn - 2.0 then
            local chain_has_tuplet = false
            if #chain > 1 then
                for _, cn in ipairs(chain) do
                    if is_note_tuplet_metric(cn) then
                        chain_has_tuplet = true
                        break
                    end
                end
            end

            local units = {}
            if chain_has_tuplet then
                for _, cn in ipairs(chain) do
                    local us = cn.start_qn or cn.sqn or 0
                    local ue = cn.end_qn or cn.eqn or (us + (cn.dur_qn or 1.0))
                    table.insert(units, { sqn = us, eqn = ue, ref_note = cn })
                end
            else
                table.insert(units, { sqn = chain_sqn, eqn = chain_eqn, ref_note = nil })
            end

            local prev_seg = nil
            local prev_seg_key = nil
            local prev_seg_bar = nil
            local unit_serial = 0

            for _, unit in ipairs(units) do
                local n_sqn = unit.sqn
                local n_eqn = unit.eqn
                local grid = 0.0625
                local raw_dur = math.max(grid, n_eqn - n_sqn)

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
                    local t_step = matched_tuplet_dur
                    local step_idx = math.floor((n_sqn / t_step) + 0.5)
                    if math.abs(n_sqn - step_idx * t_step) <= 0.04 then
                        clean_sqn = step_idx * t_step
                    else
                        clean_sqn = n_sqn
                    end
                else
                    clean_sqn = math.floor((n_sqn / grid) + 0.5) * grid
                    snapped_dur = math.floor((raw_dur / grid) + 0.5) * grid
                    if snapped_dur < grid then snapped_dur = grid end
                    local close_targets = {
                        16.0, 15.0, 14.0, 12.0, 10.0, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.5,
                        4.0, 3.5, 3.0, 2.5, 2.0, 1.75, 1.5, 1.25, 1.0, 0.75, 0.5, 0.375, 0.25, 0.1875, 0.125, 0.0625
                    }
                    for _, ct in ipairs(close_targets) do
                        local tol = (ct >= 4.0) and 0.18 or math.min(0.14, math.max(0.025, ct * 0.25))
                        if math.abs(raw_dur - ct) <= tol then
                            snapped_dur = ct
                            break
                        end
                    end
                end
                local clean_eqn = clean_sqn + snapped_dur

                if (not vis_min_qn or clean_eqn >= vis_min_qn) and (not vis_max_qn or clean_sqn <= vis_max_qn) then
                    local start_bar = Engraver.qn_to_measure_info(clean_sqn + 0.001, bpi, measure_map)
                    local end_bar = Engraver.qn_to_measure_info(math.max(clean_sqn, clean_eqn - 0.001), bpi, measure_map)

                    for bar = start_bar, end_bar do
                        local bar_sqn, bar_eqn, bar_bpi = Engraver.measure_to_qn_info(bar, bpi, measure_map)
                        local seg_sqn = math.max(clean_sqn, bar_sqn)
                        local seg_eqn = math.min(clean_eqn, bar_eqn)
                        local seg_dur = seg_eqn - seg_sqn

                        if seg_dur > 0.01 then
                            local start_in_bar = seg_sqn - bar_sqn
                            local sub_segs = Engraver.decompose_bar_segment(start_in_bar, seg_dur, bar_bpi)

                            for sub_i, sub in ipairs(sub_segs) do
                                unit_serial = unit_serial + 1
                                local sub_sqn = bar_sqn + sub.start_in_bar
                                local sub_eqn = sub_sqn + sub.dur_qn

                                local active_n = unit.ref_note
                                if not active_n then
                                    for _, cn in ipairs(chain) do
                                        local c_s = cn.start_qn or cn.sqn or 0
                                        local c_e = cn.end_qn or cn.eqn or (c_s + (cn.dur_qn or 1.0))
                                        if sub_sqn >= (c_s - 0.02) and sub_sqn < (c_e - 0.02) then
                                            active_n = cn
                                            break
                                        end
                                    end
                                end
                                if not active_n then
                                    local min_dist = 999999
                                    for _, cn in ipairs(chain) do
                                        local c_s = cn.start_qn or cn.sqn or 0
                                        local dist = math.abs(sub_sqn - c_s)
                                        if dist < min_dist then
                                            min_dist = dist
                                            active_n = cn
                                        end
                                    end
                                end
                                if not active_n then active_n = first_n end

                                local target_orig = active_n
                                if target_orig.idx and target_orig.idx < 0 then
                                    target_orig = first_n
                                end

                                local it_str = tostring(active_n.item or first_n.item or "0")
                                local tk_str = tostring(active_n.take or first_n.take or "0")
                                local seg_key = string.format("%s_%s_%.3f_%d_%d_b%d_s%d", it_str, tk_str, sub_sqn, first_n.pitch, first_n.chan or 0, bar, unit_serial)

                                local is_segmented = (start_bar ~= end_bar) or (#sub_segs > 1) or (#chain > 1)
                                local seg = {
                                    orig = target_orig,
                                    pitch = first_n.pitch,
                                    start_qn = sub_sqn,
                                    end_qn = sub_eqn,
                                    dur_qn = sub.dur_qn,
                                    is_segment = is_segmented,
                                    seg_idx = unit_serial,
                                    key = seg_key,
                                    bar = bar,
                                    item = active_n.item or first_n.item,
                                    item_obj = active_n.item_obj or first_n.item_obj,
                                    take = active_n.take or first_n.take,
                                    track = active_n.track or first_n.track,
                                    stem_dir = target_orig and target_orig.stem_dir or nil,
                                    custom_notehead_type = target_orig and target_orig.notehead_type or nil,
                                    is_tied_chain = (#chain > 1),
                                    chain_notes = (#chain > 1) and chain or nil,
                                    is_tied_from_prev = (prev_seg ~= nil),
                                    is_tied_to_next = false
                                }
                                if prev_seg then
                                    prev_seg.is_tied_to_next = true
                                end
                                table.insert(visual_notes, seg)

                                if prev_seg_key then
                                    local is_cross = (prev_seg_bar ~= nil and prev_seg_bar ~= bar)
                                    table.insert(bar_ties, {
                                        from_key = prev_seg_key,
                                        to_key = seg_key,
                                        pitch = first_n.pitch,
                                        orig = target_orig,
                                        is_cross_barline = is_cross,
                                        from_bar = prev_seg_bar,
                                        to_bar = bar,
                                        is_tied_chain = (#chain > 1)
                                    })
                                end
                                prev_seg = seg
                                prev_seg_key = seg_key
                                prev_seg_bar = bar
                            end
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

function Engraver.get_beam_groups(visual_notes, qn_per_measure, grouping, timesig_num, timesig_denom, measure_map)
    local groups = {}
    if grouping == "none" then return groups end
    local default_bpi = (qn_per_measure and qn_per_measure > 0) and qn_per_measure or 4.0

    local function get_measure_group_size(m_bpi, ts_n, ts_d)
        if grouping == "bar" then
            return m_bpi
        elseif grouping == "half_bar" then
            return m_bpi / 2.0
        elseif ts_d == 8 and ts_n and ts_n >= 6 and (ts_n % 3 == 0) then
            -- Compound meters (6/8, 9/8, 12/8): beat is a dotted quarter note (1.5 QN = 3 eighth notes per beam)
            return 1.5
        else
            return 1.0 -- Standard simple meter: per quarter-note beat
        end
    end
    
    local function is_genuine_tuplet_step(step, tn)
        -- Exclude standard binary / dotted-binary note spacings:
        -- 8th (0.50), dotted 16th (0.375), 16th (0.25), dotted 32nd (0.1875), 32nd (0.125), 64th (0.0625)
        local binary_steps = { 0.50, 0.375, 0.25, 0.1875, 0.125, 0.0625 }
        for _, bs in ipairs(binary_steps) do
            if math.abs(step - bs) < 0.025 then
                return false
            end
        end
        local expected_steps = {
            [3] = { 2/3, 1/3, 1/6, 1/12 },
            [5] = { 4/5, 2/5, 1/5, 1/10 },
            [6] = { 1/3, 1/6, 1/12 },
            [7] = { 4/7, 2/7, 1/7, 1/14 },
        }
        local list = expected_steps[tn]
        if not list then return false end
        for _, exp_s in ipairs(list) do
            if math.abs(step - exp_s) < 0.02 then
                return true
            end
        end
        return false
    end

    local function group_staff_notes(notes_list)
        -- Compute per-measure and whole-staff distance-weighted pitch balance around middle line (dstep = 4)
        -- so middle-line and third-space notes follow surrounding stem direction in the measure/staff.
        local measure_balance = {}
        local staff_below, staff_above = 0, 0
        for _, vn in ipairs(notes_list) do
            local qn = vn.display_qn or vn.start_qn
            local m = vn.bar or Engraver.qn_to_measure_info(qn + 0.001, default_bpi, measure_map)
            if not measure_balance[m] then measure_balance[m] = { below = 0, above = 0 } end
            local ds = vn.dstep or 4
            if ds < 4 then
                local w = (4 - ds)
                measure_balance[m].below = measure_balance[m].below + w
                staff_below = staff_below + w
            elseif ds > 4 then
                local w = (ds - 4)
                measure_balance[m].above = measure_balance[m].above + w
                staff_above = staff_above + w
            end
        end
        for _, vn in ipairs(notes_list) do
            local qn = vn.display_qn or vn.start_qn
            local m = vn.bar or Engraver.qn_to_measure_info(qn + 0.001, default_bpi, measure_map)
            local bal = measure_balance[m]
            if bal and bal.below ~= bal.above then
                vn._measure_prefer_stem_up = (bal.below > bal.above)
            else
                vn._measure_prefer_stem_up = (staff_below >= staff_above)
            end
        end

        local beamable = {}
        for _, vn in ipairs(notes_list) do
            if Engraver.get_flag_count(vn.dur_qn) > 0 then
                table.insert(beamable, vn)
            end
        end
        table.sort(beamable, function(a, b)
            local a_qn = a.display_qn or a.start_qn
            local b_qn = b.display_qn or b.start_qn
            if math.abs(a_qn - b_qn) > 0.04 then return a_qn < b_qn end
            return a.pitch < b.pitch
        end)
        
        -- Condense simultaneous notes (chords / dyads) into atomic temporal onsets FIRST
        -- so a chord is NEVER split across two different beam groups!
        local onsets = {}
        for _, vn in ipairs(beamable) do
            local vn_qn = vn.display_qn or vn.start_qn
            local last_o = onsets[#onsets]
            if last_o and math.abs(vn_qn - last_o.qn) <= 0.04 then
                table.insert(last_o.notes, vn)
                if vn.dur_qn < last_o.dur_qn then last_o.dur_qn = vn.dur_qn end
                if vn.dur_qn > last_o.max_dur_qn then last_o.max_dur_qn = vn.dur_qn end
            else
                table.insert(onsets, {
                    qn = vn_qn,
                    start_qn = vn.start_qn,
                    dur_qn = vn.dur_qn,
                    max_dur_qn = vn.dur_qn,
                    notes = { vn }
                })
            end
        end

        -- Detection of genuine tuplet onset sequences (e.g. triplets, quintuplets, sextuplets, septuplets)
        -- without false-matching binary rhythms or splitting chords:
        local tuplet_assigned = {}
        local num_o = #onsets
        local o_idx = 1
        local tup_counter = 0
        while o_idx <= num_o do
            local found_tup = false
            for _, tn in ipairs({ 7, 6, 5, 3 }) do
                if o_idx + tn - 1 <= num_o then
                    local first_o = onsets[o_idx]
                    local last_o = onsets[o_idx + tn - 1]
                    local m_first = Engraver.qn_to_measure_info(first_o.qn + 0.001, default_bpi, measure_map)
                    local m_last  = Engraver.qn_to_measure_info(last_o.qn + 0.001, default_bpi, measure_map)
                    if m_first == m_last then
                        local span = last_o.qn - first_o.qn
                        local step = span / (tn - 1)
                        if is_genuine_tuplet_step(step, tn) then
                            local is_uniform = true
                            for k = 1, tn - 1 do
                                local prev_o = onsets[o_idx + k - 1]
                                local cur_o  = onsets[o_idx + k]
                                local diff = cur_o.qn - prev_o.qn
                                -- Must be uniformly spaced AND contiguous (no intervening rest)
                                if math.abs(diff - step) > 0.025 or diff > (prev_o.max_dur_qn + 0.04) then
                                    is_uniform = false
                                    break
                                end
                            end
                            if is_uniform then
                                tup_counter = tup_counter + 1
                                local g_tag = "tup_" .. tostring(tup_counter)
                                for k = 0, tn - 1 do
                                    tuplet_assigned[onsets[o_idx + k]] = g_tag
                                end
                                o_idx = o_idx + tn
                                found_tup = true
                                break
                            end
                        end
                    end
                end
            end
            if not found_tup then
                o_idx = o_idx + 1
            end
        end

        local cur_group = {}
        local cur_group_onsets = 0
        local cur_group_start = nil
        local prev_onset = nil
        for _, o in ipairs(onsets) do
            local m_idx, m_sqn, _, m_bpi, m_ts_n, m_ts_d = Engraver.qn_to_measure_info(o.qn + 0.001, default_bpi, measure_map)
            local eff_ts_n = m_ts_n or timesig_num
            local eff_ts_d = m_ts_d or timesig_denom
            local group_size = get_measure_group_size(m_bpi, eff_ts_n, eff_ts_d)
            local rel_qn = math.max(0.0, (o.qn + 0.001) - m_sqn)
            local beat_idx = math.floor(rel_qn / group_size)
            local g_idx = tuplet_assigned[o] or string.format("%d_%d", m_idx, beat_idx)
            -- Break beam group whenever separated by a rest gap (>= 0.11 QN) so beams never slice through rest glyphs
            local has_rest_gap = false
            if prev_onset and not tuplet_assigned[o] then
                local gap = o.qn - (prev_onset.qn + prev_onset.max_dur_qn)
                if gap >= 0.11 then
                    has_rest_gap = true
                end
            end
            if cur_group_start == nil or g_idx ~= cur_group_start or has_rest_gap then
                if cur_group_onsets >= 2 then
                    table.insert(groups, cur_group)
                end
                cur_group = {}
                for _, vn in ipairs(o.notes) do
                    table.insert(cur_group, vn)
                end
                cur_group_onsets = 1
                cur_group_start = g_idx
            else
                for _, vn in ipairs(o.notes) do
                    table.insert(cur_group, vn)
                end
                cur_group_onsets = cur_group_onsets + 1
            end
            prev_onset = o
        end
        if cur_group_onsets >= 2 then
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
        local vn_qn = vn.display_qn or vn.start_qn or 0
        local vnx = vn.vis_nx or vn.nominal_nx or vn.nx or 0
        local vny = vn.vis_ny or vn.ny or 0
        local vdstep = vn.dstep or 4
        local last_onset = onsets[#onsets]
        if last_onset and math.abs(vn_qn - last_onset.qn) <= 0.04 then
            table.insert(last_onset.notes, vn)
            if (vn.dur_qn or 0.5) < last_onset.dur_qn then last_onset.dur_qn = vn.dur_qn or 0.5 end
            if vny < last_onset.min_ny then last_onset.min_ny = vny end
            if vny > last_onset.max_ny then last_onset.max_ny = vny end
            if vdstep < last_onset.min_dstep then last_onset.min_dstep = vdstep end
            if vdstep > last_onset.max_dstep then last_onset.max_dstep = vdstep end
        else
            local onset_base_x = vnx - (vn.head_x_offset or 0)
            table.insert(onsets, {
                qn = vn_qn,
                start_qn = vn.start_qn or vn_qn,
                dur_qn = vn.dur_qn or 0.5,
                notes = { vn },
                nominal_nx = onset_base_x,
                min_ny = vny,
                max_ny = vny,
                min_dstep = vdstep,
                max_dstep = vdstep,
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
    local below_mid_cnt = 0
    local above_mid_cnt = 0
    local prefer_stem_up = false
    local group_max_dstep = -999
    for _, onset in ipairs(onsets) do
        for _, vn in ipairs(onset.notes) do
            if vn._measure_prefer_stem_up then
                prefer_stem_up = true
            end
            if vn.dstep and vn.dstep > group_max_dstep then
                group_max_dstep = vn.dstep
            end
            local sdir = Engraver.get_note_stem_direction(vn, state)
            if sdir then
                manual_stem_dir = sdir
            end
            local mid_step = 4 -- Middle line of 5-line staff (B4 in treble clef, D3 in bass clef, C4 in alto clef)
            local dist = math.abs(vn.dstep - mid_step)
            if vn.dstep < mid_step then
                below_mid_cnt = below_mid_cnt + 1
            elseif vn.dstep > mid_step then
                above_mid_cnt = above_mid_cnt + 1
            end
            if dist > max_dist then
                max_dist = dist
                group_stem_down = (vn.dstep > mid_step)
            elseif dist == max_dist and dist > 0 then
                if below_mid_cnt > above_mid_cnt then
                    group_stem_down = false
                elseif above_mid_cnt > below_mid_cnt then
                    group_stem_down = true
                end
            end
        end
    end
    if max_dist == 0 or (prefer_stem_up and group_max_dstep <= 5) then
        -- All notes in this beam group sit on the middle line (dstep == 4) or 3rd space (dstep == 5)
        -- in a measure strongly weighted below the middle line: keep stem direction consistent (UP)
        group_stem_down = not prefer_stem_up
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
        local anchor_nh = "standard"
        if onset.notes and #onset.notes > 0 then
            local anchor_vn = onset.notes[1]
            for _, ovn in ipairs(onset.notes) do
                local ony = ovn.vis_ny or ovn.ny or 0
                local any = anchor_vn.vis_ny or anchor_vn.ny or 0
                if group_stem_down then
                    if ony < any then anchor_vn = ovn end
                else
                    if ony > any then anchor_vn = ovn end
                end
            end
            anchor_nh = anchor_vn.notehead_type or "standard"
        end
        local attach_dx = Engraver.get_notehead_stem_attachment(anchor_nh, group_stem_down, s, true)
        local sx = onset.nominal_nx + attach_dx
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
    
    -- 4. Melodic slope according to Elaine Gould ("Behind Bars", p. 17–21):
    -- Damped beam slant (max 0.25 and max 10*s vertical rise) prevents beams from shooting steeply into the air:
    local y_first = group_stem_down and first_onset.max_ny or first_onset.min_ny
    local y_last  = group_stem_down and last_onset.max_ny or last_onset.min_ny
    local raw_slope = ((y_last - y_first) * 0.5) / dx
    local max_slope = math.min(0.25, (10.0 * s) / dx)
    local slope = math.max(-max_slope, math.min(max_slope, raw_slope))
    
    -- If melody fluctuates strongly (sharp direction changes without contour trend), keep horizontal
    local span_y = math.abs(y_last - y_first)
    local has_higher, has_lower = false, false
    for i = 2, #onsets - 1 do
        local mid_y = group_stem_down and onsets[i].max_ny or onsets[i].min_ny
        if mid_y < math.min(y_first, y_last) - 8*s then has_higher = true end
        if mid_y > math.max(y_first, y_last) + 8*s then has_lower = true end
    end
    if (has_higher and has_lower) or (span_y < 3 * s) then
        slope = 0
    end
    
    -- 5. Vertical position of primary beam (Elaine Gould "Behind Bars", pp. 14, 21-24:
    --    a) Stems on ledger-line notes pointing into the staff must reach at least the middle staff line dstep = 4.
    --    b) Each secondary beam beyond the 2nd (32nd, 64th) lengthens the stem by one beam_gap.
    --    c) The innermost beam must maintain at least 14*s clearance from every notehead in the group.)
    local max_flags = 1
    for _, onset in ipairs(onsets) do
        local fc = Engraver.get_flag_count(onset.dur_qn)
        if fc > max_flags then max_flags = fc end
    end

    local extra_beam_len = math.max(0, max_flags - 2) * beam_gap
    local std_stem_len = (30 * s) + extra_beam_len
    local min_inner_clearance = ((max_flags - 1) * beam_gap) + (14.0 * s)
    local min_req_stem_len = math.max(std_stem_len, min_inner_clearance)
    local step_y_approx = 4.0 * s
    local beam_y1
    
    if group_stem_down then
        local max_needed_y1 = -math.huge
        for _, onset in ipairs(onsets) do
            local cur_x = onset.stem_x
            local target_end_y = onset.max_ny + min_req_stem_len
            if onset.max_dstep and onset.max_dstep > 4 then
                local mid_line_y = onset.max_ny + (onset.max_dstep - 4) * step_y_approx
                if mid_line_y > target_end_y then
                    target_end_y = mid_line_y
                end
            end
            local needed_y1 = target_end_y - slope * (cur_x - x1)
            if needed_y1 > max_needed_y1 then max_needed_y1 = needed_y1 end
        end
        beam_y1 = max_needed_y1
    else
        local min_needed_y1 = math.huge
        for _, onset in ipairs(onsets) do
            local cur_x = onset.stem_x
            local target_end_y = onset.min_ny - min_req_stem_len
            if onset.min_dstep and onset.min_dstep < 4 then
                local mid_line_y = onset.min_ny + (onset.min_dstep - 4) * step_y_approx
                if mid_line_y < target_end_y then
                    target_end_y = mid_line_y
                end
            end
            local needed_y1 = target_end_y - slope * (cur_x - x1)
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
            if vn.orig then
                vn.orig._rendered_stem_down = group_stem_down
            end
            
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
    
    -- Secondary beam levels (Level 1: 16ths, Level 2: 32nds, Level 3: 64ths) across onsets
    for level = 1, max_flags - 1 do
        local offset_y = level * beam_gap * dir
        local seg_start = nil
        local function flush_secondary_segment(s_idx, e_idx)
            local count = e_idx - s_idx + 1
            if count >= 2 then
                local sx = onsets[s_idx].stem_x - (s_idx == 1 and half_stem or 0)
                local sy = (beam_y1 + slope * (sx - x1)) + offset_y
                local ex = onsets[e_idx].stem_x + (e_idx == #onsets and half_stem or 0)
                local ey = (beam_y1 + slope * (ex - x1)) + offset_y
                draw_beam_quad(sx, sy, ex, ey)
            elseif count == 1 then
                -- Elaine Gould ("Behind Bars", pp. 25, 155-158) & Gardner Read (p. 90):
                -- Fractional beam (stub / beamlet) must point toward its rhythmic partner
                -- within the same metric sub-unit (e.g., toward the paired dotted note).
                local stem_pos = onsets[s_idx].stem_x
                local stub_len = 9 * s
                local stub_dir = 1
                if s_idx == 1 then
                    stub_dir = 1
                elseif s_idx == #onsets then
                    stub_dir = -1
                else
                    local prev_o = onsets[s_idx - 1]
                    local next_o = onsets[s_idx + 1]
                    local prev_dotted = prev_o and Engraver.is_dotted_duration(prev_o.dur_qn)
                    local next_dotted = next_o and Engraver.is_dotted_duration(next_o.dur_qn)
                    if prev_dotted and not next_dotted then
                        stub_dir = -1
                    elseif next_dotted and not prev_dotted then
                        stub_dir = 1
                    else
                        local cur_q = onsets[s_idx].qn or onsets[s_idx].start_qn or 0
                        local on_half_beat = math.abs((cur_q * 2.0) - math.floor(cur_q * 2.0 + 0.5)) < 0.04
                        stub_dir = on_half_beat and 1 or -1
                    end
                end
                local sx, ex
                if stub_dir == 1 then
                    sx = stem_pos - (s_idx == 1 and half_stem or 0)
                    ex = stem_pos + stub_len
                else
                    sx = stem_pos + (s_idx == #onsets and half_stem or 0)
                    ex = stem_pos - stub_len
                end
                local sy = (beam_y1 + slope * (sx - x1)) + offset_y
                local ey = (beam_y1 + slope * (ex - x1)) + offset_y
                draw_beam_quad(sx, sy, ex, ey)
            end
        end

        for i, onset in ipairs(onsets) do
            local fc = Engraver.get_flag_count(onset.dur_qn)
            local has_gap = (i > 1) and ((onset.qn - (onsets[i-1].qn + onsets[i-1].dur_qn)) > 0.06)
            if seg_start and has_gap then
                flush_secondary_segment(seg_start, i - 1)
                seg_start = nil
            end
            if fc > level then
                if not seg_start then seg_start = i end
            else
                if seg_start then
                    flush_secondary_segment(seg_start, i - 1)
                    seg_start = nil
                end
            end
        end
        if seg_start then
            flush_secondary_segment(seg_start, #onsets)
        end
    end
    
    -- Record beamed notes
    local beamed_keys = {}
    for _, onset in ipairs(onsets) do
        for _, vn in ipairs(onset.notes) do
            if vn.key ~= nil then
                beamed_keys[vn.key] = true
            end
        end
    end
    return beamed_keys
end

-- ==============================================================================
-- NOTATION ELEMENT DRAW HELPERS (NOTEHEADS, ACCIDENTALS, TIES, ETC.)
-- ==============================================================================

function Engraver.draw_oval_notehead(draw_list, cx, cy, s, col, filled, is_whole, font_music, notehead_type)
    if notehead_type == "slash" then
        -- Single-staff-space percussion / rimshot slash notehead (SMuFL E100-E103 are 2-space comping slashes)
        local rx = (is_whole and 6.2 or 5.4) * s
        local ry = 4.2 * s
        local thick = 3.0 * s
        if filled and not is_whole and reaper.APIExists("ImGui_DrawList_AddQuadFilled") then
            reaper.ImGui_DrawList_AddQuadFilled(draw_list,
                cx - rx, cy + ry,
                cx - rx + thick, cy + ry,
                cx + rx, cy - ry,
                cx + rx - thick, cy - ry,
                col)
            return
        elseif reaper.APIExists("ImGui_DrawList_PathClear") then
            reaper.ImGui_DrawList_PathClear(draw_list)
            reaper.ImGui_DrawList_PathLineTo(draw_list, cx - rx, cy + ry)
            reaper.ImGui_DrawList_PathLineTo(draw_list, cx + rx - thick, cy - ry)
            reaper.ImGui_DrawList_PathLineTo(draw_list, cx + rx, cy - ry)
            reaper.ImGui_DrawList_PathLineTo(draw_list, cx - rx + thick, cy + ry)
            if filled and not is_whole then
                reaper.ImGui_DrawList_PathFillConvex(draw_list, col)
            else
                reaper.ImGui_DrawList_PathStroke(draw_list, col, reaper.ImGui_DrawFlags_Closed(), 1.6 * s)
            end
            return
        end
    end

    local font_sz = math.floor(((notehead_type == "square") and 34 or 40) * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local glyph
        local ox = is_whole and 8.4 or 5.9
        if notehead_type == "circle_x" then
            glyph = is_whole and (SMUFL.noteheadCircleXWhole or SMUFL.noteheadCircleX) or (filled and SMUFL.noteheadCircleX or (SMUFL.noteheadCircleXHalf or SMUFL.noteheadCircleX))
            ox = 5.0
        elseif notehead_type == "x" then
            glyph = is_whole and SMUFL.noteheadXWhole or (filled and SMUFL.noteheadXBlack or SMUFL.noteheadXHalf)
            ox = is_whole and 7.5 or (filled and 5.8 or 6.7)
        elseif notehead_type == "plus" then
            glyph = is_whole and SMUFL.noteheadPlusWhole or (filled and SMUFL.noteheadPlusBlack or SMUFL.noteheadPlusHalf)
            ox = is_whole and 5.7 or (filled and 5.0 or 5.2)
        elseif notehead_type == "triangle" then
            glyph = is_whole and SMUFL.noteheadTriangleUpWhole or (filled and SMUFL.noteheadTriangleUpBlack or SMUFL.noteheadTriangleUpHalf)
            ox = is_whole and 6.4 or 5.86
        elseif notehead_type == "triangle_down" then
            glyph = is_whole and SMUFL.noteheadTriangleDownWhole or (filled and SMUFL.noteheadTriangleDownBlack or SMUFL.noteheadTriangleDownHalf)
            ox = is_whole and 5.7 or 5.85
        elseif notehead_type == "diamond" then
            glyph = is_whole and (SMUFL.noteheadDiamondWhole or SMUFL.noteheadDiamondHalf) or (filled and SMUFL.noteheadDiamondBlack or SMUFL.noteheadDiamondHalf)
            ox = is_whole and 8.0 or (filled and 6.8 or 5.6)
        elseif notehead_type == "square" then
            glyph = (is_whole or not filled) and SMUFL.noteheadSquareWhite or SMUFL.noteheadSquareBlack
            ox = 5.3
        else
            glyph = is_whole and SMUFL.note_whole or (filled and SMUFL.note_black or SMUFL.note_half)
            ox = is_whole and 8.4 or 5.9
        end
        local pos_y = cy - (font_sz * 2.012)
        local pos_x = cx - ox * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, glyph)
        return
    end
    
    -- Fallback vector shapes for percussion and special noteheads
    if notehead_type == "x" or notehead_type == "circle_x" then
        local r = 5.0 * s
        reaper.ImGui_DrawList_AddLine(draw_list, cx - r, cy - r, cx + r, cy + r, col, 2.0 * s)
        reaper.ImGui_DrawList_AddLine(draw_list, cx - r, cy + r, cx + r, cy - r, col, 2.0 * s)
        if notehead_type == "circle_x" then
            reaper.ImGui_DrawList_AddCircle(draw_list, cx, cy, 6.5 * s, col, 0, 1.6 * s)
        end
        return
    elseif notehead_type == "plus" then
        local r = 5.2 * s
        reaper.ImGui_DrawList_AddLine(draw_list, cx - r, cy, cx + r, cy, col, 2.1 * s)
        reaper.ImGui_DrawList_AddLine(draw_list, cx, cy - r, cx, cy + r, col, 2.1 * s)
        if is_whole or not filled then
            reaper.ImGui_DrawList_AddCircle(draw_list, cx, cy, 6.2 * s, col, 0, 1.4 * s)
        end
        return
    elseif notehead_type == "triangle" then
        local r = 5.5 * s
        local p1x, p1y = cx, cy - r
        local p2x, p2y = cx - r * 1.1, cy + r * 0.8
        local p3x, p3y = cx + r * 1.1, cy + r * 0.8
        if filled and not is_whole then
            reaper.ImGui_DrawList_AddTriangleFilled(draw_list, p1x, p1y, p2x, p2y, p3x, p3y, col)
        else
            reaper.ImGui_DrawList_AddTriangle(draw_list, p1x, p1y, p2x, p2y, p3x, p3y, col, 1.8 * s)
        end
        return
    elseif notehead_type == "triangle_down" then
        local r = 5.5 * s
        local p1x, p1y = cx, cy + r
        local p2x, p2y = cx - r * 1.1, cy - r * 0.8
        local p3x, p3y = cx + r * 1.1, cy - r * 0.8
        if filled and not is_whole then
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
        if filled and not is_whole then
            reaper.ImGui_DrawList_PathFillConvex(draw_list, col)
        else
            reaper.ImGui_DrawList_PathStroke(draw_list, col, reaper.ImGui_DrawFlags_Closed(), 1.8 * s)
        end
        return
    elseif notehead_type == "slash" then
        local rx = 5.8 * s
        local ry = 4.6 * s
        if filled and not is_whole then
            reaper.ImGui_DrawList_AddLine(draw_list, cx - rx, cy + ry, cx + rx, cy - ry, col, 3.2 * s)
        else
            reaper.ImGui_DrawList_AddLine(draw_list, cx - rx, cy + ry - 1.5 * s, cx + rx - 2.0 * s, cy - ry - 1.5 * s, col, 1.6 * s)
            reaper.ImGui_DrawList_AddLine(draw_list, cx - rx + 2.0 * s, cy + ry + 1.5 * s, cx + rx, cy - ry + 1.5 * s, col, 1.6 * s)
        end
        return
    elseif notehead_type == "square" then
        local rx = 5.2 * s
        local ry = 3.8 * s
        if filled and not is_whole then
            reaper.ImGui_DrawList_AddRectFilled(draw_list, cx - rx, cy - ry, cx + rx, cy + ry, col)
        else
            reaper.ImGui_DrawList_AddRect(draw_list, cx - rx, cy - ry, cx + rx, cy + ry, col, 0, 0, 1.8 * s)
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

local SMUFL_TIME_SIG_DIGITS = {
    ["0"] = "\u{E080}",
    ["1"] = "\u{E081}",
    ["2"] = "\u{E082}",
    ["3"] = "\u{E083}",
    ["4"] = "\u{E084}",
    ["5"] = "\u{E085}",
    ["6"] = "\u{E086}",
    ["7"] = "\u{E087}",
    ["8"] = "\u{E088}",
    ["9"] = "\u{E089}",
}

function Engraver.get_time_signature_width(num, denom, s)
    local scale = s or 1.0
    local num_str = tostring(math.floor(tonumber(num) or 4))
    local den_str = tostring(math.floor(tonumber(denom) or 4))
    local max_digits = math.max(#num_str, #den_str)
    return (max_digits * 13.0 + 9.0) * scale
end

function Engraver.draw_time_signature(draw_list, x, bot_y, line_spacing, s, col, num, denom, font_music, font_main)
    local scale = s or 1.0
    local draw_col = col or 0x111111FF
    local lsp = line_spacing or (8.0 * scale)
    local top_y = bot_y - 4.0 * lsp
    local num_val = math.max(1, math.floor(tonumber(num) or 4))
    local den_val = math.max(1, math.floor(tonumber(denom) or 4))
    local num_str = tostring(num_val)
    local den_str = tostring(den_val)
    local max_digits = math.max(#num_str, #den_str)
    local digit_adv = 12.5 * scale
    local total_w = max_digits * digit_adv

    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local ts_sz = math.floor(32.0 * scale + 0.5)
        -- SMuFL timeSig0..9 sit 2 staff spaces tall centered on the baseline:
        -- Numerator sits in upper half of staff (lines 3..5, centered at top_y + 1*lsp),
        -- Denominator sits in lower half of staff (lines 1..3, centered at top_y + 3*lsp).
        local num_base_y = top_y + (1.0 * lsp) - (ts_sz * 2.012)
        local den_base_y = top_y + (3.0 * lsp) - (ts_sz * 2.012)

        local num_start_x = x + (total_w - (#num_str * digit_adv)) * 0.5
        for i = 1, #num_str do
            local ch = num_str:sub(i, i)
            local glyph = SMUFL_TIME_SIG_DIGITS[ch] or ch
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, ts_sz, num_start_x + (i - 1) * digit_adv, num_base_y, draw_col, glyph)
        end

        local den_start_x = x + (total_w - (#den_str * digit_adv)) * 0.5
        for i = 1, #den_str do
            local ch = den_str:sub(i, i)
            local glyph = SMUFL_TIME_SIG_DIGITS[ch] or ch
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, ts_sz, den_start_x + (i - 1) * digit_adv, den_base_y, draw_col, glyph)
        end
    else
        local fb_font = font_main or font_music
        local fb_sz = math.floor(15.0 * scale + 0.5)
        if fb_font and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            reaper.ImGui_DrawList_AddTextEx(draw_list, fb_font, fb_sz, x + 2 * scale, top_y - 1 * scale, draw_col, num_str)
            reaper.ImGui_DrawList_AddTextEx(draw_list, fb_font, fb_sz, x + 2 * scale, top_y + 2.0 * lsp - 1 * scale, draw_col, den_str)
        else
            reaper.ImGui_DrawList_AddText(draw_list, x + 2 * scale, top_y - 1 * scale, draw_col, num_str)
            reaper.ImGui_DrawList_AddText(draw_list, x + 2 * scale, top_y + 2.0 * lsp - 1 * scale, draw_col, den_str)
        end
    end

    return x + total_w + (6.0 * scale)
end

function Engraver.draw_dot(draw_list, cx, cy, s, col, font_music, dstep, step_y)
    -- Elaine Gould ("Behind Bars", p. 30): Augmentation dots on a staff line or ledger line (dstep % 2 == 0)
    -- must never sit on the line itself; they are placed in the space immediately above the line.
    local dot_y = cy
    if dstep and (dstep % 2 == 0) then
        local sy = step_y or (4.0 * s)
        dot_y = cy - sy
    end
    local font_sz = math.floor(40 * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local pos_y = dot_y - (font_sz * 2.012)
        local pos_x = cx + 8.5 * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, SMUFL.dot)
        return
    end
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, cx + 9*s, dot_y, 1.9*s, col)
end

-- Elaine Gould ("Behind Bars", pp. 115-122) & Gardner Read (p. 252):
-- Computes canonical articulation placement (above/below) and Y coordinate:
-- 1. Marcato (^), Harmonic (o), and Fermata always sit ABOVE the staff/note/stem.
-- 2. Staccato (.) and Tenuto (-) sit on the notehead side and NEVER sit on a staff line
--    (snapping into the center of the nearest staff space away from the notehead).
-- 3. Accent (>) sits outside the staff (or clear of staff lines) on the notehead side.
function Engraver.get_articulation_y(art_id, ny, dstep, stem_down, staff_top_y, staff_bottom_y, l_spacing, s, stem_end_y)
    local step_y = (l_spacing or (8.0 * s)) * 0.5
    local cur_staff_bot = staff_bottom_y or (ny + (dstep or 0) * step_y)
    local cur_staff_top = staff_top_y or (cur_staff_bot - 8.0 * step_y)
    local lsp = l_spacing or (8.0 * s)

    -- 1. Always-above markings: marcato (^), harmonic (o), fermata
    if art_id == "marcato" or art_id == "marc" or art_id == "harmonic" or art_id == "harm" or art_id == "flageolet" or art_id == "fermata" then
        local top_ref = math.min(cur_staff_top - (9.0 * s), ny - (13.0 * s))
        if (not stem_down) and stem_end_y then
            top_ref = math.min(top_ref, stem_end_y - (9.5 * s))
        end
        return top_ref, true
    end

    local is_above = (stem_down == true)

    -- 2. Accent (>): placed on the notehead side, always outside the 5-line staff
    if art_id == "accent" or art_id == "acc" then
        if is_above then
            local ay = math.min(cur_staff_top - (7.5 * s), ny - (12.5 * s))
            return ay, true
        else
            local ay = math.max(cur_staff_bot + (7.5 * s), ny + (13.0 * s))
            return ay, false
        end
    end

    -- 3. Staccatissimo (wedge): placed on notehead side, clearing staff lines
    if art_id == "staccatissimo" or art_id == "staccatiss" or art_id == "wedge" then
        local ay = is_above and (ny - 13.5 * s) or (ny + 14.5 * s)
        if ay >= cur_staff_top - 2.0 * s and ay <= cur_staff_bot + 2.0 * s then
            local rel_y = (cur_staff_bot - ay) / lsp
            local line_idx = math.floor(rel_y + 0.5)
            if line_idx >= 0 and line_idx <= 4 and math.abs(rel_y - line_idx) < 0.38 then
                if is_above then
                    ay = (line_idx >= 4) and (cur_staff_top - 6.0 * s) or (cur_staff_bot - (line_idx + 0.5) * lsp)
                else
                    ay = (line_idx <= 0) and (cur_staff_bot + 6.0 * s) or (cur_staff_bot - (line_idx - 0.5) * lsp)
                end
            end
        end
        return ay, is_above
    end

    -- 4. Staccato (.) and Tenuto (-): placed on notehead side, strictly centered in a staff space when inside the staff
    local base_off = (art_id == "tenuto" or art_id == "ten") and (10.5 * s) or (11.0 * s)
    local ay = is_above and (ny - base_off) or (ny + base_off + 1.0 * s)
    if ay >= cur_staff_top - 2.0 * s and ay <= cur_staff_bot + 2.0 * s then
        local rel_y = (cur_staff_bot - ay) / lsp
        local line_idx = math.floor(rel_y + 0.5)
        if line_idx >= 0 and line_idx <= 4 and math.abs(rel_y - line_idx) < 0.38 then
            if is_above then
                if line_idx >= 4 then
                    ay = cur_staff_top - 5.0 * s
                else
                    ay = cur_staff_bot - (line_idx + 0.5) * lsp
                end
            else
                if line_idx <= 0 then
                    ay = cur_staff_bot + 5.0 * s
                else
                    ay = cur_staff_bot - (line_idx - 0.5) * lsp
                end
            end
        end
    end
    return ay, is_above
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
        -- Pointed roof / hat ^ (Elaine Gould p. 117: always upright above the staff)
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

-- Elaine Gould ("Behind Bars", pp. 13, 502) & Gardner Read (p. 41):
-- Draws a classical curved accolade brace ({) to the left of Grand Staff / Harp systems,
-- paired with the vertical system line at x.
function Engraver.draw_piano_brace(draw_list, x, top_y, bottom_y, s, col)
    local brace_col = col or Constants.COLORS.staff_lines or 0x111111FF
    -- Vertical system line connecting the staves
    reaper.ImGui_DrawList_AddLine(draw_list, x, top_y, x, bottom_y, brace_col, 2.2 * s)

    local mid_y = (top_y + bottom_y) * 0.5
    local half_h = (bottom_y - top_y) * 0.5
    if half_h < 10 * s then return end

    local tip_x  = x - 1.5 * s
    local beak_x = x - 10.5 * s
    local belly_outer_x = x - 9.0 * s
    local belly_inner_x = x - 6.8 * s
    local waist_outer_x = x - 1.8 * s
    local waist_inner_x = x - 4.0 * s

    -- Upper half of accolade (top_y -> mid_y): paired Bezier curves for engraved calligraphic swell
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        tip_x, top_y,
        belly_outer_x, top_y + half_h * 0.22,
        waist_outer_x, top_y + half_h * 0.78,
        beak_x, mid_y,
        brace_col, 1.7 * s)
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        tip_x, top_y,
        belly_inner_x, top_y + half_h * 0.26,
        waist_inner_x, top_y + half_h * 0.74,
        beak_x, mid_y,
        brace_col, 1.7 * s)

    -- Lower half of accolade (bottom_y -> mid_y): symmetric mirror
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        tip_x, bottom_y,
        belly_outer_x, bottom_y - half_h * 0.22,
        waist_outer_x, bottom_y - half_h * 0.78,
        beak_x, mid_y,
        brace_col, 1.7 * s)
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        tip_x, bottom_y,
        belly_inner_x, bottom_y - half_h * 0.26,
        waist_inner_x, bottom_y - half_h * 0.74,
        beak_x, mid_y,
        brace_col, 1.7 * s)
end

function Engraver.draw_flags(draw_list, stem_x, stem_end_y, s, col, count, stem_down, font_music)
    -- Elaine Gould ("Behind Bars", p. 16): Flag height must match our 8.0*s staff space (font_sz = 32*s)
    -- so at least 6*s of clear space remains between the flag tip and the notehead.
    local font_sz = math.floor(32 * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local glyph = nil
        local extra_y = 0
        if count == 1 then
            glyph = stem_down and SMUFL.flag_8th_down or SMUFL.flag_8th_up
        elseif count == 2 then
            glyph = stem_down and SMUFL.flag_16th_down or SMUFL.flag_16th_up
        elseif count == 3 then
            glyph = stem_down and SMUFL.flag_32nd_down or SMUFL.flag_32nd_up
            extra_y = (stem_down and -5.2 or 4.8) * s
        elseif count >= 4 then
            glyph = stem_down and SMUFL.flag_64th_down or SMUFL.flag_64th_up
            extra_y = (stem_down and -11.8 or 11.1) * s
        end
        if glyph then
            local pos_y = (stem_end_y + extra_y) - (font_sz * 2.012)
            local pos_x = stem_x - 0.5 * s
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, glyph)
            return
        end
    end
    for f = 0, count - 1 do
        local flag_offset = f * 6.5 * s
        local fy = stem_down and (stem_end_y - flag_offset) or (stem_end_y + flag_offset)
        local dir = stem_down and -1 or 1
        reaper.ImGui_DrawList_AddBezierCubic(draw_list,
            stem_x, fy,
            stem_x + 7*s, fy + dir * 8*s,
            stem_x + 12*s, fy + dir * 4*s,
            stem_x + 5*s, fy + dir * 14*s,
            col, 1.8*s)
    end
end

function Engraver.draw_tie(draw_list, x1, y1, x2, y2, s, col, above, opt_thickness)
    local dist = x2 - x1
    if dist < 5.0 * s then return end
    if math.abs(y2 - y1) > 16 * s then return end
    
    -- Elaine Gould ("Behind Bars", pp. 60-66):
    -- 1. Adaptive endpoint inset so closely spaced notes never invert or form a vertical spike.
    -- 2. Tapered crescent profile: thin at the ends, gently thickened at the mid-arch apex.
    local inset = math.min(5.2 * s, math.max(2.2 * s, dist * 0.22))
    local start_x = x1 + inset
    local end_x   = x2 - inset
    local span = end_x - start_x
    if span < 3.0 * s then
        start_x = x1 + (dist * 0.15)
        end_x   = x2 - (dist * 0.15)
        span = math.max(2.5 * s, end_x - start_x)
    end

    local dir = above and -1 or 1
    -- Cap arch height relative to actual inner span so short ties stay flat and graceful, never spiky
    local arc_h = math.min(9.5 * s, math.min(span * 0.34, math.max(3.0 * s, span * 0.14)))
    local cp_offset = span * 0.28
    
    local tie_col = col or Constants.COLORS.tie_col or Constants.COLORS.notehead_black or 0x1A1A1AFF
    local start_y = y1 + dir * (3.6 * s)
    local end_y   = y2 + dir * (3.6 * s)
    local base_thick = opt_thickness or (1.5 * s)
    local crown_swell = dir * math.min(1.4 * s, math.max(0.8 * s, span * 0.04))

    -- Outer arch + inner arch create an authentic engraved crescent taper
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        start_x, start_y,
        start_x + cp_offset, start_y + (dir * arc_h) + crown_swell,
        end_x - cp_offset,   end_y + (dir * arc_h) + crown_swell,
        end_x, end_y,
        tie_col, base_thick)
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        start_x, start_y,
        start_x + cp_offset, start_y + (dir * arc_h),
        end_x - cp_offset,   end_y + (dir * arc_h),
        end_x, end_y,
        tie_col, base_thick)
end

function Engraver.draw_slur(draw_list, x1, y1, x2, y2, s, col, above, opt_thickness, opt_extra_offset_y, opt_extra_arc_h)
    local dist_x = x2 - x1
    if math.abs(dist_x) < 4 * s then return end
    
    local dx = dist_x
    local dy = y2 - y1
    local chord_len = math.sqrt(dx * dx + dy * dy)
    
    -- Elaine Gould ("Behind Bars", pp. 109-115): Slurs have a generous, tapered crescent arch.
    local inset = math.min(4.5 * s, math.max(2.0 * s, math.abs(dist_x) * 0.18))
    local start_x = x1 + inset
    local end_x   = x2 - inset
    local span = math.max(3.0 * s, math.abs(end_x - start_x))

    local base_arc_h = math.min(30.0 * s, math.min(span * 0.38, math.max(7.5 * s, chord_len * 0.15)))
    local extra_arc = opt_extra_arc_h or 0
    local arc_h = base_arc_h + extra_arc
    local dir = above and -1 or 1
    
    local extra_y = opt_extra_offset_y or 0
    local base_offset_y = 6.2 * s
    local start_y = y1 + dir * (base_offset_y + extra_y)
    local end_y   = y2 + dir * (base_offset_y + extra_y)
    
    local cp_dist = span * 0.28
    local cp1_x = start_x + cp_dist
    local cp1_y = start_y + dir * arc_h
    local cp2_x = end_x - cp_dist
    local cp2_y = end_y + dir * arc_h
    
    local slur_col = col or Constants.COLORS.slur_col or Constants.COLORS.tie_col or Constants.COLORS.notehead_black or 0x1A1A1AFF
    local base_thick = opt_thickness or (1.6 * s)
    local crown_swell = dir * math.min(1.6 * s, math.max(0.9 * s, span * 0.04))
    
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        start_x, start_y,
        cp1_x, cp1_y + crown_swell,
        cp2_x, cp2_y + crown_swell,
        end_x, end_y,
        slur_col, base_thick)
    reaper.ImGui_DrawList_AddBezierCubic(draw_list,
        start_x, start_y,
        cp1_x, cp1_y,
        cp2_x, cp2_y,
        end_x, end_y,
        slur_col, base_thick)
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

local function match_tuplet_span(onsets, i, n, qn_per_measure)
    if i + n - 1 <= #onsets then
        local ok, step = is_valid_tuplet(onsets, i, n, qn_per_measure)
        if ok then return true, step, n end
    end
    -- Also support composite tuplet groups where some notes span k * step (e.g. quarter-triplet + eighth-triplet = 2 + 1 = 3 units)
    local step_candidates = {
        [3] = { 1/3, 2/3, 1/6, 4/3 },
        [5] = { 1/5, 2/5, 4/5 },
        [6] = { 1/6, 1/3 },
        [7] = { 1/7, 2/7, 4/7 },
        [8] = { 0.1875, 0.3750 }
    }
    local cands = step_candidates[n]
    if not cands or i + 1 > #onsets then return false end
    local first_o = onsets[i]
    local m_first = math.floor((first_o.start_qn + 0.001) / qn_per_measure)
    for _, step in ipairs(cands) do
        local total_dur = n * step
        local beat_in_bar = (first_o.start_qn % qn_per_measure)
        local align_ok = true
        if math.abs(total_dur - 4.0) < 0.20 then
            if beat_in_bar > 0.10 and beat_in_bar < (qn_per_measure - 0.10) then align_ok = false end
        elseif math.abs(total_dur - 1.0) < 0.12 or math.abs(total_dur - 2.0) < 0.15 then
            local sub = beat_in_bar % 1.0
            if sub > 0.08 and sub < (1.0 - 0.08) then align_ok = false end
        elseif math.abs(total_dur - 0.5) < 0.08 then
            local sub = beat_in_bar % 0.5
            if sub > 0.06 and sub < (0.5 - 0.06) then align_ok = false end
        end
        if align_ok then
            local units_sum = 0
            local consumed = 0
            local cur_expected_qn = first_o.start_qn
            local valid_seq = true
            local has_unit_step = false
            for idx = i, math.min(#onsets, i + n - 1) do
                local o = onsets[idx]
                if math.floor((o.start_qn + 0.001) / qn_per_measure) ~= m_first then
                    valid_seq = false
                    break
                end
                if math.abs(o.start_qn - cur_expected_qn) > 0.045 then
                    valid_seq = false
                    break
                end
                local d = o.dur_qn or step
                local k = math.floor((d / step) + 0.5)
                if k < 1 or k >= n or math.abs(d - k * step) > math.max(0.035, step * 0.35) then
                    valid_seq = false
                    break
                end
                if k == 1 then has_unit_step = true end
                units_sum = units_sum + k
                consumed = consumed + 1
                cur_expected_qn = cur_expected_qn + k * step
                if units_sum == n then break end
                if units_sum > n then valid_seq = false break end
            end
            if valid_seq and units_sum == n and consumed >= 2 and has_unit_step then
                return true, step, consumed
            end
        end
    end
    return false
end

function Engraver.detect_and_draw_tuplets(draw_list, visual_notes, s, col, font_music, font_main, qn_per_measure, beam_groups, cull_min_x, cull_max_x, ghost_col)
    if not visual_notes or #visual_notes < 2 then return end

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
                                local cy = stem_down and (cy_beam + 14.5 * s) or (cy_beam - 14.5 * s)

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
        local vnx = vn.nominal_nx or vn.vis_nx or vn.nx or 0
        local vny = vn.vis_ny or vn.ny or 0
        local last = list[#list]
        if last and math.abs((vn.start_qn or 0) - last.start_qn) < 0.02 then
            table.insert(last.notes, vn)
            if vny < last.min_ny then last.min_ny = vny end
            if vny > last.max_ny then last.max_ny = vny end
        else
            table.insert(list, {
                start_qn = vn.start_qn or 0,
                dur_qn = vn.dur_qn or 0.5,
                notes = { vn },
                nominal_nx = vnx,
                min_ny = vny,
                max_ny = vny,
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
                local ok, step, consumed = match_tuplet_span(onset_list, i, n, qn_per_measure)
                if ok and consumed then
                    do
                        local first_o = onset_list[i]
                        local last_o = onset_list[i + consumed - 1]
                        local x1 = first_o.nominal_nx - 8.5 * s
                        local qn_span_o = math.max(0.10, (last_o.start_qn or 0) - (first_o.start_qn or 0))
                        local px_per_qn = math.max(36.0 * s, (last_o.nominal_nx - first_o.nominal_nx) / qn_span_o)
                        local last_dur = last_o.dur_qn or step or 0.25
                        local right_ext = math.min(28.0 * s, math.max(14.0 * s, last_dur * px_per_qn * 0.60))
                        local next_o = onset_list[i + consumed]
                        if next_o and next_o.nominal_nx and next_o.nominal_nx > last_o.nominal_nx then
                            local m_last = math.floor(((last_o.start_qn or 0) + 0.001) / qn_per_measure)
                            local m_next = math.floor(((next_o.start_qn or 0) + 0.001) / qn_per_measure)
                            if m_last == m_next then
                                right_ext = math.min(right_ext, math.max(9.0 * s, (next_o.nominal_nx - last_o.nominal_nx) - 8.0 * s))
                            end
                        end
                        local x2 = last_o.nominal_nx + right_ext
                        local dx = math.max(1.0, x2 - x1)
                        local cx = (x1 + x2) / 2.0

                        if not (cull_max_x and x1 > cull_max_x) and not (cull_min_x and x2 < cull_min_x) then
                            -- Helper function: determines highest optical point of an onset,
                            -- ensuring the tuplet bracket NEVER sits inside the 5-line staff (Gould p. 198)
                            -- and clears all noteheads, rhythm dots, tie arcs, up-stem tips and above-staff articulations.
                            local function get_onset_top(o)
                                local top_y = (o.min_ny or 0) - 6.0 * s
                                for _, vn in ipairs(o.notes) do
                                    local vny = vn.vis_ny or vn.ny
                                    if vny then
                                        local head_top = vny - 6.0 * s
                                        if head_top < top_y then top_y = head_top end
                                        if Engraver.is_dotted_duration(vn.dur_qn) then
                                            local dot_top = vny - 9.0 * s
                                            if dot_top < top_y then top_y = dot_top end
                                        end
                                        local has_tie = vn.is_segment or vn.is_tied_to_next or vn.is_tied_from_prev or (vn.orig and (vn.orig.is_tied_master or vn.orig.is_tied_slave))
                                        if has_tie and (vn.stem_down or (vn.dstep and vn.dstep >= 4)) then
                                            local tie_top = vny - 15.0 * s
                                            if tie_top < top_y then top_y = tie_top end
                                        end
                                    end
                                    if vn.dstep and vny then
                                        local staff_top_y = (vny + (vn.dstep - 8) * (4.0 * s)) - 6.0 * s
                                        if staff_top_y < top_y then top_y = staff_top_y end
                                    end
                                    if vn.stem_end_y and not vn.stem_down then
                                        if (vn.stem_end_y - 4.0 * s) < top_y then top_y = vn.stem_end_y - 4.0 * s end
                                    elseif vn.stem_down == nil and not vn.stem_end_y and vny then
                                        local est = vny - 34 * s
                                        if est < top_y then top_y = est end
                                    end
                                    if vn.art_y and vn.art_is_above and (vn.art_y - 6.0 * s) < top_y then
                                        top_y = vn.art_y - 6.0 * s
                                    end
                                end
                                return top_y
                            end

                            local y_first_top = get_onset_top(first_o)
                            local y_last_top  = get_onset_top(last_o)

                            -- Slant (slope) following note contour, clamped to max 10*s vertical tilt (Gould p. 198)
                            local raw_slope = (y_last_top - y_first_top) / dx
                            local max_slope = math.min(0.22, (10.0 * s) / dx)
                            local slope = math.max(-max_slope, math.min(max_slope, raw_slope))

                            -- If direction changes (convex/concave) -> horizontal
                            local has_higher, has_lower = false, false
                            for idx = i + 1, i + consumed - 2 do
                                local mid_top = get_onset_top(onset_list[idx])
                                if mid_top < math.min(y_first_top, y_last_top) - 2 * s then has_higher = true end
                                if mid_top > math.max(y_first_top, y_last_top) + 2 * s then has_lower = true end
                            end
                            if has_higher and has_lower then slope = 0 end

                            -- Calculate y1 ensuring at least clearance (18.0*s) distance at each onset
                            local clearance = 18.0 * s
                            local y1 = y_first_top - clearance
                            for idx = i, i + consumed - 1 do
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
                            for k = 0, consumed - 1 do
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

                        i = i + consumed
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

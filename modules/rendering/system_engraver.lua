-- ==============================================================================
-- REAPER Native Notator - Modul: SystemEngraver
-- Dedicated paginated score engraving engine matching ScoreCanvas 1:1.
-- Renders a multi-track system (e.g. 5 bars) with full music engraving fidelity:
--   - Authentic Bravura SMuFL noteheads, clefs, accidentals, dots & flags
--   - Gardner Read / Elaine Gould beaming via Engraver.calculate_and_draw_beams
--   - Ties across barlines via Engraver.get_visual_notes & Engraver.draw_tie
--   - Accurate Ganztaktpausen & beat-decomposed rests
--   - Grand Staff acoustic braces and continuous barlines
--   - Hairpins, score dynamics, pedal markings, text items & tempo markers
-- ==============================================================================

local Constants          = require("constants")
local SMUFL              = Constants.SMUFL
local Engraver           = require("rendering.engraver")
local HairpinService     = require("services.hairpin_service")
local PedalService       = require("services.pedal_service")
local TempoService       = require("services.tempo_service")
local TextItemService    = require("services.text_item_service")
local DynamicTextService = require("services.dynamic_text_service")
local RepeatService      = require("services.repeat_service")

local SystemEngraver = {}

-- ------------------------------------------------------------------------------
-- 1. Page-Level Measure Map Builder (strictly fits bars between margin_l & margin_r)
-- ------------------------------------------------------------------------------
function SystemEngraver.build_page_measure_map(active_tracks, start_m, end_m, margin_l, score_w, s, state_or_key)
    local page_bars = math.max(1, end_m - start_m)
    local bpi = 4.0
    local eng_s = s or 1.0
    local raw_widths = {}
    local total_raw = 0

    for bi = 0, page_bars - 1 do
        local m = start_m + bi
        local m_sqn = m * bpi
        local m_eqn = (m + 1) * bpi
        local note_density = 0
        local has_acc = false

        for _, tdata in ipairs(active_tracks) do
            for _, n in ipairs(tdata.notes or {}) do
                if n.start_qn >= (m_sqn - 0.001) and n.start_qn < (m_eqn - 0.001) then
                    note_density = note_density + 1
                    local p_mod = n.pitch % 12
                    if p_mod == 1 or p_mod == 3 or p_mod == 6 or p_mod == 8 or p_mod == 10 then
                        has_acc = true
                    end
                end
            end
        end

        -- Base weight according to Gardner Read spacing
        local weight = 1.0 + (math.min(16, note_density) * 0.12) + (has_acc and 0.15 or 0.0)

        raw_widths[bi] = weight
        total_raw = total_raw + weight
    end

    -- Dedicated Clef & Time Signature Reserve Area at start of system
    -- start_m == 0 has Clef + TimeSig (50 * eng_s); subsequent systems have Clef only (28 * eng_s)
    local key_idx = 0
    if type(state_or_key) == "number" then
        key_idx = state_or_key
    elseif type(state_or_key) == "table" then
        if state_or_key.key_signature then
            key_idx = state_or_key.key_signature
        end
    end
    if type(key_idx) == "table" then
        key_idx = key_idx.key_idx or key_idx.idx or 0
    end
    if (key_idx == 0 or key_idx == nil) and active_tracks then
        for _, trk in ipairs(active_tracks) do
            local trk_k = trk.key_sig or (trk.items and trk.items[1] and trk.items[1].key_sig)
            if type(trk_k) == "table" then
                trk_k = trk_k.key_idx or trk_k.idx or 0
            end
            if trk_k and type(trk_k) == "number" and math.abs(trk_k) > math.abs(key_idx or 0) then
                key_idx = trk_k
            end
        end
    end
    local key_sig_w = Engraver.get_key_signature_width(key_idx, eng_s)
    local clef_w = (start_m == 0 and 50.0 or 28.0) * eng_s + key_sig_w
    local avail_score_w = math.max(10.0, score_w - clef_w)
    local starts = {}
    local widths = {}
    local cur_x = margin_l + clef_w

    for bi = 0, page_bars - 1 do
        local w = (raw_widths[bi] / total_raw) * avail_score_w
        widths[bi] = w
        starts[bi] = cur_x
        cur_x = cur_x + w
    end
    starts[page_bars] = cur_x

    return {
        start_m = start_m,
        end_m = end_m,
        page_bars = page_bars,
        margin_l = margin_l,
        score_w = score_w,
        clef_w = clef_w,
        key_sig_w = key_sig_w,
        key_idx = key_idx,
        starts = starts,
        widths = widths,
        bpi = bpi
    }
end

-- ------------------------------------------------------------------------------
-- 2. QN to Page X Mapping using Page Measure Map
-- ------------------------------------------------------------------------------
function SystemEngraver.qn_to_page_x(qn, mmap, s)
    if not qn then return (mmap and mmap.margin_l) or 0 end
    local bpi = mmap.bpi or 4.0
    local m_idx = math.floor((qn + 0.0001) / bpi)
    local bi = m_idx - mmap.start_m

    if bi < 0 then
        return (mmap.starts and mmap.starts[0]) or mmap.margin_l
    elseif bi >= mmap.page_bars then
        return mmap.starts[mmap.page_bars]
    end

    local bx = mmap.starts[bi]
    local bw = mmap.widths[bi]
    local pad_l = 14.0 * (s or 1.0)
    local pad_r = 14.0 * (s or 1.0)
    local usable_w = math.max(10.0, bw - pad_l - pad_r)

    local qn_in_bar = qn - (m_idx * bpi)
    local frac = math.max(0.0, math.min(1.0, qn_in_bar / bpi))
    return bx + pad_l + (frac * usable_w)
end

-- ------------------------------------------------------------------------------
-- 3. Dynamic Glyphs Helper
-- ------------------------------------------------------------------------------
local function get_dyn_glyph_and_width(label, dyn_font_sz)
    local clean = (label or ""):lower():gsub("%s+", "")
    local glyph = SMUFL["dyn_" .. clean]
    local gw_units = Constants.DYN_GLYPH_WIDTHS and Constants.DYN_GLYPH_WIDTHS[clean]
    if not glyph and clean:match("^[pmfzsrn]+$") then
        local composed = ""
        local w_sum = 0
        local char_map = {
            p = SMUFL.dyn_p, m = SMUFL.dyn_m, f = SMUFL.dyn_f,
            z = utf8.char(0xE525), s = utf8.char(0xE524), r = utf8.char(0xE523), n = SMUFL.dyn_n
        }
        for c in clean:gmatch(".") do
            if char_map[c] then
                composed = composed .. char_map[c]
                w_sum = w_sum + (Constants.DYN_GLYPH_WIDTHS and Constants.DYN_GLYPH_WIDTHS[c] or 380)
            end
        end
        if #composed > 0 then
            glyph = composed
            if not gw_units then gw_units = w_sum end
        end
    end
    if not gw_units then gw_units = #clean * 380 end
    return glyph, (gw_units / 1000) * dyn_font_sz
end

-- ------------------------------------------------------------------------------
-- 4. Full System ImGui Drawing (matching ScoreCanvas 100%)
-- ------------------------------------------------------------------------------
function SystemEngraver.render_system_imgui(dl, ctx, active_tracks, start_m, end_m, bounds, s, fonts, state)
    local font_music = (fonts and fonts.font_music)
    local font_main  = (fonts and fonts.font_main)
    local eng_s      = s

    local page_bars = end_m - start_m
    local mmap = SystemEngraver.build_page_measure_map(active_tracks, start_m, end_m, bounds.margin_l, bounds.score_w, eng_s, state)

    local staff_ls = bounds.staff_ls or (8.0 * eng_s)
    local staff_h  = 4 * staff_ls
    local font_sz  = math.floor(40 * eng_s + 0.5)
    local col_ink  = 0x111111FF
    local col_line = 0x333333FF

    -- Master System Bracket on Left connecting all staves
    local overall_top = active_tracks[1] and (active_tracks[1].is_grand and active_tracks[1].upper_top or active_tracks[1].top_y) or bounds.top_y
    local last_t = active_tracks[#active_tracks]
    local overall_bot = last_t and (last_t.is_grand and last_t.lower_bot or last_t.bot_y) or bounds.bot_y

    reaper.ImGui_DrawList_AddLine(dl, bounds.margin_l - 6 * eng_s, overall_top, bounds.margin_l - 6 * eng_s, overall_bot, col_ink, 2.5 * eng_s)
    reaper.ImGui_DrawList_AddLine(dl, bounds.margin_l - 6 * eng_s, overall_top, bounds.margin_l - 1 * eng_s, overall_top, col_ink, 1.2 * eng_s)
    reaper.ImGui_DrawList_AddLine(dl, bounds.margin_l - 6 * eng_s, overall_bot, bounds.margin_l - 1 * eng_s, overall_bot, col_ink, 1.2 * eng_s)
    -- Initial System Barline connecting all staves at left margin
    reaper.ImGui_DrawList_AddLine(dl, bounds.margin_l, overall_top, bounds.margin_l, overall_bot, col_ink, 1.0 * eng_s)

    -- Measure numbers above top staff
    for bi = 0, page_bars - 1 do
        local bx = mmap.starts[bi]
        local m_num = start_m + bi + 1
        reaper.ImGui_DrawList_AddText(dl, bx + 2, overall_top - (14 * eng_s), col_ink, tostring(m_num))
    end

    -- Process each track
    for _, tdata in ipairs(active_tracks) do
        local is_grand = tdata.is_grand

        -- A. Track Name (right-aligned before margin_l)
        if bounds.show_track_names ~= false then
            local tw, th = reaper.ImGui_CalcTextSize(ctx, tdata.name)
            local tx = bounds.margin_l - (18 * eng_s) - tw
            reaper.ImGui_DrawList_AddText(dl, tx, tdata.center_y - (th * 0.5), col_ink, tdata.name)
        end

        if is_grand then
            -- === GRAND STAFF (PIANO / KEYBOARDS) ===
            -- Acoustic Accolade Brace on left
            local bx_bar = bounds.margin_l - 10 * eng_s
            reaper.ImGui_DrawList_AddLine(dl, bx_bar, tdata.upper_top, bx_bar, tdata.lower_bot, col_ink, 2.4 * eng_s)
            reaper.ImGui_DrawList_AddLine(dl, bx_bar, tdata.upper_top, bx_bar + 5 * eng_s, tdata.upper_top, col_ink, 1.2 * eng_s)
            reaper.ImGui_DrawList_AddLine(dl, bx_bar, tdata.lower_bot, bx_bar + 5 * eng_s, tdata.lower_bot, col_ink, 1.2 * eng_s)
            reaper.ImGui_DrawList_AddLine(dl, bx_bar - 4 * eng_s, tdata.center_y, bx_bar, tdata.center_y, col_ink, 1.5 * eng_s)

            -- 5 Lines Upper (Treble)
            for li = 0, 4 do
                local ly = tdata.upper_bot - (li * staff_ls)
                reaper.ImGui_DrawList_AddLine(dl, bounds.margin_l, ly, bounds.margin_l + bounds.score_w, ly, col_line, 0.9 * eng_s)
            end
            -- 5 Lines Lower (Bass)
            for li = 0, 4 do
                local ly = tdata.lower_bot - (li * staff_ls)
                reaper.ImGui_DrawList_AddLine(dl, bounds.margin_l, ly, bounds.margin_l + bounds.score_w, ly, col_line, 0.9 * eng_s)
            end

            -- Initial barline at left margin for Grand Staff
            reaper.ImGui_DrawList_AddLine(dl, bounds.margin_l, tdata.upper_top, bounds.margin_l, tdata.lower_bot, col_ink, 1.0 * eng_s)

            -- Barlines across both staves (continuous through Grand Staff)
            for bi = 1, page_bars do
                local bx = mmap.starts[bi]
                reaper.ImGui_DrawList_AddLine(dl, bx, tdata.upper_top, bx, tdata.lower_bot, col_ink, 1.0 * eng_s)
            end

            -- Clefs at start of system
            local clef_draw_x = bounds.margin_l + (4.0 * eng_s)
            local g4_y = tdata.upper_bot - staff_ls
            local f3_y = tdata.lower_bot - (3 * staff_ls)
            if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, clef_draw_x, g4_y - (font_sz * 2.012), col_ink, SMUFL.g_clef)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, clef_draw_x, f3_y - (font_sz * 2.012), col_ink, SMUFL.f_clef)
            else
                reaper.ImGui_DrawList_AddText(dl, clef_draw_x, g4_y - 6, col_ink, "𝄞")
                reaper.ImGui_DrawList_AddText(dl, clef_draw_x, f3_y - 6, col_ink, "𝄢")
            end

            -- Key Signature on all systems
            local key_idx = mmap.key_idx or 0
            if key_idx ~= 0 then
                local keysig_draw_x = bounds.margin_l + (24.0 * eng_s)
                Engraver.draw_key_signature(dl, key_idx, keysig_draw_x, tdata.upper_bot, staff_ls, eng_s, col_ink, font_music, "treble")
                Engraver.draw_key_signature(dl, key_idx, keysig_draw_x, tdata.lower_bot, staff_ls, eng_s, col_ink, font_music, "bass")
            end

            -- Time Signature on Bar 1 (Measure 1 of piece only)
            if start_m == 0 and font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                local ts_x = bounds.margin_l + (28.0 * eng_s) + (mmap.key_sig_w or 0)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, ts_x, (tdata.upper_bot - 2 * staff_ls) - (font_sz * 2.012), col_ink, SMUFL.timeSig4)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, ts_x, tdata.upper_bot - (font_sz * 2.012), col_ink, SMUFL.timeSig4)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, ts_x, (tdata.lower_bot - 2 * staff_ls) - (font_sz * 2.012), col_ink, SMUFL.timeSig4)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, ts_x, tdata.lower_bot - (font_sz * 2.012), col_ink, SMUFL.timeSig4)
            end

            -- Split Notes into Upper and Lower
            local upper_notes = {}
            local lower_notes = {}
            for _, n in ipairs(tdata.notes or {}) do
                if (n.pitch or 60) >= 60 then
                    table.insert(upper_notes, n)
                else
                    table.insert(lower_notes, n)
                end
            end

            SystemEngraver.render_staff_notes_imgui(dl, upper_notes, start_m, end_m, mmap, tdata.upper_bot, staff_ls, eng_s, font_music, font_main, "treble", state, tdata.guid, tdata.dynamics)
            SystemEngraver.render_staff_notes_imgui(dl, lower_notes, start_m, end_m, mmap, tdata.lower_bot, staff_ls, eng_s, font_music, font_main, "bass", state, tdata.guid, nil)

        else
            -- === SINGLE STAFF (TREBLE, BASS, ALTO) ===
            -- 5 Lines
            for li = 0, 4 do
                local ly = tdata.bot_y - (li * staff_ls)
                reaper.ImGui_DrawList_AddLine(dl, bounds.margin_l, ly, bounds.margin_l + bounds.score_w, ly, col_line, 0.9 * eng_s)
            end

            -- Initial barline at left margin
            reaper.ImGui_DrawList_AddLine(dl, bounds.margin_l, tdata.top_y, bounds.margin_l, tdata.bot_y, col_ink, 1.0 * eng_s)

            -- Barlines across this staff
            for bi = 1, page_bars do
                local bx = mmap.starts[bi]
                reaper.ImGui_DrawList_AddLine(dl, bx, tdata.top_y, bx, tdata.bot_y, col_ink, 1.0 * eng_s)
            end

            -- Clef at start of system
            local clef_draw_x = bounds.margin_l + (4.0 * eng_s)
            if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                if tdata.clef == "bass" then
                    local f3_y = tdata.bot_y - (3 * staff_ls)
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, clef_draw_x, f3_y - (font_sz * 2.012), col_ink, SMUFL.f_clef)
                elseif tdata.clef == "alto" then
                    local c4_y = tdata.bot_y - (2 * staff_ls)
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, clef_draw_x, c4_y - (font_sz * 2.012), col_ink, SMUFL.c_clef)
                else
                    local g4_y = tdata.bot_y - staff_ls
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, clef_draw_x, g4_y - (font_sz * 2.012), col_ink, SMUFL.g_clef)
                end
            else
                local clbl = (tdata.clef == "bass") and "𝄢" or ((tdata.clef == "alto") and "𝄡" or "𝄞")
                reaper.ImGui_DrawList_AddText(dl, clef_draw_x, tdata.center_y - 6, col_ink, clbl)
            end

            -- Key Signature on all systems
            local key_idx = mmap.key_idx or 0
            if key_idx ~= 0 then
                local keysig_draw_x = bounds.margin_l + (24.0 * eng_s)
                Engraver.draw_key_signature(dl, key_idx, keysig_draw_x, tdata.bot_y, staff_ls, eng_s, col_ink, font_music, tdata.clef or "treble")
            end

            -- Time Signature on Bar 1
            if start_m == 0 and font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                local ts_x = bounds.margin_l + (28.0 * eng_s) + (mmap.key_sig_w or 0)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, ts_x, (tdata.bot_y - 2 * staff_ls) - (font_sz * 2.012), col_ink, SMUFL.timeSig4)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, ts_x, tdata.bot_y - (font_sz * 2.012), col_ink, SMUFL.timeSig4)
            end

            SystemEngraver.render_staff_notes_imgui(dl, tdata.notes, start_m, end_m, mmap, tdata.bot_y, staff_ls, eng_s, font_music, font_main, tdata.clef, state, tdata.guid, tdata.dynamics)
        end
    end
end

-- ------------------------------------------------------------------------------
-- 5. Staff Notes & Notation Engraver (Identical to ScoreCanvas.lua)
-- ------------------------------------------------------------------------------
function SystemEngraver.render_staff_notes_imgui(dl, notes, start_m, end_m, mmap, staff_bot_y, staff_ls, eng_s, font_music, font_main, clef_type, state, track_guid, dynamics)
    local bpi = mmap.bpi or 4.0
    local start_qn_page = start_m * bpi
    local end_qn_page   = end_m * bpi
    local font_sz       = math.floor(40 * eng_s + 0.5)
    local step_y        = staff_ls * 0.5

    -- 1. Get Visual Notes & Ties using core Engraver module
    local raw_notes_in_range = {}
    for _, n in ipairs(notes or {}) do
        if n.start_qn < end_qn_page and (n.end_qn or (n.start_qn + (n.duration_qn or 1.0))) > start_qn_page then
            table.insert(raw_notes_in_range, n)
        end
    end

    local visual_notes, bar_ties = Engraver.get_visual_notes(raw_notes_in_range, bpi, start_qn_page, end_qn_page)

    -- Filter out repeated bars
    local display_notes = {}
    for _, vn in ipairs(visual_notes) do
        local note_bar = math.floor((vn.start_qn + 0.001) / bpi)
        if not RepeatService.has_repeat_mark(state, track_guid, note_bar) then
            table.insert(display_notes, vn)
        end
    end

    -- Compute positions and diatonic steps for each note
    for _, vn in ipairs(display_notes) do
        local pref_acc = Engraver.get_note_preferred_accidental(vn, state)
        local eff_pitch, active_oct, oct_shift = Engraver.get_note_effective_pitch(vn.pitch, vn.start_qn, track_guid, state)
        local ny, in_treble, dstep, acc, staff_target = Engraver.pitch_to_canvas_y(eff_pitch, staff_bot_y, staff_bot_y, step_y, false, clef_type, pref_acc, nil, mmap.key_idx)
        local nx = SystemEngraver.qn_to_page_x(vn.start_qn, mmap, eng_s)

        vn.nominal_nx = nx
        vn.vis_nx     = nx
        vn.vis_ny     = ny
        vn.dstep      = dstep
        vn.acc        = acc
        vn.in_treble  = in_treble
        vn.eff_pitch  = eff_pitch
        vn.active_octave_line = active_oct
        vn.key        = tostring(eff_pitch) .. "_" .. tostring(vn.start_qn)
    end

    -- Chord Cluster Collision & Notehead Offsetting (Seconds)
    table.sort(display_notes, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.02 then return a.start_qn < b.start_qn end
        return (a.eff_pitch or a.pitch or 60) < (b.eff_pitch or b.pitch or 60)
    end)

    local chord_clusters = {}
    local cur_cluster = nil
    for _, vn in ipairs(display_notes) do
        local same_time = cur_cluster and (math.abs(vn.start_qn - cur_cluster.start_qn) < 0.03)
        if not same_time then
            cur_cluster = { start_qn = vn.start_qn, notes = {} }
            table.insert(chord_clusters, cur_cluster)
        end
        table.insert(cur_cluster.notes, vn)
        vn.chord_cluster = cur_cluster
    end

    for _, cluster in ipairs(chord_clusters) do
        local cnotes = cluster.notes
        if #cnotes > 1 then
            local max_dist = -1
            local stem_down = false
            for _, vn in ipairs(cnotes) do
                local dist = math.abs(vn.dstep - 4)
                if dist > max_dist then
                    max_dist = dist
                    stem_down = (vn.dstep >= 4)
                end
            end
            cluster.stem_down = stem_down

            for i = 2, #cnotes do
                local prev = cnotes[i-1]
                local curr = cnotes[i]
                if math.abs(curr.dstep - prev.dstep) <= 1 then
                    curr.vis_nx = curr.vis_nx + (8.5 * eng_s)
                end
            end
        else
            cluster.stem_down = (cnotes[1].dstep >= 4)
        end
    end

    -- 2. Ganztaktpausen & Rests via core Engraver module (Voice-Separated)
    local track_rests = Engraver.generate_voice_rests(raw_notes_in_range, end_m, bpi, nil, start_m, end_m - 1)
    for _, r in ipairs(track_rests) do
        if r.measure_idx and r.measure_idx >= start_m and r.measure_idx < end_m then
            local bi = r.measure_idx - start_m
            local bx = mmap.starts[bi]
            local bw = mmap.widths[bi]
            local rx = r.is_full_measure and (bx + (bw * 0.5)) or SystemEngraver.qn_to_page_x(r.start_qn, mmap, eng_s)

            local y_line4 = staff_bot_y - (3 * staff_ls)
            local y_line3 = staff_bot_y - (2 * staff_ls)

            if r.type == "whole" then
                if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, rx - (5.6 * eng_s), y_line4 - (font_sz * 2.012), 0x111111FF, SMUFL.rest_whole)
                else
                    reaper.ImGui_DrawList_AddRectFilled(dl, rx - 6 * eng_s, y_line4, rx + 6 * eng_s, y_line4 + 4 * eng_s, 0x111111FF)
                end
            elseif r.type == "half" then
                if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, rx - (5.6 * eng_s), y_line3 - (font_sz * 2.012), 0x111111FF, SMUFL.rest_half)
                else
                    reaper.ImGui_DrawList_AddRectFilled(dl, rx - 6 * eng_s, y_line3 - 4 * eng_s, rx + 6 * eng_s, y_line3, 0x111111FF)
                end
            elseif r.type == "quarter" then
                if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, rx - (5.0 * eng_s), y_line3 - (font_sz * 2.012), 0x111111FF, SMUFL.rest_quarter)
                else
                    reaper.ImGui_DrawList_AddLine(dl, rx, y_line4, rx, staff_bot_y - staff_ls, 0x111111FF, 2.0 * eng_s)
                end
            elseif r.type == "8th" then
                if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, rx - (5.0 * eng_s), y_line3 - (font_sz * 2.012), 0x111111FF, SMUFL.rest_8th)
                end
            elseif r.type == "16th" then
                if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, font_sz, rx - (5.0 * eng_s), y_line3 - (font_sz * 2.012), 0x111111FF, SMUFL.rest_16th)
                end
            end
        end
    end

    -- 3. Beaming Engine (using core Engraver module)
    local beam_groups = Engraver.get_beam_groups(display_notes, bpi, "beat")
    local beamed_notes_map = {}
    for _, bgroup in ipairs(beam_groups) do
        local bmap = Engraver.calculate_and_draw_beams(dl, bgroup, eng_s, 0x111111FF, nil)
        if bmap then
            for k in pairs(bmap) do beamed_notes_map[k] = true end
        end
    end

    -- 4. Noteheads, Accidentals, Dots, Articulations & Ledger Lines
    local notes_by_key = {}
    for _, vn in ipairs(display_notes) do
        notes_by_key[vn.key] = vn
        local nx = vn.vis_nx
        local ny = vn.vis_ny

        local is_whole = (math.abs(vn.dur_qn - 4.0) < 0.15)
        local is_half  = (math.abs(vn.dur_qn - 2.0) < 0.15 or math.abs(vn.dur_qn - 3.0) < 0.15)

        -- Notehead via Bravura SMuFL
        Engraver.draw_oval_notehead(dl, nx, ny, eng_s, 0x111111FF, not (is_whole or is_half), is_whole, font_music, "standard")

        -- Accidental
        if vn.acc and vn.acc ~= 0 then
            Engraver.draw_accidental(dl, vn.acc, nx - 10 * eng_s, ny, eng_s, font_music, 0x111111FF)
        end

        -- Dot
        if Engraver.is_dotted_duration(vn.dur_qn) then
            Engraver.draw_dot(dl, nx, ny, eng_s, 0x111111FF, font_music)
        end

        -- Articulation
        if vn.orig and vn.orig.articulation then
            local is_above = vn.chord_cluster and vn.chord_cluster.stem_down or false
            local art_y = is_above and (ny - 12 * eng_s) or (ny + 14 * eng_s)
            Engraver.draw_articulation(dl, vn.orig.articulation, nx, art_y, eng_s, 0x111111FF, font_music, is_above)
        end

        -- Ledger Lines
        if vn.dstep <= -2 then
            for ls = -2, vn.dstep, -2 do
                local ly = staff_bot_y - (ls * step_y)
                reaper.ImGui_DrawList_AddLine(dl, nx - 8 * eng_s, ly, nx + 8 * eng_s, ly, 0x333333FF, 1.2 * eng_s)
            end
        elseif vn.dstep >= 10 then
            for ls = 10, vn.dstep, 2 do
                local ly = staff_bot_y - (ls * step_y)
                reaper.ImGui_DrawList_AddLine(dl, nx - 8 * eng_s, ly, nx + 8 * eng_s, ly, 0x333333FF, 1.2 * eng_s)
            end
        end
    end

    -- 5. Stems & Flags for Clusters
    for _, cluster in ipairs(chord_clusters) do
        local cnotes = cluster.notes
        local all_whole = true
        for _, vn in ipairs(cnotes) do
            if math.abs(vn.dur_qn - 4.0) >= 0.15 then all_whole = false break end
        end

        if not all_whole then
            local stem_down = cluster.stem_down
            local min_ny = cnotes[1].vis_ny
            local max_ny = cnotes[1].vis_ny
            local shortest_dur = cnotes[1].dur_qn
            local has_beamed = false

            for _, vn in ipairs(cnotes) do
                if vn.vis_ny < min_ny then min_ny = vn.vis_ny end
                if vn.vis_ny > max_ny then max_ny = vn.vis_ny end
                if vn.dur_qn < shortest_dur then shortest_dur = vn.dur_qn end
                if beamed_notes_map[vn.key] then has_beamed = true end
            end

            local beam_end_y = nil
            local beam_stem_x = nil
            local beam_down = nil
            for _, vn in ipairs(cnotes) do
                if vn.beam_stem_end_y then
                    beam_end_y = vn.beam_stem_end_y
                    beam_stem_x = vn.beam_stem_x
                    beam_down = vn.beam_stem_down
                    break
                end
            end

            local base_nx = cnotes[1].nominal_nx
            local stem_x, stem_start_y, stem_end_y

            if has_beamed and beam_end_y then
                stem_x = beam_stem_x or (base_nx + (beam_down and (-5.0 * eng_s) or (5.0 * eng_s)))
                stem_down = beam_down
                stem_start_y = stem_down and min_ny or max_ny
                stem_end_y = beam_end_y
            else
                local stem_len = 28 * eng_s
                stem_x = base_nx + (stem_down and (-5.0 * eng_s) or (5.0 * eng_s))
                stem_start_y = stem_down and min_ny or max_ny
                stem_end_y = stem_down and (max_ny + stem_len) or (min_ny - stem_len)
            end

            reaper.ImGui_DrawList_AddLine(dl, stem_x, stem_start_y, stem_x, stem_end_y, 0x111111FF, 1.4 * eng_s)

            local flag_count = Engraver.get_flag_count(shortest_dur)
            if flag_count > 0 and not has_beamed then
                Engraver.draw_flags(dl, stem_x, stem_end_y, eng_s, 0x111111FF, flag_count, stem_down, font_music)
            end
        end
    end

    -- 6. Ties across barlines (via Engraver.draw_tie)
    for _, bt in ipairs(bar_ties or {}) do
        local n1 = notes_by_key[bt.from_key]
        local n2 = notes_by_key[bt.to_key]
        if n1 and n2 then
            local above = (n1.dstep and n1.dstep >= 4)
            Engraver.draw_tie(dl, n1.vis_nx, n1.vis_ny, n2.vis_nx, n2.vis_ny, eng_s, 0x111111FF, above)
        end
    end

    -- 7. Dynamics (p, mp, mf, f, ff etc.)
    if dynamics and #dynamics > 0 then
        local dyn_font_sz = math.floor(30 * eng_s + 0.5)
        local dy = staff_bot_y + (16 * eng_s)
        for _, d in ipairs(dynamics) do
            if d.qn and d.qn >= (start_qn_page - 0.1) and d.qn < end_qn_page then
                local dx = SystemEngraver.qn_to_page_x(d.qn, mmap, eng_s)
                local glyph, dw = get_dyn_glyph_and_width(d.label, dyn_font_sz)
                if glyph and font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                    local pos_x = dx - (dw * 0.5)
                    local pos_y = dy - (dyn_font_sz * 2.012)
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, dyn_font_sz, pos_x, pos_y, 0x111111FF, glyph)
                else
                    local lbl = d.label or "f"
                    local tw, th = reaper.ImGui_CalcTextSize(reaper.ImGui_GetCurrentContext(), lbl)
                    reaper.ImGui_DrawList_AddText(dl, dx - (tw * 0.5), dy - (th * 0.5), 0x111111FF, lbl)
                end
            end
        end
    end

    -- 8. Hairpins (< and >)
    if track_guid and state then
        local track_hairpins = HairpinService.get_hairpins_for_track(state, track_guid)
        if track_hairpins and #track_hairpins > 0 then
            local hp_open_h = 4.2 * eng_s
            local hp_tip_h  = 0.5 * eng_s
            local hp_y_mid  = staff_bot_y + (15 * eng_s)

            for _, hp in ipairs(track_hairpins) do
                local cur_s = hp.start_qn or 0
                local cur_e = hp.end_qn or (cur_s + 1.0)
                if cur_e > start_qn_page and cur_s < end_qn_page then
                    local matches_staff = true
                    if clef_type == "treble" and hp.staff == "bass" then
                        matches_staff = false
                    elseif clef_type == "bass" and hp.staff == "treble" then
                        matches_staff = false
                    end

                    if matches_staff then
                        local raw_x1 = SystemEngraver.qn_to_page_x(math.max(start_qn_page, cur_s), mmap, eng_s)
                        local raw_x2 = SystemEngraver.qn_to_page_x(math.min(end_qn_page, cur_e), mmap, eng_s)
                        local x1 = raw_x1 + (4.0 * eng_s)
                        local x2 = math.max(x1 + (8.0 * eng_s), raw_x2 - (4.0 * eng_s))

                        if hp.type == "crescendo" then
                            reaper.ImGui_DrawList_AddLine(dl, x1, hp_y_mid - hp_tip_h, x2, hp_y_mid - hp_open_h, 0x111111FF, 1.4 * eng_s)
                            reaper.ImGui_DrawList_AddLine(dl, x1, hp_y_mid + hp_tip_h, x2, hp_y_mid + hp_open_h, 0x111111FF, 1.4 * eng_s)
                        else
                            reaper.ImGui_DrawList_AddLine(dl, x1, hp_y_mid - hp_open_h, x2, hp_y_mid - hp_tip_h, 0x111111FF, 1.4 * eng_s)
                            reaper.ImGui_DrawList_AddLine(dl, x1, hp_y_mid + hp_open_h, x2, hp_y_mid + hp_tip_h, 0x111111FF, 1.4 * eng_s)
                        end
                    end
                end
            end
        end

        -- 9. Dynamic Texts (cresc. / dim. etc.)
        local track_dtexts = DynamicTextService.get_dynamic_texts_for_track(state, track_guid)
        if track_dtexts and #track_dtexts > 0 then
            local dt_y = staff_bot_y + (16 * eng_s)
            for _, dt in ipairs(track_dtexts) do
                local cur_s = dt.start_qn or 0
                local cur_e = dt.end_qn or (cur_s + 1.0)
                if cur_e > start_qn_page and cur_s < end_qn_page then
                    local x1 = SystemEngraver.qn_to_page_x(math.max(start_qn_page, cur_s), mmap, eng_s)
                    local x2 = SystemEngraver.qn_to_page_x(math.min(end_qn_page, cur_e), mmap, eng_s)
                    local lbl = dt.text or dt.label or "cresc."
                    reaper.ImGui_DrawList_AddText(dl, x1, dt_y - (6 * eng_s), 0x111111FF, lbl)
                    if x2 > x1 + (30 * eng_s) then
                        local cx = x1 + (25 * eng_s)
                        while cx < x2 do
                            reaper.ImGui_DrawList_AddLine(dl, cx, dt_y, math.min(x2, cx + (6 * eng_s)), dt_y, 0x333333FF, 1.0 * eng_s)
                            cx = cx + (12 * eng_s)
                        end
                    end
                end
            end
        end

        -- 10. Octave Lines (8va, 8vb, 15ma, 15mb etc.)
        local OctaveService = require("services.octave_service")
        local track_oct_lines = (OctaveService and OctaveService.get_lines_for_track) and OctaveService.get_lines_for_track(state, track_guid) or {}
        for _, oline in ipairs(track_oct_lines) do
            local cur_s = oline.start_qn or 0
            local cur_e = oline.end_qn or (cur_s + 4.0)
            if cur_e > start_qn_page and cur_s < end_qn_page then
                local odef = Constants.OCTAVE_LINE_DEFS[oline.type] or Constants.OCTAVE_LINE_DEFS["8va"]
                local is_below = (odef and (odef.placement == "below" or odef.corner == "bottom")) or (oline.type and oline.type:find("vb") ~= nil)
                local o_y = is_below and (staff_bot_y + 14 * eng_s) or (staff_bot_y - 4 * staff_ls - 12 * eng_s)
                local ox1 = SystemEngraver.qn_to_page_x(math.max(start_qn_page, cur_s), mmap, eng_s)
                local ox2 = SystemEngraver.qn_to_page_x(math.min(end_qn_page, cur_e), mmap, eng_s)
                if ox2 > ox1 + 4 * eng_s then
                    local lbl = (odef and odef.label) or "8"
                    reaper.ImGui_DrawList_AddText(dl, ox1, o_y - 6 * eng_s, 0x111111FF, lbl)
                    local cur_lx = ox1 + 12 * eng_s
                    local dash_len = 5.0 * eng_s
                    local dash_gap = 3.5 * eng_s
                    while cur_lx + dash_len <= ox2 do
                        reaper.ImGui_DrawList_AddLine(dl, cur_lx, o_y, cur_lx + dash_len, o_y, 0x111111FF, 1.2 * eng_s)
                        cur_lx = cur_lx + dash_len + dash_gap
                    end
                    if cur_lx < ox2 then
                        reaper.ImGui_DrawList_AddLine(dl, cur_lx, o_y, ox2, o_y, 0x111111FF, 1.2 * eng_s)
                    end
                    local hook_len = (is_below and -6.0 or 6.0) * eng_s
                    reaper.ImGui_DrawList_AddLine(dl, ox2, o_y, ox2, o_y + hook_len, 0x111111FF, 1.2 * eng_s)
                end
            end
        end
    end
end

return SystemEngraver

-- ==============================================================================
-- REAPER Native Notator - UI: PrintModal
-- High-fidelity interactive print setup dialog matching the exact ScoreCanvas look.
-- Uses Engraver routines & Bravura SMuFL font for authentic publication engraving.
-- Features:
--   - Two-page spread & Single-page preview
--   - Grand Staff (Piano/Keyboards) with acoustic brace & joint barlines
--   - Authentic Bravura clefs, noteheads, accidentals & beams
--   - Right-aligned instrument names with zero element overlap
--   - Traditional classical cover sheet (Urtext / Breitkopf style)
--   - Word-wrapped orchestration notes page
--   - Pure-Lua vector PDF export with embedded Bravura OpenType font
-- ==============================================================================

local PrintSettingsService = require("services.print_settings_service")
local PdfExportService     = require("services.pdf_export_service")
local FontManager          = require("rendering.font_manager")
local Engraver             = require("rendering.engraver")
local Constants            = require("constants")
local SystemEngraver       = require("rendering.system_engraver")

local PrintModal = {}

-- Local state for modal interaction
local current_preview_page = 1
local show_export_dialog = false
local export_pdf_path = ""
local last_exported_pdf = nil

-- Diatonic step mapping for pitch (C=0, D=1, E=2, F=3, G=4, A=5, B=6)
local PITCH_TO_DIATONIC = {
    [0] = 0, [1] = 0, [2] = 1, [3] = 1, [4] = 2, [5] = 3,
    [6] = 3, [7] = 4, [8] = 4, [9] = 5, [10] = 5, [11] = 6
}

-- ------------------------------------------------------------------------------
-- Track clef & Grand Staff detector (matches ScoreCanvas rules)
-- ------------------------------------------------------------------------------
local function get_track_clef_mode(track, track_name, track_notes, state)
    return Engraver.get_track_clef(track, track_name, track_notes, state)
end

-- ------------------------------------------------------------------------------
-- Main Render Method
-- ------------------------------------------------------------------------------
function PrintModal.render(ctx, state, midi_service, project_tracks, fonts)
    if not state.show_print_modal then return end

    local font_music = (fonts and fonts.font_music) or FontManager.font_music

    -- Initialize print settings if not yet loaded
    if not state.print_settings then
        PrintSettingsService.load_settings(state)
    end
    local s = state.print_settings

    -- Main Modal Window
    reaper.ImGui_SetNextWindowSize(ctx, 1180, 780, reaper.ImGui_Cond_FirstUseEver())
    local win_flags = reaper.ImGui_WindowFlags_NoCollapse()
    local is_vis, is_open = reaper.ImGui_Begin(ctx, "🖨 Score Print & PDF Export Setup###PrintScoreModal", true, win_flags)

    if not is_open then
        state.show_print_modal = false
        reaper.ImGui_End(ctx)
        return
    end

    if is_vis then
        local content_w, content_h = reaper.ImGui_GetContentRegionAvail(ctx)

        -- ======================================================================
        -- 1. TOP TOOLBAR (Bars per Page, Paper, Orientation, View Mode, Navigator)
        -- ======================================================================
        local top_btn_h = 26

        -- Bars per Page (Standard: 5)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Bars / Page:")
        reaper.ImGui_SameLine(ctx, 0, 6)
        reaper.ImGui_SetNextItemWidth(ctx, 70)
        local cur_bpp = tonumber(s.bars_per_page) or 5
        local changed_bpp, new_bpp = reaper.ImGui_DragInt(ctx, "##BarsPerPage", cur_bpp, 0.1, 1, 16)
        if changed_bpp then
            s.bars_per_page = math.max(1, math.min(16, new_bpp))
            PrintSettingsService.save_settings(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Measures displayed per score page (Standard: 5 Bars)")
        end

        -- Paper Size
        reaper.ImGui_SameLine(ctx, 0, 16)
        reaper.ImGui_Text(ctx, "Paper:")
        reaper.ImGui_SameLine(ctx, 0, 6)
        reaper.ImGui_SetNextItemWidth(ctx, 80)
        if reaper.ImGui_BeginCombo(ctx, "##PaperSize", s.paper_size or "A4") then
            for _, pz in ipairs({ "A4", "A3", "Letter" }) do
                local is_sel = (s.paper_size == pz)
                if reaper.ImGui_Selectable(ctx, pz, is_sel) then
                    s.paper_size = pz
                    PrintSettingsService.save_settings(state)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        -- Orientation
        reaper.ImGui_SameLine(ctx, 0, 16)
        reaper.ImGui_Text(ctx, "Orientation:")
        reaper.ImGui_SameLine(ctx, 0, 6)
        reaper.ImGui_SetNextItemWidth(ctx, 110)
        local cur_ori_lbl = (s.orientation == "portrait") and "Portrait" or "Landscape"
        if reaper.ImGui_BeginCombo(ctx, "##Orientation", cur_ori_lbl) then
            if reaper.ImGui_Selectable(ctx, "Landscape (Score)", s.orientation ~= "portrait") then
                s.orientation = "landscape"
                PrintSettingsService.save_settings(state)
            end
            if reaper.ImGui_Selectable(ctx, "Portrait", s.orientation == "portrait") then
                s.orientation = "portrait"
                PrintSettingsService.save_settings(state)
            end
            reaper.ImGui_EndCombo(ctx)
        end

        -- View Mode Toggle (Two-Page Spread vs Single Page)
        reaper.ImGui_SameLine(ctx, 0, 16)
        local spread_lbl = s.two_page_spread and "📖 Two-Page Spread" or "📄 Single Page"
        if reaper.ImGui_Button(ctx, spread_lbl, 150, top_btn_h) then
            s.two_page_spread = not s.two_page_spread
            PrintSettingsService.save_settings(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Toggle between Two-Page Book Spread (facing pages) and Single Page preview")
        end

        -- Page Calculation
        local max_qn = 16.0
        for _, t in ipairs(project_tracks) do
            local _, _, _, _, t_max = midi_service.get_track_items_and_notes(t.track)
            max_qn = math.max(max_qn, t_max or 0.0)
        end
        local total_measures = math.max(1, math.ceil(max_qn / 4.0))
        local total_score_pages = math.ceil(total_measures / (s.bars_per_page or 5))

        local total_pages = total_score_pages
        if s.include_cover ~= false then total_pages = total_pages + 1 end
        if s.include_notes_page ~= false then total_pages = total_pages + 1 end
        current_preview_page = math.max(1, math.min(total_pages, current_preview_page))

        -- Page Navigator on the right
        reaper.ImGui_SameLine(ctx, 0, 24)
        if reaper.ImGui_Button(ctx, "◀ Prev", 60, top_btn_h) and current_preview_page > 1 then
            current_preview_page = s.two_page_spread and math.max(1, current_preview_page - 2) or (current_preview_page - 1)
        end

        reaper.ImGui_SameLine(ctx, 0, 6)
        local nav_txt = s.two_page_spread
            and string.format("Pages %d-%d / %d", current_preview_page, math.min(total_pages, current_preview_page + 1), total_pages)
            or string.format("Page %d / %d", current_preview_page, total_pages)
        reaper.ImGui_TextColored(ctx, 0x5BC0DEFF, nav_txt)

        reaper.ImGui_SameLine(ctx, 0, 6)
        if reaper.ImGui_Button(ctx, "Next ▶", 60, top_btn_h) and current_preview_page < total_pages then
            current_preview_page = s.two_page_spread and math.min(total_pages, current_preview_page + 2) or (current_preview_page + 1)
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- 2. MAIN SPLIT: Left Editor (340px) | Right Page Preview Canvas
        -- ======================================================================
        local rem_w, rem_h = reaper.ImGui_GetContentRegionAvail(ctx)
        local left_col_w = 340
        local bottom_bar_h = 42
        local main_area_h = rem_h - bottom_bar_h

        local child_border = reaper.APIExists("ImGui_ChildFlags_Borders") and reaper.ImGui_ChildFlags_Borders() or 1

        -- LEFT COLUMN: Metadata & Settings Editor
        if reaper.ImGui_BeginChild(ctx, "PrintSetupLeftPanel", left_col_w, main_area_h, child_border) then
            -- Section 1: Title Page Setup
            local open_cov = reaper.ImGui_CollapsingHeader(ctx, "📜 Page 1: Title Page (Cover)", reaper.ImGui_TreeNodeFlags_DefaultOpen())
            if open_cov then
                local cov_changed = false
                local chk_cov, inc_cov = reaper.ImGui_Checkbox(ctx, "Include Cover Sheet##chk", s.include_cover ~= false)
                if chk_cov then s.include_cover = inc_cov; cov_changed = true end

                reaper.ImGui_TextDisabled(ctx, "Piece Title:")
                reaper.ImGui_SetNextItemWidth(ctx, -1)
                local c_t, v_t = reaper.ImGui_InputText(ctx, "##TitleInp", s.title or "")
                if c_t then s.title = v_t; cov_changed = true end

                reaper.ImGui_TextDisabled(ctx, "Subtitle / Genre:")
                reaper.ImGui_SetNextItemWidth(ctx, -1)
                local c_st, v_st = reaper.ImGui_InputText(ctx, "##SubTitleInp", s.subtitle or "")
                if c_st then s.subtitle = v_st; cov_changed = true end

                reaper.ImGui_TextDisabled(ctx, "Composer:")
                reaper.ImGui_SetNextItemWidth(ctx, -1)
                local c_c, v_c = reaper.ImGui_InputText(ctx, "##ComposerInp", s.composer or "")
                if c_c then s.composer = v_c; cov_changed = true end

                reaper.ImGui_TextDisabled(ctx, "Arranger / Orchestrator:")
                reaper.ImGui_SetNextItemWidth(ctx, -1)
                local c_a, v_a = reaper.ImGui_InputText(ctx, "##ArrangerInp", s.arranger or "")
                if c_a then s.arranger = v_a; cov_changed = true end

                reaper.ImGui_TextDisabled(ctx, "Publication Year / Date:")
                reaper.ImGui_SetNextItemWidth(ctx, -1)
                local c_d, v_d = reaper.ImGui_InputText(ctx, "##DateInp", s.date or "")
                if c_d then s.date = v_d; cov_changed = true end

                reaper.ImGui_TextDisabled(ctx, "Copyright Notice:")
                reaper.ImGui_SetNextItemWidth(ctx, -1)
                local c_cp, v_cp = reaper.ImGui_InputText(ctx, "##CopyInp", s.copyright or "")
                if c_cp then s.copyright = v_cp; cov_changed = true end

                if cov_changed then
                    PrintSettingsService.save_settings(state)
                end
            end

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            -- Section 2: Orchestration Notes (Page 2)
            local open_notes = reaper.ImGui_CollapsingHeader(ctx, "🎼 Page 2: Orchestrator Notes", reaper.ImGui_TreeNodeFlags_DefaultOpen())
            if open_notes then
                local notes_changed = false
                local chk_not, inc_not = reaper.ImGui_Checkbox(ctx, "Include Notes Page##chk", s.include_notes_page ~= false)
                if chk_not then s.include_notes_page = inc_not; notes_changed = true end

                reaper.ImGui_TextDisabled(ctx, "Orchestrator & Performance Notes:")
                local c_nt, v_nt = reaper.ImGui_InputTextMultiline(ctx, "##OrchNotesInp", s.orchestrator_notes or "", -1, 130)
                if c_nt then s.orchestrator_notes = v_nt; notes_changed = true end

                if notes_changed then
                    PrintSettingsService.save_settings(state)
                end
            end

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            -- Section 3: Score Layout Options
            local open_score = reaper.ImGui_CollapsingHeader(ctx, "🎯 Score Layout Options")
            if open_score then
                local sc_changed = false
                local chk_mn, inc_mn = reaper.ImGui_Checkbox(ctx, "Show Measure Numbers", s.show_measure_nums ~= false)
                if chk_mn then s.show_measure_nums = inc_mn; sc_changed = true end

                local chk_tn, inc_tn = reaper.ImGui_Checkbox(ctx, "Show Track Names on Left", s.show_track_names ~= false)
                if chk_tn then s.show_track_names = inc_tn; sc_changed = true end

                if sc_changed then
                    PrintSettingsService.save_settings(state)
                end
            end

            reaper.ImGui_EndChild(ctx)
        end

        reaper.ImGui_SameLine(ctx, 0, 6)

        -- RIGHT COLUMN: High-Fidelity Page Preview Canvas
        local preview_w = rem_w - left_col_w - 8
        if reaper.ImGui_BeginChild(ctx, "PrintPagePreviewArea", preview_w, main_area_h, child_border) then
            local p_area_w, p_area_h = reaper.ImGui_GetContentRegionAvail(ctx)
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            local orig_x, orig_y = reaper.ImGui_GetCursorScreenPos(ctx)

            -- Calculate physical page aspect ratio
            local is_landscape = (s.orientation ~= "portrait")
            local page_ratio = is_landscape and (1.414) or (1.0 / 1.414)

            -- Available dimensions
            local avail_pw = p_area_w - 20
            local avail_ph = p_area_h - 20

            local is_two_page = s.two_page_spread and true or false
            local num_pages_shown = is_two_page and 2 or 1

            local target_page_w = (avail_pw - (is_two_page and 20 or 0)) / num_pages_shown
            local target_page_h = target_page_w / page_ratio

            if target_page_h > avail_ph then
                target_page_h = avail_ph
                target_page_w = target_page_h * page_ratio
            end

            -- Background canvas area
            reaper.ImGui_DrawList_AddRectFilled(dl, orig_x, orig_y, orig_x + p_area_w, orig_y + p_area_h, 0x1E2025FF)


            -- Helper to word-wrap multiline text to fit within max_w
            local function wrap_text_for_preview(ctx_w, text, max_w)
                local lines = {}
                if not text or text == "" then return lines end
                for paragraph in (text .. "\n"):gmatch("([^\r\n]*)\r?\n") do
                    if #paragraph == 0 then
                        table.insert(lines, "")
                    else
                        local cur_line = ""
                        for word in paragraph:gmatch("%S+") do
                            local test_line = (#cur_line == 0) and word or (cur_line .. " " .. word)
                            local tw, _ = reaper.ImGui_CalcTextSize(ctx_w, test_line)
                            if tw <= max_w or #cur_line == 0 then
                                cur_line = test_line
                            else
                                table.insert(lines, cur_line)
                                cur_line = word
                            end
                        end
                        if #cur_line > 0 then
                            table.insert(lines, cur_line)
                        end
                    end
                end
                return lines
            end

            -- Helper to draw a single simulated paper page
            local function draw_simulated_page(p_num, px, py, pw, ph)
                -- 1. Drop Shadow
                reaper.ImGui_DrawList_AddRectFilled(dl, px + 5, py + 6, px + pw + 5, py + ph + 6, 0x00000055, 3.0)

                -- 2. Paper Sheet (Parchment white)
                local paper_col = 0xFCFCFAFF
                reaper.ImGui_DrawList_AddRectFilled(dl, px, py, px + pw, py + ph, paper_col, 2.0)
                reaper.ImGui_DrawList_AddRect(dl, px, py, px + pw, py + ph, 0xCCCCCCFF, 2.0, 0, 1.0)

                local base_w = (s.orientation == "portrait") and 595.0 or 842.0
                local scale = math.max(0.6, pw / base_w)

                -- Content Rendering based on page type
                local is_cover = (s.include_cover ~= false and p_num == 1)
                local is_notes = (s.include_notes_page ~= false and ((s.include_cover ~= false and p_num == 2) or (s.include_cover == false and p_num == 1)))

                if is_cover then
                    -- === RENDER TRADITIONAL CLASSICAL COVER SHEET (PAGE 1) ===
                    local m_out = 16 * scale
                    local m_in  = 22 * scale
                    reaper.ImGui_DrawList_AddRect(dl, px + m_out, py + m_out, px + pw - m_out, py + ph - m_out, 0x222222FF, 0.0, 0, 1.0 * scale)
                    reaper.ImGui_DrawList_AddRect(dl, px + m_in, py + m_in, px + pw - m_in, py + ph - m_in, 0x222222FF, 0.0, 0, 2.5 * scale)

                    local cx = px + (pw * 0.5)

                    -- Publisher Header
                    local pub_str = "EDITION   NOTATOR   •   URTEXT"
                    local pub_w, _ = reaper.ImGui_CalcTextSize(ctx, pub_str)
                    reaper.ImGui_DrawList_AddText(dl, cx - (pub_w * 0.5), py + (ph * 0.14), 0x555555FF, pub_str)

                    -- Composer Name
                    local comp_str = (s.composer and s.composer ~= "") and s.composer:upper() or "COMPOSER"
                    local comp_w, _ = reaper.ImGui_CalcTextSize(ctx, comp_str)
                    reaper.ImGui_DrawList_AddText(dl, cx - (comp_w * 0.5), py + (ph * 0.28), 0x111111FF, comp_str)

                    -- Main Piece Title
                    local tit_str = (s.title and s.title ~= "") and s.title or "Full Orchestral Score"
                    local tit_w, _ = reaper.ImGui_CalcTextSize(ctx, tit_str)
                    local tit_y = py + (ph * 0.36)
                    reaper.ImGui_DrawList_AddText(dl, cx - (tit_w * 0.5), tit_y, 0x050505FF, tit_str)

                    -- Ornamental Divider with Rosette
                    local div_w = math.min(pw * 0.5, math.max(120 * scale, tit_w + 40 * scale))
                    local div_y = tit_y + (28 * scale)
                    reaper.ImGui_DrawList_AddLine(dl, cx - (div_w * 0.5), div_y, cx - (12 * scale), div_y, 0x222222FF, 1.2 * scale)
                    reaper.ImGui_DrawList_AddLine(dl, cx + (12 * scale), div_y, cx + (div_w * 0.5), div_y, 0x222222FF, 1.2 * scale)
                    reaper.ImGui_DrawList_AddCircleFilled(dl, cx, div_y, 3.0 * scale, 0x222222FF)

                    -- Subtitle
                    local sub_str = (s.subtitle and s.subtitle ~= "") and s.subtitle or "for Full Orchestra"
                    local sub_w, _ = reaper.ImGui_CalcTextSize(ctx, sub_str)
                    reaper.ImGui_DrawList_AddText(dl, cx - (sub_w * 0.5), div_y + (18 * scale), 0x444444FF, sub_str)

                    -- Score Format
                    local fmt_str = "PARTITUR   •   FULL ORCHESTRAL SCORE"
                    local fmt_w, _ = reaper.ImGui_CalcTextSize(ctx, fmt_str)
                    reaper.ImGui_DrawList_AddText(dl, cx - (fmt_w * 0.5), py + (ph * 0.56), 0x222222FF, fmt_str)

                    -- Arranger
                    if s.arranger and s.arranger ~= "" then
                        local arr_str = "Arranged by " .. s.arranger
                        local arr_w, _ = reaper.ImGui_CalcTextSize(ctx, arr_str)
                        reaper.ImGui_DrawList_AddText(dl, cx - (arr_w * 0.5), py + (ph * 0.63), 0x555555FF, arr_str)
                    end

                    -- Date & Copyright (safely placed ABOVE bottom inner border)
                    local d_str = s.date or os.date("%Y")
                    local dw, _ = reaper.ImGui_CalcTextSize(ctx, tostring(d_str))
                    local cp_str = s.copyright or string.format("© %s All Rights Reserved", d_str)
                    local cpw, _ = reaper.ImGui_CalcTextSize(ctx, cp_str)

                    local cp_y = py + ph - m_in - (18 * scale) - 14
                    local d_y  = cp_y - (18 * scale)
                    reaper.ImGui_DrawList_AddText(dl, cx - (dw * 0.5), d_y, 0x444444FF, tostring(d_str))
                    reaper.ImGui_DrawList_AddText(dl, cx - (cpw * 0.5), cp_y, 0x666666FF, cp_str)

                elseif is_notes then
                    -- === RENDER NOTES PAGE (PAGE 2) ===
                    local nh_txt = "INSTRUMENTATION & PERFORMANCE NOTES"
                    local nh_w, _ = reaper.ImGui_CalcTextSize(ctx, nh_txt)
                    local nh_y = py + (26 * scale)
                    reaper.ImGui_DrawList_AddText(dl, px + (pw * 0.5) - (nh_w * 0.5), nh_y, 0x111111FF, nh_txt)

                    local m_side = 28 * scale
                    local line_y = nh_y + (18 * scale)
                    reaper.ImGui_DrawList_AddLine(dl, px + m_side, line_y, px + pw - m_side, line_y, 0x333333FF, 1.0 * scale)

                    -- Distinct 2-column layout with zero overlap and full wrapping
                    local start_y = line_y + (16 * scale)
                    local col_gap = 18 * scale
                    local total_avail_w = pw - (2 * m_side)
                    local col_w = (total_avail_w - col_gap) * 0.5
                    local c1_x = px + m_side
                    local c2_x = c1_x + col_w + col_gap

                    -- Col 1: Cast
                    reaper.ImGui_DrawList_AddText(dl, c1_x, start_y, 0x111111FF, "ORCHESTRATION / CAST:")
                    reaper.ImGui_DrawList_AddLine(dl, c1_x, start_y + 14, c1_x + col_w, start_y + 14, 0x888888FF, 0.8 * scale)

                    local cy = start_y + (20 * scale)
                    local max_c1_tw = col_w - 6
                    for ti, t in ipairs(project_tracks) do
                        if cy > (py + ph - (45 * scale)) then break end
                        local _, tname = reaper.GetTrackName(t.track)
                        tname = (tname and tname ~= "") and tname or ("Track " .. ti)
                        local tname_l = tname:lower()
                        if not (tname_l:find("chord") or tname_l:find("akkord") or tname_l:find("scale track")) then
                            local full_lbl = "-  " .. tname
                            local tw, _ = reaper.ImGui_CalcTextSize(ctx, full_lbl)
                            if tw > max_c1_tw then
                                while #full_lbl > 6 and tw > max_c1_tw do
                                    full_lbl = full_lbl:sub(1, #full_lbl - 2)
                                    tw, _ = reaper.ImGui_CalcTextSize(ctx, full_lbl .. "...")
                                end
                                full_lbl = full_lbl .. "..."
                            end
                            reaper.ImGui_DrawList_AddText(dl, c1_x + 4, cy, 0x333333FF, full_lbl)
                            cy = cy + 15
                        end
                    end

                    -- Col 2: Notes (Word-wrapped to fit column width)
                    reaper.ImGui_DrawList_AddText(dl, c2_x, start_y, 0x111111FF, "PERFORMANCE & EDITORIAL NOTES:")
                    reaper.ImGui_DrawList_AddLine(dl, c2_x, start_y + 14, c2_x + col_w, start_y + 14, 0x888888FF, 0.8 * scale)

                    local ny_cur = start_y + (20 * scale)
                    local note_lines = s.orchestrator_notes or "Score in C (Concert Pitch).\nAll instruments sound as written."
                    local wrapped_lines = wrap_text_for_preview(ctx, note_lines, col_w - 6)
                    for _, line in ipairs(wrapped_lines) do
                        if ny_cur > (py + ph - (45 * scale)) then break end
                        if #line > 0 then
                            reaper.ImGui_DrawList_AddText(dl, c2_x + 4, ny_cur, 0x333333FF, line)
                        end
                        ny_cur = ny_cur + 15
                    end

                    -- Footer
                    local p2_w, _ = reaper.ImGui_CalcTextSize(ctx, "- 2 -")
                    reaper.ImGui_DrawList_AddText(dl, px + (pw * 0.5) - (p2_w * 0.5), py + ph - (22 * scale), 0x555555FF, "- 2 -")

                else
                    -- === RENDER PAGINATED SCORE PAGE (PAGE 3+) ===
                    local page_offset = 0
                    if s.include_cover ~= false then page_offset = page_offset + 1 end
                    if s.include_notes_page ~= false then page_offset = page_offset + 1 end
                    local score_page_idx = math.max(1, p_num - page_offset)

                    local bpp = tonumber(s.bars_per_page) or 5
                    local start_m = (score_page_idx - 1) * bpp
                    local end_m = math.min(total_measures, start_m + bpp)
                    local page_bars = math.max(1, end_m - start_m)

                    -- Running Header (placed safely above score)
                    reaper.ImGui_DrawList_AddText(dl, px + (35 * scale), py + (16 * scale), 0x666666FF, s.title or "Score")
                    reaper.ImGui_DrawList_AddText(dl, px + pw - (65 * scale), py + (16 * scale), 0x444444FF, string.format("- %d -", p_num))

                    -- Build structured track & staff layout
                    local top_y = py + (42 * scale)
                    local bot_y = py + ph - (30 * scale)
                    local avail_h = bot_y - top_y

                    local track_layout = {}
                    local total_staves = 0
                    local grand_count = 0
                    local max_tw = 110 * scale

                    for ti, t in ipairs(project_tracks) do
                        local _, tname = reaper.GetTrackName(t.track)
                        tname = (tname and tname ~= "") and tname or ("Track " .. ti)
                        local tname_l = tname:lower()
                        if not (tname_l:find("chord") or tname_l:find("akkord") or tname_l:find("scale track")) then
                            local items, trk_notes, trk_dyns = midi_service.get_track_items_and_notes(t.track)
                            local clef_mode = get_track_clef_mode(t.track, tname, trk_notes, state)
                            local is_grand = (clef_mode == "grand")

                            total_staves = total_staves + (is_grand and 2 or 1)
                            if is_grand then grand_count = grand_count + 1 end

                            local tw, _ = reaper.ImGui_CalcTextSize(ctx, tname)
                            if tw > max_tw then max_tw = tw end

                            table.insert(track_layout, {
                                track = t.track,
                                guid = reaper.GetTrackGUID(t.track),
                                name = tname,
                                clef = clef_mode,
                                is_grand = is_grand,
                                notes = trk_notes or {},
                                dynamics = trk_dyns or {}
                            })
                        end
                    end

                    local margin_l = px + max_tw + (26 * scale)
                    local margin_r = px + pw - (20 * scale)
                    local sc_w = margin_r - margin_l
                    local bar_w = sc_w / page_bars

                    if total_staves == 0 then total_staves = 1 end

                    -- Proportional staff heights matching ScoreCanvas
                    local staff_ls = 5.6 * scale
                    local staff_h = 4 * staff_ls
                    local grand_gap = 26 * scale
                    local n_gaps = math.max(1, #track_layout - 1)
                    local used_h = (total_staves * staff_h) + (grand_count * grand_gap)
                    local inter_gap = math.max(14 * scale, (avail_h - used_h) / n_gaps)

                    if (used_h + (inter_gap * n_gaps)) > avail_h then
                        staff_ls = math.max(3.2 * scale, (avail_h / total_staves) * 0.16)
                        staff_h = 4 * staff_ls
                        grand_gap = staff_h * 1.1
                        used_h = (total_staves * staff_h) + (grand_count * grand_gap)
                        inter_gap = math.max(10 * scale, (avail_h - used_h) / n_gaps)
                    end

                    -- Compute staff vertical positions
                    local cur_y = top_y
                    for _, tl in ipairs(track_layout) do
                        if tl.is_grand then
                            tl.upper_top = cur_y
                            tl.upper_bot = cur_y + staff_h
                            tl.lower_top = tl.upper_bot + grand_gap
                            tl.lower_bot = tl.lower_top + staff_h
                            tl.center_y  = (tl.upper_bot + tl.lower_top) * 0.5
                            cur_y        = tl.lower_bot + inter_gap
                        else
                            tl.top_y    = cur_y
                            tl.bot_y    = cur_y + staff_h
                            tl.center_y = cur_y + (staff_h * 0.5)
                            cur_y       = tl.bot_y + inter_gap
                        end
                    end

                    local overall_top = track_layout[1] and (track_layout[1].is_grand and track_layout[1].upper_top or track_layout[1].top_y) or top_y
                    local last_tl = track_layout[#track_layout]
                    local overall_bot = last_tl and (last_tl.is_grand and last_tl.lower_bot or last_tl.bot_y) or bot_y

                    -- Engraver zoom parameter s (line_spacing = 8 * s, so s = staff_ls / 8.0)
                    local eng_s = staff_ls / 8.0
                    local fonts_table = {
                        font_music = font_music,
                        font_main = nil
                    }

                    -- Dedicated SystemEngraver matching ScoreCanvas 1:1
                    SystemEngraver.render_system_imgui(dl, ctx, track_layout, start_m, end_m, {
                        margin_l = margin_l,
                        score_w = sc_w,
                        top_y = overall_top,
                        bot_y = overall_bot,
                        staff_ls = staff_ls,
                        show_track_names = (s.show_track_names ~= false)
                    }, eng_s, fonts_table, state)
                end
            end

            -- Center pages inside the available preview canvas
            local center_start_y = orig_y + ((avail_ph - target_page_h) * 0.5)

            if is_two_page then
                -- Render 2 facing pages side by side
                local total_spread_w = (2 * target_page_w) + 16
                local center_start_x = orig_x + ((p_area_w - total_spread_w) * 0.5)

                -- Left Page
                draw_simulated_page(current_preview_page, center_start_x, center_start_y, target_page_w, target_page_h)

                -- Book Spine / Center Gutter
                local gutter_x = center_start_x + target_page_w
                reaper.ImGui_DrawList_AddRectFilled(dl, gutter_x, center_start_y, gutter_x + 16, center_start_y + target_page_h, 0x22252BFF)

                -- Right Page
                if current_preview_page + 1 <= total_pages then
                    draw_simulated_page(current_preview_page + 1, gutter_x + 16, center_start_y, target_page_w, target_page_h)
                else
                    -- Blank back page
                    reaper.ImGui_DrawList_AddRectFilled(dl, gutter_x + 16, center_start_y, gutter_x + 16 + target_page_w, center_start_y + target_page_h, 0x2A2D35FF, 2.0)
                    reaper.ImGui_DrawList_AddText(dl, gutter_x + 16 + (target_page_w * 0.4), center_start_y + (target_page_h * 0.5), 0x666666FF, "(End of Score)")
                end
            else
                -- Single Page View
                local center_start_x = orig_x + ((p_area_w - target_page_w) * 0.5)
                draw_simulated_page(current_preview_page, center_start_x, center_start_y, target_page_w, target_page_h)
            end

            reaper.ImGui_EndChild(ctx)
        end

        -- ======================================================================
        -- 3. BOTTOM ACTION BAR (File Path, Save XML, Export PDF Button)
        -- ======================================================================
        reaper.ImGui_Separator(ctx)
        local xml_path, has_proj = PrintSettingsService.get_project_xml_path()
        local fname = xml_path:match("([^/\\]+)$") or "settings.xml"

        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_TextColored(ctx, 0x888888FF, string.format("📁 XML Settings: %s", fname))

        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        reaper.ImGui_SameLine(ctx, avail_w - 360)

        -- Save Settings Button
        if reaper.ImGui_Button(ctx, "💾 Save Settings (XML)", 165, 30) then
            PrintSettingsService.save_settings(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Save all title, composer, notes, and layout settings to XML next to REAPER project file.")
        end

        reaper.ImGui_SameLine(ctx, 0, 10)

        -- Export PDF Button
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
        if reaper.ImGui_Button(ctx, "🖨 Export Score as PDF...", 185, 30) then
            show_export_dialog = true
            export_pdf_path = PrintSettingsService.get_default_pdf_path()
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Export complete score as publishing-quality vector PDF with embedded Bravura OpenType font.")
        end

        -- ======================================================================
        -- 4. EXPORT PDF FILE DIALOG POPUP
        -- ======================================================================
        if show_export_dialog then
            reaper.ImGui_OpenPopup(ctx, "ExportPdfDialog")
        end

        if reaper.ImGui_BeginPopupModal(ctx, "ExportPdfDialog", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Export Score as PDF Document (Bravura OpenType)")
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            reaper.ImGui_Text(ctx, "Target PDF File Path:")
            reaper.ImGui_SetNextItemWidth(ctx, 520)
            local changed_p, new_p = reaper.ImGui_InputText(ctx, "##PdfPathInput", export_pdf_path)
            if changed_p then export_pdf_path = new_p end

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_TextDisabled(ctx, string.format("Pages to generate: %d (Cover: %s, Notes: %s, Score: %d pages @ 5 bars/page)",
                total_pages, s.include_cover ~= false and "Yes" or "No", s.include_notes_page ~= false and "Yes" or "No", total_score_pages))

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            if reaper.ImGui_Button(ctx, "Cancel", 110, 28) then
                show_export_dialog = false
                reaper.ImGui_CloseCurrentPopup(ctx)
            end

            reaper.ImGui_SameLine(ctx, 0, 10)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
            if reaper.ImGui_Button(ctx, "🖨 Generate PDF Now", 180, 28) then
                local ok, out_path, num_p = PdfExportService.export_score_to_pdf(state, midi_service, project_tracks, export_pdf_path)
                if ok then
                    last_exported_pdf = out_path
                    PrintSettingsService.save_settings(state)
                    show_export_dialog = false
                    reaper.ImGui_CloseCurrentPopup(ctx)
                end
            end
            reaper.ImGui_PopStyleColor(ctx, 2)

            if last_exported_pdf then
                reaper.ImGui_SameLine(ctx, 0, 10)
                if reaper.ImGui_Button(ctx, "▶ Open in PDF Viewer", 170, 28) then
                    PdfExportService.open_in_system_viewer(last_exported_pdf)
                end
            end

            reaper.ImGui_EndPopup(ctx)
        end

        reaper.ImGui_End(ctx)
    end
end

return PrintModal

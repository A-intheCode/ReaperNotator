-- ==============================================================================
-- REAPER Native Notator - UI: PatternBrowser
-- Collapsible bottom pane with mini-score preview (4-8 measures),
-- drag & drop into canvas, audio preview via selectable REAPER track
-- and REAPER MIDI item export
-- ==============================================================================

local Constants = require("constants")
local SMUFL = Constants.SMUFL
local PatternService = require("services.pattern_service")

local PatternBrowser = {}

-- Modal dialog state
local capture_modal_open = false
local capture_name_buf = "My Pattern"
local capture_category_idx = 0
local capture_bars_idx = 0 -- 0 = 4 measures, 1 = 8 measures

local new_folder_modal_open = false
local new_folder_name_buf = "New Folder"

local preview_track_idx = 0

--- Draws a crisp 4-8 measure miniature score into the given rectangle
--- @param draw_list ImDrawList
--- @param pattern table
--- @param x number
--- @param y number
--- @param w number
--- @param h number
--- @param font_music ImFont
local function draw_mini_score(draw_list, pattern, x, y, w, h, font_music, zoom)
    local z = zoom or 1.0
    -- Background of the preview area
    local bg_col = 0x181A20FF
    local border_col = 0x333745FF
    reaper.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, bg_col, 4.0)
    reaper.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h, border_col, 4.0)
    
    local line_col = 0x666D8055
    local bar_col = 0x8892B066
    local note_col = 0xE6EDF3FF
    local staccato_col = 0xF39C12FF
    
    -- Grand Staff geometry (Treble + Bass)
    local step_y = math.max(2.4, math.min(5.0, 3.2 * z))
    local half_step_y = step_y * 0.5
    local staff_h = 4 * step_y
    local inter_staff_gap = math.max(6.0, 9.0 * z)
    
    local total_staves_h = (2 * staff_h) + inter_staff_gap
    local treble_top_y = y + math.max(4.0, math.floor((h - total_staves_h) / 2))
    local treble_bot_y = treble_top_y + staff_h
    local bass_top_y = treble_bot_y + inter_staff_gap
    local bass_bot_y = bass_top_y + staff_h
    
    -- Left brace/bracket line (Grand Staff bracket line)
    reaper.ImGui_DrawList_AddLine(draw_list, x + 4, treble_top_y, x + 4, bass_bot_y, bar_col, 1.8)
    
    -- 5 staff lines for upper staff (treble clef)
    for l = 0, 4 do
        local ly = treble_top_y + (l * step_y)
        reaper.ImGui_DrawList_AddLine(draw_list, x + 4, ly, x + w - 3, ly, line_col, 1.0)
    end
    
    -- 5 staff lines for lower staff (bass clef)
    for l = 0, 4 do
        local ly = bass_top_y + (l * step_y)
        reaper.ImGui_DrawList_AddLine(draw_list, x + 4, ly, x + w - 3, ly, line_col, 1.0)
    end
    
    local clef_w = math.max(14.0, math.floor(18.0 * z))
    local clef_font_sz = math.floor(math.max(12.0, math.min(22.0, 16.0 * z)))
    
    -- Upper clef (G-Clef 𝄞) & lower (F-Clef 𝄢)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local g_char = SMUFL.g_clef or "𝄞"
        local f_char = SMUFL.f_clef or "𝄢"
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, clef_font_sz, x + 5, treble_top_y - (4.5 * z), 0xD0D7DEEE, g_char)
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, clef_font_sz, x + 5, bass_top_y - (1.5 * z), 0xD0D7DEEE, f_char)
    else
        reaper.ImGui_DrawList_AddText(draw_list, x + 6, treble_top_y, 0xD0D7DEEE, "G")
        reaper.ImGui_DrawList_AddText(draw_list, x + 6, bass_top_y, 0xD0D7DEEE, "F")
    end
    
    -- Measure bar lines (supports 4, 8, 16 or more measures robustly)
    local bars = math.max(1, pattern.bars or 4)
    local score_x0 = x + clef_w + 4
    local score_w = math.max(10.0, w - clef_w - 8)
    local bar_w = math.max(2.0, score_w / bars)
    
    for b = 1, bars do
        local bx = score_x0 + (b * bar_w)
        local is_final = (b == bars)
        local th = is_final and 2.0 or 1.0
        reaper.ImGui_DrawList_AddLine(draw_list, bx, treble_top_y, bx, treble_bot_y, bar_col, th)
        reaper.ImGui_DrawList_AddLine(draw_list, bx, bass_top_y, bx, bass_bot_y, bar_col, th)
        if is_final then
            reaper.ImGui_DrawList_AddLine(draw_list, bx - 3, treble_top_y, bx - 3, treble_bot_y, bar_col, 1.0)
            reaper.ImGui_DrawList_AddLine(draw_list, bx - 3, bass_top_y, bx - 3, bass_bot_y, bar_col, 1.0)
        end
    end
    
    -- Draw notes
    local timesig_num = (pattern.time_sig and pattern.time_sig.num) or 4
    local timesig_denom = (pattern.time_sig and pattern.time_sig.denom) or 4
    local qn_per_bar = timesig_num * (4.0 / timesig_denom)
    local total_qn = bars * qn_per_bar
    if total_qn <= 0 then total_qn = 16.0 end
    
    local diatonic_map = { [0]=0, [1]=0, [2]=1, [3]=1, [4]=2, [5]=3, [6]=3, [7]=4, [8]=4, [9]=5, [10]=5, [11]=6 }
    local function pitch_to_diatonic(p)
        local oct = math.floor(p / 12)
        local semi = p % 12
        return oct * 7 + (diatonic_map[semi] or 0)
    end
    
    local treble_center_y = treble_top_y + (2 * step_y)
    local bass_center_y = bass_top_y + (2 * step_y)
    local note_r = math.max(1.5, 2.0 * z)
    local stem_len = math.max(5.5, 7.5 * z)
    
    for _, n in ipairs(pattern.notes or {}) do
        local nx = score_x0 + (n.start_qn / total_qn) * score_w
        local d_val = pitch_to_diatonic(n.pitch)
        
        local ny, center_y, is_treble
        if n.pitch >= 60 then
            -- Upper staff (Treble, B4 = 41)
            is_treble = true
            center_y = treble_center_y
            ny = treble_center_y - ((d_val - 41) * half_step_y)
            
            -- Ledger lines
            if ny > treble_bot_y + 1 then
                local cur_ly = treble_bot_y + step_y
                while cur_ly <= ny + 1 do
                    reaper.ImGui_DrawList_AddLine(draw_list, nx - 3, cur_ly, nx + 3, cur_ly, line_col, 1.0)
                    cur_ly = cur_ly + step_y
                end
            elseif ny < treble_top_y - 1 then
                local cur_ly = treble_top_y - step_y
                while cur_ly >= ny - 1 do
                    reaper.ImGui_DrawList_AddLine(draw_list, nx - 3, cur_ly, nx + 3, cur_ly, line_col, 1.0)
                    cur_ly = cur_ly - step_y
                end
            end
        else
            -- Lower staff (Bass, D3 = 29)
            is_treble = false
            center_y = bass_center_y
            ny = bass_center_y - ((d_val - 29) * half_step_y)
            
            -- Ledger lines
            if ny < bass_top_y - 1 then
                local cur_ly = bass_top_y - step_y
                while cur_ly >= ny - 1 do
                    reaper.ImGui_DrawList_AddLine(draw_list, nx - 3, cur_ly, nx + 3, cur_ly, line_col, 1.0)
                    cur_ly = cur_ly - step_y
                end
            elseif ny > bass_bot_y + 1 then
                local cur_ly = bass_bot_y + step_y
                while cur_ly <= ny + 1 do
                    reaper.ImGui_DrawList_AddLine(draw_list, nx - 3, cur_ly, nx + 3, cur_ly, line_col, 1.0)
                    cur_ly = cur_ly + step_y
                end
            end
        end
        
        -- Notehead
        reaper.ImGui_DrawList_AddCircleFilled(draw_list, nx, ny, note_r, note_col)
        
        -- Stem
        local stem_down = (ny < center_y)
        local stem_x = stem_down and (nx - (1.5 * z)) or (nx + (1.5 * z))
        local stem_ey = stem_down and (ny + stem_len) or (ny - stem_len)
        reaper.ImGui_DrawList_AddLine(draw_list, stem_x, ny, stem_x, stem_ey, 0xB0B8C8FF, 1.0)
        
        -- Staccato dot
        if n.art == "staccato" or n.dur_qn <= 0.3 then
            local dot_y = stem_down and (ny - (3 * z)) or (ny + (3 * z))
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, nx, dot_y, math.max(0.8, 1.0 * z), staccato_col)
        end
    end
end

--- Renders the complete bottom pane of the Pattern Browser
--- @param ctx ImGui_Context
--- @param state table
--- @param midi_service table
--- @param audio_preview table
--- @param width number
--- @param height number
--- @param project_tracks table
--- @param font_music ImFont
--- @param font_main ImFont
function PatternBrowser.render(ctx, state, midi_service, audio_preview, width, height, project_tracks, font_music, font_main)
    if not state.show_pattern_browser then return end
    
    -- One-time initialization of PatternService on first open
    if #PatternService.categories == 0 then
        PatternService.init()
    end
    
    state.selected_pattern_category = state.selected_pattern_category or "all"
    state.pattern_search_query = state.pattern_search_query or ""
    if not state.pattern_card_zoom then
        local saved_zoom = tonumber(reaper.GetExtState("REAPER_Notator", "PatternCardZoom"))
        state.pattern_card_zoom = saved_zoom or 1.0
    end
    
    local child_border = reaper.APIExists("ImGui_ChildFlags_Borders") and reaper.ImGui_ChildFlags_Borders() or 1
    local child_none = reaper.APIExists("ImGui_ChildFlags_None") and reaper.ImGui_ChildFlags_None() or 0
    
    local pane_flags = reaper.ImGui_WindowFlags_NoScrollbar()
    if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
        pane_flags = pane_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    end
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1E2026FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x383D4CFF)
    
    if reaper.ImGui_BeginChild(ctx, "PatternBrowserMainPane", width, height, child_border, pane_flags) then
        
        -- Check background pattern download status
        PatternService.check_download_progress(state)
        
        -- ======================================================================
        -- 1. HEADER / TOOLBAR (Search, preview instrument, capture & close)
        -- ======================================================================
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 2)
        
        -- Title & Icon
        reaper.ImGui_TextColored(ctx, 0xE67E22FF, "🎼 ORCHESTRAL PATTERN BROWSER")
        reaper.ImGui_SameLine(ctx, 0, 16)
        
        -- Search box
        reaper.ImGui_SetNextItemWidth(ctx, 160)
        local search_changed, new_search = reaper.ImGui_InputTextWithHint(ctx, "##PatternSearchInput", "🔍 Search...", state.pattern_search_query)
        if search_changed then
            state.pattern_search_query = new_search
        end
        
        -- Dropdown for preview instrument (REAPER tracks)
        reaper.ImGui_SameLine(ctx, 0, 12)
        reaper.ImGui_Text(ctx, "Preview Instrument:")
        reaper.ImGui_SameLine(ctx, 0, 6)
        reaper.ImGui_SetNextItemWidth(ctx, 190)
        
        -- Build track selection list
        local preview_options = { "⚡ Active Notator Track" }
        local track_map = { [1] = nil } -- nil = Active track
        for i, t in ipairs(project_tracks or {}) do
            local track_name = string.format("Track %d: %s", t.idx + 1, (t.name and #t.name > 0) and t.name or "Instrument")
            table.insert(preview_options, track_name)
            table.insert(track_map, t.track)
        end
        
        if reaper.ImGui_BeginCombo(ctx, "##PreviewTrackCombo", preview_options[preview_track_idx + 1] or preview_options[1]) then
            for idx, opt_label in ipairs(preview_options) do
                local is_sel = (idx - 1 == preview_track_idx)
                if reaper.ImGui_Selectable(ctx, opt_label, is_sel) then
                    preview_track_idx = idx - 1
                    state.pattern_preview_track = track_map[idx]
                end
                if is_sel then
                    reaper.ImGui_SetItemDefaultFocus(ctx)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Select a track from REAPER (e.g. Piano or VSTi) to audition patterns")
        end
        
        -- Button: Capture MIDI Item from REAPER
        reaper.ImGui_SameLine(ctx, 0, 12)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60AA)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
        if reaper.ImGui_Button(ctx, "💾 Capture REAPER Item", 165, 23) then
            capture_modal_open = true
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Save active/selected REAPER MIDI item as pattern to library")
        end
        
        -- Button: New Folder
        reaper.ImGui_SameLine(ctx, 0, 8)
        if reaper.ImGui_Button(ctx, "+ New Folder", 110, 23) then
            new_folder_modal_open = true
        end
        
        -- Button: Refresh Library
        reaper.ImGui_SameLine(ctx, 0, 8)
        if reaper.ImGui_Button(ctx, "🔄##RefreshPatterns", 28, 23) then
            PatternService.scan_library()
            state.status_msg = "Pattern library reloaded (" .. #PatternService.patterns .. " patterns)"
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Reload library from disk")
        end
        
        -- Button: 1-Click Factory Library Download / Update
        reaper.ImGui_SameLine(ctx, 0, 8)
        if PatternService.is_downloading then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xD35400AA)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE67E22FF)
            reaper.ImGui_Button(ctx, "⏳ Downloading...##PatDl", 155, 23)
            reaper.ImGui_PopStyleColor(ctx, 2)
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Downloading and installing 1,200 patterns...")
            end
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2E86ABAA)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x33A1DEFF)
            if reaper.ImGui_Button(ctx, "📥 Download Library (1200)", 185, 23) then
                PatternService.start_factory_download(state)
            end
            reaper.ImGui_PopStyleColor(ctx, 2)
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Download & extract 1,200 curated factory patterns (Ancient Harp, Strings, Brass, Piano, Woodwinds)")
            end
        end
        
        -- Tile zoom control (60% to 160%)
        reaper.ImGui_SameLine(ctx, 0, 12)
        reaper.ImGui_TextColored(ctx, 0x8892B0FF, "Zoom:")
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "－##PatZoomOut", 22, 23) then
            state.pattern_card_zoom = math.max(0.6, math.min(1.6, (state.pattern_card_zoom or 1.0) - 0.1))
            reaper.SetExtState("REAPER_Notator", "PatternCardZoom", string.format("%.2f", state.pattern_card_zoom), true)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Decrease tile zoom (-10%)")
        end
        
        reaper.ImGui_SameLine(ctx, 0, 2)
        local cur_zoom_pct = math.floor((state.pattern_card_zoom or 1.0) * 100 + 0.5)
        if reaper.ImGui_Button(ctx, string.format("%d%%##PatZoomReset", cur_zoom_pct), 46, 23) then
            state.pattern_card_zoom = 1.0
            reaper.SetExtState("REAPER_Notator", "PatternCardZoom", "1.00", true)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Reset tile zoom (100%)")
        end
        
        reaper.ImGui_SameLine(ctx, 0, 2)
        if reaper.ImGui_Button(ctx, "＋##PatZoomIn", 22, 23) then
            state.pattern_card_zoom = math.max(0.6, math.min(1.6, (state.pattern_card_zoom or 1.0) + 0.1))
            reaper.SetExtState("REAPER_Notator", "PatternCardZoom", string.format("%.2f", state.pattern_card_zoom), true)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Increase tile zoom (+10%)")
        end
        
        -- Close button on far right
        local win_w = reaper.ImGui_GetWindowWidth(ctx)
        reaper.ImGui_SameLine(ctx, win_w - 32)
        if reaper.ImGui_Button(ctx, "✕##ClosePatternBrowser", 24, 23) then
            state.show_pattern_browser = false
            reaper.SetExtState("REAPER_Notator", "ShowPatternBrowser", "false", true)
            PatternService.stop_preview(audio_preview)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Close Pattern Browser")
        end
        
        reaper.ImGui_Separator(ctx)
        
        -- ======================================================================
        -- 2. TWO-COLUMN BROWSER: Folders left | Grid right
        -- ======================================================================
        local content_w, content_h = reaper.ImGui_GetContentRegionAvail(ctx)
        local cat_tree_w = 230
        
        -- Left column: Folder categories
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x16181DFF)
        if reaper.ImGui_BeginChild(ctx, "PatternCatTree", cat_tree_w, content_h, child_border) then
            reaper.ImGui_TextColored(ctx, 0x8892B0FF, "CATEGORIES")
            reaper.ImGui_Separator(ctx)
            
            -- "All Patterns" entry
            local all_sel = (state.selected_pattern_category == "all")
            local total_count = #PatternService.patterns
            local all_label = string.format("📁 All Patterns (%d)", total_count)
            if reaper.ImGui_Selectable(ctx, all_label, all_sel) then
                state.selected_pattern_category = "all"
            end
            
            -- All subcategories
            for _, cat in ipairs(PatternService.categories) do
                local is_cat_sel = (state.selected_pattern_category == cat.id)
                local cat_display = string.format("%s (%d)", cat.label, cat.count)
                if reaper.ImGui_Selectable(ctx, cat_display, is_cat_sel) then
                    state.selected_pattern_category = cat.id
                end
            end
            
            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_PopStyleColor(ctx, 1)
        
        -- Right column: Pattern Cards Grid
        reaper.ImGui_SameLine(ctx, 0, 4)
        local grid_w = content_w - cat_tree_w - 6
        if reaper.ImGui_BeginChild(ctx, "PatternGrid", grid_w, content_h, child_none) then
            
            -- Filtering patterns
            local filtered_patterns = {}
            local q = state.pattern_search_query:lower()
            local target_cat = state.selected_pattern_category
            
            for _, p in ipairs(PatternService.patterns) do
                local match_cat = (target_cat == "all" or p.category == target_cat)
                local match_query = (q == "" or p.name:lower():find(q, 1, true) or (p.category and p.category:lower():find(q, 1, true)))
                if match_cat and match_query then
                    table.insert(filtered_patterns, p)
                end
            end
            
            if #filtered_patterns == 0 then
                if #PatternService.patterns == 0 then
                    -- HERO BANNER FOR EMPTY FACTORY LIBRARY
                    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 16)
                    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + 16)
                    
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1F2430FF)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x3D4A66FF)
                    local hero_w = math.max(300, grid_w - 32)
                    if reaper.ImGui_BeginChild(ctx, "EmptyPatHero", hero_w, 235, child_border) then
                        reaper.ImGui_SetCursorPosY(ctx, 16)
                        reaper.ImGui_SetCursorPosX(ctx, 20)
                        reaper.ImGui_TextColored(ctx, 0xF39C12FF, "🎼 REAPER-Notator Factory Pattern Library")
                        
                        reaper.ImGui_SetCursorPosY(ctx, 42)
                        reaper.ImGui_SetCursorPosX(ctx, 20)
                        reaper.ImGui_TextColored(ctx, 0xCCD6F6FF, "The Factory Library contains 1,200 curated orchestral, ancient harp & cinematic patterns:")
                        
                        reaper.ImGui_SetCursorPosY(ctx, 64)
                        reaper.ImGui_SetCursorPosX(ctx, 28)
                        reaper.ImGui_TextColored(ctx, 0x8892B0FF, "• 150x Ancient Greek & Roman Harp (Dorian, Phrygian, Lydian, Hymns & Processions)\n• 150x Cinematic Piano & Arpeggios\n• 300x Strings (Staccato, Ostinatos & Pizzicato)\n• 150x Epic Brass & Horns\n• 150x Woodwinds & Textures\n• 300x Cinematic & Counter Melodies")
                        
                        reaper.ImGui_SetCursorPosY(ctx, 175)
                        reaper.ImGui_SetCursorPosX(ctx, 20)
                        
                        if PatternService.is_downloading then
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xD35400FF)
                            reaper.ImGui_Button(ctx, "⏳ Downloading and extracting 1,200 patterns... please wait", 400, 32)
                            reaper.ImGui_PopStyleColor(ctx, 1)
                        else
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60EE)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
                            if reaper.ImGui_Button(ctx, "📥 1-Click Install Factory Patterns (1,200 Patterns)", 400, 32) then
                                PatternService.start_factory_download(state)
                            end
                            reaper.ImGui_PopStyleColor(ctx, 2)
                        end
                        
                        if PatternService.download_error then
                            reaper.ImGui_SameLine(ctx, 0, 12)
                            reaper.ImGui_TextColored(ctx, 0xE74C3CFF, PatternService.download_error)
                        end
                        
                        reaper.ImGui_EndChild(ctx)
                    end
                    reaper.ImGui_PopStyleColor(ctx, 2)
                else
                    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 20)
                    reaper.ImGui_TextColored(ctx, 0x8892B0FF, "  No matching patterns found in this category.")
                end
            else
                -- Responsive grid calculation
                local zoom = state.pattern_card_zoom or 1.0
                local card_w = math.floor(250 * zoom)
                local preview_h = math.floor(62 * zoom)
                local preview_w = card_w - 14
                local btn_h = math.max(18, math.floor(21 * math.min(1.0, zoom)))
                local play_btn_w = math.max(52, math.floor(66 * zoom))
                local card_h = math.floor(168 * zoom)
                local card_spacing = 8
                local cols = math.max(1, math.floor(grid_w / (card_w + card_spacing)))
                
                local card_flags = reaper.ImGui_WindowFlags_NoScrollbar()
                if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
                    card_flags = card_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
                end
                if reaper.APIExists("ImGui_WindowFlags_NoNav") then
                    card_flags = card_flags | reaper.ImGui_WindowFlags_NoNav()
                end
                
                for idx, pat in ipairs(filtered_patterns) do
                    local col_idx = (idx - 1) % cols
                    if col_idx > 0 then
                        reaper.ImGui_SameLine(ctx, 0, card_spacing)
                    end
                    
                    -- PATTERN CARD
                    local card_id = "pat_card_" .. pat.id
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x22252EFF)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x3D4354FF)
                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 6, 5)
                    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 4, 3)
                    
                    if reaper.ImGui_BeginChild(ctx, card_id, card_w, card_h, child_border, card_flags) then
                        local dl = reaper.ImGui_GetWindowDrawList(ctx)
                        local cp_x, cp_y = reaper.ImGui_GetCursorScreenPos(ctx)
                        
                        -- Title line & badges
                        local max_chars = math.max(14, math.floor(24 * zoom))
                        local name_trunc = pat.name
                        if #name_trunc > max_chars then name_trunc = name_trunc:sub(1, max_chars - 2) .. ".." end
                        reaper.ImGui_TextColored(ctx, 0xF39C12FF, name_trunc)
                        if reaper.ImGui_IsItemHovered(ctx) then
                            reaper.ImGui_SetTooltip(ctx, pat.name .. "\nCategory: " .. (pat.category or ""))
                        end
                        
                        -- Metadata badges (bars, BPM, time signature)
                        local ts = pat.time_sig or { num = 4, denom = 4 }
                        local meta_txt = string.format("%d Bars | %d BPM | %d/%d", pat.bars or 4, pat.tempo_hint or 120, ts.num, ts.denom)
                        reaper.ImGui_TextColored(ctx, 0x8892B0FF, meta_txt)
                        
                        -- Mini-score preview
                        local sc_x, sc_y = reaper.ImGui_GetCursorScreenPos(ctx)
                        draw_mini_score(dl, pat, sc_x, sc_y, preview_w, preview_h, font_music, zoom)
                        
                        -- Invisible click/drag area over preview
                        reaper.ImGui_InvisibleButton(ctx, "drag_zone_" .. pat.id, preview_w, preview_h)
                        
                        -- Drag & Drop Source
                        if reaper.ImGui_BeginDragDropSource(ctx) then
                            state.dragged_pattern = pat
                            state.is_dragging_pattern = true
                            reaper.ImGui_SetDragDropPayload(ctx, "NOTATOR_PATTERN", pat.id)
                            reaper.ImGui_Text(ctx, "🎼 " .. pat.name)
                            reaper.ImGui_TextColored(ctx, 0x8892B0FF, string.format("Drag onto track in score (%d bars)", pat.bars or 4))
                            reaper.ImGui_EndDragDropSource(ctx)
                        end
                        if reaper.ImGui_IsItemHovered(ctx) then
                            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                            reaper.ImGui_SetTooltip(ctx, "Left-click and drag into score canvas!")
                        end
                        
                        -- Bottom: action row (Play/Stop & drag hint)
                        local is_playing = (PatternService.active_preview and PatternService.active_preview.pattern and PatternService.active_preview.pattern.id == pat.id)
                        local btn_label = is_playing and "■ Stop" or "▶ Play"
                        local btn_col = is_playing and 0xE74C3CAA or 0x27AE60AA
                        local btn_hov = is_playing and 0xE74C3CFF or 0x2ECC71FF
                        
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), btn_col)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), btn_hov)
                        if reaper.ImGui_Button(ctx, btn_label .. "##" .. pat.id, play_btn_w, btn_h) then
                            if is_playing then
                                PatternService.stop_preview(audio_preview)
                            else
                                -- Determine target track: selected preview track or active track in notator
                                local target_tr = state.pattern_preview_track or state.focused_track
                                if not target_tr and #project_tracks > 0 then
                                    target_tr = project_tracks[1].track
                                end
                                if target_tr then
                                    PatternService.start_preview(pat, target_tr, audio_preview)
                                else
                                    state.status_msg = "No track available for audio preview"
                                end
                            end
                        end
                        reaper.ImGui_PopStyleColor(ctx, 2)
                        
                        reaper.ImGui_SameLine(ctx, 0, 8)
                        reaper.ImGui_TextColored(ctx, 0x6E7681FF, "⇄ Drag")
                        if reaper.ImGui_IsItemHovered(ctx) then
                            reaper.ImGui_SetTooltip(ctx, "Click and drag this pattern into score canvas")
                        end
                        
                        -- Context menu on right-click on card
                        if reaper.ImGui_BeginPopupContextItem(ctx, "card_ctx_" .. pat.id) then
                            reaper.ImGui_TextColored(ctx, 0xF39C12FF, pat.name)
                            reaper.ImGui_Separator(ctx)
                            
                            if reaper.ImGui_MenuItem(ctx, "➕ Insert into Canvas at Edit Cursor") then
                                local target_tr = state.focused_track or (project_tracks[1] and project_tracks[1].track)
                                local target_qn = reaper.TimeMap2_timeToQN(0, reaper.GetCursorPosition())
                                if target_tr then
                                    PatternService.insert_pattern_into_track(target_tr, target_qn, pat, midi_service)
                                    state.status_msg = "Pattern '" .. pat.name .. "' inserted"
                                end
                            end
                            
                            if pat.category == "08_Eigene_Patterns" or pat.category == "07_Eigene_Patterns" or pat.category == "06_Eigene_Patterns" or pat.id:match("^user_") then
                                reaper.ImGui_Separator(ctx)
                                if reaper.ImGui_MenuItem(ctx, "🗑 Delete pattern from disk") then
                                    PatternService.delete_pattern(pat)
                                    state.status_msg = "Pattern '" .. pat.name .. "' deleted"
                                end
                            end
                            
                            reaper.ImGui_EndPopup(ctx)
                        end
                        
                        reaper.ImGui_EndChild(ctx)
                    end
                    reaper.ImGui_PopStyleVar(ctx, 2)
                    reaper.ImGui_PopStyleColor(ctx, 2)
                end
            end
            
            reaper.ImGui_EndChild(ctx)
        end
        
        reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx, 2)
    
    -- ======================================================================
    -- 3. MODAL DIALOGS
    -- ======================================================================
    
    -- MODAL: Save REAPER MIDI item
    if capture_modal_open then
        reaper.ImGui_OpenPopup(ctx, "capture_item_modal_popup")
    end
    
    if reaper.ImGui_BeginPopupModal(ctx, "capture_item_modal_popup", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, "💾 SAVE REAPER MIDI ITEM AS PATTERN")
        reaper.ImGui_Separator(ctx)
        
        local cur_sel = state.selected_item or reaper.GetSelectedMediaItem(0, 0)
        if not cur_sel or not reaper.ValidatePtr(cur_sel, "MediaItem*") then
            reaper.ImGui_TextColored(ctx, 0xE74C3CFF, "⚠️ Please select a MIDI item in REAPER or Notator first!")
            reaper.ImGui_Spacing(ctx)
            if reaper.ImGui_Button(ctx, "Close", 100, 24) then
                capture_modal_open = false
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
        else
            reaper.ImGui_Text(ctx, "Name of new pattern:")
            reaper.ImGui_SetNextItemWidth(ctx, 280)
            local changed_n, new_n = reaper.ImGui_InputText(ctx, "##CaptureNameInput", capture_name_buf)
            if changed_n then capture_name_buf = new_n end
            
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Text(ctx, "Target folder:")
            reaper.ImGui_SetNextItemWidth(ctx, 280)
            
            local cat_options = {}
            for _, c in ipairs(PatternService.categories) do
                table.insert(cat_options, c.label)
            end
            if #cat_options == 0 then table.insert(cat_options, "08_Eigene_Patterns") end
            
            if reaper.ImGui_BeginCombo(ctx, "##CaptureCatCombo", cat_options[capture_category_idx + 1] or cat_options[1]) then
                for c_idx, c_lbl in ipairs(cat_options) do
                    local is_sel = (c_idx - 1 == capture_category_idx)
                    if reaper.ImGui_Selectable(ctx, c_lbl, is_sel) then
                        capture_category_idx = c_idx - 1
                    end
                end
                reaper.ImGui_EndCombo(ctx)
            end
            
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Text(ctx, "Pattern length:")
            if reaper.ImGui_RadioButton(ctx, "4 Bars", capture_bars_idx == 0) then capture_bars_idx = 0 end
            reaper.ImGui_SameLine(ctx, 0, 10)
            if reaper.ImGui_RadioButton(ctx, "8 Bars", capture_bars_idx == 1) then capture_bars_idx = 1 end
            reaper.ImGui_SameLine(ctx, 0, 10)
            if reaper.ImGui_RadioButton(ctx, "16 Bars", capture_bars_idx == 2) then capture_bars_idx = 2 end
            reaper.ImGui_SameLine(ctx, 0, 10)
            if reaper.ImGui_RadioButton(ctx, "Entire Item", capture_bars_idx == 3) then capture_bars_idx = 3 end
            
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_Button(ctx, "Save", 110, 26) then
                local chosen_cat = PatternService.categories[capture_category_idx + 1] and PatternService.categories[capture_category_idx + 1].id or "08_Eigene_Patterns"
                local bars = (capture_bars_idx == 0) and 4 or (capture_bars_idx == 1 and 8 or (capture_bars_idx == 2 and 16 or 64))
                local ok, res = PatternService.capture_reaper_item(cur_sel, capture_name_buf, chosen_cat, bars)
                if ok then
                    state.status_msg = "Pattern '" .. capture_name_buf .. "' successfully saved!"
                    capture_modal_open = false
                    reaper.ImGui_CloseCurrentPopup(ctx)
                else
                    state.status_msg = "Error: " .. tostring(res)
                end
            end
            
            reaper.ImGui_SameLine(ctx, 0, 10)
            if reaper.ImGui_Button(ctx, "Cancel", 100, 26) then
                capture_modal_open = false
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
    
    -- MODAL: Create new folder
    if new_folder_modal_open then
        reaper.ImGui_OpenPopup(ctx, "new_folder_modal_popup")
    end
    
    if reaper.ImGui_BeginPopupModal(ctx, "new_folder_modal_popup", nil, reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
        reaper.ImGui_TextColored(ctx, 0x3498DBFF, "📁 CREATE NEW CATEGORY FOLDER")
        reaper.ImGui_Separator(ctx)
        
        reaper.ImGui_Text(ctx, "Folder name:")
        reaper.ImGui_SetNextItemWidth(ctx, 260)
        local changed_f, new_f = reaper.ImGui_InputText(ctx, "##NewFolderNameInput", new_folder_name_buf)
        if changed_f then new_folder_name_buf = new_f end
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        
        if reaper.ImGui_Button(ctx, "Create", 100, 26) then
            local ok, folder_created = PatternService.create_folder(new_folder_name_buf)
            if ok then
                state.selected_pattern_category = folder_created
                state.status_msg = "Folder '" .. folder_created .. "' created"
                new_folder_modal_open = false
                reaper.ImGui_CloseCurrentPopup(ctx)
            end
        end
        
        reaper.ImGui_SameLine(ctx, 0, 10)
        if reaper.ImGui_Button(ctx, "Cancel", 100, 26) then
            new_folder_modal_open = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
end

return PatternBrowser

-- ==============================================================================
-- REAPER Native Notator - Module: BottomBar
-- Bottom status and grid bar with beam toggles
-- ==============================================================================

local BottomBar = {}

local function toggle_btn(ctx, label, is_active, w, h, active_col)
    local pushed = false
    if is_active then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), active_col or 0xFF9F1CFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFFA726FF)
        pushed = true
    end
    local clicked = reaper.ImGui_Button(ctx, label, w or 0, h or 0)
    if pushed then
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
    return clicked
end

function BottomBar.render(ctx, state, h, child_border, bottom_flags)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 6, 4)
    local open = reaper.ImGui_BeginChild(ctx, "BottomBar", 0, h, child_border, bottom_flags)
    if not open then
        reaper.ImGui_PopStyleVar(ctx)
        return
    end
    reaper.ImGui_SetScrollY(ctx, 0)
    
    reaper.ImGui_TextColored(ctx, 0x888888FF, "GRID:")
    reaper.ImGui_SameLine(ctx)
    local grids = {
        { l = "1/1", qn = 4.0 }, { l = "1/2", qn = 2.0 }, { l = "1/4", qn = 1.0 },
        { l = "1/8", qn = 0.5 }, { l = "1/16", qn = 0.25 }, { l = "1/32", qn = 0.125 },
        { l = "1/4 T", qn = 1.0 * (2/3) }, { l = "1/8 T", qn = 0.5 * (2/3) }, { l = "Free", qn = 0.0 }
    }
    for _, g in ipairs(grids) do
        local is_g = (math.abs(state.grid_qn - g.qn) < 0.001)
        if toggle_btn(ctx, g.l, is_g, 42, 22) then
            state.grid_qn = g.qn
            state.grid_label = g.l
            state.status_msg = "Grid: " .. g.l
        end
        reaper.ImGui_SameLine(ctx)
    end

    local track_name = "No track selected"
    local track = reaper.GetSelectedTrack(0, 0)
    if track then
        local _, name = reaper.GetTrackName(track)
        track_name = (name and #name > 0) and name or "Track"
    end
    
    reaper.ImGui_SameLine(ctx, 0, 16)
    local info_txt = string.format("%s | %d notes selected", track_name, state:count_selected_notes())
    if state.selected_dynamic then
        info_txt = info_txt .. string.format(" | [Dynamic '%s' selected]", state.selected_dynamic.label)
    end
    reaper.ImGui_Text(ctx, info_txt)
    
    reaper.ImGui_SameLine(ctx, 0, 16)
    reaper.ImGui_TextColored(ctx, 0xF39C12FF, state.status_msg or "")
    
    -- Horizontal scroll zone for all buttons behind status text
    reaper.ImGui_SameLine(ctx, 0, 16)
    local scroll_flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()
    if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
        scroll_flags = scroll_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    end
    
    local child_h = math.max(28, h - 8)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 0, 0)
    if reaper.ImGui_BeginChild(ctx, "BottomButtonsScroll", 0, child_h, 0, scroll_flags) then
        reaper.ImGui_SetScrollY(ctx, 0)
        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local total_needed_w = 145 + 8 + 120 + 8 + 180 + 8 + 25 -- 494 px
        if avail_w > total_needed_w then
            reaper.ImGui_SetCursorPosX(ctx, avail_w - total_needed_w)
        end
        reaper.ImGui_SetCursorPosY(ctx, 3)
        
        if toggle_btn(ctx, "🎼 Pattern Browser", state.show_pattern_browser, 145, 24, 0xE67E22FF) then
            state.show_pattern_browser = not state.show_pattern_browser
            reaper.SetExtState("REAPER_Notator", "ShowPatternBrowser", state.show_pattern_browser and "true" or "false", true)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Toggle Orchestral Pattern Browser (Drag & Drop into Canvas)")
        end


        reaper.ImGui_SameLine(ctx, 0, 8)
        if toggle_btn(ctx, "🎼 MusicXML...", state.show_musicxml_modal, 120, 24, 0x16A085FF) then
            state.show_musicxml_modal = not state.show_musicxml_modal
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "MusicXML Import & Export:\nLossless interchange of notes, transformed chord-track pitches, <harmony> tags, text items, dynamics, hairpins, and key signatures.")
        end

        reaper.ImGui_SameLine(ctx, 0, 8)
        if toggle_btn(ctx, "⚙ Settings & Shortcuts", state.show_settings, 180, 24, 0x3498DBFF) then
            state.show_settings = not state.show_settings
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Settings & Keyboard Shortcuts")
        end

        reaper.ImGui_SameLine(ctx, 0, 8)
        if toggle_btn(ctx, "?##HelpBtn", state.show_help, 25, 24, 0x27AE60FF) then
            state.show_help = not state.show_help
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Help & Documentation")
        end

        -- Horizontal scrolling via mouse wheel (lock vertical scrolling)
        reaper.ImGui_SetScrollY(ctx, 0)
        if reaper.ImGui_IsWindowHovered(ctx) then
            local wh_y = reaper.ImGui_GetMouseWheel(ctx)
            local wh_x = reaper.APIExists("ImGui_GetMouseWheelH") and reaper.ImGui_GetMouseWheelH(ctx) or 0
            if wh_x ~= 0 or wh_y ~= 0 then
                local s_amt = (wh_x ~= 0) and wh_x or wh_y
                local cur_scroll = reaper.ImGui_GetScrollX(ctx)
                reaper.ImGui_SetScrollX(ctx, cur_scroll - (s_amt * 40))
            end
        end

        reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx) -- Pop WindowPadding

    reaper.ImGui_SetScrollY(ctx, 0)
    reaper.ImGui_EndChild(ctx)
    reaper.ImGui_PopStyleVar(ctx) -- Pop BottomBar padding
end

return BottomBar

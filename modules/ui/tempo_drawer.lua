-- ==============================================================================
-- REAPER Native Notator - Module: TempoDrawer
-- Right drawer for tempo markings & gradual tempo changes
-- Precise notation layout replica with dual-handle connection
-- ==============================================================================

local TempoDrawer = {}
local TempoService = require("services.tempo_service")

-- Complete engraving reference table
local TEMPO_PRESETS = {
    { name = "Grave",            bpm = 40 },
    { name = "Largo",            bpm = 50 },
    { name = "Lento",            bpm = 56 },
    { name = "Adagio",           bpm = 66 },
    { name = "Andante",          bpm = 80 },
    { name = "Marcia moderato",  bpm = 86 },
    { name = "Andantino",        bpm = 92 },
    { name = "Andante moderato", bpm = 96 },
    { name = "Eroico",           bpm = 96 },
    { name = "Grazioso",         bpm = 108 },
    { name = "Moderato",         bpm = 108 },
    { name = "Allegretto",       bpm = 112 },
    { name = "Alla marcia",      bpm = 120 },
    { name = "Allegro moderato", bpm = 120 },
    { name = "Con brio",         bpm = 120 },
    { name = "Con moto",         bpm = 120 },
    { name = "Deciso",           bpm = 120 },
    { name = "Giocoso",          bpm = 120 },
    { name = "Marziale",         bpm = 120 },
    { name = "Gioioso",          bpm = 132 },
    { name = "Allegro",          bpm = 140 },
    { name = "Agitato",          bpm = 144 },
    { name = "Alla breve",       bpm = 144 },
    { name = "Animato",          bpm = 144 },
    { name = "Appassionato",     bpm = 144 },
    { name = "Con bravura",      bpm = 144 },
    { name = "Energico",         bpm = 144 },
    { name = "Scherzando",       bpm = 144 },
    { name = "Con fuoco",        bpm = 160 },
    { name = "Vivace",           bpm = 160 },
    { name = "Presto",           bpm = 180 },
    { name = "Prestissimo",      bpm = 200 },
}

local GRADUAL_TERMS = {
    "accel.",
    "allarg.",
    "calando",
    "lentando",
    "morendo",
    "precipitando",
    "rall.",
    "rit.",
    "smorz.",
    "sost.",
    "string."
}

-- Local state for Tempo Drawer
local search_filter = ""
local selected_modifier = "" -- "", "poco", "molto"

function TempoDrawer.render(ctx, state, width, height, child_border, sidebar_flags)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1A1C22FF)
    
    if reaper.ImGui_BeginChild(ctx, "TempoDrawer", width, height, child_border, sidebar_flags) then
        -- Header
        reaper.ImGui_TextColored(ctx, 0xF39C12FF, "⏱ TEMPO & METER")
        reaper.ImGui_SameLine(ctx, width - 26)
        if reaper.ImGui_Button(ctx, "✕##CloseTempoDrawer", 20, 20) then
            state.show_tempo = false
        end
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Selected marker actions (if active)
        if state.selected_tempo_marker then
            local sel = state.selected_tempo_marker
            reaper.ImGui_TextColored(ctx, 0x5DADE2FF, string.format("Focus: %s (Bar %.1f)", sel:get_display_text(), (sel.start_qn / 4) + 1))
            if sel.type == "absolute" then
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_PushItemWidth(ctx, 60)
                local changed, new_bpm = reaper.ImGui_DragInt(ctx, "##sel_bpm", sel.bpm, 1, 30, 360)
                if changed then
                    TempoService.set_custom_bpm(state, sel, new_bpm)
                end
                reaper.ImGui_PopItemWidth(ctx)
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "🗑##DelTempo", 22, 20) then
                    TempoService.delete_selected_tempo_marker(state)
                end
            elseif sel.type == "gradual" then
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "🗑##DelTempo", 22, 20) then
                    TempoService.delete_selected_tempo_marker(state)
                end
                reaper.ImGui_TextColored(ctx, 0xAAAAAAFF, string.format("Ramp: %d ➔", math.floor(sel.bpm or 120)))
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_PushItemWidth(ctx, 55)
                local changed, new_tbpm = reaper.ImGui_DragInt(ctx, "##sel_tbpm", sel.target_bpm or 140, 1, 30, 360)
                if changed then
                    TempoService.set_custom_bpm(state, sel, new_tbpm)
                end
                reaper.ImGui_PopItemWidth(ctx)
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextColored(ctx, 0x888888FF, "BPM")
            end
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)
        end
        
        -- Search filter
        reaper.ImGui_PushItemWidth(ctx, width - 18)
        local f_changed, new_f = reaper.ImGui_InputTextWithHint(ctx, "##TempoFilter", "🔍 Search...", search_filter)
        if f_changed then search_filter = new_f end
        reaper.ImGui_PopItemWidth(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Scroll area for tempo presets (scalable via horizontal splitter)
        local list_h = state.tempo_drawer_presets_h or 220
        local min_presets_h = 60
        local max_presets_h = math.max(min_presets_h, height - (state.selected_tempo_marker and 180 or 140))
        list_h = math.max(min_presets_h, math.min(max_presets_h, list_h))
        
        if reaper.ImGui_BeginChild(ctx, "TempoPresetsList", width - 12, list_h, 0, reaper.ImGui_WindowFlags_None()) then
            local filter_low = search_filter:lower()
            for _, item in ipairs(TEMPO_PRESETS) do
                if filter_low == "" or item.name:lower():find(filter_low, 1, true) or tostring(item.bpm):find(filter_low, 1, true) then
                    -- Authentic typography: Name on left (white), BPM on right (gray)
                    local cur_x = reaper.ImGui_GetCursorPosX(ctx)
                    local cur_y = reaper.ImGui_GetCursorPosY(ctx)
                    local btn_w = width - 28
                    
                    if reaper.ImGui_Selectable(ctx, "##preset_" .. item.name, false, 0, btn_w, 22) then
                        TempoService.add_tempo_marker(state, {
                            type     = "absolute",
                            label    = item.name,
                            bpm      = item.bpm
                        })
                    end
                    
                    -- Draw text overlay for 2-column layout
                    local is_hov = reaper.ImGui_IsItemHovered(ctx)
                    local dl = reaper.ImGui_GetWindowDrawList(ctx)
                    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
                    local item_x0, item_y0 = reaper.ImGui_GetItemRectMin(ctx)
                    local item_x1, item_y1 = reaper.ImGui_GetItemRectMax(ctx)
                    
                    local name_col = is_hov and 0xFF9F1CFF or 0xF0F0F0FF
                    local bpm_col  = is_hov and 0xF0F0F0AA or 0x888888FF
                    
                    reaper.ImGui_DrawList_AddText(dl, item_x0 + 6, item_y0 + 3, name_col, item.name)
                    local bpm_str = tostring(item.bpm)
                    reaper.ImGui_DrawList_AddText(dl, item_x1 - 32, item_y0 + 3, bpm_col, bpm_str)
                end
            end
            reaper.ImGui_EndChild(ctx)
        end
        
        -- ==================================================================
        -- HORIZONTAL SPLITTER: Draggable separator bar (Presets / Gradual)
        -- ==================================================================
        reaper.ImGui_Spacing(ctx)
        
        local splitter_h = 8
        local splitter_w = width - 14
        reaper.ImGui_InvisibleButton(ctx, "##hsplitter_tempo_drawer", splitter_w, splitter_h)
        local is_active = reaper.ImGui_IsItemActive(ctx)
        local is_hovered = reaper.ImGui_IsItemHovered(ctx)
        
        if is_active then
            local _, delta_y = reaper.ImGui_GetMouseDelta(ctx)
            if delta_y ~= 0 then
                local new_h = math.floor(list_h + delta_y)
                new_h = math.max(min_presets_h, math.min(max_presets_h, new_h))
                if state.save_tempo_drawer_presets_h then
                    state:save_tempo_drawer_presets_h(new_h)
                else
                    state.tempo_drawer_presets_h = new_h
                    reaper.SetExtState("REAPER_Notator", "tempo_drawer_presets_h", tostring(new_h), true)
                    reaper.SetProjExtState(0, "REAPER_Notator", "tempo_drawer_presets_h", tostring(new_h))
                end
            end
        end
        
        if is_hovered and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
            local def_h = 220
            if state.save_tempo_drawer_presets_h then
                state:save_tempo_drawer_presets_h(def_h)
            else
                state.tempo_drawer_presets_h = def_h
                reaper.SetExtState("REAPER_Notator", "tempo_drawer_presets_h", tostring(def_h), true)
                reaper.SetProjExtState(0, "REAPER_Notator", "tempo_drawer_presets_h", tostring(def_h))
            end
        end
        
        if is_hovered or is_active then
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
        end
        
        -- Visual divider line with subtle grip handle
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        local sp_x0, sp_y0 = reaper.ImGui_GetItemRectMin(ctx)
        local sp_x1, sp_y1 = reaper.ImGui_GetItemRectMax(ctx)
        local mid_y = math.floor((sp_y0 + sp_y1) * 0.5)
        local mid_x = math.floor((sp_x0 + sp_x1) * 0.5)
        
        local line_col = is_active and 0xFF9F1CFF or (is_hovered and 0xFF9F1CAA or 0x3E424FFF)
        reaper.ImGui_DrawList_AddLine(dl, sp_x0, mid_y, sp_x1, mid_y, line_col, is_active and 2.0 or 1.0)
        
        -- Grip bar in center
        local grip_col = is_active and 0xFFFFFFFF or (is_hovered and 0xFF9F1CFF or 0x6E7385FF)
        reaper.ImGui_DrawList_AddRectFilled(dl, mid_x - 16, mid_y - 2, mid_x + 16, mid_y + 2, grip_col, 2.0)
        
        reaper.ImGui_Spacing(ctx)
        
        -- ==================================================================
        -- GRADUAL TEMPO CHANGE (accel., rall., rit. etc. with dual handles)
        -- ==================================================================
        if reaper.ImGui_BeginChild(ctx, "GradualTempoChild", width - 12, 0, 0, reaper.ImGui_WindowFlags_None()) then
            local tree_open = reaper.ImGui_CollapsingHeader(ctx, "Gradual Tempo Change", reaper.ImGui_TreeNodeFlags_DefaultOpen())
            if tree_open then
                reaper.ImGui_Spacing(ctx)
                
                -- Modifier pills: [poco] [molto]
                local is_poco = (selected_modifier == "poco")
                local is_molto = (selected_modifier == "molto")
                
                if is_poco then
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2980B9FF)
                end
                if reaper.ImGui_Button(ctx, "poco", 50, 24) then
                    selected_modifier = is_poco and "" or "poco"
                end
                if is_poco then reaper.ImGui_PopStyleColor(ctx) end
                
                reaper.ImGui_SameLine(ctx, 0, 6)
                
                if is_molto then
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2980B9FF)
                end
                if reaper.ImGui_Button(ctx, "molto", 50, 24) then
                    selected_modifier = is_molto and "" or "molto"
                end
                if is_molto then reaper.ImGui_PopStyleColor(ctx) end
                
                reaper.ImGui_Spacing(ctx)
                
                -- List of gradual tempo terms
                for _, term in ipairs(GRADUAL_TERMS) do
                    local display_label = term
                    if selected_modifier ~= "" then
                        display_label = selected_modifier .. " " .. term
                    end
                    
                    if reaper.ImGui_Selectable(ctx, display_label .. "##grad_" .. term, false, 0, width - 28, 22) then
                        TempoService.add_tempo_marker(state, {
                            type     = "gradual",
                            label    = term,
                            modifier = selected_modifier,
                            dur_qn   = 4.0 -- Default 1 measure with 2 handles
                        })
                    end
                end
            end
            reaper.ImGui_EndChild(ctx)
        end
        
        reaper.ImGui_EndChild(ctx)
    end
    
    reaper.ImGui_PopStyleColor(ctx)
end

return TempoDrawer


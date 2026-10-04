-- ==============================================================================
-- REAPER Native Notator - Module: TempoDrawer
-- Right drawer for tempo markings & gradual tempo changes
-- Precise notation layout replica with dual-handle connection
-- ==============================================================================

local TempoDrawer = {}
local TempoService   = require("services.tempo_service")
local FermataService = require("services.fermata_service")

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
local new_fermata_type = "standard"
local new_fermata_hold = 1.5
local new_fermata_mode = "tempo_dip"

function TempoDrawer.render(ctx, state, width, height, child_border, sidebar_flags)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1A1C22FF)
    
    if reaper.ImGui_BeginChild(ctx, "TempoDrawer", width, height, child_border, sidebar_flags) then
        -- Header
        reaper.ImGui_TextColored(ctx, 0xF39C12FF, "⏱ TEMPO & FERMATAS")
        reaper.ImGui_SameLine(ctx, width - 26)
        if reaper.ImGui_Button(ctx, "✕##CloseTempoDrawer", 20, 20) then
            state.show_tempo = false
        end
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        if reaper.ImGui_BeginTabBar(ctx, "TempoDrawerTabBar") then
            -- ==========================================================
            -- TAB 1: TEMPO & METER
            -- ==========================================================
            local t_open, _ = reaper.ImGui_BeginTabItem(ctx, "⏱ Tempo")
            if t_open then
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
                            
                            local is_hov = reaper.ImGui_IsItemHovered(ctx)
                            local dl = reaper.ImGui_GetWindowDrawList(ctx)
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
                
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                local sp_x0, sp_y0 = reaper.ImGui_GetItemRectMin(ctx)
                local sp_x1, sp_y1 = reaper.ImGui_GetItemRectMax(ctx)
                local mid_y = math.floor((sp_y0 + sp_y1) * 0.5)
                local mid_x = math.floor((sp_x0 + sp_x1) * 0.5)
                
                local line_col = is_active and 0xFF9F1CFF or (is_hovered and 0xFF9F1CAA or 0x3E424FFF)
                reaper.ImGui_DrawList_AddLine(dl, sp_x0, mid_y, sp_x1, mid_y, line_col, is_active and 2.0 or 1.0)
                
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
                                    dur_qn   = 4.0
                                })
                            end
                        end
                    end
                    reaper.ImGui_EndChild(ctx)
                end

                reaper.ImGui_EndTabItem(ctx)
            end

            -- ==========================================================
            -- TAB 2: FERMATAS (SCORE PAUSES & HOLDS)
            -- ==========================================================
            local ferm_tab_lbl = string.format("𝄐 Fermatas (%d)", (state.fermatas and #state.fermatas or 0))
            local ferm_tab_flags = 0
            if state.selected_fermata and not state._tempo_tab_user_selected then
                ferm_tab_flags = reaper.ImGui_TabItemFlags_SetSelected()
            end
            local f_open, _ = reaper.ImGui_BeginTabItem(ctx, ferm_tab_lbl, nil, ferm_tab_flags)
            if f_open then
                reaper.ImGui_Spacing(ctx)

                -- 1. Selected Fermata Focus
                if state.selected_fermata then
                    local sf = state.selected_fermata
                    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, string.format("Focus: %s (Bar %d, Beat %.1f)", sf.type or "standard", sf.measure + 1, (sf.beat_rel or 0) + 1))
                    reaper.ImGui_SameLine(ctx, width - 36)
                    if reaper.ImGui_SmallButton(ctx, "✕##ClearFermSel") then
                        state.selected_fermata = nil
                    end

                    reaper.ImGui_Spacing(ctx)
                    reaper.ImGui_Text(ctx, "Type:")
                    local sf_types = { { id="standard", l="Standard 𝄐" }, { id="short", l="Short ▼" }, { id="long", l="Long ⨅" }, { id="very_long", l="Very Long" } }
                    for i, t in ipairs(sf_types) do
                        local is_cur = (sf.type == t.id)
                        if is_cur then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2980B9FF) end
                        if reaper.ImGui_Button(ctx, t.l .. "##sf_t", (width - 32) / 2, 22) then
                            sf.type = t.id
                            FermataService.save_fermatas(state)
                            FermataService.sync_takes_for_fermata(sf, state.active_tracks_cache, false)
                        end
                        if is_cur then reaper.ImGui_PopStyleColor(ctx) end
                        if i % 2 ~= 0 then reaper.ImGui_SameLine(ctx, 0, 4) end
                    end

                    reaper.ImGui_Spacing(ctx)
                    reaper.ImGui_Text(ctx, "Playback Hold:")
                    local sf_factors = { 1.25, 1.5, 2.0, 3.0 }
                    for i, fac in ipairs(sf_factors) do
                        local is_cur = (sf.playback_mode ~= "visual_only") and math.abs((sf.hold_factor or 1.5) - fac) < 0.05
                        if is_cur then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF) end
                        if reaper.ImGui_Button(ctx, string.format("%.2fx##sf_fac", fac), (width - 40) / 4, 22) then
                            sf.hold_factor = fac
                            if sf.playback_mode == "visual_only" then sf.playback_mode = "tempo_curve" end
                            FermataService.save_fermatas(state)
                            local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
                            if TempoService then (TempoService.sync_all_to_reaper or TempoService.sync_to_reaper)(state) end
                        end
                        if is_cur then reaper.ImGui_PopStyleColor(ctx) end
                        if i < 4 then reaper.ImGui_SameLine(ctx, 0, 4) end
                    end

                    reaper.ImGui_Spacing(ctx)
                    reaper.ImGui_Text(ctx, "Tempomap Mode:")
                    local sf_modes = {
                        { id = "tempo_curve", l = "∿ Curve (Ramp)" },
                        { id = "tempo_dip",   l = "⎍ Step (Dip)" },
                        { id = "visual_only", l = "👁 Visual Only" }
                    }
                    local sf_btn_w = (width - 32) / 3
                    for i, m in ipairs(sf_modes) do
                        local is_m_cur = (sf.playback_mode == m.id) or (m.id == "tempo_curve" and not sf.playback_mode)
                        if is_m_cur then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF) end
                        if reaper.ImGui_Button(ctx, m.l .. "##sf_m", sf_btn_w, 22) then
                            sf.playback_mode = m.id
                            FermataService.save_fermatas(state)
                            local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
                            if TempoService then (TempoService.sync_all_to_reaper or TempoService.sync_to_reaper)(state) end
                        end
                        if is_m_cur then reaper.ImGui_PopStyleColor(ctx) end
                        if i < 3 then reaper.ImGui_SameLine(ctx, 0, 4) end
                    end

                    reaper.ImGui_Spacing(ctx)
                    if reaper.ImGui_Button(ctx, "🗑 Delete This Fermata", width - 24, 24) then
                        FermataService.remove_fermata(state, sf.id, state.active_tracks_cache)
                        state.selected_fermata = nil
                    end

                    reaper.ImGui_Separator(ctx)
                    reaper.ImGui_Spacing(ctx)
                end

                -- 2. Insert Fermata Panel
                local cur_pos_sec = reaper.GetCursorPosition()
                local cur_qn = reaper.TimeMap2_timeToQN(0, cur_pos_sec)
                local bpi = 4.0
                local ts_num, ts_den = reaper.TimeMap_GetTimeSigAtTime(0, cur_pos_sec)
                if ts_num and ts_den and ts_den > 0 then bpi = ts_num * (4.0 / ts_den) end
                local cur_bar = math.floor((cur_qn + 0.01) / bpi) + 1
                local cur_beat = (cur_qn % bpi) + 1

                reaper.ImGui_TextColored(ctx, 0x5DADE2FF, string.format("Insert at Cursor: Bar %d (Beat %.1f)", cur_bar, cur_beat))
                reaper.ImGui_Spacing(ctx)

                reaper.ImGui_Text(ctx, "Symbol Type:")
                local all_types = { { id="standard", l="Standard 𝄐" }, { id="short", l="Short ▼" }, { id="long", l="Long ⨅" }, { id="very_long", l="Very Long" } }
                for i, t in ipairs(all_types) do
                    local is_sel = (new_fermata_type == t.id)
                    if is_sel then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF) end
                    if reaper.ImGui_Button(ctx, t.l .. "##new_t", (width - 32) / 2, 24) then
                        new_fermata_type = t.id
                    end
                    if is_sel then reaper.ImGui_PopStyleColor(ctx) end
                    if i % 2 ~= 0 then reaper.ImGui_SameLine(ctx, 0, 4) end
                end

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Text(ctx, "Hold Factor (Slowdown):")
                local factors = { 1.25, 1.5, 2.0, 3.0 }
                for i, fac in ipairs(factors) do
                    local is_cur = math.abs(new_fermata_hold - fac) < 0.05
                    if is_cur then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF) end
                    if reaper.ImGui_Button(ctx, string.format("%.2fx##new_fac", fac), (width - 40) / 4, 22) then
                        new_fermata_hold = fac
                    end
                    if is_cur then reaper.ImGui_PopStyleColor(ctx) end
                    if i < 4 then reaper.ImGui_SameLine(ctx, 0, 4) end
                end

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Text(ctx, "Playback Mode:")
                local new_modes = {
                    { id = "tempo_curve", l = "∿ Curve" },
                    { id = "tempo_dip",   l = "⎍ Step" },
                    { id = "visual_only", l = "👁 Visual" }
                }
                local new_btn_w = (width - 32) / 3
                for i, m in ipairs(new_modes) do
                    local is_m_sel = (new_fermata_mode == m.id)
                    if is_m_sel then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF) end
                    if reaper.ImGui_Button(ctx, m.l .. "##new_m", new_btn_w, 22) then
                        new_fermata_mode = m.id
                    end
                    if is_m_sel then reaper.ImGui_PopStyleColor(ctx) end
                    if i < 3 then reaper.ImGui_SameLine(ctx, 0, 4) end
                end

                reaper.ImGui_Spacing(ctx)
                if reaper.ImGui_Button(ctx, string.format("➕ Add Fermata at Cursor: Bar %d (Beat %.1f)", cur_bar, cur_beat), width - 24, 28) then
                    local ferm = FermataService.add_fermata(state, cur_qn, new_fermata_type, new_fermata_hold, state.active_tracks_cache, 1.0, new_fermata_mode)
                    state.selected_fermata = ferm
                end

                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                -- 3. List of Active Score Fermatas
                local f_count = state.fermatas and #state.fermatas or 0
                reaper.ImGui_TextColored(ctx, 0xE67E22FF, string.format("Score Fermatas (%d):", f_count))
                if reaper.ImGui_BeginChild(ctx, "FermataListChild", width - 24, 0, 1) then
                    if f_count == 0 then
                        reaper.ImGui_TextColored(ctx, 0x888888FF, "No fermatas in project yet.")
                    else
                        for idx, f in ipairs(state.fermatas) do
                            local f_lbl = string.format("Bar %d (Beat %.1f) - %s (%.1fx)", f.measure + 1, (f.beat_rel or 0) + 1, f.type or "standard", f.hold_factor or 1.5)
                            local is_f_sel = (state.selected_fermata and state.selected_fermata.id == f.id)
                            if is_f_sel then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9F1CFF) end
                            reaper.ImGui_Text(ctx, f_lbl)
                            if is_f_sel then reaper.ImGui_PopStyleColor(ctx) end

                            reaper.ImGui_SameLine(ctx, width - 90)
                            if reaper.ImGui_SmallButton(ctx, "Jump##f_" .. tostring(f.id)) then
                                state.selected_fermata = f
                                local t_sec = reaper.TimeMap2_QNToTime(0, f.qn)
                                reaper.SetEditCurPos(t_sec, true, false)
                            end
                            reaper.ImGui_SameLine(ctx)
                            if reaper.ImGui_SmallButton(ctx, "🗑##f_" .. tostring(f.id)) then
                                FermataService.remove_fermata(state, f.id, state.active_tracks_cache)
                                if state.selected_fermata and state.selected_fermata.id == f.id then
                                    state.selected_fermata = nil
                                end
                                break
                            end
                        end
                    end
                    reaper.ImGui_EndChild(ctx)
                end

                reaper.ImGui_EndTabItem(ctx)
            end

            reaper.ImGui_EndTabBar(ctx)
        end
        
        reaper.ImGui_EndChild(ctx)
    end
    
    reaper.ImGui_PopStyleColor(ctx)
end

return TempoDrawer


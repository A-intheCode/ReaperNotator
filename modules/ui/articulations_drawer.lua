-- ==============================================================================
-- REAPER Native Notator - Module: ArticulationsDrawer
-- Right drawer for Reaticulate articulations and techniques
-- Reads the Reaticulate bank of the focused track and groups by category
-- ==============================================================================

local Constants = require("constants")
local ReaticulateParser = require("services.reaticulate_parser")

local ArticulationsDrawer = {}

-- Local state for Articulations Drawer
local search_filter = ""
local selected_bank_override = {} -- Map: trk_guid -> bank

local CATEGORY_COLORS = {
    ["LEGATO"]           = 0x1ABC9CFF, -- Turquoise
    ["LONG / SUSTAIN"]   = 0x3498DBFF, -- Sapphire blue
    ["SHORT / STACCATO"] = 0xE67E22FF, -- Orange
    ["TRILLS / TREMOLO"] = 0x9B59B6FF, -- Violet
    ["EFFECTS / FX"]     = 0xE74C3CFF, -- Crimson
    ["OTHER"]            = 0x95A5A6FF  -- Light gray
}

local CATEGORY_ORDER = {
    "LEGATO",
    "LONG / SUSTAIN",
    "SHORT / STACCATO",
    "TRILLS / TREMOLO",
    "EFFECTS / FX",
    "OTHER"
}

local last_drawer_shown = false

function ArticulationsDrawer.render(ctx, state, midi_service, active_tracks_data, w, h, child_border, sidebar_flags)
    if not state.show_articulations_drawer then
        last_drawer_shown = false
        return
    end
    
    -- Reload banks fresh from disk every time the articulation drawer opens
    if not last_drawer_shown then
        ReaticulateParser.reload_all_banks(state)
        last_drawer_shown = true
    end
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1A1C22FF)
    
    if reaper.ImGui_BeginChild(ctx, "ArticulationsDrawer", w, h, child_border, sidebar_flags) then
        -- 1. Header with reload button
        reaper.ImGui_TextColored(ctx, 0x9B59B6FF, "ARTICULATIONS")
        reaper.ImGui_SameLine(ctx, w - 54)
        if reaper.ImGui_Button(ctx, "🔄##ReloadArtBanks", 22, 20) then
            local reloaded = ReaticulateParser.reload_all_banks(state)
            state.status_msg = string.format("Reloaded %d Reaticulate banks from disk", #reloaded)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Reload all banks from Reaticulate.reabank on disk")
        end
        reaper.ImGui_SameLine(ctx, w - 26)
        if reaper.ImGui_Button(ctx, "✕##CloseArtDrawer", 20, 20) then
            state.show_articulations_drawer = false
        end
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- 2. Resolve active track
        local cur_track = state.focused_track
        if (not cur_track or not reaper.ValidatePtr(cur_track, "MediaTrack*")) and active_tracks_data and active_tracks_data[1] then
            cur_track = active_tracks_data[1].track
        end
        if not cur_track or not reaper.ValidatePtr(cur_track, "MediaTrack*") then
            cur_track = reaper.GetSelectedTrack(0, 0)
        end
        
        local trk_name = "No Track"
        local trk_guid = nil
        if cur_track and reaper.ValidatePtr(cur_track, "MediaTrack*") then
            local _, tn = reaper.GetTrackName(cur_track)
            trk_name = tn or "Track"
            trk_guid = reaper.GetTrackGUID(cur_track)
        end
        
        -- Track selection dropdown if multiple tracks are active
        if active_tracks_data and #active_tracks_data > 1 then
            reaper.ImGui_SetNextItemWidth(ctx, -1)
            if reaper.ImGui_BeginCombo(ctx, "##ArtTrackSelect", "Track: " .. trk_name) then
                for _, tdata in ipairs(active_tracks_data) do
                    local is_sel = (tdata.track == cur_track)
                    if reaper.ImGui_Selectable(ctx, tdata.name or "Track", is_sel) then
                        state.focused_track = tdata.track
                        cur_track = tdata.track
                        trk_name = tdata.name or "Track"
                        trk_guid = tdata.guid
                    end
                end
                reaper.ImGui_EndCombo(ctx)
            end
        else
            reaper.ImGui_TextColored(ctx, 0x3498DBFF, "Track: " .. trk_name)
        end
        
        -- 3. Resolve Reaticulate bank for track
        local all_banks = ReaticulateParser.get_all_banks()
        local override_val = trk_guid and state.track_articulation_banks and state.track_articulation_banks[trk_guid]
        local bank = nil
        if cur_track then
            bank = ReaticulateParser.get_bank_for_track(cur_track, all_banks, override_val)
        end
        if not bank and #all_banks > 0 then
            bank = all_banks[1]
        end
        
        -- Bank tile and switch button (opens bank picker with search and libraries)
        local bank_lbl = bank and bank.name or "No Bank Selected"
        local bank_lib = (bank and bank.vendor and bank.vendor ~= "") and bank.vendor or (bank and bank.library or "General")
        local bank_sec = (bank and bank.section and bank.section ~= "") and bank.section or ""
        local bank_sub = bank_sec ~= "" and (bank_lib .. " • " .. bank_sec) or bank_lib
        
        reaper.ImGui_TextDisabled(ctx, "Active Bank:")
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x242832FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x333947FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x444C5FFF)
        
        local full_btn_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local btn_w = full_btn_w - 36
        if reaper.ImGui_Button(ctx, string.format("🏛 %s\n%s##ActiveBankBtn", bank_lbl, bank_sub), btn_w, 42) then
            state.show_bank_picker_modal = true
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Click to open Bank Picker and choose another bank for this track")
        end
        
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "🔍##BrowseBanksModalBtn", 32, 42) then
            state.show_bank_picker_modal = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Browse all Reaticulate banks with search & library filters")
        end
        
        -- Quick selection for multiple banks assigned to this track
        local track_banks = ReaticulateParser.get_track_assigned_banks(cur_track, all_banks)
        if #track_banks > 1 then
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_TextDisabled(ctx, "Track Banks:")
            for _, tb in ipairs(track_banks) do
                local is_tb_cur = (bank and tb.id == bank.id and tb.name == bank.name)
                if is_tb_cur then
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x9B59B6AA)
                end
                if reaper.ImGui_Button(ctx, (is_tb_cur and "✓ " or "") .. tb.name .. "##tb_quick_" .. tostring(tb.id), -1, 22) then
                    bank = tb
                    if trk_guid then
                        state.track_articulation_banks[trk_guid] = tb.id ~= "" and tb.id or tb.name
                        state:save_settings()
                    end
                end
                if is_tb_cur then
                    reaper.ImGui_PopStyleColor(ctx)
                end
            end
        end
        
        -- 4. Target status indicator (notes vs cursor)
        local sel_cnt = state:count_selected_notes()
        if sel_cnt > 0 then
            reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("Target: %d selected note(s)", sel_cnt))
        else
            reaper.ImGui_TextColored(ctx, 0x888888FF, "Target: Edit-Cursor position")
        end
        reaper.ImGui_Spacing(ctx)
        
        -- 5. Quick action: Remove articulation
        if reaper.ImGui_Button(ctx, "🗑 Remove Articulation", -1, 24) then
            midi_service.remove_selected_articulations(state, active_tracks_data)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Removes articulation from selected notes or deleted selected articulation marker.")
        end
        
        if reaper.ImGui_Button(ctx, "⚡ Auto-Chase & Return (Fix Playback)", -1, 24) then
            local it, tk = midi_service.get_target_item_and_take(state, active_tracks_data)
            if not tk and cur_track then
                local it_cnt = reaper.CountTrackMediaItems(cur_track)
                for ii = 0, it_cnt - 1 do
                    local m_it = reaper.GetTrackMediaItem(cur_track, ii)
                    local m_tk = m_it and reaper.GetActiveTake(m_it)
                    if m_tk and reaper.TakeIsMIDI(m_tk) then
                        it, tk = m_it, m_tk
                        break
                    end
                end
            end
            if not tk then
                tk = midi_service.get_active_midi_take()
            end
            if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") then
                reaper.Undo_BeginBlock2(0)
                midi_service.auto_chase_momentary_articulations(tk, bank)
                reaper.MIDI_Sort(tk)
                reaper.Undo_EndBlock2(0, "Notator: Auto-Chase Articulations", -1)
                reaper.UpdateArrange()
                midi_service.invalidate_cache()
                state.status_msg = "⚡ Recalculated auto-return articulations for active take!"
            else
                state.status_msg = "Please select or focus a track with MIDI item first."
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Automatically recalculates and inserts return Program Changes & Bank Selects (CC0/CC32) for momentary articulations (Marcato, Staccato, etc.).")
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- Vertical distance of articulations from staff line (independent)
        local cur_aoy = state.articulations_offset_y or 37.0
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        local aoy_changed, new_aoy = reaper.ImGui_SliderDouble(ctx, "##art_drawer_offset_slider", cur_aoy, 0.0, 74.0, "Offset to Staff: %.1f px")
        if aoy_changed then
            state.articulations_offset_y = new_aoy
            require('state').save_settings(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Adjusts the vertical distance of articulation text above the staff.")
        end
        
        -- Font size and weight of articulations (engraving standard)
        local cur_afs = state.articulations_font_size or 17.0
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        local afs_changed, new_afs = reaper.ImGui_SliderDouble(ctx, "##art_drawer_size_slider", cur_afs, 11.0, 26.0, "Font Size: %.1f pt")
        if afs_changed then
            state.articulations_font_size = new_afs
            require('state').save_settings(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Adjusts the font size of articulation text (e.g. 'Long', 'pizz.').")
        end
        
        local cur_bold = (state.articulations_bold ~= false)
        local bold_changed, new_bold = reaper.ImGui_Checkbox(ctx, "Bold Font (Engraving Standard)", cur_bold)
        if bold_changed then
            state.articulations_bold = new_bold
            require('state').save_settings(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Renders articulation text in bold weight for enhanced readability.")
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- 6. Search filter for articulations
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        local f_changed, new_f = reaper.ImGui_InputTextWithHint(ctx, "##ArtFilter", "🔍 Search articulations...", search_filter)
        if f_changed then
            search_filter = new_f
        end
        
        reaper.ImGui_Separator(ctx)
        
        -- 7. Render articulations grouped by category
        if bank and bank.articulations and #bank.articulations > 0 then
            local grouped = {}
            for _, cat in ipairs(CATEGORY_ORDER) do grouped[cat] = {} end
            
            local filter_low = search_filter:lower()
            
            for _, art in ipairs(bank.articulations) do
                local cat = ReaticulateParser.format_category(art.category)
                if not grouped[cat] then grouped[cat] = {} end
                
                local art_name_low = art.name:lower()
                if filter_low == "" or art_name_low:find(filter_low, 1, true) or cat:lower():find(filter_low, 1, true) then
                    table.insert(grouped[cat], art)
                end
            end
            
            local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
            local half_w = math.floor((avail_w - 6) / 2)
            
            for _, cat_name in ipairs(CATEGORY_ORDER) do
                local list = grouped[cat_name]
                if list and #list > 0 then
                    local cat_col = CATEGORY_COLORS[cat_name] or 0xAAAAAAFF
                    reaper.ImGui_Spacing(ctx)
                    reaper.ImGui_TextColored(ctx, cat_col, string.format("── %s (%d) ──", cat_name, #list))
                    
                    local i = 1
                    while i <= #list do
                        local art1 = list[i]
                        local art2 = list[i + 1]
                        
                        -- If name is short enough for 2 columns:
                        local is_long_1 = #art1.name > 15
                        local is_long_2 = art2 and (#art2.name > 15)
                        
                        if is_long_1 or not art2 or is_long_2 then
                            -- Single wide button
                            local dname = art1.name:gsub("(%a)([%w_']*)", function(f, r) return f:upper() .. r:lower() end)
                            local btn_lbl = string.format("%s##art_%d", dname, art1.pc)
                            if reaper.ImGui_Button(ctx, btn_lbl, -1, 24) then
                                midi_service.apply_reaticulate_art(state, art1, bank, cur_track, active_tracks_data)
                            end
                            if reaper.ImGui_IsItemHovered(ctx) then
                                reaper.ImGui_SetTooltip(ctx, string.format("%s\nPC %d | Bank: %s\nClick to assign to target", art1.name, art1.pc, bank.name))
                            end
                            i = i + 1
                        else
                            -- 2 columns
                            local dname1 = art1.name:gsub("(%a)([%w_']*)", function(f, r) return f:upper() .. r:lower() end)
                            local btn_lbl1 = string.format("%s##art_%d", dname1, art1.pc)
                            if reaper.ImGui_Button(ctx, btn_lbl1, half_w, 24) then
                                midi_service.apply_reaticulate_art(state, art1, bank, cur_track, active_tracks_data)
                            end
                            if reaper.ImGui_IsItemHovered(ctx) then
                                reaper.ImGui_SetTooltip(ctx, string.format("%s\nPC %d | Bank: %s\nClick to assign to target", art1.name, art1.pc, bank.name))
                            end
                            
                            reaper.ImGui_SameLine(ctx, 0, 6)
                            
                            local dname2 = art2.name:gsub("(%a)([%w_']*)", function(f, r) return f:upper() .. r:lower() end)
                            local btn_lbl2 = string.format("%s##art_%d", dname2, art2.pc)
                            if reaper.ImGui_Button(ctx, btn_lbl2, half_w, 24) then
                                midi_service.apply_reaticulate_art(state, art2, bank, cur_track, active_tracks_data)
                            end
                            if reaper.ImGui_IsItemHovered(ctx) then
                                reaper.ImGui_SetTooltip(ctx, string.format("%s\nPC %d | Bank: %s\nClick to assign to target", art2.name, art2.pc, bank.name))
                            end
                            
                            i = i + 2
                        end
                    end
                end
            end
        else
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_TextColored(ctx, 0x888888FF, "No articulations found in bank.")
            reaper.ImGui_TextWrapped(ctx, "Ensure Reaticulate is installed and the track has a bank assigned in Reaticulate or select a bank from the dropdown above.")
        end
        
        reaper.ImGui_EndChild(ctx)
    end
    
    reaper.ImGui_PopStyleColor(ctx)
end

return ArticulationsDrawer

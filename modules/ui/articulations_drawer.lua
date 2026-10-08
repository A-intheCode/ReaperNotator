-- ==============================================================================
-- REAPER Native Notator - Module: ArticulationsDrawer
-- Right drawer for Reaticulate articulations and techniques
-- Reads the Reaticulate bank of the focused track and groups by category
-- ==============================================================================

local Constants = require("constants")
local ReaticulateParser = require("services.reaticulate_parser")

local ArticulationsDrawer = {}

local function format_track_name_with_idx(trk)
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then return nil end
    local tidx = reaper.GetMediaTrackInfo_Value(trk, "IP_TRACKNUMBER")
    local _, tname = reaper.GetTrackName(trk)
    local num_str = (tidx and tidx > 0) and string.format("Track %d", math.floor(tidx)) or "Track"
    if tname and tname ~= "" then
        return string.format("%s: %s", num_str, tname)
    elseif tidx and tidx > 0 then
        return num_str
    end
    return nil
end

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
        
        -- Selective Playback Fix (Selected MIDI Item only)
        if reaper.ImGui_Button(ctx, "⚡ Fix Playback (Selective)##Drawer", -1, 24) then
            midi_service.fix_playback(state, active_tracks_data, false, true)
        end
        if reaper.ImGui_IsItemClicked(ctx, 1) then
            state.show_fix_last_resort_modal = true
            state.fix_last_resort_track_name = format_track_name_with_idx(cur_track) or (trk_name ~= "No Track" and trk_name) or "Track"
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Fix Playback (Selective):\nScans and reconciles ONLY the selected MIDI item (or item of selected notes) with the active sound bank.\nFixes playback, cleans micro-overlaps, and recalculates auto-chase without touching any other items.\n\nRight-click: Opens 'Fix of Last Resort' confirmation modal for this item.")
        end
        
        -- Global Playback Fix (All MIDI Items across entire project)
        if reaper.ImGui_Button(ctx, "⚡ Fix Playback (Global)##Drawer", -1, 24) then
            midi_service.fix_playback(state, active_tracks_data, false, false)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Fix Playback (Global):\nScans and reconciles ALL MIDI items across all tracks in the entire project.\nReconciles all note articulations with their respective sound banks, heals all micro-overlaps, recalculates auto-chase return points, and heals legacy dynamic hairpins.")
        end
        
        -- Slurs & Ties
        local avail_w_dt = reaper.ImGui_GetContentRegionAvail(ctx)
        local half_drawer_w = math.floor((avail_w_dt - 4) / 2)
        if reaper.ImGui_Button(ctx, "⌒ Slur [S]##Drawer", half_drawer_w, 24) then
            midi_service.toggle_slur(state, active_tracks_data)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Slur (Legato phrase mark) [Hotkey: S]:\nConnects 2 selected notes (or 1 note to next) with a Legato slur.\nPlays true Legato articulation and triggers sampler transitions.")
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "‿ Tie [T]##Drawer", half_drawer_w, 24) then
            midi_service.toggle_tie(state, active_tracks_data)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Tie (Held note) [Hotkey: T]:\nConnects 2 notes of the same pitch to combine their duration without re-striking.")
        end

        if reaper.ImGui_Button(ctx, "〰 Portamento [P]##Drawer", half_drawer_w, 24) then
            midi_service.toggle_portamento(state, active_tracks_data)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Portamento (Note Blending) [Hotkey: P]:\nConnects 2 selected notes with a straight portamento line.\nBlends notes via CC64 Sustain Hold (50% Note 1 to 50% Note 2) or alternative CC (CC34, CC5, CC65).\nRight-click portamento line to switch CC mode or toggle 'port.' label.")
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "〰 Glissando [G]##Drawer", half_drawer_w, 24) then
            midi_service.toggle_glissando(state, active_tracks_data)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Glissando (Chromatic Pitch Steps) [Hotkey: G]:\nConnects 2 selected notes with a wavy glissando line.\nGenerates chromatic pitch steps during playback (filtered out from score canvas).\nSupports Cross-Staff connections (e.g. Harp/Piano Bass to Treble/Alto Clef).")
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

function ArticulationsDrawer.render_last_resort_modal(ctx, state, active_tracks_data)
    if not state.show_fix_last_resort_modal then return end
    
    -- Center modal precisely in the horizontal AND vertical middle of REAPER-Notator / screen
    local cx, cy
    if state.is_maximized and state.screen_work_w and state.screen_work_w > 200 then
        cx = (state.screen_work_x or 0) + state.screen_work_w * 0.5
        cy = (state.screen_work_y or 0) + state.screen_work_h * 0.5
    elseif state.cur_win_x and state.cur_win_w and state.cur_win_w > 200 then
        cx = state.cur_win_x + state.cur_win_w * 0.5
        cy = state.cur_win_y + state.cur_win_h * 0.5
    end
    if not cx or not cy then
        if reaper.APIExists("ImGui_GetWindowViewport") and reaper.APIExists("ImGui_Viewport_GetCenter") then
            local vp = reaper.ImGui_GetWindowViewport(ctx)
            if vp then
                cx, cy = reaper.ImGui_Viewport_GetCenter(vp)
            end
        end
    end
    if not cx or not cy then
        if reaper.APIExists("ImGui_GetMainViewport") and reaper.APIExists("ImGui_Viewport_GetCenter") then
            local mvp = reaper.ImGui_GetMainViewport(ctx)
            if mvp then
                cx, cy = reaper.ImGui_Viewport_GetCenter(mvp)
            end
        end
    end
    
    reaper.ImGui_OpenPopup(ctx, "⚡ Fix Playback: Fix of Last Resort###FixLastResortModal")
    if cx and cy then
        reaper.ImGui_SetNextWindowPos(ctx, cx, cy, reaper.ImGui_Cond_Always(), 0.5, 0.5)
    end
    
    local popup_flags = reaper.ImGui_WindowFlags_AlwaysAutoResize()
    if reaper.APIExists("ImGui_WindowFlags_NoSavedSettings") then
        popup_flags = popup_flags | reaper.ImGui_WindowFlags_NoSavedSettings()
    end
    if reaper.APIExists("ImGui_WindowFlags_NoMove") then
        popup_flags = popup_flags | reaper.ImGui_WindowFlags_NoMove()
    end
    
    local visible, open = reaper.ImGui_BeginPopupModal(ctx, "⚡ Fix Playback: Fix of Last Resort###FixLastResortModal", true, popup_flags)
    if not open then
        state.show_fix_last_resort_modal = false
        reaper.ImGui_CloseCurrentPopup(ctx)
    end
    if visible then
        local trk_name = state.fix_last_resort_track_name
        if not trk_name or trk_name == "Track" or trk_name == "" then
            local trk = state.focused_track
            if (not trk or not reaper.ValidatePtr(trk, "MediaTrack*")) and active_tracks_data and active_tracks_data[1] then
                trk = active_tracks_data[1].track
            end
            if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then
                trk = reaper.GetSelectedTrack(0, 0)
            end
            if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then
                trk = reaper.GetTrack(0, 0)
            end
            trk_name = format_track_name_with_idx(trk) or "Active Track"
        end
        
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, "✓ Playback is already synchronized with the active sound bank.")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        reaper.ImGui_TextColored(ctx, 0xE74C3CFF, "⚠️ Fix of Last Resort (Emergency Articulation Reset)")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextWrapped(ctx, string.format(
            "Target: %s\n\nAll note articulations in this item match the instrument bank. If playback is still corrupted, silent, or notes are stuck, you can perform a Last Resort purge.\n\nThis will completely strip ALL articulation marks, keyswitches (CC0/CC32/Program Changes), and auto-chase events from this item, resetting it to clean default sustain playback.",
            trk_name
        ))
        
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Danger button in red
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xC0392BFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE74C3CFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x962D22FF)
        
        if reaper.ImGui_Button(ctx, "🧹 Purge All Articulations (Last Resort)", 280, 28) then
            state.show_fix_last_resort_modal = false
            reaper.ImGui_CloseCurrentPopup(ctx)
            local midi_service = require("services.midi_service")
            midi_service.fix_playback(state, active_tracks_data, true, true)
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_SameLine(ctx)
        
        if reaper.ImGui_Button(ctx, "✕ Cancel (Keep Articulations)", 200, 28) then
            state.show_fix_last_resort_modal = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        
        reaper.ImGui_EndPopup(ctx)
    else
        state.show_fix_last_resort_modal = false
    end
end

return ArticulationsDrawer

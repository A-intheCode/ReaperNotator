-- ==============================================================================
-- REAPER Native Notator - Module: BankPickerModal
-- Structured Reaticulate bank picker with vendor sidebar, section filters,
-- full-text search, and clean bank entries without duplicate scrollbars
-- ==============================================================================

local ReaticulateParser = require("services.reaticulate_parser")

local BankPickerModal = {}

-- Local state for picker
local search_query = ""
local selected_vendor_filter = "All"
local selected_library_filter = "All"
local selected_section_filter = "All"
local left_splitter_vendors_h = 220

function BankPickerModal.render(ctx, state, cur_track, active_tracks_data)
    if not state.show_bank_picker_modal then return end
    
    reaper.ImGui_SetNextWindowSize(ctx, 920, 640, reaper.ImGui_Cond_FirstUseEver())
    
    local flags = reaper.ImGui_WindowFlags_NoCollapse()
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "🏛 Select Articulation Bank###BankPickerModalWindow", true, flags)
    
    if not s_open then
        state.show_bank_picker_modal = false
        reaper.ImGui_End(ctx)
        return
    end
    
    if s_vis then
        -- 1. Resolve active track
        local trk = cur_track or state.focused_track
        if (not trk or not reaper.ValidatePtr(trk, "MediaTrack*")) and active_tracks_data and active_tracks_data[1] then
            trk = active_tracks_data[1].track
        end
        if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then
            trk = reaper.GetSelectedTrack(0, 0)
        end
        
        local trk_name = "No Track"
        local trk_guid = nil
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            local _, tn = reaper.GetTrackName(trk)
            trk_name = tn or "Track"
            trk_guid = reaper.GetTrackGUID(trk)
        end
        
        -- 2. Fetch all banks
        local all_banks = ReaticulateParser.get_all_banks(false, state)
        local active_bank = ReaticulateParser.get_bank_for_track(trk, all_banks, trk_guid and state.track_articulation_banks and state.track_articulation_banks[trk_guid])
        
        -- 3. Header with track info and disk reload button
        reaper.ImGui_TextColored(ctx, 0x3498DBFF, string.format("🎯 Target Track: %s", trk_name))
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("(Active: %s)", active_bank and active_bank.name or "None"))
        
        local reload_w = 175
        reaper.ImGui_SameLine(ctx, reaper.ImGui_GetWindowWidth(ctx) - reload_w - 18)
        if reaper.ImGui_Button(ctx, "🔄 Reload Banks from Disk", reload_w, 24) then
            all_banks = ReaticulateParser.reload_all_banks(state)
            state.status_msg = string.format("Reloaded %d Reaticulate banks from disk", #all_banks)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Scans REAPER scripts and data folders for Reaticulate.reabank and updates all banks fresh from disk.")
        end
        
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- 4. Quick assignment: Banks already configured on this track in Reaticulate
        local track_assigned = ReaticulateParser.get_track_assigned_banks(trk, all_banks)
        if #track_assigned > 0 then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x2A2312FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0xFF9F1C88)
            local assign_box_h = math.min(75, 30 + (#track_assigned * 26))
            if reaper.ImGui_BeginChild(ctx, "TrackAssignedBox", -1, assign_box_h, 1) then
                reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "⭐ Configured on this Track in Reaticulate:")
                for _, ab in ipairs(track_assigned) do
                    local is_act = (active_bank and ab.id == active_bank.id and ab.name == active_bank.name)
                    local btn_label = string.format("%s %s (%s)##act_%s", is_act and "✓" or "➔", ab.name, ab.vendor or "Reaticulate", tostring(ab.id))
                    if is_act then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2ECC7188)
                    end
                    if reaper.ImGui_Button(ctx, btn_label, -1, 22) then
                        if trk_guid then
                            state.track_articulation_banks[trk_guid] = ab.id ~= "" and ab.id or ab.name
                            state:save_settings()
                        end
                        state.status_msg = string.format("Selected track bank '%s'", ab.name)
                        state.show_bank_picker_modal = false
                    end
                    if is_act then
                        reaper.ImGui_PopStyleColor(ctx)
                    end
                end
                reaper.ImGui_EndChild(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx, 2)
            reaper.ImGui_Spacing(ctx)
        end
        
        -- 5. Search box (real-time filtering)
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        if reaper.ImGui_IsWindowAppearing(ctx) then
            reaper.ImGui_SetKeyboardFocusHere(ctx)
        end
        local f_changed, new_q = reaper.ImGui_InputTextWithHint(ctx, "##BankPickerSearch", "🔍 Search instrument, bank, vendor, or articulation (e.g. 'Flute', 'Violin', 'Spitfire', 'Legato')...", search_query)
        if f_changed then
            search_query = new_q
        end
        
        reaper.ImGui_Spacing(ctx)
        
        -- 6. Analyze and count vendors, libraries, and sections
        local vendors_count = {}
        local sections_map = {}
        for _, b in ipairs(all_banks) do
            local v = (b.vendor and b.vendor ~= "") and b.vendor or "User / Custom"
            vendors_count[v] = (vendors_count[v] or 0) + 1
            local s = (b.section and b.section ~= "") and b.section or "Other"
            sections_map[s] = true
        end
        
        local vendors_list = { "All" }
        for v, _ in pairs(vendors_count) do table.insert(vendors_list, v) end
        table.sort(vendors_list, function(a, b)
            if a == b then return false end
            if a == "All" then return true end
            if b == "All" then return false end
            return tostring(a):lower() < tostring(b):lower()
        end)
        
        -- Count libraries (for the currently selected vendor)
        local libraries_count = {}
        local total_libs_for_vendor = 0
        for _, b in ipairs(all_banks) do
            local v = (b.vendor and b.vendor ~= "") and b.vendor or "User / Custom"
            if selected_vendor_filter == "All" or v == selected_vendor_filter then
                local lib = (b.library and b.library ~= "") and b.library or "General"
                libraries_count[lib] = (libraries_count[lib] or 0) + 1
                total_libs_for_vendor = total_libs_for_vendor + 1
            end
        end
        
        local libraries_list = { "All" }
        for lib, _ in pairs(libraries_count) do table.insert(libraries_list, lib) end
        table.sort(libraries_list, function(a, b)
            if a == b then return false end
            if a == "All" then return true end
            if b == "All" then return false end
            return tostring(a):lower() < tostring(b):lower()
        end)
        
        -- Validate: If current library does not exist, reset to "All"
        if selected_library_filter ~= "All" and not libraries_count[selected_library_filter] then
            selected_library_filter = "All"
        end
        
        local sections_list = { "All" }
        for s, _ in pairs(sections_map) do table.insert(sections_list, s) end
        table.sort(sections_list, function(a, b)
            if a == b then return false end
            if a == "All" then return true end
            if b == "All" then return false end
            return tostring(a):lower() < tostring(b):lower()
        end)
        
        -- 7. TWO-PANE LAYOUT:
        -- Left: Vendor selection on top + horizontal splitter + Library selection below
        -- Right: Banks for the selected vendor/library combination
        local vendor_pane_w = 235
        local main_content_h = reaper.ImGui_GetWindowHeight(ctx) - reaper.ImGui_GetCursorPosY(ctx) - 42
        
        -- Adjustable height for upper pane (Vendors)
        if not left_splitter_vendors_h or left_splitter_vendors_h < 60 then
            left_splitter_vendors_h = math.floor(main_content_h * 0.42)
        end
        left_splitter_vendors_h = math.max(60, math.min(main_content_h - 100, left_splitter_vendors_h))
        
        -- LEFT PANEL: OUTER CONTAINER FOR VENDORS + SPLITTER + LIBRARIES
        if reaper.ImGui_BeginChild(ctx, "LeftSidebarColumn", vendor_pane_w, main_content_h, 0) then
            
            -- UPPER PANE: VENDORS
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x181A20FF)
            if reaper.ImGui_BeginChild(ctx, "VendorSelectionPane", -1, left_splitter_vendors_h, 1) then
                reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "🏢 VENDORS")
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)
                
                for _, v in ipairs(vendors_list) do
                    local count = (v == "All") and #all_banks or (vendors_count[v] or 0)
                    local is_sel = (selected_vendor_filter == v)
                    local v_label = string.format("%s (%d)##vendor_%s", v, count, v)
                    
                    if is_sel then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x3498DB88)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
                    end
                    
                    if reaper.ImGui_Selectable(ctx, v_label, is_sel) then
                        if selected_vendor_filter ~= v then
                            selected_vendor_filter = v
                            selected_library_filter = "All"
                        end
                    end
                    
                    if is_sel then
                        reaper.ImGui_PopStyleColor(ctx, 2)
                    end
                end
                reaper.ImGui_EndChild(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx)
            
            -- HORIZONTAL SPLITTER BETWEEN VENDORS AND LIBRARIES
            local splitter_h = 6
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2A2E39FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3498DBAA)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x3498DBFF)
            reaper.ImGui_Button(ctx, "##left_h_splitter", -1, splitter_h)
            if reaper.ImGui_IsItemActive(ctx) then
                local _, dy = reaper.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
                if dy ~= 0 then
                    left_splitter_vendors_h = math.max(60, math.min(main_content_h - 100, left_splitter_vendors_h + dy))
                    reaper.ImGui_ResetMouseDragDelta(ctx, 0)
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx) then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
            end
            reaper.ImGui_PopStyleColor(ctx, 3)
            
            -- LOWER PANE: LIBRARIES (fills remaining vertical space with -1)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x181A20FF)
            if reaper.ImGui_BeginChild(ctx, "LibrarySelectionPane", -1, -1, 1) then
                local lib_hdr = (selected_vendor_filter == "All") and "📚 LIBRARIES" or string.format("📚 %s", selected_vendor_filter)
                reaper.ImGui_TextColored(ctx, 0x3498DBFF, lib_hdr)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)
                
                for _, lib in ipairs(libraries_list) do
                    local count = (lib == "All") and total_libs_for_vendor or (libraries_count[lib] or 0)
                    local is_sel = (selected_library_filter == lib)
                    local lib_label = string.format("%s (%d)##lib_%s", lib, count, lib)
                    
                    if is_sel then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0x3498DB88)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
                    end
                    
                    if reaper.ImGui_Selectable(ctx, lib_label, is_sel) then
                        selected_library_filter = lib
                    end
                    
                    if is_sel then
                        reaper.ImGui_PopStyleColor(ctx, 2)
                    end
                end
                reaper.ImGui_EndChild(ctx)
            end
            reaper.ImGui_PopStyleColor(ctx)
            
            reaper.ImGui_EndChild(ctx)
        end
        
        reaper.ImGui_SameLine(ctx, 0, 10)
        
        -- RIGHT PANEL: BANKS OF SELECTED VENDOR & LIBRARY
        local banks_pane_w = reaper.ImGui_GetContentRegionAvail(ctx)
        if reaper.ImGui_BeginChild(ctx, "BanksContainerPane", banks_pane_w, main_content_h, 0) then
            
            -- Filter status bar at top of right panel
            reaper.ImGui_TextColored(ctx, 0x888888FF, "Vendor:")
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, selected_vendor_filter)
            
            if selected_library_filter ~= "All" then
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextDisabled(ctx, "➔")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextColored(ctx, 0x888888FF, "Library:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextColored(ctx, 0x3498DBFF, selected_library_filter)
            end
            
            -- Section filter combo on the right
            local sec_combo_w = 170
            reaper.ImGui_SameLine(ctx, banks_pane_w - sec_combo_w - 4)
            reaper.ImGui_SetNextItemWidth(ctx, sec_combo_w)
            if reaper.ImGui_BeginCombo(ctx, "##RightSectionCombo", "Section: " .. selected_section_filter) then
                for _, s in ipairs(sections_list) do
                    local is_sel = (selected_section_filter == s)
                    if reaper.ImGui_Selectable(ctx, s, is_sel) then
                        selected_section_filter = s
                    end
                end
                reaper.ImGui_EndCombo(ctx)
            end
            
            reaper.ImGui_Separator(ctx)
            
            -- Assemble matching banks
            local q_low = search_query:lower()
            local matched_banks = {}
            
            for _, b in ipairs(all_banks) do
                local b_ven = (b.vendor and b.vendor ~= "") and b.vendor or "User / Custom"
                local b_lib = (b.library and b.library ~= "") and b.library or "General"
                local b_sec = (b.section and b.section ~= "") and b.section or "Other"
                
                local pass_vendor = (selected_vendor_filter == "All") or (b_ven == selected_vendor_filter)
                local pass_library = (selected_library_filter == "All") or (b_lib == selected_library_filter)
                local pass_section = (selected_section_filter == "All") or (b_sec == selected_section_filter)
                
                if pass_vendor and pass_library and pass_section then
                    local pass_query = true
                    if q_low ~= "" then
                        local name_match = b.name:lower():find(q_low, 1, true)
                        local lib_match = b_lib:lower():find(q_low, 1, true)
                        local ven_match = b_ven:lower():find(q_low, 1, true)
                        local sec_match = b_sec:lower():find(q_low, 1, true)
                        local art_match = false
                        if b.articulations then
                            for _, a in ipairs(b.articulations) do
                                if a.name:lower():find(q_low, 1, true) then
                                    art_match = true
                                    break
                                end
                            end
                        end
                        pass_query = (name_match or lib_match or ven_match or sec_match or art_match)
                    end
                    
                    if pass_query then
                        table.insert(matched_banks, b)
                    end
                end
            end
            
            reaper.ImGui_TextDisabled(ctx, string.format("%d bank(s) found", #matched_banks))
            reaper.ImGui_Spacing(ctx)
            
            -- SINGLE SCROLLABLE LIST (No internal scrollbars per card)
            if reaper.ImGui_BeginChild(ctx, "BankScrollList", -1, -1, 1) then
                if #matched_banks == 0 then
                    reaper.ImGui_Spacing(ctx)
                    reaper.ImGui_TextColored(ctx, 0x888888FF, "No banks match your search or filter criteria.")
                    reaper.ImGui_TextDisabled(ctx, "Select 'All Vendors' on the left or clear the search field.")
                else
                    for idx, b in ipairs(matched_banks) do
                        local is_act = (active_bank and b.id == active_bank.id and b.name == active_bank.name)
                        local card_key = "card_" .. tostring(b.id ~= "" and b.id or b.name) .. "_" .. idx
                        
                        -- Draw card background
                        local start_cursor_x, start_cursor_y = reaper.ImGui_GetCursorScreenPos(ctx)
                        local row_w = reaper.ImGui_GetContentRegionAvail(ctx)
                        local row_h = 52
                        local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                        
                        local bg_col = is_act and 0x2ECC7120 or 0x22252CFF
                        local bdr_col = is_act and 0x2ECC71AA or 0x33374288
                        
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, start_cursor_x, start_cursor_y, start_cursor_x + row_w, start_cursor_y + row_h, bg_col, 4.0)
                        reaper.ImGui_DrawList_AddRect(draw_list, start_cursor_x, start_cursor_y, start_cursor_x + row_w, start_cursor_y + row_h, bdr_col, 4.0, 0, 1.0)
                        
                        -- Invisible button for whole-row clickability
                        reaper.ImGui_SetCursorScreenPos(ctx, start_cursor_x, start_cursor_y)
                        local row_clicked = reaper.ImGui_InvisibleButton(ctx, "##row_click_" .. card_key, row_w, row_h)
                        local is_row_hov = reaper.ImGui_IsItemHovered(ctx)
                        if is_row_hov and not is_act then
                            reaper.ImGui_DrawList_AddRect(draw_list, start_cursor_x, start_cursor_y, start_cursor_x + row_w, start_cursor_y + row_h, 0x3498DB88, 4.0, 0, 1.5)
                        end
                        
                        -- Draw card contents with fixed offset
                        reaper.ImGui_SetCursorScreenPos(ctx, start_cursor_x + 10, start_cursor_y + 6)
                        
                        -- Row 1: Bank name
                        reaper.ImGui_TextColored(ctx, is_act and 0x2ECC71FF or 0xFFFFFFFF, b.name)
                        
                        -- Row 2: Vendor • Library • Section
                        reaper.ImGui_SetCursorScreenPos(ctx, start_cursor_x + 10, start_cursor_y + 28)
                        local b_ven = (b.vendor and b.vendor ~= "") and b.vendor or "User / Custom"
                        local b_lib = (b.library and b.library ~= "") and b.library or "General"
                        local b_sec = (b.section and b.section ~= "") and b.section or "Standard"
                        local sub = string.format("%s • %s • %s", b_ven, b_lib, b_sec)
                        
                        local num_arts = b.articulations and #b.articulations or 0
                        if num_arts > 0 then
                            local sample_names = {}
                            for ai = 1, math.min(3, num_arts) do
                                table.insert(sample_names, b.articulations[ai].name)
                            end
                            sub = sub .. string.format("  |  %d arts (%s%s)", num_arts, table.concat(sample_names, ", "), num_arts > 3 and "..." or "")
                        end
                        reaper.ImGui_TextDisabled(ctx, sub)
                        
                        -- Selection button on the right
                        local btn_w = 80
                        reaper.ImGui_SetCursorScreenPos(ctx, start_cursor_x + row_w - btn_w - 8, start_cursor_y + 12)
                        
                        if is_act then
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2ECC7144)
                            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x2ECC71FF)
                            reaper.ImGui_Button(ctx, "✓ Active##" .. card_key, btn_w, 28)
                            reaper.ImGui_PopStyleColor(ctx, 2)
                        else
                            if reaper.ImGui_Button(ctx, "Select##" .. card_key, btn_w, 28) or (row_clicked and not is_act) then
                                if trk_guid then
                                    state.track_articulation_banks[trk_guid] = b.id ~= "" and b.id or b.name
                                    state:save_settings()
                                end
                                state.status_msg = string.format("Selected bank '%s' for track '%s'", b.name, trk_name)
                                state.show_bank_picker_modal = false
                            end
                        end
                        
                        -- Advance cursor downward for next row
                        reaper.ImGui_SetCursorScreenPos(ctx, start_cursor_x, start_cursor_y + row_h + 6)
                        reaper.ImGui_Dummy(ctx, 0, 0)
                    end
                end
                reaper.ImGui_EndChild(ctx)
            end
            
            reaper.ImGui_EndChild(ctx)
        end
        
        -- 8. Footer
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("Total: %d banks in Reaticulate library.", #all_banks))
        reaper.ImGui_SameLine(ctx, reaper.ImGui_GetWindowWidth(ctx) - 95)
        if reaper.ImGui_Button(ctx, "Close", 85, 24) then
            state.show_bank_picker_modal = false
        end
    end
    
    reaper.ImGui_End(ctx)
end

return BankPickerModal

-- ==============================================================================
-- REAPER Native Notator - Module: ClefDrawer
-- Professional 4-Category Clef & Octave Lines Drawer with Interactive Splitters
-- ==============================================================================

local Constants     = require("constants")
local OctaveService = require("services.octave_service")

local ClefDrawer = {
    search_filter = ""
}

function ClefDrawer.render(ctx, state, width, height, child_border, sidebar_flags, font_music, font_main)
    if not state.show_clefs then return end
    
    if not reaper.ImGui_BeginChild(ctx, "ClefDrawer", width, height, child_border, sidebar_flags) then
        return
    end
    
    -- ==================================================================
    -- 1. HEADER & TARGET RESOLUTION (Item vs Track Scope)
    -- ==================================================================
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "𝄞 CLEFS & OCTAVES")
    reaper.ImGui_SameLine(ctx, width - 28)
    if reaper.ImGui_SmallButton(ctx, "✕##CloseClefDrawer") then
        state.show_clefs = false
    end
    reaper.ImGui_Separator(ctx)
    
    -- Resolve Selected MIDI Item
    local sel_item = (state.selected_item and reaper.ValidatePtr(state.selected_item, "MediaItem*") and state.selected_item) or reaper.GetSelectedMediaItem(0, 0)
    local sel_take = sel_item and reaper.ValidatePtr(sel_item, "MediaItem*") and reaper.GetActiveTake(sel_item)
    local item_name = "None"
    local has_item = false
    local item_guid = nil
    local cur_item_clef = nil

    if sel_item and reaper.ValidatePtr(sel_item, "MediaItem*") then
        has_item = true
        item_guid = reaper.BR_GetMediaItemGUID and reaper.BR_GetMediaItemGUID(sel_item) or tostring(sel_item)
        if sel_take and reaper.ValidatePtr(sel_take, "MediaItem_Take*") then
            local _, iname = reaper.GetSetMediaItemTakeInfo_String(sel_take, "P_NAME", "", false)
            item_name = (iname and iname ~= "") and iname or "Selected Item"
        else
            item_name = "Selected Item"
        end
        local ok_c, c_ext = reaper.GetSetMediaItemInfo_String(sel_item, "P_EXT:notator_clef", "", false)
        if ok_c and c_ext and c_ext ~= "" and c_ext ~= "auto" then
            cur_item_clef = c_ext
        elseif state.item_clefs and item_guid and state.item_clefs[item_guid] then
            cur_item_clef = state.item_clefs[item_guid]
        end
    end

    -- Target Track Info
    local it_trk = has_item and reaper.GetMediaItem_Track(sel_item)
    local cur_trk = (it_trk and reaper.ValidatePtr(it_trk, "MediaTrack*") and it_trk) or state.focused_track
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        local sel_trk = reaper.GetSelectedTrack(0, 0)
        if sel_trk and reaper.ValidatePtr(sel_trk, "MediaTrack*") then
            cur_trk = sel_trk
            state.focused_track = cur_trk
        end
    end
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        if state.selected_notes then
            for _, sn in pairs(state.selected_notes) do
                if sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then
                    cur_trk = sn.track
                    state.focused_track = cur_trk
                    break
                end
            end
        end
    end
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        if state.selected_tracks then
            for s_guid in pairs(state.selected_tracks) do
                local trk_cnt = reaper.CountTracks(0)
                for ti = 0, trk_cnt - 1 do
                    local t = reaper.GetTrack(0, ti)
                    if t and reaper.GetTrackGUID(t) == s_guid then
                        cur_trk = t
                        state.focused_track = cur_trk
                        break
                    end
                end
                if cur_trk then break end
            end
        end
    end

    local trk_name = "None"
    local trk_guid = nil
    local has_track = false
    local cur_track_clef = "treble"
    if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        has_track = true
        local _, name = reaper.GetTrackName(cur_trk)
        trk_name = (name and name ~= "") and name or ("Track " .. math.floor(reaper.GetMediaTrackInfo_Value(cur_trk, "IP_TRACKNUMBER")))
        trk_guid = reaper.GetTrackGUID(cur_trk)
        cur_track_clef = state.track_clefs[trk_guid] or "treble"
    end

    -- Scope Switcher: Default to "item" if item selected, otherwise "track"
    if not state.clef_scope then
        state.clef_scope = has_item and "item" or "track"
    end
    if has_item and state._clef_last_has_item == false then
        state.clef_scope = "item"
    end
    state._clef_last_has_item = has_item
    if not has_item and state.clef_scope == "item" then
        state.clef_scope = "track"
    end

    local function render_scope_btn(label, target_scope, is_enabled)
        local is_active = (state.clef_scope == target_scope)
        if not is_enabled then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x666666FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x1A1C22FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x1A1C22FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1A1C22FF)
            reaper.ImGui_Button(ctx, label, -1, 23)
            reaper.ImGui_PopStyleColor(ctx, 4)
            return false
        end

        local bg = is_active and 0x2980B9FF or 0x222630FF
        local bg_hov = is_active and 0x3498DBFF or 0x303644FF
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), bg)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), bg_hov)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1B4F72FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), is_active and 0xFFFFFFFF or 0xBBBBBBFF)
        local clicked = reaper.ImGui_Button(ctx, label, -1, 23)
        reaper.ImGui_PopStyleColor(ctx, 4)
        if clicked then
            state.clef_scope = target_scope
        end
        return clicked
    end

    local short_item_name = #item_name > 18 and (item_name:sub(1, 16) .. "..") or item_name
    local short_trk_name  = #trk_name > 18 and (trk_name:sub(1, 16) .. "..") or trk_name

    render_scope_btn(string.format("📦 Selected Item: \"%s\"##ClefScopeItem", has_item and short_item_name or "None"), "item", has_item)
    render_scope_btn(string.format("🎵 Active Track: \"%s\"##ClefScopeTrk", has_track and short_trk_name or "None"), "track", has_track)

    if state.clef_scope == "item" and has_item then
        local eff_id = cur_item_clef or cur_track_clef
        local cur_def = Constants.CLEF_DEFS[eff_id]
        local cur_lbl = cur_def and cur_def.name or eff_id
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("Target: Item \"%s\"", short_item_name))
        reaper.ImGui_TextColored(ctx, 0xAAAAAAFF, string.format("Active Clef: %s", cur_lbl))
    elseif has_track then
        local cur_def = Constants.CLEF_DEFS[cur_track_clef]
        local cur_lbl = cur_def and cur_def.name or cur_track_clef
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("Target: Track \"%s\"", short_trk_name))
        reaper.ImGui_TextColored(ctx, 0xAAAAAAFF, string.format("Active Clef: %s", cur_lbl))
    else
        reaper.ImGui_TextColored(ctx, 0xE67E22FF, "Target: Select a MIDI item or track")
    end
    reaper.ImGui_Spacing(ctx)
    
    -- Search filter
    reaper.ImGui_PushItemWidth(ctx, width - 18)
    local f_changed, new_f = reaper.ImGui_InputTextWithHint(ctx, "##ClefFilter", "🔍 Search clef / octave...", ClefDrawer.search_filter)
    if f_changed then ClefDrawer.search_filter = new_f end
    reaper.ImGui_PopItemWidth(ctx)
    reaper.ImGui_Spacing(ctx)
    
    -- ==================================================================
    -- 2. SPLITTER & HEIGHT ALLOCATION FOR 4 CATEGORIES
    -- ==================================================================
    local header_used_h = 160
    local available_content_h = math.max(220, height - header_used_h)
    
    local h1 = state.clef_drawer_h1 or 180
    local h2 = state.clef_drawer_h2 or 180
    local h3 = state.clef_drawer_h3 or 140
    local min_section_h = 50
    
    -- Clamping
    h1 = math.max(min_section_h, math.min(320, h1))
    h2 = math.max(min_section_h, math.min(320, h2))
    h3 = math.max(min_section_h, math.min(260, h3))
    
    -- ==================================================================
    -- HELPER: DRAW CLEF PREVIEW CARD
    -- ==================================================================
    local function draw_clef_card(clef, card_w, card_h)
        local is_selected
        if state.clef_scope == "item" and has_item then
            is_selected = (clef.id == (cur_item_clef or cur_track_clef))
        else
            is_selected = (clef.id == cur_track_clef)
        end
        local p0_x, p0_y = reaper.ImGui_GetCursorScreenPos(ctx)
        local btn_id = "##clef_card_" .. clef.id
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), is_selected and 0x2E3648FF or 0x1E2128FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x363D50FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF9F1C33)
        
        local clicked = reaper.ImGui_Button(ctx, btn_id, card_w, card_h)
        local is_hov = reaper.ImGui_IsItemHovered(ctx)
        
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        -- Click handler
        if clicked then
            if state.clef_scope == "item" and has_item and sel_item then
                -- Immediately assign clef to the selected MIDI item!
                reaper.GetSetMediaItemInfo_String(sel_item, "P_EXT:notator_clef", clef.id, true)
                if item_guid then
                    state.item_clefs = state.item_clefs or {}
                    state.item_clefs[item_guid] = clef.id
                end
                cur_item_clef = clef.id
                
                -- Update item obj in active_tracks_data if present
                if state.active_tracks_data then
                    for _, td in ipairs(state.active_tracks_data) do
                        if td.items then
                            for _, it_obj in ipairs(td.items) do
                                if it_obj.item == sel_item then
                                    it_obj.clef = clef.id
                                end
                            end
                        end
                    end
                end
                
                state.cached_measure_map = nil
                state.cached_measure_map_sig = nil
                state._track_clefs_cache = nil
                state._cached_hdr_metrics = nil
                state:save_settings()
                if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
                if reaper.UpdateArrange then reaper.UpdateArrange() end
                state.status_msg = string.format("MIDI Item '%s': Clef set to %s", item_name, clef.name)
            elseif cur_trk and trk_guid then
                state.track_clefs[trk_guid] = clef.id
                cur_track_clef = clef.id
                state.cached_measure_map = nil
                state.cached_measure_map_sig = nil
                state._track_clefs_cache = nil
                state._cached_hdr_metrics = nil
                state:save_settings()
                if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
                if reaper.UpdateArrange then reaper.UpdateArrange() end
                state.status_msg = string.format("Track '%s': Clef set to %s", trk_name, clef.name)
            else
                state.status_msg = string.format("Clef selected: %s (Focus a track or select an item)", clef.name)
            end
        end
        
        -- Draw vector graphics on card
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        local x0 = p0_x
        local y0 = p0_y
        local x1 = p0_x + card_w
        local y1 = p0_y + card_h
        
        -- Border
        local border_col = is_selected and 0xFF9F1CFF or (is_hov and 0xFF9F1CAA or 0x3A3E4DFF)
        local border_w = is_selected and 2.0 or 1.0
        reaper.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, border_col, 4.0, 0, border_w)
        
        if is_selected then
            -- Small corner indicator for active clef
            reaper.ImGui_DrawList_AddTriangleFilled(dl, x1 - 10, y0, x1, y0, x1, y0 + 10, 0xFF9F1CFF)
        end
        
        -- Mini staff lines (5 lines centered in upper/middle area)
        local staff_w = card_w - 20
        local staff_x0 = x0 + 10
        local staff_x1 = staff_x0 + staff_w
        local staff_line_col = is_selected and 0xC0C5D0FF or (is_hov and 0x9BA1B0FF or 0x656A7AFF)
        
        local line_sp = 4.0
        local card_center_y = y0 + 26
        
        if clef.is_multi_staff == "grand" then
            -- 2 Mini-staves
            local st1_bot = y0 + 22
            local st2_bot = y0 + 38
            for l = 0, 4 do
                local ly1 = st1_bot - (l * 2.8)
                local ly2 = st2_bot - (l * 2.8)
                reaper.ImGui_DrawList_AddLine(dl, staff_x0, ly1, staff_x1, ly1, staff_line_col, 1.0)
                reaper.ImGui_DrawList_AddLine(dl, staff_x0, ly2, staff_x1, ly2, staff_line_col, 1.0)
            end
            -- System bracket / connector line on left
            reaper.ImGui_DrawList_AddLine(dl, staff_x0, st1_bot - 11.2, staff_x0, st2_bot, staff_line_col, 2.0)
            -- Symbols
            if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                local glyph_sz = 18
                local gy1 = (st1_bot - 2.8) - (glyph_sz * 2.012)
                local gy2 = (st2_bot - 8.4) - (glyph_sz * 2.012)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, glyph_sz, staff_x0 + 2, gy1, 0xFFFFFFFF, Constants.SMUFL.g_clef)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, glyph_sz, staff_x0 + 2, gy2, 0xFFFFFFFF, Constants.SMUFL.f_clef)
            end
        elseif clef.is_multi_staff == "harp_3staff" then
            -- 3 Mini-staves
            local st1_bot = y0 + 17
            local st2_bot = y0 + 28
            local st3_bot = y0 + 39
            for l = 0, 4 do
                local ly1 = st1_bot - (l * 2.0)
                local ly2 = st2_bot - (l * 2.0)
                local ly3 = st3_bot - (l * 2.0)
                reaper.ImGui_DrawList_AddLine(dl, staff_x0, ly1, staff_x1, ly1, staff_line_col, 0.9)
                reaper.ImGui_DrawList_AddLine(dl, staff_x0, ly2, staff_x1, ly2, staff_line_col, 0.9)
                reaper.ImGui_DrawList_AddLine(dl, staff_x0, ly3, staff_x1, ly3, staff_line_col, 0.9)
            end
            -- Harp brace
            reaper.ImGui_DrawList_AddLine(dl, staff_x0, st1_bot - 8.0, staff_x0, st3_bot, 0xFF9F1CFF, 2.2)
            if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                local glyph_sz = 14
                local gy1 = (st1_bot - 2.0) - (glyph_sz * 2.012)
                local gy2 = (st2_bot - 4.0) - (glyph_sz * 2.012)
                local gy3 = (st3_bot - 6.0) - (glyph_sz * 2.012)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, glyph_sz, staff_x0 + 2, gy1, 0xFFFFFFFF, Constants.SMUFL.g_clef)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, glyph_sz, staff_x0 + 2, gy2, 0xFFFFFFFF, Constants.SMUFL.c_clef)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, glyph_sz, staff_x0 + 2, gy3, 0xFFFFFFFF, Constants.SMUFL.f_clef)
            end
        else
            -- Single staff (5 lines or tab/blank)
            local lines_cnt = clef.staff_lines or 5
            local bot_y = card_center_y + ((lines_cnt - 1) * 0.5 * line_sp)
            for l = 0, lines_cnt - 1 do
                local ly = bot_y - (l * line_sp)
                reaper.ImGui_DrawList_AddLine(dl, staff_x0, ly, staff_x1, ly, staff_line_col, 1.0)
            end
            
            -- Clef glyph on staff line
            if font_music and clef.glyph and clef.glyph ~= "" and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                local glyph_sz = 26
                local anchor_line = clef.anchor_line or 3
                local anchor_y = bot_y - ((anchor_line - 1) * line_sp)
                local pos_y = anchor_y - (glyph_sz * 2.012)
                local pos_x = staff_x0 + 3
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, glyph_sz, pos_x, pos_y, 0xFFFFFFFF, clef.glyph)
            end
            
            -- Middle C reference note (whole note) for visual orientation
            if clef.c4_pos and not clef.unpitched and not clef.is_tab then
                local note_y = bot_y - (clef.c4_pos * (line_sp * 0.5))
                local note_x = staff_x0 + staff_w - 18
                local note_col = is_selected and 0xFF9F1CFF or (is_hov and 0xFFB347FF or 0xE0E0E0FF)
                
                -- Ledger line if outside staff
                if clef.c4_pos < 0 or clef.c4_pos > (lines_cnt - 1) * 2 then
                    reaper.ImGui_DrawList_AddLine(dl, note_x - 6, note_y, note_x + 6, note_y, staff_line_col, 1.2)
                end
                
                -- C4 notehead
                if font_music and Constants.SMUFL.note_whole and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                    local nsz = 16
                    reaper.ImGui_DrawList_AddTextEx(dl, font_music, nsz, note_x - 4, note_y - (nsz * 2.012), note_col, Constants.SMUFL.note_whole)
                else
                    reaper.ImGui_DrawList_AddCircle(dl, note_x, note_y, 3.2, note_col, 0, 1.5)
                end
            end
        end
        
        -- Clef name at bottom of card
        local lbl_col = is_selected and 0xFF9F1CFF or (is_hov and 0xFFFFFFFF or 0xBBBBBBFF)
        local lbl = clef.name
        if reaper.APIExists("ImGui_CalcTextSize") then
            local tw = reaper.ImGui_CalcTextSize(ctx, lbl)
            local max_tw = card_w - 8
            if tw > max_tw then
                while #lbl > 4 and reaper.ImGui_CalcTextSize(ctx, lbl .. "..") > max_tw do
                    lbl = lbl:sub(1, -2)
                end
                lbl = lbl .. ".."
            end
        end
        reaper.ImGui_DrawList_AddText(dl, x0 + 6, y1 - 18, lbl_col, lbl)
    end
    
    -- ==================================================================
    -- HELPER: RENDER A CATEGORY'S CARDS IN 2 COLUMNS
    -- ==================================================================
    local function render_category_items(cat_name)
        local items = Constants.CLEF_CATEGORIES and Constants.CLEF_CATEGORIES[cat_name]
        if not items or #items == 0 then
            items = {}
            if Constants.CLEFS_ORDERED and Constants.CLEF_DEFS then
                for _, cid in ipairs(Constants.CLEFS_ORDERED) do
                    local cdef = Constants.CLEF_DEFS[cid]
                    if cdef and cdef.cat == cat_name then
                        table.insert(items, cdef)
                    end
                end
            end
        end
        local col_w = math.floor((width - 28) / 2)
        local card_h = 66
        local filter_low = ClefDrawer.search_filter:lower()
        
        local visible_items = {}
        for _, clef in ipairs(items) do
            if filter_low == "" or clef.name:lower():find(filter_low, 1, true) or clef.id:lower():find(filter_low, 1, true) then
                table.insert(visible_items, clef)
            end
        end
        
        for i = 1, #visible_items, 2 do
            local left = visible_items[i]
            local right = visible_items[i + 1]
            
            draw_clef_card(left, col_w, card_h)
            if right then
                reaper.ImGui_SameLine(ctx, 0, 6)
                draw_clef_card(right, col_w, card_h)
            end
            reaper.ImGui_Spacing(ctx)
        end
    end
    
    -- ==================================================================
    -- HELPER: RENDER OCTAVE BUTTON (3 COLUMNS)
    -- ==================================================================
    local function render_octave_button(otype, btn_w, btn_h)
        local def = Constants.OCTAVE_LINE_DEFS[otype]
        if not def then return end
        
        local p0_x, p0_y = reaper.ImGui_GetCursorScreenPos(ctx)
        local btn_id = "##oct_btn_" .. otype
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x1E2128FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x363D50FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF9F1C33)
        
        local clicked = reaper.ImGui_Button(ctx, btn_id, btn_w, btn_h)
        local is_hov = reaper.ImGui_IsItemHovered(ctx)
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        if clicked then
            OctaveService.add_octave_line(state, trk_guid, otype)
        end
        
        -- Custom Drawing for authentic typography matching the screenshot
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        local x0 = p0_x
        local y0 = p0_y
        local x1 = p0_x + btn_w
        local y1 = p0_y + btn_h
        
        local border_col = is_hov and 0xFF9F1CAA or 0x3A3E4DFF
        reaper.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, border_col, 4.0, 0, 1.0)
        
        local txt_col = is_hov and 0xFFFFFFFF or 0xE8ECF2FF
        local corner_col = is_hov and 0xFF9F1CFF or 0x8892A4FF
        
        local mid_x = math.floor((x0 + x1) * 0.5)
        local mid_y = math.floor((y0 + y1) * 0.5)
        
        -- Label (e.g. "8", "15", "22", "loco") in italic serif style
        local label_str = def.label
        local tw = 12
        if reaper.APIExists("ImGui_CalcTextSize") then
            tw = reaper.ImGui_CalcTextSize(ctx, label_str)
        end
        local tx = mid_x - (tw * 0.5) - 3
        local ty = mid_y - 7
        reaper.ImGui_DrawList_AddText(dl, tx, ty, txt_col, label_str)
        
        -- Corner Hook (top corner ┐ or bottom corner ┘)
        local hx = tx + tw + 2
        local corner_h = 7
        local corner_w = 4
        if def.corner == "top" then
            local cy = ty + 1
            reaper.ImGui_DrawList_AddLine(dl, hx, cy, hx + corner_w, cy, corner_col, 1.6)
            reaper.ImGui_DrawList_AddLine(dl, hx + corner_w, cy, hx + corner_w, cy + corner_h, corner_col, 1.6)
        else
            local cy = ty + 12
            reaper.ImGui_DrawList_AddLine(dl, hx, cy, hx + corner_w, cy, corner_col, 1.6)
            reaper.ImGui_DrawList_AddLine(dl, hx + corner_w, cy - corner_h, hx + corner_w, cy, corner_col, 1.6)
        end
        
        if is_hov then
            reaper.ImGui_SetTooltip(ctx, string.format("%s\nClick to add octave line on track", def.name))
        end
    end
    
    -- ==================================================================
    -- HELPER: RENDER HORIZONTAL SPLITTER BAR
    -- ==================================================================
    local function render_splitter(id, current_h, splitter_idx)
        reaper.ImGui_Spacing(ctx)
        local splitter_h = 8
        local splitter_w = width - 14
        reaper.ImGui_InvisibleButton(ctx, id, splitter_w, splitter_h)
        local is_active = reaper.ImGui_IsItemActive(ctx)
        local is_hovered = reaper.ImGui_IsItemHovered(ctx)
        
        if is_active then
            local _, delta_y = reaper.ImGui_GetMouseDelta(ctx)
            if delta_y ~= 0 then
                local new_h = math.floor(current_h + delta_y)
                new_h = math.max(min_section_h, math.min(320, new_h))
                if splitter_idx == 1 then
                    state:save_clef_drawer_heights(new_h, nil, nil)
                elseif splitter_idx == 2 then
                    state:save_clef_drawer_heights(nil, new_h, nil)
                elseif splitter_idx == 3 then
                    state:save_clef_drawer_heights(nil, nil, new_h)
                end
            end
        end
        
        if is_hovered and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
            state:save_clef_drawer_heights(180, 180, 140)
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
        
        local grip_col = is_active and 0xFF9F1CFF or (is_hovered and 0xFFD285FF or 0x656A7AFF)
        reaper.ImGui_DrawList_AddRectFilled(dl, mid_x - 14, mid_y - 2, mid_x + 14, mid_y + 2, grip_col, 2.0)
        reaper.ImGui_Spacing(ctx)
    end
    
    -- ==================================================================
    -- 3. THE 4 RESIZABLE CATEGORIES
    -- ==================================================================
    
    -- --- CATEGORY 1: COMMON CLEFS ---
    reaper.ImGui_TextColored(ctx, 0xFFD700FF, "COMMON CLEFS")
    if reaper.ImGui_BeginChild(ctx, "ClefCat_Common", width - 12, h1, 0, reaper.ImGui_WindowFlags_None()) then
        render_category_items("Common Clefs")
        reaper.ImGui_EndChild(ctx)
    end
    
    -- Splitter 1 between Common and Uncommon
    render_splitter("##hsplitter_clef_1", h1, 1)
    
    -- --- CATEGORY 2: UNCOMMON CLEFS ---
    reaper.ImGui_TextColored(ctx, 0x3498DBFF, "UNCOMMON CLEFS")
    if reaper.ImGui_BeginChild(ctx, "ClefCat_Uncommon", width - 12, h2, 0, reaper.ImGui_WindowFlags_None()) then
        render_category_items("Uncommon Clefs")
        reaper.ImGui_EndChild(ctx)
    end
    
    -- Splitter 2 between Uncommon and Archaic
    render_splitter("##hsplitter_clef_2", h2, 2)
    
    -- --- CATEGORY 3: ARCHAIC CLEFS ---
    reaper.ImGui_TextColored(ctx, 0x9B59B6FF, "ARCHAIC CLEFS")
    if reaper.ImGui_BeginChild(ctx, "ClefCat_Archaic", width - 12, h3, 0, reaper.ImGui_WindowFlags_None()) then
        render_category_items("Archaic Clefs")
        reaper.ImGui_EndChild(ctx)
    end
    
    -- Splitter 3 between Archaic and Octave Lines
    render_splitter("##hsplitter_clef_3", h3, 3)
    
    -- --- CATEGORY 4: OCTAVE LINES (Takes remaining height) ---
    reaper.ImGui_TextColored(ctx, 0x1ABC9CFF, "OCTAVE LINES")
    if reaper.ImGui_BeginChild(ctx, "ClefCat_OctaveLines", width - 12, 0, 0, reaper.ImGui_WindowFlags_None()) then
        local oct_w = math.floor((width - 32) / 3)
        local oct_h = 36
        
        -- Row 1: 8 ┐, 15 ┐, 22 ┐
        render_octave_button("8va", oct_w, oct_h)
        reaper.ImGui_SameLine(ctx, 0, 6)
        render_octave_button("15ma", oct_w, oct_h)
        reaper.ImGui_SameLine(ctx, 0, 6)
        render_octave_button("22ma", oct_w, oct_h)
        
        reaper.ImGui_Spacing(ctx)
        
        -- Row 2: 8 ┘, 15 ┘, 22 ┘
        render_octave_button("8vb", oct_w, oct_h)
        reaper.ImGui_SameLine(ctx, 0, 6)
        render_octave_button("15mb", oct_w, oct_h)
        reaper.ImGui_SameLine(ctx, 0, 6)
        render_octave_button("22mb", oct_w, oct_h)
        
        reaper.ImGui_Spacing(ctx)
        
        -- Row 3: loco ┐
        local loco_w = math.floor((width - 24) * 0.5)
        render_octave_button("loco", loco_w, oct_h)
        
        reaper.ImGui_EndChild(ctx)
    end
    
    reaper.ImGui_EndChild(ctx)
end

return ClefDrawer

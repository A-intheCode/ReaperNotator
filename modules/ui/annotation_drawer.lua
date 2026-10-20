-- ==============================================================================
-- REAPER Native Notator - Module: AnnotationDrawer
-- Right Sidebar Drawer: Per-Track Annotation Layer Manager, 12 Color Presets,
-- Pen / Eraser Tools & Transparent PNG Management
-- ==============================================================================

local AnnotationService = require("services.annotation_service")

local AnnotationDrawer = {
    renaming_layer_id = nil,
    rename_buf = "",
    rename_just_opened = false
}

local function resolve_target_track(state)
    local cur_trk = state.focused_track
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        local sel_item = (state.selected_item and reaper.ValidatePtr(state.selected_item, "MediaItem*") and state.selected_item) or reaper.GetSelectedMediaItem(0, 0)
        if sel_item and reaper.ValidatePtr(sel_item, "MediaItem*") then
            cur_trk = reaper.GetMediaItem_Track(sel_item)
            state.focused_track = cur_trk
        end
    end
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        local sel_trk = reaper.GetSelectedTrack(0, 0)
        if sel_trk and reaper.ValidatePtr(sel_trk, "MediaTrack*") then
            cur_trk = sel_trk
            state.focused_track = cur_trk
        end
    end
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        if state.active_tracks_cache and #state.active_tracks_cache > 0 then
            local first_td = state.active_tracks_cache[1]
            if first_td and first_td.track and reaper.ValidatePtr(first_td.track, "MediaTrack*") then
                cur_trk = first_td.track
                state.focused_track = cur_trk
            end
        end
    end
    return cur_trk
end

function AnnotationDrawer.render(ctx, state, active_tracks_data, width, height, child_border, sidebar_flags)
    if not state.show_annotations_drawer then
        AnnotationDrawer.renaming_layer_id = nil
        AnnotationDrawer.rename_just_opened = false
        state.editing_annotation_layer = nil
        return
    end
    state.editing_annotation_layer = AnnotationDrawer.renaming_layer_id
    AnnotationService.ensure_state(state)

    if not reaper.ImGui_BeginChild(ctx, "AnnotationDrawer", width, height, child_border, sidebar_flags) then
        return
    end

    -- ==================================================================
    -- 1. HEADER
    -- ==================================================================
    reaper.ImGui_TextColored(ctx, 0xFF6B35FF, "🎨 ANNOTATION LAYERS")
    reaper.ImGui_SameLine(ctx, width - 28)
    if reaper.ImGui_SmallButton(ctx, "✕##CloseAnnotationDrawer") then
        state.show_annotations_drawer = false
        AnnotationDrawer.renaming_layer_id = nil
        AnnotationDrawer.rename_just_opened = false
        state.editing_annotation_layer = nil
        if state.annotation_tool == "pen" or state.annotation_tool == "eraser" then
            state.annotation_tool = "select"
        end
    end
    reaper.ImGui_Separator(ctx)

    -- Global visibility checkbox
    local show_all = (state.show_annotations_layer ~= false)
    local vis_changed, new_vis = reaper.ImGui_Checkbox(ctx, "Show Annotations on Score", show_all)
    if vis_changed then
        state.show_annotations_layer = new_vis
    end

    -- ==================================================================
    -- 2. TARGET TRACK SELECTOR
    -- ==================================================================
    local cur_trk = resolve_target_track(state)
    local trk_guid = nil
    local trk_name = "No Track Selected"
    if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        trk_guid = reaper.GetTrackGUID(cur_trk)
        local _, name = reaper.GetTrackName(cur_trk)
        local trk_num = math.floor(reaper.GetMediaTrackInfo_Value(cur_trk, "IP_TRACKNUMBER") or 1)
        trk_name = string.format("[%d] %s", trk_num, (name and name ~= "") and name or ("Track " .. trk_num))
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextDisabled(ctx, "Active Track:")
    reaper.ImGui_SetNextItemWidth(ctx, width - 16)
    if reaper.ImGui_BeginCombo(ctx, "##AnnTrackCombo", trk_name) then
        local list = active_tracks_data or state.active_tracks_cache or {}
        for _, td in ipairs(list) do
            if td.track and reaper.ValidatePtr(td.track, "MediaTrack*") then
                local lbl = string.format("[%d] %s", td.idx or 1, td.name or "Track")
                local is_sel = (td.track == cur_trk)
                if reaper.ImGui_Selectable(ctx, lbl .. "##ann_trk_" .. tostring(td.guid), is_sel) then
                    state.focused_track = td.track
                    cur_trk = td.track
                    trk_guid = td.guid
                end
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end

    -- 2b. PER-INSTRUMENT TILE RESOLUTION (4 STEPS)
    reaper.ImGui_Spacing(ctx)
    local cur_tw, cur_th, _, cur_res_info = AnnotationService.get_track_resolution(state, trk_guid)
    local cur_res_step = (cur_res_info and cur_res_info.step) or AnnotationService.DEFAULT_RES_STEP
    reaper.ImGui_TextDisabled(ctx, string.format("Instrument Resolution: %d×%d px", cur_tw, cur_th))
    local res_avail_w = width - 16
    local res_btn_w = math.floor((res_avail_w - 12) / 4)
    for i, rinfo in ipairs(AnnotationService.RESOLUTION_STEPS) do
        local is_sel_res = (cur_res_step == rinfo.step)
        if is_sel_res then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2980B9FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3498DBFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x262932FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x353A47FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xCCCCCCFF)
        end
        if reaper.ImGui_Button(ctx, rinfo.short .. "##ann_res_" .. tostring(rinfo.step), res_btn_w, 22) and trk_guid then
            AnnotationService.set_track_resolution_step(state, trk_guid, rinfo.step)
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, string.format(
                "%s (%d × %d px per Bar Tile)\nApplies to %s.\nExisting bar tiles on this track are automatically resampled.",
                rinfo.label, rinfo.w, rinfo.h, trk_name
            ))
        end
        if i < #AnnotationService.RESOLUTION_STEPS then
            reaper.ImGui_SameLine(ctx, 0, 4)
        end
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)

    -- ==================================================================
    -- 3. DRAWING TOOLS (PEN / ERASER / CURSOR) & BRUSH SIZE
    -- ==================================================================
    reaper.ImGui_TextDisabled(ctx, "Tool Mode:")
    local avail_w = width - 16
    local btn_w = math.floor((avail_w - 8) / 3)
    local cur_tool = state.annotation_tool or "pen"

    local function draw_tool_btn(id, label, active_col)
        local is_act = (cur_tool == id)
        if is_act then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), active_col)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), active_col)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x262932FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x353A47FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xCCCCCCFF)
        end
        local clicked = reaper.ImGui_Button(ctx, label .. "##ann_tool_" .. id, btn_w, 26)
        reaper.ImGui_PopStyleColor(ctx, 3)
        if clicked then
            state.annotation_tool = id
            cur_tool = id
        end
    end

    draw_tool_btn("pen", "✏ Pen", 0xE67E22FF)
    reaper.ImGui_SameLine(ctx, 0, 4)
    draw_tool_btn("eraser", "⌫ Erase", 0xE74C3CFF)
    reaper.ImGui_SameLine(ctx, 0, 4)
    draw_tool_btn("select", "↖ Notes", 0x3498DBFF)

    reaper.ImGui_Spacing(ctx)
    if cur_tool == "eraser" then
        reaper.ImGui_SetNextItemWidth(ctx, avail_w)
        local chg, val = reaper.ImGui_SliderDouble(ctx, "##EraserSize", state.annotation_eraser_size or 14.0, 2.0, 36.0, "Eraser Size: %.1f px")
        if chg then state.annotation_eraser_size = val end
    else
        reaper.ImGui_SetNextItemWidth(ctx, avail_w)
        local chg, val = reaper.ImGui_SliderDouble(ctx, "##BrushSize", state.annotation_brush_size or 4.0, 1.0, 20.0, "Pen Thickness: %.1f px")
        if chg then state.annotation_brush_size = val end
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)

    -- ==================================================================
    -- 4. 12 COLOR PRESETS (2x6 SWATCH GRID)
    -- ==================================================================
    reaper.ImGui_TextDisabled(ctx, "12 Color Presets:")
    local cols_per_row = 6
    local gap = 5
    local swatch_w = math.floor((avail_w - (cols_per_row - 1) * gap) / cols_per_row)
    local swatch_h = 24
    local dl = reaper.ImGui_GetWindowDrawList(ctx)

    for i, preset in ipairs(AnnotationService.COLOR_PRESETS) do
        if (i - 1) % cols_per_row ~= 0 then
            reaper.ImGui_SameLine(ctx, 0, gap)
        end
        local is_sel = (state.annotation_color_idx == i)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), preset.col)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), preset.col)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), preset.col)
        if reaper.ImGui_Button(ctx, "##color_preset_" .. tostring(i), swatch_w, swatch_h) then
            state.annotation_color_idx = i
            state.annotation_color = preset.col
            if state.annotation_tool == "eraser" then
                state.annotation_tool = "pen"
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)

        local x0, y0 = reaper.ImGui_GetItemRectMin(ctx)
        local x1, y1 = reaper.ImGui_GetItemRectMax(ctx)
        if is_sel then
            reaper.ImGui_DrawList_AddRect(dl, x0 - 1, y0 - 1, x1 + 1, y1 + 1, 0xFFFFFFFF, 3.0, 0, 2.2)
            reaper.ImGui_DrawList_AddRect(dl, x0 - 2, y0 - 2, x1 + 2, y1 + 2, 0xFF9F1CFF, 3.0, 0, 1.5)
        else
            reaper.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, 0x00000088, 2.0, 0, 1.0)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, preset.name)
        end
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)

    -- ==================================================================
    -- 5. TRACK LAYER STACK MANAGER
    -- ==================================================================
    if not trk_guid then
        reaper.ImGui_TextDisabled(ctx, "Select a track to manage layers.")
        reaper.ImGui_EndChild(ctx)
        return
    end

    local stack = AnnotationService.get_track_stack(state, trk_guid)
    local active_layer = AnnotationService.get_active_layer(state, trk_guid)

    reaper.ImGui_TextDisabled(ctx, "Track Layers (Top to Bottom):")

    -- Layer Action Toolbar: [+ Add] [Up] [Down] [Clear] [Delete]
    if reaper.ImGui_Button(ctx, "+ Layer##AddAnnLayer", 62, 22) then
        AnnotationService.add_layer(state, trk_guid)
        active_layer = AnnotationService.get_active_layer(state, trk_guid)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Create a new logical layer for this track.\n(No PNG files are created until you draw on a bar.)")
    end

    reaper.ImGui_SameLine(ctx, 0, 4)
    if reaper.ImGui_Button(ctx, "↑##MoveLayerUp", 24, 22) and active_layer then
        AnnotationService.move_layer(state, trk_guid, active_layer.id, 1)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Move layer up (render higher on top)")
    end

    reaper.ImGui_SameLine(ctx, 0, 4)
    if reaper.ImGui_Button(ctx, "↓##MoveLayerDown", 24, 22) and active_layer then
        AnnotationService.move_layer(state, trk_guid, active_layer.id, -1)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Move layer down (render underneath)")
    end

    reaper.ImGui_SameLine(ctx, 0, 4)
    if reaper.ImGui_Button(ctx, "🧹##ClearLayer", 28, 22) and active_layer then
        AnnotationService.clear_layer(state, trk_guid, active_layer.id)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Clear all painted bar tiles on this layer (deletes PNGs for this layer)")
    end

    reaper.ImGui_SameLine(ctx, 0, 4)
    if reaper.ImGui_Button(ctx, "🗑##DeleteLayer", 28, 22) and active_layer then
        AnnotationService.delete_layer(state, trk_guid, active_layer.id)
        active_layer = AnnotationService.get_active_layer(state, trk_guid)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Delete this layer and remove its PNG tiles from disk")
    end

    -- Active Layer Opacity Slider
    if active_layer then
        reaper.ImGui_SetNextItemWidth(ctx, avail_w)
        local cur_op = math.floor((active_layer.opacity or 1.0) * 100 + 0.5)
        local op_chg, new_op = reaper.ImGui_SliderInt(ctx, "##LayerOpacity", cur_op, 10, 100, "Layer Opacity: %d%%")
        if op_chg then
            active_layer.opacity = new_op / 100.0
            AnnotationService.save_metadata(state)
        end
    end

    reaper.ImGui_Spacing(ctx)

    -- Layer Stack List (Topmost layer displayed first)
    local list_h = math.max(90, reaper.ImGui_GetContentRegionAvail(ctx) - 36)
    if reaper.ImGui_BeginChild(ctx, "AnnLayerListChild", avail_w, list_h, 1) then
        for idx = #stack.layers, 1, -1 do
            local layer = stack.layers[idx]
            local is_act = (stack.active_layer_id == layer.id)
            local bar_cnt = AnnotationService.count_layer_bars(layer)

            reaper.ImGui_PushID(ctx, "layer_row_" .. tostring(layer.id))

            -- 1. Visibility toggle (👁)
            local was_hidden = (layer.visible == false)
            local vis_lbl = (not was_hidden) and "👁" or "·"
            if was_hidden then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x666666FF)
            end
            if reaper.ImGui_SmallButton(ctx, vis_lbl .. "##vis") then
                layer.visible = not layer.visible
                AnnotationService.save_metadata(state)
            end
            if was_hidden then
                reaper.ImGui_PopStyleColor(ctx)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, layer.visible and "Hide Layer" or "Show Layer")
            end

            -- 2. Lock toggle (🔒)
            reaper.ImGui_SameLine(ctx, 0, 3)
            local lock_lbl = layer.locked and "🔒" or "🔓"
            if reaper.ImGui_SmallButton(ctx, lock_lbl .. "##lock") then
                layer.locked = not layer.locked
                AnnotationService.save_metadata(state)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, layer.locked and "Unlock Layer" or "Lock Layer (prevent drawing/erasing)")
            end

            -- 3. Layer Name / Inline Rename / Selection
            reaper.ImGui_SameLine(ctx, 0, 5)
            if AnnotationDrawer.renaming_layer_id == layer.id then
                state.editing_annotation_layer = layer.id
                reaper.ImGui_SetNextItemWidth(ctx, avail_w - 75)
                if AnnotationDrawer.rename_just_opened then
                    reaper.ImGui_SetKeyboardFocusHere(ctx)
                    AnnotationDrawer.rename_just_opened = false
                end
                local enter_pressed, new_txt = reaper.ImGui_InputText(ctx, "##rename_inp", AnnotationDrawer.rename_buf, reaper.ImGui_InputTextFlags_EnterReturnsTrue() | reaper.ImGui_InputTextFlags_AutoSelectAll())
                if new_txt ~= nil then
                    AnnotationDrawer.rename_buf = new_txt
                end
                if reaper.APIExists("ImGui_Key_Escape") and reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                    AnnotationDrawer.renaming_layer_id = nil
                    AnnotationDrawer.rename_just_opened = false
                    state.editing_annotation_layer = nil
                elseif enter_pressed or (reaper.ImGui_IsMouseClicked(ctx, 0) and not reaper.ImGui_IsItemHovered(ctx)) then
                    if AnnotationDrawer.rename_buf ~= "" then
                        layer.name = AnnotationDrawer.rename_buf
                        AnnotationService.save_metadata(state)
                    end
                    AnnotationDrawer.renaming_layer_id = nil
                    AnnotationDrawer.rename_just_opened = false
                    state.editing_annotation_layer = nil
                end
            else
                local row_lbl = string.format("%s  (%d bar%s)", layer.name or "Layer", bar_cnt, bar_cnt == 1 and "" or "s")
                if is_act then
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), 0xE67E2255)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), 0xE67E2277)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFD700FF)
                end
                if reaper.ImGui_Selectable(ctx, row_lbl .. "##sel", is_act) then
                    stack.active_layer_id = layer.id
                    AnnotationService.save_metadata(state)
                end
                if is_act then
                    reaper.ImGui_PopStyleColor(ctx, 3)
                end
                if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                    AnnotationDrawer.renaming_layer_id = layer.id
                    AnnotationDrawer.rename_buf = layer.name or "Layer"
                    AnnotationDrawer.rename_just_opened = true
                    state.editing_annotation_layer = layer.id
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, string.format("%s\n• Painted Bars (PNG Sub-Tiles): %d\n• Double-click to rename", layer.name or "Layer", bar_cnt))
                end
            end

            reaper.ImGui_PopID(ctx)
        end
        reaper.ImGui_EndChild(ctx)
    end

    -- Footer: Open PNG Folder button
    if reaper.ImGui_Button(ctx, "📂 Open PNG Folder##OpenAnnDir", avail_w, 24) then
        local dir = AnnotationService.get_annotations_dir()
        if reaper.APIExists("CF_ShellExecute") then
            reaper.CF_ShellExecute(dir)
        else
            os.execute(string.format('start "" "%s"', dir:gsub("/", "\\")))
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Folder: " .. tostring(AnnotationService.get_annotations_dir()))
    end

    reaper.ImGui_EndChild(ctx)
end

return AnnotationDrawer


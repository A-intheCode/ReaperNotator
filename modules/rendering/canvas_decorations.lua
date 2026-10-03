-- ==============================================================================
-- REAPER Native Notator - Module: CanvasDecorations
-- Extracted rendering for:
-- 1. Tempo Markings (Absolute BPM & Gradual Transitions)
-- 2. Ottava / Octave Lines (8va, 15ma, 8vb, loco)
-- 3. Chord & Scale Lane (Lead-Sheet Chords & Scale Blocks)
-- ==============================================================================

local Constants = package.loaded["constants"] or require("constants")
local Engraver = package.loaded["rendering.engraver"] or require("rendering.engraver")
local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
local ScaleService = package.loaded["services.scale_service"] or require("services.scale_service")
local FontManager = package.loaded["rendering.font_manager"] or require("rendering.font_manager")

local CanvasDecorations = {}

-- ==============================================================================
-- 1. TEMPO MARKINGS
-- ==============================================================================
function CanvasDecorations.draw_tempo_markers(ctx, draw_list, state, fonts, first_staff_top_y, s, margin_left, system_start_x, qn_per_measure, measure_map, vis_min_qn, vis_max_qn, is_hovered, mouse_x, mouse_y, hov)
    local tempo_hovered_this_frame = nil
    local tempo_handle_hovered_this_frame = nil
    
    if (state.show_tempo_layer ~= false) and state.tempo_markers and #state.tempo_markers > 0 and first_staff_top_y then
        local tempo_offset_y = state.tempo_offset_y or 28.0
        local tempo_y = first_staff_top_y - tempo_offset_y * s
        local tempo_text_col = state.invert_mode and 0xFFFFFFFF or 0x111111FF
        local handle_radius = 5.0 * s
        
        for _, tm in ipairs(state.tempo_markers) do
            local is_selected = (state.selected_tempo_marker and state.selected_tempo_marker.id == tm.id)
            local is_editing = (state.editing_tempo_marker and state.editing_tempo_marker.id == tm.id)
            
            -- X1 (start) & X2 (end)
            local cur_start_qn = tm.start_qn
            local cur_end_qn = tm.end_qn or (tm.start_qn + 4.0)
            
            if is_selected or is_editing or (cur_end_qn >= vis_min_qn and cur_start_qn <= vis_max_qn) then
                -- Apply live-dragging preview
                if state.is_dragging_tempo and state.drag_tempo_marker and state.drag_tempo_marker.id == tm.id then
                    if tm.type == "absolute" then
                        if state.drag_tempo_target_qn then
                            cur_start_qn = math.max(0.0, state.drag_tempo_target_qn)
                            cur_end_qn = cur_start_qn + 4.0
                        end
                    else
                        if state.drag_tempo_handle == "start" and state.drag_tempo_target_qn then
                            cur_start_qn = math.min(cur_end_qn - 0.25, state.drag_tempo_target_qn)
                        elseif state.drag_tempo_handle == "end" and state.drag_tempo_target_qn then
                            cur_end_qn = math.max(cur_start_qn + 0.25, state.drag_tempo_target_qn)
                        elseif state.drag_tempo_handle == "body" and state.drag_tempo_delta_qn then
                            local span = cur_end_qn - cur_start_qn
                            cur_start_qn = math.max(0, tm.start_qn + state.drag_tempo_delta_qn)
                            cur_end_qn = cur_start_qn + span
                        end
                    end
                end
                
                local x1 = Engraver.qn_to_canvas_x(cur_start_qn, margin_left, s, qn_per_measure, measure_map)
                
                -- Initial tempo marking at the piece beginning (QN <= 0.05):
                -- Place left-aligned at system start above clef/time signature per publishing standards!
                if cur_start_qn <= 0.05 then
                    x1 = system_start_x + 18.0 * s
                end
                
                if tm.type == "absolute" then
                    -- ABSOLUTE TEMPO MARKING: e.g. Allegro (♩ = 140) or just ♩ = 140
                    local disp_str = tm:get_display_text()
                    local txt_sz = 14.0 * s
                    
                    -- Bounding box for hit-testing
                    local approx_w = #disp_str * 8.0 * s
                    local bb_x0 = x1 - 4 * s
                    local bb_y0 = tempo_y - 12 * s
                    local bb_x1 = x1 + approx_w + 4 * s
                    local bb_y1 = tempo_y + 6 * s
                    
                    local in_bb = (mouse_x >= bb_x0 and mouse_x <= bb_x1 and mouse_y >= bb_y0 and mouse_y <= bb_y1)
                    if in_bb and not state.is_dragging and not state.is_dragging_dynamic then
                        tempo_hovered_this_frame = tm
                        tempo_handle_hovered_this_frame = "start"
                        if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                            state.editing_tempo_marker = tm
                            state.editing_tempo_val = tostring(math.floor(tm.bpm or 120))
                            reaper.ImGui_OpenPopup(ctx, "edit_tempo_popup")
                        end
                    end
                    
                    local is_hov = (tempo_hovered_this_frame == tm)
                    
                    -- Selection frame
                    if is_selected then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, bb_x0, bb_y0, bb_x1, bb_y1, 0xFF9F1C33, 3.0)
                        reaper.ImGui_DrawList_AddRect(draw_list, bb_x0, bb_y0, bb_x1, bb_y1, 0xFF9F1CFF, 3.0, 0, 1.2 * s)
                    elseif is_hov then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, bb_x0, bb_y0, bb_x1, bb_y1, 0xFF9F1C18, 3.0)
                        reaper.ImGui_DrawList_AddRect(draw_list, bb_x0, bb_y0, bb_x1, bb_y1, 0xFF9F1C88, 3.0, 0, 1.0 * s)
                    end
                    
                    -- Draw text (bold)
                    local font_bold = (FontManager and FontManager.font_bold) or (fonts and fonts.font_bold)
                    if font_bold and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                        reaper.ImGui_DrawList_AddTextEx(draw_list, font_bold, txt_sz, x1, tempo_y - 10 * s, tempo_text_col, disp_str)
                    else
                        reaper.ImGui_DrawList_AddText(draw_list, x1, tempo_y - 10 * s, tempo_text_col, disp_str)
                    end
                    
                    -- Click to select
                    if in_bb and reaper.ImGui_IsMouseClicked(ctx, 0) and not is_editing then
                        state.selected_tempo_marker = tm
                        state.selected_dynamic = nil
                        state.selected_note = nil
                    end
                    
                    -- Right-click context menu
                    if in_bb and reaper.ImGui_IsMouseClicked(ctx, 1) then
                        state.selected_tempo_marker = tm
                        state.context_tempo_marker = tm
                        reaper.ImGui_OpenPopup(ctx, "tempo_context_popup")
                    end
                    
                else
                    -- GRADUAL TEMPO MARKING: e.g. poco accel. - - - - - - - ┤
                    local x2 = math.max(x1 + 30 * s, Engraver.qn_to_canvas_x(cur_end_qn, margin_left, s, qn_per_measure, measure_map))
                    local disp_str = tm:get_display_text()
                    local txt_sz = 13.0 * s
                    local text_w = #disp_str * 7.5 * s
                    
                    local h1_x, h1_y = x1, tempo_y
                    local h2_x, h2_y = x2, tempo_y
                    
                    -- Hit-testing for handles & line
                    if is_hovered and not state.is_dragging and not state.is_dragging_dynamic then
                        local d1 = math.sqrt((mouse_x - h1_x)^2 + (mouse_y - h1_y)^2)
                        local d2 = math.sqrt((mouse_x - h2_x)^2 + (mouse_y - h2_y)^2)
                        local in_line = (mouse_x >= x1 and mouse_x <= x2 and math.abs(mouse_y - tempo_y) <= 10 * s)
                        
                        if is_selected and d2 <= 10 * s then
                            tempo_hovered_this_frame = tm
                            tempo_handle_hovered_this_frame = "end"
                        elseif is_selected and d1 <= 10 * s then
                            tempo_hovered_this_frame = tm
                            tempo_handle_hovered_this_frame = "start"
                        elseif in_line then
                            tempo_hovered_this_frame = tm
                            tempo_handle_hovered_this_frame = "body"
                        end
                        
                        if in_line and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                            state.editing_tempo_marker = tm
                            state.editing_tempo_val = tostring(math.floor(tm.bpm or 120))
                            reaper.ImGui_OpenPopup(ctx, "edit_tempo_popup")
                        end
                    end
                    
                    local is_hov = (tempo_hovered_this_frame == tm)
                    
                    -- Selection highlight
                    if is_selected then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, x1 - 4 * s, tempo_y - 12 * s, x2 + 4 * s, tempo_y + 8 * s, 0xFF9F1C22, 3.0)
                        reaper.ImGui_DrawList_AddRect(draw_list, x1 - 4 * s, tempo_y - 12 * s, x2 + 4 * s, tempo_y + 8 * s, 0xFF9F1C88, 3.0, 0, 1.0 * s)
                    elseif is_hov then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, x1 - 4 * s, tempo_y - 12 * s, x2 + 4 * s, tempo_y + 8 * s, 0xFF9F1C11, 3.0)
                    end
                    
                    -- Italic text
                    local drew_tempo = false
                    if reaper.APIExists("ImGui_DrawList_AddTextEx") and font_italic then
                        drew_tempo = pcall(reaper.ImGui_DrawList_AddTextEx, draw_list, font_italic, txt_sz, x1, tempo_y - 10 * s, tempo_text_col, disp_str)
                    end
                    if not drew_tempo then
                        reaper.ImGui_DrawList_AddText(draw_list, x1, tempo_y - 10 * s, tempo_text_col, disp_str)
                    end
                    
                    -- Dashed line following text up to x2
                    local line_start_x = x1 + text_w + 6 * s
                    local line_col = is_selected and 0xFF9F1CFF or (is_hov and 0xF39C12FF or (state.invert_mode and 0xAAAAAAFF or 0x444444FF))
                    
                    if line_start_x < x2 then
                        local cur_lx = line_start_x
                        local dash_len = 5.0 * s
                        local dash_gap = 4.0 * s
                        while cur_lx + dash_len <= x2 do
                            reaper.ImGui_DrawList_AddLine(draw_list, cur_lx, tempo_y, cur_lx + dash_len, tempo_y, line_col, 1.2 * s)
                            cur_lx = cur_lx + dash_len + dash_gap
                        end
                        if cur_lx < x2 then
                            reaper.ImGui_DrawList_AddLine(draw_list, cur_lx, tempo_y, x2, tempo_y, line_col, 1.2 * s)
                        end
                        
                        -- Vertical terminal hook at end ┤
                        local hook_h = 6.0 * s
                        reaper.ImGui_DrawList_AddLine(draw_list, x2, tempo_y - hook_h, x2, tempo_y + hook_h, line_col, 1.5 * s)
                    end
                    
                    -- Dual handles (start & end) only when selected
                    if is_selected then
                        local h1_c = (tempo_handle_hovered_this_frame == "start") and 0xFF9F1CFF or 0x3498DBFF
                        reaper.ImGui_DrawList_AddCircleFilled(draw_list, h1_x, h1_y, handle_radius, h1_c)
                        reaper.ImGui_DrawList_AddCircle(draw_list, h1_x, h1_y, handle_radius + 1.0, 0xFFFFFFFF, 0, 1.0)
                        
                        local h2_c = (tempo_handle_hovered_this_frame == "end") and 0xFF9F1CFF or 0x2ECC71FF
                        reaper.ImGui_DrawList_AddCircleFilled(draw_list, h2_x, h2_y, handle_radius, h2_c)
                        reaper.ImGui_DrawList_AddCircle(draw_list, h2_x, h2_y, handle_radius + 1.0, 0xFFFFFFFF, 0, 1.0)
                    end
                    
                    -- Click to select
                    if is_hov and reaper.ImGui_IsMouseClicked(ctx, 0) and not is_editing then
                        state.selected_tempo_marker = tm
                        state.selected_dynamic = nil
                        state.selected_note = nil
                    end
                    
                    -- Right-click context menu
                    if is_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
                        state.selected_tempo_marker = tm
                        state.context_tempo_marker = tm
                        reaper.ImGui_OpenPopup(ctx, "tempo_context_popup")
                    end
                end
            end
        end
    end
    
    state.hovered_tempo_marker = tempo_hovered_this_frame
    state.hovered_tempo_handle = tempo_handle_hovered_this_frame
    if tempo_handle_hovered_this_frame == "start" or tempo_handle_hovered_this_frame == "end" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
    elseif tempo_handle_hovered_this_frame == "body" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end
    
    if hov then
        hov.tempo = tempo_hovered_this_frame
        hov.tempo_handle = tempo_handle_hovered_this_frame
    end
end

-- ==============================================================================
-- 2. OTTAVA / OCTAVE LINES
-- ==============================================================================
function CanvasDecorations.draw_octave_lines(ctx, draw_list, state, fonts, active_tracks_data, s, margin_left, qn_per_measure, measure_map, vis_min_qn, vis_max_qn, is_hovered, mouse_x, mouse_y, is_ctrl, hov)
    local octave_hovered_this_frame = nil
    local octave_handle_hovered_this_frame = nil
    
    if (state.show_octaves_layer ~= false) and active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.is_visible_vertically then
                local oct_lines = OctaveService.get_lines_for_track(state, tdata.guid)
                local staff_top_y = tdata.staff_top_y or (tdata.band_y0 + 40 * s)
                
                for _, oline in ipairs(oct_lines) do
                    local is_selected = (state.selected_octave_line == oline) or (state.selected_octave_lines and (state.selected_octave_lines[oline.id] ~= nil or state.selected_octave_lines[oline] ~= nil))
                    if is_selected or (oline.end_qn >= vis_min_qn and oline.start_qn <= vis_max_qn) then
                        local odef = Constants.OCTAVE_LINE_DEFS[oline.type] or Constants.OCTAVE_LINE_DEFS["8va"]
                        local ox1 = Engraver.cursor_qn_to_canvas_x(oline.start_qn, margin_left, s, qn_per_measure, measure_map)
                        local ox2 = Engraver.cursor_qn_to_canvas_x(oline.end_qn, margin_left, s, qn_per_measure, measure_map)
                        
                        local octave_offset_y = state.octave_offset_y or 18.0
                        local o_y = staff_top_y - octave_offset_y * s
                        local h_radius = 5.0 * s
                        
                        local h1_x, h1_y = ox1, o_y
                        local h2_x, h2_y = ox2, o_y
                        
                        -- Hover & Selection Detection
                        if is_hovered and not state.is_dragging and not state.is_dragging_dynamic and not state.is_dragging_tempo then
                            local d1 = math.sqrt((mouse_x - h1_x)^2 + (mouse_y - h1_y)^2)
                            local d2 = math.sqrt((mouse_x - h2_x)^2 + (mouse_y - h2_y)^2)
                            local in_body = (mouse_x >= ox1 and mouse_x <= ox2 and math.abs(mouse_y - o_y) <= 10 * s)
                            
                            if is_selected and d2 <= 10 * s then
                                octave_hovered_this_frame = oline
                                octave_handle_hovered_this_frame = "end"
                            elseif is_selected and d1 <= 10 * s then
                                octave_hovered_this_frame = oline
                                octave_handle_hovered_this_frame = "start"
                            elseif in_body then
                                octave_hovered_this_frame = oline
                                octave_handle_hovered_this_frame = "body"
                            end
                        end
                        
                        local is_hov = (octave_hovered_this_frame == oline)
                        
                        -- Click to select
                        if is_hov and reaper.ImGui_IsMouseClicked(ctx, 0) and not is_ctrl then
                            state.selected_octave_line = oline
                            state.selected_tempo_marker = nil
                            state.selected_dynamic = nil
                        end
                        
                        -- Context menu on right-click
                        if is_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
                            state.selected_octave_line = oline
                            reaper.ImGui_OpenPopup(ctx, "octave_context_popup")
                        end
                        
                        -- Draw:
                        local line_col = is_selected and 0x3498DBFF or (is_hov and 0xFF9F1CFF or (state.invert_mode and 0xCCCCCCFF or 0x222222FF))
                        local txt_col = line_col
                        
                        -- Highlight rect on selection or hover
                        if is_selected then
                            local sel_y0 = o_y - 8 * s
                            local sel_y1 = o_y + 12 * s
                            reaper.ImGui_DrawList_AddRectFilled(draw_list, ox1 - 4 * s, sel_y0, ox2 + 4 * s, sel_y1, 0x3498DB22, 3.0)
                            reaper.ImGui_DrawList_AddRect(draw_list, ox1 - 4 * s, sel_y0, ox2 + 4 * s, sel_y1, 0x3498DB88, 3.0, 0, 1.0 * s)
                        elseif is_hov then
                            local sel_y0 = o_y - 8 * s
                            local sel_y1 = o_y + 12 * s
                            reaper.ImGui_DrawList_AddRectFilled(draw_list, ox1 - 4 * s, sel_y0, ox2 + 4 * s, sel_y1, 0xFF9F1C18, 3.0)
                            reaper.ImGui_DrawList_AddRect(draw_list, ox1 - 4 * s, sel_y0, ox2 + 4 * s, sel_y1, 0xFF9F1C66, 3.0, 0, 1.0 * s)
                        end
                        
                        -- Text (e.g. "8", "15", "22", "loco")
                        local lbl_text = odef.label
                        local tw = 12 * s
                        if reaper.APIExists("ImGui_CalcTextSize") then
                            tw = reaper.ImGui_CalcTextSize(ctx, lbl_text)
                        end
                        reaper.ImGui_DrawList_AddText(draw_list, ox1, o_y - 7 * s, txt_col, lbl_text)
                        
                        -- Dashed line
                        local cur_lx = ox1 + tw + 4 * s
                        local dash_len = 6.0 * s
                        local dash_gap = 4.0 * s
                        while cur_lx + dash_len <= ox2 do
                            reaper.ImGui_DrawList_AddLine(draw_list, cur_lx, o_y, cur_lx + dash_len, o_y, line_col, 1.5 * s)
                            cur_lx = cur_lx + dash_len + dash_gap
                        end
                        if cur_lx < ox2 then
                            reaper.ImGui_DrawList_AddLine(draw_list, cur_lx, o_y, ox2, o_y, line_col, 1.5 * s)
                        end
                        
                        -- Terminal hook at line end: always pointing downward ┐
                        local hook_len = 8.0 * s
                        reaper.ImGui_DrawList_AddLine(draw_list, ox2, o_y, ox2, o_y + hook_len, line_col, 1.8 * s)
                        
                        -- Dual handles (ONLY when selected):
                        if is_selected then
                            local h1_c = (octave_handle_hovered_this_frame == "start") and 0xFF9F1CFF or 0x3498DBFF
                            reaper.ImGui_DrawList_AddCircleFilled(draw_list, h1_x, h1_y, h_radius, h1_c)
                            reaper.ImGui_DrawList_AddCircle(draw_list, h1_x, h1_y, h_radius + 1.0, 0xFFFFFFFF, 0, 1.0)
                            
                            local h2_c = (octave_handle_hovered_this_frame == "end") and 0xFF9F1CFF or 0x2ECC71FF
                            reaper.ImGui_DrawList_AddCircleFilled(draw_list, h2_x, h2_y, h_radius, h2_c)
                            reaper.ImGui_DrawList_AddCircle(draw_list, h2_x, h2_y, h_radius + 1.0, 0xFFFFFFFF, 0, 1.0)
                        end
                    end
                end
            end
        end
    end
    
    state.hovered_octave_line = octave_hovered_this_frame
    state.hovered_octave_handle = octave_handle_hovered_this_frame
    if octave_handle_hovered_this_frame == "start" or octave_handle_hovered_this_frame == "end" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
    elseif octave_handle_hovered_this_frame == "body" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end
    
    if hov then
        hov.octave = octave_hovered_this_frame
        hov.octave_handle = octave_handle_hovered_this_frame
    end
end

-- ==============================================================================
-- 3. CHORD / SCALE LANE
-- ==============================================================================
function CanvasDecorations.draw_chord_scale_lane(ctx, draw_list, state, fonts, s, canvas_p0_x, canvas_p0_y, staff_end_x, margin_left, system_start_x, hdr_x0, hdr_x1, qn_per_measure, measure_map, cull_min_x, cull_max_x, cull_min_y, cull_max_y, is_hovered, mouse_x, mouse_y, is_shift, hov)
    local chord_hovered_this_frame = nil
    local chord_handle_hovered_this_frame = nil
    if (state.show_chord_lane ~= false) then
        local ScaleService = package.loaded["services.scale_service"] or require("services.scale_service")
        local lane_y0 = canvas_p0_y + 4 * s
        local lane_y1 = lane_y0 + 34 * s
        local lane_mid_y = (lane_y0 + lane_y1) * 0.5
        local lane_x0 = math.max(system_start_x, cull_min_x)
        local lane_x1 = math.min(staff_end_x, cull_max_x)

        if lane_y1 >= cull_min_y and lane_y0 <= cull_max_y and lane_x0 < lane_x1 then
            -- Background strip of the chord lane
            reaper.ImGui_DrawList_AddRectFilled(draw_list, lane_x0, lane_y0, lane_x1, lane_y1, 0x1E202533, 4.0)
            reaper.ImGui_DrawList_AddLine(draw_list, lane_x0, lane_y1, lane_x1, lane_y1, 0xFFFFFF15, 1.0 * s)

            -- Sticky header badge on the far left
            local chd_badge_x0 = hdr_x0
            local chd_badge_x1 = hdr_x1
            local is_badge_hov = is_hovered and (mouse_x >= chd_badge_x0 and mouse_x <= chd_badge_x1 and mouse_y >= lane_y0 and mouse_y <= lane_y1)
            local badge_bg = is_badge_hov and 0x34495ECC or 0x242730EE
            local badge_bdr = is_badge_hov and 0x5BC0DEFF or 0x5BC0DE66
            reaper.ImGui_DrawList_AddRectFilled(draw_list, chd_badge_x0, lane_y0 + 2 * s, chd_badge_x1, lane_y1 - 2 * s, badge_bg, 4.0)
            reaper.ImGui_DrawList_AddRect(draw_list, chd_badge_x0, lane_y0 + 2 * s, chd_badge_x1, lane_y1 - 2 * s, badge_bdr, 4.0, 0, 1.2 * s)

            local hdr_lbl = "🎵 CHORDS"
            reaper.ImGui_DrawList_AddText(draw_list, chd_badge_x0 + 8 * s, lane_mid_y - 7 * s, 0x5BC0DEFF, hdr_lbl)

            if is_badge_hov then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                reaper.ImGui_SetTooltip(ctx, "Chord & Scale Lane\nDouble-click in lane to add chord block\nRight-click for target tracks & options")
                if reaper.ImGui_IsMouseClicked(ctx, 1) then
                    state.context_chord_item = nil
                    state.context_chord_qn = 0.0
                    reaper.ImGui_OpenPopup(ctx, "chord_lane_context_popup")
                end
            end

            -- Live dragging preview
            if state.drag_chord_item and reaper.ImGui_IsMouseDragging(ctx, 0, 2.0) and not state.is_resizing_item then
                state.is_dragging_chord = true
                local snap_grid = is_shift and 0.001 or (state.grid_qn or 0.5)
                local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
                local ci = state.drag_chord_item
                local orig_s = state.drag_chord_orig_start or ci.start_qn
                local orig_e = state.drag_chord_orig_end or ci.end_qn

                if state.drag_chord_handle == "start" then
                    local max_s = (orig_e or 4.0) - 0.25
                    ci.start_qn = math.min(max_s, math.max(0.0, target_qn))
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
                elseif state.drag_chord_handle == "end" then
                    local min_e = (orig_s or 0.0) + 0.25
                    ci.end_qn = math.max(min_e, target_qn)
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
                elseif state.drag_chord_handle == "body" then
                    local start_qn_at_click = Engraver.canvas_x_to_qn(state.drag_chord_start_x or mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
                    local delta_qn = target_qn - start_qn_at_click
                    local span = (orig_e or (orig_s + 4.0)) - orig_s
                    local new_s = math.max(0.0, orig_s + delta_qn)
                    ci.start_qn = new_s
                    ci.end_qn = new_s + span
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                end
            end

            local can_hover = is_hovered and not state.is_dragging and not state.is_dragging_dynamic and not state.is_dragging_hairpin and not state.is_dragging_articulation and not state.is_resizing_item

            for _, ci in ipairs(state.chord_items or {}) do
                local cur_s = ci.start_qn
                local cur_e = ci.end_qn
                local x1 = Engraver.cursor_qn_to_canvas_x(cur_s, margin_left, s, qn_per_measure, measure_map)
                local x2 = Engraver.cursor_qn_to_canvas_x(cur_e, margin_left, s, qn_per_measure, measure_map)
                x2 = math.max(x1 + 32 * s, x2)

                if x2 >= cull_min_x and x1 <= cull_max_x then
                    local is_selected = (state.selected_chord_item and state.selected_chord_item.id == ci.id)
                    local is_editing = (state.editing_chord_item and state.editing_chord_item.id == ci.id)

                    local h1_x, h1_y = x1, lane_mid_y
                    local h2_x, h2_y = x2, lane_mid_y
                    local dist_h1 = math.sqrt((mouse_x - h1_x)^2 + (mouse_y - h1_y)^2)
                    local dist_h2 = math.sqrt((mouse_x - h2_x)^2 + (mouse_y - h2_y)^2)
                    local in_body = (mouse_x >= x1 and mouse_x <= x2 and mouse_y >= lane_y0 and mouse_y <= lane_y1)

                    if can_hover and not state.is_dragging_chord then
                        if dist_h1 <= 9.0 * s then
                            chord_hovered_this_frame = ci
                            chord_handle_hovered_this_frame = "start"
                        elseif dist_h2 <= 9.0 * s then
                            chord_hovered_this_frame = ci
                            chord_handle_hovered_this_frame = "end"
                        elseif in_body then
                            chord_hovered_this_frame = ci
                            chord_handle_hovered_this_frame = "body"
                        end
                    end

                    local is_hov = (chord_hovered_this_frame and chord_hovered_this_frame.id == ci.id)

                    if is_hov and reaper.ImGui_IsMouseClicked(ctx, 0) and not is_ctrl and not is_editing then
                        state:clear_selection()
                        state.selected_chord_item = ci
                        state.drag_chord_item = ci
                        state.drag_chord_handle = chord_handle_hovered_this_frame or "body"
                        state.drag_chord_start_x = mouse_x
                        state.drag_chord_orig_start = ci.start_qn
                        state.drag_chord_orig_end = ci.end_qn
                        state.drag_chord_target_qn = (state.drag_chord_handle == "end") and ci.end_qn or ci.start_qn
                        state.drag_chord_delta_qn = 0
                    end

                    if is_hov and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                        state:clear_selection()
                        state.selected_chord_item = ci
                        state.editing_chord_item = ci
                        state.editing_chord_str = ci.text
                        state.editing_chord_just_opened = true
                        state.is_dragging_chord = false
                        state.drag_chord_item = nil
                    end

                    if is_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
                        state.selected_chord_item = ci
                        state.context_chord_item = ci
                        state.context_chord_qn = ci.start_qn
                        reaper.ImGui_OpenPopup(ctx, "chord_lane_context_popup")
                    end

                    if is_selected or is_hov then
                        local bg_c = is_selected and 0x5BC0DE2E or 0x5BC0DE14
                        local bdr_c = is_selected and 0x5BC0DECC or 0x5BC0DE66
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, x1, lane_y0 + 2 * s, x2, lane_y1 - 2 * s, bg_c, 3.0)
                        reaper.ImGui_DrawList_AddRect(draw_list, x1, lane_y0 + 2 * s, x2, lane_y1 - 2 * s, bdr_c, 3.0, 0, 1.0 * s)
                    end

                    -- DRAW BRACKETS [ - - - - ]
                    local bracket_col = is_selected and 0xFF9F1CFF or (is_hov and 0x5BC0DEFF or 0x5BC0DECC)
                    local hook_h = 7.5 * s
                    local hook_w = 6.0 * s
                    local line_th = 2.2 * s

                    -- 1. Opening bracket [
                    reaper.ImGui_DrawList_AddLine(draw_list, x1, lane_mid_y - hook_h, x1, lane_mid_y + hook_h, bracket_col, line_th)
                    reaper.ImGui_DrawList_AddLine(draw_list, x1, lane_mid_y - hook_h, x1 + hook_w, lane_mid_y - hook_h, bracket_col, line_th)
                    reaper.ImGui_DrawList_AddLine(draw_list, x1, lane_mid_y + hook_h, x1 + hook_w, lane_mid_y + hook_h, bracket_col, line_th)

                    -- 2. Closing bracket ]
                    reaper.ImGui_DrawList_AddLine(draw_list, x2, lane_mid_y - hook_h, x2, lane_mid_y + hook_h, bracket_col, line_th)
                    reaper.ImGui_DrawList_AddLine(draw_list, x2 - hook_w, lane_mid_y - hook_h, x2, lane_mid_y - hook_h, bracket_col, line_th)
                    reaper.ImGui_DrawList_AddLine(draw_list, x2 - hook_w, lane_mid_y + hook_h, x2, lane_mid_y + hook_h, bracket_col, line_th)

                    -- 3. Text badge at start
                    local txt_str = ci.text or "C"
                    local tw = #txt_str * 8.5 * s
                    if reaper.APIExists("ImGui_CalcTextSize") then
                        tw = reaper.ImGui_CalcTextSize(ctx, txt_str)
                    end

                    local badge_x0 = x1 + 4 * s
                    local badge_x1 = badge_x0 + tw + 12 * s
                    local badge_y0 = lane_mid_y - 11 * s
                    local badge_y1 = lane_mid_y + 11 * s

                    if is_editing then
                        reaper.ImGui_SetCursorScreenPos(ctx, badge_x0, badge_y0)
                        reaper.ImGui_SetNextItemWidth(ctx, math.max(65 * s, tw + 28 * s))
                        if state.editing_chord_just_opened then
                            reaper.ImGui_SetKeyboardFocusHere(ctx)
                            state.editing_chord_just_opened = false
                        end
                        local enter_pressed, new_txt = reaper.ImGui_InputText(ctx, "##inline_chd_" .. ci.id, state.editing_chord_str or txt_str, reaper.ImGui_InputTextFlags_EnterReturnsTrue() | reaper.ImGui_InputTextFlags_AutoSelectAll())
                        if new_txt ~= nil then
                            state.editing_chord_str = new_txt
                        end

                        if enter_pressed then
                            ScaleService.update_chord_text(state, ci.id, state.editing_chord_str)
                            state.editing_chord_item = nil
                            state.editing_chord_str = nil
                        elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                            state.editing_chord_item = nil
                            state.editing_chord_str = nil
                        elseif (reaper.APIExists("ImGui_IsItemDeactivated") and reaper.ImGui_IsItemDeactivated(ctx)) or (reaper.ImGui_IsMouseClicked(ctx, 0) and not in_body and not reaper.ImGui_IsItemActive(ctx)) then
                            ScaleService.update_chord_text(state, ci.id, state.editing_chord_str)
                            state.editing_chord_item = nil
                            state.editing_chord_str = nil
                        end
                    else
                        local badge_bg = is_selected and 0xFF9F1C33 or (is_hov and 0x2980B9EE or 0x242730EE)
                        local badge_border = is_selected and 0xFF9F1CFF or (is_hov and 0x5BC0DEFF or 0x5BC0DE88)
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, badge_x0, badge_y0, badge_x1, badge_y1, badge_bg, 3.0)
                        reaper.ImGui_DrawList_AddRect(draw_list, badge_x0, badge_y0, badge_x1, badge_y1, badge_border, 3.0, 0, 1.2 * s)

                        local txt_col = is_selected and 0xFF9F1CFF or (is_hov and 0xFFFFFFFF or 0x5BC0DEFF)
                        reaper.ImGui_DrawList_AddText(draw_list, badge_x0 + 6 * s, lane_mid_y - 7.5 * s, txt_col, txt_str)
                    end

                    -- 4. Dashed bar - - - -
                    local cur_lx = badge_x1 + 4 * s
                    local dash_len = 6.0 * s
                    local dash_gap = 5.0 * s
                    local line_c = is_selected and 0xFF9F1CFF or (is_hov and 0x5BC0DEFF or 0x5BC0DEAA)

                    while cur_lx + dash_len <= (x2 - 3 * s) do
                        reaper.ImGui_DrawList_AddLine(draw_list, cur_lx, lane_mid_y, cur_lx + dash_len, lane_mid_y, line_c, 1.8 * s)
                        cur_lx = cur_lx + dash_len + dash_gap
                    end
                    if cur_lx < (x2 - 3 * s) then
                        reaper.ImGui_DrawList_AddLine(draw_list, cur_lx, lane_mid_y, x2 - 3 * s, lane_mid_y, line_c, 1.8 * s)
                    end

                    -- 5. Dual handles (start & end)
                    if is_selected or is_hov then
                        local h_radius = 4.5 * s
                        local h1_c = (chord_handle_hovered_this_frame == "start" and is_hov) and 0xFF9F1CFF or 0x3498DBFF
                        reaper.ImGui_DrawList_AddCircleFilled(draw_list, h1_x, h1_y, h_radius, h1_c)
                        reaper.ImGui_DrawList_AddCircle(draw_list, h1_x, h1_y, h_radius + 1.0, 0xFFFFFFFF, 0, 1.0)

                        local h2_c = (chord_handle_hovered_this_frame == "end" and is_hov) and 0xFF9F1CFF or 0x2ECC71FF
                        reaper.ImGui_DrawList_AddCircleFilled(draw_list, h2_x, h2_y, h_radius, h2_c)
                        reaper.ImGui_DrawList_AddCircle(draw_list, h2_x, h2_y, h_radius + 1.0, 0xFFFFFFFF, 0, 1.0)
                    end
                end
            end

            -- Empty Lane Hover & Click
            local in_empty_lane = is_hovered and (mouse_x >= lane_x0 and mouse_x <= lane_x1 and mouse_y >= lane_y0 and mouse_y <= lane_y1) and not chord_hovered_this_frame
            if in_empty_lane and can_hover then
                local click_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, 4.0, measure_map)
                local m_snap = math.floor(click_qn / qn_per_measure) * qn_per_measure

                -- Right-click on empty lane
                if reaper.ImGui_IsMouseClicked(ctx, 1) then
                    state.context_chord_item = nil
                    state.context_chord_qn = m_snap
                    reaper.ImGui_OpenPopup(ctx, "chord_lane_context_popup")
                end

                -- Double-click creates a new chord item
                if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                    local new_ci = ScaleService.create_chord_item(state, m_snap, m_snap + qn_per_measure, "C")
                    state:clear_selection()
                    state.selected_chord_item = new_ci
                    state.editing_chord_item = new_ci
                    state.editing_chord_str = new_ci.text
                    state.editing_chord_just_opened = true
                    state.status_msg = string.format("New Chord Item created at Measure %d", math.floor(m_snap / qn_per_measure) + 1)
                end
            end
        end

        -- Mouse released drag completion (always runs, even if mouse is released outside lane culling)
        if reaper.ImGui_IsMouseReleased(ctx, 0) then
            if (state.is_dragging_chord or state.drag_chord_item) and state.drag_chord_item then
                local ci = state.drag_chord_item
                local orig_s = state.drag_chord_orig_start
                local orig_e = state.drag_chord_orig_end
                if orig_s and orig_e and (math.abs(orig_s - ci.start_qn) > 0.01 or math.abs(orig_e - ci.end_qn) > 0.01) then
                    local range_min = math.min(orig_s, orig_e, ci.start_qn, ci.end_qn)
                    local range_max = math.max(orig_s, orig_e, ci.start_qn, ci.end_qn)
                    ScaleService.revert_notes_in_range(state, range_min, range_max)
                    for _, other_ci in ipairs(state.chord_items or {}) do
                        if other_ci.id ~= ci.id and other_ci.end_qn > range_min and other_ci.start_qn < range_max then
                            ScaleService.apply_chord_item_to_target_tracks(state, other_ci)
                        end
                    end
                    ScaleService.save_chord_items(state)
                    ScaleService.apply_chord_item_to_target_tracks(state, ci)
                    if ScaleService.revert_orphaned_chord_notes then
                        ScaleService.revert_orphaned_chord_notes(state)
                    end
                    reaper.Undo_OnStateChange2(0, "Notator: Adjust Chord Item (" .. ci.text .. ")")
                    state.status_msg = string.format("Chord '%s' adjusted (measure %.2f - %.2f)", ci.text, (ci.start_qn / qn_per_measure) + 1, (ci.end_qn / qn_per_measure) + 1)
                end
            end
            state.is_dragging_chord = false
            state.drag_chord_item = nil
            state.drag_chord_handle = nil
            state.drag_chord_target_qn = nil
            state.drag_chord_delta_qn = nil
            state.drag_chord_orig_start = nil
            state.drag_chord_orig_end = nil
        end
    end

    if chord_handle_hovered_this_frame == "start" or chord_handle_hovered_this_frame == "end" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
    elseif chord_handle_hovered_this_frame == "body" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end

    state.hovered_chord_item = chord_hovered_this_frame
    state.hovered_chord_handle = chord_handle_hovered_this_frame
    if hov then
        hov.chord = chord_hovered_this_frame
        hov.chord_handle = chord_handle_hovered_this_frame
    end
end

return CanvasDecorations

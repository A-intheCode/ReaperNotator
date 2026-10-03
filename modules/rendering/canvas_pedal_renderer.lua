-- ==============================================================================
-- REAPER Native Notator - Module: CanvasPedalRenderer
-- Dedicated CC64 Holding / Sustain Pedal renderer for ScoreCanvas.
-- Renders pedal markings (Ped. ─── *, brackets, notches, retakes, pause points)
-- with authentic Bravura SMuFL glyphs, dual-handle resizing, and collision avoidance.
-- ==============================================================================

local Constants          = package.loaded["constants"] or require("constants")
local SMUFL              = Constants.SMUFL
local Engraver           = package.loaded["rendering.engraver"] or require("rendering.engraver")
local PedalService       = package.loaded["services.pedal_service"] or require("services.pedal_service")
local HairpinService     = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")

local CanvasPedalRenderer = {}

function CanvasPedalRenderer.render_track_pedals(ctx, draw_list, state, fonts, tdata, staff_bottom_y, s, margin_left, qn_per_measure, measure_map, is_hovered, mouse_x, mouse_y, hov)
    if state.show_pedal_layer == false then return hov end
    if not tdata or not tdata.guid then return hov end
    
    local track_pedals = PedalService.get_pedals_for_track(state, tdata.guid)
    if not track_pedals or #track_pedals == 0 then return hov end
    
    hov = hov or {}
    
    local FontManager = package.loaded["rendering.font_manager"] or require("rendering.font_manager")
    local font_music = (fonts and (fonts.font_music or fonts.music)) or (FontManager and FontManager.font_music)
    
    for _, pm in ipairs(track_pedals) do
        local is_selected = (state.selected_pedal and state.selected_pedal.id == pm.id) or (state.selected_pedals and state.selected_pedals[pm.id] ~= nil)
        local cur_s = pm.start_qn
        local cur_e = pm.end_qn
        
        -- Live preview during drag
        if state.is_dragging_pedal and state.drag_pedal and state.drag_pedal.id == pm.id then
            if state.drag_pedal_handle == "start" and state.drag_pedal_target_qn then
                cur_s = state.drag_pedal_target_qn
            elseif state.drag_pedal_handle == "end" and state.drag_pedal_target_qn then
                cur_e = state.drag_pedal_target_qn
            elseif state.drag_pedal_handle == "body" then
                local dur = pm.end_qn - pm.start_qn
                cur_s = (state.drag_pedal_orig_start or pm.start_qn) + (state.drag_pedal_delta_qn or 0)
                cur_e = cur_s + dur
            end
        end
        
        local raw_x1 = Engraver.qn_to_canvas_x(cur_s, margin_left, s, qn_per_measure, measure_map)
        local raw_x2 = Engraver.qn_to_canvas_x(cur_e, margin_left, s, qn_per_measure, measure_map)
        local x1 = raw_x1
        local x2 = math.max(x1 + 18 * s, raw_x2)
        
        -- Y-positioning: Below the bass staff / independent of dynamics
        local ped_offset = (state.pedal_offset_y or 75.0) * s
        local ped_y = staff_bottom_y + ped_offset
        
        -- Check collision with low notes
        local notes_to_check = tdata.visual_notes or tdata.notes or {}
        for _, vn in ipairs(notes_to_check) do
            if vn.start_qn < cur_e and vn.end_qn > cur_s then
                local note_bottom = (vn.vis_ny or (staff_bottom_y + 8.0 * s)) + 8.0 * s
                if vn.stem_down and vn.stem_end_y then
                    note_bottom = math.max(note_bottom, vn.stem_end_y + 3.0 * s)
                end
                if note_bottom >= ped_y - 12.0 * s then
                    ped_y = math.max(ped_y, note_bottom + 14.0 * s)
                end
            end
        end

        -- Check collision with hairpins
        local track_hairpins = tdata.hairpins
        if not track_hairpins and HairpinService and HairpinService.get_hairpins_for_track then
            track_hairpins = HairpinService.get_hairpins_for_track(state, tdata.guid)
        end
        local dyn_offset = (state.dynamics_offset_y or 45.0) * s
        local dyn_base_y = staff_bottom_y + dyn_offset
        if track_hairpins then
            for _, hp in ipairs(track_hairpins) do
                local hs = hp.start_qn or 0
                local he = hp.end_qn or (hs + 1.0)
                if hs < cur_e and he > cur_s then
                    local hp_bot = (hp.base_y or dyn_base_y) + 8.0 * s
                    if hp_bot >= ped_y - 12.0 * s then
                        ped_y = math.max(ped_y, hp_bot + (ped_offset * 0.6) + 4.0 * s)
                    end
                end
            end
        end

        -- Check collision with text dynamics
        local track_dtexts = tdata.dynamic_texts
        if not track_dtexts and DynamicTextService and DynamicTextService.get_dynamic_texts_for_track then
            track_dtexts = DynamicTextService.get_dynamic_texts_for_track(state, tdata.guid)
        end
        if track_dtexts then
            for _, dt in ipairs(track_dtexts) do
                local ds = dt.start_qn or 0
                local de = dt.end_qn or (ds + 1.0)
                if ds < cur_e and de > cur_s then
                    local dt_bot = (dt.base_y or dyn_base_y) + 8.0 * s
                    if dt_bot >= ped_y - 12.0 * s then
                        ped_y = math.max(ped_y, dt_bot + (ped_offset * 0.6) + 4.0 * s)
                    end
                end
            end
        end
        pm.base_y = ped_y
        
        -- Handles & Hit-Testing
        local h1_x, h1_y = x1, ped_y
        local h2_x, h2_y = x2, ped_y
        local dist_h1 = math.sqrt((mouse_x - h1_x)^2 + (mouse_y - h1_y)^2)
        local dist_h2 = math.sqrt((mouse_x - h2_x)^2 + (mouse_y - h2_y)^2)
        local in_body = (mouse_x >= x1 - 4 * s and mouse_x <= x2 + 4 * s and mouse_y >= ped_y - 12 * s and mouse_y <= ped_y + 12 * s)
        
        local hovered_pause_id = nil
        local is_blocked = false
        if hov then
            if hov.dyn or hov.dyn_hovered_this_frame or
               hov.hairpin or hov.hairpin_hovered_this_frame or
               hov.dynamic_text or hov.dynamic_text_hovered_this_frame or
               hov.text_item or hov.text_item_hovered_this_frame or
               hov.note or hov.note_hovered_this_frame or
               hov.item_edge or hov.blocked or
               (hov.pedal and hov.pedal.id ~= pm.id) then
                is_blocked = true
            end
        end
        
        local is_dragging_any = state.is_dragging or state.is_dragging_dynamic or state.is_dragging_hairpin or state.is_dragging_articulation or state.is_resizing_item or state.is_dragging_pedal
        local can_hover = is_hovered and not is_blocked and not is_dragging_any
        
        if can_hover and not hov.pedal then
            local handle_hit_r = 12.0 * s
            local pause_hit_r = 10.0 * s
            -- Check pause handles first
            for _, p in ipairs(pm.pauses or {}) do
                local px = Engraver.qn_to_canvas_x(p.qn, margin_left, s, qn_per_measure, measure_map)
                local dist_p = math.sqrt((mouse_x - px)^2 + (mouse_y - ped_y)^2)
                if dist_p <= pause_hit_r then
                    hovered_pause_id = p.id
                    hov.pedal = pm
                    hov.pedal_handle = "pause_" .. p.id
                    hov.pedal_pause = p
                    break
                end
            end
            
            if not hovered_pause_id then
                if dist_h1 <= handle_hit_r then
                    hov.pedal = pm
                    hov.pedal_handle = "start"
                elseif dist_h2 <= handle_hit_r then
                    hov.pedal = pm
                    hov.pedal_handle = "end"
                elseif in_body then
                    hov.pedal = pm
                    hov.pedal_handle = "body"
                end
            end
        end
        
        local is_hov = (hov.pedal and hov.pedal.id == pm.id)
        if is_hov then
            state.hovered_pedal = pm
            state.hovered_pedal_handle = hov.pedal_handle
            if hov.pedal_pause then
                hovered_pause_id = hov.pedal_pause.id
            end
            if hov.pedal_handle == "start" or hov.pedal_handle == "end" or (hov.pedal_handle and hov.pedal_handle:find("^pause_")) then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
            elseif hov.pedal_handle == "body" then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
            end
        end
        
        -- Context menu on right-click
        if is_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
            state.selected_pedal = pm
            state.context_pedal = pm
            state.context_pedal_click_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
            state.context_pedal_pause_id = hovered_pause_id
            state.selected_dynamic = nil
            state.selected_hairpin = nil
            state.selected_octave_line = nil
            state.selected_tempo_marker = nil
            state.selected_dynamic_text = nil
            reaper.ImGui_OpenPopup(ctx, "pedal_context_popup")
        end
        
        -- Background highlight on selection/hover
        if is_selected or is_hov then
            local bg_c = is_selected and 0x9B59B625 or 0x9B59B612
            local bdr_c = is_selected and 0x9B59B6BB or 0x8E44AD55
            reaper.ImGui_DrawList_AddRectFilled(draw_list, x1 - 4 * s, ped_y - 12 * s, x2 + 4 * s, ped_y + 12 * s, bg_c, 3.0)
            reaper.ImGui_DrawList_AddRect(draw_list, x1 - 4 * s, ped_y - 12 * s, x2 + 4 * s, ped_y + 12 * s, bdr_c, 3.0, 0, 1.0 * s)
        end
        
        local col_pedal = is_selected and 0xFF9F1CFF or (is_hov and 0x9B59B6FF or (state.invert_mode and 0xDDDDDDFF or 0x222222FF))
        local line_w = 1.6 * s
        local hook_h = 9.0 * s
        local ped_font_sz = math.floor(30 * s + 0.5)
        
        -- Draw start mark
        local line_start_x = x1
        if pm.style == "classic" or pm.style == "notch" or pm.style == "mixed" then
            -- SMuFL Ped. symbol
            if font_music and SMUFL and SMUFL.pedal_ped and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                local pos_y = ped_y - (ped_font_sz * 1.95)
                reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, ped_font_sz, x1 - 2 * s, pos_y, col_pedal, SMUFL.pedal_ped)
                local ped_adv = (1019 / 1000) * ped_font_sz
                line_start_x = x1 + ped_adv + 3 * s
            else
                reaper.ImGui_DrawList_AddText(draw_list, x1, ped_y - 10 * s, col_pedal, "Ped.")
                line_start_x = x1 + 24 * s
            end
        else -- bracket (| ── |)
            reaper.ImGui_DrawList_AddLine(draw_list, x1, ped_y - hook_h, x1, ped_y, col_pedal, line_w)
            line_start_x = x1
        end
        
        -- Line segments with pauses / breaks
        local cur_pauses = {}
        for _, p in ipairs(pm.pauses or {}) do
            local pqn = p.qn
            if state.is_dragging_pedal and state.drag_pedal and state.drag_pedal.id == pm.id and state.drag_pedal_handle == ("pause_" .. p.id) then
                pqn = state.drag_pedal_target_qn or p.qn
            end
            if pqn > cur_s and pqn < cur_e then
                table.insert(cur_pauses, {
                    id = p.id,
                    qn = pqn,
                    type = p.type or "asterisk",
                    dur = p.dur or 0.0
                })
            end
        end
        table.sort(cur_pauses, function(a, b) return a.qn < b.qn end)
        
        local seg_start_x = line_start_x
        for _, p in ipairs(cur_pauses) do
            local px = Engraver.qn_to_canvas_x(p.qn, margin_left, s, qn_per_measure, measure_map)
            
            if p.type == "notch" then
                -- Notch (inverted V /\)
                local notch_w = 6.0 * s
                local notch_h = 8.0 * s
                if px - notch_w > seg_start_x then
                    reaper.ImGui_DrawList_AddLine(draw_list, seg_start_x, ped_y, px - notch_w, ped_y, col_pedal, line_w)
                end
                reaper.ImGui_DrawList_AddLine(draw_list, px - notch_w, ped_y, px, ped_y - notch_h, col_pedal, line_w)
                reaper.ImGui_DrawList_AddLine(draw_list, px, ped_y - notch_h, px + notch_w, ped_y, col_pedal, line_w)
                seg_start_x = px + notch_w
            else
                -- Pause mark / asterisk (* or * Ped.)
                local gap_half = 9.0 * s
                if px - gap_half > seg_start_x then
                    reaper.ImGui_DrawList_AddLine(draw_list, seg_start_x, ped_y, px - gap_half, ped_y, col_pedal, line_w)
                end
                -- Hook before pause
                reaper.ImGui_DrawList_AddLine(draw_list, px - gap_half, ped_y, px - gap_half, ped_y - hook_h * 0.7, col_pedal, line_w)
                
                -- SMuFL asterisk (*)
                if font_music and SMUFL and SMUFL.pedal_up and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                    local pos_y = ped_y - (ped_font_sz * 1.95)
                    reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, ped_font_sz, px - 6 * s, pos_y, col_pedal, SMUFL.pedal_up)
                else
                    reaper.ImGui_DrawList_AddText(draw_list, px - 4 * s, ped_y - 8 * s, col_pedal, "*")
                end
                
                -- If retake, display Ped. after asterisk
                if p.type == "retake" then
                    local ped_pos_x = px + 10 * s
                    if font_music and SMUFL and SMUFL.pedal_ped and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                        local pos_y = ped_y - (ped_font_sz * 1.95)
                        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, ped_font_sz * 0.85, ped_pos_x, pos_y, col_pedal, SMUFL.pedal_ped)
                    else
                        reaper.ImGui_DrawList_AddText(draw_list, ped_pos_x, ped_y - 8 * s, col_pedal, "Ped.")
                    end
                    seg_start_x = ped_pos_x + 20 * s
                else
                    -- Hook after pause for continuation
                    reaper.ImGui_DrawList_AddLine(draw_list, px + gap_half, ped_y - hook_h * 0.7, px + gap_half, ped_y, col_pedal, line_w)
                    seg_start_x = px + gap_half
                end
            end
            
            -- Draw pause handle (amber / purple)
            if is_selected or is_hov then
                local is_p_hov = (hov.pedal_pause and hov.pedal_pause.id == p.id) or (hovered_pause_id == p.id)
                local ph_col = is_p_hov and 0xFF9F1CFF or 0xE67E22FF
                reaper.ImGui_DrawList_AddCircleFilled(draw_list, px, ped_y, 4.0 * s, ph_col)
                reaper.ImGui_DrawList_AddCircle(draw_list, px, ped_y, 4.5 * s, 0xFFFFFFFF, 0, 1.0)
            end
        end
        
        -- Final line segment up to end x2
        if x2 > seg_start_x then
            reaper.ImGui_DrawList_AddLine(draw_list, seg_start_x, ped_y, x2, ped_y, col_pedal, line_w)
        end
        
        -- End symbol
        if pm.style == "classic" then
            -- Asterisk (*) at end
            if font_music and SMUFL and SMUFL.pedal_up and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                local pos_y = ped_y - (ped_font_sz * 1.95)
                reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, ped_font_sz, x2 - 2 * s, pos_y, col_pedal, SMUFL.pedal_up)
            else
                reaper.ImGui_DrawList_AddText(draw_list, x2, ped_y - 8 * s, col_pedal, "*")
            end
        else
            -- Upward hook (|) at end
            reaper.ImGui_DrawList_AddLine(draw_list, x2, ped_y, x2, ped_y - hook_h, col_pedal, line_w)
        end
        
        -- Dual handles (start & end) on selection, hover or active drag
        local is_dragging_this = state.is_dragging_pedal and state.drag_pedal and state.drag_pedal.id == pm.id
        if is_selected or is_hov or is_dragging_this then
            local h_rad = 4.5 * s
            local is_h1_act = (hov.pedal_handle == "start" and is_hov) or (is_dragging_this and state.drag_pedal_handle == "start")
            local is_h2_act = (hov.pedal_handle == "end" and is_hov) or (is_dragging_this and state.drag_pedal_handle == "end")
            local h1_c = is_h1_act and 0xFF9F1CFF or 0x3498DBFF
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, h1_x, h1_y, h_rad, h1_c)
            reaper.ImGui_DrawList_AddCircle(draw_list, h1_x, h1_y, h_rad + 1.0, 0xFFFFFFFF, 0, 1.0)
            
            local h2_c = is_h2_act and 0xFF9F1CFF or 0x2ECC71FF
            reaper.ImGui_DrawList_AddCircleFilled(draw_list, h2_x, h2_y, h_rad, h2_c)
            reaper.ImGui_DrawList_AddCircle(draw_list, h2_x, h2_y, h_rad + 1.0, 0xFFFFFFFF, 0, 1.0)
        end
    end
    
    return hov
end

return CanvasPedalRenderer

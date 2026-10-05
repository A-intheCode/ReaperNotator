-- ==============================================================================
-- REAPER Native Notator - Module: DynamicsDrawer
-- Dynamics Drawer (10 Buttons, Re-Blend, Velocity Emphasize & CC)
-- ==============================================================================

local Constants = require("constants")

local DynamicsDrawer = {}

function DynamicsDrawer.render(ctx, state, dynamics_engine, midi_service, active_tracks_data, w, h, child_border, sidebar_flags)
    if not state.show_dynamics then return end
    
    if not reaper.ImGui_BeginChild(ctx, "DynamicsDrawer", w, h, child_border, sidebar_flags) then
        return
    end
    
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "DYNAMICS")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, 0x888888FF, "v11.13")
    reaper.ImGui_SameLine(ctx, w - 30)
    if reaper.ImGui_SmallButton(ctx, "✕") then
        state.show_dynamics = false
    end
    reaper.ImGui_Separator(ctx)
    
    -- Resolve current track & current MIDI item
    local tgt_item, tgt_take, tgt_track, tgt_name = midi_service.get_target_item_and_take(state, active_tracks_data)
    local cur_track = tgt_track or dynamics_engine.get_target_track(state, active_tracks_data)
    local trk_name = "No active track"
    if cur_track and reaper.ValidatePtr(cur_track, "MediaTrack*") then
        local _, tn = reaper.GetTrackName(cur_track)
        trk_name = tn or "Track"
    end
    
    -- Collect all MIDI items on this track
    local track_items = {}
    if cur_track and reaper.ValidatePtr(cur_track, "MediaTrack*") then
        local it_cnt = reaper.CountTrackMediaItems(cur_track)
        for i = 0, it_cnt - 1 do
            local it = reaper.GetTrackMediaItem(cur_track, i)
            local tk = it and reaper.GetActiveTake(it)
            if tk and reaper.TakeIsMIDI(tk) then
                local _, iname = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
                local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                local sqn = reaper.TimeMap2_timeToQN(0, ipos)
                local eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                local sm = math.floor(sqn / 4) + 1
                local em = math.floor(eqn / 4) + 1
                local lbl = string.format("%s (m.%d-%d)", (iname and iname ~= "") and iname or string.format("Item %d", i+1), sm, em)
                table.insert(track_items, { item = it, take = tk, name = lbl, raw_name = iname })
            end
        end
    end
    
    if not tgt_item and #track_items > 0 then
        tgt_item = track_items[1].item
        tgt_take = track_items[1].take
        tgt_name = track_items[1].name
    end
    
    -- If item has changed: Load modulators for this item
    if tgt_item and reaper.ValidatePtr(tgt_item, "MediaItem*") then
        if state.last_dyn_item ~= tgt_item then
            state.last_dyn_item = tgt_item
            dynamics_engine.load_item_modulators(tgt_item, state)
        end
    elseif cur_track and reaper.ValidatePtr(cur_track, "MediaTrack*") then
        if state.last_dyn_track ~= cur_track then
            state.last_dyn_track = cur_track
            dynamics_engine.load_track_modulators(cur_track, state)
        end
    end
    
    if active_tracks_data and #active_tracks_data > 1 then
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        if reaper.ImGui_BeginCombo(ctx, "##DynTrackSelect", "Track: " .. trk_name) then
            for _, tdata in ipairs(active_tracks_data) do
                local is_sel = (tdata.track == cur_track)
                if reaper.ImGui_Selectable(ctx, tdata.name or "Track", is_sel) then
                    state.focused_track = tdata.track
                    state.last_dyn_track = tdata.track
                    cur_track = tdata.track
                    trk_name = tdata.name or "Track"
                    state.last_dyn_item = nil
                    tgt_item, tgt_take, tgt_track, tgt_name = midi_service.get_target_item_and_take(state, active_tracks_data)
                    if tgt_item then
                        dynamics_engine.load_item_modulators(tgt_item, state)
                    else
                        dynamics_engine.load_track_modulators(tdata.track, state)
                    end
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
    else
        reaper.ImGui_TextColored(ctx, 0x3498DBFF, "Track: " .. trk_name)
    end
    
    -- Item selector if multiple items exist on the track
    if #track_items > 1 then
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        local cur_it_lbl = "Item: " .. (tgt_name or "Select Item")
        if reaper.ImGui_BeginCombo(ctx, "##DynItemSelect", cur_it_lbl) then
            for _, idata in ipairs(track_items) do
                local is_sel = (idata.item == tgt_item)
                if reaper.ImGui_Selectable(ctx, idata.name, is_sel) then
                    state.selected_item = idata.item
                    state.selected_take = idata.take
                    tgt_item = idata.item
                    tgt_take = idata.take
                    tgt_name = idata.name
                    state.last_dyn_item = idata.item
                    dynamics_engine.load_item_modulators(idata.item, state)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
    elseif #track_items == 1 then
        reaper.ImGui_TextColored(ctx, 0x1ABC9CFF, "Item: " .. (tgt_name or track_items[1].name))
    end
    
    -- Target status indicator: notes or cursor
    local sel_n_cnt = state:count_selected_notes()
    if sel_n_cnt > 0 then
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("Target: %d selected note(s)", sel_n_cnt))
    else
        reaper.ImGui_TextColored(ctx, 0x888888FF, "Target: Edit-Cursor position")
    end
    reaper.ImGui_Spacing(ctx)
    
    -- 10 DYNAMICS BUTTONS (2 columns of 5 buttons with original colors)
    local btn_w = (w - 24) / 2
    for i = 1, 5 do
        local b_left = Constants.ALEX_DYN_BUTTONS[i]
        local b_right = Constants.ALEX_DYN_BUTTONS[i + 5]
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), b_left.col)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), b_left.col | 0x22222200)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), b_left.text_col)
        if reaper.ImGui_Button(ctx, string.format("%s##dyn", b_left.label), btn_w, 24) then
            dynamics_engine.insert_dynamic_anchor(b_left, state, midi_service, active_tracks_data)
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_SameLine(ctx)
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), b_right.col)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), b_right.col | 0x22222200)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), b_right.text_col)
        if reaper.ImGui_Button(ctx, string.format("%s##dyn", b_right.label), btn_w, 24) then
            dynamics_engine.insert_dynamic_anchor(b_right, state, midi_service, active_tracks_data)
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
    end
    
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    
    -- MAIN ACTIONS: SMART RE-BLEND
    local tgt_item, tgt_take, tgt_track, tgt_name = midi_service.get_target_item_and_take(state, active_tracks_data)
    if tgt_take and reaper.ValidatePtr(tgt_take, "MediaItem_Take*") then
        local _, trk_name = reaper.GetTrackName(tgt_track)
        local btn_label = string.format("⚡ RE-BLEND: %s [%s]", trk_name or "Track", tgt_name or "Item")
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
        if reaper.ImGui_Button(ctx, btn_label, -1, 28) then
            dynamics_engine.smart_reblend_all(state, midi_service, active_tracks_data)
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
    else
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x334433FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x889988FF)
        if reaper.ImGui_Button(ctx, "⚡ RE-BLEND (No MIDI item selected)", -1, 28) then
            state.status_msg = "Re-Blend: Please select a MIDI item first via the top track badge!"
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
    
    -- EMPHASIZE VELOCITY BUTTON
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xD35400FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE67E22FF)
    if reaper.ImGui_Button(ctx, "📊 EMPHASIZE VELOCITY", -1, 26) then
        dynamics_engine.emphasize_velocity(state, midi_service, active_tracks_data)
    end
    reaper.ImGui_PopStyleColor(ctx, 2)
    
    -- Delete dynamic button (if a dynamic is selected)
    if state.selected_dynamic then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xC0392BFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE74C3CFF)
        if reaper.ImGui_Button(ctx, string.format("🗑 Delete Dynamic '%s'", state.selected_dynamic.label), -1, 25) then
            dynamics_engine.delete_selected_dynamic(state, midi_service, active_tracks_data)
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
    
    -- CLEAN NOTATION EVENTS
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x552222FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x773333FF)
    if reaper.ImGui_Button(ctx, "🗑 Clean Notation Events", -1, 24) then
        dynamics_engine.clean_notation_events(state, midi_service, active_tracks_data)
    end
    reaper.ImGui_PopStyleColor(ctx, 2)
    
    -- CC Assignment & Grid
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "CC ASSIGNMENT & GRID")
    reaper.ImGui_Separator(ctx)
    
    local mod_changed = false
    reaper.ImGui_SetNextItemWidth(ctx, 60)
    local chk_a, val_a = reaper.ImGui_DragInt(ctx, "CC A", state.dyn_cc_a, 0.2, 1, 127)
    if chk_a then state.dyn_cc_a = val_a; mod_changed = true end
    reaper.ImGui_SameLine(ctx, 0, 16)
    reaper.ImGui_SetNextItemWidth(ctx, 60)
    local chk_b, val_b = reaper.ImGui_DragInt(ctx, "CC B", state.dyn_cc_b, 0.2, 1, 127)
    if chk_b then state.dyn_cc_b = val_b; mod_changed = true end
    
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local cur_grid_lbl = Constants.DYN_GRID_OPTIONS[state.dyn_grid_idx] and Constants.DYN_GRID_OPTIONS[state.dyn_grid_idx].label or "1/16"
    if reaper.ImGui_BeginCombo(ctx, "##DynGridSel", "Grid: " .. cur_grid_lbl) then
        for idx, opt in ipairs(Constants.DYN_GRID_OPTIONS) do
            if reaper.ImGui_Selectable(ctx, opt.label, idx == state.dyn_grid_idx) then
                state.dyn_grid_idx = idx
                mod_changed = true
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end
    
    -- Marker-to-Marker Blending switch & Bypass Dynamic CC Shaping (per MIDI item)
    reaper.ImGui_Spacing(ctx)
    local cur_item_m2m = tgt_item and dynamics_engine.get_item_marker_blending(tgt_item, state) or state.dyn_marker_blending
    local chk_m2m, m2m_val = reaper.ImGui_Checkbox(ctx, "Marker-to-Marker Blending##m2m", cur_item_m2m)
    if chk_m2m then
        state.dyn_marker_blending = m2m_val
        if tgt_item and reaper.ValidatePtr(tgt_item, "MediaItem*") then
            dynamics_engine.set_item_marker_blending(tgt_item, m2m_val, state)
        elseif cur_track and reaper.ValidatePtr(cur_track, "MediaTrack*") then
            dynamics_engine.set_track_marker_blending(cur_track, m2m_val, state)
        end
        mod_changed = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        local it_info = tgt_name and (" (Applies to: " .. tgt_name .. ")") or ""
        reaper.ImGui_SetTooltip(ctx, "Active: Continuous transition between dynamic markers on this item (e.g. mp -> ff).\nOff: Markers hold their level statically; only hairpins (< and >) generate CC ramps." .. it_info)
    end
    
    -- Bypass Dynamic CC Shaping (disables CC curve calculation, protects hand-drawn CCs)
    local cur_item_byp = tgt_item and dynamics_engine.get_item_bypass_cc(tgt_item, state) or (state.dyn_bypass_cc == true)
    local chk_byp, byp_val = reaper.ImGui_Checkbox(ctx, "Bypass Dynamic CC Shaping##bypass_cc", cur_item_byp)
    if chk_byp then
        state.dyn_bypass_cc = byp_val
        if tgt_item and reaper.ValidatePtr(tgt_item, "MediaItem*") then
            dynamics_engine.set_item_bypass_cc(tgt_item, byp_val, state)
        elseif cur_track and reaper.ValidatePtr(cur_track, "MediaTrack*") then
            dynamics_engine.save_track_modulators(cur_track, state)
        end
        mod_changed = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Active: Dynamic markers & hairpins are visual notation only.\nNo CC curves are written, preserving hand-drawn CC automation in REAPER's MIDI editor.\nOff: Automatic CC curve shaping is applied.")
    end
    
    if tgt_name then
        reaper.ImGui_TextColored(ctx, 0x88AAAAFF, string.format("↳ Applies to: %s", tgt_name))
    elseif cur_track and trk_name ~= "No active track" then
        reaper.ImGui_TextColored(ctx, 0x88AAAAFF, string.format("↳ Applies to: %s", trk_name))
    end
    
    -- Smart Modulators
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "SMART MODULATORS")
    reaper.ImGui_Separator(ctx)
    
    local chk_phr, phr_val = reaper.ImGui_Checkbox(ctx, "Phrasing (Breathing)", state.dyn_phrasing_active)
    if chk_phr then state.dyn_phrasing_active = phr_val; mod_changed = true end
    
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local chk_pi, p_val = reaper.ImGui_SliderDouble(ctx, "##PhrInt", state.dyn_phrasing_intensity, 0.0, 1.0, "Phr-Int: %.2f")
    if chk_pi then state.dyn_phrasing_intensity = p_val; mod_changed = true end
    
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local chk_hi, h_val = reaper.ImGui_SliderDouble(ctx, "##HumInt", state.dyn_humanize_intensity, 0.0, 1.0, "Hum-Int: %.2f")
    if chk_hi then state.dyn_humanize_intensity = h_val; mod_changed = true end
    
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local chk_st, s_val = reaper.ImGui_SliderDouble(ctx, "##Stress", state.dyn_stress_factor, 0.0, 1.0, "Stress: %.2f")
    if chk_st then state.dyn_stress_factor = s_val; mod_changed = true end
    
    -- Bow Swell slider (directly below stress)
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local chk_bw, b_val = reaper.ImGui_SliderDouble(ctx, "##BowSwell", state.dyn_bow_intensity or 0.0, 0.0, 1.0, "Bow Swell: %.2f")
    if chk_bw then state.dyn_bow_intensity = b_val; mod_changed = true end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Simulates violin/string bow stroke dynamics.\nPressure increases towards the peak point and tapers at note end.\nOnly affects notes >= 1/4 note (shorter notes are bypassed).\n0.00 = Off, 1.00 = 100% Deformation.")
    end
    
    -- Bow Position slider (shifts swell peak: 0.0 = Start, 0.5 = Center/Default, 1.0 = End)
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local cur_bp = state.dyn_bow_pos
    if cur_bp == nil then cur_bp = 0.5 end
    local chk_bp, bp_val = reaper.ImGui_SliderDouble(ctx, "##BowPos", cur_bp, 0.0, 1.0, "Bow Position: %.2f")
    if chk_bp then state.dyn_bow_pos = bp_val; mod_changed = true end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Shifts the peak position of the Bow Swelling deformation:\n0.00 = Swell peak at attack (start of note)\n0.50 = Swell peak in the center (default)\n1.00 = Swell peak at the end of the note\nSaved per MIDI Item!")
    end
    
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local chk_vs, v_val = reaper.ImGui_SliderDouble(ctx, "##VelSens", state.dyn_vel_sensitivity, 0.0, 1.0, "Vel-Sens: %.2f")
    if chk_vs then state.dyn_vel_sensitivity = v_val; mod_changed = true end
    
    if mod_changed then
        if tgt_item and reaper.ValidatePtr(tgt_item, "MediaItem*") then
            dynamics_engine.save_item_modulators(tgt_item, state)
        elseif cur_track and reaper.ValidatePtr(cur_track, "MediaTrack*") then
            dynamics_engine.save_track_modulators(cur_track, state)
        end
        dynamics_engine.smart_reblend_all(state, midi_service, active_tracks_data)
    end
    
    -- Hairpins / Dynamic Ramps (Crescendo & Decrescendo)
    local HairpinService = require("services.hairpin_service")
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "HAIRPINS & RAMPS")
    reaper.ImGui_Separator(ctx)
    
    local hp_btn_w = (w - 24) / 2
    
    local function get_hairpin_context_bounds()
        local s_qn, e_qn = nil, nil
        local track_guid = nil
        local target_staff = nil
        
        local targets = {}
        for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
        if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
        
        if #targets >= 1 then
            table.sort(targets, function(a, b) return a.start_qn < b.start_qn end)
            s_qn = targets[1].start_qn
            if #targets == 1 then
                local n_dur = targets[1].dur_qn or (targets[1].end_qn - targets[1].start_qn)
                e_qn = targets[1].start_qn + math.max(0.5, math.min(2.0, n_dur))
            else
                e_qn = targets[#targets].end_qn
            end

            -- Staff placement defined by selected note
            local avg_p = 0
            for _, tn in ipairs(targets) do avg_p = avg_p + (tn.pitch or 60) end
            avg_p = avg_p / #targets
            target_staff = (avg_p >= 60) and "treble" or "bass"

            if targets[1].track then
                local _, guid = reaper.GetSetMediaTrackInfo_String(targets[1].track, "GUID", "", false)
                track_guid = guid
            end
        end
        
        if not track_guid and state.focused_track and reaper.ValidatePtr(state.focused_track, "MediaTrack*") then
            local _, guid = reaper.GetSetMediaTrackInfo_String(state.focused_track, "GUID", "", false)
            track_guid = guid
        end
        if not track_guid and active_tracks_data and #active_tracks_data > 0 then
            track_guid = active_tracks_data[1].guid
        end
        
        if not s_qn then
            local cur_time = reaper.GetCursorPosition()
            s_qn = reaper.TimeMap2_timeToQN(0, cur_time)
            local def_len = state.active_dur and math.max(0.5, math.min(state.active_dur, 2.0)) or 1.0
            e_qn = s_qn + def_len
        end
        
        if e_qn <= s_qn then e_qn = s_qn + 1.0 end
        return track_guid, s_qn, e_qn, target_staff
    end
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x1E3A5FFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2E5B88FF)
    if reaper.ImGui_Button(ctx, "< Crescendo##btn", hp_btn_w, 26) then
        local t_guid, s_qn, e_qn, t_staff = get_hairpin_context_bounds()
        if t_guid then
            HairpinService.create_hairpin(state, t_guid, "crescendo", s_qn, e_qn, nil, nil, midi_service, active_tracks_data, t_staff)
        else
            state.status_msg = "Hairpin: Please select a track first!"
        end
    end
    reaper.ImGui_PopStyleColor(ctx, 2)
    
    reaper.ImGui_SameLine(ctx)
    
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3D1E5FFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x5D2E88FF)
    if reaper.ImGui_Button(ctx, "> Decrescendo##btn", hp_btn_w, 26) then
        local t_guid, s_qn, e_qn, t_staff = get_hairpin_context_bounds()
        if t_guid then
            HairpinService.create_hairpin(state, t_guid, "decrescendo", s_qn, e_qn, nil, nil, midi_service, active_tracks_data, t_staff)
        else
            state.status_msg = "Hairpin: Please select a track first!"
        end
    end
    reaper.ImGui_PopStyleColor(ctx, 2)
    
    -- TEXT DYNAMICS (Cresc. & Dim. Text Tags with Scalable Duration)
    local DynamicTextService = require("services.dynamic_text_service")
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "TEXT DYNAMICS (CRESC. & DIM.)")
    reaper.ImGui_Separator(ctx)

    local txt_btn_w = (w - 24) / 2

    local text_templates = {
        { label = "Standard (cresc. / dim.)",          cresc = "cresc.",            dim = "dim." },
        { label = "Full text (crescendo / diminuendo)",cresc = "crescendo",         dim = "diminuendo" },
        { label = "Poco a poco (poco a poco...)",      cresc = "poco a poco cresc.",dim = "poco a poco dim." },
        { label = "Sempre (sempre cresc. / dim.)",     cresc = "sempre cresc.",     dim = "sempre dim." },
        { label = "Decrescendo (decresc.)",            cresc = "cresc.",            dim = "decresc." },
    }
    local cur_tmpl_idx = math.max(1, math.min(#text_templates, state.dyn_text_template_idx or 1))
    local cur_tmpl = text_templates[cur_tmpl_idx]

    -- 1. Quick Insert Buttons
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x165B4CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x1E826DFF)
    if reaper.ImGui_Button(ctx, "↗ cresc.##dt_cresc", txt_btn_w, 26) then
        local t_guid, s_qn, e_qn, t_staff = get_hairpin_context_bounds()
        if t_guid then
            DynamicTextService.create_dynamic_text(state, t_guid, "crescendo", "cresc.", s_qn, e_qn, state.dyn_text_line_pattern or "none", state.dyn_text_curve_pattern or "linear", nil, nil, midi_service, active_tracks_data, t_staff)
        else
            state.status_msg = "Text Dynamics: Please select a track first!"
        end
    end
    reaper.ImGui_PopStyleColor(ctx, 2)

    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x5B2C16FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x82401EFF)
    if reaper.ImGui_Button(ctx, "↘ dim.##dt_dim", txt_btn_w, 26) then
        local t_guid, s_qn, e_qn, t_staff = get_hairpin_context_bounds()
        if t_guid then
            DynamicTextService.create_dynamic_text(state, t_guid, "diminuendo", "dim.", s_qn, e_qn, state.dyn_text_line_pattern or "none", state.dyn_text_curve_pattern or "linear", nil, nil, midi_service, active_tracks_data, t_staff)
        else
            state.status_msg = "Text Dynamics: Please select a track first!"
        end
    end
    reaper.ImGui_PopStyleColor(ctx, 2)

    local cur_doy = state.dynamics_offset_y or 79.0
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local doy_changed, new_doy = reaper.ImGui_SliderDouble(ctx, "##dyn_hairpin_offset_slider", cur_doy, 20.0, 138.0, "Dynamics & Hairpins: %.0f px")
    if doy_changed then
        state.dynamics_offset_y = new_doy
        state.hairpins_offset_y = new_doy
        require('state').save_settings(state)
    end

    -- 2. Score Context Menu Hint
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "💡 Pattern Options:")
    reaper.ImGui_TextColored(ctx, 0xCCCCCCFF, "Right-click on 'cresc.' or 'dim.'")
    reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "in score opens all styles,")
    reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "line & CC curve patterns!")

    -- 3. Live Editor for selected Text Dynamic Marker
    if state.selected_dynamic_text then
        local sel_dt = state.selected_dynamic_text
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextColored(ctx, 0xFFD700FF, string.format("Selected: '%s' (%.1f QN)", sel_dt.text, sel_dt.end_qn - sel_dt.start_qn))
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xC0392BFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE74C3CFF)
        if reaper.ImGui_Button(ctx, string.format("🗑 Delete Text Dynamic '%s'##btn", sel_dt.text), -1, 24) then
            DynamicTextService.delete_dynamic_text(state, sel_dt.id, midi_service, active_tracks_data)
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
    
    -- ======================================================================
    -- 4. HOLDING / SUSTAIN PEDAL (CC64)
    -- ======================================================================
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextColored(ctx, 0x9B59B6FF, "HOLDING / SUSTAIN (CC64)")
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_TextColored(ctx, 0x888888FF, "Pedal")
    reaper.ImGui_Spacing(ctx)

    local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")

    -- 1. Quick Insert Button for Pedal
    local ped_btn_w = (w - 24) / 2
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x512E5FFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x7D3C98FF)
    if reaper.ImGui_Button(ctx, "Ped. ──── *##ins_ped", ped_btn_w, 26) then
        local t_guid, s_qn, e_qn, t_staff = get_hairpin_context_bounds()
        if t_guid then
            if e_qn <= s_qn + 1.0 and state:count_selected_notes() == 0 then
                e_qn = s_qn + 4.0 -- 1 full measure default at cursor
            end
            PedalService.create_pedal(state, t_guid, s_qn, e_qn, state.pedal_default_style or "classic", midi_service, active_tracks_data, t_staff)
        else
            state.status_msg = "Pedal: Please select a track first!"
        end
    end
    reaper.ImGui_PopStyleColor(ctx, 2)

    reaper.ImGui_SameLine(ctx)

    -- Button for Sustain Break / Retake
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x4A235AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x6C3483FF)
    if reaper.ImGui_Button(ctx, "+ ✽ Break##ins_pause", ped_btn_w, 26) then
        local target_pedal = state.selected_pedal
        local cur_pos = reaper.GetCursorPosition()
        local cur_qn = reaper.TimeMap2_timeToQN(0, cur_pos)
        
        -- If no pedal selected, search for pedal at cursor
        if not target_pedal and state.pedal_marks then
            for _, pm in ipairs(state.pedal_marks) do
                if cur_qn > pm.start_qn and cur_qn < pm.end_qn then
                    target_pedal = pm
                    break
                end
            end
        end

        if target_pedal then
            local p_qn = (cur_qn > target_pedal.start_qn and cur_qn < target_pedal.end_qn) and cur_qn or (target_pedal.start_qn + (target_pedal.end_qn - target_pedal.start_qn) * 0.5)
            PedalService.add_pause_point(state, target_pedal, p_qn, "asterisk", midi_service, active_tracks_data)
            state.selected_pedal = target_pedal
        else
            state.status_msg = "Sustain Break: Please select a pedal first or place cursor inside it!"
        end
    end
    reaper.ImGui_PopStyleColor(ctx, 2)

    -- Style selection
    local cur_style = state.pedal_default_style or "classic"
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0xBBBBBBFF, "Style:")
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "Ped.*##st_cls", cur_style == "classic") then
        state.pedal_default_style = "classic"
        if state.selected_pedal then
            state.selected_pedal.style = "classic"
            PedalService.save_pedals(state)
        end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "|─|##st_brk", cur_style == "bracket") then
        state.pedal_default_style = "bracket"
        if state.selected_pedal then
            state.selected_pedal.style = "bracket"
            PedalService.save_pedals(state)
        end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_RadioButton(ctx, "/\\##st_ntc", cur_style == "notch") then
        state.pedal_default_style = "notch"
        if state.selected_pedal then
            state.selected_pedal.style = "notch"
            PedalService.save_pedals(state)
        end
    end

    -- Vertical offset relative to staff
    local cur_poy = state.pedal_offset_y or 75.0
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_SetNextItemWidth(ctx, -1)
    local poy_changed, new_poy = reaper.ImGui_SliderDouble(ctx, "##ped_offset_slider", cur_poy, 10.0, 140.0, "Pedal Offset: %.0f px")
    if poy_changed then
        state.pedal_offset_y = new_poy
        require('state').save_settings(state)
    end

    -- Hint for score context menu
    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "💡 Right-click on pedal line")
    reaper.ImGui_TextColored(ctx, 0xCCCCCCFF, "in score opens break options,")
    reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "asterisk/notch patterns & CC64!")

    -- Live editor for selected pedal
    if state.selected_pedal then
        local sel_pm = state.selected_pedal
        local num_pauses = #(sel_pm.pauses or {})
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextColored(ctx, 0xFFD700FF, string.format("Pedal: %.1f QN (%d breaks)", sel_pm.end_qn - sel_pm.start_qn, num_pauses))
        
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xC0392BFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE74C3CFF)
        if reaper.ImGui_Button(ctx, "🗑 Delete Pedal Marking##btn", -1, 24) then
            PedalService.delete_pedal(state, sel_pm.id, midi_service, active_tracks_data)
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
    
    reaper.ImGui_EndChild(ctx)
end

return DynamicsDrawer

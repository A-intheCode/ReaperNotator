-- ==============================================================================
-- REAPER Native Notator - Module: SettingsModal
-- Settings window: Customizable keyboard shortcuts with capture function
-- ==============================================================================

local SettingsModal = {}

local Constants         = require("constants")
local PathService       = require("services.path_service")
local ReaticulateParser = require("services.reaticulate_parser")

function SettingsModal.apply_theme(state)
    for k, default_v in pairs(Constants.DEFAULT_COLORS) do
        local final_col = default_v
        
        if state.invert_mode then
            final_col = ((~final_col) & 0xFFFFFF00) | (final_col & 0x000000FF)
            -- Handcrafted contrast tweaks for invert mode (Dark Mode)
            if k == "paper_bg" then final_col = 0x1E1E1EFF end
            if k == "staff_line" then final_col = 0xAAAAAAFF end
            if k == "barline" then final_col = 0xFFFFFFFF end
            if k == "beatline" then final_col = 0x2D3035FF end
            if k == "notehead_black" or k == "beam_color" or k == "text_dark" or k == "art_text"
               or k == "clef_col" or k == "timesig_col" or k == "rest_col" or k == "tie_col"
               or k == "lyrics_text" or k == "fermata_col" or k == "bar_num" then
                final_col = 0xEEEEEEFF
            end
            if k == "rehearsal_box_bg" then final_col = 0x2A2D32FF end
            if k == "rehearsal_border" then final_col = 0xEEEEEEFF end
            if k == "rehearsal_text"   then final_col = 0xFFFFFFFF end
            if k == "text_muted"       then final_col = 0x999999FF end
        end
        
        -- Migrate legacy cyan bar_num default (0x5BC0DEFF) to new notehead-matching default
        if state.custom_colors and state.custom_colors.bar_num == 0x5BC0DEFF then
            state.custom_colors.bar_num = nil
        end
        
        if state.custom_colors and state.custom_colors[k] then
            final_col = state.custom_colors[k]
        end
        
        Constants.COLORS[k] = final_col
    end
end


function SettingsModal.render(ctx, state, shortcut_manager)
    if not state.show_settings then return end
    
    reaper.ImGui_SetNextWindowSize(ctx, 680, 560, reaper.ImGui_Cond_FirstUseEver())
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "⚙ Settings & Keyboard Shortcuts###SettingsWindow", true)
    
    if not s_open then
        state.show_settings = false
        state.capturing_action = nil
    end

    if s_vis then
        -- Determine modifier key state for key capture
        local is_ctrl = false
        if reaper.APIExists("ImGui_Mod_Ctrl") and reaper.APIExists("ImGui_GetKeyMods") then
            is_ctrl = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Ctrl()) ~= 0
        end
        if not is_ctrl and reaper.APIExists("ImGui_Key_LeftCtrl") and reaper.APIExists("ImGui_Key_RightCtrl") then
            is_ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl())
        end
        
        local is_shift = false
        if reaper.APIExists("ImGui_Mod_Shift") and reaper.APIExists("ImGui_GetKeyMods") then
            is_shift = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Shift()) ~= 0
        end
        if not is_shift and reaper.APIExists("ImGui_Key_LeftShift") and reaper.APIExists("ImGui_Key_RightShift") then
            is_shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
        end
        
        local is_alt = false
        if reaper.APIExists("ImGui_Mod_Alt") and reaper.APIExists("ImGui_GetKeyMods") then
            is_alt = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Alt()) ~= 0
        end
        if not is_alt and reaper.APIExists("ImGui_Key_LeftAlt") and reaper.APIExists("ImGui_Key_RightAlt") then
            is_alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftAlt()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightAlt())
        end

        -- Key capture listener
        if state.capturing_action then
            local current_target = shortcut_manager.shortcuts[state.capturing_action]
            local action_title = current_target and current_target.name or state.capturing_action
            
            -- ESC to cancel
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                state.capturing_action = nil
                state.status_msg = "Shortcut assignment cancelled"
            else
                -- Scan for pressed key
                for _, key_name in ipairs(shortcut_manager.SCAN_KEYS) do
                    local k_code = shortcut_manager.get_key_enum(key_name)
                    if k_code and reaper.ImGui_IsKeyPressed(ctx, k_code) then
                        shortcut_manager.set_shortcut(state.capturing_action, {
                            key   = key_name,
                            ctrl  = is_ctrl,
                            shift = is_shift,
                            alt   = is_alt
                        })
                        shortcut_manager.save()
                        state.status_msg = string.format("Shortcut assigned for '%s': %s", action_title, shortcut_manager.get_display_string(shortcut_manager.shortcuts[state.capturing_action]))
                        state.capturing_action = nil
                        break
                    end
                end
            end
        end

        -- Navigation Key Capture Listener
        if state.capturing_nav_action then
            if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                state.capturing_nav_action = nil
                state.status_msg = "Navigation key assignment cancelled"
            elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete()) then
                state[state.capturing_nav_action] = "none"
                require('state').save_settings(state)
                state.status_msg = "Navigation key cleared to None"
                state.capturing_nav_action = nil
            else
                local pressed_pure_mod = nil
                if reaper.APIExists("ImGui_Key_LeftShift") and (reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightShift())) then
                    pressed_pure_mod = is_ctrl and "shift_ctrl" or (is_alt and "shift_alt" or "shift")
                elseif reaper.APIExists("ImGui_Key_LeftCtrl") and (reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightCtrl())) then
                    pressed_pure_mod = is_shift and "shift_ctrl" or (is_alt and "ctrl_alt" or "ctrl")
                elseif reaper.APIExists("ImGui_Key_LeftAlt") and (reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_LeftAlt()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_RightAlt())) then
                    pressed_pure_mod = is_shift and "shift_alt" or (is_ctrl and "ctrl_alt" or "alt")
                end

                if pressed_pure_mod then
                    state[state.capturing_nav_action] = pressed_pure_mod
                    require('state').save_settings(state)
                    state.status_msg = "Navigation key assigned: " .. pressed_pure_mod
                    state.capturing_nav_action = nil
                else
                    for _, key_name in ipairs(shortcut_manager.SCAN_KEYS) do
                        local k_code = shortcut_manager.get_key_enum(key_name)
                        if k_code and reaper.ImGui_IsKeyPressed(ctx, k_code) then
                            local final_key = key_name:lower()
                            if key_name == "Space" then final_key = "space" end
                            if is_shift and final_key ~= "shift" then final_key = "shift+" .. final_key end
                            if is_ctrl and not final_key:find("ctrl") then final_key = "ctrl+" .. final_key end
                            if is_alt and not final_key:find("alt") then final_key = "alt+" .. final_key end
                            state[state.capturing_nav_action] = final_key
                            require('state').save_settings(state)
                            state.status_msg = "Navigation key assigned: " .. final_key
                            state.capturing_nav_action = nil
                            break
                        end
                    end
                end
            end
        end

        local default_open = (reaper.APIExists("ImGui_TreeNodeFlags_DefaultOpen") and reaper.ImGui_TreeNodeFlags_DefaultOpen()) or 32
        local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        local footer_h = 44

        -- Scrollable settings body
        if reaper.ImGui_BeginChild(ctx, "SettingsBodyScroll", 0, avail_h - footer_h, 0) then

            -- ==============================================================
            -- 1. General Settings
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "⚙ General Settings###hdr_general", nil, default_open) then
                reaper.ImGui_Spacing(ctx)
                
                -- --- 1. Canvas Layout & Track Spacing ---
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Canvas Layout & Track Spacing")
                else
                    reaper.ImGui_TextDisabled(ctx, "Canvas Layout & Track Spacing")
                    reaper.ImGui_Separator(ctx)
                end

                -- Track Spacing & Item Bounds
                local ts = state.track_spacing or 195.0
                local ts_changed, new_ts = reaper.ImGui_SliderDouble(ctx, "Track Spacing", ts, 70.0, 320.0, "%.1f px")
                if ts_changed then state.track_spacing = new_ts; require('state').save_settings(state) end
                
                local ib = (state.show_item_boxes ~= false)
                local ib_changed, new_ib = reaper.ImGui_Checkbox(ctx, "Show MIDI Item Bounds & Tags", ib)
                if ib_changed then state.show_item_boxes = new_ib; require('state').save_settings(state) end
                
                reaper.ImGui_Spacing(ctx)

                -- --- 2. Note Audio Audition ---
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Audio & Note Preview")
                else
                    reaper.ImGui_TextDisabled(ctx, "Audio & Note Preview")
                    reaper.ImGui_Separator(ctx)
                end

                local aud = (state.audition_notes ~= false)
                local aud_changed, new_aud = reaper.ImGui_Checkbox(ctx, "Audition notes on click / edit", aud)
                if aud_changed then
                    state.audition_notes = new_aud
                    require('state').save_settings(state)
                    if not state.audition_notes then
                        local audio_preview = require("services.audio_preview")
                        audio_preview.stop_all(state)
                    end
                end
                
                if state.audition_notes ~= false then
                    local av = math.floor(state.audition_volume or 50)
                    local av_changed, new_av = reaper.ImGui_SliderInt(ctx, "Preview Volume (50% = Written Dynamics, 100% = Max)", av, 0, 100, "%d%%")
                    if av_changed then
                        state.audition_volume = new_av
                        require('state').save_settings(state)
                    end

                    -- Preview Volume CC Controller Dropdown
                    local cur_cc = state.audition_cc or "11_1"
                    local function get_audition_cc_display(val)
                        if val == "none" or val == -1 or val == "-1" then
                            return "None (Velocity Only)"
                        elseif val == "11_1" then
                            return "CC  11 + CC 1 - Expression & Mod Wheel (Default / Orchestral)"
                        end
                        local num = tonumber(val) or 11
                        local name = Constants.get_cc_name(num)
                        return string.format("CC %3d  - %s", num, name)
                    end

                    reaper.ImGui_SetNextItemWidth(ctx, 320)
                    if reaper.ImGui_BeginCombo(ctx, "Preview Volume Controller (MIDI CC)##audition_cc_combo", get_audition_cc_display(cur_cc)) then
                        -- Presets
                        local presets = {
                            { id = "11_1", label = "CC  11 + CC 1 - Expression & Mod Wheel (Default / Orchestral)" },
                            { id = "11",   label = "CC  11  - Expression" },
                            { id = "1",    label = "CC   1  - Modulation Wheel" },
                            { id = "7",    label = "CC   7  - Channel Volume" },
                            { id = "none", label = "None (Velocity Only — Recommended for Pianos & Synths)" },
                        }
                        for _, p in ipairs(presets) do
                            local is_sel = (tostring(cur_cc) == p.id)
                            if reaper.ImGui_Selectable(ctx, p.label .. "##preset_" .. p.id, is_sel) then
                                state.audition_cc = p.id
                                require('state').save_settings(state)
                            end
                            if is_sel then reaper.ImGui_SetItemDefaultFocus(ctx) end
                        end

                        reaper.ImGui_Separator(ctx)

                        -- All 128 MIDI CC Channels (0 to 127)
                        for cc_idx = 0, 127 do
                            local cc_id = tostring(cc_idx)
                            local is_sel = (tostring(cur_cc) == cc_id)
                            local name = Constants.get_cc_name(cc_idx)
                            local label = string.format("CC %3d  - %s##cc_idx_%d", cc_idx, name, cc_idx)
                            if reaper.ImGui_Selectable(ctx, label, is_sel) then
                                state.audition_cc = cc_id
                                require('state').save_settings(state)
                            end
                            if is_sel then reaper.ImGui_SetItemDefaultFocus(ctx) end
                        end
                        reaper.ImGui_EndCombo(ctx)
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, "Select which MIDI Controller is temporarily modified by the preview volume slider.\n- Choose 'CC 11 + CC 1' (Default) for orchestral sample libraries (Spitfire, Orchestral Tools, SINE, etc.).\n- Choose 'None' for Pianos, Keyboards & Synths (only Note Velocity is sent).")
                    end

                    local r_cc = (state.audition_restore_cc ~= false)
                    local r_cc_chg, new_r_cc = reaper.ImGui_Checkbox(ctx, "Restore original controller value after preview", r_cc)
                    if r_cc_chg then
                        state.audition_restore_cc = new_r_cc
                        require('state').save_settings(state)
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, "When enabled, any temporarily altered CC value is automatically restored to its original value\nwhen the note is released, preventing permanent volume drops in instruments like SINE Player or UVI Falcon.")
                    end
                end

                reaper.ImGui_Spacing(ctx)

                -- --- 3. Measure & Rehearsal Elements ---
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Measure & Rehearsal Elements")
                else
                    reaper.ImGui_TextDisabled(ctx, "Measure & Rehearsal Elements")
                    reaper.ImGui_Separator(ctx)
                end

                local bno_y = state.bar_num_offset_y or 47.5
                local bnoy_changed, new_bnoy = reaper.ImGui_SliderDouble(ctx, "Bar Numbers Y-Offset", bno_y, 0.0, 95.0, "%.1f px")
                if bnoy_changed then state.bar_num_offset_y = new_bnoy; require('state').save_settings(state) end
                
                local bns = state.bar_num_size or 20.0
                local bns_changed, new_bns = reaper.ImGui_SliderDouble(ctx, "Bar Numbers Font Size", bns, 8.0, 32.0, "%.1f px")
                if bns_changed then state.bar_num_size = new_bns; require('state').save_settings(state) end
                
                local rmoy = state.rehearsal_mark_offset_y or -44.0
                local rmoy_changed, new_rmoy = reaper.ImGui_SliderDouble(ctx, "Rehearsal Marks Y-Offset", rmoy, -88.0, 0.0, "%.1f px")
                if rmoy_changed then state.rehearsal_mark_offset_y = new_rmoy; require('state').save_settings(state) end

                reaper.ImGui_Spacing(ctx)

                -- --- 4. Above-Staff Notations ---
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Vertical Offsets (Above Staff)")
                else
                    reaper.ImGui_TextDisabled(ctx, "Vertical Offsets (Above Staff)")
                    reaper.ImGui_Separator(ctx)
                end

                local toy = state.tempo_offset_y or 62.0
                local toy_changed, new_toy = reaper.ImGui_SliderDouble(ctx, "Tempo Markers Vertical Offset (Above Staff)", toy, 10.0, 114.0, "%.1f px")
                if toy_changed then state.tempo_offset_y = new_toy; require('state').save_settings(state) end

                local tfs = state.tempo_font_size or 16.0
                local tfs_changed, new_tfs = reaper.ImGui_SliderDouble(ctx, "Tempo Markers Font Size", tfs, 8.0, 24.0, "%.1f px")
                if tfs_changed then state.tempo_font_size = new_tfs; require('state').save_settings(state) end
                
                local ooy = state.octave_offset_y or 18.0
                local ooy_changed, new_ooy = reaper.ImGui_SliderDouble(ctx, "Octave Lines Vertical Offset (Above Staff)", ooy, 0.0, 36.0, "%.1f px")
                if ooy_changed then state.octave_offset_y = new_ooy; require('state').save_settings(state) end

                local aoy = state.articulations_offset_y or 37.0
                local aoy_changed, new_aoy = reaper.ImGui_SliderDouble(ctx, "Articulations Vertical Offset (Above Staff)", aoy, 0.0, 74.0, "%.1f px")
                if aoy_changed then state.articulations_offset_y = new_aoy; require('state').save_settings(state) end

                reaper.ImGui_Spacing(ctx)

                -- --- 5. Below-Staff Notations ---
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Vertical Offsets (Below Staff)")
                else
                    reaper.ImGui_TextDisabled(ctx, "Vertical Offsets (Below Staff)")
                    reaper.ImGui_Separator(ctx)
                end

                local doy = state.dynamics_offset_y or 79.0
                local doy_changed, new_doy = reaper.ImGui_SliderDouble(ctx, "Dynamics & Hairpins Vertical Offset (Below Staff)", doy, 20.0, 138.0, "%.1f px")
                if doy_changed then
                    state.dynamics_offset_y = new_doy
                    state.hairpins_offset_y = new_doy
                    require('state').save_settings(state)
                end

                local poy = state.pedal_offset_y or 75.0
                local poy_changed, new_poy = reaper.ImGui_SliderDouble(ctx, "Pedal / Sustain Vertical Offset (Below Staff)", poy, 10.0, 140.0, "%.1f px")
                if poy_changed then state.pedal_offset_y = new_poy; require('state').save_settings(state) end
                
                reaper.ImGui_Spacing(ctx)
            end
            
            reaper.ImGui_Spacing(ctx)

            -- ==============================================================
            -- 2. Portamento Defaults & Playback Settings
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "〰 Portamento Defaults & Playback###hdr_portamento", nil, default_open) then
                reaper.ImGui_Spacing(ctx)

                -- 1. Default Playback Mode
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Default Playback Blend & Control Mode")
                else
                    reaper.ImGui_TextDisabled(ctx, "Default Playback Blend & Control Mode")
                    reaper.ImGui_Separator(ctx)
                end

                local cur_mode = state.portamento_default_mode or "cc64"
                local mode_labels = {
                    cc64 = "CC 64 (Pedal Hold Blend) [Standard]",
                    cc34 = "CC 34 (Portamento Control)",
                    cc5  = "CC 5 (Portamento Time)",
                    cc65 = "CC 65 (Portamento Switch On/Off)",
                }
                reaper.ImGui_SetNextItemWidth(ctx, 320)
                if reaper.ImGui_BeginCombo(ctx, "Default MIDI CC Mode##port_def_mode_combo", mode_labels[cur_mode] or cur_mode) then
                    local modes = {
                        { id = "cc64", label = "CC 64 (Pedal Hold Blend) [Standard]" },
                        { id = "cc34", label = "CC 34 (Portamento Control)" },
                        { id = "cc5",  label = "CC 5 (Portamento Time)" },
                        { id = "cc65", label = "CC 65 (Portamento Switch On/Off)" },
                    }
                    for _, m in ipairs(modes) do
                        local is_sel = (cur_mode == m.id)
                        if reaper.ImGui_Selectable(ctx, m.label .. "##def_mode_" .. m.id, is_sel) then
                            state.portamento_default_mode = m.id
                            require('state').save_settings(state)
                        end
                        if is_sel then reaper.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Select default MIDI controller mode for newly created portamentos:\n- CC 64 (Pedal Hold): Holds previous note over into the arrival notehead for acoustic blending (Recommended for orchestral strings & woodwinds).\n- CC 34: Standard MIDI Portamento Control.\n- CC 5: Portamento Time (Glide speed).\n- CC 65: Portamento On/Off Switch.")
                end

                reaper.ImGui_Spacing(ctx)

                -- 2. Timing (% of Note Length)
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Default Timing (% of Note Duration)")
                else
                    reaper.ImGui_TextDisabled(ctx, "Default Timing (% of Note Duration)")
                    reaper.ImGui_Separator(ctx)
                end

                -- Start Timing (Note 1)
                local cur_s = math.floor(state.portamento_default_start_pct or 50)
                reaper.ImGui_SetNextItemWidth(ctx, 240)
                local s_chg, new_s = reaper.ImGui_SliderInt(ctx, "Default Start at Note 1##port_def_s_slider", cur_s, 0, 100, "%d%%")
                if s_chg then
                    state.portamento_default_start_pct = new_s
                    require('state').save_settings(state)
                end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextDisabled(ctx, "Presets:")
                for _, pct in ipairs({ 0, 25, 50, 75, 100 }) do
                    reaper.ImGui_SameLine(ctx)
                    local is_sel = (cur_s == pct)
                    local tag = (pct == 50) and "50% [Std]" or string.format("%d%%", pct)
                    if is_sel then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3498DBFF)
                    end
                    if reaper.ImGui_Button(ctx, tag .. "##port_def_s_" .. pct) then
                        state.portamento_default_start_pct = pct
                        require('state').save_settings(state)
                    end
                    if is_sel then
                        reaper.ImGui_PopStyleColor(ctx)
                    end
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Percentage of Note 1 duration where the portamento hold is engaged (50% = halfway through Note 1).")
                end

                -- End Timing (Note 2)
                local cur_e = math.floor(state.portamento_default_end_pct or 50)
                reaper.ImGui_SetNextItemWidth(ctx, 240)
                local e_chg, new_e = reaper.ImGui_SliderInt(ctx, "Default End at Note 2##port_def_e_slider", cur_e, 0, 100, "%d%%")
                if e_chg then
                    state.portamento_default_end_pct = new_e
                    require('state').save_settings(state)
                end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextDisabled(ctx, "Presets:")
                for _, pct in ipairs({ 0, 25, 50, 75, 100 }) do
                    reaper.ImGui_SameLine(ctx)
                    local is_sel = (cur_e == pct)
                    local tag = (pct == 50) and "50% [Std]" or string.format("%d%%", pct)
                    if is_sel then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3498DBFF)
                    end
                    if reaper.ImGui_Button(ctx, tag .. "##port_def_e_" .. pct) then
                        state.portamento_default_end_pct = pct
                        require('state').save_settings(state)
                    end
                    if is_sel then
                        reaper.ImGui_PopStyleColor(ctx)
                    end
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Percentage of Note 2 arrival notehead duration where the portamento hold is released (50% = halfway through Note 2).")
                end

                reaper.ImGui_Spacing(ctx)

                -- 3. Visual & Text Badges
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Visual Appearance & Badge Defaults")
                else
                    reaper.ImGui_TextDisabled(ctx, "Visual Appearance & Badge Defaults")
                    reaper.ImGui_Separator(ctx)
                end

                local def_txt = (state.portamento_default_show_text == true)
                local txt_chg, new_txt = reaper.ImGui_Checkbox(ctx, 'Show "port." text badge by default##port_def_txt_chk', def_txt)
                if txt_chg then
                    state.portamento_default_show_text = new_txt
                    require('state').save_settings(state)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "When enabled, newly created portamento lines display an italic 'port.' label above the line.")
                end

                local def_gap = state.portamento_default_gap or 16.0
                reaper.ImGui_SetNextItemWidth(ctx, 240)
                local gap_chg, new_gap = reaper.ImGui_SliderDouble(ctx, "Notehead Gap Distance##port_def_gap", def_gap, 4.0, 32.0, "%.1f px")
                if gap_chg then
                    state.portamento_default_gap = new_gap
                    require('state').save_settings(state)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Spacing distance between notehead centers and the ends of the diagonal portamento line (Default: 16.0 px).")
                end

                local def_th = state.portamento_default_thickness or 1.6
                reaper.ImGui_SetNextItemWidth(ctx, 240)
                local th_chg, new_th = reaper.ImGui_SliderDouble(ctx, "Line Thickness##port_def_th", def_th, 0.8, 4.0, "%.1f px")
                if th_chg then
                    state.portamento_default_thickness = new_th
                    require('state').save_settings(state)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Drawing thickness of portamento lines on the score canvas (Default: 1.6 px).")
                end

                reaper.ImGui_Spacing(ctx)

                -- 4. Batch Actions
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Actions & Project Sync")
                else
                    reaper.ImGui_TextDisabled(ctx, "Actions & Project Sync")
                    reaper.ImGui_Separator(ctx)
                end

                local num_existing = (state.portamento_marks and #state.portamento_marks) or 0
                if reaper.ImGui_Button(ctx, string.format("🔄 Apply Defaults to All Existing Portamentos (%d in project)##port_apply_all", num_existing)) then
                    local PortamentoService = require("services.portamento_service")
                    local updated_cnt = PortamentoService.apply_defaults_to_all(state, state.active_tracks_cache)
                    state.status_msg = string.format("Updated %d portamentos in project to current default settings.", updated_cnt)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Applies the current default settings (Mode, Start %, End %, and 'port.' text visibility) to all portamentos in this project and synchronizes MIDI CCs.")
                end

                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "↺ Reset to Factory Defaults##port_reset_defaults") then
                    state.portamento_default_mode = "cc64"
                    state.portamento_default_start_pct = 50
                    state.portamento_default_end_pct = 50
                    state.portamento_default_show_text = false
                    state.portamento_default_gap = 16.0
                    state.portamento_default_thickness = 1.6
                    require('state').save_settings(state)
                    state.status_msg = "Reset portamento defaults to factory settings (CC64, 50% Start, 50% End, Text Off, Gap 16px, 1.6px Thickness)."
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Resets all portamento default settings to standard: CC 64, 50% Start, 50% End, Text Off, 16.0 px Gap, 1.6 px Thickness.")
                end

                reaper.ImGui_Spacing(ctx)
            end

            reaper.ImGui_Spacing(ctx)

            -- ==============================================================
            -- 2b. Glissando Defaults & Playback Configuration
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "〰 Glissando Defaults & Playback###hdr_glissando") then
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_TextWrapped(ctx, "Configure global defaults for newly created Glissando marks. Glissandos play real chromatic pitch steps in MIDI while keeping the score canvas clean with an elegant wavy line.")
                reaper.ImGui_Spacing(ctx)

                -- 1. Timing & Playback Defaults
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Timing & Playback Defaults")
                else
                    reaper.ImGui_TextDisabled(ctx, "Timing & Playback Defaults")
                    reaper.ImGui_Separator(ctx)
                end

                -- Start Timing (Note 1)
                local cur_s = math.floor(state.glissando_default_start_pct or 50)
                reaper.ImGui_SetNextItemWidth(ctx, 240)
                local s_chg, new_s = reaper.ImGui_SliderInt(ctx, "Default Start at Note 1##gliss_def_s_slider", cur_s, 0, 100, "%d%%")
                if s_chg then
                    state.glissando_default_start_pct = new_s
                    require('state').save_settings(state)
                end
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextDisabled(ctx, "Presets:")
                for _, pct in ipairs({ 0, 25, 50, 75, 100 }) do
                    reaper.ImGui_SameLine(ctx)
                    local is_sel = (cur_s == pct)
                    local tag = (pct == 50) and "50% [Std]" or string.format("%d%%", pct)
                    if is_sel then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3498DBFF)
                    end
                    if reaper.ImGui_Button(ctx, tag .. "##gliss_def_s_" .. pct) then
                        state.glissando_default_start_pct = pct
                        require('state').save_settings(state)
                    end
                    if is_sel then
                        reaper.ImGui_PopStyleColor(ctx)
                    end
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Percentage of Note 1 duration where the chromatic pitch staircase begins (50% = halfway through Note 1).")
                end

                -- Velocity Mode
                local cur_vel_mode = state.glissando_default_vel_mode or "interpolate"
                reaper.ImGui_SetNextItemWidth(ctx, 240)
                local vel_label = (cur_vel_mode == "interpolate") and "Linear Ramp (Note 1 -> Note 2)" or "Flat (Note 1 Velocity)"
                if reaper.ImGui_BeginCombo(ctx, "Velocity Mode##gliss_def_vel_combo", vel_label) then
                    local modes = {
                        { id = "interpolate", label = "Linear Ramp (Note 1 -> Note 2)" },
                        { id = "flat",        label = "Flat (Note 1 Velocity)" }
                    }
                    for _, vm in ipairs(modes) do
                        local is_sel = (cur_vel_mode == vm.id)
                        if reaper.ImGui_Selectable(ctx, vm.label .. "##gliss_vm_" .. vm.id, is_sel) then
                            state.glissando_default_vel_mode = vm.id
                            require('state').save_settings(state)
                        end
                        if is_sel then reaper.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Velocity shaping for intermediate chromatic steps. Linear Ramp creates dynamic transitions between Note 1 and Note 2.")
                end

                reaper.ImGui_Spacing(ctx)

                -- 2. Visual Appearance & Badge Defaults
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Visual Appearance & Badge Defaults")
                else
                    reaper.ImGui_TextDisabled(ctx, "Visual Appearance & Badge Defaults")
                    reaper.ImGui_Separator(ctx)
                end

                -- Wave Style
                local cur_style = state.glissando_default_wave_style or "sine"
                reaper.ImGui_SetNextItemWidth(ctx, 240)
                local style_label = (cur_style == "sine") and "Sinusoidal Wave (Smooth)" or ((cur_style == "saw") and "Sawtooth / Zigzag Wave" or "Straight Line")
                if reaper.ImGui_BeginCombo(ctx, "Wave Style##gliss_def_style_combo", style_label) then
                    if reaper.ImGui_Selectable(ctx, "Sinusoidal Wave (Smooth)##gliss_ws_sine", cur_style == "sine") then
                        state.glissando_default_wave_style = "sine"
                        require('state').save_settings(state)
                    end
                    if reaper.ImGui_Selectable(ctx, "Sawtooth / Zigzag Wave##gliss_ws_saw", cur_style == "saw") then
                        state.glissando_default_wave_style = "saw"
                        require('state').save_settings(state)
                    end
                    if reaper.ImGui_Selectable(ctx, "Straight Line##gliss_ws_straight", cur_style == "straight" or cur_style == "line") then
                        state.glissando_default_wave_style = "straight"
                        require('state').save_settings(state)
                    end
                    reaper.ImGui_EndCombo(ctx)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Visual drawing style of the wavy glissando line on the score canvas.")
                end

                local def_txt = (state.glissando_default_show_text == true)
                local txt_chg, new_txt = reaper.ImGui_Checkbox(ctx, 'Show "gliss." text badge by default##gliss_def_txt_chk', def_txt)
                if txt_chg then
                    state.glissando_default_show_text = new_txt
                    require('state').save_settings(state)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "When enabled, newly created glissando lines display an italic 'gliss.' label above the wavy line.")
                end

                local def_gap = state.glissando_default_gap or 16.0
                reaper.ImGui_SetNextItemWidth(ctx, 240)
                local gap_chg, new_gap = reaper.ImGui_SliderDouble(ctx, "Notehead Gap Distance##gliss_def_gap", def_gap, 4.0, 32.0, "%.1f px")
                if gap_chg then
                    state.glissando_default_gap = new_gap
                    require('state').save_settings(state)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Spacing distance between notehead centers and the ends of the wavy line (Default: 16.0 px).")
                end

                local def_th = state.glissando_default_thickness or 1.6
                reaper.ImGui_SetNextItemWidth(ctx, 240)
                local th_chg, new_th = reaper.ImGui_SliderDouble(ctx, "Line Thickness##gliss_def_th", def_th, 0.8, 4.0, "%.1f px")
                if th_chg then
                    state.glissando_default_thickness = new_th
                    require('state').save_settings(state)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Drawing thickness of glissando waves on the score canvas (Default: 1.6 px).")
                end

                reaper.ImGui_Spacing(ctx)

                -- 3. Batch Actions
                if reaper.APIExists("ImGui_SeparatorText") then
                    reaper.ImGui_SeparatorText(ctx, "Actions & Project Sync")
                else
                    reaper.ImGui_TextDisabled(ctx, "Actions & Project Sync")
                    reaper.ImGui_Separator(ctx)
                end

                local num_existing = (state.glissando_marks and #state.glissando_marks) or 0
                if reaper.ImGui_Button(ctx, string.format("🔄 Apply Defaults to All Existing Glissandos (%d in project)##gliss_apply_all", num_existing)) then
                    local GlissandoService = require("services.glissando_service")
                    local updated_cnt = GlissandoService.apply_defaults_to_all(state, state.active_tracks_cache)
                    state.status_msg = string.format("Updated %d glissandos in project to current default settings.", updated_cnt)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Applies the current default settings to all glissandos in this project and synchronizes MIDI chromatic steps.")
                end

                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "↺ Reset to Factory Defaults##gliss_reset_defaults") then
                    state.glissando_default_start_pct = 50
                    state.glissando_default_vel_mode = "interpolate"
                    state.glissando_default_wave_style = "sine"
                    state.glissando_default_show_text = true
                    state.glissando_default_gap = 14.0
                    state.glissando_default_thickness = 1.6
                    require('state').save_settings(state)
                    state.status_msg = "Reset glissando defaults to factory settings (50% Start, Linear Ramp, Sine Wave, Text On, Gap 14px, 1.6px Thickness)."
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Resets all glissando default settings to standard: 50% Start, Linear Ramp, Sine Wave, Text On, 14.0 px Gap, 1.6 px Thickness.")
                end

                reaper.ImGui_Spacing(ctx)
            end

            reaper.ImGui_Spacing(ctx)

            -- ==============================================================
            -- 3. REAPER User Directory & Paths
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "📁 REAPER User Directory & Paths###hdr_paths") then
                reaper.ImGui_Spacing(ctx)
                local status = PathService.detect_status(state)
                
                -- OS Detection Badge
                local os_label = (status.os_type == "windows") and ("Windows (" .. (status.os_raw or "Win") .. ")")
                              or ((status.os_type == "macos") and ("macOS (" .. (status.os_raw or "Mac") .. ")")
                              or ("Linux (" .. (status.os_raw or "Unix") .. ")"))
                
                reaper.ImGui_TextDisabled(ctx, "Platform detected:")
                reaper.ImGui_SameLine(ctx)
                reaper.ImGui_TextColored(ctx, 0x64D2FFFF, os_label)
                
                -- Platform default path hint
                reaper.ImGui_TextDisabled(ctx, "Standard location: " .. PathService.get_os_default_path_hint())
                reaper.ImGui_Spacing(ctx)
                
                -- Path Input
                local cur_path = state.custom_resource_path or ""
                reaper.ImGui_Text(ctx, "REAPER User / Resource Folder:")
                reaper.ImGui_SetNextItemWidth(ctx, -230)
                local path_changed, new_path = reaper.ImGui_InputTextWithHint(ctx, "##reaper_user_path", "Default: Auto-detected from REAPER", cur_path)
                if path_changed then
                    state.custom_resource_path = new_path
                end
                
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "🔍 Auto-Detect##res_path", 95, 22) then
                    local def_res = reaper.APIExists("GetResourcePath") and reaper.GetResourcePath() or ""
                    state.custom_resource_path = PathService.normalize(def_res)
                    require('state').save_settings(state)
                    ReaticulateParser.reload_all_banks(state)
                    state.status_msg = "Resource path detected: " .. state.custom_resource_path
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Fills the field with the active REAPER installation directory.")
                end
                
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "↺ Reset##res_path", 55, 22) then
                    state.custom_resource_path = ""
                    require('state').save_settings(state)
                    ReaticulateParser.reload_all_banks(state)
                    state.status_msg = "Resource path reset to default."
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Resets to default REAPER resource path.")
                end

                local saved_path = reaper.GetExtState("REAPER_Notator", "reaper_resource_path") or ""
                if (state.custom_resource_path or "") ~= saved_path then
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "💾 Save##res_path", 60, 22) then
                        require('state').save_settings(state)
                        ReaticulateParser.reload_all_banks(state)
                        state.status_msg = "REAPER user path saved!"
                    end
                end
                
                -- Live Validation Status Badges
                reaper.ImGui_Spacing(ctx)
                if status.res_dir_valid then
                    reaper.ImGui_TextColored(ctx, 0x2ECC71FF, "✓ Active Folder: ")
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_Text(ctx, status.res_dir)
                else
                    reaper.ImGui_TextColored(ctx, 0xE74C3CFF, "✗ Active Folder Not Found: ")
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_Text(ctx, (status.res_dir ~= "" and status.res_dir or "Empty"))
                end
                
                -- Reaticulate & ReaBanks Status
                if status.reaticulate_found then
                    reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("✓ Reaticulate & ReaBanks detected (%d bank files found)", status.reabank_count))
                else
                    reaper.ImGui_TextDisabled(ctx, "ℹ Reaticulate not detected in Data/ or Scripts/Reaticulate")
                end
                
                -- Notator App directory info
                reaper.ImGui_TextDisabled(ctx, string.format("REAPER-Notator Home: %s | Bravura: %s | Patterns: %s",
                    status.script_dir,
                    status.bravura_valid and "✓ OK" or "✗ Missing",
                    status.patterns_valid and "✓ OK (1050)" or "✗ Missing"
                ))
                
                reaper.ImGui_Spacing(ctx)
            end
            
            reaper.ImGui_Spacing(ctx)

            -- ==============================================================
            -- 3. Voice & Ghost Notes Settings
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "👻 Voice & Ghost Notes Settings###hdr_voice") then
                reaper.ImGui_Spacing(ctx)
                local cur_op = math.floor(((state.ghost_voice_opacity or 0.25) * 100) + 0.5)
                local op_changed, new_op = reaper.ImGui_SliderInt(ctx, "Ghost Notes & Elements Opacity", cur_op, 5, 100, "%d%%")
                if op_changed then
                    state.ghost_voice_opacity = new_op / 100.0
                    require('state').save_settings(state)
                end
                local col_v = (state.voice_color_mode ~= false)
                local col_v_changed, new_col_v = reaper.ImGui_Checkbox(ctx, "Color Notes by Voice (MIDI Channels 1-16)", col_v)
                if col_v_changed then
                    state.voice_color_mode = new_col_v
                    require('state').save_settings(state)
                end
                local hide_v = (state.hide_inactive_voices == true)
                local hide_v_changed, new_hide_v = reaper.ImGui_Checkbox(ctx, "Hide Inactive Voices completely (instead of Ghosting)", hide_v)
                if hide_v_changed then
                    state.hide_inactive_voices = new_hide_v
                    require('state').save_settings(state)
                end
                reaper.ImGui_Spacing(ctx)
            end
            
            reaper.ImGui_Spacing(ctx)

            -- ==============================================================
            -- 4. Appearance & Colors
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "🎨 Appearance & Colors###hdr_appearance") then
                reaper.ImGui_Spacing(ctx)
                local inv_changed, new_inv = reaper.ImGui_Checkbox(ctx, "Invert Mode (Dark Mode)", state.invert_mode or false)
                if inv_changed then 
                    state.invert_mode = new_inv 
                    SettingsModal.apply_theme(state)
                    require('state').save_settings(state)
                end
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "Reset Colors") then
                    state.custom_colors = nil
                    SettingsModal.apply_theme(state)
                    require('state').save_settings(state)
                end
                
                local cur_int = math.floor(state.item_box_intensity or 25)
                local int_changed, new_int = reaper.ImGui_SliderInt(ctx, "MIDI Track Boxes Color Intensity", cur_int, 5, 100, "%d %%")
                if int_changed then
                    state.item_box_intensity = new_int
                    require('state').save_settings(state)
                end
                reaper.ImGui_Spacing(ctx)
                
                if not state.custom_colors then
                    state.custom_colors = {}
                end
                
                local function color_edit(label, key, default_col)
                    local current_col = state.custom_colors[key]
                    if not current_col then
                        current_col = Constants.COLORS[key] or Constants.DEFAULT_COLORS[key] or default_col
                    end
                    
                    local flags = 0
                    if reaper.APIExists("ImGui_ColorEditFlags_NoInputs") then flags = flags | reaper.ImGui_ColorEditFlags_NoInputs() end
                    if reaper.APIExists("ImGui_ColorEditFlags_AlphaPreview") then flags = flags | reaper.ImGui_ColorEditFlags_AlphaPreview() end
                    local changed, new_col_u32 = reaper.ImGui_ColorEdit4(ctx, label, current_col, flags)
                    
                    if changed then
                        state.custom_colors[key] = new_col_u32
                        SettingsModal.apply_theme(state)
                        require('state').save_settings(state)
                    end
                end
                
                -- Row 1: Canvas & Staff
                color_edit("Background", "paper_bg", 0xFAF8F5FF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Staff Lines", "staff_line", 0x222222FF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Barlines", "barline", 0x000000FF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Beat Lines", "beatline", 0xEAE6DCFF)
                
                -- Row 2: Notes & Structural Notation
                color_edit("Notes & Beams", "notehead_black", 0x111111FF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Clefs & Key Sigs", "clef_col", 0x1A1A1AFF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Time Signatures", "timesig_col", 0x1A1A1AFF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Rests & Ties", "rest_col", 0x1A1A1AFF)
                
                -- Row 3: Numbers & Text
                color_edit("Bar Numbers", "bar_num", 0x111111FF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Articulations", "art_text", 0x1A1A1AFF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Lyrics & Text", "lyrics_text", 0x1A1A1AFF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Fermatas", "fermata_col", 0x111111FF)

                -- Row 4: Rehearsal Marks
                color_edit("Rehearsal Frame", "rehearsal_border", 0x1A1A1AFF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Rehearsal Box BG", "rehearsal_box_bg", 0xFAF8F5FF)
                reaper.ImGui_SameLine(ctx)
                color_edit("Rehearsal Letter", "rehearsal_text", 0x111111FF)
                
                reaper.ImGui_Spacing(ctx)
            end
            
            reaper.ImGui_Spacing(ctx)

            -- ==============================================================
            -- 5. View Navigation and Mouse Settings
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "🖱 View Navigation and Mouse Settings###hdr_nav_mouse", nil, default_open) then
                reaper.ImGui_Spacing(ctx)
                
                local KEY_PRESETS = {
                    { id = "none",       label = "None (No Key)" },
                    { id = "shift",      label = "Shift" },
                    { id = "ctrl",       label = "Ctrl / Cmd" },
                    { id = "alt",        label = "Alt / Opt" },
                    { id = "space",      label = "Space" },
                    { id = "shift_ctrl", label = "Shift + Ctrl" },
                    { id = "shift_alt",  label = "Shift + Alt" },
                    { id = "ctrl_alt",   label = "Ctrl + Alt" },
                }

                local MOUSE_PRESETS = {
                    { id = "wheel_v",     label = "Mouse Wheel (Vertical)" },
                    { id = "wheel_h",     label = "Mouse Wheel (Horizontal Tilt)" },
                    { id = "mouse_mid",   label = "Middle Mouse Button" },
                    { id = "mouse_right", label = "Right Mouse Button" },
                    { id = "mouse_left",  label = "Left Mouse Button" },
                    { id = "disabled",    label = "Disabled" },
                }

                local function get_key_display(k_id)
                    if not k_id or k_id == "" or k_id == "none" then return "None" end
                    for _, opt in ipairs(KEY_PRESETS) do
                        if opt.id == k_id then return opt.label end
                    end
                    local d = k_id:gsub("shift%+", "Shift + "):gsub("ctrl%+", "Ctrl + "):gsub("alt%+", "Alt + ")
                    return d:sub(1,1):upper() .. d:sub(2)
                end

                local function get_mouse_display(m_id)
                    if not m_id or m_id == "" then return "Disabled" end
                    for _, opt in ipairs(MOUSE_PRESETS) do
                        if opt.id == m_id then return opt.label end
                    end
                    return m_id
                end

                local function render_nav_row(action_title, key_prop, mouse_prop, default_key, default_mouse)
                    local cur_k = state[key_prop] or default_key
                    local cur_m = state[mouse_prop] or default_mouse
                    local is_capturing = (state.capturing_nav_action == key_prop)

                    -- 1. Action Label (aligned to 165px)
                    reaper.ImGui_AlignTextToFramePadding(ctx)
                    reaper.ImGui_Text(ctx, action_title)
                    reaper.ImGui_SameLine(ctx, 175)

                    -- 2. Keyboard Shortcut Dropdown (125px)
                    reaper.ImGui_SetNextItemWidth(ctx, 125)
                    if reaper.ImGui_BeginCombo(ctx, "##kcombo_" .. key_prop, get_key_display(cur_k)) then
                        for _, opt in ipairs(KEY_PRESETS) do
                            local is_sel = (opt.id == cur_k)
                            if reaper.ImGui_Selectable(ctx, opt.label, is_sel) then
                                state[key_prop] = opt.id
                                require('state').save_settings(state)
                            end
                            if is_sel then reaper.ImGui_SetItemDefaultFocus(ctx) end
                        end
                        reaper.ImGui_EndCombo(ctx)
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, "Select key/modifier from list, or click 'Assign' to press any key.")
                    end

                    -- 3. Assign Button (58px)
                    reaper.ImGui_SameLine(ctx, 0, 5)
                    if is_capturing then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xE06610FF)
                        if reaper.ImGui_Button(ctx, "Press...##btn_" .. key_prop, 58, 22) then
                            state.capturing_nav_action = nil
                        end
                        reaper.ImGui_PopStyleColor(ctx)
                    else
                        if reaper.ImGui_Button(ctx, "Assign##btn_" .. key_prop, 58, 22) then
                            state.capturing_nav_action = key_prop
                        end
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, is_capturing and "Press any key on keyboard (or Esc to cancel, Backspace to clear)" or "Click and press any key on keyboard")
                    end

                    -- 4. Plus text
                    reaper.ImGui_SameLine(ctx, 0, 8)
                    reaper.ImGui_TextDisabled(ctx, "+")

                    -- 5. Mouse Action Dropdown (240px)
                    reaper.ImGui_SameLine(ctx, 0, 8)
                    reaper.ImGui_SetNextItemWidth(ctx, 240)
                    if reaper.ImGui_BeginCombo(ctx, "##mcombo_" .. mouse_prop, get_mouse_display(cur_m)) then
                        for _, opt in ipairs(MOUSE_PRESETS) do
                            local is_sel = (opt.id == cur_m)
                            if reaper.ImGui_Selectable(ctx, opt.label, is_sel) then
                                state[mouse_prop] = opt.id
                                require('state').save_settings(state)
                            end
                            if is_sel then reaper.ImGui_SetItemDefaultFocus(ctx) end
                        end
                        reaper.ImGui_EndCombo(ctx)
                    end
                end

                render_nav_row("Horizontal View Scroll", "nav_scroll_h_key", "nav_scroll_h_mouse", "shift", "wheel_v")
                render_nav_row("Vertical View Scroll",   "nav_scroll_v_key", "nav_scroll_v_mouse", "none",  "wheel_v")
                render_nav_row("Canvas Pan (Hand-Tool)", "nav_pan_key",      "nav_pan_mouse",      "none",  "mouse_mid")
                render_nav_row("Canvas Zoom (In / Out)", "nav_zoom_key",     "nav_zoom_mouse",     "ctrl",  "wheel_v")

                reaper.ImGui_Spacing(ctx)

                -- Duplicate modifier warning
                local h_k = state.nav_scroll_h_key or "shift"
                local h_m = state.nav_scroll_h_mouse or "wheel_v"
                local v_k = state.nav_scroll_v_key or "none"
                local v_m = state.nav_scroll_v_mouse or "wheel_v"
                if h_m ~= "disabled" and h_m == v_m and h_k == v_k then
                    reaper.ImGui_TextColored(ctx, 0xF59E0BFF, "  ⚠ Note: Horizontal & Vertical scroll share the exact same Shortcut and Mouse input.")
                end

                reaper.ImGui_Spacing(ctx)

                -- Scroll Speeds
                reaper.ImGui_SetNextItemWidth(ctx, 220)
                local sf_h = state.scroll_factor_h or state.scroll_factor or 3.0
                local sf_h_chg, new_sf_h = reaper.ImGui_SliderDouble(ctx, "Horizontal Scroll Speed##sf_h", sf_h, 0.5, 5.0, "%.1fx")
                if sf_h_chg then
                    state.scroll_factor_h = new_sf_h
                    state.scroll_factor = new_sf_h
                    require('state').save_settings(state)
                end

                reaper.ImGui_SetNextItemWidth(ctx, 220)
                local sf_v = state.scroll_factor_v or 2.0
                local sf_v_chg, new_sf_v = reaper.ImGui_SliderDouble(ctx, "Vertical Scroll Speed##sf_v", sf_v, 0.5, 5.0, "%.1fx")
                if sf_v_chg then
                    state.scroll_factor_v = new_sf_v
                    require('state').save_settings(state)
                end

                -- Invert Directions
                local inv_h = (state.scroll_invert_h == true)
                local inv_h_chg, new_inv_h = reaper.ImGui_Checkbox(ctx, "Invert Horizontal Direction", inv_h)
                if inv_h_chg then
                    state.scroll_invert_h = new_inv_h
                    require('state').save_settings(state)
                end

                reaper.ImGui_SameLine(ctx, 0, 24)
                local inv_v = (state.scroll_invert_v == true)
                local inv_v_chg, new_inv_v = reaper.ImGui_Checkbox(ctx, "Invert Vertical Direction", inv_v)
                if inv_v_chg then
                    state.scroll_invert_v = new_inv_v
                    require('state').save_settings(state)
                end

                reaper.ImGui_Spacing(ctx)

                if reaper.ImGui_SmallButton(ctx, "↺ Reset Navigation Defaults") then
                    state.nav_scroll_h_key   = "shift"
                    state.nav_scroll_h_mouse = "wheel_v"
                    state.nav_scroll_v_key   = "none"
                    state.nav_scroll_v_mouse = "wheel_v"
                    state.nav_pan_key        = "none"
                    state.nav_pan_mouse      = "mouse_mid"
                    state.nav_zoom_key       = "ctrl"
                    state.nav_zoom_mouse     = "wheel_v"
                    state.scroll_factor_h    = 3.0
                    state.scroll_factor_v    = 2.0
                    state.scroll_factor      = 3.0
                    state.scroll_invert_h    = false
                    state.scroll_invert_v    = false
                    require('state').save_settings(state)
                end

                reaper.ImGui_Spacing(ctx)
            end
            
            reaper.ImGui_Spacing(ctx)

            -- ==============================================================
            -- 6. Customize Keyboard Shortcuts
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "⌨ Customize Keyboard Shortcuts###hdr_shortcuts", nil, default_open) then
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_TextColored(ctx, 0xAAAAAAFF, "Click 'Assign' and press a key or key combination (with Shift/Ctrl/Alt).")
                
                -- Search filter
                state.shortcut_filter = state.shortcut_filter or ""
                reaper.ImGui_SetNextItemWidth(ctx, 220)
                local f_changed, new_f = reaper.ImGui_InputTextWithHint(ctx, "##sc_filter", "🔍 Filter shortcuts...", state.shortcut_filter)
                if f_changed then state.shortcut_filter = new_f end
                if state.shortcut_filter ~= "" then
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_Button(ctx, "Clear##sc_filter") then state.shortcut_filter = "" end
                end
                
                reaper.ImGui_Spacing(ctx)
                
                -- If a key is currently being captured:
                if state.capturing_action then
                    local current_target = shortcut_manager.shortcuts[state.capturing_action]
                    local action_title = current_target and current_target.name or state.capturing_action
                    
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x3A2200FF)
                    if reaper.ImGui_BeginChild(ctx, "CaptureBanner", 0, 52, 1) then
                        reaper.ImGui_TextColored(ctx, 0xFFD166FF, string.format("⏳ Press key for: '%s'", action_title))
                        reaper.ImGui_TextColored(ctx, 0xCCCCCCFF, "Optionally hold Shift, Ctrl, or Alt. [ESC] cancels.")
                        reaper.ImGui_EndChild(ctx)
                    end
                    reaper.ImGui_PopStyleColor(ctx)
                    reaper.ImGui_Spacing(ctx)
                end
                
                local filter_term = (state.shortcut_filter or ""):lower():match("^%s*(.-)%s*$")
                
                for _, cat in ipairs(shortcut_manager.CATEGORIES) do
                    local matching_actions = {}
                    for _, act_id in ipairs(shortcut_manager.ACTION_LIST) do
                        local sc = shortcut_manager.shortcuts[act_id]
                        if sc and sc.cat == cat then
                            if not filter_term or filter_term == "" then
                                table.insert(matching_actions, act_id)
                            else
                                local disp = shortcut_manager.get_display_string(sc):lower()
                                if sc.name:lower():find(filter_term, 1, true) or disp:find(filter_term, 1, true) or cat:lower():find(filter_term, 1, true) then
                                    table.insert(matching_actions, act_id)
                                end
                            end
                        end
                    end
                    
                    if #matching_actions > 0 then
                        reaper.ImGui_Spacing(ctx)
                        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "━━ " .. cat .. " ━━")
                        reaper.ImGui_Separator(ctx)
                        
                        for _, act_id in ipairs(matching_actions) do
                            local sc = shortcut_manager.shortcuts[act_id]
                            local is_this_capturing = (state.capturing_action == act_id)
                            
                            -- Column 1: Action name (left, max 260px)
                            reaper.ImGui_Text(ctx, sc.name)
                            if sc.desc and reaper.ImGui_IsItemHovered(ctx) then
                                reaper.ImGui_SetTooltip(ctx, sc.desc)
                            end
                            
                            -- Column 2: Current key assignment / badge
                            reaper.ImGui_SameLine(ctx, 270)
                            local disp_txt = is_this_capturing and "⏳ Press key..." or shortcut_manager.get_display_string(sc)
                            
                            if is_this_capturing then
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xCC7A00FF)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
                            else
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x22252BFF)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x64D2FFFF)
                            end
                            reaper.ImGui_Button(ctx, disp_txt .. "##badge_" .. act_id, 200, 24)
                            reaper.ImGui_PopStyleColor(ctx, 2)
                            
                            -- Column 3: "Assign" button
                            reaper.ImGui_SameLine(ctx, 480)
                            if is_this_capturing then
                                if reaper.ImGui_Button(ctx, "Stop##btn_" .. act_id, 70, 24) then
                                    state.capturing_action = nil
                                end
                            else
                                if reaper.ImGui_Button(ctx, "Assign##btn_" .. act_id, 70, 24) then
                                    state.capturing_action = act_id
                                end
                            end
                            
                            -- Column 4: "Delete" (✖) button
                            reaper.ImGui_SameLine(ctx, 560)
                            if reaper.ImGui_Button(ctx, "✖##clr_" .. act_id, 28, 24) then
                                shortcut_manager.clear_shortcut(act_id)
                                shortcut_manager.save()
                                if state.capturing_action == act_id then
                                    state.capturing_action = nil
                                end
                            end
                            if reaper.ImGui_IsItemHovered(ctx) then
                                reaper.ImGui_SetTooltip(ctx, "Remove shortcut")
                            end
                        end
                    end
                end
                
                reaper.ImGui_Spacing(ctx)
            end
            
            reaper.ImGui_EndChild(ctx)
        end
        
        -- ==============================================================
        -- Pinned Bottom Footer (Always visible, outside scroll area)
        -- ==============================================================
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, "Reset to Defaults", 210, 28) then
            shortcut_manager.reset_to_defaults()
            shortcut_manager.save()
            state.capturing_action = nil
            state.status_msg = "All keyboard shortcuts reset to defaults"
        end
        
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Close", -1, 28) then
            state.show_settings = false
            state.capturing_action = nil
        end
    end

    reaper.ImGui_End(ctx)
end

return SettingsModal

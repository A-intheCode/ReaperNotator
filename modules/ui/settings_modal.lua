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
        reaper.ImGui_End(ctx)
        return
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

        local default_open = (reaper.APIExists("ImGui_TreeNodeFlags_DefaultOpen") and reaper.ImGui_TreeNodeFlags_DefaultOpen()) or 0
        local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        local footer_h = 44

        -- Scrollable settings body
        if reaper.ImGui_BeginChild(ctx, "SettingsBodyScroll", 0, avail_h - footer_h, 0) then

            -- ==============================================================
            -- 1. General Settings
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "⚙ General Settings###hdr_general", default_open) then
                reaper.ImGui_Spacing(ctx)
                local sf = state.scroll_factor or 2.0
                local sf_changed, new_sf = reaper.ImGui_SliderDouble(ctx, "Mouse Wheel Scroll Speed", sf, 0.5, 10.0, "%.1fx")
                if sf_changed then state.scroll_factor = new_sf; require('state').save_settings(state) end
                
                local bno_x = state.bar_num_offset_x or 0.0
                local bnox_changed, new_bnox = reaper.ImGui_SliderDouble(ctx, "Bar Numbers X-Offset", bno_x, -25.0, 25.0, "%.1f px")
                if bnox_changed then state.bar_num_offset_x = new_bnox; require('state').save_settings(state) end
                
                local bno_y = state.bar_num_offset_y or 0.0
                local bnoy_changed, new_bnoy = reaper.ImGui_SliderDouble(ctx, "Bar Numbers Y-Offset", bno_y, -50.0, 50.0, "%.1f px")
                if bnoy_changed then state.bar_num_offset_y = new_bnoy; require('state').save_settings(state) end
                
                local rmoy = state.rehearsal_mark_offset_y or 0.0
                local rmoy_changed, new_rmoy = reaper.ImGui_SliderDouble(ctx, "Rehearsal Marks Y-Offset", rmoy, -60.0, 60.0, "%.1f px")
                if rmoy_changed then state.rehearsal_mark_offset_y = new_rmoy; require('state').save_settings(state) end
                
                local bns = state.bar_num_size or 14.0
                local bns_changed, new_bns = reaper.ImGui_SliderDouble(ctx, "Bar Numbers Font Size", bns, 8.0, 32.0, "%.1f px")
                if bns_changed then state.bar_num_size = new_bns; require('state').save_settings(state) end
                
                local doy = state.dynamics_offset_y or 45.0
                local doy_changed, new_doy = reaper.ImGui_SliderDouble(ctx, "Dynamics & Hairpins Vertical Offset", doy, 5.0, 120.0, "%.1f px")
                if doy_changed then
                    state.dynamics_offset_y = new_doy
                    state.hairpins_offset_y = new_doy
                    require('state').save_settings(state)
                end

                local poy = state.pedal_offset_y or 75.0
                local poy_changed, new_poy = reaper.ImGui_SliderDouble(ctx, "Pedal / Sustain Vertical Offset", poy, 10.0, 150.0, "%.1f px")
                if poy_changed then state.pedal_offset_y = new_poy; require('state').save_settings(state) end
                
                local aoy = state.articulations_offset_y or 16.0
                local aoy_changed, new_aoy = reaper.ImGui_SliderDouble(ctx, "Articulations Vertical Offset (Above Staff)", aoy, -20.0, 120.0, "%.1f px")
                if aoy_changed then state.articulations_offset_y = new_aoy; require('state').save_settings(state) end
                
                local ts = state.track_spacing or 70.0
                local ts_changed, new_ts = reaper.ImGui_SliderDouble(ctx, "Track Spacing", ts, -20.0, 250.0, "%.1f px")
                if ts_changed then state.track_spacing = new_ts; require('state').save_settings(state) end
                
                local ib = (state.show_item_boxes ~= false)
                local ib_changed, new_ib = reaper.ImGui_Checkbox(ctx, "Show MIDI Item Bounds & Tags", ib)
                if ib_changed then state.show_item_boxes = new_ib; require('state').save_settings(state) end
                
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
                end
                
                local toy = state.tempo_offset_y or 28.0
                local toy_changed, new_toy = reaper.ImGui_SliderDouble(ctx, "Tempo Markers Vertical Offset (Above Staff)", toy, 5.0, 120.0, "%.1f px")
                if toy_changed then state.tempo_offset_y = new_toy; require('state').save_settings(state) end
                
                local ooy = state.octave_offset_y or 18.0
                local ooy_changed, new_ooy = reaper.ImGui_SliderDouble(ctx, "Octave Lines Vertical Offset (Above Staff)", ooy, 5.0, 100.0, "%.1f px")
                if ooy_changed then state.octave_offset_y = new_ooy; require('state').save_settings(state) end
                
                reaper.ImGui_Spacing(ctx)
            end
            
            reaper.ImGui_Spacing(ctx)

            -- ==============================================================
            -- 2. REAPER User Directory & Paths
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
            -- 5. Customize Keyboard Shortcuts
            -- ==============================================================
            if reaper.ImGui_CollapsingHeader(ctx, "⌨ Customize Keyboard Shortcuts###hdr_shortcuts", default_open) then
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
        
        reaper.ImGui_End(ctx)
    end
end

return SettingsModal

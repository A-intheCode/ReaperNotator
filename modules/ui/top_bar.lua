-- ==============================================================================
-- REAPER Native Notator - Module: TopBar
-- Top toolbar: Transport, time display, layout, tracks, zoom, lock, dynamics, help
-- ==============================================================================

local TopBar = {}

local function toggle_btn(ctx, label, is_active, w, h, active_col)
    local pushed = false
    if is_active then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), active_col or 0xFF9F1CFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFFA726FF)
        pushed = true
    end
    local clicked = reaper.ImGui_Button(ctx, label, w or 0, h or 0)
    if pushed then
        reaper.ImGui_PopStyleColor(ctx, 2)
    end
    return clicked
end

function TopBar.render(ctx, state, clipboard_service, midi_service, active_tracks_data, total_tracks_cnt, child_border, topbar_flags)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 6, 4)
    local open = reaper.ImGui_BeginChild(ctx, "TopBar", 0, 50, child_border, topbar_flags)
    if not open then
        reaper.ImGui_PopStyleVar(ctx)
        return
    end
    reaper.ImGui_SetScrollY(ctx, 0)
    
    local cur_time = reaper.GetCursorPosition()
    local play_time = reaper.GetPlayPosition()
    local is_playing = (reaper.GetPlayState() == 1)
    local time_pos = is_playing and play_time or cur_time
    
    local timesig_num, timesig_denom, bpm = reaper.TimeMap_GetTimeSigAtTime(0, time_pos)
    timesig_num = (timesig_num and timesig_num > 0) and timesig_num or 4
    timesig_denom = (timesig_denom and timesig_denom > 0) and timesig_denom or 4
    bpm = (bpm and bpm > 0) and bpm or 120
    
    -- Title & Version
    reaper.ImGui_BeginGroup(ctx)
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "REAPER Notator")
    local ver_str = state.version or "v1.0.0"
    reaper.ImGui_TextDisabled(ctx, ver_str)
    reaper.ImGui_EndGroup(ctx)
    reaper.ImGui_SameLine(ctx, 0, 14)
    
    -- Transport buttons
    if reaper.ImGui_Button(ctx, "⏮", 32, 28) then
        reaper.SetEditCurPos(0, true, false)
    end
    reaper.ImGui_SameLine(ctx)
    
    local play_text = is_playing and "⏸ Pause" or "▶ Play"
    if toggle_btn(ctx, play_text, is_playing, 75, 28, 0x2ECC71FF) then
        if is_playing then reaper.CSurf_OnStop() else reaper.CSurf_OnPlay() end
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_Button(ctx, "⏹ Stop", 65, 28) then
        reaper.CSurf_OnStop()
    end

    -- Note audio preview toggle (Note Audition / Playback on Click)
    reaper.ImGui_SameLine(ctx, 0, 8)
    local audition_active = (state.audition_notes ~= false)
    local aud_btn_label = audition_active and "✓ 🔊 Preview" or "  🔇 Preview"
    if toggle_btn(ctx, aud_btn_label, audition_active, 102, 28, 0x2980B9FF) then
        state.audition_notes = not audition_active
        require("state").save_settings(state)
        if not state.audition_notes then
            local audio_preview = require("services.audio_preview")
            audio_preview.stop_all(state)
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, audition_active 
            and "Note Audio Preview ACTIVE\nPlays notes when clicking, transposing, moving & drawing.\nClick to mute." 
            or "Note Audio Preview MUTED\nClick to activate.")
    end

    -- Vertical volume slider for note preview (50% = original/dynamics, 100% = max volume 127)
    reaper.ImGui_SameLine(ctx, 0, 4)
    local cur_vol = math.floor(state.audition_volume or 50)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x24272EFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x2F333DFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(), 0x2980B9FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), 0x3498DBFF)
    
    local vol_changed, new_vol = reaper.ImGui_VSliderInt(ctx, "##preview_vol", 16, 28, cur_vol, 0, 100, "")
    reaper.ImGui_PopStyleColor(ctx, 4)
    if vol_changed then
        state.audition_volume = new_vol
        require("state").save_settings(state)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        local desc
        if cur_vol == 50 then
            desc = "50% (Default: Written dynamics & note velocity)"
        elseif cur_vol > 50 then
            local boost_pct = math.floor((cur_vol - 50) * 2)
            desc = string.format("%d%% (+%d%% Boost -> 100%% = Max Volume 127)", cur_vol, boost_pct)
        else
            desc = string.format("%d%% (Attenuated)", cur_vol)
        end
        reaper.ImGui_SetTooltip(ctx, string.format("Preview Volume: %s\nDouble-click = 50%% (Default)", desc))
    end
    if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
        state.audition_volume = 50
        require("state").save_settings(state)
    end

    -- Auto-Scroll Toggle
    reaper.ImGui_SameLine(ctx, 0, 8)
    if toggle_btn(ctx, "Auto-Scroll", state.auto_scroll, 105, 28, 0xE67E22FF) then
        state.auto_scroll = not state.auto_scroll
    end
    
    -- Time display and measure
    reaper.ImGui_SameLine(ctx, 0, 14)
    local minutes = math.floor(time_pos / 60)
    local seconds = time_pos % 60
    local time_str = string.format("%02d:%06.3f", minutes, seconds)
    local qn = reaper.TimeMap2_timeToQN(0, time_pos)
    local bar = math.floor(qn / timesig_num) + 1
    local beat = math.floor(qn % timesig_num) + 1
    local beat_str = string.format("%d.%d.00", bar, beat)
    
    reaper.ImGui_TextColored(ctx, 0x5BC0DEFF, time_str)
    reaper.ImGui_SameLine(ctx, 0, 8)
    reaper.ImGui_TextColored(ctx, 0xF39C12FF, beat_str)
    reaper.ImGui_SameLine(ctx, 0, 10)
    reaper.ImGui_TextColored(ctx, 0xDDDDDDFF, string.format("%.1f BPM  %d/%d", bpm, timesig_num, timesig_denom))
    
    -- Track selection (Track picker modal toggle)
    reaper.ImGui_SameLine(ctx, 0, 14)
    local act_cnt = active_tracks_data and #active_tracks_data or 1
    if toggle_btn(ctx, string.format("🎼 Tracks (%d)", act_cnt), state.show_track_picker, 115, 28, 0x8E44ADFF) then
        state.show_track_picker = not state.show_track_picker
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Tracks Picker: Click to open multi-track selection dialog")
    end
    
    -- View dropdown (show/hide layers and elements)
    reaper.ImGui_SameLine(ctx, 0, 10)
    reaper.ImGui_SetNextItemWidth(ctx, 110)
    if reaper.ImGui_BeginCombo(ctx, "##ViewFilterSelect", "👁 View") then
        local function view_item(label, flag_key)
            local cur_val = (state[flag_key] ~= false)
            local icon = cur_val and "✓ " or "   "
            if reaper.ImGui_Selectable(ctx, icon .. label, cur_val) then
                state[flag_key] = not cur_val
                require("state").save_settings(state)
            end
        end
        
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Elements & Layers:")
        reaper.ImGui_Separator(ctx)
        view_item("Sticky Track Names", "sticky_track_headers")
        view_item("Track Name Badges", "show_track_headers")
        view_item("MIDI Item Boxes", "show_item_boxes")
        view_item("Measure Numbers", "show_bar_numbers")
        view_item("Dynamic Markers", "show_dynamics_layer")
        view_item("Articulations (PC)", "show_articulations_layer")
        view_item("Hairpins (< & >)", "show_hairpins_layer")
        view_item("Text Dynamics (cresc. / dim.)", "show_dynamic_texts_layer")
        view_item("Holding / Sustain (Pedal CC64)", "show_pedal_layer")
        view_item("Tempo Markers", "show_tempo_layer")
        view_item("Octave Lines (8va)", "show_octaves_layer")
        view_item("Tuplets / Triplets (3, 5, ...)", "show_tuplets_layer")
        view_item("Text Items (🔤)", "show_text_items_layer")
        view_item("Chord / Scale Lane", "show_chord_lane")
        view_item("Rehearsal Marks Lane", "show_rehearsal_lane")
        
        
        
        reaper.ImGui_EndCombo(ctx)
    end
    
    -- Voices dropdown (All Notes / Voice 1..16) per instrument track
    local cur_trk = state.focused_track
    if (not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*")) and active_tracks_data and active_tracks_data[1] then
        cur_trk = active_tracks_data[1].track
    end
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        cur_trk = reaper.GetSelectedTrack(0, 0)
    end
    
    local trk_guid = cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") and reaper.GetTrackGUID(cur_trk)
    state.track_voices = state.track_voices or {}
    local cur_v = (trk_guid and state.track_voices[trk_guid]) or 0
    
    local voice_lbl = (cur_v == 0) and "🗣 All Notes" or string.format("🗣 Voice %d", cur_v)
    reaper.ImGui_SameLine(ctx, 0, 8)
    reaper.ImGui_SetNextItemWidth(ctx, 115)
    if reaper.ImGui_BeginCombo(ctx, "##VoiceFilterSelect", voice_lbl) then
        local voice_counts = {}
        if active_tracks_data then
            for _, td in ipairs(active_tracks_data) do
                if td.track == cur_trk or (trk_guid and td.guid == trk_guid) then
                    for _, n in ipairs(td.notes or {}) do
                        local v_idx = (n.chan or 0) + 1
                        voice_counts[v_idx] = (voice_counts[v_idx] or 0) + 1
                    end
                    break
                end
            end
        end
        
        local total_notes = 0
        for _, c in pairs(voice_counts) do total_notes = total_notes + c end
        
        local all_lbl = total_notes > 0 and string.format("All Notes (%d)", total_notes) or "All Notes"
        if reaper.ImGui_Selectable(ctx, all_lbl, cur_v == 0) then
            if trk_guid then state.track_voices[trk_guid] = 0 end
            state.active_voice = 0
            require("state").save_settings(state)
            state.status_msg = "Voice Filter: All Notes"
        end
        
        reaper.ImGui_Separator(ctx)
        
        for v = 1, 16 do
            local cnt = voice_counts[v] or 0
            local item_lbl = (cnt > 0) and string.format("Voice %d (Ch %d) • %d", v, v, cnt) or string.format("Voice %d (Ch %d)", v, v)
            if reaper.ImGui_Selectable(ctx, item_lbl, cur_v == v) then
                if trk_guid then state.track_voices[trk_guid] = v end
                state.active_voice = v
                require("state").save_settings(state)
                state.status_msg = string.format("Voice Filter: Voice %d (MIDI Channel %d)", v, v)
            end
        end
        
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_Selectable(ctx, "⚡ Auto-Voice (Whole Track)") then
            local ms = require("services.midi_service")
            ms.auto_split_overlaps_to_voices(state, cur_trk)
        end
        if reaper.ImGui_Selectable(ctx, "⚡ Auto-Voice on Selection") then
            local ms = require("services.midi_service")
            ms.auto_split_selection_to_voices(state, cur_trk)
        end
        
        local vc_val = (state.voice_color_mode ~= false)
        if reaper.ImGui_Selectable(ctx, (vc_val and "✓ " or "   ") .. "Color by Voice", vc_val) then
            state.voice_color_mode = not vc_val
            require("state").save_settings(state)
        end
        
        local hi_val = (state.hide_inactive_voices == true)
        if reaper.ImGui_Selectable(ctx, (hi_val and "✓ " or "   ") .. "Hide Inactive Voices", hi_val) then
            state.hide_inactive_voices = not hi_val
            require("state").save_settings(state)
        end
        
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Ghost Notes Opacity:")
        reaper.ImGui_SetNextItemWidth(ctx, 130)
        local cur_op = math.floor(((state.ghost_voice_opacity or 0.25) * 100) + 0.5)
        local op_chg, new_op = reaper.ImGui_SliderInt(ctx, "##ghost_op_drop", cur_op, 5, 100, "%d%%")
        if op_chg then
            state.ghost_voice_opacity = new_op / 100.0
            require("state").save_settings(state)
        end
        
        reaper.ImGui_EndCombo(ctx)
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        local trk_name = "Track"
        if cur_trk then
            local _, nm = reaper.GetTrackName(cur_trk)
            if nm and nm ~= "" then trk_name = nm end
        end
        reaper.ImGui_SetTooltip(ctx, string.format("Voice Filter & Active Note Channel\nTrack: %s\nSelect 'All Notes' or Voice 1..16\nRight-click notes to assign voice.", trk_name))
    end
    
    -- Horizontal scroll zone for all additional tools & buttons behind the layout dropdown
    reaper.ImGui_SameLine(ctx, 0, 10)
    local parent_avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local dq_extra = (state.display_quantize and (3 + 52) or 0)
    local total_needed_w = 105 + dq_extra + 6 + 88 + 8 + 78 + 6 + 78 + 6 + 110 + 6 + 95 + 6 + 86 + 6 + 26 + 6 + 26 + 6 + 26 + 10
    local needs_scroll = (parent_avail_w < total_needed_w)

    local scroll_flags = reaper.ImGui_WindowFlags_NoScrollbar()
    if needs_scroll then
        scroll_flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()
        if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
            scroll_flags = scroll_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        end
    end

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 0, 0)
    if reaper.ImGui_BeginChild(ctx, "TopBarToolsScroll", 0, 44, 0, scroll_flags) then
        reaper.ImGui_SetScrollY(ctx, 0)
        -- Right-align buttons when enough space is available so settings sits against the right edge
        if not needs_scroll then
            state._topbar_user_scrolled = false
            local inside_avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
            if inside_avail_w > total_needed_w then
                reaper.ImGui_SetCursorPosX(ctx, inside_avail_w - total_needed_w)
            end
        end
        
        -- Display Quantize Toggle
        if toggle_btn(ctx, "D-Quantize", state.display_quantize, 105, 26, 0x9B59B6FF) then
            state.display_quantize = not state.display_quantize
            state.status_msg = state.display_quantize and "Display Quantize ON – notes visually snap to grid" or "Display Quantize OFF"
        end
        -- Display Quantize grid selection (only visible when active)
        if state.display_quantize then
            reaper.ImGui_SameLine(ctx, 0, 3)
            reaper.ImGui_PushItemWidth(ctx, 52)
            if reaper.ImGui_BeginCombo(ctx, "##dq_grid", state.display_quantize_label, reaper.ImGui_ComboFlags_NoArrowButton()) then
                local grids = {
                    { "1/1",  4.0 },
                    { "1/2",  2.0 },
                    { "1/4",  1.0 },
                    { "1/8",  0.5 },
                    { "1/16", 0.25 },
                    { "1/32", 0.125 },
                }
                for _, g in ipairs(grids) do
                    local is_sel = (math.abs(state.display_quantize_grid - g[2]) < 0.001)
                    if reaper.ImGui_Selectable(ctx, g[1], is_sel) then
                        state.display_quantize_grid = g[2]
                        state.display_quantize_label = g[1]
                        state.status_msg = "D-Quantize Grid: " .. g[1]
                    end
                end
                reaper.ImGui_EndCombo(ctx)
            end
            reaper.ImGui_PopItemWidth(ctx)
        end
        
        -- Tools Drawer Toggle (Contains Make Notes Legato, Auto Voice, Arpeggio Chords, Quantize Tools, Rehearsal Marks & Navigation)
        reaper.ImGui_SameLine(ctx, 0, 6)
        if toggle_btn(ctx, "🛠 Tools", state.show_tools_drawer, 88, 26, 0x8E44ADFF) then
            state.show_tools_drawer = not state.show_tools_drawer
            if state.show_tools_drawer then
                state.show_clefs = false
                state.show_dynamics = false
                state.show_tempo = false
                state.show_articulations_drawer = false
                state.show_key_signatures = false
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Score Tools & Navigation:\nLegato, Auto Voice, Quantize, Arpeggios, and Rehearsal & Navigation Marks ([A], [1], D.C., D.S., Coda, Fine).")
        end
        
        -- Clefs Drawer Toggle
        reaper.ImGui_SameLine(ctx, 0, 8)
        if toggle_btn(ctx, "𝄞 Clefs", state.show_clefs, 78, 26, 0x3498DBFF) then
            state.show_clefs = not state.show_clefs
            if state.show_clefs then
                state.show_dynamics = false
                state.show_tempo = false
                state.show_articulations_drawer = false
                state.show_key_signatures = false
                state.show_tools_drawer = false
            end
        end

        -- Key & Time Signature Drawer Toggle
        reaper.ImGui_SameLine(ctx, 0, 6)
        if toggle_btn(ctx, "♯♭ Keys", state.show_key_signatures, 78, 26, 0x16A085FF) then
            state.show_key_signatures = not state.show_key_signatures
            if state.show_key_signatures then
                state.show_clefs = false
                state.show_dynamics = false
                state.show_tempo = false
                state.show_articulations_drawer = false
                state.show_tools_drawer = false
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Key & Time Signature Drawer:\nBrowse and set key signatures (7♭ to 7♯) and time signatures per MIDI item, track or project.")
        end

        -- Articulation Drawer Toggle (strictly no icon prefix!)
        reaper.ImGui_SameLine(ctx, 0, 6)
        if toggle_btn(ctx, "Articulation (L)", state.show_articulations_drawer, 110, 26, 0x9B59B6FF) then
            state.show_articulations_drawer = not state.show_articulations_drawer
            if state.show_articulations_drawer then
                state.show_clefs = false
                state.show_dynamics = false
                state.show_tempo = false
                state.show_key_signatures = false
                state.show_tools_drawer = false
                local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
                ReaticulateParser.reload_all_banks()
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Articulation Drawer (L):\nBrowse and assign Reaticulate bank articulations to notes or cursor.")
        end

        -- Dynamics Drawer Toggle
        reaper.ImGui_SameLine(ctx, 0, 6)
        if toggle_btn(ctx, "Dynamics (D)", state.show_dynamics, 95, 26, 0x27AE60FF) then
            state.show_dynamics = not state.show_dynamics
            if state.show_dynamics then
                state.show_tempo = false
                state.show_clefs = false
                state.show_articulations_drawer = false
                state.show_key_signatures = false
                state.show_tools_drawer = false
            end
        end
        
        -- Tempo Drawer Toggle
        reaper.ImGui_SameLine(ctx, 0, 6)
        if toggle_btn(ctx, "⏱ Tempo (T)", state.show_tempo, 86, 26, 0xF39C12FF) then
            state.show_tempo = not state.show_tempo
            if state.show_tempo then
                state.show_dynamics = false
                state.show_clefs = false
                state.show_articulations_drawer = false
                state.show_key_signatures = false
                state.show_tools_drawer = false
            end
        end
        
        -- Help Button
        reaper.ImGui_SameLine(ctx, 0, 6)
        if reaper.ImGui_Button(ctx, "?##HelpBtn", 26, 26) then
            state.show_help = not state.show_help
        end
        
        -- Settings Button
        reaper.ImGui_SameLine(ctx, 0, 6)
        if reaper.ImGui_Button(ctx, "⚙##SettingsBtn", 26, 26) then
            state.show_settings = not state.show_settings
        end
        
        -- Maximize / Restore Button
        reaper.ImGui_SameLine(ctx, 0, 6)
        local max_icon = state.is_maximized and "🗗##TopMaxBtn" or "🗖##TopMaxBtn"
        if reaper.ImGui_Button(ctx, max_icon, 26, 26) then
            state.request_maximize_toggle = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, state.is_maximized and "Restore window (F11)" or "Maximize window (F11)")
        end
        
        -- Horizontal scrolling via mouse wheel and scroll state management
        reaper.ImGui_SetScrollY(ctx, 0)
        if needs_scroll then
            local max_scroll_x = reaper.ImGui_GetScrollMaxX(ctx)
            local cur_scroll_x = reaper.ImGui_GetScrollX(ctx)

            if reaper.ImGui_IsWindowHovered(ctx) then
                local wh_y = reaper.ImGui_GetMouseWheel(ctx)
                local wh_x = reaper.APIExists("ImGui_GetMouseWheelH") and reaper.ImGui_GetMouseWheelH(ctx) or 0
                if wh_x ~= 0 or wh_y ~= 0 then
                    local s_amt = (wh_x ~= 0) and wh_x or wh_y
                    cur_scroll_x = cur_scroll_x - (s_amt * 40)
                    reaper.ImGui_SetScrollX(ctx, cur_scroll_x)
                    if cur_scroll_x < (max_scroll_x - 5) then
                        state._topbar_user_scrolled = true
                    else
                        state._topbar_user_scrolled = false
                    end
                end
            end

            -- If user scrolled back near the right edge, re-enable sticky right alignment
            if cur_scroll_x >= (max_scroll_x - 3) then
                state._topbar_user_scrolled = false
            elseif cur_scroll_x < (max_scroll_x - 10) and state._topbar_last_max_x == max_scroll_x then
                state._topbar_user_scrolled = true
            end

            -- Default to scrolled all the way to the right so settings/tools are visible
            if not state._topbar_user_scrolled and max_scroll_x > 0 then
                reaper.ImGui_SetScrollX(ctx, max_scroll_x)
            end

            state._topbar_last_max_x = max_scroll_x
        end

        reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_PopStyleVar(ctx) -- Pop TopBarToolsScroll padding
    
    reaper.ImGui_SetScrollY(ctx, 0)
    reaper.ImGui_EndChild(ctx)
    reaper.ImGui_PopStyleVar(ctx) -- Pop TopBar padding
end

return TopBar

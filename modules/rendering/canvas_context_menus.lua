-- ==============================================================================
-- REAPER Native Notator - Module: CanvasContextMenus
-- Extracted context menus (right-click popups) for the score canvas:
-- 1. Chord / Scale Lane (chord_lane_context_popup)
-- 2. Text Dynamics (dynamic_text_context_popup)
-- 3. Sustain Pedal (pedal_context_popup)
-- 4. Note Actions & Selection (NoteContextMenu)
-- 5. MIDI Item Header & Time Sig (item_header_context_popup)
-- 6. Floating Text Item (text_item_context_popup)
-- 7. Repeat Mark % (repeat_mark_context_popup)
-- 8. Measure Header (measure_header_context_popup)
-- 9. Dynamic Marker (dynamic_context_popup)
-- 10. Hairpins (hairpin_context_popup)
-- 11. Tempo Marker (tempo_context_popup)
-- 12. Articulation / PC (articulation_context_popup)
-- 13. Octave Line (octave_context_popup)
-- ==============================================================================

local CanvasContextMenus = {}

local function get_service(path)
    return package.loaded[path] or require(path)
end

local function get_qn_per_measure(state, qn_per_measure)
    if qn_per_measure and qn_per_measure > 0 then
        return qn_per_measure
    end
    local cur_time = reaper.GetCursorPosition()
    local play_time = reaper.GetPlayPosition()
    local is_playing = (reaper.GetPlayState() == 1)
    local time_pos = is_playing and play_time or cur_time
    local timesig_num, timesig_denom = reaper.TimeMap_GetTimeSigAtTime(0, time_pos)
    timesig_num = (timesig_num and timesig_num > 0) and timesig_num or 4
    timesig_denom = (timesig_denom and timesig_denom > 0) and timesig_denom or 4
    return timesig_num * (4 / timesig_denom)
end

local function resolve_effective_time_sig(state, track, item, qn)
    local has_kss, KeySignatureService = pcall(require, "services.key_signature_service")
    if not has_kss or not KeySignatureService then
        has_kss, KeySignatureService = pcall(require, "modules.services.key_signature_service")
    end
    if has_kss and KeySignatureService and KeySignatureService.resolve_effective_time_sig then
        local res = KeySignatureService.resolve_effective_time_sig(state, track, item, qn)
        if res and res.num and res.denom then
            return res.num, res.denom
        end
    end
    if item then
        if item.time_sig and item.time_sig.num and item.time_sig.denom then
            return item.time_sig.num, item.time_sig.denom
        end
        if item.item and reaper.ValidatePtr(item.item, "MediaItem*") then
            local ok, str = reaper.GetSetMediaItemInfo_String(item.item, "P_EXT:notator_time_sig", "", false)
            if ok and str and str ~= "" then
                local num, den = str:match("([^|]+)|([^|]+)")
                if num and den then return tonumber(num) or 4, tonumber(den) or 4 end
            end
        end
    end
    return 4, 4
end

local CHORD_MENU_SCALES = {
    { name = "Major / Ionian", suffix = "Major", scale_type = "major" },
    { name = "Dorian (Minor)", suffix = "Dorian", scale_type = "dorian" },
    { name = "Phrygian (Spanish Minor)", suffix = "Phrygian", scale_type = "phrygian" },
    { name = "Lydian (#4)", suffix = "Lydian", scale_type = "lydian" },
    { name = "Mixolydian (Dominant 7th)", suffix = "Mixolydian", scale_type = "mixolydian" },
    { name = "Natural Minor / Aeolian", suffix = "Minor", scale_type = "minor" },
    { name = "Locrian (Half-Diminished)", suffix = "Locrian", scale_type = "locrian" },
    { name = "Harmonic Minor", suffix = "Harmonic Minor", scale_type = "harmonic_minor" },
    { name = "Melodic Minor (Jazz)", suffix = "Melodic Minor", scale_type = "melodic_minor" },
    { name = "Blues Scale", suffix = "Blues", scale_type = "blues" },
    { name = "Major Pentatonic", suffix = "Major Pentatonic", scale_type = "pentatonic_maj" },
    { name = "Minor Pentatonic", suffix = "Minor Pentatonic", scale_type = "pentatonic_min" },
    { name = "Whole Tone", suffix = "Whole Tone", scale_type = "whole_tone" },
}

-- ==============================================================================
-- 1. CHORD / SCALE LANE POPUP
-- ==============================================================================
function CanvasContextMenus.render_chord_lane_popup(ctx, state, qn_per_measure)
    if reaper.ImGui_BeginPopup(ctx, "chord_lane_context_popup") then
        local ScaleService = package.loaded["services.scale_service"] or require("services.scale_service")
        local qn_pm = get_qn_per_measure(state, qn_per_measure)
        local ci = state.context_chord_item
        if ci then
            reaper.ImGui_TextColored(ctx, 0x5BC0DEFF, string.format("🎵 Chord Item: %s", ci.text))
            reaper.ImGui_TextDisabled(ctx, string.format("Measure %.2f - %.2f (%.1f QN)", (ci.start_qn / qn_pm) + 1, (ci.end_qn / qn_pm) + 1, ci.end_qn - ci.start_qn))
            reaper.ImGui_Separator(ctx)

            if reaper.ImGui_MenuItem(ctx, "✏ Edit Chord / Scale Text...") then
                state.editing_chord_item = ci
                state.editing_chord_str = ci.text
                state.editing_chord_just_opened = true
            end

            if reaper.ImGui_BeginMenu(ctx, "🎼 Change Scale / Mode...") then
                local cur_root = ScaleService.ROOT_NAMES[(ci.root or 0) + 1] or "C"
                for _, sc in ipairs(CHORD_MENU_SCALES) do
                    local is_cur = (ci.scale_type == sc.scale_type)
                    local prefix = is_cur and "✓ " or "   "
                    local sc_label = string.format("%s%s %s", prefix, cur_root, sc.name)
                    local new_chord_txt = string.format("%s %s", cur_root, sc.suffix)
                    if reaper.ImGui_MenuItem(ctx, sc_label) then
                        ScaleService.update_chord_text(state, ci.id, new_chord_txt)
                        state.status_msg = string.format("Set chord to %s", new_chord_txt)
                    end
                end
                reaper.ImGui_EndMenu(ctx)
            end

            if reaper.ImGui_MenuItem(ctx, "🔄 Transpose Target Tracks Now") then
                ScaleService.apply_chord_item_to_target_tracks(state, ci)
                state.status_msg = string.format("Transposed target tracks to %s", ci.text)
            end

            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_MenuItem(ctx, "🗑 Delete Item (Revert Notes to Original)") then
                ScaleService.delete_chord_item(state, ci.id, true)
                state.selected_chord_item = nil
                state.context_chord_item = nil
            end
            if reaper.ImGui_MenuItem(ctx, "🗑 Delete Item (Keep Transposed Pitches)") then
                ScaleService.delete_chord_item(state, ci.id, false)
                state.selected_chord_item = nil
                state.context_chord_item = nil
            end
        else
            local click_m = state.context_chord_qn and (math.floor(state.context_chord_qn / qn_pm) + 1) or 1
            reaper.ImGui_TextColored(ctx, 0x5BC0DEFF, string.format("🎵 Chord / Scale Lane (Bar %d)", click_m))
            reaper.ImGui_Separator(ctx)

            local qn = state.context_chord_qn or 0.0
            if reaper.ImGui_MenuItem(ctx, string.format("➕ Insert Chord Block 'C' (Bar %d)", click_m)) then
                ScaleService.create_chord_item(state, qn, qn + qn_pm, "C")
            end
            if reaper.ImGui_MenuItem(ctx, string.format("➕ Insert Chord Block 'Am' (Bar %d)", click_m)) then
                ScaleService.create_chord_item(state, qn, qn + qn_pm, "Am")
            end
            if reaper.ImGui_MenuItem(ctx, string.format("➕ Insert Chord Block 'G7' (Bar %d)", click_m)) then
                ScaleService.create_chord_item(state, qn, qn + qn_pm, "G7")
            end
            if reaper.ImGui_MenuItem(ctx, string.format("➕ Insert Chord Block 'F' (Bar %d)", click_m)) then
                ScaleService.create_chord_item(state, qn, qn + qn_pm, "F")
            end
            if reaper.ImGui_MenuItem(ctx, string.format("➕ Insert Chord Block 'Dm' (Bar %d)", click_m)) then
                ScaleService.create_chord_item(state, qn, qn + qn_pm, "Dm")
            end

            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_BeginMenu(ctx, string.format("🎼 Insert Scale (Default C)... (Bar %d)", click_m)) then
                for _, sc in ipairs(CHORD_MENU_SCALES) do
                    local sc_label = string.format("C %s", sc.name)
                    local new_chord_txt = string.format("C %s", sc.suffix)
                    if reaper.ImGui_MenuItem(ctx, sc_label) then
                        ScaleService.create_chord_item(state, qn, qn + qn_pm, new_chord_txt)
                        state.status_msg = string.format("Created Scale Block '%s' at Bar %d", new_chord_txt, click_m)
                    end
                end
                reaper.ImGui_EndMenu(ctx)
            end

            if reaper.ImGui_BeginMenu(ctx, string.format("🎼 Insert Scale with Custom Root... (Bar %d)", click_m)) then
                local root_list = { "C", "D", "E", "F", "G", "A", "B", "C# / Db", "Eb", "F#", "Ab", "Bb" }
                local root_keys = { "C", "D", "E", "F", "G", "A", "B", "C#", "Eb", "F#", "Ab", "Bb" }
                for r_i, r_name in ipairs(root_list) do
                    local r_code = root_keys[r_i]
                    if reaper.ImGui_BeginMenu(ctx, r_name .. " ...") then
                        for _, sc in ipairs(CHORD_MENU_SCALES) do
                            local sc_label = string.format("%s %s", r_code, sc.name)
                            local new_chord_txt = string.format("%s %s", r_code, sc.suffix)
                            if reaper.ImGui_MenuItem(ctx, sc_label) then
                                ScaleService.create_chord_item(state, qn, qn + qn_pm, new_chord_txt)
                                state.status_msg = string.format("Created Scale Block '%s' at Bar %d", new_chord_txt, click_m)
                            end
                        end
                        reaper.ImGui_EndMenu(ctx)
                    end
                end
                reaper.ImGui_EndMenu(ctx)
            end
        end

        reaper.ImGui_Separator(ctx)
        local test_m = ci and (math.floor(ci.start_qn / qn_pm) + 1) or (state.context_chord_qn and (math.floor(state.context_chord_qn / qn_pm) + 1) or 1)
        if reaper.ImGui_MenuItem(ctx, string.format("🧪 Insert Test MIDI Item (Bars %d-%d)", test_m, test_m + 3)) then
            ScaleService.insert_test_midi_case(state, test_m)
        end

        reaper.ImGui_Separator(ctx)

        -- Target Tracks Submenu
        local has_begin_menu = reaper.APIExists("ImGui_BeginMenu")
        local open_target_menu = false
        if has_begin_menu then
            open_target_menu = reaper.ImGui_BeginMenu(ctx, "🎯 Target Tracks (Effect Scope)...")
        end

        if open_target_menu then
            reaper.ImGui_TextDisabled(ctx, "Applies to selected tracks even when hidden in Notator:")
            reaper.ImGui_Spacing(ctx)
            if reaper.ImGui_MenuItem(ctx, "✓ Select All Project Tracks") then
                ScaleService.set_all_tracks_targeted(state, true)
            end
            if reaper.ImGui_MenuItem(ctx, "✕ Deselect All Tracks") then
                ScaleService.set_all_tracks_targeted(state, false)
            end
            reaper.ImGui_Separator(ctx)
            local trk_count = reaper.CountTracks(0)
            for i = 0, trk_count - 1 do
                local trk = reaper.GetTrack(0, i)
                if trk then
                    local guid = reaper.GetTrackGUID(trk)
                    local _, trk_name = reaper.GetTrackName(trk)
                    if not trk_name or trk_name == "" then trk_name = "Track " .. (i + 1) end
                    local is_tar = ScaleService.is_track_targeted(state, guid)
                    local prefix = is_tar and "✓ " or "   "
                    if reaper.ImGui_MenuItem(ctx, string.format("%s%d: %s", prefix, i + 1, trk_name)) then
                        ScaleService.set_track_targeted(state, guid, not is_tar)
                        if not is_tar and state.chord_items then
                            for _, ci_app in ipairs(state.chord_items) do
                                ScaleService.apply_chord_item_to_target_tracks(state, ci_app)
                            end
                        end
                    end
                end
            end
            reaper.ImGui_EndMenu(ctx)
        end

        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_MenuItem(ctx, "🗑 Clear All Chords (Revert Notes to Original)") then
            ScaleService.clear_all_chord_items(state, true)
        end
        if reaper.ImGui_MenuItem(ctx, "🗑 Clear All Chords (Keep Transposed Pitches)") then
            ScaleService.clear_all_chord_items(state, false)
        end

        reaper.ImGui_Separator(ctx)
        local show_lane_val = (state.show_chord_lane ~= false)
        local lane_lbl = (show_lane_val and "✓ " or "   ") .. "Show Chord / Scale Lane"
        if reaper.ImGui_MenuItem(ctx, lane_lbl) then
            state.show_chord_lane = not show_lane_val
            local StateModule = package.loaded["state"] or require("state")
            StateModule.save_settings(state)
        end

        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 2. DYNAMIC TEXT POPUP (cresc. / dim. pattern options)
-- ==============================================================================
function CanvasContextMenus.render_dynamic_text_popup(ctx, state, midi_service, active_tracks_data)
    if reaper.ImGui_BeginPopup(ctx, "dynamic_text_context_popup") then
        local dt = state.context_dynamic_text or state.selected_dynamic_text
        if dt then
            local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
            local dur_qn = dt.end_qn - dt.start_qn
            local title = string.format("𝄢 Text Dynamics: %s  (%.1f QN)", dt.text or dt.type, dur_qn)
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, title)
            reaper.ImGui_Separator(ctx)
            
            -- 1. TEXT PATTERN (Wording)
            local has_menu = reaper.APIExists("ImGui_BeginMenu")
            local open_text_menu = false
            if has_menu then
                open_text_menu = reaper.ImGui_BeginMenu(ctx, "📝 Text Pattern (Wording)...")
            else
                reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "📝 Text Pattern:")
                open_text_menu = true
            end
            
            if open_text_menu then
                local text_templates = {
                    { cresc = "cresc.",            dim = "dim.",              label = "Standard (cresc. / dim.)" },
                    { cresc = "crescendo",         dim = "diminuendo",         label = "Full text (crescendo / diminuendo)" },
                    { cresc = "poco a poco cresc.",dim = "poco a poco dim.",  label = "Poco a poco" },
                    { cresc = "sempre cresc.",     dim = "sempre dim.",       label = "Sempre" },
                    { cresc = "cresc.",            dim = "decresc.",          label = "Decrescendo (decresc.)" },
                }
                for _, tmpl in ipairs(text_templates) do
                    local choice_txt = (dt.type == "crescendo") and tmpl.cresc or tmpl.dim
                    local is_sel = (dt.text == choice_txt)
                    if reaper.ImGui_MenuItem(ctx, choice_txt .. " (" .. tmpl.label .. ")", nil, is_sel) then
                        dt.text = choice_txt
                        if choice_txt:lower():match("dim") or choice_txt:lower():match("decresc") then
                            dt.type = "diminuendo"
                        else
                            dt.type = "crescendo"
                        end
                        DynamicTextService.save_dynamic_texts(state)
                        DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data)
                        state.status_msg = string.format("Text pattern changed: '%s'", dt.text)
                    end
                end
                
                reaper.ImGui_Separator(ctx)
                if dt.type == "crescendo" then
                    if reaper.ImGui_MenuItem(ctx, "⇄ Switch to 'dim.' (Diminuendo)") then
                        dt.type = "diminuendo"
                        dt.text = "dim."
                        DynamicTextService.save_dynamic_texts(state)
                        DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data)
                        state.status_msg = "Direction changed to Diminuendo"
                    end
                else
                    if reaper.ImGui_MenuItem(ctx, "⇄ Switch to 'cresc.' (Crescendo)") then
                        dt.type = "crescendo"
                        dt.text = "cresc."
                        DynamicTextService.save_dynamic_texts(state)
                        DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data)
                        state.status_msg = "Direction changed to Crescendo"
                    end
                end
                
                if has_menu then reaper.ImGui_EndMenu(ctx) end
            end
            
            -- 2. LINE PATTERN
            local open_line_menu = false
            if has_menu then
                open_line_menu = reaper.ImGui_BeginMenu(ctx, "📏 Line Pattern...")
            else
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "📏 Line Pattern:")
                open_line_menu = true
            end
            
            if open_line_menu then
                local line_options = {
                    { id = "none",   label = "None (Text only)" },
                    { id = "dashed", label = "Dashed ( - - - - | )" },
                    { id = "dotted", label = "Dotted ( · · · · )" },
                }
                for _, lo in ipairs(line_options) do
                    local is_sel = ((dt.line_pattern or "none") == lo.id)
                    if reaper.ImGui_MenuItem(ctx, lo.label, nil, is_sel) then
                        dt.line_pattern = lo.id
                        DynamicTextService.save_dynamic_texts(state)
                        state.status_msg = string.format("Line pattern changed: %s", lo.label)
                    end
                end
                if has_menu then reaper.ImGui_EndMenu(ctx) end
            end
            
            -- 3. CC CURVE PATTERN
            local open_curve_menu = false
            if has_menu then
                open_curve_menu = reaper.ImGui_BeginMenu(ctx, "📈 CC Curve Pattern...")
            else
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "📈 CC Curve Pattern:")
                open_curve_menu = true
            end
            
            if open_curve_menu then
                local curve_options = {
                    { id = "linear",      label = "Linear (Constant slope)" },
                    { id = "exponential", label = "Exponential (Progressive)" },
                    { id = "s_curve",     label = "S-Curve (Smooth ease in/out)" },
                }
                for _, co in ipairs(curve_options) do
                    local is_sel = ((dt.curve_pattern or "linear") == co.id)
                    if reaper.ImGui_MenuItem(ctx, co.label, nil, is_sel) then
                        dt.curve_pattern = co.id
                        DynamicTextService.save_dynamic_texts(state)
                        DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data)
                        state.status_msg = string.format("CC curve changed: %s", co.label)
                    end
                end
                if has_menu then reaper.ImGui_EndMenu(ctx) end
            end
            
            -- 4. QUICK ACTIONS / LENGTH
            reaper.ImGui_Separator(ctx)
            if dur_qn > 1.0 and reaper.ImGui_MenuItem(ctx, "➖ Shorten length (-1 QN)") then
                DynamicTextService.resize_dynamic_text(state, dt.id, dt.start_qn, math.max(dt.start_qn + 0.25, dt.end_qn - 1.0), midi_service, active_tracks_data)
            end
            if reaper.ImGui_MenuItem(ctx, "➕ Extend length (+1 QN)") then
                DynamicTextService.resize_dynamic_text(state, dt.id, dt.start_qn, dt.end_qn + 1.0, midi_service, active_tracks_data)
            end
            
            reaper.ImGui_Separator(ctx)
            local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
            SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
            -- 5. DELETE
            if reaper.ImGui_MenuItem(ctx, "🗑 Delete Text Dynamic") then
                DynamicTextService.delete_dynamic_text(state, dt.id, midi_service, active_tracks_data)
                state.context_dynamic_text = nil
                state.selected_dynamic_text = nil
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 3. SUSTAIN PEDAL POPUP
-- ==============================================================================
function CanvasContextMenus.render_pedal_popup(ctx, state, midi_service, active_tracks_data)
    if reaper.ImGui_BeginPopup(ctx, "pedal_context_popup") then
        local pm = state.context_pedal or state.selected_pedal
        if pm then
            local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
            local dur_qn = pm.end_qn - pm.start_qn
            local title = string.format("🎹 Sustain / Pedal (CC64): %.1f QN", dur_qn)
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, title)
            reaper.ImGui_Separator(ctx)
            
            -- 1. INSERT BREAK / RETAKE HERE
            local click_qn = state.context_pedal_click_qn
            if click_qn and click_qn > pm.start_qn + 0.1 and click_qn < pm.end_qn - 0.1 then
                if reaper.ImGui_MenuItem(ctx, string.format("✦ Insert sustain break/retake at measure %.2f", (click_qn / 4) + 1)) then
                    PedalService.add_pause_point(state, pm, click_qn, "asterisk", midi_service, active_tracks_data)
                end
                reaper.ImGui_Separator(ctx)
            end
            
            -- If clicked on existing break/retake:
            if state.context_pedal_pause_id then
                if reaper.ImGui_MenuItem(ctx, "🗑 Remove selected break") then
                    PedalService.remove_pause_point(state, pm, state.context_pedal_pause_id, midi_service, active_tracks_data)
                    state.context_pedal_pause_id = nil
                end
                reaper.ImGui_Separator(ctx)
            end
            
            -- 2. BREAK / RETAKE SYMBOL STYLE (for all breaks of this pedal)
            local has_menu = reaper.APIExists("ImGui_BeginMenu")
            local open_pause_menu = false
            if has_menu then
                open_pause_menu = reaper.ImGui_BeginMenu(ctx, "✽ Break / Retake Symbol Style...")
            else
                reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "✽ Break / Retake Symbol Style:")
                open_pause_menu = true
            end
            if open_pause_menu then
                local pause_types = {
                    { id = "asterisk", label = "Classic Asterisk (*)" },
                    { id = "notch",    label = "Notch / Retake (/\\)" },
                    { id = "retake",   label = "Asterisk + Ped. (* Ped.)" },
                }
                for _, pt in ipairs(pause_types) do
                    if reaper.ImGui_MenuItem(ctx, pt.label) then
                        for _, p in ipairs(pm.pauses or {}) do
                            p.type = pt.id
                        end
                        PedalService.save_pedals(state)
                        state.status_msg = string.format("Pedal break symbol changed: %s", pt.label)
                    end
                end
                if has_menu then reaper.ImGui_EndMenu(ctx) end
            end
            
            -- 3. PEDAL LINE STYLE
            local open_style_menu = false
            if has_menu then
                open_style_menu = reaper.ImGui_BeginMenu(ctx, "📐 Pedal Line Style...")
            else
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_TextColored(ctx, 0x88AAAAFF, "📐 Pedal Line Style:")
                open_style_menu = true
            end
            if open_style_menu then
                local styles = {
                    { id = "classic", label = "Classic (Ped. ──── *)" },
                    { id = "bracket", label = "Bracket (| ──── |)" },
                    { id = "mixed",   label = "Mixed (Ped. ──── |)" },
                }
                for _, st in ipairs(styles) do
                    local is_sel = (pm.style == st.id)
                    if reaper.ImGui_MenuItem(ctx, st.label, nil, is_sel) then
                        pm.style = st.id
                        PedalService.save_pedals(state)
                        state.status_msg = string.format("Pedal style changed: %s", st.label)
                    end
                end
                if has_menu then reaper.ImGui_EndMenu(ctx) end
            end
            
            -- 4. CC64 AUTOMATION
            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_MenuItem(ctx, "🎹 Write CC64 to REAPER", nil, pm.apply_cc) then
                pm.apply_cc = not pm.apply_cc
                PedalService.save_pedals(state)
                if pm.apply_cc then
                    PedalService.apply_cc(state, pm, midi_service, active_tracks_data)
                end
            end
            if reaper.ImGui_MenuItem(ctx, "🧹 Clean & Resync Pedal CC64") then
                PedalService.resync_track_cc(state, pm.track_guid, midi_service, active_tracks_data)
            end
            
            -- 5. QUICK ACTIONS / LENGTH
            reaper.ImGui_Separator(ctx)
            if dur_qn > 1.0 and reaper.ImGui_MenuItem(ctx, "➖ Shorten length (-1 QN)") then
                PedalService.resize_pedal(state, pm.id, pm.start_qn, math.max(pm.start_qn + 0.25, pm.end_qn - 1.0), midi_service, active_tracks_data)
            end
            if reaper.ImGui_MenuItem(ctx, "➕ Extend length (+1 QN)") then
                PedalService.resize_pedal(state, pm.id, pm.start_qn, pm.end_qn + 1.0, midi_service, active_tracks_data)
            end
            
            -- 6. DELETE
            reaper.ImGui_Separator(ctx)
            local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
            SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
            if reaper.ImGui_MenuItem(ctx, "🗑 Delete Sustain Marking") then
                PedalService.delete_pedal(state, pm.id, midi_service, active_tracks_data)
                state.context_pedal = nil
                state.selected_pedal = nil
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 4. NOTE CONTEXT MENU
-- ==============================================================================
function CanvasContextMenus.render_note_context_menu(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    if reaper.ImGui_BeginPopup(ctx, "NoteContextMenu") then
        local cnt = state.count_selected_notes and state:count_selected_notes() or 0
        if cnt > 0 then
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, string.format("Note Actions (%d selected)", cnt))
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_MenuItem(ctx, "⚡ Quantize... (Q)") then
                state.show_quantize_modal = true
            end
            
            local cur_grid_lbl = state.quantize_grid_label or "1/16"
            if reaper.ImGui_MenuItem(ctx, string.format("⚡ Quick Quantize (%s)", cur_grid_lbl)) then
                if midi_service and midi_service.quantize_notes then
                    midi_service.quantize_notes(state)
                end
            end
            
            if reaper.ImGui_MenuItem(ctx, "Make Notes Legato") then
                if midi_service and midi_service.make_legato then
                    midi_service.make_legato(state)
                end
            end
            
            if reaper.ImGui_BeginMenu(ctx, "↕ Stem Direction") then
                local cur_stem_dir = nil
                local sn = state.selected_note
                if not sn and state.selected_notes then
                    for _, n in pairs(state.selected_notes) do sn = n break end
                end
                if sn then
                    local k = (sn.get_key and sn:get_key()) or sn.key
                    cur_stem_dir = sn.stem_dir or (state.note_stem_directions and k and state.note_stem_directions[k])
                end
                
                if reaper.ImGui_MenuItem(ctx, "↕ Invert / Flip Stems (X)") then
                    if midi_service and midi_service.invert_selected_notes_stem_direction then
                        midi_service.invert_selected_notes_stem_direction(state, "invert")
                    end
                end
                reaper.ImGui_Separator(ctx)
                
                local p_up = (cur_stem_dir == "up") and "✓ " or "   "
                if reaper.ImGui_MenuItem(ctx, p_up .. "↑ Force Stem Up") then
                    if midi_service and midi_service.invert_selected_notes_stem_direction then
                        midi_service.invert_selected_notes_stem_direction(state, "up")
                    end
                end
                
                local p_down = (cur_stem_dir == "down") and "✓ " or "   "
                if reaper.ImGui_MenuItem(ctx, p_down .. "↓ Force Stem Down") then
                    if midi_service and midi_service.invert_selected_notes_stem_direction then
                        midi_service.invert_selected_notes_stem_direction(state, "down")
                    end
                end
                
                local p_auto = (cur_stem_dir == nil) and "✓ " or "   "
                if reaper.ImGui_MenuItem(ctx, p_auto .. "✕ Auto (Default Engraving)") then
                    if midi_service and midi_service.invert_selected_notes_stem_direction then
                        midi_service.invert_selected_notes_stem_direction(state, "auto")
                    end
                end
                reaper.ImGui_EndMenu(ctx)
            end
            
            if reaper.ImGui_BeginMenu(ctx, "🎯 Articulation") then
                local cur_note_art = nil
                local sn = state.selected_note
                if not sn and state.selected_notes then
                    for _, n in pairs(state.selected_notes) do sn = n break end
                end
                if sn and sn.articulation then cur_note_art = sn.articulation end
                
                local art_items = {
                    { id = "staccato",      label = "• Staccato" },
                    { id = "staccatissimo",  label = "▼ Staccatissimo / Spiccato" },
                    { id = "tenuto",        label = "— Tenuto" },
                    { id = "accent",        label = "> Accent" },
                    { id = "marcato",       label = "^ Marcato" },
                    { id = "harmonic",      label = "○ Harmonic / Flageolet" },
                }
                for _, a in ipairs(art_items) do
                    local is_cur = (cur_note_art == a.id)
                    local prefix = is_cur and "✓ " or "   "
                    if reaper.ImGui_MenuItem(ctx, prefix .. a.label) then
                        if midi_service and midi_service.toggle_selected_articulation then
                            midi_service.toggle_selected_articulation(state, a.id)
                        end
                    end
                end
                reaper.ImGui_Separator(ctx)
                if reaper.ImGui_MenuItem(ctx, "   ✕ None (Clear Articulation)") then
                    if midi_service and midi_service.toggle_selected_articulation then
                        midi_service.toggle_selected_articulation(state, "none")
                    end
                end
                reaper.ImGui_EndMenu(ctx)
            end
            
            if reaper.ImGui_BeginMenu(ctx, "🗣 Assign Voice (Channel)") then
                local cur_note_chan = nil
                local sn = state.selected_note
                if not sn and state.selected_notes then
                    for _, n in pairs(state.selected_notes) do sn = n break end
                end
                if sn and sn.chan then cur_note_chan = sn.chan end
                
                for v = 1, 16 do
                    local is_cur = (cur_note_chan ~= nil and cur_note_chan == (v - 1))
                    local prefix = is_cur and "✓ " or "   "
                    local item_lbl = string.format("%sVoice %d (Channel %d)", prefix, v, v)
                    if reaper.ImGui_MenuItem(ctx, item_lbl) then
                        if midi_service and midi_service.set_selected_notes_voice then
                            midi_service.set_selected_notes_voice(state, v)
                        end
                    end
                end
                reaper.ImGui_EndMenu(ctx)
            end
            
            if reaper.ImGui_MenuItem(ctx, "⚡ Auto-Voice on Selection") then
                local sn = state.selected_note
                if not sn and state.selected_notes then
                    for _, n in pairs(state.selected_notes) do sn = n break end
                end
                local trk = (sn and sn.track) or state.focused_track
                if midi_service and midi_service.auto_split_selection_to_voices then
                    midi_service.auto_split_selection_to_voices(state, trk)
                end
            end
            if reaper.ImGui_MenuItem(ctx, "⚡ Auto-Voice Track Overlaps") then
                local sn = state.selected_note
                if not sn and state.selected_notes then
                    for _, n in pairs(state.selected_notes) do sn = n break end
                end
                local trk = (sn and sn.track) or state.focused_track
                if midi_service and midi_service.auto_split_overlaps_to_voices then
                    midi_service.auto_split_overlaps_to_voices(state, trk)
                end
            end
            
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_MenuItem(ctx, "🔁 Toggle Measure Repeat (%)") then
                local sn = state.selected_note
                if not sn and state.selected_notes then
                    for _, n in pairs(state.selected_notes) do sn = n break end
                end
                if sn and sn.track then
                    local RepeatService = package.loaded["services.repeat_service"] or require("services.repeat_service")
                    local bpi = get_qn_per_measure(state, qn_per_measure)
                    local m = math.floor((sn.start_qn + 0.001) / bpi)
                    RepeatService.toggle_repeat_mark(state, sn.track, m, active_tracks_data)
                end
            end
            
            reaper.ImGui_Separator(ctx)
        else
            -- No note object selected -> context menu for staff & measure
            local cur_trk = state.focused_track
            local trk_name = "Track"
            if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
                local _, name = reaper.GetTrackName(cur_trk)
                if name and name ~= "" then trk_name = name end
            end
            local click_bar = state.context_measure and (state.context_measure + 1) or nil
            local hdr = click_bar and string.format("🎼 Staff: %s (Bar %d)", trk_name, click_bar) or string.format("🎼 Staff: %s", trk_name)
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, hdr)
            reaper.ImGui_Separator(ctx)
            
            -- Measure selection & track selection
            local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
            if click_bar and state.context_measure then
                if reaper.ImGui_MenuItem(ctx, string.format(">> Select Notes in Bar %d", click_bar)) then
                    if SelectionService.select_measure then
                        SelectionService.select_measure(state, state.context_measure, active_tracks_data, midi_service, qn_per_measure)
                    end
                end
            end
            
            if reaper.ImGui_MenuItem(ctx, ">> Select All on Track (Ctrl+A)") then
                SelectionService.select_all_in_track(state, active_tracks_data, midi_service)
            end
            
            -- Measure repeat (Repeat %)
            if click_bar and cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
                local RepeatService = package.loaded["services.repeat_service"] or require("services.repeat_service")
                local cguid = reaper.GetTrackGUID(cur_trk)
                local has_rep = RepeatService.has_repeat_mark(state, cguid, state.context_measure)
                local rep_label = has_rep and string.format("❌ Remove Repeat Mark (%%) from Bar %d", click_bar) or string.format("🔁 Set Bar %d as Repeat (%%)", click_bar)
                if reaper.ImGui_MenuItem(ctx, rep_label) then
                    RepeatService.toggle_repeat_mark(state, cur_trk, state.context_measure, active_tracks_data)
                end
            end
            
            -- Track-specific actions
            if reaper.ImGui_MenuItem(ctx, "⚡ Auto-Voice Track Overlaps") then
                if midi_service and midi_service.auto_split_overlaps_to_voices then
                    midi_service.auto_split_overlaps_to_voices(state, cur_trk)
                end
            end
            
            if reaper.ImGui_MenuItem(ctx, "⚡ Quantize Track... (Q)") then
                state.show_quantize_modal = true
            end
            
            -- Tools & drawers for this staff
            if reaper.ImGui_BeginMenu(ctx, "🛠 Tools & Drawers for Track...") then
                if reaper.ImGui_MenuItem(ctx, "📖 Dynamics Drawer (D)") then
                    state.show_dynamics = true
                    state.show_articulations_drawer = false
                    state.show_clefs = false
                    state.show_tempo = false
                end
                if reaper.ImGui_MenuItem(ctx, "🎯 Articulations Drawer (L)") then
                    state.show_articulations_drawer = true
                    state.show_dynamics = false
                    state.show_clefs = false
                    state.show_tempo = false
                end
                if reaper.ImGui_MenuItem(ctx, "𝄢 Clef Drawer (C)") then
                    state.show_clefs = true
                    state.show_dynamics = false
                    state.show_articulations_drawer = false
                    state.show_tempo = false
                end
                if reaper.ImGui_MenuItem(ctx, "♯♭ Key Signature Drawer") then
                    state.show_key_signatures = true
                    state.show_clefs = false
                    state.show_tempo = false
                    state.show_dynamics = false
                end
                if reaper.ImGui_MenuItem(ctx, "⏱ Tempo Drawer (T)") then
                    state.show_tempo = true
                    state.show_dynamics = false
                    state.show_clefs = false
                    state.show_articulations_drawer = false
                end
                reaper.ImGui_EndMenu(ctx)
            end
            
            reaper.ImGui_Separator(ctx)
        end
        
        -- Always available selection and filter options
        local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
        SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
        
        if reaper.ImGui_MenuItem(ctx, "🗑️ Delete (Del / Backspace)") then
            SelectionService.delete_all_selected(state, midi_service, active_tracks_data)
        end
        
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 5. ITEM HEADER POPUP (Key & Time Signature)
-- ==============================================================================
function CanvasContextMenus.render_item_header_popup(ctx, state)
    if reaper.ImGui_BeginPopup(ctx, "item_header_context_popup") then
        local it = state.item_context_target
        local tdata = state.item_context_track_data
        if it then
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, string.format("📦 MIDI Item: %s", it.name or "Untitled"))
            reaper.ImGui_Separator(ctx)

            -- 1. Key Signature...
            if reaper.ImGui_MenuItem(ctx, "♯♭ Key Signature...") then
                state.selected_item = it.item
                state.selected_take = it.take
                state.focused_track = tdata and tdata.track or state.focused_track
                state.show_key_signatures = true
                state.show_clefs = false
                state.show_dynamics = false
                state.show_tempo = false
                state.status_msg = string.format("Item '%s': Key Signature drawer opened", it.name or "Item")
            end

            -- 2. Time Signature... (Submenu with 4/4, 3/4, 2/4, 6/8 etc.)
            if reaper.ImGui_BeginMenu(ctx, "⏱ Time Signature") then
                local common_ts = {
                    { num = 4, den = 4, lbl = "4/4 (Common Time)" },
                    { num = 3, den = 4, lbl = "3/4 (Waltz)" },
                    { num = 2, den = 4, lbl = "2/4 (March)" },
                    { num = 6, den = 8, lbl = "6/8 (Compound Duple)" },
                    { num = 12, den = 8, lbl = "12/8 (Compound Quadruple)" },
                    { num = 5, den = 4, lbl = "5/4 (Asymmetric)" },
                    { num = 7, den = 8, lbl = "7/8 (Asymmetric)" },
                }
                local cur_num, cur_den = resolve_effective_time_sig(state, tdata and tdata.track, it, it.start_qn or 0)
                local has_kss, KeySignatureService = pcall(require, "services.key_signature_service")
                if not has_kss or not KeySignatureService then
                    has_kss, KeySignatureService = pcall(require, "modules.services.key_signature_service")
                end
                for _, ts in ipairs(common_ts) do
                    local is_cur = (cur_num == ts.num and cur_den == ts.den)
                    local prefix = is_cur and "✓ " or "   "
                    if reaper.ImGui_MenuItem(ctx, prefix .. ts.lbl) then
                        if KeySignatureService and KeySignatureService.set_item_time_sig then
                            KeySignatureService.set_item_time_sig(state, it.item, it.take, ts.num, ts.den)
                        else
                            reaper.GetSetMediaItemInfo_String(it.item, "P_EXT:notator_time_sig", string.format("%d|%d", ts.num, ts.den), true)
                            it.time_sig = { num = ts.num, denom = ts.den }
                            reaper.MarkProjectDirty(0)
                            reaper.UpdateArrange()
                        end
                        state.status_msg = string.format("Set time signature to %d/%d for item '%s'", ts.num, ts.den, it.name or "Item")
                    end
                end
                reaper.ImGui_EndMenu(ctx)
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 6. TEXT ITEM POPUP
-- ==============================================================================
function CanvasContextMenus.render_text_item_popup(ctx, state, midi_service, active_tracks_data)
    if reaper.ImGui_BeginPopup(ctx, "text_item_context_popup") then
        local cti = state.context_text_item
        if cti then
            local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "🔤 Text Item")
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_MenuItem(ctx, "Edit Text") then
                state.editing_text_item = cti
                state.editing_text_str = cti.text or ""
                state.editing_text_just_opened = true
            end
            
            if reaper.ImGui_BeginMenu(ctx, "Font Style") then
                local cur_style = tostring(cti.style or "italic"):lower()
                if reaper.ImGui_MenuItem(ctx, "Italic", nil, cur_style == "italic") then
                    cti.style = "italic"
                    TextItemService.save_text_items(state)
                    reaper.Undo_OnStateChange2(0, "Notator: Change Text Style")
                end
                if reaper.ImGui_MenuItem(ctx, "Bold", nil, cur_style == "bold") then
                    cti.style = "bold"
                    TextItemService.save_text_items(state)
                    reaper.Undo_OnStateChange2(0, "Notator: Change Text Style")
                end
                if reaper.ImGui_MenuItem(ctx, "Bold Italic", nil, cur_style == "bold_italic") then
                    cti.style = "bold_italic"
                    TextItemService.save_text_items(state)
                    reaper.Undo_OnStateChange2(0, "Notator: Change Text Style")
                end
                if reaper.ImGui_MenuItem(ctx, "Regular", nil, cur_style == "regular") then
                    cti.style = "regular"
                    TextItemService.save_text_items(state)
                    reaper.Undo_OnStateChange2(0, "Notator: Change Text Style")
                end
                reaper.ImGui_EndMenu(ctx)
            end
            
            if reaper.ImGui_BeginMenu(ctx, "Font Size") then
                local sizes = { 10, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 48, 64 }
                local cur_sz = math.floor(tonumber(cti.font_size) or 16)
                for _, sz in ipairs(sizes) do
                    if reaper.ImGui_MenuItem(ctx, tostring(sz) .. " pt", nil, cur_sz == sz) then
                        cti.font_size = sz
                        TextItemService.save_text_items(state)
                        reaper.Undo_OnStateChange2(0, "Notator: Change Text Font Size")
                    end
                end
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_TextDisabled(ctx, "Custom:")
                reaper.ImGui_SetNextItemWidth(ctx, 120)
                local changed, new_sz = reaper.ImGui_SliderInt(ctx, "##custom_fs", cur_sz, 8, 72, "%d pt")
                if changed then
                    cti.font_size = new_sz
                    TextItemService.save_text_items(state)
                end
                if reaper.APIExists("ImGui_IsItemDeactivatedAfterEdit") and reaper.ImGui_IsItemDeactivatedAfterEdit(ctx) then
                    reaper.Undo_OnStateChange2(0, "Notator: Change Text Font Size")
                end
                reaper.ImGui_EndMenu(ctx)
            end
            
            reaper.ImGui_Separator(ctx)
            local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
            SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
            
            if reaper.ImGui_MenuItem(ctx, "Delete (Del / Backspace)") then
                TextItemService.delete_text_item(state, cti.id)
                if state.selected_text_item and state.selected_text_item.id == cti.id then
                    state.selected_text_item = nil
                end
                state.context_text_item = nil
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 7. REPEAT MARK POPUP (%)
-- ==============================================================================
function CanvasContextMenus.render_repeat_mark_popup(ctx, state, active_tracks_data)
    if reaper.ImGui_BeginPopup(ctx, "repeat_mark_context_popup") then
        local crm = state.context_repeat_mark
        local trk = state.context_repeat_track or state.focused_track
        if crm then
            local RepeatService = package.loaded["services.repeat_service"] or require("services.repeat_service")
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, string.format("Bar %d: Repeat Mark (%%)", crm.measure + 1))
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_MenuItem(ctx, "🔄 Sync Notes from Preceding Bar") then
                if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                    RepeatService.sync_repeat_measure_notes(state, trk, crm.measure)
                end
            end
            
            if reaper.ImGui_MenuItem(ctx, "❌ Remove Repeat Mark (%)") then
                if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                    RepeatService.toggle_repeat_mark(state, trk, crm.measure, active_tracks_data)
                end
            end
            reaper.ImGui_EndPopup(ctx)
        end
    end
end

-- ==============================================================================
-- 8. MEASURE HEADER POPUP
-- ==============================================================================
function CanvasContextMenus.render_measure_header_popup(ctx, state, active_tracks_data)
    if reaper.ImGui_BeginPopup(ctx, "measure_header_context_popup") then
        local cm = state.context_measure
        local trk = state.context_measure_track or state.focused_track
        if cm ~= nil and trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            local RepeatService = package.loaded["services.repeat_service"] or require("services.repeat_service")
            local cguid = reaper.GetTrackGUID(trk)
            local has_rep = RepeatService.has_repeat_mark(state, cguid, cm)
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, string.format("Bar %d Actions", cm + 1))
            reaper.ImGui_Separator(ctx)
            
            if has_rep then
                if reaper.ImGui_MenuItem(ctx, "❌ Remove Repeat Mark (%)") then
                    RepeatService.toggle_repeat_mark(state, trk, cm, active_tracks_data)
                end
                if reaper.ImGui_MenuItem(ctx, "🔄 Re-Sync Notes from Preceding Bar") then
                    RepeatService.sync_repeat_measure_notes(state, trk, cm)
                end
            else
                if reaper.ImGui_MenuItem(ctx, "🔁 Set as Repeat Bar (%)") then
                    RepeatService.toggle_repeat_mark(state, trk, cm, active_tracks_data)
                end
            end
            reaper.ImGui_EndPopup(ctx)
        end
    end
end

-- ==============================================================================
-- 9. DYNAMIC MARKER POPUP (p, f, mf, etc.)
-- ==============================================================================
function CanvasContextMenus.render_dynamic_popup(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    if reaper.ImGui_BeginPopup(ctx, "dynamic_context_popup") then
        local d = state.context_dynamic or state.selected_dynamic
        if d then
            local DynamicsEngine = package.loaded["services.dynamics_engine"] or require("services.dynamics_engine")
            local bpi = get_qn_per_measure(state, qn_per_measure)
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, string.format("𝄢 Dynamic: %s", d.label or "Marker"))
            reaper.ImGui_TextDisabled(ctx, string.format("Measure %.2f (QN %.2f)", (d.qn / bpi) + 1, d.qn))
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_MenuItem(ctx, "📖 Open Dynamics Drawer (D)") then
                state.focused_track = d.track
                state.show_dynamics = true
                state.show_articulations_drawer = false
                state.show_clefs = false
                state.show_tempo = false
            end
            
            reaper.ImGui_Separator(ctx)
            local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
            SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
            
            if reaper.ImGui_MenuItem(ctx, "🗑 Delete Dynamic") then
                state.selected_dynamic = d
                DynamicsEngine.delete_selected_dynamic(state, midi_service, active_tracks_data)
                state.selected_dynamic = nil
                state.context_dynamic = nil
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 10. HAIRPIN POPUP (< and >)
-- ==============================================================================
function CanvasContextMenus.render_hairpin_popup(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    if reaper.ImGui_BeginPopup(ctx, "hairpin_context_popup") then
        local hp = state.context_hairpin or state.selected_hairpin
        if hp then
            local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
            local bpi = get_qn_per_measure(state, qn_per_measure)
            local hp_label = (hp.type == "crescendo") and "Crescendo (<)" or "Decrescendo (>)"
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, string.format("𝄢 Hairpin: %s", hp_label))
            reaper.ImGui_TextDisabled(ctx, string.format("Measure %.2f - %.2f (%.1f QN)", (hp.start_qn / bpi) + 1, (hp.end_qn / bpi) + 1, hp.end_qn - hp.start_qn))
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_MenuItem(ctx, "📖 Open Dynamics Drawer (D)") then
                state.focused_track = hp.track
                state.show_dynamics = true
                state.show_articulations_drawer = false
                state.show_clefs = false
                state.show_tempo = false
            end
            
            reaper.ImGui_Separator(ctx)
            local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
            SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
            
            if reaper.ImGui_MenuItem(ctx, "🗑 Delete Hairpin") then
                HairpinService.delete_hairpin(state, hp.id, midi_service, active_tracks_data)
                state.selected_hairpin = nil
                state.context_hairpin = nil
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 11. TEMPO MARKER POPUP
-- ==============================================================================
function CanvasContextMenus.render_tempo_popup(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    if reaper.ImGui_BeginPopup(ctx, "tempo_context_popup") then
        local tm = state.context_tempo_marker or state.selected_tempo_marker
        if tm then
            local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
            local bpi = get_qn_per_measure(state, qn_per_measure)
            local disp_txt = (type(tm.get_display_text) == "function" and tm:get_display_text()) or tostring(tm.bpm or "120")
            reaper.ImGui_TextColored(ctx, 0xF39C12FF, string.format("⏱ Tempo: %s", disp_txt))
            reaper.ImGui_TextDisabled(ctx, string.format("Measure %.2f (QN %.2f)", (tm.start_qn / bpi) + 1, tm.start_qn))
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_MenuItem(ctx, "✏ Edit BPM...") then
                state.editing_tempo_marker = tm
                state.editing_tempo_val = tostring(math.floor(tm.bpm or 120))
                reaper.ImGui_OpenPopup(ctx, "edit_tempo_popup")
            end
            
            if reaper.ImGui_MenuItem(ctx, "📖 Open Tempo Drawer (T)") then
                state.show_tempo = true
                state.show_dynamics = false
                state.show_articulations_drawer = false
                state.show_clefs = false
            end
            
            reaper.ImGui_Separator(ctx)
            local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
            SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
            
            if reaper.ImGui_MenuItem(ctx, "🗑 Delete Tempo Marker") then
                state.selected_tempo_marker = tm
                TempoService.delete_selected_tempo_marker(state)
                state.selected_tempo_marker = nil
                state.context_tempo_marker = nil
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 12. ARTICULATION POPUP (Reaticulate Text / PC)
-- ==============================================================================
function CanvasContextMenus.render_articulation_popup(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    if reaper.ImGui_BeginPopup(ctx, "articulation_context_popup") then
        local art = state.context_articulation or state.selected_articulation
        if art then
            local lbl = art.label or string.format("PC %d", art.pc or 0)
            local bpi = get_qn_per_measure(state, qn_per_measure)
            reaper.ImGui_TextColored(ctx, 0x9B59B6FF, string.format("🎯 Articulation: %s", lbl))
            reaper.ImGui_TextDisabled(ctx, string.format("Measure %.2f (QN %.2f)", (art.qn / bpi) + 1, art.qn))
            reaper.ImGui_Separator(ctx)
            
            if reaper.ImGui_MenuItem(ctx, "📖 Open Articulations Drawer (L)") then
                state.focused_track = art.track
                state.show_articulations_drawer = true
                state.show_dynamics = false
                state.show_clefs = false
                state.show_tempo = false
            end
            
            reaper.ImGui_Separator(ctx)
            local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
            SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
            
            if reaper.ImGui_MenuItem(ctx, "🗑 Delete Articulation") then
                state.selected_articulation = art
                if midi_service and midi_service.delete_selected_articulation then
                    midi_service.delete_selected_articulation(state)
                end
                state.selected_articulation = nil
                state.context_articulation = nil
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- 13. OCTAVE LINE POPUP
-- ==============================================================================
function CanvasContextMenus.render_octave_popup(ctx, state, midi_service, active_tracks_data)
    if reaper.ImGui_BeginPopup(ctx, "octave_context_popup") then
        local sel_oct = state.selected_octave_line
        if sel_oct then
            local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
            local Constants = package.loaded["constants"] or require("constants")
            local odef = (Constants and Constants.OCTAVE_LINE_DEFS) and Constants.OCTAVE_LINE_DEFS[sel_oct.type]
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, odef and odef.name or "Octave Line")
            reaper.ImGui_Separator(ctx)
            local SelectionService = package.loaded["services.selection_service"] or require("services.selection_service")
            SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
            if reaper.ImGui_MenuItem(ctx, "🗑 Delete Octave Line") then
                OctaveService.delete_octave_line(state, sel_oct)
            end
        end
        reaper.ImGui_EndPopup(ctx)
    end
end

-- ==============================================================================
-- RENDER ALL CONTEXT POPUPS
-- ==============================================================================
function CanvasContextMenus.render_all(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    CanvasContextMenus.render_octave_popup(ctx, state, midi_service, active_tracks_data)
    CanvasContextMenus.render_chord_lane_popup(ctx, state, qn_per_measure)
    CanvasContextMenus.render_dynamic_text_popup(ctx, state, midi_service, active_tracks_data)
    CanvasContextMenus.render_pedal_popup(ctx, state, midi_service, active_tracks_data)
    CanvasContextMenus.render_note_context_menu(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    CanvasContextMenus.render_item_header_popup(ctx, state)
    CanvasContextMenus.render_text_item_popup(ctx, state, midi_service, active_tracks_data)
    CanvasContextMenus.render_repeat_mark_popup(ctx, state, active_tracks_data)
    CanvasContextMenus.render_measure_header_popup(ctx, state, active_tracks_data)
    CanvasContextMenus.render_dynamic_popup(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    CanvasContextMenus.render_hairpin_popup(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    CanvasContextMenus.render_tempo_popup(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    CanvasContextMenus.render_articulation_popup(ctx, state, midi_service, active_tracks_data, qn_per_measure)
end

return CanvasContextMenus

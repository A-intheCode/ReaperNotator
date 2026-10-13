-- ==============================================================================
-- REAPER Native Notator - Module: RecordModal
-- Configuration dialog for REAPER Recording, Pre-roll, Metronome Count-in,
-- Track Record-Arming, and Auto-Quantize & Overlap Cleaning Engine.
-- ==============================================================================

local RecordQuantizeService = package.loaded["services.record_quantize_service"] or require("services.record_quantize_service")

local RecordModal = {}

local GRIDS = {
    { label = "1/1  (Whole)",   qn = 4.0 },
    { label = "1/2  (Half)",    qn = 2.0 },
    { label = "1/4  (Quarter)", qn = 1.0 },
    { label = "1/8  (Eighth)",  qn = 0.5 },
    { label = "1/16 (16th)",    qn = 0.25 },
    { label = "1/32 (32nd)",    qn = 0.125 },
    { label = "1/64 (64th)",    qn = 0.0625 },
}

function RecordModal.render(ctx, state, midi_service, project_tracks, active_tracks_data)
    if not state.show_record_modal then return end

    local flags = reaper.ImGui_WindowFlags_NoCollapse()
    if reaper.APIExists("ImGui_WindowFlags_TopMost") then
        flags = flags | reaper.ImGui_WindowFlags_TopMost()
    end
    if state.focus_record_modal then
        if reaper.APIExists("ImGui_SetNextWindowFocus") then
            reaper.ImGui_SetNextWindowFocus(ctx)
        end
        state.focus_record_modal = nil
    end

    reaper.ImGui_SetNextWindowSize(ctx, 530, 680, reaper.ImGui_Cond_FirstUseEver())
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "⚡ Recording & Auto-Quantize Settings###RecordModalWindow", true, flags)

    if not s_open then
        state.show_record_modal = false
    end

    if s_vis then
        local play_state = reaper.GetPlayState()
        local is_recording = (play_state & 4) == 4
        local is_playing = (play_state & 1) == 1

        -- 1. Status Banner
        if is_recording then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF4D4DFF)
            reaper.ImGui_Text(ctx, "🔴 RECORDING IN PROGRESS – Live playhead active on canvas")
            reaper.ImGui_PopStyleColor(ctx)
        elseif is_playing then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x2ECC71FF)
            reaper.ImGui_Text(ctx, "▶ PLAYBACK ACTIVE")
            reaper.ImGui_PopStyleColor(ctx)
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
            reaper.ImGui_Text(ctx, "⏹ TRANSPORT IDLE – Configure recording & auto-quantize options below")
            reaper.ImGui_PopStyleColor(ctx)
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- SECTION 1: REAPER PRE-ROLL & COUNT-IN
        -- ======================================================================
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9F1CFF)
        reaper.ImGui_Text(ctx, "1. Pre-roll & Count-in (REAPER Native):")
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_Spacing(ctx)

        -- Pre-roll on Record (Action 41818)
        local preroll_active = (reaper.GetToggleCommandState(41818) == 1)
        local changed_preroll, new_preroll = reaper.ImGui_Checkbox(ctx, "Pre-roll before Recording##PrerollToggle", preroll_active)
        if changed_preroll then
            reaper.Main_OnCommand(41818, 0)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Plays preceding measures before recording starts (REAPER Pre-roll).")
        end

        -- Pre-roll Length (Bars)
        reaper.ImGui_SameLine(ctx, 0, 20)
        reaper.ImGui_SetNextItemWidth(ctx, 130)
        local cur_preroll_bars = state.rec_preroll_bars or 1
        if reaper.APIExists("SNM_GetDoubleConfigVar") then
            local ok_sws, sws_bars = pcall(reaper.SNM_GetDoubleConfigVar, "prerollmeas", -1.0)
            if ok_sws and sws_bars and sws_bars > 0 then
                cur_preroll_bars = math.floor(sws_bars + 0.5)
            end
        end

        local bar_labels = { [1] = "1 Bar", [2] = "2 Bars", [4] = "4 Bars" }
        local cur_bar_str = bar_labels[cur_preroll_bars] or string.format("%d Bars", cur_preroll_bars)
        if reaper.ImGui_BeginCombo(ctx, "##PrerollBarsCombo", cur_bar_str) then
            for _, b in ipairs({ 1, 2, 4 }) do
                local is_sel = (cur_preroll_bars == b)
                if reaper.ImGui_Selectable(ctx, bar_labels[b], is_sel) then
                    state.rec_preroll_bars = b
                    if reaper.APIExists("SNM_SetDoubleConfigVar") then
                        pcall(reaper.SNM_SetDoubleConfigVar, "prerollmeas", tonumber(b) or 1.0)
                    end
                    require("state").save_settings(state)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        -- Count-in on Record (Action 40364)
        local countin_active = (reaper.GetToggleCommandState(40364) == 1)
        local changed_ci, new_ci = reaper.ImGui_Checkbox(ctx, "Metronome Count-in before Recording##CountinToggle", countin_active)
        if changed_ci then
            reaper.Main_OnCommand(40364, 0)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Audible metronome count-in clicks before recording starts.")
        end

        reaper.ImGui_SameLine(ctx, 0, 16)
        if reaper.ImGui_Button(ctx, "⚙ Metronome Settings...##MetroBtn", 170, 22) then
            reaper.Main_OnCommand(40049, 0) -- Options: Metronome/pre-roll settings
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Opens REAPER's native Metronome and Pre-roll settings dialog.")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- SECTION 2: AUTO-QUANTIZE ON RECORD STOP
        -- ======================================================================
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9F1CFF)
        reaper.ImGui_Text(ctx, "2. Auto-Quantize on Record Stop:")
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_Spacing(ctx)

        -- Master Auto-Quantize Toggle
        local chk_aq, new_aq = reaper.ImGui_Checkbox(ctx, "Enable Auto-Quantize on Record Stop##MasterAQ", state.rec_auto_quantize ~= false)
        if chk_aq then
            state.rec_auto_quantize = new_aq
            require("state").save_settings(state)
        end

        if state.rec_auto_quantize ~= false then
            -- Grid Selection
            reaper.ImGui_Text(ctx, "Grid Division:")
            reaper.ImGui_SetNextItemWidth(ctx, 220)
            local cur_label = state.rec_quantize_grid_label or "1/8"
            for _, g in ipairs(GRIDS) do
                if math.abs((state.rec_quantize_grid_qn or 0.5) - g.qn) < 0.001 then
                    cur_label = g.label
                    break
                end
            end

            if reaper.ImGui_BeginCombo(ctx, "##RecGridCombo", cur_label) then
                for _, g in ipairs(GRIDS) do
                    local is_sel = (math.abs((state.rec_quantize_grid_qn or 0.5) - g.qn) < 0.001)
                    if reaper.ImGui_Selectable(ctx, g.label, is_sel) then
                        state.rec_quantize_grid_qn = g.qn
                        state.rec_quantize_grid_label = g.label:match("^(%S+)")
                        require("state").save_settings(state)
                    end
                end
                reaper.ImGui_EndCombo(ctx)
            end

            -- Grid Type (Straight / Triplet / Dotted)
            reaper.ImGui_SameLine(ctx, 0, 14)
            reaper.ImGui_SetNextItemWidth(ctx, 140)
            local cur_type = state.rec_quantize_grid_type or "straight"
            local type_names = { straight = "Straight", triplet = "Triplet", dotted = "Dotted" }
            if reaper.ImGui_BeginCombo(ctx, "##RecGridTypeCombo", type_names[cur_type] or "Straight") then
                if reaper.ImGui_Selectable(ctx, "Straight", cur_type == "straight") then 
                    state.rec_quantize_grid_type = "straight"
                    require("state").save_settings(state)
                end
                if reaper.ImGui_Selectable(ctx, "Triplet", cur_type == "triplet") then 
                    state.rec_quantize_grid_type = "triplet"
                    require("state").save_settings(state)
                end
                if reaper.ImGui_Selectable(ctx, "Dotted", cur_type == "dotted") then 
                    state.rec_quantize_grid_type = "dotted"
                    require("state").save_settings(state)
                end
                reaper.ImGui_EndCombo(ctx)
            end

            -- Tick Tolerance Radius Slider
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Text(ctx, string.format("Tick Tolerance Radius: ±%d Ticks", state.rec_tolerance_ticks or 25))
            reaper.ImGui_SetNextItemWidth(ctx, 280)
            local changed_tol, new_tol = reaper.ImGui_SliderInt(ctx, "##RecTolSlider", state.rec_tolerance_ticks or 25, 0, 120, "%d Ticks")
            if changed_tol then
                state.rec_tolerance_ticks = new_tol
                require("state").save_settings(state)
            end

            reaper.ImGui_SameLine(ctx, 0, 8)
            local function tol_btn(val)
                if reaper.ImGui_Button(ctx, string.format("%d##Tol%d", val, val), 36, 22) then
                    state.rec_tolerance_ticks = val
                    require("state").save_settings(state)
                end
                reaper.ImGui_SameLine(ctx, 0, 4)
            end
            tol_btn(0)
            tol_btn(15)
            tol_btn(25)
            tol_btn(50)
            tol_btn(80)
            reaper.ImGui_NewLine(ctx)

            reaper.ImGui_TextDisabled(ctx, "Notes within ±tolerance of the grid snap directly to the beat.")

            -- Overlap & Bounce Cleaning Checkbox
            reaper.ImGui_Spacing(ctx)
            local chk_ol, new_ol = reaper.ImGui_Checkbox(ctx, "Clean keyboard bounce (<15 ticks) & overlapping notes on same pitch##RecOverlaps", state.rec_clean_overlaps ~= false)
            if chk_ol then
                state.rec_clean_overlaps = new_ol
                require("state").save_settings(state)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Trims overlapping tails and deletes fast bounce re-attacks on identical pitches.")
            end

            -- Outlier Handling Mode (outside tolerance radius)
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Text(ctx, "Notes outside tolerance radius:")
            local cur_outlier = state.rec_outlier_mode or "keep"
            if reaper.ImGui_RadioButton(ctx, "Keep natural (unquantized)##OutlierKeep", cur_outlier == "keep") then
                state.rec_outlier_mode = "keep"
                require("state").save_settings(state)
            end
            reaper.ImGui_SameLine(ctx, 0, 16)
            if reaper.ImGui_RadioButton(ctx, "Delete outlier notes##OutlierDel", cur_outlier == "delete") then
                state.rec_outlier_mode = "delete"
                require("state").save_settings(state)
            end
            reaper.ImGui_SameLine(ctx, 0, 16)
            if reaper.ImGui_RadioButton(ctx, "Move to Voice 16##OutlierV16", cur_outlier == "voice16") then
                state.rec_outlier_mode = "voice16"
                require("state").save_settings(state)
            end
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- SECTION 3: TARGET RECORDING TRACKS (ARMING & RED BADGES)
        -- ======================================================================
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9F1CFF)
        reaper.ImGui_Text(ctx, "3. Target Recording Tracks (Arm for Recording):")
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_Spacing(ctx)

        -- Quick Arm Buttons
        if reaper.ImGui_Button(ctx, "● Arm Active Track##ArmAct", 150, 24) then
            local trk = state.focused_track or reaper.GetSelectedTrack(0, 0)
            if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                reaper.SetMediaTrackInfo_Value(trk, "I_RECARM", 1)
            end
        end
        reaper.ImGui_SameLine(ctx, 0, 8)

        if reaper.ImGui_Button(ctx, "● Arm All Score Tracks##ArmAll", 160, 24) then
            for _, tdata in ipairs(active_tracks_data or {}) do
                if tdata.track and reaper.ValidatePtr(tdata.track, "MediaTrack*") then
                    reaper.SetMediaTrackInfo_Value(tdata.track, "I_RECARM", 1)
                end
            end
        end
        reaper.ImGui_SameLine(ctx, 0, 8)

        if reaper.ImGui_Button(ctx, "○ Disarm All##DisarmAll", 110, 24) then
            local trk_cnt = reaper.CountTracks(0)
            for ti = 0, trk_cnt - 1 do
                local trk = reaper.GetTrack(0, ti)
                if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                    reaper.SetMediaTrackInfo_Value(trk, "I_RECARM", 0)
                end
            end
        end

        reaper.ImGui_Spacing(ctx)

        -- Track Selection List Child Window
        local child_h = 160
        local child_flags = reaper.APIExists("ImGui_ChildFlags_Border") and reaper.ImGui_ChildFlags_Border() or 1
        if reaper.ImGui_BeginChild(ctx, "##RecordTracksChild", 0, child_h, child_flags) then
            local trk_list = {}
            if active_tracks_data and #active_tracks_data > 0 then
                for _, td in ipairs(active_tracks_data) do
                    if td.track and reaper.ValidatePtr(td.track, "MediaTrack*") then
                        table.insert(trk_list, { track = td.track, idx = td.idx, name = td.name })
                    end
                end
            else
                local trk_cnt = reaper.CountTracks(0)
                for ti = 0, trk_cnt - 1 do
                    local trk = reaper.GetTrack(0, ti)
                    if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                        local _, tname = reaper.GetTrackName(trk)
                        table.insert(trk_list, { track = trk, idx = ti + 1, name = tname })
                    end
                end
            end

            for _, item in ipairs(trk_list) do
                local trk = item.track
                local is_armed = (reaper.GetMediaTrackInfo_Value(trk, "I_RECARM") == 1)
                
                -- Red background highlighting for armed tracks
                if is_armed then
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF5252FF)
                end

                local changed_arm, new_arm = reaper.ImGui_Checkbox(ctx, string.format("##TrkArm%d", item.idx), is_armed)
                if changed_arm then
                    reaper.SetMediaTrackInfo_Value(trk, "I_RECARM", new_arm and 1 or 0)
                end

                reaper.ImGui_SameLine(ctx, 0, 8)
                local trk_badge = is_armed and "● REC " or "  "
                reaper.ImGui_Text(ctx, string.format("%s[%d] %s", trk_badge, item.idx, item.name or "Track"))

                if is_armed then
                    reaper.ImGui_PopStyleColor(ctx)
                end
            end

            reaper.ImGui_EndChild(ctx)
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- FOOTER: CLOSE BUTTON & RECORD TOGGLE
        -- ======================================================================
        local rec_btn_text = is_recording and "⏹ Stop Recording" or "🔴 Start Recording"
        local rec_btn_col = is_recording and 0x962D22FF or 0xC0392BFF
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), rec_btn_col)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE74C3CFF)
        if reaper.ImGui_Button(ctx, rec_btn_text .. "##ModalRecBtn", 180, 32) then
            reaper.CSurf_OnRecord()
        end
        reaper.ImGui_PopStyleColor(ctx, 2)

        reaper.ImGui_SameLine(ctx, 0, 16)
        if reaper.ImGui_Button(ctx, "Close##CloseRecordModal", 100, 32) then
            state.show_record_modal = false
        end
    end

    reaper.ImGui_End(ctx)
end

return RecordModal


-- ==============================================================================
-- REAPER Native Notator - Module: RecordModal
-- Configuration dialog for REAPER Recording, Pre-roll, Metronome Count-in,
-- MIDI Input Device & Channel Routing, Bidirectional Track Record-Arming,
-- Live Note Preview, and Auto-Quantize & Overlap Cleaning Engine.
-- ==============================================================================

local RecordQuantizeService = package.loaded["services.record_quantize_service"] or require("services.record_quantize_service")
local AudioPreview = package.loaded["services.audio_preview"] or require("services.audio_preview")

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

local function apply_routing_to_all_armed(state)
    local trk_cnt = reaper.CountTracks(0)
    for ti = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            if AudioPreview.is_track_user_armed(trk) then
                RecordQuantizeService.apply_midi_routing_to_track(state, trk, true)
            end
        end
    end
    if reaper.TrackList_AdjustWindows then
        reaper.TrackList_AdjustWindows(false)
    end
    if reaper.UpdateArrange then
        reaper.UpdateArrange()
    end
end

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

    reaper.ImGui_SetNextWindowSize(ctx, 590, 760, reaper.ImGui_Cond_FirstUseEver())
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "⚡ Recording, MIDI Input & Auto-Quantize###RecordModalWindow", true, flags)

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
            reaper.ImGui_Text(ctx, "🔴 RECORDING IN PROGRESS – Live playhead & note preview active on canvas")
            reaper.ImGui_PopStyleColor(ctx)
        elseif is_playing then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x2ECC71FF)
            reaper.ImGui_Text(ctx, "▶ PLAYBACK ACTIVE")
            reaper.ImGui_PopStyleColor(ctx)
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xAAAAAAFF)
            reaper.ImGui_Text(ctx, "⏹ TRANSPORT IDLE – Configure MIDI input, armed tracks & auto-quantize below")
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

        -- Pre-roll on Record (Action 41819)
        local preroll_active = (reaper.GetToggleCommandState(41819) == 1)
        local changed_preroll, _ = reaper.ImGui_Checkbox(ctx, "Pre-roll before Recording##PrerollToggle", preroll_active)
        if changed_preroll then
            reaper.Main_OnCommand(41819, 0)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Plays preceding measures before recording starts (REAPER Pre-roll on Record).")
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

        -- Metronome & Count-in on Record (Action 40364)
        local countin_active = (reaper.GetToggleCommandState(40364) == 1)
        local changed_ci, _ = reaper.ImGui_Checkbox(ctx, "Metronome Count-in before Recording##CountinToggle", countin_active)
        if changed_ci then
            reaper.Main_OnCommand(40364, 0)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Audible metronome / count-in clicks during and before recording.")
        end

        reaper.ImGui_SameLine(ctx, 0, 16)
        if reaper.ImGui_Button(ctx, "⚙ Metronome Settings...##MetroBtn", 170, 22) then
            reaper.Main_OnCommand(40363, 0)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Opens REAPER's native Metronome and Pre-roll settings dialog.")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- SECTION 2: MIDI INPUT DEVICE, CHANNEL & LIVE PREVIEW
        -- ======================================================================
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9F1CFF)
        reaper.ImGui_Text(ctx, "2. MIDI Input Device, Routing & Live Preview:")
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_Spacing(ctx)

        local midi_devices = RecordQuantizeService.get_midi_input_devices()
        local cur_dev_id = state.rec_midi_device or 63
        local cur_dev_name = "All MIDI Inputs (All Devices)"
        for _, d in ipairs(midi_devices) do
            if d.id == cur_dev_id then
                cur_dev_name = d.name
                break
            end
        end

        reaper.ImGui_Text(ctx, "MIDI Input Device:")
        reaper.ImGui_SetNextItemWidth(ctx, 310)
        if reaper.ImGui_BeginCombo(ctx, "##RecMidiDeviceCombo", cur_dev_name) then
            for _, d in ipairs(midi_devices) do
                local is_sel = (d.id == cur_dev_id)
                if reaper.ImGui_Selectable(ctx, d.name, is_sel) then
                    state.rec_midi_device = d.id
                    require("state").save_settings(state)
                    apply_routing_to_all_armed(state)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Selects which MIDI keyboard/device is assigned to armed tracks in REAPER.")
        end

        reaper.ImGui_SameLine(ctx, 0, 12)
        local cur_chan = state.rec_midi_channel or 0
        local cur_chan_str = (cur_chan == 0) and "All Channels" or string.format("Channel %d", cur_chan)
        reaper.ImGui_SetNextItemWidth(ctx, 135)
        if reaper.ImGui_BeginCombo(ctx, "##RecMidiChanCombo", cur_chan_str) then
            if reaper.ImGui_Selectable(ctx, "All Channels", cur_chan == 0) then
                state.rec_midi_channel = 0
                require("state").save_settings(state)
                apply_routing_to_all_armed(state)
            end
            for ch = 1, 16 do
                local is_sel = (cur_chan == ch)
                if reaper.ImGui_Selectable(ctx, string.format("Channel %d (Voice %d)", ch, ch), is_sel) then
                    state.rec_midi_channel = ch
                    require("state").save_settings(state)
                    apply_routing_to_all_armed(state)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        -- Record Mode Selection (Overdub vs Standard Input)
        local cur_mode = state.rec_mode or 7
        reaper.ImGui_Text(ctx, "Record Mode:")
        reaper.ImGui_SameLine(ctx, 0, 10)
        if reaper.ImGui_RadioButton(ctx, "MIDI Overdub (Direct, No Save Dialog)##RecMode7", cur_mode == 7) then
            state.rec_mode = 7
            require("state").save_settings(state)
            apply_routing_to_all_armed(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Recommended: Records MIDI directly into score items without popping up REAPER's 'Save recorded media' dialog.")
        end
        reaper.ImGui_SameLine(ctx, 0, 14)
        if reaper.ImGui_RadioButton(ctx, "New MIDI Take##RecMode0", cur_mode == 0) then
            state.rec_mode = 0
            require("state").save_settings(state)
            apply_routing_to_all_armed(state)
        end

        -- Auto Input Monitoring & Live Note Preview Checkboxes
        local chk_mon, new_mon = reaper.ImGui_Checkbox(ctx, "Monitor Input (Hear Instrument)##RecMonCb", state.rec_auto_monitor ~= false)
        if chk_mon then
            state.rec_auto_monitor = new_mon
            require("state").save_settings(state)
            apply_routing_to_all_armed(state)
        end
        reaper.ImGui_SameLine(ctx, 0, 20)
        local chk_lp, new_lp = reaper.ImGui_Checkbox(ctx, "Live Note Preview on Canvas while Recording##RecLivePrevCb", state.rec_live_preview ~= false)
        if chk_lp then
            state.rec_live_preview = new_lp
            require("state").save_settings(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Displays incoming MIDI notes live on the score canvas in real time as you play them.")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- SECTION 3: REAL-TIME AUTO-QUANTIZE (LIVE DURING RECORDING)
        -- ======================================================================
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9F1CFF)
        reaper.ImGui_Text(ctx, "3. Real-Time Auto-Quantize (Live during Recording):")
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_Spacing(ctx)

        local chk_aq, new_aq = reaper.ImGui_Checkbox(ctx, "Enable Real-Time Auto-Quantize##MasterAQ", state.rec_auto_quantize ~= false)
        if chk_aq then
            state.rec_auto_quantize = new_aq
            require("state").save_settings(state)
        end

        if state.rec_auto_quantize ~= false then
            reaper.ImGui_Text(ctx, "Grid Division:")
            reaper.ImGui_SameLine(ctx, 0, 10)
            reaper.ImGui_SetNextItemWidth(ctx, 190)
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

            reaper.ImGui_SameLine(ctx, 0, 12)
            reaper.ImGui_SetNextItemWidth(ctx, 130)
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
            reaper.ImGui_SetNextItemWidth(ctx, 260)
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

            -- Overlap & Bounce Cleaning Checkbox
            local chk_ol, new_ol = reaper.ImGui_Checkbox(ctx, "Clean keyboard bounce (<15 ticks) & overlapping notes on same pitch##RecOverlaps", state.rec_clean_overlaps ~= false)
            if chk_ol then
                state.rec_clean_overlaps = new_ol
                require("state").save_settings(state)
            end

            -- Outlier Handling Mode
            reaper.ImGui_Text(ctx, "Notes outside tolerance:")
            reaper.ImGui_SameLine(ctx, 0, 10)
            local cur_outlier = state.rec_outlier_mode or "snap"
            if reaper.ImGui_RadioButton(ctx, "🧲 Snap to Grid##OutlierSnap", cur_outlier == "snap") then
                state.rec_outlier_mode = "snap"
                require("state").save_settings(state)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Pulls and snaps notes outside the tick tolerance radius onto the nearest grid division.")
            end
            reaper.ImGui_SameLine(ctx, 0, 12)
            if reaper.ImGui_RadioButton(ctx, "Keep natural##OutlierKeep", cur_outlier == "keep") then
                state.rec_outlier_mode = "keep"
                require("state").save_settings(state)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Leaves notes outside the tick tolerance radius at their natural unquantized timing.")
            end
            reaper.ImGui_SameLine(ctx, 0, 12)
            if reaper.ImGui_RadioButton(ctx, "Delete outliers##OutlierDel", cur_outlier == "delete") then
                state.rec_outlier_mode = "delete"
                require("state").save_settings(state)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Deletes notes that fall outside the tick tolerance radius.")
            end
            reaper.ImGui_SameLine(ctx, 0, 12)
            if reaper.ImGui_RadioButton(ctx, "Move to Voice 16##OutlierV16", cur_outlier == "voice16") then
                state.rec_outlier_mode = "voice16"
                require("state").save_settings(state)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Moves notes outside the tick tolerance radius to Voice 16 (MIDI Channel 16).")
            end
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- SECTION 4: TARGET RECORDING TRACKS (SYNCHRONIZED WITH REAPER TCP)
        -- ======================================================================
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9F1CFF)
        reaper.ImGui_Text(ctx, "4. Target Recording Tracks (Synchronized with REAPER):")
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_Spacing(ctx)

        -- Quick Arm Buttons
        if reaper.ImGui_Button(ctx, "● Arm Active Track##ArmAct", 150, 24) then
            local trk = state.focused_track or reaper.GetSelectedTrack(0, 0)
            if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                RecordQuantizeService.set_track_armed(state, trk, true)
            end
        end
        reaper.ImGui_SameLine(ctx, 0, 8)

        if reaper.ImGui_Button(ctx, "● Arm All Score Tracks##ArmAll", 160, 24) then
            for _, tdata in ipairs(active_tracks_data or {}) do
                if tdata.track and reaper.ValidatePtr(tdata.track, "MediaTrack*") then
                    RecordQuantizeService.set_track_armed(state, tdata.track, true)
                end
            end
        end
        reaper.ImGui_SameLine(ctx, 0, 8)

        if reaper.ImGui_Button(ctx, "○ Disarm All##DisarmAll", 110, 24) then
            local trk_cnt = reaper.CountTracks(0)
            for ti = 0, trk_cnt - 1 do
                local trk = reaper.GetTrack(0, ti)
                if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                    RecordQuantizeService.set_track_armed(state, trk, false)
                end
            end
        end

        reaper.ImGui_Spacing(ctx)

        -- Track Selection List Child Window (Always shows ALL REAPER tracks!)
        local child_h = 155
        local child_flags = reaper.APIExists("ImGui_ChildFlags_Border") and reaper.ImGui_ChildFlags_Border() or 1
        if reaper.ImGui_BeginChild(ctx, "##RecordTracksChild", 0, child_h, child_flags) then
            local trk_cnt = reaper.CountTracks(0)
            if trk_cnt == 0 then
                reaper.ImGui_TextDisabled(ctx, "No tracks in current REAPER project.")
            end

            for ti = 0, trk_cnt - 1 do
                local trk = reaper.GetTrack(0, ti)
                if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                    local _, tname = reaper.GetTrackName(trk)
                    if not tname or tname == "" then
                        tname = string.format("Track %d", ti + 1)
                    end
                    local is_armed = AudioPreview.is_track_user_armed(trk)
                    local in_label, is_midi_in = RecordQuantizeService.format_track_midi_input(trk)

                    if is_armed then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF5252FF)
                    end

                    local changed_arm, new_arm = reaper.ImGui_Checkbox(ctx, string.format("##TrkArm_%d", ti + 1), is_armed)
                    if changed_arm then
                        RecordQuantizeService.set_track_armed(state, trk, new_arm)
                    end

                    reaper.ImGui_SameLine(ctx, 0, 8)
                    local trk_badge = is_armed and "● REC " or "  "
                    reaper.ImGui_Text(ctx, string.format("%s[%d] %s", trk_badge, ti + 1, tname))

                    if is_armed then
                        reaper.ImGui_PopStyleColor(ctx)
                    end

                    -- Per-track MIDI Input status button on the right
                    reaper.ImGui_SameLine(ctx, 310)
                    if not is_midi_in then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xF39C12FF)
                    else
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x85C1E9FF)
                    end
                    if reaper.ImGui_SmallButton(ctx, string.format("🎹 %s##TrkInBtn_%d", in_label, ti + 1)) then
                        reaper.ImGui_OpenPopup(ctx, string.format("TrkMidiInPopup_%d", ti + 1))
                    end
                    reaper.ImGui_PopStyleColor(ctx)
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, "Click to select MIDI Input Device for this track.")
                    end

                    if reaper.ImGui_BeginPopup(ctx, string.format("TrkMidiInPopup_%d", ti + 1)) then
                        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, string.format("MIDI Input for [%d] %s:", ti + 1, tname))
                        reaper.ImGui_Separator(ctx)
                        local _, trk_dev, trk_ch = RecordQuantizeService.decode_midi_recinput(
                            reaper.GetMediaTrackInfo_Value(trk, "I_RECINPUT")
                        )
                        for _, d in ipairs(midi_devices) do
                            if reaper.ImGui_MenuItem(ctx, d.name, nil, is_midi_in and (trk_dev == d.id)) then
                                local encoded = RecordQuantizeService.encode_midi_recinput(d.id, trk_ch or 0)
                                reaper.SetMediaTrackInfo_Value(trk, "I_RECINPUT", encoded)
                                reaper.SetMediaTrackInfo_Value(trk, "I_RECMON", 1)
                                reaper.SetMediaTrackInfo_Value(trk, "I_RECMODE", state.rec_mode or 7)
                                if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
                            end
                        end
                        reaper.ImGui_EndPopup(ctx)
                    end
                end
            end

            reaper.ImGui_EndChild(ctx)
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- FOOTER: RECORD TOGGLE & CLOSE BUTTON
        -- ======================================================================
        local rec_btn_text = is_recording and "⏹ Stop Recording" or "🔴 Start Recording"
        local rec_btn_col = is_recording and 0x962D22FF or 0xC0392BFF
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), rec_btn_col)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE74C3CFF)
        if reaper.ImGui_Button(ctx, rec_btn_text .. "##ModalRecBtn", 190, 32) then
            if is_recording then
                state._last_rec_play_pos = reaper.GetPlayPosition()
                reaper.CSurf_OnStop()
            else
                RecordQuantizeService.on_record_start(state)
                reaper.CSurf_OnRecord()
            end
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

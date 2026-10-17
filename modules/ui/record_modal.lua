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

local function is_hwnd_open(hwnd)
    if not hwnd then return false end
    if reaper.APIExists("JS_Window_IsWindow") and not reaper.JS_Window_IsWindow(hwnd) then
        return false
    end
    if reaper.APIExists("JS_Window_IsVisible") and not reaper.JS_Window_IsVisible(hwnd) then
        return false
    end
    return true
end

local function resolve_top_dialog_hwnd(cand, main_hwnd, notator_hwnd)
    if not cand or cand == main_hwnd or cand == notator_hwnd then return nil end
    local cur = cand
    if reaper.APIExists("JS_Window_GetParent") then
        for _ = 1, 8 do
            local p = reaper.JS_Window_GetParent(cur)
            if not p or p == main_hwnd then
                break
            end
            cur = p
        end
    end
    if not cur or cur == main_hwnd or cur == notator_hwnd then return nil end
    if reaper.APIExists("JS_Window_GetTitle") then
        local title = reaper.JS_Window_GetTitle(cur) or ""
        if title:find("REAPER Notator") or title:find("Recording, MIDI Input") then
            return nil
        end
    end
    return cur
end

local function find_metro_hwnd(state)
    if is_hwnd_open(state._metro_hwnd) then
        return state._metro_hwnd
    end
    local main_hwnd = reaper.GetMainHwnd()
    local notator_hwnd = state._notator_hwnd

    if reaper.APIExists("JS_Window_GetFocus") then
        local f_hwnd = resolve_top_dialog_hwnd(reaper.JS_Window_GetFocus(), main_hwnd, notator_hwnd)
        if f_hwnd and is_hwnd_open(f_hwnd) then
            return f_hwnd
        end
    end
    if reaper.APIExists("JS_Window_GetForeground") then
        local fg_hwnd = resolve_top_dialog_hwnd(reaper.JS_Window_GetForeground(), main_hwnd, notator_hwnd)
        if fg_hwnd and is_hwnd_open(fg_hwnd) then
            return fg_hwnd
        end
    end
    if reaper.APIExists("JS_Window_FindTop") then
        local h = reaper.JS_Window_FindTop("Metronome", false) or reaper.JS_Window_FindTop("Metronom", false)
        h = resolve_top_dialog_hwnd(h, main_hwnd, notator_hwnd)
        if h and is_hwnd_open(h) then return h end
    end
    if reaper.APIExists("JS_Window_Find") then
        local h = reaper.JS_Window_Find("Metronome", false) or reaper.JS_Window_Find("Metronom", false)
        h = resolve_top_dialog_hwnd(h, main_hwnd, notator_hwnd)
        if h and is_hwnd_open(h) then return h end
    end
    return nil
end

local function pin_metro_hwnd_topmost(hwnd, set_focus)
    if not is_hwnd_open(hwnd) then return false end
    if reaper.APIExists("JS_Window_SetZOrder") then
        reaper.JS_Window_SetZOrder(hwnd, "TOPMOST")
    end
    if set_focus then
        if reaper.APIExists("JS_Window_SetForeground") then
            reaper.JS_Window_SetForeground(hwnd)
        end
        if reaper.APIExists("JS_Window_SetFocus") then
            reaper.JS_Window_SetFocus(hwnd)
        end
    end
    return true
end

local function refresh_open_metro_dialog(state)
    local hwnd = state._metro_hwnd
    if not is_hwnd_open(hwnd) then
        if reaper.APIExists("JS_Window_FindTop") then
            local main_hwnd = reaper.GetMainHwnd()
            local h = reaper.JS_Window_FindTop("Metronome", false) or reaper.JS_Window_FindTop("Metronom", false)
            hwnd = resolve_top_dialog_hwnd(h, main_hwnd, state._notator_hwnd)
        end
    end
    if not is_hwnd_open(hwnd) then return end

    local has_rect, left, top, right, bottom = false, 0, 0, 0, 0
    if reaper.APIExists("JS_Window_GetRect") then
        has_rect, left, top, right, bottom = reaper.JS_Window_GetRect(hwnd)
    end

    state._metro_pin_frames = 10
    reaper.defer(function()
        if is_hwnd_open(hwnd) then
            -- Close and immediately re-open so REAPER repopulates dialog controls from updated config vars
            reaper.Main_OnCommand(40363, 0)
            reaper.Main_OnCommand(40363, 0)
            state._metro_hwnd = nil
            local new_hwnd = find_metro_hwnd(state)
            if new_hwnd then
                state._metro_hwnd = new_hwnd
                if has_rect and reaper.APIExists("JS_Window_SetPosition") then
                    local w = math.abs(right - left)
                    local h_px = math.abs(bottom - top)
                    if w > 50 and h_px > 50 then
                        reaper.JS_Window_SetPosition(new_hwnd, left, top, w, h_px)
                    end
                end
                pin_metro_hwnd_topmost(new_hwnd, false)
            end
        end
    end)
end

local function set_reaper_preroll(state, enable)
    local rec_state = (reaper.GetToggleCommandState(41819) == 1)
    local play_state = (reaper.GetToggleCommandState(41818) == 1)

    if enable then
        if not rec_state then
            reaper.Main_OnCommand(41819, 0)
        end
        if reaper.APIExists("SNM_GetIntConfigVar") and reaper.APIExists("SNM_SetIntConfigVar") then
            local ok_p, p_val = pcall(reaper.SNM_GetIntConfigVar, "preroll", -1)
            if ok_p and p_val and p_val >= 0 then
                pcall(reaper.SNM_SetIntConfigVar, "preroll", p_val | 2)
            end
        end
    else
        if rec_state then
            reaper.Main_OnCommand(41819, 0)
        end
        if play_state then
            reaper.Main_OnCommand(41818, 0)
        end
        if reaper.APIExists("SNM_GetIntConfigVar") and reaper.APIExists("SNM_SetIntConfigVar") then
            local ok_p, p_val = pcall(reaper.SNM_GetIntConfigVar, "preroll", -1)
            if ok_p and p_val and p_val >= 0 then
                pcall(reaper.SNM_SetIntConfigVar, "preroll", p_val & (~3))
            end
        end
    end
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateTimeline()
    refresh_open_metro_dialog(state)
end

local function set_reaper_countin(state, enable)
    local metro_state = (reaper.GetToggleCommandState(40364) == 1)
    if enable then
        if not metro_state then
            reaper.Main_OnCommand(40364, 0)
        end
        if reaper.APIExists("SNM_GetIntConfigVar") and reaper.APIExists("SNM_SetIntConfigVar") then
            local ok_m, m_val = pcall(reaper.SNM_GetIntConfigVar, "projmetroen", -1)
            if ok_m and m_val and m_val >= 0 then
                -- Bit 0 (1): Enable metronome, Bit 2 (4): Run during recording, Bit 4 (16): Count-in before recording
                pcall(reaper.SNM_SetIntConfigVar, "projmetroen", m_val | 1 | 4 | 16)
            end
        end
    else
        if metro_state then
            reaper.Main_OnCommand(40364, 0)
        end
        if reaper.APIExists("SNM_GetIntConfigVar") and reaper.APIExists("SNM_SetIntConfigVar") then
            local ok_m, m_val = pcall(reaper.SNM_GetIntConfigVar, "projmetroen", -1)
            if ok_m and m_val and m_val >= 0 then
                -- Clear Bit 0 (1) and Bit 4 (16)
                pcall(reaper.SNM_SetIntConfigVar, "projmetroen", m_val & (~17))
            end
        end
    end
    reaper.TrackList_AdjustWindows(false)
    reaper.UpdateTimeline()
    refresh_open_metro_dialog(state)
end

function RecordModal.render(ctx, state, midi_service, project_tracks, active_tracks_data)
    if not state.show_record_modal then return end

    local metro_is_open = is_hwnd_open(state._metro_hwnd) or ((state._metro_pin_frames or 0) > 0) or ((state._metro_open_delay or 0) > 0)
    if not is_hwnd_open(state._metro_hwnd) and (state._metro_pin_frames or 0) <= 0 and (state._metro_open_delay or 0) <= 0 then
        state._metro_hwnd = nil
    end

    local flags = reaper.ImGui_WindowFlags_NoCollapse()
    if not metro_is_open and reaper.APIExists("ImGui_WindowFlags_TopMost") then
        flags = flags | reaper.ImGui_WindowFlags_TopMost()
    end
    if state.focus_record_modal then
        if reaper.APIExists("ImGui_SetNextWindowFocus") then
            reaper.ImGui_SetNextWindowFocus(ctx)
        end
        state.focus_record_modal = nil
    end

    if reaper.APIExists("ImGui_SetNextWindowSizeConstraints") then
        reaper.ImGui_SetNextWindowSizeConstraints(ctx, 590, 620, 1200, 1600)
    end
    reaper.ImGui_SetNextWindowSize(ctx, 620, 810, reaper.ImGui_Cond_FirstUseEver())
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

        -- Clean up any leftover Pre-roll on Play (41818) when Pre-roll on Record (41819) is disabled
        local preroll_active = (reaper.GetToggleCommandState(41819) == 1)
        if not preroll_active and reaper.GetToggleCommandState(41818) == 1 then
            reaper.Main_OnCommand(41818, 0)
            if reaper.APIExists("SNM_GetIntConfigVar") and reaper.APIExists("SNM_SetIntConfigVar") then
                local ok_p, p_val = pcall(reaper.SNM_GetIntConfigVar, "preroll", -1)
                if ok_p and p_val and p_val >= 0 then
                    pcall(reaper.SNM_SetIntConfigVar, "preroll", p_val & (~1))
                end
            end
            refresh_open_metro_dialog(state)
        end

        local changed_preroll, new_preroll_val = reaper.ImGui_Checkbox(ctx, "Pre-roll before Recording##PrerollToggle", preroll_active)
        if changed_preroll then
            set_reaper_preroll(state, new_preroll_val)
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
                    refresh_open_metro_dialog(state)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        -- Metronome & Count-in on Record (Action 40364 + projmetroen bitfield)
        local countin_active = (reaper.GetToggleCommandState(40364) == 1)
        local changed_ci, new_ci_val = reaper.ImGui_Checkbox(ctx, "Metronome Count-in before Recording##CountinToggle", countin_active)
        if changed_ci then
            set_reaper_countin(state, new_ci_val)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Audible metronome / count-in clicks during and before recording.")
        end

        reaper.ImGui_SameLine(ctx, 0, 16)
        if reaper.ImGui_Button(ctx, "⚙ Metronome Settings...##MetroBtn", 170, 22) then
            state._metro_open_delay = 2
            state._metro_pin_frames = 30
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Opens REAPER's native Metronome and Pre-roll settings dialog on top of all windows.")
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

        -- Auto-Divisi Recording Mode (Multi-Track Register & Polyphonic Voice Distribution)
        local chk_div, new_div = reaper.ImGui_Checkbox(ctx, "🎼 Auto-Divisi Mode (Distribute Simultaneous Notes & Registers across Armed Tracks)##RecAutoDivisi", state.rec_auto_divisi == true)
        if chk_div then
            state.rec_auto_divisi = new_div
            require("state").save_settings(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "When 2 or more tracks are armed, chords & polyphonic lines played on your MIDI keyboard are automatically distributed across the armed instruments:\n• Low Register → Cello & Double Bass\n• Mid Register → Viola / Horns\n• High Register → Violin 1 & Violin 2")
        end

        if state.rec_auto_divisi then
            reaper.ImGui_Text(ctx, "Distribution:")
            reaper.ImGui_SameLine(ctx, 0, 8)
            reaper.ImGui_SetNextItemWidth(ctx, 360)
            local div_mode = state.rec_auto_divisi_mode or "smart_register"
            local div_mode_lbl = (div_mode == "top_down")
                and "Top-Down Voice Split (1st Note → Track #1, 2nd → #2, ...)"
                or "Smart Register & Voice Split (High → Vln 1/2 • Mid → Vla • Low → Vc/Cb)"
            if reaper.ImGui_BeginCombo(ctx, "##RecAutoDivisiModeCombo", div_mode_lbl) then
                if reaper.ImGui_Selectable(ctx, "Smart Register & Voice Split (High → Vln 1/2 • Mid → Vla • Low → Vc/Cb)", div_mode == "smart_register") then
                    state.rec_auto_divisi_mode = "smart_register"
                    require("state").save_settings(state)
                end
                if reaper.ImGui_Selectable(ctx, "Top-Down Voice Split (1st Note → Track #1, 2nd → #2, ...)", div_mode == "top_down") then
                    state.rec_auto_divisi_mode = "top_down"
                    require("state").save_settings(state)
                end
                reaper.ImGui_EndCombo(ctx)
            end

            -- Tick-Based Chord Attack & Legato Transition Tolerance
            local div_tol = state.rec_divisi_tol_ticks or 45
            reaper.ImGui_Text(ctx, string.format("Divisi Chord & Transition Tolerance: ±%d Ticks", div_tol))
            reaper.ImGui_SetNextItemWidth(ctx, 240)
            local chg_dtol, new_dtol = reaper.ImGui_SliderInt(ctx, "##RecDivisiTolSlider", div_tol, 10, 160, "±%d Ticks")
            if chg_dtol then
                state.rec_divisi_tol_ticks = new_dtol
                require("state").save_settings(state)
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Tick-Based Chord & Legato Transition Guard (960 PPQ):\n• Groups chord finger attacks within ±N Ticks into one simultaneous chord\n• Trims brief legato finger-release overlaps (≤ N Ticks) when switching notes so melodies stay on the same instrument without false Divisi jumps\n• Filters out accidental micro-splinter notes (< N Ticks) during hand transitions")
            end

            reaper.ImGui_SameLine(ctx, 0, 8)
            local function dtol_btn(val)
                if reaper.ImGui_Button(ctx, string.format("%d##DTol%d", val, val), 36, 22) then
                    state.rec_divisi_tol_ticks = val
                    require("state").save_settings(state)
                end
                reaper.ImGui_SameLine(ctx, 0, 4)
            end
            dtol_btn(20)
            dtol_btn(35)
            dtol_btn(45)
            dtol_btn(60)
            dtol_btn(90)
            reaper.ImGui_NewLine(ctx)
        end

        reaper.ImGui_Spacing(ctx)

        local _, armed_by_guid = nil, {}
        if state.rec_auto_divisi and RecordQuantizeService.get_armed_tracks_divisi_profile then
            _, armed_by_guid = RecordQuantizeService.get_armed_tracks_divisi_profile(state)
        end

        -- Track Selection List Child Window (Dynamically expands with window height; Footer stays pinned at bottom!)
        local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        local footer_reserve_h = 48
        local child_h = math.max(95, avail_h - footer_reserve_h)
        local child_flags = reaper.APIExists("ImGui_ChildFlags_Border") and reaper.ImGui_ChildFlags_Border() or 1
        if reaper.ImGui_BeginChild(ctx, "##RecordTracksChild", 0, child_h, child_flags) then
            local inner_avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
            local right_btn_x = math.max(330, inner_avail_w - 195)
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
                    local tguid = reaper.GetTrackGUID(trk)
                    local is_armed = AudioPreview.is_track_user_armed(trk)
                    RecordQuantizeService._tracked_armed_guids = RecordQuantizeService._tracked_armed_guids or {}
                    if not (AudioPreview.track_restore and AudioPreview.track_restore[trk]) then
                        if is_armed then
                            if tguid then RecordQuantizeService._tracked_armed_guids[tguid] = true end
                        elseif tguid and RecordQuantizeService._tracked_armed_guids[tguid] then
                            -- Track was disarmed externally in REAPER TCP/MCP -> turn off monitoring
                            RecordQuantizeService._tracked_armed_guids[tguid] = nil
                            reaper.SetMediaTrackInfo_Value(trk, "I_RECMON", 0)
                        end
                    end
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

                    -- Show Auto-Divisi Voice Rank & Register Badge when armed and Auto-Divisi is active
                    if is_armed and state.rec_auto_divisi and tguid and armed_by_guid[tguid] then
                        local prof = armed_by_guid[tguid]
                        reaper.ImGui_SameLine(ctx, 0, 8)
                        reaper.ImGui_TextColored(ctx, 0xF1C40FFF, string.format("[#%d %s]", prof.voice_rank or 1, prof.role_label or "Voice"))
                    end

                    -- Per-track MIDI Input status button on the right
                    reaper.ImGui_SameLine(ctx, right_btn_x)
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
                                reaper.SetMediaTrackInfo_Value(trk, "I_RECMON", (is_armed and state.rec_auto_monitor ~= false) and 1 or 0)
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

    -- Deferred Metronome Settings opening & TopMost Z-order pinning (executes after ReaImGui frame completes)
    if state._metro_open_delay and state._metro_open_delay > 0 then
        state._metro_open_delay = state._metro_open_delay - 1
        if state._metro_open_delay == 0 then
            reaper.defer(function()
                local main_hwnd = reaper.GetMainHwnd()
                local notator_hwnd = state._notator_hwnd
                local existing = nil
                if is_hwnd_open(state._metro_hwnd) then
                    existing = state._metro_hwnd
                elseif reaper.APIExists("JS_Window_FindTop") then
                    local h = reaper.JS_Window_FindTop("Metronome", false) or reaper.JS_Window_FindTop("Metronom", false)
                    existing = resolve_top_dialog_hwnd(h, main_hwnd, notator_hwnd)
                end

                if existing and is_hwnd_open(existing) then
                    state._metro_hwnd = existing
                    pin_metro_hwnd_topmost(existing, true)
                else
                    reaper.Main_OnCommand(40363, 0)
                    local hwnd = find_metro_hwnd(state)
                    if not hwnd then
                        -- Action 40363 is a toggle; if it just closed a hidden window, call it once more to re-open
                        reaper.Main_OnCommand(40363, 0)
                        hwnd = find_metro_hwnd(state)
                    end
                    if hwnd then
                        state._metro_hwnd = hwnd
                        pin_metro_hwnd_topmost(hwnd, true)
                    end
                end
            end)
        end
    elseif state._metro_pin_frames and state._metro_pin_frames > 0 then
        state._metro_pin_frames = state._metro_pin_frames - 1
        local do_focus = (state._metro_pin_frames >= 22)
        reaper.defer(function()
            if not is_hwnd_open(state._metro_hwnd) then
                state._metro_hwnd = find_metro_hwnd(state)
            end
            if state._metro_hwnd then
                pin_metro_hwnd_topmost(state._metro_hwnd, do_focus)
            end
        end)
    elseif is_hwnd_open(state._metro_hwnd) then
        if reaper.ImGui_IsMouseClicked(ctx, 0) or reaper.ImGui_IsMouseReleased(ctx, 0) then
            local h = state._metro_hwnd
            reaper.defer(function()
                pin_metro_hwnd_topmost(h, false)
            end)
        end
    end
end

return RecordModal

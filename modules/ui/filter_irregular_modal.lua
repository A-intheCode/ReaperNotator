-- ==============================================================================
-- REAPER Native Notator - Module: FilterIrregularModal
-- Modal dialog for filtering and isolating irregular notes into Voice 16
-- ==============================================================================

local FilterNotesService = require("services.filter_notes_service")

local FilterIrregularModal = {}

-- Cache structure to avoid scanning 50,000 notes on every ImGui frame
local cached_stats = nil
local last_scan_sig = ""

local function make_scan_signature(state)
    return string.format("%s_%s_%d_%s_%d",
        tostring(state.filter_irregular_scope or "project"),
        tostring(state.filter_irregular_grid_qn or 0.125),
        state.filter_irregular_tolerance_ticks or 10,
        tostring(state.filter_irregular_include_triplets or false),
        state.filter_irregular_target_voice or 16
    )
end

function FilterIrregularModal.render(ctx, state, midi_service, active_tracks_data)
    if not state.show_filter_irregular_modal then
        cached_stats = nil
        return
    end

    local flags = reaper.ImGui_WindowFlags_NoCollapse()
    if reaper.APIExists("ImGui_WindowFlags_TopMost") then
        flags = flags | reaper.ImGui_WindowFlags_TopMost()
    end
    if state.focus_filter_irregular_modal then
        if reaper.APIExists("ImGui_SetNextWindowFocus") then
            reaper.ImGui_SetNextWindowFocus(ctx)
        end
        state.focus_filter_irregular_modal = nil
    end

    reaper.ImGui_SetNextWindowSize(ctx, 500, 520, reaper.ImGui_Cond_FirstUseEver())
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "🔍 Filter irregular Notes###FilterIrregularModalWindow", true, flags)

    if not s_open then
        state.show_filter_irregular_modal = false
        cached_stats = nil
    end

    if s_vis then
        local current_sig = make_scan_signature(state)
        if not cached_stats or current_sig ~= last_scan_sig then
            cached_stats = FilterNotesService.scan(state, nil, active_tracks_data)
            last_scan_sig = current_sig
        end

        local stats = cached_stats or { total_items = 0, total_notes = 0, irregular_count = 0, already_in_target_voice = 0 }
        local target_voice = state.filter_irregular_target_voice or 16

        -- ------------------------------------------------------------------
        -- 1. LIVE STATUS HEADER
        -- ------------------------------------------------------------------
        if stats.irregular_count > 0 then
            reaper.ImGui_TextColored(ctx, 0xE67E22FF, string.format("⚡ %d irregular note(s) found across %d MIDI item(s)", stats.irregular_count, stats.total_items))
        else
            reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("✓ All %d note(s) in scope land within grid tolerance", stats.total_notes))
        end

        reaper.ImGui_TextDisabled(ctx, string.format("Total notes scanned: %d | Already in Voice %d: %d", stats.total_notes, target_voice, stats.already_in_target_voice))

        reaper.ImGui_SameLine(ctx, 0, 16)
        if reaper.ImGui_SmallButton(ctx, "↻ Refresh##RefreshScan") then
            cached_stats = FilterNotesService.scan(state, nil, active_tracks_data)
            last_scan_sig = make_scan_signature(state)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Rescan MIDI takes in scope.")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 2. SCOPE SELECTION
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Scope (Where to search):")
        local scope = state.filter_irregular_scope or "project"

        if reaper.ImGui_RadioButton(ctx, "Entire Project##ScopeProj", scope == "project") then
            state.filter_irregular_scope = "project"
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Scan all MIDI items on all tracks in the entire project.")
        end

        reaper.ImGui_SameLine(ctx, 0, 20)
        if reaper.ImGui_RadioButton(ctx, "Active Track##ScopeTrk", scope == "track") then
            state.filter_irregular_scope = "track"
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Scan all MIDI items on the currently active/focused track.")
        end

        if reaper.ImGui_RadioButton(ctx, "Selected Media Items##ScopeItems", scope == "items") then
            state.filter_irregular_scope = "items"
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Scan only Media Items currently selected in the REAPER arrange view.")
        end

        reaper.ImGui_SameLine(ctx, 0, 20)
        local sel_cnt = (state.count_selected_notes and state:count_selected_notes()) or 0
        local sel_label = string.format("Selected Notes (%d)##ScopeSel", sel_cnt)
        if reaper.ImGui_RadioButton(ctx, sel_label, scope == "selection") then
            state.filter_irregular_scope = "selection"
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Filter only notes currently selected in the notation score view.")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 3. GRID SUBDIVISION & TRIPLETS
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Regular Grid Subdivision:")
        reaper.ImGui_SetNextItemWidth(ctx, 220)

        local cur_label = state.filter_irregular_grid_label or "1/32"
        for _, g in ipairs(FilterNotesService.GRIDS) do
            if math.abs((state.filter_irregular_grid_qn or 0.125) - g.qn) < 0.001 then
                cur_label = g.label
                break
            end
        end

        if reaper.ImGui_BeginCombo(ctx, "##FilterGridCombo", cur_label) then
            for _, g in ipairs(FilterNotesService.GRIDS) do
                local is_sel = (math.abs((state.filter_irregular_grid_qn or 0.125) - g.qn) < 0.001)
                if reaper.ImGui_Selectable(ctx, g.label, is_sel) then
                    state.filter_irregular_grid_qn = g.qn
                    state.filter_irregular_grid_label = g.label:match("^(%S+)")
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Standard 1/32 covers whole, half, quarter, 8th, 16th, and 32nd notes.\nNotes that do not align with this division will be flagged as irregular.")
        end

        reaper.ImGui_SameLine(ctx, 0, 16)
        local trip = state.filter_irregular_include_triplets or false
        local chg_trip, new_trip = reaper.ImGui_Checkbox(ctx, "Include Triplets##TripCb", trip)
        if chg_trip then
            state.filter_irregular_include_triplets = new_trip
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "When enabled, triplet subdivisions (1/12, 1/24, 1/48) are also treated as regular.")
        end

        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 4. TIMING TOLERANCE
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Tolerance Threshold:")
        local tol = state.filter_irregular_tolerance_ticks or 10
        reaper.ImGui_SetNextItemWidth(ctx, 260)
        local chg_tol, new_tol = reaper.ImGui_SliderInt(ctx, "##ToleranceSlider", tol, 0, 50, "%d Ticks")
        if chg_tol then
            state.filter_irregular_tolerance_ticks = new_tol
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Tolerance window in PPQ ticks (~960 ticks = 1 quarter note).\n0 = Exact mathematical snap required.\n10-15 = Natural humanization tolerance (recommended for live recordings).")
        end

        reaper.ImGui_SameLine(ctx, 0, 8)
        if reaper.ImGui_Button(ctx, "Strict (0)##Tol0", 65, 20) then state.filter_irregular_tolerance_ticks = 0 end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "10 Ticks##Tol10", 60, 20) then state.filter_irregular_tolerance_ticks = 10 end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "25 Ticks##Tol25", 60, 20) then state.filter_irregular_tolerance_ticks = 25 end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 5. TARGET VOICE
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Target Voice for Irregular Notes:")
        reaper.ImGui_SetNextItemWidth(ctx, 260)
        local chg_v, new_v = reaper.ImGui_SliderInt(ctx, "##TargetVoiceSlider", target_voice, 1, 16, "Voice %d")
        if chg_v then
            state.filter_irregular_target_voice = new_v
            target_voice = new_v
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Voice 16 (MIDI channel 15) is the recommended isolated voice for irregular / humanized notes.")
        end

        reaper.ImGui_SameLine(ctx, 0, 8)
        if reaper.ImGui_Button(ctx, "Default: Voice 16##V16Btn", 120, 20) then
            state.filter_irregular_target_voice = 16
            target_voice = 16
        end

        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 6. ADDITIONAL OPTIONS
        -- ------------------------------------------------------------------
        local mute_opt = state.filter_irregular_also_mute or false
        local chg_mute, new_mute = reaper.ImGui_Checkbox(ctx, "Mute irregular notes after moving##MuteCb", mute_opt)
        if chg_mute then state.filter_irregular_also_mute = new_mute end

        reaper.ImGui_SameLine(ctx, 0, 20)
        local sel_opt = state.filter_irregular_also_select or false
        local chg_sel, new_sel = reaper.ImGui_Checkbox(ctx, "Select irregular notes##SelCb", sel_opt)
        if chg_sel then state.filter_irregular_also_select = new_sel end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 7. ACTION BUTTONS
        -- ------------------------------------------------------------------
        local btn_label = string.format("⚡ Reassign %d note(s) to Voice %d", stats.irregular_count, target_voice)
        local has_notes = (stats.irregular_count > 0)

        if not has_notes then
            reaper.ImGui_BeginDisabled(ctx)
        end

        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
        if reaper.ImGui_Button(ctx, btn_label, 260, 32) then
            local moved = FilterNotesService.apply(state, nil, active_tracks_data)
            cached_stats = FilterNotesService.scan(state, nil, active_tracks_data)
            last_scan_sig = make_scan_signature(state)
        end
        reaper.ImGui_PopStyleColor(ctx, 2)

        if not has_notes then
            reaper.ImGui_EndDisabled(ctx)
        end

        reaper.ImGui_SameLine(ctx, 0, 16)
        if reaper.ImGui_Button(ctx, "Close##CloseFilterModal", 100, 32) then
            state.show_filter_irregular_modal = false
            cached_stats = nil
        end
    end

    reaper.ImGui_End(ctx)
end

return FilterIrregularModal


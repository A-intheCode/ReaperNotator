-- ==============================================================================
-- REAPER Native Notator - Module: QuantizeModal
-- Quantize dialog for selected or all notes (like in REAPER)
-- ==============================================================================

local QuantizeModal = {}

local GRIDS = {
    { label = "1/1  (Whole)",   qn = 4.0 },
    { label = "1/2  (Half)",    qn = 2.0 },
    { label = "1/4  (Quarter)", qn = 1.0 },
    { label = "1/8  (Eighth)",  qn = 0.5 },
    { label = "1/16 (16th)",    qn = 0.25 },
    { label = "1/32 (32nd)",    qn = 0.125 },
    { label = "1/64 (64th)",    qn = 0.0625 },
}

function QuantizeModal.render(ctx, state, midi_service, active_tracks_data)
    if not state.show_quantize_modal then return end

    reaper.ImGui_SetNextWindowSize(ctx, 480, 440, reaper.ImGui_Cond_FirstUseEver())
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "⚡ Quantize Notes###QuantizeModalWindow", true)

    if not s_open then
        state.show_quantize_modal = false
        reaper.ImGui_End(ctx)
        return
    end

    if s_vis then
        local sel_cnt = state:count_selected_notes()

        -- 1. Status Header
        if sel_cnt > 0 then
            reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("✓ %d note(s) selected for quantization", sel_cnt))
        else
            reaper.ImGui_TextColored(ctx, 0xF39C12FF, "ℹ No notes selected – affects entire active take")
        end
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- 2. Grid Selection
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Grid:")
        reaper.ImGui_SetNextItemWidth(ctx, 220)
        local cur_label = state.quantize_grid_label or "1/16"
        for _, g in ipairs(GRIDS) do
            if math.abs((state.quantize_grid_qn or 0.25) - g.qn) < 0.001 then
                cur_label = g.label
                break
            end
        end

        if reaper.ImGui_BeginCombo(ctx, "##QuantizeGridCombo", cur_label) then
            for _, g in ipairs(GRIDS) do
                local is_sel = (math.abs((state.quantize_grid_qn or 0.25) - g.qn) < 0.001)
                if reaper.ImGui_Selectable(ctx, g.label, is_sel) then
                    state.quantize_grid_qn = g.qn
                    state.quantize_grid_label = g.label:match("^(%S+)")
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        -- Grid type (Straight, Triplet, Dotted)
        reaper.ImGui_SameLine(ctx, 0, 16)
        reaper.ImGui_SetNextItemWidth(ctx, 160)
        local cur_type = state.quantize_grid_type or "straight"
        local type_names = { straight = "Straight", triplet = "Triplet", dotted = "Dotted" }
        if reaper.ImGui_BeginCombo(ctx, "##QuantizeTypeCombo", type_names[cur_type] or "Straight") then
            if reaper.ImGui_Selectable(ctx, "Straight", cur_type == "straight") then state.quantize_grid_type = "straight" end
            if reaper.ImGui_Selectable(ctx, "Triplet", cur_type == "triplet") then state.quantize_grid_type = "triplet" end
            if reaper.ImGui_Selectable(ctx, "Dotted", cur_type == "dotted") then state.quantize_grid_type = "dotted" end
            reaper.ImGui_EndCombo(ctx)
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- 3. What to quantize (Target)
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "What to quantize:")
        local target = state.quantize_target or "position"
        if reaper.ImGui_RadioButton(ctx, "Note Start (Position)", target == "position") then
            state.quantize_target = "position"
        end
        reaper.ImGui_SameLine(ctx, 0, 20)
        if reaper.ImGui_RadioButton(ctx, "Note End (Length)", target == "length") then
            state.quantize_target = "length"
        end
        reaper.ImGui_SameLine(ctx, 0, 20)
        if reaper.ImGui_RadioButton(ctx, "Position & Length", target == "both") then
            state.quantize_target = "both"
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- 4. Strength
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Strength:")
        local strength = state.quantize_strength or 100
        reaper.ImGui_SetNextItemWidth(ctx, 280)
        local changed_str, new_str = reaper.ImGui_SliderInt(ctx, "##StrengthSlider", strength, 0, 100, "%d %%")
        if changed_str then state.quantize_strength = new_str end

        reaper.ImGui_SameLine(ctx, 0, 10)
        if reaper.ImGui_Button(ctx, "50%##Str50", 42, 22) then state.quantize_strength = 50 end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "80%##Str80", 42, 22) then state.quantize_strength = 80 end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "100%##Str100", 46, 22) then state.quantize_strength = 100 end

        reaper.ImGui_Spacing(ctx)

        -- 5. Swing
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Swing (Groove):")
        local swing = state.quantize_swing or 0
        reaper.ImGui_SetNextItemWidth(ctx, 280)
        local changed_sw, new_sw = reaper.ImGui_SliderInt(ctx, "##SwingSlider", swing, 0, 100, "%d %%")
        if changed_sw then state.quantize_swing = new_sw end

        reaper.ImGui_SameLine(ctx, 0, 10)
        if reaper.ImGui_Button(ctx, "Off##Sw0", 42, 22) then state.quantize_swing = 0 end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "33%##Sw33", 42, 22) then state.quantize_swing = 33 end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "50%##Sw50", 46, 22) then state.quantize_swing = 50 end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- 6. Scope
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Apply to:")
        local scope = state.quantize_scope or "selected"
        if reaper.ImGui_RadioButton(ctx, "Selected notes only", scope == "selected") then
            state.quantize_scope = "selected"
        end
        reaper.ImGui_SameLine(ctx, 0, 24)
        if reaper.ImGui_RadioButton(ctx, "All notes in take", scope == "all") then
            state.quantize_scope = "all"
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Spacing(ctx)

        -- 7. Action buttons
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
        if reaper.ImGui_Button(ctx, "⚡ Quantize", 160, 32) then
            midi_service.quantize_notes(state)
        end
        reaper.ImGui_PopStyleColor(ctx, 2)

        reaper.ImGui_SameLine(ctx, 0, 12)
        if reaper.ImGui_Button(ctx, "Close", 100, 32) then
            state.show_quantize_modal = false
        end

        reaper.ImGui_SameLine(ctx, 0, 16)
        reaper.ImGui_TextDisabled(ctx, "(Shortcut: Q)")

        reaper.ImGui_End(ctx)
    end
end

return QuantizeModal

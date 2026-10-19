-- ==============================================================================
-- REAPER Native Notator - Module: ScaleModal
-- Dialog to transpose selected notes into any scale or mode
-- ==============================================================================

local ScaleService = require("services.scale_service")
local Engraver = require("rendering.engraver")

local ScaleModal = {}

function ScaleModal.render(ctx, state)
    if not state.show_scale_modal then return end

    local flags = reaper.ImGui_WindowFlags_NoCollapse()
    if reaper.APIExists("ImGui_WindowFlags_TopMost") then
        flags = flags | reaper.ImGui_WindowFlags_TopMost()
    end
    if state.focus_scale_modal then
        if reaper.APIExists("ImGui_SetNextWindowFocus") then
            reaper.ImGui_SetNextWindowFocus(ctx)
        end
        state.focus_scale_modal = nil
    end

    reaper.ImGui_SetNextWindowSize(ctx, 480, 440, reaper.ImGui_Cond_FirstUseEver())
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "🎹 Scale & Key Signature###ScaleModalWindow", true, flags)

    if not s_open then
        state.show_scale_modal = false
    end

    if s_vis then
        local sel_cnt = state:count_selected_notes()
        if sel_cnt == 0 and state.selected_note then
            sel_cnt = 1
        end

        -- 1. Status Header
        if sel_cnt > 0 then
            reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("✓ %d note(s) selected for scale transposition", sel_cnt))
        else
            reaper.ImGui_TextColored(ctx, 0x3498DBFF, "ℹ Set active Key Signature for note entry, or select notes to transpose.")
        end
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- 2. Root Note Selection
        state.scale_modal_root = state.scale_modal_root or 0
        state.scale_modal_type = state.scale_modal_type or "major"

        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Key / Root Note:")
        local btn_w = 32
        for i, r_name in ipairs(ScaleService.ROOT_NAMES) do
            local r_idx = i - 1
            local is_cur = (state.scale_modal_root == r_idx)
            if is_cur then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF9F1CFF)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x111111FF)
            end
            if reaper.ImGui_Button(ctx, r_name .. "##Root" .. r_idx, btn_w, 24) then
                state.scale_modal_root = r_idx
            end
            if is_cur then
                reaper.ImGui_PopStyleColor(ctx, 2)
            end
            if i % 6 ~= 0 and i < #ScaleService.ROOT_NAMES then
                reaper.ImGui_SameLine(ctx, 0, 4)
            else
                reaper.ImGui_Spacing(ctx)
            end
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- 3. Scale / Mode Selection
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Scale / Mode:")
        local cur_scale_def = ScaleService.SCALES[state.scale_modal_type] or ScaleService.SCALES["major"]

        reaper.ImGui_SetNextItemWidth(ctx, -1)
        if reaper.ImGui_BeginCombo(ctx, "##ScaleTypeCombo", cur_scale_def.name) then
            for _, skey in ipairs(ScaleService.SCALE_ORDER) do
                local sdef = ScaleService.SCALES[skey]
                local is_sel = (state.scale_modal_type == skey)
                if reaper.ImGui_Selectable(ctx, sdef.name, is_sel) then
                    state.scale_modal_type = skey
                end
                if is_sel then
                    reaper.ImGui_SetItemDefaultFocus(ctx)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        -- 4. Scale Preview / Note Names in Scale (key-signature-aware spelling)
        local kidx = ScaleService.get_key_signature_for_scale(state.scale_modal_root, state.scale_modal_type)
        local root_name = (Engraver.get_pitch_display_name and Engraver.get_pitch_display_name(60 + state.scale_modal_root, nil, kidx)) or ScaleService.ROOT_NAMES[state.scale_modal_root + 1]
        local scale_notes = {}
        for _, iv in ipairs(cur_scale_def.intervals) do
            local pc = (state.scale_modal_root + iv) % 12
            local n_str = (Engraver.get_pitch_display_name and Engraver.get_pitch_display_name(60 + pc, nil, kidx)) or ScaleService.ROOT_NAMES[pc + 1]
            table.insert(scale_notes, n_str)
        end
        local notes_str = table.concat(scale_notes, " - ")

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextDisabled(ctx, "Notes in Scale:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, 0x3498DBFF, string.format("%s %s:", root_name, cur_scale_def.name))
        reaper.ImGui_TextColored(ctx, 0xF1C40FFF, "  " .. notes_str)

        if cur_scale_def.desc then
            reaper.ImGui_TextDisabled(ctx, "  " .. cur_scale_def.desc)
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- 5. Action Buttons (Cancel / Set Key Signature / Apply Scale Transpose)
        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local btn_w_3 = (avail_w - 16) / 3.0
        if reaper.ImGui_Button(ctx, "Cancel", btn_w_3, 28) then
            state.show_scale_modal = false
        end

        reaper.ImGui_SameLine(ctx, 0, 8)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2980B9FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3498DBFF)
        if reaper.ImGui_Button(ctx, "🎼 Set Key Signature", btn_w_3, 28) then
            ScaleService.apply_scale_as_key_signature(state, state.scale_modal_root, state.scale_modal_type)
            state.show_scale_modal = false
        end
        reaper.ImGui_PopStyleColor(ctx, 2)

        reaper.ImGui_SameLine(ctx, 0, 8)
        local can_apply = (sel_cnt > 0)
        if not can_apply then
            reaper.ImGui_BeginDisabled(ctx)
        else
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
        end

        if reaper.ImGui_Button(ctx, "🎹 Transpose Notes", btn_w_3, 28) then
            ScaleService.apply_scale_as_key_signature(state, state.scale_modal_root, state.scale_modal_type)
            local ok = ScaleService.transpose_selection_to_scale(state, state.scale_modal_root, state.scale_modal_type)
            if ok then
                state.show_scale_modal = false
            end
        end

        if not can_apply then
            reaper.ImGui_EndDisabled(ctx)
        else
            reaper.ImGui_PopStyleColor(ctx, 2)
        end
    end

    reaper.ImGui_End(ctx)
end

return ScaleModal

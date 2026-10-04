-- ==============================================================================
-- REAPER Native Notator - Module: ToolsDrawer
-- Right drawer for Quick Score Tools: Make Notes Legato, Auto Voice,
-- Arpeggio Strums, Quantize Tools, Rehearsal Marks, and Navigation (D.C., D.S., Segno, Coda, Fine)
-- ==============================================================================

local RehearsalMarkService = require("services.rehearsal_mark_service")

local ToolsDrawer = {
    custom_rehearsal_text = "",
    target_bar_offset = 0
}

function ToolsDrawer.render(ctx, state, midi_service, active_tracks_data, width, height, child_border, sidebar_flags, font_music, font_main)
    if not state.show_tools_drawer then return end

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x1A1C22FF)

    if reaper.ImGui_BeginChild(ctx, "ToolsDrawer", width, height, child_border, sidebar_flags) then
        -- ------------------------------------------------------------------
        -- 1. HEADER
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0x9B59B6FF, "🛠 SCORE TOOLS")
        reaper.ImGui_SameLine(ctx, width - 26)
        if reaper.ImGui_Button(ctx, "✕##CloseToolsDrawer", 20, 20) then
            state.show_tools_drawer = false
        end
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 2. NOTE ACTIONS (Top Level: Legato & Auto Voice)
        -- ------------------------------------------------------------------
        local sel_cnt = (state.count_selected_notes and state:count_selected_notes()) or 0
        local legato_btn_lbl = (sel_cnt > 0)
            and string.format("⌒ Make Notes Legato (%d sel)", sel_cnt)
            or "⌒ Make Notes Legato"

        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2980B9FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3498DBFF)
        if reaper.ImGui_Button(ctx, legato_btn_lbl, width - 24, 28) then
            if midi_service and midi_service.make_legato then
                midi_service.make_legato(state)
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Make Notes Legato:\nExtends selected notes to the start of the next note (or whole track if none selected).")
        end

        reaper.ImGui_Spacing(ctx)

        -- Auto Voice on Selection Button
        if reaper.ImGui_Button(ctx, "⚡ Auto Voice on Selection", width - 24, 26) then
            if midi_service and midi_service.auto_split_selection_to_voices then
                midi_service.auto_split_selection_to_voices(state, nil)
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Auto Voice on Selection:\nAutomatically splits selected notes/chords into different voices 1-16.\n(If no notes are selected, processes entire track).")
        end

        reaper.ImGui_Spacing(ctx)

        -- Auto Voice Button (Whole Track)
        if reaper.ImGui_Button(ctx, "⚡ Auto Voice", width - 24, 26) then
            if midi_service and midi_service.auto_split_overlaps_to_voices then
                local cur_trk = state.focused_track or (active_tracks_data and active_tracks_data[1] and active_tracks_data[1].track)
                midi_service.auto_split_overlaps_to_voices(state, cur_trk)
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Auto Voice (Whole Track):\nDetects note overlaps across entire track and splits them into voices 1-16.")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 3. ARPEGGIO (CHORD STRUM)
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0x5DADE2FF, "Arpeggio (Chord Strum):")
        local btn_w = (width - 32) / 3
        if reaper.ImGui_Button(ctx, "↑ Roll Up##arp_up", btn_w, 24) then
            if midi_service and midi_service.toggle_arpeggio_on_selected then
                midi_service.toggle_arpeggio_on_selected(state, "up")
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Apply upward arpeggiated strum (~18 ticks micro-offset per note)")
        end

        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "↓ Down##arp_down", btn_w, 24) then
            if midi_service and midi_service.toggle_arpeggio_on_selected then
                midi_service.toggle_arpeggio_on_selected(state, "down")
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Apply downward arpeggiated strum")
        end

        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "✕ Snap##arp_snap", btn_w, 24) then
            if midi_service and midi_service.toggle_arpeggio_on_selected then
                midi_service.toggle_arpeggio_on_selected(state, "up")
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Remove arpeggio and snap notes back to chord downbeat")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 4. QUANTIZE TOOLS
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, "⚡ Quantize Tools:")

        -- Open Quantize Dialog (Q)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
        if reaper.ImGui_Button(ctx, "⚡ Quantize Notes Dialog (Q)", width - 24, 26) then
            state.show_quantize_modal = true
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        if reaper.ImGui_IsItemHovered(ctx) then
            local note_cnt = (state.count_selected_notes and state:count_selected_notes()) or 0
            reaper.ImGui_SetTooltip(ctx, string.format("Open Quantize Dialog (Q)\nSelected notes: %d", note_cnt))
        end

        reaper.ImGui_Spacing(ctx)

        -- Quick Quantize with Current Grid
        local cur_grid_lbl = state.quantize_grid_label or "1/16"
        if reaper.ImGui_Button(ctx, string.format("⚡ Quick Quantize (%s)", cur_grid_lbl), width - 24, 24) then
            if midi_service and midi_service.quantize_notes then
                midi_service.quantize_notes(state)
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, string.format("Immediately quantize selected notes (or active take) to %s grid.", cur_grid_lbl))
        end

        reaper.ImGui_Spacing(ctx)

        -- Display Quantize Toggle & Grid Combo
        local dq_val = (state.display_quantize == true)
        local dq_chg, new_dq = reaper.ImGui_Checkbox(ctx, "Display Quantize (Visual Snap)", dq_val)
        if dq_chg then
            state.display_quantize = new_dq
            state.status_msg = state.display_quantize and "Display Quantize ON – notes visually snap to grid" or "Display Quantize OFF"
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Display Quantize:\nVisually aligns notes to grid in notation view without modifying actual MIDI timing.")
        end

        if state.display_quantize then
            reaper.ImGui_Text(ctx, "  Visual Grid:")
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_PushItemWidth(ctx, 80)
            if reaper.ImGui_BeginCombo(ctx, "##dq_drawer_grid", state.display_quantize_label or "1/16") then
                local grids = {
                    { "1/1",  4.0 },
                    { "1/2",  2.0 },
                    { "1/4",  1.0 },
                    { "1/8",  0.5 },
                    { "1/16", 0.25 },
                    { "1/32", 0.125 },
                }
                for _, g in ipairs(grids) do
                    local is_sel = (math.abs((state.display_quantize_grid or 0.25) - g[2]) < 0.001)
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

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 5. REHEARSAL MARKS & NAVIGATION
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xE67E22FF, "🔖 Rehearsal Marks & Navigation")
        reaper.ImGui_Spacing(ctx)

        -- Show/Hide Rehearsal Lane Checkbox
        local show_lane = (state.show_rehearsal_lane ~= false)
        local lane_chg, lane_val = reaper.ImGui_Checkbox(ctx, "Show Rehearsal Lane (above bars)", show_lane)
        if lane_chg then
            state.show_rehearsal_lane = lane_val
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Toggle dedicated Rehearsal Marks Lane situated between Chord Track and Bar Numbers.")
        end

        reaper.ImGui_Spacing(ctx)

        -- Target Bar Detection (Always places at current edit cursor)
        local cur_pos_sec = reaper.GetCursorPosition()
        local _, cur_m = reaper.TimeMap2_timeToBeats(0, cur_pos_sec)
        local target_m_idx = math.max(0, cur_m or 0)
        local cursor_bar = target_m_idx + 1

        reaper.ImGui_TextColored(ctx, 0x5DADE2FF, string.format("Cursor at Bar: %d", cursor_bar))

        reaper.ImGui_Spacing(ctx)

        -- Quick Add Letter / Number Marks (Placed at Edit Cursor)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xE67E22FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xF39C12FF)
        if reaper.ImGui_Button(ctx, string.format("🔤 Add Letter Mark at Bar %d", cursor_bar), width - 24, 26) then
            RehearsalMarkService.add_mark(state, target_m_idx, "letter")
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, string.format("Adds auto-sequenced letter mark [A], [B], [C]... at Bar %d (Edit Cursor).\nInserting between existing marks automatically re-indexes following marks!", cursor_bar))
        end

        reaper.ImGui_Spacing(ctx)

        if reaper.ImGui_Button(ctx, string.format("🔢 Add Number Mark at Bar %d", cursor_bar), width - 24, 24) then
            RehearsalMarkService.add_mark(state, target_m_idx, "number")
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, string.format("Adds auto-sequenced number mark [1], [2], [3]... at Bar %d (Edit Cursor).", cursor_bar))
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Text(ctx, "Classical Navigation Symbols:")

        -- Navigation Grid
        local nav_w = (width - 32) / 2
        if reaper.ImGui_Button(ctx, "Da Capo (D.C.)", nav_w, 24) then
            RehearsalMarkService.add_mark(state, target_m_idx, "dc")
        end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "D.C. al Fine", nav_w, 24) then
            RehearsalMarkService.add_mark(state, target_m_idx, "dc_al_fine")
        end

        if reaper.ImGui_Button(ctx, "Dal Segno (D.S.)", nav_w, 24) then
            RehearsalMarkService.add_mark(state, target_m_idx, "ds")
        end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "D.S. al Coda", nav_w, 24) then
            RehearsalMarkService.add_mark(state, target_m_idx, "ds_al_coda")
        end

        local sym_w = (width - 36) / 3
        if reaper.ImGui_Button(ctx, "𝄋 Segno", sym_w, 24) then
            RehearsalMarkService.add_mark(state, target_m_idx, "segno")
        end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "𝄌 Coda", sym_w, 24) then
            RehearsalMarkService.add_mark(state, target_m_idx, "coda")
        end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "Fine", sym_w, 24) then
            RehearsalMarkService.add_mark(state, target_m_idx, "fine")
        end

        reaper.ImGui_Spacing(ctx)

        -- Custom Mark Input
        reaper.ImGui_PushItemWidth(ctx, width - 90)
        local txt_chg, new_txt = reaper.ImGui_InputTextWithHint(ctx, "##CustomRehText", "Custom text...", ToolsDrawer.custom_rehearsal_text)
        if txt_chg then ToolsDrawer.custom_rehearsal_text = new_txt end
        reaper.ImGui_PopItemWidth(ctx)
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Add##cust", 60, 22) then
            if ToolsDrawer.custom_rehearsal_text ~= "" then
                RehearsalMarkService.add_mark(state, target_m_idx, "custom", ToolsDrawer.custom_rehearsal_text)
                ToolsDrawer.custom_rehearsal_text = ""
            end
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 6. SCORE REHEARSAL MARKS LIST
        -- ------------------------------------------------------------------
        local marks_cnt = (state.rehearsal_marks and #state.rehearsal_marks) or 0
        reaper.ImGui_TextColored(ctx, 0xE67E22FF, string.format("Score Marks (%d):", marks_cnt))

        if reaper.ImGui_BeginChild(ctx, "RehearsalListChild", width - 24, 0, 1) then
            if marks_cnt == 0 then
                reaper.ImGui_TextColored(ctx, 0x888888FF, "No rehearsal marks in score yet.\nUse buttons above to add.")
            else
                for idx, rm in ipairs(state.rehearsal_marks) do
                    local is_rm_sel = (state.selected_rehearsal_mark and state.selected_rehearsal_mark.id == rm.id)
                    local mark_lbl = string.format("Bar %d: [%s]", rm.measure + 1, rm.label or "A")

                    if is_rm_sel then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9F1CFF)
                    end
                    reaper.ImGui_Text(ctx, mark_lbl)
                    if is_rm_sel then
                        reaper.ImGui_PopStyleColor(ctx)
                    end

                    reaper.ImGui_SameLine(ctx, width - 90)
                    if reaper.ImGui_SmallButton(ctx, "Jump##rm_" .. tostring(rm.id)) then
                        state.selected_rehearsal_mark = rm
                        local tpos = reaper.TimeMap2_beatsToTime(0, 0, rm.measure)
                        reaper.SetEditCurPos(tpos, true, false)
                    end
                    reaper.ImGui_SameLine(ctx)
                    if reaper.ImGui_SmallButton(ctx, "🗑##rm_" .. tostring(rm.id)) then
                        RehearsalMarkService.remove_mark(state, rm.id)
                        if state.selected_rehearsal_mark and state.selected_rehearsal_mark.id == rm.id then
                            state.selected_rehearsal_mark = nil
                        end
                        break
                    end
                end
            end
            reaper.ImGui_EndChild(ctx)
        end

        reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_PopStyleColor(ctx)
end

return ToolsDrawer

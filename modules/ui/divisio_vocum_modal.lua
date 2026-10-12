-- ==============================================================================
-- REAPER Native Notator - Module: DivisioVocumModal
-- Modal dialog for distributing multi-voice chords across viewport tracks (Divisio Vocum)
-- ==============================================================================

local DivisioVocumService = require("services.divisio_vocum_service")

local DivisioVocumModal = {}

local VOICE_DESCRIPTIONS = {
    [1] = "Top Voice (Highest)",
    [2] = "Upper Middle",
    [3] = "Middle Voice",
    [4] = "Lower Middle",
    [5] = "Bass Voice (Lowest)",
    [6] = "Sub-Bass / Voice 6",
    [7] = "Voice 7",
    [8] = "Voice 8"
}

function DivisioVocumModal.render(ctx, state, midi_service, active_tracks_data)
    if not (state.show_divisio_vocum_modal or state.show_explode_chords_modal) then return end

    reaper.ImGui_SetNextWindowSize(ctx, 520, 530, reaper.ImGui_Cond_FirstUseEver())
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "🎼 Divisio Vocum (Voice Distribution)###DivisioVocumModalWindow", true, reaper.ImGui_WindowFlags_NoCollapse())

    if not s_open then
        state.show_divisio_vocum_modal = false
        state.show_explode_chords_modal = false
    end

    if s_vis then
        local target_voices = state.divisio_vocum_target_voices or state.explode_chords_target_voices or 5
        local tolerance_ms = state.divisio_vocum_tolerance_ms or state.explode_chords_tolerance_ms or 25
        local gap_fill = (state.divisio_vocum_gap_fill ~= nil and state.divisio_vocum_gap_fill) or (state.explode_chords_gap_fill ~= false)
        local scope = state.divisio_vocum_scope or state.explode_chords_scope or "selected"

        -- Resolve target tracks
        local target_tracks, src_track = DivisioVocumService.get_target_tracks(state, active_tracks_data, target_voices, state.focused_track)
        local sel_cnt = (state.count_selected_notes and state:count_selected_notes()) or 0

        -- Collect chord stats
        local is_sel_scope = (scope == "selected" and sel_cnt > 0)
        local chord_groups, total_notes = DivisioVocumService.collect_notes_and_chords(src_track, tolerance_ms, is_sel_scope, state)

        -- ------------------------------------------------------------------
        -- 1. HEADER & STATUS
        -- ------------------------------------------------------------------
        local src_name = (target_tracks and target_tracks[1] and target_tracks[1].name) or "No Track"
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "SOURCE TRACK:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, 0x3498DBFF, src_name)

        if #chord_groups > 0 then
            local multi_cnt = 0
            for _, g in ipairs(chord_groups) do if #g >= 2 then multi_cnt = multi_cnt + 1 end end
            reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("✓ Detected %d chord(s) with multiple voices (%d total notes)", multi_cnt, total_notes))
        else
            reaper.ImGui_TextColored(ctx, 0xE74C3CFF, "⚠ No notes or chords detected on source track.")
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 2. TARGET VOICES / TRACKS
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Target Tracks / Voices:")
        reaper.ImGui_SetNextItemWidth(ctx, 220)
        local chg_v, new_v = reaper.ImGui_SliderInt(ctx, "##TargetVoicesSlider", target_voices, 2, 12, "%d Tracks")
        if chg_v then
            state.divisio_vocum_target_voices = new_v
            state.explode_chords_target_voices = new_v
            target_voices = new_v
        end

        reaper.ImGui_SameLine(ctx, 0, 10)
        if active_tracks_data and #active_tracks_data >= 2 then
            if reaper.ImGui_Button(ctx, string.format("Match Viewport (%d)##MatchVp", #active_tracks_data), 150, 22) then
                state.divisio_vocum_target_voices = #active_tracks_data
                state.explode_chords_target_voices = #active_tracks_data
                target_voices = #active_tracks_data
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Automatically set target voices to match the number of active tracks in score viewport.")
            end
        end

        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 3. LIVE ROUTING BREAKDOWN (PREVIEW TABLE)
        -- ------------------------------------------------------------------
        reaper.ImGui_TextDisabled(ctx, "Voice Distribution Preview (Top to Bottom):")
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x14161CFF)
        local child_border = (reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border()) or 1
        if reaper.ImGui_BeginChild(ctx, "ExplodeRoutingPreview", -1, 140, child_border) then
            for v = 1, target_voices do
                local dest_info = target_tracks and target_tracks[v]
                local v_desc = VOICE_DESCRIPTIONS[v] or string.format("Voice %d", v)
                
                if v == 1 then
                    reaper.ImGui_TextColored(ctx, 0x1ABC9CFF, string.format("Voice 1: %-20s", v_desc))
                    reaper.ImGui_SameLine(ctx, 210)
                    local t_lbl = dest_info and dest_info.name or "Source Track"
                    reaper.ImGui_TextColored(ctx, 0x1ABC9CFF, string.format("➔ %s (Retained on source)", t_lbl))
                else
                    local col = (dest_info and 0x3498DBFF) or 0x95A5A6FF
                    reaper.ImGui_TextColored(ctx, col, string.format("Voice %d: %-20s", v, v_desc))
                    reaper.ImGui_SameLine(ctx, 210)
                    if dest_info then
                        reaper.ImGui_TextColored(ctx, col, string.format("➔ %s", dest_info.name))
                    else
                        reaper.ImGui_TextColored(ctx, 0xE67E22FF, "➔ (Project track below)")
                    end
                end
            end
            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_PopStyleColor(ctx)

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 4. CHORD DETECTION TOLERANCE & GAP FILLING
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Detection Tolerance:")
        reaper.ImGui_SetNextItemWidth(ctx, 240)
        local chg_t, new_t = reaper.ImGui_SliderInt(ctx, "##ToleranceSlider", tolerance_ms, 5, 100, "%d ms")
        if chg_t then
            state.divisio_vocum_tolerance_ms = new_t
            state.explode_chords_tolerance_ms = new_t
            tolerance_ms = new_t
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Notes starting within this time window are recognized and grouped as a single chord (Default: 25 ms).")
        end

        reaper.ImGui_Spacing(ctx)

        -- Gap-filling checkbox
        local chg_gf, new_gf = reaper.ImGui_Checkbox(ctx, "Pad / Double Bass Voice in Lower Tracks (Gap-Fill)", gap_fill)
        if chg_gf then
            state.divisio_vocum_gap_fill = new_gf
            state.explode_chords_gap_fill = new_gf
            gap_fill = new_gf
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "When enabled, chords with fewer notes than target tracks (e.g. 3 notes with 5 tracks)\nwill double the lowest pitch across the remaining bottom tracks (e.g. Cello & Contrabass).\nWhen disabled, lower tracks remain empty for that chord.")
        end

        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 5. SCOPE
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Scope:")
        local sel_avail = (sel_cnt > 0)
        if not sel_avail then
            reaper.ImGui_BeginDisabled(ctx)
        end
        if reaper.ImGui_RadioButton(ctx, string.format("Selected Chords (%d notes selected)##ScopeSel", sel_cnt), scope == "selected" and sel_avail) then
            state.divisio_vocum_scope = "selected"
            state.explode_chords_scope = "selected"
            scope = "selected"
        end
        if not sel_avail then
            reaper.ImGui_EndDisabled(ctx)
        end

        reaper.ImGui_SameLine(ctx, 0, 16)
        if reaper.ImGui_RadioButton(ctx, "All Chords on Track / Item##ScopeAll", scope == "all" or not sel_avail) then
            state.divisio_vocum_scope = "all"
            state.explode_chords_scope = "all"
            scope = "all"
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 6. ACTION BUTTONS
        -- ------------------------------------------------------------------
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2980B9FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3498DBFF)
        local btn_w = 170
        if reaper.ImGui_Button(ctx, "🎼 Divisio Vocum", btn_w, 28) then
            local ok, msg = DivisioVocumService.execute(state, {
                source_track = src_track,
                target_voices = target_voices,
                tolerance_ms = tolerance_ms,
                gap_fill = gap_fill,
                scope = scope,
                active_tracks_data = active_tracks_data
            })
            state.show_divisio_vocum_modal = false
            state.show_explode_chords_modal = false
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Divisio Vocum (Voice Division):\nSplits multi-voice chords from the source track and distributes them\nvertically across the target tracks in the viewport below.\nConsumes secondary chord notes on the source track.")
        end

        reaper.ImGui_SameLine(ctx, 0, 12)
        if reaper.ImGui_Button(ctx, "Cancel##DivisioVocumCancel", 100, 28) then
            state.show_divisio_vocum_modal = false
            state.show_explode_chords_modal = false
        end

        reaper.ImGui_End(ctx)
    end
end

-- Backward compatibility alias
local ExplodeChordsModal = DivisioVocumModal

return DivisioVocumModal


-- ==============================================================================
-- REAPER Native Notator - Module: DivisiModal
-- Modal dialog for splitting voices (Voice 1..16) onto duplicated REAPER tracks
-- (cloning Kontakt/VSTi instances, Reaticulate banks, sends, and MIDI items)
-- ==============================================================================

local DivisiService = require("services.divisi_service")

local DivisiModal = {}

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local function pitch_to_name(p)
    if not p then return "-" end
    local oct = math.floor(p / 12) - 1
    local semi = (p % 12) + 1
    return string.format("%s%d", NOTE_NAMES[semi] or "C", oct)
end

function DivisiModal.render(ctx, state, midi_service, active_tracks_data)
    if not state.show_divisi_modal then return end

    local flags = reaper.ImGui_WindowFlags_NoCollapse()
    if reaper.APIExists("ImGui_WindowFlags_TopMost") then
        flags = flags | reaper.ImGui_WindowFlags_TopMost()
    end
    if state.focus_divisi_modal then
        if reaper.APIExists("ImGui_SetNextWindowFocus") then
            reaper.ImGui_SetNextWindowFocus(ctx)
        end
        state.focus_divisi_modal = nil
    end

    reaper.ImGui_SetNextWindowSize(ctx, 540, 480, reaper.ImGui_Cond_FirstUseEver())
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "✂ Divisi (Split Voices to Duplicated Tracks)###DivisiModalWindow", true, flags)

    if not s_open then
        state.show_divisi_modal = false
    end

    if s_vis then
        local sel_cnt = (state.count_selected_notes and state:count_selected_notes()) or 0
        if state.divisi_scope == nil then
            state.divisi_scope = (sel_cnt > 0) and "selected" or "all"
        elseif state.divisi_scope == "selected" and sel_cnt == 0 then
            state.divisi_scope = "all"
        end
        if state.divisi_normalize_voice1 == nil then
            state.divisi_normalize_voice1 = true
        end
        if state.divisi_remove_from_source == nil then
            state.divisi_remove_from_source = true
        end
        state.divisi_enabled_voices = state.divisi_enabled_voices or {}

        local src_track = DivisiService.resolve_source_track(state, active_tracks_data, state.divisi_target_track or state.focused_track)
        local src_name = "No Track"
        if src_track and reaper.ValidatePtr(src_track, "MediaTrack*") then
            local _, nm = reaper.GetTrackName(src_track)
            local idx = math.floor(reaper.GetMediaTrackInfo_Value(src_track, "IP_TRACKNUMBER"))
            src_name = (nm and nm ~= "") and string.format("Track %d: %s", idx, nm) or string.format("Track %d", idx)
        end

        local selected_only = (state.divisi_scope == "selected" and sel_cnt > 0)
        local voice_list, total_in_scope = DivisiService.analyze_voices(state, src_track, selected_only)

        -- ------------------------------------------------------------------
        -- 1. HEADER & SOURCE TRACK STATUS
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "SOURCE INSTRUMENT / STAFF:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, 0x3498DBFF, src_name)

        if #voice_list >= 2 then
            reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format(
                "✓ Detected %d distinct Voices (%d notes in scope) — will create %d track copy/copies",
                #voice_list, total_in_scope, #voice_list - 1
            ))
        elseif #voice_list == 1 then
            reaper.ImGui_TextColored(ctx, 0xE67E22FF, string.format(
                "⚠ Only 1 Voice (Voice %d, %d notes) found in current scope. Run 'Auto-Voice' first!",
                voice_list[1].voice, total_in_scope
            ))
        else
            reaper.ImGui_TextColored(ctx, 0xE74C3CFF, "⚠ No notes detected on source track.")
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 2. SCOPE SELECTION
        -- ------------------------------------------------------------------
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Scope:")
        local sel_avail = (sel_cnt > 0)
        if not sel_avail then
            reaper.ImGui_BeginDisabled(ctx)
        end
        if reaper.ImGui_RadioButton(ctx, string.format("Selected Notes (%d selected)##DivScopeSel", sel_cnt), state.divisi_scope == "selected" and sel_avail) then
            state.divisi_scope = "selected"
        end
        if not sel_avail then
            reaper.ImGui_EndDisabled(ctx)
        end

        reaper.ImGui_SameLine(ctx, 0, 18)
        if reaper.ImGui_RadioButton(ctx, "Entire Staff / Track##DivScopeAll", state.divisi_scope == "all" or not sel_avail) then
            state.divisi_scope = "all"
        end

        -- Quick helper button to run Auto-Voice right from here if only 1 voice is present
        if #voice_list < 2 and src_track then
            reaper.ImGui_SameLine(ctx, 0, 18)
            if reaper.ImGui_Button(ctx, "⚡ Run Auto-Voice Now", 155, 22) then
                if selected_only and midi_service and midi_service.auto_split_selection_to_voices then
                    midi_service.auto_split_selection_to_voices(state, src_track)
                elseif midi_service and midi_service.auto_split_overlaps_to_voices then
                    midi_service.auto_split_overlaps_to_voices(state, src_track)
                end
            end
        end

        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 3. LIVE VOICE BREAKDOWN & TRACK DUPLICATION PREVIEW
        -- ------------------------------------------------------------------
        reaper.ImGui_TextDisabled(ctx, "Voice Split & Track Duplication Preview (Kontakt, Reaticulate & Routing cloned):")
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x14161CFF)
        local child_border = (reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border()) or 1
        if reaper.ImGui_BeginChild(ctx, "DivisiVoicesPreview", -1, 175, child_border) then
            local clean_base = "Track"
            if src_track and reaper.ValidatePtr(src_track, "MediaTrack*") then
                local _, nm = reaper.GetTrackName(src_track)
                if nm and nm ~= "" then clean_base = nm end
            end

            if #voice_list == 0 then
                reaper.ImGui_TextDisabled(ctx, "  No active voices found.")
            else
                for idx, vi in ipairs(voice_list) do
                    local range_str = string.format("%s–%s", pitch_to_name(vi.min_pitch), pitch_to_name(vi.max_pitch))
                    if idx == 1 then
                        reaper.ImGui_TextColored(ctx, 0x1ABC9CFF, string.format(
                            "  [Primary] Voice %d (%d notes, %s)", vi.voice, vi.count, range_str
                        ))
                        reaper.ImGui_SameLine(ctx, 255)
                        reaper.ImGui_TextColored(ctx, 0x1ABC9CFF, string.format("➔ Stays on '%s'", clean_base))
                    else
                        local is_en = (state.divisi_enabled_voices[vi.voice] ~= false)
                        local chg_en, new_en = reaper.ImGui_Checkbox(ctx, string.format(
                            "Voice %d (%d notes, %s)##div_v_%d", vi.voice, vi.count, range_str, vi.voice
                        ), is_en)
                        if chg_en then
                            state.divisi_enabled_voices[vi.voice] = new_en
                            is_en = new_en
                        end
                        reaper.ImGui_SameLine(ctx, 255)
                        if is_en then
                            reaper.ImGui_TextColored(ctx, 0x3498DBFF, string.format(
                                "➔ + Duplicate Track: '%s (Divisi %d)'", clean_base, vi.voice
                            ))
                        else
                            reaper.ImGui_TextDisabled(ctx, "➔ (Skipped — stays on source track)")
                        end
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
        -- 4. OPTIONS
        -- ------------------------------------------------------------------
        local chg_norm, new_norm = reaper.ImGui_Checkbox(
            ctx,
            "Normalize extracted notes to Voice 1 (MIDI Channel 1) on new Divisi tracks",
            state.divisi_normalize_voice1
        )
        if chg_norm then state.divisi_normalize_voice1 = new_norm end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Recommended: Sets extracted notes on each duplicated Divisi track to Voice 1 (Channel 1)\nso each Divisi staff engraves as a clean primary voice and triggers Kontakt / Reaticulate on Channel 1.")
        end

        local chg_rem, new_rem = reaper.ImGui_Checkbox(
            ctx,
            "Remove split-out voices (Voice 2+) from original Source Track",
            state.divisi_remove_from_source
        )
        if chg_rem then state.divisi_remove_from_source = new_rem end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "When enabled, Voice 2+ notes are moved (removed from source track).\nWhen disabled, source track keeps all voices as a full-chord reference.")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ------------------------------------------------------------------
        -- 5. ACTION BUTTONS
        -- ------------------------------------------------------------------
        local can_execute = (#voice_list >= 2)
        if not can_execute then
            reaper.ImGui_BeginDisabled(ctx)
        end
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
        if reaper.ImGui_Button(ctx, "✂ Split Voices (Create Divisi Tracks)", 250, 30) then
            DivisiService.execute(state, {
                source_track = src_track,
                scope = state.divisi_scope,
                enabled_voices = state.divisi_enabled_voices,
                normalize_to_voice_1 = state.divisi_normalize_voice1,
                remove_from_source = state.divisi_remove_from_source,
                active_tracks_data = active_tracks_data
            })
            state.show_divisi_modal = false
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        if not can_execute then
            reaper.ImGui_EndDisabled(ctx)
        end

        reaper.ImGui_SameLine(ctx, 0, 12)
        if reaper.ImGui_Button(ctx, "Cancel##DivisiModalCancel", 100, 30) then
            state.show_divisi_modal = false
        end

        reaper.ImGui_End(ctx)
    end
end

return DivisiModal

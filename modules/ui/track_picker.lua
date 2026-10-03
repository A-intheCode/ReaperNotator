-- ==============================================================================
-- REAPER Native Notator - Module: TrackPicker
-- Modal dialog for selecting visible tracks and clefs
-- ==============================================================================

local TrackPicker = {}

function TrackPicker.render(ctx, state, project_tracks)
    if not state.show_track_picker then return end
    
    reaper.ImGui_OpenPopup(ctx, "Track Selection (Multitrack)")
    local visible, open = reaper.ImGui_BeginPopupModal(ctx, "Track Selection (Multitrack)", true, reaper.ImGui_WindowFlags_AlwaysAutoResize())
    if visible then
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Select tracks for score view:")
        reaper.ImGui_Separator(ctx)
        
        if reaper.ImGui_Button(ctx, "Select All") then
            for _, t in ipairs(project_tracks) do state.selected_tracks[t.guid] = true end
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Deselect All") then
            state.selected_tracks = {}
        end
        reaper.ImGui_Separator(ctx)
        
        for _, t in ipairs(project_tracks) do
            local is_chk = state.selected_tracks[t.guid] or false
            local lbl = string.format("Track %d: %s (%d MIDI Items)###tr_%s", t.idx, t.name, t.midi_items, t.guid)
            local changed, val = reaper.ImGui_Checkbox(ctx, lbl, is_chk)
            if changed then state.selected_tracks[t.guid] = val end
        end
        
        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_Button(ctx, "Done", 120, 0) then
            state.show_track_picker = false
            reaper.ImGui_CloseCurrentPopup(ctx)
        end
        reaper.ImGui_EndPopup(ctx)
    else
        state.show_track_picker = open
    end
end

return TrackPicker

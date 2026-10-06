-- ==============================================================================
-- REAPER Native Notator - Module: HelpModal
-- Help and keyboard shortcuts window
-- ==============================================================================

local HelpModal = {}

function HelpModal.render(ctx, state)
    if not state.show_help then return end
    
    reaper.ImGui_SetNextWindowSize(ctx, 580, 520, reaper.ImGui_Cond_Appearing())
    local h_vis, h_open = reaper.ImGui_Begin(ctx, "REAPER Notator - Shortcuts & Help", true)
    if not h_open then
        state.show_help = false
    end
    if h_vis then
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Keyboard Shortcuts & Mouse Controls:")
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_BulletText(ctx, "Ctrl + C / V / X: Copy, Paste, Cut")
        reaper.ImGui_BulletText(ctx, "Ctrl + A: Select all notes across active tracks")
        reaper.ImGui_BulletText(ctx, "Shift + Left/Right Arrow: Shorten / lengthen note by grid")
        reaper.ImGui_BulletText(ctx, "Left/Right Arrow: Move selected notes by grid")
        reaper.ImGui_BulletText(ctx, "Up/Down Arrow: Transpose selected notes by semitone")
        reaper.ImGui_BulletText(ctx, "Shift + Up/Down Arrow: Octave jump (+/- 12 semitones)")
        reaper.ImGui_BulletText(ctx, "Shift / Ctrl + Click: Add/remove note from selection")
        reaper.ImGui_BulletText(ctx, "Marquee Selection: Drag on empty score canvas")
        reaper.ImGui_BulletText(ctx, "Multi-Move: Click & drag any selected note")
        reaper.ImGui_BulletText(ctx, "Del / Backspace: Delete selected note(s) or dynamic")
        reaper.ImGui_BulletText(ctx, "C, D, E, F, G, A, B: Quick step input at cursor")
        reaper.ImGui_BulletText(ctx, "2, 3, 4, 5, 6, 7: Note value (1/32 to 1/1)")
        reaper.ImGui_BulletText(ctx, "Period (.): Toggle dotted note")
        reaper.ImGui_BulletText(ctx, "S: Slur (Legato phrase mark connecting notes with sampler Legato transition)")
        reaper.ImGui_BulletText(ctx, "T: Tie (Held note connecting identical pitches without re-striking)")
        reaper.ImGui_BulletText(ctx, "Spacebar: Play / Pause")
        reaper.ImGui_BulletText(ctx, "Click on empty staff: Sets REAPER Edit-Cursor")
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextColored(ctx, 0x64D2FFFF, "💡 Tip: Click the gear icon ⚙ in the top bar to customize all keyboard shortcuts!")
        reaper.ImGui_Spacing(ctx)
        if reaper.ImGui_Button(ctx, "Close", -1, 30) then
            state.show_help = false
        end
    end
    reaper.ImGui_End(ctx)
end

return HelpModal

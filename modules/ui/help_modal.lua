-- ==============================================================================
-- REAPER Native Notator - Module: HelpModal
-- Help and keyboard shortcuts window
-- ==============================================================================

local HelpModal = {}

function HelpModal.render(ctx, state)
    if not state.show_help then return end
    
    local flags = reaper.ImGui_WindowFlags_NoCollapse()
    if reaper.APIExists("ImGui_WindowFlags_TopMost") then
        flags = flags | reaper.ImGui_WindowFlags_TopMost()
    end
    if state.focus_help_modal then
        if reaper.APIExists("ImGui_SetNextWindowFocus") then
            reaper.ImGui_SetNextWindowFocus(ctx)
        end
        state.focus_help_modal = nil
    end

    reaper.ImGui_SetNextWindowSize(ctx, 620, 580, reaper.ImGui_Cond_Appearing())
    local h_vis, h_open = reaper.ImGui_Begin(ctx, "REAPER Notator - Shortcuts & Help", true, flags)
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
        reaper.ImGui_BulletText(ctx, "Ctrl + 1..7 / Ctrl + K: Grid snap shortcuts / Link Grid & Note Duration")
        reaper.ImGui_BulletText(ctx, "Period (.): Toggle dotted note")
        reaper.ImGui_BulletText(ctx, "S: Slur (Legato phrase mark connecting notes with sampler Legato transition)")
        reaper.ImGui_BulletText(ctx, "T: Tie (Held note connecting identical pitches without re-striking)")
        reaper.ImGui_BulletText(ctx, "Ctrl + M: Add Custom Rehearsal Marker (live at Playhead or at Edit Cursor)")
        reaper.ImGui_BulletText(ctx, "Spacebar: Play / Pause")
        reaper.ImGui_BulletText(ctx, "Record Button (Top Bar): Left-click to Record/Stop; Right-click for Record & Auto-Quantize Modal")
        reaper.ImGui_BulletText(ctx, "Divisi (Right-Click / Tools Drawer): Split Voices 2..16 onto full duplicated Kontakt/Reaticulate tracks")
        reaper.ImGui_BulletText(ctx, "Reaticulate Auto-Setup: Selecting a Bank or Articulation auto-loads Reaticulate.jsfx in FX Slot 1")
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

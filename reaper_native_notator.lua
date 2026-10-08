-- @description REAPER-Notator: Native Musical Notation & Engraving Suite
-- @author A-intheCode
-- @version 1.7.0-beta
-- @changelog
--   + v1.7.0-beta: Complete Glissando & Portamento System, Cross-Staff Support, and Dual Persistence:
--             - Glissando Engine: Real chromatic pitch steps generated in MIDI takes (NOTATOR_GLISS_STEP / NOTATOR_GLISSANDO) with full acoustic playback.
--             - Dual-Reality Score Rendering: Intermediate chromatic ladder steps are 100% hidden from the score canvas while Note 1 retains its full visual duration.
--             - Cross-Staff Glissando: Full support for cross-staff glissandi (e.g. Harp/Piano connecting Bass Clef to Treble Clef) with automatic clef split detection across staves.
--             - Wavy Line Styles: Configurable visual styles including Sinusoidal wave ('sine'), Sawtooth/Zigzag ('saw'), and Straight line ('straight').
--             - Dynamic "gliss." Text Badge: Italicized badge placed automatically above the wavy line via upward normal vectors, with hit-testing and toggle in context menu.
--             - Portamento Engine: Acoustic blending via CC64 Pedal Hold (50% Note 1 to 50% Note 2) or continuous CC controllers (CC34/CC5/CC65) with straight diagonal canvas line and 'port.' badge.
--             - Settings Modal & Batch Operations: Dedicated Glissando and Portamento sections in Settings Modal with configurable defaults and 1-click project sync.
--             - Dual Persistence & Take Auto-Recovery: Full project persistence via ExtState and MIDI take Type 15 Sysex events ensuring marks survive across sessions.
--   + v1.6.5: PreviewPlayback Hotfix: Track isolation, arm settling buffer & audition duration tuning:
--             - Track Isolation: Temporarily disarms other armed tracks during score note click preview to strictly prevent foreign instruments from sounding via Virtual MIDI Keyboard.
--             - Initial Arm Settling Buffer: Added a 250ms buffer upon mouse release after initial track arming to let VST audio buffers settle, guaranteeing clean initial note attacks with 0ms latency on consecutive notes.
--             - Audition Duration Tuning: Extended Note-On hold duration to 450ms for Legato/Standard notes (giving full acoustic body) and 300ms for Staccato/Momentary notes.
--             - Articulation Detection: Enhanced lookbehind and note-level articulation resolution ensuring exact technique triggers and bank overrides.
--             - UI Selectable ID Guard: Added unique ImGui ID hashes for CC audition presets in SettingsModal to prevent item collision.
--   + v1.6.4: Hotfix: Non-visible Legato Articulation & Item Cleanup Tools Relocation:
--             - Resolved Non-visible Legato Articulation: Legato chosen via the Articulations Drawer now renders a visible text badge above the staff (identical to Long), with complete support for font sizing, bold weight, dragging, and hover. Engraving slurs and ties continue to suppress redundant text badges per Gardner Read / Gould standards.
--             - Item Cleanup Tools in Tools Drawer: Moved 'Clean Notation Events' to the Score Tools Drawer directly below Auto-Voice with a prominent safety separator ('ITEM CLEANUP (SELECTED ITEM)').
--             - Clear all MIDI/Program Bank Events: Added dedicated action in Tools Drawer to strip Program Changes and Bank Select CCs (CC0/CC32) strictly from the selected MIDI item take.
--   + v1.5.6: Dynamic Object Scaling Decoupling & Legacy Hairpin Playback Healing:
--             - Decoupled Dynamic Scaling: Hairpins (<, >) and Dynamic Texts (cresc., dim.) now strictly collide and bound only against dynamic markers (p, f, etc.), other hairpins, and dynamic texts, completely ignoring note articulations. Hairpins can now scale freely across dense staccato phrases without shrinking.
--             - Legacy Hairpin Playback Healing: The '⚡ Fix Playback' command automatically detects collapsed hairpins and dynamic texts (<= 0.75 QN) in older projects, restores them to their natural musical phrase boundaries, re-resolves dynamic levels, and regenerates clean continuous CC automation ramps.
--             - Status Notification: Reports healed dynamic object count alongside synced notes and cleared events.
--   + v1.5.5: Hotfix release: Playback Reconciliation, Centered Last Resort Purge Modal, and Target Track Resolution:
--             - Idempotent Playback Reconciliation: Left-clicking '⚡ Fix Playback' scans and reconciles all note articulations with the active track's Reaticulate sound bank without stripping or corrupting valid articulations
--             - Centered Fix of Last Resort Confirmation Modal: Repeating click when already synchronized (or right-clicking at any time) presents a dedicated emergency confirmation modal window to purge corrupted keyswitches (CC0/CC32/PCs) and reset to clean default sustain
--             - Dead-Center Modal Placement: Modal uses Cond_Always() with pivot (0.5, 0.5) dynamically computed from screen/window dimensions to guarantee perfect horizontal and vertical centering without jitter or 50Hz flickering
--             - Target Track Resolution: Fixed REAPER C-API take track lookup (get_track_from_take) and implemented multi-tier track resolution so the modal header clearly displays the target track name (Target: Track <num>: <name>)
--             - User Manual & Workaround Documentation: Updated Section 6.5 in the User Manual with complete step-by-step instructions for troubleshooting third-party sample libraries lacking specific articulation keyswitches (e.g. staccato)
--   + v1.5.4: Hotfix release: MusicXML Articulation Import & Instant Note Audition Preview Playback:
--             - MusicXML Articulation Mapping: Implemented prioritized 3-tier matching for staccato, ensuring dedicated short patches (such as Spitfire 'Staccato Dig') take priority over generic duration fallbacks ('Short 0.5')
--             - Compact MusicXML Import Layout: Automatically sets compact track heights upon importing MusicXML scores for an organized orchestral overview
--             - Single-Note Audition Arbitration: Refined audition hit-testing to sound strictly the single closest hovered note even within dense chords or adjacent systems
--             - Track Audition Isolation: Temporarily disarms concurrent project tracks during audition clicks to eliminate VKB broadcast crosstalk across instruments sharing the same register
--             - Timeline Articulation Chasing: Auditioning notes scans the project timeline from measure 1 to chase active Program Changes and note-level articulation marks (Staccato, Marcato, Tenuto, Pizzicato)
--             - Zero-Latency First Click: Eliminated destructive patch reset on mouse release and introduced 1-frame pre-switching for Bank/Program Change before Note-On, ensuring instant articulation playback on the very first click
--   + v1.5.3: Hotfix release: Selective Copy/Paste, SMuFL Staccatissimo, Staccato alignment, and removal of print.xml auto-generation:
--             - Selective Note Copy/Paste Engine: Isolated note copying so that copying selected notes or chords never inadvertently captures unselected dynamics, hairpins, pedal markings, or tempo markers
--             - Destination MIDI Take boundary preservation: Pasting notes into a MIDI item cleanly respects existing item boundaries without truncating or unexpectedly expanding takes
--             - Authentic SMuFL Staccatissimo: Upgraded staccatissimo wedges from rough canvas polygons to authentic Bravura SMuFL glyphs (articStaccatissimoAbove / articStaccatissimoBelow) with pristine subpixel anti-aliasing
--             - Standard-compliant Staccato Dot Placement: Aligned staccato dots consistently across beamed note clusters opposite beam stems (per Elaine Gould standard), complete with automatic staff-line avoidance
--             - Decoupled print subsystem: completely removed background print XML auto-generation (*_print.xml) on project save and exit
--             - Flush Bottom Bar: Eliminated right-margin gap on the bottom control bar, cleanly docking utility modals flush to the window edge
--   + v1.5.2: Critical fix for Grand Staff system note assignment and interactive cross-staff management:
--             - Fix high notes erroneously forced into lower bass staff with 12-14 ledger lines by eliminating flawed track_has_multi_staff_chan channel assumption
--             - Natural pitch-based split in Grand Staff mode: notes >= 60 (Middle C) automatically allocate to upper Treble staff; notes < 60 allocate to lower Bass staff
--             - Interactive Cross-Staff Switching (M): select any note(s) and press M or Ctrl+Shift+Up / Ctrl+Shift+Down to switch between upper and lower systems
--             - Added Grand Staff context submenu: instant access to Move to Upper Staff, Move to Lower Staff, and Auto Staff
--             - Fully synchronized rest generation and beaming partition parity across staves in multi-voice piano contexts
--             - Enhanced automatic grand staff clef detection for tracks with broad keyboard pitch spans (piano recordings)
--   + v1.5.1: Hotfix for polyphonic engraving, stem alignment, and voice-separated beaming:
--             - Fix detached floating stems in multi-voice contexts by aligning concurrent polyphonic notes on the exact same beat axis
--             - Synchronize visual notehead positions (vis_nx) and nominal positions (nominal_nx) across all stem and flag calculations
--             - Voice-separated beaming in Engraver: partition beam groups strictly by staff and voice (st .. "_v" .. v)
--             - Standard-compliant polyphonic stem directions for beamed groups (Voice 1 stems up, Voice 2 stems down per Elaine Gould)
--             - Synchronized stem attachments for displaced noteheads on seconds and unisons in both ScoreCanvas and SystemEngraver
--   + v1.5.0: Major feature release:
--             - Smooth anti-aliased beam rendering: normalized quad winding order (strictly clockwise) in Dear ImGui screen space, ensuring full subpixel AA across all stem directions
--             - Full outer stem coverage (half_stem) and embedded stem terminations preventing protruding flat line caps on slanted beams (per Gardner Read & Elaine Gould)
--             - Non-mouse keyboard note navigation (Alt + Left / Right) and selection expansion (Alt + Shift + Left / Right) with auto-scroll integration
--             - Redesigned Settings modal with collapsible category sections, unified vertical scrolling container, pinned static footer, and live shortcut search
--             - Comprehensive Dark Mode palette inversion covering all score elements (clefs, time signatures, rests, ties, lyrics, rehearsal marks, fermatas, voice contrast)
--             - Default bar numbers color set to standard engraving black in light mode and high contrast in dark mode
--   + v1.4.5: Hotfix for Tempo Map & Time Signature synchronization in clean projects (Count == 0), project time signature preservation, and active scope UI indicator
--   + v1.4.4: Hotfix for ReaImGui child window state restoration and protected ScoreCanvas render & mouse handling preventing unpopped child window crashes
--   + v1.4.3: Direct MIDI Item Key & Time Signature assignment in Item Scope; restored Clef Drawer to track scope with auto-parent track target
--   + v1.4.2: Maintenance and UI refinements
--   + v1.4.1: Interactive Rehearsal Mark drag-and-drop, edit cursor placement, full-staff fermata hit-testing, and UI refinement
--   + v1.4.0: Major notation & engraving features:
--             - Score-wide vertical Fermatas (standard, short, long, very long) with tempomap slowdown dip & dual-persistence
--             - Dynamic Rehearsal Marks ([A], [B]...) with auto-sequencing, between Chord lane & bar numbers, and navigation marks (D.C., D.S., Segno, Coda, Fine)
--             - Arpeggiated chords (wavy line engraving & non-destructive micro-strumming playback offset)
--             - Full MusicXML 4.0 lossless import and export integration for fermatas, rehearsal marks, navigation, and arpeggios
--             - Removed Print PDF button from bottom bar while preserving internal exporter
--   + v1.3.8: Dual-persistence and maintenance updates
--   + v1.3.6: Fix crash in sidebar.lua when track pointer is invalid or deleted (MediaTrack expected in GetTrackGUID)
--   + v1.3.5: Beam rendering performance & Phase 2 optimizations:
--             - Cleaned up beam rendering: eliminated redundant outline strokes (AddQuad) on filled quads, halving C-API beam calls and cutting CPU vertex calculation by 60%
--             - High-efficiency O(1) project state change guard in MidiService eliminating redundant C-API calls during playback and idle
--             - Text measurement memoization in FontManager caching ImGui text calculations
--             - Top-level module require scoping in ScoreCanvas
--   + v1.3.0: Music engraving refinements, tempo editing & tuplet mathematics:
--             - Precise Gardner Read / Elaine Gould quarter-note quintuplet (5:4) measure spacing
--             - Clean DirectWrite unicode quarter-note tempo symbol (♩) with non-bold styling
--             - Direct double-click BPM editing popup with auto-focused numeric input
--             - Robust ReaImGui context pointer validation preventing runtime crashes
--             - Multi-track view persistence on MIDI item selection & instant clef redraw
--             - Text item bold/italic formatting toggle bugfixes
--   + v1.1.0: Major performance optimization for large scores (48+ tracks / orchestra templates):
--             - Zero-overhead measure layout & key signature caching
--             - O(N) note and rest bucketing for measure width calculations
--             - Pre-calculated and cached voice rests directly in MidiService track cache
--             - In-memory key signature resolution eliminating ReaScript C-API call storms
--             - Cached track header metrics & clef evaluation across frames
--   + v1.0.2: Fix MusicXML key signature import, mid-score modulations, pedal mark scaling & dynamics default bow intensity
--   + v1.0.1: Add TopBar version display & automated versioning
--   + v1.0.0: Initial public release
-- @about
--   # REAPER-Notator
--   Native musical notation, score editing, and engraving environment for Cockos REAPER.
--   Features SMuFL font rendering, intelligent beaming, dynamics CC automation,
--   articulations drawer, MusicXML import/export, and seamless DAW integration.
-- @provides
--   modules/**
--   docs/**
-- @license GPL-3.0
--
-- ==============================================================================
-- Copyright (C) 2026 A-intheCode
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program. If not, see <https://www.gnu.org/licenses/>.
-- ==============================================================================
-- REAPER Native Notator (Pro Edition) - Modular Main Entry Point
-- 100% Native Notation Editor for Cockos REAPER
-- Class-based architecture with modular multi-file structure
-- Original 3-column layout (Sidebar left, Canvas center, Dynamics drawer right)
-- ==============================================================================

-- 1. Path configuration for module requires
local script_source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local script_dir = script_source:match("(.*/)") or ""
if script_dir:sub(-1) ~= "/" then script_dir = script_dir .. "/" end

package.path = script_dir .. "?.lua;"
            .. script_dir .. "?/init.lua;"
            .. script_dir .. "modules/?.lua;"
            .. script_dir .. "modules/?/init.lua;"
            .. package.path


-- 0. Dev-Mode Cache Clearing
for k in pairs(package.loaded) do
    if k:match("^constants") or k:match("^state") or k:match("^classes%.") or k:match("^services%.") or k:match("^rendering%.") or k:match("^ui%.") or k:match("^input%.") then
        package.loaded[k] = nil
    end
end

-- 2. ReaImGui initialization & version check
if not reaper.APIExists("ImGui_CreateContext") then
    reaper.MB(
        "ReaImGui is not installed or not loaded!\n\n" ..
        "Please install ReaImGui via ReaPack:\n" ..
        "Extensions -> ReaPack -> Browse packages -> search and install 'ReaImGui'.",
        "REAPER Native Notator - Error", 0
    )
    return
end

local cfg_flags = reaper.APIExists("ImGui_ConfigFlags_None") and reaper.ImGui_ConfigFlags_None() or 0
local ctx = reaper.ImGui_CreateContext("REAPER Native Notator", cfg_flags)

-- 2b. Enable multi-edge window resizing (all 4 edges and corners)
if reaper.APIExists("ImGui_SetConfigVar") and reaper.APIExists("ImGui_ConfigVar_WindowsResizeFromEdges") then
    reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_WindowsResizeFromEdges(), 1)
end

-- 3. Load modules
local Constants           = require("constants")
local State               = require("state")
local MidiService         = require("services.midi_service")
local ClipboardService    = require("services.clipboard_service")
local DynamicsEngine      = require("services.dynamics_engine")
local Engraver            = require("rendering.engraver")
local FontManager         = require("rendering.font_manager")
local ScoreCanvas         = require("rendering.score_canvas")
local Sidebar             = require("ui.sidebar")
local TopBar              = require("ui.top_bar")
local TrackPicker         = require("ui.track_picker")
local DynamicsDrawer      = require("ui.dynamics_drawer")
local BottomBar           = require("ui.bottom_bar")
local HelpModal           = require("ui.help_modal")
local QuantizeModal       = require("ui.quantize_modal")
local MouseHandler        = require("input.mouse_handler")
local KeyboardHandler     = require("input.keyboard_handler")
local SettingsModal       = require("ui.settings_modal")
local ShortcutManager     = require("services.shortcut_manager")
local TempoService        = require("services.tempo_service")
local TempoDrawer         = require("ui.tempo_drawer")
local ToolsDrawer         = require("ui.tools_drawer")
local ClefDrawer          = require("ui.clef_drawer")
local ArticulationsDrawer = require("ui.articulations_drawer")
local BankPickerModal     = require("ui.bank_picker_modal")
local OctaveService       = require("services.octave_service")
local HairpinService      = require("services.hairpin_service")
local DynamicTextService  = require("services.dynamic_text_service")
local PedalService        = require("services.pedal_service")
local TextItemService     = require("services.text_item_service")
local RepeatService       = require("services.repeat_service")
local FermataService      = require("services.fermata_service")
local RehearsalMarkService= require("services.rehearsal_mark_service")
local AudioPreview        = require("services.audio_preview")
local PatternService      = require("services.pattern_service")
local PatternBrowser      = require("ui.pattern_browser")
local ScaleService        = require("services.scale_service")
local ScaleModal          = require("ui.scale_modal")
local KeySignatureService  = require("services.key_signature_service")
local KeySignatureDrawer   = require("ui.key_signature_drawer")
local MusicXmlModal        = require("ui.musicxml_modal")
local SlurService          = require("services.slur_service")
local PortamentoService    = require("services.portamento_service")
local GlissandoService     = require("services.glissando_service")

-- 4. Initialization of State & Fonts
local state = State.new()
ShortcutManager.init()
FermataService.load_fermatas(state)
TempoService.load_markers(state)
OctaveService.load_lines(state)
HairpinService.load_hairpins(state)
DynamicTextService.load_dynamic_texts(state)
PedalService.load_pedals(state)
TextItemService.load_text_items(state)
RepeatService.load_repeat_marks(state)
RehearsalMarkService.load_marks(state)
ScaleService.load_chord_items(state)
KeySignatureService.load(state)
SlurService.load_slurs(state)
PortamentoService.load_portamentos(state)
GlissandoService.load_glissandos(state)
MidiService.cleanup_orphaned_score_elements(state)
PatternService.init()
local fonts = FontManager.init(ctx, state)

reaper.atexit(function()
    AudioPreview.stop_all(state)
    -- Safely persist all Notator objects & settings before script exit / REAPER shutdown:
    TempoService.save_markers(state)
    OctaveService.save_lines(state)
    HairpinService.save_hairpins(state)
    DynamicTextService.save_dynamic_texts(state)
    PedalService.save_pedals(state)
    TextItemService.save_text_items(state)
    RepeatService.save_repeat_marks(state)
    FermataService.save_fermatas(state)
    RehearsalMarkService.save_marks(state)
    ScaleService.save_chord_items(state)
    KeySignatureService.save(state)
    SlurService.save_slurs(state)
    PortamentoService.save_portamentos(state)
    GlissandoService.save_glissandos(state)
    state:save_settings()
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
end)

-- 5. Main Render Loop (ReaImGui 60 FPS)
local function loop()
    if not state.is_open then return end
    if reaper.APIExists("ImGui_ValidatePtr") and not reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*") then return end

    -- Project-specific data (tempo markers, octave lines, hairpins, pedals, text items, repeat marks & chord items):
    -- Check every frame if the active REAPER project changed or was reloaded
    local cur_proj, proj_fn = reaper.EnumProjects(-1)
    if state.current_reaproject ~= cur_proj or state.current_proj_fn ~= proj_fn then
        state.current_reaproject = cur_proj
        state.current_proj_fn = proj_fn
        MidiService.invalidate_cache()
        state:load_settings()
        SettingsModal.apply_theme(state)
        FermataService.load_fermatas(state)
        TempoService.load_markers(state)
        OctaveService.load_lines(state)
        HairpinService.load_hairpins(state)
        DynamicTextService.load_dynamic_texts(state)
        PedalService.load_pedals(state)
        TextItemService.load_text_items(state)
        RepeatService.load_repeat_marks(state)
        RehearsalMarkService.load_marks(state)
        ScaleService.load_chord_items(state)
        SlurService.load_slurs(state)
        PortamentoService.load_portamentos(state)
        GlissandoService.load_glissandos(state)
        MidiService.cleanup_orphaned_score_elements(state)
        state:clear_selection()
    end
    
    -- Authentic dark pro color theme
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),       0x151619FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(),        0x1E2025FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),         0x2A2D35FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0x282B33FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0xE67E22FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   0xFF9F1CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),           0xF0F0F0FF)
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 6.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),  4.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),    8.0, 6.0)
    
    -- Determine multi-monitor work area (excluding taskbars) for window positioning
    local function get_screen_work_area(wx, wy, ww, wh)
        -- 1. REAPER native my_getViewport (reliably detects all OS monitors via window center)
        if reaper.my_getViewport and wx and wy and ww and wh then
            local cx = wx + math.floor(ww / 2)
            local cy = wy + math.floor(wh / 2)
            local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0, cx, cy, cx, cy, 1)
            if l and t and r and b and (r - l) > 300 and (b - t) > 300 then
                return l, t, (r - l), (b - t)
            end
        end
        
        -- 2. ReaImGui GetWindowViewport
        if reaper.APIExists("ImGui_GetWindowViewport") then
            local wvp = reaper.ImGui_GetWindowViewport(ctx)
            if wvp and reaper.APIExists("ImGui_Viewport_GetWorkPos") and reaper.APIExists("ImGui_Viewport_GetWorkSize") then
                local x, y = reaper.ImGui_Viewport_GetWorkPos(wvp)
                local w, h = reaper.ImGui_Viewport_GetWorkSize(wvp)
                if w and w > 300 and h and h > 300 then
                    return x, y, w, h
                end
            end
        end
        
        -- 3. Fallback: GetMainViewport
        if reaper.APIExists("ImGui_GetMainViewport") then
            local mvp = reaper.ImGui_GetMainViewport(ctx)
            if mvp and reaper.APIExists("ImGui_Viewport_GetWorkPos") and reaper.APIExists("ImGui_Viewport_GetWorkSize") then
                local x, y = reaper.ImGui_Viewport_GetWorkPos(mvp)
                local w, h = reaper.ImGui_Viewport_GetWorkSize(mvp)
                if w and w > 300 and h and h > 300 then
                    return x, y, w, h
                end
            end
        end
        
        return 0, 0, 1920, 1080
    end
    
    local cur_x = state.cur_win_x or state.prev_win_x or 100
    local cur_y = state.cur_win_y or state.prev_win_y or 60
    local cur_w = state.cur_win_w or state.prev_win_w or 1280
    local cur_h = state.cur_win_h or state.prev_win_h or 720
    
    local vx = state.screen_work_x
    local vy = state.screen_work_y
    local vw = state.screen_work_w
    local vh = state.screen_work_h
    
    if not vx or not vw then
        vx, vy, vw, vh = get_screen_work_area(cur_x, cur_y, cur_w, cur_h)
    end
    
    if state.request_maximize_toggle then
        state.is_maximized = not state.is_maximized
        if state.is_maximized then
            state.status_msg = "Window maximized on current display"
        else
            state.just_restored = true
            state.status_msg = "Window size restored (16:9)"
        end
        state.request_maximize_toggle = false
    end
    
    if state.is_maximized then
        reaper.ImGui_SetNextWindowPos(ctx, vx, vy, reaper.ImGui_Cond_Always())
        reaper.ImGui_SetNextWindowSize(ctx, vw, vh, reaper.ImGui_Cond_Always())
    else
        -- Enforce minimum size of at least 1280x720 (if not maximized)
        if reaper.APIExists("ImGui_SetNextWindowSizeConstraints") then
            reaper.ImGui_SetNextWindowSizeConstraints(ctx, 1280, 720, 16384, 16384)
        end
        
        if state.just_restored then
            local rw = math.max(1280, state.prev_win_w or 1280)
            local rh = math.max(720, math.floor(rw * 9 / 16 + 0.5))
            if rw > vw then rw = vw; rh = math.floor(rw * 9 / 16 + 0.5) end
            if rh > vh then rh = vh; rw = math.floor(rh * 16 / 9 + 0.5) end
            
            local rx = vx + math.floor((vw - rw) / 2)
            local ry = vy + math.floor((vh - rh) / 2)
            
            -- If previous position was on this monitor, preserve this position
            if state.prev_win_x and state.prev_win_y then
                if state.prev_win_x >= vx and state.prev_win_x < (vx + vw - 100) and
                   state.prev_win_y >= vy and state.prev_win_y < (vy + vh - 100) then
                    rx = state.prev_win_x
                    ry = state.prev_win_y
                end
            end
            
            if rx < vx then rx = vx end
            if ry < vy then ry = vy end
            if rx + rw > vx + vw then rx = math.max(vx, vx + vw - rw) end
            if ry + rh > vy + vh then ry = math.max(vy, vy + vh - rh) end
            
            reaper.ImGui_SetNextWindowPos(ctx, rx, ry, reaper.ImGui_Cond_Always())
            reaper.ImGui_SetNextWindowSize(ctx, rw, rh, reaper.ImGui_Cond_Always())
            state.just_restored = false
        else
            reaper.ImGui_SetNextWindowSize(ctx, 1280, 720, reaper.ImGui_Cond_FirstUseEver())
        end
    end
    
    if reaper.APIExists("ImGui_ConfigVar_WindowsMoveFromTitleBarOnly") and reaper.APIExists("ImGui_SetConfigVar") then
        reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_WindowsMoveFromTitleBarOnly(), 1)
    end
    
    local child_border = reaper.APIExists("ImGui_ChildFlags_Borders") and reaper.ImGui_ChildFlags_Borders() or 1
    local child_none = reaper.APIExists("ImGui_ChildFlags_None") and reaper.ImGui_ChildFlags_None() or 0
    
    local window_flags = reaper.ImGui_WindowFlags_NoScrollbar()
    if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
        window_flags = window_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    end
    if reaper.APIExists("ImGui_WindowFlags_NoNav") then
        window_flags = window_flags | reaper.ImGui_WindowFlags_NoNav()
    end
    if reaper.APIExists("ImGui_WindowFlags_NoNavInputs") then
        window_flags = window_flags | reaper.ImGui_WindowFlags_NoNavInputs()
    end
    if state.window_locked or state.drag_note ~= nil or state.is_dragging 
       or state.marquee_active or state.is_dragging_dynamic or state.is_resizing_item 
       or state.dragged_pattern ~= nil or state.is_dragging_pattern then
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            window_flags = window_flags | reaper.ImGui_WindowFlags_NoMove()
        end
    end
    
    local visible, open = reaper.ImGui_Begin(ctx, "REAPER Notator", true, window_flags)
    state.is_open = open
    
    if visible then
        reaper.ImGui_SetScrollY(ctx, 0)
        reaper.ImGui_SetScrollX(ctx, 0)
        local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
        local mx, my = reaper.ImGui_GetMousePos(ctx)
        
        state.cur_win_x = win_x
        state.cur_win_y = win_y
        state.cur_win_w = win_w
        state.cur_win_h = win_h
        
        -- Continuously update the monitor where the window is located
        local svx, svy, svw, svh = get_screen_work_area(win_x, win_y, win_w, win_h)
        state.screen_work_x = svx
        state.screen_work_y = svy
        state.screen_work_w = svw
        state.screen_work_h = svh
        
        -- Remember current unmaximized window size (for clean restoration)
        if not state.is_maximized then
            if win_w >= 1000 and win_h >= 600 and (win_w < (vw - 10) or win_h < (vh - 10)) then
                state.prev_win_w = win_w
                state.prev_win_h = win_h
                state.prev_win_x = win_x
                state.prev_win_y = win_y
            end
        end
        
        -- Maximize/Restore Button [🗖] / [🗗] directly in titlebar left of [X]
        local cur_scr_x, cur_scr_y = reaper.ImGui_GetCursorScreenPos(ctx)
        reaper.ImGui_SetCursorScreenPos(ctx, win_x + win_w - 52, win_y + 3)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), 2.0, 1.0)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00000000)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFFFFFF22)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFFFFFF44)
        local title_btn_lbl = state.is_maximized and "🗗##TitleMax" or "🗖##TitleMax"
        if reaper.ImGui_Button(ctx, title_btn_lbl, 22, 18) then
            state.request_maximize_toggle = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, state.is_maximized and "Restore (F11)" or "Maximize (F11)")
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_PopStyleVar(ctx, 1)
        reaper.ImGui_SetCursorScreenPos(ctx, cur_scr_x, cur_scr_y)
        
        -- Double click title bar toggles maximize
        if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and my >= win_y and my <= (win_y + 26) and mx >= win_x and mx <= (win_x + win_w - 60) then
            state.request_maximize_toggle = true
        end

        -- Continuous synchronization & orphan cleanup upon REAPER project changes (e.g. deleted items/tracks)
        local cur_proj_change = reaper.GetProjectStateChangeCount(0)
        local cur_total_tracks = reaper.CountTracks(0)
        if state._last_proj_change_cleanup ~= cur_proj_change or state._last_total_tracks_cleanup ~= cur_total_tracks then
            state._last_proj_change_cleanup = cur_proj_change
            state._last_total_tracks_cleanup = cur_total_tracks
            MidiService.cleanup_orphaned_score_elements(state)
        end

        local project_tracks = MidiService.get_project_midi_tracks()
        
        -- Intercept keyboard shortcuts
        KeyboardHandler.handle(ctx, state, MidiService, ClipboardService, DynamicsEngine, state.active_tracks_cache)
        
        -- Modal dialogs (track selection & help)
        TrackPicker.render(ctx, state, project_tracks)
        HelpModal.render(ctx, state)
        SettingsModal.render(ctx, state, ShortcutManager)
        QuantizeModal.render(ctx, state, MidiService, state.active_tracks_cache)
        BankPickerModal.render(ctx, state, state.focused_track, state.active_tracks_cache)
        ScaleModal.render(ctx, state)
        MusicXmlModal.render(ctx, state, project_tracks)
        ArticulationsDrawer.render_last_resort_modal(ctx, state, state.active_tracks_cache)
        
        -- ======================================================================
        -- 1. TOP BAR (Transport, time display, layout, tracks, zoom, lock, dynamics)
        -- ======================================================================
        local topbar_flags = reaper.ImGui_WindowFlags_NoScrollbar()
        if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
            topbar_flags = topbar_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            topbar_flags = topbar_flags | reaper.ImGui_WindowFlags_NoMove()
        end
        TopBar.render(ctx, state, ClipboardService, MidiService, state.active_tracks_cache, #project_tracks, child_border, topbar_flags)
        
        -- ======================================================================
        -- 2. MAIN AREA: Left sidebar (palette) | Center canvas | Right drawer (resizable)
        -- ======================================================================
        local main_avail_w, main_avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        local bottom_bar_h = 46
        local splitter_w = 6
        local spacing = 4
        
        local h_splitter_h = 6
        local browser_h = 0
        if state.show_pattern_browser then
            state.pattern_browser_h = state.pattern_browser_h or 240
            local max_pb_h = math.max(120, main_avail_h - bottom_bar_h - 160)
            state.pattern_browser_h = math.max(120, math.min(max_pb_h, state.pattern_browser_h))
            browser_h = state.pattern_browser_h + h_splitter_h + 10
        end
        local main_content_h = math.max(100, main_avail_h - bottom_bar_h - browser_h - 6)
        
        state.sidebar_w = state.sidebar_w or 230
        state.drawer_w = state.drawer_w or 236
        
        local canvas_w = main_avail_w - state.sidebar_w - splitter_w - spacing
        if state.show_dynamics or state.show_tempo or state.show_clefs or state.show_articulations_drawer or state.show_key_signatures or state.show_tools_drawer then
            canvas_w = canvas_w - state.drawer_w - splitter_w - spacing
        end
        if canvas_w < 150 then canvas_w = 150 end
        
        local sidebar_flags = 0
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            sidebar_flags = reaper.ImGui_WindowFlags_NoMove()
        end
        
        -- LEFT SIDEBAR: MAIN PALETTE (Resizable via splitter)
        Sidebar.render(ctx, state, MidiService, ClipboardService, state.active_tracks_cache, state.sidebar_w, main_content_h, child_border, sidebar_flags)
        
        -- VERTICAL SPLITTER 1: Left sidebar resizing
        reaper.ImGui_SameLine(ctx, 0, 2)
        reaper.ImGui_InvisibleButton(ctx, "vsplitter_left", splitter_w, main_content_h)
        if reaper.ImGui_IsItemActive(ctx) then
            local delta_x, _ = reaper.ImGui_GetMouseDelta(ctx)
            state.sidebar_w = math.max(140, math.min(500, state.sidebar_w + delta_x))
        end
        if reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx) then
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            local sp_x0, sp_y0 = reaper.ImGui_GetItemRectMin(ctx)
            local sp_x1, sp_y1 = reaper.ImGui_GetItemRectMax(ctx)
            local sp_col = reaper.ImGui_IsItemActive(ctx) and 0xFF9F1CFF or 0xFF9F1C66
            reaper.ImGui_DrawList_AddRectFilled(dl, sp_x0 + 1, sp_y0, sp_x1 - 1, sp_y1, sp_col)
        end
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
            state.sidebar_w = 230 -- Double-click resets to default width
        end
        
        -- CENTER AREA: SCORE CANVAS
        local canvas_flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoMove()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoNav") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoNav()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoNavInputs") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoNavInputs()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoNavFocus") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoNavFocus()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        end
        reaper.ImGui_SameLine(ctx, 0, 2)
        if reaper.ImGui_BeginChild(ctx, "ScoreCanvas", canvas_w, main_content_h, child_none, canvas_flags) then
            local is_canvas_hovered = reaper.ImGui_IsWindowHovered(ctx)
            if not is_canvas_hovered and reaper.APIExists("ImGui_HoveredFlags_ChildWindows") then
                is_canvas_hovered = reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_ChildWindows())
            end

            -- Configurable Mouse & Keyboard View Navigation Engine
            local is_shift = false
            if reaper.APIExists("ImGui_Mod_Shift") and reaper.APIExists("ImGui_GetKeyMods") then
                is_shift = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Shift()) ~= 0
            end
            if not is_shift and reaper.APIExists("ImGui_Key_LeftShift") and reaper.APIExists("ImGui_Key_RightShift") then
                is_shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
            end

            local is_ctrl = false
            if reaper.APIExists("ImGui_Mod_Ctrl") and reaper.APIExists("ImGui_GetKeyMods") then
                is_ctrl = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Ctrl()) ~= 0
            end
            if not is_ctrl and reaper.APIExists("ImGui_Key_LeftCtrl") and reaper.APIExists("ImGui_Key_RightCtrl") then
                is_ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl())
            end

            local is_alt = false
            if reaper.APIExists("ImGui_Mod_Alt") and reaper.APIExists("ImGui_GetKeyMods") then
                is_alt = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Alt()) ~= 0
            end
            if not is_alt and reaper.APIExists("ImGui_Key_LeftAlt") and reaper.APIExists("ImGui_Key_RightAlt") then
                is_alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftAlt()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightAlt())
            end

            local function check_nav_key(key_def)
                if not key_def or key_def == "" or key_def:lower() == "none" then
                    return not is_shift and not is_ctrl and not is_alt
                end
                local k = tostring(key_def):lower()
                if k == "shift" then
                    return is_shift and not is_ctrl and not is_alt
                elseif k == "ctrl" then
                    return is_ctrl and not is_shift and not is_alt
                elseif k == "alt" then
                    return is_alt and not is_ctrl and not is_shift
                elseif k == "space" then
                    return reaper.APIExists("ImGui_Key_Space") and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_Space())
                elseif k == "shift_ctrl" or k == "ctrl_shift" then
                    return is_shift and is_ctrl and not is_alt
                elseif k == "shift_alt" or k == "alt_shift" then
                    return is_shift and is_alt and not is_ctrl
                elseif k == "ctrl_alt" or k == "alt_ctrl" then
                    return is_ctrl and is_alt and not is_shift
                else
                    local need_ctrl = k:find("ctrl") ~= nil
                    local need_shift = k:find("shift") ~= nil
                    local need_alt = k:find("alt") ~= nil
                    if need_ctrl ~= is_ctrl then return false end
                    if need_shift ~= is_shift then return false end
                    if need_alt ~= is_alt then return false end

                    local clean_k = k:gsub("ctrl%+", ""):gsub("shift%+", ""):gsub("alt%+", "")
                    if clean_k == "space" then
                        return reaper.APIExists("ImGui_Key_Space") and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_Space())
                    else
                        local cap = clean_k:sub(1,1):upper() .. clean_k:sub(2)
                        local k_code = ShortcutManager.get_key_enum(cap) or ShortcutManager.get_key_enum(clean_k:upper())
                        if k_code and reaper.APIExists("ImGui_IsKeyDown") then
                            return reaper.ImGui_IsKeyDown(ctx, k_code)
                        end
                    end
                end
                return false
            end

            -- Canvas Pan (Hand Tool / Drag Navigation)
            local pan_mouse = (state.nav_pan_mouse or "mouse_mid"):lower()
            local pan_btn = -1
            if pan_mouse == "mouse_mid" then pan_btn = 2
            elseif pan_mouse == "mouse_right" then pan_btn = 1
            elseif pan_mouse == "mouse_left" then pan_btn = 0
            end

            if pan_btn >= 0 and pan_mouse ~= "disabled" then
                if reaper.ImGui_IsMouseClicked(ctx, pan_btn) and is_canvas_hovered and check_nav_key(state.nav_pan_key or "none") then
                    state._is_canvas_panning = true
                end
                if state._is_canvas_panning then
                    if reaper.ImGui_IsMouseDown(ctx, pan_btn) then
                        local delta_x, delta_y = reaper.ImGui_GetMouseDelta(ctx)
                        if delta_x ~= 0 or delta_y ~= 0 then
                            reaper.ImGui_SetScrollX(ctx, reaper.ImGui_GetScrollX(ctx) - delta_x)
                            reaper.ImGui_SetScrollY(ctx, reaper.ImGui_GetScrollY(ctx) - delta_y)
                        end
                        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll())
                    else
                        state._is_canvas_panning = false
                    end
                end
            end

            -- Mouse Wheel & Trackpad Navigation (Horizontal Scroll, Vertical Scroll, Canvas Zoom)
            if is_canvas_hovered then
                local wh_y = reaper.ImGui_GetMouseWheel(ctx)
                local wh_x = 0
                if reaper.APIExists("ImGui_GetMouseWheelH") then
                    wh_x = reaper.ImGui_GetMouseWheelH(ctx)
                end

                -- Dedicated horizontal mouse wheel / trackpad horizontal gesture
                if wh_x ~= 0 then
                    local sf_h = state.scroll_factor_h or state.scroll_factor or 3.0
                    local dir_h = state.scroll_invert_h and -1 or 1
                    local cur_scroll_x = reaper.ImGui_GetScrollX(ctx)
                    reaper.ImGui_SetScrollX(ctx, cur_scroll_x - (wh_x * 40 * sf_h * dir_h))
                end

                if wh_y ~= 0 then
                    local h_mouse = (state.nav_scroll_h_mouse or "wheel_v"):lower()
                    local v_mouse = (state.nav_scroll_v_mouse or "wheel_v"):lower()
                    local z_mouse = (state.nav_zoom_mouse or "wheel_v"):lower()

                    local is_h = (h_mouse == "wheel_v" or h_mouse == "wheel_h") and check_nav_key(state.nav_scroll_h_key or "shift")
                    local is_v = (v_mouse == "wheel_v") and check_nav_key(state.nav_scroll_v_key or "none")
                    local is_z = (z_mouse == "wheel_v") and check_nav_key(state.nav_zoom_key or "ctrl")

                    if is_h then
                        local sf_h = state.scroll_factor_h or state.scroll_factor or 3.0
                        local dir_h = state.scroll_invert_h and -1 or 1
                        local cur_scroll_x = reaper.ImGui_GetScrollX(ctx)
                        reaper.ImGui_SetScrollX(ctx, cur_scroll_x - (wh_y * 40 * sf_h * dir_h))
                    elseif is_v then
                        local has_no_wheel = reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse")
                        if has_no_wheel or (state.nav_scroll_v_key and state.nav_scroll_v_key ~= "none") then
                            local sf_v = state.scroll_factor_v or 2.0
                            local dir_v = state.scroll_invert_v and -1 or 1
                            local cur_scroll_y = reaper.ImGui_GetScrollY(ctx)
                            reaper.ImGui_SetScrollY(ctx, cur_scroll_y - (wh_y * 40 * sf_v * dir_v))
                        end
                    elseif is_z then
                        local z_step = (wh_y > 0) and 0.08 or -0.08
                        state.zoom = math.max(0.6, math.min(2.0, state.zoom + z_step))
                    end
                end
            end
            
            local ok, canvas_info = pcall(ScoreCanvas.render, ctx, state, fonts, project_tracks, MidiService)
            if ok and canvas_info then
                state.active_tracks_cache = canvas_info.active_tracks_data
                local m_ok, m_err = pcall(MouseHandler.handle, ctx, state, canvas_info, MidiService, DynamicsEngine)
                if not m_ok then
                    reaper.ShowConsoleMsg("[ScoreCanvas MouseHandler Error] " .. tostring(m_err) .. "\n")
                end
            elseif not ok then
                reaper.ShowConsoleMsg("[ScoreCanvas Render Error] " .. tostring(canvas_info) .. "\n")
            end
            reaper.ImGui_EndChild(ctx)
        end
        
        -- RIGHT AREA: DYNAMICS, TEMPO, CLEF, KEY SIGNATURE, ARTICULATIONS OR TOOLS DRAWER (Resizable via splitter)
        if state.show_dynamics or state.show_tempo or state.show_clefs or state.show_articulations_drawer or state.show_key_signatures or state.show_tools_drawer then
            -- VERTICAL SPLITTER 2: Right drawer resizing
            reaper.ImGui_SameLine(ctx, 0, 2)
            reaper.ImGui_InvisibleButton(ctx, "vsplitter_right", splitter_w, main_content_h)
            if reaper.ImGui_IsItemActive(ctx) then
                local delta_x, _ = reaper.ImGui_GetMouseDelta(ctx)
                state.drawer_w = math.max(180, math.min(500, state.drawer_w - delta_x))
            end
            if reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx) then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                local sp_x0, sp_y0 = reaper.ImGui_GetItemRectMin(ctx)
                local sp_x1, sp_y1 = reaper.ImGui_GetItemRectMax(ctx)
                local sp_col = reaper.ImGui_IsItemActive(ctx) and 0xFF9F1CFF or 0xFF9F1C66
                reaper.ImGui_DrawList_AddRectFilled(dl, sp_x0 + 1, sp_y0, sp_x1 - 1, sp_y1, sp_col)
            end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                state.drawer_w = 236 -- Double-click resets to default width
            end
            
            reaper.ImGui_SameLine(ctx, 0, 2)
            if state.show_tools_drawer then
                ToolsDrawer.render(ctx, state, MidiService, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags, fonts.font_music, fonts.font_main)
            elseif state.show_clefs then
                ClefDrawer.render(ctx, state, state.drawer_w, main_content_h, child_border, sidebar_flags, fonts.font_music, fonts.font_main)
            elseif state.show_key_signatures then
                KeySignatureDrawer.render(ctx, state, KeySignatureService, MidiService, state.drawer_w, main_content_h, child_border, sidebar_flags, fonts.font_music, fonts.font_main)
            elseif state.show_tempo then
                TempoDrawer.render(ctx, state, state.drawer_w, main_content_h, child_border, sidebar_flags)
            elseif state.show_dynamics then
                DynamicsDrawer.render(ctx, state, DynamicsEngine, MidiService, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags)
            elseif state.show_articulations_drawer then
                ArticulationsDrawer.render(ctx, state, MidiService, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags)
            end
        end
        
        -- ======================================================================
        -- 2b. BOTTOM PANE: PATTERN BROWSER (Resizable via horizontal splitter!)
        -- ======================================================================
        if state.show_pattern_browser then
            -- HORIZONTAL SPLITTER: Bottom pane resizing
            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 2)
            reaper.ImGui_InvisibleButton(ctx, "hsplitter_bottom_browser", main_avail_w, h_splitter_h)
            if reaper.ImGui_IsItemActive(ctx) then
                local _, delta_y = reaper.ImGui_GetMouseDelta(ctx)
                local max_pb_h = math.max(120, main_avail_h - bottom_bar_h - 160)
                state.pattern_browser_h = math.max(120, math.min(max_pb_h, state.pattern_browser_h - delta_y))
                reaper.SetExtState("REAPER_Notator", "PatternBrowserHeight", tostring(math.floor(state.pattern_browser_h)), true)
            end
            if reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx) then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                local sp_x0, sp_y0 = reaper.ImGui_GetItemRectMin(ctx)
                local sp_x1, sp_y1 = reaper.ImGui_GetItemRectMax(ctx)
                local sp_col = reaper.ImGui_IsItemActive(ctx) and 0xE67E22FF or 0xE67E2277
                reaper.ImGui_DrawList_AddRectFilled(dl, sp_x0, sp_y0 + 1, sp_x1, sp_y1 - 1, sp_col)
            end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                state.pattern_browser_h = 240 -- Double-click resets to default height
                reaper.SetExtState("REAPER_Notator", "PatternBrowserHeight", "240", true)
            end
            
            PatternBrowser.render(ctx, state, MidiService, AudioPreview, main_avail_w, state.pattern_browser_h, project_tracks, fonts.font_music, fonts.font_main)
        end
        
        -- ======================================================================
        -- 3. STATUS & RASTER BAR (Bottom)
        -- ======================================================================
        local bottom_flags = 0
        if reaper.APIExists("ImGui_WindowFlags_NoScrollbar") then
            bottom_flags = bottom_flags | reaper.ImGui_WindowFlags_NoScrollbar()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
            bottom_flags = bottom_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            bottom_flags = bottom_flags | reaper.ImGui_WindowFlags_NoMove()
        end
        BottomBar.render(ctx, state, bottom_bar_h, child_border, bottom_flags)
        
        reaper.ImGui_End(ctx)
    end
    
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopStyleColor(ctx, 7)
    
    if state.is_open then
        AudioPreview.update(state, ctx)
        PatternService.update_preview(AudioPreview)
        reaper.defer(loop)
    else
        AudioPreview.stop_all(state)
        PatternService.stop_preview(AudioPreview)
    end
end

-- Start application
reaper.defer(loop)

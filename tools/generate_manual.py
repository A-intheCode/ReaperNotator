#!/usr/bin/env python3
"""
REAPER-Notator - Complete User Manual & Documentation Generator
Generates:
  1. tools/user_manual.md (GitHub Markdown documentation)
  2. docs/reaper_notator_user_manual.pdf (Full publication-grade PDF manual)
"""

import os
import re
import datetime
from fpdf import FPDF
from fpdf.enums import XPos, YPos

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS_DIR = os.path.join(REPO_ROOT, "docs")
TOOLS_DIR = os.path.join(REPO_ROOT, "tools")
os.makedirs(DOCS_DIR, exist_ok=True)
os.makedirs(TOOLS_DIR, exist_ok=True)

MD_PATH = os.path.join(TOOLS_DIR, "user_manual.md")
PDF_PATH = os.path.join(DOCS_DIR, "reaper_notator_user_manual.pdf")

def get_version():
    ver_file = os.path.join(REPO_ROOT, "modules", "version.lua")
    if os.path.exists(ver_file):
        with open(ver_file, "r", encoding="utf-8") as vf:
            content = vf.read()
            m_maj = re.search(r"major\s*=\s*(\d+)", content)
            m_min = re.search(r"minor\s*=\s*(\d+)", content)
            m_pat = re.search(r"patch\s*=\s*(\d+)", content)
            m_suf = re.search(r'suffix\s*=\s*"([^"]*)"', content)
            suf = m_suf.group(1) if m_suf else ""
            if m_maj and m_min and m_pat:
                pat = int(m_pat.group(1))
                if pat == 0:
                    return f"{m_maj.group(1)}.{m_min.group(1)}{suf}"
                return f"{m_maj.group(1)}.{m_min.group(1)}.{pat}{suf}"
    return "2.15"

VERSION = get_version()

MANUAL_DATA = [
    {
        "chapter": 1,
        "title": "Introduction & Interface Architecture",
        "sections": [
            {
                "heading": "1.1 Overview, Vision & Prerequisites",
                "text": "REAPER-Notator is a native, professional music scoring, notation editing, and engraving environment built directly into Cockos REAPER using ReaImGui and standard SMuFL (Standard Music Font Layout) Bravura vector glyphs. Unlike external scoring applications, Notator runs directly inside REAPER's audio engine and timeline, providing instantaneous two-way synchronization between visual music notation and underlying REAPER MIDI takes, CC automation, and tempo maps.\n\n"
                        "Prerequisites & System Requirements:\n"
                        "- Cockos REAPER v7.0 or higher.\n"
                        "- ReaImGui extension (v0.9+ via ReaPack).\n"
                        "- Reaticulate (Required prerequisite for articulation handling, sound bank definitions, keyswitch chasing, and playback routing; install via ReaPack: https://reaticulate.com/).\n"
                        "- SWS / S&M Extension & JS_ReaScriptAPI (recommended)."
            },
            {
                "heading": "1.2 The Three-Column Workspace Layout",
                "text": "The user interface is designed around an ergonomic three-column layout:\n\n"
                        "- Left Column (Sidebar Palette): Quick tools for note entry modes (pointer, pencil, text, eraser), rhythmic durations (whole to 32nd notes), augmentation dots, accidentals, tuplets, stem orientation, and articulation toggles.\n"
                        "- Center Column (Score Canvas): Infinite interactive notation canvas displaying visual staves, barlines, noteheads, stems, beams, ties, slurs, lyrics, and rehearsal marks.\n"
                        "- Right Column (Context Drawers & Tool Panels): Collapsible slide-out panels for Dynamics automation, Reaticulate banks, Tempo maps, Clef palettes, Key signatures, Pattern browser, and Settings."
            },
            {
                "heading": "1.3 Window Resizing, Docking, Multi-Monitor 4K HiDPI & 2-Step Maximize Engine",
                "text": "REAPER-Notator can run as a floating window or docked directly into any REAPER docker (bottom, top, left, right, or multi-tabbed). The score canvas dynamically scales according to the zoom factor (adjustable from 0.6x to 2.0x), preserving crisp vector typography at all DPI scaling factors.\n\n"
                        "2-Step Monitor Maximize, Startup Centering & Multi-Monitor HiDPI Management (v2.0.1 - v2.0.7):\n"
                        "- Centered Floating Startup (Clean Session Launch): On every REAPER startup or script launch, REAPER-Notator first queries the maximum possible work area of the target monitor and opens in a clean, centered floating window in the middle of the screen. Maximization state (is_maximized) is intentionally not persisted across restarts so the user always retains full control and the window can never get stuck in an un-restorable geometry.\n"
                        "- 2-Step Screen Maximize & Restore Toggle (Top Bar / F11): Clicking the Maximize button in the top-right toolbar (or pressing F11) executes a deterministic two-step sequence: (1) it reads the full work area bounds of the monitor where the window currently resides and stores a centered floating restore rectangle in the middle of that monitor, and (2) scales the window cleanly to 100% of the monitor work area. Clicking Restore returns the window directly to the centered floating geometry.\n"
                        "- Multi-Monitor & 4K HiDPI Coordinate-Space Calibration (v2.0.7): Automatically detects mixed-DPI multi-monitor setups (such as a 4K laptop display at 150%-250% scaling alongside a 1080p external monitor at 100% scaling) without relying on REAPER's main window viewport or hardcoded 16:9 limits. Live OS HWND rectangle verification (JS_Window_GetRect vs. ReaImGui logical window coordinates + Stage 3 post-maximize verification) ensures maximizing fills 100% of any monitor regardless of aspect ratio or Windows DPI scaling.\n"
                        "- Anti-Collapse Title Bar Guard & Legacy Cleanup: Uses ImGui_WindowFlags_NoCollapse and ImGui_SetNextWindowCollapsed(ctx, false) so double-clicking the title bar never collapses the window into an unresponsive shaded bar, and automatically purges obsolete pre-v2 ExtState entries on startup.\n"
                        "- Always-On-Top Modal Layering: All secondary configuration dialogs (Record & Auto-Quantize, Filter Irregular Notes, Quantize, Divisio Vocum, Bank Picker, Settings, and Help) render with ImGui_WindowFlags_TopMost, remaining strictly in the foreground above the score canvas."
            }
        ]
    },
    {
        "chapter": 2,
        "title": "Top Toolbar, Live Recording Suite & Global Navigation",
        "sections": [
            {
                "heading": "2.1 Title & Version Indicator",
                "text": f"Located in the upper left corner, displaying 'REAPER Notator' alongside the active build and semantic version number (v{VERSION}), synchronized directly with modules/version.lua and the main @version header. When running in a Git repository environment, Notator automatically detects and displays the active commit hash via pure-Lua .git/HEAD inspection."
            },
            {
                "heading": "2.2 Transport & Playhead Controls",
                "text": "Functions:\n"
                        "- Rewind (|<): Instantly returns REAPER's edit cursor to measure 1.0 (time 0.0s).\n"
                        "- Play / Pause (> / ||): Starts timeline playback or pauses at the current cursor position. Key shortcut: Space.\n"
                        "- Record ([Rec] / [REC]): Dedicated transport recording button situated between Play and Stop.\n"
                        "  * Left-Click: Starts REAPER recording immediately (CSurf_OnRecord / Action 1013) when stopped, glowing in vivid signal red ([REC]). Clicking the red button again while recording is active calls CSurf_OnStop(), stopping both Recording and Playback completely in one click.\n"
                        "  * Right-Click: Opens the Recording & Auto-Quantize Settings modal dialog (RecordModal).\n"
                        "- Stop: Halts playback or recording completely, commits the Auto-Quantize engine to newly recorded takes (if enabled), and resets the playhead according to REAPER's project settings.\n"
                        "DAW Effect: Calls REAPER's CSurf_OnPlay, CSurf_OnRecord, CSurf_OnStop, and SetEditCurPos directly, maintaining sample-accurate alignment with REAPER's master audio engine."
            },
            {
                "heading": "2.3 Live Canvas Recording Playhead & Real-Time Live Note Preview (v2.0+)",
                "text": "Functions:\n"
                        "- Signal-Red Recording Playhead: During active recording, the score canvas renders a high-visibility signal-red vertical sweep line (0xE74C3CFF) capped with a red triangular pointer ([v]) moving in real time across all staves.\n"
                        "- Real-Time Live Note Preview: Polls incoming hardware and virtual MIDI Note-On and Note-Off events in real time via MIDI_GetRecentInputEvent and engraves played notes live on the score canvas at the red playhead with glowing red/coral noteheads and dynamically growing note durations while keys are held down.\n"
                        "- Non-Destructive Live Clamping (Zero Infinite Tie Artifacts): While recording in MIDI Overdub mode, REAPER temporarily sets the Note-Off of held notes to the end of the MIDI item until the key is released. REAPER-Notator performs real-time auto-quantize preview non-destructively on the ScoreCanvas (strictly clamping held notes to the current red playhead position) without calling MIDI_SetNote/MIDI_Sort mid-recording, and commits the final quantized notes and stop-position clamping cleanly to the REAPER take the instant recording stops.\n"
                        "- Continuous 60 FPS Auto-Scroll & Counter Tracking: The score viewport smoothly tracks the live recording playhead and updates the top bar Measure.Beat and elapsed time counters continuously."
            },
            {
                "heading": "2.4 Right-Click Record Modal: Track Arming, MIDI Input Routing, Auto-Divisi Live Recording, Pre-Roll & Count-In (v2.0 - v2.50)",
                "text": "Functions (accessible by right-clicking the Record button in the Top Toolbar):\n"
                        "- Bidirectional REAPER Track Arming: Lists all REAPER project tracks (including empty tracks that do not yet contain MIDI items). Toggling a track's checkbox in the Record Modal immediately synchronizes REAPER's native TCP/MCP Record-Arm button (I_RECARM = 1), enables Input Monitoring (I_RECMON = 1), configures MIDI Overdub (I_RECMODE = 7) so REAPER records directly into MIDI score takes without popping up Audio '.wav' Save prompts, and makes the track visible on the score canvas.\n"
                        "- Armed Track Red Canvas Badges (Genuine User Arming Only, v2.0.7): Any track genuinely armed for recording by the user displays a subtle red background tint, red outer border, red left accent stripe, and a crisp vector circle 'REC' pill badge in the track header (with automatic track title truncation so the badge and track name never overlap). Temporary internal Virtual MIDI Keyboard routing during note click auditioning (AudioPreview.is_track_user_armed) is strictly excluded so auditioning a note never triggers the red 'REC' badge.\n"
                        "- Auto-Divisi Live Recording & Zero-Latency Input FX Router (v2.29+): When 2 or more orchestral tracks are armed and 'Auto-Divisi Mode (Distribute Simultaneous Notes & Registers across Armed Tracks)' is enabled, REAPER-Notator automatically installs a zero-latency JSFX Input Router (Notator_AutoDivisi_Router.jsfx) on the armed tracks and distributes live keyboard playing across the armed instruments in real time:\n"
                        "  * 1 Note Played -> Only the single matching register instrument sounds and records (e.g. playing C2 triggers only Double Bass).\n"
                        "  * 2+ Notes Played Simultaneously -> Chords are distributed harmonically across the armed instruments (Low -> Celli/Basses, Mid -> Violas, High -> Violins I/II) using either 'Smart Register & Voice Split' or 'Top-Down Voice Split'.\n"
                        "  * Tick-Based Chord & Legato Transition Guard (+/-10 to +/-160 Ticks, default +/-45 Ticks at 960 PPQ): Groups chord finger attacks within +/-N ticks into one simultaneous chord, trims brief legato finger-release overlaps (<= N ticks) so monophonic melodies stay on the same instrument without false Divisi jumps, and filters out accidental micro-splinter notes.\n"
                        "- MIDI Input Device & Channel Selector: Choose from all connected hardware MIDI keyboards, REAPER's Virtual MIDI Keyboard (VKB), or 'All MIDI Inputs', alongside the target MIDI Channel ('All Channels' or 'Channel 1..16'), assignable globally across armed tracks or individually per track.\n"
                        "- Pre-Roll on Record (Action 41818): Toggle to audition preceding measures before recording punches in, with selectable Pre-Roll Bar Length (1, 2, or 4 bars synchronized with REAPER's prerollmeas configuration).\n"
                        "- Metronome Count-In before Record (Action 40364): Enables audible metronome lead-in clicks before recording starts, plus a 1-click shortcut button to open REAPER's native Metronome / Pre-Roll Settings dialog (Action 40049)."
            },
            {
                "heading": "2.5 Real-Time & Post-Record Auto-Quantize Engine (v2.0+)",
                "text": "Functions:\n"
                        "- Live Preview & Automatic Commit on Stop: Previews quantized rhythmic positions live on the score canvas during recording and automatically processes newly recorded MIDI notes on all armed tracks the moment recording stops.\n"
                        "- Configurable Quantize Grid: Select target rhythmic division (1/4, 1/8, 1/16, 1/32, with optional Triplet grid recognition).\n"
                        "- Key Bounce & Overlap Cleaning: Automatically eliminates mechanical keyboard pre-bounces (< 15 ticks on identical pitch), deduplicates multiple notes snapping to the same grid slot, and trims overlapping same-pitch note tails to 1 tick prior to the next note onset.\n"
                        "- Strict Tick Tolerance Slider (5 to 60 Ticks, default 25 Ticks): Defines the timing window around each rhythmic grid division.\n"
                        "- Four Outlier Handling Modes ('Notes outside tolerance'):\n"
                        "  1. '[Snap] Snap to Grid' (Default): Magnetizes all recorded notes—including notes played outside the strict tick tolerance window—cleanly onto the nearest rhythmic grid division for immediately clean, readable sheet music.\n"
                        "  2. 'Keep natural (unquantized)': Snaps notes within the tolerance window to the grid while preserving played micro-timing for notes outside the window.\n"
                        "  3. 'Delete outliers': Removes stray accidental key touches that fall outside the tolerance window.\n"
                        "  4. 'Move to Voice 16': Routes outlier notes outside the tolerance window to Voice 16 (MIDI channel 15) so they remain audible in playback while keeping Voice 1 notation pristine.\n"
                        "- Transactional Undo Safety: Enclosed within a single REAPER undo block (Undo_BeginBlock2) for instant rollback via Ctrl+Z."
            },
            {
                "heading": "2.6 Timeline & Meter Displays",
                "text": "Functions:\n"
                        "- Measure.Beat Display: Real-time read-out of playhead position in musical bars, beats, and quarter-note ticks (e.g. '004.01.00').\n"
                        "- Time Signature Indicator: Active project meter (e.g. 4/4, 3/4, 6/8, 7/8).\n"
                        "- BPM Indicator: Project master tempo at the current playhead position.\n"
                        "DAW Effect: Evaluates TimeMap_GetTimeSigAtTime on every frame to mirror timeline accelerandos, ritardandos, and time signature changes."
            },
            {
                "heading": "2.7 Audition Preview (Note Audio on Click) & Static Viewport Focus (v2.0.7)",
                "text": "Functions:\n"
                        "- Single-Note Audition: Clicking or vertically dragging any note on the canvas triggers an immediate acoustic preview sound, arbitrated to audition strictly the single hovered note even in dense chords or adjacent systems.\n"
                        "- Clean Note Audition Without 'REC' Badge (v2.0.7): AudioPreview.is_track_user_armed(track) distinguishes genuine user record-arming from temporary Virtual MIDI Keyboard preview routing. Clicking or dragging notes to audition them never displays the red 'REC' pill badge or red recording border on the instrument track header, and restores exact track states immediately after the note finishes ringing out.\n"
                        "- Static ScoreCanvas Viewport on Note Click (v2.0.7): Clicking notes, item header badges, clefs, or track headers on the ScoreCanvas selects the parent MIDI item and track in REAPER while keeping the ScoreCanvas viewport (scroll_x and scroll_y) completely stationary—unless Follow Playhead / Auto-Scroll (state.auto_scroll) is explicitly enabled.\n"
                        "- Instant Zero-Latency Response: Notes trigger instantly on mouse click with 0 ms latency, exactly like auditioning within REAPER's native MIDI Editor.\n"
                        "- Dynamics & Articulation Chasing: The engine scans the project timeline from measure 1 to chase active Program Changes, note-level articulation marks (Staccato, Marcato, Tenuto, Pizzicato), and configured CC dynamics (CC11 Expression / CC1 Modwheel).\n"
                        "- Musical Minimum Duration: Short clicks sound for a minimum of 650 ms so that instrument attack transients, body, and acoustic room release tails ring out cleanly before Note-Off is dispatched.\n"
                        "DAW Effect: Dispatches synchronized Bank Select, Program Change, CC controllers, and instantaneous MIDI Note-On / scheduled Note-Off events to the active track's virtual instrument synth while preserving original user record-arm states."
            },
            {
                "heading": "2.8 Follow Playhead (Auto-Scroll)",
                "text": "Function: When active, the score canvas scrolls horizontally in real time to keep the active playback cursor centered in the viewport."
            },
            {
                "heading": "2.9 View Mode Selector & Automatic Instrument Clef Detection (incl. Percussion Clef, v2.50)",
                "text": "Functions:\n"
                        "- Auto: Automatically detects each track's optimal clef (Treble, Bass, Alto, Tenor, Grand Staff, or Percussion Clef) from track naming heuristics and pitch registers.\n"
                        "- Automatic Unpitched Percussion Clef Detection (v2.50-beta): Tracks named after genuine unpitched drum and percussion instruments (Snare, Kick, Bass Drum, Gran Cassa, Drum Kit, Drums, Taiko, Tom, Hi-Hat, Cymbal, Piatti, Gong, Tam-Tam, Tambourine, Shaker, Maracas, Conga, Bongo, Timbales, Claves, Woodblock, Triangle, Anvil, Castanets, Battery, Perc, etc.) automatically receive the Percussion Clef (percussion_1). Pitched orchestral percussion instruments are deliberately excluded and assigned their standard pitched clefs (Timpani -> Bass Clef; Xylophone, Marimba, Vibraphone, Glockenspiel, Crotales, Tubular Bells/Chimes -> Treble Clef; Celesta -> Grand Staff).\n"
                        "- Per-Track Clef Palette & Context Menu Override: Any track's clef (Treble, Bass, Alto, Tenor, Grand Staff, Percussion Clef 1, Percussion Clef 2) can also be manually set at any time via the Clef Drawer or by right-clicking the clef on the score canvas."
            },
            {
                "heading": "2.10 Track Picker & Visibility Filters",
                "text": "Function: Opens a multi-track routing popover allowing the user to select which REAPER tracks are currently visible, focused, or edited on the score canvas."
            },
            {
                "heading": "2.11 Multi-Voice System & Auto-Voice Overlap Splitting",
                "text": "Functions:\n"
                        "- 16 Polyphonic Voices: Maps MIDI channels 0-15 to 16 distinct engraving colors with configurable ghost voice opacity (5% to 100%).\n"
                        "- Auto-Voice: Intelligently analyzes the entire track for polyphonic overlaps and distributes them to channels 1-16.\n"
                        "- Auto-Split on Selection: Splits selected chordal intervals across independent voices with automatic opposite stem orientations."
            },
            {
                "heading": "2.12 Settings Modal & Unified Dark Mode Inversion",
                "text": "Functions:\n"
                        "- Collapsible Categorization: Settings are structured into 5 collapsible category headers (Theme & Appearance, Engraving & Notation, Audition & Playback, Shortcuts, and Advanced).\n"
                        "- Single Vertical Scroll Container: The entire modal body scrolls smoothly within a single child window, preventing double scrollbars and layout clipping.\n"
                        "- Static Action Footer: Pinned at the bottom with quick access to Reset and Close actions.\n"
                        "- Real-Time Shortcut Filter: Interactive search bar to quickly locate and rebind key actions.\n"
                        "- Comprehensive Dark Mode Inversion: Full palette inversion across all score elements, including noteheads, stems, beams, clefs, time signatures, rests, ties, lyrics, rehearsal marks, fermatas, and polyphonic voice colors."
            }
        ]
    },
    {
        "chapter": 3,
        "title": "Score Canvas & Note Editing Engine",
        "sections": [
            {
                "heading": "3.1 Note Entry & Pitch Snapping",
                "text": "Functions:\n"
                        "- Click on Staff: Inserts a new note with the duration selected in the sidebar at the nearest diatonic line or space.\n"
                        "- Ledger Lines: When moving beyond the 5 staff lines, Notator automatically calculates and renders standard-compliant ledger lines above or below the staff.\n"
                        "DAW Effect: Inserts a new MIDI note event into the focused track's active MIDI take via REAPER's MIDI_InsertNote API."
            },
            {
                "heading": "3.2 Note Duration, Augmentation Dots & Grid Synchronization",
                "text": "Functions:\n"
                        "- Note Values: Supports 1/1 (Whole), 1/2 (Half), 1/4 (Quarter), 1/8 (Eighth), 1/16 (16th), and 1/32 (32nd) notes (number keys 1 through 6).\n"
                        "- Augmentation Dot: Toggles 1.5x duration expansion (keyboard shortcut: . [period]). A dotted quarter note spans 1.5 quarter notes (3 eighths).\n"
                        "- Grid & Note Duration Synchronization ([Link] Button / Ctrl+K): Allows linking the active note entry duration to the score grid snapping value so that adjusting one automatically updates the other.\n"
                        "- Dedicated Grid Hotkeys (Ctrl+1 .. Ctrl+7): Instantly sets score grid snapping via keyboard: Ctrl+7=1/1, Ctrl+6=1/2, Ctrl+5=1/4, Ctrl+4=1/8, Ctrl+3=1/16, Ctrl+2=1/32, Ctrl+1=Free Grid.\n"
                        "DAW Effect: Sets note start and end positions accurately in Quarter Note (QN) timeline units."
            },
            {
                "heading": "3.3 Accidentals (Sharps, Flats, Naturals)",
                "text": "Functions:\n"
                        "- Flat (b): Decreases chromatic pitch by 1 semitone (-1).\n"
                        "- Natural (nat): Cancels preceding sharp/flat accidentals according to Western music engraving conventions (0).\n"
                        "- Sharp (#): Increases chromatic pitch by 1 semitone (+1).\n"
                        "DAW Effect: Transposes the underlying MIDI note number (0-127) and tags visual notation accidentals."
            },
            {
                "heading": "3.4 Note Manipulation & Live MIDI Item Edge Resizing",
                "text": "Functions:\n"
                        "- Horizontal Drag: Moves notes forward or backward in time, snapping to the selected rhythmic grid (e.g. 1/4, 1/8, 1/16).\n"
                        "- Vertical Drag: Transposes note pitch chromatically. Moving noteheads automatically updates accidentals.\n"
                        "- End-Edge Drag: Lengthens or shortens note duration by pulling the right edge of the notehead.\n"
                        "- Arrow Keys: Up/Down transposes by semitones (Shift+Up/Down by octaves). Left/Right moves by grid increments.\n"
                        "- Live MIDI Item Edge Resizing: Hovering and dragging the left or right boundary edges of any MIDI item directly on the score canvas scales the item with instantaneous, real-time visual feedback during the drag (eliminating latency until mouse release) and updates REAPER's timeline media item bounds synchronously.\n"
                        "DAW Effect: Calls MIDI_SetNote and REAPER's SetMediaItemInfo_Value to update pitch, QN start, QN end, and item timeline boundaries in real time with atomic undo history."
            },
            {
                "heading": "3.5 Multi-Note Selection & Marquee Tool",
                "text": "Functions:\n"
                        "- Marquee / Box Selection: Click and drag on empty canvas space to draw a selection rectangle encompassing multiple notes across measures and staves.\n"
                        "- Shift + Click: Add individual notes to selection.\n"
                        "- Delete / Backspace: Deletes all currently selected notes simultaneously, automatically purging all associated REAPER Type 15 NOTE notation tags (articulations, custom percussion noteheads, and ties) and recalculating Auto-Chase return events so no orphaned notation tags remain in the MIDI take (v2.49-beta).\n"
                        "DAW Effect: Multi-note batch deletion and batch transposition with atomic REAPER undo block."
            },
            {
                "heading": "3.6 Second-Interval Collision & Voice Separation",
                "text": "Functions:\n"
                        "- Second Intervals (Seconds): Notes placed on adjacent staff degrees in the same chord automatically offset horizontally (left/right) according to Elaine Gould engraving rules to prevent notehead collisions.\n"
                        "- Multi-Voice Stems: Polyphonic voices automatically flip stems (Voice 1 stems up, Voice 2 stems down)."
            },
            {
                "heading": "3.7 Standard Gould Rests & Polyphonic Rest Consolidation",
                "text": "Functions:\n"
                        "- Empty Measure Rests: Empty measures automatically display a centered whole-measure rest glyph.\n"
                        "- Rhythmic Rest Decomposition: Gaps between notes decompose into standard rests (quarter, eighth, 16th rests) strictly aligned to the meter division.\n"
                        "- Polyphonic Rest Consolidation (Behind Bars p. 308): Coincident identical rests across simultaneous voices merge into a single shared centered rest, and rests strictly avoid colliding with active sounding noteheads on secondary voices."
            },
            {
                "heading": "3.8 Non-Mouse Keyboard Note Navigation & Selection Expansion",
                "text": "Functions:\n"
                        "- Alt + Left / Right Arrows: Sequential note navigation along the timeline without mouse usage, selecting the previous or next note.\n"
                        "- Alt + Shift + Left / Right Arrows: Extends and expands note selections chronologically across the measure and score.\n"
                        "- Auto-Scroll Synchronization: When Follow Playhead / Auto-Scroll is active, the score canvas smoothly glides to keep newly selected notes centered in view."
            },
            {
                "heading": "3.9 Percussion Clef Systems, General MIDI (GM) Drum Mapping (C0-C9) & Custom Percussion Noteheads (v2.48 - v2.50-beta.3)",
                "text": "Functions & Drum / Percussion Notation Architecture:\n"
                        "- Unpitched Percussion Clef Staves (percussion_1 / percussion_2): On any Percussion Clef staff, key signature accidentals and chromatic notehead accidentals (#, b, nat) are automatically suppressed so drum notation remains completely clean.\n"
                        "- Full-Range General MIDI (GM) Drum Map (MIDI 0..127 / C0 to C9, v2.50-beta.3): Clicking or dragging notes on a Percussion Clef staff directly triggers and maps General MIDI standard drum pitches (Constants.GM_DRUM_STEP_MAP and Constants.GM_STEP_TO_DRUM_PITCH):\n"
                        "  * Step 36 (1st Space from bottom, F4): Kick / Bass Drum (MIDI 36 C2 & MIDI 35 B1).\n"
                        "  * Step 37 (2nd Line, G4): Low Floor Tom (MIDI 41 F2).\n"
                        "  * Step 38 (2nd Space, A4): High Floor Tom / Pedal Hi-Hat (MIDI 43 G2 & MIDI 44 G#2).\n"
                        "  * Step 39 (Middle Line, B4): Low Tom (MIDI 45 A2).\n"
                        "  * Step 40 (3rd Space, C5): Snare Drum / Side Stick / Electric Snare / Hand Clap (MIDI 38 D2, 37 C#2, 39 D#2, 40 E2).\n"
                        "  * Step 41 (4th Line, D5): Low-Mid / Hi-Mid Tom (MIDI 47 B2 & 48 C3).\n"
                        "  * Step 42 (4th Space, E5): High Tom / Cowbell (MIDI 50 D3 & 56 G#3).\n"
                        "  * Step 43 (Top Line, F5): Ride Cymbal / Closed & Open Hi-Hat / Tambourine (MIDI 51 D#3, 42 F#2, 46 A#2, 53 F3, 54 F#3).\n"
                        "  * Step 44 (Space above staff, G5): Ride Cymbal 2 / Chinese Cymbal (MIDI 59 B3 & 52 E3).\n"
                        "  * Step 45 (1st Ledger Line above staff, A5): Crash Cymbal 1 & 2 / Splash Cymbal (MIDI 49 C#3, 55 G3, 57 A3).\n"
                        "  * Full C0-C9 Octave-Consistent Extension (v2.50-beta.3): Any MIDI note pitched below B1 (< 35, down to C0 = 0) or above A5 (> 81, up to G9 = 127) is automatically mapped via pitch-class folding (60 + (pitch % 12)) onto the exact same fixed Percussion Clef staff positions (Steps 36..45) without ever falling back to Treble Clef ledger lines.\n"
                        "- Manual Custom & Percussion Notehead Assignment ('[Drum] Notehead / Percussion Head'):\n"
                        "  * Standard Oval Default (v2.50-beta.1): All newly entered notes on Percussion Clef staves default to standard oval noteheads ('standard')—no cross or triangle noteheads are forced automatically.\n"
                        "  * Right-Click Notehead Submenu: Right-click any note (or multi-note selection) on any staff and open '[Drum] Notehead / Percussion Head' to manually assign any of the 9 Elaine Gould / SMuFL notehead types:\n"
                        "    1. Standard (Default Oval) - Standard filled/half/whole oval notehead.\n"
                        "    2. Cross (X) - Hi-Hat / Cymbal (U+E0A9 / U+E0A8 / U+E0A6).\n"
                        "    3. Circled Cross - Open / Crash Cymbal (U+E0B3).\n"
                        "    4. Diamond - Harmonic / Ride Bell / Rim (U+E0DB / U+E0DD / U+E0D8).\n"
                        "    5. Triangle Up - Triangle / Woodblock / Cowbell (U+E0BE / U+E0BD / U+E0BC).\n"
                        "    6. Slash - Rhythmic Slash / Rimshot (U+E101 / U+E102 / U+E103).\n"
                        "    7. Circle / Open - Tambourine / Open Tone (U+E0E8 / U+E0A3).\n"
                        "    8. Plus (+) - Muted / Stopped / Dead Stroke (U+E0AF).\n"
                        "    9. Ghost / Parenthesized - Ghost Note (Standard oval enclosed in SMuFL parentheses).\n"
                        "  * Persistent Storage & Stem Alignment: Stored losslessly in the MIDI take via REAPER Type 15 notation events (`NOTE <pitch> <chan> head <type>`) with exact per-glyph stem attachment coordinates for both upward and downward stems at all zoom levels (0.6x to 2.0x)."
            }
        ]
    },
    {
        "chapter": 4,
        "title": "Standard-Compliant Automatic Beaming Engine",
        "sections": [
            {
                "heading": "4.1 Meter-Based Beat Grouping",
                "text": "Functions: Consecutive eighth, 16th, and 32nd notes automatically connect with solid beams. Beaming boundaries strictly observe meter division (e.g. 4/4 groups into two half-measure halves; 6/8 groups into two dotted-quarter pulses of three eighths each)."
            },
            {
                "heading": "4.2 Slope Calculation & Melodic Contour",
                "text": "Functions: Beams calculate a graceful visual slant following the pitch direction of noteheads. Extreme melodic intervals apply Gould slant-clamping to prevent excessive angles, and flat passages render strictly horizontal beams."
            },
            {
                "heading": "4.3 Fractional Beams (Beamlets & Stubs)",
                "text": "Functions: Syncopated rhythms and mixed subdivisions (such as a dotted eighth followed by a 16th note) generate standard fractional beamlets (stubs) oriented toward the rhythmic pulse beat."
            },
            {
                "heading": "4.4 Stem Inversion ('X' Shortcut)",
                "text": "Functions: Pressing the 'X' key instantly flips the stem direction of selected notes (stems up vs. stems down). Inverting stems automatically recalculates beam anchor points and flag alignments."
            },
            {
                "heading": "4.5 Hardware-Accelerated Beaming & Smooth Edge Anti-Aliasing",
                "text": "Functions:\n"
                        "- Clockwise Vertex Winding: All beam quads (primary, secondary, and fractional beamlets) enforce strictly clockwise vertex ordering in Dear ImGui screen space (top-left -> top-right -> bottom-right -> bottom-left). This guarantees outward-facing anti-aliasing normals with silky smooth, non-jagged edges across both upward and downward stem directions.\n"
                        "- Outer Stem Coverage: Beam polygons extend by half stem thickness (1.25 * s) on outer stems to encompass outer stems completely without horizontal protrusion (per Gardner Read & Elaine Gould).\n"
                        "- Embedded Stem Terminations: Stem lines terminate slightly inside the beam thickness to ensure flat rectangular line caps remain invisible within the slanted beam polygon.\n"
                        "- Gould Quarter-Note Quintuplets (5:4): Full 4/4 bar quintuplets accurately calculate 0.8 QN step widths spanning exactly 4.0 QN total duration.\n"
                        "Performance: Minimizes C-API overhead and eliminates redundant outline strokes."
            }
        ]
    },
    {
        "chapter": 5,
        "title": "Dynamics Engine, Hairpins & Bow Swell Function",
        "sections": [
            {
                "heading": "5.1 Standard Dynamic Levels (ppp to fff)",
                "text": "Functions: The Dynamics Drawer features 10 one-click dynamic badges:\n"
                        "- ppp (Pianississimo) -> Velocity ~20, CC ~25\n"
                        "- pp (Pianissimo) -> Velocity ~35, CC ~40\n"
                        "- p (Piano) -> Velocity ~50, CC ~55\n"
                        "- mp (Mezzo-piano) -> Velocity ~65, CC ~68\n"
                        "- mf (Mezzo-forte) -> Velocity ~80, CC ~82\n"
                        "- f (Forte) -> Velocity ~95, CC ~98\n"
                        "- ff (Fortissimo) -> Velocity ~110, CC ~112\n"
                        "- fff (Fortississimo) -> Velocity ~125, CC ~127\n"
                        "- sfz (Sforzando) / fp (Forte-piano): Sudden accent followed by immediate decay.\n"
                        "DAW Effect: Inserts dynamic text markings on the score and scales note velocities and continuous controller points."
            },
            {
                "heading": "5.2 Multi-Target CC Automation",
                "text": "Functions: Dynamics can write continuous automation curves to:\n"
                        "- CC1 (Modulation Wheel) - Standard for orchestral dynamics in cinematic sample libraries.\n"
                        "- CC11 (Expression) - Secondary loudness / timbre controller.\n"
                        "- CC7 (Main Volume) - Master channel volume.\n"
                        "- Velocity Only - Traditional keyboard velocity scaling.\n"
                        "DAW Effect: Generates dense, sample-accurate MIDI CC curves in REAPER's MIDI take envelope."
            },
            {
                "heading": "5.3 Hairpins (Crescendo & Diminuendo)",
                "text": "Functions:\n"
                        "- Crescendo (<): Visual opening wedge representing gradual increase in loudness.\n"
                        "- Diminuendo (>): Visual closing wedge representing gradual decrease in loudness.\n"
                        "- Dual Drag Handles: Circular handles at the start and end of hairpins allow exact quarter-note positioning.\n"
                        "- Curvature Selection: Toggle between linear ramps and exponential curves for organic acoustic swelling.\n"
                        "- Decoupled Scaling Boundaries: Hairpin and dynamic text drag handles strictly collide and clamp against musical dynamic markers (p, pp, mp, mf, f, etc.), other hairpins, and dynamic text markings (cresc., dim.), but completely ignore note-level articulations (such as staccato dots, accents, tenutos). This allows hairpins to span freely across dense passages of staccato notes without getting restricted or shrunk down.\n"
                        "- Legacy Hairpin Playback Reconciliation: If a hairpin in an older project file was previously squeezed or collapsed due to staccato note collisions, running '⚡ Fix Playback' automatically detects collapsed hairpins (<= 0.75 QN), restores them to their natural phrase boundaries, and regenerates smooth continuous CC ramps.\n"
                        "DAW Effect: Inscribes smooth CC ramps between the bounding dynamic levels."
            },
            {
                "heading": "5.4 Bow Swell Function & Bow Position Slider",
                "text": "Functions:\n"
                        "- Bow Swell Mode: Simulates acoustic string and brass swelling where a single sustained note or phrase swells up to a climax and decays back down.\n"
                        "- Bow Position Slider (0.0 to 1.0, default 0.5): Configures the exact peak inflection point of the swell per MIDI item. Setting 0.5 places the peak in the exact center; setting 0.8 creates an expressive late swell; setting 0.2 creates an explosive early swell.\n"
                        "- Per-Item Tuning: Bow swell parameters can be customized individually per MIDI item.\n"
                        "DAW Effect: Calculates an asymmetric Bezier CC curve mapped directly into REAPER's CC lane."
            },
            {
                "heading": "5.5 Phrasing & Shaping Bypass",
                "text": "Function: Checkbox to temporarily disable CC automation playback without deleting visual dynamic markings on the score canvas."
            }
        ]
    },
    {
        "chapter": 6,
        "title": "Articulations & Reaticulate Integration",
        "sections": [
            {
                "heading": "6.1 Reaticulate Bank Auto-Discovery & Bank Picker Modal",
                "text": "Functions: REAPER-Notator automatically scans REAPER's Data and Scripts directories for factory and user Reaticulate sound bank definitions (Reaticulate-factory.reabank and Reaticulate.reabank). When a track is selected, Notator reads the track's P_EXT:reaticulate assignment, user bank override, or matches track names (e.g. 'Violin I', 'Cello', 'Horns') to corresponding library banks. Users can also explicitly assign or switch any track's sound bank at any time via the 'Select Bank...' button in the Articulations Drawer (BankPickerModal)."
            },
            {
                "heading": "6.2 Automatic Reaticulate.jsfx FX Slot 1 Setup, Primary Bank Replacement & Bank Sync (v2.0.2 - v2.0.7)",
                "text": "Functions & Zero-Configuration New Track Workflow:\n"
                        "- Automatic FX Verification & Insertion: When you create a brand-new track in REAPER (even one that only has a virtual instrument VSTi loaded or an empty FX chain) and select a bank in the Bank Picker—or apply any articulation from the Articulations Drawer / Sidebar—REAPER-Notator automatically checks the track's FX chain for 'JS:Reaticulate' (Reaticulate.jsfx). If missing, Notator automatically loads it onto the track via TrackFX_AddByName.\n"
                        "- Strict FX Slot 1 (Index 0) Placement Before Instrument VSTi: For Reaticulate to intercept Bank Select (CC0/CC32) and Program Change events and translate them into sampler keyswitches, Reaticulate.jsfx MUST sit in the very first FX slot (Slot 1 / index 0) prior to the virtual instrument (Kontakt, Sine, Opus, Play, VSL, etc.). If Reaticulate.jsfx is absent or positioned after an instrument plugin (slot > 0), REAPER-Notator automatically moves it to FX Slot 1 (index 0) via TrackFX_CopyToTrack(..., 0, true).\n"
                        "- Primary Bank Replacement Without Stacking (v2.0.4+): Adding or changing an articulation bank on a track cleanly replaces the top primary bank (appdata.banks[1]) and any conflicting Omni (src == 17) or duplicate entries in P_EXT:reaticulate before loading the new bank, and guards against Reaticulate's rfx.gc() overwriting P_EXT:reaticulate with stale uncommitted UI state—preventing duplicate stacked banks and program number conflict errors in Reaticulate.\n"
                        "- Native P_EXT:reaticulate Track Metadata Sync: Selecting a bank or applying an articulation automatically writes the structured JSON bank configuration into the track's P_EXT:reaticulate extension state (preserving existing secondary banks or generating a valid RFC-4122 UUID v4 when needed) and triggers Reaticulate's live RFX sync so both the Reaticulate GUI and JSFX immediately activate the bank.\n"
                        "- Wildcard 'Bank * *' MSB/LSB Resolution & Allocation: Many custom user .reabank files define banks using wildcard headers ('Bank * * LibraryName') rather than hardcoded MSB/LSB numbers. REAPER-Notator automatically parses project-level MSB/LSB assignments from REAPER's REATICULATE bank_msblsb ExtState, or allocates deterministic Reaticulate-compatible CRC64 MSB/LSB numbers (CC0/CC32) and persists them to the project so Bank Select events are never skipped."
            },
            {
                "heading": "6.3 Visual Playing Technique Glyphs & Applying Articulations (Selected Notes, Edit Cursor & Empty Items)",
                "text": "Functions:\n"
                        "- Instant Playing Technique Palette: Provides an instant-access drawer and sidebar buttons for standard SMuFL glyphs and text playing techniques:\n"
                        "  * Staccato (dot), Staccatissimo (wedge), Accent (>), Marcato (^), Tenuto (-)\n"
                        "  * Legato, Long / Sustain, Pizzicato (pizz.), Arco, Con Sordino, Sul Ponticello, Sul Tasto, Col Legno, Tremolo, Trills, Harmonics / Flageolet (o)\n"
                        "- Standard Engraving Placement: Automatically positions articulation marks above noteheads for stems-down notes, or below noteheads for stems-up notes (with consistent beam-side alignment and staff-line avoidance).\n"
                        "- Applying to Selected Notes: When one or more notes are selected on the score canvas, clicking an articulation attaches the persistent REAPER Type 15 notation tag (`NOTE <pitch> <chan> a <art_name>`), writes the resolved MIDI CC0 (MSB), CC32 (LSB), and Program Change at the note onset, and schedules Auto-Chase return events.\n"
                        "- Applying at Edit Cursor & Empty MIDI Items (v2.0.4+): If no notes are currently selected, clicking an articulation in the Articulations Drawer automatically finds all notes on the active track/take at the current REAPER Edit Cursor position (cursor_qn), attaches the visual notation tag (`NOTE ... a ...`) directly to those notes, and inserts the corresponding CC0/CC32 Bank Select and Program Change events. If no note exists at the Edit Cursor (or the selected MIDI item contains 0 notes), a standalone Program Change + Bank Select switch is inserted directly at the Edit Cursor, preserved across Auto-Chase passes, and visibly rendered above the staff on the ScoreCanvas.\n"
                        "DAW Effect: Writes both persistent Type 15 score notation events and sample-accurate CC0/CC32 Bank Select + Program Change events into the REAPER MIDI take, immediately marking the item dirty and synchronizing open MIDI editors."
            },
            {
                "heading": "6.4 Momentary Articulations & Auto-Chase Return Engine",
                "text": "Functions & DAW Behavior:\n"
                        "- Momentary vs. Persistent Articulations: Playing techniques such as Staccato, Staccatissimo, and Accent are momentary by nature. Unlike persistent articulations (such as Arco, Tremolo, or Con Sordino) which remain active indefinitely until changed, momentary articulations only apply to their specific notes. After the passage ends, the instrument must automatically revert to its default playing patch (typically Long / Sustain).\n"
                        "- Automatic Chase Retrigger: When a momentary articulation is placed on notes, Notator automatically scans the passage, writes the corresponding Bank Select (CC0/CC32) and Program Change events at the note start positions, and places a dedicated Retrigger Chase event (`NOTATOR_CHASE` + base patch PC) at the exact end of the momentary passage (`last_momentary_end_ppq + 10`). This guarantees that subsequent unarticulated notes immediately trigger normal sustain without requiring manual keyswitch resets.\n"
                        "- Synchronized Note Deletion: If notes are deleted within or at the end of an articulated passage (for instance, deleting bars 6-10 of a 10-bar staccato phrase), Notator's deletion engine dynamically pulls the Chase Retrigger event back to the end of the remaining momentary notes (the end of bar 5) and removes all orphaned Program Change and chase events in the deleted bars. The remaining notes continue triggering staccato smoothly, while subsequent measures cleanly return to standard playback.\n"
                        "- Selective Articulation Removal: Clicking 'Remove Articulation' on selected notes strips the visual glyphs, Type 15 notation tags, and Program Change messages exclusively from those selected notes, preserving unaffected measures on the track intact."
            },
            {
                "heading": "6.5 Playback Troubleshooting & The 'Fix Playback' Engine (Selective vs. Global)",
                "text": "Functions, Tutorial Video & Playback Reconciliation Engine:\n"
                        "- Video Tutorial: For an in-depth video walkthrough of the Fix Playback, Ties, and Slurs features, watch the official tutorial:\n"
                        "    * 'Reaper-Notator - Infos about Fix Playback , Ties and Slurs function': https://youtu.be/ahpEfmgGb3M\n"
                        "- Dual Playback Fix Engine (Selective vs. Global):\n"
                        "    * 'Fix Playback (Selective)': Scans and reconciles STRICTLY the single selected MIDI item. The target item is resolved with prioritized accuracy: (1) item containing currently selected notes, (2) item box clicked in Notator canvas, (3) media item selected in REAPER's timeline, or (4) item under the edit cursor on the focused track. It repairs articulations, cleans foreign keyswitches, recalculates auto-chase return events, heals legacy hairpins, and auto-heals micro-overlaps strictly within the boundaries of that single item, guaranteeing that no other items on the track or elsewhere in the project are touched.\n"
                        "    * 'Fix Playback (Global)': Scans and reconciles ALL MIDI items across all tracks in the entire REAPER project. It iterates through every project track, reconciles note articulations with each track's respective Reaticulate bank, clears foreign or orphaned Program Changes, recalculates all auto-chase return points, and heals legacy dynamic hairpins project-wide. Ideal for refreshing entire multi-track arrangements or duplicated orchestral cues in one click.\n"
                        "- The Problem (Cross-Track Duplication Desync): In REAPER's arrange view, composers frequently duplicate or copy MIDI items across tracks (e.g. duplicating a violin phrase down to celli or double basses). When an item is copied in REAPER, REAPER duplicates the underlying MIDI events verbatim. However, different sample libraries or instrument sections utilize different Reaticulate sound banks (for example, a Violin bank might assign PC 40 to Short/Staccato, while a Celli or Double Bass bank might use PC 49 for Staccato Dig). Because the duplicated item retains the old track's Program Changes and old auto-chase markers, playback on the new track breaks, produces silent or mismatched samples, or becomes stuck in an unwanted articulation.\n"
                        "- The Solution ('Fix Playback' Engine): To resolve this without manual MIDI editing, REAPER-Notator provides automated playback reconciliation via the 'Fix Playback (Selective)' and 'Fix Playback (Global)' buttons in the Articulations drawer.\n"
                        "- Intelligent Re-Mapping: Fix Playback parses the persistent score notation markers (`NOTE <pitch> <chan> a <art_id>`), inspects the active track's Reaticulate bank, cleans out outdated or mismatched Program Changes from previous tracks, inserts the correct Bank Select and Program Change numbers for the current track's sound library, and re-calculates all auto-chase return events.\n"
                        "- Handling Unsupported Articulations (e.g. Library Lacks Staccato): If the destination track's instrument or Reaticulate bank does not provide the requested articulation (for example, duplicating a violin staccato passage onto a flute, piano, synth, or library that lacks dedicated short patches), Fix Playback completely purges all foreign Program Changes (such as 121-0-42) and Bank Selects (CC0 / CC32) across the take, removes unsupported notation tags, clears obsolete chase events, and ensures the track's default base patch (Long / Sustain) is engaged once at the passage start so the notes play cleanly without stuck keyswitches.\n"
                        "- Same-Pitch Legato Overlap Protection & Micro-Overlap Auto-Healing:\n"
                        "    * The Mechanism: Sampler legato libraries require a small overlap (~2 PPQ ticks) between notes of different pitches to trigger true acoustic legato interval transitions. In MIDI 1.0, two notes of the exact same pitch cannot overlap on the same channel without voice cancellation. If a slurred note was transposed to the same pitch as the preceding note, REAPER's native MIDI sort flagged the 2-tick overlap as invalid and deleted the second note.\n"
                        "    * Pre-Clamping on Note Entry & Transposition: Notator automatically clamps any preceding note tail bleeding into a new or transposed note's start position on the same pitch before MIDI_InsertNote and before MIDI_Sort.\n"
                        "    * Automated Micro-Overlap Healing: Both Selective and Global Fix Playback scan takes and automatically trim micro-overlaps (<= 15 ticks on identical pitches, and <= 5 ticks on different pitches without an active slur), repairing corruptions from older projects.\n"
                        "- Step-by-Step Workaround for Duplicated Items:\n"
                        "    1. Duplicate or paste the MIDI item onto a new track in REAPER's arrange view.\n"
                        "    2. Select the duplicated MIDI item or notes in REAPER-Notator.\n"
                        "    3. Open the Articulations drawer on the right sidebar.\n"
                        "    4. Left-click 'Fix Playback (Selective)' (or 'Fix Playback (Global)' for entire project).\n"
                        "    Playback immediately re-synchronizes to the destination track's virtual instrument bank with pristine staccato and sustain transitions.\n"
                        "- Dynamic Object Healing: Fix Playback also scans for legacy hairpins or dynamic text markings that were previously compressed or collapsed (<= 0.75 QN) by articulation collisions. It restores their natural musical span, re-resolves dynamic continuity across the track, and regenerates uninterrupted CC curves.\n"
                        "- Idempotency & Safe Multi-Click: The Fix Playback command is fully idempotent. If playback is already synchronized, repeating the click will never inadvertently erase or corrupt existing articulations.\n"
                        "- Fix of Last Resort (Emergency Articulation Reset):\n"
                        "    * Right-Click Access: Right-clicking 'Fix Playback (Selective)' (or clicking again when already in sync) opens the dedicated 'Fix Playback: Fix of Last Resort' confirmation modal window, centered over the active score display.\n"
                        "    * Target Confirmation: The modal clearly displays the target item and track name and confirms that note articulations currently match the active instrument sound bank.\n"
                        "    * Emergency Reset Action: If playback remains stuck, silent, or corrupted by external MIDI CC messages, clicking the red button '[ Purge All Articulations (Last Resort) ]' completely strips all articulation glyphs, Type 15 notation tags (`NOTE <pitch> <chan> a <art_id>`), Bank Selects (CC0 / CC32), keyswitch Program Changes, and auto-chase return events (`NOTATOR_CHASE`). It then re-engages the default base patch (Long / Sustain) at the item start, resetting the item to clean default sustain playback.\n"
                        "    * Safe Cancellation: Clicking '[ Cancel (Keep Articulations) ]' or pressing Escape immediately dismisses the modal without altering any notes, articulations, or MIDI events."
            },
            {
                "heading": "6.6 Slurs (Legato Phrase Marks) & Ties (Held Notes)",
                "text": "Functions, Workflow Architecture & DAW Engine:\n"
                        "- Video Tutorial: Watch the official video guide for practical examples of Ties and Slurs:\n"
                        "    * 'Reaper-Notator - Infos about Fix Playback , Ties and Slurs function': https://youtu.be/ahpEfmgGb3M\n"
                        "```\n"
                        "+-------------------------------------------------------------+\n"
                        "|                     SELECTION WORKFLOW                      |\n"
                        "|  - 2+ Notes Selected: Melodic phrase N1 .. Nk (all notes)   |\n"
                        "|  - 1 Note Selected: N1 -> Auto-connects next note (N2)      |\n"
                        "+------------------------------+------------------------------+\n"
                        "                               |                               \n"
                        "               +---------------+---------------+               \n"
                        "               |                               |               \n"
                        "               v                               v               \n"
                        "+-----------------------------+ +-----------------------------+\n"
                        "|          SLUR (S)           | |           TIE (T)           |\n"
                        "|      Different Pitches      | |       Identical Pitch       |\n"
                        "|      (Melodic Phrasing)     | |     (Duration Addition)     |\n"
                        "+-----------------------------+ +-----------------------------+\n"
                        "               |                               |               \n"
                        "               v                               v               \n"
                        "+-----------------------------+ +-----------------------------+\n"
                        "|    PLAYBACK & AUTOMATION    | |      SCORE & ENGRAVING      |\n"
                        "| - Pre-Slur Articulation:    | | - Both original noteheads   |\n"
                        "|   Detects active patch      | |   remain visible on canvas  |\n"
                        "|   (e.g. Tremolo PC/Bank)    | |   (e.g. 2 Half Notes stay;  |\n"
                        "| - Intelligent Patch Match:  | |   NEVER merged to whole!)   |\n"
                        "|   * Has Legato -> Legato PC | | - Engraver tie curve        |\n"
                        "|   * No Legato  -> Long/     | |   (Cubic Bezier arch per    |\n"
                        "|     Sustain Fallback Patch  | |   Gould / Read stem rules)  |\n"
                        "| - Phrasing Overlap:         | +-----------------------------+\n"
                        "|   Seamless overlap between  |                |               \n"
                        "|   all steps (Ni -> Ni+1)    |                v               \n"
                        "| - Auto-Chase Return Engine: | +-----------------------------+\n"
                        "|   At phrase end (Nk),       | |       MIDI TAKE ENGINE      |\n"
                        "|   automatically returns to  | | - Note 1 sustained to end   |\n"
                        "|   pre-slur articulation     | |   of Note 2 for continuity  |\n"
                        "|   (Tremolo restored!)       | | - Note 2 deleted from take  |\n"
                        "| - Smooth Bezier phrase arch | |   (zero second-note strike) |\n"
                        "|   rendered on score canvas  | | - Virtual Note 2 on canvas  |\n"
                        "+-----------------------------+ +-----------------------------+\n"
                        "               |                               |               \n"
                        "               +---------------+---------------+               \n"
                        "                               |                               \n"
                        "                               v                               \n"
                        "+-------------------------------------------------------------+\n"
                        "|                RESIDUE-FREE REMOVAL & TOGGLE                |\n"
                        "|  - Direct Canvas Click: Click curve to select (gold highlight)|\n"
                        "|  - Key [Delete] / [Backspace] removes selected slur or tie  |\n"
                        "|  - Key S or T (Toggle Off) / 'Remove Slur/Tie'              |\n"
                        "|  - Slur: Legato/Long PC removed, Auto-Chase resynchronized  |\n"
                        "|  - Slur Cleanup: All micro-legato overlap remnants clamped  |\n"
                        "|  - Tie: Note 1 length restored, Note 2 re-inserted in take  |\n"
                        "|  - Type 15 tags purged; zero orphaned MIDI events left      |\n"
                        "+-------------------------------------------------------------+\n"
                        "```\n"
                        "- Musical Distinction (Slur vs. Tie):\n"
                        "    * Tie (Haltebogen): Exclusively connects notes of the IDENTICAL pitch. A tie performs mathematical duration addition (e.g. tying a half note to a quarter note produces a sounding duration of 3 beats). The tone sounds upon the initial attack and is held continuously; the second note is never struck again. Ties are standardly employed to cross barlines or metric half-measure divisions where single notes cannot legally be notated.\n"
                        "    * Slur (Bindebogen / Legato): Connects notes of DIFFERENT pitches. A slur signifies that all notes within the marked phrase must be performed legato (smoothly connected without re-articulation or rhythmic separation between pitches).\n"
                        "- Interactive Selection & Multi-Note Phrasing Workflow:\n"
                        "    * Sidebar Access: Located in the dedicated 'SLURS & TIES' section between Articulations and Transpose on the main sidebar, as well as in the Articulations drawer.\n"
                        "    * Direct Canvas Hit-Testing: Slurs and ties can be clicked directly on the score canvas. Clicking a curve highlights it in bright gold (#FFD700), and pressing the Delete or Backspace key immediately removes the slur or tie.\n"
                        "    * 2 Notes Selected: Pressing 'S' or clicking 'Slur [S]' immediately connects Note 1 to Note 2. Pressing 'T' or clicking 'Tie [T]' verifies pitch equality and ties them.\n"
                        "    * Multi-Note Selection (3+ Notes): Pressing 'S' or clicking 'Slur [S]' creates an expressive phrase slur spanning from N1 to Nk, incorporating all intermediate notes on that track and channel.\n"
                        "    * 1 Note Selected: Pressing 'S' or clicking 'Slur [S]' automatically identifies the next chronological note on that track and creates the slur. Pressing 'T' or clicking 'Tie [T]' searches for the next chronological note sharing the identical pitch and ties them.\n"
                        "    * Pitch Protection Guard: If 'Tie [T]' is clicked with notes of different pitches, Notator prevents an invalid tie and displays an advisory notification: 'Tie requires notes of the same pitch! Use Slur [S] for melodic phrases.'\n"
                        "- Haltebogen / Tie Engine & Dual Reality Architecture:\n"
                        "    * Notehead Preservation (No Collapsing): Both original noteheads and stems (e.g. two separate half notes) remain permanently visible and correctly positioned on the score canvas per Elaine Gould and Gardner Read engraving standards. They are NEVER collapsed or merged into a single whole note or altered note value.\n"
                        "    * Score Engraver Tie Arch: A smooth cubic Bezier tie curve (Engraver.draw_tie) connects the noteheads, positioned per engraving standards opposite stems (below noteheads for stems-up notes, above noteheads for stems-down notes).\n"
                        "    * Dual Reality MIDI Architecture: In REAPER's underlying MIDI take, Note 1 is extended through the end of Note 2 for uninterrupted sounding sustain, and Note 2 is deleted from the take via MIDI_DeleteNote to completely eliminate secondary audio re-strikes. On the score canvas, Note 2 is losslessly synthesized from Type 15 notation tags (NOTATOR_TIE / NOTATOR_TIE_SLAVE), ensuring perfect visual score fidelity across measures and barlines.\n"
                        "    * REAPER Editor Synchronization: Every tie creation or deletion instantly triggers reaper.MarkTrackItemsDirty and reaper.MIDIEditor_OnCommand(40435), ensuring open REAPER Piano Roll editors synchronize immediately without manual window refresh.\n"
                        "- Melodic Slur Phrasing, Same-Pitch Protection & Articulation Return Engine:\n"
                        "    * Pre-Slur Articulation Memory: Before applying a slur, Notator scans active take events to record the current playing technique (e.g. Tremolo PC, MSB, LSB).\n"
                        "    * Intelligent Patch Match with 'Long' / Sustain Fallback: When a slur starts, Notator queries the instrument's Reaticulate sound bank for a dedicated legato or slur patch. If the instrument library lacks an explicit legato articulation, Notator automatically falls back to long / sustain. This guarantees that the instrument cleanly transitions out of Tremolo (or other previous techniques) instead of remaining stuck in Tremolo.\n"
                        "    * Same-Pitch Overlap Protection: To trigger true acoustic legato intervals in VST libraries, slurring notes of different pitches creates a 2-PPQ overlap. However, if consecutive notes share the exact same pitch, Notator strictly prohibits overlap (capping at next_sppq - 1), preventing REAPER from destructively merging identical pitch notes.\n"
                        "    * Gunshot Bug Protection: Re-engineered auto-chase routines enforce strict range checks (0 <= pc <= 127). If an item has no previous articulation (pre_slur_pc = -1), Notator strictly avoids sending negative program change bytes, preventing the unintended playback of General MIDI Patch 127 ('Gunshot').\n"
                        "    * Dynamic Auto-Chase Return Engine: At the exact conclusion of the slur phrase (Nk), the auto-chase engine immediately sends a return Bank Select and Program Change restoring the pre-slur articulation (e.g. automatically resuming Tremolo without composer intervention).\n"
                        "- Residue-Free Removal & Toggle:\n"
                        "    * Toggling 'Slur [S]' or 'Tie [T]' on an already slurred/tied note (or hitting Delete on a selected curve) removes the curve, restores Note 1's original duration, re-inserts Note 2 into the MIDI take, deletes Legato/Long Program Changes, and cleans all Auto-Chase return events with zero orphaned MIDI data.\n"
                        "    * Automatic Legato Overlap Trimming: When a slur is deleted, Notator automatically scans all phrase notes and clamps any residual micro-legato overlap extensions (<= 10 ticks) back to note boundary, preventing note erasing when subsequently transposing adjacent notes to identical pitch."
            }
        ]
    },
    {
        "chapter": 7,
        "title": "Holding & Sustain Pedal Lane (CC64)",
        "sections": [
            {
                "heading": "7.1 Dedicated Pedal Lane",
                "text": "Functions: Renders continuous piano sustain pedal markings positioned below the bass staff with automatic collision clearance from low notes and dynamic hairpins."
            },
            {
                "heading": "7.2 Three Historical Engraving Styles",
                "text": "Functions:\n"
                        "- Classic: Ped. symbol at start, dashed horizontal line, and asterisk (*) at release.\n"
                        "- Bracket: Modern square brackets (|---|) with vertical hooks.\n"
                        "- Notch / Mixed: Combines Ped. marking with inverted 'V' notches for continuous pedal retakes."
            },
            {
                "heading": "7.3 Dual Handles & Pause / Break Retakes",
                "text": "Functions:\n"
                        "- Start & End Handles: Drag circular handles to adjust pedal engage and release times.\n"
                        "- Pause / Retake Points: Right-click on the pedal line to insert pedal breaks (quick release and re-engage) without creating multiple separate items.\n"
                        "DAW Effect: Writes CC64 value 127 at engage, momentary 0 at retakes, and 0 at final release."
            }
        ]
    },
    {
        "chapter": 8,
        "title": "Tempo Maps & Metric Transitions",
        "sections": [
            {
                "heading": "8.1 Absolute Tempo Markers",
                "text": "Functions: Insert tempo markers with custom BPM values (e.g. Quarter = 120, Dotted Quarter = 72) and descriptive Italian tempo text (Adagio, Andante, Allegro, Presto).\n"
                        "DAW Effect: Inserts a master tempo marker directly into REAPER's timeline tempo envelope."
            },
            {
                "heading": "8.2 Gradual Transitions (Accelerando / Ritardando)",
                "text": "Functions: Renders dashed tempo transition lines spanning multiple measures (e.g. 'poco a poco accel. ------').\n"
                        "DAW Effect: Generates a continuous gradual tempo ramp in REAPER, smoothly accelerating or decelerating project playback speed."
            },
            {
                "heading": "8.3 Direct Double-Click BPM Editing & Glyphs",
                "text": "Functions:\n"
                        "- Double-Click Inline Editing: Double-clicking any tempo marker opens an instantaneous popup editor with automatic keyboard focus on the numeric BPM input.\n"
                        "- Standard Unicode Note Symbol: Renders the classical quarter-note symbol (♩, U+2669) in non-bold regular weight according to professional music engraving standards.\n"
                        "DAW Effect: Updates REAPER tempo markers in real time with immediate timeline synchronization."
            }
        ]
    },
    {
        "chapter": 9,
        "title": "Octave Shift Lines (8va, 8vb, 15ma, 15mb)",
        "sections": [
            {
                "heading": "9.1 Visual Score Simplification",
                "text": "Functions: For extreme high or low passages that would otherwise require excessive ledger lines, octave shift lines simplify score reading:\n"
                        "- 8va (Ottava Alta): Notes sound 1 octave higher than written.\n"
                        "- 8vb (Ottava Bassa): Notes sound 1 octave lower than written.\n"
                        "- 15ma (Quindicesima Alta): Notes sound 2 octaves higher.\n"
                        "- 15mb (Quindicesima Bassa): Notes sound 2 octaves lower."
            },
            {
                "heading": "9.2 Visual vs. Sounding Pitch",
                "text": "DAW Effect: Notes remain in their natural visual position on the staff for effortless reading, while underlying MIDI note pitches trigger the intended high or low acoustic octaves."
            }
        ]
    },
    {
        "chapter": 10,
        "title": "Orchestral Pattern Browser & 1-Click Library",
        "sections": [
            {
                "heading": "10.1 Curated 1,500 Pattern Factory Library",
                "text": "Functions: Slide-out pattern browser organized into 10 orchestral categories (1,500 factory patterns total):\n"
                        "- 1. Strings Staccato (150x driving cinema pulses, ostinatos)\n"
                        "- 2. Strings Pizzicato (150x delicate plucks, agile grooves)\n"
                        "- 3. Brass Blockbuster (150x epic horn fanfares, low brass power)\n"
                        "- 4. Cinematic Melodies (150x soaring lyrical themes)\n"
                        "- 5. Counter Melodies (150x rich orchestral counterpoint)\n"
                        "- 6. Woodwinds Textures (150x runs, fluttering textures)\n"
                        "- 7. Cinematic Piano (150x flowing arpeggios, grand staff ballads)\n"
                        "- 8. Ancient Greek & Roman Harp (150x modal hymns, Delphic paeans, Sapphic strophes, Dorian/Phrygian/Lydian processions)\n"
                        "- 9. Orchestral & Cinematic Percussion (150x Timpani, Taiko, Gran Cassa & Piatti, Snare Drum, Cinematic Toms, Anvil & Metal, Frame Drums, Mallets)\n"
                        "- 10. Low Strings - Celli & Double Bass Tension (150x pure rhythm, pedal-point motors, half-step thriller ostinatos, tritone dissonance, odd-meter chases, Divisi-ready Celli+Bass grooves)\n"
                        "- 11. Custom User Patterns (user-captured motifs and items)"
            },
            {
                "heading": "10.2 One-Click Insertion, Drag & Drop & Audio Audition",
                "text": "Functions:\n"
                        "- Drag & Drop: Drag any pattern tile directly onto the score canvas with golden ghost-preview.\n"
                        "- Full-Length Multi-Bar Audio Audition (v2.12 - v2.13): Audition motifs in real time across their complete multi-bar duration through any instrument track. Choose 'Auto (Selected / Focused Track)' or pick any specific project instrument from the Pattern Browser dropdown without altering REAPER's track selection.\n"
                        "- Capture Selection: Select any REAPER MIDI item and click 'Capture REAPER Item' to store it permanently."
            },
            {
                "heading": "10.3 In-App 1-Click Factory Library Downloader",
                "text": "Functions: Integrated one-click 'Download Factory Library' button built into the browser toolbar and empty-state banner.\n"
                        "- 1-Click Install: Downloads and unpacks the entire 1,500 pattern library (~1 MB compressed) in one second without leaving REAPER.\n"
                        "- Offline Archive Support: Automatically unpacks local patterns.zip on first launch if present."
            }
        ]
    },
    {
        "chapter": 11,
        "title": "Rehearsal Marks, Fermatas & Score Tools",
        "sections": [
            {
                "heading": "11.1 Dynamic & Custom Rehearsal Marks, Inline Renaming & Live Shortcut (Ctrl+M)",
                "text": "Functions: Professional structural navigation, custom section markers, and rehearsal tagging:\n"
                        "- Dedicated Rehearsal Lane: Positioned cleanly between the Chord Track lane and Bar Numbers, providing unobstructed structural visibility across all systems.\n"
                        "- Interactive Mouse Drag & Drop: Click and drag any rehearsal mark directly along the top lane to move it to any measure or grid beat. Custom Markers and Navigation Marks (e.g. 'D.C.', 'D.C. al Fine') permanently retain their custom label across moves with dynamic badge hitboxes.\n"
                        "- Auto-Sequencing: Standard marks automatically sequence as [A], [B], [C]... or [1], [2], [3]... Moving or inserting standard marks chronologically re-indexes all subsequent standard marks across the score.\n"
                        "- Inline Double-Click Renaming & Auto-Sequence Exclusion (v2.0+): Double-clicking any Rehearsal Mark on the score canvas (or choosing 'Rename Mark' in the right-click context menu / Tools Drawer) opens an inline rename box. Renaming any mark locks it as a Custom Marker and automatically excludes it from the A, B, C... / 1, 2, 3... counting sequence.\n"
                        "- Live & Stopped Custom Marker Shortcut ('Ctrl+M', v2.0+): Pressing Ctrl+M (configurable in Settings -> Shortcuts) places sequential default custom markers ('Marker 1', 'Marker 2', 'Marker 3'...) at the exact Playhead position during live Playback or Recording (snapped to the active Notation Grid), or at the Edit Cursor when stopped.\n"
                        "- Edit-Cursor Placement: The Tools Drawer dynamically detects the active REAPER edit cursor position, displaying explicit actions like 'Add Letter Mark at Bar X', 'Add Number Mark at Bar X', and 'Add Custom Marker at Bar X'.\n"
                        "- Classical Navigation Symbols: Immediate one-click placement of Da Capo (D.C.), D.C. al Fine, Dal Segno (D.S.), D.S. al Coda, Segno, Coda, and Fine marks.\n"
                        "- Inverted Engraving Typography: Styled according to classical engraving rules with a crisp paper background, 2px dark border, and high-contrast dark typography.\n"
                        "- Settings & View Options: Configurable vertical Y-offset slider in Settings and a show/hide toggle in the View dropdown."
            },
            {
                "heading": "11.2 Score-Wide Vertical Fermatas",
                "text": "Functions: Classical pause and hold articulation across all staves:\n"
                        "- Four Engraving Types: Standard fermata, Short fermata (triangle/fermata corta), Long fermata (square/fermata lunga), and Very Long fermata.\n"
                        "- Full-Score Clickability: Fermatas can be clicked, selected, and edited on any staff across the entire vertical score system, not just the top staff.\n"
                        "- Tempomap Playback Coupling: Non-destructive tempo slowdown dip (1.25x to 3.0x multiplier) with automatic restoration at the release point.\n"
                        "- Keyboard Delete Support: Select any fermata or rehearsal mark and press Delete or Backspace to instantly remove it."
            },
            {
                "heading": "11.3 Score Tools Drawer & Performance Transformations",
                "text": "Functions: Fast editing actions consolidated in the right-hand Tools drawer:\n"
                        "- Make Notes Legato: Extends note durations to adjacent note downbeats for seamless cantabile phrasing.\n"
                        "- Auto Voice & Auto Voice on Selection: Polyphonic splitting of selected chords into upper Voice 1 (stems up) and lower Voice 2 (stems down).\n"
                        "- Filter Irregular Notes: Dedicated cleaning and reorganization tool for humanized and live-recorded MIDI tracks. Accurately identifies notes whose onset times deviate from standard metric divisions (whole to 32nd notes, with optional triplet support) outside a configurable tick tolerance. Includes real-time yellow canvas highlighting, regular-note dimming/ghosting, and dual actions: non-destructive note selection or reassignment to a target voice (e.g. Voice 16).\n"
                        "- Divisio Vocum (Voice Distribution): Distributes multi-voice chords from a single track vertically across the visible tracks displayed below in the score viewport (e.g. from Violin 1 down through Contrabass). Features an interactive context modal with live routing preview, target voice count (2-16), chord detection tolerance (5-100 ms), and bass voice gap-filling.\n"
                        "- Divisi (Split Voices to Duplicated Tracks, v2.15): Splits already assigned polyphonic Voices (Voice 2..16 / MIDI Channels 2..16, e.g. after running Auto-Voice) onto newly duplicated REAPER tracks directly below the source track—cloning the entire FX chain (Kontakt/VSTi instances, Reaticulate banks, sends/routing, folder hierarchy, clefs, and MIDI items) so each voice plays on its own dedicated instrument copy.\n"
                        "- Arpeggio Strums: Realistic harp, guitar, and piano roll simulation. In accordance with classical music engraving standards, noteheads remain strictly vertically aligned on the chord downbeat under a single unified stem, while a wavy arpeggio line is engraved to the left with automatic clearance for accidentals. Playback micro-strumming adaptively scales with note length (e.g. 8-16 ticks for 16th notes up to 30 ticks for sustained chords) to prevent beat spillover, and 'Snap to Grid / Remove Arpeggio' instantly restores notes to the chord downbeat.\n"
                        "- Quantize Tools: Integrated triplet, swing, and 1/4 through 1/64 grid snapping directly inside the Tools drawer."
            },
            {
                "heading": "11.4 Divisio Vocum (Orchestral Voice Distribution / Explode Chords)",
                "text": "Overview & Musical Concept:\n"
                        "Divisio Vocum (classical Latin for 'voice division') is an intelligent orchestral arranging service implemented in modules/services/divisio_vocum_service.lua with UI modal modules/ui/divisio_vocum_modal.lua. It takes multi-voice chords played or sketched on a single track (such as an ensemble piano reduction, string sketch, or brass fanfare on Violin 1) and distributes the individual polyphonic voices vertically across the active tracks displayed in the score viewport below (for example: distributing a 5-voice chord from Track 1 across Violin 1, Violin 2, Viola, Cello, and Contrabass).\n\n"
                        "How to Access the Tool:\n"
                        "- Method 1 (Score Tools Drawer): Open the right-hand Tools drawer and click 'Divisio Vocum...'.\n"
                        "- Method 2 (Canvas Context Menu): Right-click on any selected notehead or empty measure on the score canvas and select 'Divisio Vocum...' from the context menu.\n\n"
                        "Interactive Dialog Controls & Features:\n"
                        "- Source Track Detection: The service automatically identifies the source track based on the current note selection, focused track, or the uppermost visible viewport track.\n"
                        "- Target Tracks / Voices (2 to 16): An interactive slider to configure how many target tracks and polyphonic voices will receive notes. Defaults to 5 tracks.\n"
                        "- 'Match Viewport' One-Click Button: Automatically queries the number of active tracks currently visible in your score canvas and synchronizes the target voice count to match them in a single click.\n"
                        "- Live Routing Breakdown (Interactive Preview Table): Shows an immediate breakdown of voice routing before applying changes:\n"
                        "  * Voice 1 (Top / Highest Pitch): Retained directly on the source track (e.g. Violin 1 / Soprano lead).\n"
                        "  * Voice 2 (Upper Middle): Routed to Track 2 below.\n"
                        "  * Voice 3 (Middle): Routed to Track 3 below.\n"
                        "  * Voice 4 (Lower Middle): Routed to Track 4 below.\n"
                        "  * Voice 5..N (Bass / Lowest Pitch): Routed to Track 5 and subsequent lower tracks (e.g. Celli and Contrabasses).\n"
                        "- Chord Detection Tolerance (5 ms to 100 ms, default 25 ms): Configures the time window used to group notes into vertical chords. Notes played on MIDI keyboards with slight live humanization are clustered accurately into cohesive vertical chords.\n"
                        "- Pad / Double Bass Voice in Lower Tracks (Gap-Fill): When active, chords with fewer notes than target tracks (e.g. a 3-note triad distributed over 5 orchestral tracks) automatically double the lowest root/bass note into the remaining bottom tracks (e.g. Celli and Contrabass both receive the bass note). When unchecked, lower tracks remain empty for sparse chords.\n"
                        "- Scope Selection: Choose between 'Selected Chords' (restricting the operation strictly to currently selected notes) and 'All Chords on Track / Item'.\n\n"
                        "DAW Execution, Articulation & Sound Bank Bridging:\n"
                        "- Clean Voice Extraction: Distributed secondary voices (Voice 2..N) are seamlessly moved to the destination tracks at their exact Quarter-Note positions and durations, while the source track cleanly retains only Voice 1 without duplicate note clutter.\n"
                        "- Intelligent Articulation & Reaticulate Bridging: Preserves SMuFL note-level articulations (Staccato, Accent, Tenuto, Marcato, etc.) and queries each destination track's Reaticulate sound bank to output the corresponding Bank Select (CC0/CC32) and Program Change events tailored to each instrument.\n"
                        "- Transactional Undo Safety: The entire multi-track distribution operation is enclosed in a single REAPER undo transaction (Undo_BeginBlock2), ensuring immediate, complete rollback with Ctrl+Z."
            },
            {
                "heading": "11.5 Divisi (Split Polyphonic Voices onto Duplicated Instrument Tracks, v2.15)",
                "text": "Overview & Musical Concept:\n"
                        "While Divisio Vocum distributes vertical chord pitches across existing different instrument tracks in the score, Divisi (implemented in modules/services/divisi_service.lua and modules/ui/divisi_modal.lua) solves true orchestral section splitting (e.g. Violins I divisi a 2 / a 3). After splitting polyphonic passages into voices via 'Auto-Voice on Selection' or 'Auto-Voice Track Overlaps' (for example: 50 notes in Voice 1, 30 notes in Voice 2, and 5 notes in Voice 3 on a single staff), Divisi keeps Voice 1 on the original source track and duplicates the entire REAPER track once for each additional voice.\n\n"
                        "Full Track & Instrument Duplication:\n"
                        "- Complete FX & Sampler Cloning: Uses REAPER's native track duplication (Action 40062) so every Kontakt / VSTi instance, loaded sample patch, Reaticulate JSFX, Reaticulate bank assignment (P_EXT:reaticulate), track color, audio/MIDI send routing, and Notator clef setting is identically cloned onto '<Track Name> (Divisi 2)', '<Track Name> (Divisi 3)', etc.\n"
                        "- Folder Structure Preservation: If the source track is the closing track of a REAPER folder (I_FOLDERDEPTH < 0), Divisi automatically keeps all newly created Divisi tracks inside the same folder and transfers the folder-closing depth to the last Divisi track.\n"
                        "- Exact Per-Voice MIDI Filtering & Channel 1 Normalization: On each duplicated track, only the notes (along with matching Type 15 NOTE articulations, slurs, and CCs) of that specific voice are kept, and by default normalized to Voice 1 (MIDI Channel 1) so monophonic legato/kontakt patches respond immediately without channel mismatches.\n\n"
                        "How to Access Divisi:\n"
                        "- 1-Click Context Menu: Right-click selected notes or a staff and click 'Divisi (Split Voices to Duplicated Tracks)' for immediate execution.\n"
                        "- Interactive Preview Modal: Click 'Divisi (Options / Preview)...' in the right-click menu or 'Divisi (Split Voices to Tracks)...' in the Tools Drawer to inspect note counts and pitch ranges per voice, toggle individual voices, switch scope between 'Selected Notes' and 'Entire Staff / Track', or run Auto-Voice directly from the dialog."
            },
            {
                "heading": "11.6 Filter Irregular Notes (Humanized & Live-Recorded MIDI Cleaner)",
                "text": "Musical Concept & Background:\n"
                        "Live-recorded MIDI keyboard performances and humanized takes inherently feature subtle micro-timing variations. Filter Irregular Notes analyzes note onset positions relative to the musical meter, flags notes that deviate from standard metric subdivisions outside a user-defined tick tolerance, renders a live gold/yellow (#FFD700) preview on the score canvas, and allows you to either select them for manual inspection or reassign them cleanly into a secondary background voice (default Voice 16 / MIDI channel 15).\n\n"
                        "Interactive Dialog Controls & Features:\n"
                        "- Tolerance Slider (0 to 50 Ticks): Determines how many MIDI ticks of micro-timing deviation are permitted before a note is treated as irregular (with a sub-tick float epsilon < 0.05 ticks at 0 tolerance).\n"
                        "- Include Triplets Checkbox: Tests compound/triplet subdivisions (1/12, 1/24, 1/48) in addition to binary subdivisions (1/1 through 1/32).\n"
                        "- Target Voice Selector (Voice 1 through Voice 16): Chooses the destination voice when reassigning irregular notes (defaults to Voice 16).\n"
                        "- Processing Scope: Choose between Entire Project, Active Track, Selected Media Items, or Selected Notes Only.\n"
                        "- Live Canvas Yellow Preview & Regular Note Ghosting: Highlights matching irregular notes in vivid yellow on the score canvas in real time and optionally dims/ghosts regular notes.\n"
                        "- Dual Execution Actions: 'Select Notes' (non-destructively selects irregular notes for inspection) and 'Reassign to Voice' (moves irregular notes to the target voice within a single REAPER undo transaction)."
            },
            {
                "heading": "11.7 Floating Text Items & In-Place Editing",
                "text": "Functions: Pressing Ctrl+T inserts a floating score text item at the cursor. Double-click any text item to open an in-place editing field. Configure font size, standard/italic/bold styling, and staff attachment anchor points."
            },
            {
                "heading": "11.8 Melodic Pathfinder: Corpus-Trained Key-Note Inpainting & Counter-Melody Engine (v2.32 - v2.50-beta.3)",
                "text": "Overview & Musical Architecture:\n"
                        "Melodic Pathfinder (implemented in modules/services/melody_pathfinder_service.lua, modules/services/melody_style_corpus.lua, and modules/ui/melody_pathfinder_modal.lua) is an intelligent, corpus-trained melodic composition, key-note inpainting, and contrapuntal counter-melody generator built directly into REAPER-Notator. Trained via tools/train_melody_style_models.py on the 1,500-pattern orchestral library (>126,000 notes), it computes optimal musical pathways connecting user-placed landmark notes or generates complete phrases and counter-melodies harmonized against other tracks in your REAPER project.\n\n"
                        "How to Access Melodic Pathfinder:\n"
                        "- Method 1 (Canvas Context Menu): Select 2 or more landmark notes, 1 seed note, or right-click an empty measure on the ScoreCanvas and choose 'Melodic Pathfinder (Fill Between Key Notes)...'.\n"
                        "- Method 2 (Score Tools Drawer): Open the right-hand Tools Drawer and click 'Melodic Pathfinder (Fill Key Notes)...'.\n\n"
                        "The Three Input Workflows (Automatic Selection Detection):\n"
                        "- 1. Waypoint Inpainting Mode (2+ Key Notes Selected): Sketch two or more structural landmark notes in your score (for example, a starting note in Bar 1, a high climax note in Bar 3, and a cadence note in Bar 4) and select them. Melodic Pathfinder locks your landmark notes as immovable pillars (shown in gold) and computes the optimal musical bridge connecting each consecutive pair (W_1 -> W_2 -> ... -> W_k).\n"
                        "- 2. Single-Note Seed Mode (1 Note Selected): Select a single note to act as your starting anchor ('Seed Note') and choose a phrase span (2 Bars, 4 Bars, or 8 Bars). The engine generates a complete multi-bar melodic arch or counter-melody starting from that exact note.\n"
                        "- 3. Bar-Range / Reference-Aligned Mode (0 Notes Selected): With no notes selected, Melodic Pathfinder spans the active MIDI item or a 2/4/8-bar range at the Edit Cursor, derives starting, climax, and cadence anchor pitches inside your track's playable clef register (automatically harmonized with the Reference Track), and generates a complete phrase.\n\n"
                        "How the 5-Stage Mathematical & Musical Engine Works Under the Hood:\n"
                        "- Stage 1 - Corpus Rhythm Cell Generation & Contrapuntal Rhythm:\n"
                        "  * Queries MelodyStyleCorpus for empirical rhythm cells (sparse, medium, or dense) controlled by the Density (10%-100%) slider.\n"
                        "  * In Counter-Melody Mode ('Generate Counter-Melody'), the engine analyzes the Reference Track's rhythm in real time to synthesize complementary contrapuntal rhythm: when the Reference Track holds a long sustained note or rests, the Counter-Melody becomes rhythmically active (8th/16th motion); when the Reference Track plays fast runs, the Counter-Melody breathes with broader sustained notes (classical 1st/2nd species counterpoint).\n"
                        "  * Automatically inserts natural breathing rests at phrase midpoints and bar boundaries so wind, brass, and vocal lines sound phrasing-authentic.\n"
                        "- Stage 2 - Scale / Mode Construction & Strict Playable Instrument / Clef Register Bounding:\n"
                        "  * Builds candidate pitches in the chosen Scale / Mode (Auto, Major/Ionian, Natural Minor/Aeolian, Harmonic Minor, Dorian, Phrygian, Lydian, Mixolydian, Minor Pentatonic, or Chromatic) transposed to the active Key Signature root.\n"
                        "  * Automatically detects both the track's active Clef (Treble [57..81], Bass [36..62], Alto [48..72], Tenor [45..69], Grand Staff [48..81]) and 16 specific orchestral instrument playable registers from the track name (Contrabass [28..55], Cello [36..67], Viola [48..74], Violin [55..88], Tuba, Trombone, French Horn, Trumpet, Bassoon, Clarinet, Oboe, Flute, Piccolo, Timpani, Harp, Piano).\n"
                        "  * Interactive Octave Shift Buttons ('-8vb Low', 'Normal', '+8va High', 'Auto') in the modal header shift the target generation register by +/-12 semitones while clamping strictly to MIDI 0..127.\n"
                        "  * Octave-Folding: Any landmark or reference harmony note from another track is folded into the target track's playable clef register so a Bass/Cello track never receives high Violin ledger lines and vice versa.\n"
                        "- Stage 3 - 2nd-Order Viterbi Dynamic Programming Pathfinding:\n"
                        "  * Across all rhythmic slots t = 1..N between two waypoints, the engine executes a Viterbi dynamic programming trellis search over all candidate scale pitches (tracking both current pitch and previous interval for 2nd-order Markov memory).\n"
                        "  * Each transition step is scored by combining 7 musical reward/penalty functions:\n"
                        "    1. Empirical Markov Interval Log-Probabilities: Derived from the style's trained interval_weights table (-12 to +12 semitones) and scaled by the Leap Character (0%-100%) slider.\n"
                        "    2. Post-Leap Gap-Fill Law (Meyer's Law): After any melodic leap >= 4 semitones, the engine strongly rewards reversing direction by stepwise motion (gap_fill_strength 64%-77%) to resolve melodic tension naturally.\n"
                        "    3. Triadic Fanfare Bonus: Rewards consecutive chordal arpeggiations (3rds, 4ths, 5ths in the same direction) for heroic brass and symphonic styles (triad_fanfare_bonus).\n"
                        "    4. Ostinato Pivot-Note Return Bonus: Rewards returning to the anchor pitch p_{t-2} after neighbor-note excursions (pivot_return_bonus), creating hypnotic ostinato/suspense cells.\n"
                        "    5. Modal Color & Leading-Tone Rules: Boosts characteristic modal color intervals (such as Lydian #4, Dorian nat6, Phrygian b2) and optionally suppresses harsh semitone leading tones (avoid_semitone_lead) in pastoral and folk modes.\n"
                        "    6. Reference Track Harmonic Consonance & Contrary Motion: Evaluates vertical pitch-class intervals against simultaneous notes on the Reference Track ('Auto: All Other Project Tracks', any specific track, or 'None') weighted by the Harmonic Consonance Ratio (0%-100%) slider. At 80%-100%, strongly favors consonant 3rds, 6ths, 5ths, and chord tones; at 0%-25%, favors dark thriller dissonance (minor 2nds and tritones). In Counter-Melody Mode, specifically rewards imperfect consonances (3rds and 6ths) and contrary motion (moving up when the Reference Track moves down, and vice versa).\n"
                        "    7. Cadential Approach & Phrase Climax Arch: Guides the phrase along a natural sinusoidal climax arch and rewards authentic cadential approaches (-1, +1, -2 -> -1, -5 -> 0) into the destination landmark note.\n"
                        "- Stage 4 - Classical Melodic Transformations (Inversion, Retrograde, Retrograde-Inversion):\n"
                        "  * Choose from 4 contour transformations in the 'Melodic Inversion & Contour' dropdown:\n"
                        "    1. Normal (Original Contour)\n"
                        "    2. Inversion (Mirror Up <-> Down around Start): Mirrors every diatonic scale-degree delta around the starting note inside the active clef register.\n"
                        "    3. Retrograde (Reverse Time Order): Reverses the generated pitch sequence in time.\n"
                        "    4. Retrograde-Inversion (Reverse + Mirror): Combines temporal reversal with diatonic pitch inversion.\n"
                        "  * Direct In-Place Score Inversion ('Invert Sel.' Button): Immediately inverts any currently selected notes on the score canvas in-place around the first selected note within a single REAPER undo block.\n"
                        "- Stage 5 - Live Map Preview, Audition & Non-Destructive Score Application:\n"
                        "  * Live Melodic Map Preview: Real-time interactive vector graph displaying Gold nodes (Key Landmarks), Green curve (Generated Bridge / Counter-Melody), and Purple bars (Reference Track Harmony).\n"
                        "  * Seed Reroll & Live Audio Audition: Click 'New Variation (Seed #N)' to explore alternative melodic paths, or click 'Audition Melody' to hear the generated phrase played live through your track's virtual instrument on MIDI Channel 1.\n"
                        "  * Phrase Slur & Insertion Modes: Optionally check 'Add Phrase Slur automatically' to wrap the phrase in a smooth Bezier legato slur, and choose between 'Replace Between Key Notes' (replaces existing notes in the span) or 'Layer (Keep Existing)' (inserts as a polyphonic layer).\n\n"
                        "The 10 Corpus-Trained Musical & Film Composer Style Profiles:\n"
                        "- 1. Cinematic / Epic (Blockbuster Score): Aeolian default, 77% gap-fill, balanced heroic 5th/octave leaps and soaring legato (96%).\n"
                        "- 2. Film Composer Style 1 (Heroic Symphonic Fanfare): Lydian default, 95% triad-fanfare bonus, dotted/triplet brass rhythms, bold 4th/5th/octave leaps.\n"
                        "- 3. Film Composer Style 2 (Mysterious Pulse & Lyrical Suspense): Dorian default, 92% pivot-note return bonus, hypnotic neighbor-note suspense cells.\n"
                        "- 4. Film Composer Style 3 (Kinetic Action & Propulsive Hybrid): Aeolian default, 95% sequence-repeat bonus, driving syncopated staccato/accent action propulsion.\n"
                        "- 5. Film Composer Style 4 (Pastoral & Lyrical Epic Romance): Mixolydian default, 98% legato cantabile arch, avoids semitone leading-tone harshness.\n"
                        "- 6. Classical / Baroque (Chamber & Counterpoint): Major default, 55% sequence repetition, disciplined stepwise voice-leading.\n"
                        "- 7. Romantic / Lyrical (Cantabile / Late-Romantic): Harmonic Minor default, 98% legato phrasing with expressive 6th leaps.\n"
                        "- 8. Punky / Driving Action (Syncopated Pulse): Minor Pentatonic default, 65% staccato and punchy syncopated accents.\n"
                        "- 9. Ancient / Celtic Modal (Dorian / Mythic): Dorian default, modal folk intervals avoiding semitone leading tones.\n"
                        "- 10. Dark Thriller / Suspense (Phrygian / Noir): Phrygian default, 80% pivot return, minor-2nd and tritone noir tension."
            },
            {
                "heading": "11.9 Per-Track Freehand Annotation Layer System (v2.40 - v2.50)",
                "text": "Overview & Workflow (modules/services/annotation_service.lua & modules/ui/annotation_drawer.lua):\n"
                        "- Multi-Layer Per-Track Score Annotations: Open the right-hand 'Annotations' drawer to create, rename, reorder, show/hide, or delete independent freehand drawing layers for each instrument track in your score.\n"
                        "- Pen & Eraser Tools with Capsule SDF Anti-Aliasing: Draw directly over staves, measures, and notes using the Pen tool (with configurable brush radius and 12 curated color presets) or erase strokes cleanly with the Eraser tool. Strokes are rasterized using smooth Capsule Signed-Distance-Field (SDF) anti-aliasing.\n"
                        "- 4 Configurable Instrument Tile Resolutions: Choose from 4 resolution steps per instrument track for crisp vector-like ink fidelity at any zoom level.\n"
                        "- Transparent PNG Persistence & Inline Layer Renaming: Annotation tiles are automatically saved as transparent PNGs linked to your project, and double-clicking any layer name opens an inline rename box (automatically suppressing global single-key score shortcuts while typing)."
            }
        ]
    },
    {
        "chapter": 12,
        "title": "MusicXML 4.0 Import & Export",
        "sections": [
            {
                "heading": "12.1 Interoperability Standard",
                "text": "Functions: MusicXML 4.0 is the universal interchange format between professional notation software. REAPER-Notator includes a dedicated MusicXML parser and exporter written in pure Lua."
            },
            {
                "heading": "12.2 Importing Scores, Mid-Piece Time Signature Sync & Articulation Auto-Mapping",
                "text": "Functions:\n"
                        "- Orchestral Score Import: Click 'Import MusicXML' to load orchestral scores created in external notation programs. Notator parses parts, measures, time signatures, key signatures, pitch data, dynamics, lyrics, slurs, ties, and tempo markers, creating fully arranged tracks and MIDI items directly in REAPER.\n"
                        "- Mid-Piece Time Signature Timeline Sync & Orphaned Metadata Cleanup (v2.0.7): Automatically synchronizes mid-piece NOTATOR_TIME_SIG changes from imported MIDI takes directly to REAPER's master timeline via SetTempoTimeSigMarker, prunes orphaned legacy ProjExtState ties/key signatures on import and project load, and scopes legacy ties to prevent cross-track duplication.\n"
                        "- Intelligent Articulation Detection: Automatically analyzes Reaticulate sound banks loaded on destination tracks. Employs a prioritized 3-tier mapping algorithm for articulations (e.g. prioritizing dedicated 'Staccato Dig' patches for Spitfire Double Basses over fallback 'Short 0.5' duration patches).\n"
                        "- Compact Track Layout: Automatically collapses imported track heights (25px) to provide an immediate, organized orchestral overview without overwhelming the REAPER track arrangement."
            },
            {
                "heading": "12.3 Exporting Scores",
                "text": "Functions: Click 'Export MusicXML' to save your REAPER project as a standard .musicxml file ready for publication, live orchestral recording sessions, or further engraving."
            }
        ]
    },
    {
        "chapter": 13,
        "title": "Score Clipboard & Selective Copy/Paste Engine",
        "sections": [
            {
                "heading": "13.1 Selective Note & Score Clipboard",
                "text": "Functions: High-precision clipboard operations (Ctrl+C / Ctrl+V) with strict element isolation:\n"
                        "- Selective Note Copying: When copying selected notes, the clipboard selectively captures notes, chords, and explicit note articulations (staccato, accent, tenuto, fermatas) without inadvertently dragging along unselected dynamics, hairpins, pedal lines, or tempo markers.\n"
                        "- Context-Aware Pasting & Range Overwrite: Pasting notes into a MIDI item (Ctrl+V) performs an intelligent range overwrite. Preexisting notes, notation text events, Program Changes, and obsolete chase events falling within the pasted time window `[target_start_qn, target_start_qn + total_dur_qn]` are cleanly replaced. Notes crossing the paste boundaries are cleanly truncated without overlapping voice collisions. Following the paste, Notator immediately recalculates and positions the Auto-Chase return events to preserve seamless articulation transitions.\n"
                        "- Independent Element Duplication: Dynamics, hairpins, and pedal lines can also be copied and pasted independently, ensuring modular workflow efficiency."
            },
            {
                "heading": "13.2 Quantization & Sub-Tick Boundary Alignment",
                "text": "Functions: Precision alignment engine across copy/paste and editing routines:\n"
                        "- PPQ Temporal Integrity: Pasted notes maintain exact sub-tick delta relationships relative to the edit cursor.\n"
                        "- Track-Targeting: Clipboard contents paste directly into the active or focused track, enabling rapid passage duplication across orchestral sections."
            }
        ]
    },
    {
        "chapter": 14,
        "title": "Engine Architecture & Performance Optimization",
        "sections": [
            {
                "heading": "14.1 High-Efficiency O(1) Project State Caching",
                "text": "Functions:\n"
                        "- Project State Guard: Monitors reaper.GetProjectStateChangeCount(0) to eliminate thousands of redundant C-API queries during playback and idle, reducing C-API calls to 0 when the score is static.\n"
                        "- Text Size Memoization: Caches ImGui font measurement dimensions to eliminate repeated layout calculation storms.\n"
                        "- ReaImGui Context Validation: Strict pointer validation guarantees rock-solid stability during project switching and window operations."
            },
            {
                "heading": "14.2 Hardware-Accelerated Vector Graphics",
                "text": "Functions:\n"
                        "- Pure GPU-Rasterized Drawing: ReaImGui dispatches all vector paths, noteheads, and beams directly to DirectX 11 / OpenGL / Vulkan.\n"
                        "- Optimized Beam Meshing: Eliminated redundant contour stroking on filled polygons, reducing vertex count by 60% and halving C-API call overhead."
            },
            {
                "heading": "14.3 Playback Editing Query Bypass (60-70+ FPS on 30+ Tracks)",
                "text": "Functions:\n"
                        "- Zero-Latency Playback Pipeline: During active timeline playback, all mouse hover checks, ghost note previews, drag evaluations, Take C-API queries, and redundant track state scans are completely bypassed.\n"
                        "- In-Memory Layout Cache: Visual notes, stems, beams, and collision avoidance tables are precomputed once into an ultra-fast layout cache, rendering notes directly from memory with zero table allocations per frame.\n"
                        "- High Track Count Scalability: Delivers stable 60-70+ FPS playback on complex symphonic projects exceeding 30 tracks and thousands of active notes."
            },
            {
                "heading": "14.4 Viewport Frustum Culling & Coordinate Invalidation",
                "text": "Functions:\n"
                        "- 2D Frustum Culling: Bypasses drawing calculations for staves, notes, slurs, glissandi, and dynamic markings located outside the visible screen viewport.\n"
                        "- Strict Coordinate Invalidation: Off-screen notes in the layout cache have their visual coordinates explicitly set to -999999, preventing stale stems, beams, or barlines from rendering when rapidly scrolling or jumping via auto-scroll."
            },
            {
                "heading": "14.5 Same-Frame Auto-Scroll Re-anchoring",
                "text": "Functions:\n"
                        "- Zero-Latency Viewport Tracking: When follow-playhead (Auto-Scroll) triggers SetScrollX, the canvas origin, margin offsets, and measure position maps are re-anchored immediately within the exact same frame, eliminating single-frame desynchronization and visual jitter.\n"
                        "- Stopped-State Auto-Scroll Decoupling: While playback is stopped, auto-scroll is decoupled from manual canvas navigation, re-centering only when REAPER's edit cursor is explicitly relocated externally."
            },
            {
                "heading": "14.6 MusicXML Slur/Tie Spatial Index & Cached Key/Time Signature Engine (v2.0.7)",
                "text": "Functions:\n"
                        "- Per-Frame Slur & Tie Spatial/Pitch Index (get_note_render_index): Eliminates framerate drops in dense orchestral MusicXML scores containing hundreds of ties and slurs by indexing rendered notes by pitch (by_pitch) and timeline range (min_qn / max_qn), caching resolved_ties and resolved_slurs, memoizing GUID normalization (_norm_guid_cache), and using direct MediaTrack pointer comparisons—removing ~200,000 ValidatePtr/GetTrackGUID C-API calls and ~1.5M table iterations per frame.\n"
                        "- Take-Level Key & Time Signature Caching: Caches NOTATOR_KEY and NOTATOR_TIME_SIG text events per take (_take_time_events_cache, _item_pext_time_cache) with precomputed quarter-note (evt.qn) values, eliminating ~25,000 MIDI_CountEvts/MIDI_GetTextSysexEvt C-API calls and ~50,000 regex evaluations per frame."
            }
        ]
    },
    {
        "chapter": 15,
        "title": "Integrated Multi-Lane MIDI Editor",
        "sections": [
            {
                "heading": "15.1 Architecture & Synchronized Workflow",
                "text": "Functions:\n"
                        "- Docked Bottom Drawer: The Integrated MIDI Editor lives in a collapsible drawer docked directly beneath the score canvas, toggled via the bottom utility bar.\n"
                        "- Bidirectional Take Synchronization: Any edits made on the notation canvas instantly update the MIDI Editor timeline, and adjustments to velocities or CC nodes immediately write to REAPER's active MIDI take.\n"
                        "- Standalone Reference Guide: For an exhaustive guide, see the dedicated standalone documentation at tools/midi_editor_manual.md."
            },
            {
                "heading": "15.2 Note Velocity Lane & REAPER Flag Handles",
                "text": "Functions:\n"
                        "- Velocity Stalks with Flags: Note velocities (1 to 127) are represented as vertical stalks with interactive top handles ('Fahnchen') styled after REAPER's native MIDI editor.\n"
                        "- Interactive Audition Drag: Clicking and vertically dragging any flag handle adjusts the note velocity in real time, accompanied by zero-latency acoustic preview sound reflecting the new velocity level.\n"
                        "- Pencil Draw Tool: Activating the Draw tool (pencil cursor) allows sweeping across the lane to paint freehand velocity curves across consecutive notes.\n"
                        "- Dynamic Velocity Presets: Instant one-click quantization buttons for pp (32), mp (64), mf (80), f (96), and ff (112) applied to selected notes or all notes.\n"
                        "- Linear Ramp & Humanize: 'Ramp' generates a smooth linear velocity progression between selected notes, while 'Humanize' applies natural acoustic micro-variations (+/- 7)."
            },
            {
                "heading": "15.3 128 Continuous Controller Lanes & Linear Ramping",
                "text": "Functions:\n"
                        "- Complete 128 CC Controller Support: Edit Modulation (CC 1), Breath (CC 2), Volume (CC 7), Pan (CC 10), Expression (CC 11), Sustain Pedal (CC 64), and any other standard MIDI controller (CC 0 to 127).\n"
                        "- Freehand CC Curve Drawing: Paint smooth continuous automation curves with real-time vector pencil feedback.\n"
                        "- REAPER CC Curve Shapes: Fully integrated with REAPER's envelope shapes (Linear Ramp default, Square Step, Slow Start/End S-Curve, Fast Start, Fast End, and Bezier), eliminating ugly staircase steps ('Treppenstufen').\n"
                        "- Convert All to Linear: One-click batch conversion command that scans the active CC lane and transforms legacy step events into smooth linear ramps.\n"
                        "- Level Stamps & Purge: Instant level buttons (0, 32, 64, 96, 127) to stamp constant values across the item, and 'Clear CC' to purge the lane."
            },
            {
                "heading": "15.4 Dynamic CC Shaping Protection & Bypass Lock",
                "text": "Functions:\n"
                        "- Orchestral Dynamics Protection: When automated score dynamics (hairpins, swell curves) are controlling CC 1 (Modulation) or CC 11 (Expression), these lanes are automatically locked to prevent accidental pencil overwrites.\n"
                        "- Visual Lock Status: The lane header displays a red padlock indicator ('[Locked] CC Locked (Dynamic Shaping)').\n"
                        "- 1-Click Unlock / Bypass: Clicking 'Unlock (Enable Bypass)' immediately decouples the active item from automated shaping, giving full manual control over the CC curve."
            }
        ]
    },
    {
        "chapter": 16,
        "title": "Modernized Interface & Performance Settings",
        "sections": [
            {
                "heading": "16.1 Target Framerate (FPS) & Native High-Refresh Timer Engine (v2.0.5 - v2.0.7)",
                "text": "Functions:\n"
                        "- Configurable Target FPS: Located in Settings -> General Settings, allowing users to tailor GUI performance to their hardware.\n"
                        "- Selectable Presets: 15 FPS (Ultra Power Saver), 30 FPS (Power Saver / Large Scores), 60 FPS (Default / Standard Smooth), 90 FPS (High-Refresh), 120 FPS (High-Refresh Pro), 144 FPS (Ultra-High Refresh), and Uncapped / Native Host Rate (VSync).\n"
                        "- Native Win32 0x29a Timer Bridge (modules/bin/notator_timer_x64.dll & FrameTimerService, v2.0.5+): Unlocks REAPER's hardcoded 30ms (~32.0 FPS) global reaper.defer() and ReaImGui timer ceiling on Windows. Synchronizes REAPER's 0x29a main-window timer at 1ms kernel precision with the user's selected Target Framerate while REAPER Notator is open, and automatically restores REAPER's default 30ms timer upon closing (via atexit + 800ms auto-shutoff watchdog).\n"
                        "- Live Real-Time FPS Meter: Displays real-time rendering framerate ('Live: XX.X FPS') to evaluate GPU load."
            },
            {
                "heading": "16.2 Hardware Vector Line Anti-Aliasing",
                "text": "Functions:\n"
                        "- Dear ImGui Anti-Aliasing Toggle: Controls subpixel edge smoothing on vector lines and polygons.\n"
                        "- High-Performance Mode (Unchecked - Recommended): Delivers pure zero-overhead rasterization for massive 30+ track orchestral scores.\n"
                        "- Smooth Line AA Mode (Checked): Enables alpha-gradient edge anti-aliasing on stems, beams, and staff lines.\n"
                        "- Font Atlas Independence: Noteheads, accidentals, clefs, numbers, and rehearsal marks are rendered via high-resolution font texture atlases and remain ultra-smooth in all modes."
            },
            {
                "heading": "16.3 Undo Depth Limit & Memory Management",
                "text": "Functions:\n"
                        "- Max Undo Steps Slider: Restricts consecutive undo history depth (0 to 200, default: 50). Prevents continuous CC/velocity pencil drawing from ballooning project RAM and slowing REAPER state serialization.\n"
                        "- Clear Project Undo History: Dedicated button ('Clear Project Undo History') that purges accumulated project undo history on demand and reclaims RAM."
            },
            {
                "heading": "16.4 View Navigation & Mouse Engine",
                "text": "Functions:\n"
                        "- Ergonomic Input Mapping: Full customization of keyboard modifiers (None, Shift, Ctrl, Alt, Space, combinations) and mouse triggers (Mouse Wheel Vertical/Horizontal, Middle Mouse, Right Mouse, Left Mouse).\n"
                        "- Controllable Actions: Independently configure Horizontal View Scroll, Vertical View Scroll, Canvas Pan (Hand-Tool), and Canvas Zoom (In/Out).\n"
                        "- Speed & Inversion Sliders: Fine-tune horizontal and vertical scroll speed multipliers (0.5x to 5.0x) with independent 'Invert Horizontal Direction' and 'Invert Vertical Direction' checkboxes.\n"
                        "- One-Click Reset: 'Reset Navigation Defaults' restores standard navigation configuration instantly."
            },
            {
                "heading": "16.5 MIDI Editor & Score Color Themes",
                "text": "Functions:\n"
                        "- Dedicated Palette Customization: Settings -> MIDI Editor Colors enables full aesthetic customization of background, lane fills, grid lines, velocity stalks/flags, selection tints, and CC curves.\n"
                        "- Dark Mode & Invert Contrast: Handcrafted contrast adaptations for score paper, staves, barlines, and rehearsal boxes."
            }
        ]
    },
    {
        "chapter": 17,
        "title": "Keyboard Shortcuts & Quick Reference",
        "sections": [
            {
                "heading": "17.1 Comprehensive Hotkey Matrix",
                "text": "Quick reference table for high-speed score entry, MIDI editing, and viewport navigation:\n\n"
                        "| Key / Shortcut | Action | Description |\n"
                        "| :--- | :--- | :--- |\n"
                        "| Space | Play / Pause | Starts or stops timeline playback |\n"
                        "| Record Button (Left/Right Click) | Record / Record Settings | Left-click starts/stops MIDI recording; Right-click opens Record & Auto-Quantize Modal |\n"
                        "| Ctrl + M | Add Custom Marker | Places sequential Custom Rehearsal Marker live at Playhead or at Edit Cursor |\n"
                        "| F11 / Maximize Button | Maximize / Restore | 2-step full-monitor work area maximize and centered floating restore |\n"
                        "| Delete / Backspace | Delete | Deletes selected notes, dynamics, tempo marks, or lines |\n"
                        "| Esc | Clear Selection | Deselects all active items and clears focus |\n"
                        "| Up / Down Arrows | Transpose Pitch | Moves selected notes up/down by 1 semitone |\n"
                        "| Shift + Up / Down | Octave Shift | Moves selected notes up/down by 1 octave (12 semitones) |\n"
                        "| Left / Right Arrows | Nudge Position | Shifts notes horizontally by the active grid increment |\n"
                        "| Shift + Left / Right | Resize Duration | Shortens or lengthens selected notes by grid step |\n"
                        "| Alt + Left / Right | Select Note | Navigates to previous / next note on timeline without mouse usage |\n"
                        "| Alt + Shift + Left / Right | Expand Selection | Expands multi-note selection along the timeline |\n"
                        "| X | Invert Stem | Flips note stem direction (up <-> down) |\n"
                        "| 1 .. 6 | Rhythmic Values | 1=Whole, 2=Half, 3=Quarter, 4=Eighth, 5=16th, 6=32nd |\n"
                        "| Ctrl + 1 .. 7 | Grid Snap Settings | Sets score grid: Ctrl+7=1/1, Ctrl+6=1/2, Ctrl+5=1/4, Ctrl+4=1/8, Ctrl+3=1/16, Ctrl+2=1/32, Ctrl+1=Free |\n"
                        "| Ctrl + K / 🔗 Button | Grid & Note Sync | Links Note Duration and Grid so changing one automatically updates the other |\n"
                        "| . (Period) | Toggle Dot | Toggles dotted note duration (1.5x) |\n"
                        "| - / 0 / = | Accidentals | -=Flat (b), 0=Natural (nat), ==Sharp (#) |\n"
                        "| S | Slur / Legato ([Slur]) | Toggles musical legato slur over 2 notes (or note to next); engages Legato keyswitch |\n"
                        "| T | Tie / Haltebogen ([Tie]) | Toggles tie between 2 notes of identical pitch (duration sum without second note attack) |\n"
                        "| A | Accent | Toggles accent mark (>) on selected note |\n"
                        "| Ctrl + T | New Text Item | Creates a floating text annotation at cursor position |\n"
                        "| Ctrl + S | Save Project | Triggers REAPER project save |\n"
                        "| Shift + Wheel | Horizontal Scroll | Default horizontal viewport scroll (customizable in Settings) |\n"
                        "| Middle Mouse Drag | Canvas Pan | Default Hand-tool panning (customizable in Settings) |\n"
                        "| Ctrl + Wheel | Canvas Zoom | Zooms score canvas in and out |"
            }
        ]
    },
    {
        "chapter": 18,
        "title": "Elaine Gould (Behind Bars) & Gardner Read Engraving Standards Reference",
        "sections": [
            {
                "heading": "18.1 Optical Horizontal Spacing & Dynamic Measure Widths (Behind Bars pp. 38-42, Music Notation Ch. 6)",
                "text": "- Non-Linear Rhythmic Spacing (t^0.70): Instead of spacing notes linearly by MIDI tick length (which crushes 16th and 32nd notes together and wastes horizontal space on whole and half notes), intra-measure rhythmic intervals are weighted by a non-linear power curve (delta_t^0.70). A half note takes roughly 1.62x the width of a quarter note rather than 2.0x.\n"
                        "- Dynamic Collision-Free Measure Expansion: Before rendering a system, every measure is scanned across all visible tracks for horizontal density. The engine counts rhythmically distinct note onsets, accidental columns, chord second displacements, and augmentation dots. Dense bars automatically expand horizontally so noteheads, dots, and accidentals never collide."
            },
            {
                "heading": "18.2 Stems: Direction, Ledger Extensions & Multi-Flag Lengthening (Behind Bars pp. 13-16, Music Notation pp. 65-69)",
                "text": "- Middle-Line Rule: Single notes on the middle staff line (dstep == 4) default to stem down, or follow the local melodic and beam group context.\n"
                        "- Stem Extension to the Middle Line: Notes on multiple ledger lines far above or below the staff automatically extend their stems all the way to the middle staff line.\n"
                        "- 32nd & 64th Flag Stem Lengthening: Unbeamed notes with 3 or more flags (32nd and 64th notes) automatically lengthen their stems by one full staff space per additional flag beyond the 16th flag, preventing the innermost flag from colliding with the notehead."
            },
            {
                "heading": "18.3 Beaming: Metric Grouping, Rest-Breaking & Fractional Stubs (Behind Bars pp. 17-29 & 152-158, Music Notation pp. 71-81)",
                "text": "- Time-Signature-Aware Metric Grouping: Beams automatically break at main beat boundaries according to the active time signature, including compound meters (6/8, 9/8, 12/8) and asymmetric meters (5/8, 7/8).\n"
                        "- Automatic Beam Breaking Across Rests: Any intervening rest splits the active beam group so primary/secondary beams and 16th stubs never cut across rest glyphs.\n"
                        "- Inner-Beam Notehead Clearance: In beamed groups with 3 or more beams (32nd and 64th notes), stems are lengthened so the innermost beam always maintains at least 1.75 staff spaces of clearance from every notehead in the group.\n"
                        "- Damped Beam Slopes: Beam angles follow the melodic contour but are damped to a maximum slant of 1.25 staff spaces and flattened to horizontal on outer-interval inversions to avoid steep angles.\n"
                        "- Paired Fractional Beam Stubs: Isolated 16th and 32nd sub-beam stubs never point outside the beam group or into a rest. Interior stubs always point toward their rhythmically paired dotted note or metric half-beat subdivision."
            },
            {
                "heading": "18.4 Chords, Seconds (2nds) & Augmentation Dots (Behind Bars pp. 16 & 48-50, Music Notation pp. 69-70 & 113-115)",
                "text": "- Strict Two-Side Alternation for Chord Clusters: When a chord contains adjacent diatonic steps (seconds, or dense clusters like C-D-E), noteheads strictly alternate between the normal stem side and the displaced side starting from the stem root toward the stem tip. On an up-stem, the higher note of a second goes to the right of the stem while the lower note stays on the left. On a down-stem, the lower note of a second goes to the left of the stem while the higher note stays on the right. Noteheads are never placed on three columns across a single stem.\n"
                        "- Staff-Line Avoidance for Augmentation Dots: Augmentation dots never sit on a staff line. Notes on a line place their dot in the staff space immediately above.\n"
                        "- Dotted Chord Second Separation: In a dotted chord containing a second where the lower note sits on a line and the upper note already occupies the space above, the lower note dot shifts into the space below so two dots never stack in the same space."
            },
            {
                "heading": "18.5 Accidentals: Intra-Bar Memory, Natural Cancellation & Staggered Columns (Behind Bars pp. 50-54 & 78-85, Music Notation pp. 129-137)",
                "text": "- Intra-Measure Accidental Memory: Accidentals remain active for the same diatonic step and octave within a measure. Repeated altered notes in the same bar omit redundant accidentals. Returning to the diatonic key-signature pitch within the same bar automatically adds a natural cancellation sign (or the key signature sharp or flat). Tied continuation notes across a barline suppress redundant accidentals inside the same system.\n"
                        "- Multi-Column Diagonal Stacking in Chords: When multiple accidentals appear on a chord within fewer than 6 diatonic steps of each other, they stagger into up to 3 collision-free columns ordered from top-right to bottom-left, while octave intervals share the same vertical column."
            },
            {
                "heading": "18.6 Articulations: Staff-Line Avoidance & Vertical Hierarchy (Behind Bars pp. 115-121, Music Notation pp. 247-264)",
                "text": "- No Articulations on Staff Lines: Staccato dots and tenuto lines placed inside the staff automatically snap to the nearest staff space so they are never bisected by a staff line.\n"
                        "- Outside-Staff Accents & Always-Above Marks: Accents are always placed outside the five-line staff. Marcato, harmonic circles, and fermatas are always placed above the staff, clearing both the top staff line and any up-stem tips."
            },
            {
                "heading": "18.7 Ties & Slurs: Tapered Crescent Profiles, Adjacency & Stem/Articulation Clearance (Behind Bars pp. 60-66 & 110-115, Music Notation pp. 116-121 & 265-268)",
                "text": "- Dual-Bezier Tapered Crescent Rendering: Ties and slurs are drawn as 24-segment filled dual cubic-Bezier polygons with thin pointed ends and a thicker midpoint.\n"
                        "- Tie Adjacency Rule: Ties connect only immediately adjacent notes of the same pitch and never jump across an intervening note.\n"
                        "- Outward Chord Tie Splitting: In multi-note chords (both automatic barline ties and manual ties), ties split outward from the center of the chord (upper notes curve up, lower notes curve down).\n"
                        "- Slur Clearance Over Ties, Stems & Articulations: When a slur and a tie share the same side, the slur arches outside the tie with at least 1 staff space of separation. On mixed-stem phrases where the slur curves above an up-stem note, the slur anchors above the stem tip rather than cutting through the stem. Slur endpoints also anchor outside staccato and tenuto marks."
            },
            {
                "heading": "18.8 Rests, Tuplets, Glissandi & System Braces (Behind Bars pp. 136-137, 152-168, 196-204 & 499-502)",
                "text": "- Whole-Measure Rests & Metric Consolidation: Empty measures display a centered whole-bar rest hanging from the fourth line regardless of time signature. Tied chains within a bar consolidate into single dotted or standard note values where metrically valid.\n"
                        "- Polyphonic Voice Rest Merging: Identical rests occurring at the same time in Voice 1 and Voice 2 merge at the middle line, while different rest values shift vertically to their respective voice registers.\n"
                        "- Tuplet Brackets: Unbeamed tuplet brackets clear the top staff line, all up-stem tips, and any above-note articulations, with a centered gap for the tuplet number.\n"
                        "- Glissando & Portamento Endpoint Gaps: Wavy glissando and straight portamento lines automatically start to the right of any augmentation dot on the starting note and stop to the left of any accidental on the target note.\n"
                        "- System Braces vs. Brackets: Orchestral family groups use a straight system bracket with winged tips, while Grand Staff (Piano) and Harp tracks use a curved S-Bezier accolade brace tapering to a central point."
            },
            {
                "heading": "18.9 Tremolo Slash Stem Centering & Automated Unit Test Suite (Behind Bars pp. 220-224, v2.46 - v2.50-beta.3)",
                "text": "- Unmeasured & Measured Tremolo Slash Centering (v2.49-beta): Tremolo slashes (1 to 3 diagonal slashes) are horizontally centered directly on the exact stem X-coordinate (stem_x) for both unbeamed notes and beamed groups across all zoom levels (0.6x to 2.0x), maintaining clearance from noteheads and positioning inside beam groups.\n"
                        "- Comprehensive Automated Unit Test Suite (tests/test_all_modules.lua & tests/mock_reaper.lua): Verifies all 19 core modules and services via 152 headless automated unit tests—covering Constants,GM Drum Maps (C0-C9), Automatic Clef & Percussion Detection, Custom Notehead Persistence, Note Deletion Cleanup,Tremolo Stem Placement, Engraver Rules, Dynamics, Slurs/Ties, MusicXML Import/Export, Divisi/Divisio Vocum, Melodic Pathfinder, Annotation Layers, and Record/Auto-Quantize."
            }
        ]
    }
]

# Write Markdown Documentation
with open(MD_PATH, "w", encoding="utf-8") as md:
    md.write("# REAPER-Notator - Official User Manual & Function Reference\n\n")
    md.write(f"**Version:** {VERSION}  \n**Date:** {datetime.datetime.now().strftime('%Y-%m-%d')}  \n**License:** GNU General Public License v3.0  \n\n")
    md.write("---\n\n## Table of Contents\n\n")
    for chap in MANUAL_DATA:
        anchor = chap['title'].lower().replace(' ', '-').replace('&', '').replace(',', '').replace('(', '').replace(')', '').replace('---', '-')
        md.write(f"- [Chapter {chap['chapter']}: {chap['title']}](#chapter-{chap['chapter']}-{anchor})\n")
    md.write("\n---\n\n")
    
    for chap in MANUAL_DATA:
        anchor = chap['title'].lower().replace(' ', '-').replace('&', '').replace(',', '').replace('(', '').replace(')', '').replace('---', '-')
        md.write(f"## Chapter {chap['chapter']}: {chap['title']}\n\n")
        for sec in chap["sections"]:
            md.write(f"### {sec['heading']}\n\n")
            md.write(f"{sec['text']}\n\n")
        md.write("---\n\n")

print(f"Generated Markdown manual: {MD_PATH}")

# Modern PDF Generator with fpdf2
class ManualPDF(FPDF):
    def header(self):
        if self.page_no() == 1:
            return
        self.set_font("Helvetica", "B", 8)
        self.set_text_color(100, 116, 139) # Slate 500
        self.cell(self.epw * 0.7, 7, "REAPER-Notator  -  Official User Manual & Function Reference", new_x=XPos.RIGHT, new_y=YPos.TOP)
        self.cell(self.epw * 0.3, 7, f"v{VERSION}", align="R", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
        self.set_draw_color(226, 232, 240)
        self.line(self.l_margin, 14, self.w - self.r_margin, 14)
        self.ln(5)

    def footer(self):
        if self.page_no() == 1:
            return
        self.set_y(-12)
        self.set_font("Helvetica", "I", 8)
        self.set_text_color(148, 163, 184)
        self.cell(self.epw, 8, f"Page {self.page_no()}/{{nb}}  -  REAPER-Notator Documentation", align="C", new_x=XPos.LMARGIN, new_y=YPos.NEXT)

pdf = ManualPDF(orientation="P", unit="mm", format="A4")
pdf.set_margins(left=14, top=14, right=14)
pdf.alias_nb_pages()
pdf.set_auto_page_break(auto=True, margin=15)

# --- COVER / TITLE PAGE ---
pdf.add_page()
pdf.ln(20)

# Accent Banner
pdf.set_fill_color(249, 115, 22) # Orange 500
pdf.rect(14, 30, 8, 40, "F")

pdf.set_xy(28, 30)
pdf.set_font("Helvetica", "B", 30)
pdf.set_text_color(15, 23, 42) # Slate 900
pdf.cell(pdf.epw - 14, 13, "REAPER-Notator", new_x=XPos.LMARGIN, new_y=YPos.NEXT)

pdf.set_x(28)
pdf.set_font("Helvetica", "", 15)
pdf.set_text_color(71, 85, 105) # Slate 600
pdf.cell(pdf.epw - 14, 8, "Complete User Manual & Functional Reference", new_x=XPos.LMARGIN, new_y=YPos.NEXT)

pdf.set_x(28)
pdf.set_font("Helvetica", "I", 10)
pdf.set_text_color(100, 116, 139)
pdf.cell(pdf.epw - 14, 6, "Native Score Editing, Engraving & DAW Automation for Cockos REAPER", new_x=XPos.LMARGIN, new_y=YPos.NEXT)

pdf.ln(30)

# Metadata Info Box
pdf.set_x(14)
box_y = pdf.get_y()
pdf.set_fill_color(248, 250, 252)
pdf.set_draw_color(226, 232, 240)
pdf.rect(14, box_y, pdf.epw, 36, "DF")

items = [
    ("Version:", f"v{VERSION} (Production Release)"),
    ("Release Date:", datetime.datetime.now().strftime("%B %d, %Y")),
    ("Compatibility:", "Cockos REAPER v7.0+ (Windows, macOS, Linux) with ReaImGui & Reaticulate"),
    ("License:", "GNU General Public License v3.0 (GPL-3.0)")
]

for idx, (lbl, val) in enumerate(items):
    pdf.set_xy(18, box_y + 4 + idx * 7.5)
    pdf.set_font("Helvetica", "B", 9.5)
    pdf.set_text_color(30, 41, 59)
    pdf.cell(35, 6, lbl, new_x=XPos.RIGHT, new_y=YPos.TOP)
    pdf.set_font("Helvetica", "", 9.5)
    pdf.set_text_color(71, 85, 105)
    pdf.cell(pdf.epw - 40, 6, val, new_x=XPos.LMARGIN, new_y=YPos.NEXT)

pdf.set_y(box_y + 42)

# Executive Table of Contents Box
pdf.set_font("Helvetica", "B", 13)
pdf.set_text_color(30, 41, 59)
pdf.cell(pdf.epw, 8, "Manual Contents Summary", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
pdf.ln(2)

pdf.set_font("Helvetica", "", 9)
for chap in MANUAL_DATA:
    pdf.set_font("Helvetica", "B", 9)
    pdf.set_text_color(234, 88, 12)
    pdf.cell(14, 5.5, f"Ch. {chap['chapter']}:", align="R", new_x=XPos.RIGHT, new_y=YPos.TOP)
    pdf.set_font("Helvetica", "", 9)
    pdf.set_text_color(51, 65, 85)
    pdf.cell(pdf.epw - 14, 5.5, f"  {chap['title']}", new_x=XPos.LMARGIN, new_y=YPos.NEXT)

def sanitize_pdf_text(text: str) -> str:
    replacements = {
        "\u2669": "[Quarter]",
        "\u266a": "[Eighth]",
        "\u266b": "[Beamed Eighths]",
        "\u2013": "-",
        "\u2014": "-",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2026": "...",
        "\u2264": "<=",
        "\u2265": ">=",
        "\u2248": "~",
        "\u2260": "!=",
        "⚡": "[Fix]",
        "🎥": "[Video]",
        "📺": "[Video]",
        "🧹": "[Purge]",
        "✕": "[X]",
        "⌒": "[Slur]",
        "‿": "[Tie]",
        "🎹": "[MIDI]",
        "📈": "[Linear]",
        "🔒": "[Locked]",
        "🔓": "[Unlocked]",
        "✏": "[Draw]",
        "🎲": "[Humanize]",
        "⚙": "[Settings]",
        "🖱": "[Mouse]",
        "↺": "[Reset]",
        "⎍": "[Step]",
        "〰": "[S-Curve]",
        "⏳": "[Fast End]",
        "∿": "[Bezier]",
        "↔": "[Fit]",
        "＋": "+",
        "－": "-",
        "🎼": "[Score]",
        "🛠": "[Tools]",
        "➔": "->",
        "✓": "[OK]",
        "⚠": "[!]",
        "🔗": "[Link]",
        "🗑": "[Delete]",
    }
    for k, v in replacements.items():
        text = text.replace(k, v)
    return text.encode("latin-1", "replace").decode("latin-1")

# --- CHAPTER PAGES ---
for chap in MANUAL_DATA:
    pdf.add_page()
    
    # Chapter Banner
    curr_y = pdf.get_y()
    pdf.set_fill_color(30, 41, 59)
    pdf.rect(pdf.l_margin, curr_y, pdf.epw, 10, "F")
    pdf.set_font("Helvetica", "B", 11)
    pdf.set_text_color(255, 255, 255)
    pdf.set_xy(pdf.l_margin + 4, curr_y + 1)
    pdf.cell(pdf.epw - 8, 8, sanitize_pdf_text(f"Chapter {chap['chapter']}: {chap['title']}"), new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    pdf.set_y(curr_y + 14)
    
    for sec in chap["sections"]:
        # Check space before section heading
        if pdf.get_y() > 255:
            pdf.add_page()
            pdf.ln(5)
            
        # Section Heading
        pdf.set_font("Helvetica", "B", 10)
        pdf.set_text_color(234, 88, 12) # Amber / Orange
        pdf.cell(pdf.epw, 6, sanitize_pdf_text(sec["heading"]), new_x=XPos.LMARGIN, new_y=YPos.NEXT)
        pdf.ln(1)
        
        # Section Body
        pdf.set_font("Helvetica", "", 8.5)
        pdf.set_text_color(30, 41, 59)
        
        raw_text = sanitize_pdf_text(sec["text"])
        lines = raw_text.split("\n")
        in_table = False
        table_rows = []
        in_code = False
        code_lines = []
        
        for l in lines:
            line_str = l.strip()
            if line_str.startswith("```"):
                if not in_code:
                    in_code = True
                    code_lines = []
                else:
                    in_code = False
                    if code_lines:
                        pdf.ln(1)
                        needed_h = len(code_lines) * 3.3 + 4
                        if pdf.get_y() + needed_h > 275:
                            pdf.add_page()
                            pdf.ln(2)
                        box_y = pdf.get_y()
                        pdf.set_fill_color(248, 250, 252)
                        pdf.set_draw_color(203, 213, 225)
                        pdf.rect(pdf.l_margin, box_y, pdf.epw, needed_h, "DF")
                        pdf.set_font("Courier", "", 6.2)
                        pdf.set_text_color(30, 41, 59)
                        pdf.set_y(box_y + 2)
                        for cl in code_lines:
                            pdf.set_x(pdf.l_margin + 2)
                            pdf.cell(pdf.epw - 4, 3.3, cl, new_x=XPos.LMARGIN, new_y=YPos.NEXT)
                        pdf.set_font("Helvetica", "", 8.5)
                        pdf.ln(2)
                continue
                
            if in_code:
                code_lines.append(l)
                continue
                
            if not line_str:
                pdf.ln(2)
                continue
                
            if line_str.startswith("|"):
                in_table = True
                if not re.match(r"^\|[\s\-:]+\|$", line_str):
                    cols = [c.strip() for c in line_str.split("|")[1:-1]]
                    table_rows.append(cols)
                continue
            elif in_table:
                in_table = False
            
            # Format bullet points with slight indent
            if line_str.startswith("-") or line_str.startswith("*"):
                bullet_text = line_str.lstrip("-* ").strip()
                pdf.set_x(pdf.l_margin + 3)
                pdf.set_text_color(234, 88, 12)
                pdf.cell(4, 4.5, "-", new_x=XPos.RIGHT, new_y=YPos.TOP)
                pdf.set_text_color(30, 41, 59)
                pdf.multi_cell(pdf.epw - 7, 4.5, bullet_text, new_x=XPos.LMARGIN, new_y=YPos.NEXT)
            elif line_str.startswith("DAW Effect:"):
                # Callout style for DAW effect
                pdf.set_fill_color(241, 245, 249)
                pdf.set_draw_color(203, 213, 225)
                callout_y = pdf.get_y() + 1
                pdf.set_y(callout_y)
                pdf.set_font("Helvetica", "B", 8.5)
                pdf.set_text_color(15, 23, 42)
                pdf.cell(24, 4.5, "DAW Effect: ", new_x=XPos.RIGHT, new_y=YPos.TOP)
                pdf.set_font("Helvetica", "", 8.5)
                pdf.set_text_color(51, 65, 85)
                pdf.multi_cell(pdf.epw - 24, 4.5, line_str[11:].strip(), new_x=XPos.LMARGIN, new_y=YPos.NEXT)
            else:
                pdf.multi_cell(pdf.epw, 4.5, line_str, new_x=XPos.LMARGIN, new_y=YPos.NEXT)
        
        # Render table if present
        if table_rows:
            pdf.ln(2)
            pdf.set_font("Helvetica", "B", 8)
            pdf.set_fill_color(30, 41, 59)
            pdf.set_text_color(255, 255, 255)
            
            col_widths = [36, 42, pdf.epw - 78]
            for col_idx, col_name in enumerate(table_rows[0]):
                pdf.cell(col_widths[col_idx], 6, f" {col_name}", 1, new_x=XPos.RIGHT, new_y=YPos.TOP, align="L", fill=True)
            pdf.ln(6)
            
            pdf.set_font("Helvetica", "", 8)
            for r_idx, row in enumerate(table_rows[1:]):
                bg = 255 if r_idx % 2 == 0 else 248
                pdf.set_fill_color(bg, bg, bg)
                pdf.set_text_color(30, 41, 59)
                for col_idx, cell in enumerate(row):
                    pdf.cell(col_widths[col_idx], 5.2, f" {cell}", 1, new_x=XPos.RIGHT, new_y=YPos.TOP, align="L", fill=True)
                pdf.ln(5.2)
            pdf.ln(2)
            
        pdf.ln(3)

pdf.output(PDF_PATH)
print(f"Generated PDF manual successfully: {PDF_PATH}")

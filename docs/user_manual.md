# REAPER-Notator - Official User Manual & Function Reference

**Version:** 2.0.4  
**Date:** 2026-10-14  
**License:** GNU General Public License v3.0  

---

## Table of Contents

- [Chapter 1: Introduction & Interface Architecture](#chapter-1-introduction--interface-architecture)
- [Chapter 2: Top Toolbar, Live Recording Suite & Global Navigation](#chapter-2-top-toolbar-live-recording-suite--global-navigation)
- [Chapter 3: Score Canvas & Note Editing Engine](#chapter-3-score-canvas--note-editing-engine)
- [Chapter 4: Standard-Compliant Automatic Beaming Engine](#chapter-4-standard-compliant-automatic-beaming-engine)
- [Chapter 5: Dynamics Engine, Hairpins & Bow Swell Function](#chapter-5-dynamics-engine-hairpins--bow-swell-function)
- [Chapter 6: Articulations & Reaticulate Integration](#chapter-6-articulations--reaticulate-integration)
- [Chapter 7: Holding & Sustain Pedal Lane (CC64)](#chapter-7-holding--sustain-pedal-lane-cc64)
- [Chapter 8: Tempo Maps & Metric Transitions](#chapter-8-tempo-maps--metric-transitions)
- [Chapter 9: Octave Shift Lines (8va, 8vb, 15ma, 15mb)](#chapter-9-octave-shift-lines-8va-8vb-15ma-15mb)
- [Chapter 10: Orchestral Pattern Browser & 1-Click Library](#chapter-10-orchestral-pattern-browser--1-click-library)
- [Chapter 11: Rehearsal Marks, Fermatas & Score Tools](#chapter-11-rehearsal-marks-fermatas--score-tools)
- [Chapter 12: MusicXML 4.0 Import & Export](#chapter-12-musicxml-4.0-import--export)
- [Chapter 13: Score Clipboard & Selective Copy/Paste Engine](#chapter-13-score-clipboard--selective-copy/paste-engine)
- [Chapter 14: Engine Architecture & Performance Optimization](#chapter-14-engine-architecture--performance-optimization)
- [Chapter 15: Integrated Multi-Lane MIDI Editor](#chapter-15-integrated-multi-lane-midi-editor)
- [Chapter 16: Modernized Interface & Performance Settings](#chapter-16-modernized-interface--performance-settings)
- [Chapter 17: Keyboard Shortcuts & Quick Reference](#chapter-17-keyboard-shortcuts--quick-reference)

---

## Chapter 1: Introduction & Interface Architecture

### 1.1 Overview, Vision & Prerequisites

REAPER-Notator is a native, professional music scoring, notation editing, and engraving environment built directly into Cockos REAPER using ReaImGui and standard SMuFL (Standard Music Font Layout) Bravura vector glyphs. Unlike external scoring applications, Notator runs directly inside REAPER's audio engine and timeline, providing instantaneous two-way synchronization between visual music notation and underlying REAPER MIDI takes, CC automation, and tempo maps.

Prerequisites & System Requirements:
- Cockos REAPER v7.0 or higher.
- ReaImGui extension (v0.9+ via ReaPack).
- Reaticulate (Required prerequisite for articulation handling, sound bank definitions, keyswitch chasing, and playback routing; install via ReaPack: https://reaticulate.com/).
- SWS / S&M Extension & JS_ReaScriptAPI (recommended).

### 1.2 The Three-Column Workspace Layout

The user interface is designed around an ergonomic three-column layout:

- Left Column (Sidebar Palette): Quick tools for note entry modes (pointer, pencil, text, eraser), rhythmic durations (whole to 32nd notes), augmentation dots, accidentals, tuplets, stem orientation, and articulation toggles.
- Center Column (Score Canvas): Infinite interactive notation canvas displaying visual staves, barlines, noteheads, stems, beams, ties, slurs, lyrics, and rehearsal marks.
- Right Column (Context Drawers & Tool Panels): Collapsible slide-out panels for Dynamics automation, Reaticulate banks, Tempo maps, Clef palettes, Key signatures, Pattern browser, and Settings.

### 1.3 Window Resizing, Docking & 2-Step Monitor Maximize Engine

REAPER-Notator can run as a floating window or docked directly into any REAPER docker (bottom, top, left, right, or multi-tabbed). The score canvas dynamically scales according to the zoom factor (adjustable from 0.6x to 2.0x), preserving crisp vector typography at all DPI scaling factors.

2-Step Monitor Maximize, Startup Centering & Multi-Monitor Management (v2.0.1+):
- Centered Floating Startup (Clean Session Launch): On every REAPER startup or script launch, REAPER-Notator first queries the maximum possible work area of the target monitor (via ImGui_GetMainViewport and reaper.my_getViewport with HiDPI coordinate conversion) and opens in a clean, centered floating window in the middle of the screen. Maximization state (is_maximized) is intentionally not persisted across restarts so the user always retains full control and the window can never get stuck in an un-restorable geometry.
- 2-Step Screen Maximize & Restore Toggle (Top Bar / F11): Clicking the Maximize button in the top-right toolbar (or pressing F11) executes a deterministic two-step sequence: (1) it reads the full work area bounds of the monitor where the window currently resides and stores a centered floating restore rectangle in the middle of that monitor, and (2) scales the window cleanly to 100% of the monitor work area. Clicking Restore returns the window directly to the centered floating geometry.
- Anti-Collapse Title Bar Guard & Legacy Cleanup: Uses ImGui_WindowFlags_NoCollapse and ImGui_SetNextWindowCollapsed(ctx, false) so double-clicking the title bar never collapses the window into an unresponsive shaded bar, and automatically purges obsolete pre-v2 ExtState entries on startup.
- Always-On-Top Modal Layering: All secondary configuration dialogs (Record & Auto-Quantize, Filter Irregular Notes, Quantize, Divisio Vocum, Bank Picker, Settings, and Help) render with ImGui_WindowFlags_TopMost, remaining strictly in the foreground above the score canvas.

---

## Chapter 2: Top Toolbar, Live Recording Suite & Global Navigation

### 2.1 Title & Version Indicator

Located in the upper left corner, displaying 'REAPER Notator' alongside the active build and semantic version number (v2.0.4), synchronized directly with modules/version.lua and the main @version header. When running in a Git repository environment, Notator automatically detects and displays the active commit hash via pure-Lua .git/HEAD inspection.

### 2.2 Transport & Playhead Controls

Functions:
- Rewind (|<): Instantly returns REAPER's edit cursor to measure 1.0 (time 0.0s).
- Play / Pause (> / ||): Starts timeline playback or pauses at the current cursor position. Key shortcut: Space.
- Record ([Rec] / [REC]): Dedicated transport recording button situated between Play and Stop.
  * Left-Click: Starts REAPER recording immediately (CSurf_OnRecord / Action 1013) when stopped, glowing in vivid signal red ([REC]). Clicking the red button again while recording is active calls CSurf_OnStop(), stopping both Recording and Playback completely in one click.
  * Right-Click: Opens the Recording & Auto-Quantize Settings modal dialog (RecordModal).
- Stop: Halts playback or recording completely, commits the Auto-Quantize engine to newly recorded takes (if enabled), and resets the playhead according to REAPER's project settings.
DAW Effect: Calls REAPER's CSurf_OnPlay, CSurf_OnRecord, CSurf_OnStop, and SetEditCurPos directly, maintaining sample-accurate alignment with REAPER's master audio engine.

### 2.3 Live Canvas Recording Playhead & Real-Time Live Note Preview (v2.0+)

Functions:
- Signal-Red Recording Playhead: During active recording, the score canvas renders a high-visibility signal-red vertical sweep line (0xE74C3CFF) capped with a red triangular pointer ([v]) moving in real time across all staves.
- Real-Time Live Note Preview: Polls incoming hardware and virtual MIDI Note-On and Note-Off events in real time via MIDI_GetRecentInputEvent and engraves played notes live on the score canvas at the red playhead with glowing red/coral noteheads and dynamically growing note durations while keys are held down.
- Non-Destructive Live Clamping (Zero Infinite Tie Artifacts): While recording in MIDI Overdub mode, REAPER temporarily sets the Note-Off of held notes to the end of the MIDI item until the key is released. REAPER-Notator performs real-time auto-quantize preview non-destructively on the ScoreCanvas (strictly clamping held notes to the current red playhead position) without calling MIDI_SetNote/MIDI_Sort mid-recording, and commits the final quantized notes and stop-position clamping cleanly to the REAPER take the instant recording stops.
- Continuous 60 FPS Auto-Scroll & Counter Tracking: The score viewport smoothly tracks the live recording playhead and updates the top bar Measure.Beat and elapsed time counters continuously.

### 2.4 Right-Click Record Modal: Track Arming, MIDI Input Routing, Pre-Roll & Count-In (v2.0+)

Functions (accessible by right-clicking the Record button in the Top Toolbar):
- Bidirectional REAPER Track Arming: Lists all REAPER project tracks (including empty tracks that do not yet contain MIDI items). Toggling a track's checkbox in the Record Modal immediately synchronizes REAPER's native TCP/MCP Record-Arm button (I_RECARM = 1), enables Input Monitoring (I_RECMON = 1), configures MIDI Overdub (I_RECMODE = 7) so REAPER records directly into MIDI score takes without popping up Audio '.wav' Save prompts, and makes the track visible on the score canvas.
- Armed Track Red Canvas Badges: Any track armed for recording displays a subtle red background tint, red outer border, red left accent stripe, and a crisp vector circle 'REC' pill badge in the track header (with automatic track title truncation so the badge and track name never overlap).
- MIDI Input Device & Channel Selector: Choose from all connected hardware MIDI keyboards, REAPER's Virtual MIDI Keyboard (VKB), or 'All MIDI Inputs', alongside the target MIDI Channel ('All Channels' or 'Channel 1..16'), assignable globally across armed tracks or individually per track.
- Pre-Roll on Record (Action 41818): Toggle to audition preceding measures before recording punches in, with selectable Pre-Roll Bar Length (1, 2, or 4 bars synchronized with REAPER's prerollmeas configuration).
- Metronome Count-In before Record (Action 40364): Enables audible metronome lead-in clicks before recording starts, plus a 1-click shortcut button to open REAPER's native Metronome / Pre-Roll Settings dialog (Action 40049).

### 2.5 Real-Time & Post-Record Auto-Quantize Engine (v2.0+)

Functions:
- Live Preview & Automatic Commit on Stop: Previews quantized rhythmic positions live on the score canvas during recording and automatically processes newly recorded MIDI notes on all armed tracks the moment recording stops.
- Configurable Quantize Grid: Select target rhythmic division (1/4, 1/8, 1/16, 1/32, with optional Triplet grid recognition).
- Key Bounce & Overlap Cleaning: Automatically eliminates mechanical keyboard pre-bounces (< 15 ticks on identical pitch), deduplicates multiple notes snapping to the same grid slot, and trims overlapping same-pitch note tails to 1 tick prior to the next note onset.
- Strict Tick Tolerance Slider (5 to 60 Ticks, default 25 Ticks): Defines the timing window around each rhythmic grid division.
- Four Outlier Handling Modes ('Notes outside tolerance'):
  1. '[Snap] Snap to Grid' (Default): Magnetizes all recorded notes—including notes played outside the strict tick tolerance window—cleanly onto the nearest rhythmic grid division for immediately clean, readable sheet music.
  2. 'Keep natural (unquantized)': Snaps notes within the tolerance window to the grid while preserving played micro-timing for notes outside the window.
  3. 'Delete outliers': Removes stray accidental key touches that fall outside the tolerance window.
  4. 'Move to Voice 16': Routes outlier notes outside the tolerance window to Voice 16 (MIDI channel 15) so they remain audible in playback while keeping Voice 1 notation pristine.
- Transactional Undo Safety: Enclosed within a single REAPER undo block (Undo_BeginBlock2) for instant rollback via Ctrl+Z.

### 2.6 Timeline & Meter Displays

Functions:
- Measure.Beat Display: Real-time read-out of playhead position in musical bars, beats, and quarter-note ticks (e.g. '004.01.00').
- Time Signature Indicator: Active project meter (e.g. 4/4, 3/4, 6/8, 7/8).
- BPM Indicator: Project master tempo at the current playhead position.
DAW Effect: Evaluates TimeMap_GetTimeSigAtTime on every frame to mirror timeline accelerandos, ritardandos, and time signature changes.

### 2.7 Audition Preview (Note Audio on Click)

Functions:
- Single-Note Audition: Clicking or vertically dragging any note on the canvas triggers an immediate acoustic preview sound, arbitrated to audition strictly the single hovered note even in dense chords or adjacent systems.
- Non-Intrusive Direct Playback: Auditioning operates purely via direct MIDI output without ever modifying track record-arm status (I_RECARM), input monitoring (I_RECMON), or input channel routing (I_RECINPUT), guaranteeing that track states in REAPER remain 100% pristine and unaltered.
- Instant Zero-Latency Response: Notes trigger instantly on mouse click with 0 ms latency, exactly like auditioning within REAPER's native MIDI Editor.
- Dynamics & Articulation Chasing: The engine scans the project timeline from measure 1 to chase active Program Changes, note-level articulation marks (Staccato, Marcato, Tenuto, Pizzicato), and configured CC dynamics (CC11 Expression / CC1 Modwheel).
- Musical Minimum Duration: Short clicks sound for a minimum of 650 ms so that instrument attack transients, body, and acoustic room release tails ring out cleanly before Note-Off is dispatched.
DAW Effect: Dispatches synchronized Bank Select, Program Change, CC controllers, and instantaneous MIDI Note-On / scheduled Note-Off events to the active track's virtual instrument synth without altering REAPER track record arming.

### 2.8 Follow Playhead (Auto-Scroll)

Function: When active, the score canvas scrolls horizontally in real time to keep the active playback cursor centered in the viewport.

### 2.9 View Mode Selector

Functions:
- Auto: Automatically detects instrument clef based on track naming heuristics and pitch registers.
- Treble Only: Forces single G-clef staff rendering.
- Bass Only: Forces single F-clef staff rendering.
- Grand Staff: Renders classic piano/harp grand staff (Treble upper, Bass lower) connected by curly brace.

### 2.10 Track Picker & Visibility Filters

Function: Opens a multi-track routing popover allowing the user to select which REAPER tracks are currently visible, focused, or edited on the score canvas.

### 2.11 Multi-Voice System & Auto-Voice Overlap Splitting

Functions:
- 16 Polyphonic Voices: Maps MIDI channels 0-15 to 16 distinct engraving colors with configurable ghost voice opacity (5% to 100%).
- Auto-Voice: Intelligently analyzes the entire track for polyphonic overlaps and distributes them to channels 1-16.
- Auto-Split on Selection: Splits selected chordal intervals across independent voices with automatic opposite stem orientations.

### 2.12 Settings Modal & Unified Dark Mode Inversion

Functions:
- Collapsible Categorization: Settings are structured into 5 collapsible category headers (Theme & Appearance, Engraving & Notation, Audition & Playback, Shortcuts, and Advanced).
- Single Vertical Scroll Container: The entire modal body scrolls smoothly within a single child window, preventing double scrollbars and layout clipping.
- Static Action Footer: Pinned at the bottom with quick access to Reset and Close actions.
- Real-Time Shortcut Filter: Interactive search bar to quickly locate and rebind key actions.
- Comprehensive Dark Mode Inversion: Full palette inversion across all score elements, including noteheads, stems, beams, clefs, time signatures, rests, ties, lyrics, rehearsal marks, fermatas, and polyphonic voice colors.

---

## Chapter 3: Score Canvas & Note Editing Engine

### 3.1 Note Entry & Pitch Snapping

Functions:
- Click on Staff: Inserts a new note with the duration selected in the sidebar at the nearest diatonic line or space.
- Ledger Lines: When moving beyond the 5 staff lines, Notator automatically calculates and renders standard-compliant ledger lines above or below the staff.
DAW Effect: Inserts a new MIDI note event into the focused track's active MIDI take via REAPER's MIDI_InsertNote API.

### 3.2 Note Duration, Augmentation Dots & Grid Synchronization

Functions:
- Note Values: Supports 1/1 (Whole), 1/2 (Half), 1/4 (Quarter), 1/8 (Eighth), 1/16 (16th), and 1/32 (32nd) notes (number keys 1 through 6).
- Augmentation Dot: Toggles 1.5x duration expansion (keyboard shortcut: . [period]). A dotted quarter note spans 1.5 quarter notes (3 eighths).
- Grid & Note Duration Synchronization ([Link] Button / Ctrl+K): Allows linking the active note entry duration to the score grid snapping value so that adjusting one automatically updates the other.
- Dedicated Grid Hotkeys (Ctrl+1 .. Ctrl+7): Instantly sets score grid snapping via keyboard: Ctrl+7=1/1, Ctrl+6=1/2, Ctrl+5=1/4, Ctrl+4=1/8, Ctrl+3=1/16, Ctrl+2=1/32, Ctrl+1=Free Grid.
DAW Effect: Sets note start and end positions accurately in Quarter Note (QN) timeline units.

### 3.3 Accidentals (Sharps, Flats, Naturals)

Functions:
- Flat (b): Decreases chromatic pitch by 1 semitone (-1).
- Natural (nat): Cancels preceding sharp/flat accidentals according to Western music engraving conventions (0).
- Sharp (#): Increases chromatic pitch by 1 semitone (+1).
DAW Effect: Transposes the underlying MIDI note number (0-127) and tags visual notation accidentals.

### 3.4 Note Manipulation & Live MIDI Item Edge Resizing

Functions:
- Horizontal Drag: Moves notes forward or backward in time, snapping to the selected rhythmic grid (e.g. 1/4, 1/8, 1/16).
- Vertical Drag: Transposes note pitch chromatically. Moving noteheads automatically updates accidentals.
- End-Edge Drag: Lengthens or shortens note duration by pulling the right edge of the notehead.
- Arrow Keys: Up/Down transposes by semitones (Shift+Up/Down by octaves). Left/Right moves by grid increments.
- Live MIDI Item Edge Resizing: Hovering and dragging the left or right boundary edges of any MIDI item directly on the score canvas scales the item with instantaneous, real-time visual feedback during the drag (eliminating latency until mouse release) and updates REAPER's timeline media item bounds synchronously.
DAW Effect: Calls MIDI_SetNote and REAPER's SetMediaItemInfo_Value to update pitch, QN start, QN end, and item timeline boundaries in real time with atomic undo history.

### 3.5 Multi-Note Selection & Marquee Tool

Functions:
- Marquee / Box Selection: Click and drag on empty canvas space to draw a selection rectangle encompassing multiple notes across measures and staves.
- Shift + Click: Add individual notes to selection.
- Delete / Backspace: Deletes all currently selected notes simultaneously.
DAW Effect: Multi-note batch deletion and batch transposition with atomic REAPER undo block.

### 3.6 Second-Interval Collision & Voice Separation

Functions:
- Second Intervals (Seconds): Notes placed on adjacent staff degrees in the same chord automatically offset horizontally (left/right) according to Elaine Gould engraving rules to prevent notehead collisions.
- Multi-Voice Stems: Polyphonic voices automatically flip stems (Voice 1 stems up, Voice 2 stems down).

### 3.7 Standard Gould Rests & Polyphonic Rest Consolidation

Functions:
- Empty Measure Rests: Empty measures automatically display a centered whole-measure rest glyph.
- Rhythmic Rest Decomposition: Gaps between notes decompose into standard rests (quarter, eighth, 16th rests) strictly aligned to the meter division.
- Polyphonic Rest Consolidation (Behind Bars p. 308): Coincident identical rests across simultaneous voices merge into a single shared centered rest, and rests strictly avoid colliding with active sounding noteheads on secondary voices.

### 3.8 Non-Mouse Keyboard Note Navigation & Selection Expansion

Functions:
- Alt + Left / Right Arrows: Sequential note navigation along the timeline without mouse usage, selecting the previous or next note.
- Alt + Shift + Left / Right Arrows: Extends and expands note selections chronologically across the measure and score.
- Auto-Scroll Synchronization: When Follow Playhead / Auto-Scroll is active, the score canvas smoothly glides to keep newly selected notes centered in view.

---

## Chapter 4: Standard-Compliant Automatic Beaming Engine

### 4.1 Meter-Based Beat Grouping

Functions: Consecutive eighth, 16th, and 32nd notes automatically connect with solid beams. Beaming boundaries strictly observe meter division (e.g. 4/4 groups into two half-measure halves; 6/8 groups into two dotted-quarter pulses of three eighths each).

### 4.2 Slope Calculation & Melodic Contour

Functions: Beams calculate a graceful visual slant following the pitch direction of noteheads. Extreme melodic intervals apply Gould slant-clamping to prevent excessive angles, and flat passages render strictly horizontal beams.

### 4.3 Fractional Beams (Beamlets & Stubs)

Functions: Syncopated rhythms and mixed subdivisions (such as a dotted eighth followed by a 16th note) generate standard fractional beamlets (stubs) oriented toward the rhythmic pulse beat.

### 4.4 Stem Inversion ('X' Shortcut)

Functions: Pressing the 'X' key instantly flips the stem direction of selected notes (stems up vs. stems down). Inverting stems automatically recalculates beam anchor points and flag alignments.

### 4.5 Hardware-Accelerated Beaming & Smooth Edge Anti-Aliasing

Functions:
- Clockwise Vertex Winding: All beam quads (primary, secondary, and fractional beamlets) enforce strictly clockwise vertex ordering in Dear ImGui screen space (top-left -> top-right -> bottom-right -> bottom-left). This guarantees outward-facing anti-aliasing normals with silky smooth, non-jagged edges across both upward and downward stem directions.
- Outer Stem Coverage: Beam polygons extend by half stem thickness (1.25 * s) on outer stems to encompass outer stems completely without horizontal protrusion (per Gardner Read & Elaine Gould).
- Embedded Stem Terminations: Stem lines terminate slightly inside the beam thickness to ensure flat rectangular line caps remain invisible within the slanted beam polygon.
- Gould Quarter-Note Quintuplets (5:4): Full 4/4 bar quintuplets accurately calculate 0.8 QN step widths spanning exactly 4.0 QN total duration.
Performance: Minimizes C-API overhead and eliminates redundant outline strokes.

---

## Chapter 5: Dynamics Engine, Hairpins & Bow Swell Function

### 5.1 Standard Dynamic Levels (ppp to fff)

Functions: The Dynamics Drawer features 10 one-click dynamic badges:
- ppp (Pianississimo) -> Velocity ~20, CC ~25
- pp (Pianissimo) -> Velocity ~35, CC ~40
- p (Piano) -> Velocity ~50, CC ~55
- mp (Mezzo-piano) -> Velocity ~65, CC ~68
- mf (Mezzo-forte) -> Velocity ~80, CC ~82
- f (Forte) -> Velocity ~95, CC ~98
- ff (Fortissimo) -> Velocity ~110, CC ~112
- fff (Fortississimo) -> Velocity ~125, CC ~127
- sfz (Sforzando) / fp (Forte-piano): Sudden accent followed by immediate decay.
DAW Effect: Inserts dynamic text markings on the score and scales note velocities and continuous controller points.

### 5.2 Multi-Target CC Automation

Functions: Dynamics can write continuous automation curves to:
- CC1 (Modulation Wheel) - Standard for orchestral dynamics in cinematic sample libraries.
- CC11 (Expression) - Secondary loudness / timbre controller.
- CC7 (Main Volume) - Master channel volume.
- Velocity Only - Traditional keyboard velocity scaling.
DAW Effect: Generates dense, sample-accurate MIDI CC curves in REAPER's MIDI take envelope.

### 5.3 Hairpins (Crescendo & Diminuendo)

Functions:
- Crescendo (<): Visual opening wedge representing gradual increase in loudness.
- Diminuendo (>): Visual closing wedge representing gradual decrease in loudness.
- Dual Drag Handles: Circular handles at the start and end of hairpins allow exact quarter-note positioning.
- Curvature Selection: Toggle between linear ramps and exponential curves for organic acoustic swelling.
- Decoupled Scaling Boundaries: Hairpin and dynamic text drag handles strictly collide and clamp against musical dynamic markers (p, pp, mp, mf, f, etc.), other hairpins, and dynamic text markings (cresc., dim.), but completely ignore note-level articulations (such as staccato dots, accents, tenutos). This allows hairpins to span freely across dense passages of staccato notes without getting restricted or shrunk down.
- Legacy Hairpin Playback Reconciliation: If a hairpin in an older project file was previously squeezed or collapsed due to staccato note collisions, running '⚡ Fix Playback' automatically detects collapsed hairpins (<= 0.75 QN), restores them to their natural phrase boundaries, and regenerates smooth continuous CC ramps.
DAW Effect: Inscribes smooth CC ramps between the bounding dynamic levels.

### 5.4 Bow Swell Function & Bow Position Slider

Functions:
- Bow Swell Mode: Simulates acoustic string and brass swelling where a single sustained note or phrase swells up to a climax and decays back down.
- Bow Position Slider (0.0 to 1.0, default 0.5): Configures the exact peak inflection point of the swell per MIDI item. Setting 0.5 places the peak in the exact center; setting 0.8 creates an expressive late swell; setting 0.2 creates an explosive early swell.
- Per-Item Tuning: Bow swell parameters can be customized individually per MIDI item.
DAW Effect: Calculates an asymmetric Bezier CC curve mapped directly into REAPER's CC lane.

### 5.5 Phrasing & Shaping Bypass

Function: Checkbox to temporarily disable CC automation playback without deleting visual dynamic markings on the score canvas.

---

## Chapter 6: Articulations & Reaticulate Integration

### 6.1 Reaticulate Bank Auto-Discovery & Bank Picker Modal

Functions: REAPER-Notator automatically scans REAPER's Data and Scripts directories for factory and user Reaticulate sound bank definitions (Reaticulate-factory.reabank and Reaticulate.reabank). When a track is selected, Notator reads the track's P_EXT:reaticulate assignment, user bank override, or matches track names (e.g. 'Violin I', 'Cello', 'Horns') to corresponding library banks. Users can also explicitly assign or switch any track's sound bank at any time via the 'Select Bank...' button in the Articulations Drawer (BankPickerModal).

### 6.2 Automatic Reaticulate.jsfx FX Slot 1 Setup & Bank Sync on New Tracks (v2.0.2+)

Functions & Zero-Configuration New Track Workflow:
- Automatic FX Verification & Insertion: When you create a brand-new track in REAPER (even one that only has a virtual instrument VSTi loaded or an empty FX chain) and select a bank in the Bank Picker—or apply any articulation from the Articulations Drawer / Sidebar—REAPER-Notator automatically checks the track's FX chain for 'JS:Reaticulate' (Reaticulate.jsfx). If missing, Notator automatically loads it onto the track via TrackFX_AddByName.
- Strict FX Slot 1 (Index 0) Placement Before Instrument VSTi: For Reaticulate to intercept Bank Select (CC0/CC32) and Program Change events and translate them into sampler keyswitches, Reaticulate.jsfx MUST sit in the very first FX slot (Slot 1 / index 0) prior to the virtual instrument (Kontakt, Sine, Opus, Play, VSL, etc.). If Reaticulate.jsfx is absent or positioned after an instrument plugin (slot > 0), REAPER-Notator automatically moves it to FX Slot 1 (index 0) via TrackFX_CopyToTrack(..., 0, true).
- Native P_EXT:reaticulate Track Metadata Sync: Selecting a bank or applying an articulation automatically writes the structured JSON bank configuration into the track's P_EXT:reaticulate extension state (preserving existing secondary banks or generating a valid RFC-4122 UUID v4 when needed) and triggers Reaticulate's live RFX sync so both the Reaticulate GUI and JSFX immediately activate the bank.
- Wildcard 'Bank * *' MSB/LSB Resolution & Allocation: Many custom user .reabank files define banks using wildcard headers ('Bank * * LibraryName') rather than hardcoded MSB/LSB numbers. REAPER-Notator automatically parses project-level MSB/LSB assignments from REAPER's REATICULATE bank_msblsb ExtState, or allocates deterministic Reaticulate-compatible CRC64 MSB/LSB numbers (CC0/CC32) and persists them to the project so Bank Select events are never skipped.

### 6.3 Visual Playing Technique Glyphs & Applying Articulations (Selected Notes & Edit Cursor)

Functions:
- Instant Playing Technique Palette: Provides an instant-access drawer and sidebar buttons for standard SMuFL glyphs and text playing techniques:
  * Staccato (dot), Staccatissimo (wedge), Accent (>), Marcato (^), Tenuto (-)
  * Legato, Long / Sustain, Pizzicato (pizz.), Arco, Con Sordino, Sul Ponticello, Sul Tasto, Col Legno, Tremolo, Trills, Harmonics / Flageolet (o)
- Standard Engraving Placement: Automatically positions articulation marks above noteheads for stems-down notes, or below noteheads for stems-up notes (with consistent beam-side alignment and staff-line avoidance).
- Applying to Selected Notes: When one or more notes are selected on the score canvas, clicking an articulation attaches the persistent REAPER Type 15 notation tag (`NOTE <pitch> <chan> a <art_name>`), writes the resolved MIDI CC0 (MSB), CC32 (LSB), and Program Change at the note onset, and schedules Auto-Chase return events.
- Applying at Edit Cursor (No Note Selection Needed, v2.0.2+): If no notes are currently selected, clicking an articulation in the Articulations Drawer automatically finds all notes on the active track/take at the current REAPER Edit Cursor position (cursor_qn), attaches the visual notation tag (`NOTE ... a ...`) directly to those notes, and inserts the corresponding CC0/CC32 Bank Select and Program Change events. If no note exists at the Edit Cursor, a standalone Program Change switch is inserted at the cursor position.
DAW Effect: Writes both persistent Type 15 score notation events and sample-accurate CC0/CC32 Bank Select + Program Change events into the REAPER MIDI take, immediately marking the item dirty and synchronizing open MIDI editors.

### 6.4 Momentary Articulations & Auto-Chase Return Engine

Functions & DAW Behavior:
- Momentary vs. Persistent Articulations: Playing techniques such as Staccato, Staccatissimo, and Accent are momentary by nature. Unlike persistent articulations (such as Arco, Tremolo, or Con Sordino) which remain active indefinitely until changed, momentary articulations only apply to their specific notes. After the passage ends, the instrument must automatically revert to its default playing patch (typically Long / Sustain).
- Automatic Chase Retrigger: When a momentary articulation is placed on notes, Notator automatically scans the passage, writes the corresponding Bank Select (CC0/CC32) and Program Change events at the note start positions, and places a dedicated Retrigger Chase event (`NOTATOR_CHASE` + base patch PC) at the exact end of the momentary passage (`last_momentary_end_ppq + 10`). This guarantees that subsequent unarticulated notes immediately trigger normal sustain without requiring manual keyswitch resets.
- Synchronized Note Deletion: If notes are deleted within or at the end of an articulated passage (for instance, deleting bars 6-10 of a 10-bar staccato phrase), Notator's deletion engine dynamically pulls the Chase Retrigger event back to the end of the remaining momentary notes (the end of bar 5) and removes all orphaned Program Change and chase events in the deleted bars. The remaining notes continue triggering staccato smoothly, while subsequent measures cleanly return to standard playback.
- Selective Articulation Removal: Clicking 'Remove Articulation' on selected notes strips the visual glyphs, Type 15 notation tags, and Program Change messages exclusively from those selected notes, preserving unaffected measures on the track intact.

### 6.5 Playback Troubleshooting & The 'Fix Playback' Engine (Selective vs. Global)

Functions, Tutorial Video & Playback Reconciliation Engine:
- Video Tutorial: For an in-depth video walkthrough of the Fix Playback, Ties, and Slurs features, watch the official tutorial:
    * 'Reaper-Notator - Infos about Fix Playback , Ties and Slurs function': https://youtu.be/ahpEfmgGb3M
- Dual Playback Fix Engine (Selective vs. Global):
    * 'Fix Playback (Selective)': Scans and reconciles STRICTLY the single selected MIDI item. The target item is resolved with prioritized accuracy: (1) item containing currently selected notes, (2) item box clicked in Notator canvas, (3) media item selected in REAPER's timeline, or (4) item under the edit cursor on the focused track. It repairs articulations, cleans foreign keyswitches, recalculates auto-chase return events, heals legacy hairpins, and auto-heals micro-overlaps strictly within the boundaries of that single item, guaranteeing that no other items on the track or elsewhere in the project are touched.
    * 'Fix Playback (Global)': Scans and reconciles ALL MIDI items across all tracks in the entire REAPER project. It iterates through every project track, reconciles note articulations with each track's respective Reaticulate bank, clears foreign or orphaned Program Changes, recalculates all auto-chase return points, and heals legacy dynamic hairpins project-wide. Ideal for refreshing entire multi-track arrangements or duplicated orchestral cues in one click.
- The Problem (Cross-Track Duplication Desync): In REAPER's arrange view, composers frequently duplicate or copy MIDI items across tracks (e.g. duplicating a violin phrase down to celli or double basses). When an item is copied in REAPER, REAPER duplicates the underlying MIDI events verbatim. However, different sample libraries or instrument sections utilize different Reaticulate sound banks (for example, a Violin bank might assign PC 40 to Short/Staccato, while a Celli or Double Bass bank might use PC 49 for Staccato Dig). Because the duplicated item retains the old track's Program Changes and old auto-chase markers, playback on the new track breaks, produces silent or mismatched samples, or becomes stuck in an unwanted articulation.
- The Solution ('Fix Playback' Engine): To resolve this without manual MIDI editing, REAPER-Notator provides automated playback reconciliation via the 'Fix Playback (Selective)' and 'Fix Playback (Global)' buttons in the Articulations drawer.
- Intelligent Re-Mapping: Fix Playback parses the persistent score notation markers (`NOTE <pitch> <chan> a <art_id>`), inspects the active track's Reaticulate bank, cleans out outdated or mismatched Program Changes from previous tracks, inserts the correct Bank Select and Program Change numbers for the current track's sound library, and re-calculates all auto-chase return events.
- Handling Unsupported Articulations (e.g. Library Lacks Staccato): If the destination track's instrument or Reaticulate bank does not provide the requested articulation (for example, duplicating a violin staccato passage onto a flute, piano, synth, or library that lacks dedicated short patches), Fix Playback completely purges all foreign Program Changes (such as 121-0-42) and Bank Selects (CC0 / CC32) across the take, removes unsupported notation tags, clears obsolete chase events, and ensures the track's default base patch (Long / Sustain) is engaged once at the passage start so the notes play cleanly without stuck keyswitches.
- Same-Pitch Legato Overlap Protection & Micro-Overlap Auto-Healing:
    * The Mechanism: Sampler legato libraries require a small overlap (~2 PPQ ticks) between notes of different pitches to trigger true acoustic legato interval transitions. In MIDI 1.0, two notes of the exact same pitch cannot overlap on the same channel without voice cancellation. If a slurred note was transposed to the same pitch as the preceding note, REAPER's native MIDI sort flagged the 2-tick overlap as invalid and deleted the second note.
    * Pre-Clamping on Note Entry & Transposition: Notator automatically clamps any preceding note tail bleeding into a new or transposed note's start position on the same pitch before MIDI_InsertNote and before MIDI_Sort.
    * Automated Micro-Overlap Healing: Both Selective and Global Fix Playback scan takes and automatically trim micro-overlaps (<= 15 ticks on identical pitches, and <= 5 ticks on different pitches without an active slur), repairing corruptions from older projects.
- Step-by-Step Workaround for Duplicated Items:
    1. Duplicate or paste the MIDI item onto a new track in REAPER's arrange view.
    2. Select the duplicated MIDI item or notes in REAPER-Notator.
    3. Open the Articulations drawer on the right sidebar.
    4. Left-click 'Fix Playback (Selective)' (or 'Fix Playback (Global)' for entire project).
    Playback immediately re-synchronizes to the destination track's virtual instrument bank with pristine staccato and sustain transitions.
- Dynamic Object Healing: Fix Playback also scans for legacy hairpins or dynamic text markings that were previously compressed or collapsed (<= 0.75 QN) by articulation collisions. It restores their natural musical span, re-resolves dynamic continuity across the track, and regenerates uninterrupted CC curves.
- Idempotency & Safe Multi-Click: The Fix Playback command is fully idempotent. If playback is already synchronized, repeating the click will never inadvertently erase or corrupt existing articulations.
- Fix of Last Resort (Emergency Articulation Reset):
    * Right-Click Access: Right-clicking 'Fix Playback (Selective)' (or clicking again when already in sync) opens the dedicated 'Fix Playback: Fix of Last Resort' confirmation modal window, centered over the active score display.
    * Target Confirmation: The modal clearly displays the target item and track name and confirms that note articulations currently match the active instrument sound bank.
    * Emergency Reset Action: If playback remains stuck, silent, or corrupted by external MIDI CC messages, clicking the red button '[ Purge All Articulations (Last Resort) ]' completely strips all articulation glyphs, Type 15 notation tags (`NOTE <pitch> <chan> a <art_id>`), Bank Selects (CC0 / CC32), keyswitch Program Changes, and auto-chase return events (`NOTATOR_CHASE`). It then re-engages the default base patch (Long / Sustain) at the item start, resetting the item to clean default sustain playback.
    * Safe Cancellation: Clicking '[ Cancel (Keep Articulations) ]' or pressing Escape immediately dismisses the modal without altering any notes, articulations, or MIDI events.

### 6.6 Slurs (Legato Phrase Marks) & Ties (Held Notes)

Functions, Workflow Architecture & DAW Engine:
- Video Tutorial: Watch the official video guide for practical examples of Ties and Slurs:
    * 'Reaper-Notator - Infos about Fix Playback , Ties and Slurs function': https://youtu.be/ahpEfmgGb3M
```
+-------------------------------------------------------------+
|                     SELECTION WORKFLOW                      |
|  - 2+ Notes Selected: Melodic phrase N1 .. Nk (all notes)   |
|  - 1 Note Selected: N1 -> Auto-connects next note (N2)      |
+------------------------------+------------------------------+
                               |                               
               +---------------+---------------+               
               |                               |               
               v                               v               
+-----------------------------+ +-----------------------------+
|          SLUR (S)           | |           TIE (T)           |
|      Different Pitches      | |       Identical Pitch       |
|      (Melodic Phrasing)     | |     (Duration Addition)     |
+-----------------------------+ +-----------------------------+
               |                               |               
               v                               v               
+-----------------------------+ +-----------------------------+
|    PLAYBACK & AUTOMATION    | |      SCORE & ENGRAVING      |
| - Pre-Slur Articulation:    | | - Both original noteheads   |
|   Detects active patch      | |   remain visible on canvas  |
|   (e.g. Tremolo PC/Bank)    | |   (e.g. 2 Half Notes stay;  |
| - Intelligent Patch Match:  | |   NEVER merged to whole!)   |
|   * Has Legato -> Legato PC | | - Engraver tie curve        |
|   * No Legato  -> Long/     | |   (Cubic Bezier arch per    |
|     Sustain Fallback Patch  | |   Gould / Read stem rules)  |
| - Phrasing Overlap:         | +-----------------------------+
|   Seamless overlap between  |                |               
|   all steps (Ni -> Ni+1)    |                v               
| - Auto-Chase Return Engine: | +-----------------------------+
|   At phrase end (Nk),       | |       MIDI TAKE ENGINE      |
|   automatically returns to  | | - Note 1 sustained to end   |
|   pre-slur articulation     | |   of Note 2 for continuity  |
|   (Tremolo restored!)       | | - Note 2 deleted from take  |
| - Smooth Bezier phrase arch | |   (zero second-note strike) |
|   rendered on score canvas  | | - Virtual Note 2 on canvas  |
+-----------------------------+ +-----------------------------+
               |                               |               
               +---------------+---------------+               
                               |                               
                               v                               
+-------------------------------------------------------------+
|                RESIDUE-FREE REMOVAL & TOGGLE                |
|  - Direct Canvas Click: Click curve to select (gold highlight)|
|  - Key [Delete] / [Backspace] removes selected slur or tie  |
|  - Key S or T (Toggle Off) / 'Remove Slur/Tie'              |
|  - Slur: Legato/Long PC removed, Auto-Chase resynchronized  |
|  - Slur Cleanup: All micro-legato overlap remnants clamped  |
|  - Tie: Note 1 length restored, Note 2 re-inserted in take  |
|  - Type 15 tags purged; zero orphaned MIDI events left      |
+-------------------------------------------------------------+
```
- Musical Distinction (Slur vs. Tie):
    * Tie (Haltebogen): Exclusively connects notes of the IDENTICAL pitch. A tie performs mathematical duration addition (e.g. tying a half note to a quarter note produces a sounding duration of 3 beats). The tone sounds upon the initial attack and is held continuously; the second note is never struck again. Ties are standardly employed to cross barlines or metric half-measure divisions where single notes cannot legally be notated.
    * Slur (Bindebogen / Legato): Connects notes of DIFFERENT pitches. A slur signifies that all notes within the marked phrase must be performed legato (smoothly connected without re-articulation or rhythmic separation between pitches).
- Interactive Selection & Multi-Note Phrasing Workflow:
    * Sidebar Access: Located in the dedicated 'SLURS & TIES' section between Articulations and Transpose on the main sidebar, as well as in the Articulations drawer.
    * Direct Canvas Hit-Testing: Slurs and ties can be clicked directly on the score canvas. Clicking a curve highlights it in bright gold (#FFD700), and pressing the Delete or Backspace key immediately removes the slur or tie.
    * 2 Notes Selected: Pressing 'S' or clicking 'Slur [S]' immediately connects Note 1 to Note 2. Pressing 'T' or clicking 'Tie [T]' verifies pitch equality and ties them.
    * Multi-Note Selection (3+ Notes): Pressing 'S' or clicking 'Slur [S]' creates an expressive phrase slur spanning from N1 to Nk, incorporating all intermediate notes on that track and channel.
    * 1 Note Selected: Pressing 'S' or clicking 'Slur [S]' automatically identifies the next chronological note on that track and creates the slur. Pressing 'T' or clicking 'Tie [T]' searches for the next chronological note sharing the identical pitch and ties them.
    * Pitch Protection Guard: If 'Tie [T]' is clicked with notes of different pitches, Notator prevents an invalid tie and displays an advisory notification: 'Tie requires notes of the same pitch! Use Slur [S] for melodic phrases.'
- Haltebogen / Tie Engine & Dual Reality Architecture:
    * Notehead Preservation (No Collapsing): Both original noteheads and stems (e.g. two separate half notes) remain permanently visible and correctly positioned on the score canvas per Elaine Gould and Gardner Read engraving standards. They are NEVER collapsed or merged into a single whole note or altered note value.
    * Score Engraver Tie Arch: A smooth cubic Bezier tie curve (Engraver.draw_tie) connects the noteheads, positioned per engraving standards opposite stems (below noteheads for stems-up notes, above noteheads for stems-down notes).
    * Dual Reality MIDI Architecture: In REAPER's underlying MIDI take, Note 1 is extended through the end of Note 2 for uninterrupted sounding sustain, and Note 2 is deleted from the take via MIDI_DeleteNote to completely eliminate secondary audio re-strikes. On the score canvas, Note 2 is losslessly synthesized from Type 15 notation tags (NOTATOR_TIE / NOTATOR_TIE_SLAVE), ensuring perfect visual score fidelity across measures and barlines.
    * REAPER Editor Synchronization: Every tie creation or deletion instantly triggers reaper.MarkTrackItemsDirty and reaper.MIDIEditor_OnCommand(40435), ensuring open REAPER Piano Roll editors synchronize immediately without manual window refresh.
- Melodic Slur Phrasing, Same-Pitch Protection & Articulation Return Engine:
    * Pre-Slur Articulation Memory: Before applying a slur, Notator scans active take events to record the current playing technique (e.g. Tremolo PC, MSB, LSB).
    * Intelligent Patch Match with 'Long' / Sustain Fallback: When a slur starts, Notator queries the instrument's Reaticulate sound bank for a dedicated legato or slur patch. If the instrument library lacks an explicit legato articulation, Notator automatically falls back to long / sustain. This guarantees that the instrument cleanly transitions out of Tremolo (or other previous techniques) instead of remaining stuck in Tremolo.
    * Same-Pitch Overlap Protection: To trigger true acoustic legato intervals in VST libraries, slurring notes of different pitches creates a 2-PPQ overlap. However, if consecutive notes share the exact same pitch, Notator strictly prohibits overlap (capping at next_sppq - 1), preventing REAPER from destructively merging identical pitch notes.
    * Gunshot Bug Protection: Re-engineered auto-chase routines enforce strict range checks (0 <= pc <= 127). If an item has no previous articulation (pre_slur_pc = -1), Notator strictly avoids sending negative program change bytes, preventing the unintended playback of General MIDI Patch 127 ('Gunshot').
    * Dynamic Auto-Chase Return Engine: At the exact conclusion of the slur phrase (Nk), the auto-chase engine immediately sends a return Bank Select and Program Change restoring the pre-slur articulation (e.g. automatically resuming Tremolo without composer intervention).
- Residue-Free Removal & Toggle:
    * Toggling 'Slur [S]' or 'Tie [T]' on an already slurred/tied note (or hitting Delete on a selected curve) removes the curve, restores Note 1's original duration, re-inserts Note 2 into the MIDI take, deletes Legato/Long Program Changes, and cleans all Auto-Chase return events with zero orphaned MIDI data.
    * Automatic Legato Overlap Trimming: When a slur is deleted, Notator automatically scans all phrase notes and clamps any residual micro-legato overlap extensions (<= 10 ticks) back to note boundary, preventing note erasing when subsequently transposing adjacent notes to identical pitch.

---

## Chapter 7: Holding & Sustain Pedal Lane (CC64)

### 7.1 Dedicated Pedal Lane

Functions: Renders continuous piano sustain pedal markings positioned below the bass staff with automatic collision clearance from low notes and dynamic hairpins.

### 7.2 Three Historical Engraving Styles

Functions:
- Classic: Ped. symbol at start, dashed horizontal line, and asterisk (*) at release.
- Bracket: Modern square brackets (|---|) with vertical hooks.
- Notch / Mixed: Combines Ped. marking with inverted 'V' notches for continuous pedal retakes.

### 7.3 Dual Handles & Pause / Break Retakes

Functions:
- Start & End Handles: Drag circular handles to adjust pedal engage and release times.
- Pause / Retake Points: Right-click on the pedal line to insert pedal breaks (quick release and re-engage) without creating multiple separate items.
DAW Effect: Writes CC64 value 127 at engage, momentary 0 at retakes, and 0 at final release.

---

## Chapter 8: Tempo Maps & Metric Transitions

### 8.1 Absolute Tempo Markers

Functions: Insert tempo markers with custom BPM values (e.g. Quarter = 120, Dotted Quarter = 72) and descriptive Italian tempo text (Adagio, Andante, Allegro, Presto).
DAW Effect: Inserts a master tempo marker directly into REAPER's timeline tempo envelope.

### 8.2 Gradual Transitions (Accelerando / Ritardando)

Functions: Renders dashed tempo transition lines spanning multiple measures (e.g. 'poco a poco accel. ------').
DAW Effect: Generates a continuous gradual tempo ramp in REAPER, smoothly accelerating or decelerating project playback speed.

### 8.3 Direct Double-Click BPM Editing & Glyphs

Functions:
- Double-Click Inline Editing: Double-clicking any tempo marker opens an instantaneous popup editor with automatic keyboard focus on the numeric BPM input.
- Standard Unicode Note Symbol: Renders the classical quarter-note symbol (♩, U+2669) in non-bold regular weight according to professional music engraving standards.
DAW Effect: Updates REAPER tempo markers in real time with immediate timeline synchronization.

---

## Chapter 9: Octave Shift Lines (8va, 8vb, 15ma, 15mb)

### 9.1 Visual Score Simplification

Functions: For extreme high or low passages that would otherwise require excessive ledger lines, octave shift lines simplify score reading:
- 8va (Ottava Alta): Notes sound 1 octave higher than written.
- 8vb (Ottava Bassa): Notes sound 1 octave lower than written.
- 15ma (Quindicesima Alta): Notes sound 2 octaves higher.
- 15mb (Quindicesima Bassa): Notes sound 2 octaves lower.

### 9.2 Visual vs. Sounding Pitch

DAW Effect: Notes remain in their natural visual position on the staff for effortless reading, while underlying MIDI note pitches trigger the intended high or low acoustic octaves.

---

## Chapter 10: Orchestral Pattern Browser & 1-Click Library

### 10.1 Curated 1,200 Pattern Factory Library

Functions: Slide-out pattern browser organized into 8 orchestral categories (1,200 factory patterns total):
- 1. Strings Staccato (150x driving cinema pulses, ostinatos)
- 2. Strings Pizzicato (150x delicate plucks, agile grooves)
- 3. Brass Blockbuster (150x epic horn fanfares, low brass power)
- 4. Cinematic Melodies (150x soaring lyrical themes)
- 5. Counter Melodies (150x rich orchestral counterpoint)
- 6. Woodwinds Textures (150x runs, fluttering textures)
- 7. Cinematic Piano (150x flowing arpeggios, grand staff ballads)
- 8. Ancient Greek & Roman Harp (150x modal hymns, Delphic paeans, Sapphic strophes, Dorian/Phrygian/Lydian processions)
- 9. Custom User Patterns (user-captured motifs and items)

### 10.2 One-Click Insertion, Drag & Drop & Audio Audition

Functions:
- Drag & Drop: Drag any pattern tile directly onto the score canvas with golden ghost-preview.
- Audio Audition: Audition motifs in real-time through any selected REAPER instrument track.
- Capture Selection: Select any REAPER MIDI item and click 'Capture REAPER Item' to store it permanently.

### 10.3 In-App 1-Click Factory Library Downloader

Functions: Integrated one-click downloader built into the browser toolbar and empty-state banner.
- 1-Click Install: Downloads and unpacks the entire 1,200 pattern library (820 KB compressed) in one second without leaving REAPER.
- Offline Archive Support: Automatically unpacks local patterns.zip on first launch if present.

---

## Chapter 11: Rehearsal Marks, Fermatas & Score Tools

### 11.1 Dynamic & Custom Rehearsal Marks, Inline Renaming & Live Shortcut (Ctrl+M)

Functions: Professional structural navigation, custom section markers, and rehearsal tagging:
- Dedicated Rehearsal Lane: Positioned cleanly between the Chord Track lane and Bar Numbers, providing unobstructed structural visibility across all systems.
- Interactive Mouse Drag & Drop: Click and drag any rehearsal mark directly along the top lane to move it to any measure or grid beat. Custom Markers and Navigation Marks (e.g. 'D.C.', 'D.C. al Fine') permanently retain their custom label across moves with dynamic badge hitboxes.
- Auto-Sequencing: Standard marks automatically sequence as [A], [B], [C]... or [1], [2], [3]... Moving or inserting standard marks chronologically re-indexes all subsequent standard marks across the score.
- Inline Double-Click Renaming & Auto-Sequence Exclusion (v2.0+): Double-clicking any Rehearsal Mark on the score canvas (or choosing 'Rename Mark' in the right-click context menu / Tools Drawer) opens an inline rename box. Renaming any mark locks it as a Custom Marker and automatically excludes it from the A, B, C... / 1, 2, 3... counting sequence.
- Live & Stopped Custom Marker Shortcut ('Ctrl+M', v2.0+): Pressing Ctrl+M (configurable in Settings -> Shortcuts) places sequential default custom markers ('Marker 1', 'Marker 2', 'Marker 3'...) at the exact Playhead position during live Playback or Recording (snapped to the active Notation Grid), or at the Edit Cursor when stopped.
- Edit-Cursor Placement: The Tools Drawer dynamically detects the active REAPER edit cursor position, displaying explicit actions like 'Add Letter Mark at Bar X', 'Add Number Mark at Bar X', and 'Add Custom Marker at Bar X'.
- Classical Navigation Symbols: Immediate one-click placement of Da Capo (D.C.), D.C. al Fine, Dal Segno (D.S.), D.S. al Coda, Segno, Coda, and Fine marks.
- Inverted Engraving Typography: Styled according to classical engraving rules with a crisp paper background, 2px dark border, and high-contrast dark typography.
- Settings & View Options: Configurable vertical Y-offset slider in Settings and a show/hide toggle in the View dropdown.

### 11.2 Score-Wide Vertical Fermatas

Functions: Classical pause and hold articulation across all staves:
- Four Engraving Types: Standard fermata, Short fermata (triangle/fermata corta), Long fermata (square/fermata lunga), and Very Long fermata.
- Full-Score Clickability: Fermatas can be clicked, selected, and edited on any staff across the entire vertical score system, not just the top staff.
- Tempomap Playback Coupling: Non-destructive tempo slowdown dip (1.25x to 3.0x multiplier) with automatic restoration at the release point.
- Keyboard Delete Support: Select any fermata or rehearsal mark and press Delete or Backspace to instantly remove it.

### 11.3 Score Tools Drawer & Performance Transformations

Functions: Fast editing actions consolidated in the right-hand Tools drawer:
- Make Notes Legato: Extends note durations to adjacent note downbeats for seamless cantabile phrasing.
- Auto Voice & Auto Voice on Selection: Polyphonic splitting of selected chords into upper Voice 1 (stems up) and lower Voice 2 (stems down).
- Filter Irregular Notes: Dedicated cleaning and reorganization tool for humanized and live-recorded MIDI tracks. Accurately identifies notes whose onset times deviate from standard metric divisions (whole to 32nd notes, with optional triplet support) outside a configurable tick tolerance. Includes real-time yellow canvas highlighting, regular-note dimming/ghosting, and dual actions: non-destructive note selection or reassignment to a target voice (e.g. Voice 16).
- Divisio Vocum (Voice Distribution): Distributes multi-voice chords from a single track vertically across the visible tracks displayed below in the score viewport (e.g. from Violin 1 down through Contrabass). Features an interactive context modal with live routing preview, target voice count (2-16), chord detection tolerance (5-100 ms), and bass voice gap-filling.
- Arpeggio Strums: Realistic harp, guitar, and piano roll simulation. In accordance with classical music engraving standards, noteheads remain strictly vertically aligned on the chord downbeat under a single unified stem, while a wavy arpeggio line is engraved to the left with automatic clearance for accidentals. Playback micro-strumming adaptively scales with note length (e.g. 8-16 ticks for 16th notes up to 30 ticks for sustained chords) to prevent beat spillover, and 'Snap to Grid / Remove Arpeggio' instantly restores notes to the chord downbeat.
- Quantize Tools: Integrated triplet, swing, and 1/4 through 1/64 grid snapping directly inside the Tools drawer.

### 11.4 Divisio Vocum (Orchestral Voice Distribution / Explode Chords)

Overview & Musical Concept:
Divisio Vocum (classical Latin for 'voice division') is an intelligent orchestral arranging service implemented in modules/services/divisio_vocum_service.lua with UI modal modules/ui/divisio_vocum_modal.lua. It takes multi-voice chords played or sketched on a single track (such as an ensemble piano reduction, string sketch, or brass fanfare on Violin 1) and distributes the individual polyphonic voices vertically across the active tracks displayed in the score viewport below (for example: distributing a 5-voice chord from Track 1 across Violin 1, Violin 2, Viola, Cello, and Contrabass).

How to Access the Tool:
- Method 1 (Score Tools Drawer): Open the right-hand Tools drawer and click 'Divisio Vocum...'.
- Method 2 (Canvas Context Menu): Right-click on any selected notehead or empty measure on the score canvas and select 'Divisio Vocum...' from the context menu.

Interactive Dialog Controls & Features:
- Source Track Detection: The service automatically identifies the source track based on the current note selection, focused track, or the uppermost visible viewport track.
- Target Tracks / Voices (2 to 16): An interactive slider to configure how many target tracks and polyphonic voices will receive notes. Defaults to 5 tracks.
- 'Match Viewport' One-Click Button: Automatically queries the number of active tracks currently visible in your score canvas and synchronizes the target voice count to match them in a single click.
- Live Routing Breakdown (Interactive Preview Table): Shows an immediate breakdown of voice routing before applying changes:
  * Voice 1 (Top / Highest Pitch): Retained directly on the source track (e.g. Violin 1 / Soprano lead).
  * Voice 2 (Upper Middle): Routed to Track 2 below.
  * Voice 3 (Middle): Routed to Track 3 below.
  * Voice 4 (Lower Middle): Routed to Track 4 below.
  * Voice 5..N (Bass / Lowest Pitch): Routed to Track 5 and subsequent lower tracks (e.g. Celli and Contrabasses).
- Chord Detection Tolerance (5 ms to 100 ms, default 25 ms): Configures the time window used to group notes into vertical chords. Notes played on MIDI keyboards with slight live humanization are clustered accurately into cohesive vertical chords.
- Pad / Double Bass Voice in Lower Tracks (Gap-Fill): When active, chords with fewer notes than target tracks (e.g. a 3-note triad distributed over 5 orchestral tracks) automatically double the lowest root/bass note into the remaining bottom tracks (e.g. Celli and Contrabass both receive the bass note). When unchecked, lower tracks remain empty for sparse chords.
- Scope Selection: Choose between 'Selected Chords' (restricting the operation strictly to currently selected notes) and 'All Chords on Track / Item'.

DAW Execution, Articulation & Sound Bank Bridging:
- Clean Voice Extraction: Distributed secondary voices (Voice 2..N) are seamlessly moved to the destination tracks at their exact Quarter-Note positions and durations, while the source track cleanly retains only Voice 1 without duplicate note clutter.
- Intelligent Articulation & Reaticulate Bridging: Preserves SMuFL note-level articulations (Staccato, Accent, Tenuto, Marcato, etc.) and queries each destination track's Reaticulate sound bank to output the corresponding Bank Select (CC0/CC32) and Program Change events tailored to each instrument.
- Transactional Undo Safety: The entire multi-track distribution operation is enclosed in a single REAPER undo transaction (Undo_BeginBlock2), ensuring immediate, complete rollback with Ctrl+Z.

### 11.5 Filter Irregular Notes (Humanized & Live-Recorded MIDI Cleaner)

Musical Concept & Background:
Live-recorded MIDI keyboard performances and humanized takes inherently feature subtle micro-timing variations. Filter Irregular Notes analyzes note onset positions relative to the musical meter, flags notes that deviate from standard metric subdivisions outside a user-defined tick tolerance, renders a live gold/yellow (#FFD700) preview on the score canvas, and allows you to either select them for manual inspection or reassign them cleanly into a secondary background voice (default Voice 16 / MIDI channel 15).

Interactive Dialog Controls & Features:
- Tolerance Slider (0 to 50 Ticks): Determines how many MIDI ticks of micro-timing deviation are permitted before a note is treated as irregular (with a sub-tick float epsilon < 0.05 ticks at 0 tolerance).
- Include Triplets Checkbox: Tests compound/triplet subdivisions (1/12, 1/24, 1/48) in addition to binary subdivisions (1/1 through 1/32).
- Target Voice Selector (Voice 1 through Voice 16): Chooses the destination voice when reassigning irregular notes (defaults to Voice 16).
- Processing Scope: Choose between Entire Project, Active Track, Selected Media Items, or Selected Notes Only.
- Live Canvas Yellow Preview & Regular Note Ghosting: Highlights matching irregular notes in vivid yellow on the score canvas in real time and optionally dims/ghosts regular notes.
- Dual Execution Actions: 'Select Notes' (non-destructively selects irregular notes for inspection) and 'Reassign to Voice' (moves irregular notes to the target voice within a single REAPER undo transaction).

### 11.6 Floating Text Items & In-Place Editing

Functions: Pressing Ctrl+T inserts a floating score text item at the cursor. Double-click any text item to open an in-place editing field. Configure font size, standard/italic/bold styling, and staff attachment anchor points.

---

## Chapter 12: MusicXML 4.0 Import & Export

### 12.1 Interoperability Standard

Functions: MusicXML 4.0 is the universal interchange format between professional notation software. REAPER-Notator includes a dedicated MusicXML parser and exporter written in pure Lua.

### 12.2 Importing Scores & Articulation Auto-Mapping

Functions:
- Orchestral Score Import: Click 'Import MusicXML' to load orchestral scores created in external notation programs. Notator parses parts, measures, time signatures, key signatures, pitch data, dynamics, lyrics, and tempo markers, creating fully arranged tracks and MIDI items directly in REAPER.
- Intelligent Articulation Detection: Automatically analyzes Reaticulate sound banks loaded on destination tracks. Employs a prioritized 3-tier mapping algorithm for articulations (e.g. prioritizing dedicated 'Staccato Dig' patches for Spitfire Double Basses over fallback 'Short 0.5' duration patches).
- Compact Track Layout: Automatically collapses imported track heights (25px) to provide an immediate, organized orchestral overview without overwhelming the REAPER track arrangement.

### 12.3 Exporting Scores

Functions: Click 'Export MusicXML' to save your REAPER project as a standard .musicxml file ready for publication, live orchestral recording sessions, or further engraving.

---

## Chapter 13: Score Clipboard & Selective Copy/Paste Engine

### 13.1 Selective Note & Score Clipboard

Functions: High-precision clipboard operations (Ctrl+C / Ctrl+V) with strict element isolation:
- Selective Note Copying: When copying selected notes, the clipboard selectively captures notes, chords, and explicit note articulations (staccato, accent, tenuto, fermatas) without inadvertently dragging along unselected dynamics, hairpins, pedal lines, or tempo markers.
- Context-Aware Pasting & Range Overwrite: Pasting notes into a MIDI item (Ctrl+V) performs an intelligent range overwrite. Preexisting notes, notation text events, Program Changes, and obsolete chase events falling within the pasted time window `[target_start_qn, target_start_qn + total_dur_qn]` are cleanly replaced. Notes crossing the paste boundaries are cleanly truncated without overlapping voice collisions. Following the paste, Notator immediately recalculates and positions the Auto-Chase return events to preserve seamless articulation transitions.
- Independent Element Duplication: Dynamics, hairpins, and pedal lines can also be copied and pasted independently, ensuring modular workflow efficiency.

### 13.2 Quantization & Sub-Tick Boundary Alignment

Functions: Precision alignment engine across copy/paste and editing routines:
- PPQ Temporal Integrity: Pasted notes maintain exact sub-tick delta relationships relative to the edit cursor.
- Track-Targeting: Clipboard contents paste directly into the active or focused track, enabling rapid passage duplication across orchestral sections.

---

## Chapter 14: Engine Architecture & Performance Optimization

### 14.1 High-Efficiency O(1) Project State Caching

Functions:
- Project State Guard: Monitors reaper.GetProjectStateChangeCount(0) to eliminate thousands of redundant C-API queries during playback and idle, reducing C-API calls to 0 when the score is static.
- Text Size Memoization: Caches ImGui font measurement dimensions to eliminate repeated layout calculation storms.
- ReaImGui Context Validation: Strict pointer validation guarantees rock-solid stability during project switching and window operations.

### 14.2 Hardware-Accelerated Vector Graphics

Functions:
- Pure GPU-Rasterized Drawing: ReaImGui dispatches all vector paths, noteheads, and beams directly to DirectX 11 / OpenGL / Vulkan.
- Optimized Beam Meshing: Eliminated redundant contour stroking on filled polygons, reducing vertex count by 60% and halving C-API call overhead.

### 14.3 Playback Editing Query Bypass (60-70+ FPS on 30+ Tracks)

Functions:
- Zero-Latency Playback Pipeline: During active timeline playback, all mouse hover checks, ghost note previews, drag evaluations, Take C-API queries, and redundant track state scans are completely bypassed.
- In-Memory Layout Cache: Visual notes, stems, beams, and collision avoidance tables are precomputed once into an ultra-fast layout cache, rendering notes directly from memory with zero table allocations per frame.
- High Track Count Scalability: Delivers stable 60-70+ FPS playback on complex symphonic projects exceeding 30 tracks and thousands of active notes.

### 14.4 Viewport Frustum Culling & Coordinate Invalidation

Functions:
- 2D Frustum Culling: Bypasses drawing calculations for staves, notes, slurs, glissandi, and dynamic markings located outside the visible screen viewport.
- Strict Coordinate Invalidation: Off-screen notes in the layout cache have their visual coordinates explicitly set to -999999, preventing stale stems, beams, or barlines from rendering when rapidly scrolling or jumping via auto-scroll.

### 14.5 Same-Frame Auto-Scroll Re-anchoring

Functions:
- Zero-Latency Viewport Tracking: When follow-playhead (Auto-Scroll) triggers SetScrollX, the canvas origin, margin offsets, and measure position maps are re-anchored immediately within the exact same frame, eliminating single-frame desynchronization and visual jitter.
- Stopped-State Auto-Scroll Decoupling: While playback is stopped, auto-scroll is decoupled from manual canvas navigation, re-centering only when REAPER's edit cursor is explicitly relocated externally.

---

## Chapter 15: Integrated Multi-Lane MIDI Editor

### 15.1 Architecture & Synchronized Workflow

Functions:
- Docked Bottom Drawer: The Integrated MIDI Editor lives in a collapsible drawer docked directly beneath the score canvas, toggled via the bottom utility bar.
- Bidirectional Take Synchronization: Any edits made on the notation canvas instantly update the MIDI Editor timeline, and adjustments to velocities or CC nodes immediately write to REAPER's active MIDI take.
- Standalone Reference Guide: For an exhaustive guide, see the dedicated standalone documentation at docs/midi_editor_manual.md.

### 15.2 Note Velocity Lane & REAPER Flag Handles

Functions:
- Velocity Stalks with Flags: Note velocities (1 to 127) are represented as vertical stalks with interactive top handles ('Fahnchen') styled after REAPER's native MIDI editor.
- Interactive Audition Drag: Clicking and vertically dragging any flag handle adjusts the note velocity in real time, accompanied by zero-latency acoustic preview sound reflecting the new velocity level.
- Pencil Draw Tool: Activating the Draw tool (pencil cursor) allows sweeping across the lane to paint freehand velocity curves across consecutive notes.
- Dynamic Velocity Presets: Instant one-click quantization buttons for pp (32), mp (64), mf (80), f (96), and ff (112) applied to selected notes or all notes.
- Linear Ramp & Humanize: 'Ramp' generates a smooth linear velocity progression between selected notes, while 'Humanize' applies natural acoustic micro-variations (+/- 7).

### 15.3 128 Continuous Controller Lanes & Linear Ramping

Functions:
- Complete 128 CC Controller Support: Edit Modulation (CC 1), Breath (CC 2), Volume (CC 7), Pan (CC 10), Expression (CC 11), Sustain Pedal (CC 64), and any other standard MIDI controller (CC 0 to 127).
- Freehand CC Curve Drawing: Paint smooth continuous automation curves with real-time vector pencil feedback.
- REAPER CC Curve Shapes: Fully integrated with REAPER's envelope shapes (Linear Ramp default, Square Step, Slow Start/End S-Curve, Fast Start, Fast End, and Bezier), eliminating ugly staircase steps ('Treppenstufen').
- Convert All to Linear: One-click batch conversion command that scans the active CC lane and transforms legacy step events into smooth linear ramps.
- Level Stamps & Purge: Instant level buttons (0, 32, 64, 96, 127) to stamp constant values across the item, and 'Clear CC' to purge the lane.

### 15.4 Dynamic CC Shaping Protection & Bypass Lock

Functions:
- Orchestral Dynamics Protection: When automated score dynamics (hairpins, swell curves) are controlling CC 1 (Modulation) or CC 11 (Expression), these lanes are automatically locked to prevent accidental pencil overwrites.
- Visual Lock Status: The lane header displays a red padlock indicator ('[Locked] CC Locked (Dynamic Shaping)').
- 1-Click Unlock / Bypass: Clicking 'Unlock (Enable Bypass)' immediately decouples the active item from automated shaping, giving full manual control over the CC curve.

---

## Chapter 16: Modernized Interface & Performance Settings

### 16.1 Target Framerate (FPS) Configuration

Functions:
- Configurable Target FPS: Located in Settings -> General Settings, allowing users to tailor GUI performance to their hardware.
- Selectable Presets: 15 FPS (Ultra Power Saver), 30 FPS (Power Saver / Large Scores), 60 FPS (Default / Standard Smooth), 90 FPS (High-Refresh), 120 FPS (High-Refresh Pro), 144 FPS (Ultra-High Refresh), and Uncapped / Native Host Rate (VSync).
- Live Real-Time FPS Meter: Displays real-time rendering framerate ('Live: XX.X FPS') to evaluate GPU load.

### 16.2 Hardware Vector Line Anti-Aliasing

Functions:
- Dear ImGui Anti-Aliasing Toggle: Controls subpixel edge smoothing on vector lines and polygons.
- High-Performance Mode (Unchecked - Recommended): Delivers pure zero-overhead rasterization for massive 30+ track orchestral scores.
- Smooth Line AA Mode (Checked): Enables alpha-gradient edge anti-aliasing on stems, beams, and staff lines.
- Font Atlas Independence: Noteheads, accidentals, clefs, numbers, and rehearsal marks are rendered via high-resolution font texture atlases and remain ultra-smooth in all modes.

### 16.3 Undo Depth Limit & Memory Management

Functions:
- Max Undo Steps Slider: Restricts consecutive undo history depth (0 to 200, default: 50). Prevents continuous CC/velocity pencil drawing from ballooning project RAM and slowing REAPER state serialization.
- Clear Project Undo History: Dedicated button ('Clear Project Undo History') that purges accumulated project undo history on demand and reclaims RAM.

### 16.4 View Navigation & Mouse Engine

Functions:
- Ergonomic Input Mapping: Full customization of keyboard modifiers (None, Shift, Ctrl, Alt, Space, combinations) and mouse triggers (Mouse Wheel Vertical/Horizontal, Middle Mouse, Right Mouse, Left Mouse).
- Controllable Actions: Independently configure Horizontal View Scroll, Vertical View Scroll, Canvas Pan (Hand-Tool), and Canvas Zoom (In/Out).
- Speed & Inversion Sliders: Fine-tune horizontal and vertical scroll speed multipliers (0.5x to 5.0x) with independent 'Invert Horizontal Direction' and 'Invert Vertical Direction' checkboxes.
- One-Click Reset: 'Reset Navigation Defaults' restores standard navigation configuration instantly.

### 16.5 MIDI Editor & Score Color Themes

Functions:
- Dedicated Palette Customization: Settings -> MIDI Editor Colors enables full aesthetic customization of background, lane fills, grid lines, velocity stalks/flags, selection tints, and CC curves.
- Dark Mode & Invert Contrast: Handcrafted contrast adaptations for score paper, staves, barlines, and rehearsal boxes.

---

## Chapter 17: Keyboard Shortcuts & Quick Reference

### 17.1 Comprehensive Hotkey Matrix

Quick reference table for high-speed score entry, MIDI editing, and viewport navigation:

| Key / Shortcut | Action | Description |
| :--- | :--- | :--- |
| Space | Play / Pause | Starts or stops timeline playback |
| Record Button (Left/Right Click) | Record / Record Settings | Left-click starts/stops MIDI recording; Right-click opens Record & Auto-Quantize Modal |
| Ctrl + M | Add Custom Marker | Places sequential Custom Rehearsal Marker live at Playhead or at Edit Cursor |
| F11 / Maximize Button | Maximize / Restore | 2-step full-monitor work area maximize and centered floating restore |
| Delete / Backspace | Delete | Deletes selected notes, dynamics, tempo marks, or lines |
| Esc | Clear Selection | Deselects all active items and clears focus |
| Up / Down Arrows | Transpose Pitch | Moves selected notes up/down by 1 semitone |
| Shift + Up / Down | Octave Shift | Moves selected notes up/down by 1 octave (12 semitones) |
| Left / Right Arrows | Nudge Position | Shifts notes horizontally by the active grid increment |
| Shift + Left / Right | Resize Duration | Shortens or lengthens selected notes by grid step |
| Alt + Left / Right | Select Note | Navigates to previous / next note on timeline without mouse usage |
| Alt + Shift + Left / Right | Expand Selection | Expands multi-note selection along the timeline |
| X | Invert Stem | Flips note stem direction (up <-> down) |
| 1 .. 6 | Rhythmic Values | 1=Whole, 2=Half, 3=Quarter, 4=Eighth, 5=16th, 6=32nd |
| Ctrl + 1 .. 7 | Grid Snap Settings | Sets score grid: Ctrl+7=1/1, Ctrl+6=1/2, Ctrl+5=1/4, Ctrl+4=1/8, Ctrl+3=1/16, Ctrl+2=1/32, Ctrl+1=Free |
| Ctrl + K / 🔗 Button | Grid & Note Sync | Links Note Duration and Grid so changing one automatically updates the other |
| . (Period) | Toggle Dot | Toggles dotted note duration (1.5x) |
| - / 0 / = | Accidentals | -=Flat (b), 0=Natural (nat), ==Sharp (#) |
| S | Slur / Legato ([Slur]) | Toggles musical legato slur over 2 notes (or note to next); engages Legato keyswitch |
| T | Tie / Haltebogen ([Tie]) | Toggles tie between 2 notes of identical pitch (duration sum without second note attack) |
| A | Accent | Toggles accent mark (>) on selected note |
| Ctrl + T | New Text Item | Creates a floating text annotation at cursor position |
| Ctrl + S | Save Project | Triggers REAPER project save |
| Shift + Wheel | Horizontal Scroll | Default horizontal viewport scroll (customizable in Settings) |
| Middle Mouse Drag | Canvas Pan | Default Hand-tool panning (customizable in Settings) |
| Ctrl + Wheel | Canvas Zoom | Zooms score canvas in and out |

---


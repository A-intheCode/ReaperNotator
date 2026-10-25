# REAPER-Notator

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![REAPER](https://img.shields.io/badge/REAPER-v7.0+-orange.svg)](https://www.reaper.fm/)
[![ReaImGui](https://img.shields.io/badge/ReaImGui-v0.10%2B%20Required-brightgreen.svg)](https://github.com/cfillion/reaimgui)
[![Reaticulate](https://img.shields.io/badge/Reaticulate-Required-blueviolet.svg)](https://reaticulate.com/)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg)](#)

> **REAPER-Notator** is a native, professional music notation, score editing, and engraving suite built directly for Cockos REAPER using ReaImGui and standard SMuFL vector glyphs.

> [!IMPORTANT]
> **Required Dependency — ReaImGui v0.10+ (`v0.10.0` or newer):**
> Make sure your **ReaImGui** extension (*"ReaImGui: Dear ImGui for Cockos REAPER"* by cfillion) is updated to **`v0.10+`** via **Extensions $\rightarrow$ ReaPack $\rightarrow$ Synchronize packages** (or *Browse packages* $\rightarrow$ search `ReaImGui` $\rightarrow$ update to `v0.10+` and restart REAPER).

---

## Overview

REAPER-Notator brings high-end music engraving and scoring workflows straight into REAPER's timeline without external software bridges or unwieldy window switching. It combines strict adherence to classical western music engraving standards (*Gardner Read*, *Elaine Gould / Behind Bars*) with deep DAW automation integration.

---

## Video Tutorials & Guides

- 📺 **[Reaper-Notator - Infos about Fix Playback , Ties and Slurs function](https://youtu.be/ahpEfmgGb3M)**: Official tutorial demonstrating the **Selective vs. Global Fix Playback** buttons, **Ties and Slurs** MIDI architecture, and **same-pitch legato overlap protection**.

---

## Key Features

- **Mid-Piece Time Signatures, Multi-Staff Meter Engraving & Scroll-Independent Barlines (v2.51)**:
  - **Bar-Targeted Time Signature Placement (`TempoService` & `KeySignatureDrawer` / `TopBar`)**: Place the Edit Cursor at any measure (e.g., Bar 5) and click any Time Signature (`3/4`, `4/4`, `2/4`, `6/8`, `12/8`, `5/4`, `7/8`, `9/8`, or Custom). REAPER-Notator automatically:
    1. **Engraves the new Time Signature on all staves** (including both staves of Grand Staff instruments) at that bar with automatic horizontal measure-header padding so Beat 1 notes never collide with the meter digits.
    2. **Writes a native REAPER Measure/Time-Signature marker** (`SetTempoTimeSigMarker`) at that exact bar while anchoring Bar 1 so all preceding measures (e.g., Bars 1–4 in `4/4`) remain unchanged.
    3. **Propagates the new meter forward** across all subsequent measures (`Bar 5+`) with scroll-independent barline rendering across the entire composition.
  - **Elaine Gould Tuplet Bracket Clearance (v2.50.3–v2.51)**: Computes true visual top/bottom bounds across stems, beams, noteheads, and articulations so tuplet brackets and numbers never collide with noteheads.

- **Circle of Fifths & Global Harmonic Chord Palette (v2.50)**:
  - **Interactive 24-Sector Harmonic Wheel (`CircleOfFifthsModal` & `CircleOfFifthsService`)**: Located directly below `Step Input` in the Left Sidebar (`🎡 Circle of Fifths`). Features an outer ring of 12 Major keys (`C, G, D, A, E, B, F#, Db, Ab, Eb, Bb, F`) and an inner ring of 12 Relative Minor keys (`Am, Em, Bm, F#m, C#m, G#m, Ebm, Bbm, Fm, Cm, Gm, Dm`) rendered with seamless concentric annular geometry.
  - **Audition & Target Track Selector (`🔊 Audition & Target Track:`)**: Choose `Auto (Active / Armed / First MIDI Track)` or any specific REAPER project track (`1..N`) with a 1-click `🔊 Test` button. Clicking or dragging any sector or harmonic tile automatically record-arms and enables input monitoring on the target track for instant zero-latency chord auditioning.
  - **8 Drag-and-Drop Harmonic Tiles & Dynamic Tension Analysis**: Drag any sector from the Circle of Fifths onto the 8 global progression slots (`Slot 1..8`). Selecting a tile dynamically re-colors the entire Circle of Fifths by harmonic tension (`0%` Tonic to `95%` Tritone/Chromatic) and displays pairwise transition tension badges between adjacent tiles.
  - **Chord Extensions, Inversions, Score Insertion & Global Multi-Tab Persistence**: Customize Triad, 7th (`Maj7`/`m7`/`Dom7`), `9th`, `sus4`, `add9`, `6th`, or `dim7` extensions, inversions (`Root`, `1st Inv`, `2nd Inv`, `Spread`), and base octave (`C2`–`C5`). Insert single tiles or all 8 tiles at the Edit Cursor (with full Auto-Divisi support across armed tracks), set the active Key Signature from any tile (`🎼 Set Key Sig`), and share your 8-tile progression palette across all open REAPER project tabs via global `ExtState`.

- **MIDI Keyboard Step Input & Auto-Divisi Live Recording Suite (v2.36–v2.50)**:
  - **MIDI Keyboard Step Input (`🎹 Enable MIDI Keyboard Step Input`)**: Toggle in the Right-Click Record Modal when stopped. Playing single notes or chords on any hardware MIDI keyboard writes notes of exact active Grid duration (`1/1` to `1/32`, including dotted notes) at the Edit Cursor, auditions the notes, and advances the Edit Cursor by 1 Grid step—complete with `⏮ Step Back` and `⏭ Step Rest` buttons.
  - **Auto-Divisi Live Recording & Zero-Latency Input FX Router (`Notator_Auto_Divisi_Router.jsfx`)**: When 2 or more orchestral tracks are armed, live MIDI playing and Step Input automatically route single notes to their matching instrument register (e.g. `C2` $\rightarrow$ Double Bass) and distribute simultaneous chords harmonically across armed tracks (`Smart Register & Voice Split` or `Top-Down Voice Split`) with live audible JSFX routing and legato voice handover.

- **Percussion Clef Auto-Detection, Full C0–C9 Drum Map & 9 SMuFL Custom Noteheads (v2.47–v2.50)**:
  - **Automatic Unpitched Percussion Clef (`percussion_1`)**: Automatically assigns Percussion Clef to drum and unpitched percussion tracks (`Snare`, `Drums`, `Kick`, `Gran Cassa`, `Toms`, `Taiko`, `Cymbals`, `Hi-Hat`, `Tambourine`, `Percussion`, etc.) while preserving pitched clefs for `Timpani` (Bass Clef), mallets (Treble Clef), and `Celesta` (Grand Staff).
  - **Full C0–C9 (`0..127`) Percussion Staff Mapping**: Maps General MIDI drum pitches cleanly across the 5-line percussion staff and folds extreme octaves (`< 35` or `> 81`) into the Percussion System without ledger-line jumps.
  - **9 SMuFL Custom & Percussion Noteheads (`🥁 Notehead / Percussion Head`)**: Right-click any note or multi-note selection to assign `standard`, `x`, `circle_x`, `diamond`, `triangle`, `triangle_down`, `plus`, `slash`, or `square` noteheads with exact Elaine Gould stem attachment coordinates, MIDI Type 15 persistence, Clipboard Copy/Paste, and MusicXML `<notehead>` round-tripping.

- **Elaine Gould ("Behind Bars") Optical Spacing & Engraving Engine (v2.43–v2.44)**:
  - **Non-Linear Proportional Spacing ($\Delta t^{0.70}$) & Collision-Free Measure Expansion**: Weights intra-measure rhythmic intervals optically and dynamically expands dense measures so noteheads, dots, and accidentals never collide.
  - **Intra-Bar Accidental Memory & Multi-Column Chord Stacking**: Automatically tracks altered steps within each bar, emits natural ($\natural$) cancellations when returning to diatonic pitches, stacks chord accidentals into up to 3 collision-free diagonal columns, and leaves a clean visual gap between Clef and Key Signature.
  - **Complete Gould & Read Engraving Details**: 32nd/64th flag & beam stem lengthening with inner-beam clearance, rest-breaking beams, paired fractional stubs, strict 2-side chord 2nd alternation, dotted chord 2nd separation, curved S-bezier Piano/Harp accolade brace (`{`), and stem-centered tremolo slashes.

- **Melodic Pathfinder 2.0 — Film-Score Melody & Counter-Melody Composer (v2.53–v2.57)**:
  - **ReaImGui `v0.10+` Dynamic Font & `< v0.10` Legacy Compatibility (`FontManager`, v2.56)**: Automatically detects ReaImGui `v0.10+` vs. older `< v0.10` installations to prevent `font_cfg->SizePixels > 0.0f` font-atlas assertions on startup.
  - **Display Quantize Engine (`1/1` to `1/32`, v2.55)**: True non-destructive visual quantization (`Engraver.quantize_notes_for_display` & `Engraver.get_display_quantized_qn`) snaps both visual note start positions (strictly clamped within each note's own measure so bar-end notes never jump across the barline) and visual durations to the selected grid (`1/1` whole notes down to `1/32`), consolidates notes falling into the same grid slot while preserving simultaneous chords and selection links, and guarantees 0% side effects when Display Quantize is disabled.
  - **Settings Modal & High-Resolution Illustrated User Manual (v2.54)**: All Settings sections start collapsed by default on launch, with a collapsible `"Donate if you want to contribute"` section at the bottom and a 20-figure high-resolution illustrated PDF User Manual (`docs/reaper_notator_user_manual.pdf`).
  - **Three Composing Workflows**:
    1. **Blend Selected Anchor Notes (2+ Notes Selected)**: Your selected landmark notes stay 100% untouched (Orange Anchors) while Melodic Pathfinder composes a smooth musical bridge connecting them.
    2. **Grow a Theme from 1 Seed Note (1 Note Selected)**: Develops a complete **2- to 32-bar** theme starting from your selected note with recurring motifs, variations (`A – A' – B – A''`), breathing rests, and natural cadences.
    3. **Free Phrase or Counter-Melody (0 Notes Selected)**: Generates a complete phrase in your track's clef and key, or writes a true **Counter-Melody** moving in contrary motion and complementary rhythm against any Reference Track.
  - **8 Descriptive Film Score Archetypes**: *Heroic Symphonic Fanfare*, *Intimate Elegiac Strings*, *Minimalist Ostinato Pulse*, *Pastoral Folksong & Wonder*, *Gothic Fairy-Tale Waltz*, *Poetic Suspense & Noir*, *Epic Ancient Brass & Choir*, and *Romantic Contrapuntal Cantabile*.
  - **3 Interactive Coupled Bezier Curves (Tension, Note Length, Pitch)**: Sketch freehand in **Draw** mode directly over the note map—on mouse release your stroke automatically simplifies into a smooth Bezier curve with draggable handles in **Edit Handles** mode. **Tension** shapes emotional intensity, wider leaps, and note velocity (`pp` $\rightarrow$ `ff`); **Note Length** shapes rhythmic speed (fast 8ths/16ths vs. broad half/whole notes); **Pitch** shapes the high/low contour arch. Includes 4 session **RAM slots** and `.json` **Export/Import**.
  - **Pre-Armed Instant First-Note Audition & `[● REC]` Indicator (v2.53)**: Pre-arms the target instrument track while the Melodic Pathfinder window is open (showing the red `[● REC]` badge on the staff header and modal) with a 2-stage articulation warmup so clicking **Audition Melody** never drops the first note.
  - **Full Reaticulate Cloned Bank Support (v2.53)**: Resolves `//! clone="..."` and short bank names across all Reaticulate banks, fixing Spitfire BBC Symphony Orchestra (`BBC - Trumpet`, `BBC - Trumpets a3`, `BBC - Flutes a3`, `BBC - Piccolo Flute`) and Chamber/Symphonic Strings & Woodwinds.

- **Per-Track Freehand Annotation Layer System (v2.28–v2.34)**:
  - **Multi-Layer Freehand Pen & Eraser (`AnnotationService` & `AnnotationDrawer`)**: Draw directly on the score across per-bar transparent PNG tiles with 12 color presets, Analytical Capsule SDF anti-aliasing, quadratic Bézier curve smoothing, and 4 resolution steps (`1x`–`3x`) per instrument track.

- **Global `ImGuiGuardService` & 172-Test Automated Verification Suite (v2.45–v2.53)**:
  - **Zero-Leak ImGui Stack Protection**: Wraps `ImGui_Begin`/`End` and `ImGui_BeginChild`/`EndChild` across all UI modals, drawers, and panels to guarantee zero `Missing EndChild()` errors even on runtime exceptions.
  - **172 Automated Unit Tests (`tests/test_all_modules.lua`)**: Verifies all 89 Lua modules and 654 exported functions with strict `_G` global-leak protection and 0 failures.

- **1,500 Curated Orchestral Patterns Across 10 Categories (v2.17)**:
  - Added **150 Orchestral & Cinematic Percussion** (`09_Orchestral_Percussion`) and **150 Low Strings — Celli & Double Basses** (`10_Low_Strings_Celli_Basses`) patterns to the 1-click Pattern Browser library.

- **Divisi — Split Voices to Duplicated Instrument Tracks (v2.15)**:
  - **True Orchestral Section Divisi (`DivisiService` & `DivisiModal`)**: Splits polyphonic voices (`Voice 1..16` / MIDI Channels `1..16`, e.g., after running *Auto-Voice on Selection* or *Auto-Voice Track Overlaps*) onto newly duplicated REAPER tracks directly below the source staff (`<Track Name> (Divisi 2)`, `<Track Name> (Divisi 3)`, ...).
  - **Full FX, Kontakt/VSTi & Reaticulate Duplication**: Uses REAPER's native track duplication (`Action 40062`) to clone all Kontakt/VSTi instances, Reaticulate JSFX, Reaticulate bank assignments (`P_EXT:reaticulate`), sends/routing, folder hierarchy (`I_FOLDERDEPTH`), Notator clefs, and MIDI items.
  - **Per-Voice Filtering & Channel 1 Normalization**: Voice 1 remains on the source track while each secondary voice is isolated on its own duplicated track and optionally normalized to Voice 1 (MIDI Channel 1) so monophonic/legato patches respond out of the box.
  - **1-Click Context Menu & Interactive Preview Modal**: Execute in 1 click from the Note/Staff right-click menu (`✂ Divisi (Split Voices to Duplicated Tracks)`) or open the interactive preview dialog (`✂ Divisi (Options / Preview)...` / Tools Drawer) with per-voice note counts, pitch ranges, and a quick `⚡ Run Auto-Voice Now` button.

- **Pattern Browser Multi-Bar Audition, Multi-Note Staccato & Articulation Auto-Chase (v2.10–v2.14)**:
  - **Pattern Browser Full-Length Playback & Target Routing**: Auditions multi-bar orchestral patterns across their complete duration through any selected/focused track (`Auto`) or specific target instrument dropdown without altering REAPER's track selection.
  - **Multi-Note Staccato & Momentary Articulation Auto-Chase**: Applies staccato dots and momentary articulations across all selected notes simultaneously, remembers the preceding base articulation (`pre_staccato_art`), and automatically restores it on subsequent unarticulated notes.
  - **Shadow-Copied Native Timer DLL**: Loads `notator_timer_x64.dll` from a temporary shadow copy so ReaPack updates never encounter Windows file-lock conflicts even if REAPER Notator is open.

- **Clean Note Audition, Static Canvas Focus, MusicXML Performance Engine & Native 60–144 FPS Timer (v2.0.7)**:
  - **Clean Note Audition Without `● REC` Badge (`AudioPreview.is_track_user_armed`)**: Distinguishes genuine user record-arming from temporary `StuffMIDIMessage` Virtual MIDI Keyboard preview arming (`AudioPreview.track_restore`). Clicking or dragging notes to audition them never displays the red `● REC` pill badge or red recording border on the instrument track header.
  - **Static ScoreCanvas Viewport on Note Click**: Clicking notes, item badges, clefs, or track headers on the ScoreCanvas selects the parent MIDI item and track in REAPER while keeping the ScoreCanvas viewport (`scroll_x` / `scroll_y`) completely stationary unless **Auto-Scroll** (`state.auto_scroll`) is explicitly enabled.
  - **MusicXML Slur/Tie Spatial Index & Cached Key/Time Signature Engine**: Eliminates frame drops in dense orchestral MusicXML scores (with hundreds of ties and slurs) using a per-frame pitch/spatial index (`get_note_render_index`), memoized GUID normalization, direct `MediaTrack` pointer comparisons, and take-level `NOTATOR_KEY` / `NOTATOR_TIME_SIG` caches—removing over 225,000 C-API calls and 1.5M table iterations per frame.
  - **Mid-Piece MusicXML Time Signature Timeline Sync**: Automatically synchronizes mid-piece `NOTATOR_TIME_SIG` changes from MIDI takes to REAPER's master timeline via `SetTempoTimeSigMarker` and prunes orphaned legacy `ProjExtState` metadata on import and project load.
  - **Multi-Monitor & 4K HiDPI Window Maximize Engine**: Live OS HWND coordinate-space calibration (`JS_Window_GetRect` vs ReaImGui logical window state + post-maximize verification) and monitor-proportional bounds ensure maximizing (`F11`) fills 100% of any display (e.g. 4K laptop + 1080p external monitor) regardless of Windows DPI scaling (100%–250%).
  - **Native High-Refresh Timer Engine (`notator_timer_x64.dll`, 60 / 90 / 120 / 144 FPS)**: Unlocks REAPER's hardcoded 30ms (~32.0 FPS) global `reaper.defer()` and ReaImGui timer ceiling on Windows at 1ms kernel precision while REAPER Notator is open, and automatically restores REAPER's default 30ms timer upon closing.

- **Automatic Reaticulate FX Slot 1 Setup, Primary Bank Replacement & Articulation Engine (v2.0.4–v2.0.7)**:
  - **Automatic `JS:Reaticulate` (`Reaticulate.jsfx`) Verification & Slot 1 Ordering**: Selecting a bank in the Bank Picker or applying an articulation on a brand-new or unconfigured track automatically checks the track's FX chain for `Reaticulate.jsfx`. If missing, it loads it automatically; if placed after a VSTi instrument (slot $> 0$), it automatically moves `Reaticulate.jsfx` to the very first FX slot (**Slot 1 / index 0**) before the instrument so keyswitches and channel routing work out of the box.
  - **Primary Bank Replacement Without Stacking**: Adding or changing an articulation bank on a track cleanly replaces the top primary bank (`appdata.banks[1]`) and any conflicting Omni (`src == 17`) entries in `P_EXT:reaticulate`, preventing duplicate stacked banks and program number conflict errors in Reaticulate.
  - **Native `P_EXT:reaticulate` Metadata & Wildcard `Bank * *` MSB/LSB Sync**: Writes the structured JSON bank assignment into the track's `P_EXT:reaticulate` state, resolves or allocates deterministic CRC64 MSB/LSB (`CC0`/`CC32`) numbers for wildcard `Bank * *` definitions, and triggers Reaticulate's live RFX sync.
  - **Selected Notes & Empty-Item Edit-Cursor Articulation Placement**: Applies articulations (`NOTE <pitch> <chan> a <art>` + `CC0`/`CC32` Bank Select + `Program Change`) to all selected notes, attaches them to notes at the **REAPER Edit Cursor**, or inserts standalone articulations directly at the Edit Cursor inside empty selected MIDI items (rendered visibly above the staff).

- **Transport Recording Suite, MIDI Input Routing, Live Note Preview & Auto-Quantize Engine (v2.0.3)**:
  - **Native Record Button**: Dedicated transport Record button located between Play and Stop in the top toolbar with live glowing red recording status (`🔴 REC`) and idle state (`⏺ Rec`). Left-clicking while recording stops both Recording and Playback completely in one click (`CSurf_OnStop`).
  - **Right-Click Configuration Modal**: Right-clicking the Record button opens a dedicated dialog for Pre-roll, Metronome Count-in, MIDI Input Device & Channel selection, Track Record-Arming, Live Preview, and Auto-Quantize settings.
  - **MIDI Input Device & Channel Selector**: Choose from all connected hardware MIDI keyboards, REAPER's Virtual MIDI Keyboard, or All MIDI Inputs plus MIDI Channel (`All` or `1–16`). Automatically enables Input Monitoring (`I_RECMON`) and MIDI Overdub (`I_RECMODE = 7`) so REAPER records directly into MIDI score items without popping up Audio `.wav` Save prompts.
  - **Real-Time Live Note Preview & Non-Destructive Clamping**: Captures incoming MIDI Note-On/Note-Off events in real time via `MIDI_GetRecentInputEvent` and renders played notes live on the score canvas at the red playhead (strictly clamping held notes to the red playhead to prevent infinite tie artifacts).
  - **Bidirectional Track Record-Arming & Red Canvas Badges**: Lists all REAPER project tracks (including empty tracks) in the modal; arming a track immediately updates REAPER's native TCP/MCP Record-Arm button and highlights the track in the score canvas with red-tinted headers, red borders, and crisp vector `REC` pill badges.
  - **Pre-roll & Metronome Count-in Sync**: Integrated with REAPER's native Pre-roll (Action 41818), adjustable bar length (1, 2, 4 bars), Count-in (Action 40364), and quick-access button to REAPER's native Metronome/pre-roll settings dialog.
  - **Real-Time & Post-Record Auto-Quantize Engine**: Previews auto-quantized notes live on the score canvas and commits them cleanly upon stopping recording. Eliminates keyboard pre-bounces ($<15$ ticks), trims same-pitch overlaps, snaps onsets within configurable tick tolerance (default: 1/8 note @ 25 ticks), and provides four outlier handling modes: **🧲 Snap to Grid** (default), **Keep natural**, **Delete outliers**, or **Move to Voice 16**.

- **2-Step Window Maximize, Startup Centering & Custom Rehearsal Marks (v2.0.3–v2.0.7)**:
  - **2-Step Screen Work Area Maximize & Clean Centered Startup**: Queries the full work area of the target monitor first, opens centered in floating size on every REAPER launch (without persisting `is_maximized` across sessions), and scales cleanly to full monitor bounds on Maximize (`F11`).
  - **Custom Rehearsal Marks, Inline Double-Click Renaming & `Ctrl+M` Live Shortcut**: Double-click any Rehearsal Mark on the score canvas to rename it inline (automatically locking it as a Custom Marker and excluding it from the `A, B, C...` / `1, 2, 3...` sequence). Press `Ctrl+M` live during Playback/Recording (or when stopped) to drop sequential Custom Markers (`Marker 1`, `Marker 2`...) at the Playhead or Edit Cursor.

- **Filter Irregular Notes & Rhythmic Clean-Up (v1.9.9)**:
  - **Live-Recorded & Humanized MIDI Cleaner**: Detects micro-timing deviations that cause fractional rests and tied fragments in classical engraving.
  - **Subdivision & Triplet Metric Engine**: Tests note onsets against 1/1 through 1/32 subdivisions (and optional 1/12, 1/24, 1/48 triplets) across all time signature changes.
  - **Live Canvas Yellow Highlighting & Ghosting**: Real-time gold/yellow (`#FFD700`) preview on the score canvas with optional dimming/ghosting of regular notes for effortless visual inspection.
  - **Dual Execution Modes**: Non-destructively select irregular notes (`🔍 Select Notes`) or reassign them cleanly to a secondary background voice (`⚡ Reassign to Voice`, default Voice 16 / MIDI Ch 15).
  - **Gould Polyphonic Rest Consolidation**: Automatically consolidates co-occurring identical rests across polyphonic voices into a single centered rest with vertical collision avoidance.

- **Integrated Multi-Lane MIDI Editor Suite (v1.8.0)**:
  - **Synchronized Drawer Architecture**: Interactive bottom drawer with live bidirectional synchronization between the score notation canvas and REAPER's active MIDI takes.
  - **Velocity Stalks & Flag Handles**: Authentic REAPER-style velocity stalks with interactive flag handles (*"Fähnchen"*), realtime acoustic auditioning on vertical drag, and freehand pencil drawing (`✏ Draw`).
  - **Velocity Presets & Tools**: One-click dynamic velocity presets ($pp$, $mp$, $mf$, $f$, $ff$), linear velocity ramping, and natural acoustic humanizing ($\pm 7$).
  - **128 Continuous Controller Lanes**: Complete support for all 128 MIDI CC channels (Modulation CC1, Breath CC2, Expression CC11, Volume CC7, Pan CC10, Sustain CC64, etc.) with REAPER CC curve envelope integration (Linear Ramp default, Square Step, Slow Start/End S-Curve, Fast Start/End, and Bézier).
  - **Convert All to Linear**: 1-click batch conversion eliminating staircase artifacts (*"Treppenstufen"*).
  - **Dynamic CC Shaping Protection**: Automatic padlock lock (`🔒 CC Locked`) protecting CC1/CC11 orchestral dynamics from accidental overwrites, with a 1-click Unlock / Bypass toggle.
  - **Dedicated User Manual**: See the standalone documentation at [**`tools/midi_editor_manual.md`**](tools/midi_editor_manual.md).

- **Performance Overhaul & 60-70+ FPS Playback Pipeline (v1.8.0)**:
  - **Zero-Latency Playback Query Bypass**: During active playback, interactive hover checks, ghost note previews, drag evaluations, Take C-API queries, and track scans are completely bypassed, rendering purely from pre-allocated memory caches.
  - **In-Memory Layout Caching**: Precomputed note layouts, beam groups, and rest collision avoidance eliminate tens of thousands of table allocations per second during playback.
  - **Viewport Frustum Culling & Coordinate Invalidation**: Strict coordinate invalidation (`-999999`) and 2D frustum culling ensure fast scrolling and auto-scroll jumps never leave behind frozen stems or ghost barlines.
  - **Same-Frame Auto-Scroll Re-anchoring**: Immediate same-frame coordinate re-synchronization eliminating 1-frame latency on playhead jumps, with stopped-state decoupling for uninterrupted manual score inspection.

- **Modernized Interface & Performance Settings (v1.8.0)**:
  - **Target Framerate (FPS)**: Selectable presets (15, 30, 60, 90, 120, 144, Uncapped) with real-time measured FPS counter (`⚡ Live: XX.X FPS`).
  - **Hardware Vector Line Anti-Aliasing**: Toggleable Dear ImGui line/fill edge anti-aliasing with high-performance mode for 30+ track scores.
  - **Configurable Undo History**: Max Undo Steps slider (0-200) and 1-click `🧹 Clear Project Undo History` purge button.
  - **Ergonomic View Navigation**: Fully customizable keyboard modifiers and mouse buttons for Horizontal/Vertical scroll, Hand-tool pan, and Zoom, with speed multipliers and direction inversion.
  - **MIDI Editor Color Themes**: Complete palette customization in Settings -> MIDI Editor Colors.

- **Standard-Compliant Music Engraving**:
  - Full SMuFL glyph font rendering (Bravura).
  - Strict measure division and rhythmic decomposition.
  - Automatic beaming engine with slope compensation and beamlet/stub handling.
  - Multi-voice support with collision avoidance and centered whole measure rests.
  - Tuplet rendering (triplets, quintuplets, sextuplets, septuplets, etc.).
  - **Grand Staff & Cross-Staff Engine**: Natural pitch-based split at Middle C ($C_4$) with interactive cross-staff switching (`M` or `Ctrl+Shift+Up/Down`) and per-note staff overrides.

- **Dynamic Automation & CC Engine**:
  - 10 standardized dynamic levels ($ppp$ through $fff$) mapped to customizable MIDI velocities and CC values.
  - Automated hairpin curves ($crescendo$ and $diminuendo$) with linear and exponential shaping.
  - Asymmetric **Bow Swell** curve generator with adjustable peak position per MIDI item.
  - Continuous controller automation across CC1 (Modulation), CC11 (Expression), and CC7 (Volume).

- **DAW & Articulation Integration**:
  - Seamless two-way integration with [**Reaticulate**](https://reaticulate.com/) ([GitHub](https://github.com/jtackaberry/reaticulate)) sound libraries and bank presets.
  - Articulation drawer with instant key switch / program change assignment.
  - Sustain and Holding pedal lane (CC64) with dual drag handles and break/retake notches.
  - Octave shift lines ($8^{va}$, $8^{vb}$, $15^{ma}$, $15^{mb}$).
  - Live timeline audition preview with mouse-hover pitch feedback.

- **Tempo & Time Signatures**:
  - Direct synchronization with REAPER's master tempo map.
  - Gradual tempo transitions (*accelerando*, *ritardando*) and metric modulations.

- **Score-Wide Fermatas, Rehearsal Marks & Score Tools (v1.4.3)**:
  - Key & Time Signatures: Direct MIDI Item Scope support allowing immediate key and time signature application to selected items upon drawer selection with live in-memory score rendering.
  - Clef Management: Dedicated track-level clef management with automatic parent-track focus when items or notes are selected.
  - Dynamic Rehearsal Marks ([A], [B], [C]...) with automatic re-sequencing and interactive mouse **drag-and-drop** along the dedicated Rehearsal Lane.
  - Real-time vertical snap guide line and target bar downbeat indicator during mark dragging.
  - Automatic edit-cursor bar detection in the Tools Drawer (`Add Letter Mark at Bar X` / `Add Number Mark at Bar X`).
  - Score-wide vertical Fermatas (standard, short, long, very long) clickable and selectable on every staff across the entire system.
  - Tempomap playback coupling with deterministic tempo-dip slowdown (1.25x to 3.0x) and automatic restoration.
  - Standard navigation symbols: Da Capo ($D.C.$ / $D.C. \text{ al Fine}$), Dal Segno ($D.S.$ / $D.S. \text{ al Coda}$), Segno, Coda, and Fine.
  - Arpeggiated chords with bezier wavy line engraving and non-destructive micro-strumming playback offset.
- **Dual Playback Reconciliation Engine & Overlap Protection (v1.6.2)**:
  - **Selective Playback Fix (`⚡ Fix Playback (Selective)`)**: Scans and reconciles exclusively the single selected MIDI item (or item of selected notes) with the active sound bank without touching any other items on the track or in the project.
  - **Global Playback Fix (`⚡ Fix Playback (Global)`)**: Project-wide scan that reconciles all MIDI items across all tracks, clearing outdated Program Changes, healing legacy hairpins, and recalculating auto-chase return points.
  - **Same-Pitch Legato Overlap Protection & Healing**: Eliminates note-erasing bugs caused by former slur legato extensions when transposing or drawing adjacent notes on the same pitch. Tightly resolves voice conflicts down to 1 tick, clamps prior note tails on insertion, and cleans micro-legato remnants ($\le 15$ ticks same pitch, $\le 5$ ticks different pitch without active slur) on slur deletion and during playback fix.
  - **Tutorial Video Integration**: Direct in-app and documentation link to the official video walkthrough: [Reaper-Notator - Infos about Fix Playback , Ties and Slurs function](https://youtu.be/bLegp49esXg).
- **Comprehensive Slurs & Ties Engine and Pattern Library (v1.6.0 & v1.6.1)**:
  - **Interactive Slur & Tie Creation**: Fast, one-key toggling for Slurs (`S`) and Ties (`T` or `Shift+T`) across single notes, chords, and multi-measure selections with automatic context-sensitive grouping.
  - **Authentic Bézier Engraving**: Gardner Read & Elaine Gould (*Behind Bars*) compliant cubic Bézier curves with dynamic curvature direction (arch-up / arch-down), automatic staff-line avoidance, and chord tie fan-out.
  - **Intelligent Non-Destructive MIDI Playback**: Seamless audio playback where tied notes visually sustain across measure boundaries while automatically suppressing redundant Note-On re-triggering and keyswitch artifacts (preventing false re-attacks or unintended patch switches).
  - **Production-Grade Orchestral Pattern Library**: Integrated library of 1,200 production-ready MIDI patterns across 8 orchestral categories (Strings Staccato, Strings Pizzicato, Brass Blockbuster, Cinematic Melodies, Counter Melodies, Woodwinds Textures, Cinematic Piano, Ancient Harp Greek & Roman) with instant audition and insertion.
- **Dynamic Object Scaling Decoupling & Legacy Hairpin Playback Healing (v1.5.6)**:
  - **Decoupled Dynamic Scaling**: Hairpins (`<`, `>`) and Dynamic Text objects (`cresc.`, `dim.`) now strictly collide and bound against dynamic markers ($p$, $pp$, $mp$, $mf$, $f$, etc.), other hairpins, and dynamic texts. They will never collide with or be bounded by note articulations (e.g. staccatos, tenutos, accents). Hairpins can now span freely across passages containing dense patterns of dozens or hundreds of staccato notes without shrinking or collapsing.
  - **Legacy Hairpin Playback Healing via "⚡ Fix Playback"**: The "⚡ Fix Playback" command automatically detects collapsed or shrunken hairpins and dynamic texts ($\le 0.75\text{ QN}$) in legacy projects that were squeezed by old staccato collisions, expands them back to their natural musical boundaries, recalculates dynamic levels, and regenerates clean continuous CC automation ramps without staccato clipping.
  - **Dynamic Status Reporting**: Reports healed dynamic element counts in the bottom status message alongside synced notes and cleared events.
- **Playback Reconciliation & Fix of Last Resort Hotfix (v1.5.5)**:
  - **Idempotent Playback Reconciliation**: Left-clicking "⚡ Fix Playback" scans and reconciles all note articulations with the active track's Reaticulate sound bank without stripping or corrupting existing valid articulations.
  - **Fix of Last Resort Modal**: Repeating click when already synchronized (or right-clicking at any time) presents a dedicated emergency confirmation modal window to purge corrupted keyswitches (CC0/CC32/PCs) and reset to clean default sustain.
  - **Dead-Center Modal Placement**: Modal uses `Cond_Always()` with pivot `0.5, 0.5` dynamically computed from screen/window dimensions to guarantee perfect horizontal and vertical centering without jitter or 50Hz flickering.
  - **Target Track Resolution**: Fixed REAPER C-API take track lookup (`get_track_from_take`) and implemented multi-tier track resolution so the modal header clearly displays the target track name (`Target: Track <num>: <name>`).
  - **User Manual & Workaround Documentation**: Updated Section 6.5 in the User Manual with complete step-by-step instructions for troubleshooting third-party sample libraries lacking specific articulation keyswitches (e.g. staccato).
- **MusicXML Import & Instant Note Audition Hotfix (v1.5.4)**:
  - **Intelligent Articulation Mapping on Import**: Prioritized 3-tier algorithm for staccato mappings ensuring dedicated short patches (such as Spitfire 'Staccato Dig') take precedence over duration fallbacks ('Short 0.5') during MusicXML import.
  - **Compact Import Layout**: Automatically reduces track heights to 25px upon MusicXML import for an organized orchestral overview.
  - **Single-Note Audition Arbitration**: Strict hit-testing isolation ensures that clicking in dense chords or adjacent systems previews only the single clicked notehead.
  - **Track Audition Isolation**: Temporarily disarms other project tracks during preview to eliminate Virtual MIDI Keyboard crosstalk across instruments sharing identical registers.
  - **Timeline Articulation Chasing**: Auditioning scans the project timeline from measure 1 up to the clicked note, sending authentic Reaticulate bank and Program Change data.
  - **Zero-Latency First Click**: Eliminated destructive patch reset on mouse release and introduced 1-frame pre-switching for Bank/Program Change before Note-On, ensuring instant articulation playback on the very first click.
- **Selective Score Clipboard & Engraving Hotfixes (v1.5.3)**:
  - **Selective Note Copy/Paste Engine**: Isolated note copying so that copying selected notes or chords never inadvertently captures unselected dynamics, hairpins, pedal markings, or tempo markers. Pasting notes into a MIDI item cleanly respects existing item boundaries without truncating or unexpectedly expanding takes.
  - **Authentic SMuFL Staccatissimo**: Upgraded staccatissimo wedges from rough canvas polygons to authentic Bravura SMuFL glyphs (`articStaccatissimoAbove` / `articStaccatissimoBelow`) with pristine subpixel anti-aliasing and vector fallback strokes.
  - **Standard-Compliant Staccato Dot Placement**: Aligned staccato dots consistently across beamed note clusters opposite beam stems (per Elaine Gould standard), complete with automatic staff-line avoidance.
  - **Clean Saving & Print Subsystem Decoupling**: Completely removed background print XML auto-generation (`*_print.xml`) on project save and exit.
  - **Flush Bottom Bar Layout**: Eliminated the right-margin gap on the bottom control bar, cleanly docking utility modals flush to the window edge.
- **Polyphonic Engraving & Stem Alignment Hotfix (v1.5.1)**:
  - **Attached Multi-Voice Stems**: Fixed detached floating note stems in polyphonic measures by aligning concurrent voices on the exact same beat axis and eliminating false horizontal collision pushing.
  - **Full Stem & Notehead Coordinate Synchronization**: Guaranteed seamless attachment between noteheads, stems, flags, and beams across all collision adjustments and second-interval displacements.
  - **Voice-Separated Beaming**: Partitioned beam groups strictly by staff and voice, enforcing Elaine Gould standard-compliant stem directions (Voice 1 stems up, Voice 2 stems down).
- **Smooth Anti-Aliased Beaming & Enhanced Usability (v1.5.0)**:
  - **Silky Smooth Anti-Aliased Beam Rendering**: Normalized Dear ImGui quad vertex winding (strictly clockwise) across all stem orientations and beamlet/stub directions, ensuring clean outward-facing normal vectors and pristine subpixel anti-aliasing.
  - **Full Stem Width Coverage**: Extended beam boundaries to encompass the full thickness of outside stems (`half_stem`), with embedded stem line terminations preventing flat end caps from poking past slanted beam edges (per Gardner Read & Elaine Gould).
  - **Keyboard Note Navigation**: Seamless keyboard-only timeline navigation (`Alt + Left / Right`) to hop between notes, and selection expansion (`Alt + Shift + Left / Right`) with intelligent Auto-Scroll integration.
  - **Modernized Settings Modal**: Collapsible section headers, single unified vertical scrolling container to prevent clipped layouts, pinned static action footer, and live shortcut search filter.
  - **Comprehensive Dark Mode Inversion**: Full palette coverage for clefs, time signatures, rests, ties, lyrics, rehearsal marks, fermatas, and polyphonic voice contrast, plus standard engraving black bar numbers in light mode.

- **Interoperability**:
  - Native **MusicXML 4.0** import and export.
  - Clipboard copy/paste for dynamic marks, pedal lines, and score annotations.

---

## Documentation

- 📖 **[Official User Manual & Function Reference](tools/user_manual.md)** ([PDF Version](docs/reaper_notator_user_manual.pdf)): Comprehensive guide covering all engraving, playback, and DAW synchronization features.
- 🎹 **[Integrated MIDI Editor Manual](tools/midi_editor_manual.md)**: Dedicated standalone guide for the MIDI Velocity & 128 CC Automation drawer, curve shaping, and dynamic protection.
- 📊 **[Codebase Architecture & Volume Statistics](tools/codebase_statistics.md)** ([PDF Version](docs/reaper_notator_codebase_statistics.pdf)): Technical metrics and architecture breakdown.

---

## Installation

### Method 1: Via ReaPack (Recommended)

1. Ensure you have **ReaPack** installed in REAPER ([reapack.com](https://reapack.com/)).
2. Install the required dependencies in ReaPack (`Extensions` → `ReaPack` → `Browse packages...`):
   - **ReaImGui v0.10+** (**required** — `v0.10.0` or newer from ReaTeam Extensions via ReaPack)
   - **Reaticulate** (**required** — install via ReaPack or import repository `https://reaticulate.com/index.xml`)
3. In REAPER, go to:
   `Extensions` → `ReaPack` → `Import a repository...`
4. Enter the following repository URL:
   ```text
   https://raw.githubusercontent.com/A-intheCode/ReaperNotator/main/index.xml
   ```
5. Open `Extensions` → `ReaPack` → `Browse packages...`.
6. Search for `REAPER-Notator`, right-click on it, select **Install**, and click **Apply**.
7. Run `Script: reaper_native_notator.lua` from the REAPER Actions list (`?`).

### Method 2: Manual Installation

1. Install the required dependencies:
   - **ReaImGui v0.10+** (**required** — `v0.10.0` or newer)
   - **Reaticulate** (**required** — [reaticulate.com](https://reaticulate.com/))
2. Clone or download this repository into your REAPER Scripts folder:
   - **Windows:** `%APPDATA%\REAPER\Scripts\REAPER-Notator`
   - **macOS:** `~/Library/Application Support/REAPER/Scripts/REAPER-Notator`
   - **Linux:** `~/.config/REAPER/Scripts/REAPER-Notator`
3. Open REAPER, press `?` to open the **Actions List**, click **New Action...** → **Load ReaScript...**, and select `reaper_native_notator.lua`.

---

## Requirements

- **Cockos REAPER** v7.0 or higher
- **ReaImGui v0.10+** (**required** — `v0.10.0` or newer, available via ReaPack from the ReaTeam repository; run `Extensions -> ReaPack -> Synchronize packages` to update)
- **Reaticulate** (**required** — available via ReaPack: [reaticulate.com](https://reaticulate.com/))
  > **Note:** Reaticulate is an essential prerequisite for REAPER-Notator to run. It handles articulation sound bank definitions, keyswitch chasing, and MIDI playback orchestration. Make sure Reaticulate is installed before launching REAPER-Notator.
- **SWS / S&M Extension** (recommended — [sws-extension.org](https://www.sws-extension.org/))
- **JS_ReaScriptAPI** (recommended — available via ReaPack)

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.  
See the [LICENSE](LICENSE) file for details.

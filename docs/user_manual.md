# REAPER-Notator - Official User Manual & Function Reference

**Version:** 1.0.1  
**Date:** 2026-10-03  
**License:** GNU General Public License v3.0  

---

## Table of Contents

- [Chapter 1: Introduction & Interface Architecture](#chapter-1-introduction--interface-architecture)
- [Chapter 2: Top Toolbar & Global Navigation](#chapter-2-top-toolbar--global-navigation)
- [Chapter 3: Score Canvas & Note Editing Engine](#chapter-3-score-canvas--note-editing-engine)
- [Chapter 4: Standard-Compliant Automatic Beaming Engine](#chapter-4-standard-compliant-automatic-beaming-engine)
- [Chapter 5: Dynamics Engine, Hairpins & Bow Swell Function](#chapter-5-dynamics-engine-hairpins--bow-swell-function)
- [Chapter 6: Articulations & Reaticulate Integration](#chapter-6-articulations--reaticulate-integration)
- [Chapter 7: Holding & Sustain Pedal Lane (CC64)](#chapter-7-holding--sustain-pedal-lane-cc64)
- [Chapter 8: Tempo Maps & Metric Transitions](#chapter-8-tempo-maps--metric-transitions)
- [Chapter 9: Octave Shift Lines (8va, 8vb, 15ma, 15mb)](#chapter-9-octave-shift-lines-8va-8vb-15ma-15mb)
- [Chapter 10: Orchestral Pattern Browser](#chapter-10-orchestral-pattern-browser)
- [Chapter 11: Text Items & Score Annotations](#chapter-11-text-items--score-annotations)
- [Chapter 12: MusicXML 4.0 Import & Export](#chapter-12-musicxml-4.0-import--export)
- [Chapter 13: Page Print & PDF Score Layout](#chapter-13-page-print--pdf-score-layout)
- [Chapter 14: Keyboard Shortcuts & Quick Reference](#chapter-14-keyboard-shortcuts--quick-reference)

---

## Chapter 1: Introduction & Interface Architecture

### 1.1 Overview & Vision

REAPER-Notator is a native, professional music scoring, notation editing, and engraving environment built directly into Cockos REAPER using ReaImGui and standard SMuFL (Standard Music Font Layout) Bravura vector glyphs. Unlike external scoring applications, Notator runs directly inside REAPER's audio engine and timeline, providing instantaneous two-way synchronization between visual music notation and underlying REAPER MIDI takes, CC automation, and tempo maps.

### 1.2 The Three-Column Workspace Layout

The user interface is designed around an ergonomic three-column layout:

- Left Column (Sidebar Palette): Quick tools for note entry modes (pointer, pencil, text, eraser), rhythmic durations (whole to 32nd notes), augmentation dots, accidentals, tuplets, stem orientation, and articulation toggles.
- Center Column (Score Canvas): Infinite interactive notation canvas displaying visual staves, barlines, noteheads, stems, beams, ties, slurs, lyrics, and rehearsal marks.
- Right Column (Context Drawers & Tool Panels): Collapsible slide-out panels for Dynamics automation, Reaticulate banks, Tempo maps, Clef palettes, Key signatures, Pattern browser, Settings, and Page Print layout.

### 1.3 Window Resizing & Docking

REAPER-Notator can run as a floating window or docked directly into any REAPER docker (bottom, top, left, right, or multi-tabbed). The score canvas dynamically scales according to the zoom factor (adjustable from 0.6x to 2.0x), preserving crisp vector typography at all DPI scaling factors.

---

## Chapter 2: Top Toolbar & Global Navigation

### 2.1 Title & Version Indicator

Located in the upper left corner, displaying 'REAPER Notator' alongside the active build and semantic version number (e.g. v1.0.1). When running in a developer environment, Notator automatically detects and displays the active Git commit hash.

### 2.2 Transport & Playhead Controls

Functions:
- Rewind (|<): Instantly returns REAPER's edit cursor to measure 1.0 (time 0.0s).
- Play / Pause (> / ||): Starts timeline playback or pauses at the current cursor position. Key shortcut: Space.
- Stop: Halts playback and resets playhead according to REAPER's project settings.
DAW Effect: Calls REAPER's CSurf_OnPlay, CSurf_OnStop, and SetEditCurPos directly, maintaining sample-accurate alignment with REAPER's master audio engine.

### 2.3 Timeline & Meter Displays

Functions:
- Measure.Beat Display: Real-time read-out of playhead position in musical bars, beats, and quarter-note ticks (e.g. '004.01.00').
- Time Signature Indicator: Active project meter (e.g. 4/4, 3/4, 6/8, 7/8).
- BPM Indicator: Project master tempo at the current playhead position.
DAW Effect: Evaluates TimeMap_GetTimeSigAtTime on every frame to mirror timeline accelerandos, ritardandos, and time signature changes.

### 2.4 Audition Preview (Note Audio on Click)

Function: When enabled (speaker icon), clicking or vertically dragging any note on the canvas triggers an immediate acoustic preview sound.
DAW Effect: Sends instantaneous MIDI Note-On and scheduled Note-Off events to the active track's virtual instrument synth via REAPER's Audio Preview API.

### 2.5 Follow Playhead (Auto-Scroll)

Function: When active, the score canvas scrolls horizontally in real time to keep the active playback cursor centered in the viewport.

### 2.6 View Mode Selector

Functions:
- Auto: Automatically detects instrument clef based on track naming heuristics and pitch registers.
- Treble Only: Forces single G-clef staff rendering.
- Bass Only: Forces single F-clef staff rendering.
- Grand Staff: Renders classic piano/harp grand staff (Treble upper, Bass lower) connected by curly brace.

### 2.7 Track Picker & Visibility Filters

Function: Opens a multi-track routing popover allowing the user to select which REAPER tracks are currently visible, focused, or edited on the score canvas.

---

## Chapter 3: Score Canvas & Note Editing Engine

### 3.1 Note Entry & Pitch Snapping

Functions:
- Click on Staff: Inserts a new note with the duration selected in the sidebar at the nearest diatonic line or space.
- Ledger Lines: When moving beyond the 5 staff lines, Notator automatically calculates and renders standard-compliant ledger lines above or below the staff.
DAW Effect: Inserts a new MIDI note event into the focused track's active MIDI take via REAPER's MIDI_InsertNote API.

### 3.2 Note Duration & Augmentation Dots

Functions:
- Note Values: Supports 1/1 (Whole), 1/2 (Half), 1/4 (Quarter), 1/8 (Eighth), 1/16 (16th), and 1/32 (32nd) notes.
- Augmentation Dot: Toggles 1.5x duration expansion. A dotted quarter note spans 1.5 quarter notes (3 eighths).
DAW Effect: Sets note start and end positions accurately in Quarter Note (QN) timeline units.

### 3.3 Accidentals (Sharps, Flats, Naturals)

Functions:
- Flat (b): Decreases chromatic pitch by 1 semitone (-1).
- Natural (nat): Cancels preceding sharp/flat accidentals according to Western music engraving conventions (0).
- Sharp (#): Increases chromatic pitch by 1 semitone (+1).
DAW Effect: Transposes the underlying MIDI note number (0-127) and tags visual notation accidentals.

### 3.4 Note Manipulation (Move, Pitch, Length)

Functions:
- Horizontal Drag: Moves notes forward or backward in time, snapping to the selected rhythmic grid (e.g. 1/4, 1/8, 1/16).
- Vertical Drag: Transposes note pitch chromatically. Moving noteheads automatically updates accidentals.
- End-Edge Drag: Lengthens or shortens note duration by pulling the right edge of the notehead.
- Arrow Keys: Up/Down transposes by semitones (Shift+Up/Down by octaves). Left/Right moves by grid increments.
DAW Effect: Calls MIDI_SetNote to update pitch, QN start, and QN end in real time with undo history.

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

### 3.7 Standard Gould Rests

Functions:
- Empty Measure Rests: Empty measures automatically display a centered whole-measure rest glyph.
- Rhythmic Rest Decomposition: Gaps between notes decompose into standard rests (quarter, eighth, 16th rests) strictly aligned to the meter division.

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

### 6.1 Reaticulate Bank Auto-Discovery

Functions: REAPER-Notator automatically scans REAPER's user directory for Reaticulate sound bank definitions (Reaticulate.reabank). When a track is selected, Notator matches track names (e.g. 'Violin I', 'Cello', 'Horns') to corresponding library banks.

### 6.2 Visual Playing Technique Glyphs

Functions: Provides an instant-access drawer for score playing techniques:
- Staccato (dot), Staccatissimo (wedge), Accent (>), Marcato (^), Tenuto (-)
- Pizzicato (pizz.), Arco, Con Sordino, Sul Ponticello, Col Legno, Tremolo, Harmonics (o)
Placement: Notator automatically positions articulation marks above noteheads for stems-down notes, or below noteheads for stems-up notes according to standard engraving conventions.

### 6.3 DAW Automation Impact

DAW Effect: Inserting an articulation writes:
  1. REAPER Type 15 notation text events into the MIDI take for persistent score recall.
  2. MIDI CC0 / CC32 Bank Select and Program Change messages at the note start position to trigger sample library key switches in Kontakt, Spitfire, VSL, Orchestral Tools, etc.

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

## Chapter 10: Orchestral Pattern Browser

### 10.1 Built-in Cinematic Pattern Library

Functions: Slide-out pattern browser organized into 8 orchestral categories:
  1. Strings Staccato (rhythmic ostinatos, driving cinema pulses)
  2. Strings Pizzicato (delicate melodic textures)
  3. Brass Blockbuster (epic fanfares, heroic intervals)
  4. Cinematic Melodies (expressive themes)
  5. Counter Melodies (supporting orchestral counterpoint)
  6. Woodwinds Textures (rapid arpeggios, atmospheric runs)
  7. Cinematic Piano (flowing ballads, introspective etudes)
  8. Custom User Patterns (user-created motifs)

### 10.2 One-Click Insertion & Capture

Functions:
- Insert Pattern: Clicking any pattern card instantly inserts the musical motif at REAPER's edit cursor on the selected track.
- Capture Selection: Select any group of notes on your canvas and click 'Save Pattern' to store it in your custom library for future scoring projects.

---

## Chapter 11: Text Items & Score Annotations

### 11.1 Rehearsal Marks & Structural Tags

Functions: Pressing Ctrl+T inserts a floating score text item at the cursor. Supports rehearsal letters ([A], [B], [C]), section titles ('Verse', 'Chorus', 'Bridge'), and orchestration performance instructions ('Molto espressivo', 'Solo', 'Tutti').

### 11.2 In-Place Editing & Typography

Functions: Double-click any text item to open an in-place editing field. Configure font size, standard/italic/bold styling, and staff attachment anchor points.

---

## Chapter 12: MusicXML 4.0 Import & Export

### 12.1 Interoperability Standard

Functions: MusicXML 4.0 is the universal interchange format between professional notation software. REAPER-Notator includes a dedicated MusicXML parser and exporter written in pure Lua.

### 12.2 Importing Scores

Functions: Click 'Import MusicXML' to load orchestral scores created in external notation programs. Notator parses parts, measures, time signatures, key signatures, pitch data, dynamics, and tempo markers, creating fully arranged tracks and MIDI items directly in REAPER.

### 12.3 Exporting Scores

Functions: Click 'Export MusicXML' to save your REAPER project as a standard .musicxml file ready for publication, live orchestral recording sessions, or further engraving.

---

## Chapter 13: Page Print & PDF Score Layout

### 13.1 Print Modal & Layout Setup

Functions: Dedicated Print Settings dialog accessible from the top bar tools:
- Paper Sizes: Standard A4, A3, Letter, Tabloid.
- Orientation: Landscape (standard for orchestral conductor scores) or Portrait (standard for solo instrumental parts).
- Systems per Page: Configure how many measures or systems appear per page.

### 13.2 Metadata & Publishing Header

Functions: Inscribe Title, Subtitle, Composer, Arranger, and Copyright notices in classical engraving typography.

---

## Chapter 14: Keyboard Shortcuts & Quick Reference

### 14.1 Comprehensive Hotkey Matrix

Quick reference table for high-speed score entry:

| Key / Shortcut | Action | Description |
| :--- | :--- | :--- |
| Space | Play / Pause | Starts or stops timeline playback |
| Delete / Backspace | Delete | Deletes selected notes, dynamics, tempo marks, or lines |
| Esc | Clear Selection | Deselects all active items and clears focus |
| Up / Down Arrows | Transpose Pitch | Moves selected notes up/down by 1 semitone |
| Shift + Up / Down | Octave Shift | Moves selected notes up/down by 1 octave (12 semitones) |
| Left / Right Arrows | Nudge Position | Shifts notes horizontally by the active grid increment |
| Shift + Left / Right | Resize Duration | Shortens or lengthens selected notes by grid step |
| X | Invert Stem | Flips note stem direction (up <-> down) |
| 1 .. 6 | Rhythmic Values | 1=Whole, 2=Half, 3=Quarter, 4=Eighth, 5=16th, 6=32nd |
| . (Period) | Toggle Dot | Toggles dotted note duration (1.5x) |
| - / 0 / = | Accidentals | -=Flat (b), 0=Natural (nat), ==Sharp (#) |
| T | Tie Note | Toggles tie / Bindebogen to adjacent note |
| S | Slur Phrase | Toggles legato slur over selected passage |
| A | Accent | Toggles accent mark (>) on selected note |
| Ctrl + T | New Text Item | Creates a floating text annotation at cursor position |
| Ctrl + S | Save Project | Triggers REAPER project save |

---


#!/usr/bin/env python3
"""
REAPER-Notator - Complete User Manual & Documentation Generator
Generates:
  1. docs/user_manual.md (GitHub Markdown documentation)
  2. docs/reaper_notator_user_manual.pdf (Full publication-grade PDF manual)
"""

import os
import re
import datetime
from fpdf import FPDF
from fpdf.enums import XPos, YPos

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS_DIR = os.path.join(REPO_ROOT, "docs")
os.makedirs(DOCS_DIR, exist_ok=True)

MD_PATH = os.path.join(DOCS_DIR, "user_manual.md")
PDF_PATH = os.path.join(DOCS_DIR, "reaper_notator_user_manual.pdf")

def get_version():
    ver_file = os.path.join(REPO_ROOT, "modules", "version.lua")
    if os.path.exists(ver_file):
        with open(ver_file, "r", encoding="utf-8") as vf:
            content = vf.read()
            m_maj = re.search(r"major\s*=\s*(\d+)", content)
            m_min = re.search(r"minor\s*=\s*(\d+)", content)
            m_pat = re.search(r"patch\s*=\s*(\d+)", content)
            if m_maj and m_min and m_pat:
                return f"{m_maj.group(1)}.{m_min.group(1)}.{m_pat.group(1)}"
    return "1.3.6"

VERSION = get_version()

MANUAL_DATA = [
    {
        "chapter": 1,
        "title": "Introduction & Interface Architecture",
        "sections": [
            {
                "heading": "1.1 Overview & Vision",
                "text": "REAPER-Notator is a native, professional music scoring, notation editing, and engraving environment built directly into Cockos REAPER using ReaImGui and standard SMuFL (Standard Music Font Layout) Bravura vector glyphs. Unlike external scoring applications, Notator runs directly inside REAPER's audio engine and timeline, providing instantaneous two-way synchronization between visual music notation and underlying REAPER MIDI takes, CC automation, and tempo maps."
            },
            {
                "heading": "1.2 The Three-Column Workspace Layout",
                "text": "The user interface is designed around an ergonomic three-column layout:\n\n"
                        "- Left Column (Sidebar Palette): Quick tools for note entry modes (pointer, pencil, text, eraser), rhythmic durations (whole to 32nd notes), augmentation dots, accidentals, tuplets, stem orientation, and articulation toggles.\n"
                        "- Center Column (Score Canvas): Infinite interactive notation canvas displaying visual staves, barlines, noteheads, stems, beams, ties, slurs, lyrics, and rehearsal marks.\n"
                        "- Right Column (Context Drawers & Tool Panels): Collapsible slide-out panels for Dynamics automation, Reaticulate banks, Tempo maps, Clef palettes, Key signatures, Pattern browser, and Settings."
            },
            {
                "heading": "1.3 Window Resizing & Docking",
                "text": "REAPER-Notator can run as a floating window or docked directly into any REAPER docker (bottom, top, left, right, or multi-tabbed). The score canvas dynamically scales according to the zoom factor (adjustable from 0.6x to 2.0x), preserving crisp vector typography at all DPI scaling factors."
            }
        ]
    },
    {
        "chapter": 2,
        "title": "Top Toolbar & Global Navigation",
        "sections": [
            {
                "heading": "2.1 Title & Version Indicator",
                "text": f"Located in the upper left corner, displaying 'REAPER Notator' alongside the active build and semantic version number (v{VERSION}). When running in a developer environment, Notator automatically detects and displays the active Git commit hash."
            },
            {
                "heading": "2.2 Transport & Playhead Controls",
                "text": "Functions:\n"
                        "- Rewind (|<): Instantly returns REAPER's edit cursor to measure 1.0 (time 0.0s).\n"
                        "- Play / Pause (> / ||): Starts timeline playback or pauses at the current cursor position. Key shortcut: Space.\n"
                        "- Stop: Halts playback and resets playhead according to REAPER's project settings.\n"
                        "DAW Effect: Calls REAPER's CSurf_OnPlay, CSurf_OnStop, and SetEditCurPos directly, maintaining sample-accurate alignment with REAPER's master audio engine."
            },
            {
                "heading": "2.3 Timeline & Meter Displays",
                "text": "Functions:\n"
                        "- Measure.Beat Display: Real-time read-out of playhead position in musical bars, beats, and quarter-note ticks (e.g. '004.01.00').\n"
                        "- Time Signature Indicator: Active project meter (e.g. 4/4, 3/4, 6/8, 7/8).\n"
                        "- BPM Indicator: Project master tempo at the current playhead position.\n"
                        "DAW Effect: Evaluates TimeMap_GetTimeSigAtTime on every frame to mirror timeline accelerandos, ritardandos, and time signature changes."
            },
            {
                "heading": "2.4 Audition Preview (Note Audio on Click)",
                "text": "Functions:\n"
                        "- Single-Note Audition: Clicking or vertically dragging any note on the canvas triggers an immediate acoustic preview sound, arbitrated to audition strictly the single hovered note even in dense chords or adjacent systems.\n"
                        "- Track Audition Isolation: Auditioning automatically isolates the target track and temporarily disarms concurrent project tracks, preventing Virtual MIDI Keyboard crosstalk across unrelated instruments sharing the same pitch/register.\n"
                        "- Articulation Chasing: The engine scans the project timeline from measure 1 up to the clicked note position to chase active Program Changes and note-level articulation marks (Staccato, Marcato, Tenuto, Pizzicato, etc.), dispatching the authentic Reaticulate bank and patch.\n"
                        "- Zero-Latency First Click: Implements a 1-frame pre-switch mechanism for Bank/Program Change before Note-On, eliminating sampler group switching lag so notes sound cleanly on the very first click.\n"
                        "DAW Effect: Dispatches synchronized Bank Select, Program Change, and instantaneous MIDI Note-On/scheduled Note-Off events to the active track's virtual instrument synth via REAPER's Audio Preview API."
            },
            {
                "heading": "2.5 Follow Playhead (Auto-Scroll)",
                "text": "Function: When active, the score canvas scrolls horizontally in real time to keep the active playback cursor centered in the viewport."
            },
            {
                "heading": "2.6 View Mode Selector",
                "text": "Functions:\n"
                        "- Auto: Automatically detects instrument clef based on track naming heuristics and pitch registers.\n"
                        "- Treble Only: Forces single G-clef staff rendering.\n"
                        "- Bass Only: Forces single F-clef staff rendering.\n"
                        "- Grand Staff: Renders classic piano/harp grand staff (Treble upper, Bass lower) connected by curly brace."
            },
            {
                "heading": "2.7 Track Picker & Visibility Filters",
                "text": "Function: Opens a multi-track routing popover allowing the user to select which REAPER tracks are currently visible, focused, or edited on the score canvas."
            },
            {
                "heading": "2.8 Multi-Voice System & Auto-Voice Overlap Splitting",
                "text": "Functions:\n"
                        "- 16 Polyphonic Voices: Maps MIDI channels 0-15 to 16 distinct engraving colors with configurable ghost voice opacity (5% to 100%).\n"
                        "- Auto-Voice: Intelligently analyzes the entire track for polyphonic overlaps and distributes them to channels 1-16.\n"
                        "- Auto-Split on Selection: Splits selected chordal intervals across independent voices with automatic opposite stem orientations."
            },
            {
                "heading": "2.9 Settings Modal & Unified Dark Mode Inversion",
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
                "heading": "3.2 Note Duration & Augmentation Dots",
                "text": "Functions:\n"
                        "- Note Values: Supports 1/1 (Whole), 1/2 (Half), 1/4 (Quarter), 1/8 (Eighth), 1/16 (16th), and 1/32 (32nd) notes.\n"
                        "- Augmentation Dot: Toggles 1.5x duration expansion. A dotted quarter note spans 1.5 quarter notes (3 eighths).\n"
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
                "heading": "3.4 Note Manipulation (Move, Pitch, Length)",
                "text": "Functions:\n"
                        "- Horizontal Drag: Moves notes forward or backward in time, snapping to the selected rhythmic grid (e.g. 1/4, 1/8, 1/16).\n"
                        "- Vertical Drag: Transposes note pitch chromatically. Moving noteheads automatically updates accidentals.\n"
                        "- End-Edge Drag: Lengthens or shortens note duration by pulling the right edge of the notehead.\n"
                        "- Arrow Keys: Up/Down transposes by semitones (Shift+Up/Down by octaves). Left/Right moves by grid increments.\n"
                        "DAW Effect: Calls MIDI_SetNote to update pitch, QN start, and QN end in real time with undo history."
            },
            {
                "heading": "3.5 Multi-Note Selection & Marquee Tool",
                "text": "Functions:\n"
                        "- Marquee / Box Selection: Click and drag on empty canvas space to draw a selection rectangle encompassing multiple notes across measures and staves.\n"
                        "- Shift + Click: Add individual notes to selection.\n"
                        "- Delete / Backspace: Deletes all currently selected notes simultaneously.\n"
                        "DAW Effect: Multi-note batch deletion and batch transposition with atomic REAPER undo block."
            },
            {
                "heading": "3.6 Second-Interval Collision & Voice Separation",
                "text": "Functions:\n"
                        "- Second Intervals (Seconds): Notes placed on adjacent staff degrees in the same chord automatically offset horizontally (left/right) according to Elaine Gould engraving rules to prevent notehead collisions.\n"
                        "- Multi-Voice Stems: Polyphonic voices automatically flip stems (Voice 1 stems up, Voice 2 stems down)."
            },
            {
                "heading": "3.7 Standard Gould Rests",
                "text": "Functions:\n"
                        "- Empty Measure Rests: Empty measures automatically display a centered whole-measure rest glyph.\n"
                        "- Rhythmic Rest Decomposition: Gaps between notes decompose into standard rests (quarter, eighth, 16th rests) strictly aligned to the meter division."
            },
            {
                "heading": "3.8 Non-Mouse Keyboard Note Navigation & Selection Expansion",
                "text": "Functions:\n"
                        "- Alt + Left / Right Arrows: Sequential note navigation along the timeline without mouse usage, selecting the previous or next note.\n"
                        "- Alt + Shift + Left / Right Arrows: Extends and expands note selections chronologically across the measure and score.\n"
                        "- Auto-Scroll Synchronization: When Follow Playhead / Auto-Scroll is active, the score canvas smoothly glides to keep newly selected notes centered in view."
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
                "heading": "6.1 Reaticulate Bank Auto-Discovery",
                "text": "Functions: REAPER-Notator automatically scans REAPER's user directory for Reaticulate sound bank definitions (Reaticulate.reabank). When a track is selected, Notator matches track names (e.g. 'Violin I', 'Cello', 'Horns') to corresponding library banks."
            },
            {
                "heading": "6.2 Visual Playing Technique Glyphs",
                "text": "Functions: Provides an instant-access drawer for score playing techniques:\n"
                        "- Staccato (dot), Staccatissimo (wedge), Accent (>), Marcato (^), Tenuto (-)\n"
                        "- Pizzicato (pizz.), Arco, Con Sordino, Sul Ponticello, Col Legno, Tremolo, Harmonics (o)\n"
                        "Placement: Notator automatically positions articulation marks above noteheads for stems-down notes, or below noteheads for stems-up notes according to standard engraving conventions."
            },
            {
                "heading": "6.3 DAW Automation Impact",
                "text": "DAW Effect: Inserting an articulation writes:\n"
                        "  1. REAPER Type 15 notation text events into the MIDI take for persistent score recall.\n"
                        "  2. MIDI CC0 / CC32 Bank Select and Program Change messages at the note start position to trigger sample library key switches in Kontakt, Spitfire, VSL, Orchestral Tools, etc."
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
                "heading": "6.5 Playback Troubleshooting & The '⚡ Fix Playback' Workaround",
                "text": "Functions & Troubleshooting Workaround:\n"
                        "- The Problem (Cross-Track Duplication Desync): In REAPER's arrange view, composers frequently duplicate or copy MIDI items across tracks (e.g. duplicating a violin phrase down to celli or double basses). When an item is copied in REAPER, REAPER duplicates the underlying MIDI events verbatim. However, different sample libraries or instrument sections utilize different Reaticulate sound banks (for example, a Violin bank might assign PC 40 to Short/Staccato, while a Celli or Double Bass bank might use PC 49 for Staccato Dig). Because the duplicated item retains the old track's Program Changes and old auto-chase markers, playback on the new track breaks, produces silent or mismatched samples, or becomes stuck in an unwanted articulation.\n"
                        "- The Solution ('⚡ Fix Playback' Engine): To resolve this without manual MIDI editing, REAPER-Notator provides an automated playback reconciler via the '⚡ Fix Playback' button in the Articulations drawer.\n"
                        "- Intelligent Re-Mapping: Clicking '⚡ Fix Playback' scans the selected notes (or the selected MIDI item, or all items on the active track). Notator parses the persistent score notation markers (`NOTE <pitch> <chan> a <art_id>`), inspects the active track's Reaticulate bank, cleans out outdated or mismatched Program Changes from previous tracks, inserts the correct Bank Select and Program Change numbers for the current track's sound library, and re-calculates all auto-chase return events.\n"
                        "- Handling Unsupported Articulations (e.g. Library Lacks Staccato): If the destination track's instrument or Reaticulate bank does not provide the requested articulation (for example, duplicating a violin staccato passage onto a flute, piano, synth, or library that lacks dedicated short patches), '⚡ Fix Playback' completely purges all foreign Program Changes (such as 121-0-42) and Bank Selects (CC0 / CC32) across the take, removes unsupported notation tags, clears obsolete chase events, and ensures the track's default base patch (Long / Sustain) is engaged once at the passage start so the notes play cleanly without stuck keyswitches.\n"
                        "- Step-by-Step Workaround for Duplicated Items:\n"
                        "    1. Duplicate or paste the MIDI item onto a new track in REAPER's arrange view.\n"
                        "    2. Select the duplicated MIDI item or notes in REAPER-Notator.\n"
                        "    3. Open the Articulations drawer on the right sidebar.\n"
                        "    4. Left-click '⚡ Fix Playback'.\n"
                        "    Playback immediately re-synchronizes to the destination track's virtual instrument bank with pristine staccato and sustain transitions.\n"
                        "- Idempotency & Safe Multi-Click: The '⚡ Fix Playback' command is fully idempotent. If playback is already synchronized, repeating the click will never inadvertently erase or corrupt existing articulations.\n"
                        "- Fix of Last Resort (Centered Popup Confirmation Modal):\n"
                        "    * How It Works: When '⚡ Fix Playback' is clicked while playback is already synchronized (or right-clicked at any time), REAPER-Notator opens the dedicated '⚡ Fix Playback: Fix of Last Resort' confirmation modal window. The dialog automatically centers itself on the screen over the active score display.\n"
                        "    * Target Confirmation: The modal clearly displays the target track name and confirms that note articulations currently match the active instrument sound bank.\n"
                        "    * Emergency Reset Action: If playback remains stuck, silent, or corrupted by external MIDI CC messages, clicking the red button '[ 🧹 Purge All Articulations (Last Resort) ]' completely strips all articulation glyphs, Type 15 notation tags (`NOTE <pitch> <chan> a <art_id>`), Bank Selects (CC0 / CC32), keyswitch Program Changes, and auto-chase return events (`NOTATOR_CHASE`). It then re-engages the default base patch (Long / Sustain) at the item start, resetting the track to clean default sustain playback.\n"
                        "    * Safe Cancellation: Clicking '[ ✕ Cancel (Keep Articulations) ]' or pressing Escape immediately dismisses the modal without altering any notes, articulations, or MIDI events."
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
                "heading": "10.1 Curated 1,200 Pattern Factory Library",
                "text": "Functions: Slide-out pattern browser organized into 8 orchestral categories (1,200 factory patterns total):\n"
                        "- 1. Strings Staccato (150x driving cinema pulses, ostinatos)\n"
                        "- 2. Strings Pizzicato (150x delicate plucks, agile grooves)\n"
                        "- 3. Brass Blockbuster (150x epic horn fanfares, low brass power)\n"
                        "- 4. Cinematic Melodies (150x soaring lyrical themes)\n"
                        "- 5. Counter Melodies (150x rich orchestral counterpoint)\n"
                        "- 6. Woodwinds Textures (150x runs, fluttering textures)\n"
                        "- 7. Cinematic Piano (150x flowing arpeggios, grand staff ballads)\n"
                        "- 8. Ancient Greek & Roman Harp (150x modal hymns, Delphic paeans, Sapphic strophes, Dorian/Phrygian/Lydian processions)\n"
                        "- 9. Custom User Patterns (user-captured motifs and items)"
            },
            {
                "heading": "10.2 One-Click Insertion, Drag & Drop & Audio Audition",
                "text": "Functions:\n"
                        "- Drag & Drop: Drag any pattern tile directly onto the score canvas with golden ghost-preview.\n"
                        "- Audio Audition: Audition motifs in real-time through any selected REAPER instrument track.\n"
                        "- Capture Selection: Select any REAPER MIDI item and click 'Capture REAPER Item' to store it permanently."
            },
            {
                "heading": "10.3 In-App 1-Click Factory Library Downloader",
                "text": "Functions: Integrated one-click downloader built into the browser toolbar and empty-state banner.\n"
                        "- 1-Click Install: Downloads and unpacks the entire 1,200 pattern library (820 KB compressed) in one second without leaving REAPER.\n"
                        "- Offline Archive Support: Automatically unpacks local patterns.zip on first launch if present."
            }
        ]
    },
    {
        "chapter": 11,
        "title": "Rehearsal Marks, Fermatas & Score Tools",
        "sections": [
            {
                "heading": "11.1 Dynamic Rehearsal Marks & Interactive Drag-and-Drop",
                "text": "Functions: Professional structural navigation and rehearsal tagging:\n"
                        "- Dedicated Rehearsal Lane: Positioned cleanly between the Chord Track lane and Bar Numbers, providing unobstructed structural visibility across all systems.\n"
                        "- Interactive Mouse Drag & Drop: Click and drag any rehearsal mark directly along the top lane to move it to any measure. During dragging, the mark follows the cursor with a real-time vertical snap guide line and target bar indicator ('Bar X').\n"
                        "- Auto-Sequencing: Marks automatically sequence as [A], [B], [C]... or [1], [2], [3]... Moving or inserting marks chronologically re-indexes all subsequent marks across the score.\n"
                        "- Edit-Cursor Placement: The Tools Drawer dynamically detects the active REAPER edit cursor position, displaying explicit actions like 'Add Letter Mark at Bar X' and 'Add Number Mark at Bar X'.\n"
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
                        "- Arpeggio Strums: Realistic harp and guitar roll simulation with upward/downward wavy line engraving and non-destructive playback micro-offset.\n"
                        "- Quantize Tools: Integrated triplet, swing, and 1/4 through 1/64 grid snapping directly inside the Tools drawer."
            },
            {
                "heading": "11.4 Floating Text Items & In-Place Editing",
                "text": "Functions: Pressing Ctrl+T inserts a floating score text item at the cursor. Double-click any text item to open an in-place editing field. Configure font size, standard/italic/bold styling, and staff attachment anchor points."
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
                "heading": "12.2 Importing Scores & Articulation Auto-Mapping",
                "text": "Functions:\n"
                        "- Orchestral Score Import: Click 'Import MusicXML' to load orchestral scores created in external notation programs. Notator parses parts, measures, time signatures, key signatures, pitch data, dynamics, lyrics, and tempo markers, creating fully arranged tracks and MIDI items directly in REAPER.\n"
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
            }
        ]
    },
    {
        "chapter": 15,
        "title": "Keyboard Shortcuts & Quick Reference",
        "sections": [
            {
                "heading": "15.1 Comprehensive Hotkey Matrix",
                "text": "Quick reference table for high-speed score entry:\n\n"
                        "| Key / Shortcut | Action | Description |\n"
                        "| :--- | :--- | :--- |\n"
                        "| Space | Play / Pause | Starts or stops timeline playback |\n"
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
                        "| . (Period) | Toggle Dot | Toggles dotted note duration (1.5x) |\n"
                        "| - / 0 / = | Accidentals | -=Flat (b), 0=Natural (nat), ==Sharp (#) |\n"
                        "| T | Tie Note | Toggles tie / Bindebogen to adjacent note |\n"
                        "| S | Slur Phrase | Toggles legato slur over selected passage |\n"
                        "| A | Accent | Toggles accent mark (>) on selected note |\n"
                        "| Ctrl + T | New Text Item | Creates a floating text annotation at cursor position |\n"
                        "| Ctrl + S | Save Project | Triggers REAPER project save |"
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
    ("Compatibility:", "Cockos REAPER v7.0+ (Windows, macOS, Linux) with ReaImGui"),
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
        
        for l in lines:
            line_str = l.strip()
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

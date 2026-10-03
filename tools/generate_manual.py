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
                        "- Right Column (Context Drawers & Tool Panels): Collapsible slide-out panels for Dynamics automation, Reaticulate banks, Tempo maps, Clef palettes, Key signatures, Pattern browser, Settings, and Page Print layout."
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
                "text": "Located in the upper left corner, displaying 'REAPER Notator' alongside the active build and semantic version number (e.g. v1.0.1). When running in a developer environment, Notator automatically detects and displays the active Git commit hash."
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
                "text": "Function: When enabled (speaker icon), clicking or vertically dragging any note on the canvas triggers an immediate acoustic preview sound.\n"
                        "DAW Effect: Sends instantaneous MIDI Note-On and scheduled Note-Off events to the active track's virtual instrument synth via REAPER's Audio Preview API."
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
        "title": "Orchestral Pattern Browser",
        "sections": [
            {
                "heading": "10.1 Built-in Cinematic Pattern Library",
                "text": "Functions: Slide-out pattern browser organized into 8 orchestral categories:\n"
                        "  1. Strings Staccato (rhythmic ostinatos, driving cinema pulses)\n"
                        "  2. Strings Pizzicato (delicate melodic textures)\n"
                        "  3. Brass Blockbuster (epic fanfares, heroic intervals)\n"
                        "  4. Cinematic Melodies (expressive themes)\n"
                        "  5. Counter Melodies (supporting orchestral counterpoint)\n"
                        "  6. Woodwinds Textures (rapid arpeggios, atmospheric runs)\n"
                        "  7. Cinematic Piano (flowing ballads, introspective etudes)\n"
                        "  8. Custom User Patterns (user-created motifs)"
            },
            {
                "heading": "10.2 One-Click Insertion & Capture",
                "text": "Functions:\n"
                        "- Insert Pattern: Clicking any pattern card instantly inserts the musical motif at REAPER's edit cursor on the selected track.\n"
                        "- Capture Selection: Select any group of notes on your canvas and click 'Save Pattern' to store it in your custom library for future scoring projects."
            }
        ]
    },
    {
        "chapter": 11,
        "title": "Text Items & Score Annotations",
        "sections": [
            {
                "heading": "11.1 Rehearsal Marks & Structural Tags",
                "text": "Functions: Pressing Ctrl+T inserts a floating score text item at the cursor. Supports rehearsal letters ([A], [B], [C]), section titles ('Verse', 'Chorus', 'Bridge'), and orchestration performance instructions ('Molto espressivo', 'Solo', 'Tutti')."
            },
            {
                "heading": "11.2 In-Place Editing & Typography",
                "text": "Functions: Double-click any text item to open an in-place editing field. Configure font size, standard/italic/bold styling, and staff attachment anchor points."
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
                "heading": "12.2 Importing Scores",
                "text": "Functions: Click 'Import MusicXML' to load orchestral scores created in external notation programs. Notator parses parts, measures, time signatures, key signatures, pitch data, dynamics, and tempo markers, creating fully arranged tracks and MIDI items directly in REAPER."
            },
            {
                "heading": "12.3 Exporting Scores",
                "text": "Functions: Click 'Export MusicXML' to save your REAPER project as a standard .musicxml file ready for publication, live orchestral recording sessions, or further engraving."
            }
        ]
    },
    {
        "chapter": 13,
        "title": "Page Print & PDF Score Layout",
        "sections": [
            {
                "heading": "13.1 Print Modal & Layout Setup",
                "text": "Functions: Dedicated Print Settings dialog accessible from the top bar tools:\n"
                        "- Paper Sizes: Standard A4, A3, Letter, Tabloid.\n"
                        "- Orientation: Landscape (standard for orchestral conductor scores) or Portrait (standard for solo instrumental parts).\n"
                        "- Systems per Page: Configure how many measures or systems appear per page."
            },
            {
                "heading": "13.2 Metadata & Publishing Header",
                "text": "Functions: Inscribe Title, Subtitle, Composer, Arranger, and Copyright notices in classical engraving typography."
            }
        ]
    },
    {
        "chapter": 14,
        "title": "Keyboard Shortcuts & Quick Reference",
        "sections": [
            {
                "heading": "14.1 Comprehensive Hotkey Matrix",
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
    md.write(f"**Version:** 1.0.1  \n**Date:** {datetime.datetime.now().strftime('%Y-%m-%d')}  \n**License:** GNU General Public License v3.0  \n\n")
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
        self.cell(self.epw * 0.3, 7, "v1.0.1", align="R", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
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
    ("Version:", "v1.0.1 (Production Release)"),
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
    pdf.cell(pdf.epw - 8, 8, f"Chapter {chap['chapter']}: {chap['title']}", new_x=XPos.LMARGIN, new_y=YPos.NEXT)
    pdf.set_y(curr_y + 14)
    
    for sec in chap["sections"]:
        # Check space before section heading
        if pdf.get_y() > 255:
            pdf.add_page()
            pdf.ln(5)
            
        # Section Heading
        pdf.set_font("Helvetica", "B", 10)
        pdf.set_text_color(234, 88, 12) # Amber / Orange
        pdf.cell(pdf.epw, 6, sec["heading"], new_x=XPos.LMARGIN, new_y=YPos.NEXT)
        pdf.ln(1)
        
        # Section Body
        pdf.set_font("Helvetica", "", 8.5)
        pdf.set_text_color(30, 41, 59)
        
        raw_text = sec["text"]
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
            if line_str.startswith("-") or line_str.startswith("*") or line_str.startswith("-"):
                bullet_text = line_str.lstrip("-*-").strip()
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
                pdf.cell(col_widths[col_idx], 6, f" {col_name}", 1, 0, "L", fill=True)
            pdf.ln(6)
            
            pdf.set_font("Helvetica", "", 8)
            for r_idx, row in enumerate(table_rows[1:]):
                bg = 255 if r_idx % 2 == 0 else 248
                pdf.set_fill_color(bg, bg, bg)
                pdf.set_text_color(30, 41, 59)
                for col_idx, cell in enumerate(row):
                    pdf.cell(col_widths[col_idx], 5.2, f" {cell}", 1, 0, "L", fill=True)
                pdf.ln(5.2)
            pdf.ln(2)
            
        pdf.ln(3)

pdf.output(PDF_PATH)
print(f"Generated PDF manual successfully: {PDF_PATH}")

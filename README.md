# REAPER-Notator

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![REAPER](https://img.shields.io/badge/REAPER-v7.0+-orange.svg)](https://www.reaper.fm/)
[![ReaImGui](https://img.shields.io/badge/ReaImGui-v0.9+-green.svg)](https://github.com/cfillion/reaimgui)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20macOS%20%7C%20Linux-lightgrey.svg)](#)

> **REAPER-Notator** is a native, professional music notation, score editing, and engraving suite built directly for Cockos REAPER using ReaImGui and standard SMuFL vector glyphs.

---

## Overview

REAPER-Notator brings high-end music engraving and scoring workflows straight into REAPER's timeline without external software bridges or unwieldy window switching. It combines strict adherence to classical western music engraving standards (*Gardner Read*, *Elaine Gould / Behind Bars*) with deep DAW automation integration.

---

## Key Features

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
  - Score Tools drawer: Make Notes Legato, Auto Voice & Auto Voice on Selection, and integrated Quantize Tools.
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

## Installation

### Method 1: Via ReaPack (Recommended)

1. Ensure you have **ReaPack** installed in REAPER ([reapack.com](https://reapack.com/)).
2. In REAPER, go to:
   `Extensions` → `ReaPack` → `Import a repository...`
3. Enter the following repository URL:
   ```text
   https://raw.githubusercontent.com/A-intheCode/ReaperNotator/main/index.xml
   ```
4. Open `Extensions` → `ReaPack` → `Browse packages...`.
5. Search for `REAPER-Notator`, right-click on it, select **Install**, and click **Apply**.
6. Run `Script: reaper_native_notator.lua` from the REAPER Actions list (`?`).

### Method 2: Manual Installation

1. Clone or download this repository into your REAPER Scripts folder:
   - **Windows:** `%APPDATA%\REAPER\Scripts\REAPER-Notator`
   - **macOS:** `~/Library/Application Support/REAPER/Scripts/REAPER-Notator`
   - **Linux:** `~/.config/REAPER/Scripts/REAPER-Notator`
2. Open REAPER, press `?` to open the **Actions List**, click **New Action...** → **Load ReaScript...**, and select `reaper_native_notator.lua`.

---

## Requirements

- **Cockos REAPER** v7.0 or higher
- **ReaImGui** v0.9+ (available via ReaPack)
- **SWS / S&M Extension** (recommended)

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**.  
See the [LICENSE](LICENSE) file for details.

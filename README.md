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

- **Dynamic Automation & CC Engine**:
  - 10 standardized dynamic levels ($ppp$ through $fff$) mapped to customizable MIDI velocities and CC values.
  - Automated hairpin curves ($crescendo$ and $diminuendo$) with linear and exponential shaping.
  - Asymmetric **Bow Swell** curve generator with adjustable peak position per MIDI item.
  - Continuous controller automation across CC1 (Modulation), CC11 (Expression), and CC7 (Volume).

- **DAW & Articulation Integration**:
  - Seamless two-way integration with **Reaticulate** sound libraries and bank presets.
  - Articulation drawer with instant key switch / program change assignment.
  - Sustain and Holding pedal lane (CC64) with dual drag handles and break/retake notches.
  - Octave shift lines ($8^{va}$, $8^{vb}$, $15^{ma}$, $15^{mb}$).
  - Live timeline audition preview with mouse-hover pitch feedback.

- **Tempo & Time Signatures**:
  - Direct synchronization with REAPER's master tempo map.
  - Gradual tempo transitions (*accelerando*, *ritardando*) and metric modulations.

- **Score-Wide Fermatas & Rehearsal Marks (New in v1.4.0)**:
  - Score-wide vertical Fermatas (standard, short, long, very long) synchronized across all visible tracks.
  - Tempomap playback coupling with deterministic tempo-dip slowdown (1.25x to 3.0x) and automatic restoration.
  - Dynamic Rehearsal Marks ([A], [B], [C]...) with automatic re-sequencing on insertion, deletion, and movement.
  - Dedicated Rehearsal Lane positioned between the Chord Track lane and Bar Numbers.
  - Standard navigation symbols: Da Capo ($D.C.$ / $D.C. \text{ al Fine}$), Dal Segno ($D.S.$ / $D.S. \text{ al Coda}$), Segno, Coda, and Fine.
  - Arpeggiated chords with bezier wavy line engraving and non-destructive micro-strumming playback offset.
  - Full MusicXML 4.0 import and export support for fermatas, rehearsal marks, navigation, and arpeggios.

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

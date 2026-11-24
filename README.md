# REAPER Notator 3.3.5 (Exclusive Release)

[![License: Proprietary](https://img.shields.io/badge/License-Proprietary%20(All%20Rights%20Reserved)-red.svg)](LICENSE)
[![Version: 3.3.5](https://img.shields.io/badge/Version-3.3.5-gold.svg)](#)
[![REAPER](https://img.shields.io/badge/REAPER-v7.0+-orange.svg)](https://www.reaper.fm/)
[![ReaImGui](https://img.shields.io/badge/ReaImGui-v0.10%2B%20Required-brightgreen.svg)](https://github.com/cfillion/reaimgui)
[![Reaticulate](https://img.shields.io/badge/Reaticulate-Required-blueviolet.svg)](https://reaticulate.com/)

> **REAPER Notator 3.3.5** is a native, professional music notation, score editing, and engraving suite built directly for Cockos REAPER using ReaImGui and standard SMuFL vector glyphs.

> [!NOTE]
> **Platform Compatibility — Master Acoustic Studio (`Notator Acoustic Master` VST3):**
> - **REAPER Notator 3.3.5 (Score Editing, Engraving, Playback & Recording)** runs natively across **Windows, macOS, and Linux** (`REAPER v7.0+`, `ReaImGui v0.10+`, `Reaticulate`).
> - The built-in **Master Acoustic Studio (`Notator Acoustic Master` 64-bit VST3)** works **exclusively on Windows (x64) and macOS Universal2 (Intel & Apple Silicon)**. **Linux is not supported** (on Linux, the Mastering button in the Tools drawer is greyed out with the tooltip `"Linux not supported"`).

---

## What's New in v3.3.5

- **EdgeCase StaffPad MusicXML Import Fix & Unified Tie Consolidation:** Consolidates standard MusicXML `<tie>`/`<tied>` chains (cross-bar, syncopated & multi-bar) into single continuous MIDI notes—so Piano Roll, Velocity Lane & selection display unified sustained notes while Score Canvas auto-generates bar ties (with `<tied type="continue"/>`, cross-staff/`<backup>` resolution & tuplet-tie grid protection).
- **Flicker-Free Startup Splash Screen & Incremental Pattern Scan:** Launches immediately (`< 20 ms`) with the crisp 1:1 Multi-DPI **REAPER NOTATOR** logo banner, real-time progress bar (`0%–100%`), and EN / DE / FR live status text while performing staged core decryption, Bravura font setup, and non-blocking incremental indexing of all 1,500 orchestral patterns—with zero artificial delay.
- **High-DPI 1:1 Logo Branding & Native REAPER Toolbar Icons:** Crisp DPI-matched `ImGui_ImageSet` (`1x / 1.25x / 1.5x / 2x`) logo badge in the Top Bar, centered hero logo banner with version badge above all Settings sections, and native 3-state (`100% / 150% / 200%`) REAPER toolbar icon spritesheets (`toolbar_reaper_notator.png`).
- **Tempo Drawer Fractional-BPM Fix & `🔄 Sync to REAPER Tempo Map`:** Fixes Lua 5.4 float-to-integer crashes on fractional-BPM projects (with a global `I18nService` integer input guard) and adds 1-click syncing of Notator tempo markings back to REAPER's master tempo envelope.
- **Articulation Played Duration Overlap (%) (`🔗 Articulation Overlap (%)` & Piano Roll `🔗%`):** Select any articulation used on the active track from a live dropdown, dial in a percentage (`0%–100%`) so each note's played tail reaches that exact percentage into the following note (**0% score or MusicXML change**, **0 same-pitch collisions**), and auto-save all percentages to `data/articulation_overlaps.json`.
- **Piano Roll `⌒ Leg` & Persistent Score Tools Sections:** Added `⌒ Leg` (`Make Notes Legato`) right between `🎲 Hum` and `🔗%` in the Piano Roll toolbar, organized the 3 note filters into a dedicated `🔍 Filters` tab in Score Tools, and persisted open/collapsed states across all 7 Score Tools sections (with full EN / DE / FR localization).
- **1-Click Update & Auto-Restart (`🔄 Update & Restart REAPER-Notator`):** Automatically runs ReaPack `Synchronize packages` (`_REAPACK_SYNC`), saves & closes REAPER-Notator cleanly, and relaunches into the newly installed version once finished—paired with a dedicated `📦 ReaPack Browser` button and a compact latest-version-only changelog box.
- **Dual-Reality Played Durations & Humanizer (`🎲 Hum`):** `Shift+Drag` left/right note edges for early-attack Pre-Roll and Legato Tail Ghost-Halos with **0% impact** on engraved notation or MusicXML exports.
- **Fast Grid Editing (`✏`, `✂` & Heal/Glue Brush):** **Draw-Hold-Drag** auto-lengthens notes on the grid, **Grid Razor (`✂`)** slices notes/chords along grid or tuplet lines, and **Heal / Glue Brush** unites adjacent same-pitch notes while keeping 100% of the first note's properties.
- **Scale Check (`Out-of-Scale Red`) & Live Harmony Pill:** Real-time validation across Percussion Clef immunity, the active Chord Track, and Key Signatures—synchronized between Score Canvas and Piano Roll.
- **Percussion Drum Map Sidebar:** Automatically displays custom REAPER track note names and General MIDI / orchestral percussion names on Percussion Clef staves.
- **Multi-Track Stencils, Layer Lock & Smart-Lock:** Overlay reference tracks as semi-transparent background ghosts (`👁`) and protect score tracks from accidental raw edits in REAPER's external MIDI editor.
- **Top Bar `👁 View` & `🎨` Note Coloring Menus:** Consolidated visibility toggles (including switchable **Sub-Beat Rests `1/8 & 1/16`**) plus a dedicated note coloring dropdown.

---

## Installation via ReaPack

1. Ensure you have **ReaPack** installed in REAPER ([reapack.com](https://reapack.com/)).
2. Install the required dependencies in ReaPack (`Extensions` → `ReaPack` → `Browse packages...`):
   - **ReaImGui v0.10+** (**required** — `v0.10.0` or newer from ReaTeam Extensions via ReaPack)
   - **Reaticulate** (**required** — install via ReaPack or import repository `https://reaticulate.com/index.xml`)
3. In REAPER, go to `Extensions` → `ReaPack` → `Import a repository...` and enter:
   ```text
   https://raw.githubusercontent.com/A-intheCode/ReaperNotator/main/index.xml
   ```
4. Open `Extensions` → `ReaPack` → `Browse packages...`, search for `REAPER Notator 3.3.5`, right-click → **Install**, and click **Apply**.
5. Run `Script: reaper_native_notator.lua` from the REAPER Actions list (`?`).

---

## Documentation

- 📖 **[Official User Manual & Function Reference (v3.3.5 PDF)](docs/reaper_notator_user_manual.pdf)**

---

## License & Legal Notice (Closed Source — All Rights Reserved)

**Copyright © 2026 A-intheCode. All Rights Reserved.**

This repository distributes the compiled/encrypted binary release of **REAPER Notator 3.3.5**. This software is **proprietary and closed-source** (not open-source). See the [LICENSE](LICENSE) file for the full binding End-User License Agreement.

> [!CAUTION]
> **Strict Legal Notice (EN):**  
> Any copying, reproduction, modification, reverse-engineering, decompilation, decryption, unpacking, distribution, redistribution, sublicensing, or commercial sale of **REAPER Notator 3.3.5** (in whole or in part) is **strictly prohibited** without an express prior written license agreement signed by the author (**A-intheCode**). Nothing in this notice restricts the standard platform rights granted under GitHub Terms of Service Section D.5 (viewing and cloning/forking within GitHub for personal inspection), which convey zero right to modify, decrypt, redistribute, or reuse the software outside this Agreement.
>
> **Strikter Rechtlicher Hinweis (DE):**  
> Sämtliches Kopieren, Vervielfältigen, Modifizieren, Reverse-Engineering, Dekompilieren, Entschlüsseln, Entpacken, Weiterverbreiten, Unterlizenzieren oder Verkaufen von **REAPER Notator 3.3.5** (ganz oder teilweise) ist ohne ausdrückliche vorherige schriftliche Lizenzvereinbarung mit dem Autor (**A-intheCode**) **strikt untersagt**. Alle Rechte vorbehalten.

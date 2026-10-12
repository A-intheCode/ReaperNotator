# REAPER-Notator v1.9.4-beta — Codebase & Library Statistics

**Generated:** 2026-10-13 00:07

## Executive Summary

- **Version:** v1.9.4-beta
- **Total Source Files:** 75 Lua files
- **Total Line Count:** 56,409
- **Executable Code Lines:** 47,496 (84.2%)
- **Comments & Documentation:** 4,117 (7.3%)
- **Blank / Formatting Lines:** 5,317 (9.4%)
- **Orchestral Pattern Library:** 1,200 curated JSON patterns across 8 categories
- **Vector Music Typography:** SMuFL Bravura font (Bravura.otf)

## 1. Architecture & Module Volume Breakdown

| Module Directory | Files | Total Lines | Code Lines | Comments | Blank | Code % |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `modules/services` | 28 | 29,218 | 24,931 | 1,788 | 2,630 | 85.3% |
| `modules/rendering` | 7 | 11,911 | 10,127 | 740 | 1,096 | 85.0% |
| `modules/ui` | 19 | 9,337 | 7,539 | 718 | 1,106 | 80.7% |
| `modules` | 3 | 2,186 | 1,908 | 417 | 138 | 87.3% |
| `modules/input` | 2 | 2,002 | 1,740 | 91 | 173 | 86.9% |
| `Root` | 1 | 981 | 654 | 253 | 78 | 66.7% |
| `modules/classes` | 15 | 774 | 597 | 110 | 96 | 77.1% |
| **TOTAL** | **75** | **56,409** | **47,496** | **4,117** | **5,317** | **84.2%** |

## 2. Key Core System Files by Volume (Top 15)

| File | Module | Lines | Code | Comments |
| :--- | :--- | :---: | :---: | :---: |
| `modules/services/midi_service.lua` | modules/services | 5,994 | 5,226 | 241 |
| `modules/rendering/score_canvas.lua` | modules/rendering | 4,478 | 3,878 | 214 |
| `modules/rendering/engraver.lua` | modules/rendering | 2,947 | 2,512 | 226 |
| `modules/rendering/canvas_context_menus.lua` | modules/rendering | 2,204 | 1,913 | 105 |
| `modules/services/slur_service.lua` | modules/services | 2,120 | 1,830 | 102 |
| `modules/services/musicxml_import_service.lua` | modules/services | 2,118 | 1,839 | 124 |
| `modules/services/musicxml_export_service.lua` | modules/services | 1,698 | 1,435 | 145 |
| `modules/services/portamento_service.lua` | modules/services | 1,549 | 1,312 | 88 |
| `modules/services/glissando_service.lua` | modules/services | 1,474 | 1,245 | 79 |
| `modules/ui/midi_editor_drawer.lua` | modules/ui | 1,448 | 1,205 | 118 |
| `modules/ui/settings_modal.lua` | modules/ui | 1,409 | 1,144 | 96 |
| `modules/input/mouse_handler.lua` | modules/input | 1,319 | 1,157 | 50 |
| `modules/services/dynamics_engine.lua` | modules/services | 1,275 | 1,128 | 45 |
| `modules/state.lua` | modules | 1,132 | 980 | 199 |
| `modules/services/clipboard_service.lua` | modules/services | 1,044 | 890 | 58 |

## 3. Specialized Orchestral & Engraving Services (`modules/services`)

| Service File | Subsystem & Musical Responsibility | Code Lines |
| :--- | :--- | :---: |
| `modules/services/divisio_vocum_service.lua` | Divisio Vocum - Orchestral Voice Division across tracks | 308 |
| `modules/services/dynamics_engine.lua` | Orchestral Dynamics Engine - Bezier/Linear CC automation shaping | 1,128 |
| `modules/services/glissando_service.lua` | Glissando Engine - Smooth chromatic / diatonic slide generation | 1,245 |
| `modules/services/midi_service.lua` | Core MIDI Engine - Low-latency take I/O and event synchronization | 5,226 |
| `modules/services/musicxml_export_service.lua` | MusicXML 4.0 Exporter - Standard score interchange file generation | 1,435 |
| `modules/services/musicxml_import_service.lua` | MusicXML 4.0 Importer - Orchestral part loading and articulation mapping | 1,839 |
| `modules/services/audio_preview.lua` | Audition Preview Engine - Non-destructive note click playback chasing | 805 |
| `modules/services/reaticulate_parser.lua` | Reaticulate Bridge - Bank parsing and articulation keyswitch management | 376 |
| `modules/services/scale_service.lua` | Scale & Harmony Service - Chord Track harmonic transformations | 835 |
| `modules/services/slur_service.lua` | Slur Engine - Ergonomic Bezier phrasing curves and keyswitch binding | 1,830 |
| `modules/services/portamento_service.lua` | Portamento Service - High-resolution micro-tonal pitch-bend transitions | 1,312 |
| `modules/services/pattern_service.lua` | Pattern Engine - Orchestral motif browser and timeline stamping | 411 |
| `modules/services/rehearsal_mark_service.lua` | Rehearsal Marks - Structural navigation and drag-and-drop bar markers | 244 |
| `modules/services/fermata_service.lua` | Fermata Service - Score-wide pause holds and tempo mapping | 232 |
| `modules/services/pedal_service.lua` | Pedal Service - Classical damper and sustain pedal CC64 lane | 530 |

## 4. Orchestral Pattern Library Breakdown

| Category | Sub-Genre / Instrumentation | Pattern Count |
| :--- | :--- | :---: |
| `01_Strings_Staccato` | Cinematic Strings (Staccato / Spiccato Ostinatos) | 150 patterns |
| `02_Strings_Pizzicato` | Orchestral Strings (Pizzicato / Bartók Snap) | 150 patterns |
| `03_Brass_Blockbuster` | Epic Brass (Horns, Trumpets, Trombones, Tubas) | 150 patterns |
| `04_Cinematic_Melodies` | Heroic Themes & Symphonic Lead Melodies | 150 patterns |
| `05_Counter_Melodies` | Polyphonic Counter-Melodies & Descant Voices | 150 patterns |
| `06_Woodwinds_Textures` | Woodwind Runs, Flutter-Tongue & Textures | 150 patterns |
| `07_Cinematic_Piano` | Concert Grand Piano (Arpeggios & Ostinatos) | 150 patterns |
| `08_Ancient_Harp_Greek_Roman` | Antiquity Concert Harp (Greek & Roman Hymns) | 150 patterns |
| **TOTAL PATTERNS** | **8 Categories** | **1,200 patterns** |


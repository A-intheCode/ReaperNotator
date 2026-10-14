# REAPER-Notator v2.0.3 — Codebase & Library Statistics

**Generated:** 2026-10-14 20:33

## Executive Summary

- **Version:** v2.0.3
- **Total Source Files:** 79 Lua files
- **Total Line Count:** 60,903
- **Executable Code Lines:** 51,255 (84.2%)
- **Comments & Documentation:** 4,486 (7.4%)
- **Blank / Formatting Lines:** 5,708 (9.4%)
- **Orchestral Pattern Library:** 1,200 curated JSON patterns across 8 categories
- **Vector Music Typography:** SMuFL Bravura font (Bravura.otf)

## 1. Architecture & Module Volume Breakdown

| Module Directory | Files | Total Lines | Code Lines | Comments | Blank | Code % |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `modules/services` | 30 | 31,662 | 26,989 | 1,960 | 2,849 | 85.2% |
| `modules/rendering` | 7 | 12,408 | 10,575 | 764 | 1,121 | 85.2% |
| `modules/ui` | 21 | 10,378 | 8,397 | 784 | 1,223 | 80.9% |
| `modules` | 3 | 2,355 | 2,064 | 441 | 147 | 87.6% |
| `modules/input` | 2 | 2,017 | 1,754 | 91 | 174 | 87.0% |
| `Root` | 1 | 1,309 | 879 | 336 | 98 | 67.2% |
| `modules/classes` | 15 | 774 | 597 | 110 | 96 | 77.1% |
| **TOTAL** | **79** | **60,903** | **51,255** | **4,486** | **5,708** | **84.2%** |

## 2. Key Core System Files by Volume (Top 15)

| File | Module | Lines | Code | Comments |
| :--- | :--- | :---: | :---: | :---: |
| `modules/services/midi_service.lua` | modules/services | 6,122 | 5,348 | 242 |
| `modules/rendering/score_canvas.lua` | modules/rendering | 4,674 | 4,061 | 217 |
| `modules/rendering/engraver.lua` | modules/rendering | 3,161 | 2,693 | 246 |
| `modules/services/slur_service.lua` | modules/services | 2,357 | 2,037 | 119 |
| `modules/rendering/canvas_context_menus.lua` | modules/rendering | 2,229 | 1,937 | 105 |
| `modules/services/musicxml_import_service.lua` | modules/services | 2,118 | 1,839 | 124 |
| `modules/services/musicxml_export_service.lua` | modules/services | 1,698 | 1,435 | 145 |
| `modules/services/portamento_service.lua` | modules/services | 1,549 | 1,312 | 88 |
| `modules/services/glissando_service.lua` | modules/services | 1,474 | 1,245 | 79 |
| `modules/ui/midi_editor_drawer.lua` | modules/ui | 1,449 | 1,206 | 118 |
| `modules/ui/settings_modal.lua` | modules/ui | 1,420 | 1,154 | 96 |
| `modules/input/mouse_handler.lua` | modules/input | 1,320 | 1,158 | 50 |
| `reaper_native_notator.lua` | Root | 1,309 | 879 | 336 |
| `modules/services/dynamics_engine.lua` | modules/services | 1,275 | 1,128 | 45 |
| `modules/state.lua` | modules | 1,258 | 1,096 | 224 |

## 3. Specialized Orchestral & Engraving Services (`modules/services`)

| Service File | Subsystem & Musical Responsibility | Code Lines |
| :--- | :--- | :---: |
| `modules/services/divisio_vocum_service.lua` | Divisio Vocum - Orchestral Voice Division across tracks | 308 |
| `modules/services/dynamics_engine.lua` | Orchestral Dynamics Engine - Bezier/Linear CC automation shaping | 1,128 |
| `modules/services/filter_notes_service.lua` | Filter Irregular Notes - Metric onset analysis and voice routing | 308 |
| `modules/services/glissando_service.lua` | Glissando Engine - Smooth chromatic / diatonic slide generation | 1,245 |
| `modules/services/midi_service.lua` | Core MIDI Engine - Low-latency take I/O and event synchronization | 5,348 |
| `modules/services/musicxml_export_service.lua` | MusicXML 4.0 Exporter - Standard score interchange file generation | 1,435 |
| `modules/services/musicxml_import_service.lua` | MusicXML 4.0 Importer - Orchestral part loading and articulation mapping | 1,839 |
| `modules/services/audio_preview.lua` | Audition Preview Engine - Non-destructive note click playback chasing | 805 |
| `modules/services/reaticulate_parser.lua` | Reaticulate Bridge - FX Slot 1 setup, bank sync & keyswitch routing | 801 |
| `modules/services/record_quantize_service.lua` | Record & Auto-Quantize Engine - Live MIDI capture & grid quantization | 801 |
| `modules/services/scale_service.lua` | Scale & Harmony Service - Chord Track harmonic transformations | 835 |
| `modules/services/slur_service.lua` | Slur Engine - Ergonomic Bezier phrasing curves and keyswitch binding | 2,037 |
| `modules/services/portamento_service.lua` | Portamento Service - High-resolution micro-tonal pitch-bend transitions | 1,312 |
| `modules/services/pattern_service.lua` | Pattern Engine - Orchestral motif browser and timeline stamping | 411 |
| `modules/services/rehearsal_mark_service.lua` | Rehearsal Marks - Custom/auto structural navigation & live markers | 368 |
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


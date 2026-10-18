# REAPER-Notator v2.50-beta.3 — Codebase & Library Statistics

**Generated:** 2026-10-18 21:47

## Executive Summary

- **Version:** v2.50-beta.3
- **Total Source Files:** 89 Lua files
- **Total Line Count:** 75,124
- **Executable Code Lines:** 64,023 (85.2%)
- **Comments & Documentation:** 5,059 (6.7%)
- **Blank / Formatting Lines:** 6,660 (8.9%)
- **Orchestral Pattern Library:** 1,500 curated JSON patterns across 10 categories
- **Automated Unit Test Suite:** 152 unit tests across 19 core subsystems (`tests/test_all_modules.lua`, 0 failures)
- **Vector Music Typography:** SMuFL Bravura font (Bravura.otf)

## 1. Architecture & Module Volume Breakdown

| Module Directory | Files | Total Lines | Code Lines | Comments | Blank | Code % |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `modules/services` | 35 | 39,230 | 33,673 | 2,368 | 3,361 | 85.8% |
| `modules/rendering` | 7 | 14,018 | 12,032 | 849 | 1,187 | 85.8% |
| `modules/ui` | 24 | 12,345 | 10,089 | 891 | 1,391 | 81.7% |
| `tests` | 2 | 2,726 | 2,444 | 116 | 181 | 89.7% |
| `modules` | 3 | 2,621 | 2,308 | 472 | 161 | 88.1% |
| `modules/input` | 2 | 2,073 | 1,807 | 92 | 176 | 87.2% |
| `Root` | 1 | 1,321 | 1,057 | 161 | 107 | 80.0% |
| `modules/classes` | 15 | 790 | 613 | 110 | 96 | 77.6% |
| **TOTAL** | **89** | **75,124** | **64,023** | **5,059** | **6,660** | **85.2%** |

## 2. Key Core System Files by Volume (Top 15)

| File | Module | Lines | Code | Comments |
| :--- | :--- | :---: | :---: | :---: |
| `modules/services/midi_service.lua` | modules/services | 7,467 | 6,592 | 288 |
| `modules/rendering/score_canvas.lua` | modules/rendering | 5,105 | 4,456 | 244 |
| `modules/rendering/engraver.lua` | modules/rendering | 4,199 | 3,618 | 303 |
| `modules/services/slur_service.lua` | modules/services | 2,654 | 2,314 | 125 |
| `modules/services/record_quantize_service.lua` | modules/services | 2,500 | 2,167 | 162 |
| `modules/rendering/canvas_context_menus.lua` | modules/rendering | 2,339 | 2,045 | 105 |
| `modules/services/musicxml_import_service.lua` | modules/services | 2,193 | 1,911 | 125 |
| `modules/services/musicxml_export_service.lua` | modules/services | 1,715 | 1,452 | 145 |
| `modules/services/melody_pathfinder_service.lua` | modules/services | 1,571 | 1,313 | 113 |
| `modules/services/portamento_service.lua` | modules/services | 1,561 | 1,322 | 90 |
| `modules/services/glissando_service.lua` | modules/services | 1,489 | 1,257 | 82 |
| `modules/ui/midi_editor_drawer.lua` | modules/ui | 1,449 | 1,206 | 118 |
| `tests/test_all_modules.lua` | tests | 1,447 | 1,232 | 90 |
| `modules/ui/settings_modal.lua` | modules/ui | 1,420 | 1,154 | 96 |
| `modules/state.lua` | modules | 1,415 | 1,237 | 236 |

## 3. Specialized Orchestral & Engraving Services (`modules/services`)

| Service File | Subsystem & Musical Responsibility | Code Lines |
| :--- | :--- | :---: |
| `modules/services/annotation_service.lua` | Annotation Layer Engine - Per-track multi-layer freehand PNG tiles & Capsule SDF | 972 |
| `modules/services/melody_pathfinder_service.lua` | Melodic Pathfinder Engine - Corpus-trained Viterbi inpainting & counter-melodies | 1,313 |
| `modules/services/melody_style_corpus.lua` | Composer Style Corpus - Statistical Markov transition & rhythm matrices | 248 |
| `modules/services/divisi_service.lua` | Divisi Engine - Split polyphonic voices onto full duplicated tracks | 434 |
| `modules/services/divisio_vocum_service.lua` | Divisio Vocum - Orchestral Voice Division across tracks | 308 |
| `modules/services/dynamics_engine.lua` | Orchestral Dynamics Engine - Bezier/Linear CC automation shaping | 1,128 |
| `modules/services/filter_notes_service.lua` | Filter Irregular Notes - Metric onset analysis and voice routing | 308 |
| `modules/services/frame_timer_service.lua` | Native High-Refresh Timer - 1ms kernel multimedia timer (60-144 FPS) | 147 |
| `modules/services/glissando_service.lua` | Glissando Engine - Smooth chromatic / diatonic slide generation | 1,257 |
| `modules/services/midi_service.lua` | Core MIDI Engine - Low-latency take I/O and event synchronization | 6,592 |
| `modules/services/musicxml_export_service.lua` | MusicXML 4.0 Exporter - Standard score interchange file generation | 1,452 |
| `modules/services/musicxml_import_service.lua` | MusicXML 4.0 Importer - Orchestral part loading and articulation mapping | 1,911 |
| `modules/services/audio_preview.lua` | Audition Preview Engine - Non-destructive note click playback chasing | 951 |
| `modules/services/reaticulate_parser.lua` | Reaticulate Bridge - FX Slot 1 setup, bank sync & keyswitch routing | 876 |
| `modules/services/record_quantize_service.lua` | Record & Auto-Quantize Engine - Live MIDI capture & grid quantization | 2,167 |
| `modules/services/scale_service.lua` | Scale & Harmony Service - Chord Track harmonic transformations | 835 |
| `modules/services/slur_service.lua` | Slur Engine - Ergonomic Bezier phrasing curves and keyswitch binding | 2,314 |
| `modules/services/portamento_service.lua` | Portamento Service - High-resolution micro-tonal pitch-bend transitions | 1,322 |
| `modules/services/pattern_service.lua` | Pattern Engine - Orchestral motif browser and timeline stamping | 582 |
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
| `09_Orchestral_Percussion` | Orchestral & Cinematic Percussion (Timpani, Taiko, Drums) | 150 patterns |
| `10_Low_Strings_Celli_Basses` | Low Strings Tension & Rhythm (Staccato Celli & Double Basses) | 150 patterns |
| **TOTAL PATTERNS** | **10 Categories** | **1,500 patterns** |


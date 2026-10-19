# REAPER-Notator v2.50 — Codebase & Library Statistics

**Generated:** 2026-10-19 22:56

## Executive Summary

- **Version:** v2.50
- **Total Source Files:** 92 Lua files
- **Total Line Count:** 78,620
- **Executable Code Lines:** 67,010 (85.2%)
- **Comments & Documentation:** 5,292 (6.7%)
- **Blank / Formatting Lines:** 6,977 (8.9%)
- **Orchestral Pattern Library:** 1,500 curated JSON patterns across 10 categories
- **Automated Unit Test Suite:** 159 unit tests across 92 Lua modules and 644 exported functions (`tests/test_all_modules.lua`, 0 failures)
- **Vector Music Typography:** SMuFL Bravura font (Bravura.otf)

## 1. Architecture & Module Volume Breakdown

| Module Directory | Files | Total Lines | Code Lines | Comments | Blank | Code % |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `modules/services` | 37 | 41,142 | 35,334 | 2,480 | 3,524 | 85.9% |
| `modules/rendering` | 7 | 14,077 | 12,086 | 848 | 1,190 | 85.9% |
| `modules/ui` | 25 | 13,368 | 10,938 | 962 | 1,495 | 81.8% |
| `tests` | 2 | 3,159 | 2,805 | 161 | 224 | 88.8% |
| `modules` | 3 | 2,629 | 2,316 | 475 | 161 | 88.1% |
| `modules/input` | 2 | 2,123 | 1,853 | 92 | 180 | 87.3% |
| `Root` | 1 | 1,332 | 1,065 | 164 | 107 | 80.0% |
| `modules/classes` | 15 | 790 | 613 | 110 | 96 | 77.6% |
| **TOTAL** | **92** | **78,620** | **67,010** | **5,292** | **6,977** | **85.2%** |

## 2. Key Core System Files by Volume (Top 15)

| File | Module | Lines | Code | Comments |
| :--- | :--- | :---: | :---: | :---: |
| `modules/services/midi_service.lua` | modules/services | 7,523 | 6,646 | 288 |
| `modules/rendering/score_canvas.lua` | modules/rendering | 5,110 | 4,461 | 244 |
| `modules/rendering/engraver.lua` | modules/rendering | 4,252 | 3,666 | 302 |
| `modules/services/record_quantize_service.lua` | modules/services | 2,834 | 2,439 | 191 |
| `modules/services/slur_service.lua` | modules/services | 2,654 | 2,314 | 125 |
| `modules/rendering/canvas_context_menus.lua` | modules/rendering | 2,339 | 2,045 | 105 |
| `modules/services/musicxml_import_service.lua` | modules/services | 2,193 | 1,911 | 125 |
| `tests/test_all_modules.lua` | tests | 1,851 | 1,565 | 135 |
| `modules/services/musicxml_export_service.lua` | modules/services | 1,715 | 1,452 | 145 |
| `modules/services/melody_pathfinder_service.lua` | modules/services | 1,643 | 1,375 | 117 |
| `modules/services/portamento_service.lua` | modules/services | 1,561 | 1,322 | 90 |
| `modules/services/glissando_service.lua` | modules/services | 1,489 | 1,257 | 82 |
| `modules/ui/midi_editor_drawer.lua` | modules/ui | 1,449 | 1,206 | 118 |
| `modules/state.lua` | modules | 1,423 | 1,245 | 239 |
| `modules/ui/settings_modal.lua` | modules/ui | 1,420 | 1,154 | 96 |

## 3. Specialized Orchestral & Engraving Services (`modules/services`)

| Service File | Subsystem & Musical Responsibility | Code Lines |
| :--- | :--- | :---: |
| `modules/services/annotation_service.lua` | Annotation Layer Engine - Per-track multi-layer freehand PNG tiles & Capsule SDF | 972 |
| `modules/services/circle_of_fifths_service.lua` | Circle of Fifths & Harmonic Palette - Chord wheel, tension analysis & global persistence | 680 |
| `modules/services/melody_pathfinder_service.lua` | Melodic Pathfinder Engine - Corpus-trained Viterbi inpainting & counter-melodies | 1,375 |
| `modules/services/melody_style_corpus.lua` | Composer Style Corpus - Statistical Markov transition & rhythm matrices | 248 |
| `modules/services/divisi_service.lua` | Divisi Engine - Split polyphonic voices onto full duplicated tracks | 434 |
| `modules/services/divisio_vocum_service.lua` | Divisio Vocum - Orchestral Voice Division across tracks | 308 |
| `modules/services/dynamics_engine.lua` | Orchestral Dynamics Engine - Bezier/Linear CC automation shaping | 1,128 |
| `modules/services/filter_notes_service.lua` | Filter Irregular Notes - Metric onset analysis and voice routing | 308 |
| `modules/services/frame_timer_service.lua` | Native High-Refresh Timer - 1ms kernel multimedia timer (60-144 FPS) | 147 |
| `modules/services/glissando_service.lua` | Glissando Engine - Smooth chromatic / diatonic slide generation | 1,257 |
| `modules/services/imgui_guard_service.lua` | ImGui Stack Guard Engine - Zero-leak Begin/End & BeginChild/EndChild auto-unwinder | 348 |
| `modules/services/key_signature_service.lua` | Key Signature Service - Project/Take key signatures & diatonic pitch spelling | 906 |
| `modules/services/midi_service.lua` | Core MIDI Engine - Low-latency take I/O and event synchronization | 6,646 |
| `modules/services/musicxml_export_service.lua` | MusicXML 4.0 Exporter - Standard score interchange file generation | 1,452 |
| `modules/services/musicxml_import_service.lua` | MusicXML 4.0 Importer - Orchestral part loading and articulation mapping | 1,911 |
| `modules/services/audio_preview.lua` | Audition Preview Engine - Non-destructive note click playback chasing | 1,058 |
| `modules/services/reaticulate_parser.lua` | Reaticulate Bridge - FX Slot 1 setup, bank sync & keyswitch routing | 876 |
| `modules/services/record_quantize_service.lua` | Record & Auto-Quantize Engine - Live MIDI capture, Step Input & grid quantization | 2,439 |
| `modules/services/scale_service.lua` | Scale & Harmony Service - Chord Track harmonic transformations | 925 |
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


# REAPER-Notator v2.53 — Codebase & Library Statistics

**Generated:** 2026-10-24 01:26

## Executive Summary

- **Version:** v2.53
- **Total Source Files:** 93 Lua files
- **Total Line Count:** 84,786
- **Executable Code Lines:** 72,554 (85.6%)
- **Comments & Documentation:** 5,595 (6.6%)
- **Blank / Formatting Lines:** 7,320 (8.6%)
- **Orchestral Pattern Library:** 1,500 curated JSON patterns across 10 categories
- **Automated Unit Test Suite:** 159 unit tests across 93 Lua modules and 654 exported functions (`tests/test_all_modules.lua`, 0 failures)
- **Vector Music Typography:** SMuFL Bravura font (Bravura.otf)

## 1. Architecture & Module Volume Breakdown

| Module Directory | Files | Total Lines | Code Lines | Comments | Blank | Code % |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `modules/services` | 38 | 44,977 | 38,800 | 2,661 | 3,713 | 86.3% |
| `modules/rendering` | 7 | 14,673 | 12,664 | 850 | 1,208 | 86.3% |
| `modules/ui` | 25 | 13,942 | 11,460 | 984 | 1,524 | 82.2% |
| `tests` | 2 | 4,142 | 3,622 | 240 | 327 | 87.4% |
| `modules` | 3 | 2,682 | 2,364 | 483 | 164 | 88.1% |
| `modules/input` | 2 | 2,139 | 1,875 | 91 | 175 | 87.7% |
| `Root` | 1 | 1,441 | 1,156 | 176 | 113 | 80.2% |
| `modules/classes` | 15 | 790 | 613 | 110 | 96 | 77.6% |
| **TOTAL** | **93** | **84,786** | **72,554** | **5,595** | **7,320** | **85.6%** |

## 2. Key Core System Files by Volume (Top 15)

| File | Module | Lines | Code | Comments |
| :--- | :--- | :---: | :---: | :---: |
| `modules/services/midi_service.lua` | modules/services | 7,531 | 6,654 | 288 |
| `modules/rendering/score_canvas.lua` | modules/rendering | 5,252 | 4,605 | 245 |
| `modules/rendering/engraver.lua` | modules/rendering | 4,565 | 3,961 | 303 |
| `modules/services/melody_pathfinder_service.lua` | modules/services | 3,182 | 2,715 | 229 |
| `modules/services/record_quantize_service.lua` | modules/services | 2,856 | 2,459 | 193 |
| `modules/services/slur_service.lua` | modules/services | 2,826 | 2,481 | 127 |
| `tests/test_all_modules.lua` | tests | 2,820 | 2,368 | 214 |
| `modules/rendering/canvas_context_menus.lua` | modules/rendering | 2,401 | 2,107 | 105 |
| `modules/services/musicxml_import_service.lua` | modules/services | 2,193 | 1,911 | 125 |
| `modules/services/key_signature_service.lua` | modules/services | 1,735 | 1,433 | 173 |
| `modules/services/musicxml_export_service.lua` | modules/services | 1,715 | 1,452 | 145 |
| `modules/services/portamento_service.lua` | modules/services | 1,683 | 1,440 | 93 |
| `modules/services/glissando_service.lua` | modules/services | 1,594 | 1,360 | 82 |
| `modules/state.lua` | modules | 1,476 | 1,293 | 247 |
| `modules/ui/midi_editor_drawer.lua` | modules/ui | 1,457 | 1,214 | 118 |

## 3. Specialized Orchestral & Engraving Services (`modules/services`)

| Service File | Subsystem & Musical Responsibility | Code Lines |
| :--- | :--- | :---: |
| `modules/services/annotation_service.lua` | Annotation Layer Engine - Per-track multi-layer freehand PNG tiles & Capsule SDF | 972 |
| `modules/services/circle_of_fifths_service.lua` | Circle of Fifths & Harmonic Palette - Chord wheel, tension analysis & global persistence | 680 |
| `modules/services/melody_pathfinder_service.lua` | Melodic Pathfinder Engine - Corpus-trained Viterbi inpainting & counter-melodies | 2,715 |
| `modules/services/melody_style_corpus.lua` | Composer Style Corpus - Statistical Markov transition & rhythm matrices | 472 |
| `modules/services/divisi_service.lua` | Divisi Engine - Split polyphonic voices onto full duplicated tracks | 434 |
| `modules/services/divisio_vocum_service.lua` | Divisio Vocum - Orchestral Voice Division across tracks | 308 |
| `modules/services/dynamics_engine.lua` | Orchestral Dynamics Engine - Bezier/Linear CC automation shaping | 1,128 |
| `modules/services/filter_notes_service.lua` | Filter Irregular Notes - Metric onset analysis and voice routing | 308 |
| `modules/services/frame_timer_service.lua` | Native High-Refresh Timer - 1ms kernel multimedia timer (60-144 FPS) | 147 |
| `modules/services/glissando_service.lua` | Glissando Engine - Smooth chromatic / diatonic slide generation | 1,360 |
| `modules/services/imgui_guard_service.lua` | ImGui Stack Guard Engine - Zero-leak Begin/End & BeginChild/EndChild auto-unwinder | 358 |
| `modules/services/key_signature_service.lua` | Key Signature Service - Project/Take key signatures & diatonic pitch spelling | 1,433 |
| `modules/services/midi_service.lua` | Core MIDI Engine - Low-latency take I/O and event synchronization | 6,654 |
| `modules/services/musicxml_export_service.lua` | MusicXML 4.0 Exporter - Standard score interchange file generation | 1,452 |
| `modules/services/musicxml_import_service.lua` | MusicXML 4.0 Importer - Orchestral part loading and articulation mapping | 1,911 |
| `modules/services/audio_preview.lua` | Audition Preview Engine - Non-destructive note click playback chasing | 1,062 |
| `modules/services/reaticulate_parser.lua` | Reaticulate Bridge - FX Slot 1 setup, bank sync & keyswitch routing | 936 |
| `modules/services/record_quantize_service.lua` | Record & Auto-Quantize Engine - Live MIDI capture, Step Input & grid quantization | 2,459 |
| `modules/services/scale_service.lua` | Scale & Harmony Service - Chord Track harmonic transformations | 932 |
| `modules/services/slur_service.lua` | Slur Engine - Ergonomic Bezier phrasing curves and keyswitch binding | 2,481 |
| `modules/services/portamento_service.lua` | Portamento Service - High-resolution micro-tonal pitch-bend transitions | 1,440 |
| `modules/services/pattern_service.lua` | Pattern Engine - Orchestral motif browser and timeline stamping | 635 |
| `modules/services/rehearsal_mark_service.lua` | Rehearsal Marks - Custom/auto structural navigation & live markers | 382 |
| `modules/services/fermata_service.lua` | Fermata Service - Score-wide pause holds and tempo mapping | 254 |
| `modules/services/pedal_service.lua` | Pedal Service - Classical damper and sustain pedal CC64 lane | 637 |

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


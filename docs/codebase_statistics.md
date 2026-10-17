# REAPER-Notator v2.34-beta — Codebase & Library Statistics

**Generated:** 2026-10-17 15:39

## Executive Summary

- **Version:** v2.34-beta
- **Total Source Files:** 87 Lua files
- **Total Line Count:** 68,388
- **Executable Code Lines:** 57,967 (84.8%)
- **Comments & Documentation:** 4,717 (6.9%)
- **Blank / Formatting Lines:** 6,277 (9.2%)
- **Orchestral Pattern Library:** 1,500 curated JSON patterns across 10 categories
- **Vector Music Typography:** SMuFL Bravura font (Bravura.otf)

## 1. Architecture & Module Volume Breakdown

| Module Directory | Files | Total Lines | Code Lines | Comments | Blank | Code % |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| `modules/services` | 35 | 36,811 | 31,472 | 2,264 | 3,238 | 85.5% |
| `modules/rendering` | 7 | 12,990 | 11,127 | 781 | 1,134 | 85.7% |
| `modules/ui` | 24 | 12,079 | 9,843 | 885 | 1,377 | 81.5% |
| `modules` | 3 | 2,396 | 2,101 | 443 | 149 | 87.7% |
| `modules/input` | 2 | 2,051 | 1,785 | 92 | 176 | 87.0% |
| `Root` | 1 | 1,287 | 1,042 | 142 | 107 | 81.0% |
| `modules/classes` | 15 | 774 | 597 | 110 | 96 | 77.1% |
| **TOTAL** | **87** | **68,388** | **57,967** | **4,717** | **6,277** | **84.8%** |

## 2. Key Core System Files by Volume (Top 15)

| File | Module | Lines | Code | Comments |
| :--- | :--- | :---: | :---: | :---: |
| `modules/services/midi_service.lua` | modules/services | 6,936 | 6,096 | 280 |
| `modules/rendering/score_canvas.lua` | modules/rendering | 5,056 | 4,425 | 225 |
| `modules/rendering/engraver.lua` | modules/rendering | 3,298 | 2,819 | 255 |
| `modules/services/slur_service.lua` | modules/services | 2,619 | 2,282 | 123 |
| `modules/rendering/canvas_context_menus.lua` | modules/rendering | 2,292 | 1,999 | 105 |
| `modules/services/musicxml_import_service.lua` | modules/services | 2,142 | 1,861 | 125 |
| `modules/services/musicxml_export_service.lua` | modules/services | 1,698 | 1,435 | 145 |
| `modules/services/portamento_service.lua` | modules/services | 1,549 | 1,312 | 88 |
| `modules/services/glissando_service.lua` | modules/services | 1,475 | 1,246 | 79 |
| `modules/ui/midi_editor_drawer.lua` | modules/ui | 1,449 | 1,206 | 118 |
| `modules/ui/settings_modal.lua` | modules/ui | 1,420 | 1,154 | 96 |
| `modules/input/mouse_handler.lua` | modules/input | 1,351 | 1,186 | 51 |
| `modules/services/melody_pathfinder_service.lua` | modules/services | 1,315 | 1,088 | 94 |
| `modules/state.lua` | modules | 1,299 | 1,133 | 227 |
| `reaper_native_notator.lua` | Root | 1,287 | 1,042 | 142 |

## 3. Specialized Orchestral & Engraving Services (`modules/services`)

| Service File | Subsystem & Musical Responsibility | Code Lines |
| :--- | :--- | :---: |
| `modules/services/annotation_service.lua` | Annotation Layer Engine - Per-track multi-layer freehand PNG tiles & Capsule SDF | 972 |
| `modules/services/melody_pathfinder_service.lua` | Melodic Pathfinder Engine - Corpus-trained Viterbi inpainting & counter-melodies | 1,088 |
| `modules/services/melody_style_corpus.lua` | Composer Style Corpus - Statistical Markov transition & rhythm matrices | 248 |
| `modules/services/divisi_service.lua` | Divisi Engine - Split polyphonic voices onto full duplicated tracks | 434 |
| `modules/services/divisio_vocum_service.lua` | Divisio Vocum - Orchestral Voice Division across tracks | 308 |
| `modules/services/dynamics_engine.lua` | Orchestral Dynamics Engine - Bezier/Linear CC automation shaping | 1,128 |
| `modules/services/filter_notes_service.lua` | Filter Irregular Notes - Metric onset analysis and voice routing | 308 |
| `modules/services/frame_timer_service.lua` | Native High-Refresh Timer - 1ms kernel multimedia timer (60-144 FPS) | 147 |
| `modules/services/glissando_service.lua` | Glissando Engine - Smooth chromatic / diatonic slide generation | 1,246 |
| `modules/services/midi_service.lua` | Core MIDI Engine - Low-latency take I/O and event synchronization | 6,096 |
| `modules/services/musicxml_export_service.lua` | MusicXML 4.0 Exporter - Standard score interchange file generation | 1,435 |
| `modules/services/musicxml_import_service.lua` | MusicXML 4.0 Importer - Orchestral part loading and articulation mapping | 1,861 |
| `modules/services/audio_preview.lua` | Audition Preview Engine - Non-destructive note click playback chasing | 951 |
| `modules/services/reaticulate_parser.lua` | Reaticulate Bridge - FX Slot 1 setup, bank sync & keyswitch routing | 875 |
| `modules/services/record_quantize_service.lua` | Record & Auto-Quantize Engine - Live MIDI capture & grid quantization | 845 |
| `modules/services/scale_service.lua` | Scale & Harmony Service - Chord Track harmonic transformations | 835 |
| `modules/services/slur_service.lua` | Slur Engine - Ergonomic Bezier phrasing curves and keyswitch binding | 2,282 |
| `modules/services/portamento_service.lua` | Portamento Service - High-resolution micro-tonal pitch-bend transitions | 1,312 |
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


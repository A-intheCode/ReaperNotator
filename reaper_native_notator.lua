-- @description REAPER-Notator: Native Musical Notation & Engraving Suite
-- @author A-intheCode
-- @version 2.58
-- @changelog
--   + v2.58: New: Multi-Note Block Drag & Drop across staves with full SMuFL Ghost Notes preview (Ctrl+Drag to copy), Shortcut Move of selected notes to adjacent displayed staff above/below (Ctrl+UpArrow / Ctrl+DownArrow), Note Preview 4-case (Arm / Monitoring) track preparation & full 250ms warmup fix, and Legal Notice addition
--   + v2.57: Hotfix: Reliable first-click Note Preview (AudioPreview) with active REAPER track MIDI & Audio status detection (Track_GetPeakInfo on MIDI channels 1024/1025 and Audio channels 0/1), immediate Mouse-Down warmup & trigger sequence (immune to 3px mouse micro-jitter during clicks), closed-loop Note-On retry if REAPER's audio thread swallowed the initial Note-On while arming a heavy VSTi track, and fix Reaticulate P_EXT:reaticulate re-sync loop during note clicks
--   + v2.56: Hotfix: Fix `ImGui assertion failed: font_cfg->SizePixels > 0.0f` crash on systems running ReaImGui < 0.10 (auto-detect legacy 3-argument `ImGui_CreateFont(family, size_px, flags)` / `ImGui_CreateFontFromFile(file, size_px, flags)` vs. ReaImGui 0.10+ 2-argument dynamic font API in `FontManager.init`), and document `ReaImGui v0.10+` dependency requirement in GitHub README & ReaPack metadata
--   + v2.55: Stable Release: Fix Display Quantize (1/1 to 1/32) visual note position & duration quantization (`Engraver.quantize_notes_for_display` & `Engraver.get_display_quantized_qn`), intra-measure barline clamping (notes at the end of a bar never jump across the barline into the next measure), grid-slot consolidation (preserving simultaneous chords and selection links), immediate measure-map cache invalidation & ProjExtState/ExtState persistence when toggling Display Quantize in Top Bar or Tools Drawer, and 100% zero impact on score rendering or MIDI when Display Quantize is disabled
--   + v2.54: Stable Release: Settings Modal improvements (all sections collapsed by default on launch & collapsible "Donate if you want to contribute" section with Gumroad link) and updated high-resolution illustrated User Manual (PDF)
--   + v2.53: Stable Release: Melodic Pathfinder 2.0 (8 descriptive Film Score Archetypes, Leitmotif & period phrasing up to 32 bars, automatic Krumhansl-Schmuckler Key & Mode detection, half-bar chord lock, Anchor-Note blending, 3 interactive coupled Bezier curves [Tension -> Velocity/Leaps, Note Length, Pitch] with freehand Draw -> auto-simplified Edit Handles, 4 RAM slots & JSON export/import), pre-armed target track with [REC] badge & 2-stage warmup so first-note audition never drops, and full Reaticulate clone bank resolution (fixing Spitfire BBC Symphony Orchestra Trumpet, Flutes a3, Piccolo & cloned banks)
--   + v2.52: Stable Release: Full Canvas & MIDI Undo/Redo Synchronization (UndoStateService) across all score elements (Hairpins, Sustain Pedals, Dynamic Texts, Tempo Markers, Slurs, Ties, Portamentos, Glissandos, Octave Lines, Fermatas, Repeat Marks, Rehearsal Marks, Text Items & Chords), single-step Undo for Portamento (Hold Pedal CC + Canvas Marker together), clean CC64 Hold Pedal rebuild & MIDI Editor left-edge step rendering, and fix Pattern Browser 5/8 time signature JSON schema
--   + v2.51: Stable Release: Mid-piece Time Signatures across all staves & REAPER TimeMap (independent of MIDI items), Target Bar Stepper ([ - ] / [ + ]) & Smart Edit Cursor vs. Note detection in Time Signature Drawer, Compound Meter (6/8, 9/8, 12/8) dotted-quarter beam grouping, full English UI labels, barline culling fix when scrolling, and Lua 5.4 local-variable scope optimization in ScoreCanvas.render
--   + v2.50.7: Hotfix: Fix missing barlines when scrolling (wrap Engraver.qn_to_measure_info single-value return before math.max so multi-return values never inflate vis_min_measure)
--   + v2.50.6: Hotfix: Fix ReaPack index.xml source URLs (/main/ instead of /testing/), prevent legacy MIDI-item NOTATOR_TIME_SIG events from overwriting mid-piece Time Signatures, prioritize Edit Cursor bar when moving cursor to a new measure, add [ - ] / [ + ] target bar stepper in Time Signature Drawer, and commit REAPER TimeMap after each measure marker
--   + v2.50.5: Hotfix: Mid-piece Time Signature changes at the barline before the selected note or Edit Cursor across all staves (independent of MIDI items), preserving all preceding measures' time signatures and barline positions + double barline & SMuFL Time Signature engraving at mid-piece meter changes across all staves + remove remaining German words ("Taktart", "Tonart", "Dur", "Moll") from Key & Time Signature Drawer
--   + v2.50.4: Hotfix: Move Time Signature section to the top of Key & Time Signature Drawer, unify Time Signature across all staves & sync with REAPER TimeMap, and fix compound meter (6/8, 9/8, 12/8) dotted-quarter beam grouping
--   + v2.50.3: Hotfix: Increase vertical clearance of Tuplet brackets above and below noteheads, stems, beams & articulations
--   + v2.50.2: Hotfix: Fix Track Selector Uncheck All permanence & add Follow REAPER Track Selection + Live Search Filter for 500+ track templates (TopBar & Record Modal) + preserve REAPER Input Monitoring (I_RECMON) when arming/disarming tracks in TCP + fix Annotation Layer hide crash (Push/PopStyleColor balance) + fix Tuplet engraving when notes inside or across a tuplet are tied
--   + v2.50.1: Hotfix: Lock dragged sector in Circle of Fifths so dragging across adjacent sectors toward the Palette never overwrites the selected note/chord
--   + v2.50: Major Release: Circle of Fifths & Global Harmonic Chord Palette Modal (`🎡 Circle of Fifths` with 24-sector Major/Minor wheel, Audition & Target Track Selector `🔊 Audition & Target Track:`, 8 drag-and-drop progression tiles, dynamic harmonic tension analysis, score insertion & global multi-tab REAPER persistence) + MIDI Keyboard Step Input in Record Modal (writes 1 Grid length per played note/chord with Auto-Divisi support) + Auto-Divisi Live Recording & Input FX Router (`Notator_Auto_Divisi_Router.jsfx`) + Automatic Percussion Clef detection (`percussion_1`), full C0–C9 drum staff mapping & 9 SMuFL Custom/Percussion Noteheads (`🥁 Notehead / Percussion Head`) + Elaine Gould ("Behind Bars") Optical Spacing (Δt^0.70), intra-bar accidental memory & multi-column chord stacking + Melodic Pathfinder & Counter-Melody Generator (with full Key Signature integration) + Per-Track Freehand Annotation Layer System + Global `ImGuiGuardService` zero-leak UI stack protection & 159-test automated verification suite
--   + v2.50-beta.6: Hotfix & Improvements: Add Audition & Target Track Selector (`🔊 Audition & Target Track:`) + automatic track arming & forced audition in Circle of Fifths Modal + eliminate internal radial AA seam lines in Circle of Fifths sectors (`draw_annular_sector`) + full Key Signature (`KeySignatureService.resolve_effective_key` & `respell_item_notes`) integration in Melodic Pathfinder (Major & Minor keys)
--   + v2.50-beta.5: Hotfix: Fix `AudioPreview.play_note` `userdata` state indexing crash in MIDI Keyboard Step Input & Circle of Fifths click audition + add global `ImGuiGuardService` stack auto-unwinder preventing `Missing EndChild()` / `Missing End()` errors across all UI modals, drawers & panels + add clear visual gap between Clef and Key Signature in Continuous & Page View + immediate cache invalidation after Scale Transposition
--   + v2.50-beta.4: New: Circle of Fifths & Global Harmonic Chord Palette Modal (`🎡 Circle of Fifths` below Step Input in Sidebar with 8 drag-and-drop tiles, click-to-audition, dynamic harmonic tension calculation & Circle re-coloring, and global multi-tab REAPER persistence) + MIDI Keyboard Step Input in Record Modal (writes 1 Grid length per played note/chord with full Auto-Divisi support) + Key Signature & Scale Note Input fixes across Mouse Drawing (`[D]`), Step Input (`[S]`), Vertical Note Dragging, `♮ Natural [0]` override & `🎼 Set Key Signature` in Scale Modal
--   + v2.50-beta.3: Hotfix: Extend Percussion Clef staff mapping (`GM_DRUM_STEP_MAP`) across the full MIDI pitch range C0–C9 (`0..127`) so pitching notes below C2 (`< 35`) or above A5 (`> 81`) always keeps them centered in the Percussion System without ledger-line jumps
--   + v2.50-beta.2: Hotfix: Restore Percussion Clef staff mapping (`GM_DRUM_STEP_MAP` & `GM_STEP_TO_DRUM_PITCH`) exactly as in v2.50-beta while keeping automatic Cross/Percussion noteheads disabled (manual assignment only via right-click menu) + display `Percussion` in track header subtitle
--   + v2.50-beta.1: Hotfix: Do not automatically convert notes in Percussion Clef systems to percussion noteheads (`x`, `circle_x`, `triangle`, `diamond`) — all notes default to standard noteheads (`●`) unless manually changed via the right-click menu (`🥁 Notehead / Percussion Head`)
--   + v2.50-beta: New: Automatic Percussion Clef detection (`percussion_1`) from track names for true unpitched drums & percussion (`Snare`, `Drums`, `Drumset`, `Bass Drum` / `Gran Cassa`, `Kick`, `Toms`, `Taiko`, `Timbales`, `Bongos`, `Congas`, `Djembe`, `Cajon`, `Tambourine`, `Cymbals`, `Hi-Hat`, `Gong`, `Woodblock`, `Claves`, `Castanets`, `Shaker`, `Cowbell`, `Triangle`, `Percussion` / `Schlagzeug`) while strictly excluding pitched percussion (`Timpani` / `Pauken` -> Bass Clef, `Xylophone` / `Marimba` / `Vibraphone` / `Glockenspiel` / `Tubular Bells` / `Steel Drum` -> Treble Clef, `Celesta` -> Grand Staff)
--   + v2.49-beta: Hotfix: Delete all associated Type 15 notation events (`NOTE`, `NOTATOR_NOTEHEAD`, `NOTATOR_STEM`, `NOTATOR_CHORD_ORIG`, `NOTATOR_ARPEGGIO`, `TRILL`) and `ProjExtState` records when deleting notes + auto-purge orphaned Type 15 events on take parse + flush `2.5*s` stem attachment on `slash` and `diamond` noteheads
--   + v2.48-beta: Hotfix: Exact Elaine Gould & SMuFL stem attachment coordinates (`get_notehead_stem_attachment`), glyph centering & flag scaling (`32*s`) for all 9 Percussion & Custom Noteheads (`standard`, `x`, `circle_x`, `diamond`, `triangle`, `triangle_down`, `plus`, `slash`, `square`) so stems connect cleanly to every notehead contour and downward flags never touch the right side of the notehead
--   + v2.47-beta: New: Percussion & Custom Notehead Selector in Right-Click Context Menu (`🥁 Notehead / Percussion Head`) supporting single and multi-note selections across all 9 SMuFL / Elaine Gould notehead shapes (`standard`, `x`, `circle_x`, `diamond`, `triangle`, `triangle_down`, `plus`, `slash`, `square`, plus `auto`) with MIDI Type 15 (`NOTATOR_NOTEHEAD` / `NOTE head`), `ProjExtState`, Clipboard Copy/Paste & MusicXML `<notehead>` persistence
--   + v2.46-beta: Hotfix: Fix Step Input crash (`AudioPreview` require in `KeyboardHandler`), protect `KeyboardHandler` with `pcall` so `ImGui_End` is never skipped, and fix 5 undeclared global variable references (`_cached_banks`, `is_hov`, `eff_bank`, `all_have_target`, `SlurService`) caught by the new strict `_G` metatable guard in the unit test suite
--   + v2.45-beta: Comprehensive Automated Unit Test & Fuzzing Suite across all 78 Lua modules (604 exported functions, 149 test cases) + defensive nil/type safety across all 15 data classes, Engraver beam/tuplet coordinate fallbacks, SystemEngraver vertical layout fallbacks, ClipboardService argument-order resilience, and MIDI Editor track color safety
--   + v2.44-beta: Complete Elaine Gould ("Behind Bars") & Gardner Read Engraving Compliance: 32nd/64th beam & flag stem lengthening with inner-beam clearance, paired fractional beam stub direction, strict 2-side chord 2nd alternation, dotted chord 2nd collision resolution, staff-line-avoiding articulation placement, slur stem/articulation clearance & chord user-tie outward splitting, tuplet bracket staff/stem/articulation clearance, glissando/portamento dot & accidental gaps, and curved S-bezier Piano/Harp accolade brace (`{`)
--   + v2.43-beta: New: Elaine Gould ("Behind Bars") Optical Spacing & Engraving Engine: Non-linear proportional intra-measure spacing (Δt^0.70), dynamic collision-free measure expansion, intra-bar accidental memory & natural (♮) cancellation, multi-column chord accidental stacking, line-avoiding augmentation dots, middle-line ledger stem extension, and tapered crescent ties & slurs
--   + v2.42-beta: Hotfix: Break beam groups across intervening rests so beams and 16th stubs never collide with rest glyphs + preserve nominal notation durations on Melodic Pathfinder staccato notes
--   + v2.41-beta: Hotfix: Fix Melodic Pathfinder freeze on Reversed + Counter-Melody patterns, auto-jump Edit Cursor to start of selected note pattern & preserve pattern anchor across insertions
--   + v2.40-beta: Hotfix: Auto-Divisi live Note-On voice handover & legato preemption when moving a finger while holding a chord
--   + v2.39-beta: Hotfix: Prevent Auto-Divisi Input JSFX Router from popping up floating FX windows on startup or when arming tracks
--   + v2.38-beta: Hotfix: Block all keyboard shortcuts while renaming Annotation Layers + fix multiline string syntax in Auto-Divisi JSFX router
--   + v2.37-beta: Improvement: Live Audible Auto-Divisi Input FX Router (1 played note = 1 instrument heard in both Smart Register & Top-Down modes, C2 -> Double Bass) + Recording Modal footer gap
--   + v2.36-beta: New: Auto-Divisi Recording Mode (Smart Register & Voice Split across armed tracks with Tick-based chord & legato transition tolerance) + responsive Recording Modal layout
--   + v2.35-beta: New: Replace Tracks modal button with wider View-style Tracks dropdown featuring Auto-Detect Tracks, Check/Uncheck All buttons & crash-safe project-scoped persistence
--   + v2.34-beta: Improvement: Match tile aspect ratio to portrait bar-band geometry (280x420 to 840x1260 px) + Analytical Capsule SDF & 1.25px Smoothstep AA + Quadratic Bezier curve smoothing
--   + v2.33-beta: Hotfix: Eliminate dark bilinear alpha-bleed fringe (Saum / Premultiply effect) via 3.5px transparent color-bleed guard collar around strokes
--   + v2.32-beta: Hotfix: Aspect-correct annotation brush stamps per bar width so vertical and horizontal strokes have identical screen thickness
--   + v2.31-beta: Fix IDAT CRC error & missing-file crash on stroke; add 4-step per-instrument tile resolution selector (1x/1.5x/2x/3x) & 0-latency vector pen preview
--   + v2.30-beta: Improvement: Upgrade per-bar annotation tile resolution to 640x440 px (4.4x pixels) with crisp 0.35px brush edge & row-cached PNG encoding
--   + v2.29-beta: Hotfix: Define AnnotationService.MAX_TRACK_SPACING constant in ScoreCanvas & AnnotationService
--   + v2.28-beta: New: Per-Track Annotation Layer System (12 color presets, freehand Pen & Eraser, lazy 320x200 per-bar PNG tiles & auto-cleanup)
--   + v2.27-beta: Hotfix: Persist manual stem flips (X) via NOTATOR_STEM / NOTE stem tags & ProjExtState, and align 3rd-space stems in low-weighted measures
--   + v2.26-beta: Hotfix: Fix chord/dyad beam grouping, middle-line stem direction & move Tracks button right of All Notes dropdown
--   + v2.19-beta: Melodic Pathfinder: Clef Register Intelligence, Audition Wakeup & Film Composer Styles 1-4
--   + v2.18-beta: New: Melodic Pathfinder & Counter-Melody Generator (Corpus-trained Viterbi inpainting, Inversion & Reference Track Harmony)
--   + v2.17: New: 300 Percussion & Low Strings patterns (1,500 total) + Pattern Browser UI refinements
--   + v2.16: Hotfix: Fix severe UI lag when docked in REAPER Docker
--   + v2.15: New: Divisi (split voices to duplicated tracks)
--   + v2.14: Hotfix: Fix AudioPreview require in MidiService
--   + v2.13: Hotfix: Pattern Browser instrument selection & track preview routing
--   + v2.12: Hotfix: Pattern Browser full-length playback
--   + v2.11: Hotfix: Multi-note selection preserved on right-click (Filter Selection & context menu)
--   + v2.10: Staccato dots on all selected notes, pre-staccato articulation auto-chase, slur legato playback & note audition accuracy
--   + v2.0.7: Clean note audition (no REC badge), static canvas focus on click, MusicXML performance optimization, 4K HiDPI maximize & 60-144 FPS native timer
--   + v2.0.4: Reaticulate FX Slot 1 auto-setup, primary bank replacement, empty-item cursor articulations & note-to-item selection sync
--   + v2.0.0: Transport Record button, Record Settings modal, live canvas recording preview & Auto-Quantize engine
--   + v1.9.9: Filter Irregular Notes modal, multi-monitor window persistence & Gould polyphonic rest consolidation
--   + v1.9.8: Metric consolidation of tied note chains & full-measure whole note engraving
--   + v1.9.0: Divisio Vocum (voice distribution), live MIDI item boundary scaling & grid shortcuts
--   + v1.8.0: Integrated multi-lane MIDI Editor (Velocity & 128 CC lanes), playback performance overhaul & modernized Settings
--   + v1.7.0: Elaine Gould slurs, glissandi, portamento & bidirectional MusicXML 4.0
--   + v1.5.0: Anti-aliased beam rendering, keyboard note navigation, Dark Mode & Settings overhaul
--   + v1.4.0: Fermatas, Rehearsal Marks, Arpeggios & MusicXML 4.0 integration
--   + v1.0.0: Initial public release
-- @about
--   # REAPER-Notator
--   Native musical notation, score editing, and engraving environment for Cockos REAPER.
--   Requires ReaImGui v0.10+ (Dear ImGui for REAPER by cfillion) and Reaticulate.
--   Features SMuFL font rendering, intelligent beaming, dynamics CC automation,
--   articulations drawer, MusicXML import/export, and seamless DAW integration.
-- @provides
--   modules/**
--   docs/**
-- @license GPL-3.0
--
-- ==============================================================================
-- Copyright (C) 2026 A-intheCode
--
-- LEGAL NOTICE: Any copying or use of code from REAPER-Notator is not permitted
-- without an express written agreement with the author (A-intheCode).
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program. If not, see <https://www.gnu.org/licenses/>.
-- ==============================================================================
-- REAPER Native Notator (Pro Edition) - Modular Main Entry Point
-- 100% Native Notation Editor for Cockos REAPER
-- Class-based architecture with modular multi-file structure
-- Original 3-column layout (Sidebar left, Canvas center, Dynamics drawer right)
-- ==============================================================================

-- 1. Path configuration for module requires
local script_source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local script_dir = script_source:match("(.*/)") or ""
if script_dir:sub(-1) ~= "/" then script_dir = script_dir .. "/" end

package.path = script_dir .. "?.lua;"
            .. script_dir .. "?/init.lua;"
            .. script_dir .. "modules/?.lua;"
            .. script_dir .. "modules/?/init.lua;"
            .. package.path


-- 0. Dev-Mode Cache Clearing
for k in pairs(package.loaded) do
    if k:match("^version") or k:match("^constants") or k:match("^state") or k:match("^classes%.") or k:match("^services%.") or k:match("^rendering%.") or k:match("^ui%.") or k:match("^input%.") then
        package.loaded[k] = nil
    end
end

-- 2. ReaImGui initialization & version check
if not reaper.APIExists("ImGui_CreateContext") then
    local err_msg = "ReaImGui (v0.10+) is required for REAPER Notator to run!\n\n" ..
        "How to install or update ReaImGui (v0.10+):\n" ..
        "1. Open REAPER: Extensions -> ReaPack -> Browse packages\n" ..
        "2. Search for 'ReaImGui' (by cfillion)\n" ..
        "3. Right-click 'ReaImGui: Dear ImGui for Cockos REAPER' -> Install / Update to v0.10+\n" ..
        "4. Click 'Apply' in the bottom right corner of ReaPack and restart REAPER.\n\n" ..
        "Official ReaPack Repository URL:\n" ..
        "https://github.com/cfillion/reapack-index/raw/master/index.xml"
    reaper.MB(err_msg, "REAPER Notator - Missing Dependency: ReaImGui", 0)
    return
end

local cfg_flags = reaper.APIExists("ImGui_ConfigFlags_None") and reaper.ImGui_ConfigFlags_None() or 0
local ctx = reaper.ImGui_CreateContext("REAPER Native Notator", cfg_flags)

-- 2b. Enable multi-edge window resizing (all 4 edges and corners)
if reaper.APIExists("ImGui_SetConfigVar") and reaper.APIExists("ImGui_ConfigVar_WindowsResizeFromEdges") then
    reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_WindowsResizeFromEdges(), 1)
end

-- 3. Load modules
local Constants           = require("constants")
local State               = require("state")
local PathService         = require("services.path_service")
local MidiService         = require("services.midi_service")
local ClipboardService    = require("services.clipboard_service")
local DynamicsEngine      = require("services.dynamics_engine")
local Engraver            = require("rendering.engraver")
local FontManager         = require("rendering.font_manager")
local ScoreCanvas         = require("rendering.score_canvas")
local Sidebar             = require("ui.sidebar")
local TopBar              = require("ui.top_bar")
local TrackPicker         = require("ui.track_picker")
local DynamicsDrawer      = require("ui.dynamics_drawer")
local BottomBar           = require("ui.bottom_bar")
local HelpModal           = require("ui.help_modal")
local QuantizeModal       = require("ui.quantize_modal")
local MouseHandler        = require("input.mouse_handler")
local KeyboardHandler     = require("input.keyboard_handler")
local SettingsModal       = require("ui.settings_modal")
local ShortcutManager     = require("services.shortcut_manager")
local TempoService        = require("services.tempo_service")
local TempoDrawer         = require("ui.tempo_drawer")
local ToolsDrawer         = require("ui.tools_drawer")
local ClefDrawer          = require("ui.clef_drawer")
local ArticulationsDrawer = require("ui.articulations_drawer")
local BankPickerModal     = require("ui.bank_picker_modal")
local OctaveService       = require("services.octave_service")
local HairpinService      = require("services.hairpin_service")
local DynamicTextService  = require("services.dynamic_text_service")
local PedalService        = require("services.pedal_service")
local TextItemService     = require("services.text_item_service")
local RepeatService       = require("services.repeat_service")
local FermataService      = require("services.fermata_service")
local RehearsalMarkService= require("services.rehearsal_mark_service")
local AudioPreview        = require("services.audio_preview")
local PatternService      = require("services.pattern_service")
local PatternBrowser      = require("ui.pattern_browser")
local ScaleService        = require("services.scale_service")
local ScaleModal          = require("ui.scale_modal")
local KeySignatureService  = require("services.key_signature_service")
local KeySignatureDrawer   = require("ui.key_signature_drawer")
local MusicXmlModal        = require("ui.musicxml_modal")
local SlurService          = require("services.slur_service")
local PortamentoService    = require("services.portamento_service")
local GlissandoService     = require("services.glissando_service")
local AnnotationService    = require("services.annotation_service")
local AnnotationDrawer     = require("ui.annotation_drawer")
local MidiEditorDrawer     = require("ui.midi_editor_drawer")
local function safe_require(mod_name, fallback)
    local ok, mod = pcall(require, mod_name)
    if ok and mod then return mod end
    return fallback
end

local DivisioVocumModal     = safe_require("ui.divisio_vocum_modal", { render = function() end })
local DivisiModal           = safe_require("ui.divisi_modal", { render = function() end })
local MelodyPathfinderModal = safe_require("ui.melody_pathfinder_modal", { render = function() end })
local ExplodeChordsModal    = DivisioVocumModal
local FilterIrregularModal  = safe_require("ui.filter_irregular_modal", { render = function() end })
local RecordModal           = safe_require("ui.record_modal", { render = function() end })
local CircleOfFifthsService = safe_require("services.circle_of_fifths_service", {})
local CircleOfFifthsModal   = safe_require("ui.circle_of_fifths_modal", { render = function() end })
local ImGuiGuardService     = safe_require("services.imgui_guard_service", {
    install = function() end,
    safe_render = function(_ctx, _st, _lbl, fn, ...) return pcall(fn, ...) end,
    snapshot = function() return nil end,
    unwind_to_snapshot = function() end,
})
ImGuiGuardService.install(reaper)
local UndoStateService      = safe_require("services.undo_state_service", {
    install = function() end,
    init_from_project = function() end,
    on_undo = function() return false end,
    on_redo = function() return false end,
    on_external_new_action = function() end,
    commit_uncommitted_if_idle = function() return false end,
})
UndoStateService.install(reaper)
local RecordQuantizeService = safe_require("services.record_quantize_service", {
    on_record_start = function() end,
    process_recording = function() end,
    update_live_recording = function() end,
    update_midi_step_input = function() end
})

-- 4. Initialization of State & Fonts
local state = State.new()
SettingsModal.apply_theme(state)
PathService.cleanup_legacy_artifacts(state)
ShortcutManager.init()
KeySignatureService.load(state)
FermataService.load_fermatas(state)
TempoService.load_markers(state)
OctaveService.load_lines(state)
HairpinService.load_hairpins(state)
DynamicTextService.load_dynamic_texts(state)
PedalService.load_pedals(state)
TextItemService.load_text_items(state)
RepeatService.load_repeat_marks(state)
RehearsalMarkService.load_marks(state)
ScaleService.load_chord_items(state)
SlurService.load_slurs(state)
PortamentoService.load_portamentos(state)
GlissandoService.load_glissandos(state)
AnnotationService.load_metadata(state)
MidiService.load_stem_directions(state)
MidiService.load_notehead_types(state)
MidiService.cleanup_orphaned_score_elements(state)
UndoStateService.init_from_project()
state.current_reaproject, state.current_proj_fn = reaper.EnumProjects(-1)
state._last_proj_change_cleanup = reaper.GetProjectStateChangeCount(0)
state._last_total_tracks_cleanup = reaper.CountTracks(0)
state._last_can_undo_str = (reaper.Undo_CanUndo2 and reaper.Undo_CanUndo2(0)) or ""
state._last_can_redo_str = (reaper.Undo_CanRedo2 and reaper.Undo_CanRedo2(0)) or ""
PatternService.init()
if RecordQuantizeService and RecordQuantizeService.sync_auto_divisi_input_fx then
    RecordQuantizeService.sync_auto_divisi_input_fx(state, true)
end
local fonts = FontManager.init(ctx, state)
local FrameTimerService = safe_require("services.frame_timer_service", {
    init = function() return false end,
    apply_target_fps = function() return false end,
    tick = function() end,
    restore = function() end,
})
FrameTimerService.init(state)
local initial_dep_status = PathService.detect_status(state)
local reaticulate_installed = initial_dep_status.reaticulate_found

reaper.atexit(function()
    FrameTimerService.restore()
    AudioPreview.stop_all(state)
    if RecordQuantizeService and RecordQuantizeService.cleanup_all_auto_divisi_input_fx then
        pcall(RecordQuantizeService.cleanup_all_auto_divisi_input_fx)
    end
    -- Safely persist all Notator objects & settings before script exit / REAPER shutdown:
    TempoService.save_markers(state)
    OctaveService.save_lines(state)
    HairpinService.save_hairpins(state)
    DynamicTextService.save_dynamic_texts(state)
    PedalService.save_pedals(state)
    TextItemService.save_text_items(state)
    RepeatService.save_repeat_marks(state)
    FermataService.save_fermatas(state)
    RehearsalMarkService.save_marks(state)
    ScaleService.save_chord_items(state)
    KeySignatureService.save(state)
    SlurService.save_slurs(state)
    PortamentoService.save_portamentos(state)
    GlissandoService.save_glissandos(state)
    AnnotationService.commit_dirty_tiles(state, true)
    AnnotationService.save_metadata(state)
    MidiService.save_stem_directions(state)
    MidiService.save_notehead_types(state)
    state:save_settings()
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
end)

-- 5. Main Render Loop (Native High-Refresh Timer Engine with Configurable Target FPS)
local last_frame_time = 0
local frame_count = 0
local fps_timer = 0
local skipped_ticks = 0

local function loop()
    if not state.is_open then
        FrameTimerService.restore()
        return
    end
    if reaper.APIExists("ImGui_ValidatePtr") and not reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
        FrameTimerService.restore()
        return
    end

    -- Synchronize native Win32 0x29a timer with state.target_fps & update heartbeat
    FrameTimerService.tick(state)

    -- Framerate Throttling (Fallback only when native timer bridge is unavailable) & FPS Meter
    local target_fps = state.target_fps or 60
    local now = reaper.time_precise()
    if not FrameTimerService._available and target_fps > 0 and target_fps <= 20 then
        local min_dt = 1.0 / target_fps
        if (now - last_frame_time) < (min_dt - 0.002) and skipped_ticks < 1 then
            skipped_ticks = skipped_ticks + 1
            AudioPreview.update(state, ctx)
            PatternService.update_preview(AudioPreview)
            reaper.defer(loop)
            return
        end
    end
    skipped_ticks = 0

    frame_count = frame_count + 1
    if fps_timer == 0 then
        fps_timer = now
    elseif (now - fps_timer) >= 0.4 then
        state.measured_fps = frame_count / (now - fps_timer)
        frame_count = 0
        fps_timer = now
    end
    last_frame_time = now

    -- Project-specific data (tempo markers, octave lines, hairpins, pedals, text items, repeat marks & chord items):
    -- Check every frame if the active REAPER project changed or was reloaded
    if not state.reload_score_from_project then
        state.reload_score_from_project = function(st)
            MidiService.invalidate_cache()
            st.active_tracks_cache = nil
            st.cached_measure_map = nil
            st.cached_measure_map_sig = nil
            KeySignatureService.load(st, true)
            FermataService.load_fermatas(st, true)
            TempoService.load_markers(st, true)
            OctaveService.load_lines(st, true)
            HairpinService.load_hairpins(st, true)
            DynamicTextService.load_dynamic_texts(st, true)
            PortamentoService.load_portamentos(st, true)
            PedalService.load_pedals(st, true)
            TextItemService.load_text_items(st, true)
            RepeatService.load_repeat_marks(st, true)
            RehearsalMarkService.load_marks(st, true)
            ScaleService.load_chord_items(st)
            SlurService.load_slurs(st, true)
            GlissandoService.load_glissandos(st, true)
            AnnotationService.load_metadata(st)
            MidiService.load_stem_directions(st)
            MidiService.load_notehead_types(st)
        end
    end

    local cur_proj, proj_fn = reaper.EnumProjects(-1)
    if state.current_reaproject ~= cur_proj or state.current_proj_fn ~= proj_fn then
        state.current_reaproject = cur_proj
        state.current_proj_fn = proj_fn
        MidiService.invalidate_cache()
        state:load_settings()
        SettingsModal.apply_theme(state)
        KeySignatureService.load(state)
        FermataService.load_fermatas(state)
        TempoService.load_markers(state)
        OctaveService.load_lines(state)
        HairpinService.load_hairpins(state)
        DynamicTextService.load_dynamic_texts(state)
        PedalService.load_pedals(state)
        TextItemService.load_text_items(state)
        RepeatService.load_repeat_marks(state)
        RehearsalMarkService.load_marks(state)
        ScaleService.load_chord_items(state)
        SlurService.load_slurs(state)
        PortamentoService.load_portamentos(state)
        GlissandoService.load_glissandos(state)
        AnnotationService.load_metadata(state)
        MidiService.load_stem_directions(state)
        MidiService.load_notehead_types(state)
        MidiService.cleanup_orphaned_score_elements(state)
        UndoStateService.init_from_project()
        state._last_proj_change_cleanup = reaper.GetProjectStateChangeCount(0)
        state._last_total_tracks_cleanup = reaper.CountTracks(0)
        state._last_can_undo_str = (reaper.Undo_CanUndo2 and reaper.Undo_CanUndo2(0)) or ""
        state._last_can_redo_str = (reaper.Undo_CanRedo2 and reaper.Undo_CanRedo2(0)) or ""
        state._consecutive_undo_steps = 0
        state:clear_selection()
    end

    -- Recording state monitoring, Live Note Preview & Auto-Quantize trigger
    local play_state = reaper.GetPlayState()
    local is_recording = (play_state & 4) == 4
    if is_recording and not state._was_recording then
        state._was_recording = true
        state._rec_start_time = reaper.GetPlayPosition()
        state._last_rec_play_pos = state._rec_start_time
        RecordQuantizeService.on_record_start(state)
    elseif not is_recording and state._was_recording then
        state._was_recording = false
        local rec_stop_time = state._last_rec_play_pos or reaper.GetPlayPosition()
        RecordQuantizeService.process_recording(state, state._rec_start_time, rec_stop_time)
    end
    if is_recording then
        state._last_rec_play_pos = reaper.GetPlayPosition()
        RecordQuantizeService.update_live_recording(state)
    elseif RecordQuantizeService and RecordQuantizeService.update_midi_step_input then
        RecordQuantizeService.update_midi_step_input(state, MidiService)
    end

    -- Authentic dark pro color theme
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),       0x151619FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(),        0x1E2025FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),         0x2A2D35FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0x282B33FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0xE67E22FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   0xFF9F1CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),           0xF0F0F0FF)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 6.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),  4.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),    8.0, 6.0)

    -- Locate REAPER Notator's own native OS top-level window handle (HWND) for exact per-monitor rect & DPI calibration.
    -- IMPORTANT: Never call JS_Window_Find (which recursively walks all child HWNDs of all processes on the Windows desktop
    -- and causes severe lag when the window is docked into REAPER's Docker). Only query JS_Window_FindTop when floating,
    -- and throttle retries if the top-level window is not currently present (e.g. while docked).
    local function get_notator_hwnd()
        if state.is_window_docked then
            state._notator_hwnd = nil
            return nil
        end
        if state._notator_hwnd and reaper.APIExists("JS_Window_IsWindow") and reaper.JS_Window_IsWindow(state._notator_hwnd) then
            return state._notator_hwnd
        end
        state._notator_hwnd = nil
        local now_t = reaper.time_precise()
        if state._last_hwnd_lookup_time and (now_t - state._last_hwnd_lookup_time) < 0.5 then
            return nil
        end
        state._last_hwnd_lookup_time = now_t
        local hwnd = nil
        if reaper.APIExists("JS_Window_FindTop") then
            hwnd = reaper.JS_Window_FindTop("REAPER Notator", true)
        end
        state._notator_hwnd = hwnd
        return hwnd
    end

    -- Determine maximum possible screen work area (excluding taskbars) for the monitor where the window is located.
    -- Uses live OS HWND rectangle vs. ReaImGui window metrics so mixed-DPI multi-monitor setups (e.g. 4K laptop + 1080p monitor)
    -- always calibrate to 100% of the target monitor with zero GetMainViewport cross-monitor pollution.
    local function get_screen_work_area(wx, wy, ww, wh)
        local hwnd = get_notator_hwnd()
        if hwnd and reaper.APIExists("JS_Window_GetRect") then
            local ok_w, wl, wt, wr, wb = reaper.JS_Window_GetRect(hwnd)
            if ok_w and wl and wt and wr and wb and math.abs(wr - wl) > 100 and math.abs(wb - wt) > 100 then
                local win_l = math.min(wl, wr)
                local win_r = math.max(wl, wr)
                local win_t = math.min(wt, wb)
                local win_b = math.max(wt, wb)
                local os_ww = win_r - win_l
                local os_wh = win_b - win_t

                local cl_l, cl_t, cl_r, cl_b = win_l, win_t, win_r, win_b
                if reaper.APIExists("JS_Window_GetClientRect") then
                    local ok_c, c1, c2, c3, c4 = reaper.JS_Window_GetClientRect(hwnd)
                    if ok_c and c1 and c2 and c3 and c4 then
                        local ct_l = math.min(c1, c3)
                        local ct_r = math.max(c1, c3)
                        local ct_t = math.min(c2, c4)
                        local ct_b = math.max(c2, c4)
                        if ct_l == 0 and ct_t == 0 and (math.abs(win_l) > 2 or math.abs(win_t) > 2) and reaper.APIExists("JS_Window_ClientToScreen") then
                            local sx1, sy1 = reaper.JS_Window_ClientToScreen(hwnd, 0, 0)
                            local sx2, sy2 = reaper.JS_Window_ClientToScreen(hwnd, ct_r, ct_b)
                            if sx1 and sy1 and sx2 and sy2 then
                                cl_l = math.min(sx1, sx2)
                                cl_r = math.max(sx1, sx2)
                                cl_t = math.min(sy1, sy2)
                                cl_b = math.max(sy1, sy2)
                            end
                        elseif (ct_r - ct_l) > 50 and (ct_b - ct_t) > 50 then
                            cl_l, cl_t, cl_r, cl_b = ct_l, ct_t, ct_r, ct_b
                        end
                    end
                end

                local os_cw = math.max(100, cl_r - cl_l)
                local os_ch = math.max(100, cl_b - cl_t)

                local ml, mt, mr, mb = nil, nil, nil, nil
                if reaper.APIExists("JS_Window_GetViewportFromRect") then
                    ml, mt, mr, mb = reaper.JS_Window_GetViewportFromRect(win_l, win_t, win_r, win_b, true)
                end
                if (not ml or not mr or math.abs(mr - ml) <= 300) and reaper.my_getViewport then
                    local cx = math.floor((win_l + win_r) * 0.5)
                    local cy = math.floor((win_t + win_b) * 0.5)
                    ml, mt, mr, mb = reaper.my_getViewport(0, 0, 0, 0, cx, cy, cx, cy, true)
                end

                if ml and mt and mr and mb then
                    local mon_l = math.min(ml, mr)
                    local mon_r = math.max(ml, mr)
                    local mon_t = math.min(mt, mb)
                    local mon_b = math.max(mt, mb)
                    local mon_w = mon_r - mon_l
                    local mon_h = mon_b - mon_t

                    if mon_w > 300 and mon_h > 300 then
                        local cur_imgui_x = state.cur_win_x or wx
                        local cur_imgui_y = state.cur_win_y or wy
                        local cur_imgui_w = state.cur_win_w or ww
                        local cur_imgui_h = state.cur_win_h or wh

                        if cur_imgui_x and cur_imgui_y and cur_imgui_w and cur_imgui_h and cur_imgui_w > 100 and cur_imgui_h > 100 then
                            local scale_x = os_cw / cur_imgui_w
                            local scale_y = os_ch / cur_imgui_h
                            if scale_x < 0.25 or scale_x > 4.0 then scale_x = 1.0 end
                            if scale_y < 0.25 or scale_y > 4.0 then scale_y = 1.0 end

                            local frame_w = math.max(0, os_ww - os_cw)
                            local frame_h = math.max(0, os_wh - os_ch)

                            local vx = cur_imgui_x + (mon_l - win_l) / scale_x
                            local vy = cur_imgui_y + (mon_t - win_t) / scale_y
                            local vw = (mon_w - frame_w) / scale_x
                            local vh = (mon_h - frame_h) / scale_y

                            local err_x = math.abs(win_l - mon_l) + math.abs(os_ww - mon_w)
                            local err_y = math.abs(win_t - mon_t) + math.abs(os_wh - mon_h)

                            return math.floor(vx + 0.5), math.floor(vy + 0.5), math.floor(vw + 0.5), math.floor(vh + 0.5), (err_x <= 6 and err_y <= 6)
                        end
                    end
                end
            end
        end

        -- Fallback before HWND creation on frame 1 or when JS_ReaScriptAPI is unavailable
        if reaper.my_getViewport and wx and wy and ww and wh then
            local cx = wx + math.floor(ww * 0.5)
            local cy = wy + math.floor(wh * 0.5)
            local n_cx, n_cy = cx, cy
            if reaper.APIExists("ImGui_PointConvertNative") then
                local ok_cnv, nx, ny = pcall(reaper.ImGui_PointConvertNative, ctx, cx, cy, true)
                if ok_cnv and nx and ny then
                    n_cx, n_cy = nx, ny
                end
            end
            local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0, n_cx, n_cy, n_cx, n_cy, true)
            if l and t and r and b and math.abs(r - l) > 300 and math.abs(b - t) > 300 then
                local mon_l = math.min(l, r)
                local mon_r = math.max(l, r)
                local mon_t = math.min(t, b)
                local mon_b = math.max(t, b)
                if reaper.APIExists("ImGui_PointConvertNative") then
                    local ok1, cl, ct = pcall(reaper.ImGui_PointConvertNative, ctx, mon_l, mon_t, false)
                    local ok2, cr, cb = pcall(reaper.ImGui_PointConvertNative, ctx, mon_r, mon_b, false)
                    if ok1 and ok2 and cr and cl and math.abs(cr - cl) > 300 and cb and ct and math.abs(cb - ct) > 300 then
                        local rl = math.min(cl, cr)
                        local rr = math.max(cl, cr)
                        local rt = math.min(ct, cb)
                        local rb = math.max(ct, cb)
                        return rl, rt, (rr - rl), (rb - rt), false
                    end
                end
                return mon_l, mon_t, (mon_r - mon_l), (mon_b - mon_t), false
            end
        end

        return 0, 0, 1920, 1080, false
    end

    -- Helper: Computes a proportional centered window rectangle in the middle of the given screen work area (vx, vy, vw, vh)
    -- Free of any hardcoded 1280x720 or 16:9 aspect ratio constraints.
    local function get_small_centered_bounds(vx, vy, vw, vh)
        local min_w = math.min(640, math.max(360, math.floor(vw * 0.35)))
        local min_h = math.min(420, math.max(260, math.floor(vh * 0.35)))
        local def_w = math.floor(vw * 0.78 + 0.5)
        local def_h = math.floor(vh * 0.78 + 0.5)
        local target_rw = state.prev_win_w or def_w
        local target_rh = state.prev_win_h or def_h
        if target_rw >= math.floor(vw * 0.92) or target_rh >= math.floor(vh * 0.92) then
            target_rw = def_w
            target_rh = def_h
        end
        local rw = math.max(min_w, math.min(vw - 20, target_rw))
        local rh = math.max(min_h, math.min(vh - 20, target_rh))
        local rx = vx + math.floor((vw - rw) * 0.5)
        local ry = vy + math.floor((vh - rh) * 0.5)
        if rx < vx then rx = vx end
        if ry < vy then ry = vy end
        if rx + rw > vx + vw then rx = math.max(vx, vx + vw - rw) end
        if ry + rh > vy + vh then ry = math.max(vy, vy + vh - rh) end
        return rx, ry, rw, rh, min_w, min_h
    end

    local cur_x = state.cur_win_x or state.prev_win_x or 100
    local cur_y = state.cur_win_y or state.prev_win_y or 60
    local cur_w = state.cur_win_w or state.prev_win_w or 1000
    local cur_h = state.cur_win_h or state.prev_win_h or 650

    local vx = state.screen_work_x or 0
    local vy = state.screen_work_y or 0
    local vw = state.screen_work_w or 1920
    local vh = state.screen_work_h or 1080

    if state.is_window_docked then
        -- When docked into REAPER's Docker, never force floating window pos/size/constraints or maximize stages
        state.request_maximize_toggle = false
        state.is_maximized = false
        state._maximize_stage = 0
        state.just_restored = false
    else
        if state.request_maximize_toggle then
            state.request_maximize_toggle = false
            if not state.is_maximized and (state._maximize_stage or 0) == 0 then
                -- Step 1 of Maximize: Read maximum possible screen size of target monitor, place window in center first
                vx, vy, vw, vh = get_screen_work_area(cur_x, cur_y, cur_w, cur_h)
                state.screen_work_x = vx
                state.screen_work_y = vy
                state.screen_work_w = vw
                state.screen_work_h = vh
                state._maximize_stage = 1
            else
                -- Unmaximize / Restore to centered window on current display
                state.is_maximized = false
                state._maximize_stage = 0
                state.just_restored = true
                state.status_msg = "Window size restored"
            end
        end

        local min_w = math.min(640, math.max(360, math.floor(vw * 0.35)))
        local min_h = math.min(420, math.max(260, math.floor(vh * 0.35)))

        if state._maximize_stage == 1 then
            -- Stage 1: Place window in centered bounds on the target screen so OS monitor & DPI are locked in
            local rx, ry, rw, rh = get_small_centered_bounds(vx, vy, vw, vh)
            state.prev_win_x = rx
            state.prev_win_y = ry
            state.prev_win_w = rw
            state.prev_win_h = rh
            reaper.ImGui_SetNextWindowPos(ctx, rx, ry, reaper.ImGui_Cond_Always())
            reaper.ImGui_SetNextWindowSize(ctx, rw, rh, reaper.ImGui_Cond_Always())
            state._maximize_stage = 2
            state._window_pos_initialized = true
        elseif state._maximize_stage == 2 then
            -- Stage 2: Window is now centered on the target monitor -> read live HWND scale & maximize to 100% of monitor work area
            vx, vy, vw, vh = get_screen_work_area(cur_x, cur_y, cur_w, cur_h)
            state.screen_work_x = vx
            state.screen_work_y = vy
            state.screen_work_w = vw
            state.screen_work_h = vh
            state.is_maximized = true
            state._maximize_stage = 3
            state._maximize_verify_tries = 0
            state.status_msg = "Window maximized on current display"
            reaper.ImGui_SetNextWindowPos(ctx, vx, vy, reaper.ImGui_Cond_Always())
            reaper.ImGui_SetNextWindowSize(ctx, vw, vh, reaper.ImGui_Cond_Always())
            state._window_pos_initialized = true
        elseif state._maximize_stage == 3 then
            -- Stage 3: Post-maximize closed-loop verification against OS monitor work area (handles cross-monitor DPI changes)
            local cvx, cvy, cvw, cvh, is_exact = get_screen_work_area(cur_x, cur_y, cur_w, cur_h)
            state.screen_work_x = cvx
            state.screen_work_y = cvy
            state.screen_work_w = cvw
            state.screen_work_h = cvh
            vx, vy, vw, vh = cvx, cvy, cvw, cvh
            state._maximize_verify_tries = (state._maximize_verify_tries or 0) + 1
            if is_exact or state._maximize_verify_tries >= 3 then
                state._maximize_stage = 0
            end
            reaper.ImGui_SetNextWindowPos(ctx, vx, vy, reaper.ImGui_Cond_Always())
            reaper.ImGui_SetNextWindowSize(ctx, vw, vh, reaper.ImGui_Cond_Always())
            state._window_pos_initialized = true
        elseif state.is_maximized then
            reaper.ImGui_SetNextWindowPos(ctx, vx, vy, reaper.ImGui_Cond_Always())
            reaper.ImGui_SetNextWindowSize(ctx, vw, vh, reaper.ImGui_Cond_Always())
            state._window_pos_initialized = true
        else
            -- Enforce responsive minimum size without aspect-ratio constraints (only when floating)
            if reaper.APIExists("ImGui_SetNextWindowSizeConstraints") then
                reaper.ImGui_SetNextWindowSizeConstraints(ctx, min_w, min_h, 16384, 16384)
            end

            if state.just_restored or not state._window_pos_initialized or (not state._hwnd_calibrated and not reaper.ImGui_IsMouseDown(ctx, 0) and get_notator_hwnd() ~= nil) then
                -- Both on Restore AND on fresh startup (plus one-shot calibration once native HWND is live):
                -- Read maximum screen work area of target monitor, then place window cleanly in the center of the screen
                vx, vy, vw, vh = get_screen_work_area(cur_x, cur_y, cur_w, cur_h)
                state.screen_work_x = vx
                state.screen_work_y = vy
                state.screen_work_w = vw
                state.screen_work_h = vh
                local rx, ry, rw, rh = get_small_centered_bounds(vx, vy, vw, vh)
                state.prev_win_x = rx
                state.prev_win_y = ry
                state.prev_win_w = rw
                state.prev_win_h = rh
                reaper.ImGui_SetNextWindowPos(ctx, rx, ry, reaper.ImGui_Cond_Always())
                reaper.ImGui_SetNextWindowSize(ctx, rw, rh, reaper.ImGui_Cond_Always())
                if get_notator_hwnd() ~= nil then
                    state._hwnd_calibrated = true
                end
                state.just_restored = false
                state._window_pos_initialized = true
            else
                reaper.ImGui_SetNextWindowSize(ctx, min_w, min_h, reaper.ImGui_Cond_FirstUseEver())
            end
        end
    end

    if not state._config_var_init and reaper.APIExists("ImGui_ConfigVar_WindowsMoveFromTitleBarOnly") and reaper.APIExists("ImGui_SetConfigVar") then
        reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_WindowsMoveFromTitleBarOnly(), 1)
        state._config_var_init = true
    end

    local child_border = reaper.APIExists("ImGui_ChildFlags_Borders") and reaper.ImGui_ChildFlags_Borders() or 1
    local child_none = reaper.APIExists("ImGui_ChildFlags_None") and reaper.ImGui_ChildFlags_None() or 0

    local window_flags = reaper.ImGui_WindowFlags_NoScrollbar()
    if reaper.APIExists("ImGui_WindowFlags_NoCollapse") then
        window_flags = window_flags | reaper.ImGui_WindowFlags_NoCollapse()
    end
    if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
        window_flags = window_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    end
    if reaper.APIExists("ImGui_WindowFlags_NoNav") then
        window_flags = window_flags | reaper.ImGui_WindowFlags_NoNav()
    end
    if reaper.APIExists("ImGui_WindowFlags_NoNavInputs") then
        window_flags = window_flags | reaper.ImGui_WindowFlags_NoNavInputs()
    end
    if state.window_locked or state.drag_note ~= nil or state.is_dragging 
       or state.marquee_active or state.is_dragging_dynamic or state.is_resizing_item 
       or state.dragged_pattern ~= nil or state.is_dragging_pattern then
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            window_flags = window_flags | reaper.ImGui_WindowFlags_NoMove()
        end
    end

    -- Prevent any legacy collapsed state persisted in ReaImGui's .ini file from hiding the UI
    if reaper.APIExists("ImGui_SetNextWindowCollapsed") then
        reaper.ImGui_SetNextWindowCollapsed(ctx, false, reaper.ImGui_Cond_Always())
    end

    local visible, open = reaper.ImGui_Begin(ctx, "REAPER Notator", true, window_flags)
    state.is_open = open

    if visible then
        state._window_pos_initialized = true
        local is_docked = false
        if reaper.APIExists("ImGui_IsWindowDocked") then
            is_docked = reaper.ImGui_IsWindowDocked(ctx)
        end
        if not is_docked and reaper.APIExists("ImGui_GetWindowDockID") then
            local dock_id = reaper.ImGui_GetWindowDockID(ctx)
            if dock_id and dock_id ~= 0 then
                is_docked = true
            end
        end
        if state.is_window_docked and not is_docked then
            -- Just undocked back to floating window -> allow top-level HWND re-lookup without snapping
            state._notator_hwnd = nil
            state._last_hwnd_lookup_time = nil
            state._hwnd_calibrated = true
        elseif is_docked then
            state._notator_hwnd = nil
            state._hwnd_calibrated = true
        end
        state.is_window_docked = is_docked

        reaper.ImGui_SetScrollY(ctx, 0)
        reaper.ImGui_SetScrollX(ctx, 0)
        local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
        local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
        local mx, my = reaper.ImGui_GetMousePos(ctx)

        state.cur_win_x = win_x
        state.cur_win_y = win_y
        state.cur_win_w = win_w
        state.cur_win_h = win_h

        local svw = state.screen_work_w or 1920
        local svh = state.screen_work_h or 1080

        -- Remember current unmaximized floating window size (for clean restoration)
        if not is_docked and not state.is_maximized and (state._maximize_stage or 0) == 0 then
            if win_w >= 360 and win_h >= 260 and (win_w < (svw - 10) or win_h < (svh - 10)) then
                state.prev_win_w = win_w
                state.prev_win_h = win_h
                state.prev_win_x = win_x
                state.prev_win_y = win_y
            end
        end

        -- Periodically persist unmaximized floating window position to ExtState when moved or resized and mouse is released
        if not is_docked and not state.is_maximized and (state._maximize_stage or 0) == 0 then
            if win_x ~= state._last_saved_win_x or win_y ~= state._last_saved_win_y or win_w ~= state._last_saved_win_w or win_h ~= state._last_saved_win_h then
                local is_mouse_down = reaper.ImGui_IsMouseDown(ctx, 0)
                local now = reaper.time_precise()
                if not is_mouse_down or (now - (state._last_win_save_time or 0)) > 2.0 then
                    state._last_saved_win_x = win_x
                    state._last_saved_win_y = win_y
                    state._last_saved_win_w = win_w
                    state._last_saved_win_h = win_h
                    state._last_win_save_time = now
                    reaper.SetExtState("REAPER_Notator", "cur_win_x", tostring(math.floor(win_x)), true)
                    reaper.SetExtState("REAPER_Notator", "cur_win_y", tostring(math.floor(win_y)), true)
                    reaper.SetExtState("REAPER_Notator", "cur_win_w", tostring(math.floor(win_w)), true)
                    reaper.SetExtState("REAPER_Notator", "cur_win_h", tostring(math.floor(win_h)), true)
                    reaper.SetExtState("REAPER_Notator", "win_x", tostring(math.floor(win_x)), true)
                    reaper.SetExtState("REAPER_Notator", "win_y", tostring(math.floor(win_y)), true)
                    reaper.SetExtState("REAPER_Notator", "win_w", tostring(math.floor(win_w)), true)
                    reaper.SetExtState("REAPER_Notator", "win_h", tostring(math.floor(win_h)), true)
                    if state.prev_win_x then
                        reaper.SetExtState("REAPER_Notator", "prev_win_x", tostring(math.floor(state.prev_win_x)), true)
                        reaper.SetExtState("REAPER_Notator", "prev_win_y", tostring(math.floor(state.prev_win_y)), true)
                        reaper.SetExtState("REAPER_Notator", "prev_win_w", tostring(math.floor(state.prev_win_w)), true)
                        reaper.SetExtState("REAPER_Notator", "prev_win_h", tostring(math.floor(state.prev_win_h)), true)
                    end
                end
            end
        end

        -- Double click title bar toggles maximize (only when floating, never when docked)
        if not is_docked and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and my >= win_y and my <= (win_y + 26) and mx >= win_x and mx <= (win_x + win_w - 60) then
            state.request_maximize_toggle = true
        end

        local project_tracks = MidiService.get_project_midi_tracks()

        -- Continuous synchronization, Undo/Redo reload & orphan cleanup upon REAPER project changes or TCP track arm/selection changes
        local cur_proj_change = reaper.GetProjectStateChangeCount(0)
        local cur_total_tracks = reaper.CountTracks(0)
        local cur_sel_sig = MidiService._last_sel_sig
        if state._last_proj_change_cleanup ~= cur_proj_change or state._last_total_tracks_cleanup ~= cur_total_tracks or state._last_arm_sel_sig ~= cur_sel_sig then
            local proj_changed = (state._last_proj_change_cleanup ~= cur_proj_change)
            local tracks_changed = (state._last_total_tracks_cleanup ~= cur_total_tracks)
            state._last_proj_change_cleanup = cur_proj_change
            state._last_total_tracks_cleanup = cur_total_tracks
            state._last_arm_sel_sig = cur_sel_sig

            local prev_can_undo = state._last_can_undo_str
            local cur_can_undo = (reaper.Undo_CanUndo2 and reaper.Undo_CanUndo2(0)) or ""
            local cur_can_redo = (reaper.Undo_CanRedo2 and reaper.Undo_CanRedo2(0)) or ""
            local is_ext_undo = proj_changed and (cur_can_redo ~= "" and prev_can_undo and prev_can_undo ~= "" and cur_can_redo == prev_can_undo)
            local is_ext_redo = proj_changed and (cur_can_undo ~= "" and state._last_can_redo_str and state._last_can_redo_str ~= "" and cur_can_undo == state._last_can_redo_str)
            state._last_can_undo_str = cur_can_undo
            state._last_can_redo_str = cur_can_redo

            if is_ext_undo or is_ext_redo then
                if is_ext_undo then
                    state._consecutive_undo_steps = (state._consecutive_undo_steps or 0) + 1
                    UndoStateService.on_undo(cur_can_redo)
                else
                    if state._consecutive_undo_steps and state._consecutive_undo_steps > 0 then
                        state._consecutive_undo_steps = state._consecutive_undo_steps - 1
                    end
                    UndoStateService.on_redo()
                end
                if state.reload_score_from_project then
                    state:reload_score_from_project()
                end
            else
                if proj_changed and cur_can_redo == "" then
                    state._consecutive_undo_steps = 0
                end
                if proj_changed and cur_can_undo ~= "" and cur_can_undo ~= prev_can_undo then
                    UndoStateService.on_external_new_action(cur_can_undo)
                end
                if proj_changed or tracks_changed then
                    MidiService.cleanup_orphaned_score_elements(state)
                end
            end
            if RecordQuantizeService and RecordQuantizeService.sync_all_tracks_monitoring then
                RecordQuantizeService.sync_all_tracks_monitoring(state)
            end
            state._last_proj_change_cleanup = reaper.GetProjectStateChangeCount(0)
        end

        if State.sync_project_tracks then
            State.sync_project_tracks(state, project_tracks)
        end

        -- Intercept keyboard shortcuts (protected so ImGui_End is never skipped on error)
        local kb_ok, kb_err = pcall(KeyboardHandler.handle, ctx, state, MidiService, ClipboardService, DynamicsEngine, state.active_tracks_cache)
        if not kb_ok then
            reaper.ShowConsoleMsg("[KeyboardHandler Error] " .. tostring(kb_err) .. "\n")
        end

        -- Modal dialogs (track selection & help) — all guarded against stack leaks ("Missing EndChild()" / "Missing End()")
        ImGuiGuardService.safe_render(ctx, state, "TrackPicker", TrackPicker.render, ctx, state, project_tracks)
        ImGuiGuardService.safe_render(ctx, state, "HelpModal", HelpModal.render, ctx, state)
        ImGuiGuardService.safe_render(ctx, state, "SettingsModal", SettingsModal.render, ctx, state, ShortcutManager)
        ImGuiGuardService.safe_render(ctx, state, "QuantizeModal", QuantizeModal.render, ctx, state, MidiService, state.active_tracks_cache)
        ImGuiGuardService.safe_render(ctx, state, "BankPickerModal", BankPickerModal.render, ctx, state, state.focused_track, state.active_tracks_cache)
        ImGuiGuardService.safe_render(ctx, state, "ScaleModal", ScaleModal.render, ctx, state)
        ImGuiGuardService.safe_render(ctx, state, "MusicXmlModal", MusicXmlModal.render, ctx, state, project_tracks)
        ImGuiGuardService.safe_render(ctx, state, "DivisioVocumModal", DivisioVocumModal.render, ctx, state, MidiService, state.active_tracks_cache)
        ImGuiGuardService.safe_render(ctx, state, "DivisiModal", DivisiModal.render, ctx, state, MidiService, state.active_tracks_cache)
        ImGuiGuardService.safe_render(ctx, state, "MelodyPathfinderModal", MelodyPathfinderModal.render, ctx, state, MidiService, AudioPreview, state.active_tracks_cache)
        ImGuiGuardService.safe_render(ctx, state, "FilterIrregularModal", FilterIrregularModal.render, ctx, state, MidiService, state.active_tracks_cache)
        ImGuiGuardService.safe_render(ctx, state, "RecordModal", RecordModal.render, ctx, state, MidiService, project_tracks, state.active_tracks_cache)
        ImGuiGuardService.safe_render(ctx, state, "CircleOfFifthsModal", CircleOfFifthsModal.render, ctx, state, MidiService)
        ImGuiGuardService.safe_render(ctx, state, "ArticulationsLastResortModal", ArticulationsDrawer.render_last_resort_modal, ctx, state, state.active_tracks_cache)

        -- ======================================================================
        -- 1. TOP BAR (Transport, time display, layout, tracks, zoom, lock, dynamics)
        -- ======================================================================
        local topbar_flags = reaper.ImGui_WindowFlags_NoScrollbar()
        if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
            topbar_flags = topbar_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            topbar_flags = topbar_flags | reaper.ImGui_WindowFlags_NoMove()
        end
        ImGuiGuardService.safe_render(ctx, state, "TopBar", TopBar.render, ctx, state, ClipboardService, MidiService, state.active_tracks_cache, #project_tracks, child_border, topbar_flags, project_tracks)

        -- ======================================================================
        -- 2. MAIN AREA: Left sidebar (palette) | Center canvas | Right drawer (resizable)
        -- ======================================================================
        local main_avail_w, main_avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        local bottom_bar_h = 46
        local splitter_w = 6
        local spacing = 4

        local h_splitter_h = 6
        local browser_h = 0
        if state.show_pattern_browser then
            state.pattern_browser_h = state.pattern_browser_h or 240
            local max_pb_h = math.max(120, main_avail_h - bottom_bar_h - 160)
            state.pattern_browser_h = math.max(120, math.min(max_pb_h, state.pattern_browser_h))
            browser_h = state.pattern_browser_h + h_splitter_h + 10
        end
        local midi_editor_pane_h = 0
        if state.show_midi_editor then
            state.midi_editor_h = state.midi_editor_h or 180
            local max_me_h = math.max(100, main_avail_h - bottom_bar_h - browser_h - 140)
            state.midi_editor_h = math.max(100, math.min(max_me_h, state.midi_editor_h))
            midi_editor_pane_h = state.midi_editor_h + h_splitter_h + 10
        end
        local main_content_h = math.max(100, main_avail_h - bottom_bar_h - browser_h - midi_editor_pane_h - 6)

        state.sidebar_w = state.sidebar_w or 230
        state.drawer_w = state.drawer_w or 236

        local canvas_w = main_avail_w - state.sidebar_w - splitter_w - spacing
        if state.show_dynamics or state.show_tempo or state.show_clefs or state.show_articulations_drawer or state.show_key_signatures or state.show_tools_drawer or state.show_annotations_drawer then
            canvas_w = canvas_w - state.drawer_w - splitter_w - spacing
        end
        if canvas_w < 150 then canvas_w = 150 end

        local sidebar_flags = 0
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            sidebar_flags = reaper.ImGui_WindowFlags_NoMove()
        end

        -- LEFT SIDEBAR: MAIN PALETTE (Resizable via splitter)
        ImGuiGuardService.safe_render(ctx, state, "Sidebar", Sidebar.render, ctx, state, MidiService, ClipboardService, state.active_tracks_cache, state.sidebar_w, main_content_h, child_border, sidebar_flags)

        -- VERTICAL SPLITTER 1: Left sidebar resizing
        reaper.ImGui_SameLine(ctx, 0, 2)
        reaper.ImGui_InvisibleButton(ctx, "vsplitter_left", splitter_w, main_content_h)
        if reaper.ImGui_IsItemActive(ctx) then
            local delta_x, _ = reaper.ImGui_GetMouseDelta(ctx)
            state.sidebar_w = math.max(140, math.min(500, state.sidebar_w + delta_x))
        end
        if reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx) then
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            local sp_x0, sp_y0 = reaper.ImGui_GetItemRectMin(ctx)
            local sp_x1, sp_y1 = reaper.ImGui_GetItemRectMax(ctx)
            local sp_col = reaper.ImGui_IsItemActive(ctx) and 0xFF9F1CFF or 0xFF9F1C66
            reaper.ImGui_DrawList_AddRectFilled(dl, sp_x0 + 1, sp_y0, sp_x1 - 1, sp_y1, sp_col)
        end
        if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
            state.sidebar_w = 230 -- Double-click resets to default width
        end

        -- CENTER AREA: SCORE CANVAS
        local canvas_flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoMove()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoNav") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoNav()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoNavInputs") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoNavInputs()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoNavFocus") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoNavFocus()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
            canvas_flags = canvas_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        end
        reaper.ImGui_SameLine(ctx, 0, 2)
        if reaper.ImGui_BeginChild(ctx, "ScoreCanvas", canvas_w, main_content_h, child_none, canvas_flags) then
            local is_canvas_hovered = reaper.ImGui_IsWindowHovered(ctx)
            if not is_canvas_hovered and reaper.APIExists("ImGui_HoveredFlags_ChildWindows") then
                is_canvas_hovered = reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_ChildWindows())
            end

            -- Configurable Mouse & Keyboard View Navigation Engine
            local is_shift = false
            if reaper.APIExists("ImGui_Mod_Shift") and reaper.APIExists("ImGui_GetKeyMods") then
                is_shift = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Shift()) ~= 0
            end
            if not is_shift and reaper.APIExists("ImGui_Key_LeftShift") and reaper.APIExists("ImGui_Key_RightShift") then
                is_shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
            end

            local is_ctrl = false
            if reaper.APIExists("ImGui_Mod_Ctrl") and reaper.APIExists("ImGui_GetKeyMods") then
                is_ctrl = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Ctrl()) ~= 0
            end
            if not is_ctrl and reaper.APIExists("ImGui_Key_LeftCtrl") and reaper.APIExists("ImGui_Key_RightCtrl") then
                is_ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl())
            end

            local is_alt = false
            if reaper.APIExists("ImGui_Mod_Alt") and reaper.APIExists("ImGui_GetKeyMods") then
                is_alt = (reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Alt()) ~= 0
            end
            if not is_alt and reaper.APIExists("ImGui_Key_LeftAlt") and reaper.APIExists("ImGui_Key_RightAlt") then
                is_alt = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftAlt()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightAlt())
            end

            local function check_nav_key(key_def)
                if not key_def or key_def == "" or key_def:lower() == "none" then
                    return not is_shift and not is_ctrl and not is_alt
                end
                local k = tostring(key_def):lower()
                if k == "shift" then
                    return is_shift and not is_ctrl and not is_alt
                elseif k == "ctrl" then
                    return is_ctrl and not is_shift and not is_alt
                elseif k == "alt" then
                    return is_alt and not is_ctrl and not is_shift
                elseif k == "space" then
                    return reaper.APIExists("ImGui_Key_Space") and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_Space())
                elseif k == "shift_ctrl" or k == "ctrl_shift" then
                    return is_shift and is_ctrl and not is_alt
                elseif k == "shift_alt" or k == "alt_shift" then
                    return is_shift and is_alt and not is_ctrl
                elseif k == "ctrl_alt" or k == "alt_ctrl" then
                    return is_ctrl and is_alt and not is_shift
                else
                    local need_ctrl = k:find("ctrl") ~= nil
                    local need_shift = k:find("shift") ~= nil
                    local need_alt = k:find("alt") ~= nil
                    if need_ctrl ~= is_ctrl then return false end
                    if need_shift ~= is_shift then return false end
                    if need_alt ~= is_alt then return false end

                    local clean_k = k:gsub("ctrl%+", ""):gsub("shift%+", ""):gsub("alt%+", "")
                    if clean_k == "space" then
                        return reaper.APIExists("ImGui_Key_Space") and reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_Space())
                    else
                        local cap = clean_k:sub(1,1):upper() .. clean_k:sub(2)
                        local k_code = ShortcutManager.get_key_enum(cap) or ShortcutManager.get_key_enum(clean_k:upper())
                        if k_code and reaper.APIExists("ImGui_IsKeyDown") then
                            return reaper.ImGui_IsKeyDown(ctx, k_code)
                        end
                    end
                end
                return false
            end

            -- Canvas Pan (Hand Tool / Drag Navigation)
            local pan_mouse = (state.nav_pan_mouse or "mouse_mid"):lower()
            local pan_btn = -1
            if pan_mouse == "mouse_mid" then pan_btn = 2
            elseif pan_mouse == "mouse_right" then pan_btn = 1
            elseif pan_mouse == "mouse_left" then pan_btn = 0
            end

            if pan_btn >= 0 and pan_mouse ~= "disabled" then
                if reaper.ImGui_IsMouseClicked(ctx, pan_btn) and is_canvas_hovered and check_nav_key(state.nav_pan_key or "none") then
                    state._is_canvas_panning = true
                end
                if state._is_canvas_panning then
                    if reaper.ImGui_IsMouseDown(ctx, pan_btn) then
                        local delta_x, delta_y = reaper.ImGui_GetMouseDelta(ctx)
                        if delta_x ~= 0 or delta_y ~= 0 then
                            reaper.ImGui_SetScrollX(ctx, reaper.ImGui_GetScrollX(ctx) - delta_x)
                            reaper.ImGui_SetScrollY(ctx, reaper.ImGui_GetScrollY(ctx) - delta_y)
                        end
                        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll())
                    else
                        state._is_canvas_panning = false
                    end
                end
            end

            -- Mouse Wheel & Trackpad Navigation (Horizontal Scroll, Vertical Scroll, Canvas Zoom)
            if is_canvas_hovered then
                local wh_y = reaper.ImGui_GetMouseWheel(ctx)
                local wh_x = 0
                if reaper.APIExists("ImGui_GetMouseWheelH") then
                    wh_x = reaper.ImGui_GetMouseWheelH(ctx)
                end

                -- Dedicated horizontal mouse wheel / trackpad horizontal gesture
                if wh_x ~= 0 then
                    local sf_h = state.scroll_factor_h or state.scroll_factor or 3.0
                    local dir_h = state.scroll_invert_h and -1 or 1
                    local cur_scroll_x = reaper.ImGui_GetScrollX(ctx)
                    reaper.ImGui_SetScrollX(ctx, cur_scroll_x - (wh_x * 40 * sf_h * dir_h))
                end

                if wh_y ~= 0 then
                    local h_mouse = (state.nav_scroll_h_mouse or "wheel_v"):lower()
                    local v_mouse = (state.nav_scroll_v_mouse or "wheel_v"):lower()
                    local z_mouse = (state.nav_zoom_mouse or "wheel_v"):lower()

                    local is_h = (h_mouse == "wheel_v" or h_mouse == "wheel_h") and check_nav_key(state.nav_scroll_h_key or "shift")
                    local is_v = (v_mouse == "wheel_v") and check_nav_key(state.nav_scroll_v_key or "none")
                    local is_z = (z_mouse == "wheel_v") and check_nav_key(state.nav_zoom_key or "ctrl")

                    if is_h then
                        local sf_h = state.scroll_factor_h or state.scroll_factor or 3.0
                        local dir_h = state.scroll_invert_h and -1 or 1
                        local cur_scroll_x = reaper.ImGui_GetScrollX(ctx)
                        reaper.ImGui_SetScrollX(ctx, cur_scroll_x - (wh_y * 40 * sf_h * dir_h))
                    elseif is_v then
                        local has_no_wheel = reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse")
                        if has_no_wheel or (state.nav_scroll_v_key and state.nav_scroll_v_key ~= "none") then
                            local sf_v = state.scroll_factor_v or 2.0
                            local dir_v = state.scroll_invert_v and -1 or 1
                            local cur_scroll_y = reaper.ImGui_GetScrollY(ctx)
                            reaper.ImGui_SetScrollY(ctx, cur_scroll_y - (wh_y * 40 * sf_v * dir_v))
                        end
                    elseif is_z then
                        local z_step = (wh_y > 0) and 0.08 or -0.08
                        state.zoom = math.max(0.6, math.min(2.0, state.zoom + z_step))
                    end
                end
            end

            local ok, canvas_info = ImGuiGuardService.safe_render(ctx, state, "ScoreCanvas", ScoreCanvas.render, ctx, state, fonts, project_tracks, MidiService)
            if ok and canvas_info then
                state.active_tracks_cache = canvas_info.active_tracks_data
                ImGuiGuardService.safe_render(ctx, state, "ScoreCanvas MouseHandler", MouseHandler.handle, ctx, state, canvas_info, MidiService, DynamicsEngine)
            end
            reaper.ImGui_EndChild(ctx)
        end

        -- RIGHT AREA: DYNAMICS, TEMPO, CLEF, KEY SIGNATURE, ARTICULATIONS, TOOLS OR ANNOTATIONS DRAWER (Resizable via splitter)
        if state.show_dynamics or state.show_tempo or state.show_clefs or state.show_articulations_drawer or state.show_key_signatures or state.show_tools_drawer or state.show_annotations_drawer then
            -- VERTICAL SPLITTER 2: Right drawer resizing
            reaper.ImGui_SameLine(ctx, 0, 2)
            reaper.ImGui_InvisibleButton(ctx, "vsplitter_right", splitter_w, main_content_h)
            if reaper.ImGui_IsItemActive(ctx) then
                local delta_x, _ = reaper.ImGui_GetMouseDelta(ctx)
                state.drawer_w = math.max(180, math.min(500, state.drawer_w - delta_x))
            end
            if reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx) then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                local sp_x0, sp_y0 = reaper.ImGui_GetItemRectMin(ctx)
                local sp_x1, sp_y1 = reaper.ImGui_GetItemRectMax(ctx)
                local sp_col = reaper.ImGui_IsItemActive(ctx) and 0xFF9F1CFF or 0xFF9F1C66
                reaper.ImGui_DrawList_AddRectFilled(dl, sp_x0 + 1, sp_y0, sp_x1 - 1, sp_y1, sp_col)
            end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                state.drawer_w = 236 -- Double-click resets to default width
            end

            reaper.ImGui_SameLine(ctx, 0, 2)
            if state.show_tools_drawer then
                ImGuiGuardService.safe_render(ctx, state, "ToolsDrawer", ToolsDrawer.render, ctx, state, MidiService, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags, fonts.font_music, fonts.font_main)
            elseif state.show_clefs then
                ImGuiGuardService.safe_render(ctx, state, "ClefDrawer", ClefDrawer.render, ctx, state, state.drawer_w, main_content_h, child_border, sidebar_flags, fonts.font_music, fonts.font_main)
            elseif state.show_key_signatures then
                ImGuiGuardService.safe_render(ctx, state, "KeySignatureDrawer", KeySignatureDrawer.render, ctx, state, KeySignatureService, MidiService, state.drawer_w, main_content_h, child_border, sidebar_flags, fonts.font_music, fonts.font_main)
            elseif state.show_tempo then
                ImGuiGuardService.safe_render(ctx, state, "TempoDrawer", TempoDrawer.render, ctx, state, state.drawer_w, main_content_h, child_border, sidebar_flags)
            elseif state.show_dynamics then
                ImGuiGuardService.safe_render(ctx, state, "DynamicsDrawer", DynamicsDrawer.render, ctx, state, DynamicsEngine, MidiService, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags)
            elseif state.show_articulations_drawer then
                ImGuiGuardService.safe_render(ctx, state, "ArticulationsDrawer", ArticulationsDrawer.render, ctx, state, MidiService, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags)
            elseif state.show_annotations_drawer then
                ImGuiGuardService.safe_render(ctx, state, "AnnotationDrawer", AnnotationDrawer.render, ctx, state, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags)
            end
        end

        -- ======================================================================
        -- 2b. BOTTOM PANE: PATTERN BROWSER (Resizable via horizontal splitter!)
        -- ======================================================================
        if state.show_pattern_browser then
            -- HORIZONTAL SPLITTER: Bottom pane resizing
            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 2)
            reaper.ImGui_InvisibleButton(ctx, "hsplitter_bottom_browser", main_avail_w, h_splitter_h)
            if reaper.ImGui_IsItemActive(ctx) then
                local _, delta_y = reaper.ImGui_GetMouseDelta(ctx)
                local max_pb_h = math.max(120, main_avail_h - bottom_bar_h - 160)
                state.pattern_browser_h = math.max(120, math.min(max_pb_h, state.pattern_browser_h - delta_y))
                reaper.SetExtState("REAPER_Notator", "PatternBrowserHeight", tostring(math.floor(state.pattern_browser_h)), true)
            end
            if reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx) then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                local sp_x0, sp_y0 = reaper.ImGui_GetItemRectMin(ctx)
                local sp_x1, sp_y1 = reaper.ImGui_GetItemRectMax(ctx)
                local sp_col = reaper.ImGui_IsItemActive(ctx) and 0xE67E22FF or 0xE67E2277
                reaper.ImGui_DrawList_AddRectFilled(dl, sp_x0, sp_y0 + 1, sp_x1, sp_y1 - 1, sp_col)
            end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                state.pattern_browser_h = 240 -- Double-click resets to default height
                reaper.SetExtState("REAPER_Notator", "PatternBrowserHeight", "240", true)
            end

            ImGuiGuardService.safe_render(ctx, state, "PatternBrowser", PatternBrowser.render, ctx, state, MidiService, AudioPreview, main_avail_w, state.pattern_browser_h, project_tracks, fonts.font_music, fonts.font_main)
        end

        -- ======================================================================
        -- 2c. BOTTOM PANE: MIDI EDITOR (Velocity Lane, resizable via horizontal splitter!)
        -- ======================================================================
        if state.show_midi_editor then
            -- HORIZONTAL SPLITTER: MIDI Editor pane resizing
            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 2)
            reaper.ImGui_InvisibleButton(ctx, "hsplitter_bottom_midi_editor", main_avail_w, h_splitter_h)
            if reaper.ImGui_IsItemActive(ctx) then
                local _, delta_y = reaper.ImGui_GetMouseDelta(ctx)
                local max_me_h = math.max(100, main_avail_h - bottom_bar_h - 140)
                state.midi_editor_h = math.max(100, math.min(max_me_h, state.midi_editor_h - delta_y))
                reaper.SetExtState("REAPER_Notator", "MidiEditorHeight", tostring(math.floor(state.midi_editor_h)), true)
            end
            if reaper.ImGui_IsItemHovered(ctx) or reaper.ImGui_IsItemActive(ctx) then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
                local dl = reaper.ImGui_GetWindowDrawList(ctx)
                local sp_x0, sp_y0 = reaper.ImGui_GetItemRectMin(ctx)
                local sp_x1, sp_y1 = reaper.ImGui_GetItemRectMax(ctx)
                local sp_col = reaper.ImGui_IsItemActive(ctx) and 0x8E44ADFF or 0x8E44AD77
                reaper.ImGui_DrawList_AddRectFilled(dl, sp_x0, sp_y0 + 1, sp_x1, sp_y1 - 1, sp_col)
            end
            if reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                state.midi_editor_h = 180 -- Double-click resets to default height
                reaper.SetExtState("REAPER_Notator", "MidiEditorHeight", "180", true)
            end

            ImGuiGuardService.safe_render(ctx, state, "MidiEditorDrawer", MidiEditorDrawer.render, ctx, state, MidiService, AudioPreview, DynamicsEngine, main_avail_w, state.midi_editor_h, project_tracks, fonts.font_main)
        end

        -- ======================================================================
        -- 3. STATUS & RASTER BAR (Bottom)
        -- ======================================================================
        local bottom_flags = 0
        if reaper.APIExists("ImGui_WindowFlags_NoScrollbar") then
            bottom_flags = bottom_flags | reaper.ImGui_WindowFlags_NoScrollbar()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
            bottom_flags = bottom_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
        end
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            bottom_flags = bottom_flags | reaper.ImGui_WindowFlags_NoMove()
        end
        ImGuiGuardService.safe_render(ctx, state, "BottomBar", BottomBar.render, ctx, state, bottom_bar_h, child_border, bottom_flags)

        if state.is_open then
            AudioPreview.update(state, ctx)
            PatternService.update_preview(AudioPreview)
        end

        -- Commit any uncommitted scoreProjExtState changes when idle and sync Undo/Redo state after frame interactions
        UndoStateService.commit_uncommitted_if_idle(ctx, state)
        local post_proj_change = reaper.GetProjectStateChangeCount(0)
        if post_proj_change ~= state._last_proj_change_cleanup then
            local post_can_undo = (reaper.Undo_CanUndo2 and reaper.Undo_CanUndo2(0)) or ""
            local post_can_redo = (reaper.Undo_CanRedo2 and reaper.Undo_CanRedo2(0)) or ""
            if post_can_redo == "" and not state._in_undo_redo_action then
                state._consecutive_undo_steps = 0
            end
            state._last_proj_change_cleanup = post_proj_change
            state._last_total_tracks_cleanup = reaper.CountTracks(0)
            state._last_can_undo_str = post_can_undo
            state._last_can_redo_str = post_can_redo
        end
    end

    reaper.ImGui_End(ctx)

    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopStyleColor(ctx, 7)

    if state.is_open then
        reaper.defer(loop)
    else
        FrameTimerService.restore()
        AudioPreview.stop_all(state)
        PatternService.stop_preview(AudioPreview)
    end
end

-- ==============================================================================
-- 6. Dependency Check Loop (Reaticulate Verification before Full Launch)
-- ==============================================================================
local function dependency_check_loop()
    if not state.is_open then return end
    if reaper.APIExists("ImGui_ValidatePtr") and not reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*") then return end

    -- Authentic dark pro styling for setup modal
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(),       0x151619FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(),        0x1E2025FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(),         0x2A2D35FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(),         0x282B33FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(),  0xE67E22FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(),   0xFF9F1CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(),           0xF0F0F0FF)

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 6.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(),  4.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(),    8.0, 6.0)

    -- Center window on main viewport
    local mvp = reaper.APIExists("ImGui_GetMainViewport") and reaper.ImGui_GetMainViewport(ctx)
    if mvp and reaper.APIExists("ImGui_Viewport_GetWorkPos") and reaper.APIExists("ImGui_Viewport_GetWorkSize") then
        local vx, vy = reaper.ImGui_Viewport_GetWorkPos(mvp)
        local vw, vh = reaper.ImGui_Viewport_GetWorkSize(mvp)
        local win_w, win_h = 620, 420
        local win_x = vx + math.floor((vw - win_w) / 2)
        local win_y = vy + math.floor((vh - win_h) / 2)
        reaper.ImGui_SetNextWindowPos(ctx, win_x, win_y, reaper.ImGui_Cond_Appearing())
        reaper.ImGui_SetNextWindowSize(ctx, win_w, win_h, reaper.ImGui_Cond_Appearing())
    end

    local dep_flags = reaper.ImGui_WindowFlags_NoCollapse()
    if reaper.APIExists("ImGui_WindowFlags_NoDocking") then
        dep_flags = dep_flags | reaper.ImGui_WindowFlags_NoDocking()
    end

    local visible, open = reaper.ImGui_Begin(ctx, "REAPER Notator - Missing Dependency: Reaticulate###DepCheck", true, dep_flags)
    state.is_open = open

    if visible then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF9F1CFF)
        reaper.ImGui_Text(ctx, "⚠ MISSING REQUIRED DEPENDENCY: REATICULATE")
        reaper.ImGui_PopStyleColor(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_TextWrapped(ctx, 
            "REAPER Notator requires 'Reaticulate' to handle orchestral articulation banks, " ..
            "keyswitches, and playback performance. Reaticulate was not found in your REAPER " ..
            "Scripts directory (Scripts/Reaticulate)."
        )
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_Text(ctx, "Required ReaPack Repository URL:")
        local reat_repo_url = "https://reaticulate.com/index.xml"
        reaper.ImGui_PushItemWidth(ctx, 420)
        reaper.ImGui_InputText(ctx, "##repo_url", reat_repo_url, reaper.ImGui_InputTextFlags_ReadOnly())
        reaper.ImGui_PopItemWidth(ctx)
        reaper.ImGui_SameLine(ctx, 0, 8)

        if reaper.ImGui_Button(ctx, "📋 Copy Repository URL", 160, 24) then
            if reaper.APIExists("ImGui_SetClipboardText") then
                reaper.ImGui_SetClipboardText(ctx, reat_repo_url)
            elseif reaper.CF_SetClipboard then
                reaper.CF_SetClipboard(reat_repo_url)
            end
            state._dep_copied_time = reaper.time_precise()
        end

        if state._dep_copied_time and (reaper.time_precise() - state._dep_copied_time) < 4.0 then
            reaper.ImGui_TextColored(ctx, 0x2ECC71FF, "✓ Repository URL copied to clipboard! Paste it into ReaPack.")
        else
            reaper.ImGui_Spacing(ctx)
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Text(ctx, "Installation steps:")
        reaper.ImGui_BulletText(ctx, "1. Open REAPER menu: Extensions -> ReaPack -> Manage repositories...")
        reaper.ImGui_BulletText(ctx, "2. Click 'Import/commit repository...' and paste the URL (Ctrl+V).")
        reaper.ImGui_BulletText(ctx, "3. In REAPER: Extensions -> ReaPack -> Browse packages...")
        reaper.ImGui_BulletText(ctx, "4. Search for 'Reaticulate', right-click -> Install, then click 'Apply'.")

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        if reaper.ImGui_Button(ctx, "🔄 Check Again & Launch", 200, 32) then
            local check_stat = PathService.detect_status(state)
            if check_stat.reaticulate_found then
                local ReaticulateParser = require("services.reaticulate_parser")
                ReaticulateParser.reload_all_banks(state)
                reaticulate_installed = true
                reaper.ImGui_End(ctx)
                reaper.ImGui_PopStyleVar(ctx, 3)
                reaper.ImGui_PopStyleColor(ctx, 7)
                reaper.defer(loop)
                return
            else
                state._dep_not_found_time = reaper.time_precise()
            end
        end

        if state._dep_not_found_time and (reaper.time_precise() - state._dep_not_found_time) < 4.0 then
            reaper.ImGui_SameLine(ctx, 0, 10)
            reaper.ImGui_TextColored(ctx, 0xE74C3CFF, "✗ Still not detected. Please verify 'Apply' was clicked in ReaPack.")
        end

        reaper.ImGui_SameLine(ctx, 0, 14)
        if reaper.ImGui_Button(ctx, "Exit", 80, 32) then
            state.is_open = false
        end
    end
    reaper.ImGui_End(ctx)
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopStyleColor(ctx, 7)

    if state.is_open then
        reaper.defer(dependency_check_loop)
    end
end

-- Start application: verify dependencies first
if reaticulate_installed then
    reaper.defer(loop)
else
    reaper.defer(dependency_check_loop)
end

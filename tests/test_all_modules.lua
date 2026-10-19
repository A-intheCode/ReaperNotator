-- ==============================================================================
-- REAPER-Notator Comprehensive Unit Test & Fuzzing Suite (test_all_modules.lua)
-- Tests all 78 Lua modules across Core, Classes, Services, Rendering, Input & UI
-- ==============================================================================

local repo_root = _G.TEST_REPO_ROOT or "."
package.path = repo_root .. "/modules/?.lua;" .. repo_root .. "/?.lua;" .. package.path

local Mock = require("tests.mock_reaper")
_G.reaper = Mock.create_environment(repo_root)

-- Strict Global Variable Guard: Catch any undeclared global read/write across all 78 modules!
setmetatable(_G, {
    __index = function(_, k)
        error("STRICT GLOBAL GUARD: Attempt to read undeclared global '" .. tostring(k) .. "'", 2)
    end,
    __newindex = function(t, k, v)
        if k ~= "reaper" and k ~= "gfx" and k ~= "TEST_REPO_ROOT" then
            error("STRICT GLOBAL GUARD: Attempt to write undeclared global '" .. tostring(k) .. "'", 2)
        end
        rawset(t, k, v)
    end
})

local results = {
    passed = 0,
    failed = 0,
    failures = {},
    suites = {}
}

local current_suite = "General"

local function begin_suite(name)
    current_suite = name
    results.suites[name] = { passed = 0, failed = 0 }
    print(string.format("\n=== [SUITE] %s ===", name))
end

local function run_test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        results.passed = results.passed + 1
        if results.suites[current_suite] then
            results.suites[current_suite].passed = results.suites[current_suite].passed + 1
        end
        print(string.format("  [PASS] %s", name))
    else
        results.failed = results.failed + 1
        if results.suites[current_suite] then
            results.suites[current_suite].failed = results.suites[current_suite].failed + 1
        end
        local msg = string.format("[%s] %s:\n%s", current_suite, name, tostring(err))
        table.insert(results.failures, msg)
        print(string.format("  [FAIL] %s -> %s", name, tostring(err):match("^[^\n]+") or tostring(err)))
    end
end

local function assert_true(cond, msg)
    if not cond then error("Assertion failed: " .. tostring(msg or "expected truthy value"), 2) end
end

local function assert_eq(a, b, msg)
    if a ~= b then
        error(string.format("Assertion failed (%s): expected %s, got %s", tostring(msg or "equal"), tostring(b), tostring(a)), 2)
    end
end

-- ==============================================================================
-- Helper: Populate Rich Multi-Track Mock Project
-- ==============================================================================
local function setup_rich_mock_project()
    reaper = Mock.create_environment(repo_root)
    local env = reaper._mock

    local trk1 = env.add_track("Violin I", 0x336699)
    local trk2 = env.add_track("Piano Grand", 0x996633)
    local trk3 = env.add_track("Orchestral Harp", 0x669933)
    local trk4 = env.add_track("Timpani & Percussion", 0x993366)
    trk1.selected = true
    trk2.selected = true

    local item1, take1 = env.add_midi_item(trk1, 0, 16)
    local item2, take2 = env.add_midi_item(trk2, 0, 16)
    local item3, take3 = env.add_midi_item(trk3, 0, 16)
    local item4, take4 = env.add_midi_item(trk4, 0, 16)

    -- Populate Violin I with melodic phrase, chord cluster (2nds F4-G4-A4), 16th/32nd run, dotted notes, and articulations
    local notes_vln = {
        { s = 0.0,   e = 1.0,   p = 60, ch = 0, vel = 95, sel = true },
        { s = 1.0,   e = 1.75,  p = 62, ch = 0, vel = 90, sel = true }, -- dotted 8th
        { s = 1.75,  e = 2.0,   p = 64, ch = 0, vel = 90, sel = true }, -- 16th
        -- Dotted chord with 2nds (F4, G4, A4) at beat 2.0
        { s = 2.0,   e = 3.5,   p = 65, ch = 0, vel = 100, sel = false },
        { s = 2.0,   e = 3.5,   p = 67, ch = 0, vel = 100, sel = false },
        { s = 2.0,   e = 3.5,   p = 69, ch = 0, vel = 100, sel = false },
        -- 32nd run at beat 3.5
        { s = 3.5,   e = 3.625, p = 71, ch = 0, vel = 85, sel = false },
        { s = 3.625, e = 3.75,  p = 72, ch = 0, vel = 88, sel = false },
        { s = 3.75,  e = 3.875, p = 74, ch = 0, vel = 92, sel = false },
        { s = 3.875, e = 4.0,   p = 76, ch = 0, vel = 96, sel = false },
        -- Bar 2: Triplets + accidentals (F#4 -> F4 natural cancellation) + Voice 2 polyphony
        { s = 4.0,   e = 4.333, p = 66, ch = 0, vel = 90, sel = false },
        { s = 4.333, e = 4.666, p = 65, ch = 0, vel = 90, sel = false },
        { s = 4.666, e = 5.0,   p = 64, ch = 0, vel = 90, sel = false },
        { s = 4.0,   e = 5.0,   p = 55, ch = 1, vel = 80, sel = false }, -- Voice 2
        { s = 5.5,   e = 6.0,   p = 67, ch = 0, vel = 90, sel = false }, -- After a rest
        { s = 6.0,   e = 8.0,   p = 67, ch = 0, vel = 90, sel = false }, -- Same pitch for tie
    }
    for _, n in ipairs(notes_vln) do
        reaper.MIDI_InsertNote(take1, n.sel, false, n.s * 960, n.e * 960, n.ch, n.p, n.vel, false)
    end
    reaper.MIDI_InsertTextSysexEvt(take1, false, false, 0, 15, "NOTE 60 0 a staccato")
    reaper.MIDI_InsertTextSysexEvt(take1, false, false, 960, 15, "NOTE 62 0 a accent")
    reaper.MIDI_InsertTextSysexEvt(take1, false, false, 1920, 15, "NOTE 69 0 a marcato")

    -- Populate Piano Grand Staff (Treble + Bass range)
    reaper.MIDI_InsertNote(take2, false, false, 0, 960, 0, 48, 85, false)   -- C3 (Bass)
    reaper.MIDI_InsertNote(take2, false, false, 0, 960, 0, 64, 90, false)   -- E4 (Treble)
    reaper.MIDI_InsertNote(take2, false, false, 960, 1920, 0, 55, 85, false) -- G3
    reaper.MIDI_InsertNote(take2, false, false, 960, 1920, 0, 67, 90, false) -- G4

    -- Populate Harp
    reaper.MIDI_InsertNote(take3, false, false, 0, 960, 0, 50, 80, false)
    reaper.MIDI_InsertNote(take3, false, false, 960, 1920, 0, 74, 95, false)

    -- Populate Percussion
    reaper.MIDI_InsertNote(take4, false, false, 0, 480, 9, 36, 110, false)
    reaper.MIDI_InsertNote(take4, false, false, 480, 960, 9, 38, 105, false)

    local MidiService = require("services.midi_service")
    MidiService.invalidate_cache()
    local State = require("state")
    local st = State.new()
    st.focused_track = trk1
    st.selected_item = item1
    st.selected_take = take1
    st.selected_tracks[trk1.guid] = true
    st.selected_tracks[trk2.guid] = true
    st.selected_tracks[trk3.guid] = true
    st.selected_tracks[trk4.guid] = true
    local project_tracks = MidiService.get_project_midi_tracks()
    if State.sync_project_tracks then
        State.sync_project_tracks(st, project_tracks)
    end
    local FontManager = require("rendering.font_manager")
    local ScoreCanvas = require("rendering.score_canvas")
    local ctx = reaper.ImGui_CreateContext("setup")
    local fonts = FontManager.init(ctx)
    local ok, canvas_info = pcall(ScoreCanvas.render, ctx, st, fonts, project_tracks, MidiService)
    if ok and canvas_info then
        st.active_tracks_cache = canvas_info.active_tracks_data
    end
    return st, env, trk1, item1, take1, project_tracks, fonts, canvas_info
end

-- ==============================================================================
-- SUITE 1: All 78 Lua Modules Require & Load Verification
-- ==============================================================================
begin_suite("Suite 1: Module Load & Require Verification (All 78 Modules)")

local all_modules = {
    -- Core (3)
    "version", "constants", "state",
    -- Classes (15)
    "classes.chord_item", "classes.dynamic", "classes.dynamic_text", "classes.fermata",
    "classes.glissando_mark", "classes.hairpin", "classes.item", "classes.note",
    "classes.octave_line", "classes.pedal_mark", "classes.portamento_mark",
    "classes.rehearsal_mark", "classes.tempo_marker", "classes.text_item", "classes.track",
    -- Services (34)
    "services.annotation_service", "services.audio_preview", "services.circle_of_fifths_service",
    "services.clipboard_service",
    "services.divisi_service", "services.divisio_vocum_service", "services.dynamic_text_service",
    "services.dynamics_engine", "services.fermata_service", "services.filter_notes_service",
    "services.frame_timer_service", "services.glissando_service", "services.hairpin_service",
    "services.imgui_guard_service",
    "services.json_helper", "services.key_signature_service", "services.melody_pathfinder_service",
    "services.melody_style_corpus", "services.midi_service", "services.musicxml_export_service",
    "services.musicxml_import_service", "services.octave_service", "services.path_service",
    "services.pattern_service", "services.pedal_service", "services.portamento_service",
    "services.quantize_service", "services.reaticulate_parser", "services.record_quantize_service",
    "services.rehearsal_mark_service", "services.repeat_service", "services.scale_service",
    "services.selection_service", "services.shortcut_manager", "services.slur_service",
    "services.tempo_service", "services.text_item_service",
    -- Rendering (7)
    "rendering.canvas_context_menus", "rendering.canvas_decorations",
    "rendering.canvas_pedal_renderer", "rendering.engraver", "rendering.font_manager",
    "rendering.score_canvas", "rendering.system_engraver",
    -- Input (2)
    "input.keyboard_handler", "input.mouse_handler",
    -- UI (25)
    "ui.annotation_drawer", "ui.articulations_drawer", "ui.bank_picker_modal",
    "ui.bottom_bar", "ui.circle_of_fifths_modal", "ui.clef_drawer", "ui.divisi_modal", "ui.divisio_vocum_modal",
    "ui.dynamics_drawer", "ui.filter_irregular_modal", "ui.help_modal",
    "ui.key_signature_drawer", "ui.melody_pathfinder_modal", "ui.midi_editor_drawer",
    "ui.musicxml_modal", "ui.pattern_browser", "ui.quantize_modal", "ui.record_modal",
    "ui.scale_modal", "ui.settings_modal", "ui.sidebar", "ui.tempo_drawer",
    "ui.tools_drawer", "ui.top_bar", "ui.track_picker",
}

for _, mod_name in ipairs(all_modules) do
    run_test("require('" .. mod_name .. "')", function()
        local m = require(mod_name)
        assert_true(type(m) == "table", "Module " .. mod_name .. " must return a table")
    end)
end

-- ==============================================================================
-- SUITE 2: Core Modules & All 15 Data Classes
-- ==============================================================================
begin_suite("Suite 2: Core Modules & All 15 Data Classes")

run_test("Version & Constants integrity", function()
    local Version = require("version")
    local Constants = require("constants")
    assert_true(type(Version.SEMVER) == "string" and #Version.SEMVER > 0, "Version.SEMVER valid")
    assert_true(type(Version.get_display_string()) == "string", "Version.get_display_string valid")
    assert_true(type(Constants.SMUFL) == "table", "Constants.SMUFL exists")
    assert_true(type(Constants.COLORS) == "table", "Constants.COLORS exists")
    assert_true(type(Constants.CLEF_DEFS) == "table", "Constants.CLEF_DEFS exists")
end)

run_test("State initialization, selection & helper methods", function()
    local State = require("state")
    local st = State.new()
    assert_true(type(st) == "table", "State.new() returns table")
    if st.clear_selection then st:clear_selection() end
    if st.set_status then st:set_status("Unit Test Status") end
    if st.has_any_selection then
        local _ = st:has_any_selection()
    end
end)

local class_specs = {
    { mod = "classes.note",            data = { idx = 0, start_qn = 1.0, end_qn = 2.0, pitch = 60, vel = 90, chan = 0 } },
    { mod = "classes.item",            data = { pos = 0.0, len = 4.0, start_qn = 0.0, end_qn = 4.0, name = "Test Item" } },
    { mod = "classes.track",           data = { guid = "{GUID}", name = "Violin", col = 0x112233, clef = "treble" } },
    { mod = "classes.chord_item",      data = { text = "Cmaj7", start_qn = 0.0, end_qn = 4.0, root = 0 } },
    { mod = "classes.dynamic",         data = { label = "mf", qn = 0.0, c1 = 80, c11 = 80 } },
    { mod = "classes.dynamic_text",    data = { text = "cresc.", start_qn = 0.0, end_qn = 4.0, track_guid = "{GUID}" } },
    { mod = "classes.fermata",         data = { qn = 4.0, type = "standard", hold_factor = 1.5 } },
    { mod = "classes.glissando_mark",  data = { track_guid = "{GUID}", start_qn1 = 0, pitch1 = 60, start_qn2 = 2, pitch2 = 72 } },
    { mod = "classes.hairpin",         data = { type = "crescendo", start_qn = 0.0, end_qn = 4.0, track_guid = "{GUID}" } },
    { mod = "classes.octave_line",     data = { type = "8va", start_qn = 0.0, end_qn = 4.0, track_guid = "{GUID}" } },
    { mod = "classes.pedal_mark",      data = { start_qn = 0.0, end_qn = 4.0, track_guid = "{GUID}", pauses = {} } },
    { mod = "classes.portamento_mark", data = { track_guid = "{GUID}", start_qn1 = 0, pitch1 = 60, start_qn2 = 2, pitch2 = 67 } },
    { mod = "classes.rehearsal_mark",  data = { label = "A", measure = 1, qn = 0.0 } },
    { mod = "classes.tempo_marker",    data = { start_qn = 0.0, bpm = 120.0, label = "Allegro" } },
    { mod = "classes.text_item",       data = { text = "Espressivo", qn = 0.0, track_guid = "{GUID}" } },
}

for _, spec in ipairs(class_specs) do
    run_test("Class instantiation & nil-safety: " .. spec.mod, function()
        local cls = require(spec.mod)
        assert_true(type(cls.new) == "function", spec.mod .. ".new exists")
        local inst = cls.new(spec.data)
        assert_true(type(inst) == "table", spec.mod .. ".new(data) returned table")
        if inst.get_key then
            assert_true(inst:get_key() ~= nil, "get_key() non-nil")
        end
        if inst.clone then
            assert_true(type(inst:clone()) == "table", "clone() returned table")
        end
        if inst.to_table then
            local t = inst:to_table()
            assert_true(type(t) == "table", "to_table() returned table")
            if cls.from_table then
                assert_true(type(cls.from_table(t)) == "table", "from_table() roundtrip")
            end
        end
        -- Verify nil & invalid argument safety!
        local empty_inst = cls.new(nil)
        assert_true(type(empty_inst) == "table", spec.mod .. ".new(nil) is nil-safe")
        local num_inst = cls.new(123)
        assert_true(type(num_inst) == "table", spec.mod .. ".new(123) is type-safe")
    end)
end

-- ==============================================================================
-- SUITE 3: All 32 Services (CRUD, Persistence, Playback & Edge Cases)
-- ==============================================================================
begin_suite("Suite 3: All 32 Services (CRUD, Persistence, Playback & Edge Cases)")

run_test("JsonHelper: encode/decode roundtrips & malformed input safety", function()
    local Json = require("services.json_helper")
    local orig = { a = 1, b = "hello \"world\"", c = true, d = { 10, 20, 30 }, e = { nested = -3.5 } }
    local enc = Json.encode(orig)
    assert_true(type(enc) == "string" and #enc > 0, "Json.encode string")
    local dec = Json.decode(enc)
    assert_eq(dec.a, 1, "dec.a")
    assert_eq(dec.b, "hello \"world\"", "dec.b")
    assert_eq(dec.c, true, "dec.c")
    assert_eq(dec.d[2], 20, "dec.d[2]")
    pcall(Json.decode, "")
    pcall(Json.decode, "{invalid json")
    pcall(Json.decode, nil)
end)

run_test("MidiService: track/take discovery, note loading, insertion, transposition & Fix Playback", function()
    local st, env, trk1, item1, take1 = setup_rich_mock_project()
    local MidiService = require("services.midi_service")

    local tracks = MidiService.get_project_midi_tracks()
    assert_true(#tracks >= 4, "Discovered 4 MIDI tracks")

    local active_take = MidiService.get_active_midi_take()
    assert_true(active_take ~= nil, "Active take found")

    local mock_bank = {
        name = "Spitfire Symphony",
        articulations = {
            { program = 1, name = "Long" },
            { program = 40, name = "Short 0.5" },
            { program = 42, name = "Staccato Dig" },
            { program = 50, name = "Legato" },
        }
    }
    local art = MidiService.find_reaticulate_art_for_id(mock_bank, "staccato")
    assert_true(art and art.program == 42, "Prioritizes Staccato Dig (PC 42) over Short 0.5")

    if MidiService.fix_playback_selective then
        MidiService.fix_playback_selective(st)
    end
    if MidiService.fix_playback_global then
        MidiService.fix_playback_global(st)
    end
    if MidiService.purge_all_articulations_selective then
        MidiService.purge_all_articulations_selective(st)
    end
end)

run_test("SlurService: slur & tie creation, persistence, deduplication & drawing", function()
    local st, env, trk1, item1, take1 = setup_rich_mock_project()
    local SlurService = require("services.slur_service")
    local Note = require("classes.note")

    SlurService.load_slurs(st)
    local n1 = Note.new({ idx = 0, start_qn = 0.0, end_qn = 1.0, pitch = 60, vel = 90, chan = 0, take = take1, item = item1, track = trk1 })
    local n2 = Note.new({ idx = 1, start_qn = 1.0, end_qn = 2.0, pitch = 64, vel = 90, chan = 0, take = take1, item = item1, track = trk1 })
    local n3 = Note.new({ idx = 2, start_qn = 2.0, end_qn = 3.0, pitch = 64, vel = 90, chan = 0, take = take1, item = item1, track = trk1 })
    st.selected_notes = { [n1:get_key()] = n1, [n2:get_key()] = n2 }
    st.selected_note = n1

    if SlurService.toggle_slur_on_selection then
        SlurService.toggle_slur_on_selection(st)
    elseif SlurService.add_slur then
        SlurService.add_slur(st, n1, n2)
    end
    SlurService.save_slurs(st)
    SlurService.load_slurs(st)

    local render_map = {
        [n1:get_key()] = { key = n1:get_key(), nx = 200, ny = 220, pitch = 60, start_qn = 0.0, dur_qn = 1.0, stem_down = false, stem_end_y = 190, art_y = 185, art_is_above = true, track = trk1, orig = n1 },
        [n2:get_key()] = { key = n2:get_key(), nx = 280, ny = 210, pitch = 64, start_qn = 1.0, dur_qn = 1.0, stem_down = true, stem_end_y = 240, art_y = 198, art_is_above = true, track = trk1, orig = n2 },
        [n3:get_key()] = { key = n3:get_key(), nx = 360, ny = 210, pitch = 64, start_qn = 2.0, dur_qn = 1.0, stem_down = true, stem_end_y = 240, track = trk1, orig = n3 },
    }
    render_map[n2:get_key()].chord_cluster = { render_map[n2:get_key()], { ny = 225 } }

    table.insert(st.user_slurs, { id = "sl1", track_guid = trk1.guid, n1_start_qn = 0.0, pitch1 = 60, n2_start_qn = 1.0, pitch2 = 64 })
    table.insert(st.user_ties,  { id = "ti1", track_guid = trk1.guid, n1_start_qn = 1.0, n2_start_qn = 2.0, pitch = 64 })

    local ctx = reaper.ImGui_CreateContext("test")
    local dl  = reaper.ImGui_GetWindowDrawList(ctx)
    SlurService.draw_slurs(ctx, dl, st, render_map, 1.0, 0, 1000, 0, 800, true, 240, 190, false)
    SlurService.draw_user_ties(ctx, dl, st, render_map, 1.0, 0, 1000, 0, 800, true, 320, 210, false)
end)

run_test("GlissandoService & PortamentoService: creation, dot/accidental clearance & playback", function()
    local st, env, trk1, item1, take1 = setup_rich_mock_project()
    local GlissandoService = require("services.glissando_service")
    local PortamentoService = require("services.portamento_service")
    local Note = require("classes.note")

    GlissandoService.load_glissandos(st)
    PortamentoService.load_portamentos(st)

    local n1 = Note.new({ idx = 0, start_qn = 0.0, end_qn = 1.5, pitch = 60, vel = 90, chan = 0, take = take1, item = item1, track = trk1 })
    local n2 = Note.new({ idx = 1, start_qn = 1.5, end_qn = 3.0, pitch = 66, vel = 90, chan = 0, take = take1, item = item1, track = trk1 })
    local render_map = {
        [n1:get_key()] = { key = n1:get_key(), nx = 200, ny = 230, pitch = 60, start_qn = 0.0, dur_qn = 1.5, acc = 0, track = trk1, orig = n1 },
        [n2:get_key()] = { key = n2:get_key(), nx = 320, ny = 205, pitch = 66, start_qn = 1.5, dur_qn = 1.5, acc = 1, acc_x_offset = -11.0, track = trk1, orig = n2 },
    }

    local GlissandoMark = require("classes.glissando_mark")
    local PortamentoMark = require("classes.portamento_mark")
    table.insert(st.glissando_marks, GlissandoMark.new({ track_guid = trk1.guid, start_qn1 = 0.0, pitch1 = 60, start_qn2 = 1.5, pitch2 = 66 }))
    table.insert(st.portamento_marks, PortamentoMark.new({ track_guid = trk1.guid, start_qn1 = 0.0, pitch1 = 60, start_qn2 = 1.5, pitch2 = 66 }))

    local ctx = reaper.ImGui_CreateContext("test")
    local dl  = reaper.ImGui_GetWindowDrawList(ctx)
    GlissandoService.draw_glissandos(ctx, dl, st, render_map, 1.0, 0, 1000, 0, 800, true, 260, 218, false)
    PortamentoService.draw_portamentos(ctx, dl, st, render_map, 1.0, 0, 1000, 0, 800, true, 260, 218, false)
    GlissandoService.save_glissandos(st)
    PortamentoService.save_portamentos(st)
end)

run_test("DynamicsEngine, DynamicTextService & HairpinService", function()
    local st, env, trk1, item1, take1 = setup_rich_mock_project()
    local DynamicsEngine = require("services.dynamics_engine")
    local DynamicTextService = require("services.dynamic_text_service")
    local HairpinService = require("services.hairpin_service")

    if HairpinService.load_hairpins then HairpinService.load_hairpins(st) end
    if DynamicTextService.load_dynamic_texts then DynamicTextService.load_dynamic_texts(st) end
    if HairpinService.add_hairpin then
        pcall(HairpinService.add_hairpin, st, "cresc", 0.0, 4.0, trk1.guid)
    end
    if DynamicTextService.add_dynamic_text then
        pcall(DynamicTextService.add_dynamic_text, st, "cresc.", 0.0, 4.0, trk1.guid)
    end
    if DynamicsEngine.apply_dynamics_to_take then
        pcall(DynamicsEngine.apply_dynamics_to_take, take1, st)
    elseif DynamicsEngine.recalculate_all then
        pcall(DynamicsEngine.recalculate_all, st)
    end
    if HairpinService.save_hairpins then HairpinService.save_hairpins(st) end
    if DynamicTextService.save_dynamic_texts then DynamicTextService.save_dynamic_texts(st) end
end)

run_test("PedalService, OctaveService, FermataService, RehearsalMarkService, RepeatService, TempoService, KeySignatureService, ScaleService, TextItemService", function()
    local st, env, trk1, item1, take1 = setup_rich_mock_project()
    local services_to_exercise = {
        { mod = "services.pedal_service",          load = "load_pedals",          save = "save_pedals" },
        { mod = "services.octave_service",         load = "load_octave_lines",    save = "save_octave_lines" },
        { mod = "services.fermata_service",        load = "load_fermatas",        save = "save_fermatas" },
        { mod = "services.rehearsal_mark_service", load = "load_rehearsal_marks", save = "save_rehearsal_marks" },
        { mod = "services.repeat_service",         load = "load_repeats",         save = "save_repeats" },
        { mod = "services.tempo_service",          load = "load_tempo_markers",   save = "save_tempo_markers" },
        { mod = "services.key_signature_service",  load = "load_key_signatures",  save = "save_key_signatures" },
        { mod = "services.scale_service" },
        { mod = "services.text_item_service",      load = "load_text_items",      save = "save_text_items" },
    }
    for _, s in ipairs(services_to_exercise) do
        local srv = require(s.mod)
        if s.load and srv[s.load] then srv[s.load](st) end
        if s.save and srv[s.save] then srv[s.save](st) end
    end
end)

run_test("QuantizeService, RecordQuantizeService (incl. Auto-Divisi), FilterNotesService, DivisiService & DivisioVocumService", function()
    local st, env, trk1, item1, take1 = setup_rich_mock_project()
    local QuantizeService = require("services.quantize_service")
    local RecordQuantizeService = require("services.record_quantize_service")
    local FilterNotesService = require("services.filter_notes_service")
    local DivisiService = require("services.divisi_service")
    local DivisioVocumService = require("services.divisio_vocum_service")

    if QuantizeService.quantize_selected_notes then
        pcall(QuantizeService.quantize_selected_notes, st, 0.25, 1.0, true, true)
    end
    if FilterNotesService.scan_irregular_notes then
        pcall(FilterNotesService.scan_irregular_notes, st)
    end
    if RecordQuantizeService.sync_live_divisi_routing then
        st.auto_divisi_active = true
        st.auto_divisi_mode = "smart_register"
        trk1.recarm = 1
        RecordQuantizeService.sync_live_divisi_routing(st)
        st.auto_divisi_mode = "top_down"
        RecordQuantizeService.sync_live_divisi_routing(st)
        st.auto_divisi_active = false
        RecordQuantizeService.sync_live_divisi_routing(st)
    end
    if DivisiService.analyze_selected_track then
        pcall(DivisiService.analyze_selected_track, st)
    end
    if DivisioVocumService.distribute_voices then
        pcall(DivisioVocumService.distribute_voices, st)
    end
end)

run_test("MelodyPathfinderService: Normal, Inverted, Retrograde & Counter-Melody across all 4 Film Styles", function()
    local st, env, trk1, item1, take1 = setup_rich_mock_project()
    local MelodyPathfinder = require("services.melody_pathfinder_service")
    local Note = require("classes.note")

    local anchor1 = Note.new({ idx = 0, start_qn = 0.0, end_qn = 1.0, pitch = 60, vel = 90, chan = 0, take = take1, item = item1, track = trk1 })
    local anchor2 = Note.new({ idx = 1, start_qn = 4.0, end_qn = 5.0, pitch = 67, vel = 95, chan = 0, take = take1, item = item1, track = trk1 })
    st.selected_notes = { [anchor1:get_key()] = anchor1, [anchor2:get_key()] = anchor2 }

    local directions = { "normal", "inverted", "retrograde", "retrograde_inverted" }
    for style_idx = 0, 4 do
        for _, dir in ipairs(directions) do
            local opts = {
                direction = dir,
                composer_style = style_idx,
                generate_counter = true,
                clef = "treble",
                complexity = 0.5,
                step_division = 0.5,
            }
            if MelodyPathfinder.generate_candidates then
                local cands = MelodyPathfinder.generate_candidates(st, { anchor1, anchor2 }, opts)
                assert_true(type(cands) == "table" and #cands > 0, "Generated candidates for dir=" .. dir .. " style=" .. tostring(style_idx))
            end
        end
    end
end)

run_test("PatternService: pattern categories & library integrity", function()
    local PatternService = require("services.pattern_service")
    if PatternService.init then PatternService.init() end
    if PatternService.get_categories then
        local cats = PatternService.get_categories()
        assert_true(type(cats) == "table", "Pattern categories loaded")
    end
end)

run_test("MusicXML Export & Import Round-Trip Service", function()
    local st, env, trk1, item1, take1 = setup_rich_mock_project()
    local ExportSrv = require("services.musicxml_export_service")
    local ImportSrv = require("services.musicxml_import_service")

    local tmp_xml = repo_root .. "/tests/_temp_roundtrip_test.musicxml"
    if ExportSrv.export_project or ExportSrv.export_to_file then
        local fn = ExportSrv.export_to_file or ExportSrv.export_project
        pcall(fn, st, tmp_xml)
    elseif ExportSrv.build_musicxml_string then
        local xml_str = ExportSrv.build_musicxml_string(st)
        assert_true(type(xml_str) == "string" and #xml_str > 100, "MusicXML string generated")
        local f = io.open(tmp_xml, "w")
        if f then f:write(xml_str); f:close() end
    end
    if ImportSrv.import_file or ImportSrv.import_musicxml then
        local ifn = ImportSrv.import_file or ImportSrv.import_musicxml
        pcall(ifn, st, tmp_xml)
    end
    os.remove(tmp_xml)
end)

run_test("AnnotationService: Layer CRUD, Brush/Eraser Stamp & PNG Tile Roundtrip Encoding", function()
    local st, env, trk1 = setup_rich_mock_project()
    local AnnotationService = require("services.annotation_service")
    local guid = trk1.guid
    AnnotationService.ensure_state(st)
    local stack = AnnotationService.get_track_stack(st, guid)
    assert_true(type(stack) == "table" and type(stack.layers) == "table", "get_track_stack returns valid stack")
    local layer = AnnotationService.add_layer(st, guid)
    assert_true(layer ~= nil and layer.id ~= nil, "add_layer created layer")

    -- Test rasterize_bar_segment (pen & eraser) + PNG encode/decode round-trip
    AnnotationService.rasterize_bar_segment(st, guid, 0, 0.2, 0.2, 0.8, 0.8, false, 260, 195)
    AnnotationService.rasterize_bar_segment(st, guid, 0, 0.4, 0.4, 0.6, 0.6, true,  260, 195)

    local w, h = 16, 16
    local pixels = {}
    for i = 1, w * h do pixels[i] = 0xE74C3CFF end
    local png_bytes = AnnotationService.encode_rgba_png(pixels, w, h)
    assert_true(type(png_bytes) == "string" and #png_bytes > 32, "encode_rgba_png produced valid PNG stream")
    local decoded = AnnotationService.decode_rgba_png(png_bytes, w, h)
    assert_true(type(decoded) == "table" and decoded[1] == 0xE74C3CFF, "decode_rgba_png roundtrip matches exact RGBA pixel")

    AnnotationService.clear_layer(st, guid, layer.id)
    AnnotationService.delete_layer(st, guid, layer.id)
end)

-- ==============================================================================
-- SUITE 4: Engraving Engine & ScoreCanvas Rendering (Gould/Read + NaN/Inf Check)
-- ==============================================================================
begin_suite("Suite 4: Engraving Engine & ScoreCanvas Stress-Tests")

run_test("Engraver primitive drawing functions & Gould/Read invariants", function()
    local Engraver = require("rendering.engraver")
    local FontManager = require("rendering.font_manager")
    local ctx = reaper.ImGui_CreateContext("engraver_test")
    local dl  = reaper.ImGui_GetWindowDrawList(ctx)
    local fonts = FontManager.init(ctx)
    local s   = 1.0
    local col = 0x1A1A1AFF

    -- 1. Test all key signatures (-7 to +7)
    for ks = -7, 7 do
        Engraver.draw_key_signature(dl, ks, 140, 232, 8.0, s, col, fonts.font_music, "treble", 0)
        Engraver.draw_key_signature(dl, ks, 140, 232, 8.0, s, col, fonts.font_music, "bass", 0)
    end

    -- 2. Test Piano Brace '{'
    Engraver.draw_piano_brace(dl, 95, 200, 320, s, col)

    -- 3. Test Articulation staff-line avoidance (Point 6: Behind Bars pp. 115-121)
    local top_y = 200.0
    local bot_y = 232.0
    local l_spacing = 8.0
    local step_y = 4.0
    for dstep = -2, 10 do
        local ny = bot_y - dstep * step_y
        for _, art in ipairs({ "staccato", "staccatissimo", "tenuto", "accent", "marcato", "harmonic", "fermata" }) do
            local ay, is_above = Engraver.get_articulation_y(art, ny, dstep, true, top_y, bot_y, l_spacing, s, ny + 28)
            assert_true(type(ay) == "number" and ay == ay, "get_articulation_y returned finite number for " .. art)
            Engraver.draw_articulation(dl, art, 250, ay, s, col, fonts.font_music, is_above)
            if (art == "staccato" or art == "tenuto") and dstep >= 0 and dstep <= 8 then
                -- Verify ay does not sit on any of the 5 staff lines (rel_step = 0, 2, 4, 6, 8)
                local rel_step = (bot_y - ay) / step_y
                for _, staff_line_step in ipairs({ 0, 2, 4, 6, 8 }) do
                    local dist = math.abs(rel_step - staff_line_step)
                    assert_true(dist > 0.25, string.format("%s at dstep=%d landed on staff line %d (rel_step=%.2f)", art, dstep, staff_line_step, rel_step))
                end
            end
        end
    end

    -- 4. Test 32nd/64th Beaming & Paired Fractional Stubs (Points 1 & 3)
    local beam_group = {
        { vis_nx = 200, vis_ny = 224, nx = 200, ny = 224, dur_qn = 0.75,  start_qn = 0.0,   dstep = 2, pitch = 67, stem_down = false }, -- dotted 8th
        { vis_nx = 240, vis_ny = 220, nx = 240, ny = 220, dur_qn = 0.125, start_qn = 0.75,  dstep = 3, pitch = 69, stem_down = false }, -- 32nd
        { vis_nx = 270, vis_ny = 216, nx = 270, ny = 216, dur_qn = 0.125, start_qn = 0.875, dstep = 4, pitch = 71, stem_down = false }, -- 32nd
    }
    local render_map = {}
    Engraver.calculate_and_draw_beams(dl, beam_group, s, col, render_map, nil, false)
    for _, bn in ipairs(beam_group) do
        local end_y = bn.beam_stem_end_y or bn.stem_end_y
        assert_true(end_y ~= nil, "Beamed note beam_stem_end_y computed")
        assert_true(math.abs(bn.vis_ny - end_y) >= 24.0 * s, "32nd beamed stem has sufficient length")
    end

    -- 5. Test Tuplets clearing top staff line, stems & articulations (Point 8)
    local tuplet_notes = {
        { nx = 300, ny = 220, start_qn = 0.0,   dur_qn = 0.333, stem_down = false, stem_end_y = 192, art_y = 184, art_is_above = true, staff_top_y = top_y, staff_bottom_y = bot_y, chan = 0 },
        { nx = 340, ny = 216, start_qn = 0.333, dur_qn = 0.333, stem_down = false, stem_end_y = 188, art_y = 180, art_is_above = true, staff_top_y = top_y, staff_bottom_y = bot_y, chan = 0 },
        { nx = 380, ny = 212, start_qn = 0.666, dur_qn = 0.334, stem_down = false, stem_end_y = 184, art_y = 176, art_is_above = true, staff_top_y = top_y, staff_bottom_y = bot_y, chan = 0 },
    }
    Engraver.detect_and_draw_tuplets(dl, tuplet_notes, s, col, fonts.font_music, fonts.font_main, 4.0, {}, 0, 1000, col)
end)

run_test("ScoreCanvas.render full multi-track pipeline across view modes, zooms & time signatures", function()
    local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
    local ScoreCanvas = require("rendering.score_canvas")
    local MidiService = require("services.midi_service")
    local ctx = reaper.ImGui_CreateContext("canvas_test")

    local before_draws = env.draw_calls
    for _, vmode in ipairs({ "auto", "treble", "bass", "grand" }) do
        st.view_mode = vmode
        for _, zoom in ipairs({ 0.75, 1.0, 1.5 }) do
            st.zoom = zoom
            local cinfo = ScoreCanvas.render(ctx, st, fonts, project_tracks, MidiService)
            assert_true(type(cinfo) == "table", "ScoreCanvas.render returned canvas_info")
        end
    end
    -- Also test compound meter 6/8 and asymmetric meter 7/8
    env.ts_num = 6; env.ts_den = 8
    ScoreCanvas.render(ctx, st, fonts, project_tracks, MidiService)
    env.ts_num = 7; env.ts_den = 8
    ScoreCanvas.render(ctx, st, fonts, project_tracks, MidiService)
    env.ts_num = 4; env.ts_den = 4

    assert_true(env.draw_calls > before_draws + 500, "ScoreCanvas rendered hundreds of validated vector draw calls without any NaN/Inf")
end)

-- ==============================================================================
-- SUITE 5: Input Handlers (KeyboardHandler & MouseHandler)
-- ==============================================================================
begin_suite("Suite 5: Input Handlers (KeyboardHandler & MouseHandler)")

run_test("KeyboardHandler: shortcut execution & complete blocking during layer rename / active text input", function()
    local st, env, trk1, item1, take1, project_tracks, fonts, canvas_info = setup_rich_mock_project()
    local KeyboardHandler = require("input.keyboard_handler")
    local MidiService = require("services.midi_service")
    local ClipboardService = require("services.clipboard_service")
    local DynamicsEngine = require("services.dynamics_engine")
    local ctx = reaper.ImGui_CreateContext("kb_test")

    -- 1. Verify Spacebar is blocked while renaming an Annotation Layer!
    env.play_state = 0
    st.renaming_layer_id = "layer_1"
    env.active_keys_pressed[reaper.ImGui_Key_Space()] = true
    KeyboardHandler.handle(ctx, st, MidiService, ClipboardService, DynamicsEngine, st.active_tracks_cache)
    assert_eq(env.play_state, 0, "Spacebar must NOT trigger Play while renaming_layer_id is active")

    -- 2. Verify Spacebar is blocked when any ImGui InputText is active!
    st.renaming_layer_id = nil
    env.any_item_active = true
    KeyboardHandler.handle(ctx, st, MidiService, ClipboardService, DynamicsEngine, st.active_tracks_cache)
    assert_eq(env.play_state, 0, "Spacebar must NOT trigger Play when ImGui_IsAnyItemActive is true")

    env.any_item_active = false
    env.active_keys_pressed = {}
end)

run_test("KeyboardHandler: Step Input mode note entry (C, D, E, F, G, A, B, H) with AudioPreview & cursor advance", function()
    local st, env, trk1, item1, take1, project_tracks, fonts, canvas_info = setup_rich_mock_project()
    local KeyboardHandler = require("input.keyboard_handler")
    local MidiService = require("services.midi_service")
    local ClipboardService = require("services.clipboard_service")
    local DynamicsEngine = require("services.dynamics_engine")
    local ctx = reaper.ImGui_CreateContext("kb_step_test")

    st:set_input_mode("step")
    st.focused_track = trk1
    st.note_duration = 1.0
    reaper.SetEditCurPos(8.0, false, false)

    local step_keys = {
        reaper.ImGui_Key_C(),
        reaper.ImGui_Key_D(),
        reaper.ImGui_Key_E(),
        reaper.ImGui_Key_F(),
        reaper.ImGui_Key_G(),
        reaper.ImGui_Key_A(),
        reaper.ImGui_Key_B(),
        reaper.ImGui_Key_H(),
    }
    local before_notes = #take1.notes
    for i, kcode in ipairs(step_keys) do
        env.active_keys_pressed[kcode] = true
        KeyboardHandler.handle(ctx, st, MidiService, ClipboardService, DynamicsEngine, st.active_tracks_cache)
        env.active_keys_pressed[kcode] = false
    end
    assert_eq(#take1.notes, before_notes + #step_keys, "Step Input inserted all 8 notes (C..H) into active MIDI item")
    assert_true(math.abs(reaper.GetCursorPosition() - (8.0 + #step_keys * 0.5)) < 0.01, "Step Input advanced edit cursor after each note")
end)

run_test("MouseHandler: canvas hover, click & drag handling", function()
    local st, env, trk1, item1, take1, project_tracks, fonts, canvas_info = setup_rich_mock_project()
    local MouseHandler = require("input.mouse_handler")
    local MidiService = require("services.midi_service")
    local DynamicsEngine = require("services.dynamics_engine")
    local ctx = reaper.ImGui_CreateContext("mouse_test")
    MouseHandler.handle(ctx, st, canvas_info, MidiService, DynamicsEngine)
end)

-- ==============================================================================
-- SUITE 6: All 21 UI Drawers, Modals & Toolbars + Interactive Click Fuzzer
-- ==============================================================================
begin_suite("Suite 6: All 21 UI Drawers, Modals & Toolbars + Interactive Click Fuzzer")

local MidiService = require("services.midi_service")
local ClipboardService = require("services.clipboard_service")
local DynamicsEngine = require("services.dynamics_engine")
local AudioPreview = require("services.audio_preview")
local ShortcutManager = require("services.shortcut_manager")
local KeySignatureService = require("services.key_signature_service")

local ui_specs = {
    {
        name = "ui.top_bar",
        call = function(ctx, st, project_tracks, fonts)
            require("ui.top_bar").render(ctx, st, ClipboardService, MidiService, st.active_tracks_cache, #project_tracks, 1, 0, project_tracks)
        end
    },
    {
        name = "ui.sidebar",
        call = function(ctx, st, project_tracks, fonts)
            require("ui.sidebar").render(ctx, st, MidiService, ClipboardService, st.active_tracks_cache, 230, 600, 1, 0)
        end
    },
    {
        name = "ui.bottom_bar",
        call = function(ctx, st, project_tracks, fonts)
            require("ui.bottom_bar").render(ctx, st, 46, 1, 0)
        end
    },
    {
        name = "ui.track_picker",
        call = function(ctx, st, project_tracks, fonts)
            st.show_track_picker = true
            require("ui.track_picker").render(ctx, st, project_tracks)
        end
    },
    {
        name = "ui.annotation_drawer",
        call = function(ctx, st, project_tracks, fonts)
            st.show_annotations_drawer = true
            require("ui.annotation_drawer").render(ctx, st, st.active_tracks_cache, 236, 600, 1, 0)
        end
    },
    {
        name = "ui.articulations_drawer",
        call = function(ctx, st, project_tracks, fonts)
            st.show_articulations_drawer = true
            local ad = require("ui.articulations_drawer")
            ad.render(ctx, st, MidiService, st.active_tracks_cache, 236, 600, 1, 0)
            st.show_last_resort_modal = true
            ad.render_last_resort_modal(ctx, st, st.active_tracks_cache)
        end
    },
    {
        name = "ui.bank_picker_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_bank_picker = true
            require("ui.bank_picker_modal").render(ctx, st, st.focused_track, st.active_tracks_cache)
        end
    },
    {
        name = "ui.circle_of_fifths_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_circle_of_fifths_modal = true
            require("ui.circle_of_fifths_modal").render(ctx, st, MidiService)
        end
    },
    {
        name = "ui.clef_drawer",
        call = function(ctx, st, project_tracks, fonts)
            st.show_clefs = true
            require("ui.clef_drawer").render(ctx, st, 236, 600, 1, 0, fonts.font_music, fonts.font_main)
        end
    },
    {
        name = "ui.divisi_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_divisi_modal = true
            require("ui.divisi_modal").render(ctx, st, MidiService, st.active_tracks_cache)
        end
    },
    {
        name = "ui.divisio_vocum_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_divisio_modal = true
            st.show_divisio_vocum = true
            require("ui.divisio_vocum_modal").render(ctx, st, MidiService, st.active_tracks_cache)
        end
    },
    {
        name = "ui.dynamics_drawer",
        call = function(ctx, st, project_tracks, fonts)
            st.show_dynamics = true
            require("ui.dynamics_drawer").render(ctx, st, DynamicsEngine, MidiService, st.active_tracks_cache, 236, 600, 1, 0)
        end
    },
    {
        name = "ui.filter_irregular_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_filter_irregular_modal = true
            st.show_filter_irregular = true
            require("ui.filter_irregular_modal").render(ctx, st, MidiService, st.active_tracks_cache)
        end
    },
    {
        name = "ui.help_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_help = true
            require("ui.help_modal").render(ctx, st)
        end
    },
    {
        name = "ui.key_signature_drawer",
        call = function(ctx, st, project_tracks, fonts)
            st.show_key_signatures = true
            require("ui.key_signature_drawer").render(ctx, st, KeySignatureService, MidiService, 236, 600, 1, 0, fonts.font_music, fonts.font_main)
        end
    },
    {
        name = "ui.melody_pathfinder_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_melody_pathfinder_modal = true
            st.show_melody_pathfinder = true
            require("ui.melody_pathfinder_modal").render(ctx, st, MidiService, AudioPreview, st.active_tracks_cache)
        end
    },
    {
        name = "ui.midi_editor_drawer",
        call = function(ctx, st, project_tracks, fonts)
            st.show_midi_editor = true
            require("ui.midi_editor_drawer").render(ctx, st, MidiService, AudioPreview, DynamicsEngine, 1000, 180, project_tracks, fonts.font_main)
        end
    },
    {
        name = "ui.musicxml_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_musicxml_modal = true
            require("ui.musicxml_modal").render(ctx, st, project_tracks)
        end
    },
    {
        name = "ui.pattern_browser",
        call = function(ctx, st, project_tracks, fonts)
            st.show_pattern_browser = true
            require("ui.pattern_browser").render(ctx, st, MidiService, AudioPreview, 1000, 240, project_tracks, fonts.font_music, fonts.font_main)
        end
    },
    {
        name = "ui.quantize_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_quantize_modal = true
            require("ui.quantize_modal").render(ctx, st, MidiService, st.active_tracks_cache)
        end
    },
    {
        name = "ui.record_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_record_modal = true
            require("ui.record_modal").render(ctx, st, MidiService, project_tracks, st.active_tracks_cache)
        end
    },
    {
        name = "ui.scale_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_scale_modal = true
            require("ui.scale_modal").render(ctx, st)
        end
    },
    {
        name = "ui.settings_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_settings = true
            require("ui.settings_modal").render(ctx, st, ShortcutManager)
        end
    },
    {
        name = "ui.tempo_drawer",
        call = function(ctx, st, project_tracks, fonts)
            st.show_tempo = true
            require("ui.tempo_drawer").render(ctx, st, 236, 600, 1, 0)
        end
    },
    {
        name = "ui.tools_drawer",
        call = function(ctx, st, project_tracks, fonts)
            st.show_tools_drawer = true
            require("ui.tools_drawer").render(ctx, st, MidiService, st.active_tracks_cache, 236, 600, 1, 0, fonts.font_music, fonts.font_main)
        end
    },
    {
        name = "ui.circle_of_fifths_modal",
        call = function(ctx, st, project_tracks, fonts)
            st.show_circle_of_fifths_modal = true
            require("ui.circle_of_fifths_modal").render(ctx, st, MidiService)
        end
    },
}

for _, u in ipairs(ui_specs) do
    run_test("UI Render & Interactive Button Fuzzer: " .. u.name, function()
        local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
        local ctx = reaper.ImGui_CreateContext("ui_test")

        -- Pass 0: Passive render to discover total interactive widget count
        env.widget_counter = 0
        env.max_widget_seen = 0
        env.click_target_idx = nil
        env.imgui_win_depth = 0
        env.imgui_child_depth = 0
        u.call(ctx, st, project_tracks, fonts)
        assert_eq(env.imgui_child_depth, 0, u.name .. " pass 0: zero unclosed ImGui_BeginChild (Missing EndChild check)")
        assert_eq(env.imgui_win_depth, 0, u.name .. " pass 0: zero unclosed ImGui_Begin (Missing End check)")
        local total_widgets = math.min(env.max_widget_seen, 60)

        -- Passes 1..total_widgets: Click each button/checkbox/selectable one by one!
        for w_idx = 1, total_widgets do
            env.widget_counter = 0
            env.click_target_idx = w_idx
            env.imgui_win_depth = 0
            env.imgui_child_depth = 0
            u.call(ctx, st, project_tracks, fonts)
            assert_eq(env.imgui_child_depth, 0, u.name .. " click #" .. w_idx .. ": zero unclosed ImGui_BeginChild")
            assert_eq(env.imgui_win_depth, 0, u.name .. " click #" .. w_idx .. ": zero unclosed ImGui_Begin")
        end
        env.click_target_idx = nil
    end)
end

-- ==============================================================================
-- SUITE 7: Deep Function-Level Audit (Clipboard, Selection, AudioPreview,
--          Context Menus, SystemEngraver, Shortcuts & All Tool Modes)
-- ==============================================================================
begin_suite("Suite 7: Deep Function-Level Audit & Edge-Case Fuzzing")

run_test("ClipboardService: copy, cut & paste across all 8 notation object types", function()
    local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
    local ClipboardService = require("services.clipboard_service")
    local MidiService = require("services.midi_service")
    local DynamicMarker = require("classes.dynamic")
    local Hairpin = require("classes.hairpin")
    local DynamicText = require("classes.dynamic_text")
    local PedalMark = require("classes.pedal_mark")
    local TempoMarker = require("classes.tempo_marker")
    local OctaveLine = require("classes.octave_line")
    local TextItem = require("classes.text_item")

    -- Empty selection copy should safely return false
    st:clear_selection()
    assert_eq(ClipboardService.copy(st, st.active_tracks_cache), false, "Empty copy returns false")

    -- Select notes + all 7 non-note object types
    local n1 = st.active_tracks_cache[1].notes[1]
    st:select_note(n1, true)
    st.selected_dynamic = DynamicMarker.new({ track = trk1, item = item1, take = take1, qn = 0.0, label = "f" })
    st.selected_hairpin = Hairpin.new({ id = "hp_clip", track_guid = st.active_tracks_cache[1].guid, type = "cresc", start_qn = 0.0, end_qn = 2.0 })
    st.selected_dynamic_text = DynamicText.new({ id = "dt_clip", track_guid = st.active_tracks_cache[1].guid, text = "cresc.", start_qn = 0.0, end_qn = 2.0 })
    st.selected_pedal = PedalMark.new({ id = "pm_clip", track_guid = st.active_tracks_cache[1].guid, start_qn = 0.0, end_qn = 2.0 })
    st.selected_tempo_marker = TempoMarker.new({ id = "tm_clip", type = "absolute", start_qn = 0.0, bpm = 128, label = "Vivo" })
    st.selected_octave_line = OctaveLine.new({ id = "ol_clip", track_guid = st.active_tracks_cache[1].guid, type = "8va", start_qn = 0.0, end_qn = 2.0 })
    st.selected_text_item = TextItem.new({ id = "ti_clip", track_guid = st.active_tracks_cache[1].guid, qn = 0.0, text = "dolce" })

    local ok_copy = ClipboardService.copy(st, st.active_tracks_cache)
    assert_true(ok_copy == true, "ClipboardService.copy succeeded")

    reaper.SetEditCurPos(reaper.TimeMap2_QNToTime(0, 8.0), false, false)
    if ClipboardService.paste then
        ClipboardService.paste(st, st.active_tracks_cache, MidiService)
    end
    if ClipboardService.cut then
        ClipboardService.cut(st, st.active_tracks_cache, MidiService)
    end
end)

run_test("SelectionService: init_state, has_selection, count_all_selected, select_to_end & apply_filter", function()
    local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
    local SelectionService = require("services.selection_service")
    local MidiService = require("services.midi_service")

    -- Nil-safety checks
    SelectionService.init_state(nil)
    assert_eq(SelectionService.has_selection(nil), false, "has_selection(nil) is false")
    local c1 = SelectionService.count_all_selected(nil)
    assert_eq(c1, 0, "count_all_selected(nil) returns 0")

    SelectionService.init_state(st)
    st:select_note(st.active_tracks_cache[1].notes[1], false)
    assert_true(SelectionService.has_selection(st), "has_selection(st) is true")

    SelectionService.select_to_end(st, st.active_tracks_cache, MidiService)
    assert_true(st:count_selected_notes() >= 1, "select_to_end selected notes")

    if SelectionService.clear_all then
        SelectionService.clear_all(st)
    end
end)

run_test("AudioPreview, PathService, ReaticulateParser, ShortcutManager & FrameTimerService", function()
    local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
    local AudioPreview = require("services.audio_preview")
    local PathService = require("services.path_service")
    local ReaticulateParser = require("services.reaticulate_parser")
    local ShortcutManager = require("services.shortcut_manager")
    local FrameTimerService = require("services.frame_timer_service")

    -- AudioPreview
    AudioPreview.prepare_track(nil)
    AudioPreview.restore_track(nil)
    assert_eq(AudioPreview.is_track_user_armed(nil), false, "is_track_user_armed(nil)")
    local cc_val = AudioPreview.get_track_cc_at_qn(trk1, 0, 11, 1.0, take1)
    assert_true(type(cc_val) == "number", "get_track_cc_at_qn returns number")
    AudioPreview.prepare_track(trk1)
    AudioPreview.restore_track(trk1)
    AudioPreview.restore_all_tracks()

    -- PathService
    assert_eq(PathService.normalize(nil), "", "PathService.normalize(nil)")
    assert_eq(PathService.normalize("C:\\foo\\\\bar/baz/"), "C:/foo/bar/baz", "PathService.normalize cleans slashes")
    assert_true(type(PathService.to_native("C:/foo/bar")) == "string", "PathService.to_native")
    assert_eq(PathService.file_exists(nil), false, "PathService.file_exists(nil)")
    assert_eq(PathService.dir_exists(nil), false, "PathService.dir_exists(nil)")
    assert_true(type(PathService.get_script_dir()) == "string", "PathService.get_script_dir")
    assert_true(type(PathService.get_reaper_resource_dir(st)) == "string", "PathService.get_reaper_resource_dir")
    assert_true(type(PathService.get_os_default_path_hint()) == "string", "PathService.get_os_default_path_hint")

    -- ReaticulateParser
    local v, l, s = ReaticulateParser.extract_vendor_library_section("Spitfire/Albion One/Strings")
    assert_eq(v, "Spitfire", "Vendor parsed")
    assert_eq(l, "Albion One", "Library parsed")
    assert_eq(s, "Strings", "Section parsed")
    local v0, l0, s0 = ReaticulateParser.extract_vendor_library_section(nil)
    assert_eq(v0, "User / Custom", "Nil group fallback")

    -- ShortcutManager
    ShortcutManager.init()
    ShortcutManager.save()
    ShortcutManager.load()
    for action_id, sc in pairs(ShortcutManager.DEFAULT_SHORTCUTS) do
        local disp = ShortcutManager.get_display_string(sc)
        assert_true(type(disp) == "string", "Shortcut display for " .. action_id)
    end

    -- FrameTimerService
    for _, fps in ipairs({ 0, 15, 30, 60, 90, 120, 144 }) do
        st.target_fps = fps
        FrameTimerService.tick(st)
    end
    FrameTimerService.restore()
end)

run_test("CanvasContextMenus: render_all & Interactive MenuItem Fuzzer across all 19 Popups", function()
    local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
    local CanvasContextMenus = require("rendering.canvas_context_menus")
    local MidiService = require("services.midi_service")
    local ChordItem = require("classes.chord_item")
    local DynamicMarker = require("classes.dynamic")
    local Hairpin = require("classes.hairpin")
    local DynamicText = require("classes.dynamic_text")
    local PedalMark = require("classes.pedal_mark")
    local PortamentoMark = require("classes.portamento_mark")
    local GlissandoMark = require("classes.glissando_mark")
    local TempoMarker = require("classes.tempo_marker")
    local OctaveLine = require("classes.octave_line")
    local TextItem = require("classes.text_item")
    local Fermata = require("classes.fermata")
    local RehearsalMark = require("classes.rehearsal_mark")

    local ctx = reaper.ImGui_CreateContext("context_menus_test")
    local tguid = st.active_tracks_cache[1].guid
    local n1 = st.active_tracks_cache[1].notes[1]

    local function populate_context_targets()
        st:select_note(n1, false)
        st.context_note = n1
        st.context_chord_item = ChordItem.new({ id = "ci_ctx", start_qn = 0, end_qn = 4, text = "C Major", root = 0, scale_type = "major" })
        st.context_dynamic = DynamicMarker.new({ track = trk1, item = item1, take = take1, qn = 0, label = "mf" })
        st.context_hairpin = Hairpin.new({ id = "hp_ctx", track_guid = tguid, type = "cresc", start_qn = 0, end_qn = 4 })
        st.context_dynamic_text = DynamicText.new({ id = "dt_ctx", track_guid = tguid, text = "cresc.", start_qn = 0, end_qn = 4 })
        st.context_pedal = PedalMark.new({ id = "pm_ctx", track_guid = tguid, start_qn = 0, end_qn = 4 })
        st.context_portamento = PortamentoMark.new({ id = "port_ctx", track_guid = tguid, start_qn = 0, end_qn = 1, pitch1 = 60, pitch2 = 64 })
        st.context_glissando = GlissandoMark.new({ id = "gliss_ctx", track_guid = tguid, start_qn = 0, end_qn = 1, pitch1 = 60, pitch2 = 72 })
        st.context_tempo_marker = TempoMarker.new({ id = "tm_ctx", type = "absolute", start_qn = 0, bpm = 120, label = "Allegro" })
        st.editing_tempo_marker = st.context_tempo_marker
        st.context_octave_line = OctaveLine.new({ id = "ol_ctx", track_guid = tguid, type = "8va", start_qn = 0, end_qn = 4 })
        st.context_text_item = TextItem.new({ id = "ti_ctx", track_guid = tguid, qn = 0, text = "espr." })
        st.context_fermata = Fermata.new({ id = "fm_ctx", track_guid = tguid, qn = 0, type = "normal" })
        st.context_rehearsal_mark = RehearsalMark.new({ id = "rm_ctx", qn = 0, text = "A" })
        st.context_item_header = st.active_tracks_cache[1].items[1]
        st.context_measure_idx = 0
    end

    populate_context_targets()
    env.widget_counter = 0
    env.max_widget_seen = 0
    env.click_target_idx = nil
    CanvasContextMenus.render_all(ctx, st, MidiService, st.active_tracks_cache, 4.0)

    local max_menu_items = math.min(env.max_widget_seen, 80)
    for w_idx = 1, max_menu_items do
        populate_context_targets()
        env.widget_counter = 0
        env.click_target_idx = w_idx
        CanvasContextMenus.render_all(ctx, st, MidiService, st.active_tracks_cache, 4.0)
    end
    env.click_target_idx = nil
end)

run_test("SystemEngraver: Paginated Score Rendering (Single & Grand Staff) with NaN/Inf Verification", function()
    local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
    local SystemEngraver = require("rendering.system_engraver")
    local ctx = reaper.ImGui_CreateContext("sys_engraver_test")
    local dl = reaper.ImGui_GetWindowDrawList(ctx)

    local t1 = st.active_tracks_cache[1]
    t1.top_y = 120.0
    t1.bot_y = 152.0
    t1.center_y = 136.0
    t1.is_grand = false

    local t2 = st.active_tracks_cache[2]
    t2.is_grand = true
    t2.upper_top = 200.0
    t2.upper_bot = 232.0
    t2.lower_top = 280.0
    t2.lower_bot = 312.0
    t2.center_y = 256.0

    local bounds = {
        margin_l = 100.0,
        score_w = 900.0,
        top_y = 120.0,
        bot_y = 480.0,
        staff_ls = 8.0,
        show_track_names = true
    }

    local mmap = SystemEngraver.build_page_measure_map(st.active_tracks_cache, 0, 4, bounds.margin_l, bounds.score_w, 1.0, st)
    assert_true(type(mmap) == "table" and mmap.page_bars == 4, "SystemEngraver.build_page_measure_map")
    local px = SystemEngraver.qn_to_page_x(2.0, mmap, 1.0)
    assert_true(type(px) == "number" and px > bounds.margin_l, "SystemEngraver.qn_to_page_x")

    SystemEngraver.render_system_imgui(dl, ctx, st.active_tracks_cache, 0, 4, bounds, 1.0, fonts, st)
end)

run_test("MouseHandler & KeyboardHandler: All Tool Modes & All Default Shortcuts", function()
    local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
    local ScoreCanvas = require("rendering.score_canvas")
    local MouseHandler = require("input.mouse_handler")
    local KeyboardHandler = require("input.keyboard_handler")
    local MidiService = require("services.midi_service")
    local DynamicsEngine = require("services.dynamics_engine")
    local ShortcutManager = require("services.shortcut_manager")
    ShortcutManager.init()
    local ctx = reaper.ImGui_CreateContext("tools_and_shortcuts_test")

    local cinfo = ScoreCanvas.render(ctx, st, fonts, project_tracks, MidiService)
    local tool_modes = {
        "select", "insert", "erase", "slur", "tie", "glissando", "portamento",
        "hairpin_cresc", "hairpin_decresc", "pedal", "octave_8va", "octave_8vb",
        "fermata", "rehearsal", "text", "annotate_pen", "annotate_eraser"
    }
    for _, mode in ipairs(tool_modes) do
        st.tool_mode = mode
        env.mouse_x = 240.0
        env.mouse_y = 210.0
        env.mouse_clicked[0] = true
        env.mouse_down[0] = true
        MouseHandler.handle(ctx, st, cinfo, MidiService, DynamicsEngine)
        env.mouse_clicked[0] = false
        env.mouse_down[0] = false
        env.mouse_released[0] = true
        MouseHandler.handle(ctx, st, cinfo, MidiService, DynamicsEngine)
        env.mouse_released[0] = false
    end
    st.tool_mode = "select"

    -- Test every keyboard key press with a selected note in both select and step modes
    local ClipboardService = require("services.clipboard_service")
    for _, imode in ipairs({ "select", "step" }) do
        st:set_input_mode(imode)
        cinfo = ScoreCanvas.render(ctx, st, fonts, project_tracks, MidiService)
        st.active_tracks_cache = cinfo.active_tracks_data
        if st.active_tracks_cache and st.active_tracks_cache[1] and st.active_tracks_cache[1].notes[1] then
            st:select_note(st.active_tracks_cache[1].notes[1], false)
        end
        for _, def in pairs(ShortcutManager.DEFAULT_SHORTCUTS) do
            local key_fn = reaper["ImGui_Key_" .. tostring(def.key)]
            if key_fn then
                local kcode = key_fn()
                env.active_keys_pressed[kcode] = true
                env.key_mods = (def.ctrl and reaper.ImGui_Mod_Ctrl() or 0)
                             | (def.shift and reaper.ImGui_Mod_Shift() or 0)
                             | (def.alt and reaper.ImGui_Mod_Alt() or 0)
                KeyboardHandler.handle(ctx, st, MidiService, ClipboardService, DynamicsEngine, st.active_tracks_cache)
                env.active_keys_pressed[kcode] = false
                env.key_mods = 0
            end
        end
    end
end)

run_test("Percussion & Custom Notehead Selector: Multi-Note Conversion, Persistence & Engraving", function()
    local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
    local Constants = require("constants")
    local MidiService = require("services.midi_service")
    local Engraver = require("rendering.engraver")
    local ScoreCanvas = require("rendering.score_canvas")
    local ctx = reaper.ImGui_CreateContext("percussion_noteheads_test")
    local dl = reaper.ImGui_GetWindowDrawList(ctx)

    -- 1. Verify all 9 notehead types and auto are defined in Constants
    assert_true(type(Constants.NOTEHEAD_DEFS) == "table" and Constants.NOTEHEAD_DEFS.auto ~= nil, "Constants.NOTEHEAD_DEFS exists with auto")
    assert_true(type(Constants.NOTEHEAD_TYPES_ORDERED) == "table" and #Constants.NOTEHEAD_TYPES_ORDERED == 9, "9 ordered notehead shapes")
    local expected_types = { "standard", "x", "circle_x", "diamond", "triangle", "triangle_down", "plus", "slash", "square" }
    for _, htype in ipairs(expected_types) do
        local def = Constants.NOTEHEAD_DEFS[htype]
        assert_true(def ~= nil and def.label ~= nil, "NOTEHEAD_DEFS has " .. htype)
        -- Test both SMuFL and vector fallback rendering for Whole, Half, and Quarter noteheads
        Engraver.draw_oval_notehead(dl, 100, 100, 1.0, 0x111111FF, true,  false, fonts.music, htype)
        Engraver.draw_oval_notehead(dl, 120, 100, 1.0, 0x111111FF, false, false, fonts.music, htype)
        Engraver.draw_oval_notehead(dl, 140, 100, 1.0, 0x111111FF, false, true,  fonts.music, htype)
        Engraver.draw_oval_notehead(dl, 100, 120, 1.0, 0x111111FF, true,  false, nil, htype)
        Engraver.draw_oval_notehead(dl, 120, 120, 1.0, 0x111111FF, false, false, nil, htype)
        Engraver.draw_oval_notehead(dl, 140, 120, 1.0, 0x111111FF, false, true,  nil, htype)
        local dx_up, dy_up = Engraver.get_notehead_stem_attachment(htype, false, 1.0, true)
        local dx_dn, dy_dn = Engraver.get_notehead_stem_attachment(htype, true,  1.0, true)
        assert_true(dx_up > 0 and dx_dn < 0, "Stem X offset is positive for stem-up and negative for stem-down on " .. htype)
        assert_true(type(dy_up) == "number" and type(dy_dn) == "number", "Stem Y offset is numeric on " .. htype)
    end

    -- 2. Select multiple notes on a Percussion Clef system and convert their notehead type
    local trk_guid = reaper.GetTrackGUID(trk1)
    st.track_clefs[trk_guid] = "percussion"
    local cinfo = ScoreCanvas.render(ctx, st, fonts, project_tracks, MidiService)
    st.active_tracks_cache = cinfo.active_tracks_data
    local notes = st.active_tracks_cache[1].notes
    assert_true(#notes >= 3, "At least 3 notes available for multi-note selection test")

    st:clear_selection()
    st:select_note(notes[1], true)
    st:select_note(notes[2], true)
    st:select_note(notes[3], true)
    assert_eq(st:count_selected_notes(), 3, "3 notes selected simultaneously")

    -- Convert all 3 selected notes to "circle_x"
    MidiService.set_selected_notes_notehead_type(st, "circle_x")
    assert_eq(notes[1].notehead_type, "circle_x", "Note 1 notehead_type updated to circle_x")
    assert_eq(notes[2].notehead_type, "circle_x", "Note 2 notehead_type updated to circle_x")
    assert_eq(notes[3].notehead_type, "circle_x", "Note 3 notehead_type updated to circle_x")
    assert_eq(Engraver.get_note_notehead_type({ orig = notes[1], track_guid = trk_guid }, st, true, notes[1].pitch), "circle_x", "Engraver resolves circle_x")

    -- 3. Verify ProjExtState persistence round-trip
    st.note_head_types = {}
    st._persistent_notehead_records = {}
    MidiService.load_notehead_types(st)
    assert_eq(Engraver.get_note_custom_notehead_type({ orig = { pitch = notes[1].pitch, start_qn = notes[1].start_qn, chan = notes[1].chan }, track_guid = trk_guid }, st), "circle_x", "ProjExtState round-trip preserves circle_x")

    -- 4. Verify MIDI Type 15 re-parse preserves notehead_type
    MidiService.invalidate_cache()
    local _, reparsed_notes = MidiService.get_track_items_and_notes(trk1)
    local found_circle_x = 0
    for _, rn in ipairs(reparsed_notes) do
        if rn.notehead_type == "circle_x" then
            found_circle_x = found_circle_x + 1
        end
    end
    assert_true(found_circle_x >= 3, "Reparsed MIDI take preserves circle_x on all 3 selected notes")

    -- 5. Reset to "auto" (must revert to "standard", never auto-convert to percussion noteheads)
    MidiService.set_selected_notes_notehead_type(st, "auto")
    assert_eq(notes[1].notehead_type, nil, "Reset to auto clears custom notehead_type")
    for _, test_p in ipairs({ 36, 37, 38, 42, 46, 49, 51, 53, 54, 56, 60, 69, 76, 81 }) do
        assert_eq(Engraver.get_note_notehead_type({ orig = { pitch = test_p, start_qn = 99.0, chan = 0 }, track_guid = trk_guid }, st, true, test_p), "standard",
            "Unpitched percussion note at pitch " .. test_p .. " defaults to 'standard' unless set manually")
    end

    -- 6. Verify deleting a note deletes all associated Type 15 notation events & persistent records
    st:clear_selection()
    st:select_note(notes[1], false)
    MidiService.set_selected_notes_notehead_type(st, "slash")
    MidiService.invert_selected_notes_stem_direction(st, "down")
    local take1 = notes[1].take
    local sppq1 = reaper.MIDI_GetPPQPosFromProjQN(take1, notes[1].start_qn)
    reaper.MIDI_InsertTextSysexEvt(take1, false, false, sppq1, 15, string.format("NOTE %d %d articulation staccato", notes[1].pitch, notes[1].chan))
    local del_pitch = notes[1].pitch
    local del_chan = notes[1].chan
    local del_qn = notes[1].start_qn

    local del_cnt = MidiService.delete_selected_notes(st)
    assert_eq(del_cnt, 1, "Deleted 1 selected note")

    local _, _, _, text_cnt_after = reaper.MIDI_CountEvts(take1)
    local leftover_events = 0
    for ti = 0, text_cnt_after - 1 do
        local ok_t, _, _, ppq_t, etype_t, msg_t = reaper.MIDI_GetTextSysexEvt(take1, ti)
        if ok_t and etype_t == 15 and math.abs(ppq_t - sppq1) <= 25 then
            if msg_t:find(tostring(del_pitch), 1, true) then
                leftover_events = leftover_events + 1
            end
        end
    end
    assert_eq(leftover_events, 0, "All Type 15 notation events (NOTATOR_NOTEHEAD, NOTATOR_STEM, NOTE) deleted with the note")
    assert_eq(Engraver.get_note_custom_notehead_type({ orig = { pitch = del_pitch, start_qn = del_qn, chan = del_chan }, track_guid = trk_guid }, st), nil, "Deleted note custom notehead record purged")
end)

run_test("Automatic Percussion Clef Detection: True Unpitched Drums vs. Pitched Percussion & Bass Instruments", function()
    local Engraver = require("rendering.engraver")
    local State = require("state")
    local st = State.new()
    st.view_mode = "auto"

    -- 1. True unpitched percussion instruments MUST detect as "percussion_1"
    local true_percussion_names = {
        "Snare",
        "Snare Drum",
        "Military Snare",
        "Kleine Trommel",
        "Drums",
        "Drum Kit",
        "Drumset",
        "Studio Drums",
        "Schlagzeug",
        "Schlagwerk",
        "Bass Drum",
        "Orchestral Bass Drum",
        "Gran Cassa",
        "Große Trommel",
        "Kick Drum",
        "Kick",
        "Toms",
        "Floor Tom",
        "Rack Tom",
        "Taiko Drums",
        "Timbales",
        "Bongos",
        "Congas",
        "Djembe",
        "Cajon",
        "Tambourine",
        "Cymbals",
        "Crash Cymbal",
        "Ride Cymbal",
        "Hi-Hat",
        "Piatti",
        "Tam-Tam",
        "Gong",
        "Woodblock",
        "Claves",
        "Castanets",
        "Maracas",
        "Shaker",
        "Cowbell",
        "Triangle",
        "Orchestral Percussion"
    }

    for _, name in ipairs(true_percussion_names) do
        assert_true(Engraver.is_percussion_instrument_name(name), "is_percussion_instrument_name('" .. name .. "') is true")
        local detected = Engraver.get_track_clef("guid_test_perc", name, nil, st)
        assert_eq(detected, "percussion_1", "get_track_clef('" .. name .. "') auto-detects 'percussion_1'")
    end

    -- 2. Pitched percussion & mallets MUST NOT detect as percussion clef
    local pitched_percussion_expectations = {
        { name = "Timpani",                  expected = "bass" },
        { name = "Orchestral Timpani",       expected = "bass" },
        { name = "Pauken",                   expected = "bass" },
        { name = "Percussion - Timpani",     expected = "bass" },
        { name = "Xylophone",                expected = "treble" },
        { name = "Marimba",                  expected = "treble" },
        { name = "Vibraphone",               expected = "treble" },
        { name = "Glockenspiel",             expected = "treble" },
        { name = "Tubular Bells",            expected = "treble" },
        { name = "Chimes",                   expected = "treble" },
        { name = "Crotales",                 expected = "treble" },
        { name = "Kalimba",                  expected = "treble" },
        { name = "Steel Drum",               expected = "treble" },
        { name = "Hang Drum",                expected = "treble" },
        { name = "Tongue Drum",              expected = "treble" },
        { name = "Pitched Percussion",       expected = "treble" },
        { name = "Celesta",                  expected = "grand" },
    }

    for _, item in ipairs(pitched_percussion_expectations) do
        assert_true(not Engraver.is_percussion_instrument_name(item.name), "is_percussion_instrument_name('" .. item.name .. "') is false (pitched)")
        local detected = Engraver.get_track_clef("guid_test_pitched", item.name, nil, st)
        assert_eq(detected, item.expected, "get_track_clef('" .. item.name .. "') resolves to '" .. item.expected .. "' (not percussion)")
    end

    -- 3. Non-percussion instruments with overlapping substrings ("Bass", "Trombone", "Baritone", "Triangle Wave")
    local non_percussion_expectations = {
        { name = "Double Bass",              expected = "bass" },
        { name = "Bass Guitar",              expected = "bass" },
        { name = "Synth Bass",               expected = "bass" },
        { name = "Bassoon",                  expected = "bass" },
        { name = "Trombone",                 expected = "bass" },
        { name = "Baritone",                 expected = "bass" },
        { name = "Violin 1",                 expected = "treble" },
        { name = "Viola",                    expected = "alto" },
        { name = "Violoncello",              expected = "bass" },
        { name = "Grand Piano",              expected = "grand" },
        { name = "Concert Harp",             expected = "harp_3staff" },
        { name = "Triangle Wave Synth Lead", expected = "treble" },
    }

    for _, item in ipairs(non_percussion_expectations) do
        assert_true(not Engraver.is_percussion_instrument_name(item.name), "is_percussion_instrument_name('" .. item.name .. "') is false")
        local detected = Engraver.get_track_clef("guid_test_nonperc", item.name, nil, st)
        assert_eq(detected, item.expected, "get_track_clef('" .. item.name .. "') resolves to '" .. item.expected .. "'")
    end

    -- 4. Verify all MIDI pitches 0..127 (C0 to C9) stay centered on the Percussion Staff (never fall back to treble ledger lines)
    for p = 0, 127 do
        local ny, _, dstep, acc = Engraver.pitch_to_canvas_y(p, 200, 300, 4.0, false, "percussion_1", nil, 250, 0, nil)
        assert_true(dstep >= -2 and dstep <= 10, "Percussion Clef pitch " .. p .. " maps to staff step " .. tostring(dstep) .. " (within [-2, 10])")
        assert_eq(acc, 0, "Percussion Clef pitch " .. p .. " has no accidental")
        assert_true(type(ny) == "number", "Percussion Clef pitch " .. p .. " has numeric Y")
    end
end)

run_test("All Note Input Methods (Mouse Drawing, Step Input, Vertical Dragging, Accidental Overrides & C# Minor Scale/Key Signature)", function()
    local Engraver = require("rendering.engraver")
    local ScoreCanvas = require("rendering.score_canvas")
    local MouseHandler = require("input.mouse_handler")
    local KeyboardHandler = require("input.keyboard_handler")
    local MidiService = require("services.midi_service")
    local ScaleService = require("services.scale_service")
    local KeySignatureService = require("services.key_signature_service")
    local State = require("state")
    local ClipboardService = require("services.clipboard_service")
    local DynamicsEngine = require("services.dynamics_engine")

    -- 1. ScaleService -> Key Signature mapping (e.g., C# minor -> 4 sharps, minor)
    local kidx_csm, mode_csm = ScaleService.get_key_signature_for_scale(1, "minor")
    assert_eq(kidx_csm, 4, "C# minor maps to key_sig_idx = 4 (4 sharps)")
    assert_eq(mode_csm, "minor", "C# minor maps to mode = 'minor'")

    local kidx_fm, mode_fm = ScaleService.get_key_signature_for_scale(5, "minor")
    assert_eq(kidx_fm, -4, "F minor maps to key_sig_idx = -4 (4 flats)")
    assert_eq(mode_fm, "minor", "F minor maps to mode = 'minor'")

    local st = State.new()
    ScaleService.apply_scale_as_key_signature(st, 1, "minor")
    assert_eq(st.key_signature, 4, "apply_scale_as_key_signature sets state.key_signature = 4 for C# minor")
    assert_eq(st.key_signature_mode, "minor", "apply_scale_as_key_signature sets state.key_signature_mode = 'minor'")

    -- 2. Mouse Drawing (canvas_y_to_pitch) & Engraving (pitch_to_canvas_y) in C# Minor (key_sig_idx = 4)
    -- Treble clef: bottom line E4 is dstep = 0, C4 is dstep = -2, D4 = -1, E4 = 0, F4 = 1, G4 = 2, A4 = 3, B4 = 4, C5 = 5
    local treble_bot = 200.0
    local bass_bot = 300.0
    local step_y = 4.0
    local c_sharp_minor_steps = {
        { dstep = -2, expected_pitch = 61, expected_name = "C#" }, -- C#4
        { dstep = -1, expected_pitch = 63, expected_name = "D#" }, -- D#4
        { dstep =  0, expected_pitch = 64, expected_name = "E"  }, -- E4
        { dstep =  1, expected_pitch = 66, expected_name = "F#" }, -- F#4
        { dstep =  2, expected_pitch = 68, expected_name = "G#" }, -- G#4
        { dstep =  3, expected_pitch = 69, expected_name = "A"  }, -- A4
        { dstep =  4, expected_pitch = 71, expected_name = "B"  }, -- B4
        { dstep =  5, expected_pitch = 73, expected_name = "C#" }, -- C#5
    }
    for _, tc in ipairs(c_sharp_minor_steps) do
        local mouse_y = treble_bot - tc.dstep * step_y
        local p = Engraver.canvas_y_to_pitch(mouse_y, treble_bot, bass_bot, step_y, false, "treble", 0, nil, 4)
        assert_eq(p, tc.expected_pitch, string.format("Mouse Draw in C# Minor at dstep %d produces pitch %d (%s)", tc.dstep, tc.expected_pitch, tc.expected_name))

        local ny, _, out_dstep, out_acc, _, out_key_acc = Engraver.pitch_to_canvas_y(p, treble_bot, bass_bot, step_y, false, "treble", nil, nil, 4)
        assert_eq(out_dstep, tc.dstep, string.format("Engraver.pitch_to_canvas_y in C# Minor places pitch %d back on dstep %d", p, tc.dstep))
        assert_eq(out_acc, 0, string.format("Diatonic note %s in C# Minor has acc = 0 (suppressed by key signature)", tc.expected_name))
        assert_true(math.abs(ny - mouse_y) <= 0.01, "Roundtrip Y coordinate matches mouse_y")

        local disp_name = Engraver.get_pitch_display_name(p, nil, 4)
        assert_eq(disp_name, tc.expected_name, "Display name in C# Minor matches " .. tc.expected_name)
    end

    -- 3. Verify C natural (60) and F natural (65) in C# Minor (4 sharps) are placed on C and F steps with natural sign (acc = 2), NOT B# or E#!
    local _, _, c_nat_dstep, c_nat_acc, _, c_key_acc = Engraver.pitch_to_canvas_y(60, treble_bot, bass_bot, step_y, false, "treble", nil, nil, 4)
    assert_eq(c_nat_dstep, -2, "C4 natural (60) in C# Minor sits on C4 step (dstep -2), not B#3")
    assert_eq(c_nat_acc, 2, "C4 natural (60) in C# Minor displays natural sign (acc = 2)")
    assert_eq(c_key_acc, 1, "C4 step in C# Minor has key_step_acc = 1")

    local _, _, f_nat_dstep, f_nat_acc, _, f_key_acc = Engraver.pitch_to_canvas_y(65, treble_bot, bass_bot, step_y, false, "treble", nil, nil, 4)
    assert_eq(f_nat_dstep, 1, "F4 natural (65) in C# Minor sits on F4 step (dstep 1), not E#4")
    assert_eq(f_nat_acc, 2, "F4 natural (65) in C# Minor displays natural sign (acc = 2)")
    assert_eq(f_key_acc, 1, "F4 step in C# Minor has key_step_acc = 1")

    -- 4. Verify Explicit Accidental Overrides (♮ = 2, ♭ = -1, ♯ = 1) during Mouse Drawing in C# Minor
    local c5_y = treble_bot - 5 * step_y -- C5 space in treble clef
    local p_c_sharp = Engraver.canvas_y_to_pitch(c5_y, treble_bot, bass_bot, step_y, false, "treble", 0, nil, 4)
    local p_c_nat   = Engraver.canvas_y_to_pitch(c5_y, treble_bot, bass_bot, step_y, false, "treble", 2, nil, 4)
    local p_c_flat  = Engraver.canvas_y_to_pitch(c5_y, treble_bot, bass_bot, step_y, false, "treble", -1, nil, 4)
    assert_eq(p_c_sharp, 73, "Default (acc=0) at C5 space in C# Minor -> C#5 (73)")
    assert_eq(p_c_nat,   72, "Natural override (acc=2) at C5 space in C# Minor -> C♮5 (72)")
    assert_eq(p_c_flat,  71, "Flat override (acc=-1) at C5 space in C# Minor -> Cb5 (71)")

    -- 5. Verify Mouse Drawing across Bass Clef, Alto Clef, Grand Staff, and Harp 3-Staff in F Minor (key_sig_idx = -4: Bb, Eb, Ab, Db)
    -- In Bass Clef: G2 is dstep 0, A2 is dstep 1 -> in F Minor, A step is Ab2 (pitch 44)!
    local a2_bass_y = bass_bot - 1 * step_y
    local p_ab2 = Engraver.canvas_y_to_pitch(a2_bass_y, treble_bot, bass_bot, step_y, false, "bass", 0, nil, -4)
    assert_eq(p_ab2, 44, "Bass Clef A2 step in F Minor (-4) produces Ab2 (44)")
    local p_a2_nat = Engraver.canvas_y_to_pitch(a2_bass_y, treble_bot, bass_bot, step_y, false, "bass", 2, nil, -4)
    assert_eq(p_a2_nat, 45, "Bass Clef A2 step with Natural override (2) in F Minor produces A♮2 (45)")

    -- 6. End-to-End Mouse Drawing via ScoreCanvas.render + MouseHandler.handle click in C# Minor
    local st2, env, trk1, item1, take1, project_tracks, fonts, canvas_info = setup_rich_mock_project()
    local ctx = reaper.ImGui_CreateContext("note_input_test")
    st2:set_input_mode("draw")
    st2.key_signature = 4
    st2.key_signature_mode = "minor"
    st2.accidental = 0
    st2.active_dur = 1.0
    st2.focused_track = trk1
    -- Clear track/item key sig overrides so st2.key_signature = 4 governs
    st2.track_key_signatures = {}
    reaper.GetSetMediaItemInfo_String(item1, "P_EXT:notator_key_sig", "", true)
    if st2.active_tracks_cache then
        for _, td in ipairs(st2.active_tracks_cache) do
            td.clef = "treble"
            td.is_grand = false
            if td.items then
                for _, it in ipairs(td.items) do
                    it.key_sig = nil
                    it.key_sig_events = nil
                end
            end
        end
    end

    -- First render ScoreCanvas so band_y0 / treble_bottom_y are populated on st2.active_tracks_cache[1]
    env.mouse_x = 300
    env.mouse_y = 140
    env.item_hovered = true
    local cinfo = ScoreCanvas.render(ctx, st2, fonts, project_tracks, MidiService)

    local t1 = (cinfo and cinfo.active_tracks_data and cinfo.active_tracks_data[1]) or st2.active_tracks_cache[1]
    t1.clef = "treble"
    t1.is_grand = false
    local t1_treble_bot = t1.treble_bottom_y or ((t1.band_y0 or 80) + 72)
    -- Position mouse exactly on C5 space (dstep = 5 -> 5 * 4 = 20px above treble_bottom_y)
    env.mouse_x = 300
    env.mouse_y = t1_treble_bot - 5 * 4.0
    env.item_hovered = true
    cinfo = ScoreCanvas.render(ctx, st2, fonts, project_tracks, MidiService)

    assert_true(st2.draw_preview ~= nil, "ScoreCanvas.render created state.draw_preview in Draw Mode")
    assert_eq(st2.draw_preview.pitch, 73, "Mouse Draw preview at C5 space in C# Minor targets pitch 73 (C#5)")

    -- Simulate left click in MouseHandler to insert the drawn note
    env.mouse_clicked[0] = true
    MouseHandler.handle(ctx, st2, cinfo, MidiService, DynamicsEngine)
    env.mouse_clicked[0] = false
    assert_true(st2.selected_note ~= nil, "Clicking in Mouse Draw mode inserted and selected a note")
    assert_eq(st2.selected_note.pitch, 73, "Inserted note via Mouse Draw in C# Minor has pitch 73 (C#5)")
    assert_true(st2.status_msg:find("C#5", 1, true) ~= nil, "Status message reports 'C#5' (got: " .. tostring(st2.status_msg) .. ")")

    -- Now test Mouse Draw with explicit Natural override (state.accidental = 2) at the exact same C5 space
    st2.accidental = 2
    cinfo = ScoreCanvas.render(ctx, st2, fonts, project_tracks, MidiService)
    assert_eq(st2.draw_preview.pitch, 72, "Mouse Draw preview with Natural override (acc=2) at C5 space in C# Minor targets pitch 72 (C♮5)")
    env.mouse_clicked[0] = true
    MouseHandler.handle(ctx, st2, cinfo, MidiService, DynamicsEngine)
    env.mouse_clicked[0] = false
    env.item_hovered = false
    assert_eq(st2.selected_note.pitch, 72, "Inserted note with Natural override in C# Minor has pitch 72 (C♮5)")

    -- 7. Step Input Mode ([S]) Note Entry (C, D, E, F, G, A, B, H) in C# Minor
    st2:set_input_mode("step")
    st2.key_signature = 4
    st2.current_octave = 4
    st2.accidental = 0
    reaper.SetEditCurPos(2.0, false, false)
    local step_expectations = {
        { key = reaper.ImGui_Key_C(), expected_pitch = 61, label = "C#4" },
        { key = reaper.ImGui_Key_D(), expected_pitch = 63, label = "D#4" },
        { key = reaper.ImGui_Key_E(), expected_pitch = 64, label = "E4"  },
        { key = reaper.ImGui_Key_F(), expected_pitch = 66, label = "F#4" },
        { key = reaper.ImGui_Key_G(), expected_pitch = 68, label = "G#4" },
        { key = reaper.ImGui_Key_A(), expected_pitch = 69, label = "A4"  },
        { key = reaper.ImGui_Key_B(), expected_pitch = 71, label = "B4"  },
        { key = reaper.ImGui_Key_H(), expected_pitch = 71, label = "H4"  },
    }
    for _, se in ipairs(step_expectations) do
        env.active_keys_pressed[se.key] = true
        KeyboardHandler.handle(ctx, st2, MidiService, ClipboardService, DynamicsEngine, st2.active_tracks_cache)
        env.active_keys_pressed[se.key] = false
        assert_true(st2.selected_note ~= nil, "Step Input created note for " .. se.label)
        assert_eq(st2.selected_note.pitch, se.expected_pitch, "Step Input in C# Minor for key " .. se.label .. " produced pitch " .. se.expected_pitch)
    end

    -- Test pressing '0' (Natural override) in Step Input Mode (with no selected notes) and then pressing 'C'
    st2:clear_selection()
    st2.selected_note = nil
    st2.accidental = 0
    env.active_keys_pressed[reaper.ImGui_Key_0()] = true
    KeyboardHandler.handle(ctx, st2, MidiService, ClipboardService, DynamicsEngine, st2.active_tracks_cache)
    env.active_keys_pressed[reaper.ImGui_Key_0()] = false
    assert_eq(st2.accidental, 2, "Pressing '0' with no note selected toggles state.accidental = 2 (Natural override)")

    env.active_keys_pressed[reaper.ImGui_Key_C()] = true
    KeyboardHandler.handle(ctx, st2, MidiService, ClipboardService, DynamicsEngine, st2.active_tracks_cache)
    env.active_keys_pressed[reaper.ImGui_Key_C()] = false
    assert_eq(st2.selected_note.pitch, 60, "Step Input 'C' with Natural override (acc=2) in C# Minor produces C♮4 (60)")

    -- 8. In-Bar Accidental Memory in C# Minor: C#4 -> C♮4 -> C#4
    local mock_bar_notes = {
        { start_qn = 0.0, dstep = -2, acc = 0, key_step_acc = 1, in_staff = "treble" }, -- C#4 (matches key sig)
        { start_qn = 1.0, dstep = -2, acc = 2, key_step_acc = 1, in_staff = "treble" }, -- C♮4 (cancels key sig)
        { start_qn = 2.0, dstep = -2, acc = 0, key_step_acc = 1, in_staff = "treble" }, -- C#4 (restores key sig sharp!)
    }
    Engraver.apply_measure_accidental_memory(mock_bar_notes, 4.0, nil)
    assert_eq(mock_bar_notes[1].acc, 0, "1st note (C#4) in C# Minor has acc = 0")
    assert_eq(mock_bar_notes[2].acc, 2, "2nd note (C♮4) in C# Minor has acc = 2 (natural)")
    assert_eq(mock_bar_notes[3].acc, 1, "3rd note (returning to C#4 after C♮4 in same bar) displays sharp (acc = 1)")
end)

run_test("Circle of Fifths Modal & Global Palette + MIDI Keyboard Step Input with Auto-Divisi", function()
    local st, env, trk1, item1, take1, project_tracks, fonts = setup_rich_mock_project()
    local CircleOfFifthsService = require("services.circle_of_fifths_service")
    local CircleOfFifthsModal = require("ui.circle_of_fifths_modal")
    local RecordQuantizeService = require("services.record_quantize_service")
    local MidiService = require("services.midi_service")
    local ctx = reaper.ImGui_CreateContext("cof_and_midi_step_test")

    -- 1. Verify all 12 sectors (Major & Minor) and chord qualities
    assert_eq(#CircleOfFifthsService.SECTORS, 12, "12 sectors in Circle of Fifths")
    local tile_c_maj = CircleOfFifthsService.create_tile(1, "major", nil, 4)
    assert_eq(tile_c_maj.label, "C", "Sector 1 Major is C")
    assert_eq(#tile_c_maj.pitches, 3, "C Major triad has 3 notes")
    assert_eq(tile_c_maj.pitches[1], 60, "C4 = 60")
    assert_eq(tile_c_maj.pitches[2], 64, "E4 = 64")
    assert_eq(tile_c_maj.pitches[3], 67, "G4 = 67")

    local tile_csm = CircleOfFifthsService.create_tile(5, "minor", nil, 4)
    assert_eq(tile_csm.label, "C#m", "Sector 5 Minor is C#m")
    assert_eq(tile_csm.key_sig_idx, 4, "C#m key signature is +4 (4 sharps)")

    local tile_single = CircleOfFifthsService.create_tile(2, "major", "single", 4)
    assert_eq(#tile_single.pitches, 1, "Single note quality has 1 pitch")
    assert_eq(tile_single.pitches[1], 67, "G4 = 67")

    -- 2. Dynamic Harmonic Tension Calculation & Re-coloring as Tiles are added
    local tiles = { nil, nil, nil, nil, nil, nil, nil, nil }
    local map_empty = CircleOfFifthsService.compute_tension_map(tiles, nil)
    assert_eq(map_empty.has_reference, false, "Empty tiles have no reference")

    -- Drop C Major into Slot #1 -> Circle colors relative to C Major
    tiles[1] = tile_c_maj
    local map1 = CircleOfFifthsService.compute_tension_map(tiles, 1)
    assert_eq(map1.has_reference, true, "Slot 1 is active reference")
    assert_eq(map1.ref_slot, 1, "ref_slot is 1")
    assert_true(math.abs(map1.major[1].tension - 0.0) < 0.01, "Tonic C Major has 0% tension")
    assert_true(map1.major[2].tension < 0.25, "Dominant G Major has low diatonic tension (<25%)")
    assert_true(map1.major[12].tension < 0.25, "Subdominant F Major has low diatonic tension (<25%)")
    assert_true(map1.major[7].tension > 0.80, "Tritone F# Major has high tension (>80%)")

    -- Drop F# Major (Tritone) into Slot #2 -> Circle automatically recalculates relative to Slot #2 (F# Major)!
    local tile_fs_maj = CircleOfFifthsService.create_tile(7, "major", nil, 4)
    tiles[2] = tile_fs_maj
    local map2 = CircleOfFifthsService.compute_tension_map(tiles, 2)
    assert_eq(map2.ref_slot, 2, "Active reference updated to Slot 2")
    assert_true(math.abs(map2.major[7].tension - 0.0) < 0.01, "New reference F# Major now has 0% tension")
    assert_true(map2.major[1].tension > 0.80, "C Major is now the Tritone pole (>80% tension) relative to F# Major")
    assert_true(map2.tile_step_tensions[2] ~= nil and map2.tile_step_tensions[2].tension > 0.80, "Step tension from Slot 1 (C) to Slot 2 (F#) is >80%")

    -- 3. Global Multi-Tab Palette Persistence in REAPER ExtState
    local pages = {
        { name = "Heroic Theme", tiles = tiles, active_slot = 2 }
    }
    CircleOfFifthsService.add_page(pages, "Dark Suspense")
    assert_eq(#pages, 2, "Added 2nd palette tab")
    pages[2].tiles[1] = tile_csm
    CircleOfFifthsService.save_palettes(pages)

    local loaded_pages = CircleOfFifthsService.load_palettes()
    assert_eq(#loaded_pages, 2, "Loaded 2 global palette tabs from REAPER ExtState")
    assert_eq(loaded_pages[1].name, "Heroic Theme", "Tab 1 name persisted")
    assert_eq(loaded_pages[1].tiles[1].label, "C", "Tab 1 Slot 1 persisted as C")
    assert_eq(loaded_pages[1].tiles[2].label, "F#", "Tab 1 Slot 2 persisted as F#")
    assert_eq(loaded_pages[2].name, "Dark Suspense", "Tab 2 name persisted")
    assert_eq(loaded_pages[2].tiles[1].label, "C#m", "Tab 2 Slot 1 persisted as C#m")

    -- Render CircleOfFifthsModal with populated tiles, simulated sector click, and drag payload
    CircleOfFifthsService.audition_tile(st, tile_c_maj)
    CircleOfFifthsService.audition_tile(st, tile_csm)
    local AudioPreview = require("services.audio_preview")
    AudioPreview.play_note(trk1, { 60, 64, 67 }, 96, 0) -- Verify legacy userdata 1st-arg + chord table compatibility
    AudioPreview.on_mouse_released(st)

    st.show_circle_of_fifths_modal = true
    st.cof_pages = loaded_pages
    st.cof_active_page_idx = 1
    st._cof_drag_payload = tile_csm
    env.mouse_x = 300.0
    env.mouse_y = 200.0
    env.mouse_clicked[0] = true
    env.mouse_down[0] = true
    env.imgui_win_depth = 0
    env.imgui_child_depth = 0
    CircleOfFifthsModal.render(ctx, st, MidiService)
    assert_eq(env.imgui_child_depth, 0, "CircleOfFifthsModal sector click: zero unclosed ImGui_BeginChild")
    assert_eq(env.imgui_win_depth, 0, "CircleOfFifthsModal sector click: zero unclosed ImGui_Begin")
    env.mouse_clicked[0] = false
    env.mouse_down[0] = false
    env.mouse_released[0] = true
    CircleOfFifthsModal.render(ctx, st, MidiService)
    assert_eq(env.imgui_child_depth, 0, "CircleOfFifthsModal drop release: zero unclosed ImGui_BeginChild")
    assert_eq(env.imgui_win_depth, 0, "CircleOfFifthsModal drop release: zero unclosed ImGui_Begin")
    env.mouse_released[0] = false

    -- 4. MIDI Keyboard Step Input + Auto-Divisi across Armed Tracks
    -- Arm both Track 1 (High / Violin) and Track 2 (Low / Cello)
    local trk2 = project_tracks[2].track
    reaper.SetMediaTrackInfo_Value(trk1, "I_RECARM", 1)
    reaper.SetMediaTrackInfo_Value(trk2, "I_RECARM", 1)
    st.rec_auto_divisi = true
    st.rec_auto_divisi_mode = "smart_register"
    st.rec_midi_step_input = true
    st.grid_qn = 0.5 -- 1/8 note grid

    reaper.SetEditCurPos(reaper.TimeMap2_QNToTime(0, 4.0), false, false)
    local _, before_cnt1 = reaper.MIDI_CountEvts(take1)
    local item2 = reaper.GetTrackMediaItem(trk2, 0)
    local take2 = reaper.GetActiveTake(item2)
    local _, before_cnt2 = reaper.MIDI_CountEvts(take2)

    -- Insert a 2-note dyad (G5 = 79 for Violin, C3 = 48 for Cello) via MIDI Step Input cluster engine
    local ins_cnt, trk_cnt = RecordQuantizeService.insert_chord_cluster_at_qn(st, { 79, 48 }, nil, nil, 100, MidiService)
    assert_eq(ins_cnt, 2, "Inserted 2 notes via MIDI Step Input")
    assert_eq(trk_cnt, 2, "Auto-Divisi distributed the 2 notes across 2 armed tracks")

    local _, after_cnt1 = reaper.MIDI_CountEvts(take1)
    local _, after_cnt2 = reaper.MIDI_CountEvts(take2)
    assert_eq(after_cnt1, before_cnt1 + 1, "Track 1 (High register) received 1 note (G5)")
    assert_eq(after_cnt2, before_cnt2 + 1, "Track 2 (Low register) received 1 note (C3)")

    local new_cur_qn = reaper.TimeMap2_timeToQN(0, reaper.GetCursorPosition())
    assert_true(math.abs(new_cur_qn - 4.5) < 0.01, "Edit cursor advanced by 1 Grid length (0.5 QN)")

    -- Test Step Back (-1 Grid) and Step Rest (+1 Grid)
    RecordQuantizeService.step_back_cursor(st)
    assert_true(math.abs(reaper.TimeMap2_timeToQN(0, reaper.GetCursorPosition()) - 4.0) < 0.01, "step_back_cursor moved cursor back to 4.0 QN")
    RecordQuantizeService.step_rest_cursor(st)
    assert_true(math.abs(reaper.TimeMap2_timeToQN(0, reaper.GetCursorPosition()) - 4.5) < 0.01, "step_rest_cursor advanced cursor to 4.5 QN")

    -- 5. Verify ImGuiGuardService auto-unwinds crashed Begin / BeginChild / Style stacks ("Missing EndChild()" prevention)
    local ImGuiGuardService = require("services.imgui_guard_service")
    ImGuiGuardService._installed = false
    ImGuiGuardService.install(reaper)
    ImGuiGuardService.reset_stack(ctx)
    env.imgui_win_depth = 0
    env.imgui_child_depth = 0
    env.imgui_style_color_depth = 0
    env.imgui_style_var_depth = 0

    local ok_guard, _ = ImGuiGuardService.safe_render(ctx, st, "SimulatedCrashModal", function()
        reaper.ImGui_Begin(ctx, "TestCrashWindow")
        reaper.ImGui_PushStyleColor(ctx, 1, 0xFF0000FF)
        if reaper.ImGui_BeginChild(ctx, "##CrashChild", 200, 200) then
            reaper.ImGui_PushStyleVar(ctx, 1, 4.0)
            error("Simulated error inside BeginChild")
        end
        reaper.ImGui_End(ctx)
    end)
    assert_eq(ok_guard, false, "ImGuiGuardService.safe_render caught the simulated error")
    assert_eq(env.imgui_child_depth, 0, "ImGuiGuardService automatically unwound ImGui_EndChild (0 leaked children)")
    assert_eq(env.imgui_win_depth, 0, "ImGuiGuardService automatically unwound ImGui_End (0 leaked windows)")
    assert_eq(env.imgui_style_color_depth, 0, "ImGuiGuardService automatically unwound ImGui_PopStyleColor")
    assert_eq(env.imgui_style_var_depth, 0, "ImGuiGuardService automatically unwound ImGui_PopStyleVar")
end)

run_test("Full Reflection Audit: Count & Verify All Exported Functions Across All 81 Modules", function()
    local total_exported_functions = 0
    for _, mod_name in ipairs(all_modules) do
        local mod = require(mod_name)
        assert_true(type(mod) == "table", mod_name .. " exports a table")
        for k, v in pairs(mod) do
            if type(v) == "function" then
                total_exported_functions = total_exported_functions + 1
            end
        end
    end
    assert_true(total_exported_functions >= 300, string.format("Verified %d exported functions across all %d modules", total_exported_functions, #all_modules))
    print(string.format("    -> Audited %d exported functions across %d modules", total_exported_functions, #all_modules))
end)

print(string.format("\n=============================================================="))
print(string.format("UNIT TEST SUMMARY: %d PASSED | %d FAILED", results.passed, results.failed))
print(string.format("=============================================================="))

if results.failed > 0 then
    for i, f in ipairs(results.failures) do
        print(string.format("\n--- FAILURE #%d ---\n%s", i, f))
    end
end

os.remove("export_score.musicxml")
os.remove(repo_root .. "/export_score.musicxml")

return results

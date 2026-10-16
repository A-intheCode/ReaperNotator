-- @description REAPER-Notator: Native Musical Notation & Engraving Suite
-- @author A-intheCode
-- @version 2.11
-- @changelog
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
    local err_msg = "ReaImGui is required for REAPER Notator to run!\n\n" ..
        "How to install ReaImGui:\n" ..
        "1. Open REAPER: Extensions -> ReaPack -> Browse packages\n" ..
        "2. Search for 'ReaImGui' (by cfillion)\n" ..
        "3. Right-click 'ReaImGui: Dear ImGui for Cockos REAPER' -> Install\n" ..
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
local MidiEditorDrawer     = require("ui.midi_editor_drawer")
local function safe_require(mod_name, fallback)
    local ok, mod = pcall(require, mod_name)
    if ok and mod then return mod end
    return fallback
end

local DivisioVocumModal     = safe_require("ui.divisio_vocum_modal", { render = function() end })
local ExplodeChordsModal    = DivisioVocumModal
local FilterIrregularModal  = safe_require("ui.filter_irregular_modal", { render = function() end })
local RecordModal           = safe_require("ui.record_modal", { render = function() end })
local RecordQuantizeService = safe_require("services.record_quantize_service", {
    on_record_start = function() end,
    process_recording = function() end,
    update_live_recording = function() end
})

-- 4. Initialization of State & Fonts
local state = State.new()
SettingsModal.apply_theme(state)
PathService.cleanup_legacy_artifacts(state)
ShortcutManager.init()
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
KeySignatureService.load(state)
SlurService.load_slurs(state)
PortamentoService.load_portamentos(state)
GlissandoService.load_glissandos(state)
MidiService.cleanup_orphaned_score_elements(state)
state.current_reaproject, state.current_proj_fn = reaper.EnumProjects(-1)
state._last_proj_change_cleanup = reaper.GetProjectStateChangeCount(0)
state._last_total_tracks_cleanup = reaper.CountTracks(0)
PatternService.init()
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
    local cur_proj, proj_fn = reaper.EnumProjects(-1)
    if state.current_reaproject ~= cur_proj or state.current_proj_fn ~= proj_fn then
        state.current_reaproject = cur_proj
        state.current_proj_fn = proj_fn
        MidiService.invalidate_cache()
        state:load_settings()
        SettingsModal.apply_theme(state)
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
        MidiService.cleanup_orphaned_score_elements(state)
        state._last_proj_change_cleanup = reaper.GetProjectStateChangeCount(0)
        state._last_total_tracks_cleanup = reaper.CountTracks(0)
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
    
    -- Locate REAPER Notator's own native OS window handle (HWND) for exact per-monitor rect & DPI calibration
    local function get_notator_hwnd()
        if state._notator_hwnd and reaper.APIExists("JS_Window_IsWindow") and reaper.JS_Window_IsWindow(state._notator_hwnd) then
            return state._notator_hwnd
        end
        local hwnd = nil
        if reaper.APIExists("JS_Window_FindTop") then
            hwnd = reaper.JS_Window_FindTop("REAPER Notator", true)
        end
        if not hwnd and reaper.APIExists("JS_Window_Find") then
            hwnd = reaper.JS_Window_Find("REAPER Notator", true)
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

    -- Measure current monitor work area at the start of the frame (when OS HWND and state.cur_win_* are 100% in sync)
    if not state.is_maximized or (state._maximize_stage or 0) > 0 then
        local svx, svy, svw, svh = get_screen_work_area(cur_x, cur_y, cur_w, cur_h)
        if svx and svw then
            state.screen_work_x = svx
            state.screen_work_y = svy
            state.screen_work_w = svw
            state.screen_work_h = svh
        end
    end
    
    local vx = state.screen_work_x or 0
    local vy = state.screen_work_y or 0
    local vw = state.screen_work_w or 1920
    local vh = state.screen_work_h or 1080
    
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
        -- Enforce responsive minimum size without aspect-ratio constraints
        if reaper.APIExists("ImGui_SetNextWindowSizeConstraints") then
            reaper.ImGui_SetNextWindowSizeConstraints(ctx, min_w, min_h, 16384, 16384)
        end
        
        if state.just_restored or not state._window_pos_initialized or (not state._hwnd_calibrated and get_notator_hwnd() ~= nil) then
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
    
    if reaper.APIExists("ImGui_ConfigVar_WindowsMoveFromTitleBarOnly") and reaper.APIExists("ImGui_SetConfigVar") then
        reaper.ImGui_SetConfigVar(ctx, reaper.ImGui_ConfigVar_WindowsMoveFromTitleBarOnly(), 1)
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
        
        -- Remember current unmaximized window size (for clean restoration)
        if not state.is_maximized and (state._maximize_stage or 0) == 0 then
            if win_w >= 360 and win_h >= 260 and (win_w < (svw - 10) or win_h < (svh - 10)) then
                state.prev_win_w = win_w
                state.prev_win_h = win_h
                state.prev_win_x = win_x
                state.prev_win_y = win_y
            end
        end

        -- Periodically persist unmaximized window position to ExtState when moved or resized and mouse is released
        if not state.is_maximized and (state._maximize_stage or 0) == 0 then
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
        
        -- Double click title bar toggles maximize
        if reaper.ImGui_IsMouseDoubleClicked(ctx, 0) and my >= win_y and my <= (win_y + 26) and mx >= win_x and mx <= (win_x + win_w - 60) then
            state.request_maximize_toggle = true
        end

        -- Continuous synchronization & orphan cleanup upon REAPER project changes (e.g. deleted items/tracks)
        local cur_proj_change = reaper.GetProjectStateChangeCount(0)
        local cur_total_tracks = reaper.CountTracks(0)
        if state._last_proj_change_cleanup ~= cur_proj_change or state._last_total_tracks_cleanup ~= cur_total_tracks then
            state._last_proj_change_cleanup = cur_proj_change
            state._last_total_tracks_cleanup = cur_total_tracks
            MidiService.cleanup_orphaned_score_elements(state)
            state._last_proj_change_cleanup = reaper.GetProjectStateChangeCount(0)
        end

        local project_tracks = MidiService.get_project_midi_tracks()
        
        -- Intercept keyboard shortcuts
        KeyboardHandler.handle(ctx, state, MidiService, ClipboardService, DynamicsEngine, state.active_tracks_cache)
        
        -- Modal dialogs (track selection & help)
        TrackPicker.render(ctx, state, project_tracks)
        HelpModal.render(ctx, state)
        SettingsModal.render(ctx, state, ShortcutManager)
        QuantizeModal.render(ctx, state, MidiService, state.active_tracks_cache)
        BankPickerModal.render(ctx, state, state.focused_track, state.active_tracks_cache)
        ScaleModal.render(ctx, state)
        MusicXmlModal.render(ctx, state, project_tracks)
        DivisioVocumModal.render(ctx, state, MidiService, state.active_tracks_cache)
        FilterIrregularModal.render(ctx, state, MidiService, state.active_tracks_cache)
        RecordModal.render(ctx, state, MidiService, project_tracks, state.active_tracks_cache)
        ArticulationsDrawer.render_last_resort_modal(ctx, state, state.active_tracks_cache)
        
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
        TopBar.render(ctx, state, ClipboardService, MidiService, state.active_tracks_cache, #project_tracks, child_border, topbar_flags)
        
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
        if state.show_dynamics or state.show_tempo or state.show_clefs or state.show_articulations_drawer or state.show_key_signatures or state.show_tools_drawer then
            canvas_w = canvas_w - state.drawer_w - splitter_w - spacing
        end
        if canvas_w < 150 then canvas_w = 150 end
        
        local sidebar_flags = 0
        if reaper.APIExists("ImGui_WindowFlags_NoMove") then
            sidebar_flags = reaper.ImGui_WindowFlags_NoMove()
        end
        
        -- LEFT SIDEBAR: MAIN PALETTE (Resizable via splitter)
        Sidebar.render(ctx, state, MidiService, ClipboardService, state.active_tracks_cache, state.sidebar_w, main_content_h, child_border, sidebar_flags)
        
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
            
            local ok, canvas_info = pcall(ScoreCanvas.render, ctx, state, fonts, project_tracks, MidiService)
            if ok and canvas_info then
                state.active_tracks_cache = canvas_info.active_tracks_data
                local m_ok, m_err = pcall(MouseHandler.handle, ctx, state, canvas_info, MidiService, DynamicsEngine)
                if not m_ok then
                    reaper.ShowConsoleMsg("[ScoreCanvas MouseHandler Error] " .. tostring(m_err) .. "\n")
                end
            elseif not ok then
                reaper.ShowConsoleMsg("[ScoreCanvas Render Error] " .. tostring(canvas_info) .. "\n")
            end
            reaper.ImGui_EndChild(ctx)
        end
        
        -- RIGHT AREA: DYNAMICS, TEMPO, CLEF, KEY SIGNATURE, ARTICULATIONS OR TOOLS DRAWER (Resizable via splitter)
        if state.show_dynamics or state.show_tempo or state.show_clefs or state.show_articulations_drawer or state.show_key_signatures or state.show_tools_drawer then
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
                ToolsDrawer.render(ctx, state, MidiService, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags, fonts.font_music, fonts.font_main)
            elseif state.show_clefs then
                ClefDrawer.render(ctx, state, state.drawer_w, main_content_h, child_border, sidebar_flags, fonts.font_music, fonts.font_main)
            elseif state.show_key_signatures then
                KeySignatureDrawer.render(ctx, state, KeySignatureService, MidiService, state.drawer_w, main_content_h, child_border, sidebar_flags, fonts.font_music, fonts.font_main)
            elseif state.show_tempo then
                TempoDrawer.render(ctx, state, state.drawer_w, main_content_h, child_border, sidebar_flags)
            elseif state.show_dynamics then
                DynamicsDrawer.render(ctx, state, DynamicsEngine, MidiService, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags)
            elseif state.show_articulations_drawer then
                ArticulationsDrawer.render(ctx, state, MidiService, state.active_tracks_cache, state.drawer_w, main_content_h, child_border, sidebar_flags)
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
            
            PatternBrowser.render(ctx, state, MidiService, AudioPreview, main_avail_w, state.pattern_browser_h, project_tracks, fonts.font_music, fonts.font_main)
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

            MidiEditorDrawer.render(ctx, state, MidiService, AudioPreview, DynamicsEngine, main_avail_w, state.midi_editor_h, project_tracks, fonts.font_main)
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
        BottomBar.render(ctx, state, bottom_bar_h, child_border, bottom_flags)
    end
    
    reaper.ImGui_End(ctx)
    
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopStyleColor(ctx, 7)
    
    if state.is_open then
        AudioPreview.update(state, ctx)
        PatternService.update_preview(AudioPreview)
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

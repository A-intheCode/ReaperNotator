-- ==============================================================================
-- REAPER Native Notator - Module: MelodyPathfinderModal
-- Interactive Modal for Key-Note Waypoint Melodic Inpainting,
-- Clef-Aware Instrument Register Bounding, 8 Film Score Archetypes,
-- Melodic Inversion & Counter-Melody Creation, up to 32 Bars,
-- and an interactive 3-Curve Bezier Editor (Tension, Note Length, Pitch)
-- drawn directly over the Melodic Map (Freehand -> Auto-Simplify -> Handles).
-- ==============================================================================

local MelodyStyleCorpus       = require("services.melody_style_corpus")
local MelodyPathfinderService = require("services.melody_pathfinder_service")
local PatternService          = require("services.pattern_service")
local PathService             = require("services.path_service")
local Engraver                = package.loaded["rendering.engraver"] or require("rendering.engraver")

local MelodyPathfinderModal = {}

local CURVE_IDS  = MelodyPathfinderService.CURVE_IDS
local CURVE_META = MelodyPathfinderService.CURVE_META
local SPAN_PRESETS = { 2, 4, 8, 16, 24, 32 }
local NUM_RAM_SLOTS = 4
local GRAPH_PAD = 10

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local function pitch_to_name(p, key_idx)
    if not p then return "-" end
    if Engraver and Engraver.get_pitch_display_name then
        local pname, poct = Engraver.get_pitch_display_name(p, nil, tonumber(key_idx) or 0)
        if pname then
            return string.format("%s%d", tostring(pname), tonumber(poct) or (math.floor(p / 12) - 1))
        end
    end
    local oct = math.floor(p / 12) - 1
    local semi = (p % 12) + 1
    return string.format("%s%d", NOTE_NAMES[semi] or "C", oct)
end

local function clamp01(v)
    v = tonumber(v) or 0
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function with_alpha(col, a)
    return (col & 0xFFFFFF00) | (a & 0xFF)
end

--- Returns the QN span shown on the graph (identical mapping for notes & curves)
local function graph_span(preview)
    local min_qn = (preview and preview.min_qn) or 0
    local max_qn = (preview and preview.max_qn) or (min_qn + 16)
    if max_qn <= min_qn + 0.25 then max_qn = min_qn + 4.0 end
    return min_qn, max_qn, math.max(0.25, max_qn - min_qn)
end

--- Draws a real-time piano-roll / contour map of Reference Notes, Key Waypoints & Generated Melody
local function draw_contour_preview(dl, preview, x, y, w, h)
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x14171EFF, 5.0)
    reaper.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, 0x343B4DFF, 5.0)

    local inner_w = math.max(20, w - 2 * GRAPH_PAD)
    local inner_h = math.max(20, h - 2 * GRAPH_PAD)
    local min_qn, max_qn, span_qn = graph_span(preview)

    -- Measure grid lines (every 4 QN) + bar numbers
    local first_bar_qn = math.ceil(min_qn / 4.0 - 1e-6) * 4.0
    local q = first_bar_qn
    local bar_guard = 0
    local label_every = (span_qn > 64) and 4 or ((span_qn > 32) and 2 or 1)
    while q < max_qn and bar_guard < 160 do
        bar_guard = bar_guard + 1
        local gx = x + GRAPH_PAD + ((q - min_qn) / span_qn) * inner_w
        reaper.ImGui_DrawList_AddLine(dl, gx, y + 2, gx, y + h - 2, 0x2A3040AA, 1.0)
        local bar_no = math.floor(q / 4.0 + 0.5) + 1
        if (bar_no - 1) % label_every == 0 then
            reaper.ImGui_DrawList_AddText(dl, gx + 2, y + 2, 0x4A5268FF, tostring(bar_no))
        end
        q = q + 4.0
    end

    if not preview or not preview.notes or #preview.notes == 0 then
        reaper.ImGui_DrawList_AddText(dl, x + 16, y + h * 0.42, 0x8892B0FF, "No notes to preview.")
        return
    end

    local min_p, max_p = 127, 0
    for _, n in ipairs(preview.notes) do
        if n.pitch < min_p then min_p = n.pitch end
        if n.pitch > max_p then max_p = n.pitch end
    end
    for _, rn in ipairs(preview.ref_notes or {}) do
        if rn.pitch < min_p then min_p = rn.pitch end
        if rn.pitch > max_p then max_p = rn.pitch end
    end
    min_p = math.max(12, min_p - 4)
    max_p = math.min(115, max_p + 4)
    local p_span = math.max(12, max_p - min_p)

    -- 1. Reference Track Harmony Notes (subtle purple bars in background)
    for _, rn in ipairs(preview.ref_notes or {}) do
        local rx0 = x + GRAPH_PAD + math.max(0, (rn.start_qn - min_qn) / span_qn) * inner_w
        local rx1 = x + GRAPH_PAD + math.min(1, (rn.end_qn - min_qn) / span_qn) * inner_w
        local ry  = y + GRAPH_PAD + (1.0 - (rn.pitch - min_p) / p_span) * inner_h
        if rx1 > rx0 + 1 then
            reaper.ImGui_DrawList_AddRectFilled(dl, rx0, ry - 3, rx1, ry + 3, 0x9B59B655, 2.0)
        end
    end

    -- 2. Melodic contour polyline connecting generated notes
    local prev_cx, prev_cy = nil, nil
    for _, gn in ipairs(preview.notes) do
        local nx0 = x + GRAPH_PAD + math.max(0, math.min(1.0, (gn.start_qn - min_qn) / span_qn)) * inner_w
        local nx1 = x + GRAPH_PAD + math.min(1.0, (gn.start_qn + gn.dur_qn - min_qn) / span_qn) * inner_w
        local ny  = y + GRAPH_PAD + (1.0 - (gn.pitch - min_p) / p_span) * inner_h

        if prev_cx and prev_cy then
            reaper.ImGui_DrawList_AddLine(dl, prev_cx, prev_cy, nx0, ny, 0x3498DB66, 1.5)
        end
        prev_cx, prev_cy = nx0, ny

        -- Note pill: Gold for Key Waypoints, Green for generated notes (brightness = velocity)
        local vel_a = math.max(0x70, math.min(0xFF, math.floor(((gn.vel or 90) / 127) * 255)))
        local col_fill = gn.is_waypoint and 0xF39C12FF or with_alpha(0x2ECC7100, vel_a)
        local col_bord = gn.is_waypoint and 0xFFEAA7FF or 0x1ABC9CFF
        local pill_h = gn.is_waypoint and 4.5 or 3.2
        reaper.ImGui_DrawList_AddRectFilled(dl, nx0, ny - pill_h, math.max(nx0 + 4, nx1 - 1), ny + pill_h, col_fill, 2.0)
        reaper.ImGui_DrawList_AddRect(dl, nx0, ny - pill_h, math.max(nx0 + 4, nx1 - 1), ny + pill_h, col_bord, 2.0)
    end

    -- 3. Live Audition Playhead
    local ap = PatternService.active_preview
    if ap and ap.pattern and ap.pattern.id == "__mpf_preview__" then
        local elapsed = math.max(0, reaper.time_precise() - (ap.start_time or 0))
        local total_dur = (ap.total_time and ap.total_time > 0) and ap.total_time or 4.0
        local frac = math.max(0.0, math.min(1.0, elapsed / total_dur))
        local px = x + GRAPH_PAD + frac * inner_w
        reaper.ImGui_DrawList_AddLine(dl, px, y + 2, px, y + h - 2, 0x2ECC71FF, 2.0)
    end
end

--- Draws the 3 Bezier curves (inactive faded, active on top with anchor nodes & tangent handles)
local function draw_curves_overlay(dl, opts, ed, ix, iy, iw, ih)
    local active_id = opts.active_curve or "tension"
    local function to_xy(t, v) return ix + t * iw, iy + (1 - v) * ih end

    local order = {}
    for _, id in ipairs(CURVE_IDS) do
        if id ~= active_id then order[#order + 1] = id end
    end
    order[#order + 1] = active_id

    for _, id in ipairs(order) do
        local curve = opts.curves and opts.curves[id]
        if curve then
            local is_active = (id == active_id)
            local base_col = (CURVE_META[id] and CURVE_META[id].color) or 0xFFFFFFFF
            local col = is_active and base_col or with_alpha(base_col, 0x66)
            local samples = MelodyPathfinderService.sample_curve(curve, 120)
            local px, py = nil, nil
            for _, s in ipairs(samples) do
                local x, y = to_xy(s.t, s.v)
                if px then
                    reaper.ImGui_DrawList_AddLine(dl, px, py, x, y, col, is_active and 2.6 or 1.4)
                end
                px, py = x, y
            end

            if is_active and curve.nodes then
                local show_handles = (opts.curve_tool == "edit")
                for i, nd in ipairs(curve.nodes) do
                    local x, y = to_xy(nd.t, nd.v)
                    if show_handles then
                        if i > 1 and nd.cp1 then
                            local hx, hy = to_xy(nd.t + nd.cp1.dt, nd.v + nd.cp1.dv)
                            reaper.ImGui_DrawList_AddLine(dl, x, y, hx, hy, 0xFFFFFF88, 1.0)
                            reaper.ImGui_DrawList_AddCircleFilled(dl, hx, hy, 3.5, 0xFFFFFFDD)
                            reaper.ImGui_DrawList_AddCircle(dl, hx, hy, 3.5, base_col, 12, 1.2)
                        end
                        if i < #curve.nodes and nd.cp2 then
                            local hx, hy = to_xy(nd.t + nd.cp2.dt, nd.v + nd.cp2.dv)
                            reaper.ImGui_DrawList_AddLine(dl, x, y, hx, hy, 0xFFFFFF88, 1.0)
                            reaper.ImGui_DrawList_AddCircleFilled(dl, hx, hy, 3.5, 0xFFFFFFDD)
                            reaper.ImGui_DrawList_AddCircle(dl, hx, hy, 3.5, base_col, 12, 1.2)
                        end
                    end
                    local is_drag = ed.drag and ed.drag.idx == i and ed.drag.kind == "node"
                    reaper.ImGui_DrawList_AddCircleFilled(dl, x, y, is_drag and 6.0 or 4.8, base_col)
                    reaper.ImGui_DrawList_AddCircle(dl, x, y, is_drag and 6.0 or 4.8, 0x14171EFF, 12, 1.5)
                end
            end
        end
    end

    -- Live freehand stroke while drawing
    if ed.stroke and #ed.stroke >= 2 then
        local col = (CURVE_META[ed.stroke_curve or active_id] or {}).color or 0xFFFFFFFF
        for i = 2, #ed.stroke do
            local x0, y0 = to_xy(ed.stroke[i - 1].t, ed.stroke[i - 1].v)
            local x1, y1 = to_xy(ed.stroke[i].t, ed.stroke[i].v)
            reaper.ImGui_DrawList_AddLine(dl, x0, y0, x1, y1, with_alpha(col, 0xCC), 1.6)
        end
    end

    -- Legend
    local lx = ix + 4
    for _, id in ipairs(CURVE_IDS) do
        local meta = CURVE_META[id]
        local col = (id == active_id) and meta.color or with_alpha(meta.color, 0x88)
        reaper.ImGui_DrawList_AddRectFilled(dl, lx, iy + ih - 9, lx + 9, iy + ih, col, 2.0)
        reaper.ImGui_DrawList_AddText(dl, lx + 12, iy + ih - 12, col, meta.name)
        lx = lx + 18 + #meta.name * 7
    end
end

--- Mouse interaction: freehand draw -> auto-simplify on release, node / handle dragging,
--- double-click insert / remove. Returns true when the curves changed (regenerate).
local function handle_curve_interaction(ctx, state, opts, ix, iy, iw, ih, hovered)
    local ed = state.mpf_curve_edit
    local cid = opts.active_curve or "tension"
    local curve = opts.curves[cid]
    if not curve or not curve.nodes then return false end
    local changed = false

    local mx, my = reaper.ImGui_GetMousePos(ctx)
    mx, my = tonumber(mx) or 0, tonumber(my) or 0
    local function to_tv(x, y) return clamp01((x - ix) / iw), clamp01(1 - (y - iy) / ih) end
    local function to_xy(t, v) return ix + t * iw, iy + (1 - v) * ih end
    local mods = reaper.ImGui_GetKeyMods(ctx) or 0
    local shift = (mods & (reaper.ImGui_Mod_Shift() or 0)) ~= 0
    local alt = (mods & (reaper.ImGui_Mod_Alt() or 0)) ~= 0
    local tool = opts.curve_tool or "draw"

    local function hit_test()
        local nodes = curve.nodes
        if tool == "edit" then
            for i, nd in ipairs(nodes) do
                if i > 1 and nd.cp1 then
                    local hx, hy = to_xy(nd.t + nd.cp1.dt, nd.v + nd.cp1.dv)
                    if (hx - mx) ^ 2 + (hy - my) ^ 2 <= 36 then return "cp1", i end
                end
                if i < #nodes and nd.cp2 then
                    local hx, hy = to_xy(nd.t + nd.cp2.dt, nd.v + nd.cp2.dv)
                    if (hx - mx) ^ 2 + (hy - my) ^ 2 <= 36 then return "cp2", i end
                end
            end
        end
        for i, nd in ipairs(nodes) do
            local x, y = to_xy(nd.t, nd.v)
            if (x - mx) ^ 2 + (y - my) ^ 2 <= 56 then return "node", i end
        end
        return nil, nil
    end

    local clicked = hovered and reaper.ImGui_IsMouseClicked(ctx, 0)
    local dbl = hovered and reaper.ImGui_IsMouseDoubleClicked(ctx, 0)
    local down = reaper.ImGui_IsMouseDown(ctx, 0)
    local released = reaper.ImGui_IsMouseReleased(ctx, 0)

    if dbl then
        -- Double-click: remove an interior node, or insert a new node at the mouse position
        local kind, idx = hit_test()
        local nodes = MelodyPathfinderService.deep_copy(curve.nodes)
        if kind == "node" then
            if idx > 1 and idx < #nodes then table.remove(nodes, idx) end
        else
            local t, v = to_tv(mx, my)
            nodes[#nodes + 1] = { t = t, v = v }
        end
        opts.curves[cid] = MelodyPathfinderService.normalize_curve(nodes)
        ed.stroke, ed.drag = nil, nil
        return true
    end

    if clicked then
        local kind, idx = hit_test()
        if tool == "edit" and not shift and kind then
            ed.drag = { kind = kind, idx = idx }
        elseif tool == "draw" or shift then
            local t, v = to_tv(mx, my)
            ed.stroke = { { t = t, v = v } }
            ed.stroke_curve = cid
            ed.last_mx, ed.last_my = mx, my
        end
    end

    if down and ed.stroke and ed.stroke_curve == cid then
        if math.abs(mx - (ed.last_mx or mx)) + math.abs(my - (ed.last_my or my)) >= 1.5 then
            local t, v = to_tv(mx, my)
            ed.stroke[#ed.stroke + 1] = { t = t, v = v }
            ed.last_mx, ed.last_my = mx, my
        end
    end

    if down and ed.drag then
        local nodes = curve.nodes
        local i = ed.drag.idx
        local nd = nodes[i]
        if nd then
            local t, v = to_tv(mx, my)
            local prev, nxt = nodes[i - 1], nodes[i + 1]
            if ed.drag.kind == "node" then
                if i == 1 then
                    t = 0.0
                elseif i == #nodes then
                    t = 1.0
                else
                    t = math.max(prev.t + 0.01, math.min(nxt.t - 0.01, t))
                end
                nd.t, nd.v = t, v
                -- keep handles inside the neighbouring segments
                if nd.cp1 and prev then nd.cp1.dt = math.max(-(nd.t - prev.t), nd.cp1.dt) end
                if nd.cp2 and nxt then nd.cp2.dt = math.min(nxt.t - nd.t, nd.cp2.dt) end
            elseif ed.drag.kind == "cp1" and prev then
                nd.cp1 = { dt = math.max(-(nd.t - prev.t), math.min(0, t - nd.t)), dv = v - nd.v }
                nd.manual = true
                if not alt and nxt and nd.cp2 then
                    -- smooth (aligned) tangent: mirror direction, keep the opposite handle length
                    local l1 = math.sqrt(nd.cp1.dt ^ 2 + nd.cp1.dv ^ 2)
                    local l2 = math.sqrt(nd.cp2.dt ^ 2 + nd.cp2.dv ^ 2)
                    if l1 > 1e-6 then
                        local s = (l2 > 1e-6 and l2 or l1) / l1
                        nd.cp2 = { dt = math.min(nxt.t - nd.t, -nd.cp1.dt * s), dv = -nd.cp1.dv * s }
                    end
                end
            elseif ed.drag.kind == "cp2" and nxt then
                nd.cp2 = { dt = math.min(nxt.t - nd.t, math.max(0, t - nd.t)), dv = v - nd.v }
                nd.manual = true
                if not alt and prev and nd.cp1 then
                    local l2 = math.sqrt(nd.cp2.dt ^ 2 + nd.cp2.dv ^ 2)
                    local l1 = math.sqrt(nd.cp1.dt ^ 2 + nd.cp1.dv ^ 2)
                    if l2 > 1e-6 then
                        local s = (l1 > 1e-6 and l1 or l2) / l2
                        nd.cp1 = { dt = math.max(-(nd.t - prev.t), -nd.cp2.dt * s), dv = -nd.cp2.dv * s }
                    end
                end
            end
        end
    end

    if released or not down then
        if ed.stroke then
            if #ed.stroke >= 2 and ed.stroke_curve and opts.curves[ed.stroke_curve] then
                opts.curves[ed.stroke_curve] = MelodyPathfinderService.simplify_freehand_to_bezier(
                    ed.stroke, opts.curves[ed.stroke_curve], 0.025, 12
                )
                changed = true
            end
            ed.stroke = nil
        end
        if ed.drag then
            ed.drag = nil
            changed = true
        end
    end

    if hovered and not ed.stroke then
        local kind = hit_test()
        if kind then
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
        end
    end
    return changed
end

local function mark_curves_changed(state, opts)
    opts.curves_custom = true
    state.mpf_dirty = true
end

function MelodyPathfinderModal.render(ctx, state, midi_service, audio_preview, active_tracks_data)
    if not state.show_melody_pathfinder_modal then return end

    -- Initialize persistent options in state (session RAM)
    state.mpf_opts = state.mpf_opts or {
        style_id = "film_style_1",
        scale_id = "auto",
        transform_id = "normal",
        counter_melody_mode = false,
        ref_track_mode = "auto_all",
        harmony_blend = 0.80,
        phrase_bars = 4,
        octave_shift = 0,
        auto_slur = true,
        seed = 1042,
    }
    local opts = state.mpf_opts
    if opts.octave_shift == nil then opts.octave_shift = 0 end
    opts.active_curve = opts.active_curve or "tension"
    opts.curve_tool = opts.curve_tool or "draw"
    opts.phrase_bars = math.max(1, math.min(MelodyPathfinderService.MAX_PHRASE_BARS, math.floor(tonumber(opts.phrase_bars) or 4)))
    local cur_style = MelodyStyleCorpus.BY_ID[opts.style_id] or MelodyStyleCorpus.STYLES[1]
    if type(opts.curves) ~= "table" then
        opts.curves = MelodyPathfinderService.get_style_default_curves(cur_style)
        opts.curves_custom = false
    else
        local ok_struct = true
        for _, id in ipairs(CURVE_IDS) do
            local c = opts.curves[id]
            if type(c) ~= "table" or type(c.nodes) ~= "table" or #c.nodes < 2 then ok_struct = false end
        end
        if not ok_struct then
            opts.curves = MelodyPathfinderService.normalize_curves(opts.curves, cur_style)
        end
    end
    state.mpf_curve_slots = state.mpf_curve_slots or {}
    state.mpf_curve_edit = state.mpf_curve_edit or {}

    local flags = reaper.ImGui_WindowFlags_NoCollapse()
    if reaper.APIExists("ImGui_WindowFlags_TopMost") then
        flags = flags | reaper.ImGui_WindowFlags_TopMost()
    end
    if state.focus_melody_pathfinder_modal then
        if reaper.APIExists("ImGui_SetNextWindowFocus") then
            reaper.ImGui_SetNextWindowFocus(ctx)
        end
        state.focus_melody_pathfinder_modal = nil
        state.mpf_locked_sel_sig = nil
        state.mpf_locked_waypoints = nil
        state.mpf_locked_min_qn = nil
        state.mpf_locked_max_qn = nil
        state.mpf_locked_track = nil
        state.mpf_locked_take = nil
        state.mpf_dirty = true
    end

    reaper.ImGui_SetNextWindowSize(ctx, 720, 840, reaper.ImGui_Cond_FirstUseEver())
    local s_vis, s_open = reaper.ImGui_Begin(ctx, "🧭 Melodic Pathfinder###MelodyPathfinderModal", true, flags)

    if not s_open then
        state.show_melody_pathfinder_modal = false
        state.mpf_locked_sel_sig = nil
        state.mpf_locked_waypoints = nil
        state.mpf_locked_min_qn = nil
        state.mpf_locked_max_qn = nil
        state.mpf_locked_track = nil
        state.mpf_locked_take = nil
        PatternService.stop_preview(audio_preview)
        if audio_preview and audio_preview.restore_all_tracks then
            audio_preview.restore_all_tracks()
        end
    end

    if s_vis then
        local target_track, waypoints, target_take = MelodyPathfinderService.get_selected_waypoints(state, active_tracks_data)
        -- Pre-arm the target track on Virtual MIDI Keyboard while Melodic Pathfinder is open
        -- so the very first note of 'Audition Melody' never gets swallowed by track arming latency!
        if audio_preview and target_track and reaper.ValidatePtr(target_track, "MediaTrack*") then
            if audio_preview.current_track ~= target_track
                or reaper.GetMediaTrackInfo_Value(target_track, "I_RECARM") == 0
                or reaper.GetMediaTrackInfo_Value(target_track, "I_RECINPUT") ~= 6080 then
                audio_preview.prepare_track(target_track)
            end
            audio_preview.last_activity_time = reaper.time_precise()
        end
        local trk_guid = (target_track and reaper.ValidatePtr(target_track, "MediaTrack*") and reaper.GetTrackGUID(target_track)) or ""
        local cur_clef_setting = (state.track_clefs and state.track_clefs[trk_guid]) or "auto"
        local cur_q_bucket = (#waypoints == 0) and math.floor((reaper.GetCursorPosition() or 0) * 4) or 0
        local probe_qn = (waypoints[1] and waypoints[1].start_qn) or reaper.TimeMap2_timeToQN(0, reaper.GetCursorPosition() or 0)
        local eff_kidx, eff_kmode, _, eff_klabel = MelodyPathfinderService.resolve_track_key_signature(
            state, target_track, target_take, probe_qn
        )
        local wp_sig = string.format(
            "%s_%s_%d_%s_%d_%s_%s_%d",
            trk_guid,
            cur_clef_setting,
            eff_kidx or 0,
            eff_kmode or "major",
            #waypoints,
            waypoints[1] and string.format("%.3f_%d", waypoints[1].start_qn, waypoints[1].pitch) or "0",
            waypoints[#waypoints] and string.format("%.3f_%d", waypoints[#waypoints].start_qn, waypoints[#waypoints].pitch) or "0",
            cur_q_bucket
        )
        if state.mpf_last_wp_sig ~= wp_sig then
            state.mpf_last_wp_sig = wp_sig
            state.mpf_dirty = true
            -- Automatically jump Edit Cursor to the start of the selected note pattern
            if #waypoints >= 1 and waypoints[1].start_qn then
                reaper.SetEditCurPos2(0, reaper.TimeMap2_QNToTime(0, waypoints[1].start_qn), false, false)
                state._suppress_autoscroll_frames = 2
            end
        end

        -- Regenerate only when something changed (never while a curve is being dragged / drawn)
        local editing_curve = state.mpf_curve_edit.stroke or state.mpf_curve_edit.drag
        if (state.mpf_dirty or not state.mpf_preview) and not editing_curve then
            state.mpf_preview = MelodyPathfinderService.generate_preview(state, active_tracks_data, opts)
            state.mpf_dirty = false
        end
        local preview = state.mpf_preview
        local clef_reg = (preview and preview.clef_register) or { label = "Treble Clef", min_p = 55, max_p = 86 }
        local active_kidx = (preview and preview.key_idx) or eff_kidx or 0
        local active_klabel = (preview and preview.key_label) or eff_klabel or "C Major"

        -- ==================================================================
        -- 1. HEADER: ACTIVE TRACK, CLEF REGISTER, KEY SIG & WAYPOINT STATUS
        -- ==================================================================
        local trk_name = "Active Track"
        if target_track and reaper.ValidatePtr(target_track, "MediaTrack*") then
            local _, nm = reaper.GetTrackName(target_track)
            local idx = math.floor(reaper.GetMediaTrackInfo_Value(target_track, "IP_TRACKNUMBER"))
            trk_name = (nm and nm ~= "") and string.format("Track %d: %s", idx, nm) or string.format("Track %d", idx)
        end

        reaper.ImGui_TextColored(ctx, 0xF39C12FF, "TARGET STAFF:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextColored(ctx, 0x5DADE2FF, trk_name)
        if target_track and reaper.ValidatePtr(target_track, "MediaTrack*") and reaper.GetMediaTrackInfo_Value(target_track, "I_RECARM") == 1 then
            reaper.ImGui_SameLine(ctx, 0, 8)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xE74C3CF2)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xE74C3CFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xC0392BFF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
            reaper.ImGui_SmallButton(ctx, "● REC##mpf_rec_badge")
            reaper.ImGui_PopStyleColor(ctx, 4)
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Track is temporarily armed on Virtual MIDI Keyboard for instant Melodic Pathfinder auditioning.")
            end
        end
        reaper.ImGui_SameLine(ctx, 0, 10)
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format(
            "𝄞 %s [%s–%s]",
            clef_reg.label or "Clef",
            pitch_to_name(clef_reg.min_p, active_kidx),
            pitch_to_name(clef_reg.max_p, active_kidx)
        ))

        -- Quick Register Octave Shift (-1 / Auto / +1)
        reaper.ImGui_SameLine(ctx, 0, 10)
        if reaper.ImGui_SmallButton(ctx, "-8vb##mpf_oct_dn") then
            opts.octave_shift = math.max(-2, (opts.octave_shift or 0) - 1)
            state.mpf_dirty = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Shift playable Clef register down by 1 octave (-12 semitones)")
        end
        reaper.ImGui_SameLine(ctx, 0, 4)
        local oct_lbl = (opts.octave_shift == 0) and "Clef:0" or string.format("%+d Oct", opts.octave_shift)
        if reaper.ImGui_SmallButton(ctx, oct_lbl .. "##mpf_oct_rst") then
            opts.octave_shift = 0
            state.mpf_dirty = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Reset to automatic Clef & Instrument playable register")
        end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_SmallButton(ctx, "+8va##mpf_oct_up") then
            opts.octave_shift = math.min(2, (opts.octave_shift or 0) + 1)
            state.mpf_dirty = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Shift playable Clef register up by 1 octave (+12 semitones)")
        end

        reaper.ImGui_TextColored(ctx, 0xFFD700FF, string.format("🔑 %s", active_klabel))
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx,
                "Key & Mode used for generation.\n" ..
                "• Explicit Track / Item Key Signature -> honored (mode refined from the music, e.g. Dorian).\n" ..
                "• Default C Major + Scale 'Auto' -> detected automatically from Reference Tracks,\n" ..
                "  Chord Lane, selected Anchor Notes and surrounding notes (Krumhansl-Schmuckler)."
            )
        end
        if preview and preview.harmony_source then
            reaper.ImGui_SameLine(ctx, 0, 12)
            reaper.ImGui_TextColored(ctx, 0x9B59B6FF, string.format("🎼 Harmony: %s", preview.harmony_source))
        end
        if preview and preview.form_summary then
            reaper.ImGui_SameLine(ctx, 0, 12)
            reaper.ImGui_TextColored(ctx, 0x5DADE2FF, string.format("📐 %s", preview.form_summary))
        end

        local bar_start = math.floor(((preview and preview.min_qn) or 0) / 4.0) + 1
        local bar_end   = bar_start + (opts.phrase_bars or 4) - 1

        if #waypoints >= 2 then
            reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format(
                "✓ %d Anchor Notes (Waypoints) selected [%s -> %s] — blending %d musical segment(s) in %s",
                #waypoints,
                pitch_to_name(waypoints[1].pitch, active_kidx),
                pitch_to_name(waypoints[#waypoints].pitch, active_kidx),
                #waypoints - 1,
                active_klabel
            ))
        elseif #waypoints == 1 then
            reaper.ImGui_TextColored(ctx, 0xF1C40FFF, string.format(
                "★ 1 Seed Note selected (%s) — generating %d-Bar %s (Bars %d–%d) in %s (%s)!",
                pitch_to_name(waypoints[1].pitch, active_kidx),
                opts.phrase_bars or 4,
                opts.counter_melody_mode and "Counter-Melody" or "Melodic Phrase",
                bar_start,
                bar_end,
                active_klabel,
                clef_reg.label or "Clef"
            ))
        else
            reaper.ImGui_TextColored(ctx, 0xE67E22FF, string.format(
                "ℹ No notes selected — generating %d-Bar phrase (Bars %d–%d) in %s (%s [%s–%s])",
                opts.phrase_bars or 4,
                bar_start,
                bar_end,
                active_klabel,
                clef_reg.label or "Clef",
                pitch_to_name(clef_reg.min_p, active_kidx),
                pitch_to_name(clef_reg.max_p, active_kidx)
            ))
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 2. COUNTER-MELODY CHECKBOX & PHRASE LENGTH (UP TO 32 BARS)
        -- ==================================================================
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), 0x2ECC71FF)
        local cm_chg, new_cm = reaper.ImGui_Checkbox(
            ctx,
            "🎵 Generate Counter-Melody (Contrapuntal Rhythm & Contrary Motion to Reference Track)",
            opts.counter_melody_mode == true
        )
        reaper.ImGui_PopStyleColor(ctx, 1)
        if cm_chg then
            opts.counter_melody_mode = new_cm
            state.mpf_dirty = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx,
                "When enabled, generates an independent Counter-Melody based on 1 selected Seed Note (or multiple Key Notes).\nUses complementary rhythm (active when Reference Track holds/rests) and contrary motion (3rds/6ths) folded into your track's Clef!"
            )
        end

        if #waypoints < 2 then
            reaper.ImGui_TextColored(ctx, 0x8892B0FF, "Span:")
            for _, b_opt in ipairs(SPAN_PRESETS) do
                reaper.ImGui_SameLine(ctx, 0, 6)
                if reaper.ImGui_RadioButton(ctx, string.format("%d##mpf_b%d", b_opt, b_opt), opts.phrase_bars == b_opt) then
                    opts.phrase_bars = b_opt
                    state.mpf_dirty = true
                end
            end
            reaper.ImGui_SameLine(ctx, 0, 14)
            if reaper.ImGui_SmallButton(ctx, " - ##mpf_bars_dn") then
                opts.phrase_bars = math.max(1, opts.phrase_bars - 1)
                state.mpf_dirty = true
            end
            reaper.ImGui_SameLine(ctx, 0, 4)
            reaper.ImGui_TextColored(ctx, 0xCCD6F6FF, string.format("%d Bars", opts.phrase_bars))
            reaper.ImGui_SameLine(ctx, 0, 4)
            if reaper.ImGui_SmallButton(ctx, " + ##mpf_bars_up") then
                opts.phrase_bars = math.min(MelodyPathfinderService.MAX_PHRASE_BARS, opts.phrase_bars + 1)
                state.mpf_dirty = true
            end
        else
            reaper.ImGui_TextColored(ctx, 0x8892B0FF, "Span: defined by the selected Anchor Notes (first -> last anchor).")
        end

        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 3. FILM SCORE ARCHETYPE & SCALE
        -- ==================================================================
        local col_w = 320
        reaper.ImGui_TextColored(ctx, 0xF39C12FF, "1. Film Score Archetype:")
        reaper.ImGui_SameLine(ctx, col_w + 16)
        reaper.ImGui_TextColored(ctx, 0xF39C12FF, "2. Scale / Mode:")

        reaper.ImGui_SetNextItemWidth(ctx, col_w)
        if reaper.ImGui_BeginCombo(ctx, "##MPFStyleCombo", cur_style.name) then
            for _, st in ipairs(MelodyStyleCorpus.STYLES) do
                local is_sel = (st.id == opts.style_id)
                if reaper.ImGui_Selectable(ctx, st.name, is_sel) then
                    opts.style_id = st.id
                    -- Load the archetype's default 3-curve profile unless the user drew custom curves
                    if not opts.curves_custom then
                        opts.curves = MelodyPathfinderService.get_style_default_curves(st)
                    end
                    state.mpf_dirty = true
                end
                if st.description and reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, st.description)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        reaper.ImGui_SameLine(ctx, col_w + 16)
        local cur_scale_lbl = "Auto"
        for _, sc in ipairs(MelodyPathfinderService.SCALES) do
            if sc.id == opts.scale_id then cur_scale_lbl = sc.name break end
        end
        reaper.ImGui_SetNextItemWidth(ctx, col_w)
        if reaper.ImGui_BeginCombo(ctx, "##MPFScaleCombo", cur_scale_lbl) then
            for _, sc in ipairs(MelodyPathfinderService.SCALES) do
                local is_sel = (sc.id == opts.scale_id)
                if reaper.ImGui_Selectable(ctx, sc.name, is_sel) then
                    opts.scale_id = sc.id
                    state.mpf_dirty = true
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        reaper.ImGui_TextColored(ctx, 0x6E7681FF, string.format(
            "   🧠 %s",
            cur_style.description or string.format("Corpus: %d scores (%d notes)", cur_style.trained_scores or 300, cur_style.trained_notes or 10000)
        ))

        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 4. REFERENCE TRACK & HARMONIC CONSONANCE SLIDER
        -- ==================================================================
        reaper.ImGui_TextColored(ctx, 0x9B59B6FF, "3. Reference Track (Harmony / Key Context):")
        reaper.ImGui_SameLine(ctx, col_w + 16)
        reaper.ImGui_TextColored(ctx, 0x9B59B6FF, "4. Harmonic Consonance Ratio:")

        local ref_entries = {
            { label = "🌐 Auto (All Other Project Tracks)", mode = "auto_all" },
            { label = "🚫 None (Standalone Melody)",        mode = "none" },
        }
        local cur_ref_label = ref_entries[1].label
        if opts.ref_track_mode == "none" then
            cur_ref_label = ref_entries[2].label
        end

        local total_tracks = reaper.CountTracks(0)
        for ti = 0, total_tracks - 1 do
            local tr = reaper.GetTrack(0, ti)
            if tr and reaper.ValidatePtr(tr, "MediaTrack*") and tr ~= target_track then
                local _, tname = reaper.GetTrackName(tr)
                local clean = (tname and #tname > 0) and tname or string.format("Track %d", ti + 1)
                local lbl = string.format("Track %d: %s", ti + 1, clean)
                table.insert(ref_entries, { label = lbl, mode = tr })
                if opts.ref_track_mode == tr then
                    cur_ref_label = lbl
                end
            end
        end

        reaper.ImGui_SetNextItemWidth(ctx, col_w)
        if reaper.ImGui_BeginCombo(ctx, "##MPFRefTrackCombo", cur_ref_label) then
            for idx, re in ipairs(ref_entries) do
                local is_sel = (opts.ref_track_mode == re.mode)
                if reaper.ImGui_Selectable(ctx, re.label .. "##ref_" .. idx, is_sel) then
                    opts.ref_track_mode = re.mode
                    state.mpf_dirty = true
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        reaper.ImGui_SameLine(ctx, col_w + 16)
        reaper.ImGui_SetNextItemWidth(ctx, col_w)
        local harm_pct = math.floor((opts.harmony_blend or 0.8) * 100 + 0.5)
        local h_chg, new_h_pct = reaper.ImGui_SliderInt(ctx, "##MPFHarmonySlider", harm_pct, 0, 100, "%d%% Consonant")
        if h_chg then
            opts.harmony_blend = new_h_pct / 100.0
            state.mpf_dirty = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx,
                "Controls how strongly the melody locks to the Reference Track / Chord Lane harmony:\n• 80-100%: Chord tones on strong beats, consonant 3rds, 6ths & 5ths\n• 50%: Balanced counterpoint with expressive passing tensions\n• 0-25%: Dark dissonance (minor 2nds, tritones, thriller friction)"
            )
        end

        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 5. INVERSION / CONTOUR TRANSFORM & SLUR
        -- ==================================================================
        reaper.ImGui_TextColored(ctx, 0x5DADE2FF, "5. Melodic Inversion & Contour:")

        local cur_tf_name = "Normal (Original Contour)"
        for _, tf in ipairs(MelodyPathfinderService.TRANSFORMS) do
            if tf.id == opts.transform_id then cur_tf_name = tf.name break end
        end
        reaper.ImGui_SetNextItemWidth(ctx, col_w - 115)
        if reaper.ImGui_BeginCombo(ctx, "##MPFTransformCombo", cur_tf_name) then
            for _, tf in ipairs(MelodyPathfinderService.TRANSFORMS) do
                local is_sel = (tf.id == opts.transform_id)
                if reaper.ImGui_Selectable(ctx, tf.name, is_sel) then
                    opts.transform_id = tf.id
                    state.mpf_dirty = true
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        reaper.ImGui_SameLine(ctx, 0, 6)
        if reaper.ImGui_Button(ctx, "⇅ Invert Sel.", 108, 22) then
            local _, msg = MelodyPathfinderService.invert_selected_notes_in_place(state, active_tracks_data, opts.scale_id)
            state.status_msg = msg
            state.mpf_dirty = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Directly invert the currently selected notes in the score around the first note (diatonic mirror inside Clef register).")
        end

        reaper.ImGui_SameLine(ctx, col_w + 16)
        local sl_chg, new_sl = reaper.ImGui_Checkbox(ctx, "⌒ Add Phrase Slur automatically", opts.auto_slur == true)
        if sl_chg then opts.auto_slur = new_sl end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 6. 3-CURVE BEZIER EDITOR TOOLBAR (Tension, Note Length, Pitch)
        -- ==================================================================
        reaper.ImGui_TextColored(ctx, 0xCCD6F6FF, "6. Shape Curves:")
        for _, id in ipairs(CURVE_IDS) do
            local meta = CURVE_META[id]
            reaper.ImGui_SameLine(ctx, 0, 8)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), meta.color)
            if reaper.ImGui_RadioButton(ctx, meta.name .. "##mpf_curve_" .. id, opts.active_curve == id) then
                opts.active_curve = id
                state.mpf_curve_edit.stroke, state.mpf_curve_edit.drag = nil, nil
            end
            reaper.ImGui_PopStyleColor(ctx, 1)
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, meta.hint)
            end
        end
        reaper.ImGui_SameLine(ctx, 0, 16)
        if reaper.ImGui_RadioButton(ctx, "✏ Draw##mpf_tool_draw", opts.curve_tool == "draw") then
            opts.curve_tool = "draw"
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Draw freehand over the graph. On mouse release the stroke is simplified\ninto Bezier anchor nodes (only the drawn time range is replaced).")
        end
        reaper.ImGui_SameLine(ctx, 0, 6)
        if reaper.ImGui_RadioButton(ctx, "✋ Edit Handles##mpf_tool_edit", opts.curve_tool == "edit") then
            opts.curve_tool = "edit"
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Drag anchor nodes and Bezier tangent handles.\nAlt+Drag a handle = break tangent (corner).\nShift+Drag = freehand draw.\nDouble-click = add node / remove node.")
        end

        -- Quick shapes, style reset, RAM slots, JSON
        reaper.ImGui_SetNextItemWidth(ctx, 150)
        if reaper.ImGui_BeginCombo(ctx, "##MPFShapeCombo", "Shape: " .. (CURVE_META[opts.active_curve] or {}).name) then
            for _, sh in ipairs(MelodyPathfinderService.CURVE_SHAPES) do
                if reaper.ImGui_Selectable(ctx, sh.name .. "##shape_" .. sh.id, false) then
                    opts.curves[opts.active_curve] = MelodyPathfinderService.make_shape_curve(sh.id)
                    mark_curves_changed(state, opts)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        reaper.ImGui_SameLine(ctx, 0, 6)
        if reaper.ImGui_Button(ctx, "↺ Style Curves##mpf_curve_reset") then
            opts.curves = MelodyPathfinderService.get_style_default_curves(cur_style)
            opts.curves_custom = false
            state.mpf_dirty = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Reset all 3 curves to the default profile of the selected Film Score Archetype.")
        end

        reaper.ImGui_SameLine(ctx, 0, 12)
        reaper.ImGui_TextColored(ctx, 0x8892B0FF, "RAM:")
        local mods = reaper.ImGui_GetKeyMods(ctx) or 0
        local shift_held = (mods & (reaper.ImGui_Mod_Shift() or 0)) ~= 0
        for si = 1, NUM_RAM_SLOTS do
            reaper.ImGui_SameLine(ctx, 0, 4)
            local filled = state.mpf_curve_slots[si] ~= nil
            local lbl = string.format("%s%d##mpf_slot_%d", filled and "●" or "○", si, si)
            if reaper.ImGui_SmallButton(ctx, lbl) then
                if shift_held or not filled then
                    state.mpf_curve_slots[si] = MelodyPathfinderService.deep_copy(opts.curves)
                    state.status_msg = string.format("Melodic Pathfinder: curves stored in RAM slot %d.", si)
                else
                    opts.curves = MelodyPathfinderService.normalize_curves(
                        MelodyPathfinderService.deep_copy(state.mpf_curve_slots[si]), cur_style
                    )
                    mark_curves_changed(state, opts)
                    state.status_msg = string.format("Melodic Pathfinder: curves loaded from RAM slot %d.", si)
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, filled
                    and string.format("Slot %d: Click = load curves, Shift+Click = overwrite with current curves.", si)
                    or string.format("Slot %d (empty): Click = store current curves (kept for this session).", si))
            end
        end

        reaper.ImGui_SameLine(ctx, 0, 12)
        if reaper.ImGui_SmallButton(ctx, "💾 Export .json##mpf_curve_export") then
            local default_path = string.format("%s/melodic_pathfinder_curves.json", (reaper.GetProjectPath and reaper.GetProjectPath("")) or "")
            local path = PathService.browse_for_save_file(default_path, "Export Melodic Pathfinder Curves", "json")
            if path and path ~= "" then
                local ok, res = MelodyPathfinderService.export_curves_json(opts.curves, path, { style_id = opts.style_id, name = cur_style.name })
                state.status_msg = ok and ("Melodic Pathfinder: curves exported to " .. tostring(res)) or tostring(res)
            end
        end
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_SmallButton(ctx, "📂 Import .json##mpf_curve_import") then
            local ok, path = reaper.GetUserFileNameForRead("", "Import Melodic Pathfinder Curves", "json")
            if ok and ok ~= 0 and type(path) == "string" and path ~= "" then
                local curves, err = MelodyPathfinderService.import_curves_json(path, cur_style)
                if curves then
                    opts.curves = curves
                    mark_curves_changed(state, opts)
                    state.status_msg = "Melodic Pathfinder: curves imported from " .. path
                else
                    state.status_msg = "Melodic Pathfinder: " .. tostring(err)
                end
            end
        end

        -- ==================================================================
        -- 7. LIVE MELODIC MAP + INTERACTIVE CURVE CANVAS
        -- ==================================================================
        local ref_cnt = (preview and preview.ref_notes and #preview.ref_notes) or 0
        local gen_cnt = (preview and preview.notes and #preview.notes) or 0
        reaper.ImGui_TextColored(ctx, 0x8892B0FF, string.format(
            "🟠 Anchors   🟢 Generated (%d, brightness = velocity)   🟣 Reference (%d)   —   %s",
            gen_cnt, ref_cnt,
            (opts.curve_tool == "edit") and "drag nodes/handles, double-click add/remove" or "draw over the graph to shape the active curve"
        ))

        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        avail_w = math.max(200, tonumber(avail_w) or 600)
        local map_h = 220
        local cx, cy = reaper.ImGui_GetCursorScreenPos(ctx)
        cx, cy = tonumber(cx) or 0, tonumber(cy) or 0
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        draw_contour_preview(dl, preview, cx, cy, avail_w, map_h)

        local ix, iy = cx + GRAPH_PAD, cy + GRAPH_PAD
        local iw, ih = math.max(20, avail_w - 2 * GRAPH_PAD), math.max(20, map_h - 2 * GRAPH_PAD)

        -- Invisible canvas button captures the mouse so dragging never moves the window
        reaper.ImGui_InvisibleButton(ctx, "##mpf_curve_canvas", avail_w, map_h)
        local canvas_hovered = reaper.ImGui_IsItemHovered(ctx)
        if handle_curve_interaction(ctx, state, opts, ix, iy, iw, ih, canvas_hovered) then
            mark_curves_changed(state, opts)
        end
        draw_curves_overlay(dl, opts, state.mpf_curve_edit, ix, iy, iw, ih)

        -- Hover read-out: bar + coupled curve values at the mouse position
        if canvas_hovered and not state.mpf_curve_edit.stroke and not state.mpf_curve_edit.drag then
            local mx = tonumber((reaper.ImGui_GetMousePos(ctx))) or ix
            local t = clamp01((mx - ix) / iw)
            local cv = MelodyPathfinderService.evaluate_coupled_curves(opts.curves, t)
            local g_min, _, g_span = graph_span(preview)
            local bar_no = math.floor((g_min + t * g_span) / 4.0) + 1
            reaper.ImGui_SetTooltip(ctx, string.format(
                "Bar %d\nTension %d%% -> Velocity %d\nNote Length %d%%\nPitch %d%%%s",
                bar_no,
                math.floor(cv.raw_tension * 100 + 0.5), cv.velocity,
                math.floor(cv.raw_note_length * 100 + 0.5),
                math.floor(cv.pitch * 100 + 0.5),
                (cv.climax_deg > 0) and string.format("\nClimax pull +%d degrees", cv.climax_deg) or ""
            ))
        end
        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 8. ACTION BAR: REROLL VARIATION, AUDIO PREVIEW & APPLY
        -- ==================================================================
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- Button 1: Reroll Seed / New Variation
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x8E44ADFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x9B59B6FF)
        if reaper.ImGui_Button(ctx, "🎲 New Variation (Seed #" .. tostring(opts.seed) .. ")", 195, 30) then
            opts.seed = opts.seed + 37
            state.mpf_dirty = true
        end
        reaper.ImGui_PopStyleColor(ctx, 2)

        reaper.ImGui_SameLine(ctx, 0, 10)

        -- Button 2: Audio Audition Preview
        local is_playing = (PatternService.active_preview and PatternService.active_preview.pattern and PatternService.active_preview.pattern.id == "__mpf_preview__")
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), is_playing and 0xE74C3CFF or 0x2980B9FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), is_playing and 0xC0392BFF or 0x3498DBFF)
        if reaper.ImGui_Button(ctx, is_playing and "■ Stop Audition" or "▶ Audition Melody", 150, 30) then
            if is_playing then
                PatternService.stop_preview(audio_preview)
            elseif preview and preview.notes and #preview.notes > 0 and target_track then
                local q0 = preview.notes[1].start_qn
                local rel_notes = {}
                for _, n in ipairs(preview.notes) do
                    table.insert(rel_notes, {
                        pitch = n.pitch,
                        start_qn = math.max(0, n.start_qn - q0),
                        dur_qn = n.dur_qn,
                        vel = n.vel,
                        chan = n.chan or 0,
                    })
                end
                local _, _, bpm = reaper.TimeMap_GetTimeSigAtTime(0, reaper.GetCursorPosition())
                local temp_pat = {
                    id = "__mpf_preview__",
                    name = "Melodic Pathfinder Preview",
                    bars = math.max(1, math.ceil(((preview.max_qn or 16) - q0) / 4.0)),
                    time_sig = { num = 4, denom = 4 },
                    tempo_hint = (bpm and bpm > 0) and bpm or 120,
                    notes = rel_notes,
                }
                PatternService.start_preview(temp_pat, target_track, audio_preview)
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 2)

        reaper.ImGui_SameLine(ctx, 0, 10)

        -- Button 3: Apply / Insert into Score
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
        local apply_lbl = opts.counter_melody_mode and "✓ Insert Counter-Melody" or "✓ Fill Melodic Path"
        if reaper.ImGui_Button(ctx, apply_lbl, 165, 30) then
            PatternService.stop_preview(audio_preview)
            local _, msg = MelodyPathfinderService.apply_to_score(state, midi_service, preview, opts)
            state.status_msg = msg
        end
        reaper.ImGui_PopStyleColor(ctx, 2)

        reaper.ImGui_SameLine(ctx, 0, 10)
        if reaper.ImGui_Button(ctx, "Close", 65, 30) then
            PatternService.stop_preview(audio_preview)
            if audio_preview and audio_preview.restore_all_tracks then
                audio_preview.restore_all_tracks()
            end
            state.show_melody_pathfinder_modal = false
        end
    end

    reaper.ImGui_End(ctx)
end

return MelodyPathfinderModal

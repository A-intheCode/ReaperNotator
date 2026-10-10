-- ==============================================================================
-- REAPER Native Notator - UI: MidiEditorDrawer
-- Collapsible bottom drawer: MIDI Velocity & CC Lanes Graph View for active MIDI Item
-- Displays:
-- 1. Velocity Lane with REAPER-style velocity stalks (halved 3.0px width) & flag handles ("Fähnchen")
-- 2. Full 128 MIDI CC Controller Lanes (CC 0 - 127) with continuous curve rendering & freehand draw
-- 3. Dynamic CC Shaping Protection: Automatic lock & gray-out for CC A/B (CC 1 & 11 by default)
--    unless "Bypass Dynamic CC Shaping" is enabled, protecting automated curves from accidental overwrites.
-- 4. REAPER CC Shape Synchronization: Curves drawn with Shape 1 (Linear Ramp) default,
--    eliminating square steps ("Stufen") in REAPER's native MIDI editor.
-- 5. Customizable Themes & Colors: Fully connected to Constants.COLORS and SettingsModal.
-- ==============================================================================

local Constants = require("constants")
local MidiNote = require("classes.note")

local MidiEditorDrawer = {}

-- Local interaction state for Velocity
local is_dragging_velocity = false
local drag_lead_note = nil
local drag_initial_vel = 96
local drag_snapshots = {} -- [note_key] = { note = n, orig_vel = n.vel }
local is_drawing_vel = false
local draw_prev_mx = nil
local draw_prev_my = nil
local draw_trail = {}
local marquee_active = false
local marquee_start_x = 0
local marquee_start_y = 0
local last_audition_time = 0
local last_audition_vel = -1

-- Local interaction state for CC Lanes
local is_dragging_cc_nodes = false
local cc_drag_lead_event = nil
local cc_drag_start_x = 0
local cc_drag_start_y = 0
local cc_drag_start_qn = 0
local cc_drag_start_val = 0
local cc_drag_snapshots = {} -- list of { idx, orig_qn, orig_val, orig_ppq, chan, shape, ev }
local cc_marquee_active = false
local cc_marquee_start_x = 0
local cc_marquee_start_y = 0
local is_drawing_cc = false
local cc_draw_stroke = {}
local hovered_cc_node = nil


--- Standard MIDI CC Descriptions
local CC_NAMES = {
    [0] = "Bank Select MSB",
    [1] = "Modulation Wheel",
    [2] = "Breath Controller",
    [4] = "Foot Controller",
    [5] = "Portamento Time",
    [7] = "Channel Volume",
    [8] = "Balance",
    [10] = "Pan",
    [11] = "Expression Controller",
    [32] = "Bank Select LSB",
    [64] = "Sustain Pedal",
    [65] = "Portamento On/Off",
    [66] = "Sostenuto",
    [67] = "Soft Pedal",
    [68] = "Legato Footswitch",
    [71] = "Resonance / Timbre",
    [72] = "Release Time",
    [73] = "Attack Time",
    [74] = "Brightness / Cutoff",
    [84] = "Portamento Control",
    [91] = "Reverb Send Level",
    [93] = "Chorus Send Level",
    [120] = "All Sound Off",
    [121] = "Reset All Controllers",
    [123] = "All Notes Off"
}

local SHAPE_LABELS = {
    [0] = "⎍ Square (Step)",
    [1] = "📈 Linear (Ramp)",
    [2] = "〰 Slow start/end",
    [3] = "⚡ Fast start",
    [4] = "⏳ Fast end",
    [5] = "∿ Bézier"
}

--- Converts a MIDI pitch (0-127) to a standard pitch name (e.g. 60 -> "C4")
local function pitch_to_name(pitch)
    if not pitch then return "C4" end
    local names = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
    local oct = math.floor(pitch / 12) - 1
    local deg = (pitch % 12) + 1
    return string.format("%s%d", names[deg] or "C", oct)
end

--- Formats project quarter note into Measure.Beat.Fraction
local function format_qn_time(qn)
    local q = qn or 0
    local bpi = 4.0 -- Default 4/4
    local time_pos = reaper.TimeMap2_QNToTime(0, q)
    local num, den = reaper.TimeMap_GetTimeSigAtTime(0, time_pos)
    if num and num > 0 and den and den > 0 then
        bpi = num * (4.0 / den)
    end
    local m = math.floor(q / bpi) + 1
    local rem = q % bpi
    local beat = math.floor(rem) + 1
    local frac = math.floor((rem - math.floor(rem)) * 100)
    return string.format("%d.%d.%02d", m, beat, frac)
end

--- Renders an authentic, crisp vector pen/pencil cursor for the MIDI Editor draw tool
--- Hotspot is precisely at (mx, my) pointing diagonally down-left at 45 degrees
local function draw_pen_cursor(drawlist, mx, my, is_active)
    if not drawlist or not mx or not my then return end

    -- 1. Sharp Graphite Tip (Triangle pointing at mx, my)
    reaper.ImGui_DrawList_AddTriangleFilled(drawlist, mx, my, mx + 2.5, my - 4.5, mx + 4.5, my - 2.5, 0x2D3748FF)

    -- 2. Wood Sharpening Cone (Natural warm cedar quad)
    reaper.ImGui_DrawList_AddQuadFilled(drawlist, mx + 2.5, my - 4.5, mx + 5.5, my - 8.5, mx + 8.5, my - 5.5, mx + 4.5, my - 2.5, 0xD4A373FF)
    reaper.ImGui_DrawList_AddLine(drawlist, mx + 3.5, my - 3.5, mx + 7.0, my - 7.0, 0xB0896888, 1.0)

    -- 3. Hexagonal Pencil Barrel (Two-tone facet shading for 3D body)
    -- Lit top facet
    local col_facet1 = is_active and 0x00F5D4FF or 0xFBBF24FF
    reaper.ImGui_DrawList_AddQuadFilled(drawlist, mx + 5.5, my - 8.5, mx + 13.5, my - 16.5, mx + 15.0, my - 15.0, mx + 7.0, my - 7.0, col_facet1)
    -- Shaded lower facet
    local col_facet2 = is_active and 0x00BDA3FF or 0xD97706FF
    reaper.ImGui_DrawList_AddQuadFilled(drawlist, mx + 7.0, my - 7.0, mx + 15.0, my - 15.0, mx + 16.5, my - 13.5, mx + 8.5, my - 5.5, col_facet2)

    -- 4. Metal Ferrule (Brushed silver collar)
    reaper.ImGui_DrawList_AddQuadFilled(drawlist, mx + 13.5, my - 16.5, mx + 16.5, my - 19.5, mx + 19.5, my - 16.5, mx + 16.5, my - 13.5, 0x94A3B8FF)
    reaper.ImGui_DrawList_AddLine(drawlist, mx + 15.0, my - 18.0, mx + 18.0, my - 15.0, 0xE2E8F0FF, 1.0)

    -- 5. Pink Rubber Eraser Cap
    reaper.ImGui_DrawList_AddQuadFilled(drawlist, mx + 16.5, my - 19.5, mx + 19.0, my - 22.0, mx + 22.0, my - 19.0, mx + 19.5, my - 16.5, 0xFB7185FF)
    reaper.ImGui_DrawList_AddCircleFilled(drawlist, mx + 20.5, my - 20.5, 2.2, 0xFB7185FF)

    -- 6. Crisp Dark Outline (Ensures high contrast on any background/grid)
    local out_col = 0x0F172AFF
    reaper.ImGui_DrawList_AddLine(drawlist, mx, my, mx + 5.5, my - 8.5, out_col, 1.2)
    reaper.ImGui_DrawList_AddLine(drawlist, mx + 5.5, my - 8.5, mx + 16.5, my - 19.5, out_col, 1.2)
    reaper.ImGui_DrawList_AddLine(drawlist, mx + 16.5, my - 19.5, mx + 20.5, my - 22.5, out_col, 1.2)
    reaper.ImGui_DrawList_AddLine(drawlist, mx + 20.5, my - 22.5, mx + 22.5, my - 20.5, out_col, 1.2)
    reaper.ImGui_DrawList_AddLine(drawlist, mx + 22.5, my - 20.5, mx + 19.5, my - 16.5, out_col, 1.2)
    reaper.ImGui_DrawList_AddLine(drawlist, mx + 19.5, my - 16.5, mx + 8.5, my - 5.5, out_col, 1.2)
    reaper.ImGui_DrawList_AddLine(drawlist, mx + 8.5, my - 5.5, mx, my, out_col, 1.2)

    -- 7. Active Drawing Ink Indicator / Precision Hotspot
    if is_active then
        reaper.ImGui_DrawList_AddCircleFilled(drawlist, mx, my, 2.5, 0x00F5D4FF)
        reaper.ImGui_DrawList_AddCircle(drawlist, mx, my, 4.0, 0x00F5D466, 0, 1.0)
    else
        reaper.ImGui_DrawList_AddCircleFilled(drawlist, mx, my, 1.2, 0xFFFFFFFF)
    end
end

--- Main render function for the MIDI Editor bottom drawer

--- Accepts flexible signature allowing dynamics_engine injection
function MidiEditorDrawer.render(ctx, state, midi_service, audio_preview, arg5, arg6, arg7, arg8, arg9)
    if not state.show_midi_editor then return end

    local dynamics_engine, width, height, project_tracks, font_main
    if type(arg5) == "table" and (arg5.get_item_bypass_cc or arg5.load_item_modulators) then
        dynamics_engine = arg5
        width = arg6
        height = arg7
        project_tracks = arg8
        font_main = arg9
    else
        dynamics_engine = require("modules.services.dynamics_engine")
        width = arg5
        height = arg6
        project_tracks = arg7
        font_main = arg8
    end

    local child_border = reaper.APIExists("ImGui_ChildFlags_Borders") and reaper.ImGui_ChildFlags_Borders() or 1
    local child_none = reaper.APIExists("ImGui_ChildFlags_None") and reaper.ImGui_ChildFlags_None() or 0

    local pane_flags = reaper.ImGui_WindowFlags_NoScrollbar()
    if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
        pane_flags = pane_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    end

    -- Theme colors from Constants.COLORS (customizable in Settings -> MIDI Editor Colors)
    local col_bg          = (Constants.COLORS and Constants.COLORS.midi_bg) or 0x181A20FF
    local col_lane_bg     = (Constants.COLORS and Constants.COLORS.midi_lane_bg) or 0x121418FF
    local col_grid_maj    = (Constants.COLORS and Constants.COLORS.midi_grid_major) or 0x4A556866
    local col_grid_min    = (Constants.COLORS and Constants.COLORS.midi_grid_minor) or 0x33415525
    local col_vel_stalk   = (Constants.COLORS and Constants.COLORS.midi_vel_stalk) or 0x64748BAA
    local col_vel_flag    = (Constants.COLORS and Constants.COLORS.midi_vel_flag) or 0x94A3B8FF
    local col_vel_sel     = (Constants.COLORS and Constants.COLORS.midi_vel_sel) or 0xFF9F1CFF
    local col_vel_hov     = (Constants.COLORS and Constants.COLORS.midi_vel_hov) or 0x38BDF8FF
    local col_cc_line     = (Constants.COLORS and Constants.COLORS.midi_cc_line) or 0x38BDF8FF
    local col_cc_fill     = (Constants.COLORS and Constants.COLORS.midi_cc_fill) or 0x38BDF828
    local col_cc_node     = (Constants.COLORS and Constants.COLORS.midi_cc_node) or 0x7DD3FCFF
    local col_cc_locked   = (Constants.COLORS and Constants.COLORS.midi_cc_locked) or 0x64748BCC

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), col_bg)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x383D4CFF)

    if reaper.ImGui_BeginChild(ctx, "MidiEditorMainPane", width, height, child_border, pane_flags) then
        -- Find active MIDI Item and Take
        local active_item, active_take, active_track = midi_service.get_active_midi_item_and_take(state)

        -- Load dynamic shaping settings for current item/track (cached)
        if active_item and dynamics_engine and dynamics_engine.load_item_modulators then
            if state._last_loaded_dyn_mod_item ~= active_item or state._dyn_mod_dirty then
                dynamics_engine.load_item_modulators(active_item, state)
                state._last_loaded_dyn_mod_item = active_item
                state._dyn_mod_dirty = nil
            end
        end

        local is_bypassed = false
        if active_item and dynamics_engine and dynamics_engine.get_item_bypass_cc then
            is_bypassed = dynamics_engine.get_item_bypass_cc(active_item, state)
        else
            is_bypassed = (state.dyn_bypass_cc == true)
        end

        local dyn_a = math.floor(state.dyn_cc_a or 1)
        local dyn_b = math.floor(state.dyn_cc_b or 11)

        -- Current lane selection ("velocity" or integer 0..127)
        local cur_lane = state.midi_editor_lane or "velocity"
        local is_vel_lane = (cur_lane == "velocity")
        local cur_cc_num = tonumber(cur_lane) or 1
        local is_dyn_cc = (not is_vel_lane) and (cur_cc_num == dyn_a or cur_cc_num == dyn_b)
        local is_locked = (not is_vel_lane) and (not is_bypassed) and is_dyn_cc

        -- Reset CC selection if lane or take changed
        if state.midi_editor_last_cc_lane ~= cur_cc_num or state.midi_editor_last_take ~= active_take then
            state.midi_editor_last_cc_lane = cur_cc_num
            state.midi_editor_last_take = active_take
            state.selected_cc_indices = {}
        end


        -- ======================================================================
        -- 1. HEADER / TOOLBAR
        -- ======================================================================
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 2)

        -- Title & Icon
        reaper.ImGui_TextColored(ctx, 0x8E44ADFF, "🎹 MIDI EDITOR")
        reaper.ImGui_SameLine(ctx, 0, 6)
        if is_vel_lane then
            reaper.ImGui_TextColored(ctx, 0x8892B0FF, "| Velocity")
        else
            local cname = CC_NAMES[cur_cc_num] and (" | " .. CC_NAMES[cur_cc_num]) or ""
            reaper.ImGui_TextColored(ctx, 0x8892B0FF, string.format("| CC %d%s", cur_cc_num, cname))
        end

        -- Target Take / Track Badge
        reaper.ImGui_SameLine(ctx, 0, 10)
        local notes = {}
        local take_name = "Take 1"
        if active_take and reaper.ValidatePtr(active_take, "MediaItem_Take*") then
            if is_vel_lane then
                notes = midi_service.get_take_notes_for_editor(active_take, active_item, active_track)
            end
            local track_name = "Track"
            local track_col = 0x3498DBFF
            if active_track and reaper.ValidatePtr(active_track, "MediaTrack*") then
                local _, tname = reaper.GetTrackName(active_track)
                local tidx = math.floor(reaper.GetMediaTrackInfo_Value(active_track, "IP_TRACKNUMBER"))
                track_name = string.format("Track %d: %s", tidx, (tname and #tname > 0) and tname or "Instrument")
                local raw_col = reaper.GetTrackColor(active_track)
                if raw_col ~= 0 then
                    local r, g, b = reaper.ColorFromNative(raw_col)
                    track_col = (r << 24) | (g << 16) | (b << 8) | 0xFF
                end
            end
            local _, tkn = reaper.GetSetMediaItemTakeInfo_String(active_take, "P_NAME", "", false)
            take_name = (tkn and #tkn > 0) and tkn or "Take 1"

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), track_col & 0xFFFFFF55)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), track_col & 0xFFFFFF77)
            reaper.ImGui_Button(ctx, string.format(" %s [%s] ", track_name, take_name))
            reaper.ImGui_PopStyleColor(ctx, 2)
            if reaper.ImGui_IsItemHovered(ctx) then
                local note_cnt = is_vel_lane and #notes or (select(2, reaper.MIDI_CountEvts(active_take)) or 0)
                reaper.ImGui_SetTooltip(ctx, string.format("Active MIDI Item & Take currently loaded (%d Notes)", note_cnt))
            end
        else
            reaper.ImGui_TextColored(ctx, 0xE74C3CAA, "⚠ No MIDI Item")
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Select a note in the score or an item in REAPER to edit.")
            end
        end

        -- Lane Selector Dropdown (Placed on far left, immediately next to the MIDI item indicator)
        reaper.ImGui_SameLine(ctx, 0, 6)
        reaper.ImGui_SetNextItemWidth(ctx, 175)
        local combo_preview = "🎹 Note Velocity"
        if not is_vel_lane then
            local cc_title = CC_NAMES[cur_cc_num] and string.format("CC %d: %s", cur_cc_num, CC_NAMES[cur_cc_num]) or string.format("CC %d", cur_cc_num)
            if is_locked then
                combo_preview = string.format("🔒 %s", cc_title)
            else
                combo_preview = string.format("📈 %s", cc_title)
            end
        end

        if reaper.ImGui_BeginCombo(ctx, "##MidiLaneCombo", combo_preview) then
            if reaper.ImGui_Selectable(ctx, "🎹 Note Velocity", is_vel_lane) then
                state.midi_editor_lane = "velocity"
                reaper.SetExtState("REAPER_Notator", "MidiEditorLane", "velocity", true)
            end
            reaper.ImGui_Separator(ctx)
            for c = 0, 127 do
                local c_label = CC_NAMES[c] and string.format("CC %3d: %s", c, CC_NAMES[c]) or string.format("CC %3d", c)
                if c == dyn_a then
                    c_label = c_label .. (is_bypassed and " [Dynamic A]" or " [Dynamic A 🔒]")
                elseif c == dyn_b then
                    c_label = c_label .. (is_bypassed and " [Dynamic B]" or " [Dynamic B 🔒]")
                end
                local is_this_sel = (not is_vel_lane and cur_cc_num == c)
                if reaper.ImGui_Selectable(ctx, c_label, is_this_sel) then
                    state.midi_editor_lane = c
                    reaper.SetExtState("REAPER_Notator", "MidiEditorLane", tostring(c), true)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Select lane: Velocity or any of the 128 MIDI CC channels (CC 0-127).\nCC lanes managed by Dynamic CC Shaping (CC 1 & 11) are locked unless Bypass is enabled.")
        end

        -- TOOL CONTROLS & ACTIONS
        local cur_tool = state.midi_editor_tool or "select"

        if is_vel_lane then
            -- ------------------------------------------------------------------
            -- Velocity Lane Toolbar
            -- ------------------------------------------------------------------
            reaper.ImGui_SameLine(ctx, 0, 12)
            local sel_btn_col = (cur_tool == "select") and 0x2980B9FF or 0x2C3E5088
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), sel_btn_col)
            if reaper.ImGui_Button(ctx, "↖ Select", 65, 22) then
                state.midi_editor_tool = "select"
            end
            reaper.ImGui_PopStyleColor(ctx)
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Select & Grab Tool (Click/Drag flag handles or marquee select)")
            end

            reaper.ImGui_SameLine(ctx, 0, 4)
            local draw_btn_col = (cur_tool == "draw") and 0xE67E22FF or 0x2C3E5088
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), draw_btn_col)
            if reaper.ImGui_Button(ctx, "✏ Draw", 60, 22) then
                state.midi_editor_tool = "draw"
            end
            reaper.ImGui_PopStyleColor(ctx)
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Pencil Draw Tool (Click and sweep across lane to freehand draw velocities)")
            end

            -- Velocity Presets (pp, mp, mf, f, ff)
            reaper.ImGui_SameLine(ctx, 0, 10)
            reaper.ImGui_TextColored(ctx, 0x8892B088, "Presets:")
            local presets = {
                { "pp", 32 },
                { "mp", 64 },
                { "mf", 80 },
                { "f",  96 },
                { "ff", 112 },
            }
            for _, p in ipairs(presets) do
                reaper.ImGui_SameLine(ctx, 0, 3)
                if reaper.ImGui_Button(ctx, p[1] .. "##VelPre", 25, 22) then
                    if active_take and #notes > 0 then
                        reaper.Undo_BeginBlock2(0)
                        local any_sel = false
                        for _, n in ipairs(notes) do
                            if state:is_note_selected(n) then
                                any_sel = true
                                midi_service.set_note_velocity(active_take, n.idx, p[2], true)
                                n.vel = p[2]
                            end
                        end
                        if not any_sel then
                            for _, n in ipairs(notes) do
                                midi_service.set_note_velocity(active_take, n.idx, p[2], true)
                                n.vel = p[2]
                            end
                        end
                        reaper.MIDI_Sort(active_take)
                        reaper.UpdateArrange()
                        reaper.Undo_EndBlock2(0, "Set Velocity to " .. p[1], -1)
                        state.status_msg = string.format("Velocity set to %s (%d)", p[1], p[2])
                    end
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, string.format("Set velocity to %d (%s) for selected notes (or all)", p[2], p[1]))
                end
            end

            -- Ramp & Humanize Actions
            reaper.ImGui_SameLine(ctx, 0, 8)
            if reaper.ImGui_Button(ctx, "📈 Ramp", 58, 22) then
                if active_take and #notes > 0 then
                    local sel_notes = {}
                    for _, n in ipairs(notes) do
                        if state:is_note_selected(n) then
                            table.insert(sel_notes, n)
                        end
                    end
                    table.sort(sel_notes, function(a, b) return a.start_qn < b.start_qn end)
                    if #sel_notes >= 2 then
                        reaper.Undo_BeginBlock2(0)
                        local v_start = sel_notes[1].vel
                        local v_end = sel_notes[#sel_notes].vel
                        local total_range = sel_notes[#sel_notes].start_qn - sel_notes[1].start_qn
                        for i = 1, #sel_notes do
                            local n = sel_notes[i]
                            local frac = (total_range > 0.001) and ((n.start_qn - sel_notes[1].start_qn) / total_range) or ((i - 1) / (#sel_notes - 1))
                            local new_v = math.floor(v_start + frac * (v_end - v_start) + 0.5)
                            new_v = math.max(1, math.min(127, new_v))
                            midi_service.set_note_velocity(active_take, n.idx, new_v, true)
                            n.vel = new_v
                        end
                        reaper.MIDI_Sort(active_take)
                        reaper.UpdateArrange()
                        reaper.Undo_EndBlock2(0, "Ramp Note Velocities", -1)
                        state.status_msg = string.format("Ramped %d note velocities from %d to %d", #sel_notes, v_start, v_end)
                    else
                        state.status_msg = "Select at least 2 notes to apply velocity ramp"
                    end
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Linear velocity ramp across selected notes")
            end

            reaper.ImGui_SameLine(ctx, 0, 4)
            if reaper.ImGui_Button(ctx, "🎲 Humanize", 72, 22) then
                if active_take and #notes > 0 then
                    reaper.Undo_BeginBlock2(0)
                    local count = 0
                    for _, n in ipairs(notes) do
                        if state:is_note_selected(n) then
                            local delta = math.random(-7, 7)
                            local new_v = math.max(1, math.min(127, n.vel + delta))
                            midi_service.set_note_velocity(active_take, n.idx, new_v, true)
                            n.vel = new_v
                            count = count + 1
                        end
                    end
                    if count == 0 then
                        for _, n in ipairs(notes) do
                            local delta = math.random(-7, 7)
                            local new_v = math.max(1, math.min(127, n.vel + delta))
                            midi_service.set_note_velocity(active_take, n.idx, new_v, true)
                            n.vel = new_v
                            count = count + 1
                        end
                    end
                    reaper.MIDI_Sort(active_take)
                    reaper.UpdateArrange()
                    reaper.Undo_EndBlock2(0, "Humanize Velocities", -1)
                    state.status_msg = string.format("Humanized %d note velocities (+/- 7)", count)
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Subtly randomize velocities (+/- 7) for selected notes (or all)")
            end
        else
            -- ------------------------------------------------------------------
            -- CC Lane Toolbar
            -- ------------------------------------------------------------------
            if is_locked then
                reaper.ImGui_SameLine(ctx, 0, 10)
                reaper.ImGui_TextColored(ctx, 0xE74C3CFF, string.format("🔒 CC %d Locked (Dynamic Shaping)", cur_cc_num))
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, string.format("CC %d is actively managed by Dynamic CC Shaping.\nManual drawing is disabled to protect automated curves.\nEnable 'Bypass Dynamic CC Shaping' in Dynamics Drawer or click Unlock to edit.", cur_cc_num))
                end

                reaper.ImGui_SameLine(ctx, 0, 8)
                if reaper.ImGui_Button(ctx, "🔓 Unlock (Enable Bypass)", 165, 22) then
                    if dynamics_engine and active_item then
                        dynamics_engine.set_item_bypass_cc(active_item, true, state)
                        state.status_msg = string.format("Bypass Dynamic CC Shaping enabled for '%s'. CC %d unlocked for editing.", take_name, cur_cc_num)
                    else
                        state.dyn_bypass_cc = true
                        state.status_msg = string.format("Bypass Dynamic CC Shaping enabled. CC %d unlocked.", cur_cc_num)
                    end
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Activate 'Bypass Dynamic CC Shaping' for this item so you can manually draw custom CC curves.")
                end
            else
                reaper.ImGui_SameLine(ctx, 0, 10)
                local sel_btn_col = (cur_tool == "select") and 0x2980B9FF or 0x2C3E5088
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), sel_btn_col)
                if reaper.ImGui_Button(ctx, "↖ Select", 65, 22) then
                    state.midi_editor_tool = "select"
                end
                reaper.ImGui_PopStyleColor(ctx)
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Select & Grab Tool (Drag points up/down, Right-click to delete, Double-click to add)")
                end

                reaper.ImGui_SameLine(ctx, 0, 4)
                local draw_btn_col = (cur_tool == "draw") and 0x00B4D8FF or 0x2C3E5088
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), draw_btn_col)
                if reaper.ImGui_Button(ctx, "✏ Draw", 60, 22) then
                    state.midi_editor_tool = "draw"
                end
                reaper.ImGui_PopStyleColor(ctx)
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Pencil Draw Tool (Click and sweep across lane to freehand draw CC curves)")
                end

                -- REAPER CC Shape Selector Combo (Linear Ramp default)
                reaper.ImGui_SameLine(ctx, 0, 8)
                reaper.ImGui_SetNextItemWidth(ctx, 130)
                local cur_shape = state.midi_editor_cc_shape or 1
                local cur_shape_lbl = SHAPE_LABELS[cur_shape] or "📈 Linear (Ramp)"
                if reaper.ImGui_BeginCombo(ctx, "##MidiCCShapeCombo", cur_shape_lbl) then
                    for s_id = 0, 5 do
                        if SHAPE_LABELS[s_id] then
                            local is_sh_sel = (cur_shape == s_id)
                            if reaper.ImGui_Selectable(ctx, SHAPE_LABELS[s_id], is_sh_sel) then
                                state.midi_editor_cc_shape = s_id
                                reaper.SetExtState("REAPER_Notator", "MidiEditorCCShape", tostring(s_id), true)
                            end
                        end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "REAPER CC Curve Shape:\n- Linear (Ramp): Continuous smooth slope (default, eliminates square steps)\n- Square (Step): Flat horizontal steps\n- Slow start/end: S-Curve Bézier")
                end

                -- Batch Convert All to Linear Ramps
                reaper.ImGui_SameLine(ctx, 0, 4)
                if reaper.ImGui_Button(ctx, "📈 Convert All to Linear##LinAll", 145, 22) then
                    if active_take then
                        reaper.Undo_BeginBlock2(0)
                        midi_service.set_lane_cc_shapes(active_take, cur_cc_num, 1)
                        reaper.Undo_EndBlock2(0, string.format("Convert CC %d to Linear Ramps", cur_cc_num), -1)
                        state.status_msg = string.format("Converted all CC %d events to Linear Ramps in REAPER", cur_cc_num)
                    end
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Convert all CC events in this lane to Linear Ramps in REAPER, removing any square steps.")
                end

                -- Quick CC Levels
                reaper.ImGui_SameLine(ctx, 0, 8)
                reaper.ImGui_TextColored(ctx, 0x8892B088, "Levels:")
                local cc_levels = { 0, 32, 64, 96, 127 }
                for _, lv in ipairs(cc_levels) do
                    reaper.ImGui_SameLine(ctx, 0, 3)
                    if reaper.ImGui_Button(ctx, tostring(lv) .. "##CCLev", 28, 22) then
                        if active_item and active_take then
                            local it_pos = reaper.GetMediaItemInfo_Value(active_item, "D_POSITION") or 0.0
                            local it_len = reaper.GetMediaItemInfo_Value(active_item, "D_LENGTH") or 4.0
                            local sqn = reaper.TimeMap2_timeToQN(0, it_pos)
                            local eqn = reaper.TimeMap2_timeToQN(0, it_pos + it_len)
                            reaper.Undo_BeginBlock2(0)
                            midi_service.draw_cc_curve(active_take, cur_cc_num, { { qn = sqn, val = lv }, { qn = eqn, val = lv } }, 0, state.midi_editor_cc_shape or 1)
                            reaper.Undo_EndBlock2(0, string.format("Set CC %d to %d", cur_cc_num, lv), -1)
                            state.status_msg = string.format("Set CC %d curve to %d across item", cur_cc_num, lv)
                        end
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, string.format("Set flat CC %d level to %d across item", cur_cc_num, lv))
                    end
                end

                reaper.ImGui_SameLine(ctx, 0, 6)
                if reaper.ImGui_Button(ctx, "🗑 Clear CC", 70, 22) then
                    if active_take then
                        reaper.Undo_BeginBlock2(0)
                        local ok, cnt = midi_service.clear_take_ccs(active_take, cur_cc_num)
                        reaper.Undo_EndBlock2(0, string.format("Clear CC %d", cur_cc_num), -1)
                        state.status_msg = string.format("Cleared %d CC %d event(s) from take", cnt or 0, cur_cc_num)
                    end
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, string.format("Delete all CC %d events from this take", cur_cc_num))
                end
            end
        end

        -- Horizontal Zoom Controls
        reaper.ImGui_SameLine(ctx, 0, 10)
        reaper.ImGui_TextColored(ctx, 0x8892B088, "Zoom:")
        reaper.ImGui_SameLine(ctx, 0, 3)
        if reaper.ImGui_Button(ctx, "－##MidiZoomOut", 22, 22) then
            state.midi_editor_zoom_x = math.max(0.4, (state.midi_editor_zoom_x or 1.0) - 0.2)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Zoom out horizontally")
        end

        reaper.ImGui_SameLine(ctx, 0, 2)
        if reaper.ImGui_Button(ctx, "＋##MidiZoomIn", 22, 22) then
            state.midi_editor_zoom_x = math.min(4.0, (state.midi_editor_zoom_x or 1.0) + 0.2)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Zoom in horizontally")
        end

        reaper.ImGui_SameLine(ctx, 0, 2)
        if reaper.ImGui_Button(ctx, "↔ Fit##MidiFit", 38, 22) then
            state.midi_editor_zoom_x = 1.0
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Reset horizontal zoom to default (Fit Item)")
        end

        -- Close button on far right
        local cur_win_w = reaper.ImGui_GetWindowWidth(ctx)
        reaper.ImGui_SameLine(ctx, cur_win_w - 30)
        if reaper.ImGui_Button(ctx, "✕##CloseMidiEditor", 24, 22) then
            state.show_midi_editor = false
            reaper.SetExtState("REAPER_Notator", "ShowMidiEditor", "false", true)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Close MIDI Editor drawer")
        end

        reaper.ImGui_Separator(ctx)

        -- ======================================================================
        -- 2. GRAPH VIEWPORT (VELOCITY OR CC LANE)
        -- ======================================================================
        local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        if not active_take or not reaper.ValidatePtr(active_take, "MediaItem_Take*") then
            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 20)
            reaper.ImGui_TextColored(ctx, 0x8892B0FF, "   No active MIDI Item selected.")
            reaper.ImGui_TextColored(ctx, 0x666D80FF, "   Click a note in the score canvas or select a MIDI item in REAPER to view and edit.")
            reaper.ImGui_EndChild(ctx)
            reaper.ImGui_PopStyleColor(ctx, 2)
            return
        end

        -- Determine item boundaries in QN
        local it_pos = active_item and reaper.GetMediaItemInfo_Value(active_item, "D_POSITION") or 0.0
        local it_len = active_item and reaper.GetMediaItemInfo_Value(active_item, "D_LENGTH") or 4.0
        local it_start_qn = reaper.TimeMap2_timeToQN(0, it_pos)
        local it_end_qn = reaper.TimeMap2_timeToQN(0, it_pos + it_len)
        local it_len_qn = math.max(1.0, it_end_qn - it_start_qn)

        -- Compute horizontal scaling
        local zoom = state.midi_editor_zoom_x or 1.0
        local base_px_per_qn = math.max(20.0, (avail_w - 70) / it_len_qn)
        local px_per_qn = base_px_per_qn * zoom
        local total_content_w = math.max(avail_w, 50 + (it_len_qn * px_per_qn) + 50)

        local lane_flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), col_lane_bg)
        if reaper.ImGui_BeginChild(ctx, "MidiEditorLaneScroll", avail_w, avail_h, child_none, lane_flags) then
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            local scroll_x = reaper.ImGui_GetScrollX(ctx)
            local win_x0, win_y0 = reaper.ImGui_GetWindowPos(ctx)
            local win_w = reaper.ImGui_GetWindowWidth(ctx)
            local win_h = reaper.ImGui_GetWindowHeight(ctx)

            -- Reserve content space to activate scrollbar
            reaper.ImGui_Dummy(ctx, total_content_w, win_h - 18)

            -- Geometry for mapping
            local left_pad = 42.0
            local top_pad = 16.0
            local bot_pad = 22.0
            local plot_top_y = win_y0 + top_pad
            local plot_bot_y = win_y0 + win_h - bot_pad
            local plot_h = math.max(10.0, plot_bot_y - plot_top_y)

            local function qn_to_x(qn)
                return win_x0 + left_pad + ((qn - it_start_qn) * px_per_qn) - scroll_x
            end

            local function x_to_qn(screen_x)
                local rel_x = screen_x - (win_x0 + left_pad - scroll_x)
                return it_start_qn + (rel_x / px_per_qn)
            end

            local function val_to_y(v)
                local norm = (math.max(0, math.min(127, v))) / 127.0
                return plot_bot_y - (norm * plot_h)
            end

            local function y_to_val(screen_y)
                local norm = (plot_bot_y - screen_y) / plot_h
                return math.max(0, math.min(127, math.floor(norm * 127.0 + 0.5)))
            end

            local is_playing = (reaper.GetPlayState() == 1)
            local is_hovered = reaper.ImGui_IsWindowHovered(ctx) and not is_playing
            local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
            local is_shift = reaper.APIExists("ImGui_Mod_Shift") and ((reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Shift()) ~= 0) or false
            local is_ctrl = reaper.APIExists("ImGui_Mod_Ctrl") and ((reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Ctrl()) ~= 0) or false

            -- Horizontal Reference Lines (0, 32, 64, 96, 127)
            local guides = {
                { 127, "127" },
                { 96,  "96" },
                { 64,  "64" },
                { 32,  "32" },
                { 0,   "0" }
            }
            for _, g in ipairs(guides) do
                local gy = val_to_y(g[1])
                local line_col = (g[1] == 127 or g[1] == 0) and (col_grid_maj) or (col_grid_min)
                reaper.ImGui_DrawList_AddLine(dl, win_x0 + left_pad - scroll_x, gy, win_x0 + left_pad - scroll_x + (it_len_qn * px_per_qn), gy, line_col, 1.0)
                reaper.ImGui_DrawList_AddText(dl, win_x0 + 4, gy - 6, 0x8892B088, g[2])
            end

            -- Vertical Measure & Beat Grid
            local bpi = 4.0
            local cur_m_qn = math.floor(it_start_qn / bpi) * bpi
            while cur_m_qn <= it_end_qn + bpi do
                local mx = qn_to_x(cur_m_qn)
                if mx >= win_x0 - 40 and mx <= win_x0 + win_w + 40 then
                    -- Major measure line
                    reaper.ImGui_DrawList_AddLine(dl, mx, plot_top_y - 6, mx, plot_bot_y + 4, col_grid_maj, 1.2)
                    local bar_num = math.floor(cur_m_qn / bpi) + 1
                    reaper.ImGui_DrawList_AddText(dl, mx + 4, plot_top_y - 14, 0x8892B0AA, string.format("Bar %d", bar_num))

                    -- Minor beat lines (1/4 notes)
                    for b = 1, math.floor(bpi) - 1 do
                        local bx = qn_to_x(cur_m_qn + b)
                        if bx >= win_x0 and bx <= win_x0 + win_w then
                            reaper.ImGui_DrawList_AddLine(dl, bx, plot_top_y, bx, plot_bot_y, col_grid_min, 1.0)
                        end
                    end
                end
                cur_m_qn = cur_m_qn + bpi
            end

            -- Baseline
            reaper.ImGui_DrawList_AddLine(dl, win_x0 + left_pad - scroll_x, plot_bot_y, win_x0 + left_pad - scroll_x + (it_len_qn * px_per_qn), plot_bot_y, 0x8892B066, 1.5)

            -- ==================================================================
            -- A. VELOCITY LANE RENDERING & INTERACTION
            -- ==================================================================
            if is_vel_lane then
                local hovered_note = nil
                -- Check hover on note handles/stalks
                if is_hovered and not is_drawing_vel and not marquee_active then
                    for i = #notes, 1, -1 do
                        local n = notes[i]
                        local nx = qn_to_x(n.start_qn)
                        local ny = val_to_y(n.vel)

                        -- Top handle hitbox: [nx - 4, ny - 6, nx + 25, ny + 6] (22.5px flag)
                        local in_handle = (mouse_x >= nx - 4 and mouse_x <= nx + 25 and mouse_y >= ny - 6 and mouse_y <= ny + 6)
                        -- Stalk hitbox: [nx - 3, ny, nx + 3, plot_bot_y]
                        local in_stalk = (mouse_x >= nx - 3 and mouse_x <= nx + 3 and mouse_y >= ny and mouse_y <= plot_bot_y + 2)

                        if in_handle or in_stalk then
                            hovered_note = n
                            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
                            local p_name = pitch_to_name(n.pitch)
                            local t_str = format_qn_time(n.start_qn)
                            reaper.ImGui_SetTooltip(ctx, string.format("%s (MIDI %d) | Vel: %d | Time: %s", p_name, n.pitch, n.vel, t_str))
                            break
                        end
                    end
                end

                -- Pointer Tool: Dragging & Selection
                if cur_tool == "select" then
                    if is_hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
                        if hovered_note then
                            if is_shift or is_ctrl then
                                state:toggle_note_selection(hovered_note)
                            else
                                if not state:is_note_selected(hovered_note) then
                                    state:clear_selection()
                                    state:select_note(hovered_note)
                                end
                            end
                            midi_service.sync_take_note_selection(active_take, hovered_note.idx, state:is_note_selected(hovered_note), true)

                            is_dragging_velocity = true
                            drag_lead_note = hovered_note
                            drag_initial_vel = hovered_note.vel
                            drag_snapshots = {}
                            for _, n in ipairs(notes) do
                                if state:is_note_selected(n) then
                                    drag_snapshots[n:get_key()] = { note = n, orig_vel = n.vel }
                                end
                            end
                            reaper.Undo_BeginBlock2(0)
                        elseif mouse_y <= plot_bot_y + 4 and mouse_y >= plot_top_y - 10 then
                            marquee_active = true
                            marquee_start_x = mouse_x
                            marquee_start_y = mouse_y
                            if not is_shift and not is_ctrl then
                                state:clear_selection()
                            end
                        end
                    end

                    -- Active Velocity Dragging
                    if is_dragging_velocity and drag_lead_note then
                        if reaper.ImGui_IsMouseDown(ctx, 0) then
                            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeNS())
                            local cur_v = y_to_val(mouse_y)
                            local delta_v = cur_v - drag_initial_vel

                            for _, snap in pairs(drag_snapshots) do
                                local n = snap.note
                                local new_v = math.max(1, math.min(127, snap.orig_vel + delta_v))
                                if n.vel ~= new_v then
                                    n.vel = new_v
                                    midi_service.set_note_velocity(active_take, n.idx, new_v, true)
                                end
                            end

                            local now = reaper.time_precise()
                            if (now - last_audition_time > 0.08) and (drag_lead_note.vel ~= last_audition_vel) then
                                last_audition_time = now
                                last_audition_vel = drag_lead_note.vel
                                if audio_preview and audio_preview.play_note then
                                    audio_preview.play_note(state, drag_lead_note.pitch, drag_lead_note.vel, drag_lead_note.chan or 0, active_track, drag_lead_note.start_qn, drag_lead_note)
                                end
                            end
                        else
                            is_dragging_velocity = false
                            drag_lead_note = nil
                            drag_snapshots = {}
                            reaper.MIDI_Sort(active_take)
                            reaper.UpdateArrange()
                            reaper.Undo_EndBlock2(0, "Adjust Note Velocity", -1)
                        end
                    end

                    -- Active Marquee Selection
                    if marquee_active then
                        if reaper.ImGui_IsMouseDown(ctx, 0) then
                            local mx0 = math.min(marquee_start_x, mouse_x)
                            local my0 = math.min(marquee_start_y, mouse_y)
                            local mx1 = math.max(marquee_start_x, mouse_x)
                            local my1 = math.max(marquee_start_y, mouse_y)
                            reaper.ImGui_DrawList_AddRectFilled(dl, mx0, my0, mx1, my1, 0x3498DB22)
                            reaper.ImGui_DrawList_AddRect(dl, mx0, my0, mx1, my1, 0x3498DBAA, 0, 0, 1.0)
                        else
                            marquee_active = false
                            local mx0 = math.min(marquee_start_x, mouse_x)
                            local my0 = math.min(marquee_start_y, mouse_y)
                            local mx1 = math.max(marquee_start_x, mouse_x)
                            local my1 = math.max(marquee_start_y, mouse_y)

                            for _, n in ipairs(notes) do
                                local nx = qn_to_x(n.start_qn)
                                local ny = val_to_y(n.vel)
                                local stalk_hit = (nx >= mx0 and nx <= mx1 and my0 <= plot_bot_y and my1 >= ny)
                                local handle_hit = (mx1 >= nx - 4 and mx0 <= nx + 25 and my1 >= ny - 4 and my0 <= ny + 4)
                                if stalk_hit or handle_hit then
                                    state:select_note(n)
                                    midi_service.sync_take_note_selection(active_take, n.idx, true, true)
                                end
                            end
                            reaper.MIDI_Sort(active_take)
                            reaper.UpdateArrange()
                        end
                    end
                end

                -- Pencil Draw Tool
                if cur_tool == "draw" then
                    if is_hovered then
                        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
                    end


                    if is_hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
                        is_drawing_vel = true
                        draw_prev_mx = mouse_x
                        draw_prev_my = mouse_y
                        draw_trail = { { x = mouse_x, y = mouse_y } }
                        reaper.Undo_BeginBlock2(0)
                    end

                    if is_drawing_vel then
                        if reaper.ImGui_IsMouseDown(ctx, 0) then
                            table.insert(draw_trail, { x = mouse_x, y = mouse_y })
                            if #draw_trail > 60 then table.remove(draw_trail, 1) end

                            local x_min = math.min(draw_prev_mx or mouse_x, mouse_x)
                            local x_max = math.max(draw_prev_mx or mouse_x, mouse_x)

                            for _, n in ipairs(notes) do
                                local nx = qn_to_x(n.start_qn)
                                if nx >= x_min - 4 and nx <= x_max + 4 then
                                    local target_y = mouse_y
                                    if math.abs(mouse_x - (draw_prev_mx or mouse_x)) > 0.001 then
                                        local t = (nx - (draw_prev_mx or mouse_x)) / (mouse_x - (draw_prev_mx or mouse_x))
                                        t = math.max(0.0, math.min(1.0, t))
                                        target_y = (draw_prev_my or mouse_y) + t * (mouse_y - (draw_prev_my or mouse_y))
                                    end
                                    local new_v = math.max(1, math.min(127, y_to_val(target_y)))
                                    if n.vel ~= new_v then
                                        n.vel = new_v
                                        midi_service.set_note_velocity(active_take, n.idx, new_v, true)
                                        state:select_note(n)
                                        midi_service.sync_take_note_selection(active_take, n.idx, true, true)
                                    end
                                end
                            end

                            draw_prev_mx = mouse_x
                            draw_prev_my = mouse_y
                        else
                            is_drawing_vel = false
                            draw_prev_mx = nil
                            draw_prev_my = nil
                            draw_trail = {}
                            reaper.MIDI_Sort(active_take)
                            reaper.UpdateArrange()
                            reaper.Undo_EndBlock2(0, "Draw Note Velocity", -1)
                        end
                    end

                    if #draw_trail > 1 then
                        for pt = 1, #draw_trail - 1 do
                            local p1 = draw_trail[pt]
                            local p2 = draw_trail[pt + 1]
                            local alpha = math.floor((pt / #draw_trail) * 255)
                            local trail_col = (0xE67E2200) | alpha
                            reaper.ImGui_DrawList_AddLine(dl, p1.x, p1.y, p2.x, p2.y, trail_col, 2.5)
                        end
                    end
                end

                -- Render Stalks (Halved width: 3.0px unselected, 3.5px selected/hover)
                local function draw_single_note_stalk(n, is_sel)
                    local nx = qn_to_x(n.start_qn)
                    if nx >= win_x0 - 40 and nx <= win_x0 + win_w + 40 then
                        local ny = val_to_y(n.vel)
                        local is_hov = (hovered_note == n)

                        local stalk_col = col_vel_stalk
                        local handle_col = col_vel_flag
                        local border_col = 0x1E293BFF
                        local stalk_w = 3.0
                        local flag_h = 1.6
                        local bead_r = 2.5

                        if is_sel then
                            stalk_col = col_vel_sel
                            handle_col = col_vel_sel
                            border_col = 0x78350FFF
                            stalk_w = 3.5
                            flag_h = 2.0
                            bead_r = 3.0
                        elseif is_hov then
                            stalk_col = col_vel_hov
                            handle_col = col_vel_hov
                            stalk_w = 3.5
                            flag_h = 2.0
                            bead_r = 3.0
                        end

                        -- 1. Vertical Stalk (Stem - 3.0px / 3.5px)
                        reaper.ImGui_DrawList_AddLine(dl, nx, plot_bot_y, nx, ny, stalk_col, stalk_w)

                        -- 2. REAPER Top Handle Flag ("Fähnchen" - 22.5px horizontal flag)
                        local flag_w = 22.5
                        local flag_x0 = nx
                        local flag_y0 = ny - (flag_h * 0.5)
                        local flag_x1 = nx + flag_w
                        local flag_y1 = ny + (flag_h * 0.5)

                        reaper.ImGui_DrawList_AddRectFilled(dl, flag_x0, flag_y0, flag_x1, flag_y1, handle_col, 0.8)
                        reaper.ImGui_DrawList_AddRect(dl, flag_x0 - 0.5, flag_y0 - 0.5, flag_x1 + 0.5, flag_y1 + 0.5, border_col, 0.8, 0, 1.0)

                        -- Apex Bead
                        reaper.ImGui_DrawList_AddCircleFilled(dl, nx, ny, bead_r, handle_col)
                        reaper.ImGui_DrawList_AddCircle(dl, nx, ny, bead_r, border_col, 0, 1.0)

                        if is_sel then
                            reaper.ImGui_DrawList_AddCircleFilled(dl, nx, ny, 1.2, 0xFFFFFFFF)
                        end
                    end
                end

                for _, n in ipairs(notes) do
                    if not state:is_note_selected(n) then
                        draw_single_note_stalk(n, false)
                    end
                end
                for _, n in ipairs(notes) do
                    if state:is_note_selected(n) then
                        draw_single_note_stalk(n, true)
                    end
                end

            -- ==================================================================
            -- B. CC LANE RENDERING & INTERACTION (WITH DYNAMIC LOCK & SHAPE SYNC)
            -- ==================================================================
            else
                local cc_evts = midi_service.get_take_ccs_for_editor(active_take, cur_cc_num)

                -- Visual Styling: Locked vs Unlocked
                local eff_line_col = is_locked and col_cc_locked or col_cc_line
                local eff_fill_col = is_locked and 0x64748B1C or col_cc_fill
                local eff_node_col = is_locked and 0x94A3B888 or col_cc_node
                local node_border = is_locked and 0x334155AA or 0x0F172AFF

                -- Empty Lane Notice
                if #cc_evts == 0 then
                    if is_locked then
                        reaper.ImGui_DrawList_AddText(dl, win_x0 + 60, win_y0 + (win_h * 0.40), 0xE74C3C99, string.format("🔒 CC %d is locked by Dynamic CC Shaping (No manual CC events).", cur_cc_num))
                        reaper.ImGui_DrawList_AddText(dl, win_x0 + 60, win_y0 + (win_h * 0.40) + 18, 0x8892B088, "Enable 'Bypass Dynamic CC Shaping' in Dynamics Drawer or click [🔓 Unlock] to draw custom curves.")
                    else
                        reaper.ImGui_DrawList_AddText(dl, win_x0 + 60, win_y0 + (win_h * 0.40), 0x8892B0AA, string.format("No CC %d events in this item.", cur_cc_num))
                        reaper.ImGui_DrawList_AddText(dl, win_x0 + 60, win_y0 + (win_h * 0.40) + 18, 0x64748B88, "Use ✏ Draw tool or click Level presets to create curves. Double-click to insert points.")
                    end
                else
                    -- Build continuous curve polyline
                    local curve_pts = {}
                    if cc_evts[1].qn > it_start_qn then
                        table.insert(curve_pts, { x = qn_to_x(it_start_qn), y = val_to_y(cc_evts[1].val), qn = it_start_qn, val = cc_evts[1].val, shape = cc_evts[1].shape, is_edge = true })
                    end
                    for _, ev in ipairs(cc_evts) do
                        table.insert(curve_pts, { x = qn_to_x(ev.qn), y = val_to_y(ev.val), qn = ev.qn, val = ev.val, shape = ev.shape, ev = ev })
                    end
                    if cc_evts[#cc_evts].qn < it_end_qn then
                        table.insert(curve_pts, { x = qn_to_x(it_end_qn), y = val_to_y(cc_evts[#cc_evts].val), qn = it_end_qn, val = cc_evts[#cc_evts].val, shape = cc_evts[#cc_evts].shape, is_edge = true })
                    end

                    -- 1. Fill Area & Outline Curve based on REAPER Event Shapes (Linear vs Square)
                    local cull_left = plot_x0 - 20
                    local cull_right = plot_x0 + plot_w + 20
                    for i = 1, #curve_pts - 1 do
                        local p1 = curve_pts[i]
                        local p2 = curve_pts[i + 1]
                        if not (p1.x < cull_left and p2.x < cull_left) and not (p1.x > cull_right and p2.x > cull_right) then
                            local p_shape = p1.shape or 1

                            if p_shape == 0 then
                                -- Square (Step / Stufe)
                                reaper.ImGui_DrawList_AddQuadFilled(dl, p1.x, p1.y, p2.x, p1.y, p2.x, plot_bot_y, p1.x, plot_bot_y, eff_fill_col)
                                reaper.ImGui_DrawList_AddLine(dl, p1.x, p1.y, p2.x, p1.y, eff_line_col, 2.0)
                                reaper.ImGui_DrawList_AddLine(dl, p2.x, p1.y, p2.x, p2.y, eff_line_col, 2.0)
                            else
                                -- Linear Ramp (or Bézier smooth curve)
                                reaper.ImGui_DrawList_AddQuadFilled(dl, p1.x, p1.y, p2.x, p2.y, p2.x, plot_bot_y, p1.x, plot_bot_y, eff_fill_col)
                                reaper.ImGui_DrawList_AddLine(dl, p1.x, p1.y, p2.x, p2.y, eff_line_col, 2.0)
                            end
                        end
                    end

                    -- 2. Node Beads at Actual Events (viewport culled)
                    for _, pt in ipairs(curve_pts) do
                        if pt.ev and pt.x >= cull_left and pt.x <= cull_right then
                            local is_hov = (hovered_cc_node and hovered_cc_node.idx == pt.ev.idx)
                            local in_marquee = false
                            if cc_marquee_active then
                                local mx0 = math.min(cc_marquee_start_x, mouse_x)
                                local my0 = math.min(cc_marquee_start_y, mouse_y)
                                local mx1 = math.max(cc_marquee_start_x, mouse_x)
                                local my1 = math.max(cc_marquee_start_y, mouse_y)
                                if pt.x >= mx0 - 6 and pt.x <= mx1 + 6 and pt.y >= my0 - 6 and pt.y <= my1 + 6 then
                                    in_marquee = true
                                end
                            end
                            local is_sel = (pt.ev.sel == true) or (state.selected_cc_indices and state.selected_cc_indices[pt.ev.idx]) or in_marquee

                            if is_sel then
                                -- Glowing selection halo / ring
                                local halo_col = is_hov and 0xFFD16688 or 0xF59E0B66
                                reaper.ImGui_DrawList_AddCircleFilled(dl, pt.x, pt.y, 6.0, halo_col)
                                -- Bright golden / amber core
                                local sel_core_col = is_hov and 0xFFE066FF or 0xF59E0BFF
                                reaper.ImGui_DrawList_AddCircleFilled(dl, pt.x, pt.y, 4.2, sel_core_col)
                                -- Crisp white outer border
                                reaper.ImGui_DrawList_AddCircle(dl, pt.x, pt.y, 4.2, 0xFFFFFFFF, 0, 1.4)
                            else
                                local b_col = is_hov and 0xFFB703FF or eff_node_col
                                local b_r = is_hov and 4.2 or 2.8
                                reaper.ImGui_DrawList_AddCircleFilled(dl, pt.x, pt.y, b_r, b_col)
                                reaper.ImGui_DrawList_AddCircle(dl, pt.x, pt.y, b_r, node_border, 0, 1.0)
                            end
                        end
                    end
                end

                -- Top Watermark Banner if Locked
                if is_locked then
                    reaper.ImGui_DrawList_AddRectFilled(dl, win_x0 + 40, win_y0 + 20, win_x0 + win_w - 40, win_y0 + 42, 0x1E293BEE, 4.0)
                    reaper.ImGui_DrawList_AddRect(dl, win_x0 + 40, win_y0 + 20, win_x0 + win_w - 40, win_y0 + 42, 0xE74C3C88, 4.0, 0, 1.0)
                    reaper.ImGui_DrawList_AddText(dl, win_x0 + 52, win_y0 + 24, 0xE74C3CFF, string.format("🔒 CC %d is locked by Dynamic CC Shaping (Read-Only) — To edit curves, click [🔓 Unlock] in the toolbar.", cur_cc_num))

                    if is_hovered then
                        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_NotAllowed and reaper.ImGui_MouseCursor_NotAllowed() or 0)
                        if reaper.ImGui_IsMouseClicked(ctx, 0) or reaper.ImGui_IsMouseClicked(ctx, 1) then
                            state.status_msg = string.format("CC %d is locked by Dynamic CC Shaping. Click Unlock or enable Bypass in Dynamics Drawer.", cur_cc_num)
                        end
                    end
                else
                    -- Unlocked: Full Interactive Editing
                    hovered_cc_node = nil
                    if is_hovered and not is_drawing_cc and not is_dragging_cc_nodes and not cc_marquee_active then
                        for _, ev in ipairs(cc_evts) do
                            local ex = qn_to_x(ev.qn)
                            if ex > mouse_x + 8 then
                                break
                            end
                            if ex >= mouse_x - 8 then
                                local ey = val_to_y(ev.val)
                                if math.abs(mouse_y - ey) <= 8 then
                                    hovered_cc_node = ev
                                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll and reaper.ImGui_MouseCursor_ResizeAll() or reaper.ImGui_MouseCursor_ResizeNS())
                                    local sh_name = SHAPE_LABELS[ev.shape or 1] or "Linear"
                                    local is_sel = ev.sel or (state.selected_cc_indices and state.selected_cc_indices[ev.idx])
                                    local sel_txt = is_sel and " [Selected]" or ""
                                    reaper.ImGui_SetTooltip(ctx, string.format("CC %d: %d%s | Time: %s | Shape: %s\n(Drag to move point(s), Shift+Drag to lock axis, Right-Click to delete)", cur_cc_num, ev.val, sel_txt, format_qn_time(ev.qn), sh_name))
                                    break
                                end
                            end
                        end
                    end

                    -- Pointer Tool Interaction
                    if cur_tool == "select" then
                        -- Check for Delete/Backspace key to delete selected CCs
                        if is_hovered and (reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Delete()) or reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Backspace())) then
                            local del_cnt = 0
                            reaper.Undo_BeginBlock2(0)
                            local _, _, cccnt = reaper.MIDI_CountEvts(active_take)
                            for i = (cccnt or 0) - 1, 0, -1 do
                                local ok, sel, _, _, chanmsg, _, msg2, _ = reaper.MIDI_GetCC(active_take, i)
                                if ok and ((chanmsg == 176) or ((chanmsg >> 4) == 0xB)) and msg2 == cur_cc_num then
                                    if sel or (state.selected_cc_indices and state.selected_cc_indices[i]) then
                                        reaper.MIDI_DeleteCC(active_take, i)
                                        del_cnt = del_cnt + 1
                                    end
                                end
                            end
                            if del_cnt > 0 then
                                reaper.MIDI_Sort(active_take)
                                midi_service.invalidate_editor_cache()
                                reaper.UpdateArrange()
                                state.selected_cc_indices = {}
                                hovered_cc_node = nil
                                reaper.Undo_EndBlock2(0, string.format("Delete %d CC %d Event(s)", del_cnt, cur_cc_num), -1)
                                state.status_msg = string.format("Deleted %d CC %d event(s)", del_cnt, cur_cc_num)
                            else
                                reaper.Undo_EndBlock2(0, "Delete CC Events", -1)
                            end
                        end

                        if is_hovered and hovered_cc_node and reaper.ImGui_IsMouseClicked(ctx, 1) then
                            -- Right-click node -> Delete event (or all selected events if hovered is selected)
                            reaper.Undo_BeginBlock2(0)
                            local is_hovered_selected = hovered_cc_node.sel or (state.selected_cc_indices and state.selected_cc_indices[hovered_cc_node.idx])
                            local del_cnt = 0
                            local _, _, cccnt = reaper.MIDI_CountEvts(active_take)
                            for i = (cccnt or 0) - 1, 0, -1 do
                                local ok, sel, _, _, chanmsg, _, msg2, _ = reaper.MIDI_GetCC(active_take, i)
                                if ok and ((chanmsg == 176) or ((chanmsg >> 4) == 0xB)) and msg2 == cur_cc_num then
                                    local should_del = false
                                    if is_hovered_selected and (sel or (state.selected_cc_indices and state.selected_cc_indices[i])) then
                                        should_del = true
                                    elseif hovered_cc_node.idx == i then
                                        should_del = true
                                    end
                                    if should_del then
                                        reaper.MIDI_DeleteCC(active_take, i)
                                        del_cnt = del_cnt + 1
                                    end
                                end
                            end
                            reaper.MIDI_Sort(active_take)
                            midi_service.invalidate_editor_cache()
                            reaper.UpdateArrange()
                            state.selected_cc_indices = {}
                            hovered_cc_node = nil
                            reaper.Undo_EndBlock2(0, string.format("Delete %d CC %d Event(s)", del_cnt, cur_cc_num), -1)
                            state.status_msg = string.format("Deleted %d CC %d event(s)", del_cnt, cur_cc_num)

                        elseif is_hovered and hovered_cc_node and reaper.ImGui_IsMouseClicked(ctx, 0) then
                            -- Left-click on node
                            state.selected_cc_indices = state.selected_cc_indices or {}
                            local was_sel = hovered_cc_node.sel or (state.selected_cc_indices[hovered_cc_node.idx] == true)

                            if is_shift or is_ctrl then
                                -- Toggle selection
                                if was_sel then
                                    state.selected_cc_indices[hovered_cc_node.idx] = nil
                                    hovered_cc_node.sel = false
                                    midi_service.set_cc_selected(active_take, hovered_cc_node.idx, false, true)
                                else
                                    state.selected_cc_indices[hovered_cc_node.idx] = true
                                    hovered_cc_node.sel = true
                                    midi_service.set_cc_selected(active_take, hovered_cc_node.idx, true, true)
                                end
                            else
                                -- Single click: if not already selected, clear previous and select this one
                                if not was_sel then
                                    midi_service.clear_cc_selection(active_take, cur_cc_num)
                                    state.selected_cc_indices = {}
                                    for _, e in ipairs(cc_evts) do e.sel = false end
                                    state.selected_cc_indices[hovered_cc_node.idx] = true
                                    hovered_cc_node.sel = true
                                    midi_service.set_cc_selected(active_take, hovered_cc_node.idx, true, true)
                                end
                            end

                            -- Start multi-node drag
                            is_dragging_cc_nodes = true
                            cc_drag_lead_event = hovered_cc_node
                            cc_drag_start_x = mouse_x
                            cc_drag_start_y = mouse_y
                            cc_drag_start_qn = hovered_cc_node.qn
                            cc_drag_start_val = hovered_cc_node.val
                            cc_drag_snapshots = {}
                            for _, ev in ipairs(cc_evts) do
                                if ev.sel or (state.selected_cc_indices and state.selected_cc_indices[ev.idx]) or (ev.idx == hovered_cc_node.idx) then
                                    table.insert(cc_drag_snapshots, {
                                        idx = ev.idx,
                                        orig_qn = ev.qn,
                                        orig_val = ev.val,
                                        orig_ppq = ev.ppq,
                                        chan = ev.chan,
                                        shape = ev.shape,
                                        ev = ev
                                    })
                                end
                            end
                            reaper.Undo_BeginBlock2(0)

                        elseif is_hovered and not hovered_cc_node and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                            -- Double-click empty space -> Insert CC point with active shape
                            local target_qn = math.max(it_start_qn, math.min(it_end_qn, x_to_qn(mouse_x)))
                            local target_v = y_to_val(mouse_y)
                            local ppq = reaper.MIDI_GetPPQPosFromProjQN(active_take, target_qn)
                            local cur_sh = state.midi_editor_cc_shape or 1
                            reaper.Undo_BeginBlock2(0)
                            reaper.MIDI_InsertCC(active_take, true, false, ppq, 176, 0, cur_cc_num, target_v)
                            reaper.MIDI_Sort(active_take)
                            midi_service.invalidate_editor_cache()
                            if reaper.APIExists("MIDI_SetCCShape") then
                                local _, _, total_ccs = reaper.MIDI_CountEvts(active_take)
                                for j = 0, (total_ccs or 0) - 1 do
                                    local ok, _, _, c_ppq, chanmsg, _, msg2, _ = reaper.MIDI_GetCC(active_take, j)
                                    if ok and ((chanmsg == 176) or ((chanmsg >> 4) == 0xB)) and msg2 == cur_cc_num and math.abs(c_ppq - ppq) < 2 then
                                        reaper.MIDI_SetCCShape(active_take, j, cur_sh, 0.0)
                                        break
                                    end
                                end
                            end
                            reaper.UpdateArrange()
                            reaper.Undo_EndBlock2(0, string.format("Insert CC %d Event", cur_cc_num), -1)

                        elseif is_hovered and not hovered_cc_node and reaper.ImGui_IsMouseClicked(ctx, 0) then
                            -- Single click empty space -> Start CC Marquee Selection Box
                            cc_marquee_active = true
                            cc_marquee_start_x = mouse_x
                            cc_marquee_start_y = mouse_y
                            if not is_shift and not is_ctrl then
                                state.selected_cc_indices = {}
                                midi_service.clear_cc_selection(active_take, cur_cc_num)
                                for _, e in ipairs(cc_evts) do e.sel = false end
                            end
                        end

                        -- Active Multi-Node Dragging
                        if is_dragging_cc_nodes and #cc_drag_snapshots > 0 then
                            if reaper.ImGui_IsMouseDown(ctx, 0) then
                                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeAll and reaper.ImGui_MouseCursor_ResizeAll() or reaper.ImGui_MouseCursor_ResizeNS())
                                local cur_v = y_to_val(mouse_y)
                                local delta_v = cur_v - cc_drag_start_val

                                local delta_qn = 0.0
                                if math.abs(mouse_x - cc_drag_start_x) >= 4 then
                                    local cur_qn = x_to_qn(mouse_x)
                                    delta_qn = cur_qn - cc_drag_start_qn
                                end

                                if is_shift then
                                    local dx = math.abs(mouse_x - cc_drag_start_x)
                                    local dy = math.abs(mouse_y - cc_drag_start_y)
                                    if dx > dy then
                                        delta_v = 0
                                    else
                                        delta_qn = 0.0
                                    end
                                end

                                for _, snap in ipairs(cc_drag_snapshots) do
                                    local new_val = math.max(0, math.min(127, snap.orig_val + delta_v))
                                    local new_qn = math.max(it_start_qn, math.min(it_end_qn, snap.orig_qn + delta_qn))
                                    local new_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(active_take, new_qn) + 0.5)

                                    reaper.MIDI_SetCC(active_take, snap.idx, true, false, new_ppq, 176, snap.chan or 0, cur_cc_num, new_val, true)
                                    if snap.ev then
                                        snap.ev.val = new_val
                                        snap.ev.qn = new_qn
                                        snap.ev.ppq = new_ppq
                                    end
                                end
                            else
                                -- Mouse button released: finish drag
                                is_dragging_cc_nodes = false
                                local moved_dist = math.abs(mouse_x - cc_drag_start_x) + math.abs(mouse_y - cc_drag_start_y)
                                if moved_dist < 3 and not is_shift and not is_ctrl and cc_drag_lead_event then
                                    -- Click without drag on an already selected node -> isolate that single node
                                    midi_service.clear_cc_selection(active_take, cur_cc_num)
                                    state.selected_cc_indices = {}
                                    for _, e in ipairs(cc_evts) do e.sel = false end
                                    state.selected_cc_indices[cc_drag_lead_event.idx] = true
                                    cc_drag_lead_event.sel = true
                                    midi_service.set_cc_selected(active_take, cc_drag_lead_event.idx, true, true)
                                end

                                reaper.MIDI_Sort(active_take)
                                midi_service.invalidate_editor_cache()
                                reaper.UpdateArrange()
                                reaper.Undo_EndBlock2(0, string.format("Move %d CC %d Point(s)", #cc_drag_snapshots, cur_cc_num), -1)
                                state.status_msg = string.format("Moved %d CC %d point(s)", #cc_drag_snapshots, cur_cc_num)
                                cc_drag_snapshots = {}
                                cc_drag_lead_event = nil
                            end
                        end

                        -- Active CC Marquee Selection Box
                        if cc_marquee_active then
                            if reaper.ImGui_IsMouseDown(ctx, 0) then
                                local mx0 = math.min(cc_marquee_start_x, mouse_x)
                                local my0 = math.min(cc_marquee_start_y, mouse_y)
                                local mx1 = math.max(cc_marquee_start_x, mouse_x)
                                local my1 = math.max(cc_marquee_start_y, mouse_y)
                                reaper.ImGui_DrawList_AddRectFilled(dl, mx0, my0, mx1, my1, 0x3498DB22)
                                reaper.ImGui_DrawList_AddRect(dl, mx0, my0, mx1, my1, 0x3498DBAA, 0, 0, 1.0)
                            else
                                cc_marquee_active = false
                                local mx0 = math.min(cc_marquee_start_x, mouse_x)
                                local my0 = math.min(cc_marquee_start_y, mouse_y)
                                local mx1 = math.max(cc_marquee_start_x, mouse_x)
                                local my1 = math.max(cc_marquee_start_y, mouse_y)

                                state.selected_cc_indices = state.selected_cc_indices or {}
                                local newly_selected = 0
                                for _, ev in ipairs(cc_evts) do
                                    local ex = qn_to_x(ev.qn)
                                    local ey = val_to_y(ev.val)
                                    if ex >= mx0 - 6 and ex <= mx1 + 6 and ey >= my0 - 6 and ey <= my1 + 6 then
                                        ev.sel = true
                                        state.selected_cc_indices[ev.idx] = true
                                        midi_service.set_cc_selected(active_take, ev.idx, true, true)
                                        newly_selected = newly_selected + 1
                                    end
                                end
                                reaper.MIDI_Sort(active_take)
                                midi_service.invalidate_editor_cache()
                                reaper.UpdateArrange()
                                if newly_selected > 0 then
                                    state.status_msg = string.format("Selected %d CC %d point(s)", newly_selected, cur_cc_num)
                                end
                            end
                        end
                    end

                    -- Pencil / Draw Tool Interaction
                    if cur_tool == "draw" then
                        if is_hovered then
                            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_None())
                        end

                        if is_hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
                            is_drawing_cc = true
                            cc_draw_stroke = {}
                            local qn = math.max(it_start_qn, math.min(it_end_qn, x_to_qn(mouse_x)))
                            local v = y_to_val(mouse_y)
                            table.insert(cc_draw_stroke, { qn = qn, val = v, x = mouse_x, y = mouse_y })
                            reaper.Undo_BeginBlock2(0)
                        end

                        if is_drawing_cc then
                            if reaper.ImGui_IsMouseDown(ctx, 0) then
                                local qn = math.max(it_start_qn, math.min(it_end_qn, x_to_qn(mouse_x)))
                                local v = y_to_val(mouse_y)
                                local last_pt = cc_draw_stroke[#cc_draw_stroke]
                                if not last_pt or math.abs(mouse_x - last_pt.x) >= 4 or math.abs(mouse_y - last_pt.y) >= 4 then
                                    table.insert(cc_draw_stroke, { qn = qn, val = v, x = mouse_x, y = mouse_y })
                                end
                            else
                                is_drawing_cc = false
                                if #cc_draw_stroke >= 2 then
                                    midi_service.draw_cc_curve(active_take, cur_cc_num, cc_draw_stroke, 0, state.midi_editor_cc_shape or 1)
                                    reaper.Undo_EndBlock2(0, string.format("Draw CC %d Curve", cur_cc_num), -1)
                                    state.status_msg = string.format("Drawn CC %d curve (%d points, %s)", cur_cc_num, #cc_draw_stroke, SHAPE_LABELS[state.midi_editor_cc_shape or 1] or "Linear")
                                else
                                    reaper.Undo_EndBlock2(0, "Draw CC Curve", -1)
                                end
                                cc_draw_stroke = {}
                            end
                        end

                        -- Render neon drawing stroke
                        if #cc_draw_stroke > 1 then
                            for pt = 1, #cc_draw_stroke - 1 do
                                local p1 = cc_draw_stroke[pt]
                                local p2 = cc_draw_stroke[pt + 1]
                                reaper.ImGui_DrawList_AddLine(dl, p1.x, p1.y, p2.x, p2.y, 0x00F5D4FF, 2.5)
                            end
                        end
                    end
                end
            end

            -- Render Playhead during Playback
            if is_playing then
                local play_time = reaper.GetPlayPosition()
                local play_qn = reaper.TimeMap2_timeToQN(0, play_time)
                local play_x = qn_to_x(play_qn)
                if play_x >= win_x0 and play_x <= win_x0 + win_w then
                    reaper.ImGui_DrawList_AddLine(dl, play_x, plot_top_y - 8, play_x, plot_bot_y + 6, 0x2ECC71FF, 2.0)
                end
            end

            -- Render Custom Pen Cursor if Draw Tool is active and lane is hovered
            if cur_tool == "draw" and is_hovered and (is_vel_lane or not is_locked) then
                local fg_dl = (reaper.APIExists("ImGui_GetForegroundDrawList") and reaper.ImGui_GetForegroundDrawList(ctx)) or dl
                draw_pen_cursor(fg_dl, mouse_x, mouse_y, is_drawing_vel or is_drawing_cc)
            end

            reaper.ImGui_EndChild(ctx)

        end
        reaper.ImGui_PopStyleColor(ctx) -- Lane ChildBg

        reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx, 2) -- MainPane ChildBg & Border
end

return MidiEditorDrawer

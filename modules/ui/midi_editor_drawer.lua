-- ==============================================================================
-- REAPER Native Notator - UI: MidiEditorDrawer
-- Collapsible bottom drawer: MIDI Velocity Lane & Graph View for active MIDI Item
-- Displays REAPER-style velocity stalks with flag handles ("Fähnchen"),
-- bidirectional note selection synchronization with the score canvas,
-- pointer drag manipulation, freehand pencil drawing, and acoustic audition.
-- ==============================================================================

local Constants = require("constants")
local MidiNote = require("classes.note")

local MidiEditorDrawer = {}

-- Local interaction state
local is_dragging_velocity = false
local drag_lead_note = nil
local drag_initial_vel = 96
local drag_snapshots = {} -- [note_key] = { note = n, orig_vel = n.vel }
local is_drawing = false
local draw_prev_mx = nil
local draw_prev_my = nil
local draw_trail = {}
local marquee_active = false
local marquee_start_x = 0
local marquee_start_y = 0
local last_audition_time = 0
local last_audition_vel = -1

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

--- Main render function for the MIDI Editor bottom drawer
--- @param ctx ImGui_Context
--- @param state table
--- @param midi_service table
--- @param audio_preview table
--- @param width number
--- @param height number
--- @param project_tracks table
--- @param font_main ImFont
function MidiEditorDrawer.render(ctx, state, midi_service, audio_preview, width, height, project_tracks, font_main)
    if not state.show_midi_editor then return end

    local child_border = reaper.APIExists("ImGui_ChildFlags_Borders") and reaper.ImGui_ChildFlags_Borders() or 1
    local child_none = reaper.APIExists("ImGui_ChildFlags_None") and reaper.ImGui_ChildFlags_None() or 0

    local pane_flags = reaper.ImGui_WindowFlags_NoScrollbar()
    if reaper.APIExists("ImGui_WindowFlags_NoScrollWithMouse") then
        pane_flags = pane_flags | reaper.ImGui_WindowFlags_NoScrollWithMouse()
    end

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x181A20FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x383D4CFF)

    if reaper.ImGui_BeginChild(ctx, "MidiEditorMainPane", width, height, child_border, pane_flags) then
        -- Find active MIDI Item and Take
        local active_item, active_take, active_track = midi_service.get_active_midi_item_and_take(state)

        -- ======================================================================
        -- 1. HEADER / TOOLBAR
        -- ======================================================================
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 2)

        -- Title & Icon
        reaper.ImGui_TextColored(ctx, 0x8E44ADFF, "🎹 MIDI EDITOR")
        reaper.ImGui_SameLine(ctx, 0, 8)
        reaper.ImGui_TextColored(ctx, 0x8892B0FF, "| Velocity Lane")

        -- Target Take / Track Badge
        reaper.ImGui_SameLine(ctx, 0, 14)
        local notes = {}
        if active_take and reaper.ValidatePtr(active_take, "MediaItem_Take*") then
            notes = midi_service.get_take_notes_for_editor(active_take, active_item, active_track)
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
            local _, take_name = reaper.GetSetMediaItemTakeInfo_String(active_take, "P_NAME", "", false)
            take_name = (take_name and #take_name > 0) and take_name or "Take 1"

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), track_col & 0xFFFFFF55)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), track_col & 0xFFFFFF77)
            reaper.ImGui_Button(ctx, string.format(" %s  [%s]  (%d Notes) ", track_name, take_name, #notes))
            reaper.ImGui_PopStyleColor(ctx, 2)
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Active MIDI Item & Take currently loaded in the Velocity Lane")
            end
        else
            reaper.ImGui_TextColored(ctx, 0xE74C3CAA, "⚠ No Active MIDI Item")
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Select a note in the score or an item in REAPER to edit velocity.")
            end
        end

        -- Tool Mode: Pointer [Select] vs Pencil [Draw]
        reaper.ImGui_SameLine(ctx, 0, 16)
        local cur_tool = state.midi_editor_tool or "select"
        local sel_btn_col = (cur_tool == "select") and 0x2980B9FF or 0x2C3E5088
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), sel_btn_col)
        if reaper.ImGui_Button(ctx, "↖ Select", 70, 22) then
            state.midi_editor_tool = "select"
        end
        reaper.ImGui_PopStyleColor(ctx)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Select & Grab Tool (Click/Drag flag handles or marquee select)")
        end

        reaper.ImGui_SameLine(ctx, 0, 4)
        local draw_btn_col = (cur_tool == "draw") and 0xE67E22FF or 0x2C3E5088
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), draw_btn_col)
        if reaper.ImGui_Button(ctx, "✏ Draw", 65, 22) then
            state.midi_editor_tool = "draw"
        end
        reaper.ImGui_PopStyleColor(ctx)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Pencil Draw Tool (Click and sweep across lane to freehand draw velocities)")
        end

        -- Quick Velocity Presets (pp, mp, mf, f, ff)
        reaper.ImGui_SameLine(ctx, 0, 14)
        reaper.ImGui_TextColored(ctx, 0x8892B088, "Presets:")
        local presets = {
            { "pp", 32 },
            { "mp", 64 },
            { "mf", 80 },
            { "f",  96 },
            { "ff", 112 },
        }
        for _, p in ipairs(presets) do
            reaper.ImGui_SameLine(ctx, 0, 4)
            if reaper.ImGui_Button(ctx, p[1] .. "##VelPre", 26, 22) then
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
                        -- Apply to all notes in take
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
                reaper.ImGui_SetTooltip(ctx, string.format("Set velocity to %d (%s) for selected notes (or all if none selected)", p[2], p[1]))
            end
        end

        -- Ramp Action Button
        reaper.ImGui_SameLine(ctx, 0, 8)
        if reaper.ImGui_Button(ctx, "📈 Ramp", 60, 22) then
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
            reaper.ImGui_SetTooltip(ctx, "Create a linear velocity ramp across selected notes (from first note's vel to last note's vel)")
        end

        -- Humanize Action Button
        reaper.ImGui_SameLine(ctx, 0, 6)
        if reaper.ImGui_Button(ctx, "🎲 Humanize", 75, 22) then
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
            reaper.ImGui_SetTooltip(ctx, "Subtly randomize velocities (+/- 7) for selected notes (or all notes)")
        end

        -- Horizontal Zoom Controls
        reaper.ImGui_SameLine(ctx, 0, 14)
        reaper.ImGui_TextColored(ctx, 0x8892B088, "Zoom:")
        reaper.ImGui_SameLine(ctx, 0, 4)
        if reaper.ImGui_Button(ctx, "－##VelZoomOut", 22, 22) then
            state.midi_editor_zoom_x = math.max(0.4, (state.midi_editor_zoom_x or 1.0) - 0.2)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Zoom out horizontally")
        end

        reaper.ImGui_SameLine(ctx, 0, 2)
        if reaper.ImGui_Button(ctx, "＋##VelZoomIn", 22, 22) then
            state.midi_editor_zoom_x = math.min(4.0, (state.midi_editor_zoom_x or 1.0) + 0.2)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Zoom in horizontally")
        end

        reaper.ImGui_SameLine(ctx, 0, 2)
        if reaper.ImGui_Button(ctx, "↔ Fit##VelFit", 38, 22) then
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
        -- 2. VELOCITY LANE GRAPH VIEWPORT
        -- ======================================================================
        local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        if not active_take or not reaper.ValidatePtr(active_take, "MediaItem_Take*") then
            reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + 20)
            reaper.ImGui_TextColored(ctx, 0x8892B0FF, "   No active MIDI Item selected.")
            reaper.ImGui_TextColored(ctx, 0x666D80FF, "   Click a note in the score canvas or select a MIDI item in REAPER to view and edit velocities.")
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
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0x121418FF)
        if reaper.ImGui_BeginChild(ctx, "VelocityLaneScroll", avail_w, avail_h, child_none, lane_flags) then
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            local scroll_x = reaper.ImGui_GetScrollX(ctx)
            local win_x0, win_y0 = reaper.ImGui_GetWindowPos(ctx)
            local win_w = reaper.ImGui_GetWindowWidth(ctx)
            local win_h = reaper.ImGui_GetWindowHeight(ctx)

            -- Reserve content space to activate scrollbar
            reaper.ImGui_Dummy(ctx, total_content_w, win_h - 18)

            -- Geometry for velocity mapping
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

            local function vel_to_y(v)
                local norm = (math.max(1, math.min(127, v)) - 1) / 126.0
                return plot_bot_y - (norm * plot_h)
            end

            local function y_to_vel(screen_y)
                local norm = (plot_bot_y - screen_y) / plot_h
                return math.max(1, math.min(127, math.floor(1 + (norm * 126.0) + 0.5)))
            end

            -- ==================================================================
            -- 2a. BACKGROUND GRID & TIME LINES
            -- ==================================================================
            -- Horizontal Velocity Guides
            local guides = {
                { 127, "127 (fff)", 0x4A556855 },
                { 96,  "96 (f)",    0x33415544 },
                { 64,  "64 (mp)",   0x33415544 },
                { 32,  "32 (pp)",   0x33415544 },
                { 1,   "1",         0x4A556833 },
            }
            for _, g in ipairs(guides) do
                local gy = vel_to_y(g[1])
                reaper.ImGui_DrawList_AddLine(dl, win_x0, gy, win_x0 + win_w, gy, g[3], 1.0)
                reaper.ImGui_DrawList_AddText(dl, win_x0 + 4, gy - 6, 0x8892B088, tostring(g[1]))
            end

            -- Vertical Measure & Beat Grid
            local bpi = 4.0
            local cur_m_qn = math.floor(it_start_qn / bpi) * bpi
            while cur_m_qn <= it_end_qn + bpi do
                local mx = qn_to_x(cur_m_qn)
                if mx >= win_x0 - 40 and mx <= win_x0 + win_w + 40 then
                    -- Major measure line
                    reaper.ImGui_DrawList_AddLine(dl, mx, plot_top_y - 6, mx, plot_bot_y + 4, 0x4A556866, 1.2)
                    local bar_num = math.floor(cur_m_qn / bpi) + 1
                    reaper.ImGui_DrawList_AddText(dl, mx + 4, plot_top_y - 14, 0x8892B0AA, string.format("Bar %d", bar_num))

                    -- Minor beat lines (1/4 notes)
                    for b = 1, math.floor(bpi) - 1 do
                        local bx = qn_to_x(cur_m_qn + b)
                        if bx >= win_x0 and bx <= win_x0 + win_w then
                            reaper.ImGui_DrawList_AddLine(dl, bx, plot_top_y, bx, plot_bot_y, 0x33415522, 1.0)
                        end
                    end
                end
                cur_m_qn = cur_m_qn + bpi
            end

            -- Baseline
            reaper.ImGui_DrawList_AddLine(dl, win_x0 + left_pad - scroll_x, plot_bot_y, win_x0 + left_pad - scroll_x + (it_len_qn * px_per_qn), plot_bot_y, 0x8892B066, 1.5)

            -- ==================================================================
            -- 2b. MOUSE INPUT & HIT TESTING
            -- ==================================================================
            local is_hovered = reaper.ImGui_IsWindowHovered(ctx)
            local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
            local hovered_note = nil
            local is_shift = reaper.APIExists("ImGui_Mod_Shift") and ((reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Shift()) ~= 0) or false
            local is_ctrl = reaper.APIExists("ImGui_Mod_Ctrl") and ((reaper.ImGui_GetKeyMods(ctx) & reaper.ImGui_Mod_Ctrl()) ~= 0) or false

            -- Check hover on note handles/stalks (prioritize top handles)
            if is_hovered and not is_drawing and not marquee_active then
                for i = #notes, 1, -1 do
                    local n = notes[i]
                    local nx = qn_to_x(n.start_qn)
                    local ny = vel_to_y(n.vel)

                    -- Top handle hitbox: [nx - 6, ny - 8, nx + 12, ny + 8]
                    local in_handle = (mouse_x >= nx - 6 and mouse_x <= nx + 12 and mouse_y >= ny - 8 and mouse_y <= ny + 8)
                    -- Stalk hitbox: [nx - 4, ny, nx + 4, plot_bot_y]
                    local in_stalk = (mouse_x >= nx - 4 and mouse_x <= nx + 4 and mouse_y >= ny and mouse_y <= plot_bot_y + 2)

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

            -- ==================================================================
            -- 2c. POINTER TOOL: DRAGGING & SELECTION
            -- ==================================================================
            if cur_tool == "select" then
                -- Mouse Down: start drag or selection
                if is_hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
                    if hovered_note then
                        -- Handle / Stalk Clicked
                        if is_shift or is_ctrl then
                            state:toggle_note_selection(hovered_note)
                        else
                            if not state:is_note_selected(hovered_note) then
                                state:clear_selection()
                                state:select_note(hovered_note)
                            end
                        end
                        -- Sync take selection
                        midi_service.sync_take_note_selection(active_take, hovered_note.idx, state:is_note_selected(hovered_note), true)

                        -- Start Dragging Velocity
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
                        -- Empty area clicked: Start Marquee Selection
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
                        local cur_v = y_to_vel(mouse_y)
                        local delta_v = cur_v - drag_initial_vel

                        for _, snap in pairs(drag_snapshots) do
                            local n = snap.note
                            local new_v = math.max(1, math.min(127, snap.orig_vel + delta_v))
                            if n.vel ~= new_v then
                                n.vel = new_v
                                midi_service.set_note_velocity(active_take, n.idx, new_v, true)
                            end
                        end

                        -- Audible Audition Feedback (throttled ~80ms)
                        local now = reaper.time_precise()
                        if (now - last_audition_time > 0.08) and (drag_lead_note.vel ~= last_audition_vel) then
                            last_audition_time = now
                            last_audition_vel = drag_lead_note.vel
                            if audio_preview and audio_preview.play_note then
                                audio_preview.play_note(state, drag_lead_note.pitch, drag_lead_note.vel, drag_lead_note.chan or 0, active_track, drag_lead_note.start_qn, drag_lead_note)
                            end
                        end
                    else
                        -- Release Drag
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
                        -- Finalize Marquee Selection
                        marquee_active = false
                        local mx0 = math.min(marquee_start_x, mouse_x)
                        local my0 = math.min(marquee_start_y, mouse_y)
                        local mx1 = math.max(marquee_start_x, mouse_x)
                        local my1 = math.max(marquee_start_y, mouse_y)

                        for _, n in ipairs(notes) do
                            local nx = qn_to_x(n.start_qn)
                            local ny = vel_to_y(n.vel)
                            -- Check if handle or stalk intersects marquee rect
                            local stalk_hit = (nx >= mx0 and nx <= mx1 and my0 <= plot_bot_y and my1 >= ny)
                            local handle_hit = (mx1 >= nx - 4 and mx0 <= nx + 8 and my1 >= ny - 4 and my0 <= ny + 4)
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

            -- ==================================================================
            -- 2d. PENCIL / DRAW TOOL: CONTINUOUS FREEHAND SWEEP
            -- ==================================================================
            if cur_tool == "draw" then
                if is_hovered then
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_TextInput())
                end

                if is_hovered and reaper.ImGui_IsMouseClicked(ctx, 0) then
                    is_drawing = true
                    draw_prev_mx = mouse_x
                    draw_prev_my = mouse_y
                    draw_trail = { { x = mouse_x, y = mouse_y } }
                    reaper.Undo_BeginBlock2(0)
                end

                if is_drawing then
                    if reaper.ImGui_IsMouseDown(ctx, 0) then
                        table.insert(draw_trail, { x = mouse_x, y = mouse_y })
                        if #draw_trail > 60 then table.remove(draw_trail, 1) end

                        local x_min = math.min(draw_prev_mx or mouse_x, mouse_x)
                        local x_max = math.max(draw_prev_mx or mouse_x, mouse_x)

                        -- Apply interpolated velocity to any note falling within [x_min, x_max]
                        for _, n in ipairs(notes) do
                            local nx = qn_to_x(n.start_qn)
                            if nx >= x_min - 4 and nx <= x_max + 4 then
                                local target_y = mouse_y
                                if math.abs(mouse_x - (draw_prev_mx or mouse_x)) > 0.001 then
                                    local t = (nx - (draw_prev_mx or mouse_x)) / (mouse_x - (draw_prev_mx or mouse_x))
                                    t = math.max(0.0, math.min(1.0, t))
                                    target_y = (draw_prev_my or mouse_y) + t * (mouse_y - (draw_prev_my or mouse_y))
                                end
                                local new_v = y_to_vel(target_y)
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
                        -- Finish Drawing
                        is_drawing = false
                        draw_prev_mx = nil
                        draw_prev_my = nil
                        draw_trail = {}
                        reaper.MIDI_Sort(active_take)
                        reaper.UpdateArrange()
                        reaper.Undo_EndBlock2(0, "Draw Note Velocity", -1)
                    end
                end

                -- Render neon glow draw trail
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

            -- ==================================================================
            -- 2e. RENDER VELOCITY STALKS & REAPER "FÄHNCHEN" HANDLES
            -- ==================================================================
            for _, n in ipairs(notes) do
                local nx = qn_to_x(n.start_qn)
                if nx >= win_x0 - 20 and nx <= win_x0 + win_w + 20 then
                    local ny = vel_to_y(n.vel)
                    local is_sel = state:is_note_selected(n)
                    local is_hov = (hovered_note == n)

                    -- Colors
                    local stalk_col = 0x64748BAA
                    local handle_col = 0x94A3B8FF
                    local border_col = 0x1E293BFF
                    local stalk_w = 1.5

                    if is_sel then
                        stalk_col = 0xFF9F1CFF
                        handle_col = 0xFFB703FF
                        border_col = 0x78350FFF
                        stalk_w = 2.0
                    elseif is_hov then
                        stalk_col = 0x38BDF8FF
                        handle_col = 0x7DD3FCFF
                        stalk_w = 2.0
                    end

                    -- 1. Vertical Stalk (Stem)
                    reaper.ImGui_DrawList_AddLine(dl, nx, plot_bot_y, nx, ny, stalk_col, stalk_w)

                    -- 2. REAPER Top Handle Flag ("Fähnchen")
                    -- Horizontal flag tab extending to the right
                    local flag_w = 7.5
                    local flag_h = 6.0
                    local flag_x0 = nx
                    local flag_y0 = ny - (flag_h * 0.5)
                    local flag_x1 = nx + flag_w
                    local flag_y1 = ny + (flag_h * 0.5)

                    -- Flag background
                    reaper.ImGui_DrawList_AddRectFilled(dl, flag_x0, flag_y0, flag_x1, flag_y1, handle_col, 1.5)
                    -- Flag dark outline
                    reaper.ImGui_DrawList_AddRect(dl, flag_x0 - 0.5, flag_y0 - 0.5, flag_x1 + 0.5, flag_y1 + 0.5, border_col, 1.5, 0, 1.0)

                    -- Central bead cap at stem apex
                    local bead_r = is_sel and 4.0 or 3.2
                    reaper.ImGui_DrawList_AddCircleFilled(dl, nx, ny, bead_r, handle_col)
                    reaper.ImGui_DrawList_AddCircle(dl, nx, ny, bead_r, border_col, 0, 1.0)

                    -- Subtle highlight center dot for selected notes
                    if is_sel then
                        reaper.ImGui_DrawList_AddCircleFilled(dl, nx, ny, 1.5, 0xFFFFFFFF)
                    end
                end
            end

            reaper.ImGui_EndChild(ctx)
        end
        reaper.ImGui_PopStyleColor(ctx) -- ChildBg

        reaper.ImGui_EndChild(ctx)
    end
    reaper.ImGui_PopStyleColor(ctx, 2) -- MainPane ChildBg & Border
end

return MidiEditorDrawer

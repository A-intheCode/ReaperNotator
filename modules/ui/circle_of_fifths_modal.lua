-- ==============================================================================
-- REAPER Native Notator - Module: CircleOfFifthsModal
-- Interactive Circle of Fifths & Global Chord Palette Modal:
-- - Vector Circle of Fifths (12 Outer Major + 12 Inner Relative Minor sectors)
-- - Click-to-Audition in the Circle
-- - Drag & Drop from Circle onto 8 Harmonic Tiles (Slot 1..8)
-- - Dynamic Harmonic Tension Calculation & Circle Re-Coloring from Tiles
-- - Multi-Tab Global Chord Palette persisted across all REAPER projects
-- ==============================================================================

local CircleOfFifthsService = package.loaded["services.circle_of_fifths_service"] or require("services.circle_of_fifths_service")
local KeySignatureService = package.loaded["services.key_signature_service"] or require("services.key_signature_service")
local AudioPreview = package.loaded["services.audio_preview"] or require("services.audio_preview")
local Engraver = package.loaded["rendering.engraver"] or require("rendering.engraver")

local CircleOfFifthsModal = {}

local QUALITY_OPTIONS = {
    { id = "auto",   label = "Auto (Outer=Maj, Inner=Min)" },
    { id = "single", label = "Single Note (Root Only)" },
    { id = "major",  label = "Major Triad (1-3-5)" },
    { id = "minor",  label = "Minor Triad (1-b3-5)" },
    { id = "dim",    label = "Diminished (1-b3-b5)" },
    { id = "aug",    label = "Augmented (1-3-#5)" },
    { id = "maj7",   label = "Major 7th (Maj7)" },
    { id = "m7",     label = "Minor 7th (m7)" },
    { id = "dom7",   label = "Dominant 7th (7)" },
    { id = "sus2",   label = "Suspended 2nd (sus2)" },
    { id = "sus4",   label = "Suspended 4th (sus4)" },
    { id = "power5", label = "Power Chord (1-5)" }
}

--- Helper to ensure a 0xRRGGBBAA color is 100% opaque (blended over #16191E if alpha < 255)
local function ensure_opaque_color(col)
    local a = (col or 0xFF) & 0xFF
    if a >= 0xFF then return col end
    local r = (col >> 24) & 0xFF
    local g = (col >> 16) & 0xFF
    local b = (col >> 8)  & 0xFF
    local alpha = a / 255.0
    local bg_r, bg_g, bg_b = 0x16, 0x19, 0x1E
    local out_r = math.floor(r * alpha + bg_r * (1.0 - alpha) + 0.5)
    local out_g = math.floor(g * alpha + bg_g * (1.0 - alpha) + 0.5)
    local out_b = math.floor(b * alpha + bg_b * (1.0 - alpha) + 0.5)
    return (out_r << 24) | (out_g << 16) | (out_b << 8) | 0xFF
end

--- Helper to draw a seamless filled annular sector (ring wedge) without internal radial AA seams.
--- By using 100% opaque fill colors and overlapping internal quad strip angles (`da * 0.38`),
--- each sub-quad's 0.5px anti-aliased fringe lands inside the 100%-opaque solid interior
--- of the neighboring sub-quad of identical color C: a*C + (1-a)*C = C (zero visible seams).
local function draw_annular_sector(dl, cx, cy, r_in, r_out, a0, a1, fill_col, border_col, border_thickness)
    local opaque_fill = ensure_opaque_color(fill_col)
    local steps = 24
    local da = (a1 - a0) / steps
    local overlap = da * 0.38
    for s = 0, steps - 1 do
        local t0 = a0 + s * da
        local t1 = t0 + da
        local t0_draw = (s > 0) and (t0 - overlap) or t0
        local t1_draw = (s < steps - 1) and (t1 + overlap) or t1
        local c0, s0 = math.cos(t0_draw), math.sin(t0_draw)
        local c1, s1 = math.cos(t1_draw), math.sin(t1_draw)
        local x1, y1 = cx + r_in * c0,  cy + r_in * s0
        local x2, y2 = cx + r_out * c0, cy + r_out * s0
        local x3, y3 = cx + r_out * c1, cy + r_out * s1
        local x4, y4 = cx + r_in * c1,  cy + r_in * s1
        reaper.ImGui_DrawList_AddQuadFilled(dl, x1, y1, x2, y2, x3, y3, x4, y4, opaque_fill)
    end

    if border_col and (border_thickness or 1) > 0 then
        local bt = border_thickness or 1.5
        -- Outer and Inner arcs
        for s = 0, steps - 1 do
            local t0 = a0 + s * da
            local t1 = t0 + da
            reaper.ImGui_DrawList_AddLine(dl,
                cx + r_out * math.cos(t0), cy + r_out * math.sin(t0),
                cx + r_out * math.cos(t1), cy + r_out * math.sin(t1),
                border_col, bt)
            reaper.ImGui_DrawList_AddLine(dl,
                cx + r_in * math.cos(t0), cy + r_in * math.sin(t0),
                cx + r_in * math.cos(t1), cy + r_in * math.sin(t1),
                border_col, bt)
        end
        -- Radial spokes at sector boundaries only
        reaper.ImGui_DrawList_AddLine(dl,
            cx + r_in * math.cos(a0), cy + r_in * math.sin(a0),
            cx + r_out * math.cos(a0), cy + r_out * math.sin(a0),
            border_col, bt)
        reaper.ImGui_DrawList_AddLine(dl,
            cx + r_in * math.cos(a1), cy + r_in * math.sin(a1),
            cx + r_out * math.cos(a1), cy + r_out * math.sin(a1),
            border_col, bt)
    end
end

--- Returns a formatted human-readable label for a REAPER MediaTrack
local function get_track_display_label(trk, idx_1based)
    if not trk or (reaper.ValidatePtr and not reaper.ValidatePtr(trk, "MediaTrack*")) then
        return "None"
    end
    local num = idx_1based
    if not num and reaper.GetMediaTrackInfo_Value then
        num = math.floor(reaper.GetMediaTrackInfo_Value(trk, "IP_TRACKNUMBER") or 1)
    end
    local name = ""
    if reaper.GetTrackName then
        local _, tname = reaper.GetTrackName(trk)
        name = tname or ""
    end
    local fx_badge = ""
    if reaper.TrackFX_GetInstrument and reaper.TrackFX_GetInstrument(trk) >= 0 then
        fx_badge = " 🎹"
    elseif reaper.TrackFX_GetCount and reaper.TrackFX_GetCount(trk) > 0 then
        fx_badge = " 🔊"
    end
    return string.format("Track %d: %s%s", num or 1, name ~= "" and name or "Instrument", fx_badge)
end

--- Formats a tile's pitches as readable note names using its key signature
local function format_tile_pitches(tile)
    if not tile or not tile.pitches or #tile.pitches == 0 then
        return ""
    end
    local key_idx = tile.key_sig_idx or 0
    local parts = {}
    for _, p in ipairs(tile.pitches) do
        if Engraver and Engraver.get_pitch_display_name then
            local pname, poct = Engraver.get_pitch_display_name(p, nil, key_idx)
            table.insert(parts, tostring(pname or "C") .. tostring(poct or 4))
        else
            table.insert(parts, tostring(p))
        end
    end
    return table.concat(parts, " · ")
end

--- Ensures `state.cof_pages` is loaded from global REAPER ExtState
local function ensure_palettes_loaded(state)
    if not state.cof_pages or #state.cof_pages == 0 then
        state.cof_pages = CircleOfFifthsService.load_palettes()
        state.cof_active_page_idx = 1
    end
    if not state.cof_active_page_idx or state.cof_active_page_idx < 1 or state.cof_active_page_idx > #state.cof_pages then
        state.cof_active_page_idx = 1
    end
    if not state.cof_voicing_mode then
        state.cof_voicing_mode = "auto"
    end
    if not state.cof_octave then
        state.cof_octave = 4
    end
end

function CircleOfFifthsModal.render(ctx, state, midi_service)
    if not state or not state.show_circle_of_fifths_modal then return end

    ensure_palettes_loaded(state)

    local flags = reaper.ImGui_WindowFlags_NoCollapse()
    if reaper.APIExists("ImGui_WindowFlags_TopMost") then
        flags = flags | reaper.ImGui_WindowFlags_TopMost()
    end

    if reaper.APIExists("ImGui_SetNextWindowSizeConstraints") then
        reaper.ImGui_SetNextWindowSizeConstraints(ctx, 880, 580, 1450, 960)
    end
    reaper.ImGui_SetNextWindowSize(ctx, 960, 640, reaper.ImGui_Cond_FirstUseEver())

    local visible, open = reaper.ImGui_Begin(ctx, "🎡 Circle of Fifths & Global Harmonic Chord Palette###CircleOfFifthsModalWindow", true, flags)
    if not open then
        state.show_circle_of_fifths_modal = false
        state._cof_drag_payload = nil
        if AudioPreview and AudioPreview.restore_all_tracks then
            AudioPreview.restore_all_tracks()
        end
    end

    if visible then
        local page = state.cof_pages[state.cof_active_page_idx]
        if not page then
            page = state.cof_pages[1]
            state.cof_active_page_idx = 1
        end

        -- Validate explicit preview track pointer if set
        if state.cof_preview_track and reaper.ValidatePtr and not reaper.ValidatePtr(state.cof_preview_track, "MediaTrack*") then
            state.cof_preview_track = nil
        end

        -- Resolve current audition & insertion target track and keep it armed while modal is active!
        local resolved_trk = CircleOfFifthsService.resolve_audition_track(state)
        if resolved_trk and AudioPreview and AudioPreview.prepare_track then
            if AudioPreview.prepared_track ~= resolved_trk then
                if AudioPreview.prepared_track then
                    AudioPreview.restore_track(AudioPreview.prepared_track)
                end
                AudioPreview.prepare_track(resolved_trk)
            end
            AudioPreview.last_activity_time = reaper.time_precise()
        end

        -- Compute dynamic harmonic tension map from the current page's tiles
        local tension_map = CircleOfFifthsService.compute_tension_map(page.tiles, page.active_slot)

        -- ======================================================================
        -- TOP TOOLBAR ROW 1: AUDITION & TARGET TRACK SELECTOR + VOICING + OCTAVE
        -- ======================================================================
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, "🔊 Audition & Target Track:")
        reaper.ImGui_SameLine(ctx, 0, 6)
        reaper.ImGui_SetNextItemWidth(ctx, 235)
        local cur_trk_label = "⚡ Auto (" .. get_track_display_label(resolved_trk) .. ")"
        if state.cof_preview_track then
            cur_trk_label = get_track_display_label(state.cof_preview_track)
        end
        if reaper.ImGui_BeginCombo(ctx, "##CoFAuditionTrackCombo", cur_trk_label) then
            local is_auto = (state.cof_preview_track == nil)
            local auto_target = CircleOfFifthsService.resolve_audition_track({})
            if reaper.ImGui_Selectable(ctx, "⚡ Auto (" .. get_track_display_label(auto_target) .. ")", is_auto) then
                state.cof_preview_track = nil
                local new_trk = CircleOfFifthsService.resolve_audition_track(state)
                if new_trk and AudioPreview and AudioPreview.prepare_track then
                    if AudioPreview.prepared_track and AudioPreview.prepared_track ~= new_trk then
                        AudioPreview.restore_track(AudioPreview.prepared_track)
                    end
                    AudioPreview.prepare_track(new_trk)
                end
            end
            reaper.ImGui_Separator(ctx)
            local trk_cnt = reaper.CountTracks and reaper.CountTracks(0) or 0
            for ti = 0, trk_cnt - 1 do
                local t_ptr = reaper.GetTrack(0, ti)
                if t_ptr then
                    local t_lbl = get_track_display_label(t_ptr, ti + 1)
                    local is_sel = (state.cof_preview_track == t_ptr)
                    if reaper.ImGui_Selectable(ctx, t_lbl .. "##CoFTrk_" .. ti, is_sel) then
                        state.cof_preview_track = t_ptr
                        state.focused_track = t_ptr
                        if AudioPreview and AudioPreview.prepare_track then
                            if AudioPreview.prepared_track and AudioPreview.prepared_track ~= t_ptr then
                                AudioPreview.restore_track(AudioPreview.prepared_track)
                            end
                            AudioPreview.prepare_track(t_ptr)
                        end
                        -- Play a quick C4 test note on the newly selected track
                        local test_tile = tension_map.ref_tile or CircleOfFifthsService.create_tile(1, "major", state.cof_voicing_mode ~= "auto" and state.cof_voicing_mode or "major", state.cof_octave or 4)
                        CircleOfFifthsService.audition_tile(state, test_tile, t_ptr)
                    end
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Select which REAPER Instrument Track is automatically armed & used for auditioning and inserting chords from the Circle of Fifths.\n(🎹 = Virtual Instrument detected, 🔊 = FX chain present)")
        end

        reaper.ImGui_SameLine(ctx, 0, 6)
        if reaper.ImGui_Button(ctx, "🔊 Test##CoFTestAuditionBtn", 58, 0) then
            local test_tile = tension_map.ref_tile or CircleOfFifthsService.create_tile(1, "major", state.cof_voicing_mode ~= "auto" and state.cof_voicing_mode or "major", state.cof_octave or 4)
            CircleOfFifthsService.audition_tile(state, test_tile, resolved_trk)
            state.status_msg = string.format("🔊 Auditioning %s on %s", test_tile.label or "C", get_track_display_label(resolved_trk))
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Play a test chord on the selected Audition Track right now.")
        end

        reaper.ImGui_SameLine(ctx, 0, 14)
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Mode:")
        reaper.ImGui_SameLine(ctx, 0, 6)
        reaper.ImGui_SetNextItemWidth(ctx, 195)
        local cur_q_label = "Auto (Outer=Maj, Inner=Min)"
        for _, qopt in ipairs(QUALITY_OPTIONS) do
            if qopt.id == state.cof_voicing_mode then
                cur_q_label = qopt.label
                break
            end
        end
        if reaper.ImGui_BeginCombo(ctx, "##CoFVoicingCombo", cur_q_label) then
            for _, qopt in ipairs(QUALITY_OPTIONS) do
                if reaper.ImGui_Selectable(ctx, qopt.label, qopt.id == state.cof_voicing_mode) then
                    state.cof_voicing_mode = qopt.id
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Selects whether clicking/dragging a sector in the Circle of Fifths auditions & drops a Single Note, Triad, or 7th/Sus Chord.")
        end

        reaper.ImGui_SameLine(ctx, 0, 12)
        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Octave:")
        reaper.ImGui_SameLine(ctx, 0, 6)
        reaper.ImGui_SetNextItemWidth(ctx, 70)
        local oct_str = string.format("C%d", state.cof_octave or 4)
        if reaper.ImGui_BeginCombo(ctx, "##CoFOctaveCombo", oct_str) then
            for oct = 2, 6 do
                if reaper.ImGui_Selectable(ctx, string.format("Octave %d (C%d)", oct, oct), (state.cof_octave or 4) == oct) then
                    state.cof_octave = oct
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        -- TOP TOOLBAR ROW 2: HARMONIC TENSION LEGEND
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, "● Consonance (0-25%)")
        reaper.ImGui_SameLine(ctx, 0, 14)
        reaper.ImGui_TextColored(ctx, 0xF1C40FFF, "● Subdom/Mediant (26-50%)")
        reaper.ImGui_SameLine(ctx, 0, 14)
        reaper.ImGui_TextColored(ctx, 0xE67E22FF, "● Secondary/Borrowed (51-75%)")
        reaper.ImGui_SameLine(ctx, 0, 14)
        reaper.ImGui_TextColored(ctx, 0xE74C3CFF, "● Tritone Tension (76-100%)")

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ======================================================================
        -- MAIN SPLIT LAYOUT: LEFT = VECTOR CIRCLE OF FIFTHS | RIGHT = TABS & 8 TILES
        -- ======================================================================
        local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
        local left_w = 390
        local right_w = math.max(420, avail_w - left_w - 14)
        local panel_h = math.max(460, avail_h - 6)
        local child_border = reaper.APIExists("ImGui_ChildFlags_Border") and reaper.ImGui_ChildFlags_Border() or 1

        -- ----------------------------------------------------------------------
        -- LEFT PANEL: INTERACTIVE VECTOR CIRCLE OF FIFTHS
        -- ----------------------------------------------------------------------
        if reaper.ImGui_BeginChild(ctx, "##CoFCirclePanel", left_w, panel_h, child_border) then
            local ok_c, err_c = pcall(function()
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "🎡 Interactive Circle of Fifths")
            reaper.ImGui_TextDisabled(ctx, "Left-Click: Hear Tone • Drag & Drop onto Tile 1..8")
            reaper.ImGui_Spacing(ctx)

            local c_pos_x, c_pos_y = reaper.ImGui_GetCursorScreenPos(ctx)
            local canvas_w = left_w - 16
            local canvas_h = 376
            local cx = c_pos_x + canvas_w * 0.5
            local cy = c_pos_y + canvas_h * 0.5

            local r_outer_max = 172
            local r_outer_min = 114
            local r_inner_max = 110
            local r_inner_min = 54
            local r_hub       = 50

            -- Reserve interactive area via InvisibleButton
            reaper.ImGui_InvisibleButton(ctx, "##CoFWheelCanvasBtn", canvas_w, canvas_h)
            local is_wheel_hovered = reaper.ImGui_IsItemHovered(ctx)
            local mx, my = reaper.ImGui_GetMousePos(ctx)

            -- Polar hit-testing relative to (cx, cy)
            local dx = mx - cx
            local dy = my - cy
            local dist = math.sqrt(dx * dx + dy * dy)
            local hovered_ring = nil
            local hovered_idx = nil

            if is_wheel_hovered and dist >= r_inner_min and dist <= r_outer_max then
                -- Angle with 12 o'clock (-pi/2) as center of sector 1
                local angle = math.atan(dy, dx) -- [-pi, pi]
                local rel_a = angle - (-math.pi * 0.5) + (math.pi / 12.0)
                local two_pi = math.pi * 2.0
                rel_a = rel_a % two_pi
                if rel_a < 0 then rel_a = rel_a + two_pi end
                local sec = math.floor(rel_a / (math.pi / 6.0)) + 1
                if sec < 1 then sec = 1 elseif sec > 12 then sec = 12 end

                if dist >= r_outer_min and dist <= r_outer_max then
                    hovered_ring = "major"
                    hovered_idx = sec
                elseif dist >= r_inner_min and dist <= r_inner_max then
                    hovered_ring = "minor"
                    hovered_idx = sec
                end
            end

            local dl = reaper.ImGui_GetWindowDrawList(ctx)

            -- Draw subtle background halo
            reaper.ImGui_DrawList_AddCircleFilled(dl, cx, cy, r_outer_max + 5, 0x16191EFF, 64)

            -- Draw all 12 sectors (Outer Major + Inner Minor)
            local step_angle = (math.pi * 2.0) / 12.0
            for idx = 1, 12 do
                local center_a = -math.pi * 0.5 + (idx - 1) * step_angle
                local a0 = center_a - step_angle * 0.5 + 0.012
                local a1 = center_a + step_angle * 0.5 - 0.012

                local sec_data = CircleOfFifthsService.SECTORS[idx]
                local maj_t = tension_map.major[idx] or { color = 0x2ECC71FF, tension = 0, relation = "Diatonic" }
                local min_t = tension_map.minor[idx] or { color = 0x27AE60FF, tension = 0, relation = "Diatonic" }

                local is_maj_hov = (hovered_ring == "major" and hovered_idx == idx)
                local is_min_hov = (hovered_ring == "minor" and hovered_idx == idx)

                local maj_fill = maj_t.color
                if is_maj_hov then
                    maj_fill = (maj_fill & 0xFFFFFF00) | 0xFF
                end
                local maj_border = maj_t.is_reference and 0xFFD700FF or (is_maj_hov and 0xFFFFFFFF or 0x1A1D24FF)
                local maj_b_thick = (maj_t.is_reference or is_maj_hov) and 2.6 or 1.2

                draw_annular_sector(dl, cx, cy, r_outer_min, r_outer_max, a0, a1, maj_fill, maj_border, maj_b_thick)

                local min_fill = min_t.color
                if is_min_hov then
                    min_fill = (min_fill & 0xFFFFFF00) | 0xFF
                end
                local min_border = min_t.is_reference and 0xFFD700FF or (is_min_hov and 0xFFFFFFFF or 0x1A1D24FF)
                local min_b_thick = (min_t.is_reference or is_min_hov) and 2.6 or 1.2

                draw_annular_sector(dl, cx, cy, r_inner_min, r_inner_max, a0, a1, min_fill, min_border, min_b_thick)

                -- Sector Labels (Major on Outer Ring, Minor on Inner Ring)
                local r_maj_lbl = (r_outer_min + r_outer_max) * 0.5
                local mx_lbl = cx + r_maj_lbl * math.cos(center_a)
                local my_lbl = cy + r_maj_lbl * math.sin(center_a)
                local maj_tw, maj_th = reaper.ImGui_CalcTextSize(ctx, sec_data.major_label)
                reaper.ImGui_DrawList_AddText(dl, mx_lbl - maj_tw * 0.5, my_lbl - maj_th * 0.5 - 5, 0xFFFFFFFF, sec_data.major_label)

                -- Small Key Sig / Tension % sub-label on Outer Ring
                local sub_txt = tension_map.has_reference and string.format("%d%%", math.floor(maj_t.tension * 100 + 0.5)) or sec_data.acc_label
                local sub_tw, sub_th = reaper.ImGui_CalcTextSize(ctx, sub_txt)
                reaper.ImGui_DrawList_AddText(dl, mx_lbl - sub_tw * 0.5, my_lbl + maj_th * 0.5 - 6, 0xEAEAEAFF, sub_txt)

                -- Inner Ring Minor Label
                local r_min_lbl = (r_inner_min + r_inner_max) * 0.5
                local inx_lbl = cx + r_min_lbl * math.cos(center_a)
                local iny_lbl = cy + r_min_lbl * math.sin(center_a)
                local min_tw, min_th = reaper.ImGui_CalcTextSize(ctx, sec_data.minor_label)
                reaper.ImGui_DrawList_AddText(dl, inx_lbl - min_tw * 0.5, iny_lbl - min_th * 0.5 - 4, 0xFFFFFFFF, sec_data.minor_label)

                if tension_map.has_reference then
                    local msub_txt = string.format("%d%%", math.floor(min_t.tension * 100 + 0.5))
                    local msub_tw, msub_th = reaper.ImGui_CalcTextSize(ctx, msub_txt)
                    reaper.ImGui_DrawList_AddText(dl, inx_lbl - msub_tw * 0.5, iny_lbl + min_th * 0.5 - 6, 0xE0E0E0FF, msub_txt)
                end
            end

            -- Draw Center Hub showing active reference Tile
            reaper.ImGui_DrawList_AddCircleFilled(dl, cx, cy, r_hub, 0x20242CFF, 48)
            reaper.ImGui_DrawList_AddCircle(dl, cx, cy, r_hub, 0x556070FF, 48, 2.0)

            local ref_tile = tension_map.ref_tile
            if ref_tile then
                local hub_top = string.format("Slot #%d", tension_map.ref_slot or 1)
                local htw1, _ = reaper.ImGui_CalcTextSize(ctx, hub_top)
                reaper.ImGui_DrawList_AddText(dl, cx - htw1 * 0.5, cy - 22, 0xFF9F1CFF, hub_top)

                local hub_main = ref_tile.label or "C"
                local htw2, _ = reaper.ImGui_CalcTextSize(ctx, hub_main)
                reaper.ImGui_DrawList_AddText(dl, cx - htw2 * 0.5, cy - 6, 0xFFFFFFFF, hub_main)

                local sec_ref = CircleOfFifthsService.SECTORS[ref_tile.sector_idx or 1]
                local hub_sub = sec_ref and sec_ref.acc_label or "0"
                local htw3, _ = reaper.ImGui_CalcTextSize(ctx, hub_sub)
                reaper.ImGui_DrawList_AddText(dl, cx - htw3 * 0.5, cy + 11, 0x85C1E9FF, hub_sub)
            else
                local h1 = "Click or"
                local h2 = "Drag Note"
                local tw1, _ = reaper.ImGui_CalcTextSize(ctx, h1)
                local tw2, _ = reaper.ImGui_CalcTextSize(ctx, h2)
                reaper.ImGui_DrawList_AddText(dl, cx - tw1 * 0.5, cy - 13, 0xAAAAAAFF, h1)
                reaper.ImGui_DrawList_AddText(dl, cx - tw2 * 0.5, cy + 3, 0xAAAAAAFF, h2)
            end

            -- Hover Tooltip & Click-to-Audition + Drag Start on Sector
            if hovered_ring and hovered_idx then
                local sec_data = CircleOfFifthsService.SECTORS[hovered_idx]
                local t_info = tension_map[hovered_ring][hovered_idx]
                local q_ovr = (state.cof_voicing_mode ~= "auto") and state.cof_voicing_mode or nil
                local preview_tile = CircleOfFifthsService.create_tile(hovered_idx, hovered_ring, q_ovr, state.cof_octave or 4)

                if preview_tile then
                    local t_pct = math.floor(((t_info and t_info.tension) or 0) * 100 + 0.5)
                    local rel_str = (t_info and t_info.relation) or "Diatonic"
                    reaper.ImGui_SetTooltip(ctx, string.format(
                        "🎵 %s  (%s)\nKey Signature: %s\nNotes: %s\nHarmonic Relation: %s\nTension from Reference: %d%%\nTarget Track: %s\n\n• Left-Click / Drag: Hear Tone on Track\n• Drag & Drop onto Slot 1..8 to assign & recalculate Circle!",
                        preview_tile.label,
                        preview_tile.quality_label or "",
                        sec_data.acc_label,
                        format_tile_pitches(preview_tile),
                        rel_str,
                        t_pct,
                        get_track_display_label(resolved_trk)
                    ))

                    local sector_changed_while_dragging = state._cof_drag_payload
                        and reaper.ImGui_IsMouseDown(ctx, 0)
                        and (state._cof_drag_payload.sector_idx ~= hovered_idx or state._cof_drag_payload.ring ~= hovered_ring)

                    if reaper.ImGui_IsMouseClicked(ctx, 0) or sector_changed_while_dragging then
                        -- 1. Play tone immediately when clicked or swept in the Circle!
                        CircleOfFifthsService.audition_tile(state, preview_tile, resolved_trk)
                        -- 2. Start / update Drag & Drop payload
                        state._cof_drag_payload = preview_tile
                        state.status_msg = string.format("🎵 Auditioning %s (%s) on %s – Drag onto a Tile (Slot 1..8) to add to palette",
                            preview_tile.label, format_tile_pitches(preview_tile), get_track_display_label(resolved_trk))
                    end
                end
            end

            -- Info footer inside left panel
            reaper.ImGui_Spacing(ctx)
            if ref_tile then
                reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format("Active Tension Origin: Slot #%d (%s)", tension_map.ref_slot or 1, ref_tile.label))
            else
                reaper.ImGui_TextDisabled(ctx, "Drop a note/chord onto any tile to compute harmonic tension.")
            end
            end)
            if not ok_c and reaper.ShowConsoleMsg then
                reaper.ShowConsoleMsg("[CircleOfFifthsModal LeftPanel Error] " .. tostring(err_c) .. "\n")
            end
            reaper.ImGui_EndChild(ctx)
        end

        reaper.ImGui_SameLine(ctx, 0, 12)

        -- ----------------------------------------------------------------------
        -- RIGHT PANEL: GLOBAL CHORD PALETTE TABS & 8 TILES (SLOT 1..8)
        -- ----------------------------------------------------------------------
        if reaper.ImGui_BeginChild(ctx, "##CoFTilesPanel", right_w, panel_h, child_border) then
            local ok_r, err_r = pcall(function()
            -- 1. PALETTE TAB BAR (Global in REAPER)
            reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "🗂 Global Chord Palette Pages (Saved Globally in REAPER):")
            reaper.ImGui_Spacing(ctx)

            for pidx, p in ipairs(state.cof_pages) do
                local is_act_tab = (pidx == state.cof_active_page_idx)
                if is_act_tab then
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2980B9FF)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3498DBFF)
                else
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2C3E50FF)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3D566EFF)
                end

                local tab_lbl = string.format("%s##CoFTab_%d", p.name or ("Palette " .. pidx), pidx)
                if reaper.ImGui_Button(ctx, tab_lbl, 0, 26) then
                    state.cof_active_page_idx = pidx
                    page = state.cof_pages[pidx]
                    tension_map = CircleOfFifthsService.compute_tension_map(page.tiles, page.active_slot)
                end
                reaper.ImGui_PopStyleColor(ctx, 2)
                reaper.ImGui_SameLine(ctx, 0, 6)
            end

            -- "+" Button to add a new Tab page
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
            if reaper.ImGui_Button(ctx, "➕ New Tab##CoFAddTabBtn", 85, 26) then
                local _, new_idx = CircleOfFifthsService.add_page(state.cof_pages, string.format("Palette %d", #state.cof_pages + 1))
                state.cof_active_page_idx = new_idx
                page = state.cof_pages[new_idx]
                tension_map = CircleOfFifthsService.compute_tension_map(page.tiles, page.active_slot)
                state.status_msg = string.format("Created new global chord palette tab '%s'", page.name)
            end
            reaper.ImGui_PopStyleColor(ctx, 2)
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Add a new 8-tile Chord Palette page (persisted globally across REAPER projects).")
            end

            -- Delete current Tab page button (if > 1 page)
            if #state.cof_pages > 1 then
                reaper.ImGui_SameLine(ctx, 0, 6)
                if reaper.ImGui_Button(ctx, "🗑##CoFDelTabBtn", 28, 26) then
                    state.cof_active_page_idx = CircleOfFifthsService.delete_page(state.cof_pages, state.cof_active_page_idx)
                    page = state.cof_pages[state.cof_active_page_idx]
                    tension_map = CircleOfFifthsService.compute_tension_map(page.tiles, page.active_slot)
                end
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx, "Delete current Palette Tab page")
                end
            end

            reaper.ImGui_NewLine(ctx)

            -- Page Rename Row
            reaper.ImGui_Text(ctx, "Palette Name:")
            reaper.ImGui_SameLine(ctx, 0, 8)
            reaper.ImGui_SetNextItemWidth(ctx, 200)
            local chg_name, new_name = reaper.ImGui_InputText(ctx, "##CoFPageNameInput", page.name or "Palette")
            if chg_name then
                page.name = new_name
                CircleOfFifthsService.save_palettes(state.cof_pages)
            end

            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            -- 2. THE 8 TILES (2 ROWS x 4 COLUMNS)
            local grid_avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
            local gap_x = 10
            local gap_y = 10
            local card_w = math.floor((grid_avail_w - gap_x * 3) / 4)
            local card_h = 135
            local dl_panel = reaper.ImGui_GetWindowDrawList(ctx)

            for slot = 1, 8 do
                local col = (slot - 1) % 4
                if col > 0 then
                    reaper.ImGui_SameLine(ctx, 0, gap_x)
                elseif slot > 1 then
                    reaper.ImGui_Dummy(ctx, 0, gap_y - 4)
                end

                local tile = page.tiles[slot]
                local is_active_slot = (tension_map.ref_slot == slot) and (tile ~= nil)

                local sx, sy = reaper.ImGui_GetCursorScreenPos(ctx)
                reaper.ImGui_InvisibleButton(ctx, string.format("##CoFTileSlot_%d", slot), card_w, card_h)
                local is_tile_hovered = reaper.ImGui_IsItemHovered(ctx)
                local is_tile_clicked = reaper.ImGui_IsItemClicked(ctx, 0)
                local is_tile_rclicked = reaper.ImGui_IsItemClicked(ctx, 1)

                -- Check if a dragged sector from the Circle of Fifths is hovering or dropped on this tile!
                local is_drag_target = (state._cof_drag_payload ~= nil) and is_tile_hovered
                if is_drag_target and not reaper.ImGui_IsMouseDown(ctx, 0) then
                    -- DROP COMPLETE onto Slot `slot`!
                    local dropped = state._cof_drag_payload
                    page.tiles[slot] = CircleOfFifthsService.create_tile(
                        dropped.sector_idx,
                        dropped.ring,
                        dropped.quality,
                        dropped.octave
                    )
                    page.active_slot = slot
                    CircleOfFifthsService.save_palettes(state.cof_pages)
                    CircleOfFifthsService.audition_tile(state, page.tiles[slot])
                    tension_map = CircleOfFifthsService.compute_tension_map(page.tiles, page.active_slot)
                    tile = page.tiles[slot]
                    is_active_slot = true
                    state.status_msg = string.format("🎡 Dropped %s into Slot #%d – Harmonic tension recalculated in Circle of Fifths!",
                        tile.label, slot)
                    state._cof_drag_payload = nil
                end

                -- Left-click on a populated tile: set as active reference (recalculates Circle tension!) & audition
                if is_tile_clicked and tile and not state._cof_drag_payload then
                    page.active_slot = slot
                    CircleOfFifthsService.save_palettes(state.cof_pages)
                    CircleOfFifthsService.audition_tile(state, tile)
                    tension_map = CircleOfFifthsService.compute_tension_map(page.tiles, page.active_slot)
                    is_active_slot = true
                    state.status_msg = string.format("🎵 Slot #%d (%s) active – Circle of Fifths re-colored for following harmony",
                        slot, tile.label)
                end

                if is_tile_rclicked then
                    reaper.ImGui_OpenPopup(ctx, string.format("CoFTileContextMenu_%d", slot))
                end

                -- Card Background & Border
                local bg_col = tile and 0x252B37FF or 0x1B1F27FF
                if is_drag_target then
                    bg_col = 0x2C4A3EFF
                elseif is_active_slot then
                    bg_col = 0x2B384EFF
                elseif is_tile_hovered and tile then
                    bg_col = 0x2E3646FF
                end

                local border_col = 0x3D4656FF
                local border_w = 1.5
                if is_drag_target then
                    border_col = 0x2ECC71FF
                    border_w = 3.0
                elseif is_active_slot then
                    border_col = 0xFFD700FF
                    border_w = 2.6
                elseif tile then
                    border_col = 0x5D6D7EFF
                end

                reaper.ImGui_DrawList_AddRectFilled(dl_panel, sx, sy, sx + card_w, sy + card_h, bg_col, 6.0)
                reaper.ImGui_DrawList_AddRect(dl_panel, sx, sy, sx + card_w, sy + card_h, border_col, 6.0, 0, border_w)

                -- Slot Header Badge (#1..#8)
                local hdr_str = is_active_slot and string.format("★ SLOT #%d", slot) or string.format("SLOT #%d", slot)
                local hdr_col = is_active_slot and 0xFFD700FF or 0x95A5A6FF
                reaper.ImGui_DrawList_AddText(dl_panel, sx + 8, sy + 7, hdr_col, hdr_str)

                -- Step-to-Step Tension Badge (relative to previous populated tile)
                local step_t = tension_map.tile_step_tensions and tension_map.tile_step_tensions[slot]
                if tile and step_t then
                    local st_pct = string.format("%d%%", math.floor(step_t.tension * 100 + 0.5))
                    local st_w, _ = reaper.ImGui_CalcTextSize(ctx, st_pct)
                    reaper.ImGui_DrawList_AddRectFilled(dl_panel, sx + card_w - st_w - 14, sy + 5, sx + card_w - 5, sy + 23, step_t.color, 4.0)
                    reaper.ImGui_DrawList_AddText(dl_panel, sx + card_w - st_w - 9, sy + 7, 0xFFFFFFFF, st_pct)
                end

                if tile then
                    -- Main Chord / Note Label
                    local main_lbl = tile.label or "C"
                    local m_tw, _ = reaper.ImGui_CalcTextSize(ctx, main_lbl)
                    reaper.ImGui_DrawList_AddText(dl_panel, sx + (card_w - m_tw) * 0.5, sy + 36, 0xFFFFFFFF, main_lbl)

                    -- Quality Subtitle
                    local q_lbl = tile.quality_label or "Major"
                    local q_tw, _ = reaper.ImGui_CalcTextSize(ctx, q_lbl)
                    reaper.ImGui_DrawList_AddText(dl_panel, sx + (card_w - q_tw) * 0.5, sy + 58, 0x85C1E9FF, q_lbl)

                    -- Pitches string
                    local p_str = format_tile_pitches(tile)
                    local p_tw, _ = reaper.ImGui_CalcTextSize(ctx, p_str)
                    if p_tw > card_w - 10 then
                        p_str = p_str:sub(1, 16) .. ".."
                        p_tw, _ = reaper.ImGui_CalcTextSize(ctx, p_str)
                    end
                    reaper.ImGui_DrawList_AddText(dl_panel, sx + (card_w - p_tw) * 0.5, sy + 82, 0xBDC3C7FF, p_str)

                    -- Footer hint inside tile
                    local ft_str = is_active_slot and "Active Reference" or "Click: Audition • R-Click: Edit"
                    local ft_tw, _ = reaper.ImGui_CalcTextSize(ctx, ft_str)
                    reaper.ImGui_DrawList_AddText(dl_panel, sx + (card_w - ft_tw) * 0.5, sy + card_h - 22,
                        is_active_slot and 0x2ECC71FF or 0x7F8C8DFF, ft_str)
                else
                    local emp1 = "Empty Tile"
                    local emp2 = "Drag Note Here"
                    local e1w, _ = reaper.ImGui_CalcTextSize(ctx, emp1)
                    local e2w, _ = reaper.ImGui_CalcTextSize(ctx, emp2)
                    reaper.ImGui_DrawList_AddText(dl_panel, sx + (card_w - e1w) * 0.5, sy + 50, 0x566573FF, emp1)
                    reaper.ImGui_DrawList_AddText(dl_panel, sx + (card_w - e2w) * 0.5, sy + 70, 0x566573FF, emp2)
                end

                -- Tooltip on Tile Hover
                if is_tile_hovered and tile and not state._cof_drag_payload then
                    local st_txt = step_t and string.format("\nStep Tension from previous tile: %d%% (%s)",
                        math.floor(step_t.tension * 100 + 0.5), step_t.relation) or ""
                    reaper.ImGui_SetTooltip(ctx, string.format(
                        "Slot #%d: %s (%s)\nNotes: %s%s\n\n• Left-Click: Play & set as Tension Reference for Circle\n• Right-Click: Change Chord Type, Insert at Cursor, or Clear",
                        slot, tile.label, tile.quality_label or "", format_tile_pitches(tile), st_txt
                    ))
                end

                -- Right-Click Context Popup for Slot
                if reaper.ImGui_BeginPopup(ctx, string.format("CoFTileContextMenu_%d", slot)) then
                    if tile then
                        reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, string.format("Slot #%d: %s", slot, tile.label))
                        reaper.ImGui_Separator(ctx)

                        if reaper.ImGui_MenuItem(ctx, "🔊 Audition & Set as Tension Reference") then
                            page.active_slot = slot
                            CircleOfFifthsService.save_palettes(state.cof_pages)
                            CircleOfFifthsService.audition_tile(state, tile)
                        end

                        if reaper.ImGui_MenuItem(ctx, "➕ Insert Tile at Edit Cursor (1 Grid)") then
                            CircleOfFifthsService.insert_tile_at_cursor(state, tile, midi_service)
                        end

                        if reaper.ImGui_MenuItem(ctx, "🎼 Set Project Key Signature from This Tile") then
                            local cur_pos = reaper.GetCursorPosition()
                            local cur_qn = reaper.TimeMap2_timeToQN(0, cur_pos)
                            local retval, meas_idx = reaper.TimeMap_QNToMeasures(0, cur_qn)
                            local m_num = (retval and retval >= 1) and math.floor(retval) or math.max(1, (meas_idx or 0) + 1)
                            KeySignatureService.set_key_at_measure(state, m_num, tile.key_sig_idx or 0, true)
                            state.status_msg = string.format("🎼 Key Signature set from %s at Measure %d", tile.label, m_num)
                        end

                        reaper.ImGui_Separator(ctx)
                        if reaper.ImGui_BeginMenu(ctx, "🎹 Change Chord / Note Quality") then
                            for _, qopt in ipairs(QUALITY_OPTIONS) do
                                if qopt.id ~= "auto" then
                                    if reaper.ImGui_MenuItem(ctx, qopt.label, nil, tile.quality == qopt.id) then
                                        page.tiles[slot] = CircleOfFifthsService.create_tile(
                                            tile.sector_idx,
                                            tile.ring,
                                            qopt.id,
                                            tile.octave or 4
                                        )
                                        page.active_slot = slot
                                        CircleOfFifthsService.save_palettes(state.cof_pages)
                                        CircleOfFifthsService.audition_tile(state, page.tiles[slot])
                                    end
                                end
                            end
                            reaper.ImGui_EndMenu(ctx)
                        end

                        if reaper.ImGui_BeginMenu(ctx, "🎚 Change Octave") then
                            for oct = 2, 6 do
                                if reaper.ImGui_MenuItem(ctx, string.format("Octave %d (C%d)", oct, oct), nil, (tile.octave or 4) == oct) then
                                    page.tiles[slot] = CircleOfFifthsService.create_tile(
                                        tile.sector_idx,
                                        tile.ring,
                                        tile.quality,
                                        oct
                                    )
                                    CircleOfFifthsService.save_palettes(state.cof_pages)
                                    CircleOfFifthsService.audition_tile(state, page.tiles[slot])
                                end
                            end
                            reaper.ImGui_EndMenu(ctx)
                        end

                        reaper.ImGui_Separator(ctx)
                        if reaper.ImGui_MenuItem(ctx, "✕ Clear Tile") then
                            page.tiles[slot] = nil
                            if page.active_slot == slot then
                                page.active_slot = nil
                            end
                            CircleOfFifthsService.save_palettes(state.cof_pages)
                        end
                    else
                        reaper.ImGui_TextDisabled(ctx, string.format("Slot #%d is empty (Drag a note from the Circle)", slot))
                    end
                    reaper.ImGui_EndPopup(ctx)
                end
            end

            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Spacing(ctx)

            -- 3. SCORE ACTION BUTTONS FOR ACTIVE TILE & PROGRESSION
            local active_tile = tension_map.ref_tile
            if reaper.ImGui_Button(ctx, "➕ Insert Active Tile at Cursor##CoFInsOne", 215, 30) then
                if active_tile then
                    local n_ins = CircleOfFifthsService.insert_tile_at_cursor(state, active_tile, midi_service)
                    state.status_msg = string.format("Inserted %s (%d notes) at cursor", active_tile.label, n_ins)
                else
                    state.status_msg = "Select or drop a Tile first!"
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Writes the currently active Tile into the selected/armed instrument(s) at the edit cursor (supports Auto-Divisi!) and advances by 1 Grid length.")
            end

            reaper.ImGui_SameLine(ctx, 0, 8)
            if reaper.ImGui_Button(ctx, "🎼 Insert Progression (1–8) at Cursor##CoFInsProg", 245, 30) then
                local c_cnt, n_cnt = CircleOfFifthsService.insert_progression_at_cursor(state, page, midi_service)
                if c_cnt > 0 then
                    state.status_msg = string.format("🎼 Inserted %d chords (%d notes) from '%s' at cursor", c_cnt, n_cnt, page.name or "Palette")
                else
                    state.status_msg = "No populated tiles on this page to insert."
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx, "Writes all populated Tiles (1..8) sequentially into the score at the edit cursor (uses Auto-Divisi when enabled!).")
            end

            reaper.ImGui_Spacing(ctx)

            if reaper.ImGui_Button(ctx, "🎼 Set Key Signature from Active Tile##CoFSetKey", 245, 28) then
                if active_tile then
                    local cur_pos = reaper.GetCursorPosition()
                    local cur_qn = reaper.TimeMap2_timeToQN(0, cur_pos)
                    local retval, meas_idx = reaper.TimeMap_QNToMeasures(0, cur_qn)
                    local m_num = (retval and retval >= 1) and math.floor(retval) or math.max(1, (meas_idx or 0) + 1)
                    KeySignatureService.set_key_at_measure(state, m_num, active_tile.key_sig_idx or 0, true)
                    state.status_msg = string.format("🎼 Key Signature set from %s at Measure %d", active_tile.label, m_num)
                else
                    state.status_msg = "Select or drop a Tile first!"
                end
            end

            reaper.ImGui_SameLine(ctx, 0, 8)
            if reaper.ImGui_Button(ctx, "🗑 Clear All 8 Tiles##CoFClearAll", 150, 28) then
                page.tiles = { nil, nil, nil, nil, nil, nil, nil, nil }
                page.active_slot = nil
                CircleOfFifthsService.save_palettes(state.cof_pages)
                state.status_msg = string.format("Cleared all 8 tiles in '%s'", page.name or "Palette")
            end

            end)
            if not ok_r then
                state.status_msg = "CoF Tiles Error: " .. tostring(err_r)
            end
            reaper.ImGui_EndChild(ctx)
        end

        -- Render floating Drag & Drop Ghost Badge while dragging a note/chord from the Circle
        if state._cof_drag_payload then
            if reaper.ImGui_IsMouseDown(ctx, 0) then
                local mx, my = reaper.ImGui_GetMousePos(ctx)
                local fg_dl = reaper.APIExists("ImGui_GetForegroundDrawList") and reaper.ImGui_GetForegroundDrawList(ctx) or reaper.ImGui_GetWindowDrawList(ctx)
                local badge_txt = string.format("🎵 %s (%s) → Drop on Slot 1..8",
                    state._cof_drag_payload.label or "C",
                    format_tile_pitches(state._cof_drag_payload))
                local btw, bth = reaper.ImGui_CalcTextSize(ctx, badge_txt)
                local bx = mx + 14
                local by = my - 14
                reaper.ImGui_DrawList_AddRectFilled(fg_dl, bx - 8, by - 5, bx + btw + 8, by + bth + 5, 0x1E272EFF, 5.0)
                reaper.ImGui_DrawList_AddRect(fg_dl, bx - 8, by - 5, bx + btw + 8, by + bth + 5, 0xFFD700FF, 5.0, 0, 2.0)
                reaper.ImGui_DrawList_AddText(fg_dl, bx, by, 0xFFFFFFFF, badge_txt)
            else
                -- Mouse released outside any tile
                state._cof_drag_payload = nil
            end
        end
    end

    reaper.ImGui_End(ctx)
end

return CircleOfFifthsModal

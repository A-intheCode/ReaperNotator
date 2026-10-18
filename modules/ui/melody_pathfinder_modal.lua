-- ==============================================================================
-- REAPER Native Notator - Module: MelodyPathfinderModal
-- Interactive Modal for Key-Note Waypoint Melodic Inpainting,
-- Clef-Aware Instrument Register Bounding, Film Composer Styles 1-4,
-- Melodic Inversion & Counter-Melody Creation
-- ==============================================================================

local MelodyStyleCorpus       = require("services.melody_style_corpus")
local MelodyPathfinderService = require("services.melody_pathfinder_service")
local PatternService          = require("services.pattern_service")

local MelodyPathfinderModal = {}

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local function pitch_to_name(p)
    if not p then return "-" end
    local oct = math.floor(p / 12) - 1
    local semi = (p % 12) + 1
    return string.format("%s%d", NOTE_NAMES[semi] or "C", oct)
end

--- Draws a real-time piano-roll / contour map of Reference Notes, Key Waypoints & Generated Melody
local function draw_contour_preview(dl, preview, x, y, w, h)
    reaper.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x14171EFF, 5.0)
    reaper.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, 0x343B4DFF, 5.0)

    if not preview or not preview.notes or #preview.notes == 0 then
        reaper.ImGui_DrawList_AddText(dl, x + 16, y + h * 0.42, 0x8892B0FF, "No notes to preview.")
        return
    end

    local min_qn = preview.min_qn or preview.notes[1].start_qn
    local last_n = preview.notes[#preview.notes]
    local max_qn = math.max(min_qn + 4.0, (preview.max_qn or (last_n.start_qn + last_n.dur_qn)))
    local span_qn = math.max(1.0, max_qn - min_qn)

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

    local pad_x = 10
    local pad_y = 10
    local inner_w = math.max(20, w - 2 * pad_x)
    local inner_h = math.max(20, h - 2 * pad_y)

    -- Draw measure grid lines (every 4 QN)
    local first_bar_qn = math.ceil(min_qn / 4.0) * 4.0
    local q = first_bar_qn
    local bar_guard = 0
    while q < max_qn and bar_guard < 128 do
        bar_guard = bar_guard + 1
        local gx = x + pad_x + ((q - min_qn) / span_qn) * inner_w
        reaper.ImGui_DrawList_AddLine(dl, gx, y + 2, gx, y + h - 2, 0x2A3040AA, 1.0)
        q = q + 4.0
    end

    -- 1. Draw Reference Track Harmony Notes (Subtle Purple Bars in background)
    for _, rn in ipairs(preview.ref_notes or {}) do
        local rx0 = x + pad_x + math.max(0, (rn.start_qn - min_qn) / span_qn) * inner_w
        local rx1 = x + pad_x + math.min(1, (rn.end_qn - min_qn) / span_qn) * inner_w
        local ry  = y + pad_y + (1.0 - (rn.pitch - min_p) / p_span) * inner_h
        if rx1 > rx0 + 1 then
            reaper.ImGui_DrawList_AddRectFilled(dl, rx0, ry - 3, rx1, ry + 3, 0x9B59B655, 2.0)
        end
    end

    -- 2. Draw melodic contour polyline connecting generated notes
    local prev_cx, prev_cy = nil, nil
    for _, gn in ipairs(preview.notes) do
        local nx0 = x + pad_x + ((gn.start_qn - min_qn) / span_qn) * inner_w
        local nx1 = x + pad_x + math.min(1.0, (gn.start_qn + gn.dur_qn - min_qn) / span_qn) * inner_w
        local ny  = y + pad_y + (1.0 - (gn.pitch - min_p) / p_span) * inner_h

        if prev_cx and prev_cy then
            reaper.ImGui_DrawList_AddLine(dl, prev_cx, prev_cy, nx0, ny, 0x3498DB88, 1.5)
        end
        prev_cx, prev_cy = nx0, ny

        -- Note pill: Gold for Key Waypoints, Cyan/Emerald for generated bridge notes
        local col_fill = gn.is_waypoint and 0xF39C12FF or 0x2ECC71EE
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
        local px = x + pad_x + frac * inner_w
        reaper.ImGui_DrawList_AddLine(dl, px, y + 2, px, y + h - 2, 0x2ECC71FF, 2.0)
    end
end

function MelodyPathfinderModal.render(ctx, state, midi_service, audio_preview, active_tracks_data)
    if not state.show_melody_pathfinder_modal then return end

    -- Initialize persistent options in state
    state.mpf_opts = state.mpf_opts or {
        style_id = "film_style_1",
        scale_id = "auto",
        transform_id = "normal",
        counter_melody_mode = false,
        ref_track_mode = "auto_all",
        harmony_blend = 0.80,
        density = 0.50,
        leap_character = 0.45,
        phrase_bars = 4,
        octave_shift = 0,
        auto_slur = true,
        seed = 1042,
    }
    local opts = state.mpf_opts
    if opts.octave_shift == nil then opts.octave_shift = 0 end

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

    reaper.ImGui_SetNextWindowSize(ctx, 650, 635, reaper.ImGui_Cond_FirstUseEver())
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
    end

    if s_vis then
        local target_track, waypoints = MelodyPathfinderService.get_selected_waypoints(state, active_tracks_data)
        local trk_guid = (target_track and reaper.ValidatePtr(target_track, "MediaTrack*") and reaper.GetTrackGUID(target_track)) or ""
        local cur_clef_setting = (state.track_clefs and state.track_clefs[trk_guid]) or "auto"
        local cur_q_bucket = (#waypoints == 0) and math.floor((reaper.GetCursorPosition() or 0) * 4) or 0
        local wp_sig = string.format(
            "%s_%s_%d_%s_%s_%d",
            trk_guid,
            cur_clef_setting,
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

        if state.mpf_dirty or not state.mpf_preview then
            state.mpf_preview = MelodyPathfinderService.generate_preview(state, active_tracks_data, opts)
            state.mpf_dirty = false
        end
        local preview = state.mpf_preview
        local clef_reg = (preview and preview.clef_register) or { label = "Treble Clef", min_p = 55, max_p = 86 }

        -- ==================================================================
        -- 1. HEADER: ACTIVE TRACK, CLEF REGISTER & WAYPOINT LANDMARK STATUS
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
        reaper.ImGui_SameLine(ctx, 0, 12)
        reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format(
            "𝄞 %s [%s–%s]",
            clef_reg.label or "Clef",
            pitch_to_name(clef_reg.min_p),
            pitch_to_name(clef_reg.max_p)
        ))

        -- Quick Register Octave Shift (-1 / Auto / +1)
        reaper.ImGui_SameLine(ctx, 0, 12)
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

        local bar_start = math.floor(((preview and preview.min_qn) or 0) / 4.0) + 1
        local bar_end   = bar_start + (opts.phrase_bars or 4) - 1

        if #waypoints >= 2 then
            reaper.ImGui_TextColored(ctx, 0x2ECC71FF, string.format(
                "✓ %d Key Notes (Waypoints) selected [%s -> %s] — filling %d musical segment(s)",
                #waypoints,
                pitch_to_name(waypoints[1].pitch),
                pitch_to_name(waypoints[#waypoints].pitch),
                #waypoints - 1
            ))
        elseif #waypoints == 1 then
            reaper.ImGui_TextColored(ctx, 0xF1C40FFF, string.format(
                "★ 1 Seed Note selected (%s) — generating %d-Bar %s (Bars %d–%d) in %s register!",
                pitch_to_name(waypoints[1].pitch),
                opts.phrase_bars or 4,
                opts.counter_melody_mode and "Counter-Melody" or "Melodic Phrase",
                bar_start,
                bar_end,
                clef_reg.label or "Clef"
            ))
        else
            reaper.ImGui_TextColored(ctx, 0xE67E22FF, string.format(
                "ℹ No notes selected — generating %d-Bar phrase (Bars %d–%d) in %s register [%s–%s] aligned with Reference Track",
                opts.phrase_bars or 4,
                bar_start,
                bar_end,
                clef_reg.label or "Clef",
                pitch_to_name(clef_reg.min_p),
                pitch_to_name(clef_reg.max_p)
            ))
        end

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 2. COUNTER-MELODY CHECKBOX & PHRASE LENGTH (FOR 1-NOTE SEED)
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
            reaper.ImGui_SameLine(ctx, 0, 16)
            reaper.ImGui_TextColored(ctx, 0x8892B0FF, "Span:")
            reaper.ImGui_SameLine(ctx, 0, 6)
            for _, b_opt in ipairs({ 2, 4, 8 }) do
                if reaper.ImGui_RadioButton(ctx, string.format("%d Bars##mpf_b%d", b_opt, b_opt), (opts.phrase_bars or 4) == b_opt) then
                    opts.phrase_bars = b_opt
                    state.mpf_dirty = true
                end
                reaper.ImGui_SameLine(ctx, 0, 6)
            end
            reaper.ImGui_NewLine(ctx)
        end

        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 3. STYLE PROFILE (TRAINED CORPUS + FILM COMPOSER STYLES 1-4) & SCALE
        -- ==================================================================
        local col_w = 300
        reaper.ImGui_TextColored(ctx, 0xF39C12FF, "1. Musical & Film Composer Style:")
        reaper.ImGui_SameLine(ctx, col_w + 16)
        reaper.ImGui_TextColored(ctx, 0xF39C12FF, "2. Scale / Mode:")

        local cur_style = MelodyStyleCorpus.BY_ID[opts.style_id] or MelodyStyleCorpus.STYLES[1]
        reaper.ImGui_SetNextItemWidth(ctx, col_w)
        if reaper.ImGui_BeginCombo(ctx, "##MPFStyleCombo", cur_style.name) then
            for _, st in ipairs(MelodyStyleCorpus.STYLES) do
                local is_sel = (st.id == opts.style_id)
                if reaper.ImGui_Selectable(ctx, st.name, is_sel) then
                    opts.style_id = st.id
                    state.mpf_dirty = true
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

        -- Corpus & Compositional Rules badge
        reaper.ImGui_TextColored(ctx, 0x6E7681FF, string.format(
            "   🧠 Corpus: %d scores (%d notes) | Gap-Fill: %d%% | Fanfare: %d%% | Pivot: %d%% | Seq: %d%%",
            cur_style.trained_scores or 300,
            cur_style.trained_notes or 10000,
            math.floor((cur_style.gap_fill_strength or 0.75) * 100 + 0.5),
            math.floor((cur_style.triad_fanfare_bonus or 0.25) * 100 + 0.5),
            math.floor((cur_style.pivot_return_bonus or 0.20) * 100 + 0.5),
            math.floor((cur_style.sequence_repeat_bonus or 0.30) * 100 + 0.5)
        ))

        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 4. REFERENCE TRACK & HARMONIC CONSONANCE SLIDER
        -- ==================================================================
        reaper.ImGui_TextColored(ctx, 0x9B59B6FF, "3. Reference Track (Harmony / Counterpoint Context):")
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
                "Controls how consonant the generated melody is relative to MIDI notes on the Reference Track:\n• 80-100%: Pure consonant 3rds, 6ths, 5ths & chord tones (folded into your track's Clef octave)\n• 50%: Balanced counterpoint with expressive passing tensions\n• 0-25%: Dark dissonance (minor 2nds, tritones, thriller friction)"
            )
        end

        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 5. INVERSION / CONTOUR TRANSFORM & RHYTHM / LEAP SLIDERS
        -- ==================================================================
        reaper.ImGui_TextColored(ctx, 0x5DADE2FF, "5. Melodic Inversion & Contour:")
        reaper.ImGui_SameLine(ctx, col_w + 16)
        reaper.ImGui_TextColored(ctx, 0x5DADE2FF, "6. Rhythmic Density & Leap Character:")

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
            local ok, msg = MelodyPathfinderService.invert_selected_notes_in_place(state, active_tracks_data, opts.scale_id)
            state.status_msg = msg
            state.mpf_dirty = true
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Directly invert the currently selected notes in the score around the first note (diatonic mirror inside Clef register).")
        end

        reaper.ImGui_SameLine(ctx, col_w + 16)
        reaper.ImGui_SetNextItemWidth(ctx, (col_w - 8) * 0.5)
        local dens_pct = math.floor((opts.density or 0.5) * 100 + 0.5)
        local d_chg, new_d_pct = reaper.ImGui_SliderInt(ctx, "##MPFDensity", dens_pct, 10, 100, "Density %d%%")
        if d_chg then
            opts.density = new_d_pct / 100.0
            state.mpf_dirty = true
        end

        reaper.ImGui_SameLine(ctx, 0, 8)
        reaper.ImGui_SetNextItemWidth(ctx, (col_w - 8) * 0.5)
        local leap_pct = math.floor((opts.leap_character or 0.45) * 100 + 0.5)
        local l_chg, new_l_pct = reaper.ImGui_SliderInt(ctx, "##MPFLeaps", leap_pct, 0, 100, "Leaps %d%%")
        if l_chg then
            opts.leap_character = new_l_pct / 100.0
            state.mpf_dirty = true
        end

        local sl_chg, new_sl = reaper.ImGui_Checkbox(ctx, "⌒ Add Phrase Slur automatically", opts.auto_slur == true)
        if sl_chg then opts.auto_slur = new_sl end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- ==================================================================
        -- 6. LIVE CONTOUR & HARMONY MAP PREVIEW
        -- ==================================================================
        local ref_cnt = (preview and preview.ref_notes and #preview.ref_notes) or 0
        local gen_cnt = (preview and preview.notes and #preview.notes) or 0
        reaper.ImGui_TextColored(ctx, 0xCCD6F6FF, string.format(
            "LIVE MELODIC MAP PREVIEW (%d generated notes in %s [%s–%s] | %d reference harmony notes):",
            gen_cnt,
            clef_reg.label or "Clef",
            pitch_to_name(clef_reg.min_p),
            pitch_to_name(clef_reg.max_p),
            ref_cnt
        ))
        reaper.ImGui_TextColored(ctx, 0x8892B0FF, "🟠 Gold = Key Landmarks   🟢 Green = Generated Bridge/Counter-Melody   🟣 Purple = Reference Track Harmony")

        local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
        local map_h = 135
        local cx, cy = reaper.ImGui_GetCursorScreenPos(ctx)
        local dl = reaper.ImGui_GetWindowDrawList(ctx)
        draw_contour_preview(dl, preview, cx, cy, avail_w, map_h)
        reaper.ImGui_Dummy(ctx, avail_w, map_h + 6)

        -- ==================================================================
        -- 7. ACTION BAR: REROLL VARIATION, AUDIO PREVIEW & APPLY
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
                        chan = 0, -- Always audition on Channel 1 (0) so single-channel VSTis and Reaticulate respond reliably
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
            local ok, msg = MelodyPathfinderService.apply_to_score(state, midi_service, preview, opts)
            state.status_msg = msg
        end
        reaper.ImGui_PopStyleColor(ctx, 2)

        reaper.ImGui_SameLine(ctx, 0, 10)
        if reaper.ImGui_Button(ctx, "Close", 65, 30) then
            PatternService.stop_preview(audio_preview)
            state.show_melody_pathfinder_modal = false
        end
    end

    reaper.ImGui_End(ctx)
end

return MelodyPathfinderModal

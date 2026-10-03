-- ==============================================================================
-- REAPER Native Notator - Service: ClipboardService
-- Universal copy, cut, and paste engine for notes, dynamics, hairpins,
-- tempo markings, and octave lines.
-- Supports paste at edit cursor or at start position of selected notes.
-- ==============================================================================

local MidiNote = require("classes.note")
local DynamicMarker = require("classes.dynamic")
local Hairpin = require("classes.hairpin")
local TempoMarker = require("classes.tempo_marker")

local ClipboardService = {}

function ClipboardService.copy(state, active_tracks_data)
    -- 1. Determine selected notes
    local sel_notes = {}
    if state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            table.insert(sel_notes, sn)
        end
    end
    if #sel_notes == 0 and state.selected_note then
        table.insert(sel_notes, state.selected_note)
    end
    
    -- 2. Check explicitly selected non-note objects
    local sel_dynamic = state.selected_dynamic
    local sel_hairpin = state.selected_hairpin
    local sel_dynamic_text = state.selected_dynamic_text
    local sel_pedal = state.selected_pedal
    local sel_tempo_marker = state.selected_tempo_marker
    local sel_octave_line = state.selected_octave_line
    local sel_text_item = state.selected_text_item
    
    local has_any_selection = (#sel_notes > 0)
                           or (sel_dynamic ~= nil)
                           or (sel_hairpin ~= nil)
                           or (sel_dynamic_text ~= nil)
                           or (sel_pedal ~= nil)
                           or (sel_tempo_marker ~= nil)
                           or (sel_octave_line ~= nil)
                           or (sel_text_item ~= nil)
                           
    if not has_any_selection then
        state.status_msg = "Copy: Nothing selected to copy!"
        return false
    end
    
    -- 3. Determine time range (min start QN and max end QN across all selected objects)
    local min_start_qn = 1e9
    local max_end_qn = -1e9
    
    if #sel_notes > 0 then
        table.sort(sel_notes, function(a, b)
            if math.abs(a.start_qn - b.start_qn) > 0.005 then return a.start_qn < b.start_qn end
            return a.pitch < b.pitch
        end)
        for _, n in ipairs(sel_notes) do
            if n.start_qn < min_start_qn then min_start_qn = n.start_qn end
            if n.end_qn > max_end_qn then max_end_qn = n.end_qn end
        end
    end
    
    if sel_dynamic then
        if sel_dynamic.qn < min_start_qn then min_start_qn = sel_dynamic.qn end
        if (sel_dynamic.qn + 1.0) > max_end_qn then max_end_qn = sel_dynamic.qn + 1.0 end
    end
    
    if sel_hairpin then
        local hp_s = sel_hairpin.start_qn or 0.0
        local hp_e = sel_hairpin.end_qn or (hp_s + 4.0)
        if hp_s < min_start_qn then min_start_qn = hp_s end
        if hp_e > max_end_qn then max_end_qn = hp_e end
    end

    if sel_dynamic_text then
        local dt_s = sel_dynamic_text.start_qn or 0.0
        local dt_e = sel_dynamic_text.end_qn or (dt_s + 4.0)
        if dt_s < min_start_qn then min_start_qn = dt_s end
        if dt_e > max_end_qn then max_end_qn = dt_e end
    end

    if sel_pedal then
        local pm_s = sel_pedal.start_qn or 0.0
        local pm_e = sel_pedal.end_qn or (pm_s + 4.0)
        if pm_s < min_start_qn then min_start_qn = pm_s end
        if pm_e > max_end_qn then max_end_qn = pm_e end
    end
    
    if sel_tempo_marker then
        local tm_s = sel_tempo_marker.start_qn or 0.0
        local tm_e = sel_tempo_marker.end_qn or (tm_s + 4.0)
        if tm_s < min_start_qn then min_start_qn = tm_s end
        if tm_e > max_end_qn then max_end_qn = tm_e end
    end
    
    if sel_octave_line then
        local ol_s = sel_octave_line.start_qn or 0.0
        local ol_e = sel_octave_line.end_qn or (ol_s + 4.0)
        if ol_s < min_start_qn then min_start_qn = ol_s end
        if ol_e > max_end_qn then max_end_qn = ol_e end
    end
    
    if sel_text_item then
        local ti_s = sel_text_item.qn or 0.0
        local ti_e = ti_s + 1.0
        if ti_s < min_start_qn then min_start_qn = ti_s end
        if ti_e > max_end_qn then max_end_qn = ti_e end
    end
    
    if min_start_qn > 1e8 then min_start_qn = 0.0 end
    if max_end_qn < -1e8 then max_end_qn = min_start_qn + 1.0 end
    
    -- 4. Store notes relative to start point
    local clip_notes = {}
    for _, n in ipairs(sel_notes) do
        table.insert(clip_notes, {
            rel_qn       = n.start_qn - min_start_qn,
            pitch        = n.pitch,
            dur_qn       = n.dur_qn,
            vel          = n.vel or 96,
            chan         = n.chan or 0,
            articulation = n.articulation,
            track_guid   = n.track and reaper.ValidatePtr(n.track, "MediaTrack*") and reaper.GetTrackGUID(n.track) or nil
        })
    end
    
    -- 5. Capture dynamics (explicitly selected or in time range of selected notes)
    local clip_dynamics = {}
    local dyn_keys = {}
    if sel_dynamic then
        local trk_guid = sel_dynamic.track and reaper.ValidatePtr(sel_dynamic.track, "MediaTrack*") and reaper.GetTrackGUID(sel_dynamic.track)
        table.insert(clip_dynamics, {
            rel_qn     = sel_dynamic.qn - min_start_qn,
            label      = sel_dynamic.label,
            c1         = sel_dynamic.c1 or 80,
            c11        = sel_dynamic.c11 or 85,
            track_guid = trk_guid
        })
        dyn_keys[tostring(trk_guid) .. "_" .. tostring(sel_dynamic.qn)] = true
    end
    
    if #sel_notes > 0 and active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.dynamics then
                for _, d in ipairs(tdata.dynamics) do
                    local k = tostring(tdata.guid) .. "_" .. tostring(d.qn)
                    if not dyn_keys[k] and d.qn >= (min_start_qn - 0.05) and d.qn <= (max_end_qn + 0.05) then
                        table.insert(clip_dynamics, {
                            rel_qn     = d.qn - min_start_qn,
                            label      = d.label,
                            c1         = d.c1 or 80,
                            c11        = d.c11 or 85,
                            track_guid = tdata.guid
                        })
                        dyn_keys[k] = true
                    end
                end
            end
        end
    end
    
    -- 6. Capture hairpins (explicitly selected or in time range of selected notes)
    local clip_hairpins = {}
    local hp_keys = {}
    if sel_hairpin then
        local dur = (sel_hairpin.end_qn or (sel_hairpin.start_qn + 4.0)) - sel_hairpin.start_qn
        table.insert(clip_hairpins, {
            rel_start_qn = sel_hairpin.start_qn - min_start_qn,
            rel_end_qn   = (sel_hairpin.end_qn or (sel_hairpin.start_qn + 4.0)) - min_start_qn,
            dur_qn       = dur,
            type         = sel_hairpin.type or "crescendo",
            start_dyn    = sel_hairpin.start_dyn,
            end_dyn      = sel_hairpin.end_dyn,
            staff        = sel_hairpin.staff,
            track_guid   = sel_hairpin.track_guid
        })
        hp_keys[sel_hairpin.id] = true
    end
    
    if #sel_notes > 0 and state.hairpins then
        for _, hp in ipairs(state.hairpins) do
            if not hp_keys[hp.id] and hp.start_qn >= (min_start_qn - 0.05) and hp.start_qn <= (max_end_qn + 0.05) then
                local dur = (hp.end_qn or (hp.start_qn + 4.0)) - hp.start_qn
                table.insert(clip_hairpins, {
                    rel_start_qn = hp.start_qn - min_start_qn,
                    rel_end_qn   = (hp.end_qn or (hp.start_qn + 4.0)) - min_start_qn,
                    dur_qn       = dur,
                    type         = hp.type or "crescendo",
                    start_dyn    = hp.start_dyn,
                    end_dyn      = hp.end_dyn,
                    staff        = hp.staff,
                    track_guid   = hp.track_guid
                })
                hp_keys[hp.id] = true
            end
        end
    end
    
    -- 6b. Capture dynamic texts (cresc., dim., etc.)
    local clip_dynamic_texts = {}
    local dt_keys = {}
    if sel_dynamic_text then
        local dur = sel_dynamic_text.end_qn - sel_dynamic_text.start_qn
        table.insert(clip_dynamic_texts, {
            rel_start_qn  = sel_dynamic_text.start_qn - min_start_qn,
            rel_end_qn    = sel_dynamic_text.end_qn - min_start_qn,
            dur_qn        = dur,
            type          = sel_dynamic_text.type or "crescendo",
            text          = sel_dynamic_text.text or "cresc.",
            line_pattern  = sel_dynamic_text.line_pattern or "none",
            curve_pattern = sel_dynamic_text.curve_pattern or "linear",
            start_dyn     = sel_dynamic_text.start_dyn,
            end_dyn       = sel_dynamic_text.end_dyn,
            staff         = sel_dynamic_text.staff,
            track_guid    = sel_dynamic_text.track_guid
        })
        dt_keys[sel_dynamic_text.id] = true
    end
    
    if #sel_notes > 0 and state.dynamic_texts then
        for _, dt in ipairs(state.dynamic_texts) do
            if not dt_keys[dt.id] and dt.start_qn >= (min_start_qn - 0.05) and dt.start_qn <= (max_end_qn + 0.05) then
                local dur = dt.end_qn - dt.start_qn
                table.insert(clip_dynamic_texts, {
                    rel_start_qn  = dt.start_qn - min_start_qn,
                    rel_end_qn    = dt.end_qn - min_start_qn,
                    dur_qn        = dur,
                    type          = dt.type or "crescendo",
                    text          = dt.text or "cresc.",
                    line_pattern  = dt.line_pattern or "none",
                    curve_pattern = dt.curve_pattern or "linear",
                    start_dyn     = dt.start_dyn,
                    end_dyn       = dt.end_dyn,
                    staff         = dt.staff,
                    track_guid    = dt.track_guid
                })
                dt_keys[dt.id] = true
            end
        end
    end
    
    -- 6c. Capture pedal markings (explicitly selected or within time range)
    local clip_pedals = {}
    local pm_keys = {}
    if sel_pedal then
        local dur = sel_pedal.end_qn - sel_pedal.start_qn
        local cp_pauses = {}
        for _, p in ipairs(sel_pedal.pauses or {}) do
            table.insert(cp_pauses, {
                rel_qn = p.qn - sel_pedal.start_qn,
                type   = p.type or "asterisk",
                dur    = p.dur or 0.0
            })
        end
        table.insert(clip_pedals, {
            rel_start_qn = sel_pedal.start_qn - min_start_qn,
            rel_end_qn   = sel_pedal.end_qn - min_start_qn,
            dur_qn       = dur,
            style        = sel_pedal.style or "classic",
            apply_cc     = sel_pedal.apply_cc,
            staff        = sel_pedal.staff or "bass",
            track_guid   = sel_pedal.track_guid,
            pauses       = cp_pauses
        })
        pm_keys[sel_pedal.id] = true
    end

    if #sel_notes > 0 and state.pedal_marks then
        for _, pm in ipairs(state.pedal_marks) do
            if not pm_keys[pm.id] and pm.start_qn >= (min_start_qn - 0.05) and pm.start_qn <= (max_end_qn + 0.05) then
                local dur = pm.end_qn - pm.start_qn
                local cp_pauses = {}
                for _, p in ipairs(pm.pauses or {}) do
                    table.insert(cp_pauses, {
                        rel_qn = p.qn - pm.start_qn,
                        type   = p.type or "asterisk",
                        dur    = p.dur or 0.0
                    })
                end
                table.insert(clip_pedals, {
                    rel_start_qn = pm.start_qn - min_start_qn,
                    rel_end_qn   = pm.end_qn - min_start_qn,
                    dur_qn       = dur,
                    style        = pm.style or "classic",
                    apply_cc     = pm.apply_cc,
                    staff        = pm.staff or "bass",
                    track_guid   = pm.track_guid,
                    pauses       = cp_pauses
                })
                pm_keys[pm.id] = true
            end
        end
    end
    
    -- 7. Capture tempo markers (explicitly selected or within time range)
    local clip_tempos = {}
    local tm_keys = {}
    if sel_tempo_marker then
        local dur = (sel_tempo_marker.end_qn or (sel_tempo_marker.start_qn + 4.0)) - sel_tempo_marker.start_qn
        table.insert(clip_tempos, {
            rel_start_qn      = sel_tempo_marker.start_qn - min_start_qn,
            rel_end_qn        = (sel_tempo_marker.end_qn or (sel_tempo_marker.start_qn + 4.0)) - min_start_qn,
            dur_qn            = dur,
            type              = sel_tempo_marker.type or "absolute",
            label             = sel_tempo_marker.label,
            modifier          = sel_tempo_marker.modifier,
            bpm               = sel_tempo_marker.bpm,
            target_bpm        = sel_tempo_marker.target_bpm,
            custom_bpm_only   = sel_tempo_marker.custom_bpm_only,
            custom_target_bpm = sel_tempo_marker.custom_target_bpm
        })
        tm_keys[sel_tempo_marker.id] = true
    end
    
    if #sel_notes > 0 and state.tempo_markers then
        for _, tm in ipairs(state.tempo_markers) do
            if not tm_keys[tm.id] and tm.start_qn >= (min_start_qn - 0.05) and tm.start_qn <= (max_end_qn + 0.05) then
                local dur = (tm.end_qn or (tm.start_qn + 4.0)) - tm.start_qn
                table.insert(clip_tempos, {
                    rel_start_qn      = tm.start_qn - min_start_qn,
                    rel_end_qn        = (tm.end_qn or (tm.start_qn + 4.0)) - min_start_qn,
                    dur_qn            = dur,
                    type              = tm.type or "absolute",
                    label             = tm.label,
                    modifier          = tm.modifier,
                    bpm               = tm.bpm,
                    target_bpm        = tm.target_bpm,
                    custom_bpm_only   = tm.custom_bpm_only,
                    custom_target_bpm = tm.custom_target_bpm
                })
                tm_keys[tm.id] = true
            end
        end
    end
    
    -- 8. Capture octave lines (explicitly selected or in time range)
    local clip_octaves = {}
    local ol_keys = {}
    if sel_octave_line then
        local dur = (sel_octave_line.end_qn or (sel_octave_line.start_qn + 4.0)) - sel_octave_line.start_qn
        table.insert(clip_octaves, {
            rel_start_qn = sel_octave_line.start_qn - min_start_qn,
            rel_end_qn   = (sel_octave_line.end_qn or (sel_octave_line.start_qn + 4.0)) - min_start_qn,
            dur_qn       = dur,
            type         = sel_octave_line.type or "8va",
            track_guid   = sel_octave_line.track_guid
        })
        ol_keys[sel_octave_line.id] = true
    end
    
    if #sel_notes > 0 and state.octave_lines then
        for _, ol in ipairs(state.octave_lines) do
            if not ol_keys[ol.id] and ol.start_qn >= (min_start_qn - 0.05) and ol.start_qn <= (max_end_qn + 0.05) then
                local dur = (ol.end_qn or (ol.start_qn + 4.0)) - ol.start_qn
                table.insert(clip_octaves, {
                    rel_start_qn = ol.start_qn - min_start_qn,
                    rel_end_qn   = (ol.end_qn or (ol.start_qn + 4.0)) - min_start_qn,
                    dur_qn       = dur,
                    type         = ol.type or "8va",
                    track_guid   = ol.track_guid
                })
                ol_keys[ol.id] = true
            end
        end
    end
    
    -- 6e. Capture text items (explicitly selected or within time range)
    local clip_text_items = {}
    local ti_keys = {}
    if sel_text_item then
        table.insert(clip_text_items, {
            rel_qn     = sel_text_item.qn - min_start_qn,
            offset_y   = sel_text_item.offset_y or 32.0,
            text       = sel_text_item.text or "",
            style      = sel_text_item.style or "italic",
            font_size  = sel_text_item.font_size or 16.0,
            track_guid = sel_text_item.track_guid,
        })
        ti_keys[sel_text_item.id] = true
    end

    if #sel_notes > 0 and state.text_items then
        for _, ti in ipairs(state.text_items) do
            if type(ti) == "table" and not ti_keys[ti.id] and (ti.qn or 0.0) >= (min_start_qn - 0.05) and (ti.qn or 0.0) <= (max_end_qn + 0.05) then
                table.insert(clip_text_items, {
                    rel_qn     = (ti.qn or 0.0) - min_start_qn,
                    offset_y   = tonumber(ti.offset_y) or 32.0,
                    text       = tostring(ti.text or ""),
                    style      = tostring(ti.style or "italic"),
                    font_size  = tonumber(ti.font_size) or 16.0,
                    track_guid = ti.track_guid,
                })
                if ti.id then ti_keys[ti.id] = true end
            end
        end
    end
    
    state.clipboard = {
        notes         = clip_notes,
        dynamics      = clip_dynamics,
        hairpins      = clip_hairpins,
        dynamic_texts = clip_dynamic_texts,
        pedals        = clip_pedals,
        tempo_markers = clip_tempos,
        octave_lines  = clip_octaves,
        text_items    = clip_text_items,
        total_dur_qn  = math.max(0.25, max_end_qn - min_start_qn)
    }
    
    local parts = {}
    if #clip_notes > 0 then table.insert(parts, string.format("%d note(s)", #clip_notes)) end
    if #clip_dynamics > 0 then
        if #clip_dynamics == 1 and clip_dynamics[1].label then
            table.insert(parts, string.format("Dynamic '%s'", clip_dynamics[1].label))
        else
            table.insert(parts, string.format("%d dynamic(s)", #clip_dynamics))
        end
    end
    if #clip_hairpins > 0 then
        if #clip_hairpins == 1 and clip_hairpins[1].type then
            local hname = (clip_hairpins[1].type == "crescendo") and "Crescendo (<)" or "Decrescendo (>)"
            table.insert(parts, hname)
        else
            table.insert(parts, string.format("%d hairpin(s)", #clip_hairpins))
        end
    end
    if #clip_dynamic_texts > 0 then
        table.insert(parts, string.format("%d text dynamic(s)", #clip_dynamic_texts))
    end
    if #clip_pedals > 0 then
        table.insert(parts, string.format("%d pedal mark(s)", #clip_pedals))
    end
    if #clip_tempos > 0 then table.insert(parts, string.format("%d tempo marker(s)", #clip_tempos)) end
    if #clip_octaves > 0 then table.insert(parts, string.format("%d octave line(s)", #clip_octaves)) end
    if #clip_text_items > 0 then table.insert(parts, string.format("%d text item(s)", #clip_text_items)) end
    
    state.status_msg = string.format("📋 Copied: %s", table.concat(parts, ", "))
    return true
end

function ClipboardService.cut(state, midi_service, active_tracks_data)
    if ClipboardService.copy(state, active_tracks_data) then
        local del_parts = {}
        if state.selected_notes and state:count_selected_notes() > 0 then
            local del_cnt = midi_service.delete_selected_notes(state)
            table.insert(del_parts, string.format("%d note(s)", del_cnt))
        end
        if state.selected_dynamic then
            local DynamicsEngine = package.loaded["services.dynamics_engine"] or require("services.dynamics_engine")
            local lbl = state.selected_dynamic.label or ""
            DynamicsEngine.delete_selected_dynamic(state, midi_service, active_tracks_data)
            state.selected_dynamic = nil
            table.insert(del_parts, string.format("Dynamic '%s'", lbl))
        end
        if state.selected_hairpin then
            local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
            local hname = (state.selected_hairpin.type == "crescendo") and "Crescendo (<)" or "Decrescendo (>)"
            HairpinService.delete_hairpin(state, state.selected_hairpin.id, midi_service, active_tracks_data)
            state.selected_hairpin = nil
            table.insert(del_parts, hname)
        end
        if state.selected_dynamic_text then
            local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
            local txt = state.selected_dynamic_text.text or "Text Dynamic"
            DynamicTextService.delete_dynamic_text(state, state.selected_dynamic_text.id, midi_service, active_tracks_data)
            state.selected_dynamic_text = nil
            table.insert(del_parts, string.format("Text Dynamic '%s'", txt))
        end
        if state.selected_pedal then
            local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
            PedalService.delete_pedal(state, state.selected_pedal.id, midi_service, active_tracks_data)
            state.selected_pedal = nil
            table.insert(del_parts, "Pedal mark")
        end
        if state.selected_text_item then
            local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
            TextItemService.delete_text_item(state, state.selected_text_item.id)
            state.selected_text_item = nil
            table.insert(del_parts, "Text Item")
        end
        if state.selected_tempo_marker then
            local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
            TempoService.delete_selected_tempo_marker(state)
            state.selected_tempo_marker = nil
            table.insert(del_parts, "Tempo marker")
        end
        if state.selected_octave_line then
            local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
            OctaveService.delete_octave_line(state, state.selected_octave_line)
            state.selected_octave_line = nil
            table.insert(del_parts, "Octave line")
        end
        state.status_msg = string.format("✂️ Cut: %s", table.concat(del_parts, ", "))
        return true
    end
    return false
end

function ClipboardService.paste(state, midi_service, active_tracks_data)
    if not state.clipboard then
        state.status_msg = "Paste: Clipboard is empty!"
        return false
    end
    
    local clip = state.clipboard
    local has_content = (clip.notes and #clip.notes > 0)
                     or (clip.dynamics and #clip.dynamics > 0)
                     or (clip.hairpins and #clip.hairpins > 0)
                     or (clip.dynamic_texts and #clip.dynamic_texts > 0)
                     or (clip.pedals and #clip.pedals > 0)
                     or (clip.tempo_markers and #clip.tempo_markers > 0)
                     or (clip.octave_lines and #clip.octave_lines > 0)
                     or (clip.text_items and #clip.text_items > 0)
                     
    if not has_content then
        state.status_msg = "Paste: Clipboard is empty!"
        return false
    end
    
    -- 1. Determine start position:
    -- If the user has selected a note, its exact start QN is used!
    -- Otherwise the position of the REAPER edit cursor is used.
    local target_start_qn = nil
    local target_track = nil
    
    local sel_note = state.selected_note
    if not sel_note and state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            sel_note = sn
            break
        end
    end
    
    if sel_note and sel_note.start_qn then
        target_start_qn = sel_note.start_qn
        if sel_note.track and reaper.ValidatePtr(sel_note.track, "MediaTrack*") then
            target_track = sel_note.track
        end
    end
    
    if not target_start_qn then
        local cur_time = reaper.GetCursorPosition()
        target_start_qn = reaper.TimeMap2_timeToQN(0, cur_time)
    end
    
    -- 2. Determine target track
    if not target_track or not reaper.ValidatePtr(target_track, "MediaTrack*") then
        target_track = state.focused_track
    end
    if not target_track or not reaper.ValidatePtr(target_track, "MediaTrack*") then
        local act_take = midi_service.get_active_midi_take and midi_service.get_active_midi_take()
        if act_take then
            target_track = reaper.GetMediaItemTake_Track(act_take)
        elseif reaper.CountTracks(0) > 0 then
            target_track = reaper.GetTrack(0, 0)
        end
    end
    
    local target_track_guid = target_track and reaper.ValidatePtr(target_track, "MediaTrack*") and reaper.GetTrackGUID(target_track)
    
    reaper.Undo_BeginBlock2(0)
    
    local pasted_notes_count = 0
    local pasted_dyn_count = 0
    local pasted_hp_count = 0
    local pasted_tm_count = 0
    local pasted_ol_count = 0
    local pasted_ti_count = 0
    
    -- A. Insert notes
    if clip.notes and #clip.notes > 0 then
        if not target_track or not reaper.ValidatePtr(target_track, "MediaTrack*") then
            reaper.Undo_EndBlock2(0, "Notator: Paste failed", -1)
            state.status_msg = "Paste: No valid target track found!"
            return false
        end
        
        local target_item, target_take = midi_service.get_or_create_item_at_qn(target_track, target_start_qn, clip.total_dur_qn)
        if target_take and reaper.ValidatePtr(target_take, "MediaItem_Take*") then
            state.selected_notes = {}
            state.selected_note = nil
            
            for _, cn in ipairs(clip.notes) do
                local n_sqn = target_start_qn + cn.rel_qn
                local n_obj = midi_service.insert_note(target_take, n_sqn, cn.pitch, cn.dur_qn, cn.vel, cn.chan, cn.articulation)
                if n_obj then
                    state:select_note(n_obj)
                    pasted_notes_count = pasted_notes_count + 1
                end
            end
            reaper.MIDI_Sort(target_take)
        end
    end
    
    -- B. Insert dynamics
    if clip.dynamics and #clip.dynamics > 0 then
        if target_track and reaper.ValidatePtr(target_track, "MediaTrack*") then
            local target_item, target_take = midi_service.get_or_create_item_at_qn(target_track, target_start_qn, clip.total_dur_qn or 1.0)
            if target_take and reaper.ValidatePtr(target_take, "MediaItem_Take*") then
                for _, cd in ipairs(clip.dynamics) do
                    local d_qn = target_start_qn + (cd.rel_qn or 0.0)
                    local d_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(target_take, d_qn) + 0.5)
                    
                    -- Remove old event at same location
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(target_take)
                    for i = (text_cnt or 0) - 1, 0, -1 do
                        local ok, _, _, ppq, ev_type = reaper.MIDI_GetTextSysexEvt(target_take, i)
                        if ok and (ev_type == 15 or ev_type == 7) and math.abs(ppq - d_ppq) <= 20 then
                            reaper.MIDI_DeleteTextSysexEvt(target_take, i)
                        end
                    end
                    
                    reaper.MIDI_InsertTextSysexEvt(target_take, false, false, d_ppq, 15, string.format("dynamic %s :%d:%d", cd.label, cd.c1 or 80, cd.c11 or 85))
                    reaper.MIDI_InsertTextSysexEvt(target_take, false, false, d_ppq, 7, cd.label)
                    local cc_a = math.floor(state.dyn_cc_a or 1)
                    local cc_b = math.floor(state.dyn_cc_b or 11)
                    local cur_ppq = math.floor(d_ppq + 0.5)
                    local c1_v = math.max(0, math.min(127, math.floor((cd.c1 or 80) + 0.5)))
                    local c11_v = math.max(0, math.min(127, math.floor((cd.c11 or 85) + 0.5)))
                    reaper.MIDI_InsertCC(target_take, false, false, cur_ppq, 176, 0, cc_a, c1_v)
                    reaper.MIDI_InsertCC(target_take, false, false, cur_ppq, 176, 0, cc_b, c11_v)
                    pasted_dyn_count = pasted_dyn_count + 1
                end
                reaper.MIDI_Sort(target_take)
                
                local DynamicsEngine = package.loaded["services.dynamics_engine"] or require("services.dynamics_engine")
                if DynamicsEngine and DynamicsEngine.smart_reblend_all then
                    DynamicsEngine.smart_reblend_all(state, midi_service, active_tracks_data, target_take)
                end
            end
        end
    end
    
    -- C. Insert hairpins
    if clip.hairpins and #clip.hairpins > 0 and target_track_guid then
        local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
        for _, ch in ipairs(clip.hairpins) do
            local s_qn = target_start_qn + (ch.rel_start_qn or 0.0)
            local dur = ch.dur_qn or (ch.rel_end_qn and (ch.rel_end_qn - ch.rel_start_qn)) or 4.0
            local e_qn = s_qn + dur
            local new_hp = HairpinService.create_hairpin(
                state,
                target_track_guid,
                ch.type or "crescendo",
                s_qn,
                e_qn,
                ch.start_dyn,
                ch.end_dyn,
                midi_service,
                active_tracks_data,
                ch.staff
            )
            if new_hp then
                state.selected_hairpin = new_hp
                pasted_hp_count = pasted_hp_count + 1
            end
        end
    end
    
    -- C2. Insert dynamic texts
    local pasted_dt_count = 0
    if clip.dynamic_texts and #clip.dynamic_texts > 0 and target_track_guid then
        local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
        for _, cdt in ipairs(clip.dynamic_texts) do
            local s_qn = target_start_qn + (cdt.rel_start_qn or 0.0)
            local dur = cdt.dur_qn or 4.0
            local e_qn = s_qn + dur
            local new_dt = DynamicTextService.create_dynamic_text(
                state,
                target_track_guid,
                cdt.type or "crescendo",
                cdt.text or "cresc.",
                s_qn,
                e_qn,
                cdt.line_pattern or "none",
                cdt.curve_pattern or "linear",
                cdt.start_dyn,
                cdt.end_dyn,
                midi_service,
                active_tracks_data,
                cdt.staff
            )
            if new_dt then
                state.selected_dynamic_text = new_dt
                pasted_dt_count = pasted_dt_count + 1
            end
        end
    end
    
    -- C3. Insert pedal markings
    local pasted_pedal_count = 0
    if clip.pedals and #clip.pedals > 0 and target_track_guid then
        local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
        for _, cp in ipairs(clip.pedals) do
            local s_qn = target_start_qn + (cp.rel_start_qn or 0.0)
            local dur = cp.dur_qn or 4.0
            local e_qn = s_qn + dur
            local new_pm = PedalService.create_pedal(
                state,
                target_track_guid,
                s_qn,
                e_qn,
                cp.style or "classic",
                midi_service,
                active_tracks_data,
                cp.staff
            )
            if new_pm then
                if cp.pauses and #cp.pauses > 0 then
                    for _, p in ipairs(cp.pauses) do
                        local pqn = s_qn + (p.rel_qn or 1.0)
                        if pqn > s_qn and pqn < e_qn then
                            PedalService.add_pause_point(state, new_pm, pqn, p.type, midi_service, active_tracks_data)
                        end
                    end
                end
                state.selected_pedal = new_pm
                pasted_pedal_count = pasted_pedal_count + 1
            end
        end
    end
    
    -- D. Insert tempo markers
    if clip.tempo_markers and #clip.tempo_markers > 0 then
        local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
        for _, ctm in ipairs(clip.tempo_markers) do
            local s_qn = target_start_qn + (ctm.rel_start_qn or 0.0)
            local dur = ctm.dur_qn or 4.0
            local e_qn = s_qn + dur
            local new_tm = TempoMarker.new({
                type              = ctm.type or "absolute",
                label             = ctm.label or "",
                modifier          = ctm.modifier or "",
                bpm               = ctm.bpm or 120,
                start_qn          = s_qn,
                end_qn            = e_qn,
                target_bpm        = ctm.target_bpm,
                custom_bpm_only   = ctm.custom_bpm_only,
                custom_target_bpm = ctm.custom_target_bpm
            })
            state.tempo_markers = state.tempo_markers or {}
            table.insert(state.tempo_markers, new_tm)
            state.selected_tempo_marker = new_tm
            pasted_tm_count = pasted_tm_count + 1
        end
        TempoService.save_markers(state)
        TempoService.sync_all_to_reaper(state)
    end
    
    -- E. Insert octave lines
    if clip.octave_lines and #clip.octave_lines > 0 and target_track_guid then
        local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
        for _, col in ipairs(clip.octave_lines) do
            local s_qn = target_start_qn + (col.rel_start_qn or 0.0)
            local dur = col.dur_qn or 4.0
            local e_qn = s_qn + dur
            OctaveService.add_octave_line(state, target_track_guid, col.type or "8va", midi_service, active_tracks_data, s_qn, e_qn)
            pasted_ol_count = pasted_ol_count + 1
        end
    end
    
    -- F. Insert text items
    if clip.text_items and #clip.text_items > 0 and target_track_guid then
        local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
        for _, cti in ipairs(clip.text_items) do
            local ti_qn = target_start_qn + (cti.rel_qn or 0.0)
            local new_ti = TextItemService.create_text_item(
                state,
                target_track_guid,
                ti_qn,
                cti.offset_y or 32.0,
                cti.text or "Text",
                cti.style or "italic",
                cti.font_size or 16.0
            )
            if new_ti then
                state.selected_text_item = new_ti
                pasted_ti_count = pasted_ti_count + 1
            end
        end
    end
    
    -- Advance edit cursor if notes were inserted
    if pasted_notes_count > 0 then
        local new_cursor_qn = target_start_qn + clip.total_dur_qn
        local new_cursor_time = reaper.TimeMap2_QNToTime(0, new_cursor_qn)
        reaper.SetEditCurPos2(0, new_cursor_time, true, false)
        midi_service.sync_selection_to_reaper(state, active_tracks_data)
    end
    
    reaper.Undo_EndBlock2(0, "Notator: Paste", -1)
    reaper.UpdateArrange()
    
    local pasted_summary = {}
    if pasted_notes_count > 0 then table.insert(pasted_summary, string.format("%d note(s)", pasted_notes_count)) end
    if pasted_dyn_count > 0 then table.insert(pasted_summary, string.format("%d dynamic(s)", pasted_dyn_count)) end
    if pasted_hp_count > 0 then table.insert(pasted_summary, string.format("%d hairpin(s)", pasted_hp_count)) end
    if pasted_dt_count > 0 then table.insert(pasted_summary, string.format("%d text dynamic(s)", pasted_dt_count)) end
    if pasted_pedal_count > 0 then table.insert(pasted_summary, string.format("%d pedal mark(s)", pasted_pedal_count)) end
    if pasted_tm_count > 0 then table.insert(pasted_summary, string.format("%d tempo marker(s)", pasted_tm_count)) end
    if pasted_ol_count > 0 then table.insert(pasted_summary, string.format("%d octave line(s)", pasted_ol_count)) end
    if pasted_ti_count > 0 then table.insert(pasted_summary, string.format("%d text item(s)", pasted_ti_count)) end
    
    local summary_str = #pasted_summary > 0 and table.concat(pasted_summary, ", ") or "elements"
    state.status_msg = string.format("📥 Pasted %s at measure %.2f", summary_str, (target_start_qn / 4) + 1)
    return true
end

return ClipboardService

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

local function get_track_from_take(take)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil end
    local item = reaper.GetMediaItemTake_Item(take)
    if item and reaper.ValidatePtr(item, "MediaItem*") then
        return reaper.GetMediaItem_Track(item) or reaper.GetMediaItemTrack(item)
    end
    return nil
end

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
    
    -- 2. Check explicitly selected non-note objects (supports both single & multi-selection maps)
    local sel_dynamics = {}
    local dyn_seen = {}
    if state.selected_dynamics then
        for _, d in pairs(state.selected_dynamics) do
            if d and d.qn then
                table.insert(sel_dynamics, d)
                dyn_seen[d] = true
            end
        end
    end
    if state.selected_dynamic and not dyn_seen[state.selected_dynamic] then
        table.insert(sel_dynamics, state.selected_dynamic)
    end

    local sel_hairpins = {}
    local hp_seen = {}
    if state.selected_hairpins then
        for _, hp in pairs(state.selected_hairpins) do
            if hp and hp.id then
                table.insert(sel_hairpins, hp)
                hp_seen[hp.id] = true
            end
        end
    end
    if state.selected_hairpin and not hp_seen[state.selected_hairpin.id] then
        table.insert(sel_hairpins, state.selected_hairpin)
    end

    local sel_dynamic_texts = {}
    local dt_seen = {}
    if state.selected_dynamic_texts then
        for _, dt in pairs(state.selected_dynamic_texts) do
            if dt and dt.id then
                table.insert(sel_dynamic_texts, dt)
                dt_seen[dt.id] = true
            end
        end
    end
    if state.selected_dynamic_text and not dt_seen[state.selected_dynamic_text.id] then
        table.insert(sel_dynamic_texts, state.selected_dynamic_text)
    end

    local sel_pedals = {}
    local pm_seen = {}
    if state.selected_pedals then
        for _, pm in pairs(state.selected_pedals) do
            if pm and pm.id then
                table.insert(sel_pedals, pm)
                pm_seen[pm.id] = true
            end
        end
    end
    if state.selected_pedal and not pm_seen[state.selected_pedal.id] then
        table.insert(sel_pedals, state.selected_pedal)
    end

    local sel_tempo_markers = {}
    if state.selected_tempo_marker then
        table.insert(sel_tempo_markers, state.selected_tempo_marker)
    end

    local sel_octave_lines = {}
    local ol_seen = {}
    if state.selected_octave_lines then
        for _, ol in pairs(state.selected_octave_lines) do
            if ol and ol.id then
                table.insert(sel_octave_lines, ol)
                ol_seen[ol.id] = true
            end
        end
    end
    if state.selected_octave_line and not ol_seen[state.selected_octave_line.id] then
        table.insert(sel_octave_lines, state.selected_octave_line)
    end

    local sel_text_items = {}
    local ti_seen = {}
    if state.selected_text_items then
        for _, ti in pairs(state.selected_text_items) do
            if ti and ti.id then
                table.insert(sel_text_items, ti)
                ti_seen[ti.id] = true
            end
        end
    end
    if state.selected_text_item and not ti_seen[state.selected_text_item.id] then
        table.insert(sel_text_items, state.selected_text_item)
    end

    local has_any_selection = (#sel_notes > 0)
                           or (#sel_dynamics > 0)
                           or (#sel_hairpins > 0)
                           or (#sel_dynamic_texts > 0)
                           or (#sel_pedals > 0)
                           or (#sel_tempo_markers > 0)
                           or (#sel_octave_lines > 0)
                           or (#sel_text_items > 0)

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

    for _, d in ipairs(sel_dynamics) do
        local d_qn = d.qn or 0.0
        if d_qn < min_start_qn then min_start_qn = d_qn end
        if (d_qn + 1.0) > max_end_qn then max_end_qn = d_qn + 1.0 end
    end

    for _, hp in ipairs(sel_hairpins) do
        local hp_s = hp.start_qn or 0.0
        local hp_e = hp.end_qn or (hp_s + 4.0)
        if hp_s < min_start_qn then min_start_qn = hp_s end
        if hp_e > max_end_qn then max_end_qn = hp_e end
    end

    for _, dt in ipairs(sel_dynamic_texts) do
        local dt_s = dt.start_qn or 0.0
        local dt_e = dt.end_qn or (dt_s + 4.0)
        if dt_s < min_start_qn then min_start_qn = dt_s end
        if dt_e > max_end_qn then max_end_qn = dt_e end
    end

    for _, pm in ipairs(sel_pedals) do
        local pm_s = pm.start_qn or 0.0
        local pm_e = pm.end_qn or (pm_s + 4.0)
        if pm_s < min_start_qn then min_start_qn = pm_s end
        if pm_e > max_end_qn then max_end_qn = pm_e end
    end

    for _, tm in ipairs(sel_tempo_markers) do
        local tm_s = tm.start_qn or 0.0
        local tm_e = tm.end_qn or (tm_s + 4.0)
        if tm_s < min_start_qn then min_start_qn = tm_s end
        if tm_e > max_end_qn then max_end_qn = tm_e end
    end

    for _, ol in ipairs(sel_octave_lines) do
        local ol_s = ol.start_qn or 0.0
        local ol_e = ol.end_qn or (ol_s + 4.0)
        if ol_s < min_start_qn then min_start_qn = ol_s end
        if ol_e > max_end_qn then max_end_qn = ol_e end
    end

    for _, ti in ipairs(sel_text_items) do
        local ti_s = ti.qn or 0.0
        local ti_e = ti_s + 1.0
        if ti_s < min_start_qn then min_start_qn = ti_s end
        if ti_e > max_end_qn then max_end_qn = ti_e end
    end

    if min_start_qn > 1e8 then min_start_qn = 0.0 end
    if max_end_qn < -1e8 then max_end_qn = min_start_qn + 1.0 end

    -- 4. Store notes relative to start point (STRICTLY SELECTED NOTES ONLY)
    local clip_notes = {}
    for _, n in ipairs(sel_notes) do
        local k = (n.get_key and n:get_key()) or n.key
        local htype = n.notehead_type or (state.note_head_types and k and state.note_head_types[k])
        table.insert(clip_notes, {
            rel_qn        = n.start_qn - min_start_qn,
            pitch         = n.pitch,
            dur_qn        = n.dur_qn,
            vel           = n.vel or 96,
            chan          = n.chan or 0,
            articulation  = n.articulation,
            notehead_type = htype,
            track_guid    = n.track and reaper.ValidatePtr(n.track, "MediaTrack*") and reaper.GetTrackGUID(n.track) or nil
        })
    end

    -- 5. Capture dynamics (EXPLICITLY SELECTED DYNAMICS ONLY)
    local clip_dynamics = {}
    for _, d in ipairs(sel_dynamics) do
        local trk_guid = d.track and reaper.ValidatePtr(d.track, "MediaTrack*") and reaper.GetTrackGUID(d.track)
        table.insert(clip_dynamics, {
            rel_qn     = (d.qn or 0.0) - min_start_qn,
            label      = d.label,
            c1         = d.c1 or 80,
            c11        = d.c11 or 85,
            track_guid = trk_guid
        })
    end

    -- 6. Capture hairpins (EXPLICITLY SELECTED HAIRPINS ONLY)
    local clip_hairpins = {}
    for _, hp in ipairs(sel_hairpins) do
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
    end

    -- 6b. Capture dynamic texts (EXPLICITLY SELECTED DYNAMIC TEXTS ONLY)
    local clip_dynamic_texts = {}
    for _, dt in ipairs(sel_dynamic_texts) do
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
    end

    -- 6c. Capture pedal markings (EXPLICITLY SELECTED PEDALS ONLY)
    local clip_pedals = {}
    for _, pm in ipairs(sel_pedals) do
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
    end

    -- 7. Capture tempo markers (EXPLICITLY SELECTED TEMPO MARKERS ONLY)
    local clip_tempos = {}
    for _, tm in ipairs(sel_tempo_markers) do
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
    end

    -- 8. Capture octave lines (EXPLICITLY SELECTED OCTAVE LINES ONLY)
    local clip_octaves = {}
    for _, ol in ipairs(sel_octave_lines) do
        local dur = (ol.end_qn or (ol.start_qn + 4.0)) - ol.start_qn
        table.insert(clip_octaves, {
            rel_start_qn = ol.start_qn - min_start_qn,
            rel_end_qn   = (ol.end_qn or (ol.start_qn + 4.0)) - min_start_qn,
            dur_qn       = dur,
            type         = ol.type or "8va",
            track_guid   = ol.track_guid
        })
    end

    -- 9. Capture text items (EXPLICITLY SELECTED TEXT ITEMS ONLY)
    local clip_text_items = {}
    for _, ti in ipairs(sel_text_items) do
        table.insert(clip_text_items, {
            rel_qn     = (ti.qn or 0.0) - min_start_qn,
            offset_y   = tonumber(ti.offset_y) or 32.0,
            text       = tostring(ti.text or ""),
            style      = tostring(ti.style or "italic"),
            font_size  = tonumber(ti.font_size) or 16.0,
            track_guid = ti.track_guid,
        })
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
    if midi_service and not midi_service.delete_selected_notes and active_tracks_data and active_tracks_data.delete_selected_notes then
        midi_service, active_tracks_data = active_tracks_data, midi_service
    end
    midi_service = (midi_service and midi_service.delete_selected_notes) and midi_service or (package.loaded["services.midi_service"] or require("services.midi_service"))
    if ClipboardService.copy(state, active_tracks_data) then
        local del_parts = {}
        
        -- Delete notes
        if state.selected_notes and state:count_selected_notes() > 0 then
            local del_cnt = midi_service.delete_selected_notes(state)
            table.insert(del_parts, string.format("%d note(s)", del_cnt))
        end
        
        -- Delete dynamics (supporting both multi-selection map and single selection pointer)
        local DynamicsEngine = package.loaded["services.dynamics_engine"] or require("services.dynamics_engine")
        local dyns_to_delete = {}
        if state.selected_dynamics then
            for _, d in pairs(state.selected_dynamics) do
                table.insert(dyns_to_delete, d)
            end
        end
        if #dyns_to_delete == 0 and state.selected_dynamic then
            table.insert(dyns_to_delete, state.selected_dynamic)
        end
        if #dyns_to_delete > 0 then
            for _, d in ipairs(dyns_to_delete) do
                state.selected_dynamic = d
                DynamicsEngine.delete_selected_dynamic(state, midi_service, active_tracks_data)
            end
            state.selected_dynamic = nil
            state.selected_dynamics = {}
            table.insert(del_parts, string.format("%d dynamic(s)", #dyns_to_delete))
        end
        
        -- Delete hairpins (supporting both multi-selection map and single selection pointer)
        local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
        local hps_to_delete = {}
        if state.selected_hairpins then
            for _, hp in pairs(state.selected_hairpins) do
                table.insert(hps_to_delete, hp)
            end
        end
        if #hps_to_delete == 0 and state.selected_hairpin then
            table.insert(hps_to_delete, state.selected_hairpin)
        end
        if #hps_to_delete > 0 then
            for _, hp in ipairs(hps_to_delete) do
                HairpinService.delete_hairpin(state, hp.id, midi_service, active_tracks_data)
            end
            state.selected_hairpin = nil
            state.selected_hairpins = {}
            table.insert(del_parts, string.format("%d hairpin(s)", #hps_to_delete))
        end
        
        -- Delete dynamic texts
        local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
        local dts_to_delete = {}
        if state.selected_dynamic_texts then
            for _, dt in pairs(state.selected_dynamic_texts) do
                table.insert(dts_to_delete, dt)
            end
        end
        if #dts_to_delete == 0 and state.selected_dynamic_text then
            table.insert(dts_to_delete, state.selected_dynamic_text)
        end
        if #dts_to_delete > 0 then
            for _, dt in ipairs(dts_to_delete) do
                DynamicTextService.delete_dynamic_text(state, dt.id, midi_service, active_tracks_data)
            end
            state.selected_dynamic_text = nil
            state.selected_dynamic_texts = {}
            table.insert(del_parts, string.format("%d text dynamic(s)", #dts_to_delete))
        end
        
        -- Delete pedals
        local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
        local pedals_to_delete = {}
        if state.selected_pedals then
            for _, p in pairs(state.selected_pedals) do
                table.insert(pedals_to_delete, p)
            end
        end
        if #pedals_to_delete == 0 and state.selected_pedal then
            table.insert(pedals_to_delete, state.selected_pedal)
        end
        if #pedals_to_delete > 0 then
            for _, p in ipairs(pedals_to_delete) do
                PedalService.delete_pedal(state, p.id, midi_service, active_tracks_data)
            end
            state.selected_pedal = nil
            state.selected_pedals = {}
            table.insert(del_parts, string.format("%d pedal mark(s)", #pedals_to_delete))
        end
        
        -- Delete text items
        local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
        local tis_to_delete = {}
        if state.selected_text_items then
            for _, ti in pairs(state.selected_text_items) do
                table.insert(tis_to_delete, ti)
            end
        end
        if #tis_to_delete == 0 and state.selected_text_item then
            table.insert(tis_to_delete, state.selected_text_item)
        end
        if #tis_to_delete > 0 then
            for _, ti in ipairs(tis_to_delete) do
                TextItemService.delete_text_item(state, ti.id)
            end
            state.selected_text_item = nil
            state.selected_text_items = {}
            table.insert(del_parts, string.format("%d text item(s)", #tis_to_delete))
        end
        
        -- Delete octave lines
        local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
        local ols_to_delete = {}
        if state.selected_octave_lines then
            for _, ol in pairs(state.selected_octave_lines) do
                table.insert(ols_to_delete, ol)
            end
        end
        if #ols_to_delete == 0 and state.selected_octave_line then
            table.insert(ols_to_delete, state.selected_octave_line)
        end
        if #ols_to_delete > 0 then
            for _, ol in ipairs(ols_to_delete) do
                OctaveService.delete_octave_line(state, ol)
            end
            state.selected_octave_line = nil
            state.selected_octave_lines = {}
            table.insert(del_parts, string.format("%d octave line(s)", #ols_to_delete))
        end
        
        -- Delete tempo marker
        if state.selected_tempo_marker then
            local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
            TempoService.delete_selected_tempo_marker(state)
            state.selected_tempo_marker = nil
            table.insert(del_parts, "Tempo marker")
        end
        
        state.status_msg = string.format("✂️ Cut: %s", table.concat(del_parts, ", "))
        return true
    end
    return false
end

function ClipboardService.overwrite_track_bounds(state, target_track_guid, range_start_qn, range_end_qn, midi_service, active_tracks_data)
    if not target_track_guid or not range_start_qn or not range_end_qn then return end
    if range_end_qn < range_start_qn then
        range_start_qn, range_end_qn = range_end_qn, range_start_qn
    end

    -- 1. Remove overlapping hairpins on this staff
    if state.hairpins then
        local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
        local new_hps = {}
        local hp_changed = false
        for _, hp in ipairs(state.hairpins) do
            if hp.track_guid == target_track_guid then
                local hp_s = hp.start_qn or 0.0
                local hp_e = hp.end_qn or (hp_s + 4.0)
                if hp_s < (range_end_qn - 0.05) and hp_e > (range_start_qn + 0.05) then
                    hp_changed = true
                    if state.selected_hairpin and state.selected_hairpin.id == hp.id then
                        state.selected_hairpin = nil
                    end
                else
                    table.insert(new_hps, hp)
                end
            else
                table.insert(new_hps, hp)
            end
        end
        if hp_changed then
            state.hairpins = new_hps
            HairpinService.save_hairpins(state)
        end
    end

    -- 2. Remove overlapping dynamic texts on this staff
    if state.dynamic_texts then
        local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
        local new_dts = {}
        local dt_changed = false
        for _, dt in ipairs(state.dynamic_texts) do
            if dt.track_guid == target_track_guid then
                local dt_s = dt.start_qn or 0.0
                local dt_e = dt.end_qn or (dt_s + 4.0)
                if dt_s < (range_end_qn - 0.05) and dt_e > (range_start_qn + 0.05) then
                    dt_changed = true
                    if state.selected_dynamic_text and state.selected_dynamic_text.id == dt.id then
                        state.selected_dynamic_text = nil
                    end
                else
                    table.insert(new_dts, dt)
                end
            else
                table.insert(new_dts, dt)
            end
        end
        if dt_changed then
            state.dynamic_texts = new_dts
            DynamicTextService.save_dynamic_texts(state)
        end
    end

    -- 3. Clear existing dynamics and dynamic CCs in that range from target take
    local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
    local take = HairpinService.find_take_for_track(target_track_guid, active_tracks_data, range_start_qn)
    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        local clear_s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, range_start_qn) + 0.5)
        local clear_e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, range_end_qn) + 0.5)
        
        -- Delete dynamic Sysex / Text events
        local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
        local changed_text = false
        for i = (text_cnt or 0) - 1, 0, -1 do
            local ok, _, _, ppq, ev_type = reaper.MIDI_GetTextSysexEvt(take, i)
            if ok and (ev_type == 15 or ev_type == 7) and ppq >= (clear_s_ppq - 10) and ppq <= (clear_e_ppq + 10) then
                reaper.MIDI_DeleteTextSysexEvt(take, i)
                changed_text = true
            end
        end
        
        -- Delete CC1 and CC11 shaping in that range
        local _, _, cc_count = reaper.MIDI_CountEvts(take)
        local changed_cc = false
        for j = (cc_count or 0) - 1, 0, -1 do
            local ok, _, _, ppq, _, _, m, _ = reaper.MIDI_GetCC(take, j)
            if ok and (m == (state.dyn_cc_a or 1) or m == (state.dyn_cc_b or 11)) then
                if ppq >= (clear_s_ppq - 10) and ppq <= (clear_e_ppq + 10) then
                    reaper.MIDI_DeleteCC(take, j)
                    changed_cc = true
                end
            end
        end
        
        if changed_text or changed_cc then
            reaper.MIDI_Sort(take)
        end
    end
end

function ClipboardService.paste(state, midi_service, active_tracks_data)
    if midi_service and not midi_service.get_or_create_item_at_qn and active_tracks_data and active_tracks_data.get_or_create_item_at_qn then
        midi_service, active_tracks_data = active_tracks_data, midi_service
    end
    midi_service = (midi_service and midi_service.get_or_create_item_at_qn) and midi_service or (package.loaded["services.midi_service"] or require("services.midi_service"))
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
            target_track = get_track_from_take(act_take)
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
    
    -- Ensure target item and take exist across paste duration
    local target_item, target_take = nil, nil
    if target_track and reaper.ValidatePtr(target_track, "MediaTrack*") then
        target_item, target_take = midi_service.get_or_create_item_at_qn(target_track, target_start_qn, clip.total_dur_qn)
    end
    
    -- When pasting into an empty MIDI item, cleanly overwrite any previous staff bounds in that region
    local is_empty_take = false
    if target_take and reaper.ValidatePtr(target_take, "MediaItem_Take*") then
        local note_cnt = reaper.MIDI_CountEvts(target_take)
        if (note_cnt or 0) == 0 then
            is_empty_take = true
        end
    end
    if is_empty_take and target_track_guid and target_item then
        local it_pos = reaper.GetMediaItemInfo_Value(target_item, "D_POSITION")
        local it_len = reaper.GetMediaItemInfo_Value(target_item, "D_LENGTH")
        local it_s_qn = reaper.TimeMap2_timeToQN(0, it_pos)
        local it_e_qn = reaper.TimeMap2_timeToQN(0, it_pos + it_len)
        local clear_s = math.min(it_s_qn, target_start_qn)
        local clear_e = math.max(it_e_qn, target_start_qn + clip.total_dur_qn)
        ClipboardService.overwrite_track_bounds(state, target_track_guid, clear_s, clear_e, midi_service, active_tracks_data)
    end
    
    -- A. Insert notes
    if clip.notes and #clip.notes > 0 then
        if not target_track or not reaper.ValidatePtr(target_track, "MediaTrack*") then
            reaper.Undo_EndBlock2(0, "Notator: Paste failed", -1)
            state.status_msg = "Paste: No valid target track found!"
            return false
        end
        
        if target_take and reaper.ValidatePtr(target_take, "MediaItem_Take*") then
            state.selected_notes = {}
            state.selected_note = nil
            
            -- Overwrite mode: Cleanly wipe existing notes and notation events in the paste target range!
            local paste_s_qn = target_start_qn
            local paste_e_qn = target_start_qn + (clip.total_dur_qn or 1.0)
            local paste_s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(target_take, paste_s_qn) + 0.5)
            local paste_e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(target_take, paste_e_qn) + 0.5)
            
            reaper.MIDI_DisableSort(target_take)
            
            -- 1. Remove or truncate existing notes in [paste_s_ppq, paste_e_ppq]
            local _, notecnt = reaper.MIDI_CountEvts(target_take)
            for ni = notecnt - 1, 0, -1 do
                local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(target_take, ni)
                if ok then
                    if sppq >= (paste_s_ppq - 10) and sppq < (paste_e_ppq - 10) then
                        -- Note starts inside paste range: delete it
                        reaper.MIDI_DeleteNote(target_take, ni)
                    elseif sppq < (paste_s_ppq - 10) and eppq > (paste_s_ppq + 10) then
                        -- Note starts before paste range and extends into it: truncate to paste start
                        reaper.MIDI_SetNote(target_take, ni, sel, muted, sppq, paste_s_ppq, chan, pitch, vel, false)
                    end
                end
            end
            
            -- 2. Delete notation text events in paste range
            local _, _, _, text_cnt = reaper.MIDI_CountEvts(target_take)
            for ti = text_cnt - 1, 0, -1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(target_take, ti)
                if ok and etype == 15 and ppq >= (paste_s_ppq - 10) and ppq <= (paste_e_ppq + 10) then
                    if msg:match("^NOTE%s+") or msg:match("^NOTATOR_") or msg:match("^dynamic") then
                        reaper.MIDI_DeleteTextSysexEvt(target_take, ti)
                    end
                end
            end
            
            -- 3. Delete CCs and PCs in paste range
            local _, _, cc_cnt = reaper.MIDI_CountEvts(target_take)
            for ci = cc_cnt - 1, 0, -1 do
                local ok, _, _, ppq, chanmsg, cchan, msg2 = reaper.MIDI_GetCC(target_take, ci)
                if ok and ppq >= (paste_s_ppq - 10) and ppq <= (paste_e_ppq + 10) then
                    local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                    local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                    if is_pc or is_bank then
                        reaper.MIDI_DeleteCC(target_take, ci)
                    end
                end
            end
            
            -- 4. Overwrite any existing dynamics, hairpins, pedal lines in this range
            if target_track_guid then
                ClipboardService.overwrite_track_bounds(state, target_track_guid, paste_s_qn, paste_e_qn, midi_service, active_tracks_data)
            end
            
            -- 5. Insert pasted notes
            local has_pasted_heads = false
            for _, cn in ipairs(clip.notes) do
                local n_sqn = target_start_qn + cn.rel_qn
                local n_obj = midi_service.insert_note(target_take, n_sqn, cn.pitch, cn.dur_qn, cn.vel, cn.chan, cn.articulation)
                if n_obj then
                    if cn.notehead_type and cn.notehead_type ~= "auto" then
                        n_obj.notehead_type = cn.notehead_type
                        local n_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(target_take, n_sqn) + 0.5)
                        reaper.MIDI_InsertTextSysexEvt(target_take, false, false, n_ppq, 15, string.format("NOTATOR_NOTEHEAD %d %d %s %.4f", cn.pitch, cn.chan or 0, cn.notehead_type, n_sqn))
                        reaper.MIDI_InsertTextSysexEvt(target_take, false, false, n_ppq, 15, string.format("NOTE %d %d head %s", cn.pitch, cn.chan or 0, cn.notehead_type))
                        state.note_head_types = state.note_head_types or {}
                        local k = (n_obj.get_key and n_obj:get_key()) or n_obj.key
                        if k then state.note_head_types[k] = cn.notehead_type end
                        if target_track_guid then
                            local trk_k = string.format("trk_%s_%.3f_%d_%d", tostring(target_track_guid), n_sqn, cn.pitch, cn.chan or 0)
                            state.note_head_types[trk_k] = cn.notehead_type
                            state._persistent_notehead_records = state._persistent_notehead_records or {}
                            state._persistent_notehead_records[trk_k] = {
                                track_guid = target_track_guid,
                                start_qn = n_sqn,
                                pitch = cn.pitch,
                                chan = cn.chan or 0,
                                head = cn.notehead_type
                            }
                        end
                        has_pasted_heads = true
                    end
                    state:select_note(n_obj)
                    pasted_notes_count = pasted_notes_count + 1
                end
            end
            if has_pasted_heads and midi_service.save_notehead_types then
                midi_service.save_notehead_types(state)
            end
            
            -- 6. Auto-chase articulations on the target take
            local trk = get_track_from_take(target_take)
            local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
            local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks()
            local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, all_banks)
            midi_service.auto_chase_momentary_articulations(target_take, bank)
            
            reaper.MIDI_Sort(target_take)
        end
    end
    
    -- B. Insert dynamics
    if clip.dynamics and #clip.dynamics > 0 then
        if target_track and reaper.ValidatePtr(target_track, "MediaTrack*") then
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
            
            -- Overwrite any existing hairpins in this range so new hairpin is not crushed
            ClipboardService.overwrite_track_bounds(state, target_track_guid, s_qn, e_qn, midi_service, active_tracks_data)
            
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
            
            -- Overwrite any existing dynamic texts in this range
            ClipboardService.overwrite_track_bounds(state, target_track_guid, s_qn, e_qn, midi_service, active_tracks_data)
            
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
        state.tempo_markers = state.tempo_markers or {}
        for _, ctm in ipairs(clip.tempo_markers) do
            local s_qn = target_start_qn + (ctm.rel_start_qn or 0.0)
            local dur = ctm.dur_qn or 4.0
            local e_qn = s_qn + dur
            
            -- Deduplication check: check if marker with same type already exists at s_qn
            local existing_tm = nil
            for _, tm in ipairs(state.tempo_markers) do
                if math.abs((tm.start_qn or 0.0) - s_qn) < 0.05 and tm.type == (ctm.type or "absolute") then
                    existing_tm = tm
                    break
                end
            end
            
            if existing_tm then
                existing_tm.label = ctm.label or existing_tm.label
                existing_tm.modifier = ctm.modifier or existing_tm.modifier
                existing_tm.bpm = ctm.bpm or existing_tm.bpm
                existing_tm.end_qn = e_qn
                existing_tm.target_bpm = ctm.target_bpm
                existing_tm.custom_bpm_only = ctm.custom_bpm_only
                existing_tm.custom_target_bpm = ctm.custom_target_bpm
                state.selected_tempo_marker = existing_tm
                pasted_tm_count = pasted_tm_count + 1
            else
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
                table.insert(state.tempo_markers, new_tm)
                state.selected_tempo_marker = new_tm
                pasted_tm_count = pasted_tm_count + 1
            end
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

-- ==============================================================================
-- COPY SELECTED NOTES TO DISPLAYED SYSTEM ABOVE (-1) OR BELOW (+1)
-- Strictly uses the currently displayed tracks in active_tracks_data.
-- ==============================================================================
function ClipboardService.copy_selected_notes_to_adjacent_system(state, direction, midi_service, active_tracks_data)
    if not state or not midi_service then return false end
    local eff_tracks = active_tracks_data or state.active_tracks_cache
    if not eff_tracks or #eff_tracks == 0 then
        state.status_msg = "Copy to staff: No displayed staves found"
        return false
    end

    local selected_list = {}
    local seen_keys = {}
    if state.selected_notes then
        for k, sn in pairs(state.selected_notes) do
            if sn then
                local nk = k or (sn.get_key and sn:get_key()) or tostring(sn)
                if not seen_keys[nk] then
                    seen_keys[nk] = true
                    table.insert(selected_list, sn)
                end
            end
        end
    end
    if #selected_list == 0 and state.selected_note then
        table.insert(selected_list, state.selected_note)
    end
    if #selected_list == 0 then
        state.status_msg = "Copy to staff: No notes selected"
        return false
    end

    table.sort(selected_list, function(a, b)
        if math.abs((a.start_qn or 0) - (b.start_qn or 0)) > 0.001 then
            return (a.start_qn or 0) < (b.start_qn or 0)
        end
        return (a.pitch or 60) < (b.pitch or 60)
    end)

    -- Build lookup from track pointer / track GUID to displayed index (1 .. #eff_tracks)
    local track_to_idx = {}
    local guid_to_idx = {}
    for idx, tdata in ipairs(eff_tracks) do
        if tdata.track then
            track_to_idx[tdata.track] = idx
        end
        if tdata.guid then
            guid_to_idx[tdata.guid] = idx
        elseif tdata.track and reaper.ValidatePtr(tdata.track, "MediaTrack*") then
            guid_to_idx[reaper.GetTrackGUID(tdata.track)] = idx
        end
    end

    local dir_step = (direction and direction < 0) and -1 or 1
    local groups_by_target_idx = {}
    local target_indices_order = {}
    local skipped_boundary = 0

    local Engraver = package.loaded["rendering.engraver"] or require("rendering.engraver")

    for _, sn in ipairs(selected_list) do
        local src_trk = sn.track or (sn.take and get_track_from_take(sn.take))
        local src_guid = sn.track_guid or (src_trk and reaper.ValidatePtr(src_trk, "MediaTrack*") and reaper.GetTrackGUID(src_trk))
        local src_idx = (src_trk and track_to_idx[src_trk]) or (src_guid and guid_to_idx[src_guid])
        if src_idx then
            local dst_idx = src_idx + dir_step
            if dst_idx >= 1 and dst_idx <= #eff_tracks then
                if not groups_by_target_idx[dst_idx] then
                    groups_by_target_idx[dst_idx] = {}
                    table.insert(target_indices_order, dst_idx)
                end
                local k = (sn.get_key and sn:get_key()) or sn.key
                local head_type = sn.notehead_type
                if not head_type and Engraver and Engraver.get_note_custom_notehead_type then
                    head_type = Engraver.get_note_custom_notehead_type(sn, state)
                end
                local stem_dir = sn.stem_dir or (state.note_stem_directions and k and state.note_stem_directions[k])
                local pref_acc = (state.note_accidentals and k and state.note_accidentals[k]) or nil
                table.insert(groups_by_target_idx[dst_idx], {
                    sn = sn,
                    start_qn = sn.start_qn or 0,
                    dur_qn = sn.dur_qn or 1.0,
                    end_qn = sn.end_qn or ((sn.start_qn or 0) + (sn.dur_qn or 1.0)),
                    pitch = sn.pitch or 60,
                    vel = sn.vel or 96,
                    chan = sn.chan or 0,
                    articulation = sn.articulation,
                    notehead_type = head_type,
                    stem_dir = stem_dir,
                    pref_acc = pref_acc
                })
            else
                skipped_boundary = skipped_boundary + 1
            end
        end
    end

    if #target_indices_order == 0 then
        if skipped_boundary > 0 then
            state.status_msg = (dir_step < 0)
                and "▲ Already at top displayed staff"
                or "▼ Already at bottom displayed staff"
        else
            state.status_msg = "Copy to staff: Source staff is not in displayed track list"
        end
        return false
    end

    reaper.Undo_BeginBlock2(0)
    state:clear_selection()

    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks and ReaticulateParser.get_all_banks()
    local copied_count = 0
    local has_copied_heads = false
    local last_target_tdata = nil
    local first_new_note = nil

    for _, dst_idx in ipairs(target_indices_order) do
        local dst_tdata = eff_tracks[dst_idx]
        local dst_track = dst_tdata and dst_tdata.track
        local dst_guid = (dst_tdata and dst_tdata.guid) or (dst_track and reaper.ValidatePtr(dst_track, "MediaTrack*") and reaper.GetTrackGUID(dst_track))
        local notes_group = groups_by_target_idx[dst_idx]

        if dst_track and reaper.ValidatePtr(dst_track, "MediaTrack*") and notes_group and #notes_group > 0 then
            last_target_tdata = dst_tdata
            local min_sqn = notes_group[1].start_qn
            local max_eqn = notes_group[1].end_qn
            for _, ng in ipairs(notes_group) do
                if ng.start_qn < min_sqn then min_sqn = ng.start_qn end
                if ng.end_qn > max_eqn then max_eqn = ng.end_qn end
            end

            local target_item, target_take = midi_service.get_or_create_item_at_qn(dst_track, min_sqn, math.max(0.25, max_eqn - min_sqn))
            if target_take and reaper.ValidatePtr(target_take, "MediaItem_Take*") then
                reaper.MIDI_DisableSort(target_take)
                local ref_inserted = {}

                for _, ng in ipairs(notes_group) do
                    local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(target_take, ng.start_qn) + 0.5)
                    -- Prevent duplicate stacking at identical PPQ + pitch + channel
                    local _, existing_cnt = reaper.MIDI_CountEvts(target_take)
                    for ni = existing_cnt - 1, 0, -1 do
                        local ok, _, _, ex_sppq, _, ex_chan, ex_pitch = reaper.MIDI_GetNote(target_take, ni)
                        if ok and ex_pitch == ng.pitch and ex_chan == ng.chan and math.abs(ex_sppq - sppq) <= 10 then
                            reaper.MIDI_DeleteNote(target_take, ni)
                        end
                    end

                    local n_obj = midi_service.insert_note(target_take, ng.start_qn, ng.pitch, ng.dur_qn, ng.vel, ng.chan, ng.articulation)
                    if n_obj then
                        local eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(target_take, ng.start_qn + ng.dur_qn) + 0.5)
                        table.insert(ref_inserted, { idx = -1, pitch = ng.pitch, chan = ng.chan, sppq = sppq, eppq = eppq })
                        local new_k = (n_obj.get_key and n_obj:get_key()) or n_obj.key
                        if ng.notehead_type and ng.notehead_type ~= "auto" then
                            n_obj.notehead_type = ng.notehead_type
                            reaper.MIDI_InsertTextSysexEvt(target_take, false, false, sppq, 15, string.format("NOTATOR_NOTEHEAD %d %d %s %.4f", ng.pitch, ng.chan or 0, ng.notehead_type, ng.start_qn))
                            reaper.MIDI_InsertTextSysexEvt(target_take, false, false, sppq, 15, string.format("NOTE %d %d head %s", ng.pitch, ng.chan or 0, ng.notehead_type))
                            state.note_head_types = state.note_head_types or {}
                            if new_k then state.note_head_types[new_k] = ng.notehead_type end
                            if dst_guid then
                                local trk_k = string.format("trk_%s_%.3f_%d_%d", tostring(dst_guid), ng.start_qn, ng.pitch, ng.chan or 0)
                                state.note_head_types[trk_k] = ng.notehead_type
                            end
                            has_copied_heads = true
                        end
                        if ng.stem_dir and (ng.stem_dir == "up" or ng.stem_dir == "down") then
                            n_obj.stem_dir = ng.stem_dir
                            reaper.MIDI_InsertTextSysexEvt(target_take, false, false, sppq, 15, string.format("NOTATOR_STEM %d %d %s", ng.pitch, ng.chan or 0, ng.stem_dir))
                            state.note_stem_directions = state.note_stem_directions or {}
                            if new_k then state.note_stem_directions[new_k] = ng.stem_dir end
                        end
                        if ng.pref_acc ~= nil and new_k then
                            state.note_accidentals = state.note_accidentals or {}
                            state.note_accidentals[new_k] = ng.pref_acc
                        end
                        state:select_note(n_obj)
                        if not first_new_note then first_new_note = n_obj end
                        copied_count = copied_count + 1
                    end
                end

                midi_service.resolve_voice_conflicts(target_take, ref_inserted)
                local bank = dst_track and ReaticulateParser and ReaticulateParser.get_bank_for_track(dst_track, all_banks)
                midi_service.auto_chase_momentary_articulations(target_take, bank)
                reaper.MIDI_Sort(target_take)

                state.focused_track = dst_track
                state.selected_item = target_item
                state.selected_take = target_take
                reaper.SetOnlyTrackSelected(dst_track)
            end
        end
    end

    if has_copied_heads and midi_service.save_notehead_types then
        midi_service.save_notehead_types(state)
    end

    if midi_service.invalidate_cache then
        midi_service.invalidate_cache()
    end
    state.active_tracks_cache = nil
    midi_service.sync_selection_to_reaper(state, eff_tracks)
    reaper.UpdateArrange()

    local undo_lbl = (dir_step < 0) and "Notator: Copy Notes to Staff Above" or "Notator: Copy Notes to Staff Below"
    reaper.Undo_EndBlock2(0, undo_lbl, -1)

    if first_new_note and state.audition_notes then
        local AudioPreview = package.loaded["services.audio_preview"] or require("services.audio_preview")
        if AudioPreview and AudioPreview.play_note then
            AudioPreview.play_note(state, first_new_note.pitch, first_new_note.vel, first_new_note.chan, first_new_note.track, first_new_note.start_qn, first_new_note)
        end
    end

    local dst_name = (last_target_tdata and last_target_tdata.name) or "Target Staff"
    local arrow_lbl = (dir_step < 0) and "▲ Staff Above" or "▼ Staff Below"
    state.status_msg = string.format("Copied %d note(s) to %s (%s)", copied_count, dst_name, arrow_lbl)
    return true
end

return ClipboardService

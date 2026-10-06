-- ==============================================================================
-- REAPER Native Notator - Service: SelectionService
-- Central service for multi-selection, range selection to end (Select to End)
-- and combinable selection filters via checkboxes
-- ==============================================================================

local SelectionService = {}

function SelectionService.init_state(state)
    if not state then return end
    if not state.selected_notes then state.selected_notes = {} end
    if not state.selected_dynamics then state.selected_dynamics = {} end
    if not state.selected_hairpins then state.selected_hairpins = {} end
    if not state.selected_dynamic_texts then state.selected_dynamic_texts = {} end
    if not state.selected_pedals then state.selected_pedals = {} end
    if not state.selected_text_items then state.selected_text_items = {} end
    if not state.selected_octave_lines then state.selected_octave_lines = {} end

    if not state.selection_filter then
        state.selection_filter = {
            notes = true,
            dynamics = true,
            hairpins = true,
            dynamic_texts = true,
            text_items = true,
            pedals = true,
            octaves = true,
            articulations_only = false
        }
    end
end

-- Checks if at least one score object is currently selected
function SelectionService.has_selection(state)
    if not state then return false end
    if state.count_selected_notes and state:count_selected_notes() > 0 then return true end
    if state.selected_notes and next(state.selected_notes) ~= nil then return true end
    if state.selected_dynamic or (state.selected_dynamics and next(state.selected_dynamics) ~= nil) then return true end
    if state.selected_hairpin or (state.selected_hairpins and next(state.selected_hairpins) ~= nil) then return true end
    if state.selected_dynamic_text or (state.selected_dynamic_texts and next(state.selected_dynamic_texts) ~= nil) then return true end
    if state.selected_pedal or (state.selected_pedals and next(state.selected_pedals) ~= nil) then return true end
    if state.selected_text_item or (state.selected_text_items and next(state.selected_text_items) ~= nil) then return true end
    if state.selected_octave_line or (state.selected_octave_lines and next(state.selected_octave_lines) ~= nil) then return true end
    if state.selected_tempo_marker then return true end
    return false
end

-- Counts all currently selected elements by category
function SelectionService.count_all_selected(state)
    if not state then return 0, 0, 0, 0, 0, 0, 0 end
    local n_cnt = (state.count_selected_notes and state:count_selected_notes()) or 0
    local d_cnt = 0
    if state.selected_dynamics and next(state.selected_dynamics) ~= nil then
        for _ in pairs(state.selected_dynamics) do d_cnt = d_cnt + 1 end
    elseif state.selected_dynamic then
        d_cnt = 1
    end
    local hp_cnt = 0
    if state.selected_hairpins and next(state.selected_hairpins) ~= nil then
        for _ in pairs(state.selected_hairpins) do hp_cnt = hp_cnt + 1 end
    elseif state.selected_hairpin then
        hp_cnt = 1
    end
    local dt_cnt = 0
    if state.selected_dynamic_texts and next(state.selected_dynamic_texts) ~= nil then
        for _ in pairs(state.selected_dynamic_texts) do dt_cnt = dt_cnt + 1 end
    elseif state.selected_dynamic_text then
        dt_cnt = 1
    end
    local p_cnt = 0
    if state.selected_pedals and next(state.selected_pedals) ~= nil then
        for _ in pairs(state.selected_pedals) do p_cnt = p_cnt + 1 end
    elseif state.selected_pedal then
        p_cnt = 1
    end
    local ti_cnt = 0
    if state.selected_text_items and next(state.selected_text_items) ~= nil then
        for _ in pairs(state.selected_text_items) do ti_cnt = ti_cnt + 1 end
    elseif state.selected_text_item then
        ti_cnt = 1
    end
    local ol_cnt = 0
    if state.selected_octave_lines and next(state.selected_octave_lines) ~= nil then
        for _ in pairs(state.selected_octave_lines) do ol_cnt = ol_cnt + 1 end
    elseif state.selected_octave_line then
        ol_cnt = 1
    end
    local sl_cnt = state.selected_slur and 1 or 0
    local tie_cnt = state.selected_tie and 1 or 0
    return n_cnt, d_cnt, hp_cnt, dt_cnt, p_cnt, ti_cnt, ol_cnt, sl_cnt, tie_cnt
end

-- Determines the earliest start QN and bounds of current selection
function SelectionService.get_selection_bounds(state)
    local min_qn = nil
    local max_qn = nil
    local target_tracks = {}

    local function add_range(sqn, eqn, trk_guid)
        if sqn then
            if min_qn == nil or sqn < min_qn then min_qn = sqn end
            local e = eqn or (sqn + 1.0)
            if max_qn == nil or e > max_qn then max_qn = e end
        end
        if trk_guid then target_tracks[trk_guid] = true end
    end

    if state.selected_notes then
        for _, n in pairs(state.selected_notes) do
            local guid = n.track and reaper.GetTrackGUID(n.track)
            add_range(n.start_qn, n.end_qn, guid)
        end
    end
    if state.selected_dynamics and next(state.selected_dynamics) ~= nil then
        for _, d in pairs(state.selected_dynamics) do
            local guid = d.track and reaper.GetTrackGUID(d.track)
            add_range(d.qn, d.qn + 1.0, guid)
        end
    elseif state.selected_dynamic and state.selected_dynamic.qn then
        local guid = state.selected_dynamic.track and reaper.GetTrackGUID(state.selected_dynamic.track)
        add_range(state.selected_dynamic.qn, state.selected_dynamic.qn + 1.0, guid)
    end
    if state.selected_hairpins and next(state.selected_hairpins) ~= nil then
        for _, hp in pairs(state.selected_hairpins) do
            add_range(hp.start_qn, hp.end_qn, hp.track_guid)
        end
    elseif state.selected_hairpin and state.selected_hairpin.start_qn then
        add_range(state.selected_hairpin.start_qn, state.selected_hairpin.end_qn, state.selected_hairpin.track_guid)
    end
    if state.selected_dynamic_texts and next(state.selected_dynamic_texts) ~= nil then
        for _, dt in pairs(state.selected_dynamic_texts) do
            add_range(dt.start_qn, dt.end_qn, dt.track_guid)
        end
    elseif state.selected_dynamic_text and state.selected_dynamic_text.start_qn then
        add_range(state.selected_dynamic_text.start_qn, state.selected_dynamic_text.end_qn, state.selected_dynamic_text.track_guid)
    end
    if state.selected_pedals and next(state.selected_pedals) ~= nil then
        for _, pm in pairs(state.selected_pedals) do
            add_range(pm.start_qn, pm.end_qn, pm.track_guid)
        end
    elseif state.selected_pedal and state.selected_pedal.start_qn then
        add_range(state.selected_pedal.start_qn, state.selected_pedal.end_qn, state.selected_pedal.track_guid)
    end
    if state.selected_text_items and next(state.selected_text_items) ~= nil then
        for _, ti in pairs(state.selected_text_items) do
            add_range(ti.qn, ti.qn + 1.0, ti.track_guid)
        end
    elseif state.selected_text_item and state.selected_text_item.qn then
        add_range(state.selected_text_item.qn, state.selected_text_item.qn + 1.0, state.selected_text_item.track_guid)
    end
    if state.selected_octave_lines and next(state.selected_octave_lines) ~= nil then
        for _, ol in pairs(state.selected_octave_lines) do
            add_range(ol.start_qn, ol.end_qn, ol.track_guid)
        end
    elseif state.selected_octave_line and state.selected_octave_line.start_qn then
        add_range(state.selected_octave_line.start_qn, state.selected_octave_line.end_qn, state.selected_octave_line.track_guid)
    end

    -- Fallback: Edit Cursor Position
    if min_qn == nil then
        local cur_pos = reaper.GetCursorPosition()
        min_qn = reaper.TimeMap2_timeToQN(0, cur_pos)
        max_qn = min_qn + 4.0
    end
    if max_qn == nil then max_qn = min_qn + 4.0 end

    -- If selection was created in "Select to End" mode:
    if state.selection_is_to_end then
        max_qn = math.huge
    end

    -- If track is focused:
    if state.focused_track and reaper.ValidatePtr(state.focused_track, "MediaTrack*") then
        local f_guid = reaper.GetTrackGUID(state.focused_track)
        target_tracks[f_guid] = true
    end

    return min_qn, max_qn, target_tracks
end

-- Selects all notes, dynamics and events from current selection to end of track
function SelectionService.select_to_end(state, active_tracks_data, midi_service)
    SelectionService.init_state(state)
    local min_qn = SelectionService.get_selection_bounds(state)
    local start_qn = min_qn or 0.0
    state.selection_is_to_end = true
    state.selection_bounds = { start_qn = start_qn, end_qn = math.huge }

    -- Enable all filter checkboxes as everything is selected
    state.selection_filter.notes = true
    state.selection_filter.dynamics = true
    state.selection_filter.hairpins = true
    state.selection_filter.dynamic_texts = true
    state.selection_filter.text_items = true
    state.selection_filter.pedals = true
    state.selection_filter.octaves = true
    state.selection_filter.articulations_only = false

    SelectionService.apply_filter(state, active_tracks_data, midi_service)
end

-- Applies combined checkbox filters to current selection
function SelectionService.apply_filter(state, active_tracks_data, midi_service)
    SelectionService.init_state(state)
    
    -- Determine selection bounds
    local min_qn, max_qn, target_tracks
    if state.selection_bounds then
        min_qn = state.selection_bounds.start_qn
        max_qn = state.selection_bounds.end_qn
    else
        min_qn, max_qn, target_tracks = SelectionService.get_selection_bounds(state)
        state.selection_bounds = { start_qn = min_qn, end_qn = max_qn }
    end
    if not target_tracks or next(target_tracks) == nil then
        target_tracks = {}
        if state.focused_track and reaper.ValidatePtr(state.focused_track, "MediaTrack*") then
            target_tracks[reaper.GetTrackGUID(state.focused_track)] = true
        elseif active_tracks_data and #active_tracks_data > 0 then
            target_tracks[active_tracks_data[1].guid] = true
        end
    end

    local flt = state.selection_filter

    local is_measure = (state.selection_bounds and state.selection_bounds.is_measure_selection)
    local function in_range(pos_qn)
        if not pos_qn then return false end
        if is_measure then
            return pos_qn >= (min_qn - 0.005) and pos_qn < (max_qn - 0.005)
        else
            return pos_qn >= (min_qn - 0.01) and pos_qn <= (max_qn + 0.01)
        end
    end

    -- 1. Notes
    state.selected_notes = {}
    state.selected_note = nil
    local n_cnt = 0
    if flt.notes and active_tracks_data then
        for _, td in ipairs(active_tracks_data) do
            if target_tracks[td.guid] then
                for _, n in ipairs(td.notes or {}) do
                    if in_range(n.start_qn) then
                        if not flt.articulations_only or (n.articulation and n.articulation ~= "") then
                            state:select_note(n)
                            n_cnt = n_cnt + 1
                        end
                    end
                end
            end
        end
    end

    -- 2. Dynamics
    state.selected_dynamics = {}
    state.selected_dynamic = nil
    local d_cnt = 0
    if flt.dynamics and active_tracks_data then
        for _, td in ipairs(active_tracks_data) do
            if target_tracks[td.guid] then
                for _, d in ipairs(td.dynamics or {}) do
                    if in_range(d.qn) then
                        state.selected_dynamics[d.key or d] = d
                        if not state.selected_dynamic then state.selected_dynamic = d end
                        d_cnt = d_cnt + 1
                    end
                end
            end
        end
    end

    -- 3. Hairpins
    state.selected_hairpins = {}
    state.selected_hairpin = nil
    local hp_cnt = 0
    if flt.hairpins then
        local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
        if HairpinService and active_tracks_data then
            for _, td in ipairs(active_tracks_data) do
                if target_tracks[td.guid] then
                    local hps = HairpinService.get_hairpins_for_track(state, td.guid)
                    for _, hp in ipairs(hps or {}) do
                        if in_range(hp.start_qn) then
                            state.selected_hairpins[hp.id] = hp
                            if not state.selected_hairpin then state.selected_hairpin = hp end
                            hp_cnt = hp_cnt + 1
                        end
                    end
                end
            end
        end
    end

    -- 4. Dynamic Texts (Cresc. / Dim. Tags)
    state.selected_dynamic_texts = {}
    state.selected_dynamic_text = nil
    local dt_cnt = 0
    if flt.dynamic_texts then
        local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
        if DynamicTextService and active_tracks_data then
            for _, td in ipairs(active_tracks_data) do
                if target_tracks[td.guid] then
                    local dts = DynamicTextService.get_dynamic_texts_for_track(state, td.guid)
                    for _, dt in ipairs(dts or {}) do
                        if in_range(dt.start_qn) then
                            state.selected_dynamic_texts[dt.id] = dt
                            if not state.selected_dynamic_text then state.selected_dynamic_text = dt end
                            dt_cnt = dt_cnt + 1
                        end
                    end
                end
            end
        end
    end

    -- 5. Text Items
    state.selected_text_items = {}
    state.selected_text_item = nil
    local ti_cnt = 0
    if flt.text_items then
        local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
        if TextItemService and active_tracks_data then
            for _, td in ipairs(active_tracks_data) do
                if target_tracks[td.guid] then
                    local tis = TextItemService.get_text_items_for_track(state, td.guid)
                    for _, ti in ipairs(tis or {}) do
                        if in_range(ti.qn) then
                            state.selected_text_items[ti.id] = ti
                            if not state.selected_text_item then state.selected_text_item = ti end
                            ti_cnt = ti_cnt + 1
                        end
                    end
                end
            end
        end
    end

    -- 6. Pedale
    state.selected_pedals = {}
    state.selected_pedal = nil
    local p_cnt = 0
    if flt.pedals then
        local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
        if PedalService and active_tracks_data then
            for _, td in ipairs(active_tracks_data) do
                if target_tracks[td.guid] then
                    local pms = PedalService.get_pedals_for_track(state, td.guid)
                    for _, pm in ipairs(pms or {}) do
                        if in_range(pm.start_qn) then
                            state.selected_pedals[pm.id] = pm
                            if not state.selected_pedal then state.selected_pedal = pm end
                            p_cnt = p_cnt + 1
                        end
                    end
                end
            end
        end
    end

    -- 7. Octave Lines
    state.selected_octave_lines = {}
    state.selected_octave_line = nil
    local ol_cnt = 0
    if flt.octaves then
        local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
        if OctaveService and active_tracks_data then
            for _, td in ipairs(active_tracks_data) do
                if target_tracks[td.guid] then
                    local ols = OctaveService.get_lines_for_track(state, td.guid)
                    for _, ol in ipairs(ols or {}) do
                        if in_range(ol.start_qn) then
                            state.selected_octave_lines[ol.id] = ol
                            if not state.selected_octave_line then state.selected_octave_line = ol end
                            ol_cnt = ol_cnt + 1
                        end
                    end
                end
            end
        end
    end

    if midi_service then
        midi_service.sync_selection_to_reaper(state, active_tracks_data)
    end
    
    local total = n_cnt + d_cnt + hp_cnt + dt_cnt + ti_cnt + p_cnt + ol_cnt
    state.status_msg = string.format("Filter active: %d items selected (%d notes, %d dyn, %d hairpins, %d text)", total, n_cnt, d_cnt, hp_cnt, ti_cnt)
end

-- Selects everything on the track
function SelectionService.select_all_in_track(state, active_tracks_data, midi_service)
    SelectionService.init_state(state)
    state.selection_is_to_end = false
    state.selection_bounds = { start_qn = 0.0, end_qn = math.huge }
    
    state.selection_filter.notes = true
    state.selection_filter.dynamics = true
    state.selection_filter.hairpins = true
    state.selection_filter.dynamic_texts = true
    state.selection_filter.text_items = true
    state.selection_filter.pedals = true
    state.selection_filter.octaves = true
    state.selection_filter.articulations_only = false

    SelectionService.apply_filter(state, active_tracks_data, midi_service)
end

-- Selects all elements in a specific measure on focused track
function SelectionService.select_measure(state, measure_idx, active_tracks_data, midi_service, qn_per_measure)
    SelectionService.init_state(state)
    local start_qn, end_qn
    if reaper.TimeMap2_beatsToTime then
        local t0 = reaper.TimeMap2_beatsToTime(0, 0, measure_idx)
        local t1 = reaper.TimeMap2_beatsToTime(0, 0, measure_idx + 1)
        start_qn = reaper.TimeMap2_timeToQN(0, t0)
        end_qn = reaper.TimeMap2_timeToQN(0, t1)
    else
        local qn_pm = qn_per_measure or 4.0
        start_qn = measure_idx * qn_pm
        end_qn = (measure_idx + 1) * qn_pm
    end

    state.selection_is_to_end = false
    state.selection_bounds = {
        start_qn = start_qn,
        end_qn = end_qn,
        is_measure_selection = true
    }
    
    state.selection_filter.notes = true
    state.selection_filter.dynamics = true
    state.selection_filter.hairpins = true
    state.selection_filter.dynamic_texts = true
    state.selection_filter.text_items = true
    state.selection_filter.pedals = true
    state.selection_filter.octaves = true
    state.selection_filter.articulations_only = false

    SelectionService.apply_filter(state, active_tracks_data, midi_service)
    state.status_msg = string.format("Selected notes in bar %d", measure_idx + 1)
end

-- Filter Preset: Notes Only
function SelectionService.set_filter_notes_only(state, active_tracks_data, midi_service)
    SelectionService.init_state(state)
    state.selection_filter.notes = true
    state.selection_filter.dynamics = false
    state.selection_filter.hairpins = false
    state.selection_filter.dynamic_texts = false
    state.selection_filter.text_items = false
    state.selection_filter.pedals = false
    state.selection_filter.octaves = false
    state.selection_filter.articulations_only = false
    SelectionService.apply_filter(state, active_tracks_data, midi_service)
end

-- Filter Preset: Dynamics & Hairpins Only
function SelectionService.set_filter_dynamics_only(state, active_tracks_data, midi_service)
    SelectionService.init_state(state)
    state.selection_filter.notes = false
    state.selection_filter.dynamics = true
    state.selection_filter.hairpins = true
    state.selection_filter.dynamic_texts = true
    state.selection_filter.text_items = false
    state.selection_filter.pedals = false
    state.selection_filter.octaves = false
    state.selection_filter.articulations_only = false
    SelectionService.apply_filter(state, active_tracks_data, midi_service)
end

-- Filter Preset: Enable All
function SelectionService.set_filter_all_on(state, active_tracks_data, midi_service)
    SelectionService.init_state(state)
    state.selection_filter.notes = true
    state.selection_filter.dynamics = true
    state.selection_filter.hairpins = true
    state.selection_filter.dynamic_texts = true
    state.selection_filter.text_items = true
    state.selection_filter.pedals = true
    state.selection_filter.octaves = true
    state.selection_filter.articulations_only = false
    SelectionService.apply_filter(state, active_tracks_data, midi_service)
end

-- Filter Preset: Disable All
function SelectionService.set_filter_all_off(state, active_tracks_data, midi_service)
    SelectionService.init_state(state)
    state.selection_filter.notes = false
    state.selection_filter.dynamics = false
    state.selection_filter.hairpins = false
    state.selection_filter.dynamic_texts = false
    state.selection_filter.text_items = false
    state.selection_filter.pedals = false
    state.selection_filter.octaves = false
    state.selection_filter.articulations_only = false
    SelectionService.apply_filter(state, active_tracks_data, midi_service)
end

-- Deletes all currently selected objects (notes, dynamics, hairpins, pedals, etc.)
function SelectionService.delete_all_selected(state, midi_service, active_tracks_data)
    local any_deleted = false
    
    -- Delete notes
    if state.count_selected_notes and state:count_selected_notes() > 0 then
        if midi_service then
            midi_service.delete_selected_notes(state)
            any_deleted = true
        end
    end
    
    -- Delete dynamic markers
    local to_del_dyns = {}
    if state.selected_dynamics and next(state.selected_dynamics) ~= nil then
        for _, d in pairs(state.selected_dynamics) do table.insert(to_del_dyns, d) end
    elseif state.selected_dynamic then
        table.insert(to_del_dyns, state.selected_dynamic)
    end
    if #to_del_dyns > 0 then
        local DynamicsEngine = package.loaded["services.dynamics_engine"] or require("services.dynamics_engine")
        for _, d in ipairs(to_del_dyns) do
            state.selected_dynamic = d
            DynamicsEngine.delete_selected_dynamic(state, midi_service, active_tracks_data)
        end
        state.selected_dynamics = {}
        state.selected_dynamic = nil
        any_deleted = true
    end
    
    -- Delete hairpins
    local to_del_hp = {}
    if state.selected_hairpins and next(state.selected_hairpins) ~= nil then
        for _, hp in pairs(state.selected_hairpins) do table.insert(to_del_hp, hp) end
    elseif state.selected_hairpin then
        table.insert(to_del_hp, state.selected_hairpin)
    end
    if #to_del_hp > 0 then
        local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
        for _, hp in ipairs(to_del_hp) do
            HairpinService.delete_hairpin(state, hp.id, midi_service, active_tracks_data)
        end
        state.selected_hairpins = {}
        state.selected_hairpin = nil
        any_deleted = true
    end
    
    -- Delete dynamic texts
    local to_del_dt = {}
    if state.selected_dynamic_texts and next(state.selected_dynamic_texts) ~= nil then
        for _, dt in pairs(state.selected_dynamic_texts) do table.insert(to_del_dt, dt) end
    elseif state.selected_dynamic_text then
        table.insert(to_del_dt, state.selected_dynamic_text)
    end
    if #to_del_dt > 0 then
        local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
        for _, dt in ipairs(to_del_dt) do
            DynamicTextService.delete_dynamic_text(state, dt.id, midi_service, active_tracks_data)
        end
        state.selected_dynamic_texts = {}
        state.selected_dynamic_text = nil
        any_deleted = true
    end
    
    -- Delete pedals
    local to_del_pm = {}
    if state.selected_pedals and next(state.selected_pedals) ~= nil then
        for _, pm in pairs(state.selected_pedals) do table.insert(to_del_pm, pm) end
    elseif state.selected_pedal then
        table.insert(to_del_pm, state.selected_pedal)
    end
    if #to_del_pm > 0 then
        local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
        for _, pm in ipairs(to_del_pm) do
            PedalService.delete_pedal(state, pm.id, midi_service, active_tracks_data)
        end
        state.selected_pedals = {}
        state.selected_pedal = nil
        any_deleted = true
    end
    
    -- Delete text items
    local to_del_ti = {}
    if state.selected_text_items and next(state.selected_text_items) ~= nil then
        for _, ti in pairs(state.selected_text_items) do table.insert(to_del_ti, ti) end
    elseif state.selected_text_item then
        table.insert(to_del_ti, state.selected_text_item)
    end
    if #to_del_ti > 0 then
        local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
        for _, ti in ipairs(to_del_ti) do
            TextItemService.delete_text_item(state, ti.id)
        end
        state.selected_text_items = {}
        state.selected_text_item = nil
        any_deleted = true
    end
    
    -- Delete octave lines
    local to_del_ol = {}
    if state.selected_octave_lines and next(state.selected_octave_lines) ~= nil then
        for _, ol in pairs(state.selected_octave_lines) do table.insert(to_del_ol, ol) end
    elseif state.selected_octave_line then
        table.insert(to_del_ol, state.selected_octave_line)
    end
    if #to_del_ol > 0 then
        local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
        for _, ol in ipairs(to_del_ol) do
            OctaveService.delete_line(state, ol.id)
        end
        state.selected_octave_lines = {}
        state.selected_octave_line = nil
        any_deleted = true
    end

    -- Delete selected slur
    if state.selected_slur then
        local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
        SlurService.delete_slur(state, state.selected_slur.id, midi_service, active_tracks_data)
        state.selected_slur = nil
        any_deleted = true
    end

    -- Delete selected tie
    if state.selected_tie then
        local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
        SlurService.delete_tie(state, state.selected_tie.id, midi_service, active_tracks_data)
        state.selected_tie = nil
        any_deleted = true
    end

    -- Delete selected articulation(s)
    if (state.selected_articulations and state.count_selected_articulations and state:count_selected_articulations() > 0) or state.selected_articulation then
        if midi_service and midi_service.delete_selected_articulations then
            midi_service.delete_selected_articulations(state)
            any_deleted = true
        end
    end

    if midi_service then
        midi_service.sync_selection_to_reaper(state, active_tracks_data)
    end
    return any_deleted
end

-- Renders the interactive selection & filter menu with checkboxes in right-click context menu
function SelectionService.render_menu_items(ctx, state, active_tracks_data, midi_service)
    SelectionService.init_state(state)
    local n_cnt, d_cnt, hp_cnt, dt_cnt, p_cnt, ti_cnt, ol_cnt, sl_cnt, tie_cnt = SelectionService.count_all_selected(state)
    local total_cnt = n_cnt + d_cnt + hp_cnt + dt_cnt + p_cnt + ti_cnt + ol_cnt + (sl_cnt or 0) + (tie_cnt or 0)
    
    reaper.ImGui_TextColored(ctx, 0x3498DBFF, string.format("SELECTION (%d Item%s)", total_cnt, total_cnt == 1 and "" or "s"))
    reaper.ImGui_Separator(ctx)
    
    if reaper.ImGui_MenuItem(ctx, ">> Select to End (Ctrl+Shift+E)") then
        SelectionService.select_to_end(state, active_tracks_data, midi_service)
    end
    
    if reaper.ImGui_MenuItem(ctx, ">> Select All on Track (Ctrl+A)##selection_menu") then
        SelectionService.select_all_in_track(state, active_tracks_data, midi_service)
    end

    if reaper.ImGui_MenuItem(ctx, ">> Notes Only (Ctrl+Shift+N)") then
        SelectionService.set_filter_notes_only(state, active_tracks_data, midi_service)
    end
    
    if reaper.ImGui_BeginMenu(ctx, ">> Filter Notes by Voice...") then
        for v = 1, 16 do
            if reaper.ImGui_MenuItem(ctx, string.format("Voice %d Only (Channel %d)", v, v)) then
                local new_sel = {}
                for k, n in pairs(state.selected_notes) do
                    if (n.chan or 0) == (v - 1) then
                        new_sel[k] = n
                    end
                end
                state.selected_notes = new_sel
                for _, sn in pairs(new_sel) do state.selected_note = sn break end
                if midi_service and midi_service.sync_selection_to_reaper then
                    midi_service.sync_selection_to_reaper(state, active_tracks_data)
                end
                state.status_msg = string.format("Filter: Kept %d notes in Voice %d", state:count_selected_notes(), v)
            end
        end
        reaper.ImGui_EndMenu(ctx)
    end

    if reaper.ImGui_MenuItem(ctx, ">> Dynamics & Hairpins Only (Ctrl+Shift+Y)") then
        SelectionService.set_filter_dynamics_only(state, active_tracks_data, midi_service)
    end
    
    reaper.ImGui_Separator(ctx)
    reaper.ImGui_TextColored(ctx, 0xF39C12FF, "Filter Checkboxes (combinable):")
    
    -- Quick action buttons
    if reaper.ImGui_SmallButton(ctx, "Notes") then
        SelectionService.set_filter_notes_only(state, active_tracks_data, midi_service)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "Dynamics") then
        SelectionService.set_filter_dynamics_only(state, active_tracks_data, midi_service)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "All On") then
        SelectionService.set_filter_all_on(state, active_tracks_data, midi_service)
    end
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "All Off") then
        SelectionService.set_filter_all_off(state, active_tracks_data, midi_service)
    end
    
    local flt = state.selection_filter
    
    -- 1. Notes Checkbox
    local chk_n, val_n = reaper.ImGui_Checkbox(ctx, string.format("[Note] Notes (%d)", n_cnt), flt.notes)
    if chk_n then
        flt.notes = val_n
        SelectionService.apply_filter(state, active_tracks_data, midi_service)
    end
    
    if flt.notes then
        reaper.ImGui_SameLine(ctx)
        local chk_art, val_art = reaper.ImGui_Checkbox(ctx, "With Art. Only", flt.articulations_only)
        if chk_art then
            flt.articulations_only = val_art
            SelectionService.apply_filter(state, active_tracks_data, midi_service)
        end
    end
    
    -- 2. Dynamic Markers Checkbox
    local chk_d, val_d = reaper.ImGui_Checkbox(ctx, string.format("[Dyn] Dynamic Markers (%d)", d_cnt), flt.dynamics)
    if chk_d then
        flt.dynamics = val_d
        SelectionService.apply_filter(state, active_tracks_data, midi_service)
    end
    
    -- 3. Hairpins Checkbox
    local chk_hp, val_hp = reaper.ImGui_Checkbox(ctx, string.format("[<>] Hairpins (%d)", hp_cnt), flt.hairpins)
    if chk_hp then
        flt.hairpins = val_hp
        SelectionService.apply_filter(state, active_tracks_data, midi_service)
    end
    
    -- 4. Dynamic Texts Checkbox
    local chk_dt, val_dt = reaper.ImGui_Checkbox(ctx, string.format("[cresc] Dynamic Texts (%d)", dt_cnt), flt.dynamic_texts)
    if chk_dt then
        flt.dynamic_texts = val_dt
        SelectionService.apply_filter(state, active_tracks_data, midi_service)
    end
    
    -- 5. Text Items Checkbox
    local chk_ti, val_ti = reaper.ImGui_Checkbox(ctx, string.format("[Text] Text Items (%d)", ti_cnt), flt.text_items)
    if chk_ti then
        flt.text_items = val_ti
        SelectionService.apply_filter(state, active_tracks_data, midi_service)
    end
    
    -- 6. Pedals Checkbox
    local chk_p, val_p = reaper.ImGui_Checkbox(ctx, string.format("[Ped] Pedal Lines (%d)", p_cnt), flt.pedals)
    if chk_p then
        flt.pedals = val_p
        SelectionService.apply_filter(state, active_tracks_data, midi_service)
    end
    
    -- 7. Octave Lines Checkbox
    local chk_ol, val_ol = reaper.ImGui_Checkbox(ctx, string.format("[8va] Octave Lines (%d)", ol_cnt), flt.octaves)
    if chk_ol then
        flt.octaves = val_ol
        SelectionService.apply_filter(state, active_tracks_data, midi_service)
    end
    
    reaper.ImGui_Separator(ctx)
    if reaper.ImGui_MenuItem(ctx, "Deselect All (Esc)") then
        state:clear_selection()
        state.selection_bounds = nil
        state.selection_is_to_end = false
        if midi_service then midi_service.sync_selection_to_reaper(state, active_tracks_data) end
    end
    
    reaper.ImGui_Separator(ctx)
end

-- ==============================================================================
-- Keyboard Note Navigation (Alt + Arrow keys)
-- Navigates between notes/chords on the timeline and voices within a chord.
-- Auto-scrolling occurs strictly when state.auto_scroll is active.
-- ==============================================================================
function SelectionService.navigate_note(state, active_tracks_data, midi_service, direction, extend)
    if not state then return end
    
    local cur_note = state.selected_note
    local cur_track = (cur_note and cur_note.track) or state.focused_track
    if not cur_track or not reaper.ValidatePtr(cur_track, "MediaTrack*") then
        local sel_trk = reaper.GetSelectedTrack(0, 0)
        if sel_trk and reaper.ValidatePtr(sel_trk, "MediaTrack*") then
            cur_track = sel_trk
        elseif active_tracks_data and active_tracks_data[1] and active_tracks_data[1].track then
            cur_track = active_tracks_data[1].track
        end
    end

    -- Collect all notes for the active track
    local track_notes = {}
    if active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if not cur_track or tdata.track == cur_track then
                if tdata.notes then
                    for _, n in ipairs(tdata.notes) do
                        table.insert(track_notes, n)
                    end
                end
            end
        end
    end

    if #track_notes == 0 then
        state.status_msg = "No notes available to navigate on active track"
        return
    end

    -- Sort notes chronologically, then by pitch ascending
    table.sort(track_notes, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.001 then
            return a.start_qn < b.start_qn
        end
        return (a.pitch or 60) < (b.pitch or 60)
    end)

    local target_note = nil

    if direction == "next" then
        if cur_note then
            -- Find the earliest onset strictly after current note's start_qn
            local min_next_qn = nil
            for _, n in ipairs(track_notes) do
                if n.start_qn > cur_note.start_qn + 0.005 then
                    if min_next_qn == nil or n.start_qn < min_next_qn then
                        min_next_qn = n.start_qn
                    end
                end
            end
            if min_next_qn ~= nil then
                local best_dist = 999
                for _, n in ipairs(track_notes) do
                    if math.abs(n.start_qn - min_next_qn) < 0.005 then
                        local dist = math.abs((n.pitch or 60) - (cur_note.pitch or 60))
                        if dist < best_dist then
                            best_dist = dist
                            target_note = n
                        end
                    end
                end
            end
        else
            -- If no note is selected, find the first note at or after current edit cursor
            local cur_pos = reaper.GetCursorPosition()
            local cur_qn = reaper.TimeMap2_timeToQN(0, cur_pos)
            for _, n in ipairs(track_notes) do
                if n.start_qn >= cur_qn - 0.005 then
                    target_note = n
                    break
                end
            end
            if not target_note then
                target_note = track_notes[1]
            end
        end

    elseif direction == "prev" then
        if cur_note then
            -- Find the latest onset strictly before current note's start_qn
            local max_prev_qn = nil
            for _, n in ipairs(track_notes) do
                if n.start_qn < cur_note.start_qn - 0.005 then
                    if max_prev_qn == nil or n.start_qn > max_prev_qn then
                        max_prev_qn = n.start_qn
                    end
                end
            end
            if max_prev_qn ~= nil then
                local best_dist = 999
                for _, n in ipairs(track_notes) do
                    if math.abs(n.start_qn - max_prev_qn) < 0.005 then
                        local dist = math.abs((n.pitch or 60) - (cur_note.pitch or 60))
                        if dist < best_dist then
                            best_dist = dist
                            target_note = n
                        end
                    end
                end
            end
        else
            -- If no note is selected, find the last note at or before current edit cursor
            local cur_pos = reaper.GetCursorPosition()
            local cur_qn = reaper.TimeMap2_timeToQN(0, cur_pos)
            for i = #track_notes, 1, -1 do
                local n = track_notes[i]
                if n.start_qn <= cur_qn + 0.005 then
                    target_note = n
                    break
                end
            end
            if not target_note then
                target_note = track_notes[#track_notes]
            end
        end

    elseif direction == "above" then
        if cur_note then
            -- Find immediate higher pitch in the same chord (same onset)
            local best_higher = nil
            for _, n in ipairs(track_notes) do
                if math.abs(n.start_qn - cur_note.start_qn) < 0.01 and (n.pitch or 60) > (cur_note.pitch or 60) then
                    if best_higher == nil or (n.pitch or 60) < (best_higher.pitch or 60) then
                        best_higher = n
                    end
                end
            end
            target_note = best_higher
        end

    elseif direction == "below" then
        if cur_note then
            -- Find immediate lower pitch in the same chord (same onset)
            local best_lower = nil
            for _, n in ipairs(track_notes) do
                if math.abs(n.start_qn - cur_note.start_qn) < 0.01 and (n.pitch or 60) < (cur_note.pitch or 60) then
                    if best_lower == nil or (n.pitch or 60) > (best_lower.pitch or 60) then
                        best_lower = n
                    end
                end
            end
            target_note = best_lower
        end
    end

    if not target_note then
        if direction == "next" then
            state.status_msg = "Reached end of track notes"
        elseif direction == "prev" then
            state.status_msg = "Reached beginning of track notes"
        elseif direction == "above" then
            state.status_msg = "Highest note in chord"
        elseif direction == "below" then
            state.status_msg = "Lowest note in chord"
        end
        return
    end

    -- Apply note selection
    if not extend then
        state._nav_anchor_note = target_note
        state:clear_selection()
        state:select_note(target_note)
    else
        -- Extending selection (Alt + Shift + Arrow)
        if direction == "above" or direction == "below" then
            -- In chord: add note to multi-selection
            state:select_note(target_note)
        else
            -- On timeline: select all notes on track between anchor and target_note
            if not state._nav_anchor_note then
                state._nav_anchor_note = cur_note or target_note
            end
            local anchor = state._nav_anchor_note
            local min_range_qn = math.min(anchor.start_qn, target_note.start_qn)
            local max_range_qn = math.max(anchor.start_qn, target_note.start_qn)

            state:clear_selection()
            for _, n in ipairs(track_notes) do
                if n.start_qn >= min_range_qn - 0.005 and n.start_qn <= max_range_qn + 0.005 then
                    state:select_note(n)
                end
            end
            state.selected_note = target_note
        end
    end

    -- Auto-scrolling occurs strictly when state.auto_scroll is active
    local new_time = reaper.TimeMap2_QNToTime(0, target_note.start_qn)
    if state.auto_scroll then
        reaper.SetEditCurPos(new_time, true, false)
    else
        reaper.SetEditCurPos(new_time, false, false)
    end

    -- Synchronize with REAPER MIDI take events
    if midi_service and midi_service.sync_selection_to_reaper then
        midi_service.sync_selection_to_reaper(state, active_tracks_data)
    end

    -- Formulate clean musical status feedback
    local Constants = require("constants")
    local p_mod = (target_note.pitch or 60) % 12
    local oct = math.floor((target_note.pitch or 60) / 12) - 1
    local p_info = Constants.PITCH_MAP and Constants.PITCH_MAP[p_mod]
    local p_name = p_info and p_info.name or "Note"
    local bpi = (state.time_sig_num and state.time_sig_num > 0) and state.time_sig_num or 4.0
    local bar = math.floor((target_note.start_qn + 0.001) / bpi) + 1
    local beat = (target_note.start_qn % bpi) + 1
    if extend then
        local sel_cnt = state:count_selected_notes()
        state.status_msg = string.format("Extended selection: %d notes | Current: %s%d (Bar %d, Beat %.1f)", sel_cnt, p_name, oct, bar, beat)
    else
        state.status_msg = string.format("Selected note: %s%d | Bar %d (Beat %.1f)", p_name, oct, bar, beat)
    end
end

return SelectionService

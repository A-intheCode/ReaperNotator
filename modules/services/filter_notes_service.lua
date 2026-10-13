-- ==============================================================================
-- REAPER Native Notator - Service: FilterNotesService
-- Scans and isolates irregular (unquantized / micro-shifted) notes into a target
-- voice (default: Voice 16 / MIDI Channel 15) project-wide or in custom scope.
-- ==============================================================================

local MidiService = require("services.midi_service")

local FilterNotesService = {}

FilterNotesService.GRIDS = {
    { label = "1/1  (Whole)",   qn = 4.0 },
    { label = "1/2  (Half)",    qn = 2.0 },
    { label = "1/4  (Quarter)", qn = 1.0 },
    { label = "1/8  (Eighth)",  qn = 0.5 },
    { label = "1/16 (16th)",    qn = 0.25 },
    { label = "1/32 (32nd)",    qn = 0.125 },
    { label = "1/64 (64th)",    qn = 0.0625 },
}

--- Resolves target MIDI takes and items based on chosen scope
--- @param state table
--- @param scope string "project" | "track" | "items" | "selection"
--- @param active_tracks_data table List of active tracks in viewport
--- @return table takes_list Array of { take = MediaItem_Take*, item = MediaItem*, track = MediaTrack* }
function FilterNotesService.get_scope_targets(state, scope, active_tracks_data)
    local targets = {}
    local seen_takes = {}

    local function add_take(take, item, track)
        if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") or not reaper.TakeIsMIDI(take) then return end
        if seen_takes[take] then return end
        seen_takes[take] = true
        if not item or not reaper.ValidatePtr(item, "MediaItem*") then
            item = reaper.GetMediaItemTake_Item(take)
        end
        if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
            track = item and (reaper.GetMediaItem_Track(item) or reaper.GetMediaItemTrack(item))
        end
        table.insert(targets, { take = take, item = item, track = track })
    end

    if scope == "project" then
        -- 1. Entire project
        local trk_cnt = reaper.CountTracks(0)
        for ti = 0, trk_cnt - 1 do
            local trk = reaper.GetTrack(0, ti)
            if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                local it_cnt = reaper.CountTrackMediaItems(trk)
                for ii = 0, it_cnt - 1 do
                    local item = reaper.GetTrackMediaItem(trk, ii)
                    local take = reaper.GetActiveTake(item)
                    add_take(take, item, trk)
                end
            end
        end
    elseif scope == "track" then
        -- 2. Focused / active track
        local trk = state.focused_track
        if not trk and state.selected_notes then
            for _, sn in pairs(state.selected_notes) do
                if sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then
                    trk = sn.track
                    break
                end
            end
        end
        if not trk then trk = reaper.GetSelectedTrack(0, 0) end
        if not trk and active_tracks_data and #active_tracks_data > 0 then
            trk = active_tracks_data[1].track
        end
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            local it_cnt = reaper.CountTrackMediaItems(trk)
            for ii = 0, it_cnt - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = reaper.GetActiveTake(item)
                add_take(take, item, trk)
            end
        end
    elseif scope == "items" then
        -- 3. Selected Media Items only
        local sel_cnt = reaper.CountSelectedMediaItems(0)
        for i = 0, sel_cnt - 1 do
            local item = reaper.GetSelectedMediaItem(0, i)
            local take = reaper.GetActiveTake(item)
            add_take(take, item, nil)
        end
    elseif scope == "selection" then
        -- 4. Takes containing selected notes
        if state and state.selected_notes and next(state.selected_notes) then
            for _, sn in pairs(state.selected_notes) do
                if sn.take and reaper.ValidatePtr(sn.take, "MediaItem_Take*") then
                    add_take(sn.take, sn.item, sn.track)
                end
            end
        elseif state and state.selected_note and state.selected_note.take then
            add_take(state.selected_note.take, state.selected_note.item, state.selected_note.track)
        end
    end

    return targets
end

--- Checks whether a note start position lies on a regular metric grid within tolerance
--- @param take MediaItem_Take*
--- @param sppq number Start position in PPQ
--- @param grid_qn number Smallest allowed regular grid division in QN (e.g. 0.125 for 1/32)
--- @param tolerance_ticks number Allowed timing deviation in ticks
--- @param include_triplets boolean Whether to treat triplet divisions as regular
--- @return boolean is_regular
--- @return number diff_ticks
function FilterNotesService.is_note_regular(take, sppq, grid_qn, tolerance_ticks, include_triplets)
    grid_qn = grid_qn or 0.125
    tolerance_ticks = tolerance_ticks or 10

    local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
    local _, qn_measure_start, _ = reaper.TimeMap_QNToMeasures(0, sqn)
    local rel_qn = sqn - qn_measure_start

    -- 1. Base grid alignment (measures subdivisions starting from beat 1 of measure)
    local nearest_k = math.floor((rel_qn / grid_qn) + 0.5)
    local nearest_grid_qn = nearest_k * grid_qn
    local diff_qn = math.abs(rel_qn - nearest_grid_qn)
    local diff_ticks = diff_qn * 960.0

    -- 2. Optional Triplet check (1/4, 1/8, 1/16, 1/32 triplets)
    if include_triplets and diff_ticks > tolerance_ticks then
        local triplet_divisions = { 1.0 / 3.0, 0.5 / 3.0, 0.25 / 3.0, 0.125 / 3.0 }
        for _, trip_div in ipairs(triplet_divisions) do
            if trip_div >= (grid_qn * 0.3) then
                local tk = math.floor((rel_qn / trip_div) + 0.5)
                local dt = math.abs(rel_qn - (tk * trip_div)) * 960.0
                if dt < diff_ticks then
                    diff_ticks = dt
                end
            end
        end
    end

    local is_regular = (diff_ticks <= tolerance_ticks)
    return is_regular, diff_ticks
end

--- Non-destructive scan to find irregular notes according to user options
--- @param state table
--- @param opts table Configuration options
--- @param active_tracks_data table
--- @return table stats
function FilterNotesService.scan(state, opts, active_tracks_data)
    opts = opts or {}
    local scope = opts.scope or state.filter_irregular_scope or "project"
    local grid_qn = opts.grid_qn or state.filter_irregular_grid_qn or 0.125
    local tolerance_ticks = opts.tolerance_ticks or state.filter_irregular_tolerance_ticks or 10
    local include_triplets = (opts.include_triplets ~= nil) and opts.include_triplets or state.filter_irregular_include_triplets or false
    local target_voice = opts.target_voice or state.filter_irregular_target_voice or 16
    local target_chan = target_voice - 1

    local targets = FilterNotesService.get_scope_targets(state, scope, active_tracks_data)

    local stats = {
        total_items = #targets,
        total_notes = 0,
        irregular_count = 0,
        already_in_target_voice = 0,
        notes_by_take = {},
        irregular_notes = {},
        lookup = {}
    }

    local is_sel_scope = (scope == "selection")

    for _, tgt in ipairs(targets) do
        local take = tgt.take
        local _, notecnt = reaper.MIDI_CountEvts(take)
        stats.total_notes = stats.total_notes + notecnt

        for ni = 0, notecnt - 1 do
            local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
            if ok then
                -- In selection scope, only process selected notes
                local process_note = true
                if is_sel_scope then
                    process_note = sel
                    if not process_note and state and state.selected_notes then
                        for _, sn in pairs(state.selected_notes) do
                            if sn.take == take and (sn.idx == ni or (sn.pitch == pitch and math.abs((sn.sppq or sppq) - sppq) <= 25)) then
                                process_note = true
                                break
                            end
                        end
                    end
                end

                if process_note then
                    local is_regular, diff_ticks = FilterNotesService.is_note_regular(take, sppq, grid_qn, tolerance_ticks, include_triplets)
                    if not is_regular then
                        if chan == target_chan then
                            stats.already_in_target_voice = stats.already_in_target_voice + 1
                        else
                            stats.irregular_count = stats.irregular_count + 1
                            local note_info = {
                                idx = ni,
                                take = take,
                                track = tgt.track,
                                item = tgt.item,
                                sppq = sppq,
                                eppq = eppq,
                                chan = chan,
                                pitch = pitch,
                                vel = vel,
                                sel = sel,
                                muted = muted,
                                diff_ticks = diff_ticks
                            }
                            table.insert(stats.irregular_notes, note_info)
                            if not stats.notes_by_take[take] then
                                stats.notes_by_take[take] = { track = tgt.track, notes = {} }
                            end
                            table.insert(stats.notes_by_take[take].notes, note_info)

                            local tk_str = tostring(take)
                            stats.lookup[tk_str .. "_" .. ni] = true
                            stats.lookup[tk_str .. "_" .. ni .. "_" .. pitch] = true
                            local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                            stats.lookup[tk_str .. "_" .. pitch .. "_" .. string.format("%.2f", sqn)] = true
                            stats.lookup[tk_str .. "_" .. pitch .. "_" .. string.format("%.3f", sqn)] = true
                            stats.lookup["any_" .. pitch .. "_" .. string.format("%.2f", sqn)] = true
                            stats.lookup["any_" .. pitch .. "_" .. string.format("%.3f", sqn)] = true
                        end
                    end
                end
            end
        end
    end

    return stats
end

--- Applies voice reassignment for all detected irregular notes
--- @param state table
--- @param opts table
--- @param active_tracks_data table
--- @return number moved_count
function FilterNotesService.apply(state, opts, active_tracks_data)
    opts = opts or {}
    local stats = FilterNotesService.scan(state, opts, active_tracks_data)
    local target_voice = opts.target_voice or state.filter_irregular_target_voice or 16
    local target_chan = target_voice - 1
    local also_mute = (opts.also_mute ~= nil) and opts.also_mute or state.filter_irregular_also_mute or false
    local also_select = (opts.also_select ~= nil) and opts.also_select or state.filter_irregular_also_select or false

    if stats.irregular_count == 0 then
        state.status_msg = "Filter irregular Notes: No irregular notes found to reassign."
        return 0
    end

    local undo_title = string.format("Notator: Filter Irregular Notes to Voice %d", target_voice)
    reaper.Undo_BeginBlock2(0)

    local moved_count = 0
    local modified_tracks = {}

    for take, take_data in pairs(stats.notes_by_take) do
        if reaper.ValidatePtr(take, "MediaItem_Take*") then
            reaper.MIDI_DisableSort(take)

            for _, n in ipairs(take_data.notes) do
                local new_muted = also_mute and true or n.muted
                local new_sel = also_select and true or n.sel
                reaper.MIDI_SetNote(take, n.idx, new_sel, new_muted, n.sppq, n.eppq, target_chan, n.pitch, n.vel, true)
                moved_count = moved_count + 1

                -- Synchronize in-memory selected notes if present in state
                if state and state.selected_notes then
                    for _, sn in pairs(state.selected_notes) do
                        local same_take = (sn.take == take) or (tostring(sn.take) == tostring(take))
                        if same_take and (sn.idx == n.idx or (sn.pitch == n.pitch and math.abs((sn.sppq or n.sppq) - n.sppq) <= 25)) then
                            sn.chan = target_chan
                            if also_mute then sn.muted = true end
                            if also_select then sn.selected = true end
                        end
                    end
                end
            end

            reaper.MIDI_Sort(take)

            if take_data.track and reaper.ValidatePtr(take_data.track, "MediaTrack*") then
                modified_tracks[reaper.GetTrackGUID(take_data.track)] = take_data.track
            end
        end
    end

    -- Invalidate caches for all affected tracks
    for _, trk in pairs(modified_tracks) do
        MidiService.invalidate_cache(trk)
    end
    if not next(modified_tracks) then
        MidiService.invalidate_cache()
    end

    reaper.Undo_EndBlock2(0, undo_title, -1)

    state.status_msg = string.format("✓ Reassigned %d irregular notes to Voice %d", moved_count, target_voice)
    return moved_count
end

return FilterNotesService


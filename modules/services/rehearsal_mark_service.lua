-- ==============================================================================
-- REAPER Native Notator - Service: RehearsalMarkService
-- Manages auto-sequencing rehearsal marks (A, B, C...) and navigation marks
-- (D.C., D.S., Segno, Coda, Fine) positioned between Chord Track and Bar Numbers
-- ==============================================================================

local RehearsalMark = require("classes.rehearsal_mark")

local RehearsalMarkService = {}

local function index_to_letter(idx)
    idx = math.max(1, math.floor(idx))
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if idx <= 26 then
        return alphabet:sub(idx, idx)
    else
        local first = math.floor((idx - 1) / 26)
        local rem = ((idx - 1) % 26) + 1
        return alphabet:sub(first, first) .. alphabet:sub(rem, rem)
    end
end

function RehearsalMarkService.measure_from_qn(qn)
    local tpos = reaper.TimeMap2_QNToTime(0, math.max(0.0, tonumber(qn) or 0.0))
    local _, m = reaper.TimeMap2_timeToBeats(0, tpos)
    return math.max(0, math.floor((m or 0) + 0.0001))
end

function RehearsalMarkService.snap_qn_to_grid(state, raw_qn)
    raw_qn = math.max(0.0, tonumber(raw_qn) or 0.0)
    local grid = (state and state.grid_qn) or 1.0
    if grid <= 0.001 then
        return raw_qn
    end
    local _, qn_measure_start = reaper.TimeMap_QNToMeasures(0, raw_qn)
    qn_measure_start = qn_measure_start or 0.0
    local rel_qn = raw_qn - qn_measure_start
    local snapped_rel = math.floor((rel_qn / grid) + 0.5) * grid
    return math.max(0.0, qn_measure_start + snapped_rel)
end

function RehearsalMarkService.get_next_default_custom_name(state)
    local max_idx = 0
    for _, rm in ipairs((state and state.rehearsal_marks) or {}) do
        local txt = (rm.custom_text and rm.custom_text ~= "") and rm.custom_text or (rm.label or "")
        local num_str = txt:match("^[Mm]arker%s+(%d+)$")
        if num_str then
            local n = tonumber(num_str)
            if n and n > max_idx then
                max_idx = n
            end
        end
    end
    return string.format("Marker %d", max_idx + 1)
end

function RehearsalMarkService.recompute_labels(state)
    if not state.rehearsal_marks then state.rehearsal_marks = {} end

    -- Sort strictly by QN, then measure
    table.sort(state.rehearsal_marks, function(a, b)
        local a_qn = tonumber(a.qn) or 0.0
        local b_qn = tonumber(b.qn) or 0.0
        if math.abs(a_qn - b_qn) > 0.001 then
            return a_qn < b_qn
        end
        if (a.measure or 0) ~= (b.measure or 0) then
            return (a.measure or 0) < (b.measure or 0)
        end
        return tostring(a.id or "") < tostring(b.id or "")
    end)

    local letter_idx = 1
    local number_idx = 1

    for _, rm in ipairs(state.rehearsal_marks) do
        local m_type = rm.type or "letter"
        -- If a mark has an explicit custom_text set, ensure it stays locked as 'custom' and is never auto-counted
        if (m_type == "letter" or m_type == "number") and rm.custom_text and rm.custom_text ~= "" then
            m_type = "custom"
            rm.type = "custom"
        end

        if m_type == "letter" then
            rm.label = index_to_letter(letter_idx)
            letter_idx = letter_idx + 1
        elseif m_type == "number" then
            rm.label = tostring(number_idx)
            number_idx = number_idx + 1
        elseif m_type == "dc" then
            rm.label = "D.C."
        elseif m_type == "dc_al_fine" then
            rm.label = "D.C. al Fine"
        elseif m_type == "ds" then
            rm.label = "D.S."
        elseif m_type == "ds_al_coda" then
            rm.label = "D.S. al Coda"
        elseif m_type == "segno" then
            rm.label = utf8.char(0xE047) -- SMuFL segno 𝄋
        elseif m_type == "coda" then
            rm.label = utf8.char(0xE048) -- SMuFL coda 𝄌
        elseif m_type == "fine" then
            rm.label = "Fine"
        elseif m_type == "custom" then
            if rm.custom_text and rm.custom_text ~= "" then
                rm.label = rm.custom_text
            elseif rm.label and rm.label ~= "" then
                rm.custom_text = rm.label
            else
                rm.custom_text = "Marker 1"
                rm.label = "Marker 1"
            end
        end
    end
end

function RehearsalMarkService.load_marks(state, read_only)
    state.rehearsal_marks = {}
    local known_qn = {}

    -- 1. Load from Project Ext State
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "rehearsal_marks")
    local has_proj_ext = (raw and raw ~= "")
    if has_proj_ext then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id = parts[1]
            local measure = tonumber(parts[2])
            local qn = tonumber(parts[3])
            local m_type = parts[4] or "letter"
            local custom_text = parts[5] or ""
            local label = parts[6] or ""

            if id and id ~= "" and measure ~= nil then
                local resolved_qn = qn or (measure * 4.0)
                if m_type == "custom" and custom_text == "" and label ~= "" then
                    custom_text = label
                end
                local rm = RehearsalMark.new({
                    id          = id,
                    measure     = measure,
                    qn          = resolved_qn,
                    type        = m_type,
                    custom_text = custom_text,
                    label       = label
                })
                table.insert(state.rehearsal_marks, rm)
                known_qn[math.floor(resolved_qn * 100 + 0.5)] = true
            end
        end
    end

    -- 2. DUAL PERSISTENCE: Fallback scan of active MIDI takes for Type-15 Notation Events only on initial load when ProjExtState had no marks
    if not read_only and not has_proj_ext and #state.rehearsal_marks == 0 then
        local trk_count = reaper.CountTracks(0)
        for ti = 0, trk_count - 1 do
            local trk = reaper.GetTrack(0, ti)
            if trk then
                local item_count = reaper.CountTrackMediaItems(trk)
                for ii = 0, item_count - 1 do
                    local item = reaper.GetTrackMediaItem(trk, ii)
                    local take = item and reaper.GetActiveTake(item)
                    if take and reaper.TakeIsMIDI(take) then
                        local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                        for text_i = 0, text_cnt - 1 do
                            local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
                            if ok and ev_type == 15 and msg:match("^NOTATOR_REHEARSAL") then
                                local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                                local qn_key = math.floor(qn * 100 + 0.5)
                                if not known_qn[qn_key] then
                                    known_qn[qn_key] = true
                                    local m = RehearsalMarkService.measure_from_qn(qn)
                                    local m_type, custom_str = msg:match("^NOTATOR_REHEARSAL%s+([%w_]+)%s*(.*)")
                                    m_type = m_type or "letter"
                                    local rm = RehearsalMark.new({
                                        id          = string.format("rm_q%d", qn_key),
                                        measure     = m,
                                        qn          = qn,
                                        type        = m_type,
                                        custom_text = (m_type == "custom") and (custom_str or "") or "",
                                        label       = custom_str or ""
                                    })
                                    table.insert(state.rehearsal_marks, rm)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Re-compute automatic sequence (A -> B -> C...) while preserving custom & navigation marks
    RehearsalMarkService.recompute_labels(state)
    state._rehearsal_marks_loaded = true
    if state.selected_rehearsal_mark then
        local found = nil
        for _, rm in ipairs(state.rehearsal_marks) do
            if rm.id == state.selected_rehearsal_mark.id then found = rm; break end
        end
        state.selected_rehearsal_mark = found
    end
end

function RehearsalMarkService.save_marks(state)
    if not state.rehearsal_marks then return end
    local entries = {}
    for _, rm in ipairs(state.rehearsal_marks) do
        local safe_custom = tostring(rm.custom_text or ""):gsub("[|;]", " ")
        local safe_label  = tostring(rm.label or ""):gsub("[|;]", " ")
        table.insert(entries, string.format("%s|%d|%.3f|%s|%s|%s",
            rm.id or "",
            rm.measure or 0,
            rm.qn or 0.0,
            rm.type or "letter",
            safe_custom,
            safe_label
        ))
    end
    reaper.SetProjExtState(0, "REAPER_Notator", "rehearsal_marks", table.concat(entries, ";"))
end

function RehearsalMarkService.add_mark(state, measure, mark_type, custom_text, exact_qn)
    if not state.rehearsal_marks then state.rehearsal_marks = {} end
    mark_type = mark_type or "letter"

    if mark_type == "custom" and (not custom_text or custom_text == "") then
        custom_text = RehearsalMarkService.get_next_default_custom_name(state)
    end

    local qn
    if exact_qn ~= nil then
        qn = math.max(0.0, tonumber(exact_qn) or 0.0)
        measure = RehearsalMarkService.measure_from_qn(qn)
    else
        measure = math.max(0, math.floor(measure or 0))
        local tpos = reaper.TimeMap2_beatsToTime(0, 0, measure)
        qn = reaper.TimeMap2_timeToQN(0, tpos)
    end

    -- Check if a mark at this exact QN position already exists
    local existing = nil
    for _, rm in ipairs(state.rehearsal_marks) do
        if math.abs((rm.qn or 0) - qn) < 0.02 then
            existing = rm
            break
        end
    end

    local target_rm
    if existing then
        existing.measure = measure
        existing.qn = qn
        existing.type = mark_type
        existing.custom_text = (mark_type == "custom") and (custom_text or "") or ""
        if mark_type == "custom" then
            existing.label = existing.custom_text
        end
        target_rm = existing
    else
        local rm = RehearsalMark.new({
            id          = string.format("rm_%d_%d", math.floor(qn * 100), math.random(1000, 9999)),
            measure     = measure,
            qn          = qn,
            type        = mark_type,
            custom_text = (mark_type == "custom") and (custom_text or "") or "",
            label       = (mark_type == "custom") and (custom_text or "") or ""
        })
        table.insert(state.rehearsal_marks, rm)
        target_rm = rm
    end

    reaper.Undo_BeginBlock2(0)
    -- Automatically re-sequence letters & numbers
    RehearsalMarkService.recompute_labels(state)
    RehearsalMarkService.sync_takes(state)
    RehearsalMarkService.save_marks(state)
    reaper.Undo_EndBlock2(0, "Notator: Add Rehearsal Mark", -1)

    local tpos = reaper.TimeMap2_QNToTime(0, qn)
    local beats_in_m, m_idx = reaper.TimeMap2_timeToBeats(0, tpos)
    local beat_num = (beats_in_m or 0) + 1.0
    state.status_msg = string.format("Added Mark [%s] at Bar %d (Beat %.1f)", target_rm.label or "", (m_idx or measure) + 1, beat_num)
    return target_rm
end

function RehearsalMarkService.add_custom_marker_at_current_pos(state, custom_text)
    local play_state = reaper.GetPlayState()
    local is_playing = (play_state & 1) == 1 or (play_state & 4) == 4
    local pos_time = is_playing and reaper.GetPlayPosition() or reaper.GetCursorPosition()
    local raw_qn = reaper.TimeMap2_timeToQN(0, pos_time)
    local snapped_qn = RehearsalMarkService.snap_qn_to_grid(state, raw_qn)
    local m_idx = RehearsalMarkService.measure_from_qn(snapped_qn)

    if not custom_text or custom_text == "" then
        custom_text = RehearsalMarkService.get_next_default_custom_name(state)
    end

    -- If a mark already exists at the exact same snapped_qn, still create a new custom name or update it cleanly
    local rm = RehearsalMarkService.add_mark(state, m_idx, "custom", custom_text, snapped_qn)
    if state then
        state.selected_rehearsal_mark = rm
    end
    return rm
end

function RehearsalMarkService.rename_mark(state, mark_id, new_text)
    if not state or not state.rehearsal_marks or not mark_id then return false end
    new_text = tostring(new_text or ""):match("^%s*(.-)%s*$")
    if new_text == "" then return false end

    local found = nil
    for _, rm in ipairs(state.rehearsal_marks) do
        if rm.id == mark_id then
            rm.type = "custom"
            rm.custom_text = new_text
            rm.label = new_text
            found = rm
            break
        end
    end

    if not found then return false end

    -- Re-sequence remaining auto marks so the renamed mark is excluded from A, B, C... / 1, 2, 3... counting
    RehearsalMarkService.recompute_labels(state)
    RehearsalMarkService.sync_takes(state)
    RehearsalMarkService.save_marks(state)
    reaper.Undo_OnStateChange2(0, "Notator: Rename Rehearsal Mark to " .. new_text)
    state.status_msg = string.format("Renamed Rehearsal Mark to '%s' (locked as Custom)", new_text)
    return true
end

function RehearsalMarkService.remove_mark(state, mark_id)
    if not state.rehearsal_marks then return end
    reaper.Undo_BeginBlock2(0)
    for idx, rm in ipairs(state.rehearsal_marks) do
        if rm.id == mark_id then
            table.remove(state.rehearsal_marks, idx)
            break
        end
    end

    -- Automatically re-sequence letters & numbers after deletion
    RehearsalMarkService.recompute_labels(state)
    RehearsalMarkService.sync_takes(state)
    RehearsalMarkService.save_marks(state)
    reaper.Undo_EndBlock2(0, "Notator: Remove Rehearsal Mark", -1)

    state.status_msg = "Removed Rehearsal Mark"
end

function RehearsalMarkService.move_mark(state, mark_id, target_measure, target_qn)
    if not state.rehearsal_marks then return end

    if target_qn ~= nil then
        target_qn = math.max(0.0, tonumber(target_qn) or 0.0)
        target_measure = RehearsalMarkService.measure_from_qn(target_qn)
    else
        target_measure = math.max(0, math.floor(target_measure or 0))
        local tpos = reaper.TimeMap2_beatsToTime(0, 0, target_measure)
        target_qn = reaper.TimeMap2_timeToQN(0, tpos)
    end

    -- Remove any other mark that already occupied the exact same destination QN
    for idx = #state.rehearsal_marks, 1, -1 do
        local other = state.rehearsal_marks[idx]
        if other.id ~= mark_id and math.abs((other.qn or 0) - target_qn) < 0.02 then
            table.remove(state.rehearsal_marks, idx)
        end
    end

    for _, rm in ipairs(state.rehearsal_marks) do
        if rm.id == mark_id then
            rm.measure = target_measure
            rm.qn = target_qn
            -- Strictly preserve rm.type, rm.custom_text, and rm.label for custom & navigation marks!
            if rm.type == "custom" and (not rm.custom_text or rm.custom_text == "") and rm.label and rm.label ~= "" then
                rm.custom_text = rm.label
            end
            break
        end
    end

    reaper.Undo_BeginBlock2(0)
    -- Re-order and recompute auto-sequenced labels (while keeping custom & navigation marks untouched)
    RehearsalMarkService.recompute_labels(state)
    RehearsalMarkService.sync_takes(state)
    RehearsalMarkService.save_marks(state)
    reaper.Undo_EndBlock2(0, "Notator: Move Rehearsal Mark", -1)
end

function RehearsalMarkService.sync_takes(state)
    -- Write clean Type-15 events to active takes on all tracks
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    -- Remove previous NOTATOR_REHEARSAL events
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                    for text_i = text_cnt - 1, 0, -1 do
                        local ok, _, _, _, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
                        if ok and ev_type == 15 and msg:match("^NOTATOR_REHEARSAL") then
                            reaper.MIDI_DeleteTextSysexEvt(take, text_i)
                        end
                    end

                    -- Insert current marks falling within this take
                    local ipos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local ilen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local item_sqn = reaper.TimeMap2_timeToQN(0, ipos)
                    local item_eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)

                    for _, rm in ipairs(state.rehearsal_marks or {}) do
                        if rm.qn >= item_sqn - 0.05 and rm.qn <= item_eqn + 0.05 then
                            local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, rm.qn) + 0.5)
                            local payload = (rm.type == "custom" and rm.custom_text and rm.custom_text ~= "") and rm.custom_text or (rm.label or "")
                            local tag_msg = string.format("NOTATOR_REHEARSAL %s %s", rm.type or "letter", payload)
                            reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, tag_msg)
                        end
                    end
                    reaper.MIDI_Sort(take)
                end
            end
        end
    end
end

function RehearsalMarkService.get_mark_at_measure(state, measure)
    if not state.rehearsal_marks then return nil end
    for _, rm in ipairs(state.rehearsal_marks) do
        if rm.measure == measure then
            return rm
        end
    end
    return nil
end

return RehearsalMarkService

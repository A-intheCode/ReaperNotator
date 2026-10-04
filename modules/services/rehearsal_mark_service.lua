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

function RehearsalMarkService.recompute_labels(state)
    if not state.rehearsal_marks then state.rehearsal_marks = {} end

    -- Sort strictly by measure then QN
    table.sort(state.rehearsal_marks, function(a, b)
        if a.measure ~= b.measure then
            return a.measure < b.measure
        end
        return a.qn < b.qn
    end)

    local letter_idx = 1
    local number_idx = 1

    for _, rm in ipairs(state.rehearsal_marks) do
        local m_type = rm.type or "letter"
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
            rm.label = (rm.custom_text and rm.custom_text ~= "") and rm.custom_text or "Sec"
        end
    end
end

function RehearsalMarkService.load_marks(state)
    state.rehearsal_marks = {}
    local known = {}

    -- 1. Load from Project Ext State
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "rehearsal_marks")
    if raw and raw ~= "" then
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
                local rm = RehearsalMark.new({
                    id          = id,
                    measure     = measure,
                    qn          = qn or (measure * 4.0),
                    type        = m_type,
                    custom_text = custom_text,
                    label       = label
                })
                table.insert(state.rehearsal_marks, rm)
                known[measure] = true
            end
        end
    end

    -- 2. DUAL PERSISTENCE: Scan active MIDI takes for Type-15 Notation Events
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
                            local bpi = 4.0
                            local ts_num, ts_den = reaper.TimeMap_GetTimeSigAtTime(0, reaper.TimeMap2_QNToTime(0, qn))
                            if ts_num and ts_den and ts_den > 0 then bpi = ts_num * (4.0 / ts_den) end
                            local m = math.floor((qn + 0.01) / bpi)
                            if not known[m] then
                                known[m] = true
                                local m_type, custom_str = msg:match("^NOTATOR_REHEARSAL%s+([%w_]+)%s*(.*)")
                                local rm = RehearsalMark.new({
                                    id          = string.format("rm_m%d", m),
                                    measure     = m,
                                    qn          = qn,
                                    type        = m_type or "letter",
                                    custom_text = custom_str or "",
                                    label       = ""
                                })
                                table.insert(state.rehearsal_marks, rm)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Re-compute automatic sequence (A -> B -> C...)
    RehearsalMarkService.recompute_labels(state)
end

function RehearsalMarkService.save_marks(state)
    if not state.rehearsal_marks then return end
    local entries = {}
    for _, rm in ipairs(state.rehearsal_marks) do
        table.insert(entries, string.format("%s|%d|%.3f|%s|%s|%s",
            rm.id or "",
            rm.measure or 0,
            rm.qn or 0.0,
            rm.type or "letter",
            rm.custom_text or "",
            rm.label or ""
        ))
    end
    reaper.SetProjExtState(0, "REAPER_Notator", "rehearsal_marks", table.concat(entries, ";"))
end

function RehearsalMarkService.add_mark(state, measure, mark_type, custom_text)
    if not state.rehearsal_marks then state.rehearsal_marks = {} end
    measure = math.max(0, math.floor(measure or 0))
    mark_type = mark_type or "letter"

    -- Calculate measure start QN
    local bpi = 4.0
    local tpos = reaper.TimeMap2_beatsToTime(0, 0, measure)
    local qn = reaper.TimeMap2_timeToQN(0, tpos)

    -- Check if a mark at this measure already exists
    local existing = nil
    for _, rm in ipairs(state.rehearsal_marks) do
        if rm.measure == measure then
            existing = rm
            break
        end
    end

    if existing then
        existing.type = mark_type
        existing.custom_text = custom_text or ""
    else
        local rm = RehearsalMark.new({
            id          = string.format("rm_%d_%d", measure, math.random(1000, 9999)),
            measure     = measure,
            qn          = qn,
            type        = mark_type,
            custom_text = custom_text or ""
        })
        table.insert(state.rehearsal_marks, rm)
    end

    -- Automatically re-sequence letters & numbers
    RehearsalMarkService.recompute_labels(state)
    RehearsalMarkService.sync_takes(state)
    RehearsalMarkService.save_marks(state)

    state.status_msg = string.format("Added Rehearsal Mark at Bar %d", measure + 1)
end

function RehearsalMarkService.remove_mark(state, mark_id)
    if not state.rehearsal_marks then return end
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

    state.status_msg = "Removed Rehearsal Mark"
end

function RehearsalMarkService.move_mark(state, mark_id, target_measure)
    if not state.rehearsal_marks then return end
    target_measure = math.max(0, math.floor(target_measure or 0))

    -- Remove any other mark that already occupied the destination bar
    for idx = #state.rehearsal_marks, 1, -1 do
        local other = state.rehearsal_marks[idx]
        if other.id ~= mark_id and other.measure == target_measure then
            table.remove(state.rehearsal_marks, idx)
        end
    end

    for _, rm in ipairs(state.rehearsal_marks) do
        if rm.id == mark_id then
            rm.measure = target_measure
            local tpos = reaper.TimeMap2_beatsToTime(0, 0, target_measure)
            rm.qn = reaper.TimeMap2_timeToQN(0, tpos)
            break
        end
    end

    -- Re-order and recompute labels
    RehearsalMarkService.recompute_labels(state)
    RehearsalMarkService.sync_takes(state)
    RehearsalMarkService.save_marks(state)
end

function RehearsalMarkService.sync_takes(state)
    -- Write clean Type-15 events to active takes on track 0 (or all tracks)
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
                            local tag_msg = string.format("NOTATOR_REHEARSAL %s %s", rm.type or "letter", rm.label or "")
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

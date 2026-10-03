-- ==============================================================================
-- REAPER Native Notator - Service: DynamicTextService
-- Manages textual Crescendo and Diminuendo dynamics (cresc., dim. etc.)
-- with length scalability, text patterns, line patterns and CC curve patterns
-- ==============================================================================

local DynamicText = require("classes.dynamic_text")
local DynamicsEngine = require("services.dynamics_engine")
local Constants = require("constants")

local DynamicTextService = {}

local DYN_LOOKUP = {
    pppp = {c1 = 8,   c2 = 12},
    ppp  = {c1 = 20,  c2 = 25},
    pp   = {c1 = 35,  c2 = 40},
    p    = {c1 = 50,  c2 = 55},
    mp   = {c1 = 65,  c2 = 70},
    mf   = {c1 = 80,  c2 = 85},
    f    = {c1 = 95,  c2 = 100},
    ff   = {c1 = 110, c2 = 115},
    fff  = {c1 = 120, c2 = 120},
    ffff = {c1 = 127, c2 = 127},
    sfz  = {c1 = 115, c2 = 115},
    sfp  = {c1 = 110, c2 = 55},
    fp   = {c1 = 95,  c2 = 55},
}

local function sync_dynamic_texts_to_takes(state)
    local by_guid = {}
    for _, dt in ipairs(state.dynamic_texts or {}) do
        if dt.track_guid then
            by_guid[dt.track_guid] = by_guid[dt.track_guid] or {}
            table.insert(by_guid[dt.track_guid], dt)
        end
    end
    
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            local track_dt_list = by_guid[trk_guid] or {}
            
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local item_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local i_start_qn = reaper.TimeMap2_timeToQN(0, item_pos)
                    local i_end_qn = reaper.TimeMap2_timeToQN(0, item_pos + item_len)
                    
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                    local to_del = {}
                    for t_idx = text_cnt - 1, 0, -1 do
                        local ok, _, _, _, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, t_idx)
                        if ok and ev_type == 15 and msg:match("^NOTATOR_DYN_TEXT") then
                            table.insert(to_del, t_idx)
                        end
                    end
                    for _, d_idx in ipairs(to_del) do
                        reaper.MIDI_DeleteTextSysexEvt(take, d_idx)
                    end
                    
                    local inserted = false
                    for _, dt in ipairs(track_dt_list) do
                        if dt.start_qn >= (i_start_qn - 0.05) and dt.start_qn < (i_end_qn + 0.05) then
                            local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, dt.start_qn) + 0.5)
                            local msg = string.format("NOTATOR_DYN_TEXT|%s|%s|%s|%.4f|%.4f|%s|%s|%s|%s|%s",
                                dt.id, dt.type or "crescendo", dt.text or "", dt.start_qn, dt.end_qn,
                                dt.line_pattern or "none", dt.curve_pattern or "linear",
                                dt.start_dyn or "", dt.end_dyn or "", dt.staff or "")
                            reaper.MIDI_InsertTextSysexEvt(take, false, false, ppq, 15, msg)
                            inserted = true
                        end
                    end
                    if inserted or #to_del > 0 then
                        reaper.MIDI_Sort(take)
                    end
                end
            end
        end
    end
end

function DynamicTextService.load_dynamic_texts(state)
    state.dynamic_texts = {}
    local known = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "dynamic_texts")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id            = parts[1]
            local track_guid    = parts[2]
            local dtype         = parts[3]
            local text          = parts[4]
            local start_qn      = tonumber(parts[5]) or 0.0
            local end_qn        = tonumber(parts[6]) or (start_qn + 4.0)
            local line_pattern  = (parts[7] and parts[7] ~= "") and parts[7] or "none"
            local curve_pattern = (parts[8] and parts[8] ~= "") and parts[8] or "linear"
            local start_dyn     = (parts[9] and parts[9] ~= "") and parts[9] or nil
            local end_dyn       = (parts[10] and parts[10] ~= "") and parts[10] or nil
            local staff         = (parts[11] and parts[11] ~= "") and parts[11] or nil
            
            if id and id ~= "" and track_guid and dtype then
                known[id] = true
                local dt = DynamicText.new({
                    id            = id,
                    track_guid    = track_guid,
                    type          = dtype,
                    text          = text,
                    start_qn      = start_qn,
                    end_qn        = end_qn,
                    line_pattern  = line_pattern,
                    curve_pattern = curve_pattern,
                    start_dyn     = start_dyn,
                    end_dyn       = end_dyn,
                    staff         = staff
                })
                table.insert(state.dynamic_texts, dt)
            end
        end
    end

    -- DUAL PERSISTENCE: Read from MIDI takes (Type 15 notation events in .RPP)
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_count - 1 do
                local item = reaper.GetTrackMediaItem(trk, ii)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                    for text_i = 0, text_cnt - 1 do
                        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
                        if ok and ev_type == 15 and msg:match("^NOTATOR_DYN_TEXT") then
                            local parts = {}
                            for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
                            local id            = parts[2]
                            local dtype         = parts[3]
                            local text          = parts[4]
                            local start_qn      = tonumber(parts[5]) or reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                            local end_qn        = tonumber(parts[6]) or (start_qn + 4.0)
                            local line_pattern  = (parts[7] and parts[7] ~= "") and parts[7] or "none"
                            local curve_pattern = (parts[8] and parts[8] ~= "") and parts[8] or "linear"
                            local start_dyn     = (parts[9] and parts[9] ~= "") and parts[9] or nil
                            local end_dyn       = (parts[10] and parts[10] ~= "") and parts[10] or nil
                            local staff         = (parts[11] and parts[11] ~= "") and parts[11] or nil
                            if id and id ~= "" and not known[id] then
                                known[id] = true
                                table.insert(state.dynamic_texts, DynamicText.new({
                                    id            = id,
                                    track_guid    = trk_guid,
                                    type          = dtype,
                                    text          = text,
                                    start_qn      = start_qn,
                                    end_qn        = end_qn,
                                    line_pattern  = line_pattern,
                                    curve_pattern = curve_pattern,
                                    start_dyn     = start_dyn,
                                    end_dyn       = end_dyn,
                                    staff         = staff
                                }))
                            end
                        end
                    end
                end
            end
        end
    end
end

function DynamicTextService.parse_notation_event(state, track, take, ppq, msg)
    if not state or not msg then return end
    if not state.dynamic_texts then state.dynamic_texts = {} end
    local trk_guid = track and reaper.ValidatePtr(track, "MediaTrack*") and reaper.GetTrackGUID(track)
    if not trk_guid then return end
    
    local parts = {}
    for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
    local id = parts[2]
    if not id or id == "" then return end
    
    for _, dt in ipairs(state.dynamic_texts) do
        if dt.id == id then return end
    end
    
    local dtype = parts[3] or "crescendo"
    local text = parts[4] or ""
    local start_qn = tonumber(parts[5]) or (take and reaper.MIDI_GetProjQNFromPPQPos(take, ppq)) or 0.0
    local end_qn = tonumber(parts[6]) or (start_qn + 4.0)
    local line_pattern = parts[7] or "none"
    local curve_pattern = parts[8] or "linear"
    local start_dyn = (parts[9] and parts[9] ~= "") and parts[9] or nil
    local end_dyn = (parts[10] and parts[10] ~= "") and parts[10] or nil
    local staff = (parts[11] and parts[11] ~= "") and parts[11] or nil
    
    local DynamicText = package.loaded["classes.dynamic_text"] or require("classes.dynamic_text")
    table.insert(state.dynamic_texts, DynamicText.new({
        id            = id,
        track_guid    = trk_guid,
        type          = dtype,
        text          = text,
        start_qn      = start_qn,
        end_qn        = end_qn,
        line_pattern  = line_pattern,
        curve_pattern = curve_pattern,
        start_dyn     = start_dyn,
        end_dyn       = end_dyn,
        staff         = staff
    }))
end

function DynamicTextService.save_dynamic_texts(state)
    local parts = {}
    for _, dt in ipairs(state.dynamic_texts or {}) do
        local entry = string.format("%s|%s|%s|%s|%.4f|%.4f|%s|%s|%s|%s|%s",
            dt.id, dt.track_guid, dt.type, dt.text or "", dt.start_qn, dt.end_qn,
            dt.line_pattern or "none", dt.curve_pattern or "linear",
            dt.start_dyn or "", dt.end_dyn or "", dt.staff or "")
        table.insert(parts, entry)
    end
    local raw = table.concat(parts, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "dynamic_texts", raw)
    sync_dynamic_texts_to_takes(state)
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    if reaper.Main_UpdateLoopInfo then reaper.Main_UpdateLoopInfo(0) end
end

function DynamicTextService.get_dynamic_texts_for_track(state, track_guid)
    local res = {}
    for _, dt in ipairs(state.dynamic_texts or {}) do
        if dt.track_guid == track_guid then
            table.insert(res, dt)
        end
    end
    table.sort(res, function(a, b) return a.start_qn < b.start_qn end)
    return res
end

function DynamicTextService.find_take_for_track(track_guid, active_tracks_data, opt_qn)
    local fallback_tk, fallback_it = nil, nil
    if active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.guid == track_guid then
                if tdata.items and #tdata.items > 0 then
                    for _, it in ipairs(tdata.items) do
                        if it.take and reaper.ValidatePtr(it.take, "MediaItem_Take*") and reaper.TakeIsMIDI(it.take) then
                            if opt_qn and it.item and reaper.ValidatePtr(it.item, "MediaItem*") then
                                local ipos = reaper.GetMediaItemInfo_Value(it.item, "D_POSITION")
                                local ilen = reaper.GetMediaItemInfo_Value(it.item, "D_LENGTH")
                                local sqn = reaper.TimeMap2_timeToQN(0, ipos)
                                local eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                                if opt_qn >= (sqn - 0.1) and opt_qn <= (eqn + 0.1) then
                                    return it.take, it.item
                                end
                            end
                            if not fallback_tk then fallback_tk, fallback_it = it.take, it.item end
                        end
                    end
                end
                if tdata.track and reaper.ValidatePtr(tdata.track, "MediaTrack*") then
                    local item_cnt = reaper.CountTrackMediaItems(tdata.track)
                    for i = 0, item_cnt - 1 do
                        local it = reaper.GetTrackMediaItem(tdata.track, i)
                        local tk = it and reaper.GetActiveTake(it)
                        if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") and reaper.TakeIsMIDI(tk) then
                            if opt_qn then
                                local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                                local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                                local sqn = reaper.TimeMap2_timeToQN(0, ipos)
                                local eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                                if opt_qn >= (sqn - 0.1) and opt_qn <= (eqn + 0.1) then
                                    return tk, it
                                end
                            end
                            if not fallback_tk then fallback_tk, fallback_it = tk, it end
                        end
                    end
                end
            end
        end
    end
    -- Fallback via Project Track List
    local trk_cnt = reaper.CountTracks(0)
    for i = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, i)
        if trk and reaper.GetTrackGUID(trk) == track_guid then
            local item_cnt = reaper.CountTrackMediaItems(trk)
            for j = 0, item_cnt - 1 do
                local it = reaper.GetTrackMediaItem(trk, j)
                local tk = it and reaper.GetActiveTake(it)
                if tk and reaper.TakeIsMIDI(tk) then
                    if opt_qn then
                        local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                        local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                        local sqn = reaper.TimeMap2_timeToQN(0, ipos)
                        local eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                        if opt_qn >= (sqn - 0.1) and opt_qn <= (eqn + 0.1) then
                            return tk, it
                        end
                    end
                    if not fallback_tk then fallback_tk, fallback_it = tk, it end
                end
            end
        end
    end
    return fallback_tk, fallback_it
end

function DynamicTextService.get_bounds(state, dt, active_tracks_data)
    if not dt or not dt.track_guid then return 0.0, 999999.0 end
    local s_qn = dt.start_qn or 0.0
    local e_qn = dt.end_qn or (s_qn + 4.0)

    -- 1. Other dynamic texts on the same track
    local prev_dt, next_dt = nil, nil
    local max_prev_start = -1
    local min_next_start = 99999999
    if state.dynamic_texts then
        for _, other in ipairs(state.dynamic_texts) do
            if other.id ~= dt.id and other.track_guid == dt.track_guid then
                local os = other.start_qn or 0.0
                if os < s_qn then
                    if os > max_prev_start then
                        max_prev_start = os
                        prev_dt = other
                    end
                elseif os > s_qn then
                    if os < min_next_start then
                        min_next_start = os
                        next_dt = other
                    end
                end
            end
        end
    end

    -- 2. Hairpins on the same track
    local prev_hp, next_hp = nil, nil
    local max_prev_hp_start = -1
    local min_next_hp_start = 99999999
    if state.hairpins then
        for _, hp in ipairs(state.hairpins) do
            if hp.track_guid == dt.track_guid then
                local hs = hp.start_qn or 0.0
                if hs < s_qn then
                    if hs > max_prev_hp_start then
                        max_prev_hp_start = hs
                        prev_hp = hp
                    end
                elseif hs > s_qn then
                    if hs < min_next_hp_start then
                        min_next_hp_start = hs
                        next_hp = hp
                    end
                end
            end
        end
    end

    -- 3. Dynamic markers on the same track
    local prev_dyn, next_dyn = nil, nil
    local min_prev_dist, min_next_dist = 100000, 100000
    local track_dyns = {}
    if active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.guid == dt.track_guid and tdata.dynamics then
                for _, d in ipairs(tdata.dynamics) do
                    table.insert(track_dyns, d)
                end
                break
            end
        end
    end
    if #track_dyns == 0 then
        local take, _ = DynamicTextService.find_take_for_track(dt.track_guid, active_tracks_data)
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            local _, _, _, textcnt = reaper.MIDI_CountEvts(take)
            for ti = 0, textcnt - 1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 and msg:match("^dynamic%s+([%a%d]+)%s*:(%d+):(%d+)") then
                    local lbl, c1, c2 = msg:match("^dynamic%s+([%a%d]+)%s*:(%d+):(%d+)")
                    local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                    table.insert(track_dyns, { qn = qn, label = lbl, c1 = tonumber(c1), c2 = tonumber(c2) })
                end
            end
        end
    end
    table.sort(track_dyns, function(a, b) return (a.qn or 0) < (b.qn or 0) end)

    for _, d in ipairs(track_dyns) do
        if d.qn <= s_qn + 0.15 then
            local dist = s_qn - d.qn
            if dist < min_prev_dist then
                min_prev_dist = dist
                prev_dyn = d
            end
        end
        if d.qn >= e_qn - 0.15 then
            local dist = d.qn - e_qn
            if dist < min_next_dist then
                min_next_dist = dist
                next_dyn = d
            end
        end
    end

    local l_bound = 0.0
    if prev_dt then
        local pe = prev_dt.end_qn or (prev_dt.start_qn + 4.0)
        l_bound = math.max(l_bound, pe)
    end
    if prev_hp then
        local pe = prev_hp.end_qn or (prev_hp.start_qn + 4.0)
        l_bound = math.max(l_bound, pe)
    end
    if prev_dyn then
        l_bound = math.max(l_bound, prev_dyn.qn)
    end

    local r_bound = 999999.0
    if next_dt then
        local ns = next_dt.start_qn or 0.0
        r_bound = math.min(r_bound, ns)
    end
    if next_hp then
        local ns = next_hp.start_qn or 0.0
        r_bound = math.min(r_bound, ns)
    end
    if next_dyn then
        r_bound = math.min(r_bound, next_dyn.qn)
    end

    return l_bound, r_bound, prev_dt, next_dt, prev_hp, next_hp, prev_dyn, next_dyn
end

function DynamicTextService.resolve_levels(state, dt, active_tracks_data)
    local track_dyns = {}
    if active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.guid == dt.track_guid and tdata.dynamics then
                for _, d in ipairs(tdata.dynamics) do
                    table.insert(track_dyns, d)
                end
                break
            end
        end
    end
    if #track_dyns == 0 then
        local take, _ = DynamicTextService.find_take_for_track(dt.track_guid, active_tracks_data)
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            local _, _, _, textcnt = reaper.MIDI_CountEvts(take)
            for ti = 0, textcnt - 1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 and msg:match("^dynamic%s+([%a%d]+)%s*:(%d+):(%d+)") then
                    local lbl, c1, c2 = msg:match("^dynamic%s+([%a%d]+)%s*:(%d+):(%d+)")
                    local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                    table.insert(track_dyns, { qn = qn, label = lbl, c1 = tonumber(c1), c2 = tonumber(c2) })
                end
            end
        end
    end
    table.sort(track_dyns, function(a, b) return (a.qn or 0) < (b.qn or 0) end)

    local prev_dyn, next_dyn = nil, nil
    for _, d in ipairs(track_dyns) do
        if d.qn <= dt.start_qn + 0.15 then prev_dyn = d end
        if d.qn >= dt.end_qn - 0.15 and not next_dyn then next_dyn = d end
    end

    local c1_s, c11_s = nil, nil
    if dt.start_dyn and DYN_LOOKUP[dt.start_dyn:lower()] then
        c1_s = DYN_LOOKUP[dt.start_dyn:lower()].c1
        c11_s = DYN_LOOKUP[dt.start_dyn:lower()].c2
    elseif prev_dyn and prev_dyn.label and DYN_LOOKUP[prev_dyn.label:lower()] then
        c1_s = DYN_LOOKUP[prev_dyn.label:lower()].c1
        c11_s = DYN_LOOKUP[prev_dyn.label:lower()].c2
    end

    local c1_e, c11_e = nil, nil
    if dt.end_dyn and DYN_LOOKUP[dt.end_dyn:lower()] then
        c1_e = DYN_LOOKUP[dt.end_dyn:lower()].c1
        c11_e = DYN_LOOKUP[dt.end_dyn:lower()].c2
    elseif next_dyn and next_dyn.label and DYN_LOOKUP[next_dyn.label:lower()] then
        c1_e = DYN_LOOKUP[next_dyn.label:lower()].c1
        c11_e = DYN_LOOKUP[next_dyn.label:lower()].c2
    end

    local is_dim = (dt.type == "diminuendo" or dt.type == "decrescendo")
    if dt.text then
        local t_low = dt.text:lower()
        if t_low:match("dim") or t_low:match("decresc") then
            is_dim = true
        end
    end

    if is_dim then
        -- DIMINUENDO: Must decrease from loud to soft!
        -- Start level: If not set or too soft for a diminuendo (< 65), set to at least 'f' (95)
        if not c1_s or c1_s < 65 then
            c1_s = 95
            c11_s = 100
        end
        -- End level: If right neighbor is louder or equal to start, discard for diminuendo
        if c1_e and c1_e >= c1_s then
            c1_e = nil
            c11_e = nil
        end
        c1_e = c1_e or math.max(15, c1_s - 35)
        c11_e = c11_e or math.max(20, c11_s - 35)

        -- Absolute guarantee: c1_e MUST be smaller than c1_s
        if c1_e >= c1_s then
            c1_e = math.max(15, c1_s - 30)
            c11_e = math.max(20, c11_s - 30)
        end
    else
        -- CRESCENDO: Must increase from soft to loud!
        if not c1_s or c1_s > 95 then
            c1_s = 50
            c11_s = 55
        end
        if c1_e and c1_e <= c1_s then
            c1_e = nil
            c11_e = nil
        end
        c1_e = c1_e or math.min(127, c1_s + 35)
        c11_e = c11_e or math.min(127, c1_s + 35)

        -- Absolute guarantee: c1_e MUST be greater than c1_s
        if c1_e <= c1_s then
            c1_e = math.min(127, c1_s + 30)
            c11_e = math.min(127, c1_s + 30)
        end
    end

    return c1_s, c11_s, c1_e, c11_e
end

function DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data, opt_clear_start_ppq, opt_clear_end_ppq)
    if not dt or dt.start_qn >= dt.end_qn then return end

    local take, item = DynamicTextService.find_take_for_track(dt.track_guid, active_tracks_data, dt.start_qn)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

    if item and reaper.ValidatePtr(item, "MediaItem*") then
        DynamicsEngine.load_item_modulators(item, state)
    end

    -- WHEN BYPASS DYNAMIC CC SHAPING IS ACTIVE:
    -- Do not delete or write any CCs!
    if state.dyn_bypass_cc then
        return
    end

    local start_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, dt.start_qn) + 0.5)
    local end_ppq   = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, dt.end_qn) + 0.5)
    if end_ppq <= start_ppq then return end

    local c1_s, c11_s, c1_e, c11_e = DynamicTextService.resolve_levels(state, dt, active_tracks_data)

    local clear_s_ppq = start_ppq
    local clear_e_ppq = end_ppq
    if opt_clear_start_ppq then clear_s_ppq = math.min(clear_s_ppq, opt_clear_start_ppq) end
    if opt_clear_end_ppq   then clear_e_ppq = math.max(clear_e_ppq, opt_clear_end_ppq) end

    reaper.Undo_BeginBlock2(0)

    -- Delete old CC values in interval
    local _, _, cc_count = reaper.MIDI_CountEvts(take)
    for j = (cc_count or 0) - 1, 0, -1 do
        local ok, _, _, ppq, _, _, m, _ = reaper.MIDI_GetCC(take, j)
        if ok and (m == state.dyn_cc_a or m == state.dyn_cc_b) then
            if ppq >= clear_s_ppq and ppq <= clear_e_ppq then
                reaper.MIDI_DeleteCC(take, j)
            end
        end
    end

    local opt = Constants.DYN_GRID_OPTIONS[state.dyn_grid_idx] or Constants.DYN_GRID_OPTIONS[4]
    local grid_ppq = (opt and opt.val) and math.floor(opt.val * 960 + 0.5) or 240
    if grid_ppq < 10 then grid_ppq = 60 end

    local dur = end_ppq - start_ppq
    local steps = math.max(4, math.floor(dur / grid_ppq))
    local p_start = DynamicsEngine.get_pitch_at_ppq(take, start_ppq)
    local p_end = DynamicsEngine.get_pitch_at_ppq(take, end_ppq)
    local delta = (p_start and p_end) and (p_end - p_start) or 0

    local curve_pattern = dt.curve_pattern or "linear"

    for s = 0, steps do
        local cur = start_ppq + math.floor(s * (dur / steps) + 0.5)
        if cur <= end_ppq then
            local raw_ratio = (dur > 0) and ((cur - start_ppq) / dur) or 0
            local cr = raw_ratio

            if curve_pattern == "exponential" then
                if dt.type == "crescendo" then
                    cr = raw_ratio * raw_ratio
                else
                    cr = 1.0 - (1.0 - raw_ratio) * (1.0 - raw_ratio)
                end
            elseif curve_pattern == "s_curve" then
                cr = 0.5 * (1.0 - math.cos(math.pi * raw_ratio))
            end

            local base_v1 = math.floor(c1_s + (c1_e - c1_s) * cr + 0.5)
            local base_v2 = math.floor(c11_s + (c11_e - c11_s) * cr + 0.5)

            local val1 = DynamicsEngine.get_smart_val(state, c1_s, c1_e, cr, delta, base_v1)
            local val2 = DynamicsEngine.get_smart_val(state, c11_s, c11_e, cr, delta, base_v2)

            local f1 = math.max(0, math.min(127, math.floor(val1 + 0.5)))
            local f2 = math.max(0, math.min(127, math.floor(val2 + 0.5)))
            local cc_a = math.floor(state.dyn_cc_a or 1)
            local cc_b = math.floor(state.dyn_cc_b or 11)
            local cur_ppq = math.floor(cur + 0.5)
            reaper.MIDI_InsertCC(take, false, false, cur_ppq, 176, 0, cc_a, f1)
            reaper.MIDI_InsertCC(take, false, false, cur_ppq, 176, 0, cc_b, f2)
        end
    end

    reaper.MIDI_Sort(take)

    -- Apply linear curve shape (1 = Linear) so REAPER draws a real ramp instead of stair steps
    if reaper.APIExists("MIDI_SetCCShape") then
        local _, _, total_ccs = reaper.MIDI_CountEvts(take)
        for j = 0, (total_ccs or 0) - 1 do
            local ok, _, _, ppq, _, _, m, _ = reaper.MIDI_GetCC(take, j)
            if ok and (m == state.dyn_cc_a or m == state.dyn_cc_b) then
                if ppq >= clear_s_ppq and ppq <= clear_e_ppq then
                    reaper.MIDI_SetCCShape(take, j, 1, 0.0)
                end
            end
        end
    end

    local _, final_str = reaper.MIDI_GetAllEvts(take, "")
    if final_str and #final_str > 0 then
        local final_midi_table, f_pos = {}, 1
        local running_ppq = 0
        while f_pos <= #final_str do
            local offset, flag, msg, next_pos = string.unpack("<i4Bs4", final_str, f_pos)
            running_ppq = running_ppq + offset
            if #msg == 3 and (msg:byte(1) & 0xF0) == 0xB0 then
                local cn = msg:byte(2)
                if cn == state.dyn_cc_a or cn == state.dyn_cc_b then
                    if running_ppq >= clear_s_ppq and running_ppq <= clear_e_ppq then
                        flag = (flag & 0x0F) | (1 << 4) -- 1 = Linear
                    end
                end
            end
            table.insert(final_midi_table, string.pack("<i4Bs4", offset, flag, msg))
            f_pos = next_pos
        end
        reaper.MIDI_SetAllEvts(take, table.concat(final_midi_table))
        reaper.MIDI_Sort(take)
    end

    reaper.Undo_EndBlock2(0, string.format("Notator: %s CC Ramp (%s)", dt.text or dt.type, curve_pattern), -1)
    reaper.UpdateArrange()
end

function DynamicTextService.create_dynamic_text(state, track_guid, dtype, text, start_qn, end_qn, line_pattern, curve_pattern, start_dyn, end_dyn, midi_service, active_tracks_data, staff)
    if not track_guid or track_guid == "" then return nil end
    local s_qn = start_qn or 0.0
    local e_qn = end_qn or (s_qn + 4.0)
    
    -- If dynamic texts already exist on the track, check bounds
    if state.dynamic_texts then
        for _, other in ipairs(state.dynamic_texts) do
            if other.track_guid == track_guid then
                local o_s = other.start_qn or 0.0
                local o_e = other.end_qn or (o_s + 1.0)
                if s_qn >= o_s and s_qn < o_e then
                    s_qn = o_e
                    e_qn = math.max(s_qn + 0.25, e_qn)
                end
                if o_s > s_qn and e_qn > o_s then
                    e_qn = o_s
                end
            end
        end
    end
    -- Also respect hairpins as physical bounds
    if state.hairpins then
        for _, hp in ipairs(state.hairpins) do
            if hp.track_guid == track_guid then
                local h_s = hp.start_qn or 0.0
                local h_e = hp.end_qn or (h_s + 1.0)
                if s_qn >= h_s and s_qn < h_e then
                    s_qn = h_e
                    e_qn = math.max(s_qn + 0.25, e_qn)
                end
                if h_s > s_qn and e_qn > h_s then
                    e_qn = h_s
                end
            end
        end
    end
    if e_qn <= s_qn + 0.15 then
        e_qn = s_qn + 0.5
    end

    local dt = DynamicText.new({
        track_guid    = track_guid,
        type          = dtype or "crescendo",
        text          = text or (dtype == "diminuendo" and "dim." or "cresc."),
        start_qn      = s_qn,
        end_qn        = e_qn,
        line_pattern  = line_pattern or state.dyn_text_line_pattern or "none",
        curve_pattern = curve_pattern or state.dyn_text_curve_pattern or "linear",
        start_dyn     = start_dyn,
        end_dyn       = end_dyn,
        staff         = staff
    })

    if not state.dynamic_texts then state.dynamic_texts = {} end
    table.insert(state.dynamic_texts, dt)
    state.selected_dynamic_text = dt
    DynamicTextService.save_dynamic_texts(state)

    DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data)
    reaper.Undo_OnStateChange2(0, string.format("Notator: Add text dynamic '%s'", dt.text))
    state.status_msg = string.format("✨ Inserted text dynamic '%s' (%.1f QN, pattern: %s, curve: %s)",
        dt.text, dt.end_qn - dt.start_qn, dt.line_pattern, dt.curve_pattern)
    return dt
end

function DynamicTextService.resize_dynamic_text(state, dt_id, new_start_qn, new_end_qn, midi_service, active_tracks_data)
    if not state.dynamic_texts then return end
    for _, dt in ipairs(state.dynamic_texts) do
        if dt.id == dt_id then
            local old_s = dt.start_qn
            local old_e = dt.end_qn
            dt.start_qn = math.max(0, new_start_qn)
            dt.end_qn = math.max(dt.start_qn + 0.25, new_end_qn)
            DynamicTextService.save_dynamic_texts(state)

            local take = DynamicTextService.find_take_for_track(dt.track_guid, active_tracks_data)
            local clear_s, clear_e = nil, nil
            if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
                clear_s = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, math.min(old_s, dt.start_qn)) + 0.5)
                clear_e = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, math.max(old_e, dt.end_qn)) + 0.5)
            end
            DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data, clear_s, clear_e)
            state.status_msg = string.format("Adjusted text dynamic '%s': %.2f - %.2f QN (length: %.2f QN)",
                dt.text, dt.start_qn, dt.end_qn, dt.end_qn - dt.start_qn)
            break
        end
    end
end

function DynamicTextService.move_dynamic_text(state, dt_id, delta_qn, midi_service, active_tracks_data)
    if not state.dynamic_texts then return end
    for _, dt in ipairs(state.dynamic_texts) do
        if dt.id == dt_id then
            local dur = dt.end_qn - dt.start_qn
            local old_s = dt.start_qn
            local old_e = dt.end_qn
            dt.start_qn = math.max(0, dt.start_qn + delta_qn)
            dt.end_qn = dt.start_qn + dur
            DynamicTextService.save_dynamic_texts(state)

            local take = DynamicTextService.find_take_for_track(dt.track_guid, active_tracks_data)
            local clear_s, clear_e = nil, nil
            if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
                clear_s = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, math.min(old_s, dt.start_qn)) + 0.5)
                clear_e = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, math.max(old_e, dt.end_qn)) + 0.5)
            end
            DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data, clear_s, clear_e)
            state.status_msg = string.format("Moved text dynamic '%s' to %.2f QN", dt.text, dt.start_qn)
            break
        end
    end
end

function DynamicTextService.delete_dynamic_text(state, dt_id, midi_service, active_tracks_data)
    if not state.dynamic_texts then return end
    local target = nil
    local rem_idx = nil
    for idx, dt in ipairs(state.dynamic_texts) do
        if dt.id == dt_id then
            target = dt
            rem_idx = idx
            break
        end
    end
    if not target then return end

    table.remove(state.dynamic_texts, rem_idx)
    if state.selected_dynamic_text and state.selected_dynamic_text.id == dt_id then
        state.selected_dynamic_text = nil
    end
    DynamicTextService.save_dynamic_texts(state)

    local take = DynamicTextService.find_take_for_track(target.track_guid, active_tracks_data)
    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        local start_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, target.start_qn) + 0.5)
        local end_ppq   = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, target.end_qn) + 0.5)
        reaper.Undo_BeginBlock2(0)
        local _, _, cc_count = reaper.MIDI_CountEvts(take)
        for j = (cc_count or 0) - 1, 0, -1 do
            local ok, _, _, ppq, _, _, m, _ = reaper.MIDI_GetCC(take, j)
            if ok and (m == state.dyn_cc_a or m == state.dyn_cc_b) then
                if ppq >= start_ppq and ppq <= end_ppq then
                    reaper.MIDI_DeleteCC(take, j)
                end
            end
        end
        reaper.MIDI_Sort(take)
        -- Refresh remaining hairpins on this track
        if state.hairpins then
            local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
            local track_hps = {}
            for _, thp in ipairs(state.hairpins) do
                if thp.track_guid == target.track_guid then
                    table.insert(track_hps, thp)
                end
            end
            table.sort(track_hps, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
            for _, thp in ipairs(track_hps) do
                HairpinService.apply_hairpin_cc(state, thp, midi_service, active_tracks_data)
            end
        end
        reaper.Undo_EndBlock2(0, string.format("Notator: Delete text dynamic '%s'", target.text), -1)
        reaper.UpdateArrange()
    end
    state.status_msg = string.format("🗑 Deleted text dynamic '%s'", target.text)
end

return DynamicTextService

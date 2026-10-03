-- ==============================================================================
-- REAPER Native Notator - Service: HairpinService
-- Manages Crescendo (<) and Decrescendo (>) dynamic hairpins with dual handles
-- Live CC1 (ModWheel) & CC11 (Expression) calculation with Smart Modulators
-- ==============================================================================

local Hairpin = require("classes.hairpin")
local DynamicsEngine = require("services.dynamics_engine")
local Constants = require("constants")

local HairpinService = {}

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

local function sync_hairpins_to_takes(state)
    local by_guid = {}
    for _, hp in ipairs(state.hairpins or {}) do
        if hp.track_guid then
            by_guid[hp.track_guid] = by_guid[hp.track_guid] or {}
            table.insert(by_guid[hp.track_guid], hp)
        end
    end
    
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            local track_hp_list = by_guid[trk_guid] or {}
            
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
                        if ok and ev_type == 15 and msg:match("^NOTATOR_HAIRPIN") then
                            table.insert(to_del, t_idx)
                        end
                    end
                    for _, d_idx in ipairs(to_del) do
                        reaper.MIDI_DeleteTextSysexEvt(take, d_idx)
                    end
                    
                    local inserted = false
                    for _, hp in ipairs(track_hp_list) do
                        if hp.start_qn >= (i_start_qn - 0.05) and hp.start_qn < (i_end_qn + 0.05) then
                            local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, hp.start_qn) + 0.5)
                            local msg = string.format("NOTATOR_HAIRPIN|%s|%s|%.4f|%.4f|%s|%s|%s",
                                hp.id, hp.type, hp.start_qn, hp.end_qn,
                                hp.start_dyn or "", hp.end_dyn or "", hp.staff or "")
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

function HairpinService.load_hairpins(state)
    state.hairpins = {}
    local known = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "hairpins")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id = parts[1]
            local track_guid = parts[2]
            local htype = parts[3]
            local start_qn = tonumber(parts[4]) or 0.0
            local end_qn = tonumber(parts[5]) or 4.0
            local start_dyn = (parts[6] and parts[6] ~= "") and parts[6] or nil
            local end_dyn = (parts[7] and parts[7] ~= "") and parts[7] or nil
            local staff = (parts[8] and parts[8] ~= "") and parts[8] or nil
            if id and id ~= "" and track_guid and htype then
                known[id] = true
                local hp = Hairpin.new({
                    id         = id,
                    track_guid = track_guid,
                    type       = htype,
                    start_qn   = start_qn,
                    end_qn     = end_qn,
                    start_dyn  = start_dyn,
                    end_dyn    = end_dyn,
                    staff      = staff
                })
                table.insert(state.hairpins, hp)
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
                        if ok and ev_type == 15 and msg:match("^NOTATOR_HAIRPIN") then
                            local parts = {}
                            for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
                            local id = parts[2]
                            local htype = parts[3]
                            local start_qn = tonumber(parts[4]) or reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                            local end_qn = tonumber(parts[5]) or (start_qn + 4.0)
                            local start_dyn = (parts[6] and parts[6] ~= "") and parts[6] or nil
                            local end_dyn = (parts[7] and parts[7] ~= "") and parts[7] or nil
                            local staff = (parts[8] and parts[8] ~= "") and parts[8] or nil
                            if id and id ~= "" and htype and not known[id] then
                                known[id] = true
                                table.insert(state.hairpins, Hairpin.new({
                                    id         = id,
                                    track_guid = trk_guid,
                                    type       = htype,
                                    start_qn   = start_qn,
                                    end_qn     = end_qn,
                                    start_dyn  = start_dyn,
                                    end_dyn    = end_dyn,
                                    staff      = staff
                                }))
                            end
                        end
                    end
                end
            end
        end
    end
end

function HairpinService.parse_notation_event(state, track, take, ppq, msg)
    if not state or not msg then return end
    if not state.hairpins then state.hairpins = {} end
    local trk_guid = track and reaper.ValidatePtr(track, "MediaTrack*") and reaper.GetTrackGUID(track)
    if not trk_guid then return end
    
    local parts = {}
    for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
    local id = parts[2]
    if not id or id == "" then return end
    
    for _, hp in ipairs(state.hairpins) do
        if hp.id == id then return end
    end
    
    local htype = parts[3] or "crescendo"
    local start_qn = tonumber(parts[4]) or (take and reaper.MIDI_GetProjQNFromPPQPos(take, ppq)) or 0.0
    local end_qn = tonumber(parts[5]) or (start_qn + 4.0)
    local start_dyn = (parts[6] and parts[6] ~= "") and parts[6] or nil
    local end_dyn = (parts[7] and parts[7] ~= "") and parts[7] or nil
    local staff = (parts[8] and parts[8] ~= "") and parts[8] or nil
    
    table.insert(state.hairpins, Hairpin.new({
        id         = id,
        track_guid = trk_guid,
        type       = htype,
        start_qn   = start_qn,
        end_qn     = end_qn,
        start_dyn  = start_dyn,
        end_dyn    = end_dyn,
        staff      = staff
    }))
end

function HairpinService.save_hairpins(state)
    local parts = {}
    for _, hp in ipairs(state.hairpins or {}) do
        local entry = string.format("%s|%s|%s|%.4f|%.4f|%s|%s|%s",
            hp.id, hp.track_guid, hp.type, hp.start_qn, hp.end_qn,
            hp.start_dyn or "", hp.end_dyn or "", hp.staff or "")
        table.insert(parts, entry)
    end
    local raw = table.concat(parts, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "hairpins", raw)
    sync_hairpins_to_takes(state)
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    if reaper.Main_UpdateLoopInfo then reaper.Main_UpdateLoopInfo(0) end
end

function HairpinService.get_hairpins_for_track(state, track_guid)
    local res = {}
    for _, hp in ipairs(state.hairpins or {}) do
        if hp.track_guid == track_guid then
            table.insert(res, hp)
        end
    end
    table.sort(res, function(a, b) return a.start_qn < b.start_qn end)
    return res
end

function HairpinService.find_take_for_track(track_guid, active_tracks_data, opt_qn)
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
                        local tk = reaper.GetActiveTake(it)
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
    -- Fallback via REAPER project tracks
    local trk_cnt = reaper.CountTracks(0)
    for i = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, i)
        if trk and reaper.GetTrackGUID(trk) == track_guid then
            local item_cnt = reaper.CountTrackMediaItems(trk)
            for j = 0, item_cnt - 1 do
                local it = reaper.GetTrackMediaItem(trk, j)
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
    return fallback_tk, fallback_it
end

local function collect_track_dynamics(track_guid, active_tracks_data)
    local track_dyns = {}
    if active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.guid == track_guid and tdata.dynamics then
                for _, d in ipairs(tdata.dynamics) do
                    table.insert(track_dyns, d)
                end
                break
            end
        end
    end
    if #track_dyns == 0 then
        local take, _ = HairpinService.find_take_for_track(track_guid, active_tracks_data)
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
    return track_dyns
end

function HairpinService.get_hairpin_bounds(state, hp, active_tracks_data)
    if not hp then return 0.0, 999999.0, nil, nil, nil, nil end
    local s_qn = hp.start_qn or 0.0
    local e_qn = hp.end_qn or (s_qn + 4.0)
    
    -- 1. Find neighbor hairpins on the same track
    local prev_hp, next_hp = nil, nil
    local max_prev_start = -1
    local min_next_start = 99999999
    
    if state.hairpins then
        for _, other in ipairs(state.hairpins) do
            if other.id ~= hp.id and other.track_guid == hp.track_guid then
                local o_s = other.start_qn or 0.0
                -- Lies before this hairpin
                if o_s < s_qn then
                    if o_s > max_prev_start then
                        max_prev_start = o_s
                        prev_hp = other
                    end
                -- Lies after this hairpin
                elseif o_s > s_qn then
                    if o_s < min_next_start then
                        min_next_start = o_s
                        next_hp = other
                    end
                end
            end
        end
    end
    
    -- 2. Find dynamic markers on the same track
    local prev_dyn, next_dyn = nil, nil
    local max_prev_dyn_qn = -1
    local min_next_dyn_qn = 99999999
    local track_dyns = collect_track_dynamics(hp.track_guid, active_tracks_data)
    
    for _, d in ipairs(track_dyns) do
        -- Marker lies before or directly at the start
        if d.qn <= s_qn + 0.05 then
            if d.qn > max_prev_dyn_qn then
                max_prev_dyn_qn = d.qn
                prev_dyn = d
            end
        -- Marker lies strictly after the start
        elseif d.qn > s_qn + 0.05 then
            if d.qn < min_next_dyn_qn then
                min_next_dyn_qn = d.qn
                next_dyn = d
            end
        end
    end
    
    -- 2b. Find dynamic texts (cresc., dim.) on the same track
    local prev_dt, next_dt = nil, nil
    local max_prev_dt_start = -1
    local min_next_dt_start = 99999999
    if state.dynamic_texts then
        for _, dt in ipairs(state.dynamic_texts) do
            if dt.track_guid == hp.track_guid then
                local dt_s = dt.start_qn or 0.0
                if dt_s < s_qn - 0.05 then
                    if dt_s > max_prev_dt_start then
                        max_prev_dt_start = dt_s
                        prev_dt = dt
                    end
                elseif dt_s > s_qn + 0.05 then
                    if dt_s < min_next_dt_start then
                        min_next_dt_start = dt_s
                        next_dt = dt
                    end
                end
            end
        end
    end
    
    -- 2c. Find articulations on the same track
    local max_prev_art_qn = -1
    local min_next_art_qn = 99999999
    if active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.guid == hp.track_guid and tdata.articulations then
                for _, a in ipairs(tdata.articulations) do
                    local aqn = a.qn or 0.0
                    if aqn <= s_qn + 0.05 then
                        if aqn > max_prev_art_qn then max_prev_art_qn = aqn end
                    elseif aqn > s_qn + 0.05 then
                        if aqn < min_next_art_qn then min_next_art_qn = aqn end
                    end
                end
            end
        end
    end

    -- 3. Calculate strict physical bounds
    local l_bound = 0.0
    if prev_hp then
        local pe = prev_hp.end_qn or (prev_hp.start_qn + 4.0)
        l_bound = math.max(l_bound, pe)
    end
    if prev_dyn then
        l_bound = math.max(l_bound, prev_dyn.qn)
    end
    if prev_dt then
        local pde = prev_dt.end_qn or (prev_dt.start_qn + 4.0)
        l_bound = math.max(l_bound, pde)
    end
    if max_prev_art_qn >= 0 then
        l_bound = math.max(l_bound, max_prev_art_qn)
    end
    
    local r_bound = 999999.0
    if next_hp then
        local ns = next_hp.start_qn or 0.0
        r_bound = math.min(r_bound, ns)
    end
    if next_dyn then
        r_bound = math.min(r_bound, next_dyn.qn)
    end
    if next_dt then
        local nds = next_dt.start_qn or 0.0
        r_bound = math.min(r_bound, nds)
    end
    if min_next_art_qn < 99999999 then
        r_bound = math.min(r_bound, min_next_art_qn)
    end
    
    return l_bound, r_bound, prev_hp, next_hp, prev_dyn, next_dyn, prev_dt, next_dt
end

function HairpinService.resolve_all_track_hairpins(state, track_guid, active_tracks_data)
    if not state.hairpins or not track_guid then return {} end
    
    local track_hps = {}
    for _, hp in ipairs(state.hairpins) do
        if hp.track_guid == track_guid then
            table.insert(track_hps, hp)
        end
    end
    table.sort(track_hps, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
    
    local track_dyns = collect_track_dynamics(track_guid, active_tracks_data)
    
    local running_c1 = 50
    local running_c11 = 55
    if #track_dyns > 0 and track_dyns[1].qn <= 0.5 and track_dyns[1].label then
        local lk = DYN_LOOKUP[track_dyns[1].label:lower()]
        if lk then
            running_c1 = lk.c1
            running_c11 = lk.c2
        end
    end
    
    for idx, hp in ipairs(track_hps) do
        local s_qn = hp.start_qn or 0.0
        local e_qn = hp.end_qn or (s_qn + 4.0)
        
        local prev_dyn, next_dyn = nil, nil
        for _, d in ipairs(track_dyns) do
            if d.qn <= s_qn + 0.15 then
                prev_dyn = d
            end
            if d.qn >= e_qn - 0.15 and not next_dyn then
                next_dyn = d
            end
        end
        
        local prev_hp = (idx > 1) and track_hps[idx - 1] or nil
        local next_hp = (idx < #track_hps) and track_hps[idx + 1] or nil
        
        local bp_lk = (prev_dyn and prev_dyn.label) and DYN_LOOKUP[prev_dyn.label:lower()] or nil
        local bn_lk = (next_dyn and next_dyn.label) and DYN_LOOKUP[next_dyn.label:lower()] or nil
        
        local is_dyn_at_start = (prev_dyn and math.abs(prev_dyn.qn - s_qn) <= 0.45)
        local is_dyn_at_end   = (next_dyn and math.abs(next_dyn.qn - e_qn) <= 0.45)
        local is_hp_at_end    = (next_hp and math.abs((next_hp.start_qn or 0.0) - e_qn) <= 0.35)
        
        -- 1. Determine start dynamic level
        local c1_s, c11_s = nil, nil
        if hp.start_dyn and DYN_LOOKUP[hp.start_dyn:lower()] then
            c1_s = DYN_LOOKUP[hp.start_dyn:lower()].c1
            c11_s = DYN_LOOKUP[hp.start_dyn:lower()].c2
        elseif is_dyn_at_start and bp_lk then
            c1_s = bp_lk.c1
            c11_s = bp_lk.c2
        elseif prev_dyn and prev_hp and prev_dyn.qn > (prev_hp.end_qn or 0) and bp_lk then
            c1_s = bp_lk.c1
            c11_s = bp_lk.c2
        elseif prev_hp and prev_hp.c1_end then
            c1_s = prev_hp.c1_end
            c11_s = prev_hp.c11_end or prev_hp.c1_end
        elseif bp_lk then
            c1_s = bp_lk.c1
            c11_s = bp_lk.c2
        else
            c1_s = running_c1
            c11_s = running_c11
        end
        if hp.type == "decrescendo" and (not hp.start_dyn) and (not is_dyn_at_start) and (c1_s < 65) then
            c1_s = 95
            c11_s = 100
        end
        
        -- 2. Determine target dynamic level
        local c1_e, c11_e = nil, nil
        if hp.end_dyn and DYN_LOOKUP[hp.end_dyn:lower()] then
            c1_e = DYN_LOOKUP[hp.end_dyn:lower()].c1
            c11_e = DYN_LOOKUP[hp.end_dyn:lower()].c2
        elseif is_dyn_at_end and bn_lk then
            c1_e = bn_lk.c1
            c11_e = bn_lk.c2
        elseif hp.type == "crescendo" then
            if is_hp_at_end and next_hp.type == "decrescendo" then
                c1_e = math.max(c1_s + 35, 100)
                c11_e = math.max(c11_s + 35, 105)
            elseif bn_lk and bn_lk.c1 > c1_s then
                if next_hp and next_hp.start_qn < next_dyn.qn then
                    c1_e = math.min(bn_lk.c1, math.floor(c1_s + (bn_lk.c1 - c1_s) * 0.6 + 0.5))
                    c11_e = math.min(bn_lk.c2, math.floor(c11_s + (bn_lk.c2 - c11_s) * 0.6 + 0.5))
                else
                    c1_e = bn_lk.c1
                    c11_e = bn_lk.c2
                end
            else
                c1_e = math.min(127, math.max(c1_s + 35, 85))
                c11_e = math.min(127, math.max(c11_s + 35, 90))
            end
            if c1_e <= c1_s then
                c1_e = math.min(127, c1_s + 20)
                c11_e = math.min(127, c11_s + 20)
            end
        else -- decrescendo
            if bn_lk and bn_lk.c1 < c1_s then
                if next_hp and next_hp.start_qn < next_dyn.qn then
                    c1_e = math.max(bn_lk.c1, math.floor(c1_s - (c1_s - bn_lk.c1) * 0.6 + 0.5))
                    c11_e = math.max(bn_lk.c2, math.floor(c11_s - (c11_s - bn_lk.c2) * 0.6 + 0.5))
                else
                    c1_e = bn_lk.c1
                    c11_e = bn_lk.c2
                end
            else
                c1_e = math.max(20, c1_s - 35)
                c11_e = math.max(25, c11_s - 35)
            end
            if c1_e >= c1_s then
                c1_e = math.max(20, c1_s - 20)
                c11_e = math.max(25, c11_s - 20)
            end
        end
        
        hp.c1_start = math.max(0, math.min(127, c1_s))
        hp.c11_start = math.max(0, math.min(127, c11_s))
        hp.c1_end = math.max(0, math.min(127, c1_e))
        hp.c11_end = math.max(0, math.min(127, c11_e))
        running_c1 = hp.c1_end
        running_c11 = hp.c11_end
    end
    
    return track_hps
end

function HairpinService.resolve_dynamic_levels(state, hp, active_tracks_data, opt_prev_hp, opt_next_hp, opt_prev_dyn, opt_next_dyn)
    HairpinService.resolve_all_track_hairpins(state, hp.track_guid, active_tracks_data)
    local c1_s = hp.c1_start or 50
    local c11_s = hp.c11_start or 55
    local c1_e = hp.c1_end or 85
    local c11_e = hp.c11_end or 90
    return c1_s, c11_s, c1_e, c11_e, opt_prev_dyn, opt_next_dyn, opt_prev_hp, opt_next_hp
end

function HairpinService.apply_hairpin_cc(state, hp, midi_service, active_tracks_data, opt_clear_start_ppq, opt_clear_end_ppq)
    if not hp or hp.start_qn >= hp.end_qn then return end
    
    local take, item = HairpinService.find_take_for_track(hp.track_guid, active_tracks_data, hp.start_qn)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end
    
    if item and reaper.ValidatePtr(item, "MediaItem*") then
        DynamicsEngine.load_item_modulators(item, state)
    end
    
    -- WHEN BYPASS DYNAMIC CC SHAPING IS ACTIVE:
    -- Do not delete or rewrite any CCs!
    if state.dyn_bypass_cc then
        return
    end
    
    local start_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, hp.start_qn) + 0.5)
    local end_ppq   = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, hp.end_qn) + 0.5)
    if end_ppq <= start_ppq then return end
    
    local l_bound_qn, r_bound_qn, prev_hp, next_hp, prev_dyn, next_dyn = HairpinService.get_hairpin_bounds(state, hp, active_tracks_data)
    local c1_s, c11_s, c1_e, c11_e = HairpinService.resolve_dynamic_levels(state, hp, active_tracks_data, prev_hp, next_hp, prev_dyn, next_dyn)
    
    reaper.Undo_BeginBlock2(0)
    
    -- Isolated cleanup strictly within hairpin range (including previous drag position)
    local clear_s_ppq = math.min(start_ppq, opt_clear_start_ppq or start_ppq)
    local clear_e_ppq = math.max(end_ppq, opt_clear_end_ppq or end_ppq)
    
    -- Delete existing CC events isolated within allowed interval
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
    
    -- Prepare take notes for bow swelling
    local take_notes = {}
    local has_bow = (state.dyn_bow_intensity or 0) > 0
    if has_bow then
        local _, note_cnt = reaper.MIDI_CountEvts(take)
        for n = 0, (note_cnt or 0) - 1 do
            local ok, _, _, s_ppq, e_ppq, _, pitch, vel = reaper.MIDI_GetNote(take, n)
            if ok and e_ppq > start_ppq and s_ppq < end_ppq then
                local s_qn = reaper.MIDI_GetProjQNFromPPQPos(take, s_ppq)
                local e_qn = reaper.MIDI_GetProjQNFromPPQPos(take, e_ppq)
                table.insert(take_notes, {
                    start_ppq = s_ppq,
                    end_ppq = e_ppq,
                    pitch = pitch,
                    dur_qn = math.abs(e_qn - s_qn)
                })
            end
        end
    end
    
    -- Hairpin ramp itself [start_ppq .. end_ppq]
    local dur = end_ppq - start_ppq
    local steps = math.max(4, math.floor(dur / grid_ppq))
    
    local p_start = DynamicsEngine.get_pitch_at_ppq(take, start_ppq)
    local p_end = DynamicsEngine.get_pitch_at_ppq(take, end_ppq)
    local delta = (p_start and p_end) and (p_end - p_start) or 0
    
    for s = 0, steps do
        local cur = start_ppq + math.floor(s * (dur / steps) + 0.5)
        if cur <= end_ppq then
            local ratio = (dur > 0) and ((cur - start_ppq) / dur) or 0
            local val1, val2
            if state.dyn_phrasing_active then
                val1 = DynamicsEngine.get_smart_val(state, c1_s, c1_e, ratio, delta, c1_s + cur)
                val2 = DynamicsEngine.get_smart_val(state, c11_s, c11_e, ratio, delta, c11_s + cur)
            else
                val1 = math.floor(c1_s + (c1_e - c1_s) * ratio + 0.5)
                val2 = math.floor(c11_s + (c11_e - c11_s) * ratio + 0.5)
            end
            
            -- Note-level breathing phrasing
            if state.dyn_phrasing_active then
                local p_int = state.dyn_phrasing_intensity or 0.5
                for _, n in ipairs(take_notes) do
                    if cur >= n.start_ppq and cur <= n.end_ppq then
                        local ndur = n.end_ppq - n.start_ppq
                        local nprog = (ndur > 0) and ((cur - n.start_ppq) / ndur) or 0.5
                        local breath = math.sin(nprog * math.pi)
                        local breath_val = breath * (p_int * 14.0)
                        val1 = val1 + breath_val
                        val2 = val2 + breath_val
                        break
                    end
                end
            end
            
            -- Bow swelling on notes >= quarter note
            if has_bow then
                for _, n in ipairs(take_notes) do
                    if cur >= n.start_ppq and cur <= n.end_ppq and n.dur_qn >= 0.90 then
                        local ndur = n.end_ppq - n.start_ppq
                        local nprog = (ndur > 0) and ((cur - n.start_ppq) / ndur) or 0.5
                        local bcurve = DynamicsEngine.calc_bow_curve and DynamicsEngine.calc_bow_curve(nprog, state.dyn_bow_pos) or math.sin(nprog * math.pi)
                        local bmod = bcurve * ((state.dyn_bow_intensity or 0) * 22.0)
                        val1 = val1 + bmod
                        val2 = val2 + bmod
                        break
                    end
                end
            end
            
            if s == 0 then
                val1 = c1_s
                val2 = c11_s
            elseif s == steps or cur >= end_ppq then
                val1 = c1_e
                val2 = c11_e
            end
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
    
    -- Apply linear curve flags (1 << 4 = 16) (only within cleared range)
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
    
    if item and reaper.ValidatePtr(item, "MediaItem*") then
        reaper.UpdateItemInProject(item)
    end
    
    local name = (hp.type == "crescendo") and "Crescendo (<)" or "Decrescendo (>)"
    reaper.Undo_EndBlock2(0, "Notator: Adjust " .. name .. " Ramp", -1)
    reaper.UpdateArrange()
end

function HairpinService.create_hairpin(state, track_guid, hairpin_type, start_qn, end_qn, opt_start_dyn, opt_end_dyn, midi_service, active_tracks_data, opt_staff)
    if not track_guid or track_guid == "" then return nil end
    local s_qn = math.max(0.0, start_qn or 0.0)
    local e_qn = math.max(s_qn + 0.25, end_qn or (s_qn + 1.0))
    
    -- If hairpins already exist on track, check bounds to prevent overlapping
    if state.hairpins then
        for _, other in ipairs(state.hairpins) do
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
    -- Also respect dynamic texts as physical bounds
    if state.dynamic_texts then
        for _, dt in ipairs(state.dynamic_texts) do
            if dt.track_guid == track_guid then
                local dt_s = dt.start_qn or 0.0
                local dt_e = dt.end_qn or (dt_s + 1.0)
                if s_qn >= dt_s and s_qn < dt_e then
                    s_qn = dt_e
                    e_qn = math.max(s_qn + 0.25, e_qn)
                end
                if dt_s > s_qn and e_qn > dt_s then
                    e_qn = dt_s
                end
            end
        end
    end
    if e_qn <= s_qn + 0.15 then
        e_qn = s_qn + 0.5
    end
    
    local staff = opt_staff
    if not staff and active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.guid == track_guid then
                local is_grand = (tdata.clef == "grand") or (tdata.is_grand == true)
                if is_grand and tdata.notes then
                    local tr_cnt, bs_cnt = 0, 0
                    for _, n in ipairs(tdata.notes) do
                        if n.start_qn < (e_qn + 0.1) and n.end_qn > (s_qn - 0.1) then
                            if n.pitch >= 60 then tr_cnt = tr_cnt + 1 else bs_cnt = bs_cnt + 1 end
                        end
                    end
                    if tr_cnt > 0 or bs_cnt > 0 then
                        staff = (tr_cnt >= bs_cnt) and "treble" or "bass"
                    end
                end
                break
            end
        end
    end

    local hp = Hairpin.new({
        track_guid = track_guid,
        type       = hairpin_type or "crescendo",
        start_qn   = s_qn,
        end_qn     = e_qn,
        start_dyn  = opt_start_dyn,
        end_dyn    = opt_end_dyn,
        staff      = staff
    })
    
    state.hairpins = state.hairpins or {}
    table.insert(state.hairpins, hp)
    HairpinService.save_hairpins(state)
    
    state.selected_hairpin = hp
    HairpinService.apply_hairpin_cc(state, hp, midi_service, active_tracks_data)
    
    local name = (hp.type == "crescendo") and "Crescendo (<)" or "Decrescendo (>)"
    state.status_msg = string.format("%s inserted (%.2f - %.2f QN)", name, s_qn, e_qn)
    reaper.Undo_OnStateChange2(0, "Notator: Insert Hairpin")
    return hp
end

function HairpinService.delete_hairpin(state, hp_id, midi_service, active_tracks_data)
    if not state.hairpins then return end
    local target_idx = nil
    local target_hp = nil
    for idx, hp in ipairs(state.hairpins) do
        if hp.id == hp_id then
            target_idx = idx
            target_hp = hp
            break
        end
    end
    if target_idx and target_hp then
        local track_guid = target_hp.track_guid
        table.remove(state.hairpins, target_idx)
        if state.selected_hairpin and state.selected_hairpin.id == hp_id then
            state.selected_hairpin = nil
        end
        HairpinService.save_hairpins(state)
        
        -- Clean up associated CCs in take or perform smart re-blend between surrounding dynamics
        local take = HairpinService.find_take_for_track(track_guid, active_tracks_data)
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            local start_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, target_hp.start_qn) + 0.5)
            local end_ppq   = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, target_hp.end_qn) + 0.5)
            local anchors = DynamicsEngine.collect_anchors_from_take and DynamicsEngine.collect_anchors_from_take(take) or {}
            if #anchors >= 2 and midi_service then
                -- Selective re-blend only over range of deleted hairpin
                DynamicsEngine.smart_reblend_all(state, midi_service, active_tracks_data, take, start_ppq, end_ppq)
                
                -- Restore remaining hairpins on same track chronologically
                if state.hairpins then
                    local track_hps = {}
                    for _, remaining_hp in ipairs(state.hairpins) do
                        if remaining_hp.track_guid == track_guid then
                            table.insert(track_hps, remaining_hp)
                        end
                    end
                    table.sort(track_hps, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
                    for _, remaining_hp in ipairs(track_hps) do
                        HairpinService.apply_hairpin_cc(state, remaining_hp, midi_service, active_tracks_data)
                    end
                end
                -- Also refresh remaining dynamic texts on same track
                if state.dynamic_texts then
                    local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
                    local track_dts = {}
                    for _, remaining_dt in ipairs(state.dynamic_texts) do
                        if remaining_dt.track_guid == track_guid then
                            table.insert(track_dts, remaining_dt)
                        end
                    end
                    table.sort(track_dts, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
                    for _, remaining_dt in ipairs(track_dts) do
                        DynamicTextService.apply_cc(state, remaining_dt, midi_service, active_tracks_data)
                    end
                end
                state.status_msg = "Hairpin deleted & dynamics re-blended (Smart Re-Blend)"
            else
                -- Fallback if fewer than 2 dynamics present: only delete hairpin CC range
                local start_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, target_hp.start_qn) + 0.5)
                local end_ppq   = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, target_hp.end_qn) + 0.5)
                local _, _, cc_count = reaper.MIDI_CountEvts(take)
                reaper.Undo_BeginBlock2(0)
                for j = (cc_count or 0) - 1, 0, -1 do
                    local ok, _, _, ppq, _, _, m, _ = reaper.MIDI_GetCC(take, j)
                    if ok and (m == state.dyn_cc_a or m == state.dyn_cc_b) then
                        if ppq >= start_ppq and ppq <= end_ppq then
                            reaper.MIDI_DeleteCC(take, j)
                        end
                    end
                end
                reaper.MIDI_Sort(take)
                local item = reaper.GetMediaItemTake_Item(take)
                if item and reaper.ValidatePtr(item, "MediaItem*") then
                    reaper.UpdateItemInProject(item)
                end
                reaper.Undo_EndBlock2(0, "Notator: Delete hairpin", -1)
                reaper.UpdateArrange()
                state.status_msg = "Hairpin ramp deleted"
            end
        else
            state.status_msg = "Hairpin ramp deleted"
        end
    end
end

function HairpinService.update_hairpin_bounds(state, hp, new_start_qn, new_end_qn)
    if not hp then return end
    if new_start_qn then hp.start_qn = math.max(0.0, new_start_qn) end
    if new_end_qn then hp.end_qn = math.max((hp.start_qn or 0.0) + 0.25, new_end_qn) end
    HairpinService.save_hairpins(state)
end

return HairpinService


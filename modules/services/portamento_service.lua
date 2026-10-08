-- ==============================================================================
-- REAPER Native Notator - Service: PortamentoService
-- Manages Portamento marks connecting two noteheads with acoustic blending via
-- CC64 Hold (50% Note 1 to 75% Note 2) or alternative CCs (CC34, CC5, CC65).
-- Renders diagonal lines directly from notehead to notehead in the score canvas.
-- ==============================================================================

local Constants      = require("constants")
local PortamentoMark = require("classes.portamento_mark")

local PortamentoService = {}

local function pitch_to_name(pitch)
    if not pitch then return "" end
    local names = (Constants and Constants.PITCH_NAMES) or { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
    local oct = math.floor(pitch / 12) - 1
    local name = names[(pitch % 12) + 1] or "C"
    return string.format("%s%d", name, oct)
end

-- ------------------------------------------------------------------------------
-- Helper: Take & Track Resolution
-- ------------------------------------------------------------------------------

local function get_track_from_guid(track_guid, active_tracks_data)
    if not track_guid or track_guid == "" then return nil end
    if active_tracks_data then
        for _, td in ipairs(active_tracks_data) do
            if td.guid == track_guid and td.track and reaper.ValidatePtr(td.track, "MediaTrack*") then
                return td.track
            end
        end
    end
    local trk_cnt = reaper.CountTracks(0)
    for i = 0, trk_cnt - 1 do
        local t = reaper.GetTrack(0, i)
        if t and reaper.GetTrackGUID(t) == track_guid then
            return t
        end
    end
    return nil
end

local function get_all_takes_for_track(track_guid, active_tracks_data)
    local takes = {}
    local trk = get_track_from_guid(track_guid, active_tracks_data)
    if not trk then return takes, nil end

    local item_cnt = reaper.CountTrackMediaItems(trk)
    for i = 0, item_cnt - 1 do
        local it = reaper.GetTrackMediaItem(trk, i)
        if it then
            local tk = reaper.GetActiveTake(it)
            if tk and reaper.TakeIsMIDI(tk) then
                local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                local s_qn = reaper.TimeMap2_timeToQN(0, ipos)
                local e_qn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                table.insert(takes, { take = tk, item = it, start_qn = s_qn, end_qn = e_qn })
            end
        end
    end
    return takes, trk
end

local function find_take_covering_qn(takes_list, qn)
    for _, tinfo in ipairs(takes_list) do
        if qn >= (tinfo.start_qn - 0.05) and qn < (tinfo.end_qn + 0.05) then
            return tinfo.take, tinfo.item
        end
    end
    if #takes_list > 0 then
        return takes_list[1].take, takes_list[1].item
    end
    return nil, nil
end

local function get_track_from_note(n)
    if not n then return nil end
    if n.track and reaper.ValidatePtr(n.track, "MediaTrack*") then
        return n.track
    end
    if n.take and reaper.ValidatePtr(n.take, "MediaItem_Take*") then
        local item = reaper.GetMediaItemTake_Item(n.take)
        if item and reaper.ValidatePtr(item, "MediaItem*") then
            local trk = reaper.GetMediaItem_Track(item)
            if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                return trk
            end
        end
    end
    if n.orig then
        return get_track_from_note(n.orig)
    end
    return nil
end

local function get_item_from_note(n)
    if not n then return nil end
    if n.item and reaper.ValidatePtr(n.item, "MediaItem*") then
        return n.item
    end
    if n.take and reaper.ValidatePtr(n.take, "MediaItem_Take*") then
        local item = reaper.GetMediaItemTake_Item(n.take)
        if item and reaper.ValidatePtr(item, "MediaItem*") then
            return item
        end
    end
    if n.orig then
        return get_item_from_note(n.orig)
    end
    return nil
end

local function get_track_guid_from_note(n)
    if not n then return nil end
    if n.track_guid and n.track_guid ~= "" then
        return n.track_guid
    end
    if n.orig and n.orig.track_guid and n.orig.track_guid ~= "" then
        return n.orig.track_guid
    end
    local trk = get_track_from_note(n)
    if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
        return reaper.GetTrackGUID(trk)
    end
    return nil
end

local function notes_share_same_scope(n1, n2)
    if not n1 or not n2 then return false end

    -- 1. Track boundary check (must belong to the exact same track)
    local trk1 = get_track_from_note(n1)
    local trk2 = get_track_from_note(n2)
    if trk1 and trk2 and trk1 ~= trk2 then
        return false
    end
    local guid1 = get_track_guid_from_note(n1)
    local guid2 = get_track_guid_from_note(n2)
    if guid1 and guid2 and guid1 ~= guid2 then
        return false
    end

    -- 2. Staff boundary check (Grand Staff treble/bass and multi-staff)
    if n1.in_treble ~= nil and n2.in_treble ~= nil and n1.in_treble ~= n2.in_treble then
        return false
    end
    if n1.in_staff ~= nil and n2.in_staff ~= nil and n1.in_staff ~= n2.in_staff then
        return false
    end
    if n1.staff ~= nil and n2.staff ~= nil and n1.staff ~= n2.staff then
        return false
    end

    return true
end

-- ------------------------------------------------------------------------------
-- CC Mode Definitions
-- ------------------------------------------------------------------------------

function PortamentoService.get_cc_number(mode)
    if mode == "cc34" then return 34 end
    if mode == "cc5"  then return 5  end
    if mode == "cc65" then return 65 end
    return 64 -- default CC64 Hold Pedal
end

function PortamentoService.get_cc_on_value(mode)
    if mode == "cc5"  then return 127 end
    if mode == "cc65" then return 127 end
    if mode == "cc34" then return 127 end
    return 127 -- CC64 On
end

function PortamentoService.get_cc_off_value(mode)
    return 0 -- Off for all supported modes
end

function PortamentoService.get_mode_label(mode)
    if mode == "cc34" then return "CC 34 (Portamento Control)" end
    if mode == "cc5"  then return "CC 5 (Portamento Time)" end
    if mode == "cc65" then return "CC 65 (Portamento Switch On/Off)" end
    return "CC 64 (Pedal Hold Blend)"
end

-- ------------------------------------------------------------------------------
-- MIDI CC Synchronization
-- ------------------------------------------------------------------------------

local function get_measure_bounds_for_qn(qn)
    local q = math.max(0.0, qn or 0.0)
    if reaper and reaper.TimeMap2_QNToTime and reaper.TimeMap2_timeToBeats and reaper.TimeMap2_beatsToTime and reaper.TimeMap2_timeToQN then
        local t = reaper.TimeMap2_QNToTime(0, q)
        local _, m_idx = reaper.TimeMap2_timeToBeats(0, t)
        local t_start = reaper.TimeMap2_beatsToTime(0, 0, m_idx)
        local t_end = reaper.TimeMap2_beatsToTime(0, 0, m_idx + 1)
        local m_sqn = reaper.TimeMap2_timeToQN(0, t_start)
        local m_eqn = reaper.TimeMap2_timeToQN(0, t_end)
        return m_sqn, m_eqn, m_idx
    end
    local bpi = 4.0
    local m_idx = math.floor((q + 0.001) / bpi)
    return m_idx * bpi, (m_idx + 1) * bpi, m_idx
end

local function clear_portamento_cc_in_range(take, cc_num, s_ppq, e_ppq, opt_chan)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end
    local _, _, cc_cnt = reaper.MIDI_CountEvts(take)
    for j = (cc_cnt or 0) - 1, 0, -1 do
        local ok, _, _, ppq, _, ch, msg2, _ = reaper.MIDI_GetCC(take, j)
        if ok and msg2 == cc_num and (opt_chan == nil or ch == opt_chan) and ppq >= s_ppq and ppq <= e_ppq then
            reaper.MIDI_DeleteCC(take, j)
        end
    end
end

function PortamentoService.get_effective_timing(state, pm, active_tracks_data)
    local s_qn1 = pm.start_qn1 or 0.0
    local d_qn1 = pm.dur_qn1 or 1.0
    local s_qn2 = pm.start_qn2 or (s_qn1 + d_qn1)
    local d_qn2 = pm.dur_qn2 or 1.0

    -- 1. Check User Ties for arrival (Note 2): if destination note is a tied slave, move back to master note
    if state and state.user_ties then
        local chained2 = true
        local max_hops2 = 16
        while chained2 and max_hops2 > 0 do
            max_hops2 = max_hops2 - 1
            chained2 = false
            for _, tie in ipairs(state.user_ties) do
                if tie.pitch == pm.pitch2 and (tie.chan or 0) == (pm.chan or 0) and math.abs((tie.n2_start_qn or 0) - s_qn2) < 0.05 then
                    if tie.n1_start_qn and tie.n1_start_qn > (s_qn1 + 0.05) then
                        s_qn2 = tie.n1_start_qn
                        d_qn2 = tie.n1_dur or d_qn2
                        chained2 = true
                        break
                    end
                end
            end
        end
    end

    local dest_qn = s_qn2

    -- 2. Check User Ties for departure (Note 1): follow chain forward to tied slave note before dest_qn
    if state and state.user_ties then
        local cur_sqn = s_qn1
        local cur_pitch = pm.pitch1
        local cur_chan = pm.chan or 0
        local chained = true
        local max_hops = 16
        while chained and max_hops > 0 do
            max_hops = max_hops - 1
            chained = false
            for _, tie in ipairs(state.user_ties) do
                if tie.pitch == cur_pitch and (tie.chan or 0) == cur_chan and math.abs((tie.n1_start_qn or 0) - cur_sqn) < 0.05 then
                    if tie.n2_start_qn and tie.n2_start_qn < (dest_qn - 0.05) then
                        cur_sqn = tie.n2_start_qn
                        d_qn1 = tie.n2_dur or d_qn1
                        s_qn1 = cur_sqn
                        chained = true
                        break
                    end
                end
            end
        end
    end

    -- 3. Departure note actual end from active_tracks_data if available
    local n1_end = s_qn1 + d_qn1
    if active_tracks_data then
        for _, td in ipairs(active_tracks_data) do
            if td.notes then
                for _, n in ipairs(td.notes) do
                    if n.pitch == pm.pitch1 and math.abs(n.start_qn - pm.start_qn1) < 0.05 then
                        local cand_end = n.end_qn or (n.start_qn + (n.dur_qn or 1.0))
                        if cand_end > n1_end then
                            n1_end = cand_end
                        end
                        break
                    end
                end
            end
        end
    end

    -- 4. Calculate effective Departure (Note 1) segment:
    -- If Note 1 extends across multiple measures leading up to dest_qn, the departure segment
    -- is the segment in the measure directly preceding dest_qn.
    local eff_s1 = s_qn1
    local eff_d1 = d_qn1

    -- Measure bounds immediately before dest_qn
    local prev_m_sqn, _ = get_measure_bounds_for_qn(dest_qn - 0.01)

    -- If Note 1 started before this measure, but extends into or through it:
    if eff_s1 < (prev_m_sqn - 0.01) and n1_end > (prev_m_sqn + 0.05) then
        eff_s1 = prev_m_sqn
        eff_d1 = math.max(0.25, math.min(n1_end, dest_qn) - eff_s1)
    else
        eff_d1 = math.max(0.25, math.min(n1_end, dest_qn) - eff_s1)
    end

    -- 5. Calculate effective Arrival (Note 2) segment:
    -- Clamped to Note 2's notehead in its starting measure so 0%..100% maps strictly to the arrival notehead!
    local _, m2_eqn = get_measure_bounds_for_qn(s_qn2 + 0.001)
    local m2_max_dur = math.max(0.25, m2_eqn - s_qn2)
    local eff_s2 = s_qn2
    local eff_d2 = math.min(d_qn2, m2_max_dur)

    -- 6. Apply percentage timings
    local s_pct = (pm.start_pct1 or 50) / 100.0
    local e_pct = (pm.end_pct2 or 50) / 100.0
    local hold_start = eff_s1 + s_pct * eff_d1
    local hold_end   = eff_s2 + e_pct * eff_d2

    if hold_end <= hold_start then
        hold_end = hold_start + 0.05
    end

    return hold_start, hold_end, eff_s1, eff_d1
end

function PortamentoService.sync_track_cc(state, track_guid, active_tracks_data, extra_clear_ranges)
    if not track_guid or track_guid == "" then return end
    local takes_list, _ = get_all_takes_for_track(track_guid, active_tracks_data)
    if #takes_list == 0 then return end

    -- 1. Gather all portamento marks for this track
    local track_pms = {}
    for _, pm in ipairs((state and state.portamento_marks) or {}) do
        if pm.track_guid == track_guid then
            table.insert(track_pms, pm)
        end
    end

    -- 2. Build list of all clear intervals
    local clear_intervals = {}
    for _, pm in ipairs(track_pms) do
        local hs, he = PortamentoService.get_effective_timing(state, pm, active_tracks_data)
        local s = math.min(hs, pm.hold_start_qn or hs)
        local e = math.max(he, pm.hold_end_qn or he)
        table.insert(clear_intervals, { s = s - 0.05, e = e + 0.05, chan = (pm.chan or 0) & 0x0F })
        pm.hold_start_qn = hs
        pm.hold_end_qn = he
    end
    for _, r in ipairs(extra_clear_ranges or {}) do
        if r[1] and r[2] then
            table.insert(clear_intervals, { s = r[1] - 0.05, e = r[2] + 0.05, chan = r[3] })
        end
    end

    if #clear_intervals == 0 and #track_pms == 0 then return end

    -- Merge overlapping clear intervals per channel
    local merged_clear = {}
    for _, intv in ipairs(clear_intervals) do
        table.insert(merged_clear, intv)
    end
    table.sort(merged_clear, function(a, b)
        if (a.chan or 0) ~= (b.chan or 0) then return (a.chan or 0) < (b.chan or 0) end
        return a.s < b.s
    end)
    local consolidated = {}
    for _, intv in ipairs(merged_clear) do
        local last = consolidated[#consolidated]
        if last and last.chan == intv.chan and last.e >= intv.s then
            last.e = math.max(last.e, intv.e)
        else
            table.insert(consolidated, { s = intv.s, e = intv.e, chan = intv.chan })
        end
    end

    reaper.Undo_BeginBlock2(0)
    local touched_takes = {}

    -- 3. Clear portamento CCs (64, 34, 5, 65) strictly within the consolidated intervals on this track
    for _, tinfo in ipairs(takes_list) do
        local tk = tinfo.take
        local did_clear = false
        for _, ci in ipairs(consolidated) do
            if not (tinfo.end_qn < ci.s or tinfo.start_qn > ci.e) then
                if not did_clear then
                    reaper.MIDI_DisableSort(tk)
                    did_clear = true
                end
                local s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk, ci.s) + 0.5)
                local e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk, ci.e) + 0.5)
                clear_portamento_cc_in_range(tk, 64, s_ppq, e_ppq, ci.chan)
                clear_portamento_cc_in_range(tk, 34, s_ppq, e_ppq, ci.chan)
                clear_portamento_cc_in_range(tk, 5,  s_ppq, e_ppq, ci.chan)
                clear_portamento_cc_in_range(tk, 65, s_ppq, e_ppq, ci.chan)
                touched_takes[tk] = true
            end
        end
    end

    -- 4. Sort track portamentos by hold_start_qn
    table.sort(track_pms, function(a, b)
        return (a.hold_start_qn or 0) < (b.hold_start_qn or 0)
    end)

    -- 5. Resolve any adjacent / overlapping portamentos on the same channel
    for i = 1, #track_pms do
        local cur = track_pms[i]
        local next_pm = track_pms[i + 1]
        if next_pm and (cur.chan or 0) == (next_pm.chan or 0) then
            if cur.hold_end_qn >= (next_pm.hold_start_qn - 0.01) then
                -- Clamp cur.hold_end_qn to slightly before next_pm.hold_start_qn so CC Off occurs cleanly before CC On
                cur.hold_end_qn = math.max(cur.hold_start_qn + 0.05, next_pm.hold_start_qn - 0.02)
            end
        end
    end

    -- 6. Insert new CC events for all portamentos on this track
    for _, pm in ipairs(track_pms) do
        local cc_num  = PortamentoService.get_cc_number(pm.mode)
        local val_on  = PortamentoService.get_cc_on_value(pm.mode)
        local val_off = PortamentoService.get_cc_off_value(pm.mode)
        local chan    = (pm.chan or 0) & 0x0F

        local tk_start = find_take_covering_qn(takes_list, pm.hold_start_qn)
        if tk_start then
            local s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_start, pm.hold_start_qn) + 0.5)
            reaper.MIDI_InsertCC(tk_start, false, false, s_ppq, 0xB0, chan, cc_num, val_on)
            touched_takes[tk_start] = true
        end

        local tk_end = find_take_covering_qn(takes_list, pm.hold_end_qn)
        if tk_end then
            local e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk_end, pm.hold_end_qn) + 0.5)
            reaper.MIDI_InsertCC(tk_end, false, false, e_ppq, 0xB0, chan, cc_num, val_off)
            touched_takes[tk_end] = true
        end
    end

    for tk, _ in pairs(touched_takes) do
        reaper.MIDI_Sort(tk)
    end
    reaper.Undo_EndBlock2(0, "Update Portamento CC", -1)
    reaper.UpdateArrange()
end

function PortamentoService.apply_cc(state, pm, active_tracks_data)
    if not pm or not pm.track_guid or pm.track_guid == "" then return end
    PortamentoService.sync_track_cc(state, pm.track_guid, active_tracks_data)
end

function PortamentoService.remove_cc_for_portamento(pm, active_tracks_data, state)
    if not pm or not pm.track_guid or pm.track_guid == "" then return end
    local extra = { { pm.hold_start_qn or pm.start_qn1 or 0, pm.hold_end_qn or pm.start_qn2 or 1, (pm.chan or 0) & 0x0F } }
    PortamentoService.sync_track_cc(state or {}, pm.track_guid, active_tracks_data, extra)
end

-- ------------------------------------------------------------------------------
-- Persistence & Take Text Synchronization
-- ------------------------------------------------------------------------------

local function sync_portamentos_to_takes(state)
    local by_guid = {}
    for _, pm in ipairs(state.portamento_marks or {}) do
        if pm.track_guid and pm.track_guid ~= "" then
            by_guid[pm.track_guid] = by_guid[pm.track_guid] or {}
            table.insert(by_guid[pm.track_guid], pm)
        end
    end

    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            local track_pm_list = by_guid[trk_guid] or {}

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
                        if ok and ev_type == 15 and msg:match("^NOTATOR_PORTAMENTO") then
                            table.insert(to_del, t_idx)
                        end
                    end
                    for _, d_idx in ipairs(to_del) do
                        reaper.MIDI_DeleteTextSysexEvt(take, d_idx)
                    end

                    local inserted = false
                    for _, pm in ipairs(track_pm_list) do
                        if pm.start_qn1 >= (i_start_qn - 0.05) and pm.start_qn1 < (i_end_qn + 0.05) then
                            local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, pm.start_qn1) + 0.5)
                            local msg = string.format("NOTATOR_PORTAMENTO|%s|%s|%d|%s|%d|%.4f|%.4f|%s|%d|%.4f|%.4f|%.4f|%.4f|%s|%s|%d|%d",
                                pm.id, pm.track_guid, pm.chan or 0,
                                pm.n1_key or "", pm.pitch1 or 60, pm.start_qn1 or 0, pm.dur_qn1 or 1,
                                pm.n2_key or "", pm.pitch2 or 62, pm.start_qn2 or 1, pm.dur_qn2 or 1,
                                pm.hold_start_qn or 0.5, pm.hold_end_qn or 1.5,
                                pm.mode or "cc64", pm.show_text and "1" or "0",
                                pm.start_pct1 or 50, pm.end_pct2 or 50)
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

function PortamentoService.save_portamentos(state)
    state.portamento_marks = state.portamento_marks or {}
    local parts = {}
    for _, pm in ipairs(state.portamento_marks) do
        local entry = string.format("%s|%s|%d|%s|%d|%.4f|%.4f|%s|%d|%.4f|%.4f|%.4f|%.4f|%s|%s|%d|%d",
            pm.id, pm.track_guid, pm.chan or 0,
            pm.n1_key or "", pm.pitch1 or 60, pm.start_qn1 or 0, pm.dur_qn1 or 1,
            pm.n2_key or "", pm.pitch2 or 62, pm.start_qn2 or 1, pm.dur_qn2 or 1,
            pm.hold_start_qn or 0.5, pm.hold_end_qn or 1.5,
            pm.mode or "cc64", pm.show_text and "1" or "0",
            pm.start_pct1 or 50, pm.end_pct2 or 50)
        table.insert(parts, entry)
    end
    local raw = table.concat(parts, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "portamento_marks", raw)
    sync_portamentos_to_takes(state)
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
end

function PortamentoService.load_portamentos(state)
    state.portamento_marks = {}
    local known = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "portamento_marks")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id = parts[1]
            if id and id ~= "" and not known[id] then
                known[id] = true
                local pm = PortamentoMark.new({
                    id            = id,
                    track_guid    = parts[2],
                    chan          = tonumber(parts[3]) or 0,
                    n1_key        = parts[4],
                    pitch1        = tonumber(parts[5]) or 60,
                    start_qn1     = tonumber(parts[6]) or 0.0,
                    dur_qn1       = tonumber(parts[7]) or 1.0,
                    n2_key        = parts[8],
                    pitch2        = tonumber(parts[9]) or 62,
                    start_qn2     = tonumber(parts[10]) or 1.0,
                    dur_qn2       = tonumber(parts[11]) or 1.0,
                    hold_start_qn = tonumber(parts[12]),
                    hold_end_qn   = tonumber(parts[13]),
                    mode          = (parts[14] and parts[14] ~= "") and parts[14] or "cc64",
                    show_text     = (parts[15] == "1" or parts[15] == "true"),
                    start_pct1    = tonumber(parts[16]) or 50,
                    end_pct2      = tonumber(parts[17]) or 50
                })
                pm:recalculate_timing()
                local trk_exists = false
                if pm.track_guid and pm.track_guid ~= "" then
                    local num_tr = reaper.CountTracks(0)
                    for ti = 0, num_tr - 1 do
                        local t = reaper.GetTrack(0, ti)
                        if t and reaper.GetTrackGUID(t) == pm.track_guid then
                            trk_exists = true
                            break
                        end
                    end
                end
                if trk_exists then
                    table.insert(state.portamento_marks, pm)
                end
            end
        end
    end
end

-- ------------------------------------------------------------------------------
-- Portamento Creation & Toggling
-- ------------------------------------------------------------------------------

local function get_target_notes(state)
    local targets = {}
    if state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            table.insert(targets, sn)
        end
    end
    if #targets == 0 and state.selected_note then
        table.insert(targets, state.selected_note)
    end
    table.sort(targets, function(a, b)
        if math.abs((a.start_qn or 0) - (b.start_qn or 0)) > 0.001 then
            return (a.start_qn or 0) < (b.start_qn or 0)
        end
        return (a.pitch or 0) < (b.pitch or 0)
    end)
    return targets
end

local function find_next_chronological_note(n1, active_tracks_data, state)
    if not n1 then return nil end
    local n1_sqn = n1.start_qn or 0
    local n1_chan = n1.chan or 0
    local n1_pitch = n1.pitch
    local best_note = nil
    local min_dt = 999999.0
    local n1_trk = get_track_from_note(n1)
    local n1_guid = get_track_guid_from_note(n1)

    -- If n1 has user ties, advance search start to after the tie chain of the same pitch
    if state and state.user_ties then
        local cur_sqn = n1_sqn
        local chained = true
        local max_hops = 16
        while chained and max_hops > 0 do
            max_hops = max_hops - 1
            chained = false
            for _, tie in ipairs(state.user_ties) do
                if tie.pitch == n1_pitch and (tie.chan or 0) == n1_chan and math.abs((tie.n1_start_qn or 0) - cur_sqn) < 0.05 then
                    if tie.n2_start_qn and tie.n2_start_qn > cur_sqn then
                        cur_sqn = tie.n2_start_qn
                        n1_sqn = cur_sqn
                        chained = true
                        break
                    end
                end
            end
        end
    end

    if active_tracks_data then
        for _, td in ipairs(active_tracks_data) do
            local is_match = false
            if td.track and n1_trk and td.track == n1_trk then
                is_match = true
            elseif td.guid and n1_guid and td.guid == n1_guid then
                is_match = true
            end

            if is_match and td.notes then
                for _, cand in ipairs(td.notes) do
                    local cand_sqn = cand.start_qn or 0
                    local dt = cand_sqn - n1_sqn
                    if dt > 0.005 and (cand.chan or 0) == n1_chan then
                        -- Enforce same track and staff boundaries
                        if notes_share_same_scope(n1, cand) then
                            if dt < min_dt then
                                min_dt = dt
                                best_note = cand
                            end
                        end
                    end
                end
            end
        end
    end
    return best_note
end

function PortamentoService.toggle_portamento(state, active_tracks_data)
    if not state then return end
    state.portamento_marks = state.portamento_marks or {}

    local targets = get_target_notes(state)
    if #targets == 0 then
        state.status_msg = "Select 1 or 2 notes to toggle Portamento [P]."
        return
    end

    local n1 = targets[1]
    local n2 = targets[2]

    if not n2 then
        n2 = find_next_chronological_note(n1, active_tracks_data, state)
    end

    if not n2 then
        state.status_msg = "No following note found on the same track and staff for Portamento."
        return
    end

    -- Strictly reject cross-track or cross-staff connections
    if not notes_share_same_scope(n1, n2) then
        state.status_msg = "⚠️ Portamento cannot connect notes across different tracks or staves."
        return
    end

    -- Ensure chronological order
    if (n2.start_qn or 0) < (n1.start_qn or 0) then
        n1, n2 = n2, n1
    end

    local trk = get_track_from_note(n1) or get_track_from_note(n2)
    local trk_guid = get_track_guid_from_note(n1) or get_track_guid_from_note(n2) or (trk and reaper.GetTrackGUID(trk)) or ""

    local n1_k = n1.key or (n1.get_key and n1:get_key()) or string.format("%s_%d_%.4f_%d", trk_guid, n1.pitch, n1.start_qn, n1.chan or 0)
    local n2_k = n2.key or (n2.get_key and n2:get_key()) or string.format("%s_%d_%.4f_%d", trk_guid, n2.pitch, n2.start_qn, n2.chan or 0)

    -- Check if portamento already exists between these notes on THIS specific track/staff (Toggle Off)
    local existing_idx = nil
    for idx, pm in ipairs(state.portamento_marks) do
        local is_same_track = false
        if trk_guid ~= "" and pm.track_guid and pm.track_guid ~= "" then
            is_same_track = (pm.track_guid == trk_guid)
        elseif trk_guid == "" and (not pm.track_guid or pm.track_guid == "") then
            is_same_track = true
        end

        local is_same_staff = true
        local n1_staff = n1.staff or n1.in_staff
        if pm.staff ~= nil and n1_staff ~= nil and pm.staff ~= n1_staff then
            is_same_staff = false
        end
        if pm.in_treble ~= nil and n1.in_treble ~= nil and pm.in_treble ~= n1.in_treble then
            is_same_staff = false
        end

        if is_same_track and is_same_staff and (pm.chan or 0) == (n1.chan or 0) then
            if (pm.n1_key and pm.n1_key == n1_k and pm.n2_key and pm.n2_key == n2_k) or
               (math.abs(pm.start_qn1 - n1.start_qn) < 0.02 and pm.pitch1 == n1.pitch and
                math.abs(pm.start_qn2 - n2.start_qn) < 0.02 and pm.pitch2 == n2.pitch) then
                existing_idx = idx
                break
            end
        end
    end

    if existing_idx then
        -- TOGGLE OFF
        local pm = state.portamento_marks[existing_idx]
        PortamentoService.delete_portamento(state, pm.id, active_tracks_data)
        return
    end

    -- TOGGLE ON
    local dur1 = n1.dur_qn or ((n1.end_qn or (n1.start_qn + 1.0)) - n1.start_qn)
    local dur2 = n2.dur_qn or ((n2.end_qn or (n2.start_qn + 1.0)) - n2.start_qn)

    local pm = PortamentoMark.new({
        track_guid = trk_guid,
        chan       = n1.chan or 0,
        staff      = n1.staff or n1.in_staff,
        in_treble  = n1.in_treble,
        n1_key     = n1_k,
        pitch1     = n1.pitch,
        start_qn1  = n1.start_qn,
        dur_qn1    = dur1,
        n2_key     = n2_k,
        pitch2     = n2.pitch,
        start_qn2  = n2.start_qn,
        dur_qn2    = dur2,
        mode       = (state and state.portamento_default_mode) or "cc64",
        start_pct1 = (state and state.portamento_default_start_pct) or 50,
        end_pct2   = (state and state.portamento_default_end_pct) or 50,
        show_text  = (state and state.portamento_default_show_text == true)
    })

    table.insert(state.portamento_marks, pm)
    state.selected_portamento = pm
    local hs, he = PortamentoService.get_effective_timing(state, pm, active_tracks_data)
    pm.hold_start_qn = hs
    pm.hold_end_qn   = he
    PortamentoService.sync_track_cc(state, pm.track_guid, active_tracks_data)
    PortamentoService.save_portamentos(state)

    state.status_msg = string.format("Portamento added [P] (%s -> %s, %s, %d%% -> %d%%)",
        pitch_to_name(n1.pitch), pitch_to_name(n2.pitch),
        PortamentoService.get_mode_label(pm.mode), pm.start_pct1 or 50, pm.end_pct2 or 50)
end

function PortamentoService.delete_portamento(state, port_id, active_tracks_data)
    if not state or not state.portamento_marks then return end
    for idx, pm in ipairs(state.portamento_marks) do
        if pm.id == port_id then
            local old_s = pm.hold_start_qn
            local old_e = pm.hold_end_qn
            local trk_guid = pm.track_guid
            local chan = (pm.chan or 0) & 0x0F
            table.remove(state.portamento_marks, idx)
            if state.selected_portamento and state.selected_portamento.id == port_id then
                state.selected_portamento = nil
            end
            if state.hovered_portamento and state.hovered_portamento.id == port_id then
                state.hovered_portamento = nil
            end
            local extra = {}
            if old_s and old_e then
                table.insert(extra, { old_s, old_e, chan })
            end
            PortamentoService.sync_track_cc(state, trk_guid, active_tracks_data, extra)
            PortamentoService.save_portamentos(state)
            state.status_msg = "Portamento deleted [P]."
            return
        end
    end
end

function PortamentoService.set_mode(state, pm_or_id, new_mode, active_tracks_data)
    if not state or not state.portamento_marks then return end
    local pm = nil
    if type(pm_or_id) == "table" then
        pm = pm_or_id
    else
        for _, p in ipairs(state.portamento_marks) do
            if p.id == pm_or_id then pm = p; break end
        end
    end
    if not pm then return end

    local old_s = pm.hold_start_qn
    local old_e = pm.hold_end_qn
    pm.mode = new_mode or "cc64"

    local hs, he = PortamentoService.get_effective_timing(state, pm, active_tracks_data)
    pm.hold_start_qn = hs
    pm.hold_end_qn   = he

    local extra = {}
    if old_s and old_e then
        table.insert(extra, { old_s, old_e, (pm.chan or 0) & 0x0F })
    end
    PortamentoService.sync_track_cc(state, pm.track_guid, active_tracks_data, extra)
    PortamentoService.save_portamentos(state)
    state.status_msg = string.format("Portamento mode set to: %s", PortamentoService.get_mode_label(pm.mode))
end

function PortamentoService.set_show_text(state, pm_or_id, show_text)
    if not state or not state.portamento_marks then return end
    local pm = nil
    if type(pm_or_id) == "table" then
        pm = pm_or_id
    else
        for _, p in ipairs(state.portamento_marks) do
            if p.id == pm_or_id then pm = p; break end
        end
    end
    if not pm then return end

    pm.show_text = (show_text == true)
    PortamentoService.save_portamentos(state)
    state.status_msg = pm.show_text and "Portamento: 'port.' text shown" or "Portamento: 'port.' text hidden"
end

function PortamentoService.set_timing_pct(state, pm_or_id, start_pct1, end_pct2, active_tracks_data)
    if not state or not state.portamento_marks then return end
    local pm = nil
    if type(pm_or_id) == "table" then
        pm = pm_or_id
    else
        for _, p in ipairs(state.portamento_marks) do
            if p.id == pm_or_id then pm = p; break end
        end
    end
    if not pm then return end

    local old_s = pm.hold_start_qn
    local old_e = pm.hold_end_qn

    if start_pct1 ~= nil then pm.start_pct1 = tonumber(start_pct1) or 50 end
    if end_pct2 ~= nil then pm.end_pct2 = tonumber(end_pct2) or 50 end

    local hs, he = PortamentoService.get_effective_timing(state, pm, active_tracks_data)
    pm.hold_start_qn = hs
    pm.hold_end_qn   = he

    local extra = {}
    if old_s and old_e then
        table.insert(extra, { old_s, old_e, (pm.chan or 0) & 0x0F })
    end

    PortamentoService.sync_track_cc(state, pm.track_guid, active_tracks_data, extra)
    PortamentoService.save_portamentos(state)
    state.status_msg = string.format("Portamento timing: Note 1 @ %d%% -> Note 2 @ %d%%", pm.start_pct1 or 50, pm.end_pct2 or 50)
end

function PortamentoService.remove_portamentos_for_notes(state, notes, active_tracks_data)
    if not state or not state.portamento_marks or not notes or #notes == 0 then return end
    local note_keys = {}
    for _, n in ipairs(notes) do
        local k = n.key or (n.get_key and n:get_key())
        if k then note_keys[k] = true end
    end

    local to_del = {}
    local trk_guids = {}
    local extra_ranges = {}
    for _, pm in ipairs(state.portamento_marks) do
        if note_keys[pm.n1_key] or note_keys[pm.n2_key] then
            table.insert(to_del, pm.id)
            trk_guids[pm.track_guid] = true
            extra_ranges[pm.track_guid] = extra_ranges[pm.track_guid] or {}
            table.insert(extra_ranges[pm.track_guid], { pm.hold_start_qn, pm.hold_end_qn, (pm.chan or 0) & 0x0F })
        end
    end

    for _, pid in ipairs(to_del) do
        for idx = #state.portamento_marks, 1, -1 do
            if state.portamento_marks[idx].id == pid then
                table.remove(state.portamento_marks, idx)
                break
            end
        end
    end

    for tguid, _ in pairs(trk_guids) do
        PortamentoService.sync_track_cc(state, tguid, active_tracks_data, extra_ranges[tguid])
    end
    PortamentoService.save_portamentos(state)
end

function PortamentoService.apply_defaults_to_all(state, active_tracks_data)
    if not state or not state.portamento_marks or #state.portamento_marks == 0 then return 0 end
    local count = #state.portamento_marks
    local def_mode = state.portamento_default_mode or "cc64"
    local def_s    = state.portamento_default_start_pct or 50
    local def_e    = state.portamento_default_end_pct or 50
    local def_txt  = (state.portamento_default_show_text == true)
    local trks = {}
    for _, pm in ipairs(state.portamento_marks) do
        pm.mode = def_mode
        pm.start_pct1 = def_s
        pm.end_pct2 = def_e
        pm.show_text = def_txt
        if pm.track_guid and pm.track_guid ~= "" then
            trks[pm.track_guid] = true
        end
    end
    for trk_guid, _ in pairs(trks) do
        PortamentoService.sync_track_cc(state, trk_guid, active_tracks_data)
    end
    PortamentoService.save_portamentos(state)
    return count
end

-- ------------------------------------------------------------------------------
-- Canvas Rendering: Straight Diagonal Line from Notehead to Notehead
-- ------------------------------------------------------------------------------

local function dist_point_to_line_segment(px, py, x1, y1, x2, y2)
    local l2 = (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)
    if l2 == 0 then
        return math.sqrt((px - x1) * (px - x1) + (py - y1) * (py - y1))
    end
    local t = ((px - x1) * (x2 - x1) + (py - y1) * (y2 - y1)) / l2
    t = math.max(0.0, math.min(1.0, t))
    local proj_x = x1 + t * (x2 - x1)
    local proj_y = y1 + t * (y2 - y1)
    local dx = px - proj_x
    local dy = py - proj_y
    return math.sqrt(dx * dx + dy * dy)
end

local function resolve_effective_portamento_notes(state, pm, all_note_render_by_key)
    if not pm or not all_note_render_by_key then return nil, nil end

    local function note_matches_pm_track(nd)
        if not nd then return false end
        if pm.track_guid and pm.track_guid ~= "" then
            local nd_guid = get_track_guid_from_note(nd)
            if nd_guid and nd_guid ~= pm.track_guid then
                return false
            end
        end
        return true
    end

    local nd1 = all_note_render_by_key[pm.n1_key]
    local nd2 = all_note_render_by_key[pm.n2_key]

    if nd1 and not note_matches_pm_track(nd1) then nd1 = nil end
    if nd2 and not note_matches_pm_track(nd2) then nd2 = nil end

    -- Fallback by pitch and start_qn if key was re-keyed, strictly scoped to matching track
    if not nd1 or not nd2 then
        local best_d1 = 999999
        local best_d2 = 999999
        for _, nd in pairs(all_note_render_by_key) do
            if note_matches_pm_track(nd) and (pm.chan == nil or (nd.chan or (nd.orig and nd.orig.chan) or 0) == (pm.chan or 0)) then
                if not nd1 and nd.pitch == pm.pitch1 then
                    local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                    local d = math.abs(sqn - pm.start_qn1)
                    if d < 0.05 and d < best_d1 then
                        best_d1 = d
                        nd1 = nd
                    end
                end
                if not nd2 and nd.pitch == pm.pitch2 then
                    local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                    local d = math.abs(sqn - pm.start_qn2)
                    if d < 0.05 and d < best_d2 then
                        best_d2 = d
                        nd2 = nd
                    end
                end
            end
        end
    end

    if not nd1 or not nd2 then return nil, nil end

    -- STRICT GUARD: Notes MUST share same track and same staff!
    if not notes_share_same_scope(nd1, nd2) then
        return nil, nil
    end

    local base_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or pm.start_qn1 or 0

    -- =========================================================================
    -- RULE 1 (ARRIVAL / TARGET): Portamento line MUST ARRIVE at the FIRST notehead!
    -- "Die linie darf an der ersten Note ankommen, bei einer verlängerten oder Tie note! Der Port Strich geht nie durch eine Note hindurch!"
    -- If nd2 has multiple barline segments or is a tied slave, move nd2 BACK to the FIRST notehead!
    -- =========================================================================

    -- A. If nd2 has barline segments, pick the FIRST segment (lowest start_qn) OF THIS EXACT NOTE
    if nd2.orig and nd2.is_segment then
        local first_seg = nd2
        local first_sqn = nd2.start_qn or 999999
        for _, nd in pairs(all_note_render_by_key) do
            if notes_share_same_scope(nd, nd2) then
                local is_same_note = (nd.orig and nd2.orig and nd.orig == nd2.orig)
                if not is_same_note and nd2.orig and nd.orig and nd2.orig.take and nd.orig.take and nd2.orig.take == nd.orig.take and nd2.orig.idx and nd.orig.idx and nd2.orig.idx == nd.orig.idx then
                    is_same_note = true
                end
                if is_same_note and nd.is_segment then
                    local sqn = nd.start_qn or 0
                    if sqn < first_sqn and sqn > (base_sqn1 + 0.01) then
                        first_sqn = sqn
                        first_seg = nd
                    end
                end
            end
        end
        nd2 = first_seg
    end

    -- B. If nd2 was tied from an earlier master note (user ties), move nd2 back to the master note
    if state and state.user_ties then
        local cur_sqn2 = nd2.start_qn or (nd2.orig and nd2.orig.start_qn) or pm.start_qn2
        local cur_pitch2 = pm.pitch2
        local cur_chan2 = pm.chan or 0
        local chained2 = true
        local max_hops2 = 16
        while chained2 and max_hops2 > 0 do
            max_hops2 = max_hops2 - 1
            chained2 = false
            for _, tie in ipairs(state.user_ties) do
                if tie.pitch == cur_pitch2 and (tie.chan or 0) == cur_chan2 and math.abs((tie.n2_start_qn or 0) - cur_sqn2) < 0.05 then
                    -- Only step backwards if the master note is strictly AFTER base_sqn1
                    if tie.n1_start_qn and tie.n1_start_qn > (base_sqn1 + 0.05) then
                        local master_nd = all_note_render_by_key[tie.n1_key]
                        if master_nd and not notes_share_same_scope(master_nd, nd2) then
                            master_nd = nil
                        end
                        if not master_nd then
                            for _, nd in pairs(all_note_render_by_key) do
                                if notes_share_same_scope(nd, nd2) and nd.pitch == cur_pitch2 and math.abs((nd.start_qn or (nd.orig and nd.orig.start_qn) or 0) - tie.n1_start_qn) < 0.05 then
                                    master_nd = nd
                                    break
                                end
                            end
                        end
                        if master_nd then
                            nd2 = master_nd
                            cur_sqn2 = master_nd.start_qn or (master_nd.orig and master_nd.orig.start_qn) or tie.n1_start_qn
                            chained2 = true
                            break
                        end
                    end
                end
            end
        end
    end

    local dest_qn = nd2.start_qn or (nd2.orig and nd2.orig.start_qn) or pm.start_qn2 or 999999.0
    if dest_qn <= (base_sqn1 + 0.01) then
        return nil, nil
    end

    -- =========================================================================
    -- RULE 2 (DEPARTURE / START): Portamento line MUST DEPART from the LAST notehead before the slide!
    -- If nd1 has user ties or barline segments, advance FORWARD to the second note / segment before dest_qn.
    -- =========================================================================

    -- A. User ties on nd1: follow chain forward to tied slave note before dest_qn
    if state and state.user_ties then
        local cur_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or pm.start_qn1
        local cur_pitch1 = pm.pitch1
        local cur_chan1 = pm.chan or 0
        local chained1 = true
        local max_hops1 = 16
        while chained1 and max_hops1 > 0 do
            max_hops1 = max_hops1 - 1
            chained1 = false
            for _, tie in ipairs(state.user_ties) do
                if tie.pitch == cur_pitch1 and (tie.chan or 0) == cur_chan1 and math.abs((tie.n1_start_qn or 0) - cur_sqn1) < 0.05 then
                    if tie.n2_start_qn and tie.n2_start_qn < (dest_qn - 0.05) then
                        local slave_nd = all_note_render_by_key[tie.n2_key]
                        if slave_nd and not notes_share_same_scope(slave_nd, nd1) then
                            slave_nd = nil
                        end
                        if not slave_nd then
                            for _, nd in pairs(all_note_render_by_key) do
                                if notes_share_same_scope(nd, nd1) and nd.pitch == cur_pitch1 and math.abs((nd.start_qn or (nd.orig and nd.orig.start_qn) or 0) - tie.n2_start_qn) < 0.05 then
                                    slave_nd = nd
                                    break
                                end
                            end
                        end
                        if slave_nd then
                            nd1 = slave_nd
                            cur_sqn1 = slave_nd.start_qn or (slave_nd.orig and slave_nd.orig.start_qn) or tie.n2_start_qn
                            chained1 = true
                            break
                        else
                            cur_sqn1 = tie.n2_start_qn
                            chained1 = true
                            break
                        end
                    end
                end
            end
        end
    end

    -- B. Barline extension on nd1: find subsequent segment before dest_qn on the same track/staff
    if nd1 and nd1.is_segment then
        local cur_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or pm.start_qn1
        local best_seg = nil
        local best_seg_sqn = cur_sqn1

        for _, nd in pairs(all_note_render_by_key) do
            if notes_share_same_scope(nd, nd1) then
                local is_same_note = (nd1.orig and nd.orig and nd.orig == nd1.orig)
                if not is_same_note and nd.pitch == pm.pitch1 then
                    if nd1.orig and nd.orig and nd1.orig.take == nd.orig.take and nd1.orig.idx == nd.orig.idx then
                        is_same_note = true
                    end
                end

                if is_same_note and nd.is_segment then
                    local seg_sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                    if seg_sqn > (cur_sqn1 + 0.01) and seg_sqn < (dest_qn - 0.05) then
                        if seg_sqn > best_seg_sqn then
                            best_seg_sqn = seg_sqn
                            best_seg = nd
                        end
                    end
                end
            end
        end

        if best_seg then
            nd1 = best_seg
        end
    end

    -- Final strict guard before returning: strictly chronological and same scope
    if not nd1 or not nd2 or not notes_share_same_scope(nd1, nd2) then
        return nil, nil
    end

    local final_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or pm.start_qn1 or 0
    local final_sqn2 = nd2.start_qn or (nd2.orig and nd2.orig.start_qn) or pm.start_qn2 or 0
    if final_sqn2 <= (final_sqn1 + 0.01) then
        return nil, nil
    end

    return nd1, nd2
end

function PortamentoService.draw_portamentos(ctx, draw_list, state, all_note_render_by_key, s, cull_min_x, cull_max_x, cull_min_y, cull_max_y, is_hovered, mouse_x, mouse_y, fonts, opt_note_hovered)
    if not state or not state.portamento_marks or #state.portamento_marks == 0 then return nil end
    local now_hovered_pm = nil

    for _, pm in ipairs(state.portamento_marks) do
        local nd1, nd2 = resolve_effective_portamento_notes(state, pm, all_note_render_by_key)

        if nd1 and nd2 and nd1.nx and nd2.nx and (nd2.nx > nd1.nx + 2.0 * s) and notes_share_same_scope(nd1, nd2) and math.abs(nd1.ny - nd2.ny) <= 100.0 * s then
            local min_x = math.min(nd1.nx, nd2.nx)
            local max_x = math.max(nd1.nx, nd2.nx)

            if max_x >= cull_min_x and min_x <= cull_max_x then
                -- Notehead center offsets with clean, visible gap between notehead and line
                local gap = ((state and state.portamento_default_gap) or 16.0) * s
                local start_x = nd1.nx + gap
                local start_y = nd1.ny
                local end_x   = nd2.nx - gap
                local end_y   = nd2.ny

                if end_x < start_x + 4.0 * s then
                    local total_dx = nd2.nx - nd1.nx
                    local safe_gap = math.max(4.0 * s, (total_dx - 4.0 * s) * 0.5)
                    start_x = nd1.nx + safe_gap
                    end_x   = nd2.nx - safe_gap
                end

                if end_x > start_x then
                    -- Interactive hit testing: Notes ALWAYS have priority!
                    -- If a note is hovered or clicked, portamento hit-testing is bypassed so notes can be selected cleanly.
                    local is_hit = false
                    local note_is_active = (state.hovered_note ~= nil) or (opt_note_hovered ~= nil)
                    if ctx and is_hovered and mouse_x and mouse_y and not note_is_active then
                        local d = dist_point_to_line_segment(mouse_x, mouse_y, start_x, start_y, end_x, end_y)
                        local max_dist = (state.selected_portamento and state.selected_portamento.id == pm.id) and (8.0 * s) or (5.0 * s)

                        if pm.show_text then
                            local mid_x = (start_x + end_x) * 0.5
                            local mid_y = (start_y + end_y) * 0.5 - 26.0 * s
                            if mouse_x >= (mid_x - 14.0 * s) and mouse_x <= (mid_x + 24.0 * s) and
                               mouse_y >= (mid_y - 6.0 * s) and mouse_y <= (mid_y + 18.0 * s) then
                                d = 0
                            end
                        end

                        if d <= max_dist then
                            is_hit = true
                            now_hovered_pm = pm

                            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                            reaper.ImGui_SetTooltip(ctx, string.format("Portamento: %s -> %s\nMode: %s\nLeft-click to select | Right-click for options | Del to delete",
                                pitch_to_name(pm.pitch1), pitch_to_name(pm.pitch2),
                                PortamentoService.get_mode_label(pm.mode)))

                            if reaper.ImGui_IsMouseClicked(ctx, 0) then
                                state:clear_selection()
                                state.selected_portamento = pm
                            end
                            if reaper.ImGui_IsMouseClicked(ctx, 1) then
                                state:clear_selection()
                                state.selected_portamento = pm
                                state.context_portamento = pm
                                reaper.ImGui_OpenPopup(ctx, "portamento_context_popup")
                            end
                        end
                    end

                    local is_sel = (state.selected_portamento and state.selected_portamento.id == pm.id)
                    local col = Constants.COLORS.notehead_black or 0x222222FF
                    if is_sel then
                        col = 0xE67E22FF -- Selected: Gold
                    elseif is_hit then
                        col = 0x3498DBFF -- Hovered: Cyan
                    end

                    local base_th = (state and state.portamento_default_thickness) or 1.6
                    local line_thickness = (is_sel or is_hit) and (base_th * 1.5 * s) or (base_th * s)
                    reaper.ImGui_DrawList_AddLine(draw_list, start_x, start_y, end_x, end_y, col, line_thickness)

                    -- Draw optional "port." text if enabled (elevated cleanly above the line)
                    if pm.show_text then
                        local mid_x = (start_x + end_x) * 0.5
                        local mid_y = (start_y + end_y) * 0.5 - 26.0 * s
                        local f_it = (fonts and fonts.font_italic)
                        if f_it and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                            reaper.ImGui_DrawList_AddTextEx(draw_list, f_it, 13.0 * s, mid_x - 10.0 * s, mid_y, col, "port.")
                        else
                            reaper.ImGui_DrawList_AddText(draw_list, mid_x - 10.0 * s, mid_y, col, "port.")
                        end
                    end
                end
            end
        end
    end

    if is_hovered then
        state.hovered_portamento = now_hovered_pm
    end
    return now_hovered_pm
end

return PortamentoService

-- ==============================================================================
-- REAPER Native Notator - Service: GlissandoService
-- Manages Glissando marks connecting two noteheads with real chromatic
-- MIDI pitch steps in playback and a wavy line in the score canvas.
-- Supports Cross-Staff connections (e.g. Harp/Piano Bass Clef to Treble/Alto Clef).
-- ==============================================================================

local Constants     = require("constants")
local GlissandoMark = require("classes.glissando_mark")

local GlissandoService = {}

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

local function normalize_guid(g)
    if not g or g == "" then return "" end
    return tostring(g):gsub("[{}]", ""):upper():match("^%s*(.-)%s*$")
end

local function get_track_from_guid(track_guid, active_tracks_data)
    if not track_guid or track_guid == "" then return nil end
    local norm_tg = normalize_guid(track_guid)
    if active_tracks_data then
        for _, td in ipairs(active_tracks_data) do
            if normalize_guid(td.guid) == norm_tg and td.track and reaper.ValidatePtr(td.track, "MediaTrack*") then
                return td.track
            end
        end
    end
    local trk_cnt = reaper.CountTracks(0)
    for i = 0, trk_cnt - 1 do
        local t = reaper.GetTrack(0, i)
        if t and normalize_guid(reaper.GetTrackGUID(t)) == norm_tg then
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

-- ------------------------------------------------------------------------------
-- Scope & Boundary Validation
-- ------------------------------------------------------------------------------

local function notes_share_same_track(n1, n2)
    if not n1 or not n2 then return false end
    local trk1 = get_track_from_note(n1)
    local trk2 = get_track_from_note(n2)
    if trk1 and trk2 and trk1 ~= trk2 then
        return false
    end
    local guid1 = get_track_guid_from_note(n1)
    local guid2 = get_track_guid_from_note(n2)
    if guid1 and guid2 and guid1 ~= "" and guid2 ~= "" then
        if normalize_guid(guid1) ~= normalize_guid(guid2) then
            return false
        end
    end
    return true
end

local function notes_share_same_staff(n1, n2, opt_active_tracks_data)
    if not n1 or not n2 then return false end
    if not notes_share_same_track(n1, n2) then return false end

    if n1.in_treble ~= nil and n2.in_treble ~= nil and n1.in_treble ~= n2.in_treble then
        return false
    end
    if n1.in_staff ~= nil and n2.in_staff ~= nil and n1.in_staff ~= n2.in_staff then
        return false
    end
    if n1.staff ~= nil and n2.staff ~= nil and n1.staff ~= n2.staff then
        return false
    end
    -- For Grand Staff / Harp tracks, notes split across Middle C (pitch 60)
    local is_grand = false
    local trk_guid = get_track_guid_from_note(n1)
    local norm_tg = normalize_guid(trk_guid)
    if opt_active_tracks_data and norm_tg ~= "" then
        for _, td in ipairs(opt_active_tracks_data) do
            if normalize_guid(td.guid) == norm_tg then
                is_grand = (td.is_grand or td.is_harp or td.clef == "grand")
                break
            end
        end
    end
    if is_grand and n1.pitch and n2.pitch then
        local t1 = (n1.pitch >= 60)
        local t2 = (n2.pitch >= 60)
        if t1 ~= t2 then return false end
    end
    return true
end

-- ------------------------------------------------------------------------------
-- State Persistence (Project ExtState & Take Sysex Sync)
-- ------------------------------------------------------------------------------

local function sync_glissandos_to_takes(state)
    local by_guid = {}
    for _, gm in ipairs(state.glissando_marks or {}) do
        if gm.track_guid and gm.track_guid ~= "" then
            local ng = normalize_guid(gm.track_guid)
            by_guid[ng] = by_guid[ng] or {}
            table.insert(by_guid[ng], gm)
        end
    end

    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            local track_gm_list = by_guid[normalize_guid(trk_guid)] or {}

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
                        if ok and ev_type == 15 and msg:match("^NOTATOR_GLISSANDO") then
                            table.insert(to_del, t_idx)
                        end
                    end
                    for _, d_idx in ipairs(to_del) do
                        reaper.MIDI_DeleteTextSysexEvt(take, d_idx)
                    end

                    local inserted = false
                    for _, gm in ipairs(track_gm_list) do
                        if gm.start_qn1 >= (i_start_qn - 0.05) and gm.start_qn1 < (i_end_qn + 0.05) then
                            local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, gm.start_qn1) + 0.5)
                            local msg = string.format("NOTATOR_GLISSANDO|%s|%s|%d|%d|%.4f|%.4f|%d|%.4f|%.4f|%d|%s|%s|%s|%s",
                                gm.id, gm.track_guid, gm.chan or 0,
                                gm.pitch1 or 60, gm.start_qn1 or 0, gm.orig_dur1 or 1,
                                gm.pitch2 or 62, gm.start_qn2 or 1, gm.dur_qn2 or 1,
                                gm.start_pct1 or 50, gm.show_text and "1" or "0",
                                gm.cross_staff and "1" or "0", gm.vel_mode or "interpolate",
                                gm.wave_style or "sine")
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

function GlissandoService.save_glissandos(state)
    state.glissando_marks = state.glissando_marks or {}
    local parts = {}
    for _, gm in ipairs(state.glissando_marks) do
        local entry = string.format("%s|%s|%d|%d|%.4f|%.4f|%d|%.4f|%.4f|%d|%s|%s|%s|%s",
            gm.id, gm.track_guid, gm.chan or 0,
            gm.pitch1 or 60, gm.start_qn1 or 0, gm.orig_dur1 or 1,
            gm.pitch2 or 62, gm.start_qn2 or 1, gm.dur_qn2 or 1,
            gm.start_pct1 or 50, gm.show_text and "1" or "0",
            gm.cross_staff and "1" or "0", gm.vel_mode or "interpolate",
            gm.wave_style or "sine")
        table.insert(parts, entry)
    end
    local raw = table.concat(parts, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "glissando_marks", raw)
    sync_glissandos_to_takes(state)
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
end

function GlissandoService.load_glissandos(state)
    state.glissando_marks = {}
    local known = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "glissando_marks")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id = parts[1]
            if id and id ~= "" and not known[id] then
                known[id] = true
                local p1 = tonumber(parts[4]) or 60
                local p2 = tonumber(parts[7]) or 62
                local is_cross = (parts[12] == "1" or parts[12] == "true")
                if not is_cross and p1 and p2 then
                    if (p1 < 60 and p2 >= 60) or (p1 >= 60 and p2 < 60) then
                        is_cross = true
                    end
                end

                local show_txt = (parts[11] == "1" or parts[11] == "true")
                if parts[11] == nil or parts[11] == "" then
                    show_txt = (state and state.glissando_default_show_text ~= false)
                end

                local gm = GlissandoMark.new({
                    id          = id,
                    track_guid  = parts[2],
                    chan        = tonumber(parts[3]) or 0,
                    pitch1      = p1,
                    start_qn1   = tonumber(parts[5]) or 0.0,
                    orig_dur1   = tonumber(parts[6]) or 1.0,
                    dur_qn1     = tonumber(parts[6]) or 1.0,
                    pitch2      = p2,
                    start_qn2   = tonumber(parts[8]) or 1.0,
                    dur_qn2     = tonumber(parts[9]) or 1.0,
                    start_pct1  = tonumber(parts[10]) or 50,
                    show_text   = show_txt,
                    cross_staff = is_cross,
                    vel_mode    = (parts[13] and parts[13] ~= "") and parts[13] or "interpolate",
                    wave_style  = (parts[14] and parts[14] ~= "") and parts[14] or "sine"
                })
                table.insert(state.glissando_marks, gm)
            end
        end
    end

    -- Dual persistence fallback: scan active MIDI takes if ProjExtState was empty/missed marks
    local trk_cnt = reaper.CountTracks(0)
    for ti = 0, trk_cnt - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_cnt = reaper.CountTrackMediaItems(trk)
            for ii = 0, item_cnt - 1 do
                local it = reaper.GetTrackMediaItem(trk, ii)
                local tk = it and reaper.GetActiveTake(it)
                if tk and reaper.TakeIsMIDI(tk) then
                    local _, _, _, text_cnt = reaper.MIDI_CountEvts(tk)
                    for t_idx = 0, text_cnt - 1 do
                        local ok, _, _, _, ev_type, msg = reaper.MIDI_GetTextSysexEvt(tk, t_idx)
                        if ok and ev_type == 15 and msg:match("^NOTATOR_GLISSANDO|") then
                            local g_parts = {}
                            for field in (msg .. "|"):gmatch("([^|]*)|") do table.insert(g_parts, field) end
                            local gid = g_parts[2]
                            if gid and gid ~= "" and not known[gid] then
                                known[gid] = true
                                local p1 = tonumber(g_parts[5]) or 60
                                local p2 = tonumber(g_parts[8]) or 62
                                local is_cross = (g_parts[13] == "1" or g_parts[13] == "true")
                                if not is_cross and p1 and p2 then
                                    if (p1 < 60 and p2 >= 60) or (p1 >= 60 and p2 < 60) then
                                        is_cross = true
                                    end
                                end
                                local show_txt = (g_parts[12] == "1" or g_parts[12] == "true")
                                if g_parts[12] == nil or g_parts[12] == "" then
                                    show_txt = (state and state.glissando_default_show_text ~= false)
                                end
                                local gm = GlissandoMark.new({
                                    id          = gid,
                                    track_guid  = (g_parts[3] and g_parts[3] ~= "") and g_parts[3] or trk_guid,
                                    chan        = tonumber(g_parts[4]) or 0,
                                    pitch1      = p1,
                                    start_qn1   = tonumber(g_parts[6]) or 0.0,
                                    orig_dur1   = tonumber(g_parts[7]) or 1.0,
                                    dur_qn1     = tonumber(g_parts[7]) or 1.0,
                                    pitch2      = p2,
                                    start_qn2   = tonumber(g_parts[9]) or 1.0,
                                    dur_qn2     = tonumber(g_parts[10]) or 1.0,
                                    start_pct1  = tonumber(g_parts[11]) or 50,
                                    show_text   = show_txt,
                                    cross_staff = is_cross,
                                    vel_mode    = (g_parts[14] and g_parts[14] ~= "") and g_parts[14] or "interpolate",
                                    wave_style  = (g_parts[15] and g_parts[15] ~= "") and g_parts[15] or "sine"
                                })
                                table.insert(state.glissando_marks, gm)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ------------------------------------------------------------------------------
-- Target Note Gathering & Search
-- ------------------------------------------------------------------------------

local function get_target_notes(state)
    local targets = {}
    if state and state.selected_notes then
        for _, n in pairs(state.selected_notes) do
            table.insert(targets, n)
        end
        table.sort(targets, function(a, b)
            if math.abs((a.start_qn or 0) - (b.start_qn or 0)) > 0.001 then
                return (a.start_qn or 0) < (b.start_qn or 0)
            end
            return (a.pitch or 0) < (b.pitch or 0)
        end)
    end
    return targets
end

local function find_next_chronological_note(n1, active_tracks_data, state, same_staff_only)
    if not n1 or not active_tracks_data then return nil end
    local n1_sqn = n1.start_qn or 0.0
    local trk_guid = get_track_guid_from_note(n1)

    local best_note = nil
    local min_dist = math.huge

    for _, td in ipairs(active_tracks_data) do
        local is_match = false
        if trk_guid and trk_guid ~= "" and td.guid == trk_guid then
            is_match = true
        elseif td.track and n1.track and td.track == n1.track then
            is_match = true
        end

        if is_match and td.notes then
            for _, n in ipairs(td.notes) do
                local n_sqn = n.start_qn or 0.0
                if n_sqn > (n1_sqn + 0.001) then
                    local staff_match = true
                    if same_staff_only then
                        if n1.in_treble ~= nil and n.in_treble ~= nil and n1.in_treble ~= n.in_treble then
                            staff_match = false
                        end
                        if n1.in_staff ~= nil and n.in_staff ~= nil and n1.in_staff ~= n.in_staff then
                            staff_match = false
                        end
                        if n1.staff ~= nil and n.staff ~= nil and n1.staff ~= n.staff then
                            staff_match = false
                        end
                    end

                    if staff_match then
                        local dist = n_sqn - n1_sqn
                        if dist < min_dist then
                            min_dist = dist
                            best_note = n
                        end
                    end
                end
            end
        end
    end
    return best_note
end

-- ------------------------------------------------------------------------------
-- Chromatic MIDI Step Generation & Take Management
-- ------------------------------------------------------------------------------

local function generate_chromatic_steps_in_take(take, gm, n1, n2)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

    local s1_qn = gm.start_qn1
    local d1_qn = gm.orig_dur1 or gm.dur_qn1 or 1.0
    local s2_qn = gm.start_qn2
    local p1 = gm.pitch1
    local p2 = gm.pitch2
    local chan = gm.chan or 0
    local pct = (gm.start_pct1 or 50) / 100.0

    local t_start_qn = s1_qn + pct * d1_qn
    local t_end_qn = s2_qn
    if t_end_qn <= (t_start_qn + 0.02) then
        t_start_qn = math.max(s1_qn + 0.05, t_end_qn - 0.25)
    end

    local delta_p = p2 - p1
    local K = math.abs(delta_p)
    if K == 0 then return end -- unison, no steps

    local dir = (delta_p > 0) and 1 or -1
    local span_qn = t_end_qn - t_start_qn
    local step_dur_qn = span_qn / K

    local s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, t_start_qn) + 0.5)
    local e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, t_end_qn) + 0.5)
    local total_ppq = e_ppq - s_ppq
    local step_ppq = total_ppq / K

    -- Find Note 1 in take to shorten its MIDI duration and get velocity
    local vel1 = n1.vel or 96
    local vel2 = (n2 and n2.vel) or vel1
    local _, notecnt = reaper.MIDI_CountEvts(take)
    for ni = 0, notecnt - 1 do
        local ok, sel, muted, sppq, eppq, ch, p, v = reaper.MIDI_GetNote(take, ni)
        if ok and p == p1 and ch == chan then
            local n_qn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
            if math.abs(n_qn - s1_qn) <= 0.05 then
                vel1 = v
                -- Shorten Note 1 in take so it ends at first step transition
                local new_eppq = math.floor(s_ppq + step_ppq + 0.5)
                reaper.MIDI_SetNote(take, ni, sel, muted, sppq, new_eppq, ch, p, v, false)
                break
            end
        end
    end

    -- Insert intermediate chromatic notes
    for k = 1, K - 1 do
        local cur_pitch = p1 + k * dir
        local step_start = math.floor(s_ppq + k * step_ppq + 0.5)
        local step_end = math.floor(s_ppq + (k + 1) * step_ppq + 0.5)
        local cur_vel = vel1
        if gm.vel_mode == "interpolate" then
            cur_vel = math.floor(vel1 + (k / K) * (vel2 - vel1) + 0.5)
            cur_vel = math.max(1, math.min(127, cur_vel))
        end

        reaper.MIDI_InsertNote(take, false, false, step_start, step_end, chan, cur_pitch, cur_vel, false)
        local tag = string.format("NOTATOR_GLISS_STEP %s %d %d", gm.id, cur_pitch, chan)
        reaper.MIDI_InsertTextSysexEvt(take, false, false, step_start, 15, tag)
    end

    -- Insert Glissando Master tag at start of Note 1
    local s1_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, s1_qn) + 0.5)
    local master_tag = string.format("NOTATOR_GLISSANDO|%s|%s|%d|%d|%.4f|%.4f|%d|%.4f|%.4f|%d|%s|%s|%s|%s",
        gm.id, gm.track_guid, gm.chan or 0,
        p1, s1_qn, gm.orig_dur1,
        p2, s2_qn, gm.dur_qn2 or 1,
        gm.start_pct1 or 50, gm.show_text and "1" or "0",
        gm.cross_staff and "1" or "0", gm.vel_mode or "interpolate",
        gm.wave_style or "sine")
    reaper.MIDI_InsertTextSysexEvt(take, false, false, s1_ppq, 15, master_tag)

    reaper.MIDI_Sort(take)
end

local function clean_glissando_from_take(take, gliss_id, orig_p1, orig_s1, orig_dur1, chan, orig_p2, orig_s2)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

    -- 1. Delete all NOTATOR_GLISS_STEP notes and tags
    local _, notecnt, _, textcnt = reaper.MIDI_CountEvts(take)
    local notes_to_del = {}
    local step_ppqs = {}

    for ti = textcnt - 1, 0, -1 do
        local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
        if ok and etype == 15 then
            if msg:match("^NOTATOR_GLISS_STEP%s+" .. gliss_id) then
                table.insert(step_ppqs, ppq)
                reaper.MIDI_DeleteTextSysexEvt(take, ti)
            elseif msg:match("^NOTATOR_GLISSANDO|" .. gliss_id) then
                reaper.MIDI_DeleteTextSysexEvt(take, ti)
            end
        end
    end

    local p_min = (orig_p1 and orig_p2) and math.min(orig_p1, orig_p2)
    local p_max = (orig_p1 and orig_p2) and math.max(orig_p1, orig_p2)

    -- Match notes at step positions OR matching pitch/time range
    for ni = notecnt - 1, 0, -1 do
        local ok, _, _, sppq, _, ch, p = reaper.MIDI_GetNote(take, ni)
        if ok and ch == chan then
            local is_step = false
            for _, ppq in ipairs(step_ppqs) do
                if math.abs(sppq - ppq) <= 15 then
                    is_step = true
                    break
                end
            end
            if not is_step and p_min and p_max and p > p_min and p < p_max and orig_s1 and orig_s2 then
                local n_qn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                if n_qn > (orig_s1 + 0.01) and n_qn < (orig_s2 - 0.005) then
                    is_step = true
                end
            end
            if is_step then
                table.insert(notes_to_del, ni)
            end
        end
    end
    for _, ni in ipairs(notes_to_del) do
        reaper.MIDI_DeleteNote(take, ni)
    end

    -- 2. Restore Note 1 to original duration
    local _, updated_notecnt = reaper.MIDI_CountEvts(take)
    for ni = 0, updated_notecnt - 1 do
        local ok, sel, muted, sppq, eppq, ch, p, v = reaper.MIDI_GetNote(take, ni)
        if ok and p == orig_p1 and ch == chan then
            local n_qn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
            if math.abs(n_qn - orig_s1) <= 0.05 then
                local full_end_qn = orig_s1 + (orig_dur1 or 1.0)
                local full_eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, full_end_qn) + 0.5)
                reaper.MIDI_SetNote(take, ni, sel, muted, sppq, full_eppq, ch, p, v, false)
                break
            end
        end
    end

    reaper.MIDI_Sort(take)
end

-- ------------------------------------------------------------------------------
-- Glissando Operations: Toggle, Delete, Remove
-- ------------------------------------------------------------------------------

function GlissandoService.toggle_glissando(state, active_tracks_data)
    if not state then return end
    state.glissando_marks = state.glissando_marks or {}

    local targets = get_target_notes(state)
    if #targets == 0 then
        state.status_msg = "Select 1 or 2 notes to toggle Glissando [G]."
        return
    end

    local n1 = targets[1]
    local n2 = targets[2]
    local is_explicit_two_notes = (n2 ~= nil)

    if not n2 then
        -- 1 Note selected: find next note STRICTLY IN THE SAME STAFF
        n2 = find_next_chronological_note(n1, active_tracks_data, state, true)
    end

    if not n2 then
        state.status_msg = "No following note found on the same track/staff for Glissando."
        return
    end

    -- Ensure chronological order (Note 1 -> Note 2)
    if (n2.start_qn or 0) < (n1.start_qn or 0) then
        n1, n2 = n2, n1
    end

    -- Same Track check (Harps/Pianos with multi-staves are on the same track)
    if not notes_share_same_track(n1, n2) then
        state.status_msg = "⚠️ Glissando cannot connect notes across different instrument tracks."
        return
    end

    -- Check pitch difference
    if n1.pitch == n2.pitch then
        state.status_msg = "⚠️ Glissando requires two different pitches (no unison)."
        return
    end

    local cross_staff = not notes_share_same_staff(n1, n2, active_tracks_data)
    if not cross_staff and n1.pitch and n2.pitch then
        if (n1.pitch < 60 and n2.pitch >= 60) or (n1.pitch >= 60 and n2.pitch < 60) then
            cross_staff = true
        end
    end
    if cross_staff and not is_explicit_two_notes then
        -- Cross-staff is only permitted when user explicitly selects 2 notes
        state.status_msg = "⚠️ Auto-connect requires notes on the same staff. Select both notes explicitly for cross-staff glissando."
        return
    end

    local trk = get_track_from_note(n1) or get_track_from_note(n2)
    local trk_guid = get_track_guid_from_note(n1) or get_track_guid_from_note(n2) or (trk and reaper.GetTrackGUID(trk)) or ""
    local norm_tg = normalize_guid(trk_guid)

    local n1_k = n1.key or (n1.get_key and n1:get_key()) or string.format("%s_%d_%.4f_%d", trk_guid, n1.pitch, n1.start_qn, n1.chan or 0)
    local n2_k = n2.key or (n2.get_key and n2:get_key()) or string.format("%s_%d_%.4f_%d", trk_guid, n2.pitch, n2.start_qn, n2.chan or 0)

    -- Check if Glissando already exists (Toggle Off)
    local existing_idx = nil
    for idx, gm in ipairs(state.glissando_marks) do
        if normalize_guid(gm.track_guid) == norm_tg and (gm.chan or 0) == (n1.chan or 0) then
            if (gm.n1_key == n1_k and gm.n2_key == n2_k) or
               (math.abs(gm.start_qn1 - n1.start_qn) < 0.05 and gm.pitch1 == n1.pitch and
                math.abs(gm.start_qn2 - n2.start_qn) < 0.05 and gm.pitch2 == n2.pitch) then
                existing_idx = idx
                break
            end
        end
    end

    if existing_idx then
        -- TOGGLE OFF: Delete
        local gm = state.glissando_marks[existing_idx]
        GlissandoService.delete_glissando(state, gm.id, active_tracks_data)
        return
    end

    -- Remove conflicting Portamento if present
    if state.portamento_marks and #state.portamento_marks > 0 then
        local PortamentoService = require("services.portamento_service")
        local p_to_del = {}
        for _, pm in ipairs(state.portamento_marks) do
            if pm.track_guid == trk_guid and (pm.chan or 0) == (n1.chan or 0) then
                if math.abs(pm.start_qn1 - n1.start_qn) < 0.02 and pm.pitch1 == n1.pitch then
                    table.insert(p_to_del, pm.id)
                end
            end
        end
        for _, pid in ipairs(p_to_del) do
            PortamentoService.delete_portamento(state, pid, active_tracks_data)
        end
    end

    -- TOGGLE ON: Create Glissando
    local dur1 = n1.dur_qn or ((n1.end_qn or (n1.start_qn + 1.0)) - n1.start_qn)
    local dur2 = n2.dur_qn or ((n2.end_qn or (n2.start_qn + 1.0)) - n2.start_qn)

    local gm = GlissandoMark.new({
        track_guid  = trk_guid,
        chan        = n1.chan or 0,
        n1_key      = n1_k,
        pitch1      = n1.pitch,
        start_qn1   = n1.start_qn,
        dur_qn1     = dur1,
        orig_dur1   = dur1,
        n2_key      = n2_k,
        pitch2      = n2.pitch,
        start_qn2   = n2.start_qn,
        dur_qn2     = dur2,
        cross_staff = cross_staff,
        staff1      = n1.staff or n1.in_staff,
        in_treble1  = n1.in_treble,
        staff2      = n2.staff or n2.in_staff,
        in_treble2  = n2.in_treble,
        start_pct1  = (state and state.glissando_default_start_pct) or 50,
        vel_mode    = (state and state.glissando_default_vel_mode) or "interpolate",
        wave_style  = (state and state.glissando_default_wave_style) or "sine",
        show_text   = (state and state.glissando_default_show_text ~= false)
    })

    -- Generate chromatic steps in take
    local take = n1.take
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        local takes_list = get_all_takes_for_track(trk_guid, active_tracks_data)
        take = find_take_covering_qn(takes_list, n1.start_qn)
    end

    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        generate_chromatic_steps_in_take(take, gm, n1, n2)
        local it = reaper.GetMediaItemTake_Item(take)
        if it and trk then reaper.MarkTrackItemsDirty(trk, it) end
    end

    table.insert(state.glissando_marks, gm)
    GlissandoService.save_glissandos(state)

    state.selected_glissando = gm
    state.status_msg = string.format("Glissando created: %s -> %s (%d semitones%s)",
        pitch_to_name(n1.pitch), pitch_to_name(n2.pitch),
        math.abs(n2.pitch - n1.pitch),
        cross_staff and ", Cross-Staff" or "")

    reaper.UpdateArrange()
    local MidiService = package.loaded["services.midi_service"]
    if MidiService and MidiService.invalidate_cache then
        MidiService.invalidate_cache()
    end
    state.active_tracks_cache = nil
end

function GlissandoService.delete_glissando(state, gliss_id, active_tracks_data)
    if not state or not state.glissando_marks then return end

    local target_idx = nil
    local target_gm = nil
    for idx, gm in ipairs(state.glissando_marks) do
        if gm.id == gliss_id then
            target_idx = idx
            target_gm = gm
            break
        end
    end

    if not target_gm then return end

    local takes_list, trk = get_all_takes_for_track(target_gm.track_guid, active_tracks_data)
    for _, tinfo in ipairs(takes_list) do
        clean_glissando_from_take(tinfo.take, target_gm.id, target_gm.pitch1, target_gm.start_qn1, target_gm.orig_dur1, target_gm.chan or 0, target_gm.pitch2, target_gm.start_qn2)
        if tinfo.item and trk then
            reaper.MarkTrackItemsDirty(trk, tinfo.item)
        end
    end

    table.remove(state.glissando_marks, target_idx)
    if state.selected_glissando and state.selected_glissando.id == gliss_id then
        state.selected_glissando = nil
    end

    GlissandoService.save_glissandos(state)
    state.status_msg = "Glissando removed (chromatic steps cleaned, note duration restored)."

    reaper.UpdateArrange()
    local MidiService = package.loaded["services.midi_service"]
    if MidiService and MidiService.invalidate_cache then
        MidiService.invalidate_cache()
    end
    state.active_tracks_cache = nil
end

function GlissandoService.remove_glissandos_for_notes(state, notes, active_tracks_data)
    if not state or not state.glissando_marks or #state.glissando_marks == 0 then return end
    if not notes or #notes == 0 then return end

    local to_del = {}
    for _, gm in ipairs(state.glissando_marks) do
        for _, n in ipairs(notes) do
            local n_guid = get_track_guid_from_note(n)
            if (not n_guid or n_guid == "" or n_guid == gm.track_guid) and (gm.chan or 0) == (n.chan or 0) then
                if (math.abs(gm.start_qn1 - n.start_qn) < 0.05 and gm.pitch1 == n.pitch) or
                   (math.abs(gm.start_qn2 - n.start_qn) < 0.05 and gm.pitch2 == n.pitch) then
                    table.insert(to_del, gm.id)
                    break
                end
            end
        end
    end

    for _, gid in ipairs(to_del) do
        GlissandoService.delete_glissando(state, gid, active_tracks_data)
    end
end

-- ------------------------------------------------------------------------------
-- Property Modification & Re-sync
-- ------------------------------------------------------------------------------

local function resolve_gm(state, gm_or_id)
    if type(gm_or_id) == "table" then return gm_or_id end
    for _, gm in ipairs(state.glissando_marks or {}) do
        if gm.id == gm_or_id then return gm end
    end
    return nil
end

function GlissandoService.resync_glissando_in_take(state, gm, active_tracks_data)
    if not gm then return end
    local takes_list, trk = get_all_takes_for_track(gm.track_guid, active_tracks_data)
    local take = find_take_covering_qn(takes_list, gm.start_qn1)
    if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        clean_glissando_from_take(take, gm.id, gm.pitch1, gm.start_qn1, gm.orig_dur1, gm.chan or 0, gm.pitch2, gm.start_qn2)
        local n1 = { pitch = gm.pitch1, start_qn = gm.start_qn1, dur_qn = gm.orig_dur1, chan = gm.chan, vel = 96 }
        local n2 = { pitch = gm.pitch2, start_qn = gm.start_qn2, dur_qn = gm.dur_qn2, chan = gm.chan, vel = 96 }
        generate_chromatic_steps_in_take(take, gm, n1, n2)
        local it = reaper.GetMediaItemTake_Item(take)
        if it and trk then reaper.MarkTrackItemsDirty(trk, it) end
    end
end

function GlissandoService.set_timing_pct(state, gm_or_id, start_pct1, active_tracks_data)
    local gm = resolve_gm(state, gm_or_id)
    if not gm then return end
    if start_pct1 then gm.start_pct1 = math.max(0, math.min(100, start_pct1)) end
    GlissandoService.resync_glissando_in_take(state, gm, active_tracks_data)
    GlissandoService.save_glissandos(state)
    reaper.UpdateArrange()
    local MidiService = package.loaded["services.midi_service"]
    if MidiService and MidiService.invalidate_cache then MidiService.invalidate_cache() end
    state.active_tracks_cache = nil
end

function GlissandoService.set_vel_mode(state, gm_or_id, vel_mode, active_tracks_data)
    local gm = resolve_gm(state, gm_or_id)
    if not gm then return end
    gm.vel_mode = vel_mode or "interpolate"
    GlissandoService.resync_glissando_in_take(state, gm, active_tracks_data)
    GlissandoService.save_glissandos(state)
    reaper.UpdateArrange()
    local MidiService = package.loaded["services.midi_service"]
    if MidiService and MidiService.invalidate_cache then MidiService.invalidate_cache() end
    state.active_tracks_cache = nil
end

function GlissandoService.set_wave_style(state, gm_or_id, wave_style)
    local gm = resolve_gm(state, gm_or_id)
    if not gm then return end
    gm.wave_style = wave_style or "sine"
    GlissandoService.save_glissandos(state)
end

function GlissandoService.set_show_text(state, gm_or_id, show_text)
    local gm = resolve_gm(state, gm_or_id)
    if not gm then return end
    gm.show_text = (show_text == true)
    GlissandoService.save_glissandos(state)
end

function GlissandoService.apply_defaults_to_all(state, active_tracks_data)
    if not state or not state.glissando_marks then return 0 end
    local count = #state.glissando_marks
    for _, gm in ipairs(state.glissando_marks) do
        gm.start_pct1  = state.glissando_default_start_pct or 50
        gm.vel_mode    = state.glissando_default_vel_mode or "interpolate"
        gm.wave_style  = state.glissando_default_wave_style or "sine"
        gm.show_text   = (state.glissando_default_show_text == true)
        GlissandoService.resync_glissando_in_take(state, gm, active_tracks_data)
    end
    GlissandoService.save_glissandos(state)
    reaper.UpdateArrange()
    local MidiService = package.loaded["services.midi_service"]
    if MidiService and MidiService.invalidate_cache then MidiService.invalidate_cache() end
    state.active_tracks_cache = nil
    return count
end

-- ------------------------------------------------------------------------------
-- Effective Note Resolution for Canvas Rendering
-- ------------------------------------------------------------------------------

local function resolve_effective_glissando_notes(state, gm, all_note_render_by_key)
    if not gm or not all_note_render_by_key then return nil, nil end

    local function note_matches_gm_track(nd)
        if not nd then return false end
        if gm.track_guid and gm.track_guid ~= "" then
            local nd_guid = get_track_guid_from_note(nd)
            if nd_guid and nd_guid ~= "" then
                if normalize_guid(nd_guid) ~= normalize_guid(gm.track_guid) then
                    return false
                end
            end
        end
        return true
    end

    local nd1 = all_note_render_by_key[gm.n1_key]
    local nd2 = all_note_render_by_key[gm.n2_key]

    if nd1 and not note_matches_gm_track(nd1) then nd1 = nil end
    if nd2 and not note_matches_gm_track(nd2) then nd2 = nil end

    -- Fallback by pitch and start_qn if key was re-keyed, strictly scoped to matching track
    if not nd1 or not nd2 then
        local best_d1 = 999999
        local best_d2 = 999999
        for _, nd in pairs(all_note_render_by_key) do
            if note_matches_gm_track(nd) and (gm.chan == nil or (nd.chan or (nd.orig and nd.orig.chan) or 0) == (gm.chan or 0)) then
                if not nd1 and nd.pitch == gm.pitch1 then
                    local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                    local d = math.abs(sqn - gm.start_qn1)
                    if d < 0.05 and d < best_d1 then
                        best_d1 = d
                        nd1 = nd
                    end
                end
                if not nd2 and nd.pitch == gm.pitch2 then
                    local sqn = nd.start_qn or (nd.orig and nd.orig.start_qn) or 0
                    local d = math.abs(sqn - gm.start_qn2)
                    if d < 0.05 and d < best_d2 then
                        best_d2 = d
                        nd2 = nd
                    end
                end
            end
        end
    end

    if not nd1 or not nd2 then return nil, nil end

    -- STRICT TRACK GUARD: Notes MUST share same track
    if not notes_share_same_track(nd1, nd2) then
        return nil, nil
    end

    -- Automatically detect cross-staff connection
    local is_cross = false
    if nd1.in_treble ~= nil and nd2.in_treble ~= nil and nd1.in_treble ~= nd2.in_treble then
        is_cross = true
    elseif nd1.in_staff ~= nil and nd2.in_staff ~= nil and nd1.in_staff ~= nd2.in_staff then
        is_cross = true
    elseif nd1.staff ~= nil and nd2.staff ~= nil and nd1.staff ~= nd2.staff then
        is_cross = true
    elseif (nd1.pitch and nd2.pitch) and ((nd1.pitch >= 60 and nd2.pitch < 60) or (nd1.pitch < 60 and nd2.pitch >= 60)) then
        is_cross = true
    end
    if is_cross then
        gm.cross_staff = true
    end

    local base_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or gm.start_qn1 or 0

    -- =========================================================================
    -- RULE 1 (ARRIVAL / TARGET): Glissando line MUST ARRIVE at the FIRST notehead!
    -- =========================================================================

    -- A. If nd2 has barline segments, pick the FIRST segment (lowest start_qn) OF THIS EXACT NOTE
    if nd2.orig and nd2.is_segment then
        local first_seg = nd2
        local first_sqn = nd2.start_qn or 999999
        for _, nd in pairs(all_note_render_by_key) do
            if notes_share_same_track(nd, nd2) then
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
        local cur_sqn2 = nd2.start_qn or (nd2.orig and nd2.orig.start_qn) or gm.start_qn2
        local cur_pitch2 = gm.pitch2
        local cur_chan2 = gm.chan or 0
        local chained2 = true
        local max_hops2 = 16
        while chained2 and max_hops2 > 0 do
            max_hops2 = max_hops2 - 1
            chained2 = false
            for _, tie in ipairs(state.user_ties) do
                if tie.pitch == cur_pitch2 and (tie.chan or 0) == cur_chan2 and math.abs((tie.n2_start_qn or 0) - cur_sqn2) < 0.05 then
                    if tie.n1_start_qn and tie.n1_start_qn > (base_sqn1 + 0.05) then
                        local master_nd = all_note_render_by_key[tie.n1_key]
                        if not master_nd then
                            for _, nd in pairs(all_note_render_by_key) do
                                if notes_share_same_track(nd, nd2) and nd.pitch == cur_pitch2 and math.abs((nd.start_qn or (nd.orig and nd.orig.start_qn) or 0) - tie.n1_start_qn) < 0.05 then
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

    local dest_qn = nd2.start_qn or (nd2.orig and nd2.orig.start_qn) or gm.start_qn2 or 999999.0
    if dest_qn <= (base_sqn1 + 0.01) then
        return nil, nil
    end

    -- =========================================================================
    -- RULE 2 (DEPARTURE / START): Glissando line MUST DEPART from the LAST notehead before slide!
    -- =========================================================================

    -- A. User ties on nd1: follow chain forward to tied slave note before dest_qn
    if state and state.user_ties then
        local cur_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or gm.start_qn1
        local cur_pitch1 = gm.pitch1
        local cur_chan1 = gm.chan or 0
        local chained1 = true
        local max_hops1 = 16
        while chained1 and max_hops1 > 0 do
            max_hops1 = max_hops1 - 1
            chained1 = false
            for _, tie in ipairs(state.user_ties) do
                if tie.pitch == cur_pitch1 and (tie.chan or 0) == cur_chan1 and math.abs((tie.n1_start_qn or 0) - cur_sqn1) < 0.05 then
                    if tie.n2_start_qn and tie.n2_start_qn < (dest_qn - 0.05) then
                        local slave_nd = all_note_render_by_key[tie.n2_key]
                        if not slave_nd then
                            for _, nd in pairs(all_note_render_by_key) do
                                if notes_share_same_track(nd, nd1) and nd.pitch == cur_pitch1 and math.abs((nd.start_qn or (nd.orig and nd.orig.start_qn) or 0) - tie.n2_start_qn) < 0.05 then
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

    -- B. Barline extension on nd1: find subsequent segment before dest_qn
    if nd1 and nd1.is_segment then
        local cur_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or gm.start_qn1
        local best_seg = nil
        local best_seg_sqn = cur_sqn1

        for _, nd in pairs(all_note_render_by_key) do
            if notes_share_same_track(nd, nd1) then
                local is_same_note = (nd1.orig and nd.orig and nd.orig == nd1.orig)
                if not is_same_note and nd.pitch == gm.pitch1 then
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

    -- Final strict guard: must share same track
    if not nd1 or not nd2 or not notes_share_same_track(nd1, nd2) then
        return nil, nil
    end

    local final_sqn1 = nd1.start_qn or (nd1.orig and nd1.orig.start_qn) or gm.start_qn1 or 0
    local final_sqn2 = nd2.start_qn or (nd2.orig and nd2.orig.start_qn) or gm.start_qn2 or 0
    if final_sqn2 <= (final_sqn1 + 0.01) then
        return nil, nil
    end

    return nd1, nd2
end

-- ------------------------------------------------------------------------------
-- Score Canvas Rendering: Wavy Line & Badge
-- ------------------------------------------------------------------------------

function GlissandoService.draw_glissandos(ctx, draw_list, state, all_note_render_by_key, s, cull_min_x, cull_max_x, cull_min_y, cull_max_y, is_hovered, mouse_x, mouse_y, fonts, opt_note_hovered)
    if not state or not state.glissando_marks or #state.glissando_marks == 0 then return nil end
    if not all_note_render_by_key then return nil end

    local gap_px = ((state and state.glissando_default_gap) or 12.0) * s
    local base_thickness = ((state and state.glissando_default_thickness) or 1.6) * s
    local now_hovered_gm = nil

    for _, gm in ipairs(state.glissando_marks) do
        local nd1, nd2 = resolve_effective_glissando_notes(state, gm, all_note_render_by_key)

        if nd1 and nd2 and nd1.nx and nd2.nx and (nd2.nx > nd1.nx + 2.0 * s) then
            local x1 = nd1.nx
            local y1 = nd1.ny
            local x2 = nd2.nx
            local y2 = nd2.ny

            local min_x = math.min(x1, x2)
            local max_x = math.max(x1, x2)

            if max_x >= cull_min_x and min_x <= cull_max_x then
                local dx = x2 - x1
                local dy = y2 - y1
                local dist = math.sqrt(dx * dx + dy * dy)

                if dist > 6.0 * s then
                    local ux = dx / dist
                    local uy = dy / dist
                    local nx = -uy
                    local ny = ux

                    -- Upward normal vector (pointing upwards on screen, where screen Y is negative)
                    local up_nx = -uy
                    local up_ny = ux
                    if up_ny > 0 then
                        up_nx = -up_nx
                        up_ny = -up_ny
                    end

                    local eff_gap = gap_px
                    if (dist - 2.0 * eff_gap) < 8.0 * s then
                        eff_gap = math.max(2.0 * s, (dist - 8.0 * s) * 0.5)
                    end

                    local sx = x1 + ux * eff_gap
                    local sy = y1 + uy * eff_gap
                    local ex = x2 - ux * eff_gap
                    local ey = y2 - uy * eff_gap
                    local eff_dist = dist - 2.0 * eff_gap

                    -- Text Badge positioning (above the center of the line)
                    local mid_x = (sx + ex) * 0.5
                    local mid_y = (sy + ey) * 0.5
                    local badge_x = mid_x + up_nx * (13.0 * s)
                    local badge_y = mid_y + up_ny * (13.0 * s)

                    local show_badge = (gm.show_text == true) or (gm.show_text == nil and (state and state.glissando_default_show_text ~= false))

                    -- Hit testing: Notes ALWAYS have priority so note selection is clean
                    local is_hit = false
                    local note_is_active = (state.hovered_note ~= nil) or (opt_note_hovered ~= nil)
                    if ctx and is_hovered and mouse_x and mouse_y and not note_is_active then
                        local to_mx = mouse_x - sx
                        local to_my = mouse_y - sy
                        local proj = to_mx * ux + to_my * uy
                        if proj >= 0 and proj <= eff_dist then
                            local perp = math.abs(to_mx * nx + to_my * ny)
                            if perp <= (8.0 * s) then
                                is_hit = true
                                now_hovered_gm = gm
                            end
                        end

                        if not is_hit and show_badge then
                            if mouse_x >= (badge_x - 16.0 * s) and mouse_x <= (badge_x + 16.0 * s) and
                               mouse_y >= (badge_y - 12.0 * s) and mouse_y <= (badge_y + 12.0 * s) then
                                is_hit = true
                                now_hovered_gm = gm
                            end
                        end
                    end

                    if is_hit and ctx then
                        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                        reaper.ImGui_SetTooltip(ctx, string.format("Glissando: %s -> %s (%d semitones%s)\nLeft-click to select | Right-click for options | Del to delete",
                            pitch_to_name(gm.pitch1), pitch_to_name(gm.pitch2),
                            math.abs(gm.pitch2 - gm.pitch1),
                            gm.cross_staff and ", Cross-Staff" or ""))

                        if reaper.ImGui_IsMouseClicked(ctx, 0) then
                            state:clear_selection()
                            state.selected_glissando = gm
                        end
                        if reaper.ImGui_IsMouseClicked(ctx, 1) then
                            state:clear_selection()
                            state.selected_glissando = gm
                            state.context_glissando = gm
                            reaper.ImGui_OpenPopup(ctx, "glissando_context_popup")
                        end
                    end

                    -- Colors
                    local is_sel = (state.selected_glissando and state.selected_glissando.id == gm.id)
                    local col = (Constants and Constants.COLORS and Constants.COLORS.notehead_black) or 0x222222FF
                    local line_th = base_thickness
                    if is_sel then
                        col = 0xE67E22FF -- Gold / Accent
                        line_th = base_thickness * 1.5
                    elseif is_hit then
                        col = 0x3498DBFF -- Bright Blue
                        line_th = base_thickness * 1.3
                    end

                    -- Generate Line: Sine, Saw, or Straight
                    local style = gm.wave_style or (state and state.glissando_default_wave_style) or "sine"

                    if style == "straight" or style == "line" then
                        reaper.ImGui_DrawList_AddLine(draw_list, sx, sy, ex, ey, col, line_th)
                    else
                        local wavelength = math.max(8.0 * s, 11.0 * s)
                        local amp = 3.0 * s
                        local num_cycles = math.max(1, math.floor(eff_dist / wavelength + 0.5))
                        local lambda_adj = eff_dist / num_cycles
                        local steps = num_cycles * 8

                        local prev_px = sx
                        local prev_py = sy

                        for step = 1, steps do
                            local t = step / steps
                            local d = t * eff_dist
                            local wave_offset = 0.0

                            if style == "saw" then
                                local cycle_pos = (d / lambda_adj) % 1.0
                                if cycle_pos < 0.25 then
                                    wave_offset = amp * (cycle_pos / 0.25)
                                elseif cycle_pos < 0.75 then
                                    wave_offset = amp * (1.0 - (cycle_pos - 0.25) / 0.25)
                                else
                                    wave_offset = amp * (-1.0 + (cycle_pos - 0.75) / 0.25)
                                end
                            else
                                wave_offset = amp * math.sin(2.0 * math.pi * (d / lambda_adj))
                            end

                            local cur_px = sx + ux * d + nx * wave_offset
                            local cur_py = sy + uy * d + ny * wave_offset
                            reaper.ImGui_DrawList_AddLine(draw_list, prev_px, prev_py, cur_px, cur_py, col, line_th)
                            prev_px = cur_px
                            prev_py = cur_py
                        end
                    end

                    -- Text Badge: "gliss." placed above the wavy line
                    if show_badge then
                        local f_it = (fonts and (fonts.font_italic or fonts.italic))
                        if f_it and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                            reaper.ImGui_DrawList_AddTextEx(draw_list, f_it, 13.0 * s, badge_x - 12 * s, badge_y - 6 * s, col, "gliss.")
                        else
                            reaper.ImGui_DrawList_AddText(draw_list, badge_x - 12 * s, badge_y - 6 * s, col, "gliss.")
                        end
                    end
                end
            end
        end
    end

    state.hovered_glissando = now_hovered_gm
    return now_hovered_gm
end

return GlissandoService

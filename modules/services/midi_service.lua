-- ==============================================================================
-- REAPER Native Notator - Service: MidiService
-- REAPER API bridge: tracks, items, takes, notes, synchronization & item management
-- ==============================================================================

local Constants = require("constants")
local MidiNote = require("classes.note")
local MidiItem = require("classes.item")
local DynamicMarker = require("classes.dynamic")

local MidiService = {}

function MidiService.get_active_midi_take()
    local editor = reaper.MIDIEditor_GetActive()
    if editor then
        local take = reaper.MIDIEditor_GetTake(editor)
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
            return take
        end
    end
    
    local num_items = reaper.CountSelectedMediaItems(0)
    for i = 0, num_items - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local take = reaper.GetActiveTake(item)
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
            return take
        end
    end
    
    local sel_track = reaper.GetSelectedTrack(0, 0)
    if sel_track then
        local it_cnt = reaper.CountTrackMediaItems(sel_track)
        for i = 0, it_cnt - 1 do
            local item = reaper.GetTrackMediaItem(sel_track, i)
            local take = reaper.GetActiveTake(item)
            if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
                return take
            end
        end
    end
    return nil
end

local function get_track_from_take(take)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil end
    local item = reaper.GetMediaItemTake_Item(take)
    if item and reaper.ValidatePtr(item, "MediaItem*") then
        return reaper.GetMediaItem_Track(item) or reaper.GetMediaItemTrack(item)
    end
    return nil
end
MidiService.get_track_from_take = get_track_from_take

local function format_track_name_with_idx(trk)
    if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then return nil end
    local tidx = reaper.GetMediaTrackInfo_Value(trk, "IP_TRACKNUMBER")
    local _, tname = reaper.GetTrackName(trk)
    local num_str = (tidx and tidx > 0) and string.format("Track %d", math.floor(tidx)) or "Track"
    if tname and tname ~= "" then
        return string.format("%s: %s", num_str, tname)
    elseif tidx and tidx > 0 then
        return num_str
    end
    return nil
end
MidiService.format_track_name_with_idx = format_track_name_with_idx

-- ==============================================================================
-- Caching system for stage 2 performance optimization
-- ==============================================================================
MidiService._track_cache = {}
MidiService._take_cache = {}
MidiService._project_tracks_cache = nil
MidiService._last_proj_change_cnt = -1
MidiService._last_num_tracks = -1
MidiService._last_sel_sig = ""

function MidiService.invalidate_cache(track_or_guid)
    MidiService._last_proj_change_cnt = -1
    if not track_or_guid then
        MidiService._track_cache = {}
        MidiService._take_cache = {}
        MidiService._project_tracks_cache = nil
    else
        local guid = (type(track_or_guid) == "string") and track_or_guid or (reaper.ValidatePtr(track_or_guid, "MediaTrack*") and reaper.GetTrackGUID(track_or_guid))
        if guid then
            MidiService._track_cache[guid] = nil
        end
    end
end

local function get_take_hash(take)
    local h = nil
    if reaper.APIExists("MIDI_GetHash2") then
        local ok, h2 = reaper.MIDI_GetHash2(take, false)
        if ok and h2 and h2 ~= "" then return h2 end
    elseif reaper.APIExists("MIDI_GetHash") then
        local ok, h1 = reaper.MIDI_GetHash(take, false, "")
        if ok and h1 and h1 ~= "" then return h1 end
    end
    local _, notecnt, cccnt, textcnt = reaper.MIDI_CountEvts(take)
    return string.format("%d_%d_%d", notecnt, cccnt, textcnt)
end

function MidiService.get_project_midi_tracks()
    local proj_change_cnt = reaper.GetProjectStateChangeCount(0)
    local num_tracks = reaper.CountTracks(0)
    local sel_cnt = reaper.CountSelectedTracks(0)
    local sel_sig = tostring(sel_cnt) .. "_" .. tostring(reaper.GetSelectedTrack(0, 0))
    if sel_cnt > 1 then
        for st = 1, sel_cnt - 1 do
            sel_sig = sel_sig .. "_" .. tostring(reaper.GetSelectedTrack(0, st))
        end
    end
    
    if MidiService._project_tracks_cache and
       MidiService._last_proj_change_cnt == proj_change_cnt and
       MidiService._last_num_tracks == num_tracks and
       MidiService._last_sel_sig == sel_sig then
        return MidiService._project_tracks_cache
    end
    
    local tracks = {}
    for t = 0, num_tracks - 1 do
        local track = reaper.GetTrack(0, t)
        local guid = reaper.GetTrackGUID(track)
        local _, name = reaper.GetTrackName(track)
        local col = reaper.GetTrackColor(track)
        
        local num_items = reaper.CountTrackMediaItems(track)
        local midi_item_cnt = 0
        for i = 0, num_items - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            local take = reaper.GetActiveTake(item)
            if take and reaper.TakeIsMIDI(take) then
                midi_item_cnt = midi_item_cnt + 1
            end
        end
        
        if midi_item_cnt > 0 or reaper.IsTrackSelected(track) then
            table.insert(tracks, {
                track = track,
                guid = guid,
                idx = t + 1,
                name = (name and name ~= "") and name or string.format("Track %d", t + 1),
                col = col,
                midi_items = midi_item_cnt
            })
        end
    end
    
    MidiService._project_tracks_cache = tracks
    MidiService._last_proj_change_cnt = proj_change_cnt
    MidiService._last_num_tracks = num_tracks
    MidiService._last_sel_sig = sel_sig
    return tracks
end

function MidiService.find_reaticulate_art_for_id(bank, art_id)
    if not bank or not bank.articulations then return nil end
    local id = (art_id or ""):lower()
    if id == "" or id == "none" then return nil end
    
    -- Normalize target id
    if id:find("staccatiss") or id:find("wedge") then
        id = "staccatissimo"
    elseif id:find("stacc") or id:find("dig") then
        id = "staccato"
    elseif id:find("marc") then
        id = "marcato"
    elseif id:find("tenuto") or id == "ten" then
        id = "tenuto"
    elseif id:find("accent") or id == "acc" then
        id = "accent"
    elseif id:find("harm") or id:find("flag") then
        id = "harmonic"
    end
    
    -- 1. Exact match on name
    for _, a in ipairs(bank.articulations) do
        if a.name and a.name:lower() == id then return a end
    end

    -- Special handling for staccato with prioritized tiers:
    -- Tier 1: Explicit 'dig' / 'staccato dig' (e.g. Double Basses in Spitfire SSO / SSS / SCS)
    -- Tier 2: Explicit 'staccato' / 'stacc' (excluding staccatissimo, harmonics, sordino)
    -- Tier 3: Fallback duration names for libraries without a staccato patch (e.g. Spitfire Celli/Violins 'Short 0.5')
    if id == "staccato" then
        -- Tier 1: Dig / Staccato Dig
        for _, a in ipairs(bank.articulations) do
            local aname = (a.name or ""):lower()
            local aicon = (a.icon or ""):lower()
            local is_harmonic = aname:find("harm") or aname:find("flag") or aicon:find("harm") or aicon:find("flag")
            local is_sordino = aname:find("sord") or aicon:find("sord") or aname:find("%f[%a]cs%f[%A]") or aicon:find("con%-sord")
            if not is_harmonic and not is_sordino then
                if aname:find("dig") or aicon:find("dig") then
                    return a
                end
            end
        end
        -- Tier 2: Explicit Staccato
        for _, a in ipairs(bank.articulations) do
            local aname = (a.name or ""):lower()
            local aicon = (a.icon or ""):lower()
            local is_harmonic = aname:find("harm") or aname:find("flag") or aicon:find("harm") or aicon:find("flag")
            local is_sordino = aname:find("sord") or aicon:find("sord") or aname:find("%f[%a]cs%f[%A]") or aicon:find("con%-sord")
            if not is_harmonic and not is_sordino then
                if (aname:find("stacc") and not aname:find("staccatiss"))
                    or (aicon:find("stacc") and not aicon:find("staccatiss")) then
                    return a
                end
            end
        end
        -- Tier 3: Fallback to Short 0.5s for Spitfire libraries without staccato/dig
        for _, a in ipairs(bank.articulations) do
            local aname = (a.name or ""):lower()
            local aicon = (a.icon or ""):lower()
            local is_harmonic = aname:find("harm") or aname:find("flag") or aicon:find("harm") or aicon:find("flag")
            local is_sordino = aname:find("sord") or aicon:find("sord") or aname:find("%f[%a]cs%f[%A]") or aicon:find("con%-sord")
            if not is_harmonic and not is_sordino then
                if aname:find("short 0%.5") or aname:find("short 0%.25") or aname:find("short 0%.3")
                    or aname:find("short 0%.4") or aname:find("short.-0%.5") then
                    return a
                end
            end
        end
    end

    -- 2. Strict keyword & icon matching for other articulations
    for _, a in ipairs(bank.articulations) do
        local aname = (a.name or ""):lower()
        local aicon = (a.icon or ""):lower()
        local is_harmonic = aname:find("harm") or aname:find("flag") or aicon:find("harm") or aicon:find("flag")
        local is_sordino = aname:find("sord") or aicon:find("sord") or aname:find("%f[%a]cs%f[%A]") or aicon:find("con%-sord")
        
        if id == "harmonic" then
            if is_harmonic then
                return a
            end
        elseif id == "staccatissimo" then
            if not is_harmonic and not is_sordino then
                if aname:find("staccatiss") or aicon:find("staccatiss") or aname:find("spicc") or aicon:find("spicc") then
                    return a
                end
            end
        elseif id == "marcato" then
            if not is_harmonic then
                if aname:find("marc") or aicon:find("marc") then
                    return a
                end
            end
        elseif id == "tenuto" then
            -- Strict match on tenuto, NEVER fallback to long, harmonic, sordino, or short 0.5s!
            -- Supports standard 'tenuto', plus Spitfire SSO / Albion 'Short 1.0'
            if not is_harmonic and not is_sordino and not aname:find("0%.5") and not aname:find("0%.25") then
                if aname:find("tenuto") or aicon:find("tenuto") or aname:find("short 1%.0") or aname:find("short 1s") then
                    return a
                end
            end
        elseif id == "accent" then
            if not is_harmonic then
                if aname:find("accent") or aicon:find("accent") then
                    return a
                end
            end
        elseif id == "legato" or id == "slur" then
            if not is_harmonic then
                if aname:find("legato") or aicon:find("legato") or aname:find("slur") or aicon:find("slur") then
                    return a
                end
            end
        end
    end

    -- Fallback for legato/slur on instruments without a dedicated legato articulation (User Requirement)
    if id == "legato" or id == "slur" then
        -- Tier 1: Look for standard long / sustain patches (excluding harmonics, sordino, short, and tremolo)
        for _, a in ipairs(bank.articulations) do
            local aname = (a.name or ""):lower()
            local aicon = (a.icon or ""):lower()
            local is_harmonic = aname:find("harm") or aname:find("flag") or aicon:find("harm") or aicon:find("flag")
            local is_sordino = aname:find("sord") or aicon:find("sord") or aname:find("%f[%a]cs%f[%A]") or aicon:find("con%-sord")
            local is_short = aname:find("short") or aname:find("stacc") or aname:find("spicc") or aname:find("pizz") or aname:find("trem")
            if not is_harmonic and not is_sordino and not is_short then
                if aname:find("long") or aicon:find("long") or aname:find("sustain") or aicon:find("sustain") or aname:find("norm") then
                    return a
                end
            end
        end
        -- Tier 2: First non-momentary / non-tremolo articulation in bank
        for _, a in ipairs(bank.articulations) do
            local aname = (a.name or ""):lower()
            local is_mom = aname:find("stacc") or aname:find("spicc") or aname:find("marc") or aname:find("tenuto")
                or aname:find("accent") or aname:find("harm") or aname:find("trem") or aname:find("pizz")
            if not is_mom then
                return a
            end
        end
    end
    return nil
end

function MidiService.art_id_from_reaticulate_art(art_def)
    if not art_def then return nil end
    local aname = (art_def.name or ""):lower()
    local aicon = (art_def.icon or ""):lower()
    
    -- Check harmonics / flageolets FIRST so short harmonics / staccato harmonics are detected as flageolet and NEVER as staccato!
    if aname:find("harm") or aname:find("flag") or aicon:find("harm") or aicon:find("flag") then
        return "harmonic"
    end
    
    -- Staccatissimo / Spiccato
    if aname:find("staccatiss") or aicon:find("staccatiss") or aname:find("spicc") or aicon:find("spicc") then
        return "staccatissimo"
    end
    
    -- Standard Staccato (including Spitfire SSO / Albion Short 0.5 / Short 0.5s / Staccato Dig)
    if (aname:find("stacc") and not aname:find("staccatiss"))
        or (aicon:find("stacc") and not aicon:find("staccatiss"))
        or aname:find("dig") or aicon:find("dig")
        or aname:find("short 0%.5") or aname:find("short 0%.25") or aname:find("short 0%.3")
        or aname:find("short 0%.4") or aname:find("short.-0%.5") then
        return "staccato"
    end
    
    if aname:find("marc") or aicon:find("marc") then
        return "marcato"
    elseif ((aname:find("tenuto") or aicon:find("tenuto")) and not aname:find("0%.5") and not aname:find("0%.25"))
        or aname:find("short 1%.0") or aname:find("short 1s") then
        return "tenuto"
    elseif aname:find("accent") or aicon:find("accent") then
        return "accent"
    elseif aname:find("legato") or aicon:find("legato") or aname:find("slur") or aicon:find("slur") then
        return "legato"
    end
    return nil
end

function MidiService.is_momentary_articulation(art_id)
    if not art_id or art_id == "" or art_id == "none" then return false end
    local a = tostring(art_id):lower()
    return a:find("stacc") ~= nil or a:find("dig") ~= nil or a:find("0%.5") ~= nil
        or a:find("marc") ~= nil or a:find("tenuto") ~= nil
        or a:find("accent") ~= nil or a:find("spicc") ~= nil or a:find("wedge") ~= nil
        or a:find("harm") ~= nil or a:find("flag") ~= nil
end

local function parse_single_take_midi(take, item, track, i, pos, len, start_qn, end_qn, item_col, iname)
    local item_obj = MidiItem.new({
        item = item,
        take = take,
        idx = i,
        pos = pos,
        len = len,
        start_qn = start_qn,
        end_qn = end_qn,
        col = item_col,
        name = iname
    })
    
    -- Read key signature & time signature from item P_EXT
    if item and reaper.ValidatePtr(item, "MediaItem*") then
        local ok_k, k_ext = reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_key_sig", "", false)
        if ok_k and k_ext and k_ext ~= "" then
            local idx_s, mode_s = k_ext:match("^(%-?%d+)|?([%a%d_]*)")
            if idx_s then
                local kidx = tonumber(idx_s)
                item_obj.key_sig = { idx = kidx, key_idx = kidx, mode = (mode_s and mode_s ~= "") and mode_s or "major" }
            end
        end
        local ok_t, t_ext = reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_time_sig", "", false)
        if ok_t and t_ext and t_ext ~= "" then
            local num_s, den_s = t_ext:match("^(%d+)|(%d+)")
            if num_s and den_s then
                item_obj.time_sig = { num = tonumber(num_s), denom = tonumber(den_s) }
            end
        end
    end
    
    local take_notes = {}
    local take_dynamics = {}
    local take_articulations = {}
    
    -- Read articulations, stem directions & staff assignments (Type 15 Sysex/Text)
    local note_arts_list = {}
    local note_stems_list = {}
    local note_staffs_list = {}
    local note_arpeggios_list = {}
    local chase_events_list = {}
    local tie_masters = {}
    local tie_slaves = {}
    local gliss_steps = {}
    local gliss_masters = {}
    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
    for ti = 0, text_cnt - 1 do
        local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
        if ok and etype == 15 then
            local p, ch, art = msg:match("NOTE%s+(%d+)%s+(%d+)%s+a%s+([%a%d_]+)")
            if p and art then
                table.insert(note_arts_list, { ppq = ppq, pitch = tonumber(p), chan = tonumber(ch) or 0, art = art })
                if art:lower():find("arpegg") or art:lower():find("arp") then
                    table.insert(note_arpeggios_list, { ppq = ppq, dir = art:lower():find("down") and "down" or "up" })
                end
            end
            local sp, sch, sdir = msg:match("NOTE%s+(%d+)%s+(%d+)%s+stem%s+([%a]+)")
            if sp and sdir then
                sdir = sdir:lower()
                if sdir == "up" or sdir == "down" then
                    table.insert(note_stems_list, { ppq = ppq, pitch = tonumber(sp), chan = tonumber(sch) or 0, stem_dir = sdir })
                end
            end
            local stp, stch, sstf = msg:match("NOTE%s+(%d+)%s+(%d+)%s+staff%s+([%a]+)")
            if stp and sstf then
                sstf = sstf:lower()
                if sstf == "treble" or sstf == "bass" then
                    table.insert(note_staffs_list, { ppq = ppq, pitch = tonumber(stp), chan = tonumber(stch) or 0, staff = sstf })
                end
            end
            local arp_dir = msg:match("NOTATOR_ARPEGGIO%s*([%a]*)")
            if arp_dir then
                table.insert(note_arpeggios_list, { ppq = ppq, dir = (arp_dir ~= "" and arp_dir) or "up" })
            end
            local ch_c, pc_c = msg:match("NOTATOR_CHASE%s+(%d+)%s+(%d+)")
            if ch_c and pc_c then
                table.insert(chase_events_list, { ppq = ppq, chan = tonumber(ch_c) or 0, pc = tonumber(pc_c) })
            end

            -- Extract ties: master note keeps orig visual dur; slave note is preserved visually even if held as single note in REAPER take
            local t_id, t_chan, tp, t_s1, t_d1, t_s2, t_d2, t_vel = msg:match("^NOTATOR_TIE%s+([%w_]+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*(%d*)")
            if t_id then
                local p_num = tonumber(tp)
                local ch_num = tonumber(t_chan) or 0
                local s1_qn = tonumber(t_s1)
                local d1_qn = tonumber(t_d1)
                local s2_qn = tonumber(t_s2)
                local d2_qn = tonumber(t_d2)
                local vel_num = (t_vel and t_vel ~= "") and tonumber(t_vel) or 96
                local s1_ppq = ppq -- Use the exact event PPQ where master tag was inserted
                local s2_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, s2_qn) + 0.5)
                table.insert(tie_masters, { id = t_id, pitch = p_num, chan = ch_num, sppq = s1_ppq, orig_dur = d1_qn, s_qn = s1_qn, s2_qn = s2_qn, d2_qn = d2_qn, vel = vel_num })
                table.insert(tie_slaves, { id = t_id, pitch = p_num, chan = ch_num, sppq = s2_ppq, orig_dur = d2_qn, s_qn = s2_qn, vel = vel_num })
            end
            local ts_id, ts_chan, tsp, ts_s2, ts_d2 = msg:match("^NOTATOR_TIE_SLAVE%s+([%w_]+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)")
            if ts_id then
                local p_num = tonumber(tsp)
                local ch_num = tonumber(ts_chan) or 0
                local s2_qn = tonumber(ts_s2)
                local d2_qn = tonumber(ts_d2)
                local s2_ppq = ppq -- Use the exact event PPQ where slave tag was inserted
                table.insert(tie_slaves, { id = ts_id, pitch = p_num, chan = ch_num, sppq = s2_ppq, orig_dur = d2_qn, s_qn = s2_qn })
            end

            -- Extract glissando steps & masters:
            local g_step_id = msg:match("^NOTATOR_GLISS_STEP%s+([%w_]+)")
            if g_step_id then
                table.insert(gliss_steps, { ppq = ppq, id = g_step_id })
            end
            if msg:match("^NOTATOR_GLISSANDO|") then
                local g_parts = {}
                for field in (msg .. "|"):gmatch("([^|]*)|") do table.insert(g_parts, field) end
                local g_id = g_parts[2]
                if g_id and g_id ~= "" then
                    local ch_num  = tonumber(g_parts[4]) or 0
                    local p1_num  = tonumber(g_parts[5]) or 60
                    local s1_qn   = tonumber(g_parts[6]) or 0.0
                    local d1_orig = tonumber(g_parts[7]) or 1.0
                    local p2_num  = tonumber(g_parts[8])
                    local s2_qn   = tonumber(g_parts[9])
                    local d2_qn   = tonumber(g_parts[10])
                    local pct_num = tonumber(g_parts[11]) or 50
                    table.insert(gliss_masters, {
                        id = g_id, pitch = p1_num, chan = ch_num, s_qn = s1_qn, orig_dur = d1_orig,
                        pitch2 = p2_num, s2_qn = s2_qn, d2_qn = d2_qn, pct = pct_num
                    })
                end
            end
            
            -- Extract key signatures (NOTATOR_KEY_SIG <key_idx> <mode> or native key <val>)
            local idx_s, mode_s = msg:match("NOTATOR_KEY_SIG%s+(%-?%d+)%s*([%a%d_]*)")
            if not idx_s then
                local nat_idx = msg:match("^key%s+(%-?%d+)")
                if nat_idx then
                    idx_s = nat_idx
                    mode_s = "major"
                end
            end
            if idx_s then
                item_obj.key_sig_events = item_obj.key_sig_events or {}
                table.insert(item_obj.key_sig_events, { ppq = ppq, key_idx = tonumber(idx_s), idx = tonumber(idx_s), mode = (mode_s and mode_s ~= "") and mode_s or "major" })
            end
            
            -- Extract time signatures (NOTATOR_TIME_SIG <num> <denom> or native time <num>/<denom>)
            local ts_num_s, ts_den_s = msg:match("NOTATOR_TIME_SIG%s+(%d+)%s+(%d+)")
            if not ts_num_s then
                ts_num_s, ts_den_s = msg:match("^time%s+(%d+)/(%d+)")
            end
            if ts_num_s and ts_den_s then
                item_obj.time_sig_events = item_obj.time_sig_events or {}
                table.insert(item_obj.time_sig_events, { ppq = ppq, num = tonumber(ts_num_s), denom = tonumber(ts_den_s) })
            end
        end
    end
    
    -- Dual persistence fallback: read ties from ProjExtState so tied notes are never dropped
    local _, raw_user_ties = reaper.GetProjExtState(0, "REAPER_Notator", "user_ties")
    if raw_user_ties and raw_user_ties ~= "" then
        local trk_guid = track and reaper.GetTrackGUID(track)
        for entry in raw_user_ties:gmatch("([^;]+)") do
            local p = {}
            for field in (entry .. "|"):gmatch("([^|]*)|") do table.insert(p, field) end
            if p[1] and p[1] ~= "" and (p[2] == "" or not trk_guid or p[2] == trk_guid) then
                local t_id = p[1]
                local t_ch = tonumber(p[3]) or 0
                local t_pitch = tonumber(p[4]) or 60
                local t_s1_qn = tonumber(p[5]) or 0.0
                local t_d1_qn = tonumber(p[6]) or 1.0
                local t_s2_qn = tonumber(p[7]) or 1.0
                local t_d2_qn = tonumber(p[8]) or 1.0
                local t_vel = tonumber(p[9]) or 96
                local s1_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, t_s1_qn) + 0.5)
                local s2_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, t_s2_qn) + 0.5)
                
                local already_have = false
                for _, tm in ipairs(tie_masters) do
                    if tm.id == t_id then already_have = true; break end
                end
                if not already_have then
                    table.insert(tie_masters, { id = t_id, pitch = t_pitch, chan = t_ch, sppq = s1_ppq, orig_dur = t_d1_qn, s_qn = t_s1_qn, s2_qn = t_s2_qn, d2_qn = t_d2_qn, vel = t_vel })
                    table.insert(tie_slaves, { id = t_id, pitch = t_pitch, chan = t_ch, sppq = s2_ppq, orig_dur = t_d2_qn, s_qn = t_s2_qn, vel = t_vel })
                end
            end
        end
    end
    
    -- Dual persistence fallback: read glissandos from ProjExtState so chromatic steps are filtered even if take tags were modified
    local _, raw_user_gliss = reaper.GetProjExtState(0, "REAPER_Notator", "glissando_marks")
    if raw_user_gliss and raw_user_gliss ~= "" then
        local trk_guid = track and reaper.GetTrackGUID(track)
        for entry in raw_user_gliss:gmatch("([^;]+)") do
            local gp = {}
            for field in (entry .. "|"):gmatch("([^|]*)|") do table.insert(gp, field) end
            local gid = gp[1]
            local g_guid = gp[2]
            if gid and gid ~= "" and (g_guid == "" or not trk_guid or g_guid == trk_guid) then
                local g_ch  = tonumber(gp[3]) or 0
                local g_p1  = tonumber(gp[4]) or 60
                local g_s1  = tonumber(gp[5]) or 0.0
                local g_d1  = tonumber(gp[6]) or 1.0
                local g_p2  = tonumber(gp[7])
                local g_s2  = tonumber(gp[8])
                local g_d2  = tonumber(gp[9])
                local g_pct = tonumber(gp[10]) or 50

                local already_have = false
                for _, gm in ipairs(gliss_masters) do
                    if gm.id == gid then already_have = true; break end
                end
                if not already_have then
                    table.insert(gliss_masters, {
                        id = gid, pitch = g_p1, chan = g_ch, s_qn = g_s1, orig_dur = g_d1,
                        pitch2 = g_p2, s2_qn = g_s2, d2_qn = g_d2, pct = g_pct
                    })
                end
            end
        end
    end
    
    local function find_tie_master(p, ch, sppq, opt_sqn)
        for _, tm in ipairs(tie_masters) do
            if tm.pitch == p and tm.chan == ch then
                if math.abs(tm.sppq - sppq) <= 120 then
                    return tm
                elseif opt_sqn and tm.s_qn and math.abs(tm.s_qn - opt_sqn) <= 0.15 then
                    return tm
                end
            end
        end
        return nil
    end
    local function find_tie_slave(p, ch, sppq, opt_sqn)
        for _, ts in ipairs(tie_slaves) do
            if ts.pitch == p and ts.chan == ch then
                if math.abs(ts.sppq - sppq) <= 120 then
                    return ts
                elseif opt_sqn and ts.s_qn and math.abs(ts.s_qn - opt_sqn) <= 0.15 then
                    return ts
                end
            end
        end
        return nil
    end

    -- If item_obj.key_sig was not populated via P_EXT, initialize from first key event
    if not item_obj.key_sig and item_obj.key_sig_events and #item_obj.key_sig_events > 0 then
        local first_k = item_obj.key_sig_events[1]
        item_obj.key_sig = { idx = first_k.key_idx, key_idx = first_k.key_idx, mode = first_k.mode }
    end
    if not item_obj.time_sig and item_obj.time_sig_events and #item_obj.time_sig_events > 0 then
        local first_t = item_obj.time_sig_events[1]
        item_obj.time_sig = { num = first_t.num, denom = first_t.denom }
    end
    
    -- Read all notes with strict respect to item boundaries & loops
    local loop_src = reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC") ~= 0
    local src = reaper.GetMediaItemTake_Source(take)
    local src_len_qn = 0
    if src then
        local slen, is_qn = reaper.GetMediaSourceLength(src)
        if is_qn then src_len_qn = slen
        else src_len_qn = reaper.TimeMap2_timeToQN(0, pos + slen) - start_qn end
    end
    if src_len_qn <= 0.01 then src_len_qn = end_qn - start_qn end
    
    local num_loops = 1
    if loop_src and src_len_qn > 0 and (end_qn - start_qn) > (src_len_qn + 0.05) then
        num_loops = math.ceil((end_qn - start_qn) / src_len_qn)
    end
    
    local _, notecnt = reaper.MIDI_CountEvts(take)
    for loop_idx = 0, num_loops - 1 do
        local loop_offset_qn = loop_idx * src_len_qn
        for ni = 0, notecnt - 1 do
            local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
            local base_sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
            local base_eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
            
            -- Absolute project position with loop offset
            local n_sqn = base_sqn + loop_offset_qn
            local n_eqn = base_eqn + loop_offset_qn
            
            local is_gliss_step = false
            for _, gs in ipairs(gliss_steps) do
                if math.abs(gs.ppq - sppq) <= 15 then
                    is_gliss_step = true
                    break
                end
            end
            if not is_gliss_step then
                for _, gm in ipairs(gliss_masters) do
                    if (gm.chan == nil or gm.chan == chan) and gm.pitch2 and gm.s2_qn then
                        local p_min = math.min(gm.pitch, gm.pitch2)
                        local p_max = math.max(gm.pitch, gm.pitch2)
                        if pitch > p_min and pitch < p_max then
                            local t_start_qn = gm.s_qn + ((gm.pct or 50) / 100.0) * (gm.orig_dur or 1.0)
                            if n_sqn >= (t_start_qn - 0.05) and n_sqn < (gm.s2_qn - 0.005) then
                                is_gliss_step = true
                                break
                            end
                        end
                    end
                end
            end
            
            local tie_slave_info = find_tie_slave(pitch, chan, sppq, n_sqn)
            local is_tie_slave = (tie_slave_info ~= nil)
            if ok and not is_gliss_step and (not muted or is_tie_slave) then
                -- STRICT FILTERING:
                if n_sqn < end_qn - 0.005 and n_eqn > start_qn + 0.005 then
                    local cl_sqn = math.max(start_qn, n_sqn)
                    local cl_eqn = math.min(end_qn, n_eqn)
                    if math.abs(cl_sqn - start_qn) < 0.005 then cl_sqn = start_qn end
                    if math.abs(cl_eqn - end_qn) < 0.005 then cl_eqn = end_qn end
                    
                    local dur = cl_eqn - cl_sqn
                    local tie_master_info = find_tie_master(pitch, chan, sppq, n_sqn)
                    if tie_master_info and tie_master_info.orig_dur and tie_master_info.orig_dur > 0.01 then
                        dur = tie_master_info.orig_dur
                        cl_eqn = cl_sqn + dur
                    elseif tie_slave_info and tie_slave_info.orig_dur and tie_slave_info.orig_dur > 0.01 then
                        dur = tie_slave_info.orig_dur
                        cl_eqn = cl_sqn + dur
                    end

                    for _, gm in ipairs(gliss_masters) do
                        if gm.pitch == pitch and (gm.chan == nil or gm.chan == chan) and math.abs(n_sqn - gm.s_qn) <= 0.05 then
                            if gm.orig_dur and gm.orig_dur > 0.01 then
                                dur = gm.orig_dur
                                cl_eqn = cl_sqn + dur
                            end
                            break
                        end
                    end
                    
                    if dur >= 0.03125 then
                        local art = nil
                        for _, na in ipairs(note_arts_list) do
                            if na.pitch == pitch and math.abs(na.ppq - sppq) <= 25 then
                                art = na.art
                                break
                            end
                        end
                        
                        local stem_dir = nil
                        for _, ns in ipairs(note_stems_list) do
                            if ns.pitch == pitch and math.abs(ns.ppq - sppq) <= 25 then
                                stem_dir = ns.stem_dir
                                break
                            end
                        end
                        
                        local arpeggio_dir = nil
                        for _, narp in ipairs(note_arpeggios_list) do
                            if math.abs(narp.ppq - sppq) <= 75 then
                                arpeggio_dir = narp.dir or "up"
                                break
                            end
                        end
                        
                        local staff_override = nil
                        for _, nst in ipairs(note_staffs_list) do
                            if nst.pitch == pitch and math.abs(nst.ppq - sppq) <= 25 then
                                staff_override = nst.staff
                                break
                            end
                        end
                        
                        local note_obj = MidiNote.new({
                            idx = ni,
                            pitch = pitch,
                            start_qn = cl_sqn,
                            end_qn = cl_eqn,
                            dur_qn = dur,
                            vel = vel,
                            chan = chan,
                            take = take,
                            item = item,
                            track = track,
                            articulation = art,
                            stem_dir = stem_dir,
                            arpeggio = arpeggio_dir,
                            staff = staff_override,
                            is_tied_master = (tie_master_info ~= nil),
                            is_tied_slave = is_tie_slave,
                            tie_id = (tie_master_info and tie_master_info.id) or (tie_slave_info and tie_slave_info.id) or nil
                        })
                        table.insert(take_notes, note_obj)
                    end
                end
            end
        end
    end
    
    -- Synthesize tied slave notes if missing from the MIDI take (e.g. when Note 1 is held continuously across tie in REAPER MIDI)
    for _, tm in ipairs(tie_masters) do
        if tm.s2_qn and tm.d2_qn then
            local found_slave = false
            for _, n in ipairs(take_notes) do
                if n.pitch == tm.pitch and (n.chan == nil or n.chan == tm.chan) and math.abs(n.start_qn - tm.s2_qn) <= 0.15 then
                    found_slave = true
                    n.is_tied_slave = true
                    n.tie_id = tm.id
                    break
                end
            end
            if not found_slave then
                local s2_qn = tm.s2_qn
                local d2_qn = tm.d2_qn
                if s2_qn < end_qn - 0.005 and (s2_qn + d2_qn) > start_qn + 0.005 then
                    local master_staff = nil
                    for _, n in ipairs(take_notes) do
                        if n.is_tied_master and n.tie_id == tm.id then
                            master_staff = n.staff
                            break
                        end
                    end
                    local note2_obj = MidiNote.new({
                        idx = -1,
                        pitch = tm.pitch,
                        start_qn = s2_qn,
                        end_qn = s2_qn + d2_qn,
                        dur_qn = d2_qn,
                        vel = tm.vel or 96,
                        chan = tm.chan,
                        take = take,
                        item = item,
                        track = track,
                        staff = master_staff,
                        is_tied_master = false,
                        is_tied_slave = true,
                        tie_id = tm.id
                    })
                    table.insert(take_notes, note2_obj)
                end
            end
        end
    end
    
    -- Keep take_notes strictly sorted chronologically
    table.sort(take_notes, function(a, b)
        local as = a.start_qn or 0
        local bs = b.start_qn or 0
        if math.abs(as - bs) > 0.001 then return as < bs end
        return (a.pitch or 0) < (b.pitch or 0)
    end)
    
    -- Read dynamics with respect to item boundaries
    for ti = 0, text_cnt - 1 do
        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
        if ok and ev_type == 15 then
            local label, c1_s, c11_s = msg:match("dynamic%s+([%a%d]+)%s*:(%d+):(%d+)")
            if label then
                local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                if qn >= start_qn - 0.01 and qn < end_qn + 0.01 then
                    table.insert(take_dynamics, DynamicMarker.new({
                        take = take, item = item, track = track, ppq = ppq, qn = qn,
                        label = label, c1 = tonumber(c1_s) or 80, c11 = tonumber(c11_s) or 85,
                        type15_idx = ti
                    }))
                end
            else
                local dyn_lbl = msg:match("dynamic%s+([%a%d]+)")
                if dyn_lbl then
                    local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                    if qn >= start_qn - 0.01 and qn < end_qn + 0.01 then
                        table.insert(take_dynamics, DynamicMarker.new({
                            take = take, item = item, track = track, ppq = ppq, qn = qn,
                            label = dyn_lbl, c1 = 80, c11 = 85, type15_idx = ti
                        }))
                    end
                end
            end

            -- Read NOTATOR_KEY_SIG and NOTATOR_TIME_SIG Type 15 notation events
            if not item_obj.key_sig then
                local k_idx_s, k_mode_s = msg:match("^NOTATOR_KEY_SIG%s+(%-?%d+)%s*([%a%d_]*)")
                if k_idx_s then
                    local kidx = tonumber(k_idx_s)
                    item_obj.key_sig = { idx = kidx, key_idx = kidx, mode = (k_mode_s and k_mode_s ~= "") and k_mode_s or "major" }
                else
                    local nat_k = msg:match("^key%s+(%-?%d+)")
                    if nat_k then
                        local kidx = tonumber(nat_k)
                        item_obj.key_sig = { idx = kidx, key_idx = kidx, mode = "major" }
                    end
                end
            end

            if not item_obj.time_sig then
                local t_num_s, t_den_s = msg:match("^NOTATOR_TIME_SIG%s+(%d+)%s+(%d+)")
                if t_num_s and t_den_s then
                    item_obj.time_sig = { num = tonumber(t_num_s), denom = tonumber(t_den_s) }
                else
                    local nat_num, nat_den = msg:match("^time%s+(%d+)/(%d+)")
                    if nat_num and nat_den then
                        item_obj.time_sig = { num = tonumber(nat_num), denom = tonumber(nat_den) }
                    end
                end
            end

            -- Read NOTATOR events from Type 15 notation events of the MIDI take
            if state then
                if msg:match("^NOTATOR_PEDAL") then
                    local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
                    PedalService.parse_notation_event(state, track, take, ppq, msg)
                elseif msg:match("^NOTATOR_REPEAT") then
                    local RepeatService = package.loaded["services.repeat_service"] or require("services.repeat_service")
                    RepeatService.parse_notation_event(state, track, take, ppq, msg)
                elseif msg:match("^NOTATOR_HAIRPIN") then
                    local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
                    HairpinService.parse_notation_event(state, track, take, ppq, msg)
                elseif msg:match("^NOTATOR_DYN_TEXT") then
                    local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
                    DynamicTextService.parse_notation_event(state, track, take, ppq, msg)
                elseif msg:match("^NOTATOR_TEXT") then
                    local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
                    TextItemService.parse_notation_event(state, track, take, ppq, msg)
                elseif msg:match("^NOTATOR_OCTAVE") then
                    local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
                    OctaveService.parse_notation_event(state, track, take, ppq, msg)
                end
            end
        end
    end
    
    -- Read Program Changes (articulations) including preceding Bank Select (CC0/CC32)
    local cur_msb, cur_lsb = -1, -1
    local _, _, cc_cnt, _ = reaper.MIDI_CountEvts(take)
    for ci = 0, cc_cnt - 1 do
        local ok, _, _, ppq, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(take, ci)
        if ok then
            if (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and msg2 == 0 then
                cur_msb = msg3
            elseif (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and msg2 == 32 then
                cur_lsb = msg3
            elseif (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0) then -- Program Change
                local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                if qn >= start_qn - 0.01 and qn < end_qn + 0.01 then
                    local is_chase = false
                    for _, ce in ipairs(chase_events_list) do
                        if ce.chan == chan and math.abs(ce.ppq - ppq) <= 25 and ce.pc == msg2 then
                            is_chase = true
                            break
                        end
                    end
                    table.insert(take_articulations, {
                        take = take, item = item, track = track, ppq = ppq, qn = qn,
                        pc = msg2, msb = cur_msb, lsb = cur_lsb, chan = chan, cc_idx = ci,
                        is_articulation = true,
                        is_auto_return = is_chase
                    })
                end
            end
        end
    end
    
    if #take_articulations > 0 and #take_notes > 0 then
        local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
        local all_banks = ReaticulateParser.get_all_banks()
        local bank = track and ReaticulateParser.get_bank_for_track(track, all_banks)
        if bank and bank.articulations and #bank.articulations > 0 then
            for _, n in ipairs(take_notes) do
                if not n.articulation or n.articulation == "" then
                    local n_sppq = reaper.MIDI_GetPPQPosFromProjQN(take, n.start_qn)
                    local best_art = nil
                    for _, art in ipairs(take_articulations) do
                        if art.chan == n.chan and art.ppq <= n_sppq + 15 then
                            if not best_art or art.ppq > best_art.ppq then
                                best_art = art
                            end
                        end
                    end
                    if best_art and math.abs(best_art.ppq - n_sppq) <= 25 then
                        for _, a in ipairs(bank.articulations) do
                            if a.pc == best_art.pc then
                                local mapped = MidiService.art_id_from_reaticulate_art(a)
                                if mapped then
                                    n.articulation = mapped
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    
    return item_obj, take_notes, take_dynamics, take_articulations
end

function MidiService.get_track_items_and_notes(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return {}, {}, {}, {}, 0
    end
    
    local track_guid = reaper.GetTrackGUID(track)
    local track_col = reaper.GetTrackColor(track)
    local num_items = reaper.CountTrackMediaItems(track)
    local proj_change_cnt = (reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0)) or 0
    
    local cached = MidiService._track_cache[track_guid]
    local is_dirty = false
    
    if not cached or cached.num_items ~= num_items or cached.track_col ~= track_col then
        is_dirty = true
    elseif cached.proj_change_cnt == proj_change_cnt then
        -- Fast Path O(1): Entire REAPER project state is identical, zero modifications occurred.
        -- Return cached track data immediately without inspecting any items!
        if not cached.rests_cache then cached.rests_cache = {} end
        return cached.items_info, cached.all_notes, cached.all_dynamics, cached.all_articulations, cached.max_qn, cached.rests_cache
    else
        local sigs = cached.items_sig
        for i = 0, num_items - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            local sig = sigs[i + 1]
            if not sig or sig.item ~= item then
                is_dirty = true; break
            end
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local mute = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
            local col = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
            if sig.pos ~= pos or sig.len ~= len or sig.mute ~= mute or sig.col ~= col then
                is_dirty = true; break
            end
            local ok_k, k_ext_check = reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_key_sig", "", false)
            local ok_t, t_ext_check = reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_time_sig", "", false)
            if sig.k_ext ~= k_ext_check or sig.t_ext ~= t_ext_check then
                is_dirty = true; break
            end
            local take = reaper.GetActiveTake(item)
            if sig.take ~= take then
                is_dirty = true; break
            end
            if take and reaper.TakeIsMIDI(take) then
                local take_hash = get_take_hash(take)
                if sig.hash ~= take_hash then
                    is_dirty = true; break
                end
            end
        end
    end
    
    if not is_dirty and cached then
        cached.proj_change_cnt = proj_change_cnt
        if not cached.rests_cache then cached.rests_cache = {} end
        return cached.items_info, cached.all_notes, cached.all_dynamics, cached.all_articulations, cached.max_qn, cached.rests_cache
    end
    
    -- Cache miss: re-parse track
    local items_info = {}
    local all_notes = {}
    local all_dynamics = {}
    local all_articulations = {}
    local new_items_sig = {}
    local max_qn = 0
    
    for i = 0, num_items - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local take = reaper.GetActiveTake(item)
        if take and reaper.TakeIsMIDI(take) then
            local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
            local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            local mute = reaper.GetMediaItemInfo_Value(item, "B_MUTE")
            local item_col = reaper.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
            if item_col == 0 then item_col = track_col end
            local _, iname = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
            if not iname or iname == "" then iname = string.format("Item %d", i + 1) end
            local loop_src = reaper.GetMediaItemInfo_Value(item, "B_LOOPSRC") ~= 0
            
            local take_hash = get_take_hash(take)
            local _, cur_k_ext = reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_key_sig", "", false)
            local _, cur_t_ext = reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_time_sig", "", false)
            
            table.insert(new_items_sig, {
                item = item,
                take = take,
                pos = pos,
                len = len,
                mute = mute,
                col = item_col,
                hash = take_hash,
                k_ext = cur_k_ext,
                t_ext = cur_t_ext
            })
            
            local start_qn = reaper.TimeMap2_timeToQN(0, pos)
            local end_qn = reaper.TimeMap2_timeToQN(0, pos + len)
            if end_qn > max_qn then max_qn = end_qn end
            
            local tc = MidiService._take_cache[take]
            local take_cached = tc and (tc.hash == take_hash) and (tc.pos == pos) and (tc.len == len) and (tc.mute == mute) and (tc.col == item_col) and (tc.name == iname) and (tc.loop_src == loop_src) and (tc.k_ext == cur_k_ext) and (tc.t_ext == cur_t_ext)
            
            local take_item_obj, take_notes, take_dyns, take_arts
            if take_cached then
                take_item_obj = tc.item_obj
                take_notes = tc.notes
                take_dyns = tc.dynamics
                take_arts = tc.articulations
            else
                take_item_obj, take_notes, take_dyns, take_arts = parse_single_take_midi(take, item, track, i, pos, len, start_qn, end_qn, item_col, iname)
                MidiService._take_cache[take] = {
                    hash = take_hash,
                    pos = pos,
                    len = len,
                    mute = mute,
                    col = item_col,
                    name = iname,
                    loop_src = loop_src,
                    k_ext = cur_k_ext,
                    t_ext = cur_t_ext,
                    item_obj = take_item_obj,
                    notes = take_notes,
                    dynamics = take_dyns,
                    articulations = take_arts
                }
            end
            
            -- Ensure .key_sig and .time_sig are always kept up-to-date from P_EXT
            if cur_k_ext and cur_k_ext ~= "" then
                local idx_s, mode_s = cur_k_ext:match("^(%-?%d+)|?([%a%d_]*)")
                if idx_s then
                    local kidx = tonumber(idx_s)
                    take_item_obj.key_sig = { idx = kidx, key_idx = kidx, mode = (mode_s and mode_s ~= "") and mode_s or "major" }
                end
            end
            if cur_t_ext and cur_t_ext ~= "" then
                local num_s, den_s = cur_t_ext:match("^(%d+)|(%d+)")
                if num_s and den_s then
                    take_item_obj.time_sig = { num = tonumber(num_s), denom = tonumber(den_s) }
                end
            end
            
            table.insert(items_info, take_item_obj)
            for _, n in ipairs(take_notes) do table.insert(all_notes, n) end
            for _, d in ipairs(take_dyns) do table.insert(all_dynamics, d) end
            for _, a in ipairs(take_arts) do table.insert(all_articulations, a) end
        end
    end
    
    table.sort(all_notes, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.005 then return a.start_qn < b.start_qn end
        return a.pitch < b.pitch
    end)
    table.sort(all_dynamics, function(a, b) return a.ppq < b.ppq end)
    table.sort(all_articulations, function(a, b) return a.ppq < b.ppq end)
    
    MidiService._track_cache[track_guid] = {
        proj_change_cnt = proj_change_cnt,
        num_items = num_items,
        track_col = track_col,
        items_sig = new_items_sig,
        items_info = items_info,
        all_notes = all_notes,
        all_dynamics = all_dynamics,
        all_articulations = all_articulations,
        max_qn = max_qn,
        rests_cache = {}
    }
    
    return items_info, all_notes, all_dynamics, all_articulations, max_qn, MidiService._track_cache[track_guid].rests_cache
end

function MidiService.sync_selection_to_reaper(state, active_tracks_data)
    local takes = {}
    for _, sn in pairs(state.selected_notes) do
        if sn.take and reaper.ValidatePtr(sn.take, "MediaItem_Take*") then
            takes[sn.take] = true
        end
    end
    
    if active_tracks_data then
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.items then
                for _, it in ipairs(tdata.items) do
                    if it.take and reaper.ValidatePtr(it.take, "MediaItem_Take*") then
                        takes[it.take] = true
                    end
                end
            end
        end
    end
    
    for take in pairs(takes) do
        if reaper.ValidatePtr(take, "MediaItem_Take*") then
            local it = reaper.GetMediaItemTake_Item(take)
            local it_str = tostring(it or "0")
            local tk_str = tostring(take)
            local _, notecnt = reaper.MIDI_CountEvts(take)
            for i = 0, notecnt - 1 do
                local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
                if ok then
                    local qn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                    local key = string.format("%s_%s_%.3f_%d_%d", it_str, tk_str, qn, pitch, chan)
                    local should_sel = (state.selected_notes[key] ~= nil)
                    if sel ~= should_sel then
                        reaper.MIDI_SetNote(take, i, should_sel, muted, sppq, eppq, chan, pitch, vel, false)
                    end
                end
            end
        end
    end
end

-- Searches for an existing MIDI item at target location or creates a new clean item without looping (B_LOOPSRC = 0)
function MidiService.get_or_create_item_at_qn(track, target_qn, dur_qn)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return nil, nil end
    local need_dur = dur_qn or 1.0
    local target_time = reaper.TimeMap2_QNToTime(0, target_qn)
    local target_end_time = reaper.TimeMap2_QNToTime(0, target_qn + need_dur)
    
    local num_items = reaper.CountTrackMediaItems(track)
    local best_item, best_take = nil, nil
    
    for i = 0, num_items - 1 do
        local it = reaper.GetTrackMediaItem(track, i)
        local tk = reaper.GetActiveTake(it)
        if tk and reaper.TakeIsMIDI(tk) then
            local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
            local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
            local i_start_qn = reaper.TimeMap2_timeToQN(0, ipos)
            local i_end_qn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
            
            -- Exact match: target lies within item
            if target_qn >= (i_start_qn - 0.05) and target_qn <= (i_end_qn + 0.05) then
                best_item = it
                best_take = tk
                -- Expand item if necessary without looping
                if (target_qn + need_dur) > i_end_qn then
                    local new_end_qn = math.max(i_end_qn, target_qn + need_dur + 1.0)
                    reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
                    reaper.MIDI_SetItemExtents(it, i_start_qn, new_end_qn)
                    reaper.SetMediaItemInfo_Value(it, "B_LOOPSRC", 0)
                end
                break
            end
        end
    end
    
    -- If no item found: create new MIDI item across measure range!
    if not best_take then
        local timesig_num, timesig_denom, bpm = reaper.TimeMap_GetTimeSigAtTime(0, target_time)
        timesig_num = (timesig_num and timesig_num > 0) and timesig_num or 4
        timesig_denom = (timesig_denom and timesig_denom > 0) and timesig_denom or 4
        local qn_per_measure = timesig_num * (4 / timesig_denom)
        
        local measure_idx = math.floor(target_qn / qn_per_measure)
        local item_start_qn = measure_idx * qn_per_measure
        local item_end_qn = math.max((measure_idx + 1) * qn_per_measure, target_qn + need_dur)
        
        local item_start_time = reaper.TimeMap2_QNToTime(0, item_start_qn)
        local item_end_time = reaper.TimeMap2_QNToTime(0, item_end_qn)
        local item_len = item_end_time - item_start_time
        
        local new_item = reaper.CreateNewMIDIItemInProj(track, item_start_time, item_end_time, false)
        if new_item then
            reaper.SetMediaItemInfo_Value(new_item, "B_LOOPSRC", 0)
            local tk = reaper.GetActiveTake(new_item)
            if tk then
                reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "Notator MIDI", true)
                best_item = new_item
                best_take = tk
            end
            -- Initialize new item with clean default modulators (Phrasing ON, bow swell 0.0, bow pos 0.50)
            local default_dyn = "cc_a=1|cc_b=11|grid=4|phr=1|p_int=0.50|h_int=0.30|stress=0.50|bow=0.00|bow_pos=0.50|vel_sens=0.80|m2m=0|bypass_cc=0"
            reaper.GetSetMediaItemInfo_String(new_item, "P_EXT:notator_dyn_mod", default_dyn, true)
        end
    end
    
    return best_item, best_take
end

-- ==============================================================================
-- VOICES SYSTEM (1-16 Voices via MIDI Note Channels 0-15)
-- ==============================================================================

function MidiService.resolve_voice_conflicts(take, ref_notes)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end
    if not ref_notes or #ref_notes == 0 then return end
    
    local _, notecnt = reaper.MIDI_CountEvts(take)
    if notecnt <= 1 then return end
    
    local is_ref_idx = {}
    for _, rn in ipairs(ref_notes) do
        if rn.idx and rn.idx >= 0 then
            is_ref_idx[rn.idx] = true
        end
    end
    
    local to_delete = {}
    local to_modify = {}
    
    for i = 0, notecnt - 1 do
        local is_ref = is_ref_idx[i]
        local ok, sel, muted, s_ppq, e_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if ok and not is_ref then
            for _, rn in ipairs(ref_notes) do
                if math.abs(s_ppq - rn.sppq) < 5 and math.abs(e_ppq - rn.eppq) < 5 and pitch == rn.pitch and chan == rn.chan then
                    is_ref = true
                    break
                end
            end
        end
        
        if ok and not is_ref and not muted then
            for _, ref in ipairs(ref_notes) do
                -- Only collide if same pitch AND same voice (same MIDI channel)!
                if pitch == ref.pitch and chan == ref.chan then
                    local ov_s = math.max(s_ppq, ref.sppq)
                    local ov_e = math.min(e_ppq, ref.eppq)
                    if ov_e > ov_s then
                        -- Collision:
                        if ref.sppq <= s_ppq and ref.eppq >= e_ppq then
                            -- Ref covers stationary note completely -> delete
                            to_delete[i] = true
                        elseif s_ppq < ref.sppq and e_ppq > ref.sppq then
                            -- Ref overlaps into stationary note from right:
                            -- Shorten stationary note at end (to start of ref)
                            local new_e = ref.sppq
                            if new_e - s_ppq < 20 then
                                to_delete[i] = true
                            else
                                to_modify[i] = { sppq = s_ppq, eppq = new_e, sel = sel, muted = muted, chan = chan, pitch = pitch, vel = vel }
                                e_ppq = new_e
                            end
                        elseif s_ppq >= ref.sppq and s_ppq < ref.eppq and e_ppq > ref.eppq then
                            -- Ref overlaps into stationary note from left:
                            -- Shorten stationary note at start (to end of ref)
                            local new_s = ref.eppq
                            if e_ppq - new_s < 20 then
                                to_delete[i] = true
                            else
                                to_modify[i] = { sppq = new_s, eppq = e_ppq, sel = sel, muted = muted, chan = chan, pitch = pitch, vel = vel }
                                s_ppq = new_s
                            end
                        end
                    end
                end
            end
        end
    end
    
    for i, mod in pairs(to_modify) do
        if not to_delete[i] then
            reaper.MIDI_SetNote(take, i, mod.sel, mod.muted, mod.sppq, mod.eppq, mod.chan, mod.pitch, mod.vel, false)
        end
    end
    
    local del_list = {}
    for i in pairs(to_delete) do table.insert(del_list, i) end
    table.sort(del_list, function(a, b) return a > b end)
    for _, idx in ipairs(del_list) do
        reaper.MIDI_DeleteNote(take, idx)
    end
end

function MidiService.set_selected_notes_voice(state, new_voice)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then return end
    
    local new_chan = math.max(0, math.min(15, (new_voice or 1) - 1))
    
    reaper.Undo_BeginBlock2(0)
    local affected_takes = {}
    local take_modified_notes = {}
    local new_selected = {}
    
    for _, sn in ipairs(targets) do
        local take = sn.take
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not affected_takes[take] then
                affected_takes[take] = true
                reaper.MIDI_DisableSort(take)
            end
            
            local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn) + 0.5)
            local eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sn.end_qn) + 0.5)
            
            local target_idx = nil
            local ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, sn.idx)
            if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 15 then
                target_idx = sn.idx
            else
                local _, notecnt = reaper.MIDI_CountEvts(take)
                for i = 0, notecnt - 1 do
                    ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, i)
                    if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 15 then
                        target_idx = i
                        break
                    end
                end
            end
            
            if target_idx and ok then
                reaper.MIDI_SetNote(take, target_idx, true, muted, s2, e2, new_chan, p2, vel, false)
                take_modified_notes[take] = take_modified_notes[take] or {}
                table.insert(take_modified_notes[take], { idx = target_idx, pitch = p2, chan = new_chan, sppq = s2, eppq = e2 })
                
                local updated = MidiNote.new({
                    idx = target_idx, pitch = p2, start_qn = sn.start_qn, end_qn = sn.end_qn,
                    dur_qn = sn.dur_qn, vel = vel, chan = new_chan, take = take, item = sn.item,
                    track = sn.track, articulation = sn.articulation
                })
                new_selected[updated:get_key()] = updated
            end
        end
    end
    
    for tk, ref_list in pairs(take_modified_notes) do
        MidiService.resolve_voice_conflicts(tk, ref_list)
    end
    for tk in pairs(affected_takes) do
        reaper.MIDI_Sort(tk)
    end
    
    reaper.Undo_EndBlock2(0, string.format("Notator: Assign to Voice %d (Ch %d)", new_voice, new_chan + 1), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    
    state.selected_notes = new_selected
    for _, sn in pairs(new_selected) do state.selected_note = sn break end
    state.status_msg = string.format("Assigned %d note(s) to Voice %d (MIDI Channel %d)", #targets, new_voice, new_chan + 1)
end

function MidiService.auto_split_overlaps_to_voices(state, target_track, only_selected)
    -- 1. Determine all relevant tracks
    local tracks_to_process = {}
    if only_selected and state and state.selected_notes and next(state.selected_notes) then
        for _, sn in pairs(state.selected_notes) do
            local trk = sn.track
            if not trk and sn.take and reaper.ValidatePtr(sn.take, "MediaItem_Take*") then
                trk = get_track_from_take(sn.take)
            end
            if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                local guid = reaper.GetTrackGUID(trk)
                tracks_to_process[guid] = trk
            end
        end
    end
    
    if not next(tracks_to_process) then
        local trk = target_track or state.focused_track
        if not trk and state.selected_notes then
            for _, sn in pairs(state.selected_notes) do
                if sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then
                    trk = sn.track
                    break
                end
            end
        end
        if not trk then
            trk = reaper.GetSelectedTrack(0, 0)
        end
        if not trk then
            local take = MidiService.get_active_midi_take()
            if take then trk = get_track_from_take(take) end
        end
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            tracks_to_process[reaper.GetTrackGUID(trk)] = trk
        end
    end
    
    if not next(tracks_to_process) then
        state.status_msg = "Auto-Voice: No track selected"
        return
    end
    
    local undo_title = only_selected and "Notator: Auto-Voice on Selection" or "Notator: Auto-Voice Track Overlaps"
    reaper.Undo_BeginBlock2(0)
    local total_moved = 0
    local any_notes_selected = false
    
    for _, track in pairs(tracks_to_process) do
        local item_cnt = reaper.CountTrackMediaItems(track)
        if item_cnt > 0 then
            local is_grand = false
            if state and state.active_tracks_cache then
                for _, tdata in ipairs(state.active_tracks_cache) do
                    if tdata.track == track and tdata.clef == "grand" then
                        is_grand = true
                        break
                    end
                end
            end
            
            for it_idx = 0, item_cnt - 1 do
                local item = reaper.GetTrackMediaItem(track, it_idx)
                local take = reaper.GetActiveTake(item)
                if take and reaper.TakeIsMIDI(take) then
                    local _, notecnt = reaper.MIDI_CountEvts(take)
                    if notecnt > 0 then
                        reaper.MIDI_DisableSort(take)
                        
                        -- Robust selection check via index, take pointer, and PPQ position
                        local notes = {}
                        local sel_count = 0
                        for ni = 0, notecnt - 1 do
                            local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
                            if ok and not muted then
                                local is_sel = sel
                                if not is_sel and state and state.selected_notes then
                                    for _, sn in pairs(state.selected_notes) do
                                        local same_take = (sn.take == take) or (tostring(sn.take) == tostring(take))
                                        if same_take then
                                            if sn.idx == ni then
                                                is_sel = true; break
                                             elseif sn.pitch == pitch and math.abs((sn.sppq or sppq) - sppq) <= 25 then
                                                is_sel = true; break
                                            end
                                        end
                                    end
                                end
                                
                                local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                                local eqn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
                                local dur_qn = math.max(0.0625, eqn - sqn)
                                local bpi = 4.0
                                local bar_idx = math.floor(sqn / bpi)
                                
                                table.insert(notes, {
                                    idx = ni, sppq = sppq, eppq = eppq,
                                    sqn = sqn, eqn = eqn, dur_qn = dur_qn,
                                    bar_idx = bar_idx,
                                    chan = chan, pitch = pitch, vel = vel, sel = is_sel
                                })
                                if is_sel then sel_count = sel_count + 1 end
                            end
                        end
                        
                        if sel_count > 0 then any_notes_selected = true end
                        
                        -- Voice assignment (Voice 0..15):
                        local voice_notes = {}
                        for v = 0, 15 do voice_notes[v] = {} end
                        
                        if only_selected and sel_count > 0 then
                            for _, n in ipairs(notes) do
                                if not n.sel then
                                    table.insert(voice_notes[n.chan], {
                                        sppq = n.sppq, eppq = n.eppq,
                                        sqn = n.sqn, eqn = n.eqn, dur_qn = n.dur_qn,
                                        bar_idx = n.bar_idx, pitch = n.pitch
                                    })
                                end
                            end
                        end
                        
                        -- Sort chronologically; for identical start time, higher pitch first (soprano/melody stays in voice 1)
                        table.sort(notes, function(a, b)
                            if math.abs(a.sppq - b.sppq) > 15 then
                                return a.sppq < b.sppq
                            end
                            return a.pitch > b.pitch
                        end)
                        
                        for _, n in ipairs(notes) do
                            if not only_selected or n.sel then
                                local min_v = 0
                                local max_v = 15
                                if is_grand then
                                    min_v = (n.pitch >= 60) and 0 or 2
                                    max_v = (n.pitch >= 60) and 1 or 3
                                end
                                
                                local assigned_voice = nil
                                for v = min_v, max_v do
                                    local conflict = false
                                    for _, vn in ipairs(voice_notes[v]) do
                                        -- A. Same pitch at the same time
                                        local ov_s = math.max(n.sppq, vn.sppq)
                                        local ov_e = math.min(n.eppq, vn.eppq)
                                        if ov_e > ov_s + 15 then
                                            if n.pitch == vn.pitch then
                                                conflict = true
                                                break
                                            end
                                            -- True chord requires identical start AND identical duration!
                                            local same_start = math.abs(n.sppq - vn.sppq) <= 35
                                            local same_end   = math.abs(n.eppq - vn.eppq) <= 35
                                            local same_rhythm = same_start and same_end
                                            if not same_rhythm then
                                                conflict = true
                                                break
                                            end
                                        end
                                        
                                        -- B. Measure-filling whole note (Gould / Gardner Read)
                                        -- If there is a whole note in the same measure (dur_qn >= 3.4),
                                        -- NO other note starting later may belong to the same voice!
                                        if vn.bar_idx == n.bar_idx then
                                            local vn_is_whole = (vn.dur_qn >= 3.4)
                                            local n_is_whole  = (n.dur_qn >= 3.4)
                                            if (vn_is_whole or n_is_whole) and math.abs(n.sqn - vn.sqn) > 0.05 then
                                                conflict = true
                                                break
                                            end
                                        end
                                    end
                                    
                                    if not conflict then
                                        assigned_voice = v
                                        break
                                    end
                                end
                                
                                if assigned_voice == nil then assigned_voice = max_v end
                                table.insert(voice_notes[assigned_voice], {
                                    sppq = n.sppq, eppq = n.eppq,
                                    sqn = n.sqn, eqn = n.eqn, dur_qn = n.dur_qn,
                                    bar_idx = n.bar_idx, pitch = n.pitch
                                })
                                
                                if n.chan ~= assigned_voice then
                                    reaper.MIDI_SetNote(take, n.idx, n.sel, false, n.sppq, n.eppq, assigned_voice, n.pitch, n.vel, true)
                                    total_moved = total_moved + 1
                                    n.chan = assigned_voice
                                    if state and state.selected_notes then
                                        for _, sn in pairs(state.selected_notes) do
                                            local same_take = (sn.take == take) or (tostring(sn.take) == tostring(take))
                                            if same_take and (sn.idx == n.idx or (sn.pitch == n.pitch and math.abs((sn.sppq or n.sppq) - n.sppq) <= 25)) then
                                                sn.chan = assigned_voice
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        
                        reaper.MIDI_Sort(take)
                    end
                end
            end
            
            MidiService.invalidate_cache(track)
        end
    end
    
    reaper.Undo_EndBlock2(0, undo_title, -1)
    reaper.UpdateArrange()
    
    if only_selected and not any_notes_selected then
        state.status_msg = "Auto-Voice on Selection: No notes selected to voice"
    else
        local prefix = only_selected and "Auto-Voice (Selection)" or "Auto-Voice (Track)"
        state.status_msg = string.format("%s: Separated %d overlapping note(s) into distinct voices (1-16)", prefix, total_moved)
    end
end

function MidiService.auto_split_selection_to_voices(state, target_track)
    local has_sel = false
    if state and state.selected_notes and next(state.selected_notes) then
        has_sel = true
    end
    if not has_sel then
        state.status_msg = "Auto-Voice on Selection: Please select notes (or click Auto-Voice for whole track)"
        return
    end
    return MidiService.auto_split_overlaps_to_voices(state, target_track, true)
end
MidiService.auto_voice_selection_to_voices = MidiService.auto_split_selection_to_voices

function MidiService.insert_note(take, qn, pitch, dur_qn, vel, chan, articulation)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil end
    local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, qn) + 0.5)
    local eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, qn + dur_qn) + 0.5)
    
    -- Pre-clamp any prior note of the same voice/pitch whose tail bleeds into this note's start
    local _, pre_notecnt = reaper.MIDI_CountEvts(take)
    for ni = 0, pre_notecnt - 1 do
        local ok_p, sel_p, mut_p, sp_p, ep_p, ch_p, pt_p, vel_p = reaper.MIDI_GetNote(take, ni)
        if ok_p and not mut_p and pt_p == pitch and ch_p == (chan or 0) then
            if sp_p < sppq and ep_p > sppq then
                reaper.MIDI_SetNote(take, ni, sel_p, mut_p, sp_p, sppq, ch_p, pt_p, vel_p, false)
            end
        end
    end
    
    reaper.MIDI_InsertNote(take, true, false, sppq, eppq, chan or 0, pitch, vel or 96, false)
    
    if articulation and articulation ~= "" then
        local art_str = string.format("NOTE %d %d a %s", pitch, chan or 0, articulation)
        reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, art_str)
        
        local trk = get_track_from_take(take)
        local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
        local all_banks = ReaticulateParser.get_all_banks()
        local bank = trk and ReaticulateParser.get_bank_for_track(trk, all_banks)
        local art_match = bank and MidiService.find_reaticulate_art_for_id(bank, articulation)
        if art_match then
            if bank.msb and bank.msb >= 0 then
                reaper.MIDI_InsertCC(take, false, false, sppq, 0xB0, chan or 0, 0, bank.msb)
            end
            if bank.lsb and bank.lsb >= 0 then
                reaper.MIDI_InsertCC(take, false, false, sppq, 0xB0, chan or 0, 32, bank.lsb)
            end
            reaper.MIDI_InsertCC(take, false, false, sppq, 0xC0, chan or 0, art_match.pc, 0)
        end
    end
    
    local item = reaper.GetMediaItemTake_Item(take)
    local trk = get_track_from_take(take)
    
    local note_obj = MidiNote.new({
        idx = 0, pitch = pitch, start_qn = qn, end_qn = qn + dur_qn,
        dur_qn = dur_qn, vel = vel or 96, chan = chan or 0,
        take = take, item = item, track = trk, articulation = articulation
    })
    return note_obj
end

function MidiService.insert_note_at_qn(state, qn, pitch, dur)
    local track = state.focused_track or reaper.GetSelectedTrack(0, 0)
    if not track then
        local take = MidiService.get_active_midi_take()
        if take then track = get_track_from_take(take) end
    end
    if not track then return nil end
    
    local item, take = MidiService.get_or_create_item_at_qn(track, qn, dur)
    if not take then return nil end
    
    -- If an octave line spans this position, insert note with sounding pitch in MIDI take:
    local OctaveService = require("services.octave_service")
    local Constants = require("constants")
    local trk_guid = reaper.GetTrackGUID(track)
    local active_oct = OctaveService.get_active_line_at_qn(state, trk_guid, qn)
    local oct_shift = active_oct and (Constants.OCTAVE_LINE_DEFS[active_oct.type] and Constants.OCTAVE_LINE_DEFS[active_oct.type].shift_semitones or 0) or 0
    local midi_pitch = math.max(0, math.min(127, pitch + oct_shift))
    
    -- Determine active voice (voice / MIDI channel 0-15) for this track
    local v = (state.track_voices and trk_guid and state.track_voices[trk_guid]) or 0
    local chan = (v > 0) and (v - 1) or 0

    -- If a chord item spans this position and this track is targeted:
    local ScaleService = package.loaded["services.scale_service"] or (package.loaded["modules.services.scale_service"])
    local chord_orig_pitch = nil
    if ScaleService and state.chord_items and ScaleService.is_track_targeted(state, trk_guid) then
        for _, ci in ipairs(state.chord_items) do
            if qn >= (ci.start_qn - 0.05) and qn < (ci.end_qn - 0.005) then
                local snapped_pitch = ScaleService.snap_pitch_to_scale(midi_pitch, ci.root, ci.scale_type)
                if snapped_pitch ~= midi_pitch then
                    chord_orig_pitch = midi_pitch
                    midi_pitch = snapped_pitch
                end
                break
            end
        end
    end
    
    reaper.Undo_BeginBlock2(0)
    reaper.MIDI_DisableSort(take)
    local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, qn) + 0.5)
    local eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, qn + dur) + 0.5)
    -- Pre-clamp any prior note of the same voice/pitch whose tail bleeds into this note's start
    local _, pre_notecnt = reaper.MIDI_CountEvts(take)
    for ni = 0, pre_notecnt - 1 do
        local ok_p, sel_p, mut_p, sp_p, ep_p, ch_p, pt_p, vel_p = reaper.MIDI_GetNote(take, ni)
        if ok_p and not mut_p and pt_p == midi_pitch and ch_p == chan then
            if sp_p < sppq and ep_p > sppq then
                reaper.MIDI_SetNote(take, ni, sel_p, mut_p, sp_p, sppq, ch_p, pt_p, vel_p, false)
            end
        end
    end

    local n_obj = MidiService.insert_note(take, qn, midi_pitch, dur, 96, chan, state.active_articulation)

    if chord_orig_pitch then
        local tag_msg = string.format("NOTATOR_CHORD_ORIG %d %d %d", chord_orig_pitch, chan, midi_pitch)
        reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, tag_msg)
    end
    
    -- Shorten/delete overlapping notes of the same voice on identical pitch
    MidiService.resolve_voice_conflicts(take, { { pitch = midi_pitch, chan = chan, sppq = sppq, eppq = eppq } })
    
    local trk_take = get_track_from_take(take)
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks()
    local bank = trk_take and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk_take, all_banks)
    MidiService.auto_chase_momentary_articulations(take, bank)
    
    reaper.MIDI_Sort(take)
    reaper.Undo_EndBlock2(0, "Notator: Insert note", -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache(track)
    
    if n_obj then
        if state.accidental and state.accidental ~= 0 and state.note_accidentals then
            local k = n_obj:get_key()
            state.note_accidentals[k] = state.accidental
            local id_k = string.format("%s_%s_%.3f", tostring(take), tostring(n_obj.idx), qn)
            state.note_accidentals[id_k] = state.accidental
            local pos_k = string.format("%s_%.3f_%d", tostring(take), qn, pitch)
            state.note_accidentals[pos_k] = state.accidental
        end
        if state.note_base_pitch then
            local base_p = pitch - (state.accidental or 0)
            local k = n_obj:get_key()
            state.note_base_pitch[k] = base_p
            local id_k = string.format("%s_%s_%.3f", tostring(take), tostring(n_obj.idx), qn)
            state.note_base_pitch[id_k] = base_p
            local pos_k = string.format("%s_%.3f_%d", tostring(take), qn, pitch)
            state.note_base_pitch[pos_k] = base_p
        end
        state:clear_selection()
        state:select_note(n_obj)
        state.selected_note = n_obj
    end
    return n_obj
end

function MidiService.delete_selected_notes(state)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then return 0 end
    
    reaper.Undo_BeginBlock2(0)
    local by_take = {}
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not by_take[take] then by_take[take] = {} end
            table.insert(by_take[take], sn)
        end
    end
    
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks()
    local del_cnt = 0
    
    for take, n_list in pairs(by_take) do
        local trk = get_track_from_take(take)
        local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, all_banks)
        
        reaper.MIDI_DisableSort(take)
        local _, notecnt = reaper.MIDI_CountEvts(take)
        
        -- 1. Identify notes to delete and record their properties
        local idx_to_del = {}
        local deleted_note_infos = {}
        
        for _, sn in ipairs(n_list) do
            local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn)
            local target_idx = nil
            local ok, _, _, s2, e2, c2, p2, _ = reaper.MIDI_GetNote(take, sn.idx)
            if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 15 then
                target_idx = sn.idx
                table.insert(deleted_note_infos, { idx = sn.idx, pitch = p2, chan = c2, sppq = s2, eppq = e2 })
            else
                for i = 0, notecnt - 1 do
                    local ok2, _, _, s_chk, e_chk, c_chk, p_chk, _ = reaper.MIDI_GetNote(take, i)
                    if ok2 and p_chk == sn.pitch and math.abs(s_chk - sppq) < 15 then
                        target_idx = i
                        table.insert(deleted_note_infos, { idx = i, pitch = p_chk, chan = c_chk, sppq = s_chk, eppq = e_chk })
                        break
                    end
                end
            end
            if target_idx then
                table.insert(idx_to_del, target_idx)
            end
        end
        
        -- 2. Delete the MIDI notes (descending order)
        table.sort(idx_to_del, function(a, b) return a > b end)
        local seen_idx = {}
        for _, idx in ipairs(idx_to_del) do
            if not seen_idx[idx] then
                seen_idx[idx] = true
                reaper.MIDI_DeleteNote(take, idx)
                del_cnt = del_cnt + 1
            end
        end
        
        -- 3. Delete Type 15 text events attached to the deleted notes
        local _, rem_notes, _, cur_text_cnt = reaper.MIDI_CountEvts(take)
        for ti = cur_text_cnt - 1, 0, -1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
            if ok and etype == 15 then
                local p, ch = msg:match("NOTE%s+(%d+)%s+(%d+)")
                if p and ch then
                    local p_num = tonumber(p)
                    local ch_num = tonumber(ch)
                    for _, dn in ipairs(deleted_note_infos) do
                        if dn.pitch == p_num and dn.chan == ch_num and math.abs(dn.sppq - ppq) <= 25 then
                            reaper.MIDI_DeleteTextSysexEvt(take, ti)
                            break
                        end
                    end
                else
                    local orig_p, ch_orig, midi_p = msg:match("NOTATOR_CHORD_ORIG%s+(%d+)%s+(%d+)%s+(%d+)")
                    if orig_p and ch_orig and midi_p then
                        local p_num = tonumber(midi_p)
                        local ch_num = tonumber(ch_orig)
                        for _, dn in ipairs(deleted_note_infos) do
                            if dn.pitch == p_num and dn.chan == ch_num and math.abs(dn.sppq - ppq) <= 25 then
                                reaper.MIDI_DeleteTextSysexEvt(take, ti)
                                break
                            end
                        end
                    end
                end
            end
        end
        
        -- 4. Delete CCs (CC0, CC32) and Program Changes belonging to deleted notes where no remaining note exists
        local _, cur_notecnt, cur_cccnt, _ = reaper.MIDI_CountEvts(take)
        for ci = cur_cccnt - 1, 0, -1 do
            local ok, _, _, ppq, chanmsg, chan, msg2 = reaper.MIDI_GetCC(take, ci)
            if ok then
                local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                if is_pc or is_bank then
                    local belongs_to_del = false
                    for _, dn in ipairs(deleted_note_infos) do
                        if dn.chan == chan and math.abs(dn.sppq - ppq) <= 25 then
                            belongs_to_del = true
                            break
                        end
                    end
                    if belongs_to_del then
                        local has_rem_note = false
                        for ni = 0, cur_notecnt - 1 do
                            local ok_n, _, _, r_sppq, _, r_chan = reaper.MIDI_GetNote(take, ni)
                            if ok_n and r_chan == chan and math.abs(r_sppq - ppq) <= 20 then
                                has_rem_note = true
                                break
                            end
                        end
                        if not has_rem_note then
                            reaper.MIDI_DeleteCC(take, ci)
                        end
                    end
                end
            end
        end
        
        -- 5. Auto-chase articulations: retrigger chase event at end of remaining passage and remove obsolete ones!
        MidiService.auto_chase_momentary_articulations(take, bank)
        reaper.MIDI_Sort(take)
    end
    
    reaper.Undo_EndBlock2(0, string.format("Notator: Delete %d notes", del_cnt), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    
    local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
    SlurService.remove_slurs_for_notes(state, targets)
    local PortamentoService = package.loaded["services.portamento_service"] or require("services.portamento_service")
    PortamentoService.remove_portamentos_for_notes(state, targets)
    local GlissandoService = package.loaded["services.glissando_service"] or require("services.glissando_service")
    GlissandoService.remove_glissandos_for_notes(state, targets)
    
    state.selected_notes = {}
    state.selected_note = nil
    state:clear_articulation_selection()
    state.status_msg = string.format("Deleted %d note(s)", del_cnt)
    return del_cnt
end

function MidiService.make_legato(state)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then
        state.status_msg = "No notes selected for legato"
        return 0
    end
    
    reaper.Undo_BeginBlock2(0)
    
    -- Group by take
    local by_take = {}
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not by_take[take] then by_take[take] = {} end
            table.insert(by_take[take], sn)
        end
    end
    
    local legato_cnt = 0
    for take, n_list in pairs(by_take) do
        -- Collect all notes in take and sort by start time
        local _, notecnt = reaper.MIDI_CountEvts(take)
        local all_notes = {}
        for i = 0, notecnt - 1 do
            local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
            if ok then
                table.insert(all_notes, { idx = i, sppq = sppq, eppq = eppq, pitch = pitch, chan = chan })
            end
        end
        table.sort(all_notes, function(a, b) return a.sppq < b.sppq end)
        
        -- For each selected note: find in take and extend up to next note
        for _, sn in ipairs(n_list) do
            local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn)
            
            -- Find the actual MIDI index
            local target_idx = nil
            local ok, sel3, muted3, start3, end3, chan3, pitch3, vel3 = reaper.MIDI_GetNote(take, sn.idx)
            if ok and pitch3 == sn.pitch and math.abs(start3 - sppq) < 15 then
                target_idx = sn.idx
            else
                for i = 0, notecnt - 1 do
                    ok, sel3, muted3, start3, end3, chan3, pitch3, vel3 = reaper.MIDI_GetNote(take, i)
                    if ok and pitch3 == sn.pitch and math.abs(start3 - sppq) < 15 then
                        target_idx = i
                        break
                    end
                end
            end
            
            if target_idx and ok then
                    -- Find next note (any pitch) that starts AFTER this note
                    local next_start = nil
                    for _, an in ipairs(all_notes) do
                        if an.sppq > start3 + 10 then
                            next_start = an.sppq
                            break
                        end
                    end
                    
                    if next_start and next_start > end3 then
                        reaper.MIDI_SetNote(take, target_idx, sel3, muted3, start3, next_start, chan3, pitch3, vel3, false)
                        legato_cnt = legato_cnt + 1
                    end
                end
            end
        reaper.MIDI_Sort(take)
    end
    
    reaper.Undo_EndBlock2(0, string.format("Notator: Make %d notes legato", legato_cnt), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    state.status_msg = string.format("Extended %d note(s) to legato", legato_cnt)
    return legato_cnt
end

function MidiService.quantize_notes(state, opts)
    opts = opts or {}
    local base_grid = opts.grid_qn or state.quantize_grid_qn or 0.25
    local grid_type = opts.grid_type or state.quantize_grid_type or "straight"
    local target = opts.target or state.quantize_target or "position" -- "position" | "length" | "both"
    local strength = (opts.strength or state.quantize_strength or 100) / 100.0
    local swing = (opts.swing or state.quantize_swing or 0) / 100.0
    local scope = opts.scope or state.quantize_scope or "selected" -- "selected" | "all"
    
    local eff_grid = base_grid
    if grid_type == "triplet" then
        eff_grid = base_grid * (2.0 / 3.0)
    elseif grid_type == "dotted" then
        eff_grid = base_grid * 1.5
    end
    if eff_grid <= 0.001 then eff_grid = 0.25 end
    
    local function snap_qn(qn, eff_g, sw)
        local raw_k = math.floor((qn / eff_g) + 0.5)
        local snapped = raw_k * eff_g
        if sw and math.abs(sw) > 0.001 and eff_g > 0.001 then
            if raw_k % 2 ~= 0 then
                snapped = snapped + (sw * eff_g * 0.3333)
            end
        end
        return snapped
    end
    
    local targets = {}
    if scope == "selected" then
        for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
        if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    end
    
    local active_take = nil
    if #targets == 0 then
        active_take = MidiService.get_active_midi_take()
        if not active_take then
            state.status_msg = "Quantize: Please select notes or a MIDI item first!"
            return 0
        end
        local _, notecnt = reaper.MIDI_CountEvts(active_take)
        local it = reaper.GetMediaItemTake_Item(active_take)
        local trk = it and reaper.GetMediaItemTrack(it)
        for i = 0, notecnt - 1 do
            local ok, _, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(active_take, i)
            if ok and not muted then
                local sqn = reaper.MIDI_GetProjQNFromPPQPos(active_take, sppq)
                local eqn = reaper.MIDI_GetProjQNFromPPQPos(active_take, eppq)
                table.insert(targets, {
                    idx = i, pitch = pitch, start_qn = sqn, end_qn = eqn,
                    dur_qn = eqn - sqn, vel = vel, chan = chan,
                    take = active_take, item = it, track = trk
                })
            end
        end
    end
    
    if #targets == 0 then
        state.status_msg = "Quantize: No notes found to quantize."
        return 0
    end
    
    reaper.Undo_BeginBlock2(0)
    
    local by_take = {}
    for _, sn in ipairs(targets) do
        local take = sn.take or active_take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not by_take[take] then by_take[take] = {} end
            table.insert(by_take[take], sn)
        end
    end
    
    local quant_cnt = 0
    local new_selected = {}
    
    for take, n_list in pairs(by_take) do
        reaper.MIDI_DisableSort(take)
        local _, notecnt = reaper.MIDI_CountEvts(take)
        
        for _, sn in ipairs(n_list) do
            local orig_sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn)
            local target_idx = nil
            local ok, _, muted, s_chk, _, chan, p_chk, vel = reaper.MIDI_GetNote(take, sn.idx)
            if ok and p_chk == sn.pitch and math.abs(s_chk - orig_sppq) < 15 then
                target_idx = sn.idx
            else
                for i = 0, notecnt - 1 do
                    local ok2, _, m2, s2, _, c2, p2, v2 = reaper.MIDI_GetNote(take, i)
                    if ok2 and p2 == sn.pitch and math.abs(s2 - orig_sppq) < 15 then
                        target_idx = i
                        ok, muted, s_chk, chan, p_chk, vel = ok2, m2, s2, c2, p2, v2
                        break
                    end
                end
            end
            
            if target_idx and ok then
                local orig_dur = sn.dur_qn or (sn.end_qn - sn.start_qn)
                local new_start_qn = sn.start_qn
                local new_end_qn = sn.end_qn
                
                if target == "position" or target == "both" then
                    local snapped_s = snap_qn(sn.start_qn, eff_grid, swing)
                    new_start_qn = sn.start_qn + (snapped_s - sn.start_qn) * strength
                    new_start_qn = math.max(0, new_start_qn)
                    if target == "position" then
                        new_end_qn = new_start_qn + orig_dur
                    end
                end
                
                if target == "length" or target == "both" then
                    local snapped_e = snap_qn(sn.end_qn, eff_grid, swing)
                    new_end_qn = sn.end_qn + (snapped_e - sn.end_qn) * strength
                    if new_end_qn < new_start_qn + 0.03125 then
                        new_end_qn = new_start_qn + 0.03125
                    end
                end
                
                local item = sn.item or reaper.GetMediaItemTake_Item(take)
                if item then
                    local it_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local it_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local it_start_qn = reaper.TimeMap2_timeToQN(0, it_pos)
                    local it_end_qn = reaper.TimeMap2_timeToQN(0, it_pos + it_len)
                    if new_start_qn < it_start_qn or new_end_qn > it_end_qn then
                        local expand_start = math.min(it_start_qn, new_start_qn)
                        local expand_end = math.max(it_end_qn, new_end_qn)
                        reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
                        reaper.MIDI_SetItemExtents(item, expand_start, expand_end)
                        reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
                    end
                end
                
                local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_start_qn)
                local eppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_end_qn)
                reaper.MIDI_SetNote(take, target_idx, true, muted, sppq, eppq, chan, sn.pitch, vel, true)
                
                local updated = MidiNote.new({
                    idx = target_idx, pitch = sn.pitch, start_qn = new_start_qn, end_qn = new_end_qn,
                    dur_qn = new_end_qn - new_start_qn, vel = vel, chan = chan, take = take,
                    item = item or sn.item, track = sn.track, articulation = sn.articulation
                })
                local new_k = updated:get_key()
                new_selected[new_k] = updated
                
                local old_k = sn.key or (sn.get_key and sn:get_key()) or string.format("%s_%s_%.3f_%d_%d", tostring(sn.item or item), tostring(take), sn.start_qn, sn.pitch, sn.chan or chan or 0)
                local old_id = string.format("%s_%s_%.3f", tostring(take), tostring(sn.idx), sn.start_qn)
                local old_pos = string.format("%s_%.3f_%d", tostring(take), sn.start_qn, sn.pitch)
                local new_id = string.format("%s_%s_%.3f", tostring(take), tostring(target_idx), new_start_qn)
                local new_pos = string.format("%s_%.3f_%d", tostring(take), new_start_qn, sn.pitch)
                if state.note_base_pitch then
                    local bp = state.note_base_pitch[old_k] or state.note_base_pitch[old_id] or state.note_base_pitch[old_pos]
                    if bp then
                        state.note_base_pitch[new_k] = bp
                        state.note_base_pitch[new_id] = bp
                        state.note_base_pitch[new_pos] = bp
                        state.note_base_pitch[old_k] = nil
                        state.note_base_pitch[old_id] = nil
                        state.note_base_pitch[old_pos] = nil
                    end
                end
                if state.note_accidentals then
                    local acc = state.note_accidentals[old_k] or state.note_accidentals[old_id] or state.note_accidentals[old_pos]
                    if acc ~= nil then
                        state.note_accidentals[new_k] = acc
                        state.note_accidentals[new_id] = acc
                        state.note_accidentals[new_pos] = acc
                        state.note_accidentals[old_k] = nil
                        state.note_accidentals[old_id] = nil
                        state.note_accidentals[old_pos] = nil
                    end
                end
                
                quant_cnt = quant_cnt + 1
            end
        end
        reaper.MIDI_Sort(take)
    end
    
    local glabel = opts.grid_label or state.quantize_grid_label or "1/16"
    reaper.Undo_EndBlock2(0, string.format("Notator: Quantize %d notes (%s)", quant_cnt, glabel), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    
    if scope == "selected" then
        state.selected_notes = new_selected
        for _, sn in pairs(new_selected) do state.selected_note = sn break end
    end
    
    state.status_msg = string.format("⚡ Quantized %d note(s) (grid: %s, strength: %d%%)", quant_cnt, glabel, math.floor(strength * 100))
    return quant_cnt
end

function MidiService.transpose_selected(state, semitones)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then return end
    
    reaper.Undo_BeginBlock2(0)
    local affected_takes = {}
    local take_transposed_notes = {}
    local new_selected = {}
    
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            affected_takes[take] = true
            local new_pitch = math.max(0, math.min(127, sn.pitch + semitones))
            local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn)
            local target_idx = nil
            local ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, sn.idx)
            if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 15 then
                target_idx = sn.idx
            else
                local _, notecnt = reaper.MIDI_CountEvts(take)
                for i = 0, notecnt - 1 do
                    ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, i)
                    if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 15 then
                        target_idx = i
                        break
                    end
                end
            end
            
            if target_idx and ok then
                reaper.MIDI_SetNote(take, target_idx, true, muted, s2, e2, chan, new_pitch, vel, false)
                take_transposed_notes[take] = take_transposed_notes[take] or {}
                table.insert(take_transposed_notes[take], { idx = target_idx, pitch = new_pitch, chan = chan, sppq = s2, eppq = e2 })

                local updated = MidiNote.new({
                    idx = target_idx, pitch = new_pitch, start_qn = sn.start_qn, end_qn = sn.end_qn,
                    dur_qn = sn.dur_qn, vel = vel, chan = chan, take = take, item = sn.item,
                    track = sn.track, articulation = sn.articulation
                })
                local new_k = updated:get_key()
                new_selected[new_k] = updated
                local old_k = sn:get_key()
                local old_id = string.format("%s_%s_%.3f", tostring(take), tostring(sn.idx), sn.start_qn)
                local old_pos = string.format("%s_%.3f_%d", tostring(take), sn.start_qn, sn.pitch)
                local new_id = string.format("%s_%s_%.3f", tostring(take), tostring(target_idx), sn.start_qn)
                local new_pos = string.format("%s_%.3f_%d", tostring(take), sn.start_qn, new_pitch)
                if state.note_base_pitch then
                    local bp = state.note_base_pitch[old_k] or state.note_base_pitch[old_id] or state.note_base_pitch[old_pos]
                    if bp then
                        state.note_base_pitch[new_k] = bp + semitones
                        state.note_base_pitch[new_id] = bp + semitones
                        state.note_base_pitch[new_pos] = bp + semitones
                        state.note_base_pitch[old_k] = nil
                        state.note_base_pitch[old_id] = nil
                        state.note_base_pitch[old_pos] = nil
                    end
                end
                if state.note_accidentals then
                    local acc = state.note_accidentals[old_k] or state.note_accidentals[old_id] or state.note_accidentals[old_pos]
                    if acc ~= nil then
                        state.note_accidentals[new_k] = acc
                        state.note_accidentals[new_id] = acc
                        state.note_accidentals[new_pos] = acc
                        state.note_accidentals[old_k] = nil
                        state.note_accidentals[old_id] = nil
                        state.note_accidentals[old_pos] = nil
                    end
                end
            end
        end
    end
    
    for tk, ref_list in pairs(take_transposed_notes) do
        MidiService.resolve_voice_conflicts(tk, ref_list)
    end
    for take in pairs(affected_takes) do reaper.MIDI_Sort(take) end
    reaper.Undo_EndBlock2(0, string.format("Notator: Transponieren %+d", semitones), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    
    state.selected_notes = new_selected
    for _, sn in pairs(new_selected) do 
        state.selected_note = sn 
        local AudioPreview = require("services.audio_preview")
        AudioPreview.play_note(state, sn.pitch, sn.vel, sn.chan, sn.track, sn.start_qn)
        break 
    end
end

function MidiService.apply_accidental_to_selected(state, acc_type)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then return end
    
    reaper.Undo_BeginBlock2(0)
    local affected_takes = {}
    local new_selected = {}
    local changed_cnt = 0
    
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            affected_takes[take] = true
            
            local p_mod = sn.pitch % 12
            local k_old = sn:get_key()
            local id_old = string.format("%s_%s_%.3f", tostring(take), tostring(sn.idx), sn.start_qn)
            local pos_old = string.format("%s_%.3f_%d", tostring(take), sn.start_qn, sn.pitch)
            local cur_pref = state.note_accidentals and (state.note_accidentals[k_old] or state.note_accidentals[id_old] or state.note_accidentals[pos_old])
            if cur_pref == nil then
                local p_info = Constants.PITCH_MAP[p_mod]
                cur_pref = p_info and p_info.acc or 0
            end
            
            -- Determine diatonic base pitch (natural note)
            local base_pitch = state.note_base_pitch and (state.note_base_pitch[k_old] or state.note_base_pitch[id_old] or state.note_base_pitch[pos_old])
            if not base_pitch then
                if cur_pref == 1 then
                    base_pitch = sn.pitch - 1
                elseif cur_pref == -1 then
                    base_pitch = sn.pitch + 1
                else
                    if p_mod == 1 or p_mod == 6 or p_mod == 8 then
                        base_pitch = sn.pitch - 1
                    elseif p_mod == 3 or p_mod == 10 then
                        base_pitch = sn.pitch + 1
                    else
                        base_pitch = sn.pitch
                    end
                end
            end
            
            local new_pitch = base_pitch
            local new_acc_pref = 0
            
            if acc_type == 1 then -- Sharp (♯) requested
                if cur_pref == 1 then
                    -- Note already has sharp -> toggle back to natural
                    new_pitch = base_pitch
                    new_acc_pref = 0
                else
                    new_pitch = base_pitch + 1
                    new_acc_pref = 1
                end
            elseif acc_type == -1 then -- Flat (♭) requested
                if cur_pref == -1 then
                    -- Note already has flat -> toggle back to natural
                    new_pitch = base_pitch
                    new_acc_pref = 0
                else
                    new_pitch = base_pitch - 1
                    new_acc_pref = -1
                end
            elseif acc_type == 0 then -- Natural (♮) requested
                new_pitch = base_pitch
                if cur_pref == 1 or cur_pref == -1 then
                    new_acc_pref = 0
                elseif cur_pref == 2 then
                    new_acc_pref = 0
                else
                    new_acc_pref = 2
                end
            end
            
            new_pitch = math.max(0, math.min(127, new_pitch))
            local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn)
            local target_idx = nil
            local ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, sn.idx)
            if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 50 then
                target_idx = sn.idx
            else
                local _, notecnt = reaper.MIDI_CountEvts(take)
                local best_i = nil
                local best_diff = 10000000
                for i = 0, notecnt - 1 do
                    local ok_i, _, m_i, s_i, e_i, ch_i, p_i, v_i = reaper.MIDI_GetNote(take, i)
                    if ok_i and p_i == sn.pitch then
                        local diff = math.abs(s_i - sppq)
                        if diff < best_diff then
                            best_diff = diff
                            best_i = i
                        end
                    end
                end
                if best_i then
                    target_idx = best_i
                    ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, target_idx)
                end
            end
            
            if target_idx and ok then
                reaper.MIDI_SetNote(take, target_idx, true, muted, s2, e2, chan, new_pitch, vel, false)
                local it = sn.item or reaper.GetMediaItemTake_Item(take)
                if it and reaper.ValidatePtr(it, "MediaItem*") then
                    reaper.UpdateItemInProject(it)
                end
                local updated = MidiNote.new({
                    idx = target_idx, pitch = new_pitch, start_qn = sn.start_qn, end_qn = sn.end_qn,
                    dur_qn = sn.dur_qn, vel = vel, chan = chan, take = take, item = it,
                    track = sn.track, articulation = sn.articulation
                })
                local new_k = updated:get_key()
                new_selected[new_k] = updated
                local new_id_k = string.format("%s_%s_%.3f", tostring(take), tostring(target_idx), sn.start_qn)
                local new_pos_k = string.format("%s_%.3f_%d", tostring(take), sn.start_qn, new_pitch)
                
                if state.note_base_pitch then
                    if sn.pitch ~= new_pitch then
                        state.note_base_pitch[pos_old] = nil
                        state.note_base_pitch[k_old] = nil
                        state.note_base_pitch[id_old] = nil
                    end
                    state.note_base_pitch[new_k] = base_pitch
                    state.note_base_pitch[new_id_k] = base_pitch
                    state.note_base_pitch[new_pos_k] = base_pitch
                end
                
                if state.note_accidentals then
                    -- Clean old position key if pitch changed
                    if sn.pitch ~= new_pitch then
                        state.note_accidentals[pos_old] = nil
                        state.note_accidentals[k_old] = nil
                        state.note_accidentals[id_old] = nil
                    end
                    state.note_accidentals[new_k] = new_acc_pref
                    state.note_accidentals[new_id_k] = new_acc_pref
                    state.note_accidentals[new_pos_k] = new_acc_pref
                end
                state.accidental = (new_acc_pref == 2) and 0 or new_acc_pref
                changed_cnt = changed_cnt + 1
            end
        end
    end
    
    for take in pairs(affected_takes) do
        reaper.MIDI_Sort(take)
        -- Update indices after sorting
        local _, notecnt_after = reaper.MIDI_CountEvts(take)
        for _, sn_up in pairs(new_selected) do
            if sn_up.take == take then
                local up_sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn_up.start_qn)
                local best_ni = nil
                local min_d = 10000000
                for ni = 0, notecnt_after - 1 do
                    local ok_n, _, _, s_n, _, _, p_n = reaper.MIDI_GetNote(take, ni)
                    if ok_n and p_n == sn_up.pitch then
                        local d = math.abs(s_n - up_sppq)
                        if d < min_d then
                            min_d = d
                            best_ni = ni
                        end
                    end
                end
                if best_ni then
                    sn_up.idx = best_ni
                    local re_id_k = string.format("%s_%s_%.3f", tostring(take), tostring(best_ni), sn_up.start_qn)
                    if state.note_accidentals and state.note_accidentals[sn_up:get_key()] ~= nil then
                        state.note_accidentals[re_id_k] = state.note_accidentals[sn_up:get_key()]
                    end
                    if state.note_base_pitch and state.note_base_pitch[sn_up:get_key()] ~= nil then
                        state.note_base_pitch[re_id_k] = state.note_base_pitch[sn_up:get_key()]
                    end
                end
            end
        end
    end
    local acc_name = (acc_type == 1 and "♯ Sharp") or (acc_type == -1 and "♭ Flat") or "♮ Natural"
    reaper.Undo_EndBlock2(0, "Notator: " .. acc_name, -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    
    if changed_cnt > 0 then
        state.selected_notes = new_selected
        for _, sn in pairs(new_selected) do state.selected_note = sn break end
    end
    state.status_msg = string.format("%s auf %d Note(n) angewendet", acc_name, changed_cnt)
end

function MidiService.move_selected_qn(state, delta_qn)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then return end
    
    -- Prevent moving before QN 0
    for _, sn in ipairs(targets) do
        if sn.start_qn + delta_qn < 0 then
            delta_qn = -sn.start_qn
        end
    end
    if math.abs(delta_qn) < 0.001 then return end
    
    reaper.Undo_BeginBlock2(0)
    local affected_takes = {}
    local take_moved_notes = {}
    local new_selected = {}
    
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not affected_takes[take] then
                affected_takes[take] = true
                reaper.MIDI_DisableSort(take)
            end
            local new_start_qn = math.max(0, sn.start_qn + delta_qn)
            local new_end_qn = new_start_qn + sn.dur_qn
            
            -- Check item boundaries and expand if necessary with B_LOOPSRC = 0
            local item = reaper.GetMediaItemTake_Item(take)
            if item then
                local it_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local it_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local it_start_qn = reaper.TimeMap2_timeToQN(0, it_pos)
                local it_end_qn = reaper.TimeMap2_timeToQN(0, it_pos + it_len)
                if new_start_qn < it_start_qn or new_end_qn > it_end_qn then
                    local expand_start = math.min(it_start_qn, new_start_qn)
                    local expand_end = math.max(it_end_qn, new_end_qn)
                    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
                    reaper.MIDI_SetItemExtents(item, expand_start, expand_end)
                    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
                end
            end
            
            local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_start_qn)
            local eppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_end_qn)
            local orig_sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn)
            
            local target_idx = nil
            local ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, sn.idx)
            if ok and p2 == sn.pitch and math.abs(s2 - orig_sppq) < 15 then
                target_idx = sn.idx
            else
                local _, notecnt = reaper.MIDI_CountEvts(take)
                for i = 0, notecnt - 1 do
                    ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, i)
                    if ok and p2 == sn.pitch and math.abs(s2 - orig_sppq) < 15 then
                        target_idx = i
                        break
                    end
                end
            end
            
            if target_idx and ok then
                reaper.MIDI_SetNote(take, target_idx, true, muted, sppq, eppq, chan, p2, vel, false)
                take_moved_notes[take] = take_moved_notes[take] or {}
                table.insert(take_moved_notes[take], { idx = target_idx, pitch = p2, chan = chan, sppq = sppq, eppq = eppq })
                
                local updated = MidiNote.new({
                    idx = target_idx, pitch = p2, start_qn = new_start_qn, end_qn = new_end_qn,
                    dur_qn = sn.dur_qn, vel = vel, chan = chan, take = take, item = item or sn.item,
                    track = sn.track, articulation = sn.articulation
                })
                new_selected[updated:get_key()] = updated
            end
        end
    end
    
    for tk, ref_list in pairs(take_moved_notes) do
        MidiService.resolve_voice_conflicts(tk, ref_list)
    end
    for take in pairs(affected_takes) do reaper.MIDI_Sort(take) end
    reaper.Undo_EndBlock2(0, string.format("Notator: Move notes horizontally %+g QN", delta_qn), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    
    state.selected_notes = new_selected
    for _, sn in pairs(new_selected) do state.selected_note = sn break end
    state.status_msg = string.format("Moved %d note(s) by %+g QN on grid", #targets, delta_qn)
end

function MidiService.delta_selected_duration(state, delta_qn)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then return end
    
    local min_dur = 0.0625 -- Minimum duration: 1/64
    reaper.Undo_BeginBlock2(0)
    local affected_takes = {}
    local changed_cnt = 0
    
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            affected_takes[take] = true
            local new_dur = math.max(min_dur, sn.dur_qn + delta_qn)
            local new_end_qn = sn.start_qn + new_dur
            
            -- Check item boundaries and expand if necessary with B_LOOPSRC = 0
            local item = reaper.GetMediaItemTake_Item(take)
            if item then
                local it_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local it_len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local it_start_qn = reaper.TimeMap2_timeToQN(0, it_pos)
                local it_end_qn = reaper.TimeMap2_timeToQN(0, it_pos + it_len)
                if new_end_qn > it_end_qn then
                    local expand_end = math.max(it_end_qn, new_end_qn)
                    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
                    reaper.MIDI_SetItemExtents(item, it_start_qn, expand_end)
                    reaper.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
                end
            end
            
            local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn)
            local eppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_end_qn)
            
            local target_idx = nil
            local ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, sn.idx)
            if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 15 then
                target_idx = sn.idx
            else
                local _, notecnt = reaper.MIDI_CountEvts(take)
                for i = 0, notecnt - 1 do
                    ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, i)
                    if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 15 then
                        target_idx = i
                        break
                    end
                end
            end
            
            if target_idx and ok then
                reaper.MIDI_SetNote(take, target_idx, true, muted, sppq, eppq, chan, p2, vel, false)
                sn.end_qn = new_end_qn
                sn.dur_qn = new_dur
                changed_cnt = changed_cnt + 1
                if delta_qn > 0 then
                    take_expanded_notes = take_expanded_notes or {}
                    take_expanded_notes[take] = take_expanded_notes[take] or {}
                    table.insert(take_expanded_notes[take], { idx = target_idx, pitch = p2, chan = chan, sppq = sppq, eppq = eppq })
                end
            end
        end
    end
    
    if take_expanded_notes then
        for tk, ref_list in pairs(take_expanded_notes) do
            MidiService.resolve_voice_conflicts(tk, ref_list)
        end
    end
    for take in pairs(affected_takes) do reaper.MIDI_Sort(take) end
    reaper.Undo_EndBlock2(0, string.format("Notator: Change note length %+g QN", delta_qn), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    state.status_msg = string.format("Changed %d note(s) by %+g QN on grid", changed_cnt, delta_qn)
end

function MidiService.change_selected_duration(state, new_dur_qn)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then return end
    
    reaper.Undo_BeginBlock2(0)
    local affected_takes = {}
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            affected_takes[take] = true
            local final_dur = new_dur_qn
            if state.is_dotted then final_dur = final_dur * 1.5 end
            if state.get_tuplet_factor then
                final_dur = final_dur * state:get_tuplet_factor()
            elseif state.is_triplet then
                final_dur = final_dur * (2/3)
            end
            
            local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn)
            local eppq = reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn + final_dur)
            
            local target_idx = nil
            local ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, sn.idx)
            if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 15 then
                target_idx = sn.idx
            else
                local _, notecnt = reaper.MIDI_CountEvts(take)
                for i = 0, notecnt - 1 do
                    ok, _, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, i)
                    if ok and p2 == sn.pitch and math.abs(s2 - sppq) < 15 then
                        target_idx = i
                        break
                    end
                end
            end
            
            if target_idx and ok then
                reaper.MIDI_SetNote(take, target_idx, true, muted, sppq, eppq, chan, p2, vel, false)
                sn.end_qn = sn.start_qn + final_dur
                sn.dur_qn = final_dur
            end
        end
    end
    for take in pairs(affected_takes) do reaper.MIDI_Sort(take) end
    reaper.Undo_EndBlock2(0, "Notator: Change note duration", -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    state.status_msg = string.format("Changed duration for %d note(s) (%.3f QN)", #targets, new_dur_qn)
end

function MidiService.convert_selected_to_tuplet(state, tuplet_type, active_tracks_data)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then return false end
    
    table.sort(targets, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.005 then return a.start_qn < b.start_qn end
        return a.pitch < b.pitch
    end)
    
    local Constants = require("constants")
    local count = #targets
    local min_start_qn = targets[1].start_qn
    local base_dur = state.active_dur or 1.0
    local def = Constants.TUPLET_DEFS and Constants.TUPLET_DEFS[tostring(tuplet_type)]
    local factor = def and def.factor or (state.get_tuplet_factor and state:get_tuplet_factor() or (2.0 / 3.0))
    local tuplet_dur = base_dur * factor
    
    reaper.Undo_BeginBlock2(0)
    local affected_takes = {}
    for idx, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            affected_takes[take] = true
            local new_sqn = min_start_qn + (idx - 1) * tuplet_dur
            local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_sqn)
            local eppq = reaper.MIDI_GetPPQPosFromProjQN(take, new_sqn + tuplet_dur)
            
            local ok, sel, muted, s2, e2, chan, p2, vel = reaper.MIDI_GetNote(take, sn.idx)
            if ok then
                reaper.MIDI_SetNote(take, sn.idx, true, muted, sppq, eppq, chan, p2, vel, true)
                sn.start_qn = new_sqn
                sn.end_qn = new_sqn + tuplet_dur
                sn.dur_qn = tuplet_dur
            end
        end
    end
    for take in pairs(affected_takes) do reaper.MIDI_Sort(take) end
    local tname = Constants.TUPLET_DEFS and Constants.TUPLET_DEFS[tostring(tuplet_type)] and Constants.TUPLET_DEFS[tostring(tuplet_type)].name or "Tuplet"
    reaper.Undo_EndBlock2(0, string.format("Notator: Convert %d notes to %s", count, tname), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    MidiService.sync_selection_to_reaper(state, active_tracks_data)
    state.status_msg = string.format("✨ Converted %d notes to %s (%.3f QN per note)", count, tname, tuplet_dur)
    return true
end

function MidiService.create_tuplet_at_cursor(state, opt_tuplet_type, active_tracks_data)
    local tuplet_type = opt_tuplet_type or state.tuplet_type or "3"
    state:set_tuplet_type(tuplet_type)
    
    local Constants = require("constants")
    local def = Constants.TUPLET_DEFS and Constants.TUPLET_DEFS[tostring(tuplet_type)]
    local count = def and def.ratio_num or 3
    local factor = def and def.factor or (2.0 / 3.0)
    
    -- If notes are already selected: convert them directly!
    local sel_cnt = state:count_selected_notes()
    if sel_cnt > 0 then
        return MidiService.convert_selected_to_tuplet(state, tuplet_type, active_tracks_data)
    end
    
    local track = state.focused_track or reaper.GetSelectedTrack(0, 0)
    if not track then
        local take = MidiService.get_active_midi_take()
        if take then track = get_track_from_take(take) end
    end
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        state.status_msg = "Tuplet: Please select a track first!"
        return false
    end
    
    local cur_time = reaper.GetCursorPosition()
    local start_qn = reaper.TimeMap2_timeToQN(0, cur_time)
    
    local base_dur = state.active_dur or 1.0
    local tuplet_dur = base_dur * factor
    local total_span = count * tuplet_dur
    
    local item, take = MidiService.get_or_create_item_at_qn(track, start_qn, total_span)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return false end
    
    local oct = state.current_octave or 4
    local default_pitch = math.max(0, math.min(127, (oct + 1) * 12)) -- C in current octave register
    
    reaper.Undo_BeginBlock2(0)
    reaper.MIDI_DisableSort(take)
    state.selected_notes = {}
    state.selected_note = nil
    
    local first_note = nil
    for i = 0, count - 1 do
        local n_qn = start_qn + (i * tuplet_dur)
        local n_obj = MidiService.insert_note(take, n_qn, default_pitch, tuplet_dur, 96, 0, nil)
        if n_obj and i == 0 then
            first_note = n_obj
        end
    end
    reaper.MIDI_Sort(take)
    if first_note then
        state:select_note(first_note)
    end
    local tname = def and def.name or string.format("%d-tuplet", count)
    reaper.Undo_EndBlock2(0, string.format("Notator: Create %s (%d-tuplet) at cursor", tname, count), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache(track)
    MidiService.sync_selection_to_reaper(state, active_tracks_data)
    
    state.status_msg = string.format("✨ Created %s (%d notes) at measure %.2f - fill with Step Input (C..B) or Draw!", tname, count, (start_qn / 4) + 1)
    return true
end

function MidiService.auto_chase_momentary_articulations(take, opt_bank)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end
    
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser.get_all_banks()
    local trk = get_track_from_take(take)
    local bank = opt_bank
    if not bank and trk then
        bank = ReaticulateParser.get_bank_for_track(trk, all_banks)
    end
    
    -- 1. Read all notes and text/CC events from take
    local _, notecnt, cccnt, textcnt = reaper.MIDI_CountEvts(take)
    if notecnt == 0 then
        -- All notes deleted: clean up all chase events and orphaned articulation events on this empty take
        local _, _, cur_cc_cnt, cur_text_cnt = reaper.MIDI_CountEvts(take)
        for ti = cur_text_cnt - 1, 0, -1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
            if ok and etype == 15 then
                if msg:match("^NOTATOR_CHASE") or msg:match("^NOTE%s+%d+%s+%d+%s+a%s+") then
                    reaper.MIDI_DeleteTextSysexEvt(take, ti)
                end
            end
        end
        local _, _, cur_cc_cnt2 = reaper.MIDI_CountEvts(take)
        for ci = cur_cc_cnt2 - 1, 0, -1 do
            local ok, _, _, ppq, chanmsg, chan, msg2 = reaper.MIDI_GetCC(take, ci)
            if ok then
                local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                if is_pc or is_bank then
                    reaper.MIDI_DeleteCC(take, ci)
                end
            end
        end
        return
    end
    
    local notes_by_chan = {}
    for ni = 0, notecnt - 1 do
        local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
        if ok and not muted then
            if not notes_by_chan[chan] then notes_by_chan[chan] = {} end
            table.insert(notes_by_chan[chan], { idx = ni, sppq = sppq, eppq = eppq, chan = chan, pitch = pitch })
        end
    end
    
    local note_arts_list = {}
    local chase_evts_list = {}
    local slur_ranges_by_chan = {}
    for ti = 0, textcnt - 1 do
        local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
        if ok and etype == 15 then
            local p, ch, art = msg:match("NOTE%s+(%d+)%s+(%d+)%s+a%s+([%a%d_]+)")
            if p and art then
                table.insert(note_arts_list, { ppq = ppq, pitch = tonumber(p), chan = tonumber(ch) or 0, art = art })
            end
            local ch_c, pc_c = msg:match("NOTATOR_CHASE%s+(%d+)%s+(%d+)")
            if ch_c and pc_c then
                table.insert(chase_evts_list, { idx = ti, ppq = ppq, chan = tonumber(ch_c), pc = tonumber(pc_c) })
            end
            local s_id, s_chan, p1, p2, sqn, n2sqn, odur, pre_pc, pre_msb, pre_lsb = msg:match("^NOTATOR_SLUR%s+([%w_]+)%s+(%d+)%s+(%d+)%s+(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*(%-?%d*)%s*(%-?%d*)%s*(%-?%d*)")
            if s_id then
                local ch = tonumber(s_chan) or 0
                if not slur_ranges_by_chan[ch] then slur_ranges_by_chan[ch] = {} end
                local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, tonumber(sqn)) + 0.5)
                local eppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, tonumber(n2sqn)) + 0.5)
                local eff_pc = (pre_pc and pre_pc ~= "") and tonumber(pre_pc) or nil
                if eff_pc and (eff_pc < 0 or eff_pc > 127) then eff_pc = nil end
                table.insert(slur_ranges_by_chan[ch], {
                    id = s_id,
                    sppq = sppq,
                    eppq = eppq,
                    pre_pc = eff_pc,
                    pre_msb = (pre_msb and pre_msb ~= "") and tonumber(pre_msb) or -1,
                    pre_lsb = (pre_lsb and pre_lsb ~= "") and tonumber(pre_lsb) or -1
                })
            end
        end
    end
    
    local pcs_by_chan = {}
    local cur_msb = {}
    local cur_lsb = {}
    for ci = 0, cccnt - 1 do
        local ok, _, _, ppq, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(take, ci)
        if ok then
            if (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and msg2 == 0 then
                cur_msb[chan] = msg3
            elseif (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and msg2 == 32 then
                cur_lsb[chan] = msg3
            elseif (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0) then
                if not pcs_by_chan[chan] then pcs_by_chan[chan] = {} end
                local eff_msb = cur_msb[chan] or (bank and bank.msb and bank.msb >= 0 and bank.msb) or -1
                local eff_lsb = cur_lsb[chan] or (bank and bank.lsb and bank.lsb >= 0 and bank.lsb) or -1
                table.insert(pcs_by_chan[chan], {
                    idx = ci,
                    ppq = ppq,
                    chan = chan,
                    pc = msg2,
                    msb = eff_msb,
                    lsb = eff_lsb
                })
            end
        end
    end
    
    -- Determine most recent known MSB/LSB per channel
    local chan_latest_msb = {}
    local chan_latest_lsb = {}
    for chan, pc_list in pairs(pcs_by_chan) do
        table.sort(pc_list, function(a, b) return a.ppq < b.ppq end)
        for _, p in ipairs(pc_list) do
            if p.msb >= 0 then chan_latest_msb[chan] = p.msb end
            if p.lsb >= 0 then chan_latest_lsb[chan] = p.lsb end
        end
    end
    
    local function is_momentary(art_name, pc)
        if bank and bank.articulations then
            if art_name then
                local art_match = MidiService.find_reaticulate_art_for_id(bank, art_name)
                if art_match and MidiService.is_momentary_articulation(art_match.name or art_name) then
                    return true
                end
            end
            if pc then
                for _, ba in ipairs(bank.articulations) do
                    if ba.pc == pc then
                        if MidiService.is_momentary_articulation(ba.name) then
                            return true
                        end
                        break
                    end
                end
            end
            return false
        else
            if art_name and MidiService.is_momentary_articulation(art_name) then return true end
            return false
        end
    end
    
    -- 2. Determine default base articulation of the bank (e.g. PC 1 / Long / Sustain)
    local default_base_art = nil
    if bank and bank.articulations then
        for _, ba in ipairs(bank.articulations) do
            if not is_momentary(ba.name, ba.pc) then
                default_base_art = {
                    pc = ba.pc,
                    msb = (bank.msb and bank.msb >= 0) and bank.msb or -1,
                    lsb = (bank.lsb and bank.lsb >= 0) and bank.lsb or -1,
                    name = ba.name
                }
                break
            end
        end
        if not default_base_art and #bank.articulations > 0 then
            local first_ba = bank.articulations[1]
            default_base_art = {
                pc = first_ba.pc,
                msb = (bank.msb and bank.msb >= 0) and bank.msb or -1,
                lsb = (bank.lsb and bank.lsb >= 0) and bank.lsb or -1,
                name = first_ba.name
            }
        end
    end
    
    -- 3. Determine per channel where a momentary articulation (e.g. Marcato/Staccato/Slur) ends
    local needed_chase_at_ppq = {}
    for chan, n_list in pairs(notes_by_chan) do
        table.sort(n_list, function(a, b) return a.sppq < b.sppq end)
        
        local active_base = default_base_art and {
            pc = default_base_art.pc,
            msb = (default_base_art.msb >= 0) and default_base_art.msb or (chan_latest_msb[chan] or -1),
            lsb = (default_base_art.lsb >= 0) and default_base_art.lsb or (chan_latest_lsb[chan] or -1),
            name = default_base_art.name
        }
        local in_momentary = false
        local last_momentary_end_ppq = nil
        local last_active_slur = nil
        
        local function get_active_slur_at(ppq)
            local slurs = slur_ranges_by_chan[chan]
            if not slurs then return nil end
            for _, sl in ipairs(slurs) do
                if ppq >= sl.sppq - 15 and ppq <= sl.eppq + 15 then
                    return sl
                end
            end
            return nil
        end
        
        for idx, n in ipairs(n_list) do
            -- Check all program changes that occurred before or at this note
            if pcs_by_chan[chan] then
                for _, pc_ev in ipairs(pcs_by_chan[chan]) do
                    if pc_ev.ppq <= n.sppq + 15 then
                        local is_this_chase = false
                        for _, ce in ipairs(chase_evts_list) do
                            if ce.chan == chan and math.abs(ce.ppq - pc_ev.ppq) <= 15 and ce.pc == pc_ev.pc then
                                is_this_chase = true
                                break
                            end
                        end
                        local is_slur_pc = (get_active_slur_at(pc_ev.ppq) ~= nil)
                        if not is_this_chase and not is_momentary(nil, pc_ev.pc) and not is_slur_pc then
                            active_base = {
                                pc = pc_ev.pc,
                                msb = (pc_ev.msb >= 0) and pc_ev.msb or (chan_latest_msb[chan] or -1),
                                lsb = (pc_ev.lsb >= 0) and pc_ev.lsb or (chan_latest_lsb[chan] or -1),
                            }
                        end
                    end
                end
            end
            
            -- Check if this note is momentary articulated (via type 15 text, slur range, or PC at note start)
            local is_mom = false
            local cur_slur = get_active_slur_at(n.sppq)
            if cur_slur then
                is_mom = true
                last_active_slur = cur_slur
            end
            
            if not is_mom then
                for _, na in ipairs(note_arts_list) do
                    if na.pitch == n.pitch and math.abs(na.ppq - n.sppq) <= 25 then
                        if is_momentary(na.art, nil) then
                            is_mom = true
                            break
                        end
                    end
                end
            end
            if not is_mom and pcs_by_chan[chan] then
                for _, pc_ev in ipairs(pcs_by_chan[chan]) do
                    if math.abs(pc_ev.ppq - n.sppq) <= 25 and is_momentary(nil, pc_ev.pc) then
                        is_mom = true
                        break
                    end
                end
            end
            -- If the note starts while a previous momentary note is still sounding (e.g. tie across barline):
            if not is_mom and in_momentary and last_momentary_end_ppq and n.sppq < last_momentary_end_ppq - 10 then
                is_mom = true
            end
            
            if is_mom then
                in_momentary = true
                if not last_momentary_end_ppq or n.eppq > last_momentary_end_ppq then
                    last_momentary_end_ppq = n.eppq
                end
            else
                if in_momentary and (not last_momentary_end_ppq or n.sppq >= last_momentary_end_ppq - 15) then
                    -- Momentary articulation passage ended here!
                    -- Place return chase immediately after momentary passage ends
                    local return_base = active_base
                    if last_active_slur and last_active_slur.pre_pc and last_active_slur.pre_pc >= 0 and last_active_slur.pre_pc <= 127 then
                        return_base = {
                            pc = last_active_slur.pre_pc,
                            msb = (last_active_slur.pre_msb and last_active_slur.pre_msb >= 0) and last_active_slur.pre_msb or (chan_latest_msb[chan] or -1),
                            lsb = (last_active_slur.pre_lsb and last_active_slur.pre_lsb >= 0) and last_active_slur.pre_lsb or (chan_latest_lsb[chan] or -1),
                        }
                    end
                    
                    if return_base and return_base.pc and return_base.pc >= 0 and return_base.pc <= 127 then
                        local chase_ppq = (last_momentary_end_ppq and (last_momentary_end_ppq + 10 < n.sppq)) and (last_momentary_end_ppq + 10) or n.sppq
                        local chase_k = string.format("%d_%d", math.floor(chase_ppq + 0.5), chan)
                        local eff_m = (return_base.msb and return_base.msb >= 0) and return_base.msb or (chan_latest_msb[chan] or -1)
                        local eff_l = (return_base.lsb and return_base.lsb >= 0) and return_base.lsb or (chan_latest_lsb[chan] or -1)
                        needed_chase_at_ppq[chase_k] = {
                            sppq = chase_ppq,
                            chan = chan,
                            pc = return_base.pc,
                            msb = eff_m,
                            lsb = eff_l
                        }
                    end
                    in_momentary = false
                    last_active_slur = nil
                end
            end
        end
        
        -- If the take ends inside a momentary articulation, restore base articulation right at the end of the note/bar
        if in_momentary and last_momentary_end_ppq then
            local return_base = active_base
            if last_active_slur and last_active_slur.pre_pc and last_active_slur.pre_pc >= 0 and last_active_slur.pre_pc <= 127 then
                return_base = {
                    pc = last_active_slur.pre_pc,
                    msb = (last_active_slur.pre_msb and last_active_slur.pre_msb >= 0) and last_active_slur.pre_msb or (chan_latest_msb[chan] or -1),
                    lsb = (last_active_slur.pre_lsb and last_active_slur.pre_lsb >= 0) and last_active_slur.pre_lsb or (chan_latest_lsb[chan] or -1),
                }
            end
            if return_base and return_base.pc and return_base.pc >= 0 and return_base.pc <= 127 then
                local chase_ppq = last_momentary_end_ppq + 10
                local chase_k = string.format("%d_%d", math.floor(chase_ppq + 0.5), chan)
                local eff_m = (return_base.msb and return_base.msb >= 0) and return_base.msb or (chan_latest_msb[chan] or -1)
                local eff_l = (return_base.lsb and return_base.lsb >= 0) and return_base.lsb or (chan_latest_lsb[chan] or -1)
                needed_chase_at_ppq[chase_k] = {
                    sppq = chase_ppq,
                    chan = chan,
                    pc = return_base.pc,
                    msb = eff_m,
                    lsb = eff_l
                }
            end
        end
    end
    
    -- 4. Delete obsolete chase events
    local _, _, cur_cc_cnt, cur_text_cnt = reaper.MIDI_CountEvts(take)
    for ti = cur_text_cnt - 1, 0, -1 do
        local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
        if ok and etype == 15 then
            local ch_c, pc_c = msg:match("NOTATOR_CHASE%s+(%d+)%s+(%-?%d+)")
            if ch_c and pc_c then
                local num_pc = tonumber(pc_c)
                local k = string.format("%d_%d", math.floor(ppq + 0.5), tonumber(ch_c))
                local needed = needed_chase_at_ppq[k]
                if not needed or needed.pc ~= num_pc or not num_pc or num_pc < 0 or num_pc > 127 then
                    reaper.MIDI_DeleteTextSysexEvt(take, ti)
                    local _, _, cur_ccs = reaper.MIDI_CountEvts(take)
                    for ci = cur_ccs - 1, 0, -1 do
                        local ok_c, _, _, c_ppq, chanmsg, c_chan, msg2 = reaper.MIDI_GetCC(take, ci)
                        if ok_c and math.abs(c_ppq - ppq) <= 25 and c_chan == tonumber(ch_c) then
                            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                            local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                            if is_pc and (msg2 == num_pc or (num_pc and num_pc < 0 and msg2 == 127)) then
                                reaper.MIDI_DeleteCC(take, ci)
                            elseif is_bank then
                                reaper.MIDI_DeleteCC(take, ci)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- 5. Insert required chase events (with full bank select CC0 + CC32 + Program Change)
    for k, needed in pairs(needed_chase_at_ppq) do
        local _, _, upd_cc_cnt = reaper.MIDI_CountEvts(take)
        local already_has_pc = false
        for ci = 0, upd_cc_cnt - 1 do
            local ok, _, _, ppq, chanmsg, chan, msg2 = reaper.MIDI_GetCC(take, ci)
            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
            if ok and math.abs(ppq - needed.sppq) <= 15 and chan == needed.chan and is_pc and msg2 == needed.pc then
                already_has_pc = true
                break
            end
        end
        
        if not already_has_pc then
            -- Remove any conflicting PCs at this position
            for ci = upd_cc_cnt - 1, 0, -1 do
                local ok, _, _, ppq, chanmsg, chan, msg2 = reaper.MIDI_GetCC(take, ci)
                if ok and math.abs(ppq - needed.sppq) <= 15 and chan == needed.chan then
                    local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                    local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                    if is_pc or is_bank then
                        reaper.MIDI_DeleteCC(take, ci)
                    end
                end
            end
            
            -- Full Reaticulate triggering: CC0 + CC32 + PC
            if needed.msb and needed.msb >= 0 then
                reaper.MIDI_InsertCC(take, false, false, needed.sppq, 0xB0, needed.chan, 0, needed.msb)
            end
            if needed.lsb and needed.lsb >= 0 then
                reaper.MIDI_InsertCC(take, false, false, needed.sppq, 0xB0, needed.chan, 32, needed.lsb)
            end
            reaper.MIDI_InsertCC(take, false, false, needed.sppq, 0xC0, needed.chan, needed.pc, 0)
            reaper.MIDI_InsertTextSysexEvt(take, false, false, needed.sppq, 15, string.format("NOTATOR_CHASE %d %d", needed.chan, needed.pc))
        end
    end
end

function MidiService.toggle_selected_articulation(state, art_id)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then return end
    
    local function normalize_art(a)
        if not a or a == "" or a == "none" then return nil end
        local low = tostring(a):lower()
        if low:find("staccatiss") or low:find("spicc") then return "staccatissimo"
        elseif low:find("stacc") or low:find("short 0%.5") then return "staccato"
        elseif low:find("marc") then return "marcato"
        elseif low:find("tenuto") or low == "ten" or low:find("short 1%.0") then return "tenuto"
        elseif low:find("accent") or low == "acc" then return "accent"
        elseif low:find("harm") or low:find("flag") then return "harmonic"
        elseif low:find("fermata") then return "fermata"
        elseif low:find("arpegg") or low:find("arp") then return "arpeggio"
        end
        return low
    end
    
    local norm_target = normalize_art(art_id)
    local is_clearing = (art_id == "none" or art_id == nil or norm_target == nil)
    
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser.get_all_banks()
    
    reaper.Undo_BeginBlock2(0)
    local by_take = {}
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not by_take[take] then by_take[take] = {} end
            table.insert(by_take[take], sn)
        end
    end
    
    local matched_reaticulate_name = nil
    
    for take, n_list in pairs(by_take) do
        local trk = get_track_from_take(take)
        local bank = trk and ReaticulateParser.get_bank_for_track(trk, all_banks)
        local art_match = bank and norm_target and MidiService.find_reaticulate_art_for_id(bank, norm_target)
        if art_match then
            matched_reaticulate_name = art_match.name
        end
        
        reaper.MIDI_DisableSort(take)
        local handled_pcs_at_ppq = {}
        
        for _, sn in ipairs(n_list) do
            local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn) + 0.5)
            if sn.idx and sn.idx >= 0 then
                local ok, _, _, s_ppq = reaper.MIDI_GetNote(take, sn.idx)
                if ok then sppq = s_ppq end
            end
            local chan = sn.chan or 0
            local ppq_key = string.format("%d_%d", sppq, chan)
            
            -- Always delete old type 15 notation events for this note (articulations and chase events)
            local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
            for ti = text_cnt - 1, 0, -1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 and math.abs(ppq - sppq) <= 35 then
                    local p = msg:match("NOTE%s+(%d+)")
                    if p and tonumber(p) == sn.pitch then
                        if msg:match("%s+a%s+") or msg:match("^NOTATOR_CHASE") then
                            reaper.MIDI_DeleteTextSysexEvt(take, ti)
                        end
                    elseif msg:match("^NOTATOR_CHASE%s+" .. tostring(chan)) then
                        reaper.MIDI_DeleteTextSysexEvt(take, ti)
                    end
                end
            end
            
            -- Always delete previous articulation PCs/bank selects at this PPQ on this channel
            if not handled_pcs_at_ppq[ppq_key] then
                handled_pcs_at_ppq[ppq_key] = true
                local _, _, cc_cnt = reaper.MIDI_CountEvts(take)
                for ci = cc_cnt - 1, 0, -1 do
                    local ok, _, _, ppq, chanmsg, cchan, msg2 = reaper.MIDI_GetCC(take, ci)
                    if ok and math.abs(ppq - sppq) <= 35 and cchan == chan then
                        local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                        local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                        if is_pc or is_bank then
                            reaper.MIDI_DeleteCC(take, ci)
                        end
                    end
                end
            end
            
            local norm_current = normalize_art(sn.articulation)
            local toggle_off = is_clearing or (norm_current and norm_current == norm_target)
            
            if toggle_off then
                sn.articulation = nil
            else
                local safe_art = norm_target or art_id
                reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, string.format("NOTE %d %d a %s", sn.pitch, chan, safe_art))
                sn.articulation = safe_art
                
                if art_match then
                    local eff_msb = (bank.msb and bank.msb >= 0) and bank.msb or -1
                    local eff_lsb = (bank.lsb and bank.lsb >= 0) and bank.lsb or -1
                    if eff_msb >= 0 then
                        reaper.MIDI_InsertCC(take, false, false, sppq, 0xB0, chan, 0, eff_msb)
                    end
                    if eff_lsb >= 0 then
                        reaper.MIDI_InsertCC(take, false, false, sppq, 0xB0, chan, 32, eff_lsb)
                    end
                    reaper.MIDI_InsertCC(take, false, false, sppq, 0xC0, chan, art_match.pc, 0)
                end
            end
        end
        
        MidiService.auto_chase_momentary_articulations(take, bank)
        reaper.MIDI_Sort(take)
    end
    
    reaper.Undo_EndBlock2(0, "Notator: Toggle Articulation", -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    if state.selected_note then
        state.active_articulation = state.selected_note.articulation
    end
    if is_clearing or (norm_target and #targets > 0 and targets[1].articulation == nil) then
        state.status_msg = string.format("Cleared articulation from %d note(s)", #targets)
    elseif matched_reaticulate_name then
        state.status_msg = string.format("Articulation '%s' (Reaticulate: %s) set for %d note(s)", norm_target or art_id, matched_reaticulate_name, #targets)
    else
        state.status_msg = string.format("Articulation '%s' set for %d note(s)", norm_target or art_id, #targets)
    end
end

function MidiService.toggle_arpeggio_on_selected(state, direction)
    direction = direction or "up"
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then
        state.status_msg = "Please select notes or a chord first!"
        return
    end

    local take = targets[1].take or MidiService.get_active_midi_take()
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end

    local base_qn = targets[1].start_qn
    if #targets == 1 then
        local _, notecnt = reaper.MIDI_CountEvts(take)
        for ni = 0, notecnt - 1 do
            local ok, _, _, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
            if ok then
                local n_qn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                if math.abs(n_qn - base_qn) < 0.08 then
                    local already = false
                    for _, t in ipairs(targets) do if t.pitch == pitch then already = true break end end
                    if not already then
                        table.insert(targets, MidiNote.new({
                            idx = ni, pitch = pitch, start_qn = n_qn, dur_qn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq) - n_qn,
                            chan = chan, vel = vel, take = take
                        }))
                    end
                end
            end
        end
    end

    if #targets < 2 then
        state.status_msg = "Arpeggio requires at least 2 chord notes!"
        return
    end

    local has_arp = false
    for _, sn in ipairs(targets) do
        if sn.arpeggio or sn.articulation == "arpeggio" then has_arp = true break end
    end

    reaper.Undo_BeginBlock2(0)
    reaper.MIDI_DisableSort(take)

    local min_ppq = 999999999
    for _, sn in ipairs(targets) do
        local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn) + 0.5)
        if sn.idx and sn.idx >= 0 then
            local ok, _, _, s_ppq = reaper.MIDI_GetNote(take, sn.idx)
            if ok then sppq = s_ppq end
        end
        if sppq < min_ppq then min_ppq = sppq end
    end

    -- Sort targets by pitch
    table.sort(targets, function(a, b)
        if direction == "down" then
            return a.pitch > b.pitch
        else
            return a.pitch < b.pitch
        end
    end)

    -- Clean existing NOTATOR_ARPEGGIO events near min_ppq
    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
    for text_i = text_cnt - 1, 0, -1 do
        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, text_i)
        if ok and ev_type == 15 and (msg:match("^NOTATOR_ARPEGGIO") or msg:match("a%s+arpeggio")) then
            if math.abs(ppq - min_ppq) < 80 then
                reaper.MIDI_DeleteTextSysexEvt(take, text_i)
            end
        end
    end

    local spread_ticks = 18 -- ~15ms strum step at 120 BPM

    for i, sn in ipairs(targets) do
        local target_sppq = has_arp and min_ppq or (min_ppq + (i - 1) * spread_ticks)

        local _, notecnt = reaper.MIDI_CountEvts(take)
        for ni = 0, notecnt - 1 do
            local ok, sel, muted, s_ppq, e_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
            if ok and pitch == sn.pitch and math.abs(s_ppq - min_ppq) < 80 then
                local new_sppq = target_sppq
                local new_eppq = math.max(new_sppq + 40, e_ppq)
                reaper.MIDI_SetNote(take, ni, sel, muted, new_sppq, new_eppq, chan, pitch, vel, false)

                if not has_arp then
                    reaper.MIDI_InsertTextSysexEvt(take, false, false, new_sppq, 15, string.format("NOTE %d %d a arpeggio", pitch, chan))
                end
                break
            end
        end
        sn.articulation = not has_arp and "arpeggio" or nil
        sn.arpeggio = not has_arp and direction or nil
    end

    if not has_arp then
        reaper.MIDI_InsertTextSysexEvt(take, false, false, min_ppq, 15, "NOTATOR_ARPEGGIO " .. direction)
    end

    reaper.MIDI_Sort(take)
    reaper.Undo_EndBlock2(0, has_arp and "Notator: Remove Arpeggio" or "Notator: Apply Arpeggio", -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    state.status_msg = has_arp and "Removed Arpeggio (Snapped to Grid)" or string.format("Applied Arpeggio (%s)", direction)
end

function MidiService.invert_selected_notes_stem_direction(state, target_dir)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then
        state.status_msg = "No notes selected for stem direction change"
        return
    end
    
    reaper.Undo_BeginBlock2(0)
    local by_take = {}
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not by_take[take] then by_take[take] = {} end
            table.insert(by_take[take], sn)
        end
    end
    
    if not state.note_stem_directions then
        state.note_stem_directions = {}
    end
    
    -- Determine default direction if invert was chosen for group
    local default_target = nil
    if target_dir == "invert" or not target_dir then
        local has_any_up = false
        for _, sn in ipairs(targets) do
            local k = sn:get_key()
            local cur_s = sn.stem_dir or state.note_stem_directions[k]
            if cur_s == "up" then
                has_any_up = true
                break
            end
        end
        -- If already set to Up, flip to Down, otherwise Up
        default_target = has_any_up and "down" or "up"
    end
    
    for take, n_list in pairs(by_take) do
        reaper.MIDI_DisableSort(take)
        for _, sn in ipairs(n_list) do
            local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn) + 0.5)
            local chan = sn.chan or 0
            
            -- Search existing type 15 stem event
            local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
            local found_ti = nil
            for ti = text_cnt - 1, 0, -1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 then
                    local p, ch, sdir = msg:match("NOTE%s+(%d+)%s+(%d+)%s+stem%s+([%a]+)")
                    if p and tonumber(p) == sn.pitch and math.abs(ppq - sppq) <= 25 then
                        found_ti = ti
                        reaper.MIDI_DeleteTextSysexEvt(take, ti)
                    end
                end
            end
            
            local k = sn:get_key()
            local id_k = string.format("%s_%s_%.3f", tostring(take), tostring(sn.idx or 0), sn.start_qn or 0)
            local pos_k = string.format("%s_%.3f_%d", tostring(take), sn.start_qn or 0, sn.pitch)
            
            local new_dir = nil
            if target_dir == "invert" or not target_dir then
                new_dir = default_target
            elseif target_dir == "up" then
                new_dir = "up"
            elseif target_dir == "down" then
                new_dir = "down"
            elseif target_dir == "auto" then
                new_dir = nil
            end
            
            if new_dir then
                reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, string.format("NOTE %d %d stem %s", sn.pitch, chan, new_dir))
                sn.stem_dir = new_dir
                state.note_stem_directions[k] = new_dir
                state.note_stem_directions[id_k] = new_dir
                state.note_stem_directions[pos_k] = new_dir
            else
                sn.stem_dir = nil
                state.note_stem_directions[k] = nil
                state.note_stem_directions[id_k] = nil
                state.note_stem_directions[pos_k] = nil
            end
        end
        reaper.MIDI_Sort(take)
    end
    
    local undo_title = "Notator: Change Stem Direction"
    if target_dir == "invert" then undo_title = "Notator: Invert Stem Direction"
    elseif target_dir == "up" then undo_title = "Notator: Force Stem Up"
    elseif target_dir == "down" then undo_title = "Notator: Force Stem Down"
    elseif target_dir == "auto" then undo_title = "Notator: Reset Stem Direction to Auto"
    end
    
    reaper.Undo_EndBlock2(0, undo_title, -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    
    if target_dir == "invert" then
        state.status_msg = string.format("Inverted stem direction for %d note(s) (now %s)", #targets, default_target)
    elseif target_dir == "auto" then
        state.status_msg = string.format("Reset stem direction to auto for %d note(s)", #targets)
    else
        state.status_msg = string.format("Set stem direction to '%s' for %d note(s)", tostring(target_dir), #targets)
    end
end

function MidiService.set_selected_notes_staff(state, target_staff)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    if #targets == 0 then
        state.status_msg = "No notes selected for staff assignment"
        return
    end
    
    reaper.Undo_BeginBlock2(0)
    local by_take = {}
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not by_take[take] then by_take[take] = {} end
            table.insert(by_take[take], sn)
        end
    end
    
    if not state.note_staff_assignments then
        state.note_staff_assignments = {}
    end
    
    -- Determine default staff if toggle was chosen
    local default_target = nil
    if target_staff == "toggle" or not target_staff then
        local has_any_treble = false
        for _, sn in ipairs(targets) do
            local k = sn.key or (sn.get_key and sn:get_key())
            local cur_st = sn.staff or (k and state.note_staff_assignments[k])
            if cur_st == nil then
                cur_st = (sn.pitch >= 60) and "treble" or "bass"
            end
            if cur_st == "treble" then
                has_any_treble = true
                break
            end
        end
        default_target = has_any_treble and "bass" or "treble"
    end
    
    for take, n_list in pairs(by_take) do
        reaper.MIDI_DisableSort(take)
        for _, sn in ipairs(n_list) do
            local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn) + 0.5)
            local chan = sn.chan or 0
            
            -- Search existing type 15 staff event
            local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
            for ti = text_cnt - 1, 0, -1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 then
                    local p, ch, stf = msg:match("NOTE%s+(%d+)%s+(%d+)%s+staff%s+([%a]+)")
                    if p and tonumber(p) == sn.pitch and math.abs(ppq - sppq) <= 25 then
                        reaper.MIDI_DeleteTextSysexEvt(take, ti)
                    end
                end
            end
            
            local k = sn.key or (sn.get_key and sn:get_key())
            local id_k = string.format("%s_%s_%.3f", tostring(take), tostring(sn.idx or 0), sn.start_qn or 0)
            local pos_k = string.format("%s_%.3f_%d", tostring(take), sn.start_qn or 0, sn.pitch)
            
            local new_st = nil
            if target_staff == "toggle" or not target_staff then
                new_st = default_target
            elseif target_staff == "treble" then
                new_st = "treble"
            elseif target_staff == "bass" then
                new_st = "bass"
            elseif target_staff == "auto" then
                new_st = nil
            end
            
            if new_st then
                reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, string.format("NOTE %d %d staff %s", sn.pitch, chan, new_st))
                sn.staff = new_st
                if k then state.note_staff_assignments[k] = new_st end
                state.note_staff_assignments[id_k] = new_st
                state.note_staff_assignments[pos_k] = new_st
            else
                sn.staff = nil
                if k then state.note_staff_assignments[k] = nil end
                state.note_staff_assignments[id_k] = nil
                state.note_staff_assignments[pos_k] = nil
            end
        end
        reaper.MIDI_Sort(take)
    end
    
    local undo_title = "Notator: Change Note Staff"
    if target_staff == "toggle" then undo_title = "Notator: Toggle Note Staff"
    elseif target_staff == "treble" then undo_title = "Notator: Move Note to Upper Staff (Treble)"
    elseif target_staff == "bass" then undo_title = "Notator: Move Note to Lower Staff (Bass)"
    elseif target_staff == "auto" then undo_title = "Notator: Reset Note Staff to Auto"
    end
    
    reaper.Undo_EndBlock2(0, undo_title, -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    
    if target_staff == "toggle" then
        state.status_msg = string.format("Moved %d note(s) to %s staff", #targets, (default_target == "treble" and "Upper (Treble)" or "Lower (Bass)"))
    elseif target_staff == "auto" then
        state.status_msg = string.format("Reset staff to Auto (split at Middle C) for %d note(s)", #targets)
    else
        state.status_msg = string.format("Moved %d note(s) to %s staff", #targets, (target_staff == "treble" and "Upper (Treble)" or "Lower (Bass)"))
    end
    state.status_time = reaper.time_precise()
end


function MidiService.get_target_item_and_take(state, active_tracks_data)
    if state.selected_item and reaper.ValidatePtr(state.selected_item, "MediaItem*") then
        local tk = state.selected_take or reaper.GetActiveTake(state.selected_item)
        if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") and reaper.TakeIsMIDI(tk) then
            local trk = reaper.GetMediaItemTrack(state.selected_item)
            local _, iname = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
            return state.selected_item, tk, trk, iname
        end
    end
    
    for _, sn in pairs(state.selected_notes) do
        if sn.take and reaper.ValidatePtr(sn.take, "MediaItem_Take*") and reaper.TakeIsMIDI(sn.take) then
            local it = sn.item or reaper.GetMediaItemTake_Item(sn.take)
            local trk = sn.track or (it and reaper.GetMediaItemTrack(it))
            local iname = "Item"
            if it then
                local _, name = reaper.GetSetMediaItemTakeInfo_String(sn.take, "P_NAME", "", false)
                if name and name ~= "" then iname = name end
            end
            return it, sn.take, trk, iname
        end
    end
    
    if state.selected_dynamic and state.selected_dynamic.take and reaper.ValidatePtr(state.selected_dynamic.take, "MediaItem_Take*") then
        local tk = state.selected_dynamic.take
        local it = reaper.GetMediaItemTake_Item(tk)
        local trk = state.selected_dynamic.track or (it and reaper.GetMediaItemTrack(it))
        local _, iname = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
        return it, tk, trk, iname
    end
    
    if state.focused_track and reaper.ValidatePtr(state.focused_track, "MediaTrack*") then
        local cur_time = reaper.GetCursorPosition()
        local it_cnt = reaper.CountTrackMediaItems(state.focused_track)
        for i = 0, it_cnt - 1 do
            local it = reaper.GetTrackMediaItem(state.focused_track, i)
            local tk = reaper.GetActiveTake(it)
            if tk and reaper.TakeIsMIDI(tk) then
                local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                if cur_time >= ipos and cur_time <= ipos + ilen then
                    local _, iname = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
                    return it, tk, state.focused_track, iname
                end
            end
        end
        if it_cnt > 0 then
            local it = reaper.GetTrackMediaItem(state.focused_track, 0)
            local tk = reaper.GetActiveTake(it)
            if tk and reaper.TakeIsMIDI(tk) then
                local _, iname = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
                return it, tk, state.focused_track, iname
            end
        end
    end
    
    local act_tk = MidiService.get_active_midi_take()
    if act_tk then
        local it = reaper.GetMediaItemTake_Item(act_tk)
        local trk = get_track_from_take(act_tk)
        local _, iname = reaper.GetSetMediaItemTakeInfo_String(act_tk, "P_NAME", "", false)
        return it, act_tk, trk, iname
    end
    
    return nil, nil, nil, nil
end
MidiService.get_active_or_focused_item_take = MidiService.get_target_item_and_take

function MidiService.set_articulation(state, pc, msb, lsb)
    local take = state.active_take
    if not take or not reaper.MIDI_EnumSelNotes(take, -1) then return end
    
    reaper.MIDI_DisableSort(take)
    local notes_changed = false
    local sel_ni = -1
    
    while true do
        sel_ni = reaper.MIDI_EnumSelNotes(take, sel_ni)
        if sel_ni == -1 then break end
        
        local retval, sel, muted, start_ppq, end_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, sel_ni)
        if retval and sel then
            -- Optional Bank Selects if the Reabank specifies it, but Reaticulate often just works with PC.
            -- To be fully conformant with a specific Reaticulate Bank, we can send CC0 (0xB0, 0) and CC32 (0xB0, 32).
            if msb and msb >= 0 then
                reaper.MIDI_InsertCC(take, true, false, start_ppq, 0xB0, chan, 0, msb)
            end
            if lsb and lsb >= 0 then
                reaper.MIDI_InsertCC(take, true, false, start_ppq, 0xB0, chan, 32, lsb)
            end
            
            -- Insert Program Change
            reaper.MIDI_InsertCC(take, true, false, start_ppq, 0xC0, chan, pc, 0)
            notes_changed = true
        end
    end
    
    if notes_changed then
        reaper.MIDI_Sort(take)
        reaper.UpdateArrange()
        MidiService.invalidate_cache()
        state.active_tracks_cache = nil
        state.status_msg = string.format("Articulation (PC %d) set for selected notes!", pc)
    end
end

function MidiService.apply_reaticulate_art(state, art_def, bank, track, active_tracks_data)
    if not art_def then return end
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    
    local msb = bank and bank.msb
    local lsb = bank and bank.lsb
    local pc = art_def.pc
    local mapped_id = MidiService.art_id_from_reaticulate_art(art_def)
    
    reaper.Undo_BeginBlock2(0)
    
    if #targets > 0 then
        local by_take = {}
        for _, sn in ipairs(targets) do
            local take = sn.take or MidiService.get_active_midi_take()
            if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
                if not by_take[take] then by_take[take] = {} end
                table.insert(by_take[take], sn)
            end
        end
        
        for take, n_list in pairs(by_take) do
            reaper.MIDI_DisableSort(take)
            local handled_ppqs = {}
            for _, sn in ipairs(n_list) do
                local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn) + 0.5)
                local chan = sn.chan or 0
                local ppq_key = string.format("%d_%d", sppq, chan)
                
                local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
                for ti = text_cnt - 1, 0, -1 do
                    local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                    if ok and etype == 15 then
                        local p = msg:match("NOTE%s+(%d+)")
                        if p and tonumber(p) == sn.pitch and math.abs(ppq - sppq) <= 25 then
                            reaper.MIDI_DeleteTextSysexEvt(take, ti)
                        end
                    end
                end
                
                if mapped_id then
                    reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, string.format("NOTE %d %d a %s", sn.pitch, chan, mapped_id))
                    sn.articulation = mapped_id
                else
                    local safe_name = (art_def.name or "art"):gsub("%s+", "_")
                    reaper.MIDI_InsertTextSysexEvt(take, false, false, sppq, 15, string.format("NOTE %d %d a %s", sn.pitch, chan, safe_name))
                    sn.articulation = art_def.name
                end
                
                if not handled_ppqs[ppq_key] then
                    handled_ppqs[ppq_key] = true
                    local _, _, cc_cnt = reaper.MIDI_CountEvts(take)
                    for ci = cc_cnt - 1, 0, -1 do
                        local ok, _, _, ppq, chanmsg, cchan, msg2 = reaper.MIDI_GetCC(take, ci)
                        if ok and math.abs(ppq - sppq) <= 35 and cchan == chan then
                            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                            local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                            if is_pc or is_bank then
                                reaper.MIDI_DeleteCC(take, ci)
                            end
                        end
                    end
                    
                    if msb and msb >= 0 then
                        reaper.MIDI_InsertCC(take, false, false, sppq, 0xB0, chan, 0, msb)
                    end
                    if lsb and lsb >= 0 then
                        reaper.MIDI_InsertCC(take, false, false, sppq, 0xB0, chan, 32, lsb)
                    end
                    reaper.MIDI_InsertCC(take, false, false, sppq, 0xC0, chan, pc, 0)
                end
            end
            MidiService.auto_chase_momentary_articulations(take, bank)
            reaper.MIDI_Sort(take)
        end
        state.status_msg = string.format("Applied '%s' to %d note(s)", art_def.name, #targets)
    else
        local cur_pos = reaper.GetCursorPosition()
        local cur_qn = reaper.TimeMap2_timeToQN(0, cur_pos)
        local cur_trk = track or state.focused_track or reaper.GetSelectedTrack(0, 0)
        if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
            local item, take = MidiService.get_or_create_item_at_qn(cur_trk, cur_qn, 1.0)
            if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
                reaper.MIDI_DisableSort(take)
                local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, cur_qn) + 0.5)
                local chan = 0
                local trk_guid = reaper.GetTrackGUID(cur_trk)
                if state.track_voices and state.track_voices[trk_guid] and state.track_voices[trk_guid] > 0 then
                    chan = state.track_voices[trk_guid] - 1
                end
                
                local _, _, cc_cnt = reaper.MIDI_CountEvts(take)
                for ci = cc_cnt - 1, 0, -1 do
                    local ok, _, _, ppq, chanmsg, cchan, msg2 = reaper.MIDI_GetCC(take, ci)
                    if ok and math.abs(ppq - sppq) <= 35 and cchan == chan then
                        local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                        local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                        if is_pc or is_bank then
                            reaper.MIDI_DeleteCC(take, ci)
                        end
                    end
                end
                
                if msb and msb >= 0 then
                    reaper.MIDI_InsertCC(take, false, false, sppq, 0xB0, chan, 0, msb)
                end
                if lsb and lsb >= 0 then
                    reaper.MIDI_InsertCC(take, false, false, sppq, 0xB0, chan, 32, lsb)
                end
                reaper.MIDI_InsertCC(take, false, false, sppq, 0xC0, chan, pc, 0)
                MidiService.auto_chase_momentary_articulations(take, bank)
                reaper.MIDI_Sort(take)
                state.status_msg = string.format("Inserted articulation '%s' at cursor (measure %.2f)", art_def.name, (cur_qn / 4) + 1)
            end
        end
    end
    
    reaper.Undo_EndBlock2(0, "Notator: Apply Articulation " .. tostring(art_def.name), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
end

function MidiService.remove_selected_articulations(state, active_tracks_data)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    
    -- If NO notes are selected, check if a single articulation marker was selected
    if #targets == 0 and state.selected_articulation then
        local art = state.selected_articulation
        local take = art.take
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            reaper.Undo_BeginBlock2(0)
            local _, _, cc_cnt, text_cnt = reaper.MIDI_CountEvts(take)
            for ci = cc_cnt - 1, 0, -1 do
                local ok, _, _, ppq, chanmsg, chan, msg2 = reaper.MIDI_GetCC(take, ci)
                if ok and math.abs(ppq - art.ppq) <= 35 and (art.chan == nil or chan == (art.chan or 0)) then
                    local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                    local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                    if is_pc and (not art.pc or msg2 == art.pc) then
                        reaper.MIDI_DeleteCC(take, ci)
                    elseif is_bank then
                        reaper.MIDI_DeleteCC(take, ci)
                    end
                end
            end
            for ti = text_cnt - 1, 0, -1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 and math.abs(ppq - art.ppq) <= 35 then
                    if msg:match("^NOTE%s+%d+%s+%d+%s+a%s+") or msg:match("^NOTATOR_CHASE") then
                        reaper.MIDI_DeleteTextSysexEvt(take, ti)
                    end
                end
            end
            local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
            local trk = get_track_from_take(take)
            local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks()
            local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, all_banks)
            MidiService.auto_chase_momentary_articulations(take, bank)
            reaper.MIDI_Sort(take)
            reaper.Undo_EndBlock2(0, "Notator: Delete Articulation", -1)
            reaper.UpdateArrange()
            MidiService.invalidate_cache()
            state.selected_articulation = nil
            state.status_msg = "Deleted selected articulation"
            return
        end
    end
    
    if #targets == 0 then
        state.status_msg = "No notes or articulation selected to remove"
        return
    end
    
    reaper.Undo_BeginBlock2(0)
    local by_take = {}
    for _, sn in ipairs(targets) do
        local take = sn.take or MidiService.get_active_midi_take()
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not by_take[take] then by_take[take] = {} end
            table.insert(by_take[take], sn)
        end
    end
    
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks()
    for take, n_list in pairs(by_take) do
        local trk = get_track_from_take(take)
        local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, all_banks)
        reaper.MIDI_DisableSort(take)
        for _, sn in ipairs(n_list) do
            local sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, sn.start_qn) + 0.5)
            local chan = sn.chan or 0
            
            local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
            for ti = text_cnt - 1, 0, -1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 and math.abs(ppq - sppq) <= 35 then
                    local p, ch = msg:match("NOTE%s+(%d+)%s+(%d+)%s+a%s+")
                    if p and tonumber(p) == sn.pitch and (not ch or tonumber(ch) == chan) then
                        reaper.MIDI_DeleteTextSysexEvt(take, ti)
                    end
                end
            end
            sn.articulation = nil
            
            -- Check if any other note at this PPQ still has an articulation
            local other_note_has_art = false
            local _, _, _, cur_tcnt = reaper.MIDI_CountEvts(take)
            for ti = 0, cur_tcnt - 1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 and math.abs(ppq - sppq) <= 25 then
                    local p, ch = msg:match("NOTE%s+(%d+)%s+(%d+)%s+a%s+")
                    if p and tonumber(p) ~= sn.pitch and (not ch or tonumber(ch) == chan) then
                        other_note_has_art = true
                        break
                    end
                end
            end
            
            if not other_note_has_art then
                local _, _, cc_cnt = reaper.MIDI_CountEvts(take)
                for ci = cc_cnt - 1, 0, -1 do
                    local ok, _, _, ppq, chanmsg, cchan, msg2 = reaper.MIDI_GetCC(take, ci)
                    if ok and math.abs(ppq - sppq) <= 35 and cchan == chan then
                        local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                        local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                        if is_pc or is_bank then
                            reaper.MIDI_DeleteCC(take, ci)
                        end
                    end
                end
            end
        end
        MidiService.auto_chase_momentary_articulations(take, bank)
        reaper.MIDI_Sort(take)
    end
    
    reaper.Undo_EndBlock2(0, "Notator: Remove Articulations", -1)
    reaper.UpdateArrange()
    
    local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
    SlurService.remove_slurs_for_notes(state, targets)
    
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    state:clear_articulation_selection()
    state.status_msg = string.format("Removed articulations from %d note(s)", #targets)
end

function MidiService.move_articulation(art, target_take, target_ppq, target_track)
    if not art then return end
    local orig_take = art.take
    local orig_ppq = art.ppq
    
    if not target_take or not reaper.ValidatePtr(target_take, "MediaItem_Take*") then
        target_take = orig_take
    end
    if not target_take or not reaper.ValidatePtr(target_take, "MediaItem_Take*") then return end
    
    local item = reaper.GetMediaItemTake_Item(target_take)
    if item then
        local ipos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local ilen = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local min_ppq = reaper.MIDI_GetPPQPosFromProjTime(target_take, ipos)
        local max_ppq = reaper.MIDI_GetPPQPosFromProjTime(target_take, ipos + ilen)
        if min_ppq and max_ppq and max_ppq > min_ppq then
            target_ppq = math.max(min_ppq, math.min(max_ppq - 10, target_ppq))
        end
    end

    reaper.Undo_BeginBlock2(0)
    
    -- Delete original Program Change from orig_take
    if orig_take and reaper.ValidatePtr(orig_take, "MediaItem_Take*") then
        local _, notecnt, cccnt = reaper.MIDI_CountEvts(orig_take)
        local to_delete = {}
        for ci = cccnt - 1, 0, -1 do
            local ok, _, _, ppq, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(orig_take, ci)
            if ok and math.abs(ppq - orig_ppq) <= 15 then
                local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                if is_pc and msg2 == art.pc then
                    table.insert(to_delete, ci)
                elseif is_bank then
                    table.insert(to_delete, ci)
                end
            end
        end
        for _, ci in ipairs(to_delete) do
            reaper.MIDI_DeleteCC(orig_take, ci)
        end
        reaper.MIDI_Sort(orig_take)
    end
    
    -- Insert new PC at target_ppq
    local chan = art.chan or 0
    if art.msb and art.msb >= 0 then
        reaper.MIDI_InsertCC(target_take, true, false, target_ppq, 0xB0, chan, 0, art.msb)
    end
    if art.lsb and art.lsb >= 0 then
        reaper.MIDI_InsertCC(target_take, true, false, target_ppq, 0xB0, chan, 32, art.lsb)
    end
    reaper.MIDI_InsertCC(target_take, true, false, target_ppq, 0xC0, chan, art.pc, 0)
    reaper.MIDI_Sort(target_take)
    
    reaper.Undo_EndBlock2(0, "Notator: Move articulation", -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    
    art.take = target_take
    art.ppq = target_ppq
    art.qn = reaper.MIDI_GetProjQNFromPPQPos(target_take, target_ppq)
    if target_track then art.track = target_track end
end

function MidiService.delete_articulation(art)
    if not art then return end
    local take = art.take
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return end
    local art_ppq = art.ppq
    
    reaper.Undo_BeginBlock2(0)
    reaper.MIDI_DisableSort(take)
    local _, notecnt, cccnt, textcnt = reaper.MIDI_CountEvts(take)
    for ci = cccnt - 1, 0, -1 do
        local ok, _, _, ppq, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(take, ci)
        if ok and math.abs(ppq - art_ppq) <= 35 and (art.chan == nil or chan == art.chan) then
            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
            local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
            if is_pc and (not art.pc or msg2 == art.pc) then
                reaper.MIDI_DeleteCC(take, ci)
            elseif is_bank then
                reaper.MIDI_DeleteCC(take, ci)
            end
        end
    end
    for ti = textcnt - 1, 0, -1 do
        local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
        if ok and etype == 15 and math.abs(ppq - art_ppq) <= 35 then
            if msg:match("^NOTE%s+%d+%s+%d+%s+a%s+") or msg:match("^NOTATOR_CHASE") then
                reaper.MIDI_DeleteTextSysexEvt(take, ti)
            end
        end
    end
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local trk = get_track_from_take(take)
    local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks()
    local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, all_banks)
    MidiService.auto_chase_momentary_articulations(take, bank)
    reaper.MIDI_Sort(take)
    reaper.Undo_EndBlock2(0, "Notator: Delete articulation", -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
end

function MidiService.delete_selected_articulations(state)
    if not state then return end
    local to_del = {}
    if state.selected_articulations then
        for _, art in pairs(state.selected_articulations) do
            table.insert(to_del, art)
        end
    end
    if #to_del == 0 and state.selected_articulation then
        table.insert(to_del, state.selected_articulation)
    end
    if #to_del == 0 then return end

    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser and ReaticulateParser.get_all_banks()

    reaper.Undo_BeginBlock2(0)
    local by_take = {}
    for _, art in ipairs(to_del) do
        local take = art.take
        if take and reaper.ValidatePtr(take, "MediaItem_Take*") then
            if not by_take[take] then by_take[take] = {} end
            table.insert(by_take[take], art)
        end
    end

    for take, art_list in pairs(by_take) do
        local trk = get_track_from_take(take)
        local bank = trk and ReaticulateParser and ReaticulateParser.get_bank_for_track(trk, all_banks)
        reaper.MIDI_DisableSort(take)

        for _, art in ipairs(art_list) do
            local art_ppq = art.ppq
            local art_chan = art.chan
            local art_pc = art.pc

            local _, notecnt, cccnt, textcnt = reaper.MIDI_CountEvts(take)
            for ci = cccnt - 1, 0, -1 do
                local ok, _, _, ppq, chanmsg, chan, msg2, msg3 = reaper.MIDI_GetCC(take, ci)
                if ok and math.abs(ppq - art_ppq) <= 35 and (art_chan == nil or chan == art_chan) then
                    local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                    local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                    if is_pc and (not art_pc or msg2 == art_pc) then
                        reaper.MIDI_DeleteCC(take, ci)
                    elseif is_bank then
                        reaper.MIDI_DeleteCC(take, ci)
                    end
                end
            end

            for ti = textcnt - 1, 0, -1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 and math.abs(ppq - art_ppq) <= 35 then
                    if msg:match("^NOTE%s+%d+%s+%d+%s+a%s+") or msg:match("^NOTATOR_CHASE") then
                        reaper.MIDI_DeleteTextSysexEvt(take, ti)
                    end
                end
            end
        end

        MidiService.auto_chase_momentary_articulations(take, bank)
        reaper.MIDI_Sort(take)
    end

    -- Clear articulation references from selected notes in state
    if state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            for _, art in ipairs(to_del) do
                if art.qn and sn.start_qn and math.abs(sn.start_qn - art.qn) < 0.05 then
                    sn.articulation = nil
                end
            end
        end
    end
    if state.selected_note then
        for _, art in ipairs(to_del) do
            if art.qn and state.selected_note.start_qn and math.abs(state.selected_note.start_qn - art.qn) < 0.05 then
                state.selected_note.articulation = nil
            end
        end
    end

    reaper.Undo_EndBlock2(0, string.format("Notator: Delete %d articulation(s)", #to_del), -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    
    state:clear_articulation_selection()
    state.selected_articulation = nil
    state.hovered_articulation = nil
    state.active_tracks_cache = nil
    state.status_msg = string.format("Deleted %d articulation(s)", #to_del)
end

function MidiService.delete_selected_articulation(state)
    MidiService.delete_selected_articulations(state)
end

function MidiService.fix_playback(state, active_tracks_data, is_last_resort, is_selective)
    local ReaticulateParser = package.loaded["services.reaticulate_parser"] or require("services.reaticulate_parser")
    local all_banks = ReaticulateParser.get_all_banks()
    local selective = (is_selective ~= false) -- defaults to true
    
    -- 1. Identify all target takes and tracks to scan
    local targets_by_take = {}
    local take_list = {}
    local single_item_name = nil
    
    local function add_take(tk, trk)
        if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") and reaper.TakeIsMIDI(tk) then
            if not targets_by_take[tk] then
                if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then
                    trk = get_track_from_take(tk)
                end
                targets_by_take[tk] = trk or true
                local it = reaper.GetMediaItemTake_Item(tk)
                local _, iname = reaper.GetSetMediaItemTakeInfo_String(tk, "P_NAME", "", false)
                if iname and iname ~= "" then
                    single_item_name = iname
                elseif it then
                    local _, take_name = reaper.GetSetMediaItemInfo_String(it, "P_NOTES", "", false)
                    single_item_name = (take_name ~= "") and take_name or "MIDI Item"
                end
                table.insert(take_list, { take = tk, track = trk, item = it })
            end
        end
    end
    
    if selective then
        -- SELECTIVE MODE: Strictly only the selected MIDI item!
        -- 1. Explicitly selected item in Notator state
        if state.selected_item and reaper.ValidatePtr(state.selected_item, "MediaItem*") then
            local tk = state.selected_take or reaper.GetActiveTake(state.selected_item)
            local trk = reaper.GetMediaItemTrack(state.selected_item)
            add_take(tk, trk)
        end
        
        -- 2. Item containing selected notes
        if #take_list == 0 and state.selected_notes and next(state.selected_notes) ~= nil then
            for _, sn in pairs(state.selected_notes) do
                local it = sn.item or (sn.take and reaper.ValidatePtr(sn.take, "MediaItem_Take*") and reaper.GetMediaItemTake_Item(sn.take))
                local tk = sn.take or (it and reaper.GetActiveTake(it))
                local trk = sn.track or (it and reaper.GetMediaItemTrack(it))
                add_take(tk, trk)
                if #take_list > 0 then break end
            end
        elseif #take_list == 0 and state.selected_note then
            local sn = state.selected_note
            local it = sn.item or (sn.take and reaper.ValidatePtr(sn.take, "MediaItem_Take*") and reaper.GetMediaItemTake_Item(sn.take))
            local tk = sn.take or (it and reaper.GetActiveTake(it))
            local trk = sn.track or (it and reaper.GetMediaItemTrack(it))
            add_take(tk, trk)
        end
        
        -- 3. Media item selected in REAPER
        if #take_list == 0 then
            local sel_item_cnt = reaper.CountSelectedMediaItems(0)
            if sel_item_cnt > 0 then
                local it = reaper.GetSelectedMediaItem(0, 0)
                local tk = it and reaper.GetActiveTake(it)
                local trk = it and reaper.GetMediaItemTrack(it)
                add_take(tk, trk)
            end
        end
        
        -- 4. Target item under cursor on focused track / active MIDI take
        if #take_list == 0 then
            local it, tk, trk = MidiService.get_target_item_and_take(state, active_tracks_data)
            if tk then
                add_take(tk, trk)
            end
        end
    else
        -- GLOBAL MODE: Entire project - all MIDI items across all tracks!
        local num_tracks = reaper.CountTracks(0)
        for t = 0, num_tracks - 1 do
            local trk = reaper.GetTrack(0, t)
            if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                local it_cnt = reaper.CountTrackMediaItems(trk)
                for i = 0, it_cnt - 1 do
                    local it = reaper.GetTrackMediaItem(trk, i)
                    local tk = it and reaper.GetActiveTake(it)
                    add_take(tk, trk)
                end
            end
        end
    end
    
    if #take_list == 0 then
        state.status_msg = selective and "⚡ Fix Playback (Selective): No MIDI item selected to fix!" or "⚡ Fix Playback (Global): No MIDI items found in project to fix!"
        return false
    end
    
    -- MODE 1: FIX OF LAST RESORT (Emergency total articulation reset to clean default sustain)
    if is_last_resort then
        reaper.Undo_BeginBlock2(0)
        local total_cleared = 0
        local processed_takes = 0
        local last_trk_name = nil
        
        for _, item_entry in ipairs(take_list) do
            local take = item_entry.take
            local trk = item_entry.track
            if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then
                trk = get_track_from_take(take)
            end
            if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
                local formatted = format_track_name_with_idx(trk)
                if formatted and formatted ~= "" then last_trk_name = formatted end
            end
            local trk_guid = trk and reaper.ValidatePtr(trk, "MediaTrack*") and reaper.GetTrackGUID(trk)
            local trk_override = trk_guid and state.track_articulation_banks and state.track_articulation_banks[trk_guid]
            local bank = trk and ReaticulateParser.get_bank_for_track(trk, all_banks, trk_override)
            
            local default_base_art = nil
            if bank and bank.articulations and #bank.articulations > 0 then
                for _, ba in ipairs(bank.articulations) do
                    if not default_base_art and not MidiService.is_momentary_articulation(ba.name) then
                        default_base_art = ba
                        break
                    end
                end
                if not default_base_art and #bank.articulations > 0 then
                    default_base_art = bank.articulations[1]
                end
            end
            
            reaper.MIDI_DisableSort(take)
            
            -- Delete all Type 15 articulation events and NOTATOR_CHASE tags
            local _, notecnt, cccnt, textcnt = reaper.MIDI_CountEvts(take)
            for ti = textcnt - 1, 0, -1 do
                local ok_t, _, _, _, etype_t, msg_t = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok_t then
                    if (etype_t == 15 and msg_t:match("NOTE%s+%d+%s+%d+%s+a%s+")) or msg_t:find("NOTATOR_CHASE") then
                        reaper.MIDI_DeleteTextSysexEvt(take, ti)
                        total_cleared = total_cleared + 1
                    end
                end
            end
            
            -- Delete all Program Changes and Bank Selects (CC0 / CC32)
            local _, _, cur_cc_cnt = reaper.MIDI_CountEvts(take)
            for ci = cur_cc_cnt - 1, 0, -1 do
                local ok_c, _, _, _, chanmsg, _, msg2 = reaper.MIDI_GetCC(take, ci)
                if ok_c then
                    local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                    local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                    if is_pc or is_bank then
                        reaper.MIDI_DeleteCC(take, ci)
                        total_cleared = total_cleared + 1
                    end
                end
            end
            
            -- Reset articulation on selected notes
            if state.selected_notes then
                for _, sn in pairs(state.selected_notes) do
                    sn.articulation = nil
                end
            end
            if state.selected_note then
                state.selected_note.articulation = nil
            end
            
            -- Re-insert clean default base patch at item/first note start
            if default_base_art and notecnt > 0 then
                local _, _, _, first_sppq = reaper.MIDI_GetNote(take, 0)
                first_sppq = first_sppq or 0
                local eff_msb = (bank.msb and bank.msb >= 0) and bank.msb or -1
                local eff_lsb = (bank.lsb and bank.lsb >= 0) and bank.lsb or -1
                if eff_msb >= 0 then reaper.MIDI_InsertCC(take, false, false, first_sppq, 0xB0, 0, 0, eff_msb) end
                if eff_lsb >= 0 then reaper.MIDI_InsertCC(take, false, false, first_sppq, 0xB0, 0, 32, eff_lsb) end
                reaper.MIDI_InsertCC(take, false, false, first_sppq, 0xC0, 0, default_base_art.pc, 0)
            end
            
            reaper.MIDI_Sort(take)
            processed_takes = processed_takes + 1
        end
        
        if not last_trk_name then
            local fallback_trk = state.focused_track or (active_tracks_data and active_tracks_data[1] and active_tracks_data[1].track) or reaper.GetSelectedTrack(0, 0)
            last_trk_name = format_track_name_with_idx(fallback_trk) or "Track"
        end
        state.fix_last_resort_track_name = last_trk_name
        
        local undo_title = selective and "Notator: Fix Playback (Last Resort Purge - Selective)" or "Notator: Fix Playback (Last Resort Purge - Global)"
        reaper.Undo_EndBlock2(0, undo_title, -1)
        reaper.UpdateArrange()
        MidiService.invalidate_cache()
        state.active_tracks_cache = nil
        state.show_fix_last_resort_modal = false
        state.status_msg = string.format("⚡ Fix of Last Resort (%s): Purged all articulations on %s (%d item(s), %d events cleared, reset to default sustain)",
            selective and "Selective" or "Global", single_item_name or last_trk_name, processed_takes, total_cleared)
        return true
    end
    
    -- MODE 2: STANDARD IDEMPOTENT PLAYBACK RECONCILIATION
    local undo_title = selective and "Notator: Fix Playback (Selective)" or "Notator: Fix Playback (Global)"
    reaper.Undo_BeginBlock2(0)
    local total_fixed_notes = 0
    local total_cleared_events = 0
    local processed_takes = 0
    local last_trk_name = nil
    local processed_track_guids = {}
    local item_bounds_by_track = {}
    
    for _, item_entry in ipairs(take_list) do
        local take = item_entry.take
        local trk = item_entry.track
        if not trk or not reaper.ValidatePtr(trk, "MediaTrack*") then
            trk = get_track_from_take(take)
        end
        local trk_guid = trk and reaper.ValidatePtr(trk, "MediaTrack*") and reaper.GetTrackGUID(trk)
        if trk_guid then
            processed_track_guids[trk_guid] = true
            local it = item_entry.item
            if it then
                local ipos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                local ilen = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                local sqn = reaper.TimeMap2_timeToQN(0, ipos)
                local eqn = reaper.TimeMap2_timeToQN(0, ipos + ilen)
                item_bounds_by_track[trk_guid] = item_bounds_by_track[trk_guid] or {}
                table.insert(item_bounds_by_track[trk_guid], { sqn = sqn, eqn = eqn })
            end
        end
        if trk and reaper.ValidatePtr(trk, "MediaTrack*") then
            local formatted = format_track_name_with_idx(trk)
            if formatted and formatted ~= "" then last_trk_name = formatted end
        end
        
        -- Resolve Reaticulate bank for this track (do NOT blindly fallback to all_banks[1]!)
        local trk_override = trk_guid and state.track_articulation_banks and state.track_articulation_banks[trk_guid]
        local bank = trk and ReaticulateParser.get_bank_for_track(trk, all_banks, trk_override)
        
        local default_base_art = nil
        if bank and bank.articulations and #bank.articulations > 0 then
            for _, ba in ipairs(bank.articulations) do
                if not default_base_art and not MidiService.is_momentary_articulation(ba.name) then
                    default_base_art = ba
                    break
                end
            end
            if not default_base_art and #bank.articulations > 0 then
                default_base_art = bank.articulations[1]
            end
        end
        
        reaper.MIDI_DisableSort(take)
        local _, notecnt, cccnt, textcnt = reaper.MIDI_CountEvts(take)
        
        if notecnt > 0 then
            -- 1. Read all notes in this take
            local notes = {}
            for ni = 0, notecnt - 1 do
                local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
                if ok and not muted then
                    table.insert(notes, { idx = ni, sppq = sppq, eppq = eppq, chan = chan, pitch = pitch, sel = sel })
                end
            end
            table.sort(notes, function(a, b) return a.sppq < b.sppq end)
            local first_note_ppq = (#notes > 0) and notes[1].sppq or 0
            local base_pc = default_base_art and default_base_art.pc
            
            -- 2. Read all Type 15 text events in take
            local type15_arts_by_note = {}
            local _, _, _, cur_tcnt = reaper.MIDI_CountEvts(take)
            for ti = 0, cur_tcnt - 1 do
                local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok and etype == 15 then
                    local p, ch, art = msg:match("NOTE%s+(%d+)%s+(%d+)%s+a%s+([%a%d_]+)")
                    if p and art then
                        table.insert(type15_arts_by_note, {
                            ppq = ppq,
                            pitch = tonumber(p),
                            chan = tonumber(ch) or 0,
                            art = art
                        })
                    end
                end
            end
            
            -- 3. Check each note: is its articulation supported by current track's bank?
            local valid_keep_pcs_at_ppq = {}
            for _, n in ipairs(notes) do
                local art_id = nil
                for _, na in ipairs(type15_arts_by_note) do
                    if na.pitch == n.pitch and na.chan == n.chan and math.abs(na.ppq - n.sppq) <= 25 then
                        art_id = na.art
                        break
                    end
                end
                
                -- If no Type 15 tag, check if there was a Program Change at note onset:
                -- Check current track's bank FIRST!
                if not art_id and bank and bank.articulations then
                    local _, _, cur_cc_cnt = reaper.MIDI_CountEvts(take)
                    for ci = 0, cur_cc_cnt - 1 do
                        local ok_c, _, _, c_ppq, chanmsg, c_chan, msg2 = reaper.MIDI_GetCC(take, ci)
                        if ok_c and math.abs(c_ppq - n.sppq) <= 25 and c_chan == n.chan then
                            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                            if is_pc and (not default_base_art or msg2 ~= default_base_art.pc) then
                                for _, ba in ipairs(bank.articulations) do
                                    if ba.pc == msg2 then
                                        art_id = MidiService.art_id_from_reaticulate_art(ba) or ba.name
                                        break
                                    end
                                end
                            end
                        end
                        if art_id then break end
                    end
                end
                
                -- Fallback: check other banks in all_banks
                if not art_id then
                    local _, _, cur_cc_cnt = reaper.MIDI_CountEvts(take)
                    for ci = 0, cur_cc_cnt - 1 do
                        local ok_c, _, _, c_ppq, chanmsg, c_chan, msg2 = reaper.MIDI_GetCC(take, ci)
                        if ok_c and math.abs(c_ppq - n.sppq) <= 25 and c_chan == n.chan then
                            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                            if is_pc and (not default_base_art or msg2 ~= default_base_art.pc) then
                                for _, b in ipairs(all_banks) do
                                    if b.articulations then
                                        for _, ba in ipairs(b.articulations) do
                                            if ba.pc == msg2 then
                                                local m_art = MidiService.art_id_from_reaticulate_art(ba) or ba.name
                                                if m_art then art_id = m_art break end
                                            end
                                        end
                                    end
                                    if art_id then break end
                                end
                                break
                            end
                        end
                    end
                end
                
                local art_match = nil
                if art_id and bank then
                    art_match = MidiService.find_reaticulate_art_for_id(bank, art_id)
                    if not art_match and bank.articulations then
                        for _, ba in ipairs(bank.articulations) do
                            if ba.name and ba.name:lower() == art_id:lower() then
                                art_match = ba
                                break
                            end
                        end
                    end
                end
                
                if art_match then
                    -- Articulation IS supported by destination track's bank!
                    local sppq_round = math.floor(n.sppq + 0.5)
                    local pc_k = string.format("%d_%d_%d", sppq_round, n.chan, art_match.pc)
                    valid_keep_pcs_at_ppq[pc_k] = true
                    
                    -- Delete any existing mismatched PCs/Bank Selects around this position on this channel
                    local _, _, cur_ccs = reaper.MIDI_CountEvts(take)
                    for ci = cur_ccs - 1, 0, -1 do
                        local ok_c, _, _, c_ppq, chanmsg, c_chan, msg2 = reaper.MIDI_GetCC(take, ci)
                        if ok_c and math.abs(c_ppq - n.sppq) <= 25 and c_chan == n.chan then
                            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                            local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                            if (is_pc and msg2 ~= art_match.pc) or is_bank then
                                reaper.MIDI_DeleteCC(take, ci)
                            end
                        end
                    end
                    
                    -- Insert authentic CC0, CC32, and Program Change if not already present
                    local has_pc = false
                    local _, _, cur_ccs2 = reaper.MIDI_CountEvts(take)
                    for ci = 0, cur_ccs2 - 1 do
                        local ok_c, _, _, c_ppq, chanmsg, c_chan, msg2 = reaper.MIDI_GetCC(take, ci)
                        if ok_c and math.abs(c_ppq - n.sppq) <= 25 and c_chan == n.chan then
                            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                            if is_pc and msg2 == art_match.pc then
                                has_pc = true
                                break
                            end
                        end
                    end
                    if not has_pc then
                        local eff_msb = (bank.msb and bank.msb >= 0) and bank.msb or -1
                        local eff_lsb = (bank.lsb and bank.lsb >= 0) and bank.lsb or -1
                        if eff_msb >= 0 then reaper.MIDI_InsertCC(take, false, false, n.sppq, 0xB0, n.chan, 0, eff_msb) end
                        if eff_lsb >= 0 then reaper.MIDI_InsertCC(take, false, false, n.sppq, 0xB0, n.chan, 32, eff_lsb) end
                        reaper.MIDI_InsertCC(take, false, false, n.sppq, 0xC0, n.chan, art_match.pc, 0)
                        total_fixed_notes = total_fixed_notes + 1
                    end
                    
                    -- Ensure Type 15 notation tag exists so the articulation is permanently bound to the note
                    local has_t15 = false
                    for _, na in ipairs(type15_arts_by_note) do
                        if na.pitch == n.pitch and na.chan == n.chan and math.abs(na.ppq - n.sppq) <= 25 then
                            has_t15 = true
                            break
                        end
                    end
                    if not has_t15 then
                        local target_art_name = MidiService.art_id_from_reaticulate_art(art_match) or art_id or art_match.name or "staccato"
                        reaper.MIDI_InsertTextSysexEvt(take, false, false, n.sppq, 15, string.format("NOTE %d %d a %s", n.pitch, n.chan, target_art_name))
                        table.insert(type15_arts_by_note, {
                            ppq = n.sppq,
                            pitch = n.pitch,
                            chan = n.chan,
                            art = target_art_name
                        })
                    end
                else
                    -- Articulation is NOT supported (e.g. staccato is not possible with this library)
                    -- OR note has no articulation: CLEAR ALL old/foreign PCs and CC0/CC32 at this note!
                    -- Protect the default base patch if this note is at the start of the item
                    local _, _, cur_ccs = reaper.MIDI_CountEvts(take)
                    for ci = cur_ccs - 1, 0, -1 do
                        local ok_c, _, _, c_ppq, chanmsg, c_chan, msg2 = reaper.MIDI_GetCC(take, ci)
                        if ok_c and math.abs(c_ppq - n.sppq) <= 35 and c_chan == n.chan then
                            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                            local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                            local is_base_at_start = (base_pc and msg2 == base_pc and math.abs(c_ppq - first_note_ppq) <= 40)
                            if (is_pc and not is_base_at_start) or (is_bank and not (base_pc and math.abs(c_ppq - first_note_ppq) <= 40)) then
                                reaper.MIDI_DeleteCC(take, ci)
                                total_cleared_events = total_cleared_events + 1
                            end
                        end
                    end
                    
                    -- Delete unsupported Type 15 notation tags for this note
                    local _, _, _, text_cnt_del = reaper.MIDI_CountEvts(take)
                    for ti = text_cnt_del - 1, 0, -1 do
                        local ok_t, _, _, ppq_t, etype_t, msg_t = reaper.MIDI_GetTextSysexEvt(take, ti)
                        if ok_t and etype_t == 15 and math.abs(ppq_t - n.sppq) <= 35 then
                            local p, ch = msg_t:match("NOTE%s+(%d+)%s+(%d+)%s+a%s+")
                            if p and tonumber(p) == n.pitch and (not ch or tonumber(ch) == n.chan) then
                                reaper.MIDI_DeleteTextSysexEvt(take, ti)
                                total_cleared_events = total_cleared_events + 1
                            end
                        end
                    end
                    
                    if state.selected_notes then
                        for _, sn in pairs(state.selected_notes) do
                            if sn.pitch == n.pitch and sn.chan == n.chan and math.abs(sn.start_qn - reaper.MIDI_GetProjQNFromPPQPos(take, n.sppq)) < 0.05 then
                                sn.articulation = nil
                            end
                        end
                    end
                end
            end
            
            -- 4. Take-wide sweep: Delete ANY Program Changes and Bank Selects that are NOT in valid_keep_pcs_at_ppq
            -- and not the default base patch at the start of the item
            local _, _, final_cc_cnt = reaper.MIDI_CountEvts(take)
            for ci = final_cc_cnt - 1, 0, -1 do
                local ok_c, _, _, c_ppq, chanmsg, c_chan, msg2 = reaper.MIDI_GetCC(take, ci)
                if ok_c then
                    local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                    local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
                    
                    if is_pc then
                        local sppq_round = math.floor(c_ppq + 0.5)
                        local pc_k = string.format("%d_%d_%d", sppq_round, c_chan, msg2)
                        local is_valid_art = valid_keep_pcs_at_ppq[pc_k]
                        local is_base_at_start = (base_pc and msg2 == base_pc and math.abs(c_ppq - first_note_ppq) <= 40)
                        
                        if not is_valid_art and not is_base_at_start then
                            reaper.MIDI_DeleteCC(take, ci)
                            total_cleared_events = total_cleared_events + 1
                        end
                    elseif is_bank then
                        local has_valid_pc_near = false
                        for valid_k, _ in pairs(valid_keep_pcs_at_ppq) do
                            local v_ppq = tonumber(valid_k:match("^(%d+)_"))
                            if v_ppq and math.abs(v_ppq - c_ppq) <= 25 then
                                has_valid_pc_near = true
                                break
                            end
                        end
                        if not has_valid_pc_near and base_pc and math.abs(c_ppq - first_note_ppq) <= 40 then
                            has_valid_pc_near = true
                        end
                        if not has_valid_pc_near then
                            reaper.MIDI_DeleteCC(take, ci)
                            total_cleared_events = total_cleared_events + 1
                        end
                    end
                end
            end
            
            -- 5. Delete any unsupported Type 15 articulation events and obsolete NOTATOR_CHASE tags
            local _, _, _, final_tcnt = reaper.MIDI_CountEvts(take)
            for ti = final_tcnt - 1, 0, -1 do
                local ok_t, _, _, ppq_t, etype_t, msg_t = reaper.MIDI_GetTextSysexEvt(take, ti)
                if ok_t and etype_t == 15 then
                    local p, ch, art = msg_t:match("NOTE%s+(%d+)%s+(%d+)%s+a%s+([%a%d_]+)")
                    if art then
                        local art_supported = false
                        if bank then
                            local match = MidiService.find_reaticulate_art_for_id(bank, art)
                            if match then art_supported = true end
                        end
                        if not art_supported then
                            reaper.MIDI_DeleteTextSysexEvt(take, ti)
                            total_cleared_events = total_cleared_events + 1
                        end
                    end
                end
            end
            
            -- 6. Ensure default base patch (e.g. Long / Sustain) is active at start if bank exists and first note is not articulated
            if default_base_art and #notes > 0 then
                local start_ppq = notes[1].sppq
                local first_has_art = false
                for k, _ in pairs(valid_keep_pcs_at_ppq) do
                    local v_ppq = tonumber(k:match("^(%d+)_"))
                    if v_ppq and math.abs(v_ppq - start_ppq) <= 25 then
                        first_has_art = true
                        break
                    end
                end
                
                if not first_has_art then
                    local has_base = false
                    local _, _, cur_ccs3 = reaper.MIDI_CountEvts(take)
                    for ci = 0, cur_ccs3 - 1 do
                        local ok_c, _, _, ppq_c, chanmsg, cchan, msg2 = reaper.MIDI_GetCC(take, ci)
                        local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
                        if ok_c and is_pc and math.abs(ppq_c - start_ppq) <= 40 and msg2 == default_base_art.pc then
                            has_base = true
                            break
                        end
                    end
                    if not has_base then
                        local chan = notes[1].chan or 0
                        local eff_msb = (bank.msb and bank.msb >= 0) and bank.msb or -1
                        local eff_lsb = (bank.lsb and bank.lsb >= 0) and bank.lsb or -1
                        if eff_msb >= 0 then reaper.MIDI_InsertCC(take, false, false, start_ppq, 0xB0, chan, 0, eff_msb) end
                        if eff_lsb >= 0 then reaper.MIDI_InsertCC(take, false, false, start_ppq, 0xB0, chan, 32, eff_lsb) end
                        reaper.MIDI_InsertCC(take, false, false, start_ppq, 0xC0, chan, default_base_art.pc, 0)
                    end
                end
            end
        end
        
        -- 6b. Auto-heal micro-overlapping notes (e.g. slur legato remnants <= 15 ticks)
        local _, fix_notecnt = reaper.MIDI_CountEvts(take)
        for ni = 0, fix_notecnt - 1 do
            local ok_a, sel_a, mut_a, s_a, e_a, ch_a, p_a, v_a = reaper.MIDI_GetNote(take, ni)
            if ok_a and not mut_a then
                for nj = 0, fix_notecnt - 1 do
                    if ni ~= nj then
                        local ok_b, _, mut_b, s_b, _, ch_b, p_b, _ = reaper.MIDI_GetNote(take, nj)
                        if ok_b and not mut_b and ch_b == ch_a and s_b >= s_a and s_b < e_a then
                            local overlap = e_a - s_b
                            if p_b == p_a and overlap <= 15 then
                                reaper.MIDI_SetNote(take, ni, sel_a, mut_a, s_a, s_b, ch_a, p_a, v_a, false)
                                total_fixed_notes = total_fixed_notes + 1
                                break
                            elseif overlap <= 5 then
                                local has_slur = false
                                if state and state.user_slurs then
                                    local a_qn = reaper.MIDI_GetProjQNFromPPQPos(take, s_a)
                                    for _, sl in ipairs(state.user_slurs) do
                                        if math.abs((sl.start_qn or 0) - a_qn) < 0.05 then
                                            has_slur = true
                                            break
                                        end
                                    end
                                end
                                if not has_slur then
                                    reaper.MIDI_SetNote(take, ni, sel_a, mut_a, s_a, s_b, ch_a, p_a, v_a, false)
                                    total_fixed_notes = total_fixed_notes + 1
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        
        -- 7. Recalculate auto-chase return points for momentary articulations
        MidiService.auto_chase_momentary_articulations(take, bank)
        reaper.MIDI_Sort(take)
        processed_takes = processed_takes + 1
    end
    
    if not last_trk_name then
        local fallback_trk = state.focused_track or (active_tracks_data and active_tracks_data[1] and active_tracks_data[1].track) or reaper.GetSelectedTrack(0, 0)
        last_trk_name = format_track_name_with_idx(fallback_trk) or "Track"
    end
    state.fix_last_resort_track_name = last_trk_name
    
    if next(processed_track_guids) == nil then
        local fallback_trk = state.focused_track or (active_tracks_data and active_tracks_data[1] and active_tracks_data[1].track) or reaper.GetSelectedTrack(0, 0)
        if fallback_trk and reaper.ValidatePtr(fallback_trk, "MediaTrack*") then
            local f_guid = reaper.GetTrackGUID(fallback_trk)
            if f_guid then processed_track_guids[f_guid] = true end
        end
    end

    -- 8. Heal shrunken hairpins & dynamic texts squeezed by old articulation collisions
    local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
    local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
    local total_healed_dynamics = 0
    
    for trk_guid, _ in pairs(processed_track_guids) do
        if state.hairpins then
            for _, hp in ipairs(state.hairpins) do
                if hp.track_guid == trk_guid then
                    local in_scope = not selective
                    if selective and item_bounds_by_track[trk_guid] then
                        for _, b in ipairs(item_bounds_by_track[trk_guid]) do
                            if (hp.start_qn or 0) >= b.sqn - 0.5 and (hp.start_qn or 0) <= b.eqn + 0.5 then
                                in_scope = true
                                break
                            end
                        end
                    end
                    if in_scope then
                        local cur_len = (hp.end_qn or 0) - (hp.start_qn or 0)
                        -- Collapsed or shrunken due to legacy articulation collision (<= 0.75 QN)
                        if cur_len <= 0.75 then
                            local _, r_b = HairpinService.get_hairpin_bounds(state, hp, active_tracks_data)
                            if r_b and r_b > (hp.start_qn + 0.75) then
                                local target_len = hp.saved_natural_len or 4.0
                                local new_end = math.min(hp.start_qn + target_len, r_b - 0.05)
                                if new_end > (hp.end_qn or 0) then
                                    hp.end_qn = new_end
                                    total_healed_dynamics = total_healed_dynamics + 1
                                end
                            end
                        end
                    end
                end
            end
        end
        
        if state.dynamic_texts then
            for _, dt in ipairs(state.dynamic_texts) do
                if dt.track_guid == trk_guid then
                    local in_scope = not selective
                    if selective and item_bounds_by_track[trk_guid] then
                        for _, b in ipairs(item_bounds_by_track[trk_guid]) do
                            if (dt.start_qn or 0) >= b.sqn - 0.5 and (dt.start_qn or 0) <= b.eqn + 0.5 then
                                in_scope = true
                                break
                            end
                        end
                    end
                    if in_scope then
                        local cur_len = (dt.end_qn or 0) - (dt.start_qn or 0)
                        if cur_len <= 0.75 then
                            local _, r_b = DynamicTextService.get_bounds(state, dt, active_tracks_data)
                            if r_b and r_b > (dt.start_qn + 0.75) then
                                local target_len = 4.0
                                local new_end = math.min(dt.start_qn + target_len, r_b - 0.05)
                                if new_end > (dt.end_qn or 0) then
                                    dt.end_qn = new_end
                                    total_healed_dynamics = total_healed_dynamics + 1
                                end
                            end
                        end
                    end
                end
            end
        end
        
        -- Re-resolve dynamic CC curves across the track without articulation boundaries
        HairpinService.resolve_all_track_hairpins(state, trk_guid, active_tracks_data)
        if state.hairpins then
            for _, hp in ipairs(state.hairpins) do
                if hp.track_guid == trk_guid then
                    local in_scope = not selective
                    if selective and item_bounds_by_track[trk_guid] then
                        for _, b in ipairs(item_bounds_by_track[trk_guid]) do
                            if (hp.start_qn or 0) >= b.sqn - 0.5 and (hp.start_qn or 0) <= b.eqn + 0.5 then
                                in_scope = true
                                break
                            end
                        end
                    end
                    if in_scope then
                        HairpinService.apply_hairpin_cc(state, hp, MidiService, active_tracks_data)
                    end
                end
            end
        end
        if state.dynamic_texts then
            for _, dt in ipairs(state.dynamic_texts) do
                if dt.track_guid == trk_guid then
                    local in_scope = not selective
                    if selective and item_bounds_by_track[trk_guid] then
                        for _, b in ipairs(item_bounds_by_track[trk_guid]) do
                            if (dt.start_qn or 0) >= b.sqn - 0.5 and (dt.start_qn or 0) <= b.eqn + 0.5 then
                                in_scope = true
                                break
                            end
                        end
                    end
                    if in_scope then
                        DynamicTextService.apply_cc(state, dt, MidiService, active_tracks_data)
                    end
                end
            end
        end
    end
    
    if total_healed_dynamics > 0 then
        if HairpinService.save_hairpins then HairpinService.save_hairpins(state) end
        if DynamicTextService.save_dynamic_texts then DynamicTextService.save_dynamic_texts(state) end
    end
    
    local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
    if SlurService and SlurService.heal_slurs_and_ties then
        SlurService.heal_slurs_and_ties(state)
    end
    
    if total_fixed_notes == 0 and total_cleared_events == 0 and total_healed_dynamics == 0 then
        -- Playback is already synchronized with track sound bank!
        state.show_fix_last_resort_modal = true
        state.fix_last_resort_track_name = last_trk_name
        if selective then
            state.status_msg = string.format("⚡ Fix Playback (Selective): %s (%s) is already synchronized.",
                last_trk_name or "Track", single_item_name or "Item")
        else
            state.status_msg = "⚡ Fix Playback (Global): All project tracks and items are already synchronized."
        end
        reaper.Undo_EndBlock2(0, selective and "Notator: Fix Playback (Selective - In Sync)" or "Notator: Fix Playback (Global - In Sync)", -1)
        return true
    end
    
    state.show_fix_last_resort_modal = false
    reaper.Undo_EndBlock2(0, undo_title, -1)
    reaper.UpdateArrange()
    MidiService.invalidate_cache()
    state.active_tracks_cache = nil
    
    local parts = {}
    if total_cleared_events > 0 then table.insert(parts, string.format("%d cleared", total_cleared_events)) end
    if total_fixed_notes > 0 then table.insert(parts, string.format("%d synced", total_fixed_notes)) end
    if total_healed_dynamics > 0 then table.insert(parts, string.format("%d dynamics healed", total_healed_dynamics)) end
    if #parts == 0 then table.insert(parts, "0 changes") end
    
    if selective then
        state.status_msg = string.format("⚡ Fix Playback (Selective): %s (%s, %s)",
            last_trk_name or "Track", single_item_name or "1 item", table.concat(parts, ", "))
    else
        local total_trks = 0
        for _ in pairs(processed_track_guids) do total_trks = total_trks + 1 end
        state.status_msg = string.format("⚡ Fix Playback (Global): %d track(s), %d item(s), %s",
            total_trks, processed_takes or 0, table.concat(parts, ", "))
    end
    return true
end

-- ==============================================================================
-- ITEM CLEANUP TOOLS (Strictly Selected MIDI Item)
-- ==============================================================================

--- Clears all Program Changes (0xC0) and Bank Selects (CC0 / CC32) from the
--- active take of the selected MIDI item. Notes and other CCs are left untouched.
--- @param state table
--- @param active_tracks_data table|nil
--- @return number total_deleted
function MidiService.clear_program_bank_events(state, active_tracks_data)
    local target_item = nil
    if state and state.selected_item and reaper.ValidatePtr(state.selected_item, "MediaItem*") then
        target_item = state.selected_item
    elseif reaper.CountSelectedMediaItems(0) > 0 then
        target_item = reaper.GetSelectedMediaItem(0, 0)
    elseif state and state.selected_note and state.selected_note.item and reaper.ValidatePtr(state.selected_note.item, "MediaItem*") then
        target_item = state.selected_note.item
    elseif state and state.selected_notes and next(state.selected_notes) ~= nil then
        for _, sn in pairs(state.selected_notes) do
            if sn.item and reaper.ValidatePtr(sn.item, "MediaItem*") then
                target_item = sn.item
                break
            end
        end
    end

    if not target_item or not reaper.ValidatePtr(target_item, "MediaItem*") then
        local it, tk = MidiService.get_target_item_and_take(state, active_tracks_data)
        target_item = it
    end

    if not target_item or not reaper.ValidatePtr(target_item, "MediaItem*") then
        if state then
            state.status_msg = "Clear Program/Bank: Please select a MIDI item first!"
        end
        return 0
    end

    local take = (state and state.selected_take) or reaper.GetActiveTake(target_item)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") or not reaper.TakeIsMIDI(take) then
        if state then
            state.status_msg = "Clear Program/Bank: Selected item contains no active MIDI take!"
        end
        return 0
    end

    local _, item_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if not item_name or item_name == "" then
        local _, it_notes = reaper.GetSetMediaItemInfo_String(target_item, "P_NOTES", "", false)
        item_name = (it_notes ~= "") and it_notes or "Selected MIDI Item"
    end

    reaper.Undo_BeginBlock2(0)
    reaper.MIDI_DisableSort(take)

    local pc_cnt = 0
    local bank_cnt = 0

    -- 1. Scan and delete all Program Changes (0xC0) and Bank Selects (CC0 / CC32)
    local _, _, cccnt, textcnt = reaper.MIDI_CountEvts(take)
    for ci = (cccnt or 0) - 1, 0, -1 do
        local ok, _, _, _, chanmsg, _, msg2 = reaper.MIDI_GetCC(take, ci)
        if ok then
            local is_pc = (chanmsg == 192 or (chanmsg & 0xF0) == 0xC0)
            local is_bank = (chanmsg == 176 or (chanmsg & 0xF0) == 0xB0) and (msg2 == 0 or msg2 == 32)
            if is_pc then
                reaper.MIDI_DeleteCC(take, ci)
                pc_cnt = pc_cnt + 1
            elseif is_bank then
                reaper.MIDI_DeleteCC(take, ci)
                bank_cnt = bank_cnt + 1
            end
        end
    end

    -- 2. Remove any NOTATOR_CHASE text events in this take so old chase events don't retrigger
    local chase_cnt = 0
    for ti = (textcnt or 0) - 1, 0, -1 do
        local ok_t, _, _, _, _, msg_t = reaper.MIDI_GetTextSysexEvt(take, ti)
        if ok_t and msg_t and msg_t:find("NOTATOR_CHASE") then
            reaper.MIDI_DeleteTextSysexEvt(take, ti)
            chase_cnt = chase_cnt + 1
        end
    end

    -- 3. Reset articulation tags on any selected notes in state belonging to this take
    if state then
        if state.selected_notes then
            for _, sn in pairs(state.selected_notes) do
                if sn.take == take then
                    sn.articulation = nil
                end
            end
        end
        if state.selected_note and state.selected_note.take == take then
            state.selected_note.articulation = nil
        end
    end

    reaper.MIDI_Sort(take)
    local parent_track = reaper.GetMediaItemTake_Track(take)
    if parent_track and reaper.ValidatePtr(parent_track, "MediaTrack*") then
        reaper.MarkTrackItemsDirty(parent_track, target_item)
    end
    reaper.Undo_EndBlock2(0, "Notator: Clear Program & Bank Events", -1)
    reaper.UpdateArrange()

    if MidiService.invalidate_cache then
        MidiService.invalidate_cache()
    end
    if state then
        state.active_tracks_cache = nil
    end

    local total_deleted = pc_cnt + bank_cnt + chase_cnt
    if state then
        state.status_msg = string.format("🗑 Removed %d Program Change(s) and %d Bank Select(s) from '%s'", pc_cnt, bank_cnt, item_name)
    end

    return total_deleted
end

--- Cleans Type 15 notation text events (dynamics) from the selected MIDI item.
--- @param state table
--- @param active_tracks_data table|nil
function MidiService.clean_notation_events(state, active_tracks_data)
    local DynamicsEngine = package.loaded["services.dynamics_engine"] or require("services.dynamics_engine")
    if DynamicsEngine and DynamicsEngine.clean_notation_events then
        DynamicsEngine.clean_notation_events(state, MidiService, active_tracks_data)
    end
end

-- ==============================================================================
-- ORPHAN CLEANUP & SYNCHRONISATION (Item / Track Deletion Watchdog)
-- Cleans orphaned notation elements (hairpins, texts, pedals, octaves, dynamics,
-- repeat marks, and note selections) when their REAPER MIDI item or track was deleted.
-- ==============================================================================
function MidiService.cleanup_orphaned_score_elements(state)
    if not state then return end
    
    local num_tracks = reaper.CountTracks(0)
    local valid_tracks = {}
    local track_midi_spans = {}
    
    for t = 0, num_tracks - 1 do
        local trk = reaper.GetTrack(0, t)
        if trk then
            local guid = reaper.GetTrackGUID(trk)
            valid_tracks[guid] = true
            track_midi_spans[guid] = {}
            
            local num_items = reaper.CountTrackMediaItems(trk)
            for i = 0, num_items - 1 do
                local item = reaper.GetTrackMediaItem(trk, i)
                local take = item and reaper.GetActiveTake(item)
                if take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take) then
                    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                    local start_qn = reaper.TimeMap2_timeToQN(0, pos)
                    local end_qn = reaper.TimeMap2_timeToQN(0, pos + len)
                    table.insert(track_midi_spans[guid], {
                        start_qn = start_qn,
                        end_qn = end_qn
                    })
                end
            end
        end
    end
    
    local function interval_overlaps_midi(guid, q0, q1)
        if not guid or not valid_tracks[guid] then return false end
        local spans = track_midi_spans[guid]
        if not spans or #spans == 0 then return false end
        local q_start = math.min(q0, q1)
        local q_end = math.max(q0, q1)
        for _, sp in ipairs(spans) do
            if (q_start < sp.end_qn - 0.05) and (q_end > sp.start_qn + 0.05) then
                return true
            end
        end
        return false
    end
    
    local function point_inside_midi(guid, qn)
        if not guid or not valid_tracks[guid] then return false end
        local spans = track_midi_spans[guid]
        if not spans or #spans == 0 then return false end
        for _, sp in ipairs(spans) do
            if qn >= (sp.start_qn - 0.1) and qn <= (sp.end_qn + 0.1) then
                return true
            end
        end
        return false
    end
    
    local any_changed = false
    
    -- 1. Clean hairpins
    if state.hairpins and #state.hairpins > 0 then
        local kept_hairpins = {}
        local hp_changed = false
        for _, hp in ipairs(state.hairpins) do
            if interval_overlaps_midi(hp.track_guid, hp.start_qn, hp.end_qn) then
                table.insert(kept_hairpins, hp)
            else
                hp_changed = true
                if state.selected_hairpin and state.selected_hairpin.id == hp.id then
                    state.selected_hairpin = nil
                end
            end
        end
        if hp_changed then
            state.hairpins = kept_hairpins
            any_changed = true
            local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
            if HairpinService and HairpinService.save_hairpins then
                HairpinService.save_hairpins(state)
            end
        end
    end
    
    -- 2. Clean dynamic texts (cresc. / dim.)
    if state.dynamic_texts and #state.dynamic_texts > 0 then
        local kept_dt = {}
        local dt_changed = false
        for _, dt in ipairs(state.dynamic_texts) do
            if interval_overlaps_midi(dt.track_guid, dt.start_qn, dt.end_qn or (dt.start_qn + 1.0)) then
                table.insert(kept_dt, dt)
            else
                dt_changed = true
                if state.selected_dynamic_text and state.selected_dynamic_text.id == dt.id then
                    state.selected_dynamic_text = nil
                end
            end
        end
        if dt_changed then
            state.dynamic_texts = kept_dt
            any_changed = true
            local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
            if DynamicTextService and DynamicTextService.save_dynamic_texts then
                DynamicTextService.save_dynamic_texts(state)
            end
        end
    end
    
    -- 3. Clean pedal marks (CC64)
    if state.pedals and #state.pedals > 0 then
        local kept_pedals = {}
        local ped_changed = false
        for _, pm in ipairs(state.pedals) do
            if interval_overlaps_midi(pm.track_guid, pm.start_qn, pm.end_qn or (pm.start_qn + 1.0)) then
                table.insert(kept_pedals, pm)
            else
                ped_changed = true
                if state.selected_pedal and state.selected_pedal.id == pm.id then
                    state.selected_pedal = nil
                end
            end
        end
        if ped_changed then
            state.pedals = kept_pedals
            any_changed = true
            local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
            if PedalService and PedalService.save_pedals then
                PedalService.save_pedals(state)
            end
        end
    end
    
    -- 4. Clean octave lines
    if state.octave_lines and #state.octave_lines > 0 then
        local kept_octaves = {}
        local oct_changed = false
        for _, ol in ipairs(state.octave_lines) do
            if interval_overlaps_midi(ol.track_guid, ol.start_qn, ol.end_qn or (ol.start_qn + 1.0)) then
                table.insert(kept_octaves, ol)
            else
                oct_changed = true
                if state.selected_octave and state.selected_octave.id == ol.id then
                    state.selected_octave = nil
                end
            end
        end
        if oct_changed then
            state.octave_lines = kept_octaves
            any_changed = true
            local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
            if OctaveService and OctaveService.save_lines then
                OctaveService.save_lines(state)
            end
        end
    end
    
    -- 5. Clean repeat marks (Simile %)
    if state.repeat_marks and #state.repeat_marks > 0 then
        local kept_marks = {}
        local rep_changed = false
        for _, rm in ipairs(state.repeat_marks) do
            local guid = rm.track_guid
            if valid_tracks[guid] then
                local m_num = rm.measure or 0
                local m_start, m_end
                if reaper.TimeMap2_beatsToTime and reaper.TimeMap2_timeToQN then
                    local t0 = reaper.TimeMap2_beatsToTime(0, 0, m_num)
                    local t1 = reaper.TimeMap2_beatsToTime(0, 0, m_num + 1)
                    m_start = reaper.TimeMap2_timeToQN(0, t0)
                    m_end = reaper.TimeMap2_timeToQN(0, t1)
                else
                    m_start = m_num * 4.0
                    m_end = (m_num + 1) * 4.0
                end
                if track_midi_spans[guid] and #track_midi_spans[guid] > 0 and interval_overlaps_midi(guid, m_start, m_end) then
                    table.insert(kept_marks, rm)
                else
                    rep_changed = true
                end
            else
                rep_changed = true
            end
        end
        if rep_changed then
            state.repeat_marks = kept_marks
            any_changed = true
            local RepeatService = package.loaded["services.repeat_service"] or require("services.repeat_service")
            if RepeatService and RepeatService.save_repeat_marks then
                RepeatService.save_repeat_marks(state)
            end
        end
    end
    
    -- 6. Clean text items
    if state.text_items and #state.text_items > 0 then
        local kept_texts = {}
        local txt_changed = false
        for _, ti in ipairs(state.text_items) do
            if point_inside_midi(ti.track_guid, ti.qn or 0) then
                table.insert(kept_texts, ti)
            else
                txt_changed = true
                if state.selected_text_item and state.selected_text_item.id == ti.id then
                    state.selected_text_item = nil
                end
                if state.selected_text_items and state.selected_text_items[ti.id] then
                    state.selected_text_items[ti.id] = nil
                end
            end
        end
        if txt_changed then
            state.text_items = kept_texts
            any_changed = true
            local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
            if TextItemService and TextItemService.save_text_items then
                TextItemService.save_text_items(state)
            end
        end
    end
    
    -- 7. Clean invalid note and item selections
    if state.selected_notes and next(state.selected_notes) then
        local clean_sel_notes = {}
        local sel_changed = false
        for k, n in pairs(state.selected_notes) do
            if n.take and reaper.ValidatePtr(n.take, "MediaItem_Take*") then
                clean_sel_notes[k] = n
            else
                sel_changed = true
            end
        end
        if sel_changed then
            state.selected_notes = clean_sel_notes
            any_changed = true
        end
    end
    
    if state.selected_item and not reaper.ValidatePtr(state.selected_item, "MediaItem*") then
        state.selected_item = nil
        state.selected_take = nil
        any_changed = true
    end
    
    if state.focused_track and not reaper.ValidatePtr(state.focused_track, "MediaTrack*") then
        state.focused_track = nil
        any_changed = true
    end
    
    if state.selected_tracks then
        for guid in pairs(state.selected_tracks) do
            if not valid_tracks[guid] then
                state.selected_tracks[guid] = nil
                any_changed = true
            end
        end
    end
    
    -- 8. Clean and reset orphaned notes from shortened/deleted chord track items
    local ScaleService = package.loaded["services.scale_service"] or package.loaded["modules.services.scale_service"]
    if not ScaleService then
        pcall(function() ScaleService = require("services.scale_service") end)
    end
    if ScaleService and ScaleService.revert_orphaned_chord_notes then
        ScaleService.revert_orphaned_chord_notes(state)
    end
    
    -- 9. Clean orphaned slurs and ties
    if state.user_slurs and #state.user_slurs > 0 then
        local kept_slurs = {}
        local slur_changed = false
        for _, sl in ipairs(state.user_slurs) do
            if not sl.track_guid or sl.track_guid == "" or valid_tracks[sl.track_guid] then
                table.insert(kept_slurs, sl)
            else
                slur_changed = true
            end
        end
        if slur_changed then
            state.user_slurs = kept_slurs
            any_changed = true
            local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
            SlurService.save_slurs(state)
        end
    end
    if state.user_ties and #state.user_ties > 0 then
        local kept_ties = {}
        local tie_changed = false
        for _, tie in ipairs(state.user_ties) do
            local is_valid = false
            if not tie.track_guid or tie.track_guid == "" then
                is_valid = true
            elseif valid_tracks[tie.track_guid] then
                -- Locate the track and its takes
                local trk = nil
                for t = 0, num_tracks - 1 do
                    local cand = reaper.GetTrack(0, t)
                    if cand and reaper.GetTrackGUID(cand) == tie.track_guid then
                        trk = cand; break
                    end
                end
                if trk then
                    local num_items = reaper.CountTrackMediaItems(trk)
                    local found_take = false
                    for ii = 0, num_items - 1 do
                        local it = reaper.GetTrackMediaItem(trk, ii)
                        local tk = it and reaper.GetActiveTake(it)
                        if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") and reaper.TakeIsMIDI(tk) then
                            found_take = true
                            local n1_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk, tie.n1_start_qn or 0.0) + 0.5)
                            local n2_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk, tie.n2_start_qn or 1.0) + 0.5)
                            
                            local has_tag = false
                            local _, _, _, text_cnt = reaper.MIDI_CountEvts(tk)
                            for ti = 0, text_cnt - 1 do
                                local ok, _, _, _, etype, msg = reaper.MIDI_GetTextSysexEvt(tk, ti)
                                if ok and etype == 15 and msg:match("^NOTATOR_TIE%s+" .. tie.id) then
                                    has_tag = true; break
                                end
                            end
                            
                            local n1_match = false
                            local n2_match_muted = false
                            local n2_match_unmuted = false
                            local _, notecnt = reaper.MIDI_CountEvts(tk)
                            for ni = 0, notecnt - 1 do
                                local ok, _, muted, sppq, eppq, ch, p = reaper.MIDI_GetNote(tk, ni)
                                if ok and p == tie.pitch and (tie.chan == nil or ch == (tie.chan or 0)) then
                                    if math.abs(sppq - n1_sppq) <= 120 then
                                        if eppq >= n2_sppq + 10 then n1_match = true end
                                    end
                                    if math.abs(sppq - n2_sppq) <= 120 then
                                        if muted then n2_match_muted = true else n2_match_unmuted = true end
                                    end
                                end
                            end
                            
                            -- A tie requires that either Note 1 sustains into Note 2, Note 2 is muted, or has a tie tag.
                            -- If Note 2 is clearly unmuted and Note 1 does NOT cover Note 2,
                            -- then the user separated the notes in REAPER, making the tie an orphan.
                            if n2_match_unmuted and not n1_match and not n2_match_muted then
                                is_valid = false
                                if has_tag then
                                    for ti = text_cnt - 1, 0, -1 do
                                        local ok, _, _, _, etype, msg = reaper.MIDI_GetTextSysexEvt(tk, ti)
                                        if ok and etype == 15 and (msg:match("^NOTATOR_TIE%s+" .. tie.id) or msg:match("^NOTATOR_TIE_SLAVE%s+" .. tie.id)) then
                                            reaper.MIDI_DeleteTextSysexEvt(tk, ti)
                                        end
                                    end
                                end
                            elseif has_tag or n1_match or n2_match_muted then
                                is_valid = true
                                break
                            end
                        end
                    end
                    if not found_take then is_valid = false end
                end
            end
            if is_valid then
                table.insert(kept_ties, tie)
            else
                tie_changed = true
            end
        end
        if tie_changed then
            state.user_ties = kept_ties
            any_changed = true
            local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
            SlurService.save_slurs(state)
        end
    end
    
    -- 10. Clean orphaned glissandos
    if state.glissando_marks and #state.glissando_marks > 0 then
        local kept_gliss = {}
        local gliss_changed = false
        for _, gm in ipairs(state.glissando_marks) do
            if not gm.track_guid or gm.track_guid == "" or valid_tracks[gm.track_guid] then
                table.insert(kept_gliss, gm)
            else
                gliss_changed = true
                if state.selected_glissando and state.selected_glissando.id == gm.id then
                    state.selected_glissando = nil
                end
            end
        end
        if gliss_changed then
            state.glissando_marks = kept_gliss
            any_changed = true
            local GlissandoService = package.loaded["services.glissando_service"] or require("services.glissando_service")
            GlissandoService.save_glissandos(state)
        end
    end
    
    if any_changed and reaper.MarkProjectDirty then
        reaper.MarkProjectDirty(0)
    end
end

-- ==============================================================================
-- SLURS & TIES DELEGATOR INTERFACE
-- ==============================================================================

function MidiService.toggle_slur(state, active_tracks_data)
    local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
    return SlurService.toggle_slur(state, active_tracks_data)
end

function MidiService.toggle_tie(state, active_tracks_data)
    local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
    return SlurService.toggle_tie(state, active_tracks_data)
end

function MidiService.remove_slurs_and_ties(state, opt_notes)
    local SlurService = package.loaded["services.slur_service"] or require("services.slur_service")
    return SlurService.remove_slurs_and_ties(state, opt_notes)
end

function MidiService.toggle_portamento(state, active_tracks_data)
    local PortamentoService = package.loaded["services.portamento_service"] or require("services.portamento_service")
    return PortamentoService.toggle_portamento(state, active_tracks_data)
end

function MidiService.delete_portamento(state, port_id, active_tracks_data)
    local PortamentoService = package.loaded["services.portamento_service"] or require("services.portamento_service")
    return PortamentoService.delete_portamento(state, port_id, active_tracks_data)
end

function MidiService.remove_portamentos_for_notes(state, notes, active_tracks_data)
    local PortamentoService = package.loaded["services.portamento_service"] or require("services.portamento_service")
    return PortamentoService.remove_portamentos_for_notes(state, notes, active_tracks_data)
end

function MidiService.toggle_glissando(state, active_tracks_data)
    local GlissandoService = package.loaded["services.glissando_service"] or require("services.glissando_service")
    return GlissandoService.toggle_glissando(state, active_tracks_data)
end

function MidiService.delete_glissando(state, gliss_id, active_tracks_data)
    local GlissandoService = package.loaded["services.glissando_service"] or require("services.glissando_service")
    return GlissandoService.delete_glissando(state, gliss_id, active_tracks_data)
end

function MidiService.remove_glissandos_for_notes(state, notes, active_tracks_data)
    local GlissandoService = package.loaded["services.glissando_service"] or require("services.glissando_service")
    return GlissandoService.remove_glissandos_for_notes(state, notes, active_tracks_data)
end

return MidiService

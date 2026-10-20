-- ==============================================================================
-- REAPER-Notator Headless Unit Test & Fuzzing Mock Environment (mock_reaper.lua)
-- Emulates stateful REAPER Project/MIDI/Track/Take C-APIs and ReaImGui DrawList
-- with strict NaN/Inf/Nil coordinate validation and interactive UI Click Fuzzing.
-- ==============================================================================

local Mock = {}

local PPQ_PER_QN = 960.0

local function check_num(val, fn_name, arg_name)
    if type(val) ~= "number" then
        error(string.format("[DrawList Error] %s: '%s' is %s (%s), expected finite number", fn_name, arg_name, type(val), tostring(val)), 3)
    end
    if val ~= val or val == math.huge or val == -math.huge then
        error(string.format("[DrawList Error] %s: '%s' is NaN/Inf (%s)", fn_name, arg_name, tostring(val)), 3)
    end
end

function Mock.create_environment(repo_root)
    local env = {
        tracks = {},
        selected_tracks = {},
        selected_items = {},
        ext_state = {},
        proj_ext_state = {},
        tempo_markers = {},
        project_markers = {},
        edit_cursor = 0.0,
        play_pos = 0.0,
        play_state = 0, -- 0=stop, 1=play, 2=pause, 5=rec
        proj_change_cnt = 1,
        bpm = 120.0,
        ts_num = 4,
        ts_den = 4,
        draw_calls = 0,
        widget_counter = 0,
        click_target_idx = nil, -- When set to N, the N-th button/selectable returns true!
        max_widget_seen = 0,
        active_keys_down = {},
        active_keys_pressed = {},
        mouse_x = 400.0,
        mouse_y = 300.0,
        mouse_down = {},
        mouse_clicked = {},
        mouse_released = {},
        mouse_double_clicked = {},
        mouse_wheel_v = 0.0,
        mouse_wheel_h = 0.0,
        any_item_active = false,
        next_guid_id = 1000,
    }

    local function new_guid()
        env.next_guid_id = env.next_guid_id + 1
        return string.format("{00000000-0000-0000-0000-%012d}", env.next_guid_id)
    end

    local function qn_to_time(qn)
        return (qn or 0) * (60.0 / env.bpm)
    end

    local function time_to_qn(t)
        return (t or 0) * (env.bpm / 60.0)
    end

    local function pack_take_all_evts(take)
        -- Build valid REAPER MIDI_GetAllEvts binary stream from take.notes, take.ccs, take.text_evts
        local events = {}
        local item_start_qn = time_to_qn(take.item and take.item.pos or 0)
        for _, n in ipairs(take.notes) do
            local fl = (n.selected and 1 or 0) | (n.muted and 2 or 0)
            local ch = (n.chan or 0) & 0x0F
            table.insert(events, {
                ppq = math.max(0, math.floor((n.startppq or 0) + 0.5)),
                flags = fl,
                msg = string.char(0x90 | ch, math.max(0, math.min(127, math.floor(n.pitch or 60))), math.max(1, math.min(127, math.floor(n.vel or 90))))
            })
            table.insert(events, {
                ppq = math.max(0, math.floor((n.endppq or n.startppq or 0) + 0.5)),
                flags = fl,
                msg = string.char(0x80 | ch, math.max(0, math.min(127, math.floor(n.pitch or 60))), 0)
            })
        end
        for _, cc in ipairs(take.ccs) do
            local fl = (cc.selected and 1 or 0) | (cc.muted and 2 or 0) | ((cc.shape or 0) << 4)
            local ch = (cc.chan or 0) & 0x0F
            local chanmsg = cc.chanmsg or 0xB0
            table.insert(events, {
                ppq = math.max(0, math.floor((cc.ppqpos or 0) + 0.5)),
                flags = fl,
                msg = string.char((chanmsg & 0xF0) | ch, math.max(0, math.min(127, math.floor(cc.msg2 or 0))), math.max(0, math.min(127, math.floor(cc.msg3 or 0))))
            })
        end
        for _, tx in ipairs(take.text_evts) do
            local fl = (tx.selected and 1 or 0) | (tx.muted and 2 or 0)
            local ttype = math.max(1, math.min(15, math.floor(tx.type or 15)))
            local body = tostring(tx.msg or "")
            table.insert(events, {
                ppq = math.max(0, math.floor((tx.ppqpos or 0) + 0.5)),
                flags = fl,
                msg = string.char(0xFF, ttype) .. body
            })
        end
        table.sort(events, function(a, b)
            if a.ppq ~= b.ppq then return a.ppq < b.ppq end
            return #a.msg < #b.msg
        end)
        local chunks = {}
        local last_ppq = 0
        for _, ev in ipairs(events) do
            local dppq = ev.ppq - last_ppq
            last_ppq = ev.ppq
            table.insert(chunks, string.pack("i4Bs4", dppq, ev.flags, ev.msg))
        end
        -- All-Notes-Off tail event at item length
        local end_ppq = math.max(last_ppq, math.floor(time_to_qn(take.item and take.item.len or 4.0) * PPQ_PER_QN))
        table.insert(chunks, string.pack("i4Bs4", end_ppq - last_ppq, 0, string.char(0xB0, 0x7B, 0x00)))
        return table.concat(chunks)
    end

    local function unpack_take_all_evts(take, buf)
        if type(buf) ~= "string" or #buf == 0 then return false end
        local notes = {}
        local open_notes = {}
        local ccs = {}
        local text_evts = {}
        local pos = 1
        local len = #buf
        local cur_ppq = 0
        while pos + 8 <= len do
            local ok, offset, flags, msg, next_pos = pcall(string.unpack, "i4Bs4", buf, pos)
            if not ok then break end
            pos = next_pos
            cur_ppq = cur_ppq + offset
            if #msg >= 2 then
                local b1 = msg:byte(1)
                local b2 = msg:byte(2)
                if b1 == 0xFF then
                    local ttype = b2
                    local body = msg:sub(3)
                    table.insert(text_evts, {
                        selected = (flags & 1) ~= 0,
                        muted = (flags & 2) ~= 0,
                        ppqpos = cur_ppq,
                        type = ttype,
                        msg = body
                    })
                else
                    local status = b1 & 0xF0
                    local chan = b1 & 0x0F
                    local b3 = (#msg >= 3) and msg:byte(3) or 0
                    if status == 0x90 and b3 > 0 then
                        local key = chan * 256 + b2
                        open_notes[key] = open_notes[key] or {}
                        table.insert(open_notes[key], {
                            selected = (flags & 1) ~= 0,
                            muted = (flags & 2) ~= 0,
                            startppq = cur_ppq,
                            endppq = cur_ppq + 480,
                            chan = chan,
                            pitch = b2,
                            vel = b3
                        })
                    elseif status == 0x80 or (status == 0x90 and b3 == 0) then
                        local key = chan * 256 + b2
                        local stack = open_notes[key]
                        if stack and #stack > 0 then
                            local n = table.remove(stack, 1)
                            n.endppq = math.max(n.startppq + 1, cur_ppq)
                            table.insert(notes, n)
                        end
                    elseif status == 0xB0 or status == 0xC0 or status == 0xE0 or status == 0xD0 or status == 0xA0 then
                        if not (status == 0xB0 and b2 == 0x7B) then
                            table.insert(ccs, {
                                selected = (flags & 1) ~= 0,
                                muted = (flags & 2) ~= 0,
                                ppqpos = cur_ppq,
                                chanmsg = status,
                                chan = chan,
                                msg2 = b2,
                                msg3 = b3,
                                shape = (flags >> 4) & 0x0F,
                                beztension = 0.0
                            })
                        end
                    end
                end
            end
        end
        take.notes = notes
        take.ccs = ccs
        take.text_evts = text_evts
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end

    function env.add_track(name, col)
        local trk = {
            _type = "MediaTrack*",
            guid = new_guid(),
            name = name or ("Track " .. tostring(#env.tracks + 1)),
            color = col or 0x2A6F97,
            selected = (#env.tracks == 0),
            recarm = 0,
            recmon = 0,
            recmode = 0,
            recinput = 0,
            folderdepth = 0,
            heigth = 100,
            items = {},
            fx = {},
            ext_strings = {},
        }
        table.insert(env.tracks, trk)
        if trk.selected then
            table.insert(env.selected_tracks, trk)
        end
        env.proj_change_cnt = env.proj_change_cnt + 1
        return trk
    end

    function env.add_midi_item(trk, start_qn, end_qn)
        local pos = qn_to_time(start_qn or 0)
        local len = qn_to_time((end_qn or 16) - (start_qn or 0))
        local take = {
            _type = "MediaItem_Take*",
            guid = new_guid(),
            name = (trk.name or "Track") .. " MIDI",
            is_midi = true,
            notes = {},
            ccs = {},
            text_evts = {},
            ext_strings = {},
        }
        local item = {
            _type = "MediaItem*",
            guid = new_guid(),
            track = trk,
            pos = pos,
            len = len,
            selected = true,
            takes = { take },
            active_take = take,
            ext_strings = {},
        }
        take.item = item
        table.insert(trk.items, item)
        table.insert(env.selected_items, item)
        env.proj_change_cnt = env.proj_change_cnt + 1
        return item, take
    end

    local function check_widget_trigger()
        env.widget_counter = env.widget_counter + 1
        if env.widget_counter > env.max_widget_seen then
            env.max_widget_seen = env.widget_counter
        end
        if env.click_target_idx and env.widget_counter == env.click_target_idx then
            return true
        end
        return false
    end

    local r = {}
    r._mock = env

    -- Core REAPER APIs
    function r.GetResourcePath() return repo_root end
    function r.GetProjectPath() return repo_root end
    function r.GetProjectPathEx() return repo_root end
    function r.GetAppVersion() return "7.25/x64" end
    function r.GetOS() return "Win64" end
    function r.time_precise() return os.clock() end
    function r.EnumerateFiles(path, idx) return nil end
    function r.EnumerateSubdirectories(path, idx) return nil end
    function r.RecursiveCreateDirectory(path, ignored) return 1 end
    function r.file_exists(path)
        if type(path) ~= "string" then return false end
        local f = io.open(path, "rb")
        if f then f:close() return true end
        return false
    end
    function r.defer(fn) end
    function r.atexit(fn) end
    function r.ShowConsoleMsg(msg) end
    function r.ShowMessageBox(msg, title, t) return 1 end
    function r.MB(msg, title, t) return 1 end
    function r.Undo_BeginBlock() end
    function r.Undo_BeginBlock2(proj) end
    function r.Undo_EndBlock(desc, flags) env.proj_change_cnt = env.proj_change_cnt + 1 end
    function r.Undo_EndBlock2(proj, desc, flags) env.proj_change_cnt = env.proj_change_cnt + 1 end
    function r.Undo_CanUndo2(proj) return "Last Action" end
    function r.Undo_CanRedo2(proj) return nil end
    function r.Undo_DoUndo2(proj) return true end
    function r.Undo_DoRedo2(proj) return true end
    function r.PreventUIRefresh(cnt) end
    function r.UpdateArrange() end
    function r.UpdateTimeline() end
    function r.TrackList_AdjustWindows(isMinor) end
    function r.MarkProjectDirty(proj) env.proj_change_cnt = env.proj_change_cnt + 1 end
    function r.GetProjectStateChangeCount(proj) return env.proj_change_cnt end
    function r.Main_OnCommand(cmd, flag) end
    function r.NamedCommandLookup(name) return 50000 end
    function r.GetToggleCommandState(cmd) return 0 end
    function r.GetToggleCommandStateEx(sec, cmd) return 0 end
    function r.SetToggleCommandState(sec, cmd, st) return true end
    function r.RefreshToolbar2(sec, cmd) end

    function r.APIExists(name)
        if name == "JS_Window_Find" or name == "JS_Window_GetRect" then return false end
        return r[name] ~= nil or name:find("^ImGui_") ~= nil or name:find("^MIDI_") ~= nil
    end

    function r.ValidatePtr(ptr, ctype)
        if type(ptr) ~= "table" then return false end
        if not ctype then return true end
        return ptr._type == ctype
    end
    r.ValidatePtr2 = function(proj, ptr, ctype) return r.ValidatePtr(ptr, ctype) end

    -- ExtState & ProjExtState
    function r.GetExtState(sec, key)
        return (env.ext_state[sec] and env.ext_state[sec][key]) or ""
    end
    function r.SetExtState(sec, key, val, persist)
        env.ext_state[sec] = env.ext_state[sec] or {}
        env.ext_state[sec][key] = tostring(val or "")
    end
    function r.HasExtState(sec, key)
        return env.ext_state[sec] ~= nil and env.ext_state[sec][key] ~= nil and env.ext_state[sec][key] ~= ""
    end
    function r.DeleteExtState(sec, key, persist)
        if env.ext_state[sec] then env.ext_state[sec][key] = nil end
    end

    function r.GetProjExtState(proj, extname, key)
        local sec = env.proj_ext_state[extname and extname:upper() or ""]
        if sec and sec[key] ~= nil then
            return 1, sec[key]
        end
        return 0, ""
    end
    function r.SetProjExtState(proj, extname, key, val)
        local u = extname and extname:upper() or ""
        env.proj_ext_state[u] = env.proj_ext_state[u] or {}
        if key == "" or key == nil then
            env.proj_ext_state[u] = {}
        elseif val == "" or val == nil then
            env.proj_ext_state[u][key] = nil
        else
            env.proj_ext_state[u][key] = tostring(val)
        end
        env.proj_change_cnt = env.proj_change_cnt + 1
        return 1
    end
    function r.EnumProjExtState(proj, extname, idx)
        local u = extname and extname:upper() or ""
        local sec = env.proj_ext_state[u]
        if not sec then return false, "", "" end
        local keys = {}
        for k in pairs(sec) do table.insert(keys, k) end
        table.sort(keys)
        local k = keys[(idx or 0) + 1]
        if not k then return false, "", "" end
        return true, k, sec[k]
    end

    -- Transport & Cursor
    function r.GetPlayState() return env.play_state end
    function r.GetPlayStateEx(proj) return env.play_state end
    function r.GetPlayPosition() return env.play_pos end
    function r.GetPlayPosition2() return env.play_pos end
    function r.GetPlayPositionEx(proj) return env.play_pos end
    function r.GetCursorPosition() return env.edit_cursor end
    function r.GetCursorPositionEx(proj) return env.edit_cursor end
    function r.SetEditCurPos(time, moveview, seekplay) env.edit_cursor = tonumber(time) or 0 end
    function r.SetEditCurPos2(proj, time, moveview, seekplay) env.edit_cursor = tonumber(time) or 0 end
    function r.CSurf_OnPlay() env.play_state = 1 end
    function r.CSurf_OnPause() env.play_state = 2 end
    function r.CSurf_OnStop() env.play_state = 0 end
    function r.CSurf_OnRecord() env.play_state = 5 end
    function r.Master_GetTempo() return env.bpm end
    function r.SetCurrentBPM(proj, bpm, wantUndo) env.bpm = tonumber(bpm) or 120.0 return true end

    -- TimeMap & Tempo/TimeSignature
    function r.TimeMap2_QNToTime(proj, qn) return qn_to_time(qn) end
    function r.TimeMap_QNToTime(qn) return qn_to_time(qn) end
    function r.TimeMap_QNToTime_abs(proj, qn) return qn_to_time(qn) end
    function r.TimeMap2_timeToQN(proj, t) return time_to_qn(t) end
    function r.TimeMap_timeToQN(t) return time_to_qn(t) end
    function r.TimeMap_timeToQN_abs(proj, t) return time_to_qn(t) end
    function r.TimeMap_GetTimeSigAtTime(proj, time)
        return env.ts_num, env.ts_den, env.bpm
    end
    function r.TimeMap2_GetDividedBpmAtTime(proj, time) return env.bpm end
    function r.TimeMap_GetMeasureInfo(proj, measure)
        local m = math.max(0, math.floor(measure or 0))
        local qn_per_bar = env.ts_num * (4.0 / env.ts_den)
        local start_qn = m * qn_per_bar
        local end_qn = start_qn + qn_per_bar
        return qn_to_time(start_qn), start_qn, end_qn, env.ts_num, env.ts_den, env.bpm
    end
    function r.TimeMap_QNToMeasures(proj, qn)
        local qn_per_bar = env.ts_num * (4.0 / env.ts_den)
        local m = math.floor((qn or 0) / qn_per_bar)
        local m_start = m * qn_per_bar
        return m + 1, m_start, m_start + qn_per_bar
    end
    function r.TimeMap2_timeToBeats(proj, t)
        local qn = time_to_qn(t)
        local qn_per_bar = env.ts_num * (4.0 / env.ts_den)
        local m = math.floor(qn / qn_per_bar)
        local beats_in_bar = (qn - m * qn_per_bar) * (env.ts_den / 4.0)
        return beats_in_bar, m, env.ts_num, qn, env.ts_den
    end
    function r.TimeMap2_beatsToTime(proj, tpos, measures)
        local qn_per_bar = env.ts_num * (4.0 / env.ts_den)
        local qn = (measures or 0) * qn_per_bar + (tpos or 0) * (4.0 / env.ts_den)
        return qn_to_time(qn)
    end

    function r.CountTempoTimeSigMarkers(proj) return #env.tempo_markers end
    function r.GetTempoTimeSigMarker(proj, idx)
        local m = env.tempo_markers[(idx or 0) + 1]
        if not m then return false, 0, -1, 0, 120, 4, 4, false end
        return true, m.timepos or 0, m.measurepos or 0, m.beatpos or 0, m.bpm or 120, m.timesig_num or 4, m.timesig_denom or 4, m.lineartempo == true
    end
    function r.SetTempoTimeSigMarker(proj, ptidx, timepos, measurepos, beatpos, bpm, timesig_num, timesig_denom, lineartempo)
        local entry = {
            timepos = (timepos and timepos >= 0) and timepos or qn_to_time((measurepos or 0) * 4),
            measurepos = measurepos or 0,
            beatpos = beatpos or 0,
            bpm = (bpm and bpm > 0) and bpm or env.bpm,
            timesig_num = (timesig_num and timesig_num > 0) and timesig_num or env.ts_num,
            timesig_denom = (timesig_denom and timesig_denom > 0) and timesig_denom or env.ts_den,
            lineartempo = lineartempo == true
        }
        if ptidx == nil or ptidx < 0 or ptidx >= #env.tempo_markers then
            table.insert(env.tempo_markers, entry)
        else
            env.tempo_markers[ptidx + 1] = entry
        end
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end
    function r.DeleteTempoTimeSigMarker(proj, idx)
        if idx and env.tempo_markers[idx + 1] then
            table.remove(env.tempo_markers, idx + 1)
            env.proj_change_cnt = env.proj_change_cnt + 1
            return true
        end
        return false
    end
    function r.FindTempoTimeSigMarker(proj, time)
        return #env.tempo_markers - 1
    end

    -- Project Markers (Rehearsal Marks)
    function r.CountProjectMarkers(proj)
        return #env.project_markers, #env.project_markers, 0
    end
    function r.EnumProjectMarkers(idx)
        local m = env.project_markers[(idx or 0) + 1]
        if not m then return 0, false, 0, 0, "", 0 end
        return idx + 1, m.isrgn or false, m.pos or 0, m.rgnend or 0, m.name or "", m.markrgnindexnumber or (idx + 1)
    end
    function r.EnumProjectMarkers2(proj, idx)
        return r.EnumProjectMarkers(idx)
    end
    function r.EnumProjectMarkers3(proj, idx)
        local m = env.project_markers[(idx or 0) + 1]
        if not m then return 0, false, 0, 0, "", 0, 0 end
        return idx + 1, m.isrgn or false, m.pos or 0, m.rgnend or 0, m.name or "", m.markrgnindexnumber or (idx + 1), m.color or 0
    end
    function r.AddProjectMarker2(proj, isrgn, pos, rgnend, name, wantidx, color)
        local id = (wantidx and wantidx > 0) and wantidx or (#env.project_markers + 1)
        table.insert(env.project_markers, {
            isrgn = isrgn == true,
            pos = pos or 0,
            rgnend = rgnend or 0,
            name = name or "",
            markrgnindexnumber = id,
            color = color or 0
        })
        env.proj_change_cnt = env.proj_change_cnt + 1
        return id
    end
    function r.SetProjectMarkerByIndex2(proj, idx, isrgn, pos, rgnend, IDnumber, name, color, flags)
        local m = env.project_markers[(idx or 0) + 1]
        if not m then return false end
        m.isrgn = isrgn == true
        m.pos = pos or m.pos
        m.rgnend = rgnend or m.rgnend
        m.name = name or m.name
        m.color = color or m.color
        return true
    end
    function r.DeleteProjectMarkerByIndex(proj, idx)
        if env.project_markers[(idx or 0) + 1] then
            table.remove(env.project_markers, (idx or 0) + 1)
            return true
        end
        return false
    end
    function r.DeleteProjectMarker(proj, markrgnindexnumber, isrgn)
        for i, m in ipairs(env.project_markers) do
            if m.markrgnindexnumber == markrgnindexnumber then
                table.remove(env.project_markers, i)
                return true
            end
        end
        return false
    end

    -- Tracks
    function r.CountTracks(proj) return #env.tracks end
    function r.GetTrack(proj, idx) return env.tracks[(idx or 0) + 1] end
    function r.CountSelectedTracks(proj)
        local c = 0
        for _, t in ipairs(env.tracks) do if t.selected then c = c + 1 end end
        return c
    end
    function r.GetSelectedTrack(proj, sel_idx)
        local c = 0
        for _, t in ipairs(env.tracks) do
            if t.selected then
                if c == (sel_idx or 0) then return t end
                c = c + 1
            end
        end
        return nil
    end
    function r.IsTrackSelected(trk) return trk and trk.selected == true or false end
    function r.SetTrackSelected(trk, sel)
        if trk then trk.selected = (sel == true or sel == 1) end
    end
    function r.SetOnlyTrackSelected(trk)
        for _, t in ipairs(env.tracks) do t.selected = (t == trk) end
    end
    function r.GetTrackGUID(trk) return trk and trk.guid or "{00000000-0000-0000-0000-000000000000}" end
    function r.GetTrackName(trk)
        if not trk then return false, "" end
        return true, trk.name or "Track"
    end
    function r.GetTrackColor(trk) return trk and trk.color or 0 end
    function r.SetTrackColor(trk, col) if trk then trk.color = col end end
    function r.InsertTrackAtIndex(idx, wantDefaults)
        local trk = env.add_track("Track " .. tostring((idx or #env.tracks) + 1))
        return trk
    end
    function r.DeleteTrack(trk)
        for i, t in ipairs(env.tracks) do
            if t == trk then table.remove(env.tracks, i) break end
        end
    end
    function r.GetMediaTrackInfo_Value(trk, parm)
        if not trk then return 0 end
        if parm == "IP_TRACKNUMBER" then
            for i, t in ipairs(env.tracks) do if t == trk then return i end end
            return 1
        elseif parm == "I_RECARM" then return trk.recarm or 0
        elseif parm == "I_RECMON" then return trk.recmon or 0
        elseif parm == "I_RECMODE" then return trk.recmode or 0
        elseif parm == "I_RECINPUT" then return trk.recinput or 0
        elseif parm == "I_FOLDERDEPTH" then return trk.folderdepth or 0
        elseif parm == "I_CUSTOMCOLOR" then return trk.color or 0
        elseif parm == "I_SELECTED" then return trk.selected and 1 or 0
        elseif parm == "I_HEIGHTOVERRIDE" then return trk.height or 100
        end
        return trk[parm] or 0
    end
    function r.SetMediaTrackInfo_Value(trk, parm, val)
        if not trk then return false end
        if parm == "I_RECARM" then trk.recarm = val
        elseif parm == "I_RECMON" then trk.recmon = val
        elseif parm == "I_RECMODE" then trk.recmode = val
        elseif parm == "I_RECINPUT" then trk.recinput = val
        elseif parm == "I_FOLDERDEPTH" then trk.folderdepth = val
        elseif parm == "I_CUSTOMCOLOR" then trk.color = val
        elseif parm == "I_SELECTED" then trk.selected = (val == 1 or val == true)
        elseif parm == "I_HEIGHTOVERRIDE" then trk.height = val
        else trk[parm] = val
        end
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end
    function r.GetSetMediaTrackInfo_String(trk, parm, str, setNewValue)
        if not trk then return false, "" end
        trk.ext_strings = trk.ext_strings or {}
        if parm == "P_NAME" then
            if setNewValue then trk.name = tostring(str or "") end
            return true, trk.name or ""
        elseif parm == "GUID" then
            return true, trk.guid
        else
            if setNewValue then trk.ext_strings[parm] = tostring(str or "") end
            return true, trk.ext_strings[parm] or ""
        end
    end

    -- Track FX
    function r.TrackFX_GetCount(trk) return trk and trk.fx and #trk.fx or 0 end
    function r.TrackFX_GetFXName(trk, idx)
        local fx = trk and trk.fx and trk.fx[(idx or 0) + 1]
        if not fx then return false, "" end
        return true, fx.name or "JS:Reaticulate"
    end
    function r.TrackFX_AddByName(trk, fxname, recFX, instantiate)
        if not trk then return -1 end
        trk.fx = trk.fx or {}
        if instantiate == 0 then
            for i, f in ipairs(trk.fx) do
                if f.name:lower():find((fxname or ""):lower(), 1, true) then return i - 1 end
            end
            return -1
        end
        table.insert(trk.fx, { name = fxname or "FX", enabled = true, params = {} })
        return #trk.fx - 1
    end
    function r.TrackFX_Delete(trk, idx)
        if trk and trk.fx and trk.fx[(idx or 0) + 1] then
            table.remove(trk.fx, (idx or 0) + 1)
            return true
        end
        return false
    end
    function r.TrackFX_CopyToTrack(src_trk, src_fx, dst_trk, dst_fx, is_move)
        return true
    end
    function r.TrackFX_GetEnabled(trk, idx) return true end
    function r.TrackFX_SetEnabled(trk, idx, en) end
    function r.TrackFX_Show(trk, idx, showFlag) end
    function r.TrackFX_GetOpen(trk, idx) return false end
    function r.TrackFX_SetOpen(trk, idx, open) end
    function r.TrackFX_SetParam(trk, idx, param, val) return true end
    function r.TrackFX_GetParam(trk, idx, param) return 0, 0, 1 end

    -- Media Items & Takes
    function r.CountMediaItems(proj)
        local c = 0
        for _, t in ipairs(env.tracks) do c = c + #t.items end
        return c
    end
    function r.GetMediaItem(proj, idx)
        local c = 0
        for _, t in ipairs(env.tracks) do
            for _, it in ipairs(t.items) do
                if c == (idx or 0) then return it end
                c = c + 1
            end
        end
        return nil
    end
    function r.CountTrackMediaItems(trk) return trk and trk.items and #trk.items or 0 end
    function r.GetTrackMediaItem(trk, idx) return trk and trk.items and trk.items[(idx or 0) + 1] or nil end
    function r.CountSelectedMediaItems(proj)
        local c = 0
        for _, t in ipairs(env.tracks) do
            for _, it in ipairs(t.items) do if it.selected then c = c + 1 end end
        end
        return c
    end
    function r.GetSelectedMediaItem(proj, idx)
        local c = 0
        for _, t in ipairs(env.tracks) do
            for _, it in ipairs(t.items) do
                if it.selected then
                    if c == (idx or 0) then return it end
                    c = c + 1
                end
            end
        end
        return nil
    end
    function r.SetMediaItemSelected(item, sel)
        if item then item.selected = (sel == true or sel == 1) end
    end
    function r.GetMediaItem_Track(item) return item and item.track or nil end
    function r.GetMediaItemTrack(item) return item and item.track or nil end
    function r.GetMediaItemInfo_Value(item, parm)
        if not item then return 0 end
        if parm == "D_POSITION" then return item.pos or 0
        elseif parm == "D_LENGTH" then return item.len or 4
        elseif parm == "B_UISEL" then return item.selected and 1 or 0
        end
        return item[parm] or 0
    end
    function r.SetMediaItemInfo_Value(item, parm, val)
        if not item then return false end
        if parm == "D_POSITION" then item.pos = val
        elseif parm == "D_LENGTH" then item.len = val
        elseif parm == "B_UISEL" then item.selected = (val == 1 or val == true)
        else item[parm] = val
        end
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end
    function r.GetSetMediaItemInfo_String(item, parm, str, setNewValue)
        if not item then return false, "" end
        item.ext_strings = item.ext_strings or {}
        if parm == "GUID" then return true, item.guid end
        if setNewValue then item.ext_strings[parm] = tostring(str or "") end
        return true, item.ext_strings[parm] or ""
    end
    function r.CreateNewMIDIItemInProj(trk, start_time, end_time, qnInOptional)
        local s_qn = qnInOptional and start_time or time_to_qn(start_time or 0)
        local e_qn = qnInOptional and end_time or time_to_qn(end_time or 4)
        local item = env.add_midi_item(trk, s_qn, e_qn)
        return item
    end
    function r.DeleteTrackMediaItem(trk, item)
        if not trk or not trk.items then return false end
        for i, it in ipairs(trk.items) do
            if it == item then table.remove(trk.items, i) return true end
        end
        return false
    end
    function r.MIDI_SetItemExtents(item, start_qn, end_qn)
        if not item then return false end
        item.pos = qn_to_time(start_qn)
        item.len = qn_to_time(end_qn - start_qn)
        return true
    end

    -- Takes
    function r.CountTakes(item) return item and item.takes and #item.takes or 0 end
    function r.GetTake(item, idx) return item and item.takes and item.takes[(idx or 0) + 1] or nil end
    function r.GetActiveTake(item) return item and item.active_take or nil end
    function r.GetMediaItemTake(item, idx) return r.GetTake(item, idx) end
    function r.GetMediaItemTake_Item(take) return take and take.item or nil end
    function r.GetMediaItemTake_Track(take) return take and take.item and take.item.track or nil end
    function r.TakeIsMIDI(take) return take and take.is_midi == true or false end
    function r.GetTakeName(take) return take and take.name or "MIDI Take" end
    function r.GetSetMediaItemTakeInfo_String(take, parm, str, setNewValue)
        if not take then return false, "" end
        take.ext_strings = take.ext_strings or {}
        if parm == "GUID" then return true, take.guid end
        if parm == "P_NAME" then
            if setNewValue then take.name = tostring(str or "") end
            return true, take.name or ""
        end
        if setNewValue then take.ext_strings[parm] = tostring(str or "") end
        return true, take.ext_strings[parm] or ""
    end

    -- MIDI Editor & Take MIDI Operations
    function r.MIDIEditor_GetActive() return nil end
    function r.MIDIEditor_GetTake(ed) return nil end
    function r.MIDI_CountEvts(take)
        if not take then return 0, 0, 0, 0 end
        return 1, #(take.notes or {}), #(take.ccs or {}), #(take.text_evts or {})
    end
    function r.MIDI_GetHash(take, notesonly)
        if not take then return false, "" end
        return true, string.format("%d_%d_%d_%d", #(take.notes or {}), #(take.ccs or {}), #(take.text_evts or {}), env.proj_change_cnt)
    end
    r.MIDI_GetHash2 = r.MIDI_GetHash

    function r.MIDI_GetNote(take, idx)
        local n = take and take.notes and take.notes[(idx or 0) + 1]
        if not n then return false, false, false, 0, 0, 0, 0, 0 end
        return true, n.selected == true, n.muted == true, n.startppq or 0, n.endppq or 480, n.chan or 0, n.pitch or 60, n.vel or 90
    end
    function r.MIDI_InsertNote(take, selected, muted, startppqpos, endppqpos, chan, pitch, vel, noSortIn)
        if not take then return false end
        take.notes = take.notes or {}
        table.insert(take.notes, {
            selected = selected == true,
            muted = muted == true,
            startppq = math.floor((startppqpos or 0) + 0.5),
            endppq = math.floor((endppqpos or 480) + 0.5),
            chan = math.floor(chan or 0),
            pitch = math.floor(pitch or 60),
            vel = math.floor(vel or 90)
        })
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end
    function r.MIDI_SetNote(take, idx, selectedIn, mutedIn, startppqposIn, endppqposIn, chanIn, pitchIn, velIn, noSortIn)
        local n = take and take.notes and take.notes[(idx or 0) + 1]
        if not n then return false end
        if selectedIn ~= nil then n.selected = selectedIn == true end
        if mutedIn ~= nil then n.muted = mutedIn == true end
        if startppqposIn ~= nil then n.startppq = math.floor(startppqposIn + 0.5) end
        if endppqposIn ~= nil then n.endppq = math.floor(endppqposIn + 0.5) end
        if chanIn ~= nil then n.chan = math.floor(chanIn) end
        if pitchIn ~= nil then n.pitch = math.floor(pitchIn) end
        if velIn ~= nil then n.vel = math.floor(velIn) end
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end
    function r.MIDI_DeleteNote(take, idx)
        if take and take.notes and take.notes[(idx or 0) + 1] then
            table.remove(take.notes, (idx or 0) + 1)
            env.proj_change_cnt = env.proj_change_cnt + 1
            return true
        end
        return false
    end

    function r.MIDI_GetCC(take, idx)
        local cc = take and take.ccs and take.ccs[(idx or 0) + 1]
        if not cc then return false, false, false, 0, 0xB0, 0, 0, 0 end
        return true, cc.selected == true, cc.muted == true, cc.ppqpos or 0, cc.chanmsg or 0xB0, cc.chan or 0, cc.msg2 or 0, cc.msg3 or 0
    end
    function r.MIDI_InsertCC(take, selected, muted, ppqpos, chanmsg, chan, msg2, msg3)
        if not take then return false end
        take.ccs = take.ccs or {}
        table.insert(take.ccs, {
            selected = selected == true,
            muted = muted == true,
            ppqpos = math.floor((ppqpos or 0) + 0.5),
            chanmsg = chanmsg or 0xB0,
            chan = chan or 0,
            msg2 = msg2 or 0,
            msg3 = msg3 or 0,
            shape = 0,
            beztension = 0.0
        })
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end
    function r.MIDI_SetCC(take, idx, selectedIn, mutedIn, ppqposIn, chanmsgIn, chanIn, msg2In, msg3In, noSortIn)
        local cc = take and take.ccs and take.ccs[(idx or 0) + 1]
        if not cc then return false end
        if selectedIn ~= nil then cc.selected = selectedIn == true end
        if mutedIn ~= nil then cc.muted = mutedIn == true end
        if ppqposIn ~= nil then cc.ppqpos = math.floor(ppqposIn + 0.5) end
        if chanmsgIn ~= nil then cc.chanmsg = chanmsgIn end
        if chanIn ~= nil then cc.chan = chanIn end
        if msg2In ~= nil then cc.msg2 = msg2In end
        if msg3In ~= nil then cc.msg3 = msg3In end
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end
    function r.MIDI_DeleteCC(take, idx)
        if take and take.ccs and take.ccs[(idx or 0) + 1] then
            table.remove(take.ccs, (idx or 0) + 1)
            env.proj_change_cnt = env.proj_change_cnt + 1
            return true
        end
        return false
    end
    function r.MIDI_GetCCShape(take, idx)
        local cc = take and take.ccs and take.ccs[(idx or 0) + 1]
        if not cc then return false, 0, 0.0 end
        return true, cc.shape or 0, cc.beztension or 0.0
    end
    function r.MIDI_SetCCShape(take, idx, shape, beztension, noSortIn)
        local cc = take and take.ccs and take.ccs[(idx or 0) + 1]
        if not cc then return false end
        cc.shape = shape or 0
        cc.beztension = beztension or 0.0
        return true
    end

    function r.MIDI_GetTextSysexEvt(take, idx, selectedOut, mutedOut, ppqposOut, typeOut, msgOut)
        local tx = take and take.text_evts and take.text_evts[(idx or 0) + 1]
        if not tx then return false, false, false, 0, 15, "" end
        return true, tx.selected == true, tx.muted == true, tx.ppqpos or 0, tx.type or 15, tx.msg or ""
    end
    function r.MIDI_InsertTextSysexEvt(take, selected, muted, ppqpos, ttype, bytestr)
        if not take then return false end
        take.text_evts = take.text_evts or {}
        table.insert(take.text_evts, {
            selected = selected == true,
            muted = muted == true,
            ppqpos = math.floor((ppqpos or 0) + 0.5),
            type = ttype or 15,
            msg = tostring(bytestr or "")
        })
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end
    function r.MIDI_SetTextSysexEvt(take, idx, selectedIn, mutedIn, ppqposIn, typeIn, bytestrIn, noSortIn)
        local tx = take and take.text_evts and take.text_evts[(idx or 0) + 1]
        if not tx then return false end
        if selectedIn ~= nil then tx.selected = selectedIn == true end
        if mutedIn ~= nil then tx.muted = mutedIn == true end
        if ppqposIn ~= nil then tx.ppqpos = math.floor(ppqposIn + 0.5) end
        if typeIn ~= nil then tx.type = typeIn end
        if bytestrIn ~= nil then tx.msg = tostring(bytestrIn) end
        env.proj_change_cnt = env.proj_change_cnt + 1
        return true
    end
    function r.MIDI_DeleteTextSysexEvt(take, idx)
        if take and take.text_evts and take.text_evts[(idx or 0) + 1] then
            table.remove(take.text_evts, (idx or 0) + 1)
            env.proj_change_cnt = env.proj_change_cnt + 1
            return true
        end
        return false
    end

    function r.MIDI_Sort(take)
        if not take then return end
        if take.notes then
            table.sort(take.notes, function(a, b)
                if a.startppq ~= b.startppq then return a.startppq < b.startppq end
                return (a.pitch or 0) < (b.pitch or 0)
            end)
        end
        if take.ccs then
            table.sort(take.ccs, function(a, b) return (a.ppqpos or 0) < (b.ppqpos or 0) end)
        end
        if take.text_evts then
            table.sort(take.text_evts, function(a, b) return (a.ppqpos or 0) < (b.ppqpos or 0) end)
        end
    end
    function r.MIDI_DisableSort(take) end

    function r.MIDI_GetAllEvts(take)
        if not take then return false, "" end
        return true, pack_take_all_evts(take)
    end
    function r.MIDI_SetAllEvts(take, buf)
        if not take then return false end
        return unpack_take_all_evts(take, buf)
    end

    function r.MIDI_GetProjQNFromPPQPos(take, ppq)
        local item_start_qn = time_to_qn(take and take.item and take.item.pos or 0)
        return item_start_qn + ((ppq or 0) / PPQ_PER_QN)
    end
    function r.MIDI_GetPPQPosFromProjQN(take, qn)
        local item_start_qn = time_to_qn(take and take.item and take.item.pos or 0)
        return ((qn or 0) - item_start_qn) * PPQ_PER_QN
    end
    function r.MIDI_GetProjTimeFromPPQPos(take, ppq)
        return qn_to_time(r.MIDI_GetProjQNFromPPQPos(take, ppq))
    end
    function r.MIDI_GetPPQPosFromProjTime(take, t)
        return r.MIDI_GetPPQPosFromProjQN(take, time_to_qn(t))
    end
    function r.MIDI_GetPPQPos_StartOfMeasure(take, ppq)
        local qn = r.MIDI_GetProjQNFromPPQPos(take, ppq)
        local qn_per_bar = env.ts_num * (4.0 / env.ts_den)
        local bar_start_qn = math.floor(qn / qn_per_bar) * qn_per_bar
        return r.MIDI_GetPPQPosFromProjQN(take, bar_start_qn)
    end
    function r.MIDI_GetPPQPos_EndOfMeasure(take, ppq)
        local qn = r.MIDI_GetProjQNFromPPQPos(take, ppq)
        local qn_per_bar = env.ts_num * (4.0 / env.ts_den)
        local bar_end_qn = (math.floor(qn / qn_per_bar) + 1) * qn_per_bar
        return r.MIDI_GetPPQPosFromProjQN(take, bar_end_qn)
    end
    function r.MIDI_GetRecentInputEvent(idx)
        return 0, "", 0, 0, 0, 0
    end
    function r.StuffMIDIMessage(mode, msg1, msg2, msg3) end
    function r.GetNumMIDIInputs() return 2 end
    function r.GetMIDIInputName(idx, nameout) return true, "Mock MIDI Keyboard " .. tostring(idx) end

    -- ReaImGui Context & DrawList Validation
    local mock_ctx = { _type = "ImGui_Context*" }
    local mock_dl  = { _type = "ImGui_DrawList*" }
    local mock_font = { _type = "ImGui_Font*" }

    function r.ImGui_CreateContext(label) return mock_ctx end
    function r.ImGui_ValidatePtr(ptr, ctype)
        if type(ptr) == "table" and ptr._type == ctype then return true end
        return false
    end
    function r.ImGui_GetWindowDrawList(ctx) return mock_dl end
    function r.ImGui_GetForegroundDrawList(ctx) return mock_dl end
    function r.ImGui_GetBackgroundDrawList(ctx) return mock_dl end
    function r.ImGui_CreateFont(name, size, flags) return mock_font end
    function r.ImGui_CreateFontFromFile(file, idx, flags) return mock_font end
    function r.ImGui_CreateImageFromFile(file) return { _type = "ImGui_Image*", file = file } end
    function r.ImGui_CreateImageFromMem(data) return { _type = "ImGui_Image*" } end
    function r.ImGui_Attach(ctx, obj) end
    function r.ImGui_Detach(ctx, obj) end
    function r.ImGui_PushFont(ctx, font, size) end
    function r.ImGui_PopFont(ctx) end

    -- Strict DrawList Functions with NaN / Inf / Nil checks!
    function r.ImGui_DrawList_AddLine(dl, x1, y1, x2, y2, col, thick)
        check_num(x1, "AddLine", "x1")
        check_num(y1, "AddLine", "y1")
        check_num(x2, "AddLine", "x2")
        check_num(y2, "AddLine", "y2")
        check_num(col, "AddLine", "col")
        if thick ~= nil then check_num(thick, "AddLine", "thick") end
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, col, rounding, flags, thick)
        check_num(x1, "AddRect", "x1")
        check_num(y1, "AddRect", "y1")
        check_num(x2, "AddRect", "x2")
        check_num(y2, "AddRect", "y2")
        check_num(col, "AddRect", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, col, rounding, flags)
        check_num(x1, "AddRectFilled", "x1")
        check_num(y1, "AddRectFilled", "y1")
        check_num(x2, "AddRectFilled", "x2")
        check_num(y2, "AddRectFilled", "y2")
        check_num(col, "AddRectFilled", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddQuad(dl, x1, y1, x2, y2, x3, y3, x4, y4, col, thick)
        check_num(x1, "AddQuad", "x1"); check_num(y1, "AddQuad", "y1")
        check_num(x2, "AddQuad", "x2"); check_num(y2, "AddQuad", "y2")
        check_num(x3, "AddQuad", "x3"); check_num(y3, "AddQuad", "y3")
        check_num(x4, "AddQuad", "x4"); check_num(y4, "AddQuad", "y4")
        check_num(col, "AddQuad", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddQuadFilled(dl, x1, y1, x2, y2, x3, y3, x4, y4, col)
        check_num(x1, "AddQuadFilled", "x1"); check_num(y1, "AddQuadFilled", "y1")
        check_num(x2, "AddQuadFilled", "x2"); check_num(y2, "AddQuadFilled", "y2")
        check_num(x3, "AddQuadFilled", "x3"); check_num(y3, "AddQuadFilled", "y3")
        check_num(x4, "AddQuadFilled", "x4"); check_num(y4, "AddQuadFilled", "y4")
        check_num(col, "AddQuadFilled", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddTriangle(dl, x1, y1, x2, y2, x3, y3, col, thick)
        check_num(x1, "AddTriangle", "x1"); check_num(y1, "AddTriangle", "y1")
        check_num(x2, "AddTriangle", "x2"); check_num(y2, "AddTriangle", "y2")
        check_num(x3, "AddTriangle", "x3"); check_num(y3, "AddTriangle", "y3")
        check_num(col, "AddTriangle", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddTriangleFilled(dl, x1, y1, x2, y2, x3, y3, col)
        check_num(x1, "AddTriangleFilled", "x1"); check_num(y1, "AddTriangleFilled", "y1")
        check_num(x2, "AddTriangleFilled", "x2"); check_num(y2, "AddTriangleFilled", "y2")
        check_num(x3, "AddTriangleFilled", "x3"); check_num(y3, "AddTriangleFilled", "y3")
        check_num(col, "AddTriangleFilled", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddCircle(dl, x, y, rad, col, num_seg, thick)
        check_num(x, "AddCircle", "x"); check_num(y, "AddCircle", "y")
        check_num(rad, "AddCircle", "rad"); check_num(col, "AddCircle", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddCircleFilled(dl, x, y, rad, col, num_seg)
        check_num(x, "AddCircleFilled", "x"); check_num(y, "AddCircleFilled", "y")
        check_num(rad, "AddCircleFilled", "rad"); check_num(col, "AddCircleFilled", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddBezierCubic(dl, x1, y1, x2, y2, x3, y3, x4, y4, col, thick, num_seg)
        check_num(x1, "AddBezierCubic", "x1"); check_num(y1, "AddBezierCubic", "y1")
        check_num(x2, "AddBezierCubic", "x2"); check_num(y2, "AddBezierCubic", "y2")
        check_num(x3, "AddBezierCubic", "x3"); check_num(y3, "AddBezierCubic", "y3")
        check_num(x4, "AddBezierCubic", "x4"); check_num(y4, "AddBezierCubic", "y4")
        check_num(col, "AddBezierCubic", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddBezierQuadratic(dl, x1, y1, x2, y2, x3, y3, col, thick, num_seg)
        check_num(x1, "AddBezierQuadratic", "x1"); check_num(y1, "AddBezierQuadratic", "y1")
        check_num(x2, "AddBezierQuadratic", "x2"); check_num(y2, "AddBezierQuadratic", "y2")
        check_num(x3, "AddBezierQuadratic", "x3"); check_num(y3, "AddBezierQuadratic", "y3")
        check_num(col, "AddBezierQuadratic", "col")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddText(dl, x, y, col, text)
        check_num(x, "AddText", "x"); check_num(y, "AddText", "y")
        check_num(col, "AddText", "col")
        if type(text) ~= "string" then
            error("[DrawList Error] AddText: text is " .. type(text), 2)
        end
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddTextEx(dl, font, size, x, y, col, text, wrap_w, cpu_fine_clip)
        check_num(size, "AddTextEx", "size")
        check_num(x, "AddTextEx", "x"); check_num(y, "AddTextEx", "y")
        check_num(col, "AddTextEx", "col")
        if type(text) ~= "string" then
            error("[DrawList Error] AddTextEx: text is " .. type(text), 2)
        end
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_AddImage(dl, img, x1, y1, x2, y2, u1, v1, u2, v2, col)
        check_num(x1, "AddImage", "x1"); check_num(y1, "AddImage", "y1")
        check_num(x2, "AddImage", "x2"); check_num(y2, "AddImage", "y2")
        env.draw_calls = env.draw_calls + 1
    end
    function r.ImGui_DrawList_PushClipRect(dl, x1, y1, x2, y2, intersect)
        check_num(x1, "PushClipRect", "x1"); check_num(y1, "PushClipRect", "y1")
        check_num(x2, "PushClipRect", "x2"); check_num(y2, "PushClipRect", "y2")
    end
    function r.ImGui_DrawList_PopClipRect(dl) end

    -- ReaImGui Windows, Layout & Interactive Widgets (with strict stack balance tracking!)
    env.imgui_win_depth = 0
    env.imgui_child_depth = 0
    env.imgui_style_color_depth = 0
    env.imgui_style_var_depth = 0

    function r.ImGui_Begin(ctx, name, p_open, flags)
        env.imgui_win_depth = (env.imgui_win_depth or 0) + 1
        return true, true
    end
    function r.ImGui_End(ctx)
        if (env.imgui_win_depth or 0) <= 0 then
            error("[ReaImGui Stack Error] ImGui_End called without matching ImGui_Begin!", 2)
        end
        env.imgui_win_depth = env.imgui_win_depth - 1
    end
    function r.ImGui_BeginChild(ctx, id, w, h, child_flags, win_flags)
        env.imgui_child_depth = (env.imgui_child_depth or 0) + 1
        return true
    end
    function r.ImGui_EndChild(ctx)
        if (env.imgui_child_depth or 0) <= 0 then
            error("[ReaImGui Stack Error] ImGui_EndChild called without matching ImGui_BeginChild!", 2)
        end
        env.imgui_child_depth = env.imgui_child_depth - 1
    end
    function r.ImGui_BeginGroup(ctx) end
    function r.ImGui_EndGroup(ctx) end
    function r.ImGui_BeginPopup(ctx, id, flags) return true end
    function r.ImGui_BeginPopupModal(ctx, name, p_open, flags) return true, true end
    function r.ImGui_BeginPopupContextItem(ctx, id, flags) return false end
    function r.ImGui_BeginPopupContextWindow(ctx, id, flags) return false end
    function r.ImGui_EndPopup(ctx) end
    function r.ImGui_OpenPopup(ctx, id, flags) end
    function r.ImGui_CloseCurrentPopup(ctx) end
    function r.ImGui_IsPopupOpen(ctx, id, flags) return false end
    function r.ImGui_BeginCombo(ctx, label, preview, flags) return check_widget_trigger() end
    function r.ImGui_EndCombo(ctx) end
    function r.ImGui_BeginTabBar(ctx, id, flags) return true end
    function r.ImGui_EndTabBar(ctx) end
    function r.ImGui_BeginTabItem(ctx, label, p_open, flags) return true, true end
    function r.ImGui_EndTabItem(ctx) end
    function r.ImGui_BeginTable(ctx, id, col, flags, outer_w, outer_h) return true end
    function r.ImGui_EndTable(ctx) end
    function r.ImGui_TableNextRow(ctx, flags, min_h) end
    function r.ImGui_TableNextColumn(ctx) return true end
    function r.ImGui_TableSetColumnIndex(ctx, idx) return true end
    function r.ImGui_TableSetupColumn(ctx, label, flags, init_w, user_id) end
    function r.ImGui_TableHeadersRow(ctx) end
    function r.ImGui_CollapsingHeader(ctx, label, p_vis, flags) return true, true end
    function r.ImGui_TreeNode(ctx, label, flags) return true end
    function r.ImGui_TreePop(ctx) end
    function r.ImGui_BeginTooltip(ctx) return true end
    function r.ImGui_EndTooltip(ctx) end
    function r.ImGui_SetTooltip(ctx, text) end
    function r.ImGui_BeginDisabled(ctx, disabled) end
    function r.ImGui_EndDisabled(ctx) end

    function r.ImGui_Button(ctx, label, w, h)
        if env.force_button_click_pattern and type(label) == "string" and label:find(env.force_button_click_pattern, 1, true) then return true end
        return check_widget_trigger()
    end
    function r.ImGui_SmallButton(ctx, label)
        if env.force_button_click_pattern and type(label) == "string" and label:find(env.force_button_click_pattern, 1, true) then return true end
        return check_widget_trigger()
    end
    function r.ImGui_InvisibleButton(ctx, id, w, h, flags) return check_widget_trigger() end
    function r.ImGui_ArrowButton(ctx, id, dir) return check_widget_trigger() end
    function r.ImGui_RadioButton(ctx, label, active) return check_widget_trigger() end
    function r.ImGui_RadioButtonEx(ctx, label, v, v_button)
        local trig = check_widget_trigger()
        return trig, trig and v_button or v
    end
    function r.ImGui_Checkbox(ctx, label, v)
        local trig = check_widget_trigger()
        return trig, trig and (not v) or v
    end
    function r.ImGui_Selectable(ctx, label, selected, flags, w, h)
        local trig = check_widget_trigger()
        return trig, trig and (not selected) or selected
    end
    function r.ImGui_MenuItem(ctx, label, shortcut, selected, enabled)
        local trig = check_widget_trigger()
        return trig, trig and (not selected) or selected
    end
    function r.ImGui_SliderDouble(ctx, label, v, v_min, v_max, fmt, flags) return false, v or v_min or 0 end
    function r.ImGui_SliderInt(ctx, label, v, v_min, v_max, fmt, flags) return false, v or v_min or 0 end
    function r.ImGui_DragDouble(ctx, label, v, speed, v_min, v_max, fmt, flags) return false, v or 0 end
    function r.ImGui_DragInt(ctx, label, v, speed, v_min, v_max, fmt, flags) return false, v or 0 end
    function r.ImGui_InputText(ctx, label, buf, flags) return false, buf or "" end
    function r.ImGui_InputTextWithHint(ctx, label, hint, buf, flags) return false, buf or "" end
    function r.ImGui_InputInt(ctx, label, v, step, step_fast, flags) return false, v or 0 end
    function r.ImGui_InputDouble(ctx, label, v, step, step_fast, fmt, flags) return false, v or 0 end
    function r.ImGui_Combo(ctx, label, cur_item, items, popup_max_h) return false, cur_item or 0 end
    function r.ImGui_ColorEdit4(ctx, label, col, flags) return false, col or 0xFFFFFFFF end
    function r.ImGui_ColorEdit3(ctx, label, col, flags) return false, col or 0xFFFFFFFF end
    function r.ImGui_ColorButton(ctx, desc_id, col, flags, w, h) return check_widget_trigger() end
    function r.ImGui_ProgressBar(ctx, frac, w, h, overlay) end

    -- Text & Layout Queries
    function r.ImGui_Text(ctx, text) end
    function r.ImGui_TextColored(ctx, col, text) end
    function r.ImGui_TextDisabled(ctx, text) end
    function r.ImGui_TextWrapped(ctx, text) end
    function r.ImGui_BulletText(ctx, text) end
    function r.ImGui_Separator(ctx) end
    function r.ImGui_Spacing(ctx) end
    function r.ImGui_Dummy(ctx, w, h) end
    function r.ImGui_NewLine(ctx) end
    function r.ImGui_SameLine(ctx, offset, spacing) end
    function r.ImGui_Indent(ctx, indent_w) end
    function r.ImGui_Unindent(ctx, indent_w) end
    function r.ImGui_CalcTextSize(ctx, text, hide_after, wrap_w)
        local s = tostring(text or "")
        return #s * 7.0, 14.0
    end
    function r.ImGui_GetCursorScreenPos(ctx) return 100.0, 100.0 end
    function r.ImGui_SetCursorScreenPos(ctx, x, y) check_num(x, "SetCursorScreenPos", "x"); check_num(y, "SetCursorScreenPos", "y") end
    function r.ImGui_GetCursorPos(ctx) return 10.0, 10.0 end
    function r.ImGui_GetCursorPosX(ctx) return 10.0 end
    function r.ImGui_GetCursorPosY(ctx) return 10.0 end
    function r.ImGui_SetCursorPos(ctx, x, y) end
    function r.ImGui_SetCursorPosX(ctx, x) end
    function r.ImGui_SetCursorPosY(ctx, y) end
    function r.ImGui_GetContentRegionAvail(ctx) return 1000.0, 650.0 end
    function r.ImGui_GetWindowSize(ctx) return 1280.0, 720.0 end
    function r.ImGui_GetWindowWidth(ctx) return 1280.0 end
    function r.ImGui_GetWindowHeight(ctx) return 720.0 end
    function r.ImGui_GetWindowPos(ctx) return 50.0, 50.0 end
    function r.ImGui_SetNextWindowSize(ctx, w, h, cond) end
    function r.ImGui_SetNextWindowSizeConstraints(ctx, min_w, min_h, max_w, max_h) end
    function r.ImGui_SetNextWindowPos(ctx, x, y, cond, piv_x, piv_y) end
    function r.ImGui_SetNextWindowFocus(ctx) end
    function r.ImGui_SetNextWindowCollapsed(ctx, col, cond) end
    function r.ImGui_SetNextWindowBgAlpha(ctx, alpha) end
    function r.ImGui_SetNextItemWidth(ctx, w) end
    function r.ImGui_PushItemWidth(ctx, w) end
    function r.ImGui_PopItemWidth(ctx) end
    function r.ImGui_PushStyleColor(ctx, idx, col)
        env.imgui_style_color_depth = (env.imgui_style_color_depth or 0) + 1
    end
    function r.ImGui_PopStyleColor(ctx, cnt)
        env.imgui_style_color_depth = math.max(0, (env.imgui_style_color_depth or 0) - (cnt or 1))
    end
    function r.ImGui_PushStyleVar(ctx, idx, val1, val2)
        env.imgui_style_var_depth = (env.imgui_style_var_depth or 0) + 1
    end
    function r.ImGui_PopStyleVar(ctx, cnt)
        env.imgui_style_var_depth = math.max(0, (env.imgui_style_var_depth or 0) - (cnt or 1))
    end
    function r.ImGui_PushID(ctx, id) end
    function r.ImGui_PopID(ctx) end
    function r.ImGui_GetItemRectMin(ctx) return 100.0, 100.0 end
    function r.ImGui_GetItemRectMax(ctx) return 180.0, 124.0 end
    function r.ImGui_GetItemRectSize(ctx) return 80.0, 24.0 end
    function r.ImGui_IsItemHovered(ctx, flags) return env.item_hovered == true end
    function r.ImGui_IsItemActive(ctx) return env.any_item_active end
    function r.ImGui_IsItemClicked(ctx, btn) return false end
    function r.ImGui_IsItemActivated(ctx) return false end
    function r.ImGui_IsItemDeactivated(ctx) return false end
    function r.ImGui_IsItemDeactivatedAfterEdit(ctx) return false end
    function r.ImGui_IsAnyItemActive(ctx) return env.any_item_active end
    function r.ImGui_IsAnyItemHovered(ctx) return false end
    function r.ImGui_IsWindowHovered(ctx, flags) return true end
    function r.ImGui_IsWindowFocused(ctx, flags) return true end
    function r.ImGui_IsWindowAppearing(ctx) return false end
    function r.ImGui_SetKeyboardFocusHere(ctx, offset) end

    -- Mouse & Keyboard Queries
    function r.ImGui_GetMousePos(ctx) return env.mouse_x, env.mouse_y end
    function r.ImGui_IsMouseDown(ctx, btn) return env.mouse_down[btn or 0] == true end
    function r.ImGui_IsMouseClicked(ctx, btn, rep) return env.mouse_clicked[btn or 0] == true end
    function r.ImGui_IsMouseReleased(ctx, btn) return env.mouse_released[btn or 0] == true end
    function r.ImGui_IsMouseDoubleClicked(ctx, btn) return env.mouse_double_clicked[btn or 0] == true end
    function r.ImGui_IsMouseDragging(ctx, btn, lock_threshold) return env.mouse_down[btn or 0] == true end
    function r.ImGui_GetMouseDragDelta(ctx, x, y, btn, lock_threshold) return 12.0, 4.0 end
    function r.ImGui_GetMouseWheel(ctx) return env.mouse_wheel_v, env.mouse_wheel_h end
    function r.ImGui_SetMouseCursor(ctx, cur) end
    function r.ImGui_IsKeyPressed(ctx, key, rep) return env.active_keys_pressed[key] == true end
    function r.ImGui_IsKeyDown(ctx, key) return env.active_keys_down[key] == true end
    function r.ImGui_IsKeyReleased(ctx, key) return false end
    function r.ImGui_GetKeyMods(ctx) return env.key_mods or 0 end
    function r.ImGui_Viewport_GetWorkPos(vp) return 0, 0 end
    function r.ImGui_Viewport_GetWorkSize(vp) return 1920, 1080 end
    function r.ImGui_GetMainViewport(ctx) return {} end
    function r.ImGui_GetWindowViewport(ctx) return {} end
    function r.ImGui_PointConvertNative(ctx, x, y, to_native) return x or 0, y or 0 end
    function r.ColorFromNative(col)
        local c = tonumber(col) or 0
        return (c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF
    end
    function r.ColorToNative(r_val, g_val, b_val)
        return ((tonumber(r_val) or 0) << 16) | ((tonumber(g_val) or 0) << 8) | (tonumber(b_val) or 0)
    end

    -- Dynamic fallback for any ImGui_* enum/constant or unmocked function
    setmetatable(r, {
        __index = function(t, k)
            if type(k) == "string" then
                if k:find("^ImGui_Key_") or k:find("^ImGui_Mod_") or k:find("^ImGui_Col_") or
                   k:find("^ImGui_StyleVar_") or k:find("^ImGui_WindowFlags_") or
                   k:find("^ImGui_ChildFlags_") or k:find("^ImGui_PopupFlags_") or
                   k:find("^ImGui_TableFlags_") or k:find("^ImGui_TableColumnFlags_") or
                   k:find("^ImGui_InputTextFlags_") or k:find("^ImGui_ColorEditFlags_") or
                   k:find("^ImGui_Cond_") or k:find("^ImGui_MouseCursor_") or
                   k:find("^ImGui_MouseButton_") or k:find("^ImGui_HoveredFlags_") or
                   k:find("^ImGui_FocusedFlags_") or k:find("^ImGui_DrawFlags_") or
                   k:find("^ImGui_ComboFlags_") or k:find("^ImGui_SelectableFlags_") or
                   k:find("^ImGui_SliderFlags_") or k:find("^ImGui_TreeNodeFlags_") or
                   k:find("^ImGui_TabBarFlags_") or k:find("^ImGui_TabItemFlags_") or
                   k:find("^ImGui_ButtonFlags_") then
                    -- Deterministic integer constant per enum name
                    local hash = 0
                    for i = 1, #k do hash = (hash * 31 + k:byte(i)) % 65536 end
                    local fn = function() return hash + 1 end
                    rawset(t, k, fn)
                    return fn
                end
            end
            local fallback = function() return 0 end
            rawset(t, k, fallback)
            return fallback
        end
    })

    return r
end

return Mock

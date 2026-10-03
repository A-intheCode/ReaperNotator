-- ==============================================================================
-- REAPER Native Notator - Service: KeySignatureService
-- Manages key signatures and time signatures
-- per MIDI item, track, and project including REAPER type 15 MIDI events & P_EXT.
-- ==============================================================================

local Constants = require("constants")

local KeySignatureService = {}

-- Internal helper: Resolves real MediaItem and Take from wrapper or pointers
local function resolve_item_and_take(item, take)
    local real_item = nil
    local real_take = nil

    if type(item) == "table" then
        real_item = item.item
        real_take = item.take
    elseif item and reaper.ValidatePtr(item, "MediaItem*") then
        real_item = item
    end

    if type(take) == "table" then
        real_take = take.take or real_take
    elseif take and reaper.ValidatePtr(take, "MediaItem_Take*") then
        real_take = take
    end

    if not real_take and real_item and reaper.ValidatePtr(real_item, "MediaItem*") then
        real_take = reaper.GetActiveTake(real_item)
    end
    if not real_item and real_take and reaper.ValidatePtr(real_take, "MediaItem_Take*") then
        real_item = reaper.GetMediaItemTake_Item(real_take)
    end

    return real_item, real_take
end

local function make_timesig_table(num, denom)
    local t = { num = num, denom = denom }
    setmetatable(t, {
        __tostring = function(self) return tostring(self.num) end
    })
    return t
end

-- ==============================================================================
-- ITEM KEY SIGNATURE (GET / SET)
-- ==============================================================================

--- Reads the key signature of a MIDI item from P_EXT or type 15 take events.
-- If qn is provided and take is valid, resolves the active key signature at or before position qn.
-- @param item MediaItem* or MidiItem wrapper
-- @param take MediaItem_Take* (optional)
-- @param qn number (optional quarter-note position)
-- @return table { idx = number, key_idx = number, mode = string } or nil
function KeySignatureService.get_item_key_sig(item, take, qn)
    local real_item, real_take = resolve_item_and_take(item, take)

    -- If qn is provided and real_take is valid MIDI take, look for the active Type 15 notation event at or before qn
    if qn and real_take and reaper.ValidatePtr(real_take, "MediaItem_Take*") and reaper.TakeIsMIDI(real_take) then
        local target_ppq = reaper.MIDI_GetPPQPosFromProjQN(real_take, qn)
        local _, _, _, text_cnt = reaper.MIDI_CountEvts(real_take)
        local best_evt = nil
        local best_ppq = -1
        local first_evt = nil
        local first_ppq = math.huge

        for ti = 0, text_cnt - 1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(real_take, ti)
            if ok and etype == 15 then
                local idx_s, mode_s = msg:match("^NOTATOR_KEY_SIG%s+(%-?%d+)%s*([%a%d_]*)")
                local kidx, kmode = nil, nil
                if idx_s then
                    kidx = tonumber(idx_s)
                    kmode = (mode_s and mode_s ~= "") and mode_s or "major"
                else
                    local nat_idx = msg:match("^key%s+(%-?%d+)")
                    if nat_idx then
                        kidx = tonumber(nat_idx)
                        kmode = "major"
                    end
                end

                if kidx ~= nil then
                    if ppq < first_ppq then
                        first_ppq = ppq
                        first_evt = { idx = kidx, key_idx = kidx, mode = kmode }
                    end
                    if ppq <= target_ppq + 5 and ppq >= best_ppq then
                        best_ppq = ppq
                        best_evt = { idx = kidx, key_idx = kidx, mode = kmode }
                    end
                end
            end
        end

        if best_evt then
            return best_evt, best_evt.mode
        elseif first_evt then
            return first_evt, first_evt.mode
        end
    end

    -- 1st attempt: MediaItem P_EXT:notator_key_sig ("<key_idx>|<mode>")
    if real_item and reaper.ValidatePtr(real_item, "MediaItem*") then
        local ok, ext_val = reaper.GetSetMediaItemInfo_String(real_item, "P_EXT:notator_key_sig", "", false)
        if ok and ext_val and ext_val ~= "" then
            local idx_s, mode_s = ext_val:match("^(%-?%d+)|?([%a%d_]*)")
            if idx_s then
                local kidx = tonumber(idx_s)
                local kmode = (mode_s and mode_s ~= "") and mode_s or "major"
                return { idx = kidx, key_idx = kidx, mode = kmode }, kmode
            end
        end
    end

    -- 2nd attempt: Type 15 notation events in take ("NOTATOR_KEY_SIG <key_idx> <mode>" or "key <val>")
    if real_take and reaper.ValidatePtr(real_take, "MediaItem_Take*") and reaper.TakeIsMIDI(real_take) then
        local _, _, _, text_cnt = reaper.MIDI_CountEvts(real_take)
        for ti = 0, text_cnt - 1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(real_take, ti)
            if ok and etype == 15 then
                local idx_s, mode_s = msg:match("^NOTATOR_KEY_SIG%s+(%-?%d+)%s*([%a%d_]*)")
                if idx_s then
                    local kidx = tonumber(idx_s)
                    local kmode = (mode_s and mode_s ~= "") and mode_s or "major"
                    return { idx = kidx, key_idx = kidx, mode = kmode }, kmode
                end
                local nat_idx = msg:match("^key%s+(%-?%d+)")
                if nat_idx then
                    local kidx = tonumber(nat_idx)
                    return { idx = kidx, key_idx = kidx, mode = "major" }, "major"
                end
            end
        end
    end

    return nil
end

--- Writes a key signature to a MIDI item and its take.
-- Writes at PPQ 0 (or at_qn if specified) in take: type 15 "NOTATOR_KEY_SIG <key_idx> <mode>" and "key <val>".
-- Writes on MediaItem: P_EXT:notator_key_sig as "<key_idx>|<mode>" (for initial key sig).
-- If auto_respell == true: calls KeySignatureService.respell_item_notes.
-- @param state Notator state object
-- @param item MediaItem* or MidiItem wrapper
-- @param take MediaItem_Take* (optional)
-- @param key_idx Key signature index from -7 to +7
-- @param mode "major" or "minor"
-- @param auto_respell boolean
-- @param at_qn number (optional quarter-note position for mid-item key changes)
function KeySignatureService.set_item_key_sig(state, item, take, key_idx, mode, auto_respell, at_qn)
    local real_item, real_take = resolve_item_and_take(item, take)
    local kidx = tonumber(key_idx) or 0
    kidx = math.max(-7, math.min(7, kidx))
    local kmode = (mode and mode ~= "") and mode or "major"
    local is_mid_item = (at_qn and at_qn > 0.001)

    -- 1. Update take type 15 notation events
    if real_take and reaper.ValidatePtr(real_take, "MediaItem_Take*") and reaper.TakeIsMIDI(real_take) then
        local target_ppq = is_mid_item and math.floor(reaper.MIDI_GetPPQPosFromProjQN(real_take, at_qn) + 0.5) or 0
        local _, _, _, text_cnt = reaper.MIDI_CountEvts(real_take)
        local to_del = {}
        for ti = 0, text_cnt - 1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(real_take, ti)
            if ok and etype == 15 then
                if msg:match("^NOTATOR_KEY_SIG") or msg:match("^key%s+%-?%d+") then
                    if is_mid_item then
                        if math.abs(ppq - target_ppq) < 15 then
                            table.insert(to_del, ti)
                        end
                    else
                        if ppq < 15 then
                            table.insert(to_del, ti)
                        end
                    end
                end
            end
        end
        if #to_del > 0 then
            table.sort(to_del, function(a, b) return a > b end)
            for _, ti in ipairs(to_del) do
                reaper.MIDI_DeleteTextSysexEvt(real_take, ti)
            end
        end

        local notator_msg = string.format("NOTATOR_KEY_SIG %d %s", kidx, kmode)
        reaper.MIDI_InsertTextSysexEvt(real_take, false, false, target_ppq, 15, notator_msg)
        local native_msg = string.format("key %d", kidx)
        reaper.MIDI_InsertTextSysexEvt(real_take, false, false, target_ppq, 15, native_msg)
        reaper.MIDI_Sort(real_take)
    end

    -- 2. Set MediaItem P_EXT:notator_key_sig
    if not is_mid_item and real_item and reaper.ValidatePtr(real_item, "MediaItem*") then
        local ext_str = string.format("%d|%s", kidx, kmode)
        reaper.GetSetMediaItemInfo_String(real_item, "P_EXT:notator_key_sig", ext_str, true)
    end

    -- 3. Update wrapper object
    if type(item) == "table" then
        item.key_sig = { idx = kidx, key_idx = kidx, mode = kmode }
    end
    -- Also update all cached wrappers in active_tracks_cache
    if state and state.active_tracks_cache then
        for _, tdata in ipairs(state.active_tracks_cache) do
            if tdata.items then
                for _, it in ipairs(tdata.items) do
                    if (real_item and it.item == real_item) or (real_take and it.take == real_take) then
                        it.key_sig = { idx = kidx, key_idx = kidx, mode = kmode }
                    end
                end
            end
        end
    end

    -- 4. Auto-respell notes
    if auto_respell == true and real_take then
        KeySignatureService.respell_item_notes(state, real_take, kidx, kmode)
    end

    -- 5. Invalidate cache & update project
    local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
    if MidiService and MidiService.invalidate_cache then
        MidiService.invalidate_cache()
    end
    if state then state.active_tracks_cache = nil end
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    if reaper.UpdateArrange then reaper.UpdateArrange() end
end

-- ==============================================================================
-- ITEM TIME SIGNATURE (GET / SET)
-- ==============================================================================

--- Reads the time signature of a MIDI item from P_EXT or type 15 take events.
-- If qn is provided and take is valid, resolves the active time signature at or before position qn.
-- @param item MediaItem* or MidiItem wrapper
-- @param take MediaItem_Take* (optional)
-- @param qn number (optional quarter-note position)
-- @return table { num = number, denom = number } or nil
function KeySignatureService.get_item_time_sig(item, take, qn)
    local real_item, real_take = resolve_item_and_take(item, take)

    -- If qn is provided and real_take is valid MIDI take, look for the active Type 15 notation event at or before qn
    if qn and real_take and reaper.ValidatePtr(real_take, "MediaItem_Take*") and reaper.TakeIsMIDI(real_take) then
        local target_ppq = reaper.MIDI_GetPPQPosFromProjQN(real_take, qn)
        local _, _, _, text_cnt = reaper.MIDI_CountEvts(real_take)
        local best_evt = nil
        local best_ppq = -1
        local first_evt = nil
        local first_ppq = math.huge

        for ti = 0, text_cnt - 1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(real_take, ti)
            if ok and etype == 15 then
                local num_s, den_s = msg:match("^NOTATOR_TIME_SIG%s+(%d+)%s+(%d+)")
                if not num_s then
                    num_s, den_s = msg:match("^time%s+(%d+)/(%d+)")
                end
                if num_s and den_s then
                    local n_num = tonumber(num_s)
                    local n_den = tonumber(den_s)
                    local t_entry = make_timesig_table(n_num, n_den)
                    if ppq < first_ppq then
                        first_ppq = ppq
                        first_evt = t_entry
                    end
                    if ppq <= target_ppq + 5 and ppq >= best_ppq then
                        best_ppq = ppq
                        best_evt = t_entry
                    end
                end
            end
        end

        if best_evt then
            return best_evt, best_evt.num, best_evt.denom
        elseif first_evt then
            return first_evt, first_evt.num, first_evt.denom
        end
    end

    -- 1st attempt: MediaItem P_EXT:notator_time_sig ("<num>|<denom>")
    if real_item and reaper.ValidatePtr(real_item, "MediaItem*") then
        local ok, ext_val = reaper.GetSetMediaItemInfo_String(real_item, "P_EXT:notator_time_sig", "", false)
        if ok and ext_val and ext_val ~= "" then
            local num_s, den_s = ext_val:match("^(%d+)|(%d+)")
            if num_s and den_s then
                local n_num = tonumber(num_s)
                local n_den = tonumber(den_s)
                return { num = n_num, denom = n_den }, n_num, n_den
            end
        end
    end

    -- 2nd attempt: Type 15 take events ("NOTATOR_TIME_SIG <num> <denom>" or "time <num>/<denom>")
    if real_take and reaper.ValidatePtr(real_take, "MediaItem_Take*") and reaper.TakeIsMIDI(real_take) then
        local _, _, _, text_cnt = reaper.MIDI_CountEvts(real_take)
        for ti = 0, text_cnt - 1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(real_take, ti)
            if ok and etype == 15 then
                local num_s, den_s = msg:match("^NOTATOR_TIME_SIG%s+(%d+)%s+(%d+)")
                if num_s and den_s then
                    local n_num = tonumber(num_s)
                    local n_den = tonumber(den_s)
                    return make_timesig_table(n_num, n_den), n_num, n_den
                end
                local nat_n, nat_d = msg:match("^time%s+(%d+)/(%d+)")
                if nat_n and nat_d then
                    local n_num = tonumber(nat_n)
                    local n_den = tonumber(nat_d)
                    return make_timesig_table(n_num, n_den), n_num, n_den
                end
            end
        end
    end

    return nil
end

--- Writes a time signature to a MIDI item and its take.
-- Writes at PPQ 0 (or at_qn) in take: type 15 "NOTATOR_TIME_SIG <num> <denom>" and "time <num>/<denom>".
-- Writes on MediaItem: P_EXT:notator_time_sig as "<num>|<denom>" (for initial time sig).
-- @param state Notator state object
-- @param item MediaItem* or MidiItem wrapper
-- @param take MediaItem_Take* (optional)
-- @param num Numerator (e.g. 4)
-- @param denom Denominator (e.g. 4)
-- @param at_qn number (optional quarter-note position)
function KeySignatureService.set_item_time_sig(state, item, take, num, denom, at_qn)
    local real_item, real_take = resolve_item_and_take(item, take)
    local t_num = tonumber(num) or 4
    local t_den = tonumber(denom) or 4
    local is_mid_item = (at_qn and at_qn > 0.001)

    -- 1. Update take type 15 notation events
    if real_take and reaper.ValidatePtr(real_take, "MediaItem_Take*") and reaper.TakeIsMIDI(real_take) then
        local target_ppq = is_mid_item and math.floor(reaper.MIDI_GetPPQPosFromProjQN(real_take, at_qn) + 0.5) or 0
        local _, _, _, text_cnt = reaper.MIDI_CountEvts(real_take)
        local to_del = {}
        for ti = 0, text_cnt - 1 do
            local ok, _, _, ppq, etype, msg = reaper.MIDI_GetTextSysexEvt(real_take, ti)
            if ok and etype == 15 then
                if msg:match("^NOTATOR_TIME_SIG") or msg:match("^time%s+%d+/%d+") then
                    if is_mid_item then
                        if math.abs(ppq - target_ppq) < 15 then
                            table.insert(to_del, ti)
                        end
                    else
                        if ppq < 15 then
                            table.insert(to_del, ti)
                        end
                    end
                end
            end
        end
        if #to_del > 0 then
            table.sort(to_del, function(a, b) return a > b end)
            for _, ti in ipairs(to_del) do
                reaper.MIDI_DeleteTextSysexEvt(real_take, ti)
            end
        end

        local notator_msg = string.format("NOTATOR_TIME_SIG %d %d", t_num, t_den)
        reaper.MIDI_InsertTextSysexEvt(real_take, false, false, target_ppq, 15, notator_msg)
        local native_msg = string.format("time %d/%d", t_num, t_den)
        reaper.MIDI_InsertTextSysexEvt(real_take, false, false, target_ppq, 15, native_msg)
        reaper.MIDI_Sort(real_take)
    end

    -- 2. Set MediaItem P_EXT:notator_time_sig
    if not is_mid_item and real_item and reaper.ValidatePtr(real_item, "MediaItem*") then
        local ext_str = string.format("%d|%d", t_num, t_den)
        reaper.GetSetMediaItemInfo_String(real_item, "P_EXT:notator_time_sig", ext_str, true)
    end

    -- 3. Update wrapper object
    if type(item) == "table" then
        item.time_sig = { num = t_num, denom = t_den }
    end

    -- 4. Invalidate cache & update project
    local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
    if MidiService and MidiService.invalidate_cache then
        MidiService.invalidate_cache()
    end
    if state then state.active_tracks_cache = nil end
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    if reaper.UpdateArrange then reaper.UpdateArrange() end
end

-- ==============================================================================
-- HIERARCHICAL RESOLUTION (RESOLVE EFFECTIVE KEY & TIME SIG)
-- ==============================================================================

--- Resolves the effective key signature for a given position.
-- Priority: Item key > Track key (state.track_key_signatures[guid]) > Project key (state.key_signature).
-- @param state Notator state object
-- @param track MediaTrack*, track GUID string, or TrackData table
-- @param item MediaItem* or MidiItem wrapper
-- @param qn Time position in quarter notes (optional)
-- @return table { idx = number, key_idx = number, mode = string }
function KeySignatureService.resolve_effective_key(state, track, item, qn)
    -- 1st Priority: Item key
    if item then
        if type(item) == "table" then
            if not qn or not item.key_sig_events or #item.key_sig_events == 0 then
                local isig = item.key_sig
                if isig and isig.key_idx ~= nil then
                    return { idx = isig.key_idx, key_idx = isig.key_idx, mode = isig.mode or "major" }
                elseif isig and isig.idx ~= nil then
                    return { idx = isig.idx, key_idx = isig.idx, mode = isig.mode or "major" }
                end
            else
                -- Resolve from item.key_sig_events in memory without C-API calls
                local target_ppq = 0
                if item.take and reaper.ValidatePtr(item.take, "MediaItem_Take*") and reaper.TakeIsMIDI(item.take) then
                    target_ppq = reaper.MIDI_GetPPQPosFromProjQN(item.take, qn)
                end
                local best_evt = nil
                for _, evt in ipairs(item.key_sig_events) do
                    if evt.ppq <= target_ppq + 5 then
                        best_evt = evt
                    end
                end
                if best_evt then
                    return { idx = best_evt.key_idx, key_idx = best_evt.key_idx, mode = best_evt.mode or "major" }
                elseif item.key_sig then
                    local kidx = item.key_sig.key_idx or item.key_sig.idx or 0
                    return { idx = kidx, key_idx = kidx, mode = item.key_sig.mode or "major" }
                end
            end
        end
        local isig = KeySignatureService.get_item_key_sig(item, nil, qn)
        if isig and isig.key_idx ~= nil then
            return { idx = isig.key_idx, key_idx = isig.key_idx, mode = isig.mode or "major" }
        elseif isig and isig.idx ~= nil then
            return { idx = isig.idx, key_idx = isig.idx, mode = isig.mode or "major" }
        end
    elseif track and qn then
        -- Find item at position qn on this track
        local is_table_track = (type(track) == "table" and track.items)
        local found_item = nil
        if is_table_track then
            for _, it in ipairs(track.items) do
                local s_qn = it.start_qn or 0
                local e_qn = it.end_qn or s_qn
                if qn >= (s_qn - 0.005) and qn < (e_qn - 0.005) then
                    found_item = it
                    break
                end
            end
            if found_item then
                return KeySignatureService.resolve_effective_key(state, nil, found_item, qn)
            else
                -- Not inside any item on this track: check track key or fall back directly to project key (ZERO C-API calls)
                local guid = track.guid or (track.track and reaper.ValidatePtr(track.track, "MediaTrack*") and reaper.GetTrackGUID(track.track))
                if guid and state and state.track_key_signatures and state.track_key_signatures[guid] then
                    local tsig = state.track_key_signatures[guid]
                    if type(tsig) == "table" then
                        local kidx = tsig.idx or tsig.key_idx or 0
                        return { idx = kidx, key_idx = kidx, mode = tsig.mode or "major" }
                    end
                end
                local p_idx = (state and state.key_signature) or 0
                local p_mode = (state and state.key_signature_mode) or "major"
                return { idx = p_idx, key_idx = p_idx, mode = p_mode }
            end
        end
        if not found_item then
            local real_trk = (type(track) == "userdata" and reaper.ValidatePtr(track, "MediaTrack*") and track)
                or (type(track) == "table" and track.track and reaper.ValidatePtr(track.track, "MediaTrack*") and track.track)
            if real_trk then
                local t_pos = (reaper.TimeMap2_QNToTime and reaper.TimeMap2_QNToTime(0, qn)) or 0
                local item_cnt = reaper.CountTrackMediaItems(real_trk)
                for ii = 0, item_cnt - 1 do
                    local it = reaper.GetTrackMediaItem(real_trk, ii)
                    if it then
                        local pos = reaper.GetMediaItemInfo_Value(it, "D_POSITION")
                        local len = reaper.GetMediaItemInfo_Value(it, "D_LENGTH")
                        if t_pos >= (pos - 0.005) and t_pos < (pos + len - 0.005) then
                            found_item = it
                            break
                        end
                    end
                end
            end
        end
        if found_item then
            local isig = (type(found_item) == "table" and not qn and found_item.key_sig) or KeySignatureService.get_item_key_sig(found_item, nil, qn)
            if not isig and type(found_item) == "table" and found_item.key_sig then isig = found_item.key_sig end
            if isig and isig.key_idx ~= nil then
                if type(found_item) == "table" and not qn then found_item.key_sig = isig end
                return { idx = isig.key_idx, key_idx = isig.key_idx, mode = isig.mode or "major" }
            elseif isig and isig.idx ~= nil then
                if type(found_item) == "table" and not qn then found_item.key_sig = isig end
                return { idx = isig.idx, key_idx = isig.idx, mode = isig.mode or "major" }
            end
        end
    end

    -- 2nd Priority: Track key
    if track and state and state.track_key_signatures then
        local guid = (type(track) == "string" and track)
            or (type(track) == "table" and (track.guid or (track.track and reaper.ValidatePtr(track.track, "MediaTrack*") and reaper.GetTrackGUID(track.track))))
            or (reaper.ValidatePtr(track, "MediaTrack*") and reaper.GetTrackGUID(track))
        if guid and state.track_key_signatures[guid] then
            local tsig = state.track_key_signatures[guid]
            if type(tsig) == "table" then
                local kidx = tsig.idx or tsig.key_idx or 0
                return { idx = kidx, key_idx = kidx, mode = tsig.mode or "major" }
            elseif type(tsig) == "number" then
                return { idx = tsig, key_idx = tsig, mode = "major" }
            elseif type(tsig) == "string" then
                local kidx, kmode = tsig:match("^(%-?%d+):?(.*)$")
                if kidx then
                    return { idx = tonumber(kidx), key_idx = tonumber(kidx), mode = (kmode and kmode ~= "") and kmode or "major" }
                end
            end
        end
    end

    -- 3rd Priority: Project key
    local p_idx = (state and state.key_signature) or 0
    local p_mode = (state and state.key_signature_mode) or "major"
    return { idx = p_idx, key_idx = p_idx, mode = p_mode }
end

--- Resolves the effective time signature for a given position.
-- Priority: Item time sig > Project time sig (reaper.TimeMap_GetTimeSigAtTime).
-- @param state Notator state object
-- @param track MediaTrack* or track GUID string
-- @param item MediaItem* or MidiItem wrapper
-- @param qn Time position in quarter notes (optional)
-- @return table { num = number, denom = number }
function KeySignatureService.resolve_effective_time_sig(state, track, item, qn)
    -- 1st Priority: Item time sig
    if item then
        local tsig = (type(item) == "table" and not qn and item.time_sig) or KeySignatureService.get_item_time_sig(item, nil, qn)
        if not tsig and type(item) == "table" and item.time_sig then tsig = item.time_sig end
        if tsig and tsig.num and tsig.denom then
            return make_timesig_table(tsig.num, tsig.denom), tsig.num, tsig.denom
        end
    end

    -- 2nd Priority: Project time sig
    local q = qn or 0
    local t_pos = (reaper.TimeMap2_QNToTime and reaper.TimeMap2_QNToTime(0, q)) or 0
    local num, denom = reaper.TimeMap_GetTimeSigAtTime(0, t_pos)
    num = (num and num > 0) and num or 4
    denom = (denom and denom > 0) and denom or 4
    return make_timesig_table(num, denom), num, denom
end

--- Determines all measures where key signature changes (item or track change).
-- Uses both measure-center sampling and direct item position analysis for maximum reliability.
-- @param state Notator state object
-- @param active_tracks List of tracks (TrackData or MediaTrack*)
-- @param total_measures Total measures
-- @param bpi Beats per measure (QN per measure)
-- @param s Scale factor
-- @return table Map of measure_index -> { has_change = bool, max_kw = number, tracks = table }
function KeySignatureService.get_measure_key_signature_changes(state, active_tracks, total_measures, bpi, s)
    local changes = {}
    if not active_tracks or #active_tracks == 0 or not total_measures then
        return changes
    end

    local scale = s or 1.0
    local qn_per_m = (bpi and bpi > 0) and bpi or 4.0
    local proj_k = (state and state.key_signature) or 0
    local proj_mode = (state and state.key_signature_mode) or "major"
    local proj_change = (reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0)) or 0

    -- Cache check on state
    if state and state._cached_k_changes and
       state._cached_k_changes_cnt == proj_change and
       state._cached_k_changes_num_trk == #active_tracks and
       state._cached_k_changes_tot_m == total_measures and
       state._cached_k_changes_bpi == bpi and
       math.abs((state._cached_k_changes_s or 1.0) - scale) < 0.001 and
       state._cached_k_changes_key == proj_k and
       state._cached_k_changes_mode == proj_mode then
        return state._cached_k_changes
    end

    -- Fast pass: find candidate measures where key signature could change
    local candidate_measures = {}
    local has_any_custom_key = false

    for t_idx, trk_entry in ipairs(active_tracks) do
        local items = (type(trk_entry) == "table" and trk_entry.items) or {}
        local guid = (type(trk_entry) == "table" and trk_entry.guid) or (trk_entry and reaper.ValidatePtr(trk_entry, "MediaTrack*") and reaper.GetTrackGUID(trk_entry))
        if guid and state and state.track_key_signatures and state.track_key_signatures[guid] then
            has_any_custom_key = true
        end

        for _, it in ipairs(items) do
            local s_qn = it.start_qn or 0
            local e_qn = it.end_qn or s_qn
            local it_k = (it.key_sig and (it.key_sig.idx or it.key_sig.key_idx)) or proj_k
            if it_k ~= proj_k or (it.key_sig_events and #it.key_sig_events > 0) then
                has_any_custom_key = true
            end
            local m_start = math.floor((s_qn / qn_per_m) + 0.05)
            local m_end   = math.floor((e_qn / qn_per_m) + 0.05)
            if m_start >= 1 and m_start <= total_measures then
                candidate_measures[m_start] = true
            end
            if m_end >= 1 and m_end <= total_measures then
                candidate_measures[m_end] = true
            end
            if it.key_sig_events then
                for _, evt in ipairs(it.key_sig_events) do
                    local eq_qn = s_qn
                    if it.take and reaper.ValidatePtr(it.take, "MediaItem_Take*") then
                        eq_qn = reaper.MIDI_GetProjQNFromPPQPos(it.take, evt.ppq)
                    end
                    local m_evt = math.floor((eq_qn / qn_per_m) + 0.05)
                    if m_evt >= 1 and m_evt <= total_measures then
                        candidate_measures[m_evt] = true
                    end
                end
            end
        end
    end

    if not has_any_custom_key then
        if state then
            state._cached_k_changes = changes
            state._cached_k_changes_cnt = proj_change
            state._cached_k_changes_num_trk = #active_tracks
            state._cached_k_changes_tot_m = total_measures
            state._cached_k_changes_bpi = bpi
            state._cached_k_changes_s = scale
            state._cached_k_changes_key = proj_k
            state._cached_k_changes_mode = proj_mode
        end
        return changes
    end

    -- Evaluate ONLY candidate measures where key boundaries exist
    for m in pairs(candidate_measures) do
        local qn_curr = (m + 0.5) * qn_per_m
        local qn_prev = (m - 0.5) * qn_per_m
        local change_info = nil
        local max_kw = 0

        for t_idx, trk_entry in ipairs(active_tracks) do
            local trk = (type(trk_entry) == "table" and trk_entry.track) or trk_entry
            local guid = (type(trk_entry) == "table" and trk_entry.guid) or (trk and reaper.ValidatePtr(trk, "MediaTrack*") and reaper.GetTrackGUID(trk))
            local k_curr = KeySignatureService.resolve_effective_key(state, trk_entry, nil, qn_curr)
            local k_prev = KeySignatureService.resolve_effective_key(state, trk_entry, nil, qn_prev)
            local c_idx = k_curr and (k_curr.idx or k_curr.key_idx) or 0
            local p_idx = k_prev and (k_prev.idx or k_prev.key_idx) or 0

            if c_idx ~= p_idx then
                if not change_info then
                    change_info = {
                        measure = m,
                        qn = m * qn_per_m,
                        tracks = {},
                        has_change = true
                    }
                end
                local t_info = {
                    curr_idx = c_idx,
                    prev_idx = p_idx,
                    mode = k_curr and k_curr.mode or "major"
                }
                change_info.tracks[trk_entry] = t_info
                change_info.tracks[t_idx] = t_info
                if trk and trk ~= trk_entry then
                    change_info.tracks[trk] = t_info
                end
                if guid then
                    change_info.tracks[guid] = t_info
                end

                local kw = math.abs(c_idx) * (9.5 * scale)
                if c_idx == 0 and p_idx ~= 0 then
                    kw = math.abs(p_idx) * (9.5 * scale)
                end
                if kw > max_kw then max_kw = kw end
            end
        end

        if change_info then
            change_info.max_kw = max_kw
            changes[m] = change_info
        end
    end

    if state then
        state._cached_k_changes = changes
        state._cached_k_changes_cnt = proj_change
        state._cached_k_changes_num_trk = #active_tracks
        state._cached_k_changes_tot_m = total_measures
        state._cached_k_changes_bpi = bpi
        state._cached_k_changes_s = scale
        state._cached_k_changes_key = proj_k
        state._cached_k_changes_mode = proj_mode
    end

    return changes
end

-- ==============================================================================
-- ENHARMONIC RESPELLING & SCALE SNAPPING
-- ==============================================================================

--- Adjusts state.note_accidentals for notes in this take so they match the scale.
-- (e.g. Eb instead of D# in flat keys, F# instead of Gb in sharp keys).
-- @param state Notator state object
-- @param take MediaItem_Take*
-- @param key_idx Key signature index (-7 to +7)
-- @param mode "major" or "minor"
function KeySignatureService.respell_item_notes(state, take, key_idx, mode)
    if not (state and state.note_accidentals and take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take)) then
        return 0
    end

    local kidx = tonumber(key_idx) or 0
    local _, notecnt = reaper.MIDI_CountEvts(take)
    local real_item = reaper.GetMediaItemTake_Item(take)
    local respelled_cnt = 0

    for ni = 0, notecnt - 1 do
        local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
        if ok then
            local p_mod = pitch % 12
            local pref = nil

            if kidx > 0 then
                -- Sharp keys: Prefer sharps (# = 1)
                if p_mod == 1 or p_mod == 3 or p_mod == 6 or p_mod == 8 or p_mod == 10 then
                    pref = 1 -- C#, D#, F#, G#, A#
                elseif kidx >= 6 and p_mod == 5 then
                    pref = 1 -- E#
                elseif kidx >= 7 and p_mod == 0 then
                    pref = 1 -- B#
                end
            elseif kidx < 0 then
                -- Flat keys: Prefer flats (b = -1)
                if p_mod == 1 or p_mod == 3 or p_mod == 6 or p_mod == 8 or p_mod == 10 then
                    pref = -1 -- Db, Eb, Gb, Ab, Bb
                elseif kidx <= -6 and p_mod == 11 then
                    pref = -1 -- Cb
                elseif kidx <= -7 and p_mod == 4 then
                    pref = -1 -- Fb
                end
            else
                -- C major / A minor standard enharmonics
                if p_mod == 1 then pref = 1      -- C#
                elseif p_mod == 3 then pref = -1  -- Eb
                elseif p_mod == 6 then pref = 1   -- F#
                elseif p_mod == 8 then pref = 1   -- G#
                elseif p_mod == 10 then pref = -1 -- Bb
                end
            end

            if pref ~= nil then
                local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                local id_k = string.format("%s_%s_%.3f", tostring(take), tostring(ni), sqn)
                local pos_k = string.format("%s_%.3f_%d", tostring(take), sqn, pitch)
                state.note_accidentals[id_k] = pref
                state.note_accidentals[pos_k] = pref
                if real_item then
                    local full_k = string.format("%s_%s_%.3f_%d_%d", tostring(real_item), tostring(take), sqn, pitch, chan or 0)
                    state.note_accidentals[full_k] = pref
                end
                respelled_cnt = respelled_cnt + 1
            end
        end
    end

    return respelled_cnt
end

--- Transposes non-scale notes to the nearest scale degree of the target key via MIDI_SetNote.
-- @param state Notator state object
-- @param take MediaItem_Take*
-- @param key_idx Key signature index (-7 to +7)
-- @param mode "major" or "minor"
-- @return number Count of adjusted notes
function KeySignatureService.snap_item_notes_to_key(state, take, key_idx, mode)
    if not (take and reaper.ValidatePtr(take, "MediaItem_Take*") and reaper.TakeIsMIDI(take)) then
        return 0
    end

    local kidx = tonumber(key_idx) or 0
    local kmode = (mode and mode ~= "") and mode or "major"

    -- Root calculation via circle of fifths:
    local major_root = ((kidx * 7) % 12 + 12) % 12
    local root = (kmode == "minor") and (((major_root + 9) % 12 + 12) % 12) or major_root
    local intervals = (kmode == "minor") and { 0, 2, 3, 5, 7, 8, 10 } or { 0, 2, 4, 5, 7, 9, 11 }

    local in_scale = {}
    for _, iv in ipairs(intervals) do
        in_scale[(root + iv) % 12] = true
    end

    local _, notecnt = reaper.MIDI_CountEvts(take)
    local any_changed = false
    local changed_cnt = 0

    for ni = 0, notecnt - 1 do
        local ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, ni)
        if ok then
            local pc = pitch % 12
            if not in_scale[pc] then
                local down_pc = (pitch - 1) % 12
                local up_pc   = (pitch + 1) % 12
                local new_pitch = pitch
                if in_scale[up_pc] and not in_scale[down_pc] then
                    new_pitch = pitch + 1
                elseif in_scale[down_pc] and not in_scale[up_pc] then
                    new_pitch = pitch - 1
                elseif in_scale[up_pc] and in_scale[down_pc] then
                    new_pitch = (kidx >= 0) and (pitch + 1) or (pitch - 1)
                end

                if new_pitch ~= pitch and new_pitch >= 0 and new_pitch <= 127 then
                    reaper.MIDI_SetNote(take, ni, nil, nil, nil, nil, nil, new_pitch, nil, true)
                    any_changed = true
                    changed_cnt = changed_cnt + 1
                end
            end
        end
    end

    if any_changed then
        reaper.MIDI_Sort(take)
        KeySignatureService.respell_item_notes(state, take, kidx, kmode)
        local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
        if MidiService and MidiService.invalidate_cache then MidiService.invalidate_cache() end
        if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
        if reaper.UpdateArrange then reaper.UpdateArrange() end
    end

    return changed_cnt
end

-- ==============================================================================
-- PROJECT PERSISTENCE (SAVE & LOAD)
-- ==============================================================================

--- Saves key signature settings to the current REAPER project via ProjExtState.
-- @param state Notator state object
function KeySignatureService.save(state)
    if not state then return end
    local str = string.format("%d|%s", state.key_signature or 0, state.key_signature_mode or "major")
    reaper.SetProjExtState(0, "REAPER_Notator", "KEY_SIGNATURE", str)

    if state.track_key_signatures then
        local parts = {}
        for guid, ksig in pairs(state.track_key_signatures) do
            if type(ksig) == "table" then
                table.insert(parts, string.format("%s:%d:%s", guid, ksig.idx or ksig.key_idx or 0, ksig.mode or "major"))
            elseif type(ksig) == "string" and ksig:find(":") then
                table.insert(parts, guid .. ":" .. ksig)
            else
                table.insert(parts, string.format("%s:%d:major", guid, tonumber(ksig) or 0))
            end
        end
        reaper.SetProjExtState(0, "REAPER_Notator", "track_key_signatures", table.concat(parts, ";"))
    end

    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
end

--- Loads key signature settings from the current REAPER project via ProjExtState.
-- @param state Notator state object
function KeySignatureService.load(state)
    if not state then return end
    -- The user explicitly requested:
    -- Default key signature must ALWAYS be C Major on startup.
    state.key_signature = 0
    state.key_signature_mode = "major"

    local ok_t, raw_t = reaper.GetProjExtState(0, "REAPER_Notator", "track_key_signatures")
    if ok_t == 1 and raw_t and raw_t ~= "" then
        state.track_key_signatures = state.track_key_signatures or {}
        for entry in raw_t:gmatch("([^;]+)") do
            local guid, k_idx, k_mode = entry:match("^([^:]+):(%-?%d+):?(.*)$")
            if guid and k_idx then
                local mode = (k_mode and k_mode ~= "") and k_mode or "major"
                state.track_key_signatures[guid] = { idx = tonumber(k_idx), key_idx = tonumber(k_idx), mode = mode }
            end
        end
    end
end

return KeySignatureService

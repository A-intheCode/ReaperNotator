-- ==============================================================================
-- REAPER Native Notator - Service: TextItemService
-- Manages free-floating text annotations with X/Y drag-and-drop,
-- inline double-click editing, and project persistence.
-- ==============================================================================

local TextItem = require("classes.text_item")

local TextItemService = {}

local function to_hex(str)
    if not str then return "" end
    str = tostring(str)
    return (str:gsub(".", function(c)
        return string.format("%02X", string.byte(c))
    end))
end

local function from_hex(hex)
    if not hex or hex == "" then return "" end
    hex = tostring(hex)
    return (hex:gsub("(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function sync_text_items_to_takes(state)
    local by_guid = {}
    for _, ti in ipairs(state.text_items or {}) do
        if ti.track_guid then
            by_guid[ti.track_guid] = by_guid[ti.track_guid] or {}
            table.insert(by_guid[ti.track_guid], ti)
        end
    end
    
    local trk_count = reaper.CountTracks(0)
    for ti = 0, trk_count - 1 do
        local trk = reaper.GetTrack(0, ti)
        if trk then
            local trk_guid = reaper.GetTrackGUID(trk)
            local item_count = reaper.CountTrackMediaItems(trk)
            local track_ti_list = by_guid[trk_guid] or {}
            
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
                        if ok and ev_type == 15 and msg:match("^NOTATOR_TEXT") then
                            table.insert(to_del, t_idx)
                        end
                    end
                    for _, d_idx in ipairs(to_del) do
                        reaper.MIDI_DeleteTextSysexEvt(take, d_idx)
                    end
                    
                    local inserted = false
                    for _, txt_item in ipairs(track_ti_list) do
                        if txt_item.qn >= (i_start_qn - 0.05) and txt_item.qn < (i_end_qn + 0.05) then
                            local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, txt_item.qn) + 0.5)
                            local msg = string.format("NOTATOR_TEXT|%s|%.2f|%s|%.1f|%s|%s",
                                tostring(txt_item.id or ""),
                                tonumber(txt_item.offset_y) or 32.0,
                                tostring(txt_item.style or "italic"),
                                tonumber(txt_item.font_size) or 16.0,
                                to_hex(tostring(txt_item.text or "")),
                                tostring(txt_item.placement or "below")
                            )
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

function TextItemService.load_text_items(state)
    state.text_items = {}
    local known = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "text_items")
    if raw and raw ~= "" then
        for entry in raw:gmatch("([^;]+)") do
            local parts = {}
            for p in (entry .. "|"):gmatch("([^|]*)|") do
                table.insert(parts, p)
            end
            local id         = parts[1]
            local track_guid = parts[2]
            local qn         = tonumber(parts[3]) or 0.0
            local offset_y   = tonumber(parts[4]) or 32.0
            local style      = (parts[5] and parts[5] ~= "") and parts[5] or "italic"
            local font_size  = tonumber(parts[6]) or 16.0
            if font_size < 12.0 then
                font_size = math.max(14.0, math.floor(font_size * 1.45 + 0.5))
            end
            local text       = from_hex(parts[7] or "")
            local placement  = (parts[8] and parts[8] ~= "") and parts[8] or "below"

            if id and id ~= "" and track_guid and track_guid ~= "" and text ~= "" then
                known[id] = true
                local ti = TextItem.new({
                    id         = id,
                    track_guid = track_guid,
                    qn         = qn,
                    offset_y   = offset_y,
                    style      = style,
                    font_size  = font_size,
                    text       = text,
                    placement  = placement
                })
                table.insert(state.text_items, ti)
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
                        if ok and ev_type == 15 and msg:match("^NOTATOR_TEXT") then
                            local parts = {}
                            for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
                            local id = parts[2]
                            local offset_y = tonumber(parts[3]) or 32.0
                            local style = (parts[4] and parts[4] ~= "") and parts[4] or "italic"
                            local font_size = tonumber(parts[5]) or 16.0
                            local text = from_hex(parts[6] or "")
                            local qn = reaper.MIDI_GetProjQNFromPPQPos(take, ppq)
                            if id and id ~= "" and text ~= "" and not known[id] then
                                known[id] = true
                                table.insert(state.text_items, TextItem.new({
                                    id = id,
                                    track_guid = trk_guid,
                                    qn = qn,
                                    offset_y = offset_y,
                                    style = style,
                                    font_size = font_size,
                                    text = text
                                }))
                            end
                        end
                    end
                end
            end
        end
    end
end

function TextItemService.parse_notation_event(state, track, take, ppq, msg)
    if not state or not msg then return end
    if not state.text_items then state.text_items = {} end
    local trk_guid = track and reaper.ValidatePtr(track, "MediaTrack*") and reaper.GetTrackGUID(track)
    if not trk_guid then return end
    
    local parts = {}
    for p in (msg .. "|"):gmatch("([^|]*)|") do table.insert(parts, p) end
    local id = parts[2]
    if not id or id == "" then return end
    
    for _, ti in ipairs(state.text_items) do
        if ti.id == id then return end
    end
    
    local offset_y = tonumber(parts[3]) or 32.0
    local style = (parts[4] and parts[4] ~= "") and parts[4] or "italic"
    local font_size = tonumber(parts[5]) or 16.0
    if font_size < 12.0 then
        font_size = math.max(14.0, math.floor(font_size * 1.45 + 0.5))
    end
    local text = from_hex(parts[6] or "")
    local placement = (parts[7] and parts[7] ~= "") and parts[7] or "below"
    if text == "" then return end
    local qn = (take and reaper.MIDI_GetProjQNFromPPQPos(take, ppq)) or 0.0
    
    table.insert(state.text_items, TextItem.new({
        id = id,
        track_guid = trk_guid,
        qn = qn,
        offset_y = offset_y,
        style = style,
        font_size = font_size,
        text = text,
        placement = placement
    }))
end

function TextItemService.save_text_items(state)
    if not state.text_items then return end
    local list = {}
    for _, ti in ipairs(state.text_items) do
        if type(ti) == "table" and ti.text then
            local text_str = tostring(ti.text)
            -- Only store non-empty text items
            if not text_str:match("^%s*$") then
                local entry = string.format("%s|%s|%.4f|%.2f|%s|%.1f|%s|%s",
                    tostring(ti.id or ""),
                    tostring(ti.track_guid or ""),
                    tonumber(ti.qn) or 0.0,
                    tonumber(ti.offset_y) or 32.0,
                    tostring(ti.style or "italic"),
                    tonumber(ti.font_size) or 16.0,
                    to_hex(text_str),
                    tostring(ti.placement or "below")
                )
                table.insert(list, entry)
            end
        end
    end
    local raw = table.concat(list, ";")
    reaper.SetProjExtState(0, "REAPER_Notator", "text_items", raw)
    sync_text_items_to_takes(state)
    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    if reaper.Main_UpdateLoopInfo then reaper.Main_UpdateLoopInfo(0) end
end

function TextItemService.get_text_items_for_track(state, track_guid)
    local result = {}
    if not state.text_items or not track_guid then return result end
    for _, ti in ipairs(state.text_items) do
        if type(ti) == "table" and ti.track_guid == track_guid then
            table.insert(result, ti)
        end
    end
    table.sort(result, function(a, b) return (a.qn or 0.0) < (b.qn or 0.0) end)
    return result
end

function TextItemService.create_text_item(state, track_guid, qn, arg4, arg5, style, font_size)
    if not state.text_items then state.text_items = {} end

    -- Flexible parameter detection:
    -- Standard signature 1: (state, track_guid, qn, offset_y, text, style, font_size)
    -- Standard signature 2: (state, track_guid, qn, text, offset_y, style, font_size)
    local offset_y = 32.0
    local text = "Text"
    local st = style or "italic"
    local fs = font_size or 16.0

    if type(arg4) == "number" and type(arg5) == "string" then
        offset_y = arg4
        text = arg5
    elseif type(arg4) == "string" and type(arg5) == "number" then
        text = arg4
        offset_y = arg5
    elseif type(arg4) == "string" then
        text = arg4
        if type(arg5) == "string" and (not style or style == "") then
            st = arg5
        end
    elseif type(arg4) == "number" then
        offset_y = arg4
        if type(arg5) == "string" then
            text = arg5
        end
    end

    local ti = TextItem.new({
        track_guid = track_guid,
        qn         = tonumber(qn) or 0.0,
        text       = tostring(text or "Text"),
        offset_y   = tonumber(offset_y) or 32.0,
        style      = tostring(st or "italic"),
        font_size  = tonumber(fs) or 16.0
    })
    table.insert(state.text_items, ti)
    TextItemService.save_text_items(state)
    reaper.Undo_OnStateChange2(0, "Notator: Add Text Item")
    return ti
end

function TextItemService.delete_text_item(state, id)
    if not state.text_items then return end
    for i = #state.text_items, 1, -1 do
        local ti = state.text_items[i]
        if type(ti) == "table" and ti.id == id then
            table.remove(state.text_items, i)
            break
        end
    end
    if state.selected_text_item and state.selected_text_item.id == id then
        state.selected_text_item = nil
    end
    if state.editing_text_item and state.editing_text_item.id == id then
        state.editing_text_item = nil
        state.editing_text_str = nil
    end
    TextItemService.save_text_items(state)
    reaper.Undo_OnStateChange2(0, "Notator: Delete Text Item")
end

function TextItemService.update_text(state, id, new_text)
    if not state.text_items then return end
    local text_str = tostring(new_text or "")
    -- If text content is completely empty or only whitespace, remove the item
    if text_str:match("^%s*$") then
        TextItemService.delete_text_item(state, id)
        return
    end
    
    for _, ti in ipairs(state.text_items) do
        if type(ti) == "table" and ti.id == id then
            ti.text = text_str
            break
        end
    end
    TextItemService.save_text_items(state)
    reaper.Undo_OnStateChange2(0, "Notator: Edit Text Item")
end

function TextItemService.move_text_item(state, id, new_qn, new_offset_y)
    if not state.text_items then return end
    for _, ti in ipairs(state.text_items) do
        if type(ti) == "table" and ti.id == id then
            ti.qn = math.max(0.0, tonumber(new_qn) or 0.0)
            if new_offset_y ~= nil then
                ti.offset_y = tonumber(new_offset_y) or 32.0
            end
            break
        end
    end
    TextItemService.save_text_items(state)
end

return TextItemService

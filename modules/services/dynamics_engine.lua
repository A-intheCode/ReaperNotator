-- ==============================================================================
-- REAPER Native Notator - Service: DynamicsEngine
-- Alex ScoreTools Smart Re-Blend, CC-Interpolation, Velocity Emphasize & Humanize
-- ==============================================================================

local Constants = require("constants")

local DynamicsEngine = {}

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

local function delete_dynamic_from_take(take, target_ppq, opt_label, tol_ppq)
    local tol = tol_ppq or 20
    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
    local to_del = {}
    for i = (text_cnt or 0) - 1, 0, -1 do
        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, i)
        if ok and (ev_type == 15 or ev_type == 7) and math.abs(ppq - target_ppq) <= tol then
            if not opt_label or msg:find(opt_label, 1, true) then
                table.insert(to_del, i)
            end
        end
    end
    for _, idx in ipairs(to_del) do
        reaper.MIDI_DeleteTextSysexEvt(take, idx)
    end
end

local function collect_anchors_from_take(take)
    local anchors = {}
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return anchors end
    
    local _, _, _, text_cnt = reaper.MIDI_CountEvts(take)
    for i = 0, (text_cnt or 0) - 1 do
        local ok, _, _, ppq, ev_type, msg = reaper.MIDI_GetTextSysexEvt(take, i)
        if ok and msg and #msg > 0 then
            local c1, c2, label = nil, nil, nil
            if ev_type == 15 then
                local lbl, v1, v2 = msg:match("dynamic%s+([%a%d]+)%s*:(%d+):(%d+)")
                if lbl and v1 and v2 then
                    label = lbl
                    c1 = tonumber(v1)
                    c2 = tonumber(v2)
                else
                    local lbl_only = msg:match("dynamic%s+([%a%d]+)")
                    if lbl_only then
                        label = lbl_only
                        local lk = DYN_LOOKUP[lbl_only:lower()]
                        c1 = lk and lk.c1 or 80
                        c2 = lk and lk.c2 or 85
                    end
                end
            elseif ev_type == 7 then
                local clean = msg:lower():gsub("%s+", "")
                local lk = DYN_LOOKUP[clean]
                if lk then
                    label = msg:gsub("%s+", "")
                    c1 = lk.c1
                    c2 = lk.c2
                end
            end
            
            if c1 and c2 and label then
                local duplicate = false
                for _, existing in ipairs(anchors) do
                    if math.abs(existing.ppq - ppq) <= 10 then
                        duplicate = true
                        break
                    end
                end
                if not duplicate then
                    table.insert(anchors, {ppq = ppq, c1 = c1, c2 = c2, label = label})
                end
            end
        end
    end
    table.sort(anchors, function(a, b) return a.ppq < b.ppq end)
    return anchors
end

DynamicsEngine.collect_anchors_from_take = collect_anchors_from_take

function DynamicsEngine.get_target_track(state, active_tracks_data)
    if state.focused_track and reaper.ValidatePtr(state.focused_track, "MediaTrack*") then
        return state.focused_track
    end
    if state.selected_dynamic and state.selected_dynamic.track and reaper.ValidatePtr(state.selected_dynamic.track, "MediaTrack*") then
        return state.selected_dynamic.track
    end
    if state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            if sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then
                return sn.track
            end
        end
    end
    if state.selected_note and state.selected_note.track and reaper.ValidatePtr(state.selected_note.track, "MediaTrack*") then
        return state.selected_note.track
    end
    local sel_trk = reaper.GetSelectedTrack(0, 0)
    if sel_trk and reaper.ValidatePtr(sel_trk, "MediaTrack*") then
        return sel_trk
    end
    if active_tracks_data and #active_tracks_data > 0 and active_tracks_data[1].track then
        return active_tracks_data[1].track
    end
    return nil
end

function DynamicsEngine.get_track_marker_blending(track, state)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return (state and state.dyn_marker_blending == true)
    end
    local guid = reaper.GetTrackGUID(track)
    if state and state.track_marker_blending and state.track_marker_blending[guid] ~= nil then
        return state.track_marker_blending[guid]
    end
    
    local ok, str = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:notator_dyn_mod", "", false)
    if ok and str and str ~= "" then
        local m2m = str:match("m2m=(%d+)")
        if m2m then
            local val = (m2m == "1")
            if state and state.track_marker_blending then
                state.track_marker_blending[guid] = val
            end
            return val
        end
    end
    
    -- Default for unconfigured tracks: off by default (false)
    local default_val = (state and state.dyn_marker_blending == true)
    if state and state.track_marker_blending then
        state.track_marker_blending[guid] = default_val
    end
    return default_val
end

function DynamicsEngine.set_track_marker_blending(track, val, state)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return end
    local guid = reaper.GetTrackGUID(track)
    local bool_val = (val ~= false)
    if state then
        if not state.track_marker_blending then state.track_marker_blending = {} end
        state.track_marker_blending[guid] = bool_val
        local cur_trk = DynamicsEngine.get_target_track(state)
        if cur_trk == track then
            state.dyn_marker_blending = bool_val
        end
    end
    DynamicsEngine.save_track_modulators(track, state)
end

function DynamicsEngine.get_item_marker_blending(item, state)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then
        return (state and state.dyn_marker_blending == true)
    end
    local ikey = tostring(item)
    if state and state.item_marker_blending and state.item_marker_blending[ikey] ~= nil then
        return state.item_marker_blending[ikey]
    end
    local ok, str = reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_dyn_mod", "", false)
    if ok and str and str ~= "" then
        local m2m = str:match("m2m=(%d+)")
        if m2m then
            local val = (m2m == "1")
            if state and state.item_marker_blending then state.item_marker_blending[ikey] = val end
            return val
        end
    end
    local parent_trk = reaper.GetMediaItemTrack(item)
    return DynamicsEngine.get_track_marker_blending(parent_trk, state)
end

function DynamicsEngine.set_item_marker_blending(item, val, state)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then return end
    local ikey = tostring(item)
    local bool_val = (val ~= false)
    if state then
        if not state.item_marker_blending then state.item_marker_blending = {} end
        state.item_marker_blending[ikey] = bool_val
        state.dyn_marker_blending = bool_val
    end
    DynamicsEngine.save_item_modulators(item, state)
end

function DynamicsEngine.get_item_bypass_cc(item, state)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then
        return (state and state.dyn_bypass_cc == true)
    end
    local ikey = tostring(item)
    if state and state.item_bypass_cc and state.item_bypass_cc[ikey] ~= nil then
        return state.item_bypass_cc[ikey]
    end
    local ok, str = reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_dyn_mod", "", false)
    if ok and str and str ~= "" then
        local bcc = str:match("bypass_cc=(%d+)")
        if bcc then
            local val = (bcc == "1")
            if state and state.item_bypass_cc then state.item_bypass_cc[ikey] = val end
            return val
        end
    end
    local parent_trk = reaper.GetMediaItemTrack(item)
    if parent_trk and reaper.ValidatePtr(parent_trk, "MediaTrack*") then
        local tok, tstr = reaper.GetSetMediaTrackInfo_String(parent_trk, "P_EXT:notator_dyn_mod", "", false)
        if tok and tstr and tstr ~= "" then
            local tbcc = tstr:match("bypass_cc=(%d+)")
            if tbcc then
                local val = (tbcc == "1")
                if state and state.item_bypass_cc then state.item_bypass_cc[ikey] = val end
                return val
            end
        end
    end
    return (state and state.dyn_bypass_cc == true)
end

function DynamicsEngine.set_item_bypass_cc(item, val, state)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then return end
    local ikey = tostring(item)
    local bool_val = (val ~= false)
    if state then
        if not state.item_bypass_cc then state.item_bypass_cc = {} end
        state.item_bypass_cc[ikey] = bool_val
        state.dyn_bypass_cc = bool_val
    end
    DynamicsEngine.save_item_modulators(item, state)
end

function DynamicsEngine.load_item_modulators(item, state)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then return end
    local ikey = tostring(item)
    
    local ok, str = reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_dyn_mod", "", false)
    if ok and str and str ~= "" then
        -- Default reset before loading item string
        state.dyn_bow_intensity = 0.0
        state.dyn_bow_pos = 0.50
        for pair in str:gmatch("([^|]+)") do
            local k, v = pair:match("([^=]+)=(.*)")
            if k and v then
                if k == "cc_a" then state.dyn_cc_a = tonumber(v) or state.dyn_cc_a
                elseif k == "cc_b" then state.dyn_cc_b = tonumber(v) or state.dyn_cc_b
                elseif k == "grid" then state.dyn_grid_idx = tonumber(v) or state.dyn_grid_idx
                elseif k == "phr" then state.dyn_phrasing_active = (v == "1" or v == "true")
                elseif k == "p_int" then state.dyn_phrasing_intensity = tonumber(v) or state.dyn_phrasing_intensity
                elseif k == "h_int" then state.dyn_humanize_intensity = tonumber(v) or state.dyn_humanize_intensity
                elseif k == "stress" then state.dyn_stress_factor = tonumber(v) or state.dyn_stress_factor
                elseif k == "bow" then state.dyn_bow_intensity = tonumber(v) or 0.0
                elseif k == "bow_pos" then state.dyn_bow_pos = tonumber(v) or 0.50
                elseif k == "vel_sens" then state.dyn_vel_sensitivity = tonumber(v) or state.dyn_vel_sensitivity
                elseif k == "m2m" then
                    local is_on = (v == "1" or v == "true")
                    state.dyn_marker_blending = is_on
                    if state.item_marker_blending then state.item_marker_blending[ikey] = is_on end
                elseif k == "bypass_cc" then
                    local is_byp = (v == "1" or v == "true")
                    state.dyn_bypass_cc = is_byp
                    if state.item_bypass_cc then state.item_bypass_cc[ikey] = is_byp end
                end
            end
        end
    else
        -- Unconfigured / New item: ALWAYS reset item-specific modulators to clean defaults (Phrasing ON by default)
        state.dyn_bow_intensity = 0.0
        state.dyn_bow_pos = 0.50
        state.dyn_phrasing_active = true
        state.dyn_phrasing_intensity = 0.50
        state.dyn_humanize_intensity = 0.30
        state.dyn_stress_factor = 0.50
        state.dyn_vel_sensitivity = 0.80
        state.dyn_marker_blending = false
        state.dyn_bypass_cc = false
        if state.item_marker_blending then state.item_marker_blending[ikey] = false end
        if state.item_bypass_cc then state.item_bypass_cc[ikey] = false end

        -- Only inherit track-level CC routing if available
        local parent_trk = reaper.GetMediaItemTrack(item)
        if parent_trk and reaper.ValidatePtr(parent_trk, "MediaTrack*") then
            local ok_t, str_t = reaper.GetSetMediaTrackInfo_String(parent_trk, "P_EXT:notator_dyn_mod", "", false)
            if ok_t and str_t and str_t ~= "" then
                for pair in str_t:gmatch("([^|]+)") do
                    local k, v = pair:match("([^=]+)=(.*)")
                    if k == "cc_a" then state.dyn_cc_a = tonumber(v) or state.dyn_cc_a
                    elseif k == "cc_b" then state.dyn_cc_b = tonumber(v) or state.dyn_cc_b
                    elseif k == "grid" then state.dyn_grid_idx = tonumber(v) or state.dyn_grid_idx
                    end
                end
            end
        end
        -- Persist clean defaults to item so it has its own record
        DynamicsEngine.save_item_modulators(item, state)
    end
end

function DynamicsEngine.save_item_modulators(item, state)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then return end
    local ikey = tostring(item)
    local is_m2m = (state.dyn_marker_blending == true)
    local is_bypass = (state.dyn_bypass_cc == true)
    if state.item_marker_blending then state.item_marker_blending[ikey] = is_m2m end
    if state.item_bypass_cc then state.item_bypass_cc[ikey] = is_bypass end
    
    local str = string.format("cc_a=%d|cc_b=%d|grid=%d|phr=%d|p_int=%.2f|h_int=%.2f|stress=%.2f|bow=%.2f|bow_pos=%.2f|vel_sens=%.2f|m2m=%d|bypass_cc=%d",
        state.dyn_cc_a or 1,
        state.dyn_cc_b or 11,
        state.dyn_grid_idx or 4,
        (state.dyn_phrasing_active ~= false) and 1 or 0,
        state.dyn_phrasing_intensity or 0.50,
        state.dyn_humanize_intensity or 0.30,
        state.dyn_stress_factor or 0.50,
        state.dyn_bow_intensity or 0.0,
        state.dyn_bow_pos or 0.50,
        state.dyn_vel_sensitivity or 0.80,
        is_m2m and 1 or 0,
        is_bypass and 1 or 0
    )
    reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_dyn_mod", str, true)
end

function DynamicsEngine.load_track_modulators(track, state)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return end
    local guid = reaper.GetTrackGUID(track)
    
    -- Always reset item-specific modulators to clean defaults when focused on track level
    state.dyn_bow_intensity = 0.0
    state.dyn_bow_pos = 0.50
    state.dyn_phrasing_active = true
    
    -- Load track-specific blending from cache or default (OFF by default)
    local track_m2m = (state and state.dyn_marker_blending == true)
    if state and state.track_marker_blending and state.track_marker_blending[guid] ~= nil then
        track_m2m = state.track_marker_blending[guid]
    end
    state.dyn_marker_blending = track_m2m
    
    local ok, str = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:notator_dyn_mod", "", false)
    if ok and str and str ~= "" then
        for pair in str:gmatch("([^|]+)") do
            local k, v = pair:match("([^=]+)=(.*)")
            if k and v then
                if k == "cc_a" then state.dyn_cc_a = tonumber(v) or state.dyn_cc_a
                elseif k == "cc_b" then state.dyn_cc_b = tonumber(v) or state.dyn_cc_b
                elseif k == "grid" then state.dyn_grid_idx = tonumber(v) or state.dyn_grid_idx
                elseif k == "phr" then state.dyn_phrasing_active = (v == "1" or v == "true")
                elseif k == "p_int" then state.dyn_phrasing_intensity = tonumber(v) or state.dyn_phrasing_intensity
                elseif k == "h_int" then state.dyn_humanize_intensity = tonumber(v) or state.dyn_humanize_intensity
                elseif k == "stress" then state.dyn_stress_factor = tonumber(v) or state.dyn_stress_factor
                elseif k == "vel_sens" then state.dyn_vel_sensitivity = tonumber(v) or state.dyn_vel_sensitivity
                elseif k == "m2m" then
                    local is_on = (v == "1" or v == "true")
                    state.dyn_marker_blending = is_on
                    if state.track_marker_blending then
                        state.track_marker_blending[guid] = is_on
                    end
                elseif k == "bypass_cc" then
                    state.dyn_bypass_cc = (v == "1" or v == "true")
                end
            end
        end
    else
        -- Track does not have a P_EXT yet: store the default
        if state and state.track_marker_blending then
            state.track_marker_blending[guid] = track_m2m
        end
    end
end

function DynamicsEngine.save_track_modulators(track, state)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return end
    local is_m2m = DynamicsEngine.get_track_marker_blending(track, state)
    local str = string.format("cc_a=%d|cc_b=%d|grid=%d|phr=%d|p_int=%.2f|h_int=%.2f|stress=%.2f|bow=0.00|bow_pos=0.50|vel_sens=%.2f|m2m=%d|bypass_cc=%d",
        state.dyn_cc_a or 1,
        state.dyn_cc_b or 11,
        state.dyn_grid_idx or 4,
        (state.dyn_phrasing_active ~= false) and 1 or 0,
        state.dyn_phrasing_intensity or 0.50,
        state.dyn_humanize_intensity or 0.30,
        state.dyn_stress_factor or 0.50,
        state.dyn_vel_sensitivity or 0.80,
        is_m2m and 1 or 0,
        (state.dyn_bypass_cc == true) and 1 or 0
    )
    reaper.GetSetMediaTrackInfo_String(track, "P_EXT:notator_dyn_mod", str, true)
end

function DynamicsEngine.get_pitch_at_ppq(take, ppq)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return nil end
    local _, note_cnt = reaper.MIDI_CountEvts(take)
    for i = 0, note_cnt - 1 do
        local ok, _, _, start_ppq, end_ppq, _, pitch, _ = reaper.MIDI_GetNote(take, i)
        if ok and ppq >= start_ppq and ppq <= end_ppq then
            return pitch
        end
    end
    return nil
end

-- Calculates the asymmetrical bow swell shaping curve with variable peak (0.0 = start, 0.5 = center, 1.0 = end)
function DynamicsEngine.calc_bow_curve(t, pos)
    if not t then return 0 end
    local p = math.max(0.001, math.min(0.999, pos or 0.5))
    if t <= p then
        return math.sin((t / p) * (math.pi / 2))
    else
        return math.cos(((t - p) / (1.0 - p)) * (math.pi / 2))
    end
end

function DynamicsEngine.get_smart_val(state, v1, v2, ratio, pitch_delta, seed_base)
    local v = v1 + (v2 - v1) * ratio
    if state.dyn_phrasing_active then
        local s = (1 - math.cos(ratio * math.pi)) / 2
        v = v1 + (v2 - v1) * (ratio + (s - ratio) * (state.dyn_phrasing_intensity or 0.5))
    end
    if (state.dyn_stress_factor or 0) > 0 and pitch_delta ~= 0 then
        local amp = (pitch_delta / 12) * 24 * (state.dyn_stress_factor or 0)
        local taper = math.sin(ratio * math.pi)
        local sine_mod = math.sin(ratio * math.pi * 1.5) * math.exp(-ratio * 2) * taper
        v = v + (sine_mod * amp)
    end
    if (state.dyn_humanize_intensity or 0) > 0 then
        math.randomseed(math.floor(seed_base + ratio * 5000))
        v = v + (math.random() - 0.5) * 6 * (state.dyn_humanize_intensity or 0)
    end
    -- Prevent unphysical overshoot beyond boundaries
    if v1 < v2 then
        v = math.max(v1, math.min(v2, v))
    elseif v1 > v2 then
        v = math.min(v1, math.max(v2, v))
    end
    return math.max(0, math.min(127, math.floor(v + 0.5)))
end

function DynamicsEngine.insert_dynamic_anchor(btn, state, midi_service, active_tracks_data)
    local targets = {}
    for _, sn in pairs(state.selected_notes) do table.insert(targets, sn) end
    if #targets == 0 and state.selected_note then table.insert(targets, state.selected_note) end
    
    if #targets > 0 then
        reaper.Undo_BeginBlock2(0)
        local total_inserted = 0
        local seen_pos = {}
        local affected_takes = {}
        for _, n in ipairs(targets) do
            local tk = n.take
            if tk and reaper.ValidatePtr(tk, "MediaItem_Take*") then
                local it = n.item or reaper.GetMediaItemTake_Item(tk)
                if it then
                    DynamicsEngine.load_item_modulators(it, state)
                end
                local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(tk, n.start_qn) + 0.5)
                local pos_key = string.format("%s_%d", tostring(tk), ppq)
                if not seen_pos[pos_key] then
                    seen_pos[pos_key] = true
                    delete_dynamic_from_take(tk, ppq, nil, 20)
                    reaper.MIDI_InsertTextSysexEvt(tk, false, false, ppq, 15, string.format("dynamic %s :%d:%d", btn.label, btn.c1, btn.c11))
                    reaper.MIDI_InsertTextSysexEvt(tk, false, false, ppq, 7, btn.label)
                    if not state.dyn_bypass_cc then
                        local cc_a = math.floor(state.dyn_cc_a or 1)
                        local cc_b = math.floor(state.dyn_cc_b or 11)
                        local cur_ppq = math.floor(ppq + 0.5)
                        local c1_v = math.max(0, math.min(127, math.floor(btn.c1 + 0.5)))
                        local c11_v = math.max(0, math.min(127, math.floor(btn.c11 + 0.5)))
                        reaper.MIDI_InsertCC(tk, false, false, cur_ppq, 176, 0, cc_a, c1_v)
                        reaper.MIDI_InsertCC(tk, false, false, cur_ppq, 176, 0, cc_b, c11_v)
                    end
                    reaper.MIDI_Sort(tk)
                    total_inserted = total_inserted + 1
                    affected_takes[tk] = true
                end
            end
        end
        reaper.Undo_EndBlock2(0, "Notator: Dynamic " .. btn.label, -1)
        reaper.UpdateArrange()
        
        -- Automatically perform re-blend if 2 or more anchors exist
        for tk in pairs(affected_takes) do
            if #collect_anchors_from_take(tk) >= 2 then
                DynamicsEngine.smart_reblend_all(state, midi_service, active_tracks_data, tk)
            end
        end
        if state.dyn_bypass_cc then
            state.status_msg = string.format("Set dynamic %s at %d position(s) (CC Bypassed / Hand-drawn preserved)", btn.label, total_inserted)
        else
            state.status_msg = string.format("Set dynamic %s at %d position(s)", btn.label, total_inserted)
        end
    else
        local target_item, target_take = midi_service.get_target_item_and_take(state, active_tracks_data)
        if not target_take then
            local cur_time = reaper.GetCursorPosition()
            local cur_qn = reaper.TimeMap2_timeToQN(0, cur_time)
            target_item, target_take = midi_service.get_or_create_item_at_qn(state.focused_track, cur_qn, 1.0)
        end
        if not target_take or not reaper.ValidatePtr(target_take, "MediaItem_Take*") then
            state.status_msg = "Dynamics: Please select a MIDI item or track first!"
            return
        end
        
        if target_item then
            DynamicsEngine.load_item_modulators(target_item, state)
        end
        
        local cur_time = reaper.GetCursorPosition()
        local ppq = math.floor(reaper.MIDI_GetPPQPosFromProjTime(target_take, cur_time) + 0.5)
        
        reaper.Undo_BeginBlock2(0)
        delete_dynamic_from_take(target_take, ppq, nil, 20)
        reaper.MIDI_InsertTextSysexEvt(target_take, false, false, ppq, 15, string.format("dynamic %s :%d:%d", btn.label, btn.c1, btn.c11))
        reaper.MIDI_InsertTextSysexEvt(target_take, false, false, ppq, 7, btn.label)
        if not state.dyn_bypass_cc then
            local cc_a = math.floor(state.dyn_cc_a or 1)
            local cc_b = math.floor(state.dyn_cc_b or 11)
            local cur_ppq = math.floor(ppq + 0.5)
            local c1_v = math.max(0, math.min(127, math.floor(btn.c1 + 0.5)))
            local c11_v = math.max(0, math.min(127, math.floor(btn.c11 + 0.5)))
            reaper.MIDI_InsertCC(target_take, false, false, cur_ppq, 176, 0, cc_a, c1_v)
            reaper.MIDI_InsertCC(target_take, false, false, cur_ppq, 176, 0, cc_b, c11_v)
        end
        reaper.MIDI_Sort(target_take)
        reaper.Undo_EndBlock2(0, "Notator: Dynamic " .. btn.label, -1)
        reaper.UpdateArrange()
        
        -- Automatically perform re-blend if 2 or more anchors exist (affected range only!)
        if #collect_anchors_from_take(target_take) >= 2 then
            DynamicsEngine.smart_reblend_all(state, midi_service, active_tracks_data, target_take, ppq, ppq)
        end
        if state.dyn_bypass_cc then
            state.status_msg = string.format("Dynamic %s set at cursor (CC Bypassed / Hand-drawn preserved)", btn.label)
        else
            state.status_msg = string.format("Dynamic %s set at cursor (CC%d: %d, CC%d: %d)", btn.label, state.dyn_cc_a, btn.c1, state.dyn_cc_b, btn.c11)
        end
    end
end

function DynamicsEngine.smart_reblend_all(state, midi_service, active_tracks_data, opt_take, opt_range_start_ppq, opt_range_end_ppq)
    local target_item, take, target_track, item_name
    if opt_take and reaper.ValidatePtr(opt_take, "MediaItem_Take*") and reaper.TakeIsMIDI(opt_take) then
        take = opt_take
        target_item = reaper.GetMediaItemTake_Item(take)
        target_track = target_item and reaper.GetMediaItemTrack(target_item)
        local _, iname = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
        item_name = iname
    else
        target_item, take, target_track, item_name = midi_service.get_target_item_and_take(state, active_tracks_data)
    end
    
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        state.status_msg = "Re-Blend: Please select a MIDI item or note/dynamic first!"
        return
    end
    
    -- Load item-specific (or fallback track-specific) Smart Modulator settings
    if target_item and reaper.ValidatePtr(target_item, "MediaItem*") then
        DynamicsEngine.load_item_modulators(target_item, state)
    elseif target_track and reaper.ValidatePtr(target_track, "MediaTrack*") then
        DynamicsEngine.load_track_modulators(target_track, state)
    end
    
    if not state then state = {} end
    if not state.dyn_cc_a then state.dyn_cc_a = 1 end
    if not state.dyn_cc_b then state.dyn_cc_b = 11 end
    
    local anchors = collect_anchors_from_take(take)
    
    -- WHEN BYPASS DYNAMIC CC SHAPING IS ACTIVE:
    -- Do not delete or write any CC curves! Hand-drawn CC automation remains 100% intact.
    -- Only keep Text/Sysex notation markers (Type 15 & 7) synchronized.
    if state.dyn_bypass_cc then
        reaper.Undo_BeginBlock2(0)
        for i = 1, #anchors do
            local anc = anchors[i]
            if anc then
                delete_dynamic_from_take(take, anc.ppq, anc.label, 10)
                reaper.MIDI_InsertTextSysexEvt(take, false, false, anc.ppq, 15, string.format("dynamic %s :%d:%d", anc.label, anc.c1, anc.c2))
                reaper.MIDI_InsertTextSysexEvt(take, false, false, anc.ppq, 7, anc.label)
            end
        end
        reaper.MIDI_Sort(take)
        reaper.Undo_EndBlock2(0, string.format("Sync Notations (CC Bypassed) (%s)", item_name or "Item"), -1)
        reaper.UpdateArrange()
        state.status_msg = string.format("⚡ Re-Blend (CC Bypassed): Notations synchronized for '%s' (Hand-drawn CCs preserved)", item_name or "Item")
        return
    end
    if #anchors == 0 then
        -- Check if there are hairpins or dynamic texts on this track
        local trk_guid = target_track and reaper.ValidatePtr(target_track, "MediaTrack*") and reaper.GetTrackGUID(target_track)
        local has_hps = false
        if state.hairpins then
            for _, hp in ipairs(state.hairpins) do
                if not trk_guid or hp.track_guid == trk_guid then has_hps = true break end
            end
        end
        if not has_hps and state.dynamic_texts then
            for _, dt in ipairs(state.dynamic_texts) do
                if not trk_guid or dt.track_guid == trk_guid then has_hps = true break end
            end
        end
        if not has_hps then
            state.status_msg = string.format("No dynamic markers or hairpins in '%s' for Re-Blend!", item_name or "Item")
            return
        end
        
        reaper.Undo_BeginBlock2(0)
        if state.hairpins then
            local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
            if HairpinService and HairpinService.apply_hairpin_cc then
                for _, hp in ipairs(state.hairpins) do
                    if not trk_guid or hp.track_guid == trk_guid then
                        HairpinService.apply_hairpin_cc(state, hp, midi_service, active_tracks_data)
                    end
                end
            end
        end
        if state.dynamic_texts then
            local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
            if DynamicTextService and DynamicTextService.apply_cc then
                for _, dt in ipairs(state.dynamic_texts) do
                    if not trk_guid or dt.track_guid == trk_guid then
                        DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data)
                    end
                end
            end
        end
        reaper.MIDI_Sort(take)
        reaper.Undo_EndBlock2(0, string.format("Smart Re-Blend (%s)", item_name or "Item"), -1)
        reaper.UpdateArrange()
        return
    elseif #anchors == 1 then
        reaper.Undo_BeginBlock2(0)
        local a1 = anchors[1]
        local _, _, cc_count = reaper.MIDI_CountEvts(take)
        for j = (cc_count or 0) - 1, 0, -1 do
            local ok, _, _, ppq, _, _, m, _ = reaper.MIDI_GetCC(take, j)
            if ok and (m == state.dyn_cc_a or m == state.dyn_cc_b) then
                reaper.MIDI_DeleteCC(take, j)
            end
        end
        local cc_a = math.floor(state.dyn_cc_a or 1)
        local cc_b = math.floor(state.dyn_cc_b or 11)
        local a1_ppq = math.floor(a1.ppq + 0.5)
        local a1_c1 = math.max(0, math.min(127, math.floor(a1.c1 + 0.5)))
        local a1_c2 = math.max(0, math.min(127, math.floor(a1.c2 + 0.5)))
        reaper.MIDI_InsertCC(take, false, false, a1_ppq, 176, 0, cc_a, a1_c1)
        reaper.MIDI_InsertCC(take, false, false, a1_ppq, 176, 0, cc_b, a1_c2)
        
        local trk_guid = target_track and reaper.ValidatePtr(target_track, "MediaTrack*") and reaper.GetTrackGUID(target_track)
        if state.hairpins then
            local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
            if HairpinService and HairpinService.apply_hairpin_cc then
                for _, hp in ipairs(state.hairpins) do
                    if not trk_guid or hp.track_guid == trk_guid then
                        HairpinService.apply_hairpin_cc(state, hp, midi_service, active_tracks_data)
                    end
                end
            end
        end
        if state.dynamic_texts then
            local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
            if DynamicTextService and DynamicTextService.apply_cc then
                for _, dt in ipairs(state.dynamic_texts) do
                    if not trk_guid or dt.track_guid == trk_guid then
                        DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data)
                    end
                end
            end
        end
        reaper.MIDI_Sort(take)
        reaper.Undo_EndBlock2(0, string.format("Smart Re-Blend (%s)", item_name or "Item"), -1)
        reaper.UpdateArrange()
        return
    end
    
    local clear_s_ppq = nil
    local clear_e_ppq = nil
    local pair_start_idx = 1
    local pair_end_idx = #anchors - 1
    local is_selective = false
    
    if opt_range_start_ppq and opt_range_end_ppq then
        is_selective = true
        local r_min = math.min(opt_range_start_ppq, opt_range_end_ppq)
        local r_max = math.max(opt_range_start_ppq, opt_range_end_ppq)
        
        -- Left neighbor anchor (<= r_min)
        local left_idx = 1
        for i = 1, #anchors do
            if anchors[i].ppq <= r_min + 10 then
                left_idx = i
            else
                break
            end
        end
        if left_idx > 1 and anchors[left_idx].ppq >= r_min - 10 then
            left_idx = left_idx - 1
        end
        
        -- Right neighbor anchor (>= r_max)
        local right_idx = #anchors
        for i = #anchors, 1, -1 do
            if anchors[i].ppq >= r_max - 10 then
                right_idx = i
            else
                break
            end
        end
        if right_idx < #anchors and anchors[right_idx].ppq <= r_max + 10 then
            right_idx = right_idx + 1
        end
        
        left_idx = math.max(1, math.min(left_idx, #anchors - 1))
        right_idx = math.max(left_idx + 1, math.min(right_idx, #anchors))
        
        clear_s_ppq = anchors[left_idx].ppq
        clear_e_ppq = anchors[right_idx].ppq
        pair_start_idx = left_idx
        pair_end_idx = right_idx - 1
    end
    
    reaper.Undo_BeginBlock2(0)
    
    -- Delete existing CC events on CC_A and CC_B (affected range only!)
    local _, _, cc_count = reaper.MIDI_CountEvts(take)
    for j = (cc_count or 0) - 1, 0, -1 do
        local ok, _, _, ppq, _, _, m, _ = reaper.MIDI_GetCC(take, j)
        if ok and (m == state.dyn_cc_a or m == state.dyn_cc_b) then
            if (not clear_s_ppq or ppq >= clear_s_ppq) and (not clear_e_ppq or ppq <= clear_e_ppq) then
                reaper.MIDI_DeleteCC(take, j)
            end
        end
    end
    
    -- Grid resolution for CC points
    local opt = Constants.DYN_GRID_OPTIONS[state.dyn_grid_idx] or Constants.DYN_GRID_OPTIONS[4]
    local grid_ppq = (opt and opt.val) and math.floor(opt.val * 960 + 0.5) or 240
    if grid_ppq < 10 then grid_ppq = 60 end
    
    -- Determine marker blending status specifically for this item
    local is_m2m = DynamicsEngine.get_item_marker_blending(target_item, state)
    
    -- Prepare take notes for phrasing, bow swelling & pitch stress
    local take_notes = {}
    local _, note_cnt = reaper.MIDI_CountEvts(take)
    for n = 0, (note_cnt or 0) - 1 do
        local ok, _, _, s_ppq, e_ppq, _, pitch, vel = reaper.MIDI_GetNote(take, n)
        if ok then
            local s_qn = reaper.MIDI_GetProjQNFromPPQPos(take, s_ppq)
            local e_qn = reaper.MIDI_GetProjQNFromPPQPos(take, e_ppq)
            table.insert(take_notes, {
                start_ppq = s_ppq,
                end_ppq = e_ppq,
                pitch = pitch,
                vel = vel,
                dur_qn = math.abs(e_qn - s_qn)
            })
        end
    end
    table.sort(take_notes, function(a, b) return a.start_ppq < b.start_ppq end)
    
    local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
    local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
    
    local function render_segment(s_ppq, e_ppq, val1_s, val2_s, val1_e, val2_e, is_blend)
        local seg_dur = e_ppq - s_ppq
        if seg_dur <= 0 then return end
        
        local has_bow = (state.dyn_bow_intensity or 0) > 0
        local has_stress = (state.dyn_stress_factor or 0) > 0
        local has_hum = (state.dyn_humanize_intensity or 0) > 0
        
        if state.dyn_phrasing_active or has_bow or has_stress or has_hum then
            local steps = math.max(1, math.floor(seg_dur / grid_ppq))
            for s = 0, steps do
                local cur = s_ppq + math.floor(s * (seg_dur / steps) + 0.5)
                if cur <= e_ppq then
                    local ratio = (cur - s_ppq) / seg_dur
                    local base_c1 = is_blend and (val1_s + (val1_e - val1_s) * ratio) or val1_s
                    local base_c2 = is_blend and (val2_s + (val2_e - val2_s) * ratio) or val2_s
                    
                    -- Find active note at this PPQ for phrasing, bow swelling & pitch stress
                    local active_pitch = nil
                    local active_progress = nil
                    local active_dur_qn = nil
                    for _, n in ipairs(take_notes) do
                        if cur >= n.start_ppq and cur <= n.end_ppq then
                            active_pitch = n.pitch
                            local ndur = n.end_ppq - n.start_ppq
                            active_progress = (ndur > 0) and ((cur - n.start_ppq) / ndur) or 0.5
                            active_dur_qn = n.dur_qn
                            break
                        elseif n.start_ppq > cur then
                            break
                        end
                    end
                    
                    local v1 = base_c1
                    local v2 = base_c2
                    
                    -- 1. Phrasing (Breathing)
                    if state.dyn_phrasing_active then
                        local p_int = state.dyn_phrasing_intensity or 0.5
                        if active_progress then
                            local breath = math.sin(active_progress * math.pi)
                            local breath_val = breath * (p_int * 14.0)
                            v1 = v1 + breath_val
                            v2 = v2 + breath_val
                        elseif is_blend and (val1_e ~= val1_s) then
                            local s_curve = (1 - math.cos(ratio * math.pi)) / 2
                            v1 = val1_s + (val1_e - val1_s) * (ratio + (s_curve - ratio) * p_int)
                            v2 = val2_s + (val2_e - val2_s) * (ratio + (s_curve - ratio) * p_int)
                        end
                    end
                    
                    -- 2. Bow Swelling (Bell Curve / Violin Bow Simulation)
                    -- Only active for notes >= quarter note (dur_qn >= 0.90 QN). Notes below quarter note are ignored.
                    if has_bow and active_progress and active_dur_qn and active_dur_qn >= 0.90 then
                        local bow_curve = DynamicsEngine.calc_bow_curve(active_progress, state.dyn_bow_pos)
                        local bow_val = bow_curve * ((state.dyn_bow_intensity or 0) * 22.0)
                        v1 = v1 + bow_val
                        v2 = v2 + bow_val
                    end
                    
                    -- 3. Pitch Stress
                    if has_stress and active_pitch then
                        local p_stress = ((active_pitch - 60) / 12.0) * ((state.dyn_stress_factor or 0) * 10.0)
                        v1 = v1 + p_stress
                        v2 = v2 + p_stress
                    end
                    
                    -- 4. Humanize Jitter
                    if has_hum then
                        local pseudo_rnd = math.sin(cur * 12.9898 + (val1_s or 0)) * 43758.5453
                        local noise = ((pseudo_rnd - math.floor(pseudo_rnd)) - 0.5) * ((state.dyn_humanize_intensity or 0) * 10.0)
                        v1 = v1 + noise
                        v2 = v2 + noise
                    end
                    
                    -- For pure blending without bow swelling: prevent overshoot
                    if is_blend and not has_bow then
                        if val1_s < val1_e then
                            v1 = math.max(val1_s, math.min(val1_e, v1))
                        elseif val1_s > val1_e then
                            v1 = math.min(val1_s, math.max(val1_e, v1))
                        end
                        if val2_s < val2_e then
                            v2 = math.max(val2_s, math.min(val2_e, v2))
                        elseif val2_s > val2_e then
                            v2 = math.min(val2_s, math.max(val2_e, v2))
                        end
                    end
                    
                    -- Exact landing at boundary edges
                    if s == steps or cur >= e_ppq then
                        v1 = val1_e
                        v2 = val2_e
                    elseif s == 0 or cur <= s_ppq then
                        v1 = val1_s
                        v2 = val2_s
                    end
                    
                    local f1 = math.max(0, math.min(127, math.floor(v1 + 0.5)))
                    local f2 = math.max(0, math.min(127, math.floor(v2 + 0.5)))
                    local cc_a = math.floor(state.dyn_cc_a or 1)
                    local cc_b = math.floor(state.dyn_cc_b or 11)
                    local cur_ppq = math.floor(cur + 0.5)
                    reaper.MIDI_InsertCC(take, false, false, cur_ppq, 176, 0, cc_a, f1)
                    reaper.MIDI_InsertCC(take, false, false, cur_ppq, 176, 0, cc_b, f2)
                end
            end
        else
            -- Phrasing & modulators OFF
            local cc_a = math.floor(state.dyn_cc_a or 1)
            local cc_b = math.floor(state.dyn_cc_b or 11)
            local f1_s = math.max(0, math.min(127, math.floor(val1_s + 0.5)))
            local f2_s = math.max(0, math.min(127, math.floor(val2_s + 0.5)))
            local f1_e = math.max(0, math.min(127, math.floor(val1_e + 0.5)))
            local f2_e = math.max(0, math.min(127, math.floor(val2_e + 0.5)))
            local sp = math.floor(s_ppq + 0.5)
            local ep = math.floor(e_ppq + 0.5)
            if is_blend then
                reaper.MIDI_InsertCC(take, false, false, sp, 176, 0, cc_a, f1_s)
                reaper.MIDI_InsertCC(take, false, false, sp, 176, 0, cc_b, f2_s)
                reaper.MIDI_InsertCC(take, false, false, ep, 176, 0, cc_a, f1_e)
                reaper.MIDI_InsertCC(take, false, false, ep, 176, 0, cc_b, f2_e)
            else
                reaper.MIDI_InsertCC(take, false, false, sp, 176, 0, cc_a, f1_s)
                reaper.MIDI_InsertCC(take, false, false, sp, 176, 0, cc_b, f2_s)
                if ep > sp + 10 then
                    reaper.MIDI_InsertCC(take, false, false, ep - 1, 176, 0, cc_a, f1_s)
                    reaper.MIDI_InsertCC(take, false, false, ep - 1, 176, 0, cc_b, f2_s)
                end
                reaper.MIDI_InsertCC(take, false, false, ep, 176, 0, cc_a, f1_e)
                reaper.MIDI_InsertCC(take, false, false, ep, 176, 0, cc_b, f2_e)
            end
        end
    end
    
    for i = pair_start_idx, pair_end_idx do
        local a1, a2 = anchors[i], anchors[i+1]
        local dur = a2.ppq - a1.ppq
        if dur > 0 then
            -- Collect all hairpins and dynamic texts between these two markers
            local sub_elements = {}
            local trk_guid = target_track and reaper.ValidatePtr(target_track, "MediaTrack*") and reaper.GetTrackGUID(target_track)
            
            if state.hairpins then
                for _, hp in ipairs(state.hairpins) do
                    if not trk_guid or hp.track_guid == trk_guid then
                        local hp_s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, hp.start_qn) + 0.5)
                        local hp_e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, hp.end_qn) + 0.5)
                        if hp_e_ppq > a1.ppq and hp_s_ppq < a2.ppq then
                            local l_b_qn, r_b_qn, p_hp, n_hp, p_dyn, n_dyn = HairpinService.get_hairpin_bounds(state, hp, active_tracks_data)
                            local c1_s, c11_s, c1_e, c11_e = HairpinService.resolve_dynamic_levels(state, hp, active_tracks_data, p_hp, n_hp, p_dyn, n_dyn)
                            table.insert(sub_elements, {
                                type = "hairpin",
                                obj = hp,
                                start_ppq = math.max(a1.ppq, hp_s_ppq),
                                end_ppq = math.min(a2.ppq, hp_e_ppq),
                                c1_s = c1_s, c2_s = c11_s,
                                c1_e = c1_e, c2_e = c11_e
                            })
                        end
                    end
                end
            end
            
            if state.dynamic_texts then
                for _, dt in ipairs(state.dynamic_texts) do
                    if not trk_guid or dt.track_guid == trk_guid then
                        local dt_s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, dt.start_qn) + 0.5)
                        local dt_e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, dt.end_qn) + 0.5)
                        if dt_e_ppq > a1.ppq and dt_s_ppq < a2.ppq then
                            local c1_s, c11_s, c1_e, c11_e = DynamicTextService.resolve_levels(state, dt, active_tracks_data)
                            table.insert(sub_elements, {
                                type = "dynamic_text",
                                obj = dt,
                                start_ppq = math.max(a1.ppq, dt_s_ppq),
                                end_ppq = math.min(a2.ppq, dt_e_ppq),
                                c1_s = c1_s, c2_s = c11_s,
                                c1_e = c1_e, c2_e = c11_e
                            })
                        end
                    end
                end
            end
            
            table.sort(sub_elements, function(a, b) return a.start_ppq < b.start_ppq end)
            
            if #sub_elements == 0 then
                -- No elements in between: normal blending directly from a1 to a2
                render_segment(a1.ppq, a2.ppq, a1.c1, a1.c2, a2.c1, a2.c2, is_m2m)
            else
                -- 1. Leading gap before first element: [a1.ppq .. sub_elements[1].start_ppq]
                if sub_elements[1].start_ppq > a1.ppq + 10 then
                    render_segment(a1.ppq, sub_elements[1].start_ppq, a1.c1, a1.c2, a1.c1, a1.c2, false)
                else
                    local cc_a = math.floor(state.dyn_cc_a or 1)
                    local cc_b = math.floor(state.dyn_cc_b or 11)
                    local a1_ppq = math.floor(a1.ppq + 0.5)
                    local a1_c1 = math.max(0, math.min(127, math.floor(a1.c1 + 0.5)))
                    local a1_c2 = math.max(0, math.min(127, math.floor(a1.c2 + 0.5)))
                    reaper.MIDI_InsertCC(take, false, false, a1_ppq, 176, 0, cc_a, a1_c1)
                    reaper.MIDI_InsertCC(take, false, false, a1_ppq, 176, 0, cc_b, a1_c2)
                end
                
                -- 2. Intermediate gaps between elements: [elem[k].end_ppq .. elem[k+1].start_ppq]
                for k = 1, #sub_elements - 1 do
                    local cur_elem = sub_elements[k]
                    local next_elem = sub_elements[k+1]
                    if next_elem.start_ppq > cur_elem.end_ppq + 10 then
                        render_segment(cur_elem.end_ppq, next_elem.start_ppq, cur_elem.c1_e, cur_elem.c2_e, cur_elem.c1_e, cur_elem.c2_e, false)
                    end
                end
                
                -- 3. Trailing gap after last element: [sub_elements[#sub_elements].end_ppq .. a2.ppq]
                local last_elem = sub_elements[#sub_elements]
                if a2.ppq > last_elem.end_ppq + 10 then
                    render_segment(last_elem.end_ppq, a2.ppq, last_elem.c1_e, last_elem.c2_e, a2.c1, a2.c2, is_m2m)
                else
                    local cc_a = math.floor(state.dyn_cc_a or 1)
                    local cc_b = math.floor(state.dyn_cc_b or 11)
                    local a2_ppq = math.floor(a2.ppq + 0.5)
                    local a2_c1 = math.max(0, math.min(127, math.floor(a2.c1 + 0.5)))
                    local a2_c2 = math.max(0, math.min(127, math.floor(a2.c2 + 0.5)))
                    reaper.MIDI_InsertCC(take, false, false, a2_ppq, 176, 0, cc_a, a2_c1)
                    reaper.MIDI_InsertCC(take, false, false, a2_ppq, 176, 0, cc_b, a2_c2)
                end
            end
        end
    end
    reaper.MIDI_Sort(take)
    
    -- Apply CC curve shape (1 = Linear if marker blending active, 0 = Square if inactive)
    local target_shape = is_m2m and 1 or 0
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
                    if (not clear_s_ppq or running_ppq >= clear_s_ppq) and (not clear_e_ppq or running_ppq <= clear_e_ppq) then
                        flag = (flag & 0x0F) | (target_shape << 4)
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
                if (not clear_s_ppq or ppq >= clear_s_ppq) and (not clear_e_ppq or ppq <= clear_e_ppq) then
                    reaper.MIDI_SetCCShape(take, j, target_shape, 0.0)
                end
            end
        end
    end
    
    -- Ensure each anchor in affected range exists as type 7 and type 15
    local sync_start = is_selective and pair_start_idx or 1
    local sync_end = is_selective and (pair_end_idx + 1) or #anchors
    for i = sync_start, sync_end do
        local anc = anchors[i]
        if anc then
            delete_dynamic_from_take(take, anc.ppq, anc.label, 10)
            reaper.MIDI_InsertTextSysexEvt(take, false, false, anc.ppq, 15, string.format("dynamic %s :%d:%d", anc.label, anc.c1, anc.c2))
            reaper.MIDI_InsertTextSysexEvt(take, false, false, anc.ppq, 7, anc.label)
        end
    end
    reaper.MIDI_Sort(take)
    
    -- Restore and synchronize hairpins of this track (selective within range)
    if state.hairpins and #state.hairpins > 0 then
        local HairpinService = package.loaded["services.hairpin_service"] or require("services.hairpin_service")
        local trk_guid = target_track and reaper.ValidatePtr(target_track, "MediaTrack*") and reaper.GetTrackGUID(target_track)
        local track_hps = {}
        for _, hp in ipairs(state.hairpins) do
            if not trk_guid or hp.track_guid == trk_guid then
                table.insert(track_hps, hp)
            end
        end
        table.sort(track_hps, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
        if trk_guid then
            HairpinService.resolve_all_track_hairpins(state, trk_guid, active_tracks_data)
        end
        
        for _, hp in ipairs(track_hps) do
            local hp_s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, hp.start_qn) + 0.5)
            local hp_e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, hp.end_qn) + 0.5)
            local in_range = true
            if clear_s_ppq and clear_e_ppq then
                in_range = (hp_e_ppq >= clear_s_ppq and hp_s_ppq <= clear_e_ppq)
            end
            if in_range then
                HairpinService.apply_hairpin_cc(state, hp, midi_service, active_tracks_data)
            end
        end
    end
    
    -- Restore and synchronize dynamic texts (cresc. / dim. text tags) of this track
    if state.dynamic_texts and #state.dynamic_texts > 0 then
        local DynamicTextService = package.loaded["services.dynamic_text_service"] or require("services.dynamic_text_service")
        local trk_guid = target_track and reaper.ValidatePtr(target_track, "MediaTrack*") and reaper.GetTrackGUID(target_track)
        local track_dts = {}
        for _, dt in ipairs(state.dynamic_texts) do
            if not trk_guid or dt.track_guid == trk_guid then
                table.insert(track_dts, dt)
            end
        end
        table.sort(track_dts, function(a, b) return (a.start_qn or 0) < (b.start_qn or 0) end)
        
        for _, dt in ipairs(track_dts) do
            local dt_s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, dt.start_qn) + 0.5)
            local dt_e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, dt.end_qn) + 0.5)
            local in_range = true
            if clear_s_ppq and clear_e_ppq then
                in_range = (dt_e_ppq >= clear_s_ppq and dt_s_ppq <= clear_e_ppq)
            end
            if in_range then
                DynamicTextService.apply_cc(state, dt, midi_service, active_tracks_data)
            end
        end
    end
    
    local trk_name = nil
    if target_track then
        _, trk_name = reaper.GetTrackName(target_track)
    end
    reaper.Undo_EndBlock2(0, string.format("Smart Re-Blend (%s)", item_name or "Item"), -1)
    reaper.UpdateArrange()
    if midi_service and midi_service.invalidate_cache then
        midi_service.invalidate_cache()
    else
        local MidiService = package.loaded["services.midi_service"]
        if MidiService and MidiService.invalidate_cache then MidiService.invalidate_cache() end
    end
    
    if is_selective then
        local s_qn = reaper.MIDI_GetProjQNFromPPQPos(take, clear_s_ppq)
        local e_qn = reaper.MIDI_GetProjQNFromPPQPos(take, clear_e_ppq)
        state.status_msg = string.format("⚡ Re-Blend (measure %.2f - %.2f) for '%s - %s'", (s_qn / 4.0) + 1, (e_qn / 4.0) + 1, trk_name or "Track", item_name or "Item")
    else
        state.status_msg = string.format("⚡ Re-Blend successful for '%s - %s' (%d anchors)", trk_name or "Track", item_name or "Item", #anchors)
    end
end

function DynamicsEngine.emphasize_velocity(state, midi_service, active_tracks_data)
    local target_item, take, target_track, item_name = midi_service.get_target_item_and_take(state, active_tracks_data)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        state.status_msg = "Emphasize Velocity: Please select a MIDI item first!"
        return
    end
    
    local anchors = collect_anchors_from_take(take)
    if #anchors < 2 then
        state.status_msg = string.format("At least 2 dynamic markers in '%s' needed for Velocity Emphasize!", item_name or "Item")
        return
    end
    
    reaper.Undo_BeginBlock2(0)
    
    local _, note_count = reaper.MIDI_CountEvts(take)
    local affected = 0
    for i = 0, (note_count or 0) - 1 do
        local ok, sel, muted, start_ppq, end_ppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if ok then
            for j = 1, #anchors - 1 do
                local a1, a2 = anchors[j], anchors[j+1]
                if start_ppq >= a1.ppq and start_ppq <= a2.ppq then
                    local final_vel = 60
                    if state.dyn_vel_sensitivity > 0 then
                        local dur = a2.ppq - a1.ppq
                        local ratio = (dur > 0) and ((start_ppq - a1.ppq) / dur) or 0
                        local p_start = DynamicsEngine.get_pitch_at_ppq(take, a1.ppq)
                        local p_end = DynamicsEngine.get_pitch_at_ppq(take, a2.ppq)
                        local delta = (p_start and p_end) and (p_end - p_start) or 0
                        local target_vel = DynamicsEngine.get_smart_val(state, a1.c1, a2.c1, ratio, delta, a1.c1 + start_ppq)
                        final_vel = math.floor(vel * (1 - state.dyn_vel_sensitivity) + target_vel * state.dyn_vel_sensitivity + 0.5)
                    else
                        final_vel = vel
                    end
                    final_vel = math.max(1, math.min(127, final_vel))
                    reaper.MIDI_SetNote(take, i, sel, muted, start_ppq, end_ppq, chan, pitch, final_vel, false)
                    affected = affected + 1
                    break
                end
            end
        end
    end
    reaper.MIDI_Sort(take)
    reaper.Undo_EndBlock2(0, "ScoreTools: Emphasize Velocity", -1)
    reaper.UpdateArrange()
end

function DynamicsEngine.clean_notation_events(state, midi_service, active_tracks_data)
    local target_item, take, target_track, item_name = midi_service.get_target_item_and_take(state, active_tracks_data)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then
        state.status_msg = "Notation Events: Please select a MIDI item first!"
        return
    end
    
    reaper.Undo_BeginBlock2(0)
    local _, midi_string = reaper.MIDI_GetAllEvts(take, "")
    local new_midi_table, string_pos, acc_offset, del_cnt = {}, 1, 0, 0
    while string_pos <= #midi_string do
        local offset, flag, msg, next_pos = string.unpack("<i4Bs4", midi_string, string_pos)
        if #msg >= 2 and msg:byte(1) == 0xFF and (msg:byte(2) == 0x0F or msg:byte(2) == 0x07) then
            local text = msg:sub(3)
            if text:find("^dynamic%s+") or text:find("^[pPmMfFsSzZ%d]+$") then
                acc_offset = acc_offset + offset
                del_cnt = del_cnt + 1
            else
                table.insert(new_midi_table, string.pack("<i4Bs4", offset + acc_offset, flag, msg))
                acc_offset = 0
            end
        else
            table.insert(new_midi_table, string.pack("<i4Bs4", offset + acc_offset, flag, msg))
            acc_offset = 0
        end
        string_pos = next_pos
    end
    reaper.MIDI_SetAllEvts(take, table.concat(new_midi_table))
    reaper.MIDI_Sort(take)
    reaper.Undo_EndBlock2(0, "Notator: Clean notation events", -1)
    reaper.UpdateArrange()
    state.status_msg = string.format("🗑 %d notation event(s) in '%s' cleaned up (notes unchanged)", del_cnt, item_name or "Item")
end

function DynamicsEngine.delete_selected_dynamic(state, midi_service, active_tracks_data)
    local d = state.selected_dynamic
    if not d or not d.take or not reaper.ValidatePtr(d.take, "MediaItem_Take*") then return end
    
    local take = d.take
    reaper.Undo_BeginBlock2(0)
    delete_dynamic_from_take(take, d.ppq, d.label, 20)
    reaper.MIDI_Sort(take)
    reaper.Undo_EndBlock2(0, "Notator: Delete dynamic", -1)
    reaper.UpdateArrange()
    if midi_service and midi_service.invalidate_cache then
        midi_service.invalidate_cache()
    else
        local MidiService = package.loaded["services.midi_service"]
        if MidiService and MidiService.invalidate_cache then MidiService.invalidate_cache() end
    end
    
    state.selected_dynamic = nil
    state.hovered_dynamic = nil
    state.status_msg = string.format("Deleted dynamic %s", d.label)
    
    if #collect_anchors_from_take(take) >= 2 and midi_service then
        DynamicsEngine.smart_reblend_all(state, midi_service, active_tracks_data, take, d.ppq, d.ppq)
    end
end

function DynamicsEngine.move_dynamic_marker(d, target_take, target_ppq, target_track)
    if not d then return end
    local orig_take = d.take
    local orig_ppq = d.ppq
    
    if not target_take or not reaper.ValidatePtr(target_take, "MediaItem_Take*") then
        target_take = orig_take
    end
    if not target_take or not reaper.ValidatePtr(target_take, "MediaItem_Take*") then return end
    
    reaper.Undo_BeginBlock2(0)
    if orig_take and reaper.ValidatePtr(orig_take, "MediaItem_Take*") then
        delete_dynamic_from_take(orig_take, orig_ppq, d.label, 20)
        reaper.MIDI_Sort(orig_take)
    end
    
    reaper.MIDI_InsertTextSysexEvt(target_take, false, false, target_ppq, 15, string.format("dynamic %s :%d:%d", d.label, d.c1, d.c11))
    reaper.MIDI_InsertTextSysexEvt(target_take, false, false, target_ppq, 7, d.label)
    reaper.MIDI_Sort(target_take)
    
    reaper.Undo_EndBlock2(0, "Notator: Move dynamic", -1)
    reaper.UpdateArrange()
    local MidiService = package.loaded["services.midi_service"]
    if MidiService and MidiService.invalidate_cache then
        MidiService.invalidate_cache()
    end
    
    d.take = target_take
    d.ppq = target_ppq
    d.qn = reaper.MIDI_GetProjQNFromPPQPos(target_take, target_ppq)
    if target_track then d.track = target_track end
    d.key = d:get_key()
end

return DynamicsEngine

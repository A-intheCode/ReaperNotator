-- ==============================================================================
-- REAPER Native Notator - Service: UndoStateService
-- Synchronizes REAPER's C++ Undo/Redo system (40029 / 40030) with Notator's
-- ProjExtState score data so all canvas elements (Hairpins, Pedals, Dynamic
-- Texts, Tempo Markers, Slurs, Ties, Octave Lines, Repeat Marks, Fermatas,
-- Rehearsal Marks, Text Items, Chord Items, Portamentos, Glissandos, Key/Time
-- Signatures, Stem Directions, Noteheads) revert and redo 100% accurately.
-- ==============================================================================

local UndoStateService = {
    live_state = {},
    committed_state = {},
    undo_stack = {},
    redo_stack = {},
    block_depth = 0,
    _seq = 0,
    _restoring = false,
    _initialized = false,
    _installed_target = nil,
}

local SCORE_EXT_KEYS = {
    "hairpins",
    "dynamic_texts",
    "pedal_marks",
    "tempo_markers",
    "octave_lines",
    "text_items",
    "repeat_marks",
    "fermatas",
    "rehearsal_marks",
    "chord_items",
    "chord_target_tracks",
    "user_slurs",
    "user_ties",
    "portamento_marks",
    "glissando_marks",
    "KEY_SIGNATURE",
    "TIME_SIGNATURE",
    "TIME_SIG_CHANGES",
    "track_key_signatures",
    "note_stem_directions",
    "note_head_types",
    "annotation_layers",
}

local IS_SCORE_KEY = {}
for _, k in ipairs(SCORE_EXT_KEYS) do
    IS_SCORE_KEY[k] = true
end

UndoStateService.SCORE_EXT_KEYS = SCORE_EXT_KEYS
UndoStateService.IS_SCORE_KEY = IS_SCORE_KEY

local function copy_map(src)
    local dst = {}
    for _, k in ipairs(SCORE_EXT_KEYS) do
        dst[k] = (src and src[k]) or ""
    end
    if src then
        for k, v in pairs(src) do
            if dst[k] == nil then
                dst[k] = v
            end
        end
    end
    return dst
end

local function maps_differ(a, b)
    for _, k in ipairs(SCORE_EXT_KEYS) do
        local va = (a and a[k]) or ""
        local vb = (b and b[k]) or ""
        if va ~= vb then
            return true
        end
    end
    return false
end

local function is_notator_score_key(extname, key)
    if type(extname) ~= "string" or type(key) ~= "string" then
        return false
    end
    if extname ~= "REAPER_Notator" and extname:upper() ~= "REAPER_NOTATOR" then
        return false
    end
    return IS_SCORE_KEY[key] == true
end

local function write_master_track_p_ext(r, state_map, seq_num)
    if not r or not r.GetMasterTrack or not r.GetSetMediaTrackInfo_String then
        return
    end
    local ok_m, master_trk = pcall(r.GetMasterTrack, 0)
    if not ok_m or not master_trk then
        return
    end
    if seq_num ~= nil then
        pcall(r.GetSetMediaTrackInfo_String, master_trk, "P_EXT:notator_undo_seq", tostring(seq_num), true)
    end
    if state_map then
        for _, k in ipairs(SCORE_EXT_KEYS) do
            local val = state_map[k] or ""
            pcall(r.GetSetMediaTrackInfo_String, master_trk, "P_EXT:notator_ext_" .. k, val, true)
        end
    end
end

local function read_master_track_p_ext(r)
    if not r or not r.GetMasterTrack or not r.GetSetMediaTrackInfo_String then
        return nil
    end
    local ok_m, master_trk = pcall(r.GetMasterTrack, 0)
    if not ok_m or not master_trk then
        return nil
    end
    local ok_seq, seq_str = pcall(r.GetSetMediaTrackInfo_String, master_trk, "P_EXT:notator_undo_seq", "", false)
    if not ok_seq or not seq_str or seq_str == "" then
        return nil
    end
    local restored = {}
    for _, k in ipairs(SCORE_EXT_KEYS) do
        local ok_v, val = pcall(r.GetSetMediaTrackInfo_String, master_trk, "P_EXT:notator_ext_" .. k, "", false)
        restored[k] = (ok_v and val) or ""
    end
    return restored
end

function UndoStateService.record_undo_step(desc)
    if UndoStateService._restoring or not UndoStateService._initialized then
        return
    end
    local d_str = tostring(desc or "")
    local step = {
        before = copy_map(UndoStateService.committed_state),
        after  = copy_map(UndoStateService.live_state),
        desc   = d_str,
    }
    table.insert(UndoStateService.undo_stack, step)
    if #UndoStateService.undo_stack > 256 then
        table.remove(UndoStateService.undo_stack, 1)
    end
    UndoStateService.redo_stack = {}
    UndoStateService.committed_state = copy_map(UndoStateService.live_state)
    UndoStateService._last_recorded_desc = d_str
end

function UndoStateService.on_external_new_action(desc)
    if UndoStateService._restoring or not UndoStateService._initialized then
        return
    end
    local d_str = tostring(desc or "External REAPER Action")
    if not maps_differ(UndoStateService.committed_state, UndoStateService.live_state) then
        if d_str ~= "" and d_str == UndoStateService._last_recorded_desc then
            return
        end
    end
    UndoStateService.record_undo_step(d_str)
end

function UndoStateService.commit_uncommitted_if_idle(ctx, state)
    if UndoStateService._restoring or not UndoStateService._initialized then
        return false
    end
    if UndoStateService.block_depth > 0 then
        return false
    end
    if state and state._in_undo_redo_action then
        return false
    end
    local r = UndoStateService._installed_target or _G.reaper
    if ctx and r and r.APIExists and r.APIExists("ImGui_IsMouseDown") then
        local ok_md, is_down = pcall(r.ImGui_IsMouseDown, ctx, 0)
        if ok_md and is_down then
            return false
        end
    end
    if state and (
        state.is_dragging or state.is_dragging_dynamic or state.is_dragging_hairpin
        or state.is_dragging_dynamic_text or state.is_dragging_pedal
        or state.is_dragging_octave or state.is_dragging_tempo
        or state.is_dragging_text_item or state.is_dragging_chord
        or state.is_dragging_rehearsal_mark or state.is_resizing_item
    ) then
        return false
    end
    if not maps_differ(UndoStateService.committed_state, UndoStateService.live_state) then
        return false
    end
    UndoStateService._seq = (UndoStateService._seq or 0) + 1
    write_master_track_p_ext(r, UndoStateService.live_state, UndoStateService._seq)
    if UndoStateService._orig_Undo_OnStateChange2 then
        pcall(UndoStateService._orig_Undo_OnStateChange2, 0, "Notator: Edit Score")
    end
    UndoStateService.record_undo_step("Notator: Edit Score")
    return true
end

function UndoStateService.init_from_project()
    local r = UndoStateService._installed_target or _G.reaper
    if not r then return end
    local orig_get = UndoStateService._orig_GetProjExtState or r.GetProjExtState
    local orig_set = UndoStateService._orig_SetProjExtState or r.SetProjExtState
    UndoStateService.live_state = {}
    for _, k in ipairs(SCORE_EXT_KEYS) do
        local val = ""
        if orig_get then
            local _, raw = orig_get(0, "REAPER_Notator", k)
            val = tostring(raw or "")
        end
        UndoStateService.live_state[k] = val
    end
    UndoStateService.committed_state = copy_map(UndoStateService.live_state)
    UndoStateService.undo_stack = {}
    UndoStateService.redo_stack = {}
    UndoStateService.block_depth = 0
    UndoStateService._seq = (UndoStateService._seq or 0) + 1
    UndoStateService._restoring = false
    UndoStateService._initialized = true
    write_master_track_p_ext(r, UndoStateService.live_state, UndoStateService._seq)
    if orig_set then
        for _, k in ipairs(SCORE_EXT_KEYS) do
            orig_set(0, "REAPER_Notator", k, UndoStateService.live_state[k] or "")
        end
    end
end

local function apply_snapshot(target_map)
    local r = UndoStateService._installed_target or _G.reaper
    local orig_set = UndoStateService._orig_SetProjExtState or (r and r.SetProjExtState)
    for _, k in ipairs(SCORE_EXT_KEYS) do
        local val = (target_map and target_map[k]) or ""
        UndoStateService.live_state[k] = val
        UndoStateService.committed_state[k] = val
        if orig_set then
            orig_set(0, "REAPER_Notator", k, val)
        end
    end
    write_master_track_p_ext(r, UndoStateService.live_state, UndoStateService._seq)
end

function UndoStateService.can_undo()
    return #(UndoStateService.undo_stack or {}) > 0
end

function UndoStateService.can_redo()
    return #(UndoStateService.redo_stack or {}) > 0
end

function UndoStateService.on_undo(undone_desc)
    local r = UndoStateService._installed_target or _G.reaper
    UndoStateService._restoring = true
    UndoStateService.block_depth = 0
    local target_map = nil
    if #UndoStateService.undo_stack >= 2 then
        local top = UndoStateService.undo_stack[#UndoStateService.undo_stack]
        local prev = UndoStateService.undo_stack[#UndoStateService.undo_stack - 1]
        if top and prev and not maps_differ(top.before, top.after) and maps_differ(prev.before, prev.after) then
            if (undone_desc and undone_desc ~= "" and prev.desc == undone_desc) or (top.desc == prev.desc) then
                table.remove(UndoStateService.undo_stack)
            end
        end
    end
    if #UndoStateService.undo_stack > 0 then
        local step = table.remove(UndoStateService.undo_stack)
        table.insert(UndoStateService.redo_stack, step)
        target_map = step.before
        UndoStateService._last_recorded_desc = (#UndoStateService.undo_stack > 0 and UndoStateService.undo_stack[#UndoStateService.undo_stack].desc) or nil
    else
        target_map = read_master_track_p_ext(r)
        UndoStateService._last_recorded_desc = nil
    end
    if target_map then
        apply_snapshot(target_map)
    end
    UndoStateService._restoring = false
    return target_map ~= nil
end

function UndoStateService.on_redo()
    local r = UndoStateService._installed_target or _G.reaper
    UndoStateService._restoring = true
    UndoStateService.block_depth = 0
    local target_map = nil
    if #UndoStateService.redo_stack > 0 then
        local step = table.remove(UndoStateService.redo_stack)
        table.insert(UndoStateService.undo_stack, step)
        target_map = step.after
        UndoStateService._last_recorded_desc = step.desc
    else
        target_map = read_master_track_p_ext(r)
    end
    if target_map then
        apply_snapshot(target_map)
    end
    UndoStateService._restoring = false
    return target_map ~= nil
end

function UndoStateService.install(reaper_api)
    local r = reaper_api or _G.reaper
    if not r then return end
    if UndoStateService._installed_target == r then
        return
    end
    UndoStateService._installed_target = r

    local orig_SetProjExtState      = r.SetProjExtState
    local orig_GetProjExtState      = r.GetProjExtState
    local orig_Undo_BeginBlock2     = r.Undo_BeginBlock2
    local orig_Undo_BeginBlock      = r.Undo_BeginBlock
    local orig_Undo_EndBlock2       = r.Undo_EndBlock2
    local orig_Undo_EndBlock        = r.Undo_EndBlock
    local orig_Undo_OnStateChange2  = r.Undo_OnStateChange2
    local orig_Undo_OnStateChange   = r.Undo_OnStateChange
    local orig_Undo_OnStateChangeEx2= r.Undo_OnStateChangeEx2
    local orig_Undo_OnStateChangeEx = r.Undo_OnStateChangeEx

    UndoStateService._orig_SetProjExtState       = orig_SetProjExtState
    UndoStateService._orig_GetProjExtState       = orig_GetProjExtState
    UndoStateService._orig_Undo_BeginBlock2      = orig_Undo_BeginBlock2
    UndoStateService._orig_Undo_EndBlock2        = orig_Undo_EndBlock2
    UndoStateService._orig_Undo_OnStateChange2   = orig_Undo_OnStateChange2
    UndoStateService._orig_Undo_OnStateChangeEx2 = orig_Undo_OnStateChangeEx2

    if orig_SetProjExtState then
        r.SetProjExtState = function(proj, extname, key, val)
            if is_notator_score_key(extname, key) and not UndoStateService._restoring then
                if not UndoStateService._initialized then
                    UndoStateService.init_from_project()
                end
                UndoStateService.live_state[key] = tostring(val or "")
            end
            return orig_SetProjExtState(proj, extname, key, val)
        end
    end

    if orig_GetProjExtState then
        r.GetProjExtState = function(proj, extname, key)
            if is_notator_score_key(extname, key) and UndoStateService._initialized then
                local v = UndoStateService.live_state[key]
                if v ~= nil then
                    return (v ~= "" and 1 or 0), v
                end
            end
            return orig_GetProjExtState(proj, extname, key)
        end
    end

    if orig_Undo_BeginBlock2 then
        r.Undo_BeginBlock2 = function(proj)
            if UndoStateService.block_depth == 0 and not UndoStateService._restoring and UndoStateService._initialized then
                write_master_track_p_ext(r, UndoStateService.committed_state, UndoStateService._seq)
            end
            UndoStateService.block_depth = UndoStateService.block_depth + 1
            return orig_Undo_BeginBlock2(proj)
        end
    end

    if orig_Undo_BeginBlock then
        r.Undo_BeginBlock = function()
            if UndoStateService.block_depth == 0 and not UndoStateService._restoring and UndoStateService._initialized then
                write_master_track_p_ext(r, UndoStateService.committed_state, UndoStateService._seq)
            end
            UndoStateService.block_depth = UndoStateService.block_depth + 1
            return orig_Undo_BeginBlock()
        end
    end

    if orig_Undo_EndBlock2 then
        r.Undo_EndBlock2 = function(proj, desc, flags)
            if UndoStateService.block_depth > 0 then
                UndoStateService.block_depth = UndoStateService.block_depth - 1
            end
            if UndoStateService.block_depth == 0 and not UndoStateService._restoring and UndoStateService._initialized then
                local changed = maps_differ(UndoStateService.committed_state, UndoStateService.live_state)
                if changed then
                    UndoStateService._seq = (UndoStateService._seq or 0) + 1
                    write_master_track_p_ext(r, UndoStateService.live_state, UndoStateService._seq)
                end
                local eff_flags = changed and -1 or (flags or -1)
                local res = orig_Undo_EndBlock2(proj, desc, eff_flags)
                UndoStateService.record_undo_step(desc)
                return res
            end
            return orig_Undo_EndBlock2(proj, desc, flags or -1)
        end
    end

    if orig_Undo_EndBlock then
        r.Undo_EndBlock = function(desc, flags)
            if UndoStateService.block_depth > 0 then
                UndoStateService.block_depth = UndoStateService.block_depth - 1
            end
            if UndoStateService.block_depth == 0 and not UndoStateService._restoring and UndoStateService._initialized then
                local changed = maps_differ(UndoStateService.committed_state, UndoStateService.live_state)
                if changed then
                    UndoStateService._seq = (UndoStateService._seq or 0) + 1
                    write_master_track_p_ext(r, UndoStateService.live_state, UndoStateService._seq)
                end
                local eff_flags = changed and -1 or (flags or -1)
                local res = orig_Undo_EndBlock(desc, eff_flags)
                UndoStateService.record_undo_step(desc)
                return res
            end
            return orig_Undo_EndBlock(desc, flags or -1)
        end
    end

    if orig_Undo_OnStateChange2 then
        r.Undo_OnStateChange2 = function(proj, desc)
            if UndoStateService.block_depth == 0 and not UndoStateService._restoring and UndoStateService._initialized then
                if maps_differ(UndoStateService.committed_state, UndoStateService.live_state) then
                    UndoStateService._seq = (UndoStateService._seq or 0) + 1
                    write_master_track_p_ext(r, UndoStateService.live_state, UndoStateService._seq)
                end
                local res = orig_Undo_OnStateChange2(proj, desc)
                UndoStateService.record_undo_step(desc)
                return res
            end
            return orig_Undo_OnStateChange2(proj, desc)
        end
    end

    if orig_Undo_OnStateChange then
        r.Undo_OnStateChange = function(desc)
            if UndoStateService.block_depth == 0 and not UndoStateService._restoring and UndoStateService._initialized then
                if maps_differ(UndoStateService.committed_state, UndoStateService.live_state) then
                    UndoStateService._seq = (UndoStateService._seq or 0) + 1
                    write_master_track_p_ext(r, UndoStateService.live_state, UndoStateService._seq)
                end
                local res = orig_Undo_OnStateChange(desc)
                UndoStateService.record_undo_step(desc)
                return res
            end
            return orig_Undo_OnStateChange(desc)
        end
    end

    if orig_Undo_OnStateChangeEx2 then
        r.Undo_OnStateChangeEx2 = function(proj, desc, whichStates, trackparm)
            if UndoStateService.block_depth == 0 and not UndoStateService._restoring and UndoStateService._initialized then
                local changed = maps_differ(UndoStateService.committed_state, UndoStateService.live_state)
                if changed then
                    UndoStateService._seq = (UndoStateService._seq or 0) + 1
                    write_master_track_p_ext(r, UndoStateService.live_state, UndoStateService._seq)
                end
                local eff_states = changed and -1 or (whichStates or -1)
                local res = orig_Undo_OnStateChangeEx2(proj, desc, eff_states, trackparm or -1)
                UndoStateService.record_undo_step(desc)
                return res
            end
            return orig_Undo_OnStateChangeEx2(proj, desc, whichStates or -1, trackparm or -1)
        end
    end

    if orig_Undo_OnStateChangeEx then
        r.Undo_OnStateChangeEx = function(desc, whichStates, trackparm)
            if UndoStateService.block_depth == 0 and not UndoStateService._restoring and UndoStateService._initialized then
                local changed = maps_differ(UndoStateService.committed_state, UndoStateService.live_state)
                if changed then
                    UndoStateService._seq = (UndoStateService._seq or 0) + 1
                    write_master_track_p_ext(r, UndoStateService.live_state, UndoStateService._seq)
                end
                local eff_states = changed and -1 or (whichStates or -1)
                local res = orig_Undo_OnStateChangeEx(desc, eff_states, trackparm or -1)
                UndoStateService.record_undo_step(desc)
                return res
            end
            return orig_Undo_OnStateChangeEx(desc, whichStates or -1, trackparm or -1)
        end
    end
end

return UndoStateService

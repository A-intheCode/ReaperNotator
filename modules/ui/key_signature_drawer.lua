-- ==============================================================================
-- REAPER Native Notator - Module: KeySignatureDrawer
-- UI for Key Signatures (7♭ to 7♯) and Time Signatures per Item, Track, Project
-- ==============================================================================

local Constants = require("constants")

local KeySignatureDrawer = {
    search_filter = ""
}

-- 15 Key signatures ordered from -7 (7 flats) to +7 (7 sharps)
local KEY_SIGS_DATA = {
    { idx = -7, flats = 7, sharps = 0, major_en = "Cb Major", major_de = "Ces-Dur", minor_en = "Ab Minor", minor_de = "as-Moll", acc_str = "7 ♭" },
    { idx = -6, flats = 6, sharps = 0, major_en = "Gb Major", major_de = "Ges-Dur", minor_en = "Eb Minor", minor_de = "es-Moll", acc_str = "6 ♭" },
    { idx = -5, flats = 5, sharps = 0, major_en = "Db Major", major_de = "Des-Dur", minor_en = "Bb Minor", minor_de = "b-Moll",  acc_str = "5 ♭" },
    { idx = -4, flats = 4, sharps = 0, major_en = "Ab Major", major_de = "As-Dur",  minor_en = "F Minor",  minor_de = "f-Moll",  acc_str = "4 ♭" },
    { idx = -3, flats = 3, sharps = 0, major_en = "Eb Major", major_de = "Es-Dur",  minor_en = "C Minor",  minor_de = "c-Moll",  acc_str = "3 ♭" },
    { idx = -2, flats = 2, sharps = 0, major_en = "Bb Major", major_de = "B-Dur",   minor_en = "G Minor",  minor_de = "g-Moll",  acc_str = "2 ♭" },
    { idx = -1, flats = 1, sharps = 0, major_en = "F Major",  major_de = "F-Dur",   minor_en = "D Minor",  minor_de = "d-Moll",  acc_str = "1 ♭" },
    { idx =  0, flats = 0, sharps = 0, major_en = "C Major",  major_de = "C-Dur",   minor_en = "A Minor",  minor_de = "a-Moll",  acc_str = "♮" },
    { idx =  1, flats = 0, sharps = 1, major_en = "G Major",  major_de = "G-Dur",   minor_en = "E Minor",  minor_de = "e-Moll",  acc_str = "1 ♯" },
    { idx =  2, flats = 0, sharps = 2, major_en = "D Major",  major_de = "D-Dur",   minor_en = "B Minor",  minor_de = "h-Moll",  acc_str = "2 ♯" },
    { idx =  3, flats = 0, sharps = 3, major_en = "A Major",  major_de = "A-Dur",   minor_en = "F# Minor", minor_de = "fis-Moll",acc_str = "3 ♯" },
    { idx =  4, flats = 0, sharps = 4, major_en = "E Major",  major_de = "E-Dur",   minor_en = "C# Minor", minor_de = "cis-Moll",acc_str = "4 ♯" },
    { idx =  5, flats = 0, sharps = 5, major_en = "B Major",  major_de = "H-Dur",   minor_en = "G# Minor", minor_de = "gis-Moll",acc_str = "5 ♯" },
    { idx =  6, flats = 0, sharps = 6, major_en = "F# Major", major_de = "Fis-Dur", minor_en = "D# Minor", minor_de = "dis-Moll",acc_str = "6 ♯" },
    { idx =  7, flats = 0, sharps = 7, major_en = "C# Major", major_de = "Cis-Dur", minor_en = "A# Minor", minor_de = "ais-Moll",acc_str = "7 ♯" },
}

-- Treble clef standard accidental offsets from bottom line (E4)
local TREBLE_SHARP_OFFSETS = { 8, 5, 9, 6, 3, 7, 4 } -- F5, C5, G5, D5, A4, E5, B4
local TREBLE_FLAT_OFFSETS  = { 4, 7, 3, 6, 2, 5, 1 } -- B4, E5, A4, D5, G4, C5, F4

function KeySignatureDrawer.render(ctx, state, KeySignatureService, MidiService, width, height, child_border, sidebar_flags, font_music, font_main)
    if not state.show_key_signatures then return end

    if not reaper.ImGui_BeginChild(ctx, "KeySignatureDrawer", width, height, child_border, sidebar_flags) then
        return
    end

    -- Dynamic Service Resolution fallback
    if not KeySignatureService then
        KeySignatureService = package.loaded["services.key_signature_service"] or (pcall(require, "services.key_signature_service") and package.loaded["services.key_signature_service"] or nil)
    end
    if not MidiService then
        MidiService = package.loaded["services.midi_service"] or (pcall(require, "services.midi_service") and package.loaded["services.midi_service"] or nil)
    end

    -- ==================================================================
    -- 1. HEADER & CLOSE BUTTON
    -- ==================================================================
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "♯♭ KEY & TIME SIGNATURES")
    reaper.ImGui_SameLine(ctx, width - 28)
    if reaper.ImGui_SmallButton(ctx, "✕##CloseKeySigDrawer") then
        state.show_key_signatures = false
    end
    reaper.ImGui_Separator(ctx)

    -- ==================================================================
    -- 2. TARGET SCOPE RESOLUTION (Item, Track, Project)
    -- ==================================================================
    local sel_item = (state.selected_item and reaper.ValidatePtr(state.selected_item, "MediaItem*") and state.selected_item) or reaper.GetSelectedMediaItem(0, 0)
    local sel_take = sel_item and reaper.ValidatePtr(sel_item, "MediaItem*") and reaper.GetActiveTake(sel_item)
    if not sel_item and state.selected_notes then
        for _, sn in pairs(state.selected_notes) do
            if sn.item and reaper.ValidatePtr(sn.item, "MediaItem*") then
                sel_item = sn.item
                sel_take = sn.take or reaper.GetActiveTake(sel_item)
                state.selected_item = sel_item
                state.selected_take = sel_take
                break
            end
        end
    end
    local item_name = "None"
    local has_item = false

    if sel_item and reaper.ValidatePtr(sel_item, "MediaItem*") then
        has_item = true
        if sel_take and reaper.ValidatePtr(sel_take, "MediaItem_Take*") then
            local _, iname = reaper.GetSetMediaItemTakeInfo_String(sel_take, "P_NAME", "", false)
            item_name = (iname and iname ~= "") and iname or "Selected Item"
        else
            item_name = "Selected Item"
        end
    end

    -- Active Track Focus
    local it_trk = has_item and reaper.GetMediaItem_Track(sel_item)
    local cur_trk = (it_trk and reaper.ValidatePtr(it_trk, "MediaTrack*") and it_trk) or state.focused_track
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        local sel_trk = reaper.GetSelectedTrack(0, 0)
        if sel_trk and reaper.ValidatePtr(sel_trk, "MediaTrack*") then
            cur_trk = sel_trk
            state.focused_track = cur_trk
        end
    end
    if not cur_trk or not reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        if state.selected_notes then
            for _, sn in pairs(state.selected_notes) do
                if sn.track and reaper.ValidatePtr(sn.track, "MediaTrack*") then
                    cur_trk = sn.track
                    state.focused_track = cur_trk
                    break
                end
            end
        end
    end

    local trk_name = "None"
    local trk_guid = nil
    local has_track = false
    if cur_trk and reaper.ValidatePtr(cur_trk, "MediaTrack*") then
        has_track = true
        local _, name = reaper.GetTrackName(cur_trk)
        trk_name = (name and name ~= "") and name or ("Track " .. math.floor(reaper.GetMediaTrackInfo_Value(cur_trk, "IP_TRACKNUMBER")))
        trk_guid = reaper.GetTrackGUID(cur_trk)
    end

    -- Scope Switcher: Default to "item" if item selected, otherwise "track" or "project"
    if not state.key_sig_scope then
        state.key_sig_scope = has_item and "item" or (has_track and "track" or "project")
    end
    if has_item and state._keysig_last_has_item == false then
        state.key_sig_scope = "item"
    end
    state._keysig_last_has_item = has_item
    if not has_item and state.key_sig_scope == "item" then
        state.key_sig_scope = has_track and "track" or "project"
    end

    reaper.ImGui_TextColored(ctx, 0xAAAAAAFF, "Target Scope:")
    
    local function render_scope_btn(label, target_scope, is_enabled)
        local is_active = (state.key_sig_scope == target_scope)
        if not is_enabled then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x666666FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x1A1C22FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x1A1C22FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1A1C22FF)
            reaper.ImGui_Button(ctx, label, -1, 23)
            reaper.ImGui_PopStyleColor(ctx, 4)
            return false
        end

        local bg = is_active and 0x2980B9FF or 0x222630FF
        local bg_hov = is_active and 0x3498DBFF or 0x303644FF
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), bg)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), bg_hov)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x1B4F72FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), is_active and 0xFFFFFFFF or 0xBBBBBBFF)
        local clicked = reaper.ImGui_Button(ctx, label, -1, 23)
        reaper.ImGui_PopStyleColor(ctx, 4)
        if clicked then
            state.key_sig_scope = target_scope
        end
        return clicked
    end

    local short_item_name = #item_name > 18 and (item_name:sub(1, 16) .. "..") or item_name
    local short_trk_name  = #trk_name > 18 and (trk_name:sub(1, 16) .. "..") or trk_name

    render_scope_btn(string.format("📦 Selected Item: \"%s\"##ScopeItem", has_item and short_item_name or "None"), "item", has_item)
    render_scope_btn(string.format("🎵 Active Track: \"%s\"##ScopeTrk", has_track and short_trk_name or "None"), "track", has_track)
    render_scope_btn("🌐 Entire Project##ScopeProj", "project", true)

    reaper.ImGui_Spacing(ctx)

    -- ==================================================================
    -- 3. MODE SWITCHER: MAJOR (DUR) vs MINOR (MOLL)
    -- ==================================================================
    if not state.key_signature_mode then
        state.key_signature_mode = "major"
    end
    local is_major = (state.key_signature_mode ~= "minor")

    local avail_mode_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local half_w = math.floor((avail_mode_w - 6) / 2)

    -- Major Button
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), is_major and 0x3498DBFF or 0x222630FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), is_major and 0x2980B9FF or 0x303644FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), is_major and 0xFFFFFFFF or 0xAAAAAAFF)
    if reaper.ImGui_Button(ctx, "Major (Dur)##BtnMaj", half_w, 24) then
        state.key_signature_mode = "major"
    end
    reaper.ImGui_PopStyleColor(ctx, 3)

    reaper.ImGui_SameLine(ctx, 0, 6)

    -- Minor Button
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), (not is_major) and 0x3498DBFF or 0x222630FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), (not is_major) and 0x2980B9FF or 0x303644FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), (not is_major) and 0xFFFFFFFF or 0xAAAAAAFF)
    if reaper.ImGui_Button(ctx, "Minor (Moll)##BtnMin", half_w, 24) then
        state.key_signature_mode = "minor"
    end
    reaper.ImGui_PopStyleColor(ctx, 3)

    reaper.ImGui_Spacing(ctx)

    -- ==================================================================
    -- 4. RESOLVE CURRENTLY ACTIVE KEY SIGNATURE
    -- ==================================================================
    local cur_active_idx = 0
    local cur_active_mode = state.key_signature_mode or "major"

    if state.key_sig_scope == "item" and sel_item then
        if KeySignatureService and KeySignatureService.get_item_key_sig then
            local kinfo, im = KeySignatureService.get_item_key_sig(sel_item, sel_take)
            if type(kinfo) == "table" then
                cur_active_idx = kinfo.key_idx or kinfo.idx or 0
                cur_active_mode = kinfo.mode or cur_active_mode
            elseif type(kinfo) == "number" then
                cur_active_idx = kinfo
                if im then cur_active_mode = im end
            end
        elseif sel_take and reaper.ValidatePtr(sel_take, "MediaItem_Take*") then
            -- Fallback: check P_EXT
            local ok_pe, pe_val = reaper.GetSetMediaItemInfo_String(sel_item, "P_EXT:notator_key_sig", "", false)
            if ok_pe and pe_val and pe_val ~= "" then
                local k, m = pe_val:match("^(%-?%d+)|?(%a*)$")
                if k then
                    cur_active_idx = tonumber(k) or 0
                    if m and m ~= "" then cur_active_mode = m end
                end
            end
        end
    elseif state.key_sig_scope == "track" and trk_guid and state.track_key_signatures then
        local tk = state.track_key_signatures[trk_guid]
        if type(tk) == "table" then
            cur_active_idx = tk.key_idx or 0
            cur_active_mode = tk.mode or cur_active_mode
        elseif tk ~= nil then
            cur_active_idx = tonumber(tk) or 0
        end
    elseif state.key_sig_scope == "project" then
        cur_active_idx = state.key_signature or 0
        cur_active_mode = state.key_signature_mode or "major"
    end

    -- ==================================================================
    -- 5. SCROLLABLE GRID OF ALL 15 KEY SIGNATURES (7♭ to 7♯)
    -- ==================================================================
    local avail_grid_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local footer_reserved_h = 240
    local grid_h = math.max(140, height - footer_reserved_h - 130)

    if reaper.ImGui_BeginChild(ctx, "KeySigTilesGrid", avail_grid_w, grid_h, child_border, 0) then
        local card_w = math.max(160, reaper.ImGui_GetContentRegionAvail(ctx) - 2)
        local card_h = 58

        for _, sig in ipairs(KEY_SIGS_DATA) do
            local is_selected_key = (sig.idx == cur_active_idx and state.key_signature_mode == cur_active_mode)
            local p0_x, p0_y = reaper.ImGui_GetCursorScreenPos(ctx)
            local btn_id = "##key_card_" .. tostring(sig.idx)

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), is_selected_key and 0x2A3448FF or 0x1E2128FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x323B50FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF9F1C33)

            local clicked = reaper.ImGui_Button(ctx, btn_id, card_w, card_h)
            local is_hov = reaper.ImGui_IsItemHovered(ctx)

            reaper.ImGui_PopStyleColor(ctx, 3)

            -- Format names
            local name_main = is_major and sig.major_en or sig.minor_en
            local name_de   = is_major and sig.major_de or sig.minor_de
            local disp_title = string.format("%s (%s)", name_main, sig.acc_str)
            local full_title = string.format("%s  [%s]", disp_title, name_de)

            -- Click Handler: Apply Key Signature
            if clicked then
                local auto_respell = (state.key_sig_auto_respell ~= false)
                local mode = state.key_signature_mode or "major"

                if state.key_sig_scope == "item" then
                    if sel_item and reaper.ValidatePtr(sel_item, "MediaItem*") then
                        if KeySignatureService and KeySignatureService.set_item_key_sig then
                            KeySignatureService.set_item_key_sig(state, sel_item, sel_take, sig.idx, mode, auto_respell)
                        else
                            reaper.GetSetMediaItemInfo_String(sel_item, "P_EXT:notator_key_sig", string.format("%d|%s", sig.idx, mode), true)
                            if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
                        end

                        -- Immediately update in-memory active_tracks_data objects
                        if state.active_tracks_data then
                            for _, td in ipairs(state.active_tracks_data) do
                                if td.items then
                                    for _, it_obj in ipairs(td.items) do
                                        if it_obj.item == sel_item or (sel_take and it_obj.take == sel_take) then
                                            it_obj.key_sig = { idx = sig.idx, key_idx = sig.idx, mode = mode }
                                        end
                                    end
                                end
                            end
                        end
                        state.cached_measure_map = nil
                        state.cached_measure_map_sig = nil
                        local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
                        if MidiService and MidiService.invalidate_cache then
                            MidiService.invalidate_cache()
                        end
                        reaper.Undo_OnStateChange2(0, "Notator: Set Item Key Signature")
                        if reaper.UpdateArrange then reaper.UpdateArrange() end
                        state.status_msg = string.format("Item '%s': Key signature set to %s", item_name, disp_title)
                    else
                        state.status_msg = "Please select a MIDI Item to assign key signature!"
                    end
                elseif state.key_sig_scope == "track" then
                    if cur_trk and trk_guid then
                        if not state.track_key_signatures then state.track_key_signatures = {} end
                        state.track_key_signatures[trk_guid] = { key_idx = sig.idx, mode = mode }

                        local it_cnt = reaper.CountTrackMediaItems(cur_trk)
                        for i = 0, it_cnt - 1 do
                            local it = reaper.GetTrackMediaItem(cur_trk, i)
                            local tk = it and reaper.GetActiveTake(it)
                            if tk and reaper.TakeIsMIDI(tk) then
                                if KeySignatureService and KeySignatureService.set_item_key_sig then
                                    KeySignatureService.set_item_key_sig(state, it, tk, sig.idx, mode, auto_respell)
                                else
                                    reaper.GetSetMediaItemInfo_String(it, "P_EXT:notator_key_sig", string.format("%d|%s", sig.idx, mode), true)
                                end
                            end
                        end
                        if KeySignatureService and KeySignatureService.save then
                            KeySignatureService.save(state)
                        end
                        state:save_settings()
                        if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
                        state.status_msg = string.format("Track '%s': Key signature set to %s", trk_name, disp_title)
                    else
                        state.status_msg = "Please focus a track first to set key signature!"
                    end
                elseif state.key_sig_scope == "project" then
                    state.key_signature = sig.idx
                    state.key_signature_mode = mode
                    local num_trks = reaper.CountTracks(0)
                    for t = 0, num_trks - 1 do
                        local trk = reaper.GetTrack(0, t)
                        local it_cnt = reaper.CountTrackMediaItems(trk)
                        for i = 0, it_cnt - 1 do
                            local it = reaper.GetTrackMediaItem(trk, i)
                            local tk = it and reaper.GetActiveTake(it)
                            if tk and reaper.TakeIsMIDI(tk) then
                                if KeySignatureService and KeySignatureService.set_item_key_sig then
                                    KeySignatureService.set_item_key_sig(state, it, tk, sig.idx, mode, auto_respell)
                                else
                                    reaper.GetSetMediaItemInfo_String(it, "P_EXT:notator_key_sig", string.format("%d|%s", sig.idx, mode), true)
                                end
                            end
                        end
                    end
                    if KeySignatureService and KeySignatureService.save then
                        KeySignatureService.save(state)
                    end
                    state:save_settings()
                    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
                    state.status_msg = string.format("Project: Key signature set to %s", disp_title)
                end
            end

            -- DRAW TILE VECTOR GRAPHICS
            local dl = reaper.ImGui_GetWindowDrawList(ctx)
            local x0 = p0_x
            local y0 = p0_y
            local x1 = p0_x + card_w
            local y1 = p0_y + card_h

            -- Golden Border for active key, or subtle hover border
            local border_col = is_selected_key and 0xFF9F1CFF or (is_hov and 0xFF9F1CAA or 0x3A3E4DFF)
            local border_w   = is_selected_key and 2.2 or 1.0
            reaper.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, border_col, 4.0, 0, border_w)

            if is_selected_key then
                reaper.ImGui_DrawList_AddTriangleFilled(dl, x1 - 11, y0, x1, y0, x1, y0 + 11, 0xFF9F1CFF)
            end

            -- Mini 5-line staff
            local staff_w = card_w - 20
            local staff_x0 = x0 + 10
            local staff_x1 = staff_x0 + staff_w
            local staff_line_col = is_selected_key and 0xC0C8D6FF or (is_hov and 0x9BA2B2FF or 0x656A7AFF)
            local line_sp = 3.8
            local staff_bot = y0 + 26

            for l = 0, 4 do
                local ly = staff_bot - (l * line_sp)
                reaper.ImGui_DrawList_AddLine(dl, staff_x0, ly, staff_x1, ly, staff_line_col, 1.0)
            end

            -- Bravura G-Clef
            if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                local g_sz = 20
                local anchor_y = staff_bot - (1 * line_sp) -- G4
                local gy = anchor_y - (g_sz * 2.012)
                reaper.ImGui_DrawList_AddTextEx(dl, font_music, g_sz, staff_x0 + 2, gy, 0xFFFFFFFF, Constants.SMUFL.g_clef)

                -- Accidentals preview
                local acc_start_x = staff_x0 + 23
                local acc_spacing = 7.5
                local acc_sz = 15

                if sig.idx > 0 then
                    -- Sharps
                    for k = 1, sig.idx do
                        local off = TREBLE_SHARP_OFFSETS[k] or 4
                        local ay = staff_bot - (off * line_sp * 0.5)
                        local ax = acc_start_x + (k - 1) * acc_spacing
                        reaper.ImGui_DrawList_AddTextEx(dl, font_music, acc_sz, ax, ay - (acc_sz * 2.012), 0xFFFFFFFF, Constants.SMUFL.acc_sharp)
                    end
                elseif sig.idx < 0 then
                    -- Flats
                    for k = 1, -sig.idx do
                        local off = TREBLE_FLAT_OFFSETS[k] or 4
                        local ay = staff_bot - (off * line_sp * 0.5)
                        local ax = acc_start_x + (k - 1) * acc_spacing
                        reaper.ImGui_DrawList_AddTextEx(dl, font_music, acc_sz, ax, ay - (acc_sz * 2.012), 0xFFFFFFFF, Constants.SMUFL.acc_flat)
                    end
                end
            end

            -- Key Name Text below staff
            local text_col = is_selected_key and 0xFF9F1CFF or (is_hov and 0xFFFFFFFF or 0xDDDDDDFF)
            local text_y   = y0 + 36
            local text_x   = staff_x0 + 2

            if reaper.APIExists("ImGui_DrawList_AddTextEx") and font_main then
                reaper.ImGui_DrawList_AddTextEx(dl, font_main, 13.0, text_x, text_y, text_col, full_title)
            else
                reaper.ImGui_DrawList_AddText(dl, text_x, text_y, text_col, full_title)
            end

            reaper.ImGui_Spacing(ctx)
        end

        reaper.ImGui_EndChild(ctx)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)

    -- ==================================================================
    -- 6. TIME SIGNATURE SECTION
    -- ==================================================================
    reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "⏱ TIME SIGNATURE")

    state.key_sig_ts_num = state.key_sig_ts_num or 4
    state.key_sig_ts_den = state.key_sig_ts_den or 4

    local function apply_time_sig(num, denom)
        state.key_sig_ts_num = num
        state.key_sig_ts_den = denom
        local auto_respell = (state.key_sig_auto_respell ~= false)

        if state.key_sig_scope == "item" then
            if sel_item and reaper.ValidatePtr(sel_item, "MediaItem*") then
                if KeySignatureService and KeySignatureService.set_item_time_sig then
                    KeySignatureService.set_item_time_sig(state, sel_item, sel_take, num, denom)
                else
                    reaper.GetSetMediaItemInfo_String(sel_item, "P_EXT:notator_time_sig", string.format("%d|%d", num, denom), true)
                    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
                end

                -- Immediately update in-memory active_tracks_data objects
                if state.active_tracks_data then
                    for _, td in ipairs(state.active_tracks_data) do
                        if td.items then
                            for _, it_obj in ipairs(td.items) do
                                if it_obj.item == sel_item or (sel_take and it_obj.take == sel_take) then
                                    it_obj.time_sig = { num = num, denom = denom }
                                end
                            end
                        end
                    end
                end
                state.cached_measure_map = nil
                state.cached_measure_map_sig = nil
                local MidiService = package.loaded["services.midi_service"] or require("services.midi_service")
                if MidiService and MidiService.invalidate_cache then
                    MidiService.invalidate_cache()
                end
                reaper.Undo_OnStateChange2(0, "Notator: Set Item Time Signature")
                if reaper.UpdateArrange then reaper.UpdateArrange() end
                state.status_msg = string.format("Item '%s': Time signature set to %d/%d", item_name, num, denom)
            else
                state.status_msg = "Please select a MIDI Item to assign time signature!"
            end
        elseif state.key_sig_scope == "track" then
            if cur_trk then
                local it_cnt = reaper.CountTrackMediaItems(cur_trk)
                for i = 0, it_cnt - 1 do
                    local it = reaper.GetTrackMediaItem(cur_trk, i)
                    local tk = it and reaper.GetActiveTake(it)
                    if tk and reaper.TakeIsMIDI(tk) then
                        if KeySignatureService and KeySignatureService.set_item_time_sig then
                            KeySignatureService.set_item_time_sig(state, it, tk, num, denom)
                        else
                            reaper.GetSetMediaItemInfo_String(it, "P_EXT:notator_time_sig", string.format("%d|%d", num, denom), true)
                        end
                    end
                end
                if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
                state.status_msg = string.format("Track '%s': Time signature set to %d/%d", trk_name, num, denom)
            end
        elseif state.key_sig_scope == "project" then
            local cur_time = reaper.GetCursorPosition()
            reaper.SetTempoTimeSigMarker(0, -1, cur_time, -1, -1, -1, num, denom, false)
            reaper.UpdateTimeline()

            local num_trks = reaper.CountTracks(0)
            for t = 0, num_trks - 1 do
                local trk = reaper.GetTrack(0, t)
                local it_cnt = reaper.CountTrackMediaItems(trk)
                for i = 0, it_cnt - 1 do
                    local it = reaper.GetTrackMediaItem(trk, i)
                    local tk = it and reaper.GetActiveTake(it)
                    if tk and reaper.TakeIsMIDI(tk) then
                        if KeySignatureService and KeySignatureService.set_item_time_sig then
                            KeySignatureService.set_item_time_sig(state, it, tk, num, denom)
                        else
                            reaper.GetSetMediaItemInfo_String(it, "P_EXT:notator_time_sig", string.format("%d|%d", num, denom), true)
                        end
                    end
                end
            end
            if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
            state.status_msg = string.format("Project: Time signature set to %d/%d", num, denom)
        end
    end

    -- Quick Presets Row 1: [4/4], [3/4], [2/4], [6/8]
    local avail_ts_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local q_w4 = math.floor((avail_ts_w - 18) / 4)
    local q_w3 = math.floor((avail_ts_w - 12) / 3)

    if reaper.ImGui_Button(ctx, "4/4##TS_4_4", q_w4, 23) then apply_time_sig(4, 4) end
    reaper.ImGui_SameLine(ctx, 0, 6)
    if reaper.ImGui_Button(ctx, "3/4##TS_3_4", q_w4, 23) then apply_time_sig(3, 4) end
    reaper.ImGui_SameLine(ctx, 0, 6)
    if reaper.ImGui_Button(ctx, "2/4##TS_2_4", q_w4, 23) then apply_time_sig(2, 4) end
    reaper.ImGui_SameLine(ctx, 0, 6)
    if reaper.ImGui_Button(ctx, "6/8##TS_6_8", q_w4, 23) then apply_time_sig(6, 8) end

    -- Quick Presets Row 2: [12/8], [5/4], [7/8]
    if reaper.ImGui_Button(ctx, "12/8##TS_12_8", q_w3, 23) then apply_time_sig(12, 8) end
    reaper.ImGui_SameLine(ctx, 0, 6)
    if reaper.ImGui_Button(ctx, "5/4##TS_5_4", q_w3, 23) then apply_time_sig(5, 4) end
    reaper.ImGui_SameLine(ctx, 0, 6)
    if reaper.ImGui_Button(ctx, "7/8##TS_7_8", q_w3, 23) then apply_time_sig(7, 8) end

    reaper.ImGui_Spacing(ctx)

    -- Custom Stepper: Numerator / Denominator
    reaper.ImGui_Text(ctx, string.format("Custom: %d / %d", state.key_sig_ts_num, state.key_sig_ts_den))
    reaper.ImGui_SameLine(ctx, 0, 8)
    if reaper.ImGui_SmallButton(ctx, "-##DecNum") then
        state.key_sig_ts_num = math.max(1, state.key_sig_ts_num - 1)
    end
    reaper.ImGui_SameLine(ctx, 0, 2)
    if reaper.ImGui_SmallButton(ctx, "+##IncNum") then
        state.key_sig_ts_num = math.min(32, state.key_sig_ts_num + 1)
    end
    reaper.ImGui_SameLine(ctx, 0, 8)
    reaper.ImGui_Text(ctx, "Denom:")
    reaper.ImGui_SameLine(ctx, 0, 4)
    if reaper.ImGui_SmallButton(ctx, "/2##Den2") then state.key_sig_ts_den = 2 end
    reaper.ImGui_SameLine(ctx, 0, 2)
    if reaper.ImGui_SmallButton(ctx, "/4##Den4") then state.key_sig_ts_den = 4 end
    reaper.ImGui_SameLine(ctx, 0, 2)
    if reaper.ImGui_SmallButton(ctx, "/8##Den8") then state.key_sig_ts_den = 8 end
    reaper.ImGui_SameLine(ctx, 0, 2)
    if reaper.ImGui_SmallButton(ctx, "/16##Den16") then state.key_sig_ts_den = 16 end

    if reaper.ImGui_Button(ctx, string.format("Apply %d/%d to Target##ApplyCustomTS", state.key_sig_ts_num, state.key_sig_ts_den), -1, 23) then
        apply_time_sig(state.key_sig_ts_num, state.key_sig_ts_den)
    end

    reaper.ImGui_Spacing(ctx)
    reaper.ImGui_Separator(ctx)

    -- ==================================================================
    -- 7. NOTE ACTIONS SECTION
    -- ==================================================================
    if state.key_sig_auto_respell == nil then
        state.key_sig_auto_respell = true
    end

    local chk_changed, chk_val = reaper.ImGui_Checkbox(ctx, "Respell notes enharmonically##KeyRespell", state.key_sig_auto_respell)
    if chk_changed then
        state.key_sig_auto_respell = chk_val
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Automatically respells accidentals (e.g. F# vs Gb) to adhere to the active key signature.")
    end

    if reaper.ImGui_Button(ctx, "🎹 Snap / Transpose Notes to Key##SnapKey", -1, 26) then
        local mode = state.key_signature_mode or "major"
        if sel_take and reaper.ValidatePtr(sel_take, "MediaItem_Take*") then
            if KeySignatureService and KeySignatureService.snap_item_notes_to_key then
                local cnt = KeySignatureService.snap_item_notes_to_key(state, sel_take, cur_active_idx, mode)
                state.status_msg = string.format("Snapped notes to key (%s notes adjusted)", tostring(cnt or 0))
            else
                state.status_msg = "KeySignatureService snap function not available."
            end
        else
            state.status_msg = "Please select a MIDI Item to snap its notes to key."
        end
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Transposes out-of-scale notes to the nearest valid scale degrees of the chosen key signature.")
    end

    reaper.ImGui_EndChild(ctx)
end

return KeySignatureDrawer

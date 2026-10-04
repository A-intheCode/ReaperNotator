-- ==============================================================================
-- REAPER Native Notator - Module: ScoreCanvas
-- Renders the entire score canvas (DrawList): tracks, notes, beams, items, dynamics
-- ==============================================================================

local Constants = require("constants")
local SMUFL = Constants.SMUFL
local Engraver = require("rendering.engraver")
local ReaticulateParser = require("services.reaticulate_parser")
local OctaveService = require("services.octave_service")
local AudioPreview = require("services.audio_preview")
local FontManager = require("rendering.font_manager")
local RepeatService = require("services.repeat_service")
local ok_ccm, res_ccm = pcall(require, "rendering.canvas_context_menus")
if not ok_ccm then
    ok_ccm, res_ccm = pcall(require, "modules.rendering.canvas_context_menus")
end
local CanvasContextMenus = ok_ccm and res_ccm or nil
if not ok_ccm then
    reaper.ShowConsoleMsg("[ScoreCanvas] ERROR loading CanvasContextMenus: " .. tostring(res_ccm) .. "\n")
end


local has_cpr, CanvasPedalRenderer = pcall(require, "rendering.canvas_pedal_renderer")
if not has_cpr or not CanvasPedalRenderer then
    has_cpr, CanvasPedalRenderer = pcall(require, "modules.rendering.canvas_pedal_renderer")
end

local has_cd, CanvasDecorations = pcall(require, "rendering.canvas_decorations")
if not has_cd or not CanvasDecorations then
    has_cd, CanvasDecorations = pcall(require, "modules.rendering.canvas_decorations")
end

local has_kss, KeySignatureService = pcall(require, "modules.services.key_signature_service")
if not has_kss or not KeySignatureService then
    has_kss, KeySignatureService = pcall(require, "services.key_signature_service")
end

local HairpinService = require("services.hairpin_service")
local DynamicTextService = require("services.dynamic_text_service")
local TextItemService = require("services.text_item_service")
local PatternService = require("services.pattern_service")
local SelectionService = require("services.selection_service")
local StateModule = require("state")

local function resolve_effective_key(state, track, item, qn)
    if has_kss and KeySignatureService and KeySignatureService.resolve_effective_key then
        local res = KeySignatureService.resolve_effective_key(state, track, item, qn)
        if type(res) == "table" then
            return res.key_idx or res.idx or 0, res.mode or "major"
        elseif type(res) == "number" then
            return res, "major"
        end
    end
    if item then
        if item.key_sig ~= nil then
            if type(item.key_sig) == "table" then
                return item.key_sig.key_idx or item.key_sig.idx or 0, item.key_sig.mode or item.key_sig_mode or "major"
            else
                return item.key_sig, item.key_sig_mode or "major"
            end
        end
        local real_it = (item.item and reaper.ValidatePtr(item.item, "MediaItem*") and item.item)
            or (type(item) == "userdata" and reaper.ValidatePtr(item, "MediaItem*") and item)
        if real_it then
            local ok, str = reaper.GetSetMediaItemInfo_String(real_it, "P_EXT:notator_key_sig", "", false)
            if ok and str and str ~= "" then
                local idx, mode = str:match("([^|]+)|?([^|]*)")
                if idx then return tonumber(idx) or 0, (mode ~= "" and mode or "major") end
            end
        end
    end
    if track and state and state.track_key_signatures then
        local guid = type(track) == "userdata" and reaper.ValidatePtr(track, "MediaTrack*") and reaper.GetTrackGUID(track) or nil
        if guid and state.track_key_signatures[guid] then
            local entry = state.track_key_signatures[guid]
            if type(entry) == "table" then
                return entry.idx or 0, entry.mode or "major"
            elseif type(entry) == "number" then
                return entry, "major"
            end
        end
    end
    return (state and state.key_signature) or 0, (state and state.key_signature_mode) or "major"
end

local function resolve_effective_time_sig(state, track, item, qn)
    if has_kss and KeySignatureService and KeySignatureService.resolve_effective_time_sig then
        local res = KeySignatureService.resolve_effective_time_sig(state, track, item, qn)
        if type(res) == "table" then
            return res.num or 4, res.denom or 4
        elseif type(res) == "number" then
            return res, 4
        end
    end
    if item then
        if item.time_sig and item.time_sig.num and item.time_sig.denom then
            return item.time_sig.num, item.time_sig.denom
        end
        if item.item and reaper.ValidatePtr(item.item, "MediaItem*") then
            local ok, str = reaper.GetSetMediaItemInfo_String(item.item, "P_EXT:notator_time_sig", "", false)
            if ok and str and str ~= "" then
                local num, den = str:match("([^|]+)|([^|]+)")
                if num and den then return tonumber(num) or 4, tonumber(den) or 4 end
            end
        end
    end
    return 4, 4
end

local all_reaticulate_banks = nil

local ScoreCanvas = {}

local function reaper_color_to_rgba(reaper_col, alpha)
    local alpha = alpha or 0xFF
    if not reaper_col or reaper_col == 0 then
        return (0x88888800 | alpha) -- Light gray instead of dark gray for visibility
    end
    local r = reaper_col & 0xFF
    local g = (reaper_col >> 8) & 0xFF
    local b = (reaper_col >> 16) & 0xFF
    return (r << 24) | (g << 16) | (b << 8) | alpha
end


local function get_dynamic_glyph_and_width(label, dyn_font_sz)
    local clean_lbl = (label or ""):lower():gsub("%s+", "")
    local glyph = SMUFL["dyn_" .. clean_lbl]
    local glyph_w_units = Constants.DYN_GLYPH_WIDTHS and Constants.DYN_GLYPH_WIDTHS[clean_lbl]
    
    if not glyph and clean_lbl:match("^[pmfzsrn]+$") then
        local composed = ""
        local w_sum = 0
        local char_map = {
            p = SMUFL.dyn_p,
            m = SMUFL.dyn_m,
            f = SMUFL.dyn_f,
            z = utf8.char(0xE525),
            s = utf8.char(0xE524),
            r = utf8.char(0xE523),
            n = SMUFL.dyn_n
        }
        for c in clean_lbl:gmatch(".") do
            if char_map[c] then
                composed = composed .. char_map[c]
                w_sum = w_sum + (Constants.DYN_GLYPH_WIDTHS and Constants.DYN_GLYPH_WIDTHS[c] or 380)
            end
        end
        if #composed > 0 then
            glyph = composed
            if not glyph_w_units then glyph_w_units = w_sum end
        end
    end

    if not glyph_w_units then
        glyph_w_units = #clean_lbl * 380
    end
    local dyn_w = (glyph_w_units / 1000) * dyn_font_sz
    return glyph, dyn_w, clean_lbl
end

local function draw_smufl_clef(draw_list, x, bot_y, anchor_line, line_spacing, s, col, font_music, glyph)
    local font_sz = math.floor(40 * s + 0.5)
    if font_music and glyph and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local anchor_y = bot_y - ((anchor_line - 1) * line_spacing)
        local pos_y = anchor_y - (font_sz * 2.012)
        local pos_x = x - 9.0 * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, glyph)
        return true
    end
    return false
end

local function draw_treble_clef(draw_list, x, g4_y, s, col, font_music)
    local font_sz = math.floor(40 * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local pos_y = g4_y - (font_sz * 2.012)
        local pos_x = x - 9.0 * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, SMUFL.g_clef)
        return
    end
    reaper.ImGui_DrawList_AddCircle(draw_list, x + 3*s, g4_y, 7*s, col, 0, 2.2*s)
    reaper.ImGui_DrawList_AddLine(draw_list, x + 3*s, g4_y - 24*s, x + 3*s, g4_y + 16*s, col, 2.5*s)
end

local function draw_time_signature(draw_list, x, bot_y, line_spacing, s, col, num, denom, font_music, font_main)
    local col_ts = col or 0x1A1A1AFF
    local font_sz = math.floor(40 * s + 0.5)
    
    if type(num) == "table" then
        denom = num.denom or num.den or denom
        num = num.num or 4
    end
    if type(denom) == "table" then
        denom = denom.denom or denom.den or 4
    end

    local num_str = tostring(num or 4)
    local denom_str = tostring(denom or 4)
    
    local num_glyph = SMUFL["timeSig" .. num_str]
    local denom_glyph = SMUFL["timeSig" .. denom_str]
    
    if font_music and num_glyph and denom_glyph and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local y_num = (bot_y - 2 * line_spacing) - (font_sz * 2.012)
        local y_denom = bot_y - (font_sz * 2.012)
        local pos_x = x - 5.0 * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, y_num, col_ts, num_glyph)
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, y_denom, col_ts, denom_glyph)
    else
        local pos_x = x - 4.0 * s
        local y_num = bot_y - 3.4 * line_spacing
        local y_denom = bot_y - 1.8 * line_spacing
        reaper.ImGui_DrawList_AddText(draw_list, pos_x, y_num, col_ts, num_str)
        reaper.ImGui_DrawList_AddText(draw_list, pos_x, y_denom, col_ts, denom_str)
    end
end

local function draw_bass_clef(draw_list, x, f3_y, s, col, font_music)
    local font_sz = math.floor(40 * s + 0.5)
    if font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
        local pos_y = f3_y - (font_sz * 2.012)
        local pos_x = x - 9.0 * s
        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, font_sz, pos_x, pos_y, col, SMUFL.f_clef)
        return
    end
    local y_line4 = f3_y
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, x + 5*s, y_line4, 3.5*s, col)
    reaper.ImGui_DrawList_AddBezierCubic(draw_list, x + 5*s, y_line4, x + 18*s, y_line4 - 12*s, x + 18*s, y_line4 + 8*s, x + 4*s, y_line4 + 18*s, col, 2.5*s)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, x + 20*s, y_line4 - 5*s, 2.2*s, col)
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, x + 20*s, y_line4 + 5*s, 2.2*s, col)
end

local function get_track_clef(guid, track_notes, track_name, state)
    return Engraver.get_track_clef(guid, track_name, track_notes, state)
end


local function sync_arrange_selection(state, project_tracks)
    local cur_sel_item = reaper.GetSelectedMediaItem(0, 0)
    local cur_sel_trk = reaper.GetSelectedTrack(0, 0)
    
    if cur_sel_item ~= state.selected_item or cur_sel_item ~= state.last_reaper_sel_item or cur_sel_trk ~= state.last_reaper_sel_track then
        local item_changed = (cur_sel_item ~= state.selected_item)
        state.last_reaper_sel_item = cur_sel_item
        state.last_reaper_sel_track = cur_sel_trk
        
        local clicked_trk = nil
        if cur_sel_item and reaper.ValidatePtr(cur_sel_item, "MediaItem*") then
            clicked_trk = reaper.GetMediaItem_Track(cur_sel_item)
            local take = reaper.GetActiveTake(cur_sel_item)
            state.selected_item = cur_sel_item
            state.selected_take = take
            if item_changed then
                state.jump_to_item = cur_sel_item
            end
        else
            state.selected_item = nil
            state.selected_take = nil
            if cur_sel_trk and reaper.ValidatePtr(cur_sel_trk, "MediaTrack*") then
                clicked_trk = cur_sel_trk
            end
        end

        local sel_trk_count = 0
        for _ in pairs(state.selected_tracks) do sel_trk_count = sel_trk_count + 1 end
        
        local reaper_sel_trk_cnt = reaper.CountSelectedTracks(0)
        local reaper_sel_item_cnt = reaper.CountSelectedMediaItems(0)
        
        if reaper_sel_trk_cnt > 1 then
            if sel_trk_count <= 1 then
                state.selected_tracks = {}
            end
            for i = 0, reaper_sel_trk_cnt - 1 do
                local st = reaper.GetSelectedTrack(0, i)
                if st then state.selected_tracks[reaper.GetTrackGUID(st)] = true end
            end
            if clicked_trk then state.focused_track = clicked_trk end
        elseif reaper_sel_item_cnt > 1 then
            if sel_trk_count <= 1 then
                state.selected_tracks = {}
            end
            for i = 0, reaper_sel_item_cnt - 1 do
                local mi = reaper.GetSelectedMediaItem(0, i)
                if mi then
                    local mt = reaper.GetMediaItem_Track(mi)
                    if mt then state.selected_tracks[reaper.GetTrackGUID(mt)] = true end
                end
            end
            if clicked_trk then state.focused_track = clicked_trk end
        else
            if clicked_trk then
                local cguid = reaper.GetTrackGUID(clicked_trk)
                if sel_trk_count <= 1 then
                    state.selected_tracks = { [cguid] = true }
                else
                    state.selected_tracks[cguid] = true
                end
                state.focused_track = clicked_trk
            elseif project_tracks and #project_tracks > 0 and sel_trk_count == 0 then
                state.selected_tracks[project_tracks[1].guid] = true
                state.focused_track = project_tracks[1].track
            end
        end
    end
    
    local has_any_sel = false
    if project_tracks then
        for _, t in ipairs(project_tracks) do
            if state.selected_tracks[t.guid] then has_any_sel = true break end
        end
        if not has_any_sel and #project_tracks > 0 then
            state.selected_tracks[project_tracks[1].guid] = true
            state.focused_track = project_tracks[1].track
        end
    end
end

function ScoreCanvas.render(ctx, state, fonts, project_tracks, midi_service)
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    if reaper.APIExists("ImGui_DrawList_GetFlags") and reaper.APIExists("ImGui_DrawList_SetFlags") then
        local dl_flags = reaper.ImGui_DrawList_GetFlags(draw_list)
        if reaper.APIExists("ImGui_DrawListFlags_AntiAliasedLines") then
            dl_flags = dl_flags | reaper.ImGui_DrawListFlags_AntiAliasedLines()
        end
        if reaper.APIExists("ImGui_DrawListFlags_AntiAliasedFill") then
            dl_flags = dl_flags | reaper.ImGui_DrawListFlags_AntiAliasedFill()
        end
        reaper.ImGui_DrawList_SetFlags(draw_list, dl_flags)
    end
    local canvas_p0_x, canvas_p0_y = reaper.ImGui_GetCursorScreenPos(ctx)
    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)
    local s = state.zoom
    if FontManager and (not FontManager._fonts_ready or not FontManager.font_bold or not FontManager.font_italic or not FontManager.font_bold_italic) then
        FontManager.init(ctx, state)
    end
    local font_music = (FontManager and FontManager.font_music) or (fonts and fonts.font_music)
    local font_main = (FontManager and FontManager.font_main) or (fonts and fonts.font_main)
    local font_big = (FontManager and FontManager.font_big) or (fonts and fonts.font_big)
    local font_bold = (FontManager and FontManager.font_bold) or (fonts and fonts.font_bold)
    local font_italic = (FontManager and FontManager.font_italic) or (fonts and fonts.font_italic)
    local font_bold_italic = (FontManager and FontManager.font_bold_italic) or (fonts and fonts.font_bold_italic)
    
    local is_ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl())
    local is_shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
    local is_shift_or_ctrl = is_ctrl or is_shift
    
    -- Synchronize with REAPER arrange selection (immediate switching on clicks in arrange view)
    sync_arrange_selection(state, project_tracks)
    
    local active_tracks_data = {}
    local max_proj_qn = 16 * 4.0
    local cur_time = reaper.GetCursorPosition()
    local play_time = reaper.GetPlayPosition()
    local is_playing = (reaper.GetPlayState() == 1)
    local time_pos = is_playing and play_time or cur_time
    
    local timesig_num, timesig_denom, bpm = reaper.TimeMap_GetTimeSigAtTime(0, time_pos)
    timesig_num = (timesig_num and timesig_num > 0) and timesig_num or 4
    timesig_denom = (timesig_denom and timesig_denom > 0) and timesig_denom or 4
    local qn_per_measure = timesig_num * (4 / timesig_denom)
    local bpi = qn_per_measure
    local proj_change_cnt = (reaper.GetProjectStateChangeCount and reaper.GetProjectStateChangeCount(0)) or 0
    
    for _, t in ipairs(project_tracks) do
        if state.selected_tracks[t.guid] then
            local items, trk_notes, dyns, arts, trk_max_qn, r_cache = midi_service.get_track_items_and_notes(t.track)
            if trk_max_qn and trk_max_qn > max_proj_qn then
                max_proj_qn = trk_max_qn
            else
                for _, it in ipairs(items) do
                    if it.end_qn > max_proj_qn then max_proj_qn = it.end_qn end
                end
            end
            table.insert(active_tracks_data, {
                track = t.track,
                guid = t.guid,
                idx = t.idx,
                name = t.name,
                col = t.col,
                items = items,
                notes = trk_notes,
                dynamics = dyns, articulations = arts,
                rests_cache = r_cache
            })
        end
    end
    
    if #active_tracks_data == 0 then
        table.insert(active_tracks_data, {
            track = nil, guid = "default", idx = 1, name = "MIDI Track", col = 0, items = {}, notes = {}, dynamics = {}
        })
    end
    
    local total_measures = math.max(16, math.ceil(max_proj_qn / qn_per_measure) + 2)
    local measure_w, pad_left, pad_right, usable_w = Engraver.get_measure_layout(s, qn_per_measure)
    
    -- Dynamically calculate optimal track header width and key signature width based on track names (cached)
    local hdr_cache_key = string.format("%d_%.3f_%d", #active_tracks_data, s, proj_change_cnt)
    local max_hdr_text_w = 85 * s
    local max_key_sig_w = 0
    if state._cached_hdr_metrics and state._cached_hdr_metrics.key == hdr_cache_key then
        max_hdr_text_w = state._cached_hdr_metrics.max_hdr_text_w
        max_key_sig_w = state._cached_hdr_metrics.max_key_sig_w
    else
        for _, tdata in ipairs(active_tracks_data) do
            local trk_lbl = string.format("[%d] %s", tdata.idx, tdata.name or "Track")
            local tw = FontManager.calc_text_size(ctx, trk_lbl)
            if tw > max_hdr_text_w then max_hdr_text_w = tw end
            
            local trk_first_item = (tdata.items and tdata.items[1])
            local item_at_start = (trk_first_item and (trk_first_item.start_qn or 0) <= 0.1) and trk_first_item or nil
            local k_idx = resolve_effective_key(state, tdata.track, item_at_start, 0)
            local kw = Engraver.get_key_signature_width(k_idx, s)
            if kw > max_key_sig_w then max_key_sig_w = kw end
        end
        local proj_k = (state and state.key_signature) or 0
        local proj_kw = Engraver.get_key_signature_width(proj_k, s)
        if proj_kw > max_key_sig_w then max_key_sig_w = proj_kw end
        
        state._cached_hdr_metrics = {
            key = hdr_cache_key,
            max_hdr_text_w = max_hdr_text_w,
            max_key_sig_w = max_key_sig_w
        }
    end
    -- At least 130 * s, at most 190 * s, so that "Double Bass" and long names fit completely
    local hdr_w = math.max(130 * s, math.min(190 * s, max_hdr_text_w + 24 * s))
    local hdr_x0 = canvas_p0_x + 6 * s
    local hdr_x1 = hdr_x0 + hdr_w
    local system_start_x = hdr_x1 + 14 * s

    local margin_left = system_start_x + 68 * s + max_key_sig_w
    
    -- Dynamic measure width calculation (cached across frames)
    local mmap_sig = string.format("%.3f_%d_%.3f_%.2f_%d_%d_%d_%s",
        s, total_measures, qn_per_measure, margin_left, proj_change_cnt, #active_tracks_data,
        (state and state.key_signature) or 0, tostring(state and state.display_quantize_grid))
    local measure_map = nil
    if state.cached_measure_map and state.cached_measure_map_sig == mmap_sig then
        measure_map = state.cached_measure_map
    else
        measure_map = Engraver.build_measure_map(active_tracks_data, total_measures, qn_per_measure, margin_left, s, state)
        state.cached_measure_map = measure_map
        state.cached_measure_map_sig = mmap_sig
    end
    state.measure_map = measure_map
    local staff_end_x = (measure_map.starts[total_measures] or (margin_left + total_measures * measure_w)) + 40 * s
    
    local chord_lane_h = (state.show_chord_lane ~= false) and (42 * s) or 0
    local rehearsal_lane_h = (state.show_rehearsal_lane ~= false) and (28 * s) or 0
    local total_score_h = 50 * s + chord_lane_h + rehearsal_lane_h
    for _, tdata in ipairs(active_tracks_data) do
        local trk_clef = get_track_clef(tdata.guid, tdata.notes, tdata.name, state)
        tdata.clef = trk_clef
        tdata.is_grand = (trk_clef == "grand")
        tdata.is_harp  = (trk_clef == "harp_3staff")
        local user_spacing = state.track_spacing or 70.0
        
        -- Base staff height depending on clef type down to the bottom staff line
        local staff_h = tdata.is_harp and 224 or (tdata.is_grand and 148 or 80)
        
        -- Total height of the track lane: staff + track spacing (completely independent of item offsets)
        tdata.band_h = (staff_h + user_spacing) * s
        total_score_h = total_score_h + tdata.band_h
    end
    
    local canvas_total_w = math.max(avail_w, staff_end_x - canvas_p0_x + 60 * s)
    local canvas_total_h = math.max(avail_h, total_score_h)
    
    local btn_flags = 0
    if reaper.APIExists("ImGui_ButtonFlags_MouseButtonLeft") then
        btn_flags = reaper.ImGui_ButtonFlags_MouseButtonLeft()
    end
    if reaper.APIExists("ImGui_ButtonFlags_MouseButtonRight") then
        btn_flags = btn_flags | reaper.ImGui_ButtonFlags_MouseButtonRight()
    end
    
    reaper.ImGui_InvisibleButton(ctx, "ScoreCanvasHitbox", canvas_total_w, canvas_total_h, btn_flags)
    
    -- Auto-scroll and item jump logic (MUST be placed here after declaring window size via InvisibleButton, otherwise SetScrollX is cleared to 0)
    if state.jump_to_item then
        -- 1. Jump to a newly selected media item (highest priority on click)
        if reaper.ValidatePtr(state.jump_to_item, "MediaItem*") then
            local item_pos = reaper.GetMediaItemInfo_Value(state.jump_to_item, "D_POSITION")
            local item_qn = reaper.TimeMap2_timeToQN(0, item_pos)
            local target_x = Engraver.cursor_qn_to_canvas_x(item_qn, margin_left, s, qn_per_measure, measure_map)
            reaper.ImGui_SetScrollX(ctx, math.max(0, target_x - canvas_p0_x - (avail_w * 0.25)))
        end
        state.jump_to_item = nil
    elseif state.auto_scroll then
        -- 2. Automatic scrolling during playback
        if is_playing then
            local target_x = Engraver.cursor_qn_to_canvas_x(reaper.TimeMap2_timeToQN(0, play_time), margin_left, s, qn_per_measure, measure_map)
            reaper.ImGui_SetScrollX(ctx, math.max(0, target_x - canvas_p0_x - (avail_w * 0.5)))
        -- 3. Automatic scrolling in stopped state (e.g. edit cursor follows click)
        else
            local empty_click = reaper.ImGui_IsItemHovered(ctx) and reaper.ImGui_IsMouseClicked(ctx, 0)
                                and not state.hovered_note and not state.hovered_dynamic 
                                and not state.hovered_articulation and not state.hovered_item_edge
                                and not state.hovered_tempo_marker and not state.hovered_octave_line
                                and not state.hovered_chord_item

            if not empty_click and not reaper.ImGui_IsMouseClicked(ctx, 0) then
                local target_x = Engraver.cursor_qn_to_canvas_x(reaper.TimeMap2_timeToQN(0, cur_time), margin_left, s, qn_per_measure, measure_map)
                reaper.ImGui_SetScrollX(ctx, math.max(0, target_x - canvas_p0_x - (avail_w * 0.5)))
            end
        end
    end

    
    -- ======================================================================
    -- VIEWPORT CULLING CALCULATION (Frustum Culling)
    -- ======================================================================
    local win_x0, win_y0 = reaper.ImGui_GetWindowPos(ctx)
    local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
    local buf_x = 180.0 * s
    local buf_y = 60.0 * s
    local cull_min_x = win_x0 - buf_x
    local cull_max_x = win_x0 + win_w + buf_x
    local cull_min_y = win_y0 - buf_y
    local cull_max_y = win_y0 + win_h + buf_y
    
    local vis_min_qn = math.max(0, Engraver.canvas_x_to_qn(cull_min_x, margin_left, s, qn_per_measure, 0.001, measure_map) - 2.0)
    local vis_max_qn = Engraver.canvas_x_to_qn(cull_max_x, margin_left, s, qn_per_measure, 0.001, measure_map) + 2.0
    local vis_min_measure = math.max(0, math.floor(vis_min_qn / qn_per_measure))
    local vis_max_measure = math.min(total_measures, math.ceil(vis_max_qn / qn_per_measure))

    local is_hovered = reaper.ImGui_IsItemHovered(ctx)
    local is_active  = reaper.ImGui_IsItemActive(ctx)
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
    
    -- Immediately update live drag targets for dynamics and articulations
    if state.drag_articulation and reaper.ImGui_IsMouseDragging(ctx, 0, 3.0) and not state.is_resizing_item then
        state.is_dragging_articulation = true
        state.drag_art_target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
    end
    if state.drag_dynamic and reaper.ImGui_IsMouseDragging(ctx, 0, 3.0) and not state.is_resizing_item then
        state.is_dragging_dynamic = true
        state.drag_dyn_target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
    end
    if not reaper.ImGui_IsMouseDown(ctx, 0) and not reaper.ImGui_IsMouseReleased(ctx, 0) then
        state.is_dragging_dynamic = false
        state.drag_dynamic = nil
        state.drag_dyn_target_qn = nil
        state.is_dragging_articulation = false
        state.drag_articulation = nil
        state.drag_art_target_qn = nil
    end
    
    -- Canvas background (clamped to visible viewport)
    local bg_x0 = math.max(canvas_p0_x, cull_min_x)
    local bg_y0 = math.max(canvas_p0_y, cull_min_y)
    local bg_x1 = math.min(canvas_p0_x + canvas_total_w, cull_max_x)
    local bg_y1 = math.min(canvas_p0_y + canvas_total_h, cull_max_y)
    if bg_x0 < bg_x1 and bg_y0 < bg_y1 then
        reaper.ImGui_DrawList_AddRectFilled(draw_list, bg_x0, bg_y0, bg_x1, bg_y1, Constants.COLORS.paper_bg)
    end
    
    local mrx0, mry0, mrx1, mry1 = 0, 0, 0, 0
    if state.marquee_active then
        mrx0 = math.min(state.marquee_start_x, state.marquee_cur_x)
        mrx1 = math.max(state.marquee_start_x, state.marquee_cur_x)
        mry0 = math.min(state.marquee_start_y, state.marquee_cur_y)
        mry1 = math.max(state.marquee_start_y, state.marquee_cur_y)
    end
    
    local note_hovered_this_frame = nil
    local dyn_hovered_this_frame = nil
    local art_hovered_this_frame = nil
    local item_edge_hovered_this_frame = nil
    local hairpin_hovered_this_frame = nil
    local hairpin_handle_hovered_this_frame = nil
    local dynamic_text_hovered_this_frame = nil
    local dynamic_text_handle_hovered_this_frame = nil
    local pedal_hovered_this_frame = nil
    local pedal_handle_hovered_this_frame = nil
    local text_item_hovered_this_frame = nil
    local chord_hovered_this_frame = nil
    local chord_handle_hovered_this_frame = nil
    local hov = {}
    
    local chord_lane_h = (state.show_chord_lane ~= false) and (42 * s) or 0
    local rehearsal_lane_h = (state.show_rehearsal_lane ~= false) and (28 * s) or 0
    local cur_band_top = canvas_p0_y + 40 * s + chord_lane_h + rehearsal_lane_h
    local score_top_y = cur_band_top
    local score_bottom_y = cur_band_top
    local staff_line_col = Constants.COLORS.staff_line
    
    local all_note_render_data = {}
    local all_note_render_by_key = {}
    local all_articulation_render_data = {}
    local all_bar_ties = {}
    local first_staff_top_y = nil
    local last_staff_bottom_y = nil
    
    local ghost_opacity = math.max(0.05, math.min(1.0, state.ghost_voice_opacity or 0.25))
    local ghost_alpha_byte = math.floor(ghost_opacity * 255 + 0.5)
    local global_ghost_col = 0x88888800 | ghost_alpha_byte
    
    -- Render each track
    for t_idx, tdata in ipairs(active_tracks_data) do
        local single_band_h = tdata.band_h
        local band_y0 = cur_band_top
        local band_y1 = cur_band_top + single_band_h
        tdata.band_y0 = band_y0
        tdata.band_y1 = band_y1
        score_bottom_y = band_y1
        
        local track_clef = tdata.clef
        local is_grand = (track_clef == "grand") or (tdata.is_grand == true)
        local is_harp = (track_clef == "harp_3staff") or (tdata.is_harp == true)
        tdata.is_grand = is_grand
        tdata.is_harp = is_harp
        local staff_line_col = Constants.COLORS.staff_line
        local line_spacing = 8.0 * s
        local step_y = line_spacing / 2.0
        
        local treble_bottom_y = band_y0 + 72 * s
        local mid_bottom_y = is_harp and (band_y0 + 148 * s) or nil
        local bass_bottom_y = is_harp and (band_y0 + 224 * s) or (is_grand and (band_y0 + 148 * s) or (band_y0 + 80 * s))
        
        local staff_top_y = treble_bottom_y - 4*line_spacing
        local staff_bottom_y = (is_harp or is_grand) and bass_bottom_y or ((track_clef == "bass") and bass_bottom_y or treble_bottom_y)
        if not (is_harp or is_grand) then
            staff_bottom_y = band_y0 + 80 * s
            staff_top_y = staff_bottom_y - 4*line_spacing
            treble_bottom_y = staff_bottom_y
            bass_bottom_y = staff_bottom_y
        end
        tdata.staff_top_y = staff_top_y
        tdata.staff_bottom_y = staff_bottom_y
        tdata.treble_bottom_y = treble_bottom_y
        tdata.bass_bottom_y = bass_bottom_y
        tdata.mid_bottom_y = mid_bottom_y
        if not first_staff_top_y then first_staff_top_y = staff_top_y end
        last_staff_bottom_y = staff_bottom_y
        
        local is_track_vis_y = (band_y1 >= cull_min_y and band_y0 <= cull_max_y)
        tdata.is_visible_vertically = is_track_vis_y
        
        if is_track_vis_y then
            -- Track background and focus indicator
            local is_focused_track = (state.focused_track and state.focused_track == tdata.track)
            local track_bg_col = (t_idx % 2 == 1) and 0x00000000 or 0x00000006
            local tbg_x0 = math.max(canvas_p0_x, cull_min_x)
            local tbg_x1 = math.min(canvas_p0_x + canvas_total_w, cull_max_x)
            if tbg_x0 < tbg_x1 then
                reaper.ImGui_DrawList_AddRectFilled(draw_list, tbg_x0, band_y0, tbg_x1, band_y1, track_bg_col)
            end
            
            -- Draw MIDI items (culled to visible horizontal window)
            for _, it in ipairs(tdata.items) do
                local ix0 = Engraver.cursor_qn_to_canvas_x(it.start_qn, margin_left, s, qn_per_measure, measure_map)
                local ix1 = Engraver.cursor_qn_to_canvas_x(it.end_qn, margin_left, s, qn_per_measure, measure_map)
                if ix1 >= cull_min_x and ix0 <= cull_max_x then
                    local iy0 = staff_top_y - 8 * s
                    local iy1 = staff_bottom_y + 8 * s
                    
                    local is_item_sel = (state.selected_item and state.selected_item == it.item)
                    local show_boxes = (state.show_item_boxes ~= false)
                    
                    if show_boxes or is_item_sel then
                        local user_intensity = (state.item_box_intensity or 25) / 100.0
                        local fill_alpha = math.max(8, math.min(255, math.floor(user_intensity * 255)))
                        local border_alpha = math.max(30, math.min(255, math.floor(math.min(1.0, user_intensity * 1.6 + 0.2) * 255)))
                        local tag_alpha = math.max(60, math.min(255, math.floor(math.min(1.0, user_intensity * 1.2 + 0.4) * 255)))
                        local sel_fill_alpha = math.max(0x18, math.min(0xCC, math.floor(user_intensity * 255 * 0.9)))

                        local fill_col = is_item_sel and (0xFFD70000 | sel_fill_alpha) or reaper_color_to_rgba(it.col, fill_alpha)
                        local border_col = is_item_sel and 0xFFD700FF or reaper_color_to_rgba(it.col, border_alpha)
                        local border_th = is_item_sel and (2.2 * s) or (1.0 * s)
                        
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, ix0, iy0, ix1, iy1, fill_col, 5)
                        reaper.ImGui_DrawList_AddRect(draw_list, ix0, iy0, ix1, iy1, border_col, 5, 0, border_th)
                        
                        -- Top-left item tag
                        local tag_w = math.min(180 * s, math.max(60 * s, #it.name * 7.5 * s + 22 * s))
                        local tag_h = 16 * s
                        local tag_x0 = ix0
                        local tag_y0 = iy0 - tag_h
                        local tag_x1 = ix0 + tag_w
                        local tag_y1 = iy0
                        
                        local tag_bg = is_item_sel and 0xFFD700EE or reaper_color_to_rgba(it.col, tag_alpha)
                        local tag_txt_col = is_item_sel and 0x111111FF or 0xFFFFFFFF
                        local tag_lbl = is_item_sel and ("✓ " .. it.name) or it.name
                        
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, tag_x0, tag_y0, tag_x1, tag_y1, tag_bg, 3)
                        reaper.ImGui_DrawList_AddText(draw_list, tag_x0 + 4*s, tag_y0 + 1*s, tag_txt_col, tag_lbl)
                        
                        -- Item tag click (Left = selection, Right = item context menu)
                        local is_tag_hov = is_hovered and (mouse_x >= tag_x0 and mouse_x <= tag_x1 and mouse_y >= tag_y0 and mouse_y <= tag_y1)
                        if is_tag_hov then
                            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                            if reaper.ImGui_IsMouseClicked(ctx, 0) and not is_ctrl then
                                if state.selected_item == it.item then
                                    state.selected_item = nil
                                    state.selected_take = nil
                                    reaper.SelectAllMediaItems(0, false)
                                    reaper.UpdateArrange()
                                    state.status_msg = "MIDI item deselected"
                                else
                                    state.selected_item = it.item
                                    state.selected_take = it.take
                                    state.focused_track = tdata.track
                                    reaper.SelectAllMediaItems(0, false)
                                    reaper.SetMediaItemSelected(it.item, true)
                                    reaper.UpdateArrange()
                                    state.status_msg = string.format("MIDI item '%s' (%s) selected", it.name, tdata.name)
                                end
                            end
                            if reaper.ImGui_IsMouseClicked(ctx, 1) then
                                state.selected_item = it.item
                                state.selected_take = it.take
                                state.focused_track = tdata.track
                                state.item_context_target = it
                                state.item_context_track_data = tdata
                                reaper.ImGui_OpenPopup(ctx, "item_header_context_popup")
                            end
                        end
                        
                        -- Item body hover for right-click context menu
                        local is_body_hov = is_hovered and (mouse_x >= ix0 and mouse_x <= ix1 and mouse_y >= iy0 and mouse_y <= iy1)
                        if is_body_hov and not is_tag_hov and not is_ctrl and not state.is_dragging then
                            item_box_hovered_this_frame = { item = it, tdata = tdata }
                        end
                    end
                    
                    -- Edge hover for resizing
                    local edge_tol = 6 * s
                    if is_hovered and not state.is_dragging and not state.marquee_active and not is_ctrl and not state.is_resizing_item then
                        if mouse_y >= iy0 and mouse_y <= iy1 then
                            if math.abs(mouse_x - ix0) <= edge_tol then
                                item_edge_hovered_this_frame = { item_info = it, edge = "left", track = tdata.track }
                                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
                            elseif math.abs(mouse_x - ix1) <= edge_tol then
                                item_edge_hovered_this_frame = { item_info = it, edge = "right", track = tdata.track }
                                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
                            end
                        end
                    end
                end
            end
            
            -- Staff lines (culled to visible horizontal segment)
            local function draw_5lines(bot_y)
                local lx0 = math.max(system_start_x, cull_min_x)
                local lx1 = math.min(staff_end_x, cull_max_x)
                if lx0 < lx1 then
                    for l = 0, 4 do
                        local ly = bot_y - (l * line_spacing)
                        reaper.ImGui_DrawList_AddLine(draw_list, lx0, ly, lx1, ly, staff_line_col, 1.0 * s)
                    end
                end
            end
            
            local top_system_y = staff_top_y
            local btm_system_y = staff_bottom_y
            local draw_sys_bracket = (system_start_x >= cull_min_x - 10 * s and system_start_x <= cull_max_x + 10 * s)
            
            if is_harp then
                draw_5lines(treble_bottom_y)
                draw_5lines(mid_bottom_y)
                draw_5lines(bass_bottom_y)
                -- Vertical system bracket & harp accolade (3 staves connected)
                if draw_sys_bracket then
                    reaper.ImGui_DrawList_AddLine(draw_list, system_start_x, top_system_y, system_start_x, btm_system_y, staff_line_col, 2.8 * s)
                    reaper.ImGui_DrawList_AddLine(draw_list, system_start_x - 5*s, top_system_y, system_start_x - 5*s, btm_system_y, staff_line_col, 1.4 * s)
                    reaper.ImGui_DrawList_AddLine(draw_list, system_start_x - 5*s, top_system_y, system_start_x + 5*s, top_system_y, staff_line_col, 2.2 * s)
                    reaper.ImGui_DrawList_AddLine(draw_list, system_start_x - 5*s, btm_system_y, system_start_x + 5*s, btm_system_y, staff_line_col, 2.2 * s)
                end
            elseif is_grand then
                draw_5lines(treble_bottom_y)
                draw_5lines(bass_bottom_y)
                -- Vertical system bracket and accolade (grand staff brace with wings)
                if draw_sys_bracket then
                    reaper.ImGui_DrawList_AddLine(draw_list, system_start_x, top_system_y, system_start_x, btm_system_y, staff_line_col, 2.5 * s)
                    reaper.ImGui_DrawList_AddLine(draw_list, system_start_x - 4*s, top_system_y, system_start_x - 4*s, btm_system_y, staff_line_col, 1.2 * s)
                    reaper.ImGui_DrawList_AddLine(draw_list, system_start_x - 4*s, top_system_y, system_start_x + 4*s, top_system_y, staff_line_col, 2.0 * s)
                    reaper.ImGui_DrawList_AddLine(draw_list, system_start_x - 4*s, btm_system_y, system_start_x + 4*s, btm_system_y, staff_line_col, 2.0 * s)
                end
            else
                local cdef = Constants.CLEF_DEFS[track_clef]
                local lines_cnt = (cdef and cdef.staff_lines) or 5
                local lx0 = math.max(system_start_x, cull_min_x)
                local lx1 = math.min(staff_end_x, cull_max_x)
                if lx0 < lx1 then
                    for l = 0, lines_cnt - 1 do
                        local ly = staff_bottom_y - (l * line_spacing)
                        reaper.ImGui_DrawList_AddLine(draw_list, lx0, ly, lx1, ly, staff_line_col, 1.0 * s)
                    end
                end
                if draw_sys_bracket then
                    reaper.ImGui_DrawList_AddLine(draw_list, system_start_x, top_system_y, system_start_x, btm_system_y, staff_line_col, 2.0 * s)
                end
            end
        
        -- IN THE GAP BEFORE BARLINE 1: Clef and time signature (engraving standard)
        if system_start_x + 60 * s >= cull_min_x and system_start_x <= cull_max_x then
            local clef_x = system_start_x + 20 * s
            local clef_bx0 = system_start_x + 4 * s
            local clef_bx1 = system_start_x + 36 * s
            local clef_by0 = staff_top_y - 4 * s
            local clef_by1 = staff_bottom_y + 4 * s
            
            local is_clef_hov = is_hovered and (mouse_x >= clef_bx0 and mouse_x <= clef_bx1 and mouse_y >= clef_by0 and mouse_y <= clef_by1)
            if is_clef_hov then
                reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                reaper.ImGui_DrawList_AddRectFilled(draw_list, clef_bx0, clef_by0, clef_bx1, clef_by1, 0xFF9F1C25, 4)
                reaper.ImGui_DrawList_AddRect(draw_list, clef_bx0, clef_by0, clef_bx1, clef_by1, 0xFF9F1C88, 4, 0, 1.2 * s)
                
                -- Right-click: opens selection context menu
                if reaper.ImGui_IsMouseClicked(ctx, 1) then
                    reaper.ImGui_OpenPopup(ctx, "clef_popup_" .. tostring(tdata.guid))
                end
                
                -- Left-click: immediately opens clef drawer on the right and focuses this track!
                if reaper.ImGui_IsMouseClicked(ctx, 0) and not is_ctrl then
                    state.focused_track = tdata.track
                    state.show_clefs = true
                    state.show_dynamics = false
                    state.show_tempo = false
                    state.status_msg = string.format("Track '%s': Clef drawer opened", tdata.name)
                end
            end
            
            local popup_id = "clef_popup_" .. tostring(tdata.guid)
            if reaper.ImGui_BeginPopup(ctx, popup_id) then
                reaper.ImGui_Text(ctx, "Select Clef:")
                reaper.ImGui_Separator(ctx)
                local function apply_canvas_clef(c_id)
                    state.track_clefs[tdata.guid] = c_id
                    state.cached_measure_map = nil
                    state.cached_measure_map_sig = nil
                    state._track_clefs_cache = nil
                    state._cached_hdr_metrics = nil
                    StateModule.save_settings(state)
                    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
                    if reaper.UpdateArrange then reaper.UpdateArrange() end
                end
                if reaper.ImGui_MenuItem(ctx, "🎼 Treble Clef", nil, track_clef == "treble") then
                    apply_canvas_clef("treble")
                end
                if reaper.ImGui_MenuItem(ctx, "𝄢 Bass Clef", nil, track_clef == "bass") then
                    apply_canvas_clef("bass")
                end
                if reaper.ImGui_MenuItem(ctx, "🎻 Alto Clef", nil, track_clef == "alto") then
                    apply_canvas_clef("alto")
                end
                if reaper.ImGui_MenuItem(ctx, "🎺 Tenor Clef", nil, track_clef == "tenor") then
                    apply_canvas_clef("tenor")
                end
                if reaper.ImGui_MenuItem(ctx, "🎹 Grand Staff", nil, track_clef == "grand") then
                    apply_canvas_clef("grand")
                end
                if reaper.ImGui_MenuItem(ctx, "🪕 Harp / Organ (3 Staves)", nil, track_clef == "harp_3staff") then
                    apply_canvas_clef("harp_3staff")
                end
                reaper.ImGui_Separator(ctx)
                if reaper.ImGui_MenuItem(ctx, "✨ Auto Detect", nil, not state.track_clefs[tdata.guid] or state.track_clefs[tdata.guid] == "auto") then
                    apply_canvas_clef("auto")
                end
                reaper.ImGui_Separator(ctx)
                if reaper.ImGui_MenuItem(ctx, "🔍 Open Clef Drawer...", nil, false) then
                    state.focused_track = tdata.track
                    state.show_clefs = true
                    state.show_dynamics = false
                    state.show_tempo = false
                end
                reaper.ImGui_EndPopup(ctx)
            end
            
            -- 1. Clef
            local clef_col = is_clef_hov and 0xFF9F1CFF or 0x1A1A1AFF
            if is_harp then
                draw_treble_clef(draw_list, clef_x, treble_bottom_y - line_spacing, s, clef_col, font_music)
                draw_smufl_clef(draw_list, clef_x, mid_bottom_y, 3, line_spacing, s, clef_col, font_music, Constants.SMUFL.c_clef)
                draw_bass_clef(draw_list, clef_x, bass_bottom_y - 3*line_spacing, s, clef_col, font_music)
            elseif is_grand then
                draw_treble_clef(draw_list, clef_x, treble_bottom_y - line_spacing, s, clef_col, font_music)
                draw_bass_clef(draw_list, clef_x, bass_bottom_y - 3*line_spacing, s, clef_col, font_music)
            else
                local cdef = Constants.CLEF_DEFS[track_clef]
                local c_glyph = cdef and cdef.glyph or Constants.SMUFL.g_clef
                local c_anchor = cdef and cdef.anchor_line or 2
                if not draw_smufl_clef(draw_list, clef_x, staff_bottom_y, c_anchor, line_spacing, s, clef_col, font_music, c_glyph) then
                    if track_clef == "bass" then
                        draw_bass_clef(draw_list, clef_x, staff_bottom_y - 3*line_spacing, s, clef_col, font_music)
                    else
                        draw_treble_clef(draw_list, clef_x, staff_bottom_y - line_spacing, s, clef_col, font_music)
                    end
                end
            end
            
            -- 2. Key signature between clef and time signature
            local trk_first_item = (tdata.items and tdata.items[1])
            local item_at_start = (trk_first_item and (trk_first_item.start_qn or 0) <= 0.1) and trk_first_item or nil
            local eff_key_idx, eff_key_mode = resolve_effective_key(state, tdata.track, item_at_start, 0)
            local eff_ts_num, eff_ts_den = resolve_effective_time_sig(state, tdata.track, trk_first_item, 0)
            if type(eff_ts_num) == "table" then
                eff_ts_den = eff_ts_num.denom or eff_ts_den
                eff_ts_num = eff_ts_num.num
            end
            local trk_ts_num = eff_ts_num or timesig_num or 4
            local trk_ts_den = eff_ts_den or timesig_denom or 4

            local keysig_x = system_start_x + 36 * s
            local cdef = Constants.CLEF_DEFS[track_clef]
            local is_unpitched = cdef and cdef.unpitched
            if not is_unpitched and eff_key_idx and eff_key_idx ~= 0 then
                if is_harp then
                    Engraver.draw_key_signature(draw_list, eff_key_idx, keysig_x, treble_bottom_y, line_spacing, s, clef_col, font_music, "treble")
                    Engraver.draw_key_signature(draw_list, eff_key_idx, keysig_x, mid_bottom_y, line_spacing, s, clef_col, font_music, "alto")
                    Engraver.draw_key_signature(draw_list, eff_key_idx, keysig_x, bass_bottom_y, line_spacing, s, clef_col, font_music, "bass")
                elseif is_grand then
                    Engraver.draw_key_signature(draw_list, eff_key_idx, keysig_x, treble_bottom_y, line_spacing, s, clef_col, font_music, "treble")
                    Engraver.draw_key_signature(draw_list, eff_key_idx, keysig_x, bass_bottom_y, line_spacing, s, clef_col, font_music, "bass")
                else
                    local s_clef = (track_clef == "bass" and "bass") or (track_clef == "alto" and "alto") or "treble"
                    Engraver.draw_key_signature(draw_list, eff_key_idx, keysig_x, staff_bottom_y, line_spacing, s, clef_col, font_music, s_clef)
                end
            end

            -- 3. Time signature (4/4, 3/4 etc.) directly following key signature in the gap before measure 1
            local timesig_x = system_start_x + 46 * s + max_key_sig_w
            if is_harp then
                draw_time_signature(draw_list, timesig_x, treble_bottom_y, line_spacing, s, 0x1A1A1AFF, trk_ts_num, trk_ts_den, font_music, font_main)
                draw_time_signature(draw_list, timesig_x, mid_bottom_y, line_spacing, s, 0x1A1A1AFF, trk_ts_num, trk_ts_den, font_music, font_main)
                draw_time_signature(draw_list, timesig_x, bass_bottom_y, line_spacing, s, 0x1A1A1AFF, trk_ts_num, trk_ts_den, font_music, font_main)
            elseif is_grand then
                draw_time_signature(draw_list, timesig_x, treble_bottom_y, line_spacing, s, 0x1A1A1AFF, trk_ts_num, trk_ts_den, font_music, font_main)
                draw_time_signature(draw_list, timesig_x, bass_bottom_y, line_spacing, s, 0x1A1A1AFF, trk_ts_num, trk_ts_den, font_music, font_main)
            else
                draw_time_signature(draw_list, timesig_x, staff_bottom_y, line_spacing, s, 0x1A1A1AFF, trk_ts_num, trk_ts_den, font_music, font_main)
            end
        end
        
        -- Effective notes for rest calculation and collision avoidance (including live drag)
        local eff_notes = {}
        local is_dragging_notes = state.is_dragging and state.drag_note and state.drag_selected_snapshot and (#state.drag_selected_snapshot > 0)
        local drag_keys = {}
        if is_dragging_notes then
            for _, sn in ipairs(state.drag_selected_snapshot) do
                drag_keys[string.format("%s_%d_%d", tostring(sn.take or "0"), sn.idx or 0, sn.pitch or 0)] = true
            end
        end
        
        local dq = (state.display_quantize and state.display_quantize_grid and state.display_quantize_grid > 0.001) and state.display_quantize_grid or nil
        local trk_v = (state.track_voices and tdata.guid and state.track_voices[tdata.guid]) or 0
        local filter_chan = (trk_v > 0) and (trk_v - 1) or nil
        
        for _, n in ipairs(tdata.notes) do
            if filter_chan == nil or (not state.hide_inactive_voices) or ((n.chan or 0) == filter_chan) then
            local is_sel = state:is_note_selected(n) or (state.drag_note == n)
            local n_start = n.start_qn
            local n_end = n.end_qn or (n.start_qn + (n.dur_qn or 1.0))
            if is_sel or (n_end >= vis_min_qn and n_start <= vis_max_qn) then
                local k = string.format("%s_%d_%d", tostring(n.take or "0"), n.idx or 0, n.pitch or 0)
                local base_sqn = n.start_qn
                local base_dur = n.dur_qn
                local base_pitch = n.pitch
                if is_dragging_notes and drag_keys[k] then
                    local delta_qn = state.drag_delta_qn or 0
                    local delta_p = state.drag_delta_pitch or 0
                    base_sqn = math.max(0, n.start_qn + delta_qn)
                    base_pitch = math.max(0, math.min(127, n.pitch + delta_p))
                end
                
                local eff_sqn = dq and (math.max(0, math.floor((base_sqn / dq) + 0.5) * dq)) or base_sqn
                local eff_dur = dq and (math.max(dq, math.floor((base_dur / dq) + 0.5) * dq)) or base_dur
                local eff_eqn = eff_sqn + eff_dur
                
                local active_oct = OctaveService.get_active_line_at_qn(state, tdata.guid, eff_sqn)
                local oct_shift = active_oct and (Constants.OCTAVE_LINE_DEFS[active_oct.type] and Constants.OCTAVE_LINE_DEFS[active_oct.type].shift_semitones or 0) or 0
                local written_pitch = math.max(0, math.min(127, base_pitch - oct_shift))

                local is_tr = true
                local st_target = "treble"
                if is_harp then
                    if written_pitch >= 65 then
                        is_tr = true
                        st_target = "treble"
                    elseif written_pitch >= 53 then
                        is_tr = false
                        st_target = "mid"
                    else
                        is_tr = false
                        st_target = "bass"
                    end
                elseif is_grand then
                    is_tr = (written_pitch >= 60)
                    st_target = is_tr and "treble" or "bass"
                elseif track_clef == "bass" then
                    is_tr = false
                    st_target = "bass"
                end
                table.insert(eff_notes, {
                    pitch = written_pitch,
                    start_qn = eff_sqn,
                    end_qn = eff_eqn,
                    dur_qn = eff_dur,
                    in_treble = is_tr,
                    in_staff = st_target
                })
                end
            end
        end
        
        -- With display quantize: close small gaps between consecutive notes on the same staff
        if dq then
            table.sort(eff_notes, function(a, b) return a.start_qn < b.start_qn end)
            for idx = 1, #eff_notes do
                local en = eff_notes[idx]
                for next_idx = idx + 1, #eff_notes do
                    local next_en = eff_notes[next_idx]
                    if (not is_grand and not is_harp) or (is_harp and en.in_staff == next_en.in_staff) or (is_grand and en.in_treble == next_en.in_treble) then
                        if next_en.start_qn > en.start_qn then
                            if next_en.start_qn <= en.end_qn + (dq * 0.75) then
                                en.end_qn = math.max(en.end_qn, next_en.start_qn)
                                en.dur_qn = en.end_qn - en.start_qn
                            end
                            break
                        end
                    end
                end
            end
        end

        -- Rests in gaps (strict separation of staves in grand staff & harp 3-staff and 100% collision filter)
        local function draw_staff_rests(rests_list, staff_bot, staff_is_treble, staff_id)
            local visible_rests = {}
            for _, r in ipairs(rests_list) do
                local r_start = r.start_qn
                local r_end = r.start_qn + (r.is_full_measure and qn_per_measure or r.dur_qn)
                
                -- Check and draw only within the visible area:
                if r_end >= vis_min_qn and r_start <= vis_max_qn then
                    local collision = false
                    local r_bar = r.measure_idx or math.floor(r.start_qn / bpi)
                    if RepeatService.has_repeat_mark(state, tdata.guid, r_bar) then
                        collision = true
                    end
                    
                    -- IF ANY NOTE EXISTS IN THIS MEASURE ON THIS STAFF -> NO EMPTY MEASURE REST!
                    if r.is_full_measure then
                        local m_idx = r.measure_idx or math.floor(r.start_qn / bpi)
                        local bar_sqn = m_idx * bpi
                        local bar_eqn = (m_idx + 1) * bpi
                        for _, en in ipairs(eff_notes) do
                            local matches_staff = (not is_grand and not is_harp) or (is_harp and (en.in_staff == staff_id)) or (is_grand and (en.in_treble == staff_is_treble))
                            local matches_voice = (not r.voice) or (((en.chan or 0) + 1) == r.voice)
                            if matches_staff and matches_voice then
                                local en_bar = math.floor((en.start_qn + 0.001) / bpi)
                                if en_bar == m_idx or (en.start_qn < bar_eqn - 0.001 and en.end_qn > bar_sqn + 0.001) then
                                    collision = true
                                    break
                                end
                            end
                        end
                    else
                        for _, en in ipairs(eff_notes) do
                            local matches_staff = (not is_grand and not is_harp) or (is_harp and (en.in_staff == staff_id)) or (is_grand and (en.in_treble == staff_is_treble))
                            local matches_voice = (not r.voice) or (((en.chan or 0) + 1) == r.voice)
                            if matches_staff and matches_voice then
                                local n_start = en.start_qn
                                local n_end = en.end_qn
                                local tol = dq and (dq * 0.3) or 0.05
                                if not (r_end <= n_start + tol or r_start >= n_end - tol) or math.abs(n_start - r_start) < (dq and (dq * 0.7) or 0.22) then
                                    collision = true
                                    break
                                end
                            end
                        end
                    end
                    
                    if not collision then
                        table.insert(visible_rests, r)
                    end
                end
            end
            
            table.sort(visible_rests, function(a, b) return a.start_qn < b.start_qn end)
            
            local min_rest_gap = 22.0 * s
            local prev_rx = nil
            local prev_m = nil
            for _, r in ipairs(visible_rests) do
                local rx
                if r.is_full_measure then
                    if measure_map and measure_map.starts then
                        local m_idx = r.measure_idx or 0
                        local m_start = measure_map.starts[m_idx] or (margin_left + m_idx * measure_map.base_w)
                        local m_w = measure_map.widths[m_idx] or measure_map.base_w
                        rx = m_start + (m_w / 2)
                    else
                        local measure_w, pad_left, pad_right, usable_w = Engraver.get_measure_layout(s, qn_per_measure)
                        local m_x = margin_left + (r.measure_idx * measure_w)
                        rx = m_x + pad_left + (usable_w / 2)
                    end
                else
                    rx = Engraver.qn_to_canvas_x(r.start_qn, margin_left, s, qn_per_measure, measure_map)
                end
                
                local cur_m = r.measure_idx or math.floor(r.start_qn / bpi)
                if prev_rx and prev_m == cur_m and not r.is_full_measure then
                    if rx < prev_rx + min_rest_gap then
                        rx = prev_rx + min_rest_gap
                    end
                end
                prev_rx = rx
                prev_m = cur_m
                
                if rx >= cull_min_x - 30 * s and rx <= cull_max_x + 30 * s then
                    Engraver.draw_rest(draw_list, r, staff_bot, line_spacing, margin_left, s, qn_per_measure, 0x1A1A1AFF, font_music, measure_map, rx)
                end
            end
        end

        if is_harp then
            local treble_eff, alto_eff, bass_eff = {}, {}, {}
            for _, en in ipairs(eff_notes) do
                if en.in_staff == "treble" then
                    table.insert(treble_eff, en)
                elseif en.in_staff == "mid" or en.in_staff == "alto" then
                    table.insert(alto_eff, en)
                else
                    table.insert(bass_eff, en)
                end
            end
            draw_staff_rests(Engraver.generate_voice_rests(treble_eff, total_measures, qn_per_measure, dq, vis_min_measure, vis_max_measure), treble_bottom_y, true, "treble")
            draw_staff_rests(Engraver.generate_voice_rests(alto_eff, total_measures, qn_per_measure, dq, vis_min_measure, vis_max_measure), mid_bottom_y, false, "mid")
            draw_staff_rests(Engraver.generate_voice_rests(bass_eff, total_measures, qn_per_measure, dq, vis_min_measure, vis_max_measure), bass_bottom_y, false, "bass")
        elseif is_grand then
            local treble_eff = {}
            local bass_eff = {}
            for _, en in ipairs(eff_notes) do
                if en.in_treble then
                    table.insert(treble_eff, en)
                else
                    table.insert(bass_eff, en)
                end
            end
            local treble_rests = Engraver.generate_voice_rests(treble_eff, total_measures, qn_per_measure, dq, vis_min_measure, vis_max_measure)
            local bass_rests   = Engraver.generate_voice_rests(bass_eff, total_measures, qn_per_measure, dq, vis_min_measure, vis_max_measure)
            draw_staff_rests(treble_rests, treble_bottom_y, true)
            draw_staff_rests(bass_rests, bass_bottom_y, false)
        elseif track_clef == "bass" then
            local track_rests = Engraver.generate_voice_rests(eff_notes, total_measures, qn_per_measure, dq, vis_min_measure, vis_max_measure)
            draw_staff_rests(track_rests, bass_bottom_y, false)
        else
            local track_rests = Engraver.generate_voice_rests(eff_notes, total_measures, qn_per_measure, dq, vis_min_measure, vis_max_measure)
            draw_staff_rests(track_rests, staff_bottom_y, true)
        end
        
        -- Visual notes (culled to visible viewport)
        local visual_notes, bar_ties = Engraver.get_visual_notes(tdata.notes, qn_per_measure, vis_min_qn, vis_max_qn)
        for _, bt in ipairs(bar_ties) do table.insert(all_bar_ties, bt) end
        
        -- Voice filtering and ghosting (MIDI channels 0-15)
        if filter_chan ~= nil then
            if state.hide_inactive_voices then
                local filtered_vn = {}
                for _, vn in ipairs(visual_notes) do
                    if vn.orig and (vn.orig.chan or 0) == filter_chan then
                        table.insert(filtered_vn, vn)
                    end
                end
                visual_notes = filtered_vn
            else
                for _, vn in ipairs(visual_notes) do
                    if vn.orig and (vn.orig.chan or 0) ~= filter_chan then
                        vn.is_ghost_voice = true
                    end
                end
            end
        end
        
        local track_has_multi_staff_chan = false
        if is_grand then
            for _, vn_chk in ipairs(visual_notes) do
                local c = vn_chk.chan or (vn_chk.orig and vn_chk.orig.chan) or 0
                if c >= 2 then
                    track_has_multi_staff_chan = true
                    break
                end
            end
        end
        
        for _, vn in ipairs(visual_notes) do
            local pref_acc = Engraver.get_note_preferred_accidental(vn, state)
            local eff_pitch, active_oct, oct_shift = Engraver.get_note_effective_pitch(vn.pitch, vn.start_qn, tdata.guid, state)
            
            local cdef = Constants.CLEF_DEFS and Constants.CLEF_DEFS[track_clef]
            local is_unpitched = cdef and cdef.unpitched
            local note_item = vn.item or (vn.orig and vn.orig.item)
            local note_key_idx = resolve_effective_key(state, tdata.track, note_item, vn.start_qn)
            
            local force_staff = nil
            if is_grand and track_has_multi_staff_chan then
                local n_c = vn.chan or (vn.orig and vn.orig.chan) or 0
                force_staff = (n_c >= 2) and "bass" or "treble"
            end
            
            local ny, in_treble_b, dstep, acc, staff_target = Engraver.pitch_to_canvas_y(eff_pitch, treble_bottom_y, bass_bottom_y, step_y, is_grand, track_clef, pref_acc, mid_bottom_y, note_key_idx, force_staff)
            vn.nominal_ny = ny
            vn.in_staff = staff_target
            vn.in_treble = in_treble_b
            vn.dstep = dstep
            vn.acc = is_unpitched and 0 or acc
            vn.notehead_type = is_unpitched and Constants.get_percussion_notehead_type(eff_pitch) or "standard"
            vn.is_unpitched = is_unpitched
            vn.active_octave_line = active_oct
            
            -- Display quantize: visual snapping of note positions to the selected grid
            local display_qn = vn.start_qn
            if state.display_quantize and state.display_quantize_grid and state.display_quantize_grid > 0.001 then
                local dq_grid = state.display_quantize_grid
                display_qn = math.floor((vn.start_qn / dq_grid) + 0.5) * dq_grid
            end
            vn.nominal_nx = Engraver.qn_to_canvas_x(display_qn, margin_left, s, qn_per_measure, measure_map)
            vn.head_x_offset = 0
            vn.acc_x_offset = 0
            vn.vis_nx = vn.nominal_nx
            vn.vis_ny = vn.nominal_ny
        end
        
        -- Sort notes by staff (in_staff), then onset time, then pitch
        local staff_order = { treble = 1, mid = 2, alto = 2, bass = 3 }
        table.sort(visual_notes, function(a, b)
            local sa = a.in_staff or (a.in_treble and "treble" or "bass")
            local sb = b.in_staff or (b.in_treble and "treble" or "bass")
            local oa = staff_order[sa] or (a.in_treble and 1 or 3)
            local ob = staff_order[sb] or (b.in_treble and 1 or 3)
            if oa ~= ob then return oa < ob end
            if math.abs(a.start_qn - b.start_qn) > 0.02 then return a.start_qn < b.start_qn end
            return a.pitch < b.pitch
        end)
        
        -- Check whether polyphonic voices are active on this track
        local track_voices_set = {}
        for _, vn in ipairs(visual_notes) do
            local v = (vn.orig and vn.orig.chan) or 0
            track_voices_set[v] = true
        end
        local track_voice_count = 0
        for _ in pairs(track_voices_set) do track_voice_count = track_voice_count + 1 end
        local is_polyphonic_track = (track_voice_count > 1)

        -- Form chord clusters (strictly separated by staff AND by voice!)
        local chord_clusters = {}
        local cur_cluster = nil
        for _, vn in ipairs(visual_notes) do
            local vn_v = (vn.orig and vn.orig.chan) or 0
            local vn_staff = vn.in_staff or (vn.in_treble and "treble" or "bass")
            local is_arp = (vn.orig and (vn.orig.arpeggio or vn.orig.articulation == "arpeggio"))
            local time_tol = (is_arp or (cur_cluster and cur_cluster.is_arpeggio)) and 0.08 or 0.03
            local same_staff = cur_cluster and (cur_cluster.staff == vn_staff)
            local same_time = cur_cluster and (math.abs(vn.start_qn - cur_cluster.start_qn) < time_tol)
            local same_voice = cur_cluster and (cur_cluster.voice == vn_v)
            if not (same_staff and same_time and same_voice) then
                cur_cluster = {
                    start_qn     = vn.start_qn,
                    staff        = vn_staff,
                    in_treble    = vn.in_treble,
                    voice        = vn_v,
                    notes        = {},
                    is_arpeggio  = (is_arp == true or is_arp == "up" or is_arp == "down"),
                    arpeggio_dir = (vn.orig and vn.orig.arpeggio) or "up"
                }
                table.insert(chord_clusters, cur_cluster)
            end
            if is_arp then
                cur_cluster.is_arpeggio = true
                if vn.orig and vn.orig.arpeggio then cur_cluster.arpeggio_dir = vn.orig.arpeggio end
            end
            table.insert(cur_cluster.notes, vn)
            vn.chord_cluster = cur_cluster
        end
        
        for _, cluster in ipairs(chord_clusters) do
            local cnotes = cluster.notes
            local max_dist = -1
            local chord_stem_down = false
            local manual_stem_dir = nil
            for _, vn in ipairs(cnotes) do
                local sdir = Engraver.get_note_stem_direction(vn, state)
                if sdir then
                    manual_stem_dir = sdir
                end
                local mid_step = 4 -- Middle line of 5-line staff (B4 in treble clef, D3 in bass clef, C4 in alto clef)
                local dist = math.abs(vn.dstep - mid_step)
                if dist > max_dist then
                    max_dist = dist
                    chord_stem_down = (vn.dstep >= mid_step)
                end
            end
            if manual_stem_dir == "up" then
                cluster.stem_down = false
            elseif manual_stem_dir == "down" then
                cluster.stem_down = true
            elseif is_polyphonic_track then
                -- Gould ("Behind Bars"): polyphonic voice-leading per engraving standards
                -- Voice 1 (and odd voices: Voice 1, 3 -> chan 0, 2) = stems UP!
                -- Voice 2 (and even voices: Voice 2, 4 -> chan 1, 3) = stems DOWN!
                if (cluster.voice or 0) % 2 == 1 then
                    cluster.stem_down = true
                else
                    cluster.stem_down = false
                end
            else
                cluster.stem_down = chord_stem_down
            end
            
            local note_w = 10.8 * s
            for i = 1, #cnotes do
                local vn = cnotes[i]
                if i > 1 then
                    local prev_vn = cnotes[i - 1]
                    local step_diff = vn.dstep - prev_vn.dstep
                    if step_diff == 0 then
                        vn.head_x_offset = prev_vn.head_x_offset + 11.5 * s
                    elseif step_diff == 1 then
                        if chord_stem_down then
                            if prev_vn.head_x_offset == 0 then prev_vn.head_x_offset = -note_w else vn.head_x_offset = note_w end
                        else
                            if prev_vn.head_x_offset == 0 then vn.head_x_offset = note_w else vn.head_x_offset = 0 end
                        end
                    end
                end
                vn.vis_nx = vn.nominal_nx + vn.head_x_offset
            end
            
            local acc_notes = {}
            for _, vn in ipairs(cnotes) do
                if vn.acc ~= 0 and (not vn.is_segment or vn.seg_idx == 1) then table.insert(acc_notes, vn) end
            end
            if #acc_notes > 1 then
                for ai = 1, #acc_notes do
                    if ai % 2 == 0 then acc_notes[ai].acc_x_offset = -10.0 * s end
                end
            end
        end
        
        -- Collision spacing adjustment (only within the same staff and measure!)
        for ci = 2, #chord_clusters do
            local cur_c = chord_clusters[ci]
            local prev_c = nil
            for pi = ci - 1, 1, -1 do
                if chord_clusters[pi].staff == cur_c.staff then
                    prev_c = chord_clusters[pi]
                    break
                end
            end
            if prev_c then
                local cur_m = math.floor(cur_c.start_qn / bpi)
                local prev_m = math.floor(prev_c.start_qn / bpi)
                
                -- Perform collision detection and note pushing ONLY within the same measure!
                if cur_m == prev_m then
                    local prev_max_x = prev_c.notes[1].vis_nx
                    for _, pvn in ipairs(prev_c.notes) do
                        if pvn.vis_nx > prev_max_x then prev_max_x = pvn.vis_nx end
                        if Engraver.is_dotted_duration(pvn.dur_qn) then prev_max_x = math.max(prev_max_x, pvn.vis_nx + 8 * s) end
                    end
                    local cur_min_x = cur_c.notes[1].vis_nx
                    for _, cvn in ipairs(cur_c.notes) do
                        local left_edge = cvn.vis_nx
                        if cvn.acc ~= 0 then left_edge = cvn.vis_nx - 11.5 * s + cvn.acc_x_offset end
                        if left_edge < cur_min_x then cur_min_x = left_edge end
                    end
                    local min_gap = 14 * s
                    if cur_min_x < prev_max_x + min_gap then
                        local push = (prev_max_x + min_gap) - cur_min_x
                        local m_end_x = (measure_map and measure_map.starts and measure_map.starts[cur_m + 1]) or (margin_left + (cur_m + 1) * measure_w)
                        local max_allowed_x = m_end_x - 18 * s -- Safety clearance before right barline
                        for _, cvn in ipairs(cur_c.notes) do
                            cvn.vis_nx = math.min(max_allowed_x, cvn.vis_nx + push)
                        end
                    end
                end
            end
        end
        
        -- Register note rendering data
        for _, vn in ipairs(visual_notes) do
            local rdata = {
                pitch = vn.pitch, start_qn = vn.start_qn, end_qn = vn.end_qn,
                dur_qn = vn.dur_qn, nx = vn.vis_nx, ny = vn.vis_ny,
                in_treble = vn.in_treble, in_staff = vn.in_staff, dstep = vn.dstep, stem_down = false,
                stem_x = vn.vis_nx, stem_end_y = vn.vis_ny, flag_count = Engraver.get_flag_count(vn.dur_qn),
                key = vn.key, note = vn.orig, orig = vn.orig, track = tdata.track,
                item = vn.orig and vn.orig.item, take = vn.orig and vn.orig.take,
                idx = vn.orig and vn.orig.idx, is_segment = vn.is_segment,
                is_ghost_voice = vn.is_ghost_voice
            }
            table.insert(all_note_render_data, rdata)
            all_note_render_by_key[vn.key] = rdata
        end
        
        -- ======================================================================
        -- STANDARD-COMPLIANT BEAMING CALCULATION & NOTE FILTER
        -- ======================================================================
        -- Notes from repeated measures are completely hidden from visual rendering:
        local display_notes = {}
        for _, vn in ipairs(visual_notes) do
            local note_bar = math.floor((vn.start_qn + 0.001) / bpi)
            if not RepeatService.has_repeat_mark(state, tdata.guid, note_bar) then
                table.insert(display_notes, vn)
            end
        end

        local beam_groups = Engraver.get_beam_groups(display_notes, qn_per_measure, state.beam_grouping)
        local beamed_notes_map = {}
        for _, bgroup in ipairs(beam_groups) do
            local all_ghost = true
            for _, bvn in ipairs(bgroup) do
                if not bvn.is_ghost_voice then all_ghost = false break end
            end
            local beam_col = Constants.COLORS.beam_color
            if all_ghost then
                local b_v = (bgroup[1].orig and bgroup[1].orig.chan or 0) + 1
                if (state.voice_color_mode ~= false) and b_v > 1 and Constants.VOICE_COLORS and Constants.VOICE_COLORS[b_v] then
                    beam_col = (Constants.VOICE_COLORS[b_v] & 0xFFFFFF00) | ghost_alpha_byte
                else
                    beam_col = global_ghost_col
                end
            end
            local bmap = Engraver.calculate_and_draw_beams(draw_list, bgroup, s, beam_col, all_note_render_by_key, state)
            for k in pairs(bmap) do beamed_notes_map[k] = true end
        end
        
        -- Draw noteheads, accidentals, ledger lines & articulations (visible notes only)
        for _, vn in ipairs(display_notes) do
            local nx = vn.vis_nx
            local ny = vn.vis_ny
            local n = vn.orig
            local is_sel = state:is_note_selected(n)
            
            if is_sel or (nx >= cull_min_x and nx <= cull_max_x) then
                local in_treble = vn.in_treble
                local dstep = vn.dstep
                local acc = vn.acc
                
                local dist_to_mouse = math.sqrt((mouse_x - nx)^2 + (mouse_y - ny)^2)
                local is_hov = is_hovered and (dist_to_mouse <= 12.5*s) and not vn.is_ghost_voice
                if is_hov then
                    note_hovered_this_frame = n
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                end
                
                -- Note click (selection / step mode only)
                if is_hov and reaper.ImGui_IsMouseClicked(ctx, 0) and state.input_mode_type ~= "draw" then
                    state.selected_dynamic = nil
                    state.selected_tempo_marker = nil
                    state.selected_octave_line = nil
                    state.focused_track = n.track
                    if n.track and reaper.ValidatePtr(n.track, "MediaTrack*") then
                        reaper.SetOnlyTrackSelected(n.track)
                    end
                    AudioPreview.play_note(state, n.pitch, n.vel, n.chan, n.track, n.start_qn)
                    state.last_drag_audition_pitch = n.pitch
                    if is_shift_or_ctrl then
                        state:toggle_note_selection(n)
                    else
                        if not state:is_note_selected(n) then
                            state:clear_selection()
                            state:select_note(n)
                        else
                            state.selected_note = n
                        end
                    end
                    state.drag_note = n
                    state.drag_start_x = mouse_x
                    state.drag_start_y = mouse_y
                    state.drag_target_qn = n.start_qn
                    state.drag_target_pitch = n.pitch
                    state.is_dragging = false
                    
                    state.drag_selected_snapshot = {}
                    for k, sn in pairs(state.selected_notes) do
                        table.insert(state.drag_selected_snapshot, {
                            key = k or (sn.get_key and sn:get_key()),
                            idx = sn.idx, pitch = sn.pitch, start_qn = sn.start_qn,
                            end_qn = sn.end_qn, dur_qn = sn.dur_qn, vel = sn.vel,
                            chan = sn.chan, take = sn.take, item = sn.item, track = sn.track,
                            articulation = sn.articulation
                        })
                    end
                    midi_service.sync_selection_to_reaper(state, active_tracks_data)
                    local note_v = (n.chan or 0) + 1
                    state.status_msg = string.format("Selected: %d note(s) | Focus: %s%d [Voice %d / Ch %d] (Vel %d)", state:count_selected_notes(), Constants.PITCH_MAP[n.pitch % 12].name, math.floor(n.pitch/12)-1, note_v, note_v, n.vel)
                end
                
                -- Note right-click: open context menu (quantize, legato, delete)
                if is_hov and reaper.ImGui_IsMouseClicked(ctx, 1) and state.input_mode_type ~= "draw" then
                    state.selected_dynamic = nil
                    state.selected_tempo_marker = nil
                    state.selected_octave_line = nil
                    state.focused_track = n.track
                    if n.track and reaper.ValidatePtr(n.track, "MediaTrack*") then
                        reaper.SetOnlyTrackSelected(n.track)
                    end
                    AudioPreview.play_note(state, n.pitch, n.vel, n.chan, n.track, n.start_qn)
                    if not state:is_note_selected(n) then
                        state:clear_selection()
                        state:select_note(n)
                        midi_service.sync_selection_to_reaper(state, active_tracks_data)
                    end
                    reaper.ImGui_OpenPopup(ctx, "NoteContextMenu")
                end
                
                -- Notehead & highlight
                local head_col = Constants.COLORS.notehead_black
                local note_v = (n.chan or 0) + 1
                
                if vn.is_ghost_voice then
                    if (state.voice_color_mode ~= false) and note_v > 1 and Constants.VOICE_COLORS and Constants.VOICE_COLORS[note_v] then
                        head_col = (Constants.VOICE_COLORS[note_v] & 0xFFFFFF00) | ghost_alpha_byte
                    else
                        head_col = global_ghost_col
                    end
                elseif is_sel then
                    head_col = state.is_dragging and 0x88888855 or Constants.COLORS.selection_gold
                    if not state.is_dragging then
                        reaper.ImGui_DrawList_AddCircle(draw_list, nx, ny, 8.5*s, Constants.COLORS.selection_border, 0, 2.5*s)
                        if (state.voice_color_mode ~= false) and note_v > 1 and Constants.VOICE_COLORS and Constants.VOICE_COLORS[note_v] then
                            reaper.ImGui_DrawList_AddCircleFilled(draw_list, nx, ny, 3.8*s, Constants.VOICE_COLORS[note_v])
                        end
                    end
                elseif state.marquee_active and (nx >= mrx0 - 8*s and nx <= mrx1 + 8*s and ny >= mry0 - 8*s and ny <= mry1 + 8*s) then
                    head_col = 0xF39C12FF
                    reaper.ImGui_DrawList_AddCircle(draw_list, nx, ny, 7.5*s, 0xFF9F1C55, 0, 1.8*s)
                elseif is_hov then
                    head_col = Constants.COLORS.hover_orange
                elseif (state.voice_color_mode ~= false) and note_v > 1 and Constants.VOICE_COLORS and Constants.VOICE_COLORS[note_v] then
                    head_col = Constants.VOICE_COLORS[note_v]
                end
                
                -- Ledger lines dynamically calculated for all clefs & staves
                local ledger_col = staff_line_col
                local staff_bot = staff_bottom_y
                if is_harp then
                    staff_bot = (vn.in_staff == "treble") and treble_bottom_y or ((vn.in_staff == "mid" or vn.in_staff == "alto") and mid_bottom_y or bass_bottom_y)
                elseif is_grand then
                    staff_bot = (vn.in_staff == "treble") and treble_bottom_y or bass_bottom_y
                end
                
                local cur_ledger_col = vn.is_ghost_voice and head_col or ledger_col
                if dstep <= -2 then
                    for ls = -2, dstep, -2 do
                        local ly = staff_bot - (ls * step_y)
                        reaper.ImGui_DrawList_AddLine(draw_list, nx - 9*s, ly, nx + 9*s, ly, cur_ledger_col, 1.4*s)
                    end
                elseif dstep >= 10 then
                    for ls = 10, dstep, 2 do
                        local ly = staff_bot - (ls * step_y)
                        reaper.ImGui_DrawList_AddLine(draw_list, nx - 9*s, ly, nx + 9*s, ly, cur_ledger_col, 1.4*s)
                    end
                end
                
                -- Accidentals (suppressed on unpitched percussion)
                if acc ~= 0 and (not vn.is_unpitched) and (not vn.is_segment or vn.seg_idx == 1) then
                    local acc_col = vn.is_ghost_voice and head_col or nil
                    Engraver.draw_accidental(draw_list, acc, nx - 11.5*s + vn.acc_x_offset, ny, s, font_music, acc_col)
                end
                
                local is_whole = (math.abs(vn.dur_qn - 4.0) < 0.15)
                local is_half  = (math.abs(vn.dur_qn - 2.0) < 0.15 or math.abs(vn.dur_qn - 3.0) < 0.15)
                Engraver.draw_oval_notehead(draw_list, nx, ny, s, head_col, not (is_whole or is_half), is_whole, font_music, vn.notehead_type)
                
                if Engraver.is_dotted_duration(vn.dur_qn) then
                    Engraver.draw_dot(draw_list, nx, ny, s, head_col, font_music)
                end
                
                if n.articulation then
                    local is_extreme = true
                    if vn.chord_cluster and #vn.chord_cluster.notes > 1 then
                        local cnotes = vn.chord_cluster.notes
                        if vn.chord_cluster.stem_down then
                            is_extreme = (vn == cnotes[#cnotes])
                        else
                            is_extreme = (vn == cnotes[1])
                        end
                    end
                    if is_extreme then
                        local is_above = vn.chord_cluster.stem_down
                        local art_y = is_above and (ny - 12*s) or (ny + 14*s)
                        
                        if n.articulation == "marcato" or n.articulation == "marc" then
                            art_y = is_above and (ny - 19*s) or (ny + 20*s)
                        elseif n.articulation == "staccatissimo" or n.articulation == "staccatiss" or n.articulation == "wedge" then
                            art_y = is_above and (ny - 14*s) or (ny + 15*s)
                        elseif n.articulation == "harmonic" or n.articulation == "harm" or n.articulation == "flageolet" then
                            is_above = true
                            art_y = ny - 15*s
                        elseif n.articulation == "tenuto" or n.articulation == "ten" then
                            art_y = is_above and (ny - 11*s) or (ny + 13*s)
                        end
                        
                        Engraver.draw_articulation(draw_list, n.articulation, nx, art_y, s, head_col, font_music, is_above)
                    end
                end
            end
        end
        
        -- Stems & flags (respects beams! Visible clusters only)
        for _, cluster in ipairs(chord_clusters) do
            local cluster_m = math.floor((cluster.notes[1].start_qn + 0.001) / bpi)
            if not RepeatService.has_repeat_mark(state, tdata.guid, cluster_m) then
            local base_nx = cluster.notes[1].nominal_nx
            if base_nx >= cull_min_x - 30 * s and base_nx <= cull_max_x + 30 * s then
                local cnotes = cluster.notes
                if cluster.is_arpeggio and #cnotes >= 2 then
                    local arp_min_y = cnotes[1].vis_ny
                    local arp_max_y = cnotes[1].vis_ny
                    local arp_min_x = cnotes[1].vis_nx
                    for _, vn in ipairs(cnotes) do
                        if vn.vis_ny < arp_min_y then arp_min_y = vn.vis_ny end
                        if vn.vis_ny > arp_max_y then arp_max_y = vn.vis_ny end
                        local nx_left = vn.nominal_nx
                        if vn.acc_nx and vn.acc_nx < arp_min_x then nx_left = vn.acc_nx end
                        if nx_left < arp_min_x then arp_min_x = nx_left end
                    end
                    local arp_x = arp_min_x - 12 * s
                    local arp_col = Constants.COLORS.notehead_black or 0x111111FF
                    Engraver.draw_arpeggio(draw_list, arp_x, arp_min_y, arp_max_y, s, arp_col, font_music, cluster.arpeggio_dir or "up")
                end
                local all_whole = true
                for _, vn in ipairs(cnotes) do
                    if math.abs(vn.dur_qn - 4.0) >= 0.15 then all_whole = false break end
                end
                
                if not all_whole then
                    local stem_down = cluster.stem_down
                    local stem_col = Constants.COLORS.notehead_black
                    local all_ghost = true
                    for _, cv in ipairs(cnotes) do if not cv.is_ghost_voice then all_ghost = false break end end
                    
                    if all_ghost then
                        local c_v = (cnotes[1].orig and cnotes[1].orig.chan or 0) + 1
                        if (state.voice_color_mode ~= false) and c_v > 1 and Constants.VOICE_COLORS and Constants.VOICE_COLORS[c_v] then
                            stem_col = (Constants.VOICE_COLORS[c_v] & 0xFFFFFF00) | ghost_alpha_byte
                        else
                            stem_col = global_ghost_col
                        end
                    else
                        for _, cv in ipairs(cnotes) do
                            if state:is_note_selected(cv.orig) then stem_col = Constants.COLORS.selection_gold break end
                        end
                        if stem_col == Constants.COLORS.notehead_black and (state.voice_color_mode ~= false) then
                            local c_v = (cnotes[1].orig and cnotes[1].orig.chan or 0) + 1
                            if c_v > 1 and Constants.VOICE_COLORS and Constants.VOICE_COLORS[c_v] then
                                stem_col = Constants.VOICE_COLORS[c_v]
                            end
                        end
                    end
                    
                    local min_ny = cnotes[1].vis_ny
                    local max_ny = cnotes[1].vis_ny
                    local shortest_dur = cnotes[1].dur_qn
                    local has_beamed = false
                    for _, vn in ipairs(cnotes) do
                        if vn.vis_ny < min_ny then min_ny = vn.vis_ny end
                        if vn.vis_ny > max_ny then max_ny = vn.vis_ny end
                        if vn.dur_qn < shortest_dur then shortest_dur = vn.dur_qn end
                        if beamed_notes_map[vn.key] then has_beamed = true end
                    end
                    
                    local beam_end_y = nil
                    local beam_stem_x = nil
                    local beam_down = nil
                    for _, vn in ipairs(cnotes) do
                        if vn.beam_stem_end_y then
                            beam_end_y = vn.beam_stem_end_y
                            beam_stem_x = vn.beam_stem_x
                            beam_down = vn.beam_stem_down
                            break
                        end
                    end
                    
                    local stem_x, stem_start_y, stem_end_y
                    if has_beamed and beam_end_y then
                        stem_x = beam_stem_x or (base_nx + (beam_down and (-5.0 * s) or (5.0 * s)))
                        stem_down = beam_down
                        stem_start_y = stem_down and min_ny or max_ny
                        stem_end_y = beam_end_y
                    else
                        local stem_len = 32 * s
                        stem_x = base_nx + (stem_down and (-5.0 * s) or (5.0 * s))
                        stem_start_y = stem_down and min_ny or max_ny
                        stem_end_y = stem_down and (max_ny + stem_len) or (min_ny - stem_len)
                    end
                    
                    for _, cvn in ipairs(cluster.notes) do
                        cvn.stem_x = stem_x
                        cvn.stem_end_y = stem_end_y
                        cvn.stem_down = stem_down
                        local rdata = all_note_render_by_key[cvn.key]
                        if rdata then
                            rdata.stem_x = stem_x
                            rdata.stem_end_y = stem_end_y
                            rdata.stem_down = stem_down
                        end
                    end
                    
                    reaper.ImGui_DrawList_AddLine(draw_list, stem_x, stem_start_y, stem_x, stem_end_y, stem_col, 2.5 * s)
                    
                    local flag_count = Engraver.get_flag_count(shortest_dur)
                    if flag_count > 0 and not has_beamed then
                        Engraver.draw_flags(draw_list, stem_x, stem_end_y, s, stem_col, flag_count, stem_down, font_music)
                    end
                end
            end
            end
        end
        
        -- Tuplets (triplets, quintuplets, sextuplets, septuplets, octuplets per Gardner Read / Elaine Gould)
        if (state.show_tuplets_layer ~= false) then
            Engraver.detect_and_draw_tuplets(draw_list, display_notes, s, Constants.COLORS.notehead_black or 0x111111FF, font_music, font_main, qn_per_measure, beam_groups, cull_min_x, cull_max_x, global_ghost_col)
        end
        
        -- Dynamics for this track
        local dyn_offset = (state.dynamics_offset_y or 45.0) * s
        local dyn_base_y = staff_bottom_y + dyn_offset
        local dyn_font_sz = math.floor(34 * s + 0.5)
        local track_hairpins = nil
        local track_dtexts = nil
        if (state.show_dynamics_layer ~= false) then
            for _, d in ipairs(tdata.dynamics) do
                if not d.track then
                    d.track = tdata.track
                    d.key = d:get_key()
                end
                if not d.take and #tdata.items > 0 then
                    d.take = tdata.items[1].take
                    d.key = d:get_key()
                end

                local dx = Engraver.qn_to_canvas_x(d.qn, margin_left, s, qn_per_measure, measure_map)
                local is_dyn_dragged = (state.is_dragging_dynamic and state.drag_dynamic and state.drag_dynamic.key == d.key)
                local d_k = d.key or (d.get_key and d:get_key())
                local is_in_multi_dyn = state.selected_dynamics and d_k and (state.selected_dynamics[d_k] ~= nil)
                local is_dyn_sel = (state.selected_dynamic and (state.selected_dynamic == d or state.selected_dynamic.key == d.key)) or is_in_multi_dyn or is_dyn_dragged
                
                if is_dyn_sel or (dx >= cull_min_x - 30 * s and dx <= cull_max_x + 30 * s) then
                    local dy = dyn_base_y
                    d.base_y = dyn_base_y
                    
                    local glyph, dyn_w, clean_lbl = get_dynamic_glyph_and_width(d.label, dyn_font_sz)
                    local badge_half_w = math.max(18 * s, (dyn_w / 2) + 6 * s)
                    
                    local bx0 = dx - badge_half_w
                    local bx1 = dx + badge_half_w
                    local by0 = dy - 18 * s
                    local by1 = dy + 16 * s
                    
                    if state.selected_dynamic and state.selected_dynamic ~= d and state.selected_dynamic.key == d.key then
                        state.selected_dynamic = d
                    end
                    if state.drag_dynamic and state.drag_dynamic ~= d and state.drag_dynamic.key == d.key then
                        state.drag_dynamic = d
                    end
                    local is_dyn_hov = is_hovered and (mouse_x >= bx0 and mouse_x <= bx1 and mouse_y >= by0 and mouse_y <= by1)
                    
                    if is_dyn_hov then
                        dyn_hovered_this_frame = d
                        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                    end
                    
                    if is_dyn_hov and reaper.ImGui_IsMouseClicked(ctx, 0) then
                        state:clear_selection()
                        state.selected_dynamic = d
                        state.drag_dynamic = d
                        state.focused_track = d.track
                        state.drag_dyn_start_x = mouse_x
                        state.drag_dyn_start_qn = d.qn
                        state.drag_dyn_target_qn = d.qn
                        state.is_dragging_dynamic = false
                        midi_service.sync_selection_to_reaper(state, active_tracks_data)
                        state.status_msg = string.format("Selected dynamic %s (measure %.2f)", d.label, (d.qn / bpi) + 1)
                    end
                    
                    -- Right-click on dynamic: open context menu & select dynamic if not already selected
                    if is_dyn_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
                        local has_multi = state.selected_dynamics and d_k and state.selected_dynamics[d_k]
                        if not has_multi and not state.selected_dynamic then
                            state.selected_dynamic = d
                        end
                        state.context_dynamic = d
                        reaper.ImGui_OpenPopup(ctx, "dynamic_context_popup")
                    end
                    
                    local text_col = 0x1A1A1AFF
                    if is_dyn_dragged then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx0, by0, bx1, by1, 0xFF9F1C22, 4)
                        reaper.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, 0xFFFFFF33, 4, 0, 1.0 * s)
                        text_col = 0x88888866
                    elseif is_dyn_sel then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx0, by0, bx1, by1, 0xFF9F1C33, 4)
                        reaper.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, 0xFF9F1CFF, 4, 0, 1.8 * s)
                        text_col = 0xFF9F1CFF
                    elseif is_dyn_hov then
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx0, by0, bx1, by1, 0xE67E2233, 4)
                        reaper.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, 0xE67E2288, 4, 0, 1.2 * s)
                        text_col = 0xF39C12FF
                    end
                    
                    if glyph and font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                        local pos_x = dx - (dyn_w / 2)
                        local pos_y = dy - (dyn_font_sz * 2.012)
                        reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, dyn_font_sz, pos_x, pos_y, text_col, glyph)
                    else
                        local pos_x = dx - (#d.label * 5.5 * s)
                        local pos_y = dy - 10 * s
                        reaper.ImGui_DrawList_AddText(draw_list, pos_x, pos_y, text_col, d.label)
                    end
                end
            end
        end
        
        -- Hairpins (crescendo < & decrescendo >) for this track
        if (state.show_hairpins_layer ~= false) then
            track_hairpins = HairpinService.get_hairpins_for_track(state, tdata.guid)
            local hp_open_h = 8.5 * s
        local hp_tip_h = 0.5 * s
        local hp_h_radius = 5.0 * s
        
        for _, hp in ipairs(track_hairpins) do
            local is_selected = (state.selected_hairpin and state.selected_hairpin.id == hp.id) or (state.selected_hairpins and state.selected_hairpins[hp.id] ~= nil)
            local cur_s = hp.start_qn
            local cur_e = hp.end_qn or (hp.start_qn + 1.0)
            
            if is_selected or (cur_e >= vis_min_qn and cur_s <= vis_max_qn) then
                -- Placement: in grand staff, hairpins are positioned consistently below the system (below bass_bottom_y / staff_bottom_y)
                -- vertically aligned with dynamics (f, p, etc.) rather than drifting between upper and lower staves.
                local staff_bot = staff_bottom_y
                if is_harp and hp.staff == "mid" then
                    staff_bot = mid_bottom_y or staff_bottom_y
                end

                -- Calculate lowest note/stem in this time range so hairpin is ALWAYS placed below notes
                local max_note_y = staff_bot
                for _, vn in ipairs(visual_notes) do
                    if vn.start_qn < (cur_e + 0.15) and vn.end_qn > (cur_s - 0.15) then
                        local ny = vn.vis_ny or staff_bot
                        local note_bottom = ny + 5.0 * s
                        if vn.stem_down and vn.stem_end_y then
                            note_bottom = math.max(note_bottom, vn.stem_end_y + 3.0 * s)
                        end
                        if note_bottom > max_note_y then
                            max_note_y = note_bottom
                        end
                    end
                end

                local user_doy = state.dynamics_offset_y or 45.0
                local hp_y_mid = math.max(staff_bot + (user_doy * s), max_note_y + 6.0 * s)
                hp.base_y = hp_y_mid
                
                if state.is_dragging_hairpin and state.drag_hairpin and state.drag_hairpin.id == hp.id then
                    if state.drag_hairpin_handle == "start" and state.drag_hairpin_target_qn then
                        cur_s = state.drag_hairpin_target_qn
                    elseif state.drag_hairpin_handle == "end" and state.drag_hairpin_target_qn then
                        cur_e = state.drag_hairpin_target_qn
                    elseif state.drag_hairpin_handle == "body" then
                        cur_s = hp.start_qn
                        cur_e = hp.end_qn
                    end
                end
                
                -- Live preview: when dragging a dynamic marker, docked hairpins follow in real time
                if state.is_dragging_dynamic and state.drag_dynamic and state.drag_dyn_target_qn and state.drag_dyn_start_qn then
                    local drag_orig_qn = state.drag_dyn_start_qn
                    local drag_cur_qn = state.drag_dyn_target_qn
                    local d_trk = state.drag_dynamic.track
                    local d_guid = d_trk and reaper.ValidatePtr(d_trk, "MediaTrack*") and reaper.GetTrackGUID(d_trk)
                    if not d_guid or hp.track_guid == d_guid then
                        local l_limit, r_limit = 0.0, 999999.0
                        for _, ohp in ipairs(track_hairpins) do
                            if ohp.id ~= hp.id then
                                local os = ohp.start_qn or 0.0
                                local oe = ohp.end_qn or (os + 1.0)
                                if os < hp.start_qn and oe > l_limit then l_limit = oe end
                                if os > hp.start_qn and os < r_limit then r_limit = os end
                            end
                        end
                        if math.abs(cur_s - drag_orig_qn) <= 0.35 then
                            cur_s = math.max(l_limit, math.min(cur_e - 0.25, drag_cur_qn))
                        end
                        if math.abs(cur_e - drag_orig_qn) <= 0.35 then
                            cur_e = math.min(r_limit, math.max(cur_s + 0.25, drag_cur_qn))
                        end
                    end
                end
                
                local raw_x1 = Engraver.qn_to_canvas_x(cur_s, margin_left, s, qn_per_measure, measure_map)
                local raw_x2 = Engraver.qn_to_canvas_x(cur_e, margin_left, s, qn_per_measure, measure_map)
                
                -- Inset / padding so hairpin does not collide with noteheads and fits cleanly into gaps
                local pad_x1 = 5.0 * s
                local pad_x2 = 5.0 * s
                local x1 = raw_x1 + pad_x1
                local x2 = raw_x2 - pad_x2
                local dyn_at_start = false
                local dyn_at_end = false
                
                -- Dynamic marker clearance: hairpins must NEVER be drawn over dynamic texts!
                if tdata.dynamics then
                    for _, d in ipairs(tdata.dynamics) do
                        local _, dw, d_clean = get_dynamic_glyph_and_width(d.label, dyn_font_sz)
                        local badge_hw = math.max(16 * s, (dw / 2) + 6 * s)
                        local dx = Engraver.qn_to_canvas_x(d.qn, margin_left, s, qn_per_measure, measure_map)
                        local d_left_bound = dx - badge_hw - 4.0 * s
                        local d_right_bound = dx + badge_hw + 4.0 * s
                        
                        -- Marker is at or near start
                        if math.abs(d.qn - cur_s) <= 0.35 or (cur_s <= d.qn and raw_x1 <= d_right_bound and d.qn < cur_e) then
                            x1 = math.max(x1, d_right_bound)
                            dyn_at_start = true
                        end
                        
                        -- Marker is at or near end
                        if math.abs(d.qn - cur_e) <= 0.35 or (cur_e >= d.qn and raw_x2 >= d_left_bound and d.qn > cur_s) then
                            x2 = math.min(x2, d_left_bound)
                            dyn_at_end = true
                        end
                    end
                end
                
                -- Check for adjacent hairpins (avoids gaps between consecutive < and >)
                -- Applies ONLY when NO dynamic marker is placed at the junction!
                if not dyn_at_start then
                    for _, other_hp in ipairs(track_hairpins) do
                        if other_hp.id ~= hp.id then
                            local oe = other_hp.end_qn or (other_hp.start_qn + 1.0)
                            if math.abs(oe - cur_s) <= 0.35 then
                                x1 = raw_x1 -- Seamless transition between adjacent hairpins
                                break
                            end
                        end
                    end
                end
                if not dyn_at_end then
                    for _, other_hp in ipairs(track_hairpins) do
                        if other_hp.id ~= hp.id then
                            if math.abs(other_hp.start_qn - cur_e) <= 0.35 then
                                x2 = raw_x2 -- Seamless transition to next hairpin
                                break
                            end
                        end
                    end
                end
                
                x2 = math.max(x1 + 10.0 * s, x2)
                
                -- Handle positions
                local h1_x = x1
                local h1_y = hp_y_mid
                local h2_x = x2
                local h2_y = hp_y_mid
                
                -- Hit testing
                local dist_h1 = math.sqrt((mouse_x - h1_x)^2 + (mouse_y - h1_y)^2)
                local dist_h2 = math.sqrt((mouse_x - h2_x)^2 + (mouse_y - h2_y)^2)
                local in_body = (mouse_x >= x1 + 6 * s and mouse_x <= x2 - 6 * s and mouse_y >= hp_y_mid - hp_open_h - 6 * s and mouse_y <= hp_y_mid + hp_open_h + 6 * s)
                
                local can_hover = is_hovered and not dyn_hovered_this_frame and not state.is_dragging and not state.is_dragging_dynamic and not state.is_dragging_articulation and not state.is_resizing_item
                if can_hover then
                    if dist_h1 <= 8.0 * s then
                        hairpin_hovered_this_frame = hp
                        hairpin_handle_hovered_this_frame = "start"
                    elseif dist_h2 <= 8.0 * s then
                        hairpin_hovered_this_frame = hp
                        hairpin_handle_hovered_this_frame = "end"
                    elseif in_body then
                        hairpin_hovered_this_frame = hp
                        hairpin_handle_hovered_this_frame = "body"
                    end
                end
                
                local is_hov = (hairpin_hovered_this_frame and hairpin_hovered_this_frame.id == hp.id)
                
                -- Right-click on hairpin: open context menu & select hairpin if needed
                if is_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
                    local is_in_multi = state.selected_hairpins and state.selected_hairpins[hp.id]
                    if not is_in_multi and not state.selected_hairpin then
                        state.selected_hairpin = hp
                    end
                    state.context_hairpin = hp
                    reaper.ImGui_OpenPopup(ctx, "hairpin_context_popup")
                end
                
                -- Background box on selection or hover
                if is_selected or is_hov then
                    local bg_c = is_selected and 0xFF9F1C25 or 0xFF9F1C12
                    local bdr_c = is_selected and 0xFF9F1CBB or 0xE67E2255
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, x1 - 3 * s, hp_y_mid - hp_open_h - 4 * s, x2 + 3 * s, hp_y_mid + hp_open_h + 4 * s, bg_c, 3.0)
                    reaper.ImGui_DrawList_AddRect(draw_list, x1 - 3 * s, hp_y_mid - hp_open_h - 4 * s, x2 + 3 * s, hp_y_mid + hp_open_h + 4 * s, bdr_c, 3.0, 0, 1.0 * s)
                end
                
                -- Draw lines
                local line_c = is_selected and 0xFF9F1CFF or (is_hov and 0xE67E22FF or (state.invert_mode and 0xFFFFFFFF or 0x1A1A1AFF))
                local line_th = (is_selected or is_hov) and (2.2 * s) or (1.8 * s)
                
                if hp.type == "crescendo" then
                    -- Crescendo (<): opens to the right
                    reaper.ImGui_DrawList_AddLine(draw_list, x1, hp_y_mid - hp_tip_h, x2, hp_y_mid - hp_open_h, line_c, line_th)
                    reaper.ImGui_DrawList_AddLine(draw_list, x1, hp_y_mid + hp_tip_h, x2, hp_y_mid + hp_open_h, line_c, line_th)
                else
                    -- Decrescendo (>): closes to the right
                    reaper.ImGui_DrawList_AddLine(draw_list, x1, hp_y_mid - hp_open_h, x2, hp_y_mid - hp_tip_h, line_c, line_th)
                    reaper.ImGui_DrawList_AddLine(draw_list, x1, hp_y_mid + hp_open_h, x2, hp_y_mid + hp_tip_h, line_c, line_th)
                end
                
                -- Draw dual handles (start & end) on selection or hover
                if is_selected or is_hov then
                    local h1_c = (hairpin_handle_hovered_this_frame == "start" and is_hov) and 0xFF9F1CFF or 0x3498DBFF
                    reaper.ImGui_DrawList_AddCircleFilled(draw_list, h1_x, h1_y, hp_h_radius, h1_c)
                    reaper.ImGui_DrawList_AddCircle(draw_list, h1_x, h1_y, hp_h_radius + 1.0, 0xFFFFFFFF, 0, 1.0)
                    
                    local h2_c = (hairpin_handle_hovered_this_frame == "end" and is_hov) and 0xFF9F1CFF or 0x2ECC71FF
                    reaper.ImGui_DrawList_AddCircleFilled(draw_list, h2_x, h2_y, hp_h_radius, h2_c)
                    reaper.ImGui_DrawList_AddCircle(draw_list, h2_x, h2_y, hp_h_radius + 1.0, 0xFFFFFFFF, 0, 1.0)
                end
            end
        end
        end -- if show_hairpins_layer
        
        -- Dynamic texts (cresc. & dim. text tags with scalable length)
        if (state.show_dynamic_texts_layer ~= false) then
            track_dtexts = DynamicTextService.get_dynamic_texts_for_track(state, tdata.guid)
            
            for _, dt in ipairs(track_dtexts) do
                local is_selected = (state.selected_dynamic_text and state.selected_dynamic_text.id == dt.id) or (state.selected_dynamic_texts and state.selected_dynamic_texts[dt.id] ~= nil)
                local cur_s = dt.start_qn
                local cur_e = dt.end_qn
                
                -- Live preview during drag
                if state.is_dragging_dynamic_text and state.drag_dynamic_text and state.drag_dynamic_text.id == dt.id then
                    if state.drag_dynamic_text_handle == "start" and state.drag_dynamic_text_target_qn then
                        cur_s = state.drag_dynamic_text_target_qn
                    elseif state.drag_dynamic_text_handle == "end" and state.drag_dynamic_text_target_qn then
                        cur_e = state.drag_dynamic_text_target_qn
                    elseif state.drag_dynamic_text_handle == "body" then
                        cur_s = dt.start_qn
                        cur_e = dt.end_qn
                    end
                end
                
                -- Live preview: when dragging a dynamic marker, docked dynamic texts follow in real time
                if state.is_dragging_dynamic and state.drag_dynamic and state.drag_dyn_target_qn and state.drag_dyn_start_qn then
                    local drag_orig_qn = state.drag_dyn_start_qn
                    local drag_cur_qn = state.drag_dyn_target_qn
                    local d_trk = state.drag_dynamic.track
                    local d_guid = d_trk and reaper.ValidatePtr(d_trk, "MediaTrack*") and reaper.GetTrackGUID(d_trk)
                    if not d_guid or dt.track_guid == d_guid then
                        local l_limit, r_limit = 0.0, 999999.0
                        if state.dynamic_texts then
                            for _, odt in ipairs(state.dynamic_texts) do
                                if odt.id ~= dt.id and odt.track_guid == dt.track_guid then
                                    local os = odt.start_qn or 0.0
                                    local oe = odt.end_qn or (os + 1.0)
                                    if os < dt.start_qn and oe > l_limit then l_limit = oe end
                                    if os > dt.start_qn and os < r_limit then r_limit = os end
                                end
                            end
                        end
                        if math.abs(cur_s - drag_orig_qn) <= 0.35 then
                            cur_s = math.max(l_limit, math.min(cur_e - 0.25, drag_cur_qn))
                        end
                        if math.abs(cur_e - drag_orig_qn) <= 0.35 then
                            cur_e = math.min(r_limit, math.max(cur_s + 0.25, drag_cur_qn))
                        end
                    end
                end
                
                -- Calculate X coordinates
                local raw_x1 = Engraver.qn_to_canvas_x(cur_s, margin_left, s, qn_per_measure, measure_map)
                local raw_x2 = Engraver.qn_to_canvas_x(cur_e, margin_left, s, qn_per_measure, measure_map)
                local x1 = raw_x1
                local x2 = raw_x2
                
                -- Dynamic marker clearance: text and dashed line must NEVER overlap dynamic badges!
                if tdata.dynamics then
                    for _, d in ipairs(tdata.dynamics) do
                        local _, dw, d_clean = get_dynamic_glyph_and_width(d.label, dyn_font_sz)
                        local badge_hw = math.max(16 * s, (dw / 2) + 6 * s)
                        local dx = Engraver.qn_to_canvas_x(d.qn, margin_left, s, qn_per_measure, measure_map)
                        local d_left_bound = dx - badge_hw - 4.0 * s
                        local d_right_bound = dx + badge_hw + 4.0 * s
                        
                        -- Marker is at or near start
                        if math.abs(d.qn - cur_s) <= 0.35 or (cur_s <= d.qn and raw_x1 <= d_right_bound and d.qn < cur_e) then
                            x1 = math.max(x1, d_right_bound)
                        end
                        
                        -- Marker is at or near end
                        if math.abs(d.qn - cur_e) <= 0.35 or (cur_e >= d.qn and raw_x2 >= d_left_bound and d.qn > cur_s) then
                            x2 = math.min(x2, d_left_bound)
                        end
                    end
                end
                x2 = math.max(x1 + 15 * s, x2)
                
                -- Y positioning: dyn_base_y, displaced downward if low notes intersect range
                local dt_y = dyn_base_y
                if dt.staff == "treble" and treble_bottom_y then
                    dt_y = math.max(dt_y, treble_bottom_y + 12 * s)
                end
                
                -- Collision check with low notes in time range
                for _, vn in ipairs(visual_notes) do
                    if vn.start_qn < cur_e and vn.end_qn > cur_s then
                        local note_bottom = vn.vis_ny + 8.0 * s
                        if vn.stem_down and vn.stem_end_y then
                            note_bottom = math.max(note_bottom, vn.stem_end_y + 3.0 * s)
                        end
                        if note_bottom >= dt_y - 12.0 * s then
                            dt_y = math.max(dt_y, note_bottom + 14.0 * s)
                        end
                    end
                end
                
                -- Text size & rendering
                local txt = dt.text or (dt.type == "crescendo" and "cresc." or "dim.")
                local font_sz = math.floor(18 * s + 0.5)
                local tw, _ = FontManager.calc_text_size(ctx, txt)
                if tw and tw > 0 then txt_w = tw end
                
                local txt_x = x1
                local txt_y = dt_y - (font_sz * 0.5)
                
                -- Handles & Hit-Testing
                local h1_x = x1
                local h1_y = dt_y
                local h2_x = x2
                local h2_y = dt_y
                
                local dist_h1 = math.sqrt((mouse_x - h1_x)^2 + (mouse_y - h1_y)^2)
                local dist_h2 = math.sqrt((mouse_x - h2_x)^2 + (mouse_y - h2_y)^2)
                local in_body = (mouse_x >= x1 - 4 * s and mouse_x <= x2 + 4 * s and mouse_y >= dt_y - 12 * s and mouse_y <= dt_y + 12 * s)
                
                local can_hover = is_hovered and not dyn_hovered_this_frame and not hairpin_hovered_this_frame and not state.is_dragging and not state.is_dragging_dynamic and not state.is_dragging_hairpin and not state.is_dragging_articulation and not state.is_resizing_item
                if can_hover then
                    if dist_h1 <= 8.0 * s then
                        dynamic_text_hovered_this_frame = dt
                        dynamic_text_handle_hovered_this_frame = "start"
                    elseif dist_h2 <= 8.0 * s then
                        dynamic_text_hovered_this_frame = dt
                        dynamic_text_handle_hovered_this_frame = "end"
                    elseif in_body then
                        dynamic_text_hovered_this_frame = dt
                        dynamic_text_handle_hovered_this_frame = "body"
                    end
                end
                
                local is_hov = (dynamic_text_hovered_this_frame and dynamic_text_hovered_this_frame.id == dt.id)
                
                -- Context menu on text dynamic right-click
                if is_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
                    state.selected_dynamic_text = dt
                    state.context_dynamic_text = dt
                    state.selected_dynamic = nil
                    state.selected_hairpin = nil
                    state.selected_octave_line = nil
                    state.selected_tempo_marker = nil
                    reaper.ImGui_OpenPopup(ctx, "dynamic_text_context_popup")
                end
                
                -- Selection / hover bounding box (spans full duration)
                if is_selected or is_hov then
                    local bg_c = is_selected and 0x2ECC7125 or 0x2ECC7112
                    local bdr_c = is_selected and 0x2ECC71BB or 0x27AE6055
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, x1 - 4 * s, dt_y - 10 * s, x2 + 4 * s, dt_y + 10 * s, bg_c, 3.0)
                    reaper.ImGui_DrawList_AddRect(draw_list, x1 - 4 * s, dt_y - 10 * s, x2 + 4 * s, dt_y + 10 * s, bdr_c, 3.0, 0, 1.0 * s)
                end
                
                -- Render text (traditional publisher italic style)
                local text_col = is_selected and 0xFF9F1CFF or (is_hov and 0x2ECC71FF or (state.invert_mode and 0xFFFFFFFF or 0x111111FF))
                if font_main and reaper.APIExists("ImGui_DrawList_AddTextEx") then
                    reaper.ImGui_DrawList_AddTextEx(draw_list, font_main, font_sz, txt_x, txt_y, text_col, txt)
                else
                    reaper.ImGui_DrawList_AddText(draw_list, txt_x, txt_y, text_col, txt)
                end
                
                -- Draw line pattern (unless "none")
                local line_start_x = txt_x + txt_w + 6 * s
                local line_end_x = x2
                if line_end_x > line_start_x + 8 * s then
                    local line_c = is_selected and 0xFF9F1CFF or (is_hov and 0x2ECC71FF or (state.invert_mode and 0xAAAAAAFF or 0x555555FF))
                    if dt.line_pattern == "dashed" then
                        local dash_w = 6.0 * s
                        local space_w = 6.0 * s
                        local cur_lx = line_start_x
                        while cur_lx + dash_w <= line_end_x do
                            reaper.ImGui_DrawList_AddLine(draw_list, cur_lx, dt_y, cur_lx + dash_w, dt_y, line_c, 1.5 * s)
                            cur_lx = cur_lx + dash_w + space_w
                        end
                        -- Small vertical terminal hook at end of dashed extension line (Gould p. 104)
                        reaper.ImGui_DrawList_AddLine(draw_list, line_end_x, dt_y - 3 * s, line_end_x, dt_y + 3 * s, line_c, 1.5 * s)
                    elseif dt.line_pattern == "dotted" then
                        local dot_spacing = 7.0 * s
                        local cur_lx = line_start_x
                        while cur_lx <= line_end_x do
                            reaper.ImGui_DrawList_AddCircleFilled(draw_list, cur_lx, dt_y, 1.2 * s, line_c)
                            cur_lx = cur_lx + dot_spacing
                        end
                    end
                end
                
                -- Draw dual handles (start & end) on selection or hover
                if is_selected or is_hov then
                    local h_rad = 4.5 * s
                    local h1_c = (dynamic_text_handle_hovered_this_frame == "start" and is_hov) and 0xFF9F1CFF or 0x3498DBFF
                    reaper.ImGui_DrawList_AddCircleFilled(draw_list, h1_x, h1_y, h_rad, h1_c)
                    reaper.ImGui_DrawList_AddCircle(draw_list, h1_x, h1_y, h_rad + 1.0, 0xFFFFFFFF, 0, 1.0)
                    
                    local h2_c = (dynamic_text_handle_hovered_this_frame == "end" and is_hov) and 0xFF9F1CFF or 0x2ECC71FF
                    reaper.ImGui_DrawList_AddCircleFilled(draw_list, h2_x, h2_y, h_rad, h2_c)
                    reaper.ImGui_DrawList_AddCircle(draw_list, h2_x, h2_y, h_rad + 1.0, 0xFFFFFFFF, 0, 1.0)
                end
            end
        end -- if show_dynamic_texts_layer
        
        -- ----------------------------------------------------------------------
        -- HOLDING / SUSTAIN PEDAL LINES (CC64 - Delegated to CanvasPedalRenderer)
        -- ----------------------------------------------------------------------
        if CanvasPedalRenderer and CanvasPedalRenderer.render_track_pedals then
            hov.note = note_hovered_this_frame
            hov.dyn = dyn_hovered_this_frame
            hov.hairpin = hairpin_hovered_this_frame
            hov.dynamic_text = dynamic_text_hovered_this_frame
            hov.text_item = text_item_hovered_this_frame
            hov = CanvasPedalRenderer.render_track_pedals(ctx, draw_list, state, fonts, tdata, staff_bottom_y, s, margin_left, qn_per_measure, measure_map, is_hovered, mouse_x, mouse_y, hov) or hov
            if hov and hov.pedal then
                pedal_hovered_this_frame = hov.pedal
                pedal_handle_hovered_this_frame = hov.pedal_handle
            end
        end
        
        -- Draw articulations (Reaticulate PC events) for this track
        if (state.show_articulations_layer ~= false) and tdata.articulations and #tdata.articulations > 0 then
            if not all_reaticulate_banks then
                all_reaticulate_banks = ReaticulateParser.get_all_banks()
            end
            local art_offset = (state.articulations_offset_y or 16.0) * s
            local art_base_y = staff_top_y - art_offset
            for _, art in ipairs(tdata.articulations) do
                if not art.is_auto_return then
                local is_art_dragged = (state.is_dragging_articulation and state.drag_articulation and state.drag_articulation.pc == art.pc and math.abs(state.drag_articulation.qn - art.qn) < 0.02)
                local cur_qn = (is_art_dragged and state.drag_art_target_qn) and state.drag_art_target_qn or art.qn
                local dx = Engraver.qn_to_canvas_x(cur_qn, margin_left, s, qn_per_measure, measure_map)
                local art_key = state:get_articulation_key(art)
                local is_art_sel = (state.selected_articulation == art) or state:is_articulation_selected(art) or is_art_dragged
                
                local trk_override = state.track_articulation_banks and tdata.guid and state.track_articulation_banks[tdata.guid]
                local bank = ReaticulateParser.get_bank_for_track(tdata.track, all_reaticulate_banks, trk_override, art.msb, art.lsb)
                local label = ReaticulateParser.get_art_display_name(bank, art.pc, all_reaticulate_banks)
                if (not label or label:find("^PC %d+")) and art.label and not art.label:find("^PC %d+") then
                    label = art.label
                end
                art.label = label
                
                -- Standard note articulations (staccato, tenuto, marcato, etc.) are rendered directly as symbols on the note
                -- and should not appear duplicated as text in the articulation lane.
                local is_standard_symbol = false
                if bank and bank.articulations and midi_service and midi_service.art_id_from_reaticulate_art then
                    for _, ba in ipairs(bank.articulations) do
                        if ba.pc == art.pc then
                            if midi_service.art_id_from_reaticulate_art(ba) then
                                is_standard_symbol = true
                            end
                            break
                        end
                    end
                end
                if not is_standard_symbol and label then
                    local l_low = label:lower()
                    if l_low:find("^stacc") or l_low:find("staccatiss") or l_low:find("spicc") or l_low:find("^marc") or l_low:find("^tenuto") or l_low:find("^accent") or l_low:find("harmonic") or l_low:find("flageolet") then
                        is_standard_symbol = true
                    end
                end
                if not is_standard_symbol and tdata.notes then
                    for _, n in ipairs(tdata.notes) do
                        if math.abs(n.start_qn - cur_qn) < 0.05 and n.articulation and n.articulation ~= "" and n.articulation ~= "none" then
                            local a_id = n.articulation:lower()
                            if a_id:find("stacc") or a_id:find("ten") or a_id:find("marc") or a_id:find("acc") or a_id:find("harm") then
                                is_standard_symbol = true
                                break
                            end
                        end
                    end
                end
                
                if not is_standard_symbol and (is_art_sel or (dx >= cull_min_x - 30 * s and dx <= cull_max_x + 30 * s)) then
                    local art_staff_top_y = staff_top_y
                    if is_grand and (art.staff == 2 or (art.chan and art.chan >= 2)) and bass_bottom_y then
                        art_staff_top_y = bass_bottom_y - 4 * line_spacing
                    end
                    local dy = art_staff_top_y - art_offset

                    -- Gould engraving standard: collision avoidance with high notes / stems around position
                    if visual_notes then
                        for _, vn in ipairs(visual_notes) do
                            if math.abs(vn.start_qn - cur_qn) < 1.0 then
                                local note_top = vn.vis_ny - 6 * s
                                if (not vn.stem_down) and vn.stem_end_y then
                                    note_top = math.min(note_top, vn.stem_end_y - 4 * s)
                                end
                                if note_top <= dy + 6 * s then
                                    dy = math.min(dy, note_top - 12 * s)
                                end
                            end
                        end
                    end

                    art.track = tdata.track
                    art.base_y = dy
                    if not art.take and #tdata.items > 0 then art.take = tdata.items[1].take end
                    -- Publisher typography per Gould: bold & legible font size for performance directions/articulations (e.g., "Long", "pizz.")
                    local use_bold = (state.articulations_bold ~= false)
                    local font_to_use = (use_bold and font_bold) or font_main
                    local base_pt = state.articulations_font_size or 17.0
                    local font_sz = math.max(12.0, math.floor(base_pt * s + 0.5))
                    
                    local txt_w = #label * (font_sz * 0.60)
                    local cur_fs = reaper.APIExists("ImGui_GetFontSize") and reaper.ImGui_GetFontSize(ctx) or 14.0
                    if not cur_fs or cur_fs <= 0 then cur_fs = 14.0 end
                    local cw, ch = FontManager.calc_text_size(ctx, label)
                    if cw and cw > 0 then txt_w = cw * (font_sz / cur_fs) * (use_bold and 1.08 or 1.0) end
                    if ch and ch > 0 then txt_h = ch * (font_sz / cur_fs) end
                    
                    local tx = dx
                    local ty = dy - (txt_h / 2)
                    local bx0 = tx - 3 * s
                    local bx1 = tx + txt_w + 3 * s
                    local by0 = ty - 2 * s
                    local by1 = ty + txt_h + 2 * s

                    -- Register for marquee selection rectangle
                    table.insert(all_articulation_render_data, {
                        art = art,
                        key = art_key,
                        bx0 = bx0, by0 = by0, bx1 = bx1, by1 = by1,
                        cx = (bx0 + bx1) * 0.5, cy = (by0 + by1) * 0.5,
                        track = tdata.track
                    })
                    
                    local is_hov = is_hovered and (mouse_x >= bx0 and mouse_x <= bx1 and mouse_y >= by0 and mouse_y <= by1)
                    if is_hov then
                        art_hovered_this_frame = art
                        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                    end
                    
                    if is_hov and reaper.ImGui_IsMouseClicked(ctx, 0) then
                        local is_ctrl = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftCtrl()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightCtrl())
                        local is_shift = reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_LeftShift()) or reaper.ImGui_IsKeyDown(ctx, reaper.ImGui_Key_RightShift())
                        if is_ctrl or is_shift then
                            state:toggle_articulation_selection(art)
                        else
                            state:clear_selection()
                            state:clear_articulation_selection()
                            state:select_articulation(art)
                        end
                        state.drag_articulation = art
                        state.focused_track = art.track
                        state.drag_art_start_x = mouse_x
                        state.drag_art_start_qn = art.qn
                        state.drag_art_target_qn = art.qn
                        state.is_dragging_articulation = false
                        midi_service.sync_selection_to_reaper(state, active_tracks_data)
                        state.status_msg = string.format("Selected articulation %s (measure %.2f)", label, (art.qn / bpi) + 1)
                    end
                    
                    if is_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
                        state.selected_articulation = art
                        state.context_articulation = art
                        state.focused_track = art.track
                        reaper.ImGui_OpenPopup(ctx, "articulation_context_popup")
                    end
                    
                    -- Publisher typography: elegant text articulation in regular font (e.g. legato, staccato, pizz.)
                    local base_art_col = Constants.COLORS.art_text or (state.invert_mode and 0xEEEEEEFF or 0x1A1A1AFF)
                    local text_col = base_art_col
                    
                    if is_art_dragged then
                        text_col = (base_art_col & 0xFFFFFF00) | 0x55
                        reaper.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, 0xFFFFFF33, 2.0, 0, 1.0 * s)
                    elseif is_art_sel then
                        text_col = Constants.COLORS.selection_gold or 0xFF9F1CFF
                        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx0, by0, bx1, by1, 0xFF9F1C22, 2.0)
                        reaper.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, 0xFF9F1CFF, 2.0, 0, 1.2 * s)
                    elseif is_hov then
                        text_col = Constants.COLORS.hover_orange or 0xE67E22FF
                        reaper.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, 0xFF9F1C55, 2.0, 0, 1.0 * s)
                    end
                    
                    local drew_art = false
                    if reaper.APIExists("ImGui_DrawList_AddTextEx") and font_to_use then
                        drew_art = pcall(reaper.ImGui_DrawList_AddTextEx, draw_list, font_to_use, font_sz, tx, ty, text_col, label)
                    end
                    if not drew_art then
                        reaper.ImGui_DrawList_AddText(draw_list, tx, ty, text_col, label)
                    end
                end
                end
            end
        end

        -- Text items (freely movable text annotations below track in X and Y)
        if (state.show_text_items_layer ~= false) then
            local track_texts = TextItemService.get_text_items_for_track(state, tdata.guid)
            for _, ti in ipairs(track_texts) do
                local cur_qn = ti.qn or 0.0
                local cur_offset_y = ti.offset_y or 32.0
                
                -- Live position during drag-and-drop
                if state.is_dragging_text_item and state.drag_text_item and state.drag_text_item.id == ti.id then
                    cur_qn = state.drag_text_target_qn or cur_qn
                    cur_offset_y = state.drag_text_target_offset_y or cur_offset_y
                end
                
                local tx = Engraver.qn_to_canvas_x(cur_qn, margin_left, s, qn_per_measure, measure_map)
                local is_above = (ti.placement == "above")
                local ty
                if is_above and tdata.staff_top_y then
                    local off = math.abs(cur_offset_y)
                    if off > 50 then off = 18.0 end
                    ty = tdata.staff_top_y - (off * s)
                else
                    ty = staff_bottom_y + (cur_offset_y * s)
                end
                
                local font_to_use = font_italic or font_main
                local st = tostring(ti.style or "italic"):lower()
                if st == "bold" then
                    font_to_use = font_bold or font_big or font_main
                elseif st == "bold_italic" or st == "bold italic" then
                    font_to_use = font_bold_italic or font_bold or font_italic or font_main
                elseif st == "regular" then
                    font_to_use = font_main
                elseif st == "italic" then
                    font_to_use = font_italic or font_main
                end
                
                local font_sz = math.max(10.0, math.floor((ti.font_size or 16.0) * s + 0.5))
                local text_str = tostring(ti.text or "")
                local txt_w = #text_str * (font_sz * 0.55)
                local txt_h = font_sz
                local cur_fs = reaper.APIExists("ImGui_GetFontSize") and reaper.ImGui_GetFontSize(ctx) or 14.0
                if not cur_fs or cur_fs <= 0 then cur_fs = 14.0 end
                local cw, ch = FontManager.calc_text_size(ctx, text_str)
                if cw and cw > 0 then
                    txt_w = cw * (font_sz / cur_fs)
                end
                if ch and ch > 0 then
                    txt_h = ch * (font_sz / cur_fs)
                end
                
                local bx0 = tx - 4 * s
                local by0 = ty - 2 * s
                local bx1 = tx + txt_w + 4 * s
                local by1 = ty + txt_h + 2 * s
                
                local is_selected = (state.selected_text_item and state.selected_text_item.id == ti.id) or (state.selected_text_items and state.selected_text_items[ti.id] ~= nil)
                local is_editing  = (state.editing_text_item and state.editing_text_item.id == ti.id)
                local is_dragged  = (state.is_dragging_text_item and state.drag_text_item and state.drag_text_item.id == ti.id)
                
                local in_box = (mouse_x >= bx0 and mouse_x <= bx1 and mouse_y >= by0 and mouse_y <= by1)
                local can_hover = is_hovered and not is_editing and not state.is_dragging and not state.is_dragging_dynamic and not state.is_dragging_hairpin and not state.is_dragging_pedal and not state.is_dragging_articulation and not state.is_resizing_item
                
                if can_hover and in_box then
                    text_item_hovered_this_frame = ti
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                end
                local is_hov = (text_item_hovered_this_frame and text_item_hovered_this_frame.id == ti.id)
                
                -- Double-click: opens inline text editor
                if is_hov and reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then
                    state:clear_selection()
                    state.selected_text_item = ti
                    state.editing_text_item = ti
                    state.editing_text_str = text_str
                    state.editing_text_just_opened = true
                    state.is_dragging_text_item = false
                    state.drag_text_item = nil
                end
                
                -- Right-click: opens context menu
                if is_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
                    state:clear_selection()
                    state.selected_text_item = ti
                    state.context_text_item = ti
                    reaper.ImGui_OpenPopup(ctx, "text_item_context_popup")
                end
                
                -- Background / border on selection, hover, or drag
                if is_selected or is_hov or is_dragged then
                    local bg_col = is_dragged and 0x3498DB44 or (is_selected and 0x3498DB22 or 0x3498DB11)
                    local bdr_col = is_selected and 0x3498DBFF or (is_dragged and 0x2980B9FF or 0x3498DB88)
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, bx0, by0, bx1, by1, bg_col, 3.0)
                    reaper.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, bdr_col, 3.0, 0, 1.2 * s)
                end
                
                -- Inline text input when in edit mode
                if is_editing then
                    reaper.ImGui_SetCursorScreenPos(ctx, bx0, by0)
                    reaper.ImGui_SetNextItemWidth(ctx, math.max(100 * s, txt_w + 30 * s))
                    if state.editing_text_just_opened then
                        reaper.ImGui_SetKeyboardFocusHere(ctx)
                        state.editing_text_just_opened = false
                    end
                    local enter_pressed, new_txt = reaper.ImGui_InputText(ctx, "##inline_ti_" .. ti.id, state.editing_text_str or text_str, reaper.ImGui_InputTextFlags_EnterReturnsTrue() | reaper.ImGui_InputTextFlags_AutoSelectAll())
                    if new_txt ~= nil then
                        state.editing_text_str = new_txt
                    end
                    
                    -- Confirm with Enter or cancel with Escape
                    if enter_pressed then
                        TextItemService.update_text(state, ti.id, state.editing_text_str)
                        state.editing_text_item = nil
                        state.editing_text_str = nil
                    elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
                        state.editing_text_item = nil
                        state.editing_text_str = nil
                    elseif reaper.ImGui_IsMouseClicked(ctx, 0) and not in_box and not reaper.ImGui_IsItemActive(ctx) then
                        TextItemService.update_text(state, ti.id, state.editing_text_str)
                        state.editing_text_item = nil
                        state.editing_text_str = nil
                    end
                else
                    -- Draw text
                    local text_col = is_selected and 0x2980B9FF or (is_hov and 0x3498DBFF or (state.invert_mode and 0xEEEEEEFF or 0x1A1A1AFF))
                    local drew_txt = false
                    if reaper.APIExists("ImGui_DrawList_AddTextEx") and font_to_use then
                        drew_txt = pcall(reaper.ImGui_DrawList_AddTextEx, draw_list, font_to_use, font_sz, tx, ty, text_col, text_str)
                    end
                    if not drew_txt then
                        reaper.ImGui_DrawList_AddText(draw_list, tx, ty, text_col, text_str)
                    end
                end
            end
        end

        end -- is_track_vis_y
        
        cur_band_top = cur_band_top + single_band_h
    end
    -- Barlines per instrument/staff (not connected across distinct instruments!)
    local bar_top_y = (first_staff_top_y or (score_top_y + 24 * s)) - (4 * s)
    local bar_btm_y = (last_staff_bottom_y or (score_bottom_y - 40 * s)) + (4 * s)
    local bar_col = Constants.COLORS.barline or 0x000000FF
    
    local start_m = math.max(0, vis_min_measure - 1)
    local end_m = math.min(total_measures, vis_max_measure + 1)
    for m = start_m, end_m do
        local mx = (measure_map and measure_map.starts and measure_map.starts[m]) or (margin_left + (m * measure_w))
        if mx >= cull_min_x - 10 * s and mx <= cull_max_x + 10 * s and mx <= staff_end_x then
            local is_key_change = (measure_map and measure_map.key_changes and measure_map.key_changes[m])
            
            -- Barline per instrument (only within respective staff and visible track)
            for t_idx, tdata in ipairs(active_tracks_data) do
                if tdata.is_visible_vertically and tdata.staff_top_y and tdata.staff_bottom_y then
                    local trk_info = is_key_change and is_key_change.tracks and (is_key_change.tracks[tdata] or is_key_change.tracks[tdata.track] or (tdata.guid and is_key_change.tracks[tdata.guid]) or is_key_change.tracks[t_idx])
                    if not trk_info and is_key_change then
                        local eff_c = resolve_effective_key(state, tdata.track, nil, (m + 0.5) * qn_per_measure)
                        local eff_p = resolve_effective_key(state, tdata.track, nil, (m - 0.5) * qn_per_measure)
                        trk_info = { curr_idx = eff_c, prev_idx = eff_p }
                    end
                    local has_this_trk_change = trk_info and (trk_info.curr_idx ~= trk_info.prev_idx)
                    if (is_key_change and m > 0) and (has_this_trk_change or trk_info == nil) then
                        -- Thin double barline before key change per Gould/Read
                        reaper.ImGui_DrawList_AddLine(draw_list, mx - 4.0 * s, tdata.staff_top_y, mx - 4.0 * s, tdata.staff_bottom_y, bar_col, 1.8 * s)
                        reaper.ImGui_DrawList_AddLine(draw_list, mx, tdata.staff_top_y, mx, tdata.staff_bottom_y, bar_col, 1.8 * s)
                    else
                        reaper.ImGui_DrawList_AddLine(draw_list, mx, tdata.staff_top_y, mx, tdata.staff_bottom_y, bar_col, 1.8 * s)
                    end
                end
            end
            
            -- Draw key change signature directly following the double barline
            if is_key_change and m > 0 then
                local kx = mx + 5.0 * s
                for t_idx, tdata in ipairs(active_tracks_data) do
                    if tdata.is_visible_vertically and tdata.staff_bottom_y then
                        local trk_info = is_key_change.tracks and (is_key_change.tracks[tdata] or is_key_change.tracks[tdata.track] or (tdata.guid and is_key_change.tracks[tdata.guid]) or is_key_change.tracks[t_idx])
                        if not trk_info then
                            local eff_c = resolve_effective_key(state, tdata.track, nil, (m + 0.5) * qn_per_measure)
                            local eff_p = resolve_effective_key(state, tdata.track, nil, (m - 0.5) * qn_per_measure)
                            trk_info = { curr_idx = eff_c, prev_idx = eff_p }
                        end
                        local new_k = trk_info and trk_info.curr_idx
                        local prev_k = trk_info and trk_info.prev_idx or 0
                        local cdef = Constants.CLEF_DEFS and Constants.CLEF_DEFS[tdata.clef]
                        local is_unpitched = cdef and cdef.unpitched
                        
                        if not is_unpitched and new_k ~= nil and new_k ~= prev_k then
                            local l_spacing = tdata.line_spacing or (8.0 * s)
                            local cancel_k = (new_k == 0 and prev_k ~= 0) and prev_k or nil
                            if tdata.is_harp then
                                Engraver.draw_key_signature(draw_list, new_k, kx, tdata.treble_bottom_y, l_spacing, s, bar_col, font_music, "treble", cancel_k)
                                Engraver.draw_key_signature(draw_list, new_k, kx, tdata.mid_bottom_y, l_spacing, s, bar_col, font_music, "alto", cancel_k)
                                Engraver.draw_key_signature(draw_list, new_k, kx, tdata.bass_bottom_y, l_spacing, s, bar_col, font_music, "bass", cancel_k)
                            elseif tdata.is_grand then
                                Engraver.draw_key_signature(draw_list, new_k, kx, tdata.treble_bottom_y, l_spacing, s, bar_col, font_music, "treble", cancel_k)
                                Engraver.draw_key_signature(draw_list, new_k, kx, tdata.bass_bottom_y, l_spacing, s, bar_col, font_music, "bass", cancel_k)
                            else
                                local s_clef = (tdata.clef == "bass" and "bass") or (tdata.clef == "alto" and "alto") or "treble"
                                Engraver.draw_key_signature(draw_list, new_k, kx, tdata.staff_bottom_y, l_spacing, s, bar_col, font_music, s_clef, cancel_k)
                            end
                        end
                    end
                end
            end
            -- Bar number above each staff system
            if (state.show_bar_numbers ~= false) then
                local bar_num_col = Constants.COLORS.bar_num or 0x5BC0DEFF
                local bar_num_off_y = (50.0 + (state.bar_num_offset_y or 0.0)) * s
                local bar_num_off_x = (state.bar_num_offset_x or 0.0) * s
                local bar_num_sz = (state.bar_num_size or 14.0) * s
                for _, tdata in ipairs(active_tracks_data) do
                    if tdata.is_visible_vertically and tdata.staff_top_y then
                        local bx = mx + 4*s + bar_num_off_x
                        local by = tdata.staff_top_y - bar_num_off_y
                        local drew = false
                        if reaper.APIExists("ImGui_DrawList_AddTextEx") and font_main then
                            local ok = pcall(reaper.ImGui_DrawList_AddTextEx, draw_list, font_main, bar_num_sz, bx, by, bar_num_col, tostring(m + 1))
                            drew = ok
                        end
                        if not drew then
                            reaper.ImGui_DrawList_AddText(draw_list, bx, by, bar_num_col, tostring(m + 1))
                        end
                    end
                end
            end
            
            -- Measure repeat mark (simile / repeat-bar %, repeat1Bar)
            local mx_next = (measure_map and measure_map.starts and measure_map.starts[m + 1]) or (margin_left + ((m + 1) * measure_w))
            local rep_cx = (mx + mx_next) / 2
            
            for _, tdata in ipairs(active_tracks_data) do
                if tdata.is_visible_vertically and tdata.staff_bottom_y then
                    local has_rep, rep_mark = RepeatService.has_repeat_mark(state, tdata.guid, m)
                    if has_rep then
                        local l_spacing = tdata.line_spacing or (8.0 * s)
                        local rep_cy
                        if tdata.is_grand then
                            rep_cy = (tdata.treble_bottom_y or (tdata.staff_top_y + 32 * s)) - (2 * l_spacing)
                        else
                            rep_cy = tdata.staff_bottom_y - (2 * l_spacing)
                        end
                        
                        local is_rep_hov = is_hovered and (math.abs(mouse_x - rep_cx) <= 20 * s and math.abs(mouse_y - rep_cy) <= 20 * s)
                        if is_rep_hov then
                            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                            reaper.ImGui_DrawList_AddCircle(draw_list, rep_cx, rep_cy, 18 * s, Constants.COLORS.selection_gold, 0, 2.0 * s)
                            local src_m = RepeatService.find_source_measure(state, tdata.guid, m)
                            local src_info = src_m and string.format("Repeats Bar %d", src_m + 1) or "No source bar"
                            reaper.ImGui_SetTooltip(ctx, string.format("Bar %d: Repeat Mark (%%)\n%s\nRight-click for options", m + 1, src_info))
                            
                            if reaper.ImGui_IsMouseClicked(ctx, 1) then
                                state.context_repeat_mark = rep_mark
                                state.context_repeat_track = tdata.track
                                reaper.ImGui_OpenPopup(ctx, "repeat_mark_context_popup")
                            end
                        end
                        
                        local rep_col = is_rep_hov and Constants.COLORS.selection_gold or (Constants.COLORS.notehead_black or 0x111111FF)
                        Engraver.draw_repeat_mark(draw_list, rep_cx, rep_cy, s, rep_col, font_music, rep_mark.type or "1bar")
                        
                        if tdata.is_grand and tdata.bass_bottom_y then
                            local rep_cy_bass = tdata.bass_bottom_y - (2 * l_spacing)
                            Engraver.draw_repeat_mark(draw_list, rep_cx, rep_cy_bass, s, rep_col, font_music, rep_mark.type or "1bar")
                        end
                    end
                    
                    -- Context menu for measure (right-click in measure header area)
                    local bar_num_off_y = (50.0 + (state.bar_num_offset_y or 0.0)) * s
                    local is_bar_hdr_hov = is_hovered and (mouse_x >= mx and mouse_x <= mx_next and mouse_y >= (tdata.staff_top_y - bar_num_off_y - 8 * s) and mouse_y <= (tdata.staff_top_y + 4 * s))
                    if is_bar_hdr_hov and reaper.ImGui_IsMouseClicked(ctx, 1) then
                        state.context_measure = m
                        state.context_measure_track = tdata.track
                        reaper.ImGui_OpenPopup(ctx, "measure_header_context_popup")
                    end
                end
            end
        end
    end
    
    -- Ties: ONLY for split segments of the EXACT same original MIDI note across barlines!
    -- NO automatic chaining of different notes that simply lie sequentially!
    local drawn_ties = {}
    for _, bt in ipairs(all_bar_ties) do
        local nd1 = all_note_render_by_key[bt.from_key]
        local nd2 = all_note_render_by_key[bt.to_key]
        if nd1 and nd2 and nd1.track == nd2.track then
            local tie_min_x = math.min(nd1.nx, nd2.nx)
            local tie_max_x = math.max(nd1.nx, nd2.nx)
            if tie_max_x >= cull_min_x and tie_min_x <= cull_max_x and nd1.ny >= cull_min_y and nd1.ny <= cull_max_y then
                -- Strict: both segments must verifiably belong to the same original note (identical orig or take & idx)
                local is_same_note = false
                if bt.orig and (nd1.orig == bt.orig or nd2.orig == bt.orig) then
                    is_same_note = true
                elseif nd1.orig and nd2.orig and nd1.orig == nd2.orig then
                    is_same_note = true
                elseif nd1.take and nd2.take and nd1.take == nd2.take and nd1.idx and nd2.idx and nd1.idx == nd2.idx then
                    is_same_note = true
                end
                
                if is_same_note and math.abs(nd1.ny - nd2.ny) <= 16*s then
                    local tie_key = bt.from_key .. "->" .. bt.to_key
                    if not drawn_ties[tie_key] then
                        drawn_ties[tie_key] = true
                        local is_ghost_tie = (nd1.is_ghost_voice == true) or (nd2.is_ghost_voice == true)
                        local tie_col = 0x1A1A1AFF
                        if is_ghost_tie then
                            local t_v = (nd1.orig and nd1.orig.chan or 0) + 1
                            if (state.voice_color_mode ~= false) and t_v > 1 and Constants.VOICE_COLORS and Constants.VOICE_COLORS[t_v] then
                                tie_col = (Constants.VOICE_COLORS[t_v] & 0xFFFFFF00) | ghost_alpha_byte
                            else
                                tie_col = global_ghost_col
                            end
                        end
                        local tie_above = (nd1.stem_down == true) or (nd1.dstep and nd1.dstep >= 4)
                        Engraver.draw_tie(draw_list, nd1.nx, nd1.ny, nd2.nx, nd2.ny, s, tie_col, tie_above)
                    end
                end
            end
        end
    end
    
    -- ======================================================================
    -- TEMPO, OCTAVE & CHORD LANE (Delegated to CanvasDecorations)
    -- ======================================================================
    if CanvasDecorations then
        CanvasDecorations.draw_tempo_markers(ctx, draw_list, state, fonts, first_staff_top_y, s, margin_left, system_start_x, qn_per_measure, measure_map, vis_min_qn, vis_max_qn, is_hovered, mouse_x, mouse_y, hov)
        CanvasDecorations.draw_octave_lines(ctx, draw_list, state, fonts, active_tracks_data, s, margin_left, qn_per_measure, measure_map, vis_min_qn, vis_max_qn, is_hovered, mouse_x, mouse_y, is_ctrl, hov)
        CanvasDecorations.draw_chord_scale_lane(ctx, draw_list, state, fonts, s, canvas_p0_x, canvas_p0_y, staff_end_x, margin_left, system_start_x, hdr_x0, hdr_x1, qn_per_measure, measure_map, cull_min_x, cull_max_x, cull_min_y, cull_max_y, is_hovered, mouse_x, mouse_y, is_shift, hov)
        CanvasDecorations.draw_rehearsal_lane(ctx, draw_list, state, fonts, s, canvas_p0_x, canvas_p0_y, staff_end_x, margin_left, system_start_x, hdr_x0, hdr_x1, qn_per_measure, measure_map, cull_min_x, cull_max_x, is_hovered, mouse_x, mouse_y, hov)
        CanvasDecorations.draw_fermatas(ctx, draw_list, state, fonts, active_tracks_data, s, margin_left, qn_per_measure, measure_map, cull_min_x, cull_max_x, is_hovered, mouse_x, mouse_y, hov)
    end
    
    if hov then
        if hov.tempo then tempo_hovered_this_frame = hov.tempo end
        if hov.octave then octave_hovered_this_frame = hov.octave end
        if hov.chord then chord_hovered_this_frame = hov.chord end
        if hov.chord_handle then chord_handle_hovered_this_frame = hov.chord_handle end
    end
    
    state.hovered_hairpin = hairpin_hovered_this_frame
    state.hovered_hairpin_handle = hairpin_handle_hovered_this_frame
    if hairpin_handle_hovered_this_frame == "start" or hairpin_handle_hovered_this_frame == "end" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
    elseif hairpin_handle_hovered_this_frame == "body" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end
    
    state.hovered_dynamic_text = dynamic_text_hovered_this_frame
    state.hovered_dynamic_text_handle = dynamic_text_handle_hovered_this_frame
    if dynamic_text_handle_hovered_this_frame == "start" or dynamic_text_handle_hovered_this_frame == "end" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_ResizeEW())
    elseif dynamic_text_handle_hovered_this_frame == "body" then
        reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
    end
    
    -- ======================================================================
    -- 10. TRACK HEADER OVERLAY PASS (Sticky Pinning & 24px Gradient Masking)
    -- ======================================================================
    if (state.show_track_headers ~= false) then
        local paper_bg = state.invert_mode and 0x1E1E1EFF or (Constants.COLORS.paper_bg or 0xFAF8F5FF)
        local paper_bg_trans = paper_bg & 0xFFFFFF00
        local fade_w = 48.0 * s
        local orig_hdr_x0 = canvas_p0_x + 6 * s

        for _, tdata in ipairs(active_tracks_data) do
            if tdata.is_visible_vertically and tdata.staff_top_y and tdata.staff_bottom_y then
                local hdr_y0 = tdata.staff_top_y - 8 * s
                local hdr_y1 = tdata.staff_bottom_y + 8 * s
                
                local is_scrolled = (state.sticky_track_headers ~= false) and (win_x0 > orig_hdr_x0)
                local cur_hdr_x0 = is_scrolled and (win_x0 + 4 * s) or orig_hdr_x0
                local cur_hdr_x1 = cur_hdr_x0 + hdr_w
                
                -- When scrolled: full track coverage + wide transparent gradient on right (completely masks notes, lines, dynamics, hairpins & articulations)
                if is_scrolled then
                    local cover_x0 = win_x0
                    local cover_x1 = cur_hdr_x1 + 4 * s
                    local cover_y0 = (tdata.band_y0 or (hdr_y0 - 16 * s)) - 1 * s
                    local cover_y1 = (tdata.band_y1 or (hdr_y1 + 16 * s)) + 1 * s
                    
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, cover_x0, cover_y0, cover_x1, cover_y1, paper_bg)
                    
                    if reaper.APIExists("ImGui_DrawList_AddRectFilledMultiColor") then
                        reaper.ImGui_DrawList_AddRectFilledMultiColor(draw_list, cover_x1, cover_y0, cover_x1 + fade_w, cover_y1, paper_bg, paper_bg_trans, paper_bg_trans, paper_bg)
                    else
                        local slices = 16
                        local slice_w = fade_w / slices
                        local r = (paper_bg >> 24) & 0xFF
                        local g = (paper_bg >> 16) & 0xFF
                        local b = (paper_bg >> 8) & 0xFF
                        for i = 0, slices - 1 do
                            local alpha = math.floor(255 * (1 - (i / slices)))
                            local col = (r << 24) | (g << 16) | (b << 8) | alpha
                            reaper.ImGui_DrawList_AddRectFilled(draw_list, cover_x1 + i * slice_w, cover_y0, cover_x1 + (i + 1) * slice_w, cover_y1, col)
                        end
                    end
                end
                
                local is_focused = (state.focused_track == tdata.track)
                local hdr_bg = is_focused and 0xFF9F1C28 or reaper_color_to_rgba(tdata.col, 0x24)
                local border_col = is_focused and 0xFF9F1CFF or reaper_color_to_rgba(tdata.col, 0x88)
                local border_thick = is_focused and (2.2 * s) or (1.2 * s)
                
                -- Header background & border
                reaper.ImGui_DrawList_AddRectFilled(draw_list, cur_hdr_x0, hdr_y0, cur_hdr_x1, hdr_y1, hdr_bg, 4)
                reaper.ImGui_DrawList_AddRect(draw_list, cur_hdr_x0, hdr_y0, cur_hdr_x1, hdr_y1, border_col, 4, 0, border_thick)
                
                -- Left color bar (track color accent strip)
                local stripe_w = is_focused and (6 * s) or (4 * s)
                reaper.ImGui_DrawList_AddRectFilled(draw_list, cur_hdr_x0, hdr_y0, cur_hdr_x0 + stripe_w, hdr_y1, reaper_color_to_rgba(tdata.col, 0xFF), 2)
                
                -- Track title with track number [1] Track Name (high-contrast & clean legibility)
                local title_col = state.invert_mode and (is_focused and 0xFFFFFFFF or 0xEEEEEEFF) or (is_focused and 0x111111FF or 0x222222FF)
                local d_name = tdata.name or "Track"
                if #d_name > 15 then d_name = d_name:sub(1, 13) .. ".." end
                local trk_lbl = string.format("[%d] %s", tdata.idx, d_name)
                reaper.ImGui_DrawList_AddText(draw_list, cur_hdr_x0 + stripe_w + 5 * s, hdr_y0 + 5 * s, title_col, trk_lbl)
                
                -- Subtitle: item count & clefs (muted gray)
                local clef_lbl = (tdata.clef == "grand") and "Grand" or ((tdata.clef == "bass") and "Bass" or ((tdata.clef == "harp_3staff") and "Harp" or "Treble"))
                local sub_lbl = string.format("%d Items • %s", tdata.items and #tdata.items or 0, clef_lbl)
                local sub_col = state.invert_mode and 0xAAAAAAFF or 0x666666FF
                reaper.ImGui_DrawList_AddText(draw_list, cur_hdr_x0 + stripe_w + 5 * s, hdr_y0 + 20 * s, sub_col, sub_lbl)
                
                -- Clicking track header selects & focuses the track (dynamically sized tooltip without clipping)
                local is_hdr_hov = is_hovered and (mouse_x >= cur_hdr_x0 and mouse_x <= cur_hdr_x1 and mouse_y >= hdr_y0 and mouse_y <= hdr_y1)
                if is_hdr_hov then
                    reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
                    local tip = string.format("Track [%d]: %s (%d Items)\nClick: Focus track & select in REAPER", tdata.idx, tdata.name or "Track", tdata.items and #tdata.items or 0)
                    local cw, ch = FontManager.calc_text_size(ctx, tip)
                    local tw = math.max(260, cw + 22)
                    local th = ch + 14
                    local box_x0 = mouse_x + 14
                    local box_y0 = mouse_y - th - 6
                    if box_y0 < (win_y0 + 10) then
                        box_y0 = mouse_y + 20
                    end
                    local box_x1 = box_x0 + tw
                    local box_y1 = box_y0 + th
                    reaper.ImGui_DrawList_AddRectFilled(draw_list, box_x0, box_y0, box_x1, box_y1, 0x111111F0, 4)
                    reaper.ImGui_DrawList_AddRect(draw_list, box_x0, box_y0, box_x1, box_y1, 0xFF9F1CAA, 4, 0, 1.0)
                    reaper.ImGui_DrawList_AddText(draw_list, box_x0 + 11, box_y0 + 7, 0xFF9F1CFF, tip)
                    
                    if reaper.ImGui_IsMouseClicked(ctx, 0) and not is_ctrl then
                        state.focused_track = tdata.track
                        if tdata.track and reaper.ValidatePtr(tdata.track, "MediaTrack*") then
                            reaper.SetOnlyTrackSelected(tdata.track)
                        end
                        state.status_msg = string.format("Track [%d] %s selected & focused", tdata.idx, tdata.name)
                    end
                end
            end
        end
    end
    
    -- MOUSE DRAW PREVIEW (Continuous ghost note in Write Notes mode [D])
    if state.input_mode_type == "draw" and not state.is_dragging and is_hovered then
        local draw_trk = nil
        for _, tdata in ipairs(active_tracks_data) do
            if tdata.band_y0 and tdata.band_y1 and mouse_y >= tdata.band_y0 and mouse_y <= tdata.band_y1 then
                draw_trk = tdata
                break
            end
        end
        
        if draw_trk and draw_trk.band_y0 then
            local line_spacing = 8.0 * s
            local step_y = line_spacing / 2.0
            local treble_bot = draw_trk.treble_bottom_y or (draw_trk.band_y0 and (draw_trk.band_y0 + 72 * s)) or (72 * s)
            local bass_bot = draw_trk.bass_bottom_y or (draw_trk.is_grand and (draw_trk.band_y0 and (draw_trk.band_y0 + 148 * s) or (148 * s)) or (draw_trk.band_y0 and (draw_trk.band_y0 + 80 * s) or (80 * s)))
            local mid_bot = draw_trk.mid_bottom_y
            
            local snap_grid = is_shift and 0.001 or (state.display_quantize and state.display_quantize_grid) or state.grid_qn or 0.25
            local target_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, snap_grid, measure_map)
            target_qn = math.max(0, target_qn)
            
            local target_pitch, in_tr = Engraver.canvas_y_to_pitch(mouse_y, treble_bot, bass_bot, step_y, draw_trk.is_grand, draw_trk.clef, state.accidental, mid_bot)
            target_pitch = math.max(0, math.min(127, target_pitch or 60))
            
            local active_dur = state.active_dur or 1.0
            state.draw_preview = {
                trk = draw_trk,
                track = draw_trk.track,
                qn = target_qn,
                pitch = target_pitch,
                dur = active_dur,
                accidental = state.accidental or 0
            }
            
            local gx = Engraver.qn_to_canvas_x(target_qn, margin_left, s, qn_per_measure, measure_map)
            local gy, _, dstep, _, staff_tgt = Engraver.pitch_to_canvas_y(target_pitch, treble_bot, bass_bot, step_y, draw_trk.is_grand, draw_trk.clef, state.accidental, mid_bot)
            
            -- Ledger lines
            local staff_bot = (staff_tgt == "treble") and treble_bot or ((staff_tgt == "alto") and mid_bot or bass_bot)
            local ledger_col = 0x2ECC71AA
            if dstep <= -2 then
                for step = -2, dstep, -2 do
                    local ly = staff_bot - (step * step_y)
                    reaper.ImGui_DrawList_AddLine(draw_list, gx - 10 * s, ly, gx + 10 * s, ly, ledger_col, 1.4 * s)
                end
            elseif dstep >= 10 then
                for step = 10, dstep, 2 do
                    local ly = staff_bot - (step * step_y)
                    reaper.ImGui_DrawList_AddLine(draw_list, gx - 10 * s, ly, gx + 10 * s, ly, ledger_col, 1.4 * s)
                end
            end
            
            -- Accidental glyph to the left of the notehead
            if state.accidental and state.accidental ~= 0 then
                local acc_sym = (state.accidental == 1) and "♯" or ((state.accidental == -1) and "♭" or "♮")
                reaper.ImGui_DrawList_AddText(draw_list, gx - 16 * s, gy - 8 * s, 0x2ECC71FF, acc_sym)
            end
            
            -- Glowing ghost note (emerald green for Write Notes)
            local fill_col = 0x2ECC7188
            local border_col = 0x2ECC71FF
            if active_dur >= 2.0 then
                reaper.ImGui_DrawList_AddCircleFilled(draw_list, gx, gy, 6.0 * s, 0x2ECC7133)
                reaper.ImGui_DrawList_AddCircle(draw_list, gx, gy, 7.5 * s, border_col, 0, 2.2 * s)
            else
                reaper.ImGui_DrawList_AddCircleFilled(draw_list, gx, gy, 7.5 * s, fill_col)
                reaper.ImGui_DrawList_AddCircle(draw_list, gx, gy, 8.5 * s, border_col, 0, 2.0 * s)
            end
            
            -- Augmentation dot preview
            if state.is_dotted then
                reaper.ImGui_DrawList_AddCircleFilled(draw_list, gx + 12 * s, gy - 2 * s, 2.2 * s, border_col)
            end
            
            -- Floating info badge beside mouse cursor
            local p_info = Constants.PITCH_MAP and Constants.PITCH_MAP[target_pitch % 12]
            local p_name = p_info and p_info.name or "C"
            local p_oct = math.floor(target_pitch / 12) - 1
            local bpi = qn_per_measure or 4.0
            local dur_str = state.dur_label or "1/4"
            if state.is_dotted then dur_str = dur_str .. "." end
            if state.tuplet_type then
                dur_str = dur_str .. " (T" .. tostring(state.tuplet_type) .. ")"
            elseif state.is_triplet then
                dur_str = dur_str .. "T"
            end
            
            local tip
            local bw
            if #active_tracks_data > 1 then
                local trk_name = draw_trk.name or "Track"
                if #trk_name > 12 then trk_name = trk_name:sub(1, 10) .. ".." end
                tip = string.format("[%s] %s%d | Measure %.2f (%s)", trk_name, p_name, p_oct, (target_qn / bpi) + 1, dur_str)
                bw = 180 * s
            else
                tip = string.format("%s%d | Measure %.2f (%s)", p_name, p_oct, (target_qn / bpi) + 1, dur_str)
                bw = 135 * s
            end
            
            local bh = 22 * s
            local bx = mouse_x + 16 * s
            local by = mouse_y - 26 * s
            reaper.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + bw, by + bh, 0x111111EE, 4)
            reaper.ImGui_DrawList_AddRect(draw_list, bx, by, bx + bw, by + bh, border_col, 4, 0, 1.2 * s)
            reaper.ImGui_DrawList_AddText(draw_list, bx + 7 * s, by + 3 * s, border_col, tip)
            
            reaper.ImGui_SetMouseCursor(ctx, reaper.ImGui_MouseCursor_Hand())
        else
            state.draw_preview = nil
        end
    elseif state.input_mode_type ~= "draw" then
        state.draw_preview = nil
    end

    -- DRAG PREVIEW (Ghost notes & position badge during move)
    if state.is_dragging and state.drag_note and #state.drag_selected_snapshot > 0 then
        local delta_qn = state.drag_delta_qn or 0
        local delta_pitch = state.drag_delta_pitch or 0
        local bpi = qn_per_measure or 4
        
        for _, sn in ipairs(state.drag_selected_snapshot) do
            local ghost_qn = (sn.start_qn or 0) + delta_qn
            local ghost_pitch = math.max(0, math.min(127, (sn.pitch or 60) + delta_pitch))
            local gx = Engraver.qn_to_canvas_x(ghost_qn, margin_left, s, qn_per_measure, measure_map)
            
            -- Find the note's track
            local ghost_trk = nil
            for _, tdata in ipairs(active_tracks_data) do
                if tdata.track == sn.track then
                    ghost_trk = tdata
                    break
                end
            end
            ghost_trk = ghost_trk or active_tracks_data[1]
            
            if ghost_trk then
                local line_spacing = 8.0 * s
                local step_y = line_spacing / 2.0
                local treble_bot = ghost_trk.treble_bottom_y or (ghost_trk.band_y0 and (ghost_trk.band_y0 + 72 * s)) or (72 * s)
                local bass_bot = ghost_trk.bass_bottom_y or (ghost_trk.is_grand and (ghost_trk.band_y0 and (ghost_trk.band_y0 + 148 * s) or (148 * s)) or (ghost_trk.band_y0 and (ghost_trk.band_y0 + 80 * s) or (80 * s)))
                local gy = Engraver.pitch_to_canvas_y(ghost_pitch, treble_bot, bass_bot, step_y, ghost_trk.is_grand, ghost_trk.clef, nil, ghost_trk.mid_bottom_y)
                
                -- Glowing semi-transparent gold-orange ghost note with outline
                reaper.ImGui_DrawList_AddCircleFilled(draw_list, gx, gy, 7.5 * s, 0xFF9F1C88)
                reaper.ImGui_DrawList_AddCircle(draw_list, gx, gy, 8.5 * s, 0xFF9F1CFF, 0, 2.0 * s)
            end
        end
        
        -- Tooltip box beside mouse cursor with target pitch and measure position
        local base_pitch = (state.drag_note and state.drag_note.pitch) or 60
        local target_pitch = math.max(0, math.min(127, base_pitch + delta_pitch))
        local p_info = Constants.PITCH_MAP and Constants.PITCH_MAP[target_pitch % 12]
        local p_name = p_info and p_info.name or "C"
        local p_oct = math.floor(target_pitch / 12) - 1
        local base_qn = (state.drag_note and state.drag_note.start_qn) or 0
        local target_qn = math.max(0, base_qn + delta_qn)
        local tip = string.format("%s%d | Measure %.2f", p_name, p_oct, (target_qn / bpi) + 1)
        
        local bw = 120 * s
        local bh = 22 * s
        local bx = mouse_x + 16 * s
        local by = mouse_y - 26 * s
        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + bw, by + bh, 0x111111EE, 4)
        reaper.ImGui_DrawList_AddRect(draw_list, bx, by, bx + bw, by + bh, 0xFF9F1CFF, 4, 0, 1.2 * s)
        reaper.ImGui_DrawList_AddText(draw_list, bx + 8 * s, by + 3 * s, 0xFF9F1CFF, tip)
    end

    -- DRAG PREVIEW FOR DYNAMICS (Ghost dynamic, measure guideline & position badge)
    if state.is_dragging_dynamic and state.drag_dynamic then
        local d = state.drag_dynamic
        local target_qn = state.drag_dyn_target_qn or d.qn
        local gx = Engraver.qn_to_canvas_x(target_qn, margin_left, s, qn_per_measure, measure_map)
        local gy = d.base_y or (bar_btm_y - 20 * s)
        
        -- Vertical grid guideline
        reaper.ImGui_DrawList_AddLine(draw_list, gx, bar_top_y, gx, bar_btm_y + 10 * s, 0xFF9F1C88, 1.5 * s)
        
        -- Ghost dynamic badge
        local dyn_font_sz = math.floor(34 * s + 0.5)
        local glyph, dyn_w, clean_lbl = get_dynamic_glyph_and_width(d.label, dyn_font_sz)
        local badge_half_w = math.max(16 * s, (dyn_w / 2) + 6 * s)
        local bx0, bx1 = gx - badge_half_w, gx + badge_half_w
        local by0, by1 = gy - 16 * s, gy + 14 * s
        
        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx0, by0, bx1, by1, 0xFF9F1C66, 4)
        reaper.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, 0xFF9F1CFF, 4, 0, 2.0 * s)
        
        if glyph and font_music and reaper.APIExists("ImGui_DrawList_AddTextEx") then
            local pos_x = gx - (dyn_w / 2)
            local pos_y = gy - (dyn_font_sz * 2.012)
            reaper.ImGui_DrawList_AddTextEx(draw_list, font_music, dyn_font_sz, pos_x, pos_y, 0xFFFFFFFF, glyph)
        else
            reaper.ImGui_DrawList_AddText(draw_list, gx - (#d.label * 5.5 * s), gy - 10 * s, 0xFFFFFFFF, d.label)
        end
        
        -- Tooltip box beside mouse cursor
        local bpi = qn_per_measure or 4
        local tip = string.format("Dynamic: %s | Measure %.2f", d.label, (target_qn / bpi) + 1)
        local bw = (#tip * 7.5 * s) + 16 * s
        local bh = 22 * s
        local bx = mouse_x + 16 * s
        local by = mouse_y - 26 * s
        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + bw, by + bh, 0x111111EE, 4)
        reaper.ImGui_DrawList_AddRect(draw_list, bx, by, bx + bw, by + bh, 0xFF9F1CFF, 4, 0, 1.2 * s)
        reaper.ImGui_DrawList_AddText(draw_list, bx + 8 * s, by + 3 * s, 0xFF9F1CFF, tip)
    end

    -- DRAG PREVIEW FOR ARTICULATIONS (Ghost badge, measure guideline & position badge)
    if state.is_dragging_articulation and state.drag_articulation then
        local art = state.drag_articulation
        local target_qn = state.drag_art_target_qn or art.qn
        local gx = Engraver.qn_to_canvas_x(target_qn, margin_left, s, qn_per_measure, measure_map)
        local gy = art.base_y or (bar_top_y - 12 * s)
        
        -- Vertical grid guideline (in turquoise/cyan)
        reaper.ImGui_DrawList_AddLine(draw_list, gx, bar_top_y, gx, bar_btm_y + 10 * s, 0x1ABC9C99, 1.5 * s)
        
        -- Ghost articulation badge
        local label = art.label or ("PC " .. tostring(art.pc))
        local txt_w = math.max(28 * s, #label * 7.5 * s)
        local bx0 = gx - (txt_w / 2) - 4 * s
        local bx1 = gx + (txt_w / 2) + 4 * s
        local by0 = gy - 11 * s
        local by1 = gy + 11 * s
        
        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx0, by0, bx1, by1, 0x16A08588, 4)
        reaper.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, 0x1ABC9CFF, 4, 0, 2.0 * s)
        reaper.ImGui_DrawList_AddText(draw_list, gx - (txt_w / 2), gy - 7.5 * s, 0xFFFFFFFF, label)
        
        -- Tooltip box beside mouse cursor
        local bpi = qn_per_measure or 4
        local tip = string.format("Articulation: %s | Measure %.2f", label, (target_qn / bpi) + 1)
        local bw = (#tip * 7.5 * s) + 16 * s
        local bh = 22 * s
        local bx = mouse_x + 16 * s
        local by = mouse_y - 26 * s
        reaper.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + bw, by + bh, 0x111111EE, 4)
        reaper.ImGui_DrawList_AddRect(draw_list, bx, by, bx + bw, by + bh, 0x1ABC9CFF, 4, 0, 1.2 * s)
        reaper.ImGui_DrawList_AddText(draw_list, bx + 8 * s, by + 3 * s, 0x1ABC9CFF, tip)
    end

    -- DRAG PREVIEW FOR TEMPO MARKERS (Guideline & position badge)
    if state.is_dragging_tempo and state.drag_tempo_marker then
        local tm = state.drag_tempo_marker
        local bpi = qn_per_measure or 4
        
        if tm.type == "absolute" then
            local target_qn = state.drag_tempo_target_qn or tm.start_qn
            local gx = Engraver.qn_to_canvas_x(target_qn, margin_left, s, qn_per_measure, measure_map)
            
            -- Vertical guideline (gold/orange)
            reaper.ImGui_DrawList_AddLine(draw_list, gx, bar_top_y, gx, bar_btm_y + 10 * s, 0xF39C12AA, 1.8 * s)
            
            -- Tooltip box beside mouse cursor
            local tip = string.format("Tempo: %s | Measure %.2f", tm:get_display_text(), (target_qn / bpi) + 1)
            local bw = (#tip * 7.5 * s) + 16 * s
            local bh = 22 * s
            local bx = mouse_x + 16 * s
            local by = mouse_y - 26 * s
            reaper.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + bw, by + bh, 0x111111EE, 4)
            reaper.ImGui_DrawList_AddRect(draw_list, bx, by, bx + bw, by + bh, 0xF39C12FF, 4, 0, 1.2 * s)
            reaper.ImGui_DrawList_AddText(draw_list, bx + 8 * s, by + 3 * s, 0xF39C12FF, tip)
        else
            -- Gradual tempo change
            local handle = state.drag_tempo_handle or "end"
            local cur_s = tm.start_qn
            local cur_e = tm.end_qn or (tm.start_qn + 4.0)
            if handle == "start" and state.drag_tempo_target_qn then
                cur_s = math.min(cur_e - 0.25, state.drag_tempo_target_qn)
            elseif handle == "end" and state.drag_tempo_target_qn then
                cur_e = math.max(cur_s + 0.25, state.drag_tempo_target_qn)
            elseif handle == "body" and state.drag_tempo_delta_qn then
                local span = cur_e - cur_s
                cur_s = math.max(0, tm.start_qn + state.drag_tempo_delta_qn)
                cur_e = cur_s + span
            end
            
            local active_qn = (handle == "end") and cur_e or cur_s
            local gx = Engraver.qn_to_canvas_x(active_qn, margin_left, s, qn_per_measure, measure_map)
            
            -- Vertical guideline at active handle position
            local line_col = (handle == "end") and 0x2ECC71AA or 0x3498DBAA
            reaper.ImGui_DrawList_AddLine(draw_list, gx, bar_top_y, gx, bar_btm_y + 10 * s, line_col, 1.8 * s)
            
            -- Tooltip box beside mouse cursor
            local dur_measures = (cur_e - cur_s) / bpi
            local tip = string.format("%s (%d ➔ %d BPM) | Measure %.2f ➔ %.2f (%.1f measures)",
                tm:get_display_text(), math.floor(tm.bpm or 120), math.floor(tm.target_bpm or 140),
                (cur_s / bpi) + 1, (cur_e / bpi) + 1, dur_measures)
            local bw = (#tip * 7.2 * s) + 16 * s
            local bh = 22 * s
            local bx = mouse_x + 16 * s
            local by = mouse_y - 26 * s
            local badge_bdr = (handle == "end") and 0x2ECC71FF or 0x3498DBFF
            reaper.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + bw, by + bh, 0x111111EE, 4)
            reaper.ImGui_DrawList_AddRect(draw_list, bx, by, bx + bw, by + bh, badge_bdr, 4, 0, 1.2 * s)
            reaper.ImGui_DrawList_AddText(draw_list, bx + 8 * s, by + 3 * s, badge_bdr, tip)
        end
    end

    -- Draw marquee selection box
    if state.marquee_active then
        reaper.ImGui_DrawList_AddRectFilled(draw_list, mrx0, mry0, mrx1, mry1, Constants.COLORS.marquee_box, 3)
        reaper.ImGui_DrawList_AddRect(draw_list, mrx0, mry0, mrx1, mry1, Constants.COLORS.marquee_border, 3, 0, 1.2 * s)
    end
    
    -- Playhead & edit cursor (solid orange triangular cap ▼ + continuous vertical line)
    local cur_cursor_qn = reaper.TimeMap2_timeToQN(0, cur_time)
    local cur_cx = Engraver.cursor_qn_to_canvas_x(cur_cursor_qn, margin_left, s, qn_per_measure, measure_map)
    
    local cursor_col = 0xFF9F1CFF
    local cursor_border = 0xD35400FF
    local tri_w = 7.5 * s
    local tri_h = 9.5 * s
    local top_cap_y = bar_top_y - 14 * s
    
    -- Downward-pointing cursor triangle (playhead cap ▼)
    reaper.ImGui_DrawList_AddTriangleFilled(draw_list, cur_cx - tri_w, top_cap_y, cur_cx + tri_w, top_cap_y, cur_cx, top_cap_y + tri_h, cursor_col)
    reaper.ImGui_DrawList_AddTriangle(draw_list, cur_cx - tri_w, top_cap_y, cur_cx + tri_w, top_cap_y, cur_cx, top_cap_y + tri_h, cursor_border, 1.2 * s)
    
    -- Vertical cursor line through all staves
    reaper.ImGui_DrawList_AddLine(draw_list, cur_cx, top_cap_y + tri_h - 1*s, cur_cx, bar_btm_y + 10 * s, cursor_col, 2.0 * s)
    
    if is_playing then
        local play_qn = reaper.TimeMap2_timeToQN(0, play_time)
        local play_cx = Engraver.cursor_qn_to_canvas_x(play_qn, margin_left, s, qn_per_measure, measure_map)
        local play_col = 0x2ECC71FF
        local play_border = 0x27AE60FF
        reaper.ImGui_DrawList_AddTriangleFilled(draw_list, play_cx - tri_w, top_cap_y - 2*s, play_cx + tri_w, top_cap_y - 2*s, play_cx, top_cap_y - 2*s + tri_h, play_col)
        reaper.ImGui_DrawList_AddTriangle(draw_list, play_cx - tri_w, top_cap_y - 2*s, play_cx + tri_w, top_cap_y - 2*s, play_cx, top_cap_y - 2*s + tri_h, play_border, 1.2 * s)
        reaper.ImGui_DrawList_AddLine(draw_list, play_cx, top_cap_y - 2*s + tri_h - 1*s, play_cx, bar_btm_y + 12 * s, play_col, 2.2 * s)
    end
    
    -- ======================================================================
    -- PATTERN DRAG & DROP GHOST-PREVIEW & DROP TARGET
    -- ======================================================================
    local mouse_in_canvas = (mouse_x >= win_x0 and mouse_x <= (win_x0 + win_w) 
                            and mouse_y >= win_y0 and mouse_y <= (win_y0 + win_h))
    
    if state.dragged_pattern and mouse_in_canvas then
        local pat = state.dragged_pattern
        local pat_bars = pat.bars or 4
        local pat_qn_per_measure = qn_per_measure or 4.0
        local total_pat_dur = pat_bars * pat_qn_per_measure
        
        -- Find hovered track on canvas
        local target_tdata = nil
        for _, tdata in ipairs(active_tracks_data or {}) do
            local top = tdata.band_y0 or (tdata.staff_top_y - 25 * s)
            local btm = tdata.band_y1 or ((tdata.staff_bottom_y or tdata.staff_top_y + 40 * s) + 35 * s)
            if mouse_y >= top and mouse_y <= btm then
                target_tdata = tdata
                break
            end
        end
        if not target_tdata and active_tracks_data and #active_tracks_data > 0 then
            target_tdata = active_tracks_data[1]
        end
        
        if target_tdata then
            -- Calculate quantized target position
            local raw_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
            local snapped_qn = math.floor(raw_qn / pat_qn_per_measure + 0.5) * pat_qn_per_measure
            if math.abs(raw_qn - snapped_qn) > 1.0 then
                snapped_qn = math.floor(raw_qn * 4 + 0.5) / 4
            end
            if snapped_qn < 0 then snapped_qn = 0 end
            
            local px0 = Engraver.qn_to_canvas_x(snapped_qn, margin_left, s, qn_per_measure, measure_map)
            local px1 = Engraver.qn_to_canvas_x(snapped_qn + total_pat_dur, margin_left, s, qn_per_measure, measure_map)
            local py0 = target_tdata.staff_top_y - 12 * s
            local py1 = target_tdata.staff_bottom_y + 12 * s
            
            -- Golden background area across entire pattern
            reaper.ImGui_DrawList_AddRectFilled(draw_list, px0, py0, px1, py1, 0xE67E2233, 4.0 * s)
            reaper.ImGui_DrawList_AddRect(draw_list, px0, py0, px1, py1, 0xE67E22FF, 4.0 * s, 0, 2.0 * s)
            
            -- Badge displaying pattern name & measure count
            local badge_txt = string.format("🎼 %s (%d Bars)", pat.name, pat_bars)
            local badge_w = #badge_txt * 7.5 * s
            reaper.ImGui_DrawList_AddRectFilled(draw_list, px0, py0 - 22 * s, px0 + badge_w + 12 * s, py0 - 2 * s, 0x1A1C23EE, 3.0 * s)
            reaper.ImGui_DrawList_AddRect(draw_list, px0, py0 - 22 * s, px0 + badge_w + 12 * s, py0 - 2 * s, 0xE67E22FF, 3.0 * s, 0, 1.0 * s)
            reaper.ImGui_DrawList_AddText(draw_list, px0 + 6 * s, py0 - 19 * s, 0xF39C12FF, badge_txt)
            
            -- Render pattern ghost noteheads
            local t_step_y = target_tdata.step_y or (7.0 * s)
            local t_clef = target_tdata.clef or "treble"
            local t_grand = target_tdata.is_grand
            local t_treble_bot = target_tdata.treble_bottom_y or target_tdata.staff_bottom_y
            local t_bass_bot = target_tdata.bass_bottom_y or target_tdata.staff_bottom_y
            
            for _, pn in ipairs(pat.notes or {}) do
                local nx = Engraver.qn_to_canvas_x(snapped_qn + pn.start_qn, margin_left, s, qn_per_measure, measure_map)
                local ny = Engraver.pitch_to_canvas_y(pn.pitch, t_treble_bot, t_bass_bot, t_step_y, t_grand, t_clef, 0, nil)
                if ny then
                    reaper.ImGui_DrawList_AddCircleFilled(draw_list, nx, ny, 4.5 * s, 0xF39C12FF)
                    reaper.ImGui_DrawList_AddLine(draw_list, nx + 3.0 * s, ny, nx + 3.0 * s, ny - 16 * s, 0xF39C12DD, 1.5 * s)
                end
            end
            
            -- Drop validation upon mouse release
            if reaper.ImGui_IsMouseReleased(ctx, 0) then
                PatternService.insert_pattern_into_track(target_tdata.track, snapped_qn, pat, midi_service)
                state.status_msg = string.format("Pattern '%s' inserted onto track '%s'!", pat.name, target_tdata.track_name or "Track")
                state.dragged_pattern = nil
                state.is_dragging_pattern = false
            end
        end
    end
    
    -- Drag Drop Target via ReaImGui Payload (additional native fallback)
    if reaper.ImGui_BeginDragDropTarget(ctx) then
        local ret, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "NOTATOR_PATTERN")
        if ret then
            local pat = PatternService.patterns_by_id[payload] or state.dragged_pattern
            if pat and active_tracks_data and #active_tracks_data > 0 then
                local target_tdata = active_tracks_data[1]
                for _, tdata in ipairs(active_tracks_data) do
                    local top = tdata.band_y0 or (tdata.staff_top_y - 25 * s)
                    local btm = tdata.band_y1 or ((tdata.staff_bottom_y or tdata.staff_top_y + 40 * s) + 35 * s)
                    if mouse_y >= top and mouse_y <= btm then
                        target_tdata = tdata
                        break
                    end
                end
                local raw_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
                local pat_qn_per_measure = qn_per_measure or 4.0
                local snapped_qn = math.floor(raw_qn / pat_qn_per_measure + 0.5) * pat_qn_per_measure
                PatternService.insert_pattern_into_track(target_tdata.track, snapped_qn, pat, midi_service)
                state.status_msg = string.format("Pattern '%s' inserted onto track '%s'!", pat.name, target_tdata.track_name or "Track")
            end
            state.dragged_pattern = nil
            state.is_dragging_pattern = false
        end
        reaper.ImGui_EndDragDropTarget(ctx)
    end
    
    if state.dragged_pattern and reaper.ImGui_IsMouseReleased(ctx, 0) then
        state.dragged_pattern = nil
        state.is_dragging_pattern = false
    end

    -- Right-click on score canvas / empty background reliably opens context menu
    if is_hovered and reaper.ImGui_IsMouseClicked(ctx, 1) then
        if not note_hovered_this_frame and not dyn_hovered_this_frame and not hairpin_hovered_this_frame
           and not dynamic_text_hovered_this_frame and not pedal_hovered_this_frame and not text_item_hovered_this_frame
           and not octave_hovered_this_frame and not art_hovered_this_frame and not tempo_hovered_this_frame
           and not chord_hovered_this_frame and not (state.show_chord_lane ~= false and mouse_y >= canvas_p0_y and mouse_y <= (canvas_p0_y + 42 * s)) then
            
            -- Find clicked track (staff) based on mouse_y
            local target_tdata = nil
            for _, tdata in ipairs(active_tracks_data or {}) do
                local top = tdata.band_y0 or (tdata.staff_top_y - 25 * s)
                local btm = tdata.band_y1 or ((tdata.staff_bottom_y or tdata.staff_top_y + 40 * s) + 35 * s)
                if mouse_y >= top and mouse_y <= btm then
                    target_tdata = tdata
                    break
                end
            end
            
            -- Fallback: select closest track if click occurred outside staff bounds
            if not target_tdata and active_tracks_data and #active_tracks_data > 0 then
                local best_dist = math.huge
                for _, tdata in ipairs(active_tracks_data) do
                    local mid_y = tdata.staff_top_y or 0
                    local dist = math.abs(mouse_y - mid_y)
                    if dist < best_dist then
                        best_dist = dist
                        target_tdata = tdata
                    end
                end
            end
            
            if target_tdata then
                state.focused_track = target_tdata.track
                if target_tdata.track and reaper.ValidatePtr(target_tdata.track, "MediaTrack*") then
                    reaper.SetOnlyTrackSelected(target_tdata.track)
                end
            end
            
            local raw_qn = Engraver.canvas_x_to_qn(mouse_x, margin_left, s, qn_per_measure, state.grid_qn, measure_map)
            local qn_pm = qn_per_measure or 4.0
            state.context_measure = math.floor(raw_qn / qn_pm)
            state.context_click_qn = raw_qn
            if target_tdata then
                state.context_measure_track = target_tdata.track
            end
            
            reaper.ImGui_OpenPopup(ctx, "NoteContextMenu")
        end
    end
    
    -- Render all external context menus (CanvasContextMenus)
    if CanvasContextMenus and CanvasContextMenus.render_all then
        CanvasContextMenus.render_all(ctx, state, midi_service, active_tracks_data, qn_per_measure)
    end
    
    state.hovered_note = note_hovered_this_frame
    state.hovered_dynamic = dyn_hovered_this_frame
    state.hovered_articulation = art_hovered_this_frame
    state.hovered_item_edge = item_edge_hovered_this_frame
    state.hovered_hairpin = hairpin_hovered_this_frame
    state.hovered_hairpin_handle = hairpin_handle_hovered_this_frame
    state.hovered_dynamic_text = dynamic_text_hovered_this_frame
    state.hovered_dynamic_text_handle = dynamic_text_handle_hovered_this_frame
    state.hovered_pedal = pedal_hovered_this_frame
    state.hovered_pedal_handle = pedal_handle_hovered_this_frame
    state.hovered_text_item = text_item_hovered_this_frame
    state.hovered_chord_item = chord_hovered_this_frame
    state.hovered_chord_handle = chord_handle_hovered_this_frame
    state.measure_map = measure_map
    
    AudioPreview.update(state, ctx)
    
    return {
        margin_left = margin_left,
        measure_w = measure_w,
        measure_map = measure_map,
        qn_per_measure = qn_per_measure,
        canvas_p0_y = canvas_p0_y,
        all_note_render_data = all_note_render_data,
        all_articulation_render_data = all_articulation_render_data,
        active_tracks_data = active_tracks_data
    }
end

return ScoreCanvas

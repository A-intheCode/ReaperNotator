-- ==============================================================================
-- REAPER Native Notator - Service: PatternService
-- Management, disk persistence, load/save & drag & drop of
-- 4-8 measure orchestral patterns and REAPER MIDI items
-- ==============================================================================

local JsonHelper  = require("services.json_helper")
local PathService = require("services.path_service")

local PatternService = {}

PatternService.patterns = {}
PatternService.patterns_by_id = {}
PatternService.patterns_by_category = {}
PatternService.categories = {}
PatternService.active_preview = nil -- { pattern = ..., track = ..., start_time = ..., note_idx = 1, active_notes = {} }

-- Display names for standard categories
PatternService.CATEGORY_META = {
    ["all"] = { label = "📁 All Patterns", order = 0 },
    ["01_Strings_Staccato"] = { label = "🎻 Strings - Staccato & Ostinatos", order = 1 },
    ["02_Strings_Pizzicato"] = { label = "🎻 Strings - Pizzicato & Grooves", order = 2 },
    ["03_Brass_Blockbuster"] = { label = "📯 Brass - Epic Horns & Low Brass", order = 3 },
    ["04_Cinematic_Melodies"] = { label = "🎵 Cinematic Melodies & Themes", order = 4 },
    ["05_Counter_Melodies"] = { label = "✨ Counter Melodies & Lines", order = 5 },
    ["06_Woodwinds_Textures"] = { label = "🌪 Woodwinds & Textures", order = 6 },
    ["07_Cinematic_Piano"] = { label = "🎹 Cinematic Piano & Arpeggios", order = 7 },
    ["08_Eigene_Patterns"] = { label = "⭐ User Patterns", order = 8 },
    ["07_Eigene_Patterns"] = { label = "⭐ User Patterns", order = 8 }, -- Fallback
    ["06_Eigene_Patterns"] = { label = "⭐ User Patterns", order = 8 }  -- Fallback
}

--- Determines absolute base path of patterns directory
function PatternService.get_base_dir()
    return PathService.get_patterns_dir()
end

--- Initializes the pattern system and scans all patterns on disk
function PatternService.init()
    PatternService.scan_library()
end

--- Scans all subdirectories and JSON files in patterns directory
function PatternService.scan_library()
    local base_dir = PatternService.get_base_dir()
    local sep = package.config:sub(1,1) or "/"
    
    PatternService.patterns = {}
    PatternService.patterns_by_id = {}
    PatternService.patterns_by_category = {}
    PatternService.categories = {}
    
    local found_categories = {}
    
    -- Search all subdirectories
    local dir_idx = 0
    while true do
        local sub_dir = reaper.EnumerateSubdirectories(base_dir, dir_idx)
        if not sub_dir then break end
        
        found_categories[sub_dir] = true
        PatternService.patterns_by_category[sub_dir] = {}
        
        -- Search all files in subdirectory
        local full_sub = base_dir .. sep .. sub_dir
        local file_idx = 0
        while true do
            local filename = reaper.EnumerateFiles(full_sub, file_idx)
            if not filename then break end
            
            if filename:lower():match("%.json$") then
                local full_file = full_sub .. sep .. filename
                local f = io.open(full_file, "r")
                if f then
                    local content = f:read("*all")
                    f:close()
                    
                    if content and #content > 0 then
                        local pattern = JsonHelper.decode(content)
                        if pattern and pattern.id and pattern.name and pattern.notes then
                            pattern.filepath = full_file
                            pattern.category = sub_dir
                            pattern.bars = math.max(1, math.min(64, tonumber(pattern.bars) or 4))
                            
                            table.insert(PatternService.patterns, pattern)
                            PatternService.patterns_by_id[pattern.id] = pattern
                            table.insert(PatternService.patterns_by_category[sub_dir], pattern)
                        end
                    end
                end
            end
            file_idx = file_idx + 1
        end
        
        dir_idx = dir_idx + 1
    end
    
    -- Build sorted category list
    local cat_list = {}
    for cat_id, _ in pairs(found_categories) do
        local meta = PatternService.CATEGORY_META[cat_id] or { label = "📁 " .. cat_id, order = 99 }
        table.insert(cat_list, {
            id = cat_id,
            label = meta.label,
            order = meta.order,
            count = #(PatternService.patterns_by_category[cat_id] or {})
        })
    end
    
    table.sort(cat_list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.label < b.label
    end)
    
    PatternService.categories = cat_list
end

--- Creates a new category folder on disk
--- @param folder_name string
function PatternService.create_folder(folder_name)
    if not folder_name or folder_name:match("^%s*$") then return false, "Invalid folder name" end
    local safe_name = folder_name:gsub("[^%w_%- ]", ""):gsub("%s+", "_")
    if #safe_name == 0 then safe_name = "New_Folder" end
    
    local base_dir = PatternService.get_base_dir()
    local sep = package.config:sub(1,1) or "/"
    local target_dir = base_dir .. sep .. safe_name
    
    -- Create directory via reaper.RecursiveCreateDirectory or OS
    if reaper.RecursiveCreateDirectory then
        reaper.RecursiveCreateDirectory(target_dir, 0)
    else
        os.execute('mkdir "' .. target_dir .. '"')
    end
    
    PatternService.scan_library()
    return true, safe_name
end

--- Saves a pattern as a JSON file to disk
--- @param pattern table
function PatternService.save_pattern(pattern)
    if not pattern or not pattern.id or not pattern.category then return false end
    local base_dir = PatternService.get_base_dir()
    local sep = package.config:sub(1,1) or "/"
    local cat_dir = base_dir .. sep .. pattern.category
    
    if reaper.RecursiveCreateDirectory then
        reaper.RecursiveCreateDirectory(cat_dir, 0)
    end
    
    local filepath = cat_dir .. sep .. pattern.id .. ".json"
    local json_str = JsonHelper.encode(pattern)
    local f = io.open(filepath, "w")
    if f then
        f:write(json_str)
        f:close()
        PatternService.scan_library()
        return true
    end
    return false
end

--- Deletes a custom pattern from disk
--- @param pattern table
function PatternService.delete_pattern(pattern)
    if not pattern or not pattern.filepath then return false end
    os.remove(pattern.filepath)
    PatternService.scan_library()
    return true
end

--- Reads a selected REAPER MIDI item and captures it as a 4-8 measure pattern
--- @param item MediaItem
--- @param name string
--- @param category string
--- @param max_bars integer (4 to 8)
function PatternService.capture_reaper_item(item, name, category, max_bars)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then
        return false, "No valid REAPER MediaItem selected"
    end
    
    local take = reaper.GetActiveTake(item)
    if not take or not reaper.TakeIsMIDI(take) then
        return false, "Selected item does not contain a valid MIDI take"
    end
    
    local ok, notecnt = reaper.MIDI_CountEvts(take)
    if not ok or notecnt == 0 then
        return false, "Selected MIDI item contains no notes"
    end
    
    -- Determine time signature
    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local timesig_num, timesig_denom, bpm = reaper.TimeMap_GetTimeSigAtTime(0, item_pos)
    timesig_num = (timesig_num and timesig_num > 0) and timesig_num or 4
    timesig_denom = (timesig_denom and timesig_denom > 0) and timesig_denom or 4
    local qn_per_measure = timesig_num * (4.0 / timesig_denom)
    
    local bars = math.max(1, math.min(64, tonumber(max_bars) or 4))
    local max_qn = bars * qn_per_measure
    
    -- Find first note for relative origin adjustment
    local first_qn = nil
    local raw_notes = {}
    for i = 0, notecnt - 1 do
        local n_ok, sel, muted, sppq, eppq, chan, pitch, vel = reaper.MIDI_GetNote(take, i)
        if n_ok and not muted then
            local qn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
            local end_qn = reaper.MIDI_GetProjQNFromPPQPos(take, eppq)
            local dur = math.max(0.1, end_qn - qn)
            
            if not first_qn or qn < first_qn then
                first_qn = qn
            end
            
            table.insert(raw_notes, {
                pitch = pitch,
                qn = qn,
                dur = dur,
                vel = vel,
                chan = chan
            })
        end
    end
    
    if #raw_notes == 0 then
        return false, "No active notes found"
    end
    
    -- Normalize notes to 0.0 QN and clamp to max_bars
    local notes = {}
    for _, rn in ipairs(raw_notes) do
        local rel_qn = rn.qn - first_qn
        if rel_qn < (max_qn - 0.01) then
            local note_dur = math.min(rn.dur, max_qn - rel_qn)
            table.insert(notes, {
                pitch = rn.pitch,
                start_qn = math.floor(rel_qn * 1000 + 0.5) / 1000,
                dur_qn = math.floor(note_dur * 1000 + 0.5) / 1000,
                vel = rn.vel,
                chan = rn.chan,
                art = (note_dur <= 0.3) and "staccato" or nil
            })
        end
    end
    
    table.sort(notes, function(a, b) return a.start_qn < b.start_qn end)
    
    -- Generate safe filename / ID
    local clean_name = (name and #name > 0) and name or "Custom Pattern"
    local safe_id = "user_" .. clean_name:lower():gsub("[^%w_%-]", "_"):gsub("_+", "_") .. "_" .. tostring(os.time()):sub(-5)
    local target_cat = category or "08_Eigene_Patterns"
    
    local avg_pitch = 60
    if #notes > 0 then
        local sum = 0
        for _, n in ipairs(notes) do sum = sum + n.pitch end
        avg_pitch = sum / #notes
    end
    local clef = (avg_pitch < 55) and "bass" or "treble"
    
    local pattern = {
        id = safe_id,
        name = clean_name,
        category = target_cat,
        bars = bars,
        time_sig = { num = timesig_num, denom = timesig_denom },
        tempo_hint = math.floor(bpm + 0.5),
        clef = clef,
        notes = notes
    }
    
    local success = PatternService.save_pattern(pattern)
    if success then
        return true, pattern
    else
        return false, "Failed to write pattern file to disk"
    end
end

--- Inserts a pattern at target position on a track in REAPER
--- @param track MediaTrack
--- @param target_qn number
--- @param pattern table
--- @param midi_service table
function PatternService.insert_pattern_into_track(track, target_qn, pattern, midi_service)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") or not pattern then return false end
    
    local timesig_num = (pattern.time_sig and pattern.time_sig.num) or 4
    local timesig_denom = (pattern.time_sig and pattern.time_sig.denom) or 4
    local qn_per_measure = timesig_num * (4.0 / timesig_denom)
    local total_dur = (pattern.bars or 4) * qn_per_measure
    
    -- Quantize target QN to measure boundary or grid
    local snapped_qn = math.floor(target_qn / qn_per_measure + 0.5) * qn_per_measure
    if math.abs(target_qn - snapped_qn) > 1.0 then
        snapped_qn = math.floor(target_qn * 4 + 0.5) / 4 -- Snapped to quarter note
    end
    
    local item, take = midi_service.get_or_create_item_at_qn(track, snapped_qn, total_dur)
    if not take or not reaper.ValidatePtr(take, "MediaItem_Take*") then return false end
    
    reaper.Undo_BeginBlock()
    
    -- Set item name if still default
    local cur_name = ""
    local _, tk_name = reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if tk_name == "Notator MIDI" or tk_name == "" then
        reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", pattern.name, true)
    end
    
    local inserted_ref_notes = {}
    
    -- Insert all notes of the pattern
    for _, pn in ipairs(pattern.notes or {}) do
        local n_start_qn = snapped_qn + pn.start_qn
        local n_dur_qn = pn.dur_qn or 0.25
        local n_pitch = math.max(0, math.min(127, pn.pitch))
        local n_vel = math.max(1, math.min(127, pn.vel or 90))
        local n_chan = math.max(0, math.min(15, pn.chan or 0))
        
        local sppq = reaper.MIDI_GetPPQPosFromProjQN(take, n_start_qn)
        local eppq = reaper.MIDI_GetPPQPosFromProjQN(take, n_start_qn + n_dur_qn)
        
        reaper.MIDI_InsertNote(take, false, false, sppq, eppq, n_chan, n_pitch, n_vel, true)
        
        table.insert(inserted_ref_notes, {
            sppq = sppq,
            eppq = eppq,
            pitch = n_pitch,
            chan = n_chan,
            idx = -1
        })
    end
    
    reaper.MIDI_Sort(take)
    
    -- Resolve voice and pitch conflicts cleanly
    if midi_service.resolve_voice_conflicts and #inserted_ref_notes > 0 then
        midi_service.resolve_voice_conflicts(take, inserted_ref_notes)
        reaper.MIDI_Sort(take)
    end
    
    reaper.UpdateArrange()
    reaper.Undo_EndBlock("Notator: Insert pattern '" .. pattern.name .. "'", -1)
    
    return true
end

-- ==============================================================================
-- AUDIO PREVIEW (Playback via selectable REAPER track)
-- ==============================================================================

--- Starts audio playback of a pattern via specified track
--- @param pattern table
--- @param track MediaTrack
--- @param audio_preview table
function PatternService.start_preview(pattern, track, audio_preview)
    if not pattern or not track or not reaper.ValidatePtr(track, "MediaTrack*") or not audio_preview then
        return
    end
    
    PatternService.stop_preview(audio_preview)
    
    audio_preview.prepare_track(track)
    
    local sorted_notes = {}
    for _, n in ipairs(pattern.notes or {}) do
        table.insert(sorted_notes, {
            pitch = n.pitch,
            start_qn = n.start_qn,
            dur_qn = n.dur_qn,
            vel = n.vel or 90,
            chan = n.chan or 0
        })
    end
    table.sort(sorted_notes, function(a, b) return a.start_qn < b.start_qn end)
    
    local tempo = pattern.tempo_hint or 120
    local sec_per_qn = 60.0 / tempo
    
    PatternService.active_preview = {
        pattern = pattern,
        track = track,
        start_time = reaper.time_precise(),
        sec_per_qn = sec_per_qn,
        notes = sorted_notes,
        next_note_idx = 1,
        active_sounding = {}, -- { { pitch = ..., off_time = ... } }
        total_time = (pattern.bars or 4) * 4.0 * sec_per_qn
    }
end

--- Stops active pattern preview
--- @param audio_preview table
function PatternService.stop_preview(audio_preview)
    if not PatternService.active_preview then return end
    
    local p = PatternService.active_preview
    if p.track and reaper.ValidatePtr(p.track, "MediaTrack*") then
        -- Send Note-Off for all sounding notes
        for _, n in ipairs(p.active_sounding or {}) do
            reaper.StuffMIDIMessage(0, 0x80 | (n.chan or 0), n.pitch, 0)
        end
        if audio_preview and audio_preview.restore_track then
            audio_preview.restore_track(p.track)
        end
    end
    
    PatternService.active_preview = nil
end

--- Updates pattern audio preview every loop frame
--- @param audio_preview table
function PatternService.update_preview(audio_preview)
    if not PatternService.active_preview then return end
    
    local p = PatternService.active_preview
    if not p.track or not reaper.ValidatePtr(p.track, "MediaTrack*") then
        PatternService.active_preview = nil
        return
    end
    
    local now = reaper.time_precise()
    local elapsed = now - p.start_time
    
    -- Check expired notes and send Note-Off
    local remaining_sounding = {}
    for _, sn in ipairs(p.active_sounding) do
        if now >= sn.off_time then
            reaper.StuffMIDIMessage(0, 0x80 | (sn.chan or 0), sn.pitch, 0)
        else
            table.insert(remaining_sounding, sn)
        end
    end
    p.active_sounding = remaining_sounding
    
    -- Trigger new notes whose timestamp is reached
    while p.next_note_idx <= #p.notes do
        local n = p.notes[p.next_note_idx]
        local note_time = n.start_qn * p.sec_per_qn
        if elapsed >= (note_time - 0.005) then
            -- Send Note-On
            reaper.StuffMIDIMessage(0, 0x90 | (n.chan or 0), n.pitch, n.vel)
            local dur_sec = math.max(0.08, n.dur_qn * p.sec_per_qn)
            table.insert(p.active_sounding, {
                pitch = n.pitch,
                chan = n.chan or 0,
                off_time = now + dur_sec
            })
            p.next_note_idx = p.next_note_idx + 1
        else
            break
        end
    end
    
    -- Stop when entire pattern duration has completed
    if elapsed >= (p.total_time + 0.5) and #p.active_sounding == 0 then
        PatternService.stop_preview(audio_preview)
    end
end

return PatternService

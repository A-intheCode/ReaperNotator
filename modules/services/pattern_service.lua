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
    ["08_Ancient_Harp_Greek_Roman"] = { label = "🏛 Harp - Ancient Greek & Roman", order = 8 },
    ["09_Orchestral_Percussion"] = { label = "🥁 Percussion - Timpani, Taiko & Drums", order = 9 },
    ["10_Low_Strings_Celli_Basses"] = { label = "🎻 Low Strings - Celli & Bass Tension", order = 10 },
    ["11_Eigene_Patterns"] = { label = "⭐ User Patterns", order = 11 },
    ["10_Eigene_Patterns"] = { label = "⭐ User Patterns", order = 11 }, -- Fallback
    ["09_Eigene_Patterns"] = { label = "⭐ User Patterns", order = 11 }, -- Fallback
    ["08_Eigene_Patterns"] = { label = "⭐ User Patterns", order = 11 }, -- Fallback
    ["07_Eigene_Patterns"] = { label = "⭐ User Patterns", order = 11 }, -- Fallback
    ["06_Eigene_Patterns"] = { label = "⭐ User Patterns", order = 11 }  -- Fallback
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
                            local ts_num = (pattern.time_sig and pattern.time_sig.num) or 4
                            local ts_denom = (pattern.time_sig and pattern.time_sig.denom) or 4
                            local qn_per_bar = ts_num * (4.0 / ts_denom)
                            local max_note_qn = 0
                            for _, pn in ipairs(pattern.notes) do
                                local eq = (pn.start_qn or 0) + (pn.dur_qn or 0.25)
                                if eq > max_note_qn then max_note_qn = eq end
                            end
                            local needed_bars = (qn_per_bar > 0) and math.ceil((max_note_qn - 0.01) / qn_per_bar) or 1
                            local raw_bars = math.max(1, math.min(128, tonumber(pattern.bars) or 4))
                            pattern.bars = math.max(raw_bars, needed_bars)
                            
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
    
    local is_entire_item = (tonumber(max_bars) or 4) >= 64
    local bars = math.max(1, math.min(128, tonumber(max_bars) or 4))
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
    local max_rel_end_qn = 0
    for _, rn in ipairs(raw_notes) do
        local rel_qn = rn.qn - first_qn
        if rel_qn < (max_qn - 0.01) then
            local note_dur = math.min(rn.dur, max_qn - rel_qn)
            if rel_qn + note_dur > max_rel_end_qn then
                max_rel_end_qn = rel_qn + note_dur
            end
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
    
    if is_entire_item and qn_per_measure > 0 and max_rel_end_qn > 0 then
        bars = math.max(1, math.ceil((max_rel_end_qn - 0.01) / qn_per_measure))
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
    
    PatternService.stop_preview(audio_preview, true)
    if audio_preview.stop_note then
        audio_preview.stop_note(nil, true)
    end
    
    local just_switched = audio_preview.prepare_track(track)
    
    local tempo = tonumber(pattern.tempo_hint) or 120
    if tempo <= 0 then tempo = 120 end
    local sec_per_qn = 60.0 / tempo
    
    local raw_sorted = {}
    local max_note_end_qn = 0
    for _, n in ipairs(pattern.notes or {}) do
        local sqn = tonumber(n.start_qn) or 0
        local dqn = tonumber(n.dur_qn) or 0.25
        if sqn + dqn > max_note_end_qn then
            max_note_end_qn = sqn + dqn
        end
        table.insert(raw_sorted, {
            pitch = math.max(0, math.min(127, math.floor(tonumber(n.pitch) or 60))),
            start_qn = sqn,
            dur_qn = dqn,
            vel = math.max(1, math.min(127, math.floor(tonumber(n.vel) or 90))),
            chan = math.max(0, math.min(15, math.floor(tonumber(n.chan) or 0)))
        })
    end
    table.sort(raw_sorted, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.001 then
            return a.start_qn < b.start_qn
        end
        if a.pitch ~= b.pitch then
            return a.pitch < b.pitch
        end
        return a.dur_qn > b.dur_qn
    end)
    
    -- 1. Deduplicate simultaneous notes of the exact same (pitch, chan) at the same timestamp
    local sorted_notes = {}
    local used_channels = {}
    local used_notes_map = {}
    local used_notes_list = {}
    for _, n in ipairs(raw_sorted) do
        local prev = sorted_notes[#sorted_notes]
        if prev and prev.pitch == n.pitch and prev.chan == n.chan and math.abs(n.start_qn - prev.start_qn) < 0.02 then
            if n.dur_qn > prev.dur_qn then prev.dur_qn = n.dur_qn end
            if n.vel > prev.vel then prev.vel = n.vel end
        else
            table.insert(sorted_notes, n)
            used_channels[n.chan] = true
            local nk = (n.chan << 8) | n.pitch
            if not used_notes_map[nk] then
                used_notes_map[nk] = true
                table.insert(used_notes_list, { pitch = n.pitch, chan = n.chan })
            end
        end
    end
    
    -- 2. Pre-calculate safe note duration (dur_sec) with a guaranteed >= 40ms gate gap
    -- before any subsequent note of the SAME (pitch, chan) so Note-Off and Note-On never collide in the same audio block
    for i = 1, #sorted_notes do
        local ni = sorted_notes[i]
        local raw_dur_sec = math.max(0.06, ni.dur_qn * sec_per_qn)
        -- Slight natural release gap (15ms) so back-to-back legato notes don't overlap on the exact same frame
        local safe_dur_sec = math.max(0.05, raw_dur_sec - 0.015)
        for j = i + 1, #sorted_notes do
            local nj = sorted_notes[j]
            if nj.pitch == ni.pitch and nj.chan == ni.chan then
                local delta_sec = (nj.start_qn - ni.start_qn) * sec_per_qn
                -- Leave at least 40ms (~2-3 frames / audio blocks) between Note-Off and same-pitch Note-On
                local max_allowed = math.max(0.025, delta_sec - 0.040)
                if safe_dur_sec > max_allowed then
                    safe_dur_sec = max_allowed
                end
                break
            end
        end
        ni.dur_sec = safe_dur_sec
    end
    
    local timesig_num = (pattern.time_sig and tonumber(pattern.time_sig.num)) or 4
    local timesig_denom = (pattern.time_sig and tonumber(pattern.time_sig.denom)) or 4
    if timesig_num <= 0 then timesig_num = 4 end
    if timesig_denom <= 0 then timesig_denom = 4 end
    local qn_per_bar = timesig_num * (4.0 / timesig_denom)
    local total_qn = math.max((tonumber(pattern.bars) or 4) * qn_per_bar, max_note_end_qn)
    
    local now = reaper.time_precise()
    audio_preview.last_activity_time = now
    
    PatternService.active_preview = {
        pattern = pattern,
        track = track,
        start_time = now + (just_switched and 0.055 or 0.0),
        sec_per_qn = sec_per_qn,
        notes = sorted_notes,
        next_note_idx = 1,
        active_sounding = {}, -- { { pitch = ..., chan = ..., off_time = ... } }
        used_channels = used_channels,
        used_notes = used_notes_list,
        total_qn = total_qn,
        total_time = total_qn * sec_per_qn,
        all_notes_ended_time = nil,
        flush_stage = 0
    }
end

--- Stops active pattern preview and flushes all active MIDI notes cleanly before track restoration
--- @param audio_preview table
--- @param keep_track boolean|nil If true, keeps track prepared for immediate next pattern
function PatternService.stop_preview(audio_preview, keep_track)
    if not PatternService.active_preview then return end
    
    local p = PatternService.active_preview
    PatternService.active_preview = nil
    local now = reaper.time_precise()
    if audio_preview then
        audio_preview.last_activity_time = now
    end
    
    if p.track and reaper.ValidatePtr(p.track, "MediaTrack*") then
        -- 1. Send explicit Note-Off for all currently sounding notes
        for _, n in ipairs(p.active_sounding or {}) do
            local ch = (n.chan or 0) & 0x0F
            reaper.StuffMIDIMessage(0, 0x80 | ch, n.pitch, 0)
        end
        -- 2. Send explicit Note-Off for every pitch used in the pattern + All Notes Off (CC 123)
        for _, un in ipairs(p.used_notes or {}) do
            local ch = (un.chan or 0) & 0x0F
            reaper.StuffMIDIMessage(0, 0x80 | ch, un.pitch, 0)
        end
        for ch, _ in pairs(p.used_channels or { [0] = true }) do
            local c = ch & 0x0F
            reaper.StuffMIDIMessage(0, 0xB0 | c, 64, 0)  -- Sustain Pedal Off
            reaper.StuffMIDIMessage(0, 0xB0 | c, 123, 0) -- All Notes Off
        end
        
        -- IMPORTANT: Never call audio_preview.restore_track(p.track) synchronously in the same frame!
        -- Disarming / switching I_RECINPUT away from Virtual MIDI Keyboard (6080) in the same frame
        -- drops the queued StuffMIDIMessage Note-Off events before REAPER's audio thread processes them.
        if not keep_track then
            local used_notes = p.used_notes or {}
            local used_channels = p.used_channels or { [0] = true }
            local flush_start = now
            local function deferred_note_off_flush()
                local t = reaper.time_precise()
                if audio_preview then
                    audio_preview.last_activity_time = t
                end
                if (t - flush_start) < 0.045 then
                    reaper.defer(deferred_note_off_flush)
                    return
                end
                -- Second safety wave in a subsequent audio buffer block while track is still on VKB (6080)
                if not PatternService.active_preview then
                    for _, un in ipairs(used_notes) do
                        local ch = (un.chan or 0) & 0x0F
                        reaper.StuffMIDIMessage(0, 0x80 | ch, un.pitch, 0)
                    end
                    for ch, _ in pairs(used_channels) do
                        local c = ch & 0x0F
                        reaper.StuffMIDIMessage(0, 0xB0 | c, 123, 0)
                    end
                end
                if audio_preview and audio_preview.start_sequence_loop then
                    audio_preview.start_sequence_loop()
                end
            end
            reaper.defer(deferred_note_off_flush)
        end
    end
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
    -- Keep AudioPreview's inactivity timer alive for the entire multi-bar pattern duration!
    if audio_preview then
        audio_preview.last_activity_time = now
    end
    
    local elapsed = now - p.start_time
    if elapsed < 0 then return end
    
    -- 1. Check expired notes and send Note-Off
    -- Track which (chan, pitch) received a Note-Off on THIS frame so we never send a Note-On
    -- for the same pitch in the exact same audio buffer block!
    local off_sent_this_frame = {}
    local remaining_sounding = {}
    for _, sn in ipairs(p.active_sounding) do
        if now >= sn.off_time then
            local ch = (sn.chan or 0) & 0x0F
            reaper.StuffMIDIMessage(0, 0x80 | ch, sn.pitch, 0)
            off_sent_this_frame[(ch << 8) | sn.pitch] = true
        else
            table.insert(remaining_sounding, sn)
        end
    end
    p.active_sounding = remaining_sounding
    
    -- 2. Trigger new notes whose timestamp is reached
    while p.next_note_idx <= #p.notes do
        local n = p.notes[p.next_note_idx]
        local note_time = n.start_qn * p.sec_per_qn
        if elapsed >= (note_time - 0.005) then
            local n_chan = (n.chan or 0) & 0x0F
            local nk = (n_chan << 8) | n.pitch
            
            -- If same pitch+channel is still sounding, send Note-Off first and wait until next frame for Note-On
            for i = #p.active_sounding, 1, -1 do
                local sn = p.active_sounding[i]
                if sn.pitch == n.pitch and ((sn.chan or 0) & 0x0F) == n_chan then
                    reaper.StuffMIDIMessage(0, 0x80 | n_chan, sn.pitch, 0)
                    table.remove(p.active_sounding, i)
                    off_sent_this_frame[nk] = true
                end
            end
            
            -- Never send Note-Off and Note-On for the same pitch in the same defer tick / audio block!
            if off_sent_this_frame[nk] then
                break
            end
            
            if not p.cc_woken then
                p.cc_woken = true
                reaper.StuffMIDIMessage(0, 0xB0 | n_chan, 1, 96)
                reaper.StuffMIDIMessage(0, 0xB0 | n_chan, 11, 108)
            end
            
            -- Send Note-On
            reaper.StuffMIDIMessage(0, 0x90 | n_chan, n.pitch, n.vel)
            local dur_sec = n.dur_sec or math.max(0.06, n.dur_qn * p.sec_per_qn)
            table.insert(p.active_sounding, {
                pitch = n.pitch,
                chan = n_chan,
                off_time = now + dur_sec
            })
            p.next_note_idx = p.next_note_idx + 1
        else
            break
        end
    end
    
    -- 3. Post-playback safety flush & clean completion after all notes have turned off
    if p.next_note_idx > #p.notes and #p.active_sounding == 0 then
        if not p.all_notes_ended_time then
            p.all_notes_ended_time = now
            p.flush_stage = 0
        end
        local since_ended = now - p.all_notes_ended_time
        if p.flush_stage == 0 and since_ended >= 0.035 then
            p.flush_stage = 1
            for _, un in ipairs(p.used_notes or {}) do
                local ch = (un.chan or 0) & 0x0F
                reaper.StuffMIDIMessage(0, 0x80 | ch, un.pitch, 0)
            end
            for ch, _ in pairs(p.used_channels or { [0] = true }) do
                reaper.StuffMIDIMessage(0, 0xB0 | (ch & 0x0F), 123, 0)
            end
        end
        if elapsed >= (p.total_time + 0.25) and since_ended >= 0.25 then
            PatternService.stop_preview(audio_preview)
        end
    end
end

PatternService.is_downloading = false
PatternService.download_status = nil
PatternService.download_error = nil
PatternService.download_start_time = 0

--- Triggers 1-click in-app download and extraction of the factory pattern library
--- @param state table|nil
function PatternService.start_factory_download(state)
    if PatternService.is_downloading then return end
    
    local s_dir = PathService.get_script_dir()
    local target_patterns_dir = PathService.get_patterns_dir(state)
    
    -- Ensure target directory exists
    reaper.RecursiveCreateDirectory(target_patterns_dir, 0)
    
    local marker_file = PathService.normalize(s_dir .. "/.pattern_dl_status.txt")
    -- Remove any stale marker file
    os.remove(marker_file)
    
    PatternService.is_downloading = true
    PatternService.download_status = "downloading"
    PatternService.download_error = nil
    PatternService.download_start_time = reaper.time_precise()
    
    local os_type = PathService.get_os()
    local cmd = ""
    
    if os_type == "windows" then
        local target_parent = PathService.normalize(s_dir):gsub("/", "\\")
        local status_path = marker_file:gsub("/", "\\")
        local local_zip1 = (s_dir .. "/patterns.zip"):gsub("/", "\\")
        local local_zip2 = (s_dir .. "/../patterns.zip"):gsub("/", "\\")
        
        local ps_script = string.format([[$ProgressPreference = 'SilentlyContinue'; $statusFile = '%s'; $targetParent = '%s'; $localZip1 = '%s'; $localZip2 = '%s'; try { if (Test-Path $localZip1) { $srcZip = $localZip1 } elseif (Test-Path $localZip2) { $srcZip = $localZip2 } else { $srcZip = Join-Path $env:TEMP 'notator_patterns.zip'; Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/A-intheCode/ReaperNotator/main/patterns.zip' -OutFile $srcZip; } Expand-Archive -Path $srcZip -DestinationPath $targetParent -Force; Set-Content -Path $statusFile -Value 'OK'; } catch { Set-Content -Path $statusFile -Value ('ERROR:' + $_.Exception.Message); }]],
            status_path, target_parent, local_zip1, local_zip2)
            
        -- Execute via background PowerShell without command prompt window
        cmd = string.format('start /b powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -Command "%s"', ps_script)
        os.execute(cmd)
    else
        -- macOS / Linux
        local target_parent = PathService.normalize(s_dir)
        local status_path = marker_file
        local local_zip1 = s_dir .. "/patterns.zip"
        local local_zip2 = s_dir .. "/../patterns.zip"
        
        local sh_script = string.format([[STATUS='%s'; TARGET='%s'; ZIP='/tmp/notator_patterns.zip'; if [ -f '%s' ]; then unzip -o '%s' -d "$TARGET" && echo "OK" > "$STATUS"; elif [ -f '%s' ]; then unzip -o '%s' -d "$TARGET" && echo "OK" > "$STATUS"; else curl -L 'https://raw.githubusercontent.com/A-intheCode/ReaperNotator/main/patterns.zip' -o "$ZIP" && unzip -o "$ZIP" -d "$TARGET" && rm -f "$ZIP" && echo "OK" > "$STATUS" || echo "ERROR:Download failed" > "$STATUS"; fi]],
            status_path, target_parent, local_zip1, local_zip1, local_zip2, local_zip2)
            
        cmd = string.format('sh -c "%s" &', sh_script:gsub('"', '\\"'))
        os.execute(cmd)
    end
end

--- Checks if the background download and extraction process has completed
--- @param state table|nil
function PatternService.check_download_progress(state)
    if not PatternService.is_downloading then return end
    
    local s_dir = PathService.get_script_dir()
    local marker_file = PathService.normalize(s_dir .. "/.pattern_dl_status.txt")
    
    local f = io.open(marker_file, "r")
    if f then
        local content = f:read("*a") or ""
        f:close()
        os.remove(marker_file)
        
        PatternService.is_downloading = false
        if content:match("^OK") then
            PatternService.download_status = "success"
            PatternService.download_error = nil
            PatternService.scan_library()
            if state then
                state.status_msg = string.format("Successfully installed Factory Pattern Library (%d patterns)!", #PatternService.patterns)
            end
        else
            PatternService.download_status = "error"
            PatternService.download_error = content:gsub("^ERROR:", "")
            if state then
                state.status_msg = "Pattern download failed: " .. (PatternService.download_error or "Unknown error")
            end
        end
    else
        -- Timeout after 45 seconds
        if reaper.time_precise() - PatternService.download_start_time > 45.0 then
            PatternService.is_downloading = false
            PatternService.download_status = "timeout"
            PatternService.download_error = "Download timed out after 45 seconds."
            if state then
                state.status_msg = "Pattern download timed out."
            end
        end
    end
end

return PatternService

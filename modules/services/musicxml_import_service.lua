-- ==============================================================================
-- REAPER Native Notator - Service: MusicXmlImportService
-- Pure-Lua MusicXML 3.1 / 4.0 Partwise Importer.
-- Parses MusicXML files and creates REAPER tracks, MIDI items/takes,
-- notes, voices, key signatures, time signatures, dynamics, hairpins,
-- octave lines, pedals, text items, and Chord & Scale Lane items (<harmony>).
-- ==============================================================================

local Constants = require("constants")
local ChordItem = require("classes.chord_item")
local Dynamic = require("classes.dynamic")
local Hairpin = require("classes.hairpin")
local DynamicText = require("classes.dynamic_text")
local OctaveLine = require("classes.octave_line")
local PedalMark = require("classes.pedal_mark")
local TextItem = require("classes.text_item")
local KeySignatureService = require("services.key_signature_service")
local MidiService = require("services.midi_service")
local HairpinService = require("services.hairpin_service")
local DynamicTextService = require("services.dynamic_text_service")

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
    rfz  = {c1 = 115, c2 = 115},
    fz   = {c1 = 110, c2 = 110},
    sf   = {c1 = 105, c2 = 105},
}

local MusicXmlImportService = {}

-- ------------------------------------------------------------------------------
-- XML Unescape
-- ------------------------------------------------------------------------------
local function xml_unescape(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("&apos;", "'")
    str = str:gsub("&quot;", "\"")
    str = str:gsub("&gt;", ">")
    str = str:gsub("&lt;", "<")
    str = str:gsub("&amp;", "&")
    return str
end

-- ------------------------------------------------------------------------------
-- Pure-Lua Lightweight XML DOM Parser
-- ------------------------------------------------------------------------------
local function parse_xml(s)
    -- Remove comments, DOCTYPE, XML declaration
    s = s:gsub("<!%-%-.-%-%->", "")
    s = s:gsub("<!DOCTYPE.-%]>", "")
    s = s:gsub("<!DOCTYPE.->", "")
    s = s:gsub("<%?.-%?>", "")

    local root = { tag = "root", attr = {}, children = {}, text = "" }
    local stack = { root }

    local pos = 1
    local len = #s

    while pos <= len do
        local tag_start, tag_open_end = s:find("<[^>]+>", pos)
        if not tag_start then break end

        -- Text before tag
        if tag_start > pos then
            local txt = s:sub(pos, tag_start - 1)
            txt = txt:match("^%s*(.-)%s*$")
            if txt and txt ~= "" then
                stack[#stack].text = stack[#stack].text .. xml_unescape(txt)
            end
        end

        local full_tag = s:sub(tag_start, tag_open_end)
        local is_closing = (full_tag:sub(1, 2) == "</")
        local is_self_closing = (full_tag:sub(-2) == "/>")

        if is_closing then
            local tag_name = full_tag:match("</%s*([%w%-%_]+)")
            if #stack > 1 then
                table.remove(stack)
            end
        else
            -- Opening or self-closing tag
            local tag_content = full_tag:match("<%s*([%w%-%_]+)(.-)/?>")
            local tag_name = full_tag:match("<%s*([%w%-%_]+)")
            local attr_str = full_tag:match("<%s*[%w%-%_]+(.-)/?>") or ""

            local attr = {}
            for k, v in attr_str:gmatch('([%w%-%_]+)%s*=%s*"([^"]*)"') do
                attr[k] = xml_unescape(v)
            end
            for k, v in attr_str:gmatch("([%w%-%_]+)%s*=%s*'([^']*)'") do
                attr[k] = xml_unescape(v)
            end

            local node = { tag = tag_name or "unknown", attr = attr, children = {}, text = "" }
            table.insert(stack[#stack].children, node)

            if not is_self_closing then
                table.insert(stack, node)
            end
        end

        pos = tag_open_end + 1
    end

    -- Return the first child of root (usually <score-partwise>)
    for _, child in ipairs(root.children) do
        if child.tag == "score-partwise" or child.tag:find("score") then
            return child
        end
    end
    return root.children[1] or root
end

-- DOM Helper Functions
local function get_first_child(node, tag_name)
    if not node or not node.children then return nil end
    for _, c in ipairs(node.children) do
        if c.tag == tag_name then return c end
    end
    return nil
end

local function get_all_children(node, tag_name)
    local list = {}
    if not node or not node.children then return list end
    for _, c in ipairs(node.children) do
        if c.tag == tag_name then table.insert(list, c) end
    end
    return list
end

local function get_text(node)
    return (node and node.text) and node.text:match("^%s*(.-)%s*$") or ""
end

-- ------------------------------------------------------------------------------
-- Pitch Calculation from MusicXML Step, Alter, Octave
-- ------------------------------------------------------------------------------
local STEP_TO_SEMITONE = {
    C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11
}

local function musicxml_to_pitch(step, alter, octave)
    local s = step and step:upper() or "C"
    local semi = STEP_TO_SEMITONE[s] or 0
    local alt = tonumber(alter) or 0
    local oct = tonumber(octave) or 4
    local pitch = (oct + 1) * 12 + semi + alt
    return math.max(0, math.min(127, math.floor(pitch + 0.5)))
end

local ARTICULATION_TEXT_MAP = {
    ["staccato"] = "staccato",
    ["stacc."] = "staccato",
    ["stacc"] = "staccato",
    ["staccatissimo"] = "staccatissimo",
    ["staccatiss."] = "staccatissimo",
    ["spiccato"] = "spiccato",
    ["spicc."] = "spiccato",
    ["spicc"] = "spiccato",
    ["tenuto"] = "tenuto",
    ["ten."] = "tenuto",
    ["ten"] = "tenuto",
    ["accent"] = "accent",
    ["acc."] = "accent",
    ["marcato"] = "marcato",
    ["marc."] = "marcato",
    ["marc"] = "marcato",
    ["harmonic"] = "harmonic",
    ["harm."] = "harmonic",
    ["flageolet"] = "harmonic",
    ["fermata"] = "fermata",
    ["pizzicato"] = "pizzicato",
    ["pizz."] = "pizzicato",
    ["pizz"] = "pizzicato",
    ["arco"] = "arco",
    ["legato"] = "legato",
    ["detache"] = "detache",
    ["détaché"] = "detache",
    ["martellato"] = "martellato",
    ["col legno"] = "col legno",
    ["c. legno"] = "col legno",
    ["sul tasto"] = "sul tasto",
    ["tasto"] = "sul tasto",
    ["sul ponticello"] = "sul ponticello",
    ["sul pont."] = "sul ponticello",
    ["ponticello"] = "sul ponticello",
    ["con sordino"] = "con sordino",
    ["con sord."] = "con sordino",
    ["sordino"] = "con sordino",
    ["senza sordino"] = "senza sordino",
    ["senza sord."] = "senza sordino",
    ["flautando"] = "flautando",
    ["vibrato"] = "vibrato",
    ["non vibrato"] = "non vibrato",
    ["senza vibrato"] = "non vibrato",
    ["tremolo"] = "tremolo",
    ["trem."] = "tremolo",
    ["trill"] = "trill",
    ["tr."] = "trill",
    ["snap pizz"] = "snap-pizzicato",
    ["bartok pizz"] = "snap-pizzicato",
    ["snap-pizzicato"] = "snap-pizzicato",
    ["mute"] = "mute",
    ["open"] = "open",
    ["espressivo"] = "espressivo",
    ["espr."] = "espressivo",
    ["dolce"] = "dolce",
    ["cantabile"] = "cantabile",
    ["up-bow"] = "up-bow",
    ["down-bow"] = "down-bow"
}

local function detect_articulation_from_text(txt)
    if not txt or txt == "" then return nil end
    local clean = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if ARTICULATION_TEXT_MAP[clean] then
        return ARTICULATION_TEXT_MAP[clean]
    end
    local without_dot = clean:gsub("[%.:,;!]+$", "")
    if ARTICULATION_TEXT_MAP[without_dot] then
        return ARTICULATION_TEXT_MAP[without_dot]
    end
    if clean:find("^pizz") then return "pizzicato"
    elseif clean:find("^arco") then return "arco"
    elseif clean:find("^legato") then return "legato"
    elseif clean:find("^stacc") then return "staccato"
    elseif clean:find("^ten") then return "tenuto"
    elseif clean:find("^marc") then return "marcato"
    elseif clean:find("^spicc") then return "spiccato"
    elseif clean:find("^flaut") then return "flautando"
    elseif clean:find("^trem") then return "tremolo"
    elseif clean:find("ponticello") then return "sul ponticello"
    elseif clean:find("sordino") then
        if clean:find("senza") then return "senza sordino"
        else return "con sordino" end
    elseif clean:find("tasto") then return "sul tasto"
    elseif clean:find("col legno") then return "col legno"
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- Main Import Function
-- ------------------------------------------------------------------------------
function MusicXmlImportService.import_file(file_path, state, options)
    options = options or {}
    if not file_path or file_path == "" then
        return false, "No MusicXML file path provided."
    end

    local f, err = io.open(file_path, "rb")
    if not f then
        return false, string.format("Cannot open MusicXML file: %s", tostring(err))
    end
    local xml_content = f:read("*a")
    f:close()

    if not xml_content or #xml_content == 0 then
        return false, "MusicXML file is empty."
    end

    local dom = parse_xml(xml_content)
    if not dom or not dom.children then
        return false, "Failed to parse MusicXML syntax."
    end

    -- 1. Extract Part List & Track Names
    local part_list_node = get_first_child(dom, "part-list")
    local part_names = {}
    if part_list_node then
        for _, sp in ipairs(get_all_children(part_list_node, "score-part")) do
            local pid = sp.attr and sp.attr.id
            local pn_node = get_first_child(sp, "part-name")
            local pname = get_text(pn_node)
            if pid then
                part_names[pid] = pname
            end
        end
    end

    local parts = get_all_children(dom, "part")
    if #parts == 0 then
        return false, "No <part> elements found in MusicXML file."
    end

    -- Setup destination tracks
    local create_tracks = (options.create_new_tracks ~= false)
    local target_tracks = {}

    for pi, part_node in ipairs(parts) do
        local pid = part_node.attr and part_node.attr.id or string.format("P%d", pi)
        local pname = part_names[pid] or string.format("Part %d", pi)

        local tr = nil
        if create_tracks then
            local new_idx = reaper.CountTracks(0)
            reaper.InsertTrackAtIndex(new_idx, false)
            tr = reaper.GetTrack(0, new_idx)
            reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", pname, true)
        else
            tr = reaper.GetSelectedTrack(0, pi - 1) or reaper.GetTrack(0, pi - 1)
            if not tr then
                local new_idx = reaper.CountTracks(0)
                reaper.InsertTrackAtIndex(new_idx, false)
                tr = reaper.GetTrack(0, new_idx)
                reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", pname, true)
            end
        end
        table.insert(target_tracks, tr)
    end

    local total_notes_imported = 0
    local total_measures_imported = 0

    -- Tracking active directions across measures
    local active_wedges = {}
    local active_dynamic_texts = {}
    local active_octaves = {}
    local active_pedals = {}
    local imported_tempo_markers = {}
    local takes_with_dynamics = {}

    -- Process each part
    for pi, part_node in ipairs(parts) do
        local tr = target_tracks[pi]
        local trk_guid = tr and reaper.GetTrackGUID(tr) or ""

        local measures = get_all_children(part_node, "measure")
        if #measures > total_measures_imported then
            total_measures_imported = #measures
        end

        local divisions = 480
        local timesig_num, timesig_denom = 4, 4
        local bpi = 4.0
        local cur_key_idx = 0
        local cur_key_mode = "major"
        local staves_count = 1
        local is_grand_part = false

        local track_notes = {}
        local track_dynamics = {}
        local item_key_sigs = {}
        local item_time_sigs = {}
        local pending_text_arts = {}
        local open_ties = {} -- [string.format("%d_%d", chan, pitch)] = { start_qn, dur_qn, ... }
        local cur_m_start_qn = 0.0

        for m_idx, m_node in ipairs(measures) do
            local m_num = tonumber(m_node.attr and m_node.attr.number) or m_idx
            local m_start_qn = cur_m_start_qn
            local cur_div = 0
            local last_onset_qn = m_start_qn

            for _, child in ipairs(m_node.children) do
                local ctag = child.tag

                -- --------------------------------------------------------------
                -- Attributes (<attributes>)
                -- --------------------------------------------------------------
                if ctag == "attributes" then
                    local div_node = get_first_child(child, "divisions")
                    if div_node then
                        local d = tonumber(get_text(div_node))
                        if d and d > 0 then divisions = d end
                    end

                    local key_node = get_first_child(child, "key")
                    if key_node then
                        local fifths_node = get_first_child(key_node, "fifths")
                        if fifths_node then
                            cur_key_idx = tonumber(get_text(fifths_node)) or 0
                        end
                        local mode_node = get_first_child(key_node, "mode")
                        if mode_node then
                            cur_key_mode = get_text(mode_node) or "major"
                        end
                        item_key_sigs[m_idx] = { idx = cur_key_idx, mode = cur_key_mode }
                    end

                    local time_node = get_first_child(child, "time")
                    if time_node then
                        local beats_node = get_first_child(time_node, "beats")
                        local beat_type_node = get_first_child(time_node, "beat-type")
                        if beats_node and beat_type_node then
                            timesig_num = tonumber(get_text(beats_node)) or 4
                            timesig_denom = tonumber(get_text(beat_type_node)) or 4
                            bpi = timesig_num * (4.0 / timesig_denom)
                            item_time_sigs[m_idx] = { num = timesig_num, denom = timesig_denom }
                        end
                    end

                    local staves_node = get_first_child(child, "staves")
                    if staves_node then
                        local sc = tonumber(get_text(staves_node))
                        if sc then staves_count = sc end
                    end
                    if staves_count == 2 then
                        is_grand_part = true
                        if not state.track_clefs then state.track_clefs = {} end
                        if trk_guid and trk_guid ~= "" then
                            state.track_clefs[trk_guid] = "grand"
                        end
                    else
                        local clef_node = get_first_child(child, "clef")
                        if clef_node then
                            local sign_node = get_first_child(clef_node, "sign")
                            local line_node = get_first_child(clef_node, "line")
                            local sign = sign_node and get_text(sign_node)
                            local line = line_node and tonumber(get_text(line_node))
                            if not state.track_clefs then state.track_clefs = {} end
                            if trk_guid and trk_guid ~= "" then
                                if sign == "F" then
                                    state.track_clefs[trk_guid] = "bass"
                                elseif sign == "C" and line == 3 then
                                    state.track_clefs[trk_guid] = "alto"
                                elseif sign == "C" and line == 4 then
                                    state.track_clefs[trk_guid] = "tenor"
                                elseif sign == "G" then
                                    state.track_clefs[trk_guid] = "treble"
                                end
                            end
                        end
                    end

                -- --------------------------------------------------------------
                -- Backup & Forward (<backup>, <forward>)
                -- --------------------------------------------------------------
                elseif ctag == "backup" then
                    local dur_node = get_first_child(child, "duration")
                    if dur_node then
                        local d = tonumber(get_text(dur_node)) or 0
                        cur_div = math.max(0, cur_div - d)
                    end
                elseif ctag == "forward" then
                    local dur_node = get_first_child(child, "duration")
                    if dur_node then
                        local d = tonumber(get_text(dur_node)) or 0
                        cur_div = cur_div + d
                    end

                -- --------------------------------------------------------------
                -- Harmony / Chord & Scale Lane (<harmony>)
                -- --------------------------------------------------------------
                elseif ctag == "harmony" and options.import_chords ~= false and pi == 1 then
                    local root_node = get_first_child(child, "root")
                    local root_step = "C"
                    local root_alt = 0
                    if root_node then
                        local rs_node = get_first_child(root_node, "root-step")
                        if rs_node then root_step = get_text(rs_node) end
                        local ra_node = get_first_child(root_node, "root-alter")
                        if ra_node then root_alt = tonumber(get_text(ra_node)) or 0 end
                    end

                    local root_name = root_step
                    if root_alt == 1 then root_name = root_name .. "#"
                    elseif root_alt == -1 then root_name = root_name .. "b" end

                    local kind_node = get_first_child(child, "kind")
                    local kind_text = ""
                    if kind_node then
                        kind_text = (kind_node.attr and kind_node.attr.text) or get_text(kind_node)
                    end

                    local full_chord_text = root_name
                    if kind_text and kind_text ~= "" and kind_text ~= "major" and kind_text ~= "none" then
                        full_chord_text = root_name .. kind_text
                    end

                    local c_start = m_start_qn + (cur_div / divisions)
                    local c_end = m_start_qn + bpi

                    local chord_item = ChordItem.new({
                        text = full_chord_text,
                        start_qn = c_start,
                        end_qn = c_end,
                        root = STEP_TO_SEMITONE[root_step] or 0,
                        scale_type = "major"
                    })
                    if not state.chord_items then state.chord_items = {} end
                    table.insert(state.chord_items, chord_item)

                -- --------------------------------------------------------------
                -- Directions (Dynamics, Hairpins, Octaves, Pedals, Words/Text)
                -- --------------------------------------------------------------
                elseif ctag == "direction" then
                    local offset_node = get_first_child(child, "offset")
                    local off_div = offset_node and tonumber(get_text(offset_node)) or 0
                    local dir_qn = m_start_qn + ((cur_div + off_div) / divisions)

                    local dir_staff_node = get_first_child(child, "staff")
                    local dir_staff = dir_staff_node and tonumber(get_text(dir_staff_node)) or 1
                    local dir_types = get_all_children(child, "direction-type")

                    -- Tempo (<sound tempo="..."> or <metronome>)
                    local sound_node = get_first_child(child, "sound")
                    local sound_bpm = sound_node and sound_node.attr and tonumber(sound_node.attr.tempo)
                    local is_tempo_dir = false
                    if pi == 1 and (sound_bpm and sound_bpm > 0) then
                        is_tempo_dir = true
                        local words_txt = ""
                        for _, dt in ipairs(dir_types) do
                            local wn = get_first_child(dt, "words")
                            if wn then words_txt = get_text(wn) break end
                        end
                        table.insert(imported_tempo_markers, {
                            qn = dir_qn,
                            bpm = sound_bpm,
                            label = words_txt,
                            type = "absolute"
                        })
                    end

                    for _, dt in ipairs(dir_types) do
                        local metro_node = get_first_child(dt, "metronome")
                        if metro_node and pi == 1 then
                            is_tempo_dir = true
                            if not sound_bpm then
                                local per_min_node = get_first_child(metro_node, "per-minute")
                                local mbpm = per_min_node and tonumber(get_text(per_min_node))
                                if mbpm and mbpm > 0 then
                                    local words_node = get_first_child(dt, "words")
                                    local w_txt = words_node and get_text(words_node) or ""
                                    table.insert(imported_tempo_markers, {
                                        qn = dir_qn,
                                        bpm = mbpm,
                                        label = w_txt,
                                        type = "absolute"
                                    })
                                end
                            end
                        end

                        -- Dynamics (<dynamics><p/></dynamics>, <pp/>, etc.)
                        local dyn_node = get_first_child(dt, "dynamics")
                        local current_dyn_label = nil
                        if dyn_node and options.import_dynamics ~= false then
                            for _, d_tag in ipairs(dyn_node.children) do
                                local d_label = d_tag.tag or "f"
                                current_dyn_label = d_label
                                table.insert(track_dynamics, { qn = dir_qn, label = d_label, staff = dir_staff })
                            end
                        end

                        -- Hairpins / Wedges (<wedge type="crescendo|diminuendo|stop"/>)
                        local wedge_node = get_first_child(dt, "wedge")
                        if wedge_node and options.import_dynamics ~= false then
                            local wtype = wedge_node.attr and wedge_node.attr.type
                            local wedge_num = (wedge_node.attr and wedge_node.attr.number) or "1"
                            local wedge_key = string.format("%d_%d_%s", pi, dir_staff, wedge_num)

                            if wtype == "crescendo" or wtype == "diminuendo" then
                                active_wedges[wedge_key] = {
                                    pi = pi,
                                    type = wtype,
                                    start_qn = dir_qn,
                                    start_dyn = current_dyn_label,
                                    staff_num = dir_staff
                                }
                            elseif wtype == "stop" then
                                local active_w = active_wedges[wedge_key]
                                if not active_w then
                                    for k, w in pairs(active_wedges) do
                                        if w.pi == pi and w.staff_num == dir_staff then
                                            active_w = w
                                            active_wedges[k] = nil
                                            break
                                        end
                                    end
                                else
                                    active_wedges[wedge_key] = nil
                                end
                                if not active_w then
                                    for k, w in pairs(active_wedges) do
                                        if w.pi == pi then
                                            active_w = w
                                            active_wedges[k] = nil
                                            break
                                        end
                                    end
                                end

                                if active_w then
                                    local final_end_qn = dir_qn
                                    if final_end_qn <= active_w.start_qn + 0.05 then
                                        final_end_qn = active_w.start_qn + 1.0
                                    end
                                    local hp_staff = nil
                                    if is_grand_part or (staves_count == 2) then
                                        hp_staff = (active_w.staff_num == 2) and "bass" or "treble"
                                    end
                                    local hp = Hairpin.new({
                                        track_guid = trk_guid,
                                        type = active_w.type,
                                        start_qn = active_w.start_qn,
                                        end_qn = final_end_qn,
                                        start_dyn = active_w.start_dyn,
                                        end_dyn = current_dyn_label,
                                        staff = hp_staff
                                    })
                                    if not state.hairpins then state.hairpins = {} end
                                    table.insert(state.hairpins, hp)
                                end
                            end
                        end

                        -- Dynamic Dashes (for textual cresc. / dim. with dashes)
                        local dashes_node = get_first_child(dt, "dashes")
                        if dashes_node then
                            local dashtype = dashes_node.attr and dashes_node.attr.type
                            local dash_key = string.format("%d_%d", pi, dir_staff)
                            if dashtype == "stop" and active_dynamic_texts[dash_key] then
                                local adt = active_dynamic_texts[dash_key]
                                adt.end_qn = math.max(dir_qn, adt.start_qn + 0.5)
                                if not state.dynamic_texts then state.dynamic_texts = {} end
                                table.insert(state.dynamic_texts, adt)
                                active_dynamic_texts[dash_key] = nil
                            end
                        end

                        -- Octave Shift
                        local oct_node = get_first_child(dt, "octave-shift")
                        if oct_node and options.import_octaves ~= false then
                            local otype = oct_node.attr and oct_node.attr.type
                            local osize = tonumber(oct_node.attr and oct_node.attr.size) or 8
                            if otype == "up" or otype == "down" then
                                local shift = (osize >= 15) and 24 or 12
                                if otype == "down" then shift = -shift end
                                active_octaves[pi] = { shift = shift, start_qn = dir_qn }
                            elseif otype == "stop" and active_octaves[pi] then
                                local final_e = (dir_qn > active_octaves[pi].start_qn + 0.05) and dir_qn or (active_octaves[pi].start_qn + 1.0)
                                local oct = OctaveLine.new({
                                    track_guid = trk_guid,
                                    type = (active_octaves[pi].shift < 0) and "8vb" or "8va",
                                    start_qn = active_octaves[pi].start_qn,
                                    end_qn = final_e
                                })
                                if not state.octave_lines then state.octave_lines = {} end
                                table.insert(state.octave_lines, oct)
                                active_octaves[pi] = nil
                            end
                        end

                        -- Pedal
                        local ped_node = get_first_child(dt, "pedal")
                        if ped_node and options.import_pedals ~= false then
                            local ptype = ped_node.attr and ped_node.attr.type
                            if ptype == "start" then
                                active_pedals[pi] = { start_qn = dir_qn }
                            elseif ptype == "stop" and active_pedals[pi] then
                                local final_e = (dir_qn > active_pedals[pi].start_qn + 0.05) and dir_qn or (active_pedals[pi].start_qn + 1.0)
                                local ped = PedalMark.new({
                                    track_guid = trk_guid,
                                    start_qn = active_pedals[pi].start_qn,
                                    end_qn = final_e,
                                    style = "classic"
                                })
                                if not state.pedal_marks then state.pedal_marks = {} end
                                table.insert(state.pedal_marks, ped)
                                active_pedals[pi] = nil
                            end
                        end

                        -- Words / Text Items & Articulations & Textual Dynamics (cresc., dim.)
                        local words_node = get_first_child(dt, "words")
                        if words_node and not is_tempo_dir then
                            local txt = get_text(words_node)
                            if txt and txt ~= "" then
                                local clean_w = txt:lower():gsub("^%s+", ""):gsub("%s+$", "")
                                if clean_w:match("^cresc") or clean_w:match("^dim") or clean_w:match("^decresc") then
                                    local dash_key = string.format("%d_%d", pi, dir_staff)
                                    local dtype = (clean_w:match("^dim") or clean_w:match("^decresc")) and "diminuendo" or "crescendo"
                                    local dt_staff = nil
                                    if is_grand_part or (staves_count == 2) then
                                        dt_staff = (dir_staff == 2) and "bass" or "treble"
                                    end
                                    local dt_obj = DynamicText.new({
                                        track_guid = trk_guid,
                                        type = dtype,
                                        text = txt,
                                        start_qn = dir_qn,
                                        end_qn = dir_qn + 4.0,
                                        line_pattern = "dashed",
                                        staff = dt_staff
                                    })
                                    active_dynamic_texts[dash_key] = dt_obj
                                else
                                    local matched_art = detect_articulation_from_text(txt)
                                    local is_notehead_symbol = false
                                    if matched_art then
                                        local syms = { staccato=true, staccatissimo=true, tenuto=true, harmonic=true, marcato=true, accent=true }
                                        if syms[matched_art] then is_notehead_symbol = true end
                                        table.insert(pending_text_arts, {
                                            qn = dir_qn,
                                            art = matched_art,
                                            raw = txt
                                        })
                                    end

                                    -- Gould / Gardner Read standard: Instrumental performance techniques & words belong above the staff
                                    if (not is_notehead_symbol) and options.import_text_items ~= false then
                                        local dir_placement = child.attr and child.attr.placement
                                        local raw_fs = tonumber(words_node.attr and words_node.attr["font-size"])
                                        local fsize = 16.0
                                        if raw_fs and raw_fs > 0 then
                                            if raw_fs <= 11.0 then
                                                fsize = math.max(14.0, math.floor(raw_fs * 1.45 + 0.5))
                                            else
                                                fsize = raw_fs
                                            end
                                        end
                                        local fstyle = words_node.attr and words_node.attr["font-style"] or "italic"
                                        local ti = TextItem.new({
                                            track_guid = trk_guid,
                                            qn = dir_qn,
                                            text = txt,
                                            style = fstyle,
                                            font_size = fsize,
                                            offset_y = 18.0,
                                            placement = is_above and "above" or "below"
                                        })
                                        if not state.text_items then state.text_items = {} end
                                        table.insert(state.text_items, ti)
                                    end
                                end
                            end
                        end
                    end

                -- --------------------------------------------------------------
                -- Notes (<note>)
                -- --------------------------------------------------------------
                elseif ctag == "note" then
                    local is_rest = (get_first_child(child, "rest") ~= nil)
                    local is_chord = (get_first_child(child, "chord") ~= nil)

                    local dur_node = get_first_child(child, "duration")
                    local dur_div = dur_node and tonumber(get_text(dur_node)) or divisions
                    local dur_qn = math.max(0.0625, dur_div / divisions)

                    local voice_node = get_first_child(child, "voice")
                    local v_num = voice_node and tonumber(get_text(voice_node)) or 1

                    local staff_node = get_first_child(child, "staff")
                    local staff_id = staff_node and tonumber(get_text(staff_node)) or 1

                    local chan = 0
                    if is_grand_part or (staves_count == 2) then
                        if staff_id == 2 then
                            chan = 2 + (v_num > 1 and 1 or 0)
                        else
                            chan = (v_num > 1 and 1 or 0)
                        end
                    else
                        chan = math.max(0, math.min(15, v_num - 1))
                    end

                    if is_rest then
                        cur_div = cur_div + dur_div
                    else
                        local note_start_qn = m_start_qn + (cur_div / divisions)
                        if is_chord then
                            note_start_qn = last_onset_qn
                        else
                            last_onset_qn = note_start_qn
                            cur_div = cur_div + dur_div
                        end

                        local pitch_node = get_first_child(child, "pitch")
                        if pitch_node then
                            local step_node = get_first_child(pitch_node, "step")
                            local alter_node = get_first_child(pitch_node, "alter")
                            local oct_node = get_first_child(pitch_node, "octave")

                            local step = step_node and get_text(step_node) or "C"
                            local alter = alter_node and tonumber(get_text(alter_node)) or 0
                            local oct = oct_node and tonumber(get_text(oct_node)) or 4

                            local pitch = musicxml_to_pitch(step, alter, oct)

                            -- In Grand Staff without explicit staff node: assign channel based on pitch
                            if (is_grand_part or staves_count == 2) and not staff_node then
                                if pitch < 60 then
                                    chan = 2 + (v_num > 1 and 1 or 0)
                                else
                                    chan = (v_num > 1 and 1 or 0)
                                end
                            end

                            -- Accurate enharmonic accidental from MusicXML
                            local pref_acc = nil
                            local acc_node = get_first_child(child, "accidental")
                            if acc_node then
                                local atxt = get_text(acc_node)
                                if atxt == "sharp" or atxt == "double-sharp" then pref_acc = 1
                                elseif atxt == "flat" or atxt == "flat-flat" then pref_acc = -1
                                elseif atxt == "natural" then pref_acc = 2 end
                            end
                            if pref_acc == nil then
                                if alter == 1 then pref_acc = 1
                                elseif alter == -1 then pref_acc = -1
                                elseif alter == 0 and (step == "C" or step == "D" or step == "E" or step == "F" or step == "G" or step == "A" or step == "B") then
                                    pref_acc = 0
                                end
                            end

                            -- Check ties (<tie> and <notations><tied>)
                            local has_tie_start = false
                            local has_tie_stop = false
                            for _, tc in ipairs(get_all_children(child, "tie")) do
                                if tc.attr and tc.attr.type == "start" then has_tie_start = true end
                                if tc.attr and tc.attr.type == "stop" then has_tie_stop = true end
                            end

                            local notations_node = get_first_child(child, "notations")
                            if notations_node then
                                for _, tc in ipairs(get_all_children(notations_node, "tied")) do
                                    if tc.attr and tc.attr.type == "start" then has_tie_start = true end
                                    if tc.attr and tc.attr.type == "stop" then has_tie_stop = true end
                                end
                            end

                            -- Articulations
                            local note_art = nil
                            if notations_node then
                                local arts_node = get_first_child(notations_node, "articulations")
                                if arts_node then
                                    if get_first_child(arts_node, "staccatissimo") then note_art = "staccatissimo"
                                    elseif get_first_child(arts_node, "staccato") then note_art = "staccato"
                                    elseif get_first_child(arts_node, "spiccato") then note_art = "spiccato"
                                    elseif get_first_child(arts_node, "tenuto") then note_art = "tenuto"
                                    elseif get_first_child(arts_node, "accent") then note_art = "accent"
                                    elseif get_first_child(arts_node, "strong-accent") then note_art = "marcato"
                                    else
                                        local other_art_node = get_first_child(arts_node, "other-articulation")
                                        if other_art_node then
                                            local o_txt = get_text(other_art_node)
                                            note_art = detect_articulation_from_text(o_txt) or o_txt
                                        end
                                    end
                                end
                                if not note_art then
                                    local tech_node = get_first_child(notations_node, "technical")
                                    if tech_node then
                                        if get_first_child(tech_node, "harmonic") then note_art = "harmonic"
                                        elseif get_first_child(tech_node, "snap-pizzicato") then note_art = "snap-pizzicato"
                                        elseif get_first_child(tech_node, "up-bow") then note_art = "up-bow"
                                        elseif get_first_child(tech_node, "down-bow") then note_art = "down-bow"
                                        else
                                            local other_tech = get_first_child(tech_node, "other-technical")
                                            if other_tech then
                                                local o_txt = get_text(other_tech)
                                                note_art = detect_articulation_from_text(o_txt) or o_txt
                                            end
                                        end
                                    end
                                end
                                if not note_art then
                                    local orn_node = get_first_child(notations_node, "ornaments")
                                    if orn_node then
                                        if get_first_child(orn_node, "trill-mark") then note_art = "trill"
                                        elseif get_first_child(orn_node, "tremolo") then note_art = "tremolo"
                                        end
                                    end
                                end
                                if not note_art and get_first_child(notations_node, "fermata") then
                                    note_art = "fermata"
                                end
                            end

                            -- Check pending text articulations from <words>
                            if not note_art and #pending_text_arts > 0 then
                                for _, pa in ipairs(pending_text_arts) do
                                    if math.abs(note_start_qn - pa.qn) < 0.05 then
                                        note_art = pa.art
                                        break
                                    end
                                end
                            end

                            -- Merge tied notes across barlines/beats
                            local tie_key = string.format("%d_%d", chan, pitch)
                            local merged = false
                            if has_tie_stop and open_ties[tie_key] then
                                local open_note = open_ties[tie_key]
                                local expected_start = open_note.start_qn + open_note.dur_qn
                                if math.abs(expected_start - note_start_qn) < 0.1 then
                                    open_note.dur_qn = (note_start_qn + dur_qn) - open_note.start_qn
                                    merged = true
                                    if has_tie_start then
                                        open_ties[tie_key] = open_note
                                    else
                                        open_ties[tie_key] = nil
                                    end
                                end
                            end

                            if not merged then
                                local note_entry = {
                                    start_qn = note_start_qn,
                                    dur_qn = dur_qn,
                                    pitch = pitch,
                                    chan = chan,
                                    vel = 90,
                                    articulation = note_art,
                                    accidental = pref_acc
                                }
                                table.insert(track_notes, note_entry)
                                total_notes_imported = total_notes_imported + 1
                                if has_tie_start then
                                    open_ties[tie_key] = note_entry
                                end
                            end
                        end
                    end
                end
            end

            -- Advance measure start time
            cur_m_start_qn = cur_m_start_qn + bpi
        end

        -- Auto-close dangling directions for this part at score end
        for w_key, w_data in pairs(active_wedges) do
            if w_data and w_data.pi == pi then
                local auto_end_qn = math.max(w_data.start_qn + 1.0, cur_m_start_qn)
                local hp_staff = nil
                if is_grand_part or (staves_count == 2) then
                    hp_staff = (w_data.staff_num == 2) and "bass" or "treble"
                end
                local hp = Hairpin.new({
                    track_guid = trk_guid,
                    type = w_data.type,
                    start_qn = w_data.start_qn,
                    end_qn = auto_end_qn,
                    start_dyn = w_data.start_dyn,
                    end_dyn = w_data.end_dyn,
                    staff = hp_staff
                })
                if not state.hairpins then state.hairpins = {} end
                table.insert(state.hairpins, hp)
                active_wedges[w_key] = nil
            end
        end

        for d_key, dt_obj in pairs(active_dynamic_texts) do
            if dt_obj and d_key:match("^" .. tostring(pi) .. "_") then
                dt_obj.end_qn = math.max(dt_obj.start_qn + 1.0, cur_m_start_qn)
                if not state.dynamic_texts then state.dynamic_texts = {} end
                table.insert(state.dynamic_texts, dt_obj)
                active_dynamic_texts[d_key] = nil
            end
        end

        if active_octaves[pi] then
            local oct = OctaveLine.new({
                track_guid = trk_guid,
                type = (active_octaves[pi].shift < 0) and "8vb" or "8va",
                start_qn = active_octaves[pi].start_qn,
                end_qn = math.max(active_octaves[pi].start_qn + 1.0, cur_m_start_qn)
            })
            if not state.octave_lines then state.octave_lines = {} end
            table.insert(state.octave_lines, oct)
            active_octaves[pi] = nil
        end

        if active_pedals[pi] then
            local ped = PedalMark.new({
                track_guid = trk_guid,
                start_qn = active_pedals[pi].start_qn,
                end_qn = math.max(active_pedals[pi].start_qn + 1.0, cur_m_start_qn),
                style = "classic"
            })
            if not state.pedal_marks then state.pedal_marks = {} end
            table.insert(state.pedal_marks, ped)
            active_pedals[pi] = nil
        end

        -- ----------------------------------------------------------------------
        -- Create REAPER MediaItem and Insert Notes
        -- ----------------------------------------------------------------------
        if #track_notes > 0 and tr then
            local max_note_end = 4.0
            for _, n in ipairs(track_notes) do
                if n.start_qn + n.dur_qn > max_note_end then
                    max_note_end = n.start_qn + n.dur_qn
                end
            end

            -- Convert QN to project seconds
            local item_start_pos = reaper.TimeMap2_QNToTime(0, 0)
            local item_end_pos = reaper.TimeMap2_QNToTime(0, max_note_end + 1.0)
            local item_len = math.max(2.0, item_end_pos - item_start_pos)

            local item = reaper.CreateNewMIDIItemInProj(tr, item_start_pos, item_len, false)
            if item then
                local take = reaper.GetActiveTake(item)
                if take then
                    reaper.MIDI_DisableSort(take)
                    if not state.note_accidentals then state.note_accidentals = {} end
                    for _, n in ipairs(track_notes) do
                        local s_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, n.start_qn)
                        local e_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, n.start_qn + n.dur_qn)
                        reaper.MIDI_InsertNote(take, false, false, s_ppq, e_ppq, n.chan, n.pitch, n.vel, false)
                        if n.articulation and n.articulation ~= "" then
                            reaper.MIDI_InsertTextSysexEvt(take, false, false, s_ppq, 15, string.format("NOTE %d %d a %s", n.pitch, n.chan, n.articulation))
                        end
                        if n.accidental ~= nil then
                            local pos_k = string.format("%s_%.3f_%d", tostring(take), n.start_qn, n.pitch)
                            local full_k = string.format("%s_%s_%.3f_%d_%d", tostring(item), tostring(take), n.start_qn, n.pitch, n.chan or 0)
                            state.note_accidentals[pos_k] = n.accidental
                            state.note_accidentals[full_k] = n.accidental
                        end
                    end
                    for _, d in ipairs(track_dynamics) do
                        local d_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, d.qn) + 0.5)
                        local lk = DYN_LOOKUP[d.label:lower()] or { c1 = 80, c2 = 85 }
                        reaper.MIDI_InsertTextSysexEvt(take, false, false, d_ppq, 15, string.format("dynamic %s :%d:%d", d.label, lk.c1, lk.c2))
                    end
                    reaper.MIDI_Sort(take)

                    local has_dyn = (#track_dynamics > 0)
                    if not has_dyn and state and state.hairpins then
                        for _, hp in ipairs(state.hairpins) do
                            if hp.track_guid == trk_guid then
                                has_dyn = true
                                break
                            end
                        end
                    end
                    if has_dyn then
                        table.insert(takes_with_dynamics, take)
                    end

                    -- Also register note accidentals with take note index (id_k)
                    local _, notecnt = reaper.MIDI_CountEvts(take)
                    for ni = 0, notecnt - 1 do
                        local ok, _, _, sppq, _, _, pitch, _ = reaper.MIDI_GetNote(take, ni)
                        if ok then
                            local sqn = reaper.MIDI_GetProjQNFromPPQPos(take, sppq)
                            for _, n in ipairs(track_notes) do
                                if n.pitch == pitch and math.abs(n.start_qn - sqn) < 0.05 and n.accidental ~= nil then
                                    local id_k = string.format("%s_%d_%.3f", tostring(take), ni, sqn)
                                    state.note_accidentals[id_k] = n.accidental
                                    break
                                end
                            end
                        end
                    end

                    -- Apply initial Key Signature to item
                    if item_key_sigs[1] then
                        KeySignatureService.set_item_key_sig(state, item, take, item_key_sigs[1].idx, item_key_sigs[1].mode, false)
                        if state then
                            state.selected_key_sig = item_key_sigs[1].idx
                            state.selected_key_mode = item_key_sigs[1].mode
                        end
                    end
                    if item_time_sigs[1] then
                        KeySignatureService.set_item_time_sig(state, item, take, item_time_sigs[1].num, item_time_sigs[1].denom)
                        if state then
                            state.time_sig_num = item_time_sigs[1].num
                            state.time_sig_denom = item_time_sigs[1].denom
                        end
                    end
                end
            end
        end
    end

    -- Sync imported tempo markers into Notator state and REAPER
    if #imported_tempo_markers > 0 then
        local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
        local TempoMarker = package.loaded["classes.tempo_marker"] or require("classes.tempo_marker")
        if state then
            state.tempo_markers = {}
            for _, itm in ipairs(imported_tempo_markers) do
                local tm = TempoMarker.new({
                    type = itm.type or "absolute",
                    label = itm.label or "",
                    bpm = itm.bpm,
                    start_qn = itm.qn,
                    end_qn = itm.qn + 4.0,
                    custom_bpm_only = (not itm.label or itm.label == "")
                })
                table.insert(state.tempo_markers, tm)
            end
            TempoService.save_markers(state)
            TempoService.sync_all_to_reaper(state)
        end
    end

    -- Persist all imported objects to project and takes
    if state then
        if HairpinService and HairpinService.save_hairpins then
            HairpinService.save_hairpins(state)
        end
        local OctaveService = package.loaded["services.octave_service"] or require("services.octave_service")
        if OctaveService and OctaveService.save_lines then
            OctaveService.save_lines(state)
        end
        local PedalService = package.loaded["services.pedal_service"] or require("services.pedal_service")
        if PedalService and PedalService.save_pedals then
            PedalService.save_pedals(state)
        end
        local TextItemService = package.loaded["services.text_item_service"] or require("services.text_item_service")
        if TextItemService and TextItemService.save_text_items then
            TextItemService.save_text_items(state)
        end
        if DynamicTextService and DynamicTextService.save_dynamic_texts then
            DynamicTextService.save_dynamic_texts(state)
        end
        local ScaleService = package.loaded["services.scale_service"] or require("services.scale_service")
        if ScaleService and ScaleService.save_chord_items then
            ScaleService.save_chord_items(state)
        end
        if KeySignatureService and KeySignatureService.save then
            KeySignatureService.save(state)
        end
        if state.save_to_project then
            state:save_to_project()
        end
    end

    -- Automatically reblend every track with dynamics (Smart Re-Blend)
    local DynamicsEngine = package.loaded["services.dynamics_engine"] or require("services.dynamics_engine")
    if DynamicsEngine and DynamicsEngine.smart_reblend_all and #takes_with_dynamics > 0 then
        for _, d_take in ipairs(takes_with_dynamics) do
            if d_take and reaper.ValidatePtr(d_take, "MediaItem_Take*") and reaper.TakeIsMIDI(d_take) then
                pcall(DynamicsEngine.smart_reblend_all, state, MidiService, {}, d_take)
            end
        end
    end

    -- Flush caches & mark project dirty
    MidiService.invalidate_cache()
    if state then state.active_tracks_cache = nil end
    reaper.MarkProjectDirty(0)
    if reaper.UpdateArrange then reaper.UpdateArrange() end

    local success_msg = string.format("Imported %d tracks, %d notes, %d measures from MusicXML.", #parts, total_notes_imported, total_measures_imported)
    if state then state.status_msg = success_msg end

    return true, success_msg, total_notes_imported, #parts
end

return MusicXmlImportService

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
local GlissandoMark = require("classes.glissando_mark")
local PortamentoMark = require("classes.portamento_mark")
local KeySignatureService = require("services.key_signature_service")
local MidiService = require("services.midi_service")
local HairpinService = require("services.hairpin_service")
local DynamicTextService = require("services.dynamic_text_service")
local ReaticulateParser = require("services.reaticulate_parser")
local SlurService = require("services.slur_service")
local GlissandoService = require("services.glissando_service")
local PortamentoService = require("services.portamento_service")

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
    ["staccato dig"] = "staccato",
    ["dig"] = "staccato",
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
-- Reaticulate Matching Helper
-- ------------------------------------------------------------------------------
local function find_best_bank_for_part_name(pname, all_banks)
    if not all_banks or #all_banks == 0 then return nil end
    local lower_p = (pname or ""):lower()

    -- 1. Exact match on bank name
    for _, b in ipairs(all_banks) do
        local lower_b = (b.name or ""):lower()
        if lower_b:find(lower_p, 1, true) or lower_p:find(lower_b, 1, true) then
            return b
        end
    end

    -- 2. Specific instrument token matching (violins 1/2, viola, cello, bass, etc.)
    local specific_tokens = {
        "violin 1", "violin 2", "violins 1", "violins 2", "viola", "violas",
        "cello", "cellos", "celli", "double bass", "basses", "contrabass",
        "flute", "oboe", "clarinet", "bassoon", "horn", "trumpet", "trombone", "tuba", "timpani"
    }
    for _, tok in ipairs(specific_tokens) do
        if lower_p:find(tok, 1, true) then
            for _, b in ipairs(all_banks) do
                local lower_b = (b.name or ""):lower()
                if lower_b:find(tok, 1, true) then
                    return b
                end
            end
        end
    end

    -- 3. Any word token >= 4 chars
    for word in lower_p:gmatch("%a+") do
        if #word >= 4 and word ~= "part" and word ~= "track" and word ~= "midi" then
            for _, b in ipairs(all_banks) do
                if (b.name or ""):lower():find(word, 1, true) then
                    return b
                end
            end
        end
    end

    -- 4. Dummy / generic orchestral fallback: string bank or first available bank
    for _, b in ipairs(all_banks) do
        local lb = (b.name or ""):lower()
        if lb:find("string") or lb:find("violin") or lb:find("orchestra") then
            return b
        end
    end

    return all_banks[1]
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

    -- Reset bow swelling to 0.0 and bow position to 0.50 on import
    if state then
        state.dyn_bow_intensity = 0.0
        state.dyn_bow_pos = 0.50
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
    local do_import_slurs_ties = (options.import_slurs_ties ~= false)
    local do_import_gliss_port = (options.import_gliss_port ~= false)
    local target_tracks = {}
    local target_banks = {}

    if state then
        state.user_slurs = state.user_slurs or {}
        state.user_ties = state.user_ties or {}
        state.glissando_marks = state.glissando_marks or {}
        state.portamento_marks = state.portamento_marks or {}
    end

    local all_banks = ReaticulateParser.get_all_banks()
    local reaticulate_installed = (all_banks and #all_banks > 0)
    if not reaticulate_installed then
        if reaper.APIExists("ShowMessageBox") then
            reaper.ShowMessageBox(
                "Reaticulate is not installed or no .reabank articulation banks were found.\n\n" ..
                "The notes and musical notations were successfully imported, but installing Reaticulate is recommended to enable articulation playback switching and bank mapping.",
                "REAPER-Notator: Reaticulate Notice",
                0
            )
        end
    end

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

        -- Compact / collapse track height in REAPER TCP (standard compact view)
        if options.compact_tracks ~= false and tr and reaper.ValidatePtr(tr, "MediaTrack*") then
            reaper.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", 25)
        end

        -- Apply Reaticulate bank and FX to track if available
        if reaticulate_installed and tr and reaper.ValidatePtr(tr, "MediaTrack*") then
            local best_bank = find_best_bank_for_part_name(pname, all_banks)
            if best_bank then
                target_banks[pi] = best_bank

                -- Add Reaticulate.jsfx to track FX chain if not already present
                local has_fx = false
                local fx_count = reaper.TrackFX_GetCount(tr)
                for fxi = 0, fx_count - 1 do
                    local _, fx_name = reaper.TrackFX_GetFXName(tr, fxi, "")
                    if fx_name:lower():find("reaticulate") then
                        has_fx = true
                        break
                    end
                end
                if not has_fx then
                    local fx_idx = reaper.TrackFX_AddByName(tr, "Reaticulate.jsfx", false, -1)
                    if fx_idx < 0 then
                        reaper.TrackFX_AddByName(tr, "Reaticulate", false, -1)
                    end
                end

                -- Configure P_EXT:reaticulate JSON on the track
                local bank_val = (best_bank.id and best_bank.id ~= "") and best_bank.id or (best_bank.msb * 128 + (best_bank.lsb >= 0 and best_bank.lsb or 0))
                local reat_json = string.format('2{"y":0,"v":1,"defchan":1,"banks":[{"dst":17,"v":%s,"src":17,"t":"g","dstbus":1,"name":"%s"}]}',
                    (type(bank_val) == "string" and ('"' .. bank_val .. '"') or tostring(bank_val)),
                    (best_bank.name or ""):gsub('"', '\\"'))
                reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:reaticulate", reat_json, true)

                local trk_guid = reaper.GetTrackGUID(tr)
                if not state.track_articulation_banks then state.track_articulation_banks = {} end
                state.track_articulation_banks[trk_guid] = (best_bank.id and best_bank.id ~= "") and best_bank.id or best_bank.name
            end
        end
    end

    local total_notes_imported = 0
    local total_measures_imported = 0
    local do_import_keys = (options.import_keys ~= false)
    local score_initial_key_sig = nil
    local score_initial_time_sig = nil

    -- Tracking active directions across measures
    local active_wedges = {}
    local active_dynamic_texts = {}
    local active_octaves = {}
    local active_pedals = {}
    local imported_tempo_markers = {}
    local imported_fermatas = {}
    local imported_fermatas_seen = {}
    local imported_rehearsal_marks = {}
    local imported_rehearsal_seen = {}
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
        local item_key_sigs_list = {}
        local item_time_sigs = {}
        local item_time_sigs_list = {}
        local pending_text_arts = {}
        local open_ties = {} -- [string.format("%d_%d", chan, pitch)] = { note_entry = note_entry, tie_id = tie_id }
        local open_slurs = {} -- [string.format("%d_%d", chan, slur_num)] = { note_entry = note_entry, slur_id = slur_id }
        local open_glissandi = {} -- [string.format("%d_%d", chan, gliss_num)] = { note_entry = note_entry, gliss_id = gliss_id }
        local open_slides = {} -- [string.format("%d_%d", chan, slide_num)] = { note_entry = note_entry, port_id = port_id }

        local part_ties = {} -- list of { id = tie_id, n1 = n1, n2 = n2, chan = chan, pitch = pitch }
        local part_slurs = {} -- list of { id = slur_id, n1 = n1, n2 = n2, chan = chan }
        local part_glissandi = {} -- list of { id = gliss_id, n1 = n1, n2 = n2, chan = chan }
        local part_slides = {} -- list of { id = port_id, n1 = n1, n2 = n2, chan = chan }
        local cur_m_start_qn = 0.0

        for m_idx, m_node in ipairs(measures) do
            local mi = m_idx
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
                    if key_node and do_import_keys then
                        local fifths_node = get_first_child(key_node, "fifths")
                        if fifths_node then
                            cur_key_idx = tonumber(get_text(fifths_node)) or 0
                        else
                            local cancel_node = get_first_child(key_node, "cancel")
                            if cancel_node then
                                cur_key_idx = 0
                            end
                        end
                        local mode_node = get_first_child(key_node, "mode")
                        if mode_node then
                            cur_key_mode = get_text(mode_node) or "major"
                        end
                        local kentry = { idx = cur_key_idx, mode = cur_key_mode, start_qn = m_start_qn, m_idx = m_idx }
                        item_key_sigs[m_idx] = kentry
                        table.insert(item_key_sigs_list, kentry)
                        if not score_initial_key_sig then
                            score_initial_key_sig = { idx = cur_key_idx, mode = cur_key_mode }
                        end
                    end

                    local time_node = get_first_child(child, "time")
                    if time_node and do_import_keys then
                        local beats_node = get_first_child(time_node, "beats")
                        local beat_type_node = get_first_child(time_node, "beat-type")
                        if beats_node and beat_type_node then
                            timesig_num = tonumber(get_text(beats_node)) or 4
                            timesig_denom = tonumber(get_text(beat_type_node)) or 4
                            bpi = timesig_num * (4.0 / timesig_denom)
                            local tentry = { num = timesig_num, denom = timesig_denom, start_qn = m_start_qn, m_idx = m_idx }
                            item_time_sigs[m_idx] = tentry
                            table.insert(item_time_sigs_list, tentry)
                            if not score_initial_time_sig then
                                score_initial_time_sig = { num = timesig_num, denom = timesig_denom }
                            end
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

                        -- Rehearsal Marks (<rehearsal>A</rehearsal>)
                        local reh_node = get_first_child(dt, "rehearsal")
                        if reh_node and pi == 1 then
                            local r_txt = get_text(reh_node) or ""
                            r_txt = r_txt:gsub("^%s+", ""):gsub("%s+$", "")
                            local m_type = "letter"
                            if tonumber(r_txt) then
                                m_type = "number"
                            elseif #r_txt > 2 or not r_txt:match("^[A-Za-z]$") then
                                m_type = "custom"
                            end
                            local rm_key = string.format("%d_%.2f", m_idx - 1, dir_qn)
                            if not imported_rehearsal_seen[rm_key] then
                                imported_rehearsal_seen[rm_key] = true
                                table.insert(imported_rehearsal_marks, {
                                    measure = m_idx - 1,
                                    qn = dir_qn,
                                    type = m_type,
                                    custom_text = (m_type == "custom") and r_txt or "",
                                    label = r_txt
                                })
                            end
                        end

                        -- Segno (<segno/>)
                        local segno_node = get_first_child(dt, "segno")
                        if segno_node and pi == 1 then
                            local rm_key = string.format("segno_%d_%.2f", m_idx - 1, dir_qn)
                            if not imported_rehearsal_seen[rm_key] then
                                imported_rehearsal_seen[rm_key] = true
                                table.insert(imported_rehearsal_marks, {
                                    measure = m_idx - 1,
                                    qn = dir_qn,
                                    type = "segno",
                                    label = utf8.char(0xE047)
                                })
                            end
                        end

                        -- Coda (<coda/>)
                        local coda_node = get_first_child(dt, "coda")
                        if coda_node and pi == 1 then
                            local rm_key = string.format("coda_%d_%.2f", m_idx - 1, dir_qn)
                            if not imported_rehearsal_seen[rm_key] then
                                imported_rehearsal_seen[rm_key] = true
                                table.insert(imported_rehearsal_marks, {
                                    measure = m_idx - 1,
                                    qn = dir_qn,
                                    type = "coda",
                                    label = utf8.char(0xE048)
                                })
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
                                local nav_type = nil
                                if clean_w == "d.c. al fine" or clean_w == "dc al fine" or clean_w == "da capo al fine" then
                                    nav_type = "dc_al_fine"
                                elseif clean_w == "d.s. al coda" or clean_w == "ds al coda" or clean_w == "dal segno al coda" then
                                    nav_type = "ds_al_coda"
                                elseif clean_w == "d.c." or clean_w == "dc" or clean_w == "da capo" then
                                    nav_type = "dc"
                                elseif clean_w == "d.s." or clean_w == "ds" or clean_w == "dal segno" then
                                    nav_type = "ds"
                                elseif clean_w == "fine" then
                                    nav_type = "fine"
                                end

                                if nav_type and pi == 1 then
                                    local rm_key = string.format("%s_%d_%.2f", nav_type, m_idx - 1, dir_qn)
                                    if not imported_rehearsal_seen[rm_key] then
                                        imported_rehearsal_seen[rm_key] = true
                                        table.insert(imported_rehearsal_marks, {
                                            measure = m_idx - 1,
                                            qn = dir_qn,
                                            type = nav_type
                                        })
                                    end
                                elseif clean_w:match("^cresc") or clean_w:match("^dim") or clean_w:match("^decresc") then
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
                                        local syms = { staccato=true, staccatissimo=true, tenuto=true, harmonic=true, marcato=true, accent=true, legato=true, slur=true }
                                        if syms[matched_art] then is_notehead_symbol = true end
                                        table.insert(pending_text_arts, {
                                            qn = dir_qn,
                                            art = matched_art,
                                            raw = txt
                                        })
                                    end

                                    -- Gould / Gardner Read standard: Instrumental performance techniques & words belong above the staff
                                    local is_legato_or_slur = (clean_w == "legato" or clean_w == "slur" or clean_w:match("^legato") or matched_art == "legato")
                                    if (not is_notehead_symbol) and (not is_legato_or_slur) and options.import_text_items ~= false then
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

                            local notations_nodes = get_all_children(child, "notations")
                            for _, n_node in ipairs(notations_nodes) do
                                for _, tc in ipairs(get_all_children(n_node, "tied")) do
                                    local t_type = tc.attr and tc.attr.type and tostring(tc.attr.type):lower()
                                    if t_type == "start" then has_tie_start = true end
                                    if t_type == "stop" then has_tie_stop = true end
                                end
                            end

                            -- Articulations
                            local note_art = nil
                            for _, n_node in ipairs(notations_nodes) do
                                local arts_node = get_first_child(n_node, "articulations")
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
                                    local tech_node = get_first_child(n_node, "technical")
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
                                    local orn_node = get_first_child(n_node, "ornaments")
                                    if orn_node then
                                        if get_first_child(orn_node, "trill-mark") then note_art = "trill"
                                        elseif get_first_child(orn_node, "tremolo") then note_art = "tremolo"
                                        end
                                    end
                                end

                                -- Arpeggio (<arpeggiate direction="up|down"/>)
                                local arp_node = get_first_child(n_node, "arpeggiate")
                                if arp_node then
                                    note_arp = (arp_node.attr and arp_node.attr.direction == "down") and "down" or "up"
                                end

                                -- Fermata (<fermata type="upright">normal</fermata>)
                                local ferm_node = get_first_child(n_node, "fermata")
                                if ferm_node then
                                    note_art = "fermata"
                                    local ferm_shape = get_text(ferm_node) or ""
                                    local f_type = "standard"
                                    local h_fac = 1.5
                                    if ferm_shape:match("angled") then
                                        f_type = "short"
                                        h_fac = 1.25
                                    elseif ferm_shape:match("square") then
                                        f_type = "long"
                                        h_fac = 2.0
                                    elseif ferm_shape:match("double%-square") then
                                        f_type = "very_long"
                                        h_fac = 2.5
                                    end

                                    local qn_key = string.format("%.2f", note_start_qn)
                                    if not imported_fermatas_seen[qn_key] then
                                        imported_fermatas_seen[qn_key] = true
                                        table.insert(imported_fermatas, {
                                            qn = note_start_qn,
                                            measure = m_idx - 1,
                                            type = f_type,
                                            hold_factor = h_fac
                                        })
                                    end
                                end
                            end

                            -- Check notations for slurs, glissandi, and slides
                            local note_slur_starts = {}
                            local note_slur_stops = {}
                            local note_gliss_starts = {}
                            local note_gliss_stops = {}
                            local note_slide_starts = {}
                            local note_slide_stops = {}

                            for _, n_node in ipairs(notations_nodes) do
                                for _, sc in ipairs(get_all_children(n_node, "slur")) do
                                    local s_type = sc.attr and sc.attr.type and tostring(sc.attr.type):lower():match("^%s*(.-)%s*$")
                                    local s_num = tonumber(sc.attr and sc.attr.number) or 1
                                    if s_type == "start" then table.insert(note_slur_starts, s_num) end
                                    if s_type == "stop" then table.insert(note_slur_stops, s_num) end
                                end

                                for _, gc in ipairs(get_all_children(n_node, "glissando")) do
                                    local g_type = gc.attr and gc.attr.type and tostring(gc.attr.type):lower():match("^%s*(.-)%s*$")
                                    local g_num = tonumber(gc.attr and gc.attr.number) or 1
                                    if g_type == "start" then table.insert(note_gliss_starts, g_num) end
                                    if g_type == "stop" then table.insert(note_gliss_stops, g_num) end
                                end

                                for _, sc in ipairs(get_all_children(n_node, "slide")) do
                                    local s_type = sc.attr and sc.attr.type and tostring(sc.attr.type):lower():match("^%s*(.-)%s*$")
                                    local s_num = tonumber(sc.attr and sc.attr.number) or 1
                                    if s_type == "start" then table.insert(note_slide_starts, s_num) end
                                    if s_type == "stop" then table.insert(note_slide_stops, s_num) end
                                end

                                for _, on in ipairs(get_all_children(n_node, "other-notation")) do
                                    local o_type = (on.attr and on.attr.type or ""):lower()
                                    local o_txt = (get_text(on) or ""):lower()
                                    if o_type:find("gliss") or o_txt:find("gliss") then
                                        if on.attr and on.attr.type == "start" then table.insert(note_gliss_starts, 1) end
                                        if on.attr and on.attr.type == "stop" then table.insert(note_gliss_stops, 1) end
                                    elseif o_type:find("port") or o_txt:find("port") or o_type:find("slide") then
                                        if on.attr and on.attr.type == "start" then table.insert(note_slide_starts, 1) end
                                        if on.attr and on.attr.type == "stop" then table.insert(note_slide_stops, 1) end
                                    end
                                end
                            end

                            -- Also check direct child <slur> on <note> (handles non-standard MusicXML files)
                            for _, sc in ipairs(get_all_children(child, "slur")) do
                                local s_type = sc.attr and sc.attr.type and tostring(sc.attr.type):lower():match("^%s*(.-)%s*$")
                                local s_num = tonumber(sc.attr and sc.attr.number) or 1
                                if s_type == "start" then table.insert(note_slur_starts, s_num) end
                                if s_type == "stop" then table.insert(note_slur_stops, s_num) end
                            end

                            -- Check pending text articulations from <words>
                            if #pending_text_arts > 0 then
                                for _, pa in ipairs(pending_text_arts) do
                                    if math.abs(note_start_qn - pa.qn) < 0.05 then
                                        if not note_art then
                                            note_art = pa.art
                                        end
                                        local pa_txt = tostring(pa.art):lower()
                                        if pa_txt:find("gliss") then
                                            table.insert(note_gliss_starts, 1)
                                        elseif pa_txt:find("port") or pa_txt:find("slide") then
                                            table.insert(note_slide_starts, 1)
                                        end
                                    end
                                end
                            end

                            local note_entry = {
                                start_qn = note_start_qn,
                                dur_qn = dur_qn,
                                pitch = pitch,
                                chan = chan,
                                vel = 90,
                                articulation = note_art,
                                arpeggio = note_arp,
                                accidental = pref_acc
                            }
                            table.insert(track_notes, note_entry)
                            total_notes_imported = total_notes_imported + 1

                            -- Ties handling (dual-reality preservation)
                            if do_import_slurs_ties then
                                local tie_key = string.format("%d_%d", chan, pitch)
                                local prev_info = open_ties[tie_key] or open_ties[pitch]
                                if has_tie_stop and prev_info then
                                    local prev_note = prev_info.note_entry
                                    local t_id = prev_info.tie_id

                                    prev_note.is_tied_master = true
                                    prev_note.tie_id = t_id
                                    prev_note.tied_to_note = note_entry
                                    note_entry.is_tied_slave = true
                                    note_entry.tie_id = t_id

                                    table.insert(part_ties, {
                                        id = t_id,
                                        n1 = prev_note,
                                        n2 = note_entry,
                                        chan = prev_note.chan or chan,
                                        pitch = pitch
                                    })

                                    if has_tie_start then
                                        local next_tie_id = "tie_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
                                        open_ties[tie_key] = { note_entry = note_entry, tie_id = next_tie_id }
                                    else
                                        open_ties[tie_key] = nil
                                        open_ties[pitch] = nil
                                    end
                                elseif has_tie_start then
                                    local new_tie_id = "tie_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
                                    open_ties[tie_key] = { note_entry = note_entry, tie_id = new_tie_id }
                                end
                            end

                            -- Slurs handling (robust MusicXML part-level numbering across staves & voices)
                            if do_import_slurs_ties then
                                for _, s_num in ipairs(note_slur_stops) do
                                    local ch_key = string.format("%d_%d", chan, s_num)
                                    local prev_sl = open_slurs[ch_key]
                                    local matched_key = ch_key
                                    if not prev_sl then
                                        local fallback_ch1 = string.format("%d_1", chan)
                                        if open_slurs[fallback_ch1] then
                                            prev_sl = open_slurs[fallback_ch1]
                                            matched_key = fallback_ch1
                                        end
                                    end
                                    if not prev_sl then
                                        -- Look for open slur on same channel
                                        local ch_prefix = string.format("%d_", chan)
                                        for k, sl_cand in pairs(open_slurs) do
                                            if type(k) == "string" and k:sub(1, #ch_prefix) == ch_prefix then
                                                prev_sl = sl_cand
                                                matched_key = k
                                                break
                                            end
                                        end
                                    end
                                    if not prev_sl then
                                        -- Look for cross-channel match by s_num
                                        for k, sl_cand in pairs(open_slurs) do
                                            if (type(k) == "number" and k == s_num) or (type(k) == "string" and k:match("_" .. tostring(s_num) .. "$")) then
                                                prev_sl = sl_cand
                                                matched_key = k
                                                break
                                            end
                                        end
                                    end
                                    if not prev_sl then
                                        for k, sl_cand in pairs(open_slurs) do
                                            prev_sl = sl_cand
                                            matched_key = k
                                            break
                                        end
                                    end
                                    if prev_sl then
                                        table.insert(part_slurs, {
                                            id = prev_sl.slur_id,
                                            n1 = prev_sl.note_entry,
                                            n2 = note_entry,
                                            chan = prev_sl.note_entry.chan or chan
                                        })
                                        open_slurs[matched_key] = nil
                                    end
                                end
                                for _, s_num in ipairs(note_slur_starts) do
                                    local ch_key = string.format("%d_%d", chan, s_num)
                                    if not (is_chord and open_slurs[ch_key] and math.abs(open_slurs[ch_key].note_entry.start_qn - note_start_qn) < 0.001) then
                                        local new_slur_id = "slur_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
                                        open_slurs[ch_key] = { note_entry = note_entry, slur_id = new_slur_id }
                                    end
                                end
                            end

                            -- Glissandi handling
                            if do_import_gliss_port then
                                for _, g_num in ipairs(note_gliss_stops) do
                                    local ch_key = string.format("%d_%d", chan, g_num)
                                    local prev_gl = open_glissandi[ch_key] or open_glissandi[g_num]
                                    local matched_key = ch_key
                                    if not prev_gl then
                                        local fallback_ch1 = string.format("%d_1", chan)
                                        if open_glissandi[fallback_ch1] then
                                            prev_gl = open_glissandi[fallback_ch1]
                                            matched_key = fallback_ch1
                                        elseif open_glissandi[1] then
                                            prev_gl = open_glissandi[1]
                                            matched_key = 1
                                        else
                                            for k, gl_cand in pairs(open_glissandi) do
                                                prev_gl = gl_cand
                                                matched_key = k
                                                break
                                            end
                                        end
                                    end
                                    if prev_gl then
                                        table.insert(part_glissandi, {
                                            id = prev_gl.gliss_id,
                                            n1 = prev_gl.note_entry,
                                            n2 = note_entry,
                                            chan = prev_gl.note_entry.chan or chan
                                        })
                                        open_glissandi[matched_key] = nil
                                    end
                                end
                                for _, g_num in ipairs(note_gliss_starts) do
                                    local ch_key = string.format("%d_%d", chan, g_num)
                                    local new_gliss_id = "gliss_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
                                    open_glissandi[ch_key] = { note_entry = note_entry, gliss_id = new_gliss_id }
                                end
                            end

                            -- Slides / Portamento handling
                            if do_import_gliss_port then
                                for _, s_num in ipairs(note_slide_stops) do
                                    local ch_key = string.format("%d_%d", chan, s_num)
                                    local prev_sl = open_slides[ch_key] or open_slides[s_num]
                                    local matched_key = ch_key
                                    if not prev_sl then
                                        local fallback_ch1 = string.format("%d_1", chan)
                                        if open_slides[fallback_ch1] then
                                            prev_sl = open_slides[fallback_ch1]
                                            matched_key = fallback_ch1
                                        elseif open_slides[1] then
                                            prev_sl = open_slides[1]
                                            matched_key = 1
                                        else
                                            for k, sl_cand in pairs(open_slides) do
                                                prev_sl = sl_cand
                                                matched_key = k
                                                break
                                            end
                                        end
                                    end
                                    if prev_sl then
                                        table.insert(part_slides, {
                                            id = prev_sl.port_id,
                                            n1 = prev_sl.note_entry,
                                            n2 = note_entry,
                                            chan = prev_sl.note_entry.chan or chan
                                        })
                                        open_slides[matched_key] = nil
                                    end
                                end
                                for _, s_num in ipairs(note_slide_starts) do
                                    local ch_key = string.format("%d_%d", chan, s_num)
                                    local new_port_id = "port_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
                                    open_slides[ch_key] = { note_entry = note_entry, port_id = new_port_id }
                                end
                            end
                        end
                    end
                end
            end

            -- Advance measure start time
            cur_m_start_qn = cur_m_start_qn + bpi
        end

        -- Inherit score-level initial key/time signatures if this part did not define them explicitly
        if do_import_keys and #item_key_sigs_list == 0 and score_initial_key_sig then
            local inherited_k = { idx = score_initial_key_sig.idx, mode = score_initial_key_sig.mode, start_qn = 0.0, m_idx = 1 }
            item_key_sigs[1] = inherited_k
            table.insert(item_key_sigs_list, inherited_k)
        end
        if do_import_keys and #item_time_sigs_list == 0 and score_initial_time_sig then
            local inherited_t = { num = score_initial_time_sig.num, denom = score_initial_time_sig.denom, start_qn = 0.0, m_idx = 1 }
            item_time_sigs[1] = inherited_t
            table.insert(item_time_sigs_list, inherited_t)
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

                    -- Group notes by start_qn to calculate arpeggio micro-strumming (treppe)
                    local arp_groups = {}
                    for _, n in ipairs(track_notes) do
                        if n.arpeggio then
                            local k = string.format("%.3f", n.start_qn)
                            if not arp_groups[k] then arp_groups[k] = {} end
                            table.insert(arp_groups[k], n)
                        end
                    end
                    for _, grp in pairs(arp_groups) do
                        if #grp > 1 then
                            local arp_dir = grp[1].arpeggio or "up"
                            table.sort(grp, function(a, b)
                                if arp_dir == "down" then
                                    return a.pitch > b.pitch
                                else
                                    return a.pitch < b.pitch
                                end
                            end)
                            for i, n in ipairs(grp) do
                                n.strum_offset_ppq = (i - 1) * 18
                            end
                        end
                    end

                    -- Determine extended end for tie masters (chaining)
                    for _, t in ipairs(part_ties) do
                        local n1 = t.n1
                        local n2 = t.n2
                        local chain_end_qn = n2.start_qn + n2.dur_qn
                        local curr = n2
                        while curr.tied_to_note do
                            curr = curr.tied_to_note
                            chain_end_qn = curr.start_qn + curr.dur_qn
                        end
                        n1.tied_chain_end_qn = chain_end_qn
                    end

                    for _, n in ipairs(track_notes) do
                        local base_s_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n.start_qn) + 0.5)
                        local s_ppq = base_s_ppq + (n.strum_offset_ppq or 0)
                        if not n.is_tied_slave then
                            local eff_end_qn = n.tied_chain_end_qn or (n.start_qn + n.dur_qn)
                            local e_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, eff_end_qn) + 0.5)
                            if n.strum_offset_ppq and n.strum_offset_ppq > 0 then
                                e_ppq = math.max(s_ppq + 40, e_ppq)
                            end
                            reaper.MIDI_InsertNote(take, false, false, s_ppq, e_ppq, n.chan, n.pitch, n.vel, false)
                        end
                        if n.arpeggio then
                            reaper.MIDI_InsertTextSysexEvt(take, false, false, s_ppq, 15, string.format("NOTE %d %d a arpeggio", n.pitch, n.chan))
                            if not n.strum_offset_ppq or n.strum_offset_ppq == 0 then
                                reaper.MIDI_InsertTextSysexEvt(take, false, false, base_s_ppq, 15, "NOTATOR_ARPEGGIO " .. n.arpeggio)
                            end
                        elseif n.articulation and n.articulation ~= "" then
                            reaper.MIDI_InsertTextSysexEvt(take, false, false, s_ppq, 15, string.format("NOTE %d %d a %s", n.pitch, n.chan, n.articulation))
                            local track_bank = target_banks[pi]
                            if track_bank then
                                local art_match = MidiService.find_reaticulate_art_for_id(track_bank, n.articulation)
                                if not art_match and (n.articulation == "staccatissimo" or n.articulation:find("staccatiss")) then
                                    art_match = MidiService.find_reaticulate_art_for_id(track_bank, "staccato")
                                end
                                if art_match then
                                    local eff_msb = (track_bank.msb and track_bank.msb >= 0) and track_bank.msb or -1
                                    local eff_lsb = (track_bank.lsb and track_bank.lsb >= 0) and track_bank.lsb or -1
                                    if eff_msb >= 0 then
                                        reaper.MIDI_InsertCC(take, false, false, s_ppq, 0xB0, n.chan, 0, eff_msb)
                                    end
                                    if eff_lsb >= 0 then
                                        reaper.MIDI_InsertCC(take, false, false, s_ppq, 0xB0, n.chan, 32, eff_lsb)
                                    end
                                    reaper.MIDI_InsertCC(take, false, false, s_ppq, 0xC0, n.chan, art_match.pc, 0)
                                end
                            end
                        end
                        if n.accidental ~= nil then
                            local pos_k = string.format("%s_%.3f_%d", tostring(take), n.start_qn, n.pitch)
                            local full_k = string.format("%s_%s_%.3f_%d_%d", tostring(item), tostring(take), n.start_qn, n.pitch, n.chan or 0)
                            state.note_accidentals[pos_k] = n.accidental
                            state.note_accidentals[full_k] = n.accidental
                        end
                    end

                    -- Insert Type 15 Tie tags and store in state.user_ties
                    for _, t in ipairs(part_ties) do
                        local n1_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, t.n1.start_qn) + 0.5)
                        local n2_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, t.n2.start_qn) + 0.5)
                        reaper.MIDI_InsertTextSysexEvt(take, false, false, n1_sppq, 15, string.format("NOTATOR_TIE %s %d %d %.4f %.4f %.4f %.4f %d",
                            t.id, t.chan or 0, t.pitch, t.n1.start_qn, t.n1.dur_qn, t.n2.start_qn, t.n2.dur_qn, t.n2.vel or 90))
                        reaper.MIDI_InsertTextSysexEvt(take, false, false, n2_sppq, 15, string.format("NOTATOR_TIE_SLAVE %s %d %d %.4f %.4f",
                            t.id, t.chan or 0, t.pitch, t.n2.start_qn, t.n2.dur_qn))

                        local tie_obj = {
                            id = t.id,
                            track_guid = trk_guid,
                            chan = t.chan or 0,
                            pitch = t.pitch,
                            n1_start_qn = t.n1.start_qn,
                            n1_dur = t.n1.dur_qn,
                            n2_start_qn = t.n2.start_qn,
                            n2_dur = t.n2.dur_qn,
                            n2_vel = t.n2.vel or 90,
                            n1_key = string.format("%d_%.4f_%d", t.pitch, t.n1.start_qn, t.chan or 0),
                            n2_key = string.format("%d_%.4f_%d", t.pitch, t.n2.start_qn, t.chan or 0)
                        }
                        if not state.user_ties then state.user_ties = {} end
                        table.insert(state.user_ties, tie_obj)
                    end

                    -- Insert Type 15 Slur tags, legato keyswitches and store in state.user_slurs
                    for _, sl in ipairs(part_slurs) do
                        local n1 = sl.n1
                        local n_last = sl.n2
                        local slur_id = sl.id
                        local n1_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, n1.start_qn) + 0.5)
                        local s_chan = n1.chan or sl.chan or 0

                        -- Collect all chronological phrase notes strictly within this slur phrase and channel
                        local phrase_notes = {}
                        for _, pn in ipairs(track_notes) do
                            if (pn.chan == s_chan) and (pn.start_qn >= n1.start_qn - 0.005) and (pn.start_qn <= n_last.start_qn + 0.005) then
                                table.insert(phrase_notes, pn)
                            end
                        end
                        table.sort(phrase_notes, function(a, b)
                            if math.abs(a.start_qn - b.start_qn) > 0.001 then
                                return a.start_qn < b.start_qn
                            end
                            return a.pitch < b.pitch
                        end)

                        if #phrase_notes < 2 then
                            phrase_notes = { n1, n_last }
                        end

                        -- True Acoustic Legato Playback in REAPER:
                        -- Extend intermediate notes to touch the next note (+2 micro-legato overlap ticks)
                        -- so samplers like Kontakt, Spitfire, Cinematic Studio Strings, Orchestral Tools, VSL trigger legato interval transitions!
                        local find_fn = (SlurService and SlurService.find_take_note_by_pos)
                        for i = 1, #phrase_notes - 1 do
                            local curr = phrase_notes[i]
                            local next_n = phrase_notes[i + 1]
                            if (next_n.start_qn - curr.start_qn) > 0.005 then
                                local next_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, next_n.start_qn) + 0.5)
                                local curr_idx, curr_data = nil, nil
                                if find_fn then
                                    curr_idx, curr_data = find_fn(take, curr.pitch, curr.chan or s_chan, curr.start_qn)
                                else
                                    local target_ppq = reaper.MIDI_GetPPQPosFromProjQN(take, curr.start_qn)
                                    local _, notecnt = reaper.MIDI_CountEvts(take)
                                    for ni = 0, notecnt - 1 do
                                        local ok, sel, muted, sppq, eppq, ch, p, vel = reaper.MIDI_GetNote(take, ni)
                                        if ok and p == curr.pitch and ch == (curr.chan or s_chan) and math.abs(sppq - target_ppq) <= 40 then
                                            curr_idx = ni
                                            curr_data = { sel = sel, muted = muted, sppq = sppq, eppq = eppq, chan = ch, pitch = p, vel = vel }
                                            break
                                        end
                                    end
                                end
                                if curr_idx and curr_data then
                                    local leg_end_ppq
                                    if curr.pitch == next_n.pitch then
                                        -- Same pitch: never overlap to avoid REAPER note merging
                                        leg_end_ppq = math.min(curr_data.eppq, math.max(curr_data.sppq + 20, next_sppq - 1))
                                    else
                                        -- Different pitch: apply +2 tick micro-legato overlap for sampler interval triggering!
                                        leg_end_ppq = math.max(curr_data.sppq + 20, next_sppq + 2)
                                    end
                                    reaper.MIDI_SetNote(take, curr_idx, curr_data.sel, curr_data.muted, curr_data.sppq, leg_end_ppq, curr_data.chan, curr_data.pitch, curr_data.vel, false)
                                end
                            end
                        end

                        -- Tag all notes in phrase with NOTE <pitch> <chan> a legato and purge conflicting staccato tags
                        for _, pn in ipairs(phrase_notes) do
                            local pn_sppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, pn.start_qn) + 0.5)
                            local _, _, _, textcnt = reaper.MIDI_CountEvts(take)
                            for ti = (textcnt or 0) - 1, 0, -1 do
                                local ok_t, _, _, t_ppq, etype, msg_t = reaper.MIDI_GetTextSysexEvt(take, ti)
                                if ok_t and etype == 15 and math.abs(t_ppq - pn_sppq) <= 25 then
                                    local low_msg = msg_t:lower()
                                    if low_msg:find("stacc") or low_msg:find("spicc") or low_msg:find("wedge") then
                                        reaper.MIDI_DeleteTextSysexEvt(take, ti)
                                    end
                                end
                            end
                            reaper.MIDI_InsertTextSysexEvt(take, false, false, pn_sppq, 15, string.format("NOTE %d %d a legato", pn.pitch, pn.chan or s_chan))
                            pn.articulation = "legato"
                        end

                        -- Insert 10-token NOTATOR_SLUR tag matching SlurService persistence format
                        reaper.MIDI_InsertTextSysexEvt(take, false, false, n1_sppq, 15, string.format("NOTATOR_SLUR %s %d %d %d %.4f %.4f %.4f %s %s %s",
                            slur_id, s_chan, n1.pitch, n_last.pitch, n1.start_qn, n_last.start_qn, n1.dur_qn, "", -1, -1))

                        local track_bank = target_banks[pi]
                        if not track_bank and tr and ReaticulateParser then
                            local all_banks = ReaticulateParser.get_all_banks()
                            track_bank = ReaticulateParser.get_bank_for_track(tr, all_banks)
                        end
                        if track_bank then
                            local art_match = MidiService.find_reaticulate_art_for_id(track_bank, "legato")
                                or MidiService.find_reaticulate_art_for_id(track_bank, "long")
                                or MidiService.find_reaticulate_art_for_id(track_bank, "sustain")
                            if art_match then
                                local eff_msb = (track_bank.msb and track_bank.msb >= 0) and track_bank.msb or -1
                                local eff_lsb = (track_bank.lsb and track_bank.lsb >= 0) and track_bank.lsb or -1
                                if eff_msb >= 0 then reaper.MIDI_InsertCC(take, false, false, n1_sppq, 0xB0, s_chan, 0, eff_msb) end
                                if eff_lsb >= 0 then reaper.MIDI_InsertCC(take, false, false, n1_sppq, 0xB0, s_chan, 32, eff_lsb) end
                                reaper.MIDI_InsertCC(take, false, false, n1_sppq, 0xC0, s_chan, art_match.pc, 0)
                            end
                        end

                        local slur_obj = {
                            id = slur_id,
                            track_guid = trk_guid,
                            chan = s_chan,
                            n1_chan = n1.chan or s_chan,
                            n2_chan = n_last.chan or s_chan,
                            pitch1 = n1.pitch,
                            pitch2 = n_last.pitch,
                            start_qn = n1.start_qn,
                            n2_start_qn = n_last.start_qn,
                            end_qn = n_last.start_qn + n_last.dur_qn,
                            orig_dur1 = n1.dur_qn,
                            pre_slur_pc = nil,
                            pre_slur_msb = -1,
                            pre_slur_lsb = -1,
                            n1_key = string.format("%d_%.4f_%d", n1.pitch, n1.start_qn, n1.chan or s_chan),
                            n2_key = string.format("%d_%.4f_%d", n_last.pitch, n_last.start_qn, n_last.chan or s_chan)
                        }
                        if not state.user_slurs then state.user_slurs = {} end
                        table.insert(state.user_slurs, slur_obj)
                    end

                    -- Insert Glissando marks and generate chromatic ladder steps in take
                    for _, gl in ipairs(part_glissandi) do
                        local n1 = gl.n1
                        local n2 = gl.n2
                        local is_cross = (n1.pitch < 60 and n2.pitch >= 60) or (n1.pitch >= 60 and n2.pitch < 60)
                        local gm = GlissandoMark.new({
                            id = gl.id,
                            track_guid = trk_guid,
                            chan = gl.chan or 0,
                            pitch1 = n1.pitch,
                            start_qn1 = n1.start_qn,
                            orig_dur1 = n1.dur_qn,
                            dur_qn1 = n1.dur_qn,
                            pitch2 = n2.pitch,
                            start_qn2 = n2.start_qn,
                            dur_qn2 = n2.dur_qn,
                            start_pct1 = 50,
                            show_text = true,
                            cross_staff = is_cross,
                            vel_mode = "interpolate",
                            wave_style = "sine"
                        })
                        if not state.glissando_marks then state.glissando_marks = {} end
                        table.insert(state.glissando_marks, gm)

                        GlissandoService.resync_glissando_in_take(state, gm, nil)
                    end

                    -- Insert Portamento marks and generate CC hold automation in take
                    for _, sl in ipairs(part_slides) do
                        local n1 = sl.n1
                        local n2 = sl.n2
                        local pm = PortamentoMark.new({
                            id = sl.id,
                            track_guid = trk_guid,
                            chan = sl.chan or 0,
                            pitch1 = n1.pitch,
                            start_qn1 = n1.start_qn,
                            dur_qn1 = n1.dur_qn,
                            pitch2 = n2.pitch,
                            start_qn2 = n2.start_qn,
                            dur_qn2 = n2.dur_qn,
                            mode = "cc64",
                            show_text = true,
                            start_pct1 = 50,
                            end_pct2 = 50,
                            n1_key = string.format("%d_%.4f_%d", n1.pitch, n1.start_qn, sl.chan or 0),
                            n2_key = string.format("%d_%.4f_%d", n2.pitch, n2.start_qn, sl.chan or 0)
                        })
                        pm:recalculate_timing()
                        if not state.portamento_marks then state.portamento_marks = {} end
                        table.insert(state.portamento_marks, pm)

                        PortamentoService.apply_cc(state, pm, nil)
                    end
                    for _, d in ipairs(track_dynamics) do
                        local d_ppq = math.floor(reaper.MIDI_GetPPQPosFromProjQN(take, d.qn) + 0.5)
                        local lk = DYN_LOOKUP[d.label:lower()] or { c1 = 80, c2 = 85 }
                        reaper.MIDI_InsertTextSysexEvt(take, false, false, d_ppq, 15, string.format("dynamic %s :%d:%d", d.label, lk.c1, lk.c2))
                    end

                    local track_bank = target_banks[pi]
                    if not track_bank and tr and ReaticulateParser then
                        local all_banks = ReaticulateParser.get_all_banks()
                        track_bank = ReaticulateParser.get_bank_for_track(tr, all_banks)
                    end
                    if track_bank then
                        MidiService.auto_chase_momentary_articulations(take, track_bank)
                    end
                    reaper.MIDI_Sort(take)

                    -- Persist clef on item and track
                    local part_clef = (state and state.track_clefs and trk_guid and state.track_clefs[trk_guid]) or "auto"
                    if part_clef and part_clef ~= "auto" then
                        reaper.GetSetMediaItemInfo_String(item, "P_EXT:notator_clef", part_clef, true)
                        if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
                            reaper.GetSetMediaTrackInfo_String(tr, "P_EXT:notator_clef", part_clef, true)
                        end
                    end

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

                    -- Save default item modulators (ensuring bow swelling is 0.0 and bow position 0.50)
                    local DynamicsEngine = package.loaded["services.dynamics_engine"] or require("services.dynamics_engine")
                    if DynamicsEngine and DynamicsEngine.save_item_modulators then
                        DynamicsEngine.save_item_modulators(item, state)
                    end

                    -- Apply Key Signature and Time Signature to item and take
                    local init_key = item_key_sigs[1] or item_key_sigs_list[1] or score_initial_key_sig
                    if do_import_keys and init_key then
                        KeySignatureService.set_item_key_sig(state, item, take, init_key.idx, init_key.mode, false)
                        if state then
                            if state.key_signature == nil or state.key_signature == 0 then
                                state.key_signature = init_key.idx
                                state.key_signature_mode = init_key.mode or "major"
                            end
                            state.show_key_signatures = true
                            state.selected_key_sig = init_key.idx
                            state.selected_key_mode = init_key.mode or "major"
                            if trk_guid and trk_guid ~= "" then
                                if not state.track_key_signatures then state.track_key_signatures = {} end
                                state.track_key_signatures[trk_guid] = { idx = init_key.idx, key_idx = init_key.idx, mode = init_key.mode or "major" }
                            end
                        end
                    end

                    -- Insert mid-piece key signature changes
                    if do_import_keys and #item_key_sigs_list > 0 then
                        for _, ks in ipairs(item_key_sigs_list) do
                            if ks.start_qn and ks.start_qn > 0.001 then
                                KeySignatureService.set_item_key_sig(state, item, take, ks.idx, ks.mode or "major", false, ks.start_qn)
                            end
                        end
                    end

                    local init_time = item_time_sigs[1] or item_time_sigs_list[1] or score_initial_time_sig
                    if do_import_keys and init_time then
                        KeySignatureService.set_item_time_sig(state, item, take, init_time.num, init_time.denom)
                        if state then
                            if state.time_sig_num == nil or state.time_sig_num == 4 then
                                state.time_sig_num = init_time.num
                                state.time_sig_denom = init_time.denom
                            end
                        end
                    end

                    -- Insert mid-piece time signature changes
                    if do_import_keys and #item_time_sigs_list > 0 then
                        for _, ts in ipairs(item_time_sigs_list) do
                            if ts.start_qn and ts.start_qn > 0.001 then
                                KeySignatureService.set_item_time_sig(state, item, take, ts.num, ts.denom, ts.start_qn)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Synchronize score-wide key and time signatures into state and REAPER
    if do_import_keys then
        if score_initial_key_sig and state then
            state.key_signature = score_initial_key_sig.idx
            state.key_signature_mode = score_initial_key_sig.mode or "major"
            state.show_key_signatures = true
            state.selected_key_sig = score_initial_key_sig.idx
            state.selected_key_mode = score_initial_key_sig.mode or "major"
        end

        if score_initial_time_sig then
            if state then
                state.time_sig_num = score_initial_time_sig.num
                state.time_sig_denom = score_initial_time_sig.denom
            end
            local cur_bpm = reaper.Master_GetTempo() or 120.0
            for _, itm in ipairs(imported_tempo_markers) do
                if itm.qn and itm.qn < 0.001 and itm.bpm then
                    cur_bpm = itm.bpm
                    break
                end
            end
            reaper.SetTempoTimeSigMarker(0, -1, 0.0, -1, -1, cur_bpm, score_initial_time_sig.num, score_initial_time_sig.denom, false)
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

    -- Fermatas
    if #imported_fermatas > 0 and state then
        local Fermata = package.loaded["classes.fermata"] or require("classes.fermata")
        local FermataService = package.loaded["services.fermata_service"] or require("services.fermata_service")
        if not state.fermatas then state.fermatas = {} end
        for _, iferm in ipairs(imported_fermatas) do
            local bpi = 4.0
            local ts_num, ts_den = reaper.TimeMap_GetTimeSigAtTime(0, reaper.TimeMap2_QNToTime(0, iferm.qn))
            if ts_num and ts_den and ts_den > 0 then bpi = ts_num * (4.0 / ts_den) end
            local m = math.floor((iferm.qn + 0.01) / bpi)
            local beat = iferm.qn - (m * bpi)

            local ferm = Fermata.new({
                id            = string.format("ferm_%d_%d", math.floor(iferm.qn * 100), math.random(1000, 9999)),
                qn            = iferm.qn,
                measure       = m,
                beat_rel      = beat,
                type          = iferm.type or "standard",
                hold_factor   = iferm.hold_factor or 1.5,
                playback_mode = "tempo_dip"
            })
            table.insert(state.fermatas, ferm)
        end
        table.sort(state.fermatas, function(a, b) return a.qn < b.qn end)
        if FermataService then
            FermataService.save_fermatas(state)
            for _, f in ipairs(state.fermatas) do
                FermataService.sync_takes_for_fermata(f, nil, false)
            end
        end
        local TempoService = package.loaded["services.tempo_service"] or require("services.tempo_service")
        if TempoService and TempoService.sync_to_reaper then
            TempoService.sync_to_reaper(state)
        end
    end

    -- Rehearsal Marks & Navigation
    if #imported_rehearsal_marks > 0 and state then
        local RehearsalMark = package.loaded["classes.rehearsal_mark"] or require("classes.rehearsal_mark")
        local RehearsalMarkService = package.loaded["services.rehearsal_mark_service"] or require("services.rehearsal_mark_service")
        if not state.rehearsal_marks then state.rehearsal_marks = {} end
        for _, irm in ipairs(imported_rehearsal_marks) do
            local rm = RehearsalMark.new({
                id          = string.format("rm_%d_%d", math.floor(irm.qn * 100), math.random(1000, 9999)),
                measure     = irm.measure or 0,
                qn          = irm.qn,
                type        = irm.type or "letter",
                custom_text = irm.custom_text or "",
                label       = irm.label or ""
            })
            table.insert(state.rehearsal_marks, rm)
        end
        if RehearsalMarkService then
            RehearsalMarkService.recompute_labels(state)
            RehearsalMarkService.sync_takes(state)
            RehearsalMarkService.save_marks(state)
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
        if SlurService and SlurService.save_slurs then
            SlurService.save_slurs(state)
        end
        if GlissandoService and GlissandoService.save_glissandos then
            GlissandoService.save_glissandos(state)
        end
        if PortamentoService and PortamentoService.save_portamentos then
            PortamentoService.save_portamentos(state)
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

    -- Automatically select all newly imported tracks in state and focus first track
    if state and target_tracks and #target_tracks > 0 then
        state.selected_tracks = {}
        for _, t in ipairs(target_tracks) do
            if t and reaper.ValidatePtr(t, "MediaTrack*") then
                local guid = reaper.GetTrackGUID(t)
                state.selected_tracks[guid] = true
            end
        end
        if target_tracks[1] and reaper.ValidatePtr(target_tracks[1], "MediaTrack*") then
            state.focused_track = target_tracks[1]
            if reaper.SetOnlyTrackSelected then
                reaper.SetOnlyTrackSelected(target_tracks[1])
            end
        end
    end

    -- Flush caches & mark project dirty
    MidiService.invalidate_cache()
    if state then state.active_tracks_cache = nil end
    reaper.MarkProjectDirty(0)
    if reaper.TrackList_AdjustWindows then reaper.TrackList_AdjustWindows(false) end
    if reaper.UpdateArrange then reaper.UpdateArrange() end

    local success_msg = string.format("Imported %d tracks, %d notes, %d measures from MusicXML.", #parts, total_notes_imported, total_measures_imported)
    if state then state.status_msg = success_msg end

    return true, success_msg, total_notes_imported, #parts, reaticulate_installed
end

return MusicXmlImportService

-- ==============================================================================
-- REAPER Native Notator - Service: PrintSettingsService
-- Manages score print settings, layout metadata, and XML persistence
-- directly alongside the REAPER project file (<Project>_print.xml).
-- ==============================================================================

local PathService = require("services.path_service")

local PrintSettingsService = {}

-- ------------------------------------------------------------------------------
-- Escape and Unescape XML helper functions
-- ------------------------------------------------------------------------------
local function xml_escape(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("&", "&amp;")
    str = str:gsub("<", "&lt;")
    str = str:gsub(">", "&gt;")
    str = str:gsub("\"", "&quot;")
    str = str:gsub("'", "&apos;")
    return str
end

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
-- Locate the XML file path alongside the REAPER project
-- ------------------------------------------------------------------------------
function PrintSettingsService.get_project_xml_path()
    local _, proj_fn = reaper.EnumProjects(-1, "")
    if proj_fn and proj_fn ~= "" then
        -- Normalize slashes
        local norm = proj_fn:gsub("\\", "/")
        local base = norm:gsub("%.rpp$", ""):gsub("%.RPP$", "")
        return base .. "_print.xml", true
    end

    -- Fallback for unsaved / untitled projects
    local s_dir = PathService.get_script_dir()
    return s_dir .. "/untitled_score_print.xml", false
end

-- ------------------------------------------------------------------------------
-- Locate default PDF output path alongside the REAPER project
-- ------------------------------------------------------------------------------
function PrintSettingsService.get_default_pdf_path()
    local _, proj_fn = reaper.EnumProjects(-1, "")
    if proj_fn and proj_fn ~= "" then
        local norm = proj_fn:gsub("\\", "/")
        local base = norm:gsub("%.rpp$", ""):gsub("%.RPP$", "")
        return base .. "_Score.pdf", true
    end

    local s_dir = PathService.get_script_dir()
    return s_dir .. "/Score.pdf", false
end

-- ------------------------------------------------------------------------------
-- Default Print & Score Settings
-- ------------------------------------------------------------------------------
function PrintSettingsService.get_default_settings()
    local _, proj_fn = reaper.EnumProjects(-1, "")
    local default_title = "Full Orchestral Score"
    if proj_fn and proj_fn ~= "" then
        local norm = proj_fn:gsub("\\", "/")
        local fname = norm:match("([^/]+)%.rpp$") or norm:match("([^/]+)%.RPP$")
        if fname and fname ~= "" then
            default_title = fname
        end
    end

    local cur_year = os.date("%Y") or "2026"

    return {
        -- Metadata
        title              = default_title,
        subtitle           = "Full Score for Orchestra",
        composer           = "Composer",
        arranger           = "",
        date               = cur_year,
        copyright          = string.format("© %s All Rights Reserved", cur_year),
        style_template     = "classical", -- "classical" | "film" | "baroque"
        
        -- Orchestrator Notes (Page 2)
        orchestrator_notes = "Score in C (Concert Pitch).\nAll instruments sound as written except standard octave transpositions:\n- Piccolo sounds 8va higher\n- Contrabass and Contrabassoon sound 8vb lower\n\nPerformance Instructions:\n- Strings: Molto espressivo e legato unless marked otherwise.\n- Brass: Observe dynamic balance in tutti sections.\n- Woodwinds: Adhere strictly to phrase and breath marks.",
        
        -- Layout & Pagination
        bars_per_page      = 5,             -- Standard: 5 Bars per page
        paper_size         = "A4",          -- "A4" | "A3" | "Letter"
        orientation        = "landscape",   -- "landscape" (standard orchestral score) | "portrait"
        two_page_spread    = true,          -- Two-page book spread preview
        include_cover      = true,          -- Page 1: Title Page
        include_notes_page = true,          -- Page 2: Orchestration & Notes Page
        show_measure_nums  = true,          -- Bar numbers above staves
        show_track_names   = true,          -- Left system track names
        show_chords        = true,          -- Show chord lane on score
        target_tracks      = {}             -- Map: track_guid -> boolean (if empty, all active tracks)
    }
end

-- ------------------------------------------------------------------------------
-- XML Serializer (Pure Lua, no external libraries)
-- ------------------------------------------------------------------------------
function PrintSettingsService.encode_xml(settings)
    local s = settings or PrintSettingsService.get_default_settings()
    local parts = {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
        "<ScorePrintSettings version=\"1.0\">",
        "    <Metadata>",
        string.format("        <Title>%s</Title>", xml_escape(s.title)),
        string.format("        <Subtitle>%s</Subtitle>", xml_escape(s.subtitle)),
        string.format("        <Composer>%s</Composer>", xml_escape(s.composer)),
        string.format("        <Arranger>%s</Arranger>", xml_escape(s.arranger)),
        string.format("        <Date>%s</Date>", xml_escape(s.date)),
        string.format("        <Copyright>%s</Copyright>", xml_escape(s.copyright)),
        string.format("        <StyleTemplate>%s</StyleTemplate>", xml_escape(s.style_template)),
        "    </Metadata>",
        "    <OrchestratorNotes><![CDATA[" .. (s.orchestrator_notes or "") .. "]]></OrchestratorNotes>",
        "    <Layout>",
        string.format("        <BarsPerPage>%d</BarsPerPage>", tonumber(s.bars_per_page) or 5),
        string.format("        <PaperSize>%s</PaperSize>", xml_escape(s.paper_size or "A4")),
        string.format("        <Orientation>%s</Orientation>", xml_escape(s.orientation or "landscape")),
        string.format("        <TwoPageSpread>%s</TwoPageSpread>", s.two_page_spread and "true" or "false"),
        string.format("        <IncludeCover>%s</IncludeCover>", s.include_cover and "true" or "false"),
        string.format("        <IncludeNotesPage>%s</IncludeNotesPage>", s.include_notes_page and "true" or "false"),
        string.format("        <ShowMeasureNumbers>%s</ShowMeasureNumbers>", s.show_measure_nums and "true" or "false"),
        string.format("        <ShowTrackNames>%s</ShowTrackNames>", s.show_track_names and "true" or "false"),
        string.format("        <ShowChords>%s</ShowChords>", s.show_chords and "true" or "false"),
        "    </Layout>",
        "    <TargetTracks>"
    }

    if s.target_tracks and type(s.target_tracks) == "table" then
        for guid, val in pairs(s.target_tracks) do
            if val then
                table.insert(parts, string.format("        <Track guid=\"%s\" enabled=\"true\"/>", xml_escape(guid)))
            end
        end
    end

    table.insert(parts, "    </TargetTracks>")
    table.insert(parts, "</ScorePrintSettings>")
    table.insert(parts, "")

    return table.concat(parts, "\n")
end

-- ------------------------------------------------------------------------------
-- XML Parser (Robust regex tag matching)
-- ------------------------------------------------------------------------------
function PrintSettingsService.decode_xml(xml_content)
    if not xml_content or xml_content == "" then return nil end
    local s = PrintSettingsService.get_default_settings()

    local function get_tag(tag, src)
        local pat = "<" .. tag .. ">(.-)</" .. tag .. ">"
        local val = src:match(pat)
        return val and xml_unescape(val) or nil
    end

    local meta_block = xml_content:match("<Metadata>(.-)</Metadata>")
    if meta_block then
        s.title          = get_tag("Title", meta_block) or s.title
        s.subtitle       = get_tag("Subtitle", meta_block) or s.subtitle
        s.composer       = get_tag("Composer", meta_block) or s.composer
        s.arranger       = get_tag("Arranger", meta_block) or s.arranger
        s.date           = get_tag("Date", meta_block) or s.date
        s.copyright      = get_tag("Copyright", meta_block) or s.copyright
        s.style_template = get_tag("StyleTemplate", meta_block) or s.style_template
    end

    -- CDATA or standard tag for OrchestratorNotes
    local cdata_notes = xml_content:match("<OrchestratorNotes><!%[CDATA%[(.-)%]%]></OrchestratorNotes>")
    if cdata_notes then
        s.orchestrator_notes = cdata_notes
    else
        local regular_notes = get_tag("OrchestratorNotes", xml_content)
        if regular_notes then
            s.orchestrator_notes = regular_notes
        end
    end

    local layout_block = xml_content:match("<Layout>(.-)</Layout>")
    if layout_block then
        local bpp = tonumber(get_tag("BarsPerPage", layout_block))
        if bpp and bpp >= 1 and bpp <= 32 then s.bars_per_page = bpp end

        s.paper_size         = get_tag("PaperSize", layout_block) or s.paper_size
        s.orientation        = get_tag("Orientation", layout_block) or s.orientation
        
        local tps = get_tag("TwoPageSpread", layout_block)
        if tps ~= nil then s.two_page_spread = (tps == "true") end
        
        local inc_cov = get_tag("IncludeCover", layout_block)
        if inc_cov ~= nil then s.include_cover = (inc_cov == "true") end
        
        local inc_not = get_tag("IncludeNotesPage", layout_block)
        if inc_not ~= nil then s.include_notes_page = (inc_not == "true") end
        
        local smn = get_tag("ShowMeasureNumbers", layout_block)
        if smn ~= nil then s.show_measure_nums = (smn == "true") end
        
        local stn = get_tag("ShowTrackNames", layout_block)
        if stn ~= nil then s.show_track_names = (stn == "true") end
        
        local sc = get_tag("ShowChords", layout_block)
        if sc ~= nil then s.show_chords = (sc == "true") end
    end

    local trk_block = xml_content:match("<TargetTracks>(.-)</TargetTracks>")
    if trk_block then
        s.target_tracks = {}
        for guid in trk_block:gmatch("<Track guid=\"([^\"]+)\"") do
            s.target_tracks[xml_unescape(guid)] = true
        end
    end

    return s
end

-- ------------------------------------------------------------------------------
-- Save settings to the XML file next to the project file
-- ------------------------------------------------------------------------------
function PrintSettingsService.save_settings(state, custom_path)
    local path = custom_path or PrintSettingsService.get_project_xml_path()
    local settings = state.print_settings or PrintSettingsService.get_default_settings()

    local xml_text = PrintSettingsService.encode_xml(settings)
    local f, err = io.open(path, "w")
    if not f then
        state.status_msg = "Error writing print XML: " .. tostring(err)
        return false, err
    end

    f:write(xml_text)
    f:close()

    if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
    state.status_msg = string.format("Print settings saved to XML (%s)", path:match("([^/\\]+)$") or "file")
    return true, path
end

-- ------------------------------------------------------------------------------
-- Load settings from the XML file next to the project file
-- ------------------------------------------------------------------------------
function PrintSettingsService.load_settings(state)
    local path, has_proj = PrintSettingsService.get_project_xml_path()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local decoded = PrintSettingsService.decode_xml(content)
        if decoded then
            state.print_settings = decoded
            return true, path
        end
    end

    -- If no XML exists yet, initialize defaults
    state.print_settings = PrintSettingsService.get_default_settings()
    return false, path
end

return PrintSettingsService

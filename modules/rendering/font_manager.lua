-- ==============================================================================
-- REAPER Native Notator - Module: FontManager
-- Loads fonts (Segoe UI & Bravura SMuFL) and manages glyph output
-- Supports both ReaImGui >= 0.10 (dynamic 2-arg ImGui_CreateFont / ImGui_CreateFontFromFile)
-- and legacy ReaImGui < 0.10 (3-arg ImGui_CreateFont / ImGui_CreateFontFromFile
-- requiring explicit size_px > 0 as 2nd parameter).
-- ==============================================================================

local PathService = require("services.path_service")

local FontManager = {
    font_main = nil,
    font_big = nil,
    font_bold = nil,
    font_italic = nil,
    font_bold_italic = nil,
    font_music = nil,
    _fonts_ready = false,
    _is_legacy_font_api = false,
}

local DEFAULT_UI_FONT_SIZE_PX = 16
local DEFAULT_MUSIC_FONT_SIZE_PX = 36

local function detect_legacy_font_api()
    -- ReaImGui 0.10+ uses Dear ImGui 1.92+ (imgui_num >= 19200) and semver >= 0.10.0,
    -- where ImGui_CreateFont(family, [flags]) and ImGui_CreateFontFromFile(file, [flags]) take 2 args.
    -- ReaImGui < 0.10 (0.8.x / 0.9.x) uses imgui_num < 19200 and semver 0.8.x / 0.9.x,
    -- where ImGui_CreateFont(family, size_px, [flags]) and ImGui_CreateFontFromFile(file, size_px, [flags])
    -- require size_px > 0 as their 2nd argument (passing flags=0 as 2nd arg causes
    -- "ImGui assertion failed: font_cfg->SizePixels > 0.0f" on the first frame!).
    if reaper.APIExists("ImGui_GetVersion") then
        local ok_v, _, imgui_num, reaimgui_ver = pcall(reaper.ImGui_GetVersion)
        if ok_v then
            if type(reaimgui_ver) == "string" then
                local maj, min = reaimgui_ver:match("^(%d+)%.(%d+)")
                if maj and min then
                    local mj = tonumber(maj) or 0
                    local mn = tonumber(min) or 0
                    return (mj == 0 and mn < 10)
                end
            end
            if type(imgui_num) == "number" and imgui_num > 0 then
                return (imgui_num < 19200)
            end
        end
    end
    return false
end

local function is_valid_font_handle(f)
    if not f then return false end
    if reaper.APIExists("ImGui_ValidatePtr") then
        return reaper.ImGui_ValidatePtr(f, "ImGui_Font*")
    end
    return true
end

local function create_ui_font_compat(family, size_px, flags, is_legacy)
    if not reaper.APIExists("ImGui_CreateFont") then return nil end
    local safe_sz = math.max(8, math.floor(tonumber(size_px) or DEFAULT_UI_FONT_SIZE_PX))
    local safe_flags = tonumber(flags) or 0

    if is_legacy then
        -- ReaImGui < 0.10 signature: ImGui_CreateFont(family, size_px, [flags])
        -- NEVER pass flags (0) as 2nd arg here, or font_cfg->SizePixels becomes 0.0f!
        local ok, res = pcall(reaper.ImGui_CreateFont, family, safe_sz, safe_flags)
        if ok and is_valid_font_handle(res) then return res end
        ok, res = pcall(reaper.ImGui_CreateFont, family, safe_sz)
        if ok and is_valid_font_handle(res) then return res end
        return nil
    else
        -- ReaImGui >= 0.10 signature: ImGui_CreateFont(family_or_file, [flags])
        local ok, res = pcall(reaper.ImGui_CreateFont, family, safe_flags)
        if ok and is_valid_font_handle(res) then return res end
        ok, res = pcall(reaper.ImGui_CreateFont, family)
        if ok and is_valid_font_handle(res) then return res end
        return nil
    end
end

local function create_file_font_compat(path, size_px, flags, is_legacy)
    local safe_sz = math.max(12, math.floor(tonumber(size_px) or DEFAULT_MUSIC_FONT_SIZE_PX))
    local safe_flags = tonumber(flags) or 0

    if is_legacy then
        -- ReaImGui < 0.10 signature: ImGui_CreateFontFromFile(file, size_px, [flags])
        -- NEVER pass flags (0) as 2nd arg here, or font_cfg->SizePixels becomes 0.0f!
        if reaper.APIExists("ImGui_CreateFontFromFile") then
            local ok, mf = pcall(reaper.ImGui_CreateFontFromFile, path, safe_sz, safe_flags)
            if ok and is_valid_font_handle(mf) then return mf end
            ok, mf = pcall(reaper.ImGui_CreateFontFromFile, path, safe_sz)
            if ok and is_valid_font_handle(mf) then return mf end
        end
        if reaper.APIExists("ImGui_CreateFont") then
            local ok, mf = pcall(reaper.ImGui_CreateFont, path, safe_sz, safe_flags)
            if ok and is_valid_font_handle(mf) then return mf end
            ok, mf = pcall(reaper.ImGui_CreateFont, path, safe_sz)
            if ok and is_valid_font_handle(mf) then return mf end
        end
        return nil
    else
        -- ReaImGui >= 0.10 signature: ImGui_CreateFontFromFile(file, [flags]) / ImGui_CreateFont(file, [flags])
        if reaper.APIExists("ImGui_CreateFontFromFile") then
            local ok, mf = pcall(reaper.ImGui_CreateFontFromFile, path, safe_flags)
            if ok and is_valid_font_handle(mf) then return mf end
            ok, mf = pcall(reaper.ImGui_CreateFontFromFile, path)
            if ok and is_valid_font_handle(mf) then return mf end
        end
        if reaper.APIExists("ImGui_CreateFont") then
            local ok, mf = pcall(reaper.ImGui_CreateFont, path, safe_flags)
            if ok and is_valid_font_handle(mf) then return mf end
            ok, mf = pcall(reaper.ImGui_CreateFont, path)
            if ok and is_valid_font_handle(mf) then return mf end
        end
        return nil
    end
end

function FontManager.init(ctx, state)
    local os_type = PathService.get_os()
    local is_legacy = detect_legacy_font_api()
    FontManager._is_legacy_font_api = is_legacy
    
    local flag_none = reaper.APIExists("ImGui_FontFlags_None") and reaper.ImGui_FontFlags_None() or 0
    local flag_bold = reaper.APIExists("ImGui_FontFlags_Bold") and reaper.ImGui_FontFlags_Bold() or 1
    local flag_italic = reaper.APIExists("ImGui_FontFlags_Italic") and reaper.ImGui_FontFlags_Italic() or 2
    local flag_bold_italic = flag_bold | flag_italic

    local function load_styled_ui_font(flags, mac_family)
        -- Strategy 1: Load via font family name + style flags (DirectWrite / FreeType with full Unicode fallback)
        local primary_family = (os_type == "macos" and mac_family) or "Segoe UI"
        local f = create_ui_font_compat(primary_family, DEFAULT_UI_FONT_SIZE_PX, flags, is_legacy)

        -- Strategy 2: Standard OS Fallback font families with style flags
        if not f then
            local fallbacks = (os_type == "macos") and {"Helvetica Neue", "Arial"} or {"Segoe UI", "DejaVu Sans", "Liberation Sans", "Arial", "sans-serif"}
            for _, fam in ipairs(fallbacks) do
                f = create_ui_font_compat(fam, DEFAULT_UI_FONT_SIZE_PX, flags, is_legacy)
                if f then break end
            end
        end

        return f
    end

    FontManager.font_main        = load_styled_ui_font(flag_none,        "Helvetica Neue")
    FontManager.font_bold        = load_styled_ui_font(flag_bold,        "Helvetica Neue")
    FontManager.font_italic      = load_styled_ui_font(flag_italic,      "Helvetica Neue")
    FontManager.font_bold_italic = load_styled_ui_font(flag_bold_italic, "Helvetica Neue")
    FontManager.font_big         = FontManager.font_bold or FontManager.font_main

    local attached_fonts = {}
    local function safe_attach(f)
        if not f or not ctx or attached_fonts[f] then return end
        if reaper.APIExists("ImGui_ValidatePtr") then
            if not reaper.ImGui_ValidatePtr(ctx, "ImGui_Context*") then return end
            if not reaper.ImGui_ValidatePtr(f, "ImGui_Font*") then return end
        end
        local ok = pcall(reaper.ImGui_Attach, ctx, f)
        if ok then
            attached_fonts[f] = true
        end
    end

    safe_attach(FontManager.font_main)
    safe_attach(FontManager.font_big)
    safe_attach(FontManager.font_bold)
    safe_attach(FontManager.font_italic)
    safe_attach(FontManager.font_bold_italic)
    
    local bravura_candidates = {}
    local b_path = PathService.get_bravura_path(state)
    if b_path and PathService.file_exists(b_path) then
        table.insert(bravura_candidates, b_path)
    end
    local s_dir = PathService.get_script_dir()
    table.insert(bravura_candidates, s_dir .. "/Bravura.otf")
    table.insert(bravura_candidates, s_dir .. "/../Bravura.otf")
    table.insert(bravura_candidates, s_dir .. "/../../Bravura.otf")
    
    for _, path in ipairs(bravura_candidates) do
        if PathService.file_exists(path) then
            FontManager.font_music = create_file_font_compat(path, DEFAULT_MUSIC_FONT_SIZE_PX, flag_none, is_legacy)
            if FontManager.font_music then
                safe_attach(FontManager.font_music)
                break
            end
        end
    end
    FontManager._fonts_ready = true
    return FontManager
end

function FontManager.draw_glyph(draw_list, font, size, x, y, col, glyph)
    if not font or not reaper.APIExists("ImGui_DrawList_AddTextEx") then return false end
    size = math.max(1.0, tonumber(size) or 14.0)
    local pos_y = y - (size * 2.012)
    reaper.ImGui_DrawList_AddTextEx(draw_list, font, size, x, pos_y, col, glyph)
    return true
end

FontManager._text_size_cache = {}
FontManager._text_size_count = 0

function FontManager.calc_text_size(ctx, text)
    if not text or text == "" then return 0, 0 end
    local cached = FontManager._text_size_cache[text]
    if cached then
        return cached[1], cached[2]
    end
    if reaper.APIExists("ImGui_CalcTextSize") then
        local w, h = reaper.ImGui_CalcTextSize(ctx, text)
        w = w or 0
        h = h or 0
        if FontManager._text_size_count >= 1000 then
            FontManager._text_size_cache = {}
            FontManager._text_size_count = 0
        end
        FontManager._text_size_cache[text] = { w, h }
        FontManager._text_size_count = FontManager._text_size_count + 1
        return w, h
    end
    return #text * 7.5, 14.0
end

return FontManager

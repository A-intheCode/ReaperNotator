-- ==============================================================================
-- REAPER Native Notator - Module: FontManager
-- Loads fonts (Segoe UI & Bravura SMuFL) and manages glyph output
-- ==============================================================================

local PathService = require("services.path_service")

local FontManager = {
    font_main = nil,
    font_big = nil,
    font_bold = nil,
    font_italic = nil,
    font_bold_italic = nil,
    font_music = nil,
    _fonts_ready = false
}

function FontManager.init(ctx, state)
    local os_type = PathService.get_os()
    
    local flag_none = reaper.APIExists("ImGui_FontFlags_None") and reaper.ImGui_FontFlags_None() or 0
    local flag_bold = reaper.APIExists("ImGui_FontFlags_Bold") and reaper.ImGui_FontFlags_Bold() or 1
    local flag_italic = reaper.APIExists("ImGui_FontFlags_Italic") and reaper.ImGui_FontFlags_Italic() or 2
    local flag_bold_italic = flag_bold | flag_italic

    local function load_styled_ui_font(flags, mac_family)
        local f = nil
        
        -- Strategy 1: Load via font family name + style flags (DirectWrite / FreeType with full Unicode fallback)
        if reaper.APIExists("ImGui_CreateFont") then
            local primary_family = (os_type == "macos" and mac_family) or "Segoe UI"
            local ok, res = pcall(reaper.ImGui_CreateFont, primary_family, flags)
            if ok and res and (not reaper.APIExists("ImGui_ValidatePtr") or reaper.ImGui_ValidatePtr(res, "ImGui_Font*")) then
                f = res
            end
        end

        -- Strategy 2: Standard OS Fallback font families with style flags
        if not f and reaper.APIExists("ImGui_CreateFont") then
            local fallbacks = (os_type == "macos") and {"Helvetica Neue", "Arial"} or {"Segoe UI", "DejaVu Sans", "Liberation Sans", "Arial", "sans-serif"}
            for _, fam in ipairs(fallbacks) do
                local ok, res = pcall(reaper.ImGui_CreateFont, fam, flags)
                if ok and res and (not reaper.APIExists("ImGui_ValidatePtr") or reaper.ImGui_ValidatePtr(res, "ImGui_Font*")) then
                    f = res
                    break
                end
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
            if reaper.APIExists("ImGui_CreateFontFromFile") then
                local flags = reaper.APIExists("ImGui_FontFlags_None") and reaper.ImGui_FontFlags_None() or 0
                local ok, mf = pcall(reaper.ImGui_CreateFontFromFile, path, flags)
                if not ok or not mf then
                    ok, mf = pcall(reaper.ImGui_CreateFontFromFile, path)
                end
                if ok and mf and (not reaper.APIExists("ImGui_ValidatePtr") or reaper.ImGui_ValidatePtr(mf, "ImGui_Font*")) then
                    FontManager.font_music = mf
                end
            elseif reaper.APIExists("ImGui_CreateFont") then
                local flags = reaper.APIExists("ImGui_FontFlags_None") and reaper.ImGui_FontFlags_None() or 0
                local ok, mf = pcall(reaper.ImGui_CreateFont, path, flags)
                if not ok or not mf then
                    ok, mf = pcall(reaper.ImGui_CreateFont, path)
                end
                if ok and mf and (not reaper.APIExists("ImGui_ValidatePtr") or reaper.ImGui_ValidatePtr(mf, "ImGui_Font*")) then
                    FontManager.font_music = mf
                end
            end
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
    local pos_y = y - (size * 2.012)
    reaper.ImGui_DrawList_AddTextEx(draw_list, font, size, x, pos_y, col, glyph)
    return true
end

return FontManager

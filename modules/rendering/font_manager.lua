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
    local base_font_size = 20
    local os_type = PathService.get_os()
    local function create_ui_font(size, family)
        local f = nil
        if reaper.APIExists("ImGui_CreateFont") then
            if family then
                local ok, res = pcall(reaper.ImGui_CreateFont, family, size)
                if ok and res then f = res end
            end
            if not f then
                local ok, res = pcall(reaper.ImGui_CreateFont, "Segoe UI", size)
                if ok and res then f = res end
            end
            if not f then
                local fallbacks = (os_type == "macos") and {"Helvetica Neue", "Arial"} or {"DejaVu Sans", "Liberation Sans", "Arial"}
                for _, fam in ipairs(fallbacks) do
                    local ok, res = pcall(reaper.ImGui_CreateFont, fam, size)
                    if ok and res then f = res break end
                end
            end
            if not f then
                local ok, res = pcall(reaper.ImGui_CreateFont, "sans-serif", size)
                if ok and res then f = res end
            end
        end
        return f
    end

    FontManager.font_main        = create_ui_font(base_font_size, "Segoe UI")
    FontManager.font_big         = create_ui_font(28,             "Segoe UI Bold")
    FontManager.font_bold        = create_ui_font(base_font_size, "Segoe UI Bold")
    FontManager.font_italic      = create_ui_font(base_font_size, "Segoe UI Italic")
    FontManager.font_bold_italic = create_ui_font(base_font_size, "Segoe UI Bold Italic")

    local attached_fonts = {}
    local function safe_attach(f)
        if not f or not ctx or attached_fonts[f] then return end
        pcall(reaper.ImGui_Attach, ctx, f)
        attached_fonts[f] = true
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
                local ok, mf = pcall(reaper.ImGui_CreateFontFromFile, path, 0, flags)
                if not ok or not mf then
                    ok, mf = pcall(reaper.ImGui_CreateFontFromFile, path)
                end
                if ok and mf then FontManager.font_music = mf end
            elseif reaper.APIExists("ImGui_CreateFont") then
                local ok, mf = pcall(reaper.ImGui_CreateFont, path, 40)
                if not ok or not mf then
                    ok, mf = pcall(reaper.ImGui_CreateFont, path)
                end
                if ok and mf then FontManager.font_music = mf end
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

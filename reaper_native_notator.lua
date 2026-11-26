-- @description REAPER Notator 3.3.7: Native Musical Notation & Engraving Suite
-- @author A-intheCode
-- @version 3.3.7
-- @changelog
--   + v3.3.7:
--     - Dynamics multi-select & move
--     - Dynamics & hairpins copy/paste
--     - Tempo map reset fix
--     - Slur/unslur legato fix
--     - Crushed hairpin resize fix
--     - Negative delay save fix
-- @about
--   # REAPER Notator 3.3.7 (Exclusive Edition)
--   Proprietary native musical notation, score editing, and engraving environment for Cockos REAPER.
--   Requires ReaImGui v0.10+ (Dear ImGui for REAPER by cfillion) and Reaticulate.
--   Note: Master Acoustic Studio VST3 ('Notator Acoustic Master') is supported on Windows (x64) and macOS (Universal2) only — Linux not supported.
--   Copyright (C) 2026 A-intheCode. All Rights Reserved.
-- @provides
--   [nomain] notator_3_core.bin
--   [nomain] Bravura.otf
--   [nomain] patterns.zip
--   [nomain] LICENSE
--   [nomain] README.md
--   [nomain] modules/bin/notator_timer_x64.dll
--   [nomain] data/articulation_delays.json
--   [nomain] data/icons/ReaperNotator_UI_Badge_1x.png
--   [nomain] data/icons/ReaperNotator_UI_Badge_125x.png
--   [nomain] data/icons/ReaperNotator_UI_Badge_150x.png
--   [nomain] data/icons/ReaperNotator_UI_Badge_2x.png
--   [nomain] data/icons/ReaperNotator_UI_Badge_Transparent_64x64.png
--   [nomain] data/icons/ReaperNotator_Settings_Banner_1x.png
--   [nomain] data/icons/ReaperNotator_Settings_Banner_125x.png
--   [nomain] data/icons/ReaperNotator_Settings_Banner_150x.png
--   [nomain] data/icons/ReaperNotator_Settings_Banner_2x.png
--   [nomain] data/icons/ReaperNotator_UI_RN_Transparent_128x128.png
--   [nomain] data/icons/toolbar_icons/toolbar_reaper_notator.png
--   [nomain] data/icons/toolbar_icons/150/toolbar_reaper_notator.png
--   [nomain] data/icons/toolbar_icons/200/toolbar_reaper_notator.png
--   [data] data/icons/toolbar_icons/toolbar_reaper_notator.png > toolbar_icons/toolbar_reaper_notator.png
--   [data] data/icons/toolbar_icons/150/toolbar_reaper_notator.png > toolbar_icons/150/toolbar_reaper_notator.png
--   [data] data/icons/toolbar_icons/200/toolbar_reaper_notator.png > toolbar_icons/200/toolbar_reaper_notator.png
--   [nomain] effects/notator_auto_divisi_input.jsfx
--   [nomain] effects/notator_audition_router.jsfx
--   [nomain] effects/Notator_Attack_Detector.jsfx
--   [nomain] effects/Notator_Articulation_Delay.jsfx
--   [nomain] effects/Notator_Acoustic_Master.vst3
--   [nomain] effects/Notator_Acoustic_Master_macOS.zip
--   [nomain] docs/reaper_notator_user_manual.pdf
-- @license Proprietary (All Rights Reserved - Copyright (C) 2026 A-intheCode)
--
-- ==============================================================================
-- PROPRIETARY SOFTWARE — ALL RIGHTS RESERVED
-- Copyright (C) 2026 A-intheCode. All Rights Reserved.
--
-- LEGAL NOTICE:
-- This software and its binary core (notator_3_core.bin) are proprietary and
-- confidential. Any copying, reproduction, modification, reverse-engineering,
-- decompilation, decryption, unpacking, redistribution, or commercial sale is
-- strictly prohibited without an express prior written license agreement signed
-- by the author (A-intheCode). See LICENSE for complete terms.
-- ==============================================================================

local _0x1a = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local _0x2b = _0x1a:match("(.*/)") or ""
if _0x2b:sub(-1) ~= "/" then _0x2b = _0x2b .. "/" end
rawset(_G, "__NOTATOR_SCRIPT_DIR", _0x2b:gsub("/$", ""))
rawset(_G, "__NOTATOR_ENTRY_FILE", _0x1a)
if reaper and reaper.get_action_context then
    local _ok_c, _, _afn, _asec, _acmd = pcall(reaper.get_action_context)
    if _ok_c then
        if type(_afn) == "string" and _afn ~= "" then rawset(_G, "__NOTATOR_ENTRY_FILE", _afn) end
        if type(_asec) == "number" then rawset(_G, "__NOTATOR_SECTION_ID", _asec) end
        if type(_acmd) == "number" and _acmd > 0 then rawset(_G, "__NOTATOR_CMD_ID", _acmd) end
    end
end

local _0x3c = _0x2b .. "notator_3_core.bin"
local _0x4d = io.open(_0x3c, "rb")
if not _0x4d then
    if reaper and reaper.MB then
        reaper.MB("REAPER Notator 3.3.7 Core Binary ('notator_3_core.bin') is missing!\nPlease synchronize or reinstall via ReaPack.", "REAPER Notator 3.3.7 - Integrity Error", 0)
    end
    return
end
local _0x5e = _0x4d:read("*a")
_0x4d:close()

if not _0x5e or #_0x5e < 16 or _0x5e:sub(1, 4) ~= "RN30" then
    if reaper and reaper.MB then
        reaper.MB("Corrupted or invalid REAPER Notator 3.3.7 core binary.", "REAPER Notator 3.3.7 - Integrity Error", 0)
    end
    return
end

local _u = string.unpack
local _p = string.pack
local _, _ver, _olen, _pos = _u("<c4I4I4", _0x5e, 1)
local _st = 0xA37F92C5E14B8D63
local _out = {}
local _idx = 1
local _len = #_0x5e

local function _finish_boot()
    local _raw = table.concat(_out):sub(1, _olen)
    local _cnt, _rpos = _u("<I4", _raw, 1)
    local _mods = {}
    local _main_code = nil

    for _ = 1, _cnt do
        local _ml, _rl, _cl, _mn, _rp, _cb
        _ml, _rpos = _u("<I2", _raw, _rpos)
        _mn = _raw:sub(_rpos, _rpos + _ml - 1)
        _rpos = _rpos + _ml
        _rl, _rpos = _u("<I2", _raw, _rpos)
        _rp = _raw:sub(_rpos, _rpos + _rl - 1)
        _rpos = _rpos + _rl
        _cl, _rpos = _u("<I4", _raw, _rpos)
        _cb = _raw:sub(_rpos, _rpos + _cl - 1)
        _rpos = _rpos + _cl
        if _mn == "__main__" then
            _main_code = _cb
        else
            _mods[_mn] = { path = _rp, code = _cb }
        end
    end

    _raw = nil
    _out = nil
    _0x5e = nil

    for _k in pairs(package.loaded) do
        if _k:match("^version") or _k:match("^constants") or _k:match("^state") or _k:match("^classes%.") or _k:match("^services%.") or _k:match("^rendering%.") or _k:match("^ui%.") or _k:match("^input%.") then
            package.loaded[_k] = nil
        end
    end

    for _mn, _info in pairs(_mods) do
        package.preload[_mn] = function()
            local _fn, _err = load(_info.code, "@" .. _0x2b .. _info.path, "t")
            if not _fn then error(_err) end
            return _fn()
        end
    end

    if _main_code then
        local _mfn, _merr = load(_main_code, "@" .. _0x2b .. "reaper_native_notator.lua", "t")
        if not _mfn then error(_merr) end
        return _mfn()
    end
end

-- Instant (<20 ms) splash screen during chunked core decryption when ReaImGui is present
local _has_imgui = reaper and reaper.APIExists and reaper.APIExists("ImGui_CreateContext") and reaper.defer
if _has_imgui then
    local _cfg = (reaper.APIExists("ImGui_ConfigFlags_None") and reaper.ImGui_ConfigFlags_None()) or 0
    local _bctx = reaper.ImGui_CreateContext("REAPER Notator 3.3.7", _cfg)
    if reaper.APIExists("ImGui_SetConfigVar") and reaper.APIExists("ImGui_ConfigVar_WindowsResizeFromEdges") then
        reaper.ImGui_SetConfigVar(_bctx, reaper.ImGui_ConfigVar_WindowsResizeFromEdges(), 1)
    end
    rawset(_G, "__NOTATOR_BOOT_CTX", _bctx)

    local _bs = tonumber((reaper.APIExists("GetExtState") and reaper.GetExtState("REAPER_Notator", "ui_scale")) or "") or 1.0
    if _bs ~= _bs or _bs == math.huge or _bs == -math.huge then _bs = 1.0 end
    if _bs < 0.50 then _bs = 0.50 elseif _bs > 2.00 then _bs = 2.00 end
    _bs = math.floor(_bs * 100.0 + 0.5) / 100.0
    if math.abs(_bs - 1.0) < 0.005 then _bs = 1.0 end
    local _b_base_fs, _b_font_mode, _b_uifont = nil, nil, nil

    local _bimg, _bpt = nil, "ImGui_Image*"
    local _idir = _0x2b .. "data/icons/"
    if reaper.APIExists("ImGui_CreateImageSet") and reaper.APIExists("ImGui_ImageSet_Add") and reaper.APIExists("ImGui_CreateImage") then
        local _oks, _set = pcall(reaper.ImGui_CreateImageSet)
        if _oks and _set then
            local _added = 0
            local _specs = {
                { 1.0,  _idir .. "ReaperNotator_Settings_Banner_1x.png" },
                { 1.25, _idir .. "ReaperNotator_Settings_Banner_125x.png" },
                { 1.5,  _idir .. "ReaperNotator_Settings_Banner_150x.png" },
                { 2.0,  _idir .. "ReaperNotator_Settings_Banner_2x.png" },
            }
            for _i = 1, #_specs do
                local _f = io.open(_specs[_i][2], "rb")
                if _f then
                    _f:close()
                    local _oki, _im = pcall(reaper.ImGui_CreateImage, _specs[_i][2])
                    if _oki and _im and pcall(reaper.ImGui_ImageSet_Add, _set, math.max(0.25, _specs[_i][1] / _bs), _im) then
                        _added = _added + 1
                    end
                end
            end
            if _added > 0 then
                if reaper.APIExists("ImGui_Attach") then pcall(reaper.ImGui_Attach, _bctx, _set) end
                _bimg, _bpt = _set, "ImGui_ImageSet*"
            end
        end
    end
    if not _bimg and reaper.APIExists("ImGui_CreateImage") then
        local _fp = _idir .. "ReaperNotator_Settings_Banner_1x.png"
        local _f = io.open(_fp, "rb")
        if _f then
            _f:close()
            local _oki, _im = pcall(reaper.ImGui_CreateImage, _fp)
            if _oki and _im then
                if reaper.APIExists("ImGui_Attach") then pcall(reaper.ImGui_Attach, _bctx, _im) end
                _bimg, _bpt = _im, "ImGui_Image*"
            end
        end
    end
    rawset(_G, "__NOTATOR_BOOT_SPLASH_IMG", _bimg)
    rawset(_G, "__NOTATOR_BOOT_SPLASH_PTYPE", _bpt)
    rawset(_G, "__NOTATOR_BOOT_SPLASH_SCALE", _bs)

    local _lang = (reaper.APIExists("GetExtState") and reaper.GetExtState("REAPER_Notator", "ui_language")) or "en"
    local _st_txt = (_lang == "de" and "Kern-Engine wird geladen...") or (_lang == "fr" and "Chargement du moteur principal...") or "Decrypting Core Engine..."
    local _sub_txt = "v3.3.7  •  " .. ((_lang == "de" and "Native Musiknotation & Notensatz-Suite") or (_lang == "fr" and "Suite native de notation et gravure musicale") or "Native Musical Notation & Engraving Suite")
    local _bflags = 0
    for _, _fn in ipairs({ "ImGui_WindowFlags_NoTitleBar", "ImGui_WindowFlags_NoResize", "ImGui_WindowFlags_NoMove", "ImGui_WindowFlags_NoScrollbar", "ImGui_WindowFlags_NoScrollWithMouse", "ImGui_WindowFlags_NoCollapse", "ImGui_WindowFlags_NoSavedSettings", "ImGui_WindowFlags_TopMost" }) do
        if reaper[_fn] then _bflags = _bflags | reaper[_fn]() end
    end

    local function _draw_boot_splash(_pct)
        if reaper.APIExists("ImGui_ValidatePtr") and not reaper.ImGui_ValidatePtr(_bctx, "ImGui_Context*") then return false end
        local _cx, _cy
        if reaper.APIExists("ImGui_GetMainViewport") and reaper.APIExists("ImGui_Viewport_GetCenter") then
            local _ov, _vp = pcall(reaper.ImGui_GetMainViewport, _bctx)
            if _ov and _vp then
                local _oc, _vx, _vy = pcall(reaper.ImGui_Viewport_GetCenter, _vp)
                if _oc and _vx and _vy then _cx, _cy = _vx, _vy end
            end
        end
        local _cond = (reaper.ImGui_Cond_Always and reaper.ImGui_Cond_Always()) or 1
        local _ww, _wh = math.floor(420 * _bs + 0.5), math.floor(260 * _bs + 0.5)
        local _iw, _ih = math.floor(320 * _bs + 0.5), math.floor(160 * _bs + 0.5)
        local _px, _py = math.max(8, math.floor(24 * _bs + 0.5)), math.max(6, math.floor(16 * _bs + 0.5))
        local _bh = math.max(4, math.floor(8 * _bs + 0.5))
        local _br = math.max(2.0, 4.0 * _bs)
        if _cx and _cy and reaper.ImGui_SetNextWindowPos then reaper.ImGui_SetNextWindowPos(_bctx, _cx, _cy, _cond, 0.5, 0.5) end
        if reaper.ImGui_SetNextWindowSize then reaper.ImGui_SetNextWindowSize(_bctx, _ww, _wh, _cond) end
        local _fpushed = false
        if math.abs(_bs - 1.0) > 0.001 and reaper.ImGui_PushFont then
            if not _b_base_fs and reaper.ImGui_GetFontSize then
                local _ofs, _fsv = pcall(reaper.ImGui_GetFontSize, _bctx)
                if _ofs and type(_fsv) == "number" and _fsv >= 8 and _fsv <= 32 then _b_base_fs = _fsv end
            end
            local _tpx = math.max(6.5, (_b_base_fs or 13.0) * _bs)
            if _b_font_mode == "nil" then
                _fpushed = pcall(reaper.ImGui_PushFont, _bctx, nil, _tpx)
            elseif _b_font_mode == "font" and _b_uifont then
                _fpushed = pcall(reaper.ImGui_PushFont, _bctx, _b_uifont, _tpx)
            elseif _b_font_mode == nil then
                if pcall(reaper.ImGui_PushFont, _bctx, nil, _tpx) then
                    _b_font_mode = "nil"; _fpushed = true
                elseif reaper.APIExists("ImGui_CreateFont") and reaper.APIExists("ImGui_Attach") then
                    local _ocf, _cf = pcall(reaper.ImGui_CreateFont, "sans-serif", 0)
                    if _ocf and _cf then
                        pcall(reaper.ImGui_Attach, _bctx, _cf)
                        if pcall(reaper.ImGui_PushFont, _bctx, _cf, _tpx) then
                            _b_uifont = _cf; _b_font_mode = "font"; _fpushed = true
                        end
                    end
                end
                if not _fpushed then _b_font_mode = "legacy" end
            end
        end
        reaper.ImGui_PushStyleColor(_bctx, reaper.ImGui_Col_WindowBg(), 0x1C2427FF)
        reaper.ImGui_PushStyleColor(_bctx, reaper.ImGui_Col_Border(), 0xFF9F1C99)
        reaper.ImGui_PushStyleColor(_bctx, reaper.ImGui_Col_Text(), 0xE2E8F0FF)
        reaper.ImGui_PushStyleVar(_bctx, reaper.ImGui_StyleVar_WindowRounding(), math.max(4.0, 12.0 * _bs))
        reaper.ImGui_PushStyleVar(_bctx, reaper.ImGui_StyleVar_WindowBorderSize(), 1.5)
        reaper.ImGui_PushStyleVar(_bctx, reaper.ImGui_StyleVar_WindowPadding(), _px, _py)
        reaper.ImGui_PushStyleVar(_bctx, reaper.ImGui_StyleVar_ItemSpacing(), math.max(3.0, 8.0 * _bs), math.max(2.0, 4.0 * _bs))
        local _vis = reaper.ImGui_Begin(_bctx, "##REAPERNotatorSplash", nil, _bflags)
        if _vis then
            if (not _fpushed) and math.abs(_bs - 1.0) > 0.001 and reaper.ImGui_SetWindowFontScale then
                pcall(reaper.ImGui_SetWindowFontScale, _bctx, _bs)
            end
            local _aw = select(1, reaper.ImGui_GetContentRegionAvail(_bctx)) or (_ww - _px * 2)
            local _x0 = reaper.ImGui_GetCursorPosX(_bctx)
            if _bimg and reaper.APIExists("ImGui_Image") then
                reaper.ImGui_SetCursorPosX(_bctx, _x0 + math.max(0, math.floor((_aw - _iw) * 0.5)))
                reaper.ImGui_Image(_bctx, _bimg, _iw, _ih)
            else
                reaper.ImGui_Dummy(_bctx, _aw, _ih)
            end
            local _sw = select(1, reaper.ImGui_CalcTextSize(_bctx, _sub_txt)) or math.floor(260 * _bs)
            reaper.ImGui_SetCursorPosX(_bctx, _x0 + math.max(0, math.floor((_aw - _sw) * 0.5)))
            reaper.ImGui_TextColored(_bctx, 0x94A3B8FF, _sub_txt)
            reaper.ImGui_Spacing(_bctx)
            reaper.ImGui_SetCursorPosX(_bctx, _x0)
            local _bx, _by = reaper.ImGui_GetCursorScreenPos(_bctx)
            reaper.ImGui_Dummy(_bctx, _aw, _bh)
            local _dl = reaper.ImGui_GetWindowDrawList(_bctx)
            if _dl then
                reaper.ImGui_DrawList_AddRectFilled(_dl, _bx, _by, _bx + _aw, _by + _bh, 0x0F1417FF, _br)
                local _fw = math.floor(_aw * _pct + 0.5)
                if _fw > 0 then
                    reaper.ImGui_DrawList_AddRectFilled(_dl, _bx, _by, _bx + math.max(math.floor(6 * _bs + 0.5), _fw), _by + _bh, 0xFF9F1CFF, _br)
                end
                reaper.ImGui_DrawList_AddRect(_dl, _bx, _by, _bx + _aw, _by + _bh, 0x33415599, _br, 0, 1.0)
            end
            reaper.ImGui_Spacing(_bctx)
            local _pl = string.format("%d%%", math.floor(_pct * 100 + 0.5))
            local _pw = select(1, reaper.ImGui_CalcTextSize(_bctx, _pl)) or math.floor(28 * _bs)
            reaper.ImGui_SetCursorPosX(_bctx, _x0)
            reaper.ImGui_TextColored(_bctx, 0xCBD5E1FF, _st_txt)
            reaper.ImGui_SameLine(_bctx, math.max(_x0 + math.floor(100 * _bs + 0.5), _x0 + _aw - _pw))
            reaper.ImGui_TextColored(_bctx, 0xFF9F1CFF, _pl)
        end
        reaper.ImGui_End(_bctx)
        reaper.ImGui_PopStyleVar(_bctx, 4)
        reaper.ImGui_PopStyleColor(_bctx, 3)
        if _fpushed and reaper.ImGui_PopFont then pcall(reaper.ImGui_PopFont, _bctx) end
        return true
    end

    local _first_paint = true
    local function _dec_loop()
        local _frac = (_len > 12) and math.min(1.0, math.max(0.0, (_pos - 13) / (_len - 12))) or 1.0
        local _pct = 0.04 + 0.26 * _frac
        if not _draw_boot_splash(_pct) then return end
        if _first_paint then
            _first_paint = false
            reaper.defer(_dec_loop)
            return
        end
        local _t0 = (reaper.time_precise and reaper.time_precise()) or os.clock()
        local _n = 0
        while _pos <= _len - 7 do
            local _c
            _c, _pos = _u("<I8", _0x5e, _pos)
            _st = (_st + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
            local _z = _st
            _z = ((_z ~ (_z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
            _z = ((_z ~ (_z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
            local _ks = (_z ~ (_z >> 31)) & 0xFFFFFFFFFFFFFFFF
            local _pt = _c ~ _ks
            _st = (_st ~ ((_c >> 17) | ((_c << 47) & 0xFFFFFFFFFFFFFFFF))) & 0xFFFFFFFFFFFFFFFF
            _out[_idx] = _p("<I8", _pt)
            _idx = _idx + 1
            _n = _n + 1
            if (_n & 16383) == 0 then
                local _dt = ((reaper.time_precise and reaper.time_precise()) or os.clock()) - _t0
                if _dt >= 0.032 then break end
            end
        end
        if _pos <= _len - 7 then
            reaper.defer(_dec_loop)
        else
            _finish_boot()
        end
    end
    reaper.defer(_dec_loop)
    return
end

while _pos <= _len - 7 do
    local _c
    _c, _pos = _u("<I8", _0x5e, _pos)
    _st = (_st + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    local _z = _st
    _z = ((_z ~ (_z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
    _z = ((_z ~ (_z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
    local _ks = (_z ~ (_z >> 31)) & 0xFFFFFFFFFFFFFFFF
    local _pt = _c ~ _ks
    _st = (_st ~ ((_c >> 17) | ((_c << 47) & 0xFFFFFFFFFFFFFFFF))) & 0xFFFFFFFFFFFFFFFF
    _out[_idx] = _p("<I8", _pt)
    _idx = _idx + 1
end

return _finish_boot()

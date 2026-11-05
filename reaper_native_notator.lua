-- @description REAPER Notator 3.0: Native Musical Notation & Engraving Suite
-- @author A-intheCode
-- @version 3.01
-- @changelog
--   + v3.01: Update & Hotfix: Add multilingual '• Dot (×1.5) [.]' toggle button in the Left Sidebar under Note Values (toggles augmentation dot on selected notes or for new note input), exact grid-aligned MIDI note durations (0-tick gap on repeated same-pitch notes in Write Notes [D] & Step Input, 0-tick overlap on Slurs), chord slur target pitch resolution, and independent chord note & slur deletion
--   + v3.0: Major Exclusive Release: REAPER Notator 3.0 — Closed-Source Binary Core Architecture, Multi-Staff Engraving, Synthesizer V Studio Pro 2 Live Bridge, Automatic Articulation Negative Delay Scanner, Guitar/Bass Tablature, Melodic Pathfinder 2.0, Circle of Fifths & 1,500 Orchestral Patterns
-- @about
--   # REAPER Notator 3.0 (Exclusive Edition)
--   Proprietary native musical notation, score editing, and engraving environment for Cockos REAPER.
--   Requires ReaImGui v0.10+ (Dear ImGui for REAPER by cfillion) and Reaticulate.
--   Copyright (C) 2026 A-intheCode. All Rights Reserved.
-- @provides
--   [nomain] notator_3_core.bin
--   [nomain] Bravura.otf
--   [nomain] patterns.zip
--   [nomain] LICENSE
--   [nomain] README.md
--   [nomain] modules/bin/notator_timer_x64.dll
--   [nomain] data/articulation_delays.json
--   [nomain] effects/notator_auto_divisi_input.jsfx
--   [nomain] effects/Notator_Attack_Detector.jsfx
--   [nomain] effects/Notator_Articulation_Delay.jsfx
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

local _0x3c = _0x2b .. "notator_3_core.bin"
local _0x4d = io.open(_0x3c, "rb")
if not _0x4d then
    if reaper and reaper.MB then
        reaper.MB("REAPER Notator 3.0 Core Binary ('notator_3_core.bin') is missing!\nPlease synchronize or reinstall via ReaPack.", "REAPER Notator 3.0 - Integrity Error", 0)
    end
    return
end
local _0x5e = _0x4d:read("*a")
_0x4d:close()

if not _0x5e or #_0x5e < 16 or _0x5e:sub(1, 4) ~= "RN30" then
    if reaper and reaper.MB then
        reaper.MB("Corrupted or invalid REAPER Notator 3.0 core binary.", "REAPER Notator 3.0 - Integrity Error", 0)
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

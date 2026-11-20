-- @description REAPER Notator 3.3: Native Musical Notation & Engraving Suite
-- @author A-intheCode
-- @version 3.3
-- @changelog
--   + v3.3: Integrated Notation-Safe Piano Roll: Dual-Reality Played Durations (Shift+Drag Pre-Roll & Legato Tail Ghost-Halos + Humanizer with 0% score/MusicXML impact), Draw-Hold-Drag auto-lengthening, Grid Razor Split (✂) & Same-Pitch Heal/Glue Brush, Scale Check ('Out-of-Scale Red'), Percussion Drum Map sidebar, Multi-Track Stencils & Smart-Lock, Top Bar View/Note-Coloring menus (incl. Sub-Beat Rests), and updated v3.3 Manual
--   + v3.2.3: Linked multi-staff transposition (Ctrl+A + Key & Chords, EN/DE/FR), MusicXML chord import, collapsible Score Tools, taller Chord & Rehearsal lanes, and updated v3.2.3 Manual
--   + v3.2.2: Hotfix Record Caching
--   + v3.2.1: Record Mode Performance Hotfix: Fix 'Live Note Preview on Canvas while Recording' toggle (strictly zero canvas notes, zero mid-recording MediaItems, and 0.0ms silent-canvas cache reuse when unchecked while preserving 100% of recorded notes, Auto-Divisi, Full Ensemble Fill & CCs on Stop), fix 1-Bar Recording Pre-roll punch-in session sync, batch multi-track bar commits inside PreventUIRefresh, bypass mid-recording full-project item/hash scans, add O(1) incremental live-bar engraving & monotonic active-bar width stabilization for stutter-free Smooth Auto-Scroll, and update User Manual to v3.2.1
--   + v3.2: Major Feature & Engine Update: Master Acoustic Studio ('Notator Acoustic Master' 64-bit VST3 with 1-click zero-UAC/zero-sudo auto-installer, 8-Point TPT-SVF Graphical EQ, Dynamic Concert Mastering & Anti-Click Lookahead Limiter — supported on Windows x64 & macOS Universal2; greyed out on Linux with 'Linux not supported' tooltip), Tempo-Mapped Audio Wave Tracks & Audio-to-MIDI transcription, Multilingual UI (English / Deutsch / Français) & Studio Dark/Light UI themes, 1-Bar Non-Overlapping Live Recording Engine with syncopation extension, Stop-only Auto-Voice, 60-FPS 16-track gmem preview & true playable instrument ranges, expanded MusicXML (.musicxml / .xml / .mxl) importer with Elaine Gould Grand Staff slur & orchestral clef autodetection, dedicated Notator vs. REAPER update checker, and updated v3.2 User Manual
--   + v3.1: Major Feature & Engine Update: Massive upgrade of Melodic Pathfinder (Orchestra, Guitar & Bass, and Percussions / Drums modes, Reference Profile blending, dedicated Select Notes marquee mode, Merge Selected Notes / Overridden Note locks, and Note Length Multiplier — see Manual for details), plus improvements for Hairpins & Crescendos and Articulation Switching
--   + v3.01: Update & Hotfix: Add multilingual '• Dot (×1.5) [.]' toggle button in the Left Sidebar under Note Values (toggles augmentation dot on selected notes or for new note input), exact grid-aligned MIDI note durations (0-tick gap on repeated same-pitch notes in Write Notes [D] & Step Input, 0-tick overlap on Slurs), chord slur target pitch resolution, and independent chord note & slur deletion
--   + v3.0: Major Exclusive Release: REAPER Notator 3.0 — Closed-Source Binary Core Architecture, Multi-Staff Engraving, Synthesizer V Studio Pro 2 Live Bridge, Automatic Articulation Negative Delay Scanner, Guitar/Bass Tablature, Melodic Pathfinder 2.0, Circle of Fifths & 1,500 Orchestral Patterns
-- @about
--   # REAPER Notator 3.3 (Exclusive Edition)
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

local _0x3c = _0x2b .. "notator_3_core.bin"
local _0x4d = io.open(_0x3c, "rb")
if not _0x4d then
    if reaper and reaper.MB then
        reaper.MB("REAPER Notator 3.3 Core Binary ('notator_3_core.bin') is missing!\nPlease synchronize or reinstall via ReaPack.", "REAPER Notator 3.3 - Integrity Error", 0)
    end
    return
end
local _0x5e = _0x4d:read("*a")
_0x4d:close()

if not _0x5e or #_0x5e < 16 or _0x5e:sub(1, 4) ~= "RN30" then
    if reaper and reaper.MB then
        reaper.MB("Corrupted or invalid REAPER Notator 3.3 core binary.", "REAPER Notator 3.3 - Integrity Error", 0)
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

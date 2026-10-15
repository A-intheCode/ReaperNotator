-- ==============================================================================
-- REAPER Native Notator - Module: FrameTimerService
-- Unlocks true 60 / 90 / 120 / 144 FPS in REAPER by synchronizing REAPER's
-- native main-window timer (0x29a) with state.target_fps, and safely restoring
-- REAPER's default 30ms timer when REAPER Notator closes.
-- ==============================================================================

local FrameTimerService = {
    _initialized = false,
    _available = false,
    _applied_fps = nil,
    _fns = {}
}

local function get_dll_path()
    local info = debug.getinfo(1, "S")
    local src = info and info.source and info.source:match("^@?(.*)") or ""
    local dir = src:match("^(.*[\\/])") or ""
    -- FrameTimerService lives in modules/services/, so modules/bin/ is ../bin/
    local bin_path = dir .. "../bin/notator_timer_x64.dll"
    if reaper.file_exists(bin_path) then
        return bin_path
    end
    local res_path = reaper.GetResourcePath()
    local fallback1 = res_path .. "/Scripts/REAPER-Notator/modules/bin/notator_timer_x64.dll"
    if reaper.file_exists(fallback1) then
        return fallback1
    end
    return nil
end

function FrameTimerService.init(state)
    if FrameTimerService._initialized then
        if state then
            FrameTimerService.apply_target_fps(state.target_fps or 60)
        end
        return FrameTimerService._available
    end
    FrameTimerService._initialized = true

    local os_name = reaper.GetOS and reaper.GetOS() or ""
    if not os_name:find("Win64") and not os_name:find("Win32") then
        FrameTimerService._available = false
        return false
    end

    if not package or type(package.loadlib) ~= "function" then
        FrameTimerService._available = false
        return false
    end

    local dll_path = get_dll_path()
    if not dll_path then
        FrameTimerService._available = false
        return false
    end

    local symbols = {
        fps_15       = "notator_set_fps_15",
        fps_30       = "notator_set_fps_30",
        fps_60       = "notator_set_fps_60",
        fps_90       = "notator_set_fps_90",
        fps_120      = "notator_set_fps_120",
        fps_144      = "notator_set_fps_144",
        fps_uncapped = "notator_set_fps_uncapped",
        heartbeat    = "notator_timer_heartbeat",
        restore      = "notator_restore_timer",
    }

    local ok_all = true
    for key, sym in pairs(symbols) do
        local ok, fn = pcall(package.loadlib, dll_path, sym)
        if ok and type(fn) == "function" then
            FrameTimerService._fns[key] = fn
        else
            ok_all = false
        end
    end

    FrameTimerService._available = ok_all
    if ok_all and state then
        FrameTimerService.apply_target_fps(state.target_fps or 60)
    end
    return FrameTimerService._available
end

function FrameTimerService.apply_target_fps(target_fps)
    if not FrameTimerService._initialized then
        FrameTimerService.init(nil)
    end
    if not FrameTimerService._available then
        return false
    end

    local fps = tonumber(target_fps) or 60
    FrameTimerService._applied_fps = fps

    local fns = FrameTimerService._fns
    local fn = fns.fps_60
    if fps == 0 then
        fn = fns.fps_uncapped
    elseif fps <= 15 then
        fn = fns.fps_15
    elseif fps <= 32 then
        fn = fns.fps_30
    elseif fps <= 65 then
        fn = fns.fps_60
    elseif fps <= 95 then
        fn = fns.fps_90
    elseif fps <= 125 then
        fn = fns.fps_120
    else
        fn = fns.fps_144
    end

    if fn then
        pcall(fn)
        return true
    end
    return false
end

function FrameTimerService.tick(state)
    if not FrameTimerService._initialized then
        FrameTimerService.init(state)
    end
    if not FrameTimerService._available then
        return
    end

    local desired_fps = (state and state.target_fps ~= nil) and state.target_fps or 60
    if FrameTimerService._applied_fps ~= desired_fps then
        FrameTimerService.apply_target_fps(desired_fps)
    end

    local hb = FrameTimerService._fns.heartbeat
    if hb then
        pcall(hb)
    end
end

function FrameTimerService.restore()
    if FrameTimerService._available and FrameTimerService._fns.restore then
        pcall(FrameTimerService._fns.restore)
    end
    FrameTimerService._applied_fps = nil
end

return FrameTimerService


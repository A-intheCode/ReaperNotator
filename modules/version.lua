-- ==============================================================================
-- REAPER Native Notator - Module: Version
-- Single-source-of-truth versioning and build descriptor
-- ==============================================================================

local Version = {
    major = 2,
    minor = 42,
    patch = 0,
    suffix = "-beta",
}

Version.SEMVER = (Version.patch == 0) and string.format("%d.%d%s", Version.major, Version.minor, Version.suffix) or string.format("%d.%d.%d%s", Version.major, Version.minor, Version.patch, Version.suffix)

-- Cache for dynamic git hash
local cached_display = nil

local function read_first_line(filepath)
    local f = io.open(filepath, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
end

local function read_header_version(filepath)
    local f = io.open(filepath, "r")
    if not f then return nil end
    for _ = 1, 10 do
        local line = f:read("*l")
        if not line then break end
        local ver = line:match("^%-%-%s*@version%s+([%d%.%-%w_]+)")
        if ver and ver ~= "" then
            f:close()
            return ver
        end
    end
    f:close()
    return nil
end

function Version.get_display_string()
    if cached_display then
        return cached_display
    end

    -- Synchronize with @version header in main entry point if available
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    local root_dir = nil
    if info and info.source and info.source:sub(1, 1) == "@" then
        local script_source = info.source:sub(2):gsub("\\", "/")
        local mod_dir = script_source:match("(.*/)") or ""
        root_dir = mod_dir:gsub("/modules/?$", "")
        local main_ver = read_header_version(root_dir .. "/reaper_native_notator.lua")
        if main_ver and main_ver ~= Version.SEMVER then
            Version.SEMVER = main_ver
        end
    end

    local base = "v" .. Version.SEMVER

    -- Non-blocking pure-Lua git commit detection (only when .git/HEAD exists on disk; never spawns external processes)
    if root_dir then
        local git_dir = root_dir .. "/.git"
        local head_line = read_first_line(git_dir .. "/HEAD")
        if head_line then
            local hash = nil
            local ref_path = head_line:match("^ref:%s*(%S+)")
            if ref_path then
                local ref_line = read_first_line(git_dir .. "/" .. ref_path)
                if ref_line then
                    hash = ref_line:match("^([0-9a-fA-F]+)")
                end
            else
                hash = head_line:match("^([0-9a-fA-F]+)")
            end
            if hash and #hash >= 7 then
                cached_display = string.format("%s (%s)", base, hash:sub(1, 7))
                return cached_display
            end
        end
    end

    cached_display = base
    return cached_display
end

return Version

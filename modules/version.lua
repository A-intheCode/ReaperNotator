-- ==============================================================================
-- REAPER Native Notator - Module: Version
-- Single-source-of-truth versioning and build descriptor
-- ==============================================================================

local Version = {
    major = 2,
    minor = 0,
    patch = 1,
    suffix = "", -- Official 2.0.1 Release (2-step Maximize & Startup Center Fix)
}

Version.SEMVER = string.format("%d.%d.%d%s", Version.major, Version.minor, Version.patch, Version.suffix)

-- Cache for dynamic git hash
local cached_display = nil

local function read_first_line(filepath)
    local f = io.open(filepath, "r")
    if not f then return nil end
    local line = f:read("*l")
    f:close()
    return line
end

function Version.get_display_string()
    if cached_display then
        return cached_display
    end

    local base = "v" .. Version.SEMVER

    -- Non-blocking pure-Lua git commit detection (only when .git/HEAD exists on disk; never spawns external processes)
    local info = debug and debug.getinfo and debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local script_source = info.source:sub(2):gsub("\\", "/")
        local mod_dir = script_source:match("(.*/)") or ""
        local root_dir = mod_dir:gsub("/modules/?$", "")
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

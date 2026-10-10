-- ==============================================================================
-- REAPER Native Notator - Module: Version
-- Single-source-of-truth versioning and build descriptor
-- ==============================================================================

local Version = {
    major = 1,
    minor = 8,
    patch = 0,
    suffix = "-beta.16", -- e.g. "-beta", "-rc1"
}

Version.SEMVER = string.format("%d.%d.%d%s", Version.major, Version.minor, Version.patch, Version.suffix)

-- Cache for dynamic git hash
local cached_display = nil

function Version.get_display_string()
    if cached_display then
        return cached_display
    end

    local base = "v" .. Version.SEMVER

    -- Attempt dynamic git detection if running inside a git repository
    if reaper and reaper.ExecProcess then
        local script_source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
        local script_dir = script_source:match("(.*/)") or ""
        -- Try reading git commit hash
        local cmd = string.format('git -C "%s" rev-parse --short HEAD', script_dir)
        local ok, out = reaper.ExecProcess(cmd, 300)
        if ok and out and #out >= 4 then
            local hash = out:match("([0-9a-fA-F]+)")
            if hash and #hash >= 4 then
                cached_display = string.format("%s (%s)", base, hash)
                return cached_display
            end
        end
    end

    cached_display = base
    return cached_display
end

return Version

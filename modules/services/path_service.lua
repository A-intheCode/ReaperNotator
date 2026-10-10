-- ==============================================================================
-- REAPER Native Notator - Module: PathService
-- Central path and platform service for cross-platform path resolution
-- Supports Windows, macOS, and Linux without any hardcoded user paths
-- ==============================================================================

local PathService = {}

local _cached_script_dir = nil
local _cached_bravura_path = nil

--- Determines the operating system via REAPER API
--- @return string "windows"|"macos"|"linux", string raw REAPER OS string
function PathService.get_os()
    local os_str = (reaper.APIExists("GetOS") and reaper.GetOS()) or ""
    if os_str:match("^Win") then
        return "windows", os_str
    elseif os_str:match("^OSX") or os_str:match("^macOS") then
        return "macos", os_str
    else
        return "linux", os_str
    end
end

--- Returns the native system path separator
--- @return string "\\" or "/"
function PathService.get_separator()
    return (package and package.config and package.config:sub(1,1)) or "/"
end

--- Normalizes a path: unifies slashes, cleans up redundant slashes
--- @param p string
--- @return string
function PathService.normalize(p)
    if not p or p == "" then return "" end
    -- Standardize on forward slashes "/" (supported cross-platform by Lua and REAPER)
    local norm = p:gsub("\\", "/")
    -- Preserve UNC paths on Windows (e.g. //server/share)
    local is_unc = norm:match("^//")
    norm = norm:gsub("/+", "/")
    if is_unc then norm = "/" .. norm end
    -- Remove trailing slash (except for root "/")
    if #norm > 1 and norm:sub(-1) == "/" and not norm:match("^%a:/$") then
        norm = norm:sub(1, -2)
    end
    return norm
end

--- Formats a path according to native OS display conventions
--- @param p string
--- @return string
function PathService.to_native(p)
    local norm = PathService.normalize(p)
    local os_type = PathService.get_os()
    if os_type == "windows" then
        return norm:gsub("/", "\\")
    else
        return norm
    end
end

--- Safely checks if a file exists
--- @param filepath string
--- @return boolean
function PathService.file_exists(filepath)
    if not filepath or filepath == "" then return false end
    if reaper.APIExists("file_exists") then
        return reaper.file_exists(filepath)
    end
    local f = io.open(filepath, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

--- Safely checks if a directory exists
--- @param dirpath string
--- @return boolean
function PathService.dir_exists(dirpath)
    if not dirpath or dirpath == "" then return false end
    local norm = PathService.normalize(dirpath)
    if reaper.APIExists("EnumerateFiles") then
        local f = reaper.EnumerateFiles(norm, 0)
        local d = reaper.EnumerateSubdirectories(norm, 0)
        if f ~= nil or d ~= nil then return true end
    end
    -- Fallback test via temporary file probe
    local test_f = io.open(norm .. "/.notator_dir_test", "w")
    if test_f then
        test_f:close()
        os.remove(norm .. "/.notator_dir_test")
        return true
    end
    return false
end

--- Dynamically determines root directory of REAPER-Notator
--- Works in any location without any hardcoded paths
--- @return string normalized path to REAPER-Notator folder
function PathService.get_script_dir()
    if _cached_script_dir and _cached_script_dir ~= "" then
        return _cached_script_dir
    end

    -- 1. Attempt: Determine module path via debug.getinfo(1, "S").source
    local info = debug.getinfo(1, "S")
    if info and info.source and info.source:sub(1, 1) == "@" then
        local src_path = PathService.normalize(info.source:sub(2))
        -- path_service.lua is in modules/services/ -> go up two directory levels
        local parent_dir = src_path:match("(.*/modules/services/)") or src_path:match("(.*/modules/)") or src_path:match("(.*/)")
        if parent_dir then
            local root = parent_dir:gsub("/modules/services/?$", ""):gsub("/modules/?$", "")
            if root and root ~= "" and PathService.file_exists(root .. "/Bravura.otf") then
                _cached_script_dir = root
                return _cached_script_dir
            elseif root and root ~= "" then
                _cached_script_dir = root
                return _cached_script_dir
            end
        end
    end

    -- 2. Attempt: Default location via REAPER ResourcePath
    local res_path = ""
    if reaper.APIExists("GetResourcePath") then
        res_path = PathService.normalize(reaper.GetResourcePath())
    end
    local candidates = {
        res_path .. "/Scripts/REAPER-Notator",
        res_path .. "/Scripts/reaper-notator",
        res_path .. "/Scripts/REAPER-Notator-main"
    }
    for _, c in ipairs(candidates) do
        if PathService.file_exists(c .. "/Bravura.otf") or PathService.dir_exists(c .. "/modules") then
            _cached_script_dir = c
            return _cached_script_dir
        end
    end

    -- 3. Fallback
    _cached_script_dir = res_path .. "/Scripts/REAPER-Notator"
    return _cached_script_dir
end

--- Determines the REAPER resource folder (respects manual user override in Settings)
--- @param state table|nil
--- @return string normalized path
function PathService.get_reaper_resource_dir(state)
    -- 1. Check manual override from application state or ExtState
    local custom = nil
    if state and state.custom_resource_path and state.custom_resource_path ~= "" then
        custom = state.custom_resource_path
    elseif reaper.APIExists("GetExtState") then
        local ext = reaper.GetExtState("REAPER_Notator", "reaper_resource_path")
        if ext and ext ~= "" then custom = ext end
    end

    if custom and custom ~= "" then
        local norm = PathService.normalize(custom)
        if PathService.dir_exists(norm) then
            return norm
        end
    end

    -- 2. Fallback to official REAPER resource path
    if reaper.APIExists("GetResourcePath") then
        local rpath = reaper.GetResourcePath()
        if rpath and rpath ~= "" then
            return PathService.normalize(rpath)
        end
    end

    return ""
end

--- Returns an OS-specific hint for the default REAPER resource folder
--- @return string
function PathService.get_os_default_path_hint()
    local os_type = PathService.get_os()
    if os_type == "windows" then
        return "%APPDATA%\\REAPER  (e.g. C:\\Users\\<user>\\AppData\\Roaming\\REAPER)"
    elseif os_type == "macos" then
        return "~/Library/Application Support/REAPER  (e.g. /Users/<user>/Library/Application Support/REAPER)"
    else
        return "~/.config/REAPER  (e.g. /home/<user>/.config/REAPER)"
    end
end

--- Finds Bravura.otf music font dynamically and relatively
--- @param state table|nil
--- @return string|nil
function PathService.get_bravura_path(state)
    if _cached_bravura_path and PathService.file_exists(_cached_bravura_path) then
        return _cached_bravura_path
    end

    local s_dir = PathService.get_script_dir()
    local res_dir = PathService.get_reaper_resource_dir(state)

    local candidates = {
        s_dir .. "/Bravura.otf",
        s_dir .. "/../Bravura.otf",
        s_dir .. "/../../Bravura.otf",
        res_dir .. "/Scripts/REAPER-Notator/Bravura.otf",
        res_dir .. "/Scripts/reaper-notator/Bravura.otf",
        res_dir .. "/Data/Bravura.otf"
    }

    for _, p in ipairs(candidates) do
        local norm = PathService.normalize(p)
        if PathService.file_exists(norm) then
            _cached_bravura_path = norm
            return norm
        end
    end

    -- Fallback to relative default location
    return s_dir .. "/Bravura.otf"
end

--- Returns directory of orchestral pattern library
--- @param state table|nil
--- @return string
function PathService.get_patterns_dir(state)
    local s_dir = PathService.get_script_dir()
    local p = s_dir .. "/patterns"
    if PathService.dir_exists(p) then
        return p
    end
    local res_dir = PathService.get_reaper_resource_dir(state)
    local fallback = res_dir .. "/Scripts/REAPER-Notator/patterns"
    if PathService.dir_exists(fallback) then
        return fallback
    end
    return p
end

--- Returns Reaticulate Scripts directory
--- @param state table|nil
--- @return string
function PathService.get_reaticulate_dir(state)
    local res_dir = PathService.get_reaper_resource_dir(state)
    return res_dir .. "/Scripts/Reaticulate"
end

--- Returns Data directory for ReaBanks
--- @param state table|nil
--- @return string
function PathService.get_reabank_dir(state)
    local res_dir = PathService.get_reaper_resource_dir(state)
    return res_dir .. "/Data"
end

--- Runs diagnostics on all relevant paths (for Settings status badges)
--- @param state table|nil
--- @return table status report
function PathService.detect_status(state)
    local os_type, os_raw = PathService.get_os()
    local res_dir = PathService.get_reaper_resource_dir(state)
    local res_dir_valid = PathService.dir_exists(res_dir)
    local script_dir = PathService.get_script_dir()
    local bravura_path = PathService.get_bravura_path(state)
    local bravura_valid = PathService.file_exists(bravura_path)
    local patterns_dir = PathService.get_patterns_dir(state)
    local patterns_valid = PathService.dir_exists(patterns_dir)

    -- Check Reaticulate & ReaBanks
    local reat_dir = PathService.get_reaticulate_dir(state)
    local reat_user_bank = PathService.get_reabank_dir(state) .. "/Reaticulate.reabank"
    local reat_factory_bank = reat_dir .. "/Reaticulate-factory.reabank"

    local reaticulate_found = PathService.file_exists(reat_user_bank) or PathService.file_exists(reat_factory_bank) or PathService.dir_exists(reat_dir)

    -- Count ReaBank files
    local data_dir = PathService.get_reabank_dir(state)
    local reabank_count = 0
    if reaper.APIExists("EnumerateFiles") and PathService.dir_exists(data_dir) then
        local idx = 0
        while true do
            local fn = reaper.EnumerateFiles(data_dir, idx)
            if not fn or fn == "" then break end
            if fn:lower():match("%.reabank$") then
                reabank_count = reabank_count + 1
            end
            idx = idx + 1
        end
    end
    if reaper.APIExists("EnumerateFiles") and PathService.dir_exists(reat_dir) then
        local idx = 0
        while true do
            local fn = reaper.EnumerateFiles(reat_dir, idx)
            if not fn or fn == "" then break end
            if fn:lower():match("%.reabank$") then
                reabank_count = reabank_count + 1
            end
            idx = idx + 1
        end
    end

    return {
        os_type = os_type,
        os_raw = os_raw,
        res_dir = res_dir,
        res_dir_valid = res_dir_valid,
        script_dir = script_dir,
        bravura_path = bravura_path,
        bravura_valid = bravura_valid,
        patterns_dir = patterns_dir,
        patterns_valid = patterns_valid,
        reaticulate_found = reaticulate_found,
        reat_user_bank = reat_user_bank,
        reabank_count = reabank_count
    }
end

--- Opens a native Save File dialog
--- @param default_path string Default full file path or directory
--- @param title string Dialog title
--- @param default_ext string e.g. "musicxml"
--- @return string|nil picked_file
function PathService.browse_for_save_file(default_path, title, default_ext)
    default_ext = default_ext or "musicxml"
    title = title or "Save File"
    default_path = PathService.normalize(default_path or "")

    local initial_dir = default_path:match("^(.*)/") or ""
    local initial_fn = default_path:match("[^/]+$") or ("export_score." .. default_ext)
    if initial_dir == "" and reaper.GetProjectPath then
        local p = reaper.GetProjectPath("")
        if p and p ~= "" then initial_dir = PathService.normalize(p) end
    end

    -- 1. First priority: native JS_Dialog_BrowseForSaveFile from js_ReaScriptAPI
    if reaper.APIExists("JS_Dialog_BrowseForSaveFile") then
        local ext_list = string.format("%s Files (*.%s)\0*.%s\0All Files (*.*)\0*.*\0\0", default_ext:upper(), default_ext, default_ext)
        local ok, picked = reaper.JS_Dialog_BrowseForSaveFile(title, initial_dir:gsub("/", "\\"), initial_fn, ext_list)
        if ok == 1 and picked and picked ~= "" then
            return PathService.normalize(picked)
        elseif ok == 0 then
            return nil
        end
    end

    local os_type = PathService.get_os()

    -- 2. Windows fallback: PowerShell SaveFileDialog
    if os_type == "windows" then
        local res_dir = PathService.normalize(reaper.GetResourcePath())
        local script_path = res_dir .. "/_notator_save_dlg.ps1"
        local out_path = res_dir .. "/_notator_save_out.txt"

        local ps_lines = {
            "$ProgressPreference = 'SilentlyContinue'",
            "Add-Type -AssemblyName System.Windows.Forms",
            "$d = New-Object System.Windows.Forms.SaveFileDialog",
            string.format("$d.Title = '%s'", title:gsub("'", "''")),
            string.format("$d.InitialDirectory = '%s'", initial_dir:gsub("/", "\\"):gsub("'", "''")),
            string.format("$d.FileName = '%s'", initial_fn:gsub("'", "''")),
            string.format("$d.Filter = '%s Files (*.%s)|*.%s|All Files (*.*)|*.*'", default_ext:upper(), default_ext, default_ext),
            string.format("$d.DefaultExt = '%s'", default_ext),
            "$d.OverwritePrompt = $true",
            "if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {",
            string.format("    Set-Content -Path '%s' -Value $d.FileName -Encoding UTF8", out_path:gsub("/", "\\"):gsub("'", "''")),
            "}"
        }

        local f = io.open(script_path, "w")
        if f then
            f:write(table.concat(ps_lines, "\r\n"))
            f:close()

            os.remove(out_path)
            local cmd = string.format('powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%s"', script_path:gsub("/", "\\"))
            os.execute(cmd)
            os.remove(script_path)

            local out_f = io.open(out_path, "r")
            if out_f then
                local res = out_f:read("*l")
                out_f:close()
                os.remove(out_path)
                if res and res ~= "" then
                    return PathService.normalize(res)
                end
            end
            return nil
        end
    end

    -- 3. macOS fallback: osascript choose file name
    if os_type == "macos" then
        local cmd = string.format([[osascript -e 'set f to choose file name with prompt "%s" default name "%s"' 2>/dev/null]],
            title:gsub('"', '\\"'), initial_fn:gsub('"', '\\"'))
        local pipe = io.popen(cmd)
        if pipe then
            local res = pipe:read("*l")
            pipe:close()
            if res and res:match("^alias ") then
                res = res:gsub("^alias ", "")
            end
            if res and res ~= "" then
                local pcmd = string.format([[osascript -e 'POSIX path of "%s"' 2>/dev/null]], res:gsub('"', '\\"'))
                local ppipe = io.popen(pcmd)
                if ppipe then
                    local posix = ppipe:read("*l")
                    ppipe:close()
                    if posix and posix ~= "" then res = posix end
                end
                return PathService.normalize(res)
            end
        end
    end

    -- 4. Universal fallback: GetUserInputs
    local ok, user_in = reaper.GetUserInputs(title, 1, string.format("Save path (*.%s):,extrawidth=350", default_ext), default_path)
    if ok and user_in and user_in ~= "" then
        return PathService.normalize(user_in)
    end

    return nil
end

return PathService

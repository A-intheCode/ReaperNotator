local PathService = require("services.path_service")

local ReaticulateParser = {}

function ReaticulateParser.extract_vendor_library_section(group)
    if not group or group == "" then
        return "User / Custom", "Custom", "Standard"
    end
    local parts = {}
    for part in group:gmatch("[^/]+") do
        local p = part:gsub("^%s+", ""):gsub("%s+$", "")
        if p ~= "" then table.insert(parts, p) end
    end
    if #parts >= 3 then
        -- e.g. "Spitfire/Albion 1/Strings" -> Vendor: "Spitfire", Library: "Albion 1", Section: "Strings"
        return parts[1], parts[2], parts[3]
    elseif #parts == 2 then
        -- e.g. "Spitfire/Albion 1" -> Vendor: "Spitfire", Library: "Albion 1", Section: "All"
        return parts[1], parts[2], "All"
    elseif #parts == 1 then
        return parts[1], parts[1], "All"
    else
        return "User / Custom", "Custom", "Standard"
    end
end

function ReaticulateParser.extract_library_and_section(group)
    local v, l, s = ReaticulateParser.extract_vendor_library_section(group)
    return l, s
end

function ReaticulateParser.parse_file(filepath, banks_dict)
    local f = io.open(filepath, "r")
    if not f then return false end
    
    local current_bank = nil
    local current_category = "long"
    local current_icon = nil
    local pending_group = ""
    local pending_name = ""
    local pending_id = ""
    local pending_clone = nil
    
    for line in f:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        
        -- Parse Group and Name: //! g="Group" n="Name"
        local g, n = line:match('//!%s*g="([^"]+)"%s*n="([^"]+)"')
        if g and n then
            pending_group = g
            pending_name = n
        else
            local n_only = line:match('//!%s*n="([^"]+)"')
            if n_only then pending_name = n_only end
            local g_only = line:match('//!%s*g="([^"]+)"')
            if g_only then pending_group = g_only end
        end
        
        -- Parse Clone: //! clone="Target" or //! clone=Target
        local clone = line:match('//!%s*clone="([^"]+)"') or line:match('//!%s*clone=([%S]+)')
        if clone then
            pending_clone = clone:gsub('^"', ''):gsub('"$', '')
        end
        
        -- Parse ID: //! id="UUID" or //! id=UUID
        local id = line:match('//!%s*id="([^"]+)"') or line:match('//!%s*id=([%w%-]+)')
        if id then
            pending_id = id
        end
        
        -- Parse Bank: Bank MSB LSB Name
        if line:match("^Bank%s+") then
            local b_msb, b_lsb, b_name = line:match("^Bank%s+([^%s]+)%s+([^%s]+)%s+(.*)")
            if b_name then
                local ven, lib, sec = ReaticulateParser.extract_vendor_library_section(pending_group)
                current_bank = {
                    msb = (b_msb == "*") and -1 or tonumber(b_msb),
                    lsb = (b_lsb == "*") and -1 or tonumber(b_lsb),
                    name = b_name,
                    group = pending_group,
                    vendor = ven,
                    library = lib,
                    section = sec,
                    id = pending_id,
                    clone_target = pending_clone,
                    articulations = {}
                }
                table.insert(banks_dict, current_bank)
                pending_clone = nil
                pending_id = ""
                current_category = "long"
            end
        end
        
        -- Parse Articulation category and icon: //! c=legato i=legato o=note:0
        local c = line:match('//!.*c=([^%s]+)')
        if c then
            current_category = c
        end
        local ic = line:match('//!.*i=([^%s]+)')
        if ic then
            current_icon = ic
        end
        
        -- Parse Articulation PC: 20 legato
        local pc, art_name = line:match("^(%d+)%s+(.+)")
        if pc and current_bank then
            local clean_cat = current_category or "misc"
            table.insert(current_bank.articulations, {
                pc = tonumber(pc),
                name = art_name,
                category = clean_cat,
                icon = current_icon
            })
            current_category = "long"
            current_icon = nil
        end
    end
    
    f:close()
    return true
end

function ReaticulateParser.scan_and_parse_directory(dir_path, banks)
    if not dir_path or not reaper.APIExists("EnumerateFiles") then return end
    local idx = 0
    while true do
        local fname = reaper.EnumerateFiles(dir_path, idx)
        if not fname or fname == "" then break end
        if fname:lower():match("%.reabank$") and not fname:lower():match("^reaticulate%-tmp") then
            local full_path = dir_path .. "/" .. fname
            ReaticulateParser.parse_file(full_path, banks)
        end
        idx = idx + 1
    end
end

function ReaticulateParser._load_banks_from_disk(state)
    local raw_banks = {}
    local script_dir = PathService.get_reaticulate_dir(state)
    local data_dir = PathService.get_reabank_dir(state)
    
    -- 1. User Reabank first (highest priority for user definitions)
    ReaticulateParser.parse_file(data_dir .. "/Reaticulate.reabank", raw_banks)
    
    -- 2. Scan all .reabank files in Scripts/Reaticulate folder
    ReaticulateParser.scan_and_parse_directory(script_dir, raw_banks)
    
    -- 3. Fallback for factory Reabank if directory scan was empty
    if #raw_banks == 0 then
        ReaticulateParser.parse_file(script_dir .. "/Reaticulate-factory.reabank", raw_banks)
    end
    
    -- 4. Scan all additional .reabank files in Data/ directory (e.g., custom ReaBanks)
    ReaticulateParser.scan_and_parse_directory(data_dir, raw_banks)
    
    -- 5. Deduplicate by ID or group+name (user entry retains precedence)
    local seen_ids = {}
    local seen_names = {}
    local banks = {}
    
    for _, b in ipairs(raw_banks) do
        local is_dup = false
        if b.id and b.id ~= "" then
            if seen_ids[b.id] then is_dup = true else seen_ids[b.id] = true end
        end
        local full_name_key = (b.group or "") .. "///" .. (b.name or "")
        if seen_names[full_name_key] then
            is_dup = true
        else
            seen_names[full_name_key] = true
        end
        if not is_dup then
            table.insert(banks, b)
        end
    end
    
    -- Lookup maps for clones (from both raw_banks and deduplicated banks)
    local by_path = {}
    local by_id = {}
    local by_name = {}
    local function register_lookup(list)
        for _, b in ipairs(list) do
            if b.group and b.group ~= "" and b.name and b.name ~= "" then
                local p = b.group .. "/" .. b.name
                by_path[p] = by_path[p] or b
            end
            if b.id and b.id ~= "" then
                by_id[b.id] = by_id[b.id] or b
            end
            if b.name and b.name ~= "" then
                by_name[b.name] = by_name[b.name] or b
            end
        end
    end
    register_lookup(raw_banks)
    register_lookup(banks)
    
    -- Resolve clones (multi-pass for potential clone chains)
    for pass = 1, 5 do
        local any_resolved = false
        for _, b in ipairs(banks) do
            if b.clone_target and #b.articulations == 0 then
                local tgt = b.clone_target:gsub('^"', ''):gsub('"$', '')
                local src = by_id[tgt] or by_path[tgt] or by_name[tgt]
                if src and #src.articulations > 0 then
                    for _, a in ipairs(src.articulations) do
                        table.insert(b.articulations, {
                            pc = a.pc,
                            name = a.name,
                            category = a.category,
                            icon = a.icon
                        })
                    end
                    any_resolved = true
                end
            end
        end
        if not any_resolved then break end
    end
    
    -- Sort: Vendor, Library, Section, Name
    table.sort(banks, function(a, b)
        local av = (a.vendor or a.library or ""):lower()
        local bv = (b.vendor or b.library or ""):lower()
        if av ~= bv then return av < bv end
        local al = (a.library or ""):lower()
        local bl = (b.library or ""):lower()
        if al ~= bl then return al < bl end
        local as = (a.section or ""):lower()
        local bs = (b.section or ""):lower()
        if as ~= bs then return as < bs end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    
    return banks
end

function ReaticulateParser.reload_all_banks(state)
    _cached_banks = ReaticulateParser._load_banks_from_disk(state)
    return _cached_banks
end

function ReaticulateParser.get_all_banks(force_reload, state)
    if force_reload or not _cached_banks then
        _cached_banks = ReaticulateParser._load_banks_from_disk(state)
    end
    return _cached_banks
end

function ReaticulateParser.find_bank(banks, name_or_guid)
    if not banks then return nil end
    for _, b in ipairs(banks) do
        if b.name == name_or_guid or b.id == name_or_guid then
            return b
        end
    end
    return nil
end

function ReaticulateParser.format_category(raw_cat)
    if not raw_cat then return "OTHER" end
    local c = raw_cat:lower()
    if c:find("legato") then return "LEGATO"
    elseif c:find("long") then return "LONG / SUSTAIN"
    elseif c:find("short") or c:find("stacc") or c:find("spicc") or c:find("pizz") then return "SHORT / STACCATO"
    elseif c:find("trill") or c:find("trem") then return "TRILLS / TREMOLO"
    elseif c:find("fx") or c:find("rip") or c:find("fall") then return "EFFECTS / FX"
    else return "OTHER" end
end

function ReaticulateParser.get_art_display_name(bank, pc, all_banks)
    if bank and bank.articulations then
        for _, a in ipairs(bank.articulations) do
            if a.pc == pc then
                local clean = a.name:gsub("(%a)([%w_']*)", function(first, rest)
                    return first:upper() .. rest:lower()
                end)
                return clean
            end
        end
    end
    -- Fallback: Search all known banks for this PC
    if all_banks then
        for _, b in ipairs(all_banks) do
            if b.articulations then
                for _, a in ipairs(b.articulations) do
                    if a.pc == pc then
                        local clean = a.name:gsub("(%a)([%w_']*)", function(first, rest)
                            return first:upper() .. rest:lower()
                        end)
                        return clean
                    end
                end
            end
        end
    end
    return "PC " .. tostring(pc)
end

function ReaticulateParser.get_track_assigned_banks(track, all_banks)
    local assigned = {}
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then return assigned end
    all_banks = all_banks or ReaticulateParser.get_all_banks()
    
    local ok, data = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:reaticulate", "", false)
    if ok and data and #data > 1 then
        local json_str = (data:sub(1, 1) == "2") and data:sub(2) or data
        local JsonHelper = package.loaded["services.json_helper"] or require("services.json_helper")
        local ok_dec, decoded = pcall(JsonHelper.decode, json_str)
        if ok_dec and type(decoded) == "table" and type(decoded.banks) == "table" then
            for _, binfo in ipairs(decoded.banks) do
                local found = nil
                -- 1. By GUID
                if binfo.v and type(binfo.v) == "string" and #binfo.v > 3 then
                    for _, b in ipairs(all_banks) do
                        if b.id == binfo.v then found = b break end
                    end
                end
                -- 2. By Name
                if not found and binfo.name and binfo.name ~= "" then
                    for _, b in ipairs(all_banks) do
                        if b.name == binfo.name then found = b break end
                    end
                end
                -- 3. By MSB/LSB integer
                if not found and tonumber(binfo.v) then
                    local msblsb = tonumber(binfo.v)
                    for _, b in ipairs(all_banks) do
                        if b.msb >= 0 and b.lsb >= 0 and (b.msb * 128 + b.lsb) == msblsb then
                            found = b break
                        end
                    end
                end
                if found then
                    table.insert(assigned, found)
                elseif binfo.name and binfo.name ~= "" then
                    table.insert(assigned, {
                        name = binfo.name,
                        vendor = "Reaticulate",
                        library = "Track Assigned",
                        section = "Active",
                        id = tostring(binfo.v or ""),
                        articulations = {}
                    })
                end
            end
        end
        
        -- Fallback regex
        if #assigned == 0 then
            for name in data:gmatch('"name"%s*:%s*"([^"]+)"') do
                for _, b in ipairs(all_banks) do
                    if b.name == name then
                        table.insert(assigned, b)
                        break
                    end
                end
            end
            for guid in data:gmatch('"v"%s*:%s*"([%w%-]+)"') do
                for _, b in ipairs(all_banks) do
                    if b.id == guid then
                        local exists = false
                        for _, ab in ipairs(assigned) do if ab == b then exists = true break end end
                        if not exists then table.insert(assigned, b) end
                    end
                end
            end
        end
    end
    
    return assigned
end

function ReaticulateParser.get_bank_for_track(track, banks, override_or_msb, opt_lsb, opt_art_msb, opt_art_lsb)
    banks = banks or ReaticulateParser.get_all_banks()
    if not banks or #banks == 0 then return nil end
    
    local override_val = nil
    local art_msb = nil
    local art_lsb = nil
    
    if type(override_or_msb) == "string" then
        override_val = override_or_msb
        art_msb = type(opt_lsb) == "number" and opt_lsb or opt_art_msb
        art_lsb = type(opt_art_msb) == "number" and opt_art_msb or opt_art_lsb
    elseif type(override_or_msb) == "number" then
        art_msb = override_or_msb
        art_lsb = opt_lsb
    end
    
    -- 0. Override ID or Name
    if override_val and override_val ~= "" then
        for _, b in ipairs(banks) do
            if b.id == override_val or b.name == override_val then
                return b
            end
        end
    end
    
    -- 1. Exact MSB/LSB if passed
    if art_msb and art_msb >= 0 and art_lsb and art_lsb >= 0 then
        for _, b in ipairs(banks) do
            if b.msb == art_msb and b.lsb == art_lsb then
                return b
            end
        end
    end
    
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return banks[1]
    end
    
    -- 2. Check track assigned banks from Reaticulate
    local assigned = ReaticulateParser.get_track_assigned_banks(track, banks)
    if #assigned > 0 then
        return assigned[1]
    end
    
    -- 3. Fallback: Word-Token Match with Track Name
    local _, trk_name = reaper.GetTrackName(track)
    if trk_name and trk_name ~= "" then
        local lower_trk = trk_name:lower()
        -- Exact substring
        for _, b in ipairs(banks) do
            local lower_b = b.name:lower()
            if lower_trk:find(lower_b, 1, true) or lower_b:find(lower_trk, 1, true) then
                return b
            end
        end
        -- Word tokens
        for word in lower_trk:gmatch("%a+") do
            if #word >= 3 and word ~= "midi" and word ~= "track" and word ~= "spur" then
                for _, b in ipairs(banks) do
                    local lower_b = b.name:lower()
                    if lower_b:find(word, 1, true) then
                        return b
                    end
                end
            end
        end
    end
    
    return banks[1]
end

return ReaticulateParser

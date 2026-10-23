local PathService = require("services.path_service")

local ReaticulateParser = {}
local _cached_banks = nil

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
    
    for raw_line in f:lines() do
        local line = raw_line:gsub("^%s+", ""):gsub("%s+$", "")
        
        -- Parse Group and Name: //! g="Group" n="Name" (order-independent)
        if line:match("^//!") then
            local g_only = line:match('g="([^"]+)"')
            if g_only then pending_group = g_only end
            local n_only = line:match('n="([^"]+)"')
            if n_only then pending_name = n_only end
        end
        
        -- Parse Clone: //! clone="Target" or //! clone=Target
        local clone = line:match('//!.*clone="([^"]+)"') or line:match('//!.*clone=([%S]+)')
        if clone then
            pending_clone = clone:gsub('^"', ''):gsub('"$', '')
        end
        
        -- Parse ID: //! id="UUID" or //! id=UUID
        local id = line:match('//!.*id="([^"]+)"') or line:match('//!.*id=([%w%-]+)')
        if id then
            pending_id = id
        end
        
        -- Parse Bank: Bank MSB LSB Name
        if line:match("^Bank%s+") then
            local b_msb, b_lsb, b_name = line:match("^Bank%s+([^%s]+)%s+([^%s]+)%s+(.*)")
            if b_name then
                b_name = b_name:gsub("^%s+", ""):gsub("%s+$", "")
                local s_name = (pending_name and pending_name ~= "") and pending_name or b_name
                local ven, lib, sec = ReaticulateParser.extract_vendor_library_section(pending_group)
                current_bank = {
                    msb = (b_msb == "*") and -1 or tonumber(b_msb),
                    lsb = (b_lsb == "*") and -1 or tonumber(b_lsb),
                    name = b_name,
                    shortname = s_name,
                    group = pending_group,
                    vendor = ven,
                    library = lib,
                    section = sec,
                    id = pending_id,
                    clone_target = pending_clone,
                    articulations = {}
                }
                table.insert(banks_dict, current_bank)
                pending_name = ""
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
    ReaticulateParser.resolve_clones(banks_dict, banks_dict)
    return true
end

function ReaticulateParser.resolve_clones(banks, raw_banks)
    if not banks or #banks == 0 then return end
    local by_path = {}
    local by_id = {}
    local by_name = {}
    local function register_lookup(list)
        if not list then return end
        for _, b in ipairs(list) do
            if b.group and b.group ~= "" then
                if b.shortname and b.shortname ~= "" then
                    local ps = b.group .. "/" .. b.shortname
                    if not by_path[ps] or (#by_path[ps].articulations == 0 and #b.articulations > 0) then
                        by_path[ps] = b
                    end
                end
                if b.name and b.name ~= "" then
                    local pn = b.group .. "/" .. b.name
                    if not by_path[pn] or (#by_path[pn].articulations == 0 and #b.articulations > 0) then
                        by_path[pn] = b
                    end
                end
            end
            if b.id and b.id ~= "" then
                if not by_id[b.id] or (#by_id[b.id].articulations == 0 and #b.articulations > 0) then
                    by_id[b.id] = b
                end
            end
            if b.shortname and b.shortname ~= "" then
                if not by_name[b.shortname] or (#by_name[b.shortname].articulations == 0 and #b.articulations > 0) then
                    by_name[b.shortname] = b
                end
            end
            if b.name and b.name ~= "" then
                if not by_name[b.name] or (#by_name[b.name].articulations == 0 and #b.articulations > 0) then
                    by_name[b.name] = b
                end
            end
        end
    end
    register_lookup(raw_banks)
    register_lookup(banks)
    
    local all_candidates = raw_banks or banks
    for pass = 1, 5 do
        local any_resolved = false
        for _, b in ipairs(banks) do
            if b.clone_target and #b.articulations == 0 then
                local tgt = b.clone_target:gsub('^"', ''):gsub('"$', '')
                local src = by_id[tgt] or by_path[tgt] or by_name[tgt]
                if not src then
                    -- Fallback: prefix match within the same group (e.g. "CWC - Piccolo" -> "CWC - Piccolo Flute")
                    local tgt_grp, tgt_leaf = tgt:match("^(.+)/([^/]+)$")
                    local leaf_low = (tgt_leaf or tgt):lower()
                    for _, cand in ipairs(all_candidates) do
                        if cand ~= b and #cand.articulations > 0 then
                            local same_grp = (not tgt_grp) or (cand.group == tgt_grp)
                            if same_grp then
                                local cs = (cand.shortname or ""):lower()
                                local cn = (cand.name or ""):lower()
                                if (cs ~= "" and cs:find(leaf_low, 1, true) == 1) or (cn ~= "" and cn:find(leaf_low, 1, true) == 1) then
                                    src = cand
                                    break
                                end
                            end
                        end
                    end
                end
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
    
    -- 5. Deduplicate by ID or group+shortname+name (user entry retains precedence)
    local seen_ids = {}
    local seen_paths = {}
    local seen_display_in_group = {}
    local banks = {}
    
    for _, b in ipairs(raw_banks) do
        local is_dup = false
        if b.id and b.id ~= "" then
            if seen_ids[b.id] then
                is_dup = true
            else
                seen_ids[b.id] = true
            end
        end
        local canonical_leaf = (b.shortname and b.shortname ~= "") and b.shortname or (b.name or "")
        local full_path_key = (b.group or "") .. "///" .. canonical_leaf
        if seen_paths[full_path_key] then
            if not b.id or b.id == "" then
                is_dup = true
            end
        else
            seen_paths[full_path_key] = true
        end
        if not is_dup then
            local disp_key = (b.group or "") .. "///" .. (b.name or "")
            if seen_display_in_group[disp_key] and b.shortname and b.shortname ~= "" and b.shortname ~= b.name then
                -- Disambiguate banks where the Bank line has a duplicate name typo (e.g. BBC Piccolo Flute having Bank * * BBC - Flute)
                b.name = b.shortname
                disp_key = (b.group or "") .. "///" .. b.name
            end
            seen_display_in_group[disp_key] = true
            table.insert(banks, b)
        end
    end
    
    -- 6. Resolve clones across all raw and deduplicated banks
    ReaticulateParser.resolve_clones(banks, raw_banks)
    
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
    
    ReaticulateParser.sync_project_msblsb(banks, state)
    
    return banks
end

-- Exact Reaticulate CRC64 implementation for deterministic MSB/LSB allocation
local _crc64_lut = {
    0x0000000000000000,0x42f0e1eba9ea3693,0x85e1c3d753d46d26,0xc711223cfa3e5bb5,
    0x493366450e42ecdf,0x0bc387aea7a8da4c,0xccd2a5925d9681f9,0x8e224479f47cb76a,
    0x9266cc8a1c85d9be,0xd0962d61b56fef2d,0x17870f5d4f51b498,0x5577eeb6e6bb820b,
    0xdb55aacf12c73561,0x99a54b24bb2d03f2,0x5eb4691841135847,0x1c4488f3e8f96ed4,
    0x663d78ff90e185ef,0x24cd9914390bb37c,0xe3dcbb28c335e8c9,0xa12c5ac36adfde5a,
    0x2f0e1eba9ea36930,0x6dfeff5137495fa3,0xaaefdd6dcd770416,0xe81f3c86649d3285,
    0xf45bb4758c645c51,0xb6ab559e258e6ac2,0x71ba77a2dfb03177,0x334a9649765a07e4,
    0xbd68d2308226b08e,0xff9833db2bcc861d,0x388911e7d1f2dda8,0x7a79f00c7818eb3b,
    0xcc7af1ff21c30bde,0x8e8a101488293d4d,0x499b3228721766f8,0x0b6bd3c3dbfd506b,
    0x854997ba2f81e701,0xc7b97651866bd192,0x00a8546d7c558a27,0x4258b586d5bfbcb4,
    0x5e1c3d753d46d260,0x1cecdc9e94ace4f3,0xdbfdfea26e92bf46,0x990d1f49c77889d5,
    0x172f5b3033043ebf,0x55dfbadb9aee082c,0x92ce98e760d05399,0xd03e790cc93a650a,
    0xaa478900b1228e31,0xe8b768eb18c8b8a2,0x2fa64ad7e2f6e317,0x6d56ab3c4b1cd584,
    0xe374ef45bf6062ee,0xa1840eae168a547d,0x66952c92ecb40fc8,0x2465cd79455e395b,
    0x3821458aada7578f,0x7ad1a461044d611c,0xbdc0865dfe733aa9,0xff3067b657990c3a,
    0x711223cfa3e5bb50,0x33e2c2240a0f8dc3,0xf4f3e018f031d676,0xb60301f359dbe0e5,
    0xda050215ea6c212f,0x98f5e3fe438617bc,0x5fe4c1c2b9b84c09,0x1d14202910527a9a,
    0x93366450e42ecdf0,0xd1c685bb4dc4fb63,0x16d7a787b7faa0d6,0x5427466c1e109645,
    0x4863ce9ff6e9f891,0x0a932f745f03ce02,0xcd820d48a53d95b7,0x8f72eca30cd7a324,
    0x0150a8daf8ab144e,0x43a04931514122dd,0x84b16b0dab7f7968,0xc6418ae602954ffb,
    0xbc387aea7a8da4c0,0xfec89b01d3679253,0x39d9b93d2959c9e6,0x7b2958d680b3ff75,
    0xf50b1caf74cf481f,0xb7fbfd44dd257e8c,0x70eadf78271b2539,0x321a3e938ef113aa,
    0x2e5eb66066087d7e,0x6cae578bcfe24bed,0xabbf75b735dc1058,0xe94f945c9c3626cb,
    0x676dd025684a91a1,0x259d31cec1a0a732,0xe28c13f23b9efc87,0xa07cf2199274ca14,
    0x167ff3eacbaf2af1,0x548f120162451c62,0x939e303d987b47d7,0xd16ed1d631917144,
    0x5f4c95afc5edc62e,0x1dbc74446c07f0bd,0xdaad56789639ab08,0x985db7933fd39d9b,
    0x84193f60d72af34f,0xc6e9de8b7ec0c5dc,0x01f8fcb784fe9e69,0x43081d5c2d14a8fa,
    0xcd2a5925d9681f90,0x8fdab8ce70822903,0x48cb9af28abc72b6,0x0a3b7b1923564425,
    0x70428b155b4eaf1e,0x32b26afef2a4998d,0xf5a348c2089ac238,0xb753a929a170f4ab,
    0x3971ed50550c43c1,0x7b810cbbfce67552,0xbc902e8706d82ee7,0xfe60cf6caf321874,
    0xe224479f47cb76a0,0xa0d4a674ee214033,0x67c58448141f1b86,0x253565a3bdf52d15,
    0xab1721da49899a7f,0xe9e7c031e063acec,0x2ef6e20d1a5df759,0x6c0603e6b3b7c1ca,
    0xf6fae5c07d3274cd,0xb40a042bd4d8425e,0x731b26172ee619eb,0x31ebc7fc870c2f78,
    0xbfc9838573709812,0xfd39626eda9aae81,0x3a28405220a4f534,0x78d8a1b9894ec3a7,
    0x649c294a61b7ad73,0x266cc8a1c85d9be0,0xe17dea9d3263c055,0xa38d0b769b89f6c6,
    0x2daf4f0f6ff541ac,0x6f5faee4c61f773f,0xa84e8cd83c212c8a,0xeabe6d3395cb1a19,
    0x90c79d3fedd3f122,0xd2377cd44439c7b1,0x15265ee8be079c04,0x57d6bf0317edaa97,
    0xd9f4fb7ae3911dfd,0x9b041a914a7b2b6e,0x5c1538adb04570db,0x1ee5d94619af4648,
    0x02a151b5f156289c,0x4051b05e58bc1e0f,0x87409262a28245ba,0xc5b073890b687329,
    0x4b9237f0ff14c443,0x0962d61b56fef2d0,0xce73f427acc0a965,0x8c8315cc052a9ff6,
    0x3a80143f5cf17f13,0x7870f5d4f51b4980,0xbf61d7e80f251235,0xfd913603a6cf24a6,
    0x73b3727a52b393cc,0x31439391fb59a55f,0xf652b1ad0167feea,0xb4a25046a88dc879,
    0xa8e6d8b54074a6ad,0xea16395ee99e903e,0x2d071b6213a0cb8b,0x6ff7fa89ba4afd18,
    0xe1d5bef04e364a72,0xa3255f1be7dc7ce1,0x64347d271de22754,0x26c49cccb40811c7,
    0x5cbd6cc0cc10fafc,0x1e4d8d2b65facc6f,0xd95caf179fc497da,0x9bac4efc362ea149,
    0x158e0a85c2521623,0x577eeb6e6bb820b0,0x906fc95291867b05,0xd29f28b9386c4d96,
    0xcedba04ad0952342,0x8c2b41a1797f15d1,0x4b3a639d83414e64,0x09ca82762aab78f7,
    0x87e8c60fded7cf9d,0xc51827e4773df90e,0x020905d88d03a2bb,0x40f9e43324e99428,
    0x2cffe7d5975e55e2,0x6e0f063e3eb46371,0xa91e2402c48a38c4,0xebeec5e96d600e57,
    0x65cc8190991cb93d,0x273c607b30f68fae,0xe02d4247cac8d41b,0xa2dda3ac6322e288,
    0xbe992b5f8bdb8c5c,0xfc69cab42231bacf,0x3b78e888d80fe17a,0x7988096371e5d7e9,
    0xf7aa4d1a85996083,0xb55aacf12c735610,0x724b8ecdd64d0da5,0x30bb6f267fa73b36,
    0x4ac29f2a07bfd00d,0x08327ec1ae55e69e,0xcf235cfd546bbd2b,0x8dd3bd16fd818bb8,
    0x03f1f96f09fd3cd2,0x41011884a0170a41,0x86103ab85a2951f4,0xc4e0db53f3c36767,
    0xd8a453a01b3a09b3,0x9a54b24bb2d03f20,0x5d45907748ee6495,0x1fb5719ce1045206,
    0x919735e51578e56c,0xd367d40ebc92d3ff,0x1476f63246ac884a,0x568617d9ef46bed9,
    0xe085162ab69d5e3c,0xa275f7c11f7768af,0x6564d5fde549331a,0x279434164ca30589,
    0xa9b6706fb8dfb2e3,0xeb46918411358470,0x2c57b3b8eb0bdfc5,0x6ea7525342e1e956,
    0x72e3daa0aa188782,0x30133b4b03f2b111,0xf7021977f9cceaa4,0xb5f2f89c5026dc37,
    0x3bd0bce5a45a6b5d,0x79205d0e0db05dce,0xbe317f32f78e067b,0xfcc19ed95e6430e8,
    0x86b86ed5267cdbd3,0xc4488f3e8f96ed40,0x0359ad0275a8b6f5,0x41a94ce9dc428066,
    0xcf8b0890283e370c,0x8d7be97b81d4019f,0x4a6acb477bea5a2a,0x089a2aacd2006cb9,
    0x14dea25f3af9026d,0x562e43b4931334fe,0x913f6188692d6f4b,0xd3cf8063c0c759d8,
    0x5dedc41a34bbeeb2,0x1f1d25f19d51d821,0xd80c07cd676f8394,0x9afce626ce85b507
}

local function compute_crc64(s)
    local crc = 0xfffffffffffffff
    for i = 1, #s do
        local byte = string.byte(s, i)
        local t = ((crc >> 56) ~ byte) & 0xff
        crc = (_crc64_lut[t + 1] ~ (crc << 8))
    end
    return crc
end

local function json_escape_str(s)
    s = tostring(s or "")
    s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. s .. '"'
end

local function encode_project_state_json(pstate)
    local msb_parts = {}
    if pstate and type(pstate.msblsb_by_guid) == "table" then
        for k, v in pairs(pstate.msblsb_by_guid) do
            if type(k) == "string" and tonumber(v) then
                table.insert(msb_parts, json_escape_str(k) .. ":" .. tostring(math.floor(tonumber(v))))
            end
        end
    end
    local gc_str = (pstate and pstate.gc_ok == false) and "false" or "true"
    return string.format('{"msblsb_by_guid":{%s},"gc_ok":%s}', table.concat(msb_parts, ","), gc_str)
end

local function encode_track_appdata_json(appdata)
    local bank_parts = {}
    if appdata and type(appdata.banks) == "table" then
        for _, b in ipairs(appdata.banks) do
            if type(b) == "table" and b.v ~= nil then
                local fields = {}
                table.insert(fields, '"t":' .. json_escape_str(b.t or "g"))
                if type(b.v) == "number" then
                    table.insert(fields, '"v":' .. tostring(math.floor(b.v)))
                else
                    table.insert(fields, '"v":' .. json_escape_str(b.v))
                end
                table.insert(fields, '"src":' .. tostring(math.floor(tonumber(b.src) or 17)))
                table.insert(fields, '"dst":' .. tostring(math.floor(tonumber(b.dst) or 17)))
                table.insert(fields, '"dstbus":' .. tostring(math.floor(tonumber(b.dstbus) or 1)))
                if b.name and b.name ~= "" then
                    table.insert(fields, '"name":' .. json_escape_str(b.name))
                end
                if b.h ~= nil then
                    if type(b.h) == "number" then
                        table.insert(fields, '"h":' .. tostring(math.floor(b.h)))
                    elseif type(b.h) == "string" then
                        table.insert(fields, '"h":' .. json_escape_str(b.h))
                    end
                end
                table.insert(bank_parts, "{" .. table.concat(fields, ",") .. "}")
            end
        end
    end
    local v_num = (appdata and tonumber(appdata.v)) or 1
    local extra = ""
    if appdata and tonumber(appdata.defchan) then
        extra = extra .. ',"defchan":' .. tostring(math.floor(tonumber(appdata.defchan)))
    end
    return string.format('{"v":%d,"banks":[%s]%s}', v_num, table.concat(bank_parts, ","), extra)
end

function ReaticulateParser.sync_project_msblsb(banks, state)
    banks = banks or _cached_banks
    if not banks or #banks == 0 then return end
    
    local JsonHelper = package.loaded["services.json_helper"] or require("services.json_helper")
    local ok_p, pdata = reaper.GetProjExtState(0, "reaticulate", "state")
    local msblsb_by_guid = nil
    if ok_p == 1 and pdata and pdata ~= "" then
        local ok_dec, decoded = pcall(JsonHelper.decode, pdata)
        if ok_dec and type(decoded) == "table" and type(decoded.msblsb_by_guid) == "table" then
            msblsb_by_guid = decoded.msblsb_by_guid
        end
    end
    
    if msblsb_by_guid then
        for _, b in ipairs(banks) do
            if b.id and b.id ~= "" and msblsb_by_guid[b.id] then
                local msblsb = tonumber(msblsb_by_guid[b.id])
                if msblsb and msblsb >= 0 then
                    b.msb = (msblsb >> 8) & 0x7F
                    b.lsb = msblsb & 0x7F
                end
            end
        end
    end
    
    -- Fallback: Scan generated Data/Reaticulate-tmp*.reabank for Bank MSB LSB Name definitions
    local data_dir = PathService.get_reabank_dir(state)
    if data_dir and reaper.APIExists("EnumerateFiles") then
        local idx = 0
        while true do
            local fname = reaper.EnumerateFiles(data_dir, idx)
            if not fname or fname == "" then break end
            if fname:lower():match("^reaticulate%-tmp.*%.reabank$") then
                local f = io.open(data_dir .. "/" .. fname, "r")
                if f then
                    for raw_line in f:lines() do
                        local b_msb, b_lsb, b_name = raw_line:match("^%s*Bank%s+(%d+)%s+(%d+)%s+(.-)%s*$")
                        if b_msb and b_lsb and b_name then
                            local msb_n, lsb_n = tonumber(b_msb), tonumber(b_lsb)
                            for _, b in ipairs(banks) do
                                if b.name == b_name and (not b.msb or b.msb < 0 or not b.lsb or b.lsb < 0) then
                                    b.msb = msb_n
                                    b.lsb = lsb_n
                                end
                            end
                        end
                    end
                    f:close()
                end
            end
            idx = idx + 1
        end
    end
end

function ReaticulateParser.resolve_or_assign_bank_msblsb(bank, state)
    if not bank then return -1, -1 end
    local JsonHelper = package.loaded["services.json_helper"] or require("services.json_helper")
    local ok_p, pdata = reaper.GetProjExtState(0, "reaticulate", "state")
    local pstate = { msblsb_by_guid = {}, gc_ok = true }
    if ok_p == 1 and pdata and pdata ~= "" then
        local ok_dec, decoded = pcall(JsonHelper.decode, pdata)
        if ok_dec and type(decoded) == "table" then
            pstate = decoded
            if type(pstate.msblsb_by_guid) ~= "table" then
                pstate.msblsb_by_guid = {}
            end
        end
    end
    
    local guid = bank.id
    if guid and guid ~= "" then
        local existing = tonumber(pstate.msblsb_by_guid[guid])
        if existing and existing > 0 then
            bank.msb = (existing >> 8) & 0x7F
            bank.lsb = existing & 0x7F
            return bank.msb, bank.lsb
        end
        
        local msb, lsb
        if bank.msb and bank.msb >= 0 and bank.lsb and bank.lsb >= 0 then
            msb = bank.msb
            lsb = bank.lsb
        else
            local crc = compute_crc64(guid)
            msb = (crc >> 32) % 64
            lsb = (crc & 0xffffffff) % 128
            if msb == 0 and lsb == 0 then lsb = 1 end
        end
        
        local candidate = (msb << 8) | lsb
        for _ = 0, 16000 do
            local conflict = false
            for g, val in pairs(pstate.msblsb_by_guid) do
                if tonumber(val) == candidate and g ~= guid then
                    conflict = true
                    break
                end
            end
            if not conflict and (candidate & 0xff) ~= 0 and (candidate >> 8) > 0 then
                pstate.msblsb_by_guid[guid] = candidate
                break
            end
            candidate = candidate + 1
            if candidate >= (64 << 8) then
                candidate = (1 << 8) | 1
            elseif (candidate & 0xff) == 0 then
                candidate = candidate + 1
            end
        end
        
        pstate.msblsb_by_guid[guid] = candidate
        bank.msb = (candidate >> 8) & 0x7F
        bank.lsb = candidate & 0x7F
        reaper.SetProjExtState(0, "reaticulate", "state", encode_project_state_json(pstate))
        return bank.msb, bank.lsb
    end
    
    return bank.msb or 0, bank.lsb or 1
end

function ReaticulateParser.trigger_reaticulate_sync(track, state, expected_encoded, expected_v_str)
    -- 1. Bump Reaticulate's project change_cookie so Reaticulate reloads project state & track P_EXT:reaticulate
    local cookie = string.format("notator_%d_%d", os.time(), math.floor((reaper.time_precise() * 1000) % 100000))
    reaper.SetProjExtState(0, "reaticulate", "change_cookie", cookie)
    
    -- 2. Select track if needed so Reaticulate's rfx.current:sync(track) targets this track immediately
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        if not reaper.IsTrackSelected(track) then
            reaper.SetOnlyTrackSelected(track)
        end
        if reaper.APIExists("CSurf_OnTrackSelection") then
            reaper.CSurf_OnTrackSelection(track)
        end
    end
    
    -- 3. Ping Reaticulate_Main and auto-launch it if not running; also re-bump change_cookie once JSFX gmem_index is ready
    local now_str = tostring(os.clock())
    reaper.SetExtState("reaticulate", "command", "ping=" .. now_str, false)
    
    local ticks = 0
    local start_poll_t = reaper.time_precise()
    local last_cookie_bump_t = start_poll_t
    local launched_main = false
    local function poll_reaticulate_sync()
        ticks = ticks + 1
        local cur_t = reaper.time_precise()
        local elapsed_s = cur_t - start_poll_t
        local pong = reaper.GetExtState("reaticulate", "pong")
        local is_running = (pong and pong ~= "" and tonumber(pong) and tonumber(pong) >= tonumber(now_str))
        
        if not is_running and elapsed_s >= 0.05 and not launched_main then
            launched_main = true
            local cmd = reaper.GetExtState("reaticulate", "main_command_id")
            local cmd_id = cmd and tonumber(cmd)
            if not cmd_id or cmd_id == 0 or not reaper.ReverseNamedCommandLookup(cmd_id) then
                local script_dir = PathService.get_reaticulate_dir(state)
                if script_dir then
                    local main_lua = script_dir .. "/actions/Reaticulate_Main.lua"
                    if reaper.file_exists(main_lua) then
                        cmd_id = reaper.AddRemoveReaScript(true, 0, main_lua, true)
                    end
                end
                if not cmd_id or cmd_id == 0 then
                    cmd_id = reaper.NamedCommandLookup("_RSbe259504561f6a52557d2d1c64e52ef13527bf17")
                end
            end
            if cmd_id and cmd_id > 0 then
                reaper.Main_OnCommandEx(cmd_id, 0, 0)
            end
        end
        
        if track and reaper.ValidatePtr(track, "MediaTrack*") then
            local ok_ext, ext_data = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:reaticulate", "", false)
            local has_expected_bank = (not expected_v_str) or (ok_ext and ext_data and ext_data:find(expected_v_str, 1, true) ~= nil)
            if expected_encoded and not has_expected_bank then
                -- Reaticulate's rfx.gc() overwrote P_EXT:reaticulate with stale uncommitted UI state; restore our bank!
                reaper.GetSetMediaTrackInfo_String(track, "P_EXT:reaticulate", expected_encoded, true)
                local c_restore = string.format("notator_restore_%d_%d", os.time(), math.floor((cur_t * 1000) % 100000) + ticks)
                reaper.SetProjExtState(0, "reaticulate", "change_cookie", c_restore)
                last_cookie_bump_t = cur_t
            else
                local has_compiled_hash = ok_ext and ext_data and ext_data:find('"h"%s*:') ~= nil
                if has_compiled_hash and has_expected_bank then
                    return -- Reaticulate has compiled opcodes into Reaticulate.jsfx!
                end
                if (cur_t - last_cookie_bump_t) >= 0.10 then
                    last_cookie_bump_t = cur_t
                    local c2 = string.format("notator_%d_%d", os.time(), math.floor((cur_t * 1000) % 100000) + ticks)
                    reaper.SetProjExtState(0, "reaticulate", "change_cookie", c2)
                end
            end
        end
        
        if elapsed_s < 0.50 then
            reaper.defer(poll_reaticulate_sync)
        end
    end
    reaper.defer(poll_reaticulate_sync)
end

function ReaticulateParser.ensure_track_reaticulate_fx_and_bank(track, bank, state, replace_primary)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return false, "Invalid track"
    end
    
    reaper.PreventUIRefresh(1)
    
    -- 1. Check if Reaticulate.jsfx is loaded on the track, and ensure it sits at FX slot 0 (before the instrument)
    local fx_count = reaper.TrackFX_GetCount(track)
    local reaticulate_fx_idx = -1
    for i = 0, fx_count - 1 do
        local ok_n, fx_name = reaper.TrackFX_GetFXName(track, i, "")
        if ok_n and fx_name then
            local low_n = fx_name:lower()
            if low_n:find("reaticulate", 1, true) and not low_n:find("feedback translate", 1, true) then
                reaticulate_fx_idx = i
                break
            end
        end
    end
    
    local fx_added_or_moved = false
    if reaticulate_fx_idx == -1 then
        reaticulate_fx_idx = reaper.TrackFX_AddByName(track, "JS:Reaticulate", false, -1000)
        if reaticulate_fx_idx == -1 then
            reaticulate_fx_idx = reaper.TrackFX_AddByName(track, "Reaticulate.jsfx", false, -1000)
        end
        if reaticulate_fx_idx == -1 then
            reaticulate_fx_idx = reaper.TrackFX_AddByName(track, "Reaticulate", false, -1000)
        end
        if reaticulate_fx_idx >= 0 then
            reaper.TrackFX_Show(track, reaticulate_fx_idx, 2) -- hide floating window if auto-opened
            fx_added_or_moved = true
        end
    end
    
    if reaticulate_fx_idx > 0 then
        reaper.TrackFX_CopyToTrack(track, reaticulate_fx_idx, track, 0, true)
        reaticulate_fx_idx = 0
        fx_added_or_moved = true
    end
    
    if reaticulate_fx_idx >= 0 then
        if reaper.GetMediaTrackInfo_Value(track, "I_FXEN") ~= 1 then
            reaper.SetMediaTrackInfo_Value(track, "I_FXEN", 1)
        end
        if not reaper.TrackFX_GetEnabled(track, reaticulate_fx_idx) then
            reaper.TrackFX_SetEnabled(track, reaticulate_fx_idx, true)
        end
    end
    
    -- 2. Resolve MSB/LSB and ensure the bank is written into P_EXT:reaticulate on the track
    local appdata_modified = false
    local last_encoded = nil
    local target_v_str = nil
    if bank then
        ReaticulateParser.resolve_or_assign_bank_msblsb(bank, state)
        
        local JsonHelper = package.loaded["services.json_helper"] or require("services.json_helper")
        local ok_ext, ext_data = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:reaticulate", "", false)
        local appdata = { v = 1, banks = {} }
        if ok_ext and ext_data and #ext_data > 1 then
            local json_str = (ext_data:sub(1, 1) == "2") and ext_data:sub(2) or ext_data
            local ok_dec, decoded = pcall(JsonHelper.decode, json_str)
            if ok_dec and type(decoded) == "table" then
                appdata = decoded
                if type(appdata.banks) ~= "table" then
                    appdata.banks = {}
                end
            end
        end
        
        local has_guid = (bank.id and bank.id ~= "")
        local target_v = has_guid and bank.id or (((bank.msb and bank.msb >= 0 and bank.msb or 0) << 8) + (bank.lsb and bank.lsb >= 0 and bank.lsb or 1))
        target_v_str = tostring(target_v)
        local new_entry = {
            t = has_guid and "g" or "b",
            v = target_v,
            src = 17,
            dst = 17,
            dstbus = 1,
            name = bank.name or "Bank"
        }
        
        local already_has_bank = false
        for _, binfo in ipairs(appdata.banks) do
            if (has_guid and binfo.v == bank.id) or (binfo.name and binfo.name == bank.name) then
                already_has_bank = true
                break
            end
        end
        local already_sole_primary = (
            #appdata.banks == 1 and (
                (has_guid and appdata.banks[1].v == bank.id) or
                (appdata.banks[1].name and appdata.banks[1].name == bank.name)
            )
        )
        
        if replace_primary or (not already_has_bank and not already_sole_primary) then
            -- Delete top bank (index 1) and any conflicting Omni (src == 17) or duplicate entries before loading the new bank at index 1
            local kept_banks = {}
            for idx, binfo in ipairs(appdata.banks) do
                local is_top = (idx == 1)
                local is_same = (has_guid and binfo.v == bank.id) or (binfo.name and binfo.name == bank.name)
                local is_omni = (not binfo.src or binfo.src == 17)
                if not is_top and not is_same and not is_omni then
                    table.insert(kept_banks, binfo)
                end
            end
            table.insert(kept_banks, 1, new_entry)
            appdata.banks = kept_banks
            appdata_modified = true
        elseif fx_added_or_moved or (appdata.banks[1] and not appdata.banks[1].h) then
            if appdata.banks[1] then
                appdata.banks[1].h = nil
            end
            appdata_modified = true
        end
        
        if appdata_modified or fx_added_or_moved then
            for _, binfo in ipairs(appdata.banks) do
                binfo.h = nil -- Force Reaticulate to re-compile opcodes into Reaticulate.jsfx
            end
            last_encoded = "2" .. encode_track_appdata_json(appdata)
            reaper.GetSetMediaTrackInfo_String(track, "P_EXT:reaticulate", last_encoded, true)
            reaper.MarkProjectDirty(0)
        end
        
        -- Automatically initialize or validate track slur behavior when bank is assigned
        local st_mod = package.loaded["state"]
        local eff_st = state or (st_mod and (st_mod._active_instance or st_mod))
        local tguid = reaper.GetTrackGUID(track)
        if tguid then
            local cur_beh = (eff_st and eff_st.track_slur_behavior and eff_st.track_slur_behavior[tguid]) or nil
            if not cur_beh or cur_beh == "" then
                local ok_ext, ext_beh = reaper.GetSetMediaTrackInfo_String(track, "P_EXT:notator_slur_behavior", "", false)
                if ok_ext and ext_beh and ext_beh ~= "" then
                    cur_beh = ext_beh
                end
            end
            local reset_to_auto = (not cur_beh or cur_beh == "")
            if cur_beh and cur_beh:match("^pc:(%d+)$") and bank.articulations then
                local req_pc = tonumber(cur_beh:match("^pc:(%d+)$"))
                local pc_exists = false
                for _, a in ipairs(bank.articulations) do
                    if a.pc == req_pc then pc_exists = true break end
                end
                if not pc_exists then reset_to_auto = true end
            end
            if reset_to_auto then
                cur_beh = "auto"
                reaper.GetSetMediaTrackInfo_String(track, "P_EXT:notator_slur_behavior", "auto", true)
            end
            if eff_st and eff_st.track_slur_behavior then
                eff_st.track_slur_behavior[tguid] = cur_beh
            end
        end
    end
    
    reaper.PreventUIRefresh(-1)
    
    if fx_added_or_moved or appdata_modified then
        ReaticulateParser.trigger_reaticulate_sync(track, state, last_encoded, target_v_str)
    end
    
    return reaticulate_fx_idx == 0, fx_added_or_moved
end

function ReaticulateParser.reload_all_banks(state)
    _cached_banks = ReaticulateParser._load_banks_from_disk(state)
    return _cached_banks
end

function ReaticulateParser.get_all_banks(force_reload, state)
    if force_reload or not _cached_banks then
        _cached_banks = ReaticulateParser._load_banks_from_disk(state)
    else
        ReaticulateParser.sync_project_msblsb(_cached_banks, state)
    end
    return _cached_banks
end

function ReaticulateParser.find_bank(banks, name_or_guid)
    if not banks then return nil end
    for _, b in ipairs(banks) do
        if b.name == name_or_guid or b.shortname == name_or_guid or b.id == name_or_guid then
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

function ReaticulateParser.categorize_articulation(art_or_cat, opt_name)
    local raw_cat = type(art_or_cat) == "table" and art_or_cat.category or art_or_cat
    local raw_name = type(art_or_cat) == "table" and art_or_cat.name or opt_name
    local cat = ReaticulateParser.format_category(raw_cat)
    if cat ~= "OTHER" then return cat end
    if raw_name then
        local nm = tostring(raw_name):lower()
        if nm:find("legato") or nm:find("slur") or nm:find("portamento") or nm:find("gliss") then
            return "LEGATO"
        elseif nm:find("stacc") or nm:find("spicc") or nm:find("pizz") or nm:find("marc") or nm:find("short") or nm:find("col legno") or nm:find("bartok") then
            return "SHORT / STACCATO"
        elseif nm:find("trill") or nm:find("trem") then
            return "TRILLS / TREMOLO"
        elseif nm:find("fx") or nm:find("rip") or nm:find("fall") or nm:find("cluster") then
            return "EFFECTS / FX"
        elseif nm:find("long") or nm:find("sustain") or nm:find("norm") or nm:find("ord") or nm:find("tenuto") or nm:find("flautando") or nm:find("harm") or nm:find("sord") or nm:find("vibrato") or nm:find("non%-vib") or nm:find("nv") or nm:find("pont") or nm:find("tasto") then
            return "LONG / SUSTAIN"
        end
    end
    return cat
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
                -- 2. By Name or Shortname
                if not found and binfo.name and binfo.name ~= "" then
                    for _, b in ipairs(all_banks) do
                        if b.name == binfo.name or b.shortname == binfo.name then found = b break end
                    end
                end
                -- 3. By MSB/LSB integer
                if not found and tonumber(binfo.v) then
                    local msblsb = tonumber(binfo.v)
                    for _, b in ipairs(all_banks) do
                        if b.msb >= 0 and b.lsb >= 0 and ((b.msb * 256 + b.lsb) == msblsb or (b.msb * 128 + b.lsb) == msblsb) then
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
                    if b.name == name or b.shortname == name then
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

local function finalize_resolved_bank(b)
    if b and (not b.msb or b.msb < 0 or not b.lsb or b.lsb < 0) then
        ReaticulateParser.resolve_or_assign_bank_msblsb(b)
    end
    return b
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
    elseif type(override_or_msb) == "table" and override_or_msb.track_articulation_banks and track and reaper.ValidatePtr(track, "MediaTrack*") then
        local tguid = reaper.GetTrackGUID(track)
        override_val = tguid and override_or_msb.track_articulation_banks[tguid]
    end
    
    -- Automatically consult state.track_articulation_banks if caller didn't pass an explicit override string
    if (not override_val or override_val == "") and track and reaper.ValidatePtr(track, "MediaTrack*") then
        local st_mod = package.loaded["state"]
        local st = st_mod and (st_mod._active_instance or st_mod)
        if st and st.track_articulation_banks then
            local tguid = reaper.GetTrackGUID(track)
            if tguid and st.track_articulation_banks[tguid] then
                override_val = st.track_articulation_banks[tguid]
            end
        end
    end
    
    -- 0. Override ID, Name, or Shortname
    if override_val and override_val ~= "" then
        for _, b in ipairs(banks) do
            if b.id == override_val or b.name == override_val or b.shortname == override_val then
                return finalize_resolved_bank(b)
            end
        end
    end
    
    -- 1. Exact MSB/LSB if passed
    if art_msb and art_msb >= 0 and art_lsb and art_lsb >= 0 then
        for _, b in ipairs(banks) do
            if b.msb == art_msb and b.lsb == art_lsb then
                return finalize_resolved_bank(b)
            end
        end
    end
    
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return finalize_resolved_bank(banks[1])
    end
    
    -- 2. Check track assigned banks from Reaticulate
    local assigned = ReaticulateParser.get_track_assigned_banks(track, banks)
    if #assigned > 0 then
        return finalize_resolved_bank(assigned[1])
    end
    
    -- 3. Fallback: Word-Token Match with Track Name
    local _, trk_name = reaper.GetTrackName(track)
    if trk_name and trk_name ~= "" then
        local lower_trk = trk_name:lower()
        -- Exact substring
        for _, b in ipairs(banks) do
            local lower_b = b.name:lower()
            local lower_s = (b.shortname or ""):lower()
            if lower_trk:find(lower_b, 1, true) or lower_b:find(lower_trk, 1, true)
                or (lower_s ~= "" and (lower_trk:find(lower_s, 1, true) or lower_s:find(lower_trk, 1, true))) then
                return finalize_resolved_bank(b)
            end
        end
        -- Word tokens
        for word in lower_trk:gmatch("%a+") do
            if #word >= 3 and word ~= "midi" and word ~= "track" and word ~= "spur" then
                for _, b in ipairs(banks) do
                    local lower_b = b.name:lower()
                    local lower_s = (b.shortname or ""):lower()
                    if lower_b:find(word, 1, true) or (lower_s ~= "" and lower_s:find(word, 1, true)) then
                        return finalize_resolved_bank(b)
                    end
                end
            end
        end
    end
    
    return nil
end

return ReaticulateParser


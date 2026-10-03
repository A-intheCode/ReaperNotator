-- ==============================================================================
-- REAPER Native Notator - Helper: JsonHelper
-- Lightweight, robust pure-Lua JSON parser and serializer
-- ==============================================================================

local JsonHelper = {}

-- ==============================================================================
-- JSON ENCODE
-- ==============================================================================
local function escape_str(s)
    local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
    local out_char = {'\\\\', '\\"', '\\/', '\\b', '\\f', '\\n', '\\r', '\\t'}
    for i, c in ipairs(in_char) do
        s = s:gsub(c, out_char[i])
    end
    return '"' .. s .. '"'
end

local function is_array(t)
    if type(t) ~= "table" then return false end
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    for i = 1, count do
        if t[i] == nil then return false end
    end
    return true
end

function JsonHelper.encode(val, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local pad_inner = string.rep("  ", indent + 1)
    
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "null" end -- NaN
        if val >= math.huge or val <= -math.huge then return "null" end
        return tostring(val)
    elseif t == "string" then
        return escape_str(val)
    elseif t == "table" then
        if is_array(val) then
            if #val == 0 then return "[]" end
            local parts = {}
            for _, item in ipairs(val) do
                table.insert(parts, pad_inner .. JsonHelper.encode(item, indent + 1))
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        else
            local count = 0
            for _ in pairs(val) do count = count + 1 end
            if count == 0 then return "{}" end
            local parts = {}
            for k, v in pairs(val) do
                local key_str = escape_str(tostring(k))
                table.insert(parts, pad_inner .. key_str .. ": " .. JsonHelper.encode(v, indent + 1))
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
        end
    end
    return "null"
end

-- ==============================================================================
-- JSON DECODE
-- ==============================================================================
local function skip_whitespace(str, idx)
    local len = #str
    while idx <= len do
        local b = str:byte(idx)
        if b == 32 or b == 9 or b == 10 or b == 13 then
            idx = idx + 1
        else
            break
        end
    end
    return idx
end

local parse_value

local function parse_string(str, idx)
    idx = idx + 1 -- skip opening quote
    local chars = {}
    local len = #str
    while idx <= len do
        local b = str:byte(idx)
        if b == 34 then -- closing quote '"'
            return table.concat(chars), idx + 1
        elseif b == 92 then -- escape '\'
            idx = idx + 1
            local esc = str:sub(idx, idx)
            if esc == '"' or esc == '\\' or esc == '/' then
                table.insert(chars, esc)
            elseif esc == 'b' then table.insert(chars, '\b')
            elseif esc == 'f' then table.insert(chars, '\f')
            elseif esc == 'n' then table.insert(chars, '\n')
            elseif esc == 'r' then table.insert(chars, '\r')
            elseif esc == 't' then table.insert(chars, '\t')
            elseif esc == 'u' then
                local hex = str:sub(idx + 1, idx + 4)
                idx = idx + 4
                local codepoint = tonumber(hex, 16) or 63
                if codepoint < 128 then
                    table.insert(chars, string.char(codepoint))
                else
                    table.insert(chars, "?")
                end
            else
                table.insert(chars, esc)
            end
            idx = idx + 1
        else
            table.insert(chars, string.char(b))
            idx = idx + 1
        end
    end
    return table.concat(chars), idx
end

local function parse_number(str, idx)
    local s, e = str:find("^%-?%d+%.?%d*[eE]?[+%-]?%d*", idx)
    if not s then return nil, idx end
    local num = tonumber(str:sub(s, e))
    return num, e + 1
end

local function parse_array(str, idx)
    idx = idx + 1 -- skip '['
    local arr = {}
    local len = #str
    while idx <= len do
        idx = skip_whitespace(str, idx)
        if str:byte(idx) == 93 then -- ']'
            return arr, idx + 1
        end
        local val
        val, idx = parse_value(str, idx)
        table.insert(arr, val)
        idx = skip_whitespace(str, idx)
        local b = str:byte(idx)
        if b == 44 then -- ','
            idx = idx + 1
        elseif b == 93 then -- ']'
            return arr, idx + 1
        end
    end
    return arr, idx
end

local function parse_object(str, idx)
    idx = idx + 1 -- skip '{'
    local obj = {}
    local len = #str
    while idx <= len do
        idx = skip_whitespace(str, idx)
        if str:byte(idx) == 125 then -- '}'
            return obj, idx + 1
        end
        local key
        if str:byte(idx) == 34 then
            key, idx = parse_string(str, idx)
        else
            return obj, idx
        end
        idx = skip_whitespace(str, idx)
        if str:byte(idx) == 58 then -- ':'
            idx = idx + 1
        end
        idx = skip_whitespace(str, idx)
        local val
        val, idx = parse_value(str, idx)
        obj[key] = val
        idx = skip_whitespace(str, idx)
        local b = str:byte(idx)
        if b == 44 then -- ','
            idx = idx + 1
        elseif b == 125 then -- '}'
            return obj, idx + 1
        end
    end
    return obj, idx
end

function parse_value(str, idx)
    idx = skip_whitespace(str, idx)
    local b = str:byte(idx)
    if not b then return nil, idx end
    if b == 34 then -- '"'
        return parse_string(str, idx)
    elseif b == 123 then -- '{'
        return parse_object(str, idx)
    elseif b == 91 then -- '['
        return parse_array(str, idx)
    elseif b == 116 and str:sub(idx, idx + 3) == "true" then -- 'true'
        return true, idx + 4
    elseif b == 102 and str:sub(idx, idx + 4) == "false" then -- 'false'
        return false, idx + 5
    elseif b == 110 and str:sub(idx, idx + 3) == "null" then -- 'null'
        return nil, idx + 4
    else
        return parse_number(str, idx)
    end
end

function JsonHelper.decode(json_str)
    if not json_str or type(json_str) ~= "string" then return nil end
    local val, _ = parse_value(json_str, 1)
    return val
end

return JsonHelper

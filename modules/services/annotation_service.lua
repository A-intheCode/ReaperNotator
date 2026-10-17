-- ==============================================================================
-- REAPER Native Notator - Module: AnnotationService
-- Per-Track Multi-Layer Freehand Annotation System with Per-Bar Transparent PNGs
-- ==============================================================================

local AnnotationService = {}

AnnotationService.TILE_W = 320
AnnotationService.TILE_H = 200
AnnotationService.MAX_TRACK_SPACING_REF = 320.0

-- 12 Curated High-Contrast Color Presets (0xRRGGBBFF)
AnnotationService.COLOR_PRESETS = {
    { name = "Crimson Red",    col = 0xE74C3CFF },
    { name = "Coral Orange",   col = 0xFF6B35FF },
    { name = "Amber Gold",     col = 0xF1C40FFF },
    { name = "Emerald Green",  col = 0x2ECC71FF },
    { name = "Teal Mint",      col = 0x1ABC9CFF },
    { name = "Sky Blue",       col = 0x3498DBFF },
    { name = "Cobalt Blue",    col = 0x2980B9FF },
    { name = "Royal Purple",   col = 0x9B59B6FF },
    { name = "Hot Magenta",    col = 0xE84393FF },
    { name = "Sienna Brown",   col = 0xD35400FF },
    { name = "Pure White",     col = 0xFFFFFFFF },
    { name = "Charcoal Black", col = 0x1E272EFF },
}

-- ==============================================================================
-- 1. FAST PURE-LUA RGBA PNG ENCODER & DECODER (Zero External Dependencies)
-- ==============================================================================

local crc_table = {}
for n = 0, 255 do
    local c = n
    for _ = 1, 8 do
        if (c & 1) ~= 0 then
            c = 0xEDB88320 ~ (c >> 1)
        else
            c = c >> 1
        end
    end
    crc_table[n] = c
end

local function crc32(data)
    local c = 0xFFFFFFFF
    for i = 1, #data do
        local b = string.byte(data, i)
        c = crc_table[(c ~ b) & 0xFF] ~ (c >> 8)
    end
    return c ~ 0xFFFFFFFF
end

local function make_png_chunk(chunk_type, data)
    local len_bytes = string.pack(">I4", #data)
    local type_and_data = chunk_type .. data
    local crc_bytes = string.pack(">I4", crc32(type_and_data))
    return len_bytes .. type_and_data .. crc_bytes
end

-- Encodes a flat pixel array (w * h integers in 0xRRGGBBAA format) into a valid RGBA PNG binary string
function AnnotationService.encode_rgba_png(pixels, w, h)
    local png_sig = "\137PNG\r\n\26\n"
    -- IHDR: width (4), height (4), bit_depth=8, color_type=6 (RGBA), compression=0, filter=0, interlace=0
    local ihdr_data = string.pack(">I4I4BBBBB", w, h, 8, 6, 0, 0, 0)
    local ihdr_chunk = make_png_chunk("IHDR", ihdr_data)

    -- Build raw scanlines (each row starts with filter byte 0x00 followed by w * 4 RGBA bytes)
    -- Simultaneously compute Adler-32 checksum over the uncompressed scanline stream
    local s1 = 1
    local s2 = 0
    local MOD_ADLER = 65521
    local rows = {}
    local row_Format = "B" .. string.rep(">I4", w)
    local idx = 1

    for y = 1, h do
        -- Update Adler-32 for filter byte 0
        s2 = (s2 + s1) % MOD_ADLER
        for x = 1, w do
            local px = pixels[idx] or 0
            idx = idx + 1
            local r = (px >> 24) & 0xFF
            local g = (px >> 16) & 0xFF
            local b = (px >> 8)  & 0xFF
            local a = px & 0xFF
            s1 = s1 + r; s2 = s2 + s1
            s1 = s1 + g; s2 = s2 + s1
            s1 = s1 + b; s2 = s2 + s1
            s1 = s1 + a; s2 = s2 + s1
        end
        s1 = s1 % MOD_ADLER
        s2 = s2 % MOD_ADLER

        local row_base = (y - 1) * w
        rows[y] = string.pack(row_Format, 0, table.unpack(pixels, row_base + 1, row_base + w))
    end

    local raw_data = table.concat(rows)
    local total_len = #raw_data

    -- Wrap in ZLIB stream with uncompressed DEFLATE blocks (max 65535 bytes per block)
    local deflate_parts = { "\x78\x01" } -- ZLIB header (CMF=0x78, FLG=0x01)
    local pos = 1
    local max_block = 65535
    while pos <= total_len do
        local rem = total_len - pos + 1
        local blk_len = math.min(max_block, rem)
        local is_final = (pos + blk_len > total_len) and 1 or 0
        local nlen = (~blk_len) & 0xFFFF
        table.insert(deflate_parts, string.pack("<BI2I2", is_final, blk_len, nlen))
        table.insert(deflate_parts, string.sub(raw_data, pos, pos + blk_len - 1))
        pos = pos + blk_len
    end

    local adler32 = (s2 << 16) | s1
    table.insert(deflate_parts, string.pack(">I4", adler32))
    local idat_chunk = make_png_chunk("IDAT", table.concat(deflate_parts))
    local iend_chunk = make_png_chunk("IEND", "")

    return png_sig .. ihdr_chunk .. idat_chunk .. iend_chunk
end

-- Decodes an RGBA PNG file created by encode_rgba_png back into a flat pixel array (0xRRGGBBAA)
function AnnotationService.decode_rgba_png(png_bytes, expected_w, expected_h)
    if not png_bytes or #png_bytes < 40 then return nil end
    if png_bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil end

    local idat_parts = {}
    local pos = 9
    local total = #png_bytes
    local w, h = expected_w, expected_h

    while pos + 8 <= total do
        local ch_len = string.unpack(">I4", png_bytes, pos)
        local ch_type = png_bytes:sub(pos + 4, pos + 7)
        local data_start = pos + 8
        local data_end = data_start + ch_len - 1
        if data_end > total then break end

        if ch_type == "IHDR" and ch_len >= 8 then
            w, h = string.unpack(">I4I4", png_bytes, data_start)
        elseif ch_type == "IDAT" then
            table.insert(idat_parts, png_bytes:sub(data_start, data_end))
        elseif ch_type == "IEND" then
            break
        end
        pos = data_end + 5 -- skip 4-byte CRC
    end

    if w ~= expected_w or h ~= expected_h then return nil end
    local zlib_stream = table.concat(idat_parts)
    if #zlib_stream < 7 then return nil end

    -- Parse stored DEFLATE blocks starting after 2-byte ZLIB header
    local raw_parts = {}
    local zpos = 3
    local zlen = #zlib_stream - 4 -- exclude 4-byte Adler32 trailer
    while zpos + 4 <= zlen do
        local bheader, blk_len, _ = string.unpack("<BI2I2", zlib_stream, zpos)
        zpos = zpos + 5
        if (bheader & 0x06) ~= 0 then
            -- Compressed block (not stored): cannot unpack in pure stored-block reader
            return nil
        end
        if zpos + blk_len - 1 > zlen + 4 then break end
        table.insert(raw_parts, zlib_stream:sub(zpos, zpos + blk_len - 1))
        zpos = zpos + blk_len
        if (bheader & 0x01) == 1 then break end
    end

    local raw_data = table.concat(raw_parts)
    local row_bytes = 1 + w * 4
    if #raw_data < row_bytes * h then return nil end

    local pixels = {}
    local p_idx = 1
    for y = 0, h - 1 do
        local row_offset = y * row_bytes + 2 -- skip filter byte at +1
        for x = 0, w - 1 do
            local px_offset = row_offset + x * 4
            pixels[p_idx] = string.unpack(">I4", raw_data, px_offset)
            p_idx = p_idx + 1
        end
    end
    return pixels
end

-- ==============================================================================
-- 2. DIRECTORY & FILE PATH RESOLUTION
-- ==============================================================================

local function clean_guid(guid)
    return tostring(guid or "default"):gsub("[^%w_%-]", "")
end

function AnnotationService.get_annotations_dir()
    local _, proj_fn = reaper.EnumProjects(-1, "")
    local base_dir = nil
    if proj_fn and proj_fn ~= "" then
        base_dir = proj_fn:gsub("\\", "/"):match("^(.*)/[^/]+$")
    end
    if not base_dir or base_dir == "" then
        local proj_path = reaper.GetProjectPath("")
        if proj_path and proj_path ~= "" then
            base_dir = proj_path:gsub("\\", "/")
        end
    end
    if not base_dir or base_dir == "" then
        base_dir = (reaper.GetResourcePath() or ""):gsub("\\", "/") .. "/Notator_Temp_Annotations"
    end
    local ann_dir = base_dir .. "/Notator_Annotations"
    if reaper.APIExists("RecursiveCreateDirectory") then
        reaper.RecursiveCreateDirectory(ann_dir, 0)
    end
    return ann_dir
end

function AnnotationService.get_tile_png_path(track_guid, layer_id, bar_idx)
    local dir = AnnotationService.get_annotations_dir()
    local cg = clean_guid(track_guid)
    local cl = tostring(layer_id or "L1"):gsub("[^%w_%-]", "")
    return string.format("%s/trk_%s_%s_bar%d.png", dir, cg, cl, tonumber(bar_idx) or 0)
end

-- ==============================================================================
-- 3. STATE & LAYER STACK MANAGEMENT PER TRACK
-- ==============================================================================

function AnnotationService.ensure_state(state)
    if not state.track_annotations then
        state.track_annotations = {}
    end
    if not state.annotation_tool then
        state.annotation_tool = "pen" -- "pen" | "eraser" | "select"
    end
    if not state.annotation_color_idx then
        state.annotation_color_idx = 1
    end
    if not state.annotation_color then
        state.annotation_color = AnnotationService.COLOR_PRESETS[1].col
    end
    if not state.annotation_brush_size then
        state.annotation_brush_size = 4.0
    end
    if not state.annotation_eraser_size then
        state.annotation_eraser_size = 14.0
    end
    if state.show_annotations_layer == nil then
        state.show_annotations_layer = true
    end
end

function AnnotationService.get_track_stack(state, track_guid)
    AnnotationService.ensure_state(state)
    if not track_guid or track_guid == "" then return nil end
    local stack = state.track_annotations[track_guid]
    if not stack then
        stack = {
            track_guid = track_guid,
            next_layer_num = 2,
            active_layer_id = "L1",
            layers = {
                {
                    id = "L1",
                    name = "Layer 1",
                    visible = true,
                    locked = false,
                    opacity = 1.0,
                    bars = {} -- Sparse table: [bar_idx] = { pixels, png_bytes, imgui_img, png_path, dirty }
                }
            }
        }
        state.track_annotations[track_guid] = stack
    end
    return stack
end

function AnnotationService.get_active_layer(state, track_guid)
    local stack = AnnotationService.get_track_stack(state, track_guid)
    if not stack or not stack.layers or #stack.layers == 0 then return nil end
    for _, l in ipairs(stack.layers) do
        if l.id == stack.active_layer_id then
            return l
        end
    end
    stack.active_layer_id = stack.layers[#stack.layers].id
    return stack.layers[#stack.layers]
end

function AnnotationService.count_layer_bars(layer)
    if not layer or not layer.bars then return 0 end
    local cnt = 0
    for _ in pairs(layer.bars) do
        cnt = cnt + 1
    end
    return cnt
end

function AnnotationService.add_layer(state, track_guid)
    local stack = AnnotationService.get_track_stack(state, track_guid)
    if not stack then return nil end
    local num = stack.next_layer_num or (#stack.layers + 1)
    stack.next_layer_num = num + 1
    local new_id = "L" .. tostring(num) .. "_" .. tostring(math.floor((reaper.time_precise() * 1000) % 100000))
    local new_layer = {
        id = new_id,
        name = string.format("Layer %d", #stack.layers + 1),
        visible = true,
        locked = false,
        opacity = 1.0,
        bars = {} -- Strictly empty: no tiles or PNGs created until user draws on a bar
    }
    table.insert(stack.layers, new_layer)
    stack.active_layer_id = new_id
    AnnotationService.save_metadata(state)
    return new_layer
end

function AnnotationService.clear_layer(state, track_guid, layer_id)
    local stack = AnnotationService.get_track_stack(state, track_guid)
    if not stack then return end
    for _, l in ipairs(stack.layers) do
        if l.id == layer_id then
            if l.bars then
                for b_idx, tile in pairs(l.bars) do
                    local p = tile.png_path or AnnotationService.get_tile_png_path(track_guid, l.id, b_idx)
                    if p then os.remove(p) end
                end
            end
            l.bars = {}
            break
        end
    end
    AnnotationService.save_metadata(state)
end

function AnnotationService.delete_layer(state, track_guid, layer_id)
    local stack = AnnotationService.get_track_stack(state, track_guid)
    if not stack or #stack.layers <= 1 then
        -- If only 1 layer remains, just clear its tiles and reset it
        if stack and stack.layers[1] then
            AnnotationService.clear_layer(state, track_guid, stack.layers[1].id)
        end
        return
    end
    for i, l in ipairs(stack.layers) do
        if l.id == layer_id then
            AnnotationService.clear_layer(state, track_guid, layer_id)
            table.remove(stack.layers, i)
            if stack.active_layer_id == layer_id then
                local next_idx = math.max(1, math.min(#stack.layers, i))
                stack.active_layer_id = stack.layers[next_idx].id
            end
            break
        end
    end
    AnnotationService.save_metadata(state)
end

function AnnotationService.move_layer(state, track_guid, layer_id, delta)
    local stack = AnnotationService.get_track_stack(state, track_guid)
    if not stack then return end
    for i, l in ipairs(stack.layers) do
        if l.id == layer_id then
            local target_i = i + delta
            if target_i >= 1 and target_i <= #stack.layers then
                stack.layers[i], stack.layers[target_i] = stack.layers[target_i], stack.layers[i]
                AnnotationService.save_metadata(state)
            end
            break
        end
    end
end

-- ==============================================================================
-- 4. PIXEL BUFFER, RASTERIZATION & AUTO-CLEANUP OF EMPTY BAR TILES
-- ==============================================================================

local function create_empty_pixels()
    local total = AnnotationService.TILE_W * AnnotationService.TILE_H
    local px = {}
    for i = 1, total do px[i] = 0 end
    return px
end

function AnnotationService.has_visible_pixels(tile)
    if not tile or not tile.pixels then return false end
    local px = tile.pixels
    for i = 1, #px do
        if (px[i] & 0xFF) > 0 then
            return true
        end
    end
    return false
end

-- Ensures tile.pixels is loaded in RAM (decoding from disk if tile was loaded lazily)
local function ensure_tile_pixels_loaded(track_guid, layer_id, bar_idx, tile)
    if tile.pixels then return tile.pixels end
    local path = tile.png_path or AnnotationService.get_tile_png_path(track_guid, layer_id, bar_idx)
    local f = path and io.open(path, "rb")
    if f then
        local bytes = f:read("*a")
        f:close()
        local decoded = AnnotationService.decode_rgba_png(bytes, AnnotationService.TILE_W, AnnotationService.TILE_H)
        if decoded then
            tile.pixels = decoded
            return tile.pixels
        end
    end
    tile.pixels = create_empty_pixels()
    return tile.pixels
end

-- Draws a filled circle stamp into tile.pixels at (cx, cy) in tile pixel coordinates
local function draw_circle_stamp(pixels, w, h, cx, cy, radius, r_col, g_col, b_col, a_col, is_eraser)
    local rad = math.max(0.8, radius)
    local x0 = math.max(0, math.floor(cx - rad - 1))
    local x1 = math.min(w - 1, math.ceil(cx + rad + 1))
    local y0 = math.max(0, math.floor(cy - rad - 1))
    local y1 = math.min(h - 1, math.ceil(cy + rad + 1))

    for py = y0, y1 do
        local dy = (py + 0.5) - cy
        local row_base = py * w
        for px = x0, x1 do
            local dx = (px + 0.5) - cx
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= rad + 0.65 then
                local idx = row_base + px + 1
                if is_eraser then
                    if dist <= rad then
                        pixels[idx] = 0
                    else
                        -- Soft edge on eraser
                        local cur = pixels[idx] or 0
                        local cur_a = cur & 0xFF
                        if cur_a > 0 then
                            local keep = math.max(0.0, math.min(1.0, dist - rad))
                            local new_a = math.floor(cur_a * keep)
                            pixels[idx] = (new_a > 4) and ((cur & 0xFFFFFF00) | new_a) or 0
                        end
                    end
                else
                    -- Smooth 1px anti-aliased edge
                    local cov = 1.0
                    if dist > rad - 0.5 then
                        cov = math.max(0.0, math.min(1.0, (rad + 0.5) - dist))
                    end
                    local src_a = math.floor(a_col * cov + 0.5)
                    if src_a > 0 then
                        local dst = pixels[idx] or 0
                        local dst_a = dst & 0xFF
                        if dst_a == 0 or src_a >= 250 then
                            pixels[idx] = (r_col << 24) | (g_col << 16) | (b_col << 8) | src_a
                        else
                            local inv_a = 255 - src_a
                            local out_a = src_a + math.floor((dst_a * inv_a) / 255)
                            if out_a > 0 then
                                local dst_r = (dst >> 24) & 0xFF
                                local dst_g = (dst >> 16) & 0xFF
                                local dst_b = (dst >> 8)  & 0xFF
                                local out_r = math.min(255, math.floor((r_col * src_a + dst_r * dst_a * (inv_a / 255)) / out_a))
                                local out_g = math.min(255, math.floor((g_col * src_a + dst_g * dst_a * (inv_a / 255)) / out_a))
                                local out_b = math.min(255, math.floor((b_col * src_a + dst_b * dst_a * (inv_a / 255)) / out_a))
                                pixels[idx] = (out_r << 24) | (out_g << 16) | (out_b << 8) | out_a
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Rasterizes a stroke segment (u0, v0) -> (u1, v1) in [0..1] into bar_idx of the active layer.
-- Strictly obeys:
-- 1. If is_eraser and layer.bars[bar_idx] does NOT exist -> do nothing (never allocate empty tile!).
-- 2. If Pen and layer.bars[bar_idx] does NOT exist -> lazily create the 320x200 tile.
function AnnotationService.rasterize_bar_segment(state, track_guid, bar_idx, u0, v0, u1, v1, is_eraser)
    local layer = AnnotationService.get_active_layer(state, track_guid)
    if not layer or layer.locked or not layer.visible then return false end

    -- Clamp UV check: ignore if segment is completely outside [0..1]
    if (u0 < 0 and u1 < 0) or (u0 > 1 and u1 > 1) or (v0 < 0 and v1 < 0) or (v0 > 1 and v1 > 1) then
        return false
    end

    local tile = layer.bars[bar_idx]
    if not tile then
        if is_eraser then
            -- Never create a background tile when erasing on an empty bar!
            return false
        end
        tile = {
            pixels = create_empty_pixels(),
            png_path = AnnotationService.get_tile_png_path(track_guid, layer.id, bar_idx),
            tex_dirty = true,
            disk_dirty = true
        }
        layer.bars[bar_idx] = tile
    else
        ensure_tile_pixels_loaded(track_guid, layer.id, bar_idx, tile)
    end

    local w, h = AnnotationService.TILE_W, AnnotationService.TILE_H
    local x0, y0 = u0 * w, v0 * h
    local x1, y1 = u1 * w, v1 * h

    local col = state.annotation_color or 0xE74C3CFF
    local r_col = (col >> 24) & 0xFF
    local g_col = (col >> 16) & 0xFF
    local b_col = (col >> 8)  & 0xFF
    local a_col = col & 0xFF

    local radius = is_eraser and ((state.annotation_eraser_size or 14.0) * 0.5) or ((state.annotation_brush_size or 4.0) * 0.5)
    local dist = math.sqrt((x1 - x0)^2 + (y1 - y0)^2)
    local step = math.max(0.5, radius * 0.35)
    local steps = math.max(1, math.ceil(dist / step))

    for i = 0, steps do
        local t = (steps == 0) and 0 or (i / steps)
        local cx = x0 + (x1 - x0) * t
        local cy = y0 + (y1 - y0) * t
        draw_circle_stamp(tile.pixels, w, h, cx, cy, radius, r_col, g_col, b_col, a_col, is_eraser)
    end

    tile.tex_dirty = true
    tile.disk_dirty = true
    state._has_dirty_annotation_tiles = true
    return true
end

-- Updates in-memory ReaImGui textures for any tiles modified on the current frame (zero disk I/O)
function AnnotationService.update_dirty_textures(state)
    if not state or not state.track_annotations then return end
    for _, stack in pairs(state.track_annotations) do
        if stack and stack.layers then
            for _, layer in ipairs(stack.layers) do
                if layer.bars then
                    for _, tile in pairs(layer.bars) do
                        if tile.tex_dirty and tile.pixels then
                            tile.tex_dirty = false
                            local png_bytes = AnnotationService.encode_rgba_png(tile.pixels, AnnotationService.TILE_W, AnnotationService.TILE_H)
                            tile.png_bytes = png_bytes
                            if reaper.APIExists("ImGui_CreateImageFromMem") then
                                local ok, img = pcall(reaper.ImGui_CreateImageFromMem, png_bytes)
                                if ok and img then
                                    tile.imgui_img = img
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Flushes dirty tiles to disk as transparent PNGs & updates ReaImGui textures.
-- If a tile has NO visible pixels left (e.g. completely erased), removes the tile from RAM and deletes its PNG file!
function AnnotationService.commit_dirty_tiles(state, write_to_disk)
    if not state or not state.track_annotations then return end
    local any_saved = false

    for track_guid, stack in pairs(state.track_annotations) do
        if stack and stack.layers then
            for _, layer in ipairs(stack.layers) do
                if layer.bars then
                    local to_remove = {}
                    for bar_idx, tile in pairs(layer.bars) do
                        if tile.disk_dirty or tile.tex_dirty then
                            if not AnnotationService.has_visible_pixels(tile) then
                                -- Tile is 100% transparent: remove from layer and delete PNG file on disk!
                                table.insert(to_remove, bar_idx)
                                local p = tile.png_path or AnnotationService.get_tile_png_path(track_guid, layer.id, bar_idx)
                                if p then os.remove(p) end
                                any_saved = true
                            else
                                if tile.tex_dirty or not tile.png_bytes then
                                    tile.png_bytes = AnnotationService.encode_rgba_png(tile.pixels, AnnotationService.TILE_W, AnnotationService.TILE_H)
                                    tile.tex_dirty = false
                                    if reaper.APIExists("ImGui_CreateImageFromMem") then
                                        local ok, img = pcall(reaper.ImGui_CreateImageFromMem, tile.png_bytes)
                                        if ok and img then
                                            tile.imgui_img = img
                                        end
                                    end
                                end
                                if write_to_disk ~= false then
                                    local p = AnnotationService.get_tile_png_path(track_guid, layer.id, bar_idx)
                                    tile.png_path = p
                                    local f = io.open(p, "wb")
                                    if f then
                                        f:write(tile.png_bytes)
                                        f:close()
                                    end
                                    if not tile.imgui_img and reaper.APIExists("ImGui_CreateImage") then
                                        local ok, img = pcall(reaper.ImGui_CreateImage, p)
                                        if ok and img then tile.imgui_img = img end
                                    end
                                    tile.disk_dirty = false
                                    any_saved = true
                                end
                            end
                        end
                    end
                    for _, b_idx in ipairs(to_remove) do
                        layer.bars[b_idx] = nil
                    end
                end
            end
        end
    end

    if write_to_disk ~= false then
        state._has_dirty_annotation_tiles = false
        if any_saved then
            AnnotationService.save_metadata(state)
            if reaper.MarkProjectDirty then reaper.MarkProjectDirty(0) end
        end
    end
end

-- ==============================================================================
-- 5. METADATA PERSISTENCE IN PROJEXTSTATE & LAZY PNG LOADING
-- ==============================================================================

local function escape_str(s)
    return tostring(s or ""):gsub("[|;~^]", "_")
end

function AnnotationService.save_metadata(state)
    if not state or not state.track_annotations then return end
    local track_entries = {}
    for track_guid, stack in pairs(state.track_annotations) do
        if stack and stack.layers and #stack.layers > 0 then
            local layer_strs = {}
            for _, l in ipairs(stack.layers) do
                local bar_indices = {}
                if l.bars then
                    for b_idx, tile in pairs(l.bars) do
                        if tile.pixels == nil or AnnotationService.has_visible_pixels(tile) then
                            table.insert(bar_indices, tostring(b_idx))
                        end
                    end
                end
                table.sort(bar_indices, function(a, b) return (tonumber(a) or 0) < (tonumber(b) or 0) end)
                local l_str = string.format("%s^%s^%d^%d^%.2f^%s",
                    escape_str(l.id),
                    escape_str(l.name),
                    l.visible and 1 or 0,
                    l.locked and 1 or 0,
                    tonumber(l.opacity) or 1.0,
                    table.concat(bar_indices, ",")
                )
                table.insert(layer_strs, l_str)
            end
            local t_str = string.format("%s|%s|%d|%s",
                tostring(track_guid),
                escape_str(stack.active_layer_id or "L1"),
                tonumber(stack.next_layer_num) or (#stack.layers + 1),
                table.concat(layer_strs, "~")
            )
            table.insert(track_entries, t_str)
        end
    end
    reaper.SetProjExtState(0, "REAPER_Notator", "annotation_layers", table.concat(track_entries, ";"))
end

function AnnotationService.load_metadata(state)
    AnnotationService.ensure_state(state)
    state.track_annotations = {}
    local _, raw = reaper.GetProjExtState(0, "REAPER_Notator", "annotation_layers")
    if not raw or raw == "" then return end

    for t_entry in raw:gmatch("([^;]+)") do
        local parts = {}
        for f in (t_entry .. "|"):gmatch("([^|]*)|") do table.insert(parts, f) end
        local track_guid = parts[1]
        local active_id  = parts[2]
        local next_num   = tonumber(parts[3]) or 2
        local layers_raw = parts[4] or ""

        if track_guid and track_guid ~= "" then
            local layers = {}
            for l_entry in layers_raw:gmatch("([^~]+)") do
                local lp = {}
                for lf in (l_entry .. "^"):gmatch("([^^]*)^") do table.insert(lp, lf) end
                local lid   = lp[1]
                local lname = lp[2] or "Layer"
                local lvis  = (tonumber(lp[3]) or 1) ~= 0
                local llock = (tonumber(lp[4]) or 0) ~= 0
                local lopac = tonumber(lp[5]) or 1.0
                local lbars_str = lp[6] or ""

                if lid and lid ~= "" then
                    local bars = {}
                    for b_str in lbars_str:gmatch("([^,]+)") do
                        local b_idx = tonumber(b_str)
                        if b_idx then
                            local p = AnnotationService.get_tile_png_path(track_guid, lid, b_idx)
                            local f = io.open(p, "rb")
                            if f then
                                local png_bytes = f:read("*a")
                                f:close()
                                if png_bytes and #png_bytes > 40 then
                                    local img = nil
                                    if reaper.APIExists("ImGui_CreateImageFromMem") then
                                        local ok, created = pcall(reaper.ImGui_CreateImageFromMem, png_bytes)
                                        if ok then img = created end
                                    elseif reaper.APIExists("ImGui_CreateImage") then
                                        local ok, created = pcall(reaper.ImGui_CreateImage, p)
                                        if ok then img = created end
                                    end
                                    bars[b_idx] = {
                                        pixels = nil, -- Lazily decoded only if user edits/erases this bar!
                                        png_bytes = png_bytes,
                                        imgui_img = img,
                                        png_path = p,
                                        dirty = false
                                    }
                                end
                            end
                        end
                    end
                    table.insert(layers, {
                        id = lid,
                        name = lname,
                        visible = lvis,
                        locked = llock,
                        opacity = lopac,
                        bars = bars
                    })
                end
            end
            if #layers > 0 then
                state.track_annotations[track_guid] = {
                    track_guid = track_guid,
                    active_layer_id = active_id or layers[1].id,
                    next_layer_num = next_num,
                    layers = layers
                }
            end
        end
    end
end

-- Ensures the ReaImGui texture pointer is valid (ReaImGui destroys unreferenced images across frames unless recreated or attached)
function AnnotationService.get_valid_tile_image(ctx, track_guid, layer_id, bar_idx, tile)
    if not tile then return nil end
    if tile.imgui_img then
        if not reaper.APIExists("ImGui_ValidatePtr") or reaper.ImGui_ValidatePtr(tile.imgui_img, "ImGui_Image*") then
            return tile.imgui_img
        end
        tile.imgui_img = nil
    end
    if tile.png_bytes and reaper.APIExists("ImGui_CreateImageFromMem") then
        local ok, img = pcall(reaper.ImGui_CreateImageFromMem, tile.png_bytes)
        if ok and img then
            tile.imgui_img = img
            return img
        end
    end
    local p = tile.png_path or AnnotationService.get_tile_png_path(track_guid, layer_id, bar_idx)
    if p and reaper.APIExists("ImGui_CreateImage") then
        local ok, img = pcall(reaper.ImGui_CreateImage, p)
        if ok and img then
            tile.imgui_img = img
            return img
        end
    end
    return nil
end

-- Maps a screen-space stroke segment (x0, y0) -> (x1, y1) inside a track band to bar tiles
-- and updates in-memory textures immediately for 60+ FPS live visual feedback.
function AnnotationService.stroke_canvas_segment(state, tdata, x0, y0, x1, y1, margin_left, s, qn_per_measure, measure_map, is_eraser, Engraver)
    if not tdata or not tdata.guid or not tdata.band_y0 then return false end
    local layer = AnnotationService.get_active_layer(state, tdata.guid)
    if not layer or layer.locked or not layer.visible then return false end

    local staff_h = tdata.is_harp and 224 or (tdata.is_grand and 148 or 80)
    local ref_band_h = (staff_h + AnnotationService.MAX_TRACK_SPACING) * s
    if ref_band_h <= 1.0 then return false end

    local function get_bar_bounds(m)
        local bx0 = (measure_map and measure_map.starts and measure_map.starts[m])
            or Engraver.cursor_qn_to_canvas_x(m * qn_per_measure, margin_left, s, qn_per_measure, measure_map)
        local bx1 = (measure_map and measure_map.starts and measure_map.starts[m + 1])
            or Engraver.cursor_qn_to_canvas_x((m + 1) * qn_per_measure, margin_left, s, qn_per_measure, measure_map)
        return bx0, bx1
    end

    local function find_bar_at_x(px)
        local qn = Engraver.canvas_x_to_qn(px, margin_left, s, qn_per_measure, 0.0001, measure_map)
        local m = math.max(0, math.floor((qn + 0.0001) / qn_per_measure))
        local bx0, bx1 = get_bar_bounds(m)
        if px < bx0 and m > 0 then
            m = m - 1
            bx0, bx1 = get_bar_bounds(m)
        elseif px > bx1 then
            m = m + 1
            bx0, bx1 = get_bar_bounds(m)
        end
        return m, bx0, bx1
    end

    local dist = math.sqrt((x1 - x0)^2 + (y1 - y0)^2)
    local max_step_px = math.max(2.0, 4.0 * s)
    local steps = math.max(1, math.ceil(dist / max_step_px))
    local rad_u = ((is_eraser and (state.annotation_eraser_size or 14.0) or (state.annotation_brush_size or 4.0)) * 0.5) / AnnotationService.TILE_W
    local any_modified = false

    for i = 0, steps - 1 do
        local t0 = i / steps
        local t1 = (i + 1) / steps
        local sx0 = x0 + (x1 - x0) * t0
        local sy0 = y0 + (y1 - y0) * t0
        local sx1 = x0 + (x1 - x0) * t1
        local sy1 = y0 + (y1 - y0) * t1

        local mid_x = (sx0 + sx1) * 0.5
        local m, bx0, bx1 = find_bar_at_x(mid_x)
        local bw = math.max(1.0, bx1 - bx0)

        local u0 = (sx0 - bx0) / bw
        local u1 = (sx1 - bx0) / bw
        local v0 = (sy0 - tdata.band_y0) / ref_band_h
        local v1 = (sy1 - tdata.band_y0) / ref_band_h

        if AnnotationService.rasterize_bar_segment(state, tdata.guid, m, u0, v0, u1, v1, is_eraser) then
            any_modified = true
        end

        -- Seamless barline crossing when the brush radius overlaps the adjacent bar
        if math.min(u0, u1) - rad_u < 0.0 and m > 0 then
            local p_bx0, p_bx1 = get_bar_bounds(m - 1)
            local p_bw = math.max(1.0, p_bx1 - p_bx0)
            if AnnotationService.rasterize_bar_segment(state, tdata.guid, m - 1, (sx0 - p_bx0) / p_bw, v0, (sx1 - p_bx0) / p_bw, v1, is_eraser) then
                any_modified = true
            end
        end
        if math.max(u0, u1) + rad_u > 1.0 then
            local n_bx0, n_bx1 = get_bar_bounds(m + 1)
            local n_bw = math.max(1.0, n_bx1 - n_bx0)
            if AnnotationService.rasterize_bar_segment(state, tdata.guid, m + 1, (sx0 - n_bx0) / n_bw, v0, (sx1 - n_bx0) / n_bw, v1, is_eraser) then
                any_modified = true
            end
        end
    end

    if any_modified then
        AnnotationService.update_dirty_textures(state)
    end
    return any_modified
end

return AnnotationService

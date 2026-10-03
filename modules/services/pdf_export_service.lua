-- ==============================================================================
-- REAPER Native Notator - Service: PdfExportService
-- Pure-Lua vector PDF generator with embedded Bravura OpenType SMuFL font.
-- Generates publishing-quality orchestral scores:
--   Page 1: Traditional classical cover page (Urtext / Breitkopf style)
--   Page 2: Orchestration cast list & word-wrapped performance notes
--   Page 3+: Paginated score (default 5 bars/page) with Grand Staff support,
--            diatonic pitch placement, SMuFL clefs & noteheads, joint barlines.
local Constants      = require("constants")
local Engraver       = require("rendering.engraver")
local SystemEngraver = require("rendering.system_engraver")
local HairpinService = require("services.hairpin_service")
local PathService    = require("services.path_service")

local PdfExportService = {}

-- ------------------------------------------------------------------------------
-- Paper Sizes in points (72 pt = 1 inch)
-- ------------------------------------------------------------------------------
local PAPER_SIZES = {
    A4     = { w = 595.28, h = 841.89 },
    A3     = { w = 841.89, h = 1190.55 },
    Letter = { w = 612.00, h = 792.00 }
}

-- ------------------------------------------------------------------------------
-- Bravura OpenType SMuFL GID Mapping
-- ------------------------------------------------------------------------------
local BRAVURA_GIDS = {
    g_clef            = "004A", -- GID 74,  U+E050
    f_clef            = "005C", -- GID 92,  U+E062
    c_clef            = "0056", -- GID 86,  U+E05C
    brace             = "000F", -- GID 15,  U+E000
    note_black        = "009E", -- GID 158, U+E0A4
    note_half         = "009D", -- GID 157, U+E0A3
    note_whole        = "009C", -- GID 156, U+E0A2
    acc_sharp         = "0219", -- GID 537, U+E262
    acc_flat          = "0217", -- GID 535, U+E260
    acc_natural       = "0218", -- GID 536, U+E261
    flag8thUp         = "0205", -- GID 517, U+E240
    flag8thDown       = "0206", -- GID 518, U+E241
    flag16thUp        = "0207", -- GID 519, U+E242
    flag16thDown      = "0208", -- GID 520, U+E243
    rest_whole        = "03E2", -- GID 994, U+E4E3
    rest_half         = "03E3", -- GID 995, U+E4E4
    rest_quarter      = "03E4", -- GID 996, U+E4E5
    rest_8th          = "03E5", -- GID 997, U+E4E6
    rest_16th         = "03E6", -- GID 998, U+E4E7
    time_sig_common   = "0084", -- GID 132, U+E08A
    time_sig_digits   = {
        [0] = "007A", [1] = "007B", [2] = "007C", [3] = "007D", [4] = "007E",
        [5] = "007F", [6] = "0080", [7] = "0081", [8] = "0082", [9] = "0083"
    }
}

-- Diatonic step mapping for pitch (C=0, D=1, E=2, F=3, G=4, A=5, B=6)
local PITCH_TO_DIATONIC = {
    [0] = 0, [1] = 0, [2] = 1, [3] = 1, [4] = 2, [5] = 3,
    [6] = 3, [7] = 4, [8] = 4, [9] = 5, [10] = 5, [11] = 6
}
local PITCH_HAS_ACCIDENTAL = {
    [1] = "acc_sharp", [3] = "acc_flat", [6] = "acc_sharp", [8] = "acc_sharp", [10] = "acc_flat"
}

-- ------------------------------------------------------------------------------
-- Locate and load Bravura.otf binary data
-- ------------------------------------------------------------------------------
local function load_bravura_data()
    local b_path = PathService.get_bravura_path()
    local candidates = {}
    if b_path and PathService.file_exists(b_path) then
        table.insert(candidates, b_path)
    end
    local s_dir = PathService.get_script_dir()
    table.insert(candidates, s_dir .. "/Bravura.otf")
    table.insert(candidates, s_dir .. "/../Bravura.otf")
    table.insert(candidates, s_dir .. "/../../Bravura.otf")

    for _, p in ipairs(candidates) do
        local f = io.open(p, "rb")
        if f then
            local data = f:read("*a")
            f:close()
            if data and #data > 1000 then
                return data
            end
        end
    end
    return nil
end

-- ------------------------------------------------------------------------------
-- Escape PDF strings (for standard Type1 text)
-- ------------------------------------------------------------------------------
local function pdf_escape(str)
    if not str then return "" end
    str = tostring(str)
    -- Remove non-ASCII characters to prevent encoding artifacts (e.g. â€¢)
    str = str:gsub("[\128-\255]", "")
    str = str:gsub("\\", "\\\\")
    str = str:gsub("%(", "\\(")
    str = str:gsub("%)", "\\)")
    return str
end

-- ------------------------------------------------------------------------------
-- Text wrapping helper
-- ------------------------------------------------------------------------------
local function wrap_text(text, max_chars)
    max_chars = max_chars or 65
    local lines = {}
    for paragraph in text:gmatch("([^\r\n]*)") do
        if #paragraph == 0 then
            table.insert(lines, "")
        else
            local cur_line = ""
            for word in paragraph:gmatch("%S+") do
                if #cur_line == 0 then
                    cur_line = word
                elseif (#cur_line + 1 + #word) <= max_chars then
                    cur_line = cur_line .. " " .. word
                else
                    table.insert(lines, cur_line)
                    cur_line = word
                end
            end
            if #cur_line > 0 then
                table.insert(lines, cur_line)
            end
        end
    end
    return lines
end

-- ------------------------------------------------------------------------------
-- Track clef & Grand Staff detector (matches ScoreCanvas rules)
-- ------------------------------------------------------------------------------
local function get_track_clef_mode(track, track_name, track_notes, state)
    return Engraver.get_track_clef(track, track_name, track_notes, state)
end

-- ------------------------------------------------------------------------------
-- Low-Level PDF Document Builder with Bravura OpenType font embedding
-- ------------------------------------------------------------------------------
local function new_pdf_doc(paper_size, orientation)
    local p_def = PAPER_SIZES[paper_size] or PAPER_SIZES["A4"]
    local p_w, p_h = p_def.w, p_def.h
    if orientation == "landscape" then
        p_w, p_h = p_def.h, p_def.w
    end

    local bravura_bytes = load_bravura_data()

    local doc = {
        w = p_w,
        h = p_h,
        pages = {},
        bravura_bytes = bravura_bytes,
        fonts = { "Times-Roman", "Times-Bold", "Times-Italic", "Helvetica", "Helvetica-Bold" }
    }

    function doc:add_page()
        local page = {
            doc = doc,
            ops = {},
            w = doc.w,
            h = doc.h
        }

        local function py(y)
            return page.h - y
        end

        function page:py(y)
            return self.h - y
        end

        function page:set_stroke_color(r, g, b)
            table.insert(self.ops, string.format("%.3f %.3f %.3f RG", r, g, b))
        end

        function page:set_fill_color(r, g, b)
            table.insert(self.ops, string.format("%.3f %.3f %.3f rg", r, g, b))
        end

        function page:set_line_width(w)
            table.insert(self.ops, string.format("%.2f w", w))
        end

        function page:line(x1, y1, x2, y2)
            table.insert(self.ops, string.format("%.2f %.2f m %.2f %.2f l S", x1, py(y1), x2, py(y2)))
        end

        function page:beam_quad(x1, y1, x2, y2, th, dir)
            local py1 = self.h - y1
            local py2 = self.h - y2
            local py2_b = self.h - (y2 - dir * th)
            local py1_b = self.h - (y1 - dir * th)
            local s = string.format("%.2f %.2f m %.2f %.2f l %.2f %.2f l %.2f %.2f l f", x1, py1, x2, py2, x2, py2_b, x1, py1_b)
            table.insert(self.ops, s)
        end

        function page:tie(x1, y1, x2, y2, dir)
            dir = dir or -1
            local dist = math.abs(x2 - x1)
            local arch = math.min(12.0, math.max(3.5, dist * 0.16)) * dir
            local py1 = self.h - y1
            local py2 = self.h - y2
            local pc1y = self.h - (y1 + arch)
            local pc2y = self.h - (y2 + arch)
            local s = string.format("%.2f %.2f m %.2f %.2f %.2f %.2f %.2f %.2f c S",
                x1, py1, x1 + dist * 0.25, pc1y, x2 - dist * 0.25, pc2y, x2, py2)
            table.insert(self.ops, s)
        end

        function page:rect(x, y, w, h, fill, stroke)
            local op = (fill and stroke and "B") or (fill and "f") or "S"
            table.insert(self.ops, string.format("%.2f %.2f %.2f %.2f re %s", x, py(y + h), w, h, op))
        end

        function page:ellipse(cx, cy, rx, ry, fill, stroke)
            local k = 0.5522847498
            local kx, ky = rx * k, ry * k
            local y_mid = py(cy)
            local op = (fill and stroke and "B") or (fill and "f") or "S"
            local s = string.format(
                "%.2f %.2f m " ..
                "%.2f %.2f %.2f %.2f %.2f %.2f c " ..
                "%.2f %.2f %.2f %.2f %.2f %.2f c " ..
                "%.2f %.2f %.2f %.2f %.2f %.2f c " ..
                "%.2f %.2f %.2f %.2f %.2f %.2f c %s",
                cx - rx, y_mid,
                cx - rx, y_mid + ky, cx - kx, y_mid + ry, cx, y_mid + ry,
                cx + kx, y_mid + ry, cx + rx, y_mid + ky, cx + rx, y_mid,
                cx + rx, y_mid - ky, cx + kx, y_mid - ry, cx, y_mid - ry,
                cx - kx, y_mid - ry, cx - rx, y_mid - ky, cx - rx, y_mid,
                op
            )
            table.insert(self.ops, s)
        end

        function page:text(font_name, size, x, y, str, align)
            local font_id = "/F1"
            if font_name == "Times-Bold" then font_id = "/F2"
            elseif font_name == "Times-Italic" then font_id = "/F3"
            elseif font_name == "Helvetica" then font_id = "/F4"
            elseif font_name == "Helvetica-Bold" then font_id = "/F5"
            end

            local est_w = #str * (size * 0.52)
            local final_x = x
            if align == "center" then
                final_x = x - (est_w * 0.5)
            elseif align == "right" then
                final_x = x - est_w
            end

            local s = string.format("BT %s %.1f Tf %.2f %.2f Td (%s) Tj ET", font_id, size, final_x, py(y), pdf_escape(str))
            table.insert(self.ops, s)
        end

        -- SMuFL glyph using embedded Bravura OpenType font
        function page:bravura_glyph(gid_hex, size, x, y)
            if doc.bravura_bytes then
                local s = string.format("BT /F_Bravura %.1f Tf %.2f %.2f Td <%s> Tj ET", size, x, py(y), gid_hex)
                table.insert(self.ops, s)
            end
        end

        table.insert(self.pages, page)
        return page
    end

    function doc:generate_bytes()
        local objects = {}
        local function add_obj(body)
            table.insert(objects, body)
            return #objects
        end

        -- Obj 1: Catalog
        add_obj("<< /Type /Catalog /Pages 2 0 R >>")
        -- Obj 2: Pages (placeholder)
        add_obj("")

        -- Objs 3..7: Standard Type 1 Fonts
        local font_objs = {}
        for _, fname in ipairs(doc.fonts) do
            local f_id = add_obj(string.format("<< /Type /Font /Subtype /Type1 /BaseFont /%s /Encoding /WinAnsiEncoding >>", fname))
            table.insert(font_objs, f_id)
        end

        -- Embedded Bravura OpenType Font
        local type0_id = nil
        if doc.bravura_bytes then
            local ffile_id = add_obj(string.format("<< /Length %d /Subtype /OpenType >>\nstream\n", #doc.bravura_bytes) .. doc.bravura_bytes .. "\nendstream")
            local fdesc_id = add_obj(string.format("<< /Type /FontDescriptor /FontName /Bravura /Flags 4 /FontBBox [-1000 -1000 3000 3000] /ItalicAngle 0 /Ascent 800 /Descent -200 /CapHeight 700 /StemV 80 /FontFile3 %d 0 R >>", ffile_id))
            local cid_id   = add_obj(string.format("<< /Type /Font /Subtype /CIDFontType0 /BaseFont /Bravura /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> /FontDescriptor %d 0 R /DW 1000 >>", fdesc_id))
            type0_id       = add_obj(string.format("<< /Type /Font /Subtype /Type0 /BaseFont /Bravura /Encoding /Identity-H /DescendantFonts [ %d 0 R ] >>", cid_id))
        end

        -- Pages and Page Contents
        local page_obj_ids = {}
        for _, page in ipairs(doc.pages) do
            local stream_body = table.concat(page.ops, "\n")
            local stream_id = add_obj(string.format("<< /Length %d >>\nstream\n%s\nendstream", #stream_body, stream_body))

            local font_dict = string.format("<< /F1 %d 0 R /F2 %d 0 R /F3 %d 0 R /F4 %d 0 R /F5 %d 0 R",
                font_objs[1], font_objs[2], font_objs[3], font_objs[4], font_objs[5])
            if type0_id then
                font_dict = font_dict .. string.format(" /F_Bravura %d 0 R", type0_id)
            end
            font_dict = font_dict .. " >>"

            local page_id = add_obj(string.format(
                "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %.2f %.2f] /Contents %d 0 R /Resources << /Font %s >> >>",
                doc.w, doc.h, stream_id, font_dict
            ))
            table.insert(page_obj_ids, page_id)
        end

        -- Update Obj 2 (Pages root)
        local kids_str = table.concat(vim_kids or (function()
            local t = {}
            for _, pid in ipairs(page_obj_ids) do table.insert(t, string.format("%d 0 R", pid)) end
            return t
        end)(), " ")

        objects[2] = string.format("<< /Type /Pages /Kids [ %s ] /Count %d >>", kids_str, #page_obj_ids)

        -- Build final byte buffer with xref
        local buf = { "%PDF-1.6\n" }
        local offsets = {}

        for i, obj in ipairs(objects) do
            local cur_offset = 0
            for _, b in ipairs(buf) do cur_offset = cur_offset + #b end
            table.insert(offsets, cur_offset)
            table.insert(buf, string.format("%d 0 obj\n%s\nendobj\n", i, obj))
        end

        local xref_start = 0
        for _, b in ipairs(buf) do xref_start = xref_start + #b end

        table.insert(buf, string.format("xref\n0 %d\n0000000000 65535 f \n", #objects + 1))
        for _, off in ipairs(offsets) do
            table.insert(buf, string.format("%010d 00000 n \n", off))
        end

        table.insert(buf, string.format("trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n", #objects + 1, xref_start))
        return table.concat(buf)
    end

    return doc
end

-- ------------------------------------------------------------------------------
-- PAGE 1: Traditional Classical Cover Page (Urtext / Breitkopf Edition Style)
-- ------------------------------------------------------------------------------
local function render_title_page(doc, s)
    local page = doc:add_page()
    local pw, ph = doc.w, doc.h

    -- Classical double border
    local m1 = 20
    local m2 = 25
    page:set_stroke_color(0.1, 0.1, 0.1)
    page:set_line_width(0.9)
    page:rect(m1, m1, pw - (2 * m1), ph - (2 * m1), false, true)
    page:set_line_width(2.6)
    page:rect(m2, m2, pw - (2 * m2), ph - (2 * m2), false, true)

    local cx = pw * 0.5

    -- 1. Composer Name (prominent at top)
    local comp_name = (s.composer and s.composer ~= "") and s.composer:upper() or "COMPOSER"
    page:set_fill_color(0.12, 0.12, 0.12)
    page:text("Times-Bold", 18, cx, ph * 0.28, comp_name, "center")

    -- 2. Main Piece Title (Large, commanding classical serif)
    local piece_title = (s.title and s.title ~= "") and s.title or "Full Orchestral Score"
    page:set_fill_color(0.05, 0.05, 0.05)
    page:text("Times-Bold", 32, cx, ph * 0.38, piece_title, "center")

    -- 3. Ornamental double rule with diamond rosette in center
    local rule_w = math.min(pw * 0.5, #piece_title * 14.0)
    local rule_y = ph * 0.42
    page:set_stroke_color(0.2, 0.2, 0.2)
    page:set_line_width(1.2)
    page:line(cx - (rule_w * 0.5), rule_y, cx - 12, rule_y)
    page:line(cx + 12, rule_y, cx + (rule_w * 0.5), rule_y)
    page:set_line_width(0.6)
    page:line(cx - (rule_w * 0.4), rule_y + 3, cx - 12, rule_y + 3)
    page:line(cx + 12, rule_y + 3, cx + (rule_w * 0.4), rule_y + 3)

    -- Center diamond rosette
    page:set_fill_color(0.15, 0.15, 0.15)
    page:ellipse(cx, rule_y + 1, 3.2, 3.2, true, false)

    -- 4. Subtitle / Genre (Italic)
    local sub_txt = (s.subtitle and s.subtitle ~= "") and s.subtitle or "for Full Orchestra"
    page:set_fill_color(0.25, 0.25, 0.25)
    page:text("Times-Italic", 15, cx, ph * 0.47, sub_txt, "center")

    -- 5. Score Format descriptor
    page:set_fill_color(0.15, 0.15, 0.15)
    page:text("Times-Bold", 11, cx, ph * 0.55, "PARTITUR   \225   FULL ORCHESTRAL SCORE", "center")

    -- 6. Arranger / Editor if specified
    if s.arranger and s.arranger ~= "" then
        page:set_fill_color(0.3, 0.3, 0.3)
        page:text("Times-Roman", 11, cx, ph * 0.61, "Arranged & Orchestrated by " .. s.arranger, "center")
    end

    -- 7. Publication Date & Copyright at bottom
    local date_str = s.date or os.date("%Y")
    page:set_fill_color(0.3, 0.3, 0.3)
    page:text("Times-Roman", 11, cx, ph - 62, tostring(date_str), "center")

    local copy_str = s.copyright or string.format("\169 %s All Rights Reserved", date_str)
    page:text("Times-Roman", 9, cx, ph - 44, copy_str, "center")
end

-- ------------------------------------------------------------------------------
-- PAGE 2: Orchestration & Notes Page
-- ------------------------------------------------------------------------------
local function render_notes_page(doc, s, project_tracks)
    local page = doc:add_page()
    local pw, ph = doc.w, doc.h

    -- Header Title
    page:set_fill_color(0.1, 0.1, 0.1)
    page:text("Times-Bold", 16, pw * 0.5, 42, "INSTRUMENTATION & PERFORMANCE NOTES", "center")
    page:set_stroke_color(0.2, 0.2, 0.2)
    page:set_line_width(1.0)
    page:line(36, 56, pw - 36, 56)

    -- Column 1: Orchestration / Cast list
    local c1_x = 42
    local start_y = 78
    page:set_fill_color(0.1, 0.1, 0.1)
    page:text("Times-Bold", 11, c1_x, start_y, "ORCHESTRATION / CAST:")
    page:set_stroke_color(0.4, 0.4, 0.4)
    page:set_line_width(0.7)
    page:line(c1_x, start_y + 13, c1_x + 180, start_y + 13)

    local cy = start_y + 24
    for i, t in ipairs(project_tracks) do
        if cy > (ph - 60) then break end
        local _, tname = reaper.GetTrackName(t.track)
        tname = (tname and tname ~= "") and tname or ("Track " .. i)
        local tname_l = tname:lower()
        if not (tname_l:find("chord") or tname_l:find("akkord") or tname_l:find("scale track")) then
            page:set_fill_color(0.2, 0.2, 0.2)
            -- Pure ASCII bullet dash "- "
            page:text("Times-Roman", 10, c1_x + 6, cy, "-  " .. tname)
            cy = cy + 16
        end
    end

    -- Column 2: Performance Notes with word-wrapping
    local c2_x = pw * 0.42
    local c2_w = pw - c2_x - 42
    page:set_fill_color(0.1, 0.1, 0.1)
    page:text("Times-Bold", 11, c2_x, start_y, "PERFORMANCE & EDITORIAL NOTES:")
    page:set_stroke_color(0.4, 0.4, 0.4)
    page:set_line_width(0.7)
    page:line(c2_x, start_y + 13, pw - 42, start_y + 13)

    local ny_cur = start_y + 24
    local notes_text = s.orchestrator_notes or "Score in C (Concert Pitch).\nAll instruments sound as written."
    local wrapped_lines = wrap_text(notes_text, math.floor(c2_w / 5.2))

    for _, line in ipairs(wrapped_lines) do
        if ny_cur > (ph - 60) then break end
        if #line > 0 then
            page:set_fill_color(0.2, 0.2, 0.2)
            page:text("Times-Roman", 10, c2_x + 4, ny_cur, line)
        end
        ny_cur = ny_cur + 15
    end

    -- Page 2 Footer
    page:set_fill_color(0.4, 0.4, 0.4)
    page:text("Times-Roman", 10, pw * 0.5, ph - 30, "- 2 -", "center")
end

-- ------------------------------------------------------------------------------
-- Helper: Render PDF Key Signature via Bravura OpenType SMuFL
-- ------------------------------------------------------------------------------
local function render_pdf_key_signature(page, key_idx, x, bot_y, staff_ls, clef_font_sz, eng_s, clef_type)
    if not key_idx or key_idx == 0 then return end
    local count = math.min(7, math.abs(key_idx))
    local is_sharp = (key_idx > 0)
    local acc_gid = is_sharp and BRAVURA_GIDS.acc_sharp or BRAVURA_GIDS.acc_flat
    local clef = clef_type or "treble"
    if clef ~= "treble" and clef ~= "bass" and clef ~= "alto" then
        clef = (clef == "tenor") and "alto" or "treble"
    end

    local step_tables = {
        sharp = {
            treble = { 8, 5, 9, 6, 3, 7, 4 },
            bass   = { 6, 3, 7, 4, 1, 5, 2 },
            alto   = { 7, 4, 8, 5, 2, 6, 3 }
        },
        flat = {
            treble = { 4, 7, 3, 6, 2, 5, 1 },
            bass   = { 2, 5, 1, 4, 0, 3, -1 },
            alto   = { 3, 6, 2, 5, 1, 4, 0 }
        }
    }

    local steps = is_sharp and step_tables.sharp[clef] or step_tables.flat[clef]
    local step_y = staff_ls * 0.5
    local acc_spacing = 9.5 * (eng_s or 1.0)
    page:set_fill_color(0.1, 0.1, 0.1)

    for i = 1, count do
        local step = steps[i] or 4
        local acc_y = bot_y - (step * step_y)
        local acc_x = x + ((i - 1) * acc_spacing)
        page:bravura_glyph(acc_gid, clef_font_sz, acc_x, acc_y)
    end
end

-- ------------------------------------------------------------------------------
-- Helper: Render Staff Notes with Beaming, Flags, Rests, and Authentic Noteheads
-- ------------------------------------------------------------------------------
local function render_pdf_staff_notes(page, notes, start_m, end_m, mmap, target_bot_y, staff_ls, clef_font_sz, clef_type, state, track_guid, dynamics)
    local bpi = mmap.bpi or 4.0
    local start_qn_page = start_m * bpi
    local end_qn_page   = end_m * bpi
    local eng_s         = staff_ls / 8.0
    local step_y        = staff_ls * 0.5

    -- 1. Gather raw notes in range
    local raw_notes_in_range = {}
    for _, n in ipairs(notes or {}) do
        if n.start_qn < end_qn_page and (n.end_qn or (n.start_qn + (n.duration_qn or 1.0))) > start_qn_page then
            table.insert(raw_notes_in_range, n)
        end
    end

    -- 2. Split across barlines into visual note segments and bar ties
    local visual_notes, bar_ties = Engraver.get_visual_notes(raw_notes_in_range, bpi, start_qn_page, end_qn_page)

    local page_notes = {}
    for _, vn in ipairs(visual_notes) do
        local pref_acc = Engraver.get_note_preferred_accidental(vn, state)
        local eff_pitch, active_oct, oct_shift = Engraver.get_note_effective_pitch(vn.pitch, vn.start_qn, track_guid, state)
        local ny, in_treble, dstep, acc, staff_target = Engraver.pitch_to_canvas_y(eff_pitch, target_bot_y, target_bot_y, step_y, false, clef_type, pref_acc, nil, mmap.key_idx)
        local nx = SystemEngraver.qn_to_page_x(vn.start_qn, mmap, eng_s)

        local dur_qn = vn.duration_qn or 1.0
        table.insert(page_notes, {
            orig = vn,
            pitch = eff_pitch,
            raw_pitch = vn.pitch or 60,
            start_qn = vn.start_qn,
            dur_qn = dur_qn,
            nx = nx,
            ny = ny,
            dstep = dstep,
            step_offset = dstep,
            acc = acc,
            p_mod = eff_pitch % 12,
            is_whole = (math.abs(dur_qn - 4.0) < 0.15),
            is_half = (math.abs(dur_qn - 2.0) < 0.15 or math.abs(dur_qn - 3.0) < 0.15),
            key = tostring(eff_pitch) .. "_" .. tostring(vn.start_qn)
        })
    end

    table.sort(page_notes, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.02 then return a.start_qn < b.start_qn end
        return (a.pitch or 60) < (b.pitch or 60)
    end)

    -- 3. Ganztaktpause (Whole rest) for empty measures
    for bi = 0, mmap.page_bars - 1 do
        local cur_m_idx = start_m + bi
        local m_sqn = cur_m_idx * bpi
        local m_eqn = (cur_m_idx + 1) * bpi
        local has_any_note = false
        for _, pn in ipairs(page_notes) do
            if pn.start_qn >= (m_sqn - 0.05) and pn.start_qn < (m_eqn - 0.05) then
                has_any_note = true
                break
            end
        end
        if not has_any_note then
            local cx = mmap.starts[bi] + (mmap.widths[bi] * 0.5)
            page:set_fill_color(0.1, 0.1, 0.1)
            page:bravura_glyph(BRAVURA_GIDS.rest_whole, clef_font_sz, cx - 3.5, target_bot_y - (3 * staff_ls))
        end
    end

    -- 4. Form Beam Groups (duration <= 0.85 QN within same beat)
    local beam_groups = {}
    local cur_group = {}
    local cur_beat = nil

    for _, pn in ipairs(page_notes) do
        local is_beamable = (pn.dur_qn <= 0.85 and not pn.is_whole and not pn.is_half)
        local beat_idx = math.floor((pn.start_qn + 0.001) / 1.0)
        if is_beamable then
            if cur_beat == nil or beat_idx ~= cur_beat then
                if #cur_group >= 2 then
                    table.insert(beam_groups, cur_group)
                end
                cur_group = { pn }
                cur_beat = beat_idx
            else
                table.insert(cur_group, pn)
            end
        else
            if #cur_group >= 2 then
                table.insert(beam_groups, cur_group)
            end
            cur_group = {}
            cur_beat = nil
        end
    end
    if #cur_group >= 2 then
        table.insert(beam_groups, cur_group)
    end

    local beamed_map = {}

    -- 5. Draw Beams
    for _, bgroup in ipairs(beam_groups) do
        local sum_step = 0
        for _, bn in ipairs(bgroup) do sum_step = sum_step + bn.step_offset end
        local stem_down = (sum_step / #bgroup >= 4)
        local dir = stem_down and 1 or -1

        for _, bn in ipairs(bgroup) do
            bn.stem_down = stem_down
            bn.stem_x = bn.nx + (stem_down and -3.2 or 3.2)
            beamed_map[bn.key] = true
        end

        local first_n = bgroup[1]
        local last_n = bgroup[#bgroup]
        local sx1 = first_n.stem_x
        local sx2 = last_n.stem_x
        local dx = math.max(1.0, sx2 - sx1)

        local raw_slope = (last_n.ny - first_n.ny) / dx
        local slope = math.max(-0.25, math.min(0.25, raw_slope))

        local std_stem_len = 3.5 * staff_ls
        local beam_y1
        if stem_down then
            local max_needed = -math.huge
            for _, bn in ipairs(bgroup) do
                local needed = (bn.ny + std_stem_len) - slope * (bn.stem_x - sx1)
                if needed > max_needed then max_needed = needed end
            end
            beam_y1 = max_needed
        else
            local min_needed = math.huge
            for _, bn in ipairs(bgroup) do
                local needed = (bn.ny - std_stem_len) - slope * (bn.stem_x - sx1)
                if needed < min_needed then min_needed = needed end
            end
            beam_y1 = min_needed
        end
        local beam_y2 = beam_y1 + slope * (sx2 - sx1)

        -- Primary beam quad
        local b_th = 0.55 * staff_ls
        page:set_fill_color(0.1, 0.1, 0.1)
        page:beam_quad(sx1, beam_y1, sx2, beam_y2, b_th, dir)

        -- Secondary beam for 16th notes
        local has_16th = false
        for _, bn in ipairs(bgroup) do
            if bn.dur_qn <= 0.45 then has_16th = true break end
        end
        if has_16th then
            local sec_offset = -dir * 0.85 * staff_ls
            page:beam_quad(sx1, beam_y1 + sec_offset, sx2, beam_y2 + sec_offset, b_th, dir)
        end

        -- Connect stems to beam
        page:set_stroke_color(0.1, 0.1, 0.1)
        page:set_line_width(0.95)
        for _, bn in ipairs(bgroup) do
            local cur_by = beam_y1 + slope * (bn.stem_x - sx1)
            page:line(bn.stem_x, bn.ny, bn.stem_x, cur_by)
        end
    end

    -- 6. Draw Individual Notes
    for _, pn in ipairs(page_notes) do
        -- Notehead via Bravura SMuFL
        local note_gid = pn.is_whole and BRAVURA_GIDS.note_whole or (pn.is_half and BRAVURA_GIDS.note_half or BRAVURA_GIDS.note_black)
        page:set_fill_color(0.1, 0.1, 0.1)
        page:bravura_glyph(note_gid, clef_font_sz, pn.nx - 3.5, pn.ny)

        -- Accidental
        if pn.acc and pn.acc ~= 0 then
            local acc_gid = (pn.acc == 1) and BRAVURA_GIDS.acc_sharp or ((pn.acc == -1) and BRAVURA_GIDS.acc_flat or BRAVURA_GIDS.acc_natural)
            page:bravura_glyph(acc_gid, clef_font_sz, pn.nx - 11.5, pn.ny)
        end

        -- Stem & Flag (if not beamed and not whole note)
        if not pn.is_whole and not beamed_map[pn.key] then
            local stem_down = (pn.dstep >= 4)
            local stem_x = stem_down and (pn.nx - 3.2) or (pn.nx + 3.2)
            local stem_len = 3.5 * staff_ls
            local stem_end_y = stem_down and (pn.ny + stem_len) or (pn.ny - stem_len)
            page:set_stroke_color(0.1, 0.1, 0.1)
            page:set_line_width(0.95)
            page:line(stem_x, pn.ny, stem_x, stem_end_y)

            -- Flags for isolated 8th / 16th notes
            if pn.dur_qn <= 0.45 then
                page:bravura_glyph(stem_down and BRAVURA_GIDS.flag16thDown or BRAVURA_GIDS.flag16thUp, clef_font_sz, stem_x, stem_end_y)
            elseif pn.dur_qn <= 0.85 then
                page:bravura_glyph(stem_down and BRAVURA_GIDS.flag8thDown or BRAVURA_GIDS.flag8thUp, clef_font_sz, stem_x, stem_end_y)
            end
        end

        -- Dotted note
        local dotted_vals = { 6.0, 3.0, 1.5, 0.75, 0.375, 0.1875 }
        local is_dotted = false
        for _, dv in ipairs(dotted_vals) do
            if math.abs(pn.dur_qn - dv) < math.min(0.02, dv * 0.05) then is_dotted = true break end
        end
        if is_dotted then
            page:set_fill_color(0.1, 0.1, 0.1)
            page:ellipse(pn.nx + 6.0, pn.ny - 1.2, 1.3, 1.3, true, false)
        end

        -- Ledger lines
        if pn.dstep <= -2 then
            for ls = -2, pn.dstep, -2 do
                local ly = target_bot_y - (ls * (staff_ls * 0.5))
                page:set_stroke_color(0.2, 0.2, 0.2)
                page:set_line_width(0.75)
                page:line(pn.nx - 6.5, ly, pn.nx + 6.5, ly)
            end
        elseif pn.dstep >= 10 then
            for ls = 10, pn.dstep, 2 do
                local ly = target_bot_y - (ls * (staff_ls * 0.5))
                page:set_stroke_color(0.2, 0.2, 0.2)
                page:set_line_width(0.75)
                page:line(pn.nx - 6.5, ly, pn.nx + 6.5, ly)
            end
        end
    end

    -- 7. Draw Ties across barlines
    local notes_by_key = {}
    for _, pn in ipairs(page_notes) do
        if pn.orig and pn.orig.seg_key then
            notes_by_key[pn.orig.seg_key] = pn
        end
        notes_by_key[pn.key] = pn
    end

    if bar_ties then
        page:set_stroke_color(0.1, 0.1, 0.1)
        page:set_line_width(0.9)
        for _, bt in ipairs(bar_ties) do
            local n1 = notes_by_key[bt.from_key]
            local n2 = notes_by_key[bt.to_key]
            if n1 and n2 then
                local dir = (n1.step_offset < 4) and 1 or -1
                page:tie(n1.nx + 3.5, n1.ny + (dir * 2.0), n2.nx - 3.5, n2.ny + (dir * 2.0), dir)
            end
        end
    end

    -- 8. Dynamics (p, mp, mf, f etc.)
    if dynamics and #dynamics > 0 then
        local dy = target_bot_y + (16 * eng_s)
        for _, d in ipairs(dynamics) do
            if d.qn and d.qn >= (start_qn_page - 0.1) and d.qn < end_qn_page then
                local dx = SystemEngraver.qn_to_page_x(d.qn, mmap, eng_s)
                page:set_fill_color(0.1, 0.1, 0.1)
                page:text("Times-BoldItalic", 10.5, dx, dy, d.label or "f", "center")
            end
        end
    end

    -- 9. Hairpins (< and >)
    if track_guid and state then
        local track_hairpins = HairpinService.get_hairpins_for_track(state, track_guid)
        if track_hairpins and #track_hairpins > 0 then
            local hp_y_mid = target_bot_y + (15 * eng_s)
            page:set_stroke_color(0.1, 0.1, 0.1)
            page:set_line_width(0.85)

            for _, hp in ipairs(track_hairpins) do
                local cur_s = hp.start_qn or 0
                local cur_e = hp.end_qn or (cur_s + 1.0)
                if cur_e > start_qn_page and cur_s < end_qn_page then
                    local matches_staff = true
                    if clef_type == "treble" and hp.staff == "bass" then
                        matches_staff = false
                    elseif clef_type == "bass" and hp.staff == "treble" then
                        matches_staff = false
                    end

                    if matches_staff then
                        local raw_x1 = SystemEngraver.qn_to_page_x(math.max(start_qn_page, cur_s), mmap, eng_s)
                        local raw_x2 = SystemEngraver.qn_to_page_x(math.min(end_qn_page, cur_e), mmap, eng_s)
                        local x1 = raw_x1 + 4.0
                        local x2 = math.max(x1 + 8.0, raw_x2 - 4.0)

                        if hp.type == "crescendo" then
                            page:line(x1, hp_y_mid - 0.5, x2, hp_y_mid - 4.0)
                            page:line(x1, hp_y_mid + 0.5, x2, hp_y_mid + 4.0)
                        else
                            page:line(x1, hp_y_mid - 4.0, x2, hp_y_mid - 0.5)
                            page:line(x1, hp_y_mid + 4.0, x2, hp_y_mid + 0.5)
                        end
                    end
                end
            end
        end

        -- 9. Octave Lines (8va, 8vb etc.)
        local OctaveService = require("services.octave_service")
        local track_oct_lines = (OctaveService and OctaveService.get_lines_for_track) and OctaveService.get_lines_for_track(state, track_guid) or {}
        for _, oline in ipairs(track_oct_lines) do
            local cur_s = oline.start_qn or 0
            local cur_e = oline.end_qn or (cur_s + 4.0)
            if cur_e > start_qn_page and cur_s < end_qn_page then
                local odef = Constants.OCTAVE_LINE_DEFS[oline.type] or Constants.OCTAVE_LINE_DEFS["8va"]
                local is_below = (odef and (odef.placement == "below" or odef.corner == "bottom")) or (oline.type and oline.type:find("vb") ~= nil)
                local o_y = is_below and (target_bot_y + 14 * eng_s) or (target_bot_y - 4 * staff_ls - 12 * eng_s)
                local ox1 = SystemEngraver.qn_to_page_x(math.max(start_qn_page, cur_s), mmap, eng_s)
                local ox2 = SystemEngraver.qn_to_page_x(math.min(end_qn_page, cur_e), mmap, eng_s)
                if ox2 > ox1 + 4 then
                    local lbl_text = (odef and odef.label) or "8"
                    page:set_fill_color(0.15, 0.15, 0.15)
                    page:text("Times-Italic", 9.0 * eng_s, ox1, o_y + 2, lbl_text, "left")
                    local cur_lx = ox1 + 10 * eng_s
                    local dash_len = 4.0
                    local dash_gap = 3.0
                    page:set_stroke_color(0.2, 0.2, 0.2)
                    page:set_line_width(0.7)
                    while cur_lx + dash_len <= ox2 do
                        page:line(cur_lx, o_y, cur_lx + dash_len, o_y)
                        cur_lx = cur_lx + dash_len + dash_gap
                    end
                    if cur_lx < ox2 then
                        page:line(cur_lx, o_y, ox2, o_y)
                    end
                    local hook_len = is_below and -5.0 or 5.0
                    page:line(ox2, o_y, ox2, o_y + hook_len)
                end
            end
        end
    end
end

-- ------------------------------------------------------------------------------
-- PAGES 3+: Paginated Full Score Pages with Grand Staff & Bravura SMuFL
-- ------------------------------------------------------------------------------
local function render_score_pages(doc, s, project_tracks, midi_service, state)
    local pw, ph = doc.w, doc.h
    local bars_per_page = tonumber(s.bars_per_page) or 5
    if bars_per_page < 1 then bars_per_page = 5 end

    local margin_r = 30
    local margin_t = 52
    local margin_b = 36

    -- Build structured staff layout (supporting Grand Staff as 2 staves)
    local qn_per_measure = 4.0
    local max_qn = 16.0
    local track_entries = {}

    for i, t in ipairs(project_tracks) do
        local _, tname = reaper.GetTrackName(t.track)
        tname = (tname and tname ~= "") and tname or ("Track " .. i)
        local tname_l = tname:lower()
        if not (tname_l:find("chord") or tname_l:find("akkord") or tname_l:find("scale track")) then
            local items, trk_notes, dyns, arts, t_max = midi_service.get_track_items_and_notes(t.track)
            max_qn = math.max(max_qn, t_max or 0.0)

            local clef_mode = get_track_clef_mode(t.track, tname, trk_notes, state)
            local is_grand = (clef_mode == "grand")

            table.insert(track_entries, {
                track = t.track,
                guid = reaper.GetTrackGUID(t.track),
                name = tname,
                clef = clef_mode,
                is_grand = is_grand,
                notes = trk_notes or {},
                dynamics = dyns or {}
            })
        end
    end

    -- Calculate maximum track name width to ensure zero left-clipping
    local max_name_w = 0
    for _, te in ipairs(track_entries) do
        local w = #te.name * 5.2
        if w > max_name_w then max_name_w = w end
    end
    local margin_l = math.max(135.0, math.min(185.0, max_name_w + 24.0))
    local score_w = pw - margin_l - margin_r

    -- Calculate total staves across all tracks
    local total_staves = 0
    for _, te in ipairs(track_entries) do
        total_staves = total_staves + (te.is_grand and 2 or 1)
    end
    if total_staves == 0 then total_staves = 1 end

    local total_measures = math.max(bars_per_page, math.ceil(max_qn / qn_per_measure))
    local total_score_pages = math.ceil(total_measures / bars_per_page)

    local page_offset = 0
    if s.include_cover ~= false then page_offset = page_offset + 1 end
    if s.include_notes_page ~= false then page_offset = page_offset + 1 end

    -- Vertical staff distribution filling the page height
    local avail_h = ph - margin_t - margin_b
    local staff_ls = 5.8 -- line spacing in pt (staff height = 4 * 5.8 = 23.2 pt)
    local staff_h = 4 * staff_ls
    local grand_inner_gap = 22.0

    -- Count grand staffs
    local grand_count = 0
    for _, te in ipairs(track_entries) do
        if te.is_grand then grand_count = grand_count + 1 end
    end

    local track_count = #track_entries
    local inter_track_gaps_count = math.max(1, track_count - 1)
    local used_by_staves = (total_staves * staff_h) + (grand_count * grand_inner_gap)
    local inter_track_gap = math.max(16.0, (avail_h - used_by_staves) / inter_track_gaps_count)

    -- If total height exceeds available, adjust spacing
    if (used_by_staves + (inter_track_gap * inter_track_gaps_count)) > avail_h then
        staff_ls = math.max(4.0, (avail_h / total_staves) * 0.16)
        staff_h = 4 * staff_ls
        grand_inner_gap = math.max(12.0, staff_h * 0.8)
        used_by_staves = (total_staves * staff_h) + (grand_count * grand_inner_gap)
        inter_track_gap = math.max(10.0, (avail_h - used_by_staves) / inter_track_gaps_count)
    end

    -- Precompute Y positions for all tracks and staves
    local cur_top_y = margin_t
    for _, te in ipairs(track_entries) do
        if te.is_grand then
            te.upper_top_y = cur_top_y
            te.upper_bot_y = cur_top_y + staff_h
            te.lower_top_y = te.upper_bot_y + grand_inner_gap
            te.lower_bot_y = te.lower_top_y + staff_h
            te.center_y    = (te.upper_bot_y + te.lower_top_y) * 0.5
            cur_top_y      = te.lower_bot_y + inter_track_gap
        else
            te.top_y    = cur_top_y
            te.bot_y    = cur_top_y + staff_h
            te.center_y = cur_top_y + (staff_h * 0.5)
            cur_top_y   = te.bot_y + inter_track_gap
        end
    end

    local overall_top_y = track_entries[1] and (track_entries[1].is_grand and track_entries[1].upper_top_y or track_entries[1].top_y) or margin_t
    local last_te = track_entries[#track_entries]
    local overall_bot_y = last_te and (last_te.is_grand and last_te.lower_bot_y or last_te.bot_y) or (ph - margin_b)

    -- Render each score page
    for sp_idx = 1, total_score_pages do
        local page = doc:add_page()
        local cur_page_num = page_offset + sp_idx
        local start_m = (sp_idx - 1) * bars_per_page
        local end_m = math.min(total_measures, start_m + bars_per_page)
        local page_bars = end_m - start_m
        if page_bars <= 0 then page_bars = 1 end
        local eng_s = staff_ls / 8.0
        local mmap = SystemEngraver.build_page_measure_map(track_entries, start_m, end_m, margin_l, score_w, eng_s, state)

        -- 1. Running Header
        page:set_fill_color(0.2, 0.2, 0.2)
        local ptitle = s.title or "Score"
        page:text("Times-Italic", 9.5, margin_l, 32, ptitle, "left")
        page:text("Times-Roman", 9.5, pw - margin_r, 32, string.format("- %d -", cur_page_num), "right")

        -- 2. Master System Bracket on the left (connecting all staves)
        page:set_stroke_color(0.1, 0.1, 0.1)
        page:set_line_width(2.6)
        page:line(margin_l - 6, overall_top_y, margin_l - 6, overall_bot_y)
        page:set_line_width(1.2)
        page:line(margin_l - 6, overall_top_y, margin_l - 1, overall_top_y)
        page:line(margin_l - 6, overall_bot_y, margin_l - 1, overall_bot_y)
        -- Initial System Barline connecting all staves at left margin
        page:set_stroke_color(0.15, 0.15, 0.15)
        page:set_line_width(0.9)
        page:line(margin_l, overall_top_y, margin_l, overall_bot_y)

        -- Measure Numbers above top staff
        if s.show_measure_nums ~= false then
            page:set_fill_color(0.1, 0.1, 0.1)
            for bi = 0, page_bars - 1 do
                local bx = mmap.starts[bi]
                local m_num = start_m + bi + 1
                page:text("Times-Bold", 9, bx + 2, overall_top_y - 7, tostring(m_num))
            end
        end

        -- 3. Render Each Track
        for _, te in ipairs(track_entries) do
            if te.is_grand then
                -- === GRAND STAFF (TREBLE + BASS) ===
                -- Instrument Name (vertically centered between the two staves)
                page:set_fill_color(0.12, 0.12, 0.12)
                page:text("Times-Bold", 9.5, margin_l - 24, te.center_y - 4, te.name, "right")

                -- Acoustic brace on left connecting Treble to Bass staff
                page:set_stroke_color(0.1, 0.1, 0.1)
                page:set_line_width(2.2)
                page:line(margin_l - 12, te.upper_top_y, margin_l - 12, te.lower_bot_y)
                page:set_line_width(1.0)
                page:line(margin_l - 12, te.upper_top_y, margin_l - 7, te.upper_top_y)
                page:line(margin_l - 12, te.lower_bot_y, margin_l - 7, te.lower_bot_y)
                page:line(margin_l - 16, te.center_y, margin_l - 12, te.center_y)

                -- Draw 5 lines for Upper Staff (Treble)
                page:set_stroke_color(0.25, 0.25, 0.25)
                page:set_line_width(0.7)
                for li = 0, 4 do
                    local ly = te.upper_bot_y - (li * staff_ls)
                    page:line(margin_l, ly, margin_l + score_w, ly)
                end

                -- Draw 5 lines for Lower Staff (Bass)
                for li = 0, 4 do
                    local ly = te.lower_bot_y - (li * staff_ls)
                    page:line(margin_l, ly, margin_l + score_w, ly)
                end

                -- Initial barline at left margin for Grand Staff
                page:set_stroke_color(0.15, 0.15, 0.15)
                page:set_line_width(0.9)
                page:line(margin_l, te.upper_top_y, margin_l, te.lower_bot_y)

                -- Barlines across both staves (continuous through Grand Staff)
                for bi = 1, page_bars do
                    local bx = mmap.starts[bi]
                    page:line(bx, te.upper_top_y, bx, te.lower_bot_y)
                end

                -- Clefs via Bravura OpenType SMuFL
                local clef_font_sz = staff_h
                local clef_draw_x = margin_l + (4.0 * eng_s)
                -- Treble Clef on Upper Staff: origin on Line 2 (G4)
                local g4_line_y = te.upper_bot_y - staff_ls
                page:set_fill_color(0.1, 0.1, 0.1)
                page:bravura_glyph(BRAVURA_GIDS.g_clef, clef_font_sz, clef_draw_x, g4_line_y)

                -- Bass Clef on Lower Staff: origin on Line 4 (F3)
                local f3_line_y = te.lower_bot_y - (3 * staff_ls)
                page:bravura_glyph(BRAVURA_GIDS.f_clef, clef_font_sz, clef_draw_x, f3_line_y)

                -- Key Signature via Bravura OpenType SMuFL on all systems
                local key_idx = mmap.key_idx or 0
                if key_idx ~= 0 then
                    local keysig_draw_x = margin_l + (24.0 * eng_s)
                    render_pdf_key_signature(page, key_idx, keysig_draw_x, te.upper_bot_y, staff_ls, clef_font_sz, eng_s, "treble")
                    render_pdf_key_signature(page, key_idx, keysig_draw_x, te.lower_bot_y, staff_ls, clef_font_sz, eng_s, "bass")
                end

                -- Time Signature (4/4) at start of bar 1 on Page 1
                if start_m == 0 then
                    local ts_x = margin_l + (28.0 * eng_s) + (mmap.key_sig_w or 0)
                    page:bravura_glyph(BRAVURA_GIDS.time_sig_common, clef_font_sz, ts_x, te.upper_bot_y - (2 * staff_ls))
                    page:bravura_glyph(BRAVURA_GIDS.time_sig_common, clef_font_sz, ts_x, te.lower_bot_y - (2 * staff_ls))
                end

                -- Notes for Grand Staff (>= 60 in Treble, < 60 in Bass)
                local upper_notes = {}
                local lower_notes = {}
                for _, n in ipairs(te.notes or {}) do
                    local eff_pitch = Engraver.get_note_effective_pitch(n.pitch, n.start_qn, te.guid, state)
                    if eff_pitch >= 60 then
                        table.insert(upper_notes, n)
                    else
                        table.insert(lower_notes, n)
                    end
                end

                render_pdf_staff_notes(page, upper_notes, start_m, end_m, mmap, te.upper_bot_y, staff_ls, clef_font_sz, "treble", state, te.guid, te.dynamics)
                render_pdf_staff_notes(page, lower_notes, start_m, end_m, mmap, te.lower_bot_y, staff_ls, clef_font_sz, "bass", state, te.guid, nil)

            else
                -- === SINGLE STAFF (TREBLE / BASS / ALTO) ===
                page:set_fill_color(0.12, 0.12, 0.12)
                page:text("Times-Bold", 9.5, margin_l - 18, te.center_y - 3, te.name, "right")

                -- 5 Staff lines
                page:set_stroke_color(0.25, 0.25, 0.25)
                page:set_line_width(0.7)
                for li = 0, 4 do
                    local ly = te.bot_y - (li * staff_ls)
                    page:line(margin_l, ly, margin_l + score_w, ly)
                end

                -- Initial barline at left margin
                page:set_stroke_color(0.15, 0.15, 0.15)
                page:set_line_width(0.9)
                page:line(margin_l, te.top_y, margin_l, te.bot_y)

                -- Barlines across this staff
                for bi = 1, page_bars do
                    local bx = mmap.starts[bi]
                    page:line(bx, te.top_y, bx, te.bot_y)
                end

                -- Clef symbol via Bravura OpenType SMuFL
                local clef_font_sz = staff_h
                local clef_draw_x = margin_l + (4.0 * eng_s)
                page:set_fill_color(0.1, 0.1, 0.1)
                if te.clef == "bass" then
                    local f3_line_y = te.bot_y - (3 * staff_ls)
                    page:bravura_glyph(BRAVURA_GIDS.f_clef, clef_font_sz, clef_draw_x, f3_line_y)
                elseif te.clef == "alto" then
                    local c4_line_y = te.bot_y - (2 * staff_ls)
                    page:bravura_glyph(BRAVURA_GIDS.c_clef, clef_font_sz, clef_draw_x, c4_line_y)
                else
                    local g4_line_y = te.bot_y - staff_ls
                    page:bravura_glyph(BRAVURA_GIDS.g_clef, clef_font_sz, clef_draw_x, g4_line_y)
                end

                -- Key Signature via Bravura OpenType SMuFL on all systems
                local key_idx = mmap.key_idx or 0
                if key_idx ~= 0 then
                    local keysig_draw_x = margin_l + (24.0 * eng_s)
                    render_pdf_key_signature(page, key_idx, keysig_draw_x, te.bot_y, staff_ls, clef_font_sz, eng_s, te.clef or "treble")
                end

                -- Time Signature on Bar 1
                if start_m == 0 then
                    local ts_x = margin_l + (28.0 * eng_s) + (mmap.key_sig_w or 0)
                    page:bravura_glyph(BRAVURA_GIDS.time_sig_common, clef_font_sz, ts_x, te.bot_y - (2 * staff_ls))
                end

                -- Notes for Single Staff
                render_pdf_staff_notes(page, te.notes, start_m, end_m, mmap, te.bot_y, staff_ls, clef_font_sz, te.clef, state, te.guid, te.dynamics)
            end
        end

        -- Final double barline at end of piece
        if end_m >= total_measures then
            local ex = margin_l + score_w
            page:set_stroke_color(0.1, 0.1, 0.1)
            page:set_line_width(2.5)
            page:line(ex, overall_top_y, ex, overall_bot_y)
        end
    end
end

-- ------------------------------------------------------------------------------
-- Main Export Function: Builds the complete document and writes to file
-- ------------------------------------------------------------------------------
function PdfExportService.export_score_to_pdf(state, midi_service, project_tracks, target_filepath)
    local s = state.print_settings or {}
    local paper_size = s.paper_size or "A4"
    local orientation = s.orientation or "landscape"

    local doc = new_pdf_doc(paper_size, orientation)

    -- Page 1: Title & Cover
    if s.include_cover ~= false then
        render_title_page(doc, s)
    end

    -- Page 2: Orchestration & Notes Page
    if s.include_notes_page ~= false then
        render_notes_page(doc, s, project_tracks)
    end

    -- Score Pages (5 Bars per Page)
    render_score_pages(doc, s, project_tracks, midi_service, state)

    -- Write PDF bytes to file
    local bytes = doc:generate_bytes()
    local f, err = io.open(target_filepath, "wb")
    if not f then
        state.status_msg = "PDF Export Error: " .. tostring(err)
        return false, err
    end

    f:write(bytes)
    f:close()

    state.status_msg = string.format("PDF Export successful: %s (%d pages)", target_filepath:match("([^/\\]+)$") or "Score.pdf", #doc.pages)
    return true, target_filepath, #doc.pages
end

-- ------------------------------------------------------------------------------
-- Open PDF in system default PDF reader
-- ------------------------------------------------------------------------------
function PdfExportService.open_in_system_viewer(filepath)
    if not filepath or filepath == "" then return end
    if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute(filepath)
    else
        local cmd = string.format('start "" "%s"', filepath:gsub("/", "\\"))
        os.execute(cmd)
    end
end

return PdfExportService

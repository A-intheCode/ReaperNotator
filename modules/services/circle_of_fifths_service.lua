-- ==============================================================================
-- REAPER Native Notator - Service: CircleOfFifthsService
-- Interactive Circle of Fifths data model, dynamic harmonic tension calculator,
-- chord/note voicing generator, global REAPER ExtState palette persistence
-- (multi-tab 8-tile pages), auditioning, and score insertion (incl. Auto-Divisi).
-- ==============================================================================

local JsonHelper = require("services.json_helper")
local AudioPreview = require("services.audio_preview")

local CircleOfFifthsService = {}

CircleOfFifthsService.EXT_SECTION = "REAPER_Notator"
CircleOfFifthsService.EXT_KEY = "circle_of_fifths_palettes_v1"

-- Unified 12-Sector Circle of Fifths Definition (12 o'clock = C Major / A Minor, clockwise by Perfect Fifths)
CircleOfFifthsService.SECTORS = {
    { idx = 1,  fifth_pos = 0,  major_label = "C",  minor_label = "Am",  major_pc = 0,  minor_pc = 9,  key_sig_idx = 0,  acc_label = "0♯/♭" },
    { idx = 2,  fifth_pos = 1,  major_label = "G",  minor_label = "Em",  major_pc = 7,  minor_pc = 4,  key_sig_idx = 1,  acc_label = "1♯"   },
    { idx = 3,  fifth_pos = 2,  major_label = "D",  minor_label = "Bm",  major_pc = 2,  minor_pc = 11, key_sig_idx = 2,  acc_label = "2♯"   },
    { idx = 4,  fifth_pos = 3,  major_label = "A",  minor_label = "F#m", major_pc = 9,  minor_pc = 6,  key_sig_idx = 3,  acc_label = "3♯"   },
    { idx = 5,  fifth_pos = 4,  major_label = "E",  minor_label = "C#m", major_pc = 4,  minor_pc = 1,  key_sig_idx = 4,  acc_label = "4♯"   },
    { idx = 6,  fifth_pos = 5,  major_label = "B",  minor_label = "G#m", major_pc = 11, minor_pc = 8,  key_sig_idx = 5,  acc_label = "5♯"   },
    { idx = 7,  fifth_pos = 6,  major_label = "F#", minor_label = "D#m", major_pc = 6,  minor_pc = 3,  key_sig_idx = 6,  acc_label = "6♯/6♭"},
    { idx = 8,  fifth_pos = 7,  major_label = "Db", minor_label = "Bbm", major_pc = 1,  minor_pc = 10, key_sig_idx = -5, acc_label = "5♭"   },
    { idx = 9,  fifth_pos = 8,  major_label = "Ab", minor_label = "Fm",  major_pc = 8,  minor_pc = 5,  key_sig_idx = -4, acc_label = "4♭"   },
    { idx = 10, fifth_pos = 9,  major_label = "Eb", minor_label = "Cm",  major_pc = 3,  minor_pc = 0,  key_sig_idx = -3, acc_label = "3♭"   },
    { idx = 11, fifth_pos = 10, major_label = "Bb", minor_label = "Gm",  major_pc = 10, minor_pc = 7,  key_sig_idx = -2, acc_label = "2♭"   },
    { idx = 12, fifth_pos = 11, major_label = "F",  minor_label = "Dm",  major_pc = 5,  minor_pc = 2,  key_sig_idx = -1, acc_label = "1♭"   },
}

-- 12 Outer Ring Sectors (Major keys / roots ordered clockwise around the Circle of Fifths, 12 o'clock = C)
CircleOfFifthsService.OUTER_SECTORS = {
    { idx = 1,  fifth_pos = 0,  pc = 0,  name = "C",  alt_name = "C",  key_sig_idx = 0,  sig_label = "0♯/♭", mode = "major", quality = "major" },
    { idx = 2,  fifth_pos = 1,  pc = 7,  name = "G",  alt_name = "G",  key_sig_idx = 1,  sig_label = "1♯",   mode = "major", quality = "major" },
    { idx = 3,  fifth_pos = 2,  pc = 2,  name = "D",  alt_name = "D",  key_sig_idx = 2,  sig_label = "2♯",   mode = "major", quality = "major" },
    { idx = 4,  fifth_pos = 3,  pc = 9,  name = "A",  alt_name = "A",  key_sig_idx = 3,  sig_label = "3♯",   mode = "major", quality = "major" },
    { idx = 5,  fifth_pos = 4,  pc = 4,  name = "E",  alt_name = "E",  key_sig_idx = 4,  sig_label = "4♯",   mode = "major", quality = "major" },
    { idx = 6,  fifth_pos = 5,  pc = 11, name = "B",  alt_name = "Cb", key_sig_idx = 5,  sig_label = "5♯",   mode = "major", quality = "major" },
    { idx = 7,  fifth_pos = 6,  pc = 6,  name = "F#", alt_name = "Gb", key_sig_idx = 6,  sig_label = "6♯/6♭",mode = "major", quality = "major" },
    { idx = 8,  fifth_pos = 7,  pc = 1,  name = "Db", alt_name = "C#", key_sig_idx = -5, sig_label = "5♭",   mode = "major", quality = "major" },
    { idx = 9,  fifth_pos = 8,  pc = 8,  name = "Ab", alt_name = "G#", key_sig_idx = -4, sig_label = "4♭",   mode = "major", quality = "major" },
    { idx = 10, fifth_pos = 9,  pc = 3,  name = "Eb", alt_name = "D#", key_sig_idx = -3, sig_label = "3♭",   mode = "major", quality = "major" },
    { idx = 11, fifth_pos = 10, pc = 10, name = "Bb", alt_name = "A#", key_sig_idx = -2, sig_label = "2♭",   mode = "major", quality = "major" },
    { idx = 12, fifth_pos = 11, pc = 5,  name = "F",  alt_name = "F",  key_sig_idx = -1, sig_label = "1♭",   mode = "major", quality = "major" },
}

-- 12 Inner Ring Sectors (Relative Minor keys / roots ordered clockwise, 12 o'clock = Am)
CircleOfFifthsService.INNER_SECTORS = {
    { idx = 1,  fifth_pos = 0,  pc = 9,  name = "Am",  root_name = "A",  key_sig_idx = 0,  sig_label = "0♯/♭", mode = "minor", quality = "minor" },
    { idx = 2,  fifth_pos = 1,  pc = 4,  name = "Em",  root_name = "E",  key_sig_idx = 1,  sig_label = "1♯",   mode = "minor", quality = "minor" },
    { idx = 3,  fifth_pos = 2,  pc = 11, name = "Bm",  root_name = "B",  key_sig_idx = 2,  sig_label = "2♯",   mode = "minor", quality = "minor" },
    { idx = 4,  fifth_pos = 3,  pc = 6,  name = "F#m", root_name = "F#", key_sig_idx = 3,  sig_label = "3♯",   mode = "minor", quality = "minor" },
    { idx = 5,  fifth_pos = 4,  pc = 1,  name = "C#m", root_name = "C#", key_sig_idx = 4,  sig_label = "4♯",   mode = "minor", quality = "minor" },
    { idx = 6,  fifth_pos = 5,  pc = 8,  name = "G#m", root_name = "G#", key_sig_idx = 5,  sig_label = "5♯",   mode = "minor", quality = "minor" },
    { idx = 7,  fifth_pos = 6,  pc = 3,  name = "D#m", root_name = "D#", key_sig_idx = 6,  sig_label = "6♯/6♭",mode = "minor", quality = "minor" },
    { idx = 8,  fifth_pos = 7,  pc = 10, name = "Bbm", root_name = "Bb", key_sig_idx = -5, sig_label = "5♭",   mode = "minor", quality = "minor" },
    { idx = 9,  fifth_pos = 8,  pc = 5,  name = "Fm",  root_name = "F",  key_sig_idx = -4, sig_label = "4♭",   mode = "minor", quality = "minor" },
    { idx = 10, fifth_pos = 9,  pc = 0,  name = "Cm",  root_name = "C",  key_sig_idx = -3, sig_label = "3♭",   mode = "minor", quality = "minor" },
    { idx = 11, fifth_pos = 10, pc = 7,  name = "Gm",  root_name = "G",  key_sig_idx = -2, sig_label = "2♭",   mode = "minor", quality = "minor" },
    { idx = 12, fifth_pos = 11, pc = 2,  name = "Dm",  root_name = "D",  key_sig_idx = -1, sig_label = "1♭",   mode = "minor", quality = "minor" },
}

CircleOfFifthsService.CHORD_QUALITIES = {
    single = { id = "single", label = "Single Note",    suffix = "",     intervals = { 0 } },
    major  = { id = "major",  label = "Major Triad",    suffix = "",     intervals = { 0, 4, 7 } },
    minor  = { id = "minor",  label = "Minor Triad",    suffix = "m",    intervals = { 0, 3, 7 } },
    dim    = { id = "dim",    label = "Diminished",     suffix = "dim",  intervals = { 0, 3, 6 } },
    aug    = { id = "aug",    label = "Augmented",      suffix = "aug",  intervals = { 0, 4, 8 } },
    maj7   = { id = "maj7",   label = "Major 7th",      suffix = "maj7", intervals = { 0, 4, 7, 11 } },
    m7     = { id = "m7",     label = "Minor 7th",      suffix = "m7",   intervals = { 0, 3, 7, 10 } },
    dom7   = { id = "dom7",   label = "Dominant 7th",   suffix = "7",    intervals = { 0, 4, 7, 10 } },
    sus2   = { id = "sus2",   label = "Suspended 2nd",  suffix = "sus2", intervals = { 0, 2, 7 } },
    sus4   = { id = "sus4",   label = "Suspended 4th",  suffix = "sus4", intervals = { 0, 5, 7 } },
    power5 = { id = "power5", label = "Power 5th",      suffix = "5",    intervals = { 0, 7 } },
}

CircleOfFifthsService.QUALITY_ORDER = {
    "single", "major", "minor", "dim", "aug", "maj7", "m7", "dom7", "sus2", "sus4", "power5"
}

local PC_TO_FIFTH_POS = {
    [0]  = 0,  -- C
    [7]  = 1,  -- G
    [2]  = 2,  -- D
    [9]  = 3,  -- A
    [4]  = 4,  -- E
    [11] = 5,  -- B
    [6]  = 6,  -- F# / Gb
    [1]  = 7,  -- Db / C#
    [8]  = 8,  -- Ab / G#
    [3]  = 9,  -- Eb / D#
    [10] = 10, -- Bb / A#
    [5]  = 11, -- F
}

local function normalize_ring(ring)
    if ring == "inner" or ring == "minor" then return "minor" end
    return "major"
end

function CircleOfFifthsService.get_fifth_pos_for_tile(tile)
    if not tile then return 0 end
    if tile.sector_idx and CircleOfFifthsService.SECTORS[tile.sector_idx] then
        return CircleOfFifthsService.SECTORS[tile.sector_idx].fifth_pos
    end
    if tile.pc == nil then return 0 end
    local pc = tile.pc % 12
    local ring = normalize_ring(tile.ring)
    local q = tile.quality or (ring == "minor" and "minor" or "major")
    if q == "minor" or q == "m7" or (ring == "minor" and q == "single") then
        local rel_maj_pc = (pc + 3) % 12
        return PC_TO_FIFTH_POS[rel_maj_pc] or 0
    elseif q == "dim" then
        local resolved_pc = (pc + 1) % 12
        return PC_TO_FIFTH_POS[resolved_pc] or 0
    end
    return PC_TO_FIFTH_POS[pc] or 0
end

function CircleOfFifthsService.format_tile_label(tile)
    if not tile then return "Empty" end
    if tile.label and tile.label ~= "" then return tile.label end
    if tile.pc == nil then return "Empty" end
    local rname = tile.root_name or "C"
    local q = tile.quality or "major"
    local qdef = CircleOfFifthsService.CHORD_QUALITIES[q] or CircleOfFifthsService.CHORD_QUALITIES.major
    local oct = tonumber(tile.octave) or 4
    if q == "single" then
        return string.format("%s%d", rname, oct)
    end
    return string.format("%s%s", rname, qdef.suffix or "")
end

function CircleOfFifthsService.get_tile_pitches(tile)
    if not tile then return {} end
    if type(tile.pitches) == "table" and #tile.pitches > 0 then
        return tile.pitches
    end
    if tile.pc == nil then return {} end
    local pc = tile.pc % 12
    local oct = tonumber(tile.octave) or 4
    local q = tile.quality or "major"
    local qdef = CircleOfFifthsService.CHORD_QUALITIES[q] or CircleOfFifthsService.CHORD_QUALITIES.major
    local base_midi = (oct + 1) * 12 + pc
    local pitches = {}
    for _, iv in ipairs(qdef.intervals) do
        local p = math.max(0, math.min(127, base_midi + iv))
        table.insert(pitches, p)
    end
    return pitches
end

--- Creates a complete tile object from a sector index (1..12), ring ("major"|"minor"|"outer"|"inner"),
--- optional quality override, and octave (2..6).
function CircleOfFifthsService.create_tile(sector_idx, ring, quality_override, octave)
    local idx = math.max(1, math.min(12, tonumber(sector_idx) or 1))
    local norm_r = normalize_ring(ring)
    local sec = (norm_r == "minor") and CircleOfFifthsService.INNER_SECTORS[idx] or CircleOfFifthsService.OUTER_SECTORS[idx]
    local r_name = sec.root_name or sec.name or "C"
    local oct = tonumber(octave) or 4

    local q = norm_r
    if quality_override and quality_override ~= "auto" and CircleOfFifthsService.CHORD_QUALITIES[quality_override] then
        q = quality_override
    end
    local qdef = CircleOfFifthsService.CHORD_QUALITIES[q] or CircleOfFifthsService.CHORD_QUALITIES.major

    local label
    if q == "single" then
        label = string.format("%s%d", r_name, oct)
    else
        label = string.format("%s%s", r_name, qdef.suffix or "")
    end

    local base_midi = (oct + 1) * 12 + (sec.pc % 12)
    local pitches = {}
    for _, iv in ipairs(qdef.intervals) do
        table.insert(pitches, math.max(0, math.min(127, base_midi + iv)))
    end

    return {
        sector_idx = idx,
        ring = norm_r,
        pc = sec.pc,
        root_name = r_name,
        label = label,
        quality = q,
        quality_label = qdef.label,
        octave = oct,
        fifth_pos = sec.fifth_pos or (idx - 1),
        key_sig_idx = sec.key_sig_idx or 0,
        pitches = pitches
    }
end

function CircleOfFifthsService.create_tile_from_sector(sector, ring, default_quality_mode, octave)
    if not sector then return nil end
    return CircleOfFifthsService.create_tile(sector.idx or 1, ring, default_quality_mode, octave)
end

-- ==============================================================================
-- DYNAMIC HARMONIC TENSION ENGINE
-- ==============================================================================

local function circular_fifth_distance(pos_a, pos_b)
    local diff = (pos_b - pos_a) % 12
    local signed_steps = (diff <= 6) and diff or (diff - 12)
    return math.abs(signed_steps), signed_steps
end

local function compute_pitch_class_overlap(tile_a, cand_pc, cand_quality)
    if not tile_a or tile_a.pc == nil then return 0 end
    local q_a = CircleOfFifthsService.CHORD_QUALITIES[tile_a.quality or "major"] or CircleOfFifthsService.CHORD_QUALITIES.major
    local q_b = CircleOfFifthsService.CHORD_QUALITIES[cand_quality or "major"] or CircleOfFifthsService.CHORD_QUALITIES.major
    local set_a = {}
    for _, iv in ipairs(q_a.intervals) do
        set_a[(tile_a.pc + iv) % 12] = true
    end
    local shared = 0
    for _, iv in ipairs(q_b.intervals) do
        if set_a[(cand_pc + iv) % 12] then
            shared = shared + 1
        end
    end
    return shared
end

local function tension_to_color_and_tier(tension_pct, is_anchor)
    if is_anchor then
        return 0x1ABC9CFF, 0x48C9B0FF, 0xFFFFFFFF, "Active Reference (Tonic / Anchor)"
    elseif tension_pct <= 18 then
        return 0x27AE60FF, 0x2ECC71FF, 0xFFFFFFFF, "Consonant / Tonic Resolution"
    elseif tension_pct <= 32 then
        return 0x48A874FF, 0x82E0AAFF, 0x111111FF, "Diatonic (Subdominant / Dominant)"
    elseif tension_pct <= 52 then
        return 0xD4AC0DFF, 0xF7DC6FFF, 0x111111FF, "Moderate Tension (Secondary / Modal)"
    elseif tension_pct <= 75 then
        return 0xCA6F1EFF, 0xF0B27AFF, 0xFFFFFFFF, "High Tension (Chromatic Mediant)"
    else
        return 0xB03A2EFF, 0xE74C3CFF, 0xFFFFFFFF, "Maximum Tension (Tritone / Distant)"
    end
end

local function describe_harmonic_relation(signed_steps, anchor_ring, cand_ring, is_same_pc)
    local a_maj = (normalize_ring(anchor_ring) == "major")
    local c_maj = (normalize_ring(cand_ring) == "major")
    if is_same_pc and a_maj == c_maj then
        return "Unison / Tonic (I)"
    elseif signed_steps == 0 then
        if a_maj ~= c_maj then
            return (not c_maj) and "Relative Minor (vi)" or "Relative Major (III)"
        end
        return "Tonic Center (I)"
    elseif signed_steps == 1 then
        return c_maj and "Dominant (V)" or "Mediant Minor (iii)"
    elseif signed_steps == -1 then
        return c_maj and "Subdominant (IV)" or "Supertonic Minor (ii)"
    elseif signed_steps == 2 then
        return c_maj and "Secondary Dominant (V/V)" or "Leading / Lydian Minor"
    elseif signed_steps == -2 then
        return c_maj and "Subtonic / Mixolydian (bVII)" or "Parallel / Dorian Minor"
    elseif signed_steps == 3 or signed_steps == -3 then
        return "Chromatic Mediant (3 Fifths)"
    elseif signed_steps == 4 or signed_steps == -4 then
        return "Distant Mediant / Hexatonic (4 Fifths)"
    elseif signed_steps == 5 or signed_steps == -5 then
        return "Neapolitan / Leading-Tone Shift (5 Fifths)"
    else
        return "Tritone Pole (6 Fifths)"
    end
end

--- Computes the dynamic harmonic tension map for all 12 Major (outer) and 12 Minor (inner) sectors
--- based on the current 8 tiles and active reference slot.
function CircleOfFifthsService.compute_tension_map(tiles, active_slot_idx)
    local populated = {}
    local anchor_tile = nil
    local anchor_slot = nil

    if type(tiles) == "table" then
        for s_idx = 1, 8 do
            local t = tiles[s_idx]
            if t and (t.pc ~= nil or t.sector_idx ~= nil) then
                table.insert(populated, { slot = s_idx, tile = t })
                anchor_tile = t
                anchor_slot = s_idx
            end
        end
        if active_slot_idx and tiles[active_slot_idx] and (tiles[active_slot_idx].pc ~= nil or tiles[active_slot_idx].sector_idx ~= nil) then
            anchor_tile = tiles[active_slot_idx]
            anchor_slot = active_slot_idx
        end
    end

    local result = {
        has_reference = (anchor_tile ~= nil),
        ref_slot = anchor_slot,
        anchor_slot = anchor_slot,
        ref_tile = anchor_tile,
        anchor_label = anchor_tile and CircleOfFifthsService.format_tile_label(anchor_tile) or "None",
        major = {},
        minor = {},
        outer = {},
        inner = {},
        tile_step_tensions = {},
        tile_tensions = {}
    }

    if not anchor_tile then
        for i = 1, 12 do
            local m_entry = {
                tension = 0.0,
                tension_pct = 0,
                color = 0x2C3E50FF,
                fill_col = 0x2C3E50FF,
                border_col = 0x5D6D7EFF,
                text_col = 0xECF0F1FF,
                relation = "Neutral (Drop a note on a tile to calculate tension)",
                tier = "Neutral",
                is_reference = false,
                is_anchor = false
            }
            local n_entry = {
                tension = 0.0,
                tension_pct = 0,
                color = 0x212F3DFF,
                fill_col = 0x212F3DFF,
                border_col = 0x566573FF,
                text_col = 0xBDC3C7FF,
                relation = "Neutral (Drop a note on a tile to calculate tension)",
                tier = "Neutral",
                is_reference = false,
                is_anchor = false
            }
            result.major[i] = m_entry
            result.outer[i] = m_entry
            result.minor[i] = n_entry
            result.inner[i] = n_entry
        end
        return result
    end

    local anchor_fpos = CircleOfFifthsService.get_fifth_pos_for_tile(anchor_tile)
    local anchor_ring = normalize_ring(anchor_tile.ring or ((anchor_tile.quality == "minor" or anchor_tile.quality == "m7") and "minor" or "major"))
    local anchor_pc = (anchor_tile.pc or 0) % 12

    local home_tile = populated[1] and populated[1].tile or anchor_tile
    local home_fpos = CircleOfFifthsService.get_fifth_pos_for_tile(home_tile)

    local function eval_candidate(sec, ring_mode)
        local cand_fpos = sec.fifth_pos
        local dist_anchor, signed_steps = circular_fifth_distance(anchor_fpos, cand_fpos)
        local dist_home = circular_fifth_distance(home_fpos, cand_fpos)

        local chain_weighted_dist = 0
        local chain_weight_sum = 0
        for _, item in ipairs(populated) do
            if not anchor_slot or item.slot <= anchor_slot then
                local w = (item.slot == anchor_slot) and 3.5 or (item.slot == populated[1].slot and 1.0 or 0.8)
                local d = circular_fifth_distance(CircleOfFifthsService.get_fifth_pos_for_tile(item.tile), cand_fpos)
                chain_weighted_dist = chain_weighted_dist + (d * w)
                chain_weight_sum = chain_weight_sum + w
            end
        end
        local avg_chain_dist = (chain_weight_sum > 0) and (chain_weighted_dist / chain_weight_sum) or dist_anchor

        -- Base fifth-distance tension (0..6 fifths -> 0..92%)
        local local_tension = (dist_anchor / 6.0) * 90.0
        local chain_tension = (avg_chain_dist / 6.0) * 90.0
        local home_tension  = (dist_home / 6.0) * 90.0

        local raw_tension
        if #populated <= 1 then
            raw_tension = local_tension
        else
            -- Primary weight (80%) on the active/newly dropped tile so each new tile visibly re-colors the Circle!
            raw_tension = local_tension * 0.80 + chain_tension * 0.12 + home_tension * 0.08
        end

        local is_same_pc = (sec.pc == anchor_pc)
        if dist_anchor == 0 and anchor_ring ~= ring_mode then
            raw_tension = math.max(8.0, raw_tension + 8.0)
        elseif dist_anchor == 1 then
            if signed_steps == 1 and ring_mode == "major" then
                raw_tension = raw_tension + 2.0
            end
        elseif dist_anchor == 3 and anchor_ring ~= ring_mode and is_same_pc then
            raw_tension = raw_tension - 10.0
        end

        local cand_qual = (ring_mode == "minor") and "minor" or "major"
        local shared_tones = compute_pitch_class_overlap(anchor_tile, sec.pc, cand_qual)
        if shared_tones >= 2 and dist_anchor > 0 then
            raw_tension = raw_tension - 4.0
        elseif shared_tones == 0 and dist_anchor >= 4 then
            raw_tension = raw_tension + 8.0
        end

        local is_exact_anchor = is_same_pc and (anchor_ring == ring_mode)
        if is_exact_anchor then
            raw_tension = 0.0
        end

        local tension_pct = math.max(0, math.min(100, math.floor(raw_tension + 0.5)))
        local fill_c, border_c, txt_c, tier_lbl = tension_to_color_and_tier(tension_pct, is_exact_anchor)
        local rel_lbl = describe_harmonic_relation(signed_steps, anchor_ring, ring_mode, is_same_pc)

        return {
            tension = tension_pct / 100.0,
            tension_pct = tension_pct,
            color = fill_c,
            fill_col = fill_c,
            border_col = border_c,
            text_col = txt_c,
            relation = rel_lbl,
            tier = tier_lbl,
            is_reference = is_exact_anchor,
            is_anchor = is_exact_anchor,
            fifth_dist = dist_anchor,
            signed_steps = signed_steps
        }
    end

    for i, sec in ipairs(CircleOfFifthsService.OUTER_SECTORS) do
        local e = eval_candidate(sec, "major")
        result.major[i] = e
        result.outer[i] = e
    end
    for i, sec in ipairs(CircleOfFifthsService.INNER_SECTORS) do
        local e = eval_candidate(sec, "minor")
        result.minor[i] = e
        result.inner[i] = e
    end

    for idx, item in ipairs(populated) do
        if idx == 1 then
            local entry = { tension = 0.0, tension_pct = 0, relation = "Tonic (I)", label = "Tonic (I)", color = 0x27AE60EE, col = 0x2ECC71FF }
            result.tile_step_tensions[item.slot] = entry
            result.tile_tensions[item.slot] = entry
        else
            local prev_t = populated[idx - 1].tile
            local cur_t = item.tile
            local d, s_steps = circular_fifth_distance(
                CircleOfFifthsService.get_fifth_pos_for_tile(prev_t),
                CircleOfFifthsService.get_fifth_pos_for_tile(cur_t)
            )
            local step_pct = math.max(0, math.min(100, math.floor((d / 6.0) * 92.0 + ((normalize_ring(prev_t.ring) ~= normalize_ring(cur_t.ring)) and 6 or 0) + 0.5)))
            local fc, bc = tension_to_color_and_tier(step_pct, false)
            local r_lbl = describe_harmonic_relation(s_steps, prev_t.ring or "major", cur_t.ring or "major", prev_t.pc == cur_t.pc)
            local entry = {
                tension = step_pct / 100.0,
                tension_pct = step_pct,
                relation = r_lbl,
                label = r_lbl,
                color = fc,
                col = bc or fc
            }
            result.tile_step_tensions[item.slot] = entry
            result.tile_tensions[item.slot] = entry
        end
    end

    return result
end

-- ==============================================================================
-- GLOBAL REAPER EXTSTATE PALETTE PERSISTENCE (MULTI-TAB 8-TILE PAGES)
-- ==============================================================================

function CircleOfFifthsService.create_default_page(name)
    return {
        name = name or "Palette 1",
        voicing_mode = "auto",
        octave = 4,
        active_slot = 1,
        tiles = { nil, nil, nil, nil, nil, nil, nil, nil }
    }
end

function CircleOfFifthsService.load_palettes(state)
    local pages = {}
    local active_page_idx = 1
    local raw = reaper and reaper.GetExtState and reaper.GetExtState(CircleOfFifthsService.EXT_SECTION, CircleOfFifthsService.EXT_KEY) or ""
    if raw and raw ~= "" then
        local ok, data = pcall(JsonHelper.decode, raw)
        local raw_pages = (ok and type(data) == "table") and (data.pages or data) or nil
        if type(raw_pages) == "table" and #raw_pages > 0 then
            for _, p in ipairs(raw_pages) do
                local page = {
                    name = tostring(p.name or "Palette"),
                    voicing_mode = tostring(p.voicing_mode or "auto"),
                    octave = tonumber(p.octave) or 4,
                    active_slot = tonumber(p.active_slot) or 1,
                    tiles = { nil, nil, nil, nil, nil, nil, nil, nil }
                }
                if type(p.tiles) == "table" then
                    for s_idx = 1, 8 do
                        local t = p.tiles[s_idx] or p.tiles[tostring(s_idx)]
                        if type(t) == "table" and (t.sector_idx ~= nil or t.pc ~= nil) then
                            local sec_idx = tonumber(t.sector_idx)
                            if not sec_idx then
                                local fpos = tonumber(t.fifth_pos) or PC_TO_FIFTH_POS[(tonumber(t.pc) or 0) % 12] or 0
                                sec_idx = (fpos % 12) + 1
                            end
                            page.tiles[s_idx] = CircleOfFifthsService.create_tile(
                                sec_idx,
                                t.ring or "major",
                                t.quality,
                                tonumber(t.octave) or 4
                            )
                        end
                    end
                end
                table.insert(pages, page)
            end
            if type(data) == "table" and data.active_page_idx then
                active_page_idx = math.max(1, math.min(#pages, tonumber(data.active_page_idx) or 1))
            end
        end
    end

    if #pages == 0 then
        pages = { CircleOfFifthsService.create_default_page("Palette 1") }
    end

    if type(state) == "table" then
        state.cof_pages = pages
        state.cof_active_page_idx = active_page_idx
    end
    return pages
end

function CircleOfFifthsService.save_palettes(pages_or_state)
    if not pages_or_state then return false end
    local pages = pages_or_state.cof_pages or pages_or_state
    if type(pages) ~= "table" then return false end

    local export_pages = {}
    for _, p in ipairs(pages) do
        local exp_tiles = {}
        if type(p.tiles) == "table" then
            for s_idx = 1, 8 do
                local t = p.tiles[s_idx]
                if type(t) == "table" and (t.sector_idx ~= nil or t.pc ~= nil) then
                    exp_tiles[tostring(s_idx)] = {
                        sector_idx = t.sector_idx or 1,
                        pc = t.pc,
                        root_name = t.root_name,
                        label = t.label,
                        ring = t.ring,
                        fifth_pos = t.fifth_pos,
                        key_sig_idx = t.key_sig_idx,
                        quality = t.quality,
                        octave = t.octave
                    }
                end
            end
        end
        table.insert(export_pages, {
            name = p.name or "Palette",
            voicing_mode = p.voicing_mode or "auto",
            octave = p.octave or 4,
            active_slot = p.active_slot or 1,
            tiles = exp_tiles
        })
    end

    local payload = {
        version = 1,
        active_page_idx = (type(pages_or_state) == "table" and pages_or_state.cof_active_page_idx) or 1,
        pages = export_pages
    }
    local ok, json = pcall(JsonHelper.encode, payload)
    if ok and json and reaper and reaper.SetExtState then
        reaper.SetExtState(CircleOfFifthsService.EXT_SECTION, CircleOfFifthsService.EXT_KEY, json, true)
        return true
    end
    return false
end

function CircleOfFifthsService.add_page(pages_or_state, custom_name)
    local pages = pages_or_state and (pages_or_state.cof_pages or pages_or_state) or {}
    local next_num = #pages + 1
    local name = custom_name or string.format("Palette %d", next_num)
    local new_page = CircleOfFifthsService.create_default_page(name)
    table.insert(pages, new_page)
    local new_idx = #pages
    if pages_or_state and pages_or_state.cof_pages then
        pages_or_state.cof_active_page_idx = new_idx
    end
    CircleOfFifthsService.save_palettes(pages_or_state)
    return new_page, new_idx
end

function CircleOfFifthsService.delete_page(pages_or_state, page_idx)
    local pages = pages_or_state and (pages_or_state.cof_pages or pages_or_state) or {}
    if #pages <= 1 then
        pages[1] = CircleOfFifthsService.create_default_page("Palette 1")
        CircleOfFifthsService.save_palettes(pages_or_state)
        return 1
    end
    table.remove(pages, page_idx)
    local clamped = math.max(1, math.min(#pages, tonumber(page_idx) or 1))
    if pages_or_state and pages_or_state.cof_pages then
        pages_or_state.cof_active_page_idx = clamped
    end
    CircleOfFifthsService.save_palettes(pages_or_state)
    return clamped
end

-- ==============================================================================
-- AUDITION & SCORE INSERTION (WITH KEY SIGNATURE SPELLING & AUTO-DIVISI)
-- ==============================================================================

--- Resolves the best target MediaTrack for Circle of Fifths auditioning and insertion.
--- Prioritizes:
---   1. Explicit user-selected track in the Circle of Fifths modal (`state.cof_preview_track`)
---   2. `state.active_track` or `state.focused_track` (if it has an instrument/FX or is not a folder)
---   3. Selected REAPER track (preferring one with an instrument/FX)
---   4. First project track with an instrument/FX, or Track 1 as final fallback.
function CircleOfFifthsService.resolve_audition_track(state)
    local function is_valid_track(trk)
        if not trk then return false end
        if reaper and reaper.ValidatePtr then
            return reaper.ValidatePtr(trk, "MediaTrack*")
        end
        return true
    end

    local function track_has_instrument_or_fx(trk)
        if not is_valid_track(trk) then return false end
        if reaper and reaper.TrackFX_GetInstrument and reaper.TrackFX_GetInstrument(trk) >= 0 then
            return true
        end
        if reaper and reaper.TrackFX_GetCount and reaper.TrackFX_GetCount(trk) > 0 then
            return true
        end
        return false
    end

    local function is_folder_parent(trk)
        if not is_valid_track(trk) then return false end
        if reaper and reaper.GetMediaTrackInfo_Value then
            return (reaper.GetMediaTrackInfo_Value(trk, "I_FOLDERDEPTH") or 0) == 1
        end
        return false
    end

    -- 1. Explicit track chosen in the Circle of Fifths Track Selector
    if type(state) == "table" and is_valid_track(state.cof_preview_track) then
        return state.cof_preview_track
    end

    -- 2. Active / Focused track if it is an instrument track (not an empty folder track)
    if type(state) == "table" then
        if is_valid_track(state.active_track) and (track_has_instrument_or_fx(state.active_track) or not is_folder_parent(state.active_track)) then
            return state.active_track
        end
        if is_valid_track(state.focused_track) and (track_has_instrument_or_fx(state.focused_track) or not is_folder_parent(state.focused_track)) then
            return state.focused_track
        end
    end

    -- 3. Selected track in REAPER
    if reaper and reaper.GetSelectedTrack then
        local sel_trk = reaper.GetSelectedTrack(0, 0)
        if is_valid_track(sel_trk) and (track_has_instrument_or_fx(sel_trk) or not is_folder_parent(sel_trk)) then
            return sel_trk
        end
    end

    -- 4. First track in project that actually hosts a virtual instrument or FX
    if reaper and reaper.CountTracks and reaper.GetTrack then
        local cnt = reaper.CountTracks(0)
        for i = 0, cnt - 1 do
            local trk = reaper.GetTrack(0, i)
            if track_has_instrument_or_fx(trk) then
                return trk
            end
        end
        -- Next best: first non-folder track
        for i = 0, cnt - 1 do
            local trk = reaper.GetTrack(0, i)
            if not is_folder_parent(trk) then
                return trk
            end
        end
        if cnt > 0 then
            return reaper.GetTrack(0, 0)
        end
    end

    if type(state) == "table" then
        return state.active_track or state.focused_track
    end
    return nil
end

function CircleOfFifthsService.audition_tile(state, tile, opt_track)
    if not tile then return end
    local pitches = CircleOfFifthsService.get_tile_pitches(tile)
    if #pitches == 0 then return end
    local target_trk = opt_track or CircleOfFifthsService.resolve_audition_track(state)
    if AudioPreview and AudioPreview.play_note then
        -- Pass `force_audition = true` (8th arg) so clicking in the Circle of Fifths
        -- ALWAYS arms the target track and plays the chord/note even if TopBar Audition is off!
        AudioPreview.play_note(state, pitches, 96, 0, target_trk, nil, nil, true)
        if AudioPreview.on_mouse_released then
            AudioPreview.on_mouse_released(state)
        end
    end
end

function CircleOfFifthsService.insert_tile_at_cursor(state, tile, midi_service)
    if not state or not tile then return 0 end
    local MidiService = midi_service or package.loaded["services.midi_service"] or require("services.midi_service")
    local RecordQuantizeService = package.loaded["services.record_quantize_service"] or require("services.record_quantize_service")

    local pitches = CircleOfFifthsService.get_tile_pitches(tile)
    if #pitches == 0 then return 0 end

    local cursor_pos = reaper.GetCursorPosition()
    local qn = math.max(0, reaper.TimeMap2_timeToQN(0, cursor_pos))
    local dur = state.grid_qn or state.active_dur or 1.0
    if state.is_dotted then dur = dur * 1.5 end
    if state.get_tuplet_factor then
        dur = dur * state:get_tuplet_factor()
    elseif state.is_triplet then
        dur = dur * (2.0 / 3.0)
    end

    local resolved_trk = CircleOfFifthsService.resolve_audition_track(state)
    local prev_focused = state.focused_track
    if resolved_trk then
        state.focused_track = resolved_trk
    end

    if RecordQuantizeService and RecordQuantizeService.insert_chord_cluster_at_qn then
        local inserted = RecordQuantizeService.insert_chord_cluster_at_qn(state, pitches, qn, dur, 96, MidiService)
        state.focused_track = prev_focused
        if inserted and inserted > 0 then
            CircleOfFifthsService.audition_tile(state, tile, resolved_trk)
            state.status_msg = string.format("🎡 Inserted '%s' (%d note%s) at %.2f QN",
                CircleOfFifthsService.format_tile_label(tile), inserted, inserted == 1 and "" or "s", qn)
            return inserted
        end
    end
    state.focused_track = prev_focused

    local trk = resolved_trk or state.focused_track or reaper.GetSelectedTrack(0, 0) or reaper.GetTrack(0, 0)
    local inserted_cnt = 0
    for _, p in ipairs(pitches) do
        if MidiService.insert_note_at_qn(state, qn, p, dur, trk) then
            inserted_cnt = inserted_cnt + 1
        end
    end
    if inserted_cnt > 0 then
        CircleOfFifthsService.audition_tile(state, tile, trk)
        reaper.SetEditCurPos(reaper.TimeMap2_QNToTime(0, qn + dur), true, false)
        state.status_msg = string.format("🎡 Inserted '%s' at %.2f QN", CircleOfFifthsService.format_tile_label(tile), qn)
    end
    return inserted_cnt
end

function CircleOfFifthsService.insert_progression_at_cursor(state, page_or_tiles, midi_service)
    if not state or type(page_or_tiles) ~= "table" then return 0, 0 end
    local tiles = page_or_tiles.tiles or page_or_tiles
    local chord_cnt = 0
    local note_cnt = 0
    for s_idx = 1, 8 do
        local t = tiles[s_idx]
        if t and (t.pc ~= nil or t.sector_idx ~= nil) then
            local n_ins = CircleOfFifthsService.insert_tile_at_cursor(state, t, midi_service)
            if n_ins and n_ins > 0 then
                chord_cnt = chord_cnt + 1
                note_cnt = note_cnt + n_ins
            end
        end
    end
    if chord_cnt > 0 then
        state.status_msg = string.format("🎡 Inserted %d chord/note tile(s) (%d notes) from Circle of Fifths palette", chord_cnt, note_cnt)
    end
    return chord_cnt, note_cnt
end

return CircleOfFifthsService

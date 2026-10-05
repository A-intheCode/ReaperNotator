-- ==============================================================================
-- REAPER Native Notator - Module: Constants
-- Definitions for SMuFL glyphs, color palette, note values, dynamics tables
-- ==============================================================================

local Constants = {}

local Version = package.loaded["version"] or require("version")
Constants.VERSION = Version.SEMVER
Constants.VERSION_DISPLAY = Version.get_display_string()

-- SMuFL (Standard Music Font Layout) character mapping for authentic music engraving
Constants.SMUFL = {
    -- Clefs
    g_clef            = utf8.char(0xE050), -- Treble clef 𝄞 (G-clef)
    g_clef_8va        = utf8.char(0xE051), -- G-clef 8va
    g_clef_8vb        = utf8.char(0xE052), -- G-clef 8vb (Tenor G)
    g_clef_15ma       = utf8.char(0xE053), -- G-clef 15ma
    g_clef_15mb       = utf8.char(0xE054), -- G-clef 15mb
    double_g_clef     = utf8.char(0xE055), -- Double G-clef
    c_clef            = utf8.char(0xE05C), -- C-clef (Alto/Tenor/Soprano/Mezzo)
    c_clef_8vb        = utf8.char(0xE05D), -- C-clef 8vb
    f_clef            = utf8.char(0xE062), -- Bass clef 𝄢 (F-clef)
    f_clef_8va        = utf8.char(0xE063), -- F-clef 8va
    f_clef_8vb        = utf8.char(0xE064), -- F-clef 8vb
    f_clef_15ma       = utf8.char(0xE065), -- F-clef 15ma
    f_clef_15mb       = utf8.char(0xE066), -- F-clef 15mb
    percussion_clef_1 = utf8.char(0xE069), -- Neutral 1 (||)
    percussion_clef_2 = utf8.char(0xE06A), -- Neutral 2 ([])
    tab_clef_6        = utf8.char(0xE06D), -- 6-line TAB
    tab_clef_4        = utf8.char(0xE06E), -- 4-line TAB
    
    -- Noteheads
    note_whole        = utf8.char(0xE0A2), -- Whole note 𝅝
    note_half         = utf8.char(0xE0A3), -- Half note 𝅗𝅥
    note_black        = utf8.char(0xE0A4), -- Quarter / Black note 𝅘𝅥
    
    -- Percussion Noteheads (SMuFL U+E0A7..E0DB)
    noteheadXBlack            = utf8.char(0xE0A9), -- X notehead black
    noteheadXHalf             = utf8.char(0xE0A8), -- X notehead half
    noteheadXWhole            = utf8.char(0xE0A7), -- X notehead whole
    noteheadCircleX           = utf8.char(0xE0B3), -- Circle-X notehead (open hi-hat)
    noteheadTriangleUpBlack   = utf8.char(0xE0BE), -- Triangle notehead black (cowbell/triangle)
    noteheadTriangleUpHalf    = utf8.char(0xE0BD), -- Triangle notehead half
    noteheadTriangleUpWhole   = utf8.char(0xE0BC), -- Triangle notehead whole
    noteheadDiamondBlack      = utf8.char(0xE0DB), -- Diamond notehead black (ride bell/harmonics)
    noteheadDiamondHalf       = utf8.char(0xE0DA), -- Diamond notehead half
    
    -- Measure & Beat Repeat Marks / Simile (SMuFL U+E500 ff.)
    repeat1Bar                = utf8.char(0xE500), -- 1-bar repeat (%)
    repeat2Bars               = utf8.char(0xE501), -- 2-bar repeat
    repeat1Beat               = utf8.char(0xE503), -- 1-beat repeat (/)
    
    -- Flags
    flag_8th_up       = utf8.char(0xE240),
    flag_8th_down     = utf8.char(0xE241),
    flag_16th_up      = utf8.char(0xE242),
    flag_16th_down    = utf8.char(0xE243),
    flag_32nd_up      = utf8.char(0xE244),
    flag_32nd_down    = utf8.char(0xE245),
    flag_64th_up      = utf8.char(0xE246),
    flag_64th_down    = utf8.char(0xE247),
    
    -- Accidentals
    acc_flat          = utf8.char(0xE260), -- ♭
    acc_natural       = utf8.char(0xE261), -- ♮
    acc_sharp         = utf8.char(0xE262), -- ♯
    
    -- Rhythm & Rests
    dot               = utf8.char(0xE1E7), -- Augmentation Dot •
    rest_whole        = utf8.char(0xE4E3),
    rest_half         = utf8.char(0xE4E4),
    rest_quarter      = utf8.char(0xE4E5),
    rest_8th          = utf8.char(0xE4E6),
    rest_16th         = utf8.char(0xE4E7),
    rest_32nd         = utf8.char(0xE4E8),
    rest_64th         = utf8.char(0xE4E9),
    
    -- Articulations (SMuFL U+E4A0 ff.)
    accent            = utf8.char(0xE4A0), -- Accent >
    staccato          = utf8.char(0xE4A2), -- Staccato .
    staccatissimo     = utf8.char(0xE4A6), -- Staccatissimo wedge ▼ / ▲
    staccatissimoAbove = utf8.char(0xE4A6), -- Staccatissimo wedge pointing down towards notehead
    staccatissimoBelow = utf8.char(0xE4A7), -- Staccatissimo wedge pointing up towards notehead
    tenuto            = utf8.char(0xE4A4), -- Tenuto —
    marcato           = utf8.char(0xE4AC), -- Marcato ^
    harmonic          = utf8.char(0xE614), -- Flageolet / Harmonic circle (SMuFL stringsHarmonic)
    
    -- Fermatas (SMuFL U+E4C0 ff.)
    fermataAbove          = utf8.char(0xE4C0), -- Standard fermata above 𝄐
    fermataBelow          = utf8.char(0xE4C1), -- Inverted fermata below
    fermataShortAbove     = utf8.char(0xE4C4), -- Short (triangular) fermata above
    fermataShortBelow     = utf8.char(0xE4C5), -- Short fermata below
    fermataLongAbove      = utf8.char(0xE4C6), -- Long (square) fermata above
    fermataLongBelow      = utf8.char(0xE4C7), -- Long fermata below
    fermataVeryLongAbove  = utf8.char(0xE4C8), -- Very long fermata above
    fermataVeryLongBelow  = utf8.char(0xE4C9), -- Very long fermata below
    
    -- Navigation & Repeats (SMuFL U+E040 ff.)
    segno                 = utf8.char(0xE047), -- Segno sign 𝄋
    coda                  = utf8.char(0xE048), -- Coda sign 𝄌
    codaSquare            = utf8.char(0xE049),
    daCapo                = utf8.char(0xE046),
    
    -- Arpeggio / Arpeggiato (SMuFL U+E63C ff.)
    arpeggiatoUp          = utf8.char(0xE63C), -- Arpeggio wavy line (upward)
    arpeggiatoDown        = utf8.char(0xE63D), -- Arpeggio wavy line with arrow down
    arpeggiato            = utf8.char(0xE63C), -- Standard arpeggiato
    
    -- Time signature digits (SMuFL U+E080 ff.)
    timeSig0          = utf8.char(0xE080),
    timeSig1          = utf8.char(0xE081),
    timeSig2          = utf8.char(0xE082),
    timeSig3          = utf8.char(0xE083),
    timeSig4          = utf8.char(0xE084),
    timeSig5          = utf8.char(0xE085),
    timeSig6          = utf8.char(0xE086),
    timeSig7          = utf8.char(0xE087),
    timeSig8          = utf8.char(0xE088),
    timeSig9          = utf8.char(0xE089),
    timeSigCommon     = utf8.char(0xE08A),
    timeSigCutCommon  = utf8.char(0xE08B),

    -- Dynamics (SMuFL U+E520 ff.)
    dyn_p             = utf8.char(0xE520),
    dyn_m             = utf8.char(0xE521),
    dyn_f             = utf8.char(0xE522),
    dyn_mp            = utf8.char(0xE52C),
    dyn_mf            = utf8.char(0xE52D),
    dyn_pp            = utf8.char(0xE52B),
    dyn_ff            = utf8.char(0xE52F),
    dyn_ppp           = utf8.char(0xE52A), -- U+E52A dynamicPPP
    dyn_fff           = utf8.char(0xE530), -- U+E530 dynamicFFF
    dyn_pppp          = utf8.char(0xE529), -- U+E529 dynamicPPPP
    dyn_ffff          = utf8.char(0xE531), -- U+E531 dynamicFFFF
    dyn_ppppp         = utf8.char(0xE528), -- U+E528 dynamicPPPPP
    dyn_fffff         = utf8.char(0xE532), -- U+E532 dynamicFFFFF
    dyn_pppppp        = utf8.char(0xE527), -- U+E527 dynamicPPPPPP
    dyn_ffffff        = utf8.char(0xE533), -- U+E533 dynamicFFFFFF
    dyn_fp            = utf8.char(0xE534), -- U+E534 dynamicFortePiano
    dyn_fz            = utf8.char(0xE535), -- U+E535 dynamicForzando
    dyn_sfz           = utf8.char(0xE539), -- U+E539 dynamicSforzato
    dyn_sffz          = utf8.char(0xE53B), -- U+E53B dynamicSforzatoFF
    dyn_sfp           = utf8.char(0xE537), -- U+E537 dynamicSforzandoPiano
    dyn_sfpp          = utf8.char(0xE538), -- U+E538 dynamicSforzandoPianissimo
    dyn_rfz           = utf8.char(0xE53C), -- U+E53C dynamicRinforzando1
    dyn_n             = utf8.char(0xE526), -- U+E526 dynamicNiente
    -- Pedal / Sustain (SMuFL U+E650 ff.)
    pedal_ped         = utf8.char(0xE650), -- U+E650 keyboardPedalPed (Ped.)
    pedal_up          = utf8.char(0xE655), -- U+E655 keyboardPedalUp (*)
    pedal_half        = utf8.char(0xE656), -- U+E656 keyboardPedalHalf
    pedal_up_notch    = utf8.char(0xE657), -- U+E657 keyboardPedalUpNotch (/\)
    pedal_sost        = utf8.char(0xE659), -- U+E659 keyboardPedalSost (Sost.)
    -- Tuplets (SMuFL U+E880 ff.)
    tuplet0           = utf8.char(0xE880),
    tuplet1           = utf8.char(0xE881),
    tuplet2           = utf8.char(0xE882),
    tuplet3           = utf8.char(0xE883),
    tuplet4           = utf8.char(0xE884),
    tuplet5           = utf8.char(0xE885),
    tuplet6           = utf8.char(0xE886),
    tuplet7           = utf8.char(0xE887),
    tuplet8           = utf8.char(0xE888),
    tuplet9           = utf8.char(0xE889),
    tupletColon       = utf8.char(0xE88A),
}

Constants.TUPLET_DEFS = {
    ["3"] = { name = "Triplet",    ratio_num = 3, ratio_den = 2, factor = 2.0 / 3.0, label = "3 Triplet (3:2)",   glyph = utf8.char(0xE883) },
    ["5"] = { name = "Quintuplet",  ratio_num = 5, ratio_den = 4, factor = 4.0 / 5.0, label = "5 Quintuplet (5:4)", glyph = utf8.char(0xE885) },
    ["6"] = { name = "Sextuplet",   ratio_num = 6, ratio_den = 4, factor = 4.0 / 6.0, label = "6 Sextuplet (6:4)",  glyph = utf8.char(0xE886) },
    ["7"] = { name = "Septuplet",   ratio_num = 7, ratio_den = 4, factor = 4.0 / 7.0, label = "7 Septuplet (7:4)",  glyph = utf8.char(0xE887) },
    ["8"] = { name = "Octuplet",    ratio_num = 8, ratio_den = 6, factor = 6.0 / 8.0, label = "8 Octuplet (8:6)",   glyph = utf8.char(0xE888) },
}

Constants.DYN_GLYPH_WIDTHS = {
    p = 365, m = 437, f = 364,
    mp = 826, mf = 797,
    pp = 727, ff = 609,
    ppp = 1072, fff = 831,
    pppp = 1417, ffff = 1070,
    ppppp = 1776, fffff = 1310,
    pppppp = 2124, ffffff = 1550,
    fp = 619, fz = 497,
    sfz = 732, sffz = 964,
    sfp = 846, sfpp = 1198,
    rfz = 625, n = 308, pf = 770
}

-- Diatonic pitch mapping (semitone -> diatonic step & accidental)
Constants.PITCH_MAP = {
    [0]  = { step = 0, acc = 0,  name = "C" },
    [1]  = { step = 0, acc = 1,  name = "C#" },
    [2]  = { step = 1, acc = 0,  name = "D" },
    [3]  = { step = 2, acc = -1, name = "Eb" },
    [4]  = { step = 2, acc = 0,  name = "E" },
    [5]  = { step = 3, acc = 0,  name = "F" },
    [6]  = { step = 3, acc = 1,  name = "F#" },
    [7]  = { step = 4, acc = 0,  name = "G" },
    [8]  = { step = 4, acc = 1,  name = "G#" },
    [9]  = { step = 5, acc = 0,  name = "A" },
    [10] = { step = 6, acc = -1, name = "Bb" },
    [11] = { step = 6, acc = 0,  name = "B" }
}

-- Color palette
Constants.DEFAULT_COLORS = {
    paper_bg         = 0xFAF8F5FF,
    staff_line       = 0x222222FF,
    barline          = 0x000000FF,
    beatline         = 0xEAE6DCFF,
    bar_num          = 0x111111FF,
    notehead_black   = 0x111111FF,
    beam_color       = 0x111111FF,
    clef_col         = 0x1A1A1AFF,
    timesig_col      = 0x1A1A1AFF,
    rest_col         = 0x1A1A1AFF,
    tie_col          = 0x1A1A1AFF,
    lyrics_text      = 0x1A1A1AFF,
    selection_gold   = 0xFF9F1CFF,
    selection_border = 0xFF9F1C88,
    selection_glow   = 0xFFD700FF,
    hover_orange     = 0xE67E22FF,
    marquee_box      = 0xFF9F1C22,
    marquee_border   = 0xFF9F1C88,
    badge_green      = 0x2ECC71FF,
    badge_red        = 0xE74C3CFF,
    text_dark        = 0x1A1A1AFF,
    text_muted       = 0x777777FF,
    art_text         = 0x1A1A1AFF,
    rehearsal_box_bg = 0xFAF8F5FF,
    rehearsal_border = 0x1A1A1AFF,
    rehearsal_text   = 0x111111FF,
    fermata_col      = 0x111111FF
}

Constants.COLORS = {
    paper_bg         = 0xFAF8F5FF,
    staff_line       = 0x222222FF,
    barline          = 0x000000FF,
    beatline         = 0xEAE6DCFF,
    bar_num          = 0x111111FF,
    notehead_black   = 0x111111FF,
    beam_color       = 0x111111FF,
    clef_col         = 0x1A1A1AFF,
    timesig_col      = 0x1A1A1AFF,
    rest_col         = 0x1A1A1AFF,
    tie_col          = 0x1A1A1AFF,
    lyrics_text      = 0x1A1A1AFF,
    selection_gold   = 0xFF9F1CFF,
    selection_border = 0xFF9F1C88,
    selection_glow   = 0xFFD700FF,
    hover_orange     = 0xE67E22FF,
    marquee_box      = 0xFF9F1C22,
    marquee_border   = 0xFF9F1C88,
    badge_green      = 0x2ECC71FF,
    badge_red        = 0xE74C3CFF,
    text_dark        = 0x1A1A1AFF,
    text_muted       = 0x777777FF,
    art_text         = 0x1A1A1AFF,
    rehearsal_box_bg = 0xFAF8F5FF,
    rehearsal_border = 0x1A1A1AFF,
    rehearsal_text   = 0x111111FF,
    fermata_col      = 0x111111FF
}

-- 16 Voices color palette (MIDI note channels 1 to 16)
Constants.VOICE_COLORS = {
    [1]  = 0x1A1A1AFF, -- Voice 1: Classic engraving black
    [2]  = 0x27AE60FF, -- Voice 2: Emerald green
    [3]  = 0xD35400FF, -- Voice 3: Warm terracotta / orange
    [4]  = 0x8E44ADFF, -- Voice 4: Deep violet
    [5]  = 0x16A085FF, -- Voice 5: Teal / petrol
    [6]  = 0xC0392BFF, -- Voice 6: Crimson
    [7]  = 0x2980B9FF, -- Voice 7: Sapphire blue
    [8]  = 0xD4AC0DFF, -- Voice 8: Ochre gold
    [9]  = 0x2C3E50FF, -- Voice 9: Midnight blue
    [10] = 0x7F8C8DFF, -- Voice 10: Slate gray
    [11] = 0xE67E22FF, -- Voice 11: Amber
    [12] = 0xA569BDFF, -- Voice 12: Light orchid
    [13] = 0x5DADE2FF, -- Voice 13: Sky blue
    [14] = 0x48C9B0FF, -- Voice 14: Aquamarine
    [15] = 0xF5B041FF, -- Voice 15: Sun yellow / gold
    [16] = 0xEC7063FF, -- Voice 16: Coral
}

function Constants.get_voice_color(voice_num, is_invert)
    if is_invert then
        if voice_num == 1 then
            return Constants.COLORS.notehead_black or 0xEEEEEEFF
        elseif voice_num == 9 then
            return 0x5DADE2FF -- High-contrast sky blue instead of dark midnight blue in dark mode
        end
    end
    return (Constants.VOICE_COLORS and Constants.VOICE_COLORS[voice_num]) or (Constants.COLORS.notehead_black or 0x111111FF)
end

-- 10 Alex ScoreTools dynamic levels with color coding
Constants.ALEX_DYN_BUTTONS = {
    {label = "pppp", c1 = 8,   c11 = 12,  col = 0x1A1A66FF, text_col = 0xFFFFFFFF},
    {label = "ppp",  c1 = 20,  c11 = 25,  col = 0x1A3399FF, text_col = 0xFFFFFFFF},
    {label = "pp",   c1 = 35,  c11 = 40,  col = 0x334DCCFF, text_col = 0xFFFFFFFF},
    {label = "p",    c1 = 50,  c11 = 55,  col = 0x4D80E6FF, text_col = 0xFFFFFFFF},
    {label = "mp",   c1 = 65,  c11 = 70,  col = 0x33B366FF, text_col = 0xFFFFFFFF},
    {label = "mf",   c1 = 80,  c11 = 85,  col = 0xB3B333FF, text_col = 0x111111FF},
    {label = "f",    c1 = 95,  c11 = 100, col = 0xE6801AFF, text_col = 0xFFFFFFFF},
    {label = "ff",   c1 = 110, c11 = 115, col = 0xE6331AFF, text_col = 0xFFFFFFFF},
    {label = "fff",  c1 = 120, c11 = 120, col = 0xCC1A00FF, text_col = 0xFFFFFFFF},
    {label = "ffff", c1 = 127, c11 = 127, col = 0x990000FF, text_col = 0xFFFFFFFF}
}

Constants.DYN_GRID_OPTIONS = {
    {label = "1/2",   val = 2.0},
    {label = "1/4",   val = 1.0},
    {label = "1/8",   val = 0.5},
    {label = "1/16",  val = 0.25},
    {label = "1/32",  val = 0.125},
    {label = "1/64",  val = 0.0625},
    {label = "1/128", val = 0.03125}
}

-- ==============================================================================
-- COMPREHENSIVE CLEF DEFINITIONS
-- 3 categories: Common Clefs, Uncommon Clefs, Archaic Clefs
-- ==============================================================================
Constants.CLEF_DEFS = {
    -- --------------------------------------------------------------------------
    -- 1. COMMON CLEFS
    -- --------------------------------------------------------------------------
    treble = {
        id = "treble", name = "Treble Clef", cat = "Common Clefs",
        glyph = Constants.SMUFL.g_clef, anchor_line = 2,
        bottom_line_diatonic = 2, c4_pos = -2, staff_lines = 5
    },
    bass = {
        id = "bass", name = "Bass Clef", cat = "Common Clefs",
        glyph = Constants.SMUFL.f_clef, anchor_line = 4,
        bottom_line_diatonic = -10, c4_pos = 10, staff_lines = 5
    },
    alto = {
        id = "alto", name = "Alto Clef", cat = "Common Clefs",
        glyph = Constants.SMUFL.c_clef, anchor_line = 3,
        bottom_line_diatonic = -4, c4_pos = 4, staff_lines = 5
    },
    tenor = {
        id = "tenor", name = "Tenor Clef", cat = "Common Clefs",
        glyph = Constants.SMUFL.c_clef, anchor_line = 4,
        bottom_line_diatonic = -6, c4_pos = 6, staff_lines = 5
    },
    treble_8vb = {
        id = "treble_8vb", name = "Treble 8vb (Tenor)", cat = "Common Clefs",
        glyph = Constants.SMUFL.g_clef_8vb, anchor_line = 2,
        bottom_line_diatonic = -5, c4_pos = 5, staff_lines = 5
    },
    grand = {
        id = "grand", name = "Grand Staff (Piano 2 Staves)", cat = "Common Clefs",
        glyph = Constants.SMUFL.g_clef, glyph_bass = Constants.SMUFL.f_clef,
        is_multi_staff = "grand", staff_lines = 5
    },
    harp_3staff = {
        id = "harp_3staff", name = "Harp / Organ (3 Staves)", cat = "Common Clefs",
        glyph = Constants.SMUFL.g_clef, glyph_mid = Constants.SMUFL.c_clef, glyph_bass = Constants.SMUFL.f_clef,
        is_multi_staff = "harp_3staff", staff_lines = 5
    },
    percussion_1 = {
        id = "percussion_1", name = "Percussion (Neutral ||)", cat = "Common Clefs",
        glyph = Constants.SMUFL.percussion_clef_1, anchor_line = 3,
        bottom_line_diatonic = 2, c4_pos = 4, staff_lines = 5, unpitched = true
    },
    percussion_2 = {
        id = "percussion_2", name = "Percussion (Box [])", cat = "Common Clefs",
        glyph = Constants.SMUFL.percussion_clef_2, anchor_line = 3,
        bottom_line_diatonic = 2, c4_pos = 4, staff_lines = 5, unpitched = true
    },
    tab_6 = {
        id = "tab_6", name = "TAB (6-String)", cat = "Common Clefs",
        glyph = Constants.SMUFL.tab_clef_6, anchor_line = 3,
        bottom_line_diatonic = 2, staff_lines = 6, is_tab = true
    },
    tab_4 = {
        id = "tab_4", name = "TAB (4-String)", cat = "Common Clefs",
        glyph = Constants.SMUFL.tab_clef_4, anchor_line = 2,
        bottom_line_diatonic = 2, staff_lines = 4, is_tab = true
    },

    -- --------------------------------------------------------------------------
    -- 2. UNCOMMON CLEFS
    -- --------------------------------------------------------------------------
    tenor_8vb = {
        id = "tenor_8vb", name = "Tenor 8vb", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.c_clef_8vb, anchor_line = 4,
        bottom_line_diatonic = -13, c4_pos = 13, staff_lines = 5
    },
    bass_15mb = {
        id = "bass_15mb", name = "Bass 15mb", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.f_clef_15mb, anchor_line = 4,
        bottom_line_diatonic = -24, c4_pos = 24, staff_lines = 5
    },
    bass_15ma = {
        id = "bass_15ma", name = "Bass 15ma", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.f_clef_15ma, anchor_line = 4,
        bottom_line_diatonic = 4, c4_pos = -4, staff_lines = 5
    },
    bass_8vb = {
        id = "bass_8vb", name = "Bass 8vb", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.f_clef_8vb, anchor_line = 4,
        bottom_line_diatonic = -17, c4_pos = 17, staff_lines = 5
    },
    bass_8va = {
        id = "bass_8va", name = "Bass 8va", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.f_clef_8va, anchor_line = 4,
        bottom_line_diatonic = -3, c4_pos = 3, staff_lines = 5
    },
    french_violin = {
        id = "french_violin", name = "French Violin", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.g_clef, anchor_line = 1,
        bottom_line_diatonic = 4, c4_pos = -4, staff_lines = 5
    },
    blank_staff = {
        id = "blank_staff", name = "Blank Staff", cat = "Uncommon Clefs",
        glyph = "", anchor_line = 3,
        bottom_line_diatonic = 2, c4_pos = -2, staff_lines = 5
    },
    double_treble = {
        id = "double_treble", name = "Double Treble", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.double_g_clef, anchor_line = 2,
        bottom_line_diatonic = -5, c4_pos = 5, staff_lines = 5
    },
    treble_15mb = {
        id = "treble_15mb", name = "Treble 15mb", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.g_clef_15mb, anchor_line = 2,
        bottom_line_diatonic = -12, c4_pos = 12, staff_lines = 5
    },
    treble_15ma = {
        id = "treble_15ma", name = "Treble 15ma", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.g_clef_15ma, anchor_line = 2,
        bottom_line_diatonic = 16, c4_pos = -16, staff_lines = 5
    },
    treble_8va = {
        id = "treble_8va", name = "Treble 8va", cat = "Uncommon Clefs",
        glyph = Constants.SMUFL.g_clef_8va, anchor_line = 2,
        bottom_line_diatonic = 9, c4_pos = -9, staff_lines = 5
    },

    -- --------------------------------------------------------------------------
    -- 3. ARCHAIC CLEFS
    -- --------------------------------------------------------------------------
    soprano = {
        id = "soprano", name = "Soprano Clef", cat = "Archaic Clefs",
        glyph = Constants.SMUFL.c_clef, anchor_line = 1,
        bottom_line_diatonic = 0, c4_pos = 0, staff_lines = 5
    },
    baritone_f = {
        id = "baritone_f", name = "Baritone (F-Clef)", cat = "Archaic Clefs",
        glyph = Constants.SMUFL.f_clef, anchor_line = 3,
        bottom_line_diatonic = -8, c4_pos = 8, staff_lines = 5
    },
    mezzo_soprano = {
        id = "mezzo_soprano", name = "Mezzo-Soprano", cat = "Archaic Clefs",
        glyph = Constants.SMUFL.c_clef, anchor_line = 2,
        bottom_line_diatonic = -2, c4_pos = 2, staff_lines = 5
    },
    baritone_c = {
        id = "baritone_c", name = "Baritone (C-Clef)", cat = "Archaic Clefs",
        glyph = Constants.SMUFL.c_clef, anchor_line = 5,
        bottom_line_diatonic = -8, c4_pos = 8, staff_lines = 5
    },
    sub_bass = {
        id = "sub_bass", name = "Sub-Bass", cat = "Archaic Clefs",
        glyph = Constants.SMUFL.f_clef, anchor_line = 5,
        bottom_line_diatonic = -12, c4_pos = 12, staff_lines = 5
    },
    alto_8vb = {
        id = "alto_8vb", name = "Alto 8vb", cat = "Archaic Clefs",
        glyph = Constants.SMUFL.c_clef_8vb, anchor_line = 3,
        bottom_line_diatonic = -11, c4_pos = 11, staff_lines = 5
    }
}

Constants.CLEFS_ORDERED = {
    -- Common Clefs
    "treble", "bass", "alto", "tenor", "treble_8vb", "grand", "harp_3staff", "percussion_1", "percussion_2", "tab_6", "tab_4",
    -- Uncommon Clefs
    "tenor_8vb", "bass_15mb", "bass_15ma", "bass_8vb", "bass_8va", "french_violin", "blank_staff", "double_treble", "treble_15mb", "treble_15ma", "treble_8va",
    -- Archaic Clefs
    "soprano", "baritone_f", "mezzo_soprano", "baritone_c", "sub_bass", "alto_8vb"
}

Constants.CLEF_CATEGORIES = {
    "Common Clefs",
    "Uncommon Clefs",
    "Archaic Clefs",
    ["Common Clefs"] = {},
    ["Uncommon Clefs"] = {},
    ["Archaic Clefs"] = {}
}

for _, cid in ipairs(Constants.CLEFS_ORDERED) do
    local cdef = Constants.CLEF_DEFS[cid]
    if cdef and cdef.cat and Constants.CLEF_CATEGORIES[cdef.cat] then
        table.insert(Constants.CLEF_CATEGORIES[cdef.cat], cdef)
    end
end

Constants.OCTAVE_LINE_DEFS = {
    ["8va"]  = { id = "8va",  label = "8",    corner = "top", shift_semitones = 12,  shift_diatonic = 7,   placement = "above", name = "8va (1 Octave Above)" },
    ["15ma"] = { id = "15ma", label = "15",   corner = "top", shift_semitones = 24,  shift_diatonic = 14,  placement = "above", name = "15ma (2 Octaves Above)" },
    ["22ma"] = { id = "22ma", label = "22",   corner = "top", shift_semitones = 36,  shift_diatonic = 21,  placement = "above", name = "22ma (3 Octaves Above)" },
    ["8vb"]  = { id = "8vb",  label = "8",    corner = "top", shift_semitones = -12, shift_diatonic = -7,  placement = "above", name = "8vb (1 Octave Below)" },
    ["15mb"] = { id = "15mb", label = "15",   corner = "top", shift_semitones = -24, shift_diatonic = -14, placement = "above", name = "15mb (2 Octaves Below)" },
    ["22mb"] = { id = "22mb", label = "22",   corner = "top", shift_semitones = -36, shift_diatonic = -21, placement = "above", name = "22mb (3 Octaves Below)" },
    ["loco"] = { id = "loco", label = "loco", corner = "top", shift_semitones = 0,   shift_diatonic = 0,   placement = "above", name = "loco (At Pitch)" },
}

Constants.OCTAVE_LINE_ORDERED = {
    { "8va", "15ma", "22ma" },
    { "8vb", "15mb", "22mb" },
    { "loco" }
}

-- ==============================================================================
-- GENERAL MIDI PERCUSSION MAPPING (Drum Staff Diatonic Steps & Noteheads)
-- ==============================================================================
-- Staff Diatonic Steps:
-- 0 = bottom line (E4), 1 = 1st space (F4), 2 = 2nd line (G4), 3 = 2nd space (A4),
-- 4 = 3rd line (B4), 5 = 3rd space (C5), 6 = 4th line (D5), 7 = 4th space (E5),
-- 8 = 5th top line (F5), 9 = space above (G5), 10 = ledger line above (A5), -2 = ledger space below
Constants.GM_DRUM_STEP_MAP = {
    [35] = 1,  -- Acoustic Bass Drum (1st space)
    [36] = 1,  -- Bass Drum 1
    [37] = 4,  -- Side Stick / Cross-Stick (3rd line)
    [38] = 4,  -- Acoustic Snare (3rd line)
    [39] = 4,  -- Hand Clap
    [40] = 4,  -- Electric Snare
    [41] = 0,  -- Low Floor Tom (bottom line)
    [42] = 9,  -- Closed Hi-Hat (space above staff)
    [43] = 0,  -- High Floor Tom
    [44] = -2, -- Pedal Hi-Hat (ledger space below)
    [45] = 2,  -- Low Tom (2nd line)
    [46] = 9,  -- Open Hi-Hat (space above staff)
    [47] = 3,  -- Low-Mid Tom (2nd space)
    [48] = 5,  -- Hi-Mid Tom (3rd space)
    [49] = 10, -- Crash Cymbal 1 (ledger line above)
    [50] = 6,  -- High Tom (4th line)
    [51] = 8,  -- Ride Cymbal 1 (5th top line)
    [52] = 10, -- Chinese Cymbal
    [53] = 8,  -- Ride Bell
    [54] = 7,  -- Tambourine (4th space)
    [55] = 10, -- Splash Cymbal
    [56] = 6,  -- Cowbell (4th line)
    [57] = 10, -- Crash Cymbal 2
    [58] = 4,  -- Vibraslap
    [59] = 8,  -- Ride Cymbal 2
    [60] = 5,  -- Hi Bongo
    [61] = 3,  -- Low Bongo
    [62] = 5,  -- Mute Hi Conga
    [63] = 4,  -- Open Hi Conga
    [64] = 2,  -- Low Conga
    [65] = 6,  -- High Timbale
    [66] = 4,  -- Low Timbale
    [67] = 7,  -- High Agogo
    [68] = 5,  -- Low Agogo
    [69] = 9,  -- Cabasa
    [70] = 9,  -- Maracas
    [71] = 8,  -- Short Whistle
    [72] = 7,  -- Long Whistle
    [73] = 5,  -- Short Guiro
    [74] = 4,  -- Long Guiro
    [75] = 5,  -- Claves
    [76] = 6,  -- Hi Wood Block
    [77] = 4,  -- Low Wood Block
    [80] = 9,  -- Mute Triangle
    [81] = 9,  -- Open Triangle
}

function Constants.get_percussion_notehead_type(pitch)
    if not pitch then return "standard" end
    -- Open Hi-Hat -> Circle-X
    if pitch == 46 then
        return "circle_x"
    -- Cowbell, Triangles -> Triangle Up
    elseif pitch == 56 or pitch == 80 or pitch == 81 then
        return "triangle"
    -- Ride Bell / Harmonics -> Diamond
    elseif pitch == 53 then
        return "diamond"
    -- Cymbals, Hi-Hats, Cross-Stick, Claps, Tambourine, Claves, Shakers -> X
    elseif pitch == 37 or pitch == 39 or pitch == 42 or pitch == 44 or
           pitch == 49 or pitch == 51 or pitch == 52 or pitch == 54 or
           pitch == 55 or pitch == 57 or pitch == 59 or pitch == 69 or
           pitch == 70 or pitch == 75 or pitch == 76 or pitch == 77 then
        return "x"
    end
    -- Bass Drum, Snares, Toms, Bongos, Congas -> standard round noteheads
    return "standard"
end

-- ==============================================================================
-- KEY SIGNATURES (Western music engraving according to Gardner Read & Elaine Gould)
-- ==============================================================================
-- Mapping of all 15 key signatures from -7 (7b) to +7 (7#)
-- Diatonic line/space offsets from bottom staff line (0 = 1st line)
-- 0 = bottom line, 1 = 1st space, 2 = 2nd line, 3 = 2nd space,
-- 4 = 3rd line, 5 = 3rd space, 6 = 4th line, 7 = 4th space,
-- 8 = 5th line (top line), 9 = space above staff
Constants.KEY_SIGNATURES = {
    [-7] = {
        idx = -7,
        name_major = "Ces-Dur",
        name_minor = "as-Moll",
        name_major_en = "Cb Major",
        name_minor_en = "Ab Minor",
        sharps_count = 0,
        flats_count = 7,
        acc_type = "flat",
        altered_pitch_classes = { [10] = "flat", [3] = "flat", [8] = "flat", [1] = "flat", [6] = "flat", [11] = "flat", [4] = "flat" },
        glyph_positions = {
            treble = { 4, 7, 3, 6, 2, 5, 1 },
            bass   = { 2, 5, 1, 4, 0, 3, 6 },
            alto   = { 3, 6, 2, 5, 1, 4, 0 },
            Treble = { 4, 7, 3, 6, 2, 5, 1 },
            Bass   = { 2, 5, 1, 4, 0, 3, 6 },
            Alto   = { 3, 6, 2, 5, 1, 4, 0 }
        }
    },
    [-6] = {
        idx = -6,
        name_major = "Ges-Dur",
        name_minor = "es-Moll",
        name_major_en = "Gb Major",
        name_minor_en = "Eb Minor",
        sharps_count = 0,
        flats_count = 6,
        acc_type = "flat",
        altered_pitch_classes = { [10] = "flat", [3] = "flat", [8] = "flat", [1] = "flat", [6] = "flat", [11] = "flat" },
        glyph_positions = {
            treble = { 4, 7, 3, 6, 2, 5 },
            bass   = { 2, 5, 1, 4, 0, 3 },
            alto   = { 3, 6, 2, 5, 1, 4 },
            Treble = { 4, 7, 3, 6, 2, 5 },
            Bass   = { 2, 5, 1, 4, 0, 3 },
            Alto   = { 3, 6, 2, 5, 1, 4 }
        }
    },
    [-5] = {
        idx = -5,
        name_major = "Des-Dur",
        name_minor = "b-Moll",
        name_major_en = "Db Major",
        name_minor_en = "Bb Minor",
        sharps_count = 0,
        flats_count = 5,
        acc_type = "flat",
        altered_pitch_classes = { [10] = "flat", [3] = "flat", [8] = "flat", [1] = "flat", [6] = "flat" },
        glyph_positions = {
            treble = { 4, 7, 3, 6, 2 },
            bass   = { 2, 5, 1, 4, 0 },
            alto   = { 3, 6, 2, 5, 1 },
            Treble = { 4, 7, 3, 6, 2 },
            Bass   = { 2, 5, 1, 4, 0 },
            Alto   = { 3, 6, 2, 5, 1 }
        }
    },
    [-4] = {
        idx = -4,
        name_major = "As-Dur",
        name_minor = "f-Moll",
        name_major_en = "Ab Major",
        name_minor_en = "F Minor",
        sharps_count = 0,
        flats_count = 4,
        acc_type = "flat",
        altered_pitch_classes = { [10] = "flat", [3] = "flat", [8] = "flat", [1] = "flat" },
        glyph_positions = {
            treble = { 4, 7, 3, 6 },
            bass   = { 2, 5, 1, 4 },
            alto   = { 3, 6, 2, 5 },
            Treble = { 4, 7, 3, 6 },
            Bass   = { 2, 5, 1, 4 },
            Alto   = { 3, 6, 2, 5 }
        }
    },
    [-3] = {
        idx = -3,
        name_major = "Es-Dur",
        name_minor = "c-Moll",
        name_major_en = "Eb Major",
        name_minor_en = "C Minor",
        sharps_count = 0,
        flats_count = 3,
        acc_type = "flat",
        altered_pitch_classes = { [10] = "flat", [3] = "flat", [8] = "flat" },
        glyph_positions = {
            treble = { 4, 7, 3 },
            bass   = { 2, 5, 1 },
            alto   = { 3, 6, 2 },
            Treble = { 4, 7, 3 },
            Bass   = { 2, 5, 1 },
            Alto   = { 3, 6, 2 }
        }
    },
    [-2] = {
        idx = -2,
        name_major = "B-Dur",
        name_minor = "g-Moll",
        name_major_en = "Bb Major",
        name_minor_en = "G Minor",
        sharps_count = 0,
        flats_count = 2,
        acc_type = "flat",
        altered_pitch_classes = { [10] = "flat", [3] = "flat" },
        glyph_positions = {
            treble = { 4, 7 },
            bass   = { 2, 5 },
            alto   = { 3, 6 },
            Treble = { 4, 7 },
            Bass   = { 2, 5 },
            Alto   = { 3, 6 }
        }
    },
    [-1] = {
        idx = -1,
        name_major = "F-Dur",
        name_minor = "d-Moll",
        name_major_en = "F Major",
        name_minor_en = "D Minor",
        sharps_count = 0,
        flats_count = 1,
        acc_type = "flat",
        altered_pitch_classes = { [10] = "flat" },
        glyph_positions = {
            treble = { 4 },
            bass   = { 2 },
            alto   = { 3 },
            Treble = { 4 },
            Bass   = { 2 },
            Alto   = { 3 }
        }
    },
    [0] = {
        idx = 0,
        name_major = "C-Dur",
        name_minor = "a-Moll",
        name_major_en = "C Major",
        name_minor_en = "A Minor",
        sharps_count = 0,
        flats_count = 0,
        acc_type = "none",
        altered_pitch_classes = {},
        glyph_positions = {
            treble = {},
            bass   = {},
            alto   = {},
            Treble = {},
            Bass   = {},
            Alto   = {}
        }
    },
    [1] = {
        idx = 1,
        name_major = "G-Dur",
        name_minor = "e-Moll",
        name_major_en = "G Major",
        name_minor_en = "E Minor",
        sharps_count = 1,
        flats_count = 0,
        acc_type = "sharp",
        altered_pitch_classes = { [6] = "sharp" },
        glyph_positions = {
            treble = { 8 },
            bass   = { 6 },
            alto   = { 7 },
            Treble = { 8 },
            Bass   = { 6 },
            Alto   = { 7 }
        }
    },
    [2] = {
        idx = 2,
        name_major = "D-Dur",
        name_minor = "h-Moll",
        name_major_en = "D Major",
        name_minor_en = "B Minor",
        sharps_count = 2,
        flats_count = 0,
        acc_type = "sharp",
        altered_pitch_classes = { [6] = "sharp", [1] = "sharp" },
        glyph_positions = {
            treble = { 8, 5 },
            bass   = { 6, 3 },
            alto   = { 7, 4 },
            Treble = { 8, 5 },
            Bass   = { 6, 3 },
            Alto   = { 7, 4 }
        }
    },
    [3] = {
        idx = 3,
        name_major = "A-Dur",
        name_minor = "fis-Moll",
        name_major_en = "A Major",
        name_minor_en = "F# Minor",
        sharps_count = 3,
        flats_count = 0,
        acc_type = "sharp",
        altered_pitch_classes = { [6] = "sharp", [1] = "sharp", [8] = "sharp" },
        glyph_positions = {
            treble = { 8, 5, 9 },
            bass   = { 6, 3, 7 },
            alto   = { 7, 4, 8 },
            Treble = { 8, 5, 9 },
            Bass   = { 6, 3, 7 },
            Alto   = { 7, 4, 8 }
        }
    },
    [4] = {
        idx = 4,
        name_major = "E-Dur",
        name_minor = "cis-Moll",
        name_major_en = "E Major",
        name_minor_en = "C# Minor",
        sharps_count = 4,
        flats_count = 0,
        acc_type = "sharp",
        altered_pitch_classes = { [6] = "sharp", [1] = "sharp", [8] = "sharp", [3] = "sharp" },
        glyph_positions = {
            treble = { 8, 5, 9, 6 },
            bass   = { 6, 3, 7, 4 },
            alto   = { 7, 4, 8, 5 },
            Treble = { 8, 5, 9, 6 },
            Bass   = { 6, 3, 7, 4 },
            Alto   = { 7, 4, 8, 5 }
        }
    },
    [5] = {
        idx = 5,
        name_major = "H-Dur",
        name_minor = "gis-Moll",
        name_major_en = "B Major",
        name_minor_en = "G# Minor",
        sharps_count = 5,
        flats_count = 0,
        acc_type = "sharp",
        altered_pitch_classes = { [6] = "sharp", [1] = "sharp", [8] = "sharp", [3] = "sharp", [10] = "sharp" },
        glyph_positions = {
            treble = { 8, 5, 9, 6, 3 },
            bass   = { 6, 3, 7, 4, 1 },
            alto   = { 7, 4, 8, 5, 2 },
            Treble = { 8, 5, 9, 6, 3 },
            Bass   = { 6, 3, 7, 4, 1 },
            Alto   = { 7, 4, 8, 5, 2 }
        }
    },
    [6] = {
        idx = 6,
        name_major = "Fis-Dur",
        name_minor = "dis-Moll",
        name_major_en = "F# Major",
        name_minor_en = "D# Minor",
        sharps_count = 6,
        flats_count = 0,
        acc_type = "sharp",
        altered_pitch_classes = { [6] = "sharp", [1] = "sharp", [8] = "sharp", [3] = "sharp", [10] = "sharp", [5] = "sharp" },
        glyph_positions = {
            treble = { 8, 5, 9, 6, 3, 7 },
            bass   = { 6, 3, 7, 4, 1, 5 },
            alto   = { 7, 4, 8, 5, 2, 6 },
            Treble = { 8, 5, 9, 6, 3, 7 },
            Bass   = { 6, 3, 7, 4, 1, 5 },
            Alto   = { 7, 4, 8, 5, 2, 6 }
        }
    },
    [7] = {
        idx = 7,
        name_major = "Cis-Dur",
        name_minor = "ais-Moll",
        name_major_en = "C# Major",
        name_minor_en = "A# Minor",
        sharps_count = 7,
        flats_count = 0,
        acc_type = "sharp",
        altered_pitch_classes = { [6] = "sharp", [1] = "sharp", [8] = "sharp", [3] = "sharp", [10] = "sharp", [5] = "sharp", [0] = "sharp" },
        glyph_positions = {
            treble = { 8, 5, 9, 6, 3, 7, 4 },
            bass   = { 6, 3, 7, 4, 1, 5, 2 },
            alto   = { 7, 4, 8, 5, 2, 6, 3 },
            Treble = { 8, 5, 9, 6, 3, 7, 4 },
            Bass   = { 6, 3, 7, 4, 1, 5, 2 },
            Alto   = { 7, 4, 8, 5, 2, 6, 3 }
        }
    }
}

Constants.COMMON_TIME_SIGNATURES = {
    { num = 4, den = 4 },
    { num = 3, den = 4 },
    { num = 2, den = 4 },
    { num = 6, den = 8 },
    { num = 12, den = 8 },
    { num = 5, den = 4 },
    { num = 7, den = 8 }
}

function Constants.get_key_signature(idx)
    local k = tonumber(idx) or 0
    k = math.max(-7, math.min(7, k))
    return Constants.KEY_SIGNATURES[k] or Constants.KEY_SIGNATURES[0]
end

return Constants

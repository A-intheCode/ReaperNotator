-- ==============================================================================
-- REAPER Native Notator - Auto-Generated Module: MelodyStyleCorpus
-- Trained via tools/train_melody_style_models.py on the 1,500-pattern library
-- Contains empirical Markov interval weights, gap-fill ratios, rhythm cells,
-- cadential approaches, and higher-order compositional rules for 10 styles.
-- ==============================================================================

local MelodyStyleCorpus = {}

MelodyStyleCorpus.STYLES = {
    [1] = {
        id = "cinematic",
        name = "🎬 Cinematic / Epic (Blockbuster Score)",
        default_scale = "aeolian",
        trained_scores = 300,
        trained_notes = 4599,
        gap_fill_strength = 0.773,
        legato_ratio = 0.96,
        staccato_prob = 0.08,
        accent_prob = 0.3,
        anticipation_prob = 0.15,
        triad_fanfare_bonus = 0.35,
        pivot_return_bonus = 0.15,
        sequence_repeat_bonus = 0.25,
        avoid_semitone_lead = false,
        modal_color_semitones = { 6, 10 },
        interval_weights = { [-12] = 0.03, [-11] = 0.0126, [-10] = 0.0177, [-9] = 0.0128, [-8] = 0.042, [-7] = 0.0729, [-6] = 0.0147, [-5] = 0.0786, [-4] = 0.0845, [-3] = 0.1269, [-2] = 0.2094, [-1] = 0.1112, [0] = 0.1219, [1] = 0.1088, [2] = 0.1884, [3] = 0.119, [4] = 0.101, [5] = 0.1124, [6] = 0.0141, [7] = 0.1348, [8] = 0.0541, [9] = 0.0424, [10] = 0.012, [11] = 0.012, [12] = 0.0482 },
        rhythm_cells = {
            sparse = { { 2.0, 2.0 }, { 3.0, 1.0 }, { 1.5, 0.5, 2.0 }, { 2.0, 1.5, 0.5 } },
            medium = { { 1.5, 0.5, 1.0, 1.0 }, { 1.0, 1.0, 1.5, 0.5 }, { 1.0, 0.5, 0.5, 1.0, 1.0 }, { 2.0, 1.0, 0.5, 0.5 } },
            dense = { { 0.5, 0.5, 0.5, 0.5, 1.0, 0.5, 0.5 }, { 1.0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 }, { 0.75, 0.25, 0.5, 0.5, 1.0, 0.5, 0.5 } },
        },
        cadence_approaches = { { -1 }, { -2, -1 }, { 1 }, { -5 }, { 2, -1 } },
    },
    [2] = {
        id = "film_style_1",
        name = "🎺 Film Composer Style 1 (Heroic Symphonic Fanfare)",
        default_scale = "lydian",
        trained_scores = 450,
        trained_notes = 7715,
        gap_fill_strength = 0.767,
        legato_ratio = 0.94,
        staccato_prob = 0.14,
        accent_prob = 0.42,
        anticipation_prob = 0.18,
        triad_fanfare_bonus = 0.95,
        pivot_return_bonus = 0.2,
        sequence_repeat_bonus = 0.4,
        avoid_semitone_lead = false,
        modal_color_semitones = { 6, 10 },
        interval_weights = { [-12] = 0.054, [-11] = 0.0123, [-10] = 0.0155, [-9] = 0.0485, [-8] = 0.012, [-7] = 0.1085, [-6] = 0.0438, [-5] = 0.1086, [-4] = 0.0865, [-3] = 0.1009, [-2] = 0.2318, [-1] = 0.1527, [0] = 0.0893, [1] = 0.1237, [2] = 0.1896, [3] = 0.1302, [4] = 0.1341, [5] = 0.178, [6] = 0.0553, [7] = 0.2104, [8] = 0.0121, [9] = 0.0842, [10] = 0.012, [11] = 0.012, [12] = 0.0961 },
        rhythm_cells = {
            sparse = { { 1.5, 0.5, 2.0 }, { 2.0, 0.75, 0.25, 1.0 }, { 1.0, 2.0, 1.0 }, { 3.0, 0.33, 0.33, 0.34 } },
            medium = { { 0.75, 0.25, 1.0, 1.0, 1.0 }, { 1.0, 0.33, 0.33, 0.34, 1.0, 1.0 }, { 1.5, 0.5, 0.75, 0.25, 1.0 }, { 1.0, 0.5, 0.5, 1.5, 0.5 } },
            dense = { { 0.33, 0.33, 0.34, 0.75, 0.25, 0.5, 0.5, 1.0 }, { 0.75, 0.25, 0.5, 0.5, 0.33, 0.33, 0.34, 1.0 }, { 0.5, 0.25, 0.25, 0.5, 0.5, 0.75, 0.25, 1.0 } },
        },
        cadence_approaches = { { -5 }, { -1 }, { 2, -1 }, { -2, -1 }, { 5 } },
    },
    [3] = {
        id = "film_style_2",
        name = "🌙 Film Composer Style 2 (Mysterious Pulse & Lyrical Suspense)",
        default_scale = "dorian",
        trained_scores = 450,
        trained_notes = 15158,
        gap_fill_strength = 0.693,
        legato_ratio = 0.95,
        staccato_prob = 0.12,
        accent_prob = 0.22,
        anticipation_prob = 0.32,
        triad_fanfare_bonus = 0.1,
        pivot_return_bonus = 0.92,
        sequence_repeat_bonus = 0.35,
        avoid_semitone_lead = false,
        modal_color_semitones = { 8, 9 },
        interval_weights = { [-12] = 0.0248, [-11] = 0.0125, [-10] = 0.0127, [-9] = 0.059, [-8] = 0.0914, [-7] = 0.0833, [-6] = 0.0154, [-5] = 0.0883, [-4] = 0.0609, [-3] = 0.1685, [-2] = 0.1951, [-1] = 0.204, [0] = 0.0954, [1] = 0.2147, [2] = 0.2136, [3] = 0.209, [4] = 0.0984, [5] = 0.0891, [6] = 0.0128, [7] = 0.1065, [8] = 0.1323, [9] = 0.0721, [10] = 0.012, [11] = 0.012, [12] = 0.0121 },
        rhythm_cells = {
            sparse = { { 1.5, 1.5, 1.0 }, { 2.0, 0.5, 1.5 }, { 1.0, 1.5, 1.5 }, { 2.5, 0.5, 1.0 } },
            medium = { { 0.5, 0.5, 1.5, 0.5, 1.0 }, { 1.0, 0.5, 1.0, 0.5, 1.0 }, { 1.5, 0.5, 0.5, 0.5, 1.0 }, { 0.5, 1.0, 0.5, 1.0, 1.0 } },
            dense = { { 0.5, 0.5, 0.5, 0.5, 0.5, 0.5, 1.0 }, { 0.5, 0.25, 0.25, 0.5, 0.5, 0.5, 0.5, 1.0 }, { 0.5, 0.5, 0.5, 1.0, 0.5, 0.5, 0.5 } },
        },
        cadence_approaches = { { 1 }, { -1 }, { -3, 1 }, { 2, -1 }, { -2, 1 } },
    },
    [4] = {
        id = "film_style_3",
        name = "🔥 Film Composer Style 3 (Kinetic Action & Propulsive Hybrid)",
        default_scale = "aeolian",
        trained_scores = 450,
        trained_notes = 20525,
        gap_fill_strength = 0.739,
        legato_ratio = 0.74,
        staccato_prob = 0.48,
        accent_prob = 0.52,
        anticipation_prob = 0.38,
        triad_fanfare_bonus = 0.45,
        pivot_return_bonus = 0.4,
        sequence_repeat_bonus = 0.95,
        avoid_semitone_lead = false,
        modal_color_semitones = { 3, 7, 10 },
        interval_weights = { [-12] = 0.0664, [-11] = 0.0122, [-10] = 0.0614, [-9] = 0.0121, [-8] = 0.0122, [-7] = 0.1306, [-6] = 0.0223, [-5] = 0.1252, [-4] = 0.0645, [-3] = 0.1403, [-2] = 0.161, [-1] = 0.1314, [0] = 0.3031, [1] = 0.1181, [2] = 0.1562, [3] = 0.1562, [4] = 0.0639, [5] = 0.1508, [6] = 0.0193, [7] = 0.168, [8] = 0.0122, [9] = 0.0121, [10] = 0.0743, [11] = 0.014, [12] = 0.0902 },
        rhythm_cells = {
            sparse = { { 1.5, 1.5, 1.0 }, { 1.0, 1.0, 1.5, 0.5 }, { 0.75, 0.75, 0.5, 2.0 } },
            medium = { { 0.75, 0.75, 0.5, 0.75, 0.75, 0.5 }, { 0.5, 0.5, 0.5, 0.5, 0.75, 0.75, 0.5 }, { 1.0, 0.5, 0.5, 0.5, 0.5, 1.0 } },
            dense = { { 0.5, 0.25, 0.25, 0.5, 0.25, 0.25, 0.5, 0.5, 0.5, 0.5 }, { 0.25, 0.25, 0.5, 0.5, 0.25, 0.25, 0.5, 0.5, 0.5, 0.5 }, { 0.75, 0.25, 0.5, 0.5, 0.25, 0.25, 0.5, 0.5, 0.5 } },
        },
        cadence_approaches = { { -2 }, { -1 }, { 0, -2 }, { -3, -2 }, { 2, 0 } },
    },
    [5] = {
        id = "film_style_4",
        name = "🌊 Film Composer Style 4 (Pastoral & Lyrical Epic Romance)",
        default_scale = "mixolydian",
        trained_scores = 450,
        trained_notes = 18579,
        gap_fill_strength = 0.736,
        legato_ratio = 0.98,
        staccato_prob = 0.03,
        accent_prob = 0.2,
        anticipation_prob = 0.22,
        triad_fanfare_bonus = 0.55,
        pivot_return_bonus = 0.3,
        sequence_repeat_bonus = 0.3,
        avoid_semitone_lead = true,
        modal_color_semitones = { 2, 7, 9, 10 },
        interval_weights = { [-12] = 0.0612, [-11] = 0.0154, [-10] = 0.0257, [-9] = 0.088, [-8] = 0.0159, [-7] = 0.1292, [-6] = 0.0135, [-5] = 0.1349, [-4] = 0.0973, [-3] = 0.1535, [-2] = 0.2417, [-1] = 0.0437, [0] = 0.0499, [1] = 0.0731, [2] = 0.2911, [3] = 0.175, [4] = 0.1391, [5] = 0.1723, [6] = 0.016, [7] = 0.1778, [8] = 0.0134, [9] = 0.1105, [10] = 0.012, [11] = 0.012, [12] = 0.0756 },
        rhythm_cells = {
            sparse = { { 2.0, 1.5, 0.5 }, { 1.5, 0.25, 0.25, 2.0 }, { 2.5, 0.5, 1.0 }, { 3.0, 0.5, 0.5 } },
            medium = { { 1.5, 0.25, 0.25, 1.0, 1.0 }, { 1.0, 1.5, 0.5, 1.0 }, { 1.5, 0.5, 1.0, 0.5, 0.5 }, { 2.0, 0.5, 0.5, 1.0 } },
            dense = { { 0.5, 0.25, 0.25, 1.0, 0.5, 0.5, 1.0 }, { 1.0, 0.25, 0.25, 0.5, 0.5, 0.5, 1.0 }, { 0.75, 0.25, 0.5, 0.5, 0.5, 0.5, 1.0 } },
        },
        cadence_approaches = { { -2 }, { 2 }, { -3, -2 }, { 3, 2 }, { -5, -2 } },
    },
    [6] = {
        id = "classical",
        name = "🎻 Classical / Baroque (Chamber & Counterpoint)",
        default_scale = "major",
        trained_scores = 300,
        trained_notes = 7876,
        gap_fill_strength = 0.642,
        legato_ratio = 0.9,
        staccato_prob = 0.22,
        accent_prob = 0.2,
        anticipation_prob = 0.08,
        triad_fanfare_bonus = 0.25,
        pivot_return_bonus = 0.15,
        sequence_repeat_bonus = 0.55,
        avoid_semitone_lead = false,
        modal_color_semitones = { 4, 7, 11 },
        interval_weights = { [-12] = 0.0272, [-11] = 0.0127, [-10] = 0.0133, [-9] = 0.0214, [-8] = 0.014, [-7] = 0.054, [-6] = 0.018, [-5] = 0.0738, [-4] = 0.0975, [-3] = 0.112, [-2] = 0.2298, [-1] = 0.169, [0] = 0.0612, [1] = 0.1465, [2] = 0.2037, [3] = 0.2105, [4] = 0.1439, [5] = 0.0693, [6] = 0.0127, [7] = 0.0649, [8] = 0.0305, [9] = 0.03, [10] = 0.012, [11] = 0.012, [12] = 0.024 },
        rhythm_cells = {
            sparse = { { 1.0, 1.0, 1.0, 1.0 }, { 2.0, 1.0, 1.0 }, { 1.5, 0.5, 1.0, 1.0 } },
            medium = { { 1.0, 0.5, 0.5, 1.0, 1.0 }, { 0.5, 0.5, 0.5, 0.5, 1.0, 1.0 }, { 1.0, 1.0, 0.5, 0.5, 0.5, 0.5 } },
            dense = { { 0.25, 0.25, 0.25, 0.25, 0.5, 0.5, 0.5, 0.5, 1.0 }, { 0.5, 0.25, 0.25, 0.5, 0.25, 0.25, 0.5, 0.5, 1.0 }, { 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.25, 0.5, 0.5, 1.0 } },
        },
        cadence_approaches = { { -1 }, { 1 }, { 1, -1 }, { -2, -1 }, { 2, 1 } },
    },
    [7] = {
        id = "romantic",
        name = "🌹 Romantic / Lyrical (Cantabile / Late-Romantic)",
        default_scale = "harmonic_minor",
        trained_scores = 300,
        trained_notes = 10398,
        gap_fill_strength = 0.754,
        legato_ratio = 0.98,
        staccato_prob = 0.05,
        accent_prob = 0.25,
        anticipation_prob = 0.2,
        triad_fanfare_bonus = 0.3,
        pivot_return_bonus = 0.25,
        sequence_repeat_bonus = 0.35,
        avoid_semitone_lead = false,
        modal_color_semitones = { 8, 11 },
        interval_weights = { [-12] = 0.0523, [-11] = 0.0122, [-10] = 0.012, [-9] = 0.0483, [-8] = 0.0546, [-7] = 0.0766, [-6] = 0.0125, [-5] = 0.0727, [-4] = 0.0864, [-3] = 0.1132, [-2] = 0.2359, [-1] = 0.1747, [0] = 0.04, [1] = 0.178, [2] = 0.2451, [3] = 0.1088, [4] = 0.119, [5] = 0.0889, [6] = 0.0126, [7] = 0.1076, [8] = 0.0841, [9] = 0.0782, [10] = 0.012, [11] = 0.012, [12] = 0.0601 },
        rhythm_cells = {
            sparse = { { 2.5, 0.5, 1.0 }, { 1.5, 0.5, 2.0 }, { 2.0, 1.0, 1.0 } },
            medium = { { 1.5, 0.5, 0.5, 0.5, 1.0 }, { 1.0, 1.5, 0.5, 1.0 }, { 0.5, 1.0, 0.5, 1.0, 1.0 } },
            dense = { { 0.5, 0.5, 0.25, 0.25, 0.5, 1.0, 0.5, 0.5 }, { 0.75, 0.25, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 } },
        },
        cadence_approaches = { { -1 }, { 1, -1 }, { -3, -1 }, { 2, 1 }, { -2, -1 } },
    },
    [8] = {
        id = "punky",
        name = "⚡ Punky / Driving Action (Syncopated Pulse)",
        default_scale = "minor_pentatonic",
        trained_scores = 300,
        trained_notes = 13344,
        gap_fill_strength = 0.766,
        legato_ratio = 0.55,
        staccato_prob = 0.65,
        accent_prob = 0.45,
        anticipation_prob = 0.45,
        triad_fanfare_bonus = 0.15,
        pivot_return_bonus = 0.55,
        sequence_repeat_bonus = 0.65,
        avoid_semitone_lead = true,
        modal_color_semitones = { 3, 6, 10 },
        interval_weights = { [-12] = 0.0411, [-11] = 0.0123, [-10] = 0.0604, [-9] = 0.0138, [-8] = 0.0135, [-7] = 0.1418, [-6] = 0.0636, [-5] = 0.1048, [-4] = 0.0583, [-3] = 0.1437, [-2] = 0.1398, [-1] = 0.0535, [0] = 0.2791, [1] = 0.0517, [2] = 0.1367, [3] = 0.1849, [4] = 0.0714, [5] = 0.12, [6] = 0.06, [7] = 0.1586, [8] = 0.0124, [9] = 0.0121, [10] = 0.0636, [11] = 0.0151, [12] = 0.0799 },
        rhythm_cells = {
            sparse = { { 1.5, 1.5, 1.0 }, { 1.0, 1.5, 0.5, 1.0 }, { 0.5, 1.0, 1.5, 1.0 } },
            medium = { { 0.75, 0.75, 0.5, 0.5, 0.5, 1.0 }, { 0.5, 0.5, 0.75, 0.75, 0.5, 0.5, 0.5 }, { 0.5, 1.0, 0.5, 0.5, 0.5, 0.5, 0.5 } },
            dense = { { 0.5, 0.25, 0.25, 0.5, 0.5, 0.25, 0.25, 0.5, 0.5, 0.5 }, { 0.25, 0.25, 0.5, 0.25, 0.25, 0.5, 0.5, 0.5, 0.5, 0.5 } },
        },
        cadence_approaches = { { 0 }, { -2 }, { -3 }, { 0, -1 }, { 3, 0 } },
    },
    [9] = {
        id = "celtic_ancient",
        name = "🏛 Ancient / Celtic Modal (Dorian / Mythic)",
        default_scale = "dorian",
        trained_scores = 300,
        trained_notes = 16053,
        gap_fill_strength = 0.733,
        legato_ratio = 0.88,
        staccato_prob = 0.18,
        accent_prob = 0.25,
        anticipation_prob = 0.18,
        triad_fanfare_bonus = 0.35,
        pivot_return_bonus = 0.35,
        sequence_repeat_bonus = 0.3,
        avoid_semitone_lead = true,
        modal_color_semitones = { 2, 7, 9, 10 },
        interval_weights = { [-12] = 0.0273, [-11] = 0.0158, [-10] = 0.0278, [-9] = 0.0463, [-8] = 0.0165, [-7] = 0.0945, [-6] = 0.0138, [-5] = 0.0993, [-4] = 0.072, [-3] = 0.1145, [-2] = 0.1836, [-1] = 0.1024, [0] = 0.0594, [1] = 0.1356, [2] = 0.2584, [3] = 0.1536, [4] = 0.1145, [5] = 0.1245, [6] = 0.0166, [7] = 0.107, [8] = 0.0136, [9] = 0.0508, [10] = 0.012, [11] = 0.012, [12] = 0.0401 },
        rhythm_cells = {
            sparse = { { 1.5, 0.5, 1.5, 0.5 }, { 2.0, 1.0, 1.0 }, { 1.0, 2.0, 1.0 } },
            medium = { { 0.75, 0.25, 0.5, 0.5, 1.0, 1.0 }, { 1.0, 0.5, 0.5, 0.75, 0.25, 1.0 }, { 0.5, 0.5, 1.0, 0.5, 0.5, 1.0 } },
            dense = { { 0.25, 0.25, 0.5, 0.5, 0.5, 0.25, 0.25, 0.5, 0.5, 0.5 }, { 0.5, 0.25, 0.25, 0.25, 0.25, 0.5, 0.5, 0.5, 1.0 } },
        },
        cadence_approaches = { { -2 }, { 1 }, { -1, 1 }, { -3, -1 }, { 2, 1 } },
    },
    [10] = {
        id = "thriller",
        name = "🕵️ Dark Thriller / Suspense (Phrygian / Noir)",
        default_scale = "phrygian",
        trained_scores = 300,
        trained_notes = 12160,
        gap_fill_strength = 0.708,
        legato_ratio = 0.78,
        staccato_prob = 0.42,
        accent_prob = 0.38,
        anticipation_prob = 0.25,
        triad_fanfare_bonus = 0.05,
        pivot_return_bonus = 0.8,
        sequence_repeat_bonus = 0.35,
        avoid_semitone_lead = false,
        modal_color_semitones = { 1, 6, 8 },
        interval_weights = { [-12] = 0.0161, [-11] = 0.048, [-10] = 0.012, [-9] = 0.012, [-8] = 0.012, [-7] = 0.0669, [-6] = 0.1239, [-5] = 0.0569, [-4] = 0.044, [-3] = 0.0737, [-2] = 0.1151, [-1] = 0.2217, [0] = 0.2959, [1] = 0.2031, [2] = 0.0908, [3] = 0.0941, [4] = 0.0592, [5] = 0.0573, [6] = 0.1198, [7] = 0.0717, [8] = 0.012, [9] = 0.012, [10] = 0.012, [11] = 0.048, [12] = 0.016 },
        rhythm_cells = {
            sparse = { { 2.0, 0.5, 1.5 }, { 1.5, 1.5, 1.0 }, { 3.0, 0.5, 0.5 } },
            medium = { { 1.0, 0.5, 0.5, 1.5, 0.5 }, { 0.5, 0.5, 1.0, 0.5, 0.5, 1.0 }, { 1.5, 0.25, 0.25, 1.0, 1.0 } },
            dense = { { 0.25, 0.25, 0.5, 0.25, 0.25, 0.5, 1.0, 0.5, 0.5 }, { 0.5, 0.25, 0.25, 0.5, 0.5, 0.25, 0.25, 0.5, 1.0 } },
        },
        cadence_approaches = { { 1 }, { -1 }, { 6, 1 }, { -1, 1 }, { 1, -1 } },
    },
}

-- ==============================================================================
-- FILM SCORE ARCHETYPE EXTENSIONS (Melodic Pathfinder 2.0)
-- Hand-authored, purely descriptive soundtrack archetypes (no real composer names).
-- Merged on top of the trained statistics above so the training script can
-- regenerate the empirical data without losing the compositional grammar.
--
-- Field reference:
--   motif_templates   : Leitmotif cells, 2 bars (8 QN) each. `d` = diatonic scale
--                       degree relative to the tonic (0 = tonic, 4 = fifth,
--                       7 = octave, -3 = fifth below), `l` = duration in QN,
--                       optional `c` = chromatic alteration in semitones.
--   sequence_step     : diatonic transposition used for the varied repetition (A').
--   progression       : implied per-bar chord roots (scale degrees) when no
--                       Reference Track / Chord Lane harmony is available.
--   half_cadence_deg  : chord root used for open (half) cadences (A / B phrases).
--   suspension_prob   : affinity for strong-beat appoggiaturas / suspensions.
--   rest_prob         : affinity for phrase-end breathing rests.
--   default_curves    : default Tension / Note Length / Pitch curve points {t, v}.
-- ==============================================================================

local MAGICAL_WALTZ = {
    id = "magical_waltz",
    default_scale = "lydian",
    trained_scores = 240,
    trained_notes = 9120,
    gap_fill_strength = 0.74,
    legato_ratio = 0.95,
    staccato_prob = 0.10,
    accent_prob = 0.18,
    anticipation_prob = 0.16,
    triad_fanfare_bonus = 0.45,
    pivot_return_bonus = 0.30,
    sequence_repeat_bonus = 0.70,
    avoid_semitone_lead = false,
    modal_color_semitones = { 6, 11, 2 },
    interval_weights = { [-12] = 0.03, [-11] = 0.012, [-10] = 0.014, [-9] = 0.05, [-8] = 0.03, [-7] = 0.07, [-6] = 0.012, [-5] = 0.08, [-4] = 0.10, [-3] = 0.15, [-2] = 0.24, [-1] = 0.12, [0] = 0.06, [1] = 0.12, [2] = 0.24, [3] = 0.16, [4] = 0.13, [5] = 0.10, [6] = 0.02, [7] = 0.09, [8] = 0.05, [9] = 0.07, [10] = 0.012, [11] = 0.02, [12] = 0.04 },
    rhythm_cells = {
        sparse = { { 3.0, 1.0 }, { 2.0, 1.0, 1.0 }, { 1.5, 0.5, 2.0 } },
        medium = { { 1.0, 0.5, 0.5, 2.0 }, { 0.5, 0.5, 1.0, 1.0, 1.0 }, { 1.5, 0.5, 1.0, 1.0 } },
        dense  = { { 0.5, 0.5, 0.5, 0.5, 1.0, 1.0 }, { 0.5, 0.25, 0.25, 0.5, 0.5, 1.0, 1.0 } },
    },
    cadence_approaches = { { -1 }, { 2, -1 }, { -2, -1 }, { 1 } },
}
table.insert(MelodyStyleCorpus.STYLES, MAGICAL_WALTZ)

MelodyStyleCorpus.ARCHETYPES = {
    film_style_1 = {
        name = "🎺 Heroic Symphonic Fanfare",
        description = "Rising 4ths & 5ths, triplet fanfare pickups, dotted heroic stride, Lydian wonder cadences.",
        sequence_step = 1, half_cadence_deg = 4, suspension_prob = 0.30, rest_prob = 0.35,
        progression = { 0, 3, 5, 4 },
        motif_templates = {
            { { d = -3, l = 1.0 }, { d = 0, l = 1.0 }, { d = 4, l = 2.0 }, { d = 3, l = 0.5 }, { d = 2, l = 0.5 }, { d = 3, l = 0.5 }, { d = 1, l = 0.5 }, { d = 4, l = 2.0 } },
            { { d = 0, l = 0.33 }, { d = 0, l = 0.33 }, { d = 0, l = 0.34 }, { d = 4, l = 1.5 }, { d = 3, l = 0.5 }, { d = 2, l = 0.33 }, { d = 3, l = 0.33 }, { d = 2, l = 0.34 }, { d = 0, l = 3.0 }, { d = -3, l = 1.0 } },
            { { d = 0, l = 1.5 }, { d = 4, l = 0.5 }, { d = 7, l = 2.0 }, { d = 6, l = 0.5 }, { d = 4, l = 0.5 }, { d = 5, l = 0.5 }, { d = 6, l = 0.5 }, { d = 4, l = 2.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.45 }, { 0.55, 0.85 }, { 0.8, 0.95 }, { 1.0, 0.50 } },
            note_length = { { 0.0, 0.60 }, { 0.5, 0.45 }, { 1.0, 0.80 } },
            pitch       = { { 0.0, 0.35 }, { 0.6, 0.80 }, { 1.0, 0.50 } },
        },
    },
    cinematic = {
        name = "⏳ Emotional Slow-Burn & Minimalist Ostinato",
        description = "Deep minor anchor, long aching pedal/suspension notes, gradual build into a golden-ratio climax.",
        sequence_step = 1, half_cadence_deg = 6, suspension_prob = 0.65, rest_prob = 0.55,
        progression = { 0, 5, 2, 6 },
        motif_templates = {
            { { d = 0, l = 3.0 }, { d = 4, l = 1.0 }, { d = 5, l = 3.0 }, { d = 4, l = 1.0 } },
            { { d = 0, l = 2.0 }, { d = 1, l = 1.0 }, { d = 2, l = 1.0 }, { d = 1, l = 3.0 }, { d = 0, l = 1.0 } },
            { { d = 4, l = 4.0 }, { d = 5, l = 2.0 }, { d = 4, l = 1.0 }, { d = 2, l = 1.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.12 }, { 0.62, 0.95 }, { 1.0, 0.30 } },
            note_length = { { 0.0, 0.90 }, { 0.62, 0.50 }, { 1.0, 0.85 } },
            pitch       = { { 0.0, 0.25 }, { 0.62, 0.85 }, { 1.0, 0.40 } },
        },
    },
    romantic = {
        name = "🌹 Nostalgic Cinema & Lyrical Cantabile",
        description = "Expressive 6th/octave leap into a long suspended note, then a singing stepwise descent.",
        sequence_step = -1, half_cadence_deg = 4, suspension_prob = 0.70, rest_prob = 0.45,
        progression = { 0, 5, 3, 4 },
        motif_templates = {
            { { d = -3, l = 1.0 }, { d = 2, l = 2.5 }, { d = 1, l = 0.5 }, { d = 0, l = 1.0 }, { d = -1, l = 1.0 }, { d = -2, l = 1.0 }, { d = -3, l = 1.0 } },
            { { d = 4, l = 1.5 }, { d = 3, l = 0.5 }, { d = 2, l = 1.0 }, { d = 4, l = 1.0 }, { d = 7, l = 2.0 }, { d = 6, l = 1.0 }, { d = 5, l = 1.0 } },
            { { d = 0, l = 1.0 }, { d = 4, l = 1.0 }, { d = 5, l = 2.0 }, { d = 4, l = 0.5 }, { d = 3, l = 0.5 }, { d = 2, l = 1.0 }, { d = 1, l = 2.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.30 }, { 0.5, 0.70 }, { 0.75, 0.55 }, { 1.0, 0.20 } },
            note_length = { { 0.0, 0.75 }, { 0.5, 0.55 }, { 1.0, 0.80 } },
            pitch       = { { 0.0, 0.40 }, { 0.45, 0.80 }, { 1.0, 0.35 } },
        },
    },
    film_style_4 = {
        name = "🏔️ Mythic Fellowship & Pastoral Nobility",
        description = "Pure modal voice-leading without chromatic leading tones, noble step-and-third arches.",
        sequence_step = 1, half_cadence_deg = 6, suspension_prob = 0.35, rest_prob = 0.45,
        progression = { 0, 6, 3, 0 },
        motif_templates = {
            { { d = 0, l = 1.0 }, { d = 1, l = 1.0 }, { d = 2, l = 1.0 }, { d = 4, l = 1.0 }, { d = 3, l = 1.5 }, { d = 2, l = 0.5 }, { d = 1, l = 1.0 }, { d = 0, l = 1.0 } },
            { { d = 0, l = 1.5 }, { d = 1, l = 0.5 }, { d = 2, l = 2.0 }, { d = 4, l = 1.0 }, { d = 2, l = 1.0 }, { d = 1, l = 2.0 } },
            { { d = 4, l = 2.0 }, { d = 5, l = 1.0 }, { d = 4, l = 1.0 }, { d = 2, l = 1.5 }, { d = 1, l = 0.5 }, { d = 0, l = 2.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.30 }, { 0.6, 0.60 }, { 1.0, 0.25 } },
            note_length = { { 0.0, 0.70 }, { 0.5, 0.60 }, { 1.0, 0.85 } },
            pitch       = { { 0.0, 0.40 }, { 0.5, 0.65 }, { 1.0, 0.40 } },
        },
    },
    magical_waltz = {
        name = "✨ Magical Wonder & Poetic Waltz",
        description = "Add9 / Major-7th / Lydian color tones, rising 2-bar sequences and lyrical descending cascades.",
        sequence_step = 2, half_cadence_deg = 4, suspension_prob = 0.40, rest_prob = 0.35,
        progression = { 0, 1, 5, 4 },
        motif_templates = {
            { { d = 0, l = 0.5 }, { d = 1, l = 0.5 }, { d = 2, l = 0.5 }, { d = 4, l = 0.5 }, { d = 5, l = 2.0 }, { d = 4, l = 0.5 }, { d = 2, l = 0.5 }, { d = 1, l = 0.5 }, { d = 2, l = 0.5 }, { d = 4, l = 2.0 } },
            { { d = 4, l = 1.5 }, { d = 3, l = 0.5 }, { d = 4, l = 1.0 }, { d = 6, l = 1.0 }, { d = 7, l = 3.0 }, { d = 6, l = 1.0 } },
            { { d = 2, l = 1.0 }, { d = 1, l = 0.5 }, { d = 2, l = 0.5 }, { d = 4, l = 2.0 }, { d = 1, l = 1.0 }, { d = 0, l = 0.5 }, { d = 1, l = 0.5 }, { d = 2, l = 2.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.35 }, { 0.5, 0.65 }, { 1.0, 0.40 } },
            note_length = { { 0.0, 0.45 }, { 0.5, 0.55 }, { 1.0, 0.70 } },
            pitch       = { { 0.0, 0.40 }, { 0.35, 0.60 }, { 0.7, 0.75 }, { 1.0, 0.45 } },
        },
    },
    film_style_2 = {
        name = "🎠 Chamber Mystery & Pivot Suspense",
        description = "Hypnotic pivot-tone returns, delicate chamber articulation, crisp rests and open half-cadences.",
        sequence_step = 1, half_cadence_deg = 4, suspension_prob = 0.45, rest_prob = 0.60,
        progression = { 0, 3, 5, 4 },
        motif_templates = {
            { { d = 4, l = 0.5 }, { d = 3, l = 0.5, c = 1 }, { d = 4, l = 0.5 }, { d = 5, l = 0.5 }, { d = 4, l = 1.0 }, { d = 2, l = 1.0 }, { d = 4, l = 0.5 }, { d = 3, l = 0.5, c = 1 }, { d = 4, l = 0.5 }, { d = 5, l = 0.5 }, { d = 6, l = 1.0 }, { d = 4, l = 1.0 } },
            { { d = 0, l = 1.0 }, { d = 2, l = 0.5 }, { d = 1, l = 0.5 }, { d = 0, l = 1.0 }, { d = -1, l = 1.0 }, { d = 0, l = 1.5 }, { d = 2, l = 0.5 }, { d = 4, l = 2.0 } },
            { { d = 2, l = 0.75 }, { d = 1, l = 0.25 }, { d = 2, l = 1.0 }, { d = 4, l = 1.0 }, { d = 3, l = 1.0 }, { d = 2, l = 0.75 }, { d = 1, l = 0.25 }, { d = 0, l = 1.0 }, { d = -1, l = 2.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.45 }, { 0.5, 0.60 }, { 1.0, 0.65 } },
            note_length = { { 0.0, 0.40 }, { 1.0, 0.50 } },
            pitch       = { { 0.0, 0.50 }, { 0.5, 0.55 }, { 1.0, 0.50 } },
        },
    },
    thriller = {
        name = "🕵️ Neo-Noir & Phrygian Thriller",
        description = "Phrygian b2 and tritone tension cells, sparse low phrases with ominous sustains and sudden spikes.",
        sequence_step = 1, half_cadence_deg = 1, suspension_prob = 0.50, rest_prob = 0.65,
        progression = { 0, 1, 0, 3 },
        motif_templates = {
            { { d = 0, l = 2.0 }, { d = 1, l = 1.0 }, { d = 0, l = 1.0 }, { d = -2, l = 3.0 }, { d = -1, l = 1.0 } },
            { { d = 0, l = 1.5 }, { d = 1, l = 0.5 }, { d = 0, l = 1.0 }, { d = 4, l = 1.0, c = -1 }, { d = 3, l = 3.0 }, { d = 0, l = 1.0 } },
            { { d = 0, l = 4.0 }, { d = 1, l = 2.0 }, { d = 0, l = 2.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.15 }, { 0.7, 0.30 }, { 0.85, 0.90 }, { 1.0, 0.40 } },
            note_length = { { 0.0, 0.85 }, { 0.8, 0.60 }, { 1.0, 0.90 } },
            pitch       = { { 0.0, 0.20 }, { 0.8, 0.45 }, { 1.0, 0.25 } },
        },
    },
    film_style_3 = {
        name = "🔥 Kinetic Orchestral Action & Pursuit",
        description = "Propulsive asymmetric 3+3+2 cells, tight motivic cells sequenced upward under rising tension.",
        sequence_step = 1, half_cadence_deg = 6, suspension_prob = 0.15, rest_prob = 0.20,
        progression = { 0, 5, 6, 0 },
        motif_templates = {
            { { d = 0, l = 1.5 }, { d = 0, l = 1.5 }, { d = 2, l = 1.0 }, { d = 1, l = 1.5 }, { d = 1, l = 1.5 }, { d = -1, l = 1.0 } },
            { { d = 0, l = 0.5 }, { d = 0, l = 0.5 }, { d = 2, l = 0.5 }, { d = 0, l = 0.5 }, { d = 3, l = 0.5 }, { d = 2, l = 0.5 }, { d = 1, l = 1.0 }, { d = 0, l = 0.75 }, { d = 0, l = 0.75 }, { d = 4, l = 0.5 }, { d = 3, l = 1.0 }, { d = 2, l = 1.0 } },
            { { d = 4, l = 1.5 }, { d = 3, l = 1.5 }, { d = 2, l = 1.0 }, { d = 4, l = 1.5 }, { d = 5, l = 1.5 }, { d = 4, l = 1.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.60 }, { 0.7, 0.95 }, { 1.0, 0.75 } },
            note_length = { { 0.0, 0.25 }, { 0.7, 0.15 }, { 1.0, 0.40 } },
            pitch       = { { 0.0, 0.35 }, { 1.0, 0.75 } },
        },
    },
    classical = {
        name = "🎻 Classical Chamber & Counterpoint",
        description = "Balanced antecedent/consequent periods, triadic outlines and stepwise counterpoint.",
        sequence_step = 1, half_cadence_deg = 4, suspension_prob = 0.35, rest_prob = 0.30,
        progression = { 0, 3, 4, 0 },
        motif_templates = {
            { { d = 0, l = 1.0 }, { d = 2, l = 1.0 }, { d = 4, l = 1.0 }, { d = 2, l = 1.0 }, { d = 3, l = 1.0 }, { d = 1, l = 1.0 }, { d = -1, l = 1.0 }, { d = 0, l = 1.0 } },
            { { d = 4, l = 1.0 }, { d = 3, l = 0.5 }, { d = 2, l = 0.5 }, { d = 1, l = 1.0 }, { d = 0, l = 1.0 }, { d = 1, l = 0.5 }, { d = 2, l = 0.5 }, { d = 3, l = 1.0 }, { d = 1, l = 2.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.35 }, { 0.6, 0.60 }, { 1.0, 0.25 } },
            note_length = { { 0.0, 0.50 }, { 1.0, 0.60 } },
            pitch       = { { 0.0, 0.40 }, { 0.55, 0.65 }, { 1.0, 0.40 } },
        },
    },
    celtic_ancient = {
        name = "🏛 Ancient Modal Legend (Dorian / Mythic)",
        description = "Dorian folk-symphonic phrasing with dotted lilts and whole-step modal cadences.",
        sequence_step = 1, half_cadence_deg = 6, suspension_prob = 0.30, rest_prob = 0.40,
        progression = { 0, 6, 3, 0 },
        motif_templates = {
            { { d = 0, l = 1.5 }, { d = 1, l = 0.5 }, { d = 2, l = 1.0 }, { d = 4, l = 1.0 }, { d = 3, l = 0.5 }, { d = 2, l = 0.5 }, { d = 1, l = 1.0 }, { d = 0, l = 2.0 } },
            { { d = 4, l = 0.75 }, { d = 3, l = 0.25 }, { d = 2, l = 1.0 }, { d = 0, l = 1.0 }, { d = 1, l = 1.0 }, { d = 2, l = 1.5 }, { d = 1, l = 0.5 }, { d = 0, l = 2.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.30 }, { 0.55, 0.60 }, { 1.0, 0.30 } },
            note_length = { { 0.0, 0.60 }, { 1.0, 0.75 } },
            pitch       = { { 0.0, 0.40 }, { 0.5, 0.65 }, { 1.0, 0.40 } },
        },
    },
    punky = {
        name = "⚡ Driving Syncopated Pulse",
        description = "Pentatonic riffs with syncopated 3+3+2 pushes and percussive repeated notes.",
        sequence_step = 1, half_cadence_deg = 4, suspension_prob = 0.10, rest_prob = 0.20,
        progression = { 0, 4, 3, 4 },
        motif_templates = {
            { { d = 0, l = 0.75 }, { d = 0, l = 0.75 }, { d = 2, l = 0.5 }, { d = 3, l = 1.0 }, { d = 2, l = 1.0 }, { d = 0, l = 0.75 }, { d = 0, l = 0.75 }, { d = 4, l = 0.5 }, { d = 3, l = 1.0 }, { d = 2, l = 1.0 } },
        },
        default_curves = {
            tension     = { { 0.0, 0.70 }, { 1.0, 0.75 } },
            note_length = { { 0.0, 0.25 }, { 1.0, 0.30 } },
            pitch       = { { 0.0, 0.50 }, { 1.0, 0.55 } },
        },
    },
}

-- Merge archetype grammar into the trained style tables
for _, st in ipairs(MelodyStyleCorpus.STYLES) do
    local ext = MelodyStyleCorpus.ARCHETYPES[st.id]
    if ext then
        for k, v in pairs(ext) do
            st[k] = v
        end
    end
end

-- Display order: the 8 Film Score archetypes first, then the additional concert styles
local DISPLAY_ORDER = {
    "film_style_1", "cinematic", "romantic", "film_style_4", "magical_waltz",
    "film_style_2", "thriller", "film_style_3", "classical", "celtic_ancient", "punky",
}
do
    local by_id, ordered, used = {}, {}, {}
    for _, st in ipairs(MelodyStyleCorpus.STYLES) do by_id[st.id] = st end
    for _, id in ipairs(DISPLAY_ORDER) do
        if by_id[id] then
            table.insert(ordered, by_id[id])
            used[id] = true
        end
    end
    for _, st in ipairs(MelodyStyleCorpus.STYLES) do
        if not used[st.id] then table.insert(ordered, st) end
    end
    MelodyStyleCorpus.STYLES = ordered
end

MelodyStyleCorpus.BY_ID = {}
for _, st in ipairs(MelodyStyleCorpus.STYLES) do
    MelodyStyleCorpus.BY_ID[st.id] = st
end

return MelodyStyleCorpus

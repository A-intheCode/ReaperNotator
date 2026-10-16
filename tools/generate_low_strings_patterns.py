#!/usr/bin/env python3
"""
REAPER-Notator - Staccato Celli & Double Bass Rhythm & Tension Pattern Generator
Generates 150 pure rhythm, pulse, and psychological/cinematic tension patterns
for Low Strings (Violoncelli & Contrabasses) into patterns/10_Low_Strings_Celli_Basses.
Designed for Bass Clef (E1=28 to G3=55) with zero melodic distraction — purely rhythmic
motors, half-step thriller ostinatos, tritone dissonance cells, odd-meter chases,
Divisi-ready Celli+Bass interlocking grooves, and sparse ticking-clock suspense.
"""

import os
import json
import random

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_DIR = os.path.join(REPO_ROOT, "patterns", "10_Low_Strings_Celli_Basses")
os.makedirs(TARGET_DIR, exist_ok=True)

PATTERNS_SPEC = [
    # ==========================================================================
    # 1. RELENTLESS PEDAL-POINT MOTORS (1-30) - Pure Single-Note & Octave Rhythm
    # ==========================================================================
    ("Celli & Basses - 3+3+2 Dark Knight Pedal Motor (D)", "pedal", (4, 4), 4, 136),
    ("Celli & Basses - Relentless 16th Spiccato Engine (C)", "pedal", (4, 4), 4, 140),
    ("Double Bass - Sub-Octave E1 Chugging Locomotive", "pedal", (4, 4), 4, 128),
    ("Celli Staccato - Syncopated 3+2+3 Adrenaline Pulse", "pedal", (4, 4), 4, 144),
    ("Celli & Basses - Ironclad 8th-Note Downbow Drive", "pedal", (4, 4), 4, 124),
    ("Double Bass - Heavy Martele Downbeat & 16th Pickup", "pedal", (4, 4), 4, 118),
    ("Celli Staccato - High-Tension Machine Gun Spiccato (A)", "pedal", (4, 4), 4, 148),
    ("Celli & Basses - 3+3+3+3+2+2 Two-Bar Propulsion", "pedal", (4, 4), 8, 138),
    ("Double Bass - Deep C1-C2 Octave Hammer Motor", "pedal", (4, 4), 4, 130),
    ("Celli Staccato - Offbeat Accent Nervous Grid (E)", "pedal", (4, 4), 4, 132),
    ("Celli & Basses - Armored Convoy Steady Grind (G)", "pedal", (4, 4), 4, 112),
    ("Double Bass - Gritty Rosin Bite 16th Gallop", "pedal", (4, 4), 4, 142),
    ("Celli Staccato - Triple-Stroke Burst Ostinato (F)", "pedal", (4, 4), 4, 134),
    ("Celli & Basses - Unstoppable Juggernaut Pedal (D)", "pedal", (4, 4), 8, 126),
    ("Double Bass - Low F1 Subterranean Rumble Pulse", "pedal", (4, 4), 4, 120),
    ("Celli Staccato - Tight Ricochet Spiccato Shimmer", "pedal", (4, 4), 4, 146),
    ("Celli & Basses - 12/8 Triplet Warhorse Engine", "pedal", (12, 8), 4, 132),
    ("Double Bass - Menacing Quarter-Note Stomp & Drag", "pedal", (4, 4), 4, 104),
    ("Celli Staccato - Shifted 16th Grid Displacement", "pedal", (4, 4), 4, 136),
    ("Celli & Basses - Cybernetic Pulse 2+3+3 (C)", "pedal", (4, 4), 4, 140),
    ("Double Bass - Dark Matter Low D1 Drone & Bite", "pedal", (4, 4), 4, 116),
    ("Celli Staccato - Perpetual Tension 16th Stream", "pedal", (4, 4), 8, 150),
    ("Celli & Basses - Hunted Prey Accelerando Feel", "pedal", (4, 4), 4, 144),
    ("Double Bass - Concrete Bunker Heavy 8ths (A1)", "pedal", (4, 4), 4, 122),
    ("Celli Staccato - Cross-Rhythm 3-over-4 Accents", "pedal", (4, 4), 4, 134),
    ("Celli & Basses - Stormfront Octave Lock (E1-E2)", "pedal", (4, 4), 8, 138),
    ("Double Bass - Diesel Engine Chug 16th-Rest Grid", "pedal", (4, 4), 4, 128),
    ("Celli Staccato - Razor-Edge Spiccato Syncopation", "pedal", (4, 4), 4, 142),
    ("Celli & Basses - Final Countdown Octave Drive", "pedal", (4, 4), 8, 148),
    ("Double Bass - Tectonic Plate Low C1 Ostinato", "pedal", (4, 4), 4, 110),

    # ==========================================================================
    # 2. SEMITONE (b2) THRILLER OSTINATOS (31-55) - Half-Step Claustrophobia
    # ==========================================================================
    ("Double Bass - Jaws-Style Deep Semitone Stalker (E1-F1)", "semitone", (4, 4), 4, 96),
    ("Celli & Basses - Phrygian b2 Thriller Motor (D-Eb)", "semitone", (4, 4), 4, 134),
    ("Celli Staccato - Claustrophobic Half-Step Crawl (C-Db)", "semitone", (4, 4), 4, 124),
    ("Double Bass - Abyssal Predator Semitone Creep (G1-Ab1)", "semitone", (4, 4), 4, 88),
    ("Celli & Basses - 16th-Note Panic Oscillation (A-Bb)", "semitone", (4, 4), 4, 144),
    ("Celli Staccato - Arachnid Half-Step Tremolo Pulse", "semitone", (4, 4), 4, 138),
    ("Double Bass - Submarine Hull Pressure (D1-Eb1)", "semitone", (4, 4), 4, 102),
    ("Celli & Basses - Nocturnal Ambush b2 Syncopation", "semitone", (4, 4), 8, 132),
    ("Celli Staccato - Vertigo Spiral Semitone Bite", "semitone", (3, 4), 8, 140),
    ("Double Bass - Shadow in the Fog Half-Step (F1-Gb1)", "semitone", (4, 4), 4, 92),
    ("Celli & Basses - High-Voltage Semitone 3+3+2", "semitone", (4, 4), 4, 142),
    ("Celli Staccato - Paranoia Nerve Ending (B-C)", "semitone", (4, 4), 4, 136),
    ("Double Bass - Kraken Tentacle Low Semitone", "semitone", (4, 4), 4, 108),
    ("Celli & Basses - Hostage Crisis Half-Step Motor", "semitone", (4, 4), 8, 128),
    ("Celli Staccato - Surgical Tension Chromatic Bite", "semitone", (4, 4), 4, 130),
    ("Double Bass - Haunted Catacombs Slow Semitone", "semitone", (4, 4), 4, 78),
    ("Celli & Basses - Escape Velocity b2 Overdrive", "semitone", (4, 4), 4, 152),
    ("Celli Staccato -Venomous Strike Half-Step 16ths", "semitone", (4, 4), 4, 140),
    ("Double Bass - Dreadnought Approaches (C1-Db1)", "semitone", (4, 4), 4, 84),
    ("Celli & Basses - Cold Sweat Semitone Gallop", "semitone", (6, 8), 8, 136),
    ("Celli Staccato - Geiger Counter Chromatic Twitch", "semitone", (4, 4), 4, 132),
    ("Double Bass - Underworld Ferryman Half-Step", "semitone", (4, 4), 4, 94),
    ("Celli & Basses - Defcon 1 Semitone Siren Pulse", "semitone", (4, 4), 8, 146),
    ("Celli Staccato - Labyrinth Minotaur b2 Breath", "semitone", (4, 4), 4, 122),
    ("Double Bass - Black Hole Event Horizon (E1-F1)", "semitone", (4, 4), 4, 114),

    # ==========================================================================
    # 3. TRITONE (b5) & MINOR-2ND DISSONANCE ENGINES (56-75)
    # ==========================================================================
    ("Celli & Basses - Diabolus in Musica Tritone Motor (C-F#)", "tritone", (4, 4), 4, 132),
    ("Double Bass - Locrian Doom Tritone Stomp (D1-Ab1)", "tritone", (4, 4), 4, 108),
    ("Celli Staccato - Fractured Psyche Tritone 16ths", "tritone", (4, 4), 4, 140),
    ("Celli & Basses - Chernobyl Reactor Meltdown (E-Bb)", "tritone", (4, 4), 4, 128),
    ("Double Bass - Gargoyle Awakening Low b5", "tritone", (4, 4), 4, 98),
    ("Celli Staccato - Jagged Glass Minor-9th & Tritone", "tritone", (4, 4), 4, 136),
    ("Celli & Basses - Dystopian Riot Control (G-Db)", "tritone", (4, 4), 8, 142),
    ("Double Bass - Seismic Faultline Tritone Shift", "tritone", (4, 4), 4, 116),
    ("Celli Staccato - Hitchcockian Suspense Tritone Stab", "tritone", (4, 4), 4, 124),
    ("Celli & Basses -Unholy Ritual Diminished Ostinato", "tritone", (3, 4), 8, 134),
    ("Double Bass - Toxic Waste Sub-Bass Tritone (F1-B1)", "tritone", (4, 4), 4, 104),
    ("Celli Staccato - Schizophrenic Accent Grid (A-Eb)", "tritone", (4, 4), 4, 144),
    ("Celli & Basses - Biohazard Containment Breach", "tritone", (4, 4), 4, 138),
    ("Double Bass - Behemoth Footfall Root-Tritone", "tritone", (4, 4), 4, 90),
    ("Celli Staccato - Electric Shock Dissonant Double-Stops", "tritone", (4, 4), 4, 130),
    ("Celli & Basses - Nosferatu Rising Diminished Pulse", "tritone", (4, 4), 8, 120),
    ("Double Bass - Iron Torture Chamber Low b5", "tritone", (4, 4), 4, 112),
    ("Celli Staccato - Whiplash Tritone Syncopation", "tritone", (4, 4), 4, 146),
    ("Celli & Basses - Maelstrom Vortex b2-b5 Engine", "tritone", (6, 8), 8, 136),
    ("Double Bass - Cataclysmic Tremor Final Tritone", "tritone", (4, 4), 4, 126),

    # ==========================================================================
    # 4. ODD-METER PURSUIT & ACTION MOTORS (76-100) - 5/8, 7/8, 5/4, 7/4
    # ==========================================================================
    ("Celli & Basses - 5/8 Relentless Manhunt (3+2)", "odd", (5, 8), 8, 152),
    ("Celli Staccato - 7/8 Balkan Assassin Chase (2+2+3)", "odd", (7, 8), 8, 148),
    ("Double Bass - 5/4 Mission Impossible Dark Stalker", "odd", (5, 4), 4, 128),
    ("Celli & Basses - 7/8 Cyber-Heist Laser Grid (3+2+2)", "odd", (7, 8), 8, 144),
    ("Celli Staccato - 5/8 Breathless Fugitive Sprint (2+3)", "odd", (5, 8), 8, 156),
    ("Double Bass - 7/4 Colossus Asymmetric March", "odd", (7, 4), 4, 118),
    ("Celli & Basses - 6/8 Dark Cavalry Pursuit", "odd", (6, 8), 8, 138),
    ("Celli Staccato - 5/4 Ticking Timebomb Ostinato", "odd", (5, 4), 4, 134),
    ("Double Bass - 7/8 Underground Tunnel Escape", "odd", (7, 8), 8, 140),
    ("Celli & Basses - 5/8 Sniper Crosshair Tension", "odd", (5, 8), 8, 146),
    ("Celli Staccato - 7/8 Irregular Heartbeat Panic", "odd", (7, 8), 8, 150),
    ("Double Bass - 5/4 Heavy Mech Walker Stride", "odd", (5, 4), 4, 112),
    ("Celli & Basses - 6/8 Stormy Cape Horn Gale", "odd", (6, 8), 8, 142),
    ("Celli Staccato - 5/8 Ricochet Bullet Spiccato", "odd", (5, 8), 8, 154),
    ("Double Bass - 7/8 Shadow Syndicate Low Groove", "odd", (7, 8), 8, 136),
    ("Celli & Basses - 5/4 Interrogation Room Pressure", "odd", (5, 4), 4, 124),
    ("Celli Staccato - 7/4 Labyrinthine Corridor Run", "odd", (7, 4), 4, 132),
    ("Double Bass - 5/8 Primal Beast Prowl (D1)", "odd", (5, 8), 8, 140),
    ("Celli & Basses - 7/8 High-Speed Train Derailment", "odd", (7, 8), 8, 152),
    ("Celli Staccato - 6/8 Witch Hunt Tarantella", "odd", (6, 8), 8, 144),
    ("Double Bass - 5/4 Iron Curtain Espionage Bass", "odd", (5, 4), 4, 120),
    ("Celli & Basses - 7/8 Asymmetric Blade Dance", "odd", (7, 8), 8, 148),
    ("Celli Staccato - 5/8 Nerve-Wracking Countdown", "odd", (5, 8), 8, 150),
    ("Double Bass - 7/4 Leviathan Rising From Trench", "odd", (7, 4), 4, 108),
    ("Celli & Basses - 5/8 Apex Thriller Finale", "odd", (5, 8), 8, 160),

    # ==========================================================================
    # 5. INTERLOCKING CELLI + BASS DIVISI-READY GROOVES (101-125)
    # Voice 1 = Celli (Spiccato 16ths), Voice 2 = Double Bass (Heavy Anchors)
    # ==========================================================================
    ("Celli & Basses [Divisi] - Heavy Bass Anchor & Celli 16ths", "divisi", (4, 4), 4, 134),
    ("Celli & Basses [Divisi] - Call & Response ThrillerHocketing", "divisi", (4, 4), 4, 138),
    ("Celli & Basses [Divisi] - Contrabass Stabs vs Celli Motor", "divisi", (4, 4), 4, 142),
    ("Celli & Basses [Divisi] - Sub-Bass Pedal & Chromatic Celli", "divisi", (4, 4), 4, 128),
    ("Celli & Basses [Divisi] - 3+3+2 Split Section Engine", "divisi", (4, 4), 4, 136),
    ("Celli & Basses [Divisi] - Offbeat Celli Bark & Bass Downbeat", "divisi", (4, 4), 4, 124),
    ("Celli & Basses [Divisi] - 7/8 Interlocking Pursuit", "divisi", (7, 8), 8, 146),
    ("Celli & Basses [Divisi] - Dual-Layer Semitone Friction", "divisi", (4, 4), 4, 132),
    ("Celli & Basses [Divisi] - Contrabass Walking Doom & Spiccato", "divisi", (4, 4), 8, 130),
    ("Celli & Basses [Divisi] - 5/8 Split Low Strings Drive", "divisi", (5, 8), 8, 148),
    ("Celli & Basses [Divisi] - Syncopated Bass Slams & Celli Chatter", "divisi", (4, 4), 4, 140),
    ("Celli & Basses [Divisi] - Dark Octave Dialogue (C1 vs C3)", "divisi", (4, 4), 4, 126),
    ("Celli & Basses [Divisi] - Tritone Bass Under Celli Pedal", "divisi", (4, 4), 4, 134),
    ("Celli & Basses [Divisi] - 6/8 Galloping Split Section", "divisi", (6, 8), 8, 138),
    ("Celli & Basses [Divisi] - Martele Bass & Ricochet Celli", "divisi", (4, 4), 4, 144),
    ("Celli & Basses [Divisi] - Antiphonal Low Strings Battle", "divisi", (4, 4), 8, 136),
    ("Celli & Basses [Divisi] - 5/4 Asymmetric Section Split", "divisi", (5, 4), 4, 128),
    ("Celli & Basses [Divisi] - Creeping Bass Drone & Nervous Celli", "divisi", (4, 4), 4, 118),
    ("Celli & Basses [Divisi] - Double-Stop Celli Over Sub-Bass", "divisi", (4, 4), 4, 132),
    ("Celli & Basses [Divisi] - Relentless Locomotive Split", "divisi", (4, 4), 8, 146),
    ("Celli & Basses [Divisi] - Phrygian Bass & Staccato Celli", "divisi", (4, 4), 4, 130),
    ("Celli & Basses [Divisi] - 12/8 Triplet Interlock", "divisi", (12, 8), 4, 134),
    ("Celli & Basses [Divisi] - Tactical Ambush Two-Voice Grid", "divisi", (4, 4), 4, 140),
    ("Celli & Basses [Divisi] - Catacomb Echoes Voice Exchange", "divisi", (4, 4), 4, 114),
    ("Celli & Basses [Divisi] - Full Low-End Overdrive Finale", "divisi", (4, 4), 8, 150),

    # ==========================================================================
    # 6. TICKING CLOCK, COL LEGNO & SPARSE SUSPENSE PULSES (126-150)
    # ==========================================================================
    ("Celli Staccato - Ticking Bomb Col Legno Pulse", "sparse", (4, 4), 4, 120),
    ("Double Bass - Heartbeat in the Dark (Lub-Dub)", "sparse", (4, 4), 4, 76),
    ("Celli & Basses - Stalker Footsteps & Tense Silence", "sparse", (4, 4), 4, 88),
    ("Celli Staccato - Bartok Pizz & Staccato Bite", "sparse", (4, 4), 4, 112),
    ("Double Bass - Sniper Breath Sparse Sub-Stabs", "sparse", (4, 4), 4, 92),
    ("Celli & Basses - Sudden Jump-Scare Marcato Clusters", "sparse", (4, 4), 4, 126),
    ("Celli Staccato - Morse Code Distress Signal", "sparse", (4, 4), 4, 132),
    ("Double Bass - Creaking Ship Hull Low Knocks", "sparse", (4, 4), 4, 72),
    ("Celli & Basses - Unstable Geiger Counter Clicks", "sparse", (4, 4), 4, 118),
    ("Celli Staccato - Spiderweb Tremor Sparse 16ths", "sparse", (4, 4), 4, 128),
    ("Double Bass - Executioner's Pendulum Swing", "sparse", (3, 4), 8, 84),
    ("Celli & Basses - Cold War Wiretap Syncopation", "sparse", (4, 4), 4, 108),
    ("Celli Staccato - Fragile Ice Cracking Stabs", "sparse", (4, 4), 4, 116),
    ("Double Bass - Sub-Zero Isolation Low Pings", "sparse", (4, 4), 4, 68),
    ("Celli & Basses - 5/4 Defusing the Wire Tension", "sparse", (5, 4), 4, 114),
    ("Celli Staccato - Nervous Eyelid Twitch bursts", "sparse", (4, 4), 4, 134),
    ("Double Bass - Monster Behind the Door Thuds", "sparse", (4, 4), 4, 80),
    ("Celli & Basses - 7/8 Hesitant Infiltration Steps", "sparse", (7, 8), 8, 124),
    ("Celli Staccato - Dry Bone Col Legno Chatter", "sparse", (4, 4), 4, 130),
    ("Double Bass - Deep Sonar Ping & Echo", "sparse", (4, 4), 4, 86),
    ("Celli & Basses - Clocks of Doom Polyrhythmic Tick", "sparse", (4, 4), 8, 120),
    ("Celli Staccato - Whispers in the Asylum", "sparse", (4, 4), 4, 104),
    ("Double Bass - Grave Dirt Shovel Rhythm", "sparse", (4, 4), 4, 74),
    ("Celli & Basses - Accelerating Panic Heartbeat", "sparse", (4, 4), 4, 138),
    ("Celli & Basses - Final Breath Cutoff Stab", "sparse", (4, 4), 4, 110),
]

assert len(PATTERNS_SPEC) == 150, f"Expected 150 patterns, got {len(PATTERNS_SPEC)}"

# Low register roots: C2=36, D2=38, E2=40, F2=41, G2=43, A2=45
BASS_ROOTS = [36, 38, 40, 41, 43, 45]


def generate_low_strings_notes(idx, kind, num, denom, bars, title):
    random.seed(9000 + idx * 53)
    notes = []
    beats_per_bar = num * (4.0 / denom)
    total_qn = bars * beats_per_bar

    root = BASS_ROOTS[idx % len(BASS_ROOTS)]
    sub_root = max(28, root - 12)  # Double bass octave (E1=28 to A1=33)
    celli_oct = root + 12          # Celli upper octave (C3=48 to A3=57)

    is_double_bass_only = title.startswith("Double Bass")
    is_celli_only = title.startswith("Celli Staccato")

    if kind == "pedal":
        # Pure rhythmic motor on a single root/octave with metric accent patterns
        step = 0.25 if (idx % 3 != 2) else 0.5
        accent_groupings = [
            (0, 3, 6, 8, 11, 14),  # 3+3+2
            (0, 3, 5, 8, 11, 13),  # 3+2+3
            (0, 4, 8, 12),         # 4/4 iron downbeats
            (0, 2, 5, 8, 10, 13),  # syncopated motor
        ]
        acc_set = accent_groupings[idx % len(accent_groupings)]

        cur = 0.0
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            s_idx = int(round(m_pos / 0.25)) % 16
            is_acc = s_idx in acc_set

            if is_double_bass_only:
                notes.append({
                    "pitch": sub_root if (not is_acc or idx % 2 == 0) else root,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.2 if step == 0.25 else 0.35,
                    "vel": random.randint(108, 122) if is_acc else random.randint(76, 90),
                    "voice": 1,
                    "art": "accent" if is_acc else "staccato",
                })
            elif is_celli_only:
                notes.append({
                    "pitch": root if not is_acc else (celli_oct if idx % 3 == 0 else root),
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.2,
                    "vel": random.randint(106, 120) if is_acc else random.randint(74, 88),
                    "voice": 1,
                    "art": "accent" if is_acc else "staccato",
                })
            else:
                # Combined Celli (Voice 1) + Double Bass (Voice 2)
                notes.append({
                    "pitch": root,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.2,
                    "vel": random.randint(106, 120) if is_acc else random.randint(76, 90),
                    "voice": 1,
                    "art": "accent" if is_acc else "staccato",
                })
                if is_acc or step == 0.5:
                    notes.append({
                        "pitch": sub_root,
                        "start_qn": round(cur, 3),
                        "dur_qn": 0.35,
                        "vel": random.randint(108, 124) if is_acc else random.randint(82, 94),
                        "voice": 2,
                        "art": "accent" if is_acc else "staccato",
                    })
            cur += step

    elif kind == "semitone":
        # Claustrophobic half-step (root and root+1) tension ostinato
        step = 0.25 if (idx % 2 == 0) else 0.5
        base_p = sub_root if is_double_bass_only else root
        semi_p = base_p + 1

        cur = 0.0
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            s_idx = int(round(m_pos / step))
            use_semi = (s_idx in (1, 3, 6)) or (s_idx % 4 == 3)
            p = semi_p if use_semi else base_p
            is_acc = (s_idx % 3 == 0) or use_semi

            notes.append({
                "pitch": p,
                "start_qn": round(cur, 3),
                "dur_qn": round(step * 0.8, 3),
                "vel": random.randint(104, 118) if is_acc else random.randint(74, 88),
                "voice": 1,
                "art": "accent" if use_semi else "staccato",
            })
            if not is_double_bass_only and not is_celli_only and abs(m_pos % 1.0) < 0.01:
                notes.append({
                    "pitch": sub_root + (1 if use_semi else 0),
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.4,
                    "vel": random.randint(102, 116),
                    "voice": 2,
                    "art": "accent",
                })
            cur += step

    elif kind == "tritone":
        # Root, Semitone (+1), and Tritone (+6) dissonance engine
        step = 0.25
        base_p = sub_root if is_double_bass_only else root
        tritone_p = base_p + 6
        b2_p = base_p + 1

        cur = 0.0
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            s_idx = int(round(m_pos / 0.25))
            if s_idx in (3, 7, 11, 14):
                p = tritone_p
                art = "accent"
                vel = random.randint(110, 124)
            elif s_idx in (6, 15):
                p = b2_p
                art = "accent"
                vel = random.randint(100, 114)
            else:
                p = base_p
                art = "staccato"
                vel = random.randint(76, 90)

            notes.append({
                "pitch": p,
                "start_qn": round(cur, 3),
                "dur_qn": 0.2,
                "vel": vel,
                "voice": 1,
                "art": art,
            })
            if not is_double_bass_only and not is_celli_only and s_idx in (0, 6, 12):
                notes.append({
                    "pitch": sub_root if s_idx == 0 else sub_root + 6,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.4,
                    "vel": 114,
                    "voice": 2,
                    "art": "accent",
                })
            cur += step

    elif kind == "odd":
        # Asymmetric odd-meter pursuit engines (5/8, 7/8, 5/4, 7/4, 6/8)
        step = 0.25 if denom == 8 else 0.5
        base_p = sub_root if is_double_bass_only else root
        cur = 0.0
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            eighth_idx = int(round(m_pos / 0.5))
            # Accent asymmetric beat groupings: 0, 2, 4 or 0, 3, 5
            is_group_start = eighth_idx in (0, 3, 5) if (idx % 2 == 0) else eighth_idx in (0, 2, 4)
            is_sub_beat = abs((m_pos / 0.5) - eighth_idx) > 0.1

            p = base_p
            if is_group_start and not is_sub_beat and eighth_idx > 0:
                p = base_p + random.choice([0, 1, 6, 7])

            notes.append({
                "pitch": p,
                "start_qn": round(cur, 3),
                "dur_qn": round(step * 0.8, 3),
                "vel": random.randint(108, 122) if (is_group_start and not is_sub_beat) else random.randint(76, 92),
                "voice": 1,
                "art": "accent" if (is_group_start and not is_sub_beat) else "staccato",
            })
            if not is_double_bass_only and not is_celli_only and is_group_start and not is_sub_beat:
                notes.append({
                    "pitch": sub_root,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.4,
                    "vel": 116,
                    "voice": 2,
                    "art": "accent",
                })
            cur += step

    elif kind == "divisi":
        # Dedicated 2-Voice Divisi-Ready Low Strings:
        # Voice 2 = Double Bass (sub_root / sub_root+1 / sub_root+7 rhythmic anchors)
        # Voice 1 = Celli (root / root+1 / root+7 / celli_oct 16th-note spiccato engine)
        step = 0.25
        cur = 0.0
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            s_idx = int(round(m_pos / 0.25)) % 16

            # Voice 2: Double Bass plays on 3+3+2 or syncopated anchor beats
            if s_idx in (0, 6, 8, 12):
                b_pitch = sub_root if s_idx in (0, 8) else (sub_root + 1 if idx % 2 == 0 else sub_root + 7)
                notes.append({
                    "pitch": b_pitch,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.45,
                    "vel": random.randint(110, 124),
                    "voice": 2,
                    "art": "accent",
                })

            # Voice 1: Celli plays interlocking 16th spiccato motor (answering the bass)
            if s_idx not in (0, 8) or (idx % 3 == 0):
                c_pitch = root
                if s_idx in (3, 11, 15):
                    c_pitch = root + 1
                elif s_idx in (6, 14):
                    c_pitch = root + 7
                notes.append({
                    "pitch": c_pitch,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.2,
                    "vel": random.randint(102, 116) if s_idx in (3, 6, 11, 14) else random.randint(78, 92),
                    "voice": 1,
                    "art": "accent" if s_idx in (3, 6, 11, 14) else "staccato",
                })
            cur += step

    else:
        # Sparse ticking-clock, heartbeat & sudden stab suspense patterns
        base_p = sub_root if is_double_bass_only else root
        cur = 0.0
        step = 0.25
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            s_idx = int(round(m_pos / 0.25)) % 16
            # Lub-dub heartbeat (0, 2) + tense silence + sudden stab at 11 or 14
            if s_idx in (0, 2, 8, 10, 14):
                is_stab = s_idx == 14
                p = (base_p + 1) if is_stab else base_p
                notes.append({
                    "pitch": p,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.2,
                    "vel": 120 if is_stab else (102 if s_idx in (0, 8) else 80),
                    "voice": 1,
                    "art": "accent" if is_stab else "staccato",
                })
                if is_stab and not is_double_bass_only:
                    # Sudden dissonant double-stop / sub stab
                    notes.append({
                        "pitch": sub_root + 6,
                        "start_qn": round(cur, 3),
                        "dur_qn": 0.25,
                        "vel": 118,
                        "voice": 2,
                        "art": "accent",
                    })
            cur += step

    notes.sort(key=lambda n: (n["start_qn"], n["pitch"]))
    return notes


def main():
    print(f"Generating 150 Staccato Celli & Double Bass tension patterns into {TARGET_DIR}...")
    for idx, (title, kind, (num, denom), bars, tempo) in enumerate(PATTERNS_SPEC, 1):
        slug = (
            title.lower()
            .replace(" & ", "_")
            .replace(" - ", "_")
            .replace("[divisi]", "divisi")
            .replace("/", "_")
            .replace("'", "")
            .replace("(", "")
            .replace(")", "")
            .replace("#", "s")
            .replace("+", "_")
            .replace(" ", "_")
        )
        while "__" in slug:
            slug = slug.replace("__", "_")
        pat_id = f"low_str_{idx:03d}_{slug}"[:62].rstrip("_")

        notes = generate_low_strings_notes(idx, kind, num, denom, bars, title)

        data = {
            "id": pat_id,
            "name": title,
            "category": "10_Low_Strings_Celli_Basses",
            "bars": bars,
            "time_sig": {"num": num, "denom": denom},
            "tempo_hint": tempo,
            "clef": "bass",
            "notes": notes,
        }

        out_path = os.path.join(TARGET_DIR, f"{pat_id}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)

    print("Done! Successfully generated 150 Low Strings (Celli & Double Bass) patterns.")


if __name__ == "__main__":
    main()

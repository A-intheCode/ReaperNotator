#!/usr/bin/env python3
"""
REAPER-Notator - Orchestral & Cinematic Percussion Pattern Generator
Generates 150 authentic, idiomatic orchestral, cinematic, and world percussion patterns
into patterns/09_Orchestral_Percussion.
Each pattern is explicitly named after the instrument and musical context
(Timpani, Taiko, Gran Cassa & Piatti, Snare Drum, Cinematic Toms, Anvil & Metal,
Frame Drum / Darbuka, Xylophone / Marimba / Tubular Bells).
"""

import os
import json
import random

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_DIR = os.path.join(REPO_ROOT, "patterns", "09_Orchestral_Percussion")
os.makedirs(TARGET_DIR, exist_ok=True)

# 150 Percussion Patterns grouped by Instrument & Musical Context
PATTERNS_SPEC = [
    # ==========================================================================
    # 1. TIMPANI (1-25) - Pitched Orchestral Kettle Drums (C2=36 to A3=57)
    # ==========================================================================
    ("Timpani - Imperial March Dominant-Tonic (C-G)", "timpani", (4, 4), 4, 112),
    ("Timpani - Beethovenian Scherzo Octave Drive", "timpani", (3, 4), 8, 138),
    ("Timpani - Rolling Thunder Climax Build", "timpani", (4, 4), 4, 120),
    ("Timpani - Gladiatorial Arena Fourths (D-A)", "timpani", (4, 4), 4, 126),
    ("Timpani - Dark Tritone Doom Ostinato (C-F#)", "timpani", (4, 4), 4, 104),
    ("Timpani - Heroic Overture Fanfare Punctuation", "timpani", (4, 4), 8, 118),
    ("Timpani - Relentless 5/8 Battle Gallop", "timpani", (5, 8), 8, 148),
    ("Timpani - 7/8 Asymmetric War Council", "timpani", (7, 8), 8, 140),
    ("Timpani - 6/8 Cavalry Charge Kettle Drums", "timpani", (6, 8), 8, 132),
    ("Timpani - Funeral Procession Muffled Strikes", "timpani", (4, 4), 4, 68),
    ("Timpani - Mahlerian Fate Double Hammer Blow", "timpani", (4, 4), 4, 84),
    ("Timpani - Syncopated 3+3+2 Action Pedals", "timpani", (4, 4), 4, 134),
    ("Timpani - Ascending Chromatic Tension Kettles", "timpani", (4, 4), 4, 124),
    ("Timpani - Sovereign Coronation Cadence", "timpani", (4, 4), 8, 96),
    ("Timpani - Storm At Sea Triplet Fury", "timpani", (12, 8), 4, 128),
    ("Timpani - Underworld Awakening Low C-Db", "timpani", (4, 4), 4, 92),
    ("Timpani - Valkyrie Ride Dotted Rhythm", "timpani", (6, 8), 8, 136),
    ("Timpani - Siege Catapult Heavy Downbeats", "timpani", (4, 4), 4, 100),
    ("Timpani - Classical Symphony Finale Coda", "timpani", (4, 4), 8, 144),
    ("Timpani - Dual Kettle Alternating 16th Drive", "timpani", (4, 4), 4, 130),
    ("Timpani - Roman Legionnaires Heavy Step", "timpani", (4, 4), 4, 108),
    ("Timpani - Apocalyptic Dies Irae Fifths", "timpani", (4, 4), 8, 122),
    ("Timpani - Suspense Heartbeat Low D2 Pulse", "timpani", (4, 4), 4, 78),
    ("Timpani - 5/4 Titan Stride Ostinato", "timpani", (5, 4), 4, 116),
    ("Timpani - Grand Tutti Finale Roll & Accents", "timpani", (4, 4), 8, 132),

    # ==========================================================================
    # 2. TAIKO ENSEMBLE (26-50) - O-Daiko (Low), Chu-Daiko (Mid), Shime/Rim (High)
    # ==========================================================================
    ("Taiko - Samurai Warlord Charge (O-Daiko & Chu-Daiko)", "taiko", (4, 4), 4, 128),
    ("Taiko - Shogunate Fortress Gate Impacts", "taiko", (4, 4), 4, 96),
    ("Taiko - Matsuri Festival Syncopated Groove", "taiko", (4, 4), 8, 134),
    ("Taiko - Bushido Honor 3+3+2 Drive", "taiko", (4, 4), 4, 140),
    ("Taiko - O-Daiko Earthshaker & Rim Clicks", "taiko", (4, 4), 4, 110),
    ("Taiko - Ronin Duel 7/8 Blade Tension", "taiko", (7, 8), 8, 146),
    ("Taiko - Kodo Spirit Accelerating Triplets", "taiko", (6, 8), 8, 138),
    ("Taiko - Shinobi Rooftop Pursuit 5/8", "taiko", (5, 8), 8, 152),
    ("Taiko - Shime-Daiko Rapid 16th Stutter & Boom", "taiko", (4, 4), 4, 132),
    ("Taiko - Imperial Kyoto Procession", "taiko", (4, 4), 4, 88),
    ("Taiko - Dragon Boat Rowing Cadence", "taiko", (4, 4), 8, 120),
    ("Taiko - Sekigahara Battlefield Thunder", "taiko", (4, 4), 4, 136),
    ("Taiko - Bamboo Forest Ambush Rim & Sub", "taiko", (4, 4), 4, 124),
    ("Taiko - Volcanic Eruption Low Ensemble", "taiko", (4, 4), 4, 116),
    ("Taiko - Oni Demon Mask Ritual 5/4", "taiko", (5, 4), 4, 126),
    ("Taiko - Raijin God of Lightning Strikes", "taiko", (4, 4), 8, 144),
    ("Taiko - Temple Courtyard Dawn Call-and-Response", "taiko", (4, 4), 8, 104),
    ("Taiko - Katana Unsheathed Sparse Tension", "taiko", (4, 4), 4, 92),
    ("Taiko - Cavalry of Takeda 6/8 Gallop", "taiko", (6, 8), 8, 142),
    ("Taiko - Siege of Osaka Castle Heavy Hits", "taiko", (4, 4), 4, 100),
    ("Taiko - Monsoon Rain Rim-to-Center Crescendo", "taiko", (4, 4), 4, 128),
    ("Taiko - Sumo Dohyo Ring Entrance Stomp", "taiko", (4, 4), 4, 80),
    ("Taiko - Cyber-Tokyo Hybrid Taiko Motor", "taiko", (4, 4), 4, 138),
    ("Taiko - Ancestral Shrine Ceremonial 3/4", "taiko", (3, 4), 8, 108),
    ("Taiko - Final Boss Phase 2 Relentless Ensemble", "taiko", (4, 4), 8, 150),

    # ==========================================================================
    # 3. GRAN CASSA & PIATTI (51-70) - Concert Bass Drum & Orchestral Cymbals
    # ==========================================================================
    ("Gran Cassa & Piatti - Colossal Trailer Downbeats", "grancassa", (4, 4), 4, 90),
    ("Gran Cassa & Piatti - Verdi Requiem Dies Irae Slams", "grancassa", (4, 4), 4, 136),
    ("Gran Cassa & Piatti - Funeral March Solemn Boom", "grancassa", (4, 4), 4, 64),
    ("Gran Cassa & Piatti - Heroic Symphony Climax Crashes", "grancassa", (4, 4), 8, 120),
    ("Gran Cassa & Piatti - Leviathan Deep Sea Impacts", "grancassa", (4, 4), 4, 76),
    ("Gran Cassa & Piatti - Syncopated Blockbuster Booms", "grancassa", (4, 4), 4, 128),
    ("Gran Cassa & Piatti - Russian Romantic Overture Tutti", "grancassa", (4, 4), 8, 132),
    ("Gran Cassa & Piatti - Slow Executioner's Step", "grancassa", (4, 4), 4, 60),
    ("Gran Cassa & Piatti - 3/4 Imperial Waltz Accents", "grancassa", (3, 4), 8, 138),
    ("Gran Cassa & Piatti - 6/8 Pirate Galleon Broadside", "grancassa", (6, 8), 8, 126),
    ("Gran Cassa & Piatti - Offbeat Shockwave Hits", "grancassa", (4, 4), 4, 114),
    ("Gran Cassa & Piatti - Titan Footsteps & Sizzle Swell", "grancassa", (4, 4), 4, 84),
    ("Gran Cassa & Piatti - 5/4 War Machine March", "grancassa", (5, 4), 4, 108),
    ("Gran Cassa & Piatti - Double-Hit Heartbeat Sub Bass", "grancassa", (4, 4), 4, 72),
    ("Gran Cassa & Piatti - Orchestral Finale Bravura", "grancassa", (4, 4), 8, 144),
    ("Gran Cassa & Piatti - Gothic Cathedral Doom Tolls", "grancassa", (4, 4), 4, 80),
    ("Gran Cassa & Piatti - 7/8 Monster Awakening", "grancassa", (7, 8), 8, 130),
    ("Gran Cassa & Piatti - Napoleon Cannonade Strikes", "grancassa", (4, 4), 4, 116),
    ("Gran Cassa & Piatti - Suspended Cymbal Roll to Slam", "grancassa", (4, 4), 4, 100),
    ("Gran Cassa & Piatti - Apocalyptic Curtain Fall", "grancassa", (4, 4), 8, 110),

    # ==========================================================================
    # 4. SNARE DRUM / TAMBURO MILITARE (71-90) - Military & Orchestral Snare
    # ==========================================================================
    ("Snare Drum - Ravel Bolero Hypnotic Ostinato", "snare", (3, 4), 8, 72),
    ("Snare Drum - Waterloo Line Infantry Cadence", "snare", (4, 4), 4, 112),
    ("Snare Drum - Shostakovich Leningrad Invasion March", "snare", (4, 4), 8, 126),
    ("Snare Drum - 6/8 Light Brigade Cavalry Charge", "snare", (6, 8), 8, 140),
    ("Snare Drum - Tactical Spec-Ops 5/8 Infiltration", "snare", (5, 8), 8, 144),
    ("Snare Drum - Crisp Rimshot Thriller Pulse", "snare", (4, 4), 4, 120),
    ("Snare Drum - Presidential Honor Guard Procession", "snare", (4, 4), 4, 96),
    ("Snare Drum - 7/8 Espionage Ghost Notes & Accents", "snare", (7, 8), 8, 136),
    ("Snare Drum - Civil War Fife & Drum Corps", "snare", (4, 4), 8, 118),
    ("Snare Drum - Execution Scaffold Muffled Roll", "snare", (4, 4), 4, 68),
    ("Snare Drum - High-Tension 16th Drag & Flam Drive", "snare", (4, 4), 4, 132),
    ("Snare Drum - Paratrooper Drop Zone 3+3+2", "snare", (4, 4), 4, 138),
    ("Snare Drum - Roman Triumphal Field Drum", "snare", (4, 4), 4, 108),
    ("Snare Drum - Submarine Depth Charge Tension", "snare", (4, 4), 4, 100),
    ("Snare Drum - Prokofiev Sarcastic March", "snare", (4, 4), 4, 128),
    ("Snare Drum - 12/8 Triplet War Drum Roll", "snare", (12, 8), 4, 124),
    ("Snare Drum - Siege Trench Whistle & Charge", "snare", (4, 4), 8, 142),
    ("Snare Drum - Syncopated Cross-Stick Espionage", "snare", (4, 4), 4, 114),
    ("Snare Drum - 5/4 Mechanized Infantry", "snare", (5, 4), 4, 122),
    ("Snare Drum - Grand Military Tattoo Finale", "snare", (4, 4), 8, 134),

    # ==========================================================================
    # 5. CINEMATIC TOMS & TRIBAL DRUMS (91-110) - Floor Toms, Rototoms, Djembe
    # ==========================================================================
    ("Cinematic Toms - Jungle Predator 16th Chase", "toms", (4, 4), 4, 138),
    ("Cinematic Toms - Descending Floor Tom Avalanche", "toms", (4, 4), 4, 128),
    ("Cinematic Toms - Savanna Stampede 6/8 Tribal", "toms", (6, 8), 8, 136),
    ("Cinematic Toms - Bourne-Style Thriller Motor", "toms", (4, 4), 4, 132),
    ("Cinematic Toms - Gladiator Tunnel Walk Low Toms", "toms", (4, 4), 4, 104),
    ("Cinematic Toms - 7/8 Rooftop Parkour Run", "toms", (7, 8), 8, 148),
    ("Cinematic Toms - Rototom Octave Tension Roll", "toms", (4, 4), 4, 124),
    ("Cinematic Toms - Aztec Sun Temple Sacrifice", "toms", (4, 4), 8, 118),
    ("Cinematic Toms - 5/8 Primal Hunt Ostinato", "toms", (5, 8), 8, 144),
    ("Cinematic Toms - Deep Surdo & Floor Tom Groove", "toms", (4, 4), 4, 120),
    ("Cinematic Toms - Heist Countdown Syncopated Toms", "toms", (4, 4), 4, 126),
    ("Cinematic Toms - Berserker Viking Raid Drums", "toms", (4, 4), 8, 112),
    ("Cinematic Toms - 3+3+2 Adrenaline Rush", "toms", (4, 4), 4, 142),
    ("Cinematic Toms - Subterranean Cavern Echoes", "toms", (4, 4), 4, 92),
    ("Cinematic Toms - Cybernetic Pursuit 16th Grid", "toms", (4, 4), 4, 140),
    ("Cinematic Toms - Tribal War Paint Call & Answer", "toms", (4, 4), 8, 122),
    ("Cinematic Toms - 5/4 Desert Nomad Caravan", "toms", (5, 4), 4, 114),
    ("Cinematic Toms - Canyon Ambush Rim & Low Tom", "toms", (4, 4), 4, 130),
    ("Cinematic Toms - Triplet Storm Over the Steppes", "toms", (12, 8), 4, 134),
    ("Cinematic Toms - Apex Predator Final Sprint", "toms", (4, 4), 8, 152),

    # ==========================================================================
    # 6. ANVIL, FORGE & METAL PERCUSSION (111-125) - Anvil, Brake Drum, Tam-Tam
    # ==========================================================================
    ("Anvil & Metal - Nibelung Dwarven Forge Hammers", "metal", (4, 4), 4, 116),
    ("Anvil & Metal - Isengard Industrial Foundry 5/4", "metal", (5, 4), 4, 108),
    ("Anvil & Metal - Verdi Il Trovatore Gypsy Anvil", "metal", (4, 4), 4, 124),
    ("Anvil & Metal - Clockwork Automaton Ticking Gear", "metal", (4, 4), 4, 120),
    ("Anvil & Metal - Tam-Tam & Gong Ominous Prophecy", "metal", (4, 4), 4, 72),
    ("Anvil & Metal - Hephaestus Volcano Blacksmith", "metal", (3, 4), 8, 132),
    ("Anvil & Metal - Steampunk Locomotive Pistons", "metal", (4, 4), 4, 128),
    ("Anvil & Metal - Brake Drum & Iron Pipe 7/8", "metal", (7, 8), 8, 138),
    ("Anvil & Metal - Prison Cell Iron Bars Clanging", "metal", (4, 4), 4, 88),
    ("Anvil & Metal - Cyber-Factory Assembly Line", "metal", (4, 4), 4, 134),
    ("Anvil & Metal - Sword Tempering Sparks & Strikes", "metal", (6, 8), 8, 126),
    ("Anvil & Metal - Titanic Engine Room Overdrive", "metal", (4, 4), 8, 140),
    ("Anvil & Metal - Bell Plate & Anvil Syncopation", "metal", (4, 4), 4, 112),
    ("Anvil & Metal - Horror Asylum Metallic Scrape", "metal", (4, 4), 4, 80),
    ("Anvil & Metal - Colossus of Rhodes Bronze Step", "metal", (4, 4), 4, 96),

    # ==========================================================================
    # 7. FRAME DRUM, BODHRAN & DARBUKA (126-140) - World & Ancient Hand Drums
    # ==========================================================================
    ("Frame Drum - Ancient Mediterranean Tarantella 6/8", "framedrum", (6, 8), 8, 138),
    ("Frame Drum - Priestess of Isis Ritual Pulse", "framedrum", (4, 4), 4, 96),
    ("Darbuka - Cairo Night Maqsum Groove", "framedrum", (4, 4), 4, 118),
    ("Darbuka - Desert Mirage Malfuf 2+3+3 Drive", "framedrum", (4, 4), 4, 128),
    ("Bodhran - Celtic Highland Battle Jig 6/8", "framedrum", (6, 8), 8, 134),
    ("Bodhran - Irish Reel Tipping Double-Time", "framedrum", (4, 4), 8, 142),
    ("Frame Drum - Babylonian Procession 7/8", "framedrum", (7, 8), 8, 124),
    ("Darbuka - Silk Road Caravan 10/8 Sama'i", "framedrum", (5, 4), 4, 112),
    ("Frame Drum - Dionysian Bacchanal Bendir", "framedrum", (4, 4), 4, 132),
    ("Darbuka - Ottoman Janissary Mehter Rhythm", "framedrum", (4, 4), 4, 104),
    ("Frame Drum - Nordic Shamanic Skin Drum", "framedrum", (4, 4), 4, 84),
    ("Darbuka - Alhambra Courtyard Finger Rolls", "framedrum", (3, 4), 8, 126),
    ("Bodhran - Emerald Coast Storm 12/8", "framedrum", (12, 8), 4, 130),
    ("Frame Drum - Mycenaean Chariot Dust 5/8", "framedrum", (5, 8), 8, 144),
    ("Darbuka - Oasis Dervish Whirling Finale", "framedrum", (4, 4), 8, 148),

    # ==========================================================================
    # 8. ORCHESTRAL MALLETS & BELLS (141-150) - Xylophone, Marimba, Tubular Bells
    # ==========================================================================
    ("Xylophone - Danse Macabre Skeletal Clatter", "mallets", (3, 4), 8, 138),
    ("Xylophone - Fossil Carnival Staccato Run", "mallets", (4, 4), 4, 144),
    ("Marimba - Minimalist Glassian Tension Motor", "mallets", (4, 4), 8, 126),
    ("Marimba - Dark Wood Thriller 7/8 Pulse", "mallets", (7, 8), 8, 136),
    ("Tubular Bells - Westminster Cathedral Midnight Tolls", "bells", (4, 4), 4, 72),
    ("Tubular Bells - Boris Godunov Coronation Chimes", "bells", (4, 4), 4, 84),
    ("Glockenspiel - Enchanted Ice Palace Sparkle", "mallets", (3, 4), 8, 116),
    ("Xylophone - Arachnid Creeping Chromatic 5/8", "mallets", (5, 8), 8, 148),
    ("Marimba - Subterranean Labyrinth Ostinato", "mallets", (4, 4), 4, 132),
    ("Tubular Bells - Doomsday Judgment Day Strike", "bells", (4, 4), 4, 66),
]

assert len(PATTERNS_SPEC) == 150, f"Expected 150 patterns, got {len(PATTERNS_SPEC)}"


def generate_percussion_notes(idx, kind, num, denom, bars):
    random.seed(5000 + idx * 41)
    notes = []
    beats_per_bar = num * (4.0 / denom)
    total_qn = bars * beats_per_bar

    if kind == "timpani":
        # Pitched Kettle Drums: Root & Fifth/Fourth/Tritone in C2-A3 range (MIDI 36-57)
        roots = [36, 38, 40, 41, 43, 45]  # C2, D2, E2, F2, G2, A2
        root = roots[idx % len(roots)]
        fifth = root + 7 if (idx % 5 != 4) else root + 6  # occasional tritone
        fourth = root + 5
        octave = root + 12

        step = 0.5 if denom == 8 else 0.5
        cur = 0.0
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            bar_num = int(cur // beats_per_bar)
            is_downbeat = abs(m_pos) < 0.01
            is_midbeat = abs(m_pos - beats_per_bar / 2.0) < 0.01

            if is_downbeat:
                # Strong downbeat on tonic or octave
                p = root if (bar_num % 2 == 0) else fifth
                notes.append({
                    "pitch": p,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.45,
                    "vel": random.randint(108, 122),
                    "voice": 1,
                    "art": "accent"
                })
                # Optional 16th pickup or double-stroke on energetic patterns
                if idx % 3 == 0 and cur + 0.25 < total_qn:
                    notes.append({
                        "pitch": root,
                        "start_qn": round(cur + 0.25, 3),
                        "dur_qn": 0.2,
                        "vel": random.randint(80, 92),
                        "voice": 1,
                        "art": "staccato"
                    })
            elif is_midbeat:
                p = fifth if (bar_num % 2 == 0) else fourth
                notes.append({
                    "pitch": p,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.4,
                    "vel": random.randint(96, 110),
                    "voice": 1,
                    "art": "accent"
                })
            else:
                # Rhythmic kettle drive or roll at end of bar
                if m_pos >= beats_per_bar - 1.0 and (bar_num % 2 == 1):
                    # Timpani roll (16th-note tremolando simulation)
                    for sub in [0.0, 0.25]:
                        if cur + sub < total_qn - 0.01:
                            notes.append({
                                "pitch": fifth,
                                "start_qn": round(cur + sub, 3),
                                "dur_qn": 0.2,
                                "vel": min(124, 82 + int(m_pos * 10)),
                                "voice": 1,
                                "art": "staccato"
                            })
                elif random.random() < 0.65:
                    p = random.choice([root, root, fifth, octave])
                    notes.append({
                        "pitch": p,
                        "start_qn": round(cur, 3),
                        "dur_qn": 0.35,
                        "vel": random.randint(78, 96),
                        "voice": 1,
                        "art": "staccato"
                    })
            cur += step

    elif kind == "taiko":
        # Voice 2: O-Daiko (deep boom: C2=36, D2=38)
        # Voice 1: Chu-Daiko (mid: G2=43, A2=45) & Shime/Rim (high: C3=48, D3=50, E3=52)
        cur = 0.0
        step = 0.25 if (idx % 2 == 0) else 0.5
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            step_in_bar = int(round(m_pos / 0.25))
            # 3+3+2 or downbeat O-Daiko hits in Voice 2
            if step_in_bar in (0, 6, 12):
                notes.append({
                    "pitch": 36 if step_in_bar == 0 else 38,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.45,
                    "vel": random.randint(110, 125),
                    "voice": 2,
                    "art": "accent"
                })
            # Chu-Daiko & Rim interplay in Voice 1
            if step_in_bar in (0, 3, 6, 8, 10, 12, 14):
                is_rim = step_in_bar in (3, 10, 14)
                notes.append({
                    "pitch": (50 if is_rim else 43),
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.2,
                    "vel": random.randint(84, 100) if is_rim else random.randint(98, 114),
                    "voice": 1,
                    "art": "staccato" if is_rim else "accent"
                })
            elif step == 0.25 and random.random() < 0.45:
                notes.append({
                    "pitch": 52,  # Kakegoe / Rim click
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.18,
                    "vel": random.randint(72, 88),
                    "voice": 1,
                    "art": "staccato"
                })
            cur += step

    elif kind == "grancassa":
        # Voice 2: Gran Cassa (C2=36, D2=38), Voice 1: Piatti Cymbals (C3=48, E3=52)
        cur = 0.0
        step = 0.5
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            bar_num = int(cur // beats_per_bar)
            if abs(m_pos) < 0.01:
                # Massive downbeat on Gran Cassa + Piatti crash on even bars
                notes.append({
                    "pitch": 36,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.9,
                    "vel": random.randint(114, 126),
                    "voice": 2,
                    "art": "accent"
                })
                if bar_num % 2 == 0 or idx % 3 == 0:
                    notes.append({
                        "pitch": 48,
                        "start_qn": round(cur, 3),
                        "dur_qn": 1.5,
                        "vel": random.randint(106, 122),
                        "voice": 1,
                        "art": "accent"
                    })
            elif abs(m_pos - beats_per_bar * 0.5) < 0.01 or abs(m_pos - (beats_per_bar - 0.5)) < 0.01:
                if random.random() < 0.75:
                    notes.append({
                        "pitch": 38,
                        "start_qn": round(cur, 3),
                        "dur_qn": 0.45,
                        "vel": random.randint(90, 108),
                        "voice": 2,
                        "art": "staccato"
                    })
            cur += step

    elif kind == "snare":
        # Snare center (D2=38), Rimshot (E2=40), Flam/Drag (F2=41)
        cur = 0.0
        step = 0.25
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            sixteenth = int(round(m_pos / 0.25))
            if sixteenth in (0, 4, 8, 12):
                notes.append({
                    "pitch": 40 if sixteenth in (0, 8) else 38,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.2,
                    "vel": random.randint(102, 118),
                    "voice": 1,
                    "art": "accent"
                })
            elif sixteenth in (2, 3, 6, 10, 11, 14, 15) or random.random() < 0.5:
                notes.append({
                    "pitch": 38,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.18,
                    "vel": random.randint(70, 88),
                    "voice": 1,
                    "art": "staccato"
                })
            cur += step

    elif kind == "toms":
        # Floor Toms (F2=41, G2=43, A2=45) + Mid/Rototoms (B2=47, C3=48, D3=50)
        tom_pitches = [41, 43, 45, 47, 48, 50]
        cur = 0.0
        step = 0.25
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            s_idx = int(round(m_pos / 0.25))
            is_accent = s_idx in (0, 3, 6, 8, 11, 14)
            if is_accent or random.random() < 0.65:
                # Descending tom cascade towards end of measure
                if m_pos >= beats_per_bar - 1.0:
                    p = tom_pitches[max(0, 5 - (s_idx % 6))]
                else:
                    p = tom_pitches[(s_idx + idx) % 4]
                notes.append({
                    "pitch": p,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.2,
                    "vel": random.randint(104, 120) if is_accent else random.randint(76, 92),
                    "voice": 2 if p <= 43 else 1,
                    "art": "accent" if is_accent else "staccato"
                })
            cur += step

    elif kind == "metal":
        # Voice 2: Tam-Tam / Forge Sub (C2=36), Voice 1: Anvil High/Mid (G3=55, A3=57, C4=60)
        cur = 0.0
        step = 0.5
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            if abs(m_pos) < 0.01:
                notes.append({
                    "pitch": 36,
                    "start_qn": round(cur, 3),
                    "dur_qn": 1.0,
                    "vel": 112,
                    "voice": 2,
                    "art": "accent"
                })
            anvil_p = random.choice([55, 57, 60])
            is_strong = (int(round(m_pos * 2)) % 2 == 0)
            notes.append({
                "pitch": anvil_p,
                "start_qn": round(cur, 3),
                "dur_qn": 0.25,
                "vel": random.randint(104, 120) if is_strong else random.randint(80, 94),
                "voice": 1,
                "art": "accent" if is_strong else "staccato"
            })
            cur += step

    elif kind == "framedrum":
        # Voice 2: Düm (Low center: D2=38, F2=41), Voice 1: Tek / Ka (High rim: A2=45, C3=48, D3=50)
        cur = 0.0
        step = 0.25
        while cur < total_qn - 0.01:
            m_pos = cur % beats_per_bar
            s_idx = int(round(m_pos / 0.25))
            # Classic Maqsum / Malfuf / 6/8 Düm-Tek-Tek-Düm-Tek skeleton
            if s_idx in (0, 6, 8):
                notes.append({
                    "pitch": 38 if s_idx == 0 else 41,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.35,
                    "vel": random.randint(102, 116),
                    "voice": 2,
                    "art": "accent"
                })
            elif s_idx in (2, 3, 4, 10, 12, 14, 15):
                notes.append({
                    "pitch": 48 if s_idx % 2 == 0 else 50,
                    "start_qn": round(cur, 3),
                    "dur_qn": 0.2,
                    "vel": random.randint(78, 98),
                    "voice": 1,
                    "art": "staccato"
                })
            cur += step

    else:
        # Mallets (Xylophone/Marimba/Glockenspiel) & Tubular Bells
        scale = [60, 62, 63, 65, 67, 68, 71, 72, 74, 75, 79]
        step = 1.0 if kind == "bells" else 0.25
        cur = 0.0
        while cur < total_qn - 0.01:
            deg = (int(round(cur / step)) * 2 + idx) % len(scale)
            p = scale[deg]
            notes.append({
                "pitch": p,
                "start_qn": round(cur, 3),
                "dur_qn": 0.9 if kind == "bells" else 0.2,
                "vel": random.randint(96, 116) if (cur % 1.0 == 0) else random.randint(76, 92),
                "voice": 1,
                "art": "tenuto" if kind == "bells" else "staccato"
            })
            cur += step

    notes.sort(key=lambda n: (n["start_qn"], n["pitch"]))
    return notes


def main():
    print(f"Generating 150 Orchestral & Cinematic Percussion patterns into {TARGET_DIR}...")
    for idx, (title, kind, (num, denom), bars, tempo) in enumerate(PATTERNS_SPEC, 1):
        slug = (
            title.lower()
            .replace(" & ", "_")
            .replace(" - ", "_")
            .replace("/", "_")
            .replace("'", "")
            .replace("(", "")
            .replace(")", "")
            .replace("#", "s")
            .replace(" ", "_")
        )
        while "__" in slug:
            slug = slug.replace("__", "_")
        pat_id = f"perc_{idx:03d}_{slug}"[:62].rstrip("_")

        notes = generate_percussion_notes(idx, kind, num, denom, bars)
        clef = "treble" if kind in ("mallets", "bells") else "bass"

        data = {
            "id": pat_id,
            "name": title,
            "category": "09_Orchestral_Percussion",
            "bars": bars,
            "time_sig": {"num": num, "denom": denom},
            "tempo_hint": tempo,
            "clef": clef,
            "notes": notes,
        }

        out_path = os.path.join(TARGET_DIR, f"{pat_id}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)

    print("Done! Successfully generated 150 Percussion patterns.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
REAPER-Notator - Ancient Greek & Roman Harp Pattern Generator
Generates 150 authentic, modal, melodic ancient Greek & Roman harp patterns.
Idiomatic for 2-handed orchestral harp, ancient Greek Lyra/Kithara/Phorminx
and Roman Cithara/Tibicen traditions.
"""

import os
import json
import random

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TARGET_DIR = os.path.join(REPO_ROOT, "patterns", "08_Ancient_Harp_Greek_Roman")
os.makedirs(TARGET_DIR, exist_ok=True)

# 150 Authentic Titles reflecting Greek & Roman antiquity, poetry, mythology and relics
TITLES = [
    # Delphic & Apollo Hymns (1-15)
    "Delphic Hymn to Apollo - First Paean",
    "Delphic Hymn to Apollo - Prosodion",
    "Second Delphic Hymn - Glyconic Verse",
    "Second Delphic Hymn - Epode of Pytho",
    "Hymn to Apollo Pythios - Radiant Dawn",
    "Oracle of Delphi - Golden Tripod",
    "Castalian Spring - Sacred Waters",
    "Mount Parnassus - Laurel Crown",
    "Phoebus Apollo - The Golden Bow",
    "Pythian Games - Chariot Procession",
    "Apollo Musagetes - Leader of the Muses",
    "Hymn to the Sun - Helios Rising",
    "Hymn to the Muses - Calliope's Voice",
    "Hymn to Nemesis - Winged Inevitability",
    "Epitaph of Seikilos - Eternal Song",
    
    # Sappho & Aeolian Lyric Tradition (16-30)
    "Sapphic Ode - To Aphrodite of the Flowers",
    "Lesbian Lyre - Midnight Moon",
    "Sappho's Fragment 31 - Trembling Heart",
    "Aeolian Breeze - Mytilene Shore",
    "Alcaeus Ode - Golden Armor",
    "Anacreontic Strophe - Wine and Roses",
    "Archilochus - The Eclipse of Paros",
    "Simonides - Epitaph for the 300 Spartans",
    "Stesichorus - Palinode to Helen",
    "Pindaric Epinikion - Olympian Victor",
    "Pindaric Strophe - Water is Best",
    "Bacchylides - The Jovial Banquet",
    "Theocritus - Sicilian Pastoral Idyl",
    "Pastoral Syrinx - Whispering Pines",
    "Idyll of Daphnis - The Herdman's Harp",

    # Ancient Greek Modal Processions & Relics (31-50)
    "Dorian Kithara - Solemn Spartan Procession",
    "Dorian Harmonia - The Bronze Phalanx",
    "Dorian Grave - Funeral of Patroclus",
    "Dorian Epode - Temple of Hera at Olympia",
    "Phrygian Ecstasy - Mysteries of Cybele",
    "Phrygian Flute & Lyre - Mount Ida",
    "Phrygian Rhapsody - Dionysus Enthroned",
    "Lydian Elegiac - Lament of Andromache",
    "Lydian Lamentation - Tears of Niobe",
    "Lydian Serenade - Palace of Croesus",
    "Mixolydian Tragedy - Chorus of Antigone",
    "Mixolydian Elegy - Euripides Orestes Stasimon",
    "Mixolydian Lament - Trojan Women",
    "Hypodorian Lyric - Evening Star Hesperus",
    "Hypophrygian Dance - Bacchanalian Steps",
    "Hypolydian Whispers - Garden of the Hesperides",
    "Orphic Hymn - Journey to the Underworld",
    "Orpheus and Eurydice - The Backward Glance",
    "Eleusinian Mysteries - The Golden Sheaf",
    "Eleusinian Secret - Return of Persephone",

    # Athenian Glory & Philosophy (51-65)
    "Athenian Dawn - Acropolis Light",
    "Parthenon Panathenaic - Peplos Procession",
    "Theater of Dionysus - Tragic Prologue",
    "Platonic Harmonia - The Music of the Spheres",
    "Pythagorean Monochord - The Divine Ratio",
    "Aristoxenus Tetrachord - Enharmonic Cascade",
    "Socrates' Farewell - The Phaedo Canticle",
    "Aristotelian Poetics - Catharsis Theme",
    "Stoic Solitude - The Stoa Poikile",
    "Epicurean Garden - Tranquil Mind",
    "Cynic's Lantern - Diogenes in Corinth",
    "Alexandrian Scrolls - Museion of Alexandria",
    "Rhodes Colossus - Harbor Beacon",
    "Labyrinth of Knossos - Thread of Ariadne",
    "Minoan Fresco - Blue Ladies with Lyre",

    # Roman Republic & Imperial Splendor (66-85)
    "Roman Forum - Morning Senatorial Walk",
    "Capitoline Temple - Jupiter Optimus Maximus",
    "Vestal Virgin Hymn - The Sacred Fire",
    "Vestal Chant - Eternal Hearth of Vesta",
    "Roman Triumphal March - Via Sacra Procession",
    "Triumphal Laurels - Arch of Augustus",
    "Imperial Palatine - Palace of the Caesars",
    "Apollo Palatinus - Temple of White Marble",
    "Ara Pacis Augustae - Altar of Peace",
    "Campus Martius - Twilight Parade",
    "Pantheon Oculum - Shaft of Sunlight",
    "Hadrian's Villa - Reflections in the Canopus",
    "Trajan's Column - Dacic Victory Hymn",
    "Baths of Caracalla - Echoing Mosaics",
    "Circus Maximus - Four Chariot Teams",
    "Colosseum Canticle - Roman Arena Dawn",
    "Arch of Constantine - Imperial Monogram",
    "Subura Nightfall - Torches and Taverns",
    "Appian Way - Tombs in the Cypress Mist",
    "Via Flaminia - Northward Legion",

    # Roman Poets & Philosophy (86-105)
    "Virgilian Georgics - Song of the Bees",
    "Aeneid Book I - Arms and the Man",
    "Aeneid Book VI - Golden Bough in Avernus",
    "Horatian Ode - Carpe Diem Quintessence",
    "Horace in Sabine Hills - Fons Bandusiae",
    "Ovidian Metamorphoses - Daphne into Laurel",
    "Ovid's Fasti - The Roman Calendar",
    "Tibullus Elegies - Delia's Garland",
    "Propertius Elegy - Cynthia's Ghost",
    "Catullus Ode 5 - Let Us Live and Love",
    "Catullus Ode 101 - Hail and Farewell",
    "Lucretius - Nature of Things Invocation",
    "Senecan Tragedy - Phaedra's Agony",
    "Marcus Aurelius - Meditations by the Danube",
    "Ciceronian Orator - De Re Publica Cadence",
    "Pliny at Lake Como - Villa of Tranquility",
    "Pompeian Villa of the Mysteries - Fresco Dance",
    "Herculaneum Villa of the Papyri - Philosopher's Lyre",
    "Campanian Vineyard - Falernian Wine Song",
    "Bay of Naples - Capri Emperor's Grotto",

    # Mythological & Epic Legends (106-125)
    "Homeric Iliad - The Wrath of Achilles",
    "Odyssey - The Song of the Sirens",
    "Odyssey - Penelope's Loom and Harp",
    "Odyssey - Nausicaa on Phaeacian Shore",
    "Odyssey - Ithaca Hearth at Twilight",
    "Jason and the Argonauts - Golden Fleece",
    "Prometheus Bound - Caucasus Wind",
    "Theseus at Naxos - Deserted Shore",
    "Bellerophon and Pegasus - Spring of Pirene",
    "Daedalus and Icarus - Flight over the Aegean",
    "Atalanta's Race - Golden Apples",
    "Perseus and Andromeda - Sea of Aethiopia",
    "Alcestis - Devotion Beyond the Grave",
    "Hercules at the Crossroads - Virtue's Choice",
    "Dido's Lament - Carthage Pyre",
    "Sibylline Oracles - Cumaean Leaves",
    "Nymphs of Arcadia - Pan's Afternoon Sleep",
    "Dryad of the Sacred Oak - Rustling Canopy",
    "Nereids of the Aegean - Dolphin Ride",
    "Sirenum Scopuli - Enchanted Reef",

    # Ancient Harp & Lyre Instrumental Showpieces (126-150)
    "Cithara Romana - Cascading Arpeggiando I",
    "Cithara Romana - Cascading Arpeggiando II",
    "Phorminx Antiqua - Homeric Bard Rhapsody",
    "Barbitos Elegance - Seven-String Lyric Sweep",
    "Epigonion Virtuoso - Forty-String Cascades",
    "Psalterion Modal Waves - Dorian and Aeolian",
    "Trigonon Triangularis - Hellenistic Waltz",
    "Kitharodia - Contest of the Virtuosi",
    "Citharistica - Solo Improvisation in D",
    "Kitharisma - Antiphonal Strumming",
    "Arpeggiato Sacrum - Temple Dedication",
    "Glissando of the Gods - Mount Olympus",
    "Plectrum and Finger - Ostinato Duet",
    "Tetrachord Descending - Tragic Gravity",
    "Tetrachord Ascending - Heroic Apotheosis",
    "Chromatic Genus - Twilight of the Hellenes",
    "Enharmonic Whisper - Mystery of Antiquity",
    "Diastematic Purity - Clear Harmonics",
    "Tibicen and Cithara - Processional Duet",
    "Campanella Romana - Chime of the Bell Harp",
    "Bravura Harp - Roman Triumphal Finale",
    "Hellenic Sunset - Sunken Temple of Sounion",
    "Pax Romana - Serenade of the Golden Age",
    "Aegean Nocturne - Phosphorescent Waves",
    "Harp of Antiquity - Eternal Echo"
]

MODES = {
    "dorian": [2, 1, 2, 2, 2, 1, 2],       # D Dorian (D E F G A B C D)
    "phrygian": [1, 2, 2, 2, 1, 2, 2],     # E Phrygian (E F G A B C D E)
    "lydian": [2, 2, 2, 1, 2, 2, 1],       # F Lydian (F G A B C D E F)
    "mixolydian": [2, 2, 1, 2, 2, 1, 2],   # G Mixolydian (G A B C D E F G)
    "aeolian": [2, 1, 2, 2, 1, 2, 2],      # A Aeolian (A B C D E F G A)
    "hypodorian": [2, 1, 2, 2, 1, 2, 2],   # Ancient Hypodorian / Aeolian
}

ROOT_KEYS = [50, 53, 55, 57, 60, 62] # D3, F3, G3, A3, C4, D4

def build_scale(root, intervals, octaves=4):
    scale = [root]
    cur = root
    for _ in range(octaves):
        for iv in intervals:
            cur += iv
            scale.append(cur)
    return scale

def generate_pattern(index, title):
    random.seed(1000 + index * 37)
    
    pat_id = f"harp_antiquity_{index:03d}_{title.lower().replace(' ', '_').replace('-', '_').replace('\'', '').replace(',', '')}"
    # shorten if too long
    if len(pat_id) > 60:
        pat_id = pat_id[:60].rstrip("_")

    # Time signature & rhythm
    time_styles = [(4, 4), (4, 4), (3, 4), (6, 8), (4, 4), (7, 8)]
    num, denom = time_styles[index % len(time_styles)]
    
    bars_options = [4, 8, 8, 16]
    bars = bars_options[index % len(bars_options)]
    
    # Mode selection
    mode_keys = list(MODES.keys())
    mode_name = mode_keys[index % len(mode_keys)]
    intervals = MODES[mode_name]
    root = ROOT_KEYS[index % len(ROOT_KEYS)]
    
    scale = build_scale(root - 24, intervals, octaves=5) # spans bass to high treble
    
    # Tempo hint
    tempo_hints = [64, 68, 72, 76, 84, 92, 104, 116]
    tempo = tempo_hints[index % len(tempo_hints)]
    
    notes = []
    
    beats_per_bar = num if denom == 4 else (num * (4.0 / denom))
    total_qn = bars * beats_per_bar
    step_qn = 0.5 if denom == 4 else 0.5 # 8th-note or quarter-note grid
    
    # Style of harp figuration
    style_idx = index % 5
    # 0 = Sweeping arpeggio cascades with drone bass
    # 1 = Lyrical melodic cantilena with broken chord accompaniment
    # 2 = Antiphonal call-and-response (ancient bardic recitation)
    # 3 = Greek 7/8 or 6/8 dance ostinato with accents
    # 4 = Hymnic polyphonic chords and resonant suspensions
    
    cur_qn = 0.0
    bar_idx = 0
    
    # Find tonic bass pitches
    bass_tonic = root - 12
    bass_fifth = root - 5
    
    while cur_qn < total_qn - 0.01:
        measure_pos = cur_qn % beats_per_bar
        
        # 1. BASS HARP (Voice 2) on measure beginnings or half-measures
        if measure_pos == 0.0 or (beats_per_bar >= 4.0 and abs(measure_pos - (beats_per_bar / 2)) < 0.01):
            bass_dur = 2.0 if beats_per_bar >= 3.0 else beats_per_bar
            b_pitch = bass_tonic if (int(cur_qn / beats_per_bar) % 2 == 0) else bass_fifth
            if random.random() < 0.3:
                b_pitch = root - 24 # Deep resonant low string
            notes.append({
                "pitch": b_pitch,
                "start_qn": round(cur_qn, 3),
                "dur_qn": round(bass_dur, 3),
                "vel": random.randint(78, 92),
                "voice": 2,
                "art": "tenuto" if measure_pos == 0.0 else "normal"
            })
            
            # Additional open fifth in bass for resonance
            if random.random() < 0.65:
                notes.append({
                    "pitch": b_pitch + 7,
                    "start_qn": round(cur_qn, 3),
                    "dur_qn": round(bass_dur, 3),
                    "vel": random.randint(68, 80),
                    "voice": 2,
                    "art": "normal"
                })
        
        # 2. TREBLE MELODY / HARP RUN (Voice 1)
        if style_idx == 0:
            # Cascading harp runs (quintuplet or 8th note arpeggios)
            sub_step = 0.5
            target_scale_deg = (int(cur_qn * 2) % 14) + 12
            target_scale_deg = min(target_scale_deg, len(scale) - 1)
            t_pitch = scale[target_scale_deg]
            dur = 0.45
            art = "normal"
            vel = random.randint(70, 96)
            
        elif style_idx == 1:
            # Lyrical singing melody
            sub_step = 1.0 if (measure_pos % 1.0 == 0) else 0.5
            target_scale_deg = 16 + (int(cur_qn * 3) % 9)
            target_scale_deg = min(target_scale_deg, len(scale) - 1)
            t_pitch = scale[target_scale_deg]
            dur = 0.9 if sub_step >= 1.0 else 0.45
            art = "tenuto" if dur >= 0.8 else "normal"
            vel = random.randint(75, 102)
            
        elif style_idx == 2:
            # Bardic recitation (alternating high motif and middle harp fill)
            sub_step = 0.5
            if int(cur_qn * 2) % 4 == 0:
                t_pitch = scale[min(22, len(scale) - 1)]
                dur = 0.95
                vel = 94
                art = "tenuto"
            else:
                t_pitch = scale[min(14 + (int(cur_qn * 2) % 6), len(scale) - 1)]
                dur = 0.45
                vel = random.randint(64, 82)
                art = "normal"
                
        elif style_idx == 3:
            # Greek rhythmic dance (staccato pulses with rolling chords)
            sub_step = 0.5
            deg = 14 + (int(cur_qn * 4) % 8)
            t_pitch = scale[min(deg, len(scale) - 1)]
            dur = 0.25 if random.random() < 0.6 else 0.45
            art = "staccato" if dur < 0.3 else "normal"
            vel = random.randint(74, 98)
            
        else:
            # Hymnic resonant arpeggiato
            sub_step = 1.0
            deg = 15 + ((int(cur_qn) * 2) % 10)
            t_pitch = scale[min(deg, len(scale) - 1)]
            dur = 1.8
            art = "tenuto"
            vel = random.randint(82, 95)
            
            # Add third or octave
            if random.random() < 0.5:
                notes.append({
                    "pitch": scale[min(deg + 2, len(scale) - 1)],
                    "start_qn": round(cur_qn + 0.1, 3), # slight harp arpeggiation delay
                    "dur_qn": round(dur - 0.1, 3),
                    "vel": vel - 6,
                    "voice": 1,
                    "art": "normal"
                })

        notes.append({
            "pitch": t_pitch,
            "start_qn": round(cur_qn, 3),
            "dur_qn": round(dur, 3),
            "vel": vel,
            "voice": 1,
            "art": art
        })
        
        cur_qn += sub_step

    # Sort notes by start_qn and pitch
    notes.sort(key=lambda n: (n["start_qn"], n["pitch"]))

    data = {
        "id": pat_id,
        "name": title,
        "category": "08_Ancient_Harp_Greek_Roman",
        "bars": bars,
        "time_sig": {
            "num": num,
            "denom": denom
        },
        "tempo_hint": tempo,
        "clef": "grand",
        "notes": notes
    }
    
    file_path = os.path.join(TARGET_DIR, f"{pat_id}.json")
    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

def main():
    print(f"Generating 150 Ancient Greek & Roman Harp patterns into {TARGET_DIR}...")
    for idx, title in enumerate(TITLES, 1):
        generate_pattern(idx, title)
    print("Done! Generated 150 authentic harp patterns.")

if __name__ == "__main__":
    main()

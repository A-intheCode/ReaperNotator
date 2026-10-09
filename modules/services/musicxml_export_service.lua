-- ==============================================================================
-- REAPER Native Notator - Service: MusicXmlExportService
-- Pure-Lua MusicXML 3.1 / 4.0 Partwise Exporter.
-- Exports tracks, MIDI takes (with chord-transformed pitches), voices,
-- key signatures, time signatures, dynamics, hairpins, octave shifts,
-- pedals, text items, and Chord & Scale Lane items (<harmony>).
-- ==============================================================================

local Constants = require("constants")
local KeySignatureService = require("services.key_signature_service")
local MidiService = require("services.midi_service")
local Engraver = require("rendering.engraver")
local SlurService = require("services.slur_service")
local GlissandoService = require("services.glissando_service")
local PortamentoService = require("services.portamento_service")

local MusicXmlExportService = {}

local DIVISIONS_PER_QN = 480 -- 480 ticks per quarter note (clean for triplets, quintuplets, etc.)

-- ------------------------------------------------------------------------------
-- XML Escape
-- ------------------------------------------------------------------------------
local function xml_escape(str)
    if not str then return "" end
    str = tostring(str)
    str = str:gsub("&", "&amp;")
    str = str:gsub("<", "&lt;")
    str = str:gsub(">", "&gt;")
    str = str:gsub("\"", "&quot;")
    str = str:gsub("'", "&apos;")
    return str
end

-- ------------------------------------------------------------------------------
-- Pitch to Step, Alter, Octave
-- ------------------------------------------------------------------------------
local PITCH_STEPS_SHARP = {
    [0] = { step = "C", alter = 0 },
    [1] = { step = "C", alter = 1 },
    [2] = { step = "D", alter = 0 },
    [3] = { step = "D", alter = 1 },
    [4] = { step = "E", alter = 0 },
    [5] = { step = "F", alter = 0 },
    [6] = { step = "F", alter = 1 },
    [7] = { step = "G", alter = 0 },
    [8] = { step = "G", alter = 1 },
    [9] = { step = "A", alter = 0 },
    [10] = { step = "A", alter = 1 },
    [11] = { step = "B", alter = 0 }
}

local PITCH_STEPS_FLAT = {
    [0] = { step = "C", alter = 0 },
    [1] = { step = "D", alter = -1 },
    [2] = { step = "D", alter = 0 },
    [3] = { step = "E", alter = -1 },
    [4] = { step = "E", alter = 0 },
    [5] = { step = "F", alter = 0 },
    [6] = { step = "G", alter = -1 },
    [7] = { step = "G", alter = 0 },
    [8] = { step = "A", alter = -1 },
    [9] = { step = "A", alter = 0 },
    [10] = { step = "B", alter = -1 },
    [11] = { step = "B", alter = 0 }
}

local PITCH_STEPS_DEFAULT = {
    [0] = { step = "C", alter = 0 },
    [1] = { step = "C", alter = 1 },
    [2] = { step = "D", alter = 0 },
    [3] = { step = "E", alter = -1 }, -- Eb matches Constants.PITCH_MAP
    [4] = { step = "E", alter = 0 },
    [5] = { step = "F", alter = 0 },
    [6] = { step = "F", alter = 1 },
    [7] = { step = "G", alter = 0 },
    [8] = { step = "G", alter = 1 },
    [9] = { step = "A", alter = 0 },
    [10] = { step = "B", alter = -1 }, -- Bb matches Constants.PITCH_MAP
    [11] = { step = "B", alter = 0 }
}

local function pitch_to_musicxml(pitch, key_idx, pref_accidental)
    local p = math.max(0, math.min(127, math.floor(pitch + 0.5)))
    local pc = p % 12
    local octave = math.floor(p / 12) - 1

    local kidx = key_idx or 0
    if type(kidx) == "table" then kidx = kidx.key_idx or kidx.idx or 0 end

    local info
    if pref_accidental == -1 then
        info = PITCH_STEPS_FLAT[pc]
    elseif pref_accidental == 1 then
        info = PITCH_STEPS_SHARP[pc]
    elseif kidx > 0 then
        info = PITCH_STEPS_SHARP[pc]
    elseif kidx < 0 then
        info = PITCH_STEPS_FLAT[pc]
    else
        info = PITCH_STEPS_DEFAULT[pc]
    end

    return info.step, info.alter, octave
end

-- ------------------------------------------------------------------------------
-- Note Type and Dot calculation (whole, dotted half, quarter, etc.)
-- ------------------------------------------------------------------------------
local function qn_to_note_type_and_dot(dur_qn)
    if dur_qn >= 3.65 then
        return "whole", false
    elseif dur_qn >= 2.60 then
        return "half", true
    elseif dur_qn >= 1.75 then
        return "half", false
    elseif dur_qn >= 1.30 then
        return "quarter", true
    elseif dur_qn >= 0.85 then
        return "quarter", false
    elseif dur_qn >= 0.65 then
        return "eighth", true
    elseif dur_qn >= 0.42 then
        return "eighth", false
    elseif dur_qn >= 0.33 then
        return "16th", true
    elseif dur_qn >= 0.20 then
        return "16th", false
    elseif dur_qn >= 0.10 then
        return "32nd", false
    else
        return "64th", false
    end
end

local function qn_to_note_type(dur_qn)
    local t, _ = qn_to_note_type_and_dot(dur_qn)
    return t
end

-- Decompose composite durations within a measure using the Gould / Gardner Read Engraver logic
local function split_measure_note_segments(seg_n, m_start_qn, bpi)
    local rel_start = seg_n.start_qn - m_start_qn
    local dur = seg_n.dur_qn
    local decomp = Engraver.decompose_bar_segment(rel_start, dur, bpi)
    if not decomp or #decomp <= 1 then
        return { seg_n }
    end
    
    local out = {}
    for i, sub in ipairs(decomp) do
        local n_sub = {}
        for k, v in pairs(seg_n) do n_sub[k] = v end
        n_sub.start_qn = m_start_qn + sub.start_in_bar
        n_sub.dur_qn = sub.dur_qn
        n_sub.end_qn = n_sub.start_qn + sub.dur_qn
        
        -- Tie chaining for decomposed subsegments
        if i == 1 then
            n_sub.tie_stop = seg_n.tie_stop -- Tie from previous measure
            n_sub.tie_start = true          -- Tie to next segment
        elseif i == #decomp then
            n_sub.tie_stop = true           -- Tie from previous segment
            n_sub.tie_start = seg_n.tie_start -- Tie into next measure
        else
            n_sub.tie_stop = true
            n_sub.tie_start = true
        end

        -- Propagate start and stop notations to outer boundary subsegments only
        n_sub.slur_starts = (i == 1) and seg_n.slur_starts or nil
        n_sub.slur_stops  = (i == #decomp) and seg_n.slur_stops or nil
        n_sub.gliss_starts = (i == 1) and seg_n.gliss_starts or nil
        n_sub.gliss_stops  = (i == #decomp) and seg_n.gliss_stops or nil
        n_sub.slide_starts = (i == 1) and seg_n.slide_starts or nil
        n_sub.slide_stops  = (i == #decomp) and seg_n.slide_stops or nil

        table.insert(out, n_sub)
    end
    return out
end

local function is_standard_musicxml_articulation(art)
    if not art or art == "" or art == "none" then return false end
    local a = tostring(art):lower()
    return a == "staccato" or a == "staccatissimo" or a == "spiccato" or a == "tenuto"
        or a == "accent" or a == "marcato" or a == "harmonic" or a == "flageolet"
        or a == "fermata" or a == "up-bow" or a == "down-bow" or a == "snap-pizzicato"
        or a == "trill" or a == "tremolo"
        or a == "legato" or a == "slur"
        or a:match("^stacc") or a:match("^ten") or a:match("^marc") or a:match("^acc") or a:match("harm")
        or a:match("^legato") or a:match("^slur")
end

-- ------------------------------------------------------------------------------
-- Chord Kind Mapping
-- ------------------------------------------------------------------------------
local function map_chord_kind(quality)
    if not quality or quality == "" or quality == "maj" or quality == "major" then
        return "major", ""
    elseif quality == "m" or quality == "min" or quality == "minor" then
        return "minor", "m"
    elseif quality == "7" or quality == "dom7" then
        return "dominant", "7"
    elseif quality == "maj7" or quality == "M7" then
        return "major-seventh", "maj7"
    elseif quality == "m7" or quality == "min7" then
        return "minor-seventh", "m7"
    elseif quality == "dim" then
        return "diminished", "dim"
    elseif quality == "dim7" then
        return "diminished-seventh", "dim7"
    elseif quality == "hdim7" or quality == "m7b5" then
        return "half-diminished", "m7b5"
    elseif quality == "aug" or quality == "+" then
        return "augmented", "aug"
    elseif quality == "sus4" then
        return "suspended-fourth", "sus4"
    elseif quality == "sus2" then
        return "suspended-second", "sus2"
    else
        return "other", quality
    end
end

-- ------------------------------------------------------------------------------
-- Note Notations Emission (Tied, Articulations, Technical, Fermata)
-- ------------------------------------------------------------------------------
local KEY_SHARPS_ORDER = { 6, 1, 8, 3, 10, 5, 0 } -- F#, C#, G#, D#, A#, E#, B#
local KEY_SHARPS_NATS  = { 5, 0, 7, 2, 9,  4, 11 } -- F,  C,  G,  D,  A,  E,  B
local KEY_FLATS_ORDER  = { 10, 3, 8, 1, 6, 11, 4 } -- Bb, Eb, Ab, Db, Gb, Cb, Fb
local KEY_FLATS_NATS   = { 11, 4, 9, 2, 7, 0,  5 } -- B,  E,  A,  D,  G,  C,  F

local function get_visual_accidental(pitch, key_idx, pref_accidental, is_tie_stop, measure_acc_map)
    -- Gardner Read / Gould rule: A note tied over a barline does NOT repeat its accidental
    if is_tie_stop then return nil end

    local p = math.max(0, math.min(127, math.floor((pitch or 60) + 0.5)))
    local pc = p % 12
    local kidx = key_idx or 0
    if type(kidx) == "table" then kidx = kidx.key_idx or kidx.idx or 0 end

    local info
    if pref_accidental == -1 then
        info = PITCH_STEPS_FLAT[pc]
    elseif pref_accidental == 1 then
        info = PITCH_STEPS_SHARP[pc]
    elseif kidx > 0 then
        info = PITCH_STEPS_SHARP[pc]
    elseif kidx < 0 then
        info = PITCH_STEPS_FLAT[pc]
    else
        info = PITCH_STEPS_DEFAULT[pc]
    end

    local default_alter = info.alter
    local step = info.step
    local step_key = step .. tostring(math.floor(p / 12) - 1)

    local vis_acc = 0 -- 0: none, 1: sharp, -1: flat, 2: natural

    if default_alter == 1 then
        vis_acc = 1
    elseif default_alter == -1 then
        vis_acc = -1
    end

    if kidx > 0 then
        local count = math.min(7, kidx)
        for i = 1, count do
            if pc == KEY_SHARPS_ORDER[i] then
                vis_acc = 0 -- In key signature: suppress accidental
                break
            elseif pc == KEY_SHARPS_NATS[i] then
                vis_acc = 2 -- Natural sign needed
                break
            end
        end
    elseif kidx < 0 then
        local count = math.min(7, math.abs(kidx))
        for i = 1, count do
            if pc == KEY_FLATS_ORDER[i] then
                vis_acc = 0 -- In key signature: suppress accidental
                break
            elseif pc == KEY_FLATS_NATS[i] then
                vis_acc = 2 -- Natural sign needed
                break
            end
        end
    end

    if measure_acc_map then
        local prev_acc = measure_acc_map[step_key]
        if prev_acc ~= nil and prev_acc == vis_acc then
            vis_acc = 0
        end
        measure_acc_map[step_key] = vis_acc
    end

    if vis_acc == 1 then return "sharp"
    elseif vis_acc == -1 then return "flat"
    elseif vis_acc == 2 then return "natural"
    else return nil end
end

local function split_notes_into_monophonic_voices(notes, base_voice_offset)
    base_voice_offset = base_voice_offset or 1
    if not notes or #notes == 0 then return {} end

    -- Clone and sort chronologically; for same onset, higher pitch first (Soprano/melody stays in voice 1)
    local sorted = {}
    for _, n in ipairs(notes) do table.insert(sorted, n) end
    table.sort(sorted, function(a, b)
        if math.abs(a.start_qn - b.start_qn) > 0.01 then
            return a.start_qn < b.start_qn
        end
        return (a.pitch or 60) > (b.pitch or 60)
    end)

    local voice_map = {} -- [v] = list of notes
    local voice_end = {} -- [v] = end_qn
    local voice_last = {} -- [v] = { start_qn, dur_qn }

    for _, n in ipairs(sorted) do
        local n_end = n.start_qn + n.dur_qn
        local assigned_v = nil

        -- If note already has explicit channel / voice, try to honor it
        local raw_chan = n.chan or (n.orig and n.orig.chan)
        local explicit_v = (raw_chan ~= nil) and (raw_chan + base_voice_offset) or nil
        if explicit_v then
            local l = voice_last[explicit_v]
            local can_fit = false
            if not l then
                can_fit = true
            elseif math.abs(l.start_qn - n.start_qn) < 0.01 and math.abs(l.dur_qn - n.dur_qn) < 0.01 then
                can_fit = true -- True chord
            elseif n.start_qn >= (voice_end[explicit_v] or 0) - 0.01 then
                can_fit = true -- Consecutive
            end
            if can_fit then assigned_v = explicit_v end
        end

        if not assigned_v then
            for v_idx = 0, 7 do
                local v = base_voice_offset + v_idx
                local l = voice_last[v]
                if not l then
                    assigned_v = v
                    break
                elseif math.abs(l.start_qn - n.start_qn) < 0.01 and math.abs(l.dur_qn - n.dur_qn) < 0.01 then
                    -- True chord (exact same start and exact same duration)
                    assigned_v = v
                    break
                elseif n.start_qn >= (voice_end[v] or 0) - 0.01 then
                    -- Consecutive note after previous note finished
                    assigned_v = v
                    break
                end
            end
        end

        if not assigned_v then assigned_v = base_voice_offset + 7 end

        if not voice_map[assigned_v] then voice_map[assigned_v] = {} end
        table.insert(voice_map[assigned_v], n)
        voice_end[assigned_v] = math.max(voice_end[assigned_v] or 0, n_end)
        voice_last[assigned_v] = { start_qn = n.start_qn, dur_qn = n.dur_qn }
    end

    return voice_map
end

local function emit_note_notations(emit, cn, trk_clef)
    local art = cn.articulation and tostring(cn.articulation):lower()
    -- Elaine Gould / MusicXML standard: legato/slur is exclusively expressed by <slur>, never as <other-articulation>
    if art == "legato" or art == "slur" or (art and (art:match("^legato") or art:match("^slur"))) then
        art = nil
    end
    local is_arp = cn.arpeggio or (art and (art == "arpeggio" or art:find("arpegg")))
    local has_tied = cn.tie_start or cn.tie_stop
    local has_slur = (cn.slur_starts and #cn.slur_starts > 0) or (cn.slur_stops and #cn.slur_stops > 0)
    local has_gliss = (cn.gliss_starts and #cn.gliss_starts > 0) or (cn.gliss_stops and #cn.gliss_stops > 0)
    local has_slide = (cn.slide_starts and #cn.slide_starts > 0) or (cn.slide_stops and #cn.slide_stops > 0)
    local has_art = art and art ~= "" and art ~= "none"

    if not has_tied and not has_slur and not has_gliss and not has_slide and not has_art and not is_arp then return end

    emit('        <notations>\n')

    -- 1. Tied notations
    if cn.tie_stop then emit('          <tied type="stop"/>\n') end
    if cn.tie_start then
        local p = cn.pitch or 60
        local mid_p = 71 -- B4 in treble
        if trk_clef == "bass" then
            mid_p = 50 -- D3 in bass
        elseif trk_clef == "alto" then
            mid_p = 60 -- C4 in alto
        elseif trk_clef == "tenor" then
            mid_p = 57 -- A3 in tenor
        end
        local orient = (p >= mid_p) and "over" or "under"
        emit('          <tied type="start" orientation="%s"/>\n', orient)
    end

    -- 2. Slurs
    if cn.slur_stops then
        for _, sl in ipairs(cn.slur_stops) do
            emit('          <slur type="stop" number="%d"/>\n', sl.number or 1)
        end
    end
    if cn.slur_starts then
        for _, sl in ipairs(cn.slur_starts) do
            local pl = sl.placement and string.format(' placement="%s"', sl.placement) or ''
            emit('          <slur type="start" number="%d"%s/>\n', sl.number or 1, pl)
        end
    end

    -- 3. Glissandi (<glissando line-type="wavy">)
    if cn.gliss_stops then
        for _, gl in ipairs(cn.gliss_stops) do
            emit('          <glissando type="stop" number="%d"/>\n', gl.number or 1)
        end
    end
    if cn.gliss_starts then
        for _, gl in ipairs(cn.gliss_starts) do
            local txt = gl.text or "gliss."
            emit('          <glissando type="start" number="%d" line-type="wavy">%s</glissando>\n', gl.number or 1, xml_escape(txt))
        end
    end

    -- 4. Slides / Portamento (<slide line-type="solid">)
    if cn.slide_stops then
        for _, sl in ipairs(cn.slide_stops) do
            emit('          <slide type="stop" number="%d"/>\n', sl.number or 1)
        end
    end
    if cn.slide_starts then
        for _, sl in ipairs(cn.slide_starts) do
            local txt = sl.text and xml_escape(sl.text) or ""
            if txt ~= "" then
                emit('          <slide type="start" number="%d" line-type="solid">%s</slide>\n', sl.number or 1, txt)
            else
                emit('          <slide type="start" number="%d" line-type="solid"/>\n', sl.number or 1)
            end
        end
    end

    -- 5. Ornaments, Technical, Articulations, Fermata, Arpeggiate
    if has_art then
        if art == "staccato" or art == "stacc" then
            emit('          <articulations>\n            <staccato/>\n          </articulations>\n')
        elseif art == "staccatissimo" or art:match("staccatiss") or art == "spiccato" or art:match("spicc") then
            emit('          <articulations>\n            <staccatissimo/>\n          </articulations>\n')
        elseif art == "tenuto" or art == "ten" then
            emit('          <articulations>\n            <tenuto/>\n          </articulations>\n')
        elseif art == "accent" or art == "acc" then
            emit('          <articulations>\n            <accent/>\n          </articulations>\n')
        elseif art == "marcato" or art == "marc" then
            emit('          <articulations>\n            <strong-accent type="up"/>\n          </articulations>\n')
        elseif art == "harmonic" or art == "flageolet" or art:match("harm") then
            emit('          <technical>\n            <harmonic>\n              <natural/>\n            </harmonic>\n          </technical>\n')
        elseif art == "fermata" then
            emit('          <fermata type="upright"/>\n')
        elseif art == "up-bow" then
            emit('          <technical>\n            <up-bow/>\n          </technical>\n')
        elseif art == "down-bow" then
            emit('          <technical>\n            <down-bow/>\n          </technical>\n')
        elseif art == "snap-pizzicato" or art:match("bartok") or art:match("snap") then
            emit('          <technical>\n            <snap-pizzicato/>\n          </technical>\n')
        elseif art == "trill" or art:match("trill") then
            emit('          <ornaments>\n            <trill-mark/>\n          </ornaments>\n')
        elseif art == "tremolo" or art:match("trem") then
            emit('          <ornaments>\n            <tremolo type="single">3</tremolo>\n          </ornaments>\n')
        else
            -- Non-standard / custom articulation exported as other-articulation
            emit('          <articulations>\n            <other-articulation>%s</other-articulation>\n          </articulations>\n', xml_escape(cn.articulation))
        end
    end

    if is_arp then
        local arp_dir = (cn.arpeggio == "down" or (art and art:find("down"))) and "down" or "up"
        emit('          <arpeggiate direction="%s"/>\n', arp_dir)
    end

    emit('        </notations>\n')
end

-- ------------------------------------------------------------------------------
-- Compute Beams for notes in voice (eighth and sixteenth note groupings by beat)
-- ------------------------------------------------------------------------------
local function compute_voice_beams(v_notes, m_start_qn, bpi)
    local beat_onsets = {}
    for _, n in ipairs(v_notes) do
        if n.dur_qn and n.dur_qn <= 0.85 then
            local rel_qn = n.start_qn - m_start_qn
            local beat_idx = math.floor(rel_qn / 1.0)
            if not beat_onsets[beat_idx] then beat_onsets[beat_idx] = {} end

            local bo = beat_onsets[beat_idx]
            local found_onset = false
            for _, entry in ipairs(bo) do
                if math.abs(entry.onset_qn - n.start_qn) < 0.01 then
                    table.insert(entry.notes, n)
                    found_onset = true
                    break
                end
            end
            if not found_onset then
                table.insert(bo, { onset_qn = n.start_qn, notes = { n } })
            end
        end
    end

    for _, onsets in pairs(beat_onsets) do
        table.sort(onsets, function(a, b) return a.onset_qn < b.onset_qn end)
        if #onsets >= 2 then
            for oi, entry in ipairs(onsets) do
                local b1_val = (oi == 1 and "begin") or (oi == #onsets and "end") or "continue"
                for _, n in ipairs(entry.notes) do
                    n.beam1 = b1_val
                    if n.dur_qn <= 0.40 then
                        n.beam2 = b1_val
                    end
                end
            end
        end
    end
end

-- ------------------------------------------------------------------------------
-- Emit Voice Notes & Rests Stream
-- ------------------------------------------------------------------------------
local function emit_voice_notes(emit, v_notes, voice_id, staff_id, m_start_qn, m_end_qn, key_idx, trk_clef, bpi)
    local measure_acc_map = {}

    -- Close tiny gaps between consecutive notes in the voice (< 0.15 QN) to produce clean notation
    for idx = 1, #v_notes do
        local vn = v_notes[idx]
        if idx < #v_notes then
            local next_vn = v_notes[idx + 1]
            if next_vn.start_qn > vn.start_qn + 0.01 then
                local gap = next_vn.start_qn - (vn.start_qn + vn.dur_qn)
                if gap > 0.001 and gap < 0.15 then
                    vn.dur_qn = next_vn.start_qn - vn.start_qn
                end
            end
        else
            local end_gap = m_end_qn - (vn.start_qn + vn.dur_qn)
            if end_gap > 0.001 and end_gap < 0.15 then
                vn.dur_qn = m_end_qn - vn.start_qn
            end
        end
    end

    compute_voice_beams(v_notes, m_start_qn, bpi or 4.0)

    local cur_qn = m_start_qn
    local i = 1
    while i <= #v_notes do
        local n = v_notes[i]

        -- Fill rest before this note if gap >= 0.05 QN
        if n.start_qn > cur_qn + 0.05 then
            local rest_dur_qn = n.start_qn - cur_qn
            local rest_div = math.floor(rest_dur_qn * DIVISIONS_PER_QN + 0.5)
            if rest_div > 0 then
                emit('      <note>\n')
                emit('        <rest/>\n')
                emit('        <duration>%d</duration>\n', rest_div)
                emit('        <voice>%d</voice>\n', voice_id)
                if staff_id then
                    emit('        <staff>%d</staff>\n', staff_id)
                end
                emit('      </note>\n')
            end
            cur_qn = n.start_qn
        end

        -- Group chord notes sharing the same onset
        local chord_notes = { n }
        local j = i + 1
        while j <= #v_notes and math.abs(v_notes[j].start_qn - n.start_qn) < 0.01 do
            table.insert(chord_notes, v_notes[j])
            j = j + 1
        end

        for ci, cn in ipairs(chord_notes) do
            local step, alter, octave = pitch_to_musicxml(cn.pitch, key_idx, cn.accidental)
            local dur_div = math.floor(cn.dur_qn * DIVISIONS_PER_QN + 0.5)
            local note_type, has_dot = qn_to_note_type_and_dot(cn.dur_qn)

            emit('      <note>\n')
            if ci > 1 then
                emit('        <chord/>\n')
            end
            emit('        <pitch>\n')
            emit('          <step>%s</step>\n', step)
            if alter ~= 0 then
                emit('          <alter>%d</alter>\n', alter)
            end
            emit('          <octave>%d</octave>\n', octave)
            emit('        </pitch>\n')
            emit('        <duration>%d</duration>\n', dur_div)
            if cn.tie_stop then
                emit('        <tie type="stop"/>\n')
            end
            if cn.tie_start then
                emit('        <tie type="start"/>\n')
            end
            emit('        <voice>%d</voice>\n', voice_id)
            emit('        <type>%s</type>\n', note_type)
            if has_dot then
                emit('        <dot/>\n')
            end
            local vis_acc = get_visual_accidental(cn.pitch, key_idx, cn.accidental, cn.tie_stop, measure_acc_map)
            if vis_acc then
                emit('        <accidental>%s</accidental>\n', vis_acc)
            end
            if staff_id then
                emit('        <staff>%d</staff>\n', staff_id)
            end
            if cn.beam1 then
                emit('        <beam number="1">%s</beam>\n', cn.beam1)
            end
            if cn.beam2 then
                emit('        <beam number="2">%s</beam>\n', cn.beam2)
            end

            -- Notations: Tied and Articulations
            emit_note_notations(emit, cn, trk_clef)

            emit('      </note>\n')
        end

        cur_qn = n.start_qn + n.dur_qn
        i = j
    end

    -- Fill rest until measure end if needed
    if cur_qn < m_end_qn - 0.05 then
        local end_rest_qn = m_end_qn - cur_qn
        local end_rest_div = math.floor(end_rest_qn * DIVISIONS_PER_QN + 0.5)
        if end_rest_div > 0 then
            emit('      <note>\n')
            emit('        <rest/>\n')
            emit('        <duration>%d</duration>\n', end_rest_div)
            emit('        <voice>%d</voice>\n', voice_id)
            if staff_id then
                emit('        <staff>%d</staff>\n', staff_id)
            end
            emit('      </note>\n')
        end
    end
end

-- ------------------------------------------------------------------------------
-- Slur, Tie, Glissando & Slide Allocation Helpers for Export
-- ------------------------------------------------------------------------------
local function assign_mark_numbers(items, start_key, end_key)
    local active = {} -- number -> end_val
    for _, item in ipairs(items) do
        local s_val = item[start_key] or 0.0
        local e_val = item[end_key] or (s_val + 1.0)
        -- Free numbers whose end_val <= s_val
        for num, end_qn in pairs(active) do
            if end_qn <= s_val + 0.005 then
                active[num] = nil
            end
        end
        -- Find smallest unused number 1..6
        local assigned = 1
        for num = 1, 6 do
            if not active[num] then
                assigned = num
                break
            end
        end
        active[assigned] = e_val
        item._assigned_number = assigned
    end
end

local function prepare_track_marks(raw_notes, trk_guid, trk_clef, state, options)
    local norm_trk_guid = trk_guid and trk_guid:upper():gsub("[^%w]", "") or ""
    local function guid_matches(g)
        if not g or g == "" then return true end
        local ng = g:upper():gsub("[^%w]", "")
        return (ng == "" or norm_trk_guid == "" or ng == norm_trk_guid)
    end

    -- 1. Filter out glissando ladder notes and restore Note 1 orig_dur1
    local filtered_notes = {}
    local gliss_masters_list = {}
    if state and state.glissando_marks then
        for _, gm in ipairs(state.glissando_marks) do
            if guid_matches(gm.track_guid) then
                table.insert(gliss_masters_list, gm)
            end
        end
    end

    for _, n in ipairs(raw_notes) do
        local is_step = (n.is_gliss_step == true)
        if not is_step and #gliss_masters_list > 0 then
            for _, gm in ipairs(gliss_masters_list) do
                if (gm.chan == nil or gm.chan == n.chan) and gm.pitch2 and gm.start_qn2 then
                    local p_min = math.min(gm.pitch1, gm.pitch2)
                    local p_max = math.max(gm.pitch1, gm.pitch2)
                    if n.pitch > p_min and n.pitch < p_max then
                        local t_start_qn = gm.start_qn1 + ((gm.start_pct1 or 50) / 100.0) * (gm.orig_dur1 or 1.0)
                        if n.start_qn >= (t_start_qn - 0.05) and n.start_qn < (gm.start_qn2 - 0.005) then
                            is_step = true
                            break
                        end
                    end
                end
            end
        end

        if not is_step then
            -- Check if this note is Note 1 of a glissando and restore its duration
            for _, gm in ipairs(gliss_masters_list) do
                if gm.pitch1 == n.pitch and (gm.chan == nil or gm.chan == n.chan) and math.abs(n.start_qn - gm.start_qn1) <= 0.05 then
                    if gm.orig_dur1 and gm.orig_dur1 > 0.01 then
                        n.dur_qn = gm.orig_dur1
                        n.end_qn = n.start_qn + n.dur_qn
                    end
                    break
                end
            end
            table.insert(filtered_notes, n)
        end
    end

    local notes = filtered_notes

    -- Helper to match note by pitch and start_qn
    local function find_matching_note(pitch, target_qn, tol)
        tol = tol or 0.15
        local best, best_diff = nil, tol
        for _, n in ipairs(notes) do
            if n.pitch == pitch then
                local diff = math.abs((n.start_qn or 0.0) - target_qn)
                if diff <= best_diff then
                    best = n
                    best_diff = diff
                end
            end
        end
        return best
    end

    -- 2. User Ties (options.include_slurs_ties ~= false)
    if options.include_slurs_ties ~= false and state and state.user_ties then
        for _, tie in ipairs(state.user_ties) do
            if guid_matches(tie.track_guid) then
                local n1 = find_matching_note(tie.pitch, tie.n1_start_qn or 0.0)
                local n2 = find_matching_note(tie.pitch, tie.n2_start_qn or 1.0)
                if n1 then n1.is_tied_master = true end
                if n2 then n2.is_tied_slave = true end
            end
        end
    end

    -- 3. Slurs (options.include_slurs_ties ~= false)
    if options.include_slurs_ties ~= false and state and state.user_slurs then
        local track_slurs = {}
        for _, sl in ipairs(state.user_slurs) do
            if guid_matches(sl.track_guid) then
                table.insert(track_slurs, sl)
            end
        end
        table.sort(track_slurs, function(a, b) return (a.start_qn or 0.0) < (b.start_qn or 0.0) end)
        assign_mark_numbers(track_slurs, "start_qn", "n2_start_qn")

        for _, sl in ipairs(track_slurs) do
            local n1 = find_matching_note(sl.pitch1, sl.start_qn or 0.0)
            local n2 = find_matching_note(sl.pitch2, sl.n2_start_qn or 1.0)
            if not n2 then
                -- Fallback: closest note near n2_start_qn
                local tol = 0.20
                for _, n in ipairs(notes) do
                    if math.abs((n.start_qn or 0.0) - (sl.n2_start_qn or 1.0)) <= tol then
                        n2 = n
                        break
                    end
                end
            end

            if n1 then
                local mid_p = (trk_clef == "bass") and 50 or ((trk_clef == "alto") and 60 or ((trk_clef == "tenor") and 57 or 71))
                local placement = "above"
                if n1.stem_dir == "up" then
                    placement = "below"
                elseif n1.stem_dir == "down" then
                    placement = "above"
                elseif (n1.pitch or 60) < mid_p then
                    placement = "below"
                else
                    placement = "above"
                end

                n1.slur_starts = n1.slur_starts or {}
                table.insert(n1.slur_starts, { number = sl._assigned_number or 1, placement = placement })
            end
            if n2 then
                n2.slur_stops = n2.slur_stops or {}
                table.insert(n2.slur_stops, { number = sl._assigned_number or 1 })
            end
        end
    end

    -- 4. Glissandi (options.include_gliss_port ~= false)
    if options.include_gliss_port ~= false and #gliss_masters_list > 0 then
        table.sort(gliss_masters_list, function(a, b) return (a.start_qn1 or 0.0) < (b.start_qn1 or 0.0) end)
        assign_mark_numbers(gliss_masters_list, "start_qn1", "start_qn2")

        for _, gm in ipairs(gliss_masters_list) do
            local n1 = find_matching_note(gm.pitch1, gm.start_qn1 or 0.0)
            local n2 = find_matching_note(gm.pitch2, gm.start_qn2 or 1.0)
            if n1 then
                n1.gliss_starts = n1.gliss_starts or {}
                table.insert(n1.gliss_starts, {
                    number = gm._assigned_number or 1,
                    text = (gm.show_text ~= false) and "gliss." or nil
                })
            end
            if n2 then
                n2.gliss_stops = n2.gliss_stops or {}
                table.insert(n2.gliss_stops, { number = gm._assigned_number or 1 })
            end
        end
    end

    -- 5. Portamento / Slides (options.include_gliss_port ~= false)
    if options.include_gliss_port ~= false and state and state.portamento_marks then
        local track_ports = {}
        for _, pm in ipairs(state.portamento_marks) do
            if guid_matches(pm.track_guid) then
                table.insert(track_ports, pm)
            end
        end
        table.sort(track_ports, function(a, b) return (a.start_qn1 or 0.0) < (b.start_qn1 or 0.0) end)
        assign_mark_numbers(track_ports, "start_qn1", "start_qn2")

        for _, pm in ipairs(track_ports) do
            local n1 = find_matching_note(pm.pitch1, pm.start_qn1 or 0.0)
            local n2 = find_matching_note(pm.pitch2, pm.start_qn2 or 1.0)
            if n1 then
                n1.slide_starts = n1.slide_starts or {}
                table.insert(n1.slide_starts, {
                    number = pm._assigned_number or 1,
                    text = (pm.show_text) and "port." or nil
                })
            end
            if n2 then
                n2.slide_stops = n2.slide_stops or {}
                table.insert(n2.slide_stops, { number = pm._assigned_number or 1 })
            end
        end
    end

    return notes
end

-- ------------------------------------------------------------------------------
-- Main Export Function
-- ------------------------------------------------------------------------------
function MusicXmlExportService.export_project(state, options)
    options = options or {}
    local out_path = options.file_path
    if not out_path or out_path == "" then
        return false, "No output file path specified."
    end

    if state then
        if not state.user_slurs or not state.user_ties then
            SlurService.load_slurs(state)
        end
        if not state.glissando_marks then
            GlissandoService.load_glissandos(state)
        end
        if not state.portamento_marks then
            PortamentoService.load_portamentos(state)
        end
    end

    local proj_tracks = options.tracks
    if not proj_tracks or #proj_tracks == 0 then
        -- Default to active tracks cache or all tracks
        proj_tracks = {}
        local num_tracks = reaper.CountTracks(0)
        for ti = 0, num_tracks - 1 do
            local tr = reaper.GetTrack(0, ti)
            if tr and reaper.CountTrackMediaItems(tr) > 0 then
                table.insert(proj_tracks, tr)
            end
        end
    end

    if #proj_tracks == 0 then
        return false, "No tracks with MIDI items found to export."
    end

    -- Project Metadata
    local _, proj_fn = reaper.EnumProjects(-1, "")
    local work_title = "Untitled Score"
    if proj_fn and proj_fn ~= "" then
        local name = proj_fn:match("([^\\/]+)%.rpp$") or proj_fn:match("([^\\/]+)%.RPP$") or proj_fn:match("([^\\/]+)$")
        if name then work_title = name end
    end

    local xml = {}
    local function emit(fmt, ...)
        if select("#", ...) > 0 then
            table.insert(xml, string.format(fmt, ...))
        else
            table.insert(xml, fmt)
        end
    end

    -- XML Header
    emit('<?xml version="1.0" encoding="UTF-8"?>\n')
    emit('<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">\n')
    emit('<score-partwise version="4.0">\n')

    -- Work & Identification
    emit('  <work>\n')
    emit('    <work-title>%s</work-title>\n', xml_escape(work_title))
    emit('  </work>\n')
    emit('  <identification>\n')
    emit('    <encoding>\n')
    emit('      <software>REAPER Native Notator</software>\n')
    emit('      <encoding-date>%s</encoding-date>\n', os.date("%Y-%m-%d"))
    emit('    </encoding>\n')
    emit('  </identification>\n')

    -- Part List
    emit('  <part-list>\n')
    for pi, trk_entry in ipairs(proj_tracks) do
        local tr = (type(trk_entry) == "table" and trk_entry.track) or trk_entry
        local _, trk_name = reaper.GetTrackName(tr)
        if not trk_name or trk_name == "" then trk_name = string.format("Track %d", pi) end
        emit('    <score-part id="P%d">\n', pi)
        emit('      <part-name>%s</part-name>\n', xml_escape(trk_name))
        emit('    </score-part>\n')
    end
    emit('  </part-list>\n')

    -- Gather all notes, dynamics, articulations and clef per track
    local tracks_notes = {}
    local tracks_dynamics = {}
    local tracks_articulations = {}
    local tracks_clefs = {}
    local max_qn = 16.0 -- At least 4 measures
    for pi, trk_entry in ipairs(proj_tracks) do
        local tr = (type(trk_entry) == "table" and trk_entry.track) or trk_entry
        local trk_guid = (type(trk_entry) == "table" and trk_entry.guid) or (tr and reaper.GetTrackGUID(tr))
        local _, trk_name = reaper.GetTrackName(tr)
        local items_info, all_notes, all_dynamics, all_articulations, max_q = MidiService.get_track_items_and_notes(tr)
        local notes = all_notes or {}
        if #notes == 0 and type(items_info) == "table" and items_info[1] and items_info[1].pitch then
            notes = items_info
        end
        tracks_notes[pi] = notes
        tracks_dynamics[pi] = all_dynamics or {}
        tracks_articulations[pi] = all_articulations or {}

        local trk_clef = Engraver.get_track_clef(trk_guid or tr, trk_name or "", notes, state)
        tracks_clefs[pi] = trk_clef or "treble"

        for _, n in ipairs(tracks_notes[pi]) do
            local s_qn = tonumber(n.start_qn) or 0.0
            local d_qn = tonumber(n.dur_qn) or (n.end_qn and (n.end_qn - s_qn)) or 1.0
            n.start_qn = s_qn
            n.dur_qn = d_qn
            local end_qn = s_qn + d_qn
            if end_qn > max_qn then max_qn = end_qn end
        end

        for _, dyn in ipairs(tracks_dynamics[pi]) do
            if dyn.qn and dyn.qn > max_qn then max_qn = dyn.qn end
        end
    end

    -- Also check elements in state (chord items, text items, pedals, hairpins) for max QN
    if state.chord_items then
        for _, c in ipairs(state.chord_items) do
            if c.end_qn and c.end_qn > max_qn then max_qn = c.end_qn end
        end
    end
    if state.text_items then
        for _, ti in ipairs(state.text_items) do
            if ti.qn and ti.qn > max_qn then max_qn = ti.qn end
        end
    end
    if state.hairpins then
        for _, hp in ipairs(state.hairpins) do
            if hp.end_qn and hp.end_qn > max_qn then max_qn = hp.end_qn end
        end
    end

    -- Determine measure count and bounds
    local bpi = 4.0
    local timesig_num, timesig_denom = reaper.TimeMap_GetTimeSigAtTime(0, 0)
    if timesig_num and timesig_num > 0 and timesig_denom and timesig_denom > 0 then
        bpi = timesig_num * (4.0 / timesig_denom)
    end
    local total_measures = math.max(1, math.ceil(max_qn / bpi))

    -- Ensure any point events (dynamics, text items, tempo) sitting on a measure downbeat are included
    for pi = 1, #proj_tracks do
        if tracks_dynamics[pi] then
            for _, dyn in ipairs(tracks_dynamics[pi]) do
                if dyn.qn then
                    local m_req = math.floor((dyn.qn + 0.001) / bpi) + 1
                    if m_req > total_measures then total_measures = m_req end
                end
            end
        end
    end
    if state.text_items then
        for _, ti in ipairs(state.text_items) do
            if ti.qn then
                local m_req = math.floor((ti.qn + 0.001) / bpi) + 1
                if m_req > total_measures then total_measures = m_req end
            end
        end
    end

    -- Collect project tempo points for export
    local tempo_points = {}
    if state and state.tempo_markers and #state.tempo_markers > 0 then
        for _, tm in ipairs(state.tempo_markers) do
            table.insert(tempo_points, {
                qn = tm.start_qn or 0.0,
                bpm = math.floor((tm.bpm or 120) + 0.5),
                label = tm.label or "",
                type = tm.type or "absolute"
            })
        end
    else
        local cnt = reaper.CountTempoTimeSigMarkers(0)
        if cnt > 0 then
            for i = 0, cnt - 1 do
                local ok, tpos, _, _, bpm = reaper.GetTempoTimeSigMarker(0, i)
                if ok then
                    local qn = reaper.TimeMap2_timeToQN(0, tpos)
                    table.insert(tempo_points, {
                        qn = qn,
                        bpm = math.floor(bpm + 0.5),
                        label = (i == 0 and "Allegro" or ""),
                        type = "absolute"
                    })
                end
            end
        end
    end
    
    local master_bpm = math.floor((reaper.Master_GetTempo() or 120) + 0.5)
    if #tempo_points == 0 or tempo_points[1].qn > 0.05 then
        table.insert(tempo_points, 1, {
            qn = 0.0,
            bpm = master_bpm,
            label = "",
            type = "absolute"
        })
    end
    table.sort(tempo_points, function(a, b) return a.qn < b.qn end)

    -- Export Parts
    for pi, trk_entry in ipairs(proj_tracks) do
        local tr = (type(trk_entry) == "table" and trk_entry.track) or trk_entry
        local trk_guid = (type(trk_entry) == "table" and trk_entry.guid) or (tr and reaper.GetTrackGUID(tr))
        local trk_clef = tracks_clefs[pi] or "treble"
        local notes = prepare_track_marks(tracks_notes[pi] or {}, trk_guid, trk_clef, state, options)

        emit('  <part id="P%d">\n', pi)

        local prev_key_idx = nil
        local prev_num, prev_den = nil, nil

        for m = 1, total_measures do
            local m_start_qn = (m - 1) * bpi
            local m_end_qn = m * bpi
            local m_dur_div = math.floor(bpi * DIVISIONS_PER_QN + 0.5)

            emit('    <measure number="%d">\n', m)

            -- Attributes (Divisions, Key, Time, Clef)
            local eff_key = KeySignatureService.resolve_effective_key(state, trk_entry, nil, m_start_qn + 0.1)
            local key_idx = eff_key and (eff_key.idx or eff_key.key_idx) or 0
            local key_mode = eff_key and eff_key.mode or "major"

            local eff_time = nil
            if KeySignatureService and KeySignatureService.resolve_effective_time_sig then
                eff_time = KeySignatureService.resolve_effective_time_sig(state, trk_entry, nil, m_start_qn + 0.1)
            end
            local time_sec = reaper.TimeMap2_QNToTime(0, m_start_qn + 0.1)
            local r_num, r_den = reaper.TimeMap_GetTimeSigAtTime(0, time_sec)
            local num = (eff_time and eff_time.num) or (r_num and r_num > 0 and r_num) or (timesig_num or 4)
            local den = (eff_time and eff_time.denom) or (r_den and r_den > 0 and r_den) or (timesig_denom or 4)

            local need_attrs = (m == 1) or (key_idx ~= prev_key_idx) or (num ~= prev_num) or (den ~= prev_den)

            if need_attrs then
                emit('      <attributes>\n')
                if m == 1 then
                    emit('        <divisions>%d</divisions>\n', DIVISIONS_PER_QN)
                end
                if (m == 1) or (key_idx ~= prev_key_idx) then
                    emit('        <key>\n')
                    emit('          <fifths>%d</fifths>\n', key_idx)
                    emit('          <mode>%s</mode>\n', key_mode)
                    emit('        </key>\n')
                    prev_key_idx = key_idx
                end
                if (m == 1) or (num ~= prev_num) or (den ~= prev_den) then
                    emit('        <time>\n')
                    emit('          <beats>%d</beats>\n', num)
                    emit('          <beat-type>%d</beat-type>\n', den)
                    emit('        </time>\n')
                    prev_num, prev_den = num, den
                end
                if m == 1 then
                    if trk_clef == "grand" then
                        emit('        <staves>2</staves>\n')
                        emit('        <clef number="1">\n')
                        emit('          <sign>G</sign>\n')
                        emit('          <line>2</line>\n')
                        emit('        </clef>\n')
                        emit('        <clef number="2">\n')
                        emit('          <sign>F</sign>\n')
                        emit('          <line>4</line>\n')
                        emit('        </clef>\n')
                    elseif trk_clef == "bass" then
                        emit('        <clef>\n')
                        emit('          <sign>F</sign>\n')
                        emit('          <line>4</line>\n')
                        emit('        </clef>\n')
                    elseif trk_clef == "alto" then
                        emit('        <clef>\n')
                        emit('          <sign>C</sign>\n')
                        emit('          <line>3</line>\n')
                        emit('        </clef>\n')
                    elseif trk_clef == "tenor" then
                        emit('        <clef>\n')
                        emit('          <sign>C</sign>\n')
                        emit('          <line>4</line>\n')
                        emit('        </clef>\n')
                    else
                        emit('        <clef>\n')
                        emit('          <sign>G</sign>\n')
                        emit('          <line>2</line>\n')
                        emit('        </clef>\n')
                    end
                end
                emit('      </attributes>\n')
            end

            -- ------------------------------------------------------------------
            -- Tempo Directions (<direction><metronome> & <sound tempo="...">)
            -- ------------------------------------------------------------------
            if pi == 1 and tempo_points then
                for _, tp in ipairs(tempo_points) do
                    if tp.qn >= m_start_qn - 0.001 and tp.qn < m_end_qn - 0.001 then
                        local offset_div = math.floor((tp.qn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                        emit('      <direction placement="above">\n')
                        if tp.label and tp.label ~= "" then
                            emit('        <direction-type>\n')
                            emit('          <words font-weight="bold">%s </words>\n', xml_escape(tp.label))
                            emit('        </direction-type>\n')
                            emit('        <direction-type>\n')
                            emit('          <metronome parentheses="yes">\n')
                            emit('            <beat-unit>quarter</beat-unit>\n')
                            emit('            <per-minute>%d</per-minute>\n', tp.bpm)
                            emit('          </metronome>\n')
                            emit('        </direction-type>\n')
                        else
                            emit('        <direction-type>\n')
                            emit('          <metronome>\n')
                            emit('            <beat-unit>quarter</beat-unit>\n')
                            emit('            <per-minute>%d</per-minute>\n', tp.bpm)
                            emit('          </metronome>\n')
                            emit('        </direction-type>\n')
                        end
                        if offset_div > 0 then
                            emit('        <offset>%d</offset>\n', offset_div)
                        end
                        emit('        <sound tempo="%d"/>\n', tp.bpm)
                        emit('      </direction>\n')
                    end
                end
            end

            -- ------------------------------------------------------------------
            -- Rehearsal Marks & Navigation (<rehearsal>, <segno>, <coda>, D.C./D.S.)
            -- ------------------------------------------------------------------
            if pi == 1 and state.rehearsal_marks then
                for _, rm in ipairs(state.rehearsal_marks) do
                    if rm.measure == m - 1 then
                        emit('      <direction placement="above">\n')
                        emit('        <direction-type>\n')
                        if rm.type == "letter" or rm.type == "number" or rm.type == "custom" then
                            emit('          <rehearsal>%s</rehearsal>\n', xml_escape(rm.label or "A"))
                            emit('        </direction-type>\n')
                        elseif rm.type == "segno" then
                            emit('          <segno/>\n')
                            emit('        </direction-type>\n')
                        elseif rm.type == "coda" then
                            emit('          <coda/>\n')
                            emit('        </direction-type>\n')
                        elseif rm.type == "dc" or rm.type == "dc_al_fine" then
                            emit('          <words font-weight="bold">%s</words>\n', xml_escape(rm.label or "D.C."))
                            emit('        </direction-type>\n')
                            emit('        <sound dacapo="yes"/>\n')
                        elseif rm.type == "ds" or rm.type == "ds_al_coda" then
                            emit('          <words font-weight="bold">%s</words>\n', xml_escape(rm.label or "D.S."))
                            emit('        </direction-type>\n')
                            emit('        <sound dalsegno="yes"/>\n')
                        elseif rm.type == "fine" then
                            emit('          <words font-weight="bold">Fine</words>\n')
                            emit('        </direction-type>\n')
                            emit('        <sound fine="yes"/>\n')
                        else
                            emit('          <rehearsal>%s</rehearsal>\n', xml_escape(rm.label or "A"))
                            emit('        </direction-type>\n')
                        end
                        emit('      </direction>\n')
                    end
                end
            end

            -- ------------------------------------------------------------------
            -- Chord & Scale Lane items (<harmony>)
            -- ------------------------------------------------------------------
            if options.include_chords ~= false and pi == 1 and state.chord_items then
                for _, chord in ipairs(state.chord_items) do
                    if chord.start_qn >= m_start_qn - 0.001 and chord.start_qn < m_end_qn - 0.001 then
                        local root_step = "C"
                        local root_alter = 0
                        if chord.root_name then
                            local r_step = chord.root_name:sub(1, 1):upper()
                            local r_acc = chord.root_name:sub(2)
                            root_step = r_step
                            if r_acc == "#" then root_alter = 1
                            elseif r_acc == "b" then root_alter = -1 end
                        end
                        local kind_val, kind_text = map_chord_kind(chord.quality or chord.scale_type)

                        emit('      <harmony>\n')
                        emit('        <root>\n')
                        emit('          <root-step>%s</root-step>\n', root_step)
                        if root_alter ~= 0 then
                            emit('          <root-alter>%d</root-alter>\n', root_alter)
                        end
                        emit('        </root>\n')
                        if kind_text and kind_text ~= "" then
                            emit('        <kind text="%s">%s</kind>\n', xml_escape(kind_text), kind_val)
                        else
                            emit('        <kind>%s</kind>\n', kind_val)
                        end
                        emit('      </harmony>\n')
                    end
                end
            end

            -- ------------------------------------------------------------------
            -- Text Items in this measure (<direction><words>)
            -- ------------------------------------------------------------------
            if options.include_text_items ~= false and state.text_items then
                for _, ti in ipairs(state.text_items) do
                    local matches_trk = (not ti.track_guid) or (ti.track_guid == trk_guid) or (pi == 1 and not ti.track_guid)
                    if matches_trk and ti.qn >= m_start_qn - 0.001 and ti.qn < m_end_qn - 0.001 then
                        local ti_clean = ti.text and tostring(ti.text):lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
                        local is_redundant_legato = (ti_clean == "legato" or ti_clean == "slur" or ti_clean:match("^legato$") or ti_clean:match("^slur$"))
                        if not is_redundant_legato then
                            emit('      <direction placement="above">\n')
                            emit('        <direction-type>\n')
                            local font_size = ti.font_size or 14
                            local font_style = (ti.style == "italic" or ti.style == "bold_italic") and ' font-style="italic"' or ''
                            local font_weight = (ti.style == "bold" or ti.style == "bold_italic") and ' font-weight="bold"' or ''
                            emit('          <words font-size="%.1f"%s%s>%s</words>\n', font_size, font_style, font_weight, xml_escape(ti.text))
                            emit('        </direction-type>\n')
                            emit('      </direction>\n')
                        end
                    end
                end
            end

            -- ------------------------------------------------------------------
            -- Dynamics in this measure (<direction><dynamics>)
            -- ------------------------------------------------------------------
            if options.include_dynamics ~= false and tracks_dynamics[pi] then
                for _, dyn in ipairs(tracks_dynamics[pi]) do
                    if dyn and dyn.qn and dyn.qn >= m_start_qn - 0.001 and dyn.qn < m_end_qn - 0.001 then
                        local tag = (dyn.label or "f"):lower()
                        local offset_div = math.floor((dyn.qn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                        emit('      <direction placement="below">\n')
                        emit('        <direction-type>\n')
                        local valid_tags = {
                            p=true, pp=true, ppp=true, pppp=true,
                            f=true, ff=true, fff=true, ffff=true,
                            mp=true, mf=true, sfz=true, sfp=true, fp=true, rfz=true, fz=true, sf=true, sffz=true
                        }
                        if valid_tags[tag] then
                            emit('          <dynamics><%s/></dynamics>\n', tag)
                        else
                            emit('          <dynamics><other-dynamics>%s</other-dynamics></dynamics>\n', xml_escape(tag))
                        end
                        emit('        </direction-type>\n')
                        if offset_div > 0 then
                            emit('        <offset>%d</offset>\n', offset_div)
                        end
                        if trk_clef == "grand" then
                            emit('        <staff>1</staff>\n')
                        end
                        emit('      </direction>\n')
                    end
                end
            end

            -- Textual dynamic markings (cresc., dim. etc.)
            if options.include_dynamics ~= false and state.dynamic_texts then
                for _, dt in ipairs(state.dynamic_texts) do
                    local matches = (not dt.track_guid or dt.track_guid == "" or dt.track_guid == trk_guid)
                    if matches and dt.start_qn >= m_start_qn - 0.001 and dt.start_qn < m_end_qn - 0.001 then
                        local offset_div = math.floor((dt.start_qn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                        emit('      <direction placement="below">\n')
                        emit('        <direction-type>\n')
                        emit('          <words font-style="italic">%s</words>\n', xml_escape(dt.text or "cresc."))
                        emit('        </direction-type>\n')
                        if offset_div > 0 then
                            emit('        <offset>%d</offset>\n', offset_div)
                        end
                        if trk_clef == "grand" then
                            emit('        <staff>1</staff>\n')
                        end
                        emit('      </direction>\n')
                    end
                end
            end

            -- ------------------------------------------------------------------
            -- Hairpins (<wedge>)
            -- ------------------------------------------------------------------
            if options.include_hairpins ~= false and state.hairpins then
                for _, hp in ipairs(state.hairpins) do
                    local matches = (not hp.track_guid or hp.track_guid == "" or hp.track_guid == trk_guid)
                    if matches then
                        local hp_type = (hp.type == "crescendo" or hp.type == "cresc") and "crescendo" or "diminuendo"
                        
                        -- Hairpin START in this measure
                        if hp.start_qn >= m_start_qn - 0.001 and hp.start_qn < m_end_qn - 0.001 then
                            local offset_div = math.floor((hp.start_qn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                            emit('      <direction placement="below">\n')
                            emit('        <direction-type>\n')
                            emit('          <wedge type="%s"/>\n', hp_type)
                            emit('        </direction-type>\n')
                            if offset_div > 0 then
                                emit('        <offset>%d</offset>\n', offset_div)
                            end
                            if trk_clef == "grand" then
                                emit('        <staff>1</staff>\n')
                            end
                            emit('      </direction>\n')
                        end

                        -- Hairpin STOP in this measure
                        -- Case 1: Stop falls strictly inside measure m
                        -- Case 2: Stop falls on the downbeat of measure m (and hairpin began in an earlier measure)
                        -- Case 3: Final measure of the score and hairpin reaches or exceeds measure end
                        local should_stop = false
                        local stop_offset_div = 0

                        if hp.end_qn > m_start_qn + 0.05 and hp.end_qn < m_end_qn - 0.05 then
                            should_stop = true
                            stop_offset_div = math.floor((hp.end_qn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                        elseif math.abs(hp.end_qn - m_start_qn) <= 0.05 and m > 1 and hp.start_qn < m_start_qn - 0.05 then
                            should_stop = true
                            stop_offset_div = 0
                        elseif m == total_measures and hp.end_qn >= m_end_qn - 0.05 and hp.start_qn < m_end_qn then
                            should_stop = true
                            stop_offset_div = m_dur_div
                        end

                        if should_stop then
                            emit('      <direction placement="below">\n')
                            emit('        <direction-type>\n')
                            emit('          <wedge type="stop"/>\n')
                            emit('        </direction-type>\n')
                            if stop_offset_div > 0 then
                                emit('        <offset>%d</offset>\n', stop_offset_div)
                            end
                            if trk_clef == "grand" then
                                emit('        <staff>1</staff>\n')
                            end
                            emit('      </direction>\n')
                        end
                    end
                end
            end

            -- ------------------------------------------------------------------
            -- Octave Lines (<octave-shift>)
            -- ------------------------------------------------------------------
            if options.include_octaves ~= false and state.octave_lines then
                for _, oct in ipairs(state.octave_lines) do
                    local matches = (not oct.track_guid or oct.track_guid == "" or oct.track_guid == trk_guid)
                    if matches then
                        local shift_size = (math.abs(oct.shift or 12) >= 24) and 15 or 8
                        local shift_type = (oct.shift and oct.shift < 0) and "down" or "up"
                        if oct.start_qn >= m_start_qn - 0.001 and oct.start_qn < m_end_qn - 0.001 then
                            local offset_div = math.floor((oct.start_qn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                            emit('      <direction placement="above">\n')
                            emit('        <direction-type>\n')
                            emit('          <octave-shift type="%s" size="%d"/>\n', shift_type, shift_size)
                            emit('        </direction-type>\n')
                            if offset_div > 0 then
                                emit('        <offset>%d</offset>\n', offset_div)
                            end
                            emit('      </direction>\n')
                        end
                        if oct.end_qn >= m_start_qn - 0.001 and oct.end_qn < m_end_qn - 0.001 then
                            local offset_div = math.floor((oct.end_qn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                            emit('      <direction placement="above">\n')
                            emit('        <direction-type>\n')
                            emit('          <octave-shift type="stop"/>\n')
                            emit('        </direction-type>\n')
                            if offset_div > 0 then
                                emit('        <offset>%d</offset>\n', offset_div)
                            end
                            emit('      </direction>\n')
                        end
                    end
                end
            end

            -- ------------------------------------------------------------------
            -- Pedals (<pedal>)
            -- ------------------------------------------------------------------
            if options.include_pedals ~= false and state.pedal_marks then
                for _, ped in ipairs(state.pedal_marks) do
                    local matches = (not ped.track_guid or ped.track_guid == "" or ped.track_guid == trk_guid)
                    if matches then
                        if ped.start_qn >= m_start_qn - 0.001 and ped.start_qn < m_end_qn - 0.001 then
                            local offset_div = math.floor((ped.start_qn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                            emit('      <direction placement="below">\n')
                            emit('        <direction-type>\n')
                            emit('          <pedal type="start"/>\n')
                            emit('        </direction-type>\n')
                            if offset_div > 0 then
                                emit('        <offset>%d</offset>\n', offset_div)
                            end
                            emit('      </direction>\n')
                        end
                        if ped.end_qn >= m_start_qn - 0.001 and ped.end_qn < m_end_qn - 0.001 then
                            local offset_div = math.floor((ped.end_qn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                            emit('      <direction placement="below">\n')
                            emit('        <direction-type>\n')
                            emit('          <pedal type="stop"/>\n')
                            emit('        </direction-type>\n')
                            if offset_div > 0 then
                                emit('        <offset>%d</offset>\n', offset_div)
                            end
                            emit('      </direction>\n')
                        end
                    end
                end
            end

            -- ------------------------------------------------------------------
            -- Notes in this measure (Sliced strictly at bar boundaries with Ties)
            -- ------------------------------------------------------------------
            local m_notes = {}
            for _, n in ipairs(notes) do
                local n_start = tonumber(n.start_qn) or 0.0
                local n_dur = tonumber(n.dur_qn) or (n.end_qn and (n.end_qn - n_start)) or 1.0
                local n_end = n_start + n_dur
                if n_start < m_end_qn - 0.005 and n_end > m_start_qn + 0.005 then
                    local seg_start = math.max(n_start, m_start_qn)
                    local seg_end = math.min(n_end, m_end_qn)
                    local seg_dur = seg_end - seg_start
                    if seg_dur > 0.01 then
                        local orig_n = n.orig or n
                        local pref_acc = n.accidental
                        if not pref_acc and state and Engraver and Engraver.get_note_preferred_accidental then
                            pref_acc = Engraver.get_note_preferred_accidental({ orig = orig_n }, state)
                        end
                        local is_first_slice = (math.abs(seg_start - n_start) < 0.01)
                        local is_last_slice = (math.abs(seg_end - n_end) < 0.01)

                        local is_user_tie_start = (n.is_tied_master == true)
                        local is_user_tie_stop  = (n.is_tied_slave == true)

                        local seg_n = {
                            pitch = n.pitch or 60,
                            start_qn = seg_start,
                            dur_qn = seg_dur,
                            end_qn = seg_end,
                            chan = n.chan or 0,
                            vel = n.vel or 90,
                            accidental = pref_acc,
                            articulation = n.articulation,
                            is_auto_return = n.is_auto_return or (orig_n and orig_n.is_auto_return),
                            tie_stop = (n_start < m_start_qn - 0.01) or (is_first_slice and is_user_tie_stop),
                            tie_start = (n_end > m_end_qn + 0.01) or (is_last_slice and is_user_tie_start),
                            slur_starts = is_first_slice and n.slur_starts or nil,
                            slur_stops  = is_last_slice and n.slur_stops or nil,
                            gliss_starts = is_first_slice and n.gliss_starts or nil,
                            gliss_stops  = is_last_slice and n.gliss_stops or nil,
                            slide_starts = is_first_slice and n.slide_starts or nil,
                            slide_stops  = is_last_slice and n.slide_stops or nil,
                            orig = n
                        }
                        local sub_segs = split_measure_note_segments(seg_n, m_start_qn, bpi)
                        for _, sn_part in ipairs(sub_segs) do
                            table.insert(m_notes, sn_part)
                        end
                    end
                end
            end

            -- Sort notes by onset, then pitch
            table.sort(m_notes, function(a, b)
                if math.abs(a.start_qn - b.start_qn) > 0.001 then
                    return a.start_qn < b.start_qn
                end
                return (a.pitch or 60) < (b.pitch or 60)
            end)

            -- ------------------------------------------------------------------
            -- Non-standard Articulations exported as Text Elements (<direction><words>)
            -- ------------------------------------------------------------------
            local text_arts_by_qn = {}
            for _, n in ipairs(m_notes) do
                if n.articulation and not n.is_auto_return and not is_standard_musicxml_articulation(n.articulation) then
                    local a_clean = tostring(n.articulation):lower():gsub("^%s+", ""):gsub("%s+$", "")
                    if a_clean ~= "legato" and not a_clean:match("^legato") and a_clean ~= "slur" and not a_clean:match("^slur") and not a_clean:match("^tie") then
                        local q = math.floor(n.start_qn * 1000 + 0.5) / 1000
                        if not text_arts_by_qn[q] then text_arts_by_qn[q] = n.articulation end
                    end
                end
            end
            if tracks_articulations[pi] then
                for _, a in ipairs(tracks_articulations[pi]) do
                    if not a.is_auto_return and not a.is_slur and not a.is_slur_pc and (a.qn and a.qn >= m_start_qn - 0.001 and a.qn < m_end_qn - 0.001) then
                        local lbl = a.label or a.name or a.art
                        if lbl and not is_standard_musicxml_articulation(lbl) then
                            local l_clean = tostring(lbl):lower():gsub("^%s+", ""):gsub("%s+$", "")
                            if l_clean ~= "legato" and not l_clean:match("^legato") and l_clean ~= "slur" and not l_clean:match("^slur") and not l_clean:match("^tie") then
                                local q = math.floor(a.qn * 1000 + 0.5) / 1000
                                if not text_arts_by_qn[q] then text_arts_by_qn[q] = lbl end
                            end
                        end
                    end
                end
            end

            local sorted_art_qns = {}
            for q, _ in pairs(text_arts_by_qn) do table.insert(sorted_art_qns, q) end
            table.sort(sorted_art_qns)

            for _, aqn in ipairs(sorted_art_qns) do
                local art_text = text_arts_by_qn[aqn]
                local offset_div = math.floor((aqn - m_start_qn) * DIVISIONS_PER_QN + 0.5)
                emit('      <direction placement="above">\n')
                emit('        <direction-type>\n')
                emit('          <words font-style="italic">%s</words>\n', xml_escape(art_text))
                emit('        </direction-type>\n')
                if offset_div > 0 then
                    emit('        <offset>%d</offset>\n', offset_div)
                end
                if trk_clef == "grand" then
                    emit('        <staff>1</staff>\n')
                end
                emit('      </direction>\n')
            end

            local m_dur_div = math.floor(bpi * DIVISIONS_PER_QN + 0.5)

            if trk_clef == "grand" then
                -- Partition into Staff 1 (Treble, pitch >= 60) and Staff 2 (Bass, pitch < 60)
                local s1_notes = {}
                local s2_notes = {}
                for _, n in ipairs(m_notes) do
                    local staff_pref = n.staff or (state and state.note_staff_assignments and (state.note_staff_assignments[n.key or (n.get_key and n:get_key())]))
                    if staff_pref == "treble" or (not staff_pref and (n.pitch or 60) >= 60) then
                        table.insert(s1_notes, n)
                    else
                        table.insert(s2_notes, n)
                    end
                end

                local s1_voices = split_notes_into_monophonic_voices(s1_notes, 1)
                local s1_active = {}
                for v, _ in pairs(s1_voices) do table.insert(s1_active, v) end
                table.sort(s1_active)

                if #s1_active == 0 then
                    emit('      <note>\n')
                    emit('        <rest/>\n')
                    emit('        <duration>%d</duration>\n', m_dur_div)
                    emit('        <voice>1</voice>\n')
                    emit('        <staff>1</staff>\n')
                    emit('      </note>\n')
                else
                    for vi, v in ipairs(s1_active) do
                        if vi > 1 then
                            emit('      <backup>\n')
                            emit('        <duration>%d</duration>\n', m_dur_div)
                            emit('      </backup>\n')
                        end
                        emit_voice_notes(emit, s1_voices[v], v, 1, m_start_qn, m_end_qn, key_idx, "treble", bpi)
                    end
                end

                -- Backup to beginning of measure for Staff 2
                emit('      <backup>\n')
                emit('        <duration>%d</duration>\n', m_dur_div)
                emit('      </backup>\n')

                local s2_voices = split_notes_into_monophonic_voices(s2_notes, 2)
                local s2_active = {}
                for v, _ in pairs(s2_voices) do table.insert(s2_active, v) end
                table.sort(s2_active)

                if #s2_active == 0 then
                    emit('      <note>\n')
                    emit('        <rest/>\n')
                    emit('        <duration>%d</duration>\n', m_dur_div)
                    emit('        <voice>2</voice>\n')
                    emit('        <staff>2</staff>\n')
                    emit('      </note>\n')
                else
                    for vi, v in ipairs(s2_active) do
                        if vi > 1 then
                            emit('      <backup>\n')
                            emit('        <duration>%d</duration>\n', m_dur_div)
                            emit('      </backup>\n')
                        end
                        emit_voice_notes(emit, s2_voices[v], v, 2, m_start_qn, m_end_qn, key_idx, "bass", bpi)
                    end
                end

            else
                -- Single Staff (Treble, Bass, Alto, Tenor)
                -- Monophonic voices splitting (prevents whole note and half note from colliding in the same voice!)
                local voice_map = split_notes_into_monophonic_voices(m_notes, 1)

                local active_voices = {}
                for v, _ in pairs(voice_map) do
                    table.insert(active_voices, v)
                end
                table.sort(active_voices)

                if #active_voices == 0 then
                    emit('      <note>\n')
                    emit('        <rest/>\n')
                    emit('        <duration>%d</duration>\n', m_dur_div)
                    emit('        <voice>1</voice>\n')
                    emit('      </note>\n')
                else
                    for vi, v in ipairs(active_voices) do
                        if vi > 1 then
                            emit('      <backup>\n')
                            emit('        <duration>%d</duration>\n', m_dur_div)
                            emit('      </backup>\n')
                        end
                        local v_notes = voice_map[v]
                        emit_voice_notes(emit, v_notes, v, nil, m_start_qn, m_end_qn, key_idx, trk_clef, bpi)
                    end
                end
            end

            emit('    </measure>\n')
        end

        emit('  </part>\n')
    end

    emit('</score-partwise>\n')

    -- Write file to disk
    local content = table.concat(xml)
    local f, err = io.open(out_path, "wb")
    if not f then
        return false, string.format("Failed to open file for writing: %s", tostring(err))
    end
    f:write(content)
    f:close()

    return true, out_path, total_measures, #proj_tracks
end

return MusicXmlExportService

-- ==============================================================================
-- REAPER Native Notator - Class: MidiNote (OOP)
-- Represents a MIDI note in the project with synchronized properties
-- ==============================================================================

local MidiNote = {}
MidiNote.__index = MidiNote

function MidiNote.new(data)
    local self = setmetatable({}, MidiNote)
    self.idx          = data.idx or 0
    self.pitch        = data.pitch or 60
    self.start_qn     = data.start_qn or 0.0
    self.end_qn       = data.end_qn or (self.start_qn + 1.0)
    self.dur_qn       = data.dur_qn or (self.end_qn - self.start_qn)
    self.vel          = data.vel or 96
    self.chan         = data.chan or 0
    self.take         = data.take
    self.item         = data.item
    self.track        = data.track
    self.articulation = data.articulation
    self.stem_dir     = data.stem_dir
    self.arpeggio     = data.arpeggio
    self.key          = self:get_key()
    return self
end

function MidiNote:get_key()
    local it_str = tostring(self.item or "0")
    local tk_str = tostring(self.take or "0")
    return string.format("%s_%s_%.3f_%d_%d", it_str, tk_str, self.start_qn, self.pitch, self.chan or 0)
end

function MidiNote:matches_reaper(r_pitch, r_sppq)
    if self.pitch ~= r_pitch then return false end
    if not self.take or not reaper.ValidatePtr(self.take, "MediaItem_Take*") then return false end
    local sppq = reaper.MIDI_GetPPQPosFromProjQN(self.take, self.start_qn)
    return math.abs(sppq - r_sppq) < 15
end

function MidiNote:transpose(semitones)
    local new_p = math.max(0, math.min(127, self.pitch + semitones))
    self.pitch = new_p
    self.key = self:get_key()
    return new_p
end

return MidiNote

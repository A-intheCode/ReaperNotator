-- ==============================================================================
-- REAPER Native Notator - Class: RehearsalMark (OOP)
-- Manages auto-sequencing rehearsal marks (A, B, C...) and navigation marks
-- (D.C., D.S., Segno, Coda, Fine) positioned between Chord Track and Bar Numbers
-- ==============================================================================

local RehearsalMark = {}
RehearsalMark.__index = RehearsalMark

function RehearsalMark.new(data)
    local self = setmetatable({}, RehearsalMark)
    self.id          = data.id or string.format("rm_%d_%d", os.time(), math.random(1000, 9999))
    self.measure     = tonumber(data.measure) or 0
    self.qn          = tonumber(data.qn) or 0.0
    self.type        = data.type or "letter" -- "letter", "number", "custom", "dc", "ds", "segno", "coda", "fine"
    self.custom_text = data.custom_text or ""
    self.label       = data.label or "A"
    return self
end

function RehearsalMark:to_table()
    return {
        id          = self.id,
        measure     = self.measure,
        qn          = self.qn,
        type        = self.type,
        custom_text = self.custom_text,
        label       = self.label
    }
end

function RehearsalMark.from_table(t)
    return RehearsalMark.new(t)
end

return RehearsalMark

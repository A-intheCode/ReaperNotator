-- ==============================================================================
-- REAPER Native Notator - Class: TempoMarker (OOP)
-- Manages absolute tempi (Andante 80, Allegro 140) and gradual tempo changes
-- (accel., rall., rit.) with duration range (start_qn, end_qn) and handles
-- ==============================================================================

local TempoMarker = {}
TempoMarker.__index = TempoMarker

function TempoMarker.new(data)
    local self = setmetatable({}, TempoMarker)
    self.id         = data.id or string.format("tempo_%d_%d", os.time(), math.random(1000, 9999))
    self.type       = data.type or "absolute" -- "absolute" | "gradual"
    self.label      = (data.label ~= nil) and data.label or "Allegro"
    self.modifier   = data.modifier or ""     -- "", "poco", "molto"
    self.bpm        = data.bpm or 120
    self.target_bpm = data.target_bpm or nil
    self.start_qn   = data.start_qn or 0.0
    self.end_qn     = data.end_qn or (self.start_qn + 4.0) -- Default 1 measure (4 QN)
    self.linear     = (data.linear ~= false)  -- For REAPER continuous linear transition
    self.custom_bpm_only = (data.custom_bpm_only == true) or (self.label == "")
    self.custom_target_bpm = (data.custom_target_bpm == true)
    return self
end

function TempoMarker:get_display_text()
    if self.type == "gradual" then
        if self.modifier and #self.modifier > 0 then
            return string.format("%s %s", self.modifier, self.label)
        else
            return self.label
        end
    else
        if self.custom_bpm_only or not self.label or self.label == "" then
            return string.format("♩ = %d", math.floor(self.bpm or 120))
        else
            return string.format("%s  (♩ = %d)", self.label, math.floor(self.bpm or 120))
        end
    end
end

function TempoMarker:to_table()
    return {
        id                = self.id,
        type              = self.type,
        label             = self.label,
        modifier          = self.modifier,
        bpm               = self.bpm,
        target_bpm        = self.target_bpm,
        start_qn          = self.start_qn,
        end_qn            = self.end_qn,
        linear            = self.linear,
        custom_bpm_only   = self.custom_bpm_only,
        custom_target_bpm = self.custom_target_bpm
    }
end

function TempoMarker.from_table(t)
    return TempoMarker.new(t)
end

return TempoMarker


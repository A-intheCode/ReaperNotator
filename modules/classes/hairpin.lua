-- ==============================================================================
-- REAPER Native Notator - Class: Hairpin
-- Represents a Crescendo (<) or Decrescendo (>) dynamic ramp with dual handles
-- ==============================================================================

local Hairpin = {}
Hairpin.__index = Hairpin

function Hairpin.new(data)
    local self = setmetatable({}, Hairpin)
    self.id         = data.id or string.format("hp_%d_%d", math.floor(reaper.time_precise() * 1000), math.random(1000, 9999))
    self.track_guid = data.track_guid or ""
    self.type       = data.type or "crescendo" -- "crescendo" | "decrescendo"
    self.start_qn   = data.start_qn or 0.0
    self.end_qn     = data.end_qn or (self.start_qn + 4.0)
    self.start_dyn  = data.start_dyn -- optional, e.g. "p"
    self.end_dyn    = data.end_dyn   -- optional, e.g. "f"
    self.staff      = data.staff     -- optional: "treble" | "bass" | "mid"
    return self
end

function Hairpin:clone()
    return Hairpin.new({
        id         = self.id,
        track_guid = self.track_guid,
        type       = self.type,
        start_qn   = self.start_qn,
        end_qn     = self.end_qn,
        start_dyn  = self.start_dyn,
        end_dyn    = self.end_dyn,
        staff      = self.staff
    })
end

function Hairpin:get_display_name()
    if self.type == "crescendo" then
        return "Crescendo (<)"
    else
        return "Decrescendo (>)"
    end
end

return Hairpin


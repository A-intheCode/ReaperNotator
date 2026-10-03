-- ==============================================================================
-- REAPER Native Notator - Class: OctaveLine
-- Represents an Ottava / Octave bracket (8va, 15ma, 22ma, 8vb, 15mb, 22mb, loco)
-- ==============================================================================

local OctaveLine = {}
OctaveLine.__index = OctaveLine

function OctaveLine.new(data)
    local self = setmetatable({}, OctaveLine)
    self.id         = data.id or string.format("oct_%d_%d", math.floor(reaper.time_precise() * 1000), math.random(1000, 9999))
    self.track_guid = data.track_guid or ""
    self.type       = data.type or "8va" -- "8va" | "15ma" | "22ma" | "8vb" | "15mb" | "22mb" | "loco"
    self.start_qn   = data.start_qn or 0.0
    self.end_qn     = data.end_qn or (self.start_qn + 4.0)
    return self
end

function OctaveLine:clone()
    return OctaveLine.new({
        id         = self.id,
        track_guid = self.track_guid,
        type       = self.type,
        start_qn   = self.start_qn,
        end_qn     = self.end_qn
    })
end

return OctaveLine


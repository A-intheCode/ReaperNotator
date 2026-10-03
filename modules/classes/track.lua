-- ==============================================================================
-- REAPER Native Notator - Class: TrackStaff (OOP)
-- Manages a musical staff / track in multitrack scores
-- ==============================================================================

local TrackStaff = {}
TrackStaff.__index = TrackStaff

function TrackStaff.new(data)
    local self = setmetatable({}, TrackStaff)
    self.track    = data.track
    self.guid     = data.guid or "default"
    self.idx      = data.idx or 1
    self.name     = data.name or "Track"
    self.col      = data.col or 0
    self.items    = data.items or {}
    self.notes    = data.notes or {}
    self.dynamics = data.dynamics or {}
    self.clef     = data.clef or "treble"
    self.is_grand = (self.clef == "grand")
    self.band_h   = data.band_h or (self.is_grand and 210 or 135)
    return self
end

return TrackStaff

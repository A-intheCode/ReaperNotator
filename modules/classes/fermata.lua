-- ==============================================================================
-- REAPER Native Notator - Class: Fermata (OOP)
-- Manages score-wide vertical fermatas with tempomap coupling & dual-persistence
-- ==============================================================================

local Fermata = {}
Fermata.__index = Fermata

function Fermata.new(data)
    local self = setmetatable({}, Fermata)
    self.id            = data.id or string.format("ferm_%d_%d", os.time(), math.random(1000, 9999))
    self.qn            = tonumber(data.qn) or 0.0
    self.measure       = tonumber(data.measure) or 0
    self.beat_rel      = tonumber(data.beat_rel) or 0.0
    self.type          = data.type or "standard" -- "standard", "short", "long", "very_long"
    self.hold_factor   = tonumber(data.hold_factor) or 1.5 -- Slowdown factor, e.g. 1.5x (BPM = orig_bpm / 1.5)
    self.playback_mode = data.playback_mode or "tempo_dip" -- "tempo_dip" | "visual_only"
    return self
end

function Fermata:to_table()
    return {
        id            = self.id,
        qn            = self.qn,
        measure       = self.measure,
        beat_rel      = self.beat_rel,
        type          = self.type,
        hold_factor   = self.hold_factor,
        playback_mode = self.playback_mode
    }
end

function Fermata.from_table(t)
    return Fermata.new(t)
end

return Fermata

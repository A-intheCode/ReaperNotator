-- ==============================================================================
-- REAPER Native Notator - Class: ChordItem
-- Represents a Chord / Scale block on the top chord lane [ - - - - ]
-- with scalable duration range, lead-sheet text, root, and scale type
-- ==============================================================================

local ChordItem = {}
ChordItem.__index = ChordItem

function ChordItem.new(data)
    local self = setmetatable({}, ChordItem)
    self.id         = data.id or string.format("chd_%d_%d", math.floor(reaper.time_precise() * 1000), math.random(1000, 9999))
    self.text       = data.text or "C"
    self.start_qn   = data.start_qn or 0.0
    self.end_qn     = data.end_qn or (self.start_qn + 4.0)
    self.root       = data.root or 0
    self.scale_type = data.scale_type or "major"
    return self
end

function ChordItem:clone()
    return ChordItem.new({
        id         = self.id,
        text       = self.text,
        start_qn   = self.start_qn,
        end_qn     = self.end_qn,
        root       = self.root,
        scale_type = self.scale_type
    })
end

function ChordItem:get_display_name()
    local dur = math.max(0.25, self.end_qn - self.start_qn)
    return string.format("%s (%.1f QN)", self.text, dur)
end

return ChordItem

-- ==============================================================================
-- REAPER Native Notator - Class: TextItem
-- Freely movable text annotation attached to a track timeline position.
-- ==============================================================================

local TextItem = {}
TextItem.__index = TextItem

function TextItem.new(data)
    local self = setmetatable({}, TextItem)
    self.id         = (data and data.id) or string.format("txt_%d_%d", math.floor(reaper.time_precise() * 1000), math.random(1000, 9999))
    self.track_guid = (data and data.track_guid) or ""
    self.qn         = tonumber(data and data.qn) or 0.0
    self.offset_y   = tonumber(data and data.offset_y) or 32.0 -- Pixel offset below the staff bottom edge
    self.text       = tostring((data and data.text) or "Text")
    self.style      = tostring((data and data.style) or "italic") -- "italic" | "bold" | "bold_italic" | "regular"
    self.font_size  = tonumber(data and data.font_size) or 16.0
    self.placement  = (data and data.placement) or "below" -- "above" | "below"
    return self
end

function TextItem:clone()
    return TextItem.new({
        id         = self.id,
        track_guid = self.track_guid,
        qn         = self.qn,
        offset_y   = self.offset_y,
        text       = self.text,
        style      = self.style,
        font_size  = self.font_size,
        placement  = self.placement
    })
end

return TextItem

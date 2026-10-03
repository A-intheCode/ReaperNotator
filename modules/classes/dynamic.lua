-- ==============================================================================
-- REAPER Native Notator - Class: DynamicMarker (OOP)
-- Manages dynamic events (Type 15 Sysex/Text & CC1/CC11)
-- ==============================================================================

local DynamicMarker = {}
DynamicMarker.__index = DynamicMarker

function DynamicMarker.new(data)
    local self = setmetatable({}, DynamicMarker)
    self.take       = data.take
    self.item       = data.item
    self.track      = data.track
    self.ppq        = data.ppq or 0
    self.qn         = data.qn or 0.0
    self.label      = data.label or "mf"
    self.c1         = data.c1 or 75
    self.c11        = data.c11 or 80
    self.type15_idx = data.type15_idx or 0
    self.base_y     = data.base_y or 0
    self.key        = self:get_key()
    return self
end

function DynamicMarker:get_key()
    local trk = self.track
    if (not trk or not reaper.ValidatePtr(trk, "MediaTrack*")) and self.item and reaper.ValidatePtr(self.item, "MediaItem*") then
        trk = reaper.GetMediaItem_Track(self.item)
    end
    if (not trk or not reaper.ValidatePtr(trk, "MediaTrack*")) and self.take and reaper.ValidatePtr(self.take, "MediaItem_Take*") then
        local itm = reaper.GetMediaItemTake_Item(self.take)
        if itm and reaper.ValidatePtr(itm, "MediaItem*") then
            trk = reaper.GetMediaItem_Track(itm)
        end
    end
    local trk_id = (trk and reaper.ValidatePtr(trk, "MediaTrack*")) and reaper.GetTrackGUID(trk) or tostring(self.track or "no_track")
    local tk_id = tostring(self.take or "no_take")
    if self.take and reaper.ValidatePtr(self.take, "MediaItem_Take*") and reaper.BR_GetMediaItemTakeGUID then
        tk_id = reaper.BR_GetMediaItemTakeGUID(self.take)
    end
    return string.format("%s_%s_%.3f_%s", trk_id, tk_id, self.qn or 0.0, self.label or "")
end

return DynamicMarker

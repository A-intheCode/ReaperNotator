-- ==============================================================================
-- REAPER Native Notator - Class: MidiItem (OOP)
-- Manages REAPER MediaItems, boundaries, and loop-free sizing
-- ==============================================================================

local MidiItem = {}
MidiItem.__index = MidiItem

function MidiItem.new(data)
    local self = setmetatable({}, MidiItem)
    self.item     = data.item
    self.take     = data.take
    self.idx      = data.idx or 0
    self.pos      = data.pos or 0.0
    self.len      = data.len or 0.0
    self.start_qn = data.start_qn or 0.0
    self.end_qn   = data.end_qn or 0.0
    self.col      = data.col or 0
    self.name     = data.name or "MIDI Item"
    self.clef     = data.clef or nil
    return self
end

function MidiItem:set_extents(new_start_qn, new_end_qn)
    if not self.item or not reaper.ValidatePtr(self.item, "MediaItem*") then return false end
    reaper.SetMediaItemInfo_Value(self.item, "B_LOOPSRC", 0)
    reaper.MIDI_SetItemExtents(self.item, new_start_qn, new_end_qn)
    reaper.SetMediaItemInfo_Value(self.item, "B_LOOPSRC", 0)
    self.start_qn = new_start_qn
    self.end_qn = new_end_qn
    self.pos = reaper.TimeMap2_QNToTime(0, new_start_qn)
    local end_time = reaper.TimeMap2_QNToTime(0, new_end_qn)
    self.len = end_time - self.pos
    return true
end

function MidiItem:contains_qn(qn)
    return qn >= (self.start_qn - 0.005) and qn <= (self.end_qn + 0.005)
end

function MidiItem:set_selected(sel)
    if not self.item or not reaper.ValidatePtr(self.item, "MediaItem*") then return end
    reaper.SetMediaItemSelected(self.item, sel and true or false)
end

return MidiItem

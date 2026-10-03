-- ==============================================================================
-- REAPER Native Notator - Class: DynamicText
-- Represents a textual Crescendo or Diminuendo dynamic tag (cresc., dim. etc.)
-- with scalable duration range, text pattern, line pattern, and CC curve pattern
-- ==============================================================================

local DynamicText = {}
DynamicText.__index = DynamicText

function DynamicText.new(data)
    local self = setmetatable({}, DynamicText)
    self.id            = data.id or string.format("dtxt_%d_%d", math.floor(reaper.time_precise() * 1000), math.random(1000, 9999))
    self.track_guid    = data.track_guid or ""
    local txt = data.text
    local dtype = data.type
    if not dtype then
        if txt and (txt:lower():match("dim") or txt:lower():match("decresc")) then
            dtype = "diminuendo"
        else
            dtype = "crescendo"
        end
    end
    self.type          = dtype
    self.text          = txt or (self.type == "crescendo" and "cresc." or "dim.")
    self.start_qn      = data.start_qn or 0.0
    self.end_qn        = data.end_qn or (self.start_qn + 4.0)
    self.line_pattern  = data.line_pattern or "none"    -- "none" | "dashed" | "dotted"
    self.curve_pattern = data.curve_pattern or "linear" -- "linear" | "exponential" | "s_curve"
    self.start_dyn     = data.start_dyn -- optional, e.g. "p"
    self.end_dyn       = data.end_dyn   -- optional, e.g. "f"
    self.staff         = data.staff     -- optional: "treble" | "bass" | "mid"
    return self
end

function DynamicText:clone()
    return DynamicText.new({
        id            = self.id,
        track_guid    = self.track_guid,
        type          = self.type,
        text          = self.text,
        start_qn      = self.start_qn,
        end_qn        = self.end_qn,
        line_pattern  = self.line_pattern,
        curve_pattern = self.curve_pattern,
        start_dyn     = self.start_dyn,
        end_dyn       = self.end_dyn,
        staff         = self.staff
    })
end

function DynamicText:get_display_name()
    local dir_sym = (self.type == "crescendo") and "↗" or "↘"
    return string.format("%s %s (%.1f QN)", dir_sym, self.text, self.end_qn - self.start_qn)
end

return DynamicText

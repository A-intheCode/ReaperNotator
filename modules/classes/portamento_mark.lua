-- ==============================================================================
-- REAPER Native Notator - Class: PortamentoMark
-- Represents a Portamento line connecting two noteheads with configurable
-- MIDI playback control (CC64 Hold Blend, CC34, CC5, CC65).
-- ==============================================================================

local PortamentoMark = {}
PortamentoMark.__index = PortamentoMark

function PortamentoMark.new(data)
    local self = setmetatable({}, PortamentoMark)
    self.id         = data.id or string.format("port_%d_%d", math.floor(reaper.time_precise() * 1000), math.random(1000, 9999))
    self.track_guid = data.track_guid or ""
    self.chan       = data.chan or 0

    -- Note 1 references
    self.n1_key     = data.n1_key or ""
    self.pitch1     = data.pitch1 or 60
    self.start_qn1  = data.start_qn1 or 0.0
    self.dur_qn1    = data.dur_qn1 or 1.0

    -- Note 2 references
    self.n2_key     = data.n2_key or ""
    self.pitch2     = data.pitch2 or 62
    self.start_qn2  = data.start_qn2 or (self.start_qn1 + self.dur_qn1)
    self.dur_qn2    = data.dur_qn2 or 1.0

    -- Percentage timings in 25% steps (Default: 50% Note 1 to 50% Note 2)
    self.start_pct1 = data.start_pct1 or 50
    self.end_pct2   = data.end_pct2   or 50

    -- Hold interval points
    local s_pct = (self.start_pct1 or 50) / 100.0
    local e_pct = (self.end_pct2 or 50) / 100.0
    self.hold_start_qn = data.hold_start_qn or (self.start_qn1 + s_pct * self.dur_qn1)
    self.hold_end_qn   = data.hold_end_qn or (self.start_qn2 + e_pct * self.dur_qn2)

    -- Playback control mode: "cc64" (default), "cc34", "cc5", "cc65"
    self.mode       = data.mode or "cc64"

    -- Staff scoping (to prevent cross-staff interaction within polyphonic / grand staff tracks)
    self.staff      = data.staff
    self.in_treble  = data.in_treble

    -- Text badge visibility (default ALWAYS false / off per user requirement)
    self.show_text  = (data.show_text == true)

    return self
end

function PortamentoMark:recalculate_timing()
    local s_pct = (self.start_pct1 or 50) / 100.0
    local e_pct = (self.end_pct2 or 50) / 100.0
    local d2 = self.dur_qn2 or 1.0
    if reaper and reaper.TimeMap2_QNToTime and reaper.TimeMap2_timeToBeats and reaper.TimeMap2_beatsToTime and reaper.TimeMap2_timeToQN then
        local t2 = reaper.TimeMap2_QNToTime(0, math.max(0.0, (self.start_qn2 or 0) + 0.001))
        local _, m2 = reaper.TimeMap2_timeToBeats(0, t2)
        local t_m2_next = reaper.TimeMap2_beatsToTime(0, 0, m2 + 1)
        local m2_eqn = reaper.TimeMap2_timeToQN(0, t_m2_next)
        d2 = math.min(d2, math.max(0.25, m2_eqn - (self.start_qn2 or 0)))
    end
    self.hold_start_qn = self.start_qn1 + s_pct * (self.dur_qn1 or 1.0)
    self.hold_end_qn   = self.start_qn2 + e_pct * d2
    if self.hold_end_qn <= self.hold_start_qn then
        self.hold_end_qn = self.hold_start_qn + 0.05
    end
end

function PortamentoMark:clone()
    return PortamentoMark.new({
        id            = self.id,
        track_guid    = self.track_guid,
        chan          = self.chan,
        n1_key        = self.n1_key,
        pitch1        = self.pitch1,
        start_qn1     = self.start_qn1,
        dur_qn1       = self.dur_qn1,
        n2_key        = self.n2_key,
        pitch2        = self.pitch2,
        start_qn2     = self.start_qn2,
        dur_qn2       = self.dur_qn2,
        hold_start_qn = self.hold_start_qn,
        hold_end_qn   = self.hold_end_qn,
        mode          = self.mode,
        staff         = self.staff,
        in_treble     = self.in_treble,
        show_text     = self.show_text,
        start_pct1    = self.start_pct1,
        end_pct2      = self.end_pct2
    })
end

return PortamentoMark


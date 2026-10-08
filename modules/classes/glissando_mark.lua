-- ==============================================================================
-- REAPER Native Notator - Class: GlissandoMark
-- Represents a Glissando line connecting two noteheads with real chromatic
-- MIDI pitch steps during playback and a wavy line in the score canvas.
-- Supports Cross-Staff connections (e.g. Harp/Piano Bass Clef to Treble/Alto Clef).
-- ==============================================================================

local GlissandoMark = {}
GlissandoMark.__index = GlissandoMark

function GlissandoMark.new(data)
    local self = setmetatable({}, GlissandoMark)
    self.id         = data.id or string.format("gliss_%d_%d", math.floor(reaper.time_precise() * 1000), math.random(1000, 9999))
    self.track_guid = data.track_guid or ""
    self.chan       = data.chan or 0

    -- Note 1 references (Start Note)
    self.n1_key     = data.n1_key or ""
    self.pitch1     = data.pitch1 or 60
    self.start_qn1  = data.start_qn1 or 0.0
    self.dur_qn1    = data.dur_qn1 or 1.0
    self.orig_dur1  = data.orig_dur1 or self.dur_qn1 -- Full un-shortened visual duration!

    -- Note 2 references (Arrival Note)
    self.n2_key     = data.n2_key or ""
    self.pitch2     = data.pitch2 or 62
    self.start_qn2  = data.start_qn2 or (self.start_qn1 + self.dur_qn1)
    self.dur_qn2    = data.dur_qn2 or 1.0

    -- Timing: Start % of Note 1 where chromatic ladder begins (Default: 50%)
    self.start_pct1 = data.start_pct1 or 50

    -- Playback parameters
    self.vel_mode   = data.vel_mode or "interpolate" -- "interpolate" | "flat"
    self.step_mode  = data.step_mode or "chromatic"   -- "chromatic"
    self.wave_style = data.wave_style or "sine"       -- "sine" | "saw"

    -- Cross-staff flag (e.g. Bass to Treble / Alto in Harp/Piano)
    self.cross_staff = (data.cross_staff == true)
    self.staff1     = data.staff1
    self.in_treble1 = data.in_treble1
    self.staff2     = data.staff2
    self.in_treble2 = data.in_treble2

    -- Text badge visibility (default true / on)
    self.show_text  = (data.show_text ~= false)

    return self
end

function GlissandoMark:clone()
    return GlissandoMark.new({
        id          = self.id,
        track_guid  = self.track_guid,
        chan        = self.chan,
        n1_key      = self.n1_key,
        pitch1      = self.pitch1,
        start_qn1   = self.start_qn1,
        dur_qn1     = self.dur_qn1,
        orig_dur1   = self.orig_dur1,
        n2_key      = self.n2_key,
        pitch2      = self.pitch2,
        start_qn2   = self.start_qn2,
        dur_qn2     = self.dur_qn2,
        start_pct1  = self.start_pct1,
        vel_mode    = self.vel_mode,
        step_mode   = self.step_mode,
        wave_style  = self.wave_style,
        cross_staff = self.cross_staff,
        staff1      = self.staff1,
        in_treble1  = self.in_treble1,
        staff2      = self.staff2,
        in_treble2  = self.in_treble2,
        show_text   = self.show_text
    })
end

return GlissandoMark


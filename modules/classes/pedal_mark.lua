-- ==============================================================================
-- REAPER Native Notator - Class: PedalMark
-- Represents a Holding/Sustain mark (Pedal line, CC64) with dual handles
-- and configurable sustain pause points (retakes / asterisk / notch)
-- ==============================================================================

local PedalMark = {}
PedalMark.__index = PedalMark

function PedalMark.new(data)
    local self = setmetatable({}, PedalMark)
    self.id         = data.id or string.format("ped_%d_%d", math.floor(reaper.time_precise() * 1000), math.random(1000, 9999))
    self.track_guid = data.track_guid or ""
    self.start_qn   = data.start_qn or 0.0
    self.end_qn     = data.end_qn or (self.start_qn + 4.0)
    self.style      = data.style or "classic" -- "classic" (Ped. -- *) | "bracket" (| -- |) | "notch" (Ped. --/\-- |)
    self.apply_cc   = (data.apply_cc ~= false) -- default true: writes CC64
    self.staff      = data.staff or "bass"     -- "bass" | "treble" | "mid"
    self.pauses     = {}

    if data.pauses and type(data.pauses) == "table" then
        for _, p in ipairs(data.pauses) do
            table.insert(self.pauses, {
                id   = p.id or string.format("p_%d", math.random(1000, 9999)),
                qn   = tonumber(p.qn) or (self.start_qn + 1.0),
                type = p.type or "asterisk", -- "asterisk" (*) | "notch" (/\) | "retake" (* Ped.)
                dur  = tonumber(p.dur) or 0.0
            })
        end
        table.sort(self.pauses, function(a, b) return a.qn < b.qn end)
    end

    return self
end

function PedalMark:clone()
    local cloned_pauses = {}
    for _, p in ipairs(self.pauses or {}) do
        table.insert(cloned_pauses, {
            id   = p.id,
            qn   = p.qn,
            type = p.type,
            dur  = p.dur
        })
    end
    return PedalMark.new({
        id         = self.id,
        track_guid = self.track_guid,
        start_qn   = self.start_qn,
        end_qn     = self.end_qn,
        style      = self.style,
        apply_cc   = self.apply_cc,
        staff      = self.staff,
        pauses     = cloned_pauses
    })
end

function PedalMark:add_pause(qn, ptype, dur)
    local pid = string.format("p_%d", math.random(1000, 9999))
    table.insert(self.pauses, {
        id   = pid,
        qn   = qn,
        type = ptype or "asterisk",
        dur  = dur or 0.0
    })
    table.sort(self.pauses, function(a, b) return a.qn < b.qn end)
    return pid
end

function PedalMark:remove_pause(pause_id_or_idx)
    if type(pause_id_or_idx) == "number" then
        table.remove(self.pauses, pause_id_or_idx)
    else
        for i, p in ipairs(self.pauses) do
            if p.id == pause_id_or_idx then
                table.remove(self.pauses, i)
                break
            end
        end
    end
end

function PedalMark:get_display_name()
    local num_p = #(self.pauses or {})
    local pause_info = (num_p > 0) and string.format(", %d Break(s)", num_p) or ""
    return string.format("Pedal (%.1f - %.1f QN%s)", self.start_qn, self.end_qn, pause_info)
end

return PedalMark

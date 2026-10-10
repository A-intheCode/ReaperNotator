-- ==============================================================================
-- REAPER Native Notator - Module: ShortcutManager
-- Central manager for user-configurable keyboard shortcuts
-- Persistent storage via REAPER ExtState
-- ==============================================================================

local ShortcutManager = {}

ShortcutManager.CATEGORIES = {
    "Grid & Note Length",
    "Grid Position",
    "Pitch & Transposition",
    "Accidentals",
    "Edit & Selection",
    "Transport",
    "Note Values",
}

ShortcutManager.DEFAULT_SHORTCUTS = {
    undo = {
        name = "Edit: Undo",
        cat  = "Edit & Selection",
        key  = "Z",
        ctrl = true,
        shift = false,
        alt  = false
    },
    redo = {
        name = "Edit: Redo",
        cat  = "Edit & Selection",
        key  = "Z",
        ctrl = true,
        shift = true,
        alt  = false
    },
    refresh_cache = {
        name = "Refresh Engine Cache / Reload Modules",
        cat  = "Edit & Selection",
        key  = "F5",
        ctrl = false,
        shift = false,
        alt  = false,
        desc = "Reloads all Lua rendering, engraving and service modules in-memory without restarting REAPER."
    },
    -- 1. Grid & Note Length
    quantize = {
        name = "Quantize: Open Dialog",
        cat  = "Grid & Note Length",
        key  = "Q",
        ctrl = false,
        shift = false,
        alt  = false
    },
    lengthen_note = {
        name = "Increase note length by grid",
        cat  = "Grid & Note Length",
        key  = "RightArrow",
        ctrl = false,
        shift = true,
        alt  = false
    },
    shorten_note = {
        name = "Decrease note length by grid",
        cat  = "Grid & Note Length",
        key  = "LeftArrow",
        ctrl = false,
        shift = true,
        alt  = false
    },
    
    -- 2. Grid Position
    move_right = {
        name = "Move note(s) right by grid",
        cat  = "Grid Position",
        key  = "RightArrow",
        ctrl = false,
        shift = false,
        alt  = false
    },
    move_left = {
        name = "Move note(s) left by grid",
        cat  = "Grid Position",
        key  = "LeftArrow",
        ctrl = false,
        shift = false,
        alt  = false
    },
    
    -- 3. Pitch & Transposition
    pitch_up = {
        name = "Pitch up semitone (+1)",
        cat  = "Pitch & Transposition",
        key  = "UpArrow",
        ctrl = false,
        shift = false,
        alt  = false
    },
    pitch_down = {
        name = "Pitch down semitone (-1)",
        cat  = "Pitch & Transposition",
        key  = "DownArrow",
        ctrl = false,
        shift = false,
        alt  = false
    },
    octave_up = {
        name = "Pitch up octave (+12)",
        cat  = "Pitch & Transposition",
        key  = "UpArrow",
        ctrl = false,
        shift = true,
        alt  = false
    },
    octave_down = {
        name = "Pitch down octave (-12)",
        cat  = "Pitch & Transposition",
        key  = "DownArrow",
        ctrl = false,
        shift = true,
        alt  = false
    },

    -- 4. Edit & Selection
    copy = {
        name = "Copy",
        cat  = "Edit & Selection",
        key  = "C",
        ctrl = true,
        shift = false,
        alt  = false
    },
    paste = {
        name = "Paste",
        cat  = "Edit & Selection",
        key  = "V",
        ctrl = true,
        shift = false,
        alt  = false
    },
    cut = {
        name = "Cut",
        cat  = "Edit & Selection",
        key  = "X",
        ctrl = true,
        shift = false,
        alt  = false
    },
    invert_stem = {
        name = "Invert / Flip Stem Direction",
        cat  = "Edit & Selection",
        key  = "X",
        ctrl = false,
        shift = false,
        alt  = false
    },
    cross_staff_toggle = {
        name = "Toggle Cross-Staff (Upper / Lower)",
        cat  = "Edit & Selection",
        key  = "M",
        ctrl = false,
        shift = false,
        alt  = false
    },
    cross_staff_up = {
        name = "Move Note to Upper Staff (Treble)",
        cat  = "Edit & Selection",
        key  = "UpArrow",
        ctrl = true,
        shift = true,
        alt  = false
    },
    cross_staff_down = {
        name = "Move Note to Lower Staff (Bass)",
        cat  = "Edit & Selection",
        key  = "DownArrow",
        ctrl = true,
        shift = true,
        alt  = false
    },
    select_all = {
        name = "Select all notes",
        cat  = "Edit & Selection",
        key  = "A",
        ctrl = true,
        shift = false,
        alt  = false
    },
    select_to_end = {
        name = "Select to end from selection",
        cat  = "Edit & Selection",
        key  = "E",
        ctrl = true,
        shift = true,
        alt  = false
    },
    filter_notes = {
        name = "Filter selection: Notes only",
        cat  = "Edit & Selection",
        key  = "N",
        ctrl = true,
        shift = true,
        alt  = false
    },
    filter_dynamics = {
        name = "Filter selection: Dynamics only",
        cat  = "Edit & Selection",
        key  = "Y",
        ctrl = true,
        shift = true,
        alt  = false
    },
    delete = {
        name = "Delete selection",
        cat  = "Edit & Selection",
        key  = "Delete",
        ctrl = false,
        shift = false,
        alt  = false
    },
    make_legato = {
        name = "Make Notes Legato",
        cat  = "Edit & Selection",
        key  = "L",
        ctrl = true,
        shift = false,
        alt  = false
    },
    toggle_slur = {
        name = "Toggle Slur (Legato phrase mark)",
        cat  = "Edit & Selection",
        key  = "S",
        ctrl = false,
        shift = false,
        alt  = false
    },
    toggle_tie = {
        name = "Toggle Tie (Hold same-pitch notes)",
        cat  = "Edit & Selection",
        key  = "T",
        ctrl = false,
        shift = false,
        alt  = false
    },
    toggle_portamento = {
        name = "Toggle Portamento (CC64 Hold / CC34 / CC5 / CC65)",
        cat  = "Edit & Selection",
        key  = "P",
        ctrl = false,
        shift = false,
        alt  = false
    },
    toggle_glissando = {
        name = "Toggle Glissando (Chromatic Pitch Steps)",
        cat  = "Edit & Selection",
        key  = "G",
        ctrl = false,
        shift = false,
        alt  = false
    },
    select_next_note = {
        name = "Select next note on timeline",
        cat  = "Edit & Selection",
        key  = "RightArrow",
        ctrl = false,
        shift = false,
        alt  = true
    },
    select_prev_note = {
        name = "Select previous note on timeline",
        cat  = "Edit & Selection",
        key  = "LeftArrow",
        ctrl = false,
        shift = false,
        alt  = true
    },
    select_note_above = {
        name = "Select note above in chord",
        cat  = "Edit & Selection",
        key  = "UpArrow",
        ctrl = false,
        shift = false,
        alt  = true
    },
    select_note_below = {
        name = "Select note below in chord",
        cat  = "Edit & Selection",
        key  = "DownArrow",
        ctrl = false,
        shift = false,
        alt  = true
    },
    extend_next_note = {
        name = "Extend note selection right",
        cat  = "Edit & Selection",
        key  = "RightArrow",
        ctrl = false,
        shift = true,
        alt  = true
    },
    extend_prev_note = {
        name = "Extend note selection left",
        cat  = "Edit & Selection",
        key  = "LeftArrow",
        ctrl = false,
        shift = true,
        alt  = true
    },
    extend_note_above = {
        name = "Extend note selection above in chord",
        cat  = "Edit & Selection",
        key  = "UpArrow",
        ctrl = false,
        shift = true,
        alt  = true
    },
    extend_note_below = {
        name = "Extend note selection below in chord",
        cat  = "Edit & Selection",
        key  = "DownArrow",
        ctrl = false,
        shift = true,
        alt  = true
    },
    toggle_articulations = {
        name = "Toggle Articulations panel",
        cat  = "Edit & Selection",
        key  = "L",
        ctrl = false,
        shift = false,
        alt  = false
    },
    toggle_clefs = {
        name = "Toggle Clefs panel",
        cat  = "Edit & Selection",
        key  = "C",
        ctrl = false,
        shift = true,
        alt  = false
    },
    toggle_dynamics = {
        name = "Toggle Dynamics panel",
        cat  = "Edit & Selection",
        key  = "D",
        ctrl = false,
        shift = true,
        alt  = false
    },
    toggle_tempo = {
        name = "Toggle Tempo panel",
        cat  = "Edit & Selection",
        key  = "T",
        ctrl = false,
        shift = true,
        alt  = false
    },
    toggle_write_mode = {
        name = "Toggle Write Notes / Mouse Draw Mode",
        cat  = "Edit & Selection",
        key  = "D",
        ctrl = false,
        shift = false,
        alt  = false
    },
    new_text_item = {
        name = "New Text Item",
        cat  = "Edit & Selection",
        key  = "T",
        ctrl = true,
        shift = false,
        alt  = false
    },
    select_mode = {
        name = "Selection Mode / Exit Draw Mode",
        cat  = "Edit & Selection",
        key  = "Escape",
        ctrl = false,
        shift = false,
        alt  = false
    },

    -- 5. Transport
    play_pause = {
        name = "Play / Stop",
        cat  = "Transport",
        key  = "Space",
        ctrl = false,
        shift = false,
        alt  = false
    },
    rewind = {
        name = "Rewind to Start of Project",
        cat  = "Transport",
        key  = "W",
        ctrl = false,
        shift = false,
        alt  = false
    },

    toggle_autoscroll = {
        name = "Toggle Autoscroll",
        cat  = "Transport",
        key  = "Q",
        ctrl = false,
        shift = false,
        alt  = false
    },

    -- 6. Note Values
    dur_32 = {
        name = "Note value: 1/32 (32nd)",
        cat  = "Note Values",
        key  = "2",
        ctrl = false,
        shift = false,
        alt  = false
    },
    dur_16 = {
        name = "Note value: 1/16 (16th)",
        cat  = "Note Values",
        key  = "3",
        ctrl = false,
        shift = false,
        alt  = false
    },
    dur_8 = {
        name = "Note value: 1/8 (Eighth)",
        cat  = "Note Values",
        key  = "4",
        ctrl = false,
        shift = false,
        alt  = false
    },
    dur_4 = {
        name = "Note value: 1/4 (Quarter)",
        cat  = "Note Values",
        key  = "5",
        ctrl = false,
        shift = false,
        alt  = false
    },
    dur_2 = {
        name = "Note value: 1/2 (Half)",
        cat  = "Note Values",
        key  = "6",
        ctrl = false,
        shift = false,
        alt  = false
    },
    dur_1 = {
        name = "Note value: 1/1 (Whole)",
        cat  = "Note Values",
        key  = "7",
        ctrl = false,
        shift = false,
        alt  = false
    },
    
    nav_up = {
        name = "Navigate Up",
        cat  = "Grid Position",
        key  = "UpArrow",
        ctrl = false,
        shift = false,
        alt  = false
    },
    toggle_dot = {
        name = "Toggle dotted note",
        cat  = "Note Values",
        key  = "Period",
        ctrl = false,
        shift = false,
        alt  = false
    },
    
    -- 7. Accidentals
    acc_flat = {
        name = "Accidental: ♭ Flat (-)",
        cat  = "Accidentals",
        key  = "Minus",
        ctrl = false,
        shift = false,
        alt  = false
    },
    acc_natural = {
        name = "Accidental: ♮ Natural (0)",
        cat  = "Accidentals",
        key  = "0",
        ctrl = false,
        shift = false,
        alt  = false
    },
    acc_sharp = {
        name = "Accidental: ♯ Sharp (+)",
        cat  = "Accidentals",
        key  = "Equal",
        ctrl = false,
        shift = false,
        alt  = false
    },
}

ShortcutManager.ACTION_LIST = {
    "lengthen_note",
    "shorten_note",
    "move_right",
    "move_left",
    "pitch_up",
    "pitch_down",
    "octave_up",
    "octave_down",
    "acc_flat",
    "acc_natural",
    "acc_sharp",
    "copy",
    "paste",
    "cut",
    "select_all",
    "select_next_note",
    "select_prev_note",
    "select_note_above",
    "select_note_below",
    "extend_next_note",
    "extend_prev_note",
    "extend_note_above",
    "extend_note_below",
    "delete",
    "play_pause",
    "rewind",
    "dur_32",
    "dur_16",
    "dur_8",
    "dur_4",
    "dur_2",
    "dur_1",
    "toggle_dot",
    "toggle_dynamics",
    "toggle_tempo",
    "toggle_autoscroll",
    "toggle_write_mode",
    "new_text_item",
    "select_mode",
    "refresh_cache",
}

local DISPLAY_NAMES = {
    UpArrow = "↑ (Up Arrow)",
    DownArrow = "↓ (Down Arrow)",
    LeftArrow = "← (Left Arrow)",
    RightArrow = "→ (Right Arrow)",
    Space = "Space",
    Delete = "Del",
    Backspace = "Backspace",
    Period = ". (Period)",
    Comma = ", (Comma)",
    Enter = "Enter",
    Escape = "Esc",
    Tab = "Tab",
    Minus = "-",
    Equal = "=",
    Slash = "/",
    Backslash = "\\",
    Semicolon = ";",
    Apostrophe = "'",
    LeftBracket = "[",
    RightBracket = "]",
    Keypad0 = "Num 0",
    Keypad1 = "Num 1",
    Keypad2 = "Num 2",
    Keypad3 = "Num 3",
    Keypad4 = "Num 4",
    Keypad5 = "Num 5",
    Keypad6 = "Num 6",
    Keypad7 = "Num 7",
    Keypad8 = "Num 8",
    Keypad9 = "Num 9",
    KeypadAdd = "Num +",
    KeypadSubtract = "Num -",
    KeypadMultiply = "Num *",
    KeypadDivide = "Num /",
    KeypadEnter = "Num Enter",
    PageUp = "Page Up",
    PageDown = "Page Down",
    Home = "Home",
    ["End"] = "End",
    Insert = "Ins",
}

ShortcutManager.SCAN_KEYS = {
    "UpArrow", "DownArrow", "LeftArrow", "RightArrow",
    "Space", "Enter", "Tab", "Backspace", "Delete", "Insert", "Home", "End", "PageUp", "PageDown",
    "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M",
    "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "Period", "Comma", "Minus", "Equal", "Slash", "Backslash", "Semicolon", "Apostrophe",
    "LeftBracket", "RightBracket",
    "Keypad0", "Keypad1", "Keypad2", "Keypad3", "Keypad4", "Keypad5",
    "Keypad6", "Keypad7", "Keypad8", "Keypad9",
    "KeypadAdd", "KeypadSubtract", "KeypadMultiply", "KeypadDivide", "KeypadEnter"
}

ShortcutManager.shortcuts = {}

function ShortcutManager.clone_defaults()
    local t = {}
    for k, v in pairs(ShortcutManager.DEFAULT_SHORTCUTS) do
        t[k] = {
            name  = v.name,
            cat   = v.cat,
            key   = v.key,
            ctrl  = v.ctrl,
            shift = v.shift,
            alt   = v.alt
        }
    end
    return t
end

function ShortcutManager.get_key_enum(key_name)
    if not key_name or key_name == "" then return nil end
    local fn_name = "ImGui_Key_" .. key_name
    if reaper[fn_name] then
        return reaper[fn_name]()
    end
    return nil
end

function ShortcutManager.get_display_string(sc)
    if not sc or not sc.key or sc.key == "" then return "(None)" end
    local parts = {}
    if sc.ctrl then table.insert(parts, "Ctrl") end
    if sc.alt then table.insert(parts, "Alt") end
    if sc.shift then table.insert(parts, "Shift") end
    local key_disp = DISPLAY_NAMES[sc.key] or sc.key
    table.insert(parts, key_disp)
    return table.concat(parts, " + ")
end

function ShortcutManager.is_action_pressed(ctx, action_id, is_ctrl, is_shift, is_alt)
    local sc = ShortcutManager.shortcuts[action_id]
    if not sc or not sc.key or sc.key == "" then return false end
    
    local req_ctrl = not not sc.ctrl
    local req_shift = not not sc.shift
    local req_alt = not not sc.alt
    
    if req_ctrl ~= (not not is_ctrl) then return false end
    if req_shift ~= (not not is_shift) then return false end
    if req_alt ~= (not not is_alt) then return false end
    
    local key_code = ShortcutManager.get_key_enum(sc.key)
    if not key_code then return false end
    
    return reaper.ImGui_IsKeyPressed(ctx, key_code, false)
end

function ShortcutManager.set_shortcut(action_id, def)
    if not ShortcutManager.shortcuts[action_id] then
        ShortcutManager.shortcuts[action_id] = {}
    end
    local sc = ShortcutManager.shortcuts[action_id]
    sc.key   = def.key or ""
    sc.ctrl  = not not def.ctrl
    sc.shift = not not def.shift
    sc.alt   = not not def.alt
end

function ShortcutManager.clear_shortcut(action_id)
    if ShortcutManager.shortcuts[action_id] then
        local sc = ShortcutManager.shortcuts[action_id]
        sc.key = ""
        sc.ctrl = false
        sc.shift = false
        sc.alt = false
    end
end

function ShortcutManager.reset_to_defaults()
    ShortcutManager.shortcuts = ShortcutManager.clone_defaults()
end

function ShortcutManager.save()
    local parts = {}
    for act, sc in pairs(ShortcutManager.shortcuts) do
        local k = sc.key or ""
        local c = sc.ctrl and "1" or "0"
        local s = sc.shift and "1" or "0"
        local a = sc.alt and "1" or "0"
        table.insert(parts, string.format("%s:%s:%s:%s:%s", act, k, c, s, a))
    end
    local data = table.concat(parts, ";")
    reaper.SetExtState("REAPER_NATIVE_NOTATOR", "custom_shortcuts", data, true)
end

function ShortcutManager.load()
    ShortcutManager.shortcuts = ShortcutManager.clone_defaults()
    local str = reaper.GetExtState("REAPER_NATIVE_NOTATOR", "custom_shortcuts")
    if not str or str == "" then return end
    for item in str:gmatch("([^;]+)") do
        local act, k, c, s, a = item:match("([^:]+):([^:]*):([01]):([01]):([01])")
        if act and ShortcutManager.shortcuts[act] then
            ShortcutManager.shortcuts[act].key   = k
            ShortcutManager.shortcuts[act].ctrl  = (c == "1")
            ShortcutManager.shortcuts[act].shift = (s == "1")
            ShortcutManager.shortcuts[act].alt   = (a == "1")
        end
    end
end

function ShortcutManager.init()
    ShortcutManager.load()
end

return ShortcutManager

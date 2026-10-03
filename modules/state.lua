-- ==============================================================================
-- REAPER Native Notator - Module: State
-- Central reactive state container for Notator
-- ==============================================================================

local State = {}
local Constants = package.loaded["constants"] or require("constants")

function State.new()
    local self = {
        is_open = true,
        version = Constants.VERSION_DISPLAY or "v1.0.0",
        view_mode = "auto",       -- "auto", "treble", "bass", "grand"
        zoom = 1.0,              -- 0.6 to 2.0
        scroll_factor = 3.0,
        bar_num_offset_x = -10.0,
        bar_num_offset_y = 0.0,
        bar_num_size = 14.0,      -- Speed factor for canvas scrolling
        dynamics_offset_y = 45.0,     -- Vertical dynamics distance (Default +25% = 36 * 1.25 = 45.0)
        pedal_offset_y = 30.0,        -- Vertical pedal distance below dynamics (Default 30.0 px)
        articulations_offset_y = 16.0, -- Vertical articulations distance (above staff)
        articulations_font_size = 17.0, -- Font size of text articulations (standard engraving)
        articulations_bold = true,      -- Bold style for playing techniques
        track_spacing = 35.0,          -- Manual track spacing via slider
        show_item_boxes = true,        -- Show MIDI item bounding boxes & tags
        item_box_intensity = 25,       -- Color intensity of MIDI track regions in % (5-100)
        sticky_track_headers = true,   -- Stick track names to left edge during scrolling
        show_track_headers = true,     -- Show track name badges
        show_bar_numbers = true,       -- Show measure numbers
        show_dynamics_layer = true,    -- Show dynamics markers (p, f, etc.)
        show_articulations_layer = true,-- Show articulations (Reaticulate)
        show_hairpins_layer = true,    -- Show hairpins (< & >)
        show_tempo_layer = true,       -- Show tempo markers
        show_octaves_layer = true,     -- Show octave lines (8va/8vb)
        show_tuplets_layer = true,     -- Show tuplets / triplets (3, 5, etc.)
        show_key_signatures = false,   -- Show key signature accidentals on staff
        key_signature = 0,             -- Key signature index (-7 to +7, 0 = C major / A minor)
        key_signature_mode = "major",  -- "major" | "minor"
        track_key_signatures = {},     -- Map: track_guid -> { idx = ..., key_idx = ..., mode = ... }
        active_dur = 1.0,         -- QN: 1.0 = 1/4, 0.5 = 1/8, 0.25 = 1/16, etc.
        dur_label = "1/4",
        is_dotted = false,
        is_triplet = false,
        tuplet_type = nil,        -- nil (normal 1:1) | "3" (triplet 3:2) | "5" (quintuplet 5:4) | "6" (sextuplet 6:4) | "7" (septuplet 7:4) | "8" (octuplet 8:6)
        is_rest = false,
        accidental = 0,           -- 0 = natural, 1 = sharp, -1 = flat
        note_accidentals = {},    -- Map: note_key -> -1 (flat) | 0 (natural) | 1 (sharp)
        note_base_pitch = {},     -- Map: note_key -> integer (natural base pitch, e.g. 62 for D)
        note_stem_directions = {},-- Map: note_key -> "up" | "down" (manual stem direction)
        active_velocity = 90,     -- Default velocity (mf)
        active_articulation = nil,-- "accent", "staccato", "tenuto", "marcato"
        tie_active = false,
        slur_active = false,
        current_octave = 4,       -- Default octave (C4)
        
        -- Note selection & multi-selection
        selected_notes = {},      -- Map: note_key(n) -> note
        selected_note = nil,      -- Primary lead note
        hovered_note = nil,
        
        -- Marquee selection box
        marquee_active = false,
        marquee_start_x = 0,
        marquee_start_y = 0,
        marquee_cur_x = 0,
        marquee_cur_y = 0,
        
        -- Multi-Note Drag & Drop
        drag_note = nil,
        drag_selected_snapshot = {},
        drag_start_x = 0,
        drag_start_y = 0,
        drag_target_qn = 0,
        drag_target_pitch = 0,
        is_dragging = false,
        
        -- Dynamics marker interaction
        selected_dynamic = nil,   -- Currently selected marker
        selected_dynamics = {},   -- Map for multi-selection: key -> marker
        hovered_dynamic = nil,
        drag_dynamic = nil,       -- Dragged marker
        drag_dyn_start_x = 0,
        drag_dyn_start_qn = 0,
        drag_dyn_target_qn = 0,
        is_dragging_dynamic = false,

        -- Articulations (Reaticulate PC Events)
        selected_articulation = nil,
        selected_articulations = {}, -- Map: art_key -> art
        hovered_articulation = nil,
        drag_articulation = nil,
        is_dragging_articulation = false,
        drag_art_start_x = 0,
        drag_art_start_qn = 0,
        drag_art_target_qn = 0,
        
        -- Multi-Selection Maps & Filter State
        selected_hairpins = {},
        selected_dynamic_texts = {},
        selected_pedals = {},
        selected_text_items = {},
        selected_octave_lines = {},
        selection_bounds = nil,
        selection_is_to_end = false,
        selection_filter = {
            notes = true,
            dynamics = true,
            hairpins = true,
            dynamic_texts = true,
            text_items = true,
            pedals = true,
            octaves = true,
            articulations_only = false
        },
        
        -- Multitrack & Track-Picker
        selected_tracks = {},     -- Map: track_guid -> boolean
        track_clefs = {},         -- Map: track_guid -> "treble"|"bass"|"grand"|"auto"
        track_voices = {},        -- Map: track_guid -> voice (0 = All Notes, 1..16 = Voice 1..16)
        active_voice = 0,         -- Active voice (0 = All Notes, 1..16)
        voice_color_mode = true,  -- Color notes by voice (MIDI channels 1-16)
        hide_inactive_voices = false, -- Completely hide inactive voices instead of dimming
        ghost_voice_opacity = 0.25, -- Opacity / transparency of ghost notes (0.05 to 1.0, default 0.25 = 25%)
        show_track_picker = false,
        focused_track = nil,      -- MediaTrack* of focused track
        selected_item = nil,      -- MediaItem* of selected MIDI item
        selected_take = nil,      -- MediaItem_Take* of selected MIDI item
        
        -- MIDI Item Resizing & Neuanlage
        hovered_item_edge = nil,  -- { item_info = ..., edge = "left"|"right" }
        is_resizing_item = false,
        resize_item_info = nil,
        resize_edge = nil,
        resize_start_x = 0,
        resize_orig_pos = 0,
        resize_orig_len = 0,
        
        is_drawing_item = false,
        draw_item_track = nil,
        draw_item_start_qn = 0,
        draw_item_cur_qn = 0,
        
        -- Manual Slurs & Ties
        user_slurs = {},
        
        -- Panel widths (resizable via splitter drag)
        sidebar_w = 210,          -- Width of left sidebar (resizable 140-500px)
        drawer_w = 236,           -- Width of right drawer (resizable 180-500px)
        
        -- Input mode & window state
        input_mode_type = "select", -- "select" | "step" | "draw"
        draw_preview = nil,         -- { track = ..., qn = ..., pitch = ..., dur = ..., accidental = ... }
        input_mode = false,        -- Kept in sync: true if input_mode_type == "step"
        window_locked = false,
        is_maximized = false,       -- Window maximized state
        prev_win_x = 100,
        prev_win_y = 60,
        prev_win_w = 1280,
        prev_win_h = 720,
        cur_win_x = 100,
        cur_win_y = 60,
        cur_win_w = 1280,
        cur_win_h = 720,
        request_maximize_toggle = false,
        just_restored = false,
        show_help = false,
        show_dynamics_menu = (reaper.GetExtState("REAPER_Notator", "ShowDynamics") == "true"),
        show_articulation_menu = (reaper.GetExtState("REAPER_Notator", "ShowArticulations") == "true"),
        show_settings = false,
        capturing_action = nil,
        
        -- ScoreTools Dynamics Drawer
        show_dynamics = false,
        dyn_cc_a = 1,
        dyn_cc_b = 11,
        dyn_phrasing_active = true,
        dyn_phrasing_intensity = 0.5,
        dyn_humanize_intensity = 0.3,
        dyn_stress_factor = 0.5,
        dyn_bow_intensity = 0.0,  -- Bow swell curve intensity (0.0 to 1.0, default 0.0 = off)
        dyn_bow_pos = 0.5,        -- Bow position peak (0.0 = start, 0.5 = center / default, 1.0 = end of note)
        dyn_vel_sensitivity = 0.8,
        dyn_grid_idx = 4,         -- 1/64
        dyn_marker_blending = false, -- Marker-to-marker blending (default / global fallback: off)
        dyn_bypass_cc = false,    -- Bypass dynamic CC shaping (default: false -> CCs are generated)
        track_marker_blending = {}, -- Map: track_guid -> boolean (per track)
        item_marker_blending = {},  -- Map: item_ptr -> boolean (per MIDI item)
        item_bypass_cc = {},        -- Map: item_ptr -> boolean (per MIDI item)
        last_dyn_item = nil,        -- Last focused MediaItem in dynamics drawer
        
        -- Tempo Marker System
        show_tempo = false,       -- Visibility of tempo drawer on right
        tempo_markers = {},       -- List of TempoMarker objects
        selected_tempo_marker = nil,
        hovered_tempo_marker = nil,
        hovered_tempo_handle = nil, -- "start" | "end" | "body"
        drag_tempo_marker = nil,
        drag_tempo_handle = nil,    -- "start" | "end" | "body"
        is_dragging_tempo = false,
        tempo_drawer_presets_h = 220, -- Scalable height of tempo presets list (via splitter)
        
        -- Clef Drawer System
        show_clefs = false,       -- Visibility of Clef drawer on right
        clef_drawer_h1 = 180,     -- Height Category 1 (Common Clefs) via Splitter
        clef_drawer_h2 = 180,     -- Height Category 2 (Uncommon Clefs) via Splitter
        clef_drawer_h3 = 140,     -- Height Category 3 (Archaic Clefs) via Splitter
        
        -- Articulations Drawer & Bank Picker System
        show_articulations_drawer = false, -- Visibility of Articulations drawer on right
        show_bank_picker_modal = false, -- Modal for bank selection (search & categories)
        track_articulation_banks = {}, -- Map: trk_guid -> bank_id_or_name
        articulations_display_mode = "text", -- "text" (standard engraving) | "badge"
        custom_resource_path = "", -- User-defined REAPER user/resource folder (Settings)
        
        -- Orchestral Pattern Browser & Bottom Pane System
        show_pattern_browser = (reaper.GetExtState("REAPER_Notator", "ShowPatternBrowser") == "true"),
        pattern_browser_h = tonumber(reaper.GetExtState("REAPER_Notator", "PatternBrowserHeight")) or 240,
        pattern_card_zoom = tonumber(reaper.GetExtState("REAPER_Notator", "PatternCardZoom")) or 1.0,
        selected_pattern_category = "all",
        pattern_search_query = "",
        pattern_preview_track = nil,
        dragged_pattern = nil,
        is_dragging_pattern = false,
        
        -- Octave Lines (8va, 15ma, 22ma, 8vb, 15mb, 22mb, loco)
        octave_lines = {},
        selected_octave_line = nil,
        hovered_octave_line = nil,
        hovered_octave_handle = nil, -- "start" | "end" | "body"
        drag_octave_line = nil,
        drag_octave_handle = nil,    -- "start" | "end" | "body"
        is_dragging_octave = false,
        drag_octave_start_x = 0,
        drag_octave_orig_start = 0,
        drag_octave_orig_end = 0,
        drag_octave_delta_qn = 0,
        drag_octave_target_qn = 0,

        -- Hairpins / Crescendo & Decrescendo Ramps
        hairpins = {},
        selected_hairpin = nil,
        hovered_hairpin = nil,
        hovered_hairpin_handle = nil, -- "start" | "end" | "body"
        drag_hairpin = nil,
        drag_hairpin_handle = nil,    -- "start" | "end" | "body"
        is_dragging_hairpin = false,
        drag_hairpin_start_x = 0,
        drag_hairpin_orig_start = 0,
        drag_hairpin_orig_end = 0,
        drag_hairpin_delta_qn = 0,
        drag_hairpin_target_qn = 0,

        -- Dynamic Texts (Crescendo & Diminuendo text tags with length scalability)
        dynamic_texts = {},
        selected_dynamic_text = nil,
        hovered_dynamic_text = nil,
        hovered_dynamic_text_handle = nil, -- "start" | "end" | "body"
        drag_dynamic_text = nil,
        drag_dynamic_text_handle = nil,    -- "start" | "end" | "body"
        is_dragging_dynamic_text = false,
        drag_dynamic_text_start_x = 0,
        drag_dynamic_text_orig_start = 0,
        drag_dynamic_text_orig_end = 0,
        drag_dynamic_text_delta_qn = 0,
        drag_dynamic_text_target_qn = 0,
        dyn_text_template_idx = 1,         -- 1: Standard, 2: Full text, 3: Poco a poco, 4: Sempre, 5: Decresc.
        dyn_text_line_pattern = "none",     -- "none" | "dashed" | "dotted"
        dyn_text_curve_pattern = "linear",  -- "linear" | "exponential" | "s_curve"
        show_dynamic_texts_layer = true,

        -- Pedal / Sustain Mark System (Holding / Sustain marks, CC64)
        pedal_marks = {},
        selected_pedal = nil,
        hovered_pedal = nil,
        hovered_pedal_handle = nil,      -- "start" | "end" | "body" | "pause_<id>"
        drag_pedal = nil,
        drag_pedal_handle = nil,         -- "start" | "end" | "body" | "pause_<id>"
        is_dragging_pedal = false,
        drag_pedal_start_x = 0,
        drag_pedal_orig_start = 0,
        drag_pedal_orig_end = 0,
        drag_pedal_delta_qn = 0,
        drag_pedal_target_qn = 0,
        drag_pedal_pause_orig_qn = 0,
        pedal_default_style = "classic", -- "classic" (Ped. -- *) | "bracket" (| -- |) | "notch" (Ped. --/\-- |)
        show_pedal_layer = true,

        -- Text Items (Free-floating text annotations with X/Y drag & drop)
        text_items = {},
        selected_text_item = nil,
        hovered_text_item = nil,
        editing_text_item = nil,
        editing_text_str = "",
        editing_text_just_opened = false,
        drag_text_item = nil,
        is_dragging_text_item = false,
        drag_text_start_mouse_x = 0,
        drag_text_start_mouse_y = 0,
        drag_text_orig_qn = 0,
        drag_text_orig_offset_y = 32.0,
        drag_text_target_qn = 0,
        drag_text_target_offset_y = 32.0,
        show_text_items_layer = true,

        -- Chord / Scale Lane System (Live transposition with scalable brackets [ - - - - ])
        chord_items = {},
        selected_chord_item = nil,
        hovered_chord_item = nil,
        hovered_chord_handle = nil, -- "start" | "end" | "body"
        drag_chord_item = nil,
        drag_chord_handle = nil,    -- "start" | "end" | "body"
        is_dragging_chord = false,
        drag_chord_start_x = 0,
        drag_chord_orig_start = 0,
        drag_chord_orig_end = 0,
        drag_chord_delta_qn = 0,
        drag_chord_target_qn = 0,
        editing_chord_item = nil,
        editing_chord_str = "",
        editing_chord_just_opened = false,
        show_chord_lane = true,
        chord_target_tracks = {},   -- Map: track_guid -> boolean (tracks affected by chord lane)
        
        -- Scale Transposition Modal (Sidebar Button "Scale")
        show_scale_modal = false,
        scale_modal_root = 0,       -- 0 = C
        scale_modal_type = "major",

        -- Score Print & PDF Export Modal (Bottom Bar Button "Print...")
        show_print_modal = false,
        print_settings = nil,

        -- MusicXML Import & Export Modal (Bottom Bar Button "MusicXML...")
        show_musicxml_modal = false,

        -- Measure repeat marks (Simile %, repeat1Bar)
        repeat_marks = {},
        show_repeat_marks_layer = true,

        grid_qn = 0.5,            --QN: 1.0 = 1/4, 0.5 = 1/8, 0.25 = 1/16, etc.
        grid_label = "1/8",
        display_quantize = false, -- Visual note alignment in score view (Display Quantize)
        display_quantize_grid = 1.0,   -- Dedicated grid for Display Quantize (in QN)
        display_quantize_label = "1/4", -- Label for Display Quantize grid
        
        -- MIDI Note Quantization (Dialog & settings matching REAPER)
        show_quantize_modal = false,
        quantize_grid_qn = 0.25,        -- Default 1/16 (0.25 QN)
        quantize_grid_label = "1/16",
        quantize_grid_type = "straight", -- "straight" | "triplet" | "dotted"
        quantize_target = "position",    -- "position" | "length" | "both"
        quantize_strength = 100,         -- 0 .. 100 %
        quantize_swing = 0,              -- 0 .. 100 %
        quantize_scope = "selected",     -- "selected" | "all"
        
        -- Notation & Beaming Engine
        beam_grouping = "beat",   -- "beat" (1 QN), "half_bar", "bar", "none"
        show_notation_settings = false,
        
        -- Audio preview (Audition / playback when clicking & editing notes)
        audition_notes = true,
        audition_active_note = nil,
        audition_volume = 50,     -- 0 to 100% (50 = Written dynamic/velocity, 100 = 100% Max)
        
        -- Copy & Paste Clipboard (notes & events)
        clipboard = nil,          -- { notes = {}, dynamics = {}, total_dur_qn = 0 }
        
        -- Status message
        status_msg = "Ready. Drag notes & dynamics to move. Copy (Ctrl+C), Paste (Ctrl+V)."
    }
    
    function self:clear_selection()
        self.selected_notes = {}
        self.selected_note = nil
        self.selected_dynamic = nil
        self.selected_tempo_marker = nil
        self.selected_octave_line = nil
        self.selected_hairpin = nil
        self.selected_dynamic_text = nil
        self.selected_pedal = nil
        self.selected_text_item = nil
        self.selected_chord_item = nil
        
        -- Multi-selection maps & bounds
        self.selected_dynamics = {}
        self.selected_hairpins = {}
        self.selected_dynamic_texts = {}
        self.selected_pedals = {}
        self.selected_text_items = {}
        self.selected_octave_lines = {}
        self.selected_articulation = nil
        self.selected_articulations = {}
        self.selection_bounds = nil
        self.selection_is_to_end = false
    end
    
    function self:select_note(n)
        if not n then return end
        local key = n.key or (n.get_key and n:get_key())
        if not key and n.item and n.take then
            key = string.format("%s_%s_%.3f_%d_%d", tostring(n.item), tostring(n.take), n.start_qn, n.pitch, n.chan or 0)
        end
        if key then
            self.selected_notes[key] = n
            self.selected_note = n
        end
    end
    
    function self:toggle_note_selection(n)
        if not n then return end
        local key = n.key or (n.get_key and n:get_key())
        if not key and n.item and n.take then
            key = string.format("%s_%s_%.3f_%d_%d", tostring(n.item), tostring(n.take), n.start_qn, n.pitch, n.chan or 0)
        end
        if key then
            if self.selected_notes[key] then
                self.selected_notes[key] = nil
                if self.selected_note == n then
                    self.selected_note = nil
                    for _, rem in pairs(self.selected_notes) do self.selected_note = rem break end
                end
            else
                self.selected_notes[key] = n
                self.selected_note = n
            end
        end
    end
    
    function self:is_note_selected(n)
        if not n then return false end
        local key = n.key or (n.get_key and n:get_key())
        if not key and n.item and n.take then
            key = string.format("%s_%s_%.3f_%d_%d", tostring(n.item), tostring(n.take), n.start_qn, n.pitch, n.chan or 0)
        end
        if key and self.selected_notes[key] ~= nil then return true end
        if self.selected_note then
            local sn = self.selected_note
            if sn.take == n.take and sn.pitch == n.pitch and math.abs(sn.start_qn - n.start_qn) < 0.01 then
                if key then self.selected_notes[key] = n end
                self.selected_note = n
                return true
            end
        end
        for _, sn in pairs(self.selected_notes) do
            if sn.take == n.take and sn.pitch == n.pitch and math.abs(sn.start_qn - n.start_qn) < 0.01 then
                if key then self.selected_notes[key] = n end
                return true
            end
        end
        return false
    end
    
    function self:count_selected_notes()
        local cnt = 0
        for _ in pairs(self.selected_notes) do cnt = cnt + 1 end
        return cnt
    end

    function self:get_articulation_key(art)
        if not art then return nil end
        local tk = tostring(art.take or "0")
        local ppq = tostring(art.ppq or math.floor((art.qn or 0) * 960))
        local pc = tostring(art.pc or 0)
        local ch = tostring(art.chan or 0)
        return string.format("%s_%s_%s_%s", tk, ppq, pc, ch)
    end

    function self:select_articulation(art)
        if not art then return end
        local key = self:get_articulation_key(art)
        if key then
            self.selected_articulations[key] = art
            self.selected_articulation = art
        end
    end

    function self:deselect_articulation(art)
        if not art then return end
        local key = self:get_articulation_key(art)
        if key then
            self.selected_articulations[key] = nil
            if self.selected_articulation == art then
                self.selected_articulation = nil
                for _, rem in pairs(self.selected_articulations) do
                    self.selected_articulation = rem
                    break
                end
            end
        end
    end

    function self:toggle_articulation_selection(art)
        if not art then return end
        local key = self:get_articulation_key(art)
        if key and self.selected_articulations[key] then
            self:deselect_articulation(art)
        else
            self:select_articulation(art)
        end
    end

    function self:is_articulation_selected(art)
        if not art then return false end
        if self.selected_articulation == art then return true end
        local key = self:get_articulation_key(art)
        return (key and self.selected_articulations and self.selected_articulations[key] ~= nil) or false
    end

    function self:clear_articulation_selection()
        self.selected_articulations = {}
        self.selected_articulation = nil
    end

    function self:count_selected_articulations()
        local cnt = 0
        if self.selected_articulations then
            for _ in pairs(self.selected_articulations) do cnt = cnt + 1 end
        end
        if cnt == 0 and self.selected_articulation then cnt = 1 end
        return cnt
    end
    
    function self:get_tuplet_factor()
        if self.tuplet_type == "3" or self.tuplet_type == 3 then
            return 1.0 / 3.0
        elseif self.tuplet_type == "5" or self.tuplet_type == 5 then
            return 1.0 / 5.0
        elseif self.tuplet_type == "6" or self.tuplet_type == 6 then
            return 1.0 / 6.0
        elseif self.tuplet_type == "7" or self.tuplet_type == 7 then
            return 1.0 / 7.0
        elseif self.tuplet_type == "8" or self.tuplet_type == 8 then
            return 1.0 / 8.0
        end
        if self.is_triplet then return 1.0 / 3.0 end
        return 1.0
    end
    
    function self:get_tuplet_count()
        local n = tonumber(self.tuplet_type)
        return (n and n > 1) and n or 3
    end
    
    function self:set_tuplet_type(t_type)
        if t_type == nil or t_type == "normal" or t_type == "none" or self.tuplet_type == tostring(t_type) then
            self.tuplet_type = nil
            self.is_triplet = false
            self.status_msg = "Tuplet mode disabled (Normal 1:1)"
        else
            self.tuplet_type = tostring(t_type)
            self.is_triplet = (t_type == "3" or t_type == 3)
            local Constants = require("constants")
            local def = Constants.TUPLET_DEFS and Constants.TUPLET_DEFS[self.tuplet_type]
            local tname = def and def.name or (self.tuplet_type .. "-tuplet")
            self.status_msg = string.format("Tuplet mode active: %s (%s)", tname, def and def.label or "")
        end
    end
    
    
    function self:save_tempo_drawer_presets_h(h)
        self.tempo_drawer_presets_h = h
        reaper.SetExtState("REAPER_Notator", "tempo_drawer_presets_h", tostring(math.floor(h)), true)
        reaper.SetProjExtState(0, "REAPER_Notator", "tempo_drawer_presets_h", tostring(math.floor(h)))
    end

    function self:save_clef_drawer_heights(h1, h2, h3)
        if h1 then
            self.clef_drawer_h1 = h1
            reaper.SetExtState("REAPER_Notator", "clef_drawer_h1", tostring(math.floor(h1)), true)
            reaper.SetProjExtState(0, "REAPER_Notator", "clef_drawer_h1", tostring(math.floor(h1)))
        end
        if h2 then
            self.clef_drawer_h2 = h2
            reaper.SetExtState("REAPER_Notator", "clef_drawer_h2", tostring(math.floor(h2)), true)
            reaper.SetProjExtState(0, "REAPER_Notator", "clef_drawer_h2", tostring(math.floor(h2)))
        end
        if h3 then
            self.clef_drawer_h3 = h3
            reaper.SetExtState("REAPER_Notator", "clef_drawer_h3", tostring(math.floor(h3)), true)
            reaper.SetProjExtState(0, "REAPER_Notator", "clef_drawer_h3", tostring(math.floor(h3)))
        end
    end

    setmetatable(self, { __index = State })
    self.current_reaproject = nil
    self.current_proj_fn = nil
    self:load_settings()
    return self
end

function State:load_settings()
    local function get_proj_or_ext(key)
        local rv, val = reaper.GetProjExtState(0, "REAPER_Notator", key)
        if rv == 1 and val and val ~= "" then
            return val
        end
        local eval = reaper.GetExtState("REAPER_Notator", key)
        if eval and eval ~= "" then
            return eval
        end
        return nil
    end

    local function load_num(key, default)
        local v = get_proj_or_ext(key)
        if v then return tonumber(v) or default end
        return default
    end

    local function load_bool(key, default)
        local v = get_proj_or_ext(key)
        if v == "true" then return true end
        if v == "false" then return false end
        return default
    end

    local function load_str(key, default)
        local v = get_proj_or_ext(key)
        if v and v ~= "" then return v end
        return default
    end

    self.scroll_factor = load_num("scroll_factor", 3.0)
    self.bar_num_offset_x = load_num("bar_num_offset_x", -10.0)
    self.bar_num_offset_y = load_num("bar_num_offset_y", 0.0)
    self.bar_num_size = load_num("bar_num_size", 14.0)
    self.dynamics_offset_y = load_num("dynamics_offset_y", 45.0)
    self.hairpins_offset_y = self.dynamics_offset_y
    self.pedal_offset_y = load_num("pedal_offset_y", 75.0)
    self.articulations_offset_y = load_num("articulations_offset_y", 16.0)
    self.articulations_font_size = load_num("articulations_font_size", 17.0)
    self.articulations_bold = load_bool("articulations_bold", true)
    self.track_spacing = load_num("track_spacing", 70.0)
    self.show_item_boxes = load_bool("show_item_boxes", true)
    self.item_box_intensity = load_num("item_box_intensity", 25)
    self.sticky_track_headers = load_bool("sticky_track_headers", true)
    self.show_track_headers = load_bool("show_track_headers", true)
    self.show_bar_numbers = load_bool("show_bar_numbers", true)
    self.show_dynamics_layer = load_bool("show_dynamics_layer", true)
    self.show_articulations_layer = load_bool("show_articulations_layer", true)
    self.show_hairpins_layer = load_bool("show_hairpins_layer", true)
    self.show_tempo_layer = load_bool("show_tempo_layer", true)
    self.show_octaves_layer = load_bool("show_octaves_layer", true)
    self.show_tuplets_layer = load_bool("show_tuplets_layer", true)
    self.show_key_signatures = load_bool("show_key_signatures", false)
    self.key_signature = load_num("key_signature", 0)
    self.key_signature_mode = load_str("key_signature_mode", "major")
    self.show_text_items_layer = load_bool("show_text_items_layer", true)
    self.show_pedal_layer = load_bool("show_pedal_layer", true)
    self.show_dynamic_texts_layer = load_bool("show_dynamic_texts_layer", true)
    self.show_chord_lane = load_bool("show_chord_lane", true)
    self.audition_notes = load_bool("audition_notes", true)
    self.audition_volume = load_num("audition_volume", 50)
    self.tempo_offset_y = load_num("tempo_offset_y", 28.0)
    self.octave_offset_y = load_num("octave_offset_y", 18.0)
    self.invert_mode = load_bool("invert_mode", false)
    self.tempo_drawer_presets_h = load_num("tempo_drawer_presets_h", 220)
    self.clef_drawer_h1 = load_num("clef_drawer_h1", 180)
    self.clef_drawer_h2 = load_num("clef_drawer_h2", 180)
    self.clef_drawer_h3 = load_num("clef_drawer_h3", 140)
    self.view_mode = load_str("view_mode", "auto")
    self.zoom = load_num("zoom", 1.0)
    self.grid_qn = load_num("grid_qn", 0.5)
    self.grid_label = load_str("grid_label", "1/8")
    self.display_quantize = load_bool("display_quantize", false)
    self.display_quantize_grid = load_num("display_quantize_grid", 1.0)
    self.display_quantize_label = load_str("display_quantize_label", "1/4")
    self.beam_grouping = load_str("beam_grouping", "beat")
    self.dyn_cc_a = load_num("dyn_cc_a", 1)
    self.dyn_cc_b = load_num("dyn_cc_b", 11)
    self.dyn_phrasing_active = load_bool("dyn_phrasing_active", true)
    self.dyn_phrasing_intensity = load_num("dyn_phrasing_intensity", 0.5)
    self.dyn_humanize_intensity = load_num("dyn_humanize_intensity", 0.3)
    self.dyn_stress_factor = load_num("dyn_stress_factor", 0.5)
    self.dyn_bow_intensity = load_num("dyn_bow_intensity", 0.0)
    self.dyn_bow_pos = load_num("dyn_bow_pos", 0.5)
    self.dyn_vel_sensitivity = load_num("dyn_vel_sensitivity", 0.8)
    self.dyn_marker_blending = load_bool("dyn_marker_blending", false)
    self.dyn_bypass_cc = load_bool("dyn_bypass_cc", false)
    self.pedal_default_style = load_str("pedal_default_style", "classic")
    self.dyn_text_template_idx = load_num("dyn_text_template_idx", 1)
    self.dyn_text_line_pattern = load_str("dyn_text_line_pattern", "none")
    self.dyn_text_curve_pattern = load_str("dyn_text_curve_pattern", "linear")
    self.voice_color_mode = load_bool("voice_color_mode", true)
    self.hide_inactive_voices = load_bool("hide_inactive_voices", false)
    self.ghost_voice_opacity = load_num("ghost_voice_opacity", 0.25)
    self.custom_resource_path = load_str("reaper_resource_path", "")

    -- Track Clefs
    local _, raw_clefs = reaper.GetProjExtState(0, "REAPER_Notator", "track_clefs")
    if raw_clefs and raw_clefs ~= "" then
        self.track_clefs = {}
        for entry in raw_clefs:gmatch("([^;]+)") do
            local guid, clef = entry:match("^([^:]+):(.+)$")
            if guid and clef then
                self.track_clefs[guid] = clef
            end
        end
    end

    -- Track Voices (MIDI channels 1-16 per track)
    local _, raw_voices = reaper.GetProjExtState(0, "REAPER_Notator", "track_voices")
    if raw_voices and raw_voices ~= "" then
        self.track_voices = {}
        for entry in raw_voices:gmatch("([^;]+)") do
            local guid, v = entry:match("^([^:]+):(%d+)$")
            if guid and v then
                self.track_voices[guid] = tonumber(v)
            end
        end
    end

    -- Track Articulation Banks
    local ok_ab, ab_json = reaper.GetProjExtState(0, "REAPER_Notator", "track_art_banks")
    if ok_ab == 1 and ab_json and #ab_json > 2 then
        local JsonHelper = package.loaded["services.json_helper"] or require("services.json_helper")
        local ok_dec, dec_ab = pcall(JsonHelper.decode, ab_json)
        if ok_dec and type(dec_ab) == "table" then
            self.track_articulation_banks = dec_ab
        end
    end

    -- Track Key Signatures
    local _, raw_ksigs = reaper.GetProjExtState(0, "REAPER_Notator", "track_key_signatures")
    if raw_ksigs and raw_ksigs ~= "" then
        self.track_key_signatures = {}
        for entry in raw_ksigs:gmatch("([^;]+)") do
            local guid, k_idx, k_mode = entry:match("^([^:]+):(%-?%d+):?(.*)$")
            if guid and k_idx then
                local mode = (k_mode and k_mode ~= "") and k_mode or "major"
                self.track_key_signatures[guid] = { idx = tonumber(k_idx), key_idx = tonumber(k_idx), mode = mode }
            end
        end
    end

    self.custom_colors = {}
    local keys = {"paper_bg", "staff_line", "barline", "notehead_black", "bar_num", "art_text"}
    for _, k in ipairs(keys) do
        local hex = load_num("color_" .. k, nil)
        if hex then
            self.custom_colors[k] = hex
        end
    end
end

function State.save_settings(self)
    local function save_val(key, val)
        local str = tostring(val)
        reaper.SetProjExtState(0, "REAPER_Notator", key, str)
        reaper.SetExtState("REAPER_Notator", key, str, true)
    end

    save_val("scroll_factor", self.scroll_factor or 3.0)
    save_val("bar_num_offset_x", self.bar_num_offset_x or -10.0)
    save_val("bar_num_offset_y", self.bar_num_offset_y or 0.0)
    save_val("bar_num_size", self.bar_num_size or 14.0)
    save_val("dynamics_offset_y", self.dynamics_offset_y or 45.0)
    save_val("hairpins_offset_y", self.dynamics_offset_y or 45.0)
    save_val("pedal_offset_y", self.pedal_offset_y or 75.0)
    save_val("articulations_offset_y", self.articulations_offset_y or 14.0)
    save_val("articulations_font_size", self.articulations_font_size or 17.0)
    save_val("articulations_bold", self.articulations_bold ~= false)
    save_val("track_spacing", self.track_spacing or 70.0)
    save_val("show_item_boxes", self.show_item_boxes ~= false)
    save_val("item_box_intensity", self.item_box_intensity or 25)
    save_val("sticky_track_headers", self.sticky_track_headers ~= false)
    save_val("show_track_headers", self.show_track_headers ~= false)
    save_val("show_bar_numbers", self.show_bar_numbers ~= false)
    save_val("show_dynamics_layer", self.show_dynamics_layer ~= false)
    save_val("show_articulations_layer", self.show_articulations_layer ~= false)
    save_val("show_hairpins_layer", self.show_hairpins_layer ~= false)
    save_val("show_tempo_layer", self.show_tempo_layer ~= false)
    save_val("show_octaves_layer", self.show_octaves_layer ~= false)
    save_val("show_tuplets_layer", self.show_tuplets_layer ~= false)
    save_val("show_key_signatures", self.show_key_signatures == true)
    save_val("key_signature", self.key_signature or 0)
    save_val("key_signature_mode", self.key_signature_mode or "major")
    save_val("show_text_items_layer", self.show_text_items_layer ~= false)
    save_val("show_pedal_layer", self.show_pedal_layer ~= false)
    save_val("show_dynamic_texts_layer", self.show_dynamic_texts_layer ~= false)
    save_val("show_chord_lane", self.show_chord_lane ~= false)
    save_val("audition_notes", self.audition_notes ~= false)
    save_val("audition_volume", math.floor(self.audition_volume or 50))
    save_val("tempo_offset_y", self.tempo_offset_y or 28.0)
    save_val("octave_offset_y", self.octave_offset_y or 18.0)
    save_val("invert_mode", self.invert_mode == true)
    save_val("tempo_drawer_presets_h", math.floor(self.tempo_drawer_presets_h or 220))
    save_val("clef_drawer_h1", math.floor(self.clef_drawer_h1 or 180))
    save_val("clef_drawer_h2", math.floor(self.clef_drawer_h2 or 180))
    save_val("clef_drawer_h3", math.floor(self.clef_drawer_h3 or 140))
    save_val("view_mode", self.view_mode or "auto")
    save_val("zoom", string.format("%.2f", self.zoom or 1.0))
    save_val("grid_qn", self.grid_qn or 0.5)
    save_val("grid_label", self.grid_label or "1/8")
    save_val("display_quantize", self.display_quantize == true)
    save_val("display_quantize_grid", self.display_quantize_grid or 1.0)
    save_val("display_quantize_label", self.display_quantize_label or "1/4")
    save_val("beam_grouping", self.beam_grouping or "beat")
    save_val("dyn_cc_a", self.dyn_cc_a or 1)
    save_val("dyn_cc_b", self.dyn_cc_b or 11)
    save_val("dyn_phrasing_active", self.dyn_phrasing_active ~= false)
    save_val("dyn_phrasing_intensity", self.dyn_phrasing_intensity or 0.5)
    save_val("dyn_humanize_intensity", self.dyn_humanize_intensity or 0.3)
    save_val("dyn_stress_factor", self.dyn_stress_factor or 0.5)
    save_val("dyn_bow_intensity", self.dyn_bow_intensity or 0.0)
    save_val("dyn_bow_pos", self.dyn_bow_pos or 0.5)
    save_val("dyn_vel_sensitivity", self.dyn_vel_sensitivity or 0.8)
    save_val("dyn_marker_blending", self.dyn_marker_blending == true)
    save_val("dyn_bypass_cc", self.dyn_bypass_cc == true)
    save_val("pedal_default_style", self.pedal_default_style or "classic")
    save_val("dyn_text_template_idx", self.dyn_text_template_idx or 1)
    save_val("dyn_text_line_pattern", self.dyn_text_line_pattern or "none")
    save_val("dyn_text_curve_pattern", self.dyn_text_curve_pattern or "linear")
    save_val("voice_color_mode", self.voice_color_mode ~= false)
    save_val("hide_inactive_voices", self.hide_inactive_voices == true)
    save_val("ghost_voice_opacity", self.ghost_voice_opacity or 0.25)
    save_val("reaper_resource_path", self.custom_resource_path or "")

    -- Track Clefs
    if self.track_clefs then
        local parts = {}
        for guid, clef in pairs(self.track_clefs) do
            table.insert(parts, guid .. ":" .. tostring(clef))
        end
        local raw_clefs = table.concat(parts, ";")
        reaper.SetProjExtState(0, "REAPER_Notator", "track_clefs", raw_clefs)
    end

    -- Track Voices
    if self.track_voices then
        local parts = {}
        for guid, v in pairs(self.track_voices) do
            table.insert(parts, guid .. ":" .. tostring(v))
        end
        local raw_voices = table.concat(parts, ";")
        reaper.SetProjExtState(0, "REAPER_Notator", "track_voices", raw_voices)
    end

    -- Track Articulation Banks
    if self.track_articulation_banks and next(self.track_articulation_banks) then
        local JsonHelper = package.loaded["services.json_helper"] or require("services.json_helper")
        reaper.SetProjExtState(0, "REAPER_Notator", "track_art_banks", JsonHelper.encode(self.track_articulation_banks))
    end

    -- Track Key Signatures
    if self.track_key_signatures then
        local parts = {}
        for guid, ksig in pairs(self.track_key_signatures) do
            if type(ksig) == "table" then
                table.insert(parts, string.format("%s:%d:%s", guid, ksig.idx or ksig.key_idx or 0, ksig.mode or "major"))
            elseif type(ksig) == "string" and ksig:find(":") then
                table.insert(parts, guid .. ":" .. ksig)
            else
                table.insert(parts, string.format("%s:%d:major", guid, tonumber(ksig) or 0))
            end
        end
        local raw_ksigs = table.concat(parts, ";")
        reaper.SetProjExtState(0, "REAPER_Notator", "track_key_signatures", raw_ksigs)
    end

    local keys = {"paper_bg", "staff_line", "barline", "notehead_black", "bar_num", "art_text"}
    for _, k in ipairs(keys) do
        local hex = self.custom_colors and self.custom_colors[k]
        if hex then
            save_val("color_" .. k, hex)
        else
            reaper.SetProjExtState(0, "REAPER_Notator", "color_" .. k, "")
            reaper.DeleteExtState("REAPER_Notator", "color_" .. k, true)
        end
    end

    if reaper.MarkProjectDirty then
        reaper.MarkProjectDirty(0)
    end
    if reaper.Main_UpdateLoopInfo then
        reaper.Main_UpdateLoopInfo(0)
    end
end

function State:set_input_mode(mode)
    if mode == "step" then
        self.input_mode_type = "step"
        self.input_mode = true
        self.draw_preview = nil
        self.status_msg = "Step Input active (Keys C, D, E, F, G, A, B insert notes at cursor)"
    elseif mode == "draw" then
        self.input_mode_type = "draw"
        self.input_mode = false
        self.status_msg = "Write Notes active (Click on staff to place note) [Hotkeys: 2-7 note value, D/Esc to exit]"
    else
        self.input_mode_type = "select"
        self.input_mode = false
        self.draw_preview = nil
        self.status_msg = "Selection mode active"
    end
end

return State

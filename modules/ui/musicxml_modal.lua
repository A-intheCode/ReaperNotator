-- ==============================================================================
-- REAPER Native Notator - UI: MusicXmlModal
-- Interactive Modal Dialog for MusicXML 3.1 / 4.0 Import and Export.
-- Features:
--   - Export Tab: Full track selection, item preservation, chord track pitch
--     fidelity, <harmony> tags, text items, dynamics, hairpins, octave shifts.
--   - Import Tab: File browser, track generation, note insertion, score
--     element reconstruction (chords, texts, dynamics, hairpins, keys).
-- ==============================================================================

local MusicXmlExportService = require("services.musicxml_export_service")
local MusicXmlImportService = require("services.musicxml_import_service")
local PathService            = require("services.path_service")

local MusicXmlModal = {}

-- Local state for modal
local export_file_path = ""
local import_file_path = ""
local export_scope = "active" -- "active" | "all" | "selected"
local opt_include_chords = true
local opt_include_texts = true
local opt_include_dynamics = true
local opt_include_octaves_pedals = true

local opt_create_new_tracks = true
local opt_import_chords = true
local opt_import_texts = true
local opt_import_dynamics = true
local opt_import_keys = true

local status_msg = ""
local status_color = 0xFFFFFFFF

-- Helper to resolve default export path
local function get_default_export_path()
    local _, proj_fn = reaper.EnumProjects(-1, "")
    if proj_fn and proj_fn ~= "" then
        local norm = proj_fn:gsub("\\", "/")
        local base = norm:gsub("%.rpp$", ""):gsub("%.RPP$", "")
        return base .. ".musicxml"
    end
    local s_dir = PathService.get_script_dir()
    return s_dir .. "/export_score.musicxml"
end

function MusicXmlModal.render(ctx, state, project_tracks)
    if not state.show_musicxml_modal then return end

    if export_file_path == "" then
        export_file_path = get_default_export_path()
    end

    reaper.ImGui_SetNextWindowSize(ctx, 680, 520, reaper.ImGui_Cond_FirstUseEver())
    local win_flags = reaper.ImGui_WindowFlags_NoCollapse()
    local is_vis, is_open = reaper.ImGui_Begin(ctx, "🎼 MusicXML Import & Export###MusicXmlModal", true, win_flags)

    if not is_open then
        state.show_musicxml_modal = false
        reaper.ImGui_End(ctx)
        return
    end

    if is_vis then
        if reaper.ImGui_BeginTabBar(ctx, "MusicXmlTabs") then
            -- ==================================================================
            -- TAB 1: EXPORT MUSICXML
            -- ==================================================================
            if reaper.ImGui_BeginTabItem(ctx, "📤 Export MusicXML") then
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_TextColored(ctx, 0xFF9F1CFF, "Export Score to standard MusicXML (v4.0 Partwise)")
                reaper.ImGui_TextWrapped(ctx, "Preserves all custom and transformed chord-track pitches exactly as played and displayed, alongside <harmony> lead-sheet symbols, text annotations, dynamics, hairpins, and key signatures.")
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                -- Track Scope
                reaper.ImGui_Text(ctx, "Track Scope:")
                if reaper.ImGui_RadioButton(ctx, "Active Visible Tracks##ScopeActive", export_scope == "active") then
                    export_scope = "active"
                end
                reaper.ImGui_SameLine(ctx, 0, 16)
                if reaper.ImGui_RadioButton(ctx, "All Project MIDI Tracks##ScopeAll", export_scope == "all") then
                    export_scope = "all"
                end
                reaper.ImGui_SameLine(ctx, 0, 16)
                if reaper.ImGui_RadioButton(ctx, "Selected Tracks Only##ScopeSel", export_scope == "selected") then
                    export_scope = "selected"
                end

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                -- Element Checkboxes
                reaper.ImGui_Text(ctx, "Include Elements:")
                local _, c1 = reaper.ImGui_Checkbox(ctx, "Chord & Scale Lane (<harmony> symbols & custom pitches)", opt_include_chords)
                opt_include_chords = c1
                local _, c2 = reaper.ImGui_Checkbox(ctx, "Text Items (<words> annotations & titles)", opt_include_texts)
                opt_include_texts = c2
                local _, c3 = reaper.ImGui_Checkbox(ctx, "Dynamics & Hairpins (<dynamics>, <wedge>)", opt_include_dynamics)
                opt_include_dynamics = c3
                local _, c4 = reaper.ImGui_Checkbox(ctx, "Octave Lines & Pedals (<octave-shift>, <pedal>)", opt_include_octaves_pedals)
                opt_include_octaves_pedals = c4

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                -- Target File Path
                reaper.ImGui_Text(ctx, "Export File Path:")
                local _, new_path = reaper.ImGui_InputText(ctx, "##ExportPath", export_file_path)
                export_file_path = new_path

                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "Browse...##BrowseExport") then
                    local ok, file_picked = reaper.GetUserFileNameForRead(export_file_path, "Save MusicXML File", "musicxml")
                    if ok and file_picked and file_picked ~= "" then
                        export_file_path = file_picked
                    end
                end

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Spacing(ctx)

                -- Export Action Button
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x27AE60FF)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x2ECC71FF)
                if reaper.ImGui_Button(ctx, "📤 Export MusicXML Now", 220, 36) then
                    -- Collect tracks based on scope
                    local export_tracks = {}
                    if export_scope == "active" then
                        local src_tracks = state.active_tracks_cache or project_tracks or {}
                        for _, te in ipairs(src_tracks) do
                            local tr = (type(te) == "table" and te.track) or te
                            if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
                                table.insert(export_tracks, tr)
                            end
                        end
                    elseif export_scope == "selected" then
                        local sel_cnt = reaper.CountSelectedTracks(0)
                        for si = 0, sel_cnt - 1 do
                            table.insert(export_tracks, reaper.GetSelectedTrack(0, si))
                        end
                    else
                        local num_tr = reaper.CountTracks(0)
                        for ti = 0, num_tr - 1 do
                            local tr = reaper.GetTrack(0, ti)
                            if reaper.CountTrackMediaItems(tr) > 0 then
                                table.insert(export_tracks, tr)
                            end
                        end
                    end

                    -- Fallback: If empty, export all project tracks with media items
                    if #export_tracks == 0 and project_tracks then
                        for _, te in ipairs(project_tracks) do
                            local tr = (type(te) == "table" and te.track) or te
                            if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
                                table.insert(export_tracks, tr)
                            end
                        end
                    end

                    local ok, res, num_meas, num_trks = MusicXmlExportService.export_project(state, {
                        file_path = export_file_path,
                        tracks = export_tracks,
                        include_chords = opt_include_chords,
                        include_text_items = opt_include_texts,
                        include_dynamics = opt_include_dynamics,
                        include_hairpins = opt_include_dynamics,
                        include_octaves = opt_include_octaves_pedals,
                        include_pedals = opt_include_octaves_pedals
                    })

                    if ok then
                        status_msg = string.format("Exported successfully! %d tracks, %d measures to:\n%s", num_trks or #export_tracks, num_meas or 0, res)
                        status_color = 0x2ECC71FF
                    else
                        status_msg = "Export failed: " .. tostring(res)
                        status_color = 0xE74C3CFF
                    end
                end
                reaper.ImGui_PopStyleColor(ctx, 2)

                reaper.ImGui_EndTabItem(ctx)
            end

            -- ==================================================================
            -- TAB 2: IMPORT MUSICXML
            -- ==================================================================
            if reaper.ImGui_BeginTabItem(ctx, "📥 Import MusicXML") then
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_TextColored(ctx, 0x3498DBFF, "Import standard MusicXML (.musicxml / .xml)")
                reaper.ImGui_TextWrapped(ctx, "Parses parts into REAPER tracks, takes, MIDI notes, and automatically reconstructs chord lanes, text items, dynamics, hairpins, and key signatures.")
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                -- Import Source File
                reaper.ImGui_Text(ctx, "Source MusicXML File:")
                local _, new_imp_path = reaper.ImGui_InputText(ctx, "##ImportPath", import_file_path)
                import_file_path = new_imp_path

                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "Browse...##BrowseImport") then
                    local ok, file_picked = reaper.GetUserFileNameForRead("", "Select MusicXML File to Import", "musicxml")
                    if ok and file_picked and file_picked ~= "" then
                        import_file_path = file_picked
                    end
                end

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)

                -- Import Options
                reaper.ImGui_Text(ctx, "Import Options:")
                local _, i1 = reaper.ImGui_Checkbox(ctx, "Create New Tracks for each Part##ImpNewTracks", opt_create_new_tracks)
                opt_create_new_tracks = i1
                local _, i2 = reaper.ImGui_Checkbox(ctx, "Import Chords into Chord & Scale Lane (<harmony>)##ImpChords", opt_import_chords)
                opt_import_chords = i2
                local _, i3 = reaper.ImGui_Checkbox(ctx, "Import Text Items (<words>)##ImpTexts", opt_import_texts)
                opt_import_texts = i3
                local _, i4 = reaper.ImGui_Checkbox(ctx, "Import Dynamics & Hairpins##ImpDyns", opt_import_dynamics)
                opt_import_dynamics = i4
                local _, i5 = reaper.ImGui_Checkbox(ctx, "Import Key & Time Signatures##ImpKeys", opt_import_keys)
                opt_import_keys = i5

                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Spacing(ctx)

                -- Import Action Button
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2980B9FF)
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x3498DBFF)
                if reaper.ImGui_Button(ctx, "📥 Import MusicXML Now", 220, 36) then
                    package.loaded["services.musicxml_import_service"] = nil
                    package.loaded["rendering.engraver"] = nil
                    package.loaded["rendering.score_canvas"] = nil
                    package.loaded["services.dynamics_engine"] = nil
                    package.loaded["services.hairpin_service"] = nil
                    MusicXmlImportService = require("services.musicxml_import_service")
                    local ok, res, notes_cnt, trks_cnt = MusicXmlImportService.import_file(import_file_path, state, {
                        create_new_tracks = opt_create_new_tracks,
                        import_chords = opt_import_chords,
                        import_text_items = opt_import_texts,
                        import_dynamics = opt_import_dynamics,
                        import_octaves = opt_import_dynamics,
                        import_pedals = opt_import_dynamics,
                        import_keys = opt_import_keys
                    })

                    if ok then
                        status_msg = string.format("Import successful! %d tracks created/updated, %d notes imported.", trks_cnt or 0, notes_cnt or 0)
                        status_color = 0x2ECC71FF
                    else
                        status_msg = "Import failed: " .. tostring(res)
                        status_color = 0xE74C3CFF
                    end
                end
                reaper.ImGui_PopStyleColor(ctx, 2)

                reaper.ImGui_EndTabItem(ctx)
            end

            reaper.ImGui_EndTabBar(ctx)
        end

        -- Status message bar at bottom
        if status_msg and status_msg ~= "" then
            reaper.ImGui_Spacing(ctx)
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_TextColored(ctx, status_color, status_msg)
        end

        reaper.ImGui_End(ctx)
    end
end

return MusicXmlModal

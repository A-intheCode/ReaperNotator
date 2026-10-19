-- ==============================================================================
-- REAPER Native Notator - Service: ImGuiGuardService
-- Global ReaImGui Stack Guard & Auto-Unwinder
-- Guarantees that no Lua runtime error or early return can ever leave an
-- unclosed ImGui_BeginChild, ImGui_Begin, ImGui_BeginPopup, ImGui_BeginCombo,
-- ImGui_BeginMenu, ImGui_BeginDisabled, ImGui_PushStyleColor, or ImGui_PushStyleVar
-- on the ReaImGui context stack ("Missing EndChild()" / "Missing End()" prevention).
-- ==============================================================================

local ImGuiGuardService = {}

ImGuiGuardService._installed = false
ImGuiGuardService._stacks_by_ctx = {}
ImGuiGuardService._error_log = {}

local function new_scope(scope_type, label)
    return {
        type = scope_type or "root",
        label = label or "",
        style_colors = 0,
        style_vars = 0,
        disabled = 0,
        combos = 0,
        popups = 0,
        menus = 0,
    }
end

function ImGuiGuardService.get_stack(ctx)
    local key = tostring(ctx or "default_ctx")
    local st = ImGuiGuardService._stacks_by_ctx[key]
    if not st then
        st = { new_scope("root", "root") }
        ImGuiGuardService._stacks_by_ctx[key] = st
    end
    return st
end

function ImGuiGuardService.reset_stack(ctx)
    local key = tostring(ctx or "default_ctx")
    ImGuiGuardService._stacks_by_ctx[key] = { new_scope("root", "root") }
end

local function unwind_scope_internals(r, ctx, scope, target_menus, target_combos, target_popups, target_disabled, target_vars, target_colors)
    target_menus = target_menus or 0
    target_combos = target_combos or 0
    target_popups = target_popups or 0
    target_disabled = target_disabled or 0
    target_vars = target_vars or 0
    target_colors = target_colors or 0

    local orig = ImGuiGuardService._orig
    if not orig then return end

    while (scope.menus or 0) > target_menus do
        scope.menus = scope.menus - 1
        if orig.EndMenu then pcall(orig.EndMenu, ctx) end
    end
    while (scope.combos or 0) > target_combos do
        scope.combos = scope.combos - 1
        if orig.EndCombo then pcall(orig.EndCombo, ctx) end
    end
    while (scope.popups or 0) > target_popups do
        scope.popups = scope.popups - 1
        if orig.EndPopup then pcall(orig.EndPopup, ctx) end
    end
    while (scope.disabled or 0) > target_disabled do
        scope.disabled = scope.disabled - 1
        if orig.EndDisabled then pcall(orig.EndDisabled, ctx) end
    end
    if (scope.style_vars or 0) > target_vars then
        local diff = scope.style_vars - target_vars
        scope.style_vars = target_vars
        if orig.PopStyleVar then pcall(orig.PopStyleVar, ctx, diff) end
    end
    if (scope.style_colors or 0) > target_colors then
        local diff = scope.style_colors - target_colors
        scope.style_colors = target_colors
        if orig.PopStyleColor then pcall(orig.PopStyleColor, ctx, diff) end
    end
end

local function decrement_counter_in_stack(stack, field, amount)
    local rem = amount or 1
    for i = #stack, 1, -1 do
        local sc = stack[i]
        local avail = sc[field] or 0
        if avail > 0 then
            local take = math.min(avail, rem)
            sc[field] = avail - take
            rem = rem - take
            if rem <= 0 then break end
        end
    end
end

function ImGuiGuardService.install(r)
    r = r or reaper
    if not r then return false end
    if ImGuiGuardService._installed and ImGuiGuardService._reaper_ref == r then
        return true
    end

    local orig = {
        Begin = r.ImGui_Begin,
        End = r.ImGui_End,
        BeginChild = r.ImGui_BeginChild,
        EndChild = r.ImGui_EndChild,
        BeginPopup = r.ImGui_BeginPopup,
        BeginPopupModal = r.ImGui_BeginPopupModal,
        BeginPopupContextItem = r.ImGui_BeginPopupContextItem,
        BeginPopupContextWindow = r.ImGui_BeginPopupContextWindow,
        EndPopup = r.ImGui_EndPopup,
        BeginCombo = r.ImGui_BeginCombo,
        EndCombo = r.ImGui_EndCombo,
        BeginMenu = r.ImGui_BeginMenu,
        EndMenu = r.ImGui_EndMenu,
        BeginDisabled = r.ImGui_BeginDisabled,
        EndDisabled = r.ImGui_EndDisabled,
        PushStyleColor = r.ImGui_PushStyleColor,
        PopStyleColor = r.ImGui_PopStyleColor,
        PushStyleVar = r.ImGui_PushStyleVar,
        PopStyleVar = r.ImGui_PopStyleVar,
    }
    ImGuiGuardService._orig = orig
    ImGuiGuardService._reaper_ref = r
    ImGuiGuardService._installed = true

    if orig.Begin then
        r.ImGui_Begin = function(ctx, name, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            table.insert(stack, new_scope("window", tostring(name or "Window")))
            return orig.Begin(ctx, name, ...)
        end
    end

    if orig.End then
        r.ImGui_End = function(ctx, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            -- Auto-close any orphaned child scopes inside this window before calling ImGui_End!
            while #stack > 1 and stack[#stack].type == "child" do
                local child_sc = table.remove(stack)
                unwind_scope_internals(r, ctx, child_sc, 0, 0, 0, 0, 0, 0)
                if orig.EndChild then pcall(orig.EndChild, ctx) end
            end
            if #stack > 1 and stack[#stack].type == "window" then
                local win_sc = table.remove(stack)
                unwind_scope_internals(r, ctx, win_sc, 0, 0, 0, 0, 0, 0)
            end
            return orig.End(ctx, ...)
        end
    end

    if orig.BeginChild then
        r.ImGui_BeginChild = function(ctx, id, ...)
            local vis = orig.BeginChild(ctx, id, ...)
            if vis then
                local stack = ImGuiGuardService.get_stack(ctx)
                table.insert(stack, new_scope("child", tostring(id or "Child")))
            end
            return vis
        end
    end

    if orig.EndChild then
        r.ImGui_EndChild = function(ctx, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            if #stack > 1 and stack[#stack].type == "child" then
                local child_sc = table.remove(stack)
                unwind_scope_internals(r, ctx, child_sc, 0, 0, 0, 0, 0, 0)
                return orig.EndChild(ctx, ...)
            end
        end
    end

    if orig.BeginPopup then
        r.ImGui_BeginPopup = function(ctx, ...)
            local open = orig.BeginPopup(ctx, ...)
            if open then
                local stack = ImGuiGuardService.get_stack(ctx)
                local top = stack[#stack]
                top.popups = (top.popups or 0) + 1
            end
            return open
        end
    end

    if orig.BeginPopupModal then
        r.ImGui_BeginPopupModal = function(ctx, ...)
            local vis, open = orig.BeginPopupModal(ctx, ...)
            if vis then
                local stack = ImGuiGuardService.get_stack(ctx)
                local top = stack[#stack]
                top.popups = (top.popups or 0) + 1
            end
            return vis, open
        end
    end

    if orig.BeginPopupContextItem then
        r.ImGui_BeginPopupContextItem = function(ctx, ...)
            local open = orig.BeginPopupContextItem(ctx, ...)
            if open then
                local stack = ImGuiGuardService.get_stack(ctx)
                local top = stack[#stack]
                top.popups = (top.popups or 0) + 1
            end
            return open
        end
    end

    if orig.BeginPopupContextWindow then
        r.ImGui_BeginPopupContextWindow = function(ctx, ...)
            local open = orig.BeginPopupContextWindow(ctx, ...)
            if open then
                local stack = ImGuiGuardService.get_stack(ctx)
                local top = stack[#stack]
                top.popups = (top.popups or 0) + 1
            end
            return open
        end
    end

    if orig.EndPopup then
        r.ImGui_EndPopup = function(ctx, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            decrement_counter_in_stack(stack, "popups", 1)
            return orig.EndPopup(ctx, ...)
        end
    end

    if orig.BeginCombo then
        r.ImGui_BeginCombo = function(ctx, ...)
            local open = orig.BeginCombo(ctx, ...)
            if open then
                local stack = ImGuiGuardService.get_stack(ctx)
                local top = stack[#stack]
                top.combos = (top.combos or 0) + 1
            end
            return open
        end
    end

    if orig.EndCombo then
        r.ImGui_EndCombo = function(ctx, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            decrement_counter_in_stack(stack, "combos", 1)
            return orig.EndCombo(ctx, ...)
        end
    end

    if orig.BeginMenu then
        r.ImGui_BeginMenu = function(ctx, ...)
            local open = orig.BeginMenu(ctx, ...)
            if open then
                local stack = ImGuiGuardService.get_stack(ctx)
                local top = stack[#stack]
                top.menus = (top.menus or 0) + 1
            end
            return open
        end
    end

    if orig.EndMenu then
        r.ImGui_EndMenu = function(ctx, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            decrement_counter_in_stack(stack, "menus", 1)
            return orig.EndMenu(ctx, ...)
        end
    end

    if orig.BeginDisabled then
        r.ImGui_BeginDisabled = function(ctx, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            local top = stack[#stack]
            top.disabled = (top.disabled or 0) + 1
            return orig.BeginDisabled(ctx, ...)
        end
    end

    if orig.EndDisabled then
        r.ImGui_EndDisabled = function(ctx, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            decrement_counter_in_stack(stack, "disabled", 1)
            return orig.EndDisabled(ctx, ...)
        end
    end

    if orig.PushStyleColor then
        r.ImGui_PushStyleColor = function(ctx, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            local top = stack[#stack]
            top.style_colors = (top.style_colors or 0) + 1
            return orig.PushStyleColor(ctx, ...)
        end
    end

    if orig.PopStyleColor then
        r.ImGui_PopStyleColor = function(ctx, count, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            decrement_counter_in_stack(stack, "style_colors", count or 1)
            return orig.PopStyleColor(ctx, count, ...)
        end
    end

    if orig.PushStyleVar then
        r.ImGui_PushStyleVar = function(ctx, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            local top = stack[#stack]
            top.style_vars = (top.style_vars or 0) + 1
            return orig.PushStyleVar(ctx, ...)
        end
    end

    if orig.PopStyleVar then
        r.ImGui_PopStyleVar = function(ctx, count, ...)
            local stack = ImGuiGuardService.get_stack(ctx)
            decrement_counter_in_stack(stack, "style_vars", count or 1)
            return orig.PopStyleVar(ctx, count, ...)
        end
    end

    return true
end

function ImGuiGuardService.snapshot(ctx)
    local stack = ImGuiGuardService.get_stack(ctx)
    local top = stack[#stack]
    return {
        depth = #stack,
        menus = top.menus or 0,
        combos = top.combos or 0,
        popups = top.popups or 0,
        disabled = top.disabled or 0,
        style_vars = top.style_vars or 0,
        style_colors = top.style_colors or 0,
    }
end

function ImGuiGuardService.unwind_to_snapshot(ctx, snap)
    local r = ImGuiGuardService._reaper_ref or reaper
    local orig = ImGuiGuardService._orig
    if not r or not orig or not snap then return end

    local stack = ImGuiGuardService.get_stack(ctx)
    local target_depth = math.max(1, snap.depth or 1)

    while #stack > target_depth do
        local sc = table.remove(stack)
        unwind_scope_internals(r, ctx, sc, 0, 0, 0, 0, 0, 0)
        if sc.type == "child" and orig.EndChild then
            pcall(orig.EndChild, ctx)
        elseif sc.type == "window" and orig.End then
            pcall(orig.End, ctx)
        end
    end

    local top = stack[#stack]
    if top then
        unwind_scope_internals(
            r,
            ctx,
            top,
            snap.menus or 0,
            snap.combos or 0,
            snap.popups or 0,
            snap.disabled or 0,
            snap.style_vars or 0,
            snap.style_colors or 0
        )
    end
end

function ImGuiGuardService.safe_render(ctx, state, label, fn, ...)
    if type(fn) ~= "function" then return false end
    if not ImGuiGuardService._installed then
        ImGuiGuardService.install(reaper)
    end
    local snap = ImGuiGuardService.snapshot(ctx)
    local ok, res = pcall(fn, ...)
    ImGuiGuardService.unwind_to_snapshot(ctx, snap)
    if not ok then
        local msg = string.format("[%s Error] %s", tostring(label or "UI"), tostring(res))
        if type(state) == "table" then
            state.status_msg = msg
        end
        if reaper and reaper.ShowConsoleMsg and not ImGuiGuardService._error_log[msg] then
            ImGuiGuardService._error_log[msg] = true
            reaper.ShowConsoleMsg(msg .. "\n")
        end
    end
    return ok, res
end

return ImGuiGuardService


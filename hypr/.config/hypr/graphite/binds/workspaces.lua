-- Bind group "workspaces": switching. Port of `##! Workspace` in hyprland/keybinds.conf.

return function(ctx)
    local C = ctx.core
    local D = hl.dsp
    local function ws(w) return D.focus({ workspace = w }) end

    local list = {}
    -- focus workspace 1..10 in the current group of 10, on the focused monitor
    local row = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    local pad = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    for i = 1, 10 do
        list[#list + 1] = { "SUPER + code:" .. row[i], C.workspace_action("workspace", i), desc = "Go to desktop " .. i }
    end
    for i = 1, 10 do -- keypad: bindp (works even while shortcuts are inhibited)
        list[#list + 1] = { "SUPER + code:" .. pad[i], C.workspace_action("workspace", i), dont_inhibit = true, desc = "Go to desktop " .. i }
    end

    local tail = {
        { "CTRL + SUPER + Right", ws("r+1"), desc = "Next desktop on monitor" },
        { "CTRL + SUPER + Left", ws("r-1"), desc = "Previous desktop on monitor" },
        { "CTRL + SUPER + ALT + Right", ws("m+1"), desc = "Next open desktop on monitor" },
        { "CTRL + SUPER + ALT + Left", ws("m-1"), desc = "Previous open desktop on monitor" },
        { "SUPER + Page_Down", ws("+1"), desc = "Next desktop" },
        { "SUPER + Page_Up", ws("-1"), desc = "Previous desktop" },
        { "CTRL + SUPER + Page_Down", ws("r+1"), desc = "Next desktop on monitor" },
        { "CTRL + SUPER + Page_Up", ws("r-1"), desc = "Previous desktop on monitor" },
        { "SUPER + mouse_up", ws("+1"), desc = "Next desktop" },
        { "SUPER + mouse_down", ws("-1"), desc = "Previous desktop" },
        { "CTRL + SUPER + mouse_up", ws("r+1"), desc = "Next desktop on monitor" },
        { "CTRL + SUPER + mouse_down", ws("r-1"), desc = "Previous desktop on monitor" },
        -- special
        { "SUPER + S", D.workspace.toggle_special(), desc = "Toggle scratchpad" },
        { "SUPER + mouse:275", D.workspace.toggle_special(), desc = "Toggle scratchpad" },
        { "CTRL + SUPER + BracketLeft", ws("-1"), desc = "Previous desktop" },
        { "CTRL + SUPER + BracketRight", ws("+1"), desc = "Next desktop" },
        { "CTRL + SUPER + Up", ws("r-5"), desc = "Jump 5 desktops back" },
        { "CTRL + SUPER + Down", ws("r+5"), desc = "Jump 5 desktops forward" },
    }
    for _, b in ipairs(tail) do list[#list + 1] = b end
    return list
end

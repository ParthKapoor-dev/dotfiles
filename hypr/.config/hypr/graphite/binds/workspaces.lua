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
        list[#list + 1] = { "SUPER + code:" .. row[i], C.workspace_action("workspace", i) }
    end
    for i = 1, 10 do -- keypad: bindp (works even while shortcuts are inhibited)
        list[#list + 1] = { "SUPER + code:" .. pad[i], C.workspace_action("workspace", i), dont_inhibit = true }
    end

    local tail = {
        { "CTRL + SUPER + Right", ws("r+1") },
        { "CTRL + SUPER + Left", ws("r-1") },
        { "CTRL + SUPER + ALT + Right", ws("m+1") },
        { "CTRL + SUPER + ALT + Left", ws("m-1") },
        { "SUPER + Page_Down", ws("+1") },
        { "SUPER + Page_Up", ws("-1") },
        { "CTRL + SUPER + Page_Down", ws("r+1") },
        { "CTRL + SUPER + Page_Up", ws("r-1") },
        { "SUPER + mouse_up", ws("+1") },
        { "SUPER + mouse_down", ws("-1") },
        { "CTRL + SUPER + mouse_up", ws("r+1") },
        { "CTRL + SUPER + mouse_down", ws("r-1") },
        -- special
        { "SUPER + S", D.workspace.toggle_special() }, -- toggle scratchpad
        { "SUPER + mouse:275", D.workspace.toggle_special() },
        { "CTRL + SUPER + BracketLeft", ws("-1") },
        { "CTRL + SUPER + BracketRight", ws("+1") },
        { "CTRL + SUPER + Up", ws("r-5") },
        { "CTRL + SUPER + Down", ws("r+5") },
    }
    for _, b in ipairs(tail) do list[#list + 1] = b end
    return list
end

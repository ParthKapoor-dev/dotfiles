-- Bind group "windows": focus, move, close, layout, float/fullscreen/pin, send to
-- workspace, scratchpad. Port of the `##! Window` section of hyprland/keybinds.conf
-- (+ "Cursed stuff" resize).
--
-- Removed by the 2026-10-17 Fixes (custom/keybinds.conf `unbind`), kept here
-- disabled for the record:
--   SUPER + Semicolon / Apostrophe -> splitratio -/+0.1 (jcode launchers own these keys)

local L = require("graphite.layouts")

return function(ctx)
    local C, S = ctx.core, ctx.settings
    local D = hl.dsp
    local W = D.window

    local list = {
        -- mouse
        { "SUPER + mouse:272", W.drag(), desc = "Move window (drag)" },
        { "SUPER + mouse:274", W.drag(), desc = "Move window (drag)" },
        { "SUPER + mouse:273", W.resize(), desc = "Resize window (drag)" },

        -- focus in direction
        { "SUPER + Left", D.focus({ direction = "l" }), desc = "Focus window left" },
        { "SUPER + Right", D.focus({ direction = "r" }), desc = "Focus window right" },
        { "SUPER + Up", D.focus({ direction = "u" }), desc = "Focus window up" },
        { "SUPER + Down", D.focus({ direction = "d" }), desc = "Focus window down" },
        { "SUPER + BracketLeft", D.focus({ direction = "l" }), desc = "Focus window left" },
        { "SUPER + BracketRight", D.focus({ direction = "r" }), desc = "Focus window right" },

        -- move in direction
        { "SUPER + SHIFT + Left", W.move({ direction = "l" }), desc = "Move window left" },
        { "SUPER + SHIFT + Right", W.move({ direction = "r" }), desc = "Move window right" },
        { "SUPER + SHIFT + Up", W.move({ direction = "u" }), desc = "Move window up" },
        { "SUPER + SHIFT + Down", W.move({ direction = "d" }), desc = "Move window down" },

        { "ALT + F4", W.close(), desc = "Close window" },
        { "SUPER + Q", W.close(), desc = "Close window" },
        { "SUPER + SHIFT + ALT + Q", D.exec_cmd("hyprctl kill"), desc = "Force kill window (click to pick)" },

        -- split ratio: unbound by the 2026-10-17 Fixes (see header)
        { "SUPER + Semicolon", D.layout("splitratio -0.1"), repeating = true, desc = "Shrink split", enabled = false },
        { "SUPER + Apostrophe", D.layout("splitratio +0.1"), repeating = true, desc = "Grow split", enabled = false },

        -- layout cycling through settings.layouts (graphite/layouts.lua); dwindle's
        -- togglesplit moved from Super+\ to Super+Alt+\
        { "SUPER + Backslash", L.bind_fn(C, S, 1), desc = "Next layout" },
        { "SUPER + SHIFT + Backslash", L.bind_fn(C, S, -1), desc = "Previous layout" },
        { "SUPER + ALT + Backslash", D.layout("togglesplit"), desc = "Toggle split direction (dwindle)" },
        { "SUPER + ALT + Space", W.float({ action = "toggle" }), desc = "Toggle floating window" },
        { "SUPER + D", W.fullscreen({ mode = "maximized" }), desc = "Maximize window" },
        { "SUPER + F", W.fullscreen({ mode = "fullscreen" }), desc = "Fullscreen window" },
        { "SUPER + ALT + F", W.fullscreen_state({ internal = 0, client = 3, action = "toggle" }), desc = "Fake fullscreen (window keeps its size)" },
        { "SUPER + P", W.pin(), desc = "Pin window" },
    }

    -- send to workspace 1..10 (number row + keypad; raw keycodes for any layout)
    local row = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    local pad = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    for i = 1, 10 do
        list[#list + 1] = { "SUPER + SHIFT + code:" .. row[i], C.workspace_action("movetoworkspace", i), desc = "Move window to desktop " .. i }
    end
    for i = 1, 10 do
        list[#list + 1] = { "SUPER + SHIFT + code:" .. pad[i], C.workspace_action("movetoworkspace", i), desc = "Move window to desktop " .. i }
    end

    local tail = {
        { "SUPER + SHIFT + mouse_down", W.move({ workspace = "r-1" }), desc = "Move window to previous desktop on monitor" },
        { "SUPER + SHIFT + mouse_up", W.move({ workspace = "r+1" }), desc = "Move window to next desktop on monitor" },
        { "SUPER + ALT + mouse_down", W.move({ workspace = "-1" }), desc = "Move window to previous desktop" },
        { "SUPER + ALT + mouse_up", W.move({ workspace = "+1" }), desc = "Move window to next desktop" },
        { "SUPER + ALT + Page_Down", W.move({ workspace = "+1" }), desc = "Move window to next desktop" },
        { "SUPER + ALT + Page_Up", W.move({ workspace = "-1" }), desc = "Move window to previous desktop" },
        { "SUPER + SHIFT + Page_Down", W.move({ workspace = "r+1" }), desc = "Move window to next desktop on monitor" },
        { "SUPER + SHIFT + Page_Up", W.move({ workspace = "r-1" }), desc = "Move window to previous desktop on monitor" },
        { "CTRL + SUPER + SHIFT + Right", W.move({ workspace = "r+1" }), desc = "Move window to next desktop on monitor" },
        { "CTRL + SUPER + SHIFT + Left", W.move({ workspace = "r-1" }), desc = "Move window to previous desktop on monitor" },

        { "SUPER + ALT + S", W.move({ workspace = "special", follow = false }), desc = "Send window to scratchpad" },
        { "CTRL + SUPER + S", D.workspace.toggle_special(), desc = "Toggle scratchpad" },

        -- make window not amogus large
        { "CTRL + SUPER + Backslash", W.resize({ x = 640, y = 480 }), desc = "Resize window to 640×480" },
    }
    for _, b in ipairs(tail) do list[#list + 1] = b end
    return list
end

-- Bind group "windows": focus, move, close, layout, float/fullscreen/pin, send to
-- workspace, scratchpad. Port of the `##! Window` section of hyprland/keybinds.conf
-- (+ "Cursed stuff" resize).
--
-- Removed by the 2026-10-17 Fixes (custom/keybinds.conf `unbind`), kept here
-- disabled for the record:
--   SUPER + Semicolon / Apostrophe -> splitratio -/+0.1 (jcode launchers own these keys)

return function(ctx)
    local C = ctx.core
    local D = hl.dsp
    local W = D.window

    local list = {
        -- mouse
        { "SUPER + mouse:272", W.drag() }, -- move
        { "SUPER + mouse:274", W.drag() },
        { "SUPER + mouse:273", W.resize() }, -- resize

        -- focus in direction
        { "SUPER + Left", D.focus({ direction = "l" }) },
        { "SUPER + Right", D.focus({ direction = "r" }) },
        { "SUPER + Up", D.focus({ direction = "u" }) },
        { "SUPER + Down", D.focus({ direction = "d" }) },
        { "SUPER + BracketLeft", D.focus({ direction = "l" }) },
        { "SUPER + BracketRight", D.focus({ direction = "r" }) },

        -- move in direction
        { "SUPER + SHIFT + Left", W.move({ direction = "l" }) },
        { "SUPER + SHIFT + Right", W.move({ direction = "r" }) },
        { "SUPER + SHIFT + Up", W.move({ direction = "u" }) },
        { "SUPER + SHIFT + Down", W.move({ direction = "d" }) },

        { "ALT + F4", W.close() },
        { "SUPER + Q", W.close() },
        { "SUPER + SHIFT + ALT + Q", D.exec_cmd("hyprctl kill") }, -- forcefully zap a window

        -- split ratio: unbound by the 2026-10-17 Fixes (see header)
        { "SUPER + Semicolon", D.layout("splitratio -0.1"), repeating = true, enabled = false },
        { "SUPER + Apostrophe", D.layout("splitratio +0.1"), repeating = true, enabled = false },

        { "SUPER + Backslash", D.layout("togglesplit") },
        { "SUPER + ALT + Space", W.float({ action = "toggle" }) },
        { "SUPER + D", W.fullscreen({ mode = "maximized" }) },
        { "SUPER + F", W.fullscreen({ mode = "fullscreen" }) },
        { "SUPER + ALT + F", W.fullscreen_state({ internal = 0, client = 3, action = "toggle" }) }, -- fullscreen spoof
        { "SUPER + P", W.pin() },
    }

    -- send to workspace 1..10 (number row + keypad; raw keycodes for any layout)
    local row = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    local pad = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    for i = 1, 10 do
        list[#list + 1] = { "SUPER + SHIFT + code:" .. row[i], C.workspace_action("movetoworkspace", i) }
    end
    for i = 1, 10 do
        list[#list + 1] = { "SUPER + SHIFT + code:" .. pad[i], C.workspace_action("movetoworkspace", i) }
    end

    local tail = {
        { "SUPER + SHIFT + mouse_down", W.move({ workspace = "r-1" }) },
        { "SUPER + SHIFT + mouse_up", W.move({ workspace = "r+1" }) },
        { "SUPER + ALT + mouse_down", W.move({ workspace = "-1" }) },
        { "SUPER + ALT + mouse_up", W.move({ workspace = "+1" }) },
        { "SUPER + ALT + Page_Down", W.move({ workspace = "+1" }) },
        { "SUPER + ALT + Page_Up", W.move({ workspace = "-1" }) },
        { "SUPER + SHIFT + Page_Down", W.move({ workspace = "r+1" }) },
        { "SUPER + SHIFT + Page_Up", W.move({ workspace = "r-1" }) },
        { "CTRL + SUPER + SHIFT + Right", W.move({ workspace = "r+1" }) },
        { "CTRL + SUPER + SHIFT + Left", W.move({ workspace = "r-1" }) },

        { "SUPER + ALT + S", W.move({ workspace = "special", follow = false }) }, -- send to scratchpad
        { "CTRL + SUPER + S", D.workspace.toggle_special() },

        -- make window not amogus large
        { "CTRL + SUPER + Backslash", W.resize({ x = 640, y = 480 }) },
    }
    for _, b in ipairs(tail) do list[#list + 1] = b end
    return list
end

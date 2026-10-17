-- Bind group "custom": the user's own binds. Port of the old custom/keybinds.conf
-- (User, Monitors, Fixes 2026-10-17). jcode hotkeys dropped 2026-10-17 (user: not needed).

return function(ctx)
    local C = ctx.core
    local D = hl.dsp
    local X = D.exec_cmd

    return {
        -- ##! User
        { "CTRL + SUPER + Slash", X("xdg-open ~/.config/nox/shell.json"), desc = "Edit shell config" },
        -- was custom/keybinds.conf; now opens this file
        { "CTRL + SUPER + ALT + Slash", X("xdg-open ~/.config/hypr/nox/binds/custom.lua"), desc = "Edit custom keybinds" },

        -- ##! Monitors (dual-monitor)
        { "SUPER + ALT + Right", D.workspace.move({ monitor = "+1" }), desc = "Move desktop to next monitor" },
        { "SUPER + ALT + Left", D.workspace.move({ monitor = "-1" }), desc = "Move desktop to previous monitor" },
        { "SUPER + ALT + Up", D.workspace.swap_monitors({ monitor1 = "current", monitor2 = "+1" }), desc = "Swap desktops with next monitor" },

        -- ##! Fixes (2026-10-17)
        -- Text editor: same window as the `nv` shell function
        { "SUPER + X", X("ghostty --gtk-single-instance=false --class=dev.neovim --title=nvim --config-file=\"" .. C.HOME .. "/.config/nvim/ghostty.conf\" -e nvim"), desc = "Open Neovim" },

        -- ##! Nox shell
        { "SUPER + Slash", X("qs -c nox ipc call cheatsheet toggle"), desc = "Show keyboard shortcuts" },
        { "SUPER + Space", X("qs -c nox ipc call launcher toggle"), desc = "Open launcher" }, -- Spotlight-style
        { "SUPER + ALT + N", X("qs -c nox ipc call controlCenter toggle"), desc = "Open Control Center" },

    }
end

-- Bind group "custom": the user's own binds. Port of custom/keybinds.conf
-- (User, Monitors, Fixes 2026-10-17) and the jcode managed block at the end of
-- hyprland.conf.
--
-- jcode: `jcode setup-hotkey` edits hyprland.conf, which the Lua config does not
-- read. Re-run it -> copy the new lines here.

return function(ctx)
    local C = ctx.core
    local D = hl.dsp
    local X = D.exec_cmd

    return {
        -- ##! User
        { "CTRL + SUPER + Slash", X("xdg-open ~/.config/illogical-impulse/config.json") }, -- edit shell config
        -- was custom/keybinds.conf; now opens this file
        { "CTRL + SUPER + ALT + Slash", X("xdg-open ~/.config/hypr/graphite/binds/custom.lua") },

        -- ##! Monitors (dual-monitor)
        { "SUPER + ALT + Right", D.workspace.move({ monitor = "+1" }) }, -- move workspace to next monitor
        { "SUPER + ALT + Left", D.workspace.move({ monitor = "-1" }) },
        { "SUPER + ALT + Up", D.workspace.swap_monitors({ monitor1 = "current", monitor2 = "+1" }) },

        -- ##! Fixes (2026-10-17)
        -- Text editor: same window as the `nv` shell function
        { "SUPER + X", X("ghostty --gtk-single-instance=false --class=dev.neovim --title=nvim --config-file=\"" .. C.HOME .. "/.config/nvim/ghostty.conf\" -e nvim") }, -- text editor (Neovim)

        -- ##! Graphite shell (runs next to ii, see settings.companion_shells)
        { "SUPER + Space", X("qs -c graphite ipc call launcher toggle") }, -- Spotlight-style launcher
        { "SUPER + ALT + N", X("qs -c graphite ipc call controlCenter toggle") }, -- Control Center

        -- >>> jcode launch hotkeys (from hyprland.conf managed block) >>>
        { "SUPER + semicolon", X("'" .. C.HOME .. "/.jcode/hotkey/launch_jcode_0_cmd_semicolon.sh'") }, -- jcode: devex
        { "SUPER + apostrophe", X("'" .. C.HOME .. "/.jcode/hotkey/launch_jcode_1_cmd_quote.sh'") },     -- jcode: home
        -- <<< jcode <<<
    }
end

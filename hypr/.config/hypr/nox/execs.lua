-- Autostart. Port of hyprland/execs.conf (+ custom/execs.conf, which was empty).
-- exec-once == hl.on("hyprland.start"); it does NOT run on reload and does NOT run
-- under --verify-config.
-- Lines tagged [base0 2026-10-17 disabled] in the old config stay disabled.

return function(ctx)
    local C, S = ctx.core, ctx.settings
    local shell = require("nox.shells." .. S.shell)

    local cmds = {}
    local function add(list)
        for _, c in ipairs(list or {}) do cmds[#cmds + 1] = C.subst(c, S.vars) end
    end

    -- shell first (bar, wallpaper), as in the old file
    add(shell.execs_early)
    for _, name in ipairs(S.companion_shells or {}) do
        if name ~= S.shell then add({ "qs -c " .. name }) end
    end
    add({
        -- [base0 2026-10-17 disabled] gnome-keyring-daemon (systemd user unit provides it)
        "hypridle",
        "dbus-update-activation-environment --all",
        "sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP",
        -- graphical-session.target for xdg-desktop-portal 1.22+ (screen sharing)
        "systemctl --user start hyprland-session.target",
        -- [base0 2026-10-17 disabled] easyeffects (not installed)
        -- [base0 2026-10-17 disabled] start_geoclue_agent.sh (weather off)
    })
    add(shell.execs)
    -- Cursor (theme resolved in env.lua)
    add({ string.format("hyprctl setcursor %s %d", ctx.cursor and ctx.cursor.theme or S.cursor_fallback,
        ctx.cursor and ctx.cursor.size or 24) })

    hl.on("hyprland.start", function()
        for _, c in ipairs(cmds) do hl.exec_cmd(c) end
    end)
end

-- Nox Hyprland config: behaviour settings (everything that is NOT a look value).
--
-- Look values (colors, radii, gaps, timings, shadows, blur) come from tokens
-- (nox/defaults.lua <- ~/.local/state/nox/tokens.lua). This file holds
-- choices: which shell, which bind groups, which programs, which paths.
--
-- Override any of this per machine in nox/local.lua (see local.example.lua):
--   return { settings = { shell = "nox" } }

local HOME = os.getenv("HOME") or ""

return {
    -- Shell profile: nox/shells/<shell>.lua provides the shell's env, autostart
    -- commands, gestures and the "shell" bind group. "nox" = the own
    -- Quickshell shell (launcher, overview, notifications, session menu, polkit,
    -- wallpaper). The old end-4 "ii" profile was removed on 2026-10-17
    -- (lnx/reports/remove-ii.md; restore = git revert of that branch).
    shell = "nox",

    -- Layer-rule sets applied regardless of `shell` (rules for an absent
    -- namespace cost nothing).
    layer_rule_shells = { "nox" },

    -- Extra Quickshell configs autostarted next to `shell` (`qs -c <name>`). An
    -- entry equal to `shell` is skipped (execs.lua).
    companion_shells = {},

    -- Bind groups, applied in THIS order (order matters when two binds share a key:
    -- the shell's Super_L release binds must come first). "shell" resolves to
    -- shells/<shell>.lua; every other name is nox/binds/<name>.lua.
    -- Swap the shell's binds by changing `shell`, or replace "shell" here with an
    -- explicit group; drop a group by deleting its line.
    bind_groups = { "shell", "windows", "workspaces", "system", "apps", "custom" },

    -- All binds live in this submap and Hyprland is switched into it at start and
    -- after every reload (port of `submap = global` from the old hyprland.conf).
    -- Needed because `catchall` binds only work inside a submap, and the shell's
    -- Super-tap-for-launcher depends on the catchall interrupt.
    -- Set to false to put binds in the default submap (the catchall is then skipped).
    bind_submap = "global",

    -- Tiling layouts cycled by Super+\ (next) / Super+Shift+\ (previous) and by
    -- `nox layout`. The first one is the default. Built-in names (0.55.4):
    -- dwindle, master, scrolling, monocle.
    layouts = { "dwindle", "scrolling", "master", "monocle" },
    -- Per-layout options, tuned so each layout looks clearly different even with
    -- two windows (defaults made scrolling = 50/50 columns = same as dwindle).
    layout_options = {
        master = { mfact = 0.62, new_status = "master" },       -- big main window left, stack right
        scrolling = { column_width = 0.8, fullscreen_on_one_column = true }, -- wide columns, neighbours peek in
    },
    -- Show the layout name on screen when it changes (nox shell HUD).
    layout_hud = true,
    layout_labels = { dwindle = "Tiling", scrolling = "Scrolling", master = "Master + stack", monocle = "Monocle (one at a time)" },
    -- Keep the runtime choice across config reloads for the rest of the session
    -- ($XDG_RUNTIME_DIR file). Never survives a logout.
    layout_persist = true,

    -- Modules to skip (names from the MODULES list in nox.lua).
    disabled_modules = {},

    -- ${name} placeholders usable in bind/exec strings (C.subst).
    vars = {
        scripts = HOME .. "/.config/hypr/nox/scripts", -- helper scripts (nox/scripts/)
    },

    -- Programs (launchers are kept byte-identical to the old config).
    apps = {
        terminal_env = "ghostty", -- $TERMINAL
        launch = "~/.config/hypr/nox/scripts/launch_first_available.sh",
    },

    -- Fallback cursor when tokens.theme.cursor is not installed.
    cursor_fallback = "Bibata-Modern-Classic",
}

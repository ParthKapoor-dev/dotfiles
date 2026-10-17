-- Graphite Hyprland config: behaviour settings (everything that is NOT a look value).
--
-- Look values (colors, radii, gaps, timings, shadows, blur) come from tokens
-- (graphite/defaults.lua <- ~/.local/state/graphite/tokens.lua). This file holds
-- choices: which shell, which bind groups, which programs, which paths.
--
-- Override any of this per machine in graphite/local.lua (see local.example.lua):
--   return { settings = { shell = "graphite" } }

local HOME = os.getenv("HOME") or ""

return {
    -- Shell profile: graphite/shells/<shell>.lua provides the shell's env, autostart
    -- commands, gestures and the "shell" bind group. "ii" = old end-4
    -- illogical-impulse, "graphite" = the own Quickshell shell (full replacement:
    -- launcher, overview, notifications, session menu, polkit, wallpaper).
    -- Cutover / rollback steps: lnx/reports/hypr-v2.md ("Cutover"). Stop
    -- `qs -c ii` before switching: it holds the notification D-Bus name and the
    -- polkit agent slot that graphite needs.
    shell = "ii",

    -- Layer-rule sets applied regardless of `shell` (both shells may run while
    -- migrating; rules for an absent namespace cost nothing).
    layer_rule_shells = { "ii", "graphite" },

    -- Extra Quickshell configs autostarted next to `shell` (migration: graphite's
    -- bar/dock/control center run while ii still provides notifications,
    -- overview, sidebars). An entry equal to `shell` is skipped (execs.lua), so
    -- with shell = "graphite" nothing extra starts; ii is never a companion.
    companion_shells = { "graphite" },

    -- Bind groups, applied in THIS order (order matters when two binds share a key:
    -- the shell's Super_L release binds must come first). "shell" resolves to
    -- shells/<shell>.lua; every other name is graphite/binds/<name>.lua.
    -- Swap the shell's binds by changing `shell`, or replace "shell" here with an
    -- explicit group; drop a group by deleting its line.
    bind_groups = { "shell", "windows", "workspaces", "system", "apps", "custom" },

    -- All binds live in this submap and Hyprland is switched into it at start and
    -- after every reload (port of `submap = global` from the old hyprland.conf).
    -- Needed because `catchall` binds only work inside a submap, and ii's
    -- Super-tap-for-search depends on the catchall interrupt.
    -- Set to false to put binds in the default submap (the catchall is then skipped).
    bind_submap = "global",

    -- Tiling layouts cycled by Super+\ (next) / Super+Shift+\ (previous) and by
    -- `graphite-layout`. The first one is the default. Built-in names (0.55.4):
    -- dwindle, master, scrolling, monocle.
    layouts = { "dwindle", "scrolling", "master" },
    -- Keep the runtime choice across config reloads for the rest of the session
    -- ($XDG_RUNTIME_DIR file). Never survives a logout.
    layout_persist = true,

    -- Modules to skip (names from the MODULES list in graphite.lua).
    disabled_modules = {},

    -- ${name} placeholders usable in bind/exec strings (C.subst).
    vars = {
        qs = "ii",                                         -- old $qsConfig
        hyprScripts = HOME .. "/.config/hypr/hyprland/scripts",
    },

    -- Programs (launchers are kept byte-identical to the old config).
    apps = {
        terminal_env = "ghostty", -- $TERMINAL
        launch = "~/.config/hypr/hyprland/scripts/launch_first_available.sh",
    },

    -- Fallback cursor when tokens.theme.cursor is not installed.
    cursor_fallback = "Bibata-Modern-Classic",
}

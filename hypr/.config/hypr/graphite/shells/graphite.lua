-- Shell profile: Graphite (own Quickshell shell, `qs -c graphite`).
--
-- With settings.shell = "graphite" this file is the WHOLE shell side of the
-- compositor: env, autostart, gestures, the "shell" bind group and layer rules.
-- It replaced the old shells/ii.lua (end-4 illogical-impulse, removed 2026-10-17)
-- bind for bind (mapping + dropped binds listed above P.binds and in
-- lnx/reports/hypr-v2.md).
--
-- Shell-independent binds (volume, media, Print, lock, apps, windows, layout
-- cycling) live in graphite/binds/*.lua and are the same for every shell.

local P = {}

---------------------------------------------------------------------------
-- Shell API used by Hyprland. Adjust names HERE when the shell's final IPC /
-- GlobalShortcuts land (status 2026-10-17: "live" = answered by the running
-- shell today, "planned" = being built in shell-v2).
---------------------------------------------------------------------------
P.QS = "qs -c graphite"

-- `qs -c graphite ipc call <target> <function> [args]`
P.IPC = {
    launcher       = "launcher toggle",         -- live
    clipboard      = "launcher clipboard",      -- planned
    overview       = "overview toggle",         -- planned
    overview_close = "overview close",          -- planned (assumed: every target has open/close/toggle)
    session        = "session toggle",          -- planned
    notifications  = "notifications toggle",    -- live
    dnd            = "notifications toggleDnd", -- live
    control_center = "controlCenter toggle",    -- live
    dock           = "dock toggle",             -- live
    wallpaper_set  = "wallpaper set",           -- planned (+ <path>; used by bin/graphite-wallpaper)
    layout_changed = "layout changed",          -- planned (+ <name>; sent by graphite/layouts.lua)
}

-- GlobalShortcut names (appid "graphite"), dispatched as global "graphite:<name>"
P.GLOBAL = {
    launcher            = "launcherToggle",                 -- live
    launcher_release    = "launcherToggleRelease",          -- live
    launcher_interrupt  = "launcherToggleReleaseInterrupt", -- live
    notification_center = "notificationCenterToggle",       -- live
    dnd                 = "dndToggle",                      -- live
}

-- exits != 0 only when no graphite instance answers (`ipc call` to a missing
-- target or function still exits 0), so `ALIVE || fallback` = "shell is dead"
P.ALIVE = P.QS .. " ipc show >/dev/null 2>&1"

local function ipc(name, arg)
    return P.QS .. " ipc call " .. P.IPC[name] .. (arg and (" " .. arg) or "")
end
P.ipc = ipc

local function G(name) return hl.dsp.global("graphite:" .. P.GLOBAL[name]) end
local function X(cmd) return hl.dsp.exec_cmd(cmd) end

local HS = "~/.config/hypr/graphite/scripts"

---------------------------------------------------------------------------
-- env / autostart / gestures
---------------------------------------------------------------------------

-- Nothing shell-specific: Qt/cursor/XDG variables come from graphite/env.lua.
P.env = {}

-- Started first (exec-once order as with ii). The shell draws wallpaper, bar,
-- dock, notifications (org.freedesktop.Notifications) and is the polkit agent:
-- no other notification daemon / polkit agent may run next to it (the first
-- one to claim the D-Bus name / agent slot wins).
P.execs_early = {
    P.QS,
}

P.execs = {
    -- clipboard history: plain cliphist (ii also poked its own service over IPC)
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
    -- polkit: graphite's polkit module is the agent. If it is not there yet,
    -- uncomment the KDE agent (polkit-kde-agent is installed):
    -- "/usr/lib/polkit-kde-authentication-agent-1",
    -- lock right after login (ii had lock.launchOnStartup = true). Not needed
    -- while greetd/tuigreet asks for the password; uncomment for autologin:
    -- "hyprlock",
}

-- 4-finger swipe up / down = overview (as with ii)
P.gestures = {
    { fingers = 4, direction = "up", action = function() hl.exec_cmd(ipc("overview")) end },
    { fingers = 4, direction = "down", action = function() hl.exec_cmd(ipc("overview_close")) end },
}

---------------------------------------------------------------------------
-- "shell" bind group. Every ii bind (former shells/ii.lua) is mapped or dropped:
--
-- ii                                 graphite
-- Super tap (release) search         global launcherToggleRelease + interrupts; fuzzel if shell dead
-- Super_L/R hold: workspaceNumber    DROPPED (no hold-to-show-numbers overlay in graphite)
-- Super+Tab overview                 ipc overview toggle
-- Super+V clipboard                  ipc launcher clipboard; cliphist | fuzzel if shell dead
-- Super+. emoji                      fuzzel-emoji.sh (graphite has no emoji picker)
-- Super+A, Super+Alt+A, Super+B/O    DROPPED (ii left sidebar: AI chat, translator, booru)
-- Super+N right sidebar              global notificationCenterToggle
-- Super+/ cheatsheet                 DROPPED (no graphite cheatsheet)
-- Super+K on-screen keyboard         DROPPED (no OSK in graphite; no touch screen)
-- Super+M media controls             ipc controlCenter toggle (Now Playing lives there)
-- Super+G overlay widgets            DROPPED (no graphite overlay)
-- Ctrl+Alt+Delete session menu       ipc session toggle; wlogout if shell dead
-- Super+J bar toggle                 ipc dock toggle (the menubar is always shown)
-- Super+Shift+Alt+/ welcome app      DROPPED (ii only)
-- Brightness keys (ii ipc)           brightnessctl (graphite's OSD follows the backlight)
-- Ctrl+Super+T wallpaper selector    graphite-wallpaper pick
-- Ctrl+Super+Alt+T random wallpaper  graphite-wallpaper random
-- Ctrl+Super+R restart shell         qs -c graphite kill; qs -c graphite -d
-- Ctrl+Super+P panel family cycle    DROPPED (ii only)
-- Super+Shift+S region screenshot    graphite-shot region (clipboard + swappy)
-- Super+Shift+A region search        snip_to_search.sh (Google Lens, unchanged)
-- Super+Shift+X / T OCR              graphite-shot ocr
-- Super+Shift+R, Super+Alt+R record  graphite-record (region, toggle)
-- Ctrl+Alt+R, Super+Shift+Alt+R      graphite-record --fullscreen [--sound]
-- Super+keypad -/+ zoom (ii ipc)     in-process cursor zoom (same 1..3 clamp)
-- New: Super+Alt+D Do Not Disturb, Alt+Print window shot, Shift+Print monitor shot.
-- (Super+Space launcher and Super+Alt+N Control Center live in binds/custom.lua.)
---------------------------------------------------------------------------
function P.binds(ctx)
    local C = ctx.core

    local list = {
        -- ##! Shell -- these MUST stay first (Super tap = launcher on release)
        { "SUPER + Super_L", G("launcher_release"), ignore_mods = true, desc = "Launcher" },
        { "SUPER + Super_R", G("launcher_release"), ignore_mods = true, desc = "Launcher" },
        { "SUPER + Super_L", X(P.ALIVE .. " || pkill fuzzel || fuzzel") },
        { "SUPER + Super_R", X(P.ALIVE .. " || pkill fuzzel || fuzzel") },
        { "catchall", G("launcher_interrupt"), ignore_mods = true, transparent = true, non_consuming = true },
        { "CTRL + Super_L", G("launcher_interrupt") },
        { "CTRL + Super_R", G("launcher_interrupt") },
    }
    -- Super + mouse must not end in a launcher toggle either
    for _, m in ipairs({ "mouse:272", "mouse:273", "mouse:274", "mouse:275", "mouse:276", "mouse:277", "mouse_up", "mouse_down" }) do
        list[#list + 1] = { "SUPER + " .. m, G("launcher_interrupt") }
    end

    local rest = {
        { "SUPER + Tab", X(ipc("overview")), desc = "Overview" },
        { "SUPER + V", X(ipc("clipboard") .. " || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy"), desc = "Clipboard history" },
        { "SUPER + Period", X("pkill fuzzel || " .. HS .. "/fuzzel-emoji.sh copy"), desc = "Emoji >> clipboard" },
        { "SUPER + N", G("notification_center"), desc = "Notification Center" },
        { "SUPER + ALT + D", G("dnd"), desc = "Toggle Do Not Disturb" },
        { "SUPER + M", X(ipc("control_center")), desc = "Control Center (Now Playing)" },
        { "SUPER + J", X(ipc("dock")), desc = "Toggle dock" },
        { "CTRL + ALT + Delete", X(ipc("session") .. " || pkill wlogout || wlogout -p layer-shell"), desc = "Session menu" },

        -- brightness: the shell's OSD watches the backlight itself
        { "XF86MonBrightnessUp", X("brightnessctl s 5%+"), locked = true, repeating = true },
        { "XF86MonBrightnessDown", X("brightnessctl s 5%-"), locked = true, repeating = true },

        -- wallpaper / shell
        { "CTRL + SUPER + T", X("graphite-wallpaper pick"), desc = "Choose wallpaper" },
        { "CTRL + SUPER + ALT + T", X("graphite-wallpaper random"), desc = "Random wallpaper" },
        { "CTRL + SUPER + R", X(P.QS .. " kill; " .. P.QS .. " -d"), desc = "Restart shell" },

        -- ##! Utilities: screenshot / OCR / record (bin/graphite-shot, bin/graphite-record)
        { "SUPER + SHIFT + S", X("graphite-shot region"), desc = "Screenshot region (copy + edit)" },
        { "ALT + Print", X("graphite-shot window"), locked = true, desc = "Screenshot window" },
        { "SHIFT + Print", X("graphite-shot screen"), locked = true, desc = "Screenshot monitor" },
        { "SUPER + SHIFT + A", X("pidof slurp || " .. HS .. "/snip_to_search.sh"), desc = "Search region (Lens)" },
        { "SUPER + SHIFT + X", X("graphite-shot ocr"), desc = "OCR region >> clipboard" },
        { "SUPER + SHIFT + T", X("graphite-shot ocr"), desc = "OCR region >> clipboard" },
        { "SUPER + SHIFT + R", X("graphite-record"), locked = true, desc = "Record region (toggle)" },
        { "SUPER + ALT + R", X("graphite-record"), locked = true, desc = "Record region (toggle)" },
        { "CTRL + ALT + R", X("graphite-record --fullscreen"), locked = true, desc = "Record screen (toggle)" },
        { "SUPER + SHIFT + ALT + R", X("graphite-record --fullscreen --sound"), locked = true, desc = "Record screen + audio (toggle)" },

        -- ##! Screen: keypad zoom (in-process, same clamp as Super+-/=)
        { "SUPER + code:82", C.zoom_fn(-0.1), repeating = true },
        { "SUPER + code:86", C.zoom_fn(0.1), repeating = true },
    }
    for _, b in ipairs(rest) do list[#list + 1] = b end
    return list
end

---------------------------------------------------------------------------
-- layer rules. Namespaces: graphite:bar, graphite:dock, graphite:popup,
-- graphite:launcher, graphite:osd (new modules get the base blur rule through
-- ^graphite:.*$)
---------------------------------------------------------------------------
function P.layer_rules(ctx)
    local T = ctx.tokens
    local g = T.glass
    -- blur only samples pixels above ignore_alpha: keep it under the lowest glass alpha
    local minGlass = math.min(g.alpha, g.menubarAlpha, g.launcherAlpha)
    local ia = math.min(T.hypr.layerIgnoreAlpha, minGlass - 0.05)
    local padded = math.min(T.hypr.layerIgnoreAlphaPadded, minGlass - 0.05)

    return {
        { match = { namespace = "^graphite:.*$" }, blur = true, blur_popups = true, ignore_alpha = ia },
        -- menubar slides with the workspace feel; dock rises from the bottom
        { match = { namespace = "^graphite:bar$" }, animation = "slide top" },
        { match = { namespace = "^graphite:dock$" }, animation = "slide bottom", ignore_alpha = padded },
        -- menus, launcher, OSD: quick fade (they animate their own content)
        { match = { namespace = "^graphite:popup$" }, animation = "fade", ignore_alpha = padded },
        { match = { namespace = "^graphite:launcher$" }, animation = "fade" },
        { match = { namespace = "^graphite:osd$" }, animation = "fade" },
        { match = { namespace = "^graphite:notifications$" }, animation = "fade" },
        -- 0.5: lower values blur the soft card shadows (orange halo on Ember wallpaper)
        -- full-screen / static surfaces: no blur, no compositor animation (they animate themselves)
        { match = { namespace = "^graphite:(wallpaper|corners|overview)$" }, blur = false },
        { match = { namespace = "^graphite:(corners|overview|session|polkit)$" }, no_anim = true },
    }
end

return P

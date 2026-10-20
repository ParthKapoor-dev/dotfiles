-- Shell profile: Nox (own Quickshell shell, `qs -c nox`).
--
-- With settings.shell = "nox" this file is the WHOLE shell side of the
-- compositor: env, autostart, gestures, the "shell" bind group and layer rules.
-- It replaced the old shells/ii.lua (end-4 illogical-impulse, removed 2026-10-17)
-- bind for bind (mapping + dropped binds listed above P.binds and in
-- lnx/reports/hypr-v2.md).
--
-- Shell-independent binds (volume, media, Print, lock, apps, windows, layout
-- cycling) live in nox/binds/*.lua and are the same for every shell.

local P = {}

---------------------------------------------------------------------------
-- Shell API used by Hyprland. Adjust names HERE when the shell's final IPC /
-- GlobalShortcuts land (status 2026-10-17: "live" = answered by the running
-- shell today, "planned" = being built in shell-v2).
---------------------------------------------------------------------------
P.QS = "qs -c nox"

-- `qs -c nox ipc call <target> <function> [args]`
P.IPC = {
    launcher       = "launcher toggle",         -- live
    clipboard      = "launcher clipboard",      -- live
    emoji          = "launcher emoji",          -- live
    palette        = "launcher palette",        -- live (command palette, prefix ">")
    overview       = "overview toggle",         -- planned
    overview_close = "overview close",          -- planned (assumed: every target has open/close/toggle)
    session        = "session toggle",          -- planned
    notifications  = "notifications toggle",    -- live
    dnd            = "notifications toggleDnd", -- live
    control_center = "controlCenter toggle",    -- live
    dock           = "dock toggle",             -- live
    wallpaper_set  = "wallpaper set",           -- planned (+ <path>; used by nox wallpaper)
    layout_changed = "layout changed",          -- planned (+ <name>; sent by nox/layouts.lua)
    agents         = "agents toggle",           -- live (Mission Control for coding agents)
}

-- GlobalShortcut names (appid "nox"), dispatched as global "nox:<name>"
P.GLOBAL = {
    launcher            = "launcherToggle",                 -- live
    launcher_release    = "launcherToggleRelease",          -- live
    launcher_interrupt  = "launcherToggleReleaseInterrupt", -- live
    notification_center = "notificationCenterToggle",       -- live
    dnd                 = "dndToggle",                      -- live
    notes               = "notesToggle",                    -- live (Ctrl+Super+S)
    switcher_next       = "switcherNext",                   -- live (Alt+Tab)
    switcher_prev       = "switcherPrev",                   -- live (Alt+Shift+Tab)
    switcher_alt        = "switcherAlt",                    -- live (Alt_L release = switch)
}

-- exits != 0 only when no nox instance answers (`ipc call` to a missing
-- target or function still exits 0), so `ALIVE || fallback` = "shell is dead"
P.ALIVE = P.QS .. " ipc show >/dev/null 2>&1"

local function ipc(name, arg)
    return P.QS .. " ipc call " .. P.IPC[name] .. (arg and (" " .. arg) or "")
end
P.ipc = ipc

local function G(name) return hl.dsp.global("nox:" .. P.GLOBAL[name]) end
local function X(cmd) return hl.dsp.exec_cmd(cmd) end

local HS = "~/.config/hypr/nox/scripts"

---------------------------------------------------------------------------
-- env / autostart / gestures
---------------------------------------------------------------------------

-- Nothing shell-specific: Qt/cursor/XDG variables come from nox/env.lua.
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
    -- link names for the history: a copied <a href>Name</a> (Teamwork, Jira, Slack) stores only the
    -- URL in cliphist; this keeps URL -> Name (~/.local/state/nox/clip-titles.json)
    "wl-paste --type text/html --watch ~/.local/lib/nox/clip-title",
    -- Notes (Ctrl+Super+S) waits hidden on special:notes, so the first show is instant
    "nox notes start",
    -- polkit: nox's polkit module is the agent. If it is not there yet,
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
-- ii                                 nox
-- Super tap (release) search         global launcherToggleRelease + interrupts; fuzzel if shell dead
-- Super_L/R hold: workspaceNumber    DROPPED (no hold-to-show-numbers overlay in nox)
-- Super+Tab overview                 ipc overview toggle
-- Super+V clipboard                  ipc launcher clipboard; cliphist | fuzzel if shell dead
-- Super+. emoji                      ipc launcher emoji; fuzzel-emoji.sh if shell dead
-- Super+A, Super+Alt+A, Super+B/O    DROPPED (ii left sidebar: AI chat, translator, booru)
-- Super+N right sidebar              global notificationCenterToggle
-- Super+/ cheatsheet                 DROPPED (no nox cheatsheet)
-- Super+K on-screen keyboard         DROPPED (no OSK in nox; no touch screen)
-- Super+M media controls             ipc controlCenter toggle (Now Playing lives there)
-- Super+G overlay widgets            DROPPED (no nox overlay)
-- Ctrl+Alt+Delete session menu       ipc session toggle; wlogout if shell dead
-- Super+J bar toggle                 ipc dock toggle (the menubar is always shown)
-- Super+Shift+Alt+/ welcome app      DROPPED (ii only)
-- Brightness keys (ii ipc)           brightnessctl (nox's OSD follows the backlight)
-- Ctrl+Super+T wallpaper selector    nox wallpaper pick
-- Ctrl+Super+Alt+T random wallpaper  nox wallpaper random
-- Ctrl+Super+R restart shell         nox shell restart (kills crash relaunches too)
-- Ctrl+Super+P panel family cycle    DROPPED (ii only)
-- Super+Shift+S region screenshot    nox shot region (clipboard + card; Print too)
-- Super+Shift+A region search        snip_to_search.sh (Google Lens, unchanged)
-- Super+Shift+X / T OCR              nox shot ocr
-- Super+Shift+R, Super+Alt+R record  nox record (region, toggle)
-- Ctrl+Alt+R, Super+Shift+Alt+R      nox record --fullscreen [--sound]
-- Super+keypad -/+ zoom (ii ipc)     in-process cursor zoom (same 1..3 clamp)
-- New: Super+Alt+D Do Not Disturb, Alt+Print window shot, Shift+Print monitor shot,
-- Ctrl+Super+Space command palette (launcher ">": actions, toggles, binds with their keys).
-- (Super+Space launcher and Super+Alt+N Control Center live in binds/custom.lua.)
---------------------------------------------------------------------------
function P.binds(ctx)
    local C = ctx.core

    local list = {
        -- ##! Shell -- these MUST stay first (Super tap = launcher on release)
        { "SUPER + Super_L", G("launcher_release"), ignore_mods = true, desc = "Open launcher" },
        { "SUPER + Super_R", G("launcher_release"), ignore_mods = true, desc = "Open launcher" },
        { "SUPER + Super_L", X(P.ALIVE .. " || pkill fuzzel || fuzzel"), desc = "Open launcher" }, -- fuzzel if the shell is down,
        { "SUPER + Super_R", X(P.ALIVE .. " || pkill fuzzel || fuzzel"), desc = "Open launcher" },
        { "catchall", G("launcher_interrupt"), ignore_mods = true, transparent = true, non_consuming = true, desc = "Internal: cancel Super-tap launcher" },
        { "CTRL + Super_L", G("launcher_interrupt"), desc = "Internal: cancel Super-tap launcher" },
        { "CTRL + Super_R", G("launcher_interrupt"), desc = "Internal: cancel Super-tap launcher" },
    }
    -- Super + mouse must not end in a launcher toggle either
    for _, m in ipairs({ "mouse:272", "mouse:273", "mouse:274", "mouse:275", "mouse:276", "mouse:277", "mouse_up", "mouse_down" }) do
        list[#list + 1] = { "SUPER + " .. m, G("launcher_interrupt"), desc = "Internal: cancel Super-tap launcher" }
    end

    local rest = {
        { "SUPER + Tab", X(ipc("overview")), desc = "Open overview" },
        { "CTRL + SUPER + S", X("nox notes toggle"), desc = "Show or hide Notes" },
        -- Super+Shift+M / Super+Alt+M are mute / mic mute (binds/system.lua)
        { "CTRL + SUPER + M", X(ipc("agents")), desc = "Agent mission control" },
        -- Alt+Tab window switcher (most recently used); releasing Alt switches. The Alt release is a
        -- release bind (fires when Alt_L / Alt_R comes up, whatever was pressed in between) and
        -- non-consuming + transparent so apps still see Alt (menus, Alt+key shortcuts)
        { "ALT + Tab", G("switcher_next"), desc = "Switch to the previous window (hold Alt, Tab to step)" },
        { "ALT + SHIFT + Tab", G("switcher_prev"), desc = "Window switcher: step back" },
        { "ALT + Alt_L", G("switcher_alt"), release = true, ignore_mods = true, non_consuming = true, transparent = true, desc = "Internal: window switcher, Alt release switches" },
        { "ALT + Alt_R", G("switcher_alt"), release = true, ignore_mods = true, non_consuming = true, transparent = true, desc = "Internal: window switcher, Alt release switches" },
        { "SUPER + V", X(ipc("clipboard") .. " || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy"), desc = "Open clipboard history" },
        { "SUPER + Period", X(ipc("emoji") .. " || pkill fuzzel || " .. HS .. "/fuzzel-emoji.sh copy"), desc = "Emoji picker (launcher, .)" },
        { "CTRL + SUPER + Space", X(ipc("palette") .. " || pkill fuzzel || fuzzel"), desc = "Command palette (launcher, >)" },
        { "SUPER + N", G("notification_center"), desc = "Open notification center" },
        { "SUPER + ALT + D", G("dnd"), desc = "Toggle Do Not Disturb" },
        { "SUPER + M", X(ipc("control_center")), desc = "Open Control Center (Now Playing)" },
        { "SUPER + J", X(ipc("dock")), desc = "Toggle dock" },
        { "CTRL + ALT + Delete", X(ipc("session") .. " || pkill wlogout || wlogout -p layer-shell"), desc = "Open session menu" },

        -- brightness: the shell's OSD watches the backlight itself
        { "XF86MonBrightnessUp", X("brightnessctl s 5%+"), locked = true, repeating = true, desc = "Brightness up" },
        { "XF86MonBrightnessDown", X("brightnessctl s 5%-"), locked = true, repeating = true, desc = "Brightness down" },

        -- wallpaper / shell
        { "CTRL + SUPER + T", X("nox wallpaper pick"), desc = "Choose wallpaper" },
        { "CTRL + SUPER + ALT + T", X("nox wallpaper random"), desc = "Random wallpaper" },
        { "CTRL + SUPER + R", X("nox shell restart"), desc = "Restart shell" },

        -- ##! Utilities: screenshot / OCR / record (nox shot, nox record)
        -- every capture: clipboard + screenshot card (Save, Annotate, Copy, Pin, Send, Upload, Discard)
        { "SUPER + SHIFT + S", X("nox shot region"), desc = "Screenshot region" },
        { "Print", X("nox shot region"), desc = "Screenshot region" },
        { "SHIFT + Print", X("nox shot screen"), locked = true, desc = "Screenshot monitor" },
        { "ALT + Print", X("nox shot window"), locked = true, desc = "Screenshot window" },
        { "CTRL + Print", X("nox shot all"), locked = true, desc = "Screenshot all monitors" },
        { "SUPER + SHIFT + A", X("pidof slurp || " .. HS .. "/snip_to_search.sh"), desc = "Search region with Google Lens" },
        { "SUPER + SHIFT + X", X("nox shot ocr"), desc = "OCR region to clipboard" },
        { "SUPER + SHIFT + T", X("nox shot ocr"), desc = "OCR region to clipboard" },
        { "SUPER + SHIFT + R", X("nox record"), locked = true, desc = "Record region (toggle)" },
        { "SUPER + ALT + R", X("nox record"), locked = true, desc = "Record region (toggle)" },
        { "CTRL + ALT + R", X("nox record --fullscreen"), locked = true, desc = "Record screen (toggle)" },
        { "SUPER + SHIFT + ALT + R", X("nox record --fullscreen --sound"), locked = true, desc = "Record screen with audio (toggle)" },

        -- ##! Screen: keypad zoom (in-process, same clamp as Super+-/=)
        { "SUPER + code:82", C.zoom_fn(-0.1), repeating = true, desc = "Zoom out" },
        { "SUPER + code:86", C.zoom_fn(0.1), repeating = true, desc = "Zoom in" },
    }
    for _, b in ipairs(rest) do list[#list + 1] = b end
    return list
end

---------------------------------------------------------------------------
-- layer rules. Namespaces: nox:bar, nox:dock, nox:popup,
-- nox:launcher, nox:osd (new modules get the base blur rule through
-- ^nox:.*$)
---------------------------------------------------------------------------
function P.layer_rules(ctx)
    local T = ctx.tokens
    local g = T.glass
    -- blur only samples pixels above ignore_alpha: keep it under the lowest glass alpha
    local minGlass = math.min(g.alpha, g.menubarAlpha, g.launcherAlpha)
    local ia = math.min(T.hypr.layerIgnoreAlpha, minGlass - 0.05)
    local padded = math.min(T.hypr.layerIgnoreAlphaPadded, minGlass - 0.05)

    return {
        { match = { namespace = "^nox:.*$" }, blur = true, blur_popups = true, ignore_alpha = ia },
        -- menubar slides with the workspace feel; dock rises from the bottom
        { match = { namespace = "^nox:bar$" }, animation = "slide top" },
        { match = { namespace = "^nox:dock$" }, animation = "slide bottom", ignore_alpha = padded },
        -- menus, launcher, OSD: quick fade (they animate their own content)
        { match = { namespace = "^nox:popup$" }, animation = "fade", ignore_alpha = padded },
        { match = { namespace = "^nox:launcher$" }, animation = "fade" },
        { match = { namespace = "^nox:osd$" }, animation = "fade" },
        { match = { namespace = "^nox:notifications$" }, animation = "fade" },
        -- 0.5: lower values blur the soft card shadows (orange halo on Ember wallpaper)
        -- full-screen / static surfaces: no blur, no compositor animation (they animate themselves)
        { match = { namespace = "^nox:(wallpaper|corners|overview|widgets|agents)$" }, blur = false },
        { match = { namespace = "^nox:(corners|overview|session|polkit|widgets|agents)$" }, no_anim = true },
    }
end

return P

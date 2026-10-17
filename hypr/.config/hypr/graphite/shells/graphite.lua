-- Shell profile: Graphite (new own Quickshell shell, in progress).
--
-- Layer rules are live now (settings.layer_rule_shells) so the shell can be run
-- next to ii during development. env/execs/gestures/binds are a STUB: they become
-- active only with settings.shell = "graphite". Fill `binds` when the shell
-- exposes its GlobalShortcuts (appid "graphite"); keep the same data format as
-- shells/ii.lua.

local P = {}

local function G(name) return hl.dsp.global("graphite:" .. name) end

P.env = {}

P.execs_early = {
    "qs -c graphite &",
}

P.execs = {
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
}

P.gestures = {}

local IPC = "qs -c graphite ipc call "

function P.binds(ctx)
    local X = hl.dsp.exec_cmd
    return {
        -- confirmed IPC targets (shell agent, 2026-10-17)
        { "SUPER + N", X(IPC .. "controlCenter toggle"), desc = "Control Center" },
        { "SUPER + J", X(IPC .. "dock toggle"), desc = "Toggle dock" },
        -- PLACEHOLDER global names (not implemented by the shell yet):
        -- Super tap = launcher on release (mirror of ii's pattern)
        { "SUPER + Super_L", G("launcherToggleRelease"), ignore_mods = true, desc = "Launcher" },
        { "SUPER + Super_R", G("launcherToggleRelease"), ignore_mods = true },
        { "catchall", G("launcherToggleReleaseInterrupt"), ignore_mods = true, transparent = true, non_consuming = true },
        { "XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl s 5%+"), locked = true, repeating = true },
        { "XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 5%-"), locked = true, repeating = true },
    }
end

-- Namespaces: graphite:bar, graphite:dock, graphite:popup, graphite:launcher, graphite:osd
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
    }
end

return P

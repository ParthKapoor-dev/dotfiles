-- Nox design-token DEFAULTS for Hyprland.
--
-- The fallback under ~/.local/state/nox/tokens.lua (the live, merged tokens written by
-- `nox theme render`): the live tokens are deep-merged over this table, so any key they omit
-- falls back to the value here.
--
-- Everything but `hypr` comes from nox/base.lua, which `nox theme render` GENERATES from
-- tokens.json alone (the base look, no preset, no local.json; target "hypr-base"). Nothing
-- is copied by hand any more: change tokens.json and re-render.
--
-- The `hypr` table below is NOT in tokens.json: it holds compositor-only look knobs (blur
-- noise, popin %, dim, ...) that have no meaning for other layers. They are still treated as
-- tokens (tokens.json / a preset may carry a `hypr` key to override them) so no module
-- hardcodes a look value.

local base = require("nox.base")

local hypr = {
    -- Compositor-only look knobs (see header). Durations are in ms like `motion`.
    roundingPower = 2.0,         -- 2 = circle corners (macOS windows are ~circular at 12px)
    gapsWorkspaces = 50,         -- gap between workspaces while sliding
    specialGapsOut = 30,         -- scratchpad (special:special) outer gap
    border = "hairline",         -- "hairline" = 1px faint line on every window, "none" = 0px
    pinnedBorderAlpha = { 0.67, 0.47 }, -- pinned windows keep an accent border (functional cue)
    dimInactive = false,         -- macOS does not dim unfocused windows; focus = shadow
    dimStrength = 0.03,
    dimSpecial = 0.25,           -- dim behind the scratchpad
    tiledShadows = true,         -- false = old ii behaviour (no shadow on tiled windows)
    blurNoise = 0.012,
    blurContrast = 1.0,
    blurBrightness = 1.0,
    blurVibrancyDarkness = 0.35,
    blurSpecial = true,          -- blur behind the scratchpad workspace
    blurAppPopups = false,       -- app menus/popups are app surfaces: no blur (NVIDIA perf)
    popupsIgnoreAlpha = 0.4,
    inputMethodsIgnoreAlpha = 0.8,
    -- Layer blur only samples pixels whose alpha is ABOVE ignore_alpha. It must sit
    -- below the shell's glass alpha or blur silently turns off (the old ii bug:
    -- ignore_alpha 0.79 vs bar alpha 0.76). Nox glass is 0.54..0.78.
    layerIgnoreAlpha = 0.50,     -- nox:* layers (also clamped below min glass alpha)
    layerIgnoreAlphaPadded = 0.50, -- nox:dock / nox:popup: surface is larger than the
                                   -- glass (full-width dock, popup shadow margins) - keep the
                                   -- transparent/shadow area out of the blur
    popinWindowIn = 92,          -- % scale windows pop in from
    popinWindowOut = 95,
    popinLayer = 95,
}

local t = {}
for k, v in pairs(base) do t[k] = v end
t.hypr = hypr
for k, v in pairs(base.hypr or {}) do hypr[k] = v end
return t

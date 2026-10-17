-- Graphite design-token DEFAULTS for Hyprland.
--
-- This is the fallback used when ~/.local/state/graphite/tokens.lua (written by the
-- token renderer from ~/.config/graphite/tokens.json) is missing or incomplete.
-- The live tokens are deep-merged over this table, so any key the renderer omits
-- falls back to the value here.
--
-- Keys mirror tokens.json EXACTLY (preset "sequoia-graphite", copied 2026-10-17).
-- Keep this in sync with tokens.json when the preset changes.
--
-- The `hypr` table at the bottom is NOT in tokens.json: it holds compositor-only
-- look knobs (blur noise, popin %, dim, ...) that have no meaning for other layers.
-- They are still treated as tokens (the renderer may emit a `hypr` key to override
-- them) so no module hardcodes a look value.

return {
    name = "sequoia-graphite",

    color = {
        page = "#070708",
        bg = "#1C1C1E",
        surface = "#2C2C2E",
        raised = "#3A3A3C",
        glass = "#1E1E20",
        label = "#FFFFFF", labelAlpha = 0.88,
        label2Alpha = 0.56,
        label3Alpha = 0.28,
        sepAlpha = 0.10,
        hairAlpha = 0.12,
        fillAlpha = 0.07, fill2Alpha = 0.12, fill3Alpha = 0.18,
        accent = "#0A84FF",
        onAccent = "#FFFFFF",
        green = "#30D158", orange = "#FF9F0A", red = "#FF453A", yellow = "#FFD60A",
        teal = "#64D2FF", blue = "#0A84FF", purple = "#BF5AF2", pink = "#FF375F",
        trafficClose = "#FF5F57", trafficMin = "#FEBC2E", trafficZoom = "#28C840", trafficOff = "#4D4D4D",
    },

    terminal = {
        background = "#1C1C1E", foreground = "#E5E5E7", cursor = "#0A84FF", selection = "#3A3A3C",
        black = "#1C1C1E", red = "#FF453A", green = "#30D158", yellow = "#FFD60A",
        blue = "#0A84FF", magenta = "#BF5AF2", cyan = "#64D2FF", white = "#D1D1D6",
        brightBlack = "#636366", brightRed = "#FF6961", brightGreen = "#4CE06E", brightYellow = "#FFE04A",
        brightBlue = "#409CFF", brightMagenta = "#DA8FFF", brightCyan = "#8ADDFF", brightWhite = "#FFFFFF",
    },

    glass = { alpha = 0.60, menubarAlpha = 0.54, launcherAlpha = 0.78, blurSize = 8, blurPasses = 3, saturation = 1.8 },

    radius = { window = 12, menu = 10, control = 6, panel = 16 },

    size = { menubar = 30, dock = 56, dockMagnify = 1.5, gapsIn = 5, gapsOut = 10, border = 1 },

    font = {
        ui = "SF Pro Text", display = "SF Pro Display", mono = "SF Mono",
        size = 13, sizeSmall = 11, monoSize = 12.5,
    },

    motion = {
        -- cubic-bezier control points (x1,y1,x2,y2); durations in ms. No overshoot.
        ease = { 0.25, 0.1, 0.25, 1.0 },
        sheet = { 0.32, 0.72, 0.0, 1.0 },
        snap = { 0.2, 0.9, 0.1, 1.0 },
        pop = 130, fade = 220, window = 380, sheetMs = 320, workspace = 460,
    },

    shadow = {
        focused = { range = 40, power = 3, color = "#000000", alpha = 0.50, offsetY = 12 },
        unfocused = { range = 20, power = 3, color = "#000000", alpha = 0.24, offsetY = 6 },
    },

    theme = { icons = "WhiteSur-dark", cursor = "macOS", cursorSize = 24, gtk = "adw-gtk3-dark" },

    -- Compositor-only look knobs (see header). Durations are in ms like `motion`.
    hypr = {
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
        -- ignore_alpha 0.79 vs bar alpha 0.76). Graphite glass is 0.54..0.78.
        layerIgnoreAlpha = 0.50,     -- graphite:* layers (also clamped below min glass alpha)
        layerIgnoreAlphaPadded = 0.50, -- graphite:dock / graphite:popup: surface is larger than the
                                       -- glass (full-width dock, popup shadow margins) - keep the
                                       -- transparent/shadow area out of the blur
        popinWindowIn = 92,          -- % scale windows pop in from
        popinWindowOut = 95,
        popinLayer = 95,
    },
}

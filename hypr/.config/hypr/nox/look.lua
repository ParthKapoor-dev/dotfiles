-- Look: gaps, border, rounding, shadow, blur, dim. Every value comes from tokens
-- (tokens.* = shared design tokens, tokens.hypr.* = compositor-only knobs).
--
-- Sequoia Graphite decisions:
--  * Focus is shown by the SHADOW, not by border colour: the focused window gets
--    the large soft `shadow.focused` shadow, others the lighter `shadow.unfocused`
--    alpha. (Hyprland has one global shadow range/offset; only the colour differs
--    between active and inactive, so the unfocused range/offsetY tokens cannot be
--    expressed - the inactive shadow is lighter, not smaller.)
--  * Border: a 1px faint hairline (label colour @ hairAlpha) on EVERY window, same
--    for active and inactive. macOS dark mode draws exactly this 1px light edge so
--    dark windows separate from dark wallpaper and from each other; it carries no
--    focus meaning. tokens.hypr.border = "none" turns it off (0px).
--  * Blur is enabled globally only so layer surfaces (shell glass) can use it;
--    every app window gets no_blur in rules.lua (NVIDIA laptop: blur is the most
--    expensive pass). App popups are not blurred either (tokens.hypr.blurAppPopups).

return function(ctx)
    local C, T = ctx.core, ctx.tokens
    local H = T.hypr

    local hair = C.rgba(T.color.label, T.color.hairAlpha)
    local borderSize = (H.border == "none") and 0 or T.size.border

    -- tokens.glass.saturation (CSS-style, 1 = unchanged) -> Hyprland vibrancy (0..1)
    local vibrancy = C.clamp((T.glass.saturation or 1) - 1, 0, 1)

    hl.config({
        general = {
            gaps_in = T.size.gapsIn,
            gaps_out = T.size.gapsOut,
            gaps_workspaces = H.gapsWorkspaces,
            border_size = borderSize,
            col = {
                active_border = hair,
                inactive_border = hair,
            },
            snap = {
                enabled = true,
                window_gap = T.size.gapsIn,
                monitor_gap = T.size.gapsIn,
                respect_gaps = true,
            },
        },

        decoration = {
            rounding = T.radius.window,
            rounding_power = H.roundingPower,

            shadow = {
                enabled = true,
                range = T.shadow.focused.range,
                render_power = T.shadow.focused.power,
                offset = { 0, T.shadow.focused.offsetY },
                color = C.rgba(T.shadow.focused.color, T.shadow.focused.alpha),
                color_inactive = C.rgba(T.shadow.unfocused.color, T.shadow.unfocused.alpha),
            },

            blur = {
                enabled = true,
                xray = true, -- sample the wallpaper only: readable glass over bright windows
                special = H.blurSpecial,
                popups = H.blurAppPopups,
                popups_ignorealpha = H.popupsIgnoreAlpha,
                input_methods = true,
                input_methods_ignorealpha = H.inputMethodsIgnoreAlpha,
                new_optimizations = true,
                size = T.glass.blurSize,
                passes = T.glass.blurPasses,
                noise = H.blurNoise,
                contrast = H.blurContrast,
                brightness = H.blurBrightness,
                vibrancy = vibrancy,
                vibrancy_darkness = H.blurVibrancyDarkness,
            },

            dim_inactive = H.dimInactive,
            dim_strength = H.dimStrength,
            dim_special = H.dimSpecial,
        },

        misc = {
            background_color = C.rgba(T.color.page, 1),
        },
    })

    -- exported for rules.lua (pinned-window border)
    ctx.look = {
        pinned_border = {
            colors = {
                C.rgba(T.color.accent, H.pinnedBorderAlpha[1]),
                C.rgba(T.color.accent, H.pinnedBorderAlpha[2]),
            },
        },
    }
end

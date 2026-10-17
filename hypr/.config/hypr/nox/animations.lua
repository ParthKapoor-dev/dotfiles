-- Animations from tokens.motion. macOS-like: no overshoot (every curve has
-- y-control-points within 0..1), windows ~window ms, workspaces ~workspace ms,
-- popups/fades fast.
--
-- The table below is the whole mapping: leaf -> duration token + curve token.
-- Change feel by editing tokens, not this file.

return function(ctx)
    local C, T = ctx.core, ctx.tokens
    local M, H = T.motion, T.hypr

    -- curve token name -> Hyprland bezier name
    local curves = { ease = "noxEase", sheet = "noxSheet", snap = "noxSnap" }
    for tok, name in pairs(curves) do
        local p = M[tok]
        hl.curve(name, { type = "bezier", points = { { p[1], p[2] }, { p[3], p[4] } } })
    end

    -- { leaf, duration token (ms), curve token, style }
    local map = {
        { "windowsIn",           "window",    "sheet", "popin " .. H.popinWindowIn .. "%" },
        { "windowsOut",          "fade",      "ease",  "popin " .. H.popinWindowOut .. "%" },
        { "windowsMove",         "window",    "sheet" },
        { "fadeIn",              "fade",      "ease" },
        { "fadeOut",             "fade",      "ease" },
        { "fadeSwitch",          "fade",      "ease" },
        { "fadeShadow",          "fade",      "ease" },
        { "fadeDim",             "fade",      "ease" },
        { "border",              "fade",      "ease" },
        { "layersIn",            "sheetMs",   "sheet", "popin " .. H.popinLayer .. "%" },
        { "layersOut",           "pop",       "ease",  "popin " .. H.popinLayer .. "%" },
        { "fadeLayersIn",        "pop",       "snap" },
        { "fadeLayersOut",       "pop",       "ease" },
        { "workspaces",          "workspace", "sheet", "slide" },
        { "specialWorkspaceIn",  "sheetMs",   "sheet", "slidevert" },
        { "specialWorkspaceOut", "fade",      "ease",  "slidevert" },
        { "zoomFactor",          "fade",      "snap" },
    }

    hl.config({ animations = { enabled = true } })
    for _, a in ipairs(map) do
        hl.animation({
            leaf = a[1],
            enabled = true,
            speed = C.speed(M[a[2]]),
            bezier = curves[a[3]],
            style = a[4],
        })
    end
end

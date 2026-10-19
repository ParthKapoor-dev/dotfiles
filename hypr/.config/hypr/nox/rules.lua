-- Window + layer rules. Port of hyprland/rules.conf (+ custom/rules.conf, empty,
-- + the pinned-border rule from the old generated colors.conf).
-- Layer rules per shell live in shells/<name>.lua (`layer_rules`).
--
-- Rules are applied in list order; for the same effect a later rule wins.

local SIZE_45 = "(monitor_w*.45) (monitor_h*.45)"
local SIZE_60 = "(monitor_w*.60) (monitor_h*.65)"
local SIZE_85 = "(monitor_w*.85) (monitor_h*.85)"
local PIP = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$"

local window_rules = {
    -- Blur OFF for app windows (blur is only for shell layers; NVIDIA perf).
    { match = { class = "^()$", title = "^()$" }, no_blur = true }, -- xwayland context menus
    { match = { class = ".*" }, no_blur = true },

    -- Floating dialogs
    { match = { title = "^(Open File)(.*)$" }, center = true, float = true },
    { match = { title = "^(Select a File)(.*)$" }, center = true, float = true },
    { match = { title = "^(Choose wallpaper)(.*)$" }, center = true, float = true, size = SIZE_60 },
    { match = { title = "^(Open Folder)(.*)$" }, center = true, float = true },
    { match = { title = "^(Save As)(.*)$" }, center = true, float = true },
    { match = { title = "^(Library)(.*)$" }, center = true, float = true },
    { match = { title = "^(File Upload)(.*)$" }, center = true, float = true },
    { match = { title = "^(.*)(wants to save)$" }, center = true, float = true },
    { match = { title = "^(.*)(wants to open)$" }, center = true, float = true },
    { match = { class = "^(blueberry\\.py)$" }, float = true },
    { match = { class = "^(guifetch)$" }, float = true },
    { match = { class = "^(pavucontrol)$" }, float = true, size = SIZE_45, center = true },
    -- screenshot annotation (nox shot annotate): a floating sheet over the desktop
    { match = { class = "^(org\\.satty\\.satty|swappy)$" }, float = true, size = SIZE_85, center = true },
    { match = { class = "^(org.pulseaudio.pavucontrol)$" }, float = true, size = SIZE_45, center = true },
    { match = { class = "^(nm-connection-editor)$" }, float = true, size = SIZE_45, center = true },
    { match = { class = ".*plasmawindowed.*" }, float = true },
    { match = { class = "kcm_.*" }, float = true },
    { match = { class = ".*bluedevilwizard" }, float = true },
    { match = { title = ".*Welcome" }, float = true },
    { match = { title = ".*Shell conflicts.*" }, float = true },
    { match = { class = "org.freedesktop.impl.portal.desktop.kde" }, float = true, size = SIZE_60 },
    { match = { class = "^(Zotero)$" }, float = true, size = SIZE_45 },

    -- kde-material-you-colors theme-switch helper: keep it out of the way
    { match = { class = "^(plasma-changeicons)$" }, float = true, no_initial_focus = true, move = "999999 999999" },
    -- dolphin copy dialog
    { match = { title = "^(Copying — Dolphin)$" }, move = "40 80" },

    -- Tiling
    { match = { class = "^dev\\.warp\\.Warp$" }, tile = true },

    -- Picture-in-Picture
    { match = { title = PIP }, float = true, keep_aspect_ratio = true, pin = true,
      move = "(monitor_w*.73) (monitor_h*.72)", size = "(monitor_w*.25) (monitor_h*.25)" },

    -- Tearing
    { match = { title = ".*\\.exe" }, immediate = true },
    { match = { title = ".*minecraft.*" }, immediate = true },
    { match = { class = "^(steam_app).*" }, immediate = true },

    -- JetBrains IDE focus/rerender fix
    { match = { class = "^jetbrains-.*$", float = true, title = "^$|^\\s$|^win\\d+$" }, no_initial_focus = true },
}

return function(ctx)
    local T, S = ctx.tokens, ctx.settings

    for _, r in ipairs(window_rules) do hl.window_rule(r) end

    -- Old ii look: no shadow on tiled windows. Nox shows focus with the shadow,
    -- so this is off unless tokens.hypr.tiledShadows == false.
    if T.hypr.tiledShadows == false then
        hl.window_rule({ match = { float = false }, no_shadow = true })
    end

    -- Pinned windows keep a visible accent border (functional cue, from look.lua).
    if ctx.look then
        hl.window_rule({ match = { pin = true }, border_color = ctx.look.pinned_border })
    end

    -- Layer rules: every namespace gets xray (blur samples wallpaper only).
    hl.layer_rule({ match = { namespace = ".*" }, xray = true })

    for _, name in ipairs(S.layer_rule_shells) do
        local shell = require("nox.shells." .. name)
        local rules = shell.layer_rules
        if type(rules) == "function" then rules = rules(ctx) end
        for _, r in ipairs(rules or {}) do hl.layer_rule(r) end
    end
end

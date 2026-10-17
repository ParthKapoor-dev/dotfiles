-- Environment variables.
-- Port of hyprland/env.conf + custom/env.conf. Shell-specific variables live in
-- shells/<shell>.lua (`env`). Cursor theme comes from tokens.theme with a fallback
-- when the token's theme is not installed.

local function theme_installed(name)
    local home = os.getenv("HOME") or ""
    for _, dir in ipairs({ home .. "/.local/share/icons/", home .. "/.icons/", "/usr/share/icons/" }) do
        local f = io.open(dir .. name .. "/index.theme", "r")
        if f then f:close(); return true end
        f = io.open(dir .. name .. "/cursors/left_ptr", "r")
        if f then f:close(); return true end
    end
    return false
end

return function(ctx)
    local C, T, S = ctx.core, ctx.tokens, ctx.settings

    local env = {
        -- Wayland
        { "ELECTRON_OZONE_PLATFORM_HINT", "auto" },
        -- Applications (hyprlang expanded $HOME; do the same)
        { "XDG_DATA_DIRS", C.HOME .. "/.local/share/flatpak/exports/share:/var/lib/flatpak/exports/share:/usr/local/share:/usr/share" },
        -- Themes
        { "QT_QPA_PLATFORM", "wayland;xcb" },
        { "QT_QPA_PLATFORMTHEME", "kde" },
        { "XDG_MENU_PREFIX", "plasma-" },
        -- Terminal application
        { "TERMINAL", S.apps.terminal_env },
    }

    -- Cursor consistency for XWayland apps (custom/env.conf).
    local cursor = T.theme.cursor
    if not cursor or not theme_installed(cursor) then cursor = S.cursor_fallback end
    ctx.cursor = { theme = cursor, size = T.theme.cursorSize or 24 }
    env[#env + 1] = { "XCURSOR_THEME", cursor }
    env[#env + 1] = { "XCURSOR_SIZE", tostring(ctx.cursor.size) }

    local shell = require("graphite.shells." .. S.shell)
    for _, kv in ipairs(shell.env or {}) do env[#env + 1] = kv end

    for _, kv in ipairs(env) do
        hl.env(kv[1], kv[2])
    end
end

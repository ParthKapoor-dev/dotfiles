-- Bind group "apps": launchers. Port of `##! Apps` in hyprland/keybinds.conf
-- (launch_first_available.sh in graphite/scripts/ tries each in order).
-- Super+X (text editor) is overridden in binds/custom.lua (2026-10-17 Fixes).

return function(ctx)
    local S = ctx.settings
    local X = hl.dsp.exec_cmd
    local L = S.apps.launch
    local TERM = L .. [[ "${TERMINAL}" "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"]]

    return {
        { "SUPER + Return", X(TERM), desc = "Open terminal" },
        { "SUPER + T", X(TERM), desc = "Open terminal" },
        { "CTRL + ALT + T", X(TERM), desc = "Open terminal" },
        { "SUPER + E", X(L .. [[ "dolphin" "nautilus" "nemo" "thunar" "${TERMINAL}" "kitty -1 fish -c yazi"]]), desc = "Open file browser" },
        { "SUPER + W", X(L .. [[ "google-chrome-stable" "zen-browser" "firefox" "brave" "chromium" "microsoft-edge-stable" "opera" "librewolf"]]), desc = "Open web browser" },
        { "SUPER + C", X(L .. [[ "antigravity" "code" "codium" "cursor" "zed" "zedit" "zeditor" "kate" "gnome-text-editor" "emacs" "command -v nvim && kitty -1 nvim" "command -v micro && kitty -1 micro"]]), desc = "Open code editor" },
        { "CTRL + SUPER + SHIFT + ALT + W", X(L .. [[ "wps" "onlyoffice-desktopeditors" "libreoffice"]]), desc = "Open office app" },
        -- upstream text editor (kate/gnome-text-editor/emacs not installed): unbound by the Fixes
        { "SUPER + X", X(L .. [[ "kate" "gnome-text-editor" "emacs"]]), desc = "Open text editor", enabled = false },
        { "CTRL + SUPER + V", X(L .. [[ "pavucontrol-qt" "pavucontrol"]]), desc = "Open volume mixer" },
        -- settings app (was ii's settings.qml; the shell's own settings are shell.json, Ctrl+Super+/)
        { "SUPER + I", X(L .. [[ "systemsettings" "gnome-control-center"]]), desc = "Open system settings" },
        { "CTRL + SHIFT + Escape", X(L .. [[ "gnome-system-monitor" "plasma-systemmonitor --page-name Processes" "command -v btop && kitty -1 fish -c btop"]]), desc = "Open system monitor" },
    }
end

-- Bind group "apps": launchers. Port of `##! Apps` in hyprland/keybinds.conf
-- (commands byte-identical; launch_first_available.sh tries each in order).
-- Super+X (text editor) is overridden in binds/custom.lua (2026-10-17 Fixes).

return function(ctx)
    local S = ctx.settings
    local X = hl.dsp.exec_cmd
    local L = S.apps.launch
    local TERM = L .. [[ "${TERMINAL}" "kitty -1" "foot" "alacritty" "wezterm" "konsole" "kgx" "uxterm" "xterm"]]

    return {
        { "SUPER + Return", X(TERM) },
        { "SUPER + T", X(TERM) },
        { "CTRL + ALT + T", X(TERM) },
        { "SUPER + E", X(L .. [[ "dolphin" "nautilus" "nemo" "thunar" "${TERMINAL}" "kitty -1 fish -c yazi"]]) },
        { "SUPER + W", X(L .. [[ "google-chrome-stable" "zen-browser" "firefox" "brave" "chromium" "microsoft-edge-stable" "opera" "librewolf"]]) },
        { "SUPER + C", X(L .. [[ "antigravity" "code" "codium" "cursor" "zed" "zedit" "zeditor" "kate" "gnome-text-editor" "emacs" "command -v nvim && kitty -1 nvim" "command -v micro && kitty -1 micro"]]) },
        { "CTRL + SUPER + SHIFT + ALT + W", X(L .. [[ "wps" "onlyoffice-desktopeditors" "libreoffice"]]) },
        -- upstream text editor (kate/gnome-text-editor/emacs not installed): unbound by the Fixes
        { "SUPER + X", X(L .. [[ "kate" "gnome-text-editor" "emacs"]]), enabled = false },
        { "CTRL + SUPER + V", X(L .. [[ "pavucontrol-qt" "pavucontrol"]]) },
        { "SUPER + I", X("XDG_CURRENT_DESKTOP=gnome " .. L .. [[ "qs -p ~/.config/quickshell/]] .. S.vars.qs .. [[/settings.qml" "systemsettings" "gnome-control-center" "better-control"]]) },
        { "CTRL + SHIFT + Escape", X(L .. [[ "gnome-system-monitor" "plasma-systemmonitor --page-name Processes" "command -v btop && kitty -1 fish -c btop"]]) },
    }
end

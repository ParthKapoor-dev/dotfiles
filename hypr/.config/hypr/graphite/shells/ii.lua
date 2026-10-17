-- Shell profile: end-4 illogical-impulse ("ii", old pre-Lua Quickshell config).
--
-- Everything Hyprland needs to host ii: env, autostart, gestures, the "shell" bind
-- group (all `global, quickshell:*` binds + their qs-is-dead fallbacks) and ii's
-- layer rules. Port of the Shell/Utilities/Screen sections of
-- hyprland/keybinds.conf and the Quickshell/ags layer rules of hyprland/rules.conf.
--
-- NOTE: under a Lua config `hyprctl dispatch <old syntax>` and `hyprctl keyword`
-- fail, so ii itself needs _patches/quickshell-ii-lua-dispatch.patch.

local P = {}

local QS = "qs -c ii"
local ALIVE = QS .. " ipc call TEST_ALIVE"
local QSDIR = "~/.config/quickshell/ii"
local HS = "~/.config/hypr/hyprland/scripts"

local function G(name) return hl.dsp.global("quickshell:" .. name) end
local function X(cmd) return hl.dsp.exec_cmd(cmd) end

P.env = {
    { "ILLOGICAL_IMPULSE_VIRTUAL_ENV", "~/.local/state/quickshell/.venv" },
}

P.execs_early = {
    QS .. " &",
    "~/.config/hypr/custom/scripts/__restore_video_wallpaper.sh",
}

P.execs = {
    -- Clipboard history (also pokes ii's cliphist service)
    "wl-paste --type text --watch bash -c 'cliphist store && qs -c ii ipc call cliphistService update'",
    "wl-paste --type image --watch bash -c 'cliphist store && qs -c ii ipc call cliphistService update'",
}

P.gestures = {
    { fingers = 4, direction = "up", action = function() hl.dispatch(G("overviewWorkspacesToggle")) end },
    { fingers = 4, direction = "down", action = function() hl.dispatch(G("overviewWorkspacesClose")) end },
}

function P.binds(ctx)
    local C = ctx.core
    local OCR = ALIVE .. [[ || pidof slurp || grim -g "$(slurp $SLURP_ARGS)" "/tmp/ocr_image.png" && tesseract "/tmp/ocr_image.png" stdout -l $(tesseract --list-langs | awk 'NR>1{print $1}' | tr '\n' '+' | sed 's/\+$/\n/') | wl-copy && rm "/tmp/ocr_image.png"]]

    return {
        -- ##! Shell -- these MUST stay first (Super tap = search on release)
        { "SUPER + Super_L", G("searchToggleRelease"), ignore_mods = true, desc = "Toggle search" },
        { "SUPER + Super_R", G("searchToggleRelease"), ignore_mods = true, desc = "Toggle search" },
        { "SUPER + Super_L", X(ALIVE .. " || pkill fuzzel || fuzzel") },
        { "SUPER + Super_R", X(ALIVE .. " || pkill fuzzel || fuzzel") },
        { "catchall", G("searchToggleReleaseInterrupt"), ignore_mods = true, transparent = true, non_consuming = true },
        { "CTRL + Super_L", G("searchToggleReleaseInterrupt") },
        { "CTRL + Super_R", G("searchToggleReleaseInterrupt") },
        { "SUPER + mouse:272", G("searchToggleReleaseInterrupt") },
        { "SUPER + mouse:273", G("searchToggleReleaseInterrupt") },
        { "SUPER + mouse:274", G("searchToggleReleaseInterrupt") },
        { "SUPER + mouse:275", G("searchToggleReleaseInterrupt") },
        { "SUPER + mouse:276", G("searchToggleReleaseInterrupt") },
        { "SUPER + mouse:277", G("searchToggleReleaseInterrupt") },
        { "SUPER + mouse_up", G("searchToggleReleaseInterrupt") },
        { "SUPER + mouse_down", G("searchToggleReleaseInterrupt") },

        { "Super_L", G("workspaceNumber"), ignore_mods = true, transparent = true },
        { "Super_R", G("workspaceNumber"), ignore_mods = true, transparent = true },
        { "SUPER + Tab", G("overviewWorkspacesToggle") },
        { "SUPER + V", G("overviewClipboardToggle"), desc = "Clipboard history >> clipboard" },
        { "SUPER + Period", G("overviewEmojiToggle"), desc = "Emoji >> clipboard" },
        { "SUPER + A", G("sidebarLeftToggle") },
        { "SUPER + ALT + A", G("sidebarLeftToggleDetach") },
        { "SUPER + B", G("sidebarLeftToggle") },
        { "SUPER + O", G("sidebarLeftToggle") },
        { "SUPER + N", G("sidebarRightToggle"), desc = "Toggle right sidebar" },
        { "SUPER + Slash", G("cheatsheetToggle"), desc = "Toggle cheatsheet" },
        { "SUPER + K", G("oskToggle"), desc = "Toggle on-screen keyboard" },
        { "SUPER + M", G("mediaControlsToggle"), desc = "Toggle media controls" },
        { "SUPER + G", G("overlayToggle") },
        { "CTRL + ALT + Delete", G("sessionToggle"), desc = "Toggle session menu" },
        { "SUPER + J", G("barToggle"), desc = "Toggle bar" },
        { "CTRL + ALT + Delete", X(ALIVE .. " || pkill wlogout || wlogout -p layer-shell") },
        { "SHIFT + SUPER + ALT + Slash", X("qs -p " .. QSDIR .. "/welcome.qml") },

        { "XF86MonBrightnessUp", X(QS .. " ipc call brightness increment || brightnessctl s 5%+"), locked = true, repeating = true },
        { "XF86MonBrightnessDown", X(QS .. " ipc call brightness decrement || brightnessctl s 5%-"), locked = true, repeating = true },

        { "CTRL + SUPER + T", G("wallpaperSelectorToggle"), desc = "Toggle wallpaper selector" },
        { "CTRL + SUPER + ALT + T", G("wallpaperSelectorRandom"), desc = "Select random wallpaper" },
        { "CTRL + SUPER + T", X(ALIVE .. " || " .. QSDIR .. "/scripts/colors/switchwall.sh"), desc = "Change wallpaper" },
        { "CTRL + SUPER + R", X("killall ags agsv1 gjs ydotool qs quickshell; " .. QS .. " &") },
        { "CTRL + SUPER + P", G("panelFamilyCycle") },

        -- ##! Utilities (screenshot / OCR / record) - ii first, CLI fallback when qs is dead
        { "SUPER + V", X(ALIVE .. " || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy"), desc = "Copy clipboard history entry" },
        { "SUPER + Period", X(ALIVE .. " || pkill fuzzel || " .. HS .. "/fuzzel-emoji.sh copy"), desc = "Copy an emoji" },
        { "SUPER + SHIFT + S", G("regionScreenshot") },
        { "SUPER + SHIFT + S", X(ALIVE .. " || pidof slurp || hyprshot --freeze --clipboard-only --mode region --silent") },
        { "SUPER + SHIFT + A", G("regionSearch") },
        { "SUPER + SHIFT + A", X(ALIVE .. " || pidof slurp || " .. HS .. "/snip_to_search.sh") },
        { "SUPER + SHIFT + X", G("regionOcr") },
        { "SUPER + SHIFT + T", G("regionOcr") },
        { "SUPER + SHIFT + X", X(OCR) },
        { "SUPER + SHIFT + T", X(OCR) },
        { "SUPER + SHIFT + R", G("regionRecord"), locked = true },
        { "SUPER + SHIFT + R", X(ALIVE .. " || " .. QSDIR .. "/scripts/videos/record.sh"), locked = true },
        { "SUPER + ALT + R", G("regionRecord"), locked = true },
        { "SUPER + ALT + R", X(ALIVE .. " || " .. QSDIR .. "/scripts/videos/record.sh"), locked = true },
        { "CTRL + ALT + R", X(QSDIR .. "/scripts/videos/record.sh --fullscreen"), locked = true },
        { "SUPER + SHIFT + ALT + R", X(QSDIR .. "/scripts/videos/record.sh --fullscreen --sound"), locked = true },

        -- ##! Screen: keypad zoom through ii, then plain cursor zoom when qs is dead.
        -- (old fallback zoom.sh uses `hyprctl keyword`, which fails under Lua;
        -- `hyprctl eval` does the same clamp 1..3 in-process.)
        { "SUPER + code:82", X(QS .. " ipc call zoom zoomOut"), repeating = true },
        { "SUPER + code:86", X(QS .. " ipc call zoom zoomIn"), repeating = true },
        { "SUPER + code:82", X(ALIVE .. " || " .. C.zoom_eval_cmd(-0.1)), repeating = true },
        { "SUPER + code:86", X(ALIVE .. " || " .. C.zoom_eval_cmd(0.1)), repeating = true },
    }
end

-- Layer rules (also used when another shell is active: settings.layer_rule_shells)
function P.layer_rules(ctx)
    local T = ctx.tokens
    local ia = T.hypr.iiLayerIgnoreAlpha
    local legacyIa = 0.6 -- ags-era rules, kept verbatim (ags is not installed)
    local rules = {
        -- no animation for fast/overlay surfaces
        { match = { namespace = "walker" }, no_anim = true },
        { match = { namespace = "selection" }, no_anim = true },
        { match = { namespace = "overview" }, no_anim = true },
        { match = { namespace = "anyrun" }, no_anim = true },
        { match = { namespace = "indicator.*" }, no_anim = true },
        { match = { namespace = "osk" }, no_anim = true },
        { match = { namespace = "hyprpicker" }, no_anim = true },
        { match = { namespace = "noanim" }, no_anim = true },
        { match = { namespace = "gtk-layer-shell" }, blur = true, ignore_alpha = 0 },
        { match = { namespace = "launcher" }, blur = true, ignore_alpha = 0.5 },
        { match = { namespace = "notifications" }, blur = true, ignore_alpha = 0.69 },
        -- (old `logout_dialog # wlogout, blur on` line had its effect commented out: no-op, dropped)

        -- ags (legacy)
        { match = { namespace = "sideleft.*" }, animation = "slide left" },
        { match = { namespace = "sideright.*" }, animation = "slide right" },
        { match = { namespace = "session[0-9]*" }, blur = true },
        { match = { namespace = "bar[0-9]*" }, blur = true, ignore_alpha = legacyIa },
        { match = { namespace = "barcorner.*" }, blur = true, ignore_alpha = legacyIa },
        { match = { namespace = "dock[0-9]*" }, blur = true, ignore_alpha = legacyIa },
        { match = { namespace = "indicator.*" }, blur = true, ignore_alpha = legacyIa },
        { match = { namespace = "overview[0-9]*" }, blur = true, ignore_alpha = legacyIa },
        { match = { namespace = "cheatsheet[0-9]*" }, blur = true, ignore_alpha = legacyIa },
        { match = { namespace = "sideright[0-9]*" }, blur = true, ignore_alpha = legacyIa },
        { match = { namespace = "sideleft[0-9]*" }, blur = true, ignore_alpha = legacyIa },
        { match = { namespace = "osk[0-9]*" }, blur = true, ignore_alpha = legacyIa },

        -- Quickshell: illogical-impulse.
        -- FIX: ignore_alpha was 0.79 while ii's bar/panels are drawn at alpha 0.76
        -- (backgroundTransparency 0.24) -> every pixel was ignored, blur never showed.
        { match = { namespace = "quickshell:.*" }, blur_popups = true, blur = true, ignore_alpha = ia },
        { match = { namespace = "quickshell:bar" }, animation = "slide" },
        { match = { namespace = "quickshell:actionCenter" }, no_anim = true },
        { match = { namespace = "quickshell:cheatsheet" }, animation = "slide bottom" },
        { match = { namespace = "quickshell:dock" }, animation = "slide bottom" },
        { match = { namespace = "quickshell:screenCorners" }, animation = "popin 120%" },
        { match = { namespace = "quickshell:lockWindowPusher" }, no_anim = true },
        { match = { namespace = "quickshell:notificationPopup" }, animation = "fade" },
        { match = { namespace = "quickshell:overlay" }, no_anim = true, ignore_alpha = 1 },
        { match = { namespace = "quickshell:overview" }, no_anim = true },
        { match = { namespace = "quickshell:osk" }, animation = "slide bottom" },
        { match = { namespace = "quickshell:polkit" }, no_anim = true },
        { match = { namespace = "quickshell:popup" }, xray = false, ignore_alpha = 1 }, -- bar tooltips: no tint
        { match = { namespace = "quickshell:mediaControls" }, ignore_alpha = 1 },
        { match = { namespace = "quickshell:reloadPopup" }, animation = "slide" },
        { match = { namespace = "quickshell:regionSelector" }, no_anim = true },
        { match = { namespace = "quickshell:screenshot" }, no_anim = true },
        { match = { namespace = "quickshell:session" }, blur = true, no_anim = true, ignore_alpha = 0 },
        { match = { namespace = "quickshell:sidebarRight" }, animation = "slide right" },
        { match = { namespace = "quickshell:sidebarLeft" }, animation = "slide left" },
        { match = { namespace = "quickshell:verticalBar" }, animation = "slide" },
        { match = { namespace = "quickshell:osk" }, order = -1 },
        -- Quickshell: waffles
        { match = { namespace = "quickshell:wallpaperSelector" }, animation = "slide top" },
        { match = { namespace = "quickshell:wNotificationCenter" }, no_anim = true },
        { match = { namespace = "quickshell:wOnScreenDisplay" }, no_anim = true },
        { match = { namespace = "quickshell:wStartMenu" }, no_anim = true },
        { match = { namespace = "quickshell:wTaskView" }, ignore_alpha = 0, no_anim = true },

        -- Launchers need to be FAST
        { match = { namespace = "gtk4-layer-shell" }, no_anim = true },
    }
    return rules
end

return P

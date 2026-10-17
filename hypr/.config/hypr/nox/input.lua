-- Input + behaviour (everything functional that is not a look value).
-- Port of hyprland/general.conf (input, gestures, misc, binds, cursor, dwindle,
-- xwayland, non-look `general` keys) + custom/general.conf (misc.vrr).

local layouts = require("graphite.layouts")

return function(ctx)
    local S = ctx.settings

    hl.config({
        input = {
            kb_layout = "us",
            numlock_by_default = true,
            repeat_delay = 250,
            repeat_rate = 35,
            follow_mouse = 1,
            off_window_axis_events = 2,
            touchpad = {
                natural_scroll = true,
                disable_while_typing = true,
                clickfinger_behavior = true,
                scroll_factor = 0.7,
            },
        },

        gestures = {
            workspace_swipe_distance = 700,
            workspace_swipe_cancel_ratio = 0.2,
            workspace_swipe_min_speed_to_force = 5,
            workspace_swipe_direction_lock = true,
            workspace_swipe_direction_lock_threshold = 10,
            workspace_swipe_create_new = true,
        },

        general = {
            resize_on_border = true,
            no_focus_fallback = true,
            allow_tearing = true, -- lets the `immediate` window rule work
            -- first of settings.layouts, or the session's last choice (graphite/layouts.lua)
            layout = layouts.initial(S),
        },

        dwindle = {
            preserve_split = true,
            smart_split = false,
            smart_resizing = false,
        },
        master = (S.layout_options or {}).master,
        scrolling = (S.layout_options or {}).scrolling,

        misc = {
            disable_hyprland_logo = true,
            disable_splash_rendering = true,
            vrr = 2, -- custom/general.conf: VRR only for fullscreen (eDP flicker-safe)
            mouse_move_enables_dpms = true,
            key_press_enables_dpms = true,
            animate_manual_resizes = false,
            animate_mouse_windowdragging = false,
            enable_swallow = false,
            swallow_regex = "(foot|kitty|allacritty|Alacritty)",
            on_focus_under_fullscreen = 2,
            allow_session_lock_restore = true,
            session_lock_xray = true,
            initial_workspace_tracking = 0,
            focus_on_activate = true,
        },

        binds = {
            scroll_event_delay = 0,
            hide_special_on_workspace_change = true,
        },

        cursor = {
            zoom_factor = 1,
            zoom_rigid = false,
            zoom_disable_aa = true,
            hotspot_padding = 1,
        },

        xwayland = {
            force_zero_scaling = true,
        },
    })

    -- `hyprctl eval 'graphite_layout("next")'` entry point for bin/graphite-layout
    layouts.install_global(S)

    -- Trackpad gestures. Shell-specific gestures (overview) come from the shell profile.
    local gestures = {
        { fingers = 3, direction = "swipe", action = "move" },
        { fingers = 3, direction = "pinch", action = "float" },
        { fingers = 4, direction = "horizontal", action = "workspace" },
    }
    local shell = require("graphite.shells." .. S.shell)
    for _, g in ipairs(shell.gestures or {}) do gestures[#gestures + 1] = g end
    for _, g in ipairs(gestures) do hl.gesture(g) end
end

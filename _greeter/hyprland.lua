-- nox greeter compositor: the smallest Hyprland that shows the greeter (installed as
-- /etc/nox-greeter/hyprland.lua, run by launch.sh as the greetd `greeter` user).
-- No binds, no animations (the greeter animates itself). Monitors match the session's
-- hypr/nox/monitors.lua so the login screen and the desktop use the same modes and scale.
-- When the greeter quits (session launched, or crashed), Hyprland exits with it.

local shell = os.getenv("NOX_GREETER_SHELL") or "/etc/nox-greeter/shell"

for _, m in ipairs({
    { output = "", mode = "preferred", position = "auto", scale = "auto" },
    { output = "HDMI-A-1", mode = "1920x1080@60", position = "0x0", scale = "1" },
    { output = "eDP-1", mode = "1920x1080@144", position = "1920x0", scale = "1.25" },
}) do hl.monitor(m) end

hl.config({
    input = {
        kb_layout = "us",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,
        touchpad = { natural_scroll = true, disable_while_typing = true, clickfinger_behavior = true },
    },
    general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
    decoration = { rounding = 0, shadow = { enabled = false }, blur = { enabled = false } },
    animations = { enabled = false },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        disable_watchdog_warning = true,
        background_color = 0xff000000,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
    },
    ecosystem = { no_update_news = true, no_donation_nag = true },
})

hl.on("hyprland.start", function()
    hl.exec_cmd("sh -c 'qs -p \"" .. shell .. "\" -n; hyprctl dispatch \"hl.dsp.exit()\"'")
end)

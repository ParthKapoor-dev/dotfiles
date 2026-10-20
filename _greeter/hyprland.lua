-- nox greeter compositor: the smallest Hyprland that shows the greeter (installed as
-- /etc/nox-greeter/hyprland.lua, run by launch.sh as the greetd `greeter` user).
-- No binds, no animations (the greeter animates itself). Monitors match the session's: `nox
-- greeter sync` copies ~/.config/hypr/nox/machine.lua (written by `nox detect`) next to the
-- theme in /var/lib/nox-greeter, so the login screen and the desktop use the same modes and
-- scale; without it every output gets its preferred mode.
-- When the greeter quits (session launched, or crashed), Hyprland exits with it.

local shell = os.getenv("NOX_GREETER_SHELL") or "/etc/nox-greeter/shell"
local data = os.getenv("NOX_GREETER_DATA") or "/var/lib/nox-greeter"

local monitors = { { output = "", mode = "preferred", position = "auto", scale = "auto" } }
local ok, machine = pcall(dofile, data .. "/machine.lua")
if ok and type(machine) == "table" and type(machine.settings) == "table" and type(machine.settings.monitors) == "table" then
    monitors = machine.settings.monitors
end
for _, m in ipairs(monitors) do hl.monitor(m) end

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

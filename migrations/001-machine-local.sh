#!/usr/bin/env bash
# 001 (2026-10-20): machine values moved out of tracked files into git-ignored local files.
# Before: monitors were hardcoded in hypr/nox/monitors.lua (and _greeter/hyprland.lua), the
# laptop mic in shell.json voice.source, BAT1 in nox battery. Now `nox detect` writes them to
# ~/.config/nox/machine.json, shell.local.json and ~/.config/hypr/nox/machine.lua.
# Seeds machine.json with the monitor table the tracked monitors.lua had, so an install that ran
# the old config keeps the same rules (also for a monitor that is unplugged right now), then
# runs nox detect --yes (keeps saved monitor values, adds what is new).
set -euo pipefail
conf="${NOX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nox}"
m="$conf/machine.json"
if [ ! -s "$m" ]; then
    mkdir -p "$conf"
    cat >"$m" <<'JSON'
{
  "monitors": [
    { "output": "HDMI-A-1", "mode": "1920x1080@60", "position": "0x0", "scale": "1" },
    { "output": "eDP-1", "mode": "1920x1080@144", "position": "1920x0", "scale": "1.25" }
  ]
}
JSON
    echo "seeded $m with the monitors of the old tracked monitors.lua"
fi
nox detect --yes

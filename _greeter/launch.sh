#!/bin/sh
# greetd greeter command for the nox login screen (installed as /etc/nox-greeter/launch.sh,
# referenced from /etc/greetd/config.toml by `nox greeter on`). Runs as the `greeter` user.
#
# Never leaves you without a login: if the greeter Hyprland exits without having launched a
# session (crash, missing file, GPU trouble), this falls back to tuigreet in the same greetd
# slot. `touch /etc/nox-greeter/disabled` (as root) makes it go straight to tuigreet.
# (the NOX_GREETER_* overrides are for `nox greeter nested`, which runs this very script)
ETC="${NOX_GREETER_ETC:-/etc/nox-greeter}"
CACHE="${NOX_GREETER_CACHE:-/var/cache/nox-greeter}"
FALLBACK="${NOX_GREETER_FALLBACK:-tuigreet --time --asterisks --cmd start-hyprland}"
LOG="$CACHE/greeter.log"

fallback() {
    echo "$(date '+%F %T') fallback to tuigreet: $1" >>"$LOG" 2>/dev/null
    exec $FALLBACK
}

[ -e "$ETC/disabled" ] && fallback "disabled"
command -v Hyprland >/dev/null 2>&1 && command -v qs >/dev/null 2>&1 || fallback "Hyprland or qs missing"
[ -r "$ETC/hyprland.lua" ] && [ -r "$ETC/shell/shell.qml" ] || fallback "greeter files missing"
export NOX_GREETER_SHELL="$ETC/shell"

# the greeter user's home is /, so give Hyprland + Quickshell writable state of their own
export XDG_CACHE_HOME="$CACHE/cache" XDG_STATE_HOME="$CACHE/state" XDG_DATA_HOME="$CACHE/data" XDG_CONFIG_HOME="$CACHE/config"
mkdir -p "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" 2>/dev/null
export XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=Hyprland QT_QPA_PLATFORM=wayland XCURSOR_SIZE=24
marker="${XDG_RUNTIME_DIR:-/tmp}/nox-greeter-launched"
rm -f "$marker"

# keep the last 3 compositor logs
for i in 2 1; do [ -f "$CACHE/hyprland.$i.log" ] && mv -f "$CACHE/hyprland.$i.log" "$CACHE/hyprland.$((i + 1)).log"; done
[ -f "$CACHE/hyprland.log" ] && mv -f "$CACHE/hyprland.log" "$CACHE/hyprland.1.log"

Hyprland -c "$ETC/hyprland.lua" >"$CACHE/hyprland.log" 2>&1
rc=$?

if [ -e "$marker" ]; then
    rm -f "$marker"
    exit 0              # session handed to greetd: it starts it now
fi
fallback "greeter exited (rc=$rc) without launching a session"

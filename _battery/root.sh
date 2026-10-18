#!/bin/sh
# Root half of `nox battery limit <N>`: a charge cap other than UPower's default 80%.
# Not needed for the 80% <-> 100% toggle: upowerd does that over D-Bus without sudo
# (see nox/.local/lib/nox/battery). upowerd takes the cap from the udev property
# CHARGE_LIMIT=<start>,<end> ("_" = skip; upower's 60-upower-battery hwdb sets 75,80), so a
# different cap is one udev rule ordered after upower's 60-upower-battery.rules.
#   root.sh install <60-99>   write $RULE (CHARGE_LIMIT=_,<N> for $BAT), reload udev,
#                             restart upower (it re-reads the cap and re-applies on/off)
#   root.sh uninstall         remove $RULE: back to upower's default (80%)
#   root.sh status            rule, udev property, UPower state, firmware value
# Idempotent; a foreign file at $RULE is kept as $RULE.bak. Restarting upower makes the bar's
# battery widget reconnect (a second without data).
set -eu
BAT=BAT1
SYS=/sys/class/power_supply/$BAT
RULE=/etc/udev/rules.d/61-nox-battery.rules
MARK="# nox battery:"
OBJ=/org/freedesktop/UPower/devices/battery_$BAT
say() { printf 'nox battery (root): %s\n' "$*"; }
die() { printf 'nox battery (root): %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root (sudo)"
[ -e "$SYS/charge_control_end_threshold" ] || die "$SYS has no charge_control_end_threshold"

prop() { busctl --timeout=5 get-property org.freedesktop.UPower "$OBJ" org.freedesktop.UPower.Device "$1" 2>/dev/null | awk '{print $2}'; }
reload() {   # udev env -> upowerd -> firmware
    udevadm control --reload
    udevadm trigger --settle --action=change "$SYS"
    systemctl restart upower.service
    i=0; while [ "$(prop ChargeThresholdSupported)" != true ] && [ $i -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
    cap=$(prop ChargeEndThreshold); on=$(prop ChargeThresholdEnabled)
    # upowerd re-applies a saved "on" at start; if it did not, write the cap itself
    if [ "$on" = true ] && [ "$(cat "$SYS/charge_control_end_threshold")" != "$cap" ]; then
        echo "$cap" >"$SYS/charge_control_end_threshold"
    fi
    say "cap now ${cap:-?}% (protection $([ "$on" = true ] && echo on || echo off)), firmware $(cat "$SYS/charge_control_end_threshold")%"
}

case "${1:-}" in
    install)
        n="${2:-}"
        case "$n" in '' | *[!0-9]*) die "usage: root.sh install <60-99>" ;; esac
        [ "$n" -ge 60 ] && [ "$n" -le 99 ] || die "cap must be 60-99 (100 = nox battery full)"
        if [ -e "$RULE" ] && ! grep -q "^$MARK" "$RULE"; then cp -p "$RULE" "$RULE.bak"; say "kept foreign $RULE as $RULE.bak"; fi
        tmp="$RULE.nox-tmp"
        cat >"$tmp" <<EOF
$MARK charge cap for $BAT (base0/_battery/root.sh install $n; uninstall = upower's 80%).
# upowerd reads CHARGE_LIMIT=<start>,<end> ("_" = none) when it adds the battery.
ACTION!="remove", SUBSYSTEM=="power_supply", KERNEL=="$BAT", ENV{CHARGE_LIMIT}="_,$n"
EOF
        chmod 644 "$tmp"
        mv -f "$tmp" "$RULE"
        say "wrote $RULE (cap $n%)"
        reload
        ;;
    uninstall)
        if [ -e "$RULE" ] && grep -q "^$MARK" "$RULE"; then rm -f "$RULE"; say "removed $RULE"
        else say "nothing to remove ($RULE not ours or absent)"; fi
        reload
        ;;
    status)
        if [ -e "$RULE" ]; then say "rule: $(grep -o 'CHARGE_LIMIT}="[^"]*"' "$RULE")  ($RULE)"; else say "rule: none (upower default)"; fi
        say "udev: $(udevadm info -q property "$SYS" | grep '^CHARGE_LIMIT=' || echo 'no CHARGE_LIMIT')"
        say "upower: protection $(prop ChargeThresholdEnabled), cap $(prop ChargeEndThreshold)%"
        say "firmware: $(cat "$SYS/charge_control_end_threshold")%"
        ;;
    *) die "usage: root.sh install <60-99> | uninstall | status" ;;
esac

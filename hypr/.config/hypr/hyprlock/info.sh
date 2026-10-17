#!/usr/bin/env bash
# Text sources for the Nox hyprlock layouts (cmd[...] labels).
# Output may contain Pango markup; everything user-controlled is escaped.
#
#   info.sh date                 SATURDAY, 17 OCTOBER
#   info.sh name [upper]         display name (GECOS, else $USER)
#   info.sh initial              first letter of the display name
#   info.sh np [upper]           "<b>title</b>\nartist" of the playing/paused player, else empty
#   info.sh host                 VOID · ARCH
#   info.sh session              HYPRLAND 0.55.4
#   info.sh uptime               1D 03:12
#   info.sh battery              84% / ⚡84% / empty on machines without a battery
#   info.sh caps                 "Caps Lock is on" or empty
#   info.sh span 'ATTRS' <cmd..> wrap a command's output in <span ATTRS> (hyprlock
#                                sets the font weight itself, so weight/tracking go here)

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
upper() { tr '[:lower:]' '[:upper:]'; }

display_name() {
    local n
    n=$(getent passwd "$USER" 2>/dev/null | cut -d: -f5 | cut -d, -f1)
    [ -n "$n" ] || n="${USER^}"
    printf '%s' "$n"
}

case "${1:-}" in
    span)
        attrs="$2"; shift 2
        out=$("$0" "$@")
        [ -n "$out" ] && printf '<span %s>%s</span>' "$attrs" "$out"
        ;;
    date) LC_TIME=C date +'%A, %-d %B' | upper ;;
    name)
        if [ "${2:-}" = upper ]; then display_name | upper | esc; else display_name | esc; fi
        ;;
    initial) display_name | cut -c1 | upper | esc ;;
    np)
        st=$(playerctl status 2>/dev/null) || exit 0
        case "$st" in Playing | Paused) ;; *) exit 0 ;; esac
        title=$(playerctl metadata title 2>/dev/null)
        artist=$(playerctl metadata artist 2>/dev/null)
        [ -n "$title" ] || exit 0
        if [ "${2:-}" = upper ]; then
            title=$(printf '%s' "$title" | upper)
            artist=$(printf '%s' "$artist" | upper)
        fi
        mark=""
        [ "$st" = Paused ] && mark="  ‖"
        printf '<b>%s</b>%s\n<span alpha="56%%">%s</span>' \
            "$(printf '%s' "$title" | esc)" "$mark" "$(printf '%s' "$artist" | esc)"
        ;;
    host)
        id=$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-linux}")
        printf '%s · %s' "$(cat /etc/hostname 2>/dev/null || uname -n)" "$id" | upper | esc
        ;;
    session)
        v=$(hyprctl -j version 2>/dev/null | jq -r '.tag // empty' 2>/dev/null)
        printf 'HYPRLAND %s' "${v#v}"
        ;;
    uptime)
        read -r up _ </proc/uptime
        s=${up%.*}
        printf '%dD %02d:%02d' $((s / 86400)) $((s % 86400 / 3600)) $((s % 3600 / 60))
        ;;
    battery)
        for b in /sys/class/power_supply/BAT*; do
            [ -r "$b/capacity" ] || continue
            cap=$(cat "$b/capacity")
            if [ "$(cat "$b/status" 2>/dev/null)" = Charging ]; then
                printf '⚡%s%%' "$cap"
            else
                printf '%s%%' "$cap"
            fi
            exit 0
        done
        ;;
    caps)
        caps=$(hyprctl -j devices 2>/dev/null | jq -r '[.keyboards[] | select(.main == true) | .capsLock][0] // false' 2>/dev/null)
        [ "$caps" = true ] && printf 'Caps Lock is on'
        ;;
    *) echo "usage: info.sh span|date|name|initial|np|host|session|uptime|battery|caps" >&2; exit 2 ;;
esac
exit 0

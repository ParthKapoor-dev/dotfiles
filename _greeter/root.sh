#!/bin/sh
# Root half of `nox greeter install|on|off` (run through sudo by the nox greeter module).
#   root.sh install <src> <user>   copy <src> (this directory) to /etc/nox-greeter, create
#                                  /var/lib/nox-greeter (owned by <user>: `nox greeter sync`
#                                  writes it without sudo) and /var/cache/nox-greeter (greeter's)
#   root.sh check                  every file the greeter needs, tested AS the greeter user
#   root.sh on                     greetd -> /etc/nox-greeter/launch.sh (keeps config.toml.before-nox)
#   root.sh off                    greetd -> tuigreet again
# Never restarts greetd (that would end the running session): changes apply at the next login screen.
set -eu
ETC=/etc/nox-greeter
DATA=/var/lib/nox-greeter
CACHE=/var/cache/nox-greeter
CONF=/etc/greetd/config.toml
BACKUP=/etc/greetd/config.toml.before-nox
GUSER=greeter
say() { printf 'nox greeter (root): %s\n' "$*"; }
die() { printf 'nox greeter (root): %s\n' "$*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die "run as root (sudo)"
id "$GUSER" >/dev/null 2>&1 || die "no '$GUSER' user (is greetd installed?)"

write_conf() {   # $1 = greeter command
    tmp="$CONF.nox-tmp"
    cat >"$tmp" <<EOF
# greetd: written by \`nox greeter on|off\` (base0/_greeter/root.sh); previous file: $BACKUP
[terminal]
vt = 1

[default_session]
command = "$1"
user = "$GUSER"
EOF
    chmod 644 "$tmp"
    mv -f "$tmp" "$CONF"
}

check() {
    bad=0
    as() { runuser -u "$GUSER" -- "$@"; }
    for f in "$ETC/launch.sh" "$ETC/hyprland.lua" "$ETC/shell/shell.qml" "$ETC/shell/Greeter.qml" \
             "$DATA/theme.json" "$DATA/greeter.json" "$DATA/wallpaper.jpg"; do
        if as test -r "$f"; then say "ok   readable by $GUSER: $f"; else say "FAIL not readable by $GUSER: $f"; bad=1; fi
    done
    for f in "$DATA"/fonts/*; do [ -e "$f" ] || continue
        as test -r "$f" && say "ok   font: $(basename "$f")" || { say "FAIL font: $f"; bad=1; }
    done
    if as sh -c "mkdir -p '$CACHE/check' && rmdir '$CACHE/check'"; then say "ok   $CACHE writable by $GUSER"; else say "FAIL $CACHE not writable by $GUSER"; bad=1; fi
    for c in Hyprland qs tuigreet hyprctl; do
        as sh -c "command -v $c" >/dev/null && say "ok   $c on the greeter's PATH" || { say "FAIL $c missing"; bad=1; }
    done
    # the compositor config, parsed by Hyprland as the greeter user
    if out=$(cd / && as env XDG_RUNTIME_DIR=/tmp timeout 60 Hyprland --verify-config -c "$ETC/hyprland.lua" 2>&1) \
        && printf '%s' "$out" | grep -q "config ok"; then say "ok   hyprland.lua parses (as $GUSER)"
    else say "FAIL hyprland.lua: $(printf '%s' "$out" | tail -3)"; bad=1; fi
    id -nG "$GUSER" | grep -qw video && say "ok   $GUSER is in group video" || say "warn $GUSER is not in group video"
    [ "$bad" = 0 ] && say "all checks passed" || die "checks failed (login screen NOT switched)"
}

case "${1:-}" in
    install)
        src="${2:?src}"; user="${3:?user}"
        [ -r "$src/launch.sh" ] && [ -r "$src/shell/shell.qml" ] || die "bad source dir: $src"
        install -d -m 755 "$ETC" "$ETC/shell"
        install -m 755 "$src/launch.sh" "$ETC/launch.sh"
        install -m 644 "$src/hyprland.lua" "$ETC/hyprland.lua"
        rm -f "$ETC"/shell/*.qml
        for f in "$src"/shell/*.qml; do install -m 644 "$f" "$ETC/shell/"; done
        install -d -m 755 -o "$user" -g "$(id -gn "$user")" "$DATA"
        install -d -m 700 -o "$GUSER" -g "$GUSER" "$CACHE"
        say "installed $ETC, $DATA (owner $user), $CACHE (owner $GUSER)"
        ;;
    check) check ;;
    on)
        [ -x "$ETC/launch.sh" ] || die "not installed (nox greeter install)"
        check
        [ -e "$BACKUP" ] || cp -p "$CONF" "$BACKUP"
        write_conf "$ETC/launch.sh"
        say "greetd now starts the nox greeter at the next login screen (backup: $BACKUP)"
        ;;
    off)
        if [ -e "$BACKUP" ]; then cp -p "$BACKUP" "$CONF"; say "restored $CONF from $BACKUP"
        else write_conf "tuigreet --time --asterisks --cmd start-hyprland"; fi
        say "greetd starts tuigreet again at the next login screen"
        ;;
    *) die "usage: root.sh install <src> <user> | check | on | off" ;;
esac

#!/usr/bin/env bash
# install.sh - set up the nox desktop from this repo on Arch Linux.
#
#   ./install.sh                 every core step, then a prompt for each optional extra
#   ./install.sh --dry-run       report what is done and what would run; changes nothing
#   ./install.sh --only stow,theme      just these steps (an extra named here runs without a prompt)
#   ./install.sh --skip packages        everything but these
#   ./install.sh --yes           answer yes to every prompt (sudo steps still ask for the password)
#   ./install.sh --list          list the steps
#
# Idempotent: every step checks first and reports "ok" when there is nothing to do, so it is
# safe to re-run after a pull (`nox update` does the stow + theme part for you).
#
# Core steps:   preflight packages stow migrate detect theme units
# Extras:       greeter battery etc voice phone hook notes   (asked one by one; need --only or y)
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TARGET="$HOME"
CORE=(preflight packages stow migrate detect theme units)
EXTRAS=(greeter battery etc voice phone hook notes)
# stow packages whose target dirs also hold files from elsewhere: link files, never fold the dir
NO_FOLD=" bin systemd-desktop "
# user units enabled by the units step (kdeconnect-rs is started by `nox phone on` / the phone step)
UNITS=(nox-greeter-sync.path)

DRY=0 YES=0 ONLY="" SKIP=""
# no nox state yet = a fresh install: migrations (which move an older setup forward) are only
# recorded as done, never run
FRESH=0; [ -d "${XDG_STATE_HOME:-$HOME/.local/state}/nox" ] || FRESH=1
if [ -t 1 ]; then G=$'\e[32m' Y=$'\e[33m' R=$'\e[31m' B=$'\e[1m' D=$'\e[2m' N=$'\e[0m'; else G="" Y="" R="" B="" D="" N=""; fi

usage() { sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "$0"; }
while [ $# -gt 0 ]; do
    case "$1" in
        -n | --dry-run) DRY=1 ;;
        -y | --yes) YES=1 ;;
        --only) ONLY="${2:?--only needs a list}"; shift ;;
        --only=*) ONLY="${1#*=}" ;;
        --skip) SKIP="${2:?--skip needs a list}"; shift ;;
        --skip=*) SKIP="${1#*=}" ;;
        --list) printf 'core:   %s\nextras: %s\n' "${CORE[*]}" "${EXTRAS[*]}"; exit 0 ;;
        -h | --help) usage; exit 0 ;;
        *) echo "install.sh: unknown option '$1' (see --help)" >&2; exit 2 ;;
    esac
    shift
done
for s in ${ONLY//,/ } ${SKIP//,/ }; do
    case " ${CORE[*]} ${EXTRAS[*]} extras " in *" $s "*) ;; *) echo "install.sh: unknown step '$s' (--list)" >&2; exit 2 ;; esac
done
[ "$ONLY" = extras ] && ONLY="${EXTRAS[*]}" && ONLY="${ONLY// /,}"

ok() { printf '  %s[ok]%s   %s\n' "$G" "$N" "$*"; }
todo() { printf '  %s[todo]%s %s\n' "$Y" "$N" "$*"; }
skip() { printf '  %s[skip]%s %s\n' "$D" "$N" "$*"; }
bad() { printf '  %s[fail]%s %s\n' "$R" "$N" "$*"; FAILED=$((FAILED + 1)); }
step() { printf '\n%s== %s%s %s%s%s\n' "$B" "$1" "$N" "$D" "${2:-}" "$N"; }
# run CMD... : print it; execute unless --dry-run
run() {
    printf '  %s$ %s%s\n' "$D" "$*" "$N"
    [ "$DRY" = 1 ] && return 0
    "$@"
}
ask() {   # ask "question" -> 0 = yes
    [ "$YES" = 1 ] && return 0
    [ -t 0 ] || return 1
    local a; read -rp "  ${Y}?${N} $1 [y/N] " a
    [[ "$a" =~ ^[Yy] ]]
}
selected() {   # is step $1 selected by --only/--skip?
    [ -n "$ONLY" ] && { case ",$ONLY," in *",$1,"*) ;; *) return 1 ;; esac; }
    case ",$SKIP," in *",$1,"*) return 1 ;; esac
    return 0
}
explicit() { case ",$ONLY," in *",$1,"*) return 0 ;; esac; return 1; }
# the repo's own nox (works before the stow step has linked ~/.local/bin/nox)
nox() { "$REPO/nox/.local/bin/nox" "$@"; }
FAILED=0

# ------------------------------------------------------------------ manifests
# entries of a packages/*.txt file, one per line, alternatives separated by spaces
entries() { sed -e 's/#.*//' -e 's/[[:space:]]*|[[:space:]]*/ /g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//' "$1" | grep -v -e '^$' -e '^manual:'; }
satisfied() {   # satisfied ALT... : any package installed (provides count) or path present
    local a
    for a in "$@"; do
        case "$a" in
            /* | '~'*) [ -e "${a/#\~/$HOME}" ] && return 0 ;;
            *) pacman -T "$a" >/dev/null 2>&1 && return 0 ;;
        esac
    done
    return 1
}
missing_from() {   # print the first alternative of every unsatisfied entry of manifest $1
    local line
    while read -r line; do
        # shellcheck disable=SC2086
        satisfied $line || printf '%s\n' "${line%% *}"
    done < <(entries "$1")
}
aur_helper() { for h in paru yay; do command -v "$h" >/dev/null && { echo "$h"; return; }; done; }
install_pkgs() {   # install_pkgs PKG... : repo packages with pacman, the rest with the AUR helper
    local repo=() aur=() p h
    for p in "$@"; do if pacman -Si "$p" >/dev/null 2>&1; then repo+=("$p"); else aur+=("$p"); fi; done
    [ ${#repo[@]} -gt 0 ] && { run sudo pacman -Syu --needed "${repo[@]}" || bad "pacman failed"; }
    if [ ${#aur[@]} -gt 0 ]; then
        h=$(aur_helper)
        if [ -n "$h" ]; then run "$h" -S --needed "${aur[@]}" || bad "$h failed"
        else todo "no AUR helper (paru/yay): install by hand: ${aur[*]}"; fi
    fi
}

# ------------------------------------------------------------------ core steps
s_preflight() {
    step preflight "Arch, not root, repo"
    [ "$(id -u)" != 0 ] && ok "running as $(id -un)" || { bad "do not run as root (sudo is asked for where needed)"; exit 1; }
    if [ -f /etc/arch-release ] && command -v pacman >/dev/null; then ok "Arch Linux (pacman)"; else bad "not Arch Linux: packages step will not work"; fi
    ok "repo: $REPO ($(git -C "$REPO" describe --tags --always 2>/dev/null || echo no git), VERSION $(cat "$REPO/VERSION" 2>/dev/null || echo ?))"
    command -v sudo >/dev/null && ok "sudo available" || todo "sudo missing: sudo steps (packages, greeter, battery, etc) will fail"
}

s_packages() {
    step packages "packages/pacman.txt + aur.txt"
    local f miss=() all=()
    for f in pacman aur; do
        mapfile -t miss < <(missing_from "$REPO/packages/$f.txt")
        if [ ${#miss[@]} -eq 0 ]; then ok "$f.txt: all $(entries "$REPO/packages/$f.txt" | wc -l) installed"
        else todo "$f.txt: ${#miss[@]} missing: ${miss[*]}"; all+=("${miss[@]}"); fi
    done
    [ ${#all[@]} -eq 0 ] && return
    install_pkgs "${all[@]}"
}

s_stow() {
    step stow "link every package dir into ~ (GNU stow)"
    command -v stow >/dev/null || { bad "stow not installed (packages step)"; return; }
    local pkgs pkg fold out conflicts c ts n=0
    mapfile -t pkgs < <(cd "$REPO" && find . -mindepth 1 -maxdepth 1 -type d ! -name '.*' ! -name '_*' ! -name packages ! -name migrations ! -name docs ! -name web -printf '%f\n' | sort)
    # real dirs first, so stow links into them instead of folding them into the repo
    for d in .local/share/zsh/site-functions .local/bin .local/lib .config/systemd/user; do
        [ -d "$TARGET/$d" ] || run mkdir -p "$TARGET/$d"
    done
    ts=$(date +%Y%m%d-%H%M%S)
    for pkg in "${pkgs[@]}"; do
        case "$NO_FOLD" in *" $pkg "*) fold=(--no-folding) ;; *) fold=() ;; esac
        out=$(stow -n -v -d "$REPO" -t "$TARGET" "${fold[@]}" "$pkg" 2>&1 | grep -v 'WARNING: in simulation mode' || true)
        if [ -z "$out" ]; then n=$((n + 1)); continue; fi
        # conflicts: real files where a link should go -> move them aside as <file>.pre-nox-<ts>
        mapfile -t conflicts < <(printf '%s\n' "$out" | sed -n \
            -e 's/.*over existing target \(.*\) since neither a link nor a directory.*/\1/p' \
            -e 's/.*existing target is neither a link nor a directory: \(.*\)/\1/p' \
            -e 's/.*existing target is not owned by stow: \(.*\)/\1/p')
        for c in "${conflicts[@]}"; do
            [ -n "$c" ] || continue
            todo "$pkg: $c is a real file, backing it up"
            run mv "$TARGET/$c" "$TARGET/$c.pre-nox-$ts"
        done
        todo "$pkg: $(printf '%s\n' "$out" | grep -c 'LINK:' || true) link(s) to create"
        run stow -d "$REPO" -t "$TARGET" "${fold[@]}" "$pkg" || bad "stow $pkg failed: $(printf '%s' "$out" | tail -2)"
    done
    [ "$n" = "${#pkgs[@]}" ] && ok "all ${#pkgs[@]} packages linked" || ok "$n of ${#pkgs[@]} packages were already linked"
}

s_migrate() {
    step migrate "migrations/*.sh, once each (nox update --migrate)"
    local p
    p=$(nox update --check --no-pull 2>/dev/null | sed -n 's/^nox update: pending migrations: //p' | xargs -n1 basename 2>/dev/null | tr '\n' ' ')
    if [ -z "$p" ] || [ "$p" = "none " ]; then ok "no pending migrations (VERSION $(cat "$REPO/VERSION" 2>/dev/null || echo ?))"; return; fi
    if [ "$FRESH" = 1 ]; then todo "fresh install: record $p as done (nothing to migrate)"; run nox update --mark-done
    else todo "pending: $p"; run nox update --migrate || bad "a migration failed"; fi
}

s_detect() {
    step detect "machine values -> gitignored local files (nox detect)"
    local out
    if out=$(nox detect --check 2>&1); then ok "${out##*$'\n'}"; return; fi
    printf '%s\n' "$out" | sed 's/^/         /'
    if [ "$YES" = 1 ] || [ ! -t 0 ]; then run nox detect --yes; else run nox detect; fi || bad "nox detect failed"
}

s_theme() {
    step theme "render tokens into app configs (nox theme apply)"
    local out
    if out=$(nox theme status 2>&1); then ok "${out##*$'\n'}"; return; fi
    printf '%s\n' "$out" | sed 's/^/         /' | head -12
    run nox theme apply || bad "nox theme apply failed"
}

s_units() {
    step units "systemd user units"
    local u
    command -v systemctl >/dev/null || { skip "no systemctl"; return; }
    for u in "${UNITS[@]}"; do
        if [ "$(systemctl --user is-enabled "$u" 2>/dev/null)" = enabled ]; then ok "$u enabled"
        else todo "$u not enabled"; run systemctl --user daemon-reload; run systemctl --user enable --now "$u" || bad "enable $u failed"; fi
    done
}

# ------------------------------------------------------------------ extras
# each: report state; when not done, run it if selected explicitly or the user says yes
want() {   # want STEP "question"
    explicit "$1" && return 0
    [ "$DRY" = 1 ] && { skip "dry run: would ask: $2"; return 1; }
    ask "$2"
}
need_group() {   # need_group NAME : install the optional.txt packages of group NAME
    local line miss=()
    while read -r line; do
        # shellcheck disable=SC2086
        satisfied $line || miss+=("${line%% *}")
    done < <(awk -v g="## $1:" 'index($0,g)==1{on=1;next} /^## /{on=0} on' "$REPO/packages/optional.txt" |
             sed -e 's/#.*//' -e 's/[[:space:]]*|[[:space:]]*/ /g' -e 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v -e '^$' -e '^manual:')
    [ ${#miss[@]} -eq 0 ] && return 0
    todo "packages for $1: ${miss[*]}"
    install_pkgs "${miss[@]}"
}

x_greeter() {
    step greeter "nox login screen on greetd (sudo)"
    if [ -d /etc/nox-greeter ] && grep -q nox-greeter /etc/greetd/config.toml 2>/dev/null; then ok "installed and on (nox greeter status)"; return; fi
    [ -d /etc/nox-greeter ] && todo "installed, not the login screen yet" || todo "not installed"
    want greeter "install the nox greeter and make it the login screen (sudo)?" || return 0
    need_group greeter
    [ -d /etc/nox-greeter ] || run nox greeter install || { bad "greeter install failed"; return; }
    run nox greeter on || bad "greeter on failed"
}

x_battery() {
    step battery "charge cap (default 80% needs nothing; another cap needs sudo once)"
    local bat
    bat=$(nox battery status 2>/dev/null | head -1) || true
    if [ -z "$bat" ]; then skip "no battery with a charge threshold"; return; fi
    ok "$bat"
    if [ -e /etc/udev/rules.d/61-nox-battery.rules ]; then ok "custom cap rule installed"; return; fi
    want battery "set a cap other than 80% (sudo)?" || return 0
    local n; read -rp "  cap in % (60-99): " n
    run sudo sh "$REPO/_battery/root.sh" install "$n" || bad "battery cap failed"
}

x_etc() {
    step etc "/etc snapshots in _etc (sudo; review each diff)"
    local f rel gpu diffs=()
    gpu=$(nox detect --get gpu 2>/dev/null || true)
    while IFS= read -r f; do
        rel=${f#"$REPO/_etc/"}
        case "$rel" in README.md) continue ;; esac
        case "$rel" in modprobe.d/nvidia* | modprobe.d/blacklist-nouveau.conf | mkinitcpio*)
            [ "$gpu" = nvidia ] || { skip "$rel (NVIDIA only; this GPU: ${gpu:-unknown})"; continue; } ;;
        esac
        if cmp -s "$f" "/etc/$rel"; then ok "/etc/$rel matches"; else todo "/etc/$rel differs"; diffs+=("$rel"); fi
    done < <(find "$REPO/_etc" -type f | sort)
    [ ${#diffs[@]} -eq 0 ] && return
    want etc "review the ${#diffs[@]} differing file(s) one by one?" || return 0
    for rel in "${diffs[@]}"; do
        diff -u "/etc/$rel" "$REPO/_etc/$rel" 2>/dev/null | head -40 || true
        case "$rel" in default/grub | mkinitcpio*) printf '  %s!%s %s is machine-specific (boot); then regenerate grub.cfg / initramfs yourself\n' "$R" "$N" "$rel" ;; esac
        ask "install _etc/$rel -> /etc/$rel?" && { run sudo install -Dm644 "$REPO/_etc/$rel" "/etc/$rel" || bad "install /etc/$rel failed"; }
    done
}

x_voice() {
    step voice "local dictation: whisper.cpp + model (nox voice setup)"
    local d="${XDG_DATA_HOME:-$HOME/.local/share}/nox/whisper"
    if [ -x "$d/bin/whisper-server" ] && compgen -G "$d/ggml-*.bin" >/dev/null; then ok "whisper.cpp $(cat "$d/bin/VERSION" 2>/dev/null) + model in $d"; return; fi
    todo "whisper.cpp or model missing ($d)"
    want voice "build whisper.cpp (Vulkan) and download the model (~550 MB)?" || return 0
    need_group voice
    run nox voice setup || bad "nox voice setup failed"
}

x_phone() {
    step phone "phone link: kdeconnect-rs + Remote Input patch (nox phone build)"
    if [ -x "$HOME/.local/bin/kdeconnect-service" ]; then ok "kdeconnect-service installed ($(nox phone build --status 2>/dev/null || echo 'build unknown'))"; return; fi
    todo "kdeconnect-service not installed"
    want phone "clone, patch and build kdeconnect-rs (cargo, a few minutes)?" || return 0
    need_group phone
    run nox phone build || bad "nox phone build failed"
}

x_hook() {
    step hook "Claude Code status hook for Mission Control (nox agents hook)"
    command -v claude >/dev/null || [ -d "$HOME/.claude" ] || { skip "Claude Code not installed"; return; }
    if nox agents hook status >/dev/null 2>&1; then ok "agent-hook installed in ~/.claude/settings.json"; return; fi
    todo "agent-hook not in ~/.claude/settings.json"
    want hook "add the read-only agent-hook to ~/.claude/settings.json (backup kept)?" || return 0
    run nox agents hook install || bad "hook install failed"
}

x_notes() {
    step notes "Notes app (Electron, prebuilt web/ is committed)"
    if command -v electron43 >/dev/null; then ok "electron43 present; web/ prebuilt (rebuild: cd _notes && npm ci && npm run build)"
    else todo "electron43 missing (it is in packages/pacman.txt: run the packages step)"; fi
}

# ------------------------------------------------------------------ main
printf '%snox install%s  %s%s\n' "$B" "$N" "$REPO" "$([ "$DRY" = 1 ] && echo "  (dry run: nothing is changed)")"
for s in "${CORE[@]}"; do selected "$s" && "s_$s"; done
for s in "${EXTRAS[@]}"; do selected "$s" && "x_$s"; done
echo
if [ "$FAILED" -gt 0 ]; then printf '%s%d step(s) failed%s; fix and re-run (it is idempotent). nox doctor shows the state.\n' "$R" "$FAILED" "$N"; exit 1; fi
if [ "$DRY" = 1 ]; then echo "dry run done."; else printf '%sdone.%s  Check with: nox doctor   (log out and in once after a first install)\n' "$G" "$N"; fi

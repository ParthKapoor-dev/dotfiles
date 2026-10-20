#!/usr/bin/env bash
# 002 (2026-10-20): clean up after the legacy-file removal.
# - the wireplumber stow package is gone (it held only a disabled .off rule): drop the now
#   dangling ~/.config/wireplumber link (only when it is a broken symlink, never a real dir)
# - voice.enabled became modules.voice: a false in the git-ignored shell.local.json moves over
set -euo pipefail
l="${XDG_CONFIG_HOME:-$HOME/.config}/wireplumber"
if [ -L "$l" ] && [ ! -e "$l" ]; then rm -f "$l"; echo "removed dangling $l"; fi
sl="${NOX_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/nox}/shell.local.json"
if [ -f "$sl" ] && [ "$(jq -r '.voice.enabled // empty' "$sl")" = false ]; then
    jq '.modules.voice = false | del(.voice.enabled)' "$sl" >"$sl.nox-tmp" && mv -f "$sl.nox-tmp" "$sl"
    echo "shell.local.json: voice.enabled false -> modules.voice false"
fi

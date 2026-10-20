#!/usr/bin/env bash
# setup.sh: old name, kept so muscle memory still works. The installer is install.sh
# (`./install.sh --help`; `./install.sh --only stow` = what this script used to do).
exec "$(dirname "$(readlink -f "$0")")/install.sh" "$@"

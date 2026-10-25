# `nox` CLI reference

`nox` is the one entry point for the whole desktop: `~/.local/bin/nox` dispatches to the modules in
`~/.local/lib/nox/` (resolved next to the real path of the script, so a git worktree's `nox` runs
that worktree's modules; `NOX_LIB` overrides). `nox help <command>` prints a module's own help.

Back to the [README](../README.md).

## Shell and panels

| Command | What it does |
|---|---|
| `nox shell start` | start exactly one instance of `qs -c nox`, wait until it answers IPC and owns `org.freedesktop.Notifications` |
| `nox shell stop` | stop every instance, including the crash relaunches Quickshell 0.3.2 spawns on exit |
| `nox shell restart` | stop, then start. Use this rather than `qs kill` |
| `nox shell status` / `log [-f]` | instances, IPC answer, notification-server owner / the running instance's log |
| `nox ipc <target> <function> [args]` | raw `qs -c nox ipc call ...` (`qs -c nox ipc show` lists targets) |
| `nox toggle <panel>` | `launcher`, `cc` (Control Center), `nc` (notifications), `dnd`, `overview`, `session`, `dock`, `cheatsheet`, `clipboard`, `widgets`, `agents` |
| `nox widgets [status\|on\|off\|toggle\|left\|right\|auto\|reset]` | the desktop clock / activity column (runtime pick in `~/.local/state/nox/widgets.json`; `reset` = back to `shell.json desktopWidgets`) |
| `nox status` | Hyprland + shell + current look + hypridle at a glance |

## Theme

| Command | What it does |
|---|---|
| `nox theme` / `nox theme switch` | list looks (`*` = current) |
| `nox theme switch <look>` (or `nox theme <look>`) | switch look (`telemetry`, `sequoia`, `minimal`, or base Ember); apps reload |
| `nox theme render` | render every template in `targets.json` into `~/.local/state/nox/out/` (never touches app configs) |
| `nox theme diff` | what `apply` would change in the live app configs |
| `nox theme apply` | render, then run the apply hooks (backup in `~/.local/state/nox/backup/<ts>/`) |
| `nox theme status` | render + diff without writing anything (exit 1 = something pending) |
| `nox theme check` | validate tokens and templates |
| `nox theme revert [ts]` | restore the most recent (or a given) backup |
| `nox theme targets` / `get <path>` | list targets / print one merged token value |

## Hyprland

| Command | What it does |
|---|---|
| `nox hypr status` | what is running and what the next login will load |
| `nox hypr check` | `Hyprland --verify-config` on the Lua entry (no side effects) |
| `nox hypr on [--live]` | verify, then link `hyprland.lua -> nox.lua` (`--live` = `hyprctl reload full-reset`, experimental) |
| `nox hypr off` | refuses: there is no `hyprland.conf` to fall back to any more |
| `nox layout next\|prev\|set <name>\|get` | tiling layout: `dwindle`, `master`, `scrolling`, `monocle` |
| `nox workspaces save [name] [-w 1,2] [-n]` | snapshot open windows (apps, workspace, geometry); alias `nox ws` |
| `nox workspaces restore [name]` / `pick` / `list` / `show [name]` / `rm <name>` | relaunch and place a saved session (JSON in `~/.local/state/nox/sessions/`) |
| `nox dpms on\|off\|toggle [monitor]` | screen power (used by hypridle and binds) |

## Capture

| Command | What it does |
|---|---|
| `nox shot region\|screen\|window\|all` | capture to the clipboard and the screenshot card (Save, Annotate, Copy, Pin, Send to phone, Upload, Discard) |
| `nox shot copy` / `ocr` | region to clipboard only / region text via tesseract |
| `nox shot annotate\|save\|pin <file>` | satty / copy to `~/Pictures/Screenshots` / pin on screen |
| `nox record [--fullscreen] [--sound]` | toggle a wf-recorder recording (region by default) to `~/Videos` (`$NOX_RECORD_DIR`) |
| `nox ask [toggle\|close\|status\|lens]` | Circle to Ask; `lens` = Google Lens on a region |

## Desktop

| Command | What it does |
|---|---|
| `nox wallpaper pick\|random\|list [--all]` | choose from `$NOX_WALLPAPER_DIR` (default `~/Pictures/Wallpapers/prepped`, else `~/Pictures`) |
| `nox wallpaper set <path>` | set it (the shell draws it) |
| `nox wallpaper slideshow start\|stop\|next\|prev\|status\|list\|clear\|add\|remove` | cycle a list every `wallpaper.slideshowMinutes` (15) |
| `nox wallpaper lock [<path>\|follow]` | lock-screen image: fixed, or follow the desktop |
| `nox wallpaper prep [--out DIR] [--force] <image\|dir>...` | turn images into nox wallpapers (screen shape, subject on a third, dark top strip, grain; optional Real-ESRGAN upscale) |
| `nox shelf add <file\|url\|->...` | park files (by reference), links or stdin text on the drop shelf |
| `nox shelf list\|open\|close\|toggle\|remove <id>\|undo\|clear\|status` | manage the shelf (items expire after `shelf.expireHours`, 24) |
| `nox notes [toggle\|show\|hide\|new\|open <file>\|start\|quit\|qt <cmd>]` | the floating Markdown notepad (`~/Notes/*.md`) |
| `nox files terminal\|copypath\|ocr\|annotate\|webp\|png\|jpg\|half\|strip <file>...` | the Dolphin right-click "nox" menu actions |
| `nox activity [refresh\|show] [--weeks N] [--source github\|local]` | commit grid for the desktop widget (GitHub via `gh`, or local repos) |

## Apps

The launcher's App Manager (`+`) is a front end for these. Sources: `repo` (pacman), `aur` (yay),
`flatpak`, `appimage` (`~/Applications`, plus `launcher.provider.packages.appimageDirs`).

| Command | What it does |
|---|---|
| `nox apps list` | installed apps as JSON: explicit and app-owning pacman packages, Flatpak apps, AppImages; AppImages in `~/Downloads` not installed yet |
| `nox apps search <text>` | installable matches as JSON: repos (expac), AUR (aurweb RPC), Flathub (API, local appstream when offline) |
| `nox apps updates [--cached\|--fresh]` | pending updates (checkupdates, `yay -Qua`, flatpak), cached 30 min |
| `nox apps info\|open\|page <source> <id>` | details / start it / its web page |
| `nox apps install\|remove\|update <source> <id>` | change one app; repo updates run a full `-Syu` (Arch has no partial upgrades); AppImages move to `~/Applications` with a launcher entry, and go to the trash on remove |
| `nox apps upgrade` / `nox apps clean` | update everything (`yay -Syu`, `flatpak update`) / remove orphans, trim caches, unused runtimes |
| `nox apps term <command> ...` | run one of the above in a floating terminal that stays open at the end |

In the launcher: Enter opens (or installs), Shift+Enter opens the web page, Ctrl+Enter updates,
Shift+Delete uninstalls.

## AI and agents

| Command | What it does |
|---|---|
| `nox agents [toggle\|open\|close\|grid]` | the Mission Control panel / full-screen grid |
| `nox agents list [--json]` / `usage` | sessions from the status hook / tokens, context %, cost, today's totals |
| `nox agents focus <id>` / `turn <id>` / `diff <id>` | jump to the session's window / last turn's changes / open them |
| `nox agents send <id> [--] TEXT` | reply to a session (Orca terminal or tmux) |
| `nox agents start [--mode background\|ghostty\|orca] <dir> TASK...` | start a Claude Code session (background = detached tmux on `-L nox-agents`) |
| `nox agents attach [id]` / `repos` / `prune` / `answer <id> <choice>` | attach to a background agent / repos under `agents.roots` / drop dead sessions / answer seam |
| `nox agents hook [status\|install\|uninstall]` | the read-only status hook in `~/.claude/settings.json` (backup kept) |
| `nox voice [toggle\|start\|stop\|cancel\|status]` | dictation control (normally: hold Super+Shift+Space) |
| `nox voice tidy on\|off\|toggle` / `last` | filler-word removal / copy the last transcript again |
| `nox voice setup [--model q5_0\|q8_0] [--cpu]` | build whisper.cpp (Vulkan) and download the model |
| `nox voice server start\|stop\|status` / `bench` / `doctor` | the local whisper-server / timing / check every piece |

## Phone and hardware

| Command | What it does |
|---|---|
| `nox phone status` / `pair` / `on\|off` / `logs [-f]` | kdeconnect-rs daemon, devices, pairing, journal |
| `nox phone send [file...]` / `clip` / `ring` / `commands` | send files (fuzzel picker without args), clipboard, find-my-phone, Run-command buttons |
| `nox phone build [--status\|--no-install]` | clone kdeconnect-rs at the pinned commit, apply the Remote Input patch, build, install |
| `nox battery [status\|protect\|full\|toggle\|reapply]` | charge limit via UPower (80% by default, no sudo per toggle) |
| `nox battery limit <60-100>` | another cap (root once, via `_battery/root.sh`) |
| `nox greeter sync\|test\|nested\|install\|on\|off\|check\|status` | the greetd login screen (`install`, `on`, `off`, `check` use sudo) |

## Setup and maintenance

| Command | What it does |
|---|---|
| `nox detect [--yes\|--print\|--check\|--get KEY]` | machine values (monitors, battery, mic, thermal zone, backlight, GPU) into git-ignored local files |
| `nox doctor [--summary]` | read-only health check; every red line comes with its fix command |
| `nox update` | `git pull --ff-only`, new migrations, re-stow, theme apply, doctor summary |
| `nox update --check` / `--no-pull` / `--migrate` / `--mark-done` | preview / skip the pull / only migrations / record migrations as done |
| `nox help [command]` | usage, or one module's help |

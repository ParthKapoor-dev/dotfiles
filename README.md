<div align="center">

# nox

**A personal, portable Linux desktop: Hyprland, a hand-built Quickshell shell, and one CLI.**<br>
Clone it onto a fresh Arch install, run one script, get the same desktop.

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?logo=archlinux&logoColor=white)](https://archlinux.org)
[![Hyprland 0.56](https://img.shields.io/badge/Hyprland-0.56_(Lua)-58E1FF?logo=hyprland&logoColor=black)](https://hyprland.org)
[![Quickshell 0.3.2](https://img.shields.io/badge/Quickshell-0.3.2-FF6A1A)](https://quickshell.org)

[Website](https://nox.parthkapoor.me) &nbsp;·&nbsp;
[Live demo](https://nox.parthkapoor.me/desktop/) &nbsp;·&nbsp;
[Install](#install) &nbsp;·&nbsp;
[CLI reference](docs/CLI.md) &nbsp;·&nbsp;
[Keybindings](#keybindings)

<img src="docs/telemetry-desktop.jpg" width="49%" alt="Telemetry look: bar and the plan-usage popover over a topographic wallpaper">
<img src="docs/mission-control.jpg" width="49%" alt="Mission Control for coding agents (Ctrl+Super+M), empty state">

</div>

---

nox is my whole Arch Linux desktop in one repo: **Hyprland 0.56** with a Lua config, my own
**Quickshell 0.3.2** shell (`qs -c nox`: bar, dock, launcher, Control Center, notifications,
overview, Mission Control for coding agents, Circle to Ask, voice typing, a drop shelf, Notes...),
one CLI (`nox`), a token-based theme engine that themes every app from one file, and the apps,
binds and settings I use.

It is a personal system, not a distro: my looks, keys and apps are meant to be in here. It is
public so that I (or you) can clone it onto any machine and get the same desktop. Everything about
a specific machine (monitors, battery, mic, GPU) is detected and kept in git-ignored local files.

## Contents

- [Features](#features)
- [Requirements](#requirements)
- [Install](#install)
- [After installing](#after-installing)
- [Updating](#updating)
- [The `nox` command](#the-nox-command)
- [Keybindings](#keybindings)
- [Configuration](#configuration)
- [Theme system](#theme-system)
- [Repository layout](#repository-layout)
- [Uninstall and rollback](#uninstall-and-rollback)
- [Troubleshooting](#troubleshooting)
- [Website](#website)
- [Credits](#credits)

## Features

**AI and agents**
- **Mission Control** (Ctrl+Super+M): every Claude Code session on the machine in a bar panel or
  a full-screen grid, with state, context %, tokens, cost, the last turn's diff and PR link. Jump
  to a session's window, reply to it, or start a new agent in the background (tmux), in Ghostty or
  in Orca. Fed by a read-only Claude Code hook (`nox agents hook install`).
- **Circle to Ask** (Super+Shift+A): freeze the screen, circle anything, Claude answers beside it.
  Chips for OCR, explain more, translate, table to CSV, Google Lens, or sending the region to an
  agent (Claude, Codex, Gemini, opencode or a command of your own).
- **Voice typing** (hold Super+Shift+Space): local speech-to-text with whisper.cpp on the GPU
  (Vulkan), typed into the focused field. Audio never leaves the machine; transcripts are never
  logged.
- **Plan usage** in the bar: Claude 5-hour / weekly and Codex rate limits.

**Desktop**
- Bar with app menus, workspaces, layout indicator, agent status, tray, stats, phone, network,
  Bluetooth, battery, recording and Do Not Disturb indicators.
- Spotlight-style launcher (Super+Space or a Super tap): apps, calculator `=`, windows `@`,
  clipboard `:`, wallpapers `#`, commands `/`, command palette `>`, emoji, files, pinned snippets.
- Control Center (connectivity, sound, display, media, performance, notifications), notification
  center with DND, OSDs, dock, overview (Super+Tab or a 4-finger swipe), Alt+Tab switcher, session
  menu, polkit agent, keyboard cheatsheet (Super+/), desktop clock and commit-activity widgets.
- Runtime layout cycling (dwindle, master, scrolling, monocle) and saved window sessions
  (`nox workspaces save` / `restore`).
- Screenshots with an action card (Save, Annotate, Copy, Pin, Send to phone, Upload), OCR, region
  and full-screen recording.
- **Notes** (Ctrl+Super+S): a floating Markdown notepad (Milkdown Crepe on Electron) over plain
  `.md` files in `~/Notes`.
- Its own login screen: a greetd greeter (a small Hyprland + Quickshell) themed from the current
  look.

**Phone**
- KDE Connect compatible phone link through **kdeconnect-rs**, patched for Remote Input (the
  phone as mouse and keyboard on Wayland): send files and the clipboard, ring the phone,
  Run-command buttons, phone battery in the bar. Works with the official KDE Connect phone app.

**Look and theme**
- One `tokens.json` holds every colour, radius, font, size and timing. Base look **Ember** (black
  and one orange accent), with the presets **Telemetry**, **Sequoia** and **Minimal**.
- One command themes GTK 3/4, KDE/Dolphin, Ghostty, kitty, fuzzel, btop, hyprlock and satty; the
  shell and Hyprland read the tokens live.
- `nox wallpaper prep` turns any image into a wallpaper in the house style; slideshows included.

**Files**
- **Drop shelf** (Super+Shift+D): drag files, text, images or links to the screen edge, drag them
  out into any app later.
- Dolphin right-click "nox" menu: terminal here, copy path, OCR, annotate, convert to
  webp/png/jpg, half size, strip metadata.

**System**
- Idempotent installer with a dry run, per-step selection, and backups of anything it replaces.
- `nox detect` for machine values, `nox doctor` for a health check with a fix for every red line,
  `nox update` with one-shot migrations.
- Battery charge cap (80% by default) through UPower, no sudo per toggle.
- Reference copies of the `/etc` files the desktop depends on, installed only after you review
  each diff.

## Requirements

- **Arch Linux** (`pacman`), run as your normal user with `sudo` available.
- An AUR helper (`paru` or `yay`) for `packages/aur.txt`; without one the installer lists those
  packages for you to install by hand.
- **Hyprland 0.56** (Lua config) and **Quickshell 0.3.2** (the official `extra/quickshell`); both
  are in `packages/pacman.txt`.
- Optional: a Vulkan-capable GPU for voice typing (a CPU build works too), the Claude Code CLI
  for Mission Control and Circle to Ask, Rust/cargo for the phone daemon, greetd for the login
  screen. `packages/optional.txt` lists what each extra needs.

## Install

On a fresh Arch install, as your user:

```sh
git clone https://github.com/ParthKapoor-dev/dotfiles ~/code/dev/dotfiles/base0
cd ~/code/dev/dotfiles/base0
./install.sh --dry-run     # what is done, what would run; changes nothing
./install.sh               # do it; then log out and back in (or reboot)
nox doctor                 # red/green report, a fix command for every red line
```

The clone can live anywhere: `nox` finds the repo through its own stow link.

`install.sh` is idempotent: every step checks first, prints `[ok]` when there is nothing to do,
and can be re-run at any time. `setup.sh` is an alias kept for old habits.

| Flag | |
|---|---|
| `-n`, `--dry-run` | report what is done and what would run; change nothing |
| `--only stow,theme` | just these steps (an extra named here runs without a prompt; `--only extras` = every extra) |
| `--skip packages` | everything but these |
| `-y`, `--yes` | answer yes to every prompt (sudo steps still ask for the password) |
| `--list` | list the steps |
| `-h`, `--help` | usage |

<details>
<summary><b>What each step does</b></summary>

| Step | What it does |
|---|---|
| `preflight` | Arch, not root, sudo present |
| `packages` | installs what is missing from `packages/pacman.txt` (pacman) and `packages/aur.txt` (paru or yay, if present) |
| `stow` | links every package dir into `~` with GNU stow (`bin` and `systemd-desktop` without folding); a real file in the way is moved to `<file>.pre-nox-<time>` first |
| `migrate` | runs new `migrations/*.sh` once (on a fresh install they are only recorded as done) |
| `detect` | `nox detect`: this machine's monitors, battery, mic, thermal sensor, backlight, GPU into git-ignored local files |
| `theme` | `nox theme apply`: renders the tokens into every app's config |
| `units` | enables the user unit `nox-greeter-sync.path` |

Extras, asked one by one (or picked with `--only`):

| Extra | What it does |
|---|---|
| `greeter` | installs the nox login screen and makes it greetd's greeter (sudo) |
| `battery` | a charge cap other than 80% (sudo, once) |
| `etc` | compares `_etc/` with `/etc`, shows every diff and asks before installing each file (sudo; NVIDIA files only on an NVIDIA GPU) |
| `voice` | builds whisper.cpp (Vulkan) and downloads the model (~550 MB) |
| `phone` | clones, patches and builds kdeconnect-rs (cargo, a few minutes) |
| `hook` | adds the read-only Mission Control hook to `~/.claude/settings.json` (backup kept) |
| `notes` | checks the Notes app (Electron; the built web app is committed) |

</details>

Things no script can do for you: fonts that are not packaged (Apple Color Emoji, Doto) and apps
installed outside pacman (Zed, Hubstaff, Claude Code) are listed as `manual:` lines in
`packages/optional.txt`.

## After installing

```sh
nox detect                              # re-detect monitors, battery, mic... (asks before replacing a saved monitor mode)
nox doctor                              # health check; every problem comes with its fix command
nox theme switch telemetry              # pick a look (plain `nox theme` lists them)
nox greeter install && nox greeter on   # optional: the nox login screen (sudo)
```

Optional extras, each also an installer step:

- **Login screen**: `nox greeter install && nox greeter on` (sudo). The greeter is a separate
  Hyprland + Quickshell running as greetd's `greeter` user, themed from the current look, with the
  monitors from `nox detect`. `nox greeter test` previews it inside your session; `nox greeter off`
  goes back to tuigreet.
- **Voice typing**: `nox voice setup` builds whisper.cpp with Vulkan and downloads the model;
  everything stays local.
- **Phone link**: `nox phone build` clones [cosmic-utils/kdeconnect](https://github.com/cosmic-utils/kdeconnect)
  at a pinned commit, applies `_patches/kdeconnect-rs-remote-input.patch` (remote mouse and
  keyboard), builds and installs `kdeconnect-service`; then `nox phone pair`.
- **Mission Control**: `nox agents hook install` adds the read-only status hook to
  `~/.claude/settings.json`.
- **Battery cap**: 80% works without root (`nox battery`); for another cap, `nox battery limit <N>`.
- **`/etc` files**: `./install.sh --only etc` shows each diff against `_etc/` before installing it.
- **Wallpaper upscaling**: realesrgan-ncnn-vulkan in `~/.local/share/nox/realesrgan`, used by
  `nox wallpaper prep`.

## Updating

```sh
nox update          # git pull --ff-only, new migrations, re-stow, theme apply, doctor summary
nox update --check  # incoming commits + pending migrations; changes nothing
```

`nox update` never merges or rebases: a diverged repo stops at the pull. `--no-pull` skips the
pull (after pulling by hand), `--migrate` runs only the migrations.

`VERSION` (date-based, e.g. `2026.10.20`) is bumped with changes that need a migration.
Migrations are small, idempotent scripts in `migrations/NNN-*.sh`, run once per machine (state in
`~/.local/state/nox/migrations`). On a fresh install they are only recorded as done: they exist to
move an older setup forward.

## The `nox` command

One entry point for everything; `nox help <command>` shows each module's own help. Every
subcommand is in the **[CLI reference](docs/CLI.md)**.

| Command | |
|---|---|
| `nox theme [render\|check\|diff\|status\|apply\|switch <look>\|revert]` | design tokens to app themes |
| `nox shell start\|stop\|restart\|status\|log` | the Quickshell shell (`qs -c nox`) |
| `nox ipc <target> <fn>`, `nox toggle <panel>`, `nox widgets ...` | talk to the running shell |
| `nox hypr status\|check\|on` | the Hyprland Lua config (`check` = `--verify-config`) |
| `nox layout`, `nox workspaces` (`ws`), `nox dpms` | tiling layouts, saved sessions, screen power |
| `nox shot`, `nox record`, `nox ask` | screenshots + OCR + pins, screen recording, Circle to Ask |
| `nox shelf add\|list\|open\|undo\|clear` | the drop shelf |
| `nox wallpaper`, `nox activity`, `nox notes`, `nox files` | wallpaper + slideshow + prep, commit grid, Notes, Dolphin menu |
| `nox voice`, `nox phone`, `nox agents`, `nox battery` | dictation, phone link, coding agents, charge limit |
| `nox greeter` | the login screen (sync, test, install, on/off) |
| `nox detect`, `nox doctor`, `nox update`, `nox status` | machine values, health check, update, quick status |

## Keybindings

Super+/ shows every bind on screen, and the command palette (Ctrl+Super+Space) lists actions with
their keys. The binds live in `hypr/.config/hypr/nox/binds/*.lua` and `nox/shells/nox.lua`.

| Keys | Action |
|---|---|
| Super (tap), Super+Space | launcher |
| Ctrl+Super+Space | command palette |
| Super+Return, Super+T | terminal |
| Super+E / Super+W / Super+C / Super+X | files / browser / code editor / Neovim |
| Super+Q, Alt+F4 | close window |
| Super+Tab | overview |
| Alt+Tab | window switcher |
| Super+N / Super+M | notification center / Control Center |
| Super+V / Super+. | clipboard history / emoji |
| Super+Shift+S, Print | screenshot a region |
| Super+Shift+A | Circle to Ask |
| hold Super+Shift+Space | voice typing |
| Super+Shift+D | drop shelf |
| Ctrl+Super+S | Notes |
| Ctrl+Super+M | Mission Control |
| Super+L | lock |
| Super+/ | keyboard shortcuts |

<details>
<summary><b>All keybindings</b></summary>

**Apps**

| Keys | Action |
|---|---|
| Super+Return, Super+T, Ctrl+Alt+T | terminal (first available: `$TERMINAL`, kitty, foot, ...) |
| Super+E | file manager (Dolphin first) |
| Super+W | web browser |
| Super+C | code editor |
| Super+X | Neovim in its own Ghostty window |
| Ctrl+Super+Shift+Alt+W | office app |
| Ctrl+Super+V | volume mixer |
| Super+I | system settings |
| Ctrl+Shift+Escape | system monitor |
| Ctrl+Super+/ | edit `~/.config/nox/shell.json` |
| Ctrl+Super+Alt+/ | edit the custom keybinds |

**Shell**

| Keys | Action |
|---|---|
| Super (tap), Super+Space | launcher (fuzzel when the shell is down) |
| Ctrl+Super+Space | command palette |
| Super+V | clipboard history |
| Super+. | emoji picker |
| Super+Tab | overview |
| Alt+Tab / Alt+Shift+Tab | window switcher (release Alt to switch) |
| Super+N | notification center |
| Super+Alt+D | Do Not Disturb |
| Super+M, Super+Alt+N | Control Center |
| Super+J | toggle the dock |
| Super+/ | keyboard shortcuts |
| Ctrl+Alt+Delete | session menu |
| Ctrl+Super+S | Notes |
| Ctrl+Super+M | Mission Control |
| Super+Shift+A | Circle to Ask |
| hold Super+Shift+Space | voice typing |
| Super+Shift+D | drop shelf |
| Ctrl+Super+T / Ctrl+Super+Alt+T | pick a wallpaper / random wallpaper |
| Ctrl+Super+R | restart the shell |

**Windows**

| Keys | Action |
|---|---|
| Super+Arrows, Super+[ / ] | focus |
| Super+Shift+Arrows | move window |
| Super+Q, Alt+F4 | close |
| Super+Shift+Alt+Q | force kill (click to pick) |
| Super+\ / Super+Shift+\ | next / previous layout |
| Super+Alt+\ | toggle split direction (dwindle) |
| Super+Alt+Space | toggle floating |
| Super+D / Super+F / Super+Alt+F | maximize / fullscreen / fake fullscreen |
| Super+P | pin |
| Ctrl+Super+\ | resize to 640x480 |
| Super+drag / Super+right-drag | move / resize |
| Super+Shift+1..0 | move window to desktop 1..10 |
| Super+Alt+S | send to the scratchpad |
| Super+Alt+PgUp / PgDn | move window to the previous / next desktop |

**Desktops**

| Keys | Action |
|---|---|
| Super+1..0 | go to desktop 1..10 |
| Ctrl+Super+Left / Right | previous / next desktop on this monitor |
| Super+PgUp / PgDn, Super+scroll | previous / next desktop |
| Ctrl+Super+Up / Down | jump 5 desktops back / forward |
| Super+S | toggle the scratchpad |
| Super+Alt+Left / Right | move the desktop to the previous / next monitor |
| Super+Alt+Up | swap desktops with the next monitor |

**Capture**

| Keys | Action |
|---|---|
| Super+Shift+S, Print | screenshot a region |
| Shift+Print / Alt+Print / Ctrl+Print | monitor / window / all monitors |
| Super+Shift+X, Super+Shift+T | OCR a region to the clipboard |
| Super+Shift+R, Super+Alt+R | record a region (toggle) |
| Ctrl+Alt+R / Super+Shift+Alt+R | record the screen / with audio (toggle) |
| Super+Shift+C | colour picker |

**System and media**

| Keys | Action |
|---|---|
| Super+L | lock |
| Super+Shift+L | suspend |
| Ctrl+Shift+Alt+Super+Delete | shut down |
| Super+Shift+M / Super+Alt+M | mute / mic mute |
| Super+Shift+P / N / B | play-pause / next / previous track |
| Super+- / Super+= | zoom out / in |
| Super+Alt+F1 | VM mode: every other shortcut is off until you press it again |
| volume, brightness and media keys | as labelled |

</details>

## Configuration

The tracked files hold my settings with generic fallbacks. Anything about *this machine* lives in
git-ignored files next to them:

| File | Written by | Holds |
|---|---|---|
| `~/.config/nox/shell.json` | you (tracked) | the shell: bar layout, dock pins, launcher providers, modules, voice, ask, agents, shelf... (Ctrl+Super+/ opens it) |
| `~/.config/nox/shell.local.json` | `nox detect` + you | deep-merged over `shell.json`. `nox detect` writes `voice.source`, `stats.thermalZone`, `brightness.device` and `battery.device`; add any other key, e.g. `phone.device` (see `shell.local.example.json`) |
| `~/.config/nox/machine.json` | `nox detect` | facts: monitors, battery, mic, thermal sensor, backlight, GPU |
| `~/.config/nox/local.json` | `nox theme switch` + you | the current look and token overrides (`local.example.json`) |
| `~/.config/hypr/nox/machine.lua` | `nox detect` | Hyprland `settings.monitors` |
| `~/.config/hypr/nox/local.lua` | you | any Hyprland setting or token, plus an `after(ctx)` hook; wins over `machine.lua` (`local.example.lua`) |

`nox detect` keeps a value you changed by hand, keeps saved monitors that are unplugged, and asks
before replacing a saved monitor mode with a different live one.

<details>
<summary><b>Turning shell modules on and off</b></summary>

Every shell module has a switch in `shell.json`:

```json
"modules": { "voice": false, "agents": true }
```

The defaults for all of them (all on) are in `quickshell/.config/quickshell/nox/core/Config.qml`:
`bar`, `dock`, `controlCenter`, `launcher`, `osd`, `notifications`, `wallpaper`, `corners`,
`overview`, `session`, `polkit`, `clipboard`, `cheatsheet`, `switcher`, `notes`, `agents`, `shot`,
`ask`, `voice`, `shelf`. The same file has the default of every other `shell.json` key, so it is
the reference for what can be set. (The desktop widgets have their own runtime toggle,
`nox widgets`.)

</details>

<details>
<summary><b>Hyprland overrides (<code>local.lua</code>)</b></summary>

Copy `hypr/.config/hypr/nox/local.example.lua` to `~/.config/hypr/nox/local.lua`. All three
fields are optional, and the file is hot-reloaded like every other module:

```lua
return {
    settings = { bind_groups = { "shell", "windows", "workspaces", "system", "apps", "custom" } },
    tokens   = { size = { gapsOut = 6 } },
    after    = function(ctx) hl.config({ misc = { vrr = 0 } }) end,
}
```

`settings` is merged over `nox/settings.lua` before any module runs (shell, bind groups, disabled
modules, monitors), `tokens` over the theme tokens, and `after` runs last, so direct `hl.*` calls
there override everything. Your own binds belong in `nox/binds/custom.lua`.

</details>

## Theme system

`~/.config/nox/tokens.json` is the single source of every colour, radius, font, size and timing.
Looks in `presets/*.json` are overlays; `local.json` (git-ignored) holds the chosen look and any
local overrides. `nox theme` deep-merges tokens, preset and `local.json`, renders every template
listed in `targets.json` into `~/.local/state/nox/out/`, and `apply` hooks those outputs into
GTK 3/4, KDE/Dolphin, Ghostty, kitty, fuzzel, btop, hyprlock and satty (with a backup;
`nox theme revert` undoes it). The shell and Hyprland read the merged `tokens.json` / `tokens.lua`
live. Adding an app takes one template and one `targets.json` entry.

```sh
nox theme                  # list looks (* = current)
nox theme switch telemetry # switch look; apps reload
nox theme diff             # what apply would change
```

`hypr/nox/base.lua` is generated from `tokens.json` alone (target `hypr-base`) and committed: it
is Hyprland's fallback when the state dir has no tokens yet.

## Repository layout

Every top-level dir without a `_` is a **stow package** whose tree mirrors `~`, except
`packages/`, `migrations/`, `docs/` and `web/`. The `_` dirs are sources and references and are
never stowed.

```
hypr/          Hyprland Lua config: nox.lua + nox/*.lua (modules, binds, shells/nox.lua, look from tokens)
quickshell/    the shell: ~/.config/quickshell/nox (core/, services/, modules/, components/)
nox/           the nox CLI (~/.local/bin/nox + ~/.local/lib/nox/*), theme engine, ~/.config/nox:
               tokens.json, presets/, templates/, targets.json, shell.json
ghostty/ kitty/ fuzzel/ btop/ gtk/ zed/ nvim/ tmux/ zsh/ starship/   app configs
dolphin/ fontconfig/ environment/ xdg-desktop-portal/ systemd-desktop/ bin/
packages/      pacman.txt, aur.txt, optional.txt (what the desktop needs, with comments)
migrations/    NNN-*.sh, run once each by nox update / install.sh
docs/          screenshots, CLI reference
web/           the website (nox.parthkapoor.me)
_greeter/      the login screen (greetd greeter: its own small Hyprland + Quickshell), nox greeter
_notes/        Notes app source (Milkdown); the built web/ is committed in nox/.local/lib/nox/notes-app
_battery/      root half of nox battery limit
_etc/          /etc snapshots this desktop depends on (README inside)
_patches/      local patches against upstream (kdeconnect-rs Remote Input)
install.sh  setup.sh  VERSION
```

## Uninstall and rollback

There is no one-shot uninstaller; each piece is undone on its own:

| To undo | Run |
|---|---|
| the theme applied to app configs | `nox theme revert` (restores the latest backup in `~/.local/state/nox/backup/`) |
| the login screen | `nox greeter off` (back to tuigreet; the previous config is kept as `config.toml.before-nox`) |
| the Mission Control hook | `nox agents hook uninstall` (a backup of `settings.json` is kept) |
| a custom battery cap | `sudo sh _battery/root.sh uninstall` (back to UPower's 80%) |
| the symlinks in `~` | `stow -D -d <repo> -t ~ <package>` for each package |
| a file the installer replaced | it is still there as `<file>.pre-nox-<time>` |

`nox hypr off` refuses on purpose: there is no `hyprland.conf` left to fall back to, and without
`hyprland.lua` Hyprland would write and load its own default config.

## Troubleshooting

Start with `nox doctor`: it is read-only, and every red line comes with the command that fixes it.

<details>
<summary><b>Common problems</b></summary>

- **Bar, launcher or notifications gone**: `nox shell restart` (Ctrl+Super+R). Avoid `qs kill`:
  Quickshell 0.3.2 crashes on exit and relaunches itself, and only `nox shell stop` hunts those
  relaunches down. While the shell is down, the launcher, clipboard and emoji binds fall back to
  fuzzel and the session menu to wlogout.
- **Hyprland config errors**: `nox hypr check` runs `Hyprland --verify-config` without touching
  the session; `nox hypr status` shows what the next login loads.
- **Wrong monitors, battery or mic**: `nox detect --print` shows what it finds, `nox detect`
  writes it. Hand-written monitor setups go in `~/.config/hypr/nox/local.lua`.
- **An app looks unthemed**: `nox theme status` shows what is pending, `nox theme apply` applies
  it, `nox theme revert` undoes an apply that went wrong.
- **Stow conflicts**: the installer moves a real file in the way to `<file>.pre-nox-<time>`;
  compare and merge by hand, then re-run `./install.sh --only stow`.
- **No shortcut does anything**: you may be in VM mode; press Super+Alt+F1.
- **Voice typing silent**: `nox voice doctor` checks whisper.cpp, the model, the server and the
  mic (without recording); `voice.source` in `shell.local.json` picks the microphone.
- **Phone not connecting**: `nox phone status`, `nox phone logs -f`, `nox phone pair`. Do not run
  the official KDE Connect daemon next to kdeconnect-rs.
- **Mission Control empty**: `nox agents hook status`, then `nox agents hook install`.

</details>

## Website

The project site, [nox.parthkapoor.me](https://nox.parthkapoor.me), with an interactive desktop
demo at [/desktop/](https://nox.parthkapoor.me/desktop/), lives in `web/` (not stowed). To run it
locally:

```sh
cd web && pnpm install && pnpm dev
```

See `web/` for details.

## Credits

nox is built on other people's work:

- [Hyprland](https://hyprland.org) and its tools (hyprlock, hypridle, hyprpicker, xdg-desktop-portal-hyprland)
- [Quickshell](https://quickshell.org), the QML toolkit the shell and the greeter are built with
- [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) ("illogical-impulse"), where this
  setup started before it was rewritten as nox
- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) for local voice typing
- [cosmic-utils/kdeconnect](https://github.com/cosmic-utils/kdeconnect) (kdeconnect-rs) and
  [KDE Connect](https://kdeconnect.kde.org) for the phone link
- [Milkdown](https://milkdown.dev) and [Electron](https://www.electronjs.org) for Notes
- [Claude Code](https://claude.com/claude-code) behind Circle to Ask and Mission Control
- [greetd](https://sr.ht/~kennylevinsen/greetd/), [GNU Stow](https://www.gnu.org/software/stow/),
  [fuzzel](https://codeberg.org/dnkl/fuzzel), [cliphist](https://github.com/sentriz/cliphist),
  grim, slurp, [Hyprshot](https://github.com/Gustash/Hyprshot), [Satty](https://github.com/gabm/Satty),
  [wf-recorder](https://github.com/ammen99/wf-recorder), [Tesseract](https://github.com/tesseract-ocr/tesseract),
  [Real-ESRGAN ncnn Vulkan](https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan)
- [Arch Linux](https://archlinux.org) and the AUR

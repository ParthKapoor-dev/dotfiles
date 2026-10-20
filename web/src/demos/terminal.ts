// A typed terminal with real output from the repo's CLI (paths shortened to ~).
import { h, esc, reduced, sleep, visibility } from "../util";

const HELP = `usage: nox <command> [args]
  theme  [render|check|diff|status|apply|switch <look>|revert [ts]|targets|get <path>|<look>]
  shell  start|stop|restart|status|log [-f]     (qs -c nox)
  ipc    <target> <function> [args]             (qs -c nox ipc call ...)
  toggle launcher|cc|nc|dnd|overview|session|dock|cheatsheet|clipboard|widgets|agents
  widgets [status|on|off|toggle|left|right|auto|reset]   (desktop clock column; shell.json desktopWidgets)
  layout next|prev|set <name>|get
  shot   region|screen|window|all|copy|ocr|annotate|save|pin <file>
  ask    [start|toggle|close|status|lens]       (Circle to Ask: circle anything, Claude answers; Super+Shift+A)
  shelf  [add <file|url|->...|list|open|close|toggle|remove <id>|undo|clear|status]   (drop shelf; Super+Shift+D)
  record [--fullscreen] [--sound]
  wallpaper pick|random|list [--all]|set <path>|prep <image|dir>...
            slideshow start|stop|next|prev|status|list|clear|add <path>...|remove <path>...
  dpms   on|off|toggle [monitor]
  battery [status|protect|full|toggle|limit <60-100>|reapply]   (charge limit, 80% by default)
  phone  status|send [file...]|clip|ring|commands|pair|on|off|logs|build   (KDE Connect phone link)
  hypr   status|check|on [--live]|off
  greeter sync|test|nested|install|on|off|status  (login screen on greetd)
  workspaces save [name]|restore [name]|pick|list|show [name]|rm <name>  (session: apps + window layout; alias ws)
  activity [refresh|show] [--source github|local]   (commit grid for the desktop widget)
  notes  [toggle|show|hide|new|open <file>|start|quit|qt <cmd>]   (floating markdown notepad, ~/Notes)
  files  terminal|copypath|ocr|webp|png|jpg|half|strip <file>...   (Dolphin right-click nox menu)
  agents [toggle|grid|list|usage|focus|turn|diff|send|repos|start|answer <id>|prune|hook]   (coding agents panel, Ctrl+Super+M)
  voice  [toggle|start|stop|cancel|status|tidy on|off|last|setup|server|doctor|bench]   (dictation: hold Super+Shift+Space)
  detect [--yes|--print|--check|--get KEY]     (machine values -> git-ignored local files)
  update [--check|--no-pull|--migrate]          (git pull --ff-only, migrations, re-stow, theme apply, doctor)
  doctor [--summary]                            (check everything: packages, links, theme, extras; fix commands)
  status                                        (hypr + shell + theme + idle at a glance)
  help [command]`;

const DOCTOR = `
**packages
  ✓ pacman.txt: all 65 installed
  ✓ aur.txt: all 7 installed

**stow
  ✓ all 19 packages linked
  ✓ no broken links into the repo or ~/.local/state/nox

**machine
  ✓ machine values current (~/.config/nox/machine.json, detected 2026-10-20T13:57:35)

**theme
  ✓ ok: outputs rendered and hooked in (20 targets)
  ✓ every rendered output validates (nox theme check)
  ✓ fonts of the look installed (Doto, Geist, Geist Mono, Material Symbols Sharp)

**hyprland
  ✓ config verifies (Hyprland --verify-config)
  ✓ hyprland.lua -> nox.lua
  ✓ running compositor reports no config errors

**shell
  ✓ qs -c nox running, IPC answers

**units
  ✓ nox-greeter-sync.path enabled

**updates
  ✓ no pending migrations (2026.10.20)

**extras
  ✓ greeter installed and the login screen
  ! /etc/nox-greeter is older than the repo (hyprland.lua)
      optional: nox greeter install   (sudo)
  ✓ voice: whisper.cpp v1.9.5 + model
  ✓ phone: kdeconnect-service (pin 36a44d9f8cfb patch 2039293d8a1d)
  ✓ Claude agent hook installed
  ✓ wallpaper upscaler (realesrgan)

all good (1 optional item(s) open)`;

const DRY = `nox install  ~/code/dev/dotfiles/base0  (dry run: nothing is changed)

**== preflight Arch, not root, repo
  [ok]   running as you
  [ok]   Arch Linux (pacman)
  [ok]   repo: ~/code/dev/dotfiles/base0 (d60405f, VERSION 2026.10.20)
  [ok]   sudo available

**== packages packages/pacman.txt + aur.txt
  [ok]   pacman.txt: all 65 installed
  [ok]   aur.txt: all 7 installed

**== stow link every package dir into ~ (GNU stow)
  [ok]   all 19 packages linked

**== migrate migrations/*.sh, once each (nox update --migrate)
  [ok]   no pending migrations (VERSION 2026.10.20)

**== detect machine values -> gitignored local files (nox detect)
  [ok]   machine values current (~/.config/nox/machine.json)

**== theme render tokens into app configs (nox theme apply)
  [ok]   ok: outputs rendered and hooked in (20 targets)

**== units systemd user units
  [ok]   nox-greeter-sync.path enabled

**== greeter nox login screen on greetd (sudo)
  [ok]   installed and on (nox greeter status)

**== battery charge cap (default 80% needs nothing; another cap needs sudo once)
  [ok]   protection: on, charging stops at 80%
  [skip] dry run: would ask: set a cap other than 80% (sudo)?

**== voice local dictation: whisper.cpp + model (nox voice setup)
  [ok]   whisper.cpp v1.9.5 vulkan=ON + model in ~/.local/share/nox/whisper

**== phone phone link: kdeconnect-rs + Remote Input patch (nox phone build)
  [ok]   kdeconnect-service installed (pin 36a44d9f8cfb patch 2039293d8a1d)

**== hook Claude Code status hook for Mission Control (nox agents hook)
  [ok]   agent-hook installed in ~/.claude/settings.json

**== notes Notes app (Electron, prebuilt web/ is committed)
  [ok]   electron43 present; web/ prebuilt

dry run done.`;

const ASK = `nox ask - Circle to Ask: freeze the screen, circle anything, Claude answers beside it
(the shell's modules/ask; Super+Shift+A).

  nox ask               freeze the focused monitor and wait for a circle (same as Super+Shift+A)
  nox ask toggle|close  toggle / close the overlay
  nox ask status        open?, model, timings (freeze_ms, first_token_ms); never the content
  nox ask lens          Google Lens on a region

In the overlay: drag a loop around anything (a straight drag = rectangle, a click = that window),
Esc / right click closes. Chips: Copy text (OCR), Explain more, Send to agent (interactive claude
in a new terminal), Translate, Table -> CSV, Lens.
Answers come from the Claude Code CLI in headless mode (claude -p, --safe-mode, no tools, no
settings, no session files; NOX_ASK=1 in its env). Screenshots live in $XDG_RUNTIME_DIR/nox-ask
and are deleted on close.
Send to agent: "claude" (default) | "codex" | "gemini" | "opencode", or your own command.`;

const TABS: [string, string, string][] = [
  ["nox doctor", "nox doctor", DOCTOR],
  ["nox help", "nox help", HELP],
  ["install.sh --dry-run", "./install.sh --dry-run", DRY],
  ["nox help ask", "nox help ask", ASK],
];

function color(line: string) {
  if (line.startsWith("**")) return `<span class="b">${esc(line.slice(2))}</span>`;
  let s = esc(line);
  s = s.replace(/^(\s*)✓/, '$1<span class="g">✓</span>').replace(/^(\s*)!/, '$1<span class="y">!</span>').replace(/^(\s*)✗/, '$1<span class="r">✗</span>');
  s = s.replace(/\[ok\]/, '<span class="g">[ok]</span>').replace(/\[skip\]/, '<span class="y">[skip]</span>');
  s = s.replace(/(optional:|fix:)/, '<span class="d">$1</span>');
  if (/^all good|^dry run done/.test(line)) s = `<span class="g">${s}</span>`;
  return s;
}

export function initTerminal(root: HTMLElement) {
  root.innerHTML = "";
  const tabs = h("div.tm-tabs", { role: "tablist" });
  const out = h("pre.tm-out", { "aria-live": "off", tabindex: "0" });
  root.append(tabs, out);
  let run = 0;
  const buttons = TABS.map(([label], i) => {
    const b = h("button", { type: "button", role: "tab", text: label, onclick: () => play(i) });
    tabs.append(b);
    return b;
  });
  async function play(i: number) {
    const my = ++run;
    buttons.forEach((b, j) => { b.classList.toggle("on", i === j); b.setAttribute("aria-selected", String(i === j)); });
    const [, cmd, text] = TABS[i];
    const prompt = '<span class="pr">~/code/dev/dotfiles/base0 ❯</span> ';
    out.innerHTML = prompt;
    out.scrollTop = 0;
    let typed = "";
    for (const ch of cmd) {
      if (my !== run) return;
      typed += ch;
      out.innerHTML = prompt + esc(typed) + '<span class="cur"></span>';
      if (!reduced) await sleep(34 + Math.random() * 40);
    }
    if (!reduced) await sleep(260);
    const lines = text.split("\n");
    let html = prompt + esc(cmd) + "\n";
    for (let k = 0; k < lines.length; k++) {
      if (my !== run) return;
      html += color(lines[k]) + "\n";
      if (!reduced && (k % 2 === 0 || k === lines.length - 1)) {
        out.innerHTML = html + '<span class="cur"></span>';
        out.scrollTop = out.scrollHeight;
        await sleep(i === 1 ? 14 : 26);
      }
    }
    out.innerHTML = html + "\n" + prompt + '<span class="cur"></span>';
    out.scrollTop = out.scrollHeight;
  }
  buttons[0].classList.add("on");
  out.innerHTML = '<span class="pr">~/code/dev/dotfiles/base0 ❯</span> <span class="cur"></span>';
  let played = false;
  visibility(root, (on) => { if (on && !played) { played = true; setTimeout(() => play(0), 500); } });
}

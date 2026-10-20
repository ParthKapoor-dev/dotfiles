// The launcher, in miniature: apps, maths, and the real prefixes (> palette/agent, @ windows, / commands, : clipboard, # wallpapers, . emoji).
import { h, esc, toast } from "../util";

type Row = { ic: string; bg: string; label: string; sub: string; big?: boolean; act?: string };

const APPS: Row[] = [
  { ic: "G", bg: "#e8e4e0", label: "Ghostty", sub: "terminal" },
  { ic: "Z", bg: "#7aa7ff", label: "Zed", sub: "editor" },
  { ic: "D", bg: "#5aa9ff", label: "Dolphin", sub: "files" },
  { ic: "C", bg: "#3ddc97", label: "Google Chrome", sub: "browser" },
  { ic: "N", bg: "#ff3b1f", label: "Notes", sub: "Ctrl Super S" },
  { ic: "B", bg: "#ffc24b", label: "btop", sub: "system monitor" },
  { ic: "K", bg: "#c792ea", label: "kitty", sub: "terminal" },
  { ic: "V", bg: "#9cbeff", label: "Volume mixer", sub: "pavucontrol" },
];
const PALETTE: Row[] = [
  { ic: "⌘", bg: "#ff3b1f", label: "Agent mission control", sub: "Ctrl Super M" },
  { ic: "⌘", bg: "#ff3b1f", label: "Circle to Ask", sub: "Super Shift A" },
  { ic: "⌘", bg: "#ff3b1f", label: "Drop shelf: open / close", sub: "Super Shift D" },
  { ic: "⌘", bg: "#ff3b1f", label: "Voice typing (hold to talk)", sub: "Super Shift Space" },
  { ic: "⌘", bg: "#ff3b1f", label: "Screenshot region", sub: "Super Shift S" },
  { ic: "⌘", bg: "#ff3b1f", label: "Toggle Do Not Disturb", sub: "Super Alt D" },
  { ic: "⌘", bg: "#ff3b1f", label: "Next layout", sub: "Super \\" },
];
const WINDOWS: Row[] = [
  { ic: "G", bg: "#e8e4e0", label: "nvim · keybinds.lua", sub: "desktop 2" },
  { ic: "C", bg: "#3ddc97", label: "Hyprland wiki · Lua config", sub: "desktop 3" },
  { ic: "Z", bg: "#7aa7ff", label: "base0 · shell.qml", sub: "desktop 1" },
];
const COMMANDS: Row[] = [
  { ic: "/", bg: "#e8e4e0", label: "Lock Screen", sub: "command" },
  { ic: "/", bg: "#e8e4e0", label: "Suspend", sub: "command" },
  { ic: "/", bg: "#e8e4e0", label: "Restart shell", sub: "command" },
  { ic: "/", bg: "#e8e4e0", label: "Random wallpaper", sub: "command" },
];
const CLIP: Row[] = [
  { ic: ":", bg: "#3fd5e0", label: "nox theme switch telemetry", sub: "text · 2 min" },
  { ic: ":", bg: "#3fd5e0", label: "https://github.com/ParthKapoor-dev/dotfiles", sub: "link · 9 min" },
  { ic: ":", bg: "#3fd5e0", label: "screenshot 1440×900", sub: "image · 1 h" },
];
const WALLS: Row[] = [
  { ic: "#", bg: "#8d201b", label: "signal-grid.png", sub: "wallpaper" },
  { ic: "#", bg: "#6f3128", label: "ember-glow.png", sub: "wallpaper" },
  { ic: "#", bg: "#2a0c08", label: "red-fog.png", sub: "wallpaper" },
];
const EMOJI: Row[] = [
  { ic: "🔥", bg: "transparent", label: "fire", sub: "emoji" },
  { ic: "🩸", bg: "transparent", label: "drop of blood", sub: "emoji" },
  { ic: "🗡", bg: "transparent", label: "dagger", sub: "emoji" },
];

function calc(q: string): string | null {
  const s = q.replace(/^=/, "").replace(/×/g, "*").replace(/÷/g, "/").replace(/\^/g, "**").trim();
  if (!s || !/^[\d\s+\-*/().%]+$/.test(s)) return null;
  if (!q.startsWith("=") && !/[-+*/%(]/.test(s.replace(/^-/, ""))) return null;
  try {
    // eslint-disable-next-line no-new-func
    const v = Function(`"use strict";return (${s})`)();
    if (typeof v !== "number" || !isFinite(v)) return null;
    return String(Math.round(v * 1e10) / 1e10);
  } catch { return null; }
}

export function initLauncher(root: HTMLElement) {
  const box = h("div.ln-box");
  const input = h("input", { type: "text", placeholder: "Search apps, or try =, >, @, /, :, #", "aria-label": "Launcher search", autocomplete: "off", spellcheck: "false" }) as HTMLInputElement;
  const inrow = h("div.ln-in", { html: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5L14 14"/></svg>' });
  inrow.append(input);
  const list = h("ul.ln-list", { role: "listbox", "aria-label": "Results" });
  const tips = h("div.ln-tips");
  for (const [t, v] of [["2^10 + 24", "2^10 + 24"], ["> palette", ">"], ["> agent", "> fix the flaky test in api"], ["@ windows", "@"], ["/ commands", "/"], [": clipboard", ":"], ["# wallpapers", "#"]]) {
    tips.append(h("button", { type: "button", text: t, onclick: () => { input.value = v; update(); input.focus(); } }));
  }
  box.append(inrow, list, tips);
  root.append(box);
  let sel = 0;
  let rows: Row[] = [];

  function update() {
    const q = input.value;
    const t = q.trim().toLowerCase();
    const c = calc(q.trim());
    if (c != null) rows = [{ ic: "=", bg: "#ffc24b", label: c, sub: "Enter copies", big: true, act: "copy" }];
    else if (t.startsWith(">")) {
      const r = t.slice(1).trim();
      const m = r.match(/^(.*?)\s+in\s+([\w.-]+)$/);
      rows = m
        ? [{ ic: "C", bg: "#d97757", label: `Start Claude: “${m[1]}”`, sub: `in ${m[2]}`, act: "agent" }, ...PALETTE.filter((p) => p.label.toLowerCase().includes(m[1])).slice(0, 2)]
        : PALETTE.filter((p) => !r || p.label.toLowerCase().includes(r) || p.sub.toLowerCase().includes(r));
    } else if (t.startsWith("@")) rows = WINDOWS.filter((w) => w.label.toLowerCase().includes(t.slice(1).trim()));
    else if (t.startsWith("/")) rows = COMMANDS.filter((w) => w.label.toLowerCase().includes(t.slice(1).trim()));
    else if (t.startsWith(":")) rows = CLIP;
    else if (t.startsWith("#")) rows = WALLS;
    else if (t.startsWith(".")) rows = EMOJI;
    else if (!t) rows = APPS.slice(0, 6);
    else {
      rows = APPS.filter((a) => a.label.toLowerCase().includes(t) || a.sub.includes(t));
      if (!rows.length) rows = [{ ic: "↗", bg: "#e8e4e0", label: `Search the web for “${q.trim()}”`, sub: "web" }];
    }
    sel = 0;
    draw();
  }
  function draw() {
    list.innerHTML = rows.slice(0, 7).map((r, i) =>
      `<li role="option" aria-selected="${i === sel}" class="${i === sel ? "sel" : ""}" data-i="${i}"><span class="ic" style="background:${r.bg}">${esc(r.ic)}</span><span class="${r.big ? "calc" : ""}">${esc(r.label)}</span><span class="sub">${esc(r.sub)}</span></li>`).join("");
  }
  function run(r?: Row) {
    if (!r) return;
    if (r.act === "copy") { navigator.clipboard?.writeText(r.label).catch(() => {}); toast(`${r.label} copied`); }
    else if (r.act === "agent") toast("nox agents start: Claude runs it, and it appears in Mission Control");
    else toast(`${r.label}${r.sub.match(/[A-Z][a-z]+ /) ? " · " + r.sub : ""}`);
  }
  input.addEventListener("input", update);
  input.addEventListener("keydown", (e) => {
    if (e.key === "ArrowDown") { sel = Math.min(rows.length - 1, sel + 1); draw(); e.preventDefault(); }
    else if (e.key === "ArrowUp") { sel = Math.max(0, sel - 1); draw(); e.preventDefault(); }
    else if (e.key === "Enter") run(rows[sel]);
    else if (e.key === "Escape") { input.value = ""; update(); }
  });
  list.addEventListener("click", (e) => {
    const li = (e.target as HTMLElement).closest("li");
    if (li) run(rows[+li.dataset.i!]);
  });
  update();
}

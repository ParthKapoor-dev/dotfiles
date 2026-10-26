// Keybind cheatsheet, from hypr/.config/hypr/nox/binds/*.lua and shells/nox.lua.
import { h, esc } from "../util";

type G = { id: string; name: string; rows: [string, string][] };
const GROUPS: G[] = [
  { id: "ai", name: "AI & agents", rows: [
    ["SUPER + SHIFT + A", "Circle to Ask: ask Claude about a screen region"],
    ["SUPER + SHIFT + Space", "Voice typing (hold to talk)"],
    ["CTRL + SUPER + M", "Agent mission control"],
    ["CTRL + SUPER + Space", "Command palette (launcher, >)"],
    ["SUPER + Semicolon", "Hint mode: click anything by its label"],
  ] },
  { id: "shell", name: "Shell", rows: [
    ["SUPER", "Open launcher (tap)"],
    ["SUPER + Space", "Open launcher"],
    ["SUPER + Tab", "Mission Control: all windows"],
    ["SUPER + SHIFT + Tab", "Mission Control: desktops"],
    ["ALT + Tab", "Switch to the previous window (hold Alt, Tab to step)"],
    ["SUPER + SHIFT + D", "Drop shelf: open / close"],
    ["SUPER + V", "Open clipboard history"],
    ["SUPER + Period", "Emoji picker"],
    ["SUPER + N", "Open notification center"],
    ["SUPER + ALT + D", "Toggle Do Not Disturb"],
    ["SUPER + ALT + N", "Open Control Center"],
    ["SUPER + M", "Control Center (Now Playing)"],
    ["SUPER + J", "Toggle dock"],
    ["CTRL + SUPER + S", "Show or hide Notes"],
    ["SUPER + Slash", "Show keyboard shortcuts"],
    ["CTRL + SUPER + T", "Choose wallpaper"],
    ["CTRL + SUPER + R", "Restart shell"],
  ] },
  { id: "capture", name: "Capture", rows: [
    ["SUPER + SHIFT + S", "Screenshot region"],
    ["Print", "Screenshot region"],
    ["SHIFT + Print", "Screenshot monitor"],
    ["ALT + Print", "Screenshot window"],
    ["SUPER + SHIFT + X", "OCR region to clipboard"],
    ["SUPER + SHIFT + R", "Record region (toggle)"],
    ["CTRL + ALT + R", "Record screen (toggle)"],
    ["SUPER + SHIFT + C", "Color picker"],
    ["SUPER + A", "Draw on screen (pointer, pen, shapes)"],
  ] },
  { id: "windows", name: "Windows", rows: [
    ["SUPER + Q", "Close window"],
    ["SUPER + ←↑→↓", "Focus window in direction"],
    ["SUPER + SHIFT + ←↑→↓", "Move window in direction"],
    ["SUPER + Backslash", "Next layout"],
    ["SUPER + ALT + Space", "Toggle floating window"],
    ["SUPER + D", "Maximize window"],
    ["SUPER + F", "Fullscreen window"],
    ["SUPER + P", "Pin window"],
    ["SUPER + ALT + S", "Send window to scratchpad"],
    ["SUPER + Minus", "Zoom out"],
    ["SUPER + Equal", "Zoom in"],
  ] },
  { id: "desktops", name: "Desktops", rows: [
    ["SUPER + 1…0", "Go to desktop 1–10"],
    ["SUPER + SHIFT + 1…0", "Move window to desktop 1–10"],
    ["CTRL + SUPER + ←→", "Previous / next desktop on monitor"],
    ["SUPER + S", "Toggle scratchpad"],
    ["SUPER + ALT + ←→", "Move desktop to other monitor"],
  ] },
  { id: "apps", name: "Apps", rows: [
    ["SUPER + Return", "Open terminal"],
    ["SUPER + E", "Open file browser"],
    ["SUPER + W", "Open web browser"],
    ["SUPER + C", "Open code editor"],
    ["SUPER + X", "Open Neovim"],
    ["SUPER + I", "Open system settings"],
    ["CTRL + SUPER + V", "Open volume mixer"],
  ] },
  { id: "session", name: "Session & media", rows: [
    ["SUPER + L", "Lock screen"],
    ["SUPER + SHIFT + L", "Suspend"],
    ["CTRL + ALT + Delete", "Open session menu"],
    ["SUPER + SHIFT + P", "Play / pause"],
    ["SUPER + SHIFT + N", "Next track"],
    ["SUPER + SHIFT + M", "Toggle mute"],
    ["SUPER + ALT + M", "Toggle microphone mute"],
  ] },
];

const pretty = (k: string) => ({ SUPER: "Super", SHIFT: "Shift", CTRL: "Ctrl", ALT: "Alt", Backslash: "\\", Slash: "/", Period: ".", Semicolon: ";", Minus: "−", Equal: "=", Return: "↵", Delete: "Del" } as Record<string, string>)[k] ?? k;

export function initKeys(root: HTMLElement) {
  root.innerHTML = "";
  const search = h("label.keys-search", { html: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5L14 14"/></svg>' });
  const input = h("input", { type: "search", placeholder: "Search binds: “draw”, “hint”, “mission”, “super shift”…", "aria-label": "Search keybinds" }) as HTMLInputElement;
  search.append(input);
  const filters = h("div.keys-filters", { role: "group", "aria-label": "Filter groups" });
  let group = "all";
  for (const [id, name] of [["all", "All"], ...GROUPS.map((g) => [g.id, g.name])]) {
    filters.append(h("button" + (id === "all" ? ".on" : ""), { type: "button", "data-g": id, text: name, onclick: () => { group = id; filters.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b.dataset.g === id)); draw(); } }));
  }
  const grid = h("div.keys-grid");
  root.append(h("div.keys-tools", null, search, filters), grid);

  const mark = (s: string, q: string) => {
    const e = esc(s);
    if (!q) return e;
    const i = s.toLowerCase().indexOf(q);
    return i < 0 ? e : esc(s.slice(0, i)) + "<mark>" + esc(s.slice(i, i + q.length)) + "</mark>" + esc(s.slice(i + q.length));
  };
  function draw() {
    const q = input.value.trim().toLowerCase();
    let html = "";
    let n = 0;
    for (const g of GROUPS) {
      if (group !== "all" && g.id !== group) continue;
      const rows = g.rows.filter(([k, d]) => !q || d.toLowerCase().includes(q) || k.toLowerCase().replace(/\s/g, "").includes(q.replace(/\s/g, "+").replace(/\++/g, "+")) || k.toLowerCase().includes(q));
      if (!rows.length) continue;
      n += rows.length;
      html += `<section class="kgroup"><h4>${esc(g.name)}<span>${rows.length}</span></h4>${rows.map(([k, d]) => `<div class="krow"><span>${mark(d, q)}</span><span class="ks">${k.split(" + ").map((x) => `<kbd>${esc(pretty(x))}</kbd>`).join("")}</span></div>`).join("")}</section>`;
    }
    grid.innerHTML = html || `<p class="keys-empty">No bind matches “${esc(q)}”.</p>`;
    grid.setAttribute("aria-label", `${n} binds`);
  }
  input.addEventListener("input", draw);
  draw();
}

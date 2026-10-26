// Small touches: hot corners (150 ms dwell), dock folders that fan out in an arc, and a Downloads stack
// that fans the newest files up out of the dock (click opens, drag one out to an app, Esc closes).
import { h, esc, sleep, toast, visibility } from "../util";

/* ---------------------------------------------------------------- hot corners */
const HC: Record<string, [string, string]> = {
  tl: ["Mission Control", "mission"], tr: ["Control Center", "cc"], bl: ["Show desktop", "desktop"], br: ["Lock screen", "lock"],
};
export function initCorners(root: HTMLElement) {
  root.innerHTML = "";
  const scr = h("div.hc-scr", { html: '<div class="hc-bar"></div><div class="hc-w a"></div><div class="hc-w b"></div><div class="hc-w c"></div><div class="hc-lock"><b>18:40</b></div><div class="hc-cc"><i></i><i></i><i></i><i></i></div>' });
  const label = h("div.hc-label", { text: "rest the pointer in a corner" });
  for (const c of Object.keys(HC)) scr.append(h(`span.hc-z.${c}`, { "data-c": c, "aria-label": HC[c][0] }));
  root.append(scr, label);
  let t = 0;
  let mode = "";
  let back = 0;
  const set = (m: string) => {
    scr.classList.remove("m-mission", "m-cc", "m-desktop", "m-lock");
    mode = m;
    if (m) scr.classList.add(`m-${m}`);
  };
  const fire = (c: string) => {
    const [name, m] = HC[c];
    scr.querySelectorAll(".hc-z").forEach((z) => z.classList.toggle("on", (z as HTMLElement).dataset.c === c));
    label.innerHTML = `<b>${name}</b> · ${c.toUpperCase()} corner`;
    set(mode === m ? "" : m);
    clearTimeout(back);
    back = window.setTimeout(() => { set(""); scr.querySelectorAll(".hc-z").forEach((z) => z.classList.remove("on")); label.textContent = "rest the pointer in a corner"; }, 2600);
  };
  scr.addEventListener("pointerover", (e) => {
    const z = (e.target as HTMLElement).closest<HTMLElement>(".hc-z");
    if (!z) return;
    clearTimeout(t);
    z.classList.add("arm");
    t = window.setTimeout(() => { z.classList.remove("arm"); fire(z.dataset.c!); }, 150);
  });
  scr.addEventListener("pointerout", (e) => {
    const z = (e.target as HTMLElement).closest<HTMLElement>(".hc-z");
    if (z) { clearTimeout(t); z.classList.remove("arm"); }
  });
  scr.addEventListener("click", (e) => { const z = (e.target as HTMLElement).closest<HTMLElement>(".hc-z"); if (z) fire(z.dataset.c!); });
}

/* ---------------------------------------------------------------- dock folder fan */
const FOLDER = [["Zed", "#7aa7ff"], ["Ghostty", "#e8e4e0"], ["btop", "#ffc24b"], ["Dolphin", "#5aa9ff"], ["Notes", "#ff3b1f"]];
export function initFolder(root: HTMLElement) {
  root.innerHTML = "";
  const fan = h("div.fd-fan");
  const n = FOLDER.length;
  FOLDER.forEach(([name, c], i) => {
    // an arc, rising to the right like a stack
    const k = n === 1 ? 0 : i / (n - 1);
    const x = 8 + k * 46, y = -(18 + i * 34), r = -10 + k * 22;
    fan.append(h("button.fd-it", { type: "button", style: { "--x": `${x}px`, "--y": `${y}px`, "--r": `${r}deg`, "--d": `${i * 34}ms` } as any, html: `<i style="background:${c}">${name[0]}</i><span>${name}</span>` }));
  });
  const dock = h("div.fd-dock", { html: '<i class="a"></i><i class="b"></i>' });
  const folder = h("button.fd-folder", { type: "button", "aria-label": "Dev folder", html: FOLDER.slice(0, 4).map(([, c]) => `<i style="background:${c}"></i>`).join("") });
  dock.append(folder, h("i.c"));
  root.append(fan, dock);
  let open = false;
  const toggle = (v = !open) => { open = v; root.classList.toggle("fd-open", open); };
  folder.addEventListener("click", (e) => { e.stopPropagation(); toggle(); });
  fan.addEventListener("click", (e) => { const b = (e.target as HTMLElement).closest(".fd-it"); if (b) { b.classList.add("pick"); setTimeout(() => { b.classList.remove("pick"); toggle(false); }, 300); } });
  document.addEventListener("click", (e) => { if (open && !root.contains(e.target as Node)) toggle(false); });
  let played = false;
  visibility(root, async (v) => {
    if (!v || played) return;
    played = true;
    await sleep(1200);
    toggle(true);
    await sleep(2400);
    toggle(false);
  });
}

/* ---------------------------------------------------------------- Downloads stack */
// dock.pinned: { "stack": "Downloads", "path": "~/Downloads", "count": 12 } — newest at the bottom of the arc
type SFile = { name: string; ext: string; img?: string; ago: string };
const FILES: SFile[] = [
  { name: "nox-wallpaper-5k.jpg", ext: "JPG", ago: "now", img: "radial-gradient(70% 90% at 70% 110%, #ff3b1f, #8d201b 40%, #120404 75%)" },
  { name: "invoice-oct.pdf", ext: "PDF", ago: "4 min" },
  { name: "Screenshot 18-32.png", ext: "PNG", ago: "12 min", img: "linear-gradient(180deg, #1b1b1b 0 18%, #0a0a0a 18% 100%), #0a0a0a" },
  { name: "quickshell-0.3.2.tar.gz", ext: "GZ", ago: "1 h" },
  { name: "moodboard-03.webp", ext: "WEBP", ago: "2 h", img: "radial-gradient(40% 50% at 40% 45%, #e8e4e0, #3a3634 60%, #050505 90%)" },
];
export function initStack(root: HTMLElement) {
  root.innerHTML = "";
  const fan = h("div.st-fan");
  const n = FILES.length + 1;
  const place = (el: HTMLElement, i: number) => {
    // an arc that leans right as it rises, like macOS "Fan"
    const k = i / (n - 1);
    el.style.setProperty("--x", `${(4 + k * k * 44).toFixed(1)}px`);
    el.style.setProperty("--y", `${-(16 + i * 31)}px`);
    el.style.setProperty("--r", `${(-2 + k * 13).toFixed(1)}deg`);
    el.style.setProperty("--d", `${i * 30}ms`);
  };
  FILES.forEach((f, i) => {
    const th = f.img ? `<i class="th img" style="background:${f.img}"></i>` : `<i class="th doc" data-x="${f.ext}"></i>`;
    const b = h("button.st-it", { type: "button", "data-i": String(i), html: `${th}<span><b>${esc(f.name)}</b><small>${f.ago}</small></span>` });
    place(b, i);
    fan.append(b);
  });
  const openF = h("button.st-it.st-open", { type: "button", html: '<i class="th fold"><svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M2 4.5h4l1.5 1.5H14v6.5H2z"/></svg></i><span><b>Open in Files</b></span>' });
  place(openF, n - 1);
  fan.append(openF);
  const dock = h("div.st-dock");
  const apps: [string, string][] = [["Zen", "linear-gradient(160deg, #3a1410, #160606)"], ["Zed", "linear-gradient(160deg, #24405e, #142438)"], ["Slack", "linear-gradient(160deg, #3b2a44, #1a1020)"]];
  for (const [name, bg] of apps) dock.append(h("span.st-app", { "data-app": name, title: name, style: { background: bg }, html: `<em>${name}</em>` }));
  const tile = h("button.st-tile", { type: "button", "aria-label": "Downloads stack", "aria-expanded": "false", html: `<i class="a" style="background:${FILES[0].img}"></i><i class="b"></i><i class="c"></i>` });
  dock.append(tile);
  const label = h("div.st-label", { text: "click the Downloads stack" });
  root.append(fan, dock, label);

  let open = false;
  let touched = false;
  const toggle = (v = !open) => { open = v; root.classList.toggle("st-on", open); tile.setAttribute("aria-expanded", String(open)); if (!open) label.textContent = "click the Downloads stack"; else label.innerHTML = "click opens · <b>drag one to an app</b> · Esc"; };
  tile.addEventListener("click", (e) => { e.stopPropagation(); touched = true; toggle(); });
  openF.addEventListener("click", () => { toast("Opens Files in ~/Downloads"); toggle(false); });
  document.addEventListener("click", (e) => { if (open && !root.contains(e.target as Node)) toggle(false); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && open) toggle(false); });

  // click opens a file, a drag carries it out to an app in the dock
  let drag: { b: HTMLElement; f: SFile; x0: number; y0: number; ghost?: HTMLElement; over?: HTMLElement | null } | null = null;
  fan.addEventListener("pointerdown", (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>(".st-it:not(.st-open)");
    if (!b || !open) return;
    touched = true;
    drag = { b, f: FILES[+b.dataset.i!], x0: e.clientX, y0: e.clientY };
    b.setPointerCapture(e.pointerId);
  });
  fan.addEventListener("pointermove", (e) => {
    if (!drag) return;
    const r = root.getBoundingClientRect();
    if (!drag.ghost) {
      if (Math.hypot(e.clientX - drag.x0, e.clientY - drag.y0) < 6) return;
      drag.ghost = h("div.st-ghost", { html: drag.b.querySelector(".th")!.outerHTML });
      root.append(drag.ghost);
      drag.b.classList.add("lift");
      label.innerHTML = `drop <b>${esc(drag.f.name)}</b> on an app`;
    }
    drag.ghost.style.transform = `translate(${e.clientX - r.left - 17}px, ${e.clientY - r.top - 17}px)`;
    const hit = document.elementFromPoint(e.clientX, e.clientY)?.closest<HTMLElement>(".st-app") || null;
    if (hit !== drag.over) { drag.over?.classList.remove("hot"); hit?.classList.add("hot"); drag.over = hit; }
  });
  const end = (e: PointerEvent) => {
    if (!drag) return;
    const d = drag; drag = null;
    d.b.classList.remove("lift");
    d.over?.classList.remove("hot");
    if (!d.ghost) {
      if (e.type === "pointerup") { d.b.classList.add("pick"); toast(`Opens ${d.f.name} in its default app`); setTimeout(() => { d.b.classList.remove("pick"); toggle(false); }, 280); }
      return;
    }
    d.ghost.remove();
    if (d.over && e.type === "pointerup") { toast(`Dropped ${d.f.name} on ${d.over.dataset.app}`); toggle(false); }
    else label.innerHTML = "click opens · <b>drag one to an app</b> · Esc";
  };
  fan.addEventListener("pointerup", end);
  fan.addEventListener("pointercancel", end);

  let played = false;
  visibility(root, async (v) => {
    if (!v || played) return;
    played = true;
    await sleep(1600);
    if (touched) return;
    toggle(true);
    await sleep(2800);
    if (!touched) toggle(false);
  });
}

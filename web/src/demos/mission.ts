// Mission Control (Super+Tab): every window of every desktop in justified rows; Desktops (Super+Shift+Tab) brings the
// desktop strip down and regroups the same copies. Fling a window up to close it.
import { h, toast } from "../util";

type Win = { id: number; ws: number; app: string; c: string; w: number };
const SEED: Omit<Win, "id">[] = [
  { ws: 1, app: "Ghostty", c: "#e8e4e0", w: 1.3 }, { ws: 1, app: "Zed", c: "#7aa7ff", w: 1.6 },
  { ws: 2, app: "Zen", c: "#ff8a3d", w: 1.6 }, { ws: 2, app: "Slack", c: "#c792ea", w: 1.2 },
  { ws: 3, app: "Dolphin", c: "#5aa9ff", w: 1.2 }, { ws: 3, app: "btop", c: "#ffc24b", w: 1 }, { ws: 1, app: "Notes", c: "#ff3b1f", w: 0.9 },
];

export function initMission(root: HTMLElement) {
  root.innerHTML = "";
  const sw = h("div.mx-sw", { role: "group", "aria-label": "View", html: '<button type="button" class="on" data-v="win">Windows</button><button type="button" data-v="desk">Desktops</button>' });
  const strip = h("div.mx-strip");
  const field = h("div.mx-field");
  root.append(sw, strip, field);
  let wins: Win[] = [];
  let view: "win" | "desk" = "win";
  let focusWs = 1;
  let uid = 0;
  const reset = () => { wins = SEED.map((w) => ({ ...w, id: ++uid })); };
  reset();

  function render() {
    root.classList.toggle("mx-desk", view === "desk");
    strip.innerHTML = [1, 2, 3].map((n) => `<button type="button" class="mx-d${n === focusWs ? " on" : ""}" data-ws="${n}"><span>${wins.filter((w) => w.ws === n).map((w) => `<i style="background:${w.c};flex:${w.w}"></i>`).join("")}</span><small>${n}</small></button>`).join("");
    const show = view === "win" ? wins : wins.filter((w) => w.ws === focusWs);
    field.innerHTML = "";
    if (!show.length) field.append(h("p.mx-empty", { html: view === "win" ? 'All closed. <button type="button" data-x="reset">Bring them back</button>' : "No windows on this desktop" }));
    for (const w of show) {
      field.append(h("div.mx-w", { "data-id": String(w.id), style: { flexGrow: String(w.w), "--c": w.c } as any, html: `<div class="mx-tb"><i></i><span>${w.app}</span></div><div class="mx-body"></div>` }));
    }
  }
  sw.addEventListener("click", (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>("[data-v]");
    if (!b) return;
    view = b.dataset.v as "win" | "desk";
    sw.querySelectorAll("button").forEach((x) => x.classList.toggle("on", x === b));
    render();
  });
  strip.addEventListener("click", (e) => { const b = (e.target as HTMLElement).closest<HTMLElement>("[data-ws]"); if (b) { focusWs = +b.dataset.ws!; render(); } });
  field.addEventListener("click", (e) => { if ((e.target as HTMLElement).closest("[data-x=reset]")) { reset(); render(); } });

  // fling: a quick upward flick closes the window
  field.addEventListener("pointerdown", (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>(".mx-w");
    if (!el) return;
    e.preventDefault();
    el.setPointerCapture(e.pointerId);
    const y0 = e.clientY, x0 = e.clientX;
    let last = { y: e.clientY, t: performance.now() }, vy = 0;
    el.classList.add("drag");
    const move = (ev: PointerEvent) => {
      const now = performance.now();
      vy = (ev.clientY - last.y) / Math.max(1, now - last.t);
      last = { y: ev.clientY, t: now };
      el.style.transform = `translate(${(ev.clientX - x0) * 0.6}px, ${ev.clientY - y0}px) rotate(${(ev.clientX - x0) * 0.03}deg)`;
    };
    const end = (ev: PointerEvent) => {
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerup", end);
      el.removeEventListener("pointercancel", end);
      el.classList.remove("drag");
      const dy = ev.clientY - y0;
      if (vy < -0.6 || dy < -90) {
        el.classList.add("fling");
        el.style.transform = `translate(${(ev.clientX - x0) * 0.6}px, -140%) rotate(-4deg)`;
        const id = +el.dataset.id!;
        setTimeout(() => { wins = wins.filter((w) => w.id !== id); render(); }, 320);
        const w = wins.find((x) => x.id === id);
        if (w && wins.length === SEED.length) toast(`Flung ${w.app} off the top: closed`);
      } else if (Math.abs(dy) < 6 && Math.abs(ev.clientX - x0) < 6) {
        el.style.transform = "";
        const w = wins.find((x) => x.id === +el.dataset.id!);
        if (w) { focusWs = w.ws; toast(`Focus ${w.app} on desktop ${w.ws}`); render(); }
      } else el.style.transform = "";
    };
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", end);
    el.addEventListener("pointercancel", end);
  });
  render();
}

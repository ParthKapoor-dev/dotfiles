// Small touches: hot corners (150 ms dwell), dock folders that fan out in an arc, shake the mouse to find the cursor.
import { h, reduced, sleep, visibility } from "../util";

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

/* ---------------------------------------------------------------- shake to find the cursor */
export function initShake(root: HTMLElement) {
  root.innerHTML = "";
  const ring = h("div.sk-ring");
  const fake = h("div.sk-fake", { html: '<svg viewBox="0 0 16 16"><path d="M3 1.5l9.5 9.2-4.2.4 2.4 4.4-1.6.9-2.4-4.5L3 14.5z" fill="#fff" stroke="#000" stroke-width=".8"/></svg>' });
  const lab = h("div.sk-lab", { text: "shake the mouse here" });
  root.append(ring, fake, lab);
  // detector: horizontal direction flips with enough travel inside a short window (the real one samples at 30 Hz from Lua)
  let hist: { x: number; t: number }[] = [];
  let cool = 0;
  let touched = false;
  function feed(x: number, y: number, t: number) {
    hist.push({ x, t });
    hist = hist.filter((p) => t - p.t < 650);
    let flips = 0, dist = 0, dir = 0;
    for (let i = 1; i < hist.length; i++) {
      const dx = hist[i].x - hist[i - 1].x;
      dist += Math.abs(dx);
      if (Math.abs(dx) < 2) continue;
      const d = Math.sign(dx);
      if (dir && d !== dir) flips++;
      dir = d;
    }
    if (flips >= 4 && dist > 320 && t > cool) { cool = t + 900; bloom(x, y); hist = []; }
  }
  function bloom(x: number, y: number) {
    ring.style.left = `${x}px`;
    ring.style.top = `${y}px`;
    ring.classList.remove("on");
    void ring.offsetWidth;
    ring.classList.add("on");
    lab.innerHTML = "<b>found it</b>";
    setTimeout(() => (lab.textContent = "shake the mouse here"), 1600);
  }
  root.addEventListener("pointermove", (e) => {
    if (e.pointerType !== "mouse") return;
    touched = true;
    fake.classList.remove("on");
    const r = root.getBoundingClientRect();
    feed(e.clientX - r.left, e.clientY - r.top, performance.now());
  });
  root.addEventListener("click", (e) => {
    if ((e as PointerEvent).pointerType === "mouse") return;
    const r = root.getBoundingClientRect();
    bloom(e.clientX - r.left, e.clientY - r.top);
  });
  // a ghost cursor shakes once when it scrolls in
  let played = false;
  visibility(root, async (v) => {
    if (!v || played) return;
    played = true;
    await sleep(1600);
    if (touched) return;
    const r = root.getBoundingClientRect();
    const cx = r.width * 0.5, cy = r.height * 0.45;
    fake.classList.add("on");
    const N = reduced ? 1 : 40;
    for (let i = 0; i <= N; i++) {
      if (touched) return;
      const x = cx + Math.sin(i / N * Math.PI * 7) * 46, y = cy + Math.sin(i / N * Math.PI * 3) * 6;
      fake.style.transform = `translate(${x}px, ${y}px)`;
      await sleep(16);
    }
    bloom(cx + 4, cy + 6);
    await sleep(1400);
    fake.classList.remove("on");
  });
}

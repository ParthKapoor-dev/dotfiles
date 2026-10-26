// Draw on screen (Super+A): a pointer with a comet tail, pens and a marker. Pens fade 1 s after the last stroke (+1 s fade);
// the marker stays. The toolbox is the voice pill's style.
import { h, reduced, sleep, visibility } from "../util";

type Tool = "pointer" | "pen" | "marker";
type Stroke = { pts: [number, number][]; tool: Tool; color: string; end: number };
const COLORS = ["#ff3b1f", "#ffffff", "#ffc24b", "#3fd5e0"];

export function initDraw(root: HTMLElement) {
  root.innerHTML = "";
  const cv = h("canvas.dr-cv") as HTMLCanvasElement;
  const tb = h("div.dr-tb", { role: "toolbar", "aria-label": "Draw tools" });
  const tools: [Tool, string][] = [["pointer", "Pointer"], ["pen", "Pen"], ["marker", "Marker"]];
  for (const [t, lb] of tools) tb.append(h(`button.dr-t${t === "pen" ? ".on" : ""}`, { type: "button", "data-t": t, text: lb }));
  tb.append(h("span.dr-sep"));
  for (const c of COLORS) tb.append(h(`button.dr-c${c === COLORS[0] ? ".on" : ""}`, { type: "button", "data-c": c, "aria-label": `ink ${c}`, style: { "--c": c } as any }));
  tb.append(h("span.dr-sep.s2"), h("span.dr-fade", { text: "FADE" }), h("button.dr-t", { type: "button", "data-x": "clear", text: "Clear" }));
  const hint = h("div.dr-hint", { text: "draw anywhere" });
  root.append(cv, hint, tb);

  const x = cv.getContext("2d")!;
  let dpr = 1, W = 0, H = 0;
  function fit() {
    dpr = Math.min(2, devicePixelRatio || 1);
    const r = root.getBoundingClientRect();
    W = r.width; H = r.height;
    cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
    x.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  new ResizeObserver(fit).observe(root);
  fit();

  let tool: Tool = "pen";
  let color = COLORS[0];
  let strokes: Stroke[] = [];
  let live: Stroke | null = null;
  let lastEnd = 0;
  let touched = false;
  let running = false;
  const HOLD = 1000, FADE = 1000, TAIL = 380;

  tb.addEventListener("click", (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>("button");
    if (!b) return;
    touched = true;
    if (b.dataset.t) { tool = b.dataset.t as Tool; tb.querySelectorAll("[data-t]").forEach((n) => n.classList.toggle("on", n === b)); }
    if (b.dataset.c) { color = b.dataset.c; tb.querySelectorAll("[data-c]").forEach((n) => n.classList.toggle("on", n === b)); }
    if (b.dataset.x === "clear") { strokes = []; }
    loop();
  });

  function pt(e: PointerEvent): [number, number] { const r = cv.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top]; }
  cv.addEventListener("pointerdown", (e) => {
    e.preventDefault();
    touched = true;
    hint.classList.add("gone");
    cv.setPointerCapture(e.pointerId);
    live = { pts: [pt(e)], tool, color, end: 0 };
    strokes.push(live);
    loop();
  });
  cv.addEventListener("pointermove", (e) => {
    if (!live) return;
    const p = pt(e);
    const q = live.pts[live.pts.length - 1];
    if (Math.hypot(p[0] - q[0], p[1] - q[1]) > 1.5) live.pts.push(p);
  });
  const up = () => { if (!live) return; live.end = performance.now(); lastEnd = live.end; live = null; };
  cv.addEventListener("pointerup", up);
  cv.addEventListener("pointercancel", up);

  function path(s: Stroke) {
    const p = s.pts;
    x.beginPath();
    x.moveTo(p[0][0], p[0][1]);
    for (let i = 1; i < p.length - 1; i++) x.quadraticCurveTo(p[i][0], p[i][1], (p[i][0] + p[i + 1][0]) / 2, (p[i][1] + p[i + 1][1]) / 2);
    if (p.length > 1) x.lineTo(p[p.length - 1][0], p[p.length - 1][1]);
  }
  function frame() {
    const now = performance.now();
    x.clearRect(0, 0, W, H);
    x.lineCap = "round"; x.lineJoin = "round";
    // a new stroke restarts the wait for every fading pen stroke
    const since = live ? 0 : now - lastEnd;
    const fade = since < HOLD ? 1 : Math.max(0, 1 - (since - HOLD) / FADE);
    strokes = strokes.filter((s) => s.tool === "marker" || s === live || (s.tool === "pointer" ? now - s.end < TAIL + 60 || !s.end : fade > 0));
    for (const s of strokes) {
      if (s.tool === "pointer") {
        const p = s.pts.slice(-14);
        for (let i = 1; i < p.length; i++) {
          const k = i / p.length * (s.end ? Math.max(0, 1 - (now - s.end) / TAIL) : 1);
          x.strokeStyle = s.color; x.globalAlpha = k * 0.9; x.lineWidth = 1 + k * 5;
          x.beginPath(); x.moveTo(p[i - 1][0], p[i - 1][1]); x.lineTo(p[i][0], p[i][1]); x.stroke();
        }
        const l = p[p.length - 1];
        x.globalAlpha = s.end ? Math.max(0, 1 - (now - s.end) / TAIL) : 1;
        x.fillStyle = s.color; x.shadowColor = s.color; x.shadowBlur = 16;
        x.beginPath(); x.arc(l[0], l[1], 4.5, 0, Math.PI * 2); x.fill();
        x.shadowBlur = 0;
        continue;
      }
      x.globalAlpha = s.tool === "marker" ? 0.38 : (s === live ? 1 : fade);
      x.strokeStyle = s.color;
      x.lineWidth = s.tool === "marker" ? 18 : 3.2;
      path(s);
      x.stroke();
    }
    x.globalAlpha = 1;
    return strokes.some((s) => s.tool !== "marker") || !!live;
  }
  function loop() {
    if (running) return;
    running = true;
    const go = () => { if (frame()) requestAnimationFrame(go); else running = false; };
    requestAnimationFrame(go);
  }

  // one scribble: circle the word, so the fade is visible
  let played = false;
  visibility(root, async (v) => {
    if (!v || played) return;
    played = true;
    await sleep(1300);
    if (touched) return;
    hint.classList.add("gone");
    const cx = W * 0.5, cy = H * 0.42, rx = Math.min(120, W * 0.3), ry = Math.min(48, H * 0.18);
    live = { pts: [], tool: "pen", color, end: 0 };
    strokes.push(live);
    loop();
    const N = reduced ? 2 : 46;
    for (let i = 0; i <= N; i++) {
      if (touched) break;
      const a = -Math.PI * 0.9 + (i / N) * Math.PI * 2.15;
      live?.pts.push([cx + Math.cos(a) * rx * (1 + i / N * 0.08), cy + Math.sin(a) * ry]);
      await sleep(14);
    }
    if (live && !touched) { live.end = performance.now(); lastEnd = live.end; live = null; }
    setTimeout(() => hint.classList.remove("gone"), 2600);
  });
}

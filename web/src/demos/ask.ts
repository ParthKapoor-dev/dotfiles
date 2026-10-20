// Circle to Ask: a frozen screen, a lasso drawn with the pointer, an answer that streams beside it.
import { h, ICON, reduced, sleep, toast, esc, visibility } from "../util";

type Topic = "term" | "table" | "poster" | "notes";
type Pt = { x: number; y: number };

const ANSWERS: Record<Topic, { ttft: string; text: string; more: string; tr: string; ocr: string; csv?: string }> = {
  term: {
    ttft: "0.7 s",
    text: "`first` still borrows `peers` when you `push` into it, and you use `first` after the push. **Fix:** take what you need before mutating, `let first = peers.first().cloned();`, or move the `push` below the `if let`. The borrow then ends before `peers` changes.",
    more: "Why the compiler refuses: a `Vec` may reallocate on `push`, so `first` could point at freed memory. Cloning one address is cheap; if the type is large, keep an index (`let i = 0;`) instead of a reference.",
    tr: "Nothing to translate: the error is already in English. In short: you read from `peers` and then changed it while the read was still in use.",
    ocr: "error[E0502]: cannot borrow `peers` as mutable because it is also borrowed as immutable --> src/mesh.rs:88:9",
  },
  table: {
    ttft: "0.6 s",
    text: "Fastest lap is **1:30.983**, car 16, 0.21 s clear of car 1. Almost all of it is in **sector 2** (the Esses and Degner): 38.62 against 38.84. Sector 3 is a dead heat.",
    more: "Car 63 loses 0.4 s in sector 1 alone, a sign of a poor exit from turn 1 rather than raw pace; its sector 3 is second best. Ask for the deltas as a chart and I will lay them out.",
    tr: "Table headers translated (日本語): ドライバー · ラップ · セクター1 · セクター2 · セクター3.",
    ocr: "car  lap       s1      s2      s3\n16   1:30.983  31.742  38.620  20.621\n1    1:31.194  31.811  38.844  20.539\n63   1:31.611  32.144  38.902  20.565",
    csv: "car,lap,s1,s2,s3\n16,1:30.983,31.742,38.620,20.621\n1,1:31.194,31.811,38.844,20.539\n63,1:31.611,32.144,38.902,20.565",
  },
  poster: {
    ttft: "0.5 s",
    text: "Japanese: **夜は静かに燃える** (*yoru wa shizuka ni moeru*), “the night burns quietly.” 夜 night · 静かに quietly · 燃える to burn. Reads like a film-poster tagline; the red disc is a rising-sun motif.",
    more: "The particle は marks 夜 as the topic, so it is closer to “as for the night, it burns quietly.” 静か is a na-adjective; with に it becomes the adverb “quietly”.",
    tr: "English: “The night burns quietly.”  Hindi: “रात चुपचाप जलती है।”",
    ocr: "夜は静かに燃える",
  },
  notes: {
    ttft: "0.6 s",
    text: "Three open items, all in the shell: a **boot intro** for the greeter, **undo after drag-out** on the shelf, and **smart tidy** for voice. The second is the smallest: the shelf already keeps what a remove took, so drag-out only needs to feed the same stack.",
    more: "Send to agent hands this note and the circled image to a coding agent in a new terminal, in the repo of the window you circled. It can open each item as an issue.",
    tr: "Hindi: तीन काम बाकी हैं: ग्रीटर का बूट इंट्रो, शेल्फ़ पर ड्रैग-आउट के बाद अनडू, और वॉइस के लिए स्मार्ट टाइडी।",
    ocr: "Ship list\n- greeter boot intro\n- shelf: undo after drag-out\n- voice: smart tidy",
  },
};

function md(s: string) {
  return esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<b>$1</b>")
    .replace(/\*([^*]+)\*/g, "<i>$1</i>");
}

export function initAsk(root: HTMLElement) {
  root.innerHTML = "";
  const bar = h("div.d-bar", null, h("span.sq"), "Circle to Ask", h("span.sp"), h("span.hint", { text: "Super Shift A · Esc closes" }));
  const screen = h("div.ask-screen");
  screen.innerHTML = `
    <div class="ask-win w-term" data-topic="term"><div class="wt"><i></i><i></i><i></i><span>ghostty · ~/code/relay</span></div><pre><span class="d">$</span> cargo build
   <span class="b">Compiling</span> relay v0.4.1
<span class="e">error[E0502]</span>: cannot borrow \`peers\` as mutable because
it is also borrowed as immutable
  <span class="b">--></span> src/mesh.rs:88:9
<span class="b">86</span> |   let first = peers.iter().next();
   |               <span class="y">----- immutable borrow here</span>
<span class="b">88</span> |       peers.push(addr);
   |       <span class="e">^^^^^^^^^^^^^^^^ mutable borrow here</span>
<span class="b">89</span> |   if let Some(p) = first { dial(p) }</pre></div>
    <div class="ask-win w-table" data-topic="table"><div class="wt"><i></i><i></i><i></i><span>timing · suzuka</span></div>
      <table><tr><th>car</th><th>lap</th><th>s1</th><th>s2</th><th>s3</th></tr>
      <tr><td>16</td><td class="hot">1:30.983</td><td>31.742</td><td>38.620</td><td>20.621</td></tr>
      <tr><td>1</td><td>1:31.194</td><td>31.811</td><td>38.844</td><td>20.539</td></tr>
      <tr><td>63</td><td>1:31.611</td><td>32.144</td><td>38.902</td><td>20.565</td></tr></table></div>
    <div class="ask-win w-poster" data-topic="poster"><div class="sun"></div><div class="jp">夜は静かに<br>燃える<small>NO. 07 · NIGHT SERIES</small></div></div>
    <div class="ask-win w-notes" data-topic="notes"><div class="wt" style="margin:-12px -14px 8px"><i></i><i></i><i></i><span>notes</span></div><b>Ship list</b>– greeter boot intro<br>– shelf: undo after drag-out<br>– voice: smart tidy</div>`;
  const freeze = h("div.ask-freeze");
  const canvas = h("canvas.ask-canvas", { "aria-label": "Draw a loop around part of the frozen screen" }) as HTMLCanvasElement;
  const pill = h("div.ask-pill", null, h("span.dot-live"), "Drag a loop around anything");
  const card = h("div.ask-card", { role: "dialog", "aria-label": "Claude's answer" });
  const reset = h("button.chip.ask-reset", { type: "button", html: `${ICON.sparkle}<span>Circle again</span>`, style: { display: "none" } });
  screen.append(freeze, canvas, pill, card, reset);
  root.append(bar, screen);

  const ctx = canvas.getContext("2d")!;
  let W = 0, H = 0, dpr = 1;
  let pts: Pt[] = [];
  let drawing = false;
  let closed = false;
  let thinking = false;
  let session = 0;
  let touched = false;
  let raf = 0;
  let dashT = 0;

  function size() {
    const r = screen.getBoundingClientRect();
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    W = r.width; H = r.height;
    canvas.width = W * dpr; canvas.height = H * dpr;
    paint();
  }
  new ResizeObserver(size).observe(screen);

  function pathLen(p: Pt[]) {
    let L = 0;
    for (let i = 1; i < p.length; i++) L += Math.hypot(p[i].x - p[i - 1].x, p[i].y - p[i - 1].y);
    return L;
  }

  function trace(p: Pt[]) {
    ctx.beginPath();
    p.forEach((q, i) => {
      if (i === 0) ctx.moveTo(q.x, q.y);
      else {
        const m = p[i - 1];
        ctx.quadraticCurveTo(m.x, m.y, (m.x + q.x) / 2, (m.y + q.y) / 2);
      }
    });
    if (closed) ctx.closePath();
  }

  function paint() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    if (pts.length < 2) return;
    if (closed) {
      // darken everything outside the loop
      ctx.save();
      ctx.beginPath();
      ctx.rect(0, 0, W, H);
      trace(pts);
      ctx.fillStyle = "rgba(0,0,0,.5)";
      ctx.fill("evenodd");
      ctx.restore();
      trace(pts);
      ctx.fillStyle = "rgba(255,59,31,.05)";
      ctx.fill();
    }
    // glow stroke
    ctx.lineJoin = "round"; ctx.lineCap = "round";
    trace(pts);
    ctx.shadowColor = "rgba(255,59,31,.9)";
    ctx.shadowBlur = 18;
    ctx.strokeStyle = "rgba(255,90,50,.9)";
    ctx.lineWidth = 3;
    ctx.stroke();
    ctx.shadowBlur = 0;
    trace(pts);
    ctx.strokeStyle = "rgba(255,230,220,.95)";
    ctx.lineWidth = 1.2;
    ctx.stroke();
    if (thinking && closed) {
      const L = pathLen(pts);
      trace(pts);
      ctx.setLineDash([L * 0.14, L]);
      ctx.lineDashOffset = -dashT * L;
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 3.2;
      ctx.shadowColor = "#fff"; ctx.shadowBlur = 12;
      ctx.stroke();
      ctx.setLineDash([]); ctx.shadowBlur = 0;
    }
  }

  function tick() {
    dashT = (dashT + 0.012) % 1;
    paint();
    if (thinking) raf = requestAnimationFrame(tick);
  }

  const local = (e: PointerEvent): Pt => {
    const r = canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };

  function clear() {
    session++;
    thinking = false; closed = false; drawing = false; pts = [];
    cancelAnimationFrame(raf);
    card.classList.remove("on");
    pill.classList.remove("gone");
    reset.style.display = "none";
    freeze.style.background = "";
    paint();
  }

  canvas.addEventListener("pointerdown", (e) => {
    touched = true;
    clear();
    drawing = true;
    canvas.setPointerCapture(e.pointerId);
    pts = [local(e)];
    pill.classList.add("gone");
  });
  canvas.addEventListener("pointermove", (e) => {
    if (!drawing) return;
    const p = local(e);
    const l = pts[pts.length - 1];
    if (Math.hypot(p.x - l.x, p.y - l.y) > 2.5) { pts.push(p); paint(); }
  });
  const up = () => {
    if (!drawing) return;
    drawing = false;
    finish();
  };
  canvas.addEventListener("pointerup", up);
  canvas.addEventListener("pointercancel", up);
  root.addEventListener("keydown", (e) => { if (e.key === "Escape") clear(); });
  root.tabIndex = -1;
  reset.addEventListener("click", () => { clear(); });

  function bbox(p: Pt[]) {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const q of p) { x0 = Math.min(x0, q.x); y0 = Math.min(y0, q.y); x1 = Math.max(x1, q.x); y1 = Math.max(y1, q.y); }
    return { x0, y0, x1, y1 };
  }

  async function finish() {
    const my = session;
    const L = pathLen(pts);
    let b = bbox(pts);
    const sr = screen.getBoundingClientRect();
    const wins = Array.from(screen.querySelectorAll<HTMLElement>(".ask-win")).map((w) => {
      const r = w.getBoundingClientRect();
      return { el: w, x0: r.left - sr.left, y0: r.top - sr.top, x1: r.right - sr.left, y1: r.bottom - sr.top };
    });
    if (L < 24) {
      // a click = that window
      const p = pts[0];
      const w = wins.find((w) => p.x >= w.x0 && p.x <= w.x1 && p.y >= w.y0 && p.y <= w.y1) || wins[0];
      pts = rectPts(w.x0 - 4, w.y0 - 4, w.x1 + 4, w.y1 + 4);
    } else {
      const first = pts[0], last = pts[pts.length - 1];
      const gap = Math.hypot(first.x - last.x, first.y - last.y);
      const diag = Math.hypot(b.x1 - b.x0, b.y1 - b.y0);
      if (gap > diag * 0.7) {
        // a straight drag = rectangle from start to end
        pts = rectPts(Math.min(first.x, last.x), Math.min(first.y, last.y), Math.max(first.x, last.x), Math.max(first.y, last.y));
      } else if (!reduced) {
        // animate the loop closing
        const steps = 8;
        for (let i = 1; i <= steps; i++) {
          if (my !== session) return;
          pts.push({ x: last.x + (first.x - last.x) * (i / steps), y: last.y + (first.y - last.y) * (i / steps) });
          paint();
          await sleep(16);
        }
      }
    }
    if (my !== session) return;
    closed = true;
    b = bbox(pts);
    // which window did we circle? most overlap
    let best: Topic = "term", bestA = -1;
    for (const w of wins) {
      const a = Math.max(0, Math.min(b.x1, w.x1) - Math.max(b.x0, w.x0)) * Math.max(0, Math.min(b.y1, w.y1) - Math.max(b.y0, w.y0));
      if (a > bestA) { bestA = a; best = w.el.dataset.topic as Topic; }
    }
    freeze.style.background = "rgba(0,0,0,.2)";
    thinking = true;
    raf = requestAnimationFrame(tick);
    showCard(best, b, my);
  }

  function rectPts(x0: number, y0: number, x1: number, y1: number): Pt[] {
    const r: Pt[] = [];
    const n = 10;
    for (let i = 0; i <= n; i++) r.push({ x: x0 + (x1 - x0) * (i / n), y: y0 });
    for (let i = 1; i <= n; i++) r.push({ x: x1, y: y0 + (y1 - y0) * (i / n) });
    for (let i = 1; i <= n; i++) r.push({ x: x1 - (x1 - x0) * (i / n), y: y1 });
    for (let i = 1; i < n; i++) r.push({ x: x0, y: y1 - (y1 - y0) * (i / n) });
    return r;
  }

  async function stream(el: HTMLElement, text: string, my: number) {
    const words = text.split(/(\s+)/);
    let s = "";
    for (let i = 0; i < words.length; i++) {
      if (my !== session) return false;
      s += words[i];
      if (!reduced && i % 2 === 0) {
        el.innerHTML = md(s) + '<span class="caret"></span>';
        await sleep(22 + Math.random() * 30);
      }
    }
    el.innerHTML = md(s);
    return true;
  }

  async function showCard(topic: Topic, b: { x0: number; y0: number; x1: number; y1: number }, my: number) {
    const A = ANSWERS[topic];
    card.innerHTML = "";
    const head = h("div.ask-head", null, h("span.ask-glyph", { html: ICON.sparkle }), h("b", { text: "Claude" }), "sonnet", h("span.sp"), h("span", { text: "thinking" }));
    const body = h("div.ask-body", null, h("p", { html: '<span class="caret"></span>' }));
    const chips = h("div.ask-chips");
    const agents = h("div.ask-agents", { style: { display: "none" } });
    const follow = h("div.ask-follow", { text: "Ask a follow-up…" });
    card.append(head, body, chips, agents, follow);
    // place it beside the loop
    const cw = Math.min(320, W * (W < 640 ? 0.88 : 0.7));
    const ch = Math.min(340, H - 20);
    let x: number, y: number;
    const clampY = (v: number) => Math.max(10, Math.min(v, H - ch - 10));
    if (b.x1 + 14 + cw <= W - 10) { x = b.x1 + 14; y = clampY(b.y0); }
    else if (b.x0 - 14 - cw >= 10) { x = b.x0 - 14 - cw; y = clampY(b.y0); }
    else if (H - b.y1 - 12 >= ch * 0.8) { x = Math.max(10, Math.min(W - cw - 10, b.x0)); y = b.y1 + 12; }
    else if (b.y0 - 12 >= ch * 0.8) { x = Math.max(10, Math.min(W - cw - 10, b.x0)); y = Math.max(10, b.y0 - 12 - ch); }
    else { x = W - cw - 10; y = clampY(H - ch - 10); }
    card.style.left = `${x}px`; card.style.top = `${y}px`;
    card.style.width = `${cw}px`;
    card.style.maxHeight = `${H - y - 10}px`;
    await sleep(reduced ? 0 : 180);
    if (my !== session) return;
    card.classList.add("on");
    await sleep(reduced ? 0 : 520);
    if (my !== session) return;
    (head.lastChild as HTMLElement).textContent = `first token ${A.ttft}`;
    const p = body.firstChild as HTMLElement;
    if (!(await stream(p, A.text, my))) return;
    thinking = false;
    paint();
    reset.style.display = "";
    const defs = [
      { id: "copy", icon: ICON.copy, text: "Copy text" },
      { id: "more", icon: ICON.sparkle, text: "Explain more" },
      { id: "send", icon: ICON.send, text: "Send to agent", hot: true },
      { id: "tr", icon: ICON.translate, text: "Translate" },
      { id: "csv", icon: ICON.table, text: "Table → CSV" },
      { id: "lens", icon: ICON.search, text: "Lens" },
    ];
    defs.forEach((d, i) => {
      const c = h("button.chip" + (d.hot ? ".hot" : ""), { type: "button", html: `${d.icon}<span>${d.text}</span>` });
      chips.append(c);
      setTimeout(() => c.classList.add("in"), reduced ? 0 : 30 + i * 55);
      c.addEventListener("click", async () => {
        const label = c.querySelector("span")!;
        const done = (t: string) => { c.classList.add("done"); c.innerHTML = `${ICON.check}<span>${t}</span>`; };
        if (d.id === "copy") { try { await navigator.clipboard.writeText(A.ocr); } catch {} done("Copied"); toast("Text from the circle is on the clipboard (OCR)"); }
        else if (d.id === "more" || d.id === "tr") {
          if (c.classList.contains("done")) return;
          done(d.id === "more" ? "Explained" : "Translated");
          const np = h("p");
          body.append(np);
          thinking = true; raf = requestAnimationFrame(tick);
          await stream(np, d.id === "more" ? A.more : A.tr, session);
          thinking = false; paint();
          body.scrollTop = body.scrollHeight;
        } else if (d.id === "csv") {
          if (A.csv) { try { await navigator.clipboard.writeText(A.csv); } catch {} done("CSV copied"); toast("Table copied as CSV"); }
          else { label.textContent = "No table here"; setTimeout(() => (label.textContent = d.text), 1600); }
        } else if (d.id === "lens") { toast("Lens: the region goes to Google Lens in the browser"); }
        else if (d.id === "send") {
          agents.style.display = agents.style.display === "none" ? "" : "none";
          if (!agents.childElementCount) {
            for (const a of ["claude", "codex", "gemini", "opencode"]) {
              const b2 = h("button.chip", { type: "button", text: a });
              b2.addEventListener("click", () => {
                agents.style.display = "none";
                done(`Sent to ${a}`);
                toast(`${a} opened in a new terminal with the prompt and the circled image`);
              });
              agents.append(b2);
            }
          }
        }
      });
    });
  }

  // auto-play once when visible, unless the visitor draws first
  async function ghost() {
    if (touched) return;
    const my = session;
    const sr = screen.getBoundingClientRect();
    const t = screen.querySelector<HTMLElement>(".w-term")!.getBoundingClientRect();
    const cx = (t.left + t.right) / 2 - sr.left, cy = t.top - sr.top + t.height * 0.47;
    const rx = t.width * 0.5, ry = t.height * 0.36;
    pill.classList.add("gone");
    pts = [];
    const n = 46;
    for (let i = 0; i <= n; i++) {
      if (touched || my !== session) return;
      const a = -Math.PI * 0.75 + (i / n) * Math.PI * 2 * 0.96;
      const wob = 1 + Math.sin(i * 0.7) * 0.03;
      pts.push({ x: cx + Math.cos(a) * rx * wob, y: cy + Math.sin(a) * ry * wob });
      paint();
      if (!reduced) await sleep(15);
    }
    finish();
  }
  let played = false;
  visibility(root, (on) => {
    if (on && !played) { played = true; setTimeout(ghost, reduced ? 200 : 1100); }
  });
}

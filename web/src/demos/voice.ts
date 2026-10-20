// Voice typing: press and hold (or hold Space), the pill records, release, the words land in the field.
// Simulated: no microphone is ever requested.
import { h, ICON, reduced, sleep, visibility } from "../util";

const PHRASES = [
  { raw: "Um, so the the shelf now keeps an undo stack for drag-out.", fillers: [0, 3] },
  { raw: "Uh, ship it after the doctor run is green.", fillers: [0] },
  { raw: "Remind me to bump the version, um, tomorrow morning.", fillers: [5] },
  { raw: "The model stays in VRAM and the server exits when I stop talking.", fillers: [] as number[] },
];

export function initVoice(root: HTMLElement) {
  root.innerHTML = "";
  const bar = h("div.d-bar", null, h("span.sq"), "Voice typing", h("span.sp"), h("span.hint", { text: "hold Super Shift Space" }));
  const stage = h("div.v-stage");
  const field = h("div.v-field", { "aria-live": "polite" }, h("span.lbl", { text: "commit message" }), h("span.ph", { text: "Hold the button and talk. Words appear here." }));
  const raw = h("div.v-raw", { "aria-hidden": "true" });
  const pill = h("div.v-pill");
  const rd = h("span.rd");
  const wave = h("canvas") as HTMLCanvasElement;
  const label = h("span", { text: "Ready" });
  const timer = h("span.t", { text: "0:00" });
  const tidyTag = h("span.tidy.on", { text: "TIDY" });
  pill.append(rd, label, wave, timer, tidyTag, h("span.sweep"));
  const hold = h("button.v-hold", { type: "button", "aria-label": "Hold to talk (or hold Space while this is focused)", html: ICON.mic });
  const holdLbl = h("div.v-hold-lbl", null, h("b", { text: "Hold to talk" }), h("span", { html: "or hold <kbd>Space</kbd> while focused" }));
  const tidyBtn = h("button.v-toggle.on", { type: "button", "aria-pressed": "true" }, h("span.switch"), "Tidy fillers");
  const controls = h("div.v-controls", null, hold, holdLbl, tidyBtn);
  stage.append(field, raw, pill, controls);
  const meta = h("div.v-meta", { html: "<span><b>●</b> whisper.cpp · Vulkan · local</span><span>model in VRAM · server exits when idle</span><span>audio deleted after transcribing</span>" });
  root.append(bar, stage, meta);

  const wctx = wave.getContext("2d")!;
  let hist: number[] = new Array(60).fill(0);
  let state: "idle" | "rec" | "tx" = "idle";
  let downAt = 0;
  let raf = 0;
  let tidy = true;
  let n = 0;
  let touched = false;
  let busy = false;

  function drawWave() {
    const r = wave.getBoundingClientRect();
    const dpr = Math.min(devicePixelRatio || 1, 2);
    if (wave.width !== Math.round(r.width * dpr)) { wave.width = Math.round(r.width * dpr); wave.height = Math.round(r.height * dpr); }
    wctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    wctx.clearRect(0, 0, r.width, r.height);
    const cols = Math.floor(r.width / 4.5);
    const rows = 5;
    const gap = r.height / rows;
    for (let c = 0; c < cols; c++) {
      const v = hist[hist.length - cols + c] ?? 0;
      const lit = Math.round(v * rows);
      for (let k = 0; k < rows; k++) {
        const dist = Math.abs(k - (rows - 1) / 2);
        const on = dist < lit / 2 + 0.01 && lit > 0;
        wctx.fillStyle = on ? (state === "rec" ? "rgba(255,90,60,.95)" : "rgba(255,255,255,.7)") : "rgba(255,255,255,.08)";
        wctx.beginPath();
        wctx.arc(c * 4.5 + 2, k * gap + gap / 2, 1.15, 0, 6.283);
        wctx.fill();
      }
    }
  }

  let syl = 0;
  function loop(now: number) {
    if (state === "rec") {
      // speech-like envelope: syllables + pauses
      syl += 0.33;
      const env = Math.max(0, Math.sin(syl) * 0.6 + Math.sin(syl * 0.37 + 1) * 0.4);
      hist.push(Math.min(1, env * (0.55 + Math.random() * 0.5)));
      const s = Math.floor((now - downAt) / 1000);
      timer.textContent = `0:${String(s).padStart(2, "0")}`;
    } else {
      hist.push(0);
    }
    if (hist.length > 200) hist = hist.slice(-120);
    drawWave();
    if (state !== "idle" || hist.slice(-80).some((v) => v > 0)) raf = requestAnimationFrame(loop);
  }

  function press() {
    if (state !== "idle" || busy) return;
    state = "rec";
    downAt = performance.now();
    hold.classList.add("down");
    pill.className = "v-pill rec";
    label.textContent = "Listening";
    cancelAnimationFrame(raf);
    raf = requestAnimationFrame(loop);
  }

  async function release() {
    if (state !== "rec") return;
    const dur = performance.now() - downAt;
    hold.classList.remove("down");
    if (dur < 300) {
      state = "idle";
      pill.className = "v-pill";
      label.textContent = "Too short: hold and talk";
      return;
    }
    state = "tx";
    busy = true;
    pill.className = "v-pill tx";
    label.textContent = "Transcribing… local · whisper";
    await sleep(reduced ? 50 : 420 + Math.random() * 200);
    const P = PHRASES[n++ % PHRASES.length];
    const words = P.raw.split(" ");
    const kept = tidy ? words.filter((_, i) => !P.fillers.includes(i)) : words;
    if (tidy && P.fillers.length) {
      // capitalise the new first word after a struck leading filler
      if (P.fillers.includes(0) && kept.length) kept[0] = kept[0][0].toUpperCase() + kept[0].slice(1);
      raw.innerHTML = words.map((w, i) => (P.fillers.includes(i) ? `<s>${w}</s>` : w)).join(" ");
    } else raw.textContent = "";
    const secs = (0.18 + Math.random() * 0.09).toFixed(2);
    state = "idle";
    pill.className = "v-pill";
    label.textContent = `${kept.length} words · ${secs} s`;
    // type into the field
    field.querySelector(".ph")?.remove();
    field.querySelector(".cursor")?.remove();
    if (field.querySelectorAll(".w").length) field.append(" ");
    const cursor = h("span.cursor");
    for (const w of kept) {
      const s = h("span.w", { text: w + " " });
      field.append(s);
      field.append(cursor);
      requestAnimationFrame(() => s.classList.add("in"));
      if (!reduced) await sleep(55);
    }
    busy = false;
  }

  hold.addEventListener("pointerdown", (e) => { e.preventDefault(); touched = true; hold.setPointerCapture(e.pointerId); press(); });
  hold.addEventListener("pointerup", release);
  hold.addEventListener("pointercancel", release);
  hold.addEventListener("contextmenu", (e) => e.preventDefault());
  root.tabIndex = 0;
  root.setAttribute("aria-label", "Voice typing demo: hold Space or the button");
  const onKey = (e: KeyboardEvent) => {
    if (e.code !== "Space") return;
    if (!root.contains(document.activeElement) && document.activeElement !== root) return;
    if ((e.target as HTMLElement).tagName === "INPUT") return;
    e.preventDefault();
    touched = true;
    if (e.type === "keydown" && !e.repeat) press();
    if (e.type === "keyup") release();
  };
  root.addEventListener("keydown", onKey);
  root.addEventListener("keyup", onKey);
  tidyBtn.addEventListener("click", () => {
    tidy = !tidy;
    tidyBtn.classList.toggle("on", tidy);
    tidyBtn.setAttribute("aria-pressed", String(tidy));
    tidyTag.classList.toggle("on", tidy);
  });
  drawWave();

  let played = false;
  visibility(root, async (on) => {
    if (!on || played) return;
    played = true;
    await sleep(1200);
    if (touched) return;
    press();
    await sleep(1700);
    if (!touched) release();
  });
}

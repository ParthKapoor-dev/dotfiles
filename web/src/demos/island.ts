// Dynamic Island: the bar's empty centre morphs to the most important live thing.
// Order (shell.json widgets.island.order): recording, mic, agent, timer, download, music, shelf.
// Hover = a card with that thing's controls, click = pin, wheel = cycle. `nox timer 5m tea` works in the prompt.
import { h, esc, reduced, sleep, toast, visibility } from "../util";

type K = "recording" | "mic" | "agent" | "timer" | "download" | "music" | "shelf";
const ORDER: K[] = ["recording", "mic", "agent", "timer", "download", "music", "shelf"];
type Live = {
  t0: number; end?: number; dur?: number; label?: string; done?: boolean;
  p?: number; name?: string; size?: number; need?: boolean; n?: number; playing?: boolean;
};

const SVG = {
  rec: '<i class="is-rec"></i>',
  mic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></svg>',
  agent: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 1.5l1.4 4.1 4.1 1.4-4.1 1.4L8 12.5 6.6 8.4 2.5 7l4.1-1.4z"/></svg>',
  dl: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M8 2.5v8M4.5 7.5L8 11l3.5-3.5M3 13.5h10"/></svg>',
  shelf: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M10.5 2.5h3v11h-3M2.5 8h7M6.5 5l3 3-3 3"/></svg>',
  ring: (p: number) => `<svg class="is-ring" viewBox="0 0 16 16"><circle class="bg" cx="8" cy="8" r="6"/><circle class="fg" cx="8" cy="8" r="6" style="stroke-dashoffset:${(37.7 * (1 - p)).toFixed(2)}"/></svg>`,
};

const mmss = (ms: number) => { const s = Math.max(0, Math.ceil(ms / 1000)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`; };

/** nox timer's own grammar: 5m 90s 1h30m 2.5m 1:30 25 (= minutes) */
function parseTime(w: string): number | null {
  if (/^\d+(\.\d+)?$/.test(w)) return +w * 60e3;
  let m = w.match(/^(\d+):(\d{2})(?::(\d{2}))?$/);
  if (m) return m[3] ? (+m[1] * 3600 + +m[2] * 60 + +m[3]) * 1e3 : (+m[1] * 60 + +m[2]) * 1e3;
  m = w.match(/^(?:(\d+(?:\.\d+)?)h)?(?:(\d+(?:\.\d+)?)m)?(?:(\d+)s)?$/);
  if (m && (m[1] || m[2] || m[3])) return ((+(m[1] || 0)) * 3600 + (+(m[2] || 0)) * 60 + +(m[3] || 0)) * 1e3;
  return null;
}

export function initIsland(root: HTMLElement) {
  root.innerHTML = "";
  const stage = h("div.is-stage");
  const bar = h("div.is-bar", null,
    h("span.is-left", { html: '<span class="sq"></span><b>Ghostty</b><span class="is-ws"><i class="on"></i><i></i><i></i><i></i></span>' }),
    h("span.sp"),
    h("span.is-right", { html: '<span>CPU <b>14%</b></span><span class="is-clock">TUE 26 OCT 18:40</span>' }),
  );
  const pill = h("button.is-pill", { type: "button", "aria-label": "Dynamic Island" });
  const inner = h("span.is-in");
  const dots = h("span.is-dots");
  pill.append(inner, dots);
  const cardEl = h("div.is-card", { role: "dialog", "aria-label": "Island card" });
  bar.append(pill);
  const desk = h("div.is-desk", { html: '<div class="is-hint"><span>hover the island</span><span>click pins · wheel cycles</span></div>' });
  stage.append(bar, cardEl, desk);

  const ctl = h("div.is-ctl", { role: "group", "aria-label": "Start a live activity" });
  const B: [K, string][] = [["timer", "Timer 5m tea"], ["download", "Download"], ["agent", "Agent"], ["recording", "Record"], ["music", "Music"], ["mic", "Mic"], ["shelf", "Shelf drop"]];
  for (const [k, lb] of B) ctl.append(h("button.chip", { type: "button", "data-k": k, text: lb }));
  const prompt = h("label.is-prompt", { html: "<span>$</span>" });
  const input = h("input", { type: "text", value: "nox timer 5m tea", spellcheck: "false", "aria-label": "Run a nox timer command" }) as HTMLInputElement;
  prompt.append(input, h("kbd", { text: "↵" }));
  root.append(stage, h("div.is-foot", null, ctl, prompt));

  const live: Partial<Record<K, Live>> = {};
  let pin: K | null = null;
  let pinUntil = 0;
  let cardOpen = false;
  let cardPinned = false;
  let hoverT = 0;
  let touched = false;
  let shown: K | null = null;
  let sig = "";

  const pri = (k: K) => {
    const s = live[k]!;
    if (k === "agent" && s.need) return 100;
    if (k === "timer" && s.done) return 95;
    if (k === "download" && s.done) return 60;
    return 90 - ORDER.indexOf(k) * 8;
  };
  const kinds = () => (Object.keys(live) as K[]).sort((a, b) => pri(b) - pri(a));
  const cur = (): K | null => {
    const ks = kinds();
    if (!ks.length) return null;
    if (pin && live[pin] && Date.now() < pinUntil) return pin;
    return ks[0];
  };

  function compact(k: K, s: Live, now: number) {
    switch (k) {
      case "recording": return `${SVG.rec}<span class="t tnum">${mmss(now - s.t0).replace(/^0:/, "0:")}</span><span class="m">REC</span>`;
      case "mic": return `<span class="is-mic">${SVG.mic}</span><span class="t">Mic</span><span class="m">${esc(s.name || "Voice typing")}</span>`;
      case "agent": return s.need
        ? `<span class="is-ag need">${SVG.agent}</span><span class="t">Needs you</span><span class="m">tasks</span>`
        : `<span class="is-ag">${SVG.agent}</span><span class="t">${esc(s.label || "Fixing tests")}</span><span class="m tnum">${Math.max(1, Math.floor((now - s.t0) / 6e4))}m</span><span class="is-bar-p"><i style="width:${Math.round((s.p || 0) * 100)}%"></i></span>`;
      case "timer": return s.done
        ? `<span class="is-ag need">${SVG.ring(1)}</span><span class="t">${esc(s.label || "Timer")}</span><span class="m">done</span>`
        : `${SVG.ring(1 - (s.end! - now) / s.dur!)}<span class="t tnum">${mmss(s.end! - now)}</span><span class="m">${esc(s.label || "")}</span>`;
      case "download": return s.done
        ? `<span class="is-ok">${SVG.dl}</span><span class="t">Downloaded</span><span class="m">${esc(s.name!)}</span>`
        : `${SVG.ring(s.p! / 100)}<span class="t">${esc(s.name!)}</span><span class="m tnum">${Math.round(s.p!)}%</span>`;
      case "music": return `<span class="is-art"></span><span class="t">Night Drive</span><span class="is-eq${s.playing ? "" : " paused"}"><i></i><i></i><i></i><i></i></span>`;
      case "shelf": return `<span class="is-ok">${SVG.shelf}</span><span class="t">${s.n} item${s.n! > 1 ? "s" : ""} parked</span>`;
    }
  }

  function cardHTML(k: K, s: Live, now: number) {
    const head = (small: string, big: string) => `<div class="ic-h"><small>${esc(small)}</small><b>${big}</b></div>`;
    switch (k) {
      case "recording": return head("Screen recording · wf-recorder", `<span class="tnum">${mmss(now - s.t0)}</span>`) + `<div class="ic-a"><button class="chip hot" data-ia="stop">Stop recording</button></div>`;
      case "mic": return head("Microphone in use", esc(s.name || "Voice typing")) + `<div class="ic-a"><button class="chip" data-ia="micstop">Stop using mic</button></div>`;
      case "agent": return s.need
        ? head("Claude Code · tasks · fix/tasklist-crash", "Approve this edit?") + `<p class="ic-p">src/hooks/useTasks.ts · start the hook with <code>useState&lt;Task[]&gt;([])</code> so the first render gets an array.</p><div class="ic-a"><button class="chip hot" data-ia="approve">Approve</button><button class="chip" data-ia="deny">Deny</button><button class="chip" data-ia="jump">Jump to agent</button></div>`
        : head("Claude Code · tasks", esc(s.label || "Fixing tests")) + `<div class="ic-prog"><i style="width:${Math.round((s.p || 0) * 100)}%"></i></div><div class="ic-a"><button class="chip" data-ia="jump">Jump to agent</button></div>`;
      case "timer": return head(`Timer · ${s.label || "timer"}`, s.done ? "Timer done" : `<span class="tnum">${mmss(s.end! - now)}</span>`) + `<div class="ic-a">${s.done ? "" : '<button class="chip" data-ia="plus">+1 min</button>'}<button class="chip" data-ia="cancel">${s.done ? "Dismiss" : "Cancel"}</button></div>`;
      case "download": return head("Zen · Downloads", esc(s.name!)) + `<div class="ic-prog"><i style="width:${Math.round(s.p!)}%"></i></div><p class="ic-p tnum">${s.done ? `${s.size} MB · done` : `${(s.size! * s.p! / 100).toFixed(1)} of ${s.size} MB · ${Math.max(1, Math.ceil((100 - s.p!) / 6))} s left`}</p><div class="ic-a"><button class="chip" data-ia="${s.done ? "show" : "dlcancel"}">${s.done ? "Show in Files" : "Cancel"}</button></div>`;
      case "music": return head("Now playing", "Night Drive") + `<p class="ic-p">Neon Static · Midnight Tapes</p><div class="ic-a"><button class="chip" data-ia="toggle">${s.playing ? "Pause" : "Play"}</button><button class="chip" data-ia="next">Next</button></div>`;
      case "shelf": return head("Drop shelf · right edge", `${s.n} item${s.n! > 1 ? "s" : ""}`) + `<div class="ic-a"><button class="chip" data-ia="shelfopen">Open shelf</button></div>`;
    }
  }

  function render() {
    const now = Date.now();
    const k = cur();
    pill.classList.toggle("live", !!k);
    if (!k) {
      shown = null; sig = "";
      inner.innerHTML = '<span class="t idle">nothing live</span>';
      dots.innerHTML = "";
      closeCard(true);
      size();
      return;
    }
    const s = live[k]!;
    pill.classList.toggle("hot", (k === "agent" && !!s.need) || (k === "timer" && !!s.done));
    pill.classList.toggle("rec", k === "recording");
    const others = kinds().filter((x) => x !== k);
    const nsig = `${k}|${others.join(",")}|${s.need}|${s.done}`;
    inner.innerHTML = compact(k, s, now);
    if (nsig !== sig) {
      dots.innerHTML = others.slice(0, 3).map((x) => `<i class="${pri(x) >= 95 ? "hot" : ""}" title="${x}"></i>`).join("");
      if (shown !== k) { pill.classList.remove("bump"); void pill.offsetWidth; pill.classList.add("bump"); }
      sig = nsig;
      shown = k;
    }
    size();
    if (cardOpen) cardEl.innerHTML = cardHTML(k, s, now);
  }
  function size() {
    // morph: measure the content, animate the width
    const w0 = pill.offsetWidth;
    pill.style.width = "auto";
    const w1 = pill.offsetWidth;
    pill.style.width = `${w0}px`;
    void pill.offsetWidth;
    pill.style.width = `${w1}px`;
  }

  function openCard(pinIt = false) {
    const k = cur();
    if (!k) return;
    cardOpen = true;
    if (pinIt) cardPinned = true;
    cardEl.innerHTML = cardHTML(k, live[k]!, Date.now());
    cardEl.classList.add("on");
    pill.classList.add("open");
  }
  function closeCard(force = false) {
    if (cardPinned && !force) return;
    cardOpen = false;
    cardPinned = false;
    cardEl.classList.remove("on");
    pill.classList.remove("open");
  }

  function add(k: K, s: Partial<Live> = {}) { live[k] = { t0: Date.now(), ...(live[k] || {}), ...s }; render(); }
  function remove(k: K) { delete live[k]; if (pin === k) pin = null; render(); }

  function start(k: K) {
    touched = true;
    if (k === "timer") startTimer(5 * 60e3, "tea");
    else if (k === "download") add("download", { name: "nox-wallpaper-5k.jpg", size: 18.4, p: 0, done: false });
    else if (k === "agent") { add("agent", { label: "Fixing tests", p: 0.2, need: false }); later(() => live.agent && add("agent", { need: true }), 2600); }
    else if (k === "recording") { if (live.recording) remove("recording"); else add("recording", { t0: Date.now() }); }
    else if (k === "music") { if (live.music) remove("music"); else add("music", { playing: true }); }
    else if (k === "mic") { if (live.mic) remove("mic"); else { add("mic", { name: "Voice typing" }); later(() => remove("mic"), 6000); } }
    else if (k === "shelf") { add("shelf", { n: (live.shelf?.n || 0) + 1, t0: Date.now() }); }
    pin = k; pinUntil = Date.now() + 2500; render();
  }
  function startTimer(ms: number, label: string) {
    add("timer", { t0: Date.now(), end: Date.now() + ms, dur: ms, label, done: false });
  }
  const timers: number[] = [];
  const later = (fn: () => void, ms: number) => timers.push(window.setTimeout(fn, ms));

  function act(id: string) {
    const k = cur();
    if (id === "stop") { remove("recording"); toast("Saved to ~/Videos · a card offers Save, Copy, Shelf"); }
    else if (id === "micstop") remove("mic");
    else if (id === "approve") { add("agent", { need: false, p: 0.85, label: "Tests pass" }); toast("Approved: the agent carries on"); later(() => remove("agent"), 3500); }
    else if (id === "deny") { remove("agent"); toast("Denied: the agent stops and waits"); }
    else if (id === "jump") toast("Focuses the agent's terminal window");
    else if (id === "plus" && live.timer) { live.timer.end! += 6e4; live.timer.dur! += 6e4; render(); }
    else if (id === "cancel") remove("timer");
    else if (id === "dlcancel") { remove("download"); toast("Download cancelled"); }
    else if (id === "show") { remove("download"); toast("Opens Dolphin with the file selected"); }
    else if (id === "toggle" && live.music) { live.music.playing = !live.music.playing; sig = ""; render(); }
    else if (id === "next") toast("Next track (playerctl next)");
    else if (id === "shelfopen") { remove("shelf"); toast("Opens the drop shelf"); }
    if (k && !live[k]) closeCard(true);
  }

  // events
  pill.addEventListener("pointerenter", () => { clearTimeout(hoverT); hoverT = window.setTimeout(() => openCard(), 140); });
  pill.addEventListener("pointerleave", () => { clearTimeout(hoverT); hoverT = window.setTimeout(() => { if (!cardEl.matches(":hover")) closeCard(); }, 260); });
  cardEl.addEventListener("pointerenter", () => clearTimeout(hoverT));
  cardEl.addEventListener("pointerleave", () => { hoverT = window.setTimeout(() => closeCard(), 260); });
  pill.addEventListener("click", () => { touched = true; if (cardPinned) closeCard(true); else openCard(true); });
  pill.addEventListener("wheel", (e) => {
    const ks = kinds();
    if (ks.length < 2) return;
    e.preventDefault();
    const c = cur()!;
    pin = ks[(ks.indexOf(c) + (e.deltaY > 0 ? 1 : ks.length - 1)) % ks.length];
    pinUntil = Date.now() + 9000;
    render();
  }, { passive: false });
  cardEl.addEventListener("click", (e) => { const b = (e.target as HTMLElement).closest<HTMLElement>("[data-ia]"); if (b) act(b.dataset.ia!); });
  ctl.addEventListener("click", (e) => { const b = (e.target as HTMLElement).closest<HTMLElement>("[data-k]"); if (b) start(b.dataset.k as K); });
  input.addEventListener("keydown", (e) => {
    if (e.key !== "Enter") return;
    touched = true;
    const w = input.value.trim().split(/\s+/);
    if (w[0] !== "nox" || w[1] !== "timer") { toast("Try: nox timer 90s pasta"); return; }
    if (w[2] === "stop") { remove("timer"); return; }
    if (w[2] === "add" && w[3]) { const ms = parseTime(w[3]); if (ms && live.timer) { live.timer.end! += ms; live.timer.dur! += ms; render(); } return; }
    const ms = w[2] ? parseTime(w[2]) : null;
    if (!ms || ms > 24 * 3600e3) { toast("<time>: 5m · 90s · 1h30m · 1:30 · 25 (minutes)"); return; }
    startTimer(ms, w.slice(3).join(" ") || "timer");
    pin = "timer"; pinUntil = Date.now() + 2500; render();
  });

  // ticker: only while something is live and the demo is on screen
  let on = false;
  let raf = 0;
  let last = 0;
  function tick(t: number) {
    if (!on) { raf = 0; return; }
    raf = requestAnimationFrame(tick);
    if (t - last < 250) return;
    last = t;
    const now = Date.now();
    const d = live.download;
    if (d && !d.done) { d.p = Math.min(100, d.p! + 1.6 + Math.random() * 1.4); if (d.p >= 100) { d.done = true; later(() => { if (live.download?.done) remove("download"); }, 5000); } }
    const tm = live.timer;
    if (tm && !tm.done && now >= tm.end!) { tm.done = true; toast(`${tm.label} timer is done`); }
    if (live.agent && !live.agent.need) live.agent.p = Math.min(0.9, (live.agent.p || 0) + 0.004);
    if (Object.keys(live).length) render();
  }
  render();
  visibility(root, async (v) => {
    on = v;
    if (v && !raf) raf = requestAnimationFrame(tick);
    if (!v || touched || root.dataset.played) return;
    root.dataset.played = "1";
    // a short scripted morning: a timer, a download, then an agent that needs you
    await sleep(reduced ? 200 : 900);
    if (touched) return;
    startTimer(5 * 60e3, "tea");
    await sleep(2200);
    if (touched) return;
    add("download", { name: "nox-wallpaper-5k.jpg", size: 18.4, p: 8 });
    await sleep(3200);
    if (touched) return;
    add("agent", { label: "Fixing tests", p: 0.4, need: true });
  });
}

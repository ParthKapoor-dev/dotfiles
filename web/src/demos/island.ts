// Dynamic Island: one black pill in the bar's centre shows the most important live thing.
// Order (shell.json widgets.island.order): recording, mic, agent, timer, download, music, shelf.
// It springs between items with a cross-fade and blur, every other live thing waits as a mini glyph,
// and hover grows the pill in place into a card with tabs. Click pins it, wheel cycles.
// `nox timer 5m tea` works in the prompt. Nothing ticks while nothing is live.
import { h, esc, reduced, sleep, toast, visibility } from "../util";

type K = "recording" | "mic" | "agent" | "timer" | "download" | "music" | "shelf";
const ORDER: K[] = ["recording", "mic", "agent", "timer", "download", "music", "shelf"];
type Live = {
  t0: number; end?: number; dur?: number; paused?: number; label?: string; done?: boolean;
  p?: number; name?: string; size?: number; need?: boolean; n?: number; playing?: boolean;
  calls?: string[]; nextCall?: number;
};

const SVG = {
  rec: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="8" cy="8" r="5.5"/><circle cx="8" cy="8" r="2.4" fill="currentColor" stroke="none"/></svg>',
  mic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></svg>',
  agent: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 1.5l1.4 4.1 4.1 1.4-4.1 1.4L8 12.5 6.6 8.4 2.5 7l4.1-1.4z"/></svg>',
  timer: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="8" cy="9" r="5"/><path d="M8 6.5V9l1.6 1.2M6.5 2h3"/></svg>',
  dl: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><path d="M8 2.5v8M4.5 7.5L8 11l3.5-3.5M3 13.5h10"/></svg>',
  music: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M6 12.5V3.5l7-1.5v9"/><circle cx="4.3" cy="12.5" r="1.8"/><circle cx="11.3" cy="11" r="1.8"/></svg>',
  shelf: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M10.5 2.5h3v11h-3M2.5 8h7M6.5 5l3 3-3 3"/></svg>',
  check: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 8.5l3.2 3L13 4.5"/></svg>',
  prev: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M4 3h1.6v10H4zM13 3v10L6.5 8z"/></svg>',
  next: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M10.4 3H12v10h-1.6zM3 3v10l6.5-5z"/></svg>',
  play: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M4.5 2.5v11l9-5.5z"/></svg>',
  pause: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5h3v11H4zM9 2.5h3v11H9z"/></svg>',
  ring: (p: number) => `<svg class="is-ring" viewBox="0 0 16 16"><circle class="bg" cx="8" cy="8" r="6"/><circle class="fg" cx="8" cy="8" r="6" style="stroke-dashoffset:${(37.7 * (1 - Math.max(0, Math.min(1, p)))).toFixed(2)}"/></svg>`,
};
const GLYPH: Record<K, string> = { recording: SVG.rec, mic: SVG.mic, agent: SVG.agent, timer: SVG.timer, download: SVG.dl, music: SVG.music, shelf: SVG.shelf };
const NAME: Record<K, string> = { recording: "Recording", mic: "Microphone", agent: "Agent", timer: "Timer", download: "Download", music: "Music", shelf: "Shelf" };
// what a working Claude Code session streams: one cell of the strip per tool call
const CALLS = ["Read(src/hooks/useTasks.ts)", "Grep(\"useTasks\")", "Bash(pnpm vitest run TaskList)", "Read(src/TaskList.tsx)", "Edit(src/hooks/useTasks.ts)", "Bash(pnpm vitest run)", "Read(vitest.config.ts)", "Bash(pnpm tsc --noEmit)"];
const STRIP = 8;

const mmss = (ms: number) => { const s = Math.max(0, Math.ceil(ms / 1000)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`; };
const hhmm = (t: number) => { const d = new Date(t); return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`; };

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
  // the pill: a compact row (face + mini glyphs) and the card it grows into, in one black shape
  const pill = h("div.is-pill", { role: "status", "aria-live": "polite", "aria-label": "Dynamic Island" });
  const row = h("div.is-row");
  const face = h("button.is-face", { type: "button", "aria-label": "Open the island card" });
  const glyphs = h("span.is-gl");
  row.append(face, glyphs);
  const card = h("div.is-x", { role: "group", "aria-label": "Island card" });
  pill.append(row, card);
  bar.append(pill);
  const desk = h("div.is-desk", { html: '<div class="is-hint"><span>hover the island</span><span>click pins · wheel cycles · glyphs switch</span></div>' });
  stage.append(bar, desk);

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
  let open = false;
  let pinnedOpen = false;
  let hoverT = 0;
  let touched = false;
  let shown: K | null | undefined;
  let glyphSig = "";
  let cardSig = "";
  let layer: HTMLElement | null = null;

  const left = (s: Live, now: number) => (s.paused != null ? s.paused : Math.max(0, s.end! - now));
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
    // a pin holds for a while; an agent that needs you (or a finished timer) only yields to a pin set after it
    if (pin && live[pin] && Date.now() < pinUntil) return pin;
    return ks[0];
  };
  const strip = (s: Live) => {
    const n = (s.calls || []).length;
    const lit = n === 0 ? 0 : ((n - 1) % STRIP) + 1;
    return `<span class="is-strip">${Array.from({ length: STRIP }, (_, i) => `<i class="${i < lit ? "on" : ""}${i === lit - 1 ? " now" : ""}"></i>`).join("")}</span>`;
  };

  /** the compact face: each kind has its own */
  function faceHTML(k: K, s: Live, now: number) {
    switch (k) {
      case "recording": return `<span class="is-blink"></span><span class="t tnum">${mmss(now - s.t0)}</span><span class="m">REC</span>`;
      case "mic": return `<span class="is-mic">${SVG.mic}</span><span class="t">Mic</span><span class="m">listening ${mmss(now - s.t0)}</span>`;
      case "agent": return s.need
        ? `<span class="is-need"><i></i></span><span class="t acc">Needs you</span><span class="m">tasks · edit</span>`
        : `<span class="is-ag">${SVG.agent}</span><span class="t">${esc(s.label || "Fixing tests")}</span><span class="m tnum">${Math.max(1, Math.floor((now - s.t0) / 6e4))}m</span>${strip(s)}`;
      case "timer": return s.done
        ? `<span class="is-need"><i></i></span><span class="t acc">Timer done</span><span class="m">${esc(s.label || "")}</span>`
        : `${SVG.ring(left(s, now) / s.dur!)}<span class="t tnum">${mmss(left(s, now))}</span><span class="m">${s.paused != null ? "paused" : esc(s.label || "")}</span>`;
      case "download": return s.done
        ? `<span class="is-ok">${SVG.check}</span><span class="t">Downloaded</span><span class="m">${esc(s.name!)}</span>`
        : `<span class="is-dl">${SVG.dl}</span><span class="t">${esc(s.name!)}</span>${SVG.ring(s.p! / 100)}<span class="m tnum">${Math.round(s.p!)}%</span>`;
      case "music": return `<span class="is-art"></span><span class="t">Night Drive</span><span class="is-eq${s.playing ? "" : " paused"}"><i></i><i></i><i></i><i></i></span>`;
      case "shelf": return `<span class="is-ok">${SVG.shelf}</span><span class="t">${s.n} item${s.n! > 1 ? "s" : ""} parked</span>`;
    }
  }

  /** the card the pill grows into: header, body, then actions and tabs */
  function cardHTML(k: K, s: Live, now: number) {
    const head = (icon: string, small: string, big: string, right = "", hot = false) =>
      `<div class="ic-h"><span class="ic-i${hot ? " hot" : ""}">${icon}</span><div class="ic-tt"><small>${esc(small)}</small><b>${big}</b></div>${right ? `<span class="ic-r">${right}</span>` : ""}</div>`;
    const btn = (id: string, label: string, hot = false) => `<button type="button" class="ic-b${hot ? " hot" : ""}" data-ia="${id}">${label}</button>`;
    let top = "", body = "", acts = "";
    switch (k) {
      case "recording":
        top = head(SVG.rec, "Screen recording · wf-recorder", `recording_${hhmm(s.t0).replace(":", "-")}.mp4`, `<span class="tnum">${mmss(now - s.t0)}</span>`);
        body = `<p class="ic-p">~/Videos</p>`;
        acts = btn("stop", "Stop recording", true);
        break;
      case "mic":
        top = head(SVG.mic, "Microphone in use", "Voice typing · Whisper (local)");
        body = `<div class="ic-lv">${Array.from({ length: 28 }, (_, i) => `<i style="--k:${(i * 7) % 11}"></i>`).join("")}</div>`;
        acts = btn("micstop", "Stop using mic", true);
        break;
      case "agent":
        if (s.need) {
          top = head(SVG.agent, "Claude Code · tasks · waiting on you", "Allow edit?", `<span class="tnum">${mmss(now - s.t0)}</span>`, true);
          body = `<div class="ic-q">Edit src/hooks/useTasks.ts<br>useState&lt;Task[]&gt;([]) so the first render gets an array</div>
            <div class="ic-ss"><span class="hot"><i></i><b>tasks</b> Needs you</span><span><i></i><b>web</b> Working</span></div>`;
        } else {
          const calls = (s.calls || []).slice(-3);
          top = head(SVG.agent, "Claude Code · tasks · fix/tasklist-crash", esc(s.label || "Fixing tests"), `<span class="tnum">${mmss(now - s.t0)}</span>`, true);
          body = `${strip(s)}<div class="ic-calls">${calls.map((c, i) => `<span class="${i === calls.length - 1 ? "now" : ""}">${esc(c)}</span>`).join("") || "<span>starting…</span>"}</div>`;
        }
        acts = btn("jump", "Jump to agent", true) + btn("agents", "Agents");
        break;
      case "timer":
        top = head(SVG.timer, `Timer · ${s.label || "timer"}`, s.done ? "Time is up" : `${Math.round(s.dur! / 6e4)} minute timer`, `<span class="ic-big tnum">${mmss(s.done ? 0 : left(s, now))}</span>`);
        body = `<div class="ic-prog"><i style="width:${s.done ? 0 : (left(s, now) / s.dur!) * 100}%"></i></div><p class="ic-p">${s.done ? "A notification and a sound went out" : s.paused != null ? "Paused" : `Ends at ${hhmm(s.end!)}`}</p>`;
        acts = s.done ? btn("cancel", "Done", true) + btn("plus", "+1 min") : btn("plus", "+1 min") + btn("tpause", s.paused != null ? "Resume" : "Pause") + btn("cancel", "Cancel");
        break;
      case "download":
        top = head(SVG.dl, "Downloads", esc(s.name!), `<span class="tnum">${s.done ? s.size : (s.size! * s.p! / 100).toFixed(1)} MB</span>`);
        body = `<div class="ic-prog"><i style="width:${Math.round(s.p!)}%"></i></div><p class="ic-p tnum">${s.done ? "done · ~/Downloads" : `8.4 MB/s · ${Math.max(1, Math.ceil((100 - s.p!) / 6))} s left`}</p>`;
        acts = btn("show", "Show in Files", true);
        break;
      case "music":
        top = head(SVG.music, "Now playing", "Night Drive — Neon Static", `<span class="is-eq${s.playing ? "" : " paused"}"><i></i><i></i><i></i><i></i></span>`);
        body = `<div class="ic-prog"><i style="width:${((((now - s.t0) / 1000) % 240) / 2.4).toFixed(1)}%"></i></div>`;
        acts = `<button type="button" class="ic-b ico" data-ia="prev" aria-label="Previous">${SVG.prev}</button><button type="button" class="ic-b ico hot" data-ia="toggle" aria-label="Play or pause">${s.playing ? SVG.pause : SVG.play}</button><button type="button" class="ic-b ico" data-ia="next" aria-label="Next">${SVG.next}</button>`;
        break;
      case "shelf":
        top = head(SVG.shelf, "Drop shelf · right edge", `${s.n} item${s.n! > 1 ? "s" : ""} parked`);
        acts = btn("shelfopen", "Open shelf", true);
        break;
    }
    const tabs = kinds().map((x) => `<button type="button" class="ic-tab${x === k ? " on" : ""}${pri(x) >= 95 ? " hot" : ""}" data-tab="${x}" aria-label="${NAME[x]}" title="${NAME[x]}">${GLYPH[x]}</button>`).join("");
    return `${top}${body}<div class="ic-f"><div class="ic-a">${acts}</div><div class="ic-tabs">${tabs}</div></div>`;
  }

  /** spring the pill to the size of what it shows now */
  function size() {
    const max = stage.clientWidth - 24;
    if (open) {
      const w = Math.min(360, max);
      card.style.width = `${w}px`;
      pill.style.width = `${w}px`;
      pill.style.height = `${card.offsetHeight}px`;
    } else {
      pill.style.width = `${Math.min(row.offsetWidth, max)}px`;
      pill.style.height = "26px";
    }
  }

  function render() {
    const now = Date.now();
    const k = cur();
    pill.classList.toggle("live", !!k);
    if (!k) {
      if (shown !== null) swap('<span class="t idle">idle</span>');
      shown = null; glyphSig = ""; cardSig = "";
      glyphs.innerHTML = "";
      if (open) setOpen(false, true);
      size();
      return;
    }
    const s = live[k]!;
    pill.classList.toggle("hot", (k === "agent" && !!s.need) || (k === "timer" && !!s.done));
    const html = faceHTML(k, s, now);
    const fsig = `${k}|${s.need}|${s.done}`;
    if (layer?.dataset.sig !== fsig) swap(html, fsig); else if (layer.innerHTML !== html) layer.innerHTML = html;
    shown = k;
    const others = kinds().filter((x) => x !== k);
    const gsig = others.map((x) => `${x}${pri(x) >= 95 ? "!" : ""}`).join(",");
    if (gsig !== glyphSig) {
      glyphs.innerHTML = others.slice(0, 4).map((x) => `<button type="button" class="is-g${pri(x) >= 95 ? " hot" : ""}" data-g="${x}" aria-label="Show ${NAME[x]}" title="${NAME[x]}">${GLYPH[x]}</button>`).join("");
      glyphSig = gsig;
    }
    if (open) {
      const c = cardHTML(k, s, now);
      if (c !== cardSig) { card.innerHTML = c; cardSig = c; }
    }
    size();
  }
  /** cross-fade with blur from the old face to the new one */
  function swap(html: string, sig = "") {
    const old = layer;
    const L = h("span.is-l.enter", { html, "data-sig": sig });
    layer = L;
    face.append(L);
    requestAnimationFrame(() => requestAnimationFrame(() => L.classList.remove("enter")));
    if (old) {
      old.classList.add("leave");
      setTimeout(() => { old.remove(); size(); }, reduced ? 0 : 320);
    }
  }

  function setOpen(v: boolean, force = false) {
    if (!v && pinnedOpen && !force) return;
    if (v && !cur()) return;
    open = v;
    if (!v) pinnedOpen = false;
    pill.classList.toggle("open", open);
    cardSig = "";
    if (open) render(); else size();
  }

  function add(k: K, s: Partial<Live> = {}) { live[k] = { t0: Date.now(), ...(live[k] || {}), ...s }; render(); wake(); }
  function remove(k: K) { delete live[k]; if (pin === k) pin = null; render(); }
  const show = (k: K, ms = 2500) => { pin = k; pinUntil = Date.now() + ms; render(); };

  function start(k: K) {
    touched = true;
    if (k === "timer") startTimer(5 * 60e3, "tea");
    else if (k === "download") add("download", { name: "nox-wallpaper-5k.jpg", size: 18.4, p: 0, done: false });
    else if (k === "agent") { add("agent", { label: "Fixing tests", need: false, calls: [], nextCall: 0, t0: Date.now() }); later(() => live.agent && !live.agent.need && add("agent", { need: true }), 6500); }
    else if (k === "recording") { if (live.recording) remove("recording"); else add("recording", { t0: Date.now() }); }
    else if (k === "music") { if (live.music) remove("music"); else add("music", { playing: true }); }
    else if (k === "mic") { if (live.mic) remove("mic"); else { add("mic", { t0: Date.now() }); later(() => remove("mic"), 6000); } }
    else if (k === "shelf") { add("shelf", { n: (live.shelf?.n || 0) + 1, t0: Date.now() }); }
    if (live[k]) show(k);
  }
  function startTimer(ms: number, label: string) {
    add("timer", { t0: Date.now(), end: Date.now() + ms, dur: ms, label, done: false, paused: undefined });
  }
  const later = (fn: () => void, ms: number) => window.setTimeout(fn, ms);

  function act(id: string) {
    const t = live.timer;
    if (id === "stop") { remove("recording"); toast("Saved to ~/Videos · a card offers Save, Copy, Shelf"); }
    else if (id === "micstop") remove("mic");
    else if (id === "jump") {
      toast("Focuses the agent's terminal window");
      if (live.agent?.need) later(() => { if (live.agent) { add("agent", { need: false, label: "Tests pass" }); toast("Answered in the terminal: the agent carries on"); later(() => remove("agent"), 5000); } }, 1400);
    }
    else if (id === "agents") toast("Opens agent mission control (Super+Shift+M)");
    else if (id === "plus" && t) { if (t.paused != null) t.paused += 6e4; else t.end = Math.max(t.end!, Date.now()) + 6e4; t.dur! += 6e4; t.done = false; }
    else if (id === "tpause" && t) { if (t.paused != null) { t.end = Date.now() + t.paused; t.paused = undefined; } else t.paused = Math.max(0, t.end! - Date.now()); }
    else if (id === "cancel") remove("timer");
    else if (id === "show") { remove("download"); toast("Opens Dolphin with the file selected"); }
    else if (id === "toggle" && live.music) live.music.playing = !live.music.playing;
    else if (id === "next" || id === "prev") toast(`playerctl ${id === "next" ? "next" : "previous"}`);
    else if (id === "shelfopen") { remove("shelf"); toast("Opens the drop shelf"); }
    cardSig = "";
    render();
  }

  // hover grows it, leaving shrinks it back; a click pins it open
  pill.addEventListener("pointerenter", () => { clearTimeout(hoverT); hoverT = window.setTimeout(() => setOpen(true), 140); });
  pill.addEventListener("pointerleave", () => { clearTimeout(hoverT); hoverT = window.setTimeout(() => setOpen(false), 280); });
  face.addEventListener("click", () => { touched = true; if (pinnedOpen) setOpen(false, true); else { setOpen(true); pinnedOpen = open; } });
  glyphs.addEventListener("click", (e) => { const g = (e.target as HTMLElement).closest<HTMLElement>("[data-g]"); if (g) { touched = true; show(g.dataset.g as K, 9000); } });
  card.addEventListener("click", (e) => {
    const tab = (e.target as HTMLElement).closest<HTMLElement>("[data-tab]");
    if (tab) { touched = true; pinnedOpen = true; cardSig = ""; show(tab.dataset.tab as K, 9000); return; }
    const b = (e.target as HTMLElement).closest<HTMLElement>("[data-ia]");
    if (b) { touched = true; act(b.dataset.ia!); }
  });
  document.addEventListener("pointerdown", (e) => { if (pinnedOpen && !pill.contains(e.target as Node)) setOpen(false, true); });
  root.addEventListener("keydown", (e) => { if (e.key === "Escape" && open) setOpen(false, true); });
  pill.addEventListener("wheel", (e) => {
    const ks = kinds();
    if (ks.length < 2) return;
    e.preventDefault();
    const c = cur()!;
    cardSig = "";
    show(ks[(ks.indexOf(c) + (e.deltaY > 0 ? 1 : ks.length - 1)) % ks.length], 9000);
  }, { passive: false });
  ctl.addEventListener("click", (e) => { const b = (e.target as HTMLElement).closest<HTMLElement>("[data-k]"); if (b) start(b.dataset.k as K); });
  input.addEventListener("keydown", (e) => {
    if (e.key !== "Enter") return;
    touched = true;
    const w = input.value.trim().split(/\s+/);
    if (w[0] !== "nox" || w[1] !== "timer") { toast("Try: nox timer 90s pasta"); return; }
    if (w[2] === "stop") { remove("timer"); return; }
    if (w[2] === "add" && w[3]) {
      const ms = parseTime(w[3]); const tm = live.timer;
      if (ms && tm) { if (tm.paused != null) tm.paused += ms; else tm.end = Math.max(tm.end!, Date.now()) + ms; tm.dur! += ms; tm.done = false; render(); }
      return;
    }
    const ms = w[2] ? parseTime(w[2]) : null;
    if (!ms || ms > 24 * 3600e3) { toast("<time>: 5m · 90s · 1h30m · 1:30 · 25 (minutes)"); return; }
    startTimer(ms, w.slice(3).join(" ") || "timer");
    show("timer");
  });

  // ticker: only while something is live and the demo is on screen; it stops by itself when idle
  let on = false;
  let raf = 0;
  let last = 0;
  function tick(t: number) {
    if (!on || !Object.keys(live).length) { raf = 0; return; }
    raf = requestAnimationFrame(tick);
    if (t - last < 250) return;
    last = t;
    const now = Date.now();
    const d = live.download;
    if (d && !d.done) { d.p = Math.min(100, d.p! + 1.6 + Math.random() * 1.4); if (d.p >= 100) { d.done = true; later(() => { if (live.download?.done) remove("download"); }, 5000); } }
    const tm = live.timer;
    if (tm && !tm.done && tm.paused == null && now >= tm.end!) { tm.done = true; toast(`${tm.label} timer is done`); }
    const a = live.agent;
    if (a && !a.need && now >= (a.nextCall || 0)) { a.calls = [...(a.calls || []), CALLS[(a.calls || []).length % CALLS.length]]; a.nextCall = now + 900 + Math.random() * 900; }
    render();
  }
  function wake() { if (on && !raf && Object.keys(live).length) raf = requestAnimationFrame(tick); }
  render();
  visibility(root, async (v) => {
    on = v;
    wake();
    if (!v || touched || root.dataset.played) return;
    root.dataset.played = "1";
    // a short scripted morning: a timer, a download, an agent working through tool calls, then it needs you
    await sleep(reduced ? 200 : 900);
    if (touched) return;
    startTimer(5 * 60e3, "tea");
    await sleep(2200);
    if (touched) return;
    add("download", { name: "nox-wallpaper-5k.jpg", size: 18.4, p: 8 });
    await sleep(3000);
    if (touched) return;
    add("agent", { label: "Fixing tests", need: false, calls: [], nextCall: 0, t0: Date.now() - 90e3 });
    show("agent", 4000);
    await sleep(4400);
    if (touched || !live.agent) return;
    add("agent", { need: true });
  });
}

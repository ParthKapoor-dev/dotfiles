// Selection action bar: select text in the window and a small bar of actions appears above it.
// Ask · Search · Translate · Copy · Shelf, plus Open link (a URL only), Case (cycles, copies) and "= result" (maths only).
import { h, esc, reduced, sleep, toast, visibility, ICON } from "../util";

const I = {
  ask: ICON.sparkle,
  search: ICON.search,
  translate: ICON.translate,
  copy: ICON.copy,
  shelf: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M10.5 2.5h3v11h-3M2.5 8h7M6.5 5l3 3-3 3"/></svg>',
  link: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M7 9a2.8 2.8 0 0 0 4 0l2-2a2.8 2.8 0 0 0-4-4l-.7.7M9 7a2.8 2.8 0 0 0-4 0L3 9a2.8 2.8 0 0 0 4 4l.7-.7"/></svg>',
  case: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"><path d="M1.5 12.5l3-9 3 9M2.6 9.5h3.8M10 7.4a2 2 0 1 1 0 4 2 2 0 0 1 0-4zM12 7.5v5"/></svg>',
};

// sentences that have a ready translation (Translate opens Google Translate, auto → en)
const TR: Record<string, string> = {
  "la barra de 30 px pegada arriba es otro mundo frente a la píldora flotante. sin indicadores, solo el reloj.":
    "the 30 px bar flush at the top is another world compared with the floating pill. no gauges, just the clock.",
};

type Kind = "text" | "link" | "math" | "code";

function kindOf(t: string): Kind {
  if (/^(https?:\/\/)?[\w-]+(\.[\w-]+)+(\/\S*)?$/i.test(t)) return "link";
  if (calc(t) != null) return "math";
  if (/[=_{}();]|^[a-z_]+:[a-z_]+$/.test(t) && t.length < 60) return "code";
  return "text";
}

function calc(q: string): number | null {
  const s = q.replace(/=\s*$/, "").replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/(\d),(?=\d{3}\b)/g, "$1").trim();
  if (!s || !/^[\d\s+\-*/().%]+$/.test(s) || !/\d\s*[-+*/%]\s*[\d(]/.test(s)) return null;
  try {
    // eslint-disable-next-line no-new-func
    const v = Function(`"use strict";return (${s})`)();
    return typeof v === "number" && isFinite(v) ? Math.round(v * 1e6) / 1e6 : null;
  } catch { return null; }
}
const fmt = (n: number) => n.toLocaleString("en-US", { maximumFractionDigits: 4 });

const CASES = ["UPPER", "lower", "Title", "Sentence"] as const;
function recase(t: string, i: number) {
  if (i === 0) return t.toUpperCase();
  if (i === 1) return t.toLowerCase();
  if (i === 2) return t.toLowerCase().replace(/(^|[\s\-_/(“"])(\S)/g, (_, a, b) => a + b.toUpperCase());
  const l = t.toLowerCase();
  return l.charAt(0).toUpperCase() + l.slice(1);
}

function answer(t: string, k: Kind) {
  const short = t.length > 48 ? t.slice(0, 46) + "…" : t;
  if (k === "math") return `That works out to <b>${fmt(calc(t)!)}</b>. At 144 Hz a 380 ms animation is about 55 frames, versus 23 at 60 Hz, which is why short, front-loaded curves feel smoother on fast panels.`;
  if (k === "link") return `That is the <b>Animations</b> page of the Hyprland wiki: <code>animation = NAME, ONOFF, SPEED, CURVE, STYLE</code>, plus the list of things you can animate.`;
  if (k === "code") return `<code>${esc(short)}</code> is Hyprland config. <code>rounding_power</code> is the exponent of the superellipse each corner is drawn with: 2.0 is a circular arc, 4.0 a squircle.`;
  return `You selected “${esc(short)}”. In short: it is a note about how this desktop animates. I can explain it, make it shorter, or turn it into a task for an agent.`;
}

export function initSelbar(root: HTMLElement) {
  root.innerHTML = "";
  const bar = h("div.d-bar", null, h("span.sq"), "Selection bar", h("span.sp"), h("span.hint", { text: "select any text" }));
  const screen = h("div.sb-screen");
  const win = h("div.sb-win", null,
    h("div.wt", { html: "<i></i><i></i><i></i><span>zen · wiki.hypr.land/Configuring/Animations</span>" }),
  );
  const doc = h("article.sb-doc", { html: `
    <h4>Animations</h4>
    <p>Animations are declared with <code>animation = windows, 1, 4, apple, popin 92%</code>. Speed is in deciseconds, so <code>4</code> is 400 ms.</p>
    <p>At 144 Hz, a 380 ms window animation is <span class="sb-m">380 * 144 / 1000</span> frames, so keep curves short and front-loaded.</p>
    <p>Source: <span class="sb-u">wiki.hypr.land/Configuring/Animations</span></p>
    <blockquote><small>r/unixporn · 2h</small><span class="sb-es">la barra de 30 px pegada arriba es otro mundo frente a la píldora flotante. sin indicadores, solo el reloj.</span></blockquote>` });
  win.append(doc);
  const pop = h("div.sb-pop", { role: "toolbar", "aria-label": "Selection actions" });
  const card = h("div.sb-card", { "aria-live": "polite" });
  const cli = h("div.sb-cli", { html: "<span>$</span> nox selbar status · on, watching the primary selection" });
  screen.append(win, pop, card, cli);
  root.append(bar, screen);

  let text = "";
  let kind: Kind = "text";
  let caseI = -1;
  let touched = false;
  let open = false;
  let settle = 0;

  const say = (s: string) => { cli.innerHTML = `<span>$</span> ${esc(s)}`; };

  function hide() {
    open = false;
    pop.classList.remove("on");
    card.classList.remove("on");
  }

  function place(r: DOMRect) {
    const sr = screen.getBoundingClientRect();
    const pw = pop.offsetWidth || 360;
    let x = r.left + r.width / 2 - sr.left - pw / 2;
    x = Math.max(8, Math.min(sr.width - pw - 8, x));
    let y = r.top - sr.top - 48;
    const below = y < 30;
    if (below) y = r.bottom - sr.top + 10;
    pop.style.transform = `translate(${x.toFixed(0)}px, ${y.toFixed(0)}px)`;
    const cw = Math.min(340, sr.width - 16);
    const cx = Math.max(8, Math.min(sr.width - cw - 8, x));
    card.style.width = `${cw}px`;
    card.style.transform = `translate(${cx.toFixed(0)}px, ${(y + 46).toFixed(0)}px)`;
  }

  function show(t: string, r: DOMRect) {
    text = t.replace(/\s+/g, " ").trim();
    kind = kindOf(text);
    caseI = -1;
    const acts: [string, string, string, string][] = [["ask", I.ask, "Ask Claude", "Ask Claude about the selection"]];
    const v = kind === "math" ? calc(text) : null;
    if (v != null) acts.push(["calc", "", `= ${fmt(v)}`, "Copy the result"]);
    if (kind === "link") acts.push(["link", I.link, "Open link", "Open it in the browser"]);
    acts.push(["copy", I.copy, "Copy", "Copy (also lands in clipboard history)"], ["translate", I.translate, "Translate", "Google Translate, auto → en"], ["search", I.search, "Search", "Search the web"], ["shelf", I.shelf, "Shelf", "Park it on the drop shelf"], ["case", I.case, "Case", "Copy it as UPPER · lower · Title · Sentence"]);
    pop.innerHTML = acts.map(([a, svg, lb, tt], i) =>
      `${i === 1 ? '<span class="sb-sep"></span>' : ""}<button type="button" class="sb-c sb-${a}" data-a="${a}" title="${esc(tt)}" style="--d:${i * 22}ms">${svg}<span>${esc(lb)}</span></button>`).join("");
    card.classList.remove("on");
    pop.classList.remove("on");
    void pop.offsetWidth;
    place(r);
    pop.classList.add("on");
    open = true;
    say(`selection settled · ${text.length} chars · ${kind}`);
  }

  async function stream(el: HTMLElement, html: string) {
    const words = html.split(/(\s+)/);
    el.innerHTML = '<span class="caret"></span>';
    let out = "";
    for (const w of words) {
      if (!open) return;
      out += w;
      el.innerHTML = out + '<span class="caret"></span>';
      if (!reduced) await sleep(w.trim() ? 26 : 0);
    }
    el.innerHTML = out;
  }

  function act(a: string, btn: HTMLElement) {
    touched = true;
    if (a === "ask") {
      card.innerHTML = `<div class="sb-ch">${I.ask}<b>Claude</b><span>sonnet · text only</span></div><div class="sb-cb"></div>`;
      card.classList.add("on");
      say("Ask: the text goes to claude -p on stdin; the card opens where the bar was");
      stream(card.querySelector(".sb-cb")!, answer(text, kind));
    } else if (a === "translate") {
      const tr = TR[text.toLowerCase()] ?? null;
      card.innerHTML = `<div class="sb-ch">${I.translate}<b>Translate</b><span>auto → en · opens in the browser</span></div><div class="sb-cb">${tr ? esc(tr) : `<span class="dim">Opens <code>translate.google.com</code> with “${esc(text.slice(0, 60))}${text.length > 60 ? "…" : ""}”. Try the Spanish comment at the bottom.</span>`}</div>`;
      card.classList.add("on");
      say("Translate: selbar.translateUrl, auto → selbar.translateTo");
    } else if (a === "copy" || a === "calc") {
      const v = a === "calc" ? String(calc(text)) : text;
      navigator.clipboard?.writeText(v).catch(() => {});
      flash(btn, a === "calc" ? `Copied ${fmt(+v)}` : "Copied");
      say(a === "calc" ? "= result: copied" : "Copy: primary → clipboard (wl-copy)");
    } else if (a === "case") {
      caseI = (caseI + 1) % CASES.length;
      const v = recase(text, caseI);
      navigator.clipboard?.writeText(v).catch(() => {});
      btn.querySelector("span")!.textContent = CASES[caseI];
      card.innerHTML = `<div class="sb-ch">${I.case}<b>${CASES[caseI]}</b><span>copied · click again to cycle</span></div><div class="sb-cb mono">${esc(v.slice(0, 160))}</div>`;
      card.classList.add("on");
      say(`Case: copied as ${CASES[caseI]}`);
    } else if (a === "search") {
      toast(`Searches the web for “${text.slice(0, 40)}${text.length > 40 ? "…" : ""}”`);
      say("Search: selbar.searchUrl (the launcher's web engine)");
      hide();
    } else if (a === "link") {
      const u = /^https?:/.test(text) ? text : `https://${text}`;
      toast(`Opens ${u.replace(/^https?:\/\//, "").split("/")[0]} in the browser`);
      say(`Open link: xdg-open ${u}`);
      hide();
    } else if (a === "shelf") {
      toast("Parked on the drop shelf, at the right edge");
      say("Shelf: nox shelf add - (the text, on stdin)");
      hide();
    }
  }
  function flash(btn: HTMLElement, label: string) {
    const s = btn.querySelector("span")!;
    const old = s.textContent;
    btn.classList.add("ok");
    s.textContent = label;
    setTimeout(() => { btn.classList.remove("ok"); s.textContent = old; }, 1300);
  }

  pop.addEventListener("pointerdown", (e) => e.preventDefault()); // keep the selection
  pop.addEventListener("click", (e) => {
    const b = (e.target as HTMLElement).closest<HTMLElement>("[data-a]");
    if (b) act(b.dataset.a!, b);
  });

  function check() {
    const s = getSelection();
    if (!s || s.isCollapsed || !s.rangeCount) { if (open && !card.matches(":hover")) hide(); return; }
    const r = s.getRangeAt(0);
    if (!doc.contains(r.commonAncestorContainer)) return;
    const t = s.toString();
    if (t.trim().length < 2) return;
    show(t, r.getBoundingClientRect());
  }
  // settle like the real one: wait until the pointer is still and the selection stops changing
  document.addEventListener("selectionchange", () => {
    clearTimeout(settle);
    settle = window.setTimeout(check, 260);
  });
  doc.addEventListener("pointerdown", () => { touched = true; hide(); });
  root.addEventListener("keydown", (e) => { if (e.key === "Escape" && open) { hide(); say("Esc dismissed it"); } });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && open) hide(); });

  // one demonstration: select the maths, then the Spanish comment and translate it
  function select(el: Element) {
    const s = getSelection();
    if (!s) return;
    const r = document.createRange();
    r.selectNodeContents(el);
    s.removeAllRanges();
    s.addRange(r);
  }
  let played = false;
  visibility(root, async (on) => {
    if (!on || played) return;
    played = true;
    await sleep(1400);
    const visible = () => { const r = root.getBoundingClientRect(); return r.top < innerHeight && r.bottom > 0; };
    if (touched || !visible()) return;
    select(doc.querySelector(".sb-m")!);
    await sleep(1900);
    if (touched || !visible()) return;
    select(doc.querySelector(".sb-es")!);
    await sleep(1100);
    if (touched || !open) return;
    const b = pop.querySelector<HTMLElement>('[data-a="translate"]');
    if (b) act("translate", b);
    touched = false;
  });
}

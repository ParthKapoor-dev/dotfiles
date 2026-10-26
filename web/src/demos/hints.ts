// Hint mode (Super+;): home-row labels on everything you can click; type the two letters to click it.
// Real one: an AT-SPI walk on demand (capped at 300 elements / 250 ms), pressed through the element's own action.
import { h, esc, reduced, sleep, toast, visibility } from "../util";

const KEYS = "asdfjkl;";
// pairs of different keys first, doubles last, like modules/hints/HintCodes.js
const LABELS = (() => { const o: string[] = [], d: string[] = []; for (const a of KEYS) for (const b of KEYS) (a === b ? d : o).push(a + b); return o.concat(d); })();

export function initHints(root: HTMLElement) {
  root.innerHTML = "";
  const bar = h("div.d-bar", null, h("span.sq"), "Hint mode", h("span.sp"), h("span.hint", { html: "Super ;" }));
  const screen = h("div.hk-screen", { tabindex: "0", "aria-label": "Hint mode demo. Press ; to show labels, then type two letters." });
  const win = h("div.hk-win", { html: `
    <div class="hk-tb"><i></i><i></i><i></i>
      <div class="hk-tabs"><button class="hk-tab on" data-tab="0">Inbox</button><button class="hk-tab" data-tab="1">Review</button><button class="hk-tab" data-tab="2">Done</button></div>
      <button class="hk-ib" data-act="search" aria-label="Search"><svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5L14 14"/></svg></button><button class="hk-ib" data-act="new" aria-label="New task"><svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"><path d="M8 3v10M3 8h10"/></svg></button>
    </div>
    <div class="hk-body">
      <nav class="hk-side">
        <button data-side="0" class="on">Today</button><button data-side="1">Upcoming</button><button data-side="2">Projects</button><button data-side="3">Archive</button>
      </nav>
      <div class="hk-main">
        <label class="hk-row"><input type="checkbox" checked><span>Ship the island card</span><em>bar</em></label>
        <label class="hk-row"><input type="checkbox"><span>Hot corner: show desktop</span><em>shell</em></label>
        <label class="hk-row"><input type="checkbox"><span>Selection bar: ignore terminals</span><em>selbar</em></label>
        <label class="hk-row"><input type="checkbox"><span>Dock: Downloads stack fan</span><em>dock</em></label>
        <div class="hk-foot"><a href="#keys" data-act="link">All keybinds</a><button class="chip" data-act="archive">Archive done</button><button class="chip hot" data-act="sync">Sync</button></div>
      </div>
    </div>` });
  const layer = h("div.hk-layer", { "aria-hidden": "true" });
  const pill = h("div.hk-pill", { html: '<span class="hk-buf"></span><span class="hk-n"></span><span class="hk-esc">ESC cancels</span>' });
  const btn = h("button.chip.hk-go", { type: "button", html: "<kbd>;</kbd> Show labels" });
  screen.append(win, layer, pill, btn);
  root.append(bar, screen);

  type It = { el: HTMLElement; label: string; chip: HTMLElement };
  let items: It[] = [];
  let on = false;
  let buf = "";
  let touched = false;

  const sel = "button, a, input, .hk-row";
  function collect() {
    const sr = screen.getBoundingClientRect();
    const seen = new Set<Element>();
    const els = Array.from(win.querySelectorAll<HTMLElement>(sel)).filter((e) => {
      // a label row and its checkbox are one target: the row
      if (e.tagName === "INPUT") return false;
      if (seen.has(e)) return false;
      seen.add(e);
      const r = e.getBoundingClientRect();
      return r.width > 4 && r.height > 4;
    });
    return els.map((el, i) => {
      const r = el.getBoundingClientRect();
      const chip = h("span.hk-chip", { html: `<b></b><span>${esc(LABELS[i].toUpperCase())}</span>` });
      chip.style.left = `${Math.max(2, r.left - sr.left - 10).toFixed(0)}px`;
      chip.style.top = `${(r.top - sr.top + r.height / 2).toFixed(0)}px`;
      chip.style.setProperty("--d", `${i * 12}ms`);
      return { el, label: LABELS[i], chip };
    });
  }
  function open(focus = true) {
    if (on) return;
    on = true;
    buf = "";
    const t0 = performance.now();
    items = collect();
    layer.innerHTML = "";
    items.forEach((it) => layer.append(it.chip));
    screen.classList.add("hk-on");
    pill.querySelector(".hk-n")!.textContent = `${items.length} targets · ${Math.max(1, Math.round(performance.now() - t0 + 2))} ms`;
    sync();
    if (focus) screen.focus({ preventScroll: true });
  }
  function close() {
    if (!on) return;
    on = false;
    screen.classList.remove("hk-on");
    setTimeout(() => { if (!on) layer.innerHTML = ""; }, 200);
  }
  function sync() {
    pill.querySelector(".hk-buf")!.textContent = buf ? buf.toUpperCase() : "Type a label";
    for (const it of items) {
      const m = it.label.startsWith(buf);
      it.chip.classList.toggle("dim", !m);
      (it.chip.querySelector("b") as HTMLElement).textContent = m ? buf.toUpperCase() : "";
      (it.chip.querySelector("span") as HTMLElement).textContent = m ? it.label.slice(buf.length).toUpperCase() : it.label.toUpperCase();
    }
  }
  function press(k: string) {
    const nb = buf + k;
    if (!items.some((i) => i.label.startsWith(nb))) { pill.classList.remove("shake"); void pill.offsetWidth; pill.classList.add("shake"); return; }
    buf = nb;
    const hit = items.find((i) => i.label === buf);
    sync();
    if (hit) { hit.chip.classList.add("hit"); setTimeout(() => { close(); fire(hit.el); }, reduced ? 0 : 160); }
  }
  function fire(el: HTMLElement) {
    el.classList.add("hk-flash");
    setTimeout(() => el.classList.remove("hk-flash"), 500);
    if (el.classList.contains("hk-row")) { const c = el.querySelector("input") as HTMLInputElement; c.checked = !c.checked; return; }
    if (el.dataset.tab) { win.querySelectorAll(".hk-tab").forEach((t) => t.classList.toggle("on", t === el)); return; }
    if (el.dataset.side) { win.querySelectorAll("[data-side]").forEach((t) => t.classList.toggle("on", t === el)); return; }
    const a = el.dataset.act;
    if (a === "link") { toast("Pressed the link through its own action, no pointer moved"); return; }
    toast(({ search: "Search opened", new: "New task", archive: "Archived the done tasks", sync: "Synced" } as Record<string, string>)[a || ""] || "Clicked");
  }

  function key(e: KeyboardEvent) {
    if (!on) {
      if (e.key === ";" && !e.ctrlKey && !e.altKey) { e.preventDefault(); touched = true; open(); }
      return;
    }
    if (e.key === "Escape") { e.preventDefault(); close(); return; }
    if (e.key === "Backspace") { e.preventDefault(); buf = buf.slice(0, -1); sync(); return; }
    const k = e.key.toLowerCase();
    if (KEYS.includes(k) && k.length === 1) { e.preventDefault(); press(k); }
  }
  screen.addEventListener("keydown", key);
  btn.addEventListener("click", () => { touched = true; if (on) close(); else open(); });
  // clicking a chip works too (and is the only way on a phone)
  layer.addEventListener("click", (e) => {
    const c = (e.target as HTMLElement).closest(".hk-chip");
    const it = items.find((i) => i.chip === c);
    if (it) { touched = true; buf = it.label; sync(); it.chip.classList.add("hit"); setTimeout(() => { close(); fire(it.el); }, 160); }
  });
  win.addEventListener("click", (e) => { const t = e.target as HTMLElement; if (t.closest("a")) e.preventDefault(); const b = t.closest<HTMLElement>("[data-tab],[data-side],[data-act]"); if (b && !on) { touched = true; fire(b); } });
  new ResizeObserver(() => { if (on) { close(); } }).observe(screen);

  let played = false;
  visibility(root, async (v) => {
    if (!v || played) return;
    played = true;
    await sleep(1500);
    if (touched) return;
    open(false);
    // type the label of "Review"
    const target = items.find((i) => i.el.dataset.tab === "1");
    if (!target) return;
    await sleep(1300);
    if (touched || !on) return;
    press(target.label[0]);
    await sleep(650);
    if (touched || !on) return;
    press(target.label[1]);
  });
}

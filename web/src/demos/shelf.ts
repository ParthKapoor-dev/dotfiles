// Drop shelf: drag files from a Dolphin window to the right edge, then out into another app. Pointer events, so touch works.
import { h, esc, reduced, sleep, visibility } from "../util";

type F = { id: string; name: string; kind: string; label: string; cli: string };
const FILES: F[] = [
  { id: "a", name: "plan.pdf", kind: "pdf", label: "PDF", cli: "~/Downloads/plan.pdf" },
  { id: "b", name: "red-fog.png", kind: "img", label: "PNG", cli: "~/Pictures/red-fog.png" },
  { id: "c", name: "notes.md", kind: "md", label: "MD", cli: "~/Notes/notes.md" },
  { id: "d", name: "build.zip", kind: "zip", label: "ZIP", cli: "~/Downloads/build.zip" },
  { id: "e", name: "dotfiles", kind: "url", label: "URL", cli: "https://github.com/ParthKapoor-dev/dotfiles" },
  { id: "f", name: "snippet.txt", kind: "txt", label: "TXT", cli: "-" },
];

export function initShelf(root: HTMLElement) {
  root.innerHTML = "";
  const bar = h("div.d-bar", null, h("span.sq"), "Drop shelf", h("span.sp"), h("span.hint", { text: "Super Shift D" }));
  const screen = h("div.sh-screen");
  const files = h("div.sh-win.sh-files", null, h("div.wt", { html: "<i></i><i></i><i></i><span>dolphin · ~/Downloads</span>" }));
  const grid = h("div.sh-grid");
  files.append(grid);
  const app = h("div.sh-win.sh-app", null, h("div.wt", { html: "<i></i><i></i><i></i><span>zed · ~/code/web</span>" }), h("div.drop", { text: "drop here" }));
  const panel = h("div.sh-panel", { "aria-label": "Shelf" });
  const head = h("h4", null, h("span", { text: "SHELF" }));
  const undo = h("button", { type: "button", text: "UNDO" });
  head.append(undo);
  const items = h("div", { style: { display: "flex", flexDirection: "column", gap: "6px" } });
  const empty = h("p.sh-empty", { html: "Drag anything here.<br>It waits 24 h." });
  panel.append(head, items, empty);
  const help = h("span.hint.sh-help", { text: "drag a file to the right edge" });
  const cli = h("div.sh-cli", { html: "<span>$</span> nox shelf list" });
  screen.append(files, app, panel, help, cli);
  root.append(bar, screen);

  const fi = (f: F) => `<span class="fi ${f.kind}">${f.label}</span>`;
  for (const f of FILES) grid.append(h("div.file", { "data-id": f.id, html: `${fi(f)}<span>${esc(f.name)}</span>` }));

  let shelf: F[] = [];
  let grave: F[][] = [];
  let touched = false;
  let closeT = 0;

  const say = (cmd: string) => { cli.innerHTML = `<span>$</span> ${esc(cmd)}`; };

  function renderShelf() {
    items.innerHTML = "";
    for (const f of shelf) {
      items.append(h("div.sh-item", { "data-id": f.id, html: `${fi(f)}<div><b>${esc(f.name)}</b><small>${f.kind === "url" ? "LINK" : f.kind === "txt" ? "TEXT" : "FILE"} · 24 H LEFT</small></div>` }));
    }
    empty.style.display = shelf.length ? "none" : "";
    undo.style.visibility = grave.length ? "visible" : "hidden";
    grid.querySelectorAll<HTMLElement>(".file").forEach((el) => el.classList.toggle("ghosted", shelf.some((s) => s.id === el.dataset.id)));
  }
  function openPanel(on: boolean) {
    clearTimeout(closeT);
    if (on) panel.classList.add("open");
    else closeT = window.setTimeout(() => { if (!shelf.length) panel.classList.remove("open"); }, 1400);
  }
  undo.addEventListener("click", () => {
    const g = grave.pop();
    if (g) { shelf.push(...g.filter((f) => !shelf.some((s) => s.id === f.id))); renderShelf(); say("nox shelf undo"); }
  });
  panel.addEventListener("click", (e) => { if (e.target === panel) panel.classList.toggle("open"); });

  const inside = (el: Element, x: number, y: number, pad = 0) => {
    const r = el.getBoundingClientRect();
    return x >= r.left - pad && x <= r.right + pad && y >= r.top - pad && y <= r.bottom + pad;
  };
  const edgeHit = (x: number, y: number) => {
    const sr = screen.getBoundingClientRect();
    return inside(panel, x, y, 8) || (x > sr.right - 40 && y > sr.top && y < sr.bottom);
  };

  function drop(f: F, from: "files" | "shelf", x: number, y: number) {
    if (from === "files" && edgeHit(x, y)) {
      if (!shelf.some((s) => s.id === f.id)) shelf.push(f);
      renderShelf();
      say(f.cli === "-" ? "echo … | nox shelf add -" : `nox shelf add ${f.cli}`);
    } else if (from === "shelf" && inside(app, x, y)) {
      shelf = shelf.filter((s) => s.id !== f.id);
      grave.push([f]);
      const d = app.querySelector(".drop")!;
      if (d.textContent === "drop here") d.textContent = "";
      d.append(h("span.got", { html: `${fi(f).replace("fi ", "fi ")}${esc(f.name)}` }));
      d.querySelectorAll(".got .fi").forEach((n) => ((n as HTMLElement).style.cssText = "width:14px;height:16px;font-size:0;border-radius:2px 4px 2px 2px"));
      renderShelf();
      say("dragged out: left the shelf (shelf.moveOut) · nox shelf undo");
    }
    app.classList.remove("target");
    panel.classList.remove("hover");
    openPanel(shelf.length > 0);
  }

  function startDrag(e: PointerEvent, el: HTMLElement, f: F, from: "files" | "shelf") {
    e.preventDefault();
    touched = true;
    const ghost = h("div.drag-ghost", { html: from === "files" ? el.innerHTML : `<div class="sh-item">${el.innerHTML}</div>` });
    if (from === "files") ghost.className = "drag-ghost file";
    document.body.append(ghost);
    const move = (ev: PointerEvent) => {
      ghost.style.left = `${ev.clientX}px`; ghost.style.top = `${ev.clientY}px`;
      if (from === "files") panel.classList.toggle("hover", edgeHit(ev.clientX, ev.clientY));
      else app.classList.toggle("target", inside(app, ev.clientX, ev.clientY));
    };
    move(e);
    if (from === "files") openPanel(true);
    const upf = (ev: PointerEvent) => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", upf);
      window.removeEventListener("pointercancel", upf);
      ghost.remove();
      drop(f, from, ev.clientX, ev.clientY);
    };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", upf);
    window.addEventListener("pointercancel", upf);
  }

  grid.addEventListener("pointerdown", (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>(".file");
    if (!el) return;
    startDrag(e, el, FILES.find((f) => f.id === el.dataset.id)!, "files");
  });
  items.addEventListener("pointerdown", (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>(".sh-item");
    if (!el) return;
    startDrag(e, el, FILES.find((f) => f.id === el.dataset.id)!, "shelf");
  });
  renderShelf();

  // one demonstration drag, then hand over
  async function ghostDrag(f: F, fromEl: HTMLElement, to: () => DOMRect) {
    const a = fromEl.getBoundingClientRect();
    const g = h("div.drag-ghost.file", { html: fromEl.innerHTML });
    document.body.append(g);
    openPanel(true);
    const x0 = a.left + a.width / 2, y0 = a.top + a.height / 2;
    const N = reduced ? 1 : 40;
    for (let i = 0; i <= N; i++) {
      if (touched) { g.remove(); return false; }
      const b = to();
      const x1 = b.left + b.width / 2, y1 = b.top + 30;
      const k = i / N, e = k < 0.5 ? 2 * k * k : 1 - Math.pow(-2 * k + 2, 2) / 2;
      g.style.left = `${x0 + (x1 - x0) * e}px`; g.style.top = `${y0 + (y1 - y0) * e - Math.sin(k * Math.PI) * 30}px`;
      panel.classList.toggle("hover", k > 0.8);
      await sleep(16);
    }
    g.remove();
    return true;
  }
  let played = false;
  visibility(root, async (on) => {
    if (!on || played) return;
    played = true;
    await sleep(1300);
    if (touched) return;
    const el = grid.querySelector<HTMLElement>('[data-id="a"]')!;
    if (await ghostDrag(FILES[0], el, () => panel.getBoundingClientRect())) {
      shelf.push(FILES[0]); renderShelf(); panel.classList.remove("hover"); say("nox shelf add ~/Downloads/plan.pdf");
    }
  });
}

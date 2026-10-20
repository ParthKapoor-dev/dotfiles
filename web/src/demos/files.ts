// Dolphin with the nox right-click menu (base0/dolphin servicemenus -> nox files ...).
import { h, esc, toast, visibility } from "../util";

type F = { name: string; kind: string; label: string; img?: string };
const FILES: F[] = [
  { name: "red-fog.png", kind: "img", label: "PNG", img: "radial-gradient(60% 50% at 50% 60%, #ff3b1f, #2a0806 70%)" },
  { name: "ronin.jpg", kind: "img", label: "JPG", img: "linear-gradient(160deg, #3a3a3a, #050505)" },
  { name: "signal-grid.png", kind: "img", label: "PNG", img: "repeating-radial-gradient(circle at 30% 70%, #6f3128 0 2px, #0a0a0a 2px 6px)" },
  { name: "whiteboard.jpg", kind: "img", label: "JPG", img: "linear-gradient(160deg, #e7e3df, #9a9690)" },
  { name: "plan.pdf", kind: "pdf", label: "PDF" },
  { name: "notes.md", kind: "md", label: "MD" },
  { name: "build.zip", kind: "zip", label: "ZIP" },
  { name: "todo.txt", kind: "txt", label: "TXT" },
];

const FILE_ACTS: [string, string][] = [
  ["Open in Zed", "Opened in Zed"],
  ["Open in Neovim", "Opened in Neovim (Ghostty)"],
  ["Terminal here", "kitty opened in ~/Pictures"],
  ["Copy path", "Path copied"],
  ["Send to Shelf", "Parked on the shelf (nox shelf add)"],
  ["Send to phone", "Sent to phone (nox phone send)"],
];
const IMG_ACTS: [string, string][] = [
  ["Set as wallpaper", "Wallpaper set (nox wallpaper set)"],
  ["Annotate", "Opened in satty, saved in place"],
  ["Copy text (OCR)", "Text copied (tesseract)"],
  ["Convert to WebP", "Converted to WebP · copy next to the original"],
  ["Convert to PNG", "Converted to PNG"],
  ["Convert to JPEG", "Converted to JPEG"],
  ["Resize to 50%", "Resized to 50% · name-50.ext"],
  ["Remove metadata (EXIF, GPS)", "Metadata removed"],
];

export function initFiles(root: HTMLElement) {
  root.innerHTML = "";
  const bar = h("div.d-bar", null, h("span.sq"), "Dolphin", h("span.sp"), h("span.hint", { text: "right-click a file" }));
  const body = h("div.df-body");
  const side = h("div.df-side", { html: "<small>PLACES</small><span>Home</span><span>Downloads</span><span class=\"on\">Pictures</span><span>Notes</span><span>code</span><small>DEVICES</small><span>Phone</span><span>Trash</span>" });
  const main = h("div.df-main");
  const path = h("div.df-path", { html: "<span>~</span><span>/</span><b>Pictures</b>" });
  const grid = h("div.df-grid");
  for (const [i, f] of FILES.entries()) {
    const ic = f.img ? `<span class="fi img" style="background:${f.img}">${f.label}</span>` : `<span class="fi ${f.kind}">${f.label}</span>`;
    grid.append(h("div.file", { "data-i": String(i), tabindex: "0", role: "button", "aria-label": `${f.name}: open the menu`, html: `${ic}<span>${esc(f.name)}</span>` }));
  }
  const menu = h("div.cmenu", { role: "menu" });
  const sub = h("div.cmenu.sub", { role: "menu" });
  const hint = h("span.hint.df-hint", { text: "right-click or tap a file" });
  main.append(path, grid, menu, hint);
  body.append(side, main);
  root.append(bar, body);

  let current: F | null = null;
  const close = () => { menu.classList.remove("on"); sub.classList.remove("on"); grid.querySelectorAll(".sel").forEach((n) => n.classList.remove("sel")); };

  function open(el: HTMLElement, x: number, y: number) {
    close();
    current = FILES[+el.dataset.i!];
    el.classList.add("sel");
    hint.style.display = "none";
    const isImg = current.kind === "img";
    menu.innerHTML = "";
    const item = (t: string, cls = "") => h("button" + cls, { type: "button", role: "menuitem", text: t, onclick: () => { close(); toast(t === "Open" ? `Opened ${current!.name}` : `${t}…`); } });
    menu.append(item("Open"), item("Open With…", ".muted"), h("hr"));
    const nox = h("div.it", { role: "menuitem", "aria-haspopup": "true", tabindex: "0", html: `<span class="sq"></span>nox` });
    menu.append(nox, h("hr"), item("Copy", ".muted"), item("Rename…", ".muted"), item("Move to Trash", ".muted"));
    sub.innerHTML = "";
    for (const [t, msg] of [...FILE_ACTS, ...(isImg ? IMG_ACTS : [])]) {
      if (t === "Set as wallpaper") sub.append(h("hr"));
      sub.append(h("button", { type: "button", role: "menuitem", text: t, onclick: () => { close(); toast(`${msg} · ${current!.name}`); } }));
    }
    nox.append(sub);
    const showSub = () => { nox.classList.add("open"); sub.classList.add("on"); placeSub(); };
    nox.addEventListener("pointerenter", showSub);
    nox.addEventListener("click", (e) => { e.stopPropagation(); showSub(); });
    nox.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === "ArrowRight") { showSub(); (sub.querySelector("button") as HTMLElement)?.focus(); } });
    menu.querySelectorAll(":scope > button").forEach((b) => b.addEventListener("pointerenter", () => { nox.classList.remove("open"); sub.classList.remove("on"); }));
    // place inside main
    const mr = main.getBoundingClientRect();
    const mw = 200, mh = 220;
    let lx = x - mr.left, ly = y - mr.top;
    // leave room for the nox submenu on the right when the window is wide enough
    const room = mr.width >= mw + 236 + 12 ? mw + 236 : mw;
    lx = Math.max(6, Math.min(lx, mr.width - room - 6));
    ly = Math.max(6, Math.min(ly, mr.height - mh - 6));
    menu.style.left = `${lx}px`; menu.style.top = `${ly}px`;
    menu.classList.add("on");
    return showSub;
  }
  function placeSub() {
    const mr = main.getBoundingClientRect();
    const r = menu.getBoundingClientRect();
    const sw = 230;
    const nr = (sub.parentElement as HTMLElement).getBoundingClientRect();
    if (r.right + sw <= mr.right) sub.style.left = "calc(100% + 2px)";
    else sub.style.left = `${Math.max(mr.left + 6, r.right - sw) - nr.left}px`;
    const sh = sub.offsetHeight;
    let top = r.right + sw > mr.right ? 26 : -5;
    const overflow = nr.top + top + sh - (mr.bottom - 6);
    if (overflow > 0) top -= overflow;
    top = Math.max(top, mr.top + 6 - nr.top);
    sub.style.top = `${top}px`;
  }

  grid.addEventListener("contextmenu", (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>(".file");
    if (!el) return;
    e.preventDefault();
    open(el, e.clientX, e.clientY);
  });
  grid.addEventListener("click", (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>(".file");
    if (!el) return;
    e.stopPropagation();
    const r = el.getBoundingClientRect();
    open(el, r.left + r.width * 0.6, r.top + r.height * 0.7);
  });
  grid.addEventListener("keydown", (e) => {
    const el = (e.target as HTMLElement).closest<HTMLElement>(".file");
    if (el && (e.key === "Enter" || e.key === " " || e.key === "ContextMenu")) { e.preventDefault(); const r = el.getBoundingClientRect(); open(el, r.left + r.width * 0.6, r.top + r.height * 0.7); (menu.querySelector("button") as HTMLElement)?.focus(); }
  });
  root.addEventListener("keydown", (e) => { if (e.key === "Escape") close(); });
  document.addEventListener("pointerdown", (e) => { if (!menu.contains(e.target as Node) && !grid.contains(e.target as Node)) close(); });

  let played = false;
  visibility(root, (on) => {
    if (!on || played) return;
    played = true;
    setTimeout(() => {
      if (menu.classList.contains("on")) return;
      const el = grid.querySelector<HTMLElement>('[data-i="0"]')!;
      const r = el.getBoundingClientRect();
      const showSub = open(el, r.left + r.width * 0.7, r.top + r.height * 0.6);
      setTimeout(() => { if (menu.classList.contains("on")) showSub(); }, 700);
    }, 1200);
  });
}

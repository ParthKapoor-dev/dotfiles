export const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

export const $ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => root.querySelector(sel) as T;
export const $$ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = document) => Array.from(root.querySelectorAll(sel)) as T[];

/** Tiny element builder: h("div.cls.cls2", {attr}, children) */
export function h<T extends HTMLElement = HTMLElement>(
  tag: string,
  attrs: Record<string, any> | null = null,
  ...children: (Node | string | null | undefined | false)[]
): T {
  const [name, ...cls] = tag.split(".");
  const el = document.createElement(name || "div") as T;
  if (cls.length) el.className = cls.join(" ");
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === "html") el.innerHTML = v;
      else if (k === "text") el.textContent = v;
      else if (k.startsWith("on") && typeof v === "function") el.addEventListener(k.slice(2), v);
      else if (k === "style" && typeof v === "object") {
        for (const [sk, sv] of Object.entries(v)) {
          if (sk.startsWith("--")) el.style.setProperty(sk, String(sv));
          else (el.style as any)[sk] = sv;
        }
      }
      else el.setAttribute(k, v === true ? "" : String(v));
    }
  }
  for (const c of children) if (c != null && c !== false) el.append(c as Node | string);
  return el;
}

export const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

/** Run cb once when el comes near the viewport. */
export function whenNear(el: Element, cb: () => void, margin = "300px") {
  const io = new IntersectionObserver((es) => {
    if (es.some((e) => e.isIntersecting)) { io.disconnect(); cb(); }
  }, { rootMargin: margin });
  io.observe(el);
}

/** Track visibility (for pausing animation loops). */
export function visibility(el: Element, cb: (on: boolean) => void) {
  const io = new IntersectionObserver((es) => cb(es[es.length - 1].isIntersecting), { rootMargin: "100px" });
  io.observe(el);
  return io;
}

let toastTimer = 0;
export function toast(msg: string) {
  const t = document.getElementById("toast")!;
  t.innerHTML = `<span class="sq"></span><span></span>`;
  (t.lastChild as HTMLElement).textContent = msg;
  t.classList.add("on");
  clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => t.classList.remove("on"), 2600);
}

export const esc = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);

export const ICON = {
  copy: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="5" y="5" width="8.5" height="8.5" rx="1.5"/><path d="M3 10.5V3.5A1 1 0 0 1 4 2.5h6.5"/></svg>',
  sparkle: '<svg viewBox="0 0 16 16" fill="currentColor"><path d="M8 1.5l1.4 4.1 4.1 1.4-4.1 1.4L8 12.5 6.6 8.4 2.5 7l4.1-1.4z"/></svg>',
  send: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"><path d="M2 8l11.5-5.5L9 14l-1.6-4.6z"/></svg>',
  translate: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><path d="M2 3.5h7M5.5 2v1.5M3.5 3.5c.5 2.5 2.5 4.5 5 5.5M7.5 3.5c-.5 2.5-2.5 4.5-5 5.5M9 14l2.5-6 2.5 6M9.8 12h3.4"/></svg>',
  table: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="2" y="2.5" width="12" height="11" rx="1.5"/><path d="M2 6.5h12M2 10h12M6.5 6.5v7"/></svg>',
  search: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="7" cy="7" r="4.5"/><path d="M10.5 10.5L14 14"/></svg>',
  check: '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M3 8.5l3.2 3L13 4.5"/></svg>',
  mic: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"><rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/></svg>',
};

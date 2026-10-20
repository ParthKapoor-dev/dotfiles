// "Try the whole desktop": click-to-start iframe of /desktop/?embed=1 and demo buttons over postMessage.
// Contract: the page posts {nox:'ready', demos:[...]} when loaded and {nox:'demo', name, ok} after each demo;
// we send {nox:'demo', name}.
import { $, $$, toast } from "./util";

export function initTry() {
  const screen = $(".try-screen");
  const start = $("#try-start");
  const buttons = $$<HTMLButtonElement>("#try-demos button");
  let frame: HTMLIFrameElement | null = null;
  let ready = false;
  let queued: string | null = null;
  let fallback = 0;

  function boot() {
    if (frame) return;
    frame = document.createElement("iframe");
    frame.src = "/desktop/?embed=1";
    frame.title = "nox desktop, interactive model";
    frame.allow = "microphone; clipboard-write; fullscreen";
    frame.setAttribute("allowfullscreen", "");
    screen.append(frame);
    start.querySelector(".try-label")!.textContent = "Starting…";
    frame.addEventListener("load", () => {
      // if the page never says ready (older build), show it anyway
      fallback = window.setTimeout(() => { if (!ready) show(); }, 2500);
    });
  }
  function show() {
    frame?.classList.add("on");
    start.classList.add("gone");
  }
  function send(name: string) {
    frame?.contentWindow?.postMessage({ nox: "demo", name }, "*");
    buttons.forEach((b) => b.classList.toggle("on", b.dataset.demo === name && name !== "reset"));
  }

  window.addEventListener("message", (e) => {
    if (!frame || e.source !== frame.contentWindow) return;
    const d = e.data;
    if (!d || typeof d !== "object") return;
    if (d.nox === "ready") {
      ready = true;
      clearTimeout(fallback);
      show();
      if (Array.isArray(d.demos)) {
        const ok = new Set<string>(d.demos);
        buttons.forEach((b) => { const has = b.dataset.demo === "reset" || ok.has(b.dataset.demo!); b.hidden = !has; });
      }
      if (queued) { send(queued); queued = null; }
    } else if (d.nox === "demo" && d.ok === false) {
      toast(`That part is not in the model yet: ${d.name}`);
    }
  });

  start.addEventListener("click", boot);
  for (const b of buttons) {
    b.addEventListener("click", () => {
      const name = b.dataset.demo!;
      if (!frame) { boot(); queued = name; buttons.forEach((x) => x.classList.toggle("on", x === b)); }
      else if (!ready) queued = name;
      else send(name);
      // bring the frame into view on small screens
      const r = screen.getBoundingClientRect();
      if (r.bottom < 0 || r.top > innerHeight * 0.6) screen.scrollIntoView({ block: "center" });
    });
  }
}

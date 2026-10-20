// Phone link: KDE Connect run-command buttons and the Remote Input touchpad, acting on a tiny laptop.
import { h, toast } from "../util";

export function initPhone(root: HTMLElement) {
  root.innerHTML = "";
  const laptop = h("div.ph-laptop");
  const scr = h("div.ph-screen");
  scr.innerHTML = `
    <div class="ph-bar"><span>■ nox</span><span class="sp"></span><span class="pp">PHONE 41%</span><span class="clk">13:58</span></div>
    <div class="ph-desk"><div class="ph-win"></div><div class="ph-note"><b>New note</b>Started from the phone. Saved to ~/Notes.</div><div class="ph-media"><i></i><span>NOW PLAYING</span></div></div>
    <div class="ph-shotcard"></div>
    <div class="ph-cursor"><svg viewBox="0 0 12 12"><path d="M1 1l9 4-4 1.2L4.6 10z" fill="#fff" stroke="#000" stroke-width=".6"/></svg></div>
    <div class="ph-lock"><b>13:58</b><span>LOCKED FROM YOUR PHONE</span></div>
    <div class="ph-sleep"></div><div class="ph-flash"></div>`;
  laptop.append(scr, h("div.ph-base"));

  const phone = h("div.phone");
  const inn = h("div.phone-in");
  const top = h("div.phone-top", { html: "<span>13:58</span><i></i><span>41%</span>" });
  const app = h("div.phone-app");
  const title = h("h4", { html: "nox-laptop<small>Connected · KDE Connect</small>" });
  const tabs = h("div.ph-tabs", { role: "tablist" });
  const tCmd = h("button.on", { type: "button", role: "tab", "aria-selected": "true", text: "Run command" });
  const tPad = h("button", { type: "button", role: "tab", "aria-selected": "false", text: "Remote input" });
  tabs.append(tCmd, tPad);
  const cmds = h("div.ph-cmds");
  const pad = h("div.ph-pad", { html: "drag to move<br>the laptop's pointer<br>tap to click", style: { display: "none" } });
  const patch = h("div.ph-patch", { text: "remote input: local kdeconnect-rs patch", style: { display: "none" } });
  app.append(title, tabs, cmds, pad, patch);
  inn.append(top, app);
  phone.append(inn);
  root.append(laptop, phone);

  const $ = (s: string) => scr.querySelector(s) as HTMLElement;
  const lock = $(".ph-lock"), sleepEl = $(".ph-sleep"), flash = $(".ph-flash"), shot = $(".ph-shotcard"), note = $(".ph-note"), media = $(".ph-media"), cursor = $(".ph-cursor");

  const CMDS: [string, string, () => void][] = [
    ["Lock", "loginctl lock-session", () => { lock.classList.add("on"); setTimeout(() => lock.classList.remove("on"), 2600); }],
    ["Sleep", "systemctl suspend", () => { sleepEl.classList.add("on"); setTimeout(() => sleepEl.classList.remove("on"), 2200); }],
    ["Screenshot", "nox shot screen", () => { flash.classList.remove("go"); void flash.offsetWidth; flash.classList.add("go"); shot.classList.add("on"); setTimeout(() => shot.classList.remove("on"), 3000); }],
    ["New note", "nox notes new", () => { note.classList.toggle("on"); }],
    ["Pause all media", "playerctl -a pause", () => { const p = media.classList.toggle("paused"); media.querySelector("span")!.textContent = p ? "PAUSED" : "NOW PLAYING"; }],
  ];
  for (const [name, cmd, fn] of CMDS) {
    cmds.append(h("button", { type: "button", html: `<i></i>${name}`, onclick: () => { fn(); toast(`Phone ran “${name}”: ${cmd}`); } }));
  }
  const setTab = (p: boolean) => {
    tCmd.classList.toggle("on", !p); tPad.classList.toggle("on", p);
    tCmd.setAttribute("aria-selected", String(!p)); tPad.setAttribute("aria-selected", String(p));
    cmds.style.display = p ? "none" : ""; pad.style.display = p ? "" : "none"; patch.style.display = p ? "" : "none";
  };
  tCmd.addEventListener("click", () => setTab(false));
  tPad.addEventListener("click", () => setTab(true));

  // remote input
  let cx = 0.5, cy = 0.5, last: { x: number; y: number } | null = null, moved = 0;
  const place = () => { cursor.style.transform = `translate(${(cx - 0.5) * scr.clientWidth}px, ${(cy - 0.5) * scr.clientHeight}px)`; };
  pad.addEventListener("pointerdown", (e) => { pad.setPointerCapture(e.pointerId); last = { x: e.clientX, y: e.clientY }; moved = 0; pad.classList.add("act"); });
  pad.addEventListener("pointermove", (e) => {
    if (!last) return;
    const dx = e.clientX - last.x, dy = e.clientY - last.y;
    moved += Math.abs(dx) + Math.abs(dy);
    cx = Math.min(0.98, Math.max(0.02, cx + dx / 160)); cy = Math.min(0.96, Math.max(0.04, cy + dy / 130));
    last = { x: e.clientX, y: e.clientY };
    place();
  });
  const end = () => {
    if (last && moved < 4) { cursor.animate([{ scale: "1" }, { scale: "0.7" }, { scale: "1" }], { duration: 220 }); }
    last = null; pad.classList.remove("act");
  };
  pad.addEventListener("pointerup", end);
  pad.addEventListener("pointercancel", end);
  new ResizeObserver(place).observe(scr);
}

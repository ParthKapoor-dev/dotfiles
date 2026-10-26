import "./style.css";
import Lenis from "lenis";
import { gsap } from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { $, $$, reduced, whenNear, toast } from "./util";
import { initHero } from "./hero";
import { initAsk } from "./demos/ask";
import { initVoice } from "./demos/voice";
import { initAgents, initUsage } from "./demos/agents";
import { initLauncher } from "./demos/launcher";
import { initShelf } from "./demos/shelf";
import { initPhone } from "./demos/phone";
import { initTheme } from "./demos/theme";
import { initFiles } from "./demos/files";
import { initTerminal } from "./demos/terminal";
import { initKeys } from "./demos/keys";
import { initSelbar } from "./demos/selbar";
import { initIsland } from "./demos/island";
import { initHints } from "./demos/hints";
import { initCorners, initFolder, initStack } from "./demos/touches";
import { initDraw } from "./demos/draw";
import { initMission } from "./demos/mission";
import { initTry } from "./try";

document.documentElement.classList.add("js");

// ------------------------------------------------------------ smooth scroll
let lenis: Lenis | null = null;
gsap.registerPlugin(ScrollTrigger);
if (!reduced) {
  lenis = new Lenis({ duration: 1.15, easing: (t) => 1 - Math.pow(1 - t, 4), smoothWheel: true });
  lenis.on("scroll", ScrollTrigger.update);
  gsap.ticker.add((t) => lenis!.raf(t * 1000));
  gsap.ticker.lagSmoothing(0);
}
const BAR_H = 34;
document.addEventListener("click", (e) => {
  const a = (e.target as HTMLElement).closest<HTMLAnchorElement>('a[href^="#"]');
  if (!a) return;
  const id = a.getAttribute("href")!;
  const el = id === "#top" ? document.body : document.querySelector(id);
  if (!el) return;
  e.preventDefault();
  if (lenis) lenis.scrollTo(el as HTMLElement, { offset: id === "#top" ? 0 : -BAR_H + 1, duration: 1.4 });
  else (el as HTMLElement).scrollIntoView();
  history.replaceState(null, "", id === "#top" ? location.pathname : id);
});

// ------------------------------------------------------------ bar: clock, cpu, chapter
const clock = $("#bar-clock");
function tickClock() {
  const d = new Date();
  const day = d.toLocaleDateString("en-GB", { weekday: "short" }).toUpperCase();
  const mon = d.toLocaleDateString("en-GB", { month: "short" }).toUpperCase();
  clock.textContent = `${day} ${d.getDate()} ${mon} ${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
}
tickClock();
setInterval(tickClock, 10000);
const cpuMeter = $("[data-meter=cpu]");
cpuMeter.innerHTML = "<i></i>".repeat(5);
const cpuVal = $("#bar-cpu");
let cpu = 16;
function tickCpu() {
  cpu = Math.max(4, Math.min(64, cpu + (Math.random() - 0.5) * 9));
  cpuVal.textContent = `${Math.round(cpu)}%`;
  Array.from(cpuMeter.children).forEach((c, i) => c.classList.toggle("on", i < Math.ceil(cpu / 20)));
}
tickCpu();
if (!reduced) setInterval(tickCpu, 2200);

const chapterEl = $("#bar-chapter");
const navLinks = $$<HTMLAnchorElement>(".bar-nav a");
for (const sec of $$("[data-chapter]")) {
  ScrollTrigger.create({
    trigger: sec, start: "top 40%", end: "bottom 40%",
    onToggle: (st) => {
      if (!st.isActive) return;
      chapterEl.textContent = sec.dataset.chapter!;
      navLinks.forEach((a) => a.classList.toggle("on", a.getAttribute("href") === `#${sec.id}`));
    },
  });
}

// ------------------------------------------------------------ hero
const hero = initHero($("#hero-canvas") as HTMLCanvasElement);
ScrollTrigger.create({
  trigger: ".hero", start: "top top", end: "bottom top",
  onUpdate: (st) => hero.setProgress(st.progress),
});
if (!reduced) {
  gsap.to(".hero-inner", { yPercent: -12, opacity: 0, ease: "none", scrollTrigger: { trigger: ".hero", start: "top top", end: "bottom 20%", scrub: true } });
  gsap.fromTo("#screen-frame img", { rotateX: 26, scale: 0.86, y: 40 }, {
    rotateX: 0, scale: 1, y: 0, ease: "none",
    scrollTrigger: { trigger: "#screen-frame", start: "top bottom", end: "center 55%", scrub: 0.6 },
  });
}

// ------------------------------------------------------------ titles: split into masked lines
for (const t of $$("[data-split]")) {
  const parts = t.innerHTML.split(/<br\s*\/?>/i);
  t.innerHTML = parts.map((p) => `<span class="ln"><span>${p.trim()}</span></span>`).join("");
  if (reduced) continue;
  gsap.to(t.querySelectorAll(".ln > span"), {
    y: 0, duration: 1.2, ease: "expo.out", stagger: 0.09,
    scrollTrigger: { trigger: t, start: "top 86%", once: true },
  });
}

// ------------------------------------------------------------ reveals
if (!reduced) {
  ScrollTrigger.batch("[data-reveal]", {
    start: "top 90%",
    once: true,
    onEnter: (els) => gsap.to(els, { opacity: 1, y: 0, duration: 1.1, ease: "expo.out", stagger: 0.08, overwrite: true }),
  });
  // stats count up
  for (const b of $$<HTMLElement>(".stat b[data-count]")) {
    const n = +b.dataset.count!;
    const o = { v: 0 };
    b.textContent = "0";
    gsap.to(o, { v: n, duration: 1.6, ease: "power3.out", scrollTrigger: { trigger: b, start: "top 90%", once: true }, onUpdate: () => (b.textContent = String(Math.round(o.v))) });
  }
  // gentle parallax on demos
  for (const d of $$(".chapter-grid .demo")) {
    gsap.fromTo(d, { yPercent: 7 }, { yPercent: -5, ease: "none", scrollTrigger: { trigger: d, start: "top bottom", end: "bottom top", scrub: 0.8 } });
  }
  gsap.fromTo(".outro-word", { scale: 0.86, opacity: 0.2 }, { scale: 1, opacity: 1, ease: "none", scrollTrigger: { trigger: ".outro", start: "top bottom", end: "center center", scrub: 0.6 } });
}

// ------------------------------------------------------------ demos, lazily
const DEMOS: [string, (el: HTMLElement) => void][] = [
  ["#demo-ask", initAsk], ["#demo-voice", initVoice], ["#demo-agents", initAgents], ["#usage-live", initUsage],
  ["#demo-launcher", initLauncher], ["#demo-shelf", initShelf], ["#demo-phone", initPhone], ["#demo-theme", initTheme],
  ["#demo-files", initFiles], ["#demo-term", initTerminal], ["#demo-keys", initKeys],
  ["#demo-selbar", initSelbar], ["#demo-island", initIsland], ["#demo-hints", initHints],
  ["#demo-corners", initCorners], ["#demo-folder", initFolder], ["#demo-stack", initStack],
  ["#demo-draw", initDraw], ["#demo-mission", initMission],
];
for (const [sel, fn] of DEMOS) {
  const el = $(sel);
  if (!el) continue;
  whenNear(el, () => {
    fn(el);
    // inner scrollers keep their wheel events
    el.querySelectorAll(".tm-out, .ask-body, .th-json, .sb-cb").forEach((n) => n.setAttribute("data-lenis-prevent", ""));
    ScrollTrigger.refresh();
  }, "600px");
}
initTry();

// ------------------------------------------------------------ copy install
$("#clone-copy").addEventListener("click", async () => {
  const txt = "git clone https://github.com/ParthKapoor-dev/dotfiles ~/code/dev/dotfiles/base0\ncd ~/code/dev/dotfiles/base0\n./install.sh --dry-run";
  try { await navigator.clipboard.writeText(txt); toast("Copied: clone, cd, dry run"); } catch { toast("Select the text to copy it"); }
  const b = $("#clone-copy");
  b.textContent = "Copied";
  setTimeout(() => (b.textContent = "Copy"), 1800);
});

window.addEventListener("load", () => ScrollTrigger.refresh());

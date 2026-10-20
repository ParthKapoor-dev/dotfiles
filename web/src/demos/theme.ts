// Theme: pick a look or an accent, the mini desktop restyles from tokens, the JSON diff and `nox theme apply` follow.
import { h, reduced, sleep } from "../util";

type Look = {
  name: string; accent: string; bg: string; surface: string; raised: string; rw: number; rc: number;
  font: string; num: string; numw: number; glass: number; blur: number; label: string; labf: string;
  close: string; min: string; zoom: string; on: string; wall?: string;
};
const LOOKS: Record<string, Look> = {
  ember: { name: "ember", accent: "#FF5A1F", bg: "#11100F", surface: "#1B1A19", raised: "#282624", rw: 12, rc: 6, font: "Geist", num: "Geist", numw: 200, glass: 0.78, blur: 6, label: "uppercase", labf: "Geist Mono", close: "#FF5F57", min: "#FEBC2E", zoom: "#28C840", on: "#140803" },
  telemetry: { name: "telemetry", accent: "#FF3B1F", bg: "#0A0A0A", surface: "#141414", raised: "#202020", rw: 4, rc: 3, font: "Geist", num: "Doto", numw: 800, glass: 0.96, blur: 0, label: "uppercase", labf: "Geist Mono", close: "#FF3B1F", min: "#6A6A6A", zoom: "#6A6A6A", on: "#120402" },
  sequoia: { name: "sequoia", accent: "#0A84FF", bg: "#1C1C1E", surface: "#2C2C2E", raised: "#3A3A3C", rw: 12, rc: 6, font: "-apple-system, BlinkMacSystemFont, Geist", num: "-apple-system, Geist", numw: 300, glass: 0.62, blur: 14, label: "none", labf: "Geist", close: "#FF5F57", min: "#FEBC2E", zoom: "#28C840", on: "#ffffff",
    wall: "radial-gradient(80% 70% at 30% 20%, #3a4a6a, transparent 60%), radial-gradient(70% 60% at 80% 90%, #5a3a5a, transparent 60%), #101018" },
  minimal: { name: "minimal", accent: "#FF5A1F", bg: "#11100F", surface: "#1B1A19", raised: "#282624", rw: 8, rc: 5, font: "Geist", num: "Geist", numw: 200, glass: 1, blur: 0, label: "uppercase", labf: "Geist Mono", close: "#FF5F57", min: "#FEBC2E", zoom: "#28C840", on: "#140803" },
};
const SWATCH = ["#FF5A1F", "#FF3B1F", "#8D201B", "#FFC24B", "#3DDC97", "#3FD5E0", "#0A84FF", "#BF5AF2", "#E8E4E0"];
const TARGETS = ["tokens-lua", "hypr-base", "tokens-json", "gtk3", "gtk4", "gtk-settings", "kde-colors", "kde-globals", "dolphin", "dolphin-view", "ghostty", "kitty", "fuzzel", "hyprlock", "hyprlock-layout-flat", "hyprlock-layout-hairline", "btop", "satty-config", "satty-css", "term-sequences"];

export function initTheme(root: HTMLElement) {
  root.innerHTML = "";
  const stage = h("div.th-stage");
  const looks = h("div.th-looks", { role: "radiogroup", "aria-label": "Look" });
  const sw = h("div.th-swatches", null, h("span", { text: "ACCENT" }));
  const radius = h("input", { type: "range", min: "0", max: "20", value: "12", "aria-label": "Window radius" }) as HTMLInputElement;
  const mini = h("div.mini", { "aria-hidden": "true" });
  mini.innerHTML = `
    <div class="mini-wall"></div>
    <div class="mini-bar"><span class="lg"></span><b>nox</b><span class="ws"><i class="on"></i><i></i><i></i><i></i></span><span class="sp"></span><span>CPU 16%</span><span class="clk">13:58</span></div>
    <div class="mini-win"><div class="tb"><i></i><i></i><i></i></div><pre><b>$</b> nox theme switch <b class="lk">ember</b>
render  20 targets
apply   gtk kde ghostty kitty fuzzel
        btop hyprlock satty
<b>✓</b> shell + Hyprland reload live</pre></div>
    <div class="mini-cc"><div class="lab">Control center</div><div class="row"><span class="t on">Wi-Fi</span><span class="t on">BT</span></div><div class="row"><span class="t">Focus</span><span class="t">Night</span></div><div class="sl"><i></i></div><div class="lab">Battery</div><div class="big">80%</div></div>
    <div class="mini-dock"><i></i><i></i><i></i><i></i><i></i></div>`;
  const code = h("div.th-code");
  const tabs = h("div.th-tabs");
  const json = h("pre.th-json");
  const apply = h("div.th-apply", { "aria-live": "polite" });
  code.append(tabs, json, apply);
  stage.append(looks, sw, mini);
  root.append(stage, code);

  let look = "ember";
  let accent: string | null = null;
  let rw: number | null = null;
  let prev: Record<string, string> = {};

  for (const k of Object.keys(LOOKS)) {
    const L = LOOKS[k];
    looks.append(h("button", { type: "button", role: "radio", "data-k": k, html: `<i style="background:${L.accent}"></i>${k[0].toUpperCase() + k.slice(1)}`, onclick: () => { look = k; accent = null; rw = null; radius.value = String(L.rw); update(true); } }));
  }
  for (const c of SWATCH) sw.append(h("button", { type: "button", "aria-label": `Accent ${c}`, style: { background: c }, "data-c": c, onclick: () => { accent = c; update(true, "accent"); } }));
  sw.append(h("label", null, "radius", radius));
  radius.addEventListener("input", () => { rw = +radius.value; update(false, "radius"); });

  let applyRun = 0;
  async function runApply(cmd: string) {
    const my = ++applyRun;
    apply.innerHTML = `<div><span class="p">$</span> <b>${cmd}</b></div><div class="st">render → ~/.local/state/nox/out</div><div class="tg">${TARGETS.map((t) => `<span>${t}</span>`).join("")}</div><div class="fin"></div>`;
    const spans = apply.querySelectorAll(".tg span");
    for (let i = 0; i < spans.length; i++) {
      if (my !== applyRun) return;
      spans[i].classList.add("on");
      if (!reduced) await sleep(38);
    }
    if (my !== applyRun) return;
    (apply.querySelector(".fin") as HTMLElement).innerHTML = `<span class="ok">✓</span> ${TARGETS.length} targets applied · backup in ~/.local/state/nox/backup · shell + Hyprland read tokens live`;
  }

  function update(doApply: boolean, what?: "accent" | "radius") {
    const L = LOOKS[look];
    const A = accent ?? L.accent;
    const R = rw ?? L.rw;
    const v: Record<string, string> = {
      "--t-accent": A, "--t-bg": L.bg, "--t-surface": L.surface, "--t-raised": L.raised, "--t-r": `${R}px`, "--t-rs": `${L.rc}px`,
      "--t-font": L.font, "--t-num": L.num, "--t-numw": String(L.numw), "--t-glass": String(L.glass), "--t-blur": `${L.blur * 2}px`,
      "--t-label": L.label, "--t-labf": L.labf, "--t-close": L.close, "--t-min": L.min, "--t-zoom": L.zoom, "--t-on": L.on,
    };
    for (const [k, val] of Object.entries(v)) mini.style.setProperty(k, val);
    if (L.wall) mini.style.setProperty("--t-wall", L.wall); else mini.style.removeProperty("--t-wall");
    (mini.querySelector(".mini-wall") as HTMLElement).style.opacity = look === "sequoia" ? "0" : look === "telemetry" ? ".8" : ".5";
    mini.querySelector(".lk")!.textContent = look;
    looks.querySelectorAll("button").forEach((b) => { const on = b.dataset.k === look; b.classList.toggle("on", on); b.setAttribute("aria-checked", String(on)); });
    sw.querySelectorAll<HTMLElement>("button").forEach((b) => b.classList.toggle("on", b.dataset.c?.toLowerCase() === A.toLowerCase()));
    // tokens view
    const custom = accent != null || rw != null;
    tabs.innerHTML = `<span${custom ? "" : ' class="on"'}>presets/${look}.json</span><span${custom ? ' class="on"' : ""}>local.json</span>`;
    const rows: [string, string, string][] = [
      ["name", `"${look}"`, "s"],
      ["color.accent", `"${A}"`, "s"],
      ["color.bg", `"${L.bg}"`, "s"],
      ["color.surface", `"${L.surface}"`, "s"],
      ["radius.window", String(R), "n"],
      ["radius.control", String(L.rc), "n"],
      ["font.numeric", `"${L.num.split(",")[0].replace("-apple-system", "SF Pro Display")}"`, "s"],
      ["font.numericWeight", String(L.numw), "n"],
      ["glass.blurSize", String(L.blur), "n"],
    ];
    const cur: Record<string, string> = {};
    let out = "{\n";
    let group = "";
    rows.forEach(([k, val, t], i) => {
      cur[k] = val;
      const [g, key] = k.includes(".") ? k.split(".") : ["", k];
      if (g !== group) { if (group) out += "  },\n"; if (g) out += `  <span class="k">"${g}"</span>: {\n`; group = g; }
      const ind = g ? "    " : "  ";
      const changed = prev[k] !== undefined && prev[k] !== val;
      const last = i === rows.length - 1 || (rows[i + 1][0].split(".")[0] !== g);
      const ln = `${ind}<span class="k">"${key}"</span>: <span class="${t}">${val}</span>${last && g ? "" : ","}`;
      out += (changed ? `<span class="chg">${ln}</span>` : ln) + "\n";
    });
    out += "  }\n}";
    json.innerHTML = out;
    prev = cur;
    if (doApply) runApply(what === "accent" ? `nox theme apply   <span style="color:var(--text3)"># local.json color.accent</span>` : `nox theme switch ${look}`);
  }
  update(false);
  apply.innerHTML = `<div><span class="p">$</span> <b>nox theme</b></div><div>  * ember<br>    minimal<br>    sequoia<br>    telemetry</div>`;
}

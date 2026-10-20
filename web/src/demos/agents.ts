// Mission Control: live-feeling agent sessions cycling working -> NEEDS YOU -> done; reply from the card.
import { h, esc, reduced, toast, visibility } from "../util";

type State = "run" | "need" | "done";
type Q = { text: string; opts: string[]; reply?: boolean };
type Agent = {
  id: number; kind: "claude" | "codex" | "gemini" | "opencode"; repo: string; branch: string; title: string;
  state: State; lines: string[]; script: string[]; q?: Q; diff?: [number, number, number]; ctx: number; started: number; mode?: string;
  el?: HTMLElement; doneAt?: number;
};

const GLYPH: Record<Agent["kind"], [string, string]> = {
  claude: ["C", "#d97757"], codex: ["X", "#e8e8e8"], gemini: ["G", "#7aa7ff"], opencode: ["O", "#3ddc97"],
};

let uid = 0;
const mk = (a: Omit<Agent, "id" | "started" | "lines"> & { lines?: string[]; ago?: number }): Agent =>
  ({ ...a, id: ++uid, lines: a.lines ?? [], started: Date.now() - (a.ago ?? 0) * 1000 });

function seed(): Agent[] {
  return [
    mk({ kind: "claude", repo: "dotfiles", branch: "shelf-undo", title: "Shelf: undo after drag-out", state: "run", ctx: 0.34, ago: 252,
      lines: ["Read modules/shelf/ShelfView.qml"],
      script: ["Grep \"undoStack\" services/", "Edit services/Shelf.qml  +18 −4", "Bash nox shelf status", "The drag-out now pushes onto the same undo stack as remove.", "@q", "Bash qs -c nox ipc call shelf status", "@done"],
      q: { text: "Run the shell test harness? It restarts `qs -c nox` once.", opts: ["Yes", "Not now"] }, diff: [3, 41, 9] }),
    mk({ kind: "codex", repo: "api", branch: "fix/429", title: "Retry 429s with jitter", state: "run", ctx: 0.58, ago: 611,
      lines: ["Edit src/client/retry.ts  +32 −6"],
      script: ["@q", "Bash pnpm test --filter api", "12 passed · 0 failed", "@done"],
      q: { text: "Allow `pnpm test --filter api`?", opts: ["Yes", "Always", "No"] }, diff: [2, 38, 6] }),
    mk({ kind: "claude", repo: "notes-app", branch: "main", title: "Paste images as files", state: "need", ctx: 0.21, ago: 95,
      lines: ["Read web/src/paste.ts", "Two places can hold pasted images."],
      script: ["Edit web/src/paste.ts  +27 −3", "Bash npm run build", "@done"],
      q: { text: "Keep pasted images next to the note, or in `~/Notes/assets`?", opts: ["Next to note", "assets/"], reply: true }, diff: [4, 61, 12] }),
    mk({ kind: "gemini", repo: "kdeconnect-rs", branch: "remote-scroll", title: "Remote input: scroll events", state: "done", ctx: 0.47, ago: 1880,
      lines: ["Edit plugins/mousepad.rs  +42 −7", "cargo build --release ok", "Scroll and pinch now reach the compositor."],
      script: [], diff: [3, 42, 7] }),
  ];
}

export function initAgents(root: HTMLElement) {
  root.innerHTML = "";
  const head = h("div.mc-head", null,
    h("div.mc-title", null, h("small", null, h("i"), "NOX · AGENTS · LIVE"), h("h3", { text: "MISSION CONTROL" })),
    h("div.mc-stats"));
  const grid = h("div.mc-grid", { "aria-live": "polite" });
  const launch = h("form.mc-launch", null, h("span", { text: ">" }),
    h("input", { type: "text", name: "task", placeholder: "task in repo, e.g. add a --json flag in dotfiles", "aria-label": "Start a new agent task", autocomplete: "off" }),
    h("kbd", { text: "↵" }));
  const toastEl = h("div.mc-toast", { role: "status" });
  root.append(head, grid, launch, toastEl);

  let agents = seed();
  let cost = 4.82, tokens = 1840;
  const stats = head.querySelector(".mc-stats")!;

  function renderStats() {
    const need = agents.filter((a) => a.state === "need").length;
    const run = agents.filter((a) => a.state === "run").length;
    const S: [string, string, boolean?][] = [
      ["SESSIONS", String(agents.length)], ["WORKING", String(run)], ["NEEDS YOU", String(need), need > 0],
      ["ERRORS", "0"], ["TODAY", `$${cost.toFixed(2)}`], ["TOKENS", `${(tokens / 1000).toFixed(1)}M`],
    ];
    stats.innerHTML = S.map(([k, v, a]) => `<div class="mc-stat${a ? " alert" : ""}"><span>${k}</span><b>${v}</b></div>`).join("");
  }

  const fmtAgo = (a: Agent) => {
    const s = Math.floor((Date.now() - a.started) / 1000);
    return s < 60 ? `${s}s` : s < 3600 ? `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, "0")}s` : `${Math.floor(s / 3600)}h ${Math.floor((s % 3600) / 60)}m`;
  };
  const line = (l: string) => {
    const m = l.match(/^(Read|Edit|Bash|Grep|Write)\s(.*)$/);
    return m ? `<span class="tool">${m[1]}</span> ${esc(m[2])}` : esc(l);
  };

  function card(a: Agent) {
    const [g, c] = GLYPH[a.kind];
    const el = a.el ?? h("article.ag");
    a.el = el;
    el.className = `ag ${a.state === "need" ? "need" : ""}`;
    const stateTxt = a.state === "run" ? "WORKING" : a.state === "need" ? "NEEDS YOU" : "DONE";
    el.innerHTML = `
      <div class="ag-top"><span class="ag-glyph" style="background:${c}">${g}</span><b>${esc(a.repo)}</b><span>· ${esc(a.branch)}</span><span class="sp"></span><span class="ag-state ${a.state}">${stateTxt}</span></div>
      <div class="ag-title">${esc(a.title)}</div>
      <div class="ag-line">${a.lines.slice(-3).map(line).join("<br>")}</div>
      <div class="ag-slot"></div>
      <div class="ag-foot"><span>${a.kind}${a.mode ? " · " + a.mode : ""}</span><span class="ctx" title="context used"><i style="--v:${a.ctx}"></i></span><span class="t">${fmtAgo(a)}</span>${a.state === "done" && a.diff ? `<span class="diff"><b>+${a.diff[1]}</b> <s>−${a.diff[2]}</s></span>` : ""}</div>`;
    const slot = el.querySelector(".ag-slot")!;
    if (a.state === "need" && a.q) {
      const q = h("div.ag-q", null, h("p", { html: esc(a.q.text).replace(/`([^`]+)`/g, "<code>$1</code>") }));
      const row = h("div.row");
      a.q.opts.forEach((o, i) => row.append(h("button.chip" + (i === 0 ? ".hot" : ""), { type: "button", text: o, onclick: () => answer(a, o) })));
      q.append(row);
      if (a.q.reply) {
        const f = h("form.ag-reply", null, h("input", { type: "text", placeholder: "Reply…", "aria-label": "Reply to the agent" }));
        f.addEventListener("submit", (e) => { e.preventDefault(); const v = (f.firstChild as HTMLInputElement).value.trim(); if (v) answer(a, v); });
        q.append(f);
      }
      slot.append(q);
    } else if (a.state === "done") {
      const row = h("div.ag-q", null, h("div.row", null,
        h("button.chip", { type: "button", text: "Diff", onclick: () => toast(`Opens the last turn's changes: ${a.diff?.[0] ?? 2} files, +${a.diff?.[1]} −${a.diff?.[2]}`) }),
        h("button.chip", { type: "button", text: "Jump", onclick: () => toast("Focuses the session's window (or attaches its tmux)") })));
      slot.append(row);
    }
    return el;
  }

  function render() {
    grid.replaceChildren(...agents.map(card));
    renderStats();
  }

  let toastTimer = 0;
  function notify(a: Agent) {
    if (!a.q) return;
    const name = a.kind[0].toUpperCase() + a.kind.slice(1);
    toastEl.innerHTML = "";
    const [g, c] = GLYPH[a.kind];
    toastEl.append(
      h("b.ic", { text: g, style: { background: c } }),
      h("div", null, h("strong", { text: `${name} needs you` }), `${a.repo} · ${a.q.text.replace(/`/g, "")}`,
        h("div.acts", null,
          h("button.chip.hot", { type: "button", text: a.q.opts[0], onclick: () => { answer(a, a.q!.opts[0]); toastEl.classList.remove("on"); } }),
          h("button.chip", { type: "button", text: "Open", onclick: () => { toastEl.classList.remove("on"); a.el?.scrollIntoView({ block: "nearest", behavior: reduced ? "auto" : "smooth" }); a.el?.querySelector<HTMLElement>("button")?.focus({ preventScroll: true }); } }))));
    toastEl.classList.add("on");
    clearTimeout(toastTimer);
    toastTimer = window.setTimeout(() => toastEl.classList.remove("on"), 5200);
  }

  function answer(a: Agent, o: string) {
    if (a.state !== "need") return;
    a.lines.push(`↳ you: ${o}`);
    a.state = "run";
    a.q = undefined;
    toastEl.classList.remove("on");
    card(a); renderStats();
  }

  function step() {
    const now = Date.now();
    for (const a of agents) {
      if (a.state === "run") {
        if (Math.random() < 0.55) continue;
        const next = a.script.shift();
        if (!next) { a.state = "done"; a.doneAt = now; a.lines.push("Turn complete."); }
        else if (next === "@q") { if (a.q) { a.state = "need"; card(a); renderStats(); notify(a); continue; } }
        else if (next === "@done") { a.state = "done"; a.doneAt = now; a.lines.push("Turn complete."); }
        else a.lines.push(next);
        a.ctx = Math.min(0.92, a.ctx + 0.03 + Math.random() * 0.04);
        tokens += 20 + Math.round(Math.random() * 60);
        cost += 0.03 + Math.random() * 0.06;
        card(a);
      } else {
        // keep the elapsed clock fresh
        const t = a.el?.querySelector(".t");
        if (t) t.textContent = fmtAgo(a);
      }
    }
    // a long-done session gets pruned and a new one starts, so the panel stays alive
    const stale = agents.find((a) => a.state === "done" && a.doneAt && now - a.doneAt > 14000);
    if (stale) replace(stale, freshTask());
    renderStats();
  }

  const POOL: [Agent["kind"], string, string, string[]][] = [
    ["opencode", "dotfiles", "Theme: add a zed target", ["Read nox/.config/nox/targets.json", "Write templates/zed.json.tpl", "Bash nox theme check"]],
    ["claude", "relay", "Fix the borrow in mesh.rs", ["Read src/mesh.rs", "Edit src/mesh.rs  +3 −2", "Bash cargo build"]],
    ["codex", "web", "Lazy-load the desktop iframe", ["Read src/main.ts", "Edit src/main.ts  +24 −3", "Bash pnpm build"]],
  ];
  let pi = 0;
  function freshTask(): Agent {
    const [kind, repo, title, script] = POOL[pi++ % POOL.length];
    return mk({ kind, repo, branch: "main", title, state: "run", ctx: 0.05, lines: ["Session started"], script: [...script, "@q", "@done"],
      q: { text: "Commit the change on a new branch?", opts: ["Commit", "Leave it"] }, diff: [2, 20 + Math.round(Math.random() * 30), Math.round(Math.random() * 9)] });
  }
  function replace(old: Agent, nu: Agent) {
    const i = agents.indexOf(old);
    agents[i] = nu;
    const el = card(nu);
    el.classList.add("enter");
    old.el?.replaceWith(el);
    requestAnimationFrame(() => requestAnimationFrame(() => el.classList.remove("enter")));
  }

  launch.addEventListener("submit", (e) => {
    e.preventDefault();
    const inp = launch.querySelector("input")!;
    const v = inp.value.trim();
    if (!v) return;
    const m = v.match(/^(.*?)\s+in\s+([\w.-]+)\s*$/i);
    const task = (m ? m[1] : v).replace(/^>\s*/, "");
    const repo = m ? m[2] : "dotfiles";
    const nu = mk({ kind: "claude", repo, branch: "main", title: task[0].toUpperCase() + task.slice(1), state: "run", ctx: 0.03, mode: "background · tmux",
      lines: [`nox agents start --mode background ${repo}`], script: ["Read README.md", "Grep the relevant files", "@q", "Edit 2 files", "@done"],
      q: { text: `Plan ready for "${task}". Go ahead?`, opts: ["Go", "Show plan"] }, diff: [2, 24, 5] });
    const victim = agents.find((a) => a.state === "done") ?? agents[0];
    replace(victim, nu);
    renderStats();
    inp.value = "";
    toast(`Started in the background: detached tmux session (nox-agents) in ${repo}`);
  });

  render();
  let iv = 0;
  visibility(root, (on) => {
    clearInterval(iv);
    if (on) iv = window.setInterval(step, reduced ? 4000 : 1600);
  });
}

/** The usage ring widget + slider; also drives the nav bar's ring. */
export function initUsage(root: HTMLElement) {
  const r5 = h("div.ul-row", null, h("span.lab", { text: "5-hour" }), h("span.ul-dots"), h("b"));
  const r7 = h("div.ul-row", null, h("span.lab", { text: "Weekly" }), h("span.ul-dots"), h("b"));
  const slider = h("input", { type: "range", min: "0", max: "100", value: "10", "aria-label": "Simulated 5-hour usage" }) as HTMLInputElement;
  const range = h("label.ul-range", null, "simulate", slider);
  root.append(r5, r7, range);
  const dots = (row: HTMLElement, pct: number, n: number, warn: boolean) => {
    const d = row.querySelector(".ul-dots") as HTMLElement;
    if (d.childElementCount !== n) d.innerHTML = "<i></i>".repeat(n);
    const on = Math.round((pct / 100) * n);
    Array.from(d.children).forEach((c, i) => c.classList.toggle("on", i < on));
    d.classList.toggle("warn", warn);
    (row.querySelector("b") as HTMLElement).textContent = `${Math.round(pct)}%`;
  };
  const ring = document.getElementById("bar-ring") as unknown as SVGCircleElement | null;
  const pctEl = document.getElementById("bar-pct");
  const week = document.getElementById("bar-week");
  const set = (p5: number) => {
    const p7 = 73;
    dots(r5, p5, 32, p5 >= 80);
    dots(r7, p7, 32, false);
    if (ring) {
      ring.style.strokeDashoffset = String(37.7 * (1 - p5 / 100));
      ring.style.stroke = p5 >= 80 ? "var(--ember)" : p5 < 50 ? "rgba(255,255,255,.55)" : "var(--text)";
      (ring.parentNode as SVGElement).style.animation = p5 >= 95 ? "pulse 1s infinite" : "";
    }
    if (pctEl) { pctEl.textContent = `${Math.round(p5)}%`; pctEl.style.color = p5 >= 80 ? "var(--ember)" : ""; }
    if (week && !week.childElementCount) week.innerHTML = "<i></i>".repeat(5);
    if (week) Array.from(week.children).forEach((c, i) => c.classList.toggle("on", i < Math.round(p7 / 20)));
  };
  slider.addEventListener("input", () => set(+slider.value));
  set(10);
}

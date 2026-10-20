// nox Notes: the page. Milkdown Crepe edits one markdown file of ~/Notes at a time; open notes are
// tabs. The Electron main process (notes-app/main.cjs) does the file work: window.nox.call(op, args)
// and window.nox.on((name, data) => ...) come from its preload.
// Notes are plain .md files: what Crepe shows is what any editor opens. Saves 500 ms after typing
// stops, on switching tabs, on hiding and on quit; opening a note never rewrites it. A new note is
// "Untitled" until its first line names it.
//   Ctrl+N new   Ctrl+P all notes   Ctrl+W close tab   Ctrl+Tab / Ctrl+Shift+Tab next / previous tab
//   Ctrl+1..9 tab N   Ctrl+M preview   Ctrl+S save now   Esc hide
import { Crepe } from "@milkdown/crepe";
import { remarkStringifyOptionsCtx } from "@milkdown/kit/core";
// the feature styles we use (common/style.css also pulls in LaTeX with its fonts, 1.5 MB)
import "@milkdown/crepe/theme/common/prosemirror.css";
import "@milkdown/crepe/theme/common/reset.css";
import "@milkdown/crepe/theme/common/block-edit.css";
import "@milkdown/crepe/theme/common/code-mirror.css";
import "@milkdown/crepe/theme/common/cursor.css";
import "@milkdown/crepe/theme/common/image-block.css";
import "@milkdown/crepe/theme/common/link-tooltip.css";
import "@milkdown/crepe/theme/common/list-item.css";
import "@milkdown/crepe/theme/common/placeholder.css";
import "@milkdown/crepe/theme/common/toolbar.css";
import "@milkdown/crepe/theme/common/table.css";
import "@milkdown/crepe/theme/common/top-bar.css";
import "@milkdown/crepe/theme/frame-dark.css";
import "./style.css";

const call = (op, args = {}) => window.nox.call(op, args);
const $ = s => document.querySelector(s);
const el = { tabs: $("#tabs"), title: $("#title"), where: $("#where"), editor: $("#editor"), scroll: $("#scroll"),
             words: $("#words"), status: $("#status"), palette: $("#palette"), find: $("#find"), results: $("#results") };
addEventListener("error", e => call("log", { msg: e.message + " @ " + e.filename + ":" + e.lineno }));
addEventListener("unhandledrejection", e => call("log", { msg: "unhandled: " + (e.reason?.stack || e.reason) }));

// ---- state ----
let tabs = [];                // open note paths, in tab order
let current = "";
let crepe = null;
let mounting = false;
let dirty = false;
let lastText = "";            // markdown as loaded (re-serialised by Crepe) / last saved
let preview = false;
let queue = Promise.resolve();          // tab switches / saves run one at a time
const run = fn => (queue = queue.then(fn, fn));
const baseName = p => p.split("/").pop().replace(/\.md$/i, "");
const untitled = p => /^Untitled( \d+)?$/.test(baseName(p));

// ---- editor ----
// Crepe writes an empty paragraph as "<br />"; on disk that is just a blank line
const clean = md => md.replace(/^[ \t]*<br\s*\/?>[ \t]*$/gm, "").replace(/\n{3,}/g, "\n\n").replace(/^\n+/, "");

async function mount(markdown) {
    if (crepe) { const old = crepe; crepe = null; await old.destroy(); }
    el.editor.replaceChildren();
    const c = new Crepe({
        root: el.editor,
        defaultValue: markdown,
        features: { [Crepe.Feature.Latex]: false, [Crepe.Feature.AI]: false, [Crepe.Feature.TopBar]: true, [Crepe.Feature.ImageBlock]: false },
        featureConfigs: { [Crepe.Feature.Placeholder]: { text: "Start writing, or type / for blocks", mode: "doc" } },
    });
    // write markdown the way people type it: "-" bullets, "*" emphasis, "**" strong
    c.editor.config(ctx => ctx.update(remarkStringifyOptionsCtx, o => ({ ...o, bullet: "-", emphasis: "*", strong: "*", rule: "-" })));
    c.on(api => api.markdownUpdated((_ctx, md) => { if (!mounting && crepe === c && md !== lastText) changed(); }));
    mounting = true;
    await c.create();
    crepe = c;
    lastText = c.getMarkdown();
    mounting = false;
    c.setReadonly(preview);
}
const text = () => crepe ? crepe.getMarkdown() : lastText;
function focusEditor() { if (!preview) el.editor.querySelector(".ProseMirror")?.focus(); }

// ---- tabs ----
function persist() { call("state", { tabs, last: current }); }
function open(path, { focus = true } = {}) {
    return run(async () => {
        if (path === current) { if (focus) focusEditor(); return; }
        await saveNow();
        await dropIfEmpty();
        let body;
        try { body = await call("read", { path }); } catch { tabs = tabs.filter(t => t !== path); renderTabs(); return; }
        current = path;
        if (!tabs.includes(path)) tabs.push(path);
        dirty = false;
        await mount(body);
        el.scroll.scrollTop = 0;
        status("");
        info();
        renderTabs();
        persist();
        if (focus) focusEditor();
    });
}
async function newNote(name) {
    let path = await call("create");
    if (name) { try { path = await call("rename", { path, name }); } catch { /* keep Untitled */ } }
    return open(path);
}
// an Untitled note nobody wrote in is removed when you leave it (and its tab closes)
async function dropIfEmpty() {
    if (!current || !untitled(current) || clean(text()).trim() !== "") return;
    await call("remove", { path: current });
    tabs = tabs.filter(t => t !== current);
    current = "";
}
function closeTab(path) {
    return run(async () => {
        const i = tabs.indexOf(path);
        if (i < 0) return;
        if (path === current) {
            await saveNow();
            await dropIfEmpty();
            tabs = tabs.filter(t => t !== path);
            current = "";
            const next = tabs[Math.min(i, tabs.length - 1)];
            setTimeout(() => next ? open(next) : newNote());
        } else tabs.splice(i, 1);
        renderTabs();
        persist();
    });
}
function step(d) { const i = tabs.indexOf(current); if (tabs.length > 1) open(tabs[(i + d + tabs.length) % tabs.length]); }

function renderTabs() {
    el.tabs.replaceChildren(...tabs.map(p => {
        const t = document.createElement("div");
        t.className = "tab" + (p === current ? " cur" : "");
        t.title = p;
        t.innerHTML = `<svg viewBox="0 0 24 24"><path d="M7 3.5h7l4.5 4.5v12.5H7z"/><path d="M14 3.5V8h4.5"/></svg><span></span>
            <button class="x" title="Close  Ctrl+W"><svg viewBox="0 0 24 24"><path d="M7 7l10 10M17 7L7 17"/></svg></button>`;
        t.querySelector("span").textContent = baseName(p);
        t.onmousedown = e => { if (e.button === 1) { e.preventDefault(); closeTab(p); } };
        t.onclick = e => { if (e.target.closest(".x")) closeTab(p); else open(p); };
        return t;
    }));
    el.tabs.querySelector(".cur")?.scrollIntoView({ block: "nearest", inline: "nearest" });
}
function info() {
    el.title.value = current ? baseName(current) : "";
    el.where.textContent = current ? current.replace(/^\/home\/[^/]+/, "~").replace(/[^/]*$/, "") : "";
    countWords();
}

// ---- saving ----
let saveTimer = 0, countTimer = 0;
function changed() {
    dirty = true;
    status("Edited");
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => run(saveNow), 500);
    clearTimeout(countTimer);
    countTimer = setTimeout(countWords, 300);
}
async function saveNow() {
    clearTimeout(saveTimer);
    if (!current || !dirty || !crepe) return;
    const md = clean(text());
    dirty = false;
    try {
        await call("write", { path: current, text: md });
        lastText = text();
        status("Saved");
        await autoName(md);
    } catch (e) {
        dirty = true;
        status("Not saved: " + e.message, true);
    }
}
async function autoName(md) {
    if (!untitled(current)) return;
    const first = md.split("\n").map(l => l.replace(/^#{1,6}\s+|^[-*+]\s+(\[[ xX]\]\s+)?|^\d+[.)]\s+|^>\s*/, "")
        .replace(/[*_`~[\]]/g, "").trim()).find(l => l)?.replace(/[/\\:*?"<>|]/g, "").slice(0, 60).trim();
    if (first && first.length >= 2) await rename(first);
}
async function rename(name) {
    name = String(name).replace(/[/\\]/g, "-").replace(/\.md$/i, "").trim();
    if (!name || !current || name === baseName(current)) { info(); return; }
    try {
        const p = await call("rename", { path: current, name });
        tabs = tabs.map(t => t === current ? p : t);
        current = p;
        persist();
    } catch (e) { status(e.message, true); }
    info();
    renderTabs();
}

// ---- view ----
function status(s, bad = false) {
    el.status.querySelector("b").textContent = s;
    el.status.className = s === "Saved" ? "saved" : bad ? "bad" : s ? "edited" : "";
}
function countWords() {
    const t = clean(text()).replace(/[#>*_`~\-[\]()!|]/g, " ").trim();
    const n = t ? t.split(/\s+/).length : 0;
    el.words.textContent = n === 1 ? "1 word" : n + " words";
}
function setPreview(on) {
    preview = on;
    crepe?.setReadonly(on);
    document.body.classList.toggle("preview", on);
    $("#mode-edit").classList.toggle("on", !on);
    $("#mode-preview").classList.toggle("on", on);
    call("state", { preview: on });
    if (!on) focusEditor();
}

// ---- all notes (Ctrl+P) ----
let all = [], sel = 0;
async function palette(show) {
    el.palette.hidden = !show;
    if (!show) { focusEditor(); return; }
    all = await call("list");
    el.find.value = "";
    sel = 0;
    renderResults();
    el.find.focus();
}
function matches() {
    const q = el.find.value.trim().toLowerCase();
    return all.filter(n => !q || n.name.toLowerCase().includes(q) || n.preview.toLowerCase().includes(q));
}
function ago(ms) {
    const m = Math.floor((Date.now() - ms) / 60000);
    if (m < 1) return "now";
    if (m < 60) return m + "m";
    if (m < 1440) return Math.floor(m / 60) + "h";
    return new Date(ms).toLocaleDateString(undefined, { day: "numeric", month: "short" });
}
function renderResults() {
    const list = matches();
    sel = Math.max(0, Math.min(sel, list.length - 1));
    el.results.replaceChildren(...list.map((n, i) => {
        const li = document.createElement("li");
        li.className = (i === sel ? "sel" : "") + (tabs.includes(n.path) ? " open" : "");
        li.innerHTML = `<div class="name"></div><div class="pre"></div><div class="when"></div>`;
        li.querySelector(".name").textContent = n.name;
        li.querySelector(".pre").textContent = n.preview;
        li.querySelector(".when").textContent = ago(n.mtime);
        li.onmousemove = () => { if (sel !== i) { sel = i; renderResults(); } };
        li.onclick = () => { palette(false); open(n.path); };
        return li;
    }));
    if (!list.length && el.find.value.trim()) {
        const li = document.createElement("li");
        li.className = "sel new";
        li.textContent = "New note “" + el.find.value.trim() + "”";
        li.onclick = () => { const v = el.find.value.trim(); palette(false); newNote(v); };
        el.results.append(li);
    }
    el.results.querySelector(".sel")?.scrollIntoView({ block: "nearest" });
}
el.find.oninput = () => { sel = 0; renderResults(); };
el.find.onkeydown = async e => {
    const list = matches();
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); palette(false); }
    else if (e.key === "ArrowDown") { e.preventDefault(); sel = Math.min(sel + 1, list.length - 1); renderResults(); }
    else if (e.key === "ArrowUp") { e.preventDefault(); sel = Math.max(sel - 1, 0); renderResults(); }
    else if (e.key === "Enter") {
        e.preventDefault();
        const v = el.find.value.trim();
        palette(false);
        if (e.ctrlKey || !list.length) newNote(v);
        else open(list[sel].path);
    } else if (e.key === "Backspace" && e.ctrlKey && list[sel]) {
        e.preventDefault();
        const p = list[sel].path;
        if (p === current) dirty = false;
        await call("trash", { path: p });
        if (tabs.includes(p)) await closeTab(p);
        all = await call("list");
        renderResults();
    }
};
el.palette.onmousedown = e => { if (e.target === el.palette) palette(false); };

// ---- wiring ----
$("#new").onclick = () => newNote();
$("#hide").onclick = () => hide();
$("#all").onclick = () => palette(el.palette.hidden);
$("#mode-edit").onclick = () => setPreview(false);
$("#mode-preview").onclick = () => setPreview(true);
el.title.onkeydown = e => {
    if (e.key === "Enter") { e.preventDefault(); el.title.blur(); }
    else if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); info(); focusEditor(); }
};
el.title.onblur = () => { if (current && el.title.value.trim() !== baseName(current)) run(() => rename(el.title.value)); };
// links: Ctrl+click while editing, a plain click in preview
document.addEventListener("click", e => {
    const a = e.target.closest(".ProseMirror a[href]");
    if (a && (preview || e.ctrlKey)) { e.preventDefault(); call("openUrl", { url: a.href }); }
});

function hide() {
    return run(async () => {
        await saveNow();
        await dropIfEmpty();
        if (!current) {
            renderTabs();
            persist();
            setTimeout(async () => { const n = (await call("list"))[0]; const t = tabs[0] || n?.path; if (t) open(t, { focus: false }); });
        }
        call("hide");
    });
}

addEventListener("keydown", e => {
    const ctrl = e.ctrlKey || e.metaKey;
    if (e.key === "Escape") {
        // menus (slash menu, link tooltip, heading picker) and the palette close themselves first
        if (e.defaultPrevented || !el.palette.hidden || document.querySelector(".milkdown-slash-menu[data-show='true']")) return;
        e.preventDefault();
        hide();
        return;
    }
    if (!ctrl) return;
    const k = e.key.toLowerCase();
    if (k === "n" && !e.shiftKey) newNote();
    else if (k === "p") palette(el.palette.hidden);
    else if (k === "w") { if (current) closeTab(current); }
    else if (k === "s") run(saveNow);
    else if (k === "m") setPreview(!preview);
    else if (e.key === "Tab") step(e.shiftKey ? -1 : 1);
    else if (/^[1-9]$/.test(e.key) && !e.shiftKey && !e.altKey) { const t = tabs[Math.min(+e.key, tabs.length) - 1]; if (t) open(t); }
    else return;
    e.preventDefault();
    e.stopPropagation();
}, true);

// ---- host events ----
window.nox.on(async (name, data) => {
    if (name === "focus") {
        // shown again: pick up edits made elsewhere (nvim, sync) when we have none
        if (el.palette.hidden) focusEditor();
        if (!current || dirty) return;
        run(async () => {
            if (!(await call("exists", { path: current }))) {
                const gone = current;
                current = "";
                tabs = tabs.filter(t => t !== gone);
                renderTabs();
                setTimeout(() => tabs[0] ? open(tabs[0]) : newNote());
                return;
            }
            const body = await call("read", { path: current });
            if (!dirty && clean(body) !== clean(lastText)) { await mount(body); countWords(); }
        });
    } else if (name === "new") newNote();
    else if (name === "open") open(data);
    else if (name === "flush") { await run(async () => { await saveNow(); await dropIfEmpty(); persist(); }); call("quit"); }
});

function applyTheme(t) { for (const [k, v] of Object.entries(t || {})) document.documentElement.style.setProperty("--" + k, v); }

// ---- start ----
(async () => {
    const init = await call("init");
    applyTheme(init.theme);
    preview = !!init.state.preview;
    document.body.classList.toggle("preview", preview);
    $("#mode-edit").classList.toggle("on", !preview);
    $("#mode-preview").classList.toggle("on", preview);
    const list = await call("list");
    const have = new Set(list.map(n => n.path));
    tabs = (init.state.tabs || []).filter(p => have.has(p));
    const want = init.open || (have.has(init.state.last) ? init.state.last : tabs[0] || list[0]?.path);
    if (init.new || !want) await newNote(); else await open(want);
})();

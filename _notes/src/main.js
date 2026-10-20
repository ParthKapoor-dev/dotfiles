// nox Notes: the page side. Milkdown Crepe edits one markdown file of ~/Notes at a time; the host
// (notes-app/app.py, GTK + WebKit) does the file work over a message bridge:
//   page -> host  webkit.messageHandlers.nox.postMessage(JSON {id, op, args})
//   host -> page  __noxReply(id, result, error), __noxEvent(name, data)
// Notes are plain .md files: what Crepe shows is what any editor opens. Saves 600 ms after typing
// stops, on switching notes, on hiding and on quit. A new note is "Untitled" until its first line
// names it. Ctrl+N new, Ctrl+P find, Ctrl+S save, Ctrl+M markdown source, Ctrl+\ sidebar, Esc hide.
import { Crepe } from "@milkdown/crepe";
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
import "@milkdown/crepe/theme/frame-dark.css";
import "./style.css";

// ---- bridge ----
let seq = 0;
const waiting = new Map();
function call(op, args = {}) {
    return new Promise((resolve, reject) => {
        const id = ++seq;
        waiting.set(id, { resolve, reject });
        window.webkit.messageHandlers.nox.postMessage(JSON.stringify({ id, op, args }));
    });
}
window.__noxReply = (id, result, error) => {
    const w = waiting.get(id);
    if (!w) return;
    waiting.delete(id);
    error ? w.reject(new Error(error)) : w.resolve(result);
};
window.__noxEvent = (name, data) => events[name]?.(data);

const $ = s => document.querySelector(s);
const el = { side: $("#side"), list: $("#list"), find: $("#find"), count: $("#count"), title: $("#title"), editor: $("#editor"),
             source: $("#source"), scroll: $("#scroll"), words: $("#words"), status: $("#status") };

// ---- state ----
let notes = [];               // [{path, name, mtime, preview}]
let current = "";             // path of the open note
let crepe = null;
let dirty = false;
let lastText = "";            // markdown as last loaded / saved
let sourceMode = false;
let opening = Promise.resolve();
const untitled = p => /^Untitled( \d+)?$/.test(baseName(p));
const baseName = p => p.split("/").pop().replace(/\.md$/i, "");

// ---- editor ----
async function mount(markdown) {
    if (crepe) { await crepe.destroy(); crepe = null; }
    el.editor.innerHTML = "";
    crepe = new Crepe({
        root: el.editor,
        defaultValue: markdown,
        features: { [Crepe.Feature.Latex]: false, [Crepe.Feature.AI]: false, [Crepe.Feature.TopBar]: false },
        featureConfigs: {
            [Crepe.Feature.Placeholder]: { text: "Start writing, or type / for blocks", mode: "block" },
        },
    });
    crepe.on(api => api.markdownUpdated((_ctx, md) => { if (!mounting && md !== lastText) changed(); }));
    mounting = true;
    await crepe.create();
    // Crepe re-serialises what it loaded (list markers, spacing): that is not an edit, and
    // opening a note must never rewrite it
    lastText = crepe.getMarkdown();
    mounting = false;
}
let mounting = false;
function text() { return sourceMode ? el.source.value : crepe ? crepe.getMarkdown() : lastText; }
function focusEditor() {
    if (sourceMode) { el.source.focus(); return; }
    const pm = el.editor.querySelector(".ProseMirror");
    if (pm) pm.focus();
}

// ---- notes ----
async function refresh() {
    notes = await call("list");
    render();
}
async function open(path, { focus = true } = {}) {
    opening = opening.then(async () => {
        if (path === current) return;
        await flush();
        await dropIfEmpty();
        const body = await call("read", { path });
        current = path;
        lastText = body;
        dirty = false;
        if (sourceMode) el.source.value = body;
        await mount(body);
        el.title.value = baseName(path);
        status("");
        call("state", { last: path });
        countWords();
        render();
        el.scroll.scrollTop = 0;
        if (focus) focusEditor();
    });
    return opening;
}
async function newNote() {
    const path = await call("create");
    await refresh();
    await open(path);
}
// an Untitled note nobody wrote in is removed when you leave it
async function dropIfEmpty() {
    if (!current || !untitled(current) || text().trim() !== "") return false;
    await call("remove", { path: current });
    current = "";
    return true;
}

// ---- saving ----
let saveTimer = 0;
function changed() {
    dirty = true;
    status("Edited");
    clearTimeout(saveTimer);
    saveTimer = setTimeout(save, 600);
    countWords();
}
async function save() {
    clearTimeout(saveTimer);
    if (!current || !dirty) return;
    const md = text();
    dirty = false;
    try {
        await call("write", { path: current, text: md });
        lastText = md;
        status("Saved");
        await autoName(md);
        await refresh();
    } catch (e) {
        dirty = true;
        status("Not saved: " + e.message, true);
    }
}
const flush = () => save();
async function autoName(md) {
    if (!untitled(current)) return;
    const first = md.split("\n").map(l => l.replace(/^#{1,6}\s+|^[-*+]\s+(\[[ xX]\]\s+)?|^\d+[.)]\s+|^>\s*/, "")
        .replace(/[*_`~[\]]/g, "").trim()).find(l => l)?.replace(/[\/\\:*?"<>|]/g, "").slice(0, 60).trim();
    if (!first || first.length < 2) return;
    await rename(first);
}
async function rename(name) {
    name = name.replace(/[\/\\]/g, "-").replace(/\.md$/i, "").trim();
    if (!name || !current || name === baseName(current)) { el.title.value = baseName(current); return; }
    try {
        current = await call("rename", { path: current, name });
        el.title.value = baseName(current);
        call("state", { last: current });
    } catch (e) {
        status(e.message, true);
        el.title.value = baseName(current);
    }
}
async function trash(path) {
    await call("trash", { path });
    if (path === current) {
        current = "";
        await refresh();
        const next = notes[0];
        if (next) await open(next.path); else await newNote();
    } else await refresh();
}

// ---- view ----
function status(s, bad = false) {
    el.status.querySelector("b").textContent = s;
    el.status.className = s === "Saved" ? "saved" : bad ? "bad" : s ? "edited" : "";
}
function countWords() {
    const t = text().replace(/[#>*_`~\-\[\]()!|]/g, " ").trim();
    const n = t ? t.split(/\s+/).filter(Boolean).length : 0;
    el.words.textContent = (n === 1 ? "1 word" : n + " words") + (n >= 200 ? " · " + Math.max(1, Math.round(n / 220)) + " min read" : "");
}
function ago(ms) {
    const m = Math.floor((Date.now() - ms) / 60000);
    if (m < 1) return "Just now";
    if (m < 60) return m + " min ago";
    if (m < 1440) return Math.floor(m / 60) + " h ago";
    const d = new Date(ms);
    return d.toLocaleDateString(undefined, { day: "numeric", month: "short", year: d.getFullYear() === new Date().getFullYear() ? undefined : "numeric" });
}
function render() {
    const q = el.find.value.trim().toLowerCase();
    const shown = notes.filter(n => !q || n.name.toLowerCase().includes(q) || n.preview.toLowerCase().includes(q));
    el.count.textContent = notes.length;
    el.list.replaceChildren(...shown.map(n => {
        const li = document.createElement("li");
        li.className = n.path === current ? "cur" : "";
        li.innerHTML = `<div class="name"></div><div class="meta"><span class="when"></span><span class="pre"></span></div>
            <button class="del icon" title="Move to trash"><svg viewBox="0 0 24 24"><path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12"/></svg></button>`;
        li.querySelector(".name").textContent = n.name;
        li.querySelector(".when").textContent = ago(n.mtime);
        li.querySelector(".pre").textContent = n.preview;
        li.onclick = e => { if (!e.target.closest(".del")) open(n.path); };
        li.querySelector(".del").onclick = () => trash(n.path);
        return li;
    }));
}
function setSidebar(on, persist = true) {
    el.side.classList.toggle("off", !on);
    $("#toggle-side").classList.toggle("on", on);
    if (persist) call("state", { sidebar: on });
}
async function setSource(on) {
    if (on === sourceMode) return;
    await flush();
    if (on) {
        el.source.value = text();
        sourceMode = true;
        el.editor.hidden = true; el.source.hidden = false;
        fitSource();
    } else {
        const md = el.source.value;
        sourceMode = false;
        lastText = md;
        el.source.hidden = true; el.editor.hidden = false;
        await mount(md);
    }
    $("#mode-rich").classList.toggle("on", !on);
    $("#mode-src").classList.toggle("on", on);
    focusEditor();
}
function fitSource() { el.source.style.height = "auto"; el.source.style.height = el.source.scrollHeight + "px"; }

// ---- wiring ----
$("#new").onclick = () => newNote();
$("#hide").onclick = () => hide();
$("#toggle-side").onclick = () => setSidebar(el.side.classList.contains("off"));
$("#mode-rich").onclick = () => setSource(false);
$("#mode-src").onclick = () => setSource(true);
el.find.oninput = render;
el.find.onkeydown = e => {
    if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); el.find.value = ""; render(); focusEditor(); }
    else if (e.key === "Enter") { const first = el.list.querySelector("li"); if (first) first.click(); el.find.value = ""; render(); }
    else if (e.key === "ArrowDown") { e.preventDefault(); focusEditor(); }
};
el.title.onkeydown = e => {
    if (e.key === "Enter") { e.preventDefault(); el.title.blur(); }
    else if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); el.title.value = baseName(current); focusEditor(); }
};
el.title.onblur = () => { if (current && el.title.value.trim() !== baseName(current)) rename(el.title.value).then(refresh); };
el.source.oninput = () => { fitSource(); if (el.source.value !== lastText) changed(); };
// dragging the header (not its controls) moves the window; double-click does nothing special
$("#head").addEventListener("mousedown", e => {
    if (e.button !== 0 || e.target.closest("button, input")) return;
    e.preventDefault();
    call("drag");
});
// links open in the browser (the host also refuses navigation away from the app)
document.addEventListener("click", e => {
    const a = e.target.closest(".ProseMirror a[href]");
    if (a && (e.ctrlKey || e.metaKey)) { e.preventDefault(); call("openUrl", { url: a.href }); }
});

async function hide() {
    await flush();
    await dropIfEmpty();
    if (!current) { await refresh(); if (notes[0]) await open(notes[0].path, { focus: false }); }
    call("hide");
}

window.addEventListener("keydown", e => {
    const ctrl = e.ctrlKey || e.metaKey;
    if (e.key === "Escape") {
        // menus (slash menu, link tooltip, toolbar) close themselves first
        if (e.defaultPrevented || document.querySelector(".milkdown-slash-menu[data-show='true']")) return;
        e.preventDefault();
        hide();
        return;
    }
    if (!ctrl) return;
    const k = e.key.toLowerCase();
    if (k === "n" && !e.shiftKey) newNote();
    else if (k === "p") { setSidebar(true, false); el.find.focus(); el.find.select(); }
    else if (k === "s") save();
    else if (k === "m") setSource(!sourceMode);
    else if (e.key === "\\") setSidebar(el.side.classList.contains("off"));
    else return;
    e.preventDefault();
}, false);

// ---- host events ----
const events = {
    // the window was shown / focused: pick up edits made elsewhere (nvim, sync) if we have none
    async focus() {
        await refresh();
        const n = notes.find(x => x.path === current);
        if (current && !n) { current = ""; if (notes[0]) await open(notes[0].path); else await newNote(); return; }
        if (n && !dirty) {
            const body = await call("read", { path: current });
            if (body !== lastText) { lastText = body; if (sourceMode) { el.source.value = body; fitSource(); } else await mount(body); countWords(); }
        }
        focusEditor();
    },
    async open(path) { await refresh(); await open(path); },
    new() { newNote(); },
    // the host is quitting (window closed): save first, then tell it to go on
    async flush() { await flush(); await dropIfEmpty(); call("quit"); },
    theme(t) { applyTheme(t); },
};

function applyTheme(t) {
    if (!t) return;
    const r = document.documentElement.style;
    for (const [k, v] of Object.entries(t)) r.setProperty("--" + k, v);
}

// ---- start ----
(async () => {
    const init = await call("init");
    applyTheme(init.theme);
    setSidebar(init.state.sidebar ?? true, false);
    await refresh();
    const want = init.open || (init.state.last && notes.some(n => n.path === init.state.last) ? init.state.last : notes[0]?.path);
    if (init.new || !want) await newNote(); else await open(want);
    document.body.classList.add("ready");
})();

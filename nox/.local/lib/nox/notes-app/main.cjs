// nox Notes: Electron main process (run by ../notes with the system electron43). One frameless
// window running the Milkdown Crepe page in web/; this side does the file work for it over IPC
// (preload.cjs exposes window.nox). Electron, not WebKitGTK: Chromium composites on the GPU here
// (WebKitGTK can't on this NVIDIA laptop), so typing keeps up with the 144 Hz panel.
//
// Single instance. `--hidden` maps the window straight onto special:notes (Hyprland rule on the
// initial title "Notes·"), so the first Ctrl+Super+S only has to move it; ../notes does all
// hiding / showing by moving the window between workspaces, which keeps its place and size.
// A second launch forwards --new / --open PATH / --show.
// Every path must be a .md file directly inside the notes directory (~/Notes, or $NOX_NOTES_DIR).
"use strict";
const { app, BrowserWindow, ipcMain, shell } = require("electron");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const { spawn } = require("node:child_process");

const HOME = os.homedir();
const NOTES = fs.realpathSync.native(ensureDir((process.env.NOX_NOTES_DIR || "~/Notes").replace(/^~/, HOME)));
const STATE_DIR = path.join(process.env.XDG_STATE_HOME || path.join(HOME, ".local/state"), "nox");
const STATE = path.join(STATE_DIR, "notes.json");          // {tabs, last, preview}
const TOKENS = [path.join(STATE_DIR, "tokens.json"), path.join(HOME, ".config/nox/tokens.json")];
const NOTES_CMD = path.join(__dirname, "..", "notes");

function ensureDir(d) { fs.mkdirSync(d, { recursive: true }); return d; }

function args(argv) {
    const a = { hidden: argv.includes("--hidden"), show: argv.includes("--show"), new: argv.includes("--new"), open: null };
    const i = argv.indexOf("--open");
    if (i >= 0 && argv[i + 1]) a.open = argv[i + 1];
    return a;
}
const start = args(process.argv);

if (!app.requestSingleInstanceLock()) app.quit();
app.commandLine.appendSwitch("disable-features", "Vulkan");    // Vulkan doesn't work with ozone/wayland

// ---- notes ----
function notePath(p) {
    const r = path.resolve(String(p).replace(/^~/, HOME));
    if (path.dirname(r) !== NOTES || !/\.md$/i.test(r)) throw new Error("not a note: " + r);
    return r;
}
function preview(file) {
    let head = "";
    try { const fd = fs.openSync(file, "r"); const b = Buffer.alloc(2000); const n = fs.readSync(fd, b, 0, 2000, 0); fs.closeSync(fd); head = b.toString("utf8", 0, n); }
    catch { return ""; }
    const lines = [];
    for (let l of head.split("\n")) {
        l = l.replace(/^\s*(#{1,6}\s+|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+|>\s*)/, "").replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
             .replace(/[*_`~]|<br\s*\/?>/g, "").trim();
        if (l && !/^[-=*_ ]{3,}$/.test(l)) lines.push(l);
        if (lines.length === 2) break;
    }
    return (lines[1] || "").slice(0, 140);
}
function readState() { try { const d = JSON.parse(fs.readFileSync(STATE, "utf8")); return d && typeof d === "object" ? d : {}; } catch { return {}; } }
function writeAtomic(file, text, mode) {
    const tmp = path.join(path.dirname(file), "." + path.basename(file) + ".tmp");
    const fd = fs.openSync(tmp, "w", mode ?? 0o644);
    fs.writeSync(fd, text);
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    if (mode === undefined && fs.existsSync(file)) fs.chmodSync(tmp, fs.statSync(file).mode & 0o777);
    fs.renameSync(tmp, file);
}
function theme() {
    let t = null;
    for (const p of TOKENS) { try { t = JSON.parse(fs.readFileSync(p, "utf8")); break; } catch { /* next */ } }
    if (!t) return {};
    const c = t.color || {}, font = t.font || {};
    const rgba = (hex, a = 1) => { const h = hex.replace("#", ""); return `rgba(${parseInt(h.slice(0, 2), 16)}, ${parseInt(h.slice(2, 4), 16)}, ${parseInt(h.slice(4, 6), 16)}, ${a})`; };
    const lab = c.label || "#FFFFFF", acc = c.accent || "#FF3B1F";
    const out = {
        bg: c.bg || "#0A0A0A", surface: c.surface || "#141414", raised: c.raised || "#202020",
        label: rgba(lab, c.labelAlpha ?? 0.9), label2: rgba(lab, c.label2Alpha ?? 0.56), label3: rgba(lab, (c.label3Alpha ?? 0.3) + 0.08),
        sep: rgba(lab, (c.sepAlpha ?? 0.1) * 0.8), hair: rgba(lab, c.hairAlpha ?? 0.14),
        fill: rgba(lab, (c.fillAlpha ?? 0.06) * 0.85), fill2: rgba(lab, (c.fill2Alpha ?? 0.11) * 0.85), fill3: rgba(lab, (c.fill3Alpha ?? 0.18) * 0.85),
        accent: acc, "accent-soft": rgba(acc, 0.16), "accent-sel": rgba(acc, 0.3),
    };
    if (font.ui) out["font-ui"] = `"${font.ui}", sans-serif`;
    if (font.display) out["font-display"] = `"${font.display}", sans-serif`;
    if (font.mono) out["font-mono"] = `"${font.mono}", monospace`;
    return out;
}

const ops = {
    init() {
        const a = pendingStart; pendingStart = {};
        let open = null;
        if (a.open) { try { open = notePath(a.open); } catch { /* ignore */ } }
        return { theme: theme(), state: readState(), open, new: !!a.new, notes: NOTES };
    },
    list() {
        return fs.readdirSync(NOTES, { withFileTypes: true })
            .filter(e => e.isFile() && /\.md$/i.test(e.name) && !e.name.startsWith("."))
            .map(e => { const p = path.join(NOTES, e.name); return { path: p, name: e.name.slice(0, -3), mtime: fs.statSync(p).mtimeMs, preview: preview(p) }; })
            .sort((a, b) => b.mtime - a.mtime);
    },
    exists({ path: p }) { try { return fs.statSync(notePath(p)).isFile(); } catch { return false; } },
    read({ path: p }) { return fs.readFileSync(notePath(p), "utf8"); },
    write({ path: p, text }) { writeAtomic(notePath(p), text.replace(/​/g, "")); return true; },
    create() {
        for (let n = 1; ; n++) {
            const p = path.join(NOTES, n === 1 ? "Untitled.md" : `Untitled ${n}.md`);
            if (!fs.existsSync(p)) { fs.writeFileSync(p, ""); return p; }
        }
    },
    rename({ path: p, name }) {
        const src = notePath(p);
        name = String(name).replace(/[/\\\0]/g, "-").replace(/\.md$/i, "").trim().replace(/^[. ]+|[. ]+$/g, "");
        if (!name) throw new Error("empty name");
        const dst = path.join(NOTES, name + ".md");
        if (fs.existsSync(dst) && fs.realpathSync(dst) !== src) throw new Error("A note with that name exists");
        fs.renameSync(src, dst);
        return dst;
    },
    remove({ path: p }) {     // only ever an empty "Untitled"
        const f = notePath(p);
        if (fs.existsSync(f) && fs.statSync(f).size <= 8) fs.unlinkSync(f);
        return true;
    },
    async trash({ path: p }) { await shell.trashItem(notePath(p)); return true; },
    state(kw) {
        const d = Object.assign(readState(), kw);
        ensureDir(STATE_DIR);
        writeAtomic(STATE, JSON.stringify(d), 0o600);
        return true;
    },
    hide() { spawn(NOTES_CMD, ["hide"], { detached: true, stdio: "ignore" }).unref(); return true; },
    openUrl({ url }) { if (/^(https?|mailto):/i.test(url)) shell.openExternal(url); return true; },
    reveal({ path: p }) { shell.showItemInFolder(notePath(p)); return true; },
    quit() { quitting = true; setImmediate(() => app.quit()); return true; },
    log({ msg }) { console.error("nox notes page:", msg); return true; },
};
ipcMain.handle("nox", async (_e, op, a) => {
    if (!Object.hasOwn(ops, op)) throw new Error("unknown op " + op);
    return ops[op](a || {});
});

// ---- window ----
let win = null, quitting = false, pendingStart = start;
function send(name, data) { if (win && !win.isDestroyed()) win.webContents.send("nox-event", name, data); }

function create() {
    const t = theme();
    win = new BrowserWindow({
        width: 900, height: 600, minWidth: 420, minHeight: 260,
        frame: false,
        show: false,
        title: start.hidden ? "Notes·" : "Notes",
        backgroundColor: t.bg || "#0A0A0A",
        icon: path.join(__dirname, "icon.png"),
        webPreferences: { preload: path.join(__dirname, "preload.cjs"), contextIsolation: true, sandbox: true, spellcheck: true, backgroundThrottling: false },
    });
    win.removeMenu();
    win.on("page-title-updated", e => e.preventDefault());
    win.webContents.session.setSpellCheckerLanguages(["en-US"]);
    // links never navigate the app: they open in the browser
    win.webContents.setWindowOpenHandler(({ url }) => { ops.openUrl({ url }); return { action: "deny" }; });
    win.webContents.on("will-navigate", (e, url) => { if (!url.startsWith("file://" + __dirname)) { e.preventDefault(); ops.openUrl({ url }); } });
    win.on("focus", () => send("focus"));
    // closed (Super+Q): the page saves first, then asks to quit (or we quit anyway after a moment)
    win.on("close", e => {
        if (quitting) return;
        e.preventDefault();
        quitting = true;
        send("flush");
        setTimeout(() => app.exit(0), 1500);
    });
    win.loadFile(path.join(__dirname, "web", "index.html"));
    // test hook: NOX_NOTES_EVAL=file.js runs that script in the page once it has settled, prints
    // what it resolves to and quits (use with NOX_NOTES_DIR and --user-data-dir for a throwaway run)
    if (process.env.NOX_NOTES_EVAL) win.webContents.once("did-finish-load", () => setTimeout(async () => {
        try { console.log("EVAL", JSON.stringify(await win.webContents.executeJavaScript(fs.readFileSync(process.env.NOX_NOTES_EVAL, "utf8")))); }
        catch (e) { console.log("EVAL-ERROR", e.message); }
        quitting = true; app.quit();
    }, 1500));
    // mapped once it has painted: no white or empty frame. Hidden starts map too (onto special:notes,
    // by the rule on the "Notes·" title), then take the real title
    win.once("ready-to-show", () => {
        if (start.hidden) { win.showInactive(); setTimeout(() => win.setTitle("Notes"), 400); }
        else win.show();
    });
}

app.on("second-instance", (_e, argv) => {
    const a = args(argv);
    if (!win) return;
    if (a.new) send("new");
    else if (a.open) send("open", a.open);
    if (!win.isVisible()) win.show();
    if (a.show || a.new || a.open) win.focus();
});
app.whenReady().then(create);
app.on("window-all-closed", () => app.quit());

pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Drop shelf store (modules/shelf is the UI; `nox shelf`, IPC target shelf).
// A parking spot for things moving between apps. State in ~/.local/state/nox/shelf/:
//   index.json  { v, items: [...], graveyard: [...], moveOut }
//   items/      the shelf's OWN files: dropped text (.txt / .md), links (.url), image bytes (.png ...),
//               screenshot captures copied in. Nothing else under the user's home is ever deleted:
//               files dropped from a file manager are kept as a path reference only.
// Item: { id, kind: file | dir | image | text | link, name, path, stored, bytes, added (ms),
//         text (text only, up to 100k chars: what a drag-out carries), url, title (links) } + runtime `missing` (path gone).
// Expiry: shell.json shelf.expireHours (default 24) after the item was parked (re-parking refreshes
// it). A stored file of a removed item waits 15 min in the graveyard before it is deleted, so an app
// that reads a dropped file late (Slack / browser upload) still finds it.
// Nothing is logged: no names, paths or text go to the shell log.
Singleton {
    id: root

    readonly property var opts: Config.opt.shelf ?? ({})
    readonly property real expireHours: Math.max(0.01, Number(opts.expireHours ?? 24))
    readonly property real ttlMs: expireHours * 3600000
    readonly property string side: opts.side === "left" ? "left" : "right"
    readonly property string dir: Paths.stateDir + "/shelf"
    readonly property string itemsDir: dir + "/items"
    readonly property int graceMs: 15 * 60000

    property var items: []            // newest first
    property var graveyard: []        // [{ path, at }] stored files of removed items
    property var missing: ({})        // id -> true when the referenced path is gone
    property bool loaded: false
    property bool dirReady: false
    // moveOut: an item leaves the shelf once a drag-out is accepted (footer toggle keeps a runtime
    // choice in index.json over shell.json shelf.moveOut)
    property var moveOutPick: null
    readonly property bool moveOut: moveOutPick ?? (opts.moveOut ?? true)
    readonly property int count: items.length
    property real now: Date.now()

    signal added(var ids)              // UI: fresh cards animate in, the shelf peeks
    signal toast(string text, string glyph)

    // ---------------------------------------------------------------- queries
    function leftMs(it) { return Math.max(0, Math.min(ttlMs, (it.added ?? 0) + ttlMs - now)); }
    function isMissing(it) { return missing[it.id] === true; }
    function find(id) { return items.find(it => it.id === id) ?? null; }
    function extOf(name) { const m = /\.([A-Za-z0-9]{1,8})$/.exec(name ?? ""); return m ? m[1].toLowerCase() : ""; }
    function baseName(p) { return String(p).replace(/\/+$/, "").replace(/^.*\//, ""); }
    readonly property var imageExts: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "avif", "svg", "tif", "tiff", "heic", "jxl"]
    function isImageName(n) { return imageExts.indexOf(extOf(n)) !== -1; }
    function fileUrl(p) { return "file://" + encodeURI(p).replace(/#/g, "%23").replace(/\?/g, "%3F"); }
    function pathOf(url) {
        let s = String(url);
        if (!s.startsWith("file://")) return "";
        s = s.replace(/^file:\/\/[^/]*/, "");
        try { return decodeURIComponent(s); } catch (e) { return s; }
    }
    // what a drag-out of these items carries: file URLs (stored text included as its file), links as
    // their URL
    function uriFor(it) { return it.kind === "link" && it.url ? it.url : fileUrl(it.path); }

    // ---------------------------------------------------------------- adding
    function newId() { seq++; return "s" + Date.now().toString(36) + seq.toString(36); }
    property int seq: 0
    function stamp() {
        const d = new Date();
        const p = n => String(n).padStart(2, "0");
        return d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + "-" + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
    }

    function push(list) {
        if (!list.length) return [];
        let next = items.slice();
        const ids = [];
        for (const it of list) {
            const dup = it.path && !it.stored ? next.find(x => !x.stored && x.path === it.path) : null;
            if (dup) {
                next = [Object.assign({}, dup, { added: Date.now() })].concat(next.filter(x => x !== dup));
                ids.push(dup.id);
            } else {
                next.unshift(it);
                ids.push(it.id);
            }
        }
        added(ids);          // before the list changes: the UI marks these cards fresh
        items = next;
        save();
        refreshStat();
        return ids;
    }

    // files / folders by reference (absolute paths or file:// URLs). A file that came through the
    // document portal (/run/user/<uid>/doc/<id>/name: Qt asks the portal whenever the source offers
    // application/vnd.portal.filetransfer) is resolved back to its real path first.
    readonly property var docRe: /^\/run\/user\/\d+\/doc\/([^/]+)\/[^/]+$/
    function addPaths(paths) {
        const all = paths.map(p => { p = String(p); return p.startsWith("file://") ? pathOf(p) : p; });
        const docs = all.filter(p => docRe.test(p));
        if (docs.length) {
            const pr = copyC.createObject(root, { command: ["sh", "-c",
                "for id; do busctl --user --json=short call org.freedesktop.portal.Documents /org/freedesktop/portal/documents "
                + "org.freedesktop.portal.Documents Info s \"$id\" 2>/dev/null || echo null; done", "sh"].concat(docs.map(p => docRe.exec(p)[1])) });
            const out = outC.createObject(pr);
            pr.stdout = out;
            out.streamFinished.connect(() => {
                const real = {};
                out.text.split("\n").forEach((line, i) => {
                    try {
                        const bytes = JSON.parse(line)?.data?.[0];
                        if (bytes && bytes.length) {
                            let s = "";
                            for (const b of bytes) if (b) s += "%" + b.toString(16).padStart(2, "0");
                            real[docs[i]] = decodeURIComponent(s);
                        }
                    } catch (e) {}
                });
                addResolved(all.map(p => real[p] ?? p));
                pr.destroy();
            });
            pr.running = true;
            return all.length;
        }
        return addResolved(all);
    }
    Component { id: outC; StdioCollector {} }
    function addResolved(paths) {
        const list = [];
        for (let p of paths) {
            if (!p.startsWith("/")) continue;
            p = p.replace(/\/+$/, "") || "/";
            const name = baseName(p);
            list.push({ id: newId(), kind: isImageName(name) ? "image" : "file", name: name, path: p, stored: false, bytes: -1, added: Date.now() });
        }
        return push(list).length;
    }

    // plain text (or a lone URL -> link): stored as a small file in items/
    function addText(text, hint) {
        const t = String(text ?? "");
        if (!t.trim()) return false;
        const one = t.trim();
        if (/^https?:\/\/\S+$/i.test(one) && one.length < 4000) return addLink(one, hint ?? "");
        const md = /^(#{1,6} |[-*] |\d+\. |```)/m.test(t);
        const file = itemsDir + "/text-" + stamp() + "-" + (seq + 1) + (md ? ".md" : ".txt");
        const first = one.split("\n")[0].trim();
        const it = { id: newId(), kind: "text", name: first.length > 48 ? first.slice(0, 47) + "…" : first, path: file, stored: true,
                     bytes: t.length, added: Date.now(), text: t.slice(0, 100000) };
        write(file, t, false, ok => { if (ok) push([it]); else toast("Couldn't save to the shelf", "x"); });
        return true;
    }

    function addLink(url, title) {
        const u = String(url).trim();
        const m = /^[a-z]+:\/\/([^/?#]+)([^?#]*)/i.exec(u);
        const host = m ? m[1].replace(/^www\./, "") : u;
        const t = String(title ?? "").trim();
        const file = itemsDir + "/link-" + stamp() + "-" + (seq + 1) + ".url";
        const it = { id: newId(), kind: "link", name: t || host, title: t, url: u, host: host, pathname: m ? m[2] : "", path: file, stored: true,
                     bytes: -1, added: Date.now() };
        write(file, "[InternetShortcut]\nURL=" + u + "\n" + (t ? "Title=" + t.replace(/\n/g, " ") + "\n" : ""), false, ok => { if (ok) push([it]); });
        return true;
    }

    // raw image bytes (an ArrayBuffer from a browser drag)
    function addImageData(data, mime, name) {
        const ext = ({ "image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif", "image/bmp": "bmp", "image/avif": "avif", "image/svg+xml": "svg" })[mime] ?? "png";
        const file = itemsDir + "/image-" + stamp() + "-" + (seq + 1) + "." + ext;
        const nm = name && isImageName(name) ? name : "image-" + stamp() + "." + ext;
        const it = { id: newId(), kind: "image", name: nm, path: file, stored: true, bytes: data.byteLength ?? -1, added: Date.now() };
        write(file, data, true, ok => { if (ok) push([it]); else toast("Couldn't save the image", "x"); });
        return true;
    }

    // an image dragged out of a web page as a URL only: fetch it once (curl, 20 s, 50 MB cap) so
    // the shelf holds the picture; a failed fetch parks the link instead
    function addRemoteImage(url, title) {
        const u = String(url);
        const m = /\.([a-z0-9]{2,5})(?:[?#]|$)/i.exec(u.replace(/^[a-z]+:\/\/[^/]+/i, ""));
        const ext = m && isImageName("x." + m[1]) ? m[1].toLowerCase() : "png";
        const name = decodeURIComponent((u.split(/[?#]/)[0].replace(/\/+$/, "").replace(/^.*\//, "")) || "image") ;
        const file = itemsDir + "/web-" + stamp() + "-" + (seq + 1) + "." + ext;
        const it = { id: newId(), kind: "image", name: isImageName(name) ? name : name + "." + ext, path: file, stored: true, bytes: -1, added: Date.now(), url: u };
        ensureDir(() => {
            const p = copyC.createObject(root, { command: ["curl", "-fsSL", "--proto", "=https,http", "--max-time", "20", "--max-filesize", "52428800", "-A", "nox-shelf", "-o", file, "--", u] });
            p.exited.connect(code => { if (code === 0) push([it]); else addLink(u, title); p.destroy(); });
            p.running = true;
        });
        return true;
    }

    // a copy of a file the shelf should own (screenshot captures in $XDG_RUNTIME_DIR vanish at logout)
    function addCopy(src) {
        const name = baseName(src);
        const file = itemsDir + "/" + stamp() + "-" + (seq + 1) + "-" + name;
        const it = { id: newId(), kind: isImageName(name) ? "image" : "file", name: name, path: file, stored: true, bytes: -1, added: Date.now() };
        ensureDir(() => {
            const p = copyC.createObject(root, { command: ["cp", "--", src, file] });
            p.exited.connect(code => { if (code === 0) push([it]); else toast("Couldn't copy to the shelf", "x"); p.destroy(); });
            p.running = true;
        });
        return true;
    }

    // a file `nox shelf add -` already wrote into items/ (stdin text): take ownership
    function adopt(path, kind) {
        const p = String(path);
        if (!owned(p)) return false;
        const name = baseName(p);
        const it = { id: newId(), kind: kind || (isImageName(name) ? "image" : "text"), name: name, path: p, stored: true, bytes: -1, added: Date.now() };
        if (it.kind === "text") {
            const v = readC.createObject(root, { path: p });
            const t = v.text() ?? "";
            v.destroy();
            const first = t.trim().split("\n")[0].trim();
            it.text = t.slice(0, 100000);
            it.bytes = t.length;
            if (first) it.name = first.length > 48 ? first.slice(0, 47) + "…" : first;
            push([it]);
        } else push([it]);
        return true;
    }

    // ---------------------------------------------------------------- removing
    function owned(p) { return typeof p === "string" && p.startsWith(itemsDir + "/") && p.indexOf("/../") === -1 && p.indexOf("\n") === -1; }
    function remove(ids) {
        const gone = items.filter(it => ids.indexOf(it.id) !== -1);
        if (!gone.length) return 0;
        items = items.filter(it => ids.indexOf(it.id) === -1);
        lastRemoved = { items: gone, at: Date.now() };
        const now = Date.now();
        graveyard = graveyard.concat(gone.filter(it => it.stored && owned(it.path)).map(it => ({ path: it.path, at: now })));
        const m = Object.assign({}, missing);
        for (const it of gone) delete m[it.id];
        missing = m;
        save();
        return gone.length;
    }
    function clear() { return remove(items.map(it => it.id)); }
    // the last remove / clear / drag-out comes back (10 minutes; stored files are still in the
    // graveyard then)
    property var lastRemoved: null
    function undo() {
        const r = lastRemoved;
        if (!r || Date.now() - r.at > 10 * 60000) return 0;
        lastRemoved = null;
        const back = r.items.filter(it => !items.some(x => x.id === it.id));
        graveyard = graveyard.filter(g => !back.some(it => it.path === g.path));
        added(back.map(it => it.id));
        items = back.concat(items);
        save();
        refreshStat();
        return back.length;
    }
    function setMoveOut(on) { moveOutPick = on; save(); }

    // ---------------------------------------------------------------- upkeep
    function sweep() {
        now = Date.now();
        const expired = items.filter(it => leftMs(it) <= 0).map(it => it.id);
        if (expired.length) {
            remove(expired);
            toast(expired.length + " shelf item" + (expired.length > 1 ? "s" : "") + " expired", "clock");
        }
        // stored files past their grace period (owned paths only, re-checked here)
        const due = graveyard.filter(g => now - g.at >= graceMs);
        if (due.length) {
            const paths = due.map(g => g.path).filter(p => owned(p) && !items.some(it => it.path === p));
            graveyard = graveyard.filter(g => now - g.at < graceMs);
            save();
            if (paths.length) {
                const p = copyC.createObject(root, { command: ["rm", "-f", "--"].concat(paths) });
                p.exited.connect(() => p.destroy());
                p.running = true;
            }
        }
    }
    Timer { interval: 30000; running: root.loaded; repeat: true; onTriggered: { root.sweep(); root.refreshStat(); } }

    // sizes, folders and missing paths (one stat for every item)
    function refreshStat() {
        if (!loaded || !items.length) return;
        if (statProc.running) { statAgain = true; return; }
        statProc.paths = items.map(it => it.path);
        statProc.command = ["stat", "-L", "--printf", "%s\t%F\t%n\n", "--"].concat(statProc.paths);
        statProc.running = true;
    }
    property bool statAgain: false
    Process {
        id: statProc
        property var paths: []
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                for (const line of text.split("\n")) {
                    const a = line.split("\t");
                    if (a.length < 3) continue;
                    seen[a.slice(2).join("\t")] = { bytes: Number(a[0]), dir: a[1] === "directory" };
                }
                const m = {};
                let changed = false;
                const next = root.items.map(it => {
                    const s = seen[it.path];
                    if (statProc.paths.indexOf(it.path) === -1) return it;
                    if (!s) { m[it.id] = true; return it; }
                    const kind = s.dir ? "dir" : it.kind === "dir" ? "file" : it.kind;
                    if (it.bytes === s.bytes && it.kind === kind) return it;
                    changed = true;
                    return Object.assign({}, it, { bytes: s.bytes, kind: kind });
                });
                root.missing = m;
                if (changed) { root.items = next; root.save(); }
            }
        }
        stderr: StdioCollector {}   // "No such file" lines: never logged
        onExited: if (root.statAgain) { root.statAgain = false; Qt.callLater(root.refreshStat); }
    }

    // ---------------------------------------------------------------- files
    function ensureDir(then) {
        if (dirReady) { then(); return; }
        pendingDir.push(then);
        if (!mkdirProc.running) mkdirProc.running = true;
    }
    property var pendingDir: []
    Process {
        id: mkdirProc
        command: ["sh", "-c", "umask 077; mkdir -p \"$1\"", "sh", root.itemsDir]
        onExited: code => {
            root.dirReady = code === 0;
            const q = root.pendingDir; root.pendingDir = [];
            if (code === 0) for (const f of q) f();
            else root.toast("Couldn't create " + root.dir, "x");
        }
    }
    function write(path, data, binary, done) {
        ensureDir(() => {
            const w = writerC.createObject(root, { path: path });
            w.saved.connect(() => { done(true); w.destroy(); });
            w.saveFailed.connect(() => { done(false); w.destroy(); });
            if (binary) w.setData(data); else w.setText(data);
        });
    }
    Component { id: writerC; FileView { preload: false; printErrors: false; atomicWrites: true } }
    Component { id: readC; FileView { printErrors: false; blockLoading: true } }   // small files only (adopt)
    Component { id: copyC; Process {} }

    // ---------------------------------------------------------------- persistence
    function save() { saveTimer.restart(); }
    Timer {
        id: saveTimer
        interval: 250
        onTriggered: root.ensureDir(() => index.setText(JSON.stringify({ v: 1, items: root.items, graveyard: root.graveyard, moveOut: root.moveOutPick }) + "\n"))
    }
    FileView {
        id: index
        path: root.dir + "/index.json"
        blockLoading: true
        printErrors: false
        atomicWrites: true
        onLoaded: {
            root.dirReady = true;
            try {
                const d = JSON.parse(text());
                root.items = (d.items ?? []).filter(it => it && it.id && it.path);
                root.graveyard = d.graveyard ?? [];
                root.moveOutPick = d.moveOut ?? null;
            } catch (e) { console.warn("nox shelf: index.json unreadable, starting empty"); }
            root.loaded = true;
            root.sweep();
            root.refreshStat();
        }
        onLoadFailed: { root.loaded = true; }
    }
}

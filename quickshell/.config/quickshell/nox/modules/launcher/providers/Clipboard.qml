import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// Clipboard history (cliphist). Prefix ":" (also `qs -c nox ipc call launcher clipboard`).
// Lists `cliphist list` (newest first) when the prefix is typed; image entries get thumbnails
// decoded once into $XDG_RUNTIME_DIR/nox/clip/. Enter = `cliphist decode <id> | wl-copy`,
// Shift+Delete = `cliphist delete` for that entry. Nothing runs until the provider is queried.
// The store itself is filled by Hyprland: `wl-paste --watch cliphist store`.
Item {
    id: root
    property string providerId: "clipboard"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Clipboard"
    property string defaultPrefix: ":"
    property bool defaultPrefixOnly: true
    signal resultsChanged()                 // the launcher re-runs the search when this fires

    property var entries: []                // [{ id, line, text, image: bool, ext, meta }]
    property var thumbs: ({})               // id -> file url
    property real loadedAt: 0
    readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nox/clip"

    function refresh() { if (!lister.running) lister.running = true; }

    function query(text, prefixed) {
        if (!prefixed || !Config.moduleEnabled("clipboard")) return [];
        if (Date.now() - loadedAt > 1500) refresh();
        const q = text.toLowerCase();
        const out = [];
        let i = 0;
        for (const e of entries) {
            i++;
            if (q && !(e.image ? (e.meta + " image").toLowerCase().includes(q) : e.text.toLowerCase().includes(q))) continue;
            const m = q && !e.image ? Fuzzy.best(text, [[e.text, 1]]) : null;
            out.push({
                title: e.image ? "Image" : e.text.replace(/\s+/g, " ").slice(0, 160),
                sub: e.image ? e.meta : "",
                icon: e.image ? "image" : "clip",
                thumb: e.image ? (thumbs[e.id] ?? "") : "",
                highlight: m?.indices ?? [],
                type: e.image ? "Image" : "Text",
                actLabel: "Copy",
                score: -i,
                run: () => Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", e.id]),
                remove: () => { remover.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", e.line]; remover.running = true; }
            });
            if (out.length >= (options.limit ?? 60)) break;
        }
        return out;
    }

    Process {
        id: lister
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [];
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab <= 0) continue;
                    const id = line.slice(0, tab), body = line.slice(tab + 1);
                    const img = body.match(/^\[\[ binary data (.+?) (png|jpe?g|webp|gif|bmp) (\d+x\d+) \]\]$/i);
                    list.push({ id, line, text: body, image: !!img, ext: img ? img[2].toLowerCase() : "", meta: img ? img[3] + " · " + img[1] + " · " + img[2].toUpperCase() : "" });
                }
                root.entries = list;
                root.loadedAt = Date.now();
                root.queueThumbs();
                root.resultsChanged();
            }
        }
    }
    Process { id: remover; onExited: root.refresh() }

    // thumbnails: decode the first few image entries, one process at a time. Decoded to a temp
    // name and renamed, so an Image (or a second shell instance) never reads a half-written file
    // ("Unable to read image data" in the log).
    property var pending: []
    function queueThumbs() {
        pending = entries.filter(e => e.image && !thumbs[e.id]).slice(0, 12);
        nextThumb();
    }
    function nextThumb() {
        if (thumber.running || !pending.length) return;
        const e = pending[0];
        pending = pending.slice(1);
        thumber.target = thumbDir + "/" + e.id + "." + (e.ext === "jpg" ? "jpeg" : e.ext);
        thumber.eid = e.id;
        thumber.command = ["sh", "-c", "mkdir -p \"$1\" && { [ -s \"$3\" ] || { cliphist decode \"$2\" > \"$3.$$\" && mv -f \"$3.$$\" \"$3\"; }; }", "sh", thumbDir, e.id, thumber.target];
        thumber.running = true;
    }
    Process {
        id: thumber
        property string target
        property string eid
        onExited: code => {
            if (code === 0) { root.thumbs = Object.assign({}, root.thumbs, { [eid]: "file://" + target }); root.resultsChanged(); }
            root.nextThumb();
        }
    }
}

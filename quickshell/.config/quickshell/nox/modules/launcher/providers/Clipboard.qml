import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// Clipboard history (cliphist). Prefix ":" (also `qs -c nox ipc call launcher clipboard`).
// Lists `cliphist list` (newest first) when the prefix is typed. The selected entry is shown in the
// launcher's preview card: images large (and as a row thumbnail), text in full (the list line is cut
// at 100 characters) - monospace when it looks like code, a swatch for a colour, the domain for a URL.
// Only rows the launcher will show are decoded: images once into ~/.cache/nox/clipboard-previews/
// <id>.png (re-encoded by magick, at most 1600 px; reused across restarts; files of entries no longer
// in cliphist are deleted on refresh; entries cliphist stored truncated are marked "unreadable"),
// text into memory, one batch of `cliphist decode` per query. Enter = `cliphist decode <id> | wl-copy`,
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
    property var have: ({})                 // id -> cached image file name (on disk)
    property var bodies: ({})               // id -> full text (first 6000 bytes)
    property real loadedAt: 0
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/nox/clipboard-previews"
    function fileUrl(name) { return "file://" + cacheDir + "/" + name; }

    function refresh() { if (!lister.running) lister.running = true; }

    // row type + icon: a lone colour or URL is labelled as such (the preview card shows it that way)
    function kind(t) {
        const s = t.trim();
        if (/^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(s) || /^(rgba?|hsla?)\([^)]*\)$/i.test(s)) return ["Colour", "palette"];
        if (/^https?:\/\/\S+$/i.test(s)) return ["Link", "link"];
        return ["Text", "clip"];
    }

    function query(text, prefixed) {
        if (!prefixed || !Config.moduleEnabled("clipboard")) return [];
        if (Date.now() - loadedAt > 1500) refresh();
        const q = text.toLowerCase();
        const out = [], shown = [];
        let i = 0;
        for (const e of entries) {
            i++;
            if (q && !(e.image ? (e.meta + " image").toLowerCase().includes(q) : e.text.toLowerCase().includes(q))) continue;
            shown.push(e);
            const m = q && !e.image ? Fuzzy.best(text, [[e.text, 1]]) : null;
            const body = bodies[e.id];
            const [type, icon] = e.image ? ["Image", "image"] : kind(body ?? e.text);
            const img = e.image && have[e.id] ? fileUrl(have[e.id]) : "";
            out.push({
                title: e.image ? "Image" : e.text.replace(/\s+/g, " ").slice(0, 160),
                sub: e.image ? e.meta + (failed[e.id] ? " · unreadable" : "") : "",
                icon,
                thumb: img,
                thumbSlot: e.image,
                preview: img,
                previewFit: true,
                previewText: e.image ? "" : (body ?? e.text),
                previewTitle: type,
                previewTag: e.image ? e.meta : body === undefined ? "" : body.length + (body.length >= 6000 ? "+" : "") + " chars · " + body.split("\n").length + (body.includes("\n") ? " lines" : " line"),
                highlight: m?.indices ?? [],
                type,
                actLabel: "Copy",
                key: e.id,
                score: -i,
                run: () => Quickshell.execDetached(["sh", "-c", "cliphist decode \"$1\" | wl-copy", "sh", e.id]),
                remove: () => { remover.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "sh", e.line]; remover.running = true; }
            });
            if (out.length >= (options.limit ?? 60)) break;
        }
        queueThumbs(shown.filter(e => e.image));
        queueBodies(shown.filter(e => !e.image));
        return out;
    }

    // cached previews ("C\t<file>") + the history ("L\t<id>\t<preview>")
    Process {
        id: lister
        command: ["sh", "-c", "mkdir -p \"$1\" && ls \"$1\" | sed 's/^/C\\t/'; cliphist list | sed 's/^/L\\t/'", "sh", root.cacheDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const list = [], ids = {}, files = [];
                for (const raw of text.split("\n")) {
                    if (raw.startsWith("C\t")) { files.push(raw.slice(2)); continue; }
                    if (!raw.startsWith("L\t")) continue;
                    const line = raw.slice(2);
                    const tab = line.indexOf("\t");
                    if (tab <= 0) continue;
                    const id = line.slice(0, tab), body = line.slice(tab + 1);
                    const img = body.match(/^\[\[ binary data (.+?) (png|jpe?g|webp|gif|bmp) (\d+x\d+) \]\]$/i);
                    ids[id] = true;
                    list.push({ id, line, text: body, image: !!img, ext: img ? img[2].toLowerCase() : "", meta: img ? img[3] + " · " + img[1] + " · " + img[2].toUpperCase() : "" });
                }
                // previews on disk: keep those still in the history, delete the rest (and stray temp
                // files, except the one being written right now)
                const have = {}, stale = [];
                for (const f of files) {
                    const m = f.match(/^(\d+)\.([a-z]+)$/);
                    if (m && ids[m[1]]) have[m[1]] = f;
                    else if (/^\d+\.[a-z]+(\.\d+)?$/.test(f) && !(thumber.running && f.startsWith(thumber.eid + ".")))
                        stale.push(root.cacheDir + "/" + f);
                }
                if (stale.length && !cleaner.running) { cleaner.command = ["rm", "-f", "--"].concat(stale); cleaner.running = true; }
                const bodies = {};
                for (const id in root.bodies) if (ids[id]) bodies[id] = root.bodies[id];
                root.entries = list;
                root.have = have;
                root.bodies = bodies;
                root.loadedAt = Date.now();
                root.resultsChanged();
            }
        }
    }
    Process { id: remover; onExited: root.refresh() }
    Process { id: cleaner }

    // ---- image previews: one decode at a time, only for listed rows. Re-encoded to a temp name
    // and renamed, so an Image (or a second shell instance) never reads a half-written file; magick
    // fails on a truncated image (some apps' copies end up cut at a 4 KiB boundary in cliphist), so
    // those never reach an Image ("Unable to read image data" in the log). ----
    property var pending: []
    property var failed: ({})               // ids that didn't decode (not retried this session)
    function queueThumbs(list) {
        pending = list.filter(e => !have[e.id] && !failed[e.id]);
        nextThumb();
    }
    function nextThumb() {
        while (pending.length && (have[pending[0].id] || failed[pending[0].id])) pending = pending.slice(1);
        if (thumber.running || !pending.length) return;
        const e = pending[0];
        pending = pending.slice(1);
        thumber.name = e.id + ".png";
        thumber.eid = e.id;
        thumber.command = ["sh", "-c", "mkdir -p \"$1\" && t=\"$1/$3.$$\" && cliphist decode \"$2\" | magick '-[0]' -resize '1600x1600>' -strip \"png:$t\" 2>/dev/null"
                           + " && mv -f \"$t\" \"$1/$3\" || { rm -f \"$t\"; exit 1; }",
                           "sh", cacheDir, e.id, thumber.name];
        thumber.running = true;
    }
    // a page of images finishes many decodes in a row: tell the launcher at most every 150 ms
    Timer { id: changed; interval: 150; onTriggered: root.resultsChanged() }
    Process {
        id: thumber
        property string name
        property string eid
        onExited: code => {
            if (code === 0) { root.have = Object.assign({}, root.have, { [eid]: name }); changed.restart(); }
            else { root.failed = Object.assign({}, root.failed, { [eid]: true }); changed.restart(); }
            root.nextThumb();
        }
    }

    // ---- full text: one batch of decodes for the listed rows not decoded yet. Records are
    // "\x1e<id>\x1f<text>" (separators that don't occur in copied text); a failed decode leaves ""
    // so it isn't retried. ----
    property var wantBodies: []
    function queueBodies(list) {
        wantBodies = list.filter(e => bodies[e.id] === undefined).map(e => e.id);
        if (wantBodies.length && !texter.running) {
            texter.command = ["sh", "-c", "for id; do printf '\\036%s\\037' \"$id\"; cliphist decode \"$id\" | head -c 6000; done", "sh"].concat(wantBodies);
            texter.running = true;
        }
    }
    Process {
        id: texter
        stdout: StdioCollector {
            onStreamFinished: {
                const b = Object.assign({}, root.bodies);
                for (const rec of text.split("\x1e")) {
                    const sep = rec.indexOf("\x1f");
                    if (sep > 0) b[rec.slice(0, sep)] = rec.slice(sep + 1).replace(/\n$/, "");
                }
                root.bodies = b;
                changed.restart();
            }
        }
        // rows that came into view while this batch ran get the next one
        onExited: Qt.callLater(() => { if (root.wantBodies.some(id => root.bodies[id] === undefined)) root.resultsChanged(); })
    }
}

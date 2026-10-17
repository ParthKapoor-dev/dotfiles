import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// Wallpapers (prefix "#"): every image under launcher.provider.wallpapers.directory (default
// ~/Pictures), recursively; hidden folders are skipped and so is Screenshots (skipScreenshots).
// Rows show the path relative to the directory with a thumbnail, and the selected one is shown large
// beside the list (result.preview); Enter sets the wallpaper
// (same as `nox wallpaper set`). Thumbnails are made lazily, one `magick` at a time and only
// for listed rows, cached in ~/.cache/nox/wallpaper-thumbs/<md5(path:mtime)>.png.
// The listing (`find`) runs when the prefix is typed, at most every 10 s.
Item {
    id: root
    property string providerId: "wallpapers"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Wallpapers"
    property string defaultPrefix: "#"
    property bool defaultPrefixOnly: true
    signal resultsChanged()

    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: String(options.directory ?? "~/Pictures").replace(/^~(?=\/|$)/, home).replace(/\/+$/, "")
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/nox/wallpaper-thumbs"
    property var files: []          // [{ path, rel, key }]
    property var have: ({})         // thumbnail keys already on disk
    property real loadedAt: 0

    function refresh() { if (!lister.running) lister.running = true; }
    function thumbPath(f) { return cacheDir + "/" + f.key + ".png"; }

    function query(text, prefixed) {
        if (!prefixed) return [];
        if (Date.now() - loadedAt > 10000) refresh();
        const out = [];
        for (const f of files) {
            const m = text ? Fuzzy.best(text, [[f.rel, 1]]) : { score: 0, indices: [] };
            if (!m) continue;
            const current = f.path === Wallpaper.path;
            out.push({
                title: f.rel,
                highlight: m.indices,
                thumb: have[f.key] ? "file://" + thumbPath(f) : "",
                thumbSlot: true,
                preview: "file://" + f.path,
                type: current ? "Current" : "Image",
                actLabel: "Set Wallpaper",
                score: m.score + (current ? 0.01 : 0),
                file: f,
                run: () => Wallpaper.set(f.path)
            });
        }
        // thumbnails only for what the launcher will actually show (same order as the launcher:
        // score, ties by position - V4's sort isn't stable, so the index is the tie-break)
        const shown = out.map((r, i) => [r, i]).sort((a, b) => (b[0].score - a[0].score) || (a[1] - b[1]));
        const lim = options.limit ?? 30;
        queue(shown.slice(0, lim > 0 ? lim : undefined).map(x => x[0].file));
        return out;
    }

    Process {
        id: lister
        // NUL-free tab output: mtime \t path. Hidden dirs pruned; Screenshots optional.
        command: ["sh", "-c",
            "mkdir -p \"$2\"; ls \"$2\" | sed -n 's/\\.png$//p' | sed 's/^/T\\t/';"
            + " skip=; [ \"$3\" = 1 ] && skip='-o -name Screenshots';"
            + " find -L \"$1\" -mindepth 1 \\( -name '.*' $skip \\) -prune -o -type f"
            + " \\( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.avif' \\) -printf 'F\\t%T@\\t%p\\n' 2>/dev/null",
            "sh", root.dir, root.cacheDir, (root.options.skipScreenshots ?? true) ? "1" : "0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const have = {}, files = [];
                for (const l of text.split("\n")) {
                    const f = l.split("\t");
                    if (f[0] === "T" && f[1]) have[f[1]] = true;
                    else if (f[0] === "F" && f.length >= 3) {
                        const path = f.slice(2).join("\t");
                        files.push({ path, rel: path.startsWith(root.dir + "/") ? path.slice(root.dir.length + 1) : path, key: Qt.md5(path + ":" + f[1]) });
                    }
                }
                files.sort((a, b) => a.rel.localeCompare(b.rel));
                root.files = files;
                root.have = have;
                root.loadedAt = Date.now();
                root.resultsChanged();
            }
        }
    }

    // ---- lazy thumbnails, one process at a time ----
    property var pending: []
    function queue(list) {
        pending = list.filter(f => have[f.key] === undefined);
        next();
    }
    function next() {
        while (pending.length && have[pending[0].key] !== undefined) pending = pending.slice(1);
        if (thumber.running || !pending.length) return;
        const f = pending[0];
        pending = pending.slice(1);
        thumber.key = f.key;
        // first frame only ([0]), cover-crop to 16:10; written to a temp name and renamed
        thumber.command = ["sh", "-c", "magick \"$1[0]\" -auto-orient -thumbnail 256x160^ -gravity center -extent 256x160 -strip \"$2.$$.png\" && mv -f \"$2.$$.png\" \"$2\"",
                           "sh", f.path, thumbPath(f)];
        thumber.running = true;
    }
    // a long list finishes many thumbnails in a row: tell the launcher at most every 150 ms
    Timer { id: changed; interval: 150; onTriggered: root.resultsChanged() }
    Process {
        id: thumber
        property string key
        onExited: code => {
            if (code === 0) { root.have = Object.assign({}, root.have, { [key]: true }); changed.restart(); }
            else root.have = Object.assign({}, root.have, { [key]: false });   // don't retry a broken file this session
            root.next();
        }
    }
}

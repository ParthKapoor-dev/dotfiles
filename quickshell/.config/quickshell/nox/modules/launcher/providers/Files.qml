import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// File search with fd. Prefix "~": "~ invoice" finds files and folders under the roots (default
// $HOME); a query with a "/" matches the whole path ("~ code/nox launcher"). Hidden folders, .gitignore'd
// paths and the exclude list (node_modules, .git, .cache, target, build, …) are skipped. Rows show the
// name, the folder it is in and a file-type icon; images get the large preview. Enter = xdg-open,
// Shift+Enter = show it in the file manager (FileManager1 ShowItems, else xdg-open on the folder).
// Opened files are remembered (frecency "files") and ranked first; an empty "~" lists them.
// fd runs asynchronously, debounced (debounce ms) after typing stops; a newer query kills the running
// one; maxResults caps what fd returns, the launcher's limit what is shown.
// options: roots, exclude, hidden, noIgnore, maxResults, debounce, recent, frecencyWeight, opener
Item {
    id: root
    property string providerId: "files"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Files"
    property string defaultPrefix: "~"
    property bool defaultPrefixOnly: true
    signal resultsChanged()

    readonly property string home: Quickshell.env("HOME")
    function expand(p) { return String(p).replace(/^~(?=\/|$)/, home).replace(/(.)\/+$/, "$1"); }
    function tilde(p) { return p === home ? "~" : p.startsWith(home + "/") ? "~" + p.slice(home.length) : p; }
    function fileUrl(p) { return "file://" + p.split("/").map(encodeURIComponent).join("/"); }
    readonly property var roots: (options.roots ?? ["~"]).map(expand)
    readonly property var excludes: options.exclude ?? ["node_modules", ".git", ".cache", "target", "build", "dist", "__pycache__", ".venv", "venv"]

    property string wanted: ""      // query the latest fd run is for
    property var found: []          // [{ path, name, dir, isDir }] of the last finished run
    property string foundFor: ""
    property var proc: null         // the running fd, if any
    property var alive: ({})        // recent path -> true/false (exists), checked when "~" is opened empty

    // ---- file kinds: icon (glyph or Material Symbols name) + type label ----
    readonly property var kinds: [
        [/\.(png|jpe?g|webp|gif|bmp|svg|avif|heic|tiff?|ico)$/i, "image", "Image"],
        [/\.pdf$/i, "picture_as_pdf", "PDF"],
        [/\.(mp4|mkv|webm|mov|avi|m4v)$/i, "movie", "Video"],
        [/\.(mp3|flac|ogg|opus|wav|m4a|aac)$/i, "music_note", "Audio"],
        [/\.(zip|tar|gz|tgz|xz|zst|bz2|7z|rar|iso)$/i, "folder_zip", "Archive"],
        [/\.(qml|js|ts|tsx|jsx|py|rs|go|c|h|cpp|hpp|java|kt|lua|sh|zsh|fish|rb|php|cs|swift|zig|nix|sql|css|scss|html|vue|svelte)$/i, "code", "Code"],
        [/\.(json|ya?ml|toml|ini|conf|cfg|xml|csv|tsv|env|lock)$/i, "data_object", "Data"],
        [/\.(md|txt|rst|org|log|tex)$/i, "note", "Text"],
        [/\.(docx?|odt|rtf|pages)$/i, "doc", "Document"],
        [/\.(xlsx?|ods|numbers)$/i, "table_chart", "Spreadsheet"],
        [/\.(pptx?|odp|key)$/i, "slideshow", "Slides"],
        [/\.(ttf|otf|woff2?)$/i, "font_download", "Font"],
        [/\.(appimage|exe|deb|rpm|pkg\.tar\.zst)$/i, "package_2", "Package"]
    ]
    function kind(f) {
        if (f.isDir) return ["folder", "Folder"];
        for (const k of kinds) if (k[0].test(f.name)) return [k[1], k[2]];
        return ["doc", "File"];
    }
    function entry(path) {
        const isDir = path.endsWith("/");
        const p = isDir ? path.replace(/\/+$/, "") : path;
        const cut = p.lastIndexOf("/");
        // key: frecency id; folders keep fd's trailing "/" so a recent one is still known as a folder
        return { path: p, key: isDir ? p + "/" : p, name: p.slice(cut + 1), dir: p.slice(0, Math.max(1, cut)), isDir };
    }

    function result(f, m, score) {
        const [icon, type] = kind(f);
        const image = type === "Image" && !/\.(heic|tiff?|ico)$/i.test(f.name);
        return {
            title: f.name,
            sub: tilde(f.dir),
            icon,
            type,
            highlight: m?.indices ?? [],
            actLabel: "Open",
            score,
            key: f.path,
            preview: image ? fileUrl(f.path) : "",
            previewFit: true,
            previewTag: tilde(f.dir),
            alt: () => root.reveal(f.path),
            altLabel: "Show in Folder",
            run: () => {
                Frecency.record("files", f.key);
                Quickshell.execDetached((options.opener ?? ["xdg-open"]).concat([f.path]));
            }
        };
    }
    // highlight the item in the file manager; folders it can't reach that way just open
    function reveal(path) {
        Quickshell.execDetached(["sh", "-c",
            "gdbus call --session --dest org.freedesktop.FileManager1 --object-path /org/freedesktop/FileManager1"
            + " --method org.freedesktop.FileManager1.ShowItems \"['$1']\" '' >/dev/null 2>&1 || xdg-open \"$2\"",
            "sh", fileUrl(path).replace(/'/g, "%27"), path.slice(0, Math.max(1, path.lastIndexOf("/")))]);
    }

    function query(text, prefixed) {
        if (!prefixed) return [];
        const q = text.trim();
        const w = (options.frecencyWeight ?? 1) * 40;
        if (!q) {
            wanted = "";
            const recent = Frecency.top("files", options.recent ?? 8);
            if (recent.some(p => alive[p] === undefined)) check(recent);
            return recent.filter(p => alive[p] !== false).map((p, i) => result(entry(p), null, 1000 - i));
        }
        if (q !== wanted || Date.now() - doneAt > 10000) { wanted = q; debounce.restart(); }
        // rank what fd found (for this query or, while it runs, the previous one) plus recent files
        // that match; the fuzzy match is on the name, then on the path
        const out = [], seen = {};
        const path = q.includes("/");
        const add = (f, recent) => {
            if (seen[f.path]) return;
            const m = Fuzzy.best(q, [[f.name, 1], [tilde(f.path), path ? 0.9 : 0.4]]);
            // fd's own match (all terms, in order) counts for its current query only
            if (!m && (recent || foundFor !== q)) return;
            seen[f.path] = true;
            const depth = f.path.split("/").length;
            out.push(result(f, m, (m?.score ?? 8) - depth * 0.4 + Frecency.score("files", f.key) * w));
        };
        for (const p of Frecency.top("files", 200)) if (alive[p] !== false) add(entry(p), true);
        for (const f of found) add(f, false);
        return out;
    }

    // ---- fd, one process per query; a newer query kills the older one and ignores its output ----
    property real doneAt: 0
    Timer { id: debounce; interval: root.options.debounce ?? 120; onTriggered: root.start() }
    function start() {
        if (proc) { proc.running = false; proc = null; }
        const q = wanted;
        if (!q) return;
        const path = q.includes("/");
        // terms in order, anything between ("inv 2026" -> inv.*2026); lowercase = case-insensitive
        const esc = s => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
        const pattern = (path ? expand(q.startsWith("~") ? q : q.replace(/^\//, "")) : q).split(/\s+/).map(esc).join(".*");
        const args = ["fd", "--color=never", "--absolute-path", "--type", "f", "--type", "d",
                      "--max-results", String(options.maxResults ?? 300)];
        if (options.hidden) args.push("--hidden");
        if (options.noIgnore) args.push("--no-ignore");
        if (path) args.push("--full-path");
        for (const x of excludes) args.push("--exclude", x);
        args.push("--", pattern);
        proc = fdRun.createObject(root, { q, command: args.concat(roots) });
        proc.running = true;
    }
    function finished(p, text) {
        if (p !== proc) return;               // superseded
        proc = null;
        found = text.split("\n").filter(l => l).map(entry);
        foundFor = p.q;
        doneAt = Date.now();
        resultsChanged();
    }
    Component {
        id: fdRun
        Process {
            id: run
            property string q
            stdout: StdioCollector { onStreamFinished: root.finished(run, text) }
            onExited: Qt.callLater(() => run.destroy())
        }
    }

    // recent files that were deleted or moved drop out of the list
    function check(paths) {
        if (checker.running) return;
        checker.paths = paths;
        checker.command = ["sh", "-c", "for f; do [ -e \"$f\" ] && printf '%s\\n' \"$f\"; done; true", "sh"].concat(paths);
        checker.running = true;
    }
    Process {
        id: checker
        property var paths: []
        stdout: StdioCollector {
            onStreamFinished: {
                const ok = new Set(text.split("\n"));
                const a = Object.assign({}, root.alive);
                for (const p of checker.paths) a[p] = ok.has(p);
                root.alive = a;
                root.resultsChanged();
            }
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// Default apps (prefix "!"): one row per category (Web Browser, File Manager, …) showing the app
// that currently opens it (`xdg-mime query default <first type>`). Enter on a category lists the
// installed apps whose .desktop MimeType names any of its types (current one first, "Current");
// Enter on an app makes it the default for ALL the category's types (`xdg-mime default`; the web
// browser also gets `xdg-settings set default-web-browser`) and goes back to the categories.
// Esc / Backspace on an empty filter (or the "Back" row) go back too. Typed text filters both levels.
// DesktopEntries has no MimeType, so a helper reads the .desktop files itself (XDG data dirs,
// first id wins, Hidden/NoDisplay skipped); names and icons still come from DesktopEntries.
// mimeapps.list as a symlink (dotfiles): the write goes to the link's target, the link stays.
// options: categories ([{ id, title, icon, types: [...] }] replaces the list below)
Item {
    id: root
    property string providerId: "defaults"
    readonly property var options: Config.launcherProvider(providerId)
    readonly property var cat: categories.find(c => c.id === catId) ?? null
    property string name: cat ? cat.title : "Default Apps"
    property string defaultPrefix: "!"
    property bool defaultPrefixOnly: true
    // a category is open: the launcher sends Esc / Backspace-on-empty to back()
    readonly property bool nested: cat !== null
    signal resultsChanged()

    readonly property var categories: options.categories ?? [
        { id: "browser", title: "Web Browser", icon: "globe", browser: true,
          types: ["x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml"] },
        { id: "files", title: "File Manager", icon: "folder", types: ["inode/directory"] },
        { id: "images", title: "Image Viewer", icon: "image",
          types: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp", "image/svg+xml"] },
        { id: "video", title: "Video Player", icon: "play",
          types: ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime", "video/x-msvideo"] },
        { id: "music", title: "Music Player", icon: "headphones",
          types: ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav", "audio/mp4", "audio/aac"] },
        { id: "pdf", title: "PDF Viewer", icon: "doc", types: ["application/pdf"] },
        { id: "text", title: "Text Editor", icon: "note",
          types: ["text/plain", "text/markdown", "application/json", "text/x-python", "application/x-shellscript"] },
        { id: "mail", title: "Email", icon: "send", types: ["x-scheme-handler/mailto"] }
    ]

    property string catId: ""
    property var current: ({})     // category id -> desktop id ("" = none), without ".desktop"
    property var apps: []          // [{ id, types: [...] }] from the .desktop scan
    property bool stale: true      // re-read the defaults (and the app list) once per launcher session

    // every session starts at the category list with fresh values (another tool may have changed
    // them). Reset on open as well: the launcher may have queried before this handler runs, so
    // resultsChanged makes it query again.
    Connections {
        target: Panels
        function onLauncherOpenChanged() {
            root.catId = "";
            root.stale = true;
            if (Panels.launcherOpen) root.resultsChanged();
        }
    }

    function back() { catId = ""; }

    function entry(id) { return id ? DesktopEntries.byId(id) : null; }
    function appName(id) { return entry(id)?.name || id; }
    function appIcon(id) { const e = entry(id); return e ? Quickshell.iconPath(e.icon, "application-x-executable") : ""; }

    function query(text, prefixed) {
        if (!prefixed) return [];
        if (stale) {
            stale = false;
            if (!reader.running) reader.running = true;
            if (!scanner.running) scanner.running = true;
        }
        return cat ? candidates(cat, text) : overview(text);
    }

    function overview(text) {
        const out = [];
        for (const c of categories) {
            const id = current[c.id] ?? "";
            const m = text ? Fuzzy.best(text, [[c.title, 1], [id ? appName(id) : "", 0.6]]) : { score: 0, indices: [] };
            if (!m) continue;
            out.push({
                title: c.title,
                sub: id ? appName(id) : current[c.id] === undefined ? "…" : "Not set",
                image: appIcon(id),
                icon: c.icon,
                highlight: m.indices,
                key: "defaults:" + c.id,
                type: "Default App",
                actLabel: "Choose",
                score: m.score,
                stay: true,
                run: () => { root.catId = c.id; }
            });
        }
        return out;
    }

    function candidates(c, text) {
        const cur = current[c.id] ?? "";
        const ids = apps.filter(a => a.types.some(t => c.types.includes(t))).map(a => a.id);
        if (cur && !ids.includes(cur)) ids.push(cur);   // a default that doesn't list the type itself
        const out = [];
        for (const id of ids) {
            const e = entry(id);
            const m = text ? Fuzzy.best(text, [[appName(id), 1], [id, 0.5]]) : { score: 0, indices: [] };
            if (!m) continue;
            const isCur = id === cur;
            out.push({
                title: appName(id),
                sub: e?.genericName || e?.comment || id + ".desktop",
                image: appIcon(id),
                icon: c.icon,
                highlight: m.indices,
                key: "defaults:" + c.id + ":" + id,
                type: isCur ? "Current" : "",
                actLabel: isCur ? "Keep" : "Set Default",
                // current first, then by name (ties keep this order)
                score: m.score + (isCur ? 1000 : 0),
                stay: true,
                run: () => root.setDefault(c, id)
            });
        }
        out.sort((a, b) => b.score - a.score || a.title.localeCompare(b.title));
        out.push({
            title: "Back",
            sub: "All categories",
            icon: "chevL",
            key: "defaults:back",
            actLabel: "Back",
            score: -1e9,
            stay: true,
            run: () => root.back()
        });
        return out;
    }

    // shown right away; the reader confirms what xdg-mime actually stored
    function setDefault(c, id) {
        catId = "";
        if (id === current[c.id]) return;
        current = Object.assign({}, current, { [c.id]: id });
        writer.queue = writer.queue.concat([[c.browser ? "1" : "0", id + ".desktop"].concat(c.types)]);
        writer.next();
    }

    // one `xdg-mime query default` per category (first type): "<category id>\t<desktop file>"
    Process {
        id: reader
        command: ["sh", "-c", "while [ $# -gt 0 ]; do printf '%s\\t%s\\n' \"$1\" \"$(xdg-mime query default \"$2\" 2>/dev/null)\"; shift 2; done",
                  "sh"].concat(...root.categories.map(c => [c.id, c.types[0]]))
        stdout: StdioCollector {
            onStreamFinished: {
                const cur = {};
                for (const l of text.split("\n")) {
                    const f = l.split("\t");
                    if (f.length >= 2 && f[0]) cur[f[0]] = f[1].trim().replace(/\.desktop$/, "");
                }
                root.current = cur;
                root.resultsChanged();
            }
        }
    }

    // .desktop files in XDG data dir order: "<id>\t<1 = hidden>\t<MimeType>". The id is the path
    // under applications/ with "/" -> "-"; the first occurrence of an id wins (a Hidden=true copy in
    // ~/.local/share hides the system one), so dedupe happens in order below.
    Process {
        id: scanner
        command: ["sh", "-c",
            "IFS=:; for d in \"${XDG_DATA_HOME:-$HOME/.local/share}\" ${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do"
            + " a=\"${d%/}/applications\"; [ -d \"$a\" ] || continue;"
            + " find -L \"$a\" -name '*.desktop' -type f -print0 2>/dev/null | xargs -0 -r awk -v base=\"$a/\" '"
            + "  function out() { if (id != \"\") print id \"\\t\" ((hide || !app) ? 1 : 0) \"\\t\" mime }"
            + "  FNR == 1 { out(); id = substr(FILENAME, length(base) + 1); gsub(\"/\", \"-\", id); sub(/\\.desktop$/, \"\", id); sec = \"\"; mime = \"\"; hide = 0; app = 0 }"
            + "  /^\\[/ { sec = $0; next }"
            + "  sec != \"[Desktop Entry]\" { next }"
            + "  /^MimeType[ \\t]*=/ { mime = $0; sub(/^[^=]*=[ \\t]*/, \"\", mime) }"
            + "  /^(Hidden|NoDisplay)[ \\t]*=[ \\t]*true/ { hide = 1 }"
            + "  /^Type[ \\t]*=[ \\t]*Application/ { app = 1 }"
            + "  END { out() }';"
            + " done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {}, apps = [];
                for (const l of text.split("\n")) {
                    const f = l.split("\t");
                    if (f.length < 3 || !f[0] || seen[f[0]]) continue;
                    seen[f[0]] = true;
                    if (f[1] === "1" || !f[2]) continue;
                    apps.push({ id: f[0], types: f[2].split(";").map(t => t.trim()).filter(t => t) });
                }
                root.apps = apps;
                root.resultsChanged();
            }
        }
    }

    // one write at a time (each rewrites mimeapps.list). A symlinked mimeapps.list: point
    // XDG_CONFIG_HOME at the link target's folder so xdg-mime rewrites the target (older xdg-utils
    // replaced the link with a plain file); a target not named mimeapps.list relies on xdg-utils
    // >= 1.2, which follows the link itself.
    Process {
        id: writer
        property var queue: []
        function next() {
            if (running || !queue.length) return;
            command = ["sh", "-c",
                "f=\"${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list\";"
                + " if [ -L \"$f\" ]; then r=$(readlink -f \"$f\"); [ \"${r##*/}\" = mimeapps.list ] && export XDG_CONFIG_HOME=\"${r%/*}\"; fi;"
                + " b=$1 app=$2; shift 2;"
                + " xdg-mime default \"$app\" \"$@\" || exit 1;"
                + " [ \"$b\" = 1 ] && { xdg-settings set default-web-browser \"$app\" || echo \"xdg-settings failed for $app\" >&2; };"
                + " exit 0",
                "sh"].concat(queue[0]);
            queue = queue.slice(1);
            running = true;
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("nox: default apps:", text.trim()) }
        onExited: code => {
            if (code !== 0) console.warn("nox: default apps: xdg-mime default failed, exit", code);
            if (queue.length) next();
            else if (!reader.running) reader.running = true;
        }
    }
}

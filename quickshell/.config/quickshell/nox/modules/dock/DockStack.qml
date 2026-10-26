pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.services

// A file stack's entries for the dock fan (DockFolder): the newest `count` entries of `path` by
// mtime, dotfiles and in-progress *.part / *.crdownload downloads skipped (and Firefox's empty
// placeholder next to its .part), then "Open in Files". Zero idle cost: the FolderListModel exists
// only while `active` (one threaded read when the fan opens, inotify on the folder while it is up,
// nothing at all while closed). `ready` once the first listing is in.
// entries: [{ kind: "file" | "dir" | "open", name, path, url, size, md5 (of url) }]
// thumbs: { md5: file URL } of the freedesktop thumbnails that exist for them
// (~/.cache/thumbnails/{normal,large}/<md5>.png), found by one `test -e` loop per listing change
// so missing ones don't put an Image warning per file in the shell log.
Scope {
    id: root
    property bool active: false
    property string path: ""
    property int count: 12

    LazyLoader {
        id: lister
        active: root.active && root.path !== ""
        FolderListModel {
            folder: Apps.fileUrl(root.path)
            sortField: FolderListModel.Time      // newest first
            showDirs: true
            showDirsFirst: false
            showDotAndDotDot: false
            showHidden: false
        }
    }
    property int rev: 0
    Connections {
        target: lister.item
        ignoreUnknownSignals: true
        function onStatusChanged() { root.rev++; }
        function onCountChanged() { root.rev++; }
        function onRowsInserted() { root.rev++; }
        function onRowsRemoved() { root.rev++; }
        function onModelReset() { root.rev++; }
    }
    readonly property bool ready: {
        rev;
        const m = lister.item;
        return !!m && m.status === FolderListModel.Ready;
    }
    readonly property var entries: {
        rev;
        const m = lister.item;
        if (!root.active) return [];
        const out = [];
        if (m && ready) {
            const names = {};
            for (let i = 0; i < m.count; i++) names[m.get(i, "fileName")] = true;
            for (let i = 0; i < m.count && out.length < root.count; i++) {
                const name = String(m.get(i, "fileName"));
                if (name.startsWith(".") || name.endsWith(".part") || name.endsWith(".crdownload")) continue;
                if (names[name + ".part"]) continue;
                const p = String(m.get(i, "filePath"));
                // a folder that doesn't exist leaves the model on its default folder
                if (p.slice(0, p.lastIndexOf("/")) !== root.path) break;
                const url = Apps.fileUrl(p);
                out.push({ kind: m.get(i, "fileIsDir") ? "dir" : "file", name, path: p, url, md5: Qt.md5(url), size: Number(m.get(i, "fileSize")) || 0 });
            }
        }
        out.push({ kind: "open", name: "Open in Files", path: root.path, url: "", md5: "", size: 0 });
        return out;
    }

    // ---- cached thumbnails ----
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/thumbnails/"
    property var thumbs: ({})
    onActiveChanged: if (!active) thumbs = {}
    onEntriesChanged: {
        const want = entries.filter(e => e.md5 && root.thumbs[e.md5] === undefined).map(e => e.md5);
        if (!active || !want.length) return;
        if (probe.running) { probe.again = true; return; }
        probe.ask = want;
        probe.running = true;
    }
    Process {
        id: probe
        property var ask: []
        property bool again: false
        command: ["sh", "-c", "for h; do for s in normal large; do f=\"$0$s/$h.png\"; [ -e \"$f\" ] && { echo \"$h $f\"; break; }; done; done", root.thumbDir].concat(ask)
        stdout: StdioCollector {
            onStreamFinished: {
                const t = Object.assign({}, root.thumbs);
                for (const h of probe.ask) t[h] = "";
                for (const l of text.split("\n")) {
                    const sp = l.indexOf(" ");
                    if (sp > 0) t[l.slice(0, sp)] = Apps.fileUrl(l.slice(sp + 1));
                }
                if (root.active) root.thumbs = t;
            }
        }
        onExited: if (again) { again = false; root.entriesChanged(); }
    }
}

pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.core

// Browser downloads in progress, for the bar island: *.part (Firefox / Zen) and *.crdownload
// (Chromium / Helium) files in downloads.directory (~/Downloads).
// Event-driven: FolderListModel watches the folder with QFileSystemWatcher (inotify on the
// directory: create / rename / delete wake it, writes into a file don't), so inotifywait isn't
// needed and nothing runs while no partial file exists. While one does, one `find` a second reads
// sizes + mtimes; a partial file untouched for 30 s is "stalled" (a paused download, or one a crash
// left behind) and doesn't count as live, and while every file is stalled the check slows to 15 s.
// The browser doesn't expose a total, so this gives bytes so far and the rate, never a percentage.
// A partial file that goes away and leaves its final file (non-empty) behind = finished: `done`
// holds { name, path } for downloads.doneSeconds (5) so the island can flash it.
// Nothing is logged: no file names go to the shell log.
// shell.json downloads.{directory, doneSeconds}
Singleton {
    id: root
    readonly property var opts: Config.opt.downloads ?? ({})
    readonly property string home: Quickshell.env("HOME")
    readonly property string dir: String(opts.directory ?? "~/Downloads").replace(/^~(?=\/|$)/, home).replace(/\/+$/, "")
    readonly property var suffixes: [".part", ".crdownload"]

    // [{ name (partial file), final (name it will get, "" = unknown yet), bytes, rate (B/s), stalled }]
    property var files: []
    property var done: null              // { name, path } of the download that just finished
    readonly property var moving: files.filter(f => !f.stalled)
    readonly property bool live: moving.length > 0
    readonly property real bytes: moving.reduce((a, f) => a + f.bytes, 0)
    readonly property real rate: moving.reduce((a, f) => a + f.rate, 0)
    readonly property bool pending: folder.count > 0   // some partial file exists (polling on)

    function finalName(n) {
        for (const s of suffixes) if (n.endsWith(s)) n = n.slice(0, -s.length);
        // Chromium's placeholder before it knows the name ("Unconfirmed 123456")
        return /^Unconfirmed \d+$/.test(n) ? "" : n;
    }
    // 1.2 MB / 340 KB (decimal, like the browsers)
    function human(b) {
        if (b < 1000) return Math.round(b) + " B";
        const u = ["KB", "MB", "GB", "TB"];
        let i = -1;
        do { b /= 1000; i++; } while (b >= 1000 && i < u.length - 1);
        return (b < 10 ? b.toFixed(1) : Math.round(b)) + " " + u[i];
    }
    function openFolder() { Quickshell.execDetached(["xdg-open", dir]); }
    function openDone() { if (done?.path) Quickshell.execDetached(["xdg-open", done.path]); }

    FolderListModel {
        id: folder
        folder: "file://" + root.dir
        nameFilters: ["*.part", "*.crdownload"]
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        showOnlyReadable: true
        sortField: FolderListModel.Unsorted
    }
    // the folder's set of partial files changed (count alone misses a rename): scan now
    Connections {
        target: folder
        function onRowsInserted() { scanSoon.restart(); }
        function onRowsRemoved() { scanSoon.restart(); }
        function onModelReset() { scanSoon.restart(); }
        function onCountChanged() { scanSoon.restart(); }
    }
    Timer { id: scanSoon; interval: 60; onTriggered: root.scan() }
    onPendingChanged: if (!pending) { poll.stop(); scanSoon.restart(); }

    // size poll: only while a partial file exists
    Timer {
        id: poll
        interval: root.live ? 1000 : 15000
        repeat: true
        running: root.pending
        onTriggered: root.scan()
    }
    function scan() {
        if (sizer.running) { again = true; return; }
        if (!pending) { apply([]); return; }
        sizer.running = true;
    }
    property bool again: false
    property var seen: ({})              // name -> { bytes, at, rate } from the previous scan
    Process {
        id: sizer
        property var out: []
        command: ["find", root.dir, "-maxdepth", "1", "-type", "f", "(", "-name", "*.part", "-o", "-name", "*.crdownload", ")", "-printf", "%s\\t%T@\\t%f\\n"]
        onStarted: out = []
        stdout: SplitParser { onRead: line => sizer.out.push(line) }
        onExited: {
            root.apply(out.map(l => l.split("\t")).filter(p => p.length >= 3)
                .map(p => ({ bytes: Number(p[0]) || 0, mtime: Number(p[1]) * 1000 || 0, name: p.slice(2).join("\t") })));
            if (root.again) { root.again = false; running = true; }
        }
    }
    function apply(list) {
        const t = Date.now();
        const next = {}, out = [];
        for (const f of list) {
            const p = seen[f.name];
            let rate = 0;
            if (p && t > p.at) {
                const inst = Math.max(0, (f.bytes - p.bytes) * 1000 / (t - p.at));
                rate = p.rate > 0 ? p.rate * 0.6 + inst * 0.4 : inst;   // smoothed
            }
            next[f.name] = { bytes: f.bytes, at: t, rate };
            out.push({ name: f.name, final: finalName(f.name), bytes: f.bytes, rate, stalled: t - f.mtime > 30000 });
        }
        // gone since last time: finished if the final file is there, otherwise cancelled / renamed
        const gone = Object.keys(seen).filter(n => !next[n]).map(n => finalName(n)).filter(n => n !== "");
        if (gone.length) {
            checker.command = ["sh", "-c", "for f; do [ -s \"$f\" ] && printf '%s\\n' \"$f\"; done; exit 0", "sh"].concat(gone.map(n => dir + "/" + n));
            checker.running = true;
        }
        seen = next;
        files = out;
    }
    Process {
        id: checker
        stdout: SplitParser {
            onRead: line => {
                root.done = { name: line.slice(line.lastIndexOf("/") + 1), path: line };
                doneOff.interval = Math.max(1, Number(root.opts.doneSeconds ?? 5)) * 1000;
                doneOff.restart();
            }
        }
    }
    Timer { id: doneOff; onTriggered: root.done = null }
    function dismiss() { done = null; doneOff.stop(); }
}

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Hubstaff time tracker (bar widget "hubstaff"), through the CLI that ships with the Linux client:
// `~/Hubstaff/HubstaffCLI.bin.x86_64 send status` -> {"tracking", "active_project": {"name",
// "tracked_today": "H:MM:SS"}, "active_task": {"name"}} in ~25 ms, local only (talks to the running
// client; never --autostart here). Polled every widgets.hubstaff.interval ms (default 30000) and
// right away when the popover opens; between polls the time is counted on locally while tracking.
// tracked_today is the active project's time today. `available` = the client is running and answers;
// the bar widget is hidden otherwise.
// widgets.hubstaff.cli: path override for the CLI binary.
Singleton {
    id: root
    readonly property var opts: Config.widget("hubstaff")
    readonly property string cli: (opts.cli ?? "~/Hubstaff/HubstaffCLI.bin.x86_64").replace(/^~/, Quickshell.env("HOME"))

    property bool available: false
    property bool tracking: false
    property string project: ""
    property string task: ""
    property string stopReason: ""
    property int todaySec: 0             // at the last poll
    property real polledAt: 0
    property bool busy: false
    // seconds today, counted on between polls while tracking
    property int now: 0
    readonly property int today: todaySec + (tracking && polledAt > 0 ? Math.max(0, Math.floor((now - polledAt) / 1000)) : 0)

    function fmt(sec, withSeconds) {
        const h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), s = sec % 60;
        return h + ":" + String(m).padStart(2, "0") + (withSeconds ? ":" + String(s).padStart(2, "0") : "");
    }
    function parseHms(t) {
        const p = String(t ?? "").split(":").map(Number);
        if (p.length !== 3 || p.some(isNaN)) return 0;
        return p[0] * 3600 + p[1] * 60 + p[2];
    }

    function refresh() { if (!poll.running) poll.running = true; }
    function run(args) {
        if (busy) return;
        busy = true;
        action.command = [cli, "send"].concat(args);
        action.running = true;
    }
    function stop() { run(["stop"]); }
    function resume() { run(["resume"]); }
    function openApp() {
        Quickshell.execDetached(["sh", "-c", "exec \"${1%/*}/HubstaffClient.bin.x86_64\"", "sh", cli]);
    }

    Process {
        id: poll
        // only while the client runs (no process = widget hidden, the CLI is never asked)
        command: ["sh", "-c", "pgrep -f HubstaffClient.bin >/dev/null || exit 3; exec timeout 5 \"$1\" send status", "sh", root.cli]
        stdout: StdioCollector {
            onStreamFinished: {
                let j = null;
                try { j = JSON.parse(text); } catch (e) {}
                if (!j || typeof j.tracking !== "boolean") { root.available = false; return; }
                root.available = true;
                root.tracking = j.tracking;
                root.project = j.active_project?.name ?? "";
                root.task = j.active_task?.name ?? "";
                root.stopReason = j.reason ?? j.stop_reason ?? "";
                root.todaySec = root.parseHms(j.active_project?.tracked_today);
                root.polledAt = Date.now();
                root.now = Date.now();
            }
        }
        onExited: code => { if (code !== 0) root.available = false; }
    }
    Process {
        id: action
        onExited: { root.busy = false; root.refresh(); }
    }
    Timer {
        running: true; repeat: true; triggeredOnStart: true
        interval: Math.max(5000, root.opts.interval ?? 30000)
        onTriggered: root.refresh()
    }
    // local count between polls (the bar shows minutes; the popover seconds)
    Timer {
        running: root.tracking
        interval: 1000; repeat: true
        onTriggered: root.now = Date.now()
    }
}

pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Coding-agent sessions for Mission Control (modules/agents) and the bar dot (widget "agents").
// Source: the Claude Code hook ~/.local/lib/nox/agent-hook writes one JSON file per session to
// $XDG_RUNTIME_DIR/nox/agents and rewrites .stamp on every call; this watches .stamp (inotify, no
// polling) and re-reads the folder (debounced). While any session is alive a 5 s check marks
// sessions whose process died as ended; ended ones are dropped after agents.keepEndedMinutes (10).
// Tokens / context % / cost come from `nox agents usage` (transcripts, incremental), only while
// the overlay is open (every agents.usageInterval ms, 3000) - never from the hook.
// A session that starts waiting for a permission while the overlay is closed sends one
// notification (agents.notify, true) with an Open action.
// shell.json "agents": { notify, keepEndedMinutes, usageInterval, prices, contextWindow }
Singleton {
    id: root

    readonly property var opts: Config.opt.agents ?? ({})
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nox/agents"
    readonly property string lib: Quickshell.env("NOX_LIB") || (Quickshell.env("HOME") + "/.local/lib/nox")

    property var sessions: []            // parsed state files, display order
    property var usage: ({})             // id -> { ctx, window, pct, cost, model, title, say }
    property var today: ({ cost: 0, tokens: 0 })
    property var dead: ({})              // id -> ms first seen dead
    property bool loaded: false

    // overlay state (modules/agents)
    property bool open: false
    property string focusId: ""          // tile to select on open
    function toggle() { if (open) close(); else show(""); }
    function show(id) { focusId = id ?? ""; open = true; refreshUsage(); }
    function close() { open = false; }

    readonly property var alive: sessions.filter(s => s.status !== "ended")
    readonly property int working: alive.filter(s => s.status === "working").length
    readonly property int needsYou: alive.filter(s => s.status === "needs-you").length
    readonly property int errors: alive.filter(s => s.status === "error").length
    readonly property bool any: alive.length > 0

    // ---- reading ----
    Process {
        id: init
        running: true
        command: ["sh", "-c", "mkdir -p \"$1\" && chmod 700 \"$1\" && touch \"$1/.stamp\"", "sh", root.dir]
        onExited: { stampView.path = root.dir + "/.stamp"; root.reload(); }
    }
    FileView {
        id: stampView
        watchChanges: true
        printErrors: false
        onFileChanged: debounce.restart()
    }
    Timer { id: debounce; interval: 90; onTriggered: root.reload() }
    function reload() { if (reader.running) again = true; else reader.running = true; }
    property bool again: false
    Process {
        id: reader
        command: ["sh", "-c", "for f in \"$1\"/*.json; do [ -f \"$f\" ] && { cat \"$f\"; echo; }; done; exit 0", "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (!line.trim()) continue;
                    try { const s = JSON.parse(line); if (s && s.id) out.push(s); } catch (e) {}
                }
                root.apply(out);
            }
        }
        onExited: if (root.again) { root.again = false; running = true; }
    }

    readonly property var rank: ({ "needs-you": 0, "error": 1, "working": 2, "done": 3, "ended": 4 })
    function apply(list) {
        const now = Date.now();
        for (const s of list) {
            if (s.status !== "ended" && dead[s.id]) s.status = "ended", s.deadAt = dead[s.id];
        }
        // stable: oldest session first, ended ones last
        list.sort((a, b) => ((a.status === "ended") - (b.status === "ended")) || (a.started - b.started) || (a.id < b.id ? -1 : 1));
        const prev = {};
        for (const s of sessions) prev[s.id] = s;
        if (loaded && (opts.notify ?? true)) {
            for (const s of list) {
                const p = prev[s.id];
                if (s.status === "needs-you" && s.perm && (!p || p.status !== "needs-you" || (p.perm?.at ?? 0) !== s.perm.at))
                    notifyNeed(s);
            }
        }
        sessions = list;
        loaded = true;
        if (open) usageSoon.restart();
    }

    // ---- liveness: only while something is alive ----
    Timer {
        interval: 5000
        repeat: true
        running: root.any
        triggeredOnStart: true
        onTriggered: if (!checker.running) {
            checker.command = ["bash", "-c",
                "for a; do IFS=: read -r id pid st <<< \"$a\"; s=; read -r s < /proc/$pid/stat 2>/dev/null; r=${s##*) }; set -- $r; " +
                "if [ -z \"$s\" ] || { [ -n \"$st\" ] && [ \"${20}\" != \"$st\" ]; }; then echo \"$id\"; fi; done", "_"]
                .concat(root.alive.filter(s => s.pid).map(s => s.id + ":" + s.pid + ":" + (s.pidStart ?? "")));
            checker.running = true;
        }
    }
    Process {
        id: checker
        stdout: StdioCollector {
            onStreamFinished: {
                const ids = text.split("\n").filter(x => x);
                if (!ids.length) return;
                const d = Object.assign({}, root.dead);
                for (const id of ids) if (!d[id]) d[id] = Date.now();
                root.dead = d;
                root.apply(root.sessions.slice());
            }
        }
    }
    // drop ended sessions after keepEndedMinutes (the files live in RAM; the hook recreates them)
    Timer {
        interval: 60000
        repeat: true
        running: root.sessions.some(s => s.status === "ended")
        onTriggered: {
            const keep = (root.opts.keepEndedMinutes ?? 10) * 60000, now = Date.now();
            const old = root.sessions.filter(s => s.status === "ended" && now - Math.max(s.updated ?? 0, s.deadAt ?? 0) > keep);
            if (!old.length) return;
            Quickshell.execDetached(["rm", "-f"].concat(old.map(s => root.dir + "/" + s.id + ".json")));
        }
    }

    // ---- usage (transcripts) while the overlay is open ----
    function refreshUsage() { if (!usageProc.running) usageProc.running = true; }
    Timer { id: usageSoon; interval: 400; onTriggered: root.refreshUsage() }
    Timer {
        interval: Math.max(1000, root.opts.usageInterval ?? 3000)
        repeat: true
        running: root.open && root.any
        onTriggered: root.refreshUsage()
    }
    Process {
        id: usageProc
        command: [root.lib + "/agents", "usage"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const j = JSON.parse(text);
                    root.usage = j.sessions ?? {};
                    root.today = j.today ?? { cost: 0, tokens: 0 };
                } catch (e) {}
            }
        }
    }

    // ---- notification: one per permission request, with an Open action ----
    Component {
        id: noteC
        Process {
            id: np
            property string sid
            stdout: StdioCollector { onStreamFinished: if (text.trim() === "open") root.show(np.sid) }
            onExited: destroy()
        }
    }
    function notifyNeed(s) {
        if (open) return;
        const title = (s.project || "agent") + " · " + kindName(s) + " needs you";
        const p = s.perm ?? {};
        const body = [p.desc, p.cmd].filter(x => x).join(" · ") || (p.tool ? "Permission: " + p.tool : "Waiting for your answer");
        const proc = noteC.createObject(root, { sid: s.id });
        proc.command = ["notify-send", "-a", kindName(s), "-i", "utilities-terminal",
            "-A", "open=Open", "--wait", title, body];
        proc.running = true;
    }

    // ---- helpers shared by the overlay and the bar ----
    function kindName(s) { return s?.kind === "orca" ? "Orca" : s?.kind === "expai" ? "expai" : "Claude Code"; }
    function modelName(m) {
        const x = String(m ?? "").toLowerCase().match(/(opus|sonnet|haiku|fable|mythos)[-_ ]?(\d+(?:[-.]\d+)?)?/);
        return x ? (x[1] + (x[2] ? " " + x[2].replace("-", ".") : "")) : "";
    }
    function hms(ms) {
        let s = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60);
        s = s % 60;
        const p = n => (n < 10 ? "0" : "") + n;
        return h ? h + ":" + p(m) + ":" + p(s) : m + ":" + p(s);
    }
    function fmtTok(n) { n = n ?? 0; return n >= 1e6 ? (n / 1e6).toFixed(2) + "M" : n >= 1000 ? (n / 1000).toFixed(1) + "k" : String(n); }
    function byId(id) { return sessions.find(s => s.id === id) ?? null; }
}

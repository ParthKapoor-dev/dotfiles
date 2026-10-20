pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

// Coding-agent sessions for the agents panel (bar dot "agents" + Ctrl+Super+M: Needs you / Done /
// Working, modules/agents/AgentsPanel) and the full-screen grid (modules/agents/AgentsView, "expand").
// Source: the Claude Code hook ~/.local/lib/nox/agent-hook writes one JSON file per session to
// $XDG_RUNTIME_DIR/nox/agents and rewrites .stamp on every call; this watches .stamp (inotify, no
// polling) and re-reads the folder (debounced). While any session is alive a 5 s check marks
// sessions whose process died as ended; ended ones are dropped after agents.keepEndedMinutes (10).
// Tokens / context % / cost come from `nox agents usage` (transcripts, incremental), only while
// the panel or the grid is open (every agents.usageInterval ms, 3000) - never from the hook.
// Done cards: when a turn ends, `nox agents turn <id>` (off the hook path) gives its diff stat
// since the prompt, files, PR link and summary; a card stays until dismissed (D) or the next turn.
// Actions (all user-triggered): jump (focus the session's window / Orca tab / tmux client),
// reply (Orca: orca terminal send; tmux: paste-buffer + Enter; plain terminals: focus + paste
// without Enter), openDiff, openPr, dismiss, launch (launcher provider "agent").
// Answer seam: answer(id, choice) -> `nox agents answer`, which runs an optional backend
// (~/.local/lib/nox/agent-answer); without one it jumps to the session instead.
// Notifications (agents.notify, true): needs you -> Jump / Show; turn done (agents.notifyDone, true,
// turns longer than agents.notifyDoneAfter s, 20, and not while that session's window is focused)
// -> Open diff / Reply / Jump.
// shell.json "agents": { notify, notifyDone, notifyDoneAfter, keepEndedMinutes, usageInterval, prices,
//   contextWindow, roots, repoDepth, launch, tmux, diff, command, ghPr }
Singleton {
    id: root

    readonly property var opts: Config.opt.agents ?? ({})
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nox/agents"
    readonly property string lib: Quickshell.env("NOX_LIB") || (Quickshell.env("HOME") + "/.local/lib/nox")
    readonly property string helper: lib + "/agents"

    property var sessions: []            // parsed state files, display order
    property var usage: ({})             // id -> { ctx, window, pct, cost, model, title, say }
    property var today: ({ cost: 0, tokens: 0 })
    property var dead: ({})              // id -> ms first seen dead
    property var turns: ({})             // id -> `nox agents turn` result (last finished turn)
    property var dismissed: ({})         // id -> turn.at of the dismissed Done card
    property bool loaded: false

    // ---- panel (a bar popover) and grid ----
    readonly property string popupId: "bar:agents"
    readonly property bool panelOpen: Panels.popup === popupId
    property bool gridOpen: false
    readonly property bool open: panelOpen || gridOpen     // something on screen shows the sessions
    property string focusId: ""          // item to select on open
    property string replyId: ""          // open the reply box on this session (panel)
    property int openSerial: 0           // bumps on every show() (the panel re-selects)
    function toggle() { if (panelOpen) close(); else show(""); }
    function show(id, reply) {
        focusId = id ?? ""; replyId = reply ? (id ?? "") : "";
        openSerial++;
        gridOpen = false;
        // no bar (or no agents widget in it): the grid is the only surface
        if (!Panels.exists(popupId)) { gridOpen = true; refreshUsage(); return; }
        Panels.open(popupId);
        refreshUsage();
    }
    function close() { Panels.close(popupId); gridOpen = false; }
    function expand(id) { focusId = id ?? ""; Panels.close(popupId); gridOpen = true; refreshUsage(); }
    function closeGrid() { gridOpen = false; }

    readonly property var alive: sessions.filter(s => s.status !== "ended")
    readonly property int working: alive.filter(s => s.status === "working").length
    readonly property int needsYou: alive.filter(s => s.status === "needs-you").length
    readonly property int errors: alive.filter(s => s.status === "error").length
    readonly property bool any: alive.length > 0
    // panel sections
    readonly property var needList: alive.filter(s => s.status === "needs-you" || s.status === "error")
        .sort((a, b) => ((a.status === "error") - (b.status === "error")) || ((a.since ?? 0) - (b.since ?? 0)))
    readonly property var doneList: alive.filter(s => s.status === "done" && hasCard(s))
        .sort((a, b) => (b.turn?.end ?? 0) - (a.turn?.end ?? 0))
    readonly property var workList: alive.filter(s => s.status === "working")
    readonly property int doneCount: doneList.length
    function hasCard(s) { return !!(s?.turn?.end) && dismissed[s.id] !== s.turn.at; }

    // ---- reading ----
    Process {
        id: init
        running: true
        command: ["sh", "-c", "mkdir -p \"$1\" && chmod 700 \"$1\" && touch \"$1/.stamp\" && cat \"$1/.dismissed.json\" 2>/dev/null; exit 0", "sh", root.dir]
        stdout: StdioCollector { onStreamFinished: { try { const d = JSON.parse(text); if (d && typeof d === "object") root.dismissed = d; } catch (e) {} } }
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
        for (const s of list) {
            if (s.status !== "ended" && dead[s.id]) s.status = "ended", s.deadAt = dead[s.id];
        }
        // stable: oldest session first, ended ones last
        list.sort((a, b) => ((a.status === "ended") - (b.status === "ended")) || (a.started - b.started) || (a.id < b.id ? -1 : 1));
        const prev = {};
        for (const s of sessions) prev[s.id] = s;
        for (const s of list) {
            const p = prev[s.id];
            // a finished turn: fetch its card (diff stat, PR) once per turn
            if (s.turn?.end && s.status !== "ended") {
                const k = s.turn.at + ":" + s.turn.end + ":" + (s.turn.pr ?? "");
                if (turnKeys[s.id] !== k) {
                    turnKeys[s.id] = k;
                    const fresh = loaded && p && p.turn?.end !== s.turn.end && s.status === "done";
                    fetchTurn(s.id, fresh && (opts.notifyDone ?? true) && (opts.notify ?? true) && shouldNotifyDone(s));
                }
            }
            if (loaded && (opts.notify ?? true) && s.status === "needs-you" && s.perm
                && (!p || p.status !== "needs-you" || (p.perm?.at ?? 0) !== s.perm.at))
                notifyNeed(s);
        }
        sessions = list;
        loaded = true;
        if (open) usageSoon.restart();
    }
    property var turnKeys: ({})

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
            Quickshell.execDetached(["rm", "-f"].concat(old.map(s => root.dir + "/" + s.id + ".json"))
                .concat(old.map(s => root.dir + "/.turn-" + s.id + ".json")));
        }
    }

    // ---- usage (transcripts) while something is open ----
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
        command: [root.helper, "usage"]
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

    // ---- running the helper: run(args, cb(code, stdout)) ----
    Component {
        id: procC
        Process {
            id: p
            property var cb: null
            property string out: ""
            property int code: 0
            property int waits: 2
            function step() { if (--waits === 0) { try { if (cb) cb(code, out); } catch (e) { console.warn("nox agents:", e); } destroy(); } }
            stdout: StdioCollector { onStreamFinished: { p.out = text; p.step(); } }
            onExited: (code, status) => { p.code = code; p.step(); }
        }
    }
    function run(argv, cb) {
        const p = procC.createObject(root, { cb: cb ?? null });
        p.command = argv;
        p.running = true;
        return p;
    }
    function helperRun(args, cb) { return run([helper].concat(args), cb); }
    function parse(out) { try { return JSON.parse(out); } catch (e) { return {}; } }

    // ---- Done cards ----
    function fetchTurn(id, notify) {
        helperRun(["turn", id], (code, out) => {
            const t = parse(out);
            if (!t || !t.id) return;
            const m = Object.assign({}, turns);
            m[id] = t;
            turns = m;
            if (notify) notifyDone(byId(id), t);
        });
    }
    function dismiss(id) {
        const s = byId(id);
        if (!s?.turn) return;
        const d = Object.assign({}, dismissed);
        // keep only live sessions in the file
        for (const k of Object.keys(d)) if (!byId(k)) delete d[k];
        d[id] = s.turn.at;
        dismissed = d;
        Quickshell.execDetached(["sh", "-c", "umask 077; printf '%s' \"$2\" > \"$1.tmp\" && mv -f \"$1.tmp\" \"$1\"", "sh", dir + "/.dismissed.json", JSON.stringify(d)]);
    }
    function stat(t) {
        if (!t) return "";
        const n = t.nfiles ?? (t.files ?? []).length;
        if (!n) return "No file changes";
        return "+" + (t.add ?? 0) + " −" + (t.del ?? 0) + " · " + n + (n === 1 ? " file" : " files") + (t.exact === false ? " ~" : "");
    }

    // ---- actions ----
    function jump(id) {
        const s = byId(id);
        close();
        if (!s) return;
        // a frame for the popover to give the keyboard back first
        Qt.callLater(() => helperRun(["focus", id], (code, out) => {
            if (code !== 0) Panels.hud(s.bg ? "Background session · no window" : "No window for this session", "x");
        }));
    }
    function openDiff(id) {
        close();
        helperRun(["diff", id], (code, out) => { if (code !== 0) Panels.hud(parse(out).error || "Couldn't open the diff", "x"); });
    }
    function openPr(url) { if (!url) return; close(); Quickshell.execDetached(["xdg-open", url]); }
    function canReply(s) { return !!s && (s.status === "done" || s.status === "working" || s.status === "error"); }
    // how a reply reaches this session (for the reply box hint)
    function replyRoute(s) {
        if (s?.kind === "orca" && s?.orca?.handle) return "orca";
        if (s?.tmux?.pane) return "tmux";
        return "window";
    }
    signal replied(string id, bool ok)
    function reply(id, text) {
        text = String(text ?? "").trim();
        const s = byId(id);
        if (!s || !text) return;
        helperRun(["send", id, "--", text], (code, out) => {
            const r = parse(out);
            if (code === 0) { Panels.hud("Sent to " + (s.project || "agent"), "send"); replied(id, true); return; }
            if (code === 3) { pasteIntoWindow(s, text); replied(id, true); return; }
            if (code === 4) { Panels.hud(r.refused === "needs-you" ? "It's waiting on a prompt · answer it there" : "Session " + (r.refused ?? "gone"), "x"); replied(id, false); if (r.refused === "needs-you") jump(id); return; }
            Panels.hud("Reply failed" + (r.error ? " · " + r.error : ""), "x");
            replied(id, false);
        });
    }
    // plain terminals have no remote input: focus the session's window, put the text on the
    // clipboard and paste it (no Enter: the text waits in the prompt for you to send)
    function pasteIntoWindow(s, text) {
        close();
        helperRun(["focus", s.id, "--dry-run"], (code, out) => {
            const w = parse(out).window;
            if (!w?.address) { Quickshell.execDetached(["wl-copy", "--", text]); Panels.hud("No window · reply copied", "clip"); return; }
            Hypr.focusWindow(w.address);
            Quickshell.execDetached(["wl-copy", "--", text]);
            pasteLater.addr = w.address;
            pasteLater.term = Pins.terminals.test(String(w.class ?? ""));
            pasteLater.restart();
        });
    }
    Timer {
        id: pasteLater
        property string addr: ""
        property bool term: true
        interval: 220
        onTriggered: { Pins.sendPaste(addr, term); Panels.hud("Pasted · press Enter to send", "clip"); }
    }
    // launcher provider "agent": start Claude in dir with the task (mode: orca | ghostty)
    function launch(dir, task, mode) {
        helperRun(["start", "--mode", mode || (opts.launch ?? "ghostty"), dir, task], (code, out) => {
            const r = parse(out);
            const name = String(dir).replace(/\/+$/, "").replace(/^.*\//, "");
            if (code !== 0 || !r.ok) { Panels.hud("Couldn't start the agent" + (r.error ? " · " + r.error : ""), "x"); return; }
            if (r.note) Quickshell.execDetached(["notify-send", "-a", "Agents", "-i", "utilities-terminal", "Started in Ghostty", r.note]);
            Panels.hud((r.mode === "orca" ? "Orca worktree · " : "Claude · ") + name, "sparkle");
        });
    }

    // ---- answer seam: allow / deny a pending permission from nox ----
    // A backend plugs in as ~/.local/lib/nox/agent-answer <session-id> <choice> <state-file>
    // (see `nox agents answer`). Until one exists (or it can't deliver), this jumps to the session.
    readonly property bool answerBackend: false
    function canAnswer(s) { return answerBackend && s?.status === "needs-you" && !!s?.perm; }
    function answer(id, choice) {
        helperRun(["answer", id, choice], (code, out) => {
            if (code === 0) { Panels.hud(choice === "deny" ? "Denied" : "Allowed", choice === "deny" ? "x" : "check"); return; }
            jump(id);
        });
    }

    // ---- notifications (actions come back on stdout: notify-send --wait) ----
    function notifyAct(s, argv, onAction) {
        run(argv, (code, out) => onAction(out.trim()));
    }
    function notifyNeed(s) {
        if (open) return;
        const title = (s.project || "agent") + " · " + kindName(s) + " needs you";
        const p = s.perm ?? {};
        const body = [p.desc, p.cmd].filter(x => x).join(" · ") || (p.tool ? "Permission: " + p.tool : "Waiting for your answer");
        notifyAct(s, ["notify-send", "-a", kindName(s), "-i", "utilities-terminal",
            "-A", "default=Show", "-A", "jump=Jump", "-A", "open=Show", "--wait", title, body], a => {
            if (a === "jump") jump(s.id);
            else if (a === "open" || a === "default") show(s.id);
        });
    }
    function shouldNotifyDone(s) {
        if (open) return false;
        const dur = (s.turn?.end ?? 0) - (s.turn?.at ?? 0);
        if (dur < (opts.notifyDoneAfter ?? 20) * 1000) return false;
        // you're looking at it: no notification
        const pid = Hyprland.activeToplevel?.lastIpcObject?.pid ?? -1;
        return !(s.chain ?? []).includes(pid);
    }
    function notifyDone(s, t) {
        if (!s || open) return;
        const title = (s.project || "agent") + " · done";
        const body = [String(t.say || s.summary || "Turn finished").slice(0, 200), stat(t) + (t.prNum ? " · PR #" + t.prNum : "")].join("\n");
        const argv = ["notify-send", "-a", kindName(s), "-i", "utilities-terminal", "-A", "default=Show"];
        if ((t.nfiles ?? 0) > 0) argv.push("-A", "diff=Open diff");
        if (t.pr) argv.push("-A", "pr=Open PR");
        argv.push("-A", "reply=Reply", "-A", "jump=Jump", "--wait", title, body);
        notifyAct(s, argv, a => {
            if (a === "diff") openDiff(s.id);
            else if (a === "pr") openPr(t.pr);
            else if (a === "reply") show(s.id, true);
            else if (a === "jump") jump(s.id);
            else if (a === "default") show(s.id);
        });
    }

    // ---- helpers shared by the panel, the grid and the bar ----
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
    function ago(ms) {
        const s = Math.max(0, Math.floor((Date.now() - ms) / 1000));
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + "m" : s < 86400 ? Math.floor(s / 3600) + "h" : Math.floor(s / 86400) + "d";
    }
    function lastAction(s) {
        const a = (s?.activity ?? []).slice().reverse().find(x => x.k === "tool" || x.k === "say");
        if (!a) return "";
        return a.k === "say" ? a.a : (a.n + (a.a ? " " + a.a : ""));
    }
    function fmtTok(n) { n = n ?? 0; return n >= 1e6 ? (n / 1e6).toFixed(2) + "M" : n >= 1000 ? (n / 1000).toFixed(1) + "k" : String(n); }
    function byId(id) { return sessions.find(s => s.id === id) ?? null; }
}

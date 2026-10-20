pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Plan usage (bar widget "usage"): Claude 5-hour / weekly limits and, optionally, Codex.
// Claude Code only hands the plan limits to its status line, so each statusline script tees them
// through ~/.local/lib/nox/usage (install snippet in its header) into
// $XDG_RUNTIME_DIR/nox/usage/<account>.json and touches .stamp there; this watches .stamp (inotify,
// no polling). Codex: `usage codex` reads the newest ~/.codex/sessions rollout's rate_limits
// (read-only) into codex.json, every widgets.usage.codexInterval ms (300000) and every 60 s while
// the popover is open. The numbers are as fresh as the last statusline refresh of any session.
// widgets.usage: { warnAt: 80, codex: true, codexInterval: 300000, account: "claude" }
Singleton {
    id: root
    readonly property var opts: Config.widget("usage")
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nox/usage"
    readonly property string lib: Quickshell.env("NOX_LIB") || (Quickshell.env("HOME") + "/.local/lib/nox")
    readonly property real warnAt: opts.warnAt ?? 80
    readonly property bool codexOn: opts.codex ?? true

    property var files: []               // parsed <account>.json, any order
    property bool loaded: false
    property bool popoverOpen: false     // set by the widget: Codex is re-read every minute then
    property real now: Date.now()        // ms, ticks for the countdowns
    Timer { interval: 20000; running: root.files.length > 0; repeat: true; onTriggered: root.now = Date.now() }

    // ---- derived ----
    // one entry per account: Claude files whose weekly window ends at the same moment are the same
    // login (e.g. ~/.claude and the expai sandbox signed in to one account) -> keep the freshest
    readonly property var groups: {
        const out = [];
        const fs = files.slice().sort((a, b) => (b.updated ?? 0) - (a.updated ?? 0));
        for (const f of fs) {
            const wk = f.seven_day?.resets_at ?? 0;
            const g = out.find(g => g.source === f.source && f.source === "claude" && wk && Math.abs((g.seven_day?.resets_at ?? 0) - wk) <= 90);
            if (g) { g.via.push(f.account); continue; }
            out.push(Object.assign({}, f, { via: [f.account] }));
        }
        // the bar's account first, then other Claude logins, then Codex
        const rank = g => g.via.indexOf(account) >= 0 ? 0 : g.source === "claude" ? 1 : 2;
        return out.sort((a, b) => rank(a) - rank(b));
    }
    // the bar shows widgets.usage.account ("claude" = ~/.claude) while it is current, else the
    // freshest current Claude login, else whatever there is
    readonly property string account: opts.account ?? "claude"
    readonly property var primary: groups.find(g => g.via.indexOf(account) >= 0 && !stale(g))
        ?? groups.find(g => g.source === "claude" && !stale(g)) ?? groups.find(g => g.source === "claude") ?? groups[0] ?? null
    readonly property bool any: primary !== null

    // the 5-hour window rolled over since these numbers were seen -> they no longer apply
    function stale(g) {
        const r = g?.five_hour?.resets_at ?? g?.seven_day?.resets_at ?? 0;
        return !g || (r > 0 && r * 1000 <= now) || (now - (g.updated ?? 0) * 1000) > 5 * 3600 * 1000;
    }
    // a window's % as it stands now: 0 once it reset after the reading
    function pctNow(w) { return !w ? -1 : (w.resets_at && w.resets_at * 1000 <= now) ? 0 : (w.pct ?? 0); }
    function left(epoch) {                // "2h14" / "3d4h" / "12m" / "now"
        if (!epoch) return "";
        const s = Math.floor(epoch - now / 1000);
        if (s <= 0) return "now";
        const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
        return d ? d + "d" + h + "h" : h ? h + "h" + String(m).padStart(2, "0") : m + "m";
    }
    function at(epoch) {                  // local reset time: "16:40" today, "Fri 09:00" later
        if (!epoch) return "";
        const t = new Date(epoch * 1000), n = new Date(now);
        const same = t.toDateString() === n.toDateString();
        return Qt.formatDateTime(t, same ? "HH:mm" : (Math.abs(epoch * 1000 - now) > 6 * 86400000 ? "ddd d MMM HH:mm" : "ddd HH:mm"));
    }
    function ago(epoch) {
        if (!epoch) return "never";
        const s = Math.max(0, Math.floor(now / 1000 - epoch));
        return s < 60 ? "just now" : s < 3600 ? Math.floor(s / 60) + " min ago" : s < 86400 ? Math.floor(s / 3600) + " h ago" : Math.floor(s / 86400) + " d ago";
    }
    function level(p) { return p >= 95 ? 3 : p >= warnAt ? 2 : p >= 50 ? 1 : 0; }   // calm, mid, warn, critical

    // ---- reading ----
    Process {
        id: init
        running: true
        command: ["sh", "-c", "mkdir -p \"$1\" && chmod 700 \"$1\" && touch \"$1/.stamp\"", "sh", root.dir]
        onExited: { stampView.path = root.dir + "/.stamp"; root.reload(); root.pollCodex(); }
    }
    FileView {
        id: stampView
        watchChanges: true
        printErrors: false
        onFileChanged: debounce.restart()
    }
    Timer { id: debounce; interval: 120; onTriggered: root.reload() }
    property bool again: false
    function reload() { if (reader.running) again = true; else reader.running = true; }
    Process {
        id: reader
        command: ["sh", "-c", "for f in \"$1\"/*.json; do [ -f \"$f\" ] && { cat \"$f\"; echo; }; done; exit 0", "sh", root.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    if (!line.trim()) continue;
                    try {
                        const j = JSON.parse(line);
                        if (j && j.account && (j.source !== "codex" || root.codexOn)) out.push(j);
                    } catch (e) {}
                }
                root.files = out;
                root.now = Date.now();
                root.loaded = true;
            }
        }
        onExited: if (root.again) { root.again = false; running = true; }
    }

    // ---- Codex (read-only, cheap; skipped without ~/.codex) ----
    property real codexAt: 0             // ms of the last read (at most one a minute)
    function pollCodex() {
        if (!codexOn || codexProc.running || Date.now() - codexAt < 55000) return;
        codexAt = Date.now();
        codexProc.running = true;
    }
    Process {
        id: codexProc
        command: [root.lib + "/usage", "codex"]
        onExited: root.reload()
    }
    Timer {
        running: root.codexOn
        repeat: true
        interval: root.popoverOpen ? 60000 : Math.max(60000, root.opts.codexInterval ?? 300000)
        onTriggered: root.pollCodex()
    }
    onPopoverOpenChanged: if (popoverOpen) { now = Date.now(); pollCodex(); }
}

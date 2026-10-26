pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

// Selection bar state (modules/selbar is the UI; `nox selbar`, IPC target selbar).
// Wayland gives the shell no global mouse-up, and Qt only sees the primary selection while one of
// its own surfaces has keyboard focus, so the bar works from the compositor's data-control side:
//   watch   ONE long-lived `wl-paste --primary --watch`, started only while the module is loaded and
//           the bar is on. Per change it runs a tiny `wc -c` (sh + exec, ~2 ms) that drains the text
//           and prints only its byte count; CLIPBOARD_STATE=sensitive (password managers) prints "s".
//           The text itself is not read here.
//   settle  300 ms after a change, the pointer is sampled every 100 ms over Hyprland's request
//           socket (in process, no hyprctl): once it has been still for 200 ms the bar shows 14 px
//           above it. Still moving after 2.5 s = a drag that never settled: nothing shows.
//   read    only then is the text read, once (`wl-paste --primary`), into memory.
//   shown   the pointer is sampled every 150 ms while the bar is up (never while idle) to dismiss
//           it when the pointer goes more than 160 px from the bar. Also dismissed by 6 s without
//           hover, a new / cleared selection, Esc (nox:selbarDismiss) or an action.
// Privacy: the selected text lives only in `text`, only while the bar is up (cleared once it has
// faded out), is never logged, never written to disk and never leaves the machine unless an action
// is clicked. A remembered hash (not the text) keeps an app that re-asserts the same selection on
// focus from popping the bar again. Ignored apps (selbar.ignore, terminals by default) never show it.
// shell.json "selbar": { enabled (true), ignore ([classes]), maxBytes (20000), settleMs (300),
//   stillMs (200), awayPx (160), idleSeconds (6), searchUrl, translateUrl (%s = the text) }
// On/off is a runtime pick (`nox selbar on|off|toggle`) kept in ~/.local/state/nox/selbar.json over
// selbar.enabled; `nox selbar reset` drops it.
Singleton {
    id: root
    readonly property var opts: Config.opt.selbar ?? ({})
    readonly property bool enabled: state.data.enabled ?? opts.enabled ?? true
    // set by modules/selbar while it is loaded (modules.selbar); nothing runs without it
    property bool active: false
    readonly property bool watching: active && enabled && state.loaded

    // terminals: selecting there already copies, and a bar would sit on the prompt
    readonly property var defaultIgnore: ["com.mitchellh.ghostty", "dev.neovim", "kitty", "foot", "footclient", "Alacritty",
        "org.wezfurlong.wezterm", "org.kde.konsole", "org.gnome.Console", "org.gnome.Terminal", "xterm", "st-256color"]
    readonly property var ignore: (opts.ignore ?? defaultIgnore).map(c => String(c).toLowerCase())
    readonly property int maxBytes: opts.maxBytes ?? 20000
    readonly property int settleMs: opts.settleMs ?? 300
    readonly property int stillMs: opts.stillMs ?? 200
    readonly property real awayPx: opts.awayPx ?? 160
    readonly property int idleMs: Math.round((opts.idleSeconds ?? 6) * 1000)

    // ---- what the UI reads ----
    property bool shown: false
    property string text: ""            // the selection, only while shown (and its fade-out)
    property string screenName: ""
    property real atX: 0                // pointer when it settled, screen-local logical px
    property real atY: 0
    property int serial: 0              // +1 per show (the UI resets its per-show state)
    property bool hovered: false        // set by the UI
    property rect barRect: Qt.rect(0, 0, 0, 0)   // the bar, global logical px (set by the UI)
    property string app: ""             // focused window when it showed: class / title (Ask context)
    property string title: ""
    // Ask Claude with this text (modules/ask answers; rect = where the bar was, screen-local)
    signal askRequested(string text, var rect)

    function setEnabled(v) { state.data = Object.assign({}, state.data, { enabled: !!v }); state.save(); if (!v) hide("off"); }
    function toggle() { setEnabled(!enabled); }
    function reset() { state.data = {}; state.save(); }
    // counts and states only: never the text
    function status() {
        return (enabled ? "on" : "off") + " watching=" + watcher.running + " shown=" + shown
            + " ignore=" + ignore.length + (active ? "" : " (module not loaded)");
    }
    JsonState { id: state; path: Paths.state("selbar") }

    // ---- watch ----
    // tests swap these (synthetic text, a fake socket); the live ones only ever read
    property var watchCommand: ["wl-paste", "--primary", "--type", "text", "--watch", "sh", "-c",
        "if [ \"$CLIPBOARD_STATE\" = sensitive ]; then cat >/dev/null; echo s; else exec wc -c; fi"]
    property var readCommand: ["wl-paste", "--primary", "--no-newline", "--type", "text"]
    property string socketPath: Hyprland.requestSocketPath

    property real watchStarted: 0
    property int failures: 0
    onWatchingChanged: { if (!watching) { hide("off"); settle.stop(); poll.stop(); } }
    Process {
        id: watcher
        running: root.watching && !retry.running
        command: root.watchCommand
        onStarted: root.watchStarted = Date.now()
        stdout: SplitParser { onRead: line => root.changed(line) }
        onExited: code => {
            if (!root.watching) return;
            // the compositor restarted / wl-paste missing: try again, backing off to a minute
            if (Date.now() - root.watchStarted > 30000) root.failures = 0;
            root.failures++;
            if (root.failures === 1 || root.failures % 10 === 0) console.warn("nox: selbar watcher exited (" + code + "), retrying");
            retry.interval = Math.min(60000, 2000 * root.failures);
            retry.restart();
        }
    }
    Timer { id: retry }

    // one line per selection change: byte count, "0" = cleared, "s" = sensitive
    function changed(line) {
        const s = String(line).trim();
        // wl-paste replays the current selection when it starts: that is not a new selection
        if (Date.now() - watchStarted < 800) return;
        hide("changed");
        reader.running = false;
        seq++;
        if (s === "s" || s === "" || s === "0") { pending = false; settle.stop(); poll.stop(); return; }
        const n = parseInt(s, 10);
        if (!(n > 0) || n > maxBytes || ignored()) { pending = false; settle.stop(); poll.stop(); return; }
        pending = true;
        changedAt = Date.now();
        stillSince = 0;
        poll.stop();
        settle.restart();
    }
    property int seq: 0
    property bool pending: false
    property real changedAt: 0
    property real stillSince: 0         // settle: when the pointer stopped at (stillX, stillY)
    property real stillX: 0
    property real stillY: 0

    function activeClass() {
        const t = Hyprland.activeToplevel;
        return String(t?.lastIpcObject?.class || t?.wayland?.appId || "");
    }
    function ignored() {
        const t = Hyprland.activeToplevel;
        const c = activeClass().toLowerCase(), ic = String(t?.lastIpcObject?.initialClass ?? "").toLowerCase();
        return c !== "" && ignore.indexOf(c) !== -1 || ic !== "" && ignore.indexOf(ic) !== -1;
    }

    // ---- settle: is the pointer still? ----
    Timer { id: settle; interval: root.settleMs; onTriggered: { poll.interval = 100; poll.start(); root.query(); } }
    Timer {
        id: poll
        repeat: true
        interval: 100
        // while the bar is hovered the pointer is on it: nothing to check
        onTriggered: if (!(root.shown && root.hovered)) root.query()
    }
    // Hyprland's request socket: write "j/cursorpos", read the JSON, close (it closes after a reply;
    // closing first keeps PeerClosed warnings out of the shell log)
    property string reply: ""
    Socket {
        id: sock
        path: root.socketPath
        onConnectedChanged: {
            if (!connected) return;
            root.reply = "";
            write("j/cursorpos");
            flush();
        }
        parser: SplitParser {
            splitMarker: ""
            onRead: data => {
                root.reply += data;
                let p = null;
                try { p = JSON.parse(root.reply); } catch (e) { return; }
                sock.connected = false;
                root.reply = "";
                if (p && typeof p.x === "number" && typeof p.y === "number") root.cursorAt(p.x, p.y);
            }
        }
    }
    property real queriedAt: 0
    function query() {
        if (socketPath === "") return;
        if (sock.connected) {
            if (Date.now() - queriedAt < 1000) return;       // the last one has not answered yet
            sock.connected = false;                          // ... for a second: start over
        }
        queriedAt = Date.now();
        sock.connected = true;
    }
    function cursorAt(x, y) {
        const now = Date.now();
        if (shown) { checkAway(x, y); return; }
        if (!pending) { poll.stop(); return; }
        // moved more than 3 px = still from now on; still for stillMs = settled
        if (stillSince === 0 || Math.abs(x - stillX) > 3 || Math.abs(y - stillY) > 3) {
            stillSince = now; stillX = x; stillY = y;
        } else if (now - stillSince >= stillMs - 20) {
            poll.stop(); pending = false;
            read(x, y);
            return;
        }
        if (now - changedAt > 2500) { poll.stop(); pending = false; }
    }

    // ---- read the text (only now) and show ----
    property real readX: 0
    property real readY: 0
    function read(x, y) {
        if (ignored()) return;
        readX = x; readY = y;
        reader.seq = seq;
        reader.running = true;
    }
    Process {
        id: reader
        property int seq: 0
        command: root.readCommand
        stdout: StdioCollector {
            onStreamFinished: {
                if (reader.seq !== root.seq) return;      // the selection changed meanwhile
                root.show(text, root.readX, root.readY);
            }
        }
    }
    // same text again soon after the bar went away (an app re-asserting its selection on focus)
    property string lastHash: ""
    property real lastHidAt: 0
    function hash(t) {
        let h = 5381;
        for (let i = 0; i < t.length; i++) h = ((h << 5) + h + t.charCodeAt(i)) | 0;
        return t.length + ":" + h;
    }
    function show(t, x, y) {
        if (String(t).trim() === "" || t.length > maxBytes) return;
        const h = hash(t);
        if (h === lastHash && Date.now() - lastHidAt < 5000) return;
        const scr = Quickshell.screens.find(s => x >= s.x && y >= s.y && x < s.x + s.width && y < s.y + s.height) ?? Quickshell.screens[0];
        if (!scr) return;
        const at = Hyprland.activeToplevel;
        app = activeClass();
        title = at ? String(at.lastIpcObject.title ?? at.title ?? "") : "";
        lastHash = h;
        text = t;
        screenName = scr.name;
        atX = x - scr.x;
        atY = y - scr.y;
        barRect = Qt.rect(x - 60, y - 52, 120, 38);
        hovered = false;
        serial++;
        clearText.stop();
        shown = true;
        idle.restart();
        poll.interval = 150;
        poll.start();
    }

    // ---- dismiss ----
    function hide(why) {
        if (!shown) return;
        shown = false;
        hovered = false;
        lastHidAt = Date.now();
        idle.stop();
        poll.stop();
        clearText.restart();
    }
    // the UI keeps its last frame on screen while fading out; the text goes after that
    Timer { id: clearText; interval: 600; onTriggered: if (!root.shown) { root.text = ""; root.app = ""; root.title = ""; } }
    Timer { id: idle; interval: root.idleMs; onTriggered: if (!root.hovered) root.hide("idle") }
    onHoveredChanged: if (shown) { if (hovered) idle.stop(); else idle.restart(); }
    function checkAway(x, y) {
        if (hovered) return;
        const r = barRect;
        const dx = Math.max(r.x - x, 0, x - (r.x + r.width)), dy = Math.max(r.y - y, 0, y - (r.y + r.height));
        if (Math.hypot(dx, dy) > awayPx) hide("away");
    }
    // an action that leaves the bar up (Case): the 6 s start again
    function keep() { if (shown) idle.restart(); }
    // Esc (bound non-consuming, so the app still gets it) and actions
    function dismiss() { hide("dismiss"); }
    // Ask Claude: the bar is already gone (the UI unmaps it at once, so the frozen frame Ask takes
    // does not show it); Ask starts a moment later, once that frame has been presented
    function ask(rect) {
        askLater.t = text;
        askLater.rect = rect;
        hide("ask");
        askLater.restart();
    }
    Timer {
        id: askLater
        property string t: ""
        property var rect: null
        interval: 90
        onTriggered: { const t = askLater.t; askLater.t = ""; root.askRequested(t, askLater.rect); }
    }
}

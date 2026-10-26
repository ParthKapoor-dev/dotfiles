pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core

// Countdown timer (`nox timer 5m`, IPC target timer; the bar island shows it while it runs).
// Named Countdown, not Timer: a qs.services type called Timer would shadow QtQuick's Timer in
// every file that imports qs.services.
// One timer at a time. Nothing runs while no timer is set: while one runs, `now` refreshes once a
// second (aligned to the remaining seconds) for the display and a one-shot fires at the exact end.
// When it ends: a notification (notify-send, app "Timer") and a sound (timer.sound via pw-play, or
// paplay), and `ringing` stays on for timer.ringSeconds (8) so the island can show "Done".
// The running / paused timer is kept in ~/.local/state/nox/timer.json, so a shell restart doesn't
// lose it; one that ended while the shell was down is reported once (if it ended < 10 min ago).
// Durations (parse): "5m", "90s", "1h30m", "1h 5m 10s", "2.5m", "1:30" (m:ss), "1:02:03", "25" (minutes);
// at most 24 h.
// shell.json timer.{sound (a file; "" = silent), notify (true), ringSeconds (8)}
Singleton {
    id: root
    readonly property var opts: Config.opt.timer ?? ({})
    readonly property string sound: opts.sound ?? "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"
    readonly property real maxMs: 24 * 3600000

    property real endsAt: 0             // ms epoch while running, 0 otherwise
    property real duration: 0           // full length in ms (progress, "Again")
    property real pausedLeft: 0         // ms left while paused
    property string label: ""
    property real now: Date.now()
    property bool ringing: false        // just finished (cleared after ringSeconds or by dismiss())

    readonly property bool running: endsAt > 0
    readonly property bool paused: !running && pausedLeft > 0
    readonly property bool active: running || paused
    readonly property real left: running ? Math.max(0, endsAt - now) : pausedLeft
    readonly property real progress: duration > 0 ? Math.max(0, Math.min(1, 1 - left / duration)) : 0  // elapsed share

    signal finished(string label)

    // ---------------------------------------------------------------- parsing / formatting
    // ms for a duration spec, 0 = not a duration
    function parse(spec) {
        const s = String(spec ?? "").trim().toLowerCase();
        if (!s) return 0;
        let m = /^(\d+):(\d{1,2})(?::(\d{1,2}))?$/.exec(s);
        if (m) return clampMs((m[3] !== undefined ? (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]) : (+m[1]) * 60 + (+m[2])) * 1000);
        if (/^\d+(\.\d+)?$/.test(s)) return clampMs(parseFloat(s) * 60000);
        // longest unit names first, so "5min" isn't read as "5m" + "in"
        const re = /(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)/g;
        let total = 0, any = false;
        while ((m = re.exec(s)) !== null) {
            const u = m[2][0];
            total += parseFloat(m[1]) * (u === "h" ? 3600000 : u === "m" ? 60000 : 1000);
            any = true;
        }
        if (!any || s.replace(re, "").replace(/[\s,]+/g, "") !== "") return 0;
        return clampMs(total);
    }
    function clampMs(ms) { return ms > 0 ? Math.min(maxMs, Math.round(ms)) : 0; }
    // 4:05 / 1:02:03 (whole seconds, rounded up so it reads 0:01 until the very end)
    function fmt(ms) {
        const t = Math.max(0, Math.ceil(ms / 1000));
        const h = Math.floor(t / 3600), mi = Math.floor(t / 60) % 60, se = t % 60;
        return (h > 0 ? h + ":" + String(mi).padStart(2, "0") : String(mi)) + ":" + String(se).padStart(2, "0");
    }
    function status() {
        if (running) return "running " + fmt(left) + " left of " + fmt(duration) + (label ? " · " + label : "");
        if (paused) return "paused " + fmt(left) + " left of " + fmt(duration) + (label ? " · " + label : "");
        return ringing ? "done" + (label ? " · " + label : "") : "idle";
    }

    // ---------------------------------------------------------------- control
    function start(ms, lbl) {
        ms = clampMs(ms);
        if (ms <= 0) return false;
        ringing = false;
        label = String(lbl ?? "").trim().slice(0, 80);
        duration = ms;
        pausedLeft = 0;
        run(ms);
        save();
        return true;
    }
    function run(ms) {
        now = Date.now();
        endsAt = now + ms;
        ender.interval = Math.max(1, Math.round(ms));
        ender.restart();
        ticker.interval = tickIn();
        ticker.restart();
    }
    function stop() {
        const was = active || ringing;
        ender.stop();
        endsAt = 0; pausedLeft = 0; duration = 0; label = ""; ringing = false;
        save();
        return was;
    }
    function pause() {
        if (!running) return false;
        now = Date.now();
        pausedLeft = Math.max(1000, endsAt - now);
        endsAt = 0;
        ender.stop();
        save();
        return true;
    }
    function resume() {
        if (!paused) return false;
        const ms = pausedLeft;
        pausedLeft = 0;
        run(ms);
        save();
        return true;
    }
    function togglePause() { return running ? pause() : resume(); }
    // add (or with a negative ms, take off) time; starts a timer when none is set
    function add(ms) {
        ms = Math.round(ms);
        if (!active) return ms > 0 ? start(ms, "") : false;
        duration = Math.max(1000, duration + ms);
        if (running) run(Math.max(1000, Math.min(maxMs, endsAt - Date.now() + ms)));
        else pausedLeft = Math.max(1000, Math.min(maxMs, pausedLeft + ms));
        save();
        return true;
    }
    function again() { const d = duration, l = label; return d > 0 && start(d, l); }
    function dismiss() { ringing = false; ringOff.stop(); }

    function finish(late) {
        const lbl = label;
        ender.stop();
        endsAt = 0; pausedLeft = 0;
        ringing = true;
        ringOff.interval = Math.max(1, Number(opts.ringSeconds ?? 8)) * 1000;
        ringOff.restart();
        save();
        if (opts.notify ?? true) {
            const body = (lbl ? lbl + " · " : "") + fmt(duration) + (late ? " · ended at " + Qt.formatTime(new Date(late), "HH:mm") : "");
            Quickshell.execDetached(["notify-send", "-a", "Timer", "-i", "alarm-symbolic", "Timer done", body]);
        }
        if (sound && !late)
            Quickshell.execDetached(["sh", "-c", "[ -f \"$1\" ] || exit 0; command -v pw-play >/dev/null && exec pw-play -- \"$1\"; command -v paplay >/dev/null && exec paplay -- \"$1\"", "sh", sound]);
        finished(lbl);
    }

    // next display tick: just after the remaining time crosses a whole second
    function tickIn() { return Math.max(50, ((endsAt - Date.now()) % 1000) + 15); }
    Timer {
        id: ticker
        repeat: true
        running: root.running
        onTriggered: { root.now = Date.now(); interval = root.tickIn(); }
    }
    Timer { id: ender; onTriggered: root.finish(0) }
    Timer { id: ringOff; onTriggered: root.ringing = false }

    // ---------------------------------------------------------------- persistence
    function save() {
        state.data = running ? { endsAt, duration, label } : paused ? { pausedLeft, duration, label } : {};
        state.save();
    }
    JsonState {
        id: state
        path: Paths.state("timer")
        onLoadedChanged: root.restore()
    }
    property bool restored: false
    Component.onCompleted: restore()
    function restore() {
        if (restored || !state.loaded) return;
        restored = true;
        const d = state.data ?? {};
        const t = Date.now();
        label = String(d.label ?? "");
        duration = Number(d.duration ?? 0);
        if (Number(d.endsAt) > t) run(Number(d.endsAt) - t);
        else if (Number(d.pausedLeft) > 0) pausedLeft = Number(d.pausedLeft);
        else if (Number(d.endsAt) > 0 && t - Number(d.endsAt) < 600000) finish(Number(d.endsAt));
        else if (Number(d.endsAt) > 0) stop();
    }
}

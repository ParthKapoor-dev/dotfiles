pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs.core

// Notification daemon (org.freedesktop.Notifications) + popup queue + Do Not Disturb.
// The D-Bus server only exists while shell.json modules.notifications is true: only one
// process can own the name, and end-4 "ii" owns it today, so the module ships disabled.
// If the name is taken, Quickshell logs "Could not register notification server..." and
// takes over automatically once the other owner releases it.
//
// shell.json notifications.rules: list of { appName|summary|body|desktopEntry: "<regex>",
//   "mute": true (history only, no popup) | "drop": true (discard) | "timeout": ms | "urgency": "low|normal|critical" }
// All matching rules are merged in order (later wins). Regexes are case-insensitive.
Singleton {
    id: root

    readonly property bool enabled: Config.moduleEnabled("notifications")
    readonly property var opts: Config.opt.notifications ?? ({})
    readonly property bool dnd: state.data.dnd ?? false
    readonly property bool running: server.item !== null

    // history, newest first
    readonly property var list: (server.item?.trackedNotifications.values ?? []).slice().reverse()
    readonly property int count: list.length

    // popups currently on screen: [{ n: Notification, deadline: ms epoch | 0 (sticky) }], newest first
    property var popups: []
    property var arrived: ({})     // notification id -> ms epoch (for "2m ago")
    property bool paused: false    // pointer over the popups: timers stop (like macOS)
    property real pausedAt: 0

    function setDnd(on) {
        state.data = Object.assign({}, state.data, { dnd: !!on });
        state.save();
        if (on) clearPopups();
    }
    function toggleDnd() { setDnd(!dnd); }
    function timeOf(n) { return arrived[n?.id] ?? Date.now(); }

    function hidePopup(n) {
        popups = popups.filter(p => p.n !== n);
        schedule();
    }
    function clearPopups() { popups = []; expiry.stop(); }
    function dismiss(n) { hidePopup(n); n.dismiss(); }
    function clearAll() { clearPopups(); for (const n of list) n.dismiss(); }
    // run the "default" action (body click) if the app offers one
    function activate(n) {
        const a = n.actions.find(x => x.identifier === "default");
        if (a) a.invoke();
        hidePopup(n);
    }

    function setPaused(p) {
        if (p === paused) return;
        paused = p;
        if (p) { pausedAt = Date.now(); expiry.stop(); return; }
        const extra = Date.now() - pausedAt;
        popups = popups.map(x => x.deadline ? { n: x.n, deadline: x.deadline + extra } : x);
        schedule();
    }

    // ---- rules / timeouts ----
    function urgencyName(n) {
        return n.urgency === NotificationUrgency.Critical ? "critical" : n.urgency === NotificationUrgency.Low ? "low" : "normal";
    }
    function rulesFor(n) {
        const out = {};
        for (const r of (opts.rules ?? [])) {
            let ok = true;
            for (const field of ["appName", "summary", "body", "desktopEntry"]) {
                if (r[field] === undefined) continue;
                try { if (!new RegExp(r[field], "i").test(n[field] ?? "")) { ok = false; break; } }
                catch (e) { console.warn("graphite: bad notification rule regex:", r[field]); ok = false; break; }
            }
            if (ok) Object.assign(out, r);
        }
        return out;
    }
    function timeoutFor(n, rule) {
        if (rule.timeout !== undefined) return rule.timeout;
        const urgency = rule.urgency ?? urgencyName(n);
        if (urgency !== "critical" && opts.respectAppTimeout !== false && n.expireTimeout > 0) return n.expireTimeout;
        return (opts.timeout ?? {})[urgency] ?? 6000;
    }

    function handle(n) {
        const rule = rulesFor(n);
        if (rule.drop) return;                 // not tracked -> discarded
        n.tracked = true;
        arrived = Object.assign({}, arrived, { [n.id]: Date.now() });
        n.closed.connect(() => root.forget(n));

        const max = opts.maxHistory ?? 100;
        const hist = server.item.trackedNotifications.values;
        if (hist.length > max) for (const old of hist.slice(0, hist.length - max)) old.dismiss();

        const critical = (rule.urgency ?? urgencyName(n)) === "critical";
        if (rule.mute || (dnd && !(critical && opts.dndAllowCritical !== false))) return;
        const t = timeoutFor(n, rule);
        const entry = { n, deadline: t > 0 ? Date.now() + t + (paused ? Date.now() - pausedAt : 0) : 0 };
        popups = [entry].concat(popups.filter(p => p.n.id !== n.id)).slice(0, opts.maxPopups ?? 4);
        schedule();
    }
    function forget(n) {
        popups = popups.filter(p => p.n !== n);
        const a = Object.assign({}, arrived);
        delete a[n.id];
        arrived = a;
        schedule();
    }

    // one timer for the nearest deadline (no polling)
    function schedule() {
        if (paused) return;
        const now = Date.now();
        const live = popups.filter(p => !p.deadline || p.deadline > now);
        if (live.length !== popups.length) popups = live;
        const next = Math.min(...popups.filter(p => p.deadline).map(p => p.deadline));
        if (isFinite(next)) { expiry.interval = Math.max(1, next - now); expiry.restart(); }
        else expiry.stop();
    }
    Timer { id: expiry; onTriggered: root.schedule() }

    JsonState { id: state; path: Paths.state("notifications") }

    LazyLoader {
        id: server
        active: root.enabled && Config.loaded
        NotificationServer {
            bodySupported: true
            bodyMarkupSupported: true
            bodyHyperlinksSupported: false
            bodyImagesSupported: false
            actionsSupported: true
            actionIconsSupported: false
            imageSupported: true
            persistenceSupported: true
            onNotification: n => root.handle(n)
        }
    }
}

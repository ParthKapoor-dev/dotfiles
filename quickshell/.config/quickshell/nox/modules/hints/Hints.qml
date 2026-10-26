pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services
import "HintCodes.js" as Codes

// Click anything (Super+;): letter labels on everything you can click on the focused screen, type
// one to click it. One full-screen overlay (namespace nox:hints, Overlay layer, exclusive keyboard)
// on the screen that had focus; it only exists while hint mode is open.
//   windows   every window on the screen's desktop (and its open scratchpad): focus it
//   bar       bar buttons and desktop dots: their own click
//   dock      dock tiles (an autohiding dock is revealed for it): open / switch to the app
//   elements  buttons, links, tabs, menu items, check boxes and text fields inside the focused
//             window, from its AT-SPI tree (nox/.local/lib/nox/hints, started for each open and
//             gone when it has answered): clicked with AT-SPI actions, text fields focused. An
//             element without either (GTK 4 check boxes and entries) gets the pointer put on it.
//             No tree (Chromium / Electron / Zed / terminals, or accessibility off): the window
//             hints stay and the pill says "no elements".
// Labels are home-row letters (hints.chars, "asdfghjkl"), as short as possible, prefix-free: the
// last letter of a label clicks without Enter. Backspace = back a letter, Esc / click / Super+;
// again = off. The overlay waits up to hints.waitMs (300) for the elements so labels don't move
// under you; a slower walk shows the rest first and relabels if nothing was typed yet.
//   qs -c nox ipc call hints toggle | open | close | status   (`nox hints`)
// Nothing runs while it's closed: no listener, no process, the window isn't loaded.
Scope {
    id: root
    readonly property var opts: Config.opt.hints ?? ({})
    readonly property string chars: opts.chars ?? "asdfghjkl"
    readonly property bool wantElements: opts.elements ?? true
    readonly property int waitMs: opts.waitMs ?? 300
    // the helper (`nox hints`): found next to whatever `nox` is on PATH (NOX_LIB style), so it
    // works without the dispatcher knowing it; hints.helper = an explicit path
    readonly property var helper: opts.helper ? [opts.helper]
        : ["sh", "-c", "exec \"$(dirname \"$(readlink -f \"$(command -v nox)\")\")/../lib/nox/hints\" \"$@\"", "nox-hints"]

    property bool active: false       // hint mode on (keys go to the overlay)
    property bool shown: false        // overlay loaded (stays a moment after a cancel for the fade)
    property bool snap: false         // a pick: gone at once, no fade
    property string screenName: ""
    property string address: ""       // the focused window at open: its elements are walked
    property var clients: null        // hyprctl clients at open
    property var scanned: null        // the helper's answer
    property bool scanning: false
    property var targets: []
    property string typed: ""
    property int miss: 0              // bumped on a letter no label has (the pill shakes)
    property bool revealedDock: false
    readonly property var scr: Quickshell.screens.find(s => s.name === screenName) ?? null
    readonly property int elementCount: targets.filter(t => t.kind === "element").length
    readonly property string status: !wantElements || !address ? "off" : scanning ? "scanning"
        : elementCount > 0 ? "ready" : "none"

    function norm(a) { a = String(a ?? ""); return a === "" ? "" : a.startsWith("0x") ? a : "0x" + a; }
    function open() {
        if (active) return;
        killTimer.stop();
        screenName = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
        const t = Hyprland.activeToplevel;
        address = t && (t.monitor?.name ?? screenName) === screenName ? norm(t.address) : "";
        typed = "";
        targets = [];
        clients = null;
        scanned = null;
        snap = false;
        active = true;
        Hyprland.refreshMonitors();
        clientsProc.running = true;
        if (wantElements && address) {
            scanProc.command = root.helper.concat(["scan", "--address", address,
                "--max", String(opts.maxElements ?? 300), "--budget", String(opts.budgetMs ?? 250)]);
            scanning = true;
            scanProc.running = true;
            watchdog.restart();
        }
        // dock labels need the dock: an autohiding one comes up for its reveal (1.5 s off-pointer)
        if ((opts.dock ?? true) && Config.opt.dock?.autohide && !Panels.dockRevealed) { Panels.dockRevealed = true; revealedDock = true; }
        waitTimer.restart();
    }
    function close(now) {
        if (!active) return;
        active = false;
        snap = !!now;
        waitTimer.stop();
        watchdog.stop();
        scanProc.running = false;
        scanning = false;
        if (revealedDock) { revealedDock = false; Panels.dockRevealed = false; }
        if (snap) shown = false; else killTimer.restart();
    }
    function toggle() { if (active) close(false); else open(); }
    Timer { id: killTimer; interval: Theme.durHover + 40; onTriggered: if (!root.active) root.shown = false }
    // show once the elements are in, or after waitMs with what's there
    Timer { id: waitTimer; interval: root.waitMs; onTriggered: root.reveal() }
    Timer { id: watchdog; interval: 2500; onTriggered: { scanProc.running = false; root.scanning = false; } }
    function reveal() {
        if (!active || clients === null) return;
        build();
        shown = true;
    }

    // ---- targets ----
    function appName(cls) { return Apps.entryFor(cls)?.name || cls; }
    function windowTargets(s) {
        const mon = Hyprland.monitorFor(s);
        const ws = mon?.activeWorkspace?.id ?? -1;
        const special = mon?.lastIpcObject?.specialWorkspace?.name ?? "";
        let wins = (clients ?? []).filter(c => c.monitor === (mon?.id ?? -2) && !c.hidden && c.mapped !== false
            && ((c.workspace?.id ?? 0) === ws || (special && c.workspace?.name === special) || c.pinned));
        // a fullscreen window hides the rest of its desktop (a scratchpad still shows over it)
        if (wins.some(c => c.fullscreen > 0 && c.workspace?.id === ws))
            wins = wins.filter(c => c.fullscreen > 0 || c.workspace?.name === special);
        return wins.map(c => ({ kind: "window", address: c.address, title: appName(c.class || c.initialClass || ""),
                                x: c.at[0] - s.x, y: c.at[1] - s.y, w: c.size[0], h: c.size[1] }));
    }
    function barTargets(s) {
        const out = [];
        // BarButtons (hpad + clicked(button)) and desktop dots (wsId), found by walking the bar
        const walk = (it, depth) => {
            if (!it || !it.visible || it.opacity < 0.05 || depth > 16) return;
            const btn = it.hpad !== undefined && typeof it.clicked === "function";
            if ((btn || it.wsId !== undefined) && it.width > 2 && it.height > 2) {
                const p = it.mapToItem(null, 0, 0);
                out.push({ kind: "bar", item: it, x: p.x, y: p.y, w: it.width, h: it.height });
                return;
            }
            for (const c of it.children) walk(c, depth + 1);
        };
        for (const w of Panels.barWindows)
            if ((w.screen?.name ?? "") === s.name && w.visible) walk(w.contentItem, 0);
        return out.sort((a, b) => a.x - b.x);
    }
    function dockTargets(s) {
        const d = Config.opt.dock ?? {};
        if (!Panels.dockVisible || (d.screens?.length && d.screens.indexOf(s.name) < 0)) return [];
        if (d.autohide && !Panels.dockRevealed) return [];
        // the dock's resting layout (mirrors Dock.qml: 6 px shelf padding, tiles size + 4 wide,
        // separators 13, tiles standing on the shelf bottom 6 px above the screen edge)
        const size = Theme.dockSize;
        const items = Apps.items;
        const tw = it => it.sep ? 13 : size + 4;
        const baseW = 12 + items.reduce((a, it) => a + tw(it), 0);
        let x = (s.width - baseW) / 2 + 6;
        const out = [];
        for (const it of items) {
            if (!it.sep) out.push({ kind: "dock", item: it, x: x + 2, y: s.height - 12 - size, w: size, h: size });
            x += tw(it);
        }
        return out;
    }
    function elementTargets(s) {
        const r = scanned;
        if (!r || !r.ok) return [];
        return (r.elements ?? []).map(e => ({ kind: "element", field: e.kind === "field", role: e.role, bus: e.bus, path: e.path,
                                              x: e.x - s.x, y: e.y - s.y, w: e.w, h: e.h, gx: e.x, gy: e.y }))
            .filter(e => e.x + e.w > 0 && e.y + e.h > 0 && e.x < s.width && e.y < s.height);
    }
    function build() {
        const s = scr;
        if (!s) { targets = []; return; }
        const els = elementTargets(s).sort((a, b) => Codes.byReading(a, b));
        // the focused window's own chip only when it has no elements to show instead
        const wins = (opts.windows ?? true) ? windowTargets(s).filter(w => !els.length || w.address !== address)
            .sort((a, b) => Codes.byReading(a, b, 40)) : [];
        const all = wins.concat(els, (opts.bar ?? true) ? barTargets(s) : [], (opts.dock ?? true) ? dockTargets(s) : []);
        const labels = Codes.codes(all.length, chars);
        all.forEach((t, i) => t.label = labels[i]);
        targets = all;
    }

    // ---- typing ----
    function type(c) {
        const next = typed + c;
        const m = targets.filter(t => t.label.startsWith(next));
        if (!m.length) { miss++; return; }
        typed = next;
        const hit = m.find(t => t.label === next);
        if (hit) pick(hit);
    }
    function back() { typed = typed.slice(0, -1); }
    function enter() {
        const m = targets.filter(t => t.label.startsWith(typed));
        if (m.length === 1) pick(m[0]);
    }
    // the overlay goes first (keyboard back to the app), the click a moment later
    property var pending: null
    function pick(t) {
        pending = t;
        close(true);
        pickTimer.restart();
    }
    Timer { id: pickTimer; interval: 24; onTriggered: { const t = root.pending; root.pending = null; if (t) root.fire(t); } }
    function fire(t) {
        if (t.kind === "window") Hypr.focusWindow(t.address);
        else if (t.kind === "bar") { if (t.item.wsId !== undefined) Hypr.workspace(t.item.wsId); else t.item.clicked(Qt.LeftButton); }
        else if (t.kind === "dock") { Panels.close(); Apps.activate(t.item); }
        else if (t.kind === "element") {
            actProc.target = t;
            actProc.command = root.helper.concat(["act", t.bus, t.path, t.field ? "focus" : "press"]);
            actProc.running = true;
        }
    }
    // no action and no focus over AT-SPI: the pointer goes onto it, one click away
    function pointAt(t) {
        const x = Math.round(t.gx + t.w / 2), y = Math.round(t.gy + t.h / 2);
        Hypr.dispatch("movecursor " + x + " " + y, "hl.dsp.cursor.move({ x = " + x + ", y = " + y + " })");
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.clients = JSON.parse(text); } catch (e) { root.clients = []; }
                if (root.active && !root.scanning) { waitTimer.stop(); root.reveal(); }
            }
        }
    }
    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(text); } catch (e) {}
                root.scanned = r;
                root.scanning = false;
                watchdog.stop();
                if (!root.active) return;
                if (r && !r.ok) console.info("nox hints: no elements (" + r.reason + ", " + (r["class"] ?? "") + ")");
                // not shown yet: show with them; shown already: relabel unless typing started
                if (!root.shown) { waitTimer.stop(); root.reveal(); }
                else if (root.typed === "") root.build();
            }
        }
    }
    Process {
        id: actProc
        property var target: null
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null;
                try { r = JSON.parse(text); } catch (e) {}
                const t = actProc.target;
                if (!r || r.ok || !t) return;
                if (r.fallback === "pointer") { root.pointAt(t); Panels.hud("No click for that one · pointer is on it", "check"); }
                else if (r.reason === "gone") Panels.hud("That element is gone", "x");
            }
        }
    }

    // the desktop changed under it (a workspace bind, a window closing): the labels are stale
    Connections {
        target: Hyprland
        enabled: root.active
        function onFocusedWorkspaceChanged() { root.close(false); }
    }

    IpcHandler {
        target: "hints"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(false); }
        function status(): string {
            return "active=" + root.active + " screen=" + root.screenName + " targets=" + root.targets.length
                + " elements=" + root.elementCount + " status=" + root.status;
        }
    }
    LazyLoader {
        active: !Quickshell.env("NOX_LINT")
        component: GlobalShortcut {
            appid: "nox"; name: "hintsToggle"; description: "Hint mode: click anything by its label"
            onPressed: root.toggle()
        }
    }

    LazyLoader {
        active: root.shown
        PanelWindow {
            id: win
            screen: root.scr
            color: "transparent"
            WlrLayershell.namespace: "nox:hints"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            HintLayer {
                id: layer
                anchors.fill: parent
                targets: root.targets
                typed: root.typed
                status: root.status
                elementCount: root.elementCount
                dim: root.opts.dim ?? 0.16
                miss: root.miss
                opacity: root.active ? 1 : 0
                Behavior on opacity { enabled: !root.snap; NumberAnimation { duration: root.active ? Theme.durPop : Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

                MouseArea { anchors.fill: parent; z: -1; onClicked: root.close(false) }
                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.onPressed: e => {
                        if (e.key === Qt.Key_Escape) root.close(false);
                        else if (e.key === Qt.Key_Backspace) root.back();
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) root.enter();
                        else if (e.text && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
                                 && root.chars.indexOf(e.text.toLowerCase()) >= 0) root.type(e.text.toLowerCase());
                        else return;
                        e.accepted = true;
                    }
                }
            }
        }
    }
}

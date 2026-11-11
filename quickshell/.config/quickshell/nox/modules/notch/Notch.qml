pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services

// The agent notch (mock lnx/design/mock/agent-notch.html; Aria-style): a true-black notch that
// hangs from the bar's centre on the focused monitor and morphs between
//   lip      nothing running: a 96 x 6 sliver (notch.idle "lip"; "hidden" = nothing at all)
//   compact  live agents: one rolling line (orb · project · what it does · elapsed · dots)
//   need     a permission request from the gate hook: the exact command + Allow / Always / Deny /
//            steer. The terminal asks at the same time; whichever answers first wins
//   done     a turn just finished (longer than notch.doneAfter s): summary, +/-, files, PR
//   panel    click / hover / Super+O: AGENTS · REPLAY · LAPS · RECEIPTS
// Keys from any window (GlobalShortcuts, appid nox): Super+Y allow · Super+Shift+Y always ·
// Super+Backspace deny (the oldest request) · Super+O open the notch with the keyboard.
// The surface is a fixed 860 x 760 transparent Overlay layer (nox:notch) whose input mask is the
// notch body only, so it never resizes while it morphs and clicks outside the body go through.
// Hidden on fullscreen workspaces. IPC: qs -c nox ipc call notch toggle | open | close | view <name>
Scope {
    id: root
    readonly property var opts: Config.opt.notch ?? ({})
    readonly property var req: Agents.requests[0] ?? null
    property bool pinned: false          // opened by a click / Super+O / IPC
    property bool peek: false            // opened by hovering the compact line
    property bool kbd: false             // the notch holds the keyboard
    property string laterId: ""          // the request folded away with Esc ("later")
    property string doneId: ""           // the done card on show
    property real now: Date.now()
    readonly property bool reqShown: !!req && laterId !== (req.sid + ":" + req.id)
    readonly property string mode: reqShown ? "need"
        : (pinned || peek) ? "panel"
        : doneId !== "" ? "done"
        : Agents.any ? "compact"
        : (opts.idle ?? "lip") === "hidden" ? "hidden" : "lip"

    function open(view) { pinned = true; kbd = true; Agents.checkGate(); if (view) panel.go(view); }
    Component.onCompleted: Agents.checkGate()
    function close() { pinned = false; peek = false; kbd = false; }
    function toggle() { if (pinned) close(); else open(); }
    function later() { if (req) laterId = req.sid + ":" + req.id; if (!pinned) kbd = false; }

    Timer { interval: 1000; repeat: true; running: root.mode !== "lip" && root.mode !== "hidden"; onTriggered: root.now = Date.now() }

    // a fresh request takes the keyboard only if you asked for it (Super+O or a click): typing in
    // your editor must never land in the notch
    onReqChanged: if (!req) { laterId = ""; if (!pinned) kbd = false; }

    // ---- done cards: a turn that ran longer than notch.doneAfter s ----
    property var lastEnd: ({})
    Connections {
        target: Agents
        function onSessionsChanged() {
            const m = Object.assign({}, root.lastEnd);
            for (const s of Agents.sessions) {
                const e = s.turn?.end ?? 0;
                if (Agents.loaded && root.lastEnd[s.id] !== undefined && e && e !== root.lastEnd[s.id] && s.status === "done"
                    && e - (s.turn?.at ?? e) >= (root.opts.doneAfter ?? 20) * 1000 && Date.now() - e < 30000) {
                    root.doneId = s.id;
                    doneTimer.restart();
                }
                m[s.id] = e;
            }
            root.lastEnd = m;
        }
    }
    Timer { id: doneTimer; interval: (root.opts.doneSeconds ?? 9) * 1000; onTriggered: if (!win.hovered) root.doneId = ""; else restart() }

    IpcHandler {
        target: "notch"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        function view(name: string): void { root.open(name); }
        function status(): string { return JSON.stringify({ mode: root.mode, requests: Agents.requests.length, gate: Agents.gateOn }); }
    }
    LazyLoader {
        active: !Quickshell.env("NOX_LINT")
        component: Scope {
            GlobalShortcut { appid: "nox"; name: "notchAllow"; description: "Agent notch: allow the oldest request"
                onPressed: if (root.req) Agents.answerReq(root.req, "allow"); else Panels.hud("Nothing waiting", "check") }
            GlobalShortcut { appid: "nox"; name: "notchAlways"; description: "Agent notch: always allow the oldest request"
                onPressed: if (root.req) Agents.answerReq(root.req, "always") }
            GlobalShortcut { appid: "nox"; name: "notchDeny"; description: "Agent notch: deny the oldest request"
                onPressed: if (root.req) Agents.answerReq(root.req, "deny") }
            GlobalShortcut { appid: "nox"; name: "notchToggle"; description: "Agent notch: open with the keyboard"
                onPressed: { if (root.reqShown) { root.kbd = true; } else if (root.req) { root.laterId = ""; root.kbd = true; } else root.toggle(); } }
        }
    }

    PanelWindow {
        id: win
        readonly property ShellScreen scr: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
        readonly property bool full: Hyprland.monitorFor(scr)?.activeWorkspace?.hasFullscreen ?? false
        readonly property bool hovered: hover.hovered
        screen: scr
        visible: root.mode !== "hidden" && !(full && root.mode !== "need")
        color: "transparent"
        WlrLayershell.namespace: "nox:notch"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.kbd ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors.top: true
        implicitWidth: 860
        implicitHeight: 760
        mask: Region { item: hit }

        HyprlandFocusGrab {
            active: root.kbd
            windows: [win].concat(Panels.barWindows)
            onCleared: { root.kbd = false; root.pinned = false; root.peek = false; }
        }

        // target size per mode; the body glides there on a spring
        readonly property real tw: root.mode === "lip" ? 96
            : root.mode === "compact" ? compact.implicitWidth
            : root.mode === "need" ? request.implicitWidth
            : root.mode === "done" ? done.implicitWidth
            : root.mode === "panel" ? panel.implicitWidth : 96
        readonly property real th: root.mode === "lip" ? 6
            : root.mode === "compact" ? Theme.barHeight + 8
            : root.mode === "need" ? request.implicitHeight
            : root.mode === "done" ? done.implicitHeight
            : root.mode === "panel" ? panel.implicitHeight : 6
        readonly property real tr: root.mode === "lip" ? 6 : root.mode === "compact" ? (Theme.barHeight + 8) / 2 : 22
        property real bw: tw
        property real bh: th
        property real br: tr
        Behavior on bw { NumberAnimation { duration: 560; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on bh { NumberAnimation { duration: 560; easing.type: Easing.OutBack; easing.overshoot: 0.7 } }
        Behavior on br { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
        readonly property bool big: root.mode === "need" || root.mode === "done" || root.mode === "panel"

        // soft shadow under the open notch (a gradient, no effect layer)
        Shape {
            id: shadow
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.bh - 40
            width: win.bw + 120; height: 120
            opacity: win.big ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 300 } }
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: shadow.width / 2; centerY: 40; centerRadius: shadow.width / 2
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0) }
                }
                PathRectangle { x: 0; y: 0; width: shadow.width; height: shadow.height }
            }
        }
        // halo: light leaking from under the notch (red = needs you, white = done, faint accent = working)
        Shape {
            id: halo
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.bh - 34
            width: win.bw * 0.92; height: 76
            readonly property color c: root.mode === "need" ? Qt.rgba(1, 0.33, 0.09, 1) : root.mode === "done" ? Qt.rgba(1, 1, 1, 1) : Theme.accent
            readonly property real strength: root.mode === "need" ? 0.7 : root.mode === "done" ? 0.22 : 0
            opacity: strength
            Behavior on opacity { NumberAnimation { duration: 500 } }
            SequentialAnimation on scale {
                running: root.mode === "need"
                loops: Animation.Infinite
                NumberAnimation { to: 0.86; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 1100; easing.type: Easing.InOutSine }
            }
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: halo.width / 2; centerY: halo.height / 2; centerRadius: halo.width / 2
                    focalX: centerX; focalY: centerY
                    GradientStop { position: 0; color: Qt.rgba(halo.c.r, halo.c.g, halo.c.b, 0.85) }
                    GradientStop { position: 0.35; color: Qt.rgba(halo.c.r, halo.c.g, halo.c.b, 0.3) }
                    GradientStop { position: 1; color: Qt.rgba(halo.c.r, halo.c.g, halo.c.b, 0) }
                }
                PathAngleArc { centerX: halo.width / 2; centerY: halo.height / 2; radiusX: halo.width / 2; radiusY: halo.height / 2; startAngle: 0; sweepAngle: 360 }
            }
        }

        NotchShape {
            id: body
            anchors.horizontalCenter: parent.horizontalCenter
            y: 0
            bodyWidth: win.bw
            bodyHeight: win.bh
            r: win.br
            shoulder: root.mode === "lip" ? 6 : 14
        }
        // a hairline along the bottom edge of the open notch
        Rectangle {
            visible: win.big
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.bh - 1
            width: win.bw - win.br * 2; height: 1
            color: Theme.white(0.07)
        }

        // input + hover region = the body
        Item {
            id: hit
            anchors.horizontalCenter: parent.horizontalCenter
            width: win.bw + 28
            height: Math.max(win.bh, 8)
            HoverHandler { id: hover }
        }
        // hover the compact line a moment = peek at the panel; leaving closes a peek
        Timer { id: peekIn; interval: root.opts.hoverDelay ?? 350; onTriggered: if (hover.hovered && root.mode === "compact") root.peek = true }
        Timer { id: peekOut; interval: 420; onTriggered: if (!hover.hovered && !root.pinned) root.peek = false }
        Connections {
            target: hover
            function onHoveredChanged() { if (hover.hovered) { peekOut.stop(); if (root.mode === "compact") peekIn.restart(); } else { peekIn.stop(); peekOut.restart(); } }
        }

        // contents: clipped to the body, each laid out at its own full size
        Item {
            id: clipper
            anchors.horizontalCenter: parent.horizontalCenter
            width: win.bw
            height: win.bh
            clip: true
            focus: true

            NotchLayer {
                on: root.mode === "compact"
                anchors.horizontalCenter: parent.horizontalCenter
                width: compact.implicitWidth; height: compact.implicitHeight
                NotchCompact {
                    id: compact
                    anchors.fill: parent
                    now: root.now
                    rolling: !hover.hovered
                    list: { const r = Agents.rank; return Agents.alive.slice().sort((a, b) => (r[a.status] - r[b.status]) || (b.since - a.since)); }
                    onClicked: root.open()
                }
            }
            NotchLayer {
                on: root.mode === "need"
                anchors.horizontalCenter: parent.horizontalCenter
                width: request.implicitWidth; height: request.implicitHeight
                NotchRequest {
                    id: request
                    anchors.fill: parent
                    req: root.req
                    count: Agents.requests.length
                    now: root.now
                    focus: root.mode === "need"
                    onLater: root.later()
                    TapHandler { onTapped: { root.kbd = true; request.forceActiveFocus(); } }
                }
            }
            NotchLayer {
                on: root.mode === "done"
                anchors.horizontalCenter: parent.horizontalCenter
                width: done.implicitWidth; height: done.implicitHeight
                NotchDone {
                    id: done
                    anchors.fill: parent
                    sid: root.doneId
                    focus: root.mode === "done"
                    onClose: root.doneId = ""
                    onReplay: id => { root.doneId = ""; root.open("replay"); panel.replayOf(id); }
                    TapHandler { onTapped: { root.kbd = true; done.forceActiveFocus(); doneTimer.stop(); } }
                }
            }
            NotchLayer {
                on: root.mode === "panel"
                anchors.horizontalCenter: parent.horizontalCenter
                width: panel.implicitWidth; height: panel.implicitHeight
                NotchPanel {
                    id: panel
                    anchors.fill: parent
                    now: root.now
                    focus: root.mode === "panel"
                    onClose: root.close()
                    TapHandler { onTapped: { root.pinned = true; root.kbd = true; panel.forceActiveFocus(); } }
                }
            }
        }
        // hand the keyboard to whatever is on show
        Connections {
            target: root
            function onKbdChanged() { if (root.kbd) Qt.callLater(() => (root.mode === "need" ? request : root.mode === "done" ? done : panel).forceActiveFocus()); }
            function onModeChanged() { if (root.kbd) Qt.callLater(() => (root.mode === "need" ? request : root.mode === "done" ? done : panel).forceActiveFocus()); }
        }
    }
}

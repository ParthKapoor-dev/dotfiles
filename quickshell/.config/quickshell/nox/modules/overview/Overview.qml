pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Mission Control (mock #wsstrip + overview): namespace nox:overview, full screen.
// Top: a strip of desktops (176px thumbnails with their windows, current one ringed in the
// accent, "+" = next empty desktop). Below: the current desktop's windows spread out (mock
// overviewRects: 1 / 2 / 3 columns, 44x52 gaps, scale <= 0.72) with live previews and labels.
// Click a window = focus it; click a desktop = switch; drag a window onto a desktop = move it
// there. Keys (stay in Mission Control unless noted):
//   Left / Right (or Ctrl+)  previous / next desktop       Home / End  first / last desktop
//   Up / Down, Tab / Shift+Tab  select a window             1-9  go to that desktop and close
//   Shift+Left / Right  move the selected window one desktop over (and follow it)
//   Shift+1-9  send the selected window to that desktop     Delete / Ctrl+W  close the selected window
//   Enter  focus the selected window (or just close)        Esc  close
// Typing anything else opens the launcher with that text. `qs -c nox ipc call overview toggle`.
//
// Motion (mock: windows transform from their real geometry, strip slides down, wallpaper dims):
// one progress value `p` (0 = desktop, 1 = overview) drives everything, eased on the sheet curve
// over motion.workspace. The surface stays loaded (only unmapped while closed) so the wallpaper is
// already decoded; on open the window copies are captured first (map at p = 0, where every copy
// sits exactly over its real window and the background is transparent), then p animates. Cells
// move with x/y + a scale transform, nothing re-lays out per frame.
Scope {
    id: root
    readonly property var opts: Config.opt.overview ?? ({})
    readonly property bool open: Panels.overviewOpen
    property bool shown: false          // surface mapped
    property bool capture: false        // screencopies active
    property real target: 0
    property real p: 0
    Behavior on p { NumberAnimation { duration: Theme.durWorkspace; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
    onOpenChanged: {
        if (open) {
            Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces();
            hideTimer.stop(); sel = -1;
            capture = true; shown = true;
            readyWait.elapsed = 0; readyWait.restart();
        } else {
            readyWait.stop();
            target = 0; p = 0;
            hideTimer.restart();
        }
    }
    // start the transition once every window copy has a frame (or after 160 ms)
    property var readyCheck: () => true
    Timer {
        id: readyWait
        property int elapsed: 0
        interval: 16; repeat: true
        onTriggered: {
            elapsed += interval;
            if (elapsed >= 48 && (root.readyCheck() || elapsed >= 160)) { stop(); root.target = 1; root.p = 1; }
        }
    }
    Timer { id: hideTimer; interval: Theme.durWorkspace + 20; onTriggered: { if (!root.open) { root.shown = false; root.capture = false; } } }
    property int sel: -1
    function lerp(a, b, t) { return a + (b - a) * t; }

    // loaded once and kept (unmapped while closed): wallpaper decoded, no black first frame
    LazyLoader {
        active: true
        PanelWindow {
            id: win
            visible: root.shown
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            readonly property var mon: Hyprland.monitorFor(win.screen)
            readonly property int curWs: mon?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1
            readonly property real sw: win.screen?.width ?? 1536
            readonly property real sh: win.screen?.height ?? 864
            readonly property real sx: win.screen?.x ?? 0
            readonly property real sy: win.screen?.y ?? 0
            color: "transparent"
            WlrLayershell.namespace: "nox:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            // focus goes back to the app only once the close transition is over (its refocus repaint
            // would otherwise compete with the transition); keys are ignored meanwhile (stage.enabled)
            WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            // windows on this monitor, by workspace
            readonly property var wins: Hyprland.toplevels.values.filter(t => t.monitor === win.mon && (t.workspace?.id ?? 0) > 0 && !(t.lastIpcObject?.hidden ?? false))
            function winsOn(ws) { return wins.filter(t => t.workspace?.id === ws); }
            readonly property int wsCount: Math.max(root.opts.minWorkspaces ?? 5, curWs, ...Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === win.mon).map(w => w.id))
            readonly property var current: winsOn(curWs)
            // thumbnail width: 176 (mock) unless that many desktops + "+" would not fit the screen
            readonly property real thumbW: Math.max(72, Math.min(176, (sw - 80 - 44 - wsCount * 22) / Math.max(1, wsCount)))
            function close() { Panels.overviewOpen = false; }
            function go(ws) { Hypr.workspace(ws); close(); }
            // switch desktop behind Mission Control and stay open (arrow keys)
            function browse(ws) {
                ws = Math.max(1, Math.min(wsCount, ws));
                if (ws === curWs) return;
                root.sel = -1;
                Hypr.workspace(ws);
                Qt.callLater(Hyprland.refreshToplevels);
            }
            // move a window to desktop ws; follow = switch there too and keep it selected
            property string reselect: ""
            function send(t, ws, follow) {
                Hypr.moveToWorkspace(t.address, ws);
                if (follow) { reselect = t.address; Hypr.workspace(ws); }
                else root.sel = -1;
                Qt.callLater(Hyprland.refreshToplevels);
            }
            Connections {
                target: Panels
                function onOverviewStep(delta) { if (root.open) win.browse(win.curWs + delta); }
            }
            onCurrentChanged: {
                if (reselect === "") { if (root.sel >= current.length) root.sel = current.length - 1; return; }
                const i = current.findIndex(t => t.address === reselect);
                if (i >= 0) { root.sel = i; reselect = ""; }
            }
            function focus(t) { Hypr.focusWindow(t.address); close(); }

            // background: the wallpaper fades in over the desktop, dimmed (mock brightness .55).
            // Opaque base so the real windows never show through behind their copies; the image is
            // the decode Wallpaper keeps alive (same url/sourceSize/fill = cache hit, no pop).
            Item {
                anchors.fill: parent
                opacity: root.p
                Rectangle { anchors.fill: parent; color: Theme.page }
                Image {
                    id: backdrop
                    anchors.fill: parent
                    source: Wallpaper.displayUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize: Wallpaper.screenSize
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
                }
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }
            }
            MouseArea { anchors.fill: parent; enabled: root.open; onClicked: win.close() }

            Item {
                id: stage
                anchors.fill: parent
                enabled: root.open
                focus: true
                Keys.onPressed: e => {
                    const n = win.current.length;
                    const shift = e.modifiers & Qt.ShiftModifier, ctrl = e.modifiers & Qt.ControlModifier;
                    const picked = root.sel >= 0 ? win.current[root.sel] ?? null : null;
                    // Shift+digit arrives as its symbol (US layout); the native key code is layout-free
                    const shiftDigit = shift ? "!@#$%^&*(".indexOf(e.text) + 1 : 0;
                    if (e.key === Qt.Key_Escape) win.close();
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (picked) win.focus(picked); else win.close(); }
                    else if (shiftDigit > 0) { if (picked) win.send(picked, shiftDigit, false); }
                    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9 && !ctrl && !shift) win.go(e.key - Qt.Key_0);
                    else if ((e.key === Qt.Key_Left || e.key === Qt.Key_Right) && shift) {
                        const to = win.curWs + (e.key === Qt.Key_Right ? 1 : -1);
                        if (picked && to >= 1) win.send(picked, to, true);
                    }
                    else if (e.key === Qt.Key_Left) win.browse(win.curWs - 1);
                    else if (e.key === Qt.Key_Right) win.browse(win.curWs + 1);
                    else if (e.key === Qt.Key_Home) win.browse(1);
                    else if (e.key === Qt.Key_End) win.browse(win.wsCount);
                    else if (e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { if (n) root.sel = (root.sel + 1) % n; }
                    else if (e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) { if (n) root.sel = (root.sel - 1 + n) % n; }
                    else if (e.key === Qt.Key_Delete || (ctrl && e.key === Qt.Key_W)) { if (picked) Hypr.closeWindow(picked.address); }
                    else if (e.text && e.text.trim() !== "" && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                        win.close(); Panels.openLauncher(e.text);
                    } else return;
                    e.accepted = true;
                }

                // key hints along the bottom edge
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 22
                    opacity: 0.55 * root.p
                    text: Theme.labelsMono
                        ? "←→ DESKTOPS   ↑↓ WINDOWS   ⇧←→ MOVE WINDOW   ⇧1-9 SEND   DEL CLOSE   ↵ OPEN   ESC"
                        : "←→ Desktops    ↑↓ Windows    ⇧←→ Move window    ⇧1–9 Send    Del Close    ↵ Open    Esc"
                    color: Theme.label
                    font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
                    font.pixelSize: Theme.labelsMono ? 10 : 11.5
                    font.letterSpacing: Theme.labelsMono ? 1.6 : 0.2
                }

                // ---- desktop strip (mock #wsstrip: 156px, gradient, 176x99 thumbs, 22px gap) ----
                Rectangle {
                    width: parent.width; height: 156
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    opacity: Math.min(1, root.p * 1.6)
                    transform: Translate { y: root.lerp(-166, 0, root.p) }
                    Row {
                        id: strip
                        anchors.centerIn: parent
                        spacing: 22
                        Repeater {
                            id: thumbs
                            model: win.wsCount
                            Column {
                                id: th
                                required property int index
                                readonly property int ws: index + 1
                                readonly property bool cur: ws === win.curWs
                                readonly property bool drop: dragProxy.active && dragProxy.overWs === ws
                                // like area.list: only reset the miniatures when the set of windows
                                // changes, so the refresh at open does not recreate them (and restart
                                // their captures) in the middle of the transition
                                readonly property var fresh: win.winsOn(ws)
                                property var list: []
                                property string listKey: ""
                                onFreshChanged: { const k = fresh.map(t => t.address).join(","); if (k !== listKey) { listKey = k; list = fresh; } }
                                Component.onCompleted: { listKey = fresh.map(t => t.address).join(","); list = fresh; }
                                spacing: 7
                                Item {
                                    id: mini
                                    width: win.thumbW; height: Math.round(win.thumbW * win.sh / win.sw)
                                    transform: Translate {
                                        y: thMouse.containsMouse ? -2 : 0
                                        Behavior on y { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                                    }
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: th.cur || th.drop ? -2 : -1
                                        radius: (Theme.square ? 4 : 8) + 2
                                        color: th.cur || th.drop ? Theme.accent : thMouse.containsMouse ? Theme.white(0.3) : Theme.white(0.16)
                                        Behavior on color { ColorAnimation { duration: Theme.durHover } }
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.square ? 4 : 8
                                        color: "black"
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            source: Wallpaper.displayUrl
                                            fillMode: Image.PreserveAspectCrop
                                            sourceSize.width: 352
                                            asynchronous: true
                                        }
                                        Repeater {
                                            model: th.list
                                            Item {
                                                id: mw
                                                required property var modelData
                                                readonly property var o: modelData.lastIpcObject ?? ({})
                                                readonly property real k: mini.width / win.sw
                                                x: ((o.at?.[0] ?? 0) - win.sx) * k; y: ((o.at?.[1] ?? 0) - win.sy) * k
                                                width: Math.max(4, (o.size?.[0] ?? 100) * k); height: Math.max(4, (o.size?.[1] ?? 100) * k)
                                                Rectangle { anchors.fill: parent; radius: 3; color: Theme.bg; border.width: 0.5; border.color: Theme.white(0.15) }
                                                ScreencopyView {
                                                    anchors.fill: parent
                                                    captureSource: root.capture && mw.modelData.wayland ? mw.modelData.wayland : null
                                                    live: false
                                                }
                                            }
                                        }
                                    }
                                    MouseArea { id: thMouse; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(th.ws) }
                                }
                                GText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Desktop " + th.ws
                                    font.pixelSize: 12
                                    font.weight: th.cur ? Font.DemiBold : Font.Normal
                                    color: th.cur ? Theme.label : Theme.label2
                                }
                                function contains(p) { const q = mini.mapFromItem(stage, p.x, p.y); return q.x >= 0 && q.y >= 0 && q.x <= mini.width && q.y <= mini.height; }
                            }
                        }
                        // "+" (mock .wsadd): next empty desktop
                        Rectangle {
                            width: 44; height: Math.round(win.thumbW * win.sh / win.sw)
                            radius: Theme.square ? 4 : 8
                            color: addMouse.containsMouse ? Theme.white(0.14) : Theme.white(0.08)
                            Behavior on color { ColorAnimation { duration: Theme.durHover } }
                            border.width: 1; border.color: Theme.white(0.1)
                            Glyph { anchors.centerIn: parent; name: "plus"; size: 18; color: Theme.label2 }
                            MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(win.wsCount + 1) }
                        }
                    }
                }

                // ---- current desktop's windows (mock overviewRects) ----
                Item {
                    id: area
                    anchors.fill: parent
                    // spread area: x 80, from 178 to above the dock
                    readonly property real ax: 80
                    readonly property real ay: 178
                    readonly property real aw: win.sw - 160
                    readonly property real ah: win.sh - (Panels.dockVisible ? Theme.dockSize + 44 : 44) - ay
                    // reading order of the real windows (rows of 260px, then x)
                    // the Repeater only resets when the set of windows changes (a refresh of their
                    // geometry must not recreate the delegates and restart their captures)
                    property var list: []
                    property string listKey: ""
                    onSortedChanged: { const k = sorted.map(t => t.address).join(","); if (k !== listKey) { listKey = k; list = sorted; } }
                    readonly property var sorted: {
                        const c = t => { const o = t.lastIpcObject ?? {}; return [(o.at?.[0] ?? 0) + (o.size?.[0] ?? 0) / 2, (o.at?.[1] ?? 0) + (o.size?.[1] ?? 0) / 2]; };
                        return win.current.slice().sort((x, y) => { const a = c(x), b = c(y); return (Math.round(a[1] / 260) - Math.round(b[1] / 260)) * 10000 + (a[0] - b[0]); });
                    }
                    readonly property int n: list.length
                    readonly property int cols: n <= 1 ? 1 : n <= 4 ? 2 : 3
                    readonly property int rows: Math.max(1, Math.ceil(n / cols))
                    readonly property real gx: 44
                    readonly property real gy: 52
                    readonly property real cw: (aw - gx * (cols - 1)) / cols
                    readonly property real ch: (ah - gy * (rows - 1)) / rows

                    GText {
                        visible: area.n === 0
                        opacity: root.p
                        anchors.centerIn: parent
                        text: "No windows on Desktop " + win.curWs
                        secondary: true
                        font.pixelSize: 15
                    }

                    Repeater {
                        id: cells
                        model: area.list
                        Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property var o: modelData.lastIpcObject ?? ({})
                            // real geometry (screen-local)
                            readonly property real fx: (o.at?.[0] ?? 0) - win.sx
                            readonly property real fy: (o.at?.[1] ?? 0) - win.sy
                            readonly property real ww: Math.max(40, o.size?.[0] ?? 800)
                            readonly property real wh: Math.max(30, o.size?.[1] ?? 500)
                            // spread geometry
                            readonly property int col: index % area.cols
                            readonly property int row: Math.floor(index / area.cols)
                            readonly property int inRow: row === area.rows - 1 ? area.n - row * area.cols : area.cols
                            readonly property real off: (area.cols - inRow) * (area.cw + area.gx) / 2
                            readonly property real ts: Math.min(area.cw / ww, (area.ch - 26) / wh, 0.72)
                            readonly property real tx: area.ax + off + col * (area.cw + area.gx) + (area.cw - ww * ts) / 2
                            readonly property real ty: area.ay + row * (area.ch + area.gy) + (area.ch - 26 - wh * ts) / 2
                            readonly property real s: root.lerp(1, ts, root.p)
                            readonly property bool hot: cellMouse.containsMouse || root.sel === index
                            readonly property bool ready: shotView.hasContent
                            x: root.lerp(fx, tx, root.p)
                            y: root.lerp(fy, ty, root.p)
                            width: ww * s; height: wh * s
                            visible: !(dragProxy.active && dragProxy.target === cell)

                            // the window copy at full size, scaled (transform only)
                            Item {
                                id: body
                                width: cell.ww; height: cell.wh
                                transformOrigin: Item.TopLeft
                                scale: cell.s
                                RectangularShadow {
                                    anchors.fill: parent; radius: Theme.radiusWindow
                                    offset.y: 14; blur: 40; spread: -8
                                    color: Qt.rgba(0, 0, 0, 0.5)
                                    opacity: root.p
                                }
                                Rectangle { anchors.fill: parent; color: Theme.bg; radius: Theme.radiusWindow; opacity: cell.ready ? 0 : root.p }
                                ScreencopyView {
                                    id: shotView
                                    anchors.fill: parent
                                    captureSource: root.capture && cell.modelData.wayland ? cell.modelData.wayland : null
                                    // frozen while closing: the refocused window repaints then, and copying
                                    // those frames would compete with the transition
                                    live: (root.opts.live ?? true) && root.open
                                }
                                // hover / selection ring (mock: inset 3px accent, constant on screen)
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    radius: Theme.radiusWindow
                                    border.width: (cell.hot ? 3 : 1) / Math.max(0.05, cell.s)
                                    border.color: cell.hot ? Theme.accent : Theme.white(0.12)
                                    opacity: cell.hot ? 1 : root.p
                                    Behavior on border.color { ColorAnimation { duration: Theme.durHover } }
                                }
                            }
                            // app label (mock .ov-label)
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom; anchors.topMargin: 12
                                width: lbl.implicitWidth + 20; height: lbl.implicitHeight + 6
                                radius: Theme.square ? 3 : 8
                                color: Qt.rgba(0, 0, 0, 0.45)
                                opacity: Math.max(0, root.p * 2 - 1)
                                GText {
                                    id: lbl
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, cell.ww * cell.ts + 40)
                                    text: Apps.entryFor(cell.o.class ?? cell.modelData.wayland?.appId ?? "")?.name || cell.o.class || cell.modelData.title
                                    color: "white"
                                    font.weight: Font.DemiBold
                                }
                            }
                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.open
                                property point pressAt
                                onPressed: m => pressAt = Qt.point(m.x, m.y)
                                onPositionChanged: m => {
                                    if (!pressed) return;
                                    if (!dragProxy.active && Math.hypot(m.x - pressAt.x, m.y - pressAt.y) > 8) dragProxy.start(cell, mapToItem(stage, m.x, m.y));
                                    if (dragProxy.active) dragProxy.moveTo(mapToItem(stage, m.x, m.y));
                                }
                                onReleased: m => { if (dragProxy.active) dragProxy.finish(); }
                                onClicked: if (!dragProxy.wasDrag) win.focus(cell.modelData)
                            }
                        }
                    }
                    Component.onCompleted: {
                        listKey = sorted.map(t => t.address).join(","); list = sorted;
                        root.readyCheck = () => {
                            if (backdrop.status === Image.Loading) return false;
                            for (let i = 0; i < cells.count; i++) { const c = cells.itemAt(i); if (c && !c.ready) return false; }
                            return true;
                        };
                    }
                }

                // drag proxy: a small copy of the window that follows the pointer; it shrinks from
                // the cell's size when picked up and eases between positions
                Item {
                    id: dragProxy
                    property bool active: false
                    property bool wasDrag: false
                    property var target: null
                    property int overWs: -1
                    property real k: 1               // 1 = cell size, 0 = 150px proxy
                    visible: active
                    readonly property real pw: 150
                    readonly property real ph: 150 * win.sh / win.sw
                    width: target ? root.lerp(pw, target.width, k) : pw
                    height: target ? root.lerp(ph, target.height, k) : ph
                    Behavior on k { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                    property point at: Qt.point(0, 0)
                    x: at.x - width / 2; y: at.y - height / 2
                    opacity: 0.92
                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Theme.bg
                        border.width: 2
                        border.color: dragProxy.overWs > 0 ? Theme.accent : Theme.white(0.3)
                        Behavior on border.color { ColorAnimation { duration: Theme.durHover } }
                    }
                    ScreencopyView { anchors.fill: parent; anchors.margins: 2; captureSource: dragProxy.active && dragProxy.target ? dragProxy.target.modelData.wayland : null; live: false }
                    function start(c, p) {
                        target = c; k = 1; at = p; active = true; wasDrag = true;
                        k = 0;
                    }
                    function moveTo(p) {
                        at = p;
                        overWs = -1;
                        for (let i = 0; i < thumbs.count; i++) { const t = thumbs.itemAt(i); if (t && t.contains(p)) { overWs = t.ws; break; } }
                    }
                    function finish() {
                        if (overWs > 0 && target) Hypr.moveToWorkspace(target.modelData.address, overWs);
                        active = false; overWs = -1; target = null;
                        Qt.callLater(() => { dragProxy.wasDrag = false; Hyprland.refreshToplevels(); });
                    }
                }
            }
        }
    }
}

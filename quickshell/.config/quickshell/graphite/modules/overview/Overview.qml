pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Mission Control (mock #wsstrip + overview): namespace graphite:overview, full screen over the
// dimmed wallpaper. Top: a strip of desktops (176px thumbnails with their windows, current one
// ringed in the accent, "+" = next empty desktop). Below: the current desktop's windows laid out
// in a grid with live previews (ScreencopyView, only while open) and app-name labels.
// Click a window = focus it; click a desktop = switch; drag a window onto a desktop = move it
// there. Keys: Esc / Enter close, 1-9 switch desktop, ←→↑↓ select, typing opens the launcher
// with that text. `qs -c graphite ipc call overview toggle`.
Scope {
    id: root
    readonly property var opts: Config.opt.overview ?? ({})
    readonly property bool open: Panels.overviewOpen
    property bool shown: false
    onOpenChanged: {
        if (open) { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); hideTimer.stop(); sel = -1; shown = true; }
        else hideTimer.restart();
    }
    Timer { id: hideTimer; interval: Theme.durWorkspace; onTriggered: root.shown = false }
    property int sel: -1

    LazyLoader {
        active: root.shown
        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            readonly property var mon: Hyprland.monitorFor(win.screen)
            readonly property int curWs: mon?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1
            readonly property real sw: win.screen?.width ?? 1536
            readonly property real sh: win.screen?.height ?? 864
            readonly property real sx: win.screen?.x ?? 0
            readonly property real sy: win.screen?.y ?? 0
            color: "black"
            WlrLayershell.namespace: "graphite:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            // windows on this monitor, by workspace
            readonly property var wins: Hyprland.toplevels.values.filter(t => t.monitor === win.mon && (t.workspace?.id ?? 0) > 0 && !(t.lastIpcObject?.hidden ?? false))
            function winsOn(ws) { return wins.filter(t => t.workspace?.id === ws); }
            readonly property int wsCount: Math.max(root.opts.minWorkspaces ?? 5, curWs, ...Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === win.mon).map(w => w.id))
            readonly property var current: winsOn(curWs)
            function close() { Panels.overviewOpen = false; }
            function go(ws) { Hypr.workspace(ws); close(); }
            function focus(t) { Hypr.focusWindow(t.address); close(); }

            // background: dimmed wallpaper (mock: brightness .55)
            Image {
                anchors.fill: parent
                source: Wallpaper.url
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: win.sw; sourceSize.height: win.sh
            }
            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }
            MouseArea { anchors.fill: parent; onClicked: win.close() }

            Item {
                id: stage
                anchors.fill: parent
                opacity: root.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                focus: true
                Keys.onPressed: e => {
                    const n = win.current.length;
                    if (e.key === Qt.Key_Escape) win.close();
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (root.sel >= 0 && win.current[root.sel]) win.focus(win.current[root.sel]); else win.close(); }
                    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9 && !(e.modifiers & Qt.ControlModifier)) win.go(e.key - Qt.Key_0);
                    else if (e.key === Qt.Key_Right || e.key === Qt.Key_Down || e.key === Qt.Key_Tab) { if (n) root.sel = (root.sel + 1) % n; }
                    else if (e.key === Qt.Key_Left || e.key === Qt.Key_Up || e.key === Qt.Key_Backtab) { if (n) root.sel = (root.sel - 1 + n) % n; }
                    else if (e.text && e.text.trim() !== "" && !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                        win.close(); Panels.openLauncher(e.text);
                    } else return;
                    e.accepted = true;
                }

                // ---- desktop strip (mock #wsstrip: 156px, gradient, 176x99 thumbs, 22px gap) ----
                Rectangle {
                    width: parent.width; height: 156
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    transform: Translate {
                        y: root.open ? 0 : -160
                        Behavior on y { NumberAnimation { duration: Theme.durWorkspace; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                    }
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
                                spacing: 7
                                Item {
                                    id: mini
                                    width: 176; height: Math.round(176 * win.sh / win.sw)
                                    y: thMouse.containsMouse ? -2 : 0
                                    Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: th.cur || th.drop ? -2 : -1
                                        radius: (Theme.square ? 4 : 8) + 2
                                        color: th.cur || th.drop ? Theme.accent : Theme.white(0.16)
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Theme.square ? 4 : 8
                                        color: "black"
                                        clip: true
                                        Image {
                                            anchors.fill: parent
                                            source: Wallpaper.url
                                            fillMode: Image.PreserveAspectCrop
                                            sourceSize.width: 352
                                            asynchronous: true
                                        }
                                        Repeater {
                                            model: win.winsOn(th.ws)
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
                                                    captureSource: root.open && mw.modelData.wayland ? mw.modelData.wayland : null
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
                            width: 44; height: Math.round(176 * win.sh / win.sw)
                            radius: Theme.square ? 4 : 8
                            color: addMouse.containsMouse ? Theme.white(0.14) : Theme.white(0.08)
                            border.width: 1; border.color: Theme.white(0.1)
                            Glyph { anchors.centerIn: parent; name: "plus"; size: 18; color: Theme.label2 }
                            MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; onClicked: win.go(win.wsCount + 1) }
                        }
                    }
                }

                // ---- current desktop's windows (exposé grid) ----
                Item {
                    id: area
                    x: 60; y: 176
                    width: parent.width - 120; height: parent.height - 176 - 40
                    readonly property int n: win.current.length
                    readonly property int cols: Math.max(1, Math.ceil(Math.sqrt(n * (width / height) / (win.sw / win.sh))))
                    readonly property int rows: Math.max(1, Math.ceil(n / cols))
                    readonly property real cw: width / cols
                    readonly property real ch: height / rows

                    GText {
                        visible: area.n === 0
                        anchors.centerIn: parent
                        text: "No windows on Desktop " + win.curWs
                        secondary: true
                        font.pixelSize: 15
                    }

                    Repeater {
                        model: win.current
                        Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property var o: modelData.lastIpcObject ?? ({})
                            readonly property real ww: o.size?.[0] ?? 800
                            readonly property real wh: o.size?.[1] ?? 500
                            readonly property real k: Math.min((area.cw - 40) / ww, (area.ch - 56) / wh, 0.8)
                            readonly property int col: index % area.cols
                            readonly property int row: Math.floor(index / area.cols)
                            readonly property int rowCount: Math.min(area.cols, area.n - row * area.cols)
                            readonly property real rowOffset: (area.cols - rowCount) * area.cw / 2
                            readonly property bool hot: cellMouse.containsMouse || root.sel === index
                            x: rowOffset + col * area.cw + (area.cw - width) / 2
                            y: row * area.ch + (area.ch - height - 34) / 2
                            width: ww * k; height: wh * k
                            scale: root.open ? 1 : 0.94
                            Behavior on scale { NumberAnimation { duration: Theme.durWorkspace; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                            RectangularShadow {
                                anchors.fill: shot; radius: Theme.radiusWindow * cell.k
                                offset.y: 12; blur: 30; spread: -6
                                color: Qt.rgba(0, 0, 0, 0.5)
                            }
                            Rectangle { id: shot; anchors.fill: parent; color: Theme.bg; radius: Theme.radiusWindow * cell.k }
                            ScreencopyView {
                                anchors.fill: parent
                                captureSource: root.open && cell.modelData.wayland ? cell.modelData.wayland : null
                                live: root.opts.live ?? true
                            }
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                radius: Theme.radiusWindow * cell.k
                                border.width: cell.hot ? 3 : 1
                                border.color: cell.hot ? Theme.accent : Theme.white(0.12)
                            }
                            // app label (mock .ov-label)
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom; anchors.topMargin: 14
                                width: lbl.implicitWidth + 20; height: lbl.implicitHeight + 6
                                radius: Theme.square ? 3 : 8
                                color: Qt.rgba(0, 0, 0, 0.45)
                                GText {
                                    id: lbl
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, cell.width + 40)
                                    text: Apps.entryFor(cell.o.class ?? cell.modelData.wayland?.appId ?? "")?.name || cell.o.class || cell.modelData.title
                                    color: "white"
                                    font.weight: Font.DemiBold
                                }
                            }
                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                property point pressAt
                                onPressed: m => pressAt = Qt.point(m.x, m.y)
                                onPositionChanged: m => {
                                    if (!pressed) return;
                                    if (!dragProxy.active && Math.hypot(m.x - pressAt.x, m.y - pressAt.y) > 8) dragProxy.start(cell);
                                    if (dragProxy.active) dragProxy.moveTo(mapToItem(stage, m.x, m.y));
                                }
                                onReleased: m => { if (dragProxy.active) dragProxy.finish(); }
                                onClicked: if (!dragProxy.wasDrag) win.focus(cell.modelData)
                            }
                        }
                    }
                }

                // drag proxy: a small copy of the window that follows the pointer
                Rectangle {
                    id: dragProxy
                    property bool active: false
                    property bool wasDrag: false
                    property var target: null
                    property int overWs: -1
                    visible: active
                    width: 150; height: 150 * win.sh / win.sw
                    radius: 6
                    color: Theme.bg
                    border.width: 2; border.color: Theme.accent
                    opacity: 0.9
                    ScreencopyView { anchors.fill: parent; anchors.margins: 2; captureSource: dragProxy.active && dragProxy.target ? dragProxy.target.modelData.wayland : null; live: false }
                    function start(c) { target = c; active = true; wasDrag = true; }
                    function moveTo(p) {
                        x = p.x - width / 2; y = p.y - height / 2;
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

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Alt+Tab window switcher (namespace nox:switcher). Windows in most-recently-used order (all
// desktops, minimized last): a strip of app icons on glass, the selected one ringed, and a live
// preview of the selected window with its title above the strip; the rest of the screen dims.
// Hold Alt, tap Tab to step (Shift+Tab back), release Alt = switch. A quick Alt+Tab tap switches
// to the previous window without the UI ever showing (it only appears after switcher.showDelay ms,
// 110). Also: arrows / Tab inside, Enter = switch, Esc = cancel, Q / W = close the selected
// window, hover selects, click switches.
// Keys reach it as Hyprland global shortcuts (appid "nox", bound in hypr nox/shells/nox.lua):
//   switcherNext (Alt+Tab), switcherPrev (Alt+Shift+Tab), switcherAlt (Alt_L, non-consuming: its
//   release commits). Panels.switcher(cmd) is the entry point; IPC: `qs -c nox ipc call switcher next|prev|commit|cancel`.
// The MRU order is tracked here from Hyprland.activeToplevel, seeded once from hyprctl's focusHistoryID.
Scope {
    id: root
    readonly property var opts: Config.opt.switcher ?? ({})

    // ---- most recently used ----
    property var mru: []                  // window addresses, most recent first
    function touch(addr) {
        if (!addr) return;
        mru = [addr].concat(mru.filter(a => a !== addr)).slice(0, 200);
    }
    readonly property var activeAddr: Hyprland.activeToplevel?.address ?? ""
    onActiveAddrChanged: if (activeAddr && !open) touch(norm(activeAddr))
    Process {
        running: true
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const seen = JSON.parse(text).filter(c => c.focusHistoryID >= 0).sort((a, b) => a.focusHistoryID - b.focusHistoryID)
                        .map(c => c.address.replace(/^0x/, ""));
                    root.mru = root.mru.concat(seen.filter(a => root.mru.indexOf(a) < 0));
                } catch (e) {}
            }
        }
    }
    function norm(a) { return String(a ?? "").replace(/^0x/, ""); }

    // windows to offer: every mapped window, MRU first, unknown ones after, minimized last
    function snapshot() {
        const all = Hyprland.toplevels.values.filter(t => t.wayland && (t.workspace?.id ?? 0) !== 0);
        const rank = a => { const i = mru.indexOf(norm(a)); return i < 0 ? 1e6 : i; };
        const minimized = t => (t.workspace?.name ?? "").startsWith("special:minimized");
        return all.slice().sort((x, y) => (minimized(x) - minimized(y)) || (rank(x.address) - rank(y.address)));
    }

    // ---- state ----
    property bool open: false             // armed (Alt held, Tab pressed)
    property bool shown: false            // UI visible (after showDelay)
    property var list: []
    property int sel: 0
    readonly property var current: list[sel] ?? null

    function step(d) {
        if (!open) {
            list = snapshot();
            if (list.length === 0) return;
            // the first entry is the focused window: Alt+Tab goes to the one before it
            const focusedFirst = norm(list[0].address) === norm(activeAddr);
            sel = d > 0 ? (focusedFirst && list.length > 1 ? 1 : 0) : list.length - 1;
            open = true;
            showTimer.restart();
            return;
        }
        if (list.length) sel = (sel + d + list.length) % list.length;
    }
    function commit() {
        if (!open) return;
        const t = current;
        close();
        if (!t) return;
        touch(norm(t.address));
        Hypr.focusWindow(t.address);
    }
    function close() { showTimer.stop(); open = false; shown = false; }
    function closeSelected() {
        const t = current;
        if (!t) return;
        Hypr.closeWindow(t.address);
        list = list.filter(x => x !== t);
        if (!list.length) { close(); return; }
        sel = Math.min(sel, list.length - 1);
    }
    Timer { id: showTimer; interval: root.opts.showDelay ?? 110; onTriggered: if (root.open) root.shown = true }

    Connections {
        target: Panels
        function onSwitcherCommand(cmd) {
            if (cmd === "next") root.step(1);
            else if (cmd === "prev") root.step(-1);
            else if (cmd === "commit") root.commit();
            else if (cmd === "cancel") root.close();
        }
    }
    // a window closing while the switcher is up
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() {
            if (!root.open) return;
            const live = Hyprland.toplevels.values;
            const keep = root.list.filter(t => live.indexOf(t) >= 0);
            if (keep.length === root.list.length) return;
            const cur = root.current;
            root.list = keep;
            if (!keep.length) { root.close(); return; }
            const i = keep.indexOf(cur);
            root.sel = i >= 0 ? i : Math.min(root.sel, keep.length - 1);
        }
    }

    function iconFor(t) {
        const cls = t?.lastIpcObject?.class || t?.wayland?.appId || "";
        const e = Apps.entryFor(cls);
        return Quickshell.iconPath(e?.icon || cls.toLowerCase(), "application-x-executable");
    }
    function appName(t) {
        const cls = t?.lastIpcObject?.class || t?.wayland?.appId || "";
        return Apps.entryFor(cls)?.name || cls;
    }

    // ---- UI ----
    LazyLoader {
        active: true
        PanelWindow {
            id: win
            visible: root.shown || fade.opacity > 0.01
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "nox:switcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            readonly property real sw: width
            readonly property int n: root.list.length
            // icon tiles shrink to fit at most 88% of the screen width
            readonly property real tile: Math.max(44, Math.min(84, (sw * 0.88 - 24) / Math.max(1, n)))
            readonly property real icon: Math.round(tile * 0.66)

            Item {
                id: fade
                anchors.fill: parent
                opacity: root.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: root.shown ? Theme.durPop : Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

                // dim the desktop a little
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, root.opts.dim ?? 0.32) }
                MouseArea { anchors.fill: parent; onClicked: root.close() }

                Item {
                    id: keys
                    anchors.fill: parent
                    focus: true
                    Keys.onPressed: e => {
                        const shift = e.modifiers & Qt.ShiftModifier;
                        if (e.key === Qt.Key_Escape) root.close();
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.commit();
                        else if (e.key === Qt.Key_Right || (e.key === Qt.Key_Tab && !shift)) root.step(1);
                        else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab || (e.key === Qt.Key_Tab && shift)) root.step(-1);
                        else if (e.key === Qt.Key_Q || e.key === Qt.Key_W) root.closeSelected();
                        else return;
                        e.accepted = true;
                    }
                    // Alt released while the surface has the keyboard (the global shortcut covers the rest)
                    Keys.onReleased: e => { if (e.key === Qt.Key_Alt) { root.commit(); e.accepted = true; } }
                }

                Column {
                    id: stack
                    anchors.centerIn: parent
                    spacing: 18
                    scale: root.shown ? 1 : 0.97
                    Behavior on scale { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                    // live preview of the selected window
                    Item {
                        id: pv
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property real maxW: Math.min(win.sw * 0.5, 720)
                        readonly property real maxH: win.height * 0.42
                        readonly property var src: shot.sourceSize
                        readonly property real k: src.width > 0 ? Math.min(maxW / src.width, maxH / src.height) : 1
                        width: src.width > 0 ? Math.round(src.width * k) : maxW
                        height: src.width > 0 ? Math.round(src.height * k) : maxH * 0.7
                        Behavior on width { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                        Behavior on height { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                        RectangularShadow {
                            anchors.fill: parent
                            radius: Theme.radiusWindow
                            offset.y: 16; blur: 48; spread: -6
                            color: Qt.rgba(0, 0, 0, 0.55)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: Theme.radiusWindow
                            color: Theme.bg
                            border.width: 1
                            border.color: Theme.white(0.12)
                        }
                        ScreencopyView {
                            id: shot
                            anchors.fill: parent
                            anchors.margins: 1
                            captureSource: root.shown ? root.current?.wayland ?? null : null
                            live: true
                            opacity: hasContent ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
                        }
                    }

                    // title + app
                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 3
                        GText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(implicitWidth, pv.maxW)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: root.current?.title || root.appName(root.current)
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        GText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: {
                                const t = root.current;
                                const ws = t?.workspace;
                                const where = !ws ? "" : (ws.name ?? "").startsWith("special:minimized") ? "Minimized" : "Desktop " + ws.id;
                                return [root.appName(t), where].filter(x => x).join(" · ");
                            }
                            small: true
                            secondary: true
                        }
                    }

                    // icon strip
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: strip.width + 24
                        height: win.tile + 24
                        RectangularShadow {
                            anchors.fill: shelf
                            radius: shelf.radius
                            offset.y: 10; blur: 30; spread: -4
                            color: Qt.rgba(0, 0, 0, 0.4)
                        }
                        Glass {
                            id: shelf
                            anchors.fill: parent
                            menu: true
                            color: Theme.cardGlass
                            radius: Theme.square ? 8 : 22
                        }
                        // selection marker glides between tiles
                        Rectangle {
                            id: marker
                            readonly property var at: (cells.count, cells.itemAt(root.sel))
                            x: 12 + (at ? at.x : 0)
                            y: 12
                            width: win.tile; height: win.tile
                            radius: Theme.square ? 5 : 16
                            color: Theme.white(0.12)
                            border.width: Theme.square ? 1 : 0
                            border.color: Theme.white(0.22)
                            Behavior on x { enabled: root.shown; NumberAnimation { duration: Theme.durHover + 40; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 5
                                width: Theme.square ? 14 : 5; height: Theme.square ? 2 : 5
                                radius: Theme.square ? 0 : 2.5
                                color: Theme.accent
                            }
                        }
                        Row {
                            id: strip
                            x: 12; y: 12
                            Repeater {
                                id: cells
                                model: win.visible ? root.list : []
                                Item {
                                    id: cell
                                    required property var modelData
                                    required property int index
                                    width: win.tile; height: win.tile
                                    Image {
                                        anchors.centerIn: parent
                                        width: win.icon; height: win.icon
                                        sourceSize.width: win.icon * 2; sourceSize.height: win.icon * 2
                                        source: root.iconFor(cell.modelData)
                                        asynchronous: true
                                        smooth: true; mipmap: true
                                        scale: root.sel === cell.index ? 1.06 : 1
                                        opacity: (cell.modelData.workspace?.name ?? "").startsWith("special:minimized") ? 0.55 : 1
                                        Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        // only a real pointer move selects (the strip may open under a resting pointer)
                                        onPositionChanged: root.sel = cell.index
                                        onClicked: { root.sel = cell.index; root.commit(); }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

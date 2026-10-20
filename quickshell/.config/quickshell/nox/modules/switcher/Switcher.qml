pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Alt+Tab window switcher (namespace nox:switcher). Windows in most-recently-used order (all
// desktops, minimized last): a live hero preview of the selected window with its desktop/app/title
// set under it, over a filmstrip of window cards; the rest of the screen drops to near-black.
// Hold Alt, tap Tab to step (Shift+Tab back), release Alt = switch. A quick Alt+Tab tap switches
// to the previous window without the UI ever showing (it only appears after switcher.showDelay ms,
// 110). Also: arrows inside, Enter = switch, Esc = cancel, Q / W = close the selected
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
        // (Notes parks itself on special:notes while hidden: not a window to switch to)
        const all = Hyprland.toplevels.values.filter(t => t.wayland && (t.workspace?.id ?? 0) !== 0 && t.workspace?.name !== "special:notes");
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
            // (right after a shell start Hyprland.activeToplevel can still be unset: the hyprctl seed knows)
            const first = norm(list[0].address);
            const focusedFirst = first === norm(activeAddr) || (!activeAddr && first === mru[0]);
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
        const wasShown = shown;
        snap = wasShown;
        close();
        if (!t) return;
        touch(norm(t.address));
        // quick tap: the surface never took the keyboard, focus right away (as fast as Super+N).
        // Shown: the surface unmaps at once (no fade) and the focus goes one frame later, after it
        // has let go of the keyboard; focusing while the exclusive layer still held it made
        // Hyprland hand focus back to the old window when the layer unmapped
        if (!wasShown) { Hypr.focusWindow(t.address); return; }
        pendingFocus = t.address;
        focusTimer.restart();
    }
    property string pendingFocus: ""
    property bool snap: false            // commit: hide without the fade
    Timer { id: focusTimer; interval: 16; onTriggered: { Hypr.focusWindow(root.pendingFocus); root.pendingFocus = ""; root.snap = false; } }
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
            console.info("nox switcher:", cmd, "open=" + root.open, "sel=" + root.sel);
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
    // One subject on near-black: the desktop drops away (dim + vignette + film grain), the selected
    // window is a live hero preview framed by accent corner brackets, its desktop/app set as a small
    // mono label and its title in the UI font underneath with "03 / 08" at the right. Below, a
    // filmstrip of window cards (one-frame thumbnail + icon + app name); an accent hairline slides to
    // the selected card, which lifts and brightens. Only the hero is live: cards capture one frame
    // each, and a ListView only builds the cards in view, so 15 windows cost about what 8 do.
    // Enter: fade + a 0.985 -> 1 settle (durPop, <= 130 ms). Exit on commit is instant (snap).
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
            readonly property int enterMs: Math.min(Theme.durPop, 130)
            // filmstrip: cards shrink to fit up to 86% of the screen, past that the strip scrolls
            readonly property real stripMax: Math.min(sw * 0.86, 1280)
            readonly property int gap: 10
            readonly property real cardW: Math.round(Math.max(112, Math.min(152, (stripMax - gap * (n - 1)) / Math.max(1, n))))
            readonly property real thumbH: Math.round(cardW * 0.6)
            readonly property real cardH: thumbH + 28          // thumbnail + name row
            readonly property real lift: 5
            readonly property int rad: Theme.square ? 2 : 10
            function two(i) { return (i < 10 ? "0" : "") + i; }
            function isMin(t) { return (t?.workspace?.name ?? "").startsWith("special:minimized"); }
            function whereOf(t) {
                const ws = t?.workspace;
                return !ws ? "" : isMin(t) ? "Minimized" : (ws.name ?? "").startsWith("special:") ? "Scratch" : "Desktop " + ws.id;
            }

            Item {
                id: fade
                anchors.fill: parent
                opacity: root.shown ? 1 : 0
                Behavior on opacity { enabled: !root.snap; NumberAnimation { duration: root.shown ? win.enterMs : Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

                // ---- backdrop: near-black, vignette, grain ----
                Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, root.opts.dim ?? 0.74) }
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.GeometryRenderer
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: RadialGradient {
                            centerX: win.width / 2; centerY: win.height * 0.44
                            focalX: centerX; focalY: centerY
                            centerRadius: Math.hypot(win.width, win.height) * 0.56
                            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                            GradientStop { position: 0.5; color: Qt.rgba(0, 0, 0, 0.22) }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.8) }
                        }
                        startX: 0; startY: 0
                        PathLine { x: win.width; y: 0 }
                        PathLine { x: win.width; y: win.height }
                        PathLine { x: 0; y: win.height }
                        PathLine { x: 0; y: 0 }
                    }
                }
                Image {
                    anchors.fill: parent
                    source: "../../assets/grain.png"
                    fillMode: Image.Tile
                    opacity: root.opts.grain ?? 0.07
                    smooth: false
                }
                MouseArea { anchors.fill: parent; onClicked: root.close() }

                Item {
                    id: keys
                    anchors.fill: parent
                    focus: true
                    Keys.onPressed: e => {
                        const shift = e.modifiers & Qt.ShiftModifier;
                        if (e.key === Qt.Key_Escape) root.close();
                        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.commit();
                        // Tab is not handled here: the Alt+Tab bind already steps (twice = skipped windows)
                        else if (e.key === Qt.Key_Right) root.step(1);
                        else if (e.key === Qt.Key_Left) root.step(-1);
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
                    anchors.verticalCenterOffset: -win.height * 0.02
                    spacing: 0
                    scale: root.shown ? 1 : 0.985
                    Behavior on scale { NumberAnimation { duration: win.enterMs; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                    // ---- hero: live preview of the selected window ----
                    Item {
                        id: pv
                        anchors.horizontalCenter: parent.horizontalCenter
                        readonly property real maxW: Math.min(win.sw * 0.6, 920)
                        readonly property real maxH: win.height * 0.47
                        readonly property var src: shot.sourceSize
                        readonly property real k: src.width > 0 ? Math.min(maxW / src.width, maxH / src.height) : 1
                        width: src.width > 0 ? Math.round(src.width * k) : maxW
                        height: src.width > 0 ? Math.round(src.height * k) : maxH * 0.7
                        Behavior on width { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                        Behavior on height { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                        RectangularShadow {
                            anchors.fill: parent
                            radius: win.rad
                            offset.y: 24; blur: 72; spread: -4
                            color: Qt.rgba(0, 0, 0, 0.85)
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: win.rad
                            color: Theme.page
                            border.width: 1
                            border.color: Theme.white(0.14)
                        }
                        // no frame yet / minimized: the app icon stands in
                        Image {
                            anchors.centerIn: parent
                            width: 72; height: 72
                            sourceSize.width: 144; sourceSize.height: 144
                            source: root.current ? root.iconFor(root.current) : ""
                            asynchronous: true
                            smooth: true; mipmap: true
                            opacity: shot.hasContent ? 0 : 0.5
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
                        // viewfinder corners, just outside the frame
                        Brackets {
                            anchors.fill: parent
                            anchors.margins: -7
                            inset: 0
                            len: 16
                            thick: 1.5
                        }
                    }

                    Item { width: 1; height: 22 }

                    // ---- caption: DESKTOP 2 · APP / title / 03 / 08 ----
                    Item {
                        id: caption
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(pv.width, 360)
                        height: capCol.height
                        Column {
                            id: capCol
                            width: parent.width - count.width - 24
                            spacing: 7
                            Row {
                                spacing: 9
                                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: Theme.square ? 0 : 3; color: Theme.accent }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: [win.whereOf(root.current), root.appName(root.current)].filter(x => x).join(" · ")
                                    color: Theme.label2
                                    font.family: Theme.fontMono
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    font.capitalization: Font.AllUppercase
                                    font.letterSpacing: 1
                                }
                            }
                            Text {
                                width: parent.width
                                text: root.current?.title || root.appName(root.current)
                                color: Theme.label
                                font.family: Theme.fontUi
                                font.pixelSize: 22
                                font.weight: Font.Medium
                                font.letterSpacing: -0.2
                                elide: Text.ElideRight
                            }
                        }
                        Row {
                            id: count
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            spacing: 6
                            Text {
                                text: win.two(root.sel + 1)
                                color: Theme.label
                                font.family: Theme.fontMono
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            Text {
                                text: "/ " + win.two(win.n)
                                color: Theme.label3
                                font.family: Theme.fontMono
                                font.pixelSize: 13
                            }
                        }
                    }

                    Item { width: 1; height: 26 }
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.max(pv.width, strip.width); height: 1
                        color: Theme.white(0.07)
                    }
                    Item { width: 1; height: 18 }

                    // ---- filmstrip ----
                    ListView {
                        id: strip
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(win.n * (win.cardW + win.gap) - win.gap, win.stripMax)
                        height: win.cardH + win.lift + 4
                        orientation: ListView.Horizontal
                        spacing: win.gap
                        clip: true
                        interactive: contentWidth > width
                        boundsBehavior: Flickable.StopAtBounds
                        cacheBuffer: 0
                        model: win.visible ? root.list : []
                        // the selection drives the view (assigned, so a model reset can't strand it)
                        function sync() { currentIndex = root.sel; }
                        Component.onCompleted: sync()
                        onCountChanged: sync()
                        Connections { target: root; function onSelChanged() { strip.sync(); } }
                        highlightFollowsCurrentItem: true
                        highlightMoveDuration: Theme.durHover + 20
                        highlightMoveVelocity: -1
                        highlightResizeDuration: 0
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: Math.min(width * 0.15, win.cardW)
                        preferredHighlightEnd: width - Math.min(width * 0.15, win.cardW)
                        // accent hairline under the selected card
                        highlight: Item {
                            width: win.cardW; height: strip.height
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width; height: 2
                                color: Theme.accent
                            }
                        }
                        delegate: Item {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property bool on: root.sel === card.index
                            readonly property bool minimized: win.isMin(card.modelData)
                            width: win.cardW; height: strip.height
                            z: 1

                            Item {
                                id: body
                                width: parent.width; height: win.cardH
                                y: card.on ? 0 : win.lift
                                opacity: card.on ? 1 : card.minimized ? 0.32 : 0.5
                                Behavior on y { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                                Behavior on opacity { NumberAnimation { duration: Theme.durHover } }

                                Rectangle {
                                    id: frame
                                    width: parent.width; height: win.thumbH
                                    radius: win.rad
                                    color: Theme.surface
                                    border.width: 1
                                    border.color: card.on ? Theme.white(0.5) : Theme.white(0.1)
                                    Behavior on border.color { ColorAnimation { duration: Theme.durHover } }
                                    // one frame of the window, aspect-fit
                                    ScreencopyView {
                                        id: thumb
                                        readonly property var src: sourceSize
                                        readonly property real k: src.width > 0 ? Math.min((frame.width - 2) / src.width, (frame.height - 2) / src.height) : 1
                                        anchors.centerIn: parent
                                        width: src.width > 0 ? Math.round(src.width * k) : frame.width - 2
                                        height: src.width > 0 ? Math.round(src.height * k) : frame.height - 2
                                        captureSource: card.modelData?.wayland ?? null
                                        live: false
                                        opacity: hasContent ? 1 : 0
                                    }
                                    // no frame: the icon fills in
                                    Image {
                                        anchors.centerIn: parent
                                        visible: !thumb.hasContent
                                        width: Math.round(win.thumbH * 0.46); height: width
                                        sourceSize.width: width * 2; sourceSize.height: height * 2
                                        source: root.iconFor(card.modelData)
                                        asynchronous: true
                                        smooth: true; mipmap: true
                                    }
                                }
                                Row {
                                    y: win.thumbH + 8
                                    width: parent.width
                                    spacing: 7
                                    Image {
                                        id: ico
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 16; height: 16
                                        sourceSize.width: 32; sourceSize.height: 32
                                        source: root.iconFor(card.modelData)
                                        asynchronous: true
                                        smooth: true; mipmap: true
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - ico.width - parent.spacing
                                        text: root.appName(card.modelData)
                                        color: card.on ? Theme.label : Theme.label2
                                        font.family: Theme.fontMono
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        font.capitalization: Font.AllUppercase
                                        font.letterSpacing: 1
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                // only a real pointer move selects (the strip may open under a resting pointer)
                                onPositionChanged: root.sel = card.index
                                onClicked: { root.sel = card.index; root.commit(); }
                            }
                        }
                    }

                    Item { width: 1; height: 16 }

                    // ---- key hints ----
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 22
                        Repeater {
                            model: [["Tab", "next"], ["Shift", "back"], ["Q", "close"], ["Esc", "cancel"]]
                            Row {
                                id: hint
                                required property var modelData
                                spacing: 6
                                Repeater {
                                    model: 2
                                    Text {
                                        required property int index
                                        text: hint.modelData[index]
                                        color: index === 0 ? Theme.label2 : Theme.label3
                                        font.family: Theme.fontMono
                                        font.pixelSize: 9
                                        font.weight: index === 0 ? Font.Medium : Font.Normal
                                        font.capitalization: Font.AllUppercase
                                        font.letterSpacing: 0.8
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

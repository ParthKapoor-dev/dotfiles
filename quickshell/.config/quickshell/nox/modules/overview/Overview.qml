pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Mission Control: namespace nox:overview, full screen. Two views (Panels.overviewMode), switched by
// the Windows | Desktops control at the top, Space, or the other view's shortcut:
//   windows (default, Super+Tab)    every window of every desktop on this monitor spread out in
//                                   justified rows (desktop by desktop); hovering one tilts it
//                                   towards the pointer (shell.json overview.tilt)
//   desktops (Super+Shift+Tab)      the strip of desktops comes down (176px thumbnails, current one
//                                   ringed in the accent, "+" = next empty desktop) and the windows
//                                   regroup to one desktop. Hovering a thumbnail shows that desktop's
//                                   windows below (it stays shown until another one is hovered)
// Click a window = focus it (its desktop comes along); click a desktop = switch; drag a window onto
// a desktop = move it there (the strip slides down during a drag in the windows view too).
// The drop shelf opens alongside (shell.json overview.shelf, default true) and closes with it.
// Keys (stay in Mission Control unless noted):
//   Space  switch view                                     Esc  close
//   arrows / Tab / Shift+Tab  select a window (desktops view: Left / Right = previous / next desktop)
//   Home / End  first / last desktop                       1-9  go to that desktop and close
//   Shift+Left / Right  move the selected window one desktop over (and follow it)
//   Shift+1-9  send the selected window to that desktop     Delete / Ctrl+W  close the selected window
//   Enter  focus the selected window (or just close)
// Typing anything else opens the launcher with that text. `qs -c nox ipc call overview windows|desktops`.
//
// Motion: one progress value `p` (0 = desktop, 1 = Mission Control) drives the open / close; the
// current desktop's window copies grow out of their real geometry, the others fade in at their
// place. A second value `dm` (0 = windows view, 1 = desktops view) blends every copy between its two
// layouts, so switching views moves the same copies. The surface stays loaded (only unmapped while
// closed) so the wallpaper is already decoded; on open the window copies are captured first, then p
// animates. Cells move with x/y + a scale transform, nothing re-lays out per frame.
Scope {
    id: root
    readonly property var opts: Config.opt.overview ?? ({})
    readonly property bool open: Panels.overviewOpen
    property bool shown: false          // surface mapped
    property bool capture: false        // screencopies active
    property real target: 0
    property real p: 0
    Behavior on p { NumberAnimation { duration: Theme.durWorkspace; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
    // view: 0 = windows, 1 = desktops (animated while open, set straight on open)
    readonly property bool desks: Panels.overviewMode === "desktops"
    property bool dmAnim: false
    property real dm: desks ? 1 : 0
    Behavior on dm { enabled: root.dmAnim; NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
    property int hoverWs: -1            // desktops view: the thumbnail last hovered (its windows show)
    onDesksChanged: { sel = -1; hoverWs = -1; }
    onOpenChanged: {
        if (open) {
            Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces();
            hideTimer.stop(); sel = -1; hoverWs = -1;
            dmAnim = false; dm = desks ? 1 : 0; dmAnim = true;
            capture = true; shown = true;
            readyWait.elapsed = 0; readyWait.restart();
        } else {
            readyWait.stop();
            target = 0; p = 0; hoverWs = -1;
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

    // Justified rows (Exposé): the items keep their order and aspect, rows share a height, every
    // row is centred; the row count that shows the windows biggest wins. Never larger than maxScale
    // of the real window. items: [{ key, w, h }] -> { key: { x, y, s } }
    function justify(items, X, Y, W, H, gx, gy, label, maxScale) {
        const n = items.length;
        const out = {};
        if (!n || W <= 0 || H <= 0) return out;
        const asp = items.map(it => it.w / it.h);
        const total = asp.reduce((a, b) => a + b, 0);
        let best = null;
        for (let r = 1; r <= Math.min(n, 6); r++) {
            // split in order: each item goes to the row its middle falls in
            const rows = [];
            let cum = 0;
            for (let i = 0; i < n; i++) {
                const ri = Math.min(r - 1, Math.floor((cum + asp[i] / 2) / (total / r)));
                cum += asp[i];
                (rows[ri] = rows[ri] ?? []).push(i);
            }
            const rs = rows.filter(x => x && x.length);
            // height that fills the width, capped by maxScale of the row's tallest window
            let hs = rs.map(row => Math.min((W - gx * (row.length - 1)) / row.reduce((a, i) => a + asp[i], 0),
                                            Math.max(...row.map(i => items[i].h)) * maxScale));
            const room = H - gy * (rs.length - 1) - label * rs.length;
            const sum = hs.reduce((a, b) => a + b, 0);
            if (room <= 0) continue;
            if (sum > room) hs = hs.map(h => h * room / sum);
            // shown area, minus a little per row so equal sizes prefer fewer rows
            let area = 0;
            rs.forEach((row, k) => { for (const i of row) area += hs[k] * hs[k] * asp[i]; });
            area *= 1 - 0.01 * rs.length;
            if (!best || area > best.area) best = { area, rs, hs };
        }
        if (!best) return out;
        const used = best.hs.reduce((a, b) => a + b, 0) + gy * (best.rs.length - 1) + label * best.rs.length;
        let y = Y + (H - used) / 2;
        best.rs.forEach((row, k) => {
            const h = best.hs[k];
            const rw = row.reduce((a, i) => a + asp[i] * h, 0) + gx * (row.length - 1);
            let x = X + (W - rw) / 2;
            for (const i of row) {
                const it = items[i];
                // a window narrower than its row height allows sits centred in its slot
                const s = Math.min(h / it.h, maxScale);
                out[it.key] = { x: x + (asp[i] * h - it.w * s) / 2, y: y + (h - it.h * s) / 2, s };
                x += asp[i] * h + gx;
            }
            y += h + gy + label;
        });
        return out;
    }

    // loaded once and kept (unmapped while closed): wallpaper decoded, no black first frame
    LazyLoader {
        active: true
        PanelWindow {
            id: win
            visible: root.shown
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            readonly property var mon: Hyprland.monitorFor(win.screen)
            readonly property int curWs: mon?.activeWorkspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1
            // desktops view: the hovered thumbnail's desktop, else the current one
            readonly property int shownWs: root.hoverWs > 0 && root.hoverWs <= wsCount ? root.hoverWs : curWs
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
            // the windows the keys walk through: all of them, or the shown desktop's
            readonly property var selList: area.list.filter(t => !root.desks || t.workspace?.id === shownWs)
            // thumbnail width: 176 (mock) unless that many desktops + "+" would not fit the screen
            readonly property real thumbW: Math.max(72, Math.min(176, (sw - 80 - 44 - wsCount * 22) / Math.max(1, wsCount)))
            function close() { Panels.overviewOpen = false; }
            function go(ws) { Hypr.workspace(ws); close(); }
            // switch desktop behind Mission Control and stay open (arrow keys)
            function browse(ws) {
                ws = Math.max(1, Math.min(wsCount, ws));
                root.hoverWs = -1;
                if (ws === curWs) return;
                root.sel = -1;
                Hypr.workspace(ws);
                Qt.callLater(Hyprland.refreshToplevels);
            }
            // move a window to desktop ws; follow = switch there too and keep it selected
            property string reselect: ""
            function send(t, ws, follow) {
                Hypr.moveToWorkspace(t.address, ws);
                if (follow) { reselect = t.address; root.hoverWs = -1; Hypr.workspace(ws); }
                else root.sel = -1;
                Qt.callLater(Hyprland.refreshToplevels);
            }
            Connections {
                target: Panels
                function onOverviewStep(delta) { if (root.open) win.browse(win.curWs + delta); }
            }
            onSelListChanged: {
                if (reselect === "") { if (root.sel >= selList.length) root.sel = selList.length - 1; return; }
                const i = selList.findIndex(t => t.address === reselect);
                if (i >= 0) { root.sel = i; reselect = ""; }
            }
            function focus(t) { Hypr.focusWindow(t.address); close(); }
            // arrow keys between window copies: the nearest one whose centre lies that way
            function step(dx, dy) {
                const n = selList.length;
                if (!n) return;
                if (root.sel < 0) { root.sel = 0; return; }
                const c = cells.cellFor(selList[root.sel]?.address);
                if (!c) { root.sel = 0; return; }
                let best = -1, bestD = 1e12;
                for (let i = 0; i < n; i++) {
                    const o = cells.cellFor(selList[i].address);
                    if (!o || i === root.sel) continue;
                    const vx = o.cx - c.cx, vy = o.cy - c.cy;
                    const along = vx * dx + vy * dy;
                    if (along <= 4) continue;
                    const d = along + Math.abs(vx * dy - vy * dx) * 2.5;
                    if (d < bestD) { bestD = d; best = i; }
                }
                if (best >= 0) root.sel = best;
            }

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
                    const n = win.selList.length;
                    const shift = e.modifiers & Qt.ShiftModifier, ctrl = e.modifiers & Qt.ControlModifier;
                    const picked = root.sel >= 0 ? win.selList[root.sel] ?? null : null;
                    // Shift+digit arrives as its symbol (US layout); the native key code is layout-free
                    const shiftDigit = shift ? "!@#$%^&*(".indexOf(e.text) + 1 : 0;
                    const horiz = e.key === Qt.Key_Left || e.key === Qt.Key_Right;
                    if (e.key === Qt.Key_Escape) win.close();
                    else if (e.key === Qt.Key_Space && !(e.modifiers & ~Qt.KeypadModifier)) Panels.overviewMode = root.desks ? "windows" : "desktops";
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { if (picked) win.focus(picked); else win.close(); }
                    else if (shiftDigit > 0) { if (picked) win.send(picked, shiftDigit, false); }
                    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_9 && !ctrl && !shift) win.go(e.key - Qt.Key_0);
                    else if (horiz && shift) {
                        const ws = picked?.workspace?.id ?? win.curWs;
                        const to = ws + (e.key === Qt.Key_Right ? 1 : -1);
                        if (picked && to >= 1) win.send(picked, to, true);
                    }
                    else if (horiz && (root.desks || ctrl)) win.browse(win.shownWs + (e.key === Qt.Key_Right ? 1 : -1));
                    else if (horiz) win.step(e.key === Qt.Key_Right ? 1 : -1, 0);
                    else if (e.key === Qt.Key_Home) win.browse(1);
                    else if (e.key === Qt.Key_End) win.browse(win.wsCount);
                    else if (e.key === Qt.Key_Down) { if (root.desks) { if (n) root.sel = (root.sel + 1) % n; } else win.step(0, 1); }
                    else if (e.key === Qt.Key_Up) { if (root.desks) { if (n) root.sel = (root.sel - 1 + n) % n; } else win.step(0, -1); }
                    else if (e.key === Qt.Key_Tab) { if (n) root.sel = (root.sel + 1) % n; }
                    else if (e.key === Qt.Key_Backtab) { if (n) root.sel = (root.sel - 1 + n) % n; }
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
                        ? (root.desks ? "SPACE WINDOWS   ←→ DESKTOPS   ↑↓ WINDOWS   ⇧←→ MOVE WINDOW   ⇧1-9 SEND   DEL CLOSE   ↵ OPEN   ESC"
                                      : "SPACE DESKTOPS   ARROWS SELECT   ⇧←→ MOVE WINDOW   ⇧1-9 SEND   DEL CLOSE   ↵ OPEN   ESC")
                        : (root.desks ? "Space Windows    ←→ Desktops    ↑↓ Windows    ⇧←→ Move window    ⇧1–9 Send    Del Close    ↵ Open    Esc"
                                      : "Space Desktops    Arrows Select    ⇧←→ Move window    ⇧1–9 Send    Del Close    ↵ Open    Esc")
                    color: Theme.label
                    font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
                    font.pixelSize: Theme.labelsMono ? 10 : 11.5
                    font.letterSpacing: Theme.labelsMono ? 1.6 : 0.2
                }

                // ---- view switch: Windows | Desktops (top centre) ----
                Rectangle {
                    id: modeSwitch
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 14
                    z: 3
                    width: modeRow.implicitWidth + 6; height: 30
                    radius: Theme.square ? 4 : 15
                    color: Qt.rgba(0, 0, 0, 0.4)
                    border.width: 1; border.color: Theme.white(0.1)
                    opacity: root.p
                    transform: Translate { y: root.lerp(-50, 0, root.p) }
                    // the selected segment's fill slides between the two
                    Rectangle {
                        y: 3; height: parent.height - 6
                        x: 3 + root.dm * (segWin.width)
                        width: root.lerp(segWin.width, segDesk.width, root.dm)
                        radius: Theme.square ? 3 : 12
                        color: Theme.white(0.16)
                    }
                    Row {
                        id: modeRow
                        x: 3; height: parent.height
                        Repeater {
                            model: [["windows", "Windows", "grid"], ["desktops", "Desktops", "desktop"]]
                            Item {
                                id: seg
                                required property var modelData
                                required property int index
                                readonly property bool on: Panels.overviewMode === modelData[0]
                                width: segRow.implicitWidth + 26; height: parent.height
                                Component.onCompleted: if (index === 0) segWin.target = seg; else segDesk.target = seg
                                Row {
                                    id: segRow
                                    anchors.centerIn: parent
                                    spacing: 7
                                    Glyph { anchors.verticalCenter: parent.verticalCenter; name: seg.modelData[2]; size: 13; color: seg.on ? Theme.label : Theme.label2 }
                                    GText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: seg.modelData[1]
                                        font.pixelSize: 12
                                        font.weight: seg.on ? Font.DemiBold : Font.Normal
                                        color: seg.on ? Theme.label : segMouse.containsMouse ? Theme.label : Theme.label2
                                    }
                                }
                                MouseArea { id: segMouse; anchors.fill: parent; hoverEnabled: true; onClicked: Panels.overviewMode = seg.modelData[0] }
                            }
                        }
                    }
                    QtObject { id: segWin; property Item target: null; readonly property real width: target?.width ?? 0 }
                    QtObject { id: segDesk; property Item target: null; readonly property real width: target?.width ?? 0 }
                    MouseArea { anchors.fill: parent; z: -1; enabled: root.open }   // keep clicks off the backdrop
                }

                // ---- desktop strip (mock #wsstrip: 156px, gradient, 176x99 thumbs, 22px gap) ----
                // shown in the desktops view, and in the windows view while a window is dragged
                Rectangle {
                    id: stripBox
                    property real k: Math.max(root.dm, dragShow)
                    property real dragShow: dragProxy.active ? 1 : 0
                    Behavior on dragShow { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                    y: 50
                    width: parent.width; height: 156
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.35) }
                        GradientStop { position: 1; color: "transparent" }
                    }
                    visible: k > 0.01
                    opacity: Math.min(1, root.p * k * 1.6)
                    transform: Translate { y: root.lerp(-216, 0, root.p * stripBox.k) }
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
                                readonly property bool shownHere: root.desks && ws === win.shownWs && !cur
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
                                        y: thMouse.containsMouse || th.shownHere ? -2 : 0
                                        Behavior on y { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                                    }
                                    Rectangle {
                                        anchors.fill: parent; anchors.margins: th.cur || th.drop || th.shownHere ? -2 : -1
                                        radius: (Theme.square ? 4 : 8) + 2
                                        color: th.cur || th.drop ? Theme.accent : th.shownHere ? Theme.white(0.6) : thMouse.containsMouse ? Theme.white(0.3) : Theme.white(0.16)
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
                                                    captureSource: root.capture && stripBox.visible && mw.modelData.wayland ? mw.modelData.wayland : null
                                                    live: false
                                                }
                                            }
                                        }
                                    }
                                    // hover = show this desktop's windows below (desktops view)
                                    MouseArea {
                                        id: thMouse; anchors.fill: parent; hoverEnabled: true
                                        onContainsMouseChanged: if (containsMouse && root.desks && !dragProxy.active) root.hoverWs = th.ws
                                        onClicked: win.go(th.ws)
                                    }
                                }
                                GText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "Desktop " + th.ws
                                    font.pixelSize: 12
                                    font.weight: th.cur || th.shownHere ? Font.DemiBold : Font.Normal
                                    color: th.cur || th.shownHere ? Theme.label : Theme.label2
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

                // ---- the window copies (both views) ----
                Item {
                    id: area
                    anchors.fill: parent
                    // room for the copies: under the view switch (windows) or the strip (desktops),
                    // above the dock, clear of the shelf's edge while it is open alongside
                    readonly property bool shelfOn: root.opts.shelf ?? true
                    readonly property real shelfW: shelfOn ? 250 : 0
                    readonly property bool shelfLeft: (Config.opt.shelf?.side ?? "right") === "left"
                    readonly property real ax: 64 + (shelfLeft ? shelfW : 0)
                    readonly property real aw: win.sw - 128 - shelfW
                    readonly property real ab: win.sh - (Panels.dockVisible ? Theme.dockSize + 44 : 44)
                    readonly property real ayWin: 66
                    readonly property real ayDesk: 216
                    readonly property real label: 34
                    readonly property real maxScale: root.opts.maxScale ?? 0.72
                    // reading order of the real windows (rows of 260px, then x), desktop by desktop
                    readonly property var sorted: {
                        const c = t => { const o = t.lastIpcObject ?? {}; return [(o.at?.[0] ?? 0) + (o.size?.[0] ?? 0) / 2, (o.at?.[1] ?? 0) + (o.size?.[1] ?? 0) / 2]; };
                        return win.wins.slice().sort((x, y) => {
                            const wx = x.workspace?.id ?? 0, wy = y.workspace?.id ?? 0;
                            if (wx !== wy) return wx - wy;
                            const a = c(x), b = c(y);
                            return (Math.round(a[1] / 260) - Math.round(b[1] / 260)) * 10000 + (a[0] - b[0]);
                        });
                    }
                    // the Repeater only resets when the set of windows changes (a refresh of their
                    // geometry must not recreate the delegates and restart their captures)
                    property var list: []
                    property string listKey: ""
                    onSortedChanged: { const k = sorted.map(t => t.address).join(","); if (k !== listKey) { listKey = k; list = sorted; } }
                    function item(t) { const o = t.lastIpcObject ?? {}; return { key: t.address, w: Math.max(40, o.size?.[0] ?? 800), h: Math.max(30, o.size?.[1] ?? 500) }; }
                    // layouts: every window (windows view) / the shown desktop's (desktops view)
                    readonly property var all: root.justify(list.map(item), ax, ayWin, aw, ab - ayWin, 36, 18, label, maxScale)
                    readonly property var desk: root.justify(list.filter(t => t.workspace?.id === win.shownWs).map(item), ax, ayDesk, aw, ab - ayDesk, 44, 18, label, maxScale)
                    readonly property int deskN: list.filter(t => t.workspace?.id === win.shownWs).length

                    GText {
                        visible: opacity > 0
                        opacity: root.p * (root.desks ? (area.deskN === 0 ? 1 : 0) : (area.list.length === 0 ? 1 : 0))
                        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: root.desks ? (area.ayDesk + area.ab) / 2 : (area.ayWin + area.ab) / 2
                        text: root.desks ? "No windows on Desktop " + win.shownWs : "No open windows"
                        secondary: true
                        font.pixelSize: 15
                    }

                    Repeater {
                        id: cells
                        model: area.list
                        function cellFor(address) {
                            for (let i = 0; i < count; i++) { const c = itemAt(i); if (c && c.modelData.address === address) return c; }
                            return null;
                        }
                        Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property var o: modelData.lastIpcObject ?? ({})
                            readonly property int ws: modelData.workspace?.id ?? 0
                            // real geometry (screen-local)
                            readonly property real fx: (o.at?.[0] ?? 0) - win.sx
                            readonly property real fy: (o.at?.[1] ?? 0) - win.sy
                            readonly property real ww: Math.max(40, o.size?.[0] ?? 800)
                            readonly property real wh: Math.max(30, o.size?.[1] ?? 500)
                            // the two layouts: A = windows view, D = desktops view (a window of a
                            // desktop that isn't shown stays at its A spot, faded out)
                            readonly property bool onShown: ws === win.shownWs
                            readonly property var la: area.all[modelData.address] ?? ({ x: fx, y: fy, s: 1 })
                            readonly property var ld: onShown ? (area.desk[modelData.address] ?? la) : la
                            readonly property real tx: root.lerp(la.x, ld.x, root.dm)
                            readonly property real ty: root.lerp(la.y, ld.y, root.dm)
                            readonly property real ts: root.lerp(la.s, ld.s, root.dm)
                            // the current desktop's copies grow out of the real windows; the others
                            // fade in at their spot, from a little smaller
                            readonly property bool home: ws === win.curWs
                            readonly property real s: home ? root.lerp(1, ts, root.p) : ts * root.lerp(0.9, 1, root.p)
                            property real shownK: onShown ? 1 : 0
                            Behavior on shownK { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                            readonly property real fade: root.lerp(1, shownK, root.dm)
                            readonly property bool live: fade > 0.02 && (home || root.p > 0)
                            readonly property int selIndex: win.selList.indexOf(modelData)
                            readonly property bool hot: (cellMouse.containsMouse && fade > 0.5) || (root.sel >= 0 && root.sel === selIndex)
                            readonly property bool ready: shotView.hasContent
                            // centre on screen (keyboard navigation)
                            readonly property real cx: tx + ww * ts / 2
                            readonly property real cy: ty + wh * ts / 2
                            x: home ? root.lerp(fx, tx, root.p) : tx + ww * (ts - s) / 2
                            y: home ? root.lerp(fy, ty, root.p) : ty + wh * (ts - s) / 2
                            width: ww * s; height: wh * s
                            z: hot ? 2 : 1
                            opacity: (home ? 1 : root.p) * fade
                            visible: opacity > 0.01 && !(dragProxy.active && dragProxy.target === cell)

                            // hover: tilt towards the pointer (3D, Qt's perspective rotation) and lift
                            readonly property bool tilting: (root.opts.tilt ?? true) && cellMouse.containsMouse && !dragProxy.active && root.p > 0.98
                            property real tiltX: tilting ? -(cellMouse.mouseY / Math.max(1, height) - 0.5) * 12 : 0
                            property real tiltY: tilting ? (cellMouse.mouseX / Math.max(1, width) - 0.5) * 16 : 0
                            property real lift: hot && root.p > 0.98 ? 1.04 : 1
                            Behavior on tiltX { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on tiltY { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                            Behavior on lift { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                            transform: [
                                Rotation { origin.x: cell.width / 2; origin.y: cell.height / 2; axis { x: 0; y: 1; z: 0 } angle: cell.tiltY },
                                Rotation { origin.x: cell.width / 2; origin.y: cell.height / 2; axis { x: 1; y: 0; z: 0 } angle: cell.tiltX },
                                Scale { origin.x: cell.width / 2; origin.y: cell.height / 2; xScale: cell.lift; yScale: cell.lift }
                            ]

                            // the window copy at full size, scaled (transform only)
                            Item {
                                id: body
                                width: cell.ww; height: cell.wh
                                transformOrigin: Item.TopLeft
                                scale: cell.s
                                RectangularShadow {
                                    anchors.fill: parent; radius: Theme.radiusWindow
                                    offset.y: cell.hot ? 22 : 14; blur: cell.hot ? 56 : 40; spread: -8
                                    color: Qt.rgba(0, 0, 0, cell.hot ? 0.6 : 0.5)
                                    opacity: root.p
                                }
                                Rectangle { anchors.fill: parent; color: Theme.bg; radius: Theme.radiusWindow; opacity: cell.ready ? 0 : root.p }
                                ScreencopyView {
                                    id: shotView
                                    anchors.fill: parent
                                    captureSource: root.capture && cell.live && cell.modelData.wayland ? cell.modelData.wayland : null
                                    // frozen while closing: the refocused window repaints then, and copying
                                    // those frames would compete with the transition. Other desktops'
                                    // windows aren't drawn, so their copy is one frame
                                    live: (root.opts.live ?? true) && root.open && cell.home
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
                            // app label (mock .ov-label); the windows view adds the desktop number
                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom; anchors.topMargin: 9
                                width: lblRow.implicitWidth + 20; height: lbl.implicitHeight + 6
                                radius: Theme.square ? 3 : 8
                                color: Qt.rgba(0, 0, 0, 0.45)
                                opacity: Math.max(0, root.p * 2 - 1)
                                Row {
                                    id: lblRow
                                    anchors.centerIn: parent
                                    spacing: 7
                                    GText {
                                        id: lbl
                                        width: Math.min(implicitWidth, cell.ww * cell.ts + 20)
                                        text: Apps.entryFor(cell.o.class ?? cell.modelData.wayland?.appId ?? "")?.name || cell.o.class || cell.modelData.title
                                        color: "white"
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    GText {
                                        visible: opacity > 0
                                        opacity: 1 - root.dm
                                        text: String(cell.ws)
                                        color: cell.home ? Theme.accent : Theme.label2
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                            MouseArea {
                                id: cellMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.open && cell.fade > 0.5
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
                        // only the current desktop's copies animate from the real windows: wait for those
                        root.readyCheck = () => {
                            if (backdrop.status === Image.Loading) return false;
                            for (let i = 0; i < cells.count; i++) { const c = cells.itemAt(i); if (c && c.home && c.fade > 0.02 && !c.ready) return false; }
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
                    z: 5
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

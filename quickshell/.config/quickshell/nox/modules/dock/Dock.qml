pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Dock (mock #dock): centred glass shelf (size + 12 tall, radius size*.3+4, 6px above the bottom),
// cosine magnification, running indicators, tooltip, context menu, Downloads/Trash stacks.
// dock.autohide (default true): no reserved space; a 3px hot strip under the shelf reveals it after
// 150 ms, it hides 400 ms after the pointer leaves (not while its menu is open); slides with the
// sheet curve. `qs -c nox ipc call dock toggle|open|close` reveals/hides it.
// Without autohide it reserves its height (dock.reserveSpace) like the mock's tiling area.
// Window previews: resting on a running app's tile for dock.previewDelay ms (450) opens a glass
// card above it with a live thumbnail per window (title under it): click = focus that window,
// middle click / x = close it. Moving to another running tile switches the card at once; it
// closes 250 ms after the pointer has left both the tile and the card. dock.previews: false = off.
// The layer surface is full width but its input mask is only the shelf (or the hot strip).
Variants {
    model: Config.screensFor(Config.opt.dock?.screens)

    PanelWindow {
        id: win
        required property ShellScreen modelData
        screen: modelData

        readonly property real size: Theme.dockSize
        readonly property real peak: (Config.opt.dock?.magnify ?? true) ? Theme.dockMagnify : 1
        readonly property real shelfH: size + 12
        readonly property real bottomGap: 6
        readonly property real tipH: 40
        readonly property real range: size * 2.8
        readonly property var items: Apps.items
        readonly property bool autohide: Config.opt.dock?.autohide ?? false
        readonly property bool menuOpen: Panels.popup === menu.popupId
        readonly property bool hovering: hover.hovered
        // shown = on screen; with autohide only while revealed
        // autohide stays revealed on an empty desktop (no windows on this screen's workspace;
        // minimized windows live in special:minimized and don't count)
        readonly property bool shown: Panels.dockVisible && (!autohide || revealed || menuOpen || preview.hovered || (emptyDesktop && !fullscreen))
        property bool revealed: false
        // this screen's workspace, not the focused one: a fullscreen window on another monitor
        // must not disable this dock's hot strip
        readonly property var monWs: Hyprland.monitorFor(win.screen)?.activeWorkspace ?? null
        readonly property bool fullscreen: monWs?.hasFullscreen ?? false
        readonly property bool wsEmpty: !!monWs && monWs.toplevels.values.length === 0
        // settled a beat (a window closing while the next one maps, workspace switch events
        // arriving in pieces) so the dock doesn't bob
        property bool emptyDesktop: false
        onWsEmptyChanged: emptyTimer.restart()
        Component.onCompleted: emptyDesktop = wsEmpty
        Timer { id: emptyTimer; interval: 120; onTriggered: win.emptyDesktop = win.wsEmpty }
        // a window appeared while the pointer is on the dock (launched from it): keep it up until
        // the pointer leaves, like a normal reveal
        onEmptyDesktopChanged: if (!emptyDesktop && autohide && hovering) revealed = true

        // reveal / conceal timing (autohide)
        Timer { id: revealTimer; interval: Config.opt.dock?.revealDelay ?? 150; onTriggered: win.revealed = true }
        Timer { id: concealTimer; interval: Config.opt.dock?.hideDelay ?? 400; onTriggered: if (!win.hovering && !win.menuOpen && !preview.hovered) win.revealed = false }
        onHoveringChanged: { if (hovering) concealTimer.stop(); else if (revealed) concealTimer.restart(); }
        onMenuOpenChanged: if (!menuOpen && !hovering && revealed) concealTimer.restart()
        Connections {
            target: Panels
            // IPC / keybind reveal while autohiding: stay up until the pointer has been away 1.5 s
            function onDockRevealedChanged() {
                if (!win.autohide) return;
                win.revealed = Panels.dockRevealed;
                if (Panels.dockRevealed) { concealTimer.interval = 1500; concealTimer.restart(); }
            }
        }
        onRevealedChanged: { if (!revealed) { concealTimer.interval = Config.opt.dock?.hideDelay ?? 400; Panels.dockRevealed = false; } }

        // base (unmagnified) geometry, used for magnification so layout changes don't feed back
        function tileW(it) { return it.sep ? 13 : size + 4; }
        readonly property real baseW: 12 + items.reduce((a, it) => a + tileW(it), 0)
        readonly property real baseX: (width - baseW) / 2
        function baseCenter(i) {
            let x = baseX + 6;
            for (let k = 0; k < i; k++) x += tileW(items[k]);
            return x + 2 + size / 2;
        }

        WlrLayershell.namespace: "nox:dock"
        WlrLayershell.layer: WlrLayer.Top
        anchors { bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: !autohide && (Config.opt.dock?.reserveSpace ?? true) && Panels.dockVisible ? shelfH + bottomGap : 0
        implicitHeight: size * Math.max(peak, 1) + 6 + bottomGap + tipH + 12
        color: "transparent"

        mask: Region { item: hitArea }
        Item {
            id: hitArea
            x: shelf.x; width: shelf.width
            readonly property bool hot: win.autohide && !win.shown && Panels.dockVisible && !win.fullscreen
            y: hot ? win.height - 3 : win.hovering ? 0 : shelf.y
            height: hot ? 3 : !win.shown ? 0 : win.hovering ? win.height : shelf.height + win.bottomGap
        }
        // bottom-edge hot strip (autohide)
        MouseArea {
            visible: hitArea.hot
            x: hitArea.x; width: hitArea.width
            y: win.height - 3; height: 3
            hoverEnabled: true
            onContainsMouseChanged: containsMouse ? revealTimer.restart() : revealTimer.stop()
        }

        Item {
            id: stage
            anchors.fill: parent
            opacity: win.shown ? 1 : 0
            transform: Translate {
                y: win.shown ? 0 : win.shelfH + win.bottomGap + 12
                Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
            }
            Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
            HoverHandler { id: hover; enabled: win.shown }

            RectangularShadow {
                anchors.fill: shelf
                radius: shelf.radius
                offset.y: 10; blur: 30; spread: -4
                color: Theme.rgba("#000000", Theme.square ? 0.5 : 0.35)
            }
            Glass {
                id: shelf
                anchors.bottom: parent.bottom; anchors.bottomMargin: win.bottomGap
                anchors.horizontalCenter: parent.horizontalCenter
                height: win.shelfH
                width: tiles.width + 12
                radius: Theme.square ? 6 : win.size * 0.3 + 4
                border.width: Theme.square ? 1 : Theme.rimWidth
                border.color: Theme.square ? Theme.white(0.12) : Theme.rim
            }

            Row {
                id: tiles
                anchors.bottom: shelf.bottom
                anchors.horizontalCenter: shelf.horizontalCenter
                height: win.size * Math.max(win.peak, 1) + 12
                Repeater {
                    model: win.items
                    DockItem {
                        required property var modelData
                        required property int index
                        item: modelData
                        y: tiles.height - height
                        size: win.size
                        scale_: {
                            if (modelData.sep || !win.hovering || win.peak <= 1) return 1;
                            const d = Math.abs(hover.point.position.x - win.baseCenter(index));
                            return d < win.range ? 1 + (win.peak - 1) * Math.cos(d / win.range * Math.PI / 2) : 1;
                        }
                        onHoveredChanged: {
                            if (hovered) tip.target = this; else if (tip.target === this) tip.target = null;
                            preview.tileHovered(this, hovered);
                        }
                        onClicked: preview.hide()
                        onMenuRequested: { preview.hide(); menu.target = modelData; menu.anchorItem = this; Panels.open(menu.popupId); }
                    }
                }
            }

            // tooltip above the hovered tile (mock #docktip)
            Rectangle {
                id: tip
                property var target: null
                // the tile the tooltip belongs to, kept while it fades out (target is already null)
                property var last: null
                onTargetChanged: if (target) last = target
                readonly property bool on: target !== null && !win.menuOpen && preview.tile !== target
                opacity: on ? 1 : 0
                visible: opacity > 0.01 && last !== null
                Behavior on opacity { NumberAnimation { duration: tip.on ? Theme.durHover : Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                transform: Translate {
                    y: tip.on ? 0 : 3
                    Behavior on y { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                }
                color: Theme.square ? Theme.rgba("#0A0A0A", 0.96) : Theme.rgba("#28282A", 0.82)
                radius: Theme.square ? 3 : 8
                border.width: Theme.rimWidth; border.color: Theme.white(0.14)
                width: Math.min(tipText.implicitWidth, 320) + 22; height: 25
                x: last ? Math.max(4, Math.min(stage.width - width - 4, (last.s, tiles.x, last.mapToItem(stage, last.width / 2, 0).x - width / 2))) : 0
                y: last ? (last.s, last.mapToItem(stage, 0, 0).y - height - 11) : 0
                GText {
                    id: tipText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, 320)
                    text: tip.last?.label ?? ""
                    font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
                    font.pixelSize: Theme.square ? 11 : 13
                    font.capitalization: Theme.square ? Font.AllUppercase : Font.MixedCase
                    font.letterSpacing: Theme.square ? 0.66 : 0
                }
            }
        }

        // ---- window previews (hover a running tile) ----
        PopupWindow {
            id: preview
            readonly property bool enabled_: Config.opt.dock?.previews ?? true
            property var tile: null              // DockItem the card belongs to
            property var pending: null           // tile waiting out the hover delay
            readonly property var wins: tile?.item?.toplevels ?? []
            readonly property bool hovered: cardHover.hovered
            readonly property real thumbH: 112
            readonly property real maxThumbW: 220

            function tileHovered(t, on) {
                if (!enabled_) return;
                if (on) {
                    closeTimer.stop();
                    const live = (t.item?.toplevels.length ?? 0) > 0 && !t.item?.stack;
                    if (!live) { pending = null; openTimer.stop(); if (tile) closeTimer.restart(); return; }
                    if (tile) { show(t); return; }       // card already up: follow the pointer
                    pending = t; openTimer.restart();
                } else {
                    if (pending === t) { pending = null; openTimer.stop(); }
                    if (tile) closeTimer.restart();
                }
            }
            function show(t) {
                if (win.menuOpen || !t) return;
                tile = t;
                const p = t.mapToItem(null, t.width / 2, 0);
                cx = p.x; topY = p.y;
                visible = true;
            }
            function hide() { openTimer.stop(); closeTimer.stop(); pending = null; tile = null; visible = false; }
            property real cx: 0
            property real topY: 0
            Timer { id: openTimer; interval: Config.opt.dock?.previewDelay ?? 450; onTriggered: preview.show(preview.pending) }
            Timer { id: closeTimer; interval: 250; onTriggered: if (!preview.hovered && !(preview.tile?.hovered ?? false)) preview.hide() }
            onHoveredChanged: if (!hovered && tile) closeTimer.restart()
            // the app quit / its last window closed
            onWinsChanged: if (tile && wins.length === 0) hide()
            Connections { target: win; function onShownChanged() { if (!win.shown) preview.hide(); } function onMenuOpenChanged() { if (win.menuOpen) preview.hide(); } }

            anchor.window: win
            anchor.rect.x: Math.max(8, Math.min(win.width - implicitWidth - 8, cx - implicitWidth / 2))
            anchor.rect.y: topY - implicitHeight - 6
            visible: false
            color: "transparent"
            implicitWidth: card.width + 32
            implicitHeight: card.height + 32

            HoverHandler { id: cardHover }
            RectangularShadow {
                anchors.fill: card
                radius: card.radius
                offset.y: 10; blur: 28; spread: -4
                color: Theme.rgba("#000000", 0.4)
            }
            Glass {
                id: card
                x: 16; y: 16
                menu: true
                color: Theme.cardGlass
                radius: Theme.square ? 6 : 14
                width: thumbs.width + 16
                height: thumbs.height + 16
                Row {
                    id: thumbs
                    x: 8; y: 8
                    spacing: 8
                    Repeater {
                        model: preview.visible ? preview.wins : []
                        Item {
                            id: th
                            required property var modelData
                            readonly property real ar: shot.sourceSize.width > 0 ? shot.sourceSize.width / shot.sourceSize.height : 16 / 10
                            width: Math.max(120, Math.min(preview.maxThumbW, preview.thumbH * ar))
                            height: preview.thumbH + 26
                            readonly property bool hot: thMouse.containsMouse || xMouse.containsMouse
                            Rectangle {
                                anchors.fill: frame
                                anchors.margins: -3
                                radius: Theme.square ? 4 : 9
                                color: th.hot ? Theme.white(0.08) : "transparent"
                                border.width: th.modelData.activated ? 1.5 : 0
                                border.color: Theme.accent
                            }
                            Item {
                                id: frame
                                width: parent.width; height: preview.thumbH
                                Rectangle { anchors.fill: parent; radius: Theme.square ? 2 : 6; color: Theme.rgba("#000000", 0.35) }
                                ScreencopyView {
                                    id: shot
                                    anchors.centerIn: parent
                                    readonly property real k: sourceSize.width > 0 ? Math.min(parent.width / sourceSize.width, parent.height / sourceSize.height) : 1
                                    width: sourceSize.width > 0 ? sourceSize.width * k : parent.width
                                    height: sourceSize.width > 0 ? sourceSize.height * k : parent.height
                                    captureSource: preview.visible ? th.modelData : null
                                    live: true
                                }
                            }
                            GText {
                                y: preview.thumbH + 7
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: th.modelData.title || th.modelData.appId
                                small: true
                                color: th.hot ? Theme.label : Theme.label2
                            }
                            MouseArea {
                                id: thMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: m => { if (m.button === Qt.MiddleButton) th.modelData.close(); else { preview.hide(); th.modelData.activate(); } }
                            }
                            // close (mock .nt .x), on hover
                            Rectangle {
                                x: -6; y: -6
                                width: 20; height: 20
                                radius: Theme.square ? 4 : 10
                                color: Theme.rgba(Theme.t.color.glass, 0.95)
                                border.width: Theme.rimWidth; border.color: Theme.rim
                                opacity: th.hot ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
                                Glyph { anchors.centerIn: parent; name: "x"; size: 10; color: Theme.label }
                                MouseArea { id: xMouse; anchors.fill: parent; hoverEnabled: true; onClicked: th.modelData.close() }
                            }
                        }
                    }
                }
            }
        }

        // right-click menu (mock Dock.menu), opens upwards above the shelf, centred on the tile
        GPopup {
            id: menu
            property var target: null
            popupId: "dock:menu:" + win.screen?.name
            fromBottom: true
            bottomOffset: win.shelfH + win.bottomGap + 4
            popupWidth: 224
            align: "item"
            content: Column {
                readonly property var t: menu.target
                readonly property bool stack: !!t?.stack
                // stacks
                MenuRow { visible: parent.stack; width: parent.width; text: "Open"; onTriggered: { Panels.close(); Apps.openStack(menu.target.stack); } }
                MenuRow { visible: parent.stack && menu.target?.stack === "trash"; width: parent.width; text: "Empty Trash"; enabled: Apps.trashFull; onTriggered: { Panels.close(); Apps.emptyTrash(); } }
                // apps
                MenuRow { visible: !parent.stack && (parent.t?.toplevels.length ?? 0) > 0; width: parent.width; header: true; text: "Windows" }
                Repeater {
                    model: !parent.stack && menu.target ? menu.target.toplevels : []
                    MenuRow {
                        required property var modelData
                        width: parent.width
                        text: modelData.title || modelData.appId
                        checked: modelData.activated
                        onTriggered: { Panels.close(); modelData.activate(); }
                    }
                }
                MenuSep { visible: !parent.stack && (parent.t?.toplevels.length ?? 0) > 0; width: parent.width }
                MenuRow { visible: !parent.stack; width: parent.width; text: "New Window"; onTriggered: { Panels.close(); Apps.launch(menu.target); } }
                MenuRow {
                    visible: !parent.stack
                    width: parent.width
                    text: "Keep in Dock"
                    checked: menu.target?.pinned ?? false
                    onTriggered: { Panels.close(); Apps.togglePin(menu.target); }
                }
                MenuRow {
                    visible: !parent.stack && Config.moduleEnabled("overview") && (parent.t?.toplevels.length ?? 0) > 0
                    width: parent.width; text: "Show All Windows"
                    onTriggered: { Panels.close(); Panels.overviewOpen = true; }
                }
                MenuSep { visible: !parent.stack && (parent.t?.toplevels.length ?? 0) > 0; width: parent.width }
                MenuRow {
                    visible: !parent.stack && (parent.t?.toplevels.length ?? 0) > 0
                    width: parent.width; text: "Quit"
                    onTriggered: { Panels.close(); Apps.quit(menu.target); }
                }
            }
        }
    }
}

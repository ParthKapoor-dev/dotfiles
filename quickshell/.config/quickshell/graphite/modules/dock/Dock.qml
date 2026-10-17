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
// sheet curve. `qs -c graphite ipc call dock toggle|open|close` reveals/hides it.
// Without autohide it reserves its height (dock.reserveSpace) like the mock's tiling area.
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
        readonly property bool shown: Panels.dockVisible && (!autohide || revealed || menuOpen)
        property bool revealed: false
        // this screen's workspace, not the focused one: a fullscreen window on another monitor
        // must not disable this dock's hot strip
        readonly property bool fullscreen: Hyprland.monitorFor(win.screen)?.activeWorkspace?.hasFullscreen ?? false

        // reveal / conceal timing (autohide)
        Timer { id: revealTimer; interval: Config.opt.dock?.revealDelay ?? 150; onTriggered: win.revealed = true }
        Timer { id: concealTimer; interval: Config.opt.dock?.hideDelay ?? 400; onTriggered: if (!win.hovering && !win.menuOpen) win.revealed = false }
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

        WlrLayershell.namespace: "graphite:dock"
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
                        onHoveredChanged: if (hovered) tip.target = this; else if (tip.target === this) tip.target = null
                        onMenuRequested: { menu.target = modelData; menu.anchorItem = this; Panels.open(menu.popupId); }
                    }
                }
            }

            // tooltip above the hovered tile (mock #docktip)
            Rectangle {
                id: tip
                property var target: null
                visible: target !== null && !win.menuOpen
                color: Theme.square ? Theme.rgba("#0A0A0A", 0.96) : Theme.rgba("#28282A", 0.82)
                radius: Theme.square ? 3 : 8
                border.width: Theme.rimWidth; border.color: Theme.white(0.14)
                width: Math.min(tipText.implicitWidth, 320) + 22; height: 25
                x: target ? Math.max(4, Math.min(stage.width - width - 4, (target.s, tiles.x, target.mapToItem(stage, target.width / 2, 0).x - width / 2))) : 0
                y: target ? (target.s, target.mapToItem(stage, 0, 0).y - height - 11) : 0
                GText {
                    id: tipText
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, 320)
                    text: tip.target?.label ?? ""
                    font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
                    font.pixelSize: Theme.square ? 11 : 13
                    font.capitalization: Theme.square ? Font.AllUppercase : Font.MixedCase
                    font.letterSpacing: Theme.square ? 0.66 : 0
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

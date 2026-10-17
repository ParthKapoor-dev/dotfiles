pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.services

// Dock: centred glass shelf, cosine magnification, running dots, tooltip, context menu.
// Reserves its height (mock: windows tile above the dock) unless dock.reserveSpace is false.
// The layer surface is full-width but its input region (mask) is only the shelf, widened to the
// magnification band while hovered, so it never steals clicks from windows.
Variants {
    model: Config.screensFor(Config.opt.dock?.screens)

    PanelWindow {
        id: win
        required property ShellScreen modelData
        screen: modelData

        readonly property real size: Theme.dockSize
        readonly property real peak: (Config.opt.dock?.magnify ?? true) ? Theme.dockMagnify : 1
        readonly property real shelfH: size + 12          // mock: height calc(var(--dock) + 12px)
        readonly property real bottomGap: 6               // mock: bottom 6px
        readonly property real tipH: 34
        readonly property real range: size * 2.8          // mock: cosine falloff range
        readonly property var items: Apps.items
        readonly property bool shown: Panels.dockVisible
        readonly property bool hovering: hover.hovered && shown

        // base (unmagnified) geometry, used for magnification so layout changes don't feed back
        readonly property real baseW: 12 + items.reduce((a, it) => a + (it.sep ? 13 : size + 4), 0)
        readonly property real baseX: (width - baseW) / 2
        function baseCenter(i) {
            let x = baseX + 6;
            for (let k = 0; k < i; k++) x += items[k].sep ? 13 : size + 4;
            return x + 2 + size / 2;
        }

        WlrLayershell.namespace: "graphite:dock"
        WlrLayershell.layer: WlrLayer.Top
        anchors { bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: (Config.opt.dock?.reserveSpace ?? true) && shown ? shelfH + bottomGap : 0
        implicitHeight: size * Math.max(peak, 1) + 6 + bottomGap + tipH
        color: "transparent"

        mask: Region { item: hitArea }
        Item {
            id: hitArea
            x: shelf.x; width: shelf.width
            y: win.hovering ? 0 : shelf.y
            height: !win.shown ? 0 : win.hovering ? win.height : shelf.height + win.bottomGap
        }

        Item {
            id: stage
            anchors.fill: parent
            opacity: win.shown ? 1 : 0
            transform: Translate { y: win.shown ? 0 : win.shelfH + win.bottomGap + 10 }
            Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
            HoverHandler { id: hover }

            RectangularShadow {
                anchors.fill: shelf
                radius: shelf.radius
                offset.y: 10; blur: 30; spread: -4
                color: Theme.rgba("#000000", 0.35)
            }
            Glass {
                id: shelf
                brackets: false
                anchors.bottom: parent.bottom; anchors.bottomMargin: win.bottomGap
                anchors.horizontalCenter: parent.horizontalCenter
                height: win.shelfH
                width: tiles.width + 12
                radius: win.size * 0.3 + 4                   // mock: calc(var(--dock) * .3 + 4px)
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
                visible: target !== null && Panels.popup !== menu.popupId
                color: Theme.rgba("#28282A", 0.82)
                radius: 8
                border.width: Theme.rimWidth; border.color: Theme.rim
                width: tipText.implicitWidth + 22; height: 24
                x: target ? (target.s, tiles.x, target.mapToItem(stage, target.width / 2, 0).x - width / 2) : 0
                y: target ? (target.s, target.mapToItem(stage, 0, 6).y - height - 8) : 0
                GText { id: tipText; anchors.centerIn: parent; text: tip.target?.label ?? "" }
            }
        }

        // right-click menu, opens upwards from above the shelf
        GPopup {
            id: menu
            property var target: null
            popupId: "dock:menu:" + win.screen?.name
            fromBottom: true
            bottomOffset: win.shelfH + win.bottomGap + 4
            popupWidth: 200
            content: Column {
                Repeater {
                    model: menu.target ? menu.target.toplevels : []
                    MenuRow {
                        required property var modelData
                        width: parent.width
                        text: modelData.title || modelData.appId
                        checked: modelData.activated
                        onTriggered: { Panels.close(); modelData.activate(); }
                    }
                }
                MenuRow { visible: (menu.target?.toplevels.length ?? 0) > 0; width: parent.width; separator: true }
                MenuRow { width: parent.width; text: "New Window"; onTriggered: { Panels.close(); Apps.launch(menu.target); } }
                MenuRow {
                    width: parent.width
                    text: "Keep in Dock"
                    checked: menu.target?.pinned ?? false
                    onTriggered: { Panels.close(); Apps.togglePin(menu.target); }
                }
                MenuRow { visible: (menu.target?.toplevels.length ?? 0) > 0; width: parent.width; separator: true }
                MenuRow {
                    visible: (menu.target?.toplevels.length ?? 0) > 0
                    width: parent.width; text: "Quit"
                    onTriggered: { Panels.close(); Apps.quit(menu.target); }
                }
            }
        }
    }
}

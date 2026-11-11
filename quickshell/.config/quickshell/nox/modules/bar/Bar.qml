pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// Menu bar (mock #menubar): flush top, full width, glass (namespace nox:bar), reserves its
// height, 8px side padding, 1px hairline at the bottom.
Variants {
    model: Config.screensFor(Config.opt.bar?.screens)

    PanelWindow {
        id: bar
        required property ShellScreen modelData
        screen: modelData
        WlrLayershell.namespace: "nox:bar"
        WlrLayershell.layer: WlrLayer.Top
        anchors { top: true; left: true; right: true }
        implicitHeight: Theme.barHeight
        color: "transparent"

        Component.onDestruction: Panels.unregisterBar(bar)

        // Caffeine (control center tile) needs a mapped surface; the bar is always mapped.
        IdleInhibitor { window: bar; enabled: Panels.caffeine }

        Rectangle {
            anchors.fill: parent
            color: Theme.menubarGlass
            // mock: inset 0 -1px 0 rgba(255,255,255,.07) (.1 in Telemetry)
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 1
                color: Theme.sep
            }
            // click on empty bar closes popups
            MouseArea { anchors.fill: parent; onClicked: Panels.close() }
        }

        WidgetRow {
            id: leftRow
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            ids: Config.opt.bar?.left ?? []
        }
        // centre widgets: on the screen's centre when they fit, else slid into the free gap
        // between the left and right groups (the right side is usually the longer one)
        WidgetRow {
            id: centerRow
            readonly property real lo: leftRow.x + leftRow.width + 12
            readonly property real hi: rightRow.x - 12
            x: Math.max(lo, Math.min(hi - width, (parent.width - width) / 2))
            anchors.verticalCenter: parent.verticalCenter
            ids: Config.opt.bar?.center ?? []
        }
        WidgetRow {
            id: rightRow
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            ids: Config.opt.bar?.right ?? []
        }
        // free width between the left and right groups (the agent notch stays inside it)
        readonly property real centerRoom: Math.max(0, rightRow.x - leftRow.x - leftRow.width - 24)
        onCenterRoomChanged: Panels.barCenterRoom = centerRoom
        Component.onCompleted: { Panels.registerBar(bar); Panels.barCenterRoom = centerRoom; }
    }
}

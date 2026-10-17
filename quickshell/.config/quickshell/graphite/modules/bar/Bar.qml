pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// Menu bar: flush top, full width, glass (namespace graphite:bar), reserves its height.
Variants {
    model: Config.screensFor(Config.opt.bar?.screens)

    PanelWindow {
        id: bar
        required property ShellScreen modelData
        screen: modelData
        WlrLayershell.namespace: "graphite:bar"
        WlrLayershell.layer: WlrLayer.Top
        anchors { top: true; left: true; right: true }
        implicitHeight: Theme.barHeight
        color: "transparent"

        Component.onCompleted: Panels.registerBar(bar)
        Component.onDestruction: Panels.unregisterBar(bar)

        // Caffeine (control center tile) needs a mapped surface; the bar is always mapped.
        IdleInhibitor { window: bar; enabled: Panels.caffeine }

        Rectangle {
            anchors.fill: parent
            color: Theme.menubarGlass
            // mock: inset 0 -.5px 0 rgba(255,255,255,.07)
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: Theme.rimWidth
                color: Theme.fill
            }
            // click on empty bar closes popups
            MouseArea { anchors.fill: parent; onClicked: Panels.close() }
        }

        WidgetRow {
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            ids: Config.opt.bar?.left ?? []
        }
        WidgetRow {
            anchors.centerIn: parent
            ids: Config.opt.bar?.center ?? []
        }
        WidgetRow {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            ids: Config.opt.bar?.right ?? []
        }
    }
}

import QtQuick
import Quickshell.Wayland
import qs.core
import qs.components

// Focused window title (secondary text). Not in the default layout; add "windowTitle" to bar.left.
Item {
    id: root
    property string widgetId: "windowTitle"
    readonly property var options: Config.widget(widgetId)
    readonly property var toplevel: ToplevelManager.activeToplevel
    implicitHeight: Theme.barHeight - 6
    implicitWidth: Math.min(label.implicitWidth, options.maxWidth ?? 360) + 12
    GText {
        id: label
        x: 6; width: parent.width - 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.toplevel && root.toplevel.activated ? root.toplevel.title : ""
        secondary: true
    }
}

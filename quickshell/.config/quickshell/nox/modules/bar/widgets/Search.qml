import QtQuick
import qs.core
import qs.components

// mock "search" status item: opens the launcher (Spotlight)
BarButton {
    property string widgetId: "search"
    hpad: 7
    active: Panels.launcherOpen
    onClicked: Panels.launcherOpen = !Panels.launcherOpen
    Glyph { name: "search"; anchors.verticalCenter: parent.verticalCenter }
}

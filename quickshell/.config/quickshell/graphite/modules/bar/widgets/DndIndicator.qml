import QtQuick
import qs.core
import qs.components
import qs.services

// mock .dndi: filled moon while Do Not Disturb is on (click = Control Center)
BarButton {
    property string widgetId: "dnd"
    hpad: 7
    visible: Notifs.dnd
    onClicked: Panels.toggle("controlCenter")
    Glyph { name: "moonF"; anchors.verticalCenter: parent.verticalCenter }
}

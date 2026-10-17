import QtQuick
import qs.core
import qs.components

BarButton {
    property string widgetId: "controlCenter"
    active: Panels.popup === "controlCenter"
    onClicked: Panels.toggle("controlCenter")
    ControlCenterGlyph { size: Theme.iconSize; anchors.verticalCenter: parent.verticalCenter }
}

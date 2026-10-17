import QtQuick
import qs.core
import qs.components

BarButton {
    property string widgetId: "controlCenter"
    hpad: 7
    active: Panels.popup === "controlCenter"
    onClicked: Panels.toggle("controlCenter")
    Glyph { name: "cc"; anchors.verticalCenter: parent.verticalCenter }
}

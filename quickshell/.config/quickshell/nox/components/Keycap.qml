import QtQuick
import qs.core

// Keycap chip (mock kbd): 19px, min 19 wide, 0 5px padding, radius 5 (3 in square looks), white
// 10% fill, 0.5px light rim + dark bottom edge, label colour 11px medium (Telemetry: label font).
Rectangle {
    property alias text: kt.text
    implicitWidth: Math.max(19, kt.implicitWidth + 10)
    implicitHeight: 19
    radius: Theme.square ? 3 : 5
    color: Theme.white(0.1)
    border.width: Theme.rimWidth
    border.color: Theme.white(0.14)
    Rectangle { x: parent.radius; width: parent.width - parent.radius * 2; y: parent.height - 1; height: 1; color: Qt.rgba(0, 0, 0, 0.35) }
    GText {
        id: kt
        anchors.centerIn: parent
        font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: Theme.labelsMono ? 10 : 11
        font.weight: Font.Medium
    }
}

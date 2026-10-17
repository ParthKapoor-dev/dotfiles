import QtQuick
import qs.core

// Mock "logo" glyph: ring + centre dot (drawn, so no image asset needed).
Item {
    property real size: 16
    property color color: Theme.label
    implicitWidth: size; implicitHeight: size
    Rectangle {
        anchors.centerIn: parent
        width: parent.size * 0.66; height: width; radius: width / 2
        color: "transparent"; border.width: parent.size * 0.13; border.color: parent.color
    }
    Rectangle {
        anchors.centerIn: parent
        width: parent.size * 0.2; height: width; radius: width / 2
        color: parent.color
    }
}

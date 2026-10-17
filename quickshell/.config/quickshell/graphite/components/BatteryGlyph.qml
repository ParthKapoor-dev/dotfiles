import QtQuick
import qs.core

// macOS-style horizontal battery: outline, proportional fill, terminal nub, bolt when charging.
Item {
    id: b
    property real level: 1          // 0..1
    property bool charging: false
    property bool low: false
    property color color: Theme.label
    implicitWidth: 25; implicitHeight: 12

    Rectangle {
        id: body
        width: 22; height: 11; anchors.verticalCenter: parent.verticalCenter
        radius: 3.2
        color: "transparent"
        border.width: 1; border.color: Qt.rgba(b.color.r, b.color.g, b.color.b, 0.45)
        Rectangle {
            x: 2; y: 2; height: parent.height - 4; radius: 1.6
            width: Math.max(1.5, (parent.width - 4) * Math.max(0, Math.min(1, b.level)))
            color: b.charging ? Theme.green : b.low ? Theme.red : b.color
        }
    }
    Rectangle {
        x: body.width + 1; width: 1.6; height: 4; radius: 0.8
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.rgba(b.color.r, b.color.g, b.color.b, 0.45)
    }
    GIcon {
        visible: b.charging
        anchors.centerIn: body
        name: "bolt"; size: 13; filled: true
        color: "white"
        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.55)
    }
}

import QtQuick
import qs.core

// mock .ctog: round icon (accent when on) + name + status line
Item {
    id: root
    property string icon
    property string name
    property string status
    property bool on: false
    signal clicked()
    implicitHeight: 38
    Rectangle {
        id: ci
        width: 30; height: 30; radius: 15
        anchors.verticalCenter: parent.verticalCenter
        color: root.on ? Theme.accent : Theme.fill2
        Behavior on color { ColorAnimation { duration: Theme.durFade } }
        GIcon { anchors.centerIn: parent; name: root.icon; size: 16; filled: root.on; color: root.on ? Theme.onAccent : Theme.label }
    }
    Column {
        anchors.left: ci.right; anchors.leftMargin: 9; anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        GText { width: parent.width; text: root.name; font.pixelSize: Theme.fontSize - 1; font.weight: Font.DemiBold }
        GText { width: parent.width; text: root.status; small: true; secondary: true }
    }
    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}

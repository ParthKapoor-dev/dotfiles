import QtQuick
import qs.core

// mock .ctile: square module with a round icon and a small caption
Card {
    id: root
    property string icon
    property string name
    property bool on: false
    signal clicked()
    Column {
        anchors.centerIn: parent
        spacing: 6
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 30; height: 30; radius: 15
            color: root.on ? Theme.accent : Theme.fill2
            Behavior on color { ColorAnimation { duration: Theme.durFade } }
            GIcon { anchors.centerIn: parent; name: root.icon; size: 16; filled: root.on; color: root.on ? Theme.onAccent : Theme.label }
        }
        GText { anchors.horizontalCenter: parent.horizontalCenter; text: root.name; font.pixelSize: Theme.fontSizeSmall; horizontalAlignment: Text.AlignHCenter }
    }
    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}

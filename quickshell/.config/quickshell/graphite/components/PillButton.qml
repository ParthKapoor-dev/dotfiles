import QtQuick
import qs.core

// Small pill button (mock .pillbtn): optional icon + label; accent when `on`.
Rectangle {
    id: root
    property string text
    property string icon
    property bool on: false
    signal clicked()
    implicitHeight: 24
    implicitWidth: row.implicitWidth + 20
    radius: height / 2
    color: on ? Theme.accent : mouse.containsMouse ? Theme.fill3 : Theme.fill2
    border.width: Theme.rimWidth
    border.color: Theme.rim
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        GIcon { visible: root.icon !== ""; name: root.icon; size: 13; filled: root.on; color: root.on ? Theme.onAccent : Theme.label; anchors.verticalCenter: parent.verticalCenter }
        GText { visible: root.text !== ""; text: root.text; small: true; font.weight: Font.Medium; color: root.on ? Theme.onAccent : Theme.label; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.clicked() }
}

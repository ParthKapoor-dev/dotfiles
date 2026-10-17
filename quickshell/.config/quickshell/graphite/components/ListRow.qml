import QtQuick
import qs.core

// Popup row (mock .prow): round icon chip, title + optional subtitle, optional right text.
Item {
    id: root
    property string icon
    property string title
    property string subtitle
    property string trailing
    property bool on: false
    property bool chip: true
    signal clicked()
    implicitHeight: subtitle ? 40 : 34
    implicitWidth: 260

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl
        color: Theme.fill
        visible: mouse.containsMouse
    }
    Rectangle {
        id: chipBg
        visible: root.chip
        x: 10; anchors.verticalCenter: parent.verticalCenter
        width: 26; height: 26; radius: 13
        color: root.on ? Theme.accent : Theme.fill2
        GIcon { anchors.centerIn: parent; name: root.icon; size: 15; filled: root.on; color: root.on ? Theme.onAccent : Theme.label }
    }
    GIcon {
        visible: !root.chip && root.icon !== ""
        x: 10; anchors.verticalCenter: parent.verticalCenter
        name: root.icon; size: 16
    }
    Column {
        anchors.left: parent.left; anchors.leftMargin: root.chip || root.icon ? 46 : 10
        anchors.right: trail.left; anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        GText { width: parent.width; text: root.title }
        GText { width: parent.width; text: root.subtitle; small: true; secondary: true; visible: text !== "" }
    }
    GText {
        id: trail
        anchors.right: parent.right; anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: root.trailing; secondary: true; small: true
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.clicked() }
}

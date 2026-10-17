import QtQuick
import qs.core

// Menu item (mock .mi): 22px, accent highlight on hover; or a separator.
Item {
    id: root
    property string text
    property bool separator: false
    property bool enabled: true
    property bool checked: false
    property bool hasChildren: false
    signal triggered()
    implicitWidth: label.implicitWidth + 50
    implicitHeight: separator ? 11 : 22

    Rectangle {
        visible: root.separator
        anchors.verticalCenter: parent.verticalCenter
        x: 10; width: parent.width - 20; height: 1
        color: Theme.sep
    }
    Rectangle {
        visible: !root.separator
        anchors.fill: parent
        radius: Theme.radiusControl - 1
        color: Theme.accent
        opacity: mouse.containsMouse && root.enabled ? 1 : 0
    }
    GIcon {
        visible: root.checked && !root.separator
        x: 5; anchors.verticalCenter: parent.verticalCenter
        name: "check"; size: 13
        color: mouse.containsMouse ? Theme.onAccent : Theme.label
    }
    GText {
        id: label
        visible: !root.separator
        x: 22; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 40
        text: root.text
        color: !root.enabled ? Theme.label3 : mouse.containsMouse ? Theme.onAccent : Theme.label
    }
    GIcon {
        visible: root.hasChildren && !root.separator
        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
        name: "chevron_right"; size: 14
        color: mouse.containsMouse ? Theme.onAccent : Theme.label2
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !root.separator
        hoverEnabled: true
        onClicked: if (root.enabled) root.triggered()
    }
}

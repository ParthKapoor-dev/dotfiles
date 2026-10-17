import QtQuick
import qs.core

// mock .pop-h: popover title (semibold) with an optional control/value on the right.
Item {
    id: root
    property string title
    property string value: ""            // grey value on the right (battery %)
    property bool showSwitch: false
    property bool checked: false
    signal toggled()
    implicitWidth: 260
    implicitHeight: 32
    GText { x: 10; anchors.verticalCenter: parent.verticalCenter; text: root.title; font.weight: Font.DemiBold }
    GText { visible: root.value !== ""; anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: root.value; secondary: true }
    GSwitch {
        visible: root.showSwitch
        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
        checked: root.checked
        onToggled: root.toggled()
    }
}

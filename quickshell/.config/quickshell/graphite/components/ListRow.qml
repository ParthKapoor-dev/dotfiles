import QtQuick
import qs.core

// Popover row (mock .prow): 34px (40 with a subtitle), round 26px icon chip (accent when `on`),
// title + optional subtitle, optional right text or right glyph. Hover = white 7%.
Item {
    id: root
    property string icon                 // Glyph name (mock icon set; Material name works as fallback)
    property string title
    property string subtitle
    property color subtitleColor: Theme.label2
    property string trailing
    property string trailingIcon: ""
    property bool on: false
    property bool chip: true
    property bool busy: false            // dims the row (connecting…)
    property bool hoverable: true
    property alias hovered: mouse.containsMouse
    default property alias extra: extraBox.data   // content below the title row (inline forms)
    signal clicked()
    signal rightClicked()
    implicitWidth: 260
    implicitHeight: (subtitle ? 40 : 34) + extraBox.childrenRect.height

    Rectangle {
        anchors.fill: parent
        radius: Theme.square ? 3 : 6
        color: Theme.fill
        opacity: mouse.containsMouse && root.hoverable ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
    }
    Item {
        id: head
        width: parent.width; height: root.subtitle ? 40 : 34
        Rectangle {
            id: chipBg
            visible: root.chip
            x: 10; anchors.verticalCenter: parent.verticalCenter
            width: 26; height: 26; radius: Theme.square ? 4 : 13
            color: root.on ? Theme.accent : Theme.fill2
            Behavior on color { ColorAnimation { duration: Theme.durFade } }
            Glyph { anchors.centerIn: parent; name: root.icon; size: 15; color: root.on ? Theme.onAccent : Theme.label }
        }
        Glyph {
            visible: !root.chip && root.icon !== ""
            x: 10; anchors.verticalCenter: parent.verticalCenter
            name: root.icon; size: 15
        }
        Column {
            anchors.left: parent.left; anchors.leftMargin: root.chip || root.icon ? 46 : 10
            anchors.right: trail.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            opacity: root.busy ? 0.6 : 1
            GText { width: parent.width; text: root.title }
            GText { width: parent.width; text: root.subtitle; small: true; color: root.subtitleColor; visible: text !== "" }
        }
        Row {
            id: trail
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            GText { visible: root.trailing !== ""; text: root.trailing; color: Theme.label2; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Glyph { visible: root.trailingIcon !== ""; name: root.trailingIcon; size: 12; color: Theme.label2; anchors.verticalCenter: parent.verticalCenter }
        }
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: m => m.button === Qt.RightButton ? root.rightClicked() : root.clicked()
        }
    }
    Item {
        id: extraBox
        y: head.height
        width: parent.width
        height: childrenRect.height
    }
}

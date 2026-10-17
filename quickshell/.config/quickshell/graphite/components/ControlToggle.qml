import QtQuick
import qs.core

// mock .ctog: 30px round icon (accent when on; square in Telemetry) + name (12.5 semibold) + status.
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
        width: 30; height: 30; radius: Theme.square ? 4 : 15
        anchors.verticalCenter: parent.verticalCenter
        color: root.on ? Theme.accent : Theme.white(0.14)
        Behavior on color { ColorAnimation { duration: Theme.durFade } }
        Glyph { anchors.centerIn: parent; name: root.icon; size: 16; color: root.on ? Theme.onAccent : Theme.label }
    }
    Column {
        anchors.left: ci.right; anchors.leftMargin: 9; anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        GText { width: parent.width; text: root.name; font.pixelSize: 13; font.weight: Font.DemiBold }
        GText {
            width: parent.width; text: root.status
            color: Theme.label2
            font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
            font.pixelSize: Theme.square ? 10 : 11
            font.capitalization: Theme.square ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: Theme.square ? 0.5 : 0
        }
    }
    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}

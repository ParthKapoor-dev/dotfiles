import QtQuick
import qs.core

// Small pill button (mock .pillbtn): 24px, 11.5px medium, glass 70% + rim; accent when `on`.
Rectangle {
    id: root
    property string text
    property string icon
    property bool on: false
    signal clicked()
    implicitHeight: 24
    implicitWidth: row.implicitWidth + 20
    radius: Theme.square ? 4 : height / 2
    color: on ? Theme.accent : Theme.rgba(Theme.t.color.glass, mouse.containsMouse ? 0.95 : 0.75)
    border.width: Theme.glassOpaque ? 1 : Theme.rimWidth
    border.color: Theme.glassOpaque ? Theme.hair : Theme.rim
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Glyph { visible: root.icon !== ""; name: root.icon; size: 12; color: root.on ? Theme.onAccent : Theme.label; anchors.verticalCenter: parent.verticalCenter }
        GText { visible: root.text !== ""; text: root.text; font.pixelSize: 11; font.weight: Font.Medium; color: root.on ? Theme.onAccent : Theme.label; anchors.verticalCenter: parent.verticalCenter }
    }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.clicked() }
}

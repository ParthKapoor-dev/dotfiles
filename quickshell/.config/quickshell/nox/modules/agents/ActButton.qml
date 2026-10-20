import QtQuick
import qs.core

// Agents panel action (Telemetry: square, mono caps). primary = accent fill (the item's Enter
// action, only while its item is selected); key = the shortcut shown after the label.
Rectangle {
    id: root
    property string text
    property string key: ""
    property bool primary: false
    property bool danger: false
    signal clicked()
    implicitWidth: row.implicitWidth + 16
    implicitHeight: 22
    radius: Theme.square ? 0 : 5
    color: primary ? Theme.accent : ma.containsMouse ? Theme.white(0.1) : "transparent"
    border.width: primary ? 0 : 1
    border.color: danger ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.5) : Theme.white(ma.containsMouse ? 0.24 : 0.14)
    Behavior on color { ColorAnimation { duration: Theme.durHover } }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
        Text {
            text: root.text
            color: root.primary ? Theme.onAccent : root.danger ? Theme.red : Theme.label
            font.family: Theme.fontLabel
            font.pixelSize: 10
            font.weight: Font.Medium
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.0
        }
        Text {
            visible: root.key !== ""
            text: root.key
            color: root.primary ? Qt.rgba(Theme.onAccent.r, Theme.onAccent.g, Theme.onAccent.b, 0.7) : Theme.label3
            font.family: Theme.fontLabel
            font.pixelSize: 10
            font.weight: Font.Medium
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

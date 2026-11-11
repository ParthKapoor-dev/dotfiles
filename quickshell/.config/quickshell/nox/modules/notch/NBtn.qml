import QtQuick
import qs.core
import qs.components

// A notch button (mock .btn): "go" = accent fill with a glow, "line" = hairline outline,
// "ghost" = text only. key = the keycap shown after the label; note = small mono text.
Rectangle {
    id: b
    property string text: ""
    property string key: ""
    property string note: ""
    property string kind: "line"
    property color danger: Theme.red
    property bool dangerHover: false
    signal clicked()
    implicitHeight: 34
    implicitWidth: row.implicitWidth + 26
    radius: 8
    color: kind === "go" ? (ma.containsMouse ? Qt.lighter(Theme.accent, 1.08) : Theme.accent)
        : ma.containsMouse ? Theme.white(0.07) : "transparent"
    border.width: kind === "line" ? 1 : 0
    border.color: Theme.white(0.13)
    scale: ma.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 120 } }
    Behavior on color { ColorAnimation { duration: 140 } }
    // glow under the primary button
    Rectangle {
        visible: b.kind === "go"
        z: -1
        anchors.centerIn: parent
        width: parent.width + 18; height: parent.height + 14; radius: height / 2
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, ma.containsMouse ? 0.22 : 0.13)
        Behavior on color { ColorAnimation { duration: 160 } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        GText {
            anchors.verticalCenter: parent.verticalCenter
            text: b.text
            font.pixelSize: 13
            font.weight: Font.Medium
            color: b.kind === "go" ? Theme.onAccent : (b.dangerHover && ma.containsMouse) ? b.danger : b.kind === "ghost" ? Theme.label2 : Theme.label
        }
        GText {
            visible: b.note !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: b.note
            font.family: Theme.fontMono
            font.pixelSize: 10
            color: Theme.label3
            elide: Text.ElideMiddle
            width: Math.min(implicitWidth, 150)
        }
        Rectangle {
            visible: b.key !== ""
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: kt.implicitWidth + 10; implicitHeight: 17; radius: 4
            color: b.kind === "go" ? Qt.rgba(0, 0, 0, 0.22) : Theme.white(0.09)
            GText {
                id: kt
                anchors.centerIn: parent
                text: b.key
                font.family: "GeistMono Nerd Font"
                font.pixelSize: 10
                font.weight: Font.Medium
                color: b.kind === "go" ? Theme.onAccent : Theme.label2
            }
        }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: b.clicked() }
}

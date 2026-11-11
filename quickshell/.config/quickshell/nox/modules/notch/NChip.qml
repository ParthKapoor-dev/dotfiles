import QtQuick
import qs.core
import qs.components

// A small mono tag (mock .chip); hot = red, for risk tags.
Rectangle {
    id: chip
    property string text: ""
    property bool hot: false
    implicitWidth: ct.implicitWidth + 14
    implicitHeight: 19
    radius: 5
    color: hot ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.09) : "transparent"
    border.width: 1
    border.color: hot ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.5) : Theme.white(0.13)
    GText {
        id: ct
        anchors.centerIn: parent
        text: chip.text
        font.family: Theme.fontMono; font.pixelSize: 10; font.letterSpacing: 0.6
        color: chip.hot ? Theme.red : Theme.label2
    }
}

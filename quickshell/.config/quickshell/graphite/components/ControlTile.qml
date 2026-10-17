import QtQuick
import qs.core

// mock .ctile: module with a centred 30px round icon and a caption (min height 66).
// The caption is one label that wraps onto a second line when it doesn't fit ("Night / Light",
// both lines in the label colour); `sub` = optional status line under it in label2 (e.g. the
// current look), never the dimmed label3 that read as "disabled".
// The icon sits at a fixed height (not centred with the caption), so tiles side by side keep
// their icons on one line whether or not their caption wraps. Tiles are 76px tall everywhere.
// `enabled: false` = unavailable: 45% opacity, no hover, no press, clicks ignored.
Card {
    id: root
    property string icon
    property string name
    property string sub: ""
    property bool on: false
    property bool enabled: true
    signal clicked()
    implicitHeight: 76
    opacity: enabled ? 1 : 0.45
    Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
    scale: tileMouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    // hover: a faint lift of the module fill
    Rectangle {
        parent: root; z: -1
        anchors.fill: parent; radius: root.radius
        color: Theme.white(0.04)
        opacity: tileMouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    }
    Item {
        width: parent.width; height: parent.height   // the Card's padded content area
        Rectangle {
            id: chip
            y: 1
            anchors.horizontalCenter: parent.horizontalCenter
            width: 30; height: 30; radius: Theme.square ? 4 : 15
            color: root.on ? Theme.accent : Theme.white(tileMouse.containsMouse ? 0.2 : 0.14)
            Behavior on color { ColorAnimation { duration: Theme.durHover } }
            Glyph { anchors.centerIn: parent; name: root.icon; size: 16; color: root.on ? Theme.onAccent : Theme.label }
        }
        Column {
            y: chip.y + chip.height + 6
            // the caption may use the tile's padding too ("Screenshot" at 11px in a 66px tile)
            x: -7; width: parent.width + 14
            GText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.name
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                lineHeight: 0.95
                font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
                font.pixelSize: Theme.square ? 10 : 11
                font.capitalization: Theme.square ? Font.AllUppercase : Font.MixedCase
                font.letterSpacing: Theme.square ? 0.5 : 0
            }
            GText {
                visible: root.sub !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.sub
                color: Theme.label2
                font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
                font.pixelSize: Theme.square ? 9 : 10
                font.capitalization: Theme.square ? Font.AllUppercase : Font.MixedCase
                font.letterSpacing: Theme.square ? 0.5 : 0
            }
        }
    }
    MouseArea {
        id: tileMouse
        parent: root
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

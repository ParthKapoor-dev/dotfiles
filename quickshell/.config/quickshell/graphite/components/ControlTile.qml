import QtQuick
import qs.core

// mock .ctile: module with a centred 30px round icon and a small caption (min height 66).
// `sub` = second caption line in label3 (mock "Dark Mode / locked").
Card {
    id: root
    property string icon
    property string name
    property string sub: ""
    property bool on: false
    property bool locked: false
    signal clicked()
    implicitHeight: 66
    opacity: locked ? 0.8 : 1
    scale: tileMouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    // hover: a faint lift of the module fill
    Rectangle {
        parent: root; z: -1
        anchors.fill: parent; radius: root.radius
        color: Theme.white(0.04)
        opacity: tileMouse.containsMouse && !root.locked ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    }
    Column {
        anchors.centerIn: parent
        spacing: 6
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 30; height: 30; radius: Theme.square ? 4 : 15
            color: root.on ? Theme.accent : Theme.white(tileMouse.containsMouse && !root.locked ? 0.2 : 0.14)
            Behavior on color { ColorAnimation { duration: Theme.durHover } }
            Glyph { anchors.centerIn: parent; name: root.icon; size: 16; color: root.on ? Theme.onAccent : Theme.label }
        }
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            Repeater {
                model: root.sub ? [root.name, root.sub] : [root.name]
                GText {
                    required property string modelData
                    required property int index
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: index === 1 ? Theme.label3 : Theme.label
                    font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
                    font.pixelSize: Theme.square ? 10 : 11
                    font.capitalization: Theme.square ? Font.AllUppercase : Font.MixedCase
                    font.letterSpacing: Theme.square ? 0.5 : 0
                }
            }
        }
    }
    MouseArea { id: tileMouse; parent: root; anchors.fill: parent; enabled: !root.locked; hoverEnabled: true; onClicked: root.clicked() }
}

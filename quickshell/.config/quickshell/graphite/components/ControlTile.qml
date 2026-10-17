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
    Column {
        anchors.centerIn: parent
        spacing: 6
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 30; height: 30; radius: Theme.square ? 4 : 15
            color: root.on ? Theme.accent : Theme.white(0.14)
            Behavior on color { ColorAnimation { duration: Theme.durFade } }
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
    MouseArea { anchors.fill: parent; enabled: !root.locked; onClicked: root.clicked() }
}

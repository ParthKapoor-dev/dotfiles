pragma ComponentBehavior: Bound
import QtQuick
import qs.core

// mock .seg: dark track (black 28%), 26px buttons, selected = white 17% + soft shadow.
// model: [{ id, label, glyph? }], current: id
Rectangle {
    id: root
    property var model: []
    property var current
    signal picked(var id)
    implicitHeight: 30
    radius: Theme.square ? 4 : 9
    color: Qt.rgba(0, 0, 0, 0.28)
    Row {
        x: 2; y: 2
        spacing: 2
        Repeater {
            model: root.model
            Rectangle {
                id: seg
                required property var modelData
                readonly property bool on: modelData.id === root.current
                width: (root.width - 4 - 2 * (root.model.length - 1)) / root.model.length
                height: 26
                radius: Theme.square ? 3 : 7
                color: on ? Theme.white(0.17) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFade } }
                Row {
                    anchors.centerIn: parent
                    spacing: 5
                    Glyph { visible: !!seg.modelData.glyph; name: seg.modelData.glyph ?? ""; size: 13; color: lbl.color; anchors.verticalCenter: parent.verticalCenter }
                    GText { id: lbl; text: seg.modelData.label; font.pixelSize: 12; color: seg.on ? Theme.label : Theme.label2; anchors.verticalCenter: parent.verticalCenter }
                }
                MouseArea { anchors.fill: parent; onClicked: root.picked(seg.modelData.id) }
            }
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// mock Sound module: title + current output, slider, output rows (.orow: 22px chip, accent = current)
Card {
    id: root
    property bool shown: Audio.sink !== null      // no PipeWire sink: hide instead of a dead 0% slider
    CardTitle { id: t; width: parent.width; text: "Sound"; detail: Audio.sinkName }
    GSlider {
        id: sld
        anchors.top: t.bottom; anchors.topMargin: 8
        width: parent.width
        icon: Audio.glyph
        value: Audio.volume
        onMoved: v => Audio.setVolume(v)
    }
    Column {
        anchors.top: sld.bottom; anchors.topMargin: Audio.sinks.length > 1 ? 8 : 0
        width: parent.width
        spacing: 2
        Repeater {
            model: Audio.sinks.length > 1 ? Audio.sinks : []
            Item {
                id: orow
                required property var modelData
                readonly property bool on: modelData === Audio.sink
                width: parent.width; height: 30
                Rectangle { anchors.fill: parent; radius: Theme.square ? 3 : 7; color: Theme.fill; opacity: om.containsMouse ? 1 : 0 }
                Rectangle {
                    id: oi
                    x: 6; anchors.verticalCenter: parent.verticalCenter
                    width: 22; height: 22; radius: Theme.square ? 4 : 11
                    color: orow.on ? Theme.accent : Theme.fill2
                    Glyph { anchors.centerIn: parent; name: Audio.glyphFor(orow.modelData); size: 13; color: orow.on ? Theme.onAccent : Theme.label }
                }
                GText { anchors.left: oi.right; anchors.leftMargin: 9; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: Audio.nodeName(orow.modelData); font.pixelSize: 13 }
                MouseArea { id: om; anchors.fill: parent; hoverEnabled: true; onClicked: Audio.setSink(orow.modelData) }
            }
        }
    }
}

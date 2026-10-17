pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

Card {
    id: root

    Item {
        id: head
        width: parent.width; height: t.height
        CardTitle { id: t; text: "Sound" }
        GText { anchors.right: parent.right; anchors.left: t.right; anchors.leftMargin: 8; horizontalAlignment: Text.AlignRight; text: Audio.sinkName; small: true; secondary: true }
    }
    GSlider {
        id: sld
        anchors.top: head.bottom; anchors.topMargin: 8
        width: parent.width
        icon: Audio.icon
        value: Audio.volume
        onMoved: v => Audio.setVolume(v)
    }
    Column {
        id: outs
        anchors.top: sld.bottom; anchors.topMargin: Audio.sinks.length > 1 ? 8 : 0
        width: parent.width
        Repeater {
            model: Audio.sinks.length > 1 ? Audio.sinks : []
            ListRow {
                required property var modelData
                width: parent.width
                implicitHeight: 28
                chip: false
                icon: modelData === Audio.sink ? "check" : ""
                title: Audio.nodeName(modelData)
                onClicked: Audio.setSink(modelData)
            }
        }
    }
}

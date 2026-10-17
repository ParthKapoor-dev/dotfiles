pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// Output volume (PipeWire). Scroll = change, middle-click = mute, click = popover with slider +
// outputs (not in the mock's default bar; the Control Center has the same controls).
BarButton {
    id: root
    property string widgetId: "volume"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    readonly property real step: options.step ?? 0.05
    hpad: 7
    active: Panels.popup === popupId
    onClicked: b => b === Qt.MiddleButton ? Audio.toggleMute() : Panels.toggle(popupId)
    onWheel: d => Audio.setVolume(Audio.volume + (d > 0 ? step : -step))

    Glyph { name: Audio.glyph; anchors.verticalCenter: parent.verticalCenter }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        align: "itemRight"
        content: Column {
            PopHeader { width: parent.width; title: "Sound"; value: Math.round(Audio.volume * 100) + "%" }
            Item {
                width: parent.width; height: 36
                GSlider { x: 10; y: 2; width: parent.width - 20; icon: Audio.glyph; value: Audio.volume; step: root.step; onMoved: v => Audio.setVolume(v) }
            }
            SectionLabel { text: "Output" }
            Repeater {
                model: Audio.sinks
                ListRow {
                    required property var modelData
                    width: parent.width
                    icon: Audio.glyphFor(modelData)
                    on: modelData === Audio.sink
                    title: Audio.nodeName(modelData)
                    onClicked: Audio.setSink(modelData)
                }
            }
            Item { width: 1; height: 4 }
        }
    }
}

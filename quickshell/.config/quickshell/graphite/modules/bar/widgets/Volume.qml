pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// Output volume (PipeWire). Scroll = change, middle-click = mute, click = popup with slider + outputs.
BarButton {
    id: root
    property string widgetId: "volume"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    readonly property real step: options.step ?? 0.05
    active: Panels.popup === popupId
    onClicked: b => b === Qt.MiddleButton ? Audio.toggleMute() : Panels.toggle(popupId)
    onWheel: d => Audio.setVolume(Audio.volume + (d > 0 ? step : -step))

    GIcon { name: Audio.icon; filled: true; anchors.verticalCenter: parent.verticalCenter }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        content: Column {
            spacing: 2
            SectionLabel { text: "Sound" }
            GSlider {
                x: 10; width: parent.width - 20
                icon: Audio.icon
                value: Audio.volume
                step: root.step
                onMoved: v => Audio.setVolume(v)
            }
            SectionLabel { text: "Output"; topPadding: 10 }
            Repeater {
                model: Audio.sinks
                ListRow {
                    required property var modelData
                    width: parent.width
                    chip: false
                    icon: modelData === Audio.sink ? "check" : ""
                    title: Audio.nodeName(modelData)
                    onClicked: Audio.setSink(modelData)
                }
            }
        }
    }
}

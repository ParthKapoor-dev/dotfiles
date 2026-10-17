import QtQuick
import qs.core
import qs.components
import qs.services

Card {
    property bool shown: Brightness.available
    CardTitle { id: t; text: "Display" }
    GSlider {
        anchors.top: t.bottom; anchors.topMargin: 8
        width: parent.width
        icon: "light_mode"
        value: Brightness.value
        step: (Config.opt.brightness?.step ?? 5) / 100
        onMoved: v => Brightness.set(v)
    }
}

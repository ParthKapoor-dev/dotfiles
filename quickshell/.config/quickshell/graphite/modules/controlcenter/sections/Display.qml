import QtQuick
import qs.core
import qs.components
import qs.services

Card {
    property bool shown: Brightness.available
    CardTitle { id: t; width: parent.width; text: "Display"; detail: "brightness" }
    GSlider {
        anchors.top: t.bottom; anchors.topMargin: 8
        width: parent.width
        icon: "sunF"
        value: Brightness.value
        step: (Config.opt.brightness?.step ?? 5) / 100
        onMoved: v => Brightness.set(v)
    }
}

import QtQuick
import qs.core
import qs.components
import qs.services

Card {
    property bool shown: Brightness.available
    GText { id: t; text: "Display"; font.pixelSize: Theme.fontSize - 1; font.weight: Font.DemiBold }
    GSlider {
        anchors.top: t.bottom; anchors.topMargin: 8
        width: parent.width
        icon: "light_mode"
        value: Brightness.value
        step: (Config.opt.brightness?.step ?? 5) / 100
        onMoved: v => Brightness.set(v)
    }
}

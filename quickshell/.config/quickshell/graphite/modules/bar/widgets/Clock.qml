import QtQuick
import Quickshell
import qs.core
import qs.components

// "Sat 17 Oct 12:46" by default; widgets.clock.format is a Qt date format string.
BarButton {
    id: root
    property string widgetId: "clock"
    readonly property var options: Config.widget(widgetId)
    hpad: 8
    SystemClock { id: clock; precision: SystemClock.Minutes }
    GText {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, root.options.format ?? "ddd d MMM HH:mm")
        font.features: ({ "tnum": 1 })
    }
}

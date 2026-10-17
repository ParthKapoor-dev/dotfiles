import QtQuick
import Quickshell
import qs.core
import qs.components

// "Sat 17 Oct 12:46" (widgets.clock.format, Qt date format). Telemetry: label font, caps.
// widgets.clock.clickPopup: popup toggled on click (default "notifications" = Notification Center).
BarButton {
    id: root
    property string widgetId: "clock"
    readonly property var options: Config.widget(widgetId)
    readonly property bool mono: Theme.labelsMono && Theme.square
    hpad: 8
    readonly property string clickPopup: options.clickPopup ?? "notifications"
    active: clickPopup !== "" && Panels.popup === clickPopup
    onClicked: if (clickPopup !== "" && Panels.exists(clickPopup)) Panels.toggle(clickPopup)
    SystemClock { id: clock; precision: SystemClock.Minutes }
    GText {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, root.options.format ?? "ddd d MMM HH:mm")
        font.features: ({ "tnum": 1 })
        font.family: root.mono ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: root.mono ? 12 : Theme.fontSize
        font.weight: root.mono ? Font.Medium : Font.Normal
        font.capitalization: root.mono ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.mono ? 0.6 : 0
    }
}

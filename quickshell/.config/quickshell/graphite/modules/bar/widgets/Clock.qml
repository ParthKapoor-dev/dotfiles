import QtQuick
import Quickshell
import qs.core
import qs.components

// "Sat 17 Oct 12:46" by default; widgets.clock.format is a Qt date format string.
// widgets.clock.clickPopup: popup id toggled on click (default "notifications" = Notification
// Center; only when that popup exists, i.e. its module is enabled). "" = no click action.
BarButton {
    id: root
    property string widgetId: "clock"
    readonly property var options: Config.widget(widgetId)
    hpad: 8
    readonly property string clickPopup: options.clickPopup ?? "notifications"
    active: clickPopup !== "" && Panels.popup === clickPopup
    onClicked: if (clickPopup !== "" && Panels.exists(clickPopup)) Panels.toggle(clickPopup)
    SystemClock { id: clock; precision: SystemClock.Minutes }
    GText {
        anchors.verticalCenter: parent.verticalCenter
        text: Qt.formatDateTime(clock.date, root.options.format ?? "ddd d MMM HH:mm")
        font.features: ({ "tnum": 1 })
    }
}

import QtQuick
import qs.core
import qs.components
import qs.services

// Do Not Disturb toggle + link to the Notification Center. Hidden while the notifications
// module is off (another daemon, e.g. ii, owns the D-Bus name).
Card {
    property bool shown: Notifs.enabled
    implicitHeight: 58
    ControlToggle {
        width: parent.width - more.width - 8
        anchors.verticalCenter: parent.verticalCenter
        icon: "do_not_disturb_on"
        name: "Do Not Disturb"
        on: Notifs.dnd
        status: Notifs.dnd ? "On" : Notifs.count === 0 ? "No notifications" : Notifs.count + (Notifs.count === 1 ? " notification" : " notifications")
        onClicked: Notifs.toggleDnd()
    }
    PillButton {
        id: more
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        text: "Show All"
        onClicked: Panels.open("notifications")
    }
}

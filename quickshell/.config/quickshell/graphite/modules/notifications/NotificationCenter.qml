pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// Notification Center: glass popup at the top right (popup id "notifications").
// Opened from the clock (widgets.clock.clickPopup) or `qs -c graphite ipc call notifications toggle`.
GPopup {
    id: nc
    popupId: "notifications"
    align: "right"
    popupWidth: (Config.opt.notifications?.width ?? 344) + 12
    padding: 10

    content: Column {
        spacing: 8
        Item {
            width: parent.width; height: 26
            GText { x: 4; anchors.verticalCenter: parent.verticalCenter; text: "Notifications"; font.pixelSize: Theme.fontSize + 2; font.weight: Font.DemiBold }
            Row {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                PillButton { icon: "do_not_disturb_on"; text: "Focus"; on: Notifs.dnd; onClicked: Notifs.toggleDnd() }
                PillButton { visible: Notifs.count > 0; text: "Clear"; onClicked: Notifs.clearAll() }
            }
        }
        GText {
            visible: Notifs.count === 0
            width: parent.width
            topPadding: 18; bottomPadding: 18
            horizontalAlignment: Text.AlignHCenter
            text: Notifs.running ? "No Notifications" : "Notifications are handled by another daemon"
            secondary: true
        }
        ListView {
            id: listView
            visible: Notifs.count > 0
            width: parent.width
            height: Math.min(contentHeight, Config.opt.notifications?.centerMaxHeight ?? 560)
            clip: true
            spacing: 8
            boundsBehavior: Flickable.StopAtBounds
            model: Notifs.list
            delegate: Item {
                id: row
                required property var modelData
                width: listView.width
                height: card.implicitHeight + 6
                NotificationCard {
                    id: card
                    y: 6; x: 6
                    width: parent.width - 6
                    notification: row.modelData
                    compact: false
                    glass: false
                    onCloseRequested: Notifs.dismiss(row.modelData)
                }
            }
        }
    }
}

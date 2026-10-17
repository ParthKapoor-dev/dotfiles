pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Wi-Fi / wired status; popup = Wi-Fi switch + known/visible networks (scans only while open).
BarButton {
    id: root
    property string widgetId: "network"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    onActiveChanged: Network.setScanning(active)

    GIcon { name: Network.icon; filled: true; anchors.verticalCenter: parent.verticalCenter }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        content: Column {
            Item {
                width: parent.width; height: 34
                GText { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "Wi-Fi"; font.weight: Font.DemiBold }
                GSwitch {
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    checked: Network.wifiEnabled
                    onToggled: Network.setWifi(!Network.wifiEnabled)
                }
            }
            ListRow {
                visible: Network.wired
                width: parent.width
                icon: "lan"; title: "Ethernet"; subtitle: "Connected"; on: true
            }
            SectionLabel { visible: Network.wifiEnabled && Network.networks.length > 0; text: "Networks" }
            Repeater {
                model: Network.wifiEnabled
                    ? Network.networks.slice().sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength)).slice(0, 8)
                    : []
                ListRow {
                    required property var modelData
                    width: parent.width
                    icon: "wifi"
                    on: modelData.connected
                    title: modelData.name
                    trailing: modelData.connected ? "" : modelData.known ? "Known" : ""
                    onClicked: modelData.connected ? modelData.disconnect() : (modelData.known ? modelData.connect() : null)
                }
            }
            Rectangle { visible: (root.options.settingsCommand ?? []).length > 0; width: parent.width - 20; x: 10; height: 1; color: Theme.sep }
            MenuRow {
                visible: (root.options.settingsCommand ?? []).length > 0
                width: parent.width
                text: "Network Settings…"
                onTriggered: { Panels.close(); Quickshell.execDetached(root.options.settingsCommand); }
            }
        }
    }
}

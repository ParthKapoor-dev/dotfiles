pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.core
import qs.components

// Bluetooth state via native BlueZ bindings; popup = power switch + paired devices.
BarButton {
    id: root
    property string widgetId: "bluetooth"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: adapter?.enabled ?? false
    readonly property var paired: Bluetooth.devices.values.filter(d => d.paired || d.bonded)
    readonly property var connected: paired.filter(d => d.connected)
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    visible: adapter !== null

    GIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: !root.btOn ? "bluetooth_disabled" : root.connected.length ? "bluetooth_connected" : "bluetooth"
    }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        content: Column {
            Item {
                width: parent.width; height: 34
                GText { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "Bluetooth"; font.weight: Font.DemiBold }
                GSwitch {
                    anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                    checked: root.btOn
                    onToggled: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
                }
            }
            SectionLabel { visible: root.btOn && root.paired.length > 0; text: "Devices" }
            Repeater {
                model: root.btOn ? root.paired : []
                ListRow {
                    required property var modelData
                    width: parent.width
                    icon: (modelData.icon ?? "").indexOf("headset") >= 0 || (modelData.icon ?? "").indexOf("headphone") >= 0 ? "headphones"
                        : (modelData.icon ?? "").indexOf("phone") >= 0 ? "smartphone"
                        : (modelData.icon ?? "").indexOf("mouse") >= 0 ? "mouse"
                        : (modelData.icon ?? "").indexOf("keyboard") >= 0 ? "keyboard" : "bluetooth"
                    on: modelData.connected
                    title: modelData.name || modelData.deviceName
                    trailing: modelData.connected && modelData.batteryAvailable ? Math.round(modelData.battery * 100) + "%" : ""
                    onClicked: modelData.connected ? modelData.disconnect() : modelData.connect()
                }
            }
            Rectangle { visible: (root.options.settingsCommand ?? []).length > 0; width: parent.width - 20; x: 10; height: 1; color: Theme.sep }
            MenuRow {
                visible: (root.options.settingsCommand ?? []).length > 0
                width: parent.width
                text: "Bluetooth Settings…"
                onTriggered: { Panels.close(); Quickshell.execDetached(root.options.settingsCommand); }
            }
        }
    }
}

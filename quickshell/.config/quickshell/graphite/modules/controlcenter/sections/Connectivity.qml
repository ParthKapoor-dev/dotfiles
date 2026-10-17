import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.core
import qs.components
import qs.services

// Wi-Fi + Bluetooth toggles (left), Caffeine + Lock tiles (right)
Item {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var btConnected: Bluetooth.devices.values.filter(d => d.connected)
    implicitHeight: 104
    readonly property real half: (width - 10) / 2

    Card {
        width: root.half; height: root.implicitHeight
        Column {
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            ControlToggle {
                width: parent.width
                icon: Network.wired ? "lan" : Network.wifiEnabled ? "wifi" : "wifi_off"
                name: Network.wired ? "Network" : "Wi-Fi"
                on: Network.wired || (Network.wifiEnabled && Network.ssid !== "")
                status: Network.wired ? "Ethernet" : !Network.wifiEnabled ? "Off" : (Network.ssid || "Not connected")
                onClicked: Network.setWifi(!Network.wifiEnabled)
            }
            ControlToggle {
                width: parent.width
                icon: root.adapter?.enabled ? "bluetooth" : "bluetooth_disabled"
                name: "Bluetooth"
                on: root.adapter?.enabled ?? false
                status: !(root.adapter?.enabled ?? false) ? "Off" : root.btConnected.length ? (root.btConnected[0].name || root.btConnected[0].deviceName) : "On"
                onClicked: if (root.adapter) root.adapter.enabled = !root.adapter.enabled
            }
        }
    }
    Row {
        x: root.half + 10
        spacing: 10
        ControlTile {
            width: (root.half - 10) / 2; height: root.implicitHeight
            icon: "coffee"; name: "Caffeine"; on: Panels.caffeine
            onClicked: Panels.caffeine = !Panels.caffeine
        }
        ControlTile {
            width: (root.half - 10) / 2; height: root.implicitHeight
            icon: "lock"; name: "Lock"
            onClicked: { Panels.close(); Quickshell.execDetached(Config.opt.controlCenter?.lockCommand ?? ["loginctl", "lock-session"]); }
        }
    }
}

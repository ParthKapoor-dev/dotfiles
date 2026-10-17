import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Top block of the Control Center (mock grid rows 1-2): Wi-Fi / Bluetooth / Airplane (2x2 module),
// Focus (Do Not Disturb), Night Light and Caffeine tiles. Focus is 56 tall so the tiles under it
// are 76 like the bottom row (one tile size everywhere).
Item {
    id: root
    readonly property real col: (width - 30) / 4
    implicitHeight: 66 * 2 + 10

    Card {
        width: root.col * 2 + 10; height: root.implicitHeight
        Column {
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            ControlToggle {
                width: parent.width
                icon: Network.wired ? "lan" : Network.wifiEnabled ? "wifi" : "wifiOff"
                name: Network.wired ? "Network" : "Wi-Fi"
                on: Network.wired || (Network.wifiDevice !== null && Network.wifiEnabled)
                status: Network.wired ? "Ethernet" : Network.wifiDevice === null ? "No adapter" : !Network.wifiEnabled ? "Off" : (Network.ssid || "Not connected")
                onClicked: if (Network.wifiDevice !== null) Network.setWifi(!Network.wifiEnabled)
            }
            ControlToggle {
                width: parent.width
                icon: Bt.enabled ? "bt" : "btOff"
                name: "Bluetooth"
                on: Bt.enabled
                status: Bt.adapter === null ? "No adapter" : !Bt.enabled ? "Off" : Bt.connected.length ? Bt.nameOf(Bt.connected[0]) : "On"
                onClicked: Bt.setEnabled(!Bt.enabled)
            }
            ControlToggle {
                width: parent.width
                readonly property bool airplane: !Network.wifiEnabled && !Bt.enabled
                icon: "plane"
                name: "Airplane"
                on: airplane
                status: airplane ? "On" : "Off"
                onClicked: { const on = !airplane; Network.setWifi(!on); Bt.setEnabled(!on); }
            }
        }
    }
    Card {
        x: root.col * 2 + 20
        width: root.col * 2 + 10; height: 56
        ControlToggle {
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            icon: "moonF"; name: "Focus"
            on: Notifs.dnd
            status: Notifs.dnd ? "Do Not Disturb" : "Off"
            onClicked: Notifs.toggleDnd()
        }
    }
    ControlTile {
        x: root.col * 2 + 20; y: 66
        width: root.col; height: 76
        icon: "sunset"; name: "Night Light"
        on: NightLight.on
        onClicked: NightLight.toggle()
    }
    ControlTile {
        x: root.col * 3 + 30; y: 66
        width: root.col; height: 76
        icon: "coffee"; name: "Caffeine"
        on: Panels.caffeine
        onClicked: Panels.caffeine = !Panels.caffeine
    }
}

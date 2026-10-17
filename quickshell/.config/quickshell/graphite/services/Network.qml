pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// Thin view over native Quickshell.Networking (NetworkManager over D-Bus; no nmcli monitor).
Singleton {
    id: root

    readonly property var devices: Networking.devices.values
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var networks: wifiDevice ? wifiDevice.networks.values : []
    readonly property var active: networks.find(n => n.connected) ?? null
    readonly property string ssid: active?.name ?? ""
    readonly property real strength: {
        const s = active?.signalStrength ?? 0;
        return s > 1 ? s / 100 : s;
    }
    readonly property bool wired: wiredDevice !== null

    readonly property string icon: wired ? "lan"
        : !wifiEnabled ? "wifi_off"
        : !active ? "signal_wifi_0_bar"
        : strength > 0.75 ? "network_wifi"
        : strength > 0.5 ? "network_wifi_3_bar"
        : strength > 0.25 ? "network_wifi_2_bar" : "network_wifi_1_bar"

    function setWifi(on) { Networking.wifiEnabled = on; }
    // scanning only while a UI that lists networks is open
    function setScanning(on) { if (wifiDevice) wifiDevice.scannerEnabled = on; }
}

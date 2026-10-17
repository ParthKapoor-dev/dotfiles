pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Networking

// Thin view over native Quickshell.Networking (NetworkManager over D-Bus; no nmcli process).
// Connecting: known networks use their saved profile (connect()); new secured networks take a
// PSK through WifiNetwork.connectWithPsk() (sent over D-Bus, never on a command line or in logs).
Singleton {
    id: root

    readonly property var devices: Networking.devices.values
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevice: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property var networks: wifiDevice ? wifiDevice.networks.values : []
    readonly property var active: networks.find(n => n.connected) ?? null
    readonly property string ssid: active?.name ?? ""
    readonly property real strength: level(active)
    readonly property bool wired: wiredDevice !== null

    function level(n) { const s = n?.signalStrength ?? 0; return s > 1 ? s / 100 : s; }
    function secured(n) { return n && n.security !== undefined && n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe; }
    function needsPsk(n) {
        return n && (n.security === WifiSecurityType.WpaPsk || n.security === WifiSecurityType.Wpa2Psk || n.security === WifiSecurityType.Sae);
    }
    function glyphFor(n) {
        const l = level(n);
        return l > 0.66 ? "wifi" : l > 0.4 ? "wifi2" : l > 0.15 ? "wifi1" : "wifi0";
    }
    // bar / control center glyph (mock icon set)
    readonly property string glyph: wired ? "lan" : !wifiEnabled ? "wifiOff" : !active ? "wifi0" : glyphFor(active)
    // Material Symbols name (legacy callers)
    readonly property string icon: wired ? "lan" : !wifiEnabled ? "wifi_off" : !active ? "signal_wifi_0_bar"
        : strength > 0.75 ? "network_wifi" : strength > 0.5 ? "network_wifi_3_bar" : strength > 0.25 ? "network_wifi_2_bar" : "network_wifi_1_bar"

    // one entry per SSID (NM can list the same SSID per BSSID), best signal first
    readonly property var unique: {
        const best = {};
        for (const n of networks) {
            if (!n.name) continue;
            const b = best[n.name];
            if (!b || n.connected || (!b.connected && level(n) > level(b))) best[n.name] = n;
        }
        return Object.values(best).sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (level(b) - level(a)));
    }
    readonly property var knownList: unique.filter(n => n.connected || n.known)
    readonly property var otherList: unique.filter(n => !n.connected && !n.known)

    function setWifi(on) { Networking.wifiEnabled = on; }
    // scanning only while a UI that lists networks is open
    function setScanning(on) { if (wifiDevice) wifiDevice.scannerEnabled = on; }
    function failText(reason) {
        switch (reason) {
        case ConnectionFailReason.NoSecrets: return "Password required";
        case ConnectionFailReason.WifiAuthTimeout: return "Wrong password or no answer";
        case ConnectionFailReason.WifiNetworkLost: return "Network lost";
        case ConnectionFailReason.WifiClientDisconnected: return "Disconnected";
        default: return "Couldn't connect";
        }
    }
}

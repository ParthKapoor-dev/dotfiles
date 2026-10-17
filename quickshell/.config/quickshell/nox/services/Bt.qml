pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth helpers over native BlueZ bindings (Quickshell.Bluetooth).
Singleton {
    id: root
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter?.enabled ?? false
    readonly property var paired: Bluetooth.devices.values.filter(d => d.paired || d.bonded || d.trusted || d.connected)
    readonly property var connected: paired.filter(d => d.connected)
    readonly property string glyph: !enabled ? "btOff" : "bt"
    function setEnabled(on) { if (adapter) adapter.enabled = on; }
    function glyphFor(d) {
        const i = (d?.icon ?? "").toLowerCase();
        return i.includes("headset") || i.includes("headphone") || i.includes("audio") ? "headphones"
            : i.includes("phone") ? "phone"
            : i.includes("mouse") ? "mouse"
            : i.includes("keyboard") ? "keyboard"
            : i.includes("computer") ? "laptop" : "bt";
    }
    function nameOf(d) { return d?.name || d?.deviceName || "Device"; }
    function status(d) {
        if (d.state === BluetoothDeviceState.Connecting) return "Connecting…";
        if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…";
        if (!d.connected) return "Not connected";
        return "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "");
    }
}

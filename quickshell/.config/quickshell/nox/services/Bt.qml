pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.core

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
    // bond lost on the device's side: BlueZ still trusts it but the headset dropped our link key
    // (JBL multipoint evicts it when a phone takes over), so every connect fails with
    // br-connection-key-missing. Only a re-pair helps; `repair` runs fix-jbl for it in a terminal.
    function needsRepair(d) { return !!d && d.trusted && !d.paired && !d.bonded && !d.connected; }
    function repair(d) {
        const term = Config.opt.terminal ?? ["ghostty"];
        Quickshell.execDetached(term.concat(["-e", "sh", "-c",
            "echo 'Put the headset in pairing mode: phone Bluetooth off, hold power ~5 s until the LED blinks fast.'; echo; " +
            "fix-jbl \"$1\"; echo; printf 'Press Enter to close '; read _", "sh", d.address]));
    }
    // click in a device list: re-pair a lost bond, else toggle the connection
    function activate(d) {
        if (needsRepair(d)) repair(d);
        else if (d.connected) d.disconnect();
        else d.connect();
    }
    function status(d) {
        if (d.state === BluetoothDeviceState.Connecting) return "Connecting…";
        if (d.state === BluetoothDeviceState.Disconnecting) return "Disconnecting…";
        if (needsRepair(d)) return "Pairing lost · click to re-pair";
        if (!d.connected) return "Not connected";
        return "Connected" + (d.batteryAvailable ? " · " + Math.round(d.battery * 100) + "%" : "");
    }
}

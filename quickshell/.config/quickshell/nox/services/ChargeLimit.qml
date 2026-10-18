pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Battery protection (battery popover row, CC tile "chargeLimit", launcher command, action
// "chargeLimit"): cap charging at 80% / full charge for travel. Everything goes through
// `nox battery` (upowerd's EnableChargeThreshold over D-Bus, no sudo; on/off persists in upowerd).
// State = `nox battery status --json`, re-read at start, after a change, when the battery popover
// or the Control Center opens, and on IPC `chargeLimit refresh` (the CLI pokes it).
// At start it also runs `nox battery reapply -q` (firmware lost the value = re-send it).
Singleton {
    id: root
    property bool supported: false
    property bool on: false              // protection enabled (UPower)
    property int cap: 80                 // UPower's end threshold
    property int applied: 0              // what the firmware has (sysfs)
    property bool ok: true               // applied matches the setting
    property bool busy: false
    readonly property string label: on ? "Charging stops at " + cap + "%" : "Charges to 100%"

    // `nox` lives in ~/.local/bin, which may not be on the shell's PATH
    function nox(args) { return ["sh", "-c", "if command -v nox >/dev/null 2>&1; then exec nox \"$@\"; else exec \"$HOME/.local/bin/nox\" \"$@\"; fi", "sh"].concat(args); }
    function refresh() { if (!status.running) status.running = true; }
    function toggle() { set(!on); }
    function set(v) {
        if (!supported || busy) return;
        busy = true;
        change.command = nox(["battery", v ? "protect" : "full"]);
        change.running = true;
        Panels.hud(v ? "Battery protection · " + cap + "%" : "Full charge · 100%", v ? "leaf" : "bolt");
    }

    Process {
        id: status
        command: root.nox(["battery", "status", "--json"])
        stdout: StdioCollector {
            onStreamFinished: {
                let s = null;
                try { s = JSON.parse(text); } catch (e) { return; }
                root.supported = s.supported; root.on = s.enabled; root.cap = s.cap;
                root.applied = s.applied; root.ok = s.ok;
            }
        }
    }
    Process {
        id: change
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("nox battery:", text.trim()) }
        onExited: { root.busy = false; root.refresh(); }
    }
    Process {
        running: true
        command: root.nox(["battery", "reapply", "-q"])
        onExited: root.refresh()
    }
    Connections {
        target: Panels
        function onPopupChanged() { if (Panels.popup === "bar:battery" || Panels.popup === "controlCenter") root.refresh(); }
    }
    IpcHandler {
        target: "chargeLimit"
        function refresh(): void { root.refresh(); }
        function toggle(): void { root.toggle(); }
        function status(): string { return "supported=" + root.supported + " on=" + root.on + " cap=" + root.cap + " applied=" + root.applied + " ok=" + root.ok; }
    }
}

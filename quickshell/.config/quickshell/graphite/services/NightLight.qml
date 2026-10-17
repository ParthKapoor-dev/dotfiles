pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Night Light (Control Center tile, launcher command, action "nightLight"): hyprsunset (Hyprland's
// CTM protocol). shell.json nightLight.temperature (default 4500 K).
// - If a hyprsunset daemon already runs (user service / exec-once), it's driven over its IPC:
//   `hyprctl hyprsunset temperature <K>` / `hyprctl hyprsunset identity` (a second hyprsunset
//   couldn't bind the CTM manager and exited at once, so the tile looked dead).
// - Otherwise the shell runs `hyprsunset -t <K>` while on; stopping it restores the colours.
// The state of an external daemon is read once at start (and after each change).
Singleton {
    id: root
    readonly property int temperature: Config.opt.nightLight?.temperature ?? 4500
    property bool externalOn: false        // an external daemon is warming the screen
    property bool external: false          // an external daemon answers on its socket
    readonly property bool on: proc.running || externalOn

    function toggle() { set(!on); }
    function set(v) {
        v = !!v;
        if (v === on) return;
        if (proc.running) { if (!v) proc.running = false; return; }
        if (external) {
            ipc.command = ["hyprctl", "hyprsunset"].concat(v ? ["temperature", String(temperature)] : ["identity"]);
            ipc.running = true;
            externalOn = v;
            return;
        }
        proc.running = v;
    }

    Process {
        id: proc
        command: ["hyprsunset", "-t", String(root.temperature)]
    }
    Process { id: ipc; onExited: probe.running = true }
    // is a hyprsunset daemon (not ours) already running? `temperature` prints the current K
    Process {
        id: probe
        running: true
        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (proc.running) return;
                const k = parseInt(text.trim());
                root.external = isFinite(k) && k > 0;
                root.externalOn = root.external && k < 6000;
            }
        }
    }
}

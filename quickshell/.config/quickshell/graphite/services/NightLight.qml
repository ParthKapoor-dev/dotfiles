pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Night Light (Control Center tile): runs `hyprsunset -t <temperature>` while on.
// shell.json nightLight.temperature (default 4500).
Singleton {
    id: root
    readonly property bool on: proc.running
    function toggle() { proc.running = !proc.running; }
    function set(v) { proc.running = !!v; }
    Process {
        id: proc
        command: ["hyprsunset", "-t", String(Config.opt.nightLight?.temperature ?? 4500)]
    }
}

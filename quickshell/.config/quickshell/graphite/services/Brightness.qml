pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Laptop backlight. Reads sysfs directly (no polling process); writes through brightnessctl
// (it uses logind, so no udev rules or root needed). Device: shell.json brightness.device,
// "auto" = first backlight brightnessctl reports. External DDC monitors are not handled.
Singleton {
    id: root

    property string device: ""
    property int maxRaw: 0
    property int raw: 0
    readonly property bool available: device !== "" && maxRaw > 0
    readonly property real value: available ? raw / maxRaw : 0   // 0..1
    readonly property string configured: Config.opt.brightness?.device ?? "auto"

    function refresh() { if (available) cur.reload(); }

    // value 0..1; coalesced so a dragging slider spawns at most ~20 processes/s
    function set(v) {
        if (!available) return;
        const pct = Math.round(Math.max(0.01, Math.min(1, v)) * 100);
        raw = Math.round(pct / 100 * maxRaw);
        pending = pct;
        if (!throttle.running) { apply(); throttle.start(); }
    }
    function step(dir) { set(value + dir * (Config.opt.brightness?.step ?? 5) / 100); }

    property int pending: -1
    function apply() {
        if (pending < 0) return;
        Quickshell.execDetached(["brightnessctl", "-q", "-d", device, "set", pending + "%"]);
        pending = -1;
    }
    Timer { id: throttle; interval: 50; onTriggered: root.apply() }

    onConfiguredChanged: detect.running = true
    Component.onCompleted: detect.running = true

    // One-shot detection: "name,class,current,percent,max"
    Process {
        id: detect
        command: root.configured === "auto" ? ["brightnessctl", "-m", "-c", "backlight", "info"] : ["brightnessctl", "-m", "-d", root.configured, "info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("\n")[0]?.split(",") ?? [];
                if (f.length >= 5) { root.device = f[0]; root.maxRaw = parseInt(f[4]); root.raw = parseInt(f[2]); }
            }
        }
    }

    FileView {
        id: cur
        path: root.device ? "/sys/class/backlight/" + root.device + "/brightness" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { const n = parseInt(text()); if (!isNaN(n)) root.raw = n; }
    }
}

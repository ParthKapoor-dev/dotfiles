pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// CPU / memory / temperature / network sampling for the bar "stats" widget. Reads procfs/sysfs
// with FileView every shell.json stats.interval ms (default 2000): /proc/stat, /proc/meminfo,
// /proc/loadavg, /proc/net/dev and one thermal zone. No processes. The singleton only exists once
// something reads it (the widget), and `active` stops the timer when nothing wants samples.
// stats.thermalZone: "auto" (x86_pkg_temp > TCPU > k10temp/coretemp-like > acpitz) or a zone
// number. Top processes (`ps`) live in the widget's popover and only run while it is open.
Singleton {
    id: root
    readonly property var opts: Config.opt.stats ?? ({})
    readonly property int interval: Math.max(500, opts.interval ?? 2000)
    property bool active: true

    property real cpu: 0              // 0..1 over the last interval
    property var cpuHistory: []       // last 30 samples (0..1), oldest first
    property int cores: 0
    property real memTotal: 0         // KiB
    property real memUsed: 0          // KiB (MemTotal - MemAvailable)
    readonly property real mem: memTotal > 0 ? memUsed / memTotal : 0
    property real swapTotal: 0
    property real swapUsed: 0
    property real temp: -1            // °C, -1 = unknown
    property string tempSensor: ""
    property var load: [0, 0, 0]
    property real rxRate: 0           // bytes/s, all non-loopback interfaces
    property real txRate: 0

    property var prevCpu: null
    property var prevNet: null

    function fmtBytes(kib) {
        const g = kib / 1048576;
        return g >= 1 ? g.toFixed(g >= 10 ? 0 : 1) + " GB" : Math.round(kib / 1024) + " MB";
    }
    function fmtRate(b) {
        if (b >= 1048576) return (b / 1048576).toFixed(1) + " MB/s";
        if (b >= 1024) return Math.round(b / 1024) + " KB/s";
        return Math.round(b) + " B/s";
    }

    function sample() {
        stat.reload(); meminfo.reload(); loadavg.reload(); netdev.reload();
        if (thermal.path) thermal.reload();
    }
    Timer {
        running: root.active
        interval: root.interval
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    FileView {
        id: stat
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            const lines = text().split("\n");
            const f = lines[0].trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] || 0), total = f.slice(0, 8).reduce((a, b) => a + b, 0);
            if (root.prevCpu) {
                const dt = total - root.prevCpu.total, di = idle - root.prevCpu.idle;
                root.cpu = dt > 0 ? Math.max(0, Math.min(1, 1 - di / dt)) : 0;
                root.cpuHistory = root.cpuHistory.concat([root.cpu]).slice(-30);
            }
            root.prevCpu = { total, idle };
            if (!root.cores) root.cores = lines.filter(l => /^cpu\d/.test(l)).length;
        }
    }
    FileView {
        id: meminfo
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            const m = {};
            for (const l of text().split("\n")) {
                const r = l.match(/^(\w+):\s+(\d+)/);
                if (r) m[r[1]] = Number(r[2]);
            }
            root.memTotal = m.MemTotal ?? 0;
            root.memUsed = (m.MemTotal ?? 0) - (m.MemAvailable ?? m.MemFree ?? 0);
            root.swapTotal = m.SwapTotal ?? 0;
            root.swapUsed = (m.SwapTotal ?? 0) - (m.SwapFree ?? 0);
        }
    }
    FileView {
        id: loadavg
        path: "/proc/loadavg"
        printErrors: false
        onLoaded: root.load = text().trim().split(/\s+/).slice(0, 3).map(Number)
    }
    FileView {
        id: netdev
        path: "/proc/net/dev"
        printErrors: false
        onLoaded: {
            let rx = 0, tx = 0;
            for (const l of text().split("\n").slice(2)) {
                const r = l.trim().match(/^([^:]+):\s*(.*)$/);
                if (!r || r[1] === "lo") continue;
                const f = r[2].split(/\s+/).map(Number);
                rx += f[0]; tx += f[8];
            }
            const now = Date.now();
            if (root.prevNet) {
                const dt = (now - root.prevNet.at) / 1000;
                if (dt > 0) { root.rxRate = Math.max(0, (rx - root.prevNet.rx) / dt); root.txRate = Math.max(0, (tx - root.prevNet.tx) / dt); }
            }
            root.prevNet = { rx, tx, at: now };
        }
    }

    // thermal zone: stats.thermalZone = "auto" (best CPU sensor), a sensor type such as
    // "x86_pkg_temp" (what `nox detect` writes: zone numbers can change between boots) or a zone
    // number. Every zone's `type` is read once unless a number is given.
    readonly property var zonePrefs: ["x86_pkg_temp", "TCPU", "k10temp", "cpu_thermal", "cpu-thermal", "soc_thermal", "acpitz"]
    property var zoneTypes: ({})
    readonly property string zoneWant: String(opts.thermalZone ?? "auto")
    readonly property bool zoneByNumber: /^[0-9]+$/.test(zoneWant)
    readonly property string zone: {
        if (zoneByNumber) return "/sys/class/thermal/thermal_zone" + zoneWant;
        const prefs = zoneWant === "auto" ? zonePrefs : [zoneWant].concat(zonePrefs);
        for (const p of prefs) for (const z in zoneTypes) if (zoneTypes[z] === p) return "/sys/class/thermal/thermal_zone" + z;
        return "";
    }
    Instantiator {
        model: root.zoneByNumber ? 0 : 16
        FileView {
            required property int index
            path: "/sys/class/thermal/thermal_zone" + index + "/type"
            printErrors: false
            onLoaded: root.zoneTypes = Object.assign({}, root.zoneTypes, { [index]: text().trim() })
        }
    }
    FileView {
        id: thermal
        path: root.zone ? root.zone + "/temp" : ""
        printErrors: false
        onLoaded: {
            const v = Number(text().trim());
            root.temp = isFinite(v) && v > 0 ? v / 1000 : -1;
            const z = root.zone.replace(/.*thermal_zone/, "");
            root.tempSensor = root.zoneTypes[z] ?? ("zone " + z);
        }
    }
}

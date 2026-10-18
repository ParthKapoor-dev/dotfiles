pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Phone link over the lightweight KDE Connect daemon kdeconnect-rs (cosmic-utils/kdeconnect,
// `kdeconnect-service`, user unit kdeconnect-rs.service; works with the official KDE Connect
// phone app). Quickshell has no generic D-Bus client, so:
//   - one long-lived `busctl monitor` (JSON lines) watches the daemon's bus name, its signals
//     (DeviceConnected/Paired/Disconnected, BatteryReceived, ClipboardReceived, PairingRequested)
//     and the daemon's own "Text received from phone" notifications (shared text -> clipboard);
//   - one-shot `busctl call`s for ListDevices / actions.
// Nothing runs while the daemon is down except that monitor (it just waits for the name).
// The bar widget, launcher provider and `nox phone` all sit on top of this / the same calls.
// shell.json phone.device = name or id of the preferred device (default: first paired one).
Singleton {
    id: root

    readonly property string busName: "io.github.hepp3n.kdeconnect"
    readonly property string objPath: "/io/github/hepp3n/kdeconnect/Daemon"
    readonly property string iface: "io.github.hepp3n.kdeconnect.Daemon"
    readonly property string unit: "kdeconnect-rs.service"

    property bool available: false          // daemon owns its bus name
    property var devices: []                // [{ id, name, type, paired, reachable }]
    property var battery: ({})              // id -> { level, charging }
    property var pairRequest: null          // { id, name } while a phone waits for an answer

    readonly property var paired: devices.filter(d => d.paired)
    readonly property var device: {
        const want = Config.opt.phone?.device ?? "";
        const p = paired.filter(d => !want || d.id === want || d.name === want);
        return p.find(d => d.reachable) ?? p[0] ?? null;
    }
    readonly property bool connected: device?.reachable ?? false
    readonly property var deviceBattery: device ? (battery[device.id] ?? null) : null
    readonly property var unpaired: devices.filter(d => !d.paired && d.reachable)

    function call(method, sig, ...args) {
        return ["busctl", "--user", "call", busName, objPath, iface, method].concat(sig ? [sig] : [], args.map(String));
    }
    function need() {
        if (!available) { Panels.hud("Phone link is off", "phone"); return false; }
        if (!device) { Panels.hud("No paired phone", "phone"); return false; }
        if (!connected) { Panels.hud(device.name + " is not reachable", "phone"); return false; }
        return true;
    }

    function refresh() { if (available && !lister.running) lister.running = true; }
    function ring() { if (need()) { Quickshell.execDetached(call("RingDevice", "s", device.id)); Panels.hud("Ringing " + device.name, "bell"); } }
    function ping() { if (need()) Quickshell.execDetached(call("SendPing", "ss", device.id, "Ping from nox")); }
    function sendClipboard() { if (need()) Quickshell.execDetached(["nox", "phone", "--notify", "clip"]); }
    function sendFiles(files) { if (need()) Quickshell.execDetached(call("SendFiles", "as", device.id, files.length, ...files)); }
    // file picker (fuzzel) lives in the CLI so the keybind, launcher and terminal share it
    function pickAndSend() { if (need()) Quickshell.execDetached(["nox", "phone", "--notify", "send"]); }
    function pair() { Quickshell.execDetached(["nox", "phone", "--notify", "pair"]); }
    function answerPair(accept) {
        if (!pairRequest) return;
        Quickshell.execDetached(call(accept ? "AcceptPairing" : "RejectPairing", "s", pairRequest.id));
        Panels.hud(accept ? "Paired with " + pairRequest.name : "Pairing declined", accept ? "check" : "x");
        pairRequest = null;
        Qt.callLater(refresh);
    }
    function start() { Quickshell.execDetached(["systemctl", "--user", "start", unit]); }
    function stop() { Quickshell.execDetached(["systemctl", "--user", "stop", unit]); }

    // qs -c nox ipc call phone <fn>  (nox phone status shows `status`)
    IpcHandler {
        target: "phone"
        function status(): string {
            if (!root.available) return "daemon not running";
            if (!root.device) return "no paired phone";
            const b = root.deviceBattery;
            return root.device.name + (root.connected ? " · connected" : " · offline")
                + (b ? " · battery " + b.level + "%" + (b.charging ? " (charging)" : "") : "");
        }
        function ring(): void { root.ring(); }
        function clip(): void { root.sendClipboard(); }
        function send(): void { root.pickAndSend(); }
        function pair(): void { root.pair(); }
        function accept(): void { root.answerPair(true); }
        function refresh(): void { root.refresh(); }
    }

    // ---- state ----
    function onSignal(m) {
        const d = m.payload?.data ?? [];
        switch (m.member) {
        case "NameOwnerChanged":
            if (d[0] !== busName) return;
            available = d[2] !== "";
            if (available) refreshSoon.restart(); else { devices = []; battery = ({}); pairRequest = null; }
            return;
        case "DeviceConnected": case "DevicePaired": case "DeviceDisconnected":
            refreshSoon.restart();
            return;
        case "BatteryReceived": {
            const b = Object.assign({}, battery);
            b[d[0]] = { level: d[1], charging: d[2] };
            battery = b;
            return;
        }
        case "ClipboardReceived":     // the daemon already put it on the clipboard
            Panels.hud("Clipboard from phone", "clip");
            return;
        case "PairingRequested":
            pairRequest = { id: d[0], name: d[1] };
            pairPrompt.ask(d[1]);
            return;
        case "Notify":                // daemon's own notification for a shared text / unopened URL
            if (d[0] === "KDE Connect" && /^(Text|URL) received from phone$/.test(d[3] ?? "") && d[4]) {
                Quickshell.execDetached(["wl-copy", "--", d[4]]);
                Panels.hud("Phone text copied", "clip");
            }
            return;
        }
    }

    Process {
        id: monitor
        running: true
        command: ["busctl", "--user", "monitor", "--json=short",
            "--match", "type='signal',member='NameOwnerChanged',arg0='" + root.busName + "'",   // (sender= + arg0= together never matches under busctl monitor)
            "--match", "type='signal',interface='" + root.iface + "'",
            "--match", "type='method_call',interface='org.freedesktop.Notifications',member='Notify',arg0='KDE Connect'"]
        stdout: SplitParser {
            onRead: line => {
                if (line[0] !== "{") return;
                try { root.onSignal(JSON.parse(line)); } catch (e) { console.warn("nox phone: bad monitor line", e); }
            }
        }
        onExited: monitorRetry.start()
    }
    Timer { id: monitorRetry; interval: 5000; onTriggered: monitor.running = true }

    // initial: is the daemon already up?
    Process {
        running: true
        command: ["busctl", "--user", "status", root.busName]
        onExited: code => { root.available = code === 0; if (root.available) root.refresh(); }
    }
    Timer { id: refreshSoon; interval: 400; onTriggered: root.refresh() }

    Process {
        id: lister
        command: root.call("ListDevices", "").concat(["--json=short"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const rows = JSON.parse(text).data?.[0] ?? [];
                    root.devices = rows.map(r => ({ id: r[0], name: r[1], type: r[2], paired: r[3], reachable: r[4] }));
                } catch (e) { root.devices = []; }
            }
        }
    }

    // incoming pair request: actionable notification (Accept / Decline)
    Process {
        id: pairPrompt
        property string who: ""
        function ask(name) {
            who = name;
            running = false;
            command = ["notify-send", "-a", "Phone", "-i", "phone", "-u", "critical", "-w", "-t", "30000",
                "-A", "accept=Accept", "-A", "reject=Decline",
                "Pair with " + name + "?", "The phone is asking to pair. Check that the key shown on the phone matches, then accept."];
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const a = text.trim();
                if (a === "accept") root.answerPair(true);
                else if (a === "reject") root.answerPair(false);
            }
        }
    }
}

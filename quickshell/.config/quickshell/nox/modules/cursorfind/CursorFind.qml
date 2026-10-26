pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core

// Shake to find the cursor: shake the pointer and a big accent ring with a soft glow blooms
// around it, grows and fades over 600 ms. The cursor theme is left alone (`hyprctl setcursor`
// reloads the theme and can flicker).
// Detection runs inside Hyprland, not here: Hyprland 0.56 gives Lua no pointer-motion event, and
// polling cursorpos over the socket from the shell would wake it 30 times a second for ever. So
// this module sends detector.lua with `hyprctl eval` (again after every config reload, which
// recreates Hyprland's Lua state) and the compositor samples hl.get_cursor_pos() in-process: 2 Hz
// while the pointer rests, 1000/hz while it moves. A shake comes back as the socket2 event
// custom>>nox-cursorfind <x> <y>, so the shell does nothing until then. While the ring is up it
// follows the pointer by asking j/cursorpos at 60 Hz (a 700 ms burst per shake).
// The ring is one full-screen overlay (namespace nox:cursorfind, no input, no keyboard) that only
// exists while it plays.
// shell.json cursorFind { enabled (false), hz (30), travel (600 px), reversals (3),
//   windowMs (400), cooldownMs (1000), size (ring diameter at its widest, 220) }
// qs -c nox ipc call cursorfind show   (play it at the pointer, for testing / a keybind)
Scope {
    id: root
    readonly property var opts: Config.opt.cursorFind ?? ({})
    readonly property bool enabled: opts.enabled === true
    readonly property real ringSize: opts.size ?? 220
    readonly property int playMs: 600

    // ---- the detector in Hyprland ----
    // a Lua table literal of the numeric options (anything else is dropped)
    function luaCfg() {
        const keys = ["hz", "travel", "reversals", "windowMs", "cooldownMs"];
        return "{ " + keys.filter(k => typeof opts[k] === "number" && isFinite(opts[k]))
            .map(k => k + " = " + opts[k]).join(", ") + " }";
    }
    readonly property string detectorPath: decodeURIComponent(Qt.resolvedUrl("detector.lua").toString().replace(/^file:\/\//, ""))
    FileView { id: detector; path: root.detectorPath; blockLoading: true }
    function install() {
        if (!enabled) { uninstall(); return; }
        const src = detector.text();
        if (!src) return;
        // leading newline: hyprctl would take an argument starting with "--" (the Lua comment) as a flag
        Quickshell.execDetached(["hyprctl", "-q", "eval", "\n" + src + "\nNOX_CURSORFIND.start(" + luaCfg() + ")"]);
    }
    function uninstall() {
        Quickshell.execDetached(["hyprctl", "-q", "eval", "if NOX_CURSORFIND then NOX_CURSORFIND.stop() end"]);
    }
    Component.onCompleted: install()
    Component.onDestruction: uninstall()
    onEnabledChanged: install()
    // live config edits (hz, travel...) restart it with the new numbers; debounced, since a
    // shell.json save arrives as a few change signals
    onOptsChanged: if (enabled) reinstall.restart()
    Timer { id: reinstall; interval: 300; onTriggered: root.install() }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") { if (root.enabled) reinstall.restart(); return; }
            if (event.name !== "custom" || !event.data.startsWith("nox-cursorfind ")) return;
            const p = event.data.split(" ");
            root.play(Number(p[1]), Number(p[2]));
        }
    }

    IpcHandler {
        target: "cursorfind"
        function show(): void { root.pendingPlay = true; root.query(); }
        function status(): string { return root.enabled ? "on" : "off"; }
    }

    // ---- the ring ----
    property bool shown: false
    property string screenName: ""
    property real px: 0                 // pointer, global layout px
    property real py: 0
    property real ox: 0                 // that screen's origin in the layout
    property real oy: 0
    property int gen: 0                 // bumped per play: the ring restarts its animation
    function screenAt(x, y) {
        return Quickshell.screens.find(s => x >= s.x && x < s.x + s.width && y >= s.y && y < s.y + s.height) ?? null;
    }
    function play(x, y) {
        if (!isFinite(x) || !isFinite(y)) return;
        const s = screenAt(x, y);
        if (!s) return;
        screenName = s.name;
        ox = s.x; oy = s.y;
        px = x; py = y;
        gen++;
        shown = true;
        endTimer.restart();
        follow.start();
    }
    Timer { id: endTimer; interval: root.playMs + 100; onTriggered: { follow.stop(); root.shown = false; } }

    // pointer position over Hyprland's request socket (write j/cursorpos, read the JSON; it
    // closes after a reply, so we close first)
    property bool pendingPlay: false    // IPC show: play once the position is known
    property string reply: ""
    Timer { id: follow; interval: 16; repeat: true; onTriggered: root.query() }
    Socket {
        id: sock
        path: Hyprland.requestSocketPath
        onConnectedChanged: {
            if (!connected) return;
            root.reply = "";
            write("j/cursorpos");
            flush();
        }
        parser: SplitParser {
            splitMarker: ""
            onRead: data => {
                root.reply += data;
                let p = null;
                try { p = JSON.parse(root.reply); } catch (e) { return; }
                sock.connected = false;
                root.reply = "";
                if (!p || typeof p.x !== "number" || typeof p.y !== "number") return;
                if (root.pendingPlay) { root.pendingPlay = false; root.play(p.x, p.y); }
                else if (root.shown && root.screenAt(p.x, p.y)?.name === root.screenName) { root.px = p.x; root.py = p.y; }
            }
        }
    }
    function query() {
        if (sock.connected || sock.path === "") return;      // the last one has not answered yet
        sock.connected = true;
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? null
            WlrLayershell.namespace: "nox:cursorfind"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"
            mask: Region {}

            CursorRing {
                id: ring
                diameter: root.ringSize
                duration: root.playMs
                cx: root.px - root.ox
                cy: root.py - root.oy
                Component.onCompleted: ring.start()
                Connections { target: root; function onGenChanged() { ring.start(); } }
            }
        }
    }
}

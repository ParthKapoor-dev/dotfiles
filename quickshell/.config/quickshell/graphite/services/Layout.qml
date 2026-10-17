pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Current Hyprland tiling layout. Read once at start (`hyprctl -j getoption general:layout`);
// afterwards the `graphite-layout` helper (Hyprland side) reports every change through
// `qs -c graphite ipc call layout changed <name>` (IpcHandler in shell.qml), so nothing polls.
Singleton {
    id: root
    property string name: ""
    readonly property var labels: ({ dwindle: "Tiling", master: "Master", scrolling: "Scrolling", monocle: "Monocle", floating: "Floating" })
    readonly property var glyphs: ({ dwindle: "dwindle", master: "master", scrolling: "scrolling", monocle: "monocle", floating: "floating" })
    readonly property string label: labels[name] ?? (name ? name.charAt(0).toUpperCase() + name.slice(1) : "")
    readonly property string glyph: glyphs[name] ?? "layout"

    function changed(n) { if (n) root.name = String(n).trim(); }
    function next() { Quickshell.execDetached(["graphite-layout", "next"]); }
    function prev() { Quickshell.execDetached(["graphite-layout", "prev"]); }
    function set(n) { Quickshell.execDetached(["graphite-layout", "set", n]); }
    function refresh() { reader.running = true; }

    Process {
        id: reader
        running: true
        command: ["hyprctl", "-j", "getoption", "general:layout"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.changed(JSON.parse(text).str); } catch (e) {} }
        }
    }
}

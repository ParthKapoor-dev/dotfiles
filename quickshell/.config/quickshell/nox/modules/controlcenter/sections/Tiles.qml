pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Bottom row of square tiles (mock: Screenshot, Record, Dark Mode, Lock).
// controlCenter.tiles picks them in order: screenshot | record | look | lock | nightLight | caffeine
// ("darkMode" = old id of "look").
// Look replaces the mock's "Dark Mode (locked)": the shell is dark-only, so a tile that can never
// change was dead weight. It shows the current look and switches to the next one in
// controlCenter.looks (presets for `theme switch`; "default" = the base Ember tokens).
Item {
    id: root
    readonly property var ids: Config.opt.controlCenter?.tiles ?? ["screenshot", "record", "look", "lock"]
    readonly property var looks: Config.opt.controlCenter?.looks ?? ["default", "telemetry"]
    readonly property real col: (width - 30) / 4
    implicitHeight: 76

    // tokens name of a preset ("default" = base tokens, named "ember")
    function lookName(p) { return p === "default" ? "ember" : p; }
    readonly property string currentLook: Theme.t.name ?? "ember"
    readonly property string nextLook: {
        const i = looks.findIndex(p => lookName(p) === currentLook);
        return looks[(i + 1) % looks.length] ?? "default";
    }
    function title(s) { return s.split(/[-_ ]/).map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" "); }
    function switchLook() {
        Panels.hud("Look: " + title(lookName(nextLook)), "sparkle");
        // `theme` lives in ~/.local/bin, which may not be on the shell's PATH
        Quickshell.execDetached(["sh", "-c", "if command -v theme >/dev/null 2>&1; then exec theme switch \"$1\"; else exec \"$HOME/.local/bin/theme\" switch \"$1\"; fi", "sh", nextLook]);
    }

    readonly property var defs: ({
        screenshot: { icon: "shot", name: "Screenshot", on: () => false, act: () => { Panels.close(); Actions.run("screenshot"); } },
        record: { icon: "record", name: "Record", sub: () => Recorder.recording ? "Recording" : "", on: () => Recorder.recording, act: () => { Panels.close(); Recorder.toggle(); } },
        look: { icon: "sparkle", name: "Look", sub: () => root.title(root.currentLook), on: () => false, act: () => root.switchLook() },
        lock: { icon: "lock", name: "Lock", on: () => false, act: () => { Panels.close(); Actions.run("lock"); } },
        nightLight: { icon: "sunset", name: "Night Light", on: () => NightLight.on, act: () => NightLight.toggle() },
        caffeine: { icon: "coffee", name: "Caffeine", on: () => Panels.caffeine, act: () => { Panels.caffeine = !Panels.caffeine; } }
    })
    Row {
        spacing: 10
        Repeater {
            model: root.ids.map(i => i === "darkMode" ? "look" : i).filter(i => root.defs[i])
            ControlTile {
                required property string modelData
                readonly property var d: root.defs[modelData]
                width: root.col; height: 76
                icon: d.icon; name: d.name; sub: d.sub ? d.sub() : ""
                on: d.on()
                onClicked: d.act()
            }
        }
    }
}

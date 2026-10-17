pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Bottom row of square tiles (mock: Screenshot, Record, Dark Mode (locked), Lock).
// controlCenter.tiles picks them in order: screenshot | record | darkMode | lock | nightLight | caffeine
Item {
    id: root
    readonly property var ids: Config.opt.controlCenter?.tiles ?? ["screenshot", "record", "darkMode", "lock"]
    readonly property real col: (width - 30) / 4
    implicitHeight: 76
    readonly property var defs: ({
        screenshot: { icon: "shot", name: "Screenshot", on: () => false, act: () => { Panels.close(); Actions.run("screenshot"); } },
        record: { icon: "record", name: Recorder.recording ? "Stop" : "Record", on: () => Recorder.recording, act: () => { Panels.close(); Recorder.toggle(); } },
        darkMode: { icon: "moonF", name: "Dark Mode", sub: "locked", on: () => true, locked: true, act: () => {} },
        lock: { icon: "lock", name: "Lock", on: () => false, act: () => { Panels.close(); Actions.run("lock"); } },
        nightLight: { icon: "sunset", name: "Night Light", on: () => NightLight.on, act: () => NightLight.toggle() },
        caffeine: { icon: "coffee", name: "Caffeine", on: () => Panels.caffeine, act: () => { Panels.caffeine = !Panels.caffeine; } }
    })
    Row {
        spacing: 10
        Repeater {
            model: root.ids.filter(i => root.defs[i])
            ControlTile {
                required property string modelData
                readonly property var d: root.defs[modelData]
                width: root.col; height: 76
                icon: d.icon; name: d.name; sub: d.sub ?? ""
                on: d.on(); locked: d.locked ?? false
                onClicked: d.act()
            }
        }
    }
}

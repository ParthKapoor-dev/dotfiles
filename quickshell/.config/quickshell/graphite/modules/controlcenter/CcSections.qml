pragma Singleton
import QtQuick
import Quickshell

// Control Center section registry: id (shell.json controlCenter.sections) -> file in sections/.
// Add a section = one QML file + one line here.
Singleton {
    readonly property var registry: ({
        "connectivity": "Connectivity.qml",
        "display": "Display.qml",
        "sound": "Sound.qml",
        "media": "Media.qml"
    })
    function url(id) {
        const f = registry[id];
        if (!f) { console.warn("graphite: unknown control center section id:", id); return ""; }
        return Qt.resolvedUrl("sections/" + f);
    }
}

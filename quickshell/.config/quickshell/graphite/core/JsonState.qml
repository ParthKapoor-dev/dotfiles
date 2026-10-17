import QtQuick
import Quickshell
import Quickshell.Io

// A small persisted JSON object for runtime state (not config), e.g. ~/.local/state/graphite/launcher.json.
// Usage: JsonState { id: s; path: Paths.state("launcher") }  ...  s.data = newObject; s.save();
// save() is debounced; the directory is created once (one short `mkdir -p`) before the first write.
Scope {
    id: root
    required property string path
    property var data: ({})
    property bool loaded: false
    property int saveDelay: 400

    readonly property string dir: path.substring(0, path.lastIndexOf("/"))
    property bool dirReady: false

    function save() { saveTimer.restart(); }
    function flush() {
        if (!dirReady) { if (!mkdir.running) mkdir.running = true; return; }
        file.setText(JSON.stringify(root.data) + "\n");
    }

    Timer { id: saveTimer; interval: root.saveDelay; onTriggered: root.flush() }

    Process {
        id: mkdir
        command: ["mkdir", "-p", root.dir]
        onExited: (code, status) => {
            if (code !== 0) { console.warn("graphite: could not create state dir", root.dir); return; }
            root.dirReady = true;
            root.flush();
        }
    }

    FileView {
        id: file
        path: root.path
        blockLoading: true
        printErrors: false
        onLoaded: {
            root.dirReady = true;
            try { root.data = JSON.parse(text()) ?? {}; }
            catch (e) { console.warn("graphite: state file unreadable, starting fresh:", root.path); }
            root.loaded = true;
        }
        onLoadFailed: root.loaded = true   // missing file = empty state
    }
}

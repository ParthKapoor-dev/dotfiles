pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Screen recording (Control Center "Record" tile, bar `recording` indicator).
// Region via slurp, wf-recorder writes ~/Videos/Recording_<date>.mp4; stopping sends SIGINT so the
// file is finalised. Only runs while recording. shell.json recorder.{directory, args}
Singleton {
    id: root
    readonly property bool recording: proc.running
    property real startedAt: 0
    property string file: ""

    function toggle() { recording ? stop() : start(); }
    function start() {
        if (proc.running) return;
        const dir = (Config.opt.recorder?.directory ?? "").replace(/^~/, Quickshell.env("HOME")) || (Quickshell.env("HOME") + "/Videos");
        file = dir + "/Recording_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH.mm.ss") + ".mp4";
        const extra = (Config.opt.recorder?.args ?? []).map(a => "'" + String(a).replace(/'/g, "'\\''") + "'").join(" ");
        // $1 = file, $2 = dir (passed as arguments, never interpolated)
        proc.command = ["sh", "-c", "sleep 0.3; mkdir -p \"$2\" && g=$(slurp) || exit 1; exec wf-recorder " + extra + " -g \"$g\" -f \"$1\"", "rec", file, dir];
        proc.running = true;
        startedAt = Date.now();
    }
    function stop() { if (proc.running) proc.signal(2); }

    Process {
        id: proc
        onExited: (code, status) => {
            if (code === 0 && root.file) Quickshell.execDetached(["notify-send", "-a", "Screen Recording", "Recording saved", root.file]);
        }
    }
}

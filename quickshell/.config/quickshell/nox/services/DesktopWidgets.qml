pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Desktop widgets (modules/desktop): options from shell.json desktopWidgets, with the on/off and
// side picked at runtime (`nox widgets on|off|left|right|auto`, launcher, IPC target "widgets")
// kept in ~/.local/state/nox/widgets.json over the config (`nox widgets reset` drops them).
// side "auto" = the darker side of the wallpaper: prepped wallpapers put the art against one edge
// on black, so one `magick` probe per wallpaper (mean luma of the left and right 40%) decides;
// answers are cached by path for the session. No probe while widgets are off or the side is fixed.
Singleton {
    id: root
    readonly property var opt: Config.opt.desktopWidgets ?? ({})
    readonly property bool enabled: state.data.enabled ?? opt.enabled ?? true
    readonly property string side: state.data.side ?? opt.side ?? "auto"      // left | right | auto
    // what the column actually uses
    readonly property string resolvedSide: side === "right" || side === "left" ? side : (probed[Wallpaper.path] ?? "left")
    // runtime picks loaded (no on/off flash at start); side settled (auto: probe answered)
    readonly property bool ready: state.loaded
    readonly property bool sideKnown: side !== "auto" || !Wallpaper.path || probed[Wallpaper.path] !== undefined

    function setEnabled(v) { state.data = Object.assign({}, state.data, { enabled: !!v }); state.save(); }
    function toggle() { setEnabled(!enabled); }
    function setSide(s) {
        if (["left", "right", "auto"].indexOf(s) < 0) { console.warn("nox: widgets side must be left | right | auto, got", s); return false; }
        state.data = Object.assign({}, state.data, { side: s });
        state.save();
        return true;
    }
    function reset() { state.data = {}; state.save(); }
    function status() { return (enabled ? "on" : "off") + " " + side + (side === "auto" ? " (" + resolvedSide + ")" : ""); }

    JsonState { id: state; path: Paths.state("widgets") }

    // ---- auto side ----
    property var probed: ({})            // wallpaper path -> "left" | "right"
    readonly property bool wantProbe: enabled && side === "auto" && Wallpaper.path !== "" && probed[Wallpaper.path] === undefined
    onWantProbeChanged: probe()
    readonly property string wallpaper: Wallpaper.path
    onWallpaperChanged: probe()
    Component.onCompleted: probe()
    function probe() {
        if (!wantProbe || prober.running) return;
        prober.path = Wallpaper.path;
        prober.running = true;
    }
    Process {
        id: prober
        property string path
        // box-average to 5 columns: (0+1) = left 40%, (3+4) = right 40%
        command: ["magick", path + "[0]", "-colorspace", "Gray", "-scale", "5x1!",
                  "-format", "%[fx:(p{0,0}+p{1,0})/2] %[fx:(p{3,0}+p{4,0})/2]\n", "info:"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split(/\s+/).map(Number);
                // darker side wins; a near tie (full-bleed art) keeps the left
                const s = v.length === 2 && !isNaN(v[0]) && !isNaN(v[1]) && v[1] + 0.005 < v[0] ? "right" : "left";
                root.probed = Object.assign({}, root.probed, { [prober.path]: s });
            }
        }
        onExited: code => {
            if (code !== 0) {
                console.warn("nox: widgets side probe failed for", path, "(magick exit " + code + "), using left");
                root.probed = Object.assign({}, root.probed, { [path]: "left" });
            }
            root.probe();      // the wallpaper may have changed meanwhile
        }
    }
}

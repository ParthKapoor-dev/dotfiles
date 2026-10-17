pragma Singleton
import QtQuick
import Quickshell
import qs.core

// Current wallpaper: `qs -c nox ipc call wallpaper set <path>` (persisted in
// ~/.local/state/nox/wallpaper.json) overrides shell.json wallpaper.path.
Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    function expand(p) { return String(p ?? "").replace(/^~(?=\/|$)/, home); }
    // shell.json wallpaper.path wins; empty = the look's own wallpaper (tokens desktop.wallpaperPath, follows `nox theme`)
    readonly property string configured: expand(Config.opt.wallpaper?.path ?? "") || expand(Theme.t.desktop?.wallpaperPath ?? "")
    readonly property string path: expand(state.data.path ?? "") || configured
    readonly property string url: path ? "file://" + path : ""
    readonly property string fill: state.data.fill ?? Config.opt.wallpaper?.fill ?? "cover"

    function set(p) {
        state.data = Object.assign({}, state.data, { path: expand(p) });
        state.save();
    }
    function setFill(m) { state.data = Object.assign({}, state.data, { fill: m }); state.save(); }
    function reset() { state.data = {}; state.save(); }

    JsonState { id: state; path: Paths.state("wallpaper") }

    // Screen-sized decode shared by full-screen copies (Mission Control backdrop). Qt's pixmap
    // cache drops unreferenced images over ~2 MB, so a big wallpaper was re-decoded (~400 ms) on
    // every open; this holder keeps it referenced, and an Image with the same url, sourceSize,
    // fillMode and cache gets it at once.
    readonly property size screenSize: {
        const s = Quickshell.screens[0];
        const d = s?.devicePixelRatio ?? 1;
        return s ? Qt.size(Math.round(s.width * d), Math.round(s.height * d)) : Qt.size(1920, 1080);
    }
    property Image screenCopy: Image {
        source: root.url
        sourceSize: root.screenSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }
}

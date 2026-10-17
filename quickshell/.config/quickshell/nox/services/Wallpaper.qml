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
}

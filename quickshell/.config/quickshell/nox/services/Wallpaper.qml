pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
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
        source: root.displayUrl
        sourceSize: root.screenSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        visible: false
    }

    // What the wallpaper layers actually load: a screen-sized copy of big images, kept in
    // ~/.cache/nox/wallpaper (a 6000x4000 JPEG took ~370 ms to decode at login, the copy ~25 ms).
    // On a path change a quick check (cache current?) decides; on a miss the original shows and
    // the copy is made in the background for next time. center / tile need the exact pixels.
    readonly property bool scalable: fill !== "center" && fill !== "tile"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/nox/wallpaper"
    function cacheFileFor(p) { return cacheDir + "/" + Qt.md5(p) + "-" + screenSize.width + "x" + screenSize.height + ".jpg"; }
    property string displayUrl: ""
    // decide only once the saved pick is loaded (else the look's default flashes / gets cached)
    readonly property bool ready: state.loaded
    onPathChanged: pick()
    onScalableChanged: pick()
    onReadyChanged: pick()
    property bool pickAgain: false
    function pick() {
        if (!ready) return;
        if (!path) { displayUrl = ""; return; }
        if (!scalable) { displayUrl = url; return; }
        if (cacher.running) { pickAgain = true; return; }   // one check at a time; re-run after
        cacher.command = ["sh", "-c", root.cacheScript, "sh", path, cacheFileFor(path), String(screenSize.width), String(screenSize.height)];
        cacher.running = true;
    }
    // prints "cached<TAB>src" (use the copy) or "original<TAB>src", then makes the copy if useful
    readonly property string cacheScript: 'src=$1 out=$2 w=$3 h=$4
        if [ -s "$out" ] && [ "$out" -nt "$src" ]; then printf "cached\\t%s\\n" "$src"; exit 0; fi
        printf "original\\t%s\\n" "$src"
        set -- $(magick identify -format "%w %h" "$src[0]" 2>/dev/null) || exit 0
        [ -n "${1:-}" ] && [ $(( $1 * $2 )) -gt $(( w * h * 3 / 2 )) ] || exit 0
        mkdir -p "${out%/*}" && magick "$src[0]" -auto-orient -resize "${w}x${h}^" -quality 92 "$out.tmp.jpg" && mv -f "$out.tmp.jpg" "$out"'
    Process {
        id: cacher
        stdout: SplitParser {
            onRead: line => {
                const tab = line.indexOf("\t");
                const src = line.slice(tab + 1);
                if (tab < 0 || src !== root.path) return;      // answer for an older path
                root.displayUrl = line.startsWith("cached") ? "file://" + root.cacheFileFor(src) : "file://" + src;
            }
        }
        onExited: {
            if (root.pickAgain) { root.pickAgain = false; root.pick(); }
            else if (root.displayUrl === "" && root.path) root.displayUrl = root.url;
        }
    }
}

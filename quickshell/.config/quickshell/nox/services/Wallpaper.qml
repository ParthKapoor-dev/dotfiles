pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Current wallpaper: `qs -c nox ipc call wallpaper set <path>` (persisted in
// ~/.local/state/nox/wallpaper.json) overrides shell.json wallpaper.path.
// Slideshow (Wallpaper.slideshow): an ordered list of images cycled every
// shell.json wallpaper.slideshowMinutes (default 15), kept in the same state file.
Singleton {
    id: root
    readonly property string home: Quickshell.env("HOME")
    function expand(p) { return String(p ?? "").replace(/^~(?=\/|$)/, home); }
    // shell.json wallpaper.path wins; empty = the look's own wallpaper (tokens desktop.wallpaperPath, follows `nox theme`)
    readonly property string configured: expand(Config.opt.wallpaper?.path ?? "") || expand(Theme.t.desktop?.wallpaperPath ?? "")
    readonly property string path: expand(state.data.path ?? "") || configured
    readonly property string url: path ? "file://" + path : ""
    readonly property string fill: state.data.fill ?? Config.opt.wallpaper?.fill ?? "cover"

    // A manual pick that isn't in the running slideshow stops it; one that is in it continues
    // the slideshow from there (the timer starts over).
    function set(p) {
        const e = expand(p);
        if (slideshow.on) {
            const i = slideshow.paths.indexOf(e);
            if (i < 0) slideshow.stop();
            else { slideshow.write({ index: i }); if (ticker.running) ticker.restart(); }
        }
        show(e);
    }
    function show(p) { state.data = Object.assign({}, state.data, { path: p }); state.save(); }
    function setFill(m) { state.data = Object.assign({}, state.data, { fill: m }); state.save(); }
    // back to the configured wallpaper; the slideshow list is kept (stopped)
    function reset() {
        const ss = state.data.slideshow;
        state.data = ss ? { slideshow: Object.assign({}, ss, { on: false }) } : {};
        state.save();
    }

    JsonState { id: state; path: Paths.state("wallpaper") }

    // ---- slideshow: state.data.slideshow = { paths: [abs paths, in order], on, index } ----
    // Missing files are skipped when advancing (checked with one `test -f` pass); if none of the
    // list exists any more the slideshow stops. Starting shows the current wallpaper if it is in
    // the list, else the first image, at once; the timer only runs while on (and survives restarts).
    readonly property QtObject slideshow: QtObject {
        id: ss
        readonly property var saved: state.data.slideshow ?? ({})
        readonly property var paths: saved.paths ?? []
        readonly property bool on: (saved.on ?? false) && paths.length > 0
        readonly property int index: saved.index ?? 0
        readonly property real minutes: Math.max(0.05, Number(Config.opt.wallpaper?.slideshowMinutes ?? 15) || 15)

        function write(o) {
            state.data = Object.assign({}, state.data, { slideshow: Object.assign({}, ss.saved, o) });
            state.save();
        }
        // 1-based position, 0 = not in the slideshow
        function position(p) { return paths.indexOf(root.expand(p)) + 1; }
        function add(p) {
            const e = root.expand(p);
            if (e && paths.indexOf(e) < 0) write({ paths: paths.concat([e]) });
        }
        function remove(p) {
            const i = paths.indexOf(root.expand(p));
            if (i < 0) return;
            const list = paths.filter((_, j) => j !== i);
            // keep index on the shown image; removing it makes next() continue with its successor
            write({ paths: list, index: i <= index ? index - 1 : index, on: on && list.length > 0 });
        }
        function toggle(p) { if (position(p)) remove(p); else add(p); }
        function move(p, delta) {
            const i = paths.indexOf(root.expand(p)), j = i + delta;
            if (i < 0 || j < 0 || j >= paths.length) return false;
            const list = paths.slice();
            list.splice(j, 0, list.splice(i, 1)[0]);
            const cur = list.indexOf(root.path);
            write({ paths: list, index: cur >= 0 ? cur : index });
            return true;
        }
        function clear() { write({ paths: [], on: false, index: 0 }); }
        function start() {
            if (!paths.length) return;
            const cur = paths.indexOf(root.path);
            write({ on: true });
            advance(cur >= 0 ? cur : 0, 1);
        }
        function stop() { if (saved.on) write({ on: false }); }
        function next() { step(1); }
        function prev() { step(-1); }
        function step(d) {
            if (!paths.length) return;
            const cur = paths.indexOf(root.path);
            const base = cur >= 0 ? cur : Math.min(index, paths.length - 1);
            advance(base + d, d);
        }
        // show the first existing file going from paths[from] in direction dir (wrapping around)
        function advance(from, dir) {
            if (checker.running) return;
            const n = paths.length, order = [];
            for (let k = 0; k < n; k++) order.push(paths[(((from + dir * k) % n) + n) % n]);
            checker.command = ["sh", "-c", 'for f; do [ -f "$f" ] && { printf "%s\\n" "$f"; exit 0; }; done; exit 1', "sh"].concat(order);
            checker.found = "";
            checker.running = true;
        }
    }
    Process {
        id: checker
        property string found
        stdout: SplitParser { onRead: line => checker.found = line }
        onExited: {
            if (!found) {
                if (root.slideshow.on) console.warn("nox: wallpaper slideshow: no image in the list exists, stopping");
                root.slideshow.stop();
                return;
            }
            root.slideshow.write({ index: Math.max(0, root.slideshow.paths.indexOf(found)) });
            root.show(found);
            if (ticker.running) ticker.restart();
        }
    }
    Timer {
        id: ticker
        interval: root.slideshow.minutes * 60000
        running: root.ready && root.slideshow.on
        repeat: true
        onTriggered: root.slideshow.next()
    }

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

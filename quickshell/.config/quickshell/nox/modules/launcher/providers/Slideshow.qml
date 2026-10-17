import QtQuick
import Quickshell
import qs.core
import qs.services

// Wallpaper slideshow (prefix "%"): the slideshow list (Wallpaper.slideshow) in its order, after
// control rows "Start / Stop slideshow" and "Next wallpaper". Enter on an image shows it now (the
// slideshow continues from there), Alt+Up/Alt+Down reorders, Shift+Delete removes. Images are
// added from the wallpapers provider ("#", Ctrl+Enter). Typed text filters the images by name.
// Thumbnails are the images themselves, decoded small (the list is short).
Item {
    id: root
    property string providerId: "slideshow"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Slideshow"
    property string defaultPrefix: "%"
    property bool defaultPrefixOnly: true
    signal resultsChanged()

    readonly property string home: Quickshell.env("HOME")
    readonly property var ss: Wallpaper.slideshow
    // list / on / current changes (also from IPC or the timer) refresh an open launcher
    Connections {
        target: root.ss
        function onPathsChanged() { root.resultsChanged(); }
        function onOnChanged() { root.resultsChanged(); }
    }
    Connections {
        target: Wallpaper
        function onPathChanged() { root.resultsChanged(); }
    }

    function query(text, prefixed) {
        if (!prefixed) return [];
        const out = [];
        const n = ss.paths.length;
        if (!text) {
            const every = "every " + ss.minutes + " min · " + n + (n === 1 ? " image" : " images");
            if (n) out.push({
                title: ss.on ? "Stop Slideshow" : "Start Slideshow",
                sub: ss.on ? "Running, " + every : every,
                icon: ss.on ? "pause" : "play",
                key: "slideshow:toggle",
                type: "Slideshow",
                actLabel: ss.on ? "Stop" : "Start",
                run: () => { if (ss.on) ss.stop(); else ss.start(); }
            });
            if (n) out.push({
                title: "Next Wallpaper",
                icon: "next",
                key: "slideshow:next",
                type: "Slideshow",
                actLabel: "Next",
                run: () => ss.next()
            });
            if (!n) out.push({
                title: "Slideshow is empty",
                sub: "Ctrl+Enter on a wallpaper (#) adds it",
                icon: "image",
                key: "slideshow:empty",
                actLabel: "Choose Wallpapers",
                run: () => Panels.openLauncher("# ")
            });
        }
        ss.paths.forEach((p, i) => {
            const file = p.split("/").pop();
            const m = text ? Fuzzy.best(text, [[file, 1]]) : { score: 0, indices: [] };
            if (!m) return;
            const dir = p.slice(0, p.length - file.length - 1).replace(home, "~");
            out.push({
                title: file,
                sub: dir,
                highlight: m.indices,
                thumb: "file://" + p,
                thumbSlot: true,
                preview: "file://" + p,
                badge: String(i + 1),
                key: p,
                type: p === Wallpaper.path ? "Current" : "Image",
                actLabel: "Show Now",
                score: 0,
                run: () => Wallpaper.set(p),
                remove: () => ss.remove(p),
                move: d => ss.move(p, d)
            });
        });
        return out;
    }
}

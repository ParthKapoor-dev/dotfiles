pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.services

// Drop shelf (mock 23g, C6): a parking spot for files, text, images and links between apps.
// Right screen edge, vertically centred (shell.json shelf.side). Store + persistence: services/Shelf.
//   drag in     drag anything from any app to the screen edge: the shelf slides out as the drop target
//               (ShelfWindow keeps a 2 px input strip on the edge for this)
//   drag out    drag a card (or the whole pile) into any app: a real Wayland drag with text/uri-list;
//               with Move out on (shelf.moveOut) an accepted drop takes the item off the shelf
//   collapsed   a thin tab with the count; hidden when empty. Hover / click the tab to open it
//   Super+Shift+D (GlobalShortcut nox:shelfToggle) pins it open / closes it; Esc closes a pinned shelf
//   qs -c nox ipc call shelf add <path> | addText <text> | adopt <stored file> | list | remove <id>
//                            | undo | clear | open | close | toggle | status   (`nox shelf ...`)
// States: hidden (empty) | tab | open (hovered / pinned / just added) | target (a drag is over it).
Scope {
    id: root

    property string screenName: Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? ""
    property bool pinned: false
    property bool hover: false
    property bool dragIn: false
    property bool over: false
    property bool peek: false
    property int outDrags: 0
    property bool fan: false
    readonly property string st: dragIn ? "target"
        : (pinned || ((hover || peek || outDrags > 0) && Shelf.count > 0)) ? "open"
        : Shelf.count > 0 ? "tab" : "hidden"
    onStChanged: if (st !== "target") over = false

    function focusedScreen() { return Hyprland.focusedMonitor?.name ?? screenName; }
    function open() { screenName = focusedScreen(); pinned = true; }
    function close() { pinned = false; hover = false; peek = false; }
    function toggle() { if (st === "open" || st === "target") close(); else open(); }
    function peekFor(ms) { peek = true; peekTimer.interval = ms; peekTimer.restart(); }

    // ---- hover: the tab opens after a short dwell; leaving the shelf collapses it ----
    function setHover(h, screen) {
        if (h) {
            leaveTimer.stop();
            if (st === "open" && screen === screenName) hover = true;
        } else {
            dwell.stop();
            if (hover) leaveTimer.restart();
        }
    }
    function tabHovered(screen) { dwell.screen = screen; dwell.restart(); }
    function openFromTab(screen) { dwell.stop(); screenName = screen; hover = true; }
    Timer { id: dwell; property string screen: ""; interval: 160; onTriggered: { root.screenName = screen; root.hover = true; } }
    Timer { id: leaveTimer; interval: 650; onTriggered: root.hover = false }
    Timer { id: peekTimer; interval: 1900; onTriggered: root.peek = false }

    // ---- drag in ----
    function dragEnter(screen) {
        dragLeaveTimer.stop();
        screenName = screen;
        dragIn = true;
    }
    function dragLeave() { dragLeaveTimer.restart(); }
    Timer { id: dragLeaveTimer; interval: 650; onTriggered: { root.dragIn = false; root.over = false; } }

    // what a drop carries -> shelf items. Files are kept as references; text, links and image bytes
    // are stored in the shelf's own folder.
    function ingest(d) {
        dragLeaveTimer.stop();
        dragIn = false;
        over = false;
        const formats = d.formats ?? [];
        // KDE sources also offer their own uri list, which Qt does not route through the portal
        const kde = formats.indexOf("application/x-kde4-urilist") !== -1 ? d.getDataAsString("application/x-kde4-urilist") : "";
        const kdeUrls = kde.split(/\r?\n/).map(l => l.trim()).filter(l => /^[a-z][a-z0-9+.-]*:\/\//i.test(l));
        const urls = kdeUrls.length ? kdeUrls : d.hasUrls ? d.urls.map(u => String(u)) : [];
        const files = urls.filter(u => u.startsWith("file://"));
        let ok = false;
        if (files.length) ok = Shelf.addPaths(files) > 0;
        if (!ok) {
            const img = formats.find(f => /^image\/(png|jpeg|webp|gif|bmp|avif)$/.test(f));
            if (img) {
                const buf = d.getDataAsArrayBuffer(img);
                if (buf && buf.byteLength > 0) ok = Shelf.addImageData(buf, img, urls.length ? Shelf.baseName(urls[0].split(/[?#]/)[0]) : "");
            }
        }
        if (!ok) {
            const web = urls.filter(u => /^https?:\/\//i.test(u));
            if (web.length) {
                const html = d.hasHtml ? d.html : "";
                const imgSrc = /<img[^>]+src="([^"]+)"/i.exec(html)?.[1] ?? "";
                const anchor = /<a[^>]*>([\s\S]*?)<\/a>/i.exec(html)?.[1]?.replace(/<[^>]+>/g, "").trim() ?? "";
                const text = d.hasText ? d.text.trim() : "";
                for (const u of web) {
                    const title = anchor || (text && text !== u && !/^https?:\/\//.test(text) ? text.split("\n")[0] : "");
                    // an image dragged out of a page (its URL, maybe in an <img>): fetch the picture
                    if (Shelf.isImageName(u.split(/[?#]/)[0]) || (imgSrc && imgSrc === u && !anchor)) Shelf.addRemoteImage(u, title);
                    else Shelf.addLink(u, title);
                }
                ok = true;
            }
        }
        if (!ok && d.hasText && d.text.trim() !== "") ok = Shelf.addText(d.text);
        if (!ok && d.hasHtml) ok = Shelf.addText(d.html.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim());
        if (ok) { hover = true; leaveTimer.restart(); }
        else Panels.hud("The shelf can't hold that", "x");
        return ok;
    }

    // ---- drag out ----
    function outBegan(ids) { outDrags++; leaveTimer.stop(); Hyprland.refreshToplevels(); }
    // Did an app take the drop? Qt reports it as the drop action, but Hyprland (0.56) never sends
    // wl_data_source.action, so Qt says IgnoreAction for every drop. Until it does, ask the
    // compositor what is under the pointer: an app window = delivered; the desktop, the shelf or
    // nothing = cancelled (the item stays). Esc over a window counts as delivered: `nox shelf undo`.
    function outEnded(ids, action) {
        outDrags = Math.max(0, outDrags - 1);
        if (action !== Qt.IgnoreAction) { delivered(ids); return; }
        if (cursorProc.running) { delivered(ids); return; }
        cursorProc.ids = ids;
        cursorProc.running = true;
    }
    function delivered(ids) {
        if (Shelf.moveOut) Shelf.remove(ids);
        if (!pinned) { hover = false; peek = false; }
    }
    Process {
        id: cursorProc
        property var ids: []
        command: ["hyprctl", "-j", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = null;
                try { p = JSON.parse(text); } catch (e) {}
                if (p && root.windowAt(p.x, p.y)) root.delivered(cursorProc.ids);
                else root.peekFor(1200);
            }
        }
    }
    // an app window under a global point on its monitor's visible workspace (or special workspace)
    function windowAt(x, y) {
        const shown = {};
        for (const m of Hyprland.monitors.values) {
            if (m.activeWorkspace) shown[m.activeWorkspace.id] = true;
            const sp = m.lastIpcObject?.specialWorkspace?.id ?? 0;
            if (sp) shown[sp] = true;
        }
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject;
            if (!o || !o.at || !o.size || o.hidden || o.mapped === false || !shown[o.workspace?.id]) continue;
            if (x >= o.at[0] && y >= o.at[1] && x < o.at[0] + o.size[0] && y < o.at[1] + o.size[1]) return true;
        }
        return false;
    }

    function openItem(id) {
        const it = Shelf.find(id);
        if (!it) return;
        Quickshell.execDetached(["xdg-open", it.kind === "link" && it.url ? it.url : it.path]);
        if (!pinned) hover = false;
    }
    function clearAll() {
        const n = Shelf.clear();
        if (n) Panels.hud("Cleared " + n + " item" + (n > 1 ? "s" : "") + " from the shelf", "trash");
        pinned = false; hover = false; peek = false;
    }

    // Mission Control opens the shelf alongside (shell.json overview.shelf, default true), empty or
    // not, and closes it again unless it was already pinned open. While Mission Control is up the
    // shelf windows sit on the Overlay layer above it (Panels.overviewLayered, set by the overview).
    property bool byOverview: false
    readonly property bool overOverview: Panels.overviewLayered && (Config.opt.overview?.shelf ?? true)
    Connections {
        target: Panels
        function onOverviewOpenChanged() {
            if (Panels.overviewOpen) {
                if (!(Config.opt.overview?.shelf ?? true)) return;
                if (!root.pinned) { root.byOverview = true; root.open(); }
            } else {
                if (root.byOverview) { root.byOverview = false; root.close(); }
            }
        }
    }

    Connections {
        target: Shelf
        function onAdded(ids) { if (root.st === "hidden" || root.st === "tab") root.screenName = root.focusedScreen(); root.peekFor(1900); }
        function onToast(text, glyph) { Panels.hud(text, glyph); }
        function onCountChanged() { if (Shelf.count === 0) root.fan = false; }
    }

    // qs -c nox ipc call shelf add <path> | addText <text> | adopt <path> | list | remove <id> | clear
    //                        | open | close | toggle | status
    IpcHandler {
        target: "shelf"
        function add(path: string): bool { return Shelf.addPaths([path]) > 0; }
        function addText(text: string): bool { return Shelf.addText(text); }
        function addLink(url: string, title: string): bool { return /^https?:\/\//i.test(url) && Shelf.addLink(url, title); }
        // a file `nox shelf add -` wrote into the shelf's own items/ folder
        function adopt(path: string): bool { return Shelf.adopt(path, "text"); }
        // id <TAB> kind <TAB> name <TAB> path or URL <TAB> minutes left <TAB> ok|missing
        function list(): string {
            return Shelf.items.map(it => [it.id, it.kind, it.name, it.kind === "link" ? it.url : it.path,
                Math.round(Shelf.leftMs(it) / 60000), Shelf.isMissing(it) ? "missing" : "ok"].join("\t")).join("\n");
        }
        function remove(id: string): bool { return Shelf.remove([id]) > 0; }
        // put back what the last drag-out / clear / remove took off (within 10 minutes)
        function undo(): int { return Shelf.undo(); }
        function clear(): int { const n = Shelf.clear(); root.close(); return n; }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        function toggle(): void { root.toggle(); }
        function status(): string {
            return "count=" + Shelf.count + " state=" + root.st + " pinned=" + root.pinned + " screen=" + root.screenName
                + " side=" + Shelf.side + " expireHours=" + Shelf.expireHours + " moveOut=" + Shelf.moveOut;
        }
    }

    LazyLoader {
        active: !Quickshell.env("NOX_LINT")
        component: GlobalShortcut {
            appid: "nox"; name: "shelfToggle"; description: "Drop shelf: open / close"
            onPressed: root.toggle()
        }
    }

    Variants {
        model: Quickshell.screens
        ShelfWindow { ctl: root }
    }
}

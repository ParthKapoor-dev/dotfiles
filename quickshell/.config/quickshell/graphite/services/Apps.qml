pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// Dock model: pinned apps (shell.json dock.pinned) + running unpinned apps, as plain JS objects
// (no per-recompute QObject allocation). Running state comes from the wlr foreign-toplevel protocol.
Singleton {
    id: root

    function entryFor(id) {
        if (!id) return null;
        return DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
    }
    function keyFor(id, entry) { return (entry ? entry.id : id).toLowerCase(); }
    function iconFor(item) {
        const name = item.entry?.icon || item.appId;
        return Quickshell.iconPath(name, "application-x-executable");
    }

    // DesktopEntries fills its model one entry at a time at startup (~70 change signals);
    // coalesce them so the dock is rebuilt once, not per entry.
    property int entriesRev: 0
    Connections { target: DesktopEntries.applications; function onValuesChanged() { entriesDebounce.restart(); } }
    Timer { id: entriesDebounce; interval: 250; onTriggered: root.entriesRev++ }

    readonly property var pinned: Config.opt.dock?.pinned ?? []
    readonly property var items: {
        root.entriesRev;  // re-evaluate when .desktop entries change (debounced)
        const ignored = (Config.opt.dock?.ignoredAppIds ?? []).map(p => new RegExp(p, "i"));
        const out = [];
        const byKey = {};
        for (const id of root.pinned) {
            const entry = entryFor(id);
            const key = keyFor(id, entry);
            if (byKey[key]) continue;
            byKey[key] = { key, appId: id, entry, pinned: true, toplevels: [], sep: false };
            out.push(byKey[key]);
        }
        const running = [];
        for (const t of ToplevelManager.toplevels.values) {
            if (!t.appId || ignored.some(r => r.test(t.appId))) continue;
            const entry = entryFor(t.appId);
            const key = keyFor(t.appId, entry);
            if (!byKey[key]) {
                if (Config.opt.dock?.showRunning === false) continue;
                byKey[key] = { key, appId: t.appId, entry, pinned: false, toplevels: [], sep: false };
                running.push(byKey[key]);
            }
            byKey[key].toplevels.push(t);
        }
        if (out.length && running.length) out.push({ key: "__sep", sep: true, toplevels: [] });
        return out.concat(running);
    }

    function isPinned(key) { return items.some(i => !i.sep && i.pinned && i.key === key); }
    function togglePin(item) {
        const list = root.pinned.slice();
        const idx = list.findIndex(id => keyFor(id, entryFor(id)) === item.key);
        if (idx >= 0) list.splice(idx, 1); else list.push(item.entry ? item.entry.id : item.appId);
        Config.setDockPinned(list);
    }

    function launch(item) {
        if (item.entry) item.entry.execute();
        else Quickshell.execDetached([item.appId]);
    }
    // click: launch if not running, else focus; cycle windows if already focused
    function activate(item) {
        const tl = item.toplevels;
        if (!tl.length) { launch(item); return; }
        const cur = tl.findIndex(t => t.activated);
        tl[(cur + 1) % tl.length].activate();
    }
    function quit(item) { for (const t of item.toplevels) t.close(); }
}

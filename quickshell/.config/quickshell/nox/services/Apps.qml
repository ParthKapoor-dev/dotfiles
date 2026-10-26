pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Qt.labs.folderlistmodel
import qs.core

// Dock model: pinned apps (shell.json dock.pinned) + running unpinned apps, as plain JS objects
// (no per-recompute QObject allocation). Running state comes from the wlr foreign-toplevel protocol.
// A dock.pinned entry { "folder": "Dev", "apps": [ids] } is a folder tile (modules/dock/DockFolder):
// { key: "__folder:<name>", folder, apps: [app objects] }. Its apps are not pinned on their own, so
// a running one also gets a normal running tile; its windows show in the folder as well.
Singleton {
    id: root

    function entryFor(id) {
        if (!id) return null;
        return DesktopEntries.byId(id) ?? DesktopEntries.heuristicLookup(id);
    }
    function keyFor(id, entry) { return (entry ? entry.id : id).toLowerCase(); }
    function iconFor(item) {
        if (item.stack === "downloads") return Quickshell.iconPath("folder-download", "folder");
        if (item.stack === "trash") return Quickshell.iconPath(root.trashFull ? "user-trash-full" : "user-trash", "user-trash");
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
        const inFolders = {};    // key -> that app's objects inside folders (they get its windows too)
        for (const id of root.pinned) {
            if (typeof id !== "string") {
                if (!id || !id.folder) continue;
                const apps = [];
                for (const a of (Array.isArray(id.apps) ? id.apps : [])) {
                    if (typeof a !== "string" || !a) continue;
                    const entry = entryFor(a);
                    const o = { key: keyFor(a, entry), appId: a, entry, pinned: true, toplevels: [], sep: false };
                    apps.push(o);
                    if (!inFolders[o.key]) inFolders[o.key] = [];
                    inFolders[o.key].push(o);
                }
                const key = "__folder:" + id.folder;
                if (byKey[key]) continue;
                byKey[key] = { key, folder: String(id.folder), apps, appId: "", entry: null, pinned: true, toplevels: [], sep: false };
                out.push(byKey[key]);
                continue;
            }
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
            for (const o of inFolders[key] ?? []) o.toplevels.push(t);
            if (!byKey[key]) {
                if (Config.opt.dock?.showRunning === false) continue;
                byKey[key] = { key, appId: t.appId, entry, pinned: false, toplevels: [], sep: false };
                running.push(byKey[key]);
            }
            byKey[key].toplevels.push(t);
        }
        if (out.length && running.length) out.push({ key: "__sep", sep: true, toplevels: [] });
        const all = out.concat(running);
        // folder stacks after a separator (mock: Downloads, Trash)
        const stacks = (Config.opt.dock?.stacks ?? []).filter(s => s === "downloads" || s === "trash");
        if (stacks.length) {
            all.push({ key: "__sep2", sep: true, toplevels: [] });
            for (const s of stacks) all.push({ key: "__" + s, stack: s, appId: s, entry: null, pinned: false, toplevels: [], sep: false });
        }
        return all;
    }

    function isPinned(key) { return items.some(i => !i.sep && i.pinned && i.key === key); }
    function togglePin(item) {
        const list = root.pinned.slice();
        const idx = list.findIndex(id => typeof id === "string" && keyFor(id, entryFor(id)) === item.key);
        if (idx >= 0) list.splice(idx, 1); else list.push(item.entry ? item.entry.id : item.appId);
        Config.setDockPinned(list);
    }

    // visual size normalisation: measured content scale per icon (see DockItem), overridable
    // per app in shell.json dock.iconScale { "<appId or desktop id>": factor }
    property var measured: ({})
    function setMeasured(key, v) { if (measured[key] !== v) measured = Object.assign({}, measured, { [key]: v }); }
    function iconScale(item) {
        const o = Config.opt.dock?.iconScale ?? {};
        const id = item.entry?.id ?? item.appId;
        if (o[id] !== undefined) return o[id];
        if (o[item.appId] !== undefined) return o[item.appId];
        return measured[item.key] ?? 1;
    }

    function launch(item) {
        if (item.entry) item.entry.execute();
        else Quickshell.execDetached([item.appId]);
    }
    property bool trashFull: false
    readonly property string home: Quickshell.env("HOME")
    function openStack(s) {
        const c = Config.opt.dock?.stackCommands ?? {};
        // both stacks open in the default file manager (inode/directory); trash:/// only where the
        // file manager understands it (gio hands it to that same default), else the Trash folder
        const trash = ["sh", "-c", "case \"$(xdg-mime query default inode/directory)\" in"
            + " *dolphin*|*nautilus*|*nemo*|*thunar*|*caja*|*pcmanfm*) exec gio open trash:/// ;; esac;"
            + " exec xdg-open \"$HOME/.local/share/Trash/files\""];
        const cmd = c[s] ?? (s === "downloads" ? ["xdg-open", home + "/Downloads"] : trash);
        Quickshell.execDetached(cmd.map(a => String(a).replace(/^~/, home)));
    }
    function emptyTrash() { Quickshell.execDetached(["gio", "trash", "--empty"]); }

    // click: launch if not running, else focus; cycle windows if already focused
    function activate(item) {
        if (item.stack) { openStack(item.stack); return; }
        const tl = item.toplevels;
        if (!tl.length) { launch(item); return; }
        const cur = tl.findIndex(t => t.activated);
        tl[(cur + 1) % tl.length].activate();
    }
    function quit(item) { for (const t of item.toplevels) t.close(); }

    FolderListModel {
        folder: "file://" + root.home + "/.local/share/Trash/files"
        showDirs: true
        showHidden: true
        onCountChanged: root.trashFull = count > 0
    }
}

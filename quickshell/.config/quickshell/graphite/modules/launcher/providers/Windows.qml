import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.core
import qs.services

// Open Hyprland windows: match on title and app id; Enter focuses the window (switching workspace).
// Typing the prefix alone ("@") lists every window.
Item {
    id: root
    property string providerId: "windows"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Windows"
    property string defaultPrefix: "@"
    property bool defaultPrefixOnly: false

    function appIdOf(t) { return t.wayland?.appId || t.lastIpcObject?.class || ""; }

    function query(text, prefixed) {
        if (!text && !prefixed) return [];
        const out = [];
        for (const t of Hyprland.toplevels.values) {
            const appId = appIdOf(t);
            const entry = appId ? (DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId)) : null;
            const appName = entry?.name || appId;
            const m = text ? Fuzzy.best(text, [[t.title, 1], [appName, 0.9], [appId, 0.7]]) : { score: 1, indices: [] };
            if (!m) continue;
            const ws = t.workspace?.name ?? "";
            out.push({
                title: t.title || appName,
                sub: appName + (ws ? " · workspace " + ws : ""),
                image: Quickshell.iconPath(entry?.icon || appId, "application-x-executable"),
                highlight: m.indices,
                type: "Window",
                actLabel: "Switch",
                score: m.score + (t.activated ? -5 : 0),
                run: () => {
                    // Hypr.focusWindow: the legacy "focuswindow address:" string is a Lua error under hyprland.lua
                    const a = String(t.address);
                    if (a) Hypr.focusWindow(a);
                    else t.wayland?.activate();
                }
            });
        }
        return out;
    }
}

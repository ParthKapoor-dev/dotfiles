pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services

// The menu bar's app menus (mock: app name + File/Edit/View/Window/Help). Linux apps don't export
// their menus, so these are window-manager level actions on the focused app/window, like macOS's
// own items: New Window, Hide, Quit, layout, Mission Control, Move to Desktop, window list…
// Item: { label, shortcut?, check?, dis?, act } | { sep: true } | { head: "text" }
Singleton {
    id: root
    readonly property var toplevel: ToplevelManager.activeToplevel
    readonly property bool hasWindow: !!toplevel && toplevel.activated
    readonly property string appId: hasWindow ? toplevel.appId : ""
    readonly property var entry: { Apps.entriesRev; return appId ? Apps.entryFor(appId) : null; }
    readonly property string appName: entry?.name || appId || (Config.widget("appName").fallback ?? "Desktop")
    readonly property var hyprActive: Hyprland.activeToplevel
    readonly property int activeWs: hyprActive?.workspace?.id ?? Hyprland.focusedWorkspace?.id ?? 1

    function appWindows() { return appId ? ToplevelManager.toplevels.values.filter(t => t.appId === appId) : []; }
    function terminal() { return Config.opt.terminal ?? ["ghostty"]; }
    function wsCount() { return Math.max(Config.widget("workspaces").minCount ?? 4, ...Hyprland.workspaces.values.filter(w => w.id > 0).map(w => w.id)); }

    function items(name) {
        const w = hasWindow, an = appName;
        switch (name) {
        case "app": return [
            { label: "New " + an + " Window", dis: !entry, act: () => entry?.execute() },
            { sep: true },
            { label: "Hide " + an, dis: !w, act: () => { for (const t of appWindows()) { Hypr.focusWindow(addrOf(t)); Hypr.minimize(); } } },
            { label: "Show Hidden Windows", act: () => Hypr.dispatch("togglespecialworkspace minimized", "hl.dsp.workspace.toggle_special(\"minimized\")") },
            { sep: true },
            { label: "Quit " + an, dis: !w, act: () => { for (const t of appWindows()) t.close(); } },
            { label: "Force Quit " + an, dis: !w, danger: true, act: () => Hypr.killActive() }
        ];
        case "File": return [
            { label: "New Window", dis: !entry, act: () => entry?.execute() },
            { label: "New Terminal", act: () => Quickshell.execDetached(terminal()) },
            { label: "Open…", act: () => Panels.openLauncher("") },
            { sep: true },
            { label: "Close Window", dis: !w, act: () => toplevel.close() }
        ];
        case "Edit": return [
            { label: "Clipboard History…", dis: !Config.moduleEnabled("clipboard"), act: () => Panels.openLauncher(":") },
            { label: "Pick Color", act: () => Quickshell.execDetached(["hyprpicker", "-a"]) },
            { sep: true },
            { label: "Screenshot…", act: () => Actions.run("screenshot") }
        ];
        case "View": return [
            { head: "Window layout" },
            ...["dwindle", "scrolling", "master", "monocle"].map(l => ({ label: Layout.labels[l], check: Layout.name === l, act: () => Layout.set(l) })),
            { sep: true },
            { label: "Mission Control", dis: !Config.moduleEnabled("overview"), act: () => { Panels.overviewOpen = true; } },
            { label: "Notification Center", dis: !Config.moduleEnabled("notifications"), act: () => Panels.open("notifications") },
            { label: "Control Center", act: () => Panels.open("controlCenter") },
            { sep: true },
            { label: (hyprActive?.lastIpcObject?.fullscreen ?? 0) > 0 ? "Exit Full Screen" : "Enter Full Screen", dis: !w, act: () => Hypr.fullscreen("fullscreen") }
        ];
        case "Window": {
            const n = wsCount();
            const out = [
                { label: "Minimize", dis: !w, act: () => Hypr.minimize() },
                { label: "Zoom", dis: !w, act: () => Hypr.fullscreen("maximized") },
                { label: (hyprActive?.lastIpcObject?.floating ?? false) ? "Tile Window" : "Float Window", dis: !w, act: () => Hypr.toggleFloat() },
                { label: "Center", dis: !w, act: () => Hypr.center() },
                { label: "Keep on Top (Pin)", dis: !w, act: () => Hypr.pin() },
                { sep: true },
                { head: "Move to" }
            ];
            for (let i = 1; i <= n; i++) out.push({ label: "Desktop " + i, check: w && activeWs === i, dis: !w, act: () => Hypr.moveActiveTo(i) });
            const wins = Hyprland.toplevels.values.filter(t => t.workspace?.id === Hyprland.focusedWorkspace?.id);
            if (wins.length) out.push({ sep: true });
            for (const t of wins) out.push({ label: t.title || t.wayland?.appId || "Window", check: t === hyprActive, act: () => Hypr.focusWindow(addrOf(t)) });
            return out;
        }
        case "Help": return [
            { label: "Search Commands", act: () => Panels.openLauncher("/") },
            { label: "Edit Shell Config", act: () => Quickshell.execDetached(["xdg-open", Paths.shell]) },
            { sep: true },
            { label: "Hyprland Wiki", act: () => Quickshell.execDetached(["xdg-open", "https://wiki.hypr.land/"]) },
            { label: "Quickshell Docs", act: () => Quickshell.execDetached(["xdg-open", "https://quickshell.org/docs/"]) }
        ];
        }
        return [];
    }
    function addrOf(t) {
        if (t.address !== undefined) return t.address;   // HyprlandToplevel
        const h = Hyprland.toplevels.values.find(x => x.wayland === t);
        return h ? h.address : "";
    }
}

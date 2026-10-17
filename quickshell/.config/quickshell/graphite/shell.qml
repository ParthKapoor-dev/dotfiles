//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// graphite: small Quickshell shell for the "Sequoia Graphite" desktop.
// Modules are switched on/off in ~/.config/graphite/shell.json ("modules"), live.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.services
import qs.modules.bar
import qs.modules.dock
import qs.modules.controlcenter
import qs.modules.launcher
import qs.modules.osd
import qs.modules.notifications

ShellRoot {
    LazyLoader { active: Config.moduleEnabled("bar"); component: Bar {} }
    LazyLoader { active: Config.moduleEnabled("dock"); component: Dock {} }
    LazyLoader { active: Config.moduleEnabled("controlCenter"); component: ControlCenter {} }
    LazyLoader { active: Config.moduleEnabled("launcher"); component: Launcher {} }
    LazyLoader { active: Config.moduleEnabled("osd"); component: Osd {} }
    // The notification D-Bus server itself is in services/Notifs (same switch).
    LazyLoader { active: Config.moduleEnabled("notifications"); component: Notifications {} }

    // qs -c graphite ipc call controlCenter toggle
    IpcHandler {
        target: "controlCenter"
        function toggle(): void { Panels.toggle("controlCenter"); }
        function open(): void { Panels.open("controlCenter"); }
        function close(): void { Panels.close("controlCenter"); }
    }
    // qs -c graphite ipc call dock toggle
    IpcHandler {
        target: "dock"
        function toggle(): void { Panels.dockVisible = !Panels.dockVisible; }
        function open(): void { Panels.dockVisible = true; }   // ("show" is reserved by the qs ipc CLI)
        function close(): void { Panels.dockVisible = false; }
    }
    // qs -c graphite ipc call popup toggle bar:network   (ids: "controlCenter", "bar:<widgetId>")
    // qs -c graphite ipc call popup close                  (closes whatever popup is open)
    IpcHandler {
        target: "popup"
        function toggle(id: string): void { Panels.toggle(id); }
        function open(id: string): void { Panels.open(id); }
        function close(): void { Panels.close(); }
        function current(): string { return Panels.popup; }
    }

    // qs -c graphite ipc call layout changed <name>   (sent by graphite-layout after every change)
    // qs -c graphite ipc call layout get | next | prev | set <name>
    IpcHandler {
        target: "layout"
        function changed(name: string): void { Layout.changed(name); }
        function get(): string { return Layout.name; }
        function next(): void { Layout.next(); }
        function prev(): void { Layout.prev(); }
        function set(name: string): void { Layout.set(name); }
    }

    // launcher IPC (toggle|open|close|search|results) lives in modules/launcher/Launcher.qml
    // qs -c graphite ipc call notifications toggle       (Notification Center)
    // qs -c graphite ipc call notifications toggleDnd    | setDnd true|false | clear | dnd | status
    IpcHandler {
        target: "notifications"
        function toggle(): void { Panels.toggle("notifications"); }
        function open(): void { Panels.open("notifications"); }
        function close(): void { Panels.close("notifications"); }
        function toggleDnd(): void { Notifs.toggleDnd(); }
        function setDnd(on: bool): void { Notifs.setDnd(on); }
        function dnd(): bool { return Notifs.dnd; }
        function clear(): void { Notifs.clearAll(); }
        // "server=<registered> dnd=<bool> count=<history> popups=<on screen>"
        function status(): string { return "server=" + Notifs.running + " dnd=" + Notifs.dnd + " count=" + Notifs.count + " popups=" + Notifs.popups.length; }
    }

    // Hyprland global shortcuts (appid "graphite"). Not registered in lint runs (GRAPHITE_LINT=1),
    // so a syntax check never competes with the live instance for the same shortcut names.
    LazyLoader {
        active: !Quickshell.env("GRAPHITE_LINT")
        component: Scope {
        // shortcuts (appid "graphite"): bind with hl.dsp.global("graphite:<name>").
        // launcherToggleRelease + launcherToggleReleaseInterrupt = "tap Super to open" (same pattern as ii).
        GlobalShortcut {
            appid: "graphite"; name: "launcherToggle"; description: "Toggle the launcher"
            onPressed: Panels.launcherOpen = !Panels.launcherOpen
        }
        GlobalShortcut {
            id: superTap
            appid: "graphite"; name: "launcherToggleRelease"; description: "Toggle the launcher when Super is released alone"
            property bool mightTrigger: false
            property bool pressGuard: false
            onPressed: { mightTrigger = true; pressGuard = true; }
            onReleased: {
                pressGuard = false;
                if (mightTrigger) Panels.launcherOpen = !Panels.launcherOpen;
                mightTrigger = false;
            }
        }
        GlobalShortcut {
            appid: "graphite"; name: "launcherToggleReleaseInterrupt"; description: "Cancel the Super-tap launcher toggle (bind to a catchall)"
            // the catchall also fires on the Super press itself (Hyprland 0.55.3+): absorb that one
            onPressed: { if (superTap.pressGuard) { superTap.pressGuard = false; return; } superTap.mightTrigger = false; }
        }
        GlobalShortcut {
            appid: "graphite"; name: "notificationCenterToggle"; description: "Toggle the Notification Center"
            onPressed: Panels.toggle("notifications")
        }
        GlobalShortcut {
            appid: "graphite"; name: "dndToggle"; description: "Toggle Do Not Disturb"
            onPressed: Notifs.toggleDnd()
        }
        }
    }
}

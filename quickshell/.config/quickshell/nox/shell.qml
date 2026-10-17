//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// nox: small Quickshell shell for the "Sequoia" desktop.
// Modules are switched on/off in ~/.config/nox/shell.json ("modules"), live.
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
import qs.modules.wallpaper
import qs.modules.corners
import qs.modules.overview
import qs.modules.session
import qs.modules.polkit
import qs.modules.cheatsheet

ShellRoot {
    LazyLoader { active: Config.loaded && Config.moduleEnabled("bar"); component: Bar {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("dock"); component: Dock {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("controlCenter"); component: ControlCenter {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("launcher"); component: Launcher {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("osd"); component: Osd {} }
    // The notification D-Bus server itself is in services/Notifs (same switch).
    LazyLoader { active: Config.loaded && Config.moduleEnabled("notifications"); component: Notifications {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("wallpaper"); component: Background {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("corners"); component: Corners {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("overview"); component: Overview {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("session"); component: Session {} }
    // keyboard shortcuts sheet (on unless modules.cheatsheet is false)
    LazyLoader { active: Config.loaded && Config.opt.modules?.cheatsheet !== false; component: Cheatsheet {} }
    // the polkit agent registers on load (only one agent per session; see modules/polkit)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("polkit"); component: Polkit {} }

    // qs -c nox ipc call controlCenter toggle
    IpcHandler {
        target: "controlCenter"
        function toggle(): void { Panels.toggle("controlCenter"); }
        function open(): void { Panels.open("controlCenter"); }
        function close(): void { Panels.close("controlCenter"); }
    }
    // qs -c nox ipc call dock toggle
    IpcHandler {
        target: "dock"
        // with dock.autohide these reveal/conceal it; otherwise they show/hide it (and its reserved space)
        function toggle(): void { if (Config.opt.dock?.autohide) Panels.dockRevealed = !Panels.dockRevealed; else Panels.dockVisible = !Panels.dockVisible; }
        function open(): void { Panels.dockVisible = true; if (Config.opt.dock?.autohide) Panels.dockRevealed = true; }   // ("show" is reserved by the qs ipc CLI)
        function close(): void { if (Config.opt.dock?.autohide) Panels.dockRevealed = false; else Panels.dockVisible = false; }
    }
    // qs -c nox ipc call popup toggle bar:network   (ids: "controlCenter", "bar:<widgetId>")
    // qs -c nox ipc call popup close                  (closes whatever popup is open)
    IpcHandler {
        target: "popup"
        function toggle(id: string): void { Panels.toggle(id); }
        function open(id: string): void { Panels.open(id); }
        function close(): void { Panels.close(); }
        function current(): string { return Panels.popup; }
    }

    // qs -c nox ipc call overview toggle | open | close
    IpcHandler {
        target: "overview"
        function toggle(): void { Panels.overviewOpen = !Panels.overviewOpen; }
        function open(): void { Panels.overviewOpen = true; }
        function close(): void { Panels.overviewOpen = false; }
    }
    // qs -c nox ipc call cheatsheet toggle | open | close
    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { Panels.cheatsheetOpen = !Panels.cheatsheetOpen; }
        function open(): void { Panels.cheatsheetOpen = true; }
        function close(): void { Panels.cheatsheetOpen = false; }
    }
    // qs -c nox ipc call session toggle | open | close
    IpcHandler {
        target: "session"
        function toggle(): void { Panels.sessionOpen = !Panels.sessionOpen; }
        function open(): void { Panels.sessionOpen = true; }
        function close(): void { Panels.sessionOpen = false; }
    }
    // qs -c nox ipc call wallpaper set <path> | get | fill <cover|fit|stretch|center|tile> | reset
    IpcHandler {
        target: "wallpaper"
        function set(path: string): void { Wallpaper.set(path); }
        function get(): string { return Wallpaper.path; }
        function fill(mode: string): void { Wallpaper.setFill(mode); }
        function reset(): void { Wallpaper.reset(); }
    }
    // qs -c nox ipc call action run <name>   (names: services/Actions.qml) | list
    IpcHandler {
        target: "action"
        function run(name: string): bool { return Actions.run(name); }
        function list(): string { return Object.keys(Actions.table).join(" "); }
    }
    // qs -c nox ipc call hud show "<text>"
    IpcHandler {
        target: "hud"
        function show(text: string): void { Panels.hud(text, "check"); }
    }

    // qs -c nox ipc call layout changed <name>   (sent by nox layout after every change)
    // qs -c nox ipc call layout get | next | prev | set <name>
    IpcHandler {
        target: "layout"
        function changed(name: string): void { Layout.changed(name); }
        function get(): string { return Layout.name; }
        function next(): void { Layout.next(); }
        function prev(): void { Layout.prev(); }
        function set(name: string): void { Layout.set(name); }
    }

    // launcher IPC (toggle|open|close|search|results) lives in modules/launcher/Launcher.qml
    // qs -c nox ipc call notifications toggle       (Notification Center)
    // qs -c nox ipc call notifications toggleDnd    | setDnd true|false | clear | dnd | status
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

    // Hyprland global shortcuts (appid "nox"). Not registered in lint runs (NOX_LINT=1),
    // so a syntax check never competes with the live instance for the same shortcut names.
    LazyLoader {
        active: !Quickshell.env("NOX_LINT")
        component: Scope {
        // shortcuts (appid "nox"): bind with hl.dsp.global("nox:<name>").
        // launcherToggleRelease + launcherToggleReleaseInterrupt = "tap Super to open" (same pattern as ii).
        GlobalShortcut {
            appid: "nox"; name: "launcherToggle"; description: "Toggle the launcher"
            onPressed: Panels.launcherOpen = !Panels.launcherOpen
        }
        GlobalShortcut {
            id: superTap
            appid: "nox"; name: "launcherToggleRelease"; description: "Toggle the launcher when Super is released alone"
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
            appid: "nox"; name: "launcherToggleReleaseInterrupt"; description: "Cancel the Super-tap launcher toggle (bind to a catchall)"
            // the catchall also fires on the Super press itself (Hyprland 0.55.3+): absorb that one
            onPressed: { if (superTap.pressGuard) { superTap.pressGuard = false; return; } superTap.mightTrigger = false; }
        }
        GlobalShortcut {
            appid: "nox"; name: "notificationCenterToggle"; description: "Toggle the Notification Center"
            onPressed: Panels.toggle("notifications")
        }
        GlobalShortcut {
            appid: "nox"; name: "dndToggle"; description: "Toggle Do Not Disturb"
            onPressed: Notifs.toggleDnd()
        }
        GlobalShortcut {
            appid: "nox"; name: "controlCenterToggle"; description: "Toggle the Control Center"
            onPressed: Panels.toggle("controlCenter")
        }
        GlobalShortcut {
            appid: "nox"; name: "overviewToggle"; description: "Toggle Mission Control"
            onPressed: Panels.overviewOpen = !Panels.overviewOpen
        }
        GlobalShortcut {
            appid: "nox"; name: "cheatsheetToggle"; description: "Keyboard shortcuts sheet"
            onPressed: Panels.cheatsheetOpen = !Panels.cheatsheetOpen
        }
        GlobalShortcut {
            appid: "nox"; name: "sessionToggle"; description: "Toggle the power menu"
            onPressed: Panels.sessionOpen = !Panels.sessionOpen
        }
        GlobalShortcut {
            appid: "nox"; name: "clipboardToggle"; description: "Clipboard history in the launcher"
            onPressed: { if (Panels.launcherOpen) Panels.launcherOpen = false; else Panels.openLauncher(":"); }
        }
        GlobalShortcut {
            appid: "nox"; name: "dockToggle"; description: "Reveal / hide the dock"
            onPressed: { if (Config.opt.dock?.autohide) Panels.dockRevealed = !Panels.dockRevealed; else Panels.dockVisible = !Panels.dockVisible; }
        }
        GlobalShortcut {
            appid: "nox"; name: "screenshot"; description: "Region screenshot"
            onPressed: Actions.run("screenshot")
        }
        GlobalShortcut {
            appid: "nox"; name: "recordToggle"; description: "Start / stop screen recording"
            onPressed: Recorder.toggle()
        }
        }
    }
}

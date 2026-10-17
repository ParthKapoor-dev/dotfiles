//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// graphite: small Quickshell shell for the "Sequoia Graphite" desktop.
// Modules are switched on/off in ~/.config/graphite/shell.json ("modules"), live.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.modules.bar
import qs.modules.dock
import qs.modules.controlcenter

ShellRoot {
    LazyLoader { active: Config.moduleEnabled("bar"); component: Bar {} }
    LazyLoader { active: Config.moduleEnabled("dock"); component: Dock {} }
    LazyLoader { active: Config.moduleEnabled("controlCenter"); component: ControlCenter {} }

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
}

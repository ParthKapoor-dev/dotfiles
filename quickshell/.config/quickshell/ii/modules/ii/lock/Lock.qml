pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.panels.lock
import QtQuick
import Quickshell
import Quickshell.Hyprland

LockScreen {
    id: root

    // Monitor name -> workspace id to restore on unlock (set when locking)
    property var savedWorkspaces: ({})

    Timer {
        id: restoreTimer
        interval: 150
        repeat: false
        onTriggered: {
            var batch = ""
            for (var j = 0; j < Quickshell.screens.length; ++j) {
                var monName = Quickshell.screens[j].name
                var wsId = root.savedWorkspaces[monName]
                if (wsId !== undefined) {
                    batch += "dispatch " + HyprCompat.dispatchArg("focusmonitor " + monName, "hl.dsp.focus({ monitor = " + HyprCompat.luaString(monName) + " })") + "; "
                    batch += "dispatch " + HyprCompat.dispatchArg("workspace " + wsId, "hl.dsp.focus({ workspace = " + wsId + " })") + "; "
                }
            }
            if (batch.length > 0) {
                Quickshell.execDetached(["hyprctl", "--batch", batch + "reload"])
            }
        }
    }

    lockSurface: LockSurface {
        context: root.context
    }

    // Single batch for lock and unlock so we don't race multiple hyprctl calls
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked) {
                // Lock: save workspace per monitor and move all to temp workspace in one batch
                var next = {}
                // hyprlang: keyword. Lua refuses keyword -> eval (menu_decel only exists in the old conf)
                var batch = HyprCompat.lua
                    ? "eval hl.animation({ leaf = \"workspaces\", enabled = true, speed = 7, bezier = \"default\", style = \"slidevert\" }); "
                    : "keyword animation workspaces,1,7,menu_decel,slidevert; "
                for (var i = 0; i < Quickshell.screens.length; ++i) {
                    var mon = Quickshell.screens[i].name
                    var mData = HyprlandData.monitors.find(m => m.name === mon)
                    var ws = (mData?.activeWorkspace?.id ?? 1)
                    next[mon] = ws
                    batch += "dispatch " + HyprCompat.dispatchArg("focusmonitor " + mon, "hl.dsp.focus({ monitor = " + HyprCompat.luaString(mon) + " })") + "; "
                    batch += "dispatch " + HyprCompat.dispatchArg("workspace " + (2147483647 - ws), "hl.dsp.focus({ workspace = " + (2147483647 - ws) + " })") + "; "
                }
                root.savedWorkspaces = next
                Quickshell.execDetached(["hyprctl", "--batch", batch + "reload"])
            } else {
                restoreTimer.start()
            }
        }
    }

    // Push everything down (visual only; workspace switch is in Connections above)
    Variants {
        model: Quickshell.screens
        delegate: Scope {
            required property ShellScreen modelData
            property bool shouldPush: GlobalStates.screenLocked
            property string targetMonitorName: modelData.name
            property int verticalMovementDistance: modelData.height
            property int horizontalSqueeze: modelData.width * 0.2
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    id: root
    name: Translation.tr("Game mode")
    toggled: toggled
    icon: "gamepad"

    mainAction: () => {
        root.toggled = !root.toggled
        if (root.toggled) {
            if (HyprCompat.lua)
                Quickshell.execDetached(["hyprctl", "eval", "hl.config({ animations = { enabled = false }, decoration = { shadow = { enabled = false }, blur = { enabled = false }, rounding = 0 }, general = { gaps_in = 0, gaps_out = 0, border_size = 1, allow_tearing = true } })"])
            else
                Quickshell.execDetached(["bash", "-c", `hyprctl --batch "keyword animations:enabled 0; keyword decoration:shadow:enabled 0; keyword decoration:blur:enabled 0; keyword general:gaps_in 0; keyword general:gaps_out 0; keyword general:border_size 1; keyword decoration:rounding 0; keyword general:allow_tearing 1"`])
        } else {
            Quickshell.execDetached(["hyprctl", "reload"])
        }
    }
    Process {
        id: fetchActiveState
        running: true
        command: ["bash", "-c", `test "$(hyprctl getoption animations:enabled -j | jq '.int // (if .bool then 1 else 0 end)')" -ne 0`] // Lua reports bools as "bool"
        onExited: (exitCode, exitStatus) => {
            root.toggled = exitCode !== 0 // Inverted because enabled = nonzero exit
        }
    }
    tooltipText: Translation.tr("Game mode")
}

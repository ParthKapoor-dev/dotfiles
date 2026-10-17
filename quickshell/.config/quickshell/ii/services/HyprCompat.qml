pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Hyprland config-provider compatibility (base0 2026-10-17).
 *
 * Hyprland 0.55 can run a Lua config (hyprland.lua) instead of hyprland.conf.
 * Under Lua, `hyprctl dispatch X` / Hyprland.dispatch(X) is evaluated as the Lua
 * code `return hl.dispatch(X)` (old "workspace 3" syntax is a Lua syntax error),
 * and `hyprctl keyword` is refused ("Use eval"). This singleton detects the
 * provider once (`hyprctl -j status` -> configProvider "lua" | "hyprlang") and lets
 * callers give both spellings, so ii works under either config.
 */
Singleton {
    id: root
    property bool lua: false
    property bool ready: false

    // Hyprland.dispatch with the right syntax. `luaExpr` must evaluate to an
    // hl.dsp.* dispatcher, e.g. `hl.dsp.focus({ workspace = 3 })`.
    function dispatch(legacy, luaExpr) {
        Hyprland.dispatch(root.lua ? luaExpr : legacy);
    }

    // Argument for `hyprctl dispatch ...` / `hyprctl --batch "dispatch ..."`.
    function dispatchArg(legacy, luaExpr) {
        return root.lua ? luaExpr : legacy;
    }

    // Set an option at runtime: `hyprctl keyword` (hyprlang) or Lua hl.config.
    // `luaTable` is the hl.config argument, e.g. `{ cursor = { no_warps = true } }`.
    // Goes through the dispatch socket so ordering with other dispatches is kept.
    function setOption(legacyKey, legacyValue, luaTable) {
        if (root.lua)
            Hyprland.dispatch(`(function() hl.config(${luaTable}) return hl.dsp.no_op() end)()`);
        else
            Hyprland.dispatch(`keyword ${legacyKey} ${legacyValue}`);
    }

    // Lua string literal for arbitrary text (paths, window addresses, monitor names).
    function luaString(s) {
        return JSON.stringify(String(s));
    }

    Process {
        id: detectProc
        running: true
        command: ["hyprctl", "-j", "status"]
        stdout: StdioCollector {
            id: detectCollector
            onStreamFinished: {
                try {
                    root.lua = JSON.parse(detectCollector.text).configProvider === "lua";
                } catch (e) {
                    root.lua = false;
                }
                root.ready = true;
            }
        }
    }
}

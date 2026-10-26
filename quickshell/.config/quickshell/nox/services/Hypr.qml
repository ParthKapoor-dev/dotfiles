pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Hyprland dispatch that works under both config providers. Under a Lua config (hyprland.lua,
// Hyprland 0.55+) `hyprctl dispatch X` / Hyprland.dispatch(X) is evaluated as `return hl.dispatch(X)`,
// so the legacy "workspace 3" syntax is a Lua error. Callers give both spellings; the provider is
// read once from `hyprctl -j status` (configProvider "lua" | "hyprlang").
Singleton {
    id: root
    property bool lua: true            // assume Lua until detection says otherwise (nox targets it)
    property bool ready: false

    function dispatch(legacy, luaExpr) { Hyprland.dispatch(lua ? luaExpr : legacy); }
    function str(s) { return JSON.stringify(String(s)); }
    function addr(a) { a = String(a); return a.startsWith("0x") ? a : "0x" + a; }

    // common dispatchers
    function workspace(ws) {   // number, or "e+1" / "r-1" style relative ids
        const lit = typeof ws === "number" ? ws : str(ws);
        dispatch("workspace " + ws, "hl.dsp.focus({ workspace = " + lit + " })");
    }
    function focusWindow(address) {
        dispatch("focuswindow address:" + addr(address), "hl.dsp.focus({ window = " + str("address:" + addr(address)) + " })");
    }
    function moveToWorkspace(address, ws) {
        dispatch("movetoworkspacesilent " + ws + ",address:" + addr(address),
                 "hl.dsp.window.move({ workspace = " + ws + ", follow = false, window = " + str("address:" + addr(address)) + " })");
    }
    function closeWindow(address) {
        dispatch("closewindow address:" + addr(address), "hl.dsp.window.close({ window = " + str("address:" + addr(address)) + " })");
    }
    // a window property (setprop); value "unset" = back to what the window rules say
    function setProp(address, prop, value) {
        dispatch("setprop address:" + addr(address) + " " + prop + " " + value,
                 "hl.dsp.window.set_prop({ window = " + str("address:" + addr(address)) + ", prop = " + str(prop) + ", value = " + str(value) + " })");
    }
    function exit() { dispatch("exit", "hl.dsp.exit()"); }
    // active-window actions (menu bar Window menu)
    function toggleFloat() { dispatch("togglefloating", "hl.dsp.window.float({ action = \"toggle\" })"); }
    function fullscreen(mode) {   // "maximized" | "fullscreen"
        dispatch("fullscreen " + (mode === "maximized" ? 1 : 0), "hl.dsp.window.fullscreen({ mode = " + str(mode) + " })");
    }
    function pin() { dispatch("pin", "hl.dsp.window.pin()"); }
    function center() { dispatch("centerwindow", "hl.dsp.window.center()"); }
    function minimize() { dispatch("movetoworkspacesilent special:minimized", "hl.dsp.window.move({ workspace = \"special:minimized\", follow = false })"); }
    function moveActiveTo(ws) { dispatch("movetoworkspacesilent " + ws, "hl.dsp.window.move({ workspace = " + ws + ", follow = false })"); }
    function killActive() { dispatch("killactive", "hl.dsp.window.kill()"); }

    Process {
        running: true
        command: ["hyprctl", "-j", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.lua = JSON.parse(text).configProvider === "lua"; } catch (e) { root.lua = false; }
                root.ready = true;
            }
        }
    }
}

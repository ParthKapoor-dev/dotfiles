pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.core

// Pinned snippets (texts, links, profile URLs...) for the launcher's "Pinned" provider ("'"),
// kept in ~/.local/state/nox/pins.json as { pins: [{ id, name, text, added }] } in the user's order.
// Private: lives in the state dir (not in the dotfiles repo).
// paste(pin): the text goes on the clipboard and Ctrl+V (Ctrl+Shift+V in terminals) is sent to the
// window that was focused, once the launcher has closed; copy(pin) only puts it on the clipboard.
Singleton {
    id: root
    readonly property var list: state.data.pins ?? []
    readonly property bool loaded: state.loaded

    function save(pins) { state.data = Object.assign({}, state.data, { pins }); state.save(); }
    function find(id) { return list.find(p => p.id === id) ?? null; }
    function add(name, text) {
        text = String(text ?? "");
        if (!text.trim()) return null;
        const old = list.find(p => p.text === text);
        if (old) return old;
        const p = { id: Date.now().toString(36) + Math.floor(Math.random() * 1e4).toString(36),
                    name: String(name || text).replace(/\s+/g, " ").trim().slice(0, 80), text, added: Date.now() };
        save(list.concat([p]));
        return p;
    }
    function update(id, fields) { save(list.map(p => p.id === id ? Object.assign({}, p, fields) : p)); }
    function remove(id) { save(list.filter(p => p.id !== id)); }
    function move(id, d) {
        const i = list.findIndex(p => p.id === id), j = i + d;
        if (i < 0 || j < 0 || j >= list.length) return false;
        const l = list.slice();
        [l[i], l[j]] = [l[j], l[i]];
        save(l);
        return true;
    }

    readonly property var terminals: /ghostty|kitty|foot|alacritty|wezterm|konsole|terminal|xterm|tilix|st-256color/i
    function copy(p) { Quickshell.execDetached(["wl-copy", "--", p.text]); }
    function paste(p) {
        const t = Hyprland.activeToplevel;
        const cls = t?.lastIpcObject?.class ?? t?.wayland?.appId ?? "";
        pending = { text: p.text, addr: t?.address ?? "", term: terminals.test(cls) };
        Quickshell.execDetached(["wl-copy", "--", p.text]);
        pasteTimer.restart();
    }
    property var pending: null
    // the launcher's layer has to give the keyboard back first
    Timer {
        id: pasteTimer
        interval: 140
        onTriggered: {
            const q = root.pending;
            root.pending = null;
            if (q) root.sendPaste(q.addr, q.term);
        }
    }
    // Ctrl+V (Ctrl+Shift+V in terminals) to a window (address; "" = the focused one). Also used by
    // voice typing (services/Voice).
    function sendPaste(addr, term) {
        const mods = term ? "CTRL SHIFT" : "CTRL";
        const w = addr ? "address:" + Hypr.addr(addr) : "";
        Hypr.dispatch("sendshortcut " + mods + ", V, " + w,
                      "hl.dsp.send_shortcut({ mods = \"" + mods + "\", key = \"V\"" + (w ? ", window = " + Hypr.str(w) : "") + " })");
    }

    JsonState { id: state; path: Paths.state("pins") }
}

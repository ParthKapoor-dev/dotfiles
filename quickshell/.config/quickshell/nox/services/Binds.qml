pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// The LIVE Hyprland bind table (`hyprctl -j binds`), labelled and grouped. Shared by the keyboard
// shortcuts sheet (modules/cheatsheet merges rows for display) and the launcher's command palette
// (runs a bind and shows its keycaps). refresh() re-reads it; callers do that on open, so it never
// drifts from the Lua config (and Lua bind refs stay current across `hyprctl reload`).
// Labels: the bind's own description (Lua `desc = "…"`), else shell.json cheatsheet.labels (merged
// over the defaults below; keys "SUPER+SHIFT+Q", "#" = any digit 1-0). Binds with neither are left
// out unless cheatsheet.showUnlabeled. Groups: cheatsheet.groups { "<label>": "<group>" } overrides,
// else keyword heuristics.
// entries: one per bind, in hyprctl order: { label, group, mods: ["SUPER", …], key (upper case;
//   "#" for a digit-row bind), digit ("" or "1".."0"), keys: [keycap labels], combo ("Super ⇧ S"),
//   mouse (drag bind), dispatcher, arg }
// run(e): runs a bind's action. Lua binds (dispatcher "__lua") hold a function in the Lua
// registry under `arg`, called through `hyprctl eval`; legacy binds go through `hyprctl dispatch`.
Singleton {
    id: root
    readonly property var opts: Config.opt.cheatsheet ?? ({})
    property var entries: []
    property real readAt: 0         // ms epoch of the last successful read
    signal loaded()

    function refresh() { if (!reader.running) reader.running = true; }
    // re-read unless the table is younger than maxAge ms
    function refreshIfOlder(maxAge) { if (Date.now() - readAt > maxAge) refresh(); }

    readonly property var defaultLabels: ({
        "SUPER+RETURN": "Terminal", "SUPER+T": "Terminal", "CTRL+ALT+T": "Terminal",
        "SUPER+E": "Files", "SUPER+W": "Browser", "SUPER+C": "Code editor",
        "SUPER+X": "Neovim", "SUPER+I": "System settings", "CTRL+SUPER+V": "Volume mixer",
        "CTRL+SHIFT+ESCAPE": "System monitor", "SUPER+SPACE": "Launcher",
        "SUPER+ALT+N": "Control Center", "CTRL+SUPER+SLASH": "Edit shell config",
        "CTRL+SUPER+ALT+SLASH": "Edit custom binds",
        "SUPER+Q": "Close window", "ALT+F4": "Close window", "SUPER+SHIFT+ALT+Q": "Force kill window",
        "SUPER+LEFT": "Focus left", "SUPER+RIGHT": "Focus right", "SUPER+UP": "Focus up", "SUPER+DOWN": "Focus down",
        "SUPER+SHIFT+LEFT": "Move window left", "SUPER+SHIFT+RIGHT": "Move window right",
        "SUPER+SHIFT+UP": "Move window up", "SUPER+SHIFT+DOWN": "Move window down",
        "SUPER+ALT+SPACE": "Float / tile window", "SUPER+D": "Maximize", "SUPER+F": "Fullscreen",
        "SUPER+ALT+F": "Fake fullscreen", "SUPER+P": "Pin window",
        "SUPER+MOUSE:272": "Move window (drag)", "SUPER+MOUSE:273": "Resize window (drag)",
        "CTRL+SUPER+BACKSLASH": "Resize to 640×480",
        "SUPER+#": "Go to desktop", "SUPER+SHIFT+#": "Move window to desktop",
        "CTRL+SUPER+RIGHT": "Next desktop", "CTRL+SUPER+LEFT": "Previous desktop",
        "SUPER+PAGE_DOWN": "Next desktop", "SUPER+PAGE_UP": "Previous desktop",
        "SUPER+ALT+PAGE_DOWN": "Move window to next desktop", "SUPER+ALT+PAGE_UP": "Move window to previous desktop",
        "SUPER+S": "Scratchpad", "SUPER+ALT+S": "Send to scratchpad",
        "SUPER+ALT+RIGHT": "Move desktop to next monitor", "SUPER+ALT+LEFT": "Move desktop to previous monitor",
        "SUPER+MINUS": "Zoom out", "SUPER+EQUAL": "Zoom in",
        "XF86AUDIORAISEVOLUME": "Volume up", "XF86AUDIOLOWERVOLUME": "Volume down",
        "XF86AUDIOMUTE": "Mute", "XF86AUDIOMICMUTE": "Mute microphone",
        "XF86MONBRIGHTNESSUP": "Brightness up", "XF86MONBRIGHTNESSDOWN": "Brightness down",
        "XF86AUDIOPLAY": "Play / pause", "SUPER+SHIFT+P": "Play / pause",
        "XF86AUDIONEXT": "Next track", "SUPER+SHIFT+N": "Next track",
        "XF86AUDIOPREV": "Previous track", "SUPER+SHIFT+B": "Previous track",
        "PRINT": "Screenshot to clipboard", "CTRL+PRINT": "Screenshot to file"
    })
    readonly property var labels: Object.assign({}, defaultLabels, opts.labels ?? {})

    // modmask bits (Hyprland): SHIFT 1, CAPS 2, CTRL 4, ALT 8, MOD2 16, MOD3 32, SUPER 64, MOD5 128
    function mods(m) {
        const out = [];
        if (m & 64) out.push("SUPER");
        if (m & 4) out.push("CTRL");
        if (m & 8) out.push("ALT");
        if (m & 1) out.push("SHIFT");
        return out;
    }
    readonly property var digitCodes: ({ 10: "1", 11: "2", 12: "3", 13: "4", 14: "5", 15: "6", 16: "7", 17: "8", 18: "9", 19: "0" })
    readonly property var pretty: ({
        SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "⇧", RETURN: "↩", SPACE: "Space", LEFT: "←", RIGHT: "→",
        UP: "↑", DOWN: "↓", BACKSLASH: "\\", SLASH: "/", PERIOD: ".", COMMA: ",", MINUS: "−", EQUAL: "=",
        BRACKETLEFT: "[", BRACKETRIGHT: "]", SEMICOLON: ";", APOSTROPHE: "'", ESCAPE: "Esc", DELETE: "Del",
        TAB: "Tab", PAGE_UP: "PgUp", PAGE_DOWN: "PgDn", PRINT: "Print", "MOUSE:272": "Left drag",
        "MOUSE:273": "Right drag", "MOUSE:274": "Middle drag", MOUSE_UP: "Scroll ↑", MOUSE_DOWN: "Scroll ↓",
        XF86AUDIORAISEVOLUME: "Vol +", XF86AUDIOLOWERVOLUME: "Vol −", XF86AUDIOMUTE: "Mute", XF86AUDIOMICMUTE: "Mic mute",
        XF86MONBRIGHTNESSUP: "Bright +", XF86MONBRIGHTNESSDOWN: "Bright −", XF86AUDIOPLAY: "Play", XF86AUDIOPAUSE: "Pause",
        XF86AUDIONEXT: "Next", XF86AUDIOPREV: "Prev"
    })
    function groupFor(label) {
        const o = (opts.groups ?? {})[label];
        if (o) return o;
        const l = label.toLowerCase();
        if (/screenshot|record|ocr|lens|region|color picker/.test(l)) return "Screenshots";
        if (/desktop|workspace|scratchpad/.test(l)) return "Desktops";
        if (/window|focus|float|fullscreen|maximi|\bpin\b|layout|split|resize|kill|zoom/.test(l)) return "Windows";
        if (/launcher|overview|mission|notification|control center|dock|clipboard|emoji|wallpaper|shell|session|disturb/.test(l)) return "Shell";
        if (/volume|mute|\bmic\b|track|play|pause|brightness|microphone|media/.test(l)) return "Media";
        if (/terminal|browser|files|editor|neovim|settings|mixer|monitor|app/.test(l)) return "Apps";
        return "System";
    }

    function keyName(a) { return root.pretty[a] ?? (a.length === 1 ? a : a.charAt(0) + a.slice(1).toLowerCase()); }

    // a short delay first, so the launcher (or whatever ran it) has given the keyboard back and
    // focus / window binds act on the window the user was in
    function run(e) {
        if (!e || e.mouse) return false;
        const cmd = e.dispatcher === "__lua"
            ? ["hyprctl", "eval", "local f = debug.getregistry()[" + (parseInt(e.arg) || 0) + "]; if type(f) == 'function' then f() end"]
            : ["hyprctl", "dispatch", e.dispatcher].concat(e.arg ? [e.arg] : []);
        Quickshell.execDetached(["sh", "-c", "sleep 0.15; exec \"$@\"", "sh"].concat(cmd));
        return true;
    }

    Process {
        id: reader
        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(text); } catch (e) { console.warn("nox: binds: bad hyprctl output", e); return; }
                const out = [];
                for (const b of list) {
                    if (b.submap && b.submap !== "global" && b.submap !== "") continue;
                    if (b.catch_all) continue;
                    if ((b.description || "").startsWith("Internal:")) continue;   // plumbing binds (Super-tap cancel etc.)
                    const m = root.mods(b.modmask ?? 0);
                    let key = (b.key || "").toUpperCase();
                    let digit = "", descLabel = "";
                    if (!key && b.keycode) {
                        if (root.digitCodes[b.keycode] !== undefined) digit = root.digitCodes[b.keycode];
                        else continue;                       // keypad / raw codes: duplicates of the above
                    } else if (!key && !b.keycode && !b.catch_all) {
                        // 0.55.4 reports "code:N" binds as key "", keycode 0 (digit row / keypad); the
                        // number lives only in the description: "Go to desktop 3" -> label + digit
                        const mm = /^(.*) (\d+)$/.exec(b.description || "");
                        if (mm) { descLabel = mm[1]; digit = mm[2] === "10" ? "0" : mm[2]; }
                        else continue;                       // keycode-only alias without a number (keypad zoom etc.): the named-key bind is listed
                    }
                    if (!key && !digit) continue;
                    if (key === "SUPER_L" || key === "SUPER_R") { if (m.length > 1 || !b.description) continue; key = ""; }
                    const combo = m.concat([digit ? "#" : key]).filter(x => x).join("+");
                    const exact = m.concat([digit || key]).filter(x => x).join("+");
                    let label = descLabel || (b.has_description || b.description ? b.description : "");
                    if (!label) label = root.labels[exact] ?? root.labels[combo] ?? "";
                    if (!label && !root.opts.showUnlabeled) continue;
                    if (!label) label = (b.dispatcher === "__lua" ? "Lua bind " : b.dispatcher + " ") + (b.arg ?? "");
                    const keys = m.map(x => root.pretty[x] ?? x).concat(digit ? [digit] : key ? [root.keyName(key)] : []);
                    out.push({
                        label, group: root.groupFor(label), mods: m, key: digit ? "#" : key, digit, keys, combo: keys.join(" "),
                        mouse: !!b.mouse || key.startsWith("MOUSE"), dispatcher: b.dispatcher ?? "", arg: String(b.arg ?? "")
                    });
                }
                root.entries = out;
                root.readAt = Date.now();
                root.loaded();
            }
        }
    }
}

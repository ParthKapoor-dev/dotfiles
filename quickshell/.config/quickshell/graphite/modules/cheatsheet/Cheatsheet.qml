pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components

// Keyboard shortcuts sheet (mock #cheats / .ch): centred glass panel over a dimmed screen, three
// columns of groups, each row = what it does + keycaps. Source of truth is the LIVE bind table
// (`hyprctl -j binds`, read on every open), so it never drifts from the Lua config.
// Labels: the bind's own description (Lua `desc = "…"`), else shell.json cheatsheet.labels
// (merged over the defaults below; keys "SUPER+SHIFT+Q", "#" = any digit 1-0). Binds with neither
// are hidden unless cheatsheet.showUnlabeled. Same label + mods with digit keys merge to "1–0".
// Groups: cheatsheet.groups { "<label>": "<group>" } overrides, else keyword heuristics.
// Type to filter, Esc closes. `qs -c graphite ipc call cheatsheet toggle`.
Scope {
    id: root
    readonly property var opts: Config.opt.cheatsheet ?? ({})
    readonly property bool open: Panels.cheatsheetOpen
    property bool shown: false
    property string query: ""
    property var binds: []          // [{ label, group, keys: [chip…], combo }]
    onOpenChanged: {
        if (open) { hideTimer.stop(); query = ""; reader.running = true; shown = true; }
        else hideTimer.restart();
    }
    Timer { id: hideTimer; interval: Theme.durFade + 40; onTriggered: root.shown = false }

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
    readonly property var groupOrder: ["Apps", "Shell", "Windows", "Desktops", "Screenshots", "Media", "System"]

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
    function groupFor(label, key) {
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

    Process {
        id: reader
        command: ["hyprctl", "-j", "binds"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(text); } catch (e) { console.warn("graphite: cheatsheet: bad hyprctl output", e); return; }
                const rows = [], byKey = {};
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
                        else digit = "?";
                    }
                    if (!key && !digit) continue;
                    if (key === "SUPER_L" || key === "SUPER_R") { if (m.length > 1 || !b.description) continue; key = ""; }
                    const combo = m.concat([digit ? "#" : key]).filter(x => x).join("+");
                    const exact = m.concat([digit || key]).filter(x => x).join("+");
                    let label = descLabel || (b.has_description || b.description ? b.description : "");
                    if (!label) label = root.labels[exact] ?? root.labels[combo] ?? "";
                    if (!label && !root.opts.showUnlabeled) continue;
                    if (!label) label = (b.dispatcher === "__lua" ? "Lua bind " : b.dispatcher + " ") + (b.arg ?? "");
                    // merge: same label + mods (digits -> "1–0"; aliases -> "or")
                    const id = label + "|" + m.join("+") + (digit ? "|#" : "");
                    const shownKey = digit ? "#" : key;
                    if (byKey[id]) {
                        const r = byKey[id];
                        if (digit) { if (!r.digits.includes(digit)) r.digits.push(digit); continue; }
                        if (!r.alts.includes(shownKey) && r.alts.length < 2) r.alts.push(shownKey);
                        continue;
                    }
                    const r = { label, mods: m, alts: [shownKey], digits: digit ? [digit] : [], group: root.groupFor(label, key) };
                    byKey[id] = r; rows.push(r);
                }
                // alias rows with different mods but the same label: keep the first, add "or" text
                const out = [];
                const seen = {};
                for (const r of rows) {
                    const keys = r.mods.map(x => root.pretty[x] ?? x);
                    let k = r.alts.filter(a => a !== "").map(a => a === "#" ? (r.digits.includes("?") ? "1–0" : r.digits.length > 1 ? r.digits.sort((a, b) => (a === "0") - (b === "0") || a - b)[0] + "–" + r.digits[r.digits.length - 1] : r.digits[0]) : (root.pretty[a] ?? (a.length === 1 ? a : a.charAt(0) + a.slice(1).toLowerCase())));
                    const chips = keys.concat([k.join(" / ")]).filter(x => x !== "");
                    const sig = r.label;
                    if (seen[sig]) { if (!seen[sig].alias) seen[sig].alias = chips.join("+"); continue; }
                    const row = { label: r.label, group: r.group, keys: chips, alias: "", combo: chips.join(" ") };
                    seen[sig] = row; out.push(row);
                }
                root.binds = out;
            }
        }
    }

    LazyLoader {
        active: root.shown
        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "graphite:cheatsheet"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            // mock #cheats backdrop rgba(0,0,0,.28)
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.28)
                opacity: root.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                MouseArea { anchors.fill: parent; onClicked: Panels.cheatsheetOpen = false }
            }

            readonly property var filtered: {
                const q = root.query.trim().toLowerCase();
                return q ? root.binds.filter(b => (b.label + " " + b.combo + " " + b.alias + " " + b.group).toLowerCase().includes(q)) : root.binds;
            }
            // groups in order, balanced into 3 columns by row count
            readonly property var columns: {
                const groups = [];
                for (const g of root.groupOrder.concat(Object.values(root.opts.groups ?? {}))) {
                    if (groups.some(x => x.name === g)) continue;
                    const rows = filtered.filter(b => b.group === g);
                    if (rows.length) groups.push({ name: g, rows });
                }
                const cols = [[], [], []], h = [0, 0, 0];
                for (const g of groups) {
                    const i = h.indexOf(Math.min(...h));
                    cols[i].push(g); h[i] += g.rows.length + 2;
                }
                return cols;
            }

            RectangularShadow {
                anchors.fill: panel; radius: panel.radius
                offset.y: 40; blur: 100; spread: -10
                color: Qt.rgba(0, 0, 0, 0.55)
                opacity: panel.opacity
            }
            Glass {
                id: panel
                strong: true
                anchors.centerIn: parent
                width: Math.min(1060, win.width - 64)
                height: Math.min(760, win.height - 96, content.implicitHeight + 42)
                radius: Theme.square ? 6 : 20
                opacity: root.open ? 1 : 0
                scale: root.open ? 1 : 0.98
                Behavior on opacity { NumberAnimation { duration: root.open ? Theme.durPop : Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on scale { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                Item {
                    id: content
                    x: 26; y: 22
                    width: parent.width - 52; height: parent.height - 42
                    implicitHeight: top.height + 14 + grid.implicitHeight
                    // header (mock .ch-top): title, search, close pill
                    Item {
                        id: top
                        width: parent.width; height: 30
                        GText { id: title; anchors.verticalCenter: parent.verticalCenter; text: "Keyboard"; font.family: Theme.fontDisplay; font.pixelSize: 20; font.weight: Font.DemiBold }
                        Rectangle {
                            anchors.left: title.right; anchors.leftMargin: 16
                            anchors.right: closePill.left; anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            height: 28
                            radius: Theme.square ? 3 : 8
                            color: Theme.fill
                            border.width: input.activeFocus ? 1 : 0
                            border.color: Theme.white(0.18)
                            Glyph { id: sIcon; x: 9; anchors.verticalCenter: parent.verticalCenter; name: "search"; size: 13; color: Theme.label2 }
                            TextInput {
                                id: input
                                anchors.left: sIcon.right; anchors.leftMargin: 7; anchors.right: parent.right; anchors.rightMargin: 9
                                anchors.verticalCenter: parent.verticalCenter
                                focus: true
                                color: Theme.label
                                font.family: Theme.fontUi; font.pixelSize: 13
                                selectionColor: Theme.accent
                                text: root.query
                                onTextEdited: root.query = text
                                Keys.onEscapePressed: { if (text) root.query = ""; else Panels.cheatsheetOpen = false; }
                                Component.onCompleted: forceActiveFocus()
                                GText { visible: !input.text; text: "Filter shortcuts…"; color: Theme.label3; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: 13 }
                            }
                        }
                        PillButton {
                            id: closePill
                            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                            text: "Close  esc"
                            onClicked: Panels.cheatsheetOpen = false
                        }
                    }
                    Flickable {
                        id: grid
                        y: top.height + 14
                        width: parent.width; height: parent.height - y
                        implicitHeight: cols.implicitHeight
                        contentHeight: cols.implicitHeight
                        clip: contentHeight > height
                        boundsBehavior: Flickable.StopAtBounds
                        Row {
                            id: cols
                            width: grid.width
                            spacing: 30
                            Repeater {
                                model: win.columns
                                Column {
                                    id: colItem
                                    required property var modelData
                                    width: (cols.width - 60) / 3
                                    Repeater {
                                        model: colItem.modelData
                                        Column {
                                            id: grp
                                            required property var modelData
                                            width: colItem.width
                                            // mock .ch h4
                                            GText {
                                                topPadding: 12; bottomPadding: 4
                                                text: grp.modelData.name
                                                font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
                                                font.pixelSize: Theme.labelsMono ? 10 : 11
                                                font.weight: Theme.labelsMono ? Font.Medium : Font.DemiBold
                                                font.capitalization: Font.AllUppercase
                                                font.letterSpacing: Theme.labelsMono ? 0.8 : 0.66
                                                secondary: true
                                            }
                                            Repeater {
                                                model: grp.modelData.rows
                                                // mock .ch-r: 27px, label left, keycaps right, 0.5px separator
                                                Item {
                                                    id: rowItem
                                                    required property var modelData
                                                    width: grp.width; height: Math.max(27, lab.implicitHeight + 8)
                                                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 0.5; color: Theme.sep }
                                                    Rectangle {
                                                        anchors.fill: parent; anchors.bottomMargin: 1
                                                        radius: Theme.square ? 2 : 4
                                                        color: Theme.fill
                                                        opacity: rowMouse.containsMouse ? 1 : 0
                                                        Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
                                                    }
                                                    MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true }
                                                    GText {
                                                        id: lab
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: parent.width - chips.width - 10
                                                        text: rowItem.modelData.label
                                                        font.pixelSize: 13
                                                    }
                                                    Row {
                                                        id: chips
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        spacing: 3
                                                        Repeater {
                                                            model: rowItem.modelData.keys
                                                            Keycap { required property string modelData; text: modelData }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        GText {
                            visible: win.filtered.length === 0
                            y: 20
                            text: root.binds.length ? "No shortcut matches “" + root.query + "”" : "Reading binds…"
                            secondary: true
                        }
                    }
                }
            }
        }
    }
}

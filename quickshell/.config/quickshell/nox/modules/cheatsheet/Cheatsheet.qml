pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Keyboard shortcuts sheet (mock #cheats / .ch): centred glass panel over a dimmed screen, three
// columns of groups, each row = what it does + keycaps. Source of truth is the LIVE bind table
// (services/Binds: `hyprctl -j binds`, read on every open), so it never drifts from the Lua config.
// Labels, groups and cheatsheet.labels / groups / showUnlabeled are handled there (shared with the
// launcher's command palette). Same label + mods with digit keys merge to "1–0".
// Type to filter, Esc closes. `qs -c nox ipc call cheatsheet toggle`.
Scope {
    id: root
    readonly property var opts: Config.opt.cheatsheet ?? ({})
    readonly property bool open: Panels.cheatsheetOpen
    property bool shown: false
    property string query: ""
    property var binds: []          // [{ label, group, keys: [chip…], combo }]
    onOpenChanged: {
        if (open) { hideTimer.stop(); query = ""; Binds.refresh(); shown = true; }
        else hideTimer.restart();
    }
    Timer { id: hideTimer; interval: Theme.durFade + 40; onTriggered: root.shown = false }

    readonly property var groupOrder: ["Apps", "Shell", "Windows", "Desktops", "Screenshots", "Media", "System"]

    // one row per action: same label + mods with digit keys merge to "1–0", aliases add "or" text
    function build(entries) {
        const rows = [], byKey = {};
        for (const e of entries) {
            const id = e.label + "|" + e.mods.join("+") + (e.digit ? "|#" : "");
            if (byKey[id]) {
                const r = byKey[id];
                if (e.digit) { if (!r.digits.includes(e.digit)) r.digits.push(e.digit); continue; }
                if (!r.alts.includes(e.key) && r.alts.length < 2) r.alts.push(e.key);
                continue;
            }
            const r = { label: e.label, mods: e.mods, alts: [e.key], digits: e.digit ? [e.digit] : [], group: e.group };
            byKey[id] = r; rows.push(r);
        }
        // alias rows with different mods but the same label: keep the first, add "or" text
        const out = [];
        const seen = {};
        for (const r of rows) {
            const keys = r.mods.map(x => Binds.pretty[x] ?? x);
            let k = r.alts.filter(a => a !== "").map(a => a === "#" ? (r.digits.includes("?") ? "1–0" : r.digits.length > 1 ? r.digits.sort((a, b) => (a === "0") - (b === "0") || a - b)[0] + "–" + r.digits[r.digits.length - 1] : r.digits[0]) : Binds.keyName(a));
            const chips = keys.concat([k.join(" / ")]).filter(x => x !== "");
            const sig = r.label;
            if (seen[sig]) { if (!seen[sig].alias) seen[sig].alias = chips.join("+"); continue; }
            const row = { label: r.label, group: r.group, keys: chips, alias: "", combo: chips.join(" ") };
            seen[sig] = row; out.push(row);
        }
        return out;
    }
    Connections {
        target: Binds
        function onLoaded() { root.binds = root.build(Binds.entries); }
    }

    LazyLoader {
        active: root.shown
        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "nox:cheatsheet"
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

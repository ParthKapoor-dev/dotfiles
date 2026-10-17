pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Power menu (namespace graphite:session): dimmed full screen, a row of glass tiles (Lock,
// Log Out, Sleep, Restart, Shut Down; shell.json session.items). Destructive items
// (session.confirm) need a second click / Enter: the tile turns red and asks again.
// Keys: ←/→/Tab, Enter, Esc, or the first letter. `qs -c graphite ipc call session toggle`.
Scope {
    id: root
    readonly property bool open: Panels.sessionOpen
    property bool shown: false
    property int sel: 0
    property string confirming: ""
    onOpenChanged: {
        if (open) { hideTimer.stop(); sel = 0; confirming = ""; shown = true; }
        else hideTimer.restart();
    }
    Timer { id: hideTimer; interval: Theme.durFade + 50; onTriggered: root.shown = false }

    readonly property var defs: ({
        lock: { label: "Lock", glyph: "lock", key: "l" },
        logout: { label: "Log Out", glyph: "logout", key: "o" },
        sleep: { label: "Sleep", glyph: "moon", key: "s" },
        restart: { label: "Restart", glyph: "restart", key: "r" },
        poweroff: { label: "Shut Down", glyph: "power", key: "p" }
    })
    readonly property var items: (Config.opt.session?.items ?? ["lock", "logout", "sleep", "restart", "poweroff"]).filter(i => defs[i])
    readonly property var confirmSet: Config.opt.session?.confirm ?? ["logout", "restart", "poweroff"]

    function activate(i) {
        const id = items[i];
        if (!id) return;
        sel = i;
        if (confirmSet.indexOf(id) !== -1 && confirming !== id) { confirming = id; return; }
        Panels.sessionOpen = false;
        Qt.callLater(() => Actions.run(id));
    }

    LazyLoader {
        active: root.shown
        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "graphite:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, Theme.glassOpaque ? 0.82 : 0.55)
                opacity: root.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                MouseArea { anchors.fill: parent; onClicked: Panels.sessionOpen = false }
            }

            Item {
                id: content
                anchors.centerIn: parent
                width: row.width; height: col.height
                opacity: root.open ? 1 : 0
                scale: root.open ? 1 : 0.97
                Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on scale { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                focus: true
                Keys.onPressed: e => {
                    const n = root.items.length;
                    if (e.key === Qt.Key_Escape) { if (root.confirming) root.confirming = ""; else Panels.sessionOpen = false; }
                    else if (e.key === Qt.Key_Right || e.key === Qt.Key_Tab) { root.sel = (root.sel + 1) % n; root.confirming = ""; }
                    else if (e.key === Qt.Key_Left || e.key === Qt.Key_Backtab) { root.sel = (root.sel - 1 + n) % n; root.confirming = ""; }
                    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) root.activate(root.sel);
                    else {
                        const i = root.items.findIndex(id => root.defs[id].key === e.text.toLowerCase());
                        if (i >= 0) root.activate(i); else return;
                    }
                    e.accepted = true;
                }

                Column {
                    id: col
                    spacing: 22
                    GText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.confirming ? root.defs[root.confirming].label + " now?" : "Session"
                        font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontDisplay
                        font.pixelSize: Theme.labelsMono ? 13 : 22
                        font.weight: Theme.labelsMono ? Font.Medium : Font.DemiBold
                        font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase
                        font.letterSpacing: Theme.labelsMono ? 2.6 : 0
                        color: root.confirming ? Theme.red : Theme.label
                    }
                    Row {
                        id: row
                        spacing: 14
                        Repeater {
                            model: root.items
                            Item {
                                id: tile
                                required property string modelData
                                required property int index
                                readonly property var d: root.defs[modelData]
                                readonly property bool selected: root.sel === index
                                readonly property bool asking: root.confirming === modelData
                                width: 104; height: 112
                                RectangularShadow {
                                    anchors.fill: box; radius: box.radius
                                    offset.y: 14; blur: 40; spread: -6
                                    color: Qt.rgba(0, 0, 0, 0.45)
                                }
                                Glass {
                                    id: box
                                    menu: true
                                    anchors.fill: parent
                                    radius: Theme.square ? 6 : 18
                                    color: tile.asking ? Theme.rgba(Theme.t.color.red, 0.9) : tile.selected || ma.containsMouse ? Theme.rgba(Theme.t.color.raised, 0.95) : Theme.menuGlass
                                    border.color: tile.selected ? Theme.white(0.35) : Theme.rim
                                    border.width: tile.selected ? 1 : Theme.rimWidth
                                    Behavior on color { ColorAnimation { duration: Theme.durPop } }
                                }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 10
                                    Glyph { anchors.horizontalCenter: parent.horizontalCenter; name: tile.d.glyph; size: 28; color: tile.asking ? "white" : Theme.label }
                                    GText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: tile.asking ? "Confirm" : tile.d.label
                                        color: tile.asking ? "white" : Theme.label
                                        font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
                                        font.pixelSize: Theme.square ? 11 : 13
                                        font.capitalization: Theme.square ? Font.AllUppercase : Font.MixedCase
                                        font.letterSpacing: Theme.square ? 0.66 : 0
                                    }
                                }
                                MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onEntered: { if (root.sel !== tile.index) root.confirming = ""; root.sel = tile.index; } onClicked: root.activate(tile.index) }
                            }
                        }
                    }
                    GText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.confirming ? "Press ↵ or click again to confirm · esc to cancel" : "←  →  choose   ·   ↵ select   ·   esc close"
                        small: true; secondary: true
                    }
                }
            }
        }
    }
}

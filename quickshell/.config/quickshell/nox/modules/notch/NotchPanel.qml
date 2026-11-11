pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// The open notch (mock #Lp): AGENTS · REPLAY · LAPS · RECEIPTS, plus CYCLE (rotate the views every
// notch.cycleSeconds while open and untouched). Keys: Tab / 1-4 views · ↑↓ select · Enter jump ·
// R steer / reply · P replay the selected session · Y / Shift+Y / Backspace answer its request ·
// D dismiss its done card · Esc closes (or leaves the steer field first).
FocusScope {
    id: p
    property string view: "agents"
    property string selId: ""
    property bool cycling: Config.opt.notch?.cycle ?? false
    property real now: Date.now()
    property string steerId: ""
    readonly property var views: ["agents", "replay", "laps", "receipts"]
    readonly property var list: {
        const r = Agents.rank;
        return Agents.alive.slice().sort((a, b) => (r[a.status] - r[b.status]) || (b.since - a.since));
    }
    readonly property int sel: Math.max(0, list.findIndex(s => s.id === selId))
    readonly property var cur: list[sel] ?? null
    signal close()
    implicitWidth: 640
    property real topPad: 42
    implicitHeight: topPad + tabs.height + stack.height + 14

    onListChanged: if (!list.find(s => s.id === selId)) selId = list[0]?.id ?? ""
    function select(i) { if (list.length) selId = list[(i + list.length) % list.length].id; }
    function go(v) { view = v; steerId = ""; forceActiveFocus(); }
    function replayOf(id) { if (id) selId = id; go("replay"); }

    Timer {
        interval: (Config.opt.notch?.cycleSeconds ?? 5) * 1000
        repeat: true
        running: p.cycling && p.visible && p.steerId === ""
        onTriggered: p.view = p.views[(p.views.indexOf(p.view) + 1) % p.views.length]
    }

    Keys.onPressed: event => {
        const k = event.key, sh = event.modifiers & Qt.ShiftModifier;
        if (k === Qt.Key_Escape) { if (steerId) steerId = ""; else p.close(); }
        else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) go(views[(views.indexOf(view) + (k === Qt.Key_Backtab || sh ? 3 : 1)) % 4]);
        else if (k >= Qt.Key_1 && k <= Qt.Key_4) go(views[k - Qt.Key_1]);
        else if (view === "agents" && (k === Qt.Key_Down || k === Qt.Key_J)) select(sel + 1);
        else if (view === "agents" && (k === Qt.Key_Up || k === Qt.Key_K)) select(sel - 1);
        else if (view === "agents" && (k === Qt.Key_Return || k === Qt.Key_Enter) && cur) { Agents.jump(cur.id); p.close(); }
        else if (k === Qt.Key_R && cur) { steerId = cur.id; }
        else if (k === Qt.Key_P && cur) go("replay");
        else if (k === Qt.Key_Y && cur && Agents.reqFor(cur.id)) Agents.answer(cur.id, sh ? "always" : "allow");
        else if (k === Qt.Key_Backspace && cur && Agents.reqFor(cur.id)) Agents.answer(cur.id, "deny");
        else if (k === Qt.Key_D && cur && Agents.hasCard(cur)) Agents.dismiss(cur.id);
        else return;
        event.accepted = true;
    }

    // tabs
    Item {
        id: tabs
        y: p.topPad
        width: parent.width
        height: 34
        Row {
            x: 18
            height: parent.height
            Repeater {
                model: p.views
                Item {
                    id: tab
                    required property string modelData
                    required property int index
                    width: tl.implicitWidth + 20
                    height: tabs.height
                    GText {
                        id: tl
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -2
                        text: tab.modelData.toUpperCase()
                        font.family: Theme.fontMono; font.pixelSize: 11; font.letterSpacing: 1.3
                        color: p.view === tab.modelData ? Theme.label : tm.containsMouse ? Theme.label2 : Theme.label3
                    }
                    Rectangle {
                        visible: p.view === tab.modelData
                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                        width: tl.implicitWidth; height: 2; radius: 1
                        color: Theme.accent
                        Rectangle { anchors.centerIn: parent; width: parent.width + 10; height: 8; radius: 4; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18); z: -1 }
                    }
                    MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: p.go(tab.modelData) }
                }
            }
        }
        Row {
            anchors { right: parent.right; rightMargin: 20; verticalCenter: parent.verticalCenter; verticalCenterOffset: -2 }
            spacing: 7
            Rectangle {
                width: 22; height: 12; radius: 6
                anchors.verticalCenter: parent.verticalCenter
                color: p.cycling ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.white(0.11)
                Rectangle {
                    x: p.cycling ? 12 : 2; y: 2; width: 8; height: 8; radius: 4
                    color: p.cycling ? Theme.accent : Theme.label3
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }
            GText { text: "CYCLE"; font.family: Theme.fontMono; font.pixelSize: 10; font.letterSpacing: 1.1; color: Theme.label3 }
        }
        MouseArea {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: 90
            cursorShape: Qt.PointingHandCursor
            onClicked: p.cycling = !p.cycling
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.white(0.08) }
    }

    Item {
        id: stack
        y: tabs.y + tabs.height + 10
        x: 18
        width: parent.width - 36
        height: p.view === "agents" ? agents.implicitHeight
            : p.view === "replay" ? replay.implicitHeight
            : p.view === "laps" ? laps.implicitHeight : receipts.implicitHeight

        // ---- agents ----
        Column {
            id: agents
            visible: p.view === "agents"
            width: parent.width
            spacing: 2
            Repeater {
                model: Agents.overlaps
                Rectangle {
                    id: ov
                    required property var modelData
                    width: agents.width
                    height: 36
                    radius: 9
                    color: Qt.rgba(1, 0.62, 0.04, 0.07)
                    border.width: 1
                    border.color: Qt.rgba(1, 0.62, 0.04, 0.28)
                    GText {
                        anchors { left: parent.left; leftMargin: 12; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                        textFormat: Text.StyledText
                        text: "<font color='#FFB340'>Overlap.</font> " + ov.modelData.ids.map(id => Agents.byId(id)?.project ?? id.slice(0, 6)).join(" and ")
                            + " both edited <font face='" + Theme.fontMono + "' color='#FFFFFF'>" + ov.modelData.file + "</font> in the last 15 min."
                        font.pixelSize: 12; color: Theme.label2
                    }
                }
            }
            Item { width: 1; height: Agents.overlaps.length ? 6 : 0 }
            Repeater {
                model: p.list
                AgentRow {
                    id: ar
                    required property var modelData
                    required property int index
                    width: agents.width
                    s: modelData
                    now: p.now
                    selected: p.selId === modelData.id
                    steering: p.steerId === modelData.id
                    onPick: { p.selId = modelData.id; p.forceActiveFocus(); }
                    onSteeringChanged: if (steering) Qt.callLater(() => ar.focusSteer())
                    onSteerSent: t => { Agents.steer(modelData.id, t); p.steerId = ""; p.forceActiveFocus(); }
                    onSteerLeft: { p.steerId = ""; p.forceActiveFocus(); }
                }
            }
            GText {
                visible: p.list.length === 0
                width: parent.width
                height: 60
                horizontalAlignment: Text.AlignHCenter
                text: "No agents running. Start one from the launcher with “>”."
                color: Theme.label3
            }
            Item { width: 1; height: 6 }
            GText {
                width: parent.width
                text: "↑↓ select · ⏎ jump · R steer · P replay · Y allow · ⌫ deny · Tab views"
                font.family: "GeistMono Nerd Font"; font.pixelSize: 10; color: Theme.label3
                horizontalAlignment: Text.AlignRight
            }
        }
        ReplayView { id: replay; visible: p.view === "replay"; width: parent.width; sid: p.selId; shown: visible }
        LapsView { id: laps; visible: p.view === "laps"; width: parent.width; shown: visible }
        ReceiptsView { id: receipts; visible: p.view === "receipts"; width: parent.width; shown: visible }
    }
}

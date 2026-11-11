pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// The compact notch (mock .cmp): one line under the bar for the live agents. It shows one agent
// at a time (needs-you first, then working, then the rest), rolls to the next every
// notch.rollSeconds (3.6 s) with a vertical slide, and has one dot per agent on the right.
Item {
    id: c
    property var list: []                 // sessions in show order
    property real now: Date.now()
    property bool rolling: true
    property int idx: 0
    readonly property var cur: list.length ? list[idx % list.length] : null
    signal clicked()
    implicitHeight: 38
    implicitWidth: Math.min(470, Math.max(300, 13 + 22 + 10 + measure.implicitWidth + 14 + dots.implicitWidth + 14))

    function modeOf(s) {
        if (!s) return "idle";
        if (s.status === "needs-you" || s.status === "error") return "need";
        if (s.status === "working") return s.kind === "codex" ? "watch" : "work";
        return "done";
    }
    function actionOf(s) {
        if (!s) return "";
        if (s.status === "needs-you") {
            const r = Agents.reqFor(s.id);
            const p = r ? { tool: r.tool, cmd: String(r.input?.command ?? r.input?.file_path ?? "") } : (s.perm ?? {});
            return "waits on " + (p.tool || "you") + (p.cmd ? " · " + String(p.cmd).split("\n")[0] : "");
        }
        if (s.status === "error") return s.error || "stopped with an error";
        if (s.status === "done") return s.summary || "done";
        return Agents.lastAction(s) || s.lastPrompt || "working";
    }
    function since(s) { return s ? Agents.hms(now - (s.status === "working" ? (s.turn?.at ?? s.since) : s.since)) : ""; }

    Timer {
        interval: (Config.opt.notch?.rollSeconds ?? 3.6) * 1000
        repeat: true
        running: c.rolling && c.visible && c.list.length > 1
        onTriggered: { c.idx = (c.idx + 1) % c.list.length; roll.restart(); }
    }
    onListChanged: if (idx >= list.length) idx = 0

    // invisible: the widest line decides the notch width (no jumping while it rolls)
    Row {
        id: measure
        visible: false
        spacing: 9
        GText { text: c.cur?.project ?? ""; font.pixelSize: 13; font.weight: Font.Medium }
        GText { text: c.actionOf(c.cur); font.family: Theme.fontMono; font.pixelSize: 11; width: Math.min(implicitWidth, 210) }
        GText { text: "00:00"; font.pixelSize: 12 }
    }

    AgentOrb {
        id: orb
        anchors { left: parent.left; leftMargin: 13; verticalCenter: parent.verticalCenter }
        size: 18
        mode: c.modeOf(c.cur)
    }
    Item {
        id: lineBox
        anchors { left: orb.right; leftMargin: 10; right: dots.left; rightMargin: 12; top: parent.top; bottom: parent.bottom }
        clip: true
        Row {
            id: line
            width: parent.width
            height: parent.height
            spacing: 9
            GText {
                id: proj
                anchors.verticalCenter: parent.verticalCenter
                text: c.cur?.project ?? ""
                font.pixelSize: 13
                font.weight: Font.Medium
                color: Theme.label
            }
            GText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, line.width - proj.implicitWidth - time.implicitWidth - 18)
                text: c.actionOf(c.cur)
                font.family: Theme.fontMono
                font.pixelSize: 11
                color: c.cur?.status === "needs-you" ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.9) : Theme.label2
            }
            GText {
                id: time
                anchors.verticalCenter: parent.verticalCenter
                text: c.since(c.cur)
                font.pixelSize: 12
                font.features: ({ "tnum": 1 })
                color: Theme.label2
            }
        }
        SequentialAnimation {
            id: roll
            NumberAnimation { target: line; property: "y"; from: 0; to: -12; duration: 0 }
            ParallelAnimation {
                NumberAnimation { target: line; property: "y"; from: 14; to: 0; duration: 480; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
                NumberAnimation { target: line; property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }
            }
        }
    }
    Row {
        id: dots
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 4
        visible: c.list.length > 1
        Repeater {
            model: c.list.length > 1 ? c.list : []
            Rectangle {
                id: d
                required property var modelData
                required property int index
                readonly property string m: c.modeOf(modelData)
                width: index === c.idx % c.list.length ? 12 : 5
                height: 5
                radius: 2.5
                color: m === "need" ? Theme.red : m === "work" ? Theme.accent : m === "watch" ? "#64D2FF" : "#F4F1EE"
                opacity: m === "done" ? 0.55 : 1
                Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            }
        }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: c.clicked() }
}

pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services
import qs.modules.notch

// The agent notch in the bar's centre (bar widget "notch"; mock lnx/design/mock/agent-notch.html):
// a black pill with the agent's orb (an Orbkit shader, notch.orb) and one line:
//   working   project · what it is doing · elapsed · a dot per agent (rolls every rollSeconds)
//   needs you project wants <the command>, red, + the key that allows it (Super+Y)
//   done      project done · +/- · files (doneSeconds)
// Click = the popover (request card / done card / Agents · Replay · Laps · Receipts).
// Hidden while no agent runs. Cost: the orb is the only animation (notch.orbFps, 20, and only
// while an agent works or waits); the line repaints once a second.
Item {
    id: root
    property string widgetId: "notch"
    readonly property var opts: Config.opt.notch ?? ({})
    readonly property var req: AgentNotch.req
    readonly property var list: { const r = Agents.rank; return Agents.alive.slice().sort((a, b) => (r[a.status] - r[b.status]) || (b.since - a.since)); }
    readonly property string kind: req && AgentNotch.reqShown ? "need" : AgentNotch.doneId ? "done" : "live"
    property int idx: 0
    readonly property var cur: kind === "need" ? Agents.byId(req.sid) : kind === "done" ? Agents.byId(AgentNotch.doneId) : (list[idx % Math.max(1, list.length)] ?? null)
    property real now: Date.now()
    readonly property real cap: Math.min(opts.maxWidth ?? 520, Panels.barCenterRoom)
    visible: Agents.any || AgentNotch.open
    implicitHeight: Theme.barHeight
    implicitWidth: visible ? pill.width : 0

    Timer { interval: 1000; repeat: true; running: root.visible; onTriggered: root.now = Date.now() }
    Timer {
        interval: (root.opts.rollSeconds ?? 5) * 1000
        repeat: true
        running: root.visible && root.kind === "live" && root.list.length > 1 && !ma.containsMouse
        onTriggered: { fadeRoll.restart(); }
    }
    SequentialAnimation {
        id: fadeRoll
        NumberAnimation { target: line; property: "opacity"; to: 0; duration: 140 }
        ScriptAction { script: root.idx = (root.idx + 1) % Math.max(1, root.list.length) }
        NumberAnimation { target: line; property: "opacity"; to: 1; duration: 200 }
    }
    onListChanged: if (idx >= list.length) idx = 0

    function modeOf(s) {
        if (!s) return "idle";
        if (s.status === "needs-you" || s.status === "error") return "need";
        if (s.status === "working") return s.kind === "codex" ? "watch" : "work";
        return "done";
    }
    function action(s) {
        if (!s) return "";
        if (root.kind === "need") return "wants " + (req.tool === "Bash" ? "" : req.tool + " ") + String(req.input?.command ?? req.input?.file_path ?? req.input?.url ?? "").split("\n")[0];
        if (root.kind === "done") { const t = Agents.turns[s.id]; return "done" + (t ? " · " + Agents.stat(t) : ""); }
        if (s.status === "needs-you") return "waits on " + (s.perm?.tool || "you") + " in its terminal";
        if (s.status === "done") return s.summary || "done";
        return Agents.lastAction(s) || s.lastPrompt || "working";
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        height: Theme.barHeight - 6
        width: Math.min(root.cap, row.implicitWidth + 16)
        radius: height / 2
        color: "#000000"
        border.width: 1
        border.color: root.kind === "need" ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.65)
            : AgentNotch.open ? Theme.white(0.22) : ma.containsMouse ? Theme.white(0.16) : Theme.white(0.08)
        Behavior on width { NumberAnimation { duration: 380; easing.type: Easing.OutBack; easing.overshoot: 0.8 } }
        Behavior on border.color { ColorAnimation { duration: 200 } }
        clip: true

        Row {
            id: row
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            AgentOrb {
                anchors.verticalCenter: parent.verticalCenter
                size: 18
                mode: root.kind === "need" ? "need" : root.kind === "done" ? "done" : root.modeOf(root.cur)
                fps: root.opts.orbFps ?? 12
            }
            Row {
                id: line
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                GText {
                    id: projT
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.cur?.project ?? (Agents.alive.length + " agents")
                    font.pixelSize: 12; font.weight: Font.Medium
                    color: Theme.label
                }
                GText {
                    anchors.verticalCenter: parent.verticalCenter
                    // whatever room the bar leaves: pill cap - padding - orb - project - time / key - dots
                    width: Math.max(0, Math.min(implicitWidth, root.kind === "need" ? 260 : 230,
                        root.cap - 22 - 18 - 8 - projT.implicitWidth - 8 - 8 - (root.kind === "need" ? 66 : root.kind === "live" ? (root.cap >= 340 ? 44 : 0) + (root.list.length > 1 ? Math.min(5, root.list.length) * 7 + 14 : 0) : 0)))
                    visible: width > 24
                    text: root.action(root.cur)
                    font.family: Theme.fontMono; font.pixelSize: 11
                    color: root.kind === "need" ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.95) : Theme.label2
                }
                GText {
                    visible: root.kind === "live" && !!root.cur && root.cap >= 340
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.cur ? Agents.hms(root.now - (root.cur.status === "working" ? (root.cur.turn?.at ?? root.cur.since) : root.cur.since)) : ""
                    font.pixelSize: 11; font.features: ({ "tnum": 1 })
                    color: Theme.label3
                }
            }
            // need: the key that answers it, from anywhere
            Rectangle {
                visible: root.kind === "need"
                anchors.verticalCenter: parent.verticalCenter
                implicitWidth: kk.implicitWidth + 12; implicitHeight: 16; radius: 4
                color: Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.16)
                GText { id: kk; anchors.centerIn: parent; text: "Super Y"; font.family: "GeistMono Nerd Font"; font.pixelSize: 10; font.weight: Font.Medium; color: Theme.red }
            }
            Row {
                visible: root.kind === "live" && root.list.length > 1
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Repeater {
                    model: root.kind === "live" && root.list.length > 1 ? root.list.slice(0, 5) : []
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property string m: root.modeOf(modelData)
                        width: index === root.idx % root.list.length || (index === 4 && root.idx >= 4) ? 10 : 4
                        height: 4; radius: 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: m === "need" ? Theme.red : m === "work" ? Theme.accent : m === "watch" ? "#64D2FF" : Theme.white(0.5)
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }
            }
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { Panels.notePointer(); AgentNotch.laterId = ""; AgentNotch.toggle(); }
        }
    }

    GPopup {
        popupId: AgentNotch.popupId
        anchorItem: pill
        align: "itemCenter"
        bare: true
        padding: 0
        gap: 7
        popupWidth: AgentNotch.mode === "need" ? 560 : AgentNotch.mode === "done" ? 520 : 640
        content: NotchPopup {}
    }
}

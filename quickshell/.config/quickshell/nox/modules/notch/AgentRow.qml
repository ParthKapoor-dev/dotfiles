pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// One agent in the panel list (mock .ag): orb · project · branch · task, the live line under it,
// a status pill and the elapsed time on the right. Selected = soft fill + accent tick.
Item {
    id: row
    property var s: null
    property bool selected: false
    property bool steering: false
    property real now: Date.now()
    readonly property var req: s ? Agents.reqFor(s.id) : null
    readonly property string st: s?.status ?? "done"
    readonly property string mode: st === "needs-you" || st === "error" ? "need" : st === "working" ? (s?.kind === "codex" ? "watch" : "work") : "done"
    signal pick()
    signal steerSent(string text)
    signal steerLeft()
    implicitHeight: 54 + (steering ? 46 : 0)
    function focusSteer() { steer.focusInput(); }

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: row.selected ? Theme.white(0.06) : ma.containsMouse ? Theme.white(0.035) : "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle { visible: row.selected; x: 0; y: 10; width: 2; height: 34; radius: 1; color: Theme.accent }
    }
    MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: row.pick(); onDoubleClicked: Agents.jump(row.s?.id) }

    AgentOrb { id: orb; x: 10; y: 21; size: 13; mode: row.mode; animate: row.visible }
    Column {
        x: 34; y: 9
        width: row.width - 34 - rightCol.width - 18
        spacing: 4
        Row {
            width: parent.width
            spacing: 8
            GText { id: pj; text: row.s?.project ?? ""; font.pixelSize: 13; font.weight: Font.Medium }
            GText { id: br; text: row.s?.branch ?? ""; font.family: Theme.fontMono; font.pixelSize: 11; color: Theme.label3; anchors.baseline: pj.baseline; visible: text !== "" }
            GText {
                anchors.baseline: pj.baseline
                width: Math.max(0, parent.width - pj.implicitWidth - (br.visible ? br.implicitWidth + 8 : 0) - 8)
                text: row.s?.firstPrompt ?? ""
                font.pixelSize: 13; color: Theme.label2
            }
        }
        GText {
            width: parent.width
            font.family: Theme.fontMono; font.pixelSize: 11
            color: row.mode === "need" ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.85) : Theme.label3
            text: {
                const s = row.s;
                if (!s) return "";
                if (row.req) return "waits on " + row.req.tool + " · " + String(row.req.input?.command ?? row.req.input?.file_path ?? row.req.input?.url ?? "").split("\n")[0];
                if (row.st === "needs-you") return "waits on " + (s.perm?.tool || "you") + (s.perm?.cmd ? " · " + s.perm.cmd : " · in its terminal");
                if (row.st === "error") return s.error || "stopped with an error";
                if (row.st === "done") { const t = Agents.turns[s.id]; return t ? Agents.stat(t) + (t.prNum ? " · PR #" + t.prNum : "") : (s.summary || "done"); }
                return Agents.lastAction(s) + ((s.subagents ?? 0) > 0 ? " · " + s.subagents + " subagents" : "");
            }
        }
    }
    Column {
        id: rightCol
        anchors { right: parent.right; rightMargin: 10 }
        y: 9
        spacing: 4
        Rectangle {
            anchors.right: parent.right
            implicitWidth: pl.implicitWidth + 12; implicitHeight: 17; radius: 4
            color: row.mode === "need" ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.14)
                : row.mode === "work" ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                : row.mode === "watch" ? Qt.rgba(0.39, 0.82, 1, 0.1) : Theme.white(0.1)
            GText {
                id: pl
                anchors.centerIn: parent
                text: (row.s?.kind === "codex" ? "codex · watching" : row.st === "needs-you" ? "needs you" : row.st).toUpperCase()
                font.family: Theme.fontMono; font.pixelSize: 10; font.letterSpacing: 1
                color: row.mode === "need" ? Theme.red : row.mode === "work" ? Theme.accent : row.mode === "watch" ? "#64D2FF" : Theme.label
            }
        }
        GText {
            anchors.right: parent.right
            text: row.s ? Agents.hms(row.now - (row.st === "working" ? (row.s.turn?.at ?? row.s.since) : row.s.since)) : ""
            font.pixelSize: 16; font.weight: Font.Light; font.features: ({ "tnum": 1 })
        }
    }
    SteerField {
        id: steer
        visible: row.steering
        x: 34; y: 54
        width: row.width - 44
        placeholder: row.st === "working" ? "Steer " + (row.s?.project ?? "it") + " · it reads this after its next step…"
            : row.req ? "Tell it what to do instead…" : "Next prompt for " + (row.s?.project ?? "it") + "…"
        onSend: t => row.steerSent(t)
        onLeave: row.steerLeft()
    }
}

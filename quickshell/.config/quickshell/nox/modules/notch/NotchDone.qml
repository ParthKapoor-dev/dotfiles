pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services
import "notch.js" as N

// The "done" card (mock #Ld): a turn just finished. What it said, lines and files changed since
// the prompt, the PR; Open diff (Enter) · Continue (R: a new prompt) · Replay (P) · Dismiss (Esc).
FocusScope {
    id: card
    property string sid: ""
    readonly property var s: Agents.byId(sid)
    readonly property var t: Agents.turns[sid] ?? null
    property bool replying: false
    signal replay(string id)
    signal close()
    implicitWidth: 520
    property real topPad: 46
    implicitHeight: col.implicitHeight + topPad + 20
    onSidChanged: replying = false

    Keys.onPressed: event => {
        if (reply.active) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { openDiff(); event.accepted = true; }
        else if (event.key === Qt.Key_R) { cont(); event.accepted = true; }
        else if (event.key === Qt.Key_P) { card.replay(sid); event.accepted = true; }
        else if (event.key === Qt.Key_Escape) { dismiss(); event.accepted = true; }
    }
    function openDiff() { if ((t?.nfiles ?? 0) > 0) Agents.openDiff(sid); else Agents.jump(sid); card.close(); }
    function cont() { replying = true; Qt.callLater(() => reply.focusInput()); }
    function dismiss() { Agents.dismiss(sid); card.close(); }

    Column {
        id: col
        x: 22; y: card.topPad
        width: parent.width - 44
        Item {
            width: parent.width
            height: 40
            AgentOrb { id: orb; anchors.verticalCenter: parent.verticalCenter; size: 24; mode: "done" }
            Column {
                anchors { left: orb.right; leftMargin: 12; verticalCenter: parent.verticalCenter; right: when.left; rightMargin: 10 }
                spacing: 2
                GText { width: parent.width; text: card.s?.project ?? ""; font.pixelSize: 14; font.weight: Font.Medium }
                GText {
                    width: parent.width
                    text: [card.s?.branch, card.s?.turn ? "finished in " + Agents.hms((card.s.turn.end ?? 0) - (card.s.turn.at ?? 0)) : "",
                           (card.s?.turn?.n ?? 0) > 1 ? card.s.turn.n + " turns" : ""].filter(x => x).join(" · ")
                    font.pixelSize: 12; color: Theme.label3
                }
            }
            Column {
                id: when
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 1
                GText { anchors.right: parent.right; text: "DONE"; font.family: Theme.fontMono; font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.label3 }
                GText { anchors.right: parent.right; text: N.clock(card.s?.turn?.end ?? Date.now()); font.pixelSize: 26; font.weight: Font.ExtraLight; font.features: ({ "tnum": 1 }) }
            }
        }
        Item { width: 1; height: 10 }
        GText {
            width: parent.width
            text: card.s?.lastPrompt ?? ""
            font.pixelSize: 20; font.weight: Font.Light
            wrapMode: Text.WordWrap; maximumLineCount: 2
        }
        Item { width: 1; height: 6 }
        GText {
            width: parent.width
            text: card.t?.say || card.s?.turn?.say || card.s?.summary || ""
            visible: text !== ""
            font.pixelSize: 13; color: Theme.label2
            wrapMode: Text.WordWrap; maximumLineCount: 3; lineHeight: 1.2
        }
        Item { width: 1; height: 14 }
        Row {
            spacing: 22
            visible: (card.t?.nfiles ?? 0) > 0 || !!card.t?.pr
            Stat { value: "+" + (card.t?.add ?? 0); label: "added"; tone: Theme.green; visible: (card.t?.nfiles ?? 0) > 0 }
            Stat { value: "−" + (card.t?.del ?? 0); label: "removed"; tone: Theme.red; visible: (card.t?.nfiles ?? 0) > 0 }
            Stat { value: String(card.t?.nfiles ?? 0); label: (card.t?.nfiles ?? 0) === 1 ? "file" : "files"; visible: (card.t?.nfiles ?? 0) > 0 }
            Stat { value: "#" + (card.t?.prNum ?? ""); label: "pull request"; visible: !!card.t?.prNum }
        }
        Item { width: 1; height: (card.t?.nfiles ?? 0) > 0 || !!card.t?.pr ? 16 : 0 }
        Row {
            spacing: 8
            NBtn { text: (card.t?.nfiles ?? 0) > 0 ? "Open diff" : "Jump"; key: "⏎"; kind: "go"; onClicked: card.openDiff() }
            NBtn { text: "Continue"; key: "R"; onClicked: card.cont() }
            NBtn { text: "Replay"; key: "P"; onClicked: card.replay(card.sid) }
            NBtn { text: "Open PR"; visible: !!card.t?.pr; onClicked: { Agents.openPr(card.t.pr); card.close(); } }
            NBtn { text: "Dismiss"; key: "esc"; kind: "ghost"; onClicked: card.dismiss() }
        }
        Item { width: 1; height: card.replying ? 12 : 0 }
        SteerField {
            id: reply
            visible: card.replying
            width: parent.width
            placeholder: "Next prompt for " + (card.s?.project ?? "it") + "…"
            onSend: t => { Agents.steer(card.sid, t); card.replying = false; card.close(); }
            onLeave: { card.replying = false; card.forceActiveFocus(); }
        }
    }
}

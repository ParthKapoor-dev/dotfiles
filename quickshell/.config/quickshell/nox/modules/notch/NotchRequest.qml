pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services
import "notch.js" as N

// The "needs you" card (mock #Ln): who is asking, how long it has waited, the exact command (or
// the edit / URL), why, and Allow / Always / Deny / Answer in terminal, plus "Tell it what to do
// instead…" (deny + the message). The terminal asks at the same time; answering there clears this.
// Keys while the notch has focus: Enter allow · Shift+Enter always · Backspace deny · typing goes
// to the steer field · Esc = later (the card folds into the compact line, the request stays).
FocusScope {
    id: card
    property var req: null
    property int count: 1
    property real now: Date.now()
    readonly property var s: req ? Agents.byId(req.sid) : null
    readonly property var risk: N.risks(req)
    readonly property string ruleText: N.rule(req)
    readonly property var diff: N.diffLines(req, 6)
    readonly property bool isCmd: !!req?.input?.command
    property string toast: ""
    signal later()
    implicitWidth: 560
    property real topPad: 46
    implicitHeight: col.implicitHeight + topPad + 22

    function act(choice, msg) {
        if (!req) return;
        toast = choice === "deny" ? (msg ? "Denied · sent your note" : "Denied") : choice === "always" ? "Always allowed" : "Allowed";
        Agents.answerReq(req, choice, msg);
    }
    function focusSteer() { steer.focusInput(); }
    Keys.onPressed: event => {
        if (steer.active) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { act(event.modifiers & Qt.ShiftModifier ? "always" : "allow"); event.accepted = true; }
        else if (event.key === Qt.Key_Backspace || event.key === Qt.Key_Delete) { act("deny"); event.accepted = true; }
        else if (event.key === Qt.Key_Escape) { card.later(); event.accepted = true; }
        else if (event.text && event.text.length === 1 && event.text >= " " && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
            steer.focusInput(); steer.append(event.text); event.accepted = true;
        }
    }

    Column {
        id: col
        x: 22; y: card.topPad
        width: parent.width - 44
        spacing: 0

        // who + how long
        Item {
            width: parent.width
            height: 40
            AgentOrb { id: orb; anchors.verticalCenter: parent.verticalCenter; size: 24; mode: "need" }
            Column {
                anchors { left: orb.right; leftMargin: 12; verticalCenter: parent.verticalCenter; right: wait.left; rightMargin: 10 }
                spacing: 2
                GText { width: parent.width; text: card.s?.project ?? N.rel(card.req?.cwd ?? "", ""); font.pixelSize: 14; font.weight: Font.Medium }
                GText {
                    width: parent.width
                    text: [card.s?.branch, card.s ? Agents.kindName(card.s) : "", Agents.modelName(card.s?.model),
                           card.s ? Math.max(1, Math.round((card.now - card.s.started) / 60000)) + " min in" : ""].filter(x => x).join(" · ")
                    font.pixelSize: 12
                    color: Theme.label3
                }
            }
            Column {
                id: wait
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 1
                GText {
                    anchors.right: parent.right
                    text: card.count > 1 ? "WAITING · 1 OF " + card.count : "WAITING"
                    font.family: Theme.fontMono; font.pixelSize: 10; font.letterSpacing: 1.2
                    color: Theme.red
                }
                GText {
                    anchors.right: parent.right
                    text: Agents.hms(card.now - (card.req?.at ?? card.now))
                    font.pixelSize: 26; font.weight: Font.ExtraLight
                    font.features: ({ "tnum": 1 })
                }
            }
        }
        Item { width: 1; height: 14 }
        // what it wants
        Row {
            spacing: 8
            GText {
                anchors.verticalCenter: parent.verticalCenter
                text: N.verb(card.req).toUpperCase()
                font.family: Theme.fontMono; font.pixelSize: 10; font.letterSpacing: 1.4
                color: Theme.label3
            }
            NChip { text: card.req?.tool ?? "" }
            Repeater { model: card.risk; NChip { required property string modelData; text: modelData; hot: true } }
        }
        Item { width: 1; height: 8 }
        Rectangle {
            width: parent.width
            height: body.implicitHeight + 24
            radius: 8
            color: "#0A0909"
            border.width: 1
            border.color: Theme.white(0.09)
            Rectangle { x: 0; y: 10; width: 2; height: parent.height - 20; radius: 1; color: Theme.red }
            Column {
                id: body
                x: 16; y: 12
                width: parent.width - 30
                spacing: 4
                Text {
                    width: parent.width
                    visible: card.isCmd
                    textFormat: Text.RichText
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 6
                    elide: Text.ElideRight
                    text: "<span style='color:#6F6964'>$ </span>" + N.highlight(card.req?.input?.command ?? "", "#FF8A5C")
                    font.family: Theme.fontMono; font.pixelSize: 13
                    color: Theme.label
                    lineHeight: 1.25
                }
                GText {
                    visible: !card.isCmd
                    width: parent.width
                    text: N.rel(N.target(card.req), card.req?.cwd ?? "") || JSON.stringify(card.req?.input ?? {}).slice(0, 300)
                    font.family: Theme.fontMono; font.pixelSize: 13
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 3
                }
                Repeater {
                    model: card.isCmd ? [] : card.diff
                    GText {
                        required property var modelData
                        width: body.width
                        text: modelData.k + " " + modelData.t
                        font.family: Theme.fontMono; font.pixelSize: 12
                        color: modelData.k === "+" ? Theme.green : Theme.red
                        opacity: 0.9
                    }
                }
            }
        }
        Item { width: 1; height: (why.visible ? 10 : 0) }
        GText {
            id: why
            visible: !!(card.req?.input?.description)
            width: parent.width
            text: card.req?.input?.description ?? ""
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            font.pixelSize: 13
            color: Theme.label2
            lineHeight: 1.2
        }
        Item { width: 1; height: 16 }
        Item {
            width: parent.width
            height: 34
            Row {
                spacing: 8
                NBtn { text: "Allow"; key: "⏎"; kind: "go"; onClicked: card.act("allow") }
                NBtn { text: "Always"; note: card.ruleText; key: "⇧⏎"; visible: card.ruleText !== ""; onClicked: card.act("always") }
                NBtn { text: "Deny"; key: "⌫"; kind: "ghost"; dangerHover: true; onClicked: card.act("deny") }
            }
            GText {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "Answer in terminal ↗"
                font.pixelSize: 12
                color: termMa.containsMouse ? Theme.label : Theme.label3
                MouseArea { id: termMa; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { if (card.req) Agents.jump(card.req.sid); card.later(); } }
            }
        }
        Item { width: 1; height: 12 }
        SteerField {
            id: steer
            width: parent.width
            onSend: t => card.act("deny", t)
            onLeave: card.forceActiveFocus()
        }
        Item { width: 1; height: 10 }
        GText {
            width: parent.width
            text: card.toast || "Also asking in its terminal · Super+Y allows from any window, Super+Shift+Y always, Super+Backspace denies"
            font.pixelSize: 11
            color: card.toast ? Theme.accent : Theme.label3
            elide: Text.ElideRight
        }
    }
}

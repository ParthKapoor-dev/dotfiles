pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services
import "notch.js" as N

// Replay (mock #V-replay): every step of a session's turn from its transcript (`nox agents replay`):
// you · Read · Edit · Bash · said · decided, numbered, with time; the selected step's detail
// (diff preview for edits) on the right; a scrubber of the whole turn below; ← → turn by turn.
Item {
    id: v
    property string sid: ""
    property bool shown: false
    property var rd: null
    property int turn: -1                 // -1 = last turn
    property int pick: -1
    property bool loading: false
    readonly property var steps: rd?.steps ?? []
    readonly property var step: steps[pick] ?? null
    implicitHeight: 340

    function load() {
        if (!sid || !shown) return;
        loading = true;
        const argv = ["replay", sid, "--json"];
        if (turn >= 0) argv.push("--turn", String(turn));
        Agents.helperRun(argv, (code, out) => {
            loading = false;
            const d = Agents.parse(out);
            rd = d?.ok ? d : null;
            if (rd && turn < 0) turn = rd.turn ?? -1;
            pick = Math.max(0, steps.findIndex(s => s.diff)) ;
            if (pick < 0 || pick >= steps.length) pick = steps.length - 1;
            list.positionViewAtIndex(Math.max(0, pick), ListView.Contain);
        });
    }
    onSidChanged: { turn = -1; rd = null; load(); }
    onShownChanged: if (shown) load()
    onTurnChanged: if (rd && rd.turn !== turn) load()
    Timer { interval: 4000; repeat: true; running: v.shown && (Agents.byId(v.sid)?.status === "working"); onTriggered: v.load() }

    function kindKey(s) {
        if (s.k === "you") return ["Y", "y"];
        if (s.k === "say") return ["S", "s"];
        if (s.k === "decide") return ["D", "s"];
        const n = s.name ?? "";
        if (/^(Edit|Write|MultiEdit|NotebookEdit|apply_patch)$/.test(n)) return [n[0], "e"];
        if (/^(Read|Grep|Glob|WebFetch|WebSearch)$/.test(n)) return [n[0], "r"];
        return [n.slice(0, 1) || "·", (s.s === "error" || s.s === "denied") ? "y" : "x"];
    }
    function tone(t) { return t === "e" ? Theme.accent : t === "r" ? "#64D2FF" : t === "y" ? Theme.red : t === "s" ? Theme.green : Theme.label; }

    Keys.onLeftPressed: if ((rd?.turn ?? 0) > 1) turn = rd.turn - 1
    Keys.onRightPressed: if (rd && rd.turn < rd.nturns) turn = rd.turn + 1

    GText {
        visible: !v.rd
        anchors.centerIn: parent
        text: v.loading ? "Reading the transcript…" : v.sid ? "No transcript for this session" : "Pick an agent in Agents first"
        color: Theme.label3
    }
    Item {
        visible: !!v.rd
        anchors.fill: parent
        ListView {
            id: list
            x: 0; y: 0
            width: parent.width - 236
            height: parent.height - 34
            clip: true
            model: v.steps
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: st
                required property var modelData
                required property int index
                readonly property var kk: v.kindKey(modelData)
                width: list.width
                height: 27
                radius: 7
                color: v.pick === index ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1) : sma.containsMouse ? Theme.white(0.04) : "transparent"
                Rectangle { visible: v.pick === st.index; width: 2; height: parent.height; color: Theme.accent }
                GText { x: 4; width: 22; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; text: String(st.modelData.n ?? st.index + 1); font.family: Theme.fontMono; font.pixelSize: 10; color: Theme.label3 }
                Rectangle {
                    x: 32; anchors.verticalCenter: parent.verticalCenter
                    width: 15; height: 15; radius: 4
                    color: Qt.rgba(v.tone(st.kk[1]).r, v.tone(st.kk[1]).g, v.tone(st.kk[1]).b, 0.16)
                    GText { anchors.centerIn: parent; text: st.kk[0]; font.family: Theme.fontMono; font.pixelSize: 9; font.weight: Font.DemiBold; color: v.tone(st.kk[1]) }
                }
                GText {
                    x: 55; width: parent.width - 55 - tm.width - 10
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.StyledText
                    text: "<b>" + N.esc(st.modelData.k === "you" ? "You" : st.modelData.k === "say" ? "Said" : st.modelData.k === "decide" ? "Decided" : st.modelData.name) + "</b>&nbsp;&nbsp;" + N.esc(st.modelData.a ?? "")
                    font.family: Theme.fontMono; font.pixelSize: 11; color: Theme.label2
                }
                GText { id: tm; anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: st.modelData.at ? N.clock(st.modelData.at) : ""; font.family: Theme.fontMono; font.pixelSize: 10; color: Theme.label3 }
                MouseArea { id: sma; anchors.fill: parent; hoverEnabled: true; onClicked: v.pick = st.index }
            }
        }
        // detail
        Rectangle {
            x: parent.width - 222
            width: 222
            height: parent.height - 34
            radius: 9
            color: "#0A0909"
            border.width: 1; border.color: Theme.white(0.08)
            clip: true
            Column {
                x: 12; y: 12
                width: parent.width - 24
                spacing: 6
                GText {
                    width: parent.width
                    text: v.step ? (v.step.n ?? v.pick + 1) + " · " + (v.step.k === "tool" ? v.step.name : v.step.k === "you" ? "You" : v.step.k === "say" ? "Said" : "Decided") + (v.step.at ? " · " + N.clock(v.step.at) : "") : ""
                    font.pixelSize: 12; font.weight: Font.Medium
                }
                GText {
                    width: parent.width
                    text: v.step ? (v.step.a ?? "") : ""
                    wrapMode: Text.WrapAnywhere; maximumLineCount: 5
                    font.family: Theme.fontMono; font.pixelSize: 11; color: Theme.label2
                }
                GText {
                    visible: !!v.step?.r
                    width: parent.width
                    text: "→ " + (v.step?.r ?? "") + (v.step?.dur ? "  ·  " + (v.step.dur / 1000).toFixed(1) + " s" : "")
                    wrapMode: Text.WrapAnywhere; maximumLineCount: 3
                    font.family: Theme.fontMono; font.pixelSize: 11
                    color: (v.step?.s === "error" || v.step?.s === "denied") ? Theme.red : Theme.label3
                }
                Repeater {
                    model: v.step?.diff ?? []
                    GText {
                        required property string modelData
                        width: parent.width
                        text: modelData
                        elide: Text.ElideRight
                        font.family: Theme.fontMono; font.pixelSize: 11
                        color: modelData[0] === "+" ? Theme.green : modelData[0] === "-" ? Theme.red : Theme.label3
                    }
                }
            }
        }
        // scrubber
        Item {
            y: parent.height - 24
            width: parent.width
            height: 20
            GText {
                id: tl
                anchors.verticalCenter: parent.verticalCenter
                text: (v.rd?.project ?? "") + " · turn " + (v.rd?.turn ?? "") + "/" + (v.rd?.nturns ?? "")
                font.family: Theme.fontMono; font.pixelSize: 10; color: Theme.label3
                MouseArea { anchors.fill: parent; acceptedButtons: Qt.LeftButton | Qt.RightButton; cursorShape: Qt.PointingHandCursor
                    onClicked: m => { if (!v.rd) return; if (m.button === Qt.RightButton) { if (v.rd.turn < v.rd.nturns) v.turn = v.rd.turn + 1; } else if (v.rd.turn > 1) v.turn = v.rd.turn - 1; } }
            }
            Row {
                anchors { left: tl.right; leftMargin: 12; right: cnt.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 2
                Repeater {
                    model: v.steps
                    Rectangle {
                        id: tk
                        required property var modelData
                        required property int index
                        readonly property var kk: v.kindKey(modelData)
                        width: Math.max(2, (parent.width - v.steps.length * 2) / Math.max(1, v.steps.length))
                        height: v.pick === index ? 16 : 8
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 2
                        color: v.pick === index ? Theme.label : kk[1] === "e" ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : kk[1] === "y" ? Theme.red : Theme.white(0.12)
                        Behavior on height { NumberAnimation { duration: 140 } }
                        MouseArea { anchors.fill: parent; anchors.margins: -3; onClicked: { v.pick = tk.index; list.positionViewAtIndex(tk.index, ListView.Contain); } }
                    }
                }
            }
            GText { id: cnt; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: (v.pick + 1) + "/" + v.steps.length; font.family: Theme.fontMono; font.pixelSize: 10; color: Theme.label3 }
        }
    }
}

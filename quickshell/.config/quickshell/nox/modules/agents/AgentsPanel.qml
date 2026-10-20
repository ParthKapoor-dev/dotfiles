pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// The agents panel: the bar dot's popover (widget "agents"; Ctrl+Super+M, `nox agents`, IPC
// agents toggle). Act on agents without switching windows (services/Agents):
//   NEEDS YOU   permission requests (the exact tool + command / file) and errors -> Enter jumps
//               to the session's pane to answer there
//   DONE        one card per finished turn: summary, +/- since the prompt, files, PR ->
//               Enter = Open diff (Jump when nothing changed), P = Open PR, R = Continue (reply),
//               J = Jump, D = Dismiss
//   WORKING     one line each: project · task · elapsed · last action -> Enter jumps, R replies
// Keys: ↑/↓ move, Enter = the item's primary action, R reply, D dismiss, E expand (the
// full-screen grid), Esc closes (or closes the reply box first).
// The popover is rebuilt on every open, so selection starts fresh: Agents.focusId (a notification's
// session) or the first item; Agents.replyId opens the reply box right away.
FocusScope {
    id: root
    property real now: Date.now()
    property int sel: 0
    property string replying: ""         // session id with the reply box open
    focus: true
    implicitHeight: col.implicitHeight

    readonly property int maxDone: Config.opt.agents?.panelDone ?? 4
    readonly property int maxWork: Config.opt.agents?.panelWorking ?? 6
    // flat list of what's on screen: { kind, s }
    readonly property var items: {
        const out = [];
        for (const s of Agents.needList) out.push({ kind: "need", s });
        for (const s of Agents.doneList.slice(0, maxDone)) out.push({ kind: "done", s });
        for (const s of Agents.workList.slice(0, maxWork)) out.push({ kind: "work", s });
        return out;
    }
    readonly property var cur: items[Math.min(sel, items.length - 1)] ?? null
    readonly property int hidden: Math.max(0, Agents.doneList.length - maxDone) + Math.max(0, Agents.workList.length - maxWork)

    Timer { interval: 1000; repeat: true; running: root.visible; onTriggered: root.now = Date.now() }
    Component.onCompleted: {
        now = Date.now();
        const i = Agents.focusId ? items.findIndex(x => x.s.id === Agents.focusId) : -1;
        sel = Math.max(0, i);
        if (Agents.replyId && Agents.canReply(Agents.byId(Agents.replyId))) replying = Agents.replyId;
        Agents.focusId = ""; Agents.replyId = "";
        forceActiveFocus();
    }
    // while open: a notification's Show / Reply re-targets the open panel
    Connections {
        target: Agents
        function onOpenSerialChanged() {
            const i = Agents.focusId ? root.items.findIndex(x => x.s.id === Agents.focusId) : -1;
            if (i >= 0) root.sel = i;
            if (Agents.replyId && Agents.canReply(Agents.byId(Agents.replyId))) root.replying = Agents.replyId;
            Agents.focusId = ""; Agents.replyId = "";
        }
        function onReplied(id, ok) { if (ok && root.replying === id) { root.replying = ""; root.forceActiveFocus(); } }
    }
    // keep the selection on the same session when the lists change
    property string selId: ""
    onSelChanged: selId = items[sel]?.s.id ?? ""
    onItemsChanged: {
        const i = selId ? items.findIndex(x => x.s.id === selId) : -1;
        sel = i >= 0 ? i : Math.min(sel, Math.max(0, items.length - 1));
        if (replying && !items.some(x => x.s.id === replying)) replying = "";
    }

    function primary(x) {
        if (!x) return;
        if (x.kind === "done" && (Agents.turns[x.s.id]?.nfiles ?? 0) > 0) Agents.openDiff(x.s.id);
        else Agents.jump(x.s.id);
    }
    function act(x, what) {
        if (!x) return;
        const id = x.s.id;
        if (what === "jump") Agents.jump(id);
        else if (what === "diff") Agents.openDiff(id);
        else if (what === "pr") Agents.openPr(Agents.turns[id]?.pr ?? "");
        else if (what === "dismiss") Agents.dismiss(id);
        else if (what === "reply") { if (Agents.canReply(x.s)) replying = id; else Agents.jump(id); }
    }
    Keys.onPressed: e => key(e)
    function key(e) {
        const k = e.key, x = cur;
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return;
        if (k === Qt.Key_Escape) Panels.close(Agents.popupId);
        else if (k === Qt.Key_Down || k === Qt.Key_Tab) sel = items.length ? (sel + 1) % items.length : 0;
        else if (k === Qt.Key_Up || k === Qt.Key_Backtab) sel = items.length ? (sel - 1 + items.length) % items.length : 0;
        else if (k === Qt.Key_Return || k === Qt.Key_Enter) primary(x);
        else if (k === Qt.Key_R) act(x, "reply");
        else if (k === Qt.Key_D && x?.kind === "done") act(x, "dismiss");
        else if (k === Qt.Key_P && x?.kind === "done") act(x, "pr");
        else if (k === Qt.Key_J) act(x, "jump");
        else if (k === Qt.Key_E) Agents.expand(x?.s.id ?? "");
        else return;
        e.accepted = true;
    }

    Column {
        id: col
        width: parent.width
        spacing: 0

        // header: AGENTS · counts ........ today $ · expand
        Item {
            width: parent.width
            height: 36
            Row {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: Theme.square ? 0 : 3; color: Theme.accent }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Agents"
                    color: Theme.label
                    font.family: Theme.fontLabel; font.pixelSize: 11; font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 2
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: [Agents.needsYou ? Agents.needsYou + " need you" : "", Agents.doneCount ? Agents.doneCount + " done" : "",
                           Agents.working ? Agents.working + " working" : ""].filter(x => x).join(" · ")
                    color: Theme.label3
                    font.family: Theme.fontLabel; font.pixelSize: 10
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 1.0
                }
            }
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: (Agents.today?.cost ?? 0) > 0
                    text: "$" + (Agents.today?.cost ?? 0).toFixed(2) + " today"
                    color: Theme.label3
                    font.family: Theme.fontLabel; font.pixelSize: 10
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 1.0
                    font.features: ({ "tnum": 1 })
                }
                ActButton { text: "Expand"; key: "E"; onClicked: Agents.expand(root.cur?.s.id ?? "") }
            }
        }

        Repeater {
            model: root.items
            Column {
                id: entry
                required property var modelData
                required property int index
                width: col.width
                readonly property bool head: index === 0 || root.items[index - 1].kind !== modelData.kind
                // section label: NEEDS YOU · 1
                Item {
                    visible: entry.head
                    width: parent.width
                    height: visible ? 26 : 0
                    Text {
                        x: 10
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 6
                        text: (entry.modelData.kind === "need" ? "Needs you · " + Agents.needList.length
                             : entry.modelData.kind === "done" ? "Done · " + Agents.doneList.length
                             : "Working · " + Agents.workList.length)
                        color: entry.modelData.kind === "need" ? Theme.accent : Theme.label3
                        font.family: Theme.fontLabel; font.pixelSize: 10; font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase; font.letterSpacing: 1.4
                    }
                    Rectangle { x: 10; width: parent.width - 20; height: 1; color: Theme.white(0.07); visible: entry.index > 0 }
                }
                AgentItem {
                    width: parent.width
                    session: entry.modelData.s
                    kind: entry.modelData.kind
                    turn: Agents.turns[entry.modelData.s.id] ?? ({})
                    selected: entry.index === root.sel
                    replying: root.replying === entry.modelData.s.id
                    now: root.now
                    onHovered: if (!root.replying) root.sel = entry.index
                    onActivate: { root.sel = entry.index; root.primary(entry.modelData); }
                    onAct: what => { root.sel = entry.index; root.act(entry.modelData, what); }
                    onSendReply: t => Agents.reply(entry.modelData.s.id, t)
                    onCancelReply: { root.replying = ""; root.forceActiveFocus(); }
                }
                Item { width: 1; height: 3 }
            }
        }

        // nothing yet
        Column {
            visible: root.items.length === 0
            width: parent.width
            topPadding: 14
            bottomPadding: 16
            spacing: 8
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Agents.any ? "All quiet" : "No agent sessions"
                color: Theme.label2
                font.family: Theme.fontLabel; font.pixelSize: 11
                font.capitalization: Font.AllUppercase; font.letterSpacing: 1.8
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Start one from the launcher:  " + (Config.launcherProvider("agent").prefix ?? ">") + " fix the crash in void"
                color: Theme.label3
                font.family: Theme.fontMono; font.pixelSize: 11
            }
        }

        // footer: hidden rows + keys
        Item {
            width: parent.width
            height: 30
            Rectangle { x: 10; width: parent.width - 20; height: 1; color: Theme.white(0.07) }
            Row {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Repeater {
                    model: [["↑↓", "Move"], ["↵", "Open"], ["R", "Reply"], ["D", "Dismiss"], ["E", "Expand"]]
                    Row {
                        id: hint
                        required property var modelData
                        spacing: 5
                        Keycap { text: hint.modelData[0] }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: hint.modelData[1]
                            color: Theme.label3
                            font.family: Theme.fontUi; font.pixelSize: 11
                        }
                    }
                }
            }
            Text {
                visible: root.hidden > 0
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: "+" + root.hidden + " more"
                color: Theme.label3
                font.family: Theme.fontLabel; font.pixelSize: 10
                font.capitalization: Font.AllUppercase; font.letterSpacing: 1.0
            }
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services
import "notch.js" as N

// Receipts (mock #V-receipts): everything the notch did for you (`nox agents receipts`), newest
// first: allowed · always allowed (Undo removes the rule) · denied · steered (Undo while it is
// still unread) · started / races / merges.
Item {
    id: v
    property bool shown: false
    property var items: []
    implicitHeight: Math.max(80, Math.min(items.length, 9) * 36 + 8)

    function load() { Agents.helperRun(["receipts", "--limit", "40", "--json"], (code, out) => { const d = Agents.parse(out); v.items = Array.isArray(d) ? d : []; }); }
    onShownChanged: if (shown) load()
    Connections { target: Agents; function onAnswered() { if (v.shown) v.load(); } function onSteered() { if (v.shown) v.load(); } }
    function dot(k) { return k === "allow" ? Theme.green : k === "always" ? Theme.accent : k === "deny" ? Theme.red : k === "steer" ? "#64D2FF" : Theme.label3; }
    function line(r) {
        const p = N.esc(r.project ?? "");
        const c = "<font face='" + Theme.fontMono + "' color='#FFFFFF'>" + N.esc(String(r.cmd ?? "").split("\n")[0].slice(0, 90)) + "</font>";
        switch (r.kind) {
        case "allow": return "<b>Allowed</b> " + c + " for " + p;
        case "always": return "<b>Always allowed</b> <font face='" + Theme.fontMono + "' color='#FFFFFF'>" + N.esc(r.rule?.str ?? "") + "</font> in " + p;
        case "deny": return "<b>Denied</b> " + c + (r.text ? " · “" + N.esc(r.text.slice(0, 80)) + "”" : "");
        case "steer": return "<b>Steered</b> " + p + ": “" + N.esc(String(r.text ?? "").slice(0, 100)) + "”";
        case "race": return "<b>Started a race</b> " + p + (r.text ? ": “" + N.esc(r.text.slice(0, 80)) + "”" : "");
        case "merge": return "<b>Merged</b> " + N.esc(r.text ?? "") + " into " + p;
        case "start": return "<b>Started</b> " + p + (r.text ? ": “" + N.esc(r.text.slice(0, 80)) + "”" : "");
        default: return "<b>" + N.esc(r.kind) + "</b> " + p;
        }
    }

    GText {
        visible: v.items.length === 0
        anchors.centerIn: parent
        text: "Nothing yet. Answers and steers you send from the notch show up here."
        color: Theme.label3
    }
    ListView {
        anchors.fill: parent
        clip: true
        model: v.items
        boundsBehavior: Flickable.StopAtBounds
        delegate: Item {
            id: rc
            required property var modelData
            required property int index
            width: ListView.view.width
            height: 36
            Rectangle { visible: rc.index > 0; width: parent.width; height: 1; color: Theme.white(0.07) }
            GText { x: 6; width: 46; anchors.verticalCenter: parent.verticalCenter; text: N.clock(rc.modelData.at ?? 0); font.family: Theme.fontMono; font.pixelSize: 11; color: Theme.label3 }
            Rectangle { x: 58; anchors.verticalCenter: parent.verticalCenter; width: 8; height: 8; radius: 2; color: v.dot(rc.modelData.kind) }
            GText {
                x: 76; width: parent.width - 76 - un.width - 14
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                text: v.line(rc.modelData)
                font.pixelSize: 13; color: Theme.label2
                opacity: rc.modelData.undone ? 0.45 : 1
            }
            GText {
                id: un
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                text: rc.modelData.undone ? "Undone" : rc.modelData.undoable ? "Undo" : "—"
                font.pixelSize: 12
                color: rc.modelData.undoable && !rc.modelData.undone ? (uma.containsMouse ? Qt.lighter(Theme.accent, 1.2) : Theme.accent) : Theme.label3
                MouseArea {
                    id: uma
                    anchors.fill: parent; anchors.margins: -6
                    hoverEnabled: true
                    enabled: rc.modelData.undoable && !rc.modelData.undone
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Agents.helperRun(["undo", rc.modelData.id], (code, out) => {
                        const r = Agents.parse(out);
                        Panels.hud(code === 0 ? "Undone" : (r.error || "Couldn't undo"), code === 0 ? "check" : "x");
                        v.load();
                    })
                }
            }
        }
    }
}

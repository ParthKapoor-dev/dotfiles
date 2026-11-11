import QtQuick
import qs.core
import qs.components
import qs.services

// "Tell it what to do instead…" (mock .steer): one line, Enter sends, Esc leaves the field.
// Hold the mic (or Super+Shift+Space) to dictate into it while it has focus (Voice.sink).
FocusScope {
    id: f
    property string placeholder: "Tell it what to do instead…"
    property alias text: input.text
    readonly property bool active: input.activeFocus
    signal send(string text)
    signal leave()
    implicitHeight: 38
    function focusInput() { input.forceActiveFocus(); }
    function append(t) {
        const cur = input.text;
        input.text = cur && !/\s$/.test(cur) ? cur + " " + t : cur + t;
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
    }
    onActiveChanged: {
        if (active) Voice.sink = t => f.append(t);
        else if (Voice.sink) Voice.sink = null;
    }
    Component.onDestruction: if (active && Voice.sink) Voice.sink = null

    Rectangle {
        anchors.fill: parent
        radius: 9
        color: Theme.white(0.06)
        border.width: 1
        border.color: input.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.6) : Theme.white(0.09)
        Behavior on border.color { ColorAnimation { duration: 160 } }
    }
    TextInput {
        id: input
        anchors { left: parent.left; leftMargin: 12; right: mic.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
        color: Theme.label
        font.family: Theme.fontUi
        font.pixelSize: 13
        selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
        clip: true
        focus: true
        Keys.onReturnPressed: event => { const t = text.trim(); if (t) { f.send(t); text = ""; } event.accepted = true; }
        Keys.onEnterPressed: event => { const t = text.trim(); if (t) { f.send(t); text = ""; } event.accepted = true; }
        Keys.onEscapePressed: event => { f.leave(); event.accepted = true; }
        GText {
            visible: !input.text && !input.activeFocus || (!input.text && input.activeFocus)
            anchors.verticalCenter: parent.verticalCenter
            text: Voice.phase === "rec" && f.active ? "Listening…" : f.placeholder
            color: Theme.label3
            font.pixelSize: 13
        }
    }
    Rectangle {
        id: mic
        anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
        width: 28; height: 28; radius: 7
        color: (Voice.phase === "rec" && f.active) ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.2) : micMa.containsMouse ? Theme.white(0.1) : "transparent"
        Glyph {
            anchors.centerIn: parent
            name: "mic"
            size: 14
            color: (Voice.phase === "rec" && f.active) ? Theme.red : Theme.label2
        }
        MouseArea {
            id: micMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: { input.forceActiveFocus(); Voice.dictate(t => f.append(t)); }
            onReleased: Voice.release()
        }
    }
}

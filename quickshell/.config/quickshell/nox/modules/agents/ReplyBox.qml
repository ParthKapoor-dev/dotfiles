pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// Reply to an agent session from the panel: one line of text (Enter sends, Esc closes the box),
// or dictate: hold the mic button, or hold Super+Shift+Space (voice typing delivers into this
// box while it is open: Voice.sink, nothing is pasted anywhere else). The route line says how the
// text reaches the session (Orca terminal send / tmux / paste into its window, no Enter).
Item {
    id: root
    property var session: null
    signal send(string text)
    signal cancel()
    readonly property string route: Agents.replyRoute(session)
    implicitHeight: col.implicitHeight
    function focusInput() { input.forceActiveFocus(); }
    function append(t) {
        const cur = input.text;
        input.text = cur && !/\s$/.test(cur) ? cur + " " + t : cur + t;
        input.cursorPosition = input.text.length;
        input.forceActiveFocus();
    }
    // voice typing goes here while the box is open
    Component.onCompleted: Voice.sink = t => root.append(t)
    Component.onDestruction: if (Voice.sink) Voice.sink = null

    Column {
        id: col
        width: parent.width
        spacing: 6
        Rectangle {
            width: parent.width
            height: 30
            radius: Theme.square ? 0 : 6
            color: Qt.rgba(0, 0, 0, 0.35)
            border.width: 1
            border.color: input.activeFocus ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.8) : Theme.white(0.16)
            Text {
                text: "›"
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.accent
                font.family: Theme.fontMono
                font.pixelSize: 13
            }
            TextInput {
                id: input
                x: 22
                width: parent.width - x - mic.width - 10
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.label
                selectionColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4)
                font.family: Theme.fontUi
                font.pixelSize: 12
                clip: true
                Keys.onReturnPressed: e => { if (input.text.trim()) root.send(input.text.trim()); e.accepted = true; }
                Keys.onEnterPressed: e => { if (input.text.trim()) root.send(input.text.trim()); e.accepted = true; }
                Keys.onEscapePressed: e => { root.cancel(); e.accepted = true; }
                Text {
                    visible: !input.text && !input.preeditText
                    anchors.verticalCenter: parent.verticalCenter
                    text: Voice.phase === "rec" ? "Listening…" : Voice.busy ? "Transcribing…" : "Reply to " + (root.session?.project || "the agent") + "…"
                    color: Voice.phase === "rec" ? Theme.accent : Theme.label3
                    font: input.font
                }
            }
            // hold to talk
            Rectangle {
                id: mic
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 24; height: 22
                radius: Theme.square ? 0 : 4
                color: Voice.phase === "rec" ? Theme.accent : micMa.containsMouse ? Theme.white(0.1) : "transparent"
                Glyph {
                    anchors.centerIn: parent
                    name: "mic"
                    size: 13
                    color: Voice.phase === "rec" ? Theme.onAccent : Theme.label2
                }
                MouseArea {
                    id: micMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onPressed: Voice.dictate(t => root.append(t))
                    onReleased: Voice.release()
                }
            }
        }
        Flow {
            width: parent.width
            spacing: 6
            Text {
                text: root.route === "orca" ? "Via Orca · sent with Enter"
                    : root.route === "tmux" ? "Via tmux · sent with Enter"
                    : "Pastes into its window · you press Enter"
                color: Theme.label3
                font.family: Theme.fontLabel
                font.pixelSize: 10
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.9
            }
            Text {
                text: "↵ send · esc cancel · hold mic or Super+Shift+Space to talk"
                color: Theme.label3
                font.family: Theme.fontLabel
                font.pixelSize: 10
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.9
            }
        }
    }
}

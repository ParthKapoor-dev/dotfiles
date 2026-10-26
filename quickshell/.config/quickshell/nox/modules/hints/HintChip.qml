import QtQuick
import qs.core

// One hint label (modules/hints). Element / bar / dock targets: a small accent chip in the label
// font, the letters typed so far dimmed. Windows: a larger dark chip with the letters in accent
// and the app name beside them, centred on the window.
// `typed` is the prefix typed so far; a chip it doesn't match fades out.
Item {
    id: root
    property string label: ""
    property string typed: ""
    property string kind: "element"      // element | bar | dock | window
    property string title: ""            // window chips: the app name
    readonly property bool big: kind === "window"
    readonly property bool matches: typed === "" || label.startsWith(typed)
    readonly property bool lead: typed !== "" && matches       // narrowed down to this one's branch
    readonly property real fs: big ? 15 : 11

    implicitWidth: chip.width
    implicitHeight: chip.height
    opacity: matches ? 1 : 0
    visible: opacity > 0.01
    scale: lead ? 1.08 : 1
    Behavior on opacity { NumberAnimation { duration: 90; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    Behavior on scale { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSnap } }

    Rectangle {
        id: chip
        width: row.width + (root.big ? 20 : 8)
        height: root.big ? 30 : 17
        radius: Theme.square ? (root.big ? 4 : 2) : (root.big ? 9 : 4)
        color: root.big ? (Theme.glassOpaque ? Theme.rgba(Theme.t.color.glass, 1) : Theme.cardGlass) : Theme.accent
        // a dark edge keeps small chips readable on any background (light pages, the accent itself)
        border.width: 1
        border.color: root.big ? Theme.white(0.16) : Qt.rgba(0, 0, 0, 0.55)

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                // typed letters dimmed, the rest at full strength
                readonly property string done: root.label.slice(0, root.matches ? root.typed.length : 0)
                readonly property color dim: root.big ? Theme.label3 : Theme.rgba(Theme.t.color.onAccent, 0.42)
                text: (done ? "<font color=\"" + dim + "\">" + done.toUpperCase() + "</font>" : "") + root.label.slice(done.length).toUpperCase()
                color: root.big ? Theme.accent : Theme.onAccent
                font.family: Theme.fontLabel
                font.pointSize: root.fs * 0.75
                font.weight: Font.Bold
                font.letterSpacing: root.big ? 1.2 : 0.4
            }
            Text {
                visible: root.big && root.title !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: root.title.toUpperCase()
                color: Theme.label2
                font.family: Theme.fontLabel
                font.pointSize: 10 * 0.75
                font.weight: Font.Medium
                font.letterSpacing: 1
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 180)
            }
        }
    }
}

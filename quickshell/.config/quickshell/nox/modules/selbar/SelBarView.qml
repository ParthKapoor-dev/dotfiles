pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.core
import qs.components
import qs.modules.ask
import "SelText.js" as ST

// The selection bar itself (PopClip style), in the voice pill / draw toolbox language: opaque
// glass, 1 px hairline, square 5 px corners (Telemetry), mono uppercase labels, the hint above.
// Pure view: modules/selbar/SelBar places it and runs the actions; the offscreen harness renders
// it with synthetic text. Left to right:
//   ASK (the Claude burst, accent) | search · translate · copy · shelf | open link (a URL only) ·
//   case (text with letters) · "= result" (maths only, click copies it) · speak (spd-say present)
// The text itself is never drawn; only what it is (a link's host in the hint, a sum's result).
Item {
    id: root
    property string text: ""
    property bool canSpeak: false
    property string caseShown: ""        // the case last copied ("" = none yet this show)
    property bool tipBelow: false        // the bar sits under the pointer (no room above)
    property string flash: ""            // a short confirmation in the hint ("Copied")
    signal act(string id)
    readonly property bool pointerIn: hover.hovered

    readonly property var info: ST.classify(text)
    readonly property string calcText: info.isMath ? ST.fmt(info.math) : ""
    readonly property string nextCase: info.letters && !info.isUrl ? ST.nextCase(text.trim(), caseShown) : ""

    readonly property bool tele: Theme.square
    readonly property color accent: Theme.accent
    implicitWidth: row.implicitWidth + 10
    implicitHeight: 40
    width: implicitWidth
    height: implicitHeight
    property string tip: ""
    readonly property string shownTip: flash !== "" ? flash : tip

    component Label: Text {
        property real px: 10
        property real em: 0.08
        font.family: Theme.fontLabel
        font.pixelSize: px
        font.weight: Font.Medium
        font.letterSpacing: px * em
        font.capitalization: Font.AllUppercase
        color: Theme.label3
        verticalAlignment: Text.AlignVCenter
    }
    component Sep: Rectangle {
        width: 1; height: 20
        anchors.verticalCenter: parent?.verticalCenter
        color: Theme.hair
    }
    // hover = the hint above the bar
    component Hint: MouseArea {
        property string hint
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: root.tip = containsMouse ? hint : (root.tip === hint ? "" : root.tip)
    }
    // a square icon button (the toolbox's Btn)
    component Btn: Item {
        id: b
        property string icon
        property string hint
        property string action
        width: 30; height: 30
        anchors.verticalCenter: parent?.verticalCenter
        Rectangle {
            anchors.fill: parent
            radius: root.tele ? 3 : 9
            color: bm.pressed ? Theme.fill2 : bm.containsMouse ? Theme.fill : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durPop } }
        }
        GIcon {
            anchors.centerIn: parent
            name: b.icon
            size: 17
            color: bm.containsMouse ? Theme.label : Theme.label2
            scale: bm.pressed ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Theme.durPop } }
        }
        Hint { id: bm; hint: b.hint; onClicked: root.act(b.action) }
    }

    // soft drop shadow (the voice pill's, a little tighter for a small bar)
    RectangularShadow {
        anchors.fill: surface
        radius: surface.radius
        offset.y: 12; blur: 34; spread: -4
        color: Theme.rgba(Theme.t.shadow.focused.color, 0.7)
    }
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.tele ? 5 : height / 2
        color: Theme.glassOpaque ? Theme.glass : Theme.rgba(Theme.t.color.glass, Math.min(1, Theme.t.glass.alpha + 0.16))
        border.width: 1
        border.color: Theme.glassOpaque ? Theme.white(0.14) : Theme.rim
        HoverHandler { id: hover }
    }

    Row {
        id: row
        x: 5
        height: parent.height
        spacing: 4

        // ---- Ask (the primary action) ----
        Item {
            id: askBtn
            width: askRow.implicitWidth + 18; height: 30
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.fill: parent
                radius: root.tele ? 3 : 15
                color: askMouse.pressed ? Qt.alpha(root.accent, 0.26) : askMouse.containsMouse ? Qt.alpha(root.accent, 0.18) : Qt.alpha(root.accent, 0.1)
                border.width: 1
                border.color: Qt.alpha(root.accent, askMouse.containsMouse ? 0.7 : 0.45)
                Behavior on color { ColorAnimation { duration: Theme.durPop } }
            }
            Row {
                id: askRow
                anchors.centerIn: parent
                spacing: 7
                scale: askMouse.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                AskIcon { anchors.verticalCenter: parent.verticalCenter; name: "spark"; size: 12; color: root.accent }
                Label { anchors.verticalCenter: parent.verticalCenter; px: 10; em: 0.1; text: "Ask"; color: Theme.label }
            }
            Hint { id: askMouse; hint: "Ask Claude about this"; onClicked: root.act("ask") }
        }
        Sep {}

        Btn { icon: "search"; hint: "Search the web"; action: "search" }
        Btn { icon: "translate"; hint: "Translate"; action: "translate" }
        Btn { icon: "content_copy"; hint: "Copy"; action: "copy" }
        Btn { icon: "move_to_inbox"; hint: "Drop on the shelf"; action: "shelf" }

        Sep { visible: root.info.isUrl || root.nextCase !== "" || root.info.isMath || root.canSpeak }
        Btn { visible: root.info.isUrl; icon: "open_in_new"; hint: "Open " + root.info.host; action: "open" }
        Btn {
            visible: root.nextCase !== ""
            icon: "match_case"
            hint: "Copy as " + (ST.caseNames[root.nextCase] ?? "")
            action: "case"
        }
        // ---- maths: the result inline (click = copy it) ----
        Item {
            visible: root.info.isMath
            width: calcRow.implicitWidth + 18; height: 30
            anchors.verticalCenter: parent.verticalCenter
            Rectangle {
                anchors.fill: parent
                radius: root.tele ? 3 : 15
                color: calcMouse.pressed ? Theme.fill2 : calcMouse.containsMouse ? Theme.fill : "transparent"
                border.width: 1
                border.color: Theme.hair
                Behavior on color { ColorAnimation { duration: Theme.durPop } }
            }
            Row {
                id: calcRow
                anchors.centerIn: parent
                spacing: 6
                Label { anchors.verticalCenter: parent.verticalCenter; px: 11; em: 0.04; text: "="; color: Theme.label3 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.calcText
                    font.family: Theme.fontLabel
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.features: ({ "tnum": 1 })
                    color: root.accent
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 150)
                }
            }
            Hint { id: calcMouse; hint: "Copy the result"; onClicked: root.act("calc") }
        }
        Btn { visible: root.canSpeak; icon: "volume_up"; hint: "Speak"; action: "speak" }
    }

    // ---- hint above the bar (below when the bar is under the pointer) ----
    Rectangle {
        id: tipBox
        readonly property bool on: root.shownTip !== ""
        // keeps the last hint while it fades out
        property string last: root.shownTip
        Connections { target: root; function onShownTipChanged() { if (root.shownTip !== "") tipBox.last = root.shownTip; } }
        x: Math.round((root.width - width) / 2)
        y: root.tipBelow ? root.height + (on ? 7 : 3) : -height - (on ? 7 : 3)
        width: Math.min(tipLbl.implicitWidth, root.width + 30) + 18; height: 22
        radius: root.tele ? 3 : 11
        color: Theme.glassOpaque ? Theme.glass : Theme.rgba(Theme.t.color.glass, Math.min(1, Theme.t.glass.alpha + 0.16))
        border.width: 1
        border.color: root.flash !== "" ? Qt.alpha(root.accent, 0.55) : Theme.hair
        opacity: on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
        Behavior on y { NumberAnimation { duration: Theme.durPop; easing.type: Easing.OutCubic } }
        Label { id: tipLbl; anchors.centerIn: parent; width: Math.min(implicitWidth, root.width + 30); elide: Text.ElideRight; px: 9.5; em: 0.1; text: tipBox.last; color: root.flash !== "" ? Theme.label : Theme.label2 }
    }
}

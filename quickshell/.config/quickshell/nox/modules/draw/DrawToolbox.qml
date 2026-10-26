pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.core
import qs.components

// The draw toolbox (modules/draw), in the voice pill's language: 46 px, opaque glass, 1 px hairline
// with the accent hairline while live, mono uppercase labels (Telemetry). Left to right:
//   grip (pulsing dot + the tool's name; drag here to move the toolbox) | 8 tools | colours |
//   FADE chip (pens fade after a few seconds) | undo · clear · screenshot · off
// Hovering a button shows its name and key above the toolbox.
Item {
    id: root
    required property var ctl
    signal dragBy(real dx, real dy)

    readonly property bool tele: Theme.square
    readonly property color accent: Theme.accent
    implicitWidth: row.implicitWidth + 14
    implicitHeight: 46
    width: implicitWidth
    height: implicitHeight
    property string tip: ""

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
        width: 1; height: 22
        anchors.verticalCenter: parent?.verticalCenter
        color: Theme.hair
    }
    // a square icon button; on = the selected tool (accent wash + accent icon + hairline)
    component Btn: Item {
        id: b
        property string icon
        property bool on: false
        property string hint
        property color tint: Theme.label2
        signal clicked()
        width: 30; height: 30
        anchors.verticalCenter: parent?.verticalCenter
        Rectangle {
            anchors.fill: parent
            radius: root.tele ? 3 : 9
            color: b.on ? Qt.alpha(root.accent, 0.16) : bm.containsMouse ? Theme.fill : "transparent"
            border.width: b.on ? 1 : 0
            border.color: Qt.alpha(root.accent, 0.55)
            Behavior on color { ColorAnimation { duration: Theme.durPop } }
        }
        GIcon {
            anchors.centerIn: parent
            name: b.icon
            size: 17
            filled: b.on
            weight: b.on ? 500 : 400
            color: b.on ? root.accent : bm.containsMouse ? Theme.label : b.tint
            scale: bm.pressed ? 0.88 : 1
            Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: Theme.durPop } }
        }
        MouseArea {
            id: bm
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: root.tip = containsMouse ? b.hint : (root.tip === b.hint ? "" : root.tip)
            onClicked: b.clicked()
        }
    }

    // soft drop shadow (the voice pill's)
    RectangularShadow {
        anchors.fill: surface
        radius: surface.radius
        offset.y: 18; blur: 50; spread: -4
        color: Theme.rgba(Theme.t.shadow.focused.color, 0.7)
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.tele ? 5 : height / 2
        color: Theme.glassOpaque ? Theme.glass : Theme.rgba(Theme.t.color.glass, Math.min(1, Theme.t.glass.alpha + 0.16))
        border.width: 1
        border.color: Theme.glassOpaque ? Theme.white(0.14) : Theme.rim
        // accent hairline while drawing (off with the hand: the apps have the pointer)
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(root.accent, 0.5)
            opacity: root.ctl.hand ? 0.25 : 1
            Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        }
    }

    Row {
        id: row
        x: 7
        height: parent.height
        spacing: 6

        // ---- grip: live dot + the tool's name ----
        Item {
            id: grip
            width: gripRow.implicitWidth + 16; height: 30
            anchors.verticalCenter: parent.verticalCenter
            Row {
                id: gripRow
                x: 9
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Item {
                    width: 9; height: 9
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        property real p: 0
                        anchors.centerIn: parent
                        width: 9 + 18 * p; height: width
                        radius: root.tele ? 1 + 3 * p : width / 2
                        color: Qt.alpha(root.ctl.ink, 0.6 * (1 - p))
                        NumberAnimation on p {
                            running: root.visible && !root.ctl.hand
                            from: 0; to: 1; duration: 1300; loops: Animation.Infinite
                            easing.type: Easing.BezierSpline; easing.bezierCurve: [0, 0, 0.58, 1, 1, 1]
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: root.tele ? 1 : 4.5
                        color: root.ctl.hand ? Theme.label3 : root.ctl.ink
                        Behavior on color { ColorAnimation { duration: Theme.durPop } }
                    }
                }
                Label {
                    width: 62
                    px: 10.5; em: 0.1
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.ctl.tools.find(t => t.id === root.ctl.tool)?.name ?? ""
                    color: Theme.label
                }
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property point at
                onPressed: m => at = mapToItem(null, m.x, m.y)
                onPositionChanged: m => {
                    // hover moves come through too (hoverEnabled, for the hint): only a held button drags
                    if (!pressed) return;
                    const p = mapToItem(null, m.x, m.y);
                    root.dragBy(p.x - at.x, p.y - at.y);
                    at = p;
                }
                hoverEnabled: true
                onContainsMouseChanged: root.tip = containsMouse ? "Drag to move" : (root.tip === "Drag to move" ? "" : root.tip)
            }
        }
        Sep {}

        // ---- tools ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: root.ctl.tools
                Btn {
                    required property var modelData
                    required property int index
                    icon: modelData.icon
                    on: root.ctl.tool === modelData.id
                    hint: modelData.name + "  " + (index + 1) + (modelData.id === "hand" ? " · Tab" : "")
                    onClicked: root.ctl.setTool(modelData.id)
                }
            }
        }
        Sep {}

        // ---- colours ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: root.ctl.palette.length
                Item {
                    id: sw
                    required property int index
                    readonly property bool on: root.ctl.colorIx === index
                    readonly property color c: root.ctl.colorAt(index)
                    width: 22; height: 30
                    anchors.verticalCenter: parent?.verticalCenter
                    // selected: a ring round it and a soft glow
                    RectangularShadow {
                        anchors.centerIn: parent
                        width: 12; height: 12; radius: 6
                        blur: 10
                        color: Qt.alpha(sw.c, 0.8)
                        opacity: sw.on ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 18; height: 18; radius: root.tele ? 4 : 9
                        color: "transparent"
                        border.width: 1.5
                        border.color: Qt.alpha(sw.c, 0.9)
                        opacity: sw.on ? 1 : swm.containsMouse ? 0.4 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: sw.on ? 10 : 9; height: width; radius: root.tele ? 2 : width / 2
                        color: sw.c
                        Behavior on width { NumberAnimation { duration: Theme.durPop } }
                    }
                    MouseArea {
                        id: swm
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: root.tip = containsMouse ? "Colour · C / scroll" : (root.tip === "Colour · C / scroll" ? "" : root.tip)
                        onClicked: root.ctl.colorIx = sw.index
                    }
                }
            }
        }
        Sep {}

        // ---- FADE chip (the voice pill's TIDY chip): pens fade after a few seconds ----
        Rectangle {
            id: fadeChip
            anchors.verticalCenter: parent.verticalCenter
            height: 30
            width: fadeRow.implicitWidth + 20
            radius: root.tele ? 3 : 15
            color: fadeMouse.containsMouse ? Theme.fill : "transparent"
            border.width: 1
            border.color: Theme.hair
            Behavior on color { ColorAnimation { duration: Theme.durPop } }
            Row {
                id: fadeRow
                anchors.centerIn: parent
                spacing: 7
                Item {
                    width: 6; height: 6
                    anchors.verticalCenter: parent.verticalCenter
                    RectangularShadow {
                        anchors.fill: parent
                        blur: 8
                        color: Qt.alpha(root.accent, 0.9)
                        opacity: root.ctl.fade ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: root.tele ? 0 : 3
                        color: root.ctl.fade ? root.accent : Theme.label3
                        Behavior on color { ColorAnimation { duration: Theme.durPop } }
                    }
                }
                Label {
                    px: 10; em: 0.09
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Fade"
                    color: root.ctl.fade ? Theme.label : Theme.label3
                    Behavior on color { ColorAnimation { duration: Theme.durPop } }
                }
            }
            MouseArea {
                id: fadeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                readonly property string h: "Fade pens after " + Math.round(root.ctl.fadeMs / 1000) + " s · F"
                onContainsMouseChanged: root.tip = containsMouse ? h : (root.tip === h ? "" : root.tip)
                onClicked: root.ctl.fade = !root.ctl.fade
            }
        }

        // ---- actions ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Btn { icon: "undo"; hint: "Undo · Z / right click"; tint: root.ctl.count ? Theme.label2 : Theme.label3; onClicked: root.ctl.undo() }
            Btn { icon: "delete_sweep"; hint: "Clear · Backspace"; tint: root.ctl.count ? Theme.label2 : Theme.label3; onClicked: root.ctl.clear() }
            Btn { icon: "photo_camera"; hint: "Screenshot · S"; onClicked: root.ctl.capture() }
            Btn { icon: "close"; hint: "Off · Esc / Super+A"; onClicked: root.ctl.off() }
        }
    }

    // ---- hint above the toolbox ----
    Rectangle {
        id: tipBox
        readonly property bool on: root.tip !== ""
        property string shownTip: ""
        onOnChanged: if (on) shownTip = root.tip
        Connections { target: root; function onTipChanged() { if (root.tip !== "") tipBox.shownTip = root.tip; } }
        anchors.horizontalCenter: parent.horizontalCenter
        y: -height - (on ? 8 : 4)
        width: tipLbl.implicitWidth + 18; height: 22
        radius: root.tele ? 3 : 11
        color: Theme.glassOpaque ? Theme.glass : Theme.rgba(Theme.t.color.glass, Math.min(1, Theme.t.glass.alpha + 0.16))
        border.width: 1
        border.color: Theme.hair
        opacity: on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
        Behavior on y { NumberAnimation { duration: Theme.durPop; easing.type: Easing.OutCubic } }
        Label { id: tipLbl; anchors.centerIn: parent; px: 9.5; em: 0.1; text: tipBox.shownTip; color: Theme.label2 }
    }
}

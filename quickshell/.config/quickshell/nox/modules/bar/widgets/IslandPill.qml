pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.core
import qs.components

// The island pill's content for one IslandEntry: [lead] text  trail. The lead depends on the
// kind: recording = red square, mic = level bars, agent = status dot (pings while it needs you),
// timer = ring of the time left, music = cover, anything else = the entry's glyph.
// Nothing here animates by itself except the agent ping, and that only while `animate` (the
// island is on screen) and the entry is urgent.
Row {
    id: root
    property IslandEntry entry: null
    property bool animate: true
    property real maxText: 170
    readonly property string kind: entry?.kind ?? ""
    readonly property bool mono: Theme.labelsMono && Theme.square
    spacing: 7

    Item {
        id: lead
        anchors.verticalCenter: parent.verticalCenter
        width: root.kind === "mic" ? bars.width : root.kind === "music" ? 18 : 14
        height: 14

        // recording: red square (mock .mbi.rec)
        Rectangle {
            visible: root.kind === "recording"
            anchors.centerIn: parent
            width: 9; height: 9; radius: Theme.square ? 1 : 2
            color: Theme.red
        }
        // mic: the last few levels as bars
        Row {
            id: bars
            visible: root.kind === "mic"
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    readonly property var lv: root.entry?.level ?? []
                    readonly property real v: lv.length ? Math.max(0, Math.min(1, Number(lv[Math.max(0, lv.length - 5 + index)] ?? 0))) : 0
                    y: (14 - height) / 2
                    width: 2.5; radius: 1.25
                    height: 3 + v * 11
                    color: root.entry?.tint ?? Theme.accent
                }
            }
        }
        // agent: status dot, pings while the session needs you
        Item {
            visible: root.kind === "agent"
            anchors.centerIn: parent
            width: 7; height: 7
            Rectangle {
                id: ping
                anchors.centerIn: parent
                width: 7; height: 7
                radius: Theme.square ? 0 : 3.5
                color: "transparent"
                border.width: 1.5
                border.color: Theme.accent
                opacity: 0
                visible: root.entry?.urgent ?? false
                ParallelAnimation {
                    running: ping.visible && root.animate && root.kind === "agent"
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) { ping.scale = 1; ping.opacity = 0; }
                    NumberAnimation { target: ping; property: "scale"; from: 1; to: 2.6; duration: 1300; easing.type: Easing.OutCubic }
                    NumberAnimation { target: ping; property: "opacity"; from: 0.75; to: 0; duration: 1300; easing.type: Easing.OutCubic }
                }
            }
            Rectangle {
                anchors.centerIn: parent
                width: Theme.square ? 6 : 7; height: width
                radius: Theme.square ? 0 : width / 2
                color: root.entry?.tint ?? Theme.label
            }
        }
        // timer: ring of the time left
        Shape {
            visible: root.kind === "timer" && (root.entry?.progress ?? -1) >= 0
            anchors.centerIn: parent
            width: 13; height: 13
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Theme.white(0.22)
                strokeWidth: 2
                fillColor: "transparent"
                PathAngleArc { centerX: 6.5; centerY: 6.5; radiusX: 5.5; radiusY: 5.5; startAngle: 0; sweepAngle: 360 }
            }
            ShapePath {
                strokeColor: root.entry?.tint ?? Theme.accent
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: 6.5; centerY: 6.5; radiusX: 5.5; radiusY: 5.5
                    startAngle: -90
                    sweepAngle: -360 * Math.max(0.001, 1 - Math.max(0, root.entry?.progress ?? 0))
                }
            }
        }
        // music: cover (note glyph until it loads / without one)
        Rectangle {
            visible: root.kind === "music"
            anchors.centerIn: parent
            width: 18; height: 18
            radius: Theme.square ? 2 : 4
            color: Theme.fill2
            clip: true
            Glyph { anchors.centerIn: parent; name: "note"; size: 12; color: Theme.label2; visible: cover.status !== Image.Ready }
            Image {
                id: cover
                anchors.fill: parent
                source: root.kind === "music" && root.entry ? root.entry.art : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 36; sourceSize.height: 36
            }
        }
        // everything else (and a done timer): the glyph
        Glyph {
            visible: (root.kind === "download" || root.kind === "shelf" || (root.kind === "timer" && (root.entry?.progress ?? -1) < 0)) && name !== ""
            anchors.centerIn: parent
            name: root.entry?.glyph ?? ""
            size: 14
            color: root.entry?.tint ?? Theme.label
        }
    }
    GText {
        id: label
        visible: text !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.maxText)
        text: root.entry?.text ?? ""
        color: Theme.label
        font.family: root.mono ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: root.mono ? 12 : Theme.fontSize
        font.weight: Font.Medium
        font.capitalization: root.mono ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.mono ? 0.6 : 0
    }
    GText {
        visible: text !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.entry?.trail ?? ""
        color: label.visible ? Theme.label2 : Theme.label
        font.family: root.mono ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: root.mono ? 12 : Theme.fontSize
        font.capitalization: root.mono ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.mono ? 0.6 : 0
        font.features: (root.entry?.trailMono ?? true) ? ({ "tnum": 1 }) : ({})
    }
}

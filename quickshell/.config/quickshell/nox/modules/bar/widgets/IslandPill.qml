pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs.core
import qs.components

// The island pill's face for one IslandEntry (design mock .isl-l): [lead] text [ring] meta [tail].
//   agent    work = stepped spinner, project, age, strip of this turn's tool calls
//            need = accent ping, NEEDS YOU, project · tool      done = check badge, DONE, project
//   recording  blinking red dot, time, REC          mic   orange dot, mic glyph, MIC, phase
//   timer    ring of the time left, time (paused: PAUSED; rang: ping, TIMER DONE, label)
//   download glyph, name, turning ring, bytes so far (done: check badge, DOWNLOADED, name)
//   music    cover, title, eq bars (paused: flat)      shelf  tray glyph, N ITEMS PARKED
// Motion: nothing here runs a timer or an animation. Everything that loops (spinner, ping, blink,
// ring, eq) is a pure function of `frame`, which Island.qml steps at 12 Hz only while a looping
// face is live and on screen; frame 0 = still.
Row {
    id: root
    property IslandEntry entry: null
    property int frame: 0
    property real maxText: 150
    readonly property string kind: entry?.kind ?? ""
    readonly property string mode: entry?.mode ?? ""
    readonly property bool mono: Theme.labelsMono && Theme.square
    readonly property real ms: frame * 83.33          // the frame clock in ms
    // 0..1 phase of a loop of `period` ms
    function phase(period) { return (ms % period) / period; }
    function wave(period) { return 0.5 - 0.5 * Math.cos(2 * Math.PI * phase(period)); }
    spacing: 7
    height: 20

    // ---- lead -------------------------------------------------------------------------------
    Item {
        id: lead
        anchors.verticalCenter: parent.verticalCenter
        width: root.kind === "mic" ? 7 + 5 + 13 : root.kind === "music" ? 15 : 14
        height: 14

        // agent working: stepped spinner (mock .isl-spin, 800 ms a turn)
        Item {
            visible: root.kind === "agent" && root.mode === "work"
            anchors.centerIn: parent
            width: 11; height: 11
            rotation: Math.floor(root.phase(800) * 10) * 36
            Rectangle {
                anchors.fill: parent
                radius: Theme.square ? 1 : width / 2
                color: "transparent"
                border.width: 1.5
                border.color: Theme.fill3
                antialiasing: true
            }
            // the accent quarter: a square's top edge, a circle's top arc
            Rectangle {
                visible: Theme.square
                width: parent.width; height: 1.5
                color: Theme.accent
                antialiasing: true
            }
            Shape {
                visible: !Theme.square
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.accent
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc { centerX: 5.5; centerY: 5.5; radiusX: 4.75; radiusY: 4.75; startAngle: -135; sweepAngle: 90 }
                }
            }
        }
        // needs you / timer rang: accent ping (mock .isl-ping, agPing 1.3 s)
        Item {
            readonly property bool on: (root.kind === "agent" && root.mode === "need") || (root.kind === "timer" && root.mode === "ring")
            visible: on
            anchors.centerIn: parent
            width: 7; height: 7
            readonly property real p: root.phase(1300)
            Rectangle {
                anchors.centerIn: parent
                readonly property real grow: 7 * Math.min(1, parent.p / 0.75)
                width: 7 + 2 * grow; height: width
                radius: Theme.square ? 0 : width / 2
                color: "transparent"
                border.width: 1.5
                border.color: Theme.accent
                opacity: root.frame === 0 ? 0 : 0.75 * (1 - Math.min(1, parent.p / 0.75))
            }
            Rectangle {
                anchors.fill: parent
                radius: Theme.square ? 0 : width / 2
                color: Theme.accent
            }
        }
        // done: check in an accent ring (mock .isl-ok)
        Rectangle {
            visible: (root.kind === "agent" && root.mode === "done") || (root.kind === "download" && root.mode === "done")
            anchors.centerIn: parent
            width: 14; height: 14
            radius: Theme.square ? 2 : 7
            color: Theme.rgba(Theme.t.color.accent, 0.16)
            border.width: 1
            border.color: Theme.rgba(Theme.t.color.accent, 0.6)
            Glyph { anchors.centerIn: parent; name: "check"; size: 9; color: Theme.accent; strokeWidth: 2.6 }
        }
        // recording: blinking red dot (mock .isl-rec, islBlink 1.4 s)
        Item {
            visible: root.kind === "recording"
            anchors.centerIn: parent
            width: 8; height: 8
            opacity: 1 - 0.65 * root.wave(1400)
            RectangularShadow {
                anchors.fill: dot
                radius: dot.radius
                blur: 8
                color: Theme.rgba(Theme.t.color.red, 0.8)
            }
            Rectangle {
                id: dot
                anchors.fill: parent
                radius: Theme.square ? 0 : 4
                color: Theme.red
            }
        }
        // mic: orange dot + mic glyph (mock .isl-mic)
        Row {
            visible: root.kind === "mic"
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 7; height: 7
                RectangularShadow {
                    anchors.fill: md
                    radius: md.radius
                    blur: 8
                    color: Theme.rgba(Theme.t.color.orange, 0.75)
                }
                Rectangle { id: md; anchors.fill: parent; radius: Theme.square ? 0 : 3.5; color: Theme.orange }
            }
            Glyph { anchors.verticalCenter: parent.verticalCenter; name: "mic"; size: 13; color: Theme.label2 }
        }
        // timer: ring of the time left (mock .isl-ring)
        Ring {
            visible: root.kind === "timer" && root.mode !== "ring"
            anchors.centerIn: parent
            value: Math.max(0, root.entry?.progress ?? 0)
        }
        // music: cover (mock .isl-art)
        Rectangle {
            visible: root.kind === "music"
            anchors.centerIn: parent
            width: 15; height: 15
            radius: Theme.square ? 2 : 3
            color: Theme.fill2
            clip: true
            Glyph { anchors.centerIn: parent; name: "note"; size: 10; color: Theme.label2; visible: cover.status !== Image.Ready }
            Image {
                id: cover
                anchors.fill: parent
                source: root.kind === "music" && root.entry ? root.entry.art : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 30; sourceSize.height: 30
            }
            Rectangle { anchors.fill: parent; radius: parent.radius; color: "transparent"; border.width: 0.5; border.color: Theme.white(0.2) }
        }
        // download running, shelf: the glyph
        Glyph {
            visible: (root.kind === "download" && root.mode !== "done") || root.kind === "shelf"
            anchors.centerIn: parent
            name: root.entry?.glyph ?? ""
            size: 13
            color: Theme.label2
        }
    }

    // ---- text -------------------------------------------------------------------------------
    Text {
        id: label
        visible: text !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, root.maxText)
        elide: Text.ElideRight
        text: root.entry?.text ?? ""
        color: (root.entry?.textAccent ?? false) ? Theme.accent : Theme.label
        font.family: root.mono ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: root.mono ? 11 : 12
        font.weight: Font.Medium
        font.capitalization: root.mono ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.mono ? 0.66 : 0
        font.features: ({ "tnum": 1 })
    }

    // download: a ring that turns while bytes arrive (the browser gives no total, so no %)
    Item {
        visible: root.kind === "download" && root.mode === "run"
        anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 14
        Ring { anchors.fill: parent; value: 0.28; rotation: Math.floor(root.phase(1000) * 12) * 30 }
    }

    Text {
        visible: text !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: root.entry?.meta ?? ""
        color: Theme.label3
        font.family: Theme.fontLabel
        font.pixelSize: 10
        font.weight: Font.Medium
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
        font.features: ({ "tnum": 1 })
    }

    // ---- tail -------------------------------------------------------------------------------
    // agent: this turn's recent tool calls, one segment each (mock .isl-bar)
    Row {
        visible: root.kind === "agent" && root.mode === "work"
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.square ? 2 : 1
        Repeater {
            model: 8
            Rectangle {
                required property int index
                readonly property string s: (root.entry?.segs ?? [])[index] ?? ""
                width: Theme.square ? 3 : 4; height: Theme.square ? 4 : 3
                radius: Theme.square ? 0 : 1
                color: s === "run" ? Theme.label : s === "er" ? Theme.orange : s === "ok" ? Theme.accent : Theme.white(0.16)
            }
        }
    }
    // music: eq bars (mock .isl-eq, pbEq 900 ms, staggered); paused = flat
    Item {
        visible: root.kind === "music"
        anchors.verticalCenter: parent.verticalCenter
        width: 14; height: 11
        Row {
            anchors.bottom: parent.bottom
            spacing: 2
            Repeater {
                model: [0, 300, 600, 150]
                Rectangle {
                    required property int modelData
                    readonly property bool play: root.mode === "play"
                    readonly property real p: ((root.ms + modelData) % 900) / 900
                    anchors.bottom: parent.bottom
                    width: 2; radius: Theme.square ? 0 : 1
                    height: !play ? 3 : 11 * (0.35 + 0.65 * (0.5 - 0.5 * Math.cos(2 * Math.PI * p)))
                    color: play ? Theme.accent : Theme.label3
                }
            }
        }
    }

    // a 14px ring: track + `value` (0..1) of accent from 12 o'clock, clockwise
    component Ring: Shape {
        id: ring
        property real value: 0
        width: 14; height: 14
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.fill3
            strokeWidth: 2.2
            fillColor: "transparent"
            PathAngleArc { centerX: 7; centerY: 7; radiusX: 5.6; radiusY: 5.6; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: Theme.accent
            strokeWidth: 2.2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: 7; centerY: 7; radiusX: 5.6; radiusY: 5.6; startAngle: -90; sweepAngle: 360 * Math.max(0.001, Math.min(1, ring.value)) }
        }
    }
}

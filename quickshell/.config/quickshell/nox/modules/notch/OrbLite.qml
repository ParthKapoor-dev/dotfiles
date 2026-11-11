import QtQuick
import QtQuick.Shapes
import qs.core

// The fallback agent orb (no shader): a small lit sphere whose colour is the session's state (mock .orb).
//   work  accent, a sheen turning once every 1.6 s     need  red, fast sheen + a ping ring
//   done  warm white, still                             idle  dim, still, no glow
//   watch teal (observed only, e.g. Codex), slow sheen
// The glow is a radial gradient around it, so nothing here needs a shader or a layer.
Item {
    id: orb
    property string mode: "work"
    property real size: 16
    property bool animate: true
    readonly property color c: mode === "need" ? Theme.red
        : mode === "done" ? "#F4F1EE"
        : mode === "idle" ? "#5A5450"
        : mode === "watch" ? "#64D2FF"
        : Theme.accent
    readonly property bool lit: mode !== "idle"
    readonly property bool spinning: animate && (mode === "work" || mode === "need" || mode === "watch")
    implicitWidth: size
    implicitHeight: size

    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1); }

    // glow
    Shape {
        visible: orb.lit
        anchors.centerIn: parent
        width: orb.size * 3.2; height: width
        preferredRendererType: Shape.CurveRenderer
        opacity: 0.85
        SequentialAnimation on opacity {
            running: orb.spinning
            loops: Animation.Infinite
            NumberAnimation { to: 0.55; duration: orb.mode === "need" ? 600 : 1300; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0.9; duration: orb.mode === "need" ? 600 : 1300; easing.type: Easing.InOutSine }
        }
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: orb.size * 1.6; centerY: orb.size * 1.6; centerRadius: orb.size * 1.6
                focalX: centerX; focalY: centerY
                GradientStop { position: 0.0; color: Qt.rgba(orb.c.r, orb.c.g, orb.c.b, 0.55) }
                GradientStop { position: 0.32; color: Qt.rgba(orb.c.r, orb.c.g, orb.c.b, 0.22) }
                GradientStop { position: 1.0; color: Qt.rgba(orb.c.r, orb.c.g, orb.c.b, 0) }
            }
            PathAngleArc { centerX: orb.size * 1.6; centerY: orb.size * 1.6; radiusX: orb.size * 1.6; radiusY: orb.size * 1.6; startAngle: 0; sweepAngle: 360 }
        }
    }
    // ping ring (needs you)
    Rectangle {
        visible: orb.mode === "need" && orb.animate
        anchors.centerIn: parent
        width: orb.size; height: width; radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: Qt.rgba(orb.c.r, orb.c.g, orb.c.b, 0.7)
        opacity: 0
        ParallelAnimation on scale {
            running: orb.mode === "need" && orb.animate
            loops: Animation.Infinite
            NumberAnimation { from: 0.8; to: 2.1; duration: 1400; easing.type: Easing.OutCubic }
        }
        SequentialAnimation on opacity {
            running: orb.mode === "need" && orb.animate
            loops: Animation.Infinite
            NumberAnimation { from: 0.9; to: 0; duration: 1400; easing.type: Easing.OutCubic }
        }
    }
    // body
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: orb.size * 0.5; centerY: orb.size * 0.5; centerRadius: orb.size * 0.5
                focalX: orb.size * 0.35; focalY: orb.size * 0.3; focalRadius: 0
                GradientStop { position: 0.0; color: orb.lit ? "#FFFFFF" : "#8A837E" }
                GradientStop { position: 0.16; color: orb.mix(orb.c, "#FFFFFF", 0.4) }
                GradientStop { position: 0.45; color: orb.c }
                GradientStop { position: 0.8; color: orb.mix(orb.c, "#000000", 0.6) }
                GradientStop { position: 1.0; color: "#000000" }
            }
            PathAngleArc { centerX: orb.size / 2; centerY: orb.size / 2; radiusX: orb.size / 2; radiusY: orb.size / 2; startAngle: 0; sweepAngle: 360 }
        }
    }
    // sheen: a bright wedge turning over the body
    Shape {
        visible: orb.spinning
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: 0.5
        RotationAnimation on rotation {
            running: orb.spinning
            loops: Animation.Infinite
            from: 0; to: 360
            duration: orb.mode === "need" ? 700 : orb.mode === "watch" ? 3200 : 1600
        }
        ShapePath {
            strokeWidth: -1
            fillGradient: ConicalGradient {
                centerX: orb.size / 2; centerY: orb.size / 2; angle: 0
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.55; color: "transparent" }
                GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.75) }
                GradientStop { position: 0.82; color: "transparent" }
                GradientStop { position: 1.0; color: "transparent" }
            }
            PathAngleArc { centerX: orb.size / 2; centerY: orb.size / 2; radiusX: orb.size / 2 - 0.5; radiusY: orb.size / 2 - 0.5; startAngle: 0; sweepAngle: 360 }
        }
    }
}

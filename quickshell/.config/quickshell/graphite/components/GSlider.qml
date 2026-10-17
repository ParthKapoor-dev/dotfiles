import QtQuick
import qs.core

// Pill slider (mock .sld): 28px, white 13% track, white 92% fill that is never narrower than the
// knob (28 + (w-28)*v), dark glyph at 7px. value 0..1; moved(v) while dragging/scrolling.
// tokens ui.meter = "dot-matrix": mock telemetry .sld = 21px dot grid, white lit dots, no glyph.
Item {
    id: root
    property real value: 0
    property string icon: ""
    property real step: 0.05
    signal moved(real v)
    implicitHeight: Theme.dotMatrix ? 21 : 28
    implicitWidth: 200
    readonly property real v: Math.max(0, Math.min(1, value))

    Rectangle {
        visible: !Theme.dotMatrix
        anchors.fill: parent
        radius: height / 2
        // hover: track and fill brighten; the knob end (fill's round cap) grows a touch while
        // hovered/dragged; wheel/keyboard steps ease, drags follow the pointer directly
        color: Theme.white(sm.containsMouse || sm.pressed ? 0.17 : 0.13)
        Behavior on color { ColorAnimation { duration: Theme.durHover } }
        Rectangle {
            id: fillBar
            anchors.verticalCenter: parent.verticalCenter
            property real grow: sm.containsMouse || sm.pressed ? 2 : 0
            height: parent.height + grow
            x: -grow / 2
            radius: height / 2
            width: parent.height + (parent.width - parent.height) * root.v + grow
            color: Theme.white(sm.containsMouse || sm.pressed ? 1 : 0.92)
            Behavior on color { ColorAnimation { duration: Theme.durHover } }
            Behavior on grow { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
            Behavior on width { enabled: !sm.pressed; NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        }
        Glyph {
            x: 7; anchors.verticalCenter: parent.verticalCenter
            name: root.icon; size: 16
            color: Qt.rgba(0, 0, 0, 0.62)
        }
    }
    DotMeter {
        visible: Theme.dotMatrix
        anchors.fill: parent
        style: "dots"
        value: root.v
    }
    MouseArea {
        id: sm
        anchors.fill: parent
        hoverEnabled: true
        function at(x) { return Math.max(0, Math.min(1, (x - 14) / Math.max(1, width - 28))); }
        onPressed: m => root.moved(Theme.dotMatrix ? Math.max(0, Math.min(1, m.x / width)) : at(m.x))
        onPositionChanged: m => { if (pressed) root.moved(Theme.dotMatrix ? Math.max(0, Math.min(1, m.x / width)) : at(m.x)); }
        onWheel: w => root.moved(Math.max(0, Math.min(1, root.value + (w.angleDelta.y > 0 ? root.step : -root.step))))
    }
}

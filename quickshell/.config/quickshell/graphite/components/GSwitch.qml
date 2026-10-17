import QtQuick
import qs.core

// macOS-style switch (mock .switch: 32x19, knob 15 with a soft shadow; square in Telemetry)
Rectangle {
    id: root
    property bool checked: false
    signal toggled()
    implicitWidth: 32; implicitHeight: 19
    radius: Theme.square ? 3 : height / 2
    color: checked ? Theme.accent : Theme.fill3
    Behavior on color { ColorAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    Rectangle {   // knob shadow (0 1px 3px rgba(0,0,0,.35))
        x: knob.x; y: knob.y + 1; width: knob.width; height: knob.height; radius: knob.radius
        color: Qt.rgba(0, 0, 0, 0.3)
    }
    Rectangle {
        id: knob
        width: 15; height: 15; radius: Theme.square ? 2 : 7.5; y: 2
        x: root.checked ? root.width - width - 2 : 2
        color: "white"
        Behavior on x { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.toggled() }
}

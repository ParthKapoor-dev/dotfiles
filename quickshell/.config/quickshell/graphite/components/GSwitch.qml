import QtQuick
import qs.core

// macOS-style switch (mock .switch: 32x19)
Rectangle {
    id: root
    property bool checked: false
    signal toggled()
    implicitWidth: 32; implicitHeight: 19
    radius: height / 2
    color: checked ? Theme.accent : Theme.fill3
    Behavior on color { ColorAnimation { duration: Theme.durFade } }
    Rectangle {
        width: 15; height: 15; radius: 7.5; y: 2
        x: root.checked ? root.width - width - 2 : 2
        color: "white"
        Behavior on x { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
    }
    MouseArea { anchors.fill: parent; onClicked: root.toggled() }
}

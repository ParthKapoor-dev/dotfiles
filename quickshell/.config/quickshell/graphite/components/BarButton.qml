import QtQuick
import qs.core

// Menu-bar item (mock .mbi): bar-6 tall, 9px side padding (7 for icons), radius 5 (3 square looks),
// hover/open = white 14%. Emits clicked(button) / wheel(delta) / entered().
Item {
    id: root
    default property alias content: row.data
    property bool active: false
    property real hpad: 9
    property alias hovered: mouse.containsMouse
    property alias spacing: row.spacing
    signal clicked(int button)
    signal wheel(int delta)
    signal entered()

    implicitHeight: Math.max(20, Theme.barHeight - 6)
    implicitWidth: row.implicitWidth + hpad * 2

    Rectangle {
        anchors.fill: parent
        radius: Theme.square ? 3 : 5
        color: Theme.white(0.14)
        opacity: root.active || mouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: m => root.clicked(m.button)
        onWheel: w => root.wheel(w.angleDelta.y)
        onEntered: root.entered()
    }
}

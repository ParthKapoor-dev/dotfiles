import QtQuick
import qs.core

// Menu-bar item: hover/open highlight, content centred, emits clicked(button) / wheel(delta).
Item {
    id: root
    default property alias content: row.data
    property bool active: false
    property real hpad: 7
    property alias hovered: mouse.containsMouse
    property alias spacing: row.spacing
    signal clicked(int button)
    signal wheel(int delta)

    implicitHeight: Theme.barHeight - 6
    implicitWidth: row.implicitWidth + hpad * 2

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusControl - 1
        color: Theme.fill2
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
    }
}

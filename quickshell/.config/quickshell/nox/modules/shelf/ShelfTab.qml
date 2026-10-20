import QtQuick
import QtQuick.Effects
import qs.core
import qs.services

// The collapsed shelf (mock .dsh-tab): a thin tab on the screen edge with the item count.
// Hover or click opens the shelf.
Item {
    id: tab
    property bool atLeft: false
    property bool hovered: mouse.containsMouse
    signal activated()
    width: hovered ? 24 : 20
    height: 76
    Behavior on width { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

    RectangularShadow {
        anchors.fill: face
        radius: face.radius
        offset.y: 10; blur: 30
        color: Theme.rgba("#000000", Theme.glassOpaque ? 0.7 : 0.5)
    }
    // the edge side is square and runs off-screen (rounded corners face the desktop only)
    Rectangle {
        id: face
        x: tab.atLeft ? -radius : 0
        width: parent.width + radius
        height: parent.height
        radius: Theme.square ? 3 : 9
        color: Theme.glassOpaque ? Theme.rgba(Theme.t.color.glass, 1) : Theme.rgba(Theme.t.color.glass, Math.min(1, Theme.t.glass.alpha + 0.18))
        border.width: 1
        border.color: Theme.glassOpaque ? Theme.white(0.14) : Theme.rim
        clip: true
        // Telemetry: a 2px accent line on the desktop side
        Rectangle {
            visible: Theme.square
            x: tab.atLeft ? parent.width - 3 : 1
            y: 1; width: 2; height: parent.height - 2
            color: Theme.accent
        }
    }
    Column {
        x: (tab.width - width) / 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 7
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 4; height: 4
            radius: Theme.square ? 0 : 2
            color: Theme.accent
            layer.enabled: true
            layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.accent; shadowBlur: 0.5; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Shelf.count
            font.family: Theme.square ? Theme.fontNumeric : Theme.fontUi
            font.pixelSize: Theme.square ? 15 : 12
            font.weight: Theme.square ? 800 : Font.Bold
            font.variableAxes: Theme.square ? Theme.numericAxes : ({})
            color: Theme.label
        }
        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 8; height: lbl.implicitWidth
            Text {
                id: lbl
                anchors.centerIn: parent
                rotation: 90
                text: "SHELF"
                font.family: Theme.fontLabel; font.pixelSize: 8; font.weight: Font.DemiBold
                font.letterSpacing: 1.6
                color: Theme.label3
            }
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: tab.activated()
    }
}

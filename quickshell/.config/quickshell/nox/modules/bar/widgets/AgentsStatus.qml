import QtQuick
import qs.core
import qs.components
import qs.services

// Coding agents (services/Agents, Mission Control): a square dot + count. Hidden while no session
// is alive. Needs you = accent dot pinging + how many wait; working = white dot + how many work;
// all idle = dim dot + session count. Click (or Ctrl+Super+M) opens Mission Control.
BarButton {
    id: root
    property string widgetId: "agents"
    hpad: 8
    spacing: 6
    visible: Agents.any
    active: Agents.open
    onClicked: Agents.toggle()

    readonly property bool need: Agents.needsYou > 0
    readonly property bool work: !need && Agents.working > 0

    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: 7; height: 7
        Rectangle {
            id: ping
            anchors.centerIn: parent
            width: dot.width; height: dot.height
            radius: dot.radius
            color: "transparent"
            border.width: 1.5
            border.color: Theme.accent
            opacity: 0
            visible: root.need
            ParallelAnimation {
                running: root.need && root.visible
                loops: Animation.Infinite
                NumberAnimation { target: ping; property: "scale"; from: 1; to: 2.6; duration: 1300; easing.type: Easing.OutCubic }
                NumberAnimation { target: ping; property: "opacity"; from: 0.75; to: 0; duration: 1300; easing.type: Easing.OutCubic }
            }
        }
        Rectangle {
            id: dot
            anchors.centerIn: parent
            width: Theme.square ? 6 : 7; height: width
            radius: Theme.square ? 0 : width / 2
            color: root.need ? Theme.accent : root.work ? Theme.label : Theme.label2
            Behavior on color { ColorAnimation { duration: Theme.durFade } }
        }
    }
    GText {
        anchors.verticalCenter: parent.verticalCenter
        text: String(root.need ? Agents.needsYou : root.work ? Agents.working : Agents.alive.length)
        color: root.need ? Theme.accent : Theme.label2
        font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: 11
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }
}

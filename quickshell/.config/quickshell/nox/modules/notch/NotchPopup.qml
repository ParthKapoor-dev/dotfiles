pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.services

// The notch popover under the bar pill (GPopup bar:notch, bare): a black card that shows the
// oldest request, a done card, or the panel (services/AgentNotch.mode).
Item {
    id: pop
    readonly property string mode: AgentNotch.mode
    readonly property real wantWidth: mode === "need" ? 560 : mode === "done" ? 520 : 640
    implicitWidth: wantWidth
    implicitHeight: (mode === "need" ? request.implicitHeight : mode === "done" ? done.implicitHeight : panel.implicitHeight)
    property real now: Date.now()
    Timer { interval: 1000; repeat: true; running: true; onTriggered: pop.now = Date.now() }

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: "#000000"
        border.width: 1
        border.color: pop.mode === "need" ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.35) : Theme.white(0.1)
        // a thin line of light along the top edge, in the state's colour
        Rectangle {
            anchors { top: parent.top; topMargin: 1; horizontalCenter: parent.horizontalCenter }
            width: parent.width * 0.5; height: 1
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: pop.mode === "need" ? Theme.red : pop.mode === "done" ? Theme.white(0.6) : Theme.accent }
                GradientStop { position: 1; color: "transparent" }
            }
        }
    }
    NotchRequest {
        id: request
        visible: pop.mode === "need"
        width: 560
        topPad: 20
        req: AgentNotch.req
        count: Agents.requests.length
        now: pop.now
        focus: visible
        onLater: AgentNotch.later()
    }
    NotchDone {
        id: done
        visible: pop.mode === "done"
        width: 520
        topPad: 20
        sid: AgentNotch.doneId
        focus: visible
        onClose: { AgentNotch.clearDone(); AgentNotch.close(); }
        onReplay: id => { AgentNotch.clearDone(); panel.replayOf(id); AgentNotch.show("replay"); }
    }
    NotchPanel {
        id: panel
        visible: pop.mode === "panel"
        width: 640
        topPad: 8
        now: pop.now
        focus: visible
        view: AgentNotch.view
        onViewChanged: AgentNotch.view = view
        onClose: AgentNotch.close()
    }
}

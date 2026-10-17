pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// Workspace dots (mock .wsdots/.wsd): 16px slots, current = 24px slot with a 16px pill
// (tokens ui.workspaceCurrent: accent in Ember), occupied = 55% white, empty = label3.
// tokens ui.workspaceStyle = "numbers": 01 02 03 in the label font, current one inverted.
Item {
    id: root
    property string widgetId: "workspaces"
    readonly property var options: Config.widget(widgetId)
    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.id > 0)
    readonly property int current: Hyprland.focusedWorkspace?.id ?? 1
    readonly property int count: Math.max(options.minCount ?? 5, current, ...workspaces.map(w => w.id))
    readonly property bool numbers: Theme.workspaceStyle === "numbers"

    implicitWidth: row.implicitWidth + 8 + 12      // padding 0 4 + margin 0 6
    implicitHeight: Math.max(20, Theme.barHeight - 6)

    function occupied(id) {
        const w = workspaces.find(x => x.id === id);
        return !!w && w.toplevels.values.length > 0;
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2
        Repeater {
            model: root.count
            Item {
                id: dot
                required property int index
                readonly property int wsId: index + 1
                readonly property bool cur: wsId === root.current
                readonly property bool occ: root.occupied(wsId)
                width: root.numbers ? num.implicitWidth + 4 : cur ? 24 : 16
                height: 16
                Behavior on width { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                // numbers (Telemetry .wsn: 10.5px label font, padding 0 3, radius 2)
                Rectangle {
                    visible: root.numbers
                    anchors.centerIn: parent
                    width: num.implicitWidth; height: 16
                    radius: 2
                    color: dot.cur ? Theme.workspaceCurrent : "transparent"
                    GText {
                        id: num
                        anchors.centerIn: parent
                        leftPadding: 3; rightPadding: 3
                        text: (dot.wsId < 10 ? "0" : "") + dot.wsId
                        font.family: Theme.fontLabel
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: dot.cur ? "black" : hover.containsMouse ? Theme.label : dot.occ ? Theme.label2 : Theme.label3
                    }
                }
                Rectangle {
                    visible: !root.numbers
                    anchors.centerIn: parent
                    height: 6; radius: 3
                    width: dot.cur ? 16 : 6
                    color: dot.cur ? Theme.workspaceCurrent : hover.containsMouse ? Theme.label : dot.occ ? Theme.white(0.55) : Theme.label3
                    Behavior on width { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                    Behavior on color { ColorAnimation { duration: Theme.durFade } }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Hypr.workspace(dot.wsId)
                }
            }
        }
    }
    WheelHandler {
        enabled: root.options.scroll !== false
        onWheel: e => Hypr.workspace(e.angleDelta.y > 0 ? "e-1" : "e+1")
    }
}

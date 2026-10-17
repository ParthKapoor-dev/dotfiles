pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.core
import qs.components

// Compact workspace dots (mock .wsd): current = wide pill, occupied = brighter dot.
Item {
    id: root
    property string widgetId: "workspaces"
    readonly property var options: Config.widget(widgetId)
    readonly property var workspaces: Hyprland.workspaces.values.filter(w => w.id > 0)
    readonly property int current: Hyprland.focusedWorkspace?.id ?? 1
    readonly property int count: Math.max(options.minCount ?? 4, current, ...workspaces.map(w => w.id))

    implicitWidth: row.implicitWidth + 8 + 12
    implicitHeight: Theme.barHeight - 6

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
                width: cur ? 24 : 16; height: 16
                Behavior on width { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                Rectangle {
                    anchors.centerIn: parent
                    height: 6; radius: 3
                    width: dot.cur ? 16 : 6
                    color: dot.cur || hover.containsMouse ? Theme.label : root.occupied(dot.wsId) ? Theme.white(0.55) : Theme.label3
                    Behavior on width { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                    Behavior on color { ColorAnimation { duration: Theme.durFade } }
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Hyprland.dispatch("workspace " + dot.wsId)
                }
            }
        }
    }
    WheelHandler {
        enabled: root.options.scroll !== false
        onWheel: e => Hyprland.dispatch(e.angleDelta.y > 0 ? "workspace e-1" : "workspace e+1")
    }
}

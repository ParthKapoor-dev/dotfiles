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

    // one text width for every number slot (mono label font: "01" == "10")
    TextMetrics { id: numW; text: "00"; font.family: Theme.fontLabel; font.pixelSize: 11; font.weight: Font.Medium }
    readonly property real numSlot: Math.ceil(numW.advanceWidth) + 6 + 4

    // The current-workspace marker is one item that slides between slots (x/width on the sheet
    // curve, transform-only for the row) instead of each dot growing/shrinking its own pill.
    Item {
        id: track
        anchors.centerIn: parent
        width: row.implicitWidth; height: 16
        Rectangle {
            id: marker
            readonly property int i: root.current - 1
            anchors.verticalCenter: parent.verticalCenter
            // dots: 24px current slot with a 16x6 pill; numbers: inverted label cell
            x: root.numbers ? i * (root.numSlot + row.spacing) + 2 : i * (16 + row.spacing) + 4
            width: root.numbers ? root.numSlot - 4 : 16
            height: root.numbers ? 16 : 6
            radius: root.numbers ? 2 : 3
            color: Theme.workspaceCurrent
            Behavior on x { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        }
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
                width: root.numbers ? root.numSlot : cur ? 24 : 16
                height: 16
                Behavior on width {
                    enabled: !root.numbers
                    NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
                }
                // numbers (Telemetry .wsn: 10.5px label font, padding 0 3, radius 2)
                GText {
                    id: num
                    visible: root.numbers
                    anchors.centerIn: parent
                    text: (dot.wsId < 10 ? "0" : "") + dot.wsId
                    font.family: Theme.fontLabel
                    font.pixelSize: 11
                    font.weight: Font.Medium
                    color: dot.cur ? "black" : hover.containsMouse ? Theme.label : dot.occ ? Theme.label2 : Theme.label3
                    Behavior on color { ColorAnimation { duration: Theme.durFade } }
                }
                // dot (hidden under the sliding pill when current)
                Rectangle {
                    visible: !root.numbers
                    anchors.centerIn: parent
                    width: 6; height: 6; radius: 3
                    opacity: dot.cur ? 0 : 1
                    color: hover.containsMouse ? Theme.label : dot.occ ? Theme.white(0.55) : Theme.label3
                    Behavior on color { ColorAnimation { duration: Theme.durFade } }
                    Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
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

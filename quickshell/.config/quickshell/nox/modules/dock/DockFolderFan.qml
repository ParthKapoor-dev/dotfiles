pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs.core
import qs.components
import qs.services

// The fanned-out apps of a dock folder (DockFolder's surface content; a plain Item so it can be
// rendered on its own). The bounding box of the arc: name pills left of the tile, the lean to the
// right; x is set here from fan.ctl.cx, the caller sets y.
Item {
    id: fan
    required property var ctl                    // the DockFolder (apps, geometry, pick, sel...)
    property real t: 1                           // 0 = all icons in the tile, 1 = fanned out
    property real total: 400                     // ms the whole open takes (stagger included)
    property real availableWidth: 1920
    readonly property alias hovered: fanHover.hovered
    // ctl: iconSize, cx (tile centre x), apps, open, keyboardNow, sel, popupId, pick(app)

    // ---- arc geometry (i = 0 is the bottom app) ----
    readonly property real step: ctl.iconSize + 12
    function lean(i) { return 2.4 * i * i; }                         // x offset from the tile centre
    function tilt(i) { return Math.atan(4.8 * i / step) * 180 / Math.PI * 0.35; }
    readonly property real fanH: ctl.apps.length * step + 8
    readonly property real fanRight: lean(Math.max(0, ctl.apps.length - 1)) + ctl.iconSize / 2 + 16
    readonly property real labelRoom: 198 + fan.ctl.iconSize / 2
    x: Math.max(4, fan.ctl.cx - labelRoom)
    width: Math.min(fan.availableWidth - x - 4, fan.ctl.cx - x + fan.fanRight)
    height: fan.fanH + 12
    HoverHandler { id: fanHover; onHoveredChanged: if (hovered && fan.ctl.open) fan.ctl.keyboardNow = true }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: Panels.close(fan.ctl.popupId)
        Keys.onUpPressed: fan.ctl.sel = Math.min(fan.ctl.apps.length - 1, fan.ctl.sel + 1)
        Keys.onDownPressed: fan.ctl.sel = Math.max(0, fan.ctl.sel - 1)
        Keys.onReturnPressed: if (fan.ctl.sel >= 0) fan.ctl.pick(fan.ctl.apps[fan.ctl.sel])
        Keys.onEnterPressed: if (fan.ctl.sel >= 0) fan.ctl.pick(fan.ctl.apps[fan.ctl.sel])
    }

    Repeater {
        model: fan.ctl.apps
        Item {
            id: row
            required property var modelData
            required property int index
            // this icon's own progress: staggered from the bottom up, eased
            readonly property real k: {
                const ms = fan.t * fan.total - index * 18;
                const p = Math.max(0, Math.min(1, ms / 220));
                return 1 - Math.pow(1 - p, 3);
            }
            readonly property bool hot: mouse.containsMouse || fan.ctl.sel === index
            readonly property bool running: modelData.toplevels.length > 0
            // resting place (centre of the icon) in fan coordinates
            readonly property real ix: fan.ctl.cx - fan.x + fan.lean(index)
            readonly property real iy: fan.height - 6 - fan.ctl.iconSize / 2 - index * fan.step
            // start: the tile, just under the fan's bottom edge
            readonly property real sx: fan.ctl.cx - fan.x
            readonly property real sy: fan.height + fan.ctl.iconSize * 0.3
            x: sx + (ix - sx) * k - width + fan.ctl.iconSize / 2
            y: sy + (iy - sy) * k - height / 2
            width: pill.width + 10 + fan.ctl.iconSize
            height: fan.ctl.iconSize
            opacity: Math.min(1, k * 1.6)
            rotation: -fan.tilt(index) * k
            transformOrigin: Item.Right
            scale: 0.5 + 0.5 * k

            // name pill (mock .docktip look)
            Rectangle {
                id: pill
                anchors.verticalCenter: parent.verticalCenter
                x: 0
                width: Math.min(name.implicitWidth, 160) + 20
                height: 24
                radius: Theme.square ? 3 : 12
                color: row.hot ? Theme.rgba(Theme.accent, Theme.square ? 0.9 : 0.85)
                    : (Theme.square ? Theme.rgba("#0A0A0A", 0.94) : Theme.rgba("#28282A", 0.86))
                border.width: Theme.rimWidth; border.color: Theme.white(0.14)
                Behavior on color { ColorAnimation { duration: Theme.durHover } }
                GText {
                    id: name
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, 160)
                    elide: Text.ElideRight
                    text: row.modelData.entry?.name || row.modelData.appId
                    color: row.hot ? "white" : Theme.label
                    font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
                    font.pixelSize: Theme.square ? 11 : 12.5
                    font.capitalization: Theme.square ? Font.AllUppercase : Font.MixedCase
                    font.letterSpacing: Theme.square ? 0.66 : 0
                }
            }
            IconImage {
                id: icon
                x: parent.width - fan.ctl.iconSize
                width: fan.ctl.iconSize; height: fan.ctl.iconSize
                implicitSize: 96
                source: Apps.iconFor(row.modelData)
                mipmap: true
                scale: row.hot ? 1.08 : 1
                Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
            }
            // running dot, right of the icon (the dock's dot sits under it)
            Rectangle {
                readonly property bool bar: Theme.square
                visible: row.running
                x: parent.width + 4
                anchors.verticalCenter: parent.verticalCenter
                width: bar ? 2 : 4; height: bar ? 8 : 4; radius: bar ? 0 : 2
                color: bar ? Theme.accent : Theme.workspaceCurrent
                opacity: bar ? 1 : 0.8
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onContainsMouseChanged: if (containsMouse) fan.ctl.sel = -1
                onClicked: m => {
                    if (m.button === Qt.MiddleButton) { Panels.close(fan.ctl.popupId); Panels.overviewOpen = false; Apps.launch(row.modelData); }
                    else fan.ctl.pick(row.modelData);
                }
            }
        }
    }
}

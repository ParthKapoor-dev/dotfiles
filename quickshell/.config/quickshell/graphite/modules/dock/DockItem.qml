import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.core
import qs.services

// One dock tile (mock .dt): icon grows with scale_, 4px running dot, separator variant.
Item {
    id: root
    property var item
    property real size: 56
    property real scale_: 1
    readonly property bool sep: item?.sep ?? false
    property real s: scale_
    readonly property real iconSize: size * s
    readonly property string label: item?.entry?.name || item?.appId || ""
    readonly property bool running: (item?.toplevels.length ?? 0) > 0
    readonly property alias hovered: mouse.containsMouse
    signal menuRequested()

    Behavior on s { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

    width: sep ? 13 : iconSize + 4
    height: sep ? size + 12 : iconSize + 6 + 6

    // separator (mock .dsep)
    Rectangle {
        visible: root.sep
        width: 1; x: 6
        anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.topMargin: 10; anchors.bottomMargin: 10
        color: Theme.white(0.2)
    }

    IconImage {
        id: icon
        visible: !root.sep
        x: 2; y: 6
        width: root.iconSize; height: root.iconSize
        implicitSize: root.size * 1.5
        source: root.sep ? "" : Apps.iconFor(root.item)
        mipmap: true
        opacity: mouse.pressed ? 0.7 : 1
    }

    Rectangle {
        visible: !root.sep
        width: 4; height: 4; radius: 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 1
        color: Theme.label
        opacity: root.running ? 0.8 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !root.sep
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: m => {
            if (m.button === Qt.RightButton) root.menuRequested();
            else if (m.button === Qt.MiddleButton) Apps.launch(root.item);
            else { Panels.close(); Apps.activate(root.item); }
        }
    }
}

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs.core
import qs.components
import qs.services

// One dock tile (mock .dt): `size` wide (+2px margins), icon grows with the magnification scale,
// 6px under the icon for the running indicator (4px dot; Telemetry: 8x2 accent bar).
// Icons are normalised: their opaque bounding box is measured once (Canvas) and scaled to
// `fill` of the tile, so icons with and without built-in padding look the same size.
Item {
    id: root
    property var item
    property real size: 44
    property real scale_: 1
    readonly property bool sep: item?.sep ?? false
    property real s: scale_
    readonly property real iconSize: size * s
    readonly property string label: item?.stack === "downloads" ? "Downloads" : item?.stack === "trash" ? "Trash"
        : (item?.entry?.name || item?.appId || "")
    readonly property bool running: (item?.toplevels.length ?? 0) > 0
    readonly property alias hovered: mouse.containsMouse
    readonly property string source: sep ? "" : Apps.iconFor(item)
    readonly property real fill: 0.9                       // target visual size of the icon content
    readonly property real norm: sep ? 1 : Math.min(1.25, Apps.iconScale(item))
    signal menuRequested()

    Behavior on s { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

    width: sep ? 13 : iconSize + 4
    height: sep ? size + 12 : iconSize + 6

    // separator (mock .dsep: 1px white 20%, 10px vertical inset, 6px side margins)
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
        x: 2; y: 0
        width: root.iconSize; height: root.iconSize
        implicitSize: 96
        source: root.source
        mipmap: true
        scale: root.norm
        // tokens ui.dockIcons = "monochrome-until-running"
        readonly property bool mono: Theme.dockIcons === "monochrome-until-running" && !root.running
        opacity: mouse.pressed ? 0.7 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
        layer.enabled: mono && !mouse.containsMouse
        layer.effect: MultiEffect { saturation: -1; brightness: -0.08 }
    }

    // one-shot measurement of the icon's opaque bounds (cached per app in Apps.measured)
    Loader {
        active: !root.sep && root.source !== "" && Apps.measured[root.item.key] === undefined
            && (Config.opt.dock?.normalizeIcons ?? true)
        sourceComponent: Item {
            width: 64; height: 64
            opacity: 0.01
            // the icon is loaded through an Image (sized request, like IconImage); Canvas.loadImage()
            // on image://icon URLs crashes KIconLoader, so the canvas draws this item instead
            Image {
                id: probe
                width: 64; height: 64
                source: root.source
                sourceSize.width: 64; sourceSize.height: 64
                visible: false
                onStatusChanged: if (status === Image.Ready) cv.requestPaint()
            }
            Canvas {
                id: cv
                width: 64; height: 64
                renderStrategy: Canvas.Immediate
                onPaint: {
                    if (probe.status !== Image.Ready) return;
                    const ctx = getContext("2d");
                    ctx.clearRect(0, 0, 64, 64);
                    ctx.drawImage(probe, 0, 0, 64, 64);
                    const d = ctx.getImageData(0, 0, 64, 64).data;
                    let x0 = 64, y0 = 64, x1 = -1, y1 = -1;
                    for (let y = 0; y < 64; y++) for (let x = 0; x < 64; x++) {
                        if (d[(y * 64 + x) * 4 + 3] > 24) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
                    }
                    ctx.clearRect(0, 0, 64, 64);
                    const ext = Math.max(x1 - x0 + 1, y1 - y0 + 1);
                    Apps.setMeasured(root.item.key, ext > 8 ? Math.round(root.fill * 64 / ext * 100) / 100 : 1);
                }
            }
        }
    }

    // running indicator (mock .dt .run)
    Rectangle {
        visible: !root.sep
        readonly property bool bar: Theme.square
        width: bar ? 8 : 4; height: bar ? 2 : 4; radius: bar ? 0 : 2
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom; anchors.bottomMargin: 1
        color: bar ? Theme.accent : Theme.workspaceCurrent
        opacity: root.running ? (bar ? 1 : 0.8) : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !root.sep
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onPressed: Panels.notePointer()
        onClicked: m => {
            if (m.button === Qt.RightButton) root.menuRequested();
            else if (m.button === Qt.MiddleButton) { if (!root.item.stack) Apps.launch(root.item); }
            else { Panels.close(); Apps.activate(root.item); }
        }
    }
}

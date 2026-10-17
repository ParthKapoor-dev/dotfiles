pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core

// Rounded screen corners: four tiny overlay surfaces (namespace graphite:corners, no input), each
// a black quarter-circle mask of radius tokens size.screenCorner (0 = off). Hidden on fullscreen
// workspaces (corners.hideOnFullscreen).
// The four windows come from a nested Variants, not a Repeater: a Repeater only instantiates
// Item delegates inside a parent Item, so with a PanelWindow delegate inside a Scope it created
// nothing (no graphite:corners layer at all). Fullscreen hides them (visible) instead of
// destroying and re-creating the surfaces on every fullscreen toggle.
Variants {
    model: Theme.screenCorner > 0 ? Quickshell.screens : []

    Scope {
        id: scr
        required property ShellScreen modelData
        readonly property bool hidden: (Config.opt.corners?.hideOnFullscreen ?? true)
            && (Hyprland.monitorFor(modelData)?.activeWorkspace?.hasFullscreen ?? false)
        Variants {
            model: [0, 1, 2, 3]
            PanelWindow {
                id: c
                required property int modelData
                readonly property bool right: modelData % 2 === 1
                readonly property bool bottom: modelData >= 2
                readonly property real r: Theme.screenCorner
                screen: scr.modelData
                visible: !scr.hidden
                WlrLayershell.namespace: "graphite:corners"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                exclusionMode: ExclusionMode.Ignore
                anchors.top: !bottom; anchors.bottom: bottom
                anchors.left: !right; anchors.right: right
                implicitWidth: r; implicitHeight: r
                color: "transparent"
                mask: Region {}
                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    // corner square minus a quarter circle centred on the inner corner
                    transform: Scale { origin.x: c.r / 2; origin.y: c.r / 2; xScale: c.right ? -1 : 1; yScale: c.bottom ? -1 : 1 }
                    ShapePath {
                        fillColor: "black"; strokeWidth: -1
                        startX: 0; startY: 0
                        PathLine { x: c.r; y: 0 }
                        PathArc { x: 0; y: c.r; radiusX: c.r; radiusY: c.r; direction: PathArc.Counterclockwise }
                        PathLine { x: 0; y: 0 }
                    }
                }
            }
        }
    }
}

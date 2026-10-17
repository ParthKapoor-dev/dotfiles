pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core

// Glass popup on its own layer surface (namespace graphite:popup so Hyprland can blur it).
// - open state lives in Panels.popup (one popup at a time); the window only exists while shown
// - closes on outside click (HyprlandFocusGrab; bar windows are included so bar buttons
//   switch popups instead of closing-then-reopening) and on Esc
// - placement: under `anchorItem` (left edges aligned, clamped to screen) or at the screen's
//   right/left edge (`align`)
Scope {
    id: root
    required property string popupId
    property Item anchorItem: null
    property string align: anchorItem ? "item" : "right"   // "item" | "left" | "right"
    property real popupWidth: 290
    property real padding: 6
    property bool fromBottom: false         // open upwards from the bottom edge (dock menus)
    property real bottomOffset: 0
    property string namespace: "graphite:popup"
    property Component content
    property ShellScreen screen: anchorItem?.QsWindow.window?.screen ?? Quickshell.screens[0] ?? null

    readonly property bool open: Panels.popup === popupId
    Component.onCompleted: Panels.registerPopup(popupId)
    Component.onDestruction: Panels.unregisterPopup(popupId)
    property bool shown: false
    property real anchorX: 0
    readonly property real shadowPad: 28

    onOpenChanged: {
        if (open) {
            if (anchorItem) anchorX = anchorItem.mapToItem(null, 0, 0).x;
            hideTimer.stop();
            shown = true;
        } else {
            hideTimer.restart();
        }
    }
    Timer { id: hideTimer; interval: Theme.durFade; onTriggered: root.shown = false }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win
            screen: root.screen
            color: "transparent"
            WlrLayershell.namespace: root.namespace
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0

            anchors.top: !root.fromBottom
            anchors.bottom: root.fromBottom
            anchors.left: root.align !== "right"
            anchors.right: root.align === "right"
            // body position inside the window; window margins never go negative
            readonly property real gap: 6
            readonly property real bodyX: {
                if (root.align === "right") return root.shadowPad;
                const sw = win.screen ? win.screen.width : 1920;
                const want = root.align === "left" ? 8 : Math.max(8, Math.min(root.anchorX, sw - root.popupWidth - 8));
                return want - Math.max(0, want - root.shadowPad);
            }
            margins.top: 0
            margins.bottom: root.bottomOffset
            margins.right: 0
            margins.left: {
                if (root.align === "right") return 0;
                const sw = win.screen ? win.screen.width : 1920;
                const want = root.align === "left" ? 8 : Math.max(8, Math.min(root.anchorX, sw - root.popupWidth - 8));
                return Math.max(0, want - root.shadowPad);
            }
            implicitWidth: bodyX + root.popupWidth + (root.align === "right" ? 8 : root.shadowPad)
            implicitHeight: body.height + gap + root.shadowPad
            mask: Region { item: body }

            HyprlandFocusGrab {
                active: root.open
                windows: [win].concat(Panels.barWindows)
                onCleared: Panels.close(root.popupId)
            }

            RectangularShadow {
                anchors.fill: body
                radius: body.radius
                offset.y: 8
                blur: 24
                spread: -2
                color: Theme.rgba("#000000", 0.38)
                opacity: body.opacity
            }

            Glass {
                id: body
                x: win.bodyX
                y: (root.fromBottom ? root.shadowPad : win.gap) + (root.open ? 0 : (root.fromBottom ? 6 : -6))
                width: root.popupWidth
                height: loader.implicitHeight + root.padding * 2
                opacity: root.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.onEscapePressed: Panels.close(root.popupId)
                }
                Loader {
                    id: loader
                    x: root.padding; y: root.padding
                    width: parent.width - root.padding * 2
                    sourceComponent: root.content
                }
            }
        }
    }
}

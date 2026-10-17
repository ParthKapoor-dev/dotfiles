pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core

// Glass popover on its own layer surface (namespace graphite:popup so Hyprland can blur it).
// - open state lives in Panels.popup (one popup at a time); the window only exists while shown
// - closes on outside click (HyprlandFocusGrab; bar windows are included so bar buttons
//   switch popups in one click) and on Esc
// - placement (mock Menu._mount): align "item" = left edge under anchorItem (menus),
//   "itemRight" = right edge under anchorItem (status popovers), "right"/"left" = screen edge
//   panels (Control Center, Notification Center)
// - motion: fade (tokens motion.pop, ease); panels also slide (`slide`: "down" | "left" | "")
Scope {
    id: root
    required property string popupId
    property Item anchorItem: null
    property string align: anchorItem ? "item" : "right"
    property real popupWidth: 290
    property real padding: 6
    property real gap: align === "itemRight" ? 5 : align === "item" ? 3 : 6
    property real edge: 8                   // distance from the screen edge for right/left panels
    property bool fromBottom: false         // open upwards from the bottom edge (dock menus)
    property real bottomOffset: 0
    property string slide: (align === "right" || align === "left") ? "down" : ""
    property bool fillHeight: false         // panel spans the screen height (Notification Center)
    property bool bare: false               // no glass body (content draws its own cards)
    property real radius: align === "right" || align === "left" ? Theme.radiusPanel + 2 : Theme.radiusMenu
    property string namespace: "graphite:popup"
    property Component content
    property ShellScreen screen: anchorItem?.QsWindow.window?.screen ?? Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
    readonly property alias window: loader.item

    readonly property bool open: Panels.popup === popupId
    Component.onCompleted: Panels.registerPopup(popupId)
    Component.onDestruction: Panels.unregisterPopup(popupId)
    property bool shown: false
    property real anchorX: 0
    property real anchorW: 0
    readonly property real shadowPad: 56

    onOpenChanged: {
        if (open) {
            if (anchorItem) {
                const p = anchorItem.mapToItem(null, 0, 0);
                anchorX = p.x; anchorW = anchorItem.width;
            }
            hideTimer.stop();
            shown = true;
        } else {
            hideTimer.restart();
        }
    }
    Timer { id: hideTimer; interval: Theme.durSheet; onTriggered: root.shown = false }

    LazyLoader {
        id: loader
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

            readonly property real sw: win.screen ? win.screen.width : 1920
            // where the body's left edge should be on screen
            readonly property real wantX: {
                if (root.align === "right") return sw - root.edge - root.popupWidth;
                if (root.align === "left") return root.edge;
                if (root.align === "itemRight") return Math.max(6, Math.min(root.anchorX + root.anchorW - root.popupWidth, sw - root.popupWidth - 6));
                return Math.max(6, Math.min(root.anchorX, sw - root.popupWidth - 6));
            }
            anchors.top: !root.fromBottom
            anchors.bottom: root.fromBottom || root.fillHeight
            anchors.left: true
            margins.left: Math.max(0, wantX - root.shadowPad)
            margins.bottom: root.fromBottom ? root.bottomOffset : 0
            readonly property real bodyX: wantX - margins.left
            implicitWidth: bodyX + root.popupWidth + root.shadowPad
            implicitHeight: root.fillHeight ? 0 : bodyH + root.gap + root.shadowPad
            readonly property real bodyH: root.fillHeight ? win.height - root.gap - root.edge : loaderItem.implicitHeight + root.padding * 2
            mask: Region { item: body }

            HyprlandFocusGrab {
                active: root.open
                windows: [win].concat(Panels.barWindows)
                onCleared: Panels.close(root.popupId)
            }

            // mock --sh-pop: 0 24px 64px rgba(0,0,0,.6), 0 4px 14px rgba(0,0,0,.35)
            RectangularShadow {
                visible: !root.bare
                anchors.fill: body
                radius: body.radius
                offset.y: 22; blur: 56; spread: -8
                color: Theme.rgba("#000000", 0.42)
                opacity: body.opacity
            }
            RectangularShadow {
                visible: !root.bare
                anchors.fill: body
                radius: body.radius
                offset.y: 4; blur: 14; spread: -2
                color: Theme.rgba("#000000", 0.3)
                opacity: body.opacity
            }

            Glass {
                id: body
                menu: true
                color: root.bare ? "transparent" : Theme.menuGlass
                border.width: root.bare ? 0 : (Theme.glassOpaque ? 1 : Theme.rimWidth)
                outline: !root.bare
                radius: root.radius
                x: win.bodyX + (root.slide === "left" ? (root.open ? 0 : root.popupWidth + 20) : 0)
                y: (root.fromBottom ? root.shadowPad : root.gap) + (root.slide === "down" && !root.open ? -6 : 0)
                width: root.popupWidth
                height: win.bodyH
                opacity: root.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: root.open ? Theme.durPop : Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                Behavior on x { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.onEscapePressed: Panels.close(root.popupId)
                }
                Loader {
                    id: loaderItem
                    x: root.padding; y: root.padding
                    width: parent.width - root.padding * 2
                    height: root.fillHeight ? parent.height - root.padding * 2 : implicitHeight
                    sourceComponent: root.content
                }
            }
        }
    }
}

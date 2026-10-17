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
// - motion (mock .menu/.pop/#cc/#nc): popovers fade in over motion.pop (ease) while growing from
//   0.96 at their anchor and dropping 4px into place (sheet curve); panels slide (`slide`: "down" |
//   "left" | ""). Closing plays the reverse (fade over motion.pop, settle to 0.98) and the surface
//   stays mapped until it has finished.
// - keyboard: a popover opened by a pointer click starts with keyboard focus None and asks for it
//   (OnDemand) once the pointer is over it. Hyprland moves pointer focus to a layer surface that
//   maps with keyboard interactivity, so a second click on the same bar button without moving
//   the mouse went nowhere ("two clicks to close"). Opened by shortcut/IPC = OnDemand at once (Esc).
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

    property bool keyboardNow: true         // false while a pointer-opened popover isn't hovered yet
    readonly property bool panel: align === "right" || align === "left"
    onOpenChanged: {
        if (open) {
            if (anchorItem) {
                const p = anchorItem.mapToItem(null, 0, 0);
                anchorX = p.x; anchorW = anchorItem.width;
            }
            keyboardNow = !Panels.pointerOpened();
            hideTimer.stop();
            shown = true;
        } else {
            hideTimer.restart();
        }
    }
    // keep the surface until the close motion is over (slides use the sheet duration)
    Timer { id: hideTimer; interval: (root.slide !== "" ? Theme.durSheet : Theme.durPop * 1.5) + 20; onTriggered: root.shown = false }

    LazyLoader {
        id: loader
        active: root.shown

        PanelWindow {
            id: win
            screen: root.screen
            color: "transparent"
            WlrLayershell.namespace: root.namespace
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open && (root.keyboardNow || bodyHover.hovered) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
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
            // the window never runs past the screen's right edge (an oversized layer surface
            // could be clamped/shifted by the compositor and cut the body's right side)
            implicitWidth: bodyX + root.popupWidth + Math.max(0, Math.min(root.shadowPad, sw - wantX - root.popupWidth))
            implicitHeight: root.fillHeight ? 0 : bodyH + root.gap + root.shadowPad
            // tallest body that still fits on screen (window sits under the bar's exclusive zone,
            // or above the dock for fromBottom); longer content scrolls instead of running off-screen
            readonly property real maxBodyH: Math.max(80, (win.screen ? win.screen.height : 1080)
                - Theme.barHeight - root.gap - root.edge - (root.fromBottom ? root.bottomOffset : 0))
            readonly property real contentH: loaderItem.implicitHeight + root.padding * 2
            readonly property real bodyH: root.fillHeight ? win.height - root.gap - root.edge : Math.min(contentH, maxBodyH)
            mask: Region { item: body }

            HyprlandFocusGrab {
                active: root.open
                windows: [win].concat(Panels.barWindows)
                onCleared: Panels.closeByGrab(root.popupId)
            }

            // open/close motion: one wrapper (shadows + body) fades and scales from the anchor
            Item {
                id: motion
                anchors.fill: parent
                // 0 = closed, 1 = open; opacity follows `fade`, geometry follows `grow`
                property real fade: root.open ? 1 : 0
                property real grow: root.open ? 1 : 0
                Behavior on fade { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on grow { NumberAnimation { duration: root.slide !== "" || root.open ? Theme.durSheet : Theme.durPop * 1.5; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                opacity: fade
                // popovers grow from the corner at their anchor (0.96 -> 1, 4px drop); closing
                // settles to 0.98 so it doesn't shrink back into the button
                readonly property real s0: root.slide !== "" ? 1 : (root.open ? 0.96 : 0.98)
                transform: [
                    Scale {
                        origin.x: root.align === "itemRight" || root.align === "right" ? body.x + body.width : body.x
                        origin.y: root.fromBottom ? body.y + body.height : body.y
                        xScale: motion.s0 + (1 - motion.s0) * motion.grow
                        yScale: xScale
                    },
                    Translate {
                        readonly property real d: 1 - motion.grow
                        x: root.slide === "left" ? d * (root.popupWidth + 20) : 0
                        y: root.slide === "down" ? -6 * d : root.slide === "" ? (root.fromBottom ? 4 : -4) * d : 0
                    }
                ]

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
                    x: win.bodyX
                    y: root.fromBottom ? root.shadowPad : root.gap
                    width: root.popupWidth
                    height: win.bodyH
                    HoverHandler { id: bodyHover }

                    Item {
                        anchors.fill: parent
                        focus: true
                        Keys.onEscapePressed: Panels.close(root.popupId)
                    }
                    Flickable {
                        id: scroller
                        x: root.padding; y: root.padding
                        width: parent.width - root.padding * 2
                        height: parent.height - root.padding * 2
                        contentWidth: width
                        contentHeight: root.fillHeight ? height : loaderItem.implicitHeight
                        interactive: !root.fillHeight && contentHeight > height + 0.5
                        clip: interactive
                        boundsBehavior: Flickable.StopAtBounds
                        Loader {
                            id: loaderItem
                            width: scroller.width
                            height: root.fillHeight ? scroller.height : implicitHeight
                            sourceComponent: root.content
                        }
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.services

// Notification popups (banners): glass cards stacked at a screen corner, newest on top.
// Own layer surface, namespace graphite:notifications; it only exists while a popup is shown.
// Pointer over the stack pauses all timeouts. shell.json notifications.{position,width,screen}.
Scope {
    id: root
    readonly property var opts: Config.opt.notifications ?? ({})
    readonly property string position: opts.position ?? "top-right"   // top-right | top-left | top
    readonly property real cardWidth: opts.width ?? 344
    readonly property real pad: 10    // room for the close button + shadow

    LazyLoader {
        // hidden while a right-side panel covers them (notifications.hideUnder: popup ids)
        active: Notifs.popups.length > 0 && (root.opts.hideUnder ?? ["notifications", "controlCenter"]).indexOf(Panels.popup) === -1

        PanelWindow {
            id: win
            screen: Config.screensFor(root.opts.screen ? [root.opts.screen] : [])[0] ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "graphite:notifications"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: 0
            anchors.top: true
            anchors.right: root.position === "top-right"
            anchors.left: root.position === "top-left"
            margins.top: 4
            margins.right: 4
            margins.left: 4
            implicitWidth: root.cardWidth + root.pad * 2
            implicitHeight: stack.implicitHeight + root.pad * 2
            mask: Region { item: maskArea }
            // input area = the stack plus room for the close buttons that overhang each card
            Item { id: maskArea; x: root.pad - 8; y: root.pad - 8; width: stack.width + 16; height: stack.height + 16 }

            HoverHandler { onHoveredChanged: Notifs.setPaused(hovered) }

            Column {
                id: stack
                x: root.pad; y: root.pad
                width: root.cardWidth
                spacing: 8
                Repeater {
                    model: Notifs.popups
                    Item {
                        id: slot
                        required property var modelData
                        width: stack.width
                        height: card.implicitHeight
                        RectangularShadow {
                            anchors.fill: card
                            radius: card.radius
                            offset.y: 6; blur: 20; spread: -2
                            color: Theme.rgba("#000000", 0.3)
                        }
                        NotificationCard {
                            id: card
                            width: parent.width
                            notification: slot.modelData.n
                            onCloseRequested: Notifs.hidePopup(slot.modelData.n)
                            // slide in from the edge (mock .bn)
                            x: shownIn ? 0 : (root.position === "top-left" ? -1 : 1) * (width + 24)
                            property bool shownIn: false
                            Component.onCompleted: shownIn = true
                            Behavior on x { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                        }
                    }
                }
            }
        }
    }
}

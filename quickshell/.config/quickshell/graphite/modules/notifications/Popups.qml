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
    readonly property real pad: 28    // room for the close button + shadow

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
            // mock #banners: bar + 8px, 10px from the screen edge. Layer margins can't be negative,
            // so with the 28px shadow pad inside the window the cards used to land 28px under the bar
            // and 28px from the edge. Now the window ignores the bar's zone and starts pad px above
            // the wanted card top (the pad overlaps the bar but is outside the input mask), and on
            // the anchored side the card sits `edge` px from the screen edge (the shadow beyond it
            // would be off-screen anyway).
            readonly property real edge: 10
            readonly property real topY: (Config.moduleEnabled("bar") ? Theme.barHeight : 0) + 8
            readonly property bool atRight: root.position === "top-right"
            readonly property bool atLeft: root.position === "top-left"
            exclusionMode: ExclusionMode.Ignore
            anchors.top: true
            anchors.right: atRight
            anchors.left: atLeft
            margins.top: Math.max(0, topY - root.pad)
            implicitWidth: root.cardWidth + (atRight || atLeft ? root.pad + edge : root.pad * 2)
            implicitHeight: stack.implicitHeight + root.pad + (topY - margins.top)
            mask: Region { item: maskArea }
            // input area = the stack plus room for the close buttons that overhang each card
            Item { id: maskArea; x: stack.x - 8; y: stack.y - 8; width: stack.width + 16; height: stack.height + 16 }

            HoverHandler { onHoveredChanged: Notifs.setPaused(hovered) }

            Column {
                id: stack
                x: win.atLeft ? win.edge : root.pad
                y: win.topY - win.margins.top
                width: root.cardWidth
                spacing: 8
                Repeater {
                    // ScriptModel diffs by identity: only added/removed banners create/destroy
                    // delegates (a plain JS array model rebuilt every delegate on any change, so
                    // hovering - pause/resume rewrote the list - slid every banner in again)
                    model: ScriptModel { values: Notifs.popupNotifs }
                    Item {
                        id: slot
                        required property var modelData
                        width: stack.width
                        height: card.implicitHeight
                        RectangularShadow {
                            anchors.fill: card
                            radius: Theme.square ? 6 : 16
                            offset.y: 10; blur: 30; spread: -4
                            color: Theme.rgba("#000000", 0.32)
                            opacity: card.opacity
                        }
                        NotificationCard {
                            id: card
                            width: parent.width
                            notification: slot.modelData
                            onCloseRequested: Notifs.hidePopup(slot.modelData)
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

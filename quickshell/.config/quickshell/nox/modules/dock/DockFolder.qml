pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services

// Dock folder fan: a folder tile's apps rise from it in an arc that leans right as it climbs
// (macOS stack "fan"), each icon with its name on a glass pill to its left; the bottom app sits
// nearest the dock. One per dock window; Dock.qml calls toggle(tile) on a folder click.
// - open state is Panels.popup "dock:folder:<screen>", so opening any other popup (the dock's
//   right-click menu, a bar popover) closes it and the dock treats it like its menu (stays up)
// - closes on a click outside (HyprlandFocusGrab; the dock is in the grab, so clicking the
//   folder again closes it), on Esc, and after an app is picked
// - click an app = focus it (cycle its windows) or launch it, like its own dock tile; Mission
//   Control closes, as for any dock click. Up / Down + Enter pick from the keyboard once the
//   fan has keyboard focus (it asks for it when hovered, like GPopup)
// - motion: icons fly out of the tile one after another (18 ms apart, sheet curve) and drop
//   back into it on close; the surface only exists while open or closing (LazyLoader)
Scope {
    id: root
    required property PanelWindow dockWindow
    // distance from the screen bottom to the fan's bottom edge (above the magnified tile)
    property real bottomOffset: 80
    property real iconSize: Theme.dockSize

    readonly property string popupId: "dock:folder:" + (dockWindow?.screen?.name ?? "")
    readonly property bool open: Panels.popup === popupId
    property var tile: null                      // the folder's DockItem
    readonly property var apps: (tile?.item?.apps ?? []).slice(0, 12)
    property real cx: 0                          // tile centre, dock-window (= screen) x
    property bool shown: false
    property int sel: -1                         // keyboard selection
    property bool keyboardNow: false

    function toggle(t) {
        if (open && tile === t) { Panels.close(popupId); return; }
        tile = t;
        cx = t.mapToItem(null, t.width / 2, 0).x;
        sel = -1;
        keyboardNow = !Panels.pointerOpened();
        Panels.open(popupId);
    }
    function pick(a) {
        Panels.close(popupId);
        Panels.overviewOpen = false;
        Apps.activate(a);
    }
    Component.onCompleted: Panels.registerPopup(popupId)
    Component.onDestruction: Panels.unregisterPopup(popupId)
    onOpenChanged: {
        if (open) { hideTimer.stop(); shown = true; }
        else hideTimer.restart();
    }
    // the folder left the dock (unpinned, config edit) while open
    onAppsChanged: if (open && apps.length === 0) Panels.close(popupId)
    Timer { id: hideTimer; interval: Theme.durPop * 1.5 + 60; onTriggered: root.shown = false }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win
            screen: root.dockWindow.screen
            color: "transparent"
            WlrLayershell.namespace: "nox:popup"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open && (root.keyboardNow || fan.hovered) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { bottom: true; left: true; right: true }
            margins.bottom: root.bottomOffset
            implicitHeight: fan.height + 12
            mask: Region { item: fan }

            HyprlandFocusGrab {
                active: root.open
                windows: [win, root.dockWindow].concat(Panels.barWindows)
                onCleared: Panels.closeByGrab(root.popupId)
            }

            // open / close progress: 0 = all icons in the tile, 1 = fanned out
            // (starts at 0 and binds after creation, so the first open animates too)
            property real t: 0
            Component.onCompleted: t = Qt.binding(() => root.open ? 1 : 0)
            Behavior on t { NumberAnimation { duration: root.open ? 220 + 18 * root.apps.length : Theme.durPop * 1.5; easing.type: Easing.Linear } }
            readonly property real total: 220 + 18 * root.apps.length

            DockFolderFan {
                id: fan
                ctl: root
                t: win.t
                total: win.total
                availableWidth: win.width
                y: win.height - height
            }
        }
    }
}

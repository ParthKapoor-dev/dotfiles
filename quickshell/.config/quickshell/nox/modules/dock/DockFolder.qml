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
// File stacks (Apps: { fileStack, path, count }) use the same fan for files: the newest `count`
// entries of the folder by mtime (dotfiles and *.part / *.crdownload skipped), newest nearest the
// dock, then "Open in Files" on top. Click = xdg-open, drag = a real Wayland drag (text/uri-list).
// The folder is only listed while the fan is up (DockStack); the fan waits for that listing
// before it flies out. Thumbnails: DockFolderFan (freedesktop cache, else the image itself).
Scope {
    id: root
    required property PanelWindow dockWindow
    // distance from the screen bottom to the fan's bottom edge (above the magnified tile)
    property real bottomOffset: 80
    property real iconSize: Theme.dockSize

    readonly property string popupId: "dock:folder:" + (dockWindow?.screen?.name ?? "")
    readonly property bool open: Panels.popup === popupId
    property var tile: null                      // the folder's DockItem
    // file stack being shown (copied on toggle: the dock rebuilds its tiles on every window change)
    property bool isStack: false
    property string stackPath: ""
    property int stackCount: 12
    // rows that fit between the dock and the bar
    property real screenHeight: 900              // the dock's screen (logical px)
    readonly property int maxRows: Math.max(3, Math.floor((screenHeight - bottomOffset - 60) / (iconSize + 12)))
    readonly property var apps: isStack ? stackEntries : (tile?.item?.apps ?? []).slice(0, Math.min(12, maxRows))
    readonly property bool ready: !isStack || listed
    property real cx: 0                          // tile centre, dock-window (= screen) x
    property bool shown: false
    property int sel: -1                         // keyboard selection
    property bool keyboardNow: false
    property bool dragging: false                // a file is being dragged out (keeps the surface)

    function toggle(t) {
        if (open && tile === t) { Panels.close(popupId); return; }
        tile = t;
        isStack = !!t.item?.fileStack;
        if (isStack) { stackPath = t.item.path; stackCount = t.item.count; }
        cx = t.mapToItem(null, t.width / 2, 0).x;
        sel = -1;
        keyboardNow = !Panels.pointerOpened();
        Panels.open(popupId);
    }
    function pick(a) {
        Panels.close(popupId);
        Panels.overviewOpen = false;
        if (a.kind === "open") Apps.openPath(stackPath);
        else if (a.kind) Apps.openPath(a.path);
        else Apps.activate(a);
    }
    function dragBegan() { dragging = true; Panels.close(popupId); }
    function dragEnded() { dragging = false; if (!open) hideTimer.restart(); }
    Component.onCompleted: Panels.registerPopup(popupId)
    Component.onDestruction: Panels.unregisterPopup(popupId)
    onOpenChanged: {
        if (open) { hideTimer.stop(); shown = true; }
        else hideTimer.restart();
    }
    // the folder left the dock (unpinned, config edit) while open
    onAppsChanged: if (open && !isStack && apps.length === 0) Panels.close(popupId)
    Timer { id: hideTimer; interval: Theme.durPop * 1.5 + 60; onTriggered: if (!root.dragging) root.shown = false }

    // ---- file stack listing (exists only while the fan is up) ----
    DockStack {
        id: stack
        active: root.shown && root.isStack
        path: root.stackPath
        count: Math.min(root.stackCount, root.maxRows - 1)
    }
    readonly property var stackEntries: stack.entries
    readonly property bool listed: stack.ready
    readonly property var thumbs: stack.thumbs

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
                active: root.open && !root.dragging
                windows: [win, root.dockWindow].concat(Panels.barWindows)
                onCleared: Panels.closeByGrab(root.popupId)
            }

            // open / close progress: 0 = all icons in the tile, 1 = fanned out
            // (starts at 0 and binds after creation, so the first open animates too; a stack
            // waits for its listing)
            property real t: 0
            Component.onCompleted: t = Qt.binding(() => root.open && root.ready ? 1 : 0)
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

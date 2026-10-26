pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services

// One screen edge of the shelf (namespace nox:shelf, Top layer (Overlay over Mission Control), no exclusive zone).
// Wayland has no global "a drag started" signal, so the window always keeps a 2 px input strip on
// the edge (the middle 70% of its height): a drag reaching it enters this surface's DropArea, the
// shelf slides out as the drop target and the input region grows to the panel. Everything else of
// the window is input-transparent; with no items and no drag only the strip takes input.
PanelWindow {
    id: win
    required property ShellScreen modelData
    required property var ctl
    screen: modelData
    readonly property bool active: ctl.screenName === modelData.name
    readonly property bool atLeft: Shelf.side === "left"
    readonly property string st: active ? ctl.st : (Shelf.count > 0 ? "tab" : "hidden")
    readonly property bool shown: st === "open" || st === "target"
    readonly property real edgeGap: 10

    color: "transparent"
    WlrLayershell.namespace: "nox:shelf"
    // above Mission Control while it is open (ShelfView.overOverview)
    WlrLayershell.layer: ctl.overOverview ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: active && ctl.pinned ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.bottom: true
    anchors.left: atLeft
    anchors.right: !atLeft
    implicitWidth: 240

    mask: Region {
        item: strip
        Region { item: hit }
    }

    // the always-there drag sensor
    Item {
        id: strip
        x: win.atLeft ? 0 : win.width - 2
        width: 2
        y: Math.round(win.height * 0.15)
        height: Math.round(win.height * 0.7)
    }
    // input area for the current state
    Item {
        id: hit
        readonly property real panelX: win.atLeft ? win.edgeGap : win.width - win.edgeGap - panel.width
        x: win.st === "target" ? 0 : win.st === "tab" ? tab.x - 4 : win.shown ? panelX - 10 : 0
        width: win.st === "target" ? win.width : win.st === "tab" ? tab.width + 4 : win.shown ? panel.width + 20 : 0
        y: win.st === "tab" ? tab.y : win.shown ? panel.restY - (win.st === "target" ? 70 : 12) : 0
        height: win.st === "tab" ? tab.height : win.shown ? panel.height + (win.st === "target" ? 140 : 24) : 0
    }

    // inside the input region = over the tab, the panel or the strip: keeps the shelf open;
    // leaving it collapses after a moment (the controller's leave timer)
    HoverHandler {
        id: hover
        onHoveredChanged: win.ctl.setHover(hovered, win.modelData.name)
    }

    DropArea {
        id: drop
        anchors.fill: parent
        onEntered: d => {
            if (d.source) { d.accepted = false; return; }   // our own drag-out passing by
            win.ctl.dragEnter(win.modelData.name);
            d.accept(Qt.CopyAction);
        }
        onPositionChanged: d => {
            if (d.source) return;
            const r = panel.mapToItem(drop, 0, 0);
            win.ctl.over = d.x >= r.x - 34 && d.x <= r.x + panel.width + 34 && d.y >= r.y - 40 && d.y <= r.y + panel.height + 40
                || (win.atLeft ? d.x < 30 : d.x > win.width - 30);
        }
        onExited: win.ctl.dragLeave()
        onDropped: d => {
            if (d.source) { d.accepted = false; return; }
            const ok = win.ctl.ingest(d);
            if (ok) d.accept(Qt.CopyAction); else d.accepted = false;
        }
    }

    ShelfTab {
        id: tab
        atLeft: win.atLeft
        readonly property bool on: win.st === "tab"
        x: win.atLeft ? (on ? 0 : -width - 6) : (on ? win.width - width : win.width + 6)
        y: Math.round(win.height / 2 - height / 2)
        opacity: on ? 1 : 0
        Behavior on x { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        onActivated: win.ctl.openFromTab(win.modelData.name)
        onHoveredChanged: if (hovered) win.ctl.tabHovered(win.modelData.name)
    }

    Item {
        id: panel
        width: panelLoader.item ? panelLoader.item.width : 148
        height: panelLoader.item ? panelLoader.item.height : 0
        readonly property real restY: Math.round((win.height - height) / 2)
        readonly property real restX: win.atLeft ? win.edgeGap : win.width - win.edgeGap - width
        // slide in from the edge; over a drag target it leans 6 px out and grows a touch (mock .over)
        x: win.shown ? restX + (win.ctl.over && win.st === "target" ? (win.atLeft ? 6 : -6) : 0) : (win.atLeft ? -width - 30 : win.width + 30)
        y: restY
        scale: win.ctl.over && win.st === "target" ? 1.025 : 1
        opacity: win.shown ? 1 : 0
        Behavior on x { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        Behavior on scale { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        Loader {
            id: panelLoader
            active: win.active
            sourceComponent: ShelfPanel { ctl: win.ctl }
        }
        focus: win.active && win.ctl.pinned
        Keys.onEscapePressed: win.ctl.close()
    }
}

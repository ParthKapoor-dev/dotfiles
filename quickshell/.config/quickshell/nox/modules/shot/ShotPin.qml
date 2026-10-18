pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core

// One pinned screenshot: a borderless always-on-top image (Overlay layer surface, anchored
// top-left, moved by its margins). Drag = move; wheel = resize around the pointer;
// Ctrl/Shift + wheel = opacity; Esc, right/middle click or double click = close; C = copy.
// Keyboard focus is OnDemand: Esc works once the pin has been clicked.
// Namespace nox-shot-pin (outside ^nox:.* on purpose: no glass blur behind a translucent pin).
PanelWindow {
    id: pin
    required property var modelData          // { id, path, screen (name), slot }
    readonly property string path: modelData.path
    signal closeRequested()

    screen: Quickshell.screens.find(s => s.name === pin.modelData.screen) ?? Quickshell.screens[0] ?? null
    color: "transparent"
    WlrLayershell.namespace: "nox-shot-pin"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.left: true
    visible: img.status === Image.Ready && w > 0

    readonly property real sw: screen?.width ?? 1920
    readonly property real sh: screen?.height ?? 1080
    readonly property real ratio: img.implicitWidth > 0 ? img.implicitHeight / img.implicitWidth : 0.5625
    property real w: 0
    property real px: 0
    property real py: 0
    property real fade: 1
    margins.left: Math.round(px)
    margins.top: Math.round(py)
    implicitWidth: Math.max(1, Math.round(w))
    implicitHeight: Math.max(1, Math.round(w * ratio))

    // keep at least 40px of the pin on screen
    function moveTo(x, y) {
        px = Math.max(40 - w, Math.min(sw - 40, x));
        py = Math.max(40 - w * ratio, Math.min(sh - 40, y));
    }

    Component.onCompleted: {
        // 1:1 logical size (screenshots are taken at the monitor's scale), at most 40% of the
        // screen width; centred, each further pin 28px down-right of the previous one
        const dpr = screen?.devicePixelRatio ?? 1;
        w = Math.max(80, Math.min(img.implicitWidth / dpr, sw * 0.4));
        const off = (modelData.slot % 8) * 28;
        moveTo((sw - w) / 2 + off, (sh - w * ratio) / 2 + off);
    }

    Image {
        id: img
        anchors.fill: parent
        source: "file://" + pin.path
        cache: false              // the same path may be re-pinned after an annotate
        smooth: true
        mipmap: true
        opacity: pin.fade
    }
    // hairline so a pin reads as an object on any background (mock rim)
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: mouse.containsMouse ? Theme.rgba(Theme.t.color.accent, 0.8) : Theme.white(0.18)
        opacity: Math.max(pin.fade, 0.5)
        Behavior on border.color { ColorAnimation { duration: Theme.durHover } }
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: pin.closeRequested()
        Keys.onPressed: e => {
            if (e.key === Qt.Key_C) { Quickshell.execDetached(["sh", "-c", "wl-copy --type image/png < \"$1\"", "sh", pin.path]); Panels.hud("Copied", "clip"); }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real ax: 0
        property real ay: 0
        // the window moves under the pointer, so the press point stays the reference
        onPressed: m => { ax = m.x; ay = m.y; }
        onPositionChanged: m => { if (pressed && (m.buttons & Qt.LeftButton)) pin.moveTo(pin.px + m.x - ax, pin.py + m.y - ay); }
        onClicked: m => { if (m.button !== Qt.LeftButton) pin.closeRequested(); }
        onDoubleClicked: pin.closeRequested()
        onWheel: e => {
            const d = (e.angleDelta.y || e.angleDelta.x) / 120;
            if (!d) return;
            if (e.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) {
                pin.fade = Math.max(0.15, Math.min(1, pin.fade + d * 0.08));
                return;
            }
            const nw = Math.max(80, Math.min(pin.sw * 1.5, pin.w * Math.pow(1.1, d)));
            const k = nw / pin.w;
            // zoom around the pointer
            const nx = pin.px + e.x * (1 - k), ny = pin.py + e.y * (1 - k);
            pin.w = nw;
            pin.moveTo(nx, ny);
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.core
import qs.components

// What hint mode draws over one screen (a plain Item, so the offscreen harness can render it;
// Hints.qml puts it in the layer surface): a light dim, a chip per target and the hint pill
// under the bar (mock .ask-hint: dot, what to do, element count / "no elements", keycaps).
// targets: [{ label, kind: window|element|bar|dock, x, y, w, h (screen-local), title }]
Item {
    id: root
    property var targets: []
    property string typed: ""
    property string status: "scanning"     // scanning | ready | none (no AT-SPI tree) | off
    property int elementCount: 0
    property real dim: 0.16
    property real barH: Theme.barHeight
    property int miss: 0                    // bumped on a letter no label has: the pill shakes
    onMissChanged: shake.restart()

    Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, root.dim) }

    // windows first, so element chips (inside the focused window) draw over a window chip
    Repeater {
        model: root.targets
        HintChip {
            required property var modelData
            label: modelData.label
            kind: modelData.kind
            title: modelData.title ?? ""
            typed: root.typed
            z: kind === "window" ? 0 : 1
            readonly property var t: modelData
            // element: its top-left corner (centred on a short one); bar: on the item (the bar
            // is tall enough, and below it would cover the window's own chips); dock: above
            // the icon; window: centred. Always fully on screen.
            readonly property real px: kind === "element" ? t.x - 2
                : t.x + (t.w - width) / 2
            readonly property real py: kind === "element" ? (t.h < height + 6 ? t.y + (t.h - height) / 2 : t.y - 2)
                : kind === "dock" ? t.y - height - 5
                : t.y + (t.h - height) / 2
            x: Math.round(Math.max(2, Math.min(root.width - width - 2, px)))
            y: Math.round(Math.max(2, Math.min(root.height - height - 2, py)))
        }
    }

    // ---- hint pill: under the bar, or above the dock when chips sit where it would go ----
    function crowded(y0, y1) {
        const x0 = width / 2 - 230, x1 = width / 2 + 230;
        return targets.filter(t => t.kind !== "window" && t.x < x1 && t.x + t.w > x0 && t.y < y1 && t.y + t.h > y0).length;
    }
    readonly property real topY: barH + 18
    readonly property real lowY: height - Theme.dockSize - 112
    readonly property bool pillLow: crowded(topY - 4, topY + 36) > crowded(lowY - 4, lowY + 36)
    Rectangle {
        id: pill
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.pillLow ? root.lowY : root.topY
        z: 2
        height: 32
        width: pillRow.width + 18
        radius: Theme.square ? 4 : 16
        color: Theme.glassOpaque ? Theme.rgba(Theme.t.color.glass, 1) : Theme.menuGlass
        border.width: 1
        border.color: Theme.white(0.14)
        transform: Translate { id: nudge }
        SequentialAnimation {
            id: shake
            NumberAnimation { target: nudge; property: "x"; to: -5; duration: 45; easing.type: Easing.OutQuad }
            NumberAnimation { target: nudge; property: "x"; to: 4; duration: 70; easing.type: Easing.InOutQuad }
            NumberAnimation { target: nudge; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
        }
        Row {
            id: pillRow
            x: 12; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Item {
                width: 7; height: 7
                anchors.verticalCenter: parent.verticalCenter
                RectangularShadow { anchors.fill: dot; radius: dot.radius; blur: 10; color: Theme.rgba(Theme.t.color.accent, 0.9) }
                Rectangle { id: dot; anchors.fill: parent; radius: Theme.square ? 0 : 3.5; color: Theme.accent }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.typed !== "" ? root.typed.toUpperCase() : Theme.labelsMono ? "TYPE A LABEL" : "Type a label"
                color: Theme.label
                font.family: Theme.labelsMono || root.typed !== "" ? Theme.fontLabel : Theme.fontUi
                font.pointSize: (Theme.labelsMono || root.typed !== "" ? 11 : 12.5) * 0.75
                font.weight: Font.Medium
                font.letterSpacing: Theme.labelsMono || root.typed !== "" ? 0.66 : 0
            }
            // element count / scanning / no elements (an app without an accessibility tree)
            Rectangle {
                id: chip
                visible: root.status !== "off"
                anchors.verticalCenter: parent.verticalCenter
                readonly property bool warn: root.status === "none"
                height: 19
                width: chipText.implicitWidth + 12
                radius: Theme.square ? 2 : 9.5
                color: warn ? "transparent" : Theme.white(0.08)
                border.width: 1
                border.color: warn ? Theme.rgba(Theme.t.color.accent, 0.7) : Theme.white(0.1)
                Text {
                    id: chipText
                    anchors.centerIn: parent
                    text: root.status === "scanning" ? "SCANNING" : chip.warn ? "NO ELEMENTS"
                        : root.elementCount + (root.elementCount === 1 ? " ELEMENT" : " ELEMENTS")
                    color: chip.warn ? Theme.accent : Theme.label2
                    font.family: Theme.fontLabel
                    font.pointSize: 9.5 * 0.75
                    font.weight: Font.Medium
                    font.letterSpacing: 0.95
                }
                SequentialAnimation on opacity {
                    running: root.status === "scanning"
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { from: 1; to: 0.45; duration: 420; easing.type: Easing.InOutSine }
                    NumberAnimation { from: 0.45; to: 1; duration: 420; easing.type: Easing.InOutSine }
                }
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Keycap { visible: root.typed !== ""; text: Theme.labelsMono ? "BKSP" : "bksp" }
                Keycap { text: Theme.labelsMono ? "ESC" : "esc" }
            }
        }
    }
}

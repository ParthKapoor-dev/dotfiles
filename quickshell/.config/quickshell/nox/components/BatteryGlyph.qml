import QtQuick
import qs.core

// mock batteryIcon(): 26x24 viewBox drawn 24px wide: 55% outline body (19x10, r3), nub, solid fill
// (13 * level wide), black bolt while charging; red fill when low.
Item {
    id: b
    property real level: 1          // 0..1
    property bool charging: false
    property bool low: false
    property color color: Theme.label
    readonly property real k: 24 / 26
    implicitWidth: 24; implicitHeight: 24 * k

    Rectangle {
        id: body
        x: 2 * b.k; y: 7 * b.k; width: 19 * b.k; height: 10 * b.k
        radius: 3 * b.k
        color: "transparent"
        border.width: 1.5 * b.k; border.color: Qt.rgba(b.color.r, b.color.g, b.color.b, 0.55)
    }
    Rectangle {
        x: 4 * b.k; y: 9 * b.k; height: 6 * b.k; radius: 1.4 * b.k
        width: Math.max(1.5, 13 * Math.max(0, Math.min(1, b.level))) * b.k
        color: b.low ? Theme.red : b.color
    }
    Rectangle {
        x: 22.25 * b.k; y: 10.5 * b.k; width: 1.5 * b.k; height: 3 * b.k; radius: 0.75 * b.k
        color: Qt.rgba(b.color.r, b.color.g, b.color.b, 0.55)
    }
    Glyph {
        visible: b.charging
        x: 12.5 * b.k - width / 2; y: 12 * b.k - height / 2
        name: "bolt"; size: 9.5
        color: "black"
        strokeWidth: 2.6
    }
}

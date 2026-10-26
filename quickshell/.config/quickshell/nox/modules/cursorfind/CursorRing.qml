pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.core

// The find-the-cursor ring: an accent ring with a soft glow centred on (cx, cy) that grows from
// a third of `diameter` to all of it and fades in the second half of `duration` (ease-out, so it
// reads as a bloom, not a pulse). A thinner echo ring trails it by a beat. start() replays it.
Item {
    id: root
    property real cx: 0
    property real cy: 0
    property real diameter: 220
    property int duration: 600
    property color tint: Theme.accent
    property real t: 0                  // 0 -> 1 over `duration`
    property bool glow: true            // the soft accent glow (MultiEffect shadow)
    function start() { anim.restart(); }

    // padding for the glow, so the layer isn't clipped at the ring's widest
    readonly property real pad: 40
    x: cx - width / 2
    y: cy - height / 2
    width: diameter + pad * 2
    height: width

    NumberAnimation on t { id: anim; from: 0; to: 1; duration: root.duration; running: false }

    // grows fast and settles (out-cubic), fades over the last 55 %
    function grow(p) { return 1 - Math.pow(1 - Math.min(1, Math.max(0, p)), 3); }
    function fade(p) { return p < 0.45 ? 1 : Math.max(0, 1 - (p - 0.45) / 0.55); }

    Item {
        id: rings
        anchors.fill: parent
        layer.enabled: root.glow
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: root.tint
            shadowBlur: 1
            shadowScale: 1.04
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
            blurMax: 32
        }
        // main ring
        Rectangle {
            readonly property real k: 0.34 + 0.66 * root.grow(root.t)
            anchors.centerIn: parent
            width: root.diameter * k; height: width
            radius: width / 2
            color: Theme.rgba(root.tint, 0.08 * root.fade(root.t))
            border.width: 7 - 3.5 * root.grow(root.t)
            border.color: root.tint
            opacity: root.fade(root.t)
            antialiasing: true
        }
        // echo, a beat behind and fainter
        Rectangle {
            readonly property real p: (root.t - 0.18) / 0.82
            readonly property real k: 0.3 + 0.55 * root.grow(p)
            visible: p > 0
            anchors.centerIn: parent
            width: root.diameter * k; height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: root.tint
            opacity: 0.55 * root.fade(p)
            antialiasing: true
        }
    }
}

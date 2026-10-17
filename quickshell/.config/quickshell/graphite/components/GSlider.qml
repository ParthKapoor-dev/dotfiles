import QtQuick
import qs.core

// Pill slider (mock .sld): white fill, dark glyph on the left. value 0..1; moved(v) while dragging/scrolling.
// tokens ui.meter = "dot-matrix": glyph + two rows of cells (accent = filled) + mono percentage.
Item {
    id: root
    property real value: 0
    property string icon: ""
    property real step: 0.05
    signal moved(real v)
    implicitHeight: 28
    implicitWidth: 200

    Rectangle {
        visible: !Theme.dotMatrix
        anchors.fill: parent
        radius: height / 2
        color: Theme.fill2
        clip: true
        Rectangle {
            height: parent.height
            radius: height / 2
            width: Math.max(parent.height, parent.width * Math.max(0, Math.min(1, root.value)))
            color: Theme.white(0.92)
        }
    }
    GIcon {
        visible: !Theme.dotMatrix
        x: 6; anchors.verticalCenter: parent.verticalCenter
        name: root.icon; size: 16; filled: true
        color: Qt.rgba(0, 0, 0, 0.62)
    }
    // dot-matrix variant
    Item {
        visible: Theme.dotMatrix
        anchors.fill: parent
        GIcon { id: dGlyph; x: 2; anchors.verticalCenter: parent.verticalCenter; name: root.icon; size: 16; color: Theme.label2 }
        DotMeter {
            anchors.left: dGlyph.right; anchors.leftMargin: 8
            anchors.right: dPct.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            rows: 2; cell: 4; gap: 2
            value: root.value
        }
        GText {
            id: dPct
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            width: 26; horizontalAlignment: Text.AlignRight
            text: Math.round(root.value * 100)
            font.family: Theme.fontMono; small: true; secondary: true
        }
    }
    MouseArea {
        anchors.fill: parent
        function at(x) { return Math.max(0, Math.min(1, x / width)); }
        onPressed: m => root.moved(at(m.x))
        onPositionChanged: m => { if (pressed) root.moved(at(m.x)); }
        onWheel: w => root.moved(Math.max(0, Math.min(1, root.value + (w.angleDelta.y > 0 ? root.step : -root.step))))
    }
}

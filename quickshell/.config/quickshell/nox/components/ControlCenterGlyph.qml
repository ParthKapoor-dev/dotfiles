import QtQuick
import qs.core

// Mock "cc" glyph: two pill outlines with knobs on opposite sides.
Item {
    id: g
    property real size: 17
    property color color: Theme.label
    implicitWidth: size; implicitHeight: size
    Repeater {
        model: 2
        Rectangle {
            required property int index
            x: g.size * 0.125; y: g.size * (index === 0 ? 0.19 : 0.54)
            width: g.size * 0.75; height: g.size * 0.27; radius: height / 2
            color: "transparent"; border.width: Math.max(1, g.size * 0.08); border.color: g.color
            Rectangle {
                width: parent.height * 0.52; height: width; radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: index === 0 ? parent.width - width - parent.height * 0.24 : parent.height * 0.24
                color: g.color
            }
        }
    }
}

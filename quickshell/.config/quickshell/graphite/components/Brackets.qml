import QtQuick
import qs.core

// Four small accent corner brackets (tokens card.brackets, Telemetry HUD look). 8 rectangles, static.
Item {
    id: root
    property real len: 10
    property real thick: 1
    property real inset: 3
    property color color: Theme.accent
    Repeater {
        model: 4
        Item {
            required property int index
            readonly property bool atRight: index % 2 === 1
            readonly property bool atBottom: index >= 2
            x: atRight ? root.width - root.inset - root.len : root.inset
            y: atBottom ? root.height - root.inset - root.len : root.inset
            width: root.len; height: root.len
            Rectangle { y: parent.atBottom ? parent.height - root.thick : 0; width: parent.width; height: root.thick; color: root.color }
            Rectangle { x: parent.atRight ? parent.width - root.thick : 0; width: root.thick; height: parent.height; color: root.color }
        }
    }
}

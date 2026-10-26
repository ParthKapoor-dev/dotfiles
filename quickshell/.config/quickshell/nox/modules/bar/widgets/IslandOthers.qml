pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components

// The island's other live things (design mock .isl-o): mini glyphs after a hairline at the pill's
// right end; a hot one (needs you, timer rang) is accent with a dot. A click shows that one.
Row {
    id: root
    property var model: []
    readonly property int count: model.length
    signal pick(string kind)
    spacing: 5
    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 1; height: 12; color: Theme.sep }
    Item { width: 2; height: 1 }
    Repeater {
        model: root.model
        Item {
            id: mini
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            width: 12; height: 12
            Glyph {
                anchors.centerIn: parent
                name: mini.modelData.glyph
                size: 11
                color: mini.modelData.hot ? Theme.accent : Theme.label3
            }
            Rectangle {
                visible: mini.modelData.hot
                x: parent.width - 2; y: -2
                width: 4; height: 4
                radius: Theme.square ? 0 : 2
                color: Theme.accent
            }
            // no hover of its own: the island keeps the hover (its hover-to-open)
            MouseArea {
                anchors.fill: parent
                anchors.margins: -3
                onClicked: root.pick(mini.modelData.kind)
            }
        }
    }
}

import QtQuick
import qs.core

// Dot-matrix meter (tokens ui.meter = "dot-matrix"): `rows` rows of square cells across the width;
// cells up to `value` (0..1) use `fillColor` (accent), the rest a dim fill. Cell count follows width.
Item {
    id: root
    property real value: 0
    property int rows: 2
    property real cell: 3
    property real gap: 2
    property color fillColor: Theme.accent
    property color emptyColor: Theme.fill3
    readonly property int cols: Math.max(1, Math.floor((width + gap) / (cell + gap)))
    readonly property int lit: Math.round(Math.max(0, Math.min(1, value)) * cols)
    implicitHeight: rows * cell + (rows - 1) * gap

    Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.gap
        Repeater {
            model: root.rows
            Row {
                spacing: root.gap
                Repeater {
                    model: root.cols
                    Rectangle {
                        required property int index
                        width: root.cell; height: root.cell
                        radius: root.cell >= 4 ? 1 : 0
                        color: index < root.lit ? root.fillColor : root.emptyColor
                    }
                }
            }
        }
    }
}

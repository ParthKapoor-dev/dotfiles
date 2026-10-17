import QtQuick
import QtQuick.Shapes
import qs.core
import qs.components

// mock .ring: 52px conic gauge (green), 44px inner disc with a glyph. value 0..1
Item {
    id: root
    property real value: 0
    property string glyph: "laptop"
    property color color: value <= 0.2 ? Theme.red : Theme.green
    width: 52; height: 52
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: Theme.white(0.12); strokeWidth: 4; fillColor: "transparent"
            PathAngleArc { centerX: 26; centerY: 26; radiusX: 24; radiusY: 24; startAngle: 0; sweepAngle: 360 }
        }
        ShapePath {
            strokeColor: root.color; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.FlatCap
            PathAngleArc { centerX: 26; centerY: 26; radiusX: 24; radiusY: 24; startAngle: -90; sweepAngle: 360 * Math.max(0, Math.min(1, root.value)) }
        }
    }
    Glyph { anchors.centerIn: parent; name: root.glyph; size: 18 }
}

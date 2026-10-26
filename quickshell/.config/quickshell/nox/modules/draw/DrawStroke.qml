import QtQuick
import QtQuick.Shapes

// One drawing stroke (modules/draw): PathMultiline paths, optional glow = two soft wide passes
// under the ink (pointer ink).
Shape {
    id: sh
    property var paths: []
    property color color: "white"
    property real lineWidth: 4
    property real alpha: 1
    property bool glow: false
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeColor: sh.glow ? Qt.alpha(sh.color, 0.14) : "transparent"
        strokeWidth: sh.lineWidth * 4.2
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
        PathMultiline { paths: sh.glow ? sh.paths : [] }
    }
    ShapePath {
        strokeColor: sh.glow ? Qt.alpha(sh.color, 0.3) : "transparent"
        strokeWidth: sh.lineWidth * 2.2
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
        PathMultiline { paths: sh.glow ? sh.paths : [] }
    }
    ShapePath {
        strokeColor: Qt.alpha(sh.color, sh.alpha)
        strokeWidth: sh.lineWidth
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap; joinStyle: ShapePath.RoundJoin
        PathMultiline { paths: sh.paths }
    }
}

import QtQuick
import QtQuick.Shapes

// The notch body: true black, hanging from the top edge, with concave shoulders where it meets
// the edge (radius `shoulder`) and convex bottom corners (radius `r`). x = 0 is the left
// shoulder's outer edge; the body itself spans shoulder .. shoulder + bodyWidth.
Shape {
    id: sh
    property real bodyWidth: 120
    property real bodyHeight: 8
    property real r: 8
    property real shoulder: 14
    property color fill: "#000000"
    readonly property real rr: Math.max(0, Math.min(r, bodyHeight / 2, bodyWidth / 2))
    readonly property real sr: Math.max(0, Math.min(shoulder, bodyHeight - rr))
    width: bodyWidth + shoulder * 2
    height: bodyHeight
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
        strokeWidth: -1
        fillColor: sh.fill
        startX: sh.shoulder - sh.sr; startY: 0
        // left shoulder (concave): from the top edge down into the body's left side
        PathArc { x: sh.shoulder; y: sh.sr; radiusX: sh.sr; radiusY: sh.sr; direction: PathArc.Clockwise }
        PathLine { x: sh.shoulder; y: sh.bodyHeight - sh.rr }
        PathArc { x: sh.shoulder + sh.rr; y: sh.bodyHeight; radiusX: sh.rr; radiusY: sh.rr; direction: PathArc.Counterclockwise }
        PathLine { x: sh.shoulder + sh.bodyWidth - sh.rr; y: sh.bodyHeight }
        PathArc { x: sh.shoulder + sh.bodyWidth; y: sh.bodyHeight - sh.rr; radiusX: sh.rr; radiusY: sh.rr; direction: PathArc.Counterclockwise }
        PathLine { x: sh.shoulder + sh.bodyWidth; y: sh.sr }
        // right shoulder (concave)
        PathArc { x: sh.shoulder + sh.bodyWidth + sh.sr; y: 0; radiusX: sh.sr; radiusY: sh.sr; direction: PathArc.Clockwise }
        PathLine { x: sh.shoulder - sh.sr; y: 0 }
    }
}

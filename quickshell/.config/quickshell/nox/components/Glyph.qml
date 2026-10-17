pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.core
import "glyphs.js" as G

// Monochrome glyph from the design mock's own icon set (components/glyphs.js, 24x24 strokes,
// 1.7 wide, round caps), drawn with the curve renderer so it stays crisp at any scale.
// Unknown names fall back to the icon font (`fallback`, a Material Symbols name, or `name` itself).
Item {
    id: root
    property string name
    property real size: Theme.iconSize
    property color color: Theme.label
    property real strokeWidth: 1.7          // in viewBox units (24)
    property string fallback: ""
    property bool filled: false             // fallback font only
    readonly property var parts: G.glyphs[name] ?? null
    implicitWidth: size
    implicitHeight: size

    Item {
        visible: root.parts !== null
        width: 24; height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        Repeater {
            model: root.parts ?? []
            Shape {
                id: sh
                required property var modelData
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                opacity: modelData.o ?? 1
                readonly property bool stroked: (modelData.s ?? 1) !== 0
                ShapePath {
                    strokeColor: sh.stroked ? root.color : "transparent"
                    strokeWidth: sh.stroked ? (sh.modelData.w ?? root.strokeWidth) : -1
                    fillColor: sh.modelData.f ? root.color : "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    strokeStyle: sh.modelData.dash ? ShapePath.DashLine : ShapePath.SolidLine
                    dashPattern: [1.5, 1.4]
                    PathSvg { path: sh.modelData.d }
                }
            }
        }
    }
    GIcon {
        visible: root.parts === null && text !== ""
        anchors.centerIn: parent
        name: root.fallback || root.name
        size: root.size
        color: root.color
        filled: root.filled
    }
}

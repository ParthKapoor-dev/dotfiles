pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.core
import qs.components

// Mission Control glyphs missing from components/glyphs.js (mock P.branch / alert / reply), same
// 24x24 stroke style; any other name goes to the shared Glyph.
Item {
    id: root
    property string name
    property real size: 12
    property color color: Theme.label
    readonly property var own: ({
        branch: ["M5 5.5a2 2 0 1 0 4 0a2 2 0 1 0 -4 0z", "M5 18.5a2 2 0 1 0 4 0a2 2 0 1 0 -4 0z",
                 "M15 7.5a2 2 0 1 0 4 0a2 2 0 1 0 -4 0z", "M7 7.5v9M17 9.5c0 4.5-10 2.5-10 7"],
        alert: ["M12 4l9 15.5H3z", "M12 10v4M12 17h.01"],
        reply: ["M10 8.5 5 13l5 4.5", "M5 13h9a5 5 0 0 1 5 5v.5"]
    })
    implicitWidth: size
    implicitHeight: size

    Item {
        visible: root.own[root.name] !== undefined
        width: 24; height: 24
        scale: root.size / 24
        transformOrigin: Item.TopLeft
        Repeater {
            model: root.own[root.name] ?? []
            Shape {
                id: sh
                required property string modelData
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: root.color
                    strokeWidth: 1.9
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: sh.modelData }
                }
            }
        }
    }
    Glyph {
        visible: root.own[root.name] === undefined
        name: root.name
        size: root.size
        color: root.color
    }
}

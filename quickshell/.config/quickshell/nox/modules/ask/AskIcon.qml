pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.core
import qs.components

// Glyphs for Circle to Ask: the mock's extra set (23a: lasso, copy, translate, table, the filled
// Claude burst) drawn here, everything else from the shared Glyph set (components/glyphs.js).
Item {
    id: root
    property string name
    property real size: 13
    property color color: Theme.label
    readonly property var extra: ({
        lasso: [{ d: "M12 4.5c4.7 0 8 2.3 8 5.3S16.7 15 12 15s-8-2.3-8-5.2 3.3-5.3 8-5.3z" }, { d: "M7.5 14c-.7 1.8.2 3.2 1.8 3.4 1.4.2 1.7 1.3 1 3.1" }],
        copy: [{ d: "M10.5 8.5h7a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-7a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2z" }, { d: "M15.5 8.5V6a1.5 1.5 0 0 0-1.5-1.5H6A1.5 1.5 0 0 0 4.5 6v8A1.5 1.5 0 0 0 6 15.5h2.5" }],
        translate: [{ d: "M4 6h9M8.5 4v2M6 6c.5 3 2.5 5.5 5.5 7M11 6c-.6 3.4-3 6.4-6.5 8" }, { d: "M12.5 20l4-9 4 9M14 17h5" }],
        table: [{ d: "M5.5 5h13a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z" }, { d: "M3.5 10h17M3.5 14.5h17M9.5 10v9" }],
        spark: [{ f: 1, d: "M12 2.5l1.6 6.2 5.6-3.3-3.3 5.6 6.2 1.6-6.2 1.6 3.3 5.6-5.6-3.3L12 23.1l-1.6-6.6-5.6 3.3 3.3-5.6L1.9 12.6l6.2-1.6-3.3-5.6 5.6 3.3z" }]
    })
    readonly property var parts: extra[name] ?? null
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
                ShapePath {
                    strokeColor: sh.modelData.f ? "transparent" : root.color
                    strokeWidth: sh.modelData.f ? -1 : 1.7
                    fillColor: sh.modelData.f ? root.color : "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: sh.modelData.d }
                }
            }
        }
    }
    Glyph {
        visible: root.parts === null
        anchors.centerIn: parent
        name: root.name
        size: root.size
        color: root.color
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.core
import qs.components

// The shelf's own glyphs (mock 23g: shelf tray, fan chevron, clock), drawn like components/Glyph
// (24x24 strokes, 1.7 wide, round caps). Any other name goes to Glyph.
Item {
    id: root
    property string name
    property real size: 14
    property color color: Theme.label
    readonly property var own: ({
        shelf: ["M4 14h4.5l1.2 2.2h4.6l1.2-2.2H20v4.5a1.5 1.5 0 0 1-1.5 1.5h-13A1.5 1.5 0 0 1 4 18.5z", "M12 3.5v8.5M8.5 9l3.5 3.5L15.5 9"],
        fan: ["M6 9.5l6 6 6-6"],
        clock: ["M3.5 12a8.5 8.5 0 1 0 17 0a8.5 8.5 0 1 0 -17 0z", "M12 7.5V12l3 2"]
    })
    readonly property var parts: own[name] ?? null
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
                required property string modelData
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: root.color
                    strokeWidth: 1.7
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: sh.modelData }
                }
            }
        }
    }
    Glyph {
        visible: root.parts === null
        anchors.fill: parent
        name: root.parts === null ? root.name : ""
        size: root.size
        color: root.color
    }
}

import QtQuick
import qs.core

// Control Center module (mock .mod): radius 14 (4 square looks), white 5% fill + 0.5px white 7%
// rim, 10px padding. tokens card.style "hairline" = 3% fill + 1px white 9% (Telemetry).
Rectangle {
    default property alias content: inner.data
    property real pad: 10
    readonly property bool hairline: Theme.cardStyle === "hairline"
    radius: Theme.square ? 4 : 14
    color: hairline ? Theme.white(0.03) : Theme.white(0.05)
    border.width: hairline ? 1 : 0.5
    border.color: hairline ? Theme.white(0.09) : Theme.white(0.07)
    implicitHeight: inner.childrenRect.height + pad * 2
    Item { id: inner; anchors.fill: parent; anchors.margins: parent.pad }
}

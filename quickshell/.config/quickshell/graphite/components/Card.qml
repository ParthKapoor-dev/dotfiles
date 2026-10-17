import QtQuick
import qs.core

// Rounded inner card (mock Control Center .mod). tokens card.style: "flat" = soft fill + separator
// rim; "hairline" = no fill, 1px hair border (Telemetry).
Rectangle {
    default property alias content: inner.data
    property real pad: 10
    readonly property bool hairline: Theme.cardStyle === "hairline"
    radius: Theme.radiusPanel - 2
    color: hairline ? "transparent" : Theme.fill
    border.width: hairline ? 1 : Theme.rimWidth
    border.color: hairline ? Theme.hair : Theme.sep
    implicitHeight: inner.childrenRect.height + pad * 2
    Item { id: inner; anchors.fill: parent; anchors.margins: parent.pad }
}

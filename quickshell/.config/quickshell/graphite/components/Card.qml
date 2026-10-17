import QtQuick
import qs.core

// Rounded inner card (mock Control Center .mod)
Rectangle {
    default property alias content: inner.data
    property real pad: 10
    radius: 14
    color: Theme.fill
    border.width: Theme.rimWidth
    border.color: Theme.sep
    implicitHeight: inner.childrenRect.height + pad * 2
    Item { id: inner; anchors.fill: parent; anchors.margins: parent.pad }
}

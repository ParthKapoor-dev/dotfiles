pragma ComponentBehavior: Bound
import QtQuick
import qs.core

// A row of bar widgets loaded by id from the registry.
Row {
    id: root
    property var ids: []
    spacing: 1
    Repeater {
        model: root.ids
        Loader {
            required property string modelData
            anchors.verticalCenter: parent?.verticalCenter
            // A Loader keeps its item's implicit size even when the item hides itself
            // (battery absent, no BT adapter, DND off, not recording, empty tray), which left
            // ~30px holes in the bar. Collapse the slot instead. (Binding the Loader's own
            // `visible` to item.visible would latch: a child of a hidden parent reads false.)
            width: item && item.visible ? item.implicitWidth : 0
            height: item ? item.implicitHeight : 0
            source: BarWidgets.url(modelData)
            asynchronous: false
            onLoaded: if (item.hasOwnProperty("widgetId")) item.widgetId = modelData
        }
    }
}

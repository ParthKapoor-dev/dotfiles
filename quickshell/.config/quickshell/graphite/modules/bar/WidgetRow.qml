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
            source: BarWidgets.url(modelData)
            asynchronous: false
            onLoaded: if (item.hasOwnProperty("widgetId")) item.widgetId = modelData
        }
    }
}

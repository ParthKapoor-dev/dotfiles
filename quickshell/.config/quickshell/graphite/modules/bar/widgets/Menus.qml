pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components

// The File / Edit / View / Window / Help titles (widgets.menus.items picks which, in order).
Row {
    id: root
    property string widgetId: "menus"
    readonly property var options: Config.widget(widgetId)
    spacing: 1
    Repeater {
        model: root.options.items ?? ["File", "Edit", "View", "Window", "Help"]
        AppMenuButton {
            required property string modelData
            menu: modelData
            label: modelData
        }
    }
}

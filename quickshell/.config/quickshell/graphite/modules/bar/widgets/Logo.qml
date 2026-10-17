pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// System menu (mock logo menu). Entries: shell.json widgets.logo.menu, each
// { "label", "action": "<Actions name>" | "command": [argv], "shortcut"? } or { "separator": true }.
BarButton {
    id: root
    property string widgetId: "logo"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    onEntered: if (Panels.popup.startsWith("bar:menu:") ) Panels.open(popupId)

    Glyph { name: "logo"; size: 16; anchors.verticalCenter: parent.verticalCenter }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        popupWidth: 224
        content: Column {
            Repeater {
                model: root.options.menu ?? []
                MenuRow {
                    required property var modelData
                    width: parent.width
                    text: (modelData.label ?? "").replace("$USER", Quickshell.env("USER") ?? "")
                    shortcut: modelData.shortcut ?? ""
                    separator: !!modelData.separator
                    header: !!modelData.header
                    onTriggered: { Panels.close(); Actions.runItem(modelData); }
                }
            }
        }
    }
}

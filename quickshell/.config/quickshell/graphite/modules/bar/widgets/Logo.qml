pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components

// System menu button. Menu entries come from shell.json widgets.logo.menu:
// { "label": "...", "command": [argv...] } or { "separator": true }
BarButton {
    id: root
    property string widgetId: "logo"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    hpad: 9
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)

    LogoGlyph { size: 16; anchors.verticalCenter: parent.verticalCenter }

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
                    text: modelData.label ?? ""
                    separator: !!modelData.separator
                    onTriggered: {
                        Panels.close();
                        if (modelData.command) Quickshell.execDetached(modelData.command);
                    }
                }
            }
        }
    }
}

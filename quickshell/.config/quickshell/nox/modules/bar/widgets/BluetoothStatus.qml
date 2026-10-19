pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Bluetooth status + popover (mock Pops.bt): power switch, paired devices with two-line status
// (click = connect/disconnect), "Bluetooth Settings…".
BarButton {
    id: root
    property string widgetId: "bluetooth"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    hpad: 7
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    visible: Bt.adapter !== null

    Glyph { name: Bt.glyph; anchors.verticalCenter: parent.verticalCenter }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        align: "itemRight"
        content: Column {
            PopHeader { width: parent.width; title: "Bluetooth"; showSwitch: true; checked: Bt.enabled; onToggled: Bt.setEnabled(!Bt.enabled) }
            SectionLabel { visible: !Bt.enabled; text: "Bluetooth is off"; bottomPadding: 10 }
            SectionLabel { visible: Bt.enabled; text: Bt.paired.length ? "Devices" : "No paired devices"; bottomPadding: Bt.paired.length ? 3 : 10 }
            Repeater {
                model: Bt.enabled ? Bt.paired : []
                ListRow {
                    required property var modelData
                    width: parent.width
                    icon: Bt.glyphFor(modelData)
                    on: modelData.connected
                    title: Bt.nameOf(modelData)
                    subtitle: Bt.status(modelData)
                    subtitleColor: Bt.needsRepair(modelData) ? Theme.accent : Theme.label2
                    onClicked: { if (Bt.needsRepair(modelData)) Panels.close(); Bt.activate(modelData); }
                }
            }
            MenuSep { width: parent.width; visible: settings.visible }
            MenuRow {
                id: settings
                visible: (root.options.settingsCommand ?? []).length > 0
                width: parent.width
                text: "Bluetooth Settings…"
                onTriggered: { Panels.close(); Quickshell.execDetached(root.options.settingsCommand); }
            }
        }
    }
}

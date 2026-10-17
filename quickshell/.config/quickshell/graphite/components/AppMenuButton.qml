pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.modules.bar

// One menu-bar title (app name or File/Edit/…) with its dropdown. Like macOS, once a bar menu is
// open, hovering another title switches to it.
BarButton {
    id: root
    property string menu: "app"
    property string label: menu
    property bool bold: false
    readonly property string popupId: "bar:menu:" + menu
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    onEntered: if (Panels.popup.startsWith("bar:menu:") || Panels.popup === "bar:logo") Panels.open(popupId)

    GText {
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.weight: root.bold ? Font.Bold : Font.Normal
        // Telemetry: app name in mono caps with an accent square (mock .mbi.app::before)
        font.family: root.bold && Theme.labelsMono && Theme.square ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: root.bold && Theme.labelsMono && Theme.square ? 12 : Theme.fontSize
        font.capitalization: root.bold && Theme.labelsMono && Theme.square ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: root.bold && Theme.labelsMono && Theme.square ? 0.84 : 0
        leftPadding: root.bold && Theme.labelsMono && Theme.square ? 12 : 0
        Rectangle {
            visible: parent.leftPadding > 0
            width: 6; height: 6; color: Theme.accent
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    FontMetrics { id: fm; font.family: Theme.fontUi; font.pixelSize: Theme.fontSize }
    GPopup {
        popupId: root.popupId
        anchorItem: root
        popupWidth: {
            if (Panels.popup !== root.popupId) return 224;
            let m = 0;
            for (const it of AppMenus.items(root.menu))
                if (it.label) m = Math.max(m, fm.advanceWidth(it.label) + (it.shortcut ? fm.advanceWidth(it.shortcut) + 28 : 0));
            return Math.min(420, Math.max(224, m + 32 + 12));
        }
        content: Column {
            Repeater {
                model: Panels.popup === root.popupId ? AppMenus.items(root.menu) : []
                MenuRow {
                    required property var modelData
                    width: parent.width
                    text: modelData.label ?? modelData.head ?? ""
                    shortcut: modelData.shortcut ?? ""
                    separator: !!modelData.sep
                    header: modelData.head !== undefined
                    checked: !!modelData.check
                    enabled: !modelData.dis
                    danger: !!modelData.danger
                    onTriggered: { Panels.close(); modelData.act?.(); }
                }
            }
        }
    }
}

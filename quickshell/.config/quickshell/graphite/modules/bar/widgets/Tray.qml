pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.core
import qs.components

// StatusNotifier tray. Left click = activate (or menu if the item is menu-only),
// right click = menu rendered by graphite (glass, keyboard-less, submenus drill down).
// widgets.tray.monochrome desaturates icons to match the monochrome bar.
Row {
    id: root
    property string widgetId: "tray"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    property var menuItem: null          // SystemTrayItem whose menu is open
    property Item menuAnchor: null
    property var menuStack: []           // QsMenuHandle stack for submenus
    spacing: 1

    function openMenu(item, anchor) {
        menuItem = item; menuAnchor = anchor; menuStack = [item.menu];
        popup.anchorItem = anchor;
        Panels.open(popupId);
    }

    Repeater {
        model: SystemTray.items
        BarButton {
            id: btn
            required property SystemTrayItem modelData
            hpad: 6
            active: Panels.popup === root.popupId && root.menuItem === modelData
            onClicked: b => {
                if (b === Qt.RightButton || (b === Qt.LeftButton && modelData.onlyMenu)) {
                    if (modelData.hasMenu) root.openMenu(modelData, btn);
                } else if (b === Qt.MiddleButton) modelData.secondaryActivate();
                else { Panels.close(); modelData.activate(); }
            }
            onWheel: d => modelData.scroll(d, false)
            Item {
                width: 16; height: 16
                anchors.verticalCenter: parent.verticalCenter
                IconImage {
                    anchors.fill: parent
                    source: btn.modelData.icon
                    layer.enabled: root.options.monochrome ?? true
                    layer.effect: MultiEffect { saturation: -1; brightness: 0.1 }
                }
            }
        }
    }

    GPopup {
        id: popup
        popupId: root.popupId
        popupWidth: 240
        content: Column {
            QsMenuOpener { id: opener; menu: root.menuStack.length ? root.menuStack[root.menuStack.length - 1] : null }
            MenuRow {
                visible: root.menuStack.length > 1
                width: parent.width
                text: "‹ Back"
                onTriggered: root.menuStack = root.menuStack.slice(0, -1)
            }
            Repeater {
                model: opener.children
                MenuRow {
                    required property QsMenuEntry modelData
                    width: parent.width
                    text: modelData.text
                    separator: modelData.isSeparator
                    enabled: modelData.enabled
                    hasChildren: modelData.hasChildren
                    checked: modelData.buttonType !== QsMenuButtonType.None && modelData.checkState === Qt.Checked
                    onTriggered: {
                        if (modelData.hasChildren) { root.menuStack = root.menuStack.concat([modelData]); return; }
                        modelData.triggered();
                        Panels.close();
                    }
                }
            }
        }
    }
}

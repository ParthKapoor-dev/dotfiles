pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import qs.core
import qs.components

// StatusNotifier tray. widgets.tray.mode:
//  "popup" (default, mock Pops.tray): one glyph in the bar; its popover lists the background apps
//          (icon + name + status). Click = activate, right click / menu-only items = the app's
//          menu in the same popover (submenus drill down with a Back row).
//  "inline": every item as a monochrome icon in the bar (click = activate, right click = menu).
Item {
    id: root
    property string widgetId: "tray"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    readonly property bool inline: (options.mode ?? "popup") === "inline"
    property var menuItem: null          // SystemTrayItem whose menu is shown
    property var menuStack: []           // QsMenuHandle stack for submenus
    visible: SystemTray.items.values.length > 0
    implicitWidth: inline ? inlineRow.implicitWidth : btn.implicitWidth
    implicitHeight: btn.implicitHeight

    function openMenu(item, anchor) {
        menuItem = item; menuStack = [item.menu];
        popup.anchorItem = anchor;
        Panels.open(popupId);
    }
    function nameOf(it) { return it.title || it.id || it.tooltipTitle; }

    BarButton {
        id: btn
        visible: !root.inline
        hpad: 7
        active: Panels.popup === root.popupId
        onClicked: { root.menuItem = null; root.menuStack = []; popup.anchorItem = btn; Panels.toggle(root.popupId); }
        Glyph { name: "tray"; anchors.verticalCenter: parent.verticalCenter }
    }
    Row {
        id: inlineRow
        visible: root.inline
        spacing: 1
        Repeater {
            model: root.inline ? SystemTray.items : []
            BarButton {
                id: ib
                required property SystemTrayItem modelData
                hpad: 6
                active: Panels.popup === root.popupId && root.menuItem === modelData
                onClicked: b => {
                    if (b === Qt.RightButton || (b === Qt.LeftButton && modelData.onlyMenu)) { if (modelData.hasMenu) root.openMenu(modelData, ib); }
                    else if (b === Qt.MiddleButton) modelData.secondaryActivate();
                    else { Panels.close(); modelData.activate(); }
                }
                onWheel: d => modelData.scroll(d, false)
                IconImage {
                    width: 16; height: 16
                    anchors.verticalCenter: parent.verticalCenter
                    source: ib.modelData.icon
                    layer.enabled: root.options.monochrome ?? true
                    layer.effect: MultiEffect { saturation: -1; brightness: 0.1 }
                }
            }
        }
    }

    GPopup {
        id: popup
        popupId: root.popupId
        anchorItem: btn
        align: "itemRight"
        popupWidth: root.menuItem ? 250 : 290
        content: Column {
            // ---- app list ----
            PopHeader { visible: root.menuItem === null; width: parent.width; title: "Background apps" }
            Repeater {
                model: root.menuItem === null ? SystemTray.items : []
                Item {
                    id: rowItem
                    required property SystemTrayItem modelData
                    width: parent.width; height: 34
                    Rectangle { anchors.fill: parent; radius: Theme.square ? 3 : 6; color: Theme.fill; opacity: ma.containsMouse ? 1 : 0 }
                    IconImage {
                        x: 10; width: 22; height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        source: rowItem.modelData.icon
                    }
                    GText {
                        x: 44; width: parent.width - 44 - st.implicitWidth - 20
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.nameOf(rowItem.modelData)
                    }
                    GText {
                        id: st
                        anchors.right: parent.right; anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowItem.modelData.status === Status.NeedsAttention ? "attention" : "tray"
                        color: rowItem.modelData.status === Status.NeedsAttention ? Theme.accent : Theme.label2
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: m => {
                            const it = rowItem.modelData;
                            if (m.button === Qt.RightButton || it.onlyMenu) { if (it.hasMenu) { root.menuItem = it; root.menuStack = [it.menu]; } }
                            else if (m.button === Qt.MiddleButton) it.secondaryActivate();
                            else { Panels.close(); it.activate(); }
                        }
                    }
                }
            }
            // ---- an app's menu ----
            QsMenuOpener { id: opener; menu: root.menuStack.length ? root.menuStack[root.menuStack.length - 1] : null }
            MenuRow {
                visible: root.menuItem !== null && !root.inline || root.menuStack.length > 1
                width: parent.width
                text: "‹ " + (root.menuStack.length > 1 ? "Back" : "Background apps")
                onTriggered: { if (root.menuStack.length > 1) root.menuStack = root.menuStack.slice(0, -1); else { root.menuItem = null; root.menuStack = []; } }
            }
            Repeater {
                model: root.menuItem !== null ? opener.children : []
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

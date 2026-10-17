import QtQuick
import qs.core
import qs.components
import qs.modules.bar

// Bold name of the focused app (desktop entry Name, else the app id); its menu has the app-level
// actions (New Window, Hide, Quit, Force Quit). Mock .mbi.app: the menus follow the name directly.
// The slot hugs the name: when the app changes the label crossfades and the button's width eases
// to the new text (sheet curve), so File/Edit/View/… glide instead of jumping. Names longer than
// widgets.appName.maxWidth (default 180 px of text) elide with "…".
Item {
    id: root
    property string widgetId: "appName"
    readonly property var options: Config.widget(widgetId)
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    AppMenuButton {
        id: button
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        menu: "app"
        label: AppMenus.appName
        bold: true
        maxTextWidth: root.options.maxWidth ?? 180
    }
}

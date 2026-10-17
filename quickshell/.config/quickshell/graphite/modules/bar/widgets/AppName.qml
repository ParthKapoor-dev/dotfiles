import QtQuick
import qs.core
import qs.components
import qs.modules.bar

// Bold name of the focused app (desktop entry Name, else the app id); its menu has the app-level
// actions (New Window, Hide, Quit, Force Quit). Mock .mbi.app.
// The name sits in a fixed-width slot (widgets.appName.width, default 148) so File/Edit/View/…,
// the workspaces and the layout glyph never move when the app changes: the button is
// left-aligned in the slot, crossfades its text and eases its width; longer names elide.
Item {
    id: root
    property string widgetId: "appName"
    readonly property var options: Config.widget(widgetId)
    implicitWidth: options.width ?? 148
    implicitHeight: button.implicitHeight
    AppMenuButton {
        id: button
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        menu: "app"
        label: AppMenus.appName
        bold: true
        maxTextWidth: root.implicitWidth - button.hpad * 2 - (button.monoApp ? 12 : 0)
    }
}

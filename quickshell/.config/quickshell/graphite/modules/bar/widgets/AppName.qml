import QtQuick
import qs.core
import qs.components
import qs.modules.bar

// Bold name of the focused app (desktop entry Name, else the app id); its menu has the app-level
// actions (New Window, Hide, Quit, Force Quit). Mock .mbi.app.
AppMenuButton {
    property string widgetId: "appName"
    menu: "app"
    label: AppMenus.appName
    bold: true
}

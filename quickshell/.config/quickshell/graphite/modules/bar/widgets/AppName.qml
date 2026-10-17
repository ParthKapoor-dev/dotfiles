import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.components
import qs.services

// Bold name of the focused app (.desktop Name via DesktopEntries, else the app id).
BarButton {
    id: root
    property string widgetId: "appName"
    readonly property var options: Config.widget(widgetId)
    readonly property var toplevel: ToplevelManager.activeToplevel
    readonly property string appId: toplevel && toplevel.activated ? toplevel.appId : ""
    readonly property string name: {
        Apps.entriesRev;
        if (!appId) return options.fallback ?? "Desktop";
        const e = DesktopEntries.byId(appId) ?? DesktopEntries.heuristicLookup(appId);
        return e?.name || appId;
    }
    hpad: 9

    GText {
        text: root.name
        font.weight: Font.Bold
        anchors.verticalCenter: parent.verticalCenter
    }
}

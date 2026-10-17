pragma Singleton
import QtQuick
import Quickshell

// Bar widget registry: id (used in shell.json bar.left/center/right) -> file in widgets/.
// To add a widget: drop widgets/MyThing.qml (optionally with `property string widgetId`
// and `readonly property var options: Config.widget(widgetId)`), then add one line here.
Singleton {
    readonly property var registry: ({
        "logo": "Logo.qml",
        "appName": "AppName.qml",
        "menus": "Menus.qml",
        "windowTitle": "WindowTitle.qml",
        "workspaces": "Workspaces.qml",
        "layout": "LayoutIndicator.qml",
        "recording": "Recording.qml",
        "dnd": "DndIndicator.qml",
        "tray": "Tray.qml",
        "network": "NetworkStatus.qml",
        "bluetooth": "BluetoothStatus.qml",
        "volume": "Volume.qml",
        "battery": "Battery.qml",
        "search": "Search.qml",
        "controlCenter": "ControlCenterButton.qml",
        "clock": "Clock.qml"
    })
    function url(id) {
        const f = registry[id];
        if (!f) { console.warn("graphite: unknown bar widget id:", id); return ""; }
        return Qt.resolvedUrl("widgets/" + f);
    }
}

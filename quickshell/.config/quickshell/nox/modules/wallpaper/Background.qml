pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.services

// Wallpaper (background layer, namespace nox:wallpaper). One image per screen, decoded at
// screen resolution; changes cross-fade (wallpaper.transition ms). No blur, no effects.
// wallpaper.fill: cover | fit | stretch | center | tile; wallpaper.color fills the rest.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property ShellScreen modelData
        screen: modelData
        WlrLayershell.namespace: "nox:wallpaper"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: Config.opt.wallpaper?.color ?? "#000000"
        mask: Region {}

        readonly property int mode: {
            switch (Wallpaper.fill) {
            case "fit": return Image.PreserveAspectFit;
            case "stretch": return Image.Stretch;
            case "center": return Image.Pad;
            case "tile": return Image.Tile;
            default: return Image.PreserveAspectCrop;
            }
        }
        // the new image fades in over the previous one, which is then released
        property string cur: ""
        property string prev: ""
        Component.onCompleted: cur = Wallpaper.displayUrl
        Connections {
            target: Wallpaper
            function onDisplayUrlChanged() { if (Wallpaper.displayUrl !== win.cur) { win.prev = win.cur; win.cur = Wallpaper.displayUrl; } }
        }
        component Layer: Image {
            anchors.fill: parent
            fillMode: win.mode
            asynchronous: true
            cache: false
            smooth: true
            sourceSize.width: win.screen ? win.screen.width * (win.screen.devicePixelRatio ?? 1) : 0
            sourceSize.height: win.screen ? win.screen.height * (win.screen.devicePixelRatio ?? 1) : 0
        }
        Layer { source: win.prev; visible: win.prev !== "" }
        Layer {
            id: top
            source: win.cur
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Config.opt.wallpaper?.transition ?? 500; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        }
        Timer {
            interval: (Config.opt.wallpaper?.transition ?? 500) + 100
            running: win.prev !== "" && top.status === Image.Ready
            onTriggered: win.prev = ""
        }
    }
}

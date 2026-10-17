pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// OSD (mock #osd: 236x46 glass pill, glyph 19, 6px bar, value) for volume, brightness and mic,
// plus the HUD toast (mock #hud: top centre, accent glyph + text) for Panels.hud().
// Event driven: PipeWire property signals + Brightness (sysfs inotify). No polling. Windows exist
// only while visible. shell.json osd.{position: bottom|top, offset, width, timeout, volume,
// brightness, mic, hideWhilePopupOpen}
Scope {
    id: root
    readonly property var opts: Config.opt.osd ?? ({})

    property string kind: ""          // "volume" | "brightness" | "mic"
    property bool visibleNow: false
    property bool shown: false
    property bool armed: false

    function show(k) {
        if (!armed || opts[k] === false) return;
        if (opts.hideWhilePopupOpen !== false && Panels.popup === "controlCenter") return;
        kind = k;
        visibleNow = true;
        shown = true;
        hideTimer.restart();
    }
    Timer { id: armTimer; interval: 1500; running: true; onTriggered: root.armed = true }
    Timer { id: hideTimer; interval: root.opts.timeout ?? 1300; onTriggered: { root.visibleNow = false; destroyTimer.restart(); } }
    Timer { id: destroyTimer; interval: Theme.durSheet + 50; onTriggered: if (!root.visibleNow) root.shown = false }

    function disarm() { armed = false; armTimer.restart(); }
    Connections { target: Audio; function onSinkChanged() { root.disarm(); } function onSourceChanged() { root.disarm(); } }
    Connections { target: Audio; function onVolumeChanged() { root.show("volume"); } function onMutedChanged() { root.show("volume"); } }
    Connections { target: Audio; function onMicMutedChanged() { root.show("mic"); } }
    Connections { target: Brightness; function onRawChanged() { root.show("brightness"); } }

    readonly property real value: kind === "brightness" ? Brightness.value : kind === "volume" ? (Audio.muted ? 0 : Audio.volume) : 0
    readonly property string glyph: kind === "brightness" ? "sunF" : kind === "mic" ? (Audio.micMuted ? "micOff" : "mic") : Audio.glyph
    readonly property string text: kind === "mic" ? (Audio.micMuted ? "Microphone muted" : "Microphone on") : ""
    readonly property ShellScreen focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    // ---- HUD (mock #hud) ----
    property string hudText: ""
    property string hudGlyph: "check"
    property bool hudVisible: false
    property bool hudShown: false
    Connections {
        target: Panels
        function onHudRequested(text, glyph) { root.hudText = text; root.hudGlyph = glyph; root.hudVisible = true; root.hudShown = true; hudTimer.restart(); }
    }
    Timer { id: hudTimer; interval: 1800; onTriggered: { root.hudVisible = false; hudKill.restart(); } }
    Timer { id: hudKill; interval: Theme.durSheet + 50; onTriggered: if (!root.hudVisible) root.hudShown = false }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win
            screen: root.focusedScreen
            color: "transparent"
            WlrLayershell.namespace: "nox:osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            readonly property string pos: root.opts.position ?? "bottom"
            readonly property real shadowPad: 32
            anchors.bottom: pos === "bottom"
            anchors.top: pos === "top"
            margins.bottom: Math.max(0, (root.opts.offset ?? (Theme.dockSize + 44)) - shadowPad)
            margins.top: Math.max(0, (root.opts.offset ?? 96) - shadowPad)
            implicitWidth: (root.opts.width ?? 236) + shadowPad * 2
            implicitHeight: 46 + shadowPad * 2
            mask: Region {}

            RectangularShadow {
                anchors.fill: pill
                radius: pill.radius
                offset.y: 14; blur: 40; spread: -6
                color: Theme.rgba("#000000", 0.4)
                opacity: pill.opacity
            }
            Glass {
                id: pill
                brackets: false
                x: win.shadowPad
                y: win.shadowPad + (root.visibleNow ? 0 : 6)
                width: win.implicitWidth - win.shadowPad * 2
                height: 46
                radius: Theme.square ? 4 : height / 2
                opacity: root.visibleNow ? 1 : 0
                scale: root.visibleNow ? 1 : 0.98
                Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                Behavior on scale { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                Glyph { id: glyph; x: 16; anchors.verticalCenter: parent.verticalCenter; name: root.glyph; size: 19 }
                Rectangle {
                    visible: root.kind !== "mic" && !Theme.dotMatrix
                    anchors.left: glyph.right; anchors.leftMargin: 12
                    anchors.right: pct.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6; radius: 3
                    color: Theme.white(0.18)
                    Rectangle {
                        height: parent.height; radius: 3
                        width: parent.width * Math.max(0, Math.min(1, root.value))
                        color: "white"
                        Behavior on width { NumberAnimation { duration: 90 } }
                    }
                }
                DotMeter {
                    visible: root.kind !== "mic" && Theme.dotMatrix
                    style: "bars"
                    anchors.left: glyph.right; anchors.leftMargin: 12
                    anchors.right: pct.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 8
                    value: root.value
                }
                GText {
                    id: pct
                    visible: root.kind !== "mic"
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.value * 100)
                    secondary: true
                    font.family: Theme.dotMatrix ? Theme.fontLabel : Theme.fontUi
                    font.pixelSize: 12
                    font.features: ({ "tnum": 1 })
                }
                GText {
                    visible: root.kind === "mic"
                    anchors.left: glyph.right; anchors.leftMargin: 12
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.text
                }
            }
        }
    }

    LazyLoader {
        active: root.hudShown
        PanelWindow {
            id: hud
            screen: root.focusedScreen
            color: "transparent"
            WlrLayershell.namespace: "nox:osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors.top: true
            margins.top: 96 - 32
            implicitWidth: box.width + 64
            implicitHeight: box.height + 64
            mask: Region {}
            RectangularShadow {
                anchors.fill: box; radius: box.radius
                offset.y: 14; blur: 40; spread: -6
                color: Theme.rgba("#000000", 0.4)
                opacity: box.opacity
            }
            Glass {
                id: box
                brackets: false
                x: 32; y: 32 + (root.hudVisible ? 0 : -8)
                width: hudRow.implicitWidth + 28; height: 34
                radius: Theme.square ? 4 : 12
                opacity: root.hudVisible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                Row {
                    id: hudRow
                    anchors.centerIn: parent
                    spacing: 8
                    Glyph { name: root.hudGlyph; size: 16; color: Theme.accent; anchors.verticalCenter: parent.verticalCenter }
                    GText { text: root.hudText; width: Math.min(implicitWidth, 520); anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }
}

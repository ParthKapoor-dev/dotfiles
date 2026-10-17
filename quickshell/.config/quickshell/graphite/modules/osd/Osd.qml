pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.components
import qs.services

// macOS-style HUD for volume, brightness and mic mute (mock #osd: 236x46 glass pill).
// Event driven: reacts to PipeWire property changes of the default sink/source and to the
// Brightness service (sysfs inotify). No polling. The window only exists while visible.
// shell.json osd.{position: bottom|top|center, offset, width, timeout, volume, brightness, mic, hideWhilePopupOpen}
Scope {
    id: root
    readonly property var opts: Config.opt.osd ?? ({})

    property string kind: ""          // "volume" | "brightness" | "mic"
    property bool visibleNow: false
    property bool shown: false        // window alive (stays a fade longer than visibleNow)
    property bool armed: false        // ignore the values that arrive while services start up

    function show(k) {
        if (!armed || opts[k] === false) return;
        if (opts.hideWhilePopupOpen !== false && Panels.popup === "controlCenter") return;
        kind = k;
        visibleNow = true;
        shown = true;
        hideTimer.restart();
    }
    Timer { id: armTimer; interval: 1500; running: true; onTriggered: root.armed = true }
    Timer { id: hideTimer; interval: root.opts.timeout ?? 1500; onTriggered: { root.visibleNow = false; destroyTimer.restart(); } }
    Timer { id: destroyTimer; interval: Theme.durFade + 50; onTriggered: if (!root.visibleNow) root.shown = false }

    // switching the default device changes every value at once: not a user change
    function disarm() { armed = false; armTimer.restart(); }
    Connections { target: Audio; function onSinkChanged() { root.disarm(); } function onSourceChanged() { root.disarm(); } }
    Connections { target: Audio; function onVolumeChanged() { root.show("volume"); } function onMutedChanged() { root.show("volume"); } }
    Connections { target: Audio; function onMicMutedChanged() { root.show("mic"); } }
    Connections { target: Brightness; function onRawChanged() { root.show("brightness"); } }

    readonly property real value: kind === "brightness" ? Brightness.value : kind === "volume" ? (Audio.muted ? 0 : Audio.volume) : 0
    readonly property string icon: kind === "brightness" ? "light_mode" : kind === "mic" ? (Audio.micMuted ? "mic_off" : "mic") : Audio.icon
    readonly property string text: kind === "mic" ? (Audio.micMuted ? "Microphone muted" : "Microphone on") : ""

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win
            // follow the focused monitor
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "graphite:osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            readonly property string pos: root.opts.position ?? "bottom"
            readonly property real shadowPad: 24
            anchors.bottom: pos === "bottom"
            anchors.top: pos === "top"
            margins.bottom: (root.opts.offset ?? 100) - shadowPad
            margins.top: (root.opts.offset ?? 100) - shadowPad
            implicitWidth: (root.opts.width ?? 236) + shadowPad * 2
            implicitHeight: 46 + shadowPad * 2
            mask: Region {}          // never takes input

            RectangularShadow {
                anchors.fill: pill
                radius: pill.radius
                offset.y: 10; blur: 28; spread: -4
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
                radius: Theme.radiusPanel >= 12 ? height / 2 : Theme.radiusControl + 1   // pill, or square-ish looks
                opacity: root.visibleNow ? 1 : 0
                scale: root.visibleNow ? 1 : 0.98
                Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                GIcon {
                    id: glyph
                    x: 16; anchors.verticalCenter: parent.verticalCenter
                    name: root.icon; size: 19; filled: true
                }
                // dot-matrix meter (tokens ui.meter)
                DotMeter {
                    visible: root.kind !== "mic" && Theme.dotMatrix
                    anchors.left: glyph.right; anchors.leftMargin: 12
                    anchors.right: pct.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    rows: 2; cell: 4; gap: 2
                    value: root.value
                }
                // bar + value (volume, brightness)
                Rectangle {
                    visible: root.kind !== "mic" && !Theme.dotMatrix
                    anchors.left: glyph.right; anchors.leftMargin: 12
                    anchors.right: pct.left; anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 6; radius: 3
                    color: Theme.fill3
                    Rectangle {
                        height: parent.height; radius: 3
                        width: parent.width * Math.max(0, Math.min(1, root.value))
                        color: Theme.white(1)
                        Behavior on width { NumberAnimation { duration: 90 } }
                    }
                }
                GText {
                    id: pct
                    visible: root.kind !== "mic"
                    anchors.right: parent.right; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(root.value * 100)
                    secondary: !Theme.dotMatrix
                    font.family: Theme.fontNumeric
                    font.pixelSize: Theme.dotMatrix ? Theme.fontSize + 2 : Theme.fontSizeSmall + 1
                    font.weight: Theme.numericWeight
                    font.variableAxes: Theme.numericAxes
                    font.features: ({ "tnum": 1 })
                }
                // label (mic)
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
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services

// Voice typing (mock C2): the pill at the bottom centre while recording / transcribing, plus the
// controls. Logic in services/Voice; `nox voice` is the CLI.
//   hold Super+Shift+Space        GlobalShortcut nox:voiceHold (press = record, release = stop);
//                                 nox:voiceRelease = any Space release (keys let go out of order)
//   qs -c nox ipc call voice start | stop | toggle | cancel | status | copyLast | tidy | setTidy <bool> | toggleTidy
// The window exists only while the pill is up; it never takes keyboard focus (the field being
// dictated into keeps it). Only the pill itself takes clicks (the TIDY chip).
Scope {
    id: root
    readonly property var opts: Config.opt.voice ?? ({})
    readonly property bool up: Voice.phase !== "idle"
    property bool shown: false
    onUpChanged: if (up) { killTimer.stop(); shown = true; } else killTimer.restart()
    Timer { id: killTimer; interval: Theme.durSheet + 60; onTriggered: if (!root.up) root.shown = false }

    IpcHandler {
        target: "voice"
        function start(): void { Voice.start("toggle"); }
        function stop(): void { Voice.stop(); }
        function toggle(): void { Voice.toggle(); }
        function cancel(): void { Voice.cancel(); }
        function status(): string { return Voice.status(); }
        function copyLast(): void { Voice.copyLast(); }
        function tidy(): bool { return Voice.tidy; }
        function setTidy(on: bool): void { Voice.setTidy(on); }
        function toggleTidy(): bool { Voice.setTidy(!Voice.tidy); return !Voice.tidy; }
    }

    LazyLoader {
        active: !Quickshell.env("NOX_LINT")
        component: Scope {
            GlobalShortcut {
                appid: "nox"; name: "voiceHold"; description: "Voice typing: hold to talk"
                onPressed: Voice.press()
                onReleased: Voice.release()
            }
            // bound as a release bind on Space (any mods, non-consuming): stops a hold even when
            // Super / Shift came up before Space. Delivered as press and/or release by version.
            GlobalShortcut {
                appid: "nox"; name: "voiceRelease"; description: "Internal: voice typing, Space released"
                onPressed: Voice.release()
                onReleased: Voice.release()
            }
        }
    }

    readonly property ShellScreen focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    LazyLoader {
        active: root.shown
        PanelWindow {
            id: win
            screen: root.focusedScreen
            color: "transparent"
            WlrLayershell.namespace: "nox:voice"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            readonly property real pad: 40
            anchors.bottom: true
            margins.bottom: Math.max(0, (root.opts.offset ?? 96) - pad)
            implicitWidth: 560 + pad * 2
            implicitHeight: 46 + pad * 2
            mask: Region { item: pill }

            RectangularShadow {
                anchors.fill: pill
                radius: pill.cornerRadius
                offset.y: 18; blur: 50; spread: -4
                color: Theme.rgba(Theme.t.shadow.focused.color, 0.7)
                opacity: pill.opacity
                scale: pill.scale
            }
            VoicePill {
                id: pill
                readonly property bool on: Voice.phase !== "idle"
                x: Math.round((win.width - width) / 2)
                y: win.pad + (on ? 0 : 12)
                width: implicitWidth
                Behavior on width { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.94
                Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                Behavior on scale { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

                // keep the last real phase on screen while fading out
                property string shownPhase: "rec"
                Connections { target: Voice; function onPhaseChanged() { if (Voice.phase !== "idle") pill.shownPhase = Voice.phase; } }
                Component.onCompleted: if (Voice.phase !== "idle") shownPhase = Voice.phase
                phase: shownPhase
                hist: Voice.hist
                elapsed: Voice.elapsed
                tidy: Voice.tidy
                sourceLabel: Voice.sourceLabel
                words: Voice.words
                removed: Voice.removed
                seconds: Voice.recSeconds
                backend: Voice.backend
                message: Voice.message
                detail: Voice.detail
                smartFailed: Voice.smartFailed
                tidyModel: root.opts.smartTidyModel ?? "haiku"
                onTidyClicked: Voice.setTidy(!Voice.tidy)
            }
        }
    }
}

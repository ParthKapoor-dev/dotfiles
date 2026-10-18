pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.core
import qs.services

// Desktop widgets (bottom layer, namespace nox:widgets): a quiet column on the empty side of the
// wallpaper: date, big clock in the look's numeric font (Doto on Telemetry, like the lock screen),
// now playing (MPRIS) and a line from desktopWidgets.quotes (one per day). Shown only while this
// screen's workspace has no windows; fades out when one maps, back in when it is empty again.
// No input region, no keyboard focus, ignores reserved space (keeps clear of bar + dock itself).
// Options: shell.json desktopWidgets (services/DesktopWidgets.qml); no weather (no source in the shell).
Variants {
    model: Config.screensFor(DesktopWidgets.opt.screens)

    PanelWindow {
        id: win
        required property ShellScreen modelData
        screen: modelData

        readonly property var opt: DesktopWidgets.opt
        readonly property bool right: DesktopWidgets.resolvedSide === "right"
        readonly property real marginX: opt.marginX ?? 96
        readonly property real colW: opt.width ?? 440
        // this screen's workspace; settled a beat like the dock (windows closing while the next
        // maps, workspace events arriving in pieces) so the column doesn't flicker
        readonly property var monWs: Hyprland.monitorFor(win.screen)?.activeWorkspace ?? null
        readonly property bool wsEmpty: !!monWs && monWs.toplevels.values.length === 0 && !monWs.hasFullscreen
        property bool emptyDesktop: false
        onWsEmptyChanged: emptyTimer.restart()
        Component.onCompleted: emptyDesktop = wsEmpty
        Timer { id: emptyTimer; interval: 120; onTriggered: win.emptyDesktop = win.wsEmpty }
        // auto side: wait for the wallpaper probe instead of jumping sides
        readonly property bool shown: DesktopWidgets.sideKnown && (emptyDesktop || (opt.alwaysShow ?? false))

        WlrLayershell.namespace: "nox:widgets"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: !right; right: right }
        implicitWidth: marginX + colW + 16
        color: "transparent"
        mask: Region {}
        // unmapped once faded out (nothing to draw or tick while windows cover the desktop)
        visible: shown || stage.opacity > 0

        // minutes unless the time format shows seconds
        readonly property string timeFormat: opt.timeFormat ?? "HH:mm"
        SystemClock {
            id: clock
            enabled: win.visible
            precision: /s/.test(win.timeFormat.replace(/'[^']*'/g, "")) ? SystemClock.Seconds : SystemClock.Minutes
        }

        readonly property bool mono: Theme.labelsMono          // Telemetry: mono, upper-case, tracked
        function caps(s) { return mono ? String(s).toUpperCase() : String(s); }
        readonly property var show: opt.show ?? ["date", "clock", "media", "quote"]

        Item {
            id: stage
            anchors.fill: parent
            // keep clear of the bar and the dock shelf (shown on an empty desktop even with autohide)
            anchors.topMargin: Theme.barHeight
            anchors.bottomMargin: Theme.dockSize + 18
            opacity: win.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durWindow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

            Column {
                id: col
                width: win.colW
                x: win.right ? parent.width - win.marginX - width : win.marginX
                y: Math.max(0, Math.min(parent.height - height, (parent.height - height) / 2 + (win.opt.offsetY ?? -24)))
                spacing: 0
                transform: Translate {
                    y: win.shown ? 0 : 10
                    Behavior on y { NumberAnimation { duration: Theme.durWindow; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                }

                Repeater {
                    model: win.show
                    Loader {
                        required property string modelData
                        width: col.width
                        sourceComponent: ({ date: date, clock: clockC, media: media, quote: quote })[modelData] ?? null
                    }
                }
            }
        }

        readonly property int align: right ? Text.AlignRight : Text.AlignLeft

        Component {
            id: date
            Text {
                text: win.caps(Qt.formatDate(clock.date, win.opt.dateFormat ?? "dddd d MMMM"))
                horizontalAlignment: win.align
                color: Theme.white(0.62)
                font.family: win.mono ? Theme.fontLabel : Theme.fontDisplay
                font.pixelSize: win.mono ? 12.5 : 17
                font.weight: Font.Medium
                font.letterSpacing: win.mono ? 3.4 : 0.2
                leftPadding: win.right ? 0 : 4; rightPadding: win.right ? 4 : 0   // optical: line up with the clock's first stem
            }
        }
        Component {
            id: clockC
            Text {
                text: Qt.formatTime(clock.date, win.timeFormat)
                horizontalAlignment: win.align
                color: Theme.label
                font.family: Theme.fontNumeric
                font.pixelSize: win.opt.clockSize ?? 132
                font.weight: Theme.numericWeight
                font.variableAxes: Theme.numericAxes
                font.features: { "tnum": 1 }
                font.letterSpacing: win.mono ? 0 : -0.04 * font.pixelSize
                // the numeric fonts carry tall ascent/descent; trim so the date and tick sit close
                height: Math.round(font.pixelSize * 1.02)
                verticalAlignment: Text.AlignVCenter
            }
        }
        // now playing: hidden without a player that has a title
        Component {
            id: media
            Item {
                id: m
                readonly property var players: Mpris.players.values
                readonly property var player: players.find(p => p.isPlaying) ?? players.find(p => !!p.trackTitle) ?? null
                readonly property string title: player?.trackTitle ?? ""
                readonly property string artist: player?.trackArtist ?? ""
                visible: title !== ""
                implicitHeight: visible ? np.implicitHeight + 30 : 0
                Column {
                    id: np
                    y: 30
                    width: parent.width
                    spacing: 7
                    // status line with a small accent square while playing
                    Item {
                        width: parent.width; height: npLabel.implicitHeight
                        Rectangle {
                            id: dot
                            visible: m.player?.isPlaying ?? false
                            width: 6; height: 6; radius: Theme.square ? 0 : 3
                            color: Theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                            x: win.right ? parent.width - width : 0
                        }
                        Text {
                            id: npLabel
                            width: parent.width - (dot.visible ? 14 : 0)
                            x: win.right || !dot.visible ? 0 : 14
                            horizontalAlignment: win.align
                            text: win.caps((m.player?.isPlaying ?? false) ? "Now playing" : "Paused")
                            color: Theme.white(0.38)
                            font.family: win.mono ? Theme.fontLabel : Theme.fontUi
                            font.pixelSize: win.mono ? 10 : 11.5
                            font.letterSpacing: win.mono ? 2.4 : 0.3
                            font.weight: Font.Medium
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: win.align
                        elide: Text.ElideRight
                        text: win.caps(m.title + (m.artist ? (win.mono ? "  /  " : " — ") + m.artist : ""))
                        color: Theme.white(0.82)
                        font.family: win.mono ? Theme.fontLabel : Theme.fontUi
                        font.pixelSize: win.mono ? 12 : 14
                        font.letterSpacing: win.mono ? 1.6 : 0
                        font.weight: Font.Medium
                    }
                }
            }
        }
        // one line per day from desktopWidgets.quotes (rotates at midnight)
        Component {
            id: quote
            Item {
                readonly property var list: (win.opt.quotes ?? []).filter(q => !!q)
                readonly property int day: Math.floor((clock.date.getTime() - clock.date.getTimezoneOffset() * 60000) / 86400000)
                readonly property string line: list.length ? String(list[day % list.length]) : ""
                visible: line !== ""
                implicitHeight: visible ? q.implicitHeight + 30 : 0
                Rectangle {
                    // short accent tick above the line (the look's signal colour)
                    y: 30
                    x: win.right ? parent.width - width : 0
                    width: 22; height: 2
                    color: Theme.accent
                    opacity: 0.9
                }
                Text {
                    id: q
                    y: 30 + 14
                    width: Math.min(parent.width, win.opt.quoteWidth ?? 360)
                    x: win.right ? parent.width - width : 0
                    horizontalAlignment: win.align
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: parent.line
                    color: Theme.white(0.5)
                    lineHeight: 1.25
                    font.family: win.mono ? Theme.fontLabel : Theme.fontDisplay
                    font.pixelSize: win.mono ? 11.5 : 15
                    font.letterSpacing: win.mono ? 0.6 : 0
                    font.italic: !win.mono
                }
            }
        }
    }
}

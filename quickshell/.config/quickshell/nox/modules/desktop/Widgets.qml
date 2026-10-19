pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import QtQuick.Effects
import qs.core
import qs.services

// Desktop widgets (bottom layer, namespace nox:widgets): a quiet column on the empty side of the
// wallpaper: date, big clock in the look's numeric font (Doto on Telemetry, like the lock screen),
// a system readout line, now playing (MPRIS: duotone art + grain, dot progress, audio bars from
// cava), a commit-activity dot grid (nox activity) and a line from desktopWidgets.quotes (one per
// day). Shown only while this screen's workspace has no windows; fades out when one maps, back in
// when it is empty again. Nothing ticks or runs (stats, cava, position) while it is hidden.
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
        readonly property var show: opt.show ?? ["date", "clock", "system", "media", "activity", "quote"]
        // a small mono caption (section labels, readout keys)
        component Cap: Text {
            color: Theme.white(0.38)
            font.family: win.mono ? Theme.fontLabel : Theme.fontUi
            font.pixelSize: win.mono ? 10 : 11.5
            font.letterSpacing: win.mono ? 2.4 : 0.3
            font.weight: Font.Medium
        }
        // dot-matrix cell: square on the square looks, round otherwise
        component Dot: Rectangle {
            width: 4; height: 4
            radius: Theme.square ? 0 : width / 2
        }

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
                        sourceComponent: ({ date: date, clock: clockC, system: system, media: media, activity: activity, quote: quote })[modelData] ?? null
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
        // one mono readout line: HOST · UP 3D 04:12 · CPU 12% · 48°C · BAT 80% (≤80 with the charge
        // limit on). Numbers glide to each new sample. desktopWidgets.system: list of
        // host | uptime | cpu | mem | temp | battery
        Component {
            id: system
            Item {
                id: sys
                readonly property var items: win.opt.system ?? ["host", "uptime", "cpu", "temp", "battery"]
                implicitHeight: row.implicitHeight + 22
                property real cpu: SysStats.cpu * 100
                property real mem: SysStats.mem * 100
                property real temp: Math.max(0, SysStats.temp)
                Behavior on cpu { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
                Behavior on mem { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
                Behavior on temp { NumberAnimation { duration: 900; easing.type: Easing.OutCubic } }
                FileView { id: host; path: "/etc/hostname"; blockLoading: true; printErrors: false }
                FileView { id: up; path: "/proc/uptime"; blockLoading: true; printErrors: false }
                Connections { target: clock; function onDateChanged() { up.reload(); } }
                function uptime() {
                    clock.date;
                    const s = Math.floor(parseFloat(up.text()) || 0);
                    const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                    return (d ? d + "D " : "") + String(h).padStart(2, "0") + ":" + String(m).padStart(2, "0");
                }
                readonly property var bat: UPower.displayDevice
                readonly property var parts: {
                    const out = [];
                    for (const k of items) {
                        if (k === "host") out.push(["", host.text().trim() || "linux"]);
                        else if (k === "uptime") out.push(["Up", uptime()]);
                        else if (k === "cpu") out.push(["Cpu", Math.round(cpu) + "%"]);
                        else if (k === "mem") out.push(["Mem", Math.round(mem) + "%"]);
                        else if (k === "temp" && SysStats.temp >= 0) out.push(["", Math.round(temp) + "°C"]);
                        else if (k === "battery" && bat?.isLaptopBattery)
                            out.push(["Bat", Math.round(bat.percentage * 100) + "%" + (ChargeLimit.on ? " ≤" + ChargeLimit.cap : "")]);
                    }
                    return out;
                }
                Row {
                    id: row
                    y: 22
                    x: win.right ? sys.width - width : 0
                    spacing: 0
                    Repeater {
                        model: sys.parts
                        Row {
                            id: part
                            required property var modelData
                            required property int index
                            spacing: 6
                            Cap { visible: part.index > 0; text: "·"; rightPadding: 4; leftPadding: 10 }
                            Cap { visible: part.modelData[0] !== ""; text: win.caps(part.modelData[0]) }
                            Text {
                                text: win.caps(part.modelData[1])
                                color: Theme.white(0.78)
                                font.family: win.mono ? Theme.fontLabel : Theme.fontUi
                                font.pixelSize: win.mono ? 10.5 : 12
                                font.letterSpacing: win.mono ? 1.6 : 0.2
                                font.weight: Font.Medium
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }
            }
        }

        // now playing: hidden without a player that has a title. Album art as a duotone in the
        // accent with film grain, a dot progress bar with times, and live audio bars (cava, only
        // while playing on an empty desktop; hidden when cava isn't installed).
        // desktopWidgets.media: { art, progress, bars } (all default true)
        Component {
            id: media
            Item {
                id: m
                readonly property var mo: win.opt.media ?? ({})
                readonly property var players: Mpris.players.values
                readonly property var player: players.find(p => p.isPlaying) ?? players.find(p => !!p.trackTitle) ?? null
                readonly property bool playing: player?.isPlaying ?? false
                readonly property string title: player?.trackTitle ?? ""
                readonly property string artist: player?.trackArtist ?? ""
                readonly property string artUrl: mo.art === false ? "" : (player?.trackArtUrl ?? "")
                readonly property bool hasArt: artUrl !== "" && art.status === Image.Ready
                readonly property real len: player?.lengthSupported ? player.length : 0
                visible: title !== ""
                implicitHeight: visible ? Math.max(np.implicitHeight, hasArt ? artBox.height : 0) + 30 : 0

                // MPRIS doesn't push position: poll it once a second while it can move
                Timer {
                    running: win.shown && m.playing && m.len > 0
                    interval: 1000; repeat: true; triggeredOnStart: true
                    onTriggered: m.player.positionChanged()
                }
                function fmt(t) {
                    t = Math.max(0, Math.floor(t));
                    const h = Math.floor(t / 3600), mm = Math.floor(t % 3600 / 60), ss = String(t % 60).padStart(2, "0");
                    return h ? h + ":" + String(mm).padStart(2, "0") + ":" + ss : mm + ":" + ss;
                }

                // cava: 24 bars of 0..6, one "v;v;...;" line per frame
                property var bars: []
                property bool hasCava: false
                Process {
                    running: true
                    command: ["sh", "-c", "command -v cava"]
                    onExited: code => m.hasCava = code === 0
                }
                Process {
                    running: m.hasCava && m.mo.bars !== false && win.shown && m.playing
                    command: ["cava", "-p", decodeURIComponent(Qt.resolvedUrl("../../assets/cava-widgets.conf").toString().replace(/^file:\/\//, ""))]
                    stdout: SplitParser { onRead: line => m.bars = line.split(";").filter(x => x !== "").map(Number) }
                    onRunningChanged: if (!running) m.bars = []
                }

                // album art (outer edge of the column): grey + accent duotone, grain on top
                Item {
                    id: artBox
                    visible: m.hasArt
                    y: 30
                    x: win.right ? m.width - width : 0
                    width: 92; height: 92
                    Image {
                        id: art
                        anchors.fill: parent
                        source: m.artUrl
                        sourceSize.width: 184; sourceSize.height: 184
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }
                    MultiEffect {
                        anchors.fill: parent
                        source: art
                        saturation: -1
                        contrast: 0.25
                        brightness: -0.05
                        colorization: 0.5
                        colorizationColor: Theme.accent
                    }
                    Image {
                        anchors.fill: parent
                        source: "../../assets/grain.png"
                        fillMode: Image.Tile
                        opacity: 0.22
                        smooth: false
                    }
                    Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Theme.white(0.08) }
                }

                Column {
                    id: np
                    y: 30
                    readonly property real inset: m.hasArt ? artBox.width + 18 : 0
                    x: win.right ? 0 : inset
                    width: m.width - inset
                    spacing: 7
                    // status line with a small accent square while playing
                    Item {
                        width: parent.width; height: npLabel.implicitHeight
                        Rectangle {
                            id: dot
                            visible: m.playing
                            width: 6; height: 6; radius: Theme.square ? 0 : 3
                            color: Theme.accent
                            anchors.verticalCenter: parent.verticalCenter
                            x: win.right ? parent.width - width : 0
                        }
                        Cap {
                            id: npLabel
                            width: parent.width - (dot.visible ? 14 : 0)
                            x: win.right || !dot.visible ? 0 : 14
                            horizontalAlignment: win.align
                            text: win.caps(m.playing ? "Now playing" : "Paused")
                        }
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: win.align
                        elide: Text.ElideRight
                        text: win.caps(m.title)
                        color: Theme.white(0.86)
                        font.family: win.mono ? Theme.fontLabel : Theme.fontUi
                        font.pixelSize: win.mono ? 12 : 14
                        font.letterSpacing: win.mono ? 1.6 : 0
                        font.weight: Font.Medium
                    }
                    Text {
                        visible: m.artist !== ""
                        width: parent.width
                        horizontalAlignment: win.align
                        elide: Text.ElideRight
                        text: win.caps(m.artist)
                        color: Theme.white(0.5)
                        font.family: win.mono ? Theme.fontLabel : Theme.fontUi
                        font.pixelSize: win.mono ? 10.5 : 12.5
                        font.letterSpacing: win.mono ? 1.4 : 0
                    }
                    // dot progress: played dots bright, the play head in the accent, then dim
                    Item {
                        id: prog
                        visible: m.mo.progress !== false && m.len > 0
                        width: parent.width; height: visible ? 16 : 0
                        readonly property real frac: m.len > 0 ? Math.min(1, (m.player?.position ?? 0) / m.len) : 0
                        readonly property int n: Math.max(8, Math.floor((width - times.implicitWidth - 12) / 7))
                        readonly property int head: Math.round(frac * (n - 1))
                        Row {
                            id: dots
                            anchors.verticalCenter: parent.verticalCenter
                            x: win.right ? parent.width - width : 0
                            spacing: 3
                            Repeater {
                                model: prog.n
                                Dot {
                                    required property int index
                                    color: index === prog.head ? Theme.accent : index < prog.head ? Theme.white(0.78) : Theme.white(0.14)
                                }
                            }
                        }
                        Cap {
                            id: times
                            anchors.verticalCenter: parent.verticalCenter
                            x: win.right ? 0 : parent.width - width
                            text: m.fmt(m.player?.position ?? 0) + " / " + m.fmt(m.len)
                            font.features: { "tnum": 1 }
                        }
                    }
                    // audio bars: 24 columns x 6 dots, lit from the bottom, the peak dot in the accent
                    Item {
                        visible: m.hasCava && m.mo.bars !== false && m.playing
                        width: parent.width; height: visible ? 6 * 6 : 0
                        Row {
                            x: win.right ? parent.width - width : 0
                            spacing: 3
                            Repeater {
                                model: 24
                                Column {
                                    id: bar
                                    required property int index
                                    readonly property int v: m.bars[index] ?? 0
                                    spacing: 2
                                    Repeater {
                                        model: 6
                                        Dot {
                                            required property int index
                                            readonly property int lvl: 6 - index      // top row = 6
                                            color: lvl > bar.v ? Theme.white(0.06) : lvl === bar.v ? Theme.accent : Theme.white(0.7)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // commit activity: weeks x 7 days of dots (Monday on top), shaded in the accent by
        // count relative to the busiest day, today outlined. Data: ~/.local/state/nox/activity.json
        // from `nox activity refresh` (GitHub through gh, else local git), refreshed hourly while
        // shown. desktopWidgets.activity: { source: github | local, weeks: 12 }
        Component {
            id: activity
            Item {
                id: act
                readonly property var ao: win.opt.activity ?? ({})
                readonly property string file: Paths.state("activity")
                property var info: null     // (not `data`: that is Item's children list)
                readonly property var days: info?.days ?? []
                readonly property int total: days.reduce((a, d) => a + Math.max(0, d.count), 0)
                readonly property int peak: days.reduce((a, d) => Math.max(a, d.count), 0)
                readonly property int streak: {
                    let n = 0, i = days.length - 1;
                    while (i >= 0 && days[i].count < 0) i--;           // future days this week
                    if (i >= 0 && days[i].count === 0) i--;              // today not started yet
                    for (; i >= 0 && days[i].count > 0; i--) n++;
                    return n;
                }
                readonly property string today: Qt.formatDate(clock.date, "yyyy-MM-dd")
                visible: days.length > 0
                implicitHeight: visible ? 30 + head.implicitHeight + 10 + grid.height : 0

                FileView {
                    id: store
                    path: act.file
                    watchChanges: true
                    printErrors: false
                    onFileChanged: reload()
                    onLoaded: { try { act.info = JSON.parse(text()); } catch (e) { act.info = null; } }
                }
                function stale() {
                    const t = Date.parse(info?.updated ?? "");
                    return !info || isNaN(t) || Date.now() - t > 3600000 || info.days.length !== (ao.weeks ?? 12) * 7 || (info.source !== (ao.source ?? "github") && info.source !== "local");
                }
                Process {
                    id: refresher
                    command: ["nox", "activity", "refresh", "--source", act.ao.source ?? "github", "--weeks", String(act.ao.weeks ?? 12)]
                }
                Timer {
                    running: win.shown
                    interval: 60000; repeat: true; triggeredOnStart: true
                    onTriggered: if (act.stale() && !refresher.running) refresher.running = true
                }

                Cap {
                    id: head
                    y: 30
                    width: act.width
                    horizontalAlignment: win.align
                    text: win.caps("Commits · " + act.total + " in " + Math.round(act.days.length / 7) + " weeks"
                                   + (act.streak > 1 ? " · " + act.streak + " day streak" : ""))
                }
                Grid {
                    id: grid
                    y: head.y + head.implicitHeight + 10
                    x: win.right ? act.width - width : 0
                    rows: 7
                    flow: Grid.TopToBottom
                    spacing: 4
                    Repeater {
                        model: act.days
                        Rectangle {
                            required property var modelData
                            readonly property int c: modelData.count
                            readonly property real level: c <= 0 || act.peak <= 0 ? 0 : Math.ceil(4 * Math.sqrt(c / act.peak))   // 1..4
                            width: 9; height: 9
                            radius: Theme.square ? 1 : 4.5
                            color: c < 0 ? "transparent" : level === 0 ? Theme.white(0.07) : Theme.rgba(Theme.t.color.accent, [0, 0.32, 0.55, 0.78, 1][level])
                            border.width: modelData.date === act.today ? 1 : 0
                            border.color: Theme.white(0.85)
                        }
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

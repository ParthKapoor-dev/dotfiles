pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.core
import qs.components
import qs.services
// the island types (IslandEntry, IslandPill, IslandCard) by module: inside the card's LazyLoader the implicit
// same-directory import did not always resolve them at runtime
import qs.modules.bar.widgets

// Dynamic Island (bar centre, id "island"): idle = the clock (widgets.island.idle "clock"; "none" =
// hidden while nothing is live). When something is live, one black pill morphs to the most
// important thing, in widgets.island.order (default: recording, mic, agent, timer, download, music,
// shelf; leave one out to never show it). The other live things are dots on the pill's right
// edge; the wheel cycles through them. Hover (widgets.island.hoverDelay ms) = the expanded card
// (IslandCard) with that thing's controls; a click pins the card (a click outside, Esc-less, or
// another click on the pill closes it). Right click while live = the clock's popup.
// Cost: it only binds to the services' own properties. Tickers run only while something they
// show is live (recording time 1 s; the card's music position 1 s); the one looping animation
// (agent needs-you ping) runs only while that is shown on screen. The card is a PopupWindow in a
// LazyLoader: it only exists while shown.
// Sources: Recorder, Voice (modules.voice), Agents (modules.agents), Countdown (`nox timer`),
// Downloads (*.part / *.crdownload in ~/Downloads), Mpris (a player that is playing), Shelf
// (modules.shelf; for widgets.island.shelfSeconds after a drop).
// widgets.island.{idle, order, hoverDelay, maxText, cardWidth, shelfSeconds, color}
Item {
    id: root
    property string widgetId: "island"
    readonly property var options: Config.widget(widgetId)
    readonly property var order: options.order ?? ["recording", "mic", "agent", "timer", "download", "music", "shelf"]
    function wants(k) { return order.indexOf(k) !== -1; }
    readonly property bool idleClock: (options.idle ?? "clock") === "clock"
    readonly property var clockOpts: Config.widget("clock")
    readonly property bool mono: Theme.labelsMono && Theme.square
    readonly property real maxText: options.maxText ?? 150
    readonly property real cardWidth: options.cardWidth ?? 320
    // the bar is mapped (an unmapped or covered bar window stops the ping and the tickers)
    readonly property bool onScreen: visible && (QsWindow.window?.visible ?? true)

    readonly property bool useVoice: wants("mic") && Config.moduleEnabled("voice")
    readonly property bool useAgents: wants("agent") && Config.moduleEnabled("agents")
    readonly property bool useShelf: wants("shelf") && Config.moduleEnabled("shelf")

    visible: live.length > 0 || idleClock
    implicitHeight: Math.max(20, Theme.barHeight - 6)
    implicitWidth: targetWidth
    // no morph from 0 on the first layout
    property bool ready: false
    Behavior on implicitWidth { enabled: root.ready; NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
    readonly property real targetWidth: shown ? pill.implicitWidth + 24 + (dots.count > 0 ? dots.width + 8 : 0)
                                              : clockText.implicitWidth + 16

    // ---------------------------------------------------------------- shared state
    property real now: Date.now()
    Timer {
        running: root.onScreen && (recE.live || (root.cardOpen && root.shownKind === "agent"))
        interval: 1000; repeat: true; triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
    function clockTime(ms) {
        const s = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(s % 60).padStart(2, "0");
    }
    function base(p) { return String(p ?? "").replace(/^.*\//, ""); }

    // ---------------------------------------------------------------- sources
    IslandEntry {
        id: recE
        kind: "recording"
        live: root.wants("recording") && Recorder.recording
        glyph: "record"
        tint: Theme.red
        trail: live ? root.clockTime(root.now - Recorder.startedAt) : ""
        title: "Screen recording"
        sub: live ? root.base(Recorder.file) : ""
        actions: [{ label: "Stop", icon: "record", close: true, act: () => Recorder.stop() }]
    }

    IslandEntry {
        id: micE
        readonly property string phase: root.useVoice ? Voice.phase : "idle"
        readonly property bool rec: phase === "rec"
        kind: "mic"
        live: rec || phase === "tx" || phase === "tidy"
        glyph: "mic"
        tint: Theme.accent
        text: rec ? "Listening" : "Transcribing"
        trail: rec ? root.clockTime(Voice.elapsed) : ""
        level: rec ? Voice.hist.slice(-5) : []
        title: "Voice typing"
        sub: !live ? "" : rec ? (Voice.mode === "hold" ? "Release the keys to type it" : "Stop to type it") + " · " + Voice.sourceLabel
                             : phase === "tidy" ? "Tidying up" : "Transcribing" + (Voice.backend ? " · " + Voice.backend : "")
        actions: rec ? [{ label: "Stop", icon: "check", close: true, act: () => Voice.stop() },
                        { label: "Cancel", icon: "x", close: true, act: () => Voice.cancel() }]
                     : [{ label: "Cancel", icon: "x", close: true, act: () => Voice.cancel() }]
    }

    IslandEntry {
        id: agentE
        readonly property var need: root.useAgents ? Agents.needList : []
        readonly property var work: root.useAgents ? Agents.workList : []
        readonly property var s: need[0] ?? work[0] ?? null
        readonly property bool needs: need.length > 0
        function since(x) { return Agents.hms(root.now - (x?.since ?? root.now)); }
        function what(x) { return x?.status === "error" ? "Error" : x?.status === "needs-you" ? "Needs you" : "Working"; }
        kind: "agent"
        live: s !== null
        glyph: "sparkle"
        tint: needs ? Theme.accent : Theme.label
        urgent: root.useAgents && Agents.needsYou > 0
        text: s ? (s.project || "Agent") : ""
        trail: !s ? "" : needs ? (need.length > 1 ? need.length + " need you" : s.status === "error" ? "error" : "needs you")
                               : (work.length > 1 ? work.length + " working" : "working")
        trailMono: false
        title: s ? (s.project || "Agent") + " · " + Agents.kindName(s) : ""
        sub: s ? what(s) + " · " + since(s) : ""
        rows: need.length + work.length < 2 ? [] : need.concat(work).slice(0, 5).map(x => ({
            title: x.project || "Agent", sub: what(x) + " · " + since(x), glyph: "sparkle",
            on: x.status !== "working", close: true, act: () => Agents.jump(x.id)
        }))
        actions: !s ? [] : [
            { label: "Jump", icon: "arrowR", close: true, act: () => Agents.jump(s.id) },
            { label: "Agents", icon: "grid", close: true, act: () => Agents.show(s.id) }
        ]
    }

    IslandEntry {
        id: timerE
        readonly property bool on: root.wants("timer") && (Countdown.active || Countdown.ringing)
        readonly property bool ring: on && !Countdown.active
        kind: "timer"
        live: on
        glyph: "bell"
        tint: Theme.accent
        progress: on && Countdown.active ? Countdown.progress : -1
        text: !on ? "" : Countdown.label !== "" ? Countdown.label : Countdown.paused ? "Paused" : ring ? "Timer" : ""
        trail: !on ? "" : ring ? "Done" : Countdown.fmt(Countdown.left)
        title: on && Countdown.label !== "" ? Countdown.label : "Timer"
        sub: !on ? "" : Countdown.running ? "Ends at " + Qt.formatTime(new Date(Countdown.endsAt), "HH:mm")
                      : Countdown.paused ? "Paused · " + Countdown.fmt(Countdown.duration) : "Done · " + Countdown.fmt(Countdown.duration)
        actions: ring ? [{ label: "Again", icon: "restart", act: () => Countdown.again() },
                         { label: "Dismiss", icon: "check", close: true, act: () => Countdown.dismiss() }]
                      : [{ label: "+1 min", icon: "plus", act: () => Countdown.add(60000) },
                         { label: Countdown.paused ? "Resume" : "Pause", icon: Countdown.paused ? "play" : "pause", act: () => Countdown.togglePause() },
                         { label: "Stop", icon: "x", close: true, act: () => Countdown.stop() }]
    }

    IslandEntry {
        id: dlE
        readonly property bool on: root.wants("download")
        readonly property bool moving: on && Downloads.live
        readonly property var done: on && !moving ? Downloads.done : null
        readonly property var list: moving ? Downloads.moving : []
        function amount(b, r) { return Downloads.human(b) + (r > 1000 ? " · " + Downloads.human(r) + "/s" : ""); }
        kind: "download"
        live: moving || done !== null
        glyph: done ? "check" : "download"
        tint: done ? Theme.green : Theme.label
        text: done ? done.name : list.length > 1 ? list.length + " downloads" : (list[0]?.final || "Downloading")
        trail: done ? "Done" : moving ? Downloads.human(Downloads.bytes) : ""
        title: done ? "Downloaded" : list.length > 1 ? list.length + " downloads" : "Downloading"
        sub: done ? done.name : moving ? Downloads.human(Downloads.bytes) + " so far" + (Downloads.rate > 1000 ? " · " + Downloads.human(Downloads.rate) + "/s" : "") : ""
        rows: list.length > 1 ? list.map(f => ({ title: f.final || f.name, sub: amount(f.bytes, f.rate), glyph: "download" })) : []
        actions: done ? [{ label: "Open", icon: "doc", close: true, act: () => Downloads.openDone() },
                         { label: "Show folder", icon: "folder", close: true, act: () => Downloads.openFolder() }]
                      : [{ label: "Downloads", icon: "folder", close: true, act: () => Downloads.openFolder() }]
    }

    // music: a player that is playing; while the card shows it, a pause keeps it there
    readonly property var players: wants("music") ? Mpris.players.values : []
    readonly property var playing: players.find(p => p.isPlaying) ?? null
    property var heldPlayer: null
    onPlayingChanged: if (playing) heldPlayer = playing
    readonly property var player: playing ?? (cardOpen && shownKind === "music" && heldPlayer && players.indexOf(heldPlayer) !== -1 ? heldPlayer : null)
    Timer {
        running: root.cardOpen && root.shownKind === "music" && (root.player?.isPlaying ?? false)
        interval: 1000; repeat: true
        onTriggered: root.player?.positionChanged()
    }
    IslandEntry {
        id: musicE
        readonly property var p: root.player
        kind: "music"
        live: p !== null
        glyph: "note"
        art: p?.trackArtUrl ?? ""
        text: p ? (p.trackTitle || p.identity || "Playing") : ""
        trailMono: false
        title: text
        sub: p ? (p.trackArtist || p.identity || "") : ""
        progress: p && p.length > 0 ? Math.max(0, Math.min(1, p.position / p.length)) : -1
        actions: !p ? [] : [
            { label: "", icon: "prev", enabled: p.canGoPrevious, act: () => p.previous() },
            { label: "", icon: p.isPlaying ? "pause" : "play", enabled: p.canTogglePlaying, act: () => p.togglePlaying() },
            { label: "", icon: "next", enabled: p.canGoNext, act: () => p.next() }
        ]
    }

    // shelf: a drop shows for shelfSeconds (longer while its card is open)
    property var shelfIds: []
    Connections {
        target: root.useShelf ? Shelf : null
        function onAdded(ids) { root.shelfIds = ids; shelfOff.restart(); }
    }
    Timer {
        id: shelfOff
        interval: Math.max(1, Number(root.options.shelfSeconds ?? 4)) * 1000
        onTriggered: if (root.cardOpen && root.shownKind === "shelf") restart(); else root.shelfIds = []
    }
    IslandEntry {
        id: shelfE
        readonly property var got: root.useShelf ? root.shelfIds.map(id => Shelf.find(id)).filter(it => !!it) : []
        function glyphFor(it) { return it.kind === "image" ? "image" : it.kind === "link" ? "globe" : it.kind === "dir" ? "folder" : "doc"; }
        kind: "shelf"
        live: got.length > 0
        glyph: "tray"
        text: got.length === 1 ? (got[0].title || got[0].name || "Shelf") : "Shelf"
        trail: got.length > 1 ? got.length + " added" : got.length === 1 ? "added" : ""
        trailMono: false
        title: got.length > 1 ? got.length + " items added to the Shelf" : "Added to the Shelf"
        sub: root.useShelf ? Shelf.count + (Shelf.count === 1 ? " item" : " items") + " on the shelf" : ""
        rows: got.slice(0, 4).map(it => ({ title: it.title || it.name || "", sub: it.kind, glyph: glyphFor(it) }))
        actions: [{ label: "Open Shelf", icon: "tray", close: true, act: () => Quickshell.execDetached(["nox", "shelf", "open"]) }]
    }

    // ---------------------------------------------------------------- what's shown
    readonly property var byKind: ({ recording: recE, mic: micE, agent: agentE, timer: timerE, download: dlE, music: musicE, shelf: shelfE })
    readonly property var live: order.map(k => byKind[k]).filter(e => !!e && e.live)
    property string pickKind: ""                  // chosen with the wheel / the card; "" = top priority
    readonly property IslandEntry current: live.find(e => e.kind === pickKind) ?? live[0] ?? null
    // a new top priority thing takes over from a wheel pick
    readonly property string headKind: live[0]?.kind ?? ""
    onHeadKindChanged: pickKind = ""
    property IslandEntry shown: null              // what the pill draws (swapped mid-fade)
    readonly property string shownKind: shown?.kind ?? ""
    readonly property var extras: live.filter(e => e !== shown)
    Component.onCompleted: { shown = current; Qt.callLater(() => root.ready = true); }
    onCurrentChanged: if (current !== shown) swap.restart()
    onLiveChanged: if (live.length === 0) hideCard()
    SequentialAnimation {
        id: swap
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: Theme.durFade / 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase }
        ScriptAction { script: root.shown = root.current }
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase }
    }
    function cycle(d) {
        if (live.length < 2) return;
        const i = Math.max(0, live.indexOf(current));
        pickKind = live[(i + d + live.length) % live.length].kind;
    }

    // ---------------------------------------------------------------- the pill
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.square ? 4 : height / 2
        readonly property color island: root.options.color ?? Qt.rgba(0, 0, 0, 0.9)
        color: root.shown ? island : Theme.white(mouse.containsMouse || root.idleActive ? 0.14 : 0)
        Behavior on color { ColorAnimation { duration: Theme.durFade } }
        border.width: root.shown ? 1 : 0
        border.color: Theme.white(0.08)
    }
    readonly property string clockPopup: clockOpts.clickPopup ?? "notifications"
    readonly property bool idleActive: !shown && clockPopup !== "" && Panels.popup === clockPopup
    Item {
        id: content
        anchors.fill: parent
        SystemClock { id: clock; precision: SystemClock.Minutes; enabled: !root.shown }
        GText {
            id: clockText
            visible: !root.shown
            anchors.centerIn: parent
            text: Qt.formatDateTime(clock.date, root.options.format ?? root.clockOpts.format ?? "ddd d MMM HH:mm")
            font.features: ({ "tnum": 1 })
            font.family: root.mono ? Theme.fontLabel : Theme.fontUi
            font.pixelSize: root.mono ? 12 : Theme.fontSize
            font.weight: root.mono ? Font.Medium : Font.Normal
            font.capitalization: root.mono ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: root.mono ? 0.6 : 0
        }
        IslandPill {
            id: pill
            visible: root.shown !== null
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            entry: root.shown
            animate: root.onScreen
            maxText: root.maxText
        }
    }
    Row {
        id: dots
        readonly property int count: root.extras.length
        visible: count > 0 && root.shown !== null
        anchors.right: parent.right; anchors.rightMargin: 11
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Repeater {
            model: root.extras
            Rectangle {
                required property var modelData
                width: 5; height: 5
                radius: Theme.square ? 1 : 2.5
                color: modelData.tint
                opacity: 0.85
            }
        }
    }
    scale: mouse.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real acc: 0
        onPressed: Panels.notePointer()
        onEntered: { closeTimer.stop(); if (root.shown && !root.cardOpen && Panels.popup === "") openTimer.restart(); }
        onExited: { openTimer.stop(); if (root.cardOpen) closeTimer.restart(); }
        onClicked: m => {
            if (!root.shown || m.button === Qt.RightButton) {
                root.hideCard();
                if (root.clockPopup !== "" && Panels.exists(root.clockPopup)) Panels.toggle(root.clockPopup);
                return;
            }
            openTimer.stop();
            if (root.pinned) { root.hideCard(); return; }
            Panels.close();
            root.showCard();
            root.pinned = true;
        }
        onWheel: w => {
            acc += w.angleDelta.y;
            if (Math.abs(acc) < 120) return;
            root.cycle(acc > 0 ? -1 : 1);
            acc = 0;
        }
    }

    // ---------------------------------------------------------------- the card
    property bool cardOpen: false        // logically open (fades in / out on this)
    property bool cardMapped: false      // the popup exists (kept through the close motion)
    property bool pinned: false
    property bool cardHovered: false
    property real cardCx: 0              // island centre in the bar window
    Timer { id: openTimer; interval: root.options.hoverDelay ?? 140; onTriggered: if (mouse.containsMouse && Panels.popup === "") root.showCard() }
    Timer { id: closeTimer; interval: 260; onTriggered: if (!root.pinned && !mouse.containsMouse && !root.cardHovered) root.hideCard() }
    Timer { id: unmapTimer; interval: Theme.durPop * 1.5 + 30; onTriggered: if (!root.cardOpen) root.cardMapped = false }
    function placeCard() { cardCx = root.mapToItem(null, root.width / 2, 0).x; }
    function showCard() {
        if (!shown) return;
        placeCard();
        unmapTimer.stop();
        cardMapped = true;
        cardOpen = true;
    }
    function hideCard() {
        openTimer.stop(); closeTimer.stop();
        pinned = false;
        cardHovered = false;
        if (!cardOpen) return;
        cardOpen = false;
        unmapTimer.restart();
    }
    onWidthChanged: if (cardOpen) placeCard()
    // another popup (a bar button, a shortcut) takes over
    Connections { target: Panels; function onPopupChanged() { if (Panels.popup !== "") root.hideCard(); } }

    LazyLoader {
        active: root.cardMapped
        PopupWindow {
            id: pop
            readonly property real pad: 28
            anchor.window: root.QsWindow.window
            anchor.rect.x: root.cardCx - implicitWidth / 2
            anchor.rect.y: root.QsWindow.window?.height ?? Theme.barHeight
            implicitWidth: root.cardWidth + pad * 2
            implicitHeight: body.height + 6 + pad
            visible: true
            color: "transparent"
            mask: Region { item: body }

            // pinned: a click anywhere else closes it (bar windows stay usable)
            HyprlandFocusGrab {
                active: root.pinned
                windows: [pop].concat(Panels.barWindows)
                onCleared: root.hideCard()
            }
            Item {
                id: motion
                anchors.fill: parent
                property real fade: 0
                opacity: fade
                Component.onCompleted: fade = Qt.binding(() => root.cardOpen ? 1 : 0)
                Behavior on fade { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                transform: [
                    Scale {
                        origin.x: motion.width / 2; origin.y: 0
                        xScale: 0.96 + 0.04 * motion.fade; yScale: xScale
                    },
                    Translate { y: -4 * (1 - motion.fade) }
                ]
                RectangularShadow {
                    anchors.fill: body
                    radius: body.radius
                    offset.y: 14; blur: 36; spread: -6
                    color: Theme.rgba("#000000", 0.45)
                }
                Glass {
                    id: body
                    menu: true
                    color: Theme.cardGlass
                    radius: Theme.square ? 6 : 18
                    x: pop.pad; y: 6
                    width: root.cardWidth
                    height: card.implicitHeight + 28
                    HoverHandler {
                        onHoveredChanged: {
                            root.cardHovered = hovered;
                            if (hovered) closeTimer.stop(); else if (!root.pinned) closeTimer.restart();
                        }
                    }
                    IslandCard {
                        id: card
                        x: 14; y: 14
                        width: parent.width - 28
                        entry: root.shown
                        others: root.extras
                        animate: root.cardOpen
                        onActed: close => { if (close) root.hideCard(); }
                        onPick: kind => root.pickKind = kind
                    }
                }
            }
        }
    }
}

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

// Dynamic Island (bar centre, id "island"; design mock C8 / 23i). One solid black pill hanging in
// the bar shows the most important live thing; its width morphs on a spring as things come and
// go, the face cross-fades (blur + scale) and the pill bumps when the top thing changes. The
// other live things are mini glyphs at its right end (a hot one, e.g. an agent that needs you,
// in accent with a dot); a click on one shows it, a click on the pill cycles (one thing: opens the
// card), the wheel cycles too. Hover (widgets.island.hoverDelay ms) grows the pill in place into
// the card (IslandCard): a PopupWindow laid exactly over the pill, drawing the same black shape,
// which springs from the pill's size to the card's (the bar can't grow, the popup can). A click
// on the pill / card pins it (a click outside closes it). Right click = the clock's popup.
// Order: hot things first (agent needs you, timer rang), then widgets.island.order (default:
// recording, mic, agent, timer, download, music, shelf; leave one out to never show it).
// idle: widgets.island.idle "clock" = the clock while nothing is live; "none" = hidden.
// Cost: idle = nothing runs (no timer, no animation; the clock is a minute SystemClock, off with
// idle "none"). Loops (agent spinner + ping, need pulse, recording blink, download ring, eq bars,
// card mic levels) are one 12 Hz Timer stepping `frame`, running only while such a thing is shown
// and the bar is on screen (mapped, not under a fullscreen window); while the card covers the pill only the card's own loop (eq, levels)
// keeps it running. Times tick at 1 Hz only while shown (recording, agent age, card clocks). The
// card only exists while open (LazyLoader).
// Sources: Recorder, Voice (modules.voice), Agents (modules.agents), Countdown (`nox timer`),
// Downloads (*.part / *.crdownload in ~/Downloads), Mpris (a player that is playing), Shelf
// (modules.shelf; for widgets.island.shelfSeconds after a drop).
// widgets.island.{idle, order, hoverDelay, maxText, cardWidth, shelfSeconds, color}
Item {
    id: root
    property string widgetId: "island"
    // false: no popup for the card (the offscreen tests draw an IslandMorph in their own window)
    property bool popupCard: true
    readonly property var options: Config.widget(widgetId)
    readonly property var order: options.order ?? ["recording", "mic", "agent", "timer", "download", "music", "shelf"]
    function wants(k) { return order.indexOf(k) !== -1; }
    readonly property bool idleClock: (options.idle ?? "clock") === "clock"
    readonly property var clockOpts: Config.widget("clock")
    readonly property bool mono: Theme.labelsMono && Theme.square
    readonly property real maxText: options.maxText ?? 150
    // the card's layout (3 buttons + tabs) needs 372 px (the mock's width): a smaller cardWidth is raised
    readonly property real cardWidth: Math.max(372, options.cardWidth ?? 372)
    readonly property color islandColor: options.color ?? "#000000"
    // the bar is mapped (an unmapped or covered bar window stops every loop and ticker)
    readonly property bool onScreen: visible && (QsWindow.window?.visible ?? true)
    // a fullscreen window (not a maximized one) covers the bar: the decorative loops stop
    readonly property var hyprMon: QsWindow.window?.screen ? Hyprland.monitorFor(QsWindow.window.screen) : null
    readonly property bool covered: (hyprMon?.activeWorkspace?.hasFullscreen ?? false)
        && (Hyprland.activeToplevel?.lastIpcObject.fullscreen ?? 2) === 2

    readonly property bool useVoice: wants("mic") && Config.moduleEnabled("voice")
    readonly property bool useAgents: wants("agent") && Config.moduleEnabled("agents")
    readonly property bool useShelf: wants("shelf") && Config.moduleEnabled("shelf")

    readonly property real pillH: Math.max(20, Theme.barHeight - 6)
    visible: live.length > 0 || idleClock || appear.running
    implicitHeight: pillH
    implicitWidth: targetWidth
    // no morph from 0 on the first layout
    property bool ready: false
    Behavior on implicitWidth {
        enabled: root.ready && root.onScreen
        NumberAnimation { duration: 560; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
    }
    readonly property real faceW: (front === 0 ? slotA : slotB).implicitWidth
    readonly property real targetWidth: shown ? 10 + faceW + 11 + (others.count > 0 ? others.implicitWidth + 3 : 0)
                                              : clockText.implicitWidth + 16

    // ---------------------------------------------------------------- clocks
    // 12 Hz loop clock for everything that moves on its own (see IslandPill); 0 = still
    property int frame: 0
    function loops(e) {
        if (!e) return false;
        const k = e.kind, m = e.mode;
        return (k === "agent" && (m === "work" || m === "need")) || k === "recording" || (k === "timer" && m === "ring")
            || (k === "download" && m === "run") || (k === "music" && m === "play");
    }
    readonly property bool cardLoops: shownKind === "mic" ? (shown?.levels ?? false) : shownKind === "music" && shown?.mode === "play"
    readonly property bool looping: onScreen && !covered && shown !== null && (cardFull ? cardLoops : loops(shown) || (cardOpen && cardLoops))
    property var micLevels: []
    Timer {
        interval: 83; repeat: true
        running: root.looping
        onTriggered: {
            root.frame = root.frame % 1000000 + 1;
            if (root.cardOpen && root.shownKind === "mic") root.micLevels = Voice.hist.slice(-30);
        }
        onRunningChanged: if (!running) root.frame = 0
    }
    // 1 Hz wall clock for times on screen
    property real now: Date.now()
    Timer {
        running: root.onScreen && (root.shownKind === "recording" || root.shownKind === "agent")
        interval: 1000; repeat: true; triggeredOnStart: true
        onTriggered: root.now = Date.now()
    }
    function clockTime(ms) {
        const s = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m)) + ":" + String(s % 60).padStart(2, "0");
    }
    function age(ms) {
        const m = Math.max(1, Math.floor(ms / 60000));
        return m < 60 ? m + "m" : Math.floor(m / 60) + "h" + String(m % 60).padStart(2, "0");
    }
    function base(p) { return String(p ?? "").replace(/^.*\//, ""); }
    function firstLine(t) { return String(t ?? "").split("\n").map(x => x.trim()).find(x => x !== "") ?? ""; }

    // ---------------------------------------------------------------- sources
    IslandEntry {
        id: recE
        kind: "recording"
        live: root.wants("recording") && Recorder.recording
        glyph: "record"
        tint: Theme.red
        readonly property string t: live ? root.clockTime(root.now - Recorder.startedAt) : ""
        text: t
        meta: "Rec"
        tile: "rec"
        kicker: "Screen recording · wf-recorder"
        title: live ? root.base(Recorder.file) : ""
        big: t
        info: live ? String(Recorder.file).replace(/\/[^/]*$/, "").replace(Quickshell.env("HOME"), "~") : ""
        actions: [{ label: "Stop recording", icon: "record", pri: true, close: true, act: () => Recorder.stop() }]
    }

    IslandEntry {
        id: micE
        readonly property string phase: root.useVoice ? Voice.phase : "idle"
        readonly property bool rec: phase === "rec"
        kind: "mic"
        live: rec || phase === "tx" || phase === "tidy"
        glyph: "mic"
        tint: Theme.orange
        text: "Mic"
        meta: rec ? "Listening " + root.clockTime(Voice.elapsed) : phase === "tidy" ? "Tidying" : "Transcribing"
        kicker: "Voice typing" + (root.useVoice && Voice.sourceLabel ? " · " + Voice.sourceLabel : "")
        title: rec ? "Listening" : phase === "tidy" ? "Tidying up" : "Transcribing"
        big: rec ? root.clockTime(Voice.elapsed) : ""
        levels: rec
        info: !live ? "" : rec ? (Voice.mode === "hold" ? "Release the keys to type it" : "Stop to type it")
                               : Voice.backend ? "Whisper · " + Voice.backend : ""
        actions: rec ? [{ label: "Stop", icon: "check", pri: true, close: true, act: () => Voice.stop() },
                        { label: "Cancel", icon: "x", close: true, act: () => Voice.cancel() }]
                     : [{ label: "Cancel", icon: "x", close: true, act: () => Voice.cancel() }]
    }

    // agent: the first that needs you, else one that just finished a turn (agentDoneSeconds), else working
    property string doneId: ""
    property real doneSince: Date.now()      // only turns that end after the shell started
    Connections {
        target: root.useAgents ? Agents : null
        function onSessionsChanged() {
            const fresh = Agents.doneList.filter(s => (s.turn?.end ?? 0) > root.doneSince && Date.now() - s.turn.end < 10000);
            if (!fresh.length) return;
            const s = fresh.reduce((a, b) => (b.turn.end > a.turn.end ? b : a));
            root.doneSince = s.turn.end;
            root.doneId = s.id;
            doneOff.restart();
        }
    }
    Timer {
        id: doneOff
        interval: 8000
        onTriggered: if (root.cardOpen && root.shownKind === "agent") restart(); else root.doneId = ""
    }
    IslandEntry {
        id: agentE
        readonly property var need: root.useAgents ? Agents.needList : []
        readonly property var work: root.useAgents ? Agents.workList : []
        readonly property var done: root.useAgents && root.doneId !== "" ? (Agents.doneList.find(x => x.id === root.doneId) ?? null) : null
        readonly property var s: need[0] ?? done ?? work[0] ?? null
        readonly property var all: need.concat(work)
        readonly property var perm: s?.perm ?? null
        readonly property var turn: s && done === s ? (Agents.turns[s.id] ?? s.turn ?? null) : null
        readonly property string proj: s ? (s.project || "Agent") : ""
        function what(x) { return x.status === "error" ? "Error" : x.status === "needs-you" ? "Needs you" : "Working"; }
        kind: "agent"
        live: s !== null
        mode: !s ? "" : need.length > 0 ? "need" : s === done ? "done" : "work"
        hot: mode === "need"
        glyph: "sparkle"
        tint: hot ? Theme.accent : Theme.label
        text: mode === "need" ? (s.status === "error" ? "Error" : "Needs you") : mode === "done" ? "Done" : proj
        textAccent: mode === "need"
        meta: !s ? "" : mode === "need" ? proj + (perm?.tool ? " · " + perm.tool : "") + (need.length > 1 ? " · +" + (need.length - 1) : "")
                      : mode === "done" ? proj
                      : "· " + root.age(root.now - (s.since ?? root.now)) + (work.length > 1 ? " · +" + (work.length - 1) : "")
        segs: mode !== "work" ? [] : (s.activity ?? []).filter(a => a.k === "tool" && (a.ts ?? 0) >= (s.since ?? 0)).slice(-8)
            .map(a => a.s === "run" ? "run" : a.s === "er" ? "er" : "ok")
        tile: mode === "done" ? "" : "acc"
        kicker: !s ? "" : Agents.kindName(s) + " · " + proj + " · "
            + (mode === "need" ? (s.status === "error" ? "error" : "waiting on you") : mode === "done" ? "finished" : (s.branch || "working"))
        title: !s ? "" : mode === "need" ? (s.status === "error" ? "It stopped with an error" : perm?.tool ? "Allow " + perm.tool + "?" : "Needs your answer")
                       : mode === "done" ? (root.firstLine(turn?.say || s.summary) || "Turn finished")
                       : (root.firstLine(s.lastPrompt) || "Working")
        big: !s || mode === "done" ? "" : Agents.hms(root.now - (s.since ?? root.now))
        bigAccent: mode === "need"
        quote: mode !== "need" ? "" : s.status === "error" ? String(s.error ?? "") : [perm?.desc, perm?.cmd].filter(x => !!x).join("\n")
        info: mode === "work" ? (Agents.lastAction(s) ? "● " + Agents.lastAction(s) : "") : mode === "done" && turn ? Agents.stat(turn) : ""
        rows: all.length < 2 ? [] : all.slice(0, 4).map(x => ({
            title: x.project || "Agent", sub: what(x) + " · " + Agents.hms(root.now - (x.since ?? root.now)),
            on: x.status !== "working", close: true, act: () => Agents.jump(x.id)
        }))
        actions: !s ? [] : mode === "need" ? (Agents.canAnswer(s)
                ? [{ label: "Approve", pri: true, close: true, act: () => Agents.answer(s.id, "allow") },
                   { label: "Deny", close: true, act: () => Agents.answer(s.id, "deny") },
                   { label: "Jump", close: true, act: () => Agents.jump(s.id) }]
                : [{ label: "Jump to agent", pri: true, close: true, act: () => Agents.jump(s.id) },
                   { label: "Agents", close: true, act: () => Agents.show(s.id) }])
            : mode === "done" ? ((turn?.nfiles ?? (turn?.files ?? []).length) > 0
                ? [{ label: "Open diff", pri: true, close: true, act: () => Agents.openDiff(s.id) },
                   { label: "Jump", close: true, act: () => Agents.jump(s.id) },
                   { label: "Dismiss", close: true, act: () => { Agents.dismiss(s.id); root.doneId = ""; } }]
                : [{ label: "Jump to agent", pri: true, close: true, act: () => Agents.jump(s.id) },
                   { label: "Dismiss", close: true, act: () => { Agents.dismiss(s.id); root.doneId = ""; } }])
            : [{ label: "Jump to agent", pri: true, close: true, act: () => Agents.jump(s.id) },
               { label: "Agents", close: true, act: () => Agents.show(s.id) }]
    }

    IslandEntry {
        id: timerE
        readonly property bool on: root.wants("timer") && (Countdown.active || Countdown.ringing)
        readonly property bool ring: on && !Countdown.active
        readonly property real d: Countdown.duration
        kind: "timer"
        live: on
        mode: !on ? "" : ring ? "ring" : Countdown.paused ? "paused" : "run"
        hot: ring
        glyph: "bell"
        tint: Theme.accent
        progress: on && Countdown.active ? 1 - Countdown.progress : -1        // time left
        text: !on ? "" : ring ? "Timer done" : Countdown.fmt(Countdown.left)
        textAccent: ring
        meta: !on ? "" : ring ? Countdown.label : Countdown.paused ? "Paused" : Countdown.label
        kicker: "Timer" + (on && Countdown.label !== "" ? " · " + Countdown.label : "")
        title: !on ? "" : ring ? "Time is up" : Countdown.paused ? "Paused"
             : (d > 0 && d % 60000 === 0 ? d / 60000 + " minute timer" : Countdown.fmt(d) + " timer")
        big: !on ? "" : ring ? "0:00" : Countdown.fmt(Countdown.left)
        bigLarge: true
        info: !on ? "" : Countdown.running ? "Ends at " + Qt.formatTime(new Date(Countdown.endsAt), "HH:mm")
                       : Countdown.paused ? Countdown.fmt(Countdown.left) + " left of " + Countdown.fmt(d) : "Done · " + Countdown.fmt(d)
        actions: ring ? [{ label: "Done", pri: true, close: true, act: () => Countdown.dismiss() },
                         { label: "Again", act: () => Countdown.again() }]
                      : [{ label: "+1 min", act: () => Countdown.add(60000) },
                         { label: Countdown.paused ? "Resume" : "Pause", pri: Countdown.paused, act: () => Countdown.togglePause() },
                         { label: "Cancel", close: true, act: () => Countdown.stop() }]
    }

    IslandEntry {
        id: dlE
        readonly property bool on: root.wants("download")
        readonly property bool moving: on && Downloads.live
        readonly property var done: on && !moving ? Downloads.done : null
        readonly property var list: moving ? Downloads.moving : []
        readonly property string name: list.length > 1 ? list.length + " downloads" : (list[0]?.final || "Downloading")
        function amount(b, r) { return Downloads.human(b) + (r > 1000 ? " · " + Downloads.human(r) + "/s" : ""); }
        kind: "download"
        live: moving || done !== null
        mode: done ? "done" : moving ? "run" : ""
        glyph: done ? "check" : "download"
        tint: done ? Theme.green : Theme.label
        text: done ? "Downloaded" : name
        meta: done ? done.name : moving ? Downloads.human(Downloads.bytes) : ""
        kicker: "Downloads" + (list.length > 1 ? " · " + list.length + " files" : "")
        title: done ? done.name : name
        big: done ? "" : moving ? Downloads.human(Downloads.bytes) : ""
        bigAccent: true
        info: done ? "Saved to " + Downloads.dir.replace(Quickshell.env("HOME"), "~")
                   : moving ? (Downloads.rate > 1000 ? Downloads.human(Downloads.rate) + "/s" : "Waiting for data") + " · the browser gives no total" : ""
        rows: list.length > 1 ? list.map(f => ({ title: f.final || f.name, sub: amount(f.bytes, f.rate) })) : []
        actions: done ? [{ label: "Open", pri: true, close: true, act: () => Downloads.openDone() },
                         { label: "Show in Files", close: true, act: () => Downloads.openFolder() }]
                      : [{ label: "Show in Files", pri: true, close: true, act: () => Downloads.openFolder() }]
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
        readonly property string artist: p?.trackArtist ?? ""
        kind: "music"
        live: p !== null
        mode: p ? (p.isPlaying ? "play" : "pause") : ""
        glyph: "note"
        art: p?.trackArtUrl ?? ""
        text: p ? (p.trackTitle || p.identity || "Playing") : ""
        kicker: p ? (p.identity || "Player") + " · " + (p.isPlaying ? "now playing" : "paused") : ""
        title: text + (artist ? " — " + artist : "")
        progress: p && p.length > 0 ? Math.max(0, Math.min(1, p.position / p.length)) : -1
        times: p && p.length > 0 ? [root.clockTime(p.position * 1000), root.clockTime(p.length * 1000)] : []
        actions: !p ? [] : [
            { label: "", icon: "prev", enabled: p.canGoPrevious, act: () => p.previous() },
            { label: "", icon: p.isPlaying ? "pause" : "play", pri: true, enabled: p.canTogglePlaying, act: () => p.togglePlaying() },
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
        readonly property int n: root.useShelf ? Shelf.count : 0
        kind: "shelf"
        live: got.length > 0
        glyph: "tray"
        text: n + (n === 1 ? " item parked" : " items parked")
        kicker: "Drop shelf · " + (got.length === 1 ? "1 just added" : got.length + " just added")
        title: text
        info: got.slice(0, 3).map(it => it.title || it.name || "").filter(x => x).join(" · ")
        actions: [{ label: "Open shelf", pri: true, close: true, act: () => Quickshell.execDetached(["nox", "shelf", "open"]) },
                  { label: "Dismiss", close: true, act: () => { root.shelfIds = []; } }]
    }

    // ---------------------------------------------------------------- what's shown
    readonly property var byKind: ({ recording: recE, mic: micE, agent: agentE, timer: timerE, download: dlE, music: musicE, shelf: shelfE })
    // hot things first, then widgets.island.order
    readonly property var live: {
        const l = order.map(k => byKind[k]).filter(e => !!e && e.live);
        return l.filter(e => e.hot).concat(l.filter(e => !e.hot));
    }
    property string pickKind: ""                  // chosen with a click / the wheel / a tab; "" = the top one
    // a pick holds until the top thing changes or 9 s pass; a hot top thing beats a pick
    readonly property IslandEntry current: {
        const h = live[0] ?? null, p = live.find(e => e.kind === pickKind) ?? null;
        return p && !(h && h.hot && h !== p) ? p : h;
    }
    readonly property string headKind: live[0]?.kind ?? ""
    onHeadKindChanged: pickKind = ""
    Timer { id: pickOff; interval: 9000; onTriggered: if (root.cardOpen) restart(); else root.pickKind = "" }
    function pick(k) { pickKind = k; pickOff.restart(); }
    function cycle(d) {
        if (live.length < 2) return;
        const i = Math.max(0, live.indexOf(current));
        pick(live[(i + d + live.length) % live.length].kind);
    }
    property IslandEntry shown: null              // what the pill draws (the front face)
    readonly property string shownKind: shown?.kind ?? ""
    readonly property var extras: live.filter(e => e !== shown)
    // which slot is in front (the other one is leaving or empty)
    property int front: 0
    Component.onCompleted: { swapTo(current); Qt.callLater(() => root.ready = true); }
    onCurrentChanged: if (current !== shown) swapTo(current)
    onLiveChanged: if (live.length === 0) hideCard()
    function swapTo(e) {
        if (!e) {
            // the last thing left: shrink + fade the pill out, keep its face until then
            if (shown && ready && onScreen) appear.out();
            else { slotA.entry = null; slotB.entry = null; }
            shown = null;
            return;
        }
        const f = front === 0 ? slotA : slotB, b = front === 0 ? slotB : slotA;
        const was = shown;
        shown = e;
        if (!ready || !onScreen) { f.entry = e; f.still(); b.entry = null; return; }
        if (!was) { f.entry = e; f.still(); b.entry = null; appear.show(); return; }
        b.entry = e;
        front = 1 - front;
        f.leave();
        b.enter();
        if (!cardOpen) bump.restart();
    }

    // ---------------------------------------------------------------- the pill
    // appear / vanish (mock: scale .6 + fade on the spring)
    property real appearScale: 1
    QtObject {
        id: appear
        property bool running: appearIn.running || appearOut.running
        function show() { appearOut.stop(); appearIn.restart(); }
        function out() { appearIn.stop(); appearOut.restart(); }
    }
    ParallelAnimation {
        id: appearIn
        NumberAnimation { target: root; property: "appearScale"; from: 0.6; to: 1; duration: 520; easing.type: Easing.OutBack; easing.overshoot: 1.3 }
        NumberAnimation { target: root; property: "opacity"; from: 0; to: 1; duration: Theme.durFade; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: appearOut
        NumberAnimation { target: root; property: "appearScale"; to: 0.6; duration: 260; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "opacity"; to: 0; duration: 220; easing.type: Easing.InCubic }
        onFinished: { root.appearScale = 1; root.opacity = 1; slotA.entry = null; slotB.entry = null; }
    }
    // bump when the top thing changes (mock islBump)
    property real bumpScale: 1
    SequentialAnimation {
        id: bump
        NumberAnimation { target: root; property: "bumpScale"; to: 1.07; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "bumpScale"; to: 1; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 2 }
    }
    scale: appearScale * bumpScale * (mouse.pressed ? 0.97 : 1)
    Behavior on scale { enabled: !bump.running && !appear.running; NumberAnimation { duration: Theme.durHover; easing.type: Easing.OutCubic } }

    readonly property bool live0: shown !== null || appearOut.running
    readonly property bool square: Theme.square
    readonly property real pillRadius: square ? 4 : height / 2

    // needs you: a pulsing accent ring around the pill (mock islNeed 1.6 s), only while collapsed
    readonly property bool pulsing: (shown?.hot ?? false) && !cardOpen && frame > 0
    readonly property real pulse: pulsing ? 0.5 - 0.5 * Math.cos(2 * Math.PI * ((frame * 83.33) % 1600) / 1600) : 0
    RectangularShadow {
        visible: root.pulsing
        anchors.fill: bg
        radius: bg.radius
        blur: 18
        spread: 0
        color: Theme.rgba(Theme.t.color.accent, 0.35 * root.pulse)
    }
    Rectangle {
        visible: root.pulsing
        anchors.fill: bg
        anchors.margins: -5 * root.pulse
        radius: root.square ? 4 + 5 * root.pulse : height / 2
        color: "transparent"
        border.width: 1.5
        border.color: Theme.rgba(Theme.t.color.accent, 0.45 * (1 - root.pulse))
    }
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: root.pillRadius
        color: root.live0 ? root.islandColor : Theme.white(mouse.containsMouse || root.idleActive ? 0.14 : 0)
        Behavior on color { ColorAnimation { duration: Theme.durFade } }
        border.width: root.live0 ? 1 : 0
        border.color: root.pulsing ? Theme.rgba(Theme.t.color.accent, 0.55 + 0.4 * root.pulse) : Theme.white(root.square ? 0.16 : 0.12)
    }
    readonly property string clockPopup: clockOpts.clickPopup ?? "notifications"
    readonly property bool idleActive: !live0 && clockPopup !== "" && Panels.popup === clockPopup
    Item {
        id: content
        anchors.fill: parent
        clip: true
        SystemClock { id: clock; precision: SystemClock.Minutes; enabled: !root.live0 && root.idleClock }
        Text {
            id: clockText
            visible: !root.live0
            anchors.centerIn: parent
            text: Qt.formatDateTime(clock.date, root.options.format ?? root.clockOpts.format ?? "ddd d MMM HH:mm")
            color: Theme.label
            font.features: ({ "tnum": 1 })
            font.family: root.mono ? Theme.fontLabel : Theme.fontUi
            font.pixelSize: root.mono ? 12 : Theme.fontSize
            font.weight: root.mono ? Font.Medium : Font.Normal
            font.capitalization: root.mono ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: root.mono ? 0.6 : 0
        }
        // two faces: the front one, and the one leaving (cross-fade with blur + scale)
        IslandSlot { id: slotA; z: root.front === 0 ? 1 : 0; pillH: root.pillH; maxText: root.maxText; frame: root.cardFull ? 0 : root.frame }
        IslandSlot { id: slotB; z: root.front === 1 ? 1 : 0; pillH: root.pillH; maxText: root.maxText; frame: root.cardFull ? 0 : root.frame }
        // right after the front face; the pill's springing edge (clip) reveals it (mock: overflow hidden)
        IslandOthers {
            id: others
            visible: count > 0 && root.shown !== null
            x: 10 + root.faceW + 3
            anchors.verticalCenter: parent.verticalCenter
            model: root.extras
            onPick: kind => { openTimer.stop(); root.pick(kind); }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real acc: 0
        onPressed: Panels.notePointer()
        onEntered: { closeTimer.stop(); if (root.shown && !root.cardOpen && Panels.popup === "") openTimer.restart(); }
        onExited: { openTimer.stop(); if (root.cardOpen && !root.pinned) closeTimer.restart(); }
        onClicked: m => {
            if (!root.shown || m.button === Qt.RightButton) {
                root.hideCard();
                if (root.clockPopup !== "" && Panels.exists(root.clockPopup)) Panels.toggle(root.clockPopup);
                return;
            }
            openTimer.stop();
            if (root.live.length > 1 && !root.cardOpen) { root.cycle(1); return; }
            root.openPinned();
        }
        onWheel: w => {
            acc += w.angleDelta.y;
            if (Math.abs(acc) < 120) return;
            root.cycle(acc > 0 ? -1 : 1);
            acc = 0;
        }
    }

    // ---------------------------------------------------------------- the card (the pill, grown)
    property bool cardOpen: false        // logically open (grows / shrinks on this)
    property bool cardMapped: false      // the popup exists (kept through the shrink)
    property bool pinned: false
    property bool cardHovered: false
    property real grow: 0                // 0 = the pill, 1 = the card (overshoots on the spring)
    readonly property bool cardFull: cardOpen && !growIn.running && cardMapped
    property real cardFade: 0            // the card's content
    property real faceFade: 1            // the pill face drawn on the popup
    property real cardH: 120             // the card's height (set by the popup's content)
    property point pillPos: Qt.point(0, 0)
    property real anchorX: 0
    Timer { id: openTimer; interval: root.options.hoverDelay ?? 140; onTriggered: if (mouse.containsMouse && Panels.popup === "") root.showCard(false) }
    Timer { id: closeTimer; interval: 380; onTriggered: if (!root.pinned && !mouse.containsMouse && !root.cardHovered) root.hideCard() }
    // the grown card's hover (IslandMorph)
    function cardHover(on) {
        cardHovered = on;
        if (on) closeTimer.stop(); else if (!pinned) closeTimer.restart();
    }
    function placeCard() {
        // the island's own transform (bump / press scale) stays out of it
        pillPos = root.parent ? root.parent.mapToItem(null, root.x, root.y) : Qt.point(0, 0);
        anchorX = Math.round(pillPos.x + width / 2 - (cardWidth + 88) / 2);
    }
    function showCard(pin) {
        if (!shown) return;
        closeTimer.stop();
        if (!cardMapped) placeCard();
        if (pin) pinned = true;
        // opened under the pointer: count it as hovered until the popup's own hover says otherwise
        cardHovered = !pin || cardHovered;
        if (cardOpen) return;
        cardMapped = true;
        cardOpen = true;
        bump.stop(); bumpScale = 1;
        shrink.stop();
        growIn.restart();
    }
    function openPinned() { if (cardOpen) { pinned ? hideCard() : (pinned = true); return; } Panels.close(); showCard(true); }
    function hideCard() {
        openTimer.stop(); closeTimer.stop();
        pinned = false;
        cardHovered = false;
        if (!cardOpen) return;
        cardOpen = false;
        growIn.stop();
        shrink.restart();
    }
    ParallelAnimation {
        id: growIn
        NumberAnimation { target: root; property: "grow"; to: 1; duration: 600; easing.type: Easing.OutBack; easing.overshoot: 1.1 }
        NumberAnimation { target: root; property: "faceFade"; to: 0; duration: 120; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 90 }
            NumberAnimation { target: root; property: "cardFade"; to: 1; duration: 240; easing.type: Easing.OutCubic }
        }
    }
    ParallelAnimation {
        id: shrink
        NumberAnimation { target: root; property: "grow"; to: 0; duration: 380; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "cardFade"; to: 0; duration: 120; easing.type: Easing.OutCubic }
        SequentialAnimation {
            PauseAnimation { duration: 160 }
            NumberAnimation { target: root; property: "faceFade"; to: 1; duration: 200; easing.type: Easing.OutCubic }
        }
        onFinished: if (!root.cardOpen) root.cardMapped = false
    }
    onWidthChanged: if (cardMapped) placeCard()
    // another popup (a bar button, a shortcut) takes over
    Connections { target: Panels; function onPopupChanged() { if (Panels.popup !== "") root.hideCard(); } }

    LazyLoader {
        active: root.cardMapped && root.popupCard
        PopupWindow {
            id: pop
            readonly property real pad: 44
            anchor.window: root.QsWindow.window
            anchor.rect.x: root.anchorX
            anchor.rect.y: 0
            implicitWidth: root.cardWidth + pad * 2
            implicitHeight: Math.ceil(root.pillPos.y + Math.max(root.cardH, root.pillH) * 1.12 + pad)
            visible: true
            color: "transparent"
            mask: Region { item: morphView.box }

            // pinned: a click anywhere else closes it (bar windows stay usable)
            HyprlandFocusGrab {
                active: root.pinned
                windows: [pop].concat(Panels.barWindows)
                onCleared: root.hideCard()
            }
            IslandMorph {
                id: morphView
                island: root
                x: 0; y: 0
                width: pop.width; height: pop.height
            }
        }
    }
}

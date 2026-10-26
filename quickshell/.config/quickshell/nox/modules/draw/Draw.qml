pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services

// Draw on the screen (Super+A): a pointer, pens and shapes over everything, for screen shares,
// huddles and recordings. One full-screen overlay (namespace nox:draw, Overlay layer) on the screen
// that was focused when it came on, with the floating toolbox (DrawToolbox, styled like the voice
// pill; drag it by its left end). Annotations are ordinary pixels on screen, so a shared screen or
// a recording shows them.
//   pointer   a glowing dot with a short comet tail instead of the cursor; hold the button to
//             draw ink that stays a moment (draw.pointerSeconds, 2.5) and fades (Slack huddle style)
//   pen / arrow / box / circle   with FADE on (default) they fade out slowly draw.fadeSeconds (4)
//             after the last stroke: drawing again restarts the wait for all of them (and brings
//             back any that were already fading); FADE off = they stay. Shift = straight line /
//             square / circle
//   marker    never fades: only undo or clear take it away
//   spotlight dims the screen except a circle round the pointer (scroll = size); ink still draws
//   hand      clicks go to the apps again, the drawings stay (only the toolbox takes input)
// Keys while drawing (the overlay has the keyboard; the hand gives it back):
//   1-8 tools   Tab hand / back   C next colour   F fade   Ctrl+Z / Z undo   Backspace / Delete clear
//   S screenshot (toolbox hidden, `nox shot screen`)   Esc / Super+A off (everything fades away)
//   qs -c nox ipc call draw toggle | on [tool] | off | tool <name> | undo | clear | status   (`nox draw`)
// Strokes live in a ListModel (delegates keep their own fade timers) with their points in
// pathStore; the stroke being drawn is a separate live shape until the button comes up.
Scope {
    id: root
    readonly property var opts: Config.opt.draw ?? ({})

    readonly property var tools: [
        { id: "pointer", name: "Pointer", icon: "stylus_laser_pointer" },
        { id: "pen", name: "Pen", icon: "stylus" },
        { id: "marker", name: "Marker", icon: "ink_highlighter" },
        { id: "arrow", name: "Arrow", icon: "arrow_outward" },
        { id: "box", name: "Box", icon: "rectangle" },
        { id: "circle", name: "Circle", icon: "radio_button_unchecked" },
        { id: "spot", name: "Spotlight", icon: "flashlight_on" },
        { id: "hand", name: "Hand", icon: "arrow_selector_tool" }
    ]
    // "accent" = the theme accent
    readonly property var palette: opts.colors ?? ["accent", "#f4f4f2", "#ffd23f", "#3ddcff", "#5cf28a"]
    function colorAt(i) { const c = palette[i % palette.length]; return c === "accent" ? Theme.accent : c; }

    property bool active: false        // drawing mode on
    property bool shown: false         // overlay mapped (stays a moment after off for the fade-out)
    property string tool: opts.tool ?? "pointer"
    property string lastTool: "pointer"    // what Tab / the hand goes back to
    property int colorIx: 0
    readonly property color ink: colorAt(colorIx)
    property bool fade: opts.fade ?? true
    readonly property int fadeMs: Math.round((opts.fadeSeconds ?? 4) * 1000)
    readonly property int pointerMs: Math.round((opts.pointerSeconds ?? 2.5) * 1000)
    readonly property int fadeOutMs: Math.round((opts.fadeOutSeconds ?? 1.6) * 1000)
    property string screenName: ""
    property bool capturing: false     // toolbox hidden for a screenshot
    readonly property bool hand: tool === "hand"

    function focusedScreen() { return Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? ""; }
    function on(t) {
        if (!active) { screenName = focusedScreen(); }
        if (t && tools.some(x => x.id === t)) setTool(t);
        killTimer.stop();
        active = true;
        shown = true;
    }
    function off() {
        if (!active) return;
        active = false;
        clear();
        killTimer.restart();
    }
    function toggle() { if (active) off(); else on(); }
    function setTool(t) {
        if (!tools.some(x => x.id === t)) return;
        if (t !== "hand") lastTool = t;
        tool = t;
    }
    function toggleHand() { setTool(hand ? lastTool : "hand"); }
    function nextColor(d) { colorIx = (colorIx + (d ?? 1) + palette.length) % palette.length; }
    Timer { id: killTimer; interval: 420; onTriggered: if (!root.active) root.shown = false }

    // ---- strokes ----
    ListModel { id: strokes }
    property var pathStore: ({})        // sid -> [[Qt.point, ...], ...] (PathMultiline paths)
    property int seq: 0
    property int clearGen: 0            // bumped by clear(): every stroke fades out
    // bumped when a stroke starts and when it lands: every fading stroke waits its full time
    // again from there (and one that was already fading comes back)
    property int inkGen: 0
    readonly property int count: strokes.count
    // width / opacity / glow per tool
    function style(t) {
        if (t === "marker") return { w: opts.markerWidth ?? 20, a: 0.36, glow: false };
        if (t === "pointer" || t === "spot") return { w: 4.5, a: 1, glow: true };
        return { w: opts.penWidth ?? 4, a: 1, glow: false };
    }
    function commit(paths, t) {
        if (!paths.length || !paths[0].length) return;
        const st = style(t);
        const sid = ++seq;
        const ps = Object.assign({}, pathStore);
        ps[sid] = paths;
        pathStore = ps;
        const pointerInk = t === "pointer" || t === "spot";
        strokes.append({ sid, tool: t, col: String(ink), w: st.w, alpha: st.a, glow: st.glow,
                         fadeAfter: pointerInk ? pointerMs : t === "marker" || !fade ? 0 : fadeMs });
        inkGen++;
    }
    function drop(sid) {
        for (let i = 0; i < strokes.count; i++) if (strokes.get(i).sid === sid) { strokes.remove(i); break; }
        const ps = Object.assign({}, pathStore);
        delete ps[sid];
        pathStore = ps;
    }
    function undo() { if (strokes.count) drop(strokes.get(strokes.count - 1).sid); }
    function clear() { if (strokes.count) clearGen++; }

    // ---- shape geometry (paths for PathMultiline) ----
    function arrowPaths(a, b, w) {
        const dx = b.x - a.x, dy = b.y - a.y, len = Math.hypot(dx, dy);
        if (len < 2) return [[a, b]];
        const ux = dx / len, uy = dy / len, head = Math.min(len * 0.45, 16 + w * 3), sp = 0.48;
        const h1 = Qt.point(b.x - head * (ux * Math.cos(sp) - uy * Math.sin(sp)), b.y - head * (uy * Math.cos(sp) + ux * Math.sin(sp)));
        const h2 = Qt.point(b.x - head * (ux * Math.cos(sp) + uy * Math.sin(sp)), b.y - head * (uy * Math.cos(sp) - ux * Math.sin(sp)));
        return [[a, b], [h1, b, h2]];
    }
    function boxPaths(a, b, square) {
        let x1 = b.x, y1 = b.y;
        if (square) { const s = Math.max(Math.abs(b.x - a.x), Math.abs(b.y - a.y)); x1 = a.x + s * Math.sign(b.x - a.x || 1); y1 = a.y + s * Math.sign(b.y - a.y || 1); }
        // rounded corners (8 px or less on a small box)
        const l = Math.min(a.x, x1), r = Math.max(a.x, x1), t = Math.min(a.y, y1), bt = Math.max(a.y, y1);
        const rr = Math.min(8, (r - l) / 2, (bt - t) / 2);
        const pts = [];
        const arc = (cx, cy, a0) => { for (let i = 0; i <= 4; i++) { const an = a0 + i * Math.PI / 8; pts.push(Qt.point(cx + rr * Math.cos(an), cy + rr * Math.sin(an))); } };
        arc(r - rr, t + rr, -Math.PI / 2); arc(r - rr, bt - rr, 0); arc(l + rr, bt - rr, Math.PI / 2); arc(l + rr, t + rr, Math.PI);
        pts.push(pts[0]);
        return [pts];
    }
    function circlePaths(a, b, round) {
        let rx = Math.abs(b.x - a.x) / 2, ry = Math.abs(b.y - a.y) / 2;
        if (round) rx = ry = Math.max(rx, ry);
        const cx = a.x + rx * Math.sign(b.x - a.x || 1), cy = a.y + ry * Math.sign(b.y - a.y || 1);
        const pts = [];
        for (let i = 0; i <= 72; i++) { const an = i / 72 * Math.PI * 2; pts.push(Qt.point(cx + rx * Math.cos(an), cy + ry * Math.sin(an))); }
        return [pts];
    }

    function status() {
        return "active=" + active + " tool=" + tool + " color=" + palette[colorIx] + " fade=" + fade
            + " strokes=" + strokes.count + " screen=" + screenName;
    }
    IpcHandler {
        target: "draw"
        function toggle(): void { root.toggle(); }
        function on(tool: string): void { root.on(tool); }
        function off(): void { root.off(); }
        function tool(name: string): void { root.on(name); }
        function undo(): void { root.undo(); }
        function clear(): void { root.clear(); }
        function status(): string { return root.status(); }
    }
    LazyLoader {
        active: !Quickshell.env("NOX_LINT")
        component: GlobalShortcut {
            appid: "nox"; name: "drawToggle"; description: "Draw on screen: on / off"
            onPressed: root.toggle()
        }
    }

    // screenshot of the screen with the drawings (toolbox out of the way first)
    function capture() {
        capturing = true;
        captureTimer.restart();
    }
    Timer {
        id: captureTimer
        interval: 160
        onTriggered: { Quickshell.execDetached(["nox", "shot", "screen"]); restoreTimer.restart(); }
    }
    Timer { id: restoreTimer; interval: 700; onTriggered: root.capturing = false }

    LazyLoader {
        active: root.shown
        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "nox:draw"
            WlrLayershell.layer: WlrLayer.Overlay
            // the keyboard while drawing (tool keys, Esc); the hand gives it back to the apps
            WlrLayershell.keyboardFocus: root.active && !root.hand ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }
            // hand / off: only the toolbox takes input; drawing: the whole screen
            mask: Region {
                item: root.active && !root.hand ? stage : toolbox
            }

            Item {
                id: stage
                anchors.fill: parent
                focus: true
                opacity: root.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 380; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

                Keys.onPressed: e => {
                    const ctrl = e.modifiers & Qt.ControlModifier, shift = e.modifiers & Qt.ShiftModifier;
                    if (e.key === Qt.Key_Escape) root.off();
                    else if (e.key >= Qt.Key_1 && e.key <= Qt.Key_8 && !ctrl) root.setTool(root.tools[e.key - Qt.Key_1].id);
                    else if (e.key === Qt.Key_Tab) root.toggleHand();
                    else if (e.key === Qt.Key_Z && (ctrl || !shift)) root.undo();
                    else if (e.key === Qt.Key_C && !ctrl) root.nextColor(shift ? -1 : 1);
                    else if (e.key === Qt.Key_F && !ctrl) root.fade = !root.fade;
                    else if (e.key === Qt.Key_Backspace || e.key === Qt.Key_Delete) root.clear();
                    else if (e.key === Qt.Key_S && !ctrl) root.capture();
                    else return;
                    e.accepted = true;
                }

                // ---- spotlight: the screen dimmed except a soft circle round the pointer ----
                Item {
                    id: spot
                    anchors.fill: parent
                    property real r: root.opts.spotRadius ?? 150
                    opacity: root.tool === "spot" && root.active ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: Qt.rgba(0, 0, 0, 0.62)
                            strokeColor: "transparent"
                            fillRule: ShapePath.OddEvenFill
                            startX: 0; startY: 0
                            PathLine { x: spot.width; y: 0 }
                            PathLine { x: spot.width; y: spot.height }
                            PathLine { x: 0; y: spot.height }
                            PathLine { x: 0; y: 0 }
                            PathMove { x: pointer.px + spot.r; y: pointer.py }
                            PathArc { x: pointer.px - spot.r; y: pointer.py; radiusX: spot.r; radiusY: spot.r }
                            PathArc { x: pointer.px + spot.r; y: pointer.py; radiusX: spot.r; radiusY: spot.r }
                        }
                    }
                    // the rim of the light
                    Rectangle {
                        x: pointer.px - spot.r; y: pointer.py - spot.r
                        width: spot.r * 2; height: width; radius: spot.r
                        color: "transparent"
                        border.width: 1.5
                        border.color: Qt.alpha(root.ink, 0.55)
                    }
                    Behavior on r { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                }

                // ---- committed strokes ----
                Repeater {
                    model: strokes
                    Item {
                        id: st
                        required property int sid
                        required property string tool
                        required property string col
                        required property real w
                        required property real alpha
                        required property bool glow
                        required property int fadeAfter
                        anchors.fill: parent
                        readonly property var paths: root.pathStore[sid] ?? []
                        property bool leaving: false
                        // a stroke "lands": a touch thicker, then settles (and a glow that breathes in)
                        property real land: 1
                        Component.onCompleted: { landAnim.start(); if (fadeAfter > 0) fadeTimer.start(); }
                        NumberAnimation { id: landAnim; target: st; property: "land"; from: 1.35; to: 1; duration: 260; easing.type: Easing.OutCubic }
                        // a slow fade (draw.fadeOutSeconds, 1.6) once the wait is over
                        // (not while a stroke is being drawn: the wait starts again when it lands)
                        Timer { id: fadeTimer; interval: st.fadeAfter; onTriggered: if (live.drawing) restart(); else st.leave(root.fadeOutMs, false) }
                        property bool cleared: false
                        function leave(ms, clearing) {
                            if (cleared) return;
                            if (clearing) { cleared = true; backAnim.stop(); outAnim.stop(); }
                            else if (leaving) return;
                            leaving = true;
                            outAnim.duration = ms;
                            outAnim.start();
                        }
                        NumberAnimation { id: outAnim; target: st; property: "opacity"; to: 0; easing.type: Easing.InOutSine; onFinished: root.drop(st.sid) }
                        NumberAnimation { id: backAnim; target: st; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutCubic }
                        Connections {
                            target: root
                            function onClearGenChanged() { st.leave(280, true); }
                            // drawing again: wait the whole time again, fading ones come back
                            function onInkGenChanged() {
                                if (st.fadeAfter <= 0 || st.cleared) return;
                                if (st.leaving) { outAnim.stop(); st.leaving = false; backAnim.start(); }
                                fadeTimer.restart();
                            }
                        }
                        DrawStroke { paths: st.paths; color: st.col; lineWidth: st.w * st.land; alpha: st.alpha; glow: st.glow }
                    }
                }

                // ---- the stroke being drawn ----
                DrawStroke {
                    id: live
                    property bool drawing: false
                    paths: []
                    color: root.ink
                    readonly property var stl: root.style(root.tool)
                    lineWidth: stl.w
                    alpha: stl.a
                    glow: stl.glow
                    visible: drawing
                }

                // ---- input ----
                MouseArea {
                    id: pad
                    anchors.fill: parent
                    enabled: root.active && !root.hand
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: root.tool === "pointer" || root.tool === "spot" ? Qt.BlankCursor : Qt.CrossCursor
                    property point a
                    property var pts: []
                    // the stroke being drawn, as plain JS arrays: read back from the shape's
                    // property it comes out as a Qt list (no .flat, .map, ...), so this is the copy
                    property var cur: []
                    function show(paths) { cur = paths; live.paths = paths; }
                    onPressed: m => {
                        // right click = undo while drawing
                        if (m.button === Qt.RightButton) { root.undo(); return; }
                        a = Qt.point(m.x, m.y);
                        root.inkGen++;
                        pts = [a];
                        show([[a, a]]);
                        live.drawing = true;
                    }
                    onPositionChanged: m => {
                        pointer.moveTo(m.x, m.y);
                        if (!live.drawing) return;
                        const p = Qt.point(m.x, m.y), shift = m.modifiers & Qt.ShiftModifier;
                        const t = root.tool;
                        if (t === "arrow") show(root.arrowPaths(a, shift ? straight(a, p) : p, live.lineWidth));
                        else if (t === "box") show(root.boxPaths(a, p, shift));
                        else if (t === "circle") show(root.circlePaths(a, p, shift));
                        else if (shift && t !== "pointer") show([[a, straight(a, p)]]);
                        else {
                            // freehand: skip jitter, smooth towards the pointer
                            const last = pts[pts.length - 1];
                            if (Math.hypot(p.x - last.x, p.y - last.y) < 1.6) return;
                            const q = Qt.point(last.x + (p.x - last.x) * 0.55, last.y + (p.y - last.y) * 0.55);
                            pts = pts.concat([q]);
                            show([pts.concat([p])]);
                        }
                    }
                    onReleased: m => {
                        if (!live.drawing) return;
                        live.drawing = false;
                        // plain arrays of points whatever the property handed back
                        const out = Array.from(cur, path => Array.from(path, q => Qt.point(q.x, q.y)));
                        show([]);
                        // a click without a drag leaves a dot (pen / pointer), not an empty shape
                        let span = 0;
                        for (const path of out) for (const q of path) span = Math.max(span, Math.hypot(q.x - a.x, q.y - a.y));
                        if (span < 3 && ["arrow", "box", "circle"].includes(root.tool)) return;
                        root.commit(span < 3 ? [[a, Qt.point(a.x + 0.1, a.y + 0.1)]] : out, root.tool);
                    }
                    onCanceled: { live.drawing = false; show([]); }
                    onWheel: w => {
                        if (root.tool === "spot") spot.r = Math.max(60, Math.min(520, spot.r + (w.angleDelta.y > 0 ? 18 : -18)));
                        else if (w.angleDelta.y !== 0) root.nextColor(w.angleDelta.y > 0 ? -1 : 1);
                    }
                    // 0 / 45 / 90 degree line
                    function straight(a, p) {
                        const dx = p.x - a.x, dy = p.y - a.y, an = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4), len = Math.hypot(dx, dy);
                        return Qt.point(a.x + len * Math.cos(an), a.y + len * Math.sin(an));
                    }
                }

                // ---- pointer: glowing dot + comet tail (pointer and spotlight tools) ----
                Item {
                    id: pointer
                    anchors.fill: parent
                    property real px: -100
                    property real py: -100
                    property var trail: []          // [{ x, y, t }] newest last
                    readonly property bool on: root.active && (root.tool === "pointer" || root.tool === "spot") && pad.containsMouse
                    opacity: on ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
                    function moveTo(x, y) {
                        px = x; py = y;
                        if (!on) return;
                        trail = trail.concat([{ x, y, t: Date.now() }]).slice(-48);
                        if (!tick.running) tick.start();
                    }
                    // drops the tail's old end every frame; stops when the tail is gone
                    Timer {
                        id: tick
                        interval: 16; repeat: true
                        onTriggered: {
                            const now = Date.now();
                            const t = pointer.trail.filter(q => now - q.t < 260);
                            pointer.trail = t;
                            if (!t.length) stop();
                        }
                    }
                    // tail: segments from old (thin, faint) to new (thick)
                    Repeater {
                        model: 6
                        Shape {
                            id: seg
                            required property int index
                            anchors.fill: parent
                            preferredRendererType: Shape.CurveRenderer
                            readonly property var tr: pointer.trail
                            readonly property int n: tr.length
                            readonly property int from: Math.floor(n * index / 6)
                            readonly property int to: Math.min(n, Math.floor(n * (index + 1) / 6) + 1)
                            readonly property var pts: tr.slice(from, to).map(q => Qt.point(q.x, q.y))
                            visible: pts.length > 1
                            ShapePath {
                                strokeColor: Qt.alpha(root.ink, 0.12 + 0.6 * (seg.index + 1) / 6)
                                strokeWidth: 1.5 + 6.5 * (seg.index + 1) / 6
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                joinStyle: ShapePath.RoundJoin
                                PathPolyline { path: seg.pts }
                            }
                        }
                    }
                    // the dot: glow, ring, core
                    Item {
                        x: pointer.px - 14; y: pointer.py - 14
                        width: 28; height: 28
                        RectangularShadow {
                            anchors.centerIn: parent
                            width: 14; height: 14; radius: 7
                            blur: 18; spread: 2
                            color: Qt.alpha(root.ink, 0.85)
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 22; height: 22; radius: 11
                            color: "transparent"
                            border.width: 1.5
                            border.color: Qt.alpha(root.ink, pad.pressed ? 0.9 : 0.45)
                            scale: pad.pressed ? 0.8 : 1
                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        Rectangle {
                            anchors.centerIn: parent
                            width: 10; height: 10; radius: 5
                            color: root.ink
                            border.width: 1.5
                            border.color: Qt.rgba(1, 1, 1, 0.85)
                        }
                    }
                }
                // pen-type tools: a small dot of the ink under the cross cursor
                Rectangle {
                    readonly property bool on: root.active && !root.hand && root.tool !== "pointer" && root.tool !== "spot" && pad.containsMouse && !pad.pressed
                    x: pointer.px - width / 2; y: pointer.py - height / 2
                    width: Math.max(6, root.style(root.tool).w); height: width; radius: width / 2
                    color: Qt.alpha(root.ink, root.tool === "marker" ? 0.4 : 0.9)
                    opacity: on ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
                }
            }

            // ---- toolbox (bottom centre to start; drag it by its left end) ----
            DrawToolbox {
                id: toolbox
                ctl: root
                property bool placed: false
                property real ox: 0
                property real oy: 0
                x: placed ? ox : Math.round((win.width - width) / 2)
                y: (placed ? oy : win.height - height - (root.opts.offset ?? 104)) + (root.active && !root.capturing ? 0 : 16)
                opacity: root.active && !root.capturing ? 1 : 0
                scale: root.active ? 1 : 0.96
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on scale { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                onDragBy: (dx, dy) => {
                    if (!placed) { ox = x; oy = y - (root.active ? 0 : 16); placed = true; }
                    ox = Math.max(8, Math.min(win.width - width - 8, ox + dx));
                    oy = Math.max(8, Math.min(win.height - height - 8, oy + dy));
                }
            }
            Connections {
                target: root
                // a fresh session starts at the bottom centre again
                function onActiveChanged() { if (root.active) toolbox.placed = false; }
            }
        }
    }
}

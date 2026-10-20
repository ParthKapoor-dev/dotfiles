pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.core
import qs.components

// Circle to Ask, the overlay (mock 23b #ask): the frozen frame zooms in 1.6% under a dim + grain,
// a hint pill asks for a circle; the freehand loop glows red while drawn, then the outside dims more,
// marching ants run along it, a scan sweeps through it and an "OCR · N lines" tag lands; the answer
// card sits beside the loop on a leader line. A straight drag = rectangle, a click = that window.
// Pure UI: what to ask and what came back is the session's (AskSession); the frame is a file.
Item {
    id: stage
    required property var session
    property string frame: ""             // frozen monitor (png, physical pixels)
    property bool open: false             // in / out motion
    property var windowAt: null           // function(x, y) -> { x, y, w, h, app, title } | null (unzoomed stage coords)
    signal selected(var box, string geom, var win)
    signal closeRequested()

    // mock durations (default look) scale with the look's motion tokens (Telemetry ~0.75x)
    readonly property real k: Theme.durSheet / 320
    readonly property real zoomTo: 1.016
    readonly property real barH: Config.moduleEnabled("bar") ? Theme.barHeight : 0
    readonly property bool ready: img.status === Image.Ready
    readonly property bool on: open && ready
    property string mode: "idle"          // idle | drawing | selected
    property var pts: []
    property var box: null                // selection bounds (stage coords)
    property string pathD: ""             // the loop (open while drawing, closed once selected)
    property string cardSide: "r"
    property bool cardIn: false
    readonly property string fullD: "M0 0H" + width + "V" + height + "H0Z"

    function nf(v) { return v.toFixed(1); }
    function smoothD(p, close) {
        if (p.length < 2) return "";
        let d = "M" + nf(p[0].x) + " " + nf(p[0].y);
        for (let i = 1; i < p.length - 1; i++) {
            const a = p[i], b = p[i + 1];
            d += " Q" + nf(a.x) + " " + nf(a.y) + " " + nf((a.x + b.x) / 2) + " " + nf((a.y + b.y) / 2);
        }
        const l = p[p.length - 1];
        d += " L" + nf(l.x) + " " + nf(l.y);
        return close ? d + "Z" : d;
    }
    function rectD(r) { return "M" + nf(r.x) + " " + nf(r.y) + "H" + nf(r.x + r.w) + "V" + nf(r.y + r.h) + "H" + nf(r.x) + "Z"; }

    // stage point <-> frame: the frame is zoomed about the centre; the frame has physical pixels
    function unzoom(x, y) {
        const z = desk.scale, cx = width / 2, cy = height / 2;
        return { x: cx + (x - cx) / z, y: cy + (y - cy) / z };
    }
    function zoomed(x, y) {
        const z = desk.scale, cx = width / 2, cy = height / 2;
        return { x: cx + (x - cx) * z, y: cy + (y - cy) * z };
    }
    function geomOf(b) {
        const a = unzoom(b.x, b.y), c = unzoom(b.x + b.w, b.y + b.h);
        const fx = img.sourceSize.width / width, fy = img.sourceSize.height / height;
        const x = Math.max(0, Math.floor(a.x * fx)), y = Math.max(0, Math.floor(a.y * fy));
        const x2 = Math.min(img.sourceSize.width, Math.ceil(c.x * fx)), y2 = Math.min(img.sourceSize.height, Math.ceil(c.y * fy));
        return Math.max(1, x2 - x) + "x" + Math.max(1, y2 - y) + "+" + x + "+" + y;
    }

    // ---- drawing ----
    function begin(p) {
        forceActiveFocus();          // the card (and its input) hides: Esc must still close
        cardIn = false;
        tag.shown = false;
        leadShape.drawn = 0;
        mode = "drawing";
        pts = [p];
        pathD = "";
    }
    function extend(p) {
        const l = pts[pts.length - 1];
        if (Math.hypot(p.x - l.x, p.y - l.y) < 3) return;
        pts.push(p);
        pathD = smoothD(pts, false);
    }
    function finish(p) {
        const xs = pts.map(q => q.x), ys = pts.map(q => q.y);
        const b = { x: Math.min(...xs), y: Math.min(...ys) };
        b.w = Math.max(...xs) - b.x; b.h = Math.max(...ys) - b.y;
        if (pts.length < 6 || b.w < 28 || b.h < 18) {
            // a click: the window under it
            const u = unzoom(p.x, p.y);
            const w = windowAt ? windowAt(u.x, u.y) : null;
            if (w) { selectWindow(w); return; }
            mode = "idle"; box = null; pts = []; pathD = "";
            return;
        }
        // a straight drag (path ~ its chord) = the rectangle between its ends
        let len = 0;
        for (let i = 1; i < pts.length; i++) len += Math.hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y);
        const a = pts[0], z = pts[pts.length - 1];
        const chord = Math.hypot(z.x - a.x, z.y - a.y);
        if (chord > 40 && len < chord * 1.35) {
            const r = { x: Math.min(a.x, z.x), y: Math.min(a.y, z.y), w: Math.abs(z.x - a.x), h: Math.abs(z.y - a.y) };
            if (r.w >= 16 && r.h >= 12) { select(r, rectD(r)); return; }
        }
        select({ x: b.x - 4, y: b.y - 4, w: b.w + 8, h: b.h + 8 }, smoothD(pts, true));
    }
    function selectWindow(w) {
        const a = zoomed(w.x, w.y), c = zoomed(w.x + w.w, w.y + w.h);
        const r = { x: Math.max(1, a.x), y: Math.max(1, a.y) };
        r.w = Math.min(width - 1, c.x) - r.x; r.h = Math.min(height - 1, c.y) - r.y;
        select(r, rectD(r), w);
    }
    // IPC / tests: a hand-drawn loop around a rect (like the mock's demo), animated
    function lassoAround(r) {
        const cx = r.x + r.w / 2, cy = r.y + r.h / 2, rx = r.w / 2 * 1.12 + 22, ry = r.h / 2 * 1.28 + 16;
        const out = [], M = 120, ph = Math.random() * 6, a0 = -Math.PI * 0.86, sweep = Math.PI * 2 + 0.55;
        const sq = v => Math.sign(v) * Math.pow(Math.abs(v), 0.72);
        for (let i = 0; i <= M; i++) {
            const t = i / M, ang = a0 + t * sweep;
            const wob = 1 + 0.03 * Math.sin(3 * ang + ph) + 0.016 * Math.sin(7 * ang + ph * 2), grow = 0.985 + 0.06 * t;
            const c = Math.cos(ang), s = Math.sin(ang);
            out.push({ x: cx + rx * wob * grow * sq(c), y: cy + ry * wob * grow * sq(s) * (1 + 0.04 * s) });
        }
        demo.pts = out; demo.i = 1;
        begin(out[0]);
        demo.restart();
    }
    Timer {
        id: demo
        property var pts: []
        property int i: 1
        interval: 10; repeat: true
        onTriggered: {
            i = Math.min(pts.length, i + 2);
            stage.pts = pts.slice(0, i);
            stage.pathD = stage.smoothD(stage.pts, false);
            if (i >= pts.length) { stop(); stage.finish(pts[pts.length - 1]); }
        }
    }

    function select(b, d, win) {
        mode = "selected";
        box = b;
        pathD = d;
        cardSide = place();
        scan.run();
        tagIn.restart();
        cardTimer.restart();
        // the window under the loop's centre names the card ("GHOSTTY · PNPM DEV")
        const c = unzoom(b.x + b.w / 2, b.y + b.h / 2);
        stage.selected(b, geomOf(b), win ?? (windowAt ? windowAt(c.x, c.y) : null));
    }
    Timer { id: tagIn; interval: 220 * stage.k; onTriggered: tag.shown = true }
    Timer { id: cardTimer; interval: 420 * stage.k; onTriggered: { stage.cardIn = true; leadShape.drawn = 1; card.focusInput(); } }

    // card beside the loop (mock Ask.place): right, else left, else under / over
    readonly property real cardW: 392
    function place() {
        const b = box, W = cardW, gap = 34, top = barH + 14;
        let side = "r", x = b.x + b.w + gap;
        if (x + W > width - 14) { side = "l"; x = b.x - gap - W; }
        if (x < 14) { side = "b"; x = Math.max(14, Math.min(b.x + b.w / 2 - W / 2, width - W - 14)); }
        let y = side === "b" ? b.y + b.h + gap : Math.max(top, Math.min(b.y - 8, height - 300));
        if (side === "b" && y > height - 260) { side = "t"; y = top; }
        cardX = x; cardBaseY = y;
        return side;
    }
    property real cardX: 0
    property real cardBaseY: 0
    // beside the loop the card rises as the answer grows, so it stays on screen without scrolling
    readonly property real cardTop: barH + 14
    readonly property bool cardSlides: cardSide === "r" || cardSide === "l"
    readonly property real cardY: cardSlides ? Math.max(cardTop, Math.min(cardBaseY, height - 14 - card.height)) : cardBaseY

    Keys.onEscapePressed: stage.closeRequested()
    focus: true

    // ---- the frozen desktop ----
    Item {
        id: desk
        anchors.fill: parent
        scale: stage.on ? stage.zoomTo : 1
        Behavior on scale { NumberAnimation { duration: 700 * stage.k; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        Image {
            id: img
            anchors.fill: parent
            source: stage.frame !== "" ? "file://" + stage.frame : ""
            asynchronous: true
            cache: false
            smooth: true
            mipmap: false
        }
    }
    // film grain over the frozen frame (mock .cx-gw .55)
    Image {
        anchors.fill: parent
        source: "../../assets/grain.png"
        fillMode: Image.Tile
        smooth: false
        opacity: stage.on ? 0.35 : 0
        Behavior on opacity { NumberAnimation { duration: 500 * stage.k; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    }
    // dim, with the loop cut out once selected
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        opacity: !stage.on ? 0 : stage.mode === "selected" ? 0.68 : 0.4
        Behavior on opacity { NumberAnimation { duration: 520 * stage.k; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        ShapePath {
            fillColor: "black"
            strokeWidth: -1
            fillRule: ShapePath.OddEvenFill
            PathSvg { path: stage.fullD + (stage.mode === "selected" ? " " + stage.pathD : "") }
        }
    }
    // inside the loop: accent tint + the scan sweep
    Shape {
        id: inside
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        visible: stage.mode === "selected"
        opacity: stage.on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        ShapePath {
            fillColor: Theme.rgba(Theme.t.color.accent, 0.06)
            strokeWidth: -1
            PathSvg { path: stage.mode === "selected" ? stage.pathD : "" }
        }
        ShapePath {
            strokeWidth: -1
            fillGradient: LinearGradient {
                x1: 0; y1: scan.y0
                x2: 0; y2: scan.y0 + 120
                GradientStop { position: 0; color: Theme.rgba(Theme.t.color.accent, 0) }
                GradientStop { position: 0.82; color: Theme.rgba(Theme.t.color.accent, 0.28 * scan.a) }
                GradientStop { position: 0.995; color: Qt.rgba(1, 1, 1, 0.7 * scan.a) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
            }
            PathSvg { path: stage.mode === "selected" && scan.a > 0 ? stage.pathD : "" }
        }
    }
    QtObject {
        id: scan
        property real y0: -200
        property real a: 0
        function run() {
            if (!stage.box) return;
            sweep.stop();
            yAnim.from = stage.box.y - 120; yAnim.to = stage.box.y + stage.box.h;
            sweep.start();
        }
    }
    ParallelAnimation {
        id: sweep
        NumberAnimation { id: yAnim; target: scan; property: "y0"; duration: 820 * stage.k; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.32, 0.72, 0, 1, 1, 1] }
        SequentialAnimation {
            PropertyAction { target: scan; property: "a"; value: 1 }
            PauseAnimation { duration: 620 * stage.k }
            NumberAnimation { target: scan; property: "a"; to: 0; duration: 200 * stage.k }
        }
    }

    // ---- the loop: blurred glow, the line, marching ants ----
    Shape {
        id: glow
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        visible: stage.pathD !== ""
        // blurred at half resolution: the blur hides it and it costs a quarter
        layer.enabled: true
        layer.textureSize: Qt.size(Math.ceil(width / 2), Math.ceil(height / 2))
        layer.smooth: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 12; autoPaddingEnabled: false }
        property real base: stage.mode === "selected" ? 0.85 : 0.45
        property real breathe: 1
        opacity: (stage.on ? base : 0) * breathe
        Behavior on base { NumberAnimation { duration: 500 * stage.k } }
        SequentialAnimation on breathe {
            running: stage.mode === "selected" && stage.on
            loops: Animation.Infinite
            NumberAnimation { from: 1; to: 0.55; duration: 1300; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.55; to: 1; duration: 1300; easing.type: Easing.InOutSine }
        }
        ShapePath {
            strokeColor: Theme.accent
            strokeWidth: 12
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: stage.pathD }
        }
    }
    Shape {
        id: line
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: stage.pathD !== ""
        opacity: stage.on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        ShapePath {
            strokeColor: Theme.accent
            strokeWidth: stage.mode === "selected" ? 2 : 2.6
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathSvg { path: stage.pathD }
        }
    }
    Shape {
        id: ants
        anchors.fill: parent
        preferredRendererType: Shape.GeometryRenderer
        visible: stage.mode === "selected"
        opacity: stage.on ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        ShapePath {
            id: antPath
            strokeColor: Qt.rgba(1, 1, 1, 0.85)
            strokeWidth: 1
            fillColor: "transparent"
            strokeStyle: ShapePath.DashLine
            dashPattern: [1.5, 8]
            PathSvg { path: stage.mode === "selected" ? stage.pathD : "" }
        }
        // 30 fps is plenty for ants (a 144 Hz NumberAnimation would re-stroke the path every frame)
        Timer {
            running: ants.visible && stage.on
            interval: 33; repeat: true
            onTriggered: antPath.dashOffset = (antPath.dashOffset - 0.57) % 9.5
        }
    }

    // ---- leader from the loop to the card + dot ----
    Shape {
        id: leadShape
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        visible: stage.mode === "selected" && (stage.cardSide === "r" || stage.cardSide === "l")
        opacity: stage.on && stage.cardIn ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        property real drawn: 0
        Behavior on drawn { NumberAnimation { duration: 380 * stage.k; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        readonly property real sx: !stage.box ? 0 : stage.cardSide === "r" ? stage.box.x + stage.box.w + 4 : stage.box.x - 4
        readonly property real sy: !stage.box ? 0 : stage.box.y + stage.box.h / 2
        readonly property real ex: stage.cardSide === "r" ? stage.cardX - 16 : stage.cardX + stage.cardW + 16
        readonly property real ey: card.y + 20
        readonly property real fx: stage.cardSide === "r" ? stage.cardX - 2 : stage.cardX + stage.cardW + 2
        readonly property real len: Math.hypot(ex - sx, ey - sy) + Math.abs(fx - ex)
        ShapePath {
            strokeColor: Theme.rgba(Theme.t.color.accent, 0.75)
            strokeWidth: 1
            fillColor: "transparent"
            strokeStyle: ShapePath.DashLine
            // draw-in: one dash as long as the line, offset from "all gap" to "all dash"
            dashPattern: [Math.max(1, leadShape.len), Math.max(1, leadShape.len)]
            dashOffset: leadShape.len * (1 - leadShape.drawn)
            startX: leadShape.sx; startY: leadShape.sy
            PathLine { x: leadShape.ex; y: leadShape.ey }
            PathLine { x: leadShape.fx; y: leadShape.ey }
        }
    }
    Rectangle {
        visible: leadShape.visible
        opacity: leadShape.opacity
        x: leadShape.sx - 3; y: leadShape.sy - 3
        width: 6; height: 6; radius: 3
        color: Theme.accent
    }

    // ---- "OCR · 9 LINES" tag ----
    Rectangle {
        id: tag
        property bool shown: false
        visible: stage.mode === "selected"
        x: stage.box ? Math.max(8, stage.box.x - 4) : 0
        y: stage.box ? Math.max(stage.barH + 4, stage.box.y - 34) : 0
        width: tagRow.width + 14; height: 20
        radius: Theme.square ? 2 : 4
        color: Theme.accent
        opacity: shown && stage.on ? 1 : 0
        transform: Translate { y: tag.shown ? 0 : 4; Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } } }
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        Row {
            id: tagRow
            x: 7; anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            AskIcon { anchors.verticalCenter: parent.verticalCenter; name: "lasso"; size: 11; color: Theme.onAccent }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                readonly property int n: stage.session.ocrLines
                text: ("OCR · " + (n < 0 ? "reading" : n === 0 ? "image" : n + (n === 1 ? " line" : " lines"))).toUpperCase()
                color: Theme.onAccent
                font.family: Theme.fontLabel; font.pointSize: 9.5 * 0.75; font.weight: Font.Medium; font.letterSpacing: 0.95
            }
        }
    }

    // ---- hint pill ----
    Rectangle {
        id: hint
        readonly property bool shown: stage.on && stage.mode === "idle"
        anchors.horizontalCenter: parent.horizontalCenter
        y: stage.barH + 18
        height: 32
        width: hintRow.width + 18
        radius: Theme.square ? 4 : 16
        color: Theme.glassOpaque ? Theme.rgba(Theme.t.color.glass, 1) : Theme.menuGlass
        border.width: 1
        border.color: Theme.white(0.14)
        opacity: shown ? 1 : 0
        transform: Translate { y: hint.shown ? 0 : -8; Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } } }
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        Row {
            id: hintRow
            x: 12; anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Item {
                width: 7; height: 7
                anchors.verticalCenter: parent.verticalCenter
                RectangularShadow { anchors.fill: hdot; radius: hdot.radius; blur: 10; color: Theme.rgba(Theme.t.color.accent, 0.9) }
                Rectangle { id: hdot; anchors.fill: parent; radius: Theme.square ? 0 : 3.5; color: Theme.accent }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.labelsMono ? "CIRCLE ANYTHING TO ASK CLAUDE" : "Circle anything to ask Claude"
                color: Theme.label
                font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
                font.pointSize: (Theme.labelsMono ? 11 : 12.5) * 0.75
                font.weight: Font.Medium
                font.letterSpacing: Theme.labelsMono ? 0.66 : 0
            }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5
                Keycap { text: Theme.labelsMono ? "DRAG" : "drag" }
                Keycap { text: Theme.labelsMono ? "CLICK" : "click" }
                Keycap { text: Theme.labelsMono ? "ESC" : "esc" }
            }
        }
    }

    // ---- input: press anywhere (outside the card) starts a new circle ----
    MouseArea {
        id: pen
        anchors.fill: parent
        enabled: stage.on
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.CrossCursor
        preventStealing: true
        onPressed: e => {
            if (e.button === Qt.RightButton) { stage.closeRequested(); return; }
            demo.stop();
            stage.begin({ x: e.x, y: e.y });
        }
        onPositionChanged: e => { if (stage.mode === "drawing") stage.extend({ x: e.x, y: e.y }); }
        onReleased: e => { if (stage.mode === "drawing" && e.button === Qt.LeftButton) stage.finish({ x: e.x, y: e.y }); }
    }

    // ---- the answer card ----
    AskCard {
        id: card
        session: stage.session
        x: stage.cardX
        y: stage.cardY
        Behavior on y { enabled: stage.cardIn; NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        maxH: stage.cardSlides ? stage.height - stage.cardTop - 14 : stage.height - stage.cardBaseY - 14
        visible: opacity > 0.01
        opacity: stage.cardIn && stage.on && stage.mode === "selected" ? 1 : 0
        scale: opacity > 0.99 || stage.cardIn && stage.on ? 1 : 0.97
        transformOrigin: stage.cardSide === "r" ? Item.TopLeft : stage.cardSide === "l" ? Item.TopRight : Item.Top
        transform: Translate {
            x: stage.cardIn && stage.on ? 0 : stage.cardSide === "r" ? 14 : stage.cardSide === "l" ? -14 : 0
            Behavior on x { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        Behavior on scale { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        onCloseRequested: stage.closeRequested()
    }
}

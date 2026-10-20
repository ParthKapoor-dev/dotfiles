pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import qs.core
import qs.components

// The voice typing pill (mock C2 #voice, Telemetry: 46 px, square 5 px corners, #060606-ish
// opaque fill, 1 px hairline, accent hairline while recording). Pure view: services/Voice drives
// it (modules/voice/VoiceTyping), the offscreen harness feeds it simulated levels.
// Layers cross-fade like the mock's .vo-l: rec (pulsing dot, dot-matrix waveform, timer, source,
// TIDY), tx ("Transcribing… local · whisper" + sweep bar), tidy (smart tidy), done (words, struck
// fillers, seconds), error.
Item {
    id: root
    property string phase: "rec"          // rec | tx | tidy | done | error
    property var hist: []
    property int elapsed: 0
    property bool tidy: true
    property string sourceLabel: "MIC"
    property int words: 0
    property var removed: []
    property real seconds: 0
    property string backend: "gpu"
    property string message: ""
    property string detail: ""
    property string tidyModel: "haiku"
    property bool smartFailed: false
    signal tidyClicked()

    readonly property bool tele: Theme.square                  // Telemetry: mono uppercase, square
    readonly property bool dots: Theme.dotMatrix
    readonly property color accent: Theme.accent
    readonly property real ease: 1
    // mock widths: rec 360, tx 300, done = its content (the mock's fixed 300 clipped "on-device")
    readonly property real targetWidth: phase === "rec" ? 360
        : (phase === "tx" || phase === "tidy") ? 300
        : phase === "error" ? Math.max(220, Math.min(560, errRow.implicitWidth + 34))
        : Math.max(300, Math.min(560, doneRow.implicitWidth + 34))
    implicitWidth: targetWidth
    implicitHeight: 46
    readonly property real cornerRadius: surface.radius

    function mmss(ms) { const s = Math.floor(ms / 1000); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0"); }
    function track(px, em) { return px * em; }

    component Label: Text {
        property real px: 10
        property real em: 0.08
        font.family: Theme.fontLabel
        font.pixelSize: px
        font.weight: Font.Medium
        font.letterSpacing: px * em
        font.capitalization: Font.AllUppercase
        color: Theme.label3
        verticalAlignment: Text.AlignVCenter
    }
    component MainText: Text {
        font.family: root.tele ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: root.tele ? 11.5 : 13
        font.weight: Font.Medium
        font.letterSpacing: root.tele ? 11.5 * 0.06 : 0
        font.capitalization: root.tele ? Font.AllUppercase : Font.MixedCase
        color: Theme.label
        verticalAlignment: Text.AlignVCenter
    }
    component Layer: Item {
        property string when
        anchors.fill: parent
        opacity: root.phase === when ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.durPop + 40; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    }

    // ---- surface ----
    Rectangle {
        id: surface
        anchors.fill: parent
        radius: root.tele ? 5 : height / 2
        color: Theme.glassOpaque ? Theme.glass : Theme.rgba(Theme.t.color.glass, Math.min(1, Theme.t.glass.alpha + 0.16))
        border.width: 1
        border.color: Theme.glassOpaque ? Theme.white(0.14) : Theme.rim
        clip: true

        // accent hairline while recording (mock #voice[data-st=rec]::after)
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.width: 1
            border.color: Qt.alpha(root.accent, 0.5)
            opacity: root.phase === "rec" ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        }

        // ================= rec =================
        Layer {
            when: "rec"
            Row {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 11
                // pulsing dot (mock .vo-dot + voPulse: a ring that spreads 10 px and fades, 1.3 s)
                Item {
                    width: 9; height: 9
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        id: ring
                        property real p: 0
                        anchors.centerIn: parent
                        width: 9 + 20 * p; height: width
                        radius: root.tele ? 1 + 3 * p : width / 2
                        color: Qt.alpha(root.accent, 0.6 * (1 - p))
                        NumberAnimation on p {
                            running: root.phase === "rec"
                            from: 0; to: 1; duration: 1300; loops: Animation.Infinite
                            easing.type: Easing.BezierSpline; easing.bezierCurve: [0, 0, 0.58, 1, 1, 1]
                        }
                    }
                    Rectangle { anchors.fill: parent; radius: root.tele ? 1 : 4.5; color: root.accent }
                }
                // waveform (mock .vo-wave 176x30, 34 columns; Telemetry = 7-row dot matrix)
                Canvas {
                    id: wave
                    width: 176; height: 30
                    anchors.verticalCenter: parent.verticalCenter
                    renderStrategy: Canvas.Cooperative
                    property var h: root.hist
                    onHChanged: requestPaint()
                    onPaint: {
                        const x = getContext("2d");
                        x.reset();
                        const n = 34, bw = width / n, lab = Theme.t.color.label;
                        const acc = root.accent;
                        for (let i = 0; i < n; i++) {
                            const v = h[h.length - n + i] ?? 0, age = (n - 1 - i) / n, a = 1 - age * 0.72, newest = i >= n - 2;
                            const col = newest ? Qt.rgba(acc.r, acc.g, acc.b, 1) : Theme.rgba(lab, a);
                            x.fillStyle = col;
                            if (root.dots) {
                                const rows = 7, lit = Math.max(1, Math.round(v * rows * 1.15)), cx = i * bw + bw / 2;
                                for (let r = 0; r < rows; r++) {
                                    const off = Math.abs(r - 3), on = off * 2 + 1 <= lit || off === 0;
                                    x.globalAlpha = on ? 1 : 0.16;
                                    x.beginPath();
                                    x.arc(cx, 3 + r * 4, 1.35, 0, Math.PI * 2);
                                    x.fill();
                                }
                                x.globalAlpha = 1;
                            } else {
                                const hh = Math.max(2, v * (height - 2)), bx = i * bw + bw * 0.22, ww = bw * 0.56, y = (height - hh) / 2, rr = Math.min(ww / 2, hh / 2);
                                x.beginPath();
                                x.roundedRect(bx, y, ww, hh, rr, rr);
                                x.fill();
                            }
                        }
                    }
                }
                Text {
                    width: 30
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.mmss(root.elapsed)
                    font.family: Theme.fontLabel
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.features: ({ "tnum": 1 })
                    color: Theme.label
                }
                Label { width: 22; px: 9; em: 0.1; anchors.verticalCenter: parent.verticalCenter; text: root.sourceLabel }
            }
            // TIDY toggle (mock .vo-tidy: hairline chip, 6 px indicator, glows accent when on)
            Rectangle {
                id: tidyChip
                anchors.right: parent.right; anchors.rightMargin: 7
                anchors.verticalCenter: parent.verticalCenter
                height: 30
                width: tidyRow.implicitWidth + 20
                radius: root.tele ? 3 : 15
                color: tidyMouse.containsMouse ? Theme.fill : "transparent"
                border.width: 1
                border.color: Theme.hair
                Behavior on color { ColorAnimation { duration: Theme.durPop } }
                Row {
                    id: tidyRow
                    anchors.centerIn: parent
                    spacing: 7
                    Item {
                        width: 6; height: 6
                        anchors.verticalCenter: parent.verticalCenter
                        // glow (mock box-shadow 0 0 8px accent .9)
                        RectangularShadow {
                            anchors.fill: parent
                            blur: 8
                            color: Qt.alpha(root.accent, 0.9)
                            opacity: root.tidy ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: root.tele ? 0 : 3
                            color: root.tidy ? root.accent : Theme.label3
                            Behavior on color { ColorAnimation { duration: Theme.durPop } }
                        }
                    }
                    Label {
                        px: 10; em: 0.09
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Tidy"
                        color: root.tidy ? Theme.label : Theme.label3
                        Behavior on color { ColorAnimation { duration: Theme.durPop } }
                    }
                }
                MouseArea { id: tidyMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tidyClicked() }
            }
        }

        // ================= transcribing / smart tidy =================
        component Busy: Layer {
            id: busy
            property string main
            property string sub
            Row {
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 11
                // spinner (mock .vo-sp: 15 px accent arc, M12 3a9 9 0 1 0 9 9)
                Item {
                    width: 15; height: 15
                    anchors.verticalCenter: parent.verticalCenter
                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        scale: 15 / 24; transformOrigin: Item.TopLeft
                        width: 24; height: 24
                        ShapePath {
                            strokeColor: root.accent; strokeWidth: 2.4; fillColor: "transparent"; capStyle: ShapePath.RoundCap
                            startX: 12; startY: 3
                            PathArc { x: 21; y: 12; radiusX: 9; radiusY: 9; useLargeArc: true; direction: PathArc.Counterclockwise }
                        }
                    }
                    RotationAnimation on rotation { running: busy.visible; from: 0; to: 360; duration: 800; loops: Animation.Infinite }
                }
                MainText { anchors.verticalCenter: parent.verticalCenter; text: busy.main }
            }
            Label {
                anchors.right: parent.right; anchors.rightMargin: 17
                anchors.verticalCenter: parent.verticalCenter
                px: 10; em: 0.08
                text: busy.sub
            }
            // sweep bar (mock .vo-bar: 2 px track 16 px in from the sides, 5 px off the bottom)
            Rectangle {
                x: 16; width: parent.width - 32
                y: parent.height - 5 - 2; height: 2
                radius: root.tele ? 0 : 1
                color: Theme.fill
                clip: true
                Rectangle {
                    id: sweep
                    property real p: 0
                    width: parent.width * 0.4; height: parent.height
                    x: -width + (parent.width + width) * p
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.alpha(root.accent, 0) }
                        GradientStop { position: 0.5; color: root.accent }
                        GradientStop { position: 1; color: Qt.alpha(root.accent, 0) }
                    }
                    NumberAnimation on p {
                        running: busy.visible
                        from: 0; to: 1; duration: 900; loops: Animation.Infinite
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase
                    }
                }
            }
        }
        Busy {
            when: "tx"
            main: "Transcribing…"
            sub: "local · whisper" + (root.backend.startsWith("cpu") ? " · cpu" : "")
        }
        Busy {
            when: "tidy"
            main: "Tidying…"
            sub: "claude · " + root.tidyModel
        }

        // ================= done =================
        Layer {
            when: "done"
            Row {
                id: doneRow
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 11
                // mock .vo-ok: 18 px accent square, check in on-accent
                Rectangle {
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    radius: root.tele ? 3 : 9
                    color: root.accent
                    Glyph { anchors.centerIn: parent; name: "check"; size: 12; strokeWidth: 2.6; color: Theme.onAccent }
                }
                MainText { anchors.verticalCenter: parent.verticalCenter; text: root.words + (root.words === 1 ? " word" : " words") }
                // what tidy took out, struck through in accent, then collapsing (mock .fl.struck -> .gone)
                Item {
                    id: struckBox
                    property real gone: 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.round(struck.implicitWidth * (1 - gone)); height: struck.implicitHeight
                    clip: true
                    opacity: 1 - gone
                    visible: root.removed.length > 0 && gone < 1
                    SequentialAnimation {
                        running: root.phase === "done" && root.removed.length > 0
                        PropertyAction { target: struckBox; property: "gone"; value: 0 }
                        PauseAnimation { duration: 1150 }
                        NumberAnimation { target: struckBox; property: "gone"; to: 1; duration: 340; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
                    }
                Row {
                    id: struck
                    spacing: 7
                    Repeater {
                        model: root.removed.slice(0, 4).concat(root.removed.length > 4 ? ["+" + (root.removed.length - 4)] : [])
                        Item {
                            id: chip
                            required property string modelData
                            required property int index
                            readonly property bool more: modelData.startsWith("+")
                            property real strike: 0
                            width: word.implicitWidth; height: word.implicitHeight
                            Label { id: word; px: 10; em: 0.06; text: chip.modelData; color: Theme.label2; font.capitalization: Font.MixedCase }
                            Rectangle {
                                visible: !chip.more
                                y: Math.round(word.height / 2); height: 1.5
                                width: word.width * chip.strike
                                color: root.accent
                            }
                            SequentialAnimation {
                                running: root.phase === "done"
                                PropertyAction { target: chip; property: "strike"; value: 0 }
                                PauseAnimation { duration: 120 + chip.index * 70 }
                                NumberAnimation { target: chip; property: "strike"; to: 1; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase }
                            }
                        }
                    }
                }
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    px: 10; em: 0.08
                    textFormat: Text.StyledText
                    readonly property string b2: Theme.label2.toString()
                    text: root.seconds.toFixed(1) + " s"
                        + (root.removed.length ? " · tidy <font color='" + b2 + "'>−" + root.removed.length + "</font>" : "")
                        + (root.smartFailed ? " · smart tidy off" : "")
                        + " · " + (root.backend.startsWith("cpu") ? "on-device cpu" : "on-device")
                }
            }
        }

        // ================= error / no speech =================
        Layer {
            when: "error"
            Row {
                id: errRow
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 11
                Rectangle {
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    radius: root.tele ? 3 : 9
                    color: Theme.fill2
                    Glyph { anchors.centerIn: parent; name: "x"; size: 12; strokeWidth: 2.4; color: Theme.label }
                }
                MainText { anchors.verticalCenter: parent.verticalCenter; text: root.message }
                Label { anchors.verticalCenter: parent.verticalCenter; px: 10; em: 0.08; text: root.detail; visible: text !== "" }
            }
        }
    }
}

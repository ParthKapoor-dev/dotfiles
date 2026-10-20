pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.core
import qs.components
import qs.services

// Mission Control contents (mock #agents, Telemetry look): near-black backdrop with an accent wash
// from the top + grain, "NOX · AGENTS · LIVE / MISSION CONTROL" with the live stats in dot-matrix
// numerals, a grid of live session tiles, key hints. The window (AgentsView) owns open/close and
// the jump into a pane; this item owns selection and keys.
Item {
    id: root
    property var sessions: Agents.sessions
    property var usage: Agents.usage
    property var today: Agents.today
    property bool shown: false
    property bool jumping: false
    property int sel: 0
    property real now: Date.now()
    property real openedAt: 0
    signal jump(int index, var tileItem)
    signal dismiss()
    signal reply(int index)

    readonly property int n: sessions.length
    readonly property int cols: n <= 1 ? 1 : n <= 4 ? 2 : n <= 9 ? 3 : 4
    readonly property int rows: Math.max(1, Math.ceil(n / cols))
    readonly property real side: 44
    readonly property real headTop: Theme.barHeight + 26
    readonly property real gridTop: Theme.barHeight + 98
    readonly property real gap: 16
    // at most 3 rows on screen; more scroll
    readonly property real tileH: n === 0 ? 0 : Math.max(250, (height - gridTop - 66 - gap * (Math.min(rows, 3) - 1)) / Math.min(rows, 3))
    readonly property real tileW: (width - side * 2 - gap * (cols - 1)) / cols

    Timer { interval: 1000; repeat: true; running: root.shown; onTriggered: root.now = Date.now() }
    onShownChanged: if (shown) { now = Date.now(); }

    function select(i) {
        if (n === 0) return;
        sel = Math.max(0, Math.min(n - 1, i));
        // keep the selection on screen
        const t = rep.itemAt(sel);
        if (t) {
            if (t.y < flick.contentY) flick.contentY = t.y;
            else if (t.y + t.height > flick.contentY + flick.height) flick.contentY = t.y + t.height - flick.height + 8;
        }
    }
    function selectId(id) { const i = sessions.findIndex(s => s.id === id); if (i >= 0) select(i); }
    function tileAt(i) { return rep.itemAt(i); }
    function key(e) {
        if (jumping) { e.accepted = true; return; }
        const k = e.key, cur = sessions[sel];
        if (k === Qt.Key_Escape) root.dismiss();
        else if (k === Qt.Key_Right || k === Qt.Key_Tab) select((sel + 1) % Math.max(1, n));
        else if (k === Qt.Key_Left || k === Qt.Key_Backtab) select((sel - 1 + n) % Math.max(1, n));
        else if (k === Qt.Key_Down) select(Math.min(n - 1, sel + cols));
        else if (k === Qt.Key_Up) select(Math.max(0, sel - cols));
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (n) root.jump(sel, tileAt(sel)); }
        // Y / N on a waiting tile: the answer is given in the pane, so they jump there
        else if ((k === Qt.Key_Y || k === Qt.Key_N || k === Qt.Key_R) && cur?.status === "needs-you") root.jump(sel, tileAt(sel));
        // R: reply (the panel's reply box)
        else if (k === Qt.Key_R && Agents.canReply(cur)) root.reply(sel);
        else return;
        e.accepted = true;
    }
    onSessionsChanged: if (sel >= n) sel = Math.max(0, n - 1)

    // ---- backdrop: near-black, accent wash from the top, vignette, grain ----
    Item {
        id: backdrop
        anchors.fill: parent
        opacity: root.shown && !root.jumping ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.jumping ? 300 : 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0.012, 0.012, 0.012, 0.9) }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.width / 2; centerY: -root.height * 0.1
                    focalX: centerX; focalY: centerY
                    centerRadius: root.width * 0.62
                    GradientStop { position: 0.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.1) }
                    GradientStop { position: 1.0; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0) }
                }
                startX: 0; startY: 0
                PathLine { x: root.width; y: 0 }
                PathLine { x: root.width; y: root.height }
                PathLine { x: 0; y: root.height }
                PathLine { x: 0; y: 0 }
            }
        }
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.GeometryRenderer
            ShapePath {
                strokeWidth: -1
                fillGradient: RadialGradient {
                    centerX: root.width / 2; centerY: root.height * 0.45
                    focalX: centerX; focalY: centerY
                    centerRadius: Math.hypot(root.width, root.height) * 0.6
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0) }
                    GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
                }
                startX: 0; startY: 0
                PathLine { x: root.width; y: 0 }
                PathLine { x: root.width; y: root.height }
                PathLine { x: 0; y: root.height }
                PathLine { x: 0; y: 0 }
            }
        }
        Image {
            anchors.fill: parent
            source: "../../assets/grain.png"
            fillMode: Image.Tile
            opacity: Config.opt.agents?.grain ?? 0.06
            smooth: false
        }
        MouseArea { anchors.fill: parent; onClicked: root.dismiss() }
    }

    // ---- header ----
    Item {
        id: header
        x: root.side
        y: root.headTop + (root.shown && !root.jumping ? 0 : -8)
        width: root.width - root.side * 2
        height: 56
        opacity: root.shown && !root.jumping ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade + 60; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        Behavior on y { NumberAnimation { duration: Theme.durSheet + 80; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }

        Column {
            anchors.bottom: parent.bottom
            spacing: 9
            Row {
                spacing: 8
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6; height: 6
                    radius: Theme.square ? 0 : 3
                    color: Theme.accent
                }
                Text {
                    text: "nox · agents · live"
                    color: Theme.label3
                    font.family: Theme.fontLabel
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6
                }
            }
            Text {
                text: "Mission control"
                color: Theme.label
                font.family: Theme.fontLabel
                font.pixelSize: 22
                font.weight: Font.Medium
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 3.1
            }
        }
        Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -2
            spacing: 30
            Repeater {
                model: [
                    ["Sessions", Agents.alive.length, false],
                    ["Working", Agents.working, false],
                    ["Needs you", Agents.needsYou, Agents.needsYou > 0],
                    ["Errors", Agents.errors, false],
                    ["Today", "$" + (root.today?.cost ?? 0).toFixed(2), false],
                    ["Tokens", Agents.fmtTok(root.today?.tokens ?? 0), false]
                ]
                Column {
                    id: stat
                    required property var modelData
                    spacing: 7
                    Text {
                        text: stat.modelData[0]
                        color: Theme.label3
                        font.family: Theme.fontLabel
                        font.pixelSize: 10
                        font.weight: Font.Medium
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1.35
                    }
                    Text {
                        text: String(stat.modelData[1])
                        color: stat.modelData[2] ? Theme.accent : Theme.label
                        font.family: Theme.fontNumeric
                        font.pixelSize: Theme.dotMatrix ? 28 : 26
                        font.weight: Theme.dotMatrix ? Theme.numericWeight : Font.Light
                        font.variableAxes: Theme.numericAxes
                        font.features: ({ "tnum": 1 })
                        height: 26
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    // ---- tiles ----
    Flickable {
        id: flick
        x: root.side - 10
        y: root.gridTop - 10
        width: root.width - root.side * 2 + 20
        height: root.height - root.gridTop - 66 + 20
        contentWidth: width
        contentHeight: grid.height + 20
        clip: root.rows > 3
        interactive: root.rows > 3
        boundsBehavior: Flickable.StopAtBounds
        Item {
            id: grid
            x: 10; y: 10
            width: root.width - root.side * 2
            height: root.rows * root.tileH + (root.rows - 1) * root.gap
            Repeater {
                id: rep
                model: root.sessions
                AgentTile {
                    id: t
                    required property var modelData
                    session: modelData
                    usage: root.usage[modelData.id] ?? ({})
                    x: (index % root.cols) * (root.tileW + root.gap)
                    y: Math.floor(index / root.cols) * (root.tileH + root.gap)
                    width: root.tileW
                    height: root.tileH
                    z: zooming ? 2 : 1
                    selected: index === root.sel && !root.jumping
                    shown: root.shown
                    now: root.now
                    openedAt: root.openedAt
                    visible: !root.jumping || zooming
                    onHovered: if (!root.jumping && root.sel !== index) root.sel = index
                    onActivated: { if (root.jumping) return; if (root.sel === index) root.jump(index, t); else root.sel = index; }
                }
            }
        }
    }

    // nothing yet
    Column {
        anchors.centerIn: parent
        visible: root.n === 0
        opacity: root.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        spacing: 10
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No agent sessions"
            color: Theme.label2
            font.family: Theme.fontLabel
            font.pixelSize: 13
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 2
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Claude Code sessions show up here once the nox agent hook is installed"
            color: Theme.label3
            font.family: Theme.fontUi
            font.pixelSize: 12
        }
    }

    // ---- key hints ----
    Item {
        x: root.side
        width: root.width - root.side * 2
        height: 20
        y: root.height - 24 - height
        opacity: root.shown && !root.jumping ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        Row {
            spacing: 20
            Repeater {
                model: [[["←", "↑", "↓", "→"], "Move"], [["↵"], "Jump to pane"], [["R"], "Reply"], [["Y"], "Answer in pane"]]
                Row {
                    id: hint
                    required property var modelData
                    spacing: 6
                    Repeater { model: hint.modelData[0]; Keycap { required property string modelData; text: modelData } }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 2
                        text: hint.modelData[1]
                        color: Theme.label2
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                    }
                }
            }
        }
        Row {
            anchors.right: parent.right
            spacing: 6
            Keycap { text: "esc" }
            Text { anchors.verticalCenter: parent.verticalCenter; leftPadding: 2; text: "Close"; color: Theme.label2; font.family: Theme.fontUi; font.pixelSize: 12 }
        }
    }
}

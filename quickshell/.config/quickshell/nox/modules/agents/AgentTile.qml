pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts as QL
import Quickshell
import qs.core
import qs.components
import qs.services

// One live session tile (mock .mc-t, Telemetry look): status chip + tool/model, PROJECT + branch,
// task, the pending question / summary / error, the activity feed (tool calls with their result
// lines, assistant lines, your prompts; new lines type in and push the feed up), files touched,
// and context tokens / dot meter / context % / cost.
Item {
    id: tile
    required property var session
    required property int index
    property var usage: ({})
    property bool selected: false
    property bool shown: false              // overlay entrance (staggered by index)
    property real now: Date.now()
    property real openedAt: 0               // lines newer than this animate in
    property bool zooming: false            // jump-to-pane: chrome only, contents fade
    signal activated()
    signal hovered()

    readonly property var s: session ?? ({})
    readonly property string st: s.status ?? "done"
    readonly property bool need: st === "needs-you"
    readonly property bool err: st === "error"
    readonly property bool ended: st === "ended"
    readonly property bool idle: st === "done" && !(s.firstPrompt ?? "") && !(s.activity ?? []).length
    readonly property color tileBg: Qt.rgba(0.04, 0.04, 0.04, 1)
    readonly property int rad: Theme.square ? 4 : Theme.radiusPanel
    readonly property string mono: Theme.fontMono
    readonly property string labelFont: Theme.fontLabel

    // ---- entrance: fade + rise + settle, 45 ms apart ----
    property real enter: 0
    onShownChanged: { if (shown) { enter = 0; enterAnim.restart(); } else { enterAnim.stop(); enter = 0; } }
    SequentialAnimation {
        id: enterAnim
        PauseAnimation { duration: tile.index * 45 }
        NumberAnimation { target: tile; property: "enter"; to: 1; duration: Theme.durSheet + 80; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
    }
    opacity: zooming ? 1 : enter * (ended ? 0.55 : 1)
    transform: [
        Scale { id: zs; origin.x: 0; origin.y: 0 },
        Translate { id: zt; y: (1 - tile.enter) * 14 }
    ]
    scale: 0.98 + 0.02 * enter

    // ---- jump: the tile flies into its window rect (screen coords relative to this item's parent) ----
    function zoomTo(r) {
        zooming = true;
        zx.to = r.x - x; zy.to = r.y - y;
        sx.to = r.w / width; sy.to = r.h / height;
        zoomAnim.restart();
    }
    ParallelAnimation {
        id: zoomAnim
        NumberAnimation { id: zx; target: zt; property: "x"; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
        NumberAnimation { id: zy; target: zt; property: "y"; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
        NumberAnimation { id: sx; target: zs; property: "xScale"; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
        NumberAnimation { id: sy; target: zs; property: "yScale"; duration: 560; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
        SequentialAnimation {
            PauseAnimation { duration: 320 }
            NumberAnimation { target: frame; property: "opacity"; to: 0; duration: 240 }
        }
    }

    // ---- frame ----
    Item {
        id: frame
        anchors.fill: parent

        // needs-you: slow accent breathing glow
        RectangularShadow {
            anchors.fill: parent
            visible: tile.need && !tile.zooming
            radius: tile.rad
            blur: 38
            spread: 0
            color: Theme.accent
            opacity: glowPulse.v * 0.16
            QtObject { id: glowPulse; property real v: 0 }
            SequentialAnimation {
                running: tile.need && tile.shown && !tile.zooming
                loops: Animation.Infinite
                NumberAnimation { target: glowPulse; property: "v"; from: 0; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                NumberAnimation { target: glowPulse; property: "v"; from: 1; to: 0; duration: 1100; easing.type: Easing.InOutSine }
            }
        }
        RectangularShadow {
            anchors.fill: parent
            visible: !tile.zooming
            radius: tile.rad
            offset.y: tile.selected ? 26 : 18
            blur: tile.selected ? 64 : 44
            color: Qt.rgba(0, 0, 0, tile.selected ? 0.55 : 0.35)
        }
        Rectangle {
            anchors.fill: parent
            radius: tile.rad
            color: tile.zooming ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.06)
                 : tile.selected ? Qt.rgba(0.063, 0.063, 0.063, 0.92) : hover.containsMouse ? Qt.rgba(0.05, 0.05, 0.05, 0.88) : Qt.rgba(0.04, 0.04, 0.04, 0.82)
            border.width: 1
            border.color: tile.zooming ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.85)
                        : tile.need ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.72 + 0.2 * glowPulse.v)
                        : tile.err ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.35)
                        : Theme.white(tile.selected ? 0.22 : 0.12)
            Behavior on color { ColorAnimation { duration: Theme.durFade } }
        }
        // viewfinder corners just outside the selected tile (accent while it waits for you)
        Brackets {
            anchors.fill: parent
            anchors.margins: -6
            inset: 0
            len: 13
            thick: 1.5
            color: tile.need || tile.zooming ? Theme.accent : Theme.label
            opacity: tile.selected || tile.zooming ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: tile.hovered()
        onClicked: tile.activated()
    }

    // ---- content ----
    QL.ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.leftMargin: 16; anchors.rightMargin: 16
        anchors.topMargin: 15; anchors.bottomMargin: 13
        spacing: 0
        opacity: tile.zooming ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: 160 } }

        // status chip · tool · model
        QL.RowLayout {
            QL.Layout.fillWidth: true
            QL.Layout.preferredHeight: 16
            spacing: 7
            // working: square ring spinner
            Item {
                visible: tile.st === "working"
                implicitWidth: 11; implicitHeight: 11
                Rectangle { anchors.fill: parent; radius: Theme.square ? 1 : 5.5; color: "transparent"; border.width: 1.5; border.color: Theme.fill3 }
                Item {
                    anchors.fill: parent
                    RotationAnimation on rotation { running: tile.st === "working" && tile.shown; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                    Rectangle { x: 2; width: parent.width - 4; height: 1.5; color: Theme.label }
                }
            }
            // needs you: pinging square
            Item {
                visible: tile.need
                implicitWidth: 8; implicitHeight: 8
                Rectangle {
                    id: pingRing
                    anchors.centerIn: parent
                    width: 8; height: 8
                    radius: Theme.square ? 0 : 4
                    color: "transparent"
                    border.width: 1.5
                    border.color: Theme.accent
                    SequentialAnimation on scale { running: tile.need && tile.shown; loops: Animation.Infinite; NumberAnimation { from: 1; to: 2.6; duration: 1000; easing.type: Easing.OutCubic } PauseAnimation { duration: 300 } }
                    SequentialAnimation on opacity { running: tile.need && tile.shown; loops: Animation.Infinite; NumberAnimation { from: 0.8; to: 0; duration: 1000; easing.type: Easing.OutCubic } PauseAnimation { duration: 300 } }
                }
                Rectangle { anchors.fill: parent; radius: Theme.square ? 0 : 4; color: Theme.accent }
            }
            AgentGlyph {
                visible: tile.st === "done" && !tile.idle || tile.err
                name: tile.err ? "alert" : "check"
                size: 12
                color: tile.err ? Theme.red : Theme.green
            }
            Rectangle {
                visible: tile.ended || tile.idle
                implicitWidth: 7; implicitHeight: 7
                color: "transparent"
                border.width: 1.2
                border.color: Theme.label3
            }
            Text {
                text: tile.need ? "Needs you" : tile.st === "working" ? "Working" : tile.err ? "Error"
                    : tile.ended ? "Ended" : tile.idle ? "Idle" : "Done"
                color: tile.need ? Theme.accent : tile.err ? Theme.red : tile.st === "done" && !tile.idle ? Theme.green : Theme.label2
                font.family: tile.labelFont
                font.pixelSize: 10
                font.weight: Font.Medium
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1.1
            }
            Text {
                text: tile.need ? Agents.hms(tile.now - (tile.s.perm?.at ?? tile.s.since ?? tile.now))
                    : tile.st === "working" ? Agents.hms(tile.now - (tile.s.since ?? tile.now))
                    : tile.err ? String(tile.s.error ?? "").split(" ")[0].slice(0, 18)
                    : tile.ended ? (tile.s.endReason ? String(tile.s.endReason).replace(/_/g, " ") : "")
                    : Agents.hms((tile.s.since ?? tile.now) - (tile.s.started ?? tile.now))
                color: Theme.label
                font.family: tile.labelFont
                font.pixelSize: 10
                font.weight: Font.Medium
                font.letterSpacing: 0.4
                font.features: ({ "tnum": 1 })
            }
            Item { QL.Layout.fillWidth: true }
            Text {
                QL.Layout.maximumWidth: body.width * 0.55
                text: [Agents.kindName(tile.s), Agents.modelName(tile.usage?.model || tile.s.model)].filter(x => x).join(" · ")
                    + (tile.s.bg ? " · bg" : "") + ((tile.s.subagents ?? 0) > 0 ? " · +" + tile.s.subagents + " sub" : "")
                elide: Text.ElideRight
                color: Theme.label3
                font.family: tile.labelFont
                font.pixelSize: 10
                font.weight: Font.Medium
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.95
            }
        }

        // PROJECT  ⑂ branch
        QL.RowLayout {
            QL.Layout.fillWidth: true
            QL.Layout.topMargin: 13
            spacing: 10
            Text {
                text: tile.s.project || "—"
                color: Theme.label
                font.family: tile.labelFont
                font.pixelSize: 18
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.72
                QL.Layout.maximumWidth: body.width * 0.6
                elide: Text.ElideRight
            }
            AgentGlyph {
                visible: !!tile.s.branch
                name: "branch"; size: 11; color: Theme.label3
                QL.Layout.alignment: Qt.AlignVCenter
                QL.Layout.topMargin: 2
            }
            Text {
                visible: !!tile.s.branch
                QL.Layout.fillWidth: true
                QL.Layout.leftMargin: -6
                QL.Layout.topMargin: 3
                text: tile.s.branch ?? ""
                color: Theme.label3
                font.family: tile.mono
                font.pixelSize: 11
                elide: Text.ElideRight
            }
            Item { visible: !tile.s.branch; QL.Layout.fillWidth: true }
        }

        // task (session title, else the first prompt)
        Text {
            QL.Layout.fillWidth: true
            QL.Layout.topMargin: 7
            text: tile.usage?.title || tile.s.firstPrompt || (tile.idle ? "Waiting for a first prompt" : "")
            color: Theme.label2
            font.family: Theme.fontUi
            font.pixelSize: 13
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        // the pending question
        Rectangle {
            visible: tile.need
            QL.Layout.fillWidth: true
            QL.Layout.topMargin: 12
            implicitHeight: q.implicitHeight + 21
            radius: Theme.square ? 2 : 10
            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.09)
            clip: true
            Rectangle { width: 2; height: parent.height; color: Theme.accent }
            Column {
                id: q
                x: 12; y: 10
                width: parent.width - 24
                spacing: 4
                Text {
                    text: "Permission" + (tile.s.perm?.tool ? " · " + tile.s.perm.tool : "")
                    color: Theme.accent
                    font.family: tile.labelFont
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.15
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: tile.s.perm?.desc ?? ""
                    color: Theme.label
                    font.family: Theme.fontUi
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    lineHeight: 1.15
                }
                Rectangle {
                    visible: !!tile.s.perm?.cmd
                    width: Math.min(parent.width, cmd.implicitWidth + 10)
                    height: cmd.implicitHeight + 5
                    radius: Theme.square ? 2 : 3
                    color: Theme.fill2
                    Text {
                        id: cmd
                        x: 5; y: 2.5
                        width: parent.width - 10
                        text: tile.s.perm?.cmd ?? ""
                        color: Theme.label
                        font.family: tile.mono
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                Row {
                    topPadding: 6
                    spacing: 6
                    // answering happens in the pane (no decision hook): Enter / Y jumps there
                    Rectangle {
                        height: 26
                        width: jumpRow.implicitWidth + 20
                        radius: Theme.square ? 2 : 7
                        color: Theme.accent
                        scale: jumpMouse.pressed ? 0.94 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.durPop } }
                        Row {
                            id: jumpRow
                            anchors.centerIn: parent
                            spacing: 7
                            AgentGlyph { anchors.verticalCenter: parent.verticalCenter; name: "reply"; size: 12; color: Theme.onAccent }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Answer in pane"
                                color: Theme.onAccent
                                font.family: tile.labelFont
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: 0.6
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 16; height: 16; radius: 2
                                color: Qt.rgba(0, 0, 0, 0.18)
                                Text { anchors.centerIn: parent; text: "↵"; color: Theme.onAccent; font.family: tile.labelFont; font.pixelSize: 10 }
                            }
                        }
                        MouseArea { id: jumpMouse; anchors.fill: parent; onClicked: tile.activated() }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 4
                        text: "Y · N · R in the terminal"
                        color: Theme.label3
                        font.family: tile.labelFont
                        font.pixelSize: 10
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 0.8
                    }
                }
            }
        }

        // done: the last answer · error: what failed
        Rectangle {
            visible: (tile.st === "done" && !tile.idle && !!tile.s.summary) || (tile.err && !!tile.s.error)
            QL.Layout.fillWidth: true
            QL.Layout.topMargin: 12
            implicitHeight: 38
            radius: Theme.square ? 2 : 10
            color: Theme.fill
            Rectangle { width: 2; height: parent.height; color: tile.err ? Theme.red : Theme.green }
            Text {
                x: 12
                width: parent.width - 22
                anchors.verticalCenter: parent.verticalCenter
                text: tile.err ? (tile.s.error ?? "") : (tile.s.summary ?? "")
                color: tile.err ? Theme.label2 : Theme.label
                font.family: tile.err ? tile.mono : Theme.fontUi
                font.pixelSize: tile.err ? 11 : 12
                elide: Text.ElideRight
            }
        }

        // ---- activity feed ----
        Item {
            id: feed
            QL.Layout.fillWidth: true
            QL.Layout.fillHeight: true
            QL.Layout.topMargin: 12
            QL.Layout.minimumHeight: 20
            clip: true
            Rectangle { width: parent.width; height: 1; color: Theme.sep }

            readonly property real lineH: 18
            // activity (hook) + the assistant's own lines (transcript) by time; one or two rows each
            readonly property var rows: {
                const out = [];
                const acts = (tile.s.activity ?? []).slice();
                const seen = {};
                for (const a of acts) if (a.k === "say") seen[a.a] = true;
                for (const y of (tile.usage?.say ?? [])) if (!seen[y.a]) acts.push({ k: "say", a: y.a, ts: y.ts });
                acts.sort((a, b) => a.ts - b.ts);
                let i = 0;
                for (const a of acts) {
                    const key = a.k + ":" + a.ts + ":" + (a.id ?? a.a ?? "") + ":" + (i++);
                    if (a.k === "tool") {
                        out.push({ key: key, t: "tool", n: a.n, a: a.a, s: a.s, sub: !!a.sub, ts: a.ts });
                        if (a.r !== undefined && a.r !== null) out.push({ key: key + ":r", t: a.r === "you said no" ? "you" : a.s === "er" ? "er" : a.n === "Bash" ? "ok" : "res", a: a.r, ts: a.ts });
                    } else out.push({ key: key, t: a.k, a: a.a, ts: a.ts });
                }
                return out.slice(-12);
            }
            Column {
                id: lines
                width: parent.width
                y: feed.height - height
                Behavior on y { enabled: tile.shown && tile.enter >= 1; NumberAnimation { duration: 260; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                Repeater {
                    model: ScriptModel { values: feed.rows; objectProp: "key" }
                    Item {
                        id: line
                        required property var modelData
                        width: lines.width
                        height: feed.lineH
                        readonly property var d: modelData
                        readonly property bool fresh: (d.ts ?? 0) > tile.openedAt && tile.openedAt > 0
                        property real reveal: fresh ? 0 : 1
                        Component.onCompleted: if (fresh) typeAnim.start()
                        NumberAnimation { id: typeAnim; target: line; property: "reveal"; to: 1; duration: 520 }
                        Item {
                            width: parent.width * line.reveal
                            height: parent.height
                            clip: line.reveal < 1
                            Row {
                                width: line.width
                                height: parent.height
                                leftPadding: line.d.t === "res" || line.d.t === "ok" || line.d.t === "er" ? 15 : 0
                                spacing: 0
                                Text {
                                    id: lead
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: line.d.t === "tool" || line.d.t === "say" ? "● " : line.d.t === "you" ? "↳ " : "⎿ "
                                    color: line.d.t === "tool" ? (line.d.s === "er" ? Theme.red : line.d.s === "run" ? Theme.label3 : Theme.green)
                                         : line.d.t === "say" ? Theme.label : line.d.t === "you" ? Theme.accent
                                         : line.d.t === "er" ? Theme.red : line.d.t === "ok" ? Theme.green : Theme.label3
                                    font.family: tile.mono
                                    font.pixelSize: line.d.t === "tool" || line.d.t === "say" ? 9 : 11
                                    // the running call's dot breathes
                                    SequentialAnimation on opacity {
                                        running: line.d.t === "tool" && line.d.s === "run" && tile.shown
                                        loops: Animation.Infinite
                                        alwaysRunToEnd: true
                                        NumberAnimation { to: 0.25; duration: 600 }
                                        NumberAnimation { to: 1; duration: 600 }
                                    }
                                }
                                Text {
                                    id: nm
                                    visible: line.d.t === "tool"
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: line.d.n ?? ""
                                    color: line.d.sub ? Theme.label2 : Theme.label     // a subagent's call: one step back
                                    font.family: tile.mono
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: line.width - lead.implicitWidth - (nm.visible ? nm.implicitWidth : 0) - parent.leftPadding
                                    text: line.d.t === "tool" ? "(" + (line.d.a ?? "") + ")" : (line.d.a ?? "")
                                    color: line.d.t === "tool" ? Theme.label2 : line.d.t === "say" ? Theme.label
                                         : line.d.t === "you" ? Theme.accent : line.d.t === "er" ? Theme.red : line.d.t === "ok" ? Theme.green : Theme.label3
                                    font.family: tile.mono
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
            // older lines fade out toward the top (mock mask: transparent -> opaque at 46%)
            Rectangle {
                width: parent.width
                height: parent.height * 0.5
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.rgba(0.04, 0.04, 0.04, 0.97) }
                    GradientStop { position: 1; color: Qt.rgba(0.04, 0.04, 0.04, 0) }
                }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.sep }
        }

        // files touched (last 3, + more)
        Row {
            QL.Layout.fillWidth: true
            QL.Layout.topMargin: 11
            QL.Layout.preferredHeight: 18
            visible: (tile.s.files ?? []).length > 0
            spacing: 5
            clip: true
            Repeater {
                model: (tile.s.files ?? []).slice(-3)
                Rectangle {
                    id: chip
                    required property var modelData
                    height: 18
                    width: chipRow.implicitWidth + 12
                    radius: Theme.square ? 2 : 4
                    color: Theme.fill
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 4
                        Text { text: chip.modelData.m ?? "M"; color: chip.modelData.m === "A" ? Theme.green : Theme.orange; font.family: tile.mono; font.pixelSize: 10 }
                        Text { text: String(chip.modelData.p ?? "").split("/").pop(); color: Theme.label2; font.family: tile.mono; font.pixelSize: 10 }
                    }
                }
            }
            Rectangle {
                visible: (tile.s.files ?? []).length > 3
                height: 18
                width: more.implicitWidth + 12
                radius: Theme.square ? 2 : 4
                color: Theme.fill
                Text { id: more; anchors.centerIn: parent; text: "+" + ((tile.s.files ?? []).length - 3); color: Theme.label3; font.family: tile.mono; font.pixelSize: 10 }
            }
        }

        // context tokens · dot meter · context % · cost
        QL.RowLayout {
            QL.Layout.fillWidth: true
            QL.Layout.topMargin: 11
            spacing: 10
            readonly property bool known: tile.usage?.ctx !== undefined
            Text {
                text: parent.known ? Agents.fmtTok(tile.usage.ctx) + " tok" : "— tok"
                color: Theme.label3
                font.family: tile.labelFont
                font.pixelSize: 10
                font.weight: Font.Medium
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.5
                font.features: ({ "tnum": 1 })
            }
            DotMeter {
                QL.Layout.fillWidth: true
                QL.Layout.preferredHeight: 7
                QL.Layout.minimumWidth: 30
                style: "dots"
                pitch: 6
                value: (tile.usage?.pct ?? 0) / 100
                fillColor: (tile.usage?.pct ?? 0) >= 85 ? Theme.accent : Theme.label
            }
            Text {
                text: (parent.known ? tile.usage.pct : "—") + "% ctx"
                color: Theme.label3
                font.family: tile.labelFont
                font.pixelSize: 10
                font.weight: Font.Medium
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.5
                font.features: ({ "tnum": 1 })
            }
            Text {
                text: parent.known ? "$" + (tile.usage.cost ?? 0).toFixed(2) : "$—"
                color: Theme.label
                font.family: tile.labelFont
                font.pixelSize: 10
                font.weight: Font.Medium
                font.letterSpacing: 0.5
                font.features: ({ "tnum": 1 })
            }
        }
    }
}

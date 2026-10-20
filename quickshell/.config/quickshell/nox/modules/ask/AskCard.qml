pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.core
import qs.components
import "AskMd.js" as Md

// The answer card (mock 23b .ask-card, Telemetry skin): "CLAUDE · APP · TITLE" header with model and
// time to first token, the streamed answer (markdown, mono code, diff rows), chips, follow-up input.
// Everything it shows comes from `session` (AskSession).
Item {
    id: card
    required property var session
    property real maxH: 600
    property bool shown: false
    signal closeRequested()

    readonly property bool sq: Theme.square
    readonly property bool upper: Theme.labelsMono
    readonly property color cardBg: Theme.glassOpaque ? Theme.rgba(Theme.t.color.glass, 1) : Theme.cardGlass
    readonly property color wellBg: Theme.glassOpaque ? Theme.page : Qt.rgba(0, 0, 0, 0.36)
    // inline `code` chips: fill2 over the card, flattened (rich text has no alpha compositing worth trusting)
    readonly property color chipBg: Qt.tint(cardBg, Theme.white(Theme.t.color.fill2Alpha))
    function mix(a, b, t) { return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1); }
    readonly property color delFg: mix(Theme.red, Qt.rgba(1, 1, 1, 1), 0.5)
    readonly property color addFg: mix(Theme.green, Qt.rgba(1, 1, 1, 1), 0.5)
    readonly property var mdOpts: ({ mono: Theme.fontMono, codeBg: String(chipBg), codeFg: String(Theme.label), linkFg: String(Theme.accent), codePx: 11.5 })
    function label(s) { return upper ? String(s).toUpperCase() : s; }
    function html(md) { return Md.inline(md, mdOpts); }
    function para(inner) { return "<div style=\"line-height:120%\">" + inner + "</div>"; }

    width: 392
    height: Math.min(maxH, head.height + 1 + bodyH + chipsBox.height + inputBox.height + inputBox.anchors.bottomMargin)
    readonly property real fixedH: head.height + 1 + chipsBox.height + inputBox.height + inputBox.anchors.bottomMargin
    readonly property real bodyH: Math.max(60, Math.min(body.contentHeight, maxH - fixedH))

    function focusInput() { input.forceActiveFocus(); }

    // presses on the card's padding must not fall through to the drawing layer (= a new circle)
    MouseArea {
        anchors.fill: parent
        anchors.margins: -6
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.ArrowCursor
        hoverEnabled: true
    }
    RectangularShadow {
        anchors.fill: bg
        radius: bg.radius
        offset.y: 30; blur: 80; spread: -6
        color: Qt.rgba(0, 0, 0, 0.8)
    }
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: card.sq ? 6 : Theme.radiusPanel
        color: card.cardBg
        border.width: 1
        border.color: Theme.white(Theme.glassOpaque ? 0.14 : 0.1)
    }
    // Telemetry corner brackets, 5 px outside the card
    Brackets {
        visible: Theme.cardBrackets
        anchors.fill: parent
        anchors.margins: -5
        inset: 0; len: 12; thick: 1.5
    }

    // ---- header ----
    Item {
        id: head
        width: parent.width; height: 40
        Rectangle {
            id: logo
            x: 13; anchors.verticalCenter: parent.verticalCenter
            width: 20; height: 20; radius: card.sq ? 3 : 6
            color: Theme.accent
            AskIcon { anchors.centerIn: parent; name: "spark"; size: 13; color: Theme.onAccent }
        }
        Text {
            id: who
            anchors.left: logo.right; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
            text: card.label("Claude")
            color: Theme.label
            font.family: card.upper ? Theme.fontLabel : Theme.fontUi
            font.pointSize: (card.upper ? 11.5 : 13) * 0.75
            font.weight: Font.DemiBold
            font.letterSpacing: card.upper ? 1.15 : 0
        }
        Text {
            anchors.left: who.right; anchors.leftMargin: 8
            anchors.right: time.left; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            // "Ghostty · pnpm dev" (the title up to its first " — " part: apps put paths / app names after it)
            text: card.label([card.session.app, String(card.session.title).split(/\s+[—–|-]\s+/)[0]].filter(s => s).join(" · "))
            color: Theme.label3
            font.family: Theme.fontLabel; font.pointSize: 9.5 * 0.75; font.weight: Font.Medium
            font.letterSpacing: 0.95
            elide: Text.ElideRight
        }
        Text {
            id: time
            anchors.right: close.left; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: card.session.modelLabel + " · " + (card.session.firstMs < 0 ? (card.session.busy ? "…" : "—") : (card.session.firstMs / 1000).toFixed(1) + " s")
            color: Theme.label3
            font.family: Theme.fontLabel; font.pointSize: 10.5 * 0.75; font.weight: Font.Medium
            font.features: { "tnum": 1 }
        }
        Rectangle {
            id: close
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: card.sq ? 3 : 6
            color: xm.containsMouse ? Theme.fill : "transparent"
            Glyph { anchors.centerIn: parent; name: "x"; size: 10; color: Theme.label2 }
            MouseArea { id: xm; anchors.fill: parent; hoverEnabled: true; onClicked: card.closeRequested() }
        }
    }
    Rectangle { id: sep; y: head.height; width: parent.width; height: 1; color: Theme.sep }

    // ---- body ----
    Flickable {
        id: body
        y: head.height + 1
        width: parent.width
        height: card.bodyH
        clip: true
        contentWidth: width
        contentHeight: col.height + 16
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        // follow the stream unless the reader scrolled up
        property bool stick: true
        onMovementEnded: stick = contentY >= contentHeight - height - 4
        onContentHeightChanged: if (stick) contentY = Math.max(0, contentHeight - height)
        onHeightChanged: if (stick) contentY = Math.max(0, contentHeight - height)
        Connections {
            target: card.session
            function onTurnsChanged() { body.stick = true; }
        }

        Column {
            id: col
            x: 15; y: 13
            width: body.width - 30
            spacing: 0
            Repeater {
                model: card.session.turns.length
                Loader {
                    id: turn
                    required property int index
                    readonly property var tdata: card.session.turns[index] ?? ({ kind: "" })
                    width: col.width
                    sourceComponent: tdata.kind === "answer" ? answerC : tdata.kind === "you" ? youC : tdata.kind === "label" ? labelC : tdata.kind === "error" ? errorC : null
                    // components read the turn through the loader
                    property var turnData: tdata
                }
            }
            // waiting for the first token
            Item {
                visible: card.session.waiting
                width: col.width; height: visible ? 32 : 0
                Row {
                    y: 2
                    spacing: 9
                    height: 22
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: 3
                            Rectangle {
                                id: dot
                                required property int index
                                width: 5; height: 5; radius: card.sq ? 0 : 2.5
                                color: Theme.accent
                                opacity: 0.25
                                SequentialAnimation on opacity {
                                    running: card.session.waiting
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: dot.index * 150 }
                                    NumberAnimation { to: 1; duration: 400; easing.type: Easing.InOutSine }
                                    NumberAnimation { to: 0.25; duration: 600 - dot.index * 0; easing.type: Easing.InOutSine }
                                    PauseAnimation { duration: (2 - dot.index) * 150 }
                                }
                            }
                        }
                    }
                    // shimmering label (mock .ak-shim): a light band slides through the text
                    Item {
                        id: shim
                        anchors.verticalCenter: parent.verticalCenter
                        width: shimText.implicitWidth; height: shimText.implicitHeight
                        Text {
                            id: shimText
                            text: card.session.waitText
                            color: "white"
                            font.family: Theme.fontUi; font.pointSize: 12.5 * 0.75
                            visible: false
                            layer.enabled: true
                        }
                        Item {
                            id: shimSrc
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            clip: true
                            Rectangle {
                                width: shim.width * 2.2; height: shim.height
                                property real p: 0
                                x: -width + p * (shim.width + width)
                                NumberAnimation on p { from: 0; to: 1; duration: 1400; loops: Animation.Infinite; running: card.session.waiting }
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Theme.label3 }
                                    GradientStop { position: 0.45; color: Theme.label }
                                    GradientStop { position: 0.9; color: Theme.label3 }
                                }
                            }
                            Rectangle { z: -1; anchors.fill: parent; color: Theme.label3 }
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: shimSrc
                            maskEnabled: true
                            maskSource: shimText
                        }
                    }
                }
            }
        }
    }

    // scrolled: the top edge fades under the header instead of cutting a line in half
    Rectangle {
        y: body.y; width: parent.width; height: 14
        visible: body.contentY > 2
        gradient: Gradient {
            GradientStop { position: 0; color: card.cardBg }
            GradientStop { position: 1; color: Qt.rgba(card.cardBg.r, card.cardBg.g, card.cardBg.b, 0) }
        }
    }

    // ---- turn components ----
    Component {
        id: labelC
        Item {
            readonly property var t: parent ? parent.turnData : ({})
            width: col.width; height: 37
            Text {
                id: lt
                y: 14
                text: card.label(parent.t.text ?? "")
                color: Theme.label3
                font.family: Theme.fontLabel; font.pointSize: 9.5 * 0.75; font.weight: Font.Medium; font.letterSpacing: 0.95
            }
            Rectangle { anchors.left: lt.right; anchors.leftMargin: 8; anchors.right: parent.right; anchors.verticalCenter: lt.verticalCenter; height: 1; color: Theme.sep }
        }
    }
    Component {
        id: youC
        Item {
            readonly property var t: parent ? parent.turnData : ({})
            width: col.width
            height: bubble.height + 22
            Rectangle {
                id: bubble
                anchors.right: parent.right
                y: 12
                width: Math.min(parent.width * 0.86, yt.implicitWidth + 22)
                height: yt.height + 12
                radius: card.sq ? 4 : 12
                color: Theme.fill2
                Text {
                    id: yt
                    x: 11; y: 6
                    width: bubble.width - 22
                    text: parent.parent.t.text ?? ""
                    wrapMode: Text.Wrap
                    color: Theme.label
                    font.family: Theme.fontUi; font.pointSize: 12.5 * 0.75
                    font.features: { "calt": 0, "liga": 0 }
                }
            }
        }
    }
    Component {
        id: errorC
        Item {
            readonly property var t: parent ? parent.turnData : ({})
            width: col.width
            height: et.height + 14
            Rectangle { x: 0; y: 3; width: 2; height: et.height; color: Theme.accent }
            Glyph { x: 10; y: 4; name: "x"; size: 13; color: Theme.accent }
            TextEdit {
                id: et
                x: 30; y: 3
                width: parent.width - 30
                readOnly: true; selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                text: card.para(card.html(parent.t.text ?? ""))
                color: Theme.label
                selectionColor: Theme.rgba(Theme.t.color.accent, 0.35)
                font.family: Theme.fontUi; font.pixelSize: 13
                font.features: { "calt": 0, "liga": 0 }   // also reaches the mono `code` spans: no => / === ligatures
            }
        }
    }
    Component {
        id: answerC
        Column {
            id: ans
            readonly property var t: parent ? parent.turnData : ({})
            readonly property bool isLive: t.live === true
            readonly property var blocks: Md.parse(isLive ? card.session.liveText : (t.text ?? ""))
            width: col.width
            spacing: 0
            Repeater {
                model: ans.blocks.length
                Loader {
                    id: blk
                    required property int index
                    readonly property var b: ans.blocks[index] ?? ({ t: "" })
                    readonly property bool caret: ans.isLive && index === ans.blocks.length - 1
                    width: ans.width
                    sourceComponent: b.t === "code" ? codeC : textC
                    property var bdata: b
                    property bool withCaret: caret
                }
            }
        }
    }
    Component {
        id: textC
        Item {
            id: tb
            readonly property var b: parent ? parent.bdata : ({})
            readonly property bool caret: parent ? parent.withCaret : false
            readonly property bool li: b.t === "li"
            width: parent ? parent.width : 0
            height: te.height + 10
            Text {
                visible: tb.li
                y: 1
                text: tb.b.mark || "•"
                color: tb.b.mark ? Theme.label2 : Theme.accent
                font.family: tb.b.mark ? Theme.fontLabel : Theme.fontUi; font.pixelSize: 13
                lineHeight: 1.56
            }
            TextEdit {
                id: te
                x: tb.li ? 16 : 0
                width: tb.width - x
                readOnly: true; selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                text: card.para(card.html(tb.b.md ?? ""))
                color: Theme.label
                selectedTextColor: Theme.label
                selectionColor: Theme.rgba(Theme.t.color.accent, 0.35)
                font.family: Theme.fontUi; font.pixelSize: 13
                font.features: { "calt": 0, "liga": 0 }   // also reaches the mono `code` spans: no => / === ligatures
            }
            Caret {
                visible: tb.caret
                readonly property rect r: { te.text; return te.positionToRectangle(te.length); }
                x: te.x + r.x + 2
                y: te.y + r.y + (r.height - height) / 2
            }
        }
    }
    // solid while text arrives, blinks when the stream pauses (mock .ak-caret)
    component Caret: Rectangle {
        id: caretR
        width: 7; height: 13; radius: card.sq ? 0 : 1
        color: Theme.accent
        property bool blink: true
        readonly property string kick: card.session.liveText
        onKickChanged: { blink = true; blinkT.restart(); }
        opacity: blink ? 1 : 0
        Timer { id: blinkT; running: caretR.visible; interval: 450; repeat: true; onTriggered: caretR.blink = !caretR.blink }
    }
    Component {
        id: codeC
        Item {
            id: cb
            readonly property var b: parent ? parent.bdata : ({ lines: [] })
            readonly property bool caret: parent ? parent.withCaret : false
            width: parent ? parent.width : 0
            height: box.height + 12
            Rectangle {
                id: box
                y: 2
                width: parent.width
                height: 26 + lines.height + 10
                radius: card.sq ? 4 : 8
                color: card.wellBg
                border.width: 1
                border.color: Theme.hair
                clip: true
                Item {
                    width: parent.width; height: 26
                    Text {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - copyBtn.width - 20
                        text: card.label(String(cb.b.file || cb.b.lang || "code").replace(/:(\d+)$/, " · $1"))
                        color: Theme.label3
                        font.family: Theme.fontLabel; font.pointSize: 9.5 * 0.75; font.weight: Font.Medium; font.letterSpacing: 0.76
                        elide: Text.ElideMiddle
                    }
                    Rectangle {
                        id: copyBtn
                        anchors.right: parent.right; anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: cr.width + 14; height: 20; radius: card.sq ? 3 : 5
                        color: cm.containsMouse ? Theme.fill : "transparent"
                        visible: !cb.b.open
                        Row {
                            id: cr
                            anchors.centerIn: parent
                            spacing: 5
                            AskIcon { anchors.verticalCenter: parent.verticalCenter; name: cb.copied ? "check" : "copy"; size: 11; color: cb.copied ? Theme.green : Theme.label2 }
                            Text { anchors.verticalCenter: parent.verticalCenter; text: cb.copied ? "Copied" : "Copy"; color: Theme.label2; font.family: Theme.fontUi; font.pointSize: 10.5 * 0.75 }
                        }
                        MouseArea {
                            id: cm
                            anchors.fill: parent; hoverEnabled: true
                            onClicked: {
                                // a diff copies the new version (context + added lines)
                                const ls = cb.b.diff ? cb.b.lines.filter(l => l.g !== "-") : cb.b.lines;
                                card.session.copy(ls.map(l => l.s).join("\n"));
                                cb.copied = true; copiedT.restart();
                            }
                        }
                        Timer { id: copiedT; interval: 1400; onTriggered: cb.copied = false }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.sep }
                }
                Flickable {
                    id: lines
                    y: 31
                    width: parent.width
                    height: rows.height
                    contentWidth: Math.max(width, rows.width)
                    contentHeight: rows.height
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true
                    Column {
                        id: rows
                        width: Math.max(lines.width, implicitWidth)
                        Repeater {
                            model: cb.b.lines ?? []
                            Rectangle {
                                id: row
                                required property var modelData
                                required property int index
                                readonly property bool del: modelData.g === "-"
                                readonly property bool add: modelData.g === "+"
                                width: Math.max(lines.width, lt.x + lt.implicitWidth + 10)
                                implicitWidth: lt.x + lt.implicitWidth + 10
                                height: 19.5
                                color: del ? Theme.rgba(Theme.t.color.red, 0.11) : add ? Theme.rgba(Theme.t.color.green, 0.11) : "transparent"
                                Text {
                                    x: 10; width: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.g
                                    opacity: 0.75
                                    color: row.del ? card.delFg : row.add ? card.addFg : Theme.label
                                    font.family: Theme.fontMono; font.pointSize: 11.5 * 0.75; font.features: { "calt": 0, "liga": 0 }
                                }
                                Text {
                                    id: lt
                                    x: cb.b.diff ? 24 : 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.modelData.s
                                    textFormat: Text.PlainText
                                    color: row.del ? card.delFg : row.add ? card.addFg : Theme.label
                                    font.family: Theme.fontMono; font.pointSize: 11.5 * 0.75; font.features: { "calt": 0, "liga": 0 }
                                }
                                Caret {
                                    visible: cb.caret && cb.b.open && row.index === (cb.b.lines.length - 1)
                                    height: 12; width: 6
                                    x: lt.x + lt.implicitWidth + 1
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }
                    }
                }
            }
            property bool copied: false
        }
    }

    // ---- chips ----
    Item {
        id: chipsBox
        anchors.bottom: inputBox.top
        width: parent.width
        height: card.session.answered ? flow.height + 14 : 0
        visible: height > 0
        Flow {
            id: flow
            x: 13; y: 2
            width: parent.width - 26
            spacing: 6
            Repeater {
                model: [
                    { id: "copy", icon: "copy", text: "Copy text" },
                    { id: "more", icon: "sparkle", text: "Explain more" },
                    { id: "send", icon: "send", text: "Send to agent", hot: true },
                    { id: "tr", icon: "translate", text: "Translate" },
                    { id: "csv", icon: "table", text: "Table → CSV" },
                    { id: "lens", icon: "search", text: "Lens" }
                ]
                Rectangle {
                    id: chip
                    required property var modelData
                    required property int index
                    readonly property bool isUsed: card.session.used[modelData.id] !== undefined
                    readonly property string usedLabel: card.session.used[modelData.id] ?? ""
                    readonly property bool off: card.session.busy && modelData.id !== "copy" && modelData.id !== "lens"
                    width: chipRow.width + 18
                    height: 27
                    radius: card.sq ? 4 : 14
                    color: modelData.hot ? Theme.rgba(Theme.t.color.accent, cm2.containsMouse ? 0.22 : 0.15) : cm2.containsMouse ? Theme.fill2 : Theme.fill
                    border.width: modelData.hot ? 1 : Theme.rimWidth
                    border.color: modelData.hot ? Theme.rgba(Theme.t.color.accent, 0.55) : Theme.white(0.14)
                    Behavior on color { ColorAnimation { duration: Theme.durHover } }
                    // staggered entrance (mock: 55 ms apart, 5 px rise)
                    property bool inn: false
                    opacity: !inn ? 0 : off ? 0.45 : 1
                    transform: Translate { y: chip.inn ? 0 : 5; Behavior on y { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } } }
                    Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                    scale: cm2.pressed ? 0.96 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.durPop } }
                    Timer { running: card.session.answered && !chip.inn; interval: 30 + chip.index * 55; onTriggered: chip.inn = true }
                    Connections { target: card.session; function onAnsweredChanged() { if (!card.session.answered) chip.inn = false; } }
                    Row {
                        id: chipRow
                        x: 8; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        AskIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: chip.isUsed ? "check" : chip.modelData.icon
                            size: 13
                            color: chip.isUsed ? Theme.green : chip.modelData.hot ? Theme.accent : Theme.label2
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: card.label(chip.usedLabel !== "" ? chip.usedLabel : chip.modelData.text)
                            color: chip.isUsed && !chip.modelData.hot ? Theme.label2 : Theme.label
                            font.family: card.upper ? Theme.fontLabel : Theme.fontUi
                            font.pointSize: (card.upper ? 10.5 : 12) * 0.75
                            font.weight: Font.Medium
                            font.letterSpacing: card.upper ? 0.5 : 0
                        }
                    }
                    MouseArea {
                        id: cm2
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        enabled: !chip.off
                        onClicked: card.session.chip(chip.modelData.id)
                    }
                }
            }
        }
    }

    // ---- follow-up ----
    Rectangle {
        id: inputBox
        anchors.bottom: parent.bottom; anchors.bottomMargin: 10
        x: 10; width: parent.width - 20; height: 38
        radius: card.sq ? 4 : 10
        color: card.wellBg
        border.width: 1
        border.color: input.activeFocus ? Theme.rgba(Theme.t.color.accent, 0.6) : Theme.hair
        Behavior on border.color { ColorAnimation { duration: Theme.durPop } }
        TextInput {
            id: input
            x: 12; width: parent.width - 12 - ret.width - 12
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.label
            font.family: Theme.fontUi; font.pointSize: 12.5 * 0.75
            selectByMouse: true
            clip: true
            selectionColor: Theme.rgba(Theme.t.color.accent, 0.35)
            cursorDelegate: Rectangle { width: 1.5; color: Theme.accent; visible: input.cursorVisible }
            Text {
                visible: input.text === "" && !input.preeditText
                anchors.verticalCenter: parent.verticalCenter
                text: "Ask a follow-up…"
                color: Theme.label3
                font: input.font
            }
            Keys.onReturnPressed: send()
            Keys.onEnterPressed: send()
            Keys.onEscapePressed: card.closeRequested()
            function send() { if (card.session.followUp(text)) text = ""; }
        }
        Keycap {
            id: ret
            anchors.right: parent.right; anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            text: "↵"
            MouseArea { anchors.fill: parent; onClicked: input.send() }
        }
    }
}

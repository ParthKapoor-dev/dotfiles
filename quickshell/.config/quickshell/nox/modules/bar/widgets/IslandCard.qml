pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components

// The island's expanded card for one IslandEntry (design mock .isl-x), drawn inside the grown pill:
//   header   icon tile (accent / red / cover), kicker, bold title, big tabular number (or eq bars)
//   body     what the agent asks (accent-ruled box), progress (dot matrix in Telemetry), times,
//            a mono info line, mic levels, rows (other sessions, downloads, shelf items)
//   actions  1-3 buttons (primary in accent; no label = icon button) + tabs for every live thing
// emits acted(close) after an action (close = the action leaves the card's context, e.g. Jump),
// pick(kind) for a tab.
Column {
    id: root
    property IslandEntry entry: null
    property var live: []                // every live entry, for the tabs
    property int frame: 0                // Island's 12 Hz loop clock (eq bars); 0 = still
    property var micLevels: []
    signal acted(bool close)
    signal pick(string kind)
    readonly property string kind: entry?.kind ?? ""
    readonly property bool mono: Theme.labelsMono && Theme.square
    readonly property real rSmall: Theme.square ? 3 : 7
    spacing: 0

    // ---- header -----------------------------------------------------------------------------
    Item {
        width: parent.width
        height: 34
        Rectangle {
            id: tile
            width: 34; height: 34
            radius: Theme.square ? 2 : 9
            readonly property string style: root.entry?.tile ?? ""
            color: style === "acc" ? Theme.accent : style === "rec" ? Theme.rgba(Theme.t.color.red, 0.16) : Theme.fill2
            clip: true
            Glyph {
                visible: !(root.kind === "music" && cover.status === Image.Ready)
                anchors.centerIn: parent
                name: root.entry?.glyph ?? ""
                size: 17
                color: tile.style === "acc" ? Theme.onAccent : tile.style === "rec" ? Theme.red : Theme.label
            }
            Image {
                id: cover
                visible: root.kind === "music"
                anchors.fill: parent
                source: root.kind === "music" && root.entry ? root.entry.art : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 68; sourceSize.height: 68
            }
        }
        Column {
            anchors.left: tile.right; anchors.leftMargin: 11
            anchors.right: rightBox.left; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Text {
                width: parent.width
                visible: text !== ""
                elide: Text.ElideRight
                text: root.entry?.kicker ?? ""
                color: Theme.label3
                font.family: Theme.fontLabel
                font.pixelSize: 10
                font.weight: Font.Medium
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 0.95
            }
            Text {
                width: parent.width
                elide: Text.ElideRight
                text: root.entry?.title ?? ""
                color: Theme.label
                font.family: root.mono ? Theme.fontLabel : Theme.fontUi
                font.pixelSize: root.mono ? 13 : 14
                font.weight: Font.DemiBold
                font.capitalization: root.mono ? Font.AllUppercase : Font.MixedCase
                font.letterSpacing: root.mono ? 0.6 : 0
            }
        }
        Item {
            id: rightBox
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.kind === "music" ? eq.width : big.text === "" ? 0 : big.implicitWidth
            height: 34
            Text {
                id: big
                visible: root.kind !== "music"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.entry?.big ?? ""
                color: (root.entry?.bigAccent ?? false) ? Theme.accent : Theme.label
                font.family: Theme.fontNumeric
                font.pixelSize: (root.entry?.bigLarge ?? false) ? 36 : Theme.square ? 20 : 22
                font.weight: Theme.numericWeight
                font.variableAxes: Theme.numericAxes
                font.features: ({ "tnum": 1 })
            }
            // music: eq bars instead of a number (mock: the card header's .isl-eq)
            Row {
                id: eq
                visible: root.kind === "music"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 13
                spacing: 2
                Repeater {
                    model: [0, 300, 600, 150]
                    Rectangle {
                        required property int modelData
                        readonly property bool play: root.entry?.mode === "play"
                        readonly property real p: ((root.frame * 83.33 + modelData) % 900) / 900
                        anchors.bottom: parent.bottom
                        width: 2.5; radius: Theme.square ? 0 : 1
                        height: !play ? 3 : 13 * (0.35 + 0.65 * (0.5 - 0.5 * Math.cos(2 * Math.PI * p)))
                        color: play ? Theme.accent : Theme.label3
                    }
                }
            }
        }
    }

    // ---- body -------------------------------------------------------------------------------
    Item { width: 1; height: 12 }
    // what the agent asks you (mock .isl-q)
    Rectangle {
        visible: (root.entry?.quote ?? "") !== ""
        width: parent.width
        height: visible ? q.implicitHeight + 16 : 0
        radius: root.rSmall
        color: Theme.rgba(Theme.t.color.accent, 0.09)
        Rectangle { width: 2; height: parent.height; color: Theme.accent }
        Text {
            id: q
            x: 10; y: 8
            width: parent.width - 20
            text: root.entry?.quote ?? ""
            color: Theme.label
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            font.family: Theme.fontMono
            font.pixelSize: 11
            lineHeight: 1.25
        }
    }
    Item { visible: (root.entry?.quote ?? "") !== ""; width: 1; height: 8 }

    // progress: a dot matrix in Telemetry (mock .isl-pr), a 4px bar otherwise
    Item {
        id: prog
        readonly property real v: Math.max(0, Math.min(1, root.entry?.progress ?? 0))
        visible: (root.entry?.progress ?? -1) >= 0
        width: parent.width
        height: visible ? (Theme.square ? 7 : 4) + 10 : 0
        Row {
            visible: Theme.square
            y: 2
            spacing: 3
            Repeater {
                model: Math.floor((prog.width + 3) / 6)
                Rectangle {
                    required property int index
                    y: 2
                    width: 3; height: 3; radius: 1.5
                    color: index < Math.round(prog.v * Math.floor((prog.width + 3) / 6)) ? Theme.accent : Theme.white(0.16)
                }
            }
        }
        Rectangle {
            visible: !Theme.square
            y: 2
            width: parent.width; height: 4; radius: 2
            color: Theme.fill2
            Rectangle { width: parent.width * prog.v; height: parent.height; radius: 2; color: Theme.accent }
        }
    }
    Item {
        visible: (root.entry?.times ?? []).length === 2
        width: parent.width
        height: visible ? 14 : 0
        Text { text: root.entry?.times?.[0] ?? ""; color: Theme.label3; font.family: Theme.fontLabel; font.pixelSize: 10; font.weight: Font.Medium; font.features: ({ "tnum": 1 }) }
        Text { anchors.right: parent.right; text: root.entry?.times?.[1] ?? ""; color: Theme.label3; font.family: Theme.fontLabel; font.pixelSize: 10; font.weight: Font.Medium; font.features: ({ "tnum": 1 }) }
    }
    Text {
        visible: text !== ""
        width: parent.width
        elide: Text.ElideRight
        text: root.entry?.info ?? ""
        textFormat: Text.PlainText
        color: Theme.label3
        font.family: Theme.fontMono
        font.pixelSize: 11
        lineHeight: 1.35
    }
    // mic levels (mock .isl-lv): the real input level, newest on the right
    Row {
        visible: root.entry?.levels ?? false
        width: parent.width
        height: visible ? 26 : 0
        spacing: 3
        readonly property int n: 30
        Repeater {
            model: parent.n
            Item {
                id: lv
                required property int index
                readonly property var src: root.micLevels
                readonly property real v: Math.max(0, Math.min(1, Number(src[src.length - 30 + index] ?? 0)))
                width: (root.width - 29 * 3) / 30
                height: 26
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4 + lv.v * 18
                    radius: Theme.square ? 0 : 1
                    color: lv.index % 3 === 2 ? Theme.accent : Theme.label3
                }
            }
        }
    }
    // rows: other sessions, downloads, shelf items
    Column {
        visible: (root.entry?.rows ?? []).length > 0
        width: parent.width
        topPadding: 4
        Repeater {
            model: root.entry?.rows ?? []
            Item {
                id: row
                required property var modelData
                width: parent?.width ?? 0
                height: 22
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: -6; anchors.rightMargin: -6
                    radius: root.rSmall
                    color: Theme.fill
                    opacity: rm.containsMouse && !!row.modelData.act ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
                }
                Rectangle {
                    id: rdot
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5; height: 5; radius: Theme.square ? 0 : 2.5
                    color: row.modelData.on ? Theme.accent : Theme.label3
                }
                Text {
                    id: rt
                    anchors.left: rdot.right; anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width * 0.55)
                    elide: Text.ElideRight
                    text: row.modelData.title ?? ""
                    color: Theme.label2
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
                Text {
                    anchors.left: rt.right; anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    text: row.modelData.sub ?? ""
                    color: Theme.label3
                    font.family: Theme.fontMono
                    font.pixelSize: 11
                }
                MouseArea {
                    id: rm
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !!row.modelData.act
                    onClicked: { row.modelData.act(); root.acted(row.modelData.close ?? true); }
                }
            }
        }
    }

    // ---- actions + tabs ---------------------------------------------------------------------
    Item { width: 1; height: 12 }
    Item {
        id: foot
        // tabs share the row with the buttons while they fit, else they get a row of their own
        readonly property bool fits: acts.width + 12 + tabs.width <= width
        width: parent.width
        height: fits || !tabs.visible ? 28 : 28 + 8 + 24
        Row {
            id: acts
            spacing: 7
            Repeater {
                model: root.entry?.actions ?? []
                Rectangle {
                    id: btn
                    required property var modelData
                    readonly property bool icon: (modelData.label ?? "") === ""
                    readonly property bool pri: modelData.pri ?? false
                    readonly property bool ok: modelData.enabled ?? true
                    width: icon ? 32 : bl.implicitWidth + 24
                    height: 28
                    radius: Theme.square ? 3 : 14
                    color: pri ? Theme.accent : bm.containsMouse ? Theme.fill3 : Theme.fill2
                    Behavior on color { ColorAnimation { duration: Theme.durHover } }
                    opacity: ok ? (pri && bm.containsMouse ? 0.9 : 1) : 0.35
                    scale: bm.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.OutCubic } }
                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Glyph {
                            id: bg
                            visible: btn.icon
                            anchors.verticalCenter: parent.verticalCenter
                            name: btn.modelData.icon ?? ""
                            size: 13
                            color: btn.pri ? Theme.onAccent : Theme.label
                        }
                        Text {
                            id: bl
                            visible: !btn.icon
                            anchors.verticalCenter: parent.verticalCenter
                            text: btn.modelData.label ?? ""
                            color: btn.pri ? Theme.onAccent : Theme.label
                            font.family: root.mono ? Theme.fontLabel : Theme.fontUi
                            font.pixelSize: root.mono ? 11 : 12
                            font.weight: Font.Medium
                            font.capitalization: root.mono ? Font.AllUppercase : Font.MixedCase
                            font.letterSpacing: root.mono ? 0.74 : 0
                        }
                    }
                    MouseArea {
                        id: bm
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: btn.ok
                        onClicked: { btn.modelData.act(); root.acted(btn.modelData.close ?? false); }
                    }
                }
            }
        }
        // tabs (mock .isl-tab): every live thing; the shown one is on, a hot one is accent
        Row {
            id: tabs
            visible: root.live.length > 1
            anchors.right: parent.right
            y: foot.fits ? 2 : 36
            spacing: 4
            Repeater {
                model: root.live.length > 1 ? root.live : []
                Rectangle {
                    id: tab
                    required property var modelData
                    readonly property bool on: modelData === root.entry
                    width: 24; height: 24
                    radius: Theme.square ? 3 : 6
                    color: on ? Theme.fill2 : tm.containsMouse ? Theme.fill : Theme.white(0)
                    Behavior on color { ColorAnimation { duration: Theme.durHover } }
                    Glyph {
                        anchors.centerIn: parent
                        name: tab.modelData.glyph
                        size: 12
                        color: tab.modelData.hot ? Theme.accent : tab.on || tm.containsMouse ? Theme.label : Theme.label3
                    }
                    MouseArea { id: tm; anchors.fill: parent; hoverEnabled: true; onClicked: root.pick(tab.modelData.kind) }
                }
            }
        }
    }
}

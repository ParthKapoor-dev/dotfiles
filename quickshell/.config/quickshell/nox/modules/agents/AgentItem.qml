pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts as QL
import qs.core
import qs.components
import qs.services

// One row of the agents panel (AgentsPanel): kind "need" (a permission request or an error:
// the exact request + Jump), "done" (a Done card: summary, diff stat, files, PR, Open diff /
// Open PR / Continue / Jump / Dismiss) or "work" (one line: project · task · elapsed · last action).
// The parent owns selection and keys; actions come back through act(what).
Item {
    id: root
    required property var session
    property string kind: "work"
    property var turn: ({})
    property bool selected: false
    property bool replying: false
    property real now: Date.now()
    signal activate()                 // primary (Enter / click)
    signal act(string what)           // jump | diff | pr | reply | dismiss
    signal sendReply(string text)
    signal cancelReply()
    signal hovered()

    readonly property var s: session ?? ({})
    readonly property bool err: s.status === "error"
    readonly property var perm: s.perm ?? ({})
    readonly property string primary: kind === "done" ? ((turn?.nfiles ?? 0) > 0 ? "diff" : "jump") : "jump"
    readonly property string mono: Theme.fontLabel
    implicitHeight: kind === "work" && !replying ? 30 : body.implicitHeight + 22

    Rectangle {
        anchors.fill: parent
        radius: Theme.square ? 0 : 6
        color: root.selected ? Theme.white(0.075) : ma.containsMouse ? Theme.white(0.04) : "transparent"
        border.width: root.selected ? 1 : 0
        border.color: root.kind === "need" && !root.err ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.55) : Theme.white(0.14)
    }
    // the selected item's left edge (accent while it waits for you)
    Rectangle {
        visible: root.selected
        width: 2; height: parent.height - 12
        anchors.verticalCenter: parent.verticalCenter
        color: root.kind === "need" ? (root.err ? Theme.red : Theme.accent) : Theme.label
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: root.hovered()
        onClicked: root.activate()
    }

    // ---- one line: working ----
    QL.RowLayout {
        visible: root.kind === "work" && !root.replying
        x: 12; width: parent.width - 24
        height: 30
        spacing: 9
        Item {
            implicitWidth: 10; implicitHeight: 10
            Rectangle { anchors.fill: parent; radius: Theme.square ? 1 : 5; color: "transparent"; border.width: 1.5; border.color: Theme.fill3 }
            Item {
                anchors.fill: parent
                RotationAnimation on rotation { running: root.kind === "work" && root.visible; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                Rectangle { x: 2; width: parent.width - 4; height: 1.5; color: Theme.label }
            }
        }
        Text {
            text: root.s.project ?? "?"
            color: Theme.label
            font.family: root.mono; font.pixelSize: 11; font.weight: Font.DemiBold
            font.capitalization: Font.AllUppercase; font.letterSpacing: 1.0
        }
        Text {
            QL.Layout.fillWidth: true
            QL.Layout.preferredWidth: 220
            text: root.s.lastPrompt || root.s.firstPrompt || ""
            elide: Text.ElideRight
            color: Theme.label2
            font.family: Theme.fontUi; font.pixelSize: 12
        }
        Text {
            text: Agents.hms(root.now - (root.s.since ?? root.now))
            color: Theme.label
            font.family: root.mono; font.pixelSize: 11; font.features: ({ "tnum": 1 })
        }
        Text {
            QL.Layout.fillWidth: true
            QL.Layout.preferredWidth: 90
            QL.Layout.maximumWidth: 130
            text: Agents.lastAction(root.s)
            elide: Text.ElideRight
            color: Theme.label3
            font.family: Theme.fontMono; font.pixelSize: 11
        }
    }

    // ---- cards: needs you / done (and a working row while replying) ----
    Column {
        id: body
        visible: root.kind !== "work" || root.replying
        x: 12; y: 11
        width: parent.width - 24
        spacing: 7

        // status · PROJECT · branch ........ time
        Item {
            width: parent.width
            height: 16
            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10; height: 10
                    Rectangle {
                        visible: root.kind === "need" && !root.err
                        anchors.centerIn: parent
                        width: 7; height: 7
                        color: Theme.accent
                        radius: Theme.square ? 0 : 3.5
                        Rectangle {
                            anchors.centerIn: parent
                            width: 7; height: 7
                            radius: parent.radius
                            color: "transparent"
                            border.width: 1.5; border.color: Theme.accent
                            SequentialAnimation on scale { running: root.kind === "need" && root.visible; loops: Animation.Infinite; NumberAnimation { from: 1; to: 2.4; duration: 1000; easing.type: Easing.OutCubic } PauseAnimation { duration: 300 } }
                            SequentialAnimation on opacity { running: root.kind === "need" && root.visible; loops: Animation.Infinite; NumberAnimation { from: 0.8; to: 0; duration: 1000; easing.type: Easing.OutCubic } PauseAnimation { duration: 300 } }
                        }
                    }
                    AgentGlyph {
                        visible: root.err || root.kind === "done"
                        anchors.centerIn: parent
                        name: root.err ? "alert" : "check"
                        size: 11
                        color: root.err ? Theme.red : Theme.green
                    }
                    Rectangle {
                        visible: root.kind === "work"
                        anchors.centerIn: parent
                        width: 7; height: 7
                        color: Theme.label
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.s.project ?? "?"
                    color: Theme.label
                    font.family: root.mono; font.pixelSize: 12; font.weight: Font.DemiBold
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 1.2
                }
                AgentGlyph {
                    visible: !!root.s.branch
                    anchors.verticalCenter: parent.verticalCenter
                    name: "branch"; size: 10; color: Theme.label3
                }
                Text {
                    visible: !!root.s.branch
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.s.branch ?? ""
                    color: Theme.label3
                    width: Math.min(implicitWidth, body.width * 0.4)
                    elide: Text.ElideRight
                    font.family: Theme.fontMono; font.pixelSize: 11
                }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (root.kind === "need" ? (root.err ? "error · " : "waiting · ") + Agents.hms(root.now - (root.s.since ?? root.now))
                     : root.kind === "done" ? Agents.kindName(root.s) + " · " + Agents.ago(root.s.turn?.end ?? root.now)
                     : Agents.hms(root.now - (root.s.since ?? root.now)))
                color: root.kind === "need" && !root.err ? Theme.accent : root.err ? Theme.red : Theme.label3
                font.family: root.mono; font.pixelSize: 10
                font.capitalization: Font.AllUppercase; font.letterSpacing: 0.9
                font.features: ({ "tnum": 1 })
            }
        }

        // the task
        Text {
            width: parent.width
            visible: text !== ""
            text: root.s.lastPrompt || root.s.firstPrompt || ""
            elide: Text.ElideRight
            color: Theme.label2
            font.family: Theme.fontUi; font.pixelSize: 12
        }

        // needs you: the request, exactly
        Rectangle {
            visible: root.kind === "need"
            width: parent.width
            height: q.implicitHeight + 16
            color: root.err ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.07) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.07)
            Rectangle { width: 2; height: parent.height; color: root.err ? Theme.red : Theme.accent }
            Column {
                id: q
                x: 11; y: 8
                width: parent.width - 20
                spacing: 5
                Text {
                    text: root.err ? "Error" : "Permission" + (root.perm.tool ? " · " + root.perm.tool : "")
                    color: root.err ? Theme.red : Theme.accent
                    font.family: root.mono; font.pixelSize: 10; font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 1.1
                }
                Text {
                    width: parent.width
                    visible: text !== ""
                    text: root.err ? (root.s.error ?? "") : (root.perm.desc ?? "")
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    color: Theme.label
                    font.family: Theme.fontUi; font.pixelSize: 12
                }
                Rectangle {
                    visible: !root.err && !!root.perm.cmd
                    width: Math.min(parent.width, cmdT.implicitWidth + 14)
                    height: cmdT.implicitHeight + 8
                    color: Qt.rgba(0, 0, 0, 0.4)
                    border.width: 1; border.color: Theme.white(0.1)
                    Text {
                        id: cmdT
                        x: 7; y: 4
                        width: Math.min(implicitWidth, q.width - 14)
                        text: root.perm.cmd ?? ""
                        wrapMode: Text.WrapAnywhere
                        maximumLineCount: 4
                        elide: Text.ElideRight
                        color: Theme.label
                        font.family: Theme.fontMono; font.pixelSize: 11
                    }
                }
            }
        }

        // done: what the turn did
        Text {
            visible: root.kind === "done" && text !== ""
            width: parent.width
            text: root.turn?.say || root.s.turn?.say || root.s.summary || ""
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            color: Theme.label
            font.family: Theme.fontUi; font.pixelSize: 12
        }
        Row {
            visible: root.kind === "done"
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: (root.turn?.nfiles ?? 0) > 0
                text: "+" + (root.turn?.add ?? 0)
                color: Theme.green
                font.family: Theme.fontMono; font.pixelSize: 11; font.features: ({ "tnum": 1 })
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: (root.turn?.nfiles ?? 0) > 0
                text: "−" + (root.turn?.del ?? 0)
                color: Theme.red
                font.family: Theme.fontMono; font.pixelSize: 11; font.features: ({ "tnum": 1 })
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.turn?.id ? ((root.turn.nfiles ?? 0) > 0 ? root.turn.nfiles + ((root.turn.nfiles === 1) ? " file" : " files") + (root.turn.exact === false ? " · some were dirty before" : "")
                                       : "no file changes") + ((root.turn.commits ?? 0) > 0 ? " · " + root.turn.commits + (root.turn.commits === 1 ? " commit" : " commits") : "")
                                    : "…"
                color: Theme.label3
                font.family: root.mono; font.pixelSize: 10
                font.capitalization: Font.AllUppercase; font.letterSpacing: 0.9
            }
            Rectangle {
                visible: !!root.turn?.pr
                anchors.verticalCenter: parent.verticalCenter
                width: prT.implicitWidth + 12; height: 17
                color: Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.1)
                border.width: 1; border.color: Qt.rgba(Theme.green.r, Theme.green.g, Theme.green.b, 0.4)
                Text {
                    id: prT
                    anchors.centerIn: parent
                    text: "PR #" + (root.turn?.prNum ?? "") + (root.turn?.prNew ? " opened" : "")
                    color: Theme.green
                    font.family: root.mono; font.pixelSize: 10; font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase; font.letterSpacing: 0.9
                }
            }
        }
        Flow {
            visible: root.kind === "done" && (root.turn?.files ?? []).length > 0
            width: parent.width
            spacing: 5
            Repeater {
                model: (root.turn?.files ?? []).slice(0, 4)
                Rectangle {
                    id: chip
                    required property var modelData
                    width: chipRow.implicitWidth + 10; height: 18
                    color: Theme.white(0.05)
                    border.width: 1; border.color: Theme.white(0.08)
                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 5
                        Text {
                            text: chip.modelData.m ?? "M"
                            color: chip.modelData.m === "A" ? Theme.green : chip.modelData.m === "D" ? Theme.red : Theme.orange
                            font.family: Theme.fontMono; font.pixelSize: 10; font.weight: Font.Bold
                        }
                        Text {
                            text: String(chip.modelData.p ?? "").replace(/^.*\//, "")
                            color: Theme.label2
                            font.family: Theme.fontMono; font.pixelSize: 10
                        }
                    }
                }
            }
            Text {
                visible: (root.turn?.nfiles ?? 0) > 4
                height: 18
                verticalAlignment: Text.AlignVCenter
                text: "+" + ((root.turn?.nfiles ?? 0) - 4)
                color: Theme.label3
                font.family: Theme.fontMono; font.pixelSize: 10
            }
        }

        // actions (needs you: the answer happens in the session's pane; see Agents.answer for the seam)
        Flow {
            visible: !root.replying
            width: parent.width
            spacing: 6
            topPadding: 2
            ActButton { visible: root.kind === "need"; text: "Answer in pane"; key: "↵"; primary: root.selected; onClicked: root.act("jump") }
            ActButton { visible: root.kind === "need" && root.err; text: "Reply"; key: "R"; onClicked: root.act("reply") }
            ActButton { visible: root.kind === "done" && (root.turn?.nfiles ?? 0) > 0; text: "Open diff"; key: root.primary === "diff" ? "↵" : ""; primary: root.selected && root.primary === "diff"; onClicked: root.act("diff") }
            ActButton { visible: root.kind === "done" && !!root.turn?.pr; text: "Open PR"; key: "P"; onClicked: root.act("pr") }
            ActButton { visible: root.kind === "done"; text: "Continue"; key: "R"; onClicked: root.act("reply") }
            ActButton { visible: root.kind === "done"; text: "Jump"; key: root.primary === "jump" ? "↵" : "J"; primary: root.selected && root.primary === "jump"; onClicked: root.act("jump") }
            ActButton { visible: root.kind === "done"; text: "Dismiss"; key: "D"; onClicked: root.act("dismiss") }
        }
        Loader {
            active: root.replying
            visible: active
            width: parent.width
            sourceComponent: ReplyBox {
                width: body.width
                session: root.session
                onSend: t => root.sendReply(t)
                onCancel: root.cancelReply()
                Component.onCompleted: focusInput()
            }
        }
    }
}

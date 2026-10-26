pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.core
import qs.components

// The island's expanded card for one IslandEntry (hosted by Island.qml's popup):
//   header   lead chip (cover / timer ring / glyph), title + sub, big trail (time, size)
//   progress optional 3px bar (music position, timer)
//   rows     optional list (agent sessions, downloads); a click runs the row's act
//   actions  buttons: icon-only = round 30px (media transport), labelled = flat pills
//   others   the other live entries as compact pills; a click switches the island to that one
// emits acted(close) after an action (close = the action leaves the card's context, e.g. Jump).
Column {
    id: root
    property IslandEntry entry: null
    property var others: []
    property bool animate: true
    signal acted(bool close)
    signal pick(string kind)
    readonly property string kind: entry?.kind ?? ""
    spacing: 10

    // ---- header ----
    Item {
        width: parent.width
        height: 44
        Rectangle {
            id: chip
            width: 44; height: 44
            radius: Theme.square ? 4 : root.kind === "music" ? 9 : 22
            color: root.kind === "recording" ? Theme.rgba(Theme.t.color.red, 0.16) : Theme.fill2
            clip: root.kind === "music"
            Rectangle {
                visible: root.kind === "recording"
                anchors.centerIn: parent
                width: 14; height: 14; radius: Theme.square ? 2 : 3
                color: Theme.red
            }
            Image {
                visible: root.kind === "music"
                anchors.fill: parent
                source: root.kind === "music" && root.entry ? root.entry.art : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 88; sourceSize.height: 88
            }
            Shape {
                visible: root.kind === "timer" && (root.entry?.progress ?? -1) >= 0
                anchors.centerIn: parent
                width: 32; height: 32
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: Theme.white(0.18)
                    strokeWidth: 3
                    fillColor: "transparent"
                    PathAngleArc { centerX: 16; centerY: 16; radiusX: 14; radiusY: 14; startAngle: 0; sweepAngle: 360 }
                }
                ShapePath {
                    strokeColor: root.entry?.tint ?? Theme.accent
                    strokeWidth: 3
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: 16; centerY: 16; radiusX: 14; radiusY: 14
                        startAngle: -90
                        sweepAngle: -360 * Math.max(0.001, 1 - Math.max(0, root.entry?.progress ?? 0))
                    }
                }
            }
            Glyph {
                visible: name !== "" && root.kind !== "recording" && !(root.kind === "music" && (root.entry?.art ?? "") !== "")
                    && !(root.kind === "timer" && (root.entry?.progress ?? -1) >= 0)
                anchors.centerIn: parent
                name: root.entry?.glyph ?? ""
                size: 20
                color: root.entry?.tint ?? Theme.label
            }
        }
        Column {
            anchors.left: chip.right; anchors.leftMargin: 11
            anchors.right: big.left; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            GText { width: parent.width; text: root.entry?.title ?? ""; font.pixelSize: 13; font.weight: Font.DemiBold }
            GText { width: parent.width; visible: text !== ""; text: root.entry?.sub ?? ""; small: true; secondary: true }
        }
        GText {
            id: big
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: text === "" ? 0 : implicitWidth
            text: root.kind === "recording" || root.kind === "timer" || root.kind === "mic" ? (root.entry?.trail ?? "") : ""
            color: root.kind === "recording" ? Theme.red : Theme.label
            font.family: Theme.fontNumeric
            font.pixelSize: 22
            font.weight: Theme.numericWeight
            font.features: ({ "tnum": 1 })
        }
    }

    // ---- progress ----
    Rectangle {
        visible: (root.entry?.progress ?? -1) >= 0 && root.kind !== "timer"
        width: parent.width; height: 3; radius: 2
        color: Theme.white(0.18)
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.entry?.progress ?? 0))
            height: parent.height; radius: 2
            color: Theme.white(0.85)
        }
    }

    // ---- rows ----
    Column {
        visible: (root.entry?.rows ?? []).length > 0
        width: parent.width
        Repeater {
            model: root.entry?.rows ?? []
            ListRow {
                required property var modelData
                width: parent?.width ?? 0
                icon: modelData.glyph ?? ""
                chip: (modelData.glyph ?? "") !== ""
                on: modelData.on ?? false
                title: modelData.title ?? ""
                subtitle: modelData.sub ?? ""
                hoverable: !!modelData.act
                onClicked: if (modelData.act) { modelData.act(); root.acted(modelData.close ?? true); }
            }
        }
    }

    // ---- actions ----
    Flow {
        visible: (root.entry?.actions ?? []).length > 0
        width: parent.width
        spacing: 6
        Repeater {
            model: root.entry?.actions ?? []
            Item {
                id: act
                required property var modelData
                readonly property bool round: (modelData.label ?? "") === ""
                readonly property bool ok: modelData.enabled ?? true
                width: round ? 30 : pill.implicitWidth
                height: round ? 30 : 26
                opacity: ok ? 1 : 0.35
                function run() { if (!ok) return; modelData.act(); root.acted(modelData.close ?? false); }
                Rectangle {
                    visible: act.round
                    anchors.fill: parent
                    radius: Theme.square ? 3 : 15
                    color: am.containsMouse ? Theme.fill2 : Theme.white(0)
                    Behavior on color { ColorAnimation { duration: Theme.durHover } }
                    scale: am.pressed ? 0.92 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                    Glyph { anchors.centerIn: parent; name: act.modelData.icon ?? ""; size: 16 }
                    MouseArea { id: am; anchors.fill: parent; hoverEnabled: true; enabled: act.round && act.ok; onClicked: act.run() }
                }
                PillButton {
                    id: pill
                    visible: !act.round
                    anchors.verticalCenter: parent.verticalCenter
                    flat: true
                    on: act.modelData.on ?? false
                    text: act.modelData.label ?? ""
                    icon: act.modelData.icon ?? ""
                    onClicked: act.run()
                }
            }
        }
    }

    // ---- the other live things ----
    Rectangle { visible: root.others.length > 0; width: parent.width; height: 1; color: Theme.sep }
    Column {
        visible: root.others.length > 0
        width: parent.width
        spacing: 2
        Repeater {
            model: root.others
            Item {
                id: other
                required property var modelData
                width: parent?.width ?? 0
                height: 28
                clip: true
                Rectangle {
                    anchors.fill: parent
                    radius: Theme.square ? 3 : 6
                    color: Theme.fill
                    opacity: om.containsMouse ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
                }
                IslandPill {
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    entry: other.modelData
                    animate: root.animate
                    maxText: Math.min(150, other.width - 150)
                }
                Glyph { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter; name: "chevR"; size: 12; color: Theme.label3 }
                MouseArea { id: om; anchors.fill: parent; hoverEnabled: true; onClicked: root.pick(other.modelData.kind) }
            }
        }
    }
}

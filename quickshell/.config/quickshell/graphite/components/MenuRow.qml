import QtQuick
import qs.core

// Menu item (mock .mi): 22px row, text at 22px, checkmark at 6px, shortcut hint on the right.
// Highlight: tokens ui.selection "neutral" = white 12% (insp looks), else accent fill.
// `separator` / `header` turn the row into a .msep / .mhead.
Item {
    id: root
    property string text
    property string shortcut: ""
    property string icon: ""             // optional glyph left of the text
    property bool separator: false
    property bool header: false
    property bool enabled: true
    property bool checked: false
    property bool hasChildren: false
    property bool danger: false
    signal triggered()
    implicitWidth: label.implicitWidth + 32 + (shortcut ? hint.implicitWidth + 28 : 0) + (hasChildren ? 16 : 0)
    implicitHeight: separator ? 11 : header ? 24 : 22

    // separator (.msep)
    Rectangle {
        visible: root.separator
        anchors.verticalCenter: parent.verticalCenter
        x: 10; width: parent.width - 20; height: 1
        color: Theme.sep
    }
    // header (.mhead)
    SectionLabel {
        visible: root.header
        anchors.bottom: parent.bottom
        topPadding: 5; bottomPadding: 3
        text: root.text
    }

    readonly property bool row: !separator && !header
    readonly property bool hot: mouse.containsMouse && root.enabled && row
    readonly property bool accentHot: hot && !Theme.selectionNeutral
    Rectangle {
        visible: root.row
        anchors.fill: parent
        radius: Theme.square ? 3 : 5
        color: Theme.selectionNeutral ? Theme.fill2 : Theme.accent
        opacity: root.hot ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.hot ? 60 : Theme.durHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
    }
    Glyph {
        visible: root.checked && root.row
        x: 6; anchors.verticalCenter: parent.verticalCenter
        name: "check"; size: 11
        color: root.accentHot ? Theme.onAccent : Theme.label
    }
    Glyph {
        id: ico
        visible: root.icon !== "" && root.row
        x: 8; anchors.verticalCenter: parent.verticalCenter
        name: root.icon; size: 14
        color: label.color
    }
    GText {
        id: label
        visible: root.row
        x: 22; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x - 10 - (root.shortcut ? hint.implicitWidth + 28 : 0) - (root.hasChildren ? 14 : 0)
        text: root.text
        color: !root.enabled ? Theme.label3 : root.accentHot ? Theme.onAccent : root.danger ? Theme.red : Theme.label
    }
    GText {
        id: hint
        visible: root.row && root.shortcut !== ""
        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
        text: root.shortcut
        font.pixelSize: 12
        font.letterSpacing: 0.24
        color: root.accentHot ? Theme.rgba(Theme.t.color.onAccent, 0.82) : root.enabled ? Theme.label2 : Theme.label3
    }
    Glyph {
        visible: root.hasChildren && root.row
        anchors.right: parent.right; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
        name: "chevR"; size: 12
        color: root.accentHot ? Theme.onAccent : Theme.label2
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.row
        hoverEnabled: true
        onClicked: if (root.enabled) root.triggered()
    }
}

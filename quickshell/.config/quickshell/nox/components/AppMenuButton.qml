pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.modules.bar

// One menu-bar title (app name or File/Edit/…) with its dropdown. Like macOS, once a bar menu is
// open, hovering another title switches to it.
BarButton {
    id: root
    property string menu: "app"
    property string label: menu
    property bool bold: false
    readonly property string popupId: "bar:menu:" + menu
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    onEntered: if (Panels.popup.startsWith("bar:menu:") || Panels.popup === "bar:logo") Panels.open(popupId)

    property real maxTextWidth: 100000
    // Telemetry: app name in mono caps with an accent square (mock .mbi.app::before)
    readonly property bool monoApp: bold && Theme.labelsMono && Theme.square
    Rectangle {
        visible: root.monoApp
        width: 6; height: 6; color: Theme.accent
        anchors.verticalCenter: parent.verticalCenter
    }
    // Label with a crossfade: a new label fades in over the old one (motion.pop / fade) while the
    // button's width eases to the new text's width; no jump, and the row after it doesn't move
    // (the app name sits in a fixed-width slot, see AppName).
    Item {
        id: label
        anchors.verticalCenter: parent.verticalCenter
        height: ta.implicitHeight
        property bool flip: false                  // false: ta is the current text, true: tb
        readonly property Item front: flip ? tb : ta
        width: Math.min(front.implicitWidth, root.maxTextWidth)
        Behavior on width {
            enabled: root.bold
            NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
        }
        GText {
            id: ta
            width: Math.min(implicitWidth, root.maxTextWidth)
            font.weight: root.bold ? Font.Bold : Font.Normal
            font.family: root.monoApp ? Theme.fontLabel : Theme.fontUi
            font.pixelSize: root.monoApp ? 12 : Theme.fontSize
            font.capitalization: root.monoApp ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: root.monoApp ? 0.84 : 0
            opacity: label.flip ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: label.flip ? Theme.durPop : Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        }
        GText {
            id: tb
            width: Math.min(implicitWidth, root.maxTextWidth)
            font.weight: root.bold ? Font.Bold : Font.Normal
            font.family: root.monoApp ? Theme.fontLabel : Theme.fontUi
            font.pixelSize: root.monoApp ? 12 : Theme.fontSize
            font.capitalization: root.monoApp ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: root.monoApp ? 0.84 : 0
            opacity: label.flip ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: label.flip ? Theme.durFade : Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        }
        Component.onCompleted: ta.text = root.label
        Connections {
            target: root
            function onLabelChanged() {
                if (!root.bold) { ta.text = root.label; return; }
                // the outgoing text keeps its string while it fades; the incoming one gets the new
                (label.flip ? ta : tb).text = root.label;
                label.flip = !label.flip;
            }
        }
    }

    FontMetrics { id: fm; font.family: Theme.fontUi; font.pixelSize: Theme.fontSize }
    GPopup {
        popupId: root.popupId
        anchorItem: root
        popupWidth: {
            if (Panels.popup !== root.popupId) return 224;
            let m = 0;
            for (const it of AppMenus.items(root.menu))
                if (it.label) m = Math.max(m, fm.advanceWidth(it.label) + (it.shortcut ? fm.advanceWidth(it.shortcut) + 28 : 0));
            return Math.min(420, Math.max(224, m + 32 + 12));
        }
        content: Column {
            Repeater {
                model: Panels.popup === root.popupId ? AppMenus.items(root.menu) : []
                MenuRow {
                    required property var modelData
                    width: parent.width
                    text: modelData.label ?? modelData.head ?? ""
                    shortcut: modelData.shortcut ?? ""
                    separator: !!modelData.sep
                    header: modelData.head !== undefined
                    checked: !!modelData.check
                    enabled: !modelData.dis
                    danger: !!modelData.danger
                    onTriggered: { Panels.close(); modelData.act?.(); }
                }
            }
        }
    }
}

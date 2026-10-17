import QtQuick
import qs.core
import qs.components
import qs.services

// Current Hyprland layout as a compact glyph (dwindle = Tiling, scrolling, master, monocle).
// Click = next layout, right click = previous (`nox layout next|prev`); hover shows the name.
// widgets.layout.showLabel: "hover" (default) | "always" | "never"
BarButton {
    id: root
    property string widgetId: "layout"
    readonly property var options: Config.widget(widgetId)
    readonly property string mode: options.showLabel ?? "hover"
    hpad: 7
    spacing: 0
    visible: Layout.name !== ""
    onClicked: b => b === Qt.RightButton ? Layout.prev() : Layout.next()
    onWheel: d => d > 0 ? Layout.prev() : Layout.next()
    Glyph { name: Layout.glyph; size: Theme.iconSize - 1; anchors.verticalCenter: parent.verticalCenter }
    // hover label: eases open (width + fade) instead of popping in; it's the last item of the
    // left row, so nothing to its right moves
    readonly property bool showLabel: root.mode === "always" || (root.mode === "hover" && root.hovered)
    Item {
        id: labelBox
        anchors.verticalCenter: parent.verticalCenter
        height: lbl.implicitHeight
        width: root.showLabel ? lbl.implicitWidth + 5 : 0
        clip: true
        Behavior on width { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        GText {
            id: lbl
            x: 5
            opacity: root.showLabel ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
            text: Layout.label
            font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
            font.pixelSize: Theme.labelsMono ? 11 : Theme.fontSize
            font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase
            font.letterSpacing: Theme.labelsMono ? 0.6 : 0
        }
    }
}

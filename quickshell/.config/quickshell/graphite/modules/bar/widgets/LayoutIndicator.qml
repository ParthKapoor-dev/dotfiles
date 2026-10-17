import QtQuick
import qs.core
import qs.components
import qs.services

// Current Hyprland layout as a compact glyph (dwindle = Tiling, scrolling, master, monocle).
// Click = next layout, right click = previous (`graphite-layout next|prev`); hover shows the name.
// widgets.layout.showLabel: "hover" (default) | "always" | "never"
BarButton {
    id: root
    property string widgetId: "layout"
    readonly property var options: Config.widget(widgetId)
    readonly property string mode: options.showLabel ?? "hover"
    hpad: 7
    spacing: 5
    visible: Layout.name !== ""
    onClicked: b => b === Qt.RightButton ? Layout.prev() : Layout.next()
    onWheel: d => d > 0 ? Layout.prev() : Layout.next()
    Glyph { name: Layout.glyph; size: Theme.iconSize - 1; anchors.verticalCenter: parent.verticalCenter }
    GText {
        visible: root.mode === "always" || (root.mode === "hover" && root.hovered)
        anchors.verticalCenter: parent.verticalCenter
        text: Layout.label
        font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: Theme.labelsMono ? 11 : Theme.fontSize
        font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: Theme.labelsMono ? 0.6 : 0
    }
}

import QtQuick
import qs.core

// Glass surface (mock .glass + .panel): tinted translucent fill, 0.5px light rim, 1px top
// highlight and a dark outer hairline. Blur comes from Hyprland layer rules.
// `menu` = denser popover glass (tokens glass.menuAlpha); `strong` = launcher glass.
// Opaque looks (glass.alpha >= 1, Telemetry) get a plain hairline edge instead of the rim.
// card.brackets draws accent corner brackets (HUD look).
Rectangle {
    id: g
    property bool strong: false
    property bool menu: false
    property bool brackets: false            // HUD corner brackets (launcher sets Theme.cardBrackets)
    property color bracketColor: Theme.white(0.5)
    property bool outline: true
    color: strong ? Theme.launcherGlass : menu ? Theme.menuGlass : Theme.glass
    radius: Theme.radiusMenu
    border.width: Theme.glassOpaque ? 1 : Theme.rimWidth
    border.color: Theme.glassOpaque ? Theme.hair : Theme.rim
    // outer dark hairline (mock 0 0 0 .5px rgba(0,0,0,.9)), drawn behind the fill
    Rectangle {
        visible: g.outline
        z: -1
        anchors.fill: parent
        anchors.margins: -0.75
        radius: g.radius + 0.75
        color: "transparent"
        border.width: 0.75
        border.color: Qt.rgba(0, 0, 0, 0.85)
    }
    // top inner highlight (mock inset 0 1px 0 rgba(255,255,255,.05))
    Rectangle {
        visible: !Theme.glassOpaque
        x: g.radius * 0.6; width: g.width - g.radius * 1.2
        y: g.border.width; height: 1
        color: Theme.white(0.05)
    }
    Brackets { anchors.fill: parent; visible: g.brackets; z: 10; color: g.bracketColor }
}

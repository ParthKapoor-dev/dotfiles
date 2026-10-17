import QtQuick
import qs.core

// Glass surface: tinted translucent fill + light rim. Blur comes from Hyprland layer rules.
// Opaque looks (glass.alpha >= 1, e.g. Telemetry) get a plain hairline edge instead of the rim.
// card.brackets draws accent corner brackets (HUD look).
Rectangle {
    property bool strong: false
    property bool brackets: Theme.cardBrackets
    color: strong ? Theme.launcherGlass : Theme.glass
    radius: Theme.radiusMenu
    border.width: Theme.glassOpaque ? 1 : Theme.rimWidth
    border.color: Theme.glassOpaque ? Theme.hair : Theme.rim
    Brackets { anchors.fill: parent; visible: parent.brackets; z: 10 }
}

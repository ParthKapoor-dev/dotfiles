import QtQuick
import qs.core

// Glass surface: tinted translucent fill + light rim. Blur comes from Hyprland layer rules.
Rectangle {
    property bool strong: false
    color: strong ? Theme.launcherGlass : Theme.glass
    radius: Theme.radiusMenu
    border.width: Theme.rimWidth
    border.color: Theme.rim
}

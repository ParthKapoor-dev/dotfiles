import QtQuick
import qs.core

// Monochrome symbol from the icon font (tokens font.icon, default Material Symbols Rounded).
Text {
    property string name
    property real size: Theme.iconSize
    property bool filled: false
    property int weight: 400
    text: name
    color: Theme.label
    font.family: Theme.fontIcon
    font.pixelSize: size
    font.hintingPreference: Font.PreferNoHinting
    font.variableAxes: ({ "FILL": filled ? 1 : 0, "wght": weight, "opsz": Math.max(20, Math.min(48, size)), "GRAD": 0 })
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    renderType: Text.QtRendering
}

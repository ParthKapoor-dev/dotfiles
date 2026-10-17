import QtQuick
import qs.core

// Control Center module title (mock .mt): 12.5px semibold, or (ui.sectionLabels mono-upper)
// label font 10.5px medium caps, tracked 0.08em, grey. `detail` = the small text on the right
// (mock .mt small: "brightnessctl", the output name).
Item {
    id: root
    property string text
    property string detail: ""
    implicitWidth: 200
    implicitHeight: 17
    GText {
        id: t
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: Theme.labelsMono ? 11 : 13
        font.weight: Theme.labelsMono ? Font.Medium : Font.DemiBold
        font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: Theme.labelsMono ? 0.84 : 0
        color: Theme.labelsMono ? Theme.label2 : Theme.label
    }
    GText {
        anchors.left: t.right; anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: root.detail
        font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
        font.pixelSize: Theme.labelsMono ? 10 : 11
        font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase
        font.letterSpacing: Theme.labelsMono ? 0.8 : 0
        color: Theme.label2
    }
}

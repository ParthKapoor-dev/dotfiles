import QtQuick
import qs.core

Text {
    property bool small: false
    property bool secondary: false
    color: secondary ? Theme.label2 : Theme.label
    font.family: Theme.fontUi
    font.pixelSize: small ? Theme.fontSizeSmall : Theme.fontSize
    elide: Text.ElideRight
    verticalAlignment: Text.AlignVCenter
}

import QtQuick
import qs.core

// Small grey heading (mock .psec / .mhead / .ln-h). tokens ui.sectionLabels:
// "plain" = UI font 11px semibold; "mono-upper" = font.label 10px medium, uppercase, tracked (insp looks).
// Fills its parent's width and wraps, so a long line ("Power Source: Power Adapter · Fully
// charged" in the mono-upper looks) never runs past the popover's right edge.
GText {
    width: parent ? parent.width : implicitWidth
    wrapMode: Text.Wrap
    leftPadding: 10; rightPadding: 10; topPadding: 8; bottomPadding: 3
    font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
    font.pixelSize: Theme.labelsMono ? 10 : Theme.fontSizeSmall
    font.weight: Theme.labelsMono ? Font.Medium : Font.DemiBold
    font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase
    font.letterSpacing: Theme.labelsMono ? Theme.labelTracking * 10 : 0
    secondary: true
}

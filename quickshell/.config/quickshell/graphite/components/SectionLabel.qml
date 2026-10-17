import QtQuick
import qs.core

// Small grey heading (mock .psec / .mhead / .ln-h). tokens ui.sectionLabels:
// "plain" = UI font 11px semibold; "mono-upper" = font.label 10px medium, uppercase, tracked (insp looks).
GText {
    leftPadding: 10; topPadding: 8; bottomPadding: 3
    font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
    font.pixelSize: Theme.labelsMono ? 10 : Theme.fontSizeSmall
    font.weight: Theme.labelsMono ? Font.Medium : Font.DemiBold
    font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase
    font.letterSpacing: Theme.labelsMono ? Theme.labelTracking * 10 : 0
    secondary: true
}

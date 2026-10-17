import QtQuick
import qs.core

// Small grey heading (mock .psec / .mhead / .ln-h). Follows tokens ui.sectionLabels:
// "plain" = UI font, semibold; "mono-upper" = font.label, uppercase, letter-spacing font.labelTracking (em).
GText {
    leftPadding: 10; topPadding: 6; bottomPadding: 3
    font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
    font.pixelSize: Theme.fontSizeSmall
    font.weight: Theme.labelsMono ? Font.Medium : Font.DemiBold
    font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase
    font.letterSpacing: Theme.labelsMono ? Theme.labelTracking * Theme.fontSizeSmall : 0
    secondary: true
}

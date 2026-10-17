import QtQuick
import qs.core

// Title of a Control Center card ("Display", "Sound"): semibold label, or the mono-upper
// section-label style when tokens ui.sectionLabels = "mono-upper".
GText {
    font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
    font.pixelSize: Theme.labelsMono ? Theme.fontSizeSmall : Theme.fontSize - 1
    font.weight: Theme.labelsMono ? Font.Medium : Font.DemiBold
    font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase
    font.letterSpacing: Theme.labelsMono ? Theme.labelTracking * Theme.fontSizeSmall : 0
    secondary: Theme.labelsMono
}

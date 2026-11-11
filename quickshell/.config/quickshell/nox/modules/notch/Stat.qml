import QtQuick
import qs.core
import qs.components

// A big thin number over a small mono caption (mock .stats .s / .met).
Column {
    id: st
    property string value: ""
    property string label: ""
    property color tone: Theme.label
    property real px: 24
    spacing: 3
    GText { text: st.value; font.pixelSize: st.px; font.weight: Font.ExtraLight; font.features: ({ "tnum": 1 }); color: st.tone }
    GText { text: st.label.toUpperCase(); font.family: Theme.fontMono; font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.label3 }
}

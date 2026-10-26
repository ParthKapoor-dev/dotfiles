import QtQuick

// One thing the island can show (Island.qml builds one per source from its service). Plain data,
// so the pill (IslandPill) and the card (IslandCard) draw every source the same way, and the
// offscreen tests can feed fake ones.
QtObject {
    property string kind                 // recording | mic | agent | timer | download | music | shelf
    property bool live: false
    property string glyph: ""            // components/glyphs.js name for the pill / card lead
    property color tint: "white"
    // pill: [lead] text  trail
    property string text: ""
    property string trail: ""
    property bool trailMono: true        // tabular figures (times, sizes)
    // card
    property string title: ""
    property string sub: ""
    property string art: ""              // image url (music cover)
    property real progress: -1           // 0..1, -1 = no bar (the timer's ring uses it too)
    property var level: []               // mic: recent levels 0..1 (last few)
    property bool urgent: false          // agent needs you: the dot pings
    property var rows: []                // card list: [{ title, sub, glyph, on, act }]
    property var actions: []             // card buttons: [{ label, icon, act, on, close }]
}

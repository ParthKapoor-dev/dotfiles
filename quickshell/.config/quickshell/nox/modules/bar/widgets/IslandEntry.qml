import QtQuick

// One thing the island can show (Island.qml builds one per source from its service). Plain data,
// so the pill face (IslandPill) and the expanded card (IslandCard) draw every source the same way,
// and the offscreen tests can feed fake ones.
QtObject {
    property string kind                 // recording | mic | agent | timer | download | music | shelf
    property bool live: false
    // what the visuals do: agent work | need | done; timer run | paused | ring; download run | done;
    // music play | pause; anything else ""
    property string mode: ""
    property bool hot: false             // wants you (agent needs you, timer rang): sorts first, accent
    property string glyph: ""            // components/glyphs.js name (mini glyph, card tile, tabs)
    property color tint: "white"
    // ---- pill: [lead] text  meta  [tail visual]
    property string text: ""
    property bool textAccent: false
    property string meta: ""             // small uppercase label3 text after the title
    property string art: ""              // image url (music cover)
    property real progress: -1           // 0..1, -1 = none (timer ring / card bar)
    property var segs: []                // agent: recent tool calls this turn, "ok" | "run" | "er"
    // ---- card
    property string tile: ""             // "" | "acc" (accent tile) | "rec" (red tint)
    property string kicker: ""           // small uppercase line above the title
    property string title: ""
    property string big: ""              // tabular number on the right
    property bool bigAccent: false
    property bool bigLarge: false        // the timer's big digits
    property string quote: ""            // accent-ruled box (what the agent asks)
    property string info: ""             // mono line under the bar
    property var times: []               // [left, right] mono labels under the bar (music)
    property bool levels: false          // card shows the mic levels (Island.micLevels)
    property var rows: []                // [{ title, sub, on, act, close }]
    property var actions: []             // [{ label, icon, pri, act, close, enabled }]; no label = icon button
}

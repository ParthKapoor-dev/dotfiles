pragma Singleton
import QtQuick
import Quickshell

// Shared UI state: which popup is open (only one at a time), launcher, dock visibility, bar windows.
Singleton {
    id: root

    property string popup: ""          // id of the open GPopup, "" = none
    property bool dockVisible: true
    property bool caffeine: false      // idle inhibitor (owned by the bar window)
    property var barWindows: []        // registered by each bar; popups include them in their focus grab
    property bool launcherOpen: false
    property string launcherQuery: ""  // text to start the next launcher session with
    property bool overviewOpen: false
    property bool sessionOpen: false
    property bool cheatsheetOpen: false
    property bool dockRevealed: false  // autohide: pointer at the bottom edge / dock hovered / IPC
    property var popupIds: []          // ids of GPopups that currently exist (registered by GPopup)

    function open(id) { popup = id; }
    // mock #hud: short text toast at the top centre (shown by the osd module)
    signal hudRequested(string text, string glyph)
    function hud(text, glyph) { hudRequested(text, glyph ?? "check"); }
    function openLauncher(q) { launcherQuery = q ?? ""; if (launcherOpen) launcherOpen = false; launcherOpen = true; }
    function close(id) { if (id === undefined || popup === id) popup = ""; }
    function toggle(id) { popup = (popup === id) ? "" : id; }
    function exists(id) { return popupIds.indexOf(id) !== -1; }
    function registerPopup(id) { if (!exists(id)) popupIds = popupIds.concat([id]); }
    function unregisterPopup(id) { popupIds = popupIds.filter(x => x !== id); if (popup === id) popup = ""; }

    function registerBar(w) { if (barWindows.indexOf(w) === -1) barWindows = barWindows.concat([w]); }
    function unregisterBar(w) { barWindows = barWindows.filter(x => x !== w); }
}

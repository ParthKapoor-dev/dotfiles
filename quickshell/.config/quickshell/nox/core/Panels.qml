pragma Singleton
import QtQuick
import Quickshell

// Shared UI state: which popup is open (only one at a time), launcher, dock visibility, bar windows.
Singleton {
    id: root

    property string popup: ""          // id of the open GPopup, "" = none
    property bool dockVisible: true
    // idle inhibitor (owned by the bar window); starts as shell.json caffeine.default (true)
    property bool caffeine: Config.opt.caffeine?.default ?? true
    property var barWindows: []        // registered by each bar; popups include them in their focus grab
    property bool launcherOpen: false
    property string launcherQuery: ""  // text to start the next launcher session with
    property bool overviewOpen: false
    signal overviewStep(int delta)
    signal switcherCommand(string cmd)
    signal notesCommand(string cmd)     // Notes window: toggle | show | new (modules/notes)  // Alt+Tab switcher: next | prev | commit | cancel (modules/switcher)     // Mission Control: browse desktops while open (IPC overview next|prev)
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
    function toggle(id) {
        // a press outside the popup's focus grab (e.g. a surface that isn't whitelisted) closes
        // it before that same click's release toggles it: don't reopen what that press just closed
        if (popup === "" && grabClosed.id === id && Date.now() - grabClosed.at < 300) return;
        popup = (popup === id) ? "" : id;
    }
    property var grabClosed: ({ id: "", at: 0 })
    function closeByGrab(id) { if (popup === id) { grabClosed = { id, at: Date.now() }; popup = ""; } }
    // pointer presses on shell buttons (bar, dock) stamp this, so a GPopup knows it was opened by
    // a click (see GPopup: keyboard focus waits for hover)
    property real pointerAt: 0
    function notePointer() { pointerAt = Date.now(); }
    function pointerOpened() { return Date.now() - pointerAt < 600; }
    function exists(id) { return popupIds.indexOf(id) !== -1; }
    function registerPopup(id) { if (!exists(id)) popupIds = popupIds.concat([id]); }
    function unregisterPopup(id) { popupIds = popupIds.filter(x => x !== id); if (popup === id) popup = ""; }

    function registerBar(w) { if (barWindows.indexOf(w) === -1) barWindows = barWindows.concat([w]); }
    function unregisterBar(w) { barWindows = barWindows.filter(x => x !== w); }
}

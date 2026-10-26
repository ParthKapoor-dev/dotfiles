pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services
import "SelText.js" as ST

// Selection action bar (PopClip style): select text anywhere and a small bar of actions appears
// 14 px above the pointer once it is still. Watching / settling / dismissing is services/Selection;
// this is the window and the actions. The window exists only while the bar is up (and fades out);
// it is an Overlay layer (namespace nox:selbar) that never takes keyboard focus, so typing keeps
// going to the app, and only the bar itself takes the pointer.
//   Ask       Circle to Ask with the text (modules/ask; the card opens where the bar was)
//   Search    the web (selbar.searchUrl, %s = the text; default: the launcher's web engine)
//   Translate selbar.translateUrl (Google Translate, auto -> selbar.translateTo, "en")
//   Copy      primary -> clipboard          Shelf   the text onto the drop shelf
//   Open      the link (a URL only)         Case    copies it UPPER / lower / Title / Sentence, cycling
//   = result  maths only: the result inline, click copies it
//   Speak     spd-say, only if it is installed
// Esc dismisses (nox:selbarDismiss, a non-consuming Escape bind). Nothing the user selected is
// logged; actions hand the text to their program on stdin where one reads it (wl-copy, spd-say).
//   qs -c nox ipc call selbar on | off | toggle | reset | status | dismiss   (`nox selbar`)
Scope {
    id: root
    readonly property var opts: Config.opt.selbar ?? ({})
    Component.onCompleted: Selection.active = true
    Component.onDestruction: Selection.active = false

    IpcHandler {
        target: "selbar"
        function on(): void { Selection.setEnabled(true); }
        function off(): void { Selection.setEnabled(false); }
        function toggle(): bool { Selection.toggle(); return Selection.enabled; }
        function reset(): void { Selection.reset(); }
        function status(): string { return Selection.status(); }
        function dismiss(): void { Selection.dismiss(); }
    }
    LazyLoader {
        active: !Quickshell.env("NOX_LINT")
        component: Scope {
            // bound non-consuming + transparent on Escape: the app still gets every Esc
            GlobalShortcut {
                appid: "nox"; name: "selbarDismiss"; description: "Internal: Esc dismisses the selection bar"
                onPressed: if (Selection.shown) Selection.dismiss()
            }
        }
    }

    // ---- actions ----
    // the launcher's default web engine unless selbar.searchUrl says otherwise
    readonly property var web: Config.launcherProvider("web")
    readonly property string webKey: web["default"] ?? "g"
    readonly property string searchUrl: opts.searchUrl ?? web.engines?.[webKey]?.url
        ?? ({ g: "https://www.google.com/search?q=%s", d: "https://duckduckgo.com/?q=%s" })[webKey] ?? "https://www.google.com/search?q=%s"
    readonly property string translateUrl: opts.translateUrl
        ?? ("https://translate.google.com/?sl=auto&tl=" + (opts.translateTo ?? "en") + "&op=translate&text=%s")
    function openUrl(u) { Quickshell.execDetached((opts.opener ?? ["xdg-open"]).concat([u])); }
    function fill(tpl, t) { return String(tpl).replace(/%s/g, encodeURIComponent(t)); }

    property string caseShown: ""       // per show: the case the Case button last copied
    property string flash: ""
    Timer { id: flashOff; interval: 1100; onTriggered: root.flash = "" }
    Connections { target: Selection; function onSerialChanged() { root.caseShown = ""; root.flash = ""; } }
    function say(msg) { flash = msg; flashOff.restart(); }

    function act(id, view) {
        const raw = Selection.text, t = raw.trim();
        if (t === "") return;
        const info = ST.classify(t);
        switch (id) {
        case "ask": {
            if (!Config.moduleEnabled("ask")) { Panels.hud("Circle to Ask is off (modules.ask)", "x"); Selection.dismiss(); return; }
            // instantly gone (no fade): Ask freezes the screen a moment later. Deferred, so the
            // window is not torn down inside its own click handler
            const rect = view ? view.askRect() : null;
            Qt.callLater(() => { root.instant = true; Selection.ask(rect); });
            return;
        }
        case "search": openUrl(fill(searchUrl, t)); break;
        case "translate": openUrl(fill(translateUrl, t)); break;
        case "copy": pipe(["wl-copy"], raw); Panels.hud("Copied", "clip"); break;
        case "shelf":
            // the shelf peeks with the new card itself; without the shelf module there is nowhere to see it
            if (!Config.moduleEnabled("shelf")) { Panels.hud("The shelf is off (modules.shelf)", "x"); break; }
            Shelf.addText(t);
            break;
        case "open": if (info.isUrl) openUrl(info.url); break;
        case "case": {
            const k = ST.nextCase(t, caseShown);
            pipe(["wl-copy"], ST.toCase(t, k));
            caseShown = k;
            say("Copied · " + ST.caseNames[k]);
            Selection.keep();
            return;          // stays up: click again for the next case
        }
        case "calc":
            if (!info.isMath) return;
            pipe(["wl-copy"], ST.plain(info.math));
            Panels.hud("Copied " + ST.fmt(info.math), "calc");
            break;
        case "speak": pipe(["spd-say", "-e"], t); break;
        default: return;
        }
        Selection.dismiss();
    }

    // the text goes to the program on stdin (not argv, so it is not in `ps`); one at a time per
    // pipe is plenty, a busy pipe gets a second one
    component Pipe: Process {
        id: p
        property string payload: ""
        stdinEnabled: true
        onStarted: { p.write(p.payload); p.payload = ""; p.stdinEnabled = false; }
        onExited: p.stdinEnabled = true
    }
    Pipe { id: pipeA }
    Pipe { id: pipeB }
    function pipe(cmd, data) {
        const p = !pipeA.running ? pipeA : pipeB;
        if (p.running) return;
        p.command = cmd;
        p.payload = data;
        p.stdinEnabled = true;
        p.running = true;
    }

    // spd-say is optional: looked up once, the first time the bar shows
    property bool canSpeak: false
    property bool speakChecked: false
    Process {
        id: speakProbe
        command: ["sh", "-c", "command -v spd-say"]
        onExited: code => root.canSpeak = code === 0
    }

    // ---- window ----
    property bool mapped: false
    property bool instant: false        // Ask: unmap without the fade
    readonly property bool up: Selection.shown
    onUpChanged: {
        if (up) {
            killTimer.stop(); instant = false; mapped = true;
            if (!speakChecked) { speakChecked = true; speakProbe.running = true; }
        } else if (instant) { mapped = false; instant = false; }
        else killTimer.restart();
    }
    Timer { id: killTimer; interval: Theme.durFade + 80; onTriggered: if (!root.up) root.mapped = false }

    LazyLoader {
        active: root.mapped
        PanelWindow {
            id: win
            readonly property ShellScreen scr: Quickshell.screens.find(s => s.name === Selection.screenName) ?? Quickshell.screens[0] ?? null
            screen: scr
            color: "transparent"
            WlrLayershell.namespace: "nox:selbar"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true }

            // room round the bar for its shadow and the hint
            readonly property real padX: 30
            readonly property real tipRoom: 34
            readonly property real padY: 22
            readonly property real sw: scr?.width ?? 1920
            readonly property real sh: scr?.height ?? 1080
            readonly property real topLimit: (Config.moduleEnabled("bar") ? Theme.barHeight : 0) + 6
            // above the pointer by 14 px; under it when there is no room above
            readonly property bool below: Selection.atY - 14 - view.height < topLimit
            implicitWidth: Math.min(sw, view.width + padX * 2)
            implicitHeight: view.height + tipRoom + padY
            margins.left: Math.round(Math.max(0, Math.min(sw - implicitWidth, Selection.atX - implicitWidth / 2)))
            margins.top: Math.round(below ? Math.min(sh - implicitHeight, Selection.atY + 22 - padY / 2)
                                          : Math.max(0, Selection.atY - 14 - view.height - tipRoom))
            mask: Region { item: view }

            SelBarView {
                id: view
                // the bar centred on the pointer, kept inside the window
                x: Math.round(Math.max(8, Math.min(win.implicitWidth - width - 8, Selection.atX - win.margins.left - width / 2)))
                y: win.below ? Math.round(win.padY / 2) : win.tipRoom
                text: Selection.text
                canSpeak: root.canSpeak
                caseShown: root.caseShown
                flash: root.flash
                tipBelow: win.below
                onAct: id => root.act(id, view)
                onPointerInChanged: Selection.hovered = pointerIn
                // screen-local rect for Ask's card (where the bar was)
                function askRect() {
                    return { x: win.margins.left + x, y: win.margins.top + y, w: width, h: height };
                }

                // in: fade + rise 6 px + 0.96 -> 1 (out: the reverse, faster); `entered` flips a frame
                // after the window exists so the first show animates too
                property bool entered: false
                Component.onCompleted: Qt.callLater(() => view.entered = true)
                readonly property bool on: root.up && entered
                opacity: on ? 1 : 0
                scale: on ? 1 : 0.96
                transform: Translate { y: view.on ? 0 : (win.below ? -6 : 6); Behavior on y { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } } }
                Behavior on opacity { NumberAnimation { duration: view.on ? Theme.durPop : Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                Behavior on scale { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
            }
            // where the bar is, globally, for the "pointer went away" check
            readonly property rect barGlobal: Qt.rect((scr?.x ?? 0) + margins.left + view.x, (scr?.y ?? 0) + margins.top + view.y, view.width, view.height)
            onBarGlobalChanged: Selection.barRect = barGlobal
            Component.onCompleted: Selection.barRect = barGlobal
        }
    }
}

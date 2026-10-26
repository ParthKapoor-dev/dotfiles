pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services

// Circle to Ask (Super+Shift+A, `nox ask`, IPC target ask; mock 23b): freeze the focused monitor,
// circle anything, Claude answers in a card beside it.
//   1. grim captures the focused monitor at its real resolution into $XDG_RUNTIME_DIR/nox-ask
//      (png level 0: ~25 ms) BEFORE anything is shown; the headless claude boots meanwhile.
//   2. A full-screen Overlay layer (nox:ask, exclusive keyboard) shows that frame; it is pixel-identical
//      to the live screen, so mapping it is invisible until the dim / zoom / grain fade in.
//   3. Freehand loop -> bounding box (+4 px); a straight drag -> rectangle; a click -> the window under
//      it. The crop is cut from the frozen frame at full resolution (magick), so fractional scaling
//      and the 1.6% zoom are undone exactly (AskStage.geomOf).
//   4. AskSession crops, OCRs (tesseract) and asks; AskCard streams the answer.
// Esc / right click / x closes; a press outside the card starts a new circle. Closing deletes the
// frame and the crop (only Send to agent keeps a copy in nox-ask/keep).
// shell.json "ask": see AskSession.qml (model, claude, extraArgs, timeout, agentDir, systemPrompt);
// modules.ask: false turns the module off. Lens (the old Super+Shift+A) is the card's Lens chip /
// `nox ask lens`.
Scope {
    id: root
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/nox-ask"
    property bool alive: false        // the window exists (outlives `open` for the exit motion)
    property bool open: false
    property bool capturing: false
    property string frame: ""
    property string screenName: ""
    property var mon: ({ x: 0, y: 0, ws: -1, special: 0 })
    property real tKey: 0
    property int freezeMs: -1         // key -> frozen frame on screen

    signal circle(var rect)

    function start() {
        if (capturing || alive) return;
        const m = Hyprland.focusedMonitor;
        screenName = m?.name ?? Quickshell.screens[0]?.name ?? "";
        mon = { x: m?.x ?? 0, y: m?.y ?? 0, ws: m?.activeWorkspace?.id ?? -1, special: m?.lastIpcObject?.specialWorkspace?.id ?? 0 };
        Hyprland.refreshToplevels();
        tKey = Date.now(); freezeMs = -1;
        frame = dir + "/frame-" + tKey + ".png";
        capturing = true;
        // leftovers of an earlier run go first (frames / crops; keep/ after a day)
        grab.command = ["sh", "-c",
            "umask 077; mkdir -p \"$1\" && find \"$1\" -maxdepth 1 -type f \\( -name 'frame-*' -o -name 'crop-*' \\) -delete; "
            + "find \"$1/keep\" -type f -mmin +1440 -delete 2>/dev/null; exec grim ${2:+-o \"$2\"} -t png -l 0 \"$3\"",
            "sh", dir, screenName, frame];
        grab.running = true;
        session.prewarm();
    }
    function close() {
        if (!alive) return;
        open = false;
        killTimer.restart();
    }
    function toggle() { if (alive) close(); else start(); }

    // Selection bar (modules/selbar, services/Selection): "Ask Claude" with the selected text. The
    // screen freezes as usual, then the area where the bar was is selected as if clicked, and Claude
    // gets the text (no image, no OCR). The text is held only until the card asks.
    property string pendingText: ""
    property var pendingRect: null
    function askText(text, rect) {
        if (capturing || alive || String(text).trim() === "") return;
        pendingText = text;
        pendingRect = rect;
        start();
    }
    Connections {
        target: Selection
        function onAskRequested(text, rect) { root.askText(text, rect); }
    }

    Process {
        id: grab
        onExited: code => {
            root.capturing = false;
            if (code === 0) { root.alive = true; root.open = true; }
            else { root.pendingText = ""; session.stopClaude(); Panels.hud("Couldn't capture the screen", "x"); }
        }
    }
    Timer {
        id: killTimer
        interval: Math.max(Theme.durSheet, 700 * Theme.durSheet / 320) + 60
        onTriggered: if (!root.open) { root.alive = false; root.pendingText = ""; session.shutdown(root.frame); root.frame = ""; }
    }

    AskSession {
        id: session
        onToast: (text, glyph) => Panels.hud(text, glyph)
        onCloseRequested: root.close()
    }

    // topmost window at a point of the frozen monitor (logical, monitor-local): special workspace
    // first, then floating, then most recently focused
    function windowAt(x, y) {
        const gx = x + mon.x, gy = y + mon.y;
        let best = null, bestKey = 1e9;
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject;
            if (!o || !o.at || !o.size || o.hidden || o.mapped === false) continue;
            const ws = o.workspace?.id;
            const onSpecial = mon.special !== 0 && ws === mon.special;
            if (ws !== mon.ws && !onSpecial) continue;
            const ax = o.at[0], ay = o.at[1], w = o.size[0], h = o.size[1];
            if (gx < ax || gy < ay || gx >= ax + w || gy >= ay + h) continue;
            const key = (onSpecial ? 0 : 10000) + (o.floating || o.pinned ? 0 : 1000) + (o.focusHistoryID ?? 999);
            if (key < bestKey) {
                bestKey = key;
                best = { x: ax - mon.x, y: ay - mon.y, w: w, h: h, app: Apps.entryFor(o.class ?? "")?.name || o.class || "", title: o.title ?? "" };
            }
        }
        return best;
    }

    // qs -c nox ipc call ask start | toggle | close | status | circle <x> <y> <w> <h>
    IpcHandler {
        target: "ask"
        function start(): void { root.start(); }
        function toggle(): void { root.toggle(); }
        function close(): void { root.close(); }
        // scripting / tests: once frozen, loop a region (logical px of that monitor) as if hand-drawn
        function circle(x: int, y: int, w: int, h: int): bool {
            if (!root.open) return false;
            root.circle({ x: x, y: y, w: w, h: h });
            return true;
        }
        // run a chip (copy | more | send | tr | csv | lens) / ask a follow-up, as if clicked / typed
        function chip(id: string): bool { if (!root.open || !session.answered) return false; session.chip(id); return true; }
        function followUp(text: string): bool { return root.open && session.followUp(text); }
        // timings only (never the selection, OCR text or answer)
        function status(): string {
            return "open=" + root.open + " screen=" + root.screenName + " model=" + session.model
                + " freeze_ms=" + root.freezeMs + " first_token_ms=" + session.firstMs
                + " busy=" + session.busy + " answered=" + session.answered + " ocr_lines=" + session.ocrLines;
        }
    }

    LazyLoader {
        active: root.alive
        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === root.screenName) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "nox:ask"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            AskStage {
                id: stage
                anchors.fill: parent
                session: session
                frame: root.frame
                open: root.open
                windowAt: (x, y) => root.windowAt(x, y)
                onReadyChanged: {
                    if (ready && root.freezeMs < 0) root.freezeMs = Date.now() - root.tKey;
                    // selection bar text: select where the bar was (the card opens beside it)
                    if (ready && root.pendingText !== "") {
                        const r = root.pendingRect ?? { x: width / 2 - 80, y: height / 2 - 20, w: 160, h: 40 };
                        const w = root.windowAt(r.x + r.w / 2, r.y + r.h / 2);
                        stage.selectWindow({ x: r.x - 6, y: r.y - 6, w: r.w + 12, h: r.h + 12, app: w?.app ?? "", title: w?.title ?? "" });
                    }
                }
                onSelected: (box, geom, w) => {
                    if (root.pendingText !== "") {
                        const t = root.pendingText;
                        root.pendingText = "";
                        session.askText(t, w?.app ?? "", w?.title ?? "");
                    } else session.ask(root.frame, geom, w?.app ?? "", w?.title ?? "");
                }
                onCloseRequested: root.close()
                Connections {
                    target: root
                    function onCircle(r) { stage.lassoAround(r); }
                }
            }
        }
    }
}

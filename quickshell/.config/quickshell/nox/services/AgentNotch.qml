pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core

// State for the agent notch in the bar (bar widget "notch", modules/notch). The pill lives in the
// bar's centre; clicking it opens a popover (popupId bar:notch) that shows, in this order:
//   the oldest permission request (unless folded away with Esc) · a done card · the panel.
// Nothing here opens on its own: a request only changes the pill (red, the command inline),
// so typing in another window never lands in the notch. Super+O opens it with the keyboard.
Singleton {
    id: root
    readonly property var opts: Config.opt.notch ?? ({})
    readonly property string popupId: "bar:notch"
    readonly property bool open: Panels.popup === popupId
    readonly property var req: Agents.requests[0] ?? null
    property string laterId: ""          // the request folded away ("later")
    property string doneId: ""           // the done card in the pill (and in the popover)
    property string view: "agents"       // the panel's tab
    property bool panelOnly: false       // opened for the panel (a view / Super+O with no request)
    readonly property bool reqShown: !!req && laterId !== (req.sid + ":" + req.id)
    readonly property string mode: (reqShown && !panelOnly) ? "need" : (doneId !== "" && !panelOnly) ? "done" : "panel"

    function show(view) {
        if (view) { root.view = view; panelOnly = true; } else panelOnly = false;
        Agents.checkGate();
        Panels.open(popupId);
    }
    function close() { Panels.close(popupId); }
    function toggle() { if (open) close(); else show(); }
    function later() { if (req) laterId = req.sid + ":" + req.id; close(); }
    function clearDone() { doneId = ""; }
    onOpenChanged: if (!open) { panelOnly = false; }
    onReqChanged: if (!req) laterId = ""

    // ---- done: a turn that ran longer than notch.doneAfter s shows in the pill for doneSeconds ----
    property var lastEnd: ({})
    Connections {
        target: Agents
        function onSessionsChanged() {
            const m = {};
            for (const s of Agents.sessions) {
                const e = s.turn?.end ?? 0;
                if (Agents.loaded && root.lastEnd[s.id] !== undefined && e && e !== root.lastEnd[s.id] && s.status === "done"
                    && e - (s.turn?.at ?? e) >= (root.opts.doneAfter ?? 20) * 1000 && Date.now() - e < 30000) {
                    root.doneId = s.id;
                    doneTimer.restart();
                }
                m[s.id] = e;
            }
            root.lastEnd = m;
        }
    }
    Timer { id: doneTimer; interval: (root.opts.doneSeconds ?? 9) * 1000; onTriggered: if (!root.open) root.doneId = ""; else restart() }
}

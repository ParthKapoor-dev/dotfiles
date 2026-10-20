pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services

// Mission Control for coding agents (namespace nox:agents; mock C4 / 23e). Ctrl+Super+M,
// `nox agents`, the bar dot, or a "needs you" notification's Open. One tile per live session
// (services/Agents, fed by the Claude Code hook ~/.local/lib/nox/agent-hook).
// Keys: arrows move, Enter (or Y on a waiting tile) jumps to the session's pane: the tile flies
// into its window and the window takes focus (Orca: also its terminal tab). Esc / click outside
// closes. Answering happens in the pane: the status hook is read-only by design.
// The surface stays loaded and only maps while open, so it opens in one frame.
// IPC: qs -c nox ipc call agents toggle | open | close | focus <session-id> | status
Scope {
    id: root
    readonly property alias view: view    // the contents (offscreen tests grab it)

    IpcHandler {
        target: "agents"
        function toggle(): void { Agents.toggle(); }
        function open(): void { Agents.show(""); }
        function close(): void { Agents.close(); }
        function focus(id: string): void { Agents.show(id); }
        function status(): string { return "sessions=" + Agents.alive.length + " working=" + Agents.working + " needs=" + Agents.needsYou + " errors=" + Agents.errors; }
    }

    // ---- jump to pane ----
    property var pending: null            // { session, tile }
    property string focusAddr: ""
    function jump(i, tile) {
        const s = view.sessions[i];
        if (!s || view.jumping || clients.running) return;
        pending = { session: s, tile: tile };
        clients.running = true;
    }
    Process {
        id: clients
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: {
                let list = [];
                try { list = JSON.parse(text); } catch (e) {}
                root.land(list);
            }
        }
    }
    function findClient(s, list) {
        const byPid = {};
        for (const c of list) (byPid[c.pid] = byPid[c.pid] ?? []).push(c);
        for (const pid of (s.chain ?? [])) {
            const c = byPid[pid];
            if (!c) continue;
            // single-instance terminals: several windows, one pid; the title usually names the project
            const proj = String(s.project ?? "").toLowerCase();
            return c.find(x => proj && String(x.title ?? "").toLowerCase().includes(proj)) ?? c[0];
        }
        if (s.kind === "orca") return list.find(c => String(c.class ?? "").toLowerCase() === "orca") ?? null;
        return null;
    }
    function land(list) {
        const p = pending;
        pending = null;
        if (!p || !win.visible) return;
        const c = findClient(p.session, list);
        if (!c) {
            Panels.hud(p.session.bg ? "Background session · no window" : "No window for this session", "x");
            return;
        }
        focusAddr = c.address;
        const sc = win.screen;
        const r = { x: c.at[0] - (sc?.x ?? 0), y: c.at[1] - (sc?.y ?? 0), w: c.size[0], h: c.size[1] };
        // into the tile's own coordinates (the grid scrolls)
        const o = p.tile.parent.mapFromItem(view, r.x, r.y);
        view.jumping = true;
        p.tile.zoomTo({ x: o.x, y: o.y, w: r.w, h: r.h });
        orcaHandle = p.session.kind === "orca" ? (p.session.orca?.handle ?? "") : "";
        orcaCli = p.session.orca?.cli ?? "";
        landTimer.restart();
    }
    property string orcaHandle: ""
    property string orcaCli: ""
    Timer {
        id: landTimer
        interval: 600
        onTriggered: {
            root.snap = true;
            Agents.close();
            focusTimer.restart();
        }
    }
    // focus one frame after the surface let go of the keyboard (see modules/switcher)
    property bool snap: false
    Timer {
        id: focusTimer
        interval: 16
        onTriggered: {
            if (root.focusAddr) Hypr.focusWindow(root.focusAddr);
            if (root.orcaHandle)
                Quickshell.execDetached([root.orcaCli ? root.orcaCli + "/orca" : "orca", "terminal", "switch", "--terminal", root.orcaHandle]);
            root.focusAddr = ""; root.orcaHandle = "";
        }
    }

    // ---- open / close ----
    Connections {
        target: Agents
        function onOpenChanged() {
            if (Agents.open) {
                hideTimer.stop();
                root.snap = false;
                view.jumping = false;
                view.openedAt = Date.now();
                const need = view.sessions.findIndex(s => s.status === "needs-you");
                const want = Agents.focusId ? view.sessions.findIndex(s => s.id === Agents.focusId) : -1;
                view.sel = want >= 0 ? want : need >= 0 ? need : Math.min(view.sel, Math.max(0, view.sessions.length - 1));
                win.visible = true;
                view.shown = true;
                keys.forceActiveFocus();
            } else {
                view.shown = false;
                if (root.snap) { win.visible = false; view.jumping = false; }
                else hideTimer.restart();
            }
        }
        function onFocusIdChanged() { if (Agents.open && Agents.focusId) view.selectId(Agents.focusId); }
    }
    Timer { id: hideTimer; interval: Theme.durFade + 200; onTriggered: { win.visible = false; view.jumping = false; } }

    PanelWindow {
        id: win
        visible: false
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
        color: "transparent"
        WlrLayershell.namespace: "nox:agents"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: Agents.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }

        MissionView {
            id: view
            anchors.fill: parent
            onJump: (i, tile) => root.jump(i, tile)
            onDismiss: Agents.close()
        }
        Item {
            id: keys
            anchors.fill: parent
            focus: true
            Keys.onPressed: e => view.key(e)
        }
    }
}

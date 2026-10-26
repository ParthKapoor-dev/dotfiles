pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core
import qs.services

// Hot corners (mock #hotcorner): push the pointer into a screen corner and rest there for
// hotCorners.dwellMs (150) to run that corner's action; then 1 s of cooldown, and the pointer has
// to leave the corner before it can fire again, so flicking past a corner does nothing.
// Each corner is its own 2x2 px overlay surface (namespace nox:hotcorners, exclusive zone 0) that
// takes input, unlike modules/corners, whose masks take none on purpose. A corner set to "none"
// gets no surface at all, so a 2 px corner only swallows clicks where an action lives.
// Purely event-driven: the only timer runs while the pointer is inside a corner.
// shell.json hotCorners { tl, tr, bl, br, dwellMs }; actions: overview | desktops |
// controlcenter | launcher | showDesktop | notifications | lock | none. Defaults: tl = overview.
// Hidden on fullscreen workspaces (corners.hideOnFullscreen, same check as modules/corners).
// showDesktop moves this desktop's windows to special:minimized (they show in the dock like any
// minimized window); triggering it again on the same desktop brings back the ones still there.
Scope {
    id: root
    readonly property var opts: Config.opt.hotCorners ?? ({})
    readonly property int dwellMs: Math.max(0, opts.dwellMs ?? 150)
    readonly property int cooldownMs: 1000
    readonly property var names: ["tl", "tr", "bl", "br"]
    readonly property var defaults: ({ tl: "overview", tr: "none", bl: "none", br: "none" })
    readonly property var known: ["overview", "desktops", "controlcenter", "launcher", "showDesktop", "notifications", "lock"]
    function actionFor(corner) {
        const a = opts[corner] ?? defaults[corner];
        return known.indexOf(a) !== -1 ? a : "none";
    }
    // corner indices (0 tl, 1 tr, 2 bl, 3 br) that have an action
    readonly property var live: [0, 1, 2, 3].filter(i => actionFor(names[i]) !== "none")

    property real firedAt: 0
    function fire(action, screen) {
        const now = Date.now();
        if (now - firedAt < cooldownMs) return;
        firedAt = now;
        if (action === "overview") Panels.overviewOpen = !Panels.overviewOpen;
        else if (action === "desktops") Panels.overview("desktops");
        else if (action === "controlcenter") Panels.toggle("controlCenter");
        else if (action === "notifications") Panels.toggle("notifications");
        else if (action === "launcher") Panels.launcherOpen = !Panels.launcherOpen;
        else if (action === "lock") Actions.run("lock");
        else if (action === "showDesktop") showDesktop(screen);
    }

    // ---- show desktop ----
    // (Hypr.moveToWorkspace only takes numeric workspaces in its Lua spelling)
    function moveTo(address, ws) {
        const lit = typeof ws === "number" ? ws : Hypr.str(ws);
        Hypr.dispatch("movetoworkspacesilent " + ws + ",address:" + Hypr.addr(address),
                      "hl.dsp.window.move({ workspace = " + lit + ", follow = false, window = " + Hypr.str("address:" + Hypr.addr(address)) + " })");
    }
    property var stash: null           // { ws: id, addrs: [...] } of the last show-desktop
    function showDesktop(screen) {
        const ws = Hyprland.monitorFor(screen)?.activeWorkspace ?? null;
        if (!ws) return;
        const here = ws.toplevels.values;
        if (here.length === 0) {
            // nothing on this desktop: bring back what the last show-desktop put away here
            if (stash && stash.ws === ws.id) {
                const back = new Set(stash.addrs);
                for (const t of Hyprland.toplevels.values)
                    if (back.has(t.address) && (t.workspace?.name ?? "") === "special:minimized") moveTo(t.address, ws.id);
            }
            stash = null;
            return;
        }
        stash = { ws: ws.id, addrs: here.map(t => t.address) };
        for (const t of here) moveTo(t.address, "special:minimized");
    }

    Variants {
        model: root.live.length ? Quickshell.screens : []

        Scope {
            id: scr
            required property ShellScreen modelData
            readonly property bool hidden: (Config.opt.corners?.hideOnFullscreen ?? true)
                && (Hyprland.monitorFor(modelData)?.activeWorkspace?.hasFullscreen ?? false)
            Variants {
                model: root.live
                PanelWindow {
                    id: c
                    required property int modelData
                    readonly property bool onRight: modelData % 2 === 1
                    readonly property bool onBottom: modelData >= 2
                    readonly property string action: root.actionFor(root.names[modelData])
                    screen: scr.modelData
                    visible: !scr.hidden
                    WlrLayershell.namespace: "nox:hotcorners"
                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    anchors.top: !onBottom; anchors.bottom: onBottom
                    anchors.left: !onRight; anchors.right: onRight
                    implicitWidth: 2; implicitHeight: 2
                    color: "transparent"

                    // armed again only once the pointer has left the corner
                    property bool armed: true
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onContainsMouseChanged: {
                            if (containsMouse) { if (c.armed) dwell.restart(); }
                            else { dwell.stop(); c.armed = true; }
                        }
                    }
                    Timer {
                        id: dwell
                        interval: root.dwellMs
                        onTriggered: { c.armed = false; root.fire(c.action, c.screen); }
                    }
                }
            }
        }
    }
}

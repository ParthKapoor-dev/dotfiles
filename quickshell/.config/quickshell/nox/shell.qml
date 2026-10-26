//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
// nox: the Quickshell shell of the nox desktop.
// Modules are switched on/off in ~/.config/nox/shell.json "modules" (live): Config.moduleEnabled(name),
// defaults for every module in core/Config.qml defaults.modules.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.services
import qs.modules.bar
import qs.modules.dock
import qs.modules.controlcenter
import qs.modules.launcher
import qs.modules.osd
import qs.modules.notifications
import qs.modules.wallpaper
import qs.modules.corners
import qs.modules.overview
import qs.modules.session
import qs.modules.polkit
import qs.modules.cheatsheet
import qs.modules.shot
import qs.modules.desktop
import qs.modules.switcher
import qs.modules.notes
import qs.modules.agents
import qs.modules.ask
import qs.modules.voice
import qs.modules.draw
import qs.modules.shelf
import qs.modules.selbar
import qs.modules.hotcorners
import qs.modules.cursorfind

ShellRoot {
    LazyLoader { active: Config.loaded && Config.moduleEnabled("bar"); component: Bar {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("dock"); component: Dock {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("controlCenter"); component: ControlCenter {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("launcher"); component: Launcher {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("osd"); component: Osd {} }
    // The notification D-Bus server itself is in services/Notifs (same switch).
    LazyLoader { active: Config.loaded && Config.moduleEnabled("notifications"); component: Notifications {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("wallpaper"); component: Background {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("corners"); component: Corners {} }
    // hot corners: rest the pointer in a screen corner (shell.json hotCorners; modules/hotcorners)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("hotCorners"); component: HotCorners {} }
    // shake to find the cursor (cursorFind.enabled, off by default: Hyprland samples the pointer
    // in-process, see modules/cursorfind/detector.lua; IPC target cursorfind)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("cursorFind") && (Config.opt.cursorFind?.enabled ?? false); component: CursorFind {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("overview"); component: Overview {} }
    // Alt+Tab window switcher
    LazyLoader { active: Config.loaded && Config.moduleEnabled("switcher"); component: Switcher {} }
    // floating markdown notepad (Ctrl+Super+S)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("notes"); component: Notes {} }
    // voice typing: hold Super+Shift+Space, speak, release (IPC target voice, `nox voice`).
    // Pill only while in use; whisper-server only while warm (services/Voice)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("voice"); component: VoiceTyping {} }
    // draw on the screen: pointer, pens, shapes, spotlight (Super+A, IPC target draw, `nox draw`)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("draw"); component: Draw {} }
    // coding agents at a glance (Ctrl+Super+M, `nox agents`, IPC target agents)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("agents"); component: AgentsView {} }
    LazyLoader { active: Config.loaded && Config.moduleEnabled("session"); component: Session {} }
    // keyboard shortcuts sheet
    LazyLoader { active: Config.loaded && Config.moduleEnabled("cheatsheet"); component: Cheatsheet {} }
    // post-screenshot card + pinned screenshots (IPC target shot;
    // screenshot.card.enabled: false keeps pins but sends plain notifications instead of the card)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("shot"); component: Shot {} }
    // Circle to Ask: freeze the screen, circle anything, Claude answers beside it (Super+Shift+A,
    // `nox ask`, IPC target ask; shell.json "ask")
    LazyLoader { active: Config.loaded && Config.moduleEnabled("ask"); component: Ask {} }
    // Drop shelf: drag anything to the right screen edge to park it, drag it out into any app later
    // (Super+Shift+D, `nox shelf`, IPC target shelf; shell.json "shelf"; store in services/Shelf)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("shelf"); component: ShelfView {} }
    // selection action bar: select text, a bar of actions appears above the pointer (`nox selbar`,
    // IPC target selbar; shell.json "selbar"; watcher + state in services/Selection)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("selbar"); component: SelBar {} }
    // clock / date / now playing on the empty side of the wallpaper (desktopWidgets.enabled,
    // `nox widgets on|off`; services/DesktopWidgets)
    LazyLoader { active: Config.loaded && DesktopWidgets.ready && DesktopWidgets.enabled; component: Widgets {} }
    // the polkit agent registers on load (only one agent per session; see modules/polkit)
    LazyLoader { active: Config.loaded && Config.moduleEnabled("polkit"); component: Polkit {} }
    // battery charge cap: singletons load on first use; start it now so the cap is re-checked at
    // login and IPC target chargeLimit exists (services/ChargeLimit)
    readonly property bool chargeLimitOn: ChargeLimit.on
    // the countdown timer (services/Countdown, IPC target timer): start it now so a timer from
    // before a restart keeps running
    readonly property bool countdownOn: Countdown.active

    // qs -c nox ipc call controlCenter toggle
    IpcHandler {
        target: "controlCenter"
        function toggle(): void { Panels.toggle("controlCenter"); }
        function open(): void { Panels.open("controlCenter"); }
        function close(): void { Panels.close("controlCenter"); }
    }
    // qs -c nox ipc call dock toggle
    IpcHandler {
        target: "dock"
        // with dock.autohide these reveal/conceal it; otherwise they show/hide it (and its reserved space)
        function toggle(): void { if (Config.opt.dock?.autohide) Panels.dockRevealed = !Panels.dockRevealed; else Panels.dockVisible = !Panels.dockVisible; }
        function open(): void { Panels.dockVisible = true; if (Config.opt.dock?.autohide) Panels.dockRevealed = true; }   // ("show" is reserved by the qs ipc CLI)
        function close(): void { if (Config.opt.dock?.autohide) Panels.dockRevealed = false; else Panels.dockVisible = false; }
    }
    // qs -c nox ipc call popup toggle bar:network   (ids: "controlCenter", "bar:<widgetId>")
    // qs -c nox ipc call popup close                  (closes whatever popup is open)
    IpcHandler {
        target: "popup"
        function toggle(id: string): void { Panels.toggle(id); }
        function open(id: string): void { Panels.open(id); }
        function close(): void { Panels.close(); }
        function current(): string { return Panels.popup; }
    }

    // qs -c nox ipc call switcher next | prev | commit | cancel
    IpcHandler {
        target: "switcher"
        function next(): void { Panels.switcherCommand("next"); }
        function prev(): void { Panels.switcherCommand("prev"); }
        function commit(): void { Panels.switcherCommand("commit"); }
        function cancel(): void { Panels.switcherCommand("cancel"); }
    }
    // qs -c nox ipc call overview toggle | open | close | windows | desktops | next | prev
    IpcHandler {
        target: "overview"
        function toggle(): void { Panels.overviewOpen = !Panels.overviewOpen; }
        function open(): void { Panels.overviewOpen = true; }
        // open in that view; again = close, from the other view = switch (Super+Tab / Super+Shift+Tab)
        function windows(): void { Panels.overview("windows"); }
        function desktops(): void { Panels.overview("desktops"); }
        function mode(): string { return Panels.overviewMode; }
        function close(): void { Panels.overviewOpen = false; }
        // while open: next / previous desktop without closing (the arrow keys)
        function next(): void { Panels.overviewStep(1); }
        function prev(): void { Panels.overviewStep(-1); }
    }
    // qs -c nox ipc call cheatsheet toggle | open | close
    IpcHandler {
        target: "cheatsheet"
        function toggle(): void { Panels.cheatsheetOpen = !Panels.cheatsheetOpen; }
        function open(): void { Panels.cheatsheetOpen = true; }
        function close(): void { Panels.cheatsheetOpen = false; }
    }
    // qs -c nox ipc call session toggle | open | close
    IpcHandler {
        target: "session"
        function toggle(): void { Panels.sessionOpen = !Panels.sessionOpen; }
        function open(): void { Panels.sessionOpen = true; }
        function close(): void { Panels.sessionOpen = false; }
    }
    // qs -c nox ipc call wallpaper set <path> | get | fill <cover|fit|stretch|center|tile> | reset
    //   slideshowStart | slideshowStop | slideshowNext | slideshowPrev | slideshowAdd <path>
    //   slideshowRemove <path> | slideshowMove <path> <delta> | slideshowClear
    //   slideshowList (paths in order) | slideshowStatus ("on|off <minutes> <count>") | slideshowInterval (minutes)
    IpcHandler {
        target: "wallpaper"
        function set(path: string): void { Wallpaper.set(path); }
        function get(): string { return Wallpaper.path; }
        function fill(mode: string): void { Wallpaper.setFill(mode); }
        function reset(): void { Wallpaper.reset(); }
        function slideshowStart(): void { Wallpaper.slideshow.start(); }
        function slideshowStop(): void { Wallpaper.slideshow.stop(); }
        function slideshowNext(): void { Wallpaper.slideshow.next(); }
        function slideshowPrev(): void { Wallpaper.slideshow.prev(); }
        function slideshowAdd(path: string): void { Wallpaper.slideshow.add(path); }
        function slideshowRemove(path: string): void { Wallpaper.slideshow.remove(path); }
        function slideshowMove(path: string, delta: int): bool { return Wallpaper.slideshow.move(path, delta); }
        function slideshowClear(): void { Wallpaper.slideshow.clear(); }
        function slideshowList(): string { return Wallpaper.slideshow.paths.join("\n"); }
        function slideshowStatus(): string { const s = Wallpaper.slideshow; return (s.on ? "on " : "off ") + s.minutes + " " + s.paths.length; }
        function slideshowInterval(): real { return Wallpaper.slideshow.minutes; }
    }
    // qs -c nox ipc call action run <name>   (names: services/Actions.qml) | list
    IpcHandler {
        target: "action"
        function run(name: string): bool { return Actions.run(name); }
        function list(): string { return Object.keys(Actions.table).join(" "); }
    }
    // qs -c nox ipc call widgets toggle | on | off | side <left|right|auto> | reset | status
    IpcHandler {
        target: "widgets"
        function toggle(): void { DesktopWidgets.toggle(); }
        function on(): void { DesktopWidgets.setEnabled(true); }
        function off(): void { DesktopWidgets.setEnabled(false); }
        function side(s: string): bool { return DesktopWidgets.setSide(s); }
        function reset(): void { DesktopWidgets.reset(); }
        function status(): string { return DesktopWidgets.status(); }
    }
    // qs -c nox ipc call timer start <time> <label> | stop | pause | resume | toggle | add <time> | status | left
    // (`nox timer`; services/Countdown, shown by the bar island)
    IpcHandler {
        target: "timer"
        function start(spec: string, label: string): string {
            const ms = Countdown.parse(spec);
            if (ms <= 0) return "error: not a duration: '" + spec + "' (5m, 90s, 1h30m, 1:30, 25)";
            Countdown.start(ms, label);
            return Countdown.status();
        }
        function stop(): bool { return Countdown.stop(); }
        function pause(): bool { return Countdown.pause(); }
        function resume(): bool { return Countdown.resume(); }
        function toggle(): bool { return Countdown.togglePause(); }
        function add(spec: string): string {
            const s = String(spec).trim();
            const ms = Countdown.parse(s.replace(/^[-+]\s*/, ""));
            if (ms <= 0) return "error: not a duration: '" + spec + "'";
            Countdown.add(s.startsWith("-") ? -ms : ms);
            return Countdown.status();
        }
        function status(): string { return Countdown.status(); }
        function left(): int { return Math.ceil(Countdown.left / 1000); }
    }
    // qs -c nox ipc call hud show "<text>"
    IpcHandler {
        target: "hud"
        function show(text: string): void { Panels.hud(text, "check"); }
    }

    // qs -c nox ipc call layout changed <name>   (sent by nox layout after every change)
    // qs -c nox ipc call layout get | next | prev | set <name>
    IpcHandler {
        target: "layout"
        function changed(name: string): void { Layout.changed(name); }
        function get(): string { return Layout.name; }
        function next(): void { Layout.next(); }
        function prev(): void { Layout.prev(); }
        function set(name: string): void { Layout.set(name); }
    }

    // launcher IPC (toggle|open|close|search|results) lives in modules/launcher/Launcher.qml
    // qs -c nox ipc call notifications toggle       (Notification Center)
    // qs -c nox ipc call notifications toggleDnd    | setDnd true|false | clear | dnd | status
    IpcHandler {
        target: "notifications"
        function toggle(): void { Panels.toggle("notifications"); }
        function open(): void { Panels.open("notifications"); }
        function close(): void { Panels.close("notifications"); }
        function toggleDnd(): void { Notifs.toggleDnd(); }
        function setDnd(on: bool): void { Notifs.setDnd(on); }
        function dnd(): bool { return Notifs.dnd; }
        function clear(): void { Notifs.clearAll(); }
        function clearApp(app: string): void { Notifs.clearApp(app); }
        // "server=<registered> dnd=<bool> count=<history> popups=<on screen>"
        function status(): string { return "server=" + Notifs.running + " dnd=" + Notifs.dnd + " count=" + Notifs.count + " popups=" + Notifs.popups.length; }
    }

    // Hyprland global shortcuts (appid "nox"). Not registered in lint runs (NOX_LINT=1),
    // so a syntax check never competes with the live instance for the same shortcut names.
    LazyLoader {
        active: !Quickshell.env("NOX_LINT")
        component: Scope {
        // shortcuts (appid "nox"): bind with hl.dsp.global("nox:<name>").
        // launcherToggleRelease + launcherToggleReleaseInterrupt = "tap Super to open" (same pattern as ii).
        GlobalShortcut {
            appid: "nox"; name: "launcherToggle"; description: "Toggle the launcher"
            onPressed: Panels.launcherOpen = !Panels.launcherOpen
        }
        GlobalShortcut {
            id: superTap
            appid: "nox"; name: "launcherToggleRelease"; description: "Toggle the launcher when Super is released alone"
            property bool mightTrigger: false
            property bool pressGuard: false
            onPressed: { mightTrigger = true; pressGuard = true; }
            onReleased: {
                pressGuard = false;
                if (mightTrigger) Panels.launcherOpen = !Panels.launcherOpen;
                mightTrigger = false;
            }
        }
        GlobalShortcut {
            appid: "nox"; name: "launcherToggleReleaseInterrupt"; description: "Cancel the Super-tap launcher toggle (bind to a catchall)"
            // the catchall also fires on the Super press itself (Hyprland 0.55.3+): absorb that one
            onPressed: { if (superTap.pressGuard) { superTap.pressGuard = false; return; } superTap.mightTrigger = false; }
        }
        // Alt+Tab: next / prev step the switcher; switcherAlt (Alt release) commits the selection
        GlobalShortcut { appid: "nox"; name: "notesToggle"; description: "Show / hide Notes"; onPressed: Panels.notesCommand("toggle") }
        GlobalShortcut { appid: "nox"; name: "switcherNext"; description: "Window switcher: next (Alt+Tab)"; onPressed: Panels.switcherCommand("next") }
        GlobalShortcut { appid: "nox"; name: "switcherPrev"; description: "Window switcher: previous (Alt+Shift+Tab)"; onPressed: Panels.switcherCommand("prev") }
        // bound as a release bind: Hyprland delivers it at the Alt release (as a press and/or release
        // event depending on version), so both commit; the second one finds the switcher closed
        GlobalShortcut { appid: "nox"; name: "switcherAlt"; description: "Window switcher: Alt released = switch"; onPressed: Panels.switcherCommand("commit"); onReleased: Panels.switcherCommand("commit") }
        GlobalShortcut {
            appid: "nox"; name: "notificationCenterToggle"; description: "Toggle the Notification Center"
            onPressed: Panels.toggle("notifications")
        }
        GlobalShortcut {
            appid: "nox"; name: "dndToggle"; description: "Toggle Do Not Disturb"
            onPressed: Notifs.toggleDnd()
        }
        GlobalShortcut {
            appid: "nox"; name: "controlCenterToggle"; description: "Toggle the Control Center"
            onPressed: Panels.toggle("controlCenter")
        }
        GlobalShortcut {
            appid: "nox"; name: "overviewToggle"; description: "Toggle Mission Control"
            onPressed: Panels.overviewOpen = !Panels.overviewOpen
        }
        GlobalShortcut {
            appid: "nox"; name: "cheatsheetToggle"; description: "Keyboard shortcuts sheet"
            onPressed: Panels.cheatsheetOpen = !Panels.cheatsheetOpen
        }
        GlobalShortcut {
            appid: "nox"; name: "sessionToggle"; description: "Toggle the power menu"
            onPressed: Panels.sessionOpen = !Panels.sessionOpen
        }
        GlobalShortcut {
            appid: "nox"; name: "clipboardToggle"; description: "Clipboard history in the launcher"
            onPressed: { if (Panels.launcherOpen) Panels.launcherOpen = false; else Panels.openLauncher(":"); }
        }
        GlobalShortcut {
            appid: "nox"; name: "dockToggle"; description: "Reveal / hide the dock"
            onPressed: { if (Config.opt.dock?.autohide) Panels.dockRevealed = !Panels.dockRevealed; else Panels.dockVisible = !Panels.dockVisible; }
        }
        GlobalShortcut {
            appid: "nox"; name: "screenshot"; description: "Region screenshot"
            onPressed: Actions.run("screenshot")
        }
        GlobalShortcut {
            appid: "nox"; name: "recordToggle"; description: "Start / stop screen recording"
            onPressed: Recorder.toggle()
        }
        }
    }
}

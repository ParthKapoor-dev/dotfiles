pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core

// Named shell actions shared by the logo menu, session menu, launcher commands, Control Center
// tiles and IPC. Config items can say { "action": "<name>" } instead of a command.
// Session commands are configurable: shell.json session.commands.{lock,sleep,restart,poweroff}.
Singleton {
    id: root
    readonly property var sessionCmds: Object.assign({
        lock: ["loginctl", "lock-session"],
        sleep: ["systemctl", "suspend"],
        restart: ["systemctl", "reboot"],
        poweroff: ["systemctl", "poweroff"]
    }, Config.opt.session?.commands ?? {})

    readonly property var table: ({
        lock: () => Quickshell.execDetached(root.sessionCmds.lock),
        sleep: () => Quickshell.execDetached(root.sessionCmds.sleep),
        restart: () => Quickshell.execDetached(root.sessionCmds.restart),
        poweroff: () => Quickshell.execDetached(root.sessionCmds.poweroff),
        logout: () => Hypr.exit(),
        controlCenter: () => Panels.toggle("controlCenter"),
        notifications: () => Panels.toggle("notifications"),
        dnd: () => Notifs.toggleDnd(),
        dock: () => { Panels.dockVisible = !Panels.dockVisible; },
        launcher: () => { Panels.launcherOpen = !Panels.launcherOpen; },
        clipboard: () => Panels.openLauncher(":"),
        wallpapers: () => Panels.openLauncher("# "),
        wallpaperSlideshow: () => Panels.openLauncher("% "),
        defaultApps: () => Panels.openLauncher("! "),
        overview: () => { Panels.overviewOpen = !Panels.overviewOpen; },
        session: () => { Panels.sessionOpen = !Panels.sessionOpen; },
        screenshot: () => Quickshell.execDetached(Config.opt.screenshot?.command ?? root.screenshotCmd),
        record: () => Recorder.toggle(),
        nightLight: () => NightLight.toggle(),
        caffeine: () => { Panels.caffeine = !Panels.caffeine; },
        chargeLimit: () => ChargeLimit.toggle(),
        layoutNext: () => Layout.next(),
        forceQuit: () => Hypr.killActive(),
        // desktop widgets (services/DesktopWidgets.qml)
        desktopWidgets: () => DesktopWidgets.toggle(),
        widgetsLeft: () => DesktopWidgets.setSide("left"),
        widgetsRight: () => DesktopWidgets.setSide("right"),
        widgetsAuto: () => DesktopWidgets.setSide("auto"),
        // phone link (services/Phone.qml, kdeconnect-rs)
        phoneClip: () => Phone.sendClipboard(),
        phoneSend: () => Phone.pickAndSend(),
        phoneRing: () => Phone.ring(),
        phonePair: () => Phone.pair(),
        about: () => { about.running = true; }
    })
    // region screenshot -> clipboard + screenshot card (nox shot; Save on the card keeps it)
    readonly property var screenshotCmd: ["sh", "-c", "sleep 0.3; exec nox shot region"]

    Process {
        id: about
        command: ["hyprctl", "-j", "version"]
        stdout: StdioCollector {
            onStreamFinished: {
                let v = "";
                try { v = JSON.parse(text).tag ?? ""; } catch (e) {}
                Panels.hud("Nox · Hyprland " + v.replace(/^v/, "") + " · Arch Linux", "logo");
            }
        }
    }

    function has(name) { return table[name] !== undefined; }
    function run(name) {
        const f = table[name];
        if (!f) { console.warn("nox: unknown action", name); return false; }
        f();
        return true;
    }
    // menu/command item: { action } | { command: [argv] }
    function runItem(it) {
        if (it.action) return run(it.action);
        if (it.command) { Quickshell.execDetached(it.command); return true; }
        return false;
    }
}

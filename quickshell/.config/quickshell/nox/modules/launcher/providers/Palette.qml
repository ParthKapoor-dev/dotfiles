import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// Command palette, prefix ">" (Ctrl+Super+Space = `qs -c nox ipc call launcher palette`): one fuzzy
// list of everything the desktop can do, every `nox` CLI feature included. Type tag on the right =
// category; rows that have a Hyprland bind show its keycaps too, so the palette teaches the shortcuts.
//   Toggle      Wi-Fi, Bluetooth, Night Light, Do Not Disturb, Caffeine, Battery protection, Dock
//               auto-hide, Desktop widgets, Wallpaper slideshow, Screen recording; state = subtitle
//   Settings    one row per `nox` module that has choices or needs an argument; Enter opens its level
//               (nested: Esc / Backspace on an empty filter / "Back" return). Choices mark the current
//               one with ✓. Levels: Look (theme), Tiling layout, Desktop widgets, Battery, Phone link,
//               Sessions (workspaces: save / save as typed name / restore / pick / delete), Wallpaper
//               (slideshow, fill, lock screen image, prep typed path), Login screen (greeter), Screen
//               power (dpms), Shell, Hyprland config
//   Shell / Session / Window
//               every services/Actions name (labels below, else its commands.items label, else title-cased)
//   Capture     nox shot (region / copy / window / monitor / OCR / pin last), nox record (3 kinds)
//   Command     launcher.provider.commands items that run a non-nox command
//   <bind group> every labelled bind from services/Binds (the cheatsheet's source), run in place
// Typing searches the levels' rows too ("widgets right", "lock image"), so nothing is two steps away.
// A row's `bind` names bind labels: it borrows their keycaps and those binds are not listed again.
// Destructive rows ask first (confirm); sudo-only commands (greeter install / on / off) are hint rows
// that copy the command. Status-like commands report through a notification. Empty query = recently
// used first (Frecency "palette"), then everything in the order above. Each launcher session
// re-reads the bind table (Lua bind refs), looks, saved sessions, lock image and greeter state.
// options: recent (rows on top for an empty query, default 8)
Item {
    id: root
    property string providerId: "palette"
    readonly property var options: Config.launcherProvider(providerId)
    property string defaultPrefix: ">"
    property bool defaultPrefixOnly: true
    signal resultsChanged()                 // the launcher re-runs the search when this fires

    // ---- levels (nested): the launcher sends Esc / Backspace-on-empty to back()
    property string level: ""
    readonly property var levelDef: level ? (levels().find(l => l.id === level) ?? null) : null
    readonly property bool nested: levelDef !== null
    property string name: levelDef ? levelDef.title : "Command Palette"
    function back() { level = ""; }
    // every session starts at the top level with fresh state (another tool may have changed it)
    Connections {
        target: Panels
        function onLauncherOpenChanged() {
            root.level = "";
            if (Panels.launcherOpen) { root.poll(); root.resultsChanged(); }
        }
    }
    Connections {
        target: Binds
        function onLoaded() { root.resultsChanged(); }
    }

    // ---- running nox: it lives in ~/.local/bin, which may not be on the shell's PATH
    readonly property string noxFn: "n() { if command -v nox >/dev/null 2>&1; then nox \"$@\"; else \"$HOME/.local/bin/nox\" \"$@\"; fi; }; "
    function noxArgv(args) { return ["sh", "-c", root.noxFn + "n \"$@\"", "sh"].concat(args); }
    // the short sleep lets the launcher close first (captures, region pickers)
    function nox(args) { Quickshell.execDetached(["sh", "-c", "sleep 0.2; " + root.noxFn + "n \"$@\"", "sh"].concat(args)); }
    // status / check commands: their output as a notification
    function report(title, args) {
        Quickshell.execDetached(["sh", "-c", root.noxFn + "t=$1; shift; out=$(n \"$@\" 2>&1); notify-send -a Nox \"$t\" \"$(printf %s \"$out\" | tail -c 1500)\"", "sh", title].concat(args));
    }
    // long-running output (logs): in a terminal
    function inTerminal(args) {
        const term = Config.launcherProvider("run").terminal ?? ["ghostty", "-e"];
        Quickshell.execDetached(term.concat(root.noxArgv(args)));
    }
    // sudo-only commands are not run from here: copy them for a terminal
    function copyCommand(cmd) {
        Quickshell.execDetached(["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", cmd]);
        Panels.hud("Copied: " + cmd, "clip");
    }
    function title(s) { return s.split(/[-_ ]/).map(w => w.charAt(0).toUpperCase() + w.slice(1)).join(" "); }
    function onOff(v) { return v ? "On" : "Off"; }
    function mark(t, cur) { return cur ? t + "  ✓" : t; }
    function hud(t, g) { Panels.hud(t, g); }

    // ---- async state, read once per launcher session (poll) -------------------------------------
    component Probe: Process {
        id: pr
        property var parse: t => t
        property var value: null
        stdout: StdioCollector {
            onStreamFinished: { pr.value = pr.parse(text); root.resultsChanged(); }
        }
    }
    // `nox theme switch`: looks, "* " = current
    Probe {
        id: looksProbe
        command: root.noxArgv(["theme", "switch"])
        parse: t => t.split("\n").map(x => x.replace(/^\*?\s*/, "").trim()).filter(x => /^[\w.-]+$/.test(x))
    }
    // `nox workspaces list`: "<name>  2026-10-18 11:30  3 windows  ws 1,2"
    Probe {
        id: sessionsProbe
        command: root.noxArgv(["workspaces", "list"])
        parse: t => t.split("\n").map(l => /^(\S+)\s+(\d{4}-\d\d-\d\d \d\d:\d\d)\s+(\d+) windows?\s+ws (.*)$/.exec(l))
                     .filter(m => m).map(m => ({ name: m[1], when: m[2], windows: +m[3], ws: m[4] }))
    }
    // `nox wallpaper lock`: "follows the desktop wallpaper" | "pinned: <path>"
    Probe {
        id: lockProbe
        command: root.noxArgv(["wallpaper", "lock"])
        parse: t => { const m = /pinned: (.*)/.exec(t); return m ? m[1].trim() : ""; }
    }
    // `nox greeter status`: "login screen: nox greeter (ON)", "synced: telemetry look, <date>"
    Probe {
        id: greeterProbe
        command: root.noxArgv(["greeter", "status"])
        parse: t => ({
            on: /login screen:.*\(ON\)/.test(t),
            installed: /installed:\s+\//.test(t),
            synced: (/synced:\s+(.*)/.exec(t) ?? [])[1] ?? ""
        })
    }
    property real polledAt: 0
    function poll() {
        Binds.refreshIfOlder(1500);
        if (Date.now() - polledAt < 1500) return;
        polledAt = Date.now();
        for (const p of [looksProbe, sessionsProbe, lockProbe, greeterProbe]) if (!p.running) p.running = true;
    }

    // ---- services/Actions: name -> row. toggles / levels / launcher cover the rest
    readonly property var skipActions: ["dnd", "nightLight", "caffeine", "chargeLimit", "record", "launcher",
        "phoneClip", "phoneSend", "phoneRing", "phonePair", "desktopWidgets", "widgetsLeft", "widgetsRight", "widgetsAuto"]
    readonly property var actionDefs: ({
        lock: { t: "Lock screen", icon: "lock", cat: "Session", bind: ["Lock screen"] },
        sleep: { t: "Sleep", icon: "moon", cat: "Session", bind: ["Suspend"], confirm: "Sleep now?", kw: "suspend" },
        logout: { t: "Log out", icon: "logout", cat: "Session", confirm: "Log out now?", kw: "sign out exit hyprland" },
        restart: { t: "Restart computer", icon: "restart", cat: "Session", confirm: "Restart now?", kw: "reboot" },
        poweroff: { t: "Shut down", icon: "power", cat: "Session", bind: ["Shut down"], confirm: "Shut down now?", kw: "power off halt" },
        session: { t: "Power menu", icon: "power", cat: "Session", bind: ["Open session menu"], kw: "session logout shutdown" },
        controlCenter: { t: "Control Center", icon: "cc", cat: "Shell", bind: ["Open Control Center", "Open Control Center (Now Playing)"], kw: "settings now playing media" },
        notifications: { t: "Notification Center", icon: "bell", cat: "Shell", bind: ["Open notification center"] },
        overview: { t: "Mission Control", icon: "grid", cat: "Shell", bind: ["Open overview"], kw: "overview expose workspaces" },
        clipboard: { t: "Clipboard history", icon: "clip", cat: "Shell", bind: ["Open clipboard history"], kw: "paste cliphist" },
        dock: { t: "Show / hide dock", icon: "grid", cat: "Shell", bind: ["Toggle dock"] },
        defaultApps: { t: "Default apps", icon: "settings", cat: "Shell", kw: "browser file manager mime open with xdg" },
        about: { t: "About this desktop", icon: "logo", cat: "Shell", kw: "version hyprland" },
        wallpapers: { t: "Choose wallpaper", icon: "image", cat: "Wallpaper", bind: ["Choose wallpaper"], kw: "background picture pick" },
        wallpaperSlideshow: { t: "Edit wallpaper slideshow", icon: "play", cat: "Wallpaper", kw: "cycle rotate list" },
        screenshot: { t: "Screenshot region", icon: "shot", cat: "Capture", kw: "capture grim slurp" },
        layoutNext: { t: "Next layout", icon: "layout", cat: "Window", bind: ["Next layout"], kw: "tiling scrolling master dwindle" },
        forceQuit: { t: "Force quit active window", icon: "x", cat: "Window", confirm: "Force quit the active window?", kw: "kill close" }
    })

    // binds that end the session or take the keyboard away ask first
    readonly property var dangerous: /shut ?down|power ?off|reboot|restart(?! shell)|log ?out|suspend|force kill|vm mode/i

    // ---- levels: { id, title, icon, kw, sub, rows(text) -> [row] }; row.typed = only inside the
    // level (it uses the typed text), row.flat = title when searched from the top level, row.levelOnly =
    // not searched from there (a top-level row does the same)
    function levels() {
        const ss = Wallpaper.slideshow;
        const out = [];

        // theme looks
        const cur = Theme.t.name ?? "ember";
        const looks = looksProbe.value?.length ? looksProbe.value
            : (Config.opt.controlCenter?.looks ?? ["default", "telemetry"]).map(p => p === "default" ? "ember" : p);
        out.push({ id: "look", title: "Look", icon: "sparkle", kw: "theme look style appearance colors nox theme", sub: root.title(cur), rows: () => looks.map(l => ({
            key: "look:" + l, title: root.mark(root.title(l), l === cur), flat: "Look: " + root.title(l), icon: "sparkle", actLabel: "Switch",
            run: () => { root.hud("Look: " + root.title(l), "sparkle"); root.nox(["theme", "switch", l]); }
        })).concat([
            { key: "theme:check", title: "Check theme outputs", icon: "check", sub: "nox theme check", run: () => root.report("Theme check", ["theme", "check"]) },
            { key: "theme:diff", title: "Show pending theme changes", icon: "doc", sub: "nox theme diff", run: () => root.inTerminal(["theme", "diff"]) },
            { key: "theme:apply", title: "Apply theme to app configs", icon: "sparkle", sub: "nox theme apply (backs up first)", confirm: "Hook the theme into app configs?", run: () => root.report("Theme apply", ["theme", "apply"]) },
            { key: "theme:revert", title: "Revert theme hooks", icon: "restart", sub: "nox theme revert: app configs back to pre-nox", confirm: "Revert every app config to its pre-nox backup?", run: () => root.report("Theme revert", ["theme", "revert"]) }
        ]) });

        // tiling layout
        out.push({ id: "layout", title: "Tiling layout", icon: Layout.glyph, kw: "layout tiling dwindle master scrolling monocle nox layout", sub: Layout.label, rows: () =>
            ["dwindle", "scrolling", "master", "monocle"].map(n => ({
                key: "layout:" + n, title: root.mark(Layout.labels[n] ?? root.title(n), Layout.name === n), flat: "Layout: " + (Layout.labels[n] ?? n),
                icon: Layout.glyphs[n] ?? "layout", sub: n, run: () => Layout.set(n)
            })).concat([
                { key: "layout:next", levelOnly: true, title: "Next layout", icon: "arrowR", bind: ["Next layout"], run: () => Layout.next() },
                { key: "layout:prev", title: "Previous layout", icon: "chevL", bind: ["Previous layout"], run: () => Layout.prev() }
            ]) });

        // desktop widgets (nox widgets)
        const dw = DesktopWidgets;
        const sideSub = s => s === "auto" ? "darker side of the wallpaper" + (dw.side === "auto" ? " · now " + dw.resolvedSide : "") : "";
        out.push({ id: "widgets", title: "Desktop widgets", icon: "desktop", kw: "widgets clock desktop column side nox widgets", sub: root.onOff(dw.enabled) + " · " + dw.side, rows: () => [
            { key: "widgets:on", title: root.mark("On", dw.enabled), flat: "Desktop widgets: On", icon: "desktop", run: () => { dw.setEnabled(true); root.hud("Desktop widgets on", "desktop"); } },
            { key: "widgets:off", title: root.mark("Off", !dw.enabled), flat: "Desktop widgets: Off", icon: "desktop", run: () => { dw.setEnabled(false); root.hud("Desktop widgets off", "desktop"); } }
        ].concat(["left", "right", "auto"].map(s => ({
            key: "widgets:" + s, title: root.mark("Side: " + root.title(s), dw.side === s), flat: "Widgets side: " + root.title(s), icon: "desktop", sub: sideSub(s),
            run: () => { dw.setSide(s); root.hud("Widgets: " + s, "desktop"); }
        }))).concat([
            { key: "widgets:reset", title: "Reset to shell.json", flat: "Desktop widgets: reset", icon: "restart", sub: "drops the on/off and side picks", run: () => { dw.reset(); root.hud("Desktop widgets reset", "desktop"); } }
        ]) });

        // battery (nox battery)
        const cl = ChargeLimit;
        out.push({ id: "battery", title: "Battery charge limit", icon: "leaf", kw: "battery charge limit protect full 80 100 health travel nox battery",
            sub: cl.supported ? cl.label + (cl.ok ? "" : " · firmware has " + cl.applied + "%") : "not supported here", rows: () => [
            { key: "battery:protect", title: root.mark("Protect: stop at " + cl.cap + "%", cl.on), flat: "Battery: protect at " + cl.cap + "%", icon: "leaf", run: () => cl.set(true) },
            { key: "battery:full", title: root.mark("Full charge: 100%", !cl.on), flat: "Battery: full charge 100%", icon: "bolt", sub: "for travel; protect again afterwards", run: () => cl.set(false) },
            { key: "battery:reapply", title: "Re-apply the limit", flat: "Battery: re-apply limit", icon: "reload", sub: "if the firmware lost it", run: () => root.report("Battery", ["battery", "reapply"]) },
            { key: "battery:status", title: "Battery status", icon: "gauge", sub: "nox battery status", run: () => root.report("Battery", ["battery", "status"]) }
        ] });

        // phone link (nox phone)
        const ph = Phone.device;
        const psub = ph ? ph.name + (Phone.connected ? (Phone.deviceBattery ? " · " + Phone.deviceBattery.level + "%" : "") : " · not reachable") : "";
        out.push({ id: "phone", title: "Phone link", icon: "phone", kw: "phone kde connect android nox phone",
            sub: !Phone.available ? "Off" : ph ? psub : "On · no paired phone", rows: () => {
            const r = [
                { key: "phone:on", title: root.mark("Daemon on", Phone.available), flat: "Phone link: on", icon: "phone", sub: "for this session", run: () => root.report("Phone link", ["phone", "on"]) },
                { key: "phone:off", title: root.mark("Daemon off", !Phone.available), flat: "Phone link: off", icon: "phone", run: () => root.report("Phone link", ["phone", "off"]) },
                { key: "phone:pair", title: "Pair phone", icon: "key", sub: ph ? "Paired with " + ph.name : "Shows the pairing steps", run: () => Phone.pair() }
            ];
            if (Phone.pairRequest)
                r.push({ key: "phone:accept", title: "Accept pairing from " + Phone.pairRequest.name, icon: "check", sub: "The phone is waiting", run: () => Phone.answerPair(true) });
            if (Phone.connected) r.push(
                { key: "phone:ring", title: "Ring phone", icon: "bell", sub: psub, run: () => Phone.ring() },
                { key: "phone:clip", title: "Send clipboard to phone", icon: "clip", sub: psub, run: () => Phone.sendClipboard() },
                { key: "phone:send", title: "Send file to phone…", icon: "send", sub: psub, run: () => Phone.pickAndSend() });
            r.push({ key: "phone:status", title: "Phone link status", icon: "gauge", sub: "nox phone status", run: () => root.report("Phone link", ["phone", "status"]) },
                   { key: "phone:logs", title: "Phone daemon log", icon: "doc", sub: "nox phone logs -f (terminal)", run: () => root.inTerminal(["phone", "logs", "-f"]) });
            return r;
        } });

        // sessions (nox workspaces): typed text = the name for "Save as"
        const sessions = sessionsProbe.value ?? [];
        out.push({ id: "sessions", title: "Sessions", icon: "layout", kw: "session workspaces save restore windows apps snapshot nox workspaces",
            sub: sessions.length ? sessions.length + " saved · newest " + sessions[0].name : "none saved", rows: text => {
            const r = [];
            const name = text.trim();
            if (name) r.push(/^[A-Za-z0-9._-]{1,64}$/.test(name)
                ? { key: "ws:saveas", typed: true, title: "Save session as “" + name + "”", icon: "download", actLabel: "Save",
                    sub: sessions.some(s => s.name === name) ? "replaces the saved one" : "open windows and their layout",
                    confirm: sessions.some(s => s.name === name) ? "Replace session “" + name + "”?" : "",
                    run: () => root.nox(["workspaces", "save", name, "--notify"]) }
                : { key: "ws:badname", typed: true, title: "“" + name + "” can't be a session name", icon: "x", sub: "letters, digits, . _ - only", stay: true, run: () => {} });
            r.push({ key: "ws:save", title: "Save session", icon: "download", sub: "as “default” · type a name to save as", flat: "Sessions: save", run: () => root.nox(["workspaces", "save", "--notify"]) });
            if (sessions.length)
                r.push({ key: "ws:restore", title: "Restore last session", icon: "reload", sub: sessions[0].name + " · " + sessions[0].when, run: () => root.nox(["workspaces", "restore", "--notify"]) });
            r.push({ key: "ws:pick", title: "Restore session… (picker)", icon: "list", sub: "nox workspaces pick", run: () => root.nox(["workspaces", "pick", "--notify"]) });
            for (const s of sessions)
                r.push({ key: "ws:restore:" + s.name, title: "Restore “" + s.name + "”", icon: "reload", sub: s.when + " · " + s.windows + " windows · ws " + s.ws,
                         run: () => root.nox(["workspaces", "restore", s.name, "--notify"]) });
            for (const s of sessions)
                r.push({ key: "ws:rm:" + s.name, title: "Delete “" + s.name + "”", icon: "trash", sub: s.when + " · " + s.windows + " windows",
                         confirm: "Delete session “" + s.name + "”?", run: () => root.report("Sessions", ["workspaces", "rm", s.name]) });
            return r;
        } });

        // wallpaper (nox wallpaper): typed text starting with / or ~ = a path for prep
        const lockPinned = lockProbe.value ?? "";
        out.push({ id: "wallpaper", title: "Wallpaper", icon: "image", kw: "wallpaper background slideshow lock fill prep nox wallpaper",
            sub: (Wallpaper.path.split("/").pop() || "none") + (ss.on ? " · slideshow on" : ""), rows: text => {
            const r = [];
            const p = text.trim();
            if (/^[\/~]/.test(p))
                r.push({ key: "wall:prep", typed: true, title: "Prep wallpapers from “" + p + "”", icon: "sparkle", actLabel: "Prep",
                         sub: "-> ~/Pictures/Wallpapers/prepped (screen shape, dark strip, grain)",
                         run: () => root.report("Wallpaper prep", ["wallpaper", "prep", p.replace(/^~(?=\/|$)/, Wallpaper.home)]) });
            r.push({ key: "wall:pick", levelOnly: true, title: "Choose wallpaper…", icon: "image", bind: ["Choose wallpaper"], run: () => Actions.run("wallpapers") },
                   { key: "wall:random", title: "Random wallpaper", icon: "image", bind: ["Random wallpaper"], run: () => root.nox(["wallpaper", "random"]) });
            if (ss.paths.length) {
                const st = (ss.index + 1) + " of " + ss.paths.length + (ss.on ? "" : " · paused");
                r.push({ key: "wall:ssOn", title: root.mark("Slideshow on", ss.on), flat: "Wallpaper slideshow: start", icon: "play", sub: "every " + ss.minutes + " min", run: () => ss.start() },
                       { key: "wall:ssOff", title: root.mark("Slideshow off", !ss.on), flat: "Wallpaper slideshow: stop", icon: "pause", run: () => ss.stop() },
                       { key: "wall:next", title: "Next wallpaper", flat: "Slideshow: next wallpaper", icon: "next", sub: st, run: () => ss.next() },
                       { key: "wall:prev", title: "Previous wallpaper", flat: "Slideshow: previous wallpaper", icon: "prev", sub: st, run: () => ss.prev() });
            }
            r.push({ key: "wall:ssEdit", title: "Edit slideshow list…", icon: "list", sub: "Ctrl+Enter in the picker adds / removes", run: () => Actions.run("wallpaperSlideshow") });
            for (const f of ["cover", "contain", "center", "tile"])
                r.push({ key: "wall:fill:" + f, title: root.mark("Fill: " + root.title(f), Wallpaper.fill === f), flat: "Wallpaper fill: " + root.title(f), icon: "expand",
                         run: () => Wallpaper.setFill(f) });
            r.push({ key: "wall:lockFollow", title: root.mark("Lock screen image: follow the desktop", lockProbe.value !== null && !lockPinned), icon: "lock",
                     run: () => root.report("Lock screen image", ["wallpaper", "lock", "follow"]) },
                   { key: "wall:lockPin", title: root.mark("Lock screen image: pin this wallpaper", !!lockPinned && lockPinned === Wallpaper.path), icon: "lock",
                     sub: lockPinned && lockPinned !== Wallpaper.path ? "pinned now: " + lockPinned.split("/").pop() : (Wallpaper.path.split("/").pop() || ""),
                     run: () => root.report("Lock screen image", ["wallpaper", "lock", Wallpaper.path]) });
            if (!/^[\/~]/.test(p))
                r.push({ key: "wall:prepHint", title: "Prep wallpapers…", icon: "sparkle", sub: "type a folder or image path (~/…)", stay: true, run: () => {} });
            return r;
        } });

        // login screen (nox greeter); install / on / off need sudo: hint rows copy the command
        const gs = greeterProbe.value;
        out.push({ id: "greeter", title: "Login screen", icon: "user", kw: "greeter login greetd lock nox greeter",
            sub: gs ? (gs.on ? "nox greeter on" : gs.installed ? "installed, not active" : "not installed") + (gs.synced ? " · synced " + gs.synced : "") : "", rows: () => [
            { key: "greeter:sync", title: "Sync now", flat: "Login screen: sync now", icon: "reload", sub: "theme, wallpaper, fonts -> /var/lib/nox-greeter", run: () => root.report("Login screen", ["greeter", "sync"]) },
            { key: "greeter:status", title: "Status", flat: "Login screen: status", icon: "gauge", sub: "nox greeter status", run: () => root.report("Login screen", ["greeter", "status"]) },
            { key: "greeter:test", title: "Preview", flat: "Login screen: preview", icon: "eye", sub: "full-screen test against a fake greetd; Esc clears", run: () => root.nox(["greeter", "test"]) },
            { key: "greeter:install", title: "Install (needs sudo)", flat: "Login screen: install (sudo)", icon: "shield", sub: "copies: nox greeter install", actLabel: "Copy", run: () => root.copyCommand("nox greeter install") },
            { key: "greeter:on", title: root.mark("Use as login screen (needs sudo)", gs?.on === true), flat: "Login screen: on (sudo)", icon: "shield", sub: "copies: nox greeter on", actLabel: "Copy", run: () => root.copyCommand("nox greeter on") },
            { key: "greeter:off", title: root.mark("Back to tuigreet (needs sudo)", gs?.on === false), flat: "Login screen: off (sudo)", icon: "shield", sub: "copies: nox greeter off", actLabel: "Copy", run: () => root.copyCommand("nox greeter off") }
        ] });

        // screen power (nox dpms): off blanks every screen until input
        out.push({ id: "dpms", title: "Screen power", icon: "laptop", kw: "dpms screen display monitor off blank power nox dpms", sub: "nox dpms", rows: () => [
            { key: "dpms:off", title: "Turn screens off", icon: "moon", sub: "any key or the mouse wakes them", confirm: "Turn the screens off?", run: () => root.nox(["dpms", "off"]) },
            { key: "dpms:toggle", title: "Toggle screens", icon: "laptop", confirm: "Toggle screen power?", run: () => root.nox(["dpms", "toggle"]) },
            { key: "dpms:on", title: "Turn screens on", icon: "sun", run: () => root.nox(["dpms", "on"]) }
        ] });

        // shell (nox shell, nox status)
        out.push({ id: "shell", title: "Shell", icon: "logo", kw: "shell quickshell qs bar nox shell status", sub: "qs -c nox", rows: () => [
            { key: "shell:restart", title: "Restart shell", icon: "reload", bind: ["Restart shell"], run: () => root.nox(["shell", "restart"]) },
            { key: "shell:status", title: "Shell status", icon: "gauge", sub: "nox shell status", run: () => root.report("Shell", ["shell", "status"]) },
            { key: "shell:log", title: "Shell log", icon: "doc", sub: "nox shell log -f (terminal)", run: () => root.inTerminal(["shell", "log", "-f"]) },
            { key: "shell:desktop", title: "Desktop status", icon: "check", sub: "nox status: Hyprland, shell, theme, idle", run: () => root.report("Nox status", ["status"]) },
            { key: "shell:stop", title: "Stop shell", icon: "x", sub: "bar, dock and launcher go away until nox shell start", confirm: "Stop the shell?", run: () => root.nox(["shell", "stop"]) }
        ] });

        // Hyprland config (nox hypr); `off` refuses by design, so it is not offered
        out.push({ id: "hypr", title: "Hyprland config", icon: "settings", kw: "hyprland hypr lua config verify nox hypr", sub: "nox hypr", rows: () => [
            { key: "hypr:status", title: "Config status", icon: "gauge", sub: "nox hypr status", run: () => root.report("Hyprland config", ["hypr", "status"]) },
            { key: "hypr:check", title: "Verify config", icon: "check", sub: "Hyprland --verify-config, no side effects", run: () => root.report("Hyprland config", ["hypr", "check"]) },
            { key: "hypr:on", title: "Activate the nox Lua config now", icon: "reload", sub: "nox hypr on --live: full reset of the running session", confirm: "Full-reset Hyprland's config now?", run: () => root.report("Hyprland config", ["hypr", "on", "--live"]) }
        ] });
        return out;
    }

    // every top-level row: { key, title, sub, icon, cat, kw, bind?: [labels], keys?, confirm?, actLabel?, stay?, run }
    function topRows(withLevelRows) {
        const out = [];

        // toggles
        const tog = (key, t, on, sub, icon, kw, flip, bind) => out.push({
            key: "toggle:" + key, title: t, sub: sub, icon, cat: "Toggle", kw: "toggle switch " + kw,
            actLabel: on ? "Turn Off" : "Turn On", bind, run: flip
        });
        if (Network.wifiDevice)
            tog("wifi", "Wi-Fi", Network.wifiEnabled, Network.wifiEnabled ? "On" + (Network.ssid ? " · " + Network.ssid : "") : "Off",
                Network.wifiEnabled ? "wifi" : "wifiOff", "wifi wireless network wlan internet",
                () => { const v = !Network.wifiEnabled; Network.setWifi(v); root.hud("Wi-Fi " + root.onOff(v).toLowerCase(), v ? "wifi" : "wifiOff"); });
        if (Bt.adapter)
            tog("bluetooth", "Bluetooth", Bt.enabled, Bt.enabled ? "On" + (Bt.connected.length ? " · " + Bt.connected.map(d => Bt.nameOf(d)).join(", ") : "") : "Off",
                Bt.enabled ? "bt" : "btOff", "bluetooth bt headphones",
                () => { const v = !Bt.enabled; Bt.setEnabled(v); root.hud("Bluetooth " + root.onOff(v).toLowerCase(), v ? "bt" : "btOff"); });
        tog("nightLight", "Night Light", NightLight.on, root.onOff(NightLight.on), "sunset", "night warm hyprsunset blue light",
            () => { const v = !NightLight.on; NightLight.toggle(); root.hud("Night Light " + root.onOff(v).toLowerCase(), "sunset"); });
        if (Config.moduleEnabled("notifications"))
            tog("dnd", "Do Not Disturb", Notifs.dnd, root.onOff(Notifs.dnd), "moonF", "dnd focus notifications silence quiet",
                () => { const v = !Notifs.dnd; Notifs.toggleDnd(); root.hud("Do Not Disturb " + root.onOff(v).toLowerCase(), "moonF"); }, ["Toggle Do Not Disturb"]);
        tog("caffeine", "Caffeine", Panels.caffeine, Panels.caffeine ? "On · the screen stays awake" : "Off · idle dims, locks and sleeps",
            "coffee", "caffeine awake idle inhibit keep screen on",
            () => { const v = !Panels.caffeine; Panels.caffeine = v; root.hud("Caffeine " + root.onOff(v).toLowerCase(), "coffee"); });
        if (ChargeLimit.supported)   // ChargeLimit shows its own HUD
            tog("chargeLimit", "Battery protection", ChargeLimit.on, (ChargeLimit.on ? "On · " : "Off · ") + ChargeLimit.label,
                "leaf", "battery charge limit 80 100 full protect health travel", () => ChargeLimit.toggle());
        if (Config.moduleEnabled("dock")) {
            const ah = !!(Config.opt.dock?.autohide);
            tog("dockAutohide", "Dock auto-hide", ah, ah ? "On · shows at the bottom edge" : "Off · the dock keeps its space",
                "grid", "dock autohide auto hide reveal",
                () => { Config.setDockOption("autohide", !ah); root.hud("Dock auto-hide " + root.onOff(!ah).toLowerCase(), "grid"); });
        }
        const dw = DesktopWidgets;
        tog("widgets", "Desktop widgets", dw.enabled, root.onOff(dw.enabled) + " · side " + dw.side, "desktop", "widgets clock desktop",
            () => { const v = !dw.enabled; dw.setEnabled(v); root.hud("Desktop widgets " + root.onOff(v).toLowerCase(), "desktop"); });
        const ss = Wallpaper.slideshow;
        if (ss.paths.length)
            tog("slideshow", "Wallpaper slideshow", ss.on, (ss.on ? "On · " : "Off · ") + ss.paths.length + " wallpapers, every " + ss.minutes + " min",
                "play", "wallpaper slideshow cycle rotate",
                () => { const v = !ss.on; if (v) ss.start(); else ss.stop(); root.hud("Slideshow " + root.onOff(v).toLowerCase(), "play"); });
        tog("record", "Screen recording", Recorder.recording, Recorder.recording ? "Recording · Enter stops it" : "Off · pick a region",
            "record", "record video screencast wf-recorder", () => Recorder.toggle());

        // levels: a row that opens each; typing also searches their rows
        const lv = levels();
        for (const l of lv)
            out.push({ key: "level:" + l.id, title: l.title + "…", sub: l.sub, icon: l.icon, cat: "Settings", kw: l.kw, actLabel: "Open",
                       stay: true, run: () => { root.level = l.id; } });
        if (withLevelRows)
            for (const l of lv)
                for (const r of l.rows("")) {
                    if (r.typed || r.stay || r.levelOnly) continue;
                    out.push(Object.assign({}, r, { title: r.flat ?? (l.title + ": " + r.title), cat: l.title, kw: l.kw + " " + (r.kw ?? "") + " " + (r.sub ?? "") }));
                }

        // services/Actions; one without a definition above takes its launcher.provider.commands label
        // ("Desktop Widgets: On / Off"), else a title-cased name
        const items = Config.launcherProvider("commands").items ?? [];
        const byAction = {};
        for (const it of items) if (it.action && it.label && !byAction[it.action]) byAction[it.action] = it;
        for (const a of Object.keys(Actions.table)) {
            if (root.skipActions.includes(a)) continue;
            const c = byAction[a];
            const d = root.actionDefs[a]
                ?? (c ? { t: c.label, icon: c.icon || "dots", cat: "Shell", kw: (c.keywords ?? []).join(" "), confirm: c.confirm }
                      : { t: root.title(a.replace(/([a-z])([A-Z])/g, "$1 $2")).replace(/ (\w)/g, (m, x) => " " + x.toLowerCase()), icon: "dots", cat: "Shell" });
            out.push({ key: "action:" + a, title: d.t, sub: "", icon: d.icon, cat: d.cat, kw: (d.kw ?? "") + " " + a, bind: d.bind, confirm: d.confirm ?? "",
                       run: () => Actions.run(a) });
        }

        // capture (nox shot, nox record)
        const cli = (key, t, icon, args, kw, bind, sub) => out.push({ key: "nox:" + key, title: t, sub: sub ?? "", icon, cat: "Capture", kw: kw + " nox " + args.join(" "), bind, run: () => root.nox(args) });
        cli("shotRegion", "Screenshot region", "shotRegion", ["shot", "region"], "screenshot capture region annotate satty", ["Screenshot region"]);
        cli("shotCopy", "Screenshot region to clipboard only", "shotRegion", ["shot", "copy"], "screenshot capture copy");
        cli("shotWindow", "Screenshot window", "shotWin", ["shot", "window"], "screenshot capture window", ["Screenshot window"]);
        cli("shotScreen", "Screenshot monitor", "shotScreen", ["shot", "screen"], "screenshot capture monitor display", ["Screenshot monitor"]);
        cli("shotAll", "Screenshot all monitors", "shotScreen", ["shot", "all"], "screenshot capture all screens monitors", ["Screenshot all monitors"]);
        cli("ocr", "OCR region to clipboard", "doc", ["shot", "ocr"], "ocr text recognize tesseract copy", ["OCR region to clipboard"]);
        cli("record", "Record region", "recRegion", ["record"], "record video screencast", ["Record region (toggle)"], "Run again to stop");
        cli("recordFull", "Record screen", "record", ["record", "--fullscreen"], "record video screencast fullscreen monitor", ["Record screen (toggle)"], "Run again to stop");
        cli("recordSound", "Record screen with audio", "record", ["record", "--fullscreen", "--sound"], "record video screencast sound desktop audio", ["Record screen with audio (toggle)"], "Run again to stop");
        out.push({ key: "nox:shotPin", title: "Pin last screenshot", sub: "on screen, always on top; Esc closes", icon: "image", cat: "Capture", kw: "pin screenshot float nox shot pin",
                   run: () => Quickshell.execDetached(["sh", "-c", root.noxFn + "d=$(xdg-user-dir PICTURES 2>/dev/null || echo \"$HOME/Pictures\")/Screenshots; f=$(ls -t \"$d\"/*.png 2>/dev/null | head -n1); [ -n \"$f\" ] && n shot pin \"$f\" || notify-send -a Nox 'No screenshot to pin' \"$d is empty\"", "sh"]) });

        // launcher.provider.commands items that run a command (nox ones are covered above)
        for (const it of items) {
            if (!it.label || !Array.isArray(it.command) || !it.command.length || it.command[0] === "nox") continue;
            const argv = it.command;
            out.push({ key: "cmd:" + it.label, title: it.label, sub: "", icon: it.icon || "terminal", cat: "Command",
                       kw: (it.keywords ?? []).join(" ") + " " + argv.join(" "), confirm: it.confirm ?? "", run: () => Quickshell.execDetached(argv) });
        }
        return out;
    }

    // keycaps for rows that name a bind; returns the claimed labels
    function attachKeys(rows) {
        const byLabel = {};
        for (const e of Binds.entries) if (!e.mouse && e.keys.length && !e.digit && !byLabel[e.label]) byLabel[e.label] = e;
        const claimed = new Set();
        for (const r of rows)
            for (const l of (r.bind ?? [])) {
                claimed.add(l);
                if (!r.keys && byLabel[l]) r.keys = byLabel[l].keys;
            }
        return claimed;
    }
    // binds: one row per label (+ digit); aliases ("Super ⇧ T" for OCR) go in the subtitle
    function bindRows(claimed) {
        const out = [], seen = {};
        for (const e of Binds.entries) {
            if (e.mouse || !e.keys.length || e.key === "" || claimed.has(e.label) || /^command palette/i.test(e.label)) continue;
            const t = e.label + (e.digit ? " " + (e.digit === "0" ? "10" : e.digit) : "");
            if (seen[t]) { if (!seen[t].sub) seen[t].sub = "or " + e.combo; continue; }
            const r = { key: "bind:" + t, title: t, sub: "", icon: "keyboard", cat: e.group, kw: "shortcut keybind",
                        keys: e.keys, confirm: root.dangerous.test(e.label) ? e.label + "?" : "", run: () => Binds.run(e) };
            seen[t] = r;
            out.push(r);
        }
        return out;
    }

    // fuzzy on the title, then keywords / category / keycaps / subtitle; every typed word found
    // anywhere also counts ("ctrl super t" finds the bind whatever the modifier order)
    function match(q, r) {
        const kc = (r.keys ?? []).join(" ").replace(/⇧/g, "shift");
        const m = Fuzzy.best(q, [[r.title, 1], [(r.kw ?? "") + " " + (r.cat ?? "") + " " + kc, 0.7], [r.sub ?? "", 0.5]]);
        // every typed word is one of the keycaps: the shortcut itself was typed
        const caps = (r.keys ?? []).map(k => k.toLowerCase().replace("⇧", "shift"));
        const words = q.toLowerCase().split(/\s+/);
        if (caps.length && words.length > 1 && words.every(w => caps.includes(w))) return { score: words.length === caps.length ? 140 : 120, indices: [] };
        if (m) return m;
        const hay = (r.title + " " + (r.kw ?? "") + " " + (r.cat ?? "") + " " + kc + " " + (r.sub ?? "")).toLowerCase();
        return q.toLowerCase().split(/\s+/).every(w => hay.includes(w)) ? { score: 12, indices: [] } : null;
    }

    function result(r, m, score) {
        const key = r.key, run = r.run, stay = !!r.stay;
        return {
            title: r.title, sub: r.sub ?? "", icon: r.icon || "dots", type: r.cat ?? "", keys: r.keys ?? [], highlight: m.indices,
            actLabel: r.actLabel ?? "Run", confirm: r.confirm ?? "", key, stay, score,
            run: () => { if (!stay || key.startsWith("level:")) Frecency.record("palette", key); run(); }
        };
    }

    function query(text, prefixed) {
        if (!prefixed) return [];
        poll();
        const q = text.trim();
        const out = [];
        // inside a level: its rows (typed rows always), then Back
        if (levelDef) {
            const rows = levelDef.rows(text);
            attachKeys(rows);
            rows.forEach((r, i) => {
                const m = r.typed || !q ? { score: 0, indices: [] } : match(q, r);
                if (!m) return;
                out.push(result(Object.assign({ cat: "" }, r), m, r.typed ? 1e6 : q ? m.score + Frecency.score("palette", r.key) * 10 : -i));
            });
            out.push({ title: "Back", sub: "Command palette", icon: "chevL", key: "palette:back", actLabel: "Back", score: -1e9, stay: true, run: () => root.back() });
            return out;
        }
        const rows = topRows(q !== "");
        const claimed = attachKeys(rows);
        const all = rows.concat(bindRows(claimed));
        const recent = Frecency.top("palette", options.recent ?? 8);
        for (const r of all) {
            const m = q ? match(q, r) : { score: 0, indices: [] };
            if (!m) continue;
            const ri = recent.indexOf(r.key);
            // empty query: recent rows on top (most recent first), then the declared order (ties keep it)
            out.push(result(r, m, q ? m.score + Frecency.score("palette", r.key) * 10 : (ri >= 0 ? 100 - ri : 0)));
        }
        return out;
    }
}

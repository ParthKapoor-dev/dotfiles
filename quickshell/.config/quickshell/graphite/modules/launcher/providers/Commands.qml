import QtQuick
import Quickshell
import qs.core
import qs.services

// System actions from shell.json launcher.provider.commands.items:
//   { label, icon, keywords?, confirm? ("Restart now?" = Enter twice), command: [argv] | action: "<builtin>" }
// Builtin actions: dnd, controlCenter, notifications, dock, launcher.
// Typing "/" lists all of them.
Item {
    id: root
    property string providerId: "commands"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Commands"
    property string defaultPrefix: "/"
    property bool defaultPrefixOnly: false

    readonly property var builtins: ({
        "dnd": () => Notifs.toggleDnd(),
        "controlCenter": () => Panels.toggle("controlCenter"),
        "notifications": () => Panels.toggle("notifications"),
        "dock": () => { Panels.dockVisible = !Panels.dockVisible; },
        "launcher": () => { Panels.launcherOpen = !Panels.launcherOpen; }
    })
    // builtins that only make sense while their module is enabled
    function available(it) {
        if (it.action === "dnd" || it.action === "notifications") return Config.moduleEnabled("notifications");
        if (it.action === "controlCenter") return Config.moduleEnabled("controlCenter");
        if (it.action === "dock") return Config.moduleEnabled("dock");
        return true;
    }

    function query(text, prefixed) {
        if (!text && !prefixed) return [];
        const out = [];
        for (const it of (options.items ?? [])) {
            if (!it.label || !available(it)) continue;
            const m = text ? Fuzzy.best(text, [[it.label, 1], [(it.keywords ?? []).join(" "), 0.8]]) : { score: 1, indices: [] };
            if (!m) continue;
            const key = it.label;
            out.push({
                title: it.label,
                sub: it.action === "dnd" ? (Notifs.dnd ? "Currently on" : "Currently off") : "",
                icon: it.icon || "terminal",
                highlight: m.indices,
                type: "Command",
                actLabel: "Run",
                confirm: it.confirm || "",
                score: m.score + Frecency.score("commands", key) * 10,
                run: () => {
                    Frecency.record("commands", key);
                    if (it.action) { const f = root.builtins[it.action]; if (f) f(); else console.warn("graphite: unknown launcher action", it.action); }
                    else if (it.command) Quickshell.execDetached(it.command);
                }
            });
        }
        return out;
    }
}

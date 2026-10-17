import QtQuick
import Quickshell
import qs.core
import qs.services

// Desktop applications: fuzzy match on name (then generic name, keywords, comment), boosted by
// frecency (launch history in ~/.local/state/graphite/launcher.json). Empty query = recent apps.
// options: limit, showRecent, recentLimit, frecencyWeight, terminal (argv prefix for Terminal=true apps)
Item {
    id: root
    property string providerId: "apps"
    readonly property var options: Config.launcherProvider(providerId)
    property bool lastEmpty: false
    property string name: lastEmpty ? "Recent" : "Applications"
    property string defaultPrefix: ""
    property bool defaultPrefixOnly: false

    function item(e, m) {
        return {
            title: e.name,
            sub: e.genericName || e.comment || "",
            image: Quickshell.iconPath(e.icon, "application-x-executable"),
            highlight: m ? m.indices : [],
            type: "Application",
            score: (m ? m.score : 0) + Frecency.score("apps", e.id) * 100 * (options.frecencyWeight ?? 0.35),
            run: () => {
                Frecency.record("apps", e.id);
                if (e.runInTerminal) Quickshell.execDetached((options.terminal ?? ["ghostty", "-e"]).concat(e.command));
                else e.execute();
            }
        };
    }

    function query(text, prefixed) {
        lastEmpty = text === "";
        if (text === "") {
            if (options.showRecent === false) return [];
            return Frecency.top("apps", options.recentLimit ?? 6)
                .map(id => DesktopEntries.byId(id))
                .filter(e => e && !e.noDisplay)
                .map(e => item(e, null));
        }
        const out = [];
        for (const e of DesktopEntries.applications.values) {
            if (e.noDisplay) continue;
            const m = Fuzzy.best(text, [[e.name, 1], [e.genericName, 0.7], [(e.keywords ?? []).join(" "), 0.6], [e.comment, 0.35], [e.id, 0.5]]);
            if (m) out.push(item(e, m));
        }
        return out;
    }
}

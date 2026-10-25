import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// App Manager (prefix "+"): installed apps from pacman, the AUR, Flatpak and AppImages in one list,
// plus search-to-install over the repos, the AUR and Flathub. The data and every change go through
// `nox apps` (nox/.local/lib/nox/apps): reads return JSON, changes open a floating terminal
// (`nox apps term …`) where pacman / yay / flatpak show what they will do and ask first.
//   "+"            Updates (N) row -> the update list, Clean up, AppImages in ~/Downloads, installed apps
//   "+ text"       installed matches first, then installable results (searched after typing stops)
// Installed row: Enter = open (no app entry: its web page), Shift+Enter = web page / folder,
// Ctrl+Enter = update it (when one is pending), Shift+Delete = uninstall. Search row: Enter = install.
// The installed list is re-read on every launcher open; updates are cached 30 min by `nox apps`.
// options: debounce (ms, default 350), minChars (search, default 2), searchLimit (per source, default 8)
Item {
    id: root
    property string providerId: "packages"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: level === "updates" ? "Updates" : "App Manager"
    property string defaultPrefix: "+"
    property bool defaultPrefixOnly: true
    readonly property bool nested: level !== ""
    signal resultsChanged()

    property string level: ""          // "" | "updates"
    property var installed: []
    property var downloads: []
    property var have: ({})
    property var updates: []
    property bool checking: false
    property bool stale: true
    property var found: []
    property string foundFor: ""
    property string wanted: ""
    property bool searching: false

    readonly property var labels: ({ repo: "pacman", aur: "AUR", flatpak: "Flatpak", appimage: "AppImage" })
    readonly property var upd: {
        const m = {};
        for (const u of updates) m[u.source + ":" + u.id] = u;
        return m;
    }
    readonly property var owned: {
        const m = {};
        for (const r of installed) m[r.source + ":" + r.id] = true;
        return m;
    }

    Connections {
        target: Panels
        function onLauncherOpenChanged() {
            root.level = "";
            root.stale = true;
            if (Panels.launcherOpen) root.resultsChanged();
        }
    }

    function back() { level = ""; }

    function apps(args) { return ["nox", "apps"].concat(args); }
    function term(args) { Panels.launcherOpen = false; Quickshell.execDetached(apps(["term"].concat(args))); }

    function iconOf(r) {
        if (r.iconUrl) return r.iconUrl;
        if (r.icon && r.icon.startsWith("/")) return "file://" + r.icon;
        return r.icon ? Quickshell.iconPath(r.icon, true) : "";
    }
    function size(r) {
        if (r.sizeText) return r.sizeText;
        let n = r.size ?? 0;
        if (!n) return "";
        for (const u of ["B", "KiB", "MiB", "GiB"]) {
            if (n < 1024 || u === "GiB") return u === "B" ? n + " B" : n.toFixed(1) + " " + u;
            n /= 1024;
        }
        return "";
    }
    function details(r, u, isInstalled) {
        const rows = [
            ["Source", labels[r.source] + (r.repo ? " (" + r.repo + ")" : r.origin ? " (" + r.origin + ")" : "")],
            ["Package", r.source === "appimage" ? r.id.replace(Quickshell.env("HOME"), "~") : r.id],
            ["Version", (r.version || "—") + (u ? "  →  " + (u.new || "newer") : "")],
            ["Size", size(r)],
            ["Installed", isInstalled ? (r.date || "yes") : "no"],
            ["Votes", r.votes !== undefined ? r.votes + (r.outOfDate ? "  (flagged out of date)" : "") : ""],
            ["Installs", r.installs ? r.installs + " last month" : ""]
        ].filter(x => x[1]);
        const desc = r.pkgdesc && r.pkgdesc !== r.desc ? r.desc + "\n" + r.pkgdesc : r.desc;
        const keys = isInstalled
            ? ["↵ " + (r.desktop || r.source === "appimage" ? "open" : "web page"),
               r.source === "appimage" ? "⇧↵ show in folder" : "⇧↵ web page",
               u ? "⌃↵ update" : "", "⇧⌦ uninstall"].filter(k => k)
            : ["↵ install", "⇧↵ web page"];
        return rows.map(x => (x[0] + ":").padEnd(11) + x[1]).join("\n") + (desc ? "\n\n" + desc : "") + "\n\n" + keys.join("   ");
    }

    // ---- rows ----
    function installedRow(r, m, score) {
        const u = upd[r.source + ":" + r.id];
        const openable = !!r.desktop || r.source === "appimage";
        const row = {
            title: r.name,
            sub: [r.version + (u ? " → " + (u.new || "update") : ""), r.desc].filter(x => x).join(" · "),
            image: iconOf(r),
            icon: "tray",
            highlight: m?.indices ?? [],
            type: u ? labels[r.source] + " · update" : labels[r.source],
            key: "pkg:" + r.source + ":" + r.id,
            actLabel: openable ? "Open" : "Web Page",
            score,
            previewText: details(r, u, true),
            previewMono: true,
            previewTitle: r.name,
            alt: () => r.source === "appimage"
                ? Quickshell.execDetached(["xdg-open", r.id.slice(0, r.id.lastIndexOf("/"))])
                : Quickshell.execDetached(apps(["page", r.source, r.id])),
            altLabel: r.source === "appimage" ? "Show in Folder" : "Web Page",
            remove: () => root.term(["remove", r.source, r.id]),
            run: () => openable ? Quickshell.execDetached(apps(["open", r.source, r.id, r.desktop || ""]))
                                : Quickshell.execDetached(apps(["page", r.source, r.id]))
        };
        if (u) { row.mark = () => root.term(["update", r.source, r.id]); row.markLabel = "Update"; }
        return row;
    }
    function availableRow(r, m, score) {
        return {
            title: r.name,
            sub: [r.version, r.desc].filter(x => x).join(" · "),
            image: iconOf(r),
            icon: "download",
            highlight: m?.indices ?? [],
            type: labels[r.source],
            key: "pkg:get:" + r.source + ":" + r.id,
            actLabel: "Install",
            score,
            previewText: details(r, null, false),
            previewMono: true,
            previewTitle: r.name,
            alt: () => Quickshell.execDetached(apps(["page", r.source, r.id])),
            altLabel: "Web Page",
            run: () => root.term(r.source === "flatpak" && r.origin ? ["install", r.source, r.id, r.origin] : ["install", r.source, r.id])
        };
    }
    function actionRows() {
        const n = updates.length;
        const by = {};
        for (const u of updates) by[u.source] = (by[u.source] ?? 0) + 1;
        const parts = Object.keys(by).map(s => by[s] + " " + labels[s]);
        return [{
            title: n ? n + " update" + (n === 1 ? "" : "s") + " available" : "Updates",
            sub: checking && !n ? "Checking…" : n ? parts.join(" · ") : "Everything is up to date",
            icon: "reload",
            key: "pkg:updates",
            type: "Updates",
            badge: n ? String(n) : "",
            actLabel: n ? "Show" : "Check Again",
            stay: true,
            words: "updates upgrade system update all",
            run: () => { if (n) root.level = "updates"; else root.checkUpdates(true); }
        }, {
            title: "Clean up",
            sub: "Orphaned packages, package cache, AUR build files, unused Flatpak runtimes",
            icon: "sparkle",
            key: "pkg:clean",
            type: "Maintenance",
            actLabel: "Clean",
            words: "clean up orphans cache autoremove",
            run: () => root.term(["clean"])
        }];
    }
    function downloadRows() {
        return downloads.map(d => ({
            title: "Install " + d.name,
            sub: "AppImage in ~/Downloads · " + size(d) + " · moves it to ~/Applications and adds it to the launcher",
            icon: "download",
            key: "pkg:dl:" + d.id,
            type: "AppImage",
            actLabel: "Install",
            words: d.name + " appimage install",
            remove: () => root.term(["remove", "appimage", d.id]),
            run: () => root.term(["install", "appimage", d.id])
        }));
    }
    function updateRows(q) {
        const out = [{
            title: "Update everything",
            sub: (have.yay ? "yay -Syu" : "pacman -Syu") + (have.flatpak ? ", then flatpak update" : ""),
            icon: "reload",
            key: "pkg:upgrade",
            actLabel: "Update",
            score: 1e9,
            run: () => root.term(["upgrade"])
        }];
        const names = {};
        for (const r of installed) names[r.source + ":" + r.id] = r;
        // repo packages only upgrade together (no partial upgrades): one row for all of them, plus
        // the ones that are apps so they can be found by name
        const sys = updates.filter(u => u.source === "repo");
        if (sys.length) {
            const m = q ? Fuzzy.best(q, [["System packages", 1], [sys.map(u => u.id).join(" "), 0.5]]) : { score: 0, indices: [] };
            if (m) out.push({
                title: "System packages (" + sys.length + ")",
                sub: sys.slice(0, 6).map(u => u.id).join(", ") + (sys.length > 6 ? ", …" : "") + " · pacman -Syu",
                icon: "tray",
                highlight: m.indices,
                type: "pacman",
                key: "pkg:upd:system",
                actLabel: "Update",
                score: m.score + 500,
                previewText: sys.map(u => u.id.padEnd(28) + " " + u.version + "  →  " + u.new).join("\n"),
                previewMono: true,
                previewTitle: sys.length + " pacman updates",
                run: () => root.term(["update", "repo", sys[0].id])
            });
        }
        for (const u of updates) {
            const r = names[u.source + ":" + u.id];
            if (u.source === "repo" && !r?.desktop) continue;
            const title = r?.name || u.name || u.id;
            const m = q ? Fuzzy.best(q, [[title, 1], [u.id, 0.8]]) : { score: 0, indices: [] };
            if (!m) continue;
            out.push({
                title,
                sub: (u.version ? u.version + " → " : "→ ") + (u.new || "newer") + (r?.desc ? " · " + r.desc : ""),
                image: r ? iconOf(r) : "",
                icon: "tray",
                highlight: m.indices,
                type: labels[u.source],
                key: "pkg:upd:" + u.source + ":" + u.id,
                actLabel: u.source === "repo" ? "Update All" : "Update",
                // GUI apps first, then by source and name
                score: m.score + (r?.desktop ? 100 : 0) + (u.source === "repo" ? 0 : 50),
                run: () => root.term(["update", u.source, u.id])
            });
        }
        out.push({ title: "Back", sub: "App Manager", icon: "chevL", key: "pkg:back", actLabel: "Back", score: -1e9, stay: true, run: () => root.back() });
        return out;
    }

    function query(text, prefixed) {
        if (!prefixed) return [];
        if (stale) { stale = false; refresh(); }
        const q = text.trim();
        if (level === "updates") return updateRows(q);
        if (!q) {
            wanted = "";
            const out = actionRows().concat(downloadRows()).map((r, i) => Object.assign(r, { score: 1e6 - i }));
            installed.filter(r => r.desktop || r.source === "appimage" || r.source === "flatpak")
                .slice().sort((a, b) => a.name.localeCompare(b.name))
                .forEach((r, i) => out.push(installedRow(r, null, -i)));
            return out;
        }
        const out = [];
        for (const a of actionRows().concat(downloadRows())) {
            const m = Fuzzy.best(q, [[a.title, 1], [a.words, 0.7]]);
            if (m) out.push(Object.assign(a, { highlight: m.indices, score: m.score + 5 }));
        }
        for (const r of installed) {
            const m = Fuzzy.best(q, [[r.name, 1], [r.id, 0.8], [r.desc || "", 0.3]]);
            if (m) out.push(installedRow(r, m, m.score + (r.desktop ? 3 : 0) + 20));
        }
        if (q.length >= (options.minChars ?? 2)) {
            if (q !== wanted) { wanted = q; debounce.restart(); }
            const per = {}, cap = options.searchLimit ?? 8;
            const ql = q.toLowerCase();
            // results of an older query (still typing) only while they fuzzy-match the new text
            const current = foundFor === q;
            const older = !current && foundFor && q.toLowerCase().startsWith(foundFor.toLowerCase());
            for (const r of current || older ? found : []) {
                if (owned[r.source + ":" + r.id]) continue;
                const m = Fuzzy.best(q, [[r.name, 1], [r.id, 0.8], [r.desc || "", 0.3]]);
                if (!m && !current) continue;
                if ((per[r.source] = (per[r.source] ?? 0) + 1) > cap) continue;
                // the server matched it (often on the description) even when the fuzzy match didn't
                const exact = r.name.toLowerCase() === ql || r.id.toLowerCase() === ql ? 30 : 0;
                const pop = r.source === "flatpak" ? Math.log10(1 + (r.installs ?? 0)) : r.source === "aur" ? Math.log10(1 + (r.votes ?? 0)) : 2;
                out.push(availableRow(r, m, (m?.score ?? 0) * 0.5 + exact + pop - 10));
            }
            if (searching && foundFor !== q)
                out.push({ title: "Searching pacman, AUR and Flathub…", sub: q, icon: "search", key: "pkg:searching", actLabel: "", score: -1e8, stay: true, run: () => {} });
        }
        return out;
    }

    // ---- data ----
    function refresh() {
        if (!lister.running) lister.running = true;
        checkUpdates(false);
    }
    function checkUpdates(fresh) {
        if (updater.running) return;
        checking = true;
        updater.command = apps(["updates"].concat(fresh ? ["--fresh"] : []));
        updater.running = true;
    }
    Process {
        id: lister
        command: root.apps(["list"])
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    root.installed = d.installed ?? [];
                    root.downloads = d.downloads ?? [];
                    root.have = d.have ?? {};
                } catch (e) { console.warn("nox: app manager: bad list output", e); }
                root.resultsChanged();
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("nox: app manager:", text.trim()) }
    }
    Process {
        id: updater
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.updates = JSON.parse(text).updates ?? []; } catch (e) { console.warn("nox: app manager: bad updates output", e); }
                root.checking = false;
                root.resultsChanged();
            }
        }
        onExited: root.checking = false
    }

    // one search at a time; a newer query kills the older one and ignores its output
    property var proc: null
    Timer { id: debounce; interval: root.options.debounce ?? 350; onTriggered: root.start() }
    function start() {
        if (proc) { proc.running = false; proc = null; }
        const q = wanted;
        if (!q) return;
        searching = true;
        resultsChanged();
        proc = searchRun.createObject(root, { q, command: apps(["search", q]) });
        proc.running = true;
    }
    function finished(p, text) {
        if (p !== proc) return;
        proc = null;
        searching = false;
        try { found = JSON.parse(text).results ?? []; } catch (e) { found = []; }
        foundFor = p.q;
        resultsChanged();
    }
    Component {
        id: searchRun
        Process {
            id: run
            property string q
            stdout: StdioCollector { onStreamFinished: root.finished(run, text) }
            onExited: Qt.callLater(() => run.destroy())
        }
    }
}

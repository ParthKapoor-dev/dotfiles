import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// Emoji picker. Prefix "." (Super+. = `qs -c nox ipc call launcher emoji`). Data: assets/emoji.tsv
// (emoji, name, group, keywords; Unicode 17, no skin-tone variants), read on the first query.
// Empty query = recently used first, then the full list in Unicode order. Enter = paste into the
// window you were typing in (clipboard + Ctrl+V, Ctrl+Shift+V in terminals); Shift+Enter = copy only.
// Shown as a tile grid (the launcher's grid mode, result.section = the grid section): empty query =
// "Frequently Used" + every group in full, a search = one "Results" section with every match.
// options.grid: false = the old list rows (options.limit then caps both lists).
Item {
    id: root
    property string providerId: "emoji"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Emoji"
    property string defaultPrefix: "."
    property bool defaultPrefixOnly: true
    readonly property bool grid: options.grid ?? true    // launcher: tiles instead of rows, no row limit
    signal resultsChanged()                 // the launcher re-runs the search when this fires

    property var entries: []                // [{ e, name, title, group, hay }]
    property var byEmoji: ({})
    readonly property string dataPath: decodeURIComponent(Qt.resolvedUrl("../../../assets/emoji.tsv").toString().replace(/^file:\/\//, ""))

    function parse(text) {
        const list = [], map = {};
        for (const line of text.split("\n")) {
            if (!line || line.startsWith("#")) continue;
            const [e, name, group, kw] = line.split("\t");
            if (!e || !name) continue;
            const x = { e, name, title: name.charAt(0).toUpperCase() + name.slice(1), group: group ?? "", hay: (kw ?? "").toLowerCase() };
            list.push(x);
            map[e] = x;
        }
        entries = list;
        byEmoji = map;
        resultsChanged();
    }

    // name prefix > word prefix > name substring > keyword > group; every term must match
    function rank(x, terms) {
        const n = x.name.toLowerCase();
        let s = 0;
        for (const t of terms) {
            if (n.startsWith(t)) s += 4;
            else if (n.includes(" " + t)) s += 3;
            else if (n.includes(t)) s += 2;
            else if (x.hay.includes(t)) s += 1;
            else if (x.group.toLowerCase().includes(t)) s += 0.5;
            else return 0;
        }
        return s;
    }

    function result(x, score, q, section) {
        const at = q ? x.title.toLowerCase().indexOf(q) : -1;
        return {
            title: x.title,
            section,
            glyph: x.e,
            type: x.group.replace(/ &.*$/, ""),
            actLabel: "Paste",
            highlight: at < 0 ? [] : Array.from({ length: q.length }, (_, i) => at + i),
            score,
            // paste into the window you were typing in (clipboard + Ctrl+V, as pinned snippets do)
            run: () => { Frecency.record("emoji", x.e); Pins.paste({ text: x.e }); },
            alt: () => { Frecency.record("emoji", x.e); Pins.copy({ text: x.e }); }, altLabel: "Copy"
        };
    }

    function query(text, prefixed) {
        if (!prefixed) return [];
        if (!entries.length) { if (file.path === "") file.path = dataPath; return []; }
        const limit = grid ? entries.length * 2 : options.limit ?? 80;
        const q = text.trim().toLowerCase();
        const out = [];
        if (!q) {
            // grid: the frequently used ones stay in their groups too (each group is complete)
            const recent = Frecency.top("emoji", options.recent ?? 16).filter(e => byEmoji[e]);
            recent.forEach((e, i) => out.push(result(byEmoji[e], 1000 - i, "", "Frequently Used")));
            for (let i = 0; i < entries.length && out.length < limit; i++)
                if (grid || !recent.includes(entries[i].e)) out.push(result(entries[i], -i, "", entries[i].group));
            return out;
        }
        const terms = q.split(/\s+/);
        for (let i = 0; i < entries.length; i++) {
            const s = rank(entries[i], terms);
            if (s > 0) out.push(result(entries[i], s + (entries[i].name === q ? 5 : 0) + Frecency.score("emoji", entries[i].e) - i / 100000, q, "Results"));
        }
        return out.sort((a, b) => b.score - a.score).slice(0, limit);
    }

    FileView {
        id: file
        path: ""
        printErrors: true
        onLoaded: root.parse(text())
    }
}

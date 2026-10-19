import QtQuick
import Quickshell
import qs.core
import qs.services

// Pinned snippets (prefix "'"; services/Pins.qml, ~/.local/state/nox/pins.json): texts and links you
// reuse (profile URLs, addresses, replies). Found by name or text, also from the plain launcher.
//   Enter        paste into the window you were in (clipboard + Ctrl+V; Ctrl+Shift+V in terminals)
//   Shift+Enter  copy only            Ctrl+Enter  edit (rename / replace text / delete)
//   Alt+Up/Down  reorder              Shift+Delete  unpin
// Adding: type `'name = text` (or just `'text`) and pick "Pin …", or Ctrl+Enter on a clipboard
// entry (":"). Editing: the typed text is the new value; Esc goes back.
Item {
    id: root
    property string providerId: "pins"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Pinned"
    property string defaultPrefix: "'"
    property bool defaultPrefixOnly: false
    signal resultsChanged()

    property string editing: ""           // pin id while its edit level is open
    readonly property bool nested: editing !== ""
    function back() { editing = ""; }
    Connections { target: Pins; function onListChanged() { root.resultsChanged(); } }

    function isUrl(s) { return /^https?:\/\/\S+$/i.test(s.trim()); }
    function oneLine(s) { return s.replace(/\s+/g, " ").trim(); }
    function short(s) { return oneLine(s).replace(/^https?:\/\/(www\.)?/i, "").slice(0, 120); }

    function query(text, prefixed) {
        if (!prefixed) editing = "";          // the edit level only lives under the prefix
        if (nested) return editRows(text);
        const q = text.trim();
        if (!prefixed && q.length < 2) return [];
        const out = [];
        Pins.list.forEach((p, i) => {
            let m = { score: 0, indices: [] };
            if (q) {
                const byName = Fuzzy.best(q, [[p.name, 1]]);
                const byText = p.text.toLowerCase().includes(q.toLowerCase());
                if (!byName && !byText) return;
                m = byName ?? { score: 0.3, indices: [] };
            }
            out.push({
                title: p.name,
                sub: p.name === oneLine(p.text).slice(0, 80) ? "" : short(p.text),
                icon: isUrl(p.text) ? "link" : "push_pin",
                highlight: m.indices,
                previewText: p.text,
                previewTitle: "Pinned",
                type: "Pinned",
                key: "pin:" + p.id,
                badge: prefixed && !q ? String(i + 1) : "",
                score: prefixed ? -i : m.score - 0.2,
                actLabel: "Paste",
                run: () => Pins.paste(p),
                alt: () => Pins.copy(p), altLabel: "Copy",
                mark: () => { root.editing = p.id; return "reset"; }, markLabel: "Edit",
                remove: () => Pins.remove(p.id),
                move: prefixed ? d => Pins.move(p.id, d) : undefined
            });
        });
        if (prefixed && q) {
            // "name = text" pins text under that name; anything else pins the text as is
            const eq = q.indexOf(" = ");
            const nm = eq > 0 ? q.slice(0, eq).trim() : "";
            const body = eq > 0 ? q.slice(eq + 3).trim() : q;
            if (body && !Pins.list.some(p => p.text === body)) out.push({
                title: nm ? "Pin “" + nm + "”" : "Pin “" + short(body) + "”",
                sub: nm ? short(body) : "Tip: name = text pins it under a name",
                icon: "push_pin",
                type: "New",
                key: "pin:new",
                score: -1e6,
                actLabel: "Pin",
                stay: true,
                run: () => Pins.add(nm || body, body)
            });
        }
        if (prefixed && !q && Pins.list.length === 0) out.push({
            title: "Nothing pinned yet",
            sub: "Type name = text and press Enter, or Ctrl+Enter on a clipboard entry (:)",
            icon: "push_pin",
            key: "pin:empty",
            stay: true,
            run: () => {}
        });
        return out;
    }

    // edit level: the typed text is the new value
    function editRows(text) {
        const p = Pins.find(editing);
        if (!p) { editing = ""; return []; }
        const t = text.trim();
        const out = [{
            title: p.name,
            sub: t ? "Editing" : "Type a new name or text, then pick below · Esc goes back",
            icon: isUrl(p.text) ? "link" : "push_pin",
            previewText: p.text,
            previewTitle: "Pinned",
            type: "Pinned",
            key: "edit:info",
            actLabel: "Paste",
            run: () => Pins.paste(p)
        }];
        if (t) {
            out.push({ title: "Rename to “" + oneLine(t).slice(0, 80) + "”", icon: "edit", key: "edit:name", type: "Edit", actLabel: "Rename",
                       stay: true, run: () => { Pins.update(p.id, { name: oneLine(t).slice(0, 80) }); root.editing = ""; } });
            out.push({ title: "Replace text with “" + short(t) + "”", icon: "edit", key: "edit:text", type: "Edit", actLabel: "Replace",
                       previewText: t, previewTitle: "New text",
                       stay: true, run: () => { Pins.update(p.id, { text: t }); root.editing = ""; } });
        }
        out.push({ title: "Copy", icon: "clip", key: "edit:copy", type: "Edit", actLabel: "Copy", run: () => Pins.copy(p) });
        out.push({ title: "Unpin", icon: "trash", key: "edit:delete", type: "Edit", actLabel: "Unpin", confirm: "Unpin “" + p.name + "”?",
                   stay: true, run: () => { Pins.remove(p.id); root.editing = ""; } });
        return out;
    }
}

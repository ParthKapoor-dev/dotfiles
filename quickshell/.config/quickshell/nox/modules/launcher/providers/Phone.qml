import QtQuick
import Quickshell
import qs.core
import qs.services

// Phone link actions (services/Phone.qml, kdeconnect-rs): Send clipboard / Send file… / Ring /
// Pair. Matched by name ("send clip", "ring phone", …); typing the prefix lists all of them.
// Send/Ring only show while a paired phone is reachable; "Pair phone" always shows (it starts the
// daemon for this session if needed and shows the pairing steps as a notification).
Item {
    id: root
    property string providerId: "phone"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Phone"
    property string defaultPrefix: "^"
    property bool defaultPrefixOnly: false

    function items() {
        const d = Phone.device, on = Phone.connected;
        const b = Phone.deviceBattery;
        const sub = d ? d.name + (on ? (b ? " · " + b.level + "%" : "") : " · not reachable") : "";
        const out = [];
        if (on) {
            out.push({ title: "Send clipboard to phone", icon: "clip", kw: "phone kde connect share copy", sub: sub, run: () => Phone.sendClipboard() });
            out.push({ title: "Send file to phone…", icon: "send", kw: "phone kde connect share upload", sub: sub, run: () => Phone.pickAndSend() });
            out.push({ title: "Ring phone", icon: "bell", kw: "find my phone locate kde connect", sub: sub, run: () => Phone.ring() });
        }
        if (Phone.pairRequest)
            out.push({ title: "Accept pairing from " + Phone.pairRequest.name, icon: "key", kw: "phone pair kde connect", sub: "The phone is waiting", run: () => Phone.answerPair(true) });
        out.push({ title: "Pair phone", icon: "phone", kw: "kde connect link android connect",
            sub: Phone.available ? (d ? "Paired with " + d.name : "Shows the pairing steps") : "Starts the phone link daemon and shows the pairing steps",
            run: () => Phone.pair() });
        return out;
    }

    function query(text, prefixed) {
        if (!text && !prefixed) return [];
        const out = [];
        for (const it of items()) {
            const m = text ? Fuzzy.best(text, [[it.title, 1], [it.kw, 0.7]]) : { score: 1, indices: [] };
            if (!m) continue;
            out.push({
                title: it.title, sub: it.sub, icon: it.icon, highlight: m.indices, type: "Phone", actLabel: "Run",
                score: m.score + Frecency.score("phone", it.title) * 10,
                run: () => { Frecency.record("phone", it.title); it.run(); }
            });
        }
        return out;
    }
}

pragma Singleton
import QtQuick
import Quickshell
import qs.core

// Launch history for the launcher, in ~/.local/state/graphite/launcher.json:
//   { "<namespace>": { "<key>": { "n": launches, "t": last launch (ms epoch) } } }
// score() = log2(1 + n) weighted by recency; namespaces keep providers apart ("apps", "commands", ...).
Singleton {
    id: root

    function record(ns, key) {
        const d = Object.assign({}, store.data);
        const bucket = Object.assign({}, d[ns] ?? {});
        const e = bucket[key] ?? { n: 0, t: 0 };
        bucket[key] = { n: e.n + 1, t: Date.now() };
        d[ns] = bucket;
        store.data = d;
        store.save();
    }

    function score(ns, key) {
        const e = store.data[ns]?.[key];
        if (!e) return 0;
        const hours = (Date.now() - e.t) / 3600000;
        const w = hours < 4 ? 1 : hours < 24 ? 0.8 : hours < 168 ? 0.6 : hours < 720 ? 0.4 : 0.2;
        return Math.log2(1 + e.n) * w;
    }

    // keys of a namespace, best first
    function top(ns, n) {
        const bucket = store.data[ns] ?? {};
        return Object.keys(bucket).sort((a, b) => score(ns, b) - score(ns, a)).slice(0, n);
    }

    JsonState { id: store; path: Paths.state("launcher") }
}

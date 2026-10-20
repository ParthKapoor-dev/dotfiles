import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.services

// Start a coding agent from the launcher: "> fix the TaskList crash in void" -> Claude in the repo
// "void" with that task (services/Agents.launch -> `nox agents start`); it then shows up in the
// agents panel. Shares the command palette's ">" (joinPrefix: queried next to the palette, and
// only answers when the text names a repo, so palette searches stay clean):
//   "<task> in <repo>"   "<repo>: <task>"   or a word that is a repo name ("void fix the crash")
// Repos: git repos under agents.roots (default ["~/code"], agents.repoDepth 4), recent first
// (`nox agents repos`, cached a minute). Enter = agents.launch ("ghostty": a new Ghostty window,
// inside tmux so replies work; "orca": a new Orca worktree with the agent, Ghostty if Orca can't);
// Shift+Enter = the other one.
// options (launcher.provider.agent): prefix (">"), rows (repo matches shown, 3)
Item {
    id: root
    property string providerId: "agent"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Start agent"
    property string defaultPrefix: ">"
    property bool defaultPrefixOnly: true
    property bool joinPrefix: true            // queried alongside another provider with the same prefix
    signal resultsChanged()

    readonly property var aopts: Config.opt.agents ?? ({})
    readonly property string mode: aopts.launch === "orca" ? "orca" : "ghostty"
    readonly property string other: mode === "orca" ? "ghostty" : "orca"
    property var repos: []
    readonly property string home: Quickshell.env("HOME")

    Connections {
        target: Panels
        function onLauncherOpenChanged() { if (Panels.launcherOpen && !lister.running) lister.running = true; }
    }
    Process {
        id: lister
        command: [Agents.helper, "repos", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const r = JSON.parse(text); if (Array.isArray(r)) { root.repos = r; root.resultsChanged(); } } catch (e) {}
            }
        }
    }

    function modeLabel(m) { return m === "orca" ? "Orca worktree" : (aopts.tmux === false ? "Ghostty" : "Ghostty · tmux"); }
    function tilde(p) { return p.startsWith(home + "/") ? "~" + p.slice(home.length) : p; }

    // -> [{ repo, task }]
    function parse(text) {
        const t = text.trim();
        if (!t || !repos.length) return [];
        const low = t.toLowerCase();
        const byName = n => repos.filter(r => r.name.toLowerCase() === n);
        const byPrefix = n => n.length >= 2 ? repos.filter(r => r.name.toLowerCase().startsWith(n)) : [];
        let m = low.match(/^(.*\S)\s+in\s+([\w.@-]+)\s*$/);           // "<task> in <repo>"
        if (m) {
            const hits = byName(m[2]).length ? byName(m[2]) : byPrefix(m[2]);
            if (hits.length) return hits.map(r => ({ repo: r, task: t.slice(0, m[1].length).trim() }));
        }
        m = low.match(/^([\w.@-]+)\s*:\s*(\S.*)$/);                      // "<repo>: <task>"
        if (m) {
            const hits = byName(m[1]).length ? byName(m[1]) : byPrefix(m[1]);
            if (hits.length) return hits.map(r => ({ repo: r, task: t.slice(t.indexOf(":") + 1).trim() }));
        }
        const words = low.split(/\s+/);
        if (words.length < 3) return [];                                  // short = a palette search
        for (const w of words) {
            const hits = w.length >= 3 ? byName(w.replace(/[^\w.@-]/g, "")) : [];
            if (hits.length) return hits.map(r => ({ repo: r, task: t }));
        }
        return [];
    }

    function query(text, prefixed) {
        if (!prefixed) return [];
        const out = [];
        const rows = options.rows ?? 3;
        for (const h of parse(text).slice(0, rows)) {
            if (!h.task) continue;
            const r = h.repo;
            out.push({
                title: h.task,
                sub: tilde(r.path) + (r.branch ? " · " + r.branch : "") + " · " + modeLabel(mode),
                icon: "sparkle", type: "Agent", actLabel: "Start", score: 100 + (r.recent ?? 0) / 1e13,
                key: "agent:" + r.path,
                run: () => Agents.launch(r.path, h.task, root.mode),
                alt: () => Agents.launch(r.path, h.task, root.other),
                altLabel: root.other === "orca" ? "In Orca" : "In Ghostty"
            });
        }
        return out;
    }
}

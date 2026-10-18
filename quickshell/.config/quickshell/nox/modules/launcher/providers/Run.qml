import QtQuick
import Quickshell
import qs.core

// Run a shell command, only behind its prefix (default "$", the shell prompt; ">" is the command
// palette's since 2026-10-18): "$ make -C ~/src".
// options: shell (argv prefix, default ["sh","-c"]), terminal (argv prefix for "Run in Terminal"; [] hides it)
Item {
    id: root
    property string providerId: "run"
    readonly property var options: Config.launcherProvider(providerId)
    property string name: "Run"
    property string defaultPrefix: "$"
    property bool defaultPrefixOnly: true

    function query(text, prefixed) {
        const cmd = text.trim();
        if (!cmd) return [];
        const shell = options.shell ?? ["sh", "-c"];
        const term = options.terminal ?? ["ghostty", "-e"];
        const out = [{
            title: cmd, sub: "Run in background", icon: "terminal", type: "Shell", actLabel: "Run", score: 2,
            run: () => Quickshell.execDetached(shell.concat([cmd]))
        }];
        if (term.length) out.push({
            title: cmd, sub: "Run in terminal", icon: "open_in_new", type: "Terminal", actLabel: "Run", score: 1,
            run: () => Quickshell.execDetached(term.concat(shell, [cmd]))
        });
        return out;
    }
}

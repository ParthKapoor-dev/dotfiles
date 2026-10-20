pragma Singleton
import QtQuick
import Quickshell

// Where nox reads its config from.
// $NOX_CONFIG_DIR overrides; default is $XDG_CONFIG_HOME/nox (~/.config/nox).
// State files (launcher frecency, DND) live in stateDir.
Singleton {
    readonly property string configDir: {
        const override = Quickshell.env("NOX_CONFIG_DIR");
        if (override) return override;
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.config") + "/nox";
    }
    readonly property string tokens: configDir + "/tokens.json"
    readonly property string shell: configDir + "/shell.json"
    // machine-local overrides, deep-merged over shell.json (git-ignored; `nox detect` writes it)
    readonly property string shellLocal: configDir + "/shell.local.json"

    // Runtime state (not config): $NOX_STATE_DIR or $XDG_STATE_HOME/nox (~/.local/state/nox)
    readonly property string stateDir: {
        const override = Quickshell.env("NOX_STATE_DIR");
        if (override) return override;
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.local/state") + "/nox";
    }
    function state(name) { return stateDir + "/" + name + ".json"; }
    // merged tokens written by `nox theme switch`; always $XDG_STATE_HOME/nox (not NOX_STATE_DIR)
    readonly property string mergedTokens: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.local/state") + "/nox/tokens.json";
    }
}

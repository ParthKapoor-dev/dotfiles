pragma Singleton
import QtQuick
import Quickshell

// Where graphite reads its config from.
// $GRAPHITE_CONFIG_DIR overrides; default is $XDG_CONFIG_HOME/graphite (~/.config/graphite).
// State files (launcher frecency, DND) live in stateDir.
Singleton {
    readonly property string configDir: {
        const override = Quickshell.env("GRAPHITE_CONFIG_DIR");
        if (override) return override;
        const xdg = Quickshell.env("XDG_CONFIG_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.config") + "/graphite";
    }
    readonly property string tokens: configDir + "/tokens.json"
    readonly property string shell: configDir + "/shell.json"

    // Runtime state (not config): $GRAPHITE_STATE_DIR or $XDG_STATE_HOME/graphite (~/.local/state/graphite)
    readonly property string stateDir: {
        const override = Quickshell.env("GRAPHITE_STATE_DIR");
        if (override) return override;
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.local/state") + "/graphite";
    }
    function state(name) { return stateDir + "/" + name + ".json"; }
    // merged tokens written by `graphite-theme switch`; always $XDG_STATE_HOME/graphite (not GRAPHITE_STATE_DIR)
    readonly property string mergedTokens: {
        const xdg = Quickshell.env("XDG_STATE_HOME");
        return (xdg ? xdg : Quickshell.env("HOME") + "/.local/state") + "/graphite/tokens.json";
    }
}

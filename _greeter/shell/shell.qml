//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// nox greeter: the login screen on greetd (spec: lnx/design/mock, "Login screen").
// Runs as the `greeter` user inside a small Hyprland (/etc/nox-greeter/hyprland.lua), so it can
// not read ~parth: everything it shows comes from $NOX_GREETER_DATA (default /var/lib/nox-greeter),
// written by `nox greeter sync` (theme.json = rendered tokens, greeter.json = user + sessions,
// wallpaper.jpg = already cropped / blurred / dimmed for the look, fonts/, avatar.png).
// The password goes to greetd (Quickshell.Services.Greetd); greetd's PAM stack does the rest.
ShellRoot {
    id: root
    readonly property string dataDir: Quickshell.env("NOX_GREETER_DATA") || "/var/lib/nox-greeter"
    readonly property bool testMode: (Quickshell.env("NOX_GREETER_TEST") || "") !== ""

    property var tokens: ({})
    property var conf: ({})
    FileView {
        path: root.dataDir + "/theme.json"; blockLoading: true; printErrors: false
        onLoaded: { try { root.tokens = JSON.parse(text()); } catch (e) { console.warn("greeter: bad theme.json", e); } }
    }
    FileView {
        path: root.dataDir + "/greeter.json"; blockLoading: true; printErrors: false
        onLoaded: { try { root.conf = JSON.parse(text()); } catch (e) { console.warn("greeter: bad greeter.json", e); } }
    }

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: win
            required property var modelData
            screen: modelData
            // the login UI goes on the first screen; the others only show the wallpaper
            readonly property bool primary: modelData === Quickshell.screens[0]
            color: "black"
            WlrLayershell.namespace: "nox:greeter"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            Greeter {
                anchors.fill: parent
                tokens: root.tokens
                conf: root.conf
                dataDir: root.dataDir
                testMode: root.testMode
                showUi: win.primary
            }
        }
    }
}

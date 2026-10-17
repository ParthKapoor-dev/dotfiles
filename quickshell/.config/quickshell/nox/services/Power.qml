pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Power profiles (power-profiles-daemon via Quickshell's UPower PowerProfiles). `available` is
// true only when the daemon's D-Bus service is installed, so the "Performance" segments hide
// themselves on machines without it.
Singleton {
    id: root
    property bool available: false
    readonly property int profile: available ? PowerProfiles.profile : PowerProfile.Balanced
    readonly property bool hasPerformance: available && PowerProfiles.hasPerformanceProfile
    readonly property var modes: [
        { id: PowerProfile.PowerSaver, label: "Saver", glyph: "leaf" },
        { id: PowerProfile.Balanced, label: "Balanced", glyph: "gauge" },
        { id: PowerProfile.Performance, label: "Performance", glyph: "bolt" }
    ].filter(m => m.id !== PowerProfile.Performance || hasPerformance)
    function set(p) { if (available) PowerProfiles.profile = p; }

    FileView {
        path: "/usr/share/dbus-1/system-services/net.hadess.PowerProfiles.service"
        printErrors: false
        onLoaded: root.available = true
    }
    FileView {
        path: "/usr/share/dbus-1/system-services/org.freedesktop.UPower.PowerProfiles.service"
        printErrors: false
        onLoaded: root.available = true
    }
}

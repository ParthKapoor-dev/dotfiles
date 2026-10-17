import QtQuick
import qs.core
import qs.components
import qs.services

// Power mode (mock "Performance · powerprofilesctl"). Hidden without power-profiles-daemon.
Card {
    property bool shown: Power.available
    CardTitle { id: t; width: parent.width; text: "Performance"; detail: "power profile" }
    Segmented {
        anchors.top: t.bottom; anchors.topMargin: 8
        width: parent.width
        model: Power.modes
        current: Power.profile
        onPicked: id => Power.set(id)
    }
}

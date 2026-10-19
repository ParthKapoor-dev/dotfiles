pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Hubstaff (services/Hubstaff.qml), like the macOS menu bar item: a dot (accent while tracking)
// and today's time for the active project, H:MM. Hidden while the client isn't running.
// Popover: task over project, time today with seconds, Stop / Resume Timer, Open Hubstaff.
// widgets.hubstaff: { showTime: true, interval: 30000, cli: "~/Hubstaff/HubstaffCLI.bin.x86_64" }
BarButton {
    id: root
    property string widgetId: "hubstaff"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    hpad: 7
    spacing: 5
    visible: Hubstaff.available
    active: Panels.popup === popupId
    onClicked: { Hubstaff.refresh(); Panels.toggle(popupId); }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 6; height: 6
        radius: Theme.square ? 0 : 3
        color: Hubstaff.tracking ? Theme.accent : "transparent"
        border.width: Hubstaff.tracking ? 0 : 1
        border.color: Theme.label2
    }
    GText {
        visible: root.options.showTime ?? true
        anchors.verticalCenter: parent.verticalCenter
        text: Hubstaff.fmt(Hubstaff.today, false)
        color: Hubstaff.tracking ? Theme.label : Theme.label2
        font.features: ({ "tnum": 1 })
    }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        align: "itemRight"
        content: Column {
            PopHeader {
                width: parent.width
                title: "Hubstaff"
                value: Hubstaff.fmt(Hubstaff.today, true)
            }
            SectionLabel {
                topPadding: 0
                width: parent.width
                text: Hubstaff.tracking ? "Tracking" : "Not tracking" + (Hubstaff.stopReason ? " · " + Hubstaff.stopReason : "")
            }
            ListRow {
                visible: Hubstaff.project !== ""
                width: parent.width
                icon: "folder"
                on: Hubstaff.tracking
                // the task is what you work on: it leads, the project sits under it
                title: Hubstaff.task !== "" ? Hubstaff.task : Hubstaff.project
                subtitle: Hubstaff.task !== "" ? Hubstaff.project : "No task"
                onClicked: { Panels.close(); Hubstaff.openApp(); }
            }
            MenuSep { width: parent.width }
            MenuRow {
                width: parent.width
                icon: Hubstaff.tracking ? "pause" : "play"
                text: Hubstaff.tracking ? "Stop Timer" : "Resume Timer"
                enabled: !Hubstaff.busy && (Hubstaff.tracking || Hubstaff.project !== "")
                onTriggered: { Panels.close(); if (Hubstaff.tracking) Hubstaff.stop(); else Hubstaff.resume(); }
            }
            MenuRow { width: parent.width; icon: "open_in_new"; text: "Open Hubstaff"; onTriggered: { Panels.close(); Hubstaff.openApp(); } }
        }
    }
}

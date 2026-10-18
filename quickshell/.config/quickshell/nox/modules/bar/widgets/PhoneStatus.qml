pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Phone link (services/Phone.qml, kdeconnect-rs): phone glyph + battery % while the paired phone
// is connected, dimmed while it is away. Hidden entirely while the daemon isn't running.
// Popover: device + battery, Ring / Send clipboard / Send file… / Pair, a pending pair request.
// widgets.phone.showPercent: true (default) | false
BarButton {
    id: root
    property string widgetId: "phone"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    readonly property var bat: Phone.deviceBattery
    hpad: 7
    spacing: 4
    visible: Phone.available
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)

    Glyph {
        name: "phone"
        anchors.verticalCenter: parent.verticalCenter
        opacity: Phone.connected ? 1 : 0.45
        color: Phone.pairRequest ? Theme.accent : Theme.label
    }
    GText {
        visible: Phone.connected && root.bat !== null && (root.options.showPercent ?? true)
        anchors.verticalCenter: parent.verticalCenter
        text: (root.bat?.charging ? "+" : "") + (root.bat?.level ?? 0) + "%"
        color: (root.bat?.level ?? 100) <= 15 && !root.bat?.charging ? Theme.red : Theme.label
        font.features: ({ "tnum": 1 })
    }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        align: "itemRight"
        content: Column {
            PopHeader {
                width: parent.width
                title: Phone.device?.name ?? "Phone"
                value: root.bat ? root.bat.level + "%" : ""
            }
            SectionLabel {
                topPadding: 0
                text: !Phone.device ? "No paired phone"
                    : Phone.connected ? "Connected" + (root.bat?.charging ? " · Charging" : "")
                    : "Not reachable · open KDE Connect on the phone"
            }
            ListRow {
                visible: Phone.pairRequest !== null
                width: parent.width
                icon: "key"
                on: true
                title: "Accept pairing"
                subtitle: (Phone.pairRequest?.name ?? "") + " wants to pair"
                onClicked: Phone.answerPair(true)
            }
            MenuSep { width: parent.width }
            MenuRow { width: parent.width; icon: "bell"; text: "Ring Phone"; enabled: Phone.connected; onTriggered: { Panels.close(); Phone.ring(); } }
            MenuRow { width: parent.width; icon: "clip"; text: "Send Clipboard"; enabled: Phone.connected; onTriggered: { Panels.close(); Phone.sendClipboard(); } }
            MenuRow { width: parent.width; icon: "send"; text: "Send File…"; enabled: Phone.connected; onTriggered: { Panels.close(); Phone.pickAndSend(); } }
            MenuSep { width: parent.width }
            MenuRow { width: parent.width; icon: "phone"; text: Phone.device ? "Pair Another Phone…" : "Pair Phone…"; onTriggered: { Panels.close(); Phone.pair(); } }
        }
    }
}

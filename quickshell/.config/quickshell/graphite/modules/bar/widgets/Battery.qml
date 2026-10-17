pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.UPower
import qs.core
import qs.components

// Battery (UPower display device). Percentage shown on hover by default
// (widgets.battery.showPercent: "hover" | "always" | "never"); popup has details.
BarButton {
    id: root
    property string widgetId: "battery"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev?.isLaptopBattery ?? false
    readonly property real level: dev?.percentage ?? 0
    readonly property int pct: Math.round(level * 100)
    readonly property bool charging: dev?.state === UPowerDeviceState.Charging
    readonly property bool full: dev?.state === UPowerDeviceState.FullyCharged
    readonly property bool plugged: charging || full || dev?.state === UPowerDeviceState.PendingCharge || !UPower.onBattery
    readonly property bool low: pct <= (options.lowPercent ?? 20)
    readonly property string mode: options.showPercent ?? "hover"
    visible: present
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    spacing: 5

    function duration(s) {
        if (!s || s <= 0) return "";
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }

    GText {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.mode === "always" || (root.mode === "hover" && (root.hovered || root.active))
        text: root.pct + "%"
        font.features: ({ "tnum": 1 })
    }
    BatteryGlyph {
        anchors.verticalCenter: parent.verticalCenter
        level: root.level; charging: root.charging; low: root.low && !root.plugged
    }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        popupWidth: 250
        content: Column {
            Item {
                width: parent.width; height: 32
                GText { x: 10; anchors.verticalCenter: parent.verticalCenter; text: "Battery"; font.weight: Font.DemiBold }
                GText { anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter; text: root.pct + "%"; secondary: true }
            }
            GText {
                x: 10; width: parent.width - 20; height: 22
                text: "Power Source: " + (root.plugged ? "Power Adapter" : "Battery")
                secondary: true; small: true
            }
            GText {
                x: 10; width: parent.width - 20; height: 22
                readonly property string t: root.charging ? root.duration(root.dev?.timeToFull) : root.duration(root.dev?.timeToEmpty)
                visible: t !== "" && !root.full
                text: root.charging ? t + " until full" : t + " remaining"
                secondary: true; small: true
            }
        }
    }
}

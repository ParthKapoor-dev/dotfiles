pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.UPower
import qs.core
import qs.components
import qs.services

// Battery (UPower display device). Mock glyph; percentage on hover by default
// (widgets.battery.showPercent: "hover" | "always" | "never"). tokens ui.meter = "dot-matrix":
// squared glyph (bolt charging, leaf plugged in, red low, pulsing critical) + "87%" (Telemetry). Popover: %, power source, time, power mode,
// battery protection (80% charge cap <-> full charge).
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
    readonly property bool low: pct <= (options.lowPercent ?? 20) && !plugged
    readonly property bool critical: pct <= (options.criticalPercent ?? 10) && !plugged
    readonly property string mode: options.showPercent ?? "hover"
    visible: present
    hpad: 7
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    spacing: Theme.dotMatrix ? 4 : 0

    function duration(s) {
        if (!s || s <= 0) return "";
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        return h + ":" + String(m).padStart(2, "0");
    }

    // hover percentage eases open (width + fade) instead of popping; the glyph keeps its own
    // 5px gap inside the box so the row spacing doesn't jump when it closes
    readonly property bool showPct: !Theme.dotMatrix && (root.mode === "always" || (root.mode === "hover" && (root.hovered || root.active)))
    Item {
        visible: !Theme.dotMatrix
        anchors.verticalCenter: parent.verticalCenter
        height: pctText.implicitHeight
        width: root.showPct ? pctText.implicitWidth + 5 : 0
        clip: true
        Behavior on width { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        GText {
            id: pctText
            text: root.pct + "%"
            font.features: ({ "tnum": 1 })
            opacity: root.showPct ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        }
    }
    BatteryGlyph {
        visible: !Theme.dotMatrix
        anchors.verticalCenter: parent.verticalCenter
        level: root.level; charging: root.charging; low: root.low
    }
    // Telemetry: a state mark (bolt = charging, leaf = plugged in and held at the charge cap / full),
    // the battery glyph squared (red fill = low, pulsing = critical) and the percentage. The mark
    // sits beside the glyph: inside a 10px-high body it turns to mush
    Glyph {
        visible: Theme.dotMatrix && name !== ""
        anchors.verticalCenter: parent.verticalCenter
        name: root.charging ? "bolt" : root.plugged ? "leaf" : ""
        size: 11
        color: root.charging ? Theme.label : Theme.label2
    }
    BatteryGlyph {
        visible: Theme.dotMatrix
        anchors.verticalCenter: parent.verticalCenter
        square: Theme.square
        level: root.level; charging: root.charging; low: root.low
        badge: ""
        property real pulse: 1
        opacity: root.critical ? pulse : 1
        SequentialAnimation on pulse {
            running: root.critical
            loops: Animation.Infinite
            NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        }
    }
    GText {
        visible: Theme.dotMatrix
        anchors.verticalCenter: parent.verticalCenter
        text: root.pct + "%"
        color: root.low ? Theme.red : Theme.label
        font.family: Theme.fontLabel
        font.pixelSize: 11
        font.weight: Font.Medium
        font.features: ({ "tnum": 1 })
    }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        align: "itemRight"
        content: Column {
            PopHeader { width: parent.width; title: "Battery"; value: root.pct + "%" }
            SectionLabel {
                topPadding: 0
                readonly property string t: root.charging ? root.duration(root.dev?.timeToFull) : root.duration(root.dev?.timeToEmpty)
                text: "Power Source: " + (root.plugged ? "Power Adapter" : "Battery")
                      + (root.full ? " · Fully charged" : t ? " · " + t + (root.charging ? " until full" : " left") : "")
            }
            SectionLabel { visible: Power.available; text: "Power Mode" }
            Item {
                visible: Power.available
                width: parent.width; height: 38
                Segmented {
                    x: 8; y: 2; width: parent.width - 16
                    model: Power.modes.map(m => ({ id: m.id, label: m.label === "Performance" ? "Perf" : m.label }))
                    current: Power.profile
                    onPicked: id => Power.set(id)
                }
            }
            // charge limit (services/ChargeLimit): click = 80% cap <-> full charge for travel
            ListRow {
                visible: ChargeLimit.supported
                width: parent.width
                icon: "leaf"
                on: ChargeLimit.on
                busy: ChargeLimit.busy
                title: "Battery Protection"
                subtitle: ChargeLimit.ok ? ChargeLimit.label : "Not applied (firmware " + ChargeLimit.applied + "%)"
                subtitleColor: ChargeLimit.ok ? Theme.label2 : Theme.red
                trailing: ChargeLimit.on ? ChargeLimit.cap + "%" : "100%"
                onClicked: ChargeLimit.toggle()
            }
            Item { width: 1; height: 4 }
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components
import qs.services

// Plan usage (services/Usage): a ring for the Claude 5-hour window (% used), the time to its reset
// ("2H14") and a thin 5-bar meter for the weekly window. Calm/dim below 50 %, white to warnAt,
// accent from widgets.usage.warnAt (80) and pulsing from 95 %. Numbers from before the last 5-hour
// reset are "stale": dim, hollow ring, "–". Hidden until a statusline has written any data.
// Click = popover: every account (Claude, the expai login if it is a different one, Codex) with its
// windows, exact reset times and countdowns, when it was seen, today's estimated spend
// (`nox agents usage`) and a row into Mission Control.
// widgets.usage: { warnAt: 80, codex: true, codexInterval: 300000 }
BarButton {
    id: root
    property string widgetId: "usage"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    readonly property var g: Usage.primary
    readonly property bool stale: Usage.stale(g)
    readonly property real p5: Usage.pctNow(g?.five_hour)
    readonly property real p7: Usage.pctNow(g?.seven_day)
    readonly property int lvl: stale ? 0 : Usage.level(p5)
    hpad: 7
    spacing: 6
    visible: Usage.any
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    onActiveChanged: {
        Usage.popoverOpen = active;
        if (active && typeof Agents.refreshUsage === "function") Agents.refreshUsage();
    }

    function tone(level, isStale) {
        return isStale ? Theme.label3 : level >= 2 ? Theme.accent : level === 1 ? Theme.label : Theme.label2;
    }
    readonly property color c5: tone(lvl, stale)

    UsageRing {
        id: ring
        anchors.verticalCenter: parent.verticalCenter
        value: root.stale ? 0 : root.p5 / 100
        color: root.c5
        hollow: root.stale
        SequentialAnimation on opacity {
            running: root.lvl >= 3 && root.visible
            loops: Animation.Infinite
            onRunningChanged: if (!running) ring.opacity = 1
            NumberAnimation { to: 0.3; duration: 650; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 650; easing.type: Easing.InOutSine }
        }
    }
    // fixed widths ("100%", "4H59") so the bar doesn't twitch as numbers change
    Item {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(widest.advanceWidth, pct.implicitWidth); height: pct.implicitHeight
        TextMetrics { id: widest; font: pct.font; text: "88%" }
        GText {
            id: pct
            anchors.verticalCenter: parent.verticalCenter
            text: root.stale || root.p5 < 0 ? "–" : Math.round(root.p5) + "%"
            color: root.c5
            font.family: Theme.dotMatrix ? Theme.fontLabel : Theme.fontUi
            font.pixelSize: Theme.dotMatrix ? 11 : Theme.fontSize - 1
            font.weight: Theme.dotMatrix ? Font.Medium : Font.Normal
            font.features: ({ "tnum": 1 })
        }
    }
    GText {
        visible: !root.stale && text !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: Usage.left(root.g?.five_hour?.resets_at).toUpperCase()
        color: Theme.label3
        font.family: Theme.fontLabel
        font.pixelSize: 10
        font.weight: Font.Medium
        font.letterSpacing: 0.4
        font.features: ({ "tnum": 1 })
    }
    // weekly: 5 thin bars (the Stats meter, thinner)
    Row {
        visible: root.p7 >= 0
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1.5
        Repeater {
            model: 5
            Rectangle {
                required property int index
                width: 2; height: 9
                radius: Theme.square ? 0 : 1
                color: index < Math.round(root.p7 / 20) ? root.tone(Usage.level(root.p7), root.stale) : Theme.fill3
                Behavior on color { ColorAnimation { duration: Theme.durFade } }
            }
        }
    }

    // ---- popover ----
    // the meter under each window (dot-matrix bars in Telemetry, a thin bar elsewhere)
    component Meter: Item {
        id: m
        property real value: 0
        property color color: Theme.label
        implicitHeight: Theme.dotMatrix ? 8 : 4
        DotMeter { visible: Theme.dotMatrix; anchors.fill: parent; style: "bars"; value: m.value; fillColor: m.color }
        Rectangle {
            visible: !Theme.dotMatrix
            anchors.fill: parent
            radius: 2
            color: Theme.fill2
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, m.value)); height: parent.height
                radius: 2
                color: m.color
                Behavior on width { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
            }
        }
    }
    function windowName(key, w) {
        if (key === "five_hour") return "5-hour";
        if (key === "seven_day") return "Weekly";
        if (key === "spend_limit") return "Spend limit";
        if (key.startsWith("model:")) return "Weekly · " + key.slice(6);
        if (key.startsWith("seven_day_")) {
            const n = key.slice(10).replace(/_/g, " ");
            return "Weekly · " + n.charAt(0).toUpperCase() + n.slice(1);
        }
        const mins = w?.window_minutes ?? 0;
        return mins ? (mins % 1440 === 0 ? mins / 1440 + "-day" : mins % 60 === 0 ? mins / 60 + "-hour" : mins + "-min") : key.replace(/_/g, " ");
    }
    function windows(gr) {
        const l = gr?.limits ?? {};
        const keys = Object.keys(l).sort((a, b) => {
            const r = k => k === "five_hour" ? 0 : k === "seven_day" ? 1 : 2;
            return r(a) - r(b) || a.localeCompare(b);
        });
        return keys.map(k => ({ key: k, w: l[k] }));
    }
    function money(x) { return "$" + (x >= 100 ? Math.round(x) : x.toFixed(2)); }
    function tokens(n) { return n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e3 ? Math.round(n / 1e3) + "K" : String(n); }

    // one window: name + % on a line, the meter, then "resets Fri 09:00 · in 3d4h"
    component Win: Column {
        id: wr
        property string name
        property var w
        property bool groupStale: false
        readonly property real p: Usage.pctNow(w)
        readonly property bool reset: !!w?.resets_at && w.resets_at * 1000 <= Usage.now
        readonly property color c: root.tone(Usage.level(p), groupStale && !reset)
        x: 10; width: parent.width - 20
        spacing: 5
        topPadding: 5; bottomPadding: 6
        Item {
            width: parent.width; height: nm.implicitHeight
            GText { id: nm; text: wr.name }
            GText {
                anchors.right: parent.right
                text: wr.reset ? "–" : Math.round(wr.p) + "%" + (wr.w?.used_usd !== undefined ? "  " + root.money(wr.w.used_usd) + (wr.w.limit_usd ? " / " + root.money(wr.w.limit_usd) : "") : "")
                color: Usage.level(wr.p) >= 2 && !wr.groupStale ? Theme.accent : Theme.label
                font.family: Theme.dotMatrix ? Theme.fontLabel : Theme.fontUi
                font.weight: Font.Medium
                font.features: ({ "tnum": 1 })
            }
        }
        Meter { width: parent.width; value: wr.reset ? 0 : wr.p / 100; color: wr.c }
        GText {
            visible: !!wr.w?.resets_at
            width: parent.width
            small: true
            secondary: true
            font.features: ({ "tnum": 1 })
            text: wr.reset ? "Reset " + Usage.at(wr.w.resets_at) + " · not seen since"
                           : "Resets " + Usage.at(wr.w?.resets_at) + " · in " + Usage.left(wr.w?.resets_at)
        }
    }

    readonly property var popup: pop
    GPopup {
        id: pop
        popupId: root.popupId
        anchorItem: root
        align: "itemRight"
        popupWidth: 300
        content: Column {
            id: col
            PopHeader {
                width: parent.width
                title: "Plan Usage"
                value: root.g ? (root.stale ? "Stale" : Math.round(root.p5) + "% · 5h") : ""
            }
            Repeater {
                model: Usage.groups
                Column {
                    id: grp
                    required property var modelData
                    required property int index
                    readonly property bool isStale: Usage.stale(modelData)
                    width: col.width
                    MenuSep { visible: grp.index > 0; width: parent.width }
                    Item {
                        width: parent.width; height: head.implicitHeight
                        SectionLabel {
                            id: head
                            width: parent.width - when.implicitWidth - 4
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                            text: grp.modelData.source === "codex" ? "Codex" + (grp.modelData.plan ? " · " + grp.modelData.plan : "")
                                : "Claude" + (grp.modelData.account !== "claude" && grp.modelData.via.indexOf("claude") < 0 ? " · " + grp.modelData.account : "")
                        }
                        SectionLabel {
                            id: when
                            anchors.right: parent.right
                            width: implicitWidth
                            wrapMode: Text.NoWrap
                            text: (grp.isStale ? "Stale · " : "") + Usage.ago(grp.modelData.updated)
                            color: grp.isStale ? Theme.label3 : Theme.label2
                        }
                    }
                    // every window reset since the reading (no session for a while): one line, no bars
                    readonly property bool allReset: root.windows(modelData).every(x => !!x.w?.resets_at && x.w.resets_at * 1000 <= Usage.now)
                    GText {
                        visible: grp.allReset
                        x: 10; width: parent.width - 20
                        topPadding: 2; bottomPadding: 6
                        small: true
                        secondary: true
                        text: "Every window has reset since this reading"
                    }
                    Repeater {
                        model: grp.allReset ? [] : root.windows(grp.modelData)
                        Win {
                            required property var modelData
                            name: root.windowName(modelData.key, modelData.w)
                            w: modelData.w
                            groupStale: grp.isStale
                        }
                    }
                    GText {
                        visible: grp.modelData.source === "claude" && !!grp.modelData.model
                        x: 10; width: parent.width - 20
                        bottomPadding: 4
                        small: true
                        color: Theme.label3
                        text: "Status line of " + grp.modelData.via.map(a => a === "claude" ? "~/.claude" : a).join(" + ") + " · " + grp.modelData.model
                        elide: Text.ElideRight
                    }
                }
            }
            // today's estimate (API-price equivalent of the tracked sessions, `nox agents usage`)
            Column {
                readonly property var t: Agents.today ?? null
                visible: (t?.cost ?? 0) > 0
                width: parent.width
                MenuSep { width: parent.width }
                Item {
                    x: 10; width: parent.width - 20; height: 26
                    GText { anchors.verticalCenter: parent.verticalCenter; text: "Today" }
                    GText {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: "≈ " + root.money(parent.parent.t?.cost ?? 0) + " · " + root.tokens(parent.parent.t?.tokens ?? 0) + " tok"
                        secondary: true
                        font.features: ({ "tnum": 1 })
                    }
                }
                GText {
                    x: 10; width: parent.width - 20
                    bottomPadding: 4
                    small: true
                    color: Theme.label3
                    text: "API list-price equivalent of tracked sessions"
                }
            }
            MenuSep { width: parent.width }
            MenuRow {
                width: parent.width
                text: "Mission Control"
                shortcut: "Ctrl Super M"
                onTriggered: { Panels.close(); Agents.show(""); }
            }
        }
    }
}

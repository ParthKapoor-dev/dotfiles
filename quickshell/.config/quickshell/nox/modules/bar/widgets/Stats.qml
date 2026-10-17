pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.components
import qs.services

// System monitor (services/SysStats: procfs via FileView, no processes). widgets.stats.show picks
// the readings in order: "cpu" | "mem" | "temp" | "net" (default cpu + mem).
// Plain looks (Ember): small glyph + "12%". Dot-matrix looks (Telemetry): mono caps tag, a 5-bar
// meter and the number (mock telemetry .bdots, like the battery). Values over widgets.stats.hot
// (default 0.85) turn accent. Click = popover with CPU history, memory, swap, temperature,
// network and the top processes (`top`, only while the popover is open).
BarButton {
    id: root
    property string widgetId: "stats"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    readonly property var show: options.show ?? ["cpu", "mem"]
    readonly property real hot: options.hot ?? 0.85
    hpad: 7
    spacing: Theme.dotMatrix ? 9 : 8
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)

    function reading(k) {
        switch (k) {
        case "cpu": return { glyph: "cpu", tag: "CPU", v: SysStats.cpu, text: Math.round(SysStats.cpu * 100) + "%", w: "88%" };
        case "mem": return { glyph: "mem", tag: "MEM", v: SysStats.mem, text: Math.round(SysStats.mem * 100) + "%", w: "88%" };
        case "temp": return { glyph: "gauge", tag: "TMP", v: SysStats.temp > 0 ? SysStats.temp / 100 : 0, text: SysStats.temp > 0 ? Math.round(SysStats.temp) + "°" : "–", w: "88°" };
        case "net": return { glyph: "arrowUp", tag: "NET", v: -1, text: SysStats.fmtRate(SysStats.rxRate + SysStats.txRate).replace(" ", ""), w: "99.9MB/s" };
        }
        return null;
    }

    Repeater {
        model: root.show.filter(k => ["cpu", "mem", "temp", "net"].indexOf(k) !== -1)
        Row {
            id: cell
            required property string modelData
            readonly property var r: root.reading(modelData)
            readonly property bool isHot: r.v >= root.hot
            anchors.verticalCenter: parent?.verticalCenter
            spacing: Theme.dotMatrix ? 5 : 4
            Glyph {
                visible: !Theme.dotMatrix
                anchors.verticalCenter: parent.verticalCenter
                name: cell.r.glyph; size: 14
                color: cell.isHot ? Theme.accent : Theme.label
            }
            GText {
                visible: Theme.dotMatrix
                anchors.verticalCenter: parent.verticalCenter
                text: cell.r.tag
                color: Theme.label3
                font.family: Theme.fontLabel
                font.pixelSize: 10
                font.weight: Font.Medium
                font.letterSpacing: 0.6
            }
            // 5-bar meter (dot-matrix looks)
            Row {
                visible: Theme.dotMatrix && cell.r.v >= 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Repeater {
                    model: 5
                    Rectangle {
                        required property int index
                        width: 3; height: 9
                        color: index < Math.round(cell.r.v * 5) ? (cell.isHot ? Theme.accent : Theme.label) : Theme.fill3
                        Behavior on color { ColorAnimation { duration: Theme.durFade } }
                    }
                }
            }
            // fixed width (a two-digit value) so the bar doesn't twitch every sample
            Item {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(widest.advanceWidth, num.implicitWidth)
                height: num.implicitHeight
                TextMetrics { id: widest; font: num.font; text: cell.r.w }
                GText {
                    id: num
                    anchors.verticalCenter: parent.verticalCenter
                    text: cell.r.text
                    color: cell.isHot ? Theme.accent : Theme.label
                    font.family: Theme.dotMatrix ? Theme.fontLabel : Theme.fontUi
                    font.pixelSize: Theme.dotMatrix ? 11 : Theme.fontSize - 1
                    font.weight: Theme.dotMatrix ? Font.Medium : Font.Normal
                    font.features: ({ "tnum": 1 })
                }
            }
        }
    }

    // ---- popover ----
    property var procs: []
    Process {
        id: top
        // second frame = CPU over the 0.4 s between frames (the first is since process start)
        command: ["top", "-b", "-n", "2", "-d", "0.4", "-o", "%CPU", "-w", "512"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                let n = 0, out = [];
                for (const l of lines) {
                    if (/^\s*PID\s/.test(l)) { n++; continue; }
                    if (n < 2) continue;
                    const f = l.trim().split(/\s+/);
                    if (f.length < 12) continue;
                    out.push({ pid: f[0], cpu: Number(f[8]), mem: Number(f[9]), name: f.slice(11).join(" ") });
                    if (out.length >= (root.options.topCount ?? 5)) break;
                }
                root.procs = out;
            }
        }
    }
    Timer {
        running: Panels.popup === root.popupId
        interval: Math.max(2000, SysStats.interval)
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!top.running) top.running = true
    }

    component Meter: Item {
        id: m
        property real value: 0
        implicitHeight: Theme.dotMatrix ? 8 : 4
        DotMeter { visible: Theme.dotMatrix; anchors.fill: parent; style: "bars"; value: m.value; fillColor: m.value >= root.hot ? Theme.accent : Theme.label }
        Rectangle {
            visible: !Theme.dotMatrix
            anchors.fill: parent
            radius: 2
            color: Theme.fill2
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, m.value)); height: parent.height
                radius: 2
                color: m.value >= root.hot ? Theme.accent : Theme.label
                Behavior on width { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
            }
        }
    }
    // label + value on one line, meter under it (mock .pop rows: 10px inset)
    component Stat: Column {
        id: st
        property string label
        property string value
        property real meter: -1
        x: 10; width: parent.width - 20
        spacing: 5
        topPadding: 5; bottomPadding: 5
        Item {
            width: parent.width; height: l.implicitHeight
            GText { id: l; text: st.label }
            GText { anchors.right: parent.right; text: st.value; secondary: true; font.features: ({ "tnum": 1 }) }
        }
        Meter { visible: st.meter >= 0; width: parent.width; value: st.meter }
    }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        align: "itemRight"
        content: Column {
            id: col
            PopHeader { width: parent.width; title: "System"; value: SysStats.cores ? SysStats.cores + " threads" : "" }
            // CPU history: one bar per sample (oldest left), dot-matrix columns in Telemetry
            Item {
                x: 10; width: parent.width - 20; height: 34
                Row {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    spacing: 2
                    Repeater {
                        // always 30 slots: samples not taken yet are flat placeholder ticks
                        model: new Array(Math.max(0, 30 - SysStats.cpuHistory.length)).fill(-1).concat(SysStats.cpuHistory)
                        Rectangle {
                            required property real modelData
                            width: (col.width - 20 - 29 * 2) / 30
                            height: Math.max(2, modelData * 34)
                            radius: Theme.square ? 0 : 1
                            color: modelData < 0 ? Theme.fill2 : modelData >= root.hot ? Theme.accent : Theme.rgba(Theme.t.color.label, 0.5)
                            anchors.bottom: parent?.bottom
                        }
                    }
                }
            }
            Stat {
                label: "CPU"
                value: Math.round(SysStats.cpu * 100) + "% · load " + SysStats.load.map(x => x.toFixed(2)).join(" ")
                meter: SysStats.cpu
            }
            Stat {
                label: "Memory"
                value: SysStats.fmtBytes(SysStats.memUsed) + " of " + SysStats.fmtBytes(SysStats.memTotal)
                meter: SysStats.mem
            }
            Stat {
                visible: SysStats.swapTotal > 0
                label: "Swap"
                value: SysStats.fmtBytes(SysStats.swapUsed) + " of " + SysStats.fmtBytes(SysStats.swapTotal)
                meter: SysStats.swapTotal > 0 ? SysStats.swapUsed / SysStats.swapTotal : 0
            }
            Stat {
                visible: SysStats.temp > 0
                label: "Temperature"
                value: Math.round(SysStats.temp) + " °C · " + SysStats.tempSensor
            }
            Stat {
                label: "Network"
                value: "↓ " + SysStats.fmtRate(SysStats.rxRate) + "   ↑ " + SysStats.fmtRate(SysStats.txRate)
            }
            Item {
                width: col.width; height: hdr.implicitHeight
                SectionLabel { id: hdr; text: "Top Processes" }
                SectionLabel { anchors.right: parent.right; anchors.rightMargin: 48; width: 58; wrapMode: Text.NoWrap; horizontalAlignment: Text.AlignRight; text: "CPU" }
                SectionLabel { anchors.right: parent.right; width: 58; wrapMode: Text.NoWrap; horizontalAlignment: Text.AlignRight; text: "Mem" }
            }
            Repeater {
                model: root.procs
                Item {
                    id: pr
                    required property var modelData
                    width: col.width; height: 26
                    GText { x: 10; width: parent.width - 126; anchors.verticalCenter: parent.verticalCenter; text: pr.modelData.name }
                    GText {
                        x: parent.width - 10 - 48 - 48; width: 48; anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: pr.modelData.cpu.toFixed(1) + "%"
                        color: pr.modelData.cpu >= 100 * root.hot ? Theme.accent : Theme.label
                        font.features: ({ "tnum": 1 })
                    }
                    GText {
                        x: parent.width - 10 - 48; width: 48; anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: pr.modelData.mem.toFixed(1) + "%"
                        secondary: true
                        font.features: ({ "tnum": 1 })
                    }
                }
            }
            GText {
                visible: root.procs.length === 0
                x: 10; height: 26
                text: "Sampling…"; secondary: true
            }
            MenuSep { width: parent.width }
            MenuRow {
                width: parent.width
                text: "Open System Monitor"
                onTriggered: { Panels.close(); Quickshell.execDetached(root.options.monitorCommand ?? (Config.opt.terminal ?? ["ghostty"]).concat(["-e", "btop"])); }
            }
        }
    }
}

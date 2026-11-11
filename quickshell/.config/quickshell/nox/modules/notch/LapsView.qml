pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// Laps (mock #V-laps): today as lanes, one per agent session (`nox agents laps`): working
// stretches in accent, time spent waiting on you hatched red, a diamond each time you stepped in,
// a "now" line; agent time / your waits / parallel peak / leverage on top; what shipped below.
// Numbers it can't know are shown as "—", never guessed.
Item {
    id: v
    property bool shown: false
    property var rd: null
    readonly property var m: rd?.metrics ?? ({})
    readonly property var lanes: (rd?.lanes ?? []).slice(0, 7)
    readonly property real t0: { let a = Infinity; for (const l of lanes) for (const s of l.segs ?? []) a = Math.min(a, s[0]); if (!isFinite(a)) a = Date.now() - 8 * 3600000; a = Math.max(a, rd?.from ?? 0); const d = new Date(a); d.setMinutes(0, 0, 0); return d.getTime(); }
    readonly property real t1: Math.max(rd?.now ?? Date.now(), t0 + 3600000)
    implicitHeight: 96 + Math.max(1, lanes.length) * 24 + 18 + 42

    function load() { Agents.helperRun(["laps", "--json"], (code, out) => { const d = Agents.parse(out); if (d?.ok) rd = d; }); }
    onShownChanged: if (shown) load()
    Timer { interval: 30000; repeat: true; running: v.shown; onTriggered: v.load() }
    function dur(ms) {
        if (ms === null || ms === undefined) return ["—", ""];
        const h = Math.floor(ms / 3600000), mm = Math.round((ms % 3600000) / 60000);
        return h ? [String(h), "h " + (mm < 10 ? "0" : "") + mm + "m"] : [String(mm), "m"];
    }
    function xOf(t, w) { return (t - t0) / (t1 - t0) * w; }

    Row {
        id: mets
        width: parent.width
        spacing: 8
        Repeater {
            model: [
                { v: v.dur(v.m.agentMs), l: "agent time", acc: true },
                { v: v.dur(v.m.waitMs), l: "waited on you" },
                { v: [v.m.parallelPeak !== undefined && v.m.parallelPeak !== null ? String(v.m.parallelPeak) : "—", ""], l: "at once, peak" },
                { v: [v.m.leverage !== undefined && v.m.leverage !== null ? Number(v.m.leverage).toFixed(1) : "—", v.m.leverage !== null && v.m.leverage !== undefined ? "×" : ""], l: "leverage" }
            ]
            Rectangle {
                id: met
                required property var modelData
                width: (mets.width - 24) / 4
                height: 64
                radius: 9
                color: Theme.white(0.05)
                Row {
                    x: 12; y: 8
                    GText { text: met.modelData.v[0]; font.pixelSize: 28; font.weight: Font.ExtraLight; font.features: ({ "tnum": 1 }); color: met.modelData.acc ? Theme.accent : Theme.label }
                    GText { text: met.modelData.v[1]; font.pixelSize: 14; color: Theme.label2; anchors.baseline: parent.children[0].baseline }
                }
                GText { x: 12; y: 44; text: met.modelData.l.toUpperCase(); font.family: Theme.fontMono; font.pixelSize: 10; font.letterSpacing: 1.2; color: Theme.label3 }
            }
        }
    }
    Item {
        id: lanesBox
        y: 78
        width: parent.width
        height: Math.max(1, v.lanes.length) * 24 + 18
        readonly property real lx: 86
        readonly property real lw: width - lx
        Repeater {
            model: v.lanes
            Item {
                id: lane
                required property var modelData
                required property int index
                y: index * 24
                width: lanesBox.width
                height: 24
                GText {
                    width: lanesBox.lx - 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: lane.modelData.project + (lane.modelData.live ? " ●" : "")
                    font.family: Theme.fontMono; font.pixelSize: 11; color: Theme.label2
                }
                Rectangle { x: lanesBox.lx; width: lanesBox.lw; y: 12; height: 1; color: Theme.white(0.08) }
                Repeater {
                    model: lane.modelData.segs ?? []
                    Rectangle {
                        required property var modelData
                        x: lanesBox.lx + v.xOf(modelData[0], lanesBox.lw)
                        width: Math.max(2, v.xOf(modelData[1], lanesBox.lw) - v.xOf(modelData[0], lanesBox.lw))
                        y: 7; height: 10; radius: 3
                        color: lane.modelData.kind === "codex" ? "#64D2FF" : Theme.accent
                        opacity: 0.85
                    }
                }
                Repeater {
                    model: lane.modelData.waits ?? []
                    Rectangle {
                        required property var modelData
                        x: lanesBox.lx + v.xOf(modelData[0], lanesBox.lw)
                        width: Math.max(4, v.xOf(modelData[1], lanesBox.lw) - v.xOf(modelData[0], lanesBox.lw))
                        y: 7; height: 10; radius: 2
                        color: "transparent"
                        border.width: 1.5; border.color: Theme.red
                    }
                }
                Repeater {
                    model: lane.modelData.marks ?? []
                    Rectangle {
                        required property var modelData
                        x: lanesBox.lx + v.xOf(modelData, lanesBox.lw) - 3.5
                        y: 3; width: 7; height: 7
                        rotation: 45
                        color: Theme.label
                        border.width: 1.5; border.color: "#000000"
                    }
                }
            }
        }
        // hours + now
        Repeater {
            model: { const out = []; const step = (v.t1 - v.t0) > 6 * 3600000 ? 2 * 3600000 : 3600000; for (let t = v.t0; t <= v.t1; t += step) out.push(t); return out; }
            GText {
                required property var modelData
                x: lanesBox.lx + v.xOf(modelData, lanesBox.lw) - width / 2
                y: lanesBox.height - 14
                text: new Date(modelData).getHours() + ":00"
                font.family: Theme.fontMono; font.pixelSize: 10; color: Theme.label3
            }
        }
        Rectangle {
            x: lanesBox.lx + v.xOf(v.rd?.now ?? Date.now(), lanesBox.lw)
            y: -4; width: 1; height: lanesBox.height - 14
            color: Theme.accent
            Rectangle { anchors.centerIn: parent; width: 5; height: parent.height; color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18) }
        }
    }
    GText {
        y: lanesBox.y + lanesBox.height + 8
        width: parent.width
        textFormat: Text.StyledText
        wrapMode: Text.WordWrap; maximumLineCount: 2
        text: {
            const sh = v.rd?.shipped;
            if (!sh) return "";
            const repos = (sh.repos ?? []).filter(r => r.count > 0).map(r => r.project + " " + r.count);
            return "<b>Shipped today:</b> " + (sh.commits ?? 0) + " commits" + (repos.length ? " (" + repos.slice(0, 4).join(", ") + ")" : "")
                + " · " + (sh.prs?.length ?? 0) + " PRs · " + (v.m.interventions ?? "—") + " times you stepped in";
        }
        font.pixelSize: 12; color: Theme.label2
    }
}

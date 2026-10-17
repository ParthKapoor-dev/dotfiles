pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.core
import qs.components

// Month grid (mock .cal): red "OCTOBER 2026" heading, Monday-first weekday initials, 26px days,
// today in a red 24px circle, days of other months in label3. Wheel / arrows change month.
Column {
    id: root
    property int offset: 0
    SystemClock { id: clock; precision: SystemClock.Hours }
    readonly property date today: clock.date
    readonly property date month: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property var days: {
        const first = (month.getDay() + 6) % 7;      // Monday-first
        const start = new Date(month.getFullYear(), month.getMonth(), 1 - first);
        const out = [];
        for (let i = 0; i < 42; i++) out.push(new Date(start.getFullYear(), start.getMonth(), start.getDate() + i));
        const rows = Math.ceil((first + new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()) / 7);
        return out.slice(0, rows * 7);
    }
    spacing: 6

    Item {
        width: parent.width; height: 16
        GText {
            text: Qt.formatDate(root.month, "MMMM yyyy").toUpperCase()
            color: Theme.red
            font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 0.44
            font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi
        }
        Row {
            anchors.right: parent.right
            spacing: 2
            Repeater {
                model: [["chevL", -1], ["chevR", 1]]
                Item {
                    required property var modelData
                    width: 16; height: 16
                    Glyph { anchors.centerIn: parent; name: parent.modelData[0]; size: 12; color: Theme.label2 }
                    MouseArea { anchors.fill: parent; onClicked: root.offset += parent.modelData[1] }
                }
            }
        }
    }
    Grid {
        id: grid
        columns: 7
        width: parent.width
        rowSpacing: 2
        readonly property real cw: width / 7
        Repeater {
            model: ["M", "T", "W", "T", "F", "S", "S"]
            GText {
                required property string modelData
                width: grid.cw; height: 16
                horizontalAlignment: Text.AlignHCenter
                text: modelData; color: Theme.label3
                font.pixelSize: 10; font.weight: Font.DemiBold
            }
        }
        Repeater {
            model: root.days
            Item {
                id: day
                required property date modelData
                readonly property bool isToday: modelData.toDateString() === root.today.toDateString()
                readonly property bool other: modelData.getMonth() !== root.month.getMonth()
                width: grid.cw; height: 26
                Rectangle {
                    visible: day.isToday
                    anchors.centerIn: parent
                    width: 24; height: 24; radius: Theme.square ? 4 : 12
                    color: Theme.red
                }
                GText {
                    anchors.centerIn: parent
                    text: day.modelData.getDate()
                    font.pixelSize: 11
                    font.weight: day.isToday ? Font.Bold : Font.Normal
                    font.features: ({ "tnum": 1 })
                    color: day.isToday ? "white" : day.other ? Theme.label3 : Theme.label
                }
            }
        }
    }
    WheelHandler { onWheel: e => root.offset += e.angleDelta.y > 0 ? -1 : 1 }
}

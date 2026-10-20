pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import qs.core
import qs.components
import qs.services

// The open shelf (mock .dsh-p): header (dot, SHELF, count, clear), the drop zone while something is
// dragged in, the items (one card, a tilted pile with a count, or the fanned-out list) and the
// footer (Move out toggle, expiry). Skinned per look: Telemetry = opaque square panel, mono caps,
// accent corner brackets on the target, dot-matrix count; Ember = glass, rounded.
Item {
    id: panel
    required property var ctl
    readonly property string st: ctl.st
    readonly property bool target: st === "target"
    readonly property bool over: ctl.over && target
    readonly property bool shownOpen: st === "open" || st === "target"
    readonly property int n: Shelf.count
    readonly property bool fan: ctl.fan && n > 1
    readonly property string mode: n > 1 ? (fan ? "fan" : "pile") : "solo"
    readonly property real stride: 42

    width: 148
    height: col.height
    property real near: over ? 1 : target ? 0.45 : 0
    Behavior on near { NumberAnimation { duration: Theme.durFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }

    // ---- surface ----
    RectangularShadow {
        anchors.fill: bg
        radius: bg.radius
        offset.y: 26; blur: 64; spread: -6
        color: Theme.rgba("#000000", Theme.glassOpaque ? 0.8 : 0.6)
    }
    // target glow (mock box-shadow 0 0 calc(18px + near*40px) accent)
    RectangularShadow {
        anchors.fill: bg
        radius: bg.radius
        blur: 18 + panel.near * 44
        spread: panel.over ? 2 : 0
        color: Theme.rgba(Theme.t.color.accent, panel.over ? 0.36 : 0.08 + panel.near * 0.22)
        opacity: panel.target ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        Behavior on blur { NumberAnimation { duration: Theme.durFade } }
    }
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Theme.square ? 4 : Math.max(8, Theme.radiusPanel - 2)
        color: Theme.glassOpaque ? Theme.rgba(Theme.t.color.glass, 1) : Theme.rgba(Theme.t.color.glass, Math.min(1, Theme.t.glass.alpha + 0.16))
        border.width: panel.over ? 1.5 : 1
        border.color: panel.target ? Theme.rgba(Theme.t.color.accent, panel.over ? 0.95 : 0.3 + panel.near * 0.4)
            : Theme.glassOpaque ? Theme.white(0.14) : Theme.rim
        Behavior on border.color { ColorAnimation { duration: Theme.durFade } }
        clip: true
        Image {
            anchors.fill: parent
            source: "../../assets/grain.png"
            fillMode: Image.Tile
            opacity: Theme.glassOpaque ? 0.05 : 0.08
            smooth: false
        }
    }
    // outer dark hairline (glass looks)
    Rectangle {
        visible: !Theme.glassOpaque
        z: -1
        anchors.fill: bg
        anchors.margins: -0.75
        radius: bg.radius + 0.75
        color: "transparent"
        border.width: 0.75
        border.color: Qt.rgba(0, 0, 0, 0.85)
    }
    // Telemetry: accent corner brackets around the target / the pinned shelf
    Brackets {
        visible: Theme.cardBrackets
        anchors.fill: bg
        anchors.margins: panel.over ? -8 : -5
        Behavior on anchors.margins { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        inset: 0; len: 12; thick: 1.5
        color: Theme.accent
        opacity: panel.target || panel.ctl.pinned ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
    }

    Column {
        id: col
        width: parent.width

        // ---- header ----
        Item {
            width: parent.width
            height: 32
            Rectangle {
                id: dot
                x: 11
                anchors.verticalCenter: parent.verticalCenter
                width: 6; height: 6
                radius: Theme.square ? 0 : 3
                readonly property bool lit: panel.target || panel.ctl.pinned
                color: lit ? Theme.accent : Theme.label3
                Behavior on color { ColorAnimation { duration: Theme.durFade } }
                layer.enabled: lit
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Theme.accent; shadowBlur: 0.6; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
            }
            Text {
                x: dot.x + 13
                anchors.verticalCenter: parent.verticalCenter
                text: "SHELF"
                font.family: Theme.fontLabel; font.pixelSize: 10; font.weight: Font.DemiBold
                font.letterSpacing: 1.4
                color: Theme.label2
                Text {
                    x: parent.implicitWidth + 7
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(panel.n).padStart(2, "0")
                    font.family: Theme.fontLabel; font.pixelSize: 10; font.weight: Font.Medium
                    color: Theme.label3
                }
            }
            Rectangle {
                id: clr
                anchors.right: parent.right; anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 22; height: 22
                radius: Theme.square ? 2 : 6
                visible: panel.n > 0
                color: clrMouse.containsMouse ? Theme.fill : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durHover } }
                Glyph { anchors.centerIn: parent; name: "trash"; size: 12; color: clrMouse.containsMouse ? Theme.label : Theme.label3 }
                MouseArea { id: clrMouse; anchors.fill: parent; hoverEnabled: true; onClicked: panel.ctl.clearAll() }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.sep }
        }

        // ---- drop zone (mock .dsh-drop) ----
        Item {
            id: dz
            width: parent.width
            readonly property bool emptyOpen: panel.n === 0 && panel.st === "open"
            readonly property bool on: panel.target || emptyOpen
            readonly property bool row: panel.target && panel.n > 0
            height: on ? (row ? 54 : 92) + 14 : 0
            Behavior on height { NumberAnimation { duration: 420; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
            clip: true
            Rectangle {
                id: zone
                x: 10; y: 10
                width: parent.width - 20
                height: Math.max(0, parent.height - 14)
                radius: Theme.square ? 2 : 8
                color: panel.over ? Theme.rgba(Theme.t.color.accent, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durFade } }
                // marching ants (still and dim on an empty open shelf)
                Shape {
                    anchors.fill: parent
                    opacity: dz.emptyOpen && !panel.target ? 0.5 : 1
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        id: ants
                        strokeColor: Theme.rgba(Theme.t.color.accent, 0.8)
                        strokeWidth: 1
                        fillColor: "transparent"
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [5, 5]
                        NumberAnimation on dashOffset { from: 10; to: 0; duration: 700; loops: Animation.Infinite; running: panel.target }
                        PathRectangle { x: 0.5; y: 0.5; width: zone.width - 1; height: zone.height - 1; radius: zone.radius }
                    }
                }
                Grid {
                    anchors.centerIn: parent
                    columns: dz.row ? 2 : 1
                    rowSpacing: 8; columnSpacing: 8
                    horizontalItemAlignment: Grid.AlignHCenter
                    verticalItemAlignment: Grid.AlignVCenter
                    ShelfIcon {
                        name: "shelf"; size: 18
                        color: Theme.accent
                        transform: Translate { y: panel.over ? 3 : 0; Behavior on y { NumberAnimation { duration: Theme.durPop } } }
                        scale: panel.over ? 1.15 : 1
                        Behavior on scale { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                    }
                    Text {
                        text: dz.emptyOpen && !panel.target ? "SHELF IS EMPTY\nDRAG HERE" : "DROP TO PARK"
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Theme.fontLabel; font.pointSize: 7.125; font.weight: Font.DemiBold
                        font.letterSpacing: 1.5
                        lineHeight: 1.3
                        color: panel.over ? Theme.label : dz.emptyOpen && !panel.target ? Theme.label3 : Theme.label2
                    }
                }
            }
        }

        // ---- items ----
        Item {
            id: body
            width: parent.width
            readonly property real want: panel.n === 0 ? 0 : panel.n === 1 ? 128 : panel.fan ? Math.min(14 + panel.n * panel.stride + 30, 330) : 160
            height: want
            Behavior on height { NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
            clip: true

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.bottomMargin: panel.n > 1 ? 30 : 0
                contentWidth: width
                contentHeight: panel.fan ? 14 + panel.n * panel.stride : height
                interactive: panel.fan && contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                clip: panel.fan
                Item {
                    id: pileLayer
                    width: flick.width
                    height: Math.max(flick.height, flick.contentHeight)
                    Repeater {
                        model: rows
                        ShelfCard {
                            required property string iid
                            required property bool leaving
                            required property bool fresh
                            itemId: iid
                            readonly property int liveOrder: Shelf.items.findIndex(it => it.id === iid)
                            property int lastOrder: 0
                            onLiveOrderChanged: if (liveOrder >= 0) lastOrder = liveOrder
                            order: liveOrder >= 0 ? liveOrder : lastOrder
                            count: panel.n
                            mode: panel.mode
                            grabTarget: panel.mode === "pile" ? ghost : null
                            payload: () => panel.payloadFor(iid)
                            onRemoveRequested: Shelf.remove([iid])
                            onOpenRequested: panel.ctl.openItem(iid)
                            onDragBegan: ids => panel.ctl.outBegan(ids)
                            onDragEnded: (ids, action) => panel.ctl.outEnded(ids, action)
                        }
                    }
                }
            }

            // count badge on the pile (mock .dsh-cnt)
            Rectangle {
                id: cnt
                anchors.right: parent.right; anchors.rightMargin: 6
                y: 3
                z: 20
                height: Theme.square ? 20 : 22
                width: Math.max(Theme.square ? 24 : 22, cntText.implicitWidth + 12)
                radius: Theme.square ? 2 : height / 2
                color: Theme.accent
                border.width: 2
                border.color: Qt.rgba(0, 0, 0, 0.6)
                opacity: panel.mode === "pile" ? 1 : 0
                scale: panel.mode === "pile" ? bump : 0.5
                property real bump: 1
                Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                SequentialAnimation {
                    id: bumpAnim
                    NumberAnimation { target: cnt; property: "bump"; to: 1.3; duration: 120; easing.type: Easing.OutQuad }
                    NumberAnimation { target: cnt; property: "bump"; to: 1; duration: 300; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
                }
                Connections { target: Shelf; function onCountChanged() { if (Shelf.count > 1) bumpAnim.restart(); } }
                RectangularShadow { z: -1; anchors.fill: parent; radius: parent.radius; offset.y: 4; blur: 12; color: Theme.rgba(Theme.t.color.accent, 0.45) }
                Text {
                    id: cntText
                    anchors.centerIn: parent
                    text: panel.n
                    font.family: Theme.square ? Theme.fontNumeric : Theme.fontUi
                    font.pixelSize: Theme.square ? 13 : 11
                    font.weight: Theme.square ? 800 : Font.Bold
                    font.variableAxes: Theme.square ? Theme.numericAxes : ({})
                    color: Theme.onAccent
                }
            }

            // Fan out N / Stack (mock .dsh-fan)
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 12; anchors.rightMargin: 12
                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                height: 22
                radius: Theme.square ? 2 : 6
                visible: panel.n > 1
                color: fanMouse.containsMouse ? Theme.fill : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durHover } }
                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    ShelfIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "fan"; size: 10
                        color: fanMouse.containsMouse ? Theme.label : Theme.label2
                        rotation: panel.fan ? 180 : 0
                        Behavior on rotation { NumberAnimation { duration: Theme.durSheet; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.fan ? "STACK" : "FAN OUT " + panel.n
                        font.family: Theme.fontLabel; font.pointSize: 7.125; font.weight: Font.Medium
                        font.letterSpacing: 1
                        color: fanMouse.containsMouse ? Theme.label : Theme.label2
                    }
                }
                MouseArea { id: fanMouse; anchors.fill: parent; hoverEnabled: true; onClicked: panel.ctl.fan = !panel.ctl.fan }
            }
        }

        // ---- footer: Move out + expiry ----
        Item {
            width: parent.width
            height: 30
            Rectangle { width: parent.width; height: 1; color: Theme.sep }
            Rectangle {
                id: mv
                x: 8
                anchors.verticalCenter: parent.verticalCenter
                height: 20
                width: mvRow.implicitWidth + 13
                radius: Theme.square ? 2 : 5
                color: mvMouse.containsMouse ? Theme.fill : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durHover } }
                Row {
                    id: mvRow
                    x: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12; height: 7
                        radius: Theme.square ? 0 : 3.5
                        color: Shelf.moveOut ? Theme.rgba(Theme.t.color.accent, 0.55) : Theme.fill2
                        Behavior on color { ColorAnimation { duration: Theme.durPop } }
                        Rectangle {
                            x: Shelf.moveOut ? 6 : 1; y: 1
                            width: 5; height: 5
                            radius: Theme.square ? 0 : 2.5
                            color: Shelf.moveOut ? "#ffffff" : Theme.label2
                            Behavior on x { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "MOVE OUT"
                        font.family: Theme.fontLabel; font.pixelSize: 9; font.weight: Font.Medium
                        font.letterSpacing: 0.7
                        color: mvMouse.containsMouse ? Theme.label : Theme.label2
                    }
                }
                MouseArea {
                    id: mvMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        Shelf.setMoveOut(!Shelf.moveOut);
                        Panels.hud(Shelf.moveOut ? "Dragging out moves the item off the shelf" : "Dragging out leaves it on the shelf", "check");
                    }
                }
            }
            Row {
                anchors.right: parent.right; anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                ShelfIcon { anchors.verticalCenter: parent.verticalCenter; name: "clock"; size: 10; color: Theme.label3 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (Shelf.expireHours >= 1 ? Math.round(Shelf.expireHours) + "H" : Math.round(Shelf.expireHours * 60) + "M")
                    font.family: Theme.fontLabel; font.pixelSize: 9; font.weight: Font.Medium
                    font.letterSpacing: 0.7
                    color: Theme.label3
                }
            }
        }
    }

    // ---- drag image of the whole pile (mock .dsh-ghost): the top three thumbs + the count. Lives
    // off-screen, always up to date, so a press can grab it at once ----
    Item {
        id: ghost
        x: -2000
        width: 150; height: 100
        Repeater {
            model: Shelf.items.slice(0, 3)
            Item {
                id: ghostCard
                required property var modelData
                required property int index
                x: 12 + [0, 5, -5][index]; y: 14 + [0, -5, -8][index]
                z: 3 - index
                width: 124; height: 72
                rotation: [0, 5, -6][index]
                RectangularShadow { anchors.fill: parent; radius: Theme.square ? 2 : 7; offset.y: 8; blur: 16; color: Theme.rgba("#000000", 0.5) }
                ShelfThumb { item: ghostCard.modelData; showTag: ghostCard.index === 0 }
            }
        }
        Rectangle {
            x: 12 + 124 - width + 8; y: 14 - 9
            z: 9
            visible: panel.n > 1
            height: Theme.square ? 20 : 22
            width: Math.max(Theme.square ? 24 : 22, gText.implicitWidth + 12)
            radius: Theme.square ? 2 : height / 2
            color: Theme.accent
            Text {
                id: gText
                anchors.centerIn: parent
                text: panel.n
                font.family: Theme.square ? Theme.fontNumeric : Theme.fontUi
                font.pixelSize: Theme.square ? 13 : 11
                font.weight: Theme.square ? 800 : Font.Bold
                font.variableAxes: Theme.square ? Theme.numericAxes : ({})
                color: Theme.onAccent
            }
        }
    }

    // ---- rows: one per card, kept while a removed card plays its exit ----
    ListModel { id: rows }
    property var freshIds: ({})
    function sync() {
        const live = Shelf.items.map(it => it.id);
        for (let i = rows.count - 1; i >= 0; i--) {
            const r = rows.get(i);
            if (live.indexOf(r.iid) === -1 && !r.leaving) {
                rows.setProperty(i, "leaving", true);
                reap.restart();
            }
        }
        const have = {};
        for (let i = 0; i < rows.count; i++) have[rows.get(i).iid] = true;
        for (const id of live) if (!have[id]) rows.append({ iid: id, leaving: false, fresh: freshIds[id] === true });
        if (Shelf.count < 2) ctl.fan = false;
    }
    Timer {
        id: reap
        interval: 300
        onTriggered: { for (let i = rows.count - 1; i >= 0; i--) if (rows.get(i).leaving) rows.remove(i); }
    }
    Connections {
        target: Shelf
        function onItemsChanged() { panel.sync(); }
        function onAdded(ids) { const f = Object.assign({}, panel.freshIds); for (const id of ids) f[id] = true; panel.freshIds = f; freshClear.restart(); }
    }
    Timer { id: freshClear; interval: 1500; onTriggered: panel.freshIds = ({}) }
    Component.onCompleted: sync()

    // ---- drag-out payload: one item, or the whole pile ----
    function payloadFor(id) {
        const its = mode === "pile" ? Shelf.items.filter(it => !Shelf.isMissing(it)) : [Shelf.find(id)].filter(it => it);
        return { ids: its.map(it => it.id), mime: mimeFor(its) };
    }
    function mimeFor(its) {
        if (its.length === 1 && its[0].kind === "text") return { "text/plain": its[0].text ?? "" };
        if (its.length === 1 && its[0].kind === "link") return { "text/uri-list": its[0].url + "\r\n", "text/plain": its[0].url };
        return { "text/uri-list": its.map(it => Shelf.uriFor(it)).join("\r\n") + "\r\n" };
    }
}

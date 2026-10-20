pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.core
import qs.components
import qs.services

// One parked item (mock .dsh-it): thumbnail, name, type · size, time left, × on hover.
// Laid out by ShelfPanel: solo (one card), pile (tilted stack, the top card drags the whole pile)
// or fan (a list). Dragging starts a real Wayland drag (Drag.Automatic) with the payload the panel
// hands over in `payload()`; dragEnded reports Qt's drop action (see ShelfView.outEnded).
Item {
    id: card
    required property string itemId
    required property int order          // 0 = top of the pile / first row
    // a copy of the item, kept while the card plays its exit after the item is gone from the store
    property var item: ({})
    readonly property var live: Shelf.find(itemId)
    onLiveChanged: if (live) item = live
    property string mode: "solo"         // solo | pile | fan
    property int count: 1
    property bool leaving: false
    property bool fresh: false
    property bool lifted: false          // its drag is in flight (dimmed in place)
    property Item grabTarget: thumb      // what the drag image is made of (the panel: the whole pile)
    property var payload: () => ({ ids: [itemId], mime: {} })
    readonly property bool missing: Shelf.isMissing(item)
    readonly property bool hovered: mouse.containsMouse && !leaving
    readonly property bool isTop: order === 0
    readonly property real leftMs: Shelf.leftMs(item)
    readonly property bool old: leftMs < 2 * 3600000
    readonly property bool fan: mode === "fan"
    readonly property bool pile: mode === "pile"
    signal removeRequested()
    signal openRequested()
    signal dragBegan(var ids)
    signal dragEnded(var ids, int dropAction)

    // pile offsets (mock P3) and the fan stride
    readonly property var pileAt: [[0, 0, 0], [8, -6, 6], [-7, -9, -6.5], [3, -12, 2.5]][Math.min(order, 3)]
    readonly property real restX: 12 + (pile ? pileAt[0] : 0)
    readonly property real restY: 12 + (pile ? pileAt[1] : fan ? order * 42 : 0)
    readonly property real restR: pile ? pileAt[2] : 0

    width: 124
    height: fan ? 30 : 106
    z: leaving ? 0 : count - order
    transformOrigin: Item.Center
    x: restX + (leaving ? 60 : 0)
    y: restY - 10 * (1 - enter)
    rotation: restR + (leaving ? 8 : 0) - 5 * (1 - enter)
    scale: 1 + 0.12 * (1 - enter)
    opacity: leaving ? 0 : pile && order > 3 ? 0 : 1
    property real enter: 1
    Behavior on x { NumberAnimation { duration: card.leaving ? 260 : 460; easing.type: Easing.BezierSpline; easing.bezierCurve: card.leaving ? Theme.curveEase : Theme.curveSheet } }
    Behavior on y { NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
    Behavior on rotation { NumberAnimation { duration: card.leaving ? 260 : 460; easing.type: Easing.BezierSpline; easing.bezierCurve: card.leaving ? Theme.curveEase : Theme.curveSheet } }
    Behavior on opacity { NumberAnimation { duration: card.leaving ? 240 : Theme.durFade } }
    Behavior on height { NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
    NumberAnimation on enter { id: enterAnim; running: false; from: 0; to: 1; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet }
    Component.onCompleted: {
        if (live) item = live;
        if (fresh) { enter = 0; enterAnim.start(); }
    }

    // ---- thumbnail (scaled down to a 52x30 chip in the fan) ----
    Item {
        id: thumbBox
        width: 124; height: 72
        scale: card.fan ? 0.42 : 1
        transformOrigin: Item.TopLeft
        Behavior on scale { NumberAnimation { duration: 460; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveSheet } }
        opacity: card.lifted ? 0.28 : card.missing ? 0.45 : card.old && !card.pile ? 0.72 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }

        RectangularShadow {
            anchors.fill: thumb
            radius: thumb.radius
            offset.y: card.hovered ? 10 : 6
            blur: card.hovered ? 26 : 18
            color: Theme.rgba("#000000", card.hovered ? 0.55 : 0.45)
            Behavior on blur { NumberAnimation { duration: Theme.durHover } }
        }
        RectangularShadow {
            anchors.fill: thumb
            radius: thumb.radius
            blur: 22
            color: Theme.rgba(Theme.t.color.accent, 0.3)
            opacity: card.hovered && !card.missing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
        }
        ShelfThumb {
            id: thumb
            item: card.item
            missing: card.missing
            layer.enabled: card.missing || card.lifted
            layer.effect: MultiEffect { saturation: -1 }
        }
        // non-top pile cards sit a little darker (mock brightness .8)
        Rectangle {
            anchors.fill: thumb
            radius: thumb.radius
            color: "#000000"
            opacity: card.pile && !card.isTop ? 0.22 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        }
        // the flash of a fresh card (mock dshIn brightness 1.5)
        Rectangle {
            anchors.fill: thumb
            radius: thumb.radius
            color: "#ffffff"
            opacity: 0.28 * (1 - card.enter)
        }
        // hover ring
        Rectangle {
            anchors.fill: thumb
            radius: thumb.radius
            color: "transparent"
            border.width: 1
            border.color: Theme.rgba(Theme.t.color.accent, 0.7)
            opacity: card.hovered && !card.missing ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durHover } }
        }
    }

    // ---- name + meta ----
    Text {
        id: nameText
        x: card.fan ? 60 : 0
        y: card.fan ? 1 : 79
        width: card.fan ? 64 : 124
        text: card.item.name ?? ""
        elide: Text.ElideRight
        font.family: Theme.square ? Theme.fontLabel : Theme.fontUi
        font.pointSize: card.fan ? 7.875 : Theme.square ? 7.875 : 8.625
        font.letterSpacing: Theme.square ? 0.2 : 0
        color: card.missing ? Theme.label3 : Theme.label
        opacity: card.pile && !card.isTop ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
    }
    Item {
        id: meta
        x: card.fan ? 60 : 0
        y: card.fan ? 17 : 97
        width: card.fan ? 64 : 124
        height: 9
        opacity: card.pile && !card.isTop ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Theme.durFade } }
        Text {
            visible: !card.fan
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - ttl.width - 6
            elide: Text.ElideRight
            text: card.missing ? "MISSING" : card.metaText()
            font.family: Theme.fontLabel; font.pixelSize: 9; font.weight: Font.Medium
            font.letterSpacing: 0.7
            color: card.missing ? Theme.accent : Theme.label3
        }
        Row {
            id: ttl
            x: card.fan ? 0 : parent.width - width
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            readonly property real frac: Math.max(0, Math.min(1, card.leftMs / Shelf.ttlMs))
            readonly property color tint: card.old ? Theme.accent : Theme.label3
            // time-left bar (dot-matrix in the Telemetry look)
            Item {
                width: 15; height: 3
                anchors.verticalCenter: parent.verticalCenter
                Rectangle { visible: !Theme.dotMatrix; anchors.fill: parent; anchors.topMargin: 0.5; anchors.bottomMargin: 0.5; radius: 1; color: Theme.fill2 }
                Rectangle { visible: !Theme.dotMatrix; y: 0.5; height: 2; width: parent.width * ttl.frac; radius: 1; color: ttl.tint }
                Row {
                    visible: Theme.dotMatrix
                    spacing: 0.7
                    Repeater {
                        model: 6
                        Rectangle {
                            required property int index
                            width: 1.8; height: 1.8; radius: 0.9
                            y: 0.6
                            color: (index + 0.5) / 6 <= ttl.frac ? ttl.tint : Theme.fill2
                        }
                    }
                }
            }
            Text {
                text: card.ttlText()
                font.family: Theme.fontLabel; font.pixelSize: 9; font.weight: Font.Medium
                font.letterSpacing: 0.7
                color: ttl.tint
            }
        }
    }

    function sizeText(b) {
        if (b === undefined || b < 0) return "";
        if (b < 1024) return b + " B";
        const u = ["KB", "MB", "GB", "TB"];
        let v = b / 1024, i = 0;
        while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
        return (v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + u[i];
    }
    function metaText() {
        const it = item;
        if (it.kind === "text") return "TEXT · " + (it.bytes ?? 0) + " CH";
        if (it.kind === "link") return "LINK";
        if (it.kind === "dir") return "FOLDER";
        const e = Shelf.extOf(it.name ?? "").toUpperCase() || "FILE";
        const s = sizeText(it.bytes);
        return s ? e + " · " + s : e;
    }
    function ttlText() {
        const h = Math.max(1, Math.ceil(leftMs / 3600000));
        if (leftMs < 3600000) return Math.max(1, Math.ceil(leftMs / 60000)) + "M LEFT";
        return old ? h + "H LEFT" : h + "H";
    }

    // ---- input: hover, double click = open, drag = a real Wayland drag ----
    Item {
        id: proxy
        width: 1; height: 1
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.proposedAction: Qt.CopyAction
        Drag.active: mouse.drag.active
        property var ids: []
        Drag.onDragStarted: { card.lifted = true; card.dragBegan(proxy.ids); }
        Drag.onDragFinished: dropAction => {
            card.lifted = false;
            proxy.x = 0; proxy.y = 0;
            card.dragEnded(proxy.ids, dropAction);
        }
    }
    MouseArea {
        id: mouse
        x: 0; y: 0
        width: card.width
        height: card.fan ? 30 : 106
        hoverEnabled: true
        enabled: !card.leaving && (!card.pile || card.isTop)
        cursorShape: card.missing ? Qt.ArrowCursor : drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        drag.target: card.missing ? null : proxy
        drag.threshold: 5
        onPressed: ev => {
            if (card.missing) return;
            const p = card.payload();
            proxy.ids = p.ids;
            proxy.Drag.mimeData = p.mime;
            const g = card.grabTarget ?? thumb;
            // the pointer keeps its spot on a single thumb; the pile ghost hangs from its middle
            const at = g === thumb ? mouse.mapToItem(g, ev.x, ev.y) : Qt.point(g.width / 2, 44);
            proxy.Drag.hotSpot.x = Math.max(0, Math.min(g.width, at.x));
            proxy.Drag.hotSpot.y = Math.max(0, Math.min(g.height, at.y));
            g.grabToImage(r => { proxy.Drag.imageSource = r.url; });
        }
        onReleased: { proxy.x = 0; proxy.y = 0; }
        onDoubleClicked: if (!card.missing) card.openRequested()
    }

    // × (mock .dsh-x): on hover, not on pile cards
    Rectangle {
        x: card.fan ? card.width - 14 : 124 - 22
        y: card.fan ? 6 : 4
        z: 5
        width: 18; height: 18
        radius: Theme.square ? 2 : 9
        color: xMouse.containsMouse ? Theme.accent : Qt.rgba(0, 0, 0, 0.72)
        Behavior on color { ColorAnimation { duration: Theme.durHover } }
        visible: !card.pile
        opacity: (card.hovered || xMouse.containsMouse) && !card.lifted ? 1 : 0
        scale: opacity > 0.5 ? 1 : 0.7
        Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
        Behavior on scale { NumberAnimation { duration: Theme.durPop; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curveEase } }
        Glyph { anchors.centerIn: parent; name: "x"; size: 9; color: xMouse.containsMouse ? Theme.onAccent : "#ffffff"; strokeWidth: 2.4 }
        MouseArea { id: xMouse; anchors.fill: parent; anchors.margins: -3; hoverEnabled: true; enabled: parent.opacity > 0.5; onClicked: card.removeRequested() }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.core
import qs.modules.bar.widgets

// The island grown in place (hosted by Island.qml's PopupWindow, laid exactly over the bar pill):
// one black shape that is the bar pill's exact box at island.grow 0 and the card's at 1 (the
// spring overshoots a little). The pill face fades out as it grows, the card fades in after it;
// on the way back the face returns and the popup unmaps over the identical bar pill. The offscreen
// tests place one of these in their own window.
Item {
    id: root
    property Island island: null
    readonly property Item box: morph
    readonly property real gr: island?.grow ?? 0
    readonly property real grc: Math.max(0, Math.min(1, gr))
    readonly property real pillW: island?.width ?? 0
    readonly property real pillH: island?.pillH ?? 0
    readonly property real cardW: island?.cardWidth ?? 0
    readonly property real cardH: card.implicitHeight + 25
    readonly property bool square: Theme.square
    Binding { target: root.island; property: "cardH"; value: root.cardH; when: root.island !== null }

    RectangularShadow {
        anchors.fill: morph
        radius: morph.radius
        offset.y: 22; blur: 56; spread: -4
        color: Theme.rgba("#000000", 0.75)
        opacity: root.grc
    }
    Rectangle {
        id: morph
        width: root.pillW + (root.cardW - root.pillW) * root.gr
        height: root.pillH + (root.cardH - root.pillH) * root.gr
        x: (root.island?.pillPos.x ?? 0) - (root.island?.anchorX ?? 0) + (root.pillW - width) / 2
        y: root.island?.pillPos.y ?? 0
        radius: (root.island?.pillRadius ?? 0) + ((root.square ? 6 : 18) - (root.island?.pillRadius ?? 0)) * root.grc
        color: root.island?.islandColor ?? "black"
        border.width: 1
        border.color: Theme.white((root.square ? 0.16 : 0.12) + 0.04 * root.grc)
        clip: true
        HoverHandler { onHoveredChanged: root.island?.cardHover(hovered) }
        // a click on the card itself pins it
        TapHandler { onTapped: if (root.island) root.island.pinned = true }
        // the pill face, as the bar draws it (fades as the card grows)
        Item {
            readonly property real f: root.island?.faceFade ?? 0
            visible: f > 0.01
            opacity: f
            x: (morph.width - root.pillW) / 2
            width: root.pillW; height: root.pillH
            IslandPill {
                id: face
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                entry: root.island?.shown ?? null
                frame: root.island?.frame ?? 0
                maxText: root.island?.maxText ?? 150
            }
            IslandOthers {
                visible: count > 0
                x: 10 + face.implicitWidth + 3
                anchors.verticalCenter: parent.verticalCenter
                model: root.island?.extras ?? []
            }
        }
        IslandCard {
            id: card
            readonly property real f: root.island?.cardFade ?? 0
            visible: f > 0.01
            opacity: f
            x: 14; y: 13
            width: root.cardW - 28
            entry: root.island?.shown ?? null
            live: root.island?.live ?? []
            frame: root.island?.frame ?? 0
            micLevels: root.island?.micLevels ?? []
            onActed: close => { if (close) root.island?.hideCard(); }
            onPick: kind => root.island?.pick(kind)
        }
        // Telemetry: the accent corner bracket of an open panel
        Item {
            visible: root.square
            opacity: root.island?.cardFade ?? 0
            width: 10; height: 10
            Rectangle { width: 10; height: 1.5; color: Theme.accent }
            Rectangle { width: 1.5; height: 10; color: Theme.accent }
        }
    }
}

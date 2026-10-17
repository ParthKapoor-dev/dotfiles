pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris
import qs.core
import qs.components

// Now playing (mock .np + .prog). Hidden when no player. Position refreshes once a second only
// while the Control Center is open and the track plays.
Card {
    id: root
    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => p.isPlaying) ?? players[0] ?? null
    property bool shown: player !== null
    implicitHeight: 44 + 9 + (Theme.dotMatrix ? 8 : 3) + 20

    Timer {
        running: root.visible && (root.player?.isPlaying ?? false) && Panels.popup === "controlCenter"
        interval: 1000; repeat: true
        onTriggered: root.player?.positionChanged()
    }
    Item {
        id: np
        width: parent.width; height: 44
        Rectangle {
            id: art
            width: 44; height: 44; radius: Theme.square ? 3 : 8
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: "#ff8d4f" }
                GradientStop { position: 1; color: "#7a2cff" }
            }
            clip: true
            Image {
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 88; sourceSize.height: 88
            }
        }
        Column {
            anchors.left: art.right; anchors.leftMargin: 10
            anchors.right: ctl.left; anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            GText { width: parent.width; text: root.player?.trackTitle || root.player?.identity || ""; font.pixelSize: 13; font.weight: Font.DemiBold }
            GText { width: parent.width; text: root.player?.trackArtist ?? ""; small: true; secondary: true }
        }
        Row {
            id: ctl
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Repeater {
                model: [
                    { g: "prev", act: () => root.player?.previous(), ok: root.player?.canGoPrevious ?? false },
                    { g: root.player?.isPlaying ? "pause" : "play", act: () => root.player?.togglePlaying(), ok: root.player?.canTogglePlaying ?? false },
                    { g: "next", act: () => root.player?.next(), ok: root.player?.canGoNext ?? false }
                ]
                Rectangle {
                    required property var modelData
                    width: 28; height: 28; radius: Theme.square ? 3 : 14
                    color: cm.containsMouse ? Theme.fill2 : "transparent"
                    opacity: modelData.ok ? 1 : 0.35
                    Glyph { anchors.centerIn: parent; name: parent.modelData.g; size: 15 }
                    MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; enabled: parent.modelData.ok; onClicked: parent.modelData.act() }
                }
            }
        }
    }
    readonly property real progress: (root.player?.length ?? 0) > 0 ? Math.max(0, Math.min(1, root.player.position / root.player.length)) : 0
    Rectangle {
        visible: !Theme.dotMatrix
        anchors.top: np.bottom; anchors.topMargin: 6
        width: parent.width; height: 3; radius: 2
        color: Theme.white(0.18)
        Rectangle { width: parent.width * root.progress; height: parent.height; radius: 2; color: Theme.white(0.85) }
    }
    DotMeter {
        visible: Theme.dotMatrix
        style: "bars"
        anchors.top: np.bottom; anchors.topMargin: 6
        width: parent.width; height: 8
        value: root.progress
    }
}

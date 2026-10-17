import QtQuick
import Quickshell.Services.Mpris
import qs.core
import qs.components

// Now playing (MPRIS). Hidden when no player.
Card {
    id: root
    readonly property var players: Mpris.players.values
    readonly property var player: players.find(p => p.isPlaying) ?? players[0] ?? null
    property bool shown: player !== null
    implicitHeight: 64

    Rectangle {
        id: art
        width: 44; height: 44; radius: 8
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.fill2
        clip: true
        Image {
            anchors.fill: parent
            source: root.player?.trackArtUrl ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: 88; sourceSize.height: 88
        }
        GIcon { anchors.centerIn: parent; visible: !(root.player?.trackArtUrl); name: "music_note"; color: Theme.label2 }
    }
    Column {
        anchors.left: art.right; anchors.leftMargin: 10
        anchors.right: ctl.left; anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        GText { width: parent.width; text: root.player?.trackTitle || root.player?.identity || ""; font.weight: Font.DemiBold }
        GText { width: parent.width; text: root.player?.trackArtist ?? ""; small: true; secondary: true }
    }
    Row {
        id: ctl
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
            model: [
                { icon: "skip_previous", act: () => root.player?.previous(), ok: root.player?.canGoPrevious ?? false },
                { icon: root.player?.isPlaying ? "pause" : "play_arrow", act: () => root.player?.togglePlaying(), ok: root.player?.canTogglePlaying ?? false },
                { icon: "skip_next", act: () => root.player?.next(), ok: root.player?.canGoNext ?? false }
            ]
            Item {
                required property var modelData
                width: 28; height: 28
                opacity: modelData.ok ? 1 : 0.35
                GIcon { anchors.centerIn: parent; name: parent.modelData.icon; filled: true; size: 20 }
                MouseArea { anchors.fill: parent; enabled: parent.modelData.ok; onClicked: parent.modelData.act() }
            }
        }
    }
}

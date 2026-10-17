pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Default output + input via native PipeWire bindings (no pactl/wpctl processes).
Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink?.ready ?? false
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property string sinkName: sink ? (sink.description || sink.nickname || sink.name) : ""
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)

    // default input (microphone)
    readonly property PwNode source: Pipewire.defaultAudioSource
    readonly property bool micReady: source?.ready ?? false
    readonly property bool micMuted: source?.audio?.muted ?? false
    function toggleMic() { if (micReady) source.audio.muted = !source.audio.muted; }

    readonly property string icon: (!ready || muted) ? "volume_off" : volume < 0.01 ? "volume_mute" : volume < 0.5 ? "volume_down" : "volume_up"

    function setVolume(v) {
        if (!ready) return;
        sink.audio.muted = false;
        sink.audio.volume = Math.max(0, Math.min(1, v));
    }
    function toggleMute() { if (ready) sink.audio.muted = !sink.audio.muted; }
    function setSink(node) { Pipewire.preferredDefaultAudioSink = node; }
    function nodeName(n) { return n.description || n.nickname || n.name; }

    PwObjectTracker { objects: [root.sink, root.source].filter(n => !!n) }
}

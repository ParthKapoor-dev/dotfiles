import QtQuick
import Quickshell
import qs.core

// The orb that marks an agent's state. Uses the Orbkit shader orb set in shell.json
// notch.orb (modules/notch/orbs, ported shaders) when it is there, else OrbLite (plain shapes).
//   mode: work | need | done | idle | watch  ->  shader state thinking | speaking | idle | idle | thinking
// "need" is tinted red (notch.needTint) so it reads as waiting at 16 px.
Item {
    id: o
    property string mode: "work"
    property real size: 16
    property bool animate: true
    property int fps: Config.opt.notch?.orbFps ?? 12
    readonly property string orbName: Config.opt.notch?.orb ?? "lite"
    readonly property url shaderOrb: Qt.resolvedUrl("orbs/Orb.qml")
    implicitWidth: size
    implicitHeight: size
    Loader {
        id: shader
        anchors.centerIn: parent
        active: o.orbName !== "lite"
        source: active ? o.shaderOrb : ""
        onLoaded: {
            item.orb = Qt.binding(() => o.orbName);
            item.size = Qt.binding(() => o.size);
            if ("fps" in item) item.fps = Qt.binding(() => o.fps);
            item.orbState = Qt.binding(() => o.mode === "need" ? "speaking" : (o.mode === "work" || o.mode === "watch") ? "thinking" : "idle");
            item.running = Qt.binding(() => o.animate && o.visible && o.mode !== "idle");
            if ("tint" in item)
                item.tint = Qt.binding(() => o.mode === "need" ? (Config.opt.notch?.needTint ?? "#FF453A") : o.mode === "idle" ? "#5A5450" : "transparent");
        }
    }
    // the fallback; its animations must stop while hidden (a running animation, even on an
    // invisible item, makes Qt redraw the whole bar every frame)
    OrbLite {
        anchors.centerIn: parent
        visible: shader.status !== Loader.Ready
        size: o.size
        mode: o.mode
        animate: o.animate && visible && o.visible
    }
}

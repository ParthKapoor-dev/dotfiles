pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs.modules.bar.widgets

// One face of the island pill (Island.qml keeps two: the front one and the one leaving).
// enter() / leave() cross-fade with blur + scale (design mock .isl-l.enter / .leave).
Item {
    id: slot
    property IslandEntry entry: null
    property real pillH: 20
    property real maxText: 150
    property int frame: 0                // Island's loop clock (0 under the grown card: still)
    property real blurAmt: 0
    x: 10
    width: face.implicitWidth
    height: pillH
    implicitWidth: face.implicitWidth
    visible: entry !== null
    transformOrigin: Item.Center
    // the blur needs a GPU scene graph (the software one would draw nothing): plain fade there
    layer.enabled: blurAmt > 0.01 && GraphicsInfo.api !== GraphicsInfo.Software
    layer.effect: MultiEffect { blurEnabled: true; blur: slot.blurAmt; blurMax: 10 }
    IslandPill {
        id: face
        anchors.verticalCenter: parent.verticalCenter
        entry: slot.entry
        frame: slot.frame
        maxText: slot.maxText
    }
    function still() { ain.stop(); aout.stop(); opacity = 1; scale = 1; blurAmt = 0; }
    function enter() { aout.stop(); opacity = 0; scale = 0.9; blurAmt = 1; ain.restart(); }
    function leave() { ain.stop(); aout.restart(); }
    ParallelAnimation {
        id: ain
        NumberAnimation { target: slot; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: slot; property: "blurAmt"; to: 0; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: slot; property: "scale"; to: 1; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
    }
    ParallelAnimation {
        id: aout
        NumberAnimation { target: slot; property: "opacity"; to: 0; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: slot; property: "blurAmt"; to: 1; duration: 240; easing.type: Easing.OutCubic }
        NumberAnimation { target: slot; property: "scale"; to: 1.08; duration: 240; easing.type: Easing.OutCubic }
        onFinished: { slot.entry = null; slot.still(); }
    }
}

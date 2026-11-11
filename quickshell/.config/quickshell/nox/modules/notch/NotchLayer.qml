import QtQuick

// One of the notch's contents (compact line, request card, done card, panel): fades out at once
// when the notch leaves it and fades in a beat after the body has started to morph into it.
Item {
    id: nl
    property bool on: false
    opacity: 0
    visible: opacity > 0.01
    enabled: on
    onOnChanged: {
        fade.stop();
        fade.delay = on ? 120 : 0;
        fade.to = on ? 1 : 0;
        fade.dur = on ? 260 : 100;
        fade.start();
    }
    Component.onCompleted: if (on) opacity = 1
    SequentialAnimation {
        id: fade
        property int delay: 0
        property real to: 1
        property int dur: 200
        PauseAnimation { duration: fade.delay }
        NumberAnimation { target: nl; property: "opacity"; to: fade.to; duration: fade.dur; easing.type: Easing.OutCubic }
    }
}

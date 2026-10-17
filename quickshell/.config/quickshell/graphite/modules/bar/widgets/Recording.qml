import QtQuick
import qs.core
import qs.components
import qs.services

// mock .mbi.rec: red square + elapsed time while recording; click stops.
BarButton {
    id: root
    property string widgetId: "recording"
    property real now: Date.now()
    visible: Recorder.recording
    spacing: 5
    onClicked: Recorder.stop()
    Timer { running: Recorder.recording; interval: 1000; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() }
    Rectangle { width: 9; height: 9; radius: 2; color: Theme.red; anchors.verticalCenter: parent.verticalCenter }
    GText {
        anchors.verticalCenter: parent.verticalCenter
        readonly property int s: Math.max(0, Math.floor((root.now - Recorder.startedAt) / 1000))
        text: Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0")
        color: "white"
        font.features: ({ "tnum": 1 })
    }
}

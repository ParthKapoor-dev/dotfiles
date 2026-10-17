pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import qs.core
import qs.components

// Polkit authentication agent + dialog (namespace graphite:polkit). Only one agent can register
// per session: while another one (e.g. ii) holds it, `registered` stays false; after that agent
// exits, `qs -c graphite ipc call polkit retry` (or a shell restart) registers graphite's.
// Dialog: dimmed screen, glass sheet with key glyph, the action message, password field
// (Enter = OK, Esc = Cancel), wrong-password shake, Cancel / Authenticate buttons.
Scope {
    id: root
    property bool agentOn: true
    readonly property var agent: loader.item
    readonly property var flow: agent?.flow ?? null
    readonly property bool active: agent?.isActive ?? false
    readonly property bool registered: agent?.isRegistered ?? false
    property bool busy: false
    property string error: ""

    function retry() { agentOn = false; Qt.callLater(() => { root.agentOn = true; }); }
    function cancel() { flow?.cancelAuthenticationRequest(); }
    function submit(text) { if (!flow) return; busy = true; error = ""; flow.submit(text); }

    LazyLoader {
        id: loader
        active: root.agentOn
        PolkitAgent {
            onAuthenticationRequestStarted: { root.busy = false; root.error = ""; }
        }
    }
    Connections {
        target: root.flow
        function onAuthenticationFailed() { root.busy = false; root.error = "Wrong password. Try again."; }
        function onIsResponseRequiredChanged() { if (root.flow?.isResponseRequired) root.busy = false; }
    }

    LazyLoader {
        active: root.active
        PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null
            color: "transparent"
            WlrLayershell.namespace: "graphite:polkit"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; bottom: true; left: true; right: true }

            Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.45) }

            RectangularShadow {
                anchors.fill: sheet; radius: sheet.radius
                offset.y: 24; blur: 64; spread: -8
                color: Qt.rgba(0, 0, 0, 0.6)
            }
            Glass {
                id: sheet
                menu: true
                anchors.centerIn: parent
                width: 380
                height: col.implicitHeight + 40
                radius: Theme.square ? 6 : 16
                transform: Translate { id: shake; x: 0 }
                SequentialAnimation {
                    id: shakeAnim
                    NumberAnimation { target: shake; property: "x"; to: -8; duration: 60 }
                    NumberAnimation { target: shake; property: "x"; to: 8; duration: 90 }
                    NumberAnimation { target: shake; property: "x"; to: -6; duration: 90 }
                    NumberAnimation { target: shake; property: "x"; to: 0; duration: 80 }
                }
                Connections { target: root; function onErrorChanged() { if (root.error) { shakeAnim.restart(); pw.text = ""; } } }

                Column {
                    id: col
                    x: 24; y: 22; width: parent.width - 48
                    spacing: 12
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 56; height: 56; radius: Theme.square ? 6 : 14
                        color: Theme.fill2
                        Glyph { anchors.centerIn: parent; name: "key"; size: 28 }
                    }
                    GText {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: "Authentication Required"
                        font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    GText {
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: (root.flow?.message ?? "").replace(/\.$/, "")
                        wrapMode: Text.Wrap; maximumLineCount: 4
                        secondary: true
                    }
                    GText {
                        visible: text !== ""
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: root.error || (root.flow?.supplementaryMessage ?? "")
                        color: root.error || root.flow?.supplementaryIsError ? Theme.red : Theme.label2
                        wrapMode: Text.Wrap; small: true
                    }
                    GText {
                        visible: (root.flow?.selectedIdentity?.displayName ?? "") !== ""
                        width: parent.width; horizontalAlignment: Text.AlignHCenter
                        text: "as " + (root.flow?.selectedIdentity?.displayName ?? "")
                        small: true; secondary: true
                    }
                    Rectangle {
                        width: parent.width; height: 32
                        radius: Theme.square ? 3 : 8
                        color: Qt.rgba(0, 0, 0, 0.3)
                        border.width: 1
                        border.color: pw.activeFocus ? Theme.rgba(Theme.t.color.accent, 0.8) : Theme.hair
                        TextInput {
                            id: pw
                            anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: root.flow?.responseVisible ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "•"
                            color: Theme.label
                            font.family: Theme.fontUi; font.pixelSize: Theme.fontSize
                            enabled: !root.busy
                            focus: true
                            Component.onCompleted: forceActiveFocus()
                            Keys.onReturnPressed: { root.submit(text); }
                            Keys.onEnterPressed: { root.submit(text); }
                            Keys.onEscapePressed: root.cancel()
                            GText {
                                visible: pw.text === ""
                                anchors.verticalCenter: parent.verticalCenter
                                text: (root.flow?.inputPrompt ?? "").trim().replace(/:$/, "") || "Password"
                                color: Theme.label3
                            }
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        spacing: 8
                        PillButton { text: "Cancel"; implicitHeight: 28; implicitWidth: 92; onClicked: root.cancel() }
                        PillButton { text: root.busy ? "Checking…" : "Authenticate"; on: true; implicitHeight: 28; implicitWidth: 112; onClicked: root.submit(pw.text) }
                    }
                }
            }
        }
    }

    // qs -c graphite ipc call polkit status | retry
    IpcHandler {
        target: "polkit"
        function status(): string { return "registered=" + root.registered + " active=" + root.active; }
        function retry(): void { root.retry(); }
    }
}

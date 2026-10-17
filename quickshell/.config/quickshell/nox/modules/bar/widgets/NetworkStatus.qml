pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Networking as NM
import qs.core
import qs.components
import qs.services

// Wi-Fi / wired status + Wi-Fi popover (mock Pops.wifi). Scans only while the popover is open.
// Click a network: connected -> shows Disconnect / Forget; known -> connects; open -> connects;
// secured & new -> inline password field (masked, eye toggle, Enter connects, Esc cancels).
// Right click a known network: Connect / Forget. Progress and errors show under the name.
BarButton {
    id: root
    property string widgetId: "network"
    readonly property var options: Config.widget(widgetId)
    readonly property string popupId: "bar:" + widgetId
    hpad: 7
    active: Panels.popup === popupId
    onClicked: Panels.toggle(popupId)
    onActiveChanged: { Network.setScanning(active); if (!active) { expanded = ""; errors = ({}); } }

    property string expanded: ""        // SSID whose inline panel is open
    property string expandMode: ""      // "password" | "actions"
    property var errors: ({})           // SSID -> message
    function setError(name, msg) { const e = Object.assign({}, errors); if (msg) e[name] = msg; else delete e[name]; errors = e; }

    Glyph { name: Network.glyph; anchors.verticalCenter: parent.verticalCenter }

    component WifiRow: ListRow {
        id: row
        required property var modelData
        readonly property var net: modelData
        readonly property bool open: root.expanded === net.name
        readonly property bool busy: net.stateChanging || net.state === NM.ConnectionState.Connecting
        width: parent?.width ?? 260
        icon: Network.glyphFor(net)
        on: net.connected
        title: net.name
        subtitle: busy ? (net.state === NM.ConnectionState.Disconnecting ? "Disconnecting…" : "Connecting…")
                  : (root.errors[net.name] ?? "")
        subtitleColor: root.errors[net.name] && !busy ? Theme.red : Theme.label2
        trailingIcon: Network.secured(net) ? "lock" : ""
        onClicked: {
            root.setError(net.name, "");
            if (net.connected) { root.toggleExpand(net.name, "actions"); return; }
            if (net.known || !Network.secured(net)) { root.expanded = ""; net.connect(); return; }
            if (Network.needsPsk(net)) { root.toggleExpand(net.name, "password"); return; }
            root.setError(net.name, "Enterprise networks: use Network Settings");
        }
        onRightClicked: if (net.known || net.connected) root.toggleExpand(net.name, "actions")
        Connections {
            target: row.net
            function onConnectionFailed(reason) {
                root.setError(row.net.name, Network.failText(reason));
                if (reason === NM.ConnectionFailReason.NoSecrets && Network.needsPsk(row.net)) { root.expanded = row.net.name; root.expandMode = "password"; }
            }
            function onConnectedChanged() { if (row.net.connected) { root.setError(row.net.name, ""); if (root.expandMode === "password") root.expanded = ""; } }
        }

        // inline password field (mock-style input: fill2 pill, 1px accent ring while focused)
        Item {
            visible: row.open && root.expandMode === "password"
            width: row.width; height: visible ? 40 : 0
            Rectangle {
                id: field
                x: 46; y: 2; width: parent.width - 46 - 10; height: 30
                radius: Theme.square ? 3 : 8
                color: Qt.rgba(0, 0, 0, 0.3)
                border.width: 1
                border.color: pw.activeFocus ? Theme.rgba(Theme.t.color.accent, 0.8) : Theme.hair
                TextInput {
                    id: pw
                    anchors.left: parent.left; anchors.leftMargin: 10
                    anchors.right: eye.left; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    echoMode: showPw.checked ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: Theme.label
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.onAccent
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fontSize
                    clip: true
                    onVisibleChanged: if (visible) { text = ""; forceActiveFocus(); }
                    Keys.onReturnPressed: submit()
                    Keys.onEnterPressed: submit()
                    Keys.onEscapePressed: root.expanded = ""
                    function submit() {
                        if (text.length < 8) { root.setError(row.net.name, "Password must be at least 8 characters"); return; }
                        root.setError(row.net.name, "");
                        row.net.connectWithPsk(text);
                        text = "";
                    }
                    GText { visible: pw.text === ""; text: "Password"; color: Theme.label3; anchors.verticalCenter: parent.verticalCenter }
                }
                Item {
                    id: eye
                    anchors.right: go.left; anchors.rightMargin: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24
                    Glyph { anchors.centerIn: parent; name: showPw.checked ? "eyeOff" : "eye"; size: 15; color: Theme.label2 }
                    MouseArea { id: showPw; property bool checked: false; anchors.fill: parent; onClicked: checked = !checked }
                }
                Rectangle {
                    id: go
                    anchors.right: parent.right; anchors.rightMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 24; radius: Theme.square ? 3 : 12
                    color: pw.text.length >= 8 ? Theme.accent : Theme.fill2
                    Glyph { anchors.centerIn: parent; name: "arrowR"; size: 13; color: pw.text.length >= 8 ? Theme.onAccent : Theme.label2 }
                    MouseArea { anchors.fill: parent; onClicked: pw.submit() }
                }
            }
        }
        // inline actions (connected / known)
        Item {
            visible: row.open && root.expandMode === "actions"
            width: row.width; height: visible ? 32 : 0
            Row {
                x: 46; y: 2
                spacing: 6
                PillButton {
                    text: row.net.connected ? "Disconnect" : "Connect"
                    onClicked: { root.expanded = ""; row.net.connected ? row.net.disconnect() : row.net.connect(); }
                }
                PillButton {
                    visible: row.net.known
                    text: "Forget"
                    onClicked: { root.expanded = ""; row.net.forget(); }
                }
            }
        }
    }
    function toggleExpand(name, mode) {
        if (expanded === name && expandMode === mode) { expanded = ""; return; }
        expandMode = mode; expanded = name;
    }

    GPopup {
        popupId: root.popupId
        anchorItem: root
        align: "itemRight"
        content: Column {
            // no Wi-Fi hardware (desktop, rfkill'd card that vanished): no switch, no "Searching…"
            readonly property bool hasWifi: Network.wifiDevice !== null
            readonly property bool wifiOn: hasWifi && Network.wifiEnabled
            PopHeader {
                width: parent.width; title: parent.hasWifi ? "Wi-Fi" : "Network"
                showSwitch: parent.hasWifi; checked: Network.wifiEnabled
                onToggled: Network.setWifi(!Network.wifiEnabled)
            }
            ListRow {
                visible: Network.wired
                width: parent.width
                icon: "lan"; title: "Ethernet"; subtitle: "Connected"; on: true
            }
            SectionLabel { visible: parent.hasWifi && !Network.wifiEnabled; text: "Wi-Fi is off"; bottomPadding: 10 }
            SectionLabel { visible: !parent.hasWifi && !Network.wired; text: "No network adapter"; bottomPadding: 10 }
            SectionLabel { visible: !parent.hasWifi && Network.wired; text: "No Wi-Fi adapter"; bottomPadding: 10 }
            SectionLabel { visible: parent.wifiOn && Network.knownList.length > 0; text: Network.knownList.length > 1 ? "Known Networks" : "Known Network" }
            Repeater { model: parent.wifiOn ? Network.knownList : []; WifiRow {} }
            SectionLabel { visible: parent.wifiOn && Network.otherList.length > 0; text: "Other Networks" }
            Repeater { model: parent.wifiOn ? Network.otherList.slice(0, root.options.maxOther ?? 8) : []; WifiRow {} }
            SectionLabel { visible: parent.wifiOn && Network.unique.length === 0; text: "Searching…"; bottomPadding: 8 }
            MenuSep { width: parent.width; visible: settings.visible }
            MenuRow {
                id: settings
                visible: (root.options.settingsCommand ?? []).length > 0
                width: parent.width
                text: "Wi-Fi Settings…"
                onTriggered: { Panels.close(); Quickshell.execDetached(root.options.settingsCommand); }
            }
        }
    }
}

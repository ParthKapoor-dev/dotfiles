pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.core
import qs.services

// One notification (mock .nt): 32px app icon, bold summary + time on one line, body (2 lines in
// banners, 5 in the center), optional image thumbnail and action pills. Click = default action;
// middle click or the hover × (top-left, mock .nt .x) dismisses.
// `card: true` draws its own glass card (banners); false = row inside a group card (center).
Item {
    id: root
    required property var notification
    property bool compact: true
    property bool card: true
    readonly property var n: notification
    signal closeRequested()

    implicitHeight: body.implicitHeight + (card ? 24 : 0)
    readonly property real padX: card ? 14 : 0
    readonly property real padY: card ? 12 : 0

    readonly property string iconSource: {
        const ic = n?.appIcon || DesktopEntries.byId(n?.desktopEntry ?? "")?.icon || DesktopEntries.heuristicLookup(n?.appName ?? "")?.icon || "";
        if (!ic) return "";
        if (ic.startsWith("/") || ic.includes("://")) return ic.startsWith("/") ? "file://" + ic : ic;
        return Quickshell.iconPath(ic, true);
    }
    readonly property var buttons: (n?.actions ?? []).filter(a => a.identifier !== "default" && a.text)

    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: !root.compact }
    function when() {
        const t = Notifs.timeOf(n);
        const mins = Math.floor(((root.compact ? Date.now() : clock.date.getTime()) - t) / 60000);
        if (root.compact && mins < 1) return "now";
        return Qt.formatDateTime(new Date(t), mins < 1440 ? "HH:mm" : "d MMM");
    }

    Glass {
        visible: root.card
        anchors.fill: parent
        menu: true
        radius: Theme.square ? 6 : 16
    }
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: m => { if (m.button === Qt.MiddleButton) root.closeRequested(); else Notifs.activate(root.n); }
    }

    Row {
        id: body
        x: root.padX; y: root.padY
        width: parent.width - root.padX * 2
        spacing: 10

        Item {
            width: 32; height: 32
            y: 1
            IconImage {
                id: appIcon
                anchors.fill: parent
                source: root.iconSource
                visible: root.iconSource !== "" && status === Image.Ready
                asynchronous: true
            }
            Rectangle {
                anchors.fill: parent
                visible: !appIcon.visible
                radius: Theme.square ? 4 : 8
                color: Theme.fill2
                Glyph { anchors.centerIn: parent; name: "bell"; size: 17; color: Theme.label2 }
            }
        }

        Column {
            width: body.width - 42 - (thumb.visible ? thumb.width + 10 : 0)
            spacing: 2
            Item {
                width: parent.width; height: summary.implicitHeight
                GText {
                    id: summary
                    width: parent.width - whenText.implicitWidth - 8
                    text: root.n?.summary || root.n?.appName || ""
                    font.weight: Font.DemiBold
                }
                GText { id: whenText; anchors.right: parent.right; anchors.baseline: summary.baseline; text: root.when(); small: true; secondary: true }
            }
            GText {
                width: parent.width
                visible: text !== ""
                text: root.n?.body ?? ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: root.compact ? 2 : 5
                elide: Text.ElideRight
                verticalAlignment: Text.AlignTop
                lineHeight: 1.05
            }
            Flow {
                visible: root.buttons.length > 0
                width: parent.width
                spacing: 6
                topPadding: 6
                Repeater {
                    model: root.buttons
                    PillButton {
                        required property var modelData
                        text: modelData.text
                        onClicked: { modelData.invoke(); Notifs.hidePopup(root.n); }
                    }
                }
            }
        }

        Image {
            id: thumb
            visible: (root.n?.image ?? "") !== "" && status === Image.Ready
            width: 40; height: 40
            source: root.n?.image ?? ""
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 80; sourceSize.height: 80
            asynchronous: true
        }
    }

    // close button (mock .nt .x: 20px round glass at the top-left corner, on hover)
    Rectangle {
        x: root.card ? -6 : -20; y: root.card ? -6 : -16
        width: 20; height: 20
        color: Theme.rgba(Theme.t.color.glass, 0.95)
        radius: Theme.square ? 4 : 10
        border.width: Theme.rimWidth
        border.color: Theme.rim
        opacity: hover.containsMouse || closeMouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
        Glyph { anchors.centerIn: parent; name: "x"; size: 10; color: Theme.label }
        MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.closeRequested() }
    }
}

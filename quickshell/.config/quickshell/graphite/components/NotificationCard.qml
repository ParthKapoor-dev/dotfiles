pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import qs.core
import qs.services

// One notification (mock .card .nt): app icon, app name + time, bold summary, body, optional
// image, action buttons. Click = default action; hover shows a close button (dismisses it).
// Used by the popups (compact) and the Notification Center.
Rectangle {
    id: root
    required property var notification
    property bool compact: true           // popups: 2 body lines, center: 5
    property bool glass: true             // popups sit on the desktop: glass; in the center: card fill
    readonly property var n: notification
    signal closeRequested()

    implicitHeight: body.implicitHeight + 24
    radius: Theme.radiusPanel
    readonly property bool hairline: Theme.glassOpaque || (!glass && Theme.cardStyle === "hairline")
    color: glass ? Theme.glass : hairline ? "transparent" : Theme.fill
    border.width: hairline ? 1 : Theme.rimWidth
    border.color: hairline ? Theme.hair : glass ? Theme.rim : Theme.sep

    readonly property string iconSource: {
        const ic = n?.appIcon || DesktopEntries.byId(n?.desktopEntry ?? "")?.icon || "";
        if (!ic) return "";
        if (ic.startsWith("/") || ic.includes("://")) return ic.startsWith("/") ? "file://" + ic : ic;
        return Quickshell.iconPath(ic, true);
    }
    readonly property var buttons: (n?.actions ?? []).filter(a => a.identifier !== "default" && a.text)

    SystemClock { id: clock; precision: SystemClock.Minutes; enabled: !root.compact }
    function ago() {
        const mins = Math.floor(((root.compact ? Date.now() : clock.date.getTime()) - Notifs.timeOf(n)) / 60000);
        if (mins < 1) return "now";
        if (mins < 60) return mins + "m ago";
        if (mins < 1440) return Math.floor(mins / 60) + "h ago";
        return Qt.formatDateTime(new Date(Notifs.timeOf(n)), "d MMM");
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
        x: 14; y: 12
        width: parent.width - 28
        spacing: 10

        Item {
            width: 32; height: 32
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
                radius: 8
                color: Theme.fill2
                GIcon { anchors.centerIn: parent; name: "notifications"; size: 18; color: Theme.label2 }
            }
        }

        Column {
            width: body.width - 42 - (thumb.visible ? thumb.width + 10 : 0)
            spacing: 2
            Item {
                width: parent.width; height: summary.implicitHeight
                GText {
                    id: summary
                    width: parent.width - when.implicitWidth - 8
                    text: root.n?.summary || root.n?.appName || ""
                    font.weight: Font.DemiBold
                }
                GText { id: when; anchors.right: parent.right; anchors.baseline: summary.baseline; text: root.ago(); small: true; secondary: true }
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
            }
            GText {
                width: parent.width
                visible: (root.n?.summary ?? "") !== "" && (root.n?.appName ?? "") !== ""
                text: root.n?.appName ?? ""
                small: true; secondary: true
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

    // close button (mock .nt .x): top-left, on hover
    Rectangle {
        x: -6; y: -6
        width: 20; height: 20
        color: Theme.surface
        radius: Theme.radiusPanel >= 12 ? 10 : Theme.radiusControl
        border.width: Theme.rimWidth
        border.color: Theme.rim
        opacity: hover.containsMouse || closeMouse.containsMouse ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.durPop } }
        GIcon { anchors.centerIn: parent; name: "close"; size: 12; color: Theme.label2 }
        MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.closeRequested() }
    }
}

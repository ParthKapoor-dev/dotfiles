pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.core
import qs.components
import qs.services

// Notification Center (mock #nc): a 356px column at the right edge (bar+6 to 8px above the
// bottom) that slides in from the right. Header with Do Not Disturb + Clear All pills, then
// notifications grouped by app in glass cards, a month calendar and a batteries card
// (laptop + Bluetooth devices that report a level). Popup id "notifications" (clock click,
// `qs -c graphite ipc call notifications toggle`).
GPopup {
    id: nc
    readonly property var opts: Config.opt.notifications?.center ?? ({})
    popupId: "notifications"
    align: "right"
    popupWidth: opts.width ?? 356
    padding: 0
    bare: true
    fillHeight: true
    slide: "left"

    FileView { id: hostFile; path: "/etc/hostname"; blockLoading: true; printErrors: false }
    component CardShadow: RectangularShadow {
        radius: Theme.square ? 6 : 16
        offset.y: 10; blur: 30; spread: -4
        color: Theme.rgba("#000000", 0.3)
    }
    component GroupLabel: Item {
        property string leftText
        property string rightText
        id: gl
        width: parent?.width ?? 0; height: 14
        GText { width: gl.width - countText.implicitWidth - 8; text: gl.leftText; font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi; font.pixelSize: Theme.labelsMono ? 10 : 11; font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase; font.letterSpacing: Theme.labelsMono ? 0.8 : 0; font.weight: Theme.labelsMono ? Font.Medium : Font.DemiBold; color: Theme.label2 }
        GText { id: countText; anchors.right: parent.right; text: gl.rightText; font.family: Theme.labelsMono ? Theme.fontLabel : Theme.fontUi; font.pixelSize: Theme.labelsMono ? 10 : 11; font.capitalization: Theme.labelsMono ? Font.AllUppercase : Font.MixedCase; font.letterSpacing: Theme.labelsMono ? 0.8 : 0; color: Theme.label2 }
    }

    content: Flickable {
        id: flick
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        // notifications grouped by app, newest group first
        readonly property var groups: {
            const out = [], byApp = {};
            for (const n of Notifs.list) {
                const k = n.appName || n.desktopEntry || "Other";
                if (!byApp[k]) { byApp[k] = { app: k, list: [] }; out.push(byApp[k]); }
                byApp[k].list.push(n);
            }
            return out;
        }

        Column {
            id: col
            width: flick.width
            spacing: 10

            // header (mock .nc-h). The NC is floating cards on a transparent full-height layer, so
            // whatever is behind the header is an app window, not wallpaper: the mock's bare title
            // with a 4px text-shadow is unreadable on a light window. The title gets the same glass
            // capsule as the mock's .pillbtn pills next to it, so the whole row reads as three
            // pills and stays legible on any background.
            Item {
                width: parent.width; height: 28
                Rectangle {
                    id: titlePill
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    height: 28
                    width: Math.min(titleText.implicitWidth + 24, parent.width - pills.width - 8)
                    radius: Theme.square ? 4 : height / 2
                    color: Theme.menuGlass
                    border.width: Theme.glassOpaque ? 1 : Theme.rimWidth
                    border.color: Theme.glassOpaque ? Theme.hair : Theme.rim
                    GText {
                        id: titleText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, parent.width - 24)
                        text: "Notifications"; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                }
                Row {
                    id: pills
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    PillButton { icon: "moonF"; text: Notifs.dnd ? "Focus on" : "Do Not Disturb"; on: Notifs.dnd; onClicked: Notifs.toggleDnd() }
                    PillButton { visible: Notifs.count > 0; text: "Clear All"; onClicked: Notifs.clearAll() }
                }
            }

            // empty state
            Item {
                visible: Notifs.count === 0
                width: parent.width; height: 52
                CardShadow { anchors.fill: emptyCard }
                Glass {
                    id: emptyCard
                    anchors.fill: parent; menu: true; radius: Theme.square ? 6 : 16
                    GText { anchors.centerIn: parent; text: Notifs.running ? "No Notifications" : "Notifications are handled by another daemon"; secondary: true }
                }
            }

            Repeater {
                model: flick.groups
                Column {
                    id: grp
                    required property var modelData
                    width: col.width
                    spacing: 6
                    // group label (mock .grp) sits inside the card as its first row: outside it
                    // floated over app windows with no backing, like the header did
                    Item {
                        width: parent.width; height: gcol.implicitHeight + 24
                        CardShadow { anchors.fill: parent }
                        Glass { anchors.fill: parent; menu: true; radius: Theme.square ? 6 : 16 }
                        Column {
                            id: gcol
                            x: 14; y: 12; width: parent.width - 28
                            spacing: 12
                            GroupLabel {
                                width: gcol.width
                                leftText: grp.modelData.app
                                rightText: grp.modelData.list.length > 6 ? "6 of " + grp.modelData.list.length
                                    : grp.modelData.list.length > 1 ? grp.modelData.list.length + " notifications" : ""
                            }
                            Repeater {
                                model: grp.modelData.list.slice(0, 6)
                                Column {
                                    id: entry
                                    required property var modelData
                                    required property int index
                                    width: gcol.width
                                    spacing: 12
                                    Rectangle { visible: entry.index > 0; width: parent.width; height: 1; color: Theme.sep }
                                    NotificationCard {
                                        width: parent.width
                                        notification: entry.modelData
                                        compact: false
                                        card: false
                                        onCloseRequested: Notifs.dismiss(entry.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // calendar (mock .cal)
            Item {
                visible: nc.opts.calendar !== false
                width: parent.width; height: cal.implicitHeight + 24
                CardShadow { anchors.fill: parent }
                Glass { anchors.fill: parent; menu: true; radius: Theme.square ? 6 : 16 }
                Calendar { id: cal; x: 14; y: 12; width: parent.width - 28 }
            }

            // batteries (mock .batt rings)
            Item {
                id: batt
                readonly property var items: {
                    const out = [];
                    const d = UPower.displayDevice;
                    if (d?.isLaptopBattery) out.push({ glyph: "laptop", p: d.percentage, name: hostFile.text().trim() || "This laptop" });
                    for (const b of Bt.connected) if (b.batteryAvailable) out.push({ glyph: Bt.glyphFor(b), p: b.battery, name: Bt.nameOf(b) });
                    return out.slice(0, 3);
                }
                visible: nc.opts.batteries !== false && items.length > 0
                width: parent.width; height: 120
                CardShadow { anchors.fill: parent }
                Glass { anchors.fill: parent; menu: true; radius: Theme.square ? 6 : 16 }
                CardTitle { x: 14; y: 12; width: parent.width - 28; text: "Batteries" }
                Row {
                    x: 14; y: 38; width: parent.width - 28
                    Repeater {
                        model: batt.items
                        Column {
                            id: bi
                            required property var modelData
                            width: (batt.width - 28) / 3
                            spacing: 4
                            Ring { anchors.horizontalCenter: parent.horizontalCenter; value: bi.modelData.p; glyph: bi.modelData.glyph }
                            GText { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(bi.modelData.p * 100) + "%"; small: true; secondary: true; font.features: ({ "tnum": 1 }) }
                            GText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: bi.modelData.name; small: true; secondary: true }
                        }
                    }
                }
            }
        }
    }
}

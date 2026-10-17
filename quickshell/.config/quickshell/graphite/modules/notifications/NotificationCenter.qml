pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.core
import qs.components
import qs.services

// Notification Center (mock #nc): a 356px column at the right edge, 8px under the bar and 10px
// from the screen edge (the same column as the banners), that slides in from the right. A header
// card with Do Not Disturb + Clear All, then notifications grouped by app, a month calendar and a
// batteries card (laptop + Bluetooth devices that report a level). Every block is a card of the
// same width and glass (tokens glass.cardAlpha: near-opaque, so a saturated wallpaper blurred
// behind the layer can't tint them). Popup id "notifications" (clock click,
// `qs -c graphite ipc call notifications toggle`).
GPopup {
    id: nc
    readonly property var opts: Config.opt.notifications?.center ?? ({})
    popupId: "notifications"
    align: "right"
    popupWidth: opts.width ?? 356
    edge: 10
    gap: 8
    padding: 0
    bare: true
    fillHeight: true
    slide: "left"

    FileView { id: hostFile; path: "/etc/hostname"; blockLoading: true; printErrors: false }
    // one NC card: soft shadow + near-opaque glass; `inner` is the content box (14/12 padding)
    component NcCard: Item {
        id: card
        default property alias content: inner.data
        property real padY: 12
        width: parent?.width ?? 0
        implicitHeight: inner.childrenRect.height + padY * 2
        RectangularShadow {
            anchors.fill: parent
            radius: cardBg.radius
            offset.y: 8; blur: 24; spread: -6
            color: Theme.rgba("#000000", Theme.glassOpaque ? 0.45 : 0.32)
        }
        Glass { id: cardBg; anchors.fill: parent; menu: true; color: Theme.cardGlass; radius: Theme.square ? 6 : 16 }
        Item { id: inner; x: 14; y: card.padY; width: card.width - 28; height: childrenRect.height }
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
        // clipping cuts the cards' side shadows into hard vertical edges: only clip while the
        // column actually overflows and scrolls
        clip: contentHeight > height
        interactive: contentHeight > height
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

            // header (mock .nc-h). The mock's bare title + floating pills sit on wallpaper; here
            // the column floats over app windows, so the header is the column's first card: same
            // width and edges as the cards below, title at the cards' 14px text inset, the two
            // pills inside it on the right (flat fill pills, accent when DND is on).
            NcCard {
                padY: 0
                Item {
                    width: parent.width; height: 40
                    GText {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - pills.width - 10)
                        text: "Notifications"; font.pixelSize: 15; font.weight: Font.DemiBold
                    }
                    Row {
                        id: pills
                        anchors.right: parent.right; anchors.rightMargin: -6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        PillButton { flat: true; icon: "moonF"; text: Notifs.dnd ? "Focus on" : "Do Not Disturb"; on: Notifs.dnd; onClicked: Notifs.toggleDnd() }
                        PillButton { flat: true; visible: Notifs.count > 0; text: "Clear All"; onClicked: Notifs.clearAll() }
                    }
                }
            }

            // empty state
            NcCard {
                visible: Notifs.count === 0
                padY: 0
                Item {
                    width: parent.width; height: 52
                    GText { anchors.centerIn: parent; width: Math.min(implicitWidth, parent.width); text: Notifs.running ? "No Notifications" : "Notifications are handled by another daemon"; secondary: true }
                }
            }

            Repeater {
                model: flick.groups
                NcCard {
                    id: grp
                    required property var modelData
                    width: col.width
                    // group label (mock .grp) sits inside the card as its first row: outside it
                    // floated over app windows with no backing
                    Column {
                        id: gcol
                        width: parent.width
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

            // calendar (mock .cal)
            NcCard {
                visible: nc.opts.calendar !== false
                Calendar { width: parent.width }
            }

            // batteries (mock .batt: title, then a 3-column grid of 52px rings with "87%" and the
            // device name under each, 11px grey, centred in its column)
            NcCard {
                id: batt
                readonly property var items: {
                    const out = [];
                    const d = UPower.displayDevice;
                    if (d?.isLaptopBattery) out.push({ glyph: "laptop", p: d.percentage, name: hostFile.text().trim() || "This laptop" });
                    for (const b of Bt.connected) if (b.batteryAvailable) out.push({ glyph: Bt.glyphFor(b), p: b.battery, name: Bt.nameOf(b) });
                    return out.slice(0, 3);
                }
                visible: nc.opts.batteries !== false && items.length > 0
                Column {
                    width: parent.width
                    spacing: 8
                    CardTitle { width: parent.width; text: "Batteries" }
                    Row {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: batt.items
                            Column {
                                id: bi
                                required property var modelData
                                width: (batt.width - 28 - 16) / 3
                                spacing: 0
                                Ring { anchors.horizontalCenter: parent.horizontalCenter; value: bi.modelData.p; glyph: bi.modelData.glyph }
                                Item { width: 1; height: 4 }
                                GText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: Math.round(bi.modelData.p * 100) + "%"; small: true; secondary: true; font.features: ({ "tnum": 1 }) }
                                GText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: bi.modelData.name; small: true; secondary: true }
                            }
                        }
                    }
                }
            }
        }
    }
}

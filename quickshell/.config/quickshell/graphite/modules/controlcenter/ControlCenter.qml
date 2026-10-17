pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// Control Center (mock #cc): 320px glass panel, 12px padding, radius 18, 10px gaps, top right
// under the bar; fades in and drops 6px with the sheet curve. Sections by id from CcSections.
GPopup {
    id: cc
    popupId: "controlCenter"
    align: "right"
    popupWidth: 320
    padding: 12
    radius: Theme.square ? 6 : 18
    onOpenChanged: if (open) Brightness.refresh()

    content: Column {
        spacing: 10
        Repeater {
            model: Config.opt.controlCenter?.sections ?? []
            Loader {
                required property string modelData
                width: parent.width
                source: CcSections.url(modelData)
                visible: status === Loader.Ready && item.shown !== false  // sections may define `shown`
            }
        }
    }
}

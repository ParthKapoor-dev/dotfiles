pragma ComponentBehavior: Bound
import QtQuick
import qs.core
import qs.components
import qs.services

// Control Center: glass panel at the top-right, sections loaded by id from CcSections.
GPopup {
    id: cc
    popupId: "controlCenter"
    align: "right"
    popupWidth: 320
    padding: 12
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

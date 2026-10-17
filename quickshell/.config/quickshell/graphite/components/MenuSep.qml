import QtQuick
import qs.core

// mock .msep: 1px separator, 5px above/below, 10px side inset
Item {
    implicitWidth: 100
    implicitHeight: 11
    Rectangle { x: 10; width: parent.width - 20; height: 1; anchors.verticalCenter: parent.verticalCenter; color: Theme.sep }
}

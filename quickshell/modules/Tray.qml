import QtQuick
import Quickshell
import Quickshell.Services.SystemTray

Pill {
    id: root
    visible: SystemTray.items.values.length > 0
    horizontalPadding: 8

    Row {
        spacing: 8

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayItem
                required property var modelData

                width: 16
                height: 16

                Image {
                    anchors.fill: parent
                    sourceSize: Qt.size(16, 16)
                    source: trayItem.modelData.icon.includes("://")
                        ? trayItem.modelData.icon
                        : Quickshell.iconPath(trayItem.modelData.icon)
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) trayItem.modelData.activate()
                        else trayItem.modelData.secondaryActivate()
                    }
                }
            }
        }
    }
}

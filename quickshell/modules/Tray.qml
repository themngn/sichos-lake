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

                // 16px base, scaled with the rest of the bar's icons
                // (Theme.barIconScale).
                width: Math.round(16 * Theme.barIconScale)
                height: Math.round(16 * Theme.barIconScale)

                Image {
                    anchors.fill: parent
                    sourceSize: Qt.size(trayItem.width, trayItem.height)
                    source: trayItem.modelData.icon.includes("://")
                        ? trayItem.modelData.icon
                        : Quickshell.iconPath(trayItem.modelData.icon)
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            trayItem.modelData.activate()
                        } else if (mouse.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate()
                        } else if (trayItem.modelData.hasMenu) {
                            // Right click: the item's actual context menu
                            // (Quit/Show/etc.) — secondaryActivate() is a
                            // distinct action tied to middle click per the
                            // StatusNotifierItem spec, not "show the menu".
                            // display() renders a real Qt Widgets QMenu,
                            // which needs shell.qml's `UseQApplication`
                            // pragma — without it this fails silently
                            // (well, logs "quickshell was not started in
                            // QApplication mode" to stderr, easy to miss).
                            const pos = trayItem.QsWindow.itemPosition(trayItem)
                            trayItem.modelData.display(trayItem.QsWindow.window, pos.x, pos.y + trayItem.height)
                        }
                    }
                }
            }
        }
    }
}

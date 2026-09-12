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

                // Both a named theme icon (Telegram's modelData.icon
                // resolves to "image://icon/org.telegram.desktop-mute-symbolic")
                // and a raw embedded pixmap (OBS's StatusNotifierItem
                // IconName is empty, so it resolves to "image://qspixmap/1/1"
                // instead) contain "://", so that alone can't tell them
                // apart -- confirmed via a debug dump of modelData.icon for
                // both. The image provider name is the real signal: only
                // qspixmap (raw pixmap, no theme icon at all) is just the
                // app's full logo scaled down with almost no built-in
                // margin (confirmed: OBS's own icon fills ~95% of its
                // canvas edge to edge), so only that case reads visibly
                // larger than a real themed status icon -- like Telegram's,
                // designed with margin for tray size -- at the same box
                // size. Inset just that case to compensate.
                readonly property bool rawPixmap: trayItem.modelData.icon.includes("image://qspixmap/")
                // Math.round, not a bare fraction: confirmed live (raw
                // pixmap dumped straight from D-Bus and compared pixel-row
                // by pixel-row against the rendered bar icon) that OBS's
                // source icon is a perfectly symmetric circle -- the
                // "cut off at the bottom" look came from *this* size
                // landing on a fractional pixel value (18 * 0.75 = 13.5),
                // which centerIn + a raster image rounds asymmetrically
                // (loses a row of antialiasing at the bottom edge only).
                // Whole-pixel sizes rendered symmetrically in every test.
                readonly property int iconSize: rawPixmap
                    ? Math.round(trayItem.width * 0.75)
                    : trayItem.width

                Image {
                    anchors.centerIn: parent
                    width: trayItem.iconSize
                    height: trayItem.iconSize
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

import QtQuick
import Quickshell
import Quickshell.Hyprland

// Context menu for a tray icon (Tray.qml right click), drawn in QML like
// every other bar menu -- same glass card, rows, hover and open animation --
// instead of SystemTrayItem.display(), which pops a native Qt Widgets QMenu
// that ignores Theme entirely (and so was the one menu that never went
// translucent). Entries come from the item's own DBusMenu via QsMenuOpener.
// Submenus open in place (with a Back row) rather than as cascading popups.
// Open/close behaviour is the same as WorkspaceMenu.qml: focus grab for
// outside clicks / Esc, plus a hover-leave fallback.
PopupWindow {
    id: menu

    // Set by Tray.qml when opening; null = closed.
    property var handle: null
    property string title: ""
    property Item anchorItem: null
    // Submenu entries navigated into, outermost first.
    property var stack: []
    readonly property var current: stack.length > 0 ? stack[stack.length - 1] : handle

    visible: handle !== null && anchorItem !== null
    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4
    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight
    color: "transparent"

    function close() {
        menu.handle = null
        menu.stack = []
    }

    // DBusMenu labels carry GTK-style mnemonics ("_Quit"); "__" is a literal underscore.
    function label(text) {
        return (text || "").replace(/__/g, "\u0000").replace(/_/g, "").replace(/\u0000/g, "_")
    }

    function iconSource(icon) {
        if (!icon) return ""
        return icon.includes("://") || icon.startsWith("/") ? icon : Quickshell.iconPath(icon, true)
    }

    function activate(entry) {
        if (!entry.enabled || entry.isSeparator) return
        if (entry.hasChildren) {
            menu.stack = menu.stack.concat([entry])
            return
        }
        entry.triggered()
        menu.close()
    }

    QsMenuOpener {
        id: opener
        menu: menu.current
    }

    // See WorkspaceMenu.qml for why the grab is delayed a tick after showing.
    property bool grabbing: false
    onVisibleChanged: {
        menu.grabbing = false
        if (menu.visible) grabDelay.restart()
    }
    Timer {
        id: grabDelay
        interval: 50
        onTriggered: menu.grabbing = menu.visible
    }
    HyprlandFocusGrab {
        windows: [menu]
        active: menu.grabbing
        onCleared: menu.close()
    }

    property bool wasHovered: false
    onHandleChanged: menu.wasHovered = false
    Timer {
        interval: menu.wasHovered ? 400 : 1500
        running: menu.visible && !menuHover.hovered
        onTriggered: menu.close()
    }

    // Every row as wide as the widest label (measured off-layout below).
    readonly property real rowWidth: Math.max(180, labelMeasure.implicitWidth + 3 * Theme.fontSize + 40)

    Rectangle {
        id: bg
        SurfaceAppear { target: bg; shown: menu.visible }
        implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
        implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding
        color: Theme.surfaceFor(menu.screen)
        border.color: Theme.surfaceBorder
        border.width: Theme.surfaceBorderWidth
        radius: Theme.surfaceRadius

        focus: true
        Keys.onEscapePressed: menu.close()

        HoverHandler {
            id: menuHover
            onHoveredChanged: if (hovered) menu.wasHovered = true
        }

        Column {
            id: labelMeasure
            opacity: 0
            Repeater {
                model: opener.children
                delegate: Text {
                    required property var modelData
                    text: menu.label(modelData.text)
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: 2

            Text {
                visible: menu.title !== "" && menu.stack.length === 0
                bottomPadding: 6
                text: menu.title
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
                color: Theme.text
            }

            // Back out of a submenu.
            Rectangle {
                visible: menu.stack.length > 0
                width: menu.rowWidth
                height: Theme.controlHeight
                radius: Theme.controlRadius
                color: backArea.containsMouse ? Theme.hoverFill : "transparent"

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        color: Theme.textMuted
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: menu.stack.length > 0 ? menu.label(menu.stack[menu.stack.length - 1].text) : ""
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        font.bold: true
                        color: Theme.text
                    }
                }
                MouseArea {
                    id: backArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: menu.stack = menu.stack.slice(0, -1)
                }
            }

            Repeater {
                model: opener.children

                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property var entry: modelData
                    readonly property bool hasIndicator: entry.buttonType !== QsMenuButtonType.None
                    readonly property bool checked: entry.checkState === Qt.Checked

                    width: menu.rowWidth
                    height: entry.isSeparator ? 9 : Theme.controlHeight

                    Rectangle {
                        visible: row.entry.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 1
                        color: Theme.separator
                    }

                    Rectangle {
                        visible: !row.entry.isSeparator
                        anchors.fill: parent
                        radius: Theme.controlRadius
                        color: rowArea.containsMouse && row.entry.enabled ? Theme.hoverFill : "transparent"
                    }

                    Row {
                        visible: !row.entry.isSeparator
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        opacity: row.entry.enabled ? 1 : 0.4

                        Text {
                            visible: row.hasIndicator
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.entry.buttonType === QsMenuButtonType.RadioButton
                                ? (row.checked ? "󰐾" : "󰐽")
                                : (row.checked ? "󰄲" : "󰄱")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            color: row.checked ? Theme.accent : Theme.textMuted
                        }
                        Image {
                            visible: source !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: 16
                            height: 16
                            sourceSize: Qt.size(16, 16)
                            source: menu.iconSource(row.entry.icon)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: menu.label(row.entry.text)
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: Theme.text
                        }
                    }

                    Text {
                        visible: !row.entry.isSeparator && row.entry.hasChildren
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 3
                        color: Theme.textMuted
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        enabled: !row.entry.isSeparator
                        hoverEnabled: true
                        cursorShape: row.entry.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: menu.activate(row.entry)
                    }
                }
            }
        }
    }
}

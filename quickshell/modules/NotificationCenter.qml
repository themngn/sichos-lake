import QtQuick
import Quickshell

// Bar bell icon + full-height notification history drawer, styled to match
// Launcher.qml (same dim full-screen overlay + click-outside-to-close +
// flat Theme.background/Theme.accent box) rather than the small rounded
// dropdown popups the other bar widgets use — docked to the right edge
// instead of centered, and full height instead of a fixed box size.
Pill {
    id: root

    // Set by Bar.qml to this instance's own screen/name, same pattern as
    // Weather/AiModelUsage/BluetoothIndicator -- `screen` is what the
    // PanelWindow below actually renders on, `screenName` is just the
    // string key ShellState.notificationCenterScreen compares against.
    property var screen: null
    property string screenName: ""

    readonly property int count: NotificationHistory.entries.length
    readonly property bool panelOpen: ShellState.notificationCenterScreen === root.screenName

    tooltipText: root.count > 0 ? root.count + " notification" + (root.count === 1 ? "" : "s") : "No notifications"
    onClicked: ShellState.notificationCenterScreen = root.panelOpen ? "" : root.screenName

    // Ink heights (fontTools glyf bbox, units/1000em): bell-badge 700,
    // plain bell 684 -- close enough that a shared correction covers both,
    // but kept per-state so a future glyph swap doesn't silently drift.
    function iconInkUnits() {
        return root.count > 0 ? 700 : 684
    }

    BarIcon {
        // Presence-only indicator (no count) — a number badge kept
        // leaving an awkward fixed-width gap when empty; the glyph
        // switch (plain bell -> bell-badge) plus accent color together
        // say "there's something to see" instead.
        glyph: root.count > 0 ? "󱅫" : ""
        pixelSize: Theme.barIconInkHeight * 1000 / root.iconInkUnits()
        color: root.count > 0 ? Theme.accent : Theme.text
    }

    PanelWindow {
        id: panel

        screen: root.screen
        visible: root.panelOpen
        focusable: true
        color: Qt.rgba(0, 0, 0, 0.35)

        anchors {
            top: true
            left: true
            right: true
            bottom: true
        }

        MouseArea {
            anchors.fill: parent
            onClicked: ShellState.notificationCenterScreen = ""
        }

        Rectangle {
            id: box
            width: 380
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Theme.background
            border.color: Theme.accent
            border.width: 4
            radius: 0

            // Swallows clicks so they don't fall through to the outer
            // click-to-close MouseArea.
            MouseArea { anchors.fill: parent }

            Column {
                id: inner
                anchors.fill: parent
                anchors.margins: 15
                spacing: 10

                Row {
                    width: parent.width
                    height: 25

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "[ Notifications ]"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 2
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        visible: root.count > 0
                        text: "Clear All"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        color: Theme.accent

                        MouseArea { anchors.fill: parent; onClicked: NotificationHistory.clear() }
                    }
                }

                Text {
                    visible: root.count === 0
                    text: "No notifications"
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    color: Theme.textDim
                }

                ListView {
                    id: list
                    visible: root.count > 0
                    width: parent.width
                    height: parent.height - 35
                    clip: true
                    model: NotificationHistory.entries

                    delegate: Rectangle {
                        id: entryItem
                        required property var modelData
                        width: list.width
                        height: entryContent.height + 20
                        color: entryMouse.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : "transparent"
                        radius: 0

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 3
                            color: Theme.accent
                        }

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: NotificationHistory.remove(entryItem.modelData.id)
                        }

                        Column {
                            id: entryContent
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                right: parent.right
                                rightMargin: 8
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 4

                            Row {
                                id: entryHeader
                                width: parent.width
                                spacing: 6

                                Image {
                                    id: entryIcon
                                    visible: source !== ""
                                    width: visible ? 18 : 0
                                    height: 18
                                    // No `image` field here (unlike the live toast) — history
                                    // never stores it; see the comment where NotificationHistory.add()
                                    // is called for why it can't survive being persisted anyway.
                                    source: {
                                        if (!entryItem.modelData.appIcon) return ""
                                        return entryItem.modelData.appIcon.startsWith("/")
                                            ? "file://" + entryItem.modelData.appIcon
                                            : Quickshell.iconPath(entryItem.modelData.appIcon, true)
                                    }
                                }

                                Text {
                                    width: entryHeader.width - (entryIcon.visible ? entryIcon.width + entryHeader.spacing : 0)
                                        - closeGlyph.implicitWidth - entryHeader.spacing
                                    text: entryItem.modelData.summary
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }

                                Text {
                                    id: closeGlyph
                                    text: ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    color: Theme.textDim

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: NotificationHistory.remove(entryItem.modelData.id)
                                    }
                                }
                            }

                            Text {
                                visible: entryItem.modelData.body.length > 0
                                width: parent.width
                                text: entryItem.modelData.body
                                // StyledText, not PlainText — senders like
                                // Telegram send real markup (<b>, etc.);
                                // no `elide` alongside maximumLineCount
                                // here, same reasoning as Notifications.qml's
                                // toast body (that combination on rich text
                                // is what caused its "Maximum call stack"
                                // crash).
                                textFormat: Text.StyledText
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 2
                                color: Theme.textMuted
                            }

                            Text {
                                text: Qt.formatDateTime(new Date(entryItem.modelData.time), "MMM d, HH:mm")
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize - 3
                                color: Theme.textDim
                            }
                        }
                    }
                }
            }
        }
    }
}

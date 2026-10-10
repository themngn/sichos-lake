import QtQuick
import QtQuick.Effects
import Quickshell

// Bar bell icon + full-height notification history drawer, sharing
// Launcher.qml's dim full-screen overlay + click-outside-to-close behavior
// and the same Theme.surface card as every other popup — docked to the
// right edge instead of centered, and full height instead of a fixed box size.
Pill {
    id: root

    // Set by Bar.qml to this instance's own screen/name, same pattern as
    // Weather/AiModelUsage/BluetoothIndicator -- `screen` is what the
    // PanelWindow below actually renders on, `screenName` is just the
    // string key ShellState.notificationCenterScreen compares against.
    property var screen: null
    property string screenName: ""

    readonly property int count: NotificationHistory.entries.length

    // Clicking an entry, same as clicking its toast: the sender's own
    // "default" action if the notification is still live (e.g. Telegram
    // opens that exact chat). Once it isn't -- past the grace window, or
    // after a restart -- the next best thing: focus the app's existing
    // window, or launch the app if none is open. Either way the entry has
    // been dealt with, so it's removed and the panel closes (like macOS).
    function activateEntry(entry) {
        const live = NotificationHistory.liveFor(entry)
        const action = live ? live.actions.find(a => a.identifier === "default") : null
        if (action) {
            action.invoke()
        } else {
            NotificationHistory.focusOrLaunchApp(entry.desktopEntry, entry.appName)
        }
        NotificationHistory.remove(entry.id)
        ShellState.notificationCenterScreen = ""
    }
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
        color: Theme.backdrop

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

        // Soft macOS-style drop shadow under the card (drawn first, so beneath it).
        RectangularShadow {
            anchors.fill: box
            radius: box.radius
            offset.y: Theme.surfaceShadowOffset
            blur: Theme.surfaceShadowBlur
            color: Theme.surfaceShadow
            // Follows the card's open animation (SurfaceAppear) instead of
            // sitting at full strength under a card that's still fading in.
            opacity: box.opacity
            scale: box.scale
            transformOrigin: box.transformOrigin
        }

        Rectangle {
            id: box
            SurfaceAppear { target: box; shown: panel.visible; origin: Item.Right }
            width: 380
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
                // Inset from the screen edges so the rounded card reads as
                // floating, like the bar popups, instead of having its
                // corners clipped against the edge.
                margins: 8
            }
            color: Theme.surface
            border.color: Theme.surfaceBorder
            border.width: Theme.surfaceBorderWidth
            radius: Theme.surfaceRadius

            // Swallows clicks so they don't fall through to the outer
            // click-to-close MouseArea.
            MouseArea { anchors.fill: parent }

            Column {
                id: inner
                anchors.fill: parent
                anchors.margins: Theme.surfacePadding
                spacing: Theme.sectionSpacing

                Item {
                    id: header
                    width: parent.width
                    height: 20

                    Row {
                        spacing: 6
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: ""
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 1
                            color: Theme.accent
                        }
                        Text {
                            text: "Notifications"
                            color: Theme.text
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        visible: root.count > 0
                        text: "Clear All"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                        color: Theme.accent

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotificationHistory.clear()
                        }
                    }
                }

                Text {
                    visible: root.count === 0
                    text: "No notifications"
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 1
                    color: Theme.textDim
                }

                ListView {
                    id: list
                    visible: root.count > 0
                    width: parent.width
                    height: parent.height - header.height - parent.spacing
                    clip: true
                    spacing: 8
                    model: NotificationHistory.entries

                    // Each entry is its own card laid out exactly like the live
                    // toast (Notifications.qml) -- icon + bold summary + close in
                    // the header, body, then time -- so a notification looks the
                    // same before and after it lands here.
                    delegate: Rectangle {
                        id: entryItem
                        required property var modelData
                        // A folded run (count > 1: same app + summary, see
                        // NotificationHistory.add()) lists each message's body
                        // separately, each with its own close, instead of one body.
                        readonly property bool expanded: entryItem.modelData.count > 1
                        width: list.width
                        height: entryContent.height + 2 * Theme.cardPadding
                        color: entryMouse.containsMouse ? Theme.hoverFill : Theme.controlFill
                        border.color: Theme.surfaceBorder
                        border.width: Theme.surfaceBorderWidth
                        radius: Theme.controlRadius

                        MouseArea {
                            id: entryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.activateEntry(entryItem.modelData)
                        }

                        Column {
                            id: entryContent
                            anchors {
                                left: parent.left
                                right: parent.right
                                top: parent.top
                                margins: Theme.cardPadding
                            }
                            spacing: Theme.cardSpacing

                            Row {
                                id: entryHeader
                                width: parent.width
                                spacing: 8

                                Image {
                                    id: entryIcon
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Theme.notificationIconSize
                                    height: Theme.notificationIconSize
                                    sourceSize.width: width
                                    sourceSize.height: height
                                    source: {
                                        if (!entryItem.modelData.appIcon)
                                            return Qt.resolvedUrl("../assets/notification-default.svg")
                                        return entryItem.modelData.appIcon.startsWith("/")
                                            ? "file://" + entryItem.modelData.appIcon
                                            : Quickshell.iconPath(entryItem.modelData.appIcon, true)
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: entryHeader.width - entryIcon.width - closeGlyph.implicitWidth
                                        - (countBadge.visible ? countBadge.width + entryHeader.spacing : 0)
                                        - 2 * entryHeader.spacing
                                    text: entryItem.modelData.summary
                                    font.family: Theme.uiFontFamily
                                    font.pixelSize: Theme.fontSize
                                    font.bold: true
                                    color: Theme.text
                                    elide: Text.ElideRight
                                }

                                // How many messages are folded into this entry.
                                Rectangle {
                                    id: countBadge
                                    visible: entryItem.expanded
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: countNumber.implicitHeight + 2
                                    width: Math.max(height, countNumber.implicitWidth + 10)
                                    radius: height / 2
                                    color: Theme.accent

                                    Text {
                                        id: countNumber
                                        anchors.centerIn: parent
                                        // "" + ...: a single (never folded) entry has
                                        // no `count` field at all (NotificationHistory.add()
                                        // only sets one on the folded path) -- this Text
                                        // still binds (and warns "Unable to assign
                                        // undefined to QString" without the concat) even
                                        // though the badge stays invisible for it.
                                        text: "" + entryItem.modelData.count
                                        font.family: Theme.uiFontFamily
                                        font.pixelSize: Theme.fontSize - 3
                                        font.bold: true
                                        color: Theme.textOnLight
                                    }
                                }

                                Text {
                                    id: closeGlyph
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSize - 3
                                    color: closeArea.containsMouse ? Theme.text : Theme.textDim

                                    MouseArea {
                                        id: closeArea
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        hoverEnabled: true
                                        onClicked: NotificationHistory.remove(entryItem.modelData.id)
                                    }
                                }
                            }

                            Text {
                                visible: !entryItem.expanded && entryItem.modelData.body.length > 0
                                width: parent.width
                                text: entryItem.modelData.body
                                textFormat: Text.StyledText
                                wrapMode: Text.WordWrap
                                // No elide on top of maximumLineCount -- see the
                                // same Text in Notifications.qml for why.
                                maximumLineCount: 4
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: Theme.textMuted
                            }

                            Column {
                                visible: entryItem.expanded && entryItem.modelData.bodies !== undefined
                                width: parent.width
                                spacing: Theme.cardSpacing

                                Repeater {
                                    model: entryItem.modelData.bodies || []
                                    delegate: Row {
                                        id: messageItem
                                        required property var modelData
                                        required property int index
                                        width: parent.width
                                        spacing: 8

                                        Text {
                                            width: parent.width - msgCloseGlyph.implicitWidth - parent.spacing
                                            text: messageItem.modelData.body
                                            textFormat: Text.StyledText
                                            wrapMode: Text.WordWrap
                                            font.family: Theme.uiFontFamily
                                            font.pixelSize: Theme.fontSize - 1
                                            color: Theme.textMuted
                                        }

                                        Text {
                                            id: msgCloseGlyph
                                            text: ""
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSize - 3
                                            color: msgCloseArea.containsMouse ? Theme.text : Theme.textDim

                                            MouseArea {
                                                id: msgCloseArea
                                                anchors.fill: parent
                                                anchors.margins: -6
                                                hoverEnabled: true
                                                onClicked: NotificationHistory.removeMessage(entryItem.modelData.id, messageItem.index)
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                text: Qt.formatDateTime(new Date(entryItem.expanded
                                    ? entryItem.modelData.bodies[0].time
                                    : entryItem.modelData.time), "MMM d, HH:mm")
                                font.family: Theme.uiFontFamily
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

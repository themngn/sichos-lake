import QtQuick
import Quickshell

// Do-not-disturb popup for NotificationMuteToggle.qml: On/Off plus timed
// muting (ShellState.setNotificationsMuted/muteNotificationsUntil, which
// also own the auto-unmute). Same hover-persistent PopupWindow shape as
// GameFocusPopup.qml. Muting only skips the toasts -- everything still
// lands in the notification center.
PopupWindow {
    id: popup

    required property Item anchorItem
    // Re-evaluated each time the popup opens, for the "until" caption and
    // the "until morning" target.
    property real now: Date.now()
    onVisibleChanged: if (visible) popup.now = Date.now()

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4

    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight
    color: "transparent"

    // Next 08:00 local time (today if it's still before 8, else tomorrow).
    function nextMorning() {
        const d = new Date(popup.now)
        if (d.getHours() >= 8) d.setDate(d.getDate() + 1)
        d.setHours(8, 0, 0, 0)
        return d.getTime()
    }
    function untilText() {
        if (!ShellState.notificationsMuted) return "Notifications show as usual"
        if (ShellState.notificationsMutedUntil <= 0) return "Muted until you turn it off"
        const d = new Date(ShellState.notificationsMutedUntil)
        const today = d.toDateString() === new Date(popup.now).toDateString()
        return "Muted until " + Qt.formatDateTime(d, today ? "HH:mm" : "ddd HH:mm")
    }

    Rectangle {
        id: bg
        SurfaceAppear { target: bg; shown: popup.visible }
        implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
        implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding
        color: Theme.surfaceFor(popup.screen)
        border.color: Theme.surfaceBorder
        border.width: Theme.surfaceBorderWidth
        radius: Theme.surfaceRadius

        HoverHandler {
            id: popupHoverHandler
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: Theme.sectionSpacing

            Item {
                width: 240
                height: 20

                PinButton {
                    toggleId: "notifmute"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    HeaderIcon {
                        glyph: ShellState.notificationsMuted ? "󰂛" : "󰂚"
                        color: ShellState.notificationsMuted ? Theme.danger : Theme.accent
                    }
                    Text {
                        text: "Do Not Disturb"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }

            Flow {
                width: 240
                spacing: 6

                Repeater {
                    model: [
                        { muted: false, label: "Off" },
                        { muted: true, label: "On" }
                    ]
                    delegate: Rectangle {
                        id: modeButton
                        required property var modelData
                        readonly property bool active: ShellState.notificationsMuted === modelData.muted
                        width: 117
                        height: Theme.controlHeight
                        radius: Theme.controlRadius
                        color: modeButton.active ? Theme.selectedFill : modeArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                        border.color: modeButton.active ? Theme.accent : Theme.surfaceBorder
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modeButton.modelData.label
                            font.family: Theme.uiFontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: modeButton.active ? Theme.text : Theme.textMuted
                        }

                        MouseArea {
                            id: modeArea
                            hoverEnabled: true
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setNotificationsMuted(modeButton.modelData.muted, 0)
                        }
                    }
                }
            }

            Column {
                width: 240
                spacing: 6

                Text {
                    text: "Mute for"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Flow {
                    width: 240
                    spacing: 6

                    Repeater {
                        model: [
                            { minutes: 30, label: "30 min" },
                            { minutes: 60, label: "1 hour" },
                            { minutes: 120, label: "2 hours" },
                            { minutes: -1, label: "Until 08:00" }
                        ]
                        delegate: Rectangle {
                            id: modeButton
                            required property var modelData
                            readonly property bool active: false
                            width: 117
                            height: Theme.controlHeight
                            radius: Theme.controlRadius
                            color: modeButton.active ? Theme.selectedFill : modeArea.containsMouse ? Theme.hoverFill : Theme.controlFill
                            border.color: modeButton.active ? Theme.accent : Theme.surfaceBorder
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: modeButton.modelData.label
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: modeButton.active ? Theme.text : Theme.textMuted
                            }

                            MouseArea {
                                id: modeArea
                                hoverEnabled: true
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: modeButton.modelData.minutes > 0
                                    ? ShellState.setNotificationsMuted(true, modeButton.modelData.minutes)
                                    : ShellState.muteNotificationsUntil(popup.nextMorning())
                            }
                        }
                    }
                }
            }

            Text {
                width: 240
                wrapMode: Text.WordWrap
                text: popup.untilText()
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}

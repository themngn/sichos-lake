import QtQuick
import Quickshell

// Do-not-disturb popup for NotificationMuteToggle.qml: On/Off plus timed
// muting (ShellState.setNotificationsMuted/muteNotificationsUntil, which
// also own the auto-unmute). Same MorphContent shape as
// GameFocusPopup.qml. Muting only skips the toasts -- everything still
// lands in the notification center.
MorphContent {
    id: popup

    // Re-evaluated each time the popup opens, for the "until" caption and
    // the "until morning" target.
    property real now: Date.now()
    onShownChanged: if (shown) popup.now = Date.now()


    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

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

    Item {
        id: bg
        anchors.fill: parent

        HoverHandler {
            id: popupHoverHandler
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: Theme.sectionSpacing

            Item {
                width: Theme.togglePopupWidth
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
                width: Theme.togglePopupWidth
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
                        width: (Theme.togglePopupWidth - 6) / 2
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
                width: Theme.togglePopupWidth
                spacing: 6

                SectionLabel {
                    text: "Mute for"
                }

                Flow {
                    width: Theme.togglePopupWidth
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
                            width: (Theme.togglePopupWidth - 6) / 2
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
                width: Theme.togglePopupWidth
                wrapMode: Text.WordWrap
                text: popup.untilText()
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}

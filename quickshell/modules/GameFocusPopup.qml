import QtQuick
import Quickshell

// Gaming Focus popup for GameFocusToggle.qml: On/Off switch plus the dim
// amount slider. Same MorphContent shape as SunsetPopup.qml
// (see its comment on HoverHandler vs. a background MouseArea). Reads/writes
// GameFocus directly -- it's a singleton, so there's no per-screen state to
// thread through signals the way SunsetPopup's props mirror ShellState.
MorphContent {
    id: popup
    // Set when the Control Center embeds this as one of its pages: the
    // header's back button returns there.
    property string backPopupId: ""
    // Wider when embedded, to match the Control Center card.
    property real contentWidth: Theme.togglePopupWidth



    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

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
                width: popup.contentWidth
                height: 20

                PinButton {
                    toggleId: "gamefocus"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    BackButton {
                        visible: popup.backPopupId !== ""
                        onClicked: ShellState.activePopup = popup.backPopupId
                    }
                    HeaderIcon {
                        glyph: "󰊴"
                        color: Theme.accent
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Gaming Focus"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }

            Row {
                width: popup.contentWidth
                spacing: 6

                Repeater {
                    model: [
                        { on: true, label: "On" },
                        { on: false, label: "Off" }
                    ]
                    delegate: Rectangle {
                        id: modeButton
                        required property var modelData
                        readonly property bool active: GameFocus.enabled === modelData.on
                        width: (popup.contentWidth - 6) / 2
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
                            onClicked: GameFocus.enabled = modeButton.modelData.on
                        }
                    }
                }
            }

            // Dim amount, 5% steps. Takes effect live on any currently
            // dimmed screen (the overlay binds straight to dimAmount).
            Column {
                width: popup.contentWidth
                spacing: 4

                Item {
                    width: parent.width
                    height: 14
                    Text {
                        anchors.left: parent.left
                        text: "Dim other screens"
                        color: Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        anchors.right: parent.right
                        text: Math.round(GameFocus.dimAmount * 100) + "%"
                        color: GameFocus.enabled ? Theme.accent : Theme.textDim
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                }

                Rectangle {
                    id: track
                    width: parent.width
                    height: Theme.trackHeight
                    radius: Theme.trackRadius
                    color: Theme.track
                    opacity: GameFocus.enabled ? 1 : 0.5

                    readonly property real fraction: (GameFocus.dimAmount - GameFocus.minDim) / (GameFocus.maxDim - GameFocus.minDim)

                    Rectangle {
                        width: track.width * track.fraction
                        height: parent.height
                        radius: Theme.trackRadius
                        color: Theme.accent
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPositionChanged: (mouse) => {
                            if (pressed) GameFocus.setDimAmount(popup._dimAt(mouse.x))
                        }
                        onPressed: (mouse) => GameFocus.setDimAmount(popup._dimAt(mouse.x))
                        onWheel: (wheel) => GameFocus.setDimAmount(GameFocus.dimAmount + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                    }
                }
            }

            Text {
                width: popup.contentWidth
                wrapMode: Text.WordWrap
                text: !GameFocus.enabled ? "Off"
                    : GameFocus.dimming ? "Game focused on " + GameFocus.gameMonitor
                    : "Waiting for a focused game"
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    function _dimAt(x) {
        const fraction = Math.max(0, Math.min(1, x / track.width))
        return GameFocus.minDim + fraction * (GameFocus.maxDim - GameFocus.minDim)
    }
}

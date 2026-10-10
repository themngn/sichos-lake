import QtQuick
import Quickshell

// Gaming Focus popup for GameFocusToggle.qml: On/Off switch plus the dim
// amount slider. Same hover-persistent PopupWindow shape as SunsetPopup.qml
// (see its comment on HoverHandler vs. a background MouseArea). Reads/writes
// GameFocus directly -- it's a singleton, so there's no per-screen state to
// thread through signals the way SunsetPopup's props mirror ShellState.
PopupWindow {
    id: popup

    required property Item anchorItem

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 4

    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight
    color: "transparent"

    Rectangle {
        id: bg
        implicitWidth: column.implicitWidth + 24
        implicitHeight: column.implicitHeight + 20
        color: "#1c1c1c"
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 1
        radius: 6

        HoverHandler {
            id: popupHoverHandler
        }

        Column {
            id: column
            anchors.centerIn: parent
            spacing: 12

            Item {
                width: 220
                height: 20

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "󰊴"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize + 1
                        color: Theme.accent
                    }
                    Text {
                        text: "Gaming Focus"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }

            Row {
                width: 220
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
                        width: 107
                        height: 26
                        radius: 4
                        color: modeButton.active ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.06)
                        border.color: modeButton.active ? Theme.accent : Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: modeButton.modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                            color: modeButton.active ? Theme.text : Theme.textMuted
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: GameFocus.enabled = modeButton.modelData.on
                        }
                    }
                }
            }

            // Dim amount, 5% steps. Takes effect live on any currently
            // dimmed screen (the overlay binds straight to dimAmount).
            Column {
                width: 220
                spacing: 4

                Item {
                    width: parent.width
                    height: 14
                    Text {
                        anchors.left: parent.left
                        text: "Dim other screens"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                    Text {
                        anchors.right: parent.right
                        text: Math.round(GameFocus.dimAmount * 100) + "%"
                        color: GameFocus.enabled ? Theme.accent : Theme.textDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 2
                    }
                }

                Rectangle {
                    id: track
                    width: parent.width
                    height: 8
                    color: Qt.rgba(1, 1, 1, 0.12)
                    opacity: GameFocus.enabled ? 1 : 0.5

                    readonly property real fraction: (GameFocus.dimAmount - GameFocus.minDim) / (GameFocus.maxDim - GameFocus.minDim)

                    Rectangle {
                        width: track.width * track.fraction
                        height: parent.height
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
                width: 220
                wrapMode: Text.WordWrap
                text: !GameFocus.enabled ? "Off"
                    : GameFocus.dimming ? "Game focused on " + GameFocus.gameMonitor
                    : "Waiting for a focused game"
                color: Theme.textDim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }

    function _dimAt(x) {
        const fraction = Math.max(0, Math.min(1, x / track.width))
        return GameFocus.minDim + fraction * (GameFocus.maxDim - GameFocus.minDim)
    }
}

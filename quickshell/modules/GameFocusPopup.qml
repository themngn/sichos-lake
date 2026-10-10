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
                        font.family: Theme.uiFontFamily
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
                width: 220
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
                width: 220
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

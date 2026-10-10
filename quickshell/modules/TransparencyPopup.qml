import QtQuick
import Quickshell

// Transparency popup for TransparencyToggle.qml: Semi/Opaque switch plus the
// terminal's opacity in semi mode. Same hover-persistent PopupWindow shape
// as GameFocusPopup.qml. Both go through ShellState (setTransparencyOpaque/
// setTerminalOpacity), which owns pushing the change to kitty.
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

    function _opacityAt(x) {
        return 0.5 + Math.max(0, Math.min(1, x / track.width)) * 0.45
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
                width: 220
                height: 20

                PinButton {
                    toggleId: "transparency"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    HeaderIcon {
                        glyph: "\uf042"
                        color: Theme.accent
                    }
                    Text {
                        text: "Transparency"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }

            Flow {
                width: 220
                spacing: 6

                Repeater {
                    model: [
                        { opaque: false, label: "Semi" },
                        { opaque: true, label: "Opaque" }
                    ]
                    delegate: Rectangle {
                        id: modeButton
                        required property var modelData
                        readonly property bool active: ShellState.transparencyOpaque === modelData.opaque
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
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ShellState.setTransparencyOpaque(modeButton.modelData.opaque)
                        }
                    }
                }
            }

            // Semi mode's terminal opacity, 50-95% in 5% steps (100% is
            // what "Opaque" is for). Applies live while in semi mode; while
            // opaque it just presets the level to come back to.
            Column {
                width: 220
                spacing: 4

                Item {
                    width: parent.width
                    height: 14
                    Text {
                        anchors.left: parent.left
                        text: "Terminal opacity"
                        color: Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        anchors.right: parent.right
                        text: Math.round(BarSettings.terminalOpacity * 100) + "%"
                        color: ShellState.transparencyOpaque ? Theme.textDim : Theme.accent
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
                    opacity: ShellState.transparencyOpaque ? 0.5 : 1

                    Rectangle {
                        width: track.width * (BarSettings.terminalOpacity - 0.5) / 0.45
                        height: parent.height
                        radius: Theme.trackRadius
                        color: Theme.accent
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPositionChanged: (mouse) => {
                            if (pressed) ShellState.setTerminalOpacity(popup._opacityAt(mouse.x))
                        }
                        onPressed: (mouse) => ShellState.setTerminalOpacity(popup._opacityAt(mouse.x))
                        onWheel: (wheel) => ShellState.setTerminalOpacity(BarSettings.terminalOpacity + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                    }
                }
            }

            Text {
                width: 220
                wrapMode: Text.WordWrap
                text: ShellState.transparencyOpaque
                    ? "Bar and terminals fully opaque"
                    : "Bar transparent over an empty desktop; terminals at " + Math.round(BarSettings.terminalOpacity * 100) + "%"
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}

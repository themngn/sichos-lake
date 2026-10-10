import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Microphone popup for MicMuteToggle.qml: Live/Muted switch, input volume,
// and the list of input devices to pick the default from. Same
// ToggleMorphPopup content shape as GameFocusPopup.qml. Everything here
// acts on PipeWire directly (the default source's own mute/volume, and
// Pipewire.preferredDefaultAudioSource for switching), the same objects the
// XF86AudioMicMute key and wpctl go through, so they all stay in agreement.
Item {
    id: popup

    required property Item anchorItem
    // Content for ToggleMorphPopup (the bar's one morphing card, shared by
    // every toggle-row popup): the toggle reparents this into the card and
    // drives `shown`; the card sizes itself to this item's implicit size,
    // lines up under anchorItem, and cross-fades between contents.
    property bool shown: false
    anchors.top: parent ? parent.top : undefined
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined
    opacity: shown ? 1 : 0
    visible: opacity > 0
    // Outgoing content clears out quickly so the two don't read as a
    // jumble mid-morph; the incoming one fades in over the full open time.
    Behavior on opacity {
        NumberAnimation { duration: shown ? Theme.openDuration : 70; easing.type: Easing.OutCubic }
    }
    property var source: Pipewire.defaultAudioSource


    readonly property bool popupHovered: popupHoverHandler.hovered
    readonly property bool hasAudio: popup.source !== null && popup.source.audio !== null
    readonly property bool muted: popup.hasAudio && popup.source.audio.muted
    readonly property real volume: popup.hasAudio ? popup.source.audio.volume : 0
    // Hardware/virtual inputs only: no sinks, no app capture streams, no
    // video nodes (cameras have no audio interface).
    readonly property var inputs: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)

    implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    function setVolume(v) {
        if (popup.hasAudio) popup.source.audio.volume = Math.max(0, Math.min(1, v))
    }

    function nodeLabel(n) {
        return n.description || n.nickname || n.name
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
                width: 240
                height: 20

                PinButton {
                    toggleId: "mic"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    HeaderIcon {
                        glyph: popup.muted ? "󰍭" : "󰍬"
                        color: popup.muted ? Theme.danger : Theme.accent
                    }
                    Text {
                        text: "Microphone"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }

            Text {
                visible: !popup.hasAudio
                text: "No microphone"
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            Row {
                visible: popup.hasAudio
                width: 240
                spacing: 6

                Repeater {
                    model: [
                        { muted: false, label: "Live" },
                        { muted: true, label: "Muted" }
                    ]
                    delegate: Rectangle {
                        id: modeButton
                        required property var modelData
                        readonly property bool active: popup.muted === modelData.muted
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
                            onClicked: if (popup.hasAudio) popup.source.audio.muted = modeButton.modelData.muted
                        }
                    }
                }
            }

            Column {
                visible: popup.hasAudio
                width: 240
                spacing: 4

                Item {
                    width: parent.width
                    height: 14
                    Text {
                        anchors.left: parent.left
                        text: "Input volume"
                        color: Theme.textMuted
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }
                    Text {
                        anchors.right: parent.right
                        text: Math.round(popup.volume * 100) + "%"
                        color: popup.muted ? Theme.textDim : Theme.accent
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
                    opacity: popup.muted ? 0.5 : 1

                    Rectangle {
                        width: track.width * Math.min(1, popup.volume)
                        height: parent.height
                        radius: Theme.trackRadius
                        color: Theme.accent
                    }

                    MouseArea {
                        anchors.fill: parent
                        onPositionChanged: (mouse) => { if (pressed) popup.setVolume(mouse.x / track.width) }
                        onPressed: (mouse) => popup.setVolume(mouse.x / track.width)
                        onWheel: (wheel) => popup.setVolume(popup.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                    }
                }
            }

            Column {
                visible: popup.inputs.length > 0
                width: 240
                spacing: 2

                Text {
                    bottomPadding: 4
                    text: "Input device"
                    color: Theme.textMuted
                    font.family: Theme.uiFontFamily
                    font.pixelSize: Theme.fontSize - 2
                }

                Repeater {
                    model: popup.inputs
                    delegate: Rectangle {
                        id: deviceRow
                        required property var modelData
                        readonly property bool current: popup.source !== null && popup.source.id === modelData.id
                        width: 240
                        height: Theme.controlHeight
                        radius: Theme.controlRadius
                        color: deviceArea.containsMouse ? Theme.hoverFill : "transparent"

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                id: radio
                                anchors.verticalCenter: parent.verticalCenter
                                text: deviceRow.current ? "󰐾" : "󰐽"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: deviceRow.current ? Theme.accent : Theme.textMuted
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - radio.width - parent.spacing
                                elide: Text.ElideRight
                                text: popup.nodeLabel(deviceRow.modelData)
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: deviceRow.current ? Theme.text : Theme.textMuted
                            }
                        }

                        MouseArea {
                            id: deviceArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: deviceRow.current ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: if (!deviceRow.current) Pipewire.preferredDefaultAudioSource = deviceRow.modelData
                        }
                    }
                }
            }
        }
    }
}

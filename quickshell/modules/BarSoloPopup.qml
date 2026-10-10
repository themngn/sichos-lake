import QtQuick
import Quickshell

// Bar placement popup for BarSoloToggle.qml: show the bar on every screen,
// or on one picked screen only (ShellState.barSoloScreen). Same
// ToggleMorphPopup content shape as GameFocusPopup.qml; the screen list
// uses MicPopup's radio-row style. Picking another screen hides this bar
// (and with it this popup) -- expected, the bar moved.
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
    // The screen this popup's bar lives on, to tag it "this screen".
    property string screenName: ""


    readonly property bool popupHovered: popupHoverHandler.hovered

    implicitWidth: column.implicitWidth + 2 * Theme.surfacePadding
    implicitHeight: column.implicitHeight + 2 * Theme.surfacePadding

    // Monitor make/model next to the connector name, when Quickshell has one.
    function screenLabel(s) {
        const model = s.model || ""
        return model.length ? s.name + " · " + model : s.name
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
                    toggleId: "barsolo"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                }

                Row {
                    spacing: 6
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    HeaderIcon {
                        glyph: "󰍹"
                        color: Theme.accent
                    }
                    Text {
                        text: "Bar Placement"
                        font.family: Theme.uiFontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        color: Theme.text
                    }
                }
            }

            Column {
                width: 240
                spacing: 2

                Repeater {
                    // "" = all screens, then one row per connected screen.
                    model: [""].concat(Quickshell.screens.map(s => s.name))
                    delegate: Rectangle {
                        id: screenRow
                        required property string modelData
                        readonly property bool current: modelData === ""
                            ? ShellState.barSoloScreen === "" || !Quickshell.screens.some(s => s.name === ShellState.barSoloScreen)
                            : ShellState.barSoloScreen === modelData
                        readonly property var screenObj: Quickshell.screens.find(s => s.name === modelData) || null
                        width: 240
                        height: Theme.controlHeight
                        radius: Theme.controlRadius
                        color: screenArea.containsMouse ? Theme.hoverFill : "transparent"

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
                                text: screenRow.current ? "󰐾" : "󰐽"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                color: screenRow.current ? Theme.accent : Theme.textMuted
                            }
                            Text {
                                id: rowLabel
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, parent.width - radio.width - hereTag.implicitWidth - 2 * parent.spacing)
                                elide: Text.ElideRight
                                text: screenRow.modelData === "" ? "All screens"
                                    : screenRow.screenObj ? popup.screenLabel(screenRow.screenObj) : screenRow.modelData
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 1
                                color: screenRow.current ? Theme.text : Theme.textMuted
                            }
                            Text {
                                id: hereTag
                                anchors.verticalCenter: parent.verticalCenter
                                visible: screenRow.modelData !== "" && screenRow.modelData === popup.screenName
                                text: "this screen"
                                font.family: Theme.uiFontFamily
                                font.pixelSize: Theme.fontSize - 3
                                color: Theme.textDim
                            }
                        }

                        MouseArea {
                            id: screenArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: screenRow.current ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: if (!screenRow.current) ShellState.barSoloScreen = screenRow.modelData
                        }
                    }
                }
            }

            Text {
                width: 240
                wrapMode: Text.WordWrap
                text: "Click the bar icon to keep the bar on this screen only"
                color: Theme.textDim
                font.family: Theme.uiFontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}

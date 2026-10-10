import QtQuick

// Clock and Date Bar Widget with interactive hover/click Calendar popup.
// Left click toggles the calendar popup. Hover (with 250ms initial delay,
// or immediate switch if another menu is already open) opens CalendarPopup.qml,
// staying open while hovered over the card.
Pill {
    id: root
    property date now: new Date()
    property string screenName: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    readonly property string popupId: "calendar"
    readonly property bool popupOpen: ShellState.activePopup === root.popupId && ShellState.activePopupScreen === root.screenName
    readonly property bool popupHovered: calendarPopup.popupHovered

    Timer {
        id: openDelayTimer
        interval: 250
        onTriggered: {
            if (root.hovered) {
                ShellState.activePopup = root.popupId
                ShellState.activePopupScreen = root.screenName
            }
        }
    }

    Timer {
        id: closeDelayTimer
        interval: 300
        onTriggered: {
            if (!root.hovered && !root.popupHovered) {
                if (ShellState.activePopup === root.popupId) {
                    ShellState.activePopup = ""
                }
            }
        }
    }

    function _updateHoverState() {
        if (root.hovered) {
            closeDelayTimer.stop()
            if (ShellState.activePopup !== "" && !root.popupOpen) {
                openDelayTimer.stop()
                ShellState.activePopup = root.popupId
                ShellState.activePopupScreen = root.screenName
            } else if (ShellState.activePopup === "" && !openDelayTimer.running) {
                openDelayTimer.start()
            }
        } else if (root.popupHovered) {
            closeDelayTimer.stop()
            openDelayTimer.stop()
        } else {
            openDelayTimer.stop()
            if (root.popupOpen && !closeDelayTimer.running) {
                closeDelayTimer.start()
            }
        }
    }

    onHoveredChanged: _updateHoverState()
    onPopupHoveredChanged: _updateHoverState()

    onClicked: (mouse) => {
        if (root.popupOpen) {
            ShellState.activePopup = ""
        } else {
            ShellState.activePopup = root.popupId
            ShellState.activePopupScreen = root.screenName
        }
    }

    Text {
        text: Qt.formatDateTime(root.now, TimeRegion.use24Hour ? "ddd dd  HH:mm" : "ddd dd  h:mm AP")
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }

    // Set by Bar.qml: the bar's MorphPopup card (see MorphContent.qml).
    property Item popupHost: null
    readonly property Item _popupContent: CalendarPopup {
        id: calendarPopup
        parent: root.popupHost
        anchorItem: root
        shown: root.popupOpen
    }
}

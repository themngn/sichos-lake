import QtQuick

// Warm Light / Night Light indicator and settings toggle (SunsetToggle.qml).
// Left click toggles between schedule and off. Hover (with 250ms initial delay,
// or immediate switch if another menu is already open) opens SunsetPopup.qml,
// staying open while hovered over the popup card.
Pill {
    id: root
    property bool active: false
    property string mode: "schedule"
    property int kelvin: 2500
    property bool scheduleWarm: false
    property string screenName: ""
    signal modeSelected(string mode)
    signal setTemperature(int kelvin)
    signal scheduleSaved()

    opacity: root.active ? 1 : 0.5

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    readonly property string popupId: "sunset"
    readonly property bool popupOpen: ShellState.activePopup === root.popupId && ShellState.activePopupScreen === root.screenName
    readonly property bool popupHovered: popup.popupHovered

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
        if (mouse.button === Qt.RightButton) {
            if (root.popupOpen) {
                ShellState.activePopup = ""
            } else {
                ShellState.activePopup = root.popupId
                ShellState.activePopupScreen = root.screenName
            }
        } else {
            if (root.mode === "off") {
                root.modeSelected("schedule")
            } else {
                root.modeSelected("off")
            }
        }
    }

    Text {
        text: "\uf186"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: root.active ? Theme.text : Theme.textMuted
    }

    SunsetPopup {
        id: popup
        anchorItem: root
        visible: root.popupOpen
        mode: root.mode
        kelvin: root.kelvin
        scheduleWarm: root.scheduleWarm
        onModeSelected: (m) => root.modeSelected(m)
        onSetTemperature: (k) => root.setTemperature(k)
        onScheduleSaved: root.scheduleSaved()
    }
}

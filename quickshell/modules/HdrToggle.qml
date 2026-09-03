import QtQuick

// HDR indicator and settings toggle (HdrToggle.qml), next to Warm Light in
// Bar.qml. Left click toggles HDR immediately — same action as Win+Shift+H
// and `quickshell ipc call hdr toggle`, all three go through HdrSettings so
// the icon always reflects the real state. Hover (with 250ms initial delay,
// or immediate switch if another menu is already open) opens HdrPopup.qml
// to pick which monitors HDR actually applies to, staying open while
// hovered over the popup card.
Pill {
    id: root
    readonly property bool active: HdrSettings.active
    property string screenName: ""

    opacity: root.active ? 1 : 0.5
    tooltipText: root.active ? "HDR on" : "HDR off"

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    readonly property string popupId: "hdr"
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
            HdrSettings.toggleActive()
        }
    }

    Text {
        text: "HDR"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 3
        font.bold: true
        color: root.active ? Theme.text : Theme.textMuted
    }

    HdrPopup {
        id: popup
        anchorItem: root
        visible: root.popupOpen
    }
}

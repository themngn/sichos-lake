import QtQuick

// Gaming Focus toggle (see GameFocus.qml). Left click arms/disarms the mode;
// hover (or right click) opens GameFocusPopup.qml for the dim amount -- same
// hover/popup handling as IdleToggle.qml. Armed-but-idle
// (no game focused) and actively dimming are both "active" for the purposes
// of staying visible in a collapsed row, but only the latter lights the icon
// in the success green, so a glance tells you whether it's actually engaged.
Pill {
    id: root
    property bool revealed: true
    property string screenName: ""

    readonly property bool armed: GameFocus.enabled
    readonly property bool dimming: GameFocus.dimming

    // While on, stays visible in the collapsed row only if pinned (the
    // default; BarSettings, via PinButton in the popup).
    readonly property bool shown: root.revealed || (root.armed && BarSettings.isPinned("gamefocus"))
    opacity: root.shown ? (root.armed ? 1 : 0.5) : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
    // Same width-collapse trick as the other fixed toggles — see
    // TransparencyToggle's comment.
    clip: true
    width: root.shown ? root.implicitWidth : 0
    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    readonly property string popupId: "gamefocus"
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
            GameFocus.enabled = !GameFocus.enabled
        }
    }

    Text {
        text: "󰊴"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.dimming ? Theme.success : (root.armed ? Theme.text : Theme.textMuted)
    }

    GameFocusPopup {
        id: popup
        anchorItem: root
        visible: root.popupOpen
    }
}

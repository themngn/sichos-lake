import QtQuick

// Do-not-disturb toggle. One click flips ShellState.notificationsMuted,
// which Notifications.qml checks when a toast would otherwise pop up; hover
// (or right click) opens NotificationMutePopup.qml for timed muting -- same
// hover/popup handling as GameFocusToggle.qml. Like MicMuteToggle, "active"
// here means muted: an accidentally-still-muted state (missing something
// you actually needed to see) is a worse failure mode than an
// accidentally-still-unmuted one, so it's the state that gets the
// persistent, hard-to-miss reminder.
Pill {
    id: root
    property bool muted: false
    property bool revealed: true
    property string screenName: ""
    signal toggle()

    // Same red as MicMuteToggle's mutedColor -- kept local rather than
    // hoisted into Theme.qml for the same reason that one is: it belongs to
    // the custom alert-widget outside this repo, this just matches it.
    readonly property color mutedColor: Theme.danger

    readonly property bool shown: root.revealed || (root.muted && BarSettings.isPinned("notifmute"))
    opacity: root.shown ? (root.muted ? 1 : 0.5) : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
    clip: true
    width: root.shown ? root.implicitWidth : 0
    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    readonly property string popupId: "notifmute"
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
            root.toggle()
        }
    }

    Text {
        text: root.muted ? "󰂛" : "󰂚" // md-bell_off / md-bell
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.muted ? root.mutedColor : Theme.textMuted
    }

    NotificationMutePopup {
        id: popup
        anchorItem: root
        visible: root.popupOpen
    }
}

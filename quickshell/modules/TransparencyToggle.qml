import QtQuick

// Bar + terminal transparency toggle. One click flips between the bar's
// normal dynamic transparency (transparent over an empty desktop, 80% once a
// window's behind it) and a fully opaque backdrop for both the bar and every
// open kitty window. Hover (or right click) opens TransparencyPopup.qml for
// the same switch plus the terminal's semi-transparent level -- same
// hover/popup handling as GameFocusToggle.qml.
Pill {
    id: root
    property bool opaque: false
    // Whether the bar has revealed the toggle row (hover/popup-open) --
    // set externally by Bar.qml. Only matters while inactive: an active
    // toggle stays shown (while pinned -- BarSettings, via PinButton in the
    // popup), so its on/off state is never hidden from a glance at the bar.
    property bool revealed: true
    property string screenName: ""
    signal toggle()

    readonly property bool shown: root.revealed || (root.opaque && BarSettings.isPinned("transparency"))
    opacity: root.shown ? (root.opaque ? 1 : 0.5) : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
    // Collapses the pill's own width to 0 when hidden (rather than just
    // fading it out) so Bar.qml's toggleRow -- sized by its children's real
    // widths -- closes the gap and the remaining visible pills slide flush
    // together instead of leaving dead space where this one used to sit.
    clip: true
    width: root.shown ? root.implicitWidth : 0
    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    readonly property string popupId: "transparency"
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
        text: "\uf042"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.opaque ? Theme.text : Theme.textMuted
    }

    TransparencyPopup {
        id: popup
        anchorItem: root
        visible: root.popupOpen
    }
}

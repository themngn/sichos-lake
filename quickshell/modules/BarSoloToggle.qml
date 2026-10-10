import QtQuick

// "Bar on this screen only" toggle (ShellState.barSoloScreen). Clicking it
// pins the bar to the screen this pill lives on (screenName) and hides it
// everywhere else; since the only bar left visible is the pinned one,
// clicking again always unpins. Hover (or right click) opens
// BarSoloPopup.qml to pick any screen (or all) directly -- same hover/popup
// handling as GameFocusToggle.qml.
Pill {
    id: root
    property string screenName: ""
    property bool active: false
    // Set externally by Bar.qml, same as TransparencyToggle's.
    property bool revealed: true
    signal toggle()

    readonly property bool shown: root.revealed || (root.active && BarSettings.isPinned("barsolo"))
    opacity: root.shown ? (root.active ? 1 : 0.5) : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
    // Width collapse rather than just a fade -- see TransparencyToggle.
    clip: true
    width: root.shown ? root.implicitWidth : 0
    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    readonly property string popupId: "barsolo"
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
        text: "󰍹"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.active ? Theme.text : Theme.textMuted
    }

    // Set by Bar.qml: the bar's ToggleMorphPopup card. The popup content is
    // assigned to a property (not declared as a child) because Pill's
    // default property would otherwise lay it out inside the pill itself;
    // `parent` then moves it into the card, keeping every binding to this
    // toggle intact.
    property Item popupHost: null
    readonly property Item _popupContent: BarSoloPopup {
        id: popup
        parent: root.popupHost
        anchorItem: root
        screenName: root.screenName
        shown: root.popupOpen
    }
}

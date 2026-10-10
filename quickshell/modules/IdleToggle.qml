import QtQuick

// Stay Awake toggle and settings (IdleToggle.qml).
// Left click toggles Stay Awake immediately. Hover (with 250ms initial delay,
// or immediate switch if another menu is already open) opens IdlePopup.qml,
// staying open while hovered over the popup.
Pill {
    id: root
    property bool active: false
    property string screenName: ""
    // Whether the bar has revealed the toggle row (hover/popup-open) --
    // set externally by Bar.qml. Only matters while inactive: an active
    // toggle always stays shown regardless, so its on/off state is never
    // hidden from a glance at the bar.
    property bool revealed: true
    signal toggle()
    signal settingsSaved()

    // While on, stays visible in the collapsed row only if pinned (the
    // default; BarSettings, via PinButton in the popup).
    readonly property bool shown: root.revealed || (root.active && BarSettings.isPinned("idle"))
    opacity: root.shown ? (root.active ? 1 : 0.5) : 0
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

    // --- Hover Management with Trigger Delay, Immediate Switch & Stay on Hover ---
    readonly property string popupId: "idle"
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
        text: "\udb80\udd76"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.active ? Theme.text : Theme.textMuted
    }

    // Set by Bar.qml: the bar's MorphPopup card. The popup content is
    // assigned to a property (not declared as a child) because Pill's
    // default property would otherwise lay it out inside the pill itself;
    // `parent` then moves it into the card, keeping every binding to this
    // toggle intact.
    property Item popupHost: null
    readonly property Item _popupContent: IdlePopup {
        id: popup
        parent: root.popupHost
        anchorItem: root
        shown: root.popupOpen
        active: root.active
        onSettingsSaved: root.settingsSaved()
    }
}

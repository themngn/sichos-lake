import QtQuick

// Warm Light / Night Light indicator and settings toggle (SunsetToggle.qml).
// Left click force-toggles the warm filter on/off directly, based on its
// current on-screen appearance (root.active). "Follow schedule" is a
// separate, independent property/switch (root.scheduleFollow, edited from
// SunsetPopup.qml's checkbox) -- clicking here never touches it, and
// checking/unchecking it never goes through this click path. Hover (with
// 250ms initial delay, or immediate switch if another menu is already
// open) opens SunsetPopup.qml, staying open while hovered over the popup
// card.
Pill {
    id: root
    property bool active: false
    property bool scheduleFollow: true
    property int kelvin: 2500
    property string screenName: ""
    // Whether the bar has revealed the toggle row (hover/popup-open) --
    // set externally by Bar.qml. Only matters while inactive: an active
    // toggle always stays shown regardless, so its on/off state is never
    // hidden from a glance at the bar.
    property bool revealed: true
    signal setWarm(bool warm)
    signal setTemperature(int kelvin)
    signal setScheduleFollow(bool follow)
    signal scheduleSaved()

    readonly property bool shown: root.active || root.revealed
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
            root.setWarm(!root.active)
        }
    }

    Text {
        text: "\uf186"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.active ? Theme.text : Theme.textMuted
    }

    SunsetPopup {
        id: popup
        anchorItem: root
        visible: root.popupOpen
        active: root.active
        scheduleFollow: root.scheduleFollow
        kelvin: root.kelvin
        onSetWarm: (w) => root.setWarm(w)
        onSetTemperature: (k) => root.setTemperature(k)
        onSetScheduleFollow: (f) => root.setScheduleFollow(f)
        onScheduleSaved: root.scheduleSaved()
    }
}

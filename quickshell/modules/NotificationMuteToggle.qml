import QtQuick

// Do-not-disturb toggle. Same shape as TransparencyToggle/MicMuteToggle --
// no popup, one click flips ShellState.notificationsMuted, which
// Notifications.qml checks when a toast would otherwise pop up. Like
// MicMuteToggle, "active" here means muted: an accidentally-still-muted
// state (missing something you actually needed to see) is a worse failure
// mode than an accidentally-still-unmuted one, so it's the state that gets
// the persistent, hard-to-miss reminder.
Pill {
    id: root
    property bool muted: false
    property bool revealed: true
    signal toggle()

    tooltipText: root.muted ? "Notifications muted (click to unmute)" : "Notifications on (click to mute)"

    // Same red as MicMuteToggle's mutedColor -- kept local rather than
    // hoisted into Theme.qml for the same reason that one is: it belongs to
    // the custom alert-widget outside this repo, this just matches it.
    readonly property color mutedColor: "#ee3e3e"

    readonly property bool shown: root.muted || root.revealed
    opacity: root.shown ? (root.muted ? 1 : 0.5) : 0
    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }
    clip: true
    width: root.shown ? root.implicitWidth : 0
    Behavior on width {
        NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
    }

    onClicked: root.toggle()

    Text {
        text: root.muted ? "󰂛" : "󰂚" // md-bell_off / md-bell
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.muted ? root.mutedColor : Theme.textMuted
    }
}

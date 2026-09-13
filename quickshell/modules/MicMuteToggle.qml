import QtQuick
import Quickshell

// Microphone mute toggle. No popup, same shape as TransparencyToggle — one
// click flips Pipewire.defaultAudioSource's mute state, the same PipeWire
// object hyprland's XF86AudioMicMute key already drives via
// `wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle` (keybindings.lua), so the
// hardware button and this pill always agree without any extra wiring.
// Unlike the other fixed toggles, "active" here means muted — the state you
// actually want a persistent, hard-to-miss reminder for, since an
// accidentally-still-muted mic in a call is a much worse failure mode than
// an accidentally-still-unmuted one.
Pill {
    id: root
    property var source: null
    property bool revealed: true

    readonly property bool muted: root.source && root.source.audio ? root.source.audio.muted : false
    tooltipText: !root.source ? "No microphone" : (root.muted ? "Mic muted (click to unmute)" : "Mic live (click to mute)")

    // Matches the custom alert-widget's (~/.config/quickshell/custom/alert-widget)
    // colRed — not in Theme.qml since that widget lives outside this repo, but
    // reusing its exact red keeps every "something needs your attention right
    // now" indicator across the bar visually consistent.
    readonly property color mutedColor: "#ee3e3e"

    // PipeWire's mute here is a software-only mute — confirmed live it never
    // touches the actual ALSA "Capture Switch" mixer control, so the kernel's
    // audio-micmute LED trigger (the physical mic-mute light next to the
    // webcam/keyboard, /sys/class/leds/platform::micmute, already set to that
    // trigger by default) never fires no matter which path changed the mute
    // (this pill or the hardware XF86AudioMicMute key both only go through
    // PipeWire). Driving the LED ourselves on every change, regardless of
    // source, is the only way to keep it honest. brightnessctl (already used
    // by Backlight.qml) rather than a raw sysfs write — the brightness file
    // is root-owned (0644) and a plain shell redirect gets EACCES; brightnessctl
    // goes through logind's SetBrightness D-Bus call instead, which this
    // session's seat ACL does permit. execDetached + a device name that may
    // not exist on every machine (this is laptop-specific hardware) is a
    // silent no-op elsewhere — same tradeoff install.sh already accepts for
    // other hardware-dependent bits rather than needing per-machine config.
    onMutedChanged: Quickshell.execDetached(["brightnessctl", "-d", "platform::micmute", "set", root.muted ? "1" : "0"])
    // onMutedChanged only fires on a change — sync the LED to whatever the
    // mic's actual mute state already is at quickshell startup too (e.g.
    // after a restart while already muted), rather than leaving it wherever
    // it happened to be left.
    Component.onCompleted: Quickshell.execDetached(["brightnessctl", "-d", "platform::micmute", "set", root.muted ? "1" : "0"])

    readonly property bool shown: root.muted || root.revealed
    opacity: root.shown ? (root.muted ? 1 : 0.5) : 0
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

    onClicked: {
        if (root.source && root.source.audio) root.source.audio.muted = !root.source.audio.muted
    }

    Text {
        text: root.muted ? "󰍭" : "󰍬"
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize * Theme.barIconScale
        color: root.muted ? root.mutedColor : Theme.textMuted
    }
}

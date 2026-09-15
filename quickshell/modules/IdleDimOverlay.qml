import QtQuick
import Quickshell
import Quickshell.Wayland

// Idle-dim, one instance per screen (see shell.qml's Variants). Originally
// this was a plain `brightnessctl -s set 10%` hypridle listener (see
// hypridle.conf/IdlePopup.qml's git history), which only ever dims the
// laptop panel's own backlight (/sys/class/backlight/amdgpu_bl1) — an
// external/DP monitor with no backlight sysfs node and no DDC brightness
// control (DisplaySettings.qml's own "no brightness control" case) just
// never dimmed at all. A software overlay dims every connected output
// identically regardless of what brightness control (if any) it actually
// has, so this replaced brightnessctl entirely rather than running
// alongside it. All state lives in ShellState.idleDimActive (driven by
// hypridle.conf's on-timeout/on-resume over `quickshell ipc call idledim
// dim`/`undim`) so every screen's overlay fades in lockstep.
PanelWindow {
    id: overlay

    required property var modelData
    screen: modelData

    color: "transparent"
    exclusiveZone: 0
    focusable: false

    // Overlay layer so this sits above the bar/normal windows on every
    // screen, same as NowPlaying.qml -- but with an empty input region
    // (zero-area mask) so it never actually intercepts a click or
    // keypress; it's purely a visual dim; nothing here needs to be first to
    // see real input, and the whole point is to let the immediate next
    // keypress/click reach whatever's underneath and end idle normally.
    WlrLayershell.layer: WlrLayer.Overlay
    mask: Region {}

    anchors { top: true; left: true; right: true; bottom: true }
    // A zero-exclusive-zone top-anchored surface measures its margin from
    // the space Bar.qml's own exclusiveZone already reserves, regardless of
    // this surface's Overlay layer -- confirmed live in NowPlaying.qml
    // (see its own comment on this exact quirk). Cancel it out so the dim
    // actually reaches y=0 and covers the bar strip too, instead of leaving
    // a permanently-undimmed bar-height gap at the top of every screen.
    margins.top: -Theme.barHeight

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: ShellState.idleDimActive ? 0.75 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }
}

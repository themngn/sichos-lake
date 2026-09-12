import QtQuick
import Quickshell
import Quickshell.Wayland

// Transient full-width strip, same height/position as Bar.qml, that pops up
// for a few seconds whenever Spotify's track changes and shows "artist:
// title" — a "Now Playing" toast rather than a permanent widget, same
// pop()-then-auto-hide idea as VolumeOSD. One instance per screen (see
// shell.qml's Variants) so it shows on every display at once; all the actual
// state (spotify tracking, animation, visibility) lives in the shared
// NowPlayingState singleton so every instance stays in lockstep instead of
// animating independently.
PanelWindow {
    id: root

    required property var modelData
    screen: modelData

    // Transparent window, not Theme.background — only the strip Rectangle
    // below paints the bar-colored band, so growing the window taller to
    // fit the album art doesn't turn the whole thing into a bigger bar; the
    // art alone pokes out past the strip against the desktop underneath.
    color: "transparent"
    exclusiveZone: 0
    visible: NowPlayingState.visible

    // Overlay (not the default Top layer Bar.qml sits on) so this paints in
    // front of the bar instead of merely stacking as another Top surface.
    WlrLayershell.layer: WlrLayer.Overlay

    anchors {
        top: true
        left: true
        right: true
    }
    // Confirmed live: Hyprland measures a zero-exclusive-zone top-anchored
    // surface's margin from the space already left over by Bar.qml's own
    // exclusiveZone (Theme.barHeight), regardless of this surface's own
    // layer — Overlay only changed paint order, not that avoidance offset,
    // so this still landed a full bar-height too low. Cancel it out
    // explicitly to actually land flush at y=0, overlapping the bar.
    margins.top: -Theme.barHeight

    // Tall enough to hold the 128px album art, which pokes out past the
    // bar's own 24px strip rather than being cropped down to fit it.
    readonly property int coverSize: 128
    implicitHeight: cover.visible ? coverSize : Theme.barHeight

    Rectangle {
        width: parent.width
        height: Theme.barHeight
        color: Theme.background
    }

    Image {
        id: cover
        readonly property string artUrl: NowPlayingState.spotify ? (NowPlayingState.spotify.trackArtUrl || "") : ""
        visible: artUrl !== ""
        anchors {
            top: parent.top
            left: parent.left
        }
        width: visible ? root.coverSize : 0
        height: root.coverSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: artUrl
    }

    Text {
        anchors {
            left: cover.visible ? cover.right : parent.left
            leftMargin: 8
            top: parent.top
            topMargin: (Theme.barHeight - height) / 2
        }
        text: NowPlayingState.shownPrefix + NowPlayingState.shownAnimated
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }
}

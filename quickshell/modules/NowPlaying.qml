import QtQuick
import Quickshell
import Quickshell.Services.Mpris

// Transient full-width strip, same height/position as Bar.qml (directly
// underneath it), that pops up for a few seconds whenever Spotify's track
// changes and shows the new title/artist — a "Now Playing" toast rather
// than a permanent widget, same pop()-then-auto-hide idea as VolumeOSD.
PanelWindow {
    id: root

    screen: Quickshell.screens[0]
    color: Theme.background
    exclusiveZone: 0
    visible: false

    anchors {
        top: true
        left: true
        right: true
    }
    // Not Theme.barHeight: Hyprland positions a zero-exclusive-zone
    // top-anchored surface's margin from the top of the space already left
    // over by Bar.qml's own exclusiveZone (Theme.barHeight), not from the
    // literal screen edge — a Theme.barHeight margin here stacked on top of
    // that reservation and pushed this a whole bar-height too far down.

    implicitHeight: Theme.barHeight

    // Matched by desktopEntry rather than identity ("Spotify") — MPRIS
    // identity strings aren't guaranteed stable across client versions,
    // but the desktop-entry id Spotify registers itself under is.
    readonly property var spotify: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; i++) {
            if (players[i].desktopEntry === "spotify") return players[i]
        }
        return null
    }

    function pop() {
        root.visible = true
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: 4000
        onTriggered: root.visible = false
    }

    // postTrackChanged (not trackChanged) — fires once the new track's
    // metadata (title/artist) is actually loaded, so the toast doesn't
    // briefly show the previous track's text for a frame.
    Connections {
        target: root.spotify
        function onPostTrackChanged() { root.pop() }
    }

    Text {
        anchors {
            left: parent.left
            leftMargin: 8
            verticalCenter: parent.verticalCenter
        }
        text: root.spotify
            ? (root.spotify.trackArtist
                ? root.spotify.trackTitle + "  —  " + root.spotify.trackArtist
                : root.spotify.trackTitle)
            : ""
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }


}

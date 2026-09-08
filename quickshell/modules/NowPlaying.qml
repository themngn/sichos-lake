import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Mpris

// Transient full-width strip, same height/position as Bar.qml, that pops up
// for a few seconds whenever Spotify's track changes and shows "artist:
// title" — a "Now Playing" toast rather than a permanent widget, same
// pop()-then-auto-hide idea as VolumeOSD.
PanelWindow {
    id: root

    screen: Quickshell.screens[0]
    color: Theme.background
    exclusiveZone: 0
    visible: false

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

    readonly property string trackArtist: root.spotify ? (root.spotify.trackArtist || "") : ""
    readonly property string trackTitle: root.spotify ? (root.spotify.trackTitle || "") : ""

    // "Artist: " prefix — frozen (not re-animated) across a track change
    // where the artist stays the same, so back-to-back tracks off the same
    // album don't re-erase/retype a name that hasn't actually changed.
    property string shownPrefix: ""
    // The part typeTimer is actively backspacing/typing: just the title
    // when the artist is unchanged, or the whole "artist: title" line as
    // one unit when the artist changed (or on a fresh pop).
    property string shownAnimated: ""
    property string lastArtist: ""

    function pop() {
        const wasVisible = root.visible
        root.visible = true
        hideTimer.restart()

        const artist = root.trackArtist
        const title = root.trackTitle
        const sameArtist = wasVisible && artist !== "" && artist === root.lastArtist
        root.lastArtist = artist

        if (sameArtist) {
            typeTimer.animateTo(title, false, "")
        } else {
            // Artist changed (or nothing shown yet): fold any frozen prefix
            // back into the animated portion first, so the backspace phase
            // erases the whole previous line instead of jump-cutting the
            // prefix away and only animating the title.
            if (root.shownPrefix !== "") {
                root.shownAnimated = root.shownPrefix + root.shownAnimated
                root.shownPrefix = ""
            }
            const target = artist ? (artist + ": " + title) : title
            typeTimer.animateTo(target, !wasVisible, artist)
        }
    }

    Timer {
        id: hideTimer
        interval: 4000
        onTriggered: root.visible = false
    }

    // Backspaces shownAnimated down to "" then types target back in, one
    // character per tick — skips the backspace half on a fresh pop (nothing
    // stale on screen to erase) or when target already matches. When
    // splitArtist is non-empty, finishing a full "artist: title" retype
    // re-splits it into shownPrefix/shownAnimated so the *next* same-artist
    // change can freeze the prefix and animate only the title.
    Timer {
        id: typeTimer
        interval: 28
        repeat: true
        property string target: ""
        property bool backspacing: false
        property string splitArtist: ""

        function animateTo(newTarget, skipBackspace, splitArtistOnComplete) {
            stop()
            if (skipBackspace) root.shownAnimated = ""
            splitArtist = splitArtistOnComplete
            if (newTarget === root.shownAnimated) {
                applySplit()
                return
            }
            target = newTarget
            backspacing = !skipBackspace && root.shownAnimated.length > 0
            start()
        }

        function applySplit() {
            if (splitArtist === "") return
            root.shownPrefix = splitArtist + ": "
            root.shownAnimated = root.shownAnimated.slice(splitArtist.length + 2)
            splitArtist = ""
        }

        onTriggered: {
            if (backspacing) {
                if (root.shownAnimated.length > 0) {
                    root.shownAnimated = root.shownAnimated.slice(0, -1)
                } else {
                    backspacing = false
                    if (target.length === 0) { stop(); applySplit() }
                }
            } else if (root.shownAnimated.length < target.length) {
                root.shownAnimated = target.slice(0, root.shownAnimated.length + 1)
            } else {
                stop()
                applySplit()
            }
        }
    }

    // postTrackChanged (not trackChanged) — fires once the new track's
    // metadata (title/artist) is actually loaded, so the toast doesn't
    // briefly show the previous track's text for a frame. isPlayingChanged
    // additionally pops on resume-from-pause (same track, no track change
    // at all, so postTrackChanged alone would miss it) — only on the
    // transition into playing, not out of it, so pausing doesn't pop it.
    Connections {
        target: root.spotify
        function onPostTrackChanged() { root.pop() }
        function onIsPlayingChanged() {
            if (root.spotify && root.spotify.isPlaying) root.pop()
        }
    }

    Image {
        id: cover
        readonly property string artUrl: root.spotify ? (root.spotify.trackArtUrl || "") : ""
        visible: artUrl !== ""
        anchors {
            left: parent.left
            leftMargin: 8
            verticalCenter: parent.verticalCenter
        }
        width: visible ? Theme.barHeight - 8 : 0
        height: Theme.barHeight - 8
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        source: artUrl
    }

    Text {
        anchors {
            left: cover.visible ? cover.right : parent.left
            leftMargin: 8
            verticalCenter: parent.verticalCenter
        }
        text: root.shownPrefix + root.shownAnimated
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        color: Theme.text
    }


}

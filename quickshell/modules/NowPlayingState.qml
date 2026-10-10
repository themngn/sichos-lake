pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Shared "now playing" toast state, factored out of NowPlaying.qml so it can
// be driven once and rendered by one PanelWindow per screen (see shell.qml's
// Variants) instead of a single window pinned to Quickshell.screens[0] --
// without this, the toast only ever popped up on one monitor regardless of
// which screen the user was actually looking at.
QtObject {
    id: root

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

    property bool visible: false

    // Local file:// copy of the current track's cover, or "" while none is
    // downloaded yet. NowPlaying.qml used to point its Image straight at
    // Spotify's https trackArtUrl, which crashed quickshell outright
    // (SIGSEGV in QQuickPixmap::clear -> QObject::disconnect, confirmed
    // from the crash report) on a track change: each per-screen window
    // had its own async network load in flight, and switching source
    // mid-load disconnected from a reply Qt had already torn down.
    // Downloading once here and handing every window a local file (loaded
    // synchronously there) leaves no network reply for Qt to clean up.
    property string artPath: ""
    readonly property string artUrl: root.spotify ? (root.spotify.trackArtUrl || "") : ""
    readonly property string _artDir: Quickshell.env("XDG_RUNTIME_DIR") + "/sichos-nowplaying"
    property string _artFetching: ""

    onArtUrlChanged: {
        root.artPath = ""
        if (root.artUrl !== "" && !_artProc.running) root._fetchArt()
    }

    function _fetchArt() {
        root._artFetching = root.artUrl
        // Spotify's art URLs end in a stable per-image hash, so it doubles
        // as the file name; everything else in the dir is a previous
        // track's cover and gets dropped so this never grows.
        const name = root.artUrl.replace(/.*\//, "").replace(/[^A-Za-z0-9]/g, "") || "cover"
        _artProc.dest = root._artDir + "/" + name
        _artProc.command = ["sh", "-c",
            'mkdir -p "$1" && find "$1" -type f ! -path "$2" -delete; [ -s "$2" ] || { curl -sfL --max-time 15 -o "$2.part" "$3" && mv "$2.part" "$2"; }',
            "sh", root._artDir, _artProc.dest, root.artUrl]
        _artProc.running = true
    }

    property Process _artProc: Process {
        id: _artProc
        property string dest: ""
        onExited: (code) => {
            // Track changed again mid-download -- fetch the new one instead
            // of showing a stale cover.
            if (root._artFetching !== root.artUrl) {
                if (root.artUrl !== "") root._fetchArt()
                return
            }
            if (code === 0) root.artPath = "file://" + _artProc.dest
        }
    }

    Component.onCompleted: if (root.artUrl !== "") root._fetchArt()

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

    property Timer hideTimer: Timer {
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
    property Timer typeTimer: Timer {
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
    property Connections _conn: Connections {
        target: root.spotify
        function onPostTrackChanged() { root.pop() }
        function onIsPlayingChanged() {
            if (root.spotify && root.spotify.isPlaying) root.pop()
        }
    }
}

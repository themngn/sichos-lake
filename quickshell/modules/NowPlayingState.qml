pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// Shared "now playing" toast state, factored out of NowPlaying.qml so it can
// be driven once and rendered by every screen's bar (Bar.qml swaps it in for
// the workspaces) in lockstep instead of each animating on its own.
QtObject {
    id: root

    // Matched by desktopEntry rather than identity ("Spotify") — MPRIS
    // identity strings aren't guaranteed stable across client versions,
    // but the desktop-entry id Spotify registers itself under is.
    readonly property var spotify: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; i++) {
            if (players[i].desktopEntry === "spotify" && !root.isProxy(players[i])) return players[i]
        }
        return null
    }

    // The player that most recently started playing, kept after it pauses:
    // the Control Center's large card shows it, so pausing Spotify doesn't
    // swap the card to whatever else has a track loaded -- only another
    // player starting does. Null once that player's gone (closed).
    property var lastActive: null
    readonly property var _playing: Mpris.players.values.filter(p => p.isPlaying && !root.isProxy(p))
    property var _prevPlaying: []
    on_PlayingChanged: {
        const fresh = root._playing.filter(p => !root._prevPlaying.includes(p))
        if (fresh.length > 0) root.lastActive = fresh[fresh.length - 1]
        else if (!root.lastActive && root._playing.length > 0) root.lastActive = root._playing[0]
        root._prevPlaying = root._playing
    }

    // Covers a player embeds as a data: URL (Telegram), decoded once into a
    // file under $XDG_RUNTIME_DIR: ColorQuantizer can't load data: URLs
    // ("Failed to load image from data:image/jpeg;base64,..."), so the
    // cards' tint stayed grey. localArt() hands out the file once it's
    // written and the data: URL itself until then (Image shows that fine).
    // It's called from the cards' bindings, so it only reads: the write is
    // queued with Qt.callLater (queueing inside it was a binding loop), and
    // the payload goes to base64 on stdin -- a cover can be over the kernel's
    // 128 KiB limit for a single argument ("Process failed to start").
    readonly property string _dataArtDir: Quickshell.env("XDG_RUNTIME_DIR") + "/sichos-mpris-art"
    property var _dataArtDone: ({})
    property var _dataArtQueue: []
    // url -> key, so a binding re-evaluating doesn't hash the whole image again.
    property var _dataArtKeys: ({})
    function _dataArtKey(u) {
        let k = root._dataArtKeys[u]
        if (k === undefined) { k = Qt.md5(u); root._dataArtKeys[u] = k }
        return k
    }
    function localArt(u) {
        if (!u.startsWith("data:image/")) return u
        const key = root._dataArtKey(u)
        if (root._dataArtDone[key]) return "file://" + root._dataArtDir + "/" + key
        Qt.callLater(root._queueDataArt, u)
        return u
    }
    function _queueDataArt(u) {
        const key = root._dataArtKey(u)
        if (root._dataArtDone[key] || root._dataArtQueue.some(q => q.key === key)) return
        root._dataArtQueue = root._dataArtQueue.concat([{ key: key, url: u }])
        root._nextDataArt()
    }
    function _nextDataArt() {
        if (root._dataArtProc.running || root._dataArtQueue.length === 0) return
        const q = root._dataArtQueue[0]
        root._dataArtProc.key = q.key
        root._dataArtProc.command = ["sh", "-c",
            'mkdir -p "$1" && base64 -d > "$1/$2.tmp" && mv "$1/$2.tmp" "$1/$2"',
            "sh", root._dataArtDir, q.key]
        root._dataArtProc.stdinEnabled = true
        root._dataArtProc.running = true
        root._dataArtProc.write(q.url.slice(q.url.indexOf(",") + 1))
        // Closing stdin is what ends base64's input.
        root._dataArtProc.stdinEnabled = false
    }
    property Process _dataArtProc: Process {
        property string key: ""
        onExited: (code) => {
            const key = root._dataArtProc.key
            root._dataArtQueue = root._dataArtQueue.filter(q => q.key !== key)
            if (code === 0) {
                const done = Object.assign({}, root._dataArtDone)
                done[key] = true
                root._dataArtDone = done
            }
            Qt.callLater(root._nextDataArt)
        }
    }

    // playerctld re-exports the active player under its own bus name (same
    // identity, desktop entry and track), so it's never a player of its own.
    function isProxy(p) {
        return !!p && p.dbusName === "org.mpris.MediaPlayer2.playerctld"
    }

    // A player's name as its app calls itself: the desktop entry's Name,
    // since MPRIS Identity can be anything -- Firefox's is "Mozilla
    // org.mozilla.firefox". Identity only when there's no entry.
    function appName(p) {
        if (!p) return ""
        // Read so a binding calling this re-runs once the entries have
        // loaded (byId alone isn't a dependency; the first call can be early).
        void DesktopEntries.applications.values.length
        const e = p.desktopEntry ? DesktopEntries.byId(p.desktopEntry) : null
        return e && e.name ? e.name : (p.identity || "")
    }

    readonly property string trackArtist: root.spotify ? (root.spotify.trackArtist || "") : ""
    readonly property string trackTitle: root.spotify ? (root.spotify.trackTitle || "") : ""

    property bool visible: false

    // Local file:// copy of the current track's cover, or "" while none is
    // downloaded yet. Used by QuickSettings' media cards (the bar toast has
    // no cover anymore). NowPlaying.qml used to point its Image straight at
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
    // Artist of the line actually on screen (lastArtist already holds the
    // next one while the old line is still being erased), so NowPlaying.qml
    // can style the artist and title differently: the first
    // shownArtist.length characters, then ": ", are the artist. Switched
    // only when the line is empty, between erasing and typing.
    property string shownArtist: ""

    function pop() {
        // Popping mid-erase: the line is still up, so treat it as visible
        // and let the usual backspace/retype take over from what's left.
        root.hiding = false
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

    // Set while the line is being backspaced away before hiding, so the
    // hide mirrors the show (typed in, erased out) instead of just fading.
    // A pop() mid-erase clears it and types the new line back in.
    property bool hiding: false

    property Timer hideTimer: Timer {
        id: hideTimer
        interval: 4000
        onTriggered: {
            if (root.shownPrefix !== "") {
                root.shownAnimated = root.shownPrefix + root.shownAnimated
                root.shownPrefix = ""
            }
            root.hiding = true
            typeTimer.animateTo("", false, "")
            // Nothing on screen to erase: hide straight away.
            if (!typeTimer.running) root._finishHide()
        }
    }

    function _finishHide() {
        root.hiding = false
        root.visible = false
    }

    // Backspaces shownAnimated down to "" then types target back in, one
    // character per tick — skips the backspace half on a fresh pop (nothing
    // stale on screen to erase) or when target already matches. When
    // splitArtist is non-empty, finishing a full "artist: title" retype
    // re-splits it into shownPrefix/shownAnimated so the *next* same-artist
    // change can freeze the prefix and animate only the title.
    property Timer typeTimer: Timer {
        id: typeTimer
        interval: 14
        repeat: true
        property string target: ""
        property bool backspacing: false
        property string splitArtist: ""
        property string nextArtist: ""

        function animateTo(newTarget, skipBackspace, splitArtistOnComplete) {
            stop()
            splitArtist = splitArtistOnComplete
            // A full-line retype (or the hide) always passes the new line's
            // artist here ("" for none); a same-artist title change passes
            // "" too, but its frozen prefix keeps the line from ever going
            // empty, so shownArtist isn't touched then.
            nextArtist = splitArtistOnComplete
            if (skipBackspace) {
                root.shownAnimated = ""
                root.shownArtist = nextArtist
            }
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
                    if (root.shownPrefix === "") root.shownArtist = nextArtist
                    if (target.length === 0) {
                        stop()
                        applySplit()
                        if (root.hiding) root._finishHide()
                    }
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

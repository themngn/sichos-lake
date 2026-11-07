import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

// One thing making sound, for the Control Center's source cards: an MPRIS
// player (`player`) and/or an app's PipeWire streams (`app`, an AudioInfo
// group). Either can be missing: a game or call has no player, and a player
// that hasn't played yet has no stream. Holds what the card and the banner
// both show, so a source keeps one state while it moves between the two.
QtObject {
    id: src
    property var player: null
    property var app: null
    // root.artFor(player) in QuickSettings; a game's comes from AudioInfo.
    property string artSource: ""
    // On screen: gates the position poll.
    property bool shown: false

    readonly property bool isPlayer: !!src.player
    readonly property var game: src.app ? AudioInfo.gameFor(src.app) : null
    readonly property string _wantedArt: src.isPlayer ? src.artSource : (src.game && src.game.art ? "file://" + src.game.art : "")
    // The cover shown. On a track change the old one goes before the new one
    // has downloaded (NowPlayingState.artPath), which made the banner shrink to
    // a card and grow back: keep showing the old one for a second first. A
    // track that really has no cover gets there after that.
    property string art: ""
    on_WantedArtChanged: src._syncArt()
    Component.onCompleted: src.art = src._wantedArt
    function _syncArt() {
        if (src._wantedArt !== "") {
            _artHold.stop()
            src.art = src._wantedArt
        } else if (src.art !== "") {
            _artHold.restart()
        }
    }
    property Timer _artHold: Timer {
        id: _artHold
        interval: 1000
        onTriggered: src.art = src._wantedArt
    }
    readonly property string appName: src.isPlayer ? NowPlayingState.appName(src.player) : (src.app ? src.app.name : "")
    readonly property string title: src.isPlayer ? (src.player.trackTitle || src.appName)
        : (src.game && src.game.name ? src.game.name : src.appName)
    readonly property string subtitle: src.isPlayer
        ? [src.player.trackArtist || "", src.appName].filter(s => s !== "" && s !== src.title).join(" · ")
        : (src.game ? "Game" : "Playing audio")
    // A stream only has an "is it playing" through its player; a bare stream
    // only shows up here while it's live.
    readonly property bool isPlaying: src.isPlayer ? src.player.isPlaying : true
    readonly property bool hasLength: src.isPlayer && src.length > 0
    readonly property bool canSeek: src.hasLength && src.player.canSeek
    readonly property real progress: src.hasLength ? Math.max(0, Math.min(1, src.position / src.length)) : 0
    readonly property bool canSkip: src.isPlayer && (src.player.canGoPrevious || src.player.canGoNext)

    // The app's icon, for a source with no cover.
    readonly property string icon: {
        void DesktopEntries.applications.values.length
        const e = src.isPlayer && src.player.desktopEntry ? DesktopEntries.byId(src.player.desktopEntry) : null
        if (e && e.icon) {
            if (e.icon.startsWith("/")) return "file://" + e.icon
            const path = Quickshell.iconPath(e.icon, true)
            if (path) return path
        }
        return src.app ? src.app.icon : ""
    }

    readonly property var audio: src.app && src.app.node ? src.app.node.audio : null
    readonly property bool muted: !!(src.audio && src.audio.muted)
    readonly property real volume: src.audio ? src.audio.volume : 1

    // Height only, so implicitWidth keeps the aspect. A local file, loaded
    // synchronously like every cover here (see NowPlayingState.artPath).
    property Image _probe: Image {
        source: src.art
        sourceSize.height: 112
        asynchronous: false
        visible: false
    }
    readonly property bool hasArt: src.art !== "" && src._probe.status === Image.Ready
    readonly property real ratio: src.hasArt && src._probe.implicitHeight > 0 ? src._probe.implicitWidth / src._probe.implicitHeight : 1
    // A 1:1 cover gets the record; anything wider fills the slot.
    readonly property bool square: src.hasArt && src.ratio < 1.2

    // A theme icon as a file, which is all ColorQuantizer can read (see
    // scripts/icon-file.py). Only looked up for a source with no cover.
    readonly property string _iconName: src.art === "" && src.icon.startsWith("image://icon/")
        ? src.icon.slice("image://icon/".length).split("?")[0] : ""
    property string _iconPath: ""
    readonly property string _iconFile: src.icon.startsWith("file://") ? src.icon
        : src._iconPath !== "" ? "file://" + src._iconPath : ""
    on_IconNameChanged: {
        src._iconPath = ""
        if (src._iconName !== "") { _iconProc.running = false; _iconProc.running = true }
    }
    property Process _iconProc: Process {
        id: _iconProc
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/icon-file.py", src._iconName]
        stdout: StdioCollector { onStreamFinished: src._iconPath = text.trim() }
    }

    // The card's colour: the most saturated of the cover's (or the icon's)
    // eight quantized colours, pinned to a dark lightness so white text
    // always reads on it. Not a data: URL, which it can't load -- the file
    // follows, see NowPlayingState.localArt.
    property ColorQuantizer _quant: ColorQuantizer {
        source: {
            const u = src.art !== "" ? src.art : src._iconFile
            return u.startsWith("data:") ? "" : u
        }
        depth: 3
        rescaleSize: 64
    }
    readonly property var _best: {
        let best = null, score = -1
        for (const c of src._quant.colors || []) {
            const s = c.hslSaturation * (1 - Math.abs(c.hslLightness - 0.5))
            if (s > score) { score = s; best = c }
        }
        return best
    }
    readonly property bool hasTint: !!src._best
    readonly property color tint: src.hasTint
        ? Qt.hsla(Math.max(0, src._best.hslHue), Math.min(src._best.hslSaturation, 0.55), 0.22, 1) : Theme.controlFill
    readonly property color tintDeep: src.hasTint
        ? Qt.hsla(Math.max(0, src._best.hslHue), Math.min(src._best.hslSaturation, 0.55) * 0.8, 0.12, 1) : Theme.controlFill

    // Firefox only reports a video's time some of the time: on YouTube, seconds
    // into playing (or after a seek) Position drops to 0 and mpris:length goes
    // from the metadata, until the next pause brings both back, correct (seen on
    // the bus). So these keep the last real values for the track and count on
    // from them while it plays; a seek in the page during such a gap only shows
    // at the next pause.
    property real length: 0
    property real position: 0
    property real _syncedAt: 0
    property bool _wasPlaying: false
    property real _pausedAt: 0
    readonly property bool _reports: src.isPlayer && src.player.lengthSupported && src.player.length > 0
    readonly property bool _playing: src.isPlayer && src.player.isPlaying
    readonly property string _trackKey: src.isPlayer ? src.player.trackTitle + "|" + (src.player.metadata["xesam:url"] || "") : ""
    on_ReportsChanged: src._sync()
    on_PlayingChanged: {
        if (!src._playing) src._pausedAt = Date.now()
        src._sync()
    }
    on_TrackKeyChanged: {
        src.length = 0
        src.position = 0
        src._wasPlaying = false
        src._sync()
    }
    function _sync() {
        const now = Date.now()
        // Right after a pause MprisPlayer.position still says where the track
        // last resumed, until the real one arrives (under a second, checked
        // live): read then, the time jumps back and forward again on resume.
        const settling = !src._playing && now - src._pausedAt < 600
        if (src._reports && !settling) {
            src.length = src.player.length
            src.position = src.player.position
        } else if (src.length > 0 && src._wasPlaying) {
            src.position = Math.min(src.length, src.position + (now - src._syncedAt) / 1000 * (src.player ? src.player.rate : 1))
        }
        src._syncedAt = now
        src._wasPlaying = src._playing
    }
    // Hidden as well, more slowly: a gap can start while the hub is closed. On
    // screen while paused too, for the real position after a pause or a seek.
    property Timer _poll: Timer {
        interval: src.shown ? 1000 : 5000
        repeat: true
        running: src.isPlayer && (src._playing || src.shown)
        onTriggered: src._sync()
    }
    function seekTo(fraction) {
        const target = src.length * Math.max(0, Math.min(1, fraction))
        src.player.position = target
        src.position = target
        src._syncedAt = Date.now()
    }

    function setVolume(v) { if (src.app) AudioInfo.setAppVolume(src.app, v) }
    function toggleMute() { if (src.app) AudioInfo.setAppMuted(src.app, !src.muted) }
    // This source leads and plays alone: it becomes NowPlayingState's
    // lastActive, and the others pause -- switching to it, not mixing it in.
    function makeLead() {
        const p = src.player
        if (!p) return
        NowPlayingState.lastActive = p
        for (const o of Mpris.players.values)
            if (o !== p && o.isPlaying && o.canPause && !NowPlayingState.isProxy(o)) o.pause()
        if (!p.isPlaying && p.canPlay) p.play()
    }
}

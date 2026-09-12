pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared state that needs to be visible from more than one top-level window
// (the per-screen Bar and the single Launcher instance), so it can't just
// live as a local property on either one.
QtObject {
    id: root

    // Name of currently active open hover popup (e.g. "ai-model-usage", "sunset", "idle", "weather", "calendar", or "")
    // When any popup is open, hovering over another bar widget opens it IMMEDIATELY without delay.
    property string activePopup: ""

    // Screen (Quickshell ScreenInfo.name) that opened activePopup. Each per-screen
    // Bar instantiates its own copy of every widget sharing the same popupId, so
    // without this a hover on one monitor would flip activePopup and pop the same
    // widget's card open on every other monitor too.
    property string activePopupScreen: ""

    property bool idleActive: false

    // Screen (Quickshell ScreenInfo.name) where the notification center
    // panel is currently open, or "" if closed. Bar.qml instantiates one
    // NotificationCenter (and its own PanelWindow) per screen, same as
    // every other right-side widget -- this makes sure only one of those
    // panels is ever visible at a time, on whichever screen's bell icon
    // was actually clicked, instead of each one just always rendering on
    // Quickshell.screens[0] regardless of which bar it belongs to.
    property string notificationCenterScreen: ""

    // Whether the bar/terminal transparency toggle is in "opaque" mode.
    // kitty.conf's background_opacity line is the actual source of truth
    // (see toggle-transparency.py) — this is just loaded from it once at
    // startup so the bar and its toggle icon open already matching
    // whatever kitty windows currently show, then flipped locally by the
    // toggle itself (see Bar.qml's TransparencyToggle).
    property bool transparencyOpaque: false

    readonly property FileView _kittyConf: FileView {
        path: Quickshell.env("HOME") + "/.config/kitty/kitty.conf"
        printErrors: false
    }

    function _loadTransparency() {
        const m = /background_opacity\s+([\d.]+)/.exec(root._kittyConf.text())
        root.transparencyOpaque = m ? (+m[1] >= 1.0) : false
    }

    // Whether the filter is warm right now — the single source of truth
    // for the light, not a value derived from some other mode enum.
    // Written by exactly three things: SunsetToggle's pill/On-Off buttons
    // (forceSunsetWarm), a schedule boundary crossing while
    // sunsetScheduleFollow is true (_checkScheduleBoundary), and
    // setScheduleFollow's own immediate resync when re-enabling follow.
    // Doesn't persist across a quickshell restart, same as idleActive above.
    property bool sunsetWarm: false

    // Whether the schedule (hyprsunset.conf's day/night profile times) is
    // allowed to drive sunsetWarm at its own boundary crossings. Completely
    // independent of sunsetWarm itself -- toggling this never changes the
    // light (see setScheduleFollow), and forcing the light via the pill or
    // On/Off buttons never changes this. That independence is the whole
    // point: turn schedule off and a force stays put until the next
    // explicit force; turn it back on and the schedule resumes from
    // wherever the clock currently is, ignoring whatever was forced while
    // it was off.
    property bool sunsetScheduleFollow: true

    // Last manually-set warmth, shown by the popup's slider regardless of
    // sunsetWarm/sunsetScheduleFollow. Seeded from hyprsunset.conf's night
    // profile at startup (see _loadSunsetKelvin) so it survives a
    // quickshell restart even though the two properties above don't — the
    // file is the one place this actually persists.
    property int sunsetKelvin: 2500

    readonly property FileView _sunsetConf: FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/hyprsunset.conf"
        printErrors: false
    }

    // Single spot that both writes sunsetWarm and pushes the matching
    // hyprctl command, so the pill, the boundary check, and re-enabling
    // the schedule can't drift from each other on which command means what.
    function _applyWarm(v) {
        root.sunsetWarm = v
        Quickshell.execDetached(v
            ? ["hyprctl", "hyprsunset", "temperature", String(root.sunsetKelvin)]
            : ["hyprctl", "hyprsunset", "identity"])
    }

    // Called by the pill's click and the popup's explicit On/Off buttons.
    // Never touches sunsetScheduleFollow -- forcing a state is meant to be
    // a plain override that sticks until the next explicit force or
    // schedule boundary, not something that silently unchecks "Follow
    // schedule" in the menu.
    function forceSunsetWarm(v) {
        if (root.sunsetWarm === v) return
        root._applyWarm(v)
    }

    // Called by the popup's "Follow schedule" checkbox. Turning follow off
    // makes no change to the light at all -- sunsetWarm already holds
    // whatever it currently is, it just stops being written until follow
    // is re-enabled. Turning it on resyncs immediately to whatever the
    // schedule currently says (rather than waiting up to 30s for the next
    // timer tick) and hands the last force's value back to the daemon.
    function setScheduleFollow(follow) {
        if (root.sunsetScheduleFollow === follow) return
        root.sunsetScheduleFollow = follow
        if (follow) {
            const isNight = root._computePhaseIsNight()
            root._lastPhase = isNight
            root._applyWarm(isNight)
        }
    }

    // QV4 (this Qt's JS engine) doesn't have String.matchAll — walk exec() instead.
    function _computePhaseIsNight() {
        const re = /time\s*=\s*(\d{1,2}):(\d{2})/g
        const matches = []
        let m
        while ((m = re.exec(root._sunsetConf.text())) !== null) matches.push(m)
        const dayMin = matches[0] ? (+matches[0][1]) * 60 + (+matches[0][2]) : 7 * 60
        const nightMin = matches[1] ? (+matches[1][1]) * 60 + (+matches[1][2]) : 23 * 60
        const now = new Date()
        const nowMin = now.getHours() * 60 + now.getMinutes()
        return nightMin > dayMin
            ? (nowMin >= nightMin || nowMin < dayMin)
            : (nowMin >= nightMin && nowMin < dayMin)
    }

    // Night/day phase as of the last check, so a boundary crossing can be
    // detected (isNight !== _lastPhase) instead of recomputing sunsetWarm
    // unconditionally on every tick -- an unconditional recompute would
    // stomp a manual force back to the schedule's value every 30 seconds
    // even with sunsetScheduleFollow true, which defeats "stays forced
    // until the next explicit force or boundary crossing".
    property bool _lastPhase: false
    property bool _phaseInitialized: false

    function _checkScheduleBoundary() {
        const isNight = root._computePhaseIsNight()
        if (!root._phaseInitialized) {
            root._phaseInitialized = true
            root._lastPhase = isNight
            // Seed only -- no push. hyprsunset already applied whichever
            // profile this is at its own startup (see hyprsunset.conf's
            // header comment), so pushing here would just be a redundant
            // gamma call for zero visible change.
            if (root.sunsetScheduleFollow) root.sunsetWarm = isNight
            return
        }
        if (isNight === root._lastPhase) return
        root._lastPhase = isNight
        if (root.sunsetScheduleFollow) root._applyWarm(isNight)
    }

    // Re-checks every 30s so a schedule boundary crossing is caught without
    // needing a click.
    property Timer _sunsetTimer: Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._checkScheduleBoundary()
    }

    // Reads the persisted warmth once at startup so the slider opens on the
    // actually-configured value instead of always starting from the
    // in-memory default — hyprsunset.conf is the only place this survives
    // a quickshell restart.
    function _loadSunsetKelvin() {
        const m = /temperature\s*=\s*(\d+)/.exec(root._sunsetConf.text())
        if (m) root.sunsetKelvin = +m[1]
    }

    Component.onCompleted: {
        root._loadSunsetKelvin()
        root._loadTransparency()
    }

    // Dragging the popup's slider updates the displayed value on every
    // mouse move (cheap, just a property), but the disk write + hyprctl
    // spawn are debounced behind a short timer instead of firing per pixel
    // — a fast drag generates dozens of position-changed events a second,
    // and each hyprctl call makes hyprsunset push a new gamma table to the
    // compositor, which is a synchronous DRM call that visibly stutters
    // the cursor for a frame or two. Cutting the call rate is the only
    // lever available here — the stutter-per-call itself is inherent to
    // how gamma changes get applied.
    property int _pendingKelvin: -1

    property Timer _kelvinCommitTimer: Timer {
        interval: 200
        repeat: false
        onTriggered: root._commitKelvin()
    }

    // Called from Bar.qml's onSetTemperature. Deliberately leaves
    // sunsetWarm/sunsetScheduleFollow untouched — presetting tonight's
    // warmth shouldn't itself force the light on or knock "Follow
    // schedule" off.
    function setSunsetKelvin(k) {
        root.sunsetKelvin = k
        root._pendingKelvin = k
        root._kelvinCommitTimer.restart()
    }

    function _commitKelvin() {
        if (root._pendingKelvin < 0) return
        const k = root._pendingKelvin
        root._pendingKelvin = -1
        root._sunsetConf.setText(root._sunsetConf.text().replace(/temperature\s*=\s*\d+/, "temperature = " + k))
        // Only worth an actual gamma push if it has a visible effect right
        // now — dialing in tonight's warmth while the filter is currently
        // off shouldn't stutter the cursor for a change nothing on screen
        // reflects yet.
        if (root.sunsetWarm)
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(k)])
    }
}

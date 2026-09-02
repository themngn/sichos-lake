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

    // User's chosen sunset mode, from SunsetToggle's popup: "schedule"
    // (follow hyprsunset.conf's day/night profiles), "on" (a warm filter
    // forced on, whatever kelvin), or "off" (identity forced, no filter).
    // Doesn't persist across a quickshell restart, same as idleActive above.
    property string sunsetMode: "schedule"

    // Last manually-set warmth, kept independent of sunsetMode so the
    // SunsetToggle popup's slider still shows a sensible value (and
    // reapplying "on" reuses it) even after switching to "schedule" or
    // "off" and back. Seeded from hyprsunset.conf's night profile at
    // startup (see _loadSunsetKelvin) so it survives a quickshell restart
    // even though sunsetMode itself doesn't — the file is the one place
    // this actually persists.
    property int sunsetKelvin: 2500

    // Whether the filter is ACTUALLY warm right now — true for "on", false
    // for "off", and for "schedule" computed from hyprsunset.conf's two
    // profile times against the current clock. This (not sunsetMode) is
    // what SunsetToggle's icon brightness should follow, so picking
    // "Follow schedule" during the day doesn't light the icon up white for
    // a filter that isn't actually doing anything until night.
    property bool sunsetWarm: false

    readonly property FileView _sunsetConf: FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/hyprsunset.conf"
        printErrors: false
    }

    function _recomputeSunsetWarm() {
        if (root.sunsetMode === "on") { root.sunsetWarm = true; return }
        if (root.sunsetMode === "off") { root.sunsetWarm = false; return }

        // QV4 (this Qt's JS engine) doesn't have String.matchAll — walk exec() instead.
        const re = /time\s*=\s*(\d{1,2}):(\d{2})/g
        const matches = []
        let m
        while ((m = re.exec(root._sunsetConf.text())) !== null) matches.push(m)
        const dayMin = matches[0] ? (+matches[0][1]) * 60 + (+matches[0][2]) : 7 * 60
        const nightMin = matches[1] ? (+matches[1][1]) * 60 + (+matches[1][2]) : 23 * 60
        const now = new Date()
        const nowMin = now.getHours() * 60 + now.getMinutes()
        root.sunsetWarm = nightMin > dayMin
            ? (nowMin >= nightMin || nowMin < dayMin)
            : (nowMin >= nightMin && nowMin < dayMin)
    }

    // Reads the persisted warmth once at startup so the slider opens on the
    // actually-configured value instead of always starting from the
    // in-memory default — hyprsunset.conf is the only place this survives
    // a quickshell restart.
    function _loadSunsetKelvin() {
        const m = /temperature\s*=\s*(\d+)/.exec(root._sunsetConf.text())
        if (m) root.sunsetKelvin = +m[1]
    }

    onSunsetModeChanged: root._recomputeSunsetWarm()

    // Also re-checks every 30s so the icon flips on its own at the
    // schedule's day/night boundary without needing a click.
    property Timer _sunsetTimer: Timer {
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._recomputeSunsetWarm()
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

    // Called from Bar.qml's onSetTemperature — dragging the slider always
    // implies "on" (same as turning a real thermostat dial), so this owns
    // both the mode switch and the debounced persist/apply.
    function setSunsetKelvin(k) {
        root.sunsetMode = "on"
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
        // now — dialing in tonight's warmth while it's still daytime
        // shouldn't stutter the cursor for a change nothing on screen
        // reflects until sunset.
        if (root.sunsetMode === "on" || (root.sunsetMode === "schedule" && root.sunsetWarm))
            Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(k)])
    }
}

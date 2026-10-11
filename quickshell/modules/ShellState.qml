pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Shared state that needs to be visible from more than one top-level window
// (the per-screen Bar and the single Launcher instance), so it can't just
// live as a local property on either one.
QtObject {
    id: root

    // Name of currently active open hover popup (e.g. "ai-model-usage", "sunset", "idle", "weather", "calendar", or "")
    // When any popup is open, hovering over another bar widget opens it IMMEDIATELY without delay.
    // Which OSD (VolumeOSD, BacklightOSD, ...) popped most recently. They all
    // share one spot on screen, so each hides itself as soon as a different
    // one takes over instead of stacking on top of it.
    property string activeOsd: ""
    property string activePopup: ""

    // Screen (Quickshell ScreenInfo.name) that opened activePopup. Each per-screen
    // Bar instantiates its own copy of every widget sharing the same popupId, so
    // without this a hover on one monitor would flip activePopup and pop the same
    // widget's card open on every other monitor too.
    property string activePopupScreen: ""

    // While a popup that closes only on a click outside is open (the
    // Control Center: QuickSettings.qml sets its page ids here), other bar
    // popups mustn't take over on hover. Every widget's hover logic -- and
    // user-local custom widgets' -- assigns activePopup/activePopupScreen
    // directly, so rather than teaching each one, a switch to anything
    // outside the group is reverted here. Widgets set the screen right after
    // the popup id in the same tick, so that follow-up is reverted too.
    // Text entry inside a bar popup (Wi-Fi password, Bluetooth PIN). A
    // popup surface never gets keyboard focus of its own, so while a field
    // wants input, the bar on keySinkScreen takes exclusive keyboard focus
    // and passes every key to keySink.handleKey(event) (Bar.qml).
    property var keySink: null
    property string keySinkScreen: ""

    property var popupLockGroup: []
    property string _lockedPopup: ""
    property string _lockedScreen: ""
    property bool _revertScreen: false
    onActivePopupChanged: {
        if (root.popupLockGroup.length === 0 || root.activePopup === "") return
        if (root.popupLockGroup.includes(root.activePopup)) {
            root._lockedPopup = root.activePopup
            return
        }
        root._revertScreen = true
        Qt.callLater(() => { root._revertScreen = false })
        root.activePopup = root._lockedPopup
    }
    onActivePopupScreenChanged: {
        if (root._revertScreen && root.activePopupScreen !== root._lockedScreen)
            root.activePopupScreen = root._lockedScreen
        else if (root.popupLockGroup.includes(root.activePopup))
            root._lockedScreen = root.activePopupScreen
    }
    // `quickshell ipc call controlcenter toggle` (SUPER+N, keybindings.lua):
    // opens the Control Center on the focused monitor, or closes it.
    property IpcHandler _controlCenterIpc: IpcHandler {
        target: "controlcenter"
        function toggle(): void {
            if (root.popupLockGroup.includes(root.activePopup)) {
                root.activePopup = ""
                return
            }
            const mon = Hyprland.focusedMonitor
            if (!mon) return
            root.activePopupScreen = mon.name
            root.activePopup = "quicksettings"
        }
    }
    function lockPopups(group, popup, screen) {
        root._lockedPopup = popup
        root._lockedScreen = screen
        root.popupLockGroup = group
    }

    property bool idleActive: false

    // Do-not-disturb: suppresses new toast popups (Notifications.qml) while
    // on. Doesn't touch NotificationHistory -- everything still lands in
    // the bell icon's drawer, it's only the on-screen popup that's
    // skipped, same "nothing lost, just not interrupting you" semantics as
    // GNOME/Windows DND. Doesn't persist across a quickshell restart, same
    // as idleActive/sunsetWarm above.
    property bool notificationsMuted: false
    // When a timed mute (NotificationMutePopup's "30 min"/"1 h"/...) ends,
    // as epoch ms; 0 = muted indefinitely (or not muted at all).
    property real notificationsMutedUntil: 0

    // minutes > 0 mutes until now + minutes; minutes = 0 mutes indefinitely.
    // Every unmute (pill click, popup, timer) clears the deadline too, so a
    // later plain mute doesn't inherit a stale one.
    function setNotificationsMuted(muted, minutes) {
        root.notificationsMutedUntil = muted && minutes > 0 ? Date.now() + minutes * 60000 : 0
        root.notificationsMuted = muted
    }
    function muteNotificationsUntil(epochMs) {
        root.notificationsMutedUntil = epochMs
        root.notificationsMuted = true
    }
    // Checked once a minute (plus on every change) rather than a one-shot
    // Timer at the deadline -- a timer's interval is wall-clock-blind
    // across suspend, so after a laptop sleep past the deadline a one-shot
    // would still wait out its remaining interval.
    property Timer _dndTimer: Timer {
        running: root.notificationsMuted && root.notificationsMutedUntil > 0
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (Date.now() >= root.notificationsMutedUntil) root.setNotificationsMuted(false, 0)
        }
    }

    // Idle-dim state, driven purely over IPC (`quickshell ipc call idledim
    // dim`/`undim`) from hypridle.conf's on-timeout/on-resume — see
    // IdleDimOverlay.qml for why this replaced a brightnessctl backlight
    // dim. Lives here rather than on the overlay itself since one overlay
    // instance exists per screen (shell.qml's Variants) and they all need
    // to fade in/out in lockstep, same reasoning as NowPlayingState.
    property bool idleDimActive: false

    property IpcHandler _idleDimIpc: IpcHandler {
        target: "idledim"
        function dim() { root.idleDimActive = true }
        function undim() { root.idleDimActive = false }
    }

    // Screen (Quickshell ScreenInfo.name) where the notification center
    // panel is currently open, or "" if closed. Bar.qml instantiates one
    // NotificationCenter (and its own PanelWindow) per screen, same as
    // every other right-side widget -- this makes sure only one of those
    // panels is ever visible at a time, on whichever screen's bell icon
    // was actually clicked, instead of each one just always rendering on
    // Quickshell.screens[0] regardless of which bar it belongs to.
    property string notificationCenterScreen: ""

    // Screen (Quickshell ScreenInfo.name) the bar is pinned to, or "" to
    // show it on every screen. Set from the launcher's Toggles folder or
    // `quickshell ipc call bar toggleSolo` (SUPER+SHIFT+B) -- both pin to
    // whichever monitor the toggle was used on. Doesn't persist across a
    // quickshell restart, same as idleActive above.
    property string barSoloScreen: ""

    // Toggling from the pinned screen unpins; toggling from any other
    // screen moves the pin there instead of just unpinning, since hitting
    // the key on a bar-less monitor almost certainly means "I want it here".
    function toggleBarSolo(screenName) {
        root.barSoloScreen = root.barSoloScreen === screenName ? "" : screenName
    }

    property IpcHandler _barIpc: IpcHandler {
        target: "bar"
        function toggleSolo() {
            const mon = Hyprland.focusedMonitor
            if (mon) root.toggleBarSolo(mon.name)
        }
        function showAll() { root.barSoloScreen = "" }
    }

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

    // Pill click and TransparencyPopup's Semi/Opaque buttons both land here.
    // The bar flips its own state immediately for a snappy icon;
    // toggle-transparency.py makes kitty agree (kitty.conf + live windows).
    function setTransparencyOpaque(opaque) {
        root.transparencyOpaque = opaque
        root._pushTransparency()
    }
    function _pushTransparency() {
        Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/toggle-transparency.py",
            root.transparencyOpaque ? "opaque" : "semi", String(BarSettings.terminalOpacity)])
    }
    // TransparencyPopup's terminal-opacity slider (semi mode's level). The
    // value lives in BarSettings, not kitty.conf: while opaque, kitty.conf
    // says 1.0, so it can't also remember the semi level to return to.
    // Pushing to kitty is debounced -- each push rewrites kitty.conf and
    // runs `kitty @` once per open window, too much to do per drag pixel.
    function setTerminalOpacity(v) {
        BarSettings.terminalOpacity = Math.round(Math.max(0.5, Math.min(0.95, v)) * 100) / 100
        if (!root.transparencyOpaque) _terminalOpacityTimer.restart()
    }
    property Timer _terminalOpacityTimer: Timer {
        interval: 200
        onTriggered: root._pushTransparency()
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

pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking

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

    // The Control Center's / toggle row's switches, kept across quickshell
    // restarts and reboots in ~/.config/quickshell/shell-state.json (they
    // used to reset to off on every hot-reload of any .qml file). Aliases
    // straight onto the JsonAdapter, same as BarSettings.terminalOpacity,
    // so every existing reader/writer keeps working unchanged. Anything that
    // has to *act* on a restored value (pushing hyprsunset, Bluetooth) waits
    // for `stateLoaded` -- before that these still hold the defaults.
    property alias idleActive: _state.idleActive
    // When a timed Stay Awake (setIdleActive with minutes) ends, as epoch
    // ms; 0 = on indefinitely (or off). Same shape as notificationsMutedUntil.
    property alias idleActiveUntil: _state.idleActiveUntil

    // Do-not-disturb: suppresses new toast popups (Notifications.qml) while
    // on. Doesn't touch NotificationHistory -- everything still lands in
    // the bell icon's drawer, it's only the on-screen popup that's
    // skipped, same "nothing lost, just not interrupting you" semantics as
    // GNOME/Windows DND. A timed mute that ran out while quickshell wasn't
    // running is cleared by _dndTimer's triggeredOnStart.
    property alias notificationsMuted: _state.notificationsMuted
    // When a timed mute (NotificationMutePopup's "30 min"/"1 h"/...) ends,
    // as epoch ms; 0 = muted indefinitely (or not muted at all).
    property alias notificationsMutedUntil: _state.notificationsMutedUntil
    // When the current mute started, as epoch ms (0 = not muted), so
    // NotificationHistory.missedCount can tell what arrived while silenced.
    // Extending a running mute keeps it -- those are still the same quiet
    // stretch from the user's point of view.
    property alias notificationsMutedSince: _state.notificationsMutedSince

    property bool stateLoaded: false
    property FileView _stateFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/shell-state.json"
        printErrors: false
        onAdapterUpdated: writeAdapter()
        onLoaded: root.stateLoaded = true
        // First run: no file yet, the defaults stand (the first change
        // writes it).
        onLoadFailed: root.stateLoaded = true

        adapter: JsonAdapter {
            id: _state
            property bool idleActive: false
            property real idleActiveUntil: 0
            property bool notificationsMuted: false
            property real notificationsMutedUntil: 0
            property real notificationsMutedSince: 0
            // Radio states from just before Airplane mode went on -- see
            // setAirplane. Default on, i.e. "nothing remembered" restores both.
            property bool airplaneWifiWas: true
            property bool airplaneBluetoothWas: true
            property bool sunsetWarm: false
            property bool sunsetScheduleFollow: true
            // The schedule phase (night = true) sunsetWarm was last set in --
            // see _restoreSunset.
            property bool sunsetPhase: false
            property bool bluetoothEnabled: true
        }
    }

    // Bluetooth on/off. BlueZ doesn't remember it: bluetoothd's AutoEnable
    // (default true, /etc/bluetooth/main.conf) powers the adapter back on at
    // every boot, so the Control Center's Bluetooth/Airplane tiles turned it
    // off only until the next login. Remembered here instead and put back
    // once the adapter shows up. Tracks the adapter itself (not just this
    // shell's toggles), so a change from bluetoothctl/blueman sticks too --
    // except during the first few seconds, when AutoEnable may still be
    // powering it on behind our back (that would read as "user turned it
    // on"); _btSettle re-asserts the saved state once that's over.
    readonly property var _btAdapter: Bluetooth.defaultAdapter
    property bool _btTracking: false
    function _restoreBluetooth() {
        if (!root.stateLoaded || !root._btAdapter) return
        root._btTracking = false
        if (root._btAdapter.enabled !== _state.bluetoothEnabled) root._btAdapter.enabled = _state.bluetoothEnabled
        root._btSettle.restart()
    }
    on_BtAdapterChanged: root._restoreBluetooth()
    onStateLoadedChanged: {
        root._restoreBluetooth()
        root._restoreSunset()
    }
    property Timer _btSettle: Timer {
        interval: 5000
        onTriggered: {
            if (!root._btAdapter) return
            if (root._btAdapter.enabled !== _state.bluetoothEnabled) root._btAdapter.enabled = _state.bluetoothEnabled
            root._btTracking = true
        }
    }
    // The Control Center's Bluetooth/Airplane tiles and the Bluetooth page's
    // switch: saved right away, so a toggle inside the settle window above
    // isn't reverted by it.
    function setBluetooth(on) {
        _state.bluetoothEnabled = on
        if (root._btAdapter) root._btAdapter.enabled = on
    }
    property Connections _btWatch: Connections {
        target: root._btAdapter
        function onEnabledChanged() {
            if (root._btTracking) _state.bluetoothEnabled = root._btAdapter.enabled
        }
    }

    // Airplane mode isn't a state of its own (the Control Center reads it as
    // "both radios off"); this only makes leaving it put back what was on
    // before, instead of forcing both radios on. Bluetooth's "was" is the
    // saved intent (_state.bluetoothEnabled), not the adapter, which may
    // still be mid-AutoEnable or absent. Turning it on while both radios are
    // already off keeps the earlier memory rather than remembering off/off,
    // which would make the next "off" restore nothing.
    function setAirplane(on) {
        if (on) {
            if (Networking.wifiEnabled || _state.bluetoothEnabled) {
                _state.airplaneWifiWas = Networking.wifiEnabled
                _state.airplaneBluetoothWas = _state.bluetoothEnabled
            }
            Networking.wifiEnabled = false
            root.setBluetooth(false)
            return
        }
        Networking.wifiEnabled = _state.airplaneWifiWas
        root.setBluetooth(_state.airplaneBluetoothWas)
        // Consumed: a later airplane-off without a fresh "on" (e.g. after
        // both radios were switched off one at a time) falls back to both on.
        _state.airplaneWifiWas = true
        _state.airplaneBluetoothWas = true
    }

    // minutes > 0 mutes until now + minutes; minutes = 0 mutes indefinitely.
    // Every unmute (pill click, popup, timer) clears the deadline too, so a
    // later plain mute doesn't inherit a stale one.
    function setNotificationsMuted(muted, minutes) {
        if (muted && !root.notificationsMuted) root.notificationsMutedSince = Date.now()
        else if (!muted) root.notificationsMutedSince = 0
        root.notificationsMutedUntil = muted && minutes > 0 ? Date.now() + minutes * 60000 : 0
        root.notificationsMuted = muted
    }
    function muteNotificationsUntil(epochMs) {
        if (!root.notificationsMuted) root.notificationsMutedSince = Date.now()
        root.notificationsMutedUntil = epochMs
        root.notificationsMuted = true
    }
    // Plain `notificationsMuted = x` writers (if any) get the same
    // bookkeeping. Not while shell-state.json is still loading: the adapter
    // fills its properties one by one, so notificationsMuted can land before
    // the saved notificationsMutedSince and this would stamp "now" over it.
    onNotificationsMutedChanged: {
        if (!root.stateLoaded) return
        if (!root.notificationsMuted) {
            root.notificationsMutedSince = 0
            root.notificationsMutedUntil = 0
        } else if (root.notificationsMutedSince === 0) root.notificationsMutedSince = Date.now()
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

    // Stay Awake, optionally timed: minutes > 0 keeps it on until now +
    // minutes, otherwise indefinitely. Same deadline handling as the mute
    // above. The toggles that just flip `idleActive` keep working: turning
    // it off by any route drops the deadline (onIdleActiveChanged), so a
    // later plain "on" doesn't inherit a stale one and switch itself off.
    function setIdleActive(on, minutes) {
        root.idleActiveUntil = on && minutes > 0 ? Date.now() + minutes * 60000 : 0
        root.idleActive = on
    }
    onIdleActiveChanged: {
        if (root.stateLoaded && !root.idleActive) root.idleActiveUntil = 0
    }
    property Timer _idleTimer: Timer {
        running: root.idleActive && root.idleActiveUntil > 0
        interval: 30000
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (Date.now() >= root.idleActiveUntil) root.setIdleActive(false, 0)
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
    // whichever monitor the toggle was used on. Deliberately doesn't persist
    // (not a Control Center setting): a pin to a monitor that's gone or
    // moved after a reboot would just hide the bar.
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

    // update.sh's retry after a deploy left quickshell on a failed reload:
    // the file watcher only reloads on a content change (touching shell.qml
    // does nothing), so a reload of identical files needs asking for.
    property IpcHandler _shellIpc: IpcHandler {
        target: "shell"
        function reload(): void { Quickshell.reload(false) }
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

    // Whether the filter is warm right now -- the single source of truth
    // for the light, not a value derived from some other mode enum.
    // Written by SunsetToggle's pill/On-Off buttons (forceSunsetWarm), a
    // schedule boundary crossing (_checkScheduleBoundary), setScheduleFollow's
    // own immediate resync when re-enabling follow, and _restoreSunset.
    // Persisted (shell-state.json), see _restoreSunset for how it comes back.
    property alias sunsetWarm: _state.sunsetWarm

    // Whether the schedule (hyprsunset.conf's day/night profile times) is
    // allowed to drive sunsetWarm at its own boundary crossings. Completely
    // independent of sunsetWarm itself -- toggling this never changes the
    // light (see setScheduleFollow), and forcing the light via the pill or
    // On/Off buttons never changes this. That independence is the whole
    // point: turn schedule off and a force stays put until the next
    // explicit force; turn it back on and the schedule resumes from
    // wherever the clock currently is, ignoring whatever was forced while
    // it was off.
    property alias sunsetScheduleFollow: _state.sunsetScheduleFollow

    // Last manually-set warmth, shown by the popup's slider regardless of
    // sunsetWarm/sunsetScheduleFollow. Seeded from hyprsunset.conf's night
    // profile at startup (see _loadSunsetKelvin) -- the file is where this
    // persists, since hyprsunset itself reads it from there.
    property int sunsetKelvin: 2500

    // watchChanges + reload: SunsetPopup (one per bar plus one per Control
    // Center) rewrites this file's profile times through its own FileView.
    // Without picking that up, this copy kept the startup text, so the next
    // warmth change (_commitKelvin, a read-modify-write of the whole file)
    // silently put the old times back, and the boundary check kept using
    // them. Same-process writes do fire fileChanged (checked in a throwaway
    // instance, atomic writes included).
    readonly property FileView _sunsetConf: FileView {
        path: Quickshell.env("HOME") + "/.config/hypr/hyprsunset.conf"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        // The kelvin is (re)read here, not only in Component.onCompleted /
        // _restoreSunset: this FileView loads asynchronously, and text() is
        // still "" at both of those points, so sunsetKelvin silently kept its
        // 2500 default while the conf said 3500 -- and _syncSunset then
        // "corrected" hyprsunset's own 3500 night switch to 2500 a few seconds
        // later (seen in hyprsunset's journal at 23:00:00 -> 23:00:03). Not
        // mid-drag, where the pending value is newer than the file.
        onLoaded: {
            root._parseSunsetTimes()
            if (root._pendingKelvin < 0) {
                const before = root.sunsetKelvin
                root._loadSunsetKelvin()
                if (root.sunsetKelvin !== before && root.stateLoaded && root.sunsetWarm) root._syncSunset()
            }
        }
    }

    // hyprsunset.conf's two profile times (day = first, night = second, same
    // reading as _computePhaseIsNight) as "HH:MM", for display; "" until the
    // conf has loaded. Refreshed on every (re)load of the conf above.
    property int _sunsetDayMin: -1
    property int _sunsetNightMin: -1
    readonly property string sunsetDayTime: root._fmtMin(root._sunsetDayMin)
    readonly property string sunsetNightTime: root._fmtMin(root._sunsetNightMin)
    function _fmtMin(m) {
        if (m < 0) return ""
        const h = Math.floor(m / 60), mm = m % 60
        return (h < 10 ? "0" : "") + h + ":" + (mm < 10 ? "0" : "") + mm
    }
    function _parseSunsetTimes() {
        const re = /time\s*=\s*(\d{1,2}):(\d{2})/g
        const mins = []
        let m
        while ((m = re.exec(root._sunsetConf.text())) !== null) mins.push((+m[1]) * 60 + (+m[2]))
        root._sunsetDayMin = mins.length > 0 ? mins[0] : -1
        root._sunsetNightMin = mins.length > 1 ? mins[1] : -1
    }
    // Epoch ms of the next day/night switch, or 0 while the times are
    // unknown. Wall-clock based (new Date at each boundary's HH:MM), so a
    // DST change day still lands on the right local time.
    function sunsetNextChange() {
        if (root._sunsetDayMin < 0 || root._sunsetNightMin < 0) return 0
        const now = new Date()
        let best = 0
        for (const mins of [root._sunsetDayMin, root._sunsetNightMin]) {
            const t = new Date(now.getFullYear(), now.getMonth(), now.getDate(), Math.floor(mins / 60), mins % 60)
            if (t.getTime() <= now.getTime()) t.setDate(t.getDate() + 1)
            if (best === 0 || t.getTime() < best) best = t.getTime()
        }
        return best
    }

    // Single spot that both writes sunsetWarm and pushes the matching
    // hyprctl command, so the pill, the boundary check, and re-enabling
    // the schedule can't drift from each other on which command means what.
    function _applyWarm(v) {
        root.sunsetWarm = v
        _state.sunsetPhase = root._computePhaseIsNight()
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
    // schedule currently says (rather than waiting for the next timer
    // tick) and hands the last force's value back to the daemon.
    function setScheduleFollow(follow) {
        if (root.sunsetScheduleFollow === follow) return
        root.sunsetScheduleFollow = follow
        if (follow) {
            const isNight = root._computePhaseIsNight()
            root._lastPhase = isNight
            root._applyWarm(isNight)
        }
    }

    // SunsetPopup's Save (new profile times). hyprsunset only reads its
    // config at startup -- no live-reload IPC -- so it's restarted (its
    // systemd --user unit; only under the uwsm session, see autostart.lua),
    // and a restarted hyprsunset applies whichever profile is current,
    // dropping any force -- so follow goes back on and the state is synced
    // to that once it's up again.
    function restartSunsetSchedule() {
        root.sunsetScheduleFollow = true
        Quickshell.execDetached(["systemctl", "--user", "restart", "hyprsunset.service"])
        root._resyncAfterRestart.restart()
    }
    property Timer _resyncAfterRestart: Timer {
        interval: 1500
        onTriggered: {
            const isNight = root._computePhaseIsNight()
            root._lastPhase = isNight
            root.sunsetWarm = isNight
            _state.sunsetPhase = isNight
            root._syncSunsetTries = 5
            root._syncSunset()
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
    // stomp a manual force back to the schedule's value on every tick
    // even with sunsetScheduleFollow true, which defeats "stays forced
    // until the next explicit force or boundary crossing".
    property bool _lastPhase: false

    // hyprsunset switches profiles by itself at each schedule time. This
    // used to push the same switch again from here when it noticed the
    // boundary (up to 30s later), which showed as the light changing twice.
    // Now a crossing only updates sunsetWarm, and _syncSunset pushes only
    // where hyprsunset's actual state disagrees -- i.e. Follow schedule is
    // off and hyprsunset just overrode a forced state, which is put back.
    function _checkScheduleBoundary() {
        const isNight = root._computePhaseIsNight()
        if (isNight === root._lastPhase) return
        root._lastPhase = isNight
        if (root.sunsetScheduleFollow) {
            root.sunsetWarm = isNight
            _state.sunsetPhase = isNight
        }
        root._syncSunset()
    }

    // Startup (once shell-state.json is in): a saved force is still current
    // only if no schedule boundary has passed since it was set (same rule as
    // a live one) -- with Follow schedule off it always is. Then hyprsunset
    // is brought in line, which is a no-op after a plain quickshell reload
    // (hyprsunset kept the light) and puts a force back after a login
    // (hyprsunset starts on the schedule's profile).
    function _restoreSunset() {
        root._loadSunsetKelvin()
        const isNight = root._computePhaseIsNight()
        root._lastPhase = isNight
        if (root.sunsetScheduleFollow && _state.sunsetPhase !== isNight) {
            root.sunsetWarm = isNight
            _state.sunsetPhase = isNight
        }
        root._syncSunsetTries = 10
        root._syncSunset()
    }

    // Reads hyprsunset's current temperature (identity reads 6000, its
    // neutral value; the warmth range tops out at 5000) and pushes only on a
    // mismatch. hyprsunset may not be up yet at login (it's a separate
    // systemd --user unit) -- hyprctl then prints an error instead of a
    // number, retried every 2s while _syncSunsetTries lasts.
    property int _syncSunsetTries: 0
    function _syncSunset() {
        if (root._sunsetQuery.running) return
        root._sunsetQuery.running = true
    }
    property Process _sunsetQuery: Process {
        command: ["hyprctl", "hyprsunset", "temperature"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = parseInt(text.trim())
                if (isNaN(t)) {
                    if (root._syncSunsetTries-- > 0) root._sunsetRetry.restart()
                    return
                }
                root._syncSunsetTries = 0
                // hyprsunset 0.4.0 keeps reporting the last temperature it
                // was set to after an `identity` (journal: last command
                // identity, query still answers 2500), so "warm" can't be
                // read from t -- only "neutral" can be trusted (6000). A
                // warm state is therefore always re-sent (re-applying the
                // same temperature is invisible); otherwise a neutral screen
                // reporting the stale kelvin would pass as matching and Night
                // Light would show On over a neutral screen. Off pushes
                // identity whenever t isn't 6000, which after any warm
                // stretch is always -- also invisible when already neutral.
                const warmNow = t < 6000
                if (root.sunsetWarm || warmNow)
                    Quickshell.execDetached(root.sunsetWarm
                        ? ["hyprctl", "hyprsunset", "temperature", String(root.sunsetKelvin)]
                        : ["hyprctl", "hyprsunset", "identity"])
            }
        }
    }
    property Timer _sunsetRetry: Timer {
        interval: 2000
        onTriggered: root._syncSunset()
    }

    // Re-checks every 10s so a schedule boundary crossing is caught (and,
    // with Follow schedule off, a force put back) without needing a click.
    property Timer _sunsetTimer: Timer {
        interval: 10000
        running: root.stateLoaded
        repeat: true
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

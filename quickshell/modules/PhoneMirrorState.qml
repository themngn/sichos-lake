pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Phone mirror (scrcpy) state shared by the bar widget (PhoneMirror.qml) on
// every screen and the per-screen PhoneMirrorPanel.qml (loading placeholder,
// controls card, collapsed edge tab). The window itself is managed by
// scripts/phone-mirror.sh; only the screen it was opened on shows the panel.
QtObject {
    id: root

    readonly property string title: "SichOS Phone"
    // Keep in sync with phone-mirror.sh's GAP.
    readonly property int gap: 6
    readonly property int controlsHeight: 60

    // Read off Hyprland's own window list rather than tracked here, so
    // closing the window any other way (SUPER+W, the phone disconnecting)
    // still resets everything. Stays true while collapsed (the window is
    // just parked off-screen).
    // (Guarded: during a reload the toplevel list is briefly unavailable,
    // which made the plain `.some(...)` evaluate to undefined.)
    readonly property bool open: {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : null
        return !!list && list.some(t => t.title === root.title)
    }
    property bool loading: false

    // Collapsed/screen live in a runtime-dir file rather than plain
    // properties so a quickshell reload (which recreates this singleton)
    // picks the still-running window back up -- otherwise a collapsed,
    // off-screen window came back with its controls showing and no tab.
    // $XDG_RUNTIME_DIR, not ~/.local/state: it should reset at logout,
    // same as the scrcpy window itself.
    readonly property bool collapsed: root._persist.collapsed
    readonly property string screenName: root._persist.screenName
    property JsonAdapter _persist: JsonAdapter {
        property bool collapsed: false
        property string screenName: ""
    }
    // Which monitor edge it docks to ("right"/"left"), switched from the
    // controls card. A preference, so unlike the above it's kept across
    // logins, next to phone-aspect.
    readonly property string side: root._sideFile.text().trim() === "left" ? "left" : "right"
    property FileView _sideFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/sichos/phone-side"
        printErrors: false
    }
    function toggleSide() {
        const next = root.side === "left" ? "right" : "left"
        root._sideFile.setText(next)
        // An expanded window slides across to the new side right away.
        if (root.open && !root.collapsed)
            Quickshell.execDetached(["bash", root._script, "expand", root.screenName, next, String(Theme.barHeight),
                                     String(root.geom.w), String(root.geom.h)])
    }
    property FileView _persistFile: FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/sichos-phone-mirror.json"
        printErrors: false
        adapter: root._persist
        onAdapterUpdated: writeAdapter()
    }

    // Phone audio on this computer -- a detached audio-only scrcpy (see
    // phone-mirror.sh's audio-* commands). Its default `--audio-source=
    // output` takes the phone's output over: the phone goes quiet while this
    // is on and plays again once it stops. The truth is the process itself,
    // polled, so it survives reloads and notices the process dying.
    property bool audio: false
    function setAudio(on) {
        root.audio = on
        root._audioPoll.restart()
        Quickshell.execDetached(["bash", root._script, on ? "audio-on" : "audio-off"])
    }
    property Process _audioStatus: Process {
        command: ["bash", root._script, "audio-status"]
        onExited: (code) => root.audio = code === 0
    }
    // restart() in setAudio delays the next poll so it doesn't race the
    // process starting up; the first check on a (re)load is onCompleted.
    Component.onCompleted: root._audioStatus.running = true
    property Timer _audioPoll: Timer {
        running: root.open
        repeat: true
        interval: 2000
        onTriggered: root._audioStatus.running = true
    }

    // Whether the phone's PIN pad is up, reported by phone-mirror.sh's wake
    // loop into a runtime file. Android hides the pad from mirroring (it
    // shows black), so PhoneMirrorPanel overlays a "type your PIN" hint.
    // Polled with reload() rather than watchChanges: FileView doesn't pick
    // up writes from other processes (see BarSettings' IpcHandler comment).
    // "3": the pad is up because the saved PIN was rejected (the script has
    // forgotten it by then). "2": locked, being unlocked -- PhoneMirrorPanel
    // covers the phone so the lock screen never shows in the mirror.
    property bool pinPad: false
    property bool pinRejected: false
    property bool unlocking: false
    property FileView _pinFile: FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/sichos-phone-pinpad"
        printErrors: false
        onLoaded: {
            const st = text().trim()
            root.pinPad = st === "1" || st === "3"
            root.pinRejected = st === "3"
            if (root.pinRejected) root.pinSaved = false
            // A "0" left over from the previous run doesn't lift the cover
            // put up by _expectLock while the new loop is still starting.
            if (st !== "0" || !root._lockGrace.running) root.unlocking = st === "2"
            if (st !== "0") root._lockGrace.stop()
        }
        onLoadFailed: root.pinPad = false
    }
    // The wake loop needs ~0.3-0.5s (adb) to report anything, while the
    // window is already sliding in -- the lock screen flashed by before the
    // cover went up. So on expand/wake the cover goes up straight away if the
    // sichlink daemon last reported the phone locked (or its screen off,
    // which on this phone means locked within seconds), until the loop's
    // first report or this grace runs out.
    property Timer _lockGrace: Timer {
        interval: 2000
        onTriggered: root._pinFile.reload()
    }
    function _expectLock() {
        const p = Sichlink.phone
        if (p && (p.locked === true || p.screen_on === false)) {
            root.unlocking = true
            root._lockGrace.restart()
        }
    }
    property Timer _pinPoll: Timer {
        running: root.open && !root.collapsed
        repeat: true
        // Tiny file, read in-process: cheap enough to poll fast, so the
        // hint tracks the phone (~0.4s rounds) without adding much lag.
        interval: 100
        onTriggered: root._pinFile.reload()
        onRunningChanged: if (!running) { root.pinPad = false; root.unlocking = false }
    }

    // PIN entry relay. Keys sent to the scrcpy window are invisible to
    // quickshell, so while the pad is up PhoneMirrorPanel's hint takes the
    // keyboard instead, counts the digits (shown as dots) and forwards each
    // key to the phone here. One long-lived `adb shell` fed over stdin: the
    // digits never show up in any process's argv, and nothing is stored or
    // logged. Each key still costs ~0.3s on the phone (`input` starts a JVM
    // per line), but stdin keeps them in order.
    property int pinLength: 0
    // The digits typed so far, kept only so "Remember on this PC" can hand
    // them to phone-mirror.sh save-pin on Enter; cleared with the pad.
    property string _typed: ""
    onPinPadChanged: if (!root.pinPad) { root.pinLength = 0; root._typed = "" }
    property Process _pinInput: Process {
        // Through the script only so it picks the same adb serial as the mirror.
        command: ["bash", root._script, "shell"]
        stdinEnabled: true
        running: root.pinPad
    }
    function _pinKey(code) {
        if (root._pinInput.running) root._pinInput.write("input keyevent " + code + "\n")
    }
    function pinDigit(d) {  // Android KEYCODE_0..9 = 7..16
        root._pinKey(7 + d)
        root.pinLength++
        root._typed += String(d)
    }
    function pinBackspace() {
        root._pinKey(67)  // KEYCODE_DEL
        root.pinLength = Math.max(0, root.pinLength - 1)
        root._typed = root._typed.slice(0, -1)
    }
    function pinEnter() {
        root._pinKey(66)  // KEYCODE_ENTER; a wrong PIN leaves the pad up, empty
        if (root.rememberPin && root._typed !== "") {
            // save-pin keeps it only if the phone actually unlocks.
            root._savePin.running = false
            root._savePin.running = true
            root._savePin.write(root._typed + "\n")
        }
        root.pinLength = 0
        root._typed = ""
    }

    // Saved PIN (phone-mirror.sh "Saved PIN"): typed by the wake loop itself,
    // so the card only shows when there is none or it was rejected.
    // rememberPin is the card's "Remember on this PC" checkbox.
    property bool pinSaved: false
    property bool rememberPin: false
    property Process _pinSavedCheck: Process {
        command: ["bash", root._script, "pin-saved"]
        running: true
        onExited: (code) => root.pinSaved = code === 0
    }
    property Process _savePin: Process {
        command: ["bash", root._script, "save-pin"]
        stdinEnabled: true
        onExited: (code) => {
            if (code === 0) root.rememberPin = false
            root._pinSavedCheck.running = true
        }
    }
    // Set from the Phone page (PhonePage.qml) without going through the
    // mirror's PIN card; stdin, never argv.
    property Process _storePin: Process {
        command: ["bash", root._script, "store-pin"]
        stdinEnabled: true
        onExited: root._pinSavedCheck.running = true
    }
    function storePin(pin) {
        root._storePin.running = false
        root._storePin.running = true
        root._storePin.write(pin + "\n")
    }
    function forgetPin() {
        root.pinSaved = false
        Quickshell.execDetached(["bash", root._script, "forget-pin"])
    }

    // Phone screen off (asleep or dozing) while the mirror is shown --
    // PhoneMirrorPanel then covers it with a "click to wake" card. One
    // long-lived adb shell reports the power state once a second, only
    // while expanded (dumpsys power is ~70ms on the phone).
    property bool screenOff: false
    // Also the display's current size, for apps that turn the phone
    // sideways (games, video): wider than tall = landscape, and the window
    // is resized to that shape with its surfaces following (geom). From the
    // display's own line in `dumpsys window displays` (`cur=2712x1220`, ~30ms).
    // Not `mDisplayRotation`: its first match is a config override that
    // stayed ROTATION_0 with a game in landscape (the live one,
    // mCurrentRotation, is hundreds of lines further down).
    property bool phoneWide: false
    property Process _powerWatch: Process {
        running: root.open && !root.collapsed
        command: ["bash", root._script, "shell", "while true; do dumpsys power | grep -o 'mWakefulness=[A-Za-z]*'; "
            + "dumpsys window displays | grep -o -m1 ' cur=[0-9]*x[0-9]*'; sleep 1; done"]
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf("mWakefulness=") === 0) root.screenOff = line !== "mWakefulness=Awake"
                else {
                    const m = /cur=(\d+)x(\d+)/.exec(line)
                    if (m) root.phoneWide = parseInt(m[1]) > parseInt(m[2])
                }
            }
        }
        onRunningChanged: if (!running) root.screenOff = false
    }
    readonly property bool landscape: root.open && root.phoneWide

    // The window's size on its screen, shared by phone-mirror.sh (passed to
    // expand/layout) and PhoneMirrorPanel's surfaces. Portrait: always the
    // full height between the bar and the controls card (what scrcpy's
    // --window-height opens it at) -- not resizable. Landscape: a share of
    // the screen's width (60% by default; the full height would make it over
    // twice the screen wide), capped to that same height; the share is what
    // the corner grip (PhoneMirrorPanel, landscape only) drags.
    // `aspect` is always the portrait width/height.
    readonly property var _screenInfo: {
        const s = Quickshell.screens.find(x => x.name === root.screenName) || Quickshell.screens[0]
        const sw = s ? s.width : 1920, sh = s ? s.height : 1080
        return { sw: sw, fullH: sh - Theme.barHeight - root.controlsHeight - root.gap * 3 }
    }
    readonly property var geom: root.geomFor(root._size.landscape)
    function geomFor(share) {
        const sw = root._screenInfo.sw, fullH = root._screenInfo.fullH
        if (!root.landscape) return { w: Math.round(fullH * root.aspect), h: fullH }
        let w = Math.round(sw * Math.max(0.3, Math.min(root._maxWide, share)))
        let h = Math.round(w * root.aspect)
        if (h > fullH) { h = fullH; w = Math.round(h / root.aspect) }
        return { w: w, h: h }
    }
    // The share for a given window width (the grip reports widths), clamped
    // the way geomFor clamps it.
    function shareForWidth(w) {
        return Math.max(0.3, Math.min(root.maxShare(), w / root._screenInfo.sw))
    }
    // Landscape can go edge to edge: the screen's width minus a gap each side.
    readonly property real _maxWide: (root._screenInfo.sw - 2 * root.gap) / root._screenInfo.sw
    // Largest landscape share (also stops at the height under the bar).
    function maxShare() {
        return Math.min(root._maxWide, root._screenInfo.fullH / root.aspect / root._screenInfo.sw)
    }
    // Double-click on the grip: largest size, or back to the size before.
    function toggleMax() {
        if (!root.landscape) return
        const cur = root._size.landscape
        const max = root.maxShare()
        if (cur >= max - 0.001) {
            root.setShare(root._size.landscapeBefore)
        } else {
            root._size.landscapeBefore = cur
            root.setShare(max)
        }
        root._sizeFile.writeAdapter()
    }
    function setShare(share) {
        if (root.landscape) root._size.landscape = share
    }
    property JsonAdapter _size: JsonAdapter {
        property real landscape: 0.6
        // What toggleMax() returns to.
        property real landscapeBefore: 0.6
    }
    property FileView _sizeFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/sichos/phone-size.json"
        printErrors: false
        adapter: root._size
    }
    // True while the grip is held: the window follows at ~25fps without the
    // slide animation, and the size is saved on release.
    property bool resizing: false
    onResizingChanged: {
        if (root.resizing) return
        root._layoutTick.stop()
        root._sizeFile.writeAdapter()
        root._layout()
    }
    property Timer _layoutTick: Timer {
        interval: 40
        onTriggered: root._layout(true)
    }
    // Re-docked at the new size as soon as the phone turns; a hidden mirror
    // gets it on expand.
    onGeomChanged: {
        if (!root.open || root.collapsed || root.loading) return
        if (root.resizing) { if (!root._layoutTick.running) root._layoutTick.start() }
        else root._layout()
    }
    function _layout(fast) {
        Quickshell.execDetached(["bash", root._script, "layout", root.screenName, root.side, String(Theme.barHeight),
                                 String(root.geom.w), String(root.geom.h)].concat(fast ? ["fast"] : []))
    }
    // Same wake as on expand: also brings up the PIN pad if it's locked.
    function wake() {
        root.screenOff = false  // hide the card right away; the next report confirms
        root._expectLock()
        Quickshell.execDetached(["bash", root._script, "wake"])
    }

    onOpenChanged: {
        if (root.open) {
            // Only for a mirror this session just started (not the window
            // reappearing to a reloaded quickshell): phone-mirror.sh opens
            // it off-screen, and expanding now slides it in together with
            // the controls card, which starts its slide on this same change.
            if (root.loading) root.expand()
            root.loading = false
            root._aspectProbe.running = true
        } else {
            // Not reached on a reload: `open` starts false and only ever
            // rises then, so persisted state survives.
            root._persist.collapsed = false
            if (root.audio) root.setAudio(false)
            root.phoneWide = false
        }
    }

    readonly property string _script: Quickshell.env("HOME") + "/.config/quickshell/scripts/phone-mirror.sh"

    // What toggle() does next, for buttons (Control Center tile and page).
    readonly property string toggleLabel: root.loading ? "Connecting…"
        : !root.open ? "Mirror" : root.collapsed ? "Show" : "Hide"

    // Bar icon: open, or show/hide (collapse/expand) once open. Closing is
    // only ever the controls card's close button -- reconnecting scrcpy is
    // the slow part, so the bar never throws a session away.
    function toggle(screenName) {
        if (root.loading) return
        if (!root.open) root._start(screenName)
        else if (root.collapsed) root.expand()
        else root.collapse()
    }
    // SUPER+X (keybindings.lua): same as the bar icon; opens on the focused
    // monitor when there's no mirror yet.
    property IpcHandler _ipc: IpcHandler {
        target: "phone"
        function toggle(): void {
            const mon = Hyprland.focusedMonitor
            root.toggle(mon ? mon.name : root.screenName)
        }
        // SUPER+SHIFT+X: disconnect, same as the controls card's close.
        function close(): void { root.close() }
    }
    // Explicit actions for the Phone page's buttons (toggle() is the
    // bar/keybinding one-button version).
    function start(screenName) { if (!root.open && !root.loading) root._start(screenName) }
    // Launcher's phone folder: bring the mirror up (start it, or show it
    // if hidden) and open that app on the phone. Started in parallel with
    // the mirror -- on a locked phone the app waits behind the keyguard
    // until the mirror's wake loop unlocks it.
    function launchApp(pkg, screenName) {
        if (!root.open) root.start(screenName)
        else if (root.collapsed) root.expand()
        Quickshell.execDetached(["bash", root._script, "launch", pkg])
    }
    function _start(screenName) {
        root._persist.screenName = screenName
        root._persist.collapsed = false
        root.loading = true
        root._loadingTimeout.restart()
        root._startProc.command = ["bash", root._script, "open", screenName,
                                   String(Theme.barHeight), String(root.controlsHeight), root.side]
        root._startProc.running = true
    }
    function close() {
        Quickshell.execDetached(["bash", root._script, "close"])
    }
    function collapse() {
        root._persist.collapsed = true
        Quickshell.execDetached(["bash", root._script, "collapse", root.side])
    }
    function expand() {
        root._persist.collapsed = false
        root._expectLock()
        Quickshell.execDetached(["bash", root._script, "expand", root.screenName, root.side, String(Theme.barHeight),
                                 String(root.geom.w), String(root.geom.h)])
    }
    // Android KeyEvent codes: 4 back, 3 home, 187 recents, 24/25 volume up/down, 26 power.
    // Held volume buttons: one adb shell looping keyevents on the phone until
    // released -- a process per step would add a full adb round trip each
    // time. Stopping it kills the local adb client, which ends the loop on
    // the phone too (same as the wake loop in phone-mirror.sh). Each
    // `input keyevent` takes ~0.3s there, so this repeats ~3x a second.
    property Process _keyRepeat: Process {}
    function startKeyRepeat(code) {
        root._keyRepeat.running = false
        root._keyRepeat.command = ["bash", root._script, "shell", "while true; do input keyevent " + code + "; done"]
        root._keyRepeat.running = true
    }
    function stopKeyRepeat() {
        root._keyRepeat.running = false
    }

    // longPress: `input keyevent --longpress` (power: the phone's power menu).
    function key(code, longPress) {
        Quickshell.execDetached(["bash", root._script, "key"].concat(longPress ? ["--longpress"] : []).concat([String(code)]))
    }

    property Process _startProc: Process {
        // Non-zero = nothing was launched (no adb device; the script already
        // sent a notification), so there's no window to wait for.
        onExited: (code) => { if (code !== 0) root.loading = false }
    }

    // scrcpy can also fail after launching (device unauthorized, adb
    // dropping) with nothing reported back -- don't spin forever.
    property Timer _loadingTimeout: Timer {
        interval: 15000
        onTriggered: root.loading = false
    }

    // The placeholder and controls card need the phone's width/height ratio
    // before scrcpy has reported anything, so the last seen window's ratio
    // is remembered.
    property FileView _aspectFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/sichos/phone-aspect"
        printErrors: false
    }
    readonly property real aspect: {
        const v = parseFloat(root._aspectFile.text())
        return v > 0.2 && v < 5 ? v : 0.45
    }
    property Process _aspectProbe: Process {
        command: ["sh", "-c", "hyprctl clients -j | jq -r '[.[] | select(.title == \"SichOS Phone\")][0] | .size[0] / .size[1]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Stored as the portrait ratio even if the phone is sideways now.
                let v = parseFloat(text)
                if (v > 1) v = 1 / v
                if (v > 0.2 && v <= 1) root._aspectFile.setText(String(v))
            }
        }
    }
}

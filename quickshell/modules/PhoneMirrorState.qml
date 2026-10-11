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
            Quickshell.execDetached(["bash", root._script, "expand", root.screenName, next, String(Theme.barHeight)])
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
    property bool pinPad: false
    property FileView _pinFile: FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/sichos-phone-pinpad"
        printErrors: false
        onLoaded: root.pinPad = text().trim() === "1"
        onLoadFailed: root.pinPad = false
    }
    property Timer _pinPoll: Timer {
        running: root.open && !root.collapsed
        repeat: true
        // Tiny file, read in-process: cheap enough to poll fast, so the
        // hint tracks the phone (~0.4s rounds) without adding much lag.
        interval: 100
        onTriggered: root._pinFile.reload()
        onRunningChanged: if (!running) root.pinPad = false
    }

    // PIN entry relay. Keys sent to the scrcpy window are invisible to
    // quickshell, so while the pad is up PhoneMirrorPanel's hint takes the
    // keyboard instead, counts the digits (shown as dots) and forwards each
    // key to the phone here. One long-lived `adb shell` fed over stdin: the
    // digits never show up in any process's argv, and nothing is stored or
    // logged. Each key still costs ~0.3s on the phone (`input` starts a JVM
    // per line), but stdin keeps them in order.
    property int pinLength: 0
    onPinPadChanged: if (!root.pinPad) root.pinLength = 0
    property Process _pinInput: Process {
        command: ["adb", "shell"]
        stdinEnabled: true
        running: root.pinPad
    }
    function _pinKey(code) {
        if (root._pinInput.running) root._pinInput.write("input keyevent " + code + "\n")
    }
    function pinDigit(d) {  // Android KEYCODE_0..9 = 7..16
        root._pinKey(7 + d)
        root.pinLength++
    }
    function pinBackspace() {
        root._pinKey(67)  // KEYCODE_DEL
        root.pinLength = Math.max(0, root.pinLength - 1)
    }
    function pinEnter() {
        root._pinKey(66)  // KEYCODE_ENTER; a wrong PIN leaves the pad up, empty
        root.pinLength = 0
    }

    // Phone screen off (asleep or dozing) while the mirror is shown --
    // PhoneMirrorPanel then covers it with a "click to wake" card. One
    // long-lived adb shell reports the power state once a second, only
    // while expanded (dumpsys power is ~70ms on the phone).
    property bool screenOff: false
    property Process _powerWatch: Process {
        running: root.open && !root.collapsed
        command: ["adb", "shell", "while true; do dumpsys power | grep -o 'mWakefulness=[A-Za-z]*'; sleep 1; done"]
        stdout: SplitParser {
            onRead: (line) => root.screenOff = line.indexOf("mWakefulness=") === 0 && line !== "mWakefulness=Awake"
        }
        onRunningChanged: if (!running) root.screenOff = false
    }
    // Same wake as on expand: also brings up the PIN pad if it's locked.
    function wake() {
        root.screenOff = false  // hide the card right away; the next report confirms
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
        }
    }

    readonly property string _script: Quickshell.env("HOME") + "/.config/quickshell/scripts/phone-mirror.sh"

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
        Quickshell.execDetached(["bash", root._script, "expand", root.screenName, root.side, String(Theme.barHeight)])
    }
    // Android KeyEvent codes: 4 back, 3 home, 187 recents.
    function key(code) {
        Quickshell.execDetached(["bash", root._script, "key", String(code)])
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
                const v = parseFloat(text)
                if (v > 0.2 && v < 5) root._aspectFile.setText(String(v))
            }
        }
    }
}

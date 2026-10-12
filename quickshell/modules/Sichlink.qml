pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// State of the sichlink phone-link daemon (~/Work/sichlink: `sichlink daemon`,
// a systemd --user unit) for the Control Center's Phone tile and its
// "qs-phone" page (PhonePage.qml). `sichlink watch` streams the daemon's
// status as one JSON line per change, so nothing is polled while the daemon
// runs; when it isn't running (or isn't installed) the watch exits and is
// retried -- every 3s while the Control Center is open, every 30s otherwise.
QtObject {
    id: root

    // quickshell's PATH (inherited from Hyprland) has no ~/.local/bin, where
    // the daemon is installed for now -- every call goes through this.
    function cmd(args) {
        return ["sh", "-c", 'PATH="$HOME/.local/bin:$PATH"; command -v sichlink >/dev/null || exit 127; exec sichlink "$@"', "sichlink"].concat(args)
    }

    property bool installed: true
    property bool running: false
    // Optimistic state while systemctl starts/stops the unit.
    property bool busy: false
    property var status: ({ id: "", name: "", devices: [] })
    readonly property var devices: root.running ? (root.status.devices || []) : []
    // The paired phone everything summarizes: a connected one first.
    readonly property var phone: root.devices.find(d => d.trusted && d.connected)
        || root.devices.find(d => d.trusted) || null
    // Everything else the daemon sees: phones to pair, other paired ones.
    readonly property var others: root.devices.filter(d => d !== root.phone)

    // One line on how far a phone is from being mirrorable.
    function adbText(d) {
        if (!d.connected) return "Offline"
        if (!d.trusted) return "Not paired"
        if (d.adb_serial) return "Ready to mirror"
        if (d.adb_wifi === false) return d.can_toggle ? "Turning on wireless debugging…" : "Wireless debugging off"
        if (d.adb === "unauthorized") return "Allow this PC's adb key on the phone"
        if (d.adb === "failed") return "adb couldn't connect"
        return "Connecting adb…"
    }
    // Screen/lock state, "" until the phone has reported one.
    function lockText(d) {
        if (!d || d.screen_on === null || d.screen_on === undefined) return ""
        if (!d.locked) return d.screen_on ? "Unlocked" : "Screen off"
        return d.needs_pin ? "Locked" : "Locked, no PIN needed"
    }
    // The daemon's state as a short tile/status line (the phone's own state
    // when there is one).
    readonly property string stateText: !root.installed ? "Phone Link not installed"
        : root.busy ? (root._wantOn ? "Starting…" : "Stopping…")
        : !root.running ? "Phone Link off"
        : !root.phone ? (root.devices.length > 0 ? "Not paired" : "Searching…")
        : !root.phone.connected ? "Offline"
        : root.phone.adb_serial ? "Ready to mirror"
        : root.adbText(root.phone)

    property bool _wantOn: false
    function setEnabled(on) {
        root._wantOn = on
        root.busy = true
        Quickshell.execDetached(["systemctl", "--user", on ? "enable" : "disable", "--now", "sichlink"])
        root._busyTimeout.restart()
        root._retry.interval = 500
        if (!root._watch.running) root._retry.restart()
    }
    function unpair(id) { Quickshell.execDetached(root.cmd(["unpair", id])) }
    // Screen on + dismiss the lock screen: straight in while Extend Unlock
    // trusts this PC, otherwise the phone shows its PIN pad.
    function wake(id) { Quickshell.execDetached(root.cmd(["wake", id])) }
    // `sichlink connect`: connect now (phone, wireless debugging, adb) rather
    // than on the daemon's next 10-15s round. The result shows up through
    // the watch stream; connectingId only drives the button's label.
    property string connectingId: ""
    property Process _connectProc: Process {
        onExited: root.connectingId = ""
    }
    function connect(id) {
        if (root._connectProc.running) return
        root.connectingId = id
        root._connectProc.command = root.cmd(["connect", id])
        root._connectProc.running = true
    }

    // --- Pairing: `sichlink pair` prints the code, then waits (up to 60s)
    // for the answer on the phone. ---
    property string pairingId: ""
    property string pairCode: ""
    property string pairError: ""
    function pair(id) {
        root.pairingId = id
        root.pairCode = ""
        root.pairError = ""
        root._pairProc.command = root.cmd(["pair", id])
        root._pairProc.running = true
    }
    property Process _pairProc: Process {
        stdout: SplitParser {
            onRead: (line) => {
                const m = line.match(/^\s+(\d{6})\s*$/)
                if (m) root.pairCode = m[1]
            }
        }
        stderr: SplitParser {
            onRead: (line) => root.pairError = line.replace(/^Error:\s*/, "")
        }
        onExited: (code) => {
            if (code === 0) root.pairError = ""
            else if (!root.pairError) root.pairError = "Pairing failed"
            root.pairCode = ""
            root.pairingId = code === 0 ? "" : root.pairingId
        }
    }

    // --- Status stream ---
    // "mirror": the phone asked for the mirror (the app's Mirror button or
    // Quick Settings tile) -- open it on the focused monitor, or show it if
    // it's collapsed. Never closes it: a second tap shouldn't take it away.
    function _event(ev) {
        if (ev.event === "mirror") {
            if (!PhoneMirrorState.open || PhoneMirrorState.collapsed) {
                const mon = Hyprland.focusedMonitor
                PhoneMirrorState.toggle(mon ? mon.name : PhoneMirrorState.screenName)
            }
        }
    }

    property Process _watch: Process {
        command: root.cmd(["watch"])
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                let msg
                try {
                    msg = JSON.parse(line)
                } catch (e) {
                    return
                }
                // One-off events share the stream with the status objects.
                if (msg.event !== undefined) {
                    root._event(msg)
                    return
                }
                root.status = msg
                root.installed = true
                root.running = true
                if (root._wantOn) root.busy = false
            }
        }
        onExited: (code) => {
            root.installed = code !== 127
            root.running = false
            // While starting, the first retries can beat the daemon's socket.
            if (!root._wantOn || code === 127) root.busy = false
            root._retry.restart()
        }
    }
    readonly property bool _ccOpen: ShellState.activePopup === "quicksettings" || ShellState.activePopup === "qs-phone"
    on_CcOpenChanged: if (root._ccOpen && !root.running) { root._retry.interval = 100; root._retry.restart() }
    property Timer _retry: Timer {
        interval: 3000
        onTriggered: {
            root._retry.interval = root._ccOpen || root.busy ? 1000 * (root.busy ? 1 : 3) : 30000
            if (!root._watch.running) root._watch.running = true
        }
    }
    // A unit that fails to start never produces a status line or a new exit.
    property Timer _busyTimeout: Timer {
        interval: 8000
        onTriggered: root.busy = false
    }
}

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

    // Whether the mirror can reach the phone over Wi-Fi. The daemon only
    // connects wireless adb on demand (the mirror's `sichlink connect`, and
    // turns wireless debugging on for it if the app may), so "idle" -- paired,
    // nothing connected -- counts.
    function canMirror(d) {
        if (!d || !d.connected || !d.trusted) return false
        if (d.adb_serial) return true
        return d.adb !== "unauthorized" && (d.adb_wifi === true || !!d.can_toggle)
    }
    // One line on how far a phone is from being mirrorable.
    function adbText(d) {
        if (!d.connected) return "Offline"
        if (!d.trusted) return "Not paired"
        if (d.adb_serial) return "Ready to mirror"
        if (d.adb === "idle") return root.canMirror(d) ? "Ready to mirror" : "Wireless debugging off"
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
    // Battery as "94%" / "94% · Charging" / "Full", "" until the phone has
    // reported one (an app older than the battery message never does).
    function batteryText(d) {
        if (!d || d.battery === null || d.battery === undefined) return ""
        if (d.battery_full && d.plugged) return "Full"
        return d.battery + "%" + (d.charging ? " · Charging" : "")
    }
    // nf-md-battery(_10.._90) by level; charging gets the bolt variant.
    function batteryGlyph(d) {
        if (!d || d.battery === null || d.battery === undefined) return ""
        if (d.charging || (d.battery_full && d.plugged)) return "\u{f0084}" // battery_charging
        const steps = ["\u{f008e}", "\u{f007a}", "\u{f007b}", "\u{f007c}", "\u{f007d}", "\u{f007e}",
            "\u{f007f}", "\u{f0080}", "\u{f0081}", "\u{f0082}", "\u{f0079}"]
        return steps[Math.max(0, Math.min(10, Math.round(d.battery / 10)))]
    }
    // Wallpaper the phone sent, as a URL that changes with every new image
    // (same file path each time), "" for none.
    function wallpaperUrl(d) {
        return d && d.wallpaper ? "file://" + d.wallpaper + "?" + d.wallpaper_rev : ""
    }
    // The daemon's state as a short tile/status line (the phone's own state
    // when there is one).
    readonly property string stateText: !root.installed ? "Phone Link not installed"
        : root.busy ? (root._wantOn ? "Starting…" : "Stopping…")
        : !root.running ? "Phone Link off"
        : !root.phone ? (root.devices.length > 0 ? "Not paired" : "Searching…")
        : !root.phone.connected ? "Offline"
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
    // --- Display mode: the phone as an extra monitor (`sichlink display`,
    // a Hyprland headless output streamed to the app). `display on` only
    // returns once the phone shows it -- up to a minute while the phone
    // waits to be unlocked (it never opens over the lock screen) -- so
    // displayStarting covers that wait; the on state itself comes from the
    // watch stream, which also sees it end when the phone leaves it. ---
    readonly property bool displayOn: !!root.phone && !!root.phone.display
    property bool displayStarting: false
    property string displayError: ""
    property Process _displayProc: Process {
        stderr: SplitParser {
            onRead: (line) => root.displayError = line.replace(/^Error:\s*/, "")
        }
        onExited: (code) => {
            root.displayStarting = false
            if (code !== 0 && !root.displayError) root.displayError = "Display mode failed"
        }
    }
    function setDisplay(on) {
        root.displayError = ""
        if (on) {
            if (root._displayProc.running) return
            root.displayStarting = true
            root._displayProc.command = root.cmd(["display", "on", root.phone ? root.phone.id : ""])
            root._displayProc.running = true
        } else {
            // Also ends a start still waiting for the phone: the daemon
            // cancels it and the pending `display on` returns.
            Quickshell.execDetached(root.cmd(["display", "off"]))
        }
    }

    // --- Drive: the phone's storage as a folder (`sichlink mount`: sshfs over
    // sichlink's own TLS connection -- no adb, works with the phone locked).
    // `mount` returns once it's mounted (a few seconds), `unmount` once it's
    // gone; the state itself comes from the watch stream: `mount` = the folder
    // while one is set up (the daemon remounts it whenever the phone is back),
    // `mounted` = there right now. ---
    readonly property string drivePath: root.phone && root.phone.mount ? root.phone.mount : ""
    readonly property bool driveMounted: !!root.phone && !!root.phone.mounted
    property bool driveBusy: false
    property string driveError: ""
    property Process _driveProc: Process {
        stderr: SplitParser {
            onRead: (line) => root.driveError = line.replace(/^Error:\s*/, "")
        }
        onExited: (code) => {
            root.driveBusy = false
            if (code !== 0 && !root.driveError) root.driveError = "Mounting failed"
        }
    }
    function setDrive(on) {
        if (root._driveProc.running || !root.phone) return
        root.driveError = ""
        root.driveBusy = true
        root._driveProc.command = root.cmd([on ? "mount" : "unmount", root.phone.id])
        root._driveProc.running = true
    }
    // SichOS's file manager (hypr/programs.lua), not xdg-open: the
    // inode/directory default can be anything -- here VS Code had claimed it.
    function openDrive() {
        if (root.driveMounted) Quickshell.execDetached(["nautilus", "--new-window", root.drivePath])
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

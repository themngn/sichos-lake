pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Wi-Fi hotspot for the Control Center's Hotspot tile and its page
// (HotspotPage.qml, "qs-hotspot"); the work is in
// scripts/hotspot.py (see its header for shared vs. standalone). Polled only
// while the Control Center is open -- NetworkManager keeps the hotspot
// running either way.
QtObject {
    id: root

    readonly property string _script: Quickshell.env("HOME") + "/.config/quickshell/scripts/hotspot.py"
    readonly property bool watching: ShellState.activePopup === "quicksettings" || ShellState.activePopup === "qs-hotspot"
    onWatchingChanged: if (root.watching) root.refresh()

    // From `hotspot.py status`.
    property bool active: false
    property bool starting: false
    property string mode: ""          // "shared" / "standalone" while active
    property string ssid: ""
    property string password: ""
    property int clients: 0
    property bool wifiConnected: false
    property string wifiName: ""
    property bool canShare: false
    property string shareProblem: ""

    // An on/off call in flight, and the last one's failure.
    property string pending: ""       // "on" / "off" / "prepare" / ""
    property string error: ""
    readonly property bool busy: root.pending === "on" || root.pending === "off" || root.starting

    // A tap that would cost the Wi-Fi connection (sharing isn't possible
    // here) only arms the tile; a second tap within a few seconds starts
    // the standalone hotspot. The tile says what the second tap does.
    property bool armed: false
    property Timer _disarm: Timer { interval: 4000; onTriggered: root.armed = false }

    function toggle() {
        if (root.pending !== "") return
        if (root.active || root.starting) { root.stop(); return }
        if (root.canShare) { root.start("shared"); return }
        // No Wi-Fi to lose: straight on.
        if (!root.wifiConnected || root.armed) { root.start("standalone"); return }
        root.armed = true
        root._disarm.restart()
    }
    function start(mode) {
        root.armed = false
        root.error = ""
        root.pending = "on"
        root._run(["on", mode])
    }
    function stop() {
        root.error = ""
        root.pending = "off"
        root._run(["off"])
    }
    // Through wl-copy's stdin, not its argv (visible in the process list).
    function copyPassword() {
        if (!root.password) return
        root._copy.stdinEnabled = true
        root._copy.running = true
    }
    property Process _copy: Process {
        command: ["wl-copy"]
        stdinEnabled: true
        onStarted: { root._copy.write(root.password); root._copy.stdinEnabled = false }
    }

    // Creates the profile, so the page has a name and password (and a QR
    // code) to show before the hotspot has ever run.
    function prepare() {
        if (root.ssid !== "" || root.pending !== "") return
        root.pending = "prepare"
        root._run(["prepare"])
    }

    // The "join this network" QR code, as a PNG under $XDG_RUNTIME_DIR
    // (tmpfs, gone at logout -- it holds the password). `qrRev` changes the
    // Image's URL so a regenerated file is reloaded, not taken from cache.
    readonly property string qrPath: Quickshell.env("XDG_RUNTIME_DIR") + "/sichos-hotspot-qr.png"
    property int qrRev: 0
    property string qrError: ""
    readonly property bool qrBusy: root._qr.running
    function makeQr() {
        root.qrError = ""
        root._qr.running = true
    }
    property Process _qr: Process {
        command: [Quickshell.env("HOME") + "/.config/quickshell/scripts/wifi-share.py", "qr", root.ssid, root.qrPath]
        stderr: StdioCollector { id: qrErr }
        onExited: (code) => {
            if (code === 0) root.qrRev++
            else root.qrError = qrErr.text.trim().split("\n").pop() || "Couldn't make the QR code"
        }
    }
    // Same network, new settings: drop a stale code.
    onSsidChanged: root.qrRev = 0
    onPasswordChanged: root.qrRev = 0

    function refresh() { if (!root._status.running) root._status.running = true }
    property Timer _poll: Timer {
        interval: 2000
        repeat: true
        running: root.watching || root.pending !== ""
        onTriggered: root.refresh()
    }
    property Process _status: Process {
        command: [root._script, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let s
                try { s = JSON.parse(this.text) } catch (e) { return }
                root.active = s.active
                root.starting = s.starting
                root.mode = s.mode
                root.ssid = s.ssid
                root.password = s.password
                root.clients = s.clients
                root.wifiConnected = s.wifiConnected
                root.wifiName = s.wifiName
                root.canShare = s.canShare
                root.shareProblem = s.shareProblem
            }
        }
    }
    property Process _action: Process {
        stderr: StdioCollector { id: actionErr }
        onExited: (code) => {
            if (code !== 0) root.error = actionErr.text.trim().split("\n").pop() || "Failed"
            root.pending = ""
            root.refresh()
        }
    }
    function _run(args) {
        root._action.command = [root._script].concat(args)
        root._action.running = true
    }
}

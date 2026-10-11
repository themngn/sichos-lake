pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Proton VPN state for the Control Center's VPN tile. The Proton VPN app
// (Flatpak com.protonvpn.www) has no CLI to connect with, but every
// connection it makes is an ordinary NetworkManager connection (WireGuard or
// OpenVPN, named "ProtonVPN <server>"), so state is read from -- and
// disconnecting done through -- nmcli; connecting opens the app, which
// (re)connects to the last/quick-connect server. Polled only while the
// Control Center's main page is open.
QtObject {
    id: root

    readonly property bool active: ShellState.activePopup === "quicksettings"
    property string connection: "" // active Proton connection's name, "" = off
    property bool busy: false
    readonly property bool connected: root.connection !== ""
    // "ProtonVPN JP#12" -> "JP#12"
    readonly property string server: root.connection.replace(/^ProtonVPN\s*/i, "")

    function toggle() {
        if (root.connected) {
            root.busy = true
            Quickshell.execDetached(["nmcli", "connection", "down", "id", root.connection])
        } else {
            root.openApp()
        }
        root._poll.restart()
    }
    function openApp() {
        Quickshell.execDetached(["flatpak", "run", "com.protonvpn.www"])
    }

    property Process _proc: Process {
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"]
        stdout: StdioCollector {
            onStreamFinished: {
                let found = ""
                for (const line of text.split("\n")) {
                    const name = line.split(":")[0]
                    if (/^proton/i.test(name)) { found = name.replace(/\\:/g, ":"); break }
                }
                root.connection = found
                root.busy = false
            }
        }
    }
    property Timer _poll: Timer {
        interval: 3000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: if (!root._proc.running) root._proc.running = true
    }
}

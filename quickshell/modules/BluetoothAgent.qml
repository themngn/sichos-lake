pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Runs scripts/bt-agent.py, the BlueZ pairing agent (see its header for why
// one is needed at all), and holds whatever it's currently asking: the
// Bluetooth menu shows `request` as a prompt and answers through answer().
// `display` is a code to type on the other device (no answer expected).
QtObject {
    id: root

    // {id, type: confirm|authorize|pin|passkey, device, name, passkey}
    property var request: null
    // {type: display-pin|display-passkey, device, name, passkey}
    property var display: null
    // Typed so far for a pin/passkey request (entered via ShellState.keySink).
    property string typed: ""

    function answer(value) {
        if (!root.request) return
        if (root._proc.running) root._proc.write(root.request.id + " " + value + "\n")
        root.request = null
        root.typed = ""
    }

    // Any device pairing finishes (or fails) without the agent saying so;
    // the menu clears a stale display code itself through this.
    function clearDisplay() { root.display = null }

    property Process _proc: Process {
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/bt-agent.py"]
        running: true
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (line) => {
                let m
                try { m = JSON.parse(line) } catch (e) { return }
                if (m.type === "cancel") {
                    root.request = null
                    root.display = null
                    root.typed = ""
                } else if (m.type === "display-pin" || m.type === "display-passkey") {
                    root.display = m
                } else if (m.type !== "ready") {
                    root.typed = ""
                    root.request = m
                }
            }
        }
        // bluetoothd restarting drops the agent registration with it; come
        // back after a moment rather than silently losing pairing.
        onExited: root._restart.start()
    }
    property Timer _restart: Timer {
        interval: 5000
        onTriggered: root._proc.running = true
    }
}
